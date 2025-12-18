--[[
    PlayerManager.lua
    Spieler-Lifecycle Management für "Dungeon Tycoon"
    Pfad: ServerScriptService/Server/Core/PlayerManager
    
    Verantwortlich für:
    - Spieler Join/Leave Handling
    - Koordination mit DataManager
    - Initiale Client-Updates
    - Session-Tracking
    
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
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- DataManager wird später geladen (zirkuläre Abhängigkeit vermeiden)
local DataManager = nil

local PlayerManager = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Timeout für Daten-Laden (Sekunden)
    LoadTimeout = 30,
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- INTERNER STATE
-------------------------------------------------
local activeSessions = {}       -- { [UserId] = { JoinTime, LastActivity, ... } }
local isInitialized = false
local isShuttingDown = false

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
PlayerManager.Signals = {
    PlayerReady = SignalUtil.new(),         -- (player, data) - Spieler vollständig geladen
    PlayerLeaving = SignalUtil.new(),       -- (player) - Spieler verlässt
    PlayerKicked = SignalUtil.new(),        -- (player, reason) - Spieler gekickt
    SessionUpdated = SignalUtil.new(),      -- (player, sessionData) - Session aktualisiert
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[PlayerManager]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[PlayerManager]", ...)
end

--[[
    Erstellt eine neue Session für einen Spieler
    @param player: Der Spieler
    @return: Session-Daten
]]
local function createSession(player)
    local session = {
        UserId = player.UserId,
        Name = player.Name,
        JoinTime = os.time(),
        LastActivity = os.time(),
        IsReady = false,
        DataLoaded = false,
    }
    
    activeSessions[player.UserId] = session
    debugPrint("Session erstellt für " .. player.Name)
    
    return session
end

--[[
    Aktualisiert die letzte Aktivität eines Spielers
    @param player: Der Spieler
]]
local function updateActivity(player)
    local session = activeSessions[player.UserId]
    if session then
        session.LastActivity = os.time()
    end
end

--[[
    Sendet initiale Daten an den Client
    @param player: Der Spieler
    @param data: Die Spielerdaten
]]
local function sendInitialData(player, data)
    -- Prüfen ob Spieler noch verbunden
    if not player or not player.Parent then
        return
    end
    
    debugPrint("Sende initiale Daten an " .. player.Name)
    
    -- Währung senden
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = data.Currency.Gold,
        Gems = data.Currency.Gems,
    })
    
    -- Dungeon-Daten senden
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Level = data.Dungeon.Level,
        Experience = data.Dungeon.Experience,
        Name = data.Dungeon.Name,
        Rooms = data.Dungeon.Rooms,
        UnlockedTraps = data.Dungeon.UnlockedTraps,
        UnlockedMonsters = data.Dungeon.UnlockedMonsters,
    })
    
    -- Helden-Daten senden
    RemoteIndex.FireClient("Heroes_Update", player, {
        Owned = data.Heroes.Owned,
        Team = data.Heroes.Team,
        Unlocked = data.Heroes.Unlocked,
    })
    
    -- Stats senden
    RemoteIndex.FireClient("Player_StatsUpdate", player, data.Stats)
    
    -- Inbox senden
    RemoteIndex.FireClient("Inbox_Update", player, data.Inbox)
    
    -- DataLoaded Event
    RemoteIndex.FireClient("Player_DataLoaded", player, {
        Success = true,
        Prestige = data.Prestige,
        Settings = data.Settings,
        Tutorial = data.Progress.Tutorial,
    })
end

--[[
    Handler wenn Spielerdaten geladen wurden
    @param player: Der Spieler
    @param data: Die geladenen Daten
]]
local function onDataLoaded(player, data)
    local session = activeSessions[player.UserId]
    if not session then
        debugWarn("Keine Session für " .. player.Name .. " bei DataLoaded")
        return
    end
    
    -- Session aktualisieren
    session.DataLoaded = true
    session.IsReady = true
    
    -- Initiale Daten an Client senden
    sendInitialData(player, data)
    
    -- Signal feuern
    PlayerManager.Signals.PlayerReady:Fire(player, data)
    PlayerManager.Signals.SessionUpdated:Fire(player, session)
    
    debugPrint("Spieler bereit: " .. player.Name)
end

