--[[
    ServerMain.lua
    Haupt-Entry-Point für den Server
    Pfad: ServerScriptService/Server/ServerMain
    
    Dieses Script:
    - Initialisiert alle Server-Module in korrekter Reihenfolge
    - Verbindet Remote-Handler
    - Startet den GameLoop
    
    WICHTIG: Dies ist ein SCRIPT, kein ModuleScript!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

print("[ServerMain] Starte Server-Initialisierung...")

-------------------------------------------------
-- PFADE DEFINIEREN
-------------------------------------------------
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")
local RemotesPath = SharedPath:WaitForChild("Remotes")

local ServerPath = ServerScriptService:WaitForChild("Server")
local CorePath = ServerPath:WaitForChild("Core")
local SystemsPath = ServerPath:WaitForChild("Systems")
local ServicesPath = ServerPath:WaitForChild("Services")

-------------------------------------------------
-- SHARED MODULES LADEN
-------------------------------------------------
print("[ServerMain] Lade Shared Modules...")

local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))

local DataTemplate = require(ModulesPath:WaitForChild("DataTemplate"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

print("[ServerMain] Shared Modules geladen!")

-------------------------------------------------
-- REMOTES ERSTELLEN
-------------------------------------------------
print("[ServerMain] Erstelle Remotes...")
RemoteIndex.Setup()
print("[ServerMain] Remotes erstellt!")

-------------------------------------------------
-- CORE MODULES LADEN
-------------------------------------------------
print("[ServerMain] Lade Core Modules...")

local DataManager = require(CorePath:WaitForChild("DataManager"))
local PlayerManager = require(CorePath:WaitForChild("PlayerManager"))
local GameLoop = require(CorePath:WaitForChild("GameLoop"))

print("[ServerMain] Core Modules geladen!")

-------------------------------------------------
-- CORE INITIALISIEREN
-------------------------------------------------
print("[ServerMain] Initialisiere Core...")

-- DataManager zuerst (hat keine Abhängigkeiten)
DataManager.Initialize()

-- PlayerManager (braucht DataManager)
PlayerManager.Initialize(DataManager)

-- GameLoop (braucht DataManager und PlayerManager)
GameLoop.Initialize(DataManager, PlayerManager)

print("[ServerMain] Core initialisiert!")

-------------------------------------------------
-- REMOTE HANDLER VERBINDEN
-------------------------------------------------
print("[ServerMain] Verbinde Remote Handler...")

--[[
    =============================================
    WÄHRUNG & ECONOMY
    =============================================
]]

-- Currency_Request: Client fragt aktuelle Währung ab
RemoteIndex.Get("Currency_Request").OnServerInvoke = function(player)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    return {
        Success = true,
        Gold = data.Currency.Gold,
        Gems = data.Currency.Gems,
    }
end

-- Currency_CollectPassive: Passives Einkommen abholen
RemoteIndex.Get("Currency_CollectPassive").OnServerInvoke = function(player)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    local currentTime = os.time()
    local lastCollect = data.Cooldowns.LastPassiveCollect or currentTime
    local dungeonLevel = data.Dungeon.Level or 1
    local prestigeLevel = data.Prestige.Level or 0
    
    -- Angesammeltes Einkommen berechnen
    local accumulated = CurrencyUtil.CalculateAccumulatedIncome(
        dungeonLevel,
        prestigeLevel,
        lastCollect,
        currentTime
    )
    
    if accumulated <= 0 then
        return { Success = false, Error = "Nichts zum Abholen" }
    end
    
    -- Gold hinzufügen
    local currentGold = data.Currency.Gold or 0
    local addable = CurrencyUtil.CalculateAddable(currentGold, accumulated, "Gold")
    
    if addable > 0 then
        DataManager.IncrementValue(player, "Currency.Gold", addable)
        DataManager.IncrementValue(player, "Stats.TotalGoldEarned", addable)
        DataManager.SetValue(player, "Cooldowns.LastPassiveCollect", currentTime)
        
        -- Client updaten
        RemoteIndex.FireClient("Currency_Update", player, {
            Gold = currentGold + addable,
            Gems = data.Currency.Gems,
            Source = "PassiveCollect",
            Amount = addable,
        })
        
        return {
            Success = true,
            Amount = addable,
            NewTotal = currentGold + addable,
        }
    end
    
    return { Success = false, Error = "Gold-Limit erreicht" }
end

--[[
    =============================================
    DUNGEON BUILDING
    =============================================
]]

-- Dungeon_AddRoom: Neuen Raum kaufen
RemoteIndex.Get("Dungeon_AddRoom").OnServerInvoke = function(player, roomId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Raum-Config prüfen
    local roomConfig = RoomConfig.GetRoom(roomId)
    if not roomConfig then
        return { Success = false, Error = "Ungültiger Raum-Typ" }
    end
    
    -- Maximale Räume prüfen
    local currentRooms = #data.Dungeon.Rooms
    if currentRooms >= GameConfig.Dungeon.MaxRooms then
        return { Success = false, Error = "Maximale Raumanzahl erreicht" }
    end
    
    -- Unlock-Requirement prüfen
    local req = roomConfig.UnlockRequirement
    if req.Type == "DungeonLevel" then
        if data.Dungeon.Level < req.Level then
            return { Success = false, Error = "Dungeon-Level " .. req.Level .. " benötigt" }
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
            return { Success = false, Error = "Maximum dieses Raum-Typs erreicht" }
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
    totalCost = CurrencyUtil.ApplyPrestigeDiscount(totalCost, data.Prestige.Level or 0)
    
    -- Kosten prüfen
    local canAfford, affordError = CurrencyUtil.CanAfford(data.Currency, totalCost)
    if not canAfford then
        return { Success = false, Error = affordError }
    end
    
    -- Kosten abziehen
    DataManager.IncrementValue(player, "Currency.Gold", -totalCost.Gold)
    DataManager.IncrementValue(player, "Currency.Gems", -totalCost.Gems)
    DataManager.IncrementValue(player, "Stats.TotalGoldSpent", totalCost.Gold)
    DataManager.IncrementValue(player, "Stats.TotalGemsSpent", totalCost.Gems)
    
    -- Neuen Raum hinzufügen
    local newRoom = {
        RoomId = roomId,
        Level = 1,
        Traps = {},
        Monsters = {},
    }
    
    local rooms = data.Dungeon.Rooms
    rooms[#rooms + 1] = newRoom
    DataManager.SetValue(player, "Dungeon.Rooms", rooms)
    
    -- XP für Dungeon hinzufügen
    local xpGain = 50 + (currentRooms * 10)
    DataManager.IncrementValue(player, "Dungeon.Experience", xpGain)
    
    -- Level-Up prüfen
    local newExp = data.Dungeon.Experience + xpGain
    local newLevel = DataTemplate.CalculateDungeonLevel(newExp)
    if newLevel > data.Dungeon.Level then
        DataManager.SetValue(player, "Dungeon.Level", newLevel)
        PlayerManager.SendNotification(player, "Level Up!", "Dein Dungeon ist jetzt Level " .. newLevel, "Success")
    end
    
    -- Client updaten
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = data.Currency.Gold - totalCost.Gold,
        Gems = data.Currency.Gems - totalCost.Gems,
    })
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Level = newLevel or data.Dungeon.Level,
        Experience = newExp,
        Rooms = rooms,
    })
    
    return {
        Success = true,
        RoomIndex = #rooms,
        Cost = totalCost,
    }
