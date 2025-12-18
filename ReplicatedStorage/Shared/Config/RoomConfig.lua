--[[
    RoomConfig.lua
    Definitionen aller Raum-Typen für den Dungeon
    Pfad: ReplicatedStorage/Shared/Config/RoomConfig
    
    Jeder Raum hat:
    - Eindeutige ID
    - Größe und Layout
    - Kosten (Gold/Gems)
    - Slots für Fallen und Monster
    - Passive Boni
    - Freischalt-Bedingungen
]]

local RoomConfig = {}

-------------------------------------------------
-- RAUM-KATEGORIEN
-------------------------------------------------
RoomConfig.Categories = {
    Corridor = {
        Name = "Korridor",
        Description = "Schmale Gänge für Fallen",
        Icon = "rbxassetid://0",
    },
    Chamber = {
        Name = "Kammer",
        Description = "Mittelgroße Räume für Kämpfe",
        Icon = "rbxassetid://0",
    },
    Hall = {
        Name = "Halle",
        Description = "Große Räume für epische Schlachten",
        Icon = "rbxassetid://0",
    },
    Special = {
        Name = "Spezial",
        Description = "Einzigartige Räume mit besonderen Effekten",
        Icon = "rbxassetid://0",
    },
}

-------------------------------------------------
-- RAUM-GRÖSSEN (in Studs)
-------------------------------------------------
RoomConfig.Sizes = {
    Small = {
        Width = 20,
        Length = 30,
        Height = 15,
    },
    Medium = {
        Width = 30,
        Length = 40,
        Height = 18,
    },
    Large = {
        Width = 50,
        Length = 60,
        Height = 25,
    },
    Massive = {
        Width = 80,
        Length = 100,
        Height = 35,
    },
}

