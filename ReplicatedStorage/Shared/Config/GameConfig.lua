--[[
    GameConfig.lua
    Zentrale Konfiguration für "Dungeon Tycoon"
    Pfad: ReplicatedStorage/Shared/Config/GameConfig
    
    WICHTIG: Alle Gameplay-relevanten Konstanten gehören hierher.
    Keine Magic Numbers in anderen Scripts!
]]

local GameConfig = {}

-------------------------------------------------
-- WÄHRUNG
-------------------------------------------------
GameConfig.Currency = {
    -- Startwerte für neue Spieler
    StartingGold = 500,
    StartingGems = 10,
    
    -- Maximale Werte (Soft Cap)
    MaxGold = 1000000000,      -- 1 Milliarde
    MaxGems = 1000000,         -- 1 Million
    
    -- Passive Income (Gold pro Minute pro Dungeon-Level)
    PassiveIncomeBase = 10,
    PassiveIncomeMultiplier = 1.15,  -- Pro Level +15%
}

-------------------------------------------------
-- DUNGEON
-------------------------------------------------
GameConfig.Dungeon = {
    -- Startgröße (Räume)
    StartingRooms = 3,
    MaxRooms = 50,
    
    -- Kosten für neuen Raum (Basis * Multiplikator^AnzahlRäume)
    RoomCostBase = 100,
    RoomCostMultiplier = 1.25,
    
    -- Fallen pro Raum
    MaxTrapsPerRoom = 5,
    
    -- Monster pro Raum
    MaxMonstersPerRoom = 3,
}

-------------------------------------------------
-- HELDEN (für Raids)
-------------------------------------------------
GameConfig.Heroes = {
    -- Maximale Helden im Team
    MaxPartySize = 4,
    
    -- Basis-Stats für Level 1
    BaseHealth = 100,
    BaseDamage = 10,
    BaseSpeed = 10,
    
    -- Stat-Wachstum pro Level (%)
    HealthGrowth = 0.10,    -- +10% pro Level
    DamageGrowth = 0.08,    -- +8% pro Level
    SpeedGrowth = 0.03,     -- +3% pro Level
    
    -- Max Level
    MaxLevel = 100,
}

-------------------------------------------------
-- RAIDS
-------------------------------------------------
GameConfig.Raids = {
    -- Cooldown zwischen Raids (Sekunden)
    RaidCooldown = 300,     -- 5 Minuten
    
    -- Zeitlimit für einen Raid (Sekunden)
    RaidTimeLimit = 120,    -- 2 Minuten
    
    -- Belohnungs-Multiplikator basierend auf Dungeon-Level
    RewardMultiplierBase = 1.0,
    RewardMultiplierPerLevel = 0.05,  -- +5% pro Level
    
    -- Mindest-Dungeon-Level um raiden zu können
    MinDungeonLevelToRaid = 5,
}

-------------------------------------------------
-- PRESTIGE
-------------------------------------------------
GameConfig.Prestige = {
    -- Benötigtes Dungeon-Level für Prestige
    RequiredDungeonLevel = 50,
    
    -- Bonus pro Prestige-Level (%)
    BonusPerPrestige = 0.10,  -- +10% auf alles
    
    -- Max Prestige
    MaxPrestige = 100,
}

-------------------------------------------------
-- TIMING & TICKS
-------------------------------------------------
GameConfig.Timing = {
    -- Passive Income Intervall (Sekunden)
    PassiveIncomeInterval = 60,
    
    -- Auto-Save Intervall (Sekunden)
    AutoSaveInterval = 120,
    
    -- Combat Tick Rate (Sekunden)
    CombatTickRate = 0.5,
}

-------------------------------------------------
-- MOBILE & UI
-------------------------------------------------
GameConfig.UI = {
    -- Touch-Button Größe (Minimum für Mobile)
    MinTouchSize = 48,
    
    -- Animation Durations (Sekunden)
    TweenDurationFast = 0.15,
    TweenDurationNormal = 0.3,
    TweenDurationSlow = 0.5,
}

-------------------------------------------------
-- DEBUG (Nur für Entwicklung)
-------------------------------------------------
GameConfig.Debug = {
    -- Debug-Modus aktivieren
    Enabled = false,
    
    -- Verbose Logging
    VerboseLogging = false,
    
    -- Instant-Cooldowns (für Tests)
    InstantCooldowns = false,
}

return GameConfig