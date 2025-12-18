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
-- SERVICES LADEN
-------------------------------------------------
print("[ServerMain] Lade Services...")

local CurrencyService = require(ServicesPath:WaitForChild("CurrencyService"))
local ShopService = require(ServicesPath:WaitForChild("ShopService"))

print("[ServerMain] Services geladen!")

-------------------------------------------------
-- SYSTEMS LADEN
-------------------------------------------------
print("[ServerMain] Lade Systems...")

local DungeonSystem = require(SystemsPath:WaitForChild("DungeonSystem"))
local RaidSystem = require(SystemsPath:WaitForChild("RaidSystem"))
local HeroSystem = require(SystemsPath:WaitForChild("HeroSystem"))

print("[ServerMain] Systems geladen!")

-------------------------------------------------
-- INITIALISIERUNG (Reihenfolge wichtig!)
-------------------------------------------------
print("[ServerMain] Initialisiere Module...")

-- 1. DataManager zuerst (keine Abhängigkeiten)
DataManager.Initialize()

-- 2. PlayerManager (braucht DataManager)
PlayerManager.Initialize(DataManager)

-- 3. CurrencyService (braucht DataManager, PlayerManager)
CurrencyService.Initialize(DataManager, PlayerManager)

-- 4. ShopService (braucht DataManager, PlayerManager, CurrencyService)
ShopService.Initialize(DataManager, PlayerManager, CurrencyService)

-- 5. DungeonSystem (braucht DataManager, PlayerManager, CurrencyService)
DungeonSystem.Initialize(DataManager, PlayerManager, CurrencyService)

-- 6. HeroSystem (braucht DataManager, PlayerManager, CurrencyService)
HeroSystem.Initialize(DataManager, PlayerManager, CurrencyService)

-- 7. RaidSystem (braucht DataManager, PlayerManager, CurrencyService, DungeonSystem)
RaidSystem.Initialize(DataManager, PlayerManager, CurrencyService, DungeonSystem)

-- 8. GameLoop (braucht DataManager, PlayerManager)
GameLoop.Initialize(DataManager, PlayerManager)