end

-- Dungeon_PlaceTrap: Falle in Raum platzieren
RemoteIndex.Get("Dungeon_PlaceTrap").OnServerInvoke = function(player, roomIndex, slotIndex, trapId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return { Success = false, Error = "Ungültiger Raum" }
    end
    
    -- Trap-Config prüfen
    local trapConfig = TrapConfig.GetTrap(trapId)
    if not trapConfig then
        return { Success = false, Error = "Ungültige Falle" }
    end
    
    -- Freischaltung prüfen
    if not data.Dungeon.UnlockedTraps[trapId] then
        return { Success = false, Error = "Falle nicht freigeschaltet" }
    end
    
    -- Slot-Limit prüfen
    local roomConfig = RoomConfig.GetRoom(room.RoomId)
    if slotIndex < 1 or slotIndex > roomConfig.TrapSlots then
        return { Success = false, Error = "Ungültiger Fallen-Slot" }
    end
    
    -- Kosten prüfen (erste Platzierung kostenlos, danach Kosten)
    local existingTrap = room.Traps[slotIndex]
    local cost = { Gold = 0, Gems = 0 }
    
    if not existingTrap then
        -- Erste Platzierung: volle Kosten
        cost = {
            Gold = trapConfig.PurchaseCost,
            Gems = trapConfig.PurchaseGems,
        }
    end
    
    -- Prestige-Rabatt
    cost = CurrencyUtil.ApplyPrestigeDiscount(cost, data.Prestige.Level or 0)
    
    -- Kosten prüfen
    if cost.Gold > 0 or cost.Gems > 0 then
        local canAfford, affordError = CurrencyUtil.CanAfford(data.Currency, cost)
        if not canAfford then
            return { Success = false, Error = affordError }
        end
        
        -- Kosten abziehen
        DataManager.IncrementValue(player, "Currency.Gold", -cost.Gold)
        DataManager.IncrementValue(player, "Currency.Gems", -cost.Gems)
        DataManager.IncrementValue(player, "Stats.TotalGoldSpent", cost.Gold)
        DataManager.IncrementValue(player, "Stats.TotalGemsSpent", cost.Gems)
    end
    
    -- Falle platzieren
    room.Traps[slotIndex] = {
        TrapId = trapId,
        Level = 1,
    }
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Client updaten
    if cost.Gold > 0 or cost.Gems > 0 then
        RemoteIndex.FireClient("Currency_Update", player, {
            Gold = data.Currency.Gold,
            Gems = data.Currency.Gems,
        })
    end
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Rooms = data.Dungeon.Rooms,
    })
    
    return {
        Success = true,
        Cost = cost,
    }
