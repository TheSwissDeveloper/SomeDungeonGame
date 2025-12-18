--[[
    TrapConfig.lua
    Definitionen aller Fallen-Typen
    Pfad: ReplicatedStorage/Shared/Config/TrapConfig
    
    Jede Falle hat:
    - Eindeutige ID
    - Basis-Stats (Schaden, Cooldown, Reichweite)
    - Kosten (Gold/Gems)
    - Upgrade-Skalierung
    - Visuelle Referenz (Asset-ID)
]]

local TrapConfig = {}

-------------------------------------------------
-- UPGRADE-SKALIERUNG (Global)
-------------------------------------------------
TrapConfig.UpgradeSettings = {
    -- Kosten-Multiplikator pro Level
    CostMultiplier = 1.35,
    
    -- Stat-Verbesserung pro Level (%)
    DamageIncrease = 0.12,      -- +12% Schaden pro Level
    CooldownReduction = 0.05,   -- -5% Cooldown pro Level (min 50%)
    
    -- Max Upgrade Level
    MaxLevel = 25,
}

-------------------------------------------------
-- FALLEN-RARITÄTEN
-------------------------------------------------
TrapConfig.Rarities = {
    Common = {
        Name = "Gewöhnlich",
        Color = Color3.fromRGB(180, 180, 180),
        StatMultiplier = 1.0,
    },
    Uncommon = {
        Name = "Ungewöhnlich",
        Color = Color3.fromRGB(30, 255, 30),
        StatMultiplier = 1.25,
    },
    Rare = {
        Name = "Selten",
        Color = Color3.fromRGB(30, 144, 255),
        StatMultiplier = 1.5,
    },
    Epic = {
        Name = "Episch",
        Color = Color3.fromRGB(163, 53, 238),
        StatMultiplier = 2.0,
    },
    Legendary = {
        Name = "Legendär",
        Color = Color3.fromRGB(255, 165, 0),
        StatMultiplier = 3.0,
    },
}