print("[ServerMain] Module initialisiert!")

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
    
    -- Gold hinzufügen über CurrencyService
    local success, actualAmount = CurrencyService.AddGold(
        player,
        accumulated,
        CurrencyService.TransactionType.PassiveIncome,
        "PassiveCollect"
    )
    
    if success then
        DataManager.SetValue(player, "Cooldowns.LastPassiveCollect", currentTime)
        
        return {
            Success = true,
            Amount = actualAmount,
            NewTotal = DataManager.GetValue(player, "Currency.Gold"),
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
    local success, errorMsg, roomIndex = DungeonSystem.AddRoom(player, roomId)
    
    if success then
        return {
            Success = true,
            RoomIndex = roomIndex,
        }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Dungeon_UpgradeRoom: Raum upgraden
RemoteIndex.Get("Dungeon_UpgradeRoom").OnServerInvoke = function(player, roomIndex)
    local success, errorMsg, newLevel, cost = ShopService.UpgradeRoom(player, roomIndex)
    
    if success then
        return {
            Success = true,
            NewLevel = newLevel,
            Cost = cost,
        }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Dungeon_PlaceTrap: Falle platzieren
RemoteIndex.Get("Dungeon_PlaceTrap").OnServerInvoke = function(player, roomIndex, slotIndex, trapId)
    local success, errorMsg = DungeonSystem.PlaceTrap(player, roomIndex, slotIndex, trapId)
    
    if success then
        return { Success = true }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Dungeon_RemoveTrap: Falle entfernen
RemoteIndex.Get("Dungeon_RemoveTrap").OnServerInvoke = function(player, roomIndex, slotIndex)
    local success, errorMsg = DungeonSystem.RemoveTrap(player, roomIndex, slotIndex)
    
    if success then
        return { Success = true }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Dungeon_PlaceMonster: Monster platzieren
RemoteIndex.Get("Dungeon_PlaceMonster").OnServerInvoke = function(player, roomIndex, slotIndex, monsterId)
    local success, errorMsg = DungeonSystem.PlaceMonster(player, roomIndex, slotIndex, monsterId)
    
    if success then
        return { Success = true }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Dungeon_RemoveMonster: Monster entfernen
RemoteIndex.Get("Dungeon_RemoveMonster").OnServerInvoke = function(player, roomIndex, slotIndex)
    local success, errorMsg = DungeonSystem.RemoveMonster(player, roomIndex, slotIndex)
    
    if success then
        return { Success = true }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Dungeon_Rename: Dungeon umbenennen
RemoteIndex.Get("Dungeon_Rename").OnServerInvoke = function(player, newName)
    local success, errorMsg, sanitizedName = DungeonSystem.RenameDungeon(player, newName)
    
    if success then
        return { Success = true, Name = sanitizedName }
    else
        return { Success = false, Error = errorMsg }
    end
end

--[[
    =============================================
    SHOP & UNLOCKS
    =============================================
]]

-- Shop_UnlockTrap: Falle freischalten
RemoteIndex.Get("Shop_UnlockTrap").OnServerInvoke = function(player, trapId)
    local success, errorMsg, cost = ShopService.UnlockTrap(player, trapId)
    
    if success then
        return { Success = true, Cost = cost }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Shop_UnlockMonster: Monster freischalten
RemoteIndex.Get("Shop_UnlockMonster").OnServerInvoke = function(player, monsterId)
    local success, errorMsg, cost = ShopService.UnlockMonster(player, monsterId)
    
    if success then
        return { Success = true, Cost = cost }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Shop_UnlockRoom: Raum-Typ freischalten
RemoteIndex.Get("Shop_UnlockRoom").OnServerInvoke = function(player, roomId)
    local success, errorMsg, cost = ShopService.UnlockRoom(player, roomId)
    
    if success then
        return { Success = true, Cost = cost }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Shop_UnlockHero: Held freischalten
RemoteIndex.Get("Shop_UnlockHero").OnServerInvoke = function(player, heroId)
    local success, errorMsg, cost = ShopService.UnlockHero(player, heroId)
    
    if success then
        return { Success = true, Cost = cost }
    else
        return { Success = false, Error = errorMsg }
    end
end

--[[
    =============================================
    HELDEN-MANAGEMENT
    =============================================
]]

-- Heroes_Recruit: Held rekrutieren
RemoteIndex.Get("Heroes_Recruit").OnServerInvoke = function(player, heroId)
    local success, result = HeroSystem.RecruitHero(player, heroId)
    
    if success then
        return {
            Success = true,
            HeroInstanceId = result.InstanceId,
            Hero = result.Hero,
            Rarity = result.Rarity,
            RarityName = result.RarityName,
        }
    else
        return { Success = false, Error = result }
    end
end

-- Heroes_SetTeam: Raid-Team setzen
RemoteIndex.Get("Heroes_SetTeam").OnServerInvoke = function(player, teamIds)
    local success, errorMsg, synergies = HeroSystem.SetTeam(player, teamIds)
    
    if success then
        return {
            Success = true,
            Synergies = synergies,
        }
    else
        return { Success = false, Error = errorMsg }
    end
end

-- Heroes_Upgrade: Held upgraden (XP hinzufügen)
RemoteIndex.Get("Heroes_Upgrade").OnServerInvoke = function(player, heroInstanceId, xpAmount)
    -- XP durch Items/Käufe - hier Beispiel mit fixen Kosten
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Kosten: 100 Gold pro 10 XP
    local cost = { Gold = math.floor(xpAmount * 10), Gems = 0 }
    
    local purchaseSuccess, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.Upgrade,
        "HeroXP:" .. heroInstanceId
    )
    
    if not purchaseSuccess then
        return { Success = false, Error = purchaseError }
    end
    
    local success, newLevel, leveledUp = HeroSystem.AddHeroXP(player, heroInstanceId, xpAmount)
    
    if success then
        return {
            Success = true,
            NewLevel = newLevel,
            LeveledUp = leveledUp,
        }
    else
        return { Success = false, Error = "Held nicht gefunden" }
    end
end

-- Heroes_Dismiss: Held entlassen
RemoteIndex.Get("Heroes_Dismiss").OnServerInvoke = function(player, heroInstanceId)
    local success, errorMsg, refund = HeroSystem.DismissHero(player, heroInstanceId)
    
    if success then
        return {
            Success = true,
            Refund = refund,
        }
    else
        return { Success = false, Error = errorMsg }
    end
end

--[[
    =============================================
    RAIDS
    =============================================
]]