--[[
    Handler wenn Daten-Laden fehlschlägt
    @param player: Der Spieler
    @param errorMessage: Fehlermeldung
]]
local function onDataLoadFailed(player, errorMessage)
    local session = activeSessions[player.UserId]
    if session then
        session.DataLoaded = false
        session.IsReady = false
    end
    
    debugWarn("Daten-Laden fehlgeschlagen für " .. player.Name .. ": " .. errorMessage)
    
    -- Client informieren
    if player and player.Parent then
        RemoteIndex.FireClient("Player_DataLoaded", player, {
            Success = false,
            Error = errorMessage,
        })
    end
end

-------------------------------------------------
-- SPIELER JOIN/LEAVE HANDLER
-------------------------------------------------

--[[
    Handler wenn ein Spieler dem Spiel beitritt
    @param player: Der neue Spieler
]]
local function onPlayerAdded(player)
    debugPrint("Spieler beigetreten: " .. player.Name .. " (ID: " .. player.UserId .. ")")
    
    -- Session erstellen
    local session = createSession(player)
    
    -- Daten laden (async)
    task.spawn(function()
        -- Kurz warten damit Client bereit ist
        task.wait(1)
        
        -- Prüfen ob Spieler noch da ist
        if not player or not player.Parent then
            debugPrint("Spieler " .. session.Name .. " hat vor Daten-Laden verlassen")
            activeSessions[session.UserId] = nil
            return
        end
        
        -- DataManager aufrufen
        if DataManager then
            DataManager.LoadPlayer(player)
        else
            debugWarn("DataManager nicht verfügbar!")
            onDataLoadFailed(player, "Interner Fehler: DataManager nicht initialisiert")
        end
    end)
end

--[[
    Handler wenn ein Spieler das Spiel verlässt
    @param player: Der Spieler der verlässt
]]
local function onPlayerRemoving(player)
    debugPrint("Spieler verlässt: " .. player.Name)
    
    -- Signal feuern bevor Cleanup
    PlayerManager.Signals.PlayerLeaving:Fire(player)
    
    -- DataManager aufrufen
    if DataManager then
        DataManager.UnloadPlayer(player)
    end
    
    -- Session entfernen
    activeSessions[player.UserId] = nil
    
    debugPrint("Spieler entfernt: " .. player.Name)
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

--[[
    Initialisiert den PlayerManager
    @param dataManagerRef: Referenz zum DataManager
]]
function PlayerManager.Initialize(dataManagerRef)
    if isInitialized then
        debugWarn("PlayerManager bereits initialisiert!")
        return
    end
    
    debugPrint("Initialisiere PlayerManager...")
    
    -- DataManager Referenz speichern
    DataManager = dataManagerRef
    
    -- DataManager Signals verbinden
    if DataManager and DataManager.Signals then
        DataManager.Signals.PlayerDataLoaded:Connect(onDataLoaded)
        DataManager.Signals.DataLoadFailed:Connect(onDataLoadFailed)
    end
    
    -- Player Events verbinden
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Bereits verbundene Spieler verarbeiten
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            onPlayerAdded(player)
        end)
    end
    
    -- BindToClose für graceful shutdown
    game:BindToClose(function()
        PlayerManager.OnServerShutdown()
    end)
    
    isInitialized = true
    debugPrint("PlayerManager initialisiert!")
end

--[[
    Gibt die Session eines Spielers zurück
    @param player: Der Spieler
    @return: Session-Daten oder nil
]]
function PlayerManager.GetSession(player)
    return activeSessions[player.UserId]
end

--[[
    Prüft ob ein Spieler vollständig geladen ist
    @param player: Der Spieler
    @return: boolean
]]
function PlayerManager.IsPlayerReady(player)
    local session = activeSessions[player.UserId]
    return session ~= nil and session.IsReady
end

--[[
    Gibt alle aktiven Sessions zurück
    @return: Table mit Sessions
]]
function PlayerManager.GetAllSessions()
    return activeSessions
end

--[[
    Gibt die Anzahl aktiver Spieler zurück
    @return: Anzahl
]]
function PlayerManager.GetPlayerCount()
    local count = 0
    for _ in pairs(activeSessions) do
        count = count + 1
    end
    return count
end

