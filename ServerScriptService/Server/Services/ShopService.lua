--[[
    ShopService.lua
    Zentraler Service für Shop-Operationen
    Pfad: ServerScriptService/Server/Services/ShopService
    
    Verantwortlich für:
    - Freischaltungen (Traps, Monster, Räume, Helden)
    - Upgrades (Level-Erhöhungen)
    - Kaufvalidierung
    - Preis-Berechnungen
    
    WICHTIG: Nutzt CurrencyService für alle Transaktionen!
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
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Service-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil
local CurrencyService = nil

local ShopService = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Freischalt-Kosten Multiplikator (relativ zum Kaufpreis)
    UnlockCostMultiplier = 2.0,
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
ShopService.Signals = {
    TrapUnlocked = SignalUtil.new(),        -- (player, trapId)
    MonsterUnlocked = SignalUtil.new(),     -- (player, monsterId)
    RoomUnlocked = SignalUtil.new(),        -- (player, roomId)
    HeroUnlocked = SignalUtil.new(),        -- (player, heroId)
    
    TrapUpgraded = SignalUtil.new(),        -- (player, roomIndex, slotIndex, newLevel)
    MonsterUpgraded = SignalUtil.new(),     -- (player, roomIndex, slotIndex, newLevel)
    RoomUpgraded = SignalUtil.new(),        -- (player, roomIndex, newLevel)
    HeroUpgraded = SignalUtil.new(),        -- (player, heroInstanceId, newLevel)
    
    PurchaseFailed = SignalUtil.new(),      -- (player, itemType, reason)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[ShopService]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[ShopService]", ...)
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
        Rooms = data.Dungeon.Rooms,
        UnlockedTraps = data.Dungeon.UnlockedTraps,
        UnlockedMonsters = data.Dungeon.UnlockedMonsters,
        UnlockedRooms = data.Dungeon.UnlockedRooms,
    })
end

--[[
    Sendet Helden-Update an Client
    @param player: Der Spieler
    @param data: Spielerdaten
]]
local function sendHeroesUpdate(player, data)
    RemoteIndex.FireClient("Heroes_Update", player, {
        Owned = data.Heroes.Owned,
        Team = data.Heroes.Team,
        Unlocked = data.Heroes.Unlocked,
    })
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den ShopService
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
    @param currencyServiceRef: Referenz zum CurrencyService
]]
function ShopService.Initialize(dataManagerRef, playerManagerRef, currencyServiceRef)
    debugPrint("Initialisiere ShopService...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    CurrencyService = currencyServiceRef
    
    debugPrint("ShopService initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - FREISCHALTUNGEN
-------------------------------------------------

--[[
    Schaltet eine Falle frei
    @param player: Der Spieler
    @param trapId: ID der Falle
    @return: success, errorMessage, cost
]]
function ShopService.UnlockTrap(player, trapId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Bereits freigeschaltet?
    if data.Dungeon.UnlockedTraps[trapId] then
        return false, "Bereits freigeschaltet", nil
    end
    
    -- Config prüfen
    local trapConfig = TrapConfig.GetTrap(trapId)
    if not trapConfig then
        return false, "Ungültige Falle", nil
    end
    
    -- Kosten berechnen
    local baseCost = {
        Gold = trapConfig.PurchaseCost * CONFIG.UnlockCostMultiplier,
        Gems = trapConfig.PurchaseGems * CONFIG.UnlockCostMultiplier,
    }
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Unlock,
        "Trap:" .. trapId
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "Trap", purchaseError)
        return false, purchaseError, cost
    end
    
    -- Freischalten
    data.Dungeon.UnlockedTraps[trapId] = true
    DataManager.SetValue(player, "Dungeon.UnlockedTraps", data.Dungeon.UnlockedTraps)
    
    -- Updates senden
    sendDungeonUpdate(player, data)
    
    -- Benachrichtigung
    if PlayerManager then
        PlayerManager.SendNotification(
            player,
            "Falle freigeschaltet!",
            trapConfig.Name .. " ist jetzt verfügbar.",
            "Success"
        )
    end
    
    -- Signal feuern
    ShopService.Signals.TrapUnlocked:Fire(player, trapId)
    
    debugPrint(player.Name .. " hat Falle freigeschaltet: " .. trapId)
    
    return true, nil, cost
end

--[[
    Schaltet ein Monster frei
    @param player: Der Spieler
    @param monsterId: ID des Monsters
    @return: success, errorMessage, cost
]]
function ShopService.UnlockMonster(player, monsterId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Bereits freigeschaltet?
    if data.Dungeon.UnlockedMonsters[monsterId] then
        return false, "Bereits freigeschaltet", nil
    end
    
    -- Config prüfen
    local monsterConfig = MonsterConfig.GetMonster(monsterId)
    if not monsterConfig then
        return false, "Ungültiges Monster", nil
    end
    
    -- Nicht kaufbar?
    if monsterConfig.Purchasable == false then
        return false, "Dieses Monster kann nicht gekauft werden", nil
    end
    
    -- Kosten berechnen
    local baseCost = {
        Gold = monsterConfig.PurchaseCost * CONFIG.UnlockCostMultiplier,
        Gems = monsterConfig.PurchaseGems * CONFIG.UnlockCostMultiplier,
    }
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Unlock,
        "Monster:" .. monsterId
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "Monster", purchaseError)
        return false, purchaseError, cost
    end
    
    -- Freischalten
    data.Dungeon.UnlockedMonsters[monsterId] = true
    DataManager.SetValue(player, "Dungeon.UnlockedMonsters", data.Dungeon.UnlockedMonsters)
    
    -- Updates senden
    sendDungeonUpdate(player, data)
    
    -- Benachrichtigung
    if PlayerManager then
        PlayerManager.SendNotification(
            player,
            "Monster freigeschaltet!",
            monsterConfig.Name .. " ist jetzt verfügbar.",
            "Success"
        )
    end
    
    -- Signal feuern
    ShopService.Signals.MonsterUnlocked:Fire(player, monsterId)
    
    debugPrint(player.Name .. " hat Monster freigeschaltet: " .. monsterId)
    
    return true, nil, cost
end

--[[
    Schaltet einen Raum-Typ frei
    @param player: Der Spieler
    @param roomId: ID des Raum-Typs
    @return: success, errorMessage, cost
]]
function ShopService.UnlockRoom(player, roomId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Bereits freigeschaltet?
    if data.Dungeon.UnlockedRooms[roomId] then
        return false, "Bereits freigeschaltet", nil
    end
    
    -- Config prüfen
    local roomConfig = RoomConfig.GetRoom(roomId)
    if not roomConfig then
        return false, "Ungültiger Raum-Typ", nil
    end
    
    -- Freischalt-Bedingung prüfen
    local req = roomConfig.UnlockRequirement
    if req.Type == "DungeonLevel" then
        if data.Dungeon.Level < req.Level then
            return false, "Dungeon-Level " .. req.Level .. " benötigt", nil
        end
    end
    
    -- Kosten berechnen
    local baseCost = {
        Gold = roomConfig.PurchaseCost * CONFIG.UnlockCostMultiplier,
        Gems = roomConfig.PurchaseGems * CONFIG.UnlockCostMultiplier,
    }
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Unlock,
        "Room:" .. roomId
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "Room", purchaseError)
        return false, purchaseError, cost
    end
    
    -- Freischalten
    data.Dungeon.UnlockedRooms[roomId] = true
    DataManager.SetValue(player, "Dungeon.UnlockedRooms", data.Dungeon.UnlockedRooms)
    
    -- Updates senden
    sendDungeonUpdate(player, data)
    
    -- Benachrichtigung
    if PlayerManager then
        PlayerManager.SendNotification(
            player,
            "Raum freigeschaltet!",
            roomConfig.Name .. " ist jetzt verfügbar.",
            "Success"
        )
    end
    
    -- Signal feuern
    ShopService.Signals.RoomUnlocked:Fire(player, roomId)
    
    debugPrint(player.Name .. " hat Raum freigeschaltet: " .. roomId)
    
    return true, nil, cost
end

--[[
    Schaltet einen Helden frei
    @param player: Der Spieler
    @param heroId: ID des Helden
    @return: success, errorMessage, cost
]]
function ShopService.UnlockHero(player, heroId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Bereits freigeschaltet?
    if data.Heroes.Unlocked[heroId] then
        return false, "Bereits freigeschaltet", nil
    end
    
    -- Config prüfen
    local heroConfig = HeroConfig.GetHero(heroId)
    if not heroConfig then
        return false, "Ungültiger Held", nil
    end
    
    -- Kosten berechnen (dreifacher Rekrutierungspreis zum Freischalten)
    local baseCost = {
        Gold = heroConfig.RecruitCost * 3,
        Gems = heroConfig.RecruitGems * 3,
    }
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Unlock,
        "Hero:" .. heroId
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "Hero", purchaseError)
        return false, purchaseError, cost
    end
    
    -- Freischalten
    data.Heroes.Unlocked[heroId] = true
    DataManager.SetValue(player, "Heroes.Unlocked", data.Heroes.Unlocked)
    
    -- Updates senden
    sendHeroesUpdate(player, data)
    
    -- Benachrichtigung
    if PlayerManager then
        PlayerManager.SendNotification(
            player,
            "Held freigeschaltet!",
            heroConfig.Name .. " kann jetzt rekrutiert werden.",
            "Success"
        )
    end
    
    -- Signal feuern
    ShopService.Signals.HeroUnlocked:Fire(player, heroId)
    
    debugPrint(player.Name .. " hat Held freigeschaltet: " .. heroId)
    
    return true, nil, cost
end

-------------------------------------------------
-- PUBLIC API - UPGRADES
-------------------------------------------------

--[[
    Upgraded eine Falle
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @param slotIndex: Index des Fallen-Slots
    @return: success, errorMessage, newLevel, cost
]]
function ShopService.UpgradeTrap(player, roomIndex, slotIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil, nil
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum", nil, nil
    end
    
    -- Falle prüfen
    local trap = room.Traps[slotIndex]
    if not trap then
        return false, "Keine Falle in diesem Slot", nil, nil
    end
    
    -- Config laden
    local trapConfig = TrapConfig.GetTrap(trap.TrapId)
    if not trapConfig then
        return false, "Ungültige Fallen-Daten", nil, nil
    end
    
    -- Max-Level prüfen
    local currentLevel = trap.Level or 1
    local maxLevel = TrapConfig.UpgradeSettings.MaxLevel
    
    if currentLevel >= maxLevel then
        return false, "Maximales Level erreicht", currentLevel, nil
    end
    
    -- Kosten berechnen
    local baseCost = TrapConfig.CalculateUpgradeCost(trap.TrapId, currentLevel)
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Upgrade,
        "Trap:" .. trap.TrapId .. ":Lv" .. (currentLevel + 1)
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "TrapUpgrade", purchaseError)
        return false, purchaseError, currentLevel, cost
    end
    
    -- Level erhöhen
    local newLevel = currentLevel + 1
    room.Traps[slotIndex].Level = newLevel
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Updates senden
    sendDungeonUpdate(player, data)
    
    -- Signal feuern
    ShopService.Signals.TrapUpgraded:Fire(player, roomIndex, slotIndex, newLevel)
    
    debugPrint(player.Name .. " hat Falle upgraded: " .. trap.TrapId .. " -> Lv" .. newLevel)
    
    return true, nil, newLevel, cost
end

--[[
    Upgraded ein Monster
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @param slotIndex: Index des Monster-Slots
    @return: success, errorMessage, newLevel, cost
]]
function ShopService.UpgradeMonster(player, roomIndex, slotIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil, nil
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum", nil, nil
    end
    
    -- Monster prüfen
    local monster = room.Monsters[slotIndex]
    if not monster then
        return false, "Kein Monster in diesem Slot", nil, nil
    end
    
    -- Config laden
    local monsterConfig = MonsterConfig.GetMonster(monster.MonsterId)
    if not monsterConfig then
        return false, "Ungültige Monster-Daten", nil, nil
    end
    
    -- Max-Level prüfen
    local currentLevel = monster.Level or 1
    local maxLevel = MonsterConfig.UpgradeSettings.MaxLevel
    
    if currentLevel >= maxLevel then
        return false, "Maximales Level erreicht", currentLevel, nil
    end
    
    -- Kosten berechnen
    local baseCost = MonsterConfig.CalculateUpgradeCost(monster.MonsterId, currentLevel)
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Upgrade,
        "Monster:" .. monster.MonsterId .. ":Lv" .. (currentLevel + 1)
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "MonsterUpgrade", purchaseError)
        return false, purchaseError, currentLevel, cost
    end
    
    -- Level erhöhen
    local newLevel = currentLevel + 1
    room.Monsters[slotIndex].Level = newLevel
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Updates senden
    sendDungeonUpdate(player, data)
    
    -- Signal feuern
    ShopService.Signals.MonsterUpgraded:Fire(player, roomIndex, slotIndex, newLevel)
    
    debugPrint(player.Name .. " hat Monster upgraded: " .. monster.MonsterId .. " -> Lv" .. newLevel)
    
    return true, nil, newLevel, cost
end

--[[
    Upgraded einen Raum
    @param player: Der Spieler
    @param roomIndex: Index des Raums
    @return: success, errorMessage, newLevel, cost
]]
function ShopService.UpgradeRoom(player, roomIndex)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil, nil
    end
    
    -- Raum prüfen
    local room = data.Dungeon.Rooms[roomIndex]
    if not room then
        return false, "Ungültiger Raum", nil, nil
    end
    
    -- Config laden
    local roomConfig = RoomConfig.GetRoom(room.RoomId)
    if not roomConfig then
        return false, "Ungültige Raum-Daten", nil, nil
    end
    
    -- Max-Level prüfen
    local currentLevel = room.Level or 1
    local maxLevel = RoomConfig.UpgradeSettings.MaxLevel
    
    if currentLevel >= maxLevel then
        return false, "Maximales Level erreicht", currentLevel, nil
    end
    
    -- Kosten berechnen
    local baseCost = RoomConfig.CalculateUpgradeCost(room.RoomId, currentLevel)
    local cost = CurrencyService.CalculateCostWithDiscount(player, baseCost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Upgrade,
        "Room:" .. room.RoomId .. ":Lv" .. (currentLevel + 1)
    )
    
    if not success then
        ShopService.Signals.PurchaseFailed:Fire(player, "RoomUpgrade", purchaseError)
        return false, purchaseError, currentLevel, cost
    end
    
    -- Level erhöhen
    local newLevel = currentLevel + 1
    room.Level = newLevel
    DataManager.SetValue(player, "Dungeon.Rooms", data.Dungeon.Rooms)
    
    -- Updates senden
    sendDungeonUpdate(player, data)
    
    -- Signal feuern
    ShopService.Signals.RoomUpgraded:Fire(player, roomIndex, newLevel)
    
    debugPrint(player.Name .. " hat Raum upgraded: " .. room.RoomId .. " -> Lv" .. newLevel)
    
    return true, nil, newLevel, cost
end

--[[
    Upgraded einen Helden mit XP
    @param player: Der Spieler
    @param heroInstanceId: Instance-ID des Helden
    @param xpAmount: XP-Menge zum Hinzufügen
    @return: success, errorMessage, newLevel, leveledUp
]]
function ShopService.AddHeroXP(player, heroInstanceId, xpAmount)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil, false
    end
    
    -- Held prüfen
    local hero = data.Heroes.Owned[heroInstanceId]
    if not hero then
        return false, "Held nicht gefunden", nil, false
    end
    
    -- Config laden
    local heroConfig = HeroConfig.GetHero(hero.HeroId)
    if not heroConfig then
        return false, "Ungültige Helden-Daten", nil, false
    end
    
    -- Max-Level prüfen
    local currentLevel = hero.Level or 1
    local maxLevel = HeroConfig.UpgradeSettings.MaxLevel
    
    if currentLevel >= maxLevel then
        return true, nil, currentLevel, false
    end
    
    -- XP hinzufügen
    local currentXP = hero.Experience or 0
    local newXP = currentXP + xpAmount
    
    -- Level-Ups berechnen
    local newLevel = currentLevel
    local leveledUp = false
    
    while newLevel < maxLevel do
        local xpNeeded = HeroConfig.CalculateXPForLevel(newLevel)
        if newXP >= xpNeeded then
            newXP = newXP - xpNeeded
            newLevel = newLevel + 1
            leveledUp = true
        else
            break
        end
    end
    
    -- Daten speichern
    hero.Level = newLevel
    hero.Experience = newXP
    DataManager.SetValue(player, "Heroes.Owned", data.Heroes.Owned)
    
    -- Updates senden
    sendHeroesUpdate(player, data)
    
    -- Benachrichtigung bei Level-Up
    if leveledUp and PlayerManager then
        PlayerManager.SendNotification(
            player,
            "Level Up!",
            heroConfig.Name .. " ist jetzt Level " .. newLevel,
            "Success"
        )
    end
    
    -- Signal feuern
    if leveledUp then
        ShopService.Signals.HeroUpgraded:Fire(player, heroInstanceId, newLevel)
    end
    
    debugPrint(player.Name .. "'s Held " .. hero.HeroId .. " -> Lv" .. newLevel .. " (+" .. xpAmount .. " XP)")
    
    return true, nil, newLevel, leveledUp
end

-------------------------------------------------
-- PUBLIC API - PREISABFRAGEN
-------------------------------------------------

--[[
    Gibt die Kosten für eine Fallen-Freischaltung zurück
    @param player: Der Spieler
    @param trapId: ID der Falle
    @return: cost oder nil
]]
function ShopService.GetTrapUnlockCost(player, trapId)
    local trapConfig = TrapConfig.GetTrap(trapId)
    if not trapConfig then return nil end
    
    local baseCost = {
        Gold = trapConfig.PurchaseCost * CONFIG.UnlockCostMultiplier,
        Gems = trapConfig.PurchaseGems * CONFIG.UnlockCostMultiplier,
    }
    
    return CurrencyService.CalculateCostWithDiscount(player, baseCost)
end

--[[
    Gibt die Kosten für eine Monster-Freischaltung zurück
    @param player: Der Spieler
    @param monsterId: ID des Monsters
    @return: cost oder nil
]]
function ShopService.GetMonsterUnlockCost(player, monsterId)
    local monsterConfig = MonsterConfig.GetMonster(monsterId)
    if not monsterConfig then return nil end
    
    local baseCost = {
        Gold = monsterConfig.PurchaseCost * CONFIG.UnlockCostMultiplier,
        Gems = monsterConfig.PurchaseGems * CONFIG.UnlockCostMultiplier,
    }
    
    return CurrencyService.CalculateCostWithDiscount(player, baseCost)
end

--[[
    Gibt die Kosten für ein Fallen-Upgrade zurück
    @param player: Der Spieler
    @param trapId: ID der Falle
    @param currentLevel: Aktuelles Level
    @return: cost oder nil
]]
function ShopService.GetTrapUpgradeCost(player, trapId, currentLevel)
    local baseCost = TrapConfig.CalculateUpgradeCost(trapId, currentLevel)
    if not baseCost then return nil end
    
    return CurrencyService.CalculateCostWithDiscount(player, baseCost)
end

--[[
    Gibt die Kosten für ein Monster-Upgrade zurück
    @param player: Der Spieler
    @param monsterId: ID des Monsters
    @param currentLevel: Aktuelles Level
    @return: cost oder nil
]]
function ShopService.GetMonsterUpgradeCost(player, monsterId, currentLevel)
    local baseCost = MonsterConfig.CalculateUpgradeCost(monsterId, currentLevel)
    if not baseCost then return nil end
    
    return CurrencyService.CalculateCostWithDiscount(player, baseCost)
end

--[[
    Gibt die Kosten für ein Raum-Upgrade zurück
    @param player: Der Spieler
    @param roomId: ID des Raums
    @param currentLevel: Aktuelles Level
    @return: cost oder nil
]]
function ShopService.GetRoomUpgradeCost(player, roomId, currentLevel)
    local baseCost = RoomConfig.CalculateUpgradeCost(roomId, currentLevel)
    if not baseCost then return nil end
    
    return CurrencyService.CalculateCostWithDiscount(player, baseCost)
end

--[[
    Gibt alle verfügbaren (aber nicht freigeschalteten) Items zurück
    @param player: Der Spieler
    @return: { Traps = {...}, Monsters = {...}, Rooms = {...}, Heroes = {...} }
]]
function ShopService.GetAvailableUnlocks(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    local available = {
        Traps = {},
        Monsters = {},
        Rooms = {},
        Heroes = {},
    }
    
    local dungeonLevel = data.Dungeon.Level or 1
    
    -- Verfügbare Fallen
    for trapId, trapConfig in pairs(TrapConfig.Traps) do
        if not data.Dungeon.UnlockedTraps[trapId] then
            table.insert(available.Traps, {
                Id = trapId,
                Config = trapConfig,
                Cost = ShopService.GetTrapUnlockCost(player, trapId),
            })
        end
    end
    
    -- Verfügbare Monster
    for monsterId, monsterConfig in pairs(MonsterConfig.Monsters) do
        if not data.Dungeon.UnlockedMonsters[monsterId] then
            if monsterConfig.Purchasable ~= false then
                table.insert(available.Monsters, {
                    Id = monsterId,
                    Config = monsterConfig,
                    Cost = ShopService.GetMonsterUnlockCost(player, monsterId),
                })
            end
        end
    end
    
    -- Verfügbare Räume
    for roomId, roomConfig in pairs(RoomConfig.Rooms) do
        if not data.Dungeon.UnlockedRooms[roomId] then
            local req = roomConfig.UnlockRequirement
            local canUnlock = true
            
            if req.Type == "DungeonLevel" and dungeonLevel < req.Level then
                canUnlock = false
            end
            
            if canUnlock then
                table.insert(available.Rooms, {
                    Id = roomId,
                    Config = roomConfig,
                    Cost = CurrencyService.CalculateCostWithDiscount(player, {
                        Gold = roomConfig.PurchaseCost * CONFIG.UnlockCostMultiplier,
                        Gems = roomConfig.PurchaseGems * CONFIG.UnlockCostMultiplier,
                    }),
                })
            end
        end
    end
    
    -- Verfügbare Helden
    for heroId, heroConfig in pairs(HeroConfig.Heroes) do
        if not data.Heroes.Unlocked[heroId] then
            table.insert(available.Heroes, {
                Id = heroId,
                Config = heroConfig,
                Cost = CurrencyService.CalculateCostWithDiscount(player, {
                    Gold = heroConfig.RecruitCost * 3,
                    Gems = heroConfig.RecruitGems * 3,
                }),
            })
        end
    end
    
    return available
end

return ShopService
