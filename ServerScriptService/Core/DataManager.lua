--[[
    DataManager.lua
    Spieler-Datenverwaltung für "Dungeon Tycoon"
    Pfad: ServerScriptService/Server/Core/DataManager
    
    Features:
    - DataStore mit Retry-Logik
    - Session-Locking (verhindert Duplikation)
    - Auto-Save Intervall
    - Graceful Shutdown
    - Daten-Migration bei Version-Updates
    
    WICHTIG: Nur vom Server verwenden!
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared Modules laden
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")

local DataTemplate = require(ModulesPath:WaitForChild("DataTemplate"))
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))

local DataManager = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- DataStore Name
    DataStoreName = "DungeonTycoon_PlayerData_v1",
    
    -- Session Lock Key Prefix
    SessionLockPrefix = "DungeonTycoon_SessionLock_",
    
    -- Retry-Einstellungen
    MaxRetries = 5,
    RetryDelay = 2,             -- Sekunden zwischen Retries
    
    -- Auto-Save Intervall (aus GameConfig)
    AutoSaveInterval = GameConfig.Timing.AutoSaveInterval,
    
    -- Session Lock Timeout (Sekunden)
    SessionLockTimeout = 1800,  -- 30 Minuten
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- INTERNER STATE
-------------------------------------------------
local dataStore = nil
local sessionLockStore = nil
local playerDataCache = {}      -- { [UserId] = { Data = {...}, Loaded = bool, Changed = bool } }
local playerSaveJobs = {}       -- { [UserId] = true } - Verhindert doppeltes Speichern
local isShuttingDown = false

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
DataManager.Signals = {
    PlayerDataLoaded = SignalUtil.new(),    -- (player, data)
    PlayerDataSaved = SignalUtil.new(),     -- (player)
    PlayerDataChanged = SignalUtil.new(),   -- (player, key, newValue)
    DataLoadFailed = SignalUtil.new(),      -- (player, errorMessage)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[DataManager]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[DataManager]", ...)
end

--[[
    Führt eine DataStore-Operation mit Retry aus
    @param operation: Funktion die ausgeführt wird
    @param operationName: Name für Logging
    @return: success, result/error
]]
local function performWithRetry(operation, operationName)
    local attempts = 0
    local lastError = nil
    
    while attempts < CONFIG.MaxRetries do
        attempts = attempts + 1
        
        local success, result = pcall(operation)
        
        if success then
            return true, result
        else
            lastError = result
            debugWarn(operationName .. " fehlgeschlagen (Versuch " .. attempts .. "/" .. CONFIG.MaxRetries .. "): " .. tostring(result))
            
            if attempts < CONFIG.MaxRetries then
                task.wait(CONFIG.RetryDelay)
            end
        end
    end
    
    return false, lastError
end

--[[
    Generiert den Session-Lock Key für einen Spieler
    @param userId: UserId des Spielers
    @return: Session Lock Key
]]
local function getSessionLockKey(userId)
    return CONFIG.SessionLockPrefix .. tostring(userId)
end

--[[
    Prüft und setzt Session-Lock
    @param userId: UserId des Spielers
    @return: success, isLocked (von anderem Server)
]]
local function acquireSessionLock(userId)
    local lockKey = getSessionLockKey(userId)
    local jobId = game.JobId
    local currentTime = os.time()
    
    local success, result = performWithRetry(function()
        return sessionLockStore:UpdateAsync(lockKey, function(oldValue)
            -- Kein Lock oder Lock abgelaufen
            if oldValue == nil then
                return {
                    JobId = jobId,
                    Timestamp = currentTime,
                }
            end
            
            -- Lock von diesem Server
            if oldValue.JobId == jobId then
                return {
                    JobId = jobId,
                    Timestamp = currentTime,
                }
            end
            
            -- Lock abgelaufen?
            if currentTime - (oldValue.Timestamp or 0) > CONFIG.SessionLockTimeout then
                debugPrint("Session-Lock für " .. userId .. " war abgelaufen, übernehme...")
                return {
                    JobId = jobId,
                    Timestamp = currentTime,
                }
            end
            
            -- Lock von anderem Server, noch gültig
            return nil  -- Keine Änderung
        end)
    end, "AcquireSessionLock")
    
    if not success then
        return false, false
    end
    
    -- Prüfen ob wir den Lock bekommen haben
    if result and result.JobId == jobId then
        return true, false
    end
    
    return true, true  -- Locked von anderem Server
end

--[[
    Gibt Session-Lock frei
    @param userId: UserId des Spielers
]]
local function releaseSessionLock(userId)
    local lockKey = getSessionLockKey(userId)
    local jobId = game.JobId
    
    performWithRetry(function()
        return sessionLockStore:UpdateAsync(lockKey, function(oldValue)
            if oldValue and oldValue.JobId == jobId then
                return nil  -- Lock entfernen
            end
            return oldValue  -- Nicht unser Lock, nicht ändern
        end)
    end, "ReleaseSessionLock")
end

--[[
    Aktualisiert Session-Lock Timestamp (Heartbeat)
    @param userId: UserId des Spielers
]]
local function refreshSessionLock(userId)
    local lockKey = getSessionLockKey(userId)
    local jobId = game.JobId
    local currentTime = os.time()
    
    sessionLockStore:UpdateAsync(lockKey, function(oldValue)
        if oldValue and oldValue.JobId == jobId then
            return {
                JobId = jobId,
                Timestamp = currentTime,
            }
        end
        return oldValue
    end)
end

-------------------------------------------------
-- LADEN & SPEICHERN
-------------------------------------------------

--[[
    Lädt Spielerdaten aus DataStore
    @param player: Der Spieler
    @return: success, data/error
]]
local function loadPlayerData(player)
    local userId = player.UserId
    local dataKey = "Player_" .. tostring(userId)
    
    debugPrint("Lade Daten für " .. player.Name .. " (ID: " .. userId .. ")")
    
    -- Session-Lock prüfen
    local lockSuccess, isLocked = acquireSessionLock(userId)
    
    if not lockSuccess then
        return false, "Session-Lock konnte nicht geprüft werden"
    end
    
    if isLocked then
        return false, "Daten sind auf einem anderen Server aktiv. Bitte warte einen Moment."
    end
    
    -- Daten laden
    local success, result = performWithRetry(function()
        return dataStore:GetAsync(dataKey)
    end, "LoadPlayerData")
    
    if not success then
        releaseSessionLock(userId)
        return false, "Daten konnten nicht geladen werden: " .. tostring(result)
    end
    
    local playerData
    
    if result == nil then
        -- Neuer Spieler
        debugPrint("Neuer Spieler, erstelle Daten...")
        playerData = DataTemplate.GetNewPlayerData()
    else
        -- Bestehender Spieler
        playerData = result
        
        -- Migration prüfen
        if playerData.Version < DataTemplate.Version then
            debugPrint("Migriere Daten von v" .. playerData.Version .. " auf v" .. DataTemplate.Version)
            playerData = DataTemplate.Migrate(playerData)
        end
        
        -- Validierung (fehlende Felder auffüllen)
        playerData = DataTemplate.Validate(playerData)
    end
    
    -- LastLogin aktualisieren
    playerData.LastLogin = os.time()
    
    return true, playerData
end

--[[
    Speichert Spielerdaten in DataStore
    @param userId: UserId des Spielers
    @param data: Die zu speichernden Daten
    @param isLeaving: Ob der Spieler gerade verlässt
    @return: success, error
]]
local function savePlayerData(userId, data, isLeaving)
    -- Verhindere doppeltes Speichern
    if playerSaveJobs[userId] then
        debugPrint("Speichern für " .. userId .. " bereits aktiv, überspringe...")
        return true, nil
    end
    
    playerSaveJobs[userId] = true
    
    local dataKey = "Player_" .. tostring(userId)
    
    debugPrint("Speichere Daten für UserId: " .. userId)
    
    local success, result = performWithRetry(function()
        return dataStore:SetAsync(dataKey, data)
    end, "SavePlayerData")
    
    playerSaveJobs[userId] = nil
    
    if not success then
        debugWarn("Speichern fehlgeschlagen für " .. userId .. ": " .. tostring(result))
        return false, result
    end
    
    -- Session-Lock freigeben wenn Spieler verlässt
    if isLeaving then
        releaseSessionLock(userId)
    end
    
    debugPrint("Daten gespeichert für UserId: " .. userId)
    return true, nil
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

--[[
    Initialisiert den DataManager
    Muss beim Server-Start aufgerufen werden!
]]
function DataManager.Initialize()
    debugPrint("Initialisiere DataManager...")
    
    -- DataStores erstellen
    local success, err = pcall(function()
        dataStore = DataStoreService:GetDataStore(CONFIG.DataStoreName)
        sessionLockStore = DataStoreService:GetDataStore(CONFIG.DataStoreName .. "_Locks")
    end)
    
    if not success then
        debugWarn("DataStore konnte nicht erstellt werden: " .. tostring(err))
        -- Im Studio ohne API-Zugriff weitermachen
        if RunService:IsStudio() then
            debugPrint("Studio-Modus: Verwende Mock-DataStore")
        end
    end
    
    -- Auto-Save Loop starten
    task.spawn(function()
        while true do
            task.wait(CONFIG.AutoSaveInterval)
            
            if isShuttingDown then
                break
            end
            
            DataManager.SaveAllPlayers()
        end
    end)
    
    -- Session-Lock Refresh Loop
    task.spawn(function()
        while true do
            task.wait(60)  -- Jede Minute
            
            if isShuttingDown then
                break
            end
            
            for userId, cacheEntry in pairs(playerDataCache) do
                if cacheEntry.Loaded then
                    task.spawn(function()
                        refreshSessionLock(userId)
                    end)
                end
            end
        end
    end)
    
    debugPrint("DataManager initialisiert!")
end

--[[
    Lädt Daten für einen Spieler
    @param player: Der Spieler
]]
function DataManager.LoadPlayer(player)
    local userId = player.UserId
    
    -- Bereits geladen?
    if playerDataCache[userId] and playerDataCache[userId].Loaded then
        debugWarn("Daten für " .. player.Name .. " bereits geladen!")
        return
    end
    
    -- Cache-Entry erstellen
    playerDataCache[userId] = {
        Data = nil,
        Loaded = false,
        Changed = false,
    }
    
    -- Daten laden
    local success, result = loadPlayerData(player)
    
    -- Spieler noch da?
    if not player or not player.Parent then
        debugPrint("Spieler " .. userId .. " hat während des Ladens verlassen")
        playerDataCache[userId] = nil
        return
    end
    
    if success then
        playerDataCache[userId].Data = result
        playerDataCache[userId].Loaded = true
        
        debugPrint("Daten geladen für " .. player.Name)
        DataManager.Signals.PlayerDataLoaded:Fire(player, result)
    else
        debugWarn("Laden fehlgeschlagen für " .. player.Name .. ": " .. tostring(result))
        playerDataCache[userId] = nil
        DataManager.Signals.DataLoadFailed:Fire(player, result)
        
        -- Spieler kicken bei kritischem Fehler
        player:Kick("Deine Daten konnten nicht geladen werden. Bitte versuche es erneut.\n\nFehler: " .. tostring(result))
    end
end

--[[
    Speichert Daten für einen Spieler
    @param player: Der Spieler (oder UserId als number)
    @param isLeaving: Ob der Spieler verlässt (optional)
    @return: success
]]
function DataManager.SavePlayer(player, isLeaving)
    local userId = type(player) == "number" and player or player.UserId
    local cacheEntry = playerDataCache[userId]
    
    if not cacheEntry or not cacheEntry.Loaded then
        debugWarn("Keine Daten zum Speichern für UserId: " .. userId)
        return false
    end
    
    local success, err = savePlayerData(userId, cacheEntry.Data, isLeaving)
    
    if success then
        cacheEntry.Changed = false
        DataManager.Signals.PlayerDataSaved:Fire(player)
    end
    
    return success
end

--[[
    Speichert alle aktiven Spieler
]]
function DataManager.SaveAllPlayers()
    debugPrint("Auto-Save für alle Spieler...")
    
    for userId, cacheEntry in pairs(playerDataCache) do
        if cacheEntry.Loaded then
            task.spawn(function()
                DataManager.SavePlayer(userId, false)
            end)
        end
    end
end

--[[
    Cleanup wenn Spieler verlässt
    @param player: Der Spieler
]]
function DataManager.UnloadPlayer(player)
    local userId = player.UserId
    local cacheEntry = playerDataCache[userId]
    
    if not cacheEntry then
        return
    end
    
    if cacheEntry.Loaded then
        -- TotalPlayTime aktualisieren
        local sessionTime = os.time() - (cacheEntry.Data.LastLogin or os.time())
        cacheEntry.Data.TotalPlayTime = (cacheEntry.Data.TotalPlayTime or 0) + sessionTime
        
        -- Speichern
        DataManager.SavePlayer(userId, true)
    end
    
    -- Cache aufräumen
    playerDataCache[userId] = nil
    debugPrint("Spieler entladen: " .. player.Name)
end

--[[
    Gibt die Daten eines Spielers zurück
    @param player: Der Spieler
    @return: Daten-Tabelle oder nil
]]
function DataManager.GetData(player)
    local userId = player.UserId
    local cacheEntry = playerDataCache[userId]
    
    if cacheEntry and cacheEntry.Loaded then
        return cacheEntry.Data
    end
    
    return nil
end

--[[
    Setzt einen Wert in den Spielerdaten
    @param player: Der Spieler
    @param path: Pfad zum Wert (z.B. "Currency.Gold" oder {"Currency", "Gold"})
    @param value: Der neue Wert
    @return: success
]]
function DataManager.SetValue(player, path, value)
    local data = DataManager.GetData(player)
    if not data then
        return false
    end
    
    -- Pfad parsen
    local keys = type(path) == "string" and string.split(path, ".") or path
    
    -- Zum letzten Key navigieren
    local current = data
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(current[key]) ~= "table" then
            debugWarn("Ungültiger Pfad: " .. table.concat(keys, "."))
            return false
        end
        current = current[key]
    end
    
    -- Wert setzen
    local finalKey = keys[#keys]
    local oldValue = current[finalKey]
    current[finalKey] = value
    
    -- Als geändert markieren
    local userId = player.UserId
    if playerDataCache[userId] then
        playerDataCache[userId].Changed = true
    end
    
    -- Signal feuern
    DataManager.Signals.PlayerDataChanged:Fire(player, path, value)
    
    debugPrint("Wert geändert für " .. player.Name .. ": " .. table.concat(keys, ".") .. " = " .. tostring(value))
    return true
end

--[[
    Holt einen Wert aus den Spielerdaten
    @param player: Der Spieler
    @param path: Pfad zum Wert
    @param default: Standardwert wenn nicht gefunden
    @return: Der Wert oder default
]]
function DataManager.GetValue(player, path, default)
    local data = DataManager.GetData(player)
    if not data then
        return default
    end
    
    local keys = type(path) == "string" and string.split(path, ".") or path
    
    local current = data
    for _, key in ipairs(keys) do
        if type(current) ~= "table" then
            return default
        end
        current = current[key]
        if current == nil then
            return default
        end
    end
    
    return current
end

--[[
    Inkrementiert einen numerischen Wert
    @param player: Der Spieler
    @param path: Pfad zum Wert
    @param amount: Betrag (kann negativ sein)
    @return: success, newValue
]]
function DataManager.IncrementValue(player, path, amount)
    local currentValue = DataManager.GetValue(player, path, 0)
    
    if type(currentValue) ~= "number" then
        debugWarn("IncrementValue: Wert ist keine Zahl: " .. path)
        return false, nil
    end
    
    local newValue = currentValue + amount
    local success = DataManager.SetValue(player, path, newValue)
    
    return success, newValue
end

--[[
    Prüft ob Spielerdaten geladen sind
    @param player: Der Spieler
    @return: boolean
]]
function DataManager.IsLoaded(player)
    local userId = player.UserId
    local cacheEntry = playerDataCache[userId]
    return cacheEntry ~= nil and cacheEntry.Loaded
end

--[[
    Server-Shutdown Handler
]]
function DataManager.OnServerShutdown()
    debugPrint("Server-Shutdown erkannt, speichere alle Daten...")
    isShuttingDown = true
    
    local saveThreads = {}
    
    for userId, cacheEntry in pairs(playerDataCache) do
        if cacheEntry.Loaded then
            local thread = task.spawn(function()
                savePlayerData(userId, cacheEntry.Data, true)
            end)
            table.insert(saveThreads, thread)
        end
    end
    
    -- Warten bis alle gespeichert sind (max 25 Sekunden)
    local startTime = os.clock()
    while #saveThreads > 0 and (os.clock() - startTime) < 25 do
        task.wait(0.1)
    end
    
    debugPrint("Shutdown-Save abgeschlossen!")
end

return DataManager