--[[
    Kickt einen Spieler mit Grund
    @param player: Der Spieler
    @param reason: Grund für den Kick
]]
function PlayerManager.KickPlayer(player, reason)
    reason = reason or "Du wurdest vom Server entfernt."
    
    debugPrint("Kicke Spieler: " .. player.Name .. " - Grund: " .. reason)
    
    -- Signal feuern
    PlayerManager.Signals.PlayerKicked:Fire(player, reason)
    
    -- Spieler kicken
    player:Kick(reason)
end

--[[
    Aktualisiert Session-Daten eines Spielers
    @param player: Der Spieler
    @param key: Der Key der aktualisiert werden soll
    @param value: Der neue Wert
]]
function PlayerManager.UpdateSession(player, key, value)
    local session = activeSessions[player.UserId]
    if session then
        session[key] = value
        session.LastActivity = os.time()
        PlayerManager.Signals.SessionUpdated:Fire(player, session)
    end
end

--[[
    Sendet eine Benachrichtigung an einen Spieler
    @param player: Der Spieler
    @param title: Titel der Benachrichtigung
    @param message: Nachricht
    @param notificationType: Typ (Info, Success, Warning, Error)
]]
function PlayerManager.SendNotification(player, title, message, notificationType)
    notificationType = notificationType or "Info"
    
    RemoteIndex.FireClient("UI_Notification", player, {
        Title = title,
        Message = message,
        Type = notificationType,
    })
end

--[[
    Sendet eine Fehlermeldung an einen Spieler
    @param player: Der Spieler
    @param message: Fehlermeldung
]]
function PlayerManager.SendError(player, message)
    RemoteIndex.FireClient("UI_Error", player, {
        Message = message,
    })
end

--[[
    Sendet ein Update an einen Spieler (generisch)
    @param player: Der Spieler
    @param updateType: Typ des Updates (Currency, Dungeon, Heroes, etc.)
    @param data: Die Daten
]]
function PlayerManager.SendUpdate(player, updateType, data)
    local remoteName = updateType .. "_Update"
    
    if RemoteIndex.Exists(remoteName) then
        RemoteIndex.FireClient(remoteName, player, data)
    else
        debugWarn("Unbekannter Update-Typ: " .. updateType)
    end
end

--[[
    Broadcast an alle Spieler
    @param remoteName: Name des RemoteEvents
    @param data: Die Daten
]]
function PlayerManager.BroadcastToAll(remoteName, data)
    if RemoteIndex.Exists(remoteName) and RemoteIndex.GetType(remoteName) == "Event" then
        RemoteIndex.FireAllClients(remoteName, data)
    else
        debugWarn("Ungültiges Remote für Broadcast: " .. remoteName)
    end
end

--[[
    Sendet an alle bereiten Spieler
    @param remoteName: Name des RemoteEvents
    @param data: Die Daten
]]
function PlayerManager.BroadcastToReady(remoteName, data)
    for userId, session in pairs(activeSessions) do
        if session.IsReady then
            local player = Players:GetPlayerByUserId(userId)
            if player then
                RemoteIndex.FireClient(remoteName, player, data)
            end
        end
    end
end

--[[
    Server-Shutdown Handler
]]
function PlayerManager.OnServerShutdown()
    if isShuttingDown then
        return
    end
    
    debugPrint("Server-Shutdown erkannt...")
    isShuttingDown = true
    
    -- DataManager Shutdown aufrufen
    if DataManager and DataManager.OnServerShutdown then
        DataManager.OnServerShutdown()
    end
    
    debugPrint("PlayerManager Shutdown abgeschlossen!")
end

--[[
    Gibt Session-Statistiken zurück
    @return: Statistik-Table
]]
function PlayerManager.GetStats()
    local totalPlayers = 0
    local readyPlayers = 0
    local totalSessionTime = 0
    local currentTime = os.time()
    
    for userId, session in pairs(activeSessions) do
        totalPlayers = totalPlayers + 1
        
        if session.IsReady then
            readyPlayers = readyPlayers + 1
        end
        
        totalSessionTime = totalSessionTime + (currentTime - session.JoinTime)
    end
    
    return {
        TotalPlayers = totalPlayers,
        ReadyPlayers = readyPlayers,
        AverageSessionTime = totalPlayers > 0 and (totalSessionTime / totalPlayers) or 0,
    }
end

return PlayerManager
