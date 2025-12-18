--[[
    RewardSystem.lua
    Zentrales Belohnungssystem
    Pfad: ServerScriptService/Server/Systems/RewardSystem
    
    Verantwortlich für:
    - Loot-Tabellen und Drop-Berechnung
    - Achievement-Tracking
    - Milestone-Belohnungen
    - Daily/Weekly Rewards
    - Prestige-Belohnungen
    
    WICHTIG: Nutzt CurrencyService für Auszahlungen!
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
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Service/Manager-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil
local CurrencyService = nil

local RewardSystem = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Lucky Drop Chance (Bonus-Drop)
    LuckyDropChance = 0.05,         -- 5%
    LuckyDropMultiplier = 2.0,      -- Doppelte Belohnung
    
    -- First-Time Bonus
    FirstTimeBonus = 1.5,           -- 50% mehr beim ersten Mal
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- LOOT TABELLEN
-------------------------------------------------
local LOOT_TABLES = {
    -- Raid-Belohnungen basierend auf Erfolg
    RaidVictory = {
        Currency = {
            Gold = { Min = 200, Max = 500, BaseMultiplier = 1.0 },
            Gems = { Min = 2, Max = 5, Chance = 0.3 },
        },
        BonusDrops = {
            { Type = "GoldBonus", Chance = 0.15, Amount = 100 },
            { Type = "GemBonus", Chance = 0.05, Amount = 3 },
            { Type = "XPBonus", Chance = 0.2, Amount = 50 },
        },
    },
    
    RaidPartial = {
        Currency = {
            Gold = { Min = 50, Max = 150, BaseMultiplier = 1.0 },
            Gems = { Min = 0, Max = 2, Chance = 0.1 },
        },
        BonusDrops = {
            { Type = "GoldBonus", Chance = 0.1, Amount = 50 },
        },
    },
    
    -- Defense-Belohnungen
    DefenseSuccess = {
        Currency = {
            Gold = { Min = 100, Max = 300, BaseMultiplier = 1.0 },
            Gems = { Min = 1, Max = 3, Chance = 0.2 },
        },
        BonusDrops = {
            { Type = "GoldBonus", Chance = 0.1, Amount = 75 },
            { Type = "DefenseXP", Chance = 0.25, Amount = 30 },
        },
    },
    
    -- Daily Login Rewards (Tag 1-7, dann wiederholen)
    DailyLogin = {
        [1] = { Gold = 100, Gems = 0 },
        [2] = { Gold = 150, Gems = 0 },
        [3] = { Gold = 200, Gems = 1 },
        [4] = { Gold = 250, Gems = 1 },
        [5] = { Gold = 300, Gems = 2 },
        [6] = { Gold = 400, Gems = 2 },
        [7] = { Gold = 500, Gems = 5 },  -- Wochenbonus
    },
    
    -- Level-Up Belohnungen
    LevelUp = {
        [5]  = { Gold = 500, Gems = 5, Title = "Anfänger" },
        [10] = { Gold = 1000, Gems = 10, Title = "Lehrling" },
        [15] = { Gold = 1500, Gems = 15 },
        [20] = { Gold = 2500, Gems = 25, Title = "Geselle" },
        [25] = { Gold = 3500, Gems = 35 },
        [30] = { Gold = 5000, Gems = 50, Title = "Experte" },
        [40] = { Gold = 7500, Gems = 75, Title = "Meister" },
        [50] = { Gold = 10000, Gems = 100, Title = "Großmeister" },
        [75] = { Gold = 25000, Gems = 250, Title = "Legende" },
        [100] = { Gold = 50000, Gems = 500, Title = "Dungeon Lord" },
    },
}

-------------------------------------------------
-- ACHIEVEMENTS
-------------------------------------------------
local ACHIEVEMENTS = {
    -- Dungeon Building
    FirstRoom = {
        Id = "first_room",
        Name = "Baumeister",
        Description = "Baue deinen ersten Raum",
        Reward = { Gold = 100, Gems = 1 },
        Hidden = false,
    },
    TenRooms = {
        Id = "ten_rooms",
        Name = "Architekt",
        Description = "Besitze 10 Räume",
        Reward = { Gold = 500, Gems = 5 },
        Hidden = false,
    },
    MaxRooms = {
        Id = "max_rooms",
        Name = "Dungeon-Imperium",
        Description = "Erreiche die maximale Raumanzahl",
        Reward = { Gold = 2500, Gems = 25 },
        Hidden = false,
    },
    
    -- Traps
    FirstTrap = {
        Id = "first_trap",
        Name = "Fallensteller",
        Description = "Platziere deine erste Falle",
        Reward = { Gold = 50, Gems = 0 },
        Hidden = false,
    },
    AllTrapTypes = {
        Id = "all_trap_types",
        Name = "Fallen-Sammler",
        Description = "Schalte alle Fallentypen frei",
        Reward = { Gold = 1000, Gems = 15 },
        Hidden = false,
    },
    
    -- Monsters
    FirstMonster = {
        Id = "first_monster",
        Name = "Monstermeister",
        Description = "Platziere dein erstes Monster",
        Reward = { Gold = 50, Gems = 0 },
        Hidden = false,
    },
    HundredMonsters = {
        Id = "hundred_monsters",
        Name = "Monsterhorde",
        Description = "Platziere insgesamt 100 Monster",
        Reward = { Gold = 750, Gems = 10 },
        Hidden = false,
    },
    
    -- Heroes
    FirstHero = {
        Id = "first_hero",
        Name = "Rekrutierer",
        Description = "Rekrutiere deinen ersten Helden",
        Reward = { Gold = 100, Gems = 2 },
        Hidden = false,
    },
    LegendaryHero = {
        Id = "legendary_hero",
        Name = "Legendenjäger",
        Description = "Rekrutiere einen legendären Helden",
        Reward = { Gold = 1000, Gems = 20 },
        Hidden = false,
    },
    FullTeam = {
        Id = "full_team",
        Name = "Kampfbereit",
        Description = "Stelle ein vollständiges Helden-Team zusammen",
        Reward = { Gold = 250, Gems = 5 },
        Hidden = false,
    },
    
    -- Raids
    FirstRaid = {
        Id = "first_raid",
        Name = "Räuber",
        Description = "Führe deinen ersten Raid durch",
        Reward = { Gold = 150, Gems = 2 },
        Hidden = false,
    },
    TenRaidWins = {
        Id = "ten_raid_wins",
        Name = "Plünderer",
        Description = "Gewinne 10 Raids",
        Reward = { Gold = 500, Gems = 10 },
        Hidden = false,
    },
    HundredRaidWins = {
        Id = "hundred_raid_wins",
        Name = "Kriegsherr",
        Description = "Gewinne 100 Raids",
        Reward = { Gold = 2500, Gems = 50 },
        Hidden = false,
    },
    PerfectRaid = {
        Id = "perfect_raid",
        Name = "Perfektionist",
        Description = "Gewinne einen Raid ohne Heldenverlust",
        Reward = { Gold = 300, Gems = 5 },
        Hidden = false,
    },
    
    -- Defense
    FirstDefense = {
        Id = "first_defense",
        Name = "Verteidiger",
        Description = "Verteidige deinen Dungeon erfolgreich",
        Reward = { Gold = 150, Gems = 2 },
        Hidden = false,
    },
    TenDefenseWins = {
        Id = "ten_defense_wins",
        Name = "Bollwerk",
        Description = "Verteidige 10 Angriffe erfolgreich",
        Reward = { Gold = 500, Gems = 10 },
        Hidden = false,
    },
    KillHundredHeroes = {
        Id = "kill_hundred_heroes",
        Name = "Heldenschreck",
        Description = "Besiege 100 angreifende Helden",
        Reward = { Gold = 750, Gems = 15 },
        Hidden = false,
    },
    
    -- Prestige
    FirstPrestige = {
        Id = "first_prestige",
        Name = "Neuanfang",
        Description = "Erreiche dein erstes Prestige",
        Reward = { Gold = 500, Gems = 25 },
        Hidden = false,
    },
    MaxPrestige = {
        Id = "max_prestige",
        Name = "Transzendenz",
        Description = "Erreiche das maximale Prestige-Level",
        Reward = { Gold = 10000, Gems = 500 },
        Hidden = true,
    },
    
    -- Currency
    Millionaire = {
        Id = "millionaire",
        Name = "Millionär",
        Description = "Besitze 1.000.000 Gold",
        Reward = { Gems = 50 },
        Hidden = false,
    },
    GemCollector = {
        Id = "gem_collector",
        Name = "Juwelier",
        Description = "Sammle insgesamt 1.000 Gems",
        Reward = { Gold = 5000 },
        Hidden = false,
    },
    
    -- Playtime
    OneHour = {
        Id = "one_hour",
        Name = "Zeitvertreib",
        Description = "Spiele 1 Stunde",
        Reward = { Gold = 100, Gems = 1 },
        Hidden = false,
    },
    TenHours = {
        Id = "ten_hours",
        Name = "Hingabe",
        Description = "Spiele 10 Stunden",
        Reward = { Gold = 500, Gems = 10 },
        Hidden = false,
    },
    HundredHours = {
        Id = "hundred_hours",
        Name = "Veteran",
        Description = "Spiele 100 Stunden",
        Reward = { Gold = 2500, Gems = 50 },
        Hidden = true,
    },
    
    -- Secret
    SecretRoom = {
        Id = "secret_room",
        Name = "Geheimnis",
        Description = "???",
        Reward = { Gold = 1000, Gems = 25 },
        Hidden = true,
    },
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
RewardSystem.Signals = {
    RewardGranted = SignalUtil.new(),           -- (player, rewardType, reward)
    AchievementUnlocked = SignalUtil.new(),     -- (player, achievementId, achievement)
    MilestoneReached = SignalUtil.new(),        -- (player, milestoneType, level)
    LuckyDrop = SignalUtil.new(),               -- (player, dropType, amount)
    LevelUpReward = SignalUtil.new(),           -- (player, level, reward)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[RewardSystem]", ...)
    end
end

--[[
    Würfelt ob Lucky Drop auftritt
    @return: boolean
]]
local function rollLuckyDrop()
    return math.random() < CONFIG.LuckyDropChance
end

--[[
    Berechnet zufälligen Wert zwischen Min und Max
    @param min: Minimum
    @param max: Maximum
    @return: Zufallswert
]]
local function randomRange(min, max)
    return math.random(min, max)
end

--[[
    Berechnet Level-basierten Multiplikator
    @param level: Dungeon-Level
    @return: Multiplikator
]]
local function getLevelMultiplier(level)
    return 1 + (level - 1) * 0.05  -- +5% pro Level
end

--[[
    Berechnet Prestige-basierten Multiplikator
    @param prestigeLevel: Prestige-Level
    @return: Multiplikator
]]
local function getPrestigeMultiplier(prestigeLevel)
    return 1 + prestigeLevel * GameConfig.Prestige.BonusPerPrestige
end

--[[
    Sendet Achievement-Update an Client
    @param player: Der Spieler
    @param achievement: Achievement-Daten
]]
local function sendAchievementNotification(player, achievement)
    RemoteIndex.FireClient("Achievement_Unlocked", player, {
        Id = achievement.Id,
        Name = achievement.Name,
        Description = achievement.Description,
        Reward = achievement.Reward,
    })
    
    if PlayerManager then
        PlayerManager.SendNotification(
            player,
            "🏆 Achievement freigeschaltet!",
            achievement.Name,
            "Success"
        )
    end
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert das RewardSystem
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
    @param currencyServiceRef: Referenz zum CurrencyService
]]
function RewardSystem.Initialize(dataManagerRef, playerManagerRef, currencyServiceRef)
    debugPrint("Initialisiere RewardSystem...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    CurrencyService = currencyServiceRef
    
    debugPrint("RewardSystem initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - LOOT BERECHNUNG
-------------------------------------------------

--[[
    Berechnet Loot aus einer Loot-Tabelle
    @param lootTableName: Name der Loot-Tabelle
    @param level: Dungeon-Level für Skalierung
    @param prestigeLevel: Prestige-Level
    @param modifiers: Zusätzliche Modifikatoren { BonusGold, BonusGems, etc. }
    @return: reward { Gold, Gems, BonusDrops }
]]
function RewardSystem.CalculateLoot(lootTableName, level, prestigeLevel, modifiers)
    local lootTable = LOOT_TABLES[lootTableName]
    if not lootTable then
        debugPrint("Loot-Tabelle nicht gefunden: " .. tostring(lootTableName))
        return { Gold = 0, Gems = 0, BonusDrops = {} }
    end
    
    level = level or 1
    prestigeLevel = prestigeLevel or 0
    modifiers = modifiers or {}
    
    local levelMult = getLevelMultiplier(level)
    local prestigeMult = getPrestigeMultiplier(prestigeLevel)
    local totalMult = levelMult * prestigeMult
    
    local reward = {
        Gold = 0,
        Gems = 0,
        BonusDrops = {},
    }
    
    -- Währung berechnen
    if lootTable.Currency then
        -- Gold
        if lootTable.Currency.Gold then
            local goldData = lootTable.Currency.Gold
            local baseGold = randomRange(goldData.Min, goldData.Max)
            local goldMult = goldData.BaseMultiplier or 1.0
            
            reward.Gold = math.floor(baseGold * goldMult * totalMult)
            
            -- Bonus-Modifikator
            if modifiers.BonusGold then
                reward.Gold = math.floor(reward.Gold * (1 + modifiers.BonusGold))
            end
        end
        
        -- Gems
        if lootTable.Currency.Gems then
            local gemData = lootTable.Currency.Gems
            local dropChance = gemData.Chance or 1.0
            
            if math.random() < dropChance then
                reward.Gems = randomRange(gemData.Min, gemData.Max)
                
                -- Prestige-Bonus auf Gems (geringer)
                reward.Gems = math.floor(reward.Gems * (1 + prestigeLevel * 0.02))
                
                if modifiers.BonusGems then
                    reward.Gems = math.floor(reward.Gems * (1 + modifiers.BonusGems))
                end
            end
        end
    end
    
    -- Bonus-Drops
    if lootTable.BonusDrops then
        for _, drop in ipairs(lootTable.BonusDrops) do
            if math.random() < drop.Chance then
                table.insert(reward.BonusDrops, {
                    Type = drop.Type,
                    Amount = math.floor(drop.Amount * totalMult),
                })
            end
        end
    end
    
    -- Lucky Drop Check
    if rollLuckyDrop() then
        reward.Gold = math.floor(reward.Gold * CONFIG.LuckyDropMultiplier)
        reward.Gems = math.floor(reward.Gems * CONFIG.LuckyDropMultiplier)
        reward.IsLucky = true
    end
    
    return reward
end

--[[
    Gibt Belohnung an Spieler
    @param player: Der Spieler
    @param reward: Belohnung { Gold, Gems, ... }
    @param rewardType: Typ für Tracking
    @param source: Quelle (optional)
    @return: actualReward
]]
function RewardSystem.GrantReward(player, reward, rewardType, source)
    if not CurrencyService then
        debugPrint("CurrencyService nicht verfügbar")
        return reward
    end
    
    local actualReward = CurrencyService.GiveReward(
        player,
        reward,
        CurrencyService.TransactionType.AchievementReward,
        source or rewardType
    )
    
    -- Bonus-Drops verarbeiten
    if reward.BonusDrops then
        for _, drop in ipairs(reward.BonusDrops) do
            if drop.Type == "GoldBonus" then
                CurrencyService.AddGold(
                    player,
                    drop.Amount,
                    CurrencyService.TransactionType.AchievementReward,
                    "BonusDrop"
                )
                actualReward.Gold = (actualReward.Gold or 0) + drop.Amount
            elseif drop.Type == "GemBonus" then
                CurrencyService.AddGems(
                    player,
                    drop.Amount,
                    CurrencyService.TransactionType.AchievementReward,
                    "BonusDrop"
                )
                actualReward.Gems = (actualReward.Gems or 0) + drop.Amount
            end
        end
    end
    
    -- Lucky Drop Benachrichtigung
    if reward.IsLucky and PlayerManager then
        PlayerManager.SendNotification(
            player,
            "🍀 Lucky Drop!",
            "Doppelte Belohnung!",
            "Success"
        )
        
        RewardSystem.Signals.LuckyDrop:Fire(player, rewardType, actualReward)
    end
    
    RewardSystem.Signals.RewardGranted:Fire(player, rewardType, actualReward)
    
    debugPrint(player.Name .. " erhält " .. (actualReward.Gold or 0) .. " Gold, " .. (actualReward.Gems or 0) .. " Gems")
    
    return actualReward
end

-------------------------------------------------
-- PUBLIC API - RAID REWARDS
-------------------------------------------------

--[[
    Berechnet und gibt Raid-Belohnung
    @param player: Der Spieler
    @param raidResult: Ergebnis des Raids
    @return: reward
]]
function RewardSystem.GrantRaidReward(player, raidResult)
    local data = DataManager and DataManager.GetData(player)
    if not data then return { Gold = 0, Gems = 0 } end
    
    local dungeonLevel = data.Dungeon.Level or 1
    local prestigeLevel = data.Prestige.Level or 0
    
    -- Loot-Tabelle basierend auf Ergebnis
    local lootTableName
    if raidResult.Status == "Victory" then
        lootTableName = "RaidVictory"
    else
        lootTableName = "RaidPartial"
    end
    
    -- Progress-Modifikator
    local progressMult = raidResult.Stats.RoomsCleared / math.max(1, raidResult.TotalRooms)
    
    local modifiers = {
        BonusGold = progressMult * 0.5,  -- Bis zu 50% Bonus
    }
    
    -- Perfekter Raid Bonus
    if raidResult.Status == "Victory" and raidResult.Stats.HeroesLost == 0 then
        modifiers.BonusGold = (modifiers.BonusGold or 0) + 0.25
        modifiers.BonusGems = 0.5
    end
    
    -- Loot berechnen
    local reward = RewardSystem.CalculateLoot(
        lootTableName,
        raidResult.TargetLevel or dungeonLevel,
        prestigeLevel,
        modifiers
    )
    
    -- XP hinzufügen
    reward.XP = raidResult.Rewards and raidResult.Rewards.XP or 0
    
    -- Belohnung geben
    return RewardSystem.GrantReward(player, reward, "RaidReward", "Raid:" .. (raidResult.RaidId or "unknown"))
end

--[[
    Berechnet und gibt Defense-Belohnung
    @param player: Der verteidigende Spieler
    @param defenseResult: Ergebnis der Verteidigung
    @return: reward
]]
function RewardSystem.GrantDefenseReward(player, defenseResult)
    local data = DataManager and DataManager.GetData(player)
    if not data then return { Gold = 0, Gems = 0 } end
    
    local dungeonLevel = data.Dungeon.Level or 1
    local prestigeLevel = data.Prestige.Level or 0
    
    -- Basis-Belohnung für Defense
    local modifiers = {
        BonusGold = defenseResult.HeroesKilled * 0.1,  -- +10% pro getötetem Held
    }
    
    -- Erfolgreiche Verteidigung Bonus
    if not defenseResult.AttackerWon then
        modifiers.BonusGold = (modifiers.BonusGold or 0) + 0.5
        modifiers.BonusGems = 0.25
    end
    
    local reward = RewardSystem.CalculateLoot(
        "DefenseSuccess",
        dungeonLevel,
        prestigeLevel,
        modifiers
    )
    
    return RewardSystem.GrantReward(player, reward, "DefenseReward", "Defense")
end

-------------------------------------------------
-- PUBLIC API - ACHIEVEMENTS
-------------------------------------------------

--[[
    Prüft und schaltet Achievement frei
    @param player: Der Spieler
    @param achievementId: ID des Achievements
    @return: success, alreadyUnlocked
]]
function RewardSystem.UnlockAchievement(player, achievementId)
    local data = DataManager and DataManager.GetData(player)
    if not data then return false, false end
    
    -- Achievement existiert?
    local achievement = ACHIEVEMENTS[achievementId]
    if not achievement then
        debugPrint("Achievement nicht gefunden: " .. tostring(achievementId))
        return false, false
    end
    
    -- Bereits freigeschaltet?
    if data.Progress.Achievements[achievement.Id] then
        return false, true
    end
    
    -- Achievement freischalten
    DataManager.SetValue(player, "Progress.Achievements." .. achievement.Id, {
        UnlockedAt = os.time(),
        Claimed = false,
    })
    
    -- Belohnung sofort geben
    if achievement.Reward then
        RewardSystem.GrantReward(
            player,
            achievement.Reward,
            "Achievement",
            "Achievement:" .. achievement.Id
        )
    end
    
    -- Benachrichtigung
    sendAchievementNotification(player, achievement)
    
    -- Signal
    RewardSystem.Signals.AchievementUnlocked:Fire(player, achievement.Id, achievement)
    
    debugPrint(player.Name .. " hat Achievement freigeschaltet: " .. achievement.Name)
    
    return true, false
end

--[[
    Prüft Achievement-Fortschritt basierend auf Stats
    @param player: Der Spieler
    @param statType: Typ der Statistik
    @param value: Aktueller Wert
]]
function RewardSystem.CheckAchievementProgress(player, statType, value)
    -- Mapping von Stats zu Achievements
    local achievementChecks = {
        RoomCount = {
            { threshold = 1, achievement = "FirstRoom" },
            { threshold = 10, achievement = "TenRooms" },
            { threshold = GameConfig.Dungeon.MaxRooms, achievement = "MaxRooms" },
        },
        TrapCount = {
            { threshold = 1, achievement = "FirstTrap" },
        },
        MonsterCount = {
            { threshold = 1, achievement = "FirstMonster" },
            { threshold = 100, achievement = "HundredMonsters" },
        },
        HeroCount = {
            { threshold = 1, achievement = "FirstHero" },
        },
        RaidsSuccessful = {
            { threshold = 1, achievement = "FirstRaid" },
            { threshold = 10, achievement = "TenRaidWins" },
            { threshold = 100, achievement = "HundredRaidWins" },
        },
        SuccessfulDefenses = {
            { threshold = 1, achievement = "FirstDefense" },
            { threshold = 10, achievement = "TenDefenseWins" },
        },
        HeroesKilled = {
            { threshold = 100, achievement = "KillHundredHeroes" },
        },
        PrestigeLevel = {
            { threshold = 1, achievement = "FirstPrestige" },
            { threshold = GameConfig.Prestige.MaxPrestige, achievement = "MaxPrestige" },
        },
        TotalGoldEarned = {
            { threshold = 1000000, achievement = "Millionaire" },
        },
        TotalGemsEarned = {
            { threshold = 1000, achievement = "GemCollector" },
        },
        TotalPlayTime = {
            { threshold = 3600, achievement = "OneHour" },
            { threshold = 36000, achievement = "TenHours" },
            { threshold = 360000, achievement = "HundredHours" },
        },
    }
    
    local checks = achievementChecks[statType]
    if not checks then return end
    
    for _, check in ipairs(checks) do
        if value >= check.threshold then
            RewardSystem.UnlockAchievement(player, check.achievement)
        end
    end
end

--[[
    Gibt alle Achievements zurück
    @return: Achievements-Tabelle
]]
function RewardSystem.GetAllAchievements()
    return ACHIEVEMENTS
end

--[[
    Gibt Achievement-Fortschritt eines Spielers zurück
    @param player: Der Spieler
    @return: { total, unlocked, percentage, achievements }
]]
function RewardSystem.GetAchievementProgress(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return { total = 0, unlocked = 0, percentage = 0, achievements = {} }
    end
    
    local total = 0
    local unlocked = 0
    local achievements = {}
    
    for key, achievement in pairs(ACHIEVEMENTS) do
        total = total + 1
        
        local isUnlocked = data.Progress.Achievements[achievement.Id] ~= nil
        if isUnlocked then
            unlocked = unlocked + 1
        end
        
        -- Versteckte Achievements nur zeigen wenn freigeschaltet
        if not achievement.Hidden or isUnlocked then
            achievements[achievement.Id] = {
                Name = achievement.Name,
                Description = isUnlocked and achievement.Description or (achievement.Hidden and "???" or achievement.Description),
                Reward = achievement.Reward,
                IsUnlocked = isUnlocked,
                Hidden = achievement.Hidden,
            }
        end
    end
    
    return {
        total = total,
        unlocked = unlocked,
        percentage = total > 0 and (unlocked / total * 100) or 0,
        achievements = achievements,
    }
end

-------------------------------------------------
-- PUBLIC API - LEVEL UP REWARDS
-------------------------------------------------

--[[
    Gibt Level-Up Belohnung
    @param player: Der Spieler
    @param newLevel: Das neue Level
    @return: reward oder nil
]]
function RewardSystem.GrantLevelUpReward(player, newLevel)
    local levelReward = LOOT_TABLES.LevelUp[newLevel]
    if not levelReward then
        return nil
    end
    
    local reward = {
        Gold = levelReward.Gold or 0,
        Gems = levelReward.Gems or 0,
    }
    
    -- Belohnung geben
    local actualReward = RewardSystem.GrantReward(
        player,
        reward,
        "LevelUp",
        "Level:" .. newLevel
    )
    
    -- Titel vergeben (falls vorhanden)
    if levelReward.Title and DataManager then
        DataManager.SetValue(player, "Profile.Title", levelReward.Title)
        
        if PlayerManager then
            PlayerManager.SendNotification(
                player,
                "Neuer Titel!",
                "Du bist jetzt: " .. levelReward.Title,
                "Success"
            )
        end
    end
    
    RewardSystem.Signals.LevelUpReward:Fire(player, newLevel, actualReward)
    RewardSystem.Signals.MilestoneReached:Fire(player, "Level", newLevel)
    
    return actualReward
end

-------------------------------------------------
-- PUBLIC API - DAILY REWARDS
-------------------------------------------------

--[[
    Gibt Daily Login Reward
    @param player: Der Spieler
    @param streakDay: Tag des Streaks (1-7)
    @return: reward
]]
function RewardSystem.GrantDailyReward(player, streakDay)
    -- Tag auf 1-7 normalisieren
    local day = ((streakDay - 1) % 7) + 1
    
    local dailyReward = LOOT_TABLES.DailyLogin[day]
    if not dailyReward then
        dailyReward = LOOT_TABLES.DailyLogin[1]
    end
    
    local reward = {
        Gold = dailyReward.Gold or 0,
        Gems = dailyReward.Gems or 0,
    }
    
    return RewardSystem.GrantReward(player, reward, "DailyLogin", "Daily:Day" .. day)
end

-------------------------------------------------
-- PUBLIC API - FIRST TIME BONUS
-------------------------------------------------

--[[
    Gibt First-Time Bonus für eine Aktion
    @param player: Der Spieler
    @param actionType: Typ der Aktion
    @param baseReward: Basis-Belohnung
    @return: reward (mit Bonus falls First-Time)
]]
function RewardSystem.GrantFirstTimeBonus(player, actionType, baseReward)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return RewardSystem.GrantReward(player, baseReward, actionType)
    end
    
    -- Prüfen ob First-Time
    local firstTimeKey = "FirstTime_" .. actionType
    if data.Progress[firstTimeKey] then
        return RewardSystem.GrantReward(player, baseReward, actionType)
    end
    
    -- First-Time markieren
    DataManager.SetValue(player, "Progress." .. firstTimeKey, true)
    
    -- Bonus anwenden
    local bonusReward = {
        Gold = math.floor((baseReward.Gold or 0) * CONFIG.FirstTimeBonus),
        Gems = math.floor((baseReward.Gems or 0) * CONFIG.FirstTimeBonus),
    }
    
    if PlayerManager then
        PlayerManager.SendNotification(
            player,
            "Erstes Mal Bonus!",
            "50% extra Belohnung!",
            "Success"
        )
    end
    
    return RewardSystem.GrantReward(player, bonusReward, actionType .. "_FirstTime")
end

-------------------------------------------------
-- PUBLIC API - UTILITY
-------------------------------------------------

--[[
    Gibt Loot-Tabelle zurück
    @param tableName: Name der Tabelle
    @return: Loot-Tabelle oder nil
]]
function RewardSystem.GetLootTable(tableName)
    return LOOT_TABLES[tableName]
end

--[[
    Gibt alle Level-Rewards zurück
    @return: Level-Rewards Tabelle
]]
function RewardSystem.GetLevelRewards()
    return LOOT_TABLES.LevelUp
end

--[[
    Berechnet erwarteten Loot (für UI-Vorschau)
    @param lootTableName: Name der Loot-Tabelle
    @param level: Level
    @param prestigeLevel: Prestige-Level
    @return: { MinGold, MaxGold, AvgGold, GemChance }
]]
function RewardSystem.GetExpectedLoot(lootTableName, level, prestigeLevel)
    local lootTable = LOOT_TABLES[lootTableName]
    if not lootTable or not lootTable.Currency then
        return { MinGold = 0, MaxGold = 0, AvgGold = 0, GemChance = 0 }
    end
    
    local mult = getLevelMultiplier(level or 1) * getPrestigeMultiplier(prestigeLevel or 0)
    
    local result = {
        MinGold = 0,
        MaxGold = 0,
        AvgGold = 0,
        GemChance = 0,
        MinGems = 0,
        MaxGems = 0,
    }
    
    if lootTable.Currency.Gold then
        result.MinGold = math.floor(lootTable.Currency.Gold.Min * mult)
        result.MaxGold = math.floor(lootTable.Currency.Gold.Max * mult)
        result.AvgGold = math.floor((result.MinGold + result.MaxGold) / 2)
    end
    
    if lootTable.Currency.Gems then
        result.GemChance = lootTable.Currency.Gems.Chance or 1
        result.MinGems = lootTable.Currency.Gems.Min
        result.MaxGems = lootTable.Currency.Gems.Max
    end
    
    return result
end

return RewardSystem
