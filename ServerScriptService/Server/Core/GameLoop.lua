--[[
    GameLoop.lua
    Zentraler Spiel-Tick
    Pfad: ServerScriptService/Server/Core/GameLoop
    
    Verantwortlich für:
    - Passives Einkommen (zeitbasiert)
    - Cooldown-Management
    - Daily Rewards/Reset
    - Periodische Updates
    
    WICHTIG: Läuft kontinuierlich auf dem Server!
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
    -- Tick-Raten (in Sekunden)
    MainTickRate = 1,                   -- Haupt-Tick
    PassiveIncomeRate = 60,             -- Passives Einkommen
    CooldownCheckRate = 5,              -- Cooldown-Prüfung
    StatsUpdateRate = 30,               -- Stats an Client senden
    DailyCheckRate = 60,                -- Daily Reset prüfen
    
    -- Auto-Collect Settings
    AutoCollectEnabled = false,         -- Automatisches Einsammeln
    MaxAccumulatedMinutes = 480,        -- Max 8 Stunden akkumulieren
    
    -- Daily Reset
    DailyResetHour = 0,                 -- Mitternacht UTC
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- LOOP STATE
-------------------------------------------------
local loopState = {
    IsRunning = false,
    StartTime = 0,
    TotalTicks = 0,
    
    -- Timer für verschiedene Operationen
    PassiveIncomeTimer = 0,
    CooldownCheckTimer = 0,
    StatsUpdateTimer = 0,
    DailyCheckTimer = 0,
    
    -- Letzter Daily Reset (Server-weit)
    LastDailyReset = 0,
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
GameLoop.Signals = {
    Tick = SignalUtil.new(),                    -- (deltaTime, totalTicks)
    PassiveIncomeTick = SignalUtil.new(),       -- ()
    CooldownTick = SignalUtil.new(),            -- ()
    DailyReset = SignalUtil.new(),              -- (player)
    LoopStarted = SignalUtil.new(),             -- ()
    LoopStopped = SignalUtil.new(),             -- ()
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[GameLoop]", ...)
    end
end

--[[
    Gibt aktuellen UTC-Tag zurück (als Zahl YYYYMMDD)
]]
local function getCurrentDay()
    local date = os.date("!*t")
    return date.year * 10000 + date.month * 100 + date.day
end

--[[
    Prüft ob Daily Reset nötig ist
    @param lastResetDay: Letzter Reset-Tag
    @return: boolean
]]
local function needsDailyReset(lastResetDay)
    local currentDay = getCurrentDay()
    return currentDay > lastResetDay
end

-------------------------------------------------
-- TICK HANDLERS
-------------------------------------------------

--[[
    Verarbeitet passives Einkommen für alle Spieler
]]
local function processPassiveIncome()
    if not DataManager or not PlayerManager then return end
    
    for _, player in ipairs(PlayerManager.GetReadyPlayers()) do
        local data = DataManager.GetData(player)
        if not data then continue end
        
        local dungeonLevel = data.Dungeon.Level or 1
        local prestigeLevel = data.Prestige.Level or 0
        
        -- Einkommen pro Minute berechnen
        local incomePerMinute = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
        
        -- Akkumuliertes Einkommen tracken (nicht automatisch hinzufügen)
        -- Spieler muss manuell "Abholen" klicken
        
        -- Letzte Sammelzeit updaten falls nicht gesetzt
        if not data.Cooldowns.LastPassiveCollect then
            DataManager.SetValue(player, "Cooldowns.LastPassiveCollect", os.time())
        end
        
        -- Max-Akkumulation prüfen und Client informieren
        local lastCollect = data.Cooldowns.LastPassiveCollect or os.time()
        local minutesPassed = (os.time() - lastCollect) / 60
        
        if minutesPassed >= CONFIG.MaxAccumulatedMinutes then
            -- Benachrichtigung dass Max erreicht
            if minutesPassed < CONFIG.MaxAccumulatedMinutes + 1 then
                PlayerManager.SendNotification(
                    player,
                    "Einkommen voll!",
                    "Sammle dein passives Gold ein!",
                    "Warning"
                )
            end
        end
        
        -- Auto-Collect (falls aktiviert)
        if CONFIG.AutoCollectEnabled then
            local accumulated = CurrencyUtil.CalculateAccumulatedIncome(
                dungeonLevel,
                prestigeLevel,
                lastCollect,
                os.time()
            )
            
            if accumulated > 0 then
                local currentGold = data.Currency.Gold or 0
                local maxGold = GameConfig.Currency.MaxGold
                local addable = math.min(accumulated, maxGold - currentGold)
                
                if addable > 0 then
                    DataManager.IncrementValue(player, "Currency.Gold", addable)
                    DataManager.SetValue(player, "Cooldowns.LastPassiveCollect", os.time())
                    
                    -- Stats tracken
                    DataManager.IncrementValue(player, "Stats.TotalGoldEarned", addable)
                    
                    -- Client informieren
                    RemoteIndex.FireClient("Currency_Update", player, {
                        Gold = data.Currency.Gold + addable,
                        Gems = data.Currency.Gems,
                        Source = "PassiveIncome",
                    })
                end
            end
        end
    end
    
    GameLoop.Signals.PassiveIncomeTick:Fire()
end

--[[
    Prüft und verarbeitet Cooldowns für alle Spieler
]]
local function processCooldowns()
    if not DataManager or not PlayerManager then return end
    
    local currentTime = os.time()
    
    for _, player in ipairs(PlayerManager.GetReadyPlayers()) do
        local data = DataManager.GetData(player)
        if not data then continue end
        
        -- Raid Cooldown prüfen
        local lastRaid = data.Cooldowns.LastRaidTime or 0
        local raidCooldown = GameConfig.Raids.RaidCooldown
        local raidReady = (currentTime - lastRaid) >= raidCooldown
        
        -- Client über Cooldown-Status informieren
        RemoteIndex.FireClient("Cooldown_Update", player, {
            RaidReady = raidReady,
            RaidCooldownRemaining = raidReady and 0 or (raidCooldown - (currentTime - lastRaid)),
        })
    end
    
    GameLoop.Signals.CooldownTick:Fire()
end

--[[
    Prüft Daily Reset für alle Spieler
]]
local function processDailyReset()
    if not DataManager or not PlayerManager then return end
    
    local currentDay = getCurrentDay()
    
    for _, player in ipairs(PlayerManager.GetReadyPlayers()) do
        local data = DataManager.GetData(player)
        if not data then continue end
        
        local lastLoginDay = data.LastLoginDay or 0
        
        if needsDailyReset(lastLoginDay) then
            debugPrint("Daily Reset für " .. player.Name)
            
            -- Letzten Login-Tag updaten
            DataManager.SetValue(player, "LastLoginDay", currentDay)
            
            -- Daily Streak prüfen
            local streak = data.DailyStreak or 0
            local yesterday = currentDay - 1
            
            if lastLoginDay == yesterday then
                -- Streak fortsetzen
                streak = streak + 1
            elseif lastLoginDay < yesterday then
                -- Streak zurücksetzen
                streak = 1
            end
            
            DataManager.SetValue(player, "DailyStreak", streak)
            
            -- Daily Reward berechnen
            local dailyReward = {
                Gold = 100 + (streak * 50),     -- Basis + Streak-Bonus
                Gems = math.floor(streak / 7), -- 1 Gem pro Woche
            }
            
            -- Max-Caps anwenden
            dailyReward.Gold = math.min(dailyReward.Gold, 1000)
            dailyReward.Gems = math.min(dailyReward.Gems, 10)
            
            -- Belohnung zur Inbox hinzufügen
            local inbox = data.Inbox or {}
            table.insert(inbox, {
                Id = "daily_" .. currentDay,
                Type = "DailyReward",
                Title = "Tägliche Belohnung",
                Message = "Tag " .. streak .. " Streak!",
                Rewards = dailyReward,
                Claimed = false,
                CreatedAt = os.time(),
                ExpiresAt = os.time() + 86400 * 7, -- 7 Tage gültig
            })
            
            DataManager.SetValue(player, "Inbox", inbox)
            
            -- Client benachrichtigen
            RemoteIndex.FireClient("Inbox_Update", player, inbox)
            
            PlayerManager.SendNotification(
                player,
                "Tägliche Belohnung!",
                "Tag " .. streak .. " - Schau in deine Inbox!",
                "Success"
            )
            
            -- Signal feuern
            GameLoop.Signals.DailyReset:Fire(player)
        end
    end
end

--[[
    Sendet periodische Stats-Updates an alle Spieler
]]
local function processStatsUpdate()
    if not DataManager or not PlayerManager then return end
    
    for _, player in ipairs(PlayerManager.GetReadyPlayers()) do
        local data = DataManager.GetData(player)
        if not data then continue end
        
        local dungeonLevel = data.Dungeon.Level or 1
        local prestigeLevel = data.Prestige.Level or 0
        local lastCollect = data.Cooldowns.LastPassiveCollect or os.time()
        
        -- Akkumuliertes Einkommen berechnen
        local accumulated = CurrencyUtil.CalculateAccumulatedIncome(
            dungeonLevel,
            prestigeLevel,
            lastCollect,
            os.time()
        )
        
        -- Einkommen pro Minute
        local incomePerMinute = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
        
        -- Stats an Client senden
        RemoteIndex.FireClient("Stats_Update", player, {
            AccumulatedIncome = accumulated,
            IncomePerMinute = incomePerMinute,
            DungeonLevel = dungeonLevel,
            PrestigeLevel = prestigeLevel,
            PrestigeBonus = prestigeLevel * GameConfig.Prestige.BonusPerPrestige,
        })
    end
end

-------------------------------------------------
-- HAUPT-LOOP
-------------------------------------------------

--[[
    Haupt-Tick Funktion
    @param deltaTime: Zeit seit letztem Tick
]]
local function mainTick(deltaTime)
    if not loopState.IsRunning then return end
    
    loopState.TotalTicks = loopState.TotalTicks + 1
    
    -- Timer updaten
    loopState.PassiveIncomeTimer = loopState.PassiveIncomeTimer + deltaTime
    loopState.CooldownCheckTimer = loopState.CooldownCheckTimer + deltaTime
    loopState.StatsUpdateTimer = loopState.StatsUpdateTimer + deltaTime
    loopState.DailyCheckTimer = loopState.DailyCheckTimer + deltaTime
    
    -- Passives Einkommen
    if loopState.PassiveIncomeTimer >= CONFIG.PassiveIncomeRate then
        loopState.PassiveIncomeTimer = 0
        task.spawn(processPassiveIncome)
    end
    
    -- Cooldown-Check
    if loopState.CooldownCheckTimer >= CONFIG.CooldownCheckRate then
        loopState.CooldownCheckTimer = 0
        task.spawn(processCooldowns)
    end
    
    -- Stats-Update
    if loopState.StatsUpdateTimer >= CONFIG.StatsUpdateRate then
        loopState.StatsUpdateTimer = 0
        task.spawn(processStatsUpdate)
    end
    
    -- Daily Reset Check
    if loopState.DailyCheckTimer >= CONFIG.DailyCheckRate then
        loopState.DailyCheckTimer = 0
        task.spawn(processDailyReset)
    end
    
    -- Tick Signal
    GameLoop.Signals.Tick:Fire(deltaTime, loopState.TotalTicks)
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den GameLoop
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
]]
function GameLoop.Initialize(dataManagerRef, playerManagerRef)
    debugPrint("Initialisiere GameLoop...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    
    -- Letzten Daily Reset initialisieren
    loopState.LastDailyReset = getCurrentDay()
    
    debugPrint("GameLoop initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - LOOP CONTROL
-------------------------------------------------

--[[
    Startet den GameLoop
]]
function GameLoop.Start()
    if loopState.IsRunning then
        debugPrint("GameLoop läuft bereits")
        return
    end
    
    debugPrint("Starte GameLoop...")
    
    loopState.IsRunning = true
    loopState.StartTime = os.time()
    loopState.TotalTicks = 0
    
    -- Tick-Loop starten
    task.spawn(function()
        local lastTick = os.clock()
        
        while loopState.IsRunning do
            local currentTime = os.clock()
            local deltaTime = currentTime - lastTick
            lastTick = currentTime
            
            mainTick(deltaTime)
            
            task.wait(CONFIG.MainTickRate)
        end
    end)
    
    GameLoop.Signals.LoopStarted:Fire()
    debugPrint("GameLoop gestartet!")
end

--[[
    Stoppt den GameLoop
]]
function GameLoop.Stop()
    if not loopState.IsRunning then
        debugPrint("GameLoop läuft nicht")
        return
    end
    
    debugPrint("Stoppe GameLoop...")
    
    loopState.IsRunning = false
    
    GameLoop.Signals.LoopStopped:Fire()
    debugPrint("GameLoop gestoppt!")
end

--[[
    Pausiert/Setzt den GameLoop fort
    @param paused: boolean
]]
function GameLoop.SetPaused(paused)
    if paused then
        GameLoop.Stop()
    else
        GameLoop.Start()
    end
end

--[[
    Prüft ob GameLoop läuft
    @return: boolean
]]
function GameLoop.IsRunning()
    return loopState.IsRunning
end

-------------------------------------------------
-- PUBLIC API - MANUELLE TRIGGER
-------------------------------------------------

--[[
    Erzwingt Passive Income Tick
]]
function GameLoop.ForcePassiveIncomeTick()
    task.spawn(processPassiveIncome)
end

--[[
    Erzwingt Cooldown Check
]]
function GameLoop.ForceCooldownCheck()
    task.spawn(processCooldowns)
end

--[[
    Erzwingt Daily Reset für einen Spieler
    @param player: Der Spieler
]]
function GameLoop.ForceDailyReset(player)
    if not DataManager then return end
    
    local data = DataManager.GetData(player)
    if not data then return end
    
    -- LastLoginDay auf "gestern" setzen um Reset zu triggern
    DataManager.SetValue(player, "LastLoginDay", getCurrentDay() - 1)
    
    -- Daily Reset verarbeiten
    task.spawn(processDailyReset)
end

--[[
    Erzwingt Stats-Update für einen Spieler
    @param player: Der Spieler
]]
function GameLoop.ForceStatsUpdate(player)
    if not DataManager then return end
    
    local data = DataManager.GetData(player)
    if not data then return end
    
    local dungeonLevel = data.Dungeon.Level or 1
    local prestigeLevel = data.Prestige.Level or 0
    local lastCollect = data.Cooldowns.LastPassiveCollect or os.time()
    
    local accumulated = CurrencyUtil.CalculateAccumulatedIncome(
        dungeonLevel,
        prestigeLevel,
        lastCollect,
        os.time()
    )
    
    local incomePerMinute = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
    
    RemoteIndex.FireClient("Stats_Update", player, {
        AccumulatedIncome = accumulated,
        IncomePerMinute = incomePerMinute,
        DungeonLevel = dungeonLevel,
        PrestigeLevel = prestigeLevel,
        PrestigeBonus = prestigeLevel * GameConfig.Prestige.BonusPerPrestige,
    })
end

-------------------------------------------------
-- PUBLIC API - STATISTIKEN
-------------------------------------------------

--[[
    Gibt Loop-Statistiken zurück
    @return: Stats-Table
]]
function GameLoop.GetStats()
    return {
        IsRunning = loopState.IsRunning,
        TotalTicks = loopState.TotalTicks,
        Uptime = loopState.IsRunning and (os.time() - loopState.StartTime) or 0,
        CurrentDay = getCurrentDay(),
        
        -- Timer States
        PassiveIncomeTimer = loopState.PassiveIncomeTimer,
        CooldownCheckTimer = loopState.CooldownCheckTimer,
        StatsUpdateTimer = loopState.StatsUpdateTimer,
        
        -- Rates
        MainTickRate = CONFIG.MainTickRate,
        PassiveIncomeRate = CONFIG.PassiveIncomeRate,
        CooldownCheckRate = CONFIG.CooldownCheckRate,
    }
end

--[[
    Gibt formattierte Uptime zurück
    @return: String (z.B. "2h 15m 30s")
]]
function GameLoop.GetFormattedUptime()
    if not loopState.IsRunning then
        return "Nicht aktiv"
    end
    
    local seconds = os.time() - loopState.StartTime
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

-------------------------------------------------
-- PUBLIC API - KONFIGURATION
-------------------------------------------------

--[[
    Setzt Tick-Rate
    @param tickType: "Main", "PassiveIncome", "Cooldown", "Stats"
    @param rate: Neue Rate in Sekunden
]]
function GameLoop.SetTickRate(tickType, rate)
    if tickType == "Main" then
        CONFIG.MainTickRate = rate
    elseif tickType == "PassiveIncome" then
        CONFIG.PassiveIncomeRate = rate
    elseif tickType == "Cooldown" then
        CONFIG.CooldownCheckRate = rate
    elseif tickType == "Stats" then
        CONFIG.StatsUpdateRate = rate
    end
    
    debugPrint("Tick-Rate geändert: " .. tickType .. " = " .. rate .. "s")
end

--[[
    Aktiviert/Deaktiviert Auto-Collect
    @param enabled: boolean
]]
function GameLoop.SetAutoCollect(enabled)
    CONFIG.AutoCollectEnabled = enabled
    debugPrint("Auto-Collect: " .. tostring(enabled))
end

return GameLoop
