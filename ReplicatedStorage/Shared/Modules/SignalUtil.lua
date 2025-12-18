--[[
    SignalUtil.lua
    Leichtgewichtiges Event/Signal-System
    Pfad: ReplicatedStorage/Shared/Modules/SignalUtil
    
    Verwendung:
    - Interne Kommunikation zwischen Modulen
    - Unabhängig von BindableEvents
    - Automatisches Connection-Management
    
    Beispiel:
        local signal = SignalUtil.new()
        
        local connection = signal:Connect(function(data)
            print("Received:", data)
        end)
        
        signal:Fire("Hello!")
        
        connection:Disconnect()
]]

local SignalUtil = {}
SignalUtil.__index = SignalUtil

-------------------------------------------------
-- CONNECTION CLASS
-------------------------------------------------
local Connection = {}
Connection.__index = Connection

--[[
    Erstellt eine neue Connection
    @param signal: Das zugehörige Signal
    @param callback: Die Callback-Funktion
    @return: Connection-Objekt
]]
function Connection.new(signal, callback)
    local self = setmetatable({}, Connection)
    
    self._signal = signal
    self._callback = callback
    self._connected = true
    
    return self
end

--[[
    Trennt die Connection vom Signal
]]
function Connection:Disconnect()
    if not self._connected then
        return
    end
    
    self._connected = false
    
    -- Aus Signal-Liste entfernen
    local signal = self._signal
    if signal and signal._connections then
        for i, conn in ipairs(signal._connections) do
            if conn == self then
                table.remove(signal._connections, i)
                break
            end
        end
    end
    
    -- Referenzen aufräumen
    self._signal = nil
    self._callback = nil
end

--[[
    Prüft ob Connection noch aktiv ist
    @return: boolean
]]
function Connection:IsConnected()
    return self._connected
end

-------------------------------------------------
-- SIGNAL CLASS
-------------------------------------------------

--[[
    Erstellt ein neues Signal
    @return: Signal-Objekt
]]
function SignalUtil.new()
    local self = setmetatable({}, SignalUtil)
    
    self._connections = {}
    self._onceConnections = {}
    
    return self
end

--[[
    Verbindet eine Callback-Funktion mit dem Signal
    @param callback: Funktion die aufgerufen wird
    @return: Connection-Objekt
]]
function SignalUtil:Connect(callback)
    if type(callback) ~= "function" then
        error("[SignalUtil] Connect erwartet eine Funktion, bekommen: " .. type(callback))
    end
    
    local connection = Connection.new(self, callback)
    table.insert(self._connections, connection)
    
    return connection
end

--[[
    Verbindet eine Callback-Funktion die nur einmal ausgeführt wird
    @param callback: Funktion die einmal aufgerufen wird
    @return: Connection-Objekt
]]
function SignalUtil:Once(callback)
    if type(callback) ~= "function" then
        error("[SignalUtil] Once erwartet eine Funktion, bekommen: " .. type(callback))
    end
    
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        callback(...)
    end)
    
    return connection
end

--[[
    Feuert das Signal und ruft alle verbundenen Callbacks auf
    @param ...: Beliebige Argumente die an Callbacks übergeben werden
]]
function SignalUtil:Fire(...)
    -- Kopie der Connections erstellen (falls während Fire disconnected wird)
    local connections = table.clone(self._connections)
    
    for _, connection in ipairs(connections) do
        if connection._connected and connection._callback then
            -- Protected Call um Fehler in einem Callback abzufangen
            local success, err = pcall(connection._callback, ...)
            if not success then
                warn("[SignalUtil] Fehler in Signal-Callback: " .. tostring(err))
            end
        end
    end
end

--[[
    Feuert das Signal in einem separaten Thread (nicht-blockierend)
    @param ...: Beliebige Argumente die an Callbacks übergeben werden
]]
function SignalUtil:FireDeferred(...)
    local args = {...}
    task.defer(function()
        self:Fire(table.unpack(args))
    end)
end

--[[
    Wartet auf das nächste Fire des Signals
    @param timeout: Optionales Timeout in Sekunden
    @return: Die Argumente des Fire-Aufrufs oder nil bei Timeout
]]
function SignalUtil:Wait(timeout)
    local waitingThread = coroutine.running()
    local result = nil
    local timedOut = false
    
    -- Connection erstellen
    local connection
    connection = self:Once(function(...)
        result = {...}
        if coroutine.status(waitingThread) == "suspended" then
            task.spawn(waitingThread)
        end
    end)
    
    -- Timeout-Handler
    if timeout then
        task.delay(timeout, function()
            if connection:IsConnected() then
                timedOut = true
                connection:Disconnect()
                if coroutine.status(waitingThread) == "suspended" then
                    task.spawn(waitingThread)
                end
            end
        end)
    end
    
    -- Warten
    coroutine.yield()
    
    if timedOut then
        return nil
    end
    
    return table.unpack(result or {})