end

-- Dungeon_PlaceMonster: Monster in Raum platzieren
RemoteIndex.Get("Dungeon_PlaceMonster").OnServerInvoke = function(player, roomIndex, slotIndex, monsterId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return { Success = false, Error = "Ungültiger Raum" }
    end
    
    -- Monster-Config prüfen
    local monsterConfig = MonsterConfig.GetMonster(monsterId)
    if not monsterConfig then
        return { Success = false, Error = "Ungültiges Monster" }
    end
    
    -- Freischaltung prüfen
    if not data.Dungeon.UnlockedMonsters[monsterId] then
        return { Success = false, Error = "Monster nicht freigeschaltet" }
    end
    
    -- Raum-Einschränkungen prüfen
    local roomConfig = RoomConfig.GetRoom(room.RoomId)
    if not RoomConfig.CanPlaceMonster(room.RoomId, monsterConfig.Rarity) then
        return { Success = false, Error = "Dieses Monster kann hier nicht platziert werden" }
    end
    
    -- Slot-Limit prüfen
    if slotIndex < 1 or slotIndex > roomConfig.MonsterSlots then
        return { Success = false, Error = "Ungültiger Monster-Slot" }
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
        if count >= monsterConfig.MaxPerDungeon then
            return { Success = false, Error = "Maximum dieses Monster-Typs erreicht" }
        end
    end
    
    -- Kosten
    local existingMonster = room.Monsters[slotIndex]
    local cost = { Gold = 0, Gems = 0 }
    
    if not existingMonster then
        cost = {
            Gold = monsterConfig.PurchaseCost,
            Gems = monsterConfig.PurchaseGems,
        }
    end
    
    cost = CurrencyUtil.ApplyPrestigeDiscount(cost, data.Prestige.Level or 0)
    
    if cost.Gold > 0 or cost.Gems > 0 then
        local canAfford, affordError = CurrencyUtil.CanAfford(data.Currency, cost)
        if not canAfford then
            return { Success = false, Error = affordError }
        end
        
        DataManager.IncrementValue(player, "Currency.Gold", -cost.Gold)
        DataManager.IncrementValue(player, "Currency.Gems", -cost.Gems)
        DataManager.IncrementValue(player, "Stats.TotalGoldSpent", cost.Gold)
        DataManager.IncrementValue(player, "Stats.TotalGemsSpent", cost.Gems)
    end
    
    -- Monster platzieren
    room.Monsters[slotIndex] = {
        MonsterId = monsterId,
        Level = 1,
    }
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Client updaten
    if cost.Gold > 0 or cost.Gems > 0 then
        RemoteIndex.FireClient("Currency_Update", player, {
            Gold = data.Currency.Gold,
            Gems = data.Currency.Gems,
        })
    end
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Rooms = data.Dungeon.Rooms,
    })
    
    return {
        Success = true,
        Cost = cost,
    }
