--[[
    DungeonSystem.lua
    Zentrales System für Dungeon-Operationen
    Pfad: ServerScriptService/Server/Systems/DungeonSystem
    
    Verantwortlich für:
    - Raum-Management (Hinzufügen, Entfernen, Anordnen)
    - Fallen/Monster-Platzierung
    - Dungeon-Stats-Berechnung
    - XP und Level-Verwaltung
    
    WICHTIG: Nutzt CurrencyService für Transaktionen!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Auf Shared-Module warten
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")
local RemotesPath = SharedPath:WaitForChild("Remotes")

-- Module laden
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local DataTemplate = require(ModulesPath:WaitForChild("DataTemplate"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Service/Manager-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil
local CurrencyService = nil

local DungeonSystem = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- XP-Belohnungen
    XPPerRoomAdded = 50,
    XPPerRoomBaseMultiplier = 10,   -- + roomCount * 10
    XPPerTrapPlaced = 15,
    XPPerMonsterPlaced = 20,
    XPPerUpgrade = 25,
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
DungeonSystem.Signals = {
    RoomAdded = SignalUtil.new(),           -- (player, roomIndex, roomData)
    RoomRemoved = SignalUtil.new(),         -- (player, roomIndex)
    RoomUpgraded = SignalUtil.new(),        -- (player, roomIndex, newLevel)
    
    TrapPlaced = SignalUtil.new(),          -- (player, roomIndex, slotIndex, trapData)
    TrapRemoved = SignalUtil.new(),         -- (player, roomIndex, slotIndex)
    
    MonsterPlaced = SignalUtil.new(),       -- (player, roomIndex, slotIndex, monsterData)
    MonsterRemoved = SignalUtil.new(),      -- (player, roomIndex, slotIndex)
    
    DungeonLevelUp = SignalUtil.new(),      -- (player, newLevel, oldLevel)
    DungeonRenamed = SignalUtil.new(),      -- (player, newName)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[DungeonSystem]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[DungeonSystem]", ...)
end

--[[
    Sendet Dungeon-Update an Client
    @param player: Der Spieler
    @param data: Spielerdaten
]]
local function sendDungeonUpdate(player, data)
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Level = data.Dungeon.Level,
        Experience = data.Dungeon.Experience,
        Name = data.Dungeon.Name,
        Rooms = data.Dungeon.Rooms,
        UnlockedTraps = data.Dungeon.UnlockedTraps,
        UnlockedMonsters = data.Dungeon.UnlockedMonsters,
        UnlockedRooms = data.Dungeon.UnlockedRooms,
    })
end

--[[
    Fügt XP zum Dungeon hinzu und prüft Level-Up
    @param player: Der Spieler
    @param xpAmount: XP-Menge
    @return: leveledUp, newLevel
]]
local function addDungeonXP(player, xpAmount)
    local data = DataManager.GetData(player)
    if not data then return false, 0 end
    
    local oldLevel = data.Dungeon.Level or 1
    local oldXP = data.Dungeon.Experience or 0
    local newXP = oldXP + xpAmount
    
    -- Neues Level berechnen
    local newLevel = DataTemplate.CalculateDungeonLevel(newXP)
    local maxLevel = 100
    newLevel = math.min(newLevel, maxLevel)
    
    -- Daten aktualisieren
    DataManager.SetValue(player, "Dungeon.Experience", newXP)
    
    local leveledUp = newLevel > oldLevel
    if leveledUp then
        DataManager.SetValue(player, "Dungeon.Level", newLevel)
        
        -- Signal feuern
        DungeonSystem.Signals.DungeonLevelUp:Fire(player, newLevel, oldLevel)
        
        -- Benachrichtigung
        if PlayerManager then
            PlayerManager.SendNotification(
                player,
                "Dungeon Level Up!",
                "Dein Dungeon ist jetzt Level " .. newLevel .. "!",
                "Success"
            )
        end
        
        debugPrint(player.Name .. "'s Dungeon Level Up: " .. oldLevel .. " -> " .. newLevel)
    end
    
    return leveledUp, newLevel
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert das DungeonSystem
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
    @param currencyServiceRef: Referenz zum CurrencyService
]]
function DungeonSystem.Initialize(dataManagerRef, playerManagerRef, currencyServiceRef)
    debugPrint("Initialisiere DungeonSystem...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    CurrencyService = currencyServiceRef
    
    debugPrint("DungeonSystem initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - RAUM-MANAGEMENT
-------------------------------------------------

--[[
    Fügt einen neuen Raum zum Dungeon hinzu
    @param player: Der Spieler
    @param roomId: ID des Raum-Typs
    @return: success, errorMessage, roomIndex
]]
function DungeonSystem.AddRoom(player, roomId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Raum-Config prüfen
    local roomConfig = RoomConfig.GetRoom(roomId)
    if not roomConfig then
        return false, "Ungültiger Raum-Typ", nil
    end
    
    -- Maximale Räume prüfen
    local currentRooms = #data.Dungeon.Rooms
    if currentRooms >= GameConfig.Dungeon.MaxRooms then
        return false, "Maximale Raumanzahl erreicht (" .. GameConfig.Dungeon.MaxRooms .. ")", nil
    end
    
    -- Unlock-Requirement prüfen
    local req = roomConfig.UnlockRequirement
    if req.Type == "DungeonLevel" then
        if data.Dungeon.Level < req.Level then
            return false, "Dungeon-Level " .. req.Level .. " benötigt", nil
        end
    end
    
    -- MaxPerDungeon prüfen
    if roomConfig.MaxPerDungeon then
        local count = 0
        for _, room in ipairs(data.Dungeon.Rooms) do
            if room.RoomId == roomId then
                count = count + 1
            end
        end
        if count >= roomConfig.MaxPerDungeon then
            return false, "Maximum dieses Raum-Typs erreicht (" .. roomConfig.MaxPerDungeon .. ")", nil
        end
    end
    
    -- Freischaltung prüfen (außer Starter-Räume)
    if req.Type ~= "None" and not data.Dungeon.UnlockedRooms[roomId] then
        -- Prüfen ob automatisch freigeschaltet durch Level
        if req.Type == "DungeonLevel" and data.Dungeon.Level >= req.Level then
            -- OK, wird durch Level freigeschaltet
        else
            return false, "Raum muss erst freigeschaltet werden", nil
        end
    end
    
    -- Kosten berechnen (Raum-Kosten + Position-Kosten)
    local roomCost = {
        Gold = roomConfig.PurchaseCost,
        Gems = roomConfig.PurchaseGems,
    }
    local positionCost = CurrencyUtil.CalculateNewRoomCost(currentRooms)
    local totalCost = CurrencyUtil.AddCosts(roomCost, positionCost)
    
    -- Prestige-Rabatt anwenden
    totalCost = CurrencyService.CalculateCostWithDiscount(player, totalCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        totalCost,
        CurrencyService.TransactionType.RoomPurchase,
        "Room:" .. roomId
    )
    
    if not success then
        return false, purchaseError, nil
    end
    
    -- Neuen Raum erstellen
    local newRoom = {
        RoomId = roomId,
        Level = 1,
        Traps = {},
        Monsters = {},
    }
    
    -- Raum hinzufügen
    local rooms = data.Dungeon.Rooms
    rooms[#rooms + 1] = newRoom
    DataManager.SetValue(player, "Dungeon.Rooms", rooms)
    
    local newRoomIndex = #rooms
    
    -- XP hinzufügen
    local xpGain = CONFIG.XPPerRoomAdded + (currentRooms * CONFIG.XPPerRoomBaseMultiplier)
    addDungeonXP(player, xpGain)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.RoomAdded:Fire(player, newRoomIndex, newRoom)
    
    debugPrint(player.Name .. " hat Raum hinzugefügt: " .. roomId .. " (Index: " .. newRoomIndex .. ")")
    
    return true, nil, newRoomIndex
end

--[[
    Entfernt einen Raum (nur der letzte Raum kann entfernt werden)
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @return: success, errorMessage
]]
function DungeonSystem.RemoveRoom(player, roomIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local rooms = data.Dungeon.Rooms
    
    -- Mindestens 3 Räume behalten
    if #rooms <= 3 then
        return false, "Mindestens 3 Räume erforderlich"
    end
    
    -- Nur letzter Raum kann entfernt werden
    if roomIndex ~= #rooms then
        return false, "Nur der letzte Raum kann entfernt werden"
    end
    
    -- Raum entfernen
    local removedRoom = table.remove(rooms, roomIndex)
    DataManager.SetValue(player, "Dungeon.Rooms", rooms)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.RoomRemoved:Fire(player, roomIndex)
    
    debugPrint(player.Name .. " hat Raum entfernt: Index " .. roomIndex)
    
    return true, nil
end

-------------------------------------------------
-- PUBLIC API - FALLEN-MANAGEMENT
-------------------------------------------------

--[[
    Platziert eine Falle in einem Raum
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @param slotIndex: Index des Fallen-Slots
    @param trapId: ID der Falle
    @return: success, errorMessage
]]
function DungeonSystem.PlaceTrap(player, roomIndex, slotIndex, trapId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum"
    end
    
    -- Trap-Config prüfen
    local trapConfig = TrapConfig.GetTrap(trapId)
    if not trapConfig then
        return false, "Ungültige Falle"
    end
    
    -- Freischaltung prüfen
    if not data.Dungeon.UnlockedTraps[trapId] then
        return false, "Falle nicht freigeschaltet"
    end
    
    -- Slot-Limit prüfen
    local roomConfig = RoomConfig.GetRoom(room.RoomId)
    if not roomConfig then
        return false, "Ungültige Raum-Daten"
    end
    
    if slotIndex < 1 or slotIndex > roomConfig.TrapSlots then
        return false, "Ungültiger Fallen-Slot (max: " .. roomConfig.TrapSlots .. ")"
    end
    
    -- Kosten prüfen (erste Platzierung hat Kosten, Austausch kostenlos)
    local existingTrap = room.Traps[slotIndex]
    local isNewPlacement = existingTrap == nil
    
    if isNewPlacement then
        local cost = {
            Gold = trapConfig.PurchaseCost,
            Gems = trapConfig.PurchaseGems,
        }
        cost = CurrencyService.CalculateCostWithDiscount(player, cost)
        
        local success, purchaseError = CurrencyService.Purchase(
            player,
            cost,
            CurrencyService.TransactionType.TrapPurchase,
            "Trap:" .. trapId
        )
        
        if not success then
            return false, purchaseError
        end
        
        -- XP für neue Platzierung
        addDungeonXP(player, CONFIG.XPPerTrapPlaced)
    end
    
    -- Falle platzieren
    room.Traps[slotIndex] = {
        TrapId = trapId,
        Level = 1,
    }
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.TrapPlaced:Fire(player, roomIndex, slotIndex, room.Traps[slotIndex])
    
    debugPrint(player.Name .. " hat Falle platziert: " .. trapId .. " (Raum " .. roomIndex .. ", Slot " .. slotIndex .. ")")
    
    return true, nil
end

--[[
    Entfernt eine Falle aus einem Raum
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @param slotIndex: Index des Fallen-Slots
    @return: success, errorMessage
]]
function DungeonSystem.RemoveTrap(player, roomIndex, slotIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum"
    end
    
    if not room.Traps[slotIndex] then
        return false, "Keine Falle in diesem Slot"
    end
    
    local removedTrap = room.Traps[slotIndex]
    room.Traps[slotIndex] = nil
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.TrapRemoved:Fire(player, roomIndex, slotIndex)
    
    debugPrint(player.Name .. " hat Falle entfernt: Raum " .. roomIndex .. ", Slot " .. slotIndex)
    
    return true, nil
end

-------------------------------------------------
-- PUBLIC API - MONSTER-MANAGEMENT
-------------------------------------------------

--[[
    Platziert ein Monster in einem Raum
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @param slotIndex: Index des Monster-Slots
    @param monsterId: ID des Monsters
    @return: success, errorMessage
]]
function DungeonSystem.PlaceMonster(player, roomIndex, slotIndex, monsterId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum"
    end
    
    -- Monster-Config prüfen
    local monsterConfig = MonsterConfig.GetMonster(monsterId)
    if not monsterConfig then
        return false, "Ungültiges Monster"
    end
    
    -- Freischaltung prüfen
    if not data.Dungeon.UnlockedMonsters[monsterId] then
        return false, "Monster nicht freigeschaltet"
    end
    
    -- Raum-Config prüfen
    local roomConfig = RoomConfig.GetRoom(room.RoomId)
    if not roomConfig then
        return false, "Ungültige Raum-Daten"
    end
    
    -- Raum-Einschränkungen prüfen
    if not RoomConfig.CanPlaceMonster(room.RoomId, monsterConfig.Rarity) then
        return false, "Dieses Monster kann in diesem Raum nicht platziert werden"
    end
    
    -- Slot-Limit prüfen
    if slotIndex < 1 or slotIndex > roomConfig.MonsterSlots then
        return false, "Ungültiger Monster-Slot (max: " .. roomConfig.MonsterSlots .. ")"
    end
    
    -- MaxPerDungeon für Monster prüfen
    if monsterConfig.MaxPerDungeon then
        local count = 0
        for _, r in ipairs(data.Dungeon.Rooms) do
            for _, m in pairs(r.Monsters or {}) do
                if m.MonsterId == monsterId then
                    count = count + 1
                end
            end
        end
        
        -- Existierendes Monster im gleichen Slot nicht zählen
        local existingMonster = room.Monsters[slotIndex]
        if existingMonster and existingMonster.MonsterId == monsterId then
            count = count - 1
        end
        
        if count >= monsterConfig.MaxPerDungeon then
            return false, "Maximum dieses Monster-Typs erreicht (" .. monsterConfig.MaxPerDungeon .. ")"
        end
    end
    
    -- Kosten prüfen
    local existingMonster = room.Monsters[slotIndex]
    local isNewPlacement = existingMonster == nil
    
    if isNewPlacement then
        local cost = {
            Gold = monsterConfig.PurchaseCost,
            Gems = monsterConfig.PurchaseGems,
        }
        cost = CurrencyService.CalculateCostWithDiscount(player, cost)
        
        local success, purchaseError = CurrencyService.Purchase(
            player,
            cost,
            CurrencyService.TransactionType.MonsterPurchase,
            "Monster:" .. monsterId
        )
        
        if not success then
            return false, purchaseError
        end
        
        -- XP für neue Platzierung
        addDungeonXP(player, CONFIG.XPPerMonsterPlaced)
    end
    
    -- Monster platzieren
    room.Monsters[slotIndex] = {
        MonsterId = monsterId,
        Level = 1,
    }
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.MonsterPlaced:Fire(player, roomIndex, slotIndex, room.Monsters[slotIndex])
    
    debugPrint(player.Name .. " hat Monster platziert: " .. monsterId .. " (Raum " .. roomIndex .. ", Slot " .. slotIndex .. ")")
    
    return true, nil
end

--[[
    Entfernt ein Monster aus einem Raum
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @param slotIndex: Index des Monster-Slots
    @return: success, errorMessage
]]
function DungeonSystem.RemoveMonster(player, roomIndex, slotIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum"
    end
    
    if not room.Monsters[slotIndex] then
        return false, "Kein Monster in diesem Slot"
    end
    
    local removedMonster = room.Monsters[slotIndex]
    room.Monsters[slotIndex] = nil
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.MonsterRemoved:Fire(player, roomIndex, slotIndex)
    
    debugPrint(player.Name .. " hat Monster entfernt: Raum " .. roomIndex .. ", Slot " .. slotIndex)
    
    return true, nil
end

-------------------------------------------------
-- PUBLIC API - DUNGEON-STATS
-------------------------------------------------

--[[
    Berechnet die Gesamt-Stats eines Dungeons
    @param player: Der Spieler
    @return: stats { TotalDPS, TotalHP, TrapCount, MonsterCount, RoomCount, ... }
]]
function DungeonSystem.CalculateDungeonStats(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    local stats = {
        RoomCount = 0,
        TrapCount = 0,
        MonsterCount = 0,
        TotalTrapDPS = 0,
        TotalMonsterHP = 0,
        TotalMonsterDPS = 0,
        EstimatedDifficulty = 0,
    }
    
    local rooms = data.Dungeon.Rooms or {}
    stats.RoomCount = #rooms
    
    for roomIndex, room in ipairs(rooms) do
        local roomConfig = RoomConfig.GetRoom(room.RoomId)
        local roomLevel = room.Level or 1
        local roomBonuses = roomConfig and RoomConfig.CalculateBonusesAtLevel(room.RoomId, roomLevel) or {}
        
        -- Trap-DPS Bonus aus Raum
        local trapDamageBonus = 0
        for _, bonus in ipairs(roomBonuses) do
            if bonus.Type == "TrapDamage" then
                trapDamageBonus = trapDamageBonus + (bonus.Value or 0)
            end
        end
        
        -- Monster-Boni aus Raum
        local monsterHealthBonus = 0
        local monsterDamageBonus = 0
        for _, bonus in ipairs(roomBonuses) do
            if bonus.Type == "MonsterHealth" then
                monsterHealthBonus = monsterHealthBonus + (bonus.Value or 0)
            elseif bonus.Type == "MonsterDamage" then
                monsterDamageBonus = monsterDamageBonus + (bonus.Value or 0)
            end
        end
        
        -- Fallen durchgehen
        for slotIndex, trap in pairs(room.Traps or {}) do
            stats.TrapCount = stats.TrapCount + 1
            
            local trapStats = TrapConfig.CalculateStatsAtLevel(trap.TrapId, trap.Level or 1)
            if trapStats then
                local dps = trapStats.Damage / trapStats.Cooldown
                dps = dps * (1 + trapDamageBonus)
                stats.TotalTrapDPS = stats.TotalTrapDPS + dps
            end
        end
        
        -- Monster durchgehen
        for slotIndex, monster in pairs(room.Monsters or {}) do
            stats.MonsterCount = stats.MonsterCount + 1
            
            local monsterStats = MonsterConfig.CalculateStatsAtLevel(monster.MonsterId, monster.Level or 1)
            if monsterStats then
                local hp = monsterStats.Health * (1 + monsterHealthBonus)
                local dps = monsterStats.Damage / monsterStats.AttackCooldown
                dps = dps * (1 + monsterDamageBonus)
                
                stats.TotalMonsterHP = stats.TotalMonsterHP + hp
                stats.TotalMonsterDPS = stats.TotalMonsterDPS + dps
            end
        end
    end
    
    -- Geschätzte Schwierigkeit (einfache Formel)
    stats.EstimatedDifficulty = math.floor(
        (stats.TotalTrapDPS * 2) + 
        (stats.TotalMonsterDPS * 3) + 
        (stats.TotalMonsterHP / 10) +
        (stats.RoomCount * 50)
    )
    
    return stats
end

--[[
    Gibt die Dungeon-Info für einen Spieler zurück
    @param player: Der Spieler
    @return: dungeonInfo
]]
function DungeonSystem.GetDungeonInfo(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    local stats = DungeonSystem.CalculateDungeonStats(player)
    
    return {
        Name = data.Dungeon.Name,
        Level = data.Dungeon.Level,
        Experience = data.Dungeon.Experience,
        XPToNextLevel = DataTemplate.GetXPForNextLevel(data.Dungeon.Level),
        RoomCount = #data.Dungeon.Rooms,
        MaxRooms = GameConfig.Dungeon.MaxRooms,
        Stats = stats,
        PassiveIncomePerMinute = CurrencyUtil.CalculatePassiveIncome(
            data.Dungeon.Level,
            data.Prestige.Level or 0
        ),
    }
end

--[[
    Benennt einen Dungeon um
    @param player: Der Spieler
    @param newName: Neuer Name
    @return: success, errorMessage, sanitizedName
]]
function DungeonSystem.RenameDungeon(player, newName)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Name validieren
    if type(newName) ~= "string" then
        return false, "Ungültiger Name", nil
    end
    
    -- Länge begrenzen
    newName = string.sub(newName, 1, 30)
    
    -- Nur erlaubte Zeichen (alphanumerisch, Leerzeichen, Bindestrich, Unterstrich)
    newName = string.gsub(newName, "[^%w%s%-_äöüÄÖÜß]", "")
    
    -- Whitespace trimmen
    newName = string.match(newName, "^%s*(.-)%s*$") or ""
    
    if #newName < 3 then
        return false, "Name zu kurz (min. 3 Zeichen)", nil
    end
    
    -- Name speichern
    DataManager.SetValue(player, "Dungeon.Name", newName)
    
    -- Client updaten
    sendDungeonUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    DungeonSystem.Signals.DungeonRenamed:Fire(player, newName)
    
    debugPrint(player.Name .. " hat Dungeon umbenannt zu: " .. newName)
    
    return true, nil, newName
end

-------------------------------------------------
-- PUBLIC API - ABFRAGEN
-------------------------------------------------

--[[
    Gibt verfügbare Slots für einen Raum zurück
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @return: { TrapSlots = {...}, MonsterSlots = {...} }
]]
function DungeonSystem.GetAvailableSlots(player, roomIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then return nil end
    
    local roomConfig = RoomConfig.GetRoom(room.RoomId)
    if not roomConfig then return nil end
    
    local availableTrapSlots = {}
    local availableMonsterSlots = {}
    
    -- Freie Trap-Slots finden
    for i = 1, roomConfig.TrapSlots do
        if not room.Traps[i] then
            table.insert(availableTrapSlots, i)
        end
    end
    
    -- Freie Monster-Slots finden
    for i = 1, roomConfig.MonsterSlots do
        if not room.Monsters[i] then
            table.insert(availableMonsterSlots, i)
        end
    end
    
    return {
        TrapSlots = availableTrapSlots,
        MonsterSlots = availableMonsterSlots,
        TotalTrapSlots = roomConfig.TrapSlots,
        TotalMonsterSlots = roomConfig.MonsterSlots,
        UsedTrapSlots = roomConfig.TrapSlots - #availableTrapSlots,
        UsedMonsterSlots = roomConfig.MonsterSlots - #availableMonsterSlots,
    }
end

--[[
    Gibt die Kosten für den nächsten Raum zurück
    @param player: Der Spieler
    @param roomId: ID des Raum-Typs
    @return: totalCost
]]
function DungeonSystem.GetNextRoomCost(player, roomId)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    local roomConfig = RoomConfig.GetRoom(roomId)
    if not roomConfig then return nil end
    
    local currentRooms = #data.Dungeon.Rooms
    
    local roomCost = {
        Gold = roomConfig.PurchaseCost,
        Gems = roomConfig.PurchaseGems,
    }
    local positionCost = CurrencyUtil.CalculateNewRoomCost(currentRooms)
    local totalCost = CurrencyUtil.AddCosts(roomCost, positionCost)
    
    return CurrencyService.CalculateCostWithDiscount(player, totalCost)
end

--[[
    Prüft ob ein Spieler einen bestimmten Raum-Typ hinzufügen kann
    @param player: Der Spieler
    @param roomId: ID des Raum-Typs
    @return: canAdd, reason
]]
function DungeonSystem.CanAddRoom(player, roomId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local roomConfig = RoomConfig.GetRoom(roomId)
    if not roomConfig then
        return false, "Ungültiger Raum-Typ"
    end
    
    -- Max Räume
    if #data.Dungeon.Rooms >= GameConfig.Dungeon.MaxRooms then
        return false, "Maximale Raumanzahl erreicht"
    end
    
    -- Unlock-Requirement
    local req = roomConfig.UnlockRequirement
    if req.Type == "DungeonLevel" and data.Dungeon.Level < req.Level then
        return false, "Dungeon-Level " .. req.Level .. " benötigt"
    end
    
    -- MaxPerDungeon
    if roomConfig.MaxPerDungeon then
        local count = 0
        for _, room in ipairs(data.Dungeon.Rooms) do
            if room.RoomId == roomId then
                count = count + 1
            end
        end
        if count >= roomConfig.MaxPerDungeon then
            return false, "Maximum erreicht"
        end
    end
    
    -- Kosten prüfen
    local cost = DungeonSystem.GetNextRoomCost(player, roomId)
    local canAfford, affordError = CurrencyService.CanAfford(player, cost)
    if not canAfford then
        return false, affordError
    end
    
    return true, nil
end

return DungeonSystem