-- Raid_FindTarget: Raid-Ziel suchen
RemoteIndex.Get("Raid_FindTarget").OnServerInvoke = function(player)
    -- Vorprüfung
    local canRaid, reason = RaidSystem.CanRaid(player)
    if not canRaid then
        return { Success = false, Error = reason }
    end
    
    local success, result = RaidSystem.FindTarget(player)
    
    if success then
        return {
            Success = true,
            IsNPC = result.IsNPC,
            TargetName = result.TargetData.Dungeon.Name,
            TargetLevel = result.TargetData.Dungeon.Level,
            RoomCount = #result.TargetData.Dungeon.Rooms,
            -- TargetData für StartRaid zwischenspeichern
            TargetInfo = result,
        }
    else
        return { Success = false, Error = result }
    end
end

-- Raid_Start: Raid starten
RemoteIndex.Get("Raid_Start").OnServerInvoke = function(player, targetInfo)
    if not targetInfo then
        return { Success = false, Error = "Kein Ziel ausgewählt" }
    end
    
    local success, result = RaidSystem.StartRaid(player, targetInfo)
    
    if success then
        return {
            Success = true,
            RaidId = result.RaidId,
            TargetName = result.TargetName,
            TotalRooms = result.TotalRooms,
        }
    else
        return { Success = false, Error = result }
    end
end

--[[
    =============================================
    PRESTIGE
    =============================================
]]

-- Prestige_Info: Prestige-Info abfragen
RemoteIndex.Get("Prestige_Info").OnServerInvoke = function(player)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    local currentLevel = data.Prestige.Level or 0
    local dungeonLevel = data.Dungeon.Level or 1
    local requiredLevel = GameConfig.Prestige.RequiredDungeonLevel
    local canPrestige = dungeonLevel >= requiredLevel
    
    local nextBonus = (currentLevel + 1) * GameConfig.Prestige.BonusPerPrestige
    local totalBonus = currentLevel * GameConfig.Prestige.BonusPerPrestige
    
    return {
        Success = true,
        CurrentLevel = currentLevel,
        TotalBonus = totalBonus,
        NextBonus = nextBonus,
        CanPrestige = canPrestige,
        RequiredDungeonLevel = requiredLevel,
        CurrentDungeonLevel = dungeonLevel,
    }
end

-- Prestige_Execute: Prestige durchführen
RemoteIndex.Get("Prestige_Execute").OnServerInvoke = function(player)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    local dungeonLevel = data.Dungeon.Level or 1
    local requiredLevel = GameConfig.Prestige.RequiredDungeonLevel
    
    if dungeonLevel < requiredLevel then
        return { Success = false, Error = "Dungeon-Level " .. requiredLevel .. " benötigt" }
    end
    
    local maxPrestige = GameConfig.Prestige.MaxPrestige
    local currentPrestige = data.Prestige.Level or 0
    
    if currentPrestige >= maxPrestige then
        return { Success = false, Error = "Maximales Prestige erreicht" }
    end
    
    -- Prestige durchführen
    local newPrestigeLevel = currentPrestige + 1
    local newBonus = newPrestigeLevel * GameConfig.Prestige.BonusPerPrestige
    
    -- Prestige-Daten setzen
    DataManager.SetValue(player, "Prestige.Level", newPrestigeLevel)
    DataManager.SetValue(player, "Prestige.TotalBonusPercent", newBonus)
    
    -- Dungeon zurücksetzen (aber Freischaltungen behalten)
    DataManager.SetValue(player, "Dungeon.Level", 1)
    DataManager.SetValue(player, "Dungeon.Experience", 0)
    
    -- Starter-Räume zurücksetzen
    local starterRooms = {
        [1] = { RoomId = "stone_corridor", Level = 1, Traps = {}, Monsters = {} },
        [2] = { RoomId = "stone_corridor", Level = 1, Traps = {}, Monsters = {} },
        [3] = { RoomId = "guard_chamber", Level = 1, Traps = {}, Monsters = {} },
    }
    DataManager.SetValue(player, "Dungeon.Rooms", starterRooms)
    
    -- Währung zurücksetzen auf Startwerte
    DataManager.SetValue(player, "Currency.Gold", GameConfig.Currency.StartingGold)
    DataManager.SetValue(player, "Currency.Gems", GameConfig.Currency.StartingGems)
    
    -- Helden behalten, aber Team leeren
    DataManager.SetValue(player, "Heroes.Team", {})
    
    -- Client über Änderungen informieren
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = GameConfig.Currency.StartingGold,
        Gems = GameConfig.Currency.StartingGems,
        Source = "Prestige",
    })
    
    RemoteIndex.FireClient("Dungeon_Update", player, {
        Level = 1,
        Experience = 0,
        Rooms = starterRooms,
    })
    
    RemoteIndex.FireClient("Heroes_Update", player, {
        Owned = data.Heroes.Owned,
        Team = {},
        Unlocked = data.Heroes.Unlocked,
    })
    
    -- Benachrichtigung
    PlayerManager.SendNotification(
        player,
        "Prestige " .. newPrestigeLevel .. "!",
        "+" .. math.floor(newBonus * 100) .. "% Bonus auf alles!",
        "Success"
    )
    
    return {
        Success = true,
        NewPrestigeLevel = newPrestigeLevel,
        TotalBonus = newBonus,
    }
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

