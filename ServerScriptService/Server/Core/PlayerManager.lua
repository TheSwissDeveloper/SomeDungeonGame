--[[
    PlayerManager.lua
    Spieler-Lifecycle Management
    Pfad: ServerScriptService/Server/Core/PlayerManager
    
    Verantwortlich für:
    - Spieler Join/Leave Handling
    - Session-Tracking
    - Benachrichtigungen an Spieler
    - Spieler-bezogene Utilities
    
    WICHTIG: Arbeitet eng mit DataManager zusammen!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Auf Shared-Module warten
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")
local RemotesPath = SharedPath:WaitForChild("Remotes")

-- Module laden
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- DataManager-Referenz (wird bei Initialize gesetzt)
local DataManager = nil

local PlayerManager = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Session Timeout (für AFK-Erkennung)
    AFKTimeout = 600,           -- 10 Minuten
    AFKCheckInterval = 60,      -- Jede Minute prüfen
    
    -- Willkommensnachricht
    ShowWelcomeMessage = true,
    WelcomeDelay = 2,           -- Sekunden nach Join
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- INTERNER STATE
-------------------------------------------------
local activeSessions = {}       -- { [UserId] = SessionData }
local playerCount = 0

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
PlayerManager.Signals = {
    PlayerJoined = SignalUtil.new(),        -- (player)
    PlayerLeft = SignalUtil.new(),          -- (player)
    PlayerReady = SignalUtil.new(),         -- (player, data)
    PlayerAFK = SignalUtil.new(),           -- (player)
    PlayerReturned = SignalUtil.new(),      -- (player)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[PlayerManager]", ...)
    end
end

local function debugWarn(...)
    warn("[PlayerManager]", ...)
end

--[[
    Erstellt Session-Daten für einen Spieler
    @param player: Der Spieler
    @return: SessionData
]]
local function createSessionData(player)
    return {
        UserId = player.UserId,
        JoinTime = os.time(),
        LastActivity = os.time(),
        IsAFK = false,
        IsReady = false,
        Character = nil,
    }
end

--[[
    Sendet Willkommensnachricht
    @param player: Der Spieler
    @param isNewPlayer: Ob es ein neuer Spieler ist
]]
local function sendWelcomeMessage(player, isNewPlayer)
    if not CONFIG.ShowWelcomeMessage then return end
    
    task.delay(CONFIG.WelcomeDelay, function()
        if not player or not player.Parent then return end
        
        if isNewPlayer then
            PlayerManager.SendNotification(
                player,
                "Willkommen bei Dungeon Tycoon!",
                "Baue deinen Dungeon und verteidige ihn gegen Angreifer!",
                "Info"
            )
        else
            local data = DataManager and DataManager.GetData(player)
            if data then
                local level = data.Dungeon.Level or 1
                PlayerManager.SendNotification(
                    player,
                    "Willkommen zurück!",
                    "Dein Dungeon ist Level " .. level,
                    "Success"
                )
            end
        end
    end)
end

-------------------------------------------------
-- SPIELER EVENT HANDLER
-------------------------------------------------

--[[
    Handler für Spieler-Join
    @param player: Der beigetretene Spieler
]]
local function onPlayerAdded(player)
    debugPrint(player.Name .. " ist beigetreten")
    
    -- Session erstellen
    activeSessions[player.UserId] = createSessionData(player)
    playerCount = playerCount + 1
    
    -- Signal feuern
    PlayerManager.Signals.PlayerJoined:Fire(player)
    
    -- Daten laden (über DataManager)
    if DataManager then
        DataManager.LoadPlayer(player)
        
        -- Auf Daten warten
        DataManager.Signals.PlayerDataLoaded:Connect(function(loadedPlayer, data)
            if loadedPlayer == player then
                local session = activeSessions[player.UserId]
                if session then
                    session.IsReady = true
                end
                
                -- Prüfen ob neuer Spieler
                local isNewPlayer = data.Stats.TotalPlayTime == 0
                
                -- Willkommensnachricht
                sendWelcomeMessage(player, isNewPlayer)
                
                -- Signal feuern
                PlayerManager.Signals.PlayerReady:Fire(player, data)
                
                debugPrint(player.Name .. " ist bereit (Level " .. (data.Dungeon.Level or 1) .. ")")
            end
        end)
    end
    
    -- Character-Handling
    player.CharacterAdded:Connect(function(character)
        local session = activeSessions[player.UserId]
        if session then
            session.Character = character
        end
    end)
    
    -- Aktivitäts-Tracking
    player.Chatted:Connect(function()
        PlayerManager.UpdateActivity(player)
    end)
end

--[[
    Handler für Spieler-Leave
    @param player: Der verlassende Spieler
]]
local function onPlayerRemoving(player)
    debugPrint(player.Name .. " verlässt")
    
    -- Signal feuern (vor Cleanup!)
    PlayerManager.Signals.PlayerLeft:Fire(player)
    
    -- Daten speichern und entladen
    if DataManager then
        DataManager.UnloadPlayer(player)
    end
    
    -- Session entfernen
    activeSessions[player.UserId] = nil
    playerCount = playerCount - 1
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den PlayerManager
    @param dataManagerRef: Referenz zum DataManager
]]
function PlayerManager.Initialize(dataManagerRef)
    debugPrint("Initialisiere PlayerManager...")
    
    DataManager = dataManagerRef
    
    -- Events verbinden
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Bereits verbundene Spieler verarbeiten
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            onPlayerAdded(player)
        end)
    end
    
    -- AFK-Check Loop starten
    task.spawn(function()
        while true do
            task.wait(CONFIG.AFKCheckInterval)
            PlayerManager._checkAFKPlayers()
        end
    end)
    
    debugPrint("PlayerManager initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - NOTIFICATIONS
-------------------------------------------------

--[[
    Sendet Benachrichtigung an Spieler
    @param player: Ziel-Spieler
    @param title: Titel der Benachrichtigung
    @param message: Nachricht
    @param notifType: Typ (Success, Error, Warning, Info)
]]
function PlayerManager.SendNotification(player, title, message, notifType)
    if not player or not player.Parent then return end
    
    RemoteIndex.FireClient("Notification", player, {
        Title = title or "Benachrichtigung",
        Message = message or "",
        Type = notifType or "Info",
    })
end

--[[
    Sendet Benachrichtigung an alle Spieler
    @param title: Titel
    @param message: Nachricht
    @param notifType: Typ
]]
function PlayerManager.BroadcastNotification(title, message, notifType)
    RemoteIndex.FireAllClients("Notification", {
        Title = title or "Benachrichtigung",
        Message = message or "",
        Type = notifType or "Info",
    })
end

--[[
    Sendet Benachrichtigung an alle außer einen Spieler
    @param excludePlayer: Spieler der ausgeschlossen wird
    @param title: Titel
    @param message: Nachricht
    @param notifType: Typ
]]
function PlayerManager.BroadcastExcept(excludePlayer, title, message, notifType)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= excludePlayer then
            PlayerManager.SendNotification(player, title, message, notifType)
        end
    end
end

-------------------------------------------------
-- PUBLIC API - SESSION MANAGEMENT
-------------------------------------------------

--[[
    Gibt Session-Daten eines Spielers zurück
    @param player: Der Spieler
    @return: SessionData oder nil
]]
function PlayerManager.GetSession(player)
    return activeSessions[player.UserId]
end

--[[
    Prüft ob Spieler bereit ist (Daten geladen)
    @param player: Der Spieler
    @return: boolean
]]
function PlayerManager.IsPlayerReady(player)
    local session = activeSessions[player.UserId]
    return session ~= nil and session.IsReady
end

--[[
    Aktualisiert letzte Aktivität eines Spielers
    @param player: Der Spieler
]]
function PlayerManager.UpdateActivity(player)
    local session = activeSessions[player.UserId]
    if session then
        local wasAFK = session.IsAFK
        session.LastActivity = os.time()
        session.IsAFK = false
        
        if wasAFK then
            PlayerManager.Signals.PlayerReturned:Fire(player)
            debugPrint(player.Name .. " ist zurück vom AFK")
        end
    end
end

--[[
    Prüft ob Spieler AFK ist
    @param player: Der Spieler
    @return: boolean
]]
function PlayerManager.IsAFK(player)
    local session = activeSessions[player.UserId]
    return session ~= nil and session.IsAFK
end

--[[
    Interner AFK-Check (vom Loop aufgerufen)
]]
function PlayerManager._checkAFKPlayers()
    local currentTime = os.time()
    
    for userId, session in pairs(activeSessions) do
        if not session.IsAFK then
            local inactiveTime = currentTime - session.LastActivity
            
            if inactiveTime >= CONFIG.AFKTimeout then
                session.IsAFK = true
                
                local player = Players:GetPlayerByUserId(userId)
                if player then
                    PlayerManager.Signals.PlayerAFK:Fire(player)
                    debugPrint(player.Name .. " ist jetzt AFK")
                end
            end
        end
    end
end

-------------------------------------------------
-- PUBLIC API - SPIELER ABFRAGEN
-------------------------------------------------

--[[
    Gibt Anzahl aktiver Spieler zurück
    @return: Spieleranzahl
]]
function PlayerManager.GetPlayerCount()
    return playerCount
end

--[[
    Gibt alle aktiven Spieler zurück
    @return: Array von Spielern
]]
function PlayerManager.GetAllPlayers()
    return Players:GetPlayers()
end

--[[
    Gibt alle bereiten Spieler zurück
    @return: Array von Spielern
]]
function PlayerManager.GetReadyPlayers()
    local readyPlayers = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if PlayerManager.IsPlayerReady(player) then
            table.insert(readyPlayers, player)
        end
    end
    
    return readyPlayers
end

--[[
    Findet Spieler nach Name
    @param name: Spielername (partiell)
    @return: Spieler oder nil
]]
function PlayerManager.FindPlayerByName(name)
    name = name:lower()
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower():find(name) then
            return player
        end
    end
    
    return nil
end

--[[
    Findet Spieler nach UserId
    @param userId: User-ID
    @return: Spieler oder nil
]]
function PlayerManager.GetPlayerByUserId(userId)
    return Players:GetPlayerByUserId(userId)
end

-------------------------------------------------
-- PUBLIC API - SPIELZEIT
-------------------------------------------------

--[[
    Gibt Spielzeit der aktuellen Session zurück
    @param player: Der Spieler
    @return: Sekunden oder 0
]]
function PlayerManager.GetSessionPlayTime(player)
    local session = activeSessions[player.UserId]
    if session then
        return os.time() - session.JoinTime
    end
    return 0
end

--[[
    Gibt formatierte Spielzeit zurück
    @param player: Der Spieler
    @return: Formatierter String (z.B. "1h 23m")
]]
function PlayerManager.GetFormattedPlayTime(player)
    local seconds = PlayerManager.GetSessionPlayTime(player)
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

-------------------------------------------------
-- PUBLIC API - UTILITY
-------------------------------------------------

--[[
    Teleportiert Spieler zu Position
    @param player: Der Spieler
    @param position: Vector3 oder CFrame
]]
function PlayerManager.TeleportPlayer(player, position)
    local character = player.Character
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    if typeof(position) == "Vector3" then
        humanoidRootPart.CFrame = CFrame.new(position)
    else
        humanoidRootPart.CFrame = position
    end
end

--[[
    Gibt Statistiken über alle Spieler zurück
    @return: Stats-Table
]]
function PlayerManager.GetStats()
    local afkCount = 0
    local readyCount = 0
    
    for _, session in pairs(activeSessions) do
        if session.IsAFK then
            afkCount = afkCount + 1
        end
        if session.IsReady then
            readyCount = readyCount + 1
        end
    end
    
    return {
        TotalPlayers = playerCount,
        ReadyPlayers = readyCount,
        AFKPlayers = afkCount,
        ActivePlayers = playerCount - afkCount,
    }
end

return PlayerManager