end

--[[
    Gibt die Anzahl aktiver Connections zurück
    @return: Anzahl der Connections
]]
function SignalUtil:GetConnectionCount()
    return #self._connections
end

--[[
    Trennt alle Connections und räumt auf
]]
function SignalUtil:DisconnectAll()
    -- Rückwärts iterieren um sicheres Entfernen zu gewährleisten
    for i = #self._connections, 1, -1 do
        local connection = self._connections[i]
        if connection then
            connection._connected = false
            connection._signal = nil
            connection._callback = nil
        end
    end
    
    self._connections = {}
end

--[[
    Zerstört das Signal komplett
]]
function SignalUtil:Destroy()
    self:DisconnectAll()
    setmetatable(self, nil)
end

-------------------------------------------------
-- UTILITY FUNKTIONEN
-------------------------------------------------

--[[
    Erstellt ein Signal das automatisch mit einem Instance zerstört wird
    @param instance: Roblox Instance (z.B. Player, Part)
    @return: Signal-Objekt
]]
function SignalUtil.createManaged(instance)
    local signal = SignalUtil.new()
    
    -- Bei Zerstörung der Instance auch Signal zerstören
    if instance and instance.Destroying then
        instance.Destroying:Connect(function()
            signal:Destroy()
        end)
    end
    
    return signal
end

--[[
    Wrapper um ein Roblox-Event als Signal zu nutzen
    @param rbxSignal: Ein Roblox RBXScriptSignal (z.B. Part.Touched)
    @return: Signal-Objekt das das Roblox-Event spiegelt
]]
function SignalUtil.fromRBXSignal(rbxSignal)
    local signal = SignalUtil.new()
    
    local rbxConnection = rbxSignal:Connect(function(...)
        signal:Fire(...)
    end)
    
    -- Original Destroy erweitern
    local originalDestroy = signal.Destroy
    signal.Destroy = function(self)
        rbxConnection:Disconnect()
        originalDestroy(self)
    end
    
    return signal
end

--[[
    Kombiniert mehrere Signals zu einem
    Feuert wenn EINES der Signals feuert
    @param ...: Mehrere Signal-Objekte
    @return: Neues kombiniertes Signal
]]
function SignalUtil.any(...)
    local signals = {...}
    local combined = SignalUtil.new()
    local connections = {}
    
    for i, signal in ipairs(signals) do
        local conn = signal:Connect(function(...)
            combined:Fire(i, ...)  -- Index des Signals + Argumente
        end)
        table.insert(connections, conn)
    end
    
    -- Cleanup erweitern
    local originalDestroy = combined.Destroy
    combined.Destroy = function(self)
        for _, conn in ipairs(connections) do
            conn:Disconnect()
        end
        originalDestroy(self)
    end
    
    return combined
end

--[[
    Erstellt ein Signal das nur feuert wenn eine Bedingung erfüllt ist
    @param sourceSignal: Das Quell-Signal
    @param predicate: Funktion die true/false zurückgibt
    @return: Gefiltertes Signal
]]
function SignalUtil.filter(sourceSignal, predicate)
    local filtered = SignalUtil.new()
    
    local conn = sourceSignal:Connect(function(...)
        if predicate(...) then
            filtered:Fire(...)
        end
    end)
    
    -- Cleanup erweitern
    local originalDestroy = filtered.Destroy
    filtered.Destroy = function(self)
        conn:Disconnect()
        originalDestroy(self)
    end
    
    return filtered
end

--[[
    Erstellt ein Signal das Argumente transformiert
    @param sourceSignal: Das Quell-Signal
    @param transformer: Funktion die Argumente transformiert
    @return: Transformiertes Signal
]]
function SignalUtil.map(sourceSignal, transformer)
    local mapped = SignalUtil.new()
    
    local conn = sourceSignal:Connect(function(...)
        local result = transformer(...)
        mapped:Fire(result)
    end)
    
    -- Cleanup erweitern
    local originalDestroy = mapped.Destroy
    mapped.Destroy = function(self)
        conn:Disconnect()
        originalDestroy(self)
    end
    
    return mapped
end

return SignalUtil