--[[
    =============================================
    TUTORIAL & ACHIEVEMENTS
    =============================================
]]

-- Tutorial_Complete: Tutorial-Schritt abschließen
RemoteIndex.Get("Tutorial_Complete").OnServerInvoke = function(player, stepName)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Gültige Schritte
    local validSteps = { "Intro", "FirstRoom", "FirstTrap", "FirstMonster", "FirstRaid", "FirstDefense" }
    local isValid = false
    
    for _, step in ipairs(validSteps) do
        if step == stepName then
            isValid = true
            break
        end
    end
    
    if not isValid then
        return { Success = false, Error = "Ungültiger Tutorial-Schritt" }
    end
    
    -- Bereits abgeschlossen?
    if data.Progress.Tutorial[stepName] then
        return { Success = false, Error = "Bereits abgeschlossen" }
    end
    
    DataManager.SetValue(player, "Progress.Tutorial." .. stepName, true)
    
    -- Belohnung je nach Schritt
    local rewards = {
        Intro = { Gold = 100, Gems = 0 },
        FirstRoom = { Gold = 200, Gems = 0 },
        FirstTrap = { Gold = 150, Gems = 0 },
        FirstMonster = { Gold = 150, Gems = 0 },
        FirstRaid = { Gold = 500, Gems = 5 },
        FirstDefense = { Gold = 300, Gems = 3 },
    }
    
    local reward = rewards[stepName]
    if reward then
        CurrencyService.GiveReward(
            player,
            reward,
            CurrencyService.TransactionType.AchievementReward,
            "Tutorial:" .. stepName
        )
    end
    
    return {
        Success = true,
        Reward = reward,
    }
end

--[[
    =============================================
    INBOX & REWARDS
    =============================================
]]

-- Inbox_Claim: Belohnung abholen
RemoteIndex.Get("Inbox_Claim").OnServerInvoke = function(player, rewardId)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    -- Belohnung finden
    local inbox = data.Inbox or {}
    local rewardIndex = nil
    local reward = nil
    
    for i, item in ipairs(inbox) do
        if item.Id == rewardId then
            rewardIndex = i
            reward = item
            break
        end
    end
    
    if not reward then
        return { Success = false, Error = "Belohnung nicht gefunden" }
    end
    
    if reward.Claimed then
        return { Success = false, Error = "Bereits abgeholt" }
    end
    
    -- Abgelaufen?
    if reward.ExpiresAt and os.time() > reward.ExpiresAt then
        return { Success = false, Error = "Belohnung abgelaufen" }
    end
    
    -- Belohnung geben
    local actualReward = CurrencyService.GiveReward(
        player,
        reward.Rewards or {},
        CurrencyService.TransactionType.AchievementReward,
        "Inbox:" .. rewardId
    )
    
    -- Als abgeholt markieren oder entfernen
    table.remove(inbox, rewardIndex)
    DataManager.SetValue(player, "Inbox", inbox)
    
    -- Client updaten
    RemoteIndex.FireClient("Inbox_Update", player, inbox)
    
    return {
        Success = true,
        Reward = actualReward,
    }
end

