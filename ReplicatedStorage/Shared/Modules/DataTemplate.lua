--[[
    DataTemplate.lua
    Spieler-Datenstruktur für "Dungeon Tycoon"
    Pfad: ReplicatedStorage/Shared/Modules/DataTemplate
    
    WICHTIG: Diese Struktur definiert ALLE Spielerdaten.
    Änderungen hier erfordern Migrations-Logik im DataManager!
    
    Versionierung:
    - Version wird bei Schema-Änderungen erhöht
    - DataManager prüft Version und migriert alte Daten
]]

local DataTemplate = {}

-------------------------------------------------
-- AKTUELLE DATEN-VERSION
-------------------------------------------------
DataTemplate.Version = 1

-------------------------------------------------
-- SPIELER-DATEN TEMPLATE
-------------------------------------------------
DataTemplate.Template = {
    -------------------------------------------------
    -- META-DATEN
    -------------------------------------------------
    Version = 1,                    -- Für Migrationen
    CreatedAt = 0,                  -- Unix Timestamp (wird beim Erstellen gesetzt)
    LastLogin = 0,                  -- Unix Timestamp
    TotalPlayTime = 0,              -- Sekunden
    
    -------------------------------------------------
    -- WÄHRUNGEN
    -------------------------------------------------
    Currency = {
        Gold = 500,                 -- Startwert aus GameConfig
        Gems = 10,                  -- Startwert aus GameConfig
    },
    
    -------------------------------------------------
    -- STATISTIKEN
    -------------------------------------------------
    Stats = {
        -- Allgemein
        TotalGoldEarned = 0,
        TotalGemsEarned = 0,
        TotalGoldSpent = 0,
        TotalGemsSpent = 0,
        
        -- Raids (als Angreifer)
        RaidsCompleted = 0,
        RaidsSuccessful = 0,        -- Dungeon komplett durchgelaufen
        RaidsFailed = 0,            -- Alle Helden gestorben
        TotalRaidDamageDealt = 0,
        
        -- Defense (eigener Dungeon)
        TimesRaided = 0,
        SuccessfulDefenses = 0,     -- Angreifer gescheitert
        FailedDefenses = 0,         -- Angreifer erfolgreich
        TotalDefenseDamageDealt = 0,
        
        -- Kills
        HeroesKilled = 0,           -- Im eigenen Dungeon
        MonstersKilled = 0,         -- Bei Raids
        TrapsTriggered = 0,         -- Eigene Fallen ausgelöst
    },
    
    -------------------------------------------------
    -- DUNGEON
    -------------------------------------------------
    Dungeon = {
        -- Allgemein
        Level = 1,
        Experience = 0,
        Name = "Unbenannter Dungeon",
        
        -- Räume: Array von Raum-Daten
        -- Index = Position im Dungeon (1 = Eingang, aufsteigend)
        Rooms = {
            -- Starter-Räume (3 Stück)
            [1] = {
                RoomId = "stone_corridor",
                Level = 1,
                Traps = {},         -- { [SlotIndex] = { TrapId, Level } }
                Monsters = {},      -- { [SlotIndex] = { MonsterId, Level } }
            },
            [2] = {
                RoomId = "stone_corridor",
                Level = 1,
                Traps = {},
                Monsters = {},
            },
            [3] = {
                RoomId = "guard_chamber",
                Level = 1,
                Traps = {},
                Monsters = {},
            },
        },
        
        -- Freigeschaltete Räume (gekauft aber nicht platziert)
        UnlockedRooms = {},         -- { RoomId = true }
        
        -- Freigeschaltete Fallen
        UnlockedTraps = {
            ["spike_floor"] = true,     -- Starter-Falle
            ["arrow_wall"] = true,      -- Starter-Falle
        },
        
        -- Freigeschaltete Monster
        UnlockedMonsters = {
            ["skeleton"] = true,        -- Starter-Monster
            ["slime"] = true,           -- Starter-Monster
        },
    },
    
    -------------------------------------------------
    -- HELDEN (für Raids)
    -------------------------------------------------
    Heroes = {
        -- Rekrutierte Helden
        -- Key = Unique Instance ID (generiert bei Rekrutierung)
        Owned = {
            --[[
            ["hero_uuid_123"] = {
                HeroId = "knight",      -- Referenz zu HeroConfig
                Level = 1,
                Experience = 0,
                Rarity = "Common",      -- Wird bei Rekrutierung gewürfelt
            },
            ]]
        },
        
        -- Aktuelles Raid-Team (max 4 Helden)
        -- Array von Hero Instance IDs
        Team = {},                  -- { "hero_uuid_123", "hero_uuid_456", ... }
        
        -- Freigeschaltete Helden (können rekrutiert werden)
        Unlocked = {
            ["knight"] = true,      -- Starter
            ["archer"] = true,      -- Starter
            ["apprentice"] = true,  -- Starter
            ["cleric"] = true,      -- Starter
        },
    },
    
    -------------------------------------------------
    -- COOLDOWNS & TIMER
    -------------------------------------------------
    Cooldowns = {
        LastRaidTime = 0,           -- Unix Timestamp des letzten Raids
        LastPassiveCollect = 0,     -- Wann wurde passives Einkommen zuletzt gesammelt
    },
    
    -------------------------------------------------
    -- PRESTIGE
    -------------------------------------------------
    Prestige = {
        Level = 0,                  -- Anzahl Prestiges
        TotalBonusPercent = 0,      -- Kumulierter Bonus (berechnet aus Level)
    },
    
    -------------------------------------------------
    -- EINSTELLUNGEN
    -------------------------------------------------
    Settings = {
        MusicEnabled = true,
        SFXEnabled = true,
        NotificationsEnabled = true,
        Language = "de",            -- Sprach-Code
    },
    
    -------------------------------------------------
    -- TUTORIAL & ACHIEVEMENTS
    -------------------------------------------------
    Progress = {
        -- Tutorial-Schritte (abgeschlossen = true)
        Tutorial = {
            Intro = false,
            FirstRoom = false,
            FirstTrap = false,
            FirstMonster = false,
            FirstRaid = false,
            FirstDefense = false,
        },
        
        -- Achievements
        Achievements = {
            --[[
            ["achievement_id"] = {
                Unlocked = true,
                UnlockedAt = 123456789,  -- Unix Timestamp
            },
            ]]
        },
    },
    
    -------------------------------------------------
    -- INBOX / BELOHNUNGEN
    -------------------------------------------------
    Inbox = {
        -- Nicht abgeholte Belohnungen
        --[[
        {
            Id = "reward_uuid",
            Type = "RaidReward",        -- oder "DailyLogin", "Achievement", etc.
            Rewards = {
                Gold = 500,
                Gems = 5,
            },
            CreatedAt = 123456789,
            ExpiresAt = 123456789,      -- Optional
            Claimed = false,
        },
        ]]
    },
}

