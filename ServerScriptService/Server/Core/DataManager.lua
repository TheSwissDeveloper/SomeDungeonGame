--[[
    DataManager.lua
    Zentrales Daten-Management für "Dungeon Tycoon"
    Pfad: ServerScriptService/Server/Core/DataManager
    
    Verantwortlich für:
    - Spielerdaten laden/speichern (DataStoreService)
    - Session-Locking (verhindert Daten-Duplikation)
    - Auto-Save
    - Daten-Migration bei Schema-Änderungen
    
    WICHTIG: 
    - Nur vom Server verwenden!
    - Alle Daten-Änderungen über diesen Manager!
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Auf Shared-Module warten
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")

-- Module laden
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local DataTemplate = require(ModulesPath:WaitForChild("DataTemplate"))
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
    MaxLoadRetries = 5,
    RetryDelay = 2,
    
    -- Auto-Save Intervall (Sekunden)
    AutoSaveInterval = GameConfig.Timing.AutoSaveInterval,  -- 120
    
    -- Session Lock Timeout (Sekunden)
    SessionLockTimeout = 1800,  -- 30 Minuten
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
    
    -- Studio-Modus (keine echten DataStores)
    UseStudioMock = RunService:IsStudio() and false,  -- Auf true setzen für Mock-Daten
}

-------------------------------------------------
-- INTERNER STATE
-------------------------------------------------
local playerDataStore = nil
local sessionLockStore = nil

local playerData = {}           -- { [UserId] = data }
local playerSessions = {}       -- { [UserId] = { SessionId, LastSave, IsLoaded } }
local pendingSaves = {}         -- { [UserId] = true }

local isInitialized = false
local isShuttingDown = false
local autoSaveConnection = nil

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
DataManager.Signals = {
    PlayerDataLoaded = SignalUtil.new(),    -- (player, data)
    PlayerDataSaved = SignalUtil.new(),     -- (player)
    DataLoadFailed = SignalUtil.new(),      -- (player, errorMessage)
    DataSaveFailed = SignalUtil.new(),      -- (player, errorMessage)
    DataChanged = SignalUtil.new(),         -- (player, path, newValue, oldValue)
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

-- Error ausgeben
local function debugError(...)
    warn("[DataManager] ERROR:", ...)
end

--[[
    Generiert eine einzigartige Session-ID
    @return: Session-ID String
]]
local function generateSessionId()
    return game.JobId .. "_" .. os.time() .. "_" .. math.random(100000, 999999)
end

--[[
    Holt einen Wert aus verschachteltem Table per Pfad
    @param tbl: Das Table
    @param path: Pfad als String (z.B. "Currency.Gold")
    @return: Wert oder nil
]]
local function getNestedValue(tbl, path)
    local keys = string.split(path, ".")
    local current = tbl
    
    for _, key in ipairs(keys) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    
    return current
end

--[[
    Setzt einen Wert in verschachteltem Table per Pfad
    @param tbl: Das Table
    @param path: Pfad als String (z.B. "Currency.Gold")
    @param value: Der neue Wert
    @return: success
]]
local function setNestedValue(tbl, path, value)
    local keys = string.split(path, ".")
    local current = tbl
    
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    
    current[keys[#keys]] = value
    return true
end

--[[
    Prüft und erwirbt Session-Lock
    @param userId: User-ID des Spielers
    @param sessionId: Neue Session-ID
    @return: success, existingSessionId
]]
local function acquireSessionLock(userId, sessionId)
    if CONFIG.UseStudioMock then
        return true, nil
    end
    
    local key = CONFIG.SessionLockPrefix .. tostring(userId)
    local success, result = pcall(function()
        return sessionLockStore:UpdateAsync(key, function(oldData)
            local currentTime = os.time()
            
            -- Kein Lock vorhanden oder abgelaufen
            if not oldData or (currentTime - (oldData.Timestamp or 0)) > CONFIG.SessionLockTimeout then
                return {
                    SessionId = sessionId,
                    Timestamp = currentTime,
                    JobId = game.JobId,
                }
            end
            
            -- Lock gehört uns bereits (Re-Join im gleichen Server)
            if oldData.JobId == game.JobId then
                return {
                    SessionId = sessionId,
                    Timestamp = currentTime,
                    JobId = game.JobId,
                }
            end
            
            -- Lock gehört anderem Server
            return nil  -- Keine Änderung
        end)
    end)
    
    if not success then
        debugError("Session-Lock Fehler für " .. userId .. ": " .. tostring(result))
        return false, nil
    end
    
    if result and result.SessionId == sessionId then
        return true, nil
    else
        return false, result and result.SessionId or "unknown"
    end
end

--[[
    Gibt Session-Lock frei
    @param userId: User-ID des Spielers
]]
local function releaseSessionLock(userId)
    if CONFIG.UseStudioMock then
        return
    end
    
    local key = CONFIG.SessionLockPrefix .. tostring(userId)
    local success, err = pcall(function()
        sessionLockStore:RemoveAsync(key)
    end)
    
    if not success then
        debugWarn("Session-Lock Freigabe fehlgeschlagen für " .. userId .. ": " .. tostring(err))
    end
end

--[[
    Lädt Rohdaten aus DataStore
    @param userId: User-ID des Spielers
    @return: data oder nil, errorMessage
]]
local function loadRawData(userId)
    if CONFIG.UseStudioMock then
        debugPrint("Studio-Modus: Erstelle neue Daten für " .. userId)
        return nil, nil  -- Neue Daten werden erstellt
    end
    
    local key = "Player_" .. tostring(userId)
    local success, result = pcall(function()
        return playerDataStore:GetAsync(key)
    end)
    
    if not success then
        return nil, tostring(result)
    end
    
    return result, nil
end

--[[
    Speichert Daten in DataStore
    @param userId: User-ID des Spielers
    @param data: Die zu speichernden Daten
    @return: success, errorMessage
]]
local function saveRawData(userId, data)
    if CONFIG.UseStudioMock then
        debugPrint("Studio-Modus: Speichern simuliert für " .. userId)
        return true, nil
    end
    
    local key = "Player_" .. tostring(userId)
    local success, err = pcall(function()
        playerDataStore:SetAsync(key, data)
    end)
    
    if not success then
        return false, tostring(err)
    end
    
    return true, nil
end

--[[
    Verarbeitet und validiert geladene Daten
    @param rawData: Rohdaten aus DataStore
    @return: Validierte Daten
]]
local function processLoadedData(rawData)
    local data
    
    if rawData then
        -- Bestehende Daten
        data = rawData
        
        -- Migration prüfen
        if data.Version ~= DataTemplate.Version then
            debugPrint("Migriere Daten von v" .. (data.Version or 0) .. " auf v" .. DataTemplate.Version)
            data = DataTemplate.Migrate(data)
        end
        
        -- Validierung (fehlende Felder hinzufügen)
        data = DataTemplate.Validate(data)
    else
        -- Neue Spielerdaten
        data = DataTemplate.GetNewPlayerData()
        debugPrint("Neue Spielerdaten erstellt")
    end
    
    return data
end

--[[
    Speichert Daten eines Spielers
    @param player: Der Spieler
    @param force: Erzwinge Speichern (auch wenn kürzlich gespeichert)
    @return: success
]]
local function savePlayerData(player, force)
    local userId = player.UserId
    local session = playerSessions[userId]
    local data = playerData[userId]
    
    if not session or not data then
        return false
    end
    
    -- Bereits Speicherung in Bearbeitung?
    if pendingSaves[userId] and not force then
        return false
    end
    
    pendingSaves[userId] = true
    
    -- Letzte Login-Zeit aktualisieren
    data.LastLogin = os.time()
    
    -- Spielzeit aktualisieren
    local sessionTime = os.time() - (session.SessionStart or os.time())
    data.TotalPlayTime = (data.TotalPlayTime or 0) + sessionTime
    session.SessionStart = os.time()  -- Reset für nächste Berechnung
    
    -- Speichern
    local success, err = saveRawData(userId, data)
    
    pendingSaves[userId] = nil
    
    if success then
        session.LastSave = os.time()
        DataManager.Signals.PlayerDataSaved:Fire(player)
        debugPrint("Daten gespeichert für " .. player.Name)
        return true
    else
        debugError("Speichern fehlgeschlagen für " .. player.Name .. ": " .. tostring(err))
        DataManager.Signals.DataSaveFailed:Fire(player, err)
        return false
    end
end

--[[
    Auto-Save Loop
]]
local function startAutoSave()
    if autoSaveConnection then
        return
    end
    
    task.spawn(function()
        while not isShuttingDown do
            task.wait(CONFIG.AutoSaveInterval)
            
            if isShuttingDown then
                break
            end
            
            debugPrint("Auto-Save gestartet...")
            
            for userId, session in pairs(playerSessions) do
                if session.IsLoaded then
                    local player = Players:GetPlayerByUserId(userId)
                    if player then
                        task.spawn(function()
                            savePlayerData(player, false)
                        end)
                    end
                end
            end
            
            debugPrint("Auto-Save abgeschlossen")
        end
    end)
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den DataManager
]]
function DataManager.Initialize()
    if isInitialized then
        debugWarn("DataManager bereits initialisiert!")
        return
    end
    
    debugPrint("Initialisiere DataManager...")
    
    -- DataStores erstellen
    if not CONFIG.UseStudioMock then
        local success, err = pcall(function()
            playerDataStore = DataStoreService:GetDataStore(CONFIG.DataStoreName)
            sessionLockStore = DataStoreService:GetDataStore(CONFIG.DataStoreName .. "_Sessions")
        end)
        
        if not success then
            debugError("DataStore-Initialisierung fehlgeschlagen: " .. tostring(err))
            -- Fallback auf Mock-Modus
            CONFIG.UseStudioMock = true
            debugWarn("Fallback auf Mock-Modus aktiviert")
        end
    end
    
    -- Auto-Save starten
    startAutoSave()
    
    isInitialized = true
    debugPrint("DataManager initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - SPIELER LADEN/ENTLADEN
-------------------------------------------------

--[[
    Lädt Daten für einen Spieler
    @param player: Der Spieler
]]
function DataManager.LoadPlayer(player)
    local userId = player.UserId
    
    -- Bereits geladen?
    if playerSessions[userId] and playerSessions[userId].IsLoaded then
        debugWarn("Daten für " .. player.Name .. " bereits geladen")
        return
    end
    
    debugPrint("Lade Daten für " .. player.Name .. " (ID: " .. userId .. ")")
    
    -- Session erstellen
    local sessionId = generateSessionId()
    playerSessions[userId] = {
        SessionId = sessionId,
        SessionStart = os.time(),
        LastSave = 0,
        IsLoaded = false,
    }
    
    -- Session-Lock erwerben (mit Retries)
    local lockAcquired = false
    local lockError = nil
    
    for attempt = 1, CONFIG.MaxLoadRetries do
        -- Spieler noch da?
        if not player or not player.Parent then
            debugPrint("Spieler " .. userId .. " hat während Laden verlassen")
            playerSessions[userId] = nil
            return
        end
        
        local success, existingSession = acquireSessionLock(userId, sessionId)
        
        if success then
            lockAcquired = true
            break
        else
            lockError = "Session-Lock von anderem Server gehalten"
            debugWarn("Session-Lock Versuch " .. attempt .. " fehlgeschlagen für " .. player.Name)
            
            if attempt < CONFIG.MaxLoadRetries then
                task.wait(CONFIG.RetryDelay)
            end
        end
    end
    
    if not lockAcquired then
        debugError("Session-Lock konnte nicht erworben werden für " .. player.Name)
        playerSessions[userId] = nil
        DataManager.Signals.DataLoadFailed:Fire(player, lockError or "Session-Lock fehlgeschlagen")
        
        -- Spieler kicken (Daten-Schutz)
        player:Kick("Deine Daten werden noch von einer anderen Sitzung verwendet. Bitte versuche es in einigen Minuten erneut.")
        return
    end
    
    -- Daten laden (mit Retries)
    local rawData = nil
    local loadError = nil
    
    for attempt = 1, CONFIG.MaxLoadRetries do
        -- Spieler noch da?
        if not player or not player.Parent then
            debugPrint("Spieler " .. userId .. " hat während Laden verlassen")
            releaseSessionLock(userId)
            playerSessions[userId] = nil
            return
        end
        
        local data, err = loadRawData(userId)
        
        if err then
            loadError = err
            debugWarn("Laden Versuch " .. attempt .. " fehlgeschlagen für " .. player.Name .. ": " .. err)
            
            if attempt < CONFIG.MaxLoadRetries then
                task.wait(CONFIG.RetryDelay)
            end
        else
            rawData = data
            loadError = nil
            break
        end
    end
    
    if loadError then
        debugError("Daten-Laden endgültig fehlgeschlagen für " .. player.Name)
        releaseSessionLock(userId)
        playerSessions[userId] = nil
        DataManager.Signals.DataLoadFailed:Fire(player, loadError)
        
        player:Kick("Deine Daten konnten nicht geladen werden. Bitte versuche es später erneut.")
        return
    end
    
    -- Spieler noch da? (finale Prüfung)
    if not player or not player.Parent then
        debugPrint("Spieler " .. userId .. " hat während Laden verlassen")
        releaseSessionLock(userId)
        playerSessions[userId] = nil
        return
    end
    
    -- Daten verarbeiten
    local processedData = processLoadedData(rawData)
    
    -- Daten cachen
    playerData[userId] = processedData
    playerSessions[userId].IsLoaded = true
    playerSessions[userId].SessionStart = os.time()
    
    debugPrint("Daten erfolgreich geladen für " .. player.Name)
    
    -- Signal feuern
    DataManager.Signals.PlayerDataLoaded:Fire(player, processedData)
end

--[[
    Entlädt Daten für einen Spieler (beim Verlassen)
    @param player: Der Spieler
]]
function DataManager.UnloadPlayer(player)
    local userId = player.UserId
    local session = playerSessions[userId]
    
    if not session then
        debugPrint("Keine Session für " .. player.Name .. " zum Entladen")
        return
    end
    
    debugPrint("Entlade Daten für " .. player.Name)
    
    -- Daten speichern
    if session.IsLoaded and playerData[userId] then
        savePlayerData(player, true)
    end
    
    -- Session-Lock freigeben
    releaseSessionLock(userId)
    
    -- Cleanup
    playerData[userId] = nil
    playerSessions[userId] = nil
    pendingSaves[userId] = nil
    
    debugPrint("Daten entladen für " .. player.Name)
end

-------------------------------------------------
-- PUBLIC API - DATEN-ZUGRIFF
-------------------------------------------------

--[[
    Gibt die Daten eines Spielers zurück
    @param player: Der Spieler
    @return: Spielerdaten oder nil
]]
function DataManager.GetData(player)
    return playerData[player.UserId]
end

--[[
    Gibt einen spezifischen Wert zurück
    @param player: Der Spieler
    @param path: Pfad zum Wert (z.B. "Currency.Gold")
    @return: Wert oder nil
]]
function DataManager.GetValue(player, path)
    local data = playerData[player.UserId]
    if not data then return nil end
    
    return getNestedValue(data, path)
end

--[[
    Setzt einen spezifischen Wert
    @param player: Der Spieler
    @param path: Pfad zum Wert (z.B. "Currency.Gold")
    @param value: Der neue Wert
    @return: success
]]
function DataManager.SetValue(player, path, value)
    local data = playerData[player.UserId]
    if not data then 
        debugWarn("SetValue fehlgeschlagen - keine Daten für " .. player.Name)
        return false 
    end
    
    local oldValue = getNestedValue(data, path)
    local success = setNestedValue(data, path, value)
    
    if success then
        DataManager.Signals.DataChanged:Fire(player, path, value, oldValue)
    end
    
    return success
end

--[[
    Erhöht einen numerischen Wert
    @param player: Der Spieler
    @param path: Pfad zum Wert
    @param amount: Erhöhungsbetrag (kann negativ sein)
    @return: Neuer Wert oder nil
]]
function DataManager.IncrementValue(player, path, amount)
    local data = playerData[player.UserId]
    if not data then return nil end
    
    local currentValue = getNestedValue(data, path) or 0
    
    if type(currentValue) ~= "number" then
        debugWarn("IncrementValue: Wert ist keine Zahl - " .. path)
        return nil
    end
    
    local newValue = currentValue + amount
    setNestedValue(data, path, newValue)
    
    DataManager.Signals.DataChanged:Fire(player, path, newValue, currentValue)
    
    return newValue
end

--[[
    Fügt einen Wert zu einem Array hinzu
    @param player: Der Spieler
    @param path: Pfad zum Array
    @param value: Der hinzuzufügende Wert
    @return: success
]]
function DataManager.ArrayInsert(player, path, value)
    local data = playerData[player.UserId]
    if not data then return false end
    
    local array = getNestedValue(data, path)
    
    if type(array) ~= "table" then
        setNestedValue(data, path, {})
        array = getNestedValue(data, path)
    end
    
    table.insert(array, value)
    
    DataManager.Signals.DataChanged:Fire(player, path, array, nil)
    
    return true
end

--[[
    Entfernt einen Wert aus einem Array
    @param player: Der Spieler
    @param path: Pfad zum Array
    @param index: Index des zu entfernenden Elements
    @return: Entfernter Wert oder nil
]]
function DataManager.ArrayRemove(player, path, index)
    local data = playerData[player.UserId]
    if not data then return nil end
    
    local array = getNestedValue(data, path)
    
    if type(array) ~= "table" then
        return nil
    end
    
    local removed = table.remove(array, index)
    
    if removed then
        DataManager.Signals.DataChanged:Fire(player, path, array, nil)
    end
    
    return removed
end

-------------------------------------------------
-- PUBLIC API - SPEICHERN
-------------------------------------------------

--[[
    Erzwingt Speichern für einen Spieler
    @param player: Der Spieler
    @return: success
]]
function DataManager.SavePlayer(player)
    return savePlayerData(player, true)
end

--[[
    Speichert alle Spieler
]]
function DataManager.SaveAllPlayers()
    debugPrint("Speichere alle Spieler...")
    
    for userId, session in pairs(playerSessions) do
        if session.IsLoaded then
            local player = Players:GetPlayerByUserId(userId)
            if player then
                task.spawn(function()
                    savePlayerData(player, true)
                end)
            end
        end
    end
end

-------------------------------------------------
-- PUBLIC API - SHUTDOWN
-------------------------------------------------

--[[
    Graceful Shutdown Handler
]]
function DataManager.OnServerShutdown()
    if isShuttingDown then
        return
    end
    
    debugPrint("Server-Shutdown erkannt - speichere alle Daten...")
    isShuttingDown = true
    
    -- Alle Spieler speichern und Locks freigeben
    local saveThreads = {}
    
    for userId, session in pairs(playerSessions) do
        if session.IsLoaded and playerData[userId] then
            local player = Players:GetPlayerByUserId(userId)
            
            table.insert(saveThreads, task.spawn(function()
                if player then
                    -- Daten speichern
                    local data = playerData[userId]
                    data.LastLogin = os.time()
                    
                    local sessionTime = os.time() - (session.SessionStart or os.time())
                    data.TotalPlayTime = (data.TotalPlayTime or 0) + sessionTime
                    
                    saveRawData(userId, data)
                end
                
                -- Lock freigeben
                releaseSessionLock(userId)
            end))
        end
    end
    
    -- Warten auf alle Speichervorgänge (max 25 Sekunden für BindToClose)
    local startTime = os.clock()
    while os.clock() - startTime < 25 do
        local allDone = true
        for _, thread in ipairs(saveThreads) do
            if coroutine.status(thread) ~= "dead" then
                allDone = false
                break
            end
        end
        
        if allDone then
            break
        end
        
        task.wait(0.1)
    end
    
    debugPrint("Shutdown-Speicherung abgeschlossen!")
end

-------------------------------------------------
-- PUBLIC API - HILFSFUNKTIONEN
-------------------------------------------------

--[[
    Prüft ob Daten für einen Spieler geladen sind
    @param player: Der Spieler
    @return: boolean
]]
function DataManager.IsDataLoaded(player)
    local session = playerSessions[player.UserId]
    return session ~= nil and session.IsLoaded
end

--[[
    Gibt Session-Info für einen Spieler zurück
    @param player: Der Spieler
    @return: Session-Info oder nil
]]
function DataManager.GetSessionInfo(player)
    return playerSessions[player.UserId]
end

--[[
    Gibt Statistiken über geladene Daten zurück
    @return: Stats-Table
]]
function DataManager.GetStats()
    local loadedCount = 0
    local pendingSaveCount = 0
    
    for userId, session in pairs(playerSessions) do
        if session.IsLoaded then
            loadedCount = loadedCount + 1
        end
    end
    
    for _ in pairs(pendingSaves) do
        pendingSaveCount = pendingSaveCount + 1
    end
    
    return {
        LoadedPlayers = loadedCount,
        PendingSaves = pendingSaveCount,
        IsShuttingDown = isShuttingDown,
        AutoSaveInterval = CONFIG.AutoSaveInterval,
    }
end

--[[
    Setzt Daten zurück (NUR FÜR DEBUG/ADMIN)
    @param player: Der Spieler
    @return: success
]]
function DataManager.ResetData(player)
    if not CONFIG.Debug then
        debugWarn("ResetData nur im Debug-Modus verfügbar!")
        return false
    end
    
    local userId = player.UserId
    
    if not playerSessions[userId] then
        return false
    end
    
    -- Neue Daten erstellen
    local newData = DataTemplate.GetNewPlayerData()
    playerData[userId] = newData
    
    debugPrint("Daten zurückgesetzt für " .. player.Name)
    
    -- Signal feuern
    DataManager.Signals.PlayerDataLoaded:Fire(player, newData)
    
    return true
end

return DataManager