-------------------------------------------------
-- RAUM-TYPEN
-------------------------------------------------
RoomConfig.Rooms = {
    -------------------------------------------------
    -- KORRIDORE (Starter-Räume)
    -------------------------------------------------
    ["stone_corridor"] = {
        Id = "stone_corridor",
        Name = "Steinerner Korridor",
        Description = "Ein einfacher Gang aus grobem Stein.",
        Category = "Corridor",
        Size = "Small",
        
        -- Slots
        TrapSlots = 3,
        MonsterSlots = 1,
        
        -- Kosten
        PurchaseCost = 100,
        PurchaseGems = 0,
        
        -- Freischaltung
        UnlockRequirement = {
            Type = "None",  -- Sofort verfügbar
        },
        
        -- Passive Boni
        Bonuses = {},
        
        -- Visuals
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
    
    ["spike_corridor"] = {
        Id = "spike_corridor",
        Name = "Stachel-Korridor",
        Description = "Ein Gang mit versteckten Stachelfallen im Boden.",
        Category = "Corridor",
        Size = "Small",
        
        TrapSlots = 5,
        MonsterSlots = 0,
        
        PurchaseCost = 300,
        PurchaseGems = 0,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 3,
        },
        
        Bonuses = {
            {
                Type = "TrapDamage",
                TrapCategory = "Floor",
                Value = 0.15,  -- +15% Schaden für Bodenfallen
            },
        },
        
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
    
    ["arrow_corridor"] = {
        Id = "arrow_corridor",
        Name = "Pfeil-Korridor",
        Description = "Wände voller versteckter Pfeilschlitze.",
        Category = "Corridor",
        Size = "Small",
        
        TrapSlots = 4,
        MonsterSlots = 0,
        
        PurchaseCost = 350,
        PurchaseGems = 0,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 5,
        },
        
        Bonuses = {
            {
                Type = "TrapDamage",
                TrapCategory = "Wall",
                Value = 0.20,  -- +20% Schaden für Wandfallen
            },
        },
        
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- KAMMERN (Standard-Räume)
    -------------------------------------------------
    ["guard_chamber"] = {
        Id = "guard_chamber",
        Name = "Wachkammer",
        Description = "Ein Raum für Monster-Wachen.",
        Category = "Chamber",
        Size = "Medium",
        
        TrapSlots = 2,
        MonsterSlots = 3,
        
        PurchaseCost = 500,
        PurchaseGems = 0,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 2,
        },
        
        Bonuses = {
            {
                Type = "MonsterHealth",
                Value = 0.10,  -- +10% HP für Monster in diesem Raum
            },
        },
        
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
    
    ["armory"] = {
        Id = "armory",
        Name = "Waffenkammer",
        Description = "Monster hier sind besser bewaffnet.",
        Category = "Chamber",
        Size = "Medium",
        
        TrapSlots = 2,
        MonsterSlots = 3,
        
        PurchaseCost = 800,
        PurchaseGems = 0,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 7,
        },
        
        Bonuses = {
            {
                Type = "MonsterDamage",
                Value = 0.20,  -- +20% Schaden für Monster
            },
        },
        
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
    
    ["torture_chamber"] = {
        Id = "torture_chamber",
        Name = "Folterkammer",
        Description = "Ein grausamer Raum voller Fallen.",
        Category = "Chamber",
        Size = "Medium",
        
        TrapSlots = 5,
        MonsterSlots = 1,
        
        PurchaseCost = 1000,
        PurchaseGems = 5,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 10,
        },
        
        Bonuses = {
            {
                Type = "TrapCooldown",
                Value = -0.15,  -- -15% Cooldown für alle Fallen
            },
        },
        
        Theme = "Dark",
        AssetId = "rbxassetid://0",
    },
    
    ["crypt"] = {
        Id = "crypt",
        Name = "Gruft",
        Description = "Untote sind hier besonders stark.",
        Category = "Chamber",
        Size = "Medium",
        
        TrapSlots = 2,
        MonsterSlots = 4,
        
        PurchaseCost = 1200,
        PurchaseGems = 10,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 12,
        },
        
        Bonuses = {
            {
                Type = "MonsterBuff",
                MonsterIds = { "skeleton", "archer_skeleton", "necromancer", "vampire", "lich_king" },
                StatBonus = 0.30,  -- +30% alle Stats für Untote
            },
        },
        
        Theme = "Crypt",
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- HALLEN (Große Räume)
    -------------------------------------------------
    ["great_hall"] = {
        Id = "great_hall",
        Name = "Große Halle",
        Description = "Eine imposante Halle für große Schlachten.",
        Category = "Hall",
        Size = "Large",
        
        TrapSlots = 6,
        MonsterSlots = 5,
        
        PurchaseCost = 3000,
        PurchaseGems = 30,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 15,
        },
        
        Bonuses = {
            {
                Type = "MonsterHealth",
                Value = 0.15,
            },
            {
                Type = "MonsterDamage",
                Value = 0.10,
            },
        },
        
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
    
    ["fire_hall"] = {
        Id = "fire_hall",
        Name = "Feuerhalle",
        Description = "Lava fließt durch diesen glühenden Raum.",
        Category = "Hall",
        Size = "Large",
        
        TrapSlots = 8,
        MonsterSlots = 4,
        
        PurchaseCost = 5000,
        PurchaseGems = 50,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 20,
        },
        
        Bonuses = {
            {
                Type = "TrapDamage",
                TrapCategory = "All",
                Value = 0.25,
            },
            {
                Type = "EnvironmentDamage",
                DamagePerSecond = 5,  -- Helden nehmen passiv Schaden
            },
        },
        
        Theme = "Fire",
        AssetId = "rbxassetid://0",
    },
    
    ["frost_hall"] = {
        Id = "frost_hall",
        Name = "Frosthalle",
        Description = "Eisige Kälte verlangsamt alle Eindringlinge.",
        Category = "Hall",
        Size = "Large",
        
        TrapSlots = 6,
        MonsterSlots = 5,
        
        PurchaseCost = 5500,
        PurchaseGems = 55,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 22,
        },
        
        Bonuses = {
            {
                Type = "HeroSlow",
                Value = 0.20,  -- Helden sind 20% langsamer
            },
            {
                Type = "TrapBuff",
                TrapIds = { "freeze_rune" },
                DurationBonus = 1.0,  -- +1 Sekunde Freeze-Dauer
            },
        },
        
        Theme = "Ice",
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- SPEZIAL-RÄUME
    -------------------------------------------------
    ["treasure_vault"] = {
        Id = "treasure_vault",
        Name = "Schatzkammer",
        Description = "Voller Reichtümer - zieht Raids an!",
        Category = "Special",
        Size = "Medium",
        
        TrapSlots = 4,
        MonsterSlots = 2,
        
        PurchaseCost = 10000,
        PurchaseGems = 100,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 25,
        },
        
        -- Limitierung: Nur 1 pro Dungeon
        MaxPerDungeon = 1,
        
        Bonuses = {
            {
                Type = "PassiveIncome",
                Value = 0.50,  -- +50% passives Einkommen
            },
            {
                Type = "RaidAttraction",
                Value = 0.30,  -- +30% Chance von Raids angegriffen zu werden
            },
        },
        
        Theme = "Gold",
        AssetId = "rbxassetid://0",
    },
    
    ["boss_lair"] = {
        Id = "boss_lair",
        Name = "Boss-Versteck",
        Description = "Hier wartet der mächtigste Wächter.",
        Category = "Special",
        Size = "Massive",
        
        TrapSlots = 10,
        MonsterSlots = 1,  -- Nur für Boss-Monster
        
        PurchaseCost = 25000,
        PurchaseGems = 250,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 30,
        },
        
        MaxPerDungeon = 1,
        
        -- Nur Boss-Monster erlaubt
        AllowedMonsterRarities = { "Legendary" },
        
        Bonuses = {
            {
                Type = "MonsterHealth",
                Value = 0.50,  -- +50% HP für den Boss
            },
            {
                Type = "MonsterDamage",
                Value = 0.30,  -- +30% Schaden
            },
            {
                Type = "TrapDamage",
                TrapCategory = "All",
                Value = 0.20,
            },
        },
        
        Theme = "Dark",
        AssetId = "rbxassetid://0",
    },
    
    ["summoning_circle"] = {
        Id = "summoning_circle",
        Name = "Beschwörungskreis",
        Description = "Verstärkt Beschwörungs-Monster enorm.",
        Category = "Special",
        Size = "Medium",
        
        TrapSlots = 2,
        MonsterSlots = 3,
        
        PurchaseCost = 8000,
        PurchaseGems = 80,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 18,
        },
        
        MaxPerDungeon = 2,
        
        Bonuses = {
            {
                Type = "MonsterBuff",
                MonsterIds = { "necromancer", "dark_mage" },
                StatBonus = 0.40,
            },
            {
                Type = "SummonBonus",
                ExtraSummons = 2,  -- +2 maximale Beschwörungen
            },
        },
        
        Theme = "Magic",
        AssetId = "rbxassetid://0",
    },
    
    ["healing_spring"] = {
        Id = "healing_spring",
        Name = "Heilende Quelle",
        Description = "Monster regenerieren hier HP.",
        Category = "Special",
        Size = "Medium",
        
        TrapSlots = 2,
        MonsterSlots = 4,
        
        PurchaseCost = 6000,
        PurchaseGems = 60,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 15,
        },
        
        MaxPerDungeon = 1,
        
        Bonuses = {
            {
                Type = "MonsterRegen",
                HealPerSecond = 10,  -- Monster heilen 10 HP/s
            },
        },
        
        Theme = "Nature",
        AssetId = "rbxassetid://0",
    },
    
    ["maze_section"] = {
        Id = "maze_section",
        Name = "Labyrinth-Abschnitt",
        Description = "Verwirrt Helden und verlängert ihren Weg.",
        Category = "Special",
        Size = "Large",
        
        TrapSlots = 8,
        MonsterSlots = 2,
        
        PurchaseCost = 4000,
        PurchaseGems = 40,
        
        UnlockRequirement = {
            Type = "DungeonLevel",
            Level = 12,
        },
        
        MaxPerDungeon = 3,
        
        Bonuses = {
            {
                Type = "HeroConfusion",
                ConfusionChance = 0.30,  -- 30% Chance dass Helden falsch abbiegen
            },
            {
                Type = "RaidTimeBonus",
                ExtraTime = -15,  -- Raid dauert effektiv 15 Sekunden länger
            },
        },
        
        Theme = "Stone",
        AssetId = "rbxassetid://0",
    },
}

