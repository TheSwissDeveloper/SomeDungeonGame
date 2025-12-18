--[[
    GameLoop.lua
    Zentrale Game-Loop für "Dungeon Tycoon"
    Pfad: ServerScriptService/Server/Core/GameLoop
    
    Verantwortlich für:
    - Passive Income Verteilung
    - Cooldown-Management
    - Periodische Server-Tasks
    - Zeitbasierte Events
    
    WICHTIG: Nur vom Server verwenden!
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Auf Shared-Module warten
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")
local RemotesPath = SharedPath:WaitForChild("Remotes")

-- Module laden
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Manager-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil

local GameLoop = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Tick-Intervalle (Sekunden)
    MainTickInterval = 1.0,             -- Haupt-Loop
    PassiveIncomeInterval = GameConfig.Timing.PassiveIncomeInterval,  -- 60 Sekunden
    CooldownCheckInterval = 5.0,        -- Cooldown-Prüfung
    StatsUpdateInterval = 30.0,         -- Stats an Client senden
    
    -- Daily Reset Zeit (UTC Stunde)
    DailyResetHour = 0,                 -- Mitternacht UTC
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- INTERNER STATE
-------------------------------------------------
local isRunning = false
local isPaused = false
local lastTickTime = 0
local tickCount = 0

-- Timer-Tracking
local timers = {
    PassiveIncome = 0,
    CooldownCheck = 0,
    StatsUpdate = 0,
    DailyReset = 0,
}

-- Letzte Daily Reset Prüfung
local lastDailyResetDay = -1

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
GameLoop.Signals = {
    Tick = SignalUtil.new(),                    -- (deltaTime, tickCount)
    PassiveIncomeDistributed = SignalUtil.new(),-- (player, amount)
    DailyReset = SignalUtil.new(),              -- ()
    CooldownExpired = SignalUtil.new(),         -- (player, cooldownType)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[GameLoop]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[GameLoop]", ...)
end

--[[
    Berechnet und verteilt passives Einkommen an einen Spieler
    @param player: Der Spieler
]]
local function distributePassiveIncome(player)
    if not DataManager then return end
    
    local data = DataManager.GetData(player)
    if not data then return end
    
    local dungeonLevel = data.Dungeon.Level or 1
    local prestigeLevel = data.Prestige.Level or 0
    
    -- Einkommen berechnen (pro Minute, aber wir ticken alle 60 Sekunden)
    local income = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
    
    if income <= 0 then return end
    
    -- Gold hinzufügen (mit Cap-Check)
    local currentGold = data.Currency.Gold or 0
    local addable = CurrencyUtil.CalculateAddable(currentGold, income, "Gold")
    
    if addable > 0 then
        DataManager.IncrementValue(player, "Currency.Gold", addable)
        DataManager.IncrementValue(player, "Stats.TotalGoldEarned", addable)
        
        -- Client updaten
        RemoteIndex.FireClient("Currency_Update", player, {
            Gold = currentGold + addable,
            Gems = data.Currency.Gems,
            Source = "PassiveIncome",
            Amount = addable,
        })
        
        -- Signal feuern
        GameLoop.Signals.PassiveIncomeDistributed:Fire(player, addable)
        
        debugPrint("Passives Einkommen für " .. player.Name .. ": +" .. addable .. " Gold")
    end
end

--[[
    Verteilt passives Einkommen an alle Spieler
]]
local function distributePassiveIncomeToAll()
    for _, player in ipairs(Players:GetPlayers()) do
        if PlayerManager and PlayerManager.IsPlayerReady(player) then
            task.spawn(function()
                distributePassiveIncome(player)
            end)
        end
    end
end

--[[
    Prüft Cooldowns für einen Spieler
    @param player: Der Spieler
]]
local function checkPlayerCooldowns(player)
    if not DataManager then return end
    
    local data = DataManager.GetData(player)
    if not data then return end
    
    local currentTime = os.time()
    local cooldowns = data.Cooldowns or {}
    
    -- Raid-Cooldown prüfen
    local lastRaidTime = cooldowns.LastRaidTime or 0
    local raidCooldown = GameConfig.Raids.RaidCooldown
    
    -- Debug-Modus: Instant Cooldowns
    if GameConfig.Debug.InstantCooldowns then
        raidCooldown = 0
    end
    
    local raidCooldownRemaining = math.max(0, (lastRaidTime + raidCooldown) - currentTime)
    
    -- Wenn Cooldown gerade abgelaufen ist, Signal feuern
    if lastRaidTime > 0 and raidCooldownRemaining == 0 then
        -- Prüfen ob wir das Signal bereits gefeuert haben
        local session = PlayerManager and PlayerManager.GetSession(player)
        if session and not session.RaidCooldownNotified then
            session.RaidCooldownNotified = true
            GameLoop.Signals.CooldownExpired:Fire(player, "Raid")
            
            -- Client benachrichtigen
            if PlayerManager then
                PlayerManager.SendNotification(
                    player,
                    "Raid bereit!",
                    "Du kannst wieder andere Dungeons angreifen.",
                    "Info"
                )
            end
        end
    elseif raidCooldownRemaining > 0 then
        -- Cooldown läuft noch, Reset-Flag zurücksetzen
        local session = PlayerManager and PlayerManager.GetSession(player)
        if session then
            session.RaidCooldownNotified = false
        end
    end
end

--[[
    Prüft Cooldowns für alle Spieler
]]
local function checkAllCooldowns()
    for _, player in ipairs(Players:GetPlayers()) do
        if PlayerManager and PlayerManager.IsPlayerReady(player) then
            task.spawn(function()
                checkPlayerCooldowns(player)
            end)
        end
    end
end

--[[
    Sendet Stats-Update an einen Spieler
    @param player: Der Spieler
]]
local function sendStatsUpdate(player)
    if not DataManager then return end
    
    local data = DataManager.GetData(player)
    if not data then return end
    
    -- Aktuelle Cooldowns berechnen
    local currentTime = os.time()
    local cooldowns = data.Cooldowns or {}
    
    local raidCooldownRemaining = math.max(0, 
        ((cooldowns.LastRaidTime or 0) + GameConfig.Raids.RaidCooldown) - currentTime
    )
    
    -- Passives Einkommen Info
    local dungeonLevel = data.Dungeon.Level or 1
    local prestigeLevel = data.Prestige.Level or 0
    local incomePerMinute = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
    
    -- Stats senden
    RemoteIndex.FireClient("Player_StatsUpdate", player, {
        Stats = data.Stats,
        Cooldowns = {
            RaidCooldownRemaining = raidCooldownRemaining,
        },
        PassiveIncome = {
            PerMinute = incomePerMinute,
            PerHour = incomePerMinute * 60,
        },
        PlayTime = data.TotalPlayTime + (currentTime - (data.LastLogin or currentTime)),
    })
end

--[[
    Sendet Stats-Updates an alle Spieler
]]
local function sendStatsUpdateToAll()
    for _, player in ipairs(Players:GetPlayers()) do
        if PlayerManager and PlayerManager.IsPlayerReady(player) then
            task.spawn(function()
                sendStatsUpdate(player)
            end)
        end
    end
end

--[[
    Prüft ob Daily Reset durchgeführt werden soll
]]
local function checkDailyReset()
    local currentTime = os.time()
    local utcDate = os.date("!*t", currentTime)
    local currentDay = utcDate.yday
    
    -- Prüfen ob neuer Tag und Reset-Stunde erreicht
    if currentDay ~= lastDailyResetDay and utcDate.hour >= CONFIG.DailyResetHour then
        lastDailyResetDay = currentDay
        performDailyReset()
    end
end

--[[
    Führt den täglichen Reset durch
]]
local function performDailyReset()
    debugPrint("Daily Reset wird durchgeführt...")
    
    -- Signal feuern
    GameLoop.Signals.DailyReset:Fire()
    
    -- Für jeden Spieler
    for _, player in ipairs(Players:GetPlayers()) do
        if PlayerManager and PlayerManager.IsPlayerReady(player) then
            task.spawn(function()
                -- Daily Login Reward könnte hier verarbeitet werden
                -- TODO: Daily Reward System implementieren
                
                PlayerManager.SendNotification(
                    player,
                    "Neuer Tag!",
                    "Tägliche Belohnungen wurden zurückgesetzt.",
                    "Info"
                )
            end)
        end
    end
    
    debugPrint("Daily Reset abgeschlossen!")
end

--[[
    Haupt-Tick Funktion
    @param deltaTime: Zeit seit letztem Tick
]]
local function mainTick(deltaTime)
    tickCount = tickCount + 1
    
    -- Timer aktualisieren
    timers.PassiveIncome = timers.PassiveIncome + deltaTime
    timers.CooldownCheck = timers.CooldownCheck + deltaTime
    timers.StatsUpdate = timers.StatsUpdate + deltaTime
    timers.DailyReset = timers.DailyReset + deltaTime
    
    -- Passive Income (alle 60 Sekunden)
    if timers.PassiveIncome >= CONFIG.PassiveIncomeInterval then
        timers.PassiveIncome = 0
        task.spawn(distributePassiveIncomeToAll)
    end
    
    -- Cooldown-Check (alle 5 Sekunden)
    if timers.CooldownCheck >= CONFIG.CooldownCheckInterval then
        timers.CooldownCheck = 0
        task.spawn(checkAllCooldowns)
    end
    
    -- Stats-Update (alle 30 Sekunden)
    if timers.StatsUpdate >= CONFIG.StatsUpdateInterval then
        timers.StatsUpdate = 0
        task.spawn(sendStatsUpdateToAll)
    end
    
    -- Daily Reset Check (alle 60 Sekunden)
    if timers.DailyReset >= 60 then
        timers.DailyReset = 0
        task.spawn(checkDailyReset)
    end
    
    -- Tick Signal feuern
    GameLoop.Signals.Tick:Fire(deltaTime, tickCount)
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

--[[
    Initialisiert den GameLoop
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
]]
function GameLoop.Initialize(dataManagerRef, playerManagerRef)
    if isRunning then
        debugWarn("GameLoop bereits initialisiert!")
        return
    end
    
    debugPrint("Initialisiere GameLoop...")
    
    -- Manager-Referenzen speichern
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    
    -- Initial Daily Reset Day setzen
    local utcDate = os.date("!*t", os.time())
    lastDailyResetDay = utcDate.yday
    
    debugPrint("GameLoop initialisiert!")
end

--[[
    Startet den GameLoop
]]
function GameLoop.Start()
    if isRunning then
        debugWarn("GameLoop läuft bereits!")
        return
    end
    
    debugPrint("Starte GameLoop...")
    
    isRunning = true
    isPaused = false
    lastTickTime = os.clock()
    
    -- Main Loop starten
    task.spawn(function()
        while isRunning do
            if not isPaused then
                local currentTime = os.clock()
                local deltaTime = currentTime - lastTickTime
                lastTickTime = currentTime
                
                -- Tick ausführen
                local success, err = pcall(mainTick, deltaTime)
                if not success then
                    debugWarn("Fehler im GameLoop Tick: " .. tostring(err))
                end
            end
            
            task.wait(CONFIG.MainTickInterval)
        end
    end)
    
    debugPrint("GameLoop gestartet!")
end

--[[
    Stoppt den GameLoop
]]
function GameLoop.Stop()
    if not isRunning then
        return
    end
    
    debugPrint("Stoppe GameLoop...")
    isRunning = false
    debugPrint("GameLoop gestoppt!")
end

--[[
    Pausiert den GameLoop
]]
function GameLoop.Pause()
    if isPaused then
        return
    end
    
    debugPrint("GameLoop pausiert")
    isPaused = true
end

--[[
    Setzt den GameLoop fort
]]
function GameLoop.Resume()
    if not isPaused then
        return
    end
    
    debugPrint("GameLoop fortgesetzt")
    isPaused = false
    lastTickTime = os.clock()
end

--[[
    Prüft ob der GameLoop läuft
    @return: boolean
]]
function GameLoop.IsRunning()
    return isRunning and not isPaused
end

--[[
    Gibt den aktuellen Tick-Count zurück
    @return: Anzahl der Ticks seit Start
]]
function GameLoop.GetTickCount()
    return tickCount
end

--[[
    Gibt die Timer-Status zurück
    @return: Timer-Table
]]
function GameLoop.GetTimers()
    return {
        PassiveIncome = CONFIG.PassiveIncomeInterval - timers.PassiveIncome,
        CooldownCheck = CONFIG.CooldownCheckInterval - timers.CooldownCheck,
        StatsUpdate = CONFIG.StatsUpdateInterval - timers.StatsUpdate,
    }
end

--[[
    Erzwingt passives Einkommen für einen Spieler (Debug)
    @param player: Der Spieler
]]
function GameLoop.ForcePassiveIncome(player)
    if not GameConfig.Debug.Enabled then
        debugWarn("ForcePassiveIncome nur im Debug-Modus verfügbar!")
        return
    end
    
    distributePassiveIncome(player)
end

--[[
    Erzwingt Stats-Update für einen Spieler
    @param player: Der Spieler
]]
function GameLoop.ForceStatsUpdate(player)
    sendStatsUpdate(player)
end

--[[
    Berechnet verbleibendes Raid-Cooldown für einen Spieler
    @param player: Der Spieler
    @return: Sekunden bis Raid verfügbar (0 wenn bereit)
]]
function GameLoop.GetRaidCooldown(player)
    if not DataManager then return 0 end
    
    local data = DataManager.GetData(player)
    if not data then return 0 end
    
    -- Debug: Instant Cooldowns
    if GameConfig.Debug.InstantCooldowns then
        return 0
    end
    
    local currentTime = os.time()
    local lastRaidTime = data.Cooldowns.LastRaidTime or 0
    local cooldown = GameConfig.Raids.RaidCooldown
    
    return math.max(0, (lastRaidTime + cooldown) - currentTime)
end

--[[
    Prüft ob ein Spieler raiden kann
    @param player: Der Spieler
    @return: canRaid, reason
]]
function GameLoop.CanPlayerRaid(player)
    if not DataManager then
        return false, "System nicht bereit"
    end
    
    local data = DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    -- Dungeon-Level prüfen
    local dungeonLevel = data.Dungeon.Level or 1
    if dungeonLevel < GameConfig.Raids.MinDungeonLevelToRaid then
        return false, "Dungeon-Level " .. GameConfig.Raids.MinDungeonLevelToRaid .. " benötigt"
    end
    
    -- Team prüfen
    local team = data.Heroes.Team or {}
    if #team == 0 then
        return false, "Kein Helden-Team ausgewählt"
    end
    
    -- Cooldown prüfen
    local cooldownRemaining = GameLoop.GetRaidCooldown(player)
    if cooldownRemaining > 0 then
        local minutes = math.ceil(cooldownRemaining / 60)
        return false, "Raid-Cooldown: " .. minutes .. " Minuten verbleibend"
    end
    
    return true, nil
end

--[[
    Setzt den Raid-Cooldown für einen Spieler
    @param player: Der Spieler
]]
function GameLoop.SetRaidCooldown(player)
    if not DataManager then return end
    
    DataManager.SetValue(player, "Cooldowns.LastRaidTime", os.time())
    
    -- Session-Flag zurücksetzen
    if PlayerManager then
        local session = PlayerManager.GetSession(player)
        if session then
            session.RaidCooldownNotified = false
        end
    end
end

return GameLoop