-------------------------------------------------
-- HILFSFUNKTIONEN
-------------------------------------------------

-- Erstellt eine tiefe Kopie des Templates
function DataTemplate.GetNewPlayerData()
    local function deepCopy(original)
        local copy = {}
        for key, value in pairs(original) do
            if type(value) == "table" then
                copy[key] = deepCopy(value)
            else
                copy[key] = value
            end
        end
        return copy
    end
    
    local newData = deepCopy(DataTemplate.Template)
    
    -- Setze Timestamps
    local now = os.time()
    newData.CreatedAt = now
    newData.LastLogin = now
    newData.Cooldowns.LastPassiveCollect = now
    
    return newData
end

-- Validiert Spielerdaten und füllt fehlende Felder
function DataTemplate.Validate(playerData)
    local template = DataTemplate.Template
    
    local function validateTable(data, templateTable, path)
        path = path or "root"
        
        -- Füge fehlende Felder hinzu
        for key, templateValue in pairs(templateTable) do
            if data[key] == nil then
                -- Feld fehlt, füge es hinzu
                if type(templateValue) == "table" then
                    data[key] = DataTemplate._deepCopy(templateValue)
                else
                    data[key] = templateValue
                end
                warn("[DataTemplate] Fehlendes Feld hinzugefügt: " .. path .. "." .. tostring(key))
            elseif type(templateValue) == "table" and type(data[key]) == "table" then
                -- Rekursiv validieren für verschachtelte Tabellen
                -- Aber nicht für Arrays (Rooms, Owned, etc.)
                if templateValue[1] == nil and data[key][1] == nil then
                    validateTable(data[key], templateValue, path .. "." .. tostring(key))
                end
            end
        end
    end
    
    validateTable(playerData, template)
    return playerData
end

-- Interne Deep Copy Funktion
function DataTemplate._deepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = DataTemplate._deepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- Migriert alte Daten auf neue Version
function DataTemplate.Migrate(playerData)
    local currentVersion = playerData.Version or 0
    
    -- Migration v0 -> v1
    if currentVersion < 1 then
        -- Beispiel: Neue Felder hinzufügen
        playerData.Version = 1
        
        -- Stelle sicher dass alle neuen Felder existieren
        playerData = DataTemplate.Validate(playerData)
        
        print("[DataTemplate] Migriert von v" .. currentVersion .. " auf v1")
    end
    
    -- Zukünftige Migrationen hier hinzufügen:
    -- if currentVersion < 2 then
    --     -- Migration v1 -> v2
    --     playerData.Version = 2
    -- end
    
    return playerData
end

-- Generiert eine einzigartige ID für Helden-Instanzen
function DataTemplate.GenerateUniqueId()
    -- Format: timestamp_random
    local timestamp = os.time()
    local random = math.random(100000, 999999)
    return string.format("%d_%d", timestamp, random)
end

-- Berechnet Dungeon-Level basierend auf XP
function DataTemplate.CalculateDungeonLevel(experience)
    -- Einfache Formel: Level = floor(sqrt(XP / 100)) + 1
    -- Level 1 = 0 XP
    -- Level 2 = 100 XP
    -- Level 3 = 400 XP
    -- Level 10 = 8100 XP
    local level = math.floor(math.sqrt(experience / 100)) + 1
    return math.min(level, 100)  -- Max Level 100
end

-- Berechnet benötigte XP für nächstes Level
function DataTemplate.GetXPForNextLevel(currentLevel)
    -- XP für Level N = (N-1)^2 * 100
    local nextLevel = currentLevel + 1
    return (nextLevel - 1) ^ 2 * 100
end

return DataTemplate