end

-- Dungeon_RemoveTrap: Falle entfernen
RemoteIndex.Get("Dungeon_RemoveTrap").OnServerInvoke = function(player, roomIndex, slotIndex)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return { Success = false, Error = "Ungültiger Raum" }
    end
    
    if not room.Traps[slotIndex] then
        return { Success = false, Error = "Keine Falle in diesem Slot" }
    end
    
    room.Traps[slotIndex] = nil
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Rooms = data.Dungeon.Rooms,
    })
    
    return { Success = true }
end

-- Dungeon_RemoveMonster: Monster entfernen
RemoteIndex.Get("Dungeon_RemoveMonster").OnServerInvoke = function(player, roomIndex, slotIndex)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return { Success = false, Error = "Ungültiger Raum" }
    end
    
    if not room.Monsters[slotIndex] then
        return { Success = false, Error = "Kein Monster in diesem Slot" }
    end
    
    room.Monsters[slotIndex] = nil
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Rooms = data.Dungeon.Rooms,
    })
    
    return { Success = true }
end

-- Dungeon_Rename: Dungeon umbenennen
RemoteIndex.Get("Dungeon_Rename").OnServerInvoke = function(player, newName)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Name validieren
    if type(newName) ~= "string" then
        return { Success = false, Error = "Ungültiger Name" }
    end
    
    newName = string.sub(newName, 1, 30)  -- Max 30 Zeichen
    newName = string.gsub(newName, "[^%w%s%-_]", "")  -- Nur alphanumerisch, Leerzeichen, Bindestrich, Unterstrich
    
    if #newName < 3 then
        return { Success = false, Error = "Name zu kurz (min. 3 Zeichen)" }
    end
    
    DataManager.SetValue(player, "Dungeon.Name", newName)
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Name = newName,
    })
    
    return { Success = true, Name = newName }
end

--[[
    =============================================
    SHOP & UNLOCKS
    =============================================
]]

-- Shop_UnlockTrap: Falle freischalten
RemoteIndex.Get("Shop_UnlockTrap").OnServerInvoke = function(player, trapId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Bereits freigeschaltet?
    if data.Dungeon.UnlockedTraps[trapId] then
        return { Success = false, Error = "Bereits freigeschaltet" }
    end
    
    -- Trap-Config prüfen
    local trapConfig = TrapConfig.GetTrap(trapId)
    if not trapConfig then
        return { Success = false, Error = "Ungültige Falle" }
    end
    
    -- Kosten (doppelter Kaufpreis zum Freischalten)
    local cost = {
        Gold = trapConfig.PurchaseCost * 2,
        Gems = trapConfig.PurchaseGems * 2,
    }
    
    cost = CurrencyUtil.ApplyPrestigeDiscount(cost, data.Prestige.Level or 0)
    
    local canAfford, affordError = CurrencyUtil.CanAfford(data.Currency, cost)
    if not canAfford then
        return { Success = false, Error = affordError }
    end
    
    -- Kosten abziehen
    DataManager.IncrementValue(player, "Currency.Gold", -cost.Gold)
    DataManager.IncrementValue(player, "Currency.Gems", -cost.Gems)
    DataManager.IncrementValue(player, "Stats.TotalGoldSpent", cost.Gold)
    DataManager.IncrementValue(player, "Stats.TotalGemsSpent", cost.Gems)
    
    -- Freischalten
    data.Dungeon.UnlockedTraps[trapId] = true
    DataManager.SetValue(player, "Dungeon.UnlockedTraps", data.Dungeon.UnlockedTraps)
    
    -- Client updaten
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = data.Currency.Gold,
        Gems = data.Currency.Gems,
    })
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        UnlockedTraps = data.Dungeon.UnlockedTraps,
    })
    
    PlayerManager.SendNotification(player, "Freigeschaltet!", trapConfig.Name .. " ist jetzt verfügbar.", "Success")
    
    return { Success = true, Cost = cost }
