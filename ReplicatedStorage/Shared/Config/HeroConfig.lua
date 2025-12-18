--[[
    HeroConfig.lua
    Definitionen aller Helden-Typen für Raids
    Pfad: ReplicatedStorage/Shared/Config/HeroConfig
    
    Jeder Held hat:
    - Eindeutige ID
    - Klasse (Tank, DPS, Healer, Support)
    - Basis-Stats (HP, Schaden, Speed, etc.)
    - Fähigkeiten (Aktiv & Passiv)
    - Kosten und Upgrade-Pfade
]]

local HeroConfig = {}

-------------------------------------------------
-- UPGRADE-SKALIERUNG (Global)
-------------------------------------------------
HeroConfig.UpgradeSettings = {
    -- XP benötigt pro Level (Basis * Multiplikator^Level)
    XPBase = 100,
    XPMultiplier = 1.2,
    
    -- Stat-Verbesserung pro Level (%)
    HealthIncrease = 0.10,      -- +10% HP pro Level
    DamageIncrease = 0.08,      -- +8% Schaden pro Level
    SpeedIncrease = 0.02,       -- +2% Speed pro Level
    
    -- Max Level
    MaxLevel = 100,
    
    -- Kosten für Rekrutierung (Gold)
    RecruitCostMultiplier = 1.5,    -- Pro Rarität
}

-------------------------------------------------
-- HELDEN-RARITÄTEN
-------------------------------------------------
HeroConfig.Rarities = {
    Common = {
        Name = "Gewöhnlich",
        Color = Color3.fromRGB(180, 180, 180),
        StatMultiplier = 1.0,
        DropChance = 0.60,      -- 60% bei Rekrutierung
    },
    Uncommon = {
        Name = "Ungewöhnlich",
        Color = Color3.fromRGB(30, 255, 30),
        StatMultiplier = 1.25,
        DropChance = 0.25,      -- 25%
    },
    Rare = {
        Name = "Selten",
        Color = Color3.fromRGB(30, 144, 255),
        StatMultiplier = 1.5,
        DropChance = 0.10,      -- 10%
    },
    Epic = {
        Name = "Episch",
        Color = Color3.fromRGB(163, 53, 238),
        StatMultiplier = 2.0,
        DropChance = 0.04,      -- 4%
    },
    Legendary = {
        Name = "Legendär",
        Color = Color3.fromRGB(255, 165, 0),
        StatMultiplier = 3.0,
        DropChance = 0.01,      -- 1%
    },
}

-------------------------------------------------
-- HELDEN-KLASSEN
-------------------------------------------------
HeroConfig.Classes = {
    Tank = {
        Name = "Tank",
        Description = "Absorbiert Schaden und schützt das Team",
        Icon = "rbxassetid://0",
        PreferredPosition = "Front",
        
        -- Basis-Modifikatoren für die Klasse
        HealthModifier = 1.5,       -- +50% HP
        DamageModifier = 0.7,       -- -30% Schaden
        SpeedModifier = 0.8,        -- -20% Speed
    },
    DPS = {
        Name = "Schadensteiler",
        Description = "Verursacht hohen Schaden",
        Icon = "rbxassetid://0",
        PreferredPosition = "Back",
        
        HealthModifier = 0.8,
        DamageModifier = 1.4,
        SpeedModifier = 1.0,
    },
    Healer = {
        Name = "Heiler",
        Description = "Heilt und unterstützt Verbündete",
        Icon = "rbxassetid://0",
        PreferredPosition = "Back",
        
        HealthModifier = 0.9,
        DamageModifier = 0.5,
        SpeedModifier = 1.0,
    },
    Support = {
        Name = "Unterstützer",
        Description = "Bufft Verbündete und debufft Feinde",
        Icon = "rbxassetid://0",
        PreferredPosition = "Middle",
        
        HealthModifier = 1.0,
        DamageModifier = 0.8,
        SpeedModifier = 1.1,
    },
}