-------------------------------------------------
-- RAUM-THEMES (Visuelle Stile)
-------------------------------------------------
RoomConfig.Themes = {
    Stone = {
        Name = "Stein",
        PrimaryColor = Color3.fromRGB(128, 128, 128),
        SecondaryColor = Color3.fromRGB(80, 80, 80),
        AmbientLight = Color3.fromRGB(180, 180, 200),
    },
    Dark = {
        Name = "Dunkel",
        PrimaryColor = Color3.fromRGB(40, 40, 50),
        SecondaryColor = Color3.fromRGB(20, 20, 30),
        AmbientLight = Color3.fromRGB(100, 80, 120),
    },
    Fire = {
        Name = "Feuer",
        PrimaryColor = Color3.fromRGB(60, 30, 20),
        SecondaryColor = Color3.fromRGB(180, 80, 40),
        AmbientLight = Color3.fromRGB(255, 150, 100),
    },
    Ice = {
        Name = "Eis",
        PrimaryColor = Color3.fromRGB(200, 220, 255),
        SecondaryColor = Color3.fromRGB(150, 180, 220),
        AmbientLight = Color3.fromRGB(180, 200, 255),
    },
    Crypt = {
        Name = "Gruft",
        PrimaryColor = Color3.fromRGB(50, 50, 40),
        SecondaryColor = Color3.fromRGB(80, 70, 60),
        AmbientLight = Color3.fromRGB(150, 180, 150),
    },
    Gold = {
        Name = "Gold",
        PrimaryColor = Color3.fromRGB(180, 150, 80),
        SecondaryColor = Color3.fromRGB(255, 200, 100),
        AmbientLight = Color3.fromRGB(255, 230, 180),
    },
    Magic = {
        Name = "Magisch",
        PrimaryColor = Color3.fromRGB(60, 40, 80),
        SecondaryColor = Color3.fromRGB(150, 100, 200),
        AmbientLight = Color3.fromRGB(180, 150, 255),
    },
    Nature = {
        Name = "Natur",
        PrimaryColor = Color3.fromRGB(60, 80, 50),
        SecondaryColor = Color3.fromRGB(100, 150, 80),
        AmbientLight = Color3.fromRGB(180, 220, 180),
    },
}