end

-- Shop_UnlockMonster: Monster freischalten
RemoteIndex.Get("Shop_UnlockMonster").OnServerInvoke = function(player, monsterId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    if data.Dungeon.UnlockedMonsters[monsterId] then
        return { Success = false, Error = "Bereits freigeschaltet" }
    end
    
    local monsterConfig = MonsterConfig.GetMonster(monsterId)
    if not monsterConfig then
        return { Success = false, Error = "Ungültiges Monster" }
    end
    
    if monsterConfig.Purchasable == false then
        return { Success = false, Error = "Dieses Monster kann nicht gekauft werden" }
    end
    
    local cost = {
        Gold = monsterConfig.PurchaseCost * 2,
        Gems = monsterConfig.PurchaseGems * 2,
    }
    
    cost = CurrencyUtil.ApplyPrestigeDiscount(cost, data.Prestige.Level or 0)
    
    local canAfford, affordError = CurrencyUtil.CanAfford(data.Currency, cost)
    if not canAfford then
        return { Success = false, Error = affordError }
    end
    
    DataManager.IncrementValue(player, "Currency.Gold", -cost.Gold)
    DataManager.IncrementValue(player, "Currency.Gems", -cost.Gems)
    DataManager.IncrementValue(player, "Stats.TotalGoldSpent", cost.Gold)
    DataManager.IncrementValue(player, "Stats.TotalGemsSpent", cost.Gems)
    
    data.Dungeon.UnlockedMonsters[monsterId] = true
    DataManager.SetValue(player, "Dungeon.UnlockedMonsters", data.Dungeon.UnlockedMonsters)
    
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = data.Currency.Gold,
        Gems = data.Currency.Gems,
    })
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        UnlockedMonsters = data.Dungeon.UnlockedMonsters,
    })
    
    PlayerManager.SendNotification(player, "Freigeschaltet!", monsterConfig.Name .. " ist jetzt verfügbar.", "Success")
    
    return { Success = true, Cost = cost }
end

--[[
    =============================================
    HELDEN-MANAGEMENT
    =============================================
]]

-- Heroes_Recruit: Held rekrutieren
RemoteIndex.Get("Heroes_Recruit").OnServerInvoke = function(player, heroId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Hero-Config prüfen
    local heroConfig = HeroConfig.GetHero(heroId)
    if not heroConfig then
        return { Success = false, Error = "Ungültiger Held" }
    end
    
    -- Freischaltung prüfen
    if not data.Heroes.Unlocked[heroId] then
        return { Success = false, Error = "Held nicht freigeschaltet" }
    end
    
    -- Kosten
    local cost = {
        Gold = heroConfig.RecruitCost,
        Gems = heroConfig.RecruitGems,
    }
    
    cost = CurrencyUtil.ApplyPrestigeDiscount(cost, data.Prestige.Level or 0)
    
    local canAfford, affordError = CurrencyUtil.CanAfford(data.Currency, cost)
    if not canAfford then
        return { Success = false, Error = affordError }
    end
    
    -- Kosten abziehen
    DataManager.IncrementValue(player, "Currency.Gold", -cost.Gold)
    DataManager.IncrementValue(player, "Currency.Gems", -cost.Gems)
    DataManager.IncrementValue(player, "Stats.TotalGoldSpent", cost.Gold)
    DataManager.IncrementValue(player, "Stats.TotalGemsSpent", cost.Gems)
    
    -- Rarität würfeln
    local roll = math.random()
    local rarity = "Common"
    local cumulativeChance = 0
    
    for rarityName, rarityData in pairs(HeroConfig.Rarities) do
        cumulativeChance = cumulativeChance + rarityData.DropChance
        if roll <= cumulativeChance then
            rarity = rarityName
            break
        end
    end
    
    -- Neuen Helden erstellen
    local heroInstanceId = DataTemplate.GenerateUniqueId()
    local newHero = {
        HeroId = heroId,
        Level = 1,
        Experience = 0,
        Rarity = rarity,
    }
    
    data.Heroes.Owned[heroInstanceId] = newHero
    DataManager.SetValue(player, "Heroes.Owned", data.Heroes.Owned)
    
    -- Client updaten
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = data.Currency.Gold,
        Gems = data.Currency.Gems,
    })
    
    RemoteIndex.FireClient("Heroes_Update", player, {
        Owned = data.Heroes.Owned,
    })
    
    local rarityColor = HeroConfig.Rarities[rarity].Name
    PlayerManager.SendNotification(player, "Held rekrutiert!", heroConfig.Name .. " (" .. rarityColor .. ")", "Success")
    
    return {
        Success = true,
        HeroInstanceId = heroInstanceId,
        Hero = newHero,
        Rarity = rarity,
    }