-- Inbox_ClaimAll: Alle abholen
RemoteIndex.Get("Inbox_ClaimAll").OnServerInvoke = function(player)
    local data = DataManager.GetData(player)
    if not data then
        return { Success = false, Error = "Daten nicht geladen" }
    end
    
    local inbox = data.Inbox or {}
    local totalReward = { Gold = 0, Gems = 0 }
    local claimedCount = 0
    local newInbox = {}
    
    for _, item in ipairs(inbox) do
        local canClaim = not item.Claimed
        
        -- Abgelaufen?
        if item.ExpiresAt and os.time() > item.ExpiresAt then
            canClaim = false
        end
        
        if canClaim and item.Rewards then
            -- Belohnung geben
            local actualReward = CurrencyService.GiveReward(
                player,
                item.Rewards,
                CurrencyService.TransactionType.AchievementReward,
                "Inbox:" .. item.Id
            )
            
            totalReward.Gold = totalReward.Gold + (actualReward.Gold or 0)
            totalReward.Gems = totalReward.Gems + (actualReward.Gems or 0)
            claimedCount = claimedCount + 1
        else
            -- Nicht abholbar, behalten
            table.insert(newInbox, item)
        end
    end
    
    DataManager.SetValue(player, "Inbox", newInbox)
    
    -- Client updaten
    RemoteIndex.FireClient("Inbox_Update", player, newInbox)
    
    return {
        Success = true,
        ClaimedCount = claimedCount,
        TotalReward = totalReward,
    }
end

--[[
    =============================================
    DEBUG (Nur im Debug-Modus)
    =============================================
]]

-- Debug_Command: Debug-Befehle
RemoteIndex.Get("Debug_Command").OnServerInvoke = function(player, command, ...)
    if not GameConfig.Debug.Enabled then
        return { Success = false, Error = "Debug-Modus nicht aktiviert" }
    end
    
    local args = {...}
    
    if command == "AddGold" then
        local amount = args[1] or 1000
        CurrencyService.AddGold(player, amount, CurrencyService.TransactionType.AdminGrant, "Debug")
        return { Success = true, Message = "+" .. amount .. " Gold" }
        
    elseif command == "AddGems" then
        local amount = args[1] or 100
        CurrencyService.AddGems(player, amount, CurrencyService.TransactionType.AdminGrant, "Debug")
        return { Success = true, Message = "+" .. amount .. " Gems" }
        
    elseif command == "SetLevel" then
        local level = args[1] or 10
        DataManager.SetValue(player, "Dungeon.Level", level)
        RemoteIndex.FireClient("Dungeon_Update", player, { Level = level })
        return { Success = true, Message = "Level = " .. level }
        
    elseif command == "ResetData" then
        DataManager.ResetData(player)
        return { Success = true, Message = "Daten zurückgesetzt" }
        
    elseif command == "UnlockAll" then
        local data = DataManager.GetData(player)
        if data then
            -- Alle Fallen freischalten
            for trapId, _ in pairs(TrapConfig.Traps) do
                data.Dungeon.UnlockedTraps[trapId] = true
            end
            DataManager.SetValue(player, "Dungeon.UnlockedTraps", data.Dungeon.UnlockedTraps)
            
            -- Alle Monster freischalten
            for monsterId, config in pairs(MonsterConfig.Monsters) do
                if config.Purchasable ~= false then
                    data.Dungeon.UnlockedMonsters[monsterId] = true
                end
            end
            DataManager.SetValue(player, "Dungeon.UnlockedMonsters", data.Dungeon.UnlockedMonsters)
            
            -- Alle Helden freischalten
            for heroId, _ in pairs(HeroConfig.Heroes) do
                data.Heroes.Unlocked[heroId] = true
            end
            DataManager.SetValue(player, "Heroes.Unlocked", data.Heroes.Unlocked)
            
            -- Client updaten
            RemoteIndex.FireClient("Dungeon_Update", player, {
                UnlockedTraps = data.Dungeon.UnlockedTraps,
                UnlockedMonsters = data.Dungeon.UnlockedMonsters,
            })
            RemoteIndex.FireClient("Heroes_Update", player, {
                Unlocked = data.Heroes.Unlocked,
            })
        end
        return { Success = true, Message = "Alles freigeschaltet" }
        
    elseif command == "SkipCooldown" then
        DataManager.SetValue(player, "Cooldowns.LastRaidTime", 0)
        return { Success = true, Message = "Raid-Cooldown zurückgesetzt" }
        
    else
        return { Success = false, Error = "Unbekannter Befehl: " .. tostring(command) }
    end
end

print("[ServerMain] Remote Handler verbunden!")

-------------------------------------------------
-- RAID-SYSTEM EVENTS VERBINDEN
-------------------------------------------------

-- XP nach Raid verteilen
RaidSystem.Signals.RaidEnded:Connect(function(player, result)
    HeroSystem.DistributeRaidXP(player, result)
end)

print("[ServerMain] System-Events verbunden!")

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
