--[[
    MonsterConfig.lua
    Definitionen aller Monster-Typen
    Pfad: ReplicatedStorage/Shared/Config/MonsterConfig
    
    Jedes Monster hat:
    - Eindeutige ID
    - Basis-Stats (HP, Schaden, Speed, etc.)
    - AI-Verhalten (Melee, Ranged, Support, Boss)
    - Kosten und Upgrade-Pfade
    - Fähigkeiten (Abilities)
]]

local MonsterConfig = {}

-------------------------------------------------
-- UPGRADE-SKALIERUNG (Global)
-------------------------------------------------
MonsterConfig.UpgradeSettings = {
    -- Kosten-Multiplikator pro Level
    CostMultiplier = 1.4,
    
    -- Stat-Verbesserung pro Level (%)
    HealthIncrease = 0.15,      -- +15% HP pro Level
    DamageIncrease = 0.10,      -- +10% Schaden pro Level
    
    -- Max Upgrade Level
    MaxLevel = 30,
}

-------------------------------------------------
-- MONSTER-RARITÄTEN
-------------------------------------------------
MonsterConfig.Rarities = {
    Common = {
        Name = "Gewöhnlich",
        Color = Color3.fromRGB(180, 180, 180),
        StatMultiplier = 1.0,
    },
    Uncommon = {
        Name = "Ungewöhnlich",
        Color = Color3.fromRGB(30, 255, 30),
        StatMultiplier = 1.3,
    },
    Rare = {
        Name = "Selten",
        Color = Color3.fromRGB(30, 144, 255),
        StatMultiplier = 1.6,
    },
    Epic = {
        Name = "Episch",
        Color = Color3.fromRGB(163, 53, 238),
        StatMultiplier = 2.2,
    },
    Legendary = {
        Name = "Legendär",
        Color = Color3.fromRGB(255, 165, 0),
        StatMultiplier = 3.5,
    },
}

-------------------------------------------------
-- AI-VERHALTENSTYPEN
-------------------------------------------------
MonsterConfig.BehaviorTypes = {
    Melee = {
        Description = "Greift Helden im Nahkampf an",
        PreferredRange = 5,
        FleeAtHealthPercent = 0,    -- Flieht nie
    },
    Ranged = {
        Description = "Hält Abstand und greift aus der Ferne an",
        PreferredRange = 20,
        FleeAtHealthPercent = 0.2,  -- Flieht bei 20% HP
    },
    Support = {
        Description = "Unterstützt andere Monster",
        PreferredRange = 15,
        FleeAtHealthPercent = 0.3,
    },
    Tank = {
        Description = "Zieht Aggro und absorbiert Schaden",
        PreferredRange = 3,
        FleeAtHealthPercent = 0,
    },
    Boss = {
        Description = "Mächtiger Endgegner mit mehreren Phasen",
        PreferredRange = 10,
        FleeAtHealthPercent = 0,
    },
}