end

-- Heroes_SetTeam: Raid-Team setzen
RemoteIndex.Get("Heroes_SetTeam").OnServerInvoke = function(player, teamIds)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Team validieren
    if type(teamIds) ~= "table" then
        return { Success = false, Error = "Ungültiges Team-Format" }
    end
    
    if #teamIds > GameConfig.Heroes.MaxPartySize then
        return { Success = false, Error = "Zu viele Helden im Team (max " .. GameConfig.Heroes.MaxPartySize .. ")" }
    end
    
    -- Prüfen ob alle Helden dem Spieler gehören
    for _, heroInstanceId in ipairs(teamIds) do
        if not data.Heroes.Owned[heroInstanceId] then
            return { Success = false, Error = "Held nicht im Besitz: " .. heroInstanceId }
        end
    end
    
    -- Team setzen
    DataManager.SetValue(player, "Heroes.Team", teamIds)
    
    RemoteIndex.FireClient("Heroes_Update", player, {
        Team = teamIds,
    })
    
    return { Success = true }
end

--[[
    =============================================
    SPIELER-EINSTELLUNGEN
    =============================================
]]

-- Player_SettingsUpdate: Einstellungen ändern
RemoteIndex.Get("Player_SettingsUpdate").OnServerInvoke = function(player, settingKey, value)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Erlaubte Settings
    local allowedSettings = {
        MusicEnabled = "boolean",
        SFXEnabled = "boolean",
        NotificationsEnabled = "boolean",
        Language = "string",
    }
    
    if not allowedSettings[settingKey] then
        return { Success = false, Error = "Ungültige Einstellung" }
    end
    
    if type(value) ~= allowedSettings[settingKey] then
        return { Success = false, Error = "Ungültiger Wert-Typ" }
    end
    
    -- Sprache validieren
    if settingKey == "Language" then
        local validLanguages = { "de", "en", "es", "fr" }
        local isValid = false
        for _, lang in ipairs(validLanguages) do
            if value == lang then
                isValid = true
                break
            end
        end
        if not isValid then
            return { Success = false, Error = "Ungültige Sprache" }
        end
    end
    
    DataManager.SetValue(player, "Settings." .. settingKey, value)
    
    return { Success = true }
end

print("[ServerMain] Remote Handler verbunden!")

-------------------------------------------------
-- GAMELOOP STARTEN
-------------------------------------------------
print("[ServerMain] Starte GameLoop...")
GameLoop.Start()
print("[ServerMain] GameLoop gestartet!")

-------------------------------------------------
-- SERVER BEREIT
-------------------------------------------------
print("[ServerMain] ========================================")
print("[ServerMain] Dungeon Tycoon Server bereit!")
print("[ServerMain] Version: 1.0.0")
print("[ServerMain] Debug-Modus: " .. tostring(GameConfig.Debug.Enabled))
print("[ServerMain] ========================================")