-------------------------------------------------
-- FALLEN-TYPEN
-------------------------------------------------
TrapConfig.Traps = {
    -------------------------------------------------
    -- COMMON TRAPS
    -------------------------------------------------
    ["spike_floor"] = {
        Id = "spike_floor",
        Name = "Stachelboden",
        Description = "Spitze Stacheln schießen aus dem Boden.",
        Rarity = "Common",
        Category = "Floor",
        
        -- Basis-Stats (Level 1)
        BaseDamage = 15,
        BaseCooldown = 3.0,         -- Sekunden
        BaseRange = 5,              -- Studs
        
        -- Kosten
        PurchaseCost = 50,          -- Gold
        PurchaseGems = 0,           -- Gems (0 = nur Gold)
        
        -- Spezial-Effekte
        Effects = {},
        
        -- Asset-Referenz
        AssetId = "rbxassetid://0", -- Placeholder
    },
    
    ["arrow_wall"] = {
        Id = "arrow_wall",
        Name = "Pfeilwand",
        Description = "Schießt Pfeile aus der Wand.",
        Rarity = "Common",
        Category = "Wall",
        
        BaseDamage = 20,
        BaseCooldown = 2.5,
        BaseRange = 15,
        
        PurchaseCost = 75,
        PurchaseGems = 0,
        
        Effects = {},
        AssetId = "rbxassetid://0",
    },
    
    ["pit_trap"] = {
        Id = "pit_trap",
        Name = "Fallgrube",
        Description = "Helden fallen in eine tiefe Grube.",
        Rarity = "Common",
        Category = "Floor",
        
        BaseDamage = 25,
        BaseCooldown = 8.0,
        BaseRange = 4,
        
        PurchaseCost = 100,
        PurchaseGems = 0,
        
        Effects = {
            { Type = "Stun", Duration = 1.5 },
        },
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- UNCOMMON TRAPS
    -------------------------------------------------
    ["poison_dart"] = {
        Id = "poison_dart",
        Name = "Giftpfeil",
        Description = "Verschießt vergiftete Pfeile.",
        Rarity = "Uncommon",
        Category = "Wall",
        
        BaseDamage = 10,
        BaseCooldown = 2.0,
        BaseRange = 20,
        
        PurchaseCost = 200,
        PurchaseGems = 0,
        
        Effects = {
            { Type = "Poison", DamagePerSecond = 5, Duration = 4.0 },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["flame_jet"] = {
        Id = "flame_jet",
        Name = "Flammenwerfer",
        Description = "Speit einen Flammenkegel.",
        Rarity = "Uncommon",
        Category = "Wall",
        
        BaseDamage = 30,
        BaseCooldown = 4.0,
        BaseRange = 10,
        
        PurchaseCost = 300,
        PurchaseGems = 0,
        
        Effects = {
            { Type = "Burn", DamagePerSecond = 8, Duration = 3.0 },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["swinging_axe"] = {
        Id = "swinging_axe",
        Name = "Pendel-Axt",
        Description = "Eine schwere Axt schwingt hin und her.",
        Rarity = "Uncommon",
        Category = "Ceiling",
        
        BaseDamage = 45,
        BaseCooldown = 3.5,
        BaseRange = 6,
        
        PurchaseCost = 350,
        PurchaseGems = 0,
        
        Effects = {},
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- RARE TRAPS
    -------------------------------------------------
    ["freeze_rune"] = {
        Id = "freeze_rune",
        Name = "Frost-Rune",
        Description = "Friert Helden für kurze Zeit ein.",
        Rarity = "Rare",
        Category = "Floor",
        
        BaseDamage = 20,
        BaseCooldown = 6.0,
        BaseRange = 8,
        
        PurchaseCost = 800,
        PurchaseGems = 5,
        
        Effects = {
            { Type = "Freeze", Duration = 2.5 },
            { Type = "Slow", Percentage = 0.5, Duration = 3.0 },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["boulder_trap"] = {
        Id = "boulder_trap",
        Name = "Felsbrocken",
        Description = "Ein riesiger Stein rollt durch den Gang.",
        Rarity = "Rare",
        Category = "Special",
        
        BaseDamage = 80,
        BaseCooldown = 15.0,
        BaseRange = 30,
        
        PurchaseCost = 1000,
        PurchaseGems = 10,
        
        Effects = {
            { Type = "Knockback", Force = 50 },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["lightning_pillar"] = {
        Id = "lightning_pillar",
        Name = "Blitzsäule",
        Description = "Entlädt elektrische Energie in der Nähe.",
        Rarity = "Rare",
        Category = "Floor",
        
        BaseDamage = 55,
        BaseCooldown = 5.0,
        BaseRange = 12,
        
        PurchaseCost = 1200,
        PurchaseGems = 8,
        
        Effects = {
            { Type = "Chain", MaxTargets = 3, DamageFalloff = 0.7 },
        },
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- EPIC TRAPS
    -------------------------------------------------
    ["death_laser"] = {
        Id = "death_laser",
        Name = "Todeslaser",
        Description = "Ein fokussierter Energiestrahl.",
        Rarity = "Epic",
        Category = "Wall",
        
        BaseDamage = 100,
        BaseCooldown = 8.0,
        BaseRange = 40,
        
        PurchaseCost = 5000,
        PurchaseGems = 50,
        
        Effects = {
            { Type = "Pierce", MaxTargets = 5 },
            { Type = "Burn", DamagePerSecond = 15, Duration = 2.0 },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["void_portal"] = {
        Id = "void_portal",
        Name = "Leerenportal",
        Description = "Teleportiert Helden zurück zum Start.",
        Rarity = "Epic",
        Category = "Floor",
        
        BaseDamage = 30,
        BaseCooldown = 20.0,
        BaseRange = 6,
        
        PurchaseCost = 7500,
        PurchaseGems = 75,
        
        Effects = {
            { Type = "Teleport", Target = "RoomStart" },
            { Type = "Stun", Duration = 1.0 },
        },
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- LEGENDARY TRAPS
    -------------------------------------------------
    ["dragon_statue"] = {
        Id = "dragon_statue",
        Name = "Drachenstatue",
        Description = "Speit vernichtenden Drachenatem.",
        Rarity = "Legendary",
        Category = "Special",
        
        BaseDamage = 200,
        BaseCooldown = 12.0,
        BaseRange = 25,
        
        PurchaseCost = 25000,
        PurchaseGems = 250,
        
        Effects = {
            { Type = "Burn", DamagePerSecond = 30, Duration = 5.0 },
            { Type = "Fear", Duration = 2.0 },
        },
        AssetId = "rbxassetid://0",
    },
    
    ["ancient_guardian"] = {
        Id = "ancient_guardian",
        Name = "Uralter Wächter",
        Description = "Eine animierte Rüstung, die Eindringlinge angreift.",
        Rarity = "Legendary",
        Category = "Special",
        
        BaseDamage = 150,
        BaseCooldown = 6.0,
        BaseRange = 10,
        
        PurchaseCost = 30000,
        PurchaseGems = 300,
        
        Effects = {
            { Type = "Stun", Duration = 1.5 },
            { Type = "ArmorBreak", Percentage = 0.25, Duration = 5.0 },
        },
        AssetId = "rbxassetid://0",
    },
}

-------------------------------------------------
-- HILFSFUNKTIONEN
-------------------------------------------------

-- Gibt Fallen-Daten per ID zurück
function TrapConfig.GetTrap(trapId)
    return TrapConfig.Traps[trapId]
end

-- Gibt alle Fallen einer Rarität zurück
function TrapConfig.GetTrapsByRarity(rarity)
    local result = {}
    for id, trap in pairs(TrapConfig.Traps) do
        if trap.Rarity == rarity then
            table.insert(result, trap)
        end
    end
    return result
end

-- Gibt alle Fallen einer Kategorie zurück
function TrapConfig.GetTrapsByCategory(category)
    local result = {}
    for id, trap in pairs(TrapConfig.Traps) do
        if trap.Category == category then
            table.insert(result, trap)
        end
    end
    return result
end

-- Berechnet Upgrade-Kosten für ein bestimmtes Level
function TrapConfig.CalculateUpgradeCost(trapId, currentLevel)
    local trap = TrapConfig.Traps[trapId]
    if not trap then return nil end
    
    local settings = TrapConfig.UpgradeSettings
    local goldCost = math.floor(trap.PurchaseCost * (settings.CostMultiplier ^ currentLevel))
    local gemCost = math.floor(trap.PurchaseGems * (settings.CostMultiplier ^ currentLevel) * 0.5)
    
    return {
        Gold = goldCost,
        Gems = gemCost,
    }
end

-- Berechnet Stats für ein bestimmtes Level
function TrapConfig.CalculateStatsAtLevel(trapId, level)
    local trap = TrapConfig.Traps[trapId]
    if not trap then return nil end
    
    local settings = TrapConfig.UpgradeSettings
    local rarity = TrapConfig.Rarities[trap.Rarity]
    local levelBonus = level - 1
    
    local damage = trap.BaseDamage * rarity.StatMultiplier
    damage = damage * (1 + settings.DamageIncrease * levelBonus)
    
    local cooldown = trap.BaseCooldown
    local cooldownReduction = settings.CooldownReduction * levelBonus
    cooldown = cooldown * math.max(0.5, 1 - cooldownReduction)
    
    return {
        Damage = math.floor(damage),
        Cooldown = cooldown,
        Range = trap.BaseRange,
        Effects = trap.Effects,
    }
end

return TrapConfig