-------------------------------------------------
-- HELDEN-TYPEN
-------------------------------------------------
HeroConfig.Heroes = {
    -------------------------------------------------
    -- COMMON HEROES
    -------------------------------------------------
    ["knight"] = {
        Id = "knight",
        Name = "Ritter",
        Description = "Ein tapferer Krieger mit Schwert und Schild.",
        Rarity = "Common",
        Class = "Tank",
        
        -- Basis-Stats (Level 1, vor Klassen-Modifikator)
        BaseHealth = 120,
        BaseDamage = 15,
        BaseSpeed = 10,
        BaseArmor = 10,
        
        -- Angriffs-Eigenschaften
        AttackRange = 5,
        AttackCooldown = 1.5,
        
        -- Rekrutierungskosten
        RecruitCost = 200,
        RecruitGems = 0,
        
        -- Fähigkeiten
        Abilities = {
            {
                Name = "Schildblock",
                Description = "Blockt den nächsten Angriff komplett",
                Type = "Active",
                Cooldown = 12,
                Duration = 2.0,
                DamageReduction = 1.0,  -- 100% Reduktion
            },
        },
        
        -- Asset-Referenz
        AssetId = "rbxassetid://0",
    },
    
    ["archer"] = {
        Id = "archer",
        Name = "Bogenschütze",
        Description = "Ein präziser Fernkämpfer.",
        Rarity = "Common",
        Class = "DPS",
        
        BaseHealth = 70,
        BaseDamage = 22,
        BaseSpeed = 12,
        BaseArmor = 0,
        
        AttackRange = 30,
        AttackCooldown = 1.8,
        
        RecruitCost = 180,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Präzisionsschuss",
                Description = "Nächster Angriff ist ein garantierter Kritischer Treffer",
                Type = "Active",
                Cooldown = 10,
                CritMultiplier = 2.0,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["apprentice"] = {
        Id = "apprentice",
        Name = "Lehrling",
        Description = "Ein junger Magier in Ausbildung.",
        Rarity = "Common",
        Class = "DPS",
        
        BaseHealth = 60,
        BaseDamage = 25,
        BaseSpeed = 10,
        BaseArmor = 0,
        
        AttackRange = 25,
        AttackCooldown = 2.0,
        
        RecruitCost = 200,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Feuerball",
                Description = "Wirft einen explodierenden Feuerball",
                Type = "Active",
                Cooldown = 8,
                Damage = 40,
                AoERadius = 8,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["cleric"] = {
        Id = "cleric",
        Name = "Kleriker",
        Description = "Ein Diener des Lichts mit Heilkräften.",
        Rarity = "Common",
        Class = "Healer",
        
        BaseHealth = 80,
        BaseDamage = 10,
        BaseSpeed = 10,
        BaseArmor = 5,
        
        AttackRange = 20,
        AttackCooldown = 2.5,
        
        RecruitCost = 250,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Heiliges Licht",
                Description = "Heilt einen Verbündeten",
                Type = "Active",
                Cooldown = 6,
                HealAmount = 50,
                TargetType = "LowestHealthAlly",
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- UNCOMMON HEROES
    -------------------------------------------------
    ["berserker"] = {
        Id = "berserker",
        Name = "Berserker",
        Description = "Ein wilder Krieger, der stärker wird je mehr er verletzt ist.",
        Rarity = "Uncommon",
        Class = "DPS",
        
        BaseHealth = 100,
        BaseDamage = 28,
        BaseSpeed = 14,
        BaseArmor = 5,
        
        AttackRange = 6,
        AttackCooldown = 1.2,
        
        RecruitCost = 500,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Blutrausch",
                Description = "+50% Schaden wenn unter 50% HP",
                Type = "Passive",
                HealthThreshold = 0.5,
                DamageBonus = 0.5,
            },
            {
                Name = "Wirbelwind",
                Description = "Trifft alle Feinde im Nahkampf",
                Type = "Active",
                Cooldown = 10,
                DamageMultiplier = 0.8,
                AoERadius = 8,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["ranger"] = {
        Id = "ranger",
        Name = "Waldläufer",
        Description = "Ein erfahrener Jäger mit Fallen-Expertise.",
        Rarity = "Uncommon",
        Class = "DPS",
        
        BaseHealth = 85,
        BaseDamage = 24,
        BaseSpeed = 16,
        BaseArmor = 5,
        
        AttackRange = 28,
        AttackCooldown = 1.6,
        
        RecruitCost = 550,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Fallen erkennen",
                Description = "Erkennt und entschärft eine Falle",
                Type = "Active",
                Cooldown = 15,
                DetectionRange = 20,
            },
            {
                Name = "Giftpfeil",
                Description = "Vergiftet das Ziel",
                Type = "Active",
                Cooldown = 8,
                PoisonDamage = 10,
                PoisonDuration = 4,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["shieldmaiden"] = {
        Id = "shieldmaiden",
        Name = "Schildmaid",
        Description = "Eine furchtlose Kriegerin mit unerschütterlicher Verteidigung.",
        Rarity = "Uncommon",
        Class = "Tank",
        
        BaseHealth = 150,
        BaseDamage = 18,
        BaseSpeed = 9,
        BaseArmor = 20,
        
        AttackRange = 5,
        AttackCooldown = 1.8,
        
        RecruitCost = 600,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Schildwall",
                Description = "Reduziert Schaden für alle Verbündeten dahinter",
                Type = "Active",
                Cooldown = 18,
                Duration = 5,
                DamageReduction = 0.5,
                AoERadius = 10,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["bard"] = {
        Id = "bard",
        Name = "Barde",
        Description = "Ein musikalisches Genie, das mit Liedern inspiriert.",
        Rarity = "Uncommon",
        Class = "Support",
        
        BaseHealth = 75,
        BaseDamage = 12,
        BaseSpeed = 12,
        BaseArmor = 0,
        
        AttackRange = 15,
        AttackCooldown = 2.0,
        
        RecruitCost = 500,
        RecruitGems = 0,
        
        Abilities = {
            {
                Name = "Kampflied",
                Description = "Erhöht Schaden aller Verbündeten",
                Type = "Active",
                Cooldown = 20,
                Duration = 8,
                DamageBonus = 0.25,
                AoERadius = 20,
            },
            {
                Name = "Beruhigende Melodie",
                Description = "Heilt alle Verbündeten langsam",
                Type = "Active",
                Cooldown = 25,
                Duration = 6,
                HealPerSecond = 10,
                AoERadius = 20,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- RARE HEROES
    -------------------------------------------------
    ["paladin"] = {
        Id = "paladin",
        Name = "Paladin",
        Description = "Ein heiliger Krieger mit göttlicher Macht.",
        Rarity = "Rare",
        Class = "Tank",
        
        BaseHealth = 180,
        BaseDamage = 25,
        BaseSpeed = 10,
        BaseArmor = 25,
        
        AttackRange = 6,
        AttackCooldown = 1.6,
        
        RecruitCost = 2000,
        RecruitGems = 20,
        
        Abilities = {
            {
                Name = "Göttlicher Schutz",
                Description = "Macht einen Verbündeten unverwundbar",
                Type = "Active",
                Cooldown = 30,
                Duration = 3,
                TargetType = "LowestHealthAlly",
            },
            {
                Name = "Heilige Vergeltung",
                Description = "Reflektiert 25% des erlittenen Schadens",
                Type = "Passive",
                ReflectPercent = 0.25,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["assassin"] = {
        Id = "assassin",
        Name = "Assassine",
        Description = "Ein tödlicher Schattenkrieger.",
        Rarity = "Rare",
        Class = "DPS",
        
        BaseHealth = 90,
        BaseDamage = 45,
        BaseSpeed = 20,
        BaseArmor = 0,
        
        AttackRange = 5,
        AttackCooldown = 1.0,
        
        RecruitCost = 2500,
        RecruitGems = 25,
        
        Abilities = {
            {
                Name = "Hinterhalt",
                Description = "Erster Angriff verursacht 300% Schaden",
                Type = "Passive",
                FirstStrikeMultiplier = 3.0,
            },
            {
                Name = "Schattenschritt",
                Description = "Teleportiert hinter den schwächsten Feind",
                Type = "Active",
                Cooldown = 12,
                TargetType = "LowestHealthEnemy",
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["archmage"] = {
        Id = "archmage",
        Name = "Erzmagier",
        Description = "Ein Meister der arkanen Künste.",
        Rarity = "Rare",
        Class = "DPS",
        
        BaseHealth = 80,
        BaseDamage = 50,
        BaseSpeed = 8,
        BaseArmor = 0,
        
        AttackRange = 35,
        AttackCooldown = 2.5,
        
        RecruitCost = 2800,
        RecruitGems = 30,
        
        Abilities = {
            {
                Name = "Meteorregen",
                Description = "Ruft Meteore auf ein Gebiet herab",
                Type = "Active",
                Cooldown = 20,
                Damage = 100,
                AoERadius = 15,
                Duration = 3,
            },
            {
                Name = "Arkane Barriere",
                Description = "Absorbiert magischen Schaden",
                Type = "Passive",
                MagicDamageReduction = 0.5,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["priest"] = {
        Id = "priest",
        Name = "Priester",
        Description = "Ein mächtiger Heiler mit Wiederbelebungskräften.",
        Rarity = "Rare",
        Class = "Healer",
        
        BaseHealth = 100,
        BaseDamage = 15,
        BaseSpeed = 10,
        BaseArmor = 5,
        
        AttackRange = 25,
        AttackCooldown = 2.0,
        
        RecruitCost = 3000,
        RecruitGems = 35,
        
        Abilities = {
            {
                Name = "Massenheilung",
                Description = "Heilt alle Verbündeten",
                Type = "Active",
                Cooldown = 15,
                HealAmount = 40,
                AoERadius = 30,
            },
            {
                Name = "Auferstehung",
                Description = "Belebt einen gefallenen Helden wieder",
                Type = "Active",
                Cooldown = 60,
                ReviveHealthPercent = 0.5,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- EPIC HEROES
    -------------------------------------------------
    ["dragon_knight"] = {
        Id = "dragon_knight",
        Name = "Drachenritter",
        Description = "Ein legendärer Krieger mit Drachenblut.",
        Rarity = "Epic",
        Class = "Tank",
        
        BaseHealth = 250,
        BaseDamage = 40,
        BaseSpeed = 12,
        BaseArmor = 35,
        
        AttackRange = 7,
        AttackCooldown = 1.5,
        
        RecruitCost = 15000,
        RecruitGems = 150,
        
        Abilities = {
            {
                Name = "Drachenhaut",
                Description = "Immunität gegen Feuer und reduziert allen Schaden",
                Type = "Passive",
                FireImmunity = true,
                DamageReduction = 0.15,
            },
            {
                Name = "Drachenatem",
                Description = "Speit Feuer in einem Kegel",
                Type = "Active",
                Cooldown = 15,
                Damage = 80,
                BurnDamage = 20,
                BurnDuration = 4,
                ConeAngle = 60,
                Range = 15,
            },
            {
                Name = "Drachenwille",
                Description = "Kann nicht unter 1 HP fallen für 3 Sekunden",
                Type = "Active",
                Cooldown = 45,
                Duration = 3,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["shadow_dancer"] = {
        Id = "shadow_dancer",
        Name = "Schattentänzerin",
        Description = "Eine mysteriöse Kriegerin zwischen Licht und Schatten.",
        Rarity = "Epic",
        Class = "DPS",
        
        BaseHealth = 120,
        BaseDamage = 65,
        BaseSpeed = 22,
        BaseArmor = 10,
        
        AttackRange = 6,
        AttackCooldown = 0.8,
        
        RecruitCost = 18000,
        RecruitGems = 180,
        
        Abilities = {
            {
                Name = "Schattenform",
                Description = "Wird unsichtbar und unverwundbar",
                Type = "Active",
                Cooldown = 20,
                Duration = 3,
                Invisible = true,
                Invulnerable = true,
            },
            {
                Name = "Tanz der Klingen",
                Description = "Greift alle Feinde im Umkreis blitzschnell an",
                Type = "Active",
                Cooldown = 12,
                Attacks = 5,
                DamagePerAttack = 0.6,  -- 60% des normalen Schadens
                AoERadius = 12,
            },
            {
                Name = "Tödliche Präzision",
                Description = "Kritische Treffer ignorieren Rüstung",
                Type = "Passive",
                CritIgnoresArmor = true,
                CritChanceBonus = 0.15,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["high_priest"] = {
        Id = "high_priest",
        Name = "Hohepriester",
        Description = "Der mächtigste Heiler mit göttlicher Verbindung.",
        Rarity = "Epic",
        Class = "Healer",
        
        BaseHealth = 130,
        BaseDamage = 20,
        BaseSpeed = 10,
        BaseArmor = 15,
        
        AttackRange = 30,
        AttackCooldown = 2.2,
        
        RecruitCost = 20000,
        RecruitGems = 200,
        
        Abilities = {
            {
                Name = "Göttliche Intervention",
                Description = "Heilt alle Verbündeten auf volle Gesundheit",
                Type = "Active",
                Cooldown = 90,
                FullHeal = true,
                AoERadius = 50,
            },
            {
                Name = "Segen des Lichts",
                Description = "Verbündete regenerieren HP über Zeit",
                Type = "Aura",
                AoERadius = 25,
                HealPerSecond = 15,
            },
            {
                Name = "Schutzgebet",
                Description = "Absorbiert den nächsten tödlichen Treffer",
                Type = "Active",
                Cooldown = 40,
                TargetType = "LowestHealthAlly",
                AbsorbLethalDamage = true,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    -------------------------------------------------
    -- LEGENDARY HEROES
    -------------------------------------------------
    ["immortal_champion"] = {
        Id = "immortal_champion",
        Name = "Unsterblicher Champion",
        Description = "Ein Krieger, der den Tod selbst besiegt hat.",
        Rarity = "Legendary",
        Class = "Tank",
        
        BaseHealth = 400,
        BaseDamage = 55,
        BaseSpeed = 14,
        BaseArmor = 50,
        
        AttackRange = 7,
        AttackCooldown = 1.4,
        
        RecruitCost = 100000,
        RecruitGems = 1000,
        
        Abilities = {
            {
                Name = "Unsterblichkeit",
                Description = "Steht einmal pro Raid bei tödlichem Schaden wieder auf",
                Type = "Passive",
                ReviveOnDeath = true,
                ReviveHealthPercent = 0.5,
                UsesPerRaid = 1,
            },
            {
                Name = "Titanengriff",
                Description = "Hält einen Feind fest und verursacht massiven Schaden",
                Type = "Active",
                Cooldown = 18,
                StunDuration = 3,
                DamageMultiplier = 2.5,
            },
            {
                Name = "Unbeugsamer Wille",
                Description = "Immun gegen Stun, Slow und Knockback",
                Type = "Passive",
                CCImmunity = { "Stun", "Slow", "Knockback", "Fear" },
            },
            {
                Name = "Kriegsruf",
                Description = "Erhöht Stats aller Verbündeten massiv",
                Type = "Active",
                Cooldown = 30,
                Duration = 10,
                HealthBonus = 0.20,
                DamageBonus = 0.30,
                SpeedBonus = 0.15,
                AoERadius = 30,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
    
    ["arcane_sovereign"] = {
        Id = "arcane_sovereign",
        Name = "Arkaner Herrscher",
        Description = "Der mächtigste Magier aller Zeiten.",
        Rarity = "Legendary",
        Class = "DPS",
        
        BaseHealth = 150,
        BaseDamage = 100,
        BaseSpeed = 10,
        BaseArmor = 20,
        
        AttackRange = 40,
        AttackCooldown = 2.0,
        
        RecruitCost = 120000,
        RecruitGems = 1200,
        
        Abilities = {
            {
                Name = "Arkane Explosion",
                Description = "Verheerender magischer Schaden an allen Feinden",
                Type = "Active",
                Cooldown = 25,
                Damage = 200,
                AoERadius = 50,
            },
            {
                Name = "Zeitverzerrung",
                Description = "Verlangsamt alle Feinde um 80%",
                Type = "Active",
                Cooldown = 35,
                Duration = 5,
                SlowPercent = 0.80,
                AoERadius = 40,
            },
            {
                Name = "Magische Meisterschaft",
                Description = "Alle Fähigkeiten haben 30% kürzere Cooldowns",
                Type = "Passive",
                CooldownReduction = 0.30,
            },
            {
                Name = "Mana-Schild",
                Description = "Absorbiert Schaden und wandelt ihn in Mana um",
                Type = "Passive",
                DamageAbsorbPercent = 0.25,
                DamageToManaRatio = 1.0,
            },
        },
        
        AssetId = "rbxassetid://0",
    },
}

-------------------------------------------------
-- TEAM-SYNERGIEN
-------------------------------------------------
HeroConfig.Synergies = {
    ["holy_trio"] = {
        Name = "Heilige Trinität",
        Description = "Team mit Tank, DPS und Healer",
        RequiredClasses = { "Tank", "DPS", "Healer" },
        Bonus = {
            AllStats = 0.10,     -- +10% auf alle Stats
        },
    },
    
    ["full_assault"] = {
        Name = "Voller Angriff",
        Description = "Team mit 3+ DPS Helden",
        RequiredClassCount = { Class = "DPS", Count = 3 },
        Bonus = {
            Damage = 0.25,      -- +25% Schaden
        },
    },
    
    ["fortress"] = {
        Name = "Festung",
        Description = "Team mit 2+ Tanks",
        RequiredClassCount = { Class = "Tank", Count = 2 },
        Bonus = {
            Health = 0.30,      -- +30% HP für alle
            Armor = 10,         -- +10 Rüstung für alle
        },
    },
    
    ["legendary_duo"] = {
        Name = "Legendäres Duo",
        Description = "Team mit 2 Legendären Helden",
        RequiredRarityCount = { Rarity = "Legendary", Count = 2 },
        Bonus = {
            AllStats = 0.20,    -- +20% auf alle Stats
            CooldownReduction = 0.10,
        },
    },
}

-------------------------------------------------
-- HILFSFUNKTIONEN
-------------------------------------------------

-- Gibt Helden-Daten per ID zurück
function HeroConfig.GetHero(heroId)
    return HeroConfig.Heroes[heroId]
end

-- Gibt alle Helden einer Rarität zurück
function HeroConfig.GetHeroesByRarity(rarity)
    local result = {}
    for id, hero in pairs(HeroConfig.Heroes) do
        if hero.Rarity == rarity then
            table.insert(result, hero)
        end
    end
    return result
end

-- Gibt alle Helden einer Klasse zurück
function HeroConfig.GetHeroesByClass(class)
    local result = {}
    for id, hero in pairs(HeroConfig.Heroes) do
        if hero.Class == class then
            table.insert(result, hero)
        end
    end
    return result
end

-- Berechnet XP für ein bestimmtes Level
function HeroConfig.CalculateXPForLevel(level)
    local settings = HeroConfig.UpgradeSettings
    return math.floor(settings.XPBase * (settings.XPMultiplier ^ (level - 1)))
end

-- Berechnet Gesamt-XP bis zu einem Level
function HeroConfig.CalculateTotalXPToLevel(targetLevel)
    local totalXP = 0
    for level = 1, targetLevel - 1 do
        totalXP = totalXP + HeroConfig.CalculateXPForLevel(level)
    end
    return totalXP
end

-- Berechnet Stats für ein bestimmtes Level
function HeroConfig.CalculateStatsAtLevel(heroId, level)
    local hero = HeroConfig.Heroes[heroId]
    if not hero then return nil end
    
    local settings = HeroConfig.UpgradeSettings
    local rarity = HeroConfig.Rarities[hero.Rarity]
    local class = HeroConfig.Classes[hero.Class]
    local levelBonus = level - 1
    
    -- Basis-Stats mit Raritäts-Multiplikator
    local health = hero.BaseHealth * rarity.StatMultiplier
    local damage = hero.BaseDamage * rarity.StatMultiplier
    local speed = hero.BaseSpeed
    
    -- Klassen-Modifikatoren
    health = health * class.HealthModifier
    damage = damage * class.DamageModifier
    speed = speed * class.SpeedModifier
    
    -- Level-Skalierung
    health = health * (1 + settings.HealthIncrease * levelBonus)
    damage = damage * (1 + settings.DamageIncrease * levelBonus)
    speed = speed * (1 + settings.SpeedIncrease * levelBonus)
    
    return {
        Health = math.floor(health),
        Damage = math.floor(damage),
        Speed = math.floor(speed * 10) / 10,  -- Eine Dezimalstelle
        Armor = hero.BaseArmor,
        AttackRange = hero.AttackRange,
        AttackCooldown = hero.AttackCooldown,
        Abilities = hero.Abilities,
    }
end

-- Prüft und gibt aktive Synergien für ein Team zurück
function HeroConfig.GetActivesynergies(heroIds)
    local activeSynergies = {}
    
    -- Sammle Infos über das Team
    local classCount = {}
    local rarityCount = {}
    
    for _, heroId in ipairs(heroIds) do
        local hero = HeroConfig.Heroes[heroId]
        if hero then
            classCount[hero.Class] = (classCount[hero.Class] or 0) + 1
            rarityCount[hero.Rarity] = (rarityCount[hero.Rarity] or 0) + 1
        end
    end
    
    -- Prüfe jede Synergie
    for synId, synergy in pairs(HeroConfig.Synergies) do
        local isActive = false
        
        -- Prüfe RequiredClasses
        if synergy.RequiredClasses then
            isActive = true
            for _, requiredClass in ipairs(synergy.RequiredClasses) do
                if not classCount[requiredClass] or classCount[requiredClass] < 1 then
                    isActive = false
                    break
                end
            end
        end
        
        -- Prüfe RequiredClassCount
        if synergy.RequiredClassCount then
            local req = synergy.RequiredClassCount
            isActive = classCount[req.Class] and classCount[req.Class] >= req.Count
        end
        
        -- Prüfe RequiredRarityCount
        if synergy.RequiredRarityCount then
            local req = synergy.RequiredRarityCount
            isActive = rarityCount[req.Rarity] and rarityCount[req.Rarity] >= req.Count
        end
        
        if isActive then
            table.insert(activeSynergies, {
                Id = synId,
                Name = synergy.Name,
                Bonus = synergy.Bonus,
            })
        end
    end
    
    return activeSynergies
end

return HeroConfig