-------------------------------------------------
-- UPGRADE-SETTINGS
-------------------------------------------------
RoomConfig.UpgradeSettings = {
    -- Max Upgrade-Level pro Raum
    MaxLevel = 10,
    
    -- Kosten-Multiplikator pro Level
    CostMultiplier = 1.5,
    
    -- Bonus pro Level
    TrapSlotPerLevel = 0,       -- Keine zusätzlichen Slots
    MonsterSlotPerLevel = 0,    -- Keine zusätzlichen Slots
    BonusIncreasePerLevel = 0.10,  -- +10% auf alle Raum-Boni pro Level
}

-------------------------------------------------
-- HILFSFUNKTIONEN
-------------------------------------------------

-- Gibt Raum-Daten per ID zurück
function RoomConfig.GetRoom(roomId)
    return RoomConfig.Rooms[roomId]
end

-- Gibt alle Räume einer Kategorie zurück
function RoomConfig.GetRoomsByCategory(category)
    local result = {}
    for id, room in pairs(RoomConfig.Rooms) do
        if room.Category == category then
            table.insert(result, room)
        end
    end
    return result
end

-- Gibt alle freigeschalteten Räume für ein Dungeon-Level zurück
function RoomConfig.GetUnlockedRooms(dungeonLevel)
    local result = {}
    for id, room in pairs(RoomConfig.Rooms) do
        local req = room.UnlockRequirement
        local isUnlocked = false
        
        if req.Type == "None" then
            isUnlocked = true
        elseif req.Type == "DungeonLevel" then
            isUnlocked = dungeonLevel >= req.Level
        end
        
        if isUnlocked then
            table.insert(result, room)
        end
    end
    return result
end

-- Berechnet Upgrade-Kosten für ein bestimmtes Level
function RoomConfig.CalculateUpgradeCost(roomId, currentLevel)
    local room = RoomConfig.Rooms[roomId]
    if not room then return nil end
    
    local settings = RoomConfig.UpgradeSettings
    local goldCost = math.floor(room.PurchaseCost * (settings.CostMultiplier ^ currentLevel))
    local gemCost = math.floor(room.PurchaseGems * (settings.CostMultiplier ^ currentLevel) * 0.5)
    
    return {
        Gold = goldCost,
        Gems = gemCost,
    }
end

-- Berechnet Raum-Boni für ein bestimmtes Level
function RoomConfig.CalculateBonusesAtLevel(roomId, level)
    local room = RoomConfig.Rooms[roomId]
    if not room then return nil end
    
    local settings = RoomConfig.UpgradeSettings
    local levelMultiplier = 1 + (settings.BonusIncreasePerLevel * (level - 1))
    
    local scaledBonuses = {}
    for _, bonus in ipairs(room.Bonuses) do
        local scaledBonus = {}
        for key, value in pairs(bonus) do
            if type(value) == "number" and key ~= "DamagePerSecond" and key ~= "HealPerSecond" then
                scaledBonus[key] = value * levelMultiplier
            else
                scaledBonus[key] = value
            end
        end
        table.insert(scaledBonuses, scaledBonus)
    end
    
    return scaledBonuses
end

-- Gibt die Größe eines Raums zurück
function RoomConfig.GetRoomSize(roomId)
    local room = RoomConfig.Rooms[roomId]
    if not room then return nil end
    
    return RoomConfig.Sizes[room.Size]
end

-- Prüft ob ein Monster in einem Raum platziert werden kann
function RoomConfig.CanPlaceMonster(roomId, monsterRarity)
    local room = RoomConfig.Rooms[roomId]
    if not room then return false end
    
    -- Wenn keine Einschränkung, alle erlaubt
    if not room.AllowedMonsterRarities then
        return true
    end
    
    -- Prüfe ob Rarität erlaubt
    for _, allowedRarity in ipairs(room.AllowedMonsterRarities) do
        if allowedRarity == monsterRarity then
            return true
        end
    end
    
    return false
end

return RoomConfig