-------------------------------------------------
-- MONSTER-TYPEN
-------------------------------------------------
MonsterConfig.Monsters = {
    -------------------------------------------------
    -- COMMON MONSTERS
    -------------------------------------------------
    ["skeleton"] = {
        Id = "skeleton",
        Name = "Skelett",
        Description = "Ein klappriger Untoter mit rostigem Schwert.",
        Rarity = "Common",
        Behavior = "Melee",
        
        -- Basis-Stats (Level 1)
        BaseHealth = 80,
        BaseDamage = 12,
        BaseSpeed = 12,
        BaseArmor = 0,
        
        -- Angriffs-Eigenschaften
        AttackRange = 5,
        AttackCooldown = 1.5,
        
        -- Kosten
        PurchaseCost = 100,
        PurchaseGems = 0,
        
        -- Fähigkeiten
        Abilities = {},
        
        -- Asset-Referenz
        AssetId = "rbxassetid://0",
    },
    
    ["slime"] = {
        Id = "slime",
        Name = "Schleim",
        Description = "Ein glibberiges Wesen, das sich teilt.",
        Rarity = "Common",
        Behavior = "Melee",
        
        BaseHealth = 60,
        BaseDamage = 8,
        BaseSpeed = 8,
        BaseArmor = 0,
        
        AttackRange = 4,
        AttackCooldown = 2.0,
        
        PurchaseCost = 75,
        PurchaseGems = 0,
        
        Abilities = {
            {
                Name = "Teilung",
                Description = "Spawnt 2 Mini-Schleime bei Tod",
                Type = "OnDeath",
                SpawnCount = 2,
                SpawnId = "mini_slime",
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["mini_slime"] = {
        Id = "mini_slime",
        Name = "Mini-Schleim",
        Description = "Ein kleiner Schleim aus der Teilung.",
        Rarity = "Common",
        Behavior = "Melee",
        
        BaseHealth = 20,
        BaseDamage = 4,
        BaseSpeed = 10,
        BaseArmor = 0,
        
        AttackRange = 3,
        AttackCooldown = 1.5,
        
        -- Nicht kaufbar, nur durch Teilung
        PurchaseCost = 0,
        PurchaseGems = 0,
        Purchasable = false,
        
        Abilities = {},
        AssetId = "rbxassetid://0",
    },
    
    ["goblin"] = {
        Id = "goblin",
        Name = "Goblin",
        Description = "Klein, fies und überraschend schnell.",
        Rarity = "Common",
        Behavior = "Melee",
        
        BaseHealth = 50,
        BaseDamage = 15,
        BaseSpeed = 18,
        BaseArmor = 0,
        
        AttackRange = 4,
        AttackCooldown = 1.0,
        
        PurchaseCost = 120,
        PurchaseGems = 0,
        
        Abilities = {},
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- UNCOMMON MONSTERS
    -------------------------------------------------
    ["archer_skeleton"] = {
        Id = "archer_skeleton",
        Name = "Skelett-Bogenschütze",
        Description = "Ein Skelett mit einem morschen Bogen.",
        Rarity = "Uncommon",
        Behavior = "Ranged",
        
        BaseHealth = 60,
        BaseDamage = 18,
        BaseSpeed = 10,
        BaseArmor = 0,
        
        AttackRange = 25,
        AttackCooldown = 2.0,
        
        PurchaseCost = 250,
        PurchaseGems = 0,
        
        Abilities = {},
        AssetId = "rbxassetid://0",
    },
    
    ["orc_warrior"] = {
        Id = "orc_warrior",
        Name = "Ork-Krieger",
        Description = "Ein muskelbepackter Ork mit Streitaxt.",
        Rarity = "Uncommon",
        Behavior = "Melee",
        
        BaseHealth = 150,
        BaseDamage = 25,
        BaseSpeed = 10,
        BaseArmor = 5,
        
        AttackRange = 6,
        AttackCooldown = 2.0,
        
        PurchaseCost = 350,
        PurchaseGems = 0,
        
        Abilities = {
            {
                Name = "Wutschrei",
                Description = "Erhöht Schaden um 50% für 5 Sekunden",
                Type = "Active",
                Cooldown = 15,
                DamageMultiplier = 1.5,
                Duration = 5,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["dark_mage"] = {
        Id = "dark_mage",
        Name = "Dunkelmagier",
        Description = "Ein finsterer Zauberer mit Schattenkräften.",
        Rarity = "Uncommon",
        Behavior = "Ranged",
        
        BaseHealth = 70,
        BaseDamage = 30,
        BaseSpeed = 8,
        BaseArmor = 0,
        
        AttackRange = 30,
        AttackCooldown = 2.5,
        
        PurchaseCost = 400,
        PurchaseGems = 0,
        
        Abilities = {
            {
                Name = "Schattenblitz",
                Description = "Trifft bis zu 3 Ziele gleichzeitig",
                Type = "Attack",
                MaxTargets = 3,
                DamageFalloff = 0.7,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- RARE MONSTERS
    -------------------------------------------------
    ["golem"] = {
        Id = "golem",
        Name = "Steingolem",
        Description = "Ein lebendiger Fels mit immenser Stärke.",
        Rarity = "Rare",
        Behavior = "Tank",
        
        BaseHealth = 400,
        BaseDamage = 35,
        BaseSpeed = 5,
        BaseArmor = 20,
        
        AttackRange = 6,
        AttackCooldown = 3.0,
        
        PurchaseCost = 1500,
        PurchaseGems = 15,
        
        Abilities = {
            {
                Name = "Erderschütterung",
                Description = "Stunt alle Helden im Umkreis",
                Type = "Active",
                Cooldown = 20,
                Range = 12,
                StunDuration = 2.0,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["vampire"] = {
        Id = "vampire",
        Name = "Vampir",
        Description = "Ein blutdurstiger Untoter der Nacht.",
        Rarity = "Rare",
        Behavior = "Melee",
        
        BaseHealth = 180,
        BaseDamage = 40,
        BaseSpeed = 16,
        BaseArmor = 5,
        
        AttackRange = 5,
        AttackCooldown = 1.5,
        
        PurchaseCost = 1800,
        PurchaseGems = 20,
        
        Abilities = {
            {
                Name = "Lebensraub",
                Description = "Heilt sich für 30% des verursachten Schadens",
                Type = "Passive",
                LifestealPercent = 0.30,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["necromancer"] = {
        Id = "necromancer",
        Name = "Nekromant",
        Description = "Beschwört gefallene Krieger als Skelette.",
        Rarity = "Rare",
        Behavior = "Support",
        
        BaseHealth = 120,
        BaseDamage = 20,
        BaseSpeed = 8,
        BaseArmor = 0,
        
        AttackRange = 25,
        AttackCooldown = 3.0,
        
        PurchaseCost = 2000,
        PurchaseGems = 25,
        
        Abilities = {
            {
                Name = "Skelett beschwören",
                Description = "Beschwört ein Skelett alle 10 Sekunden",
                Type = "Summon",
                Cooldown = 10,
                SummonId = "skeleton",
                MaxSummons = 3,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- EPIC MONSTERS
    -------------------------------------------------
    ["demon"] = {
        Id = "demon",
        Name = "Dämon",
        Description = "Ein Wesen aus der Unterwelt mit Feuermagie.",
        Rarity = "Epic",
        Behavior = "Melee",
        
        BaseHealth = 350,
        BaseDamage = 60,
        BaseSpeed = 14,
        BaseArmor = 10,
        
        AttackRange = 7,
        AttackCooldown = 1.8,
        
        PurchaseCost = 8000,
        PurchaseGems = 80,
        
        Abilities = {
            {
                Name = "Höllenfeuer",
                Description = "Verbrennt alle Helden im Umkreis",
                Type = "Active",
                Cooldown = 12,
                Range = 15,
                DamagePerSecond = 25,
                Duration = 4,
            },
            {
                Name = "Feuerresistenz",
                Description = "Immun gegen Feuerschaden",
                Type = "Passive",
                Immunity = "Fire",
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["frost_witch"] = {
        Id = "frost_witch",
        Name = "Frosthexe",
        Description = "Eine eiskalte Hexe mit Frostmagie.",
        Rarity = "Epic",
        Behavior = "Ranged",
        
        BaseHealth = 200,
        BaseDamage = 50,
        BaseSpeed = 10,
        BaseArmor = 5,
        
        AttackRange = 35,
        AttackCooldown = 2.2,
        
        PurchaseCost = 10000,
        PurchaseGems = 100,
        
        Abilities = {
            {
                Name = "Frostschild",
                Description = "Verlangsamt Angreifer um 40%",
                Type = "Passive",
                SlowPercent = 0.40,
                SlowDuration = 2.0,
            },
            {
                Name = "Blizzard",
                Description = "Friert alle Helden für 3 Sekunden ein",
                Type = "Active",
                Cooldown = 25,
                Range = 20,
                FreezeDuration = 3.0,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- LEGENDARY MONSTERS (Bosse)
    -------------------------------------------------
    ["dragon"] = {
        Id = "dragon",
        Name = "Uralter Drache",
        Description = "Der mächtigste Wächter eines Dungeons.",
        Rarity = "Legendary",
        Behavior = "Boss",
        
        BaseHealth = 2000,
        BaseDamage = 120,
        BaseSpeed = 12,
        BaseArmor = 30,
        
        AttackRange = 15,
        AttackCooldown = 2.5,
        
        PurchaseCost = 100000,
        PurchaseGems = 1000,
        
        -- Limitierung: Nur 1 pro Dungeon
        MaxPerDungeon = 1,
        
        Abilities = {
            {
                Name = "Drachenatem",
                Description = "Feuert einen verheerenden Flammenkegel",
                Type = "Active",
                Cooldown = 8,
                Range = 30,
                Damage = 200,
                BurnDamage = 40,
                BurnDuration = 5,
            },
            {
                Name = "Flügelschlag",
                Description = "Schlägt alle Helden zurück",
                Type = "Active",
                Cooldown = 15,
                Range = 20,
                KnockbackForce = 80,
                Damage = 80,
            },
            {
                Name = "Drachenschuppen",
                Description = "Reduziert allen Schaden um 25%",
                Type = "Passive",
                DamageReduction = 0.25,
            },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["lich_king"] = {
        Id = "lich_king",
        Name = "Lichkönig",
        Description = "Ein uralter Untoter mit absoluter Macht über den Tod.",
        Rarity = "Legendary",
        Behavior = "Boss",
        
        BaseHealth = 1500,
        BaseDamage = 80,
        BaseSpeed = 8,
        BaseArmor = 15,
        
        AttackRange = 30,
        AttackCooldown = 2.0,
        
        PurchaseCost = 80000,
        PurchaseGems = 800,
        
        MaxPerDungeon = 1,
        
        Abilities = {
            {
                Name = "Armee der Toten",
                Description = "Beschwört 5 Skelette auf einmal",
                Type = "Summon",
                Cooldown = 20,
                SummonId = "skeleton",
                SummonCount = 5,
                MaxSummons = 10,
            },
            {
                Name = "Todesgriff",
                Description = "Zieht einen Helden zu sich und stunt ihn",
                Type = "Active",
                Cooldown = 12,
                Range = 40,
                PullSpeed = 50,
                StunDuration = 2.5,
            },
            {
                Name = "Unheilige Aura",
                Description = "Erhöht Schaden aller Monster um 20%",
                Type = "Aura",
                Range = 30,
                DamageBonus = 0.20,
            },
        },
        AssetId = "rbxassetid://0",
    },
}

-------------------------------------------------
-- HILFSFUNKTIONEN
-------------------------------------------------

-- Gibt Monster-Daten per ID zurück
function MonsterConfig.GetMonster(monsterId)
    return MonsterConfig.Monsters[monsterId]
end

-- Gibt alle kaufbaren Monster zurück
function MonsterConfig.GetPurchasableMonsters()
    local result = {}
    for id, monster in pairs(MonsterConfig.Monsters) do
        if monster.Purchasable ~= false and monster.PurchaseCost > 0 then
            table.insert(result, monster)
        end
    end
    return result
end

-- Gibt alle Monster einer Rarität zurück
function MonsterConfig.GetMonstersByRarity(rarity)
    local result = {}
    for id, monster in pairs(MonsterConfig.Monsters) do
        if monster.Rarity == rarity then
            table.insert(result, monster)
        end
    end
    return result
end

-- Gibt alle Monster eines Verhaltenstyps zurück
function MonsterConfig.GetMonstersByBehavior(behavior)
    local result = {}
    for id, monster in pairs(MonsterConfig.Monsters) do
        if monster.Behavior == behavior then
            table.insert(result, monster)
        end
    end
    return result
end

-- Berechnet Upgrade-Kosten für ein bestimmtes Level
function MonsterConfig.CalculateUpgradeCost(monsterId, currentLevel)
    local monster = MonsterConfig.Monsters[monsterId]
    if not monster then return nil end
    
    local settings = MonsterConfig.UpgradeSettings
    local goldCost = math.floor(monster.PurchaseCost * (settings.CostMultiplier ^ currentLevel))
    local gemCost = math.floor(monster.PurchaseGems * (settings.CostMultiplier ^ currentLevel) * 0.5)
    
    return {
        Gold = goldCost,
        Gems = gemCost,
    }
end

-- Berechnet Stats für ein bestimmtes Level
function MonsterConfig.CalculateStatsAtLevel(monsterId, level)
    local monster = MonsterConfig.Monsters[monsterId]
    if not monster then return nil end
    
    local settings = MonsterConfig.UpgradeSettings
    local rarity = MonsterConfig.Rarities[monster.Rarity]
    local levelBonus = level - 1
    
    local health = monster.BaseHealth * rarity.StatMultiplier
    health = health * (1 + settings.HealthIncrease * levelBonus)
    
    local damage = monster.BaseDamage * rarity.StatMultiplier
    damage = damage * (1 + settings.DamageIncrease * levelBonus)
    
    return {
        Health = math.floor(health),
        Damage = math.floor(damage),
        Speed = monster.BaseSpeed,
        Armor = monster.BaseArmor,
        AttackRange = monster.AttackRange,
        AttackCooldown = monster.AttackCooldown,
        Abilities = monster.Abilities,
    }
end

return MonsterConfig
