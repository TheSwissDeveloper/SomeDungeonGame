--[[
    DataController.lua
    Client-seitiges Daten-Management
    Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/DataController
    
    Verantwortlich für:
    - Lokales Caching von Server-Daten
    - Schneller synchroner Zugriff für UI
    - State-Management
    - Signals bei Änderungen
    
    WICHTIG: Dies sind GECACHTE Daten!
    Authoritative Daten sind immer auf dem Server!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")

local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))

local DataController = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- LOKALER STATE (Gecachte Server-Daten)
-------------------------------------------------
local cachedData = {
    -- Währung
    Currency = {
        Gold = 0,
        Gems = 0,
    },
    
    -- Dungeon
    Dungeon = {
        Name = "Mein Dungeon",
        Level = 1,
        Experience = 0,
        Rooms = {},
        UnlockedTraps = {},
        UnlockedMonsters = {},
        UnlockedRooms = {},
    },
    
    -- Helden
    Heroes = {
        Owned = {},
        Team = {},
        Unlocked = {},
    },
    
    -- Prestige
    Prestige = {
        Level = 0,
        TotalBonusPercent = 0,
    },
    
    -- Progress
    Progress = {
        Tutorial = {},
        Achievements = {},
    },
    
    -- Cooldowns (lokal getrackt)
    Cooldowns = {
        LastRaidTime = 0,
        LastPassiveCollect = 0,
    },
    
    -- Settings
    Settings = {
        MusicEnabled = true,
        SFXEnabled = true,
        NotificationsEnabled = true,
        Language = "de",
    },
    
    -- Inbox
    Inbox = {},
    
    -- Stats
    Stats = {
        TotalGoldEarned = 0,
        TotalGemsEarned = 0,
        RaidsCompleted = 0,
        RaidsSuccessful = 0,
    },
}

-- UI State (nicht persistiert)
local uiState = {
    SelectedRoom = nil,
    SelectedSlot = nil,
    SelectedHero = nil,
    CurrentTab = "Dungeon",
    IsInRaid = false,
    ActiveRaid = nil,
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
DataController.Signals = {
    CurrencyChanged = SignalUtil.new(),     -- (gold, gems)
    DungeonChanged = SignalUtil.new(),      -- (dungeonData)
    HeroesChanged = SignalUtil.new(),       -- (heroesData)
    PrestigeChanged = SignalUtil.new(),     -- (prestigeData)
    SettingsChanged = SignalUtil.new(),     -- (settingsData)
    InboxChanged = SignalUtil.new(),        -- (inboxData)
    UIStateChanged = SignalUtil.new(),      -- (key, value)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[DataController]", ...)
    end
end

--[[
    Deep-Copy für Tables
]]
local function deepCopy(original)
    if type(original) ~= "table" then
        return original
    end
    
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = deepCopy(value)
    end
    return copy
end

--[[
    Merged neue Daten in bestehende (partielles Update)
]]
local function mergeData(target, source)
    if type(source) ~= "table" then
        return source
    end
    
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            mergeData(target[key], value)
        else
            target[key] = deepCopy(value)
        end
    end
    
    return target
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den DataController
]]
function DataController.Initialize()
    debugPrint("Initialisiere DataController...")
    debugPrint("DataController initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - CURRENCY
-------------------------------------------------

--[[
    Aktualisiert gecachte Währung
    @param gold: Neuer Gold-Wert
    @param gems: Neuer Gems-Wert
]]
function DataController.UpdateCurrency(gold, gems)
    local oldGold = cachedData.Currency.Gold
    local oldGems = cachedData.Currency.Gems
    
    if gold ~= nil then
        cachedData.Currency.Gold = gold
    end
    
    if gems ~= nil then
        cachedData.Currency.Gems = gems
    end
    
    if oldGold ~= cachedData.Currency.Gold or oldGems ~= cachedData.Currency.Gems then
        DataController.Signals.CurrencyChanged:Fire(cachedData.Currency.Gold, cachedData.Currency.Gems)
        debugPrint("Währung aktualisiert: " .. cachedData.Currency.Gold .. " Gold, " .. cachedData.Currency.Gems .. " Gems")
    end
end

--[[
    Gibt aktuelle Währung zurück
    @return: { Gold, Gems }
]]
function DataController.GetCurrency()
    return {
        Gold = cachedData.Currency.Gold,
        Gems = cachedData.Currency.Gems,
    }
end

--[[
    Gibt Gold zurück
    @return: Gold-Wert
]]
function DataController.GetGold()
    return cachedData.Currency.Gold
end

--[[
    Gibt Gems zurück
    @return: Gems-Wert
]]
function DataController.GetGems()
    return cachedData.Currency.Gems
end

--[[
    Gibt formatierten Währungsstring zurück
    @return: { Gold = "💰 1.5K", Gems = "💎 50" }
]]
function DataController.GetFormattedCurrency()
    return {
        Gold = "💰 " .. CurrencyUtil.FormatNumber(cachedData.Currency.Gold),
        Gems = "💎 " .. CurrencyUtil.FormatNumber(cachedData.Currency.Gems),
    }
end

-------------------------------------------------
-- PUBLIC API - DUNGEON
-------------------------------------------------

--[[
    Aktualisiert Dungeon-Daten
    @param data: Partielle oder vollständige Dungeon-Daten
]]
function DataController.UpdateDungeon(data)
    if not data then return end
    
    mergeData(cachedData.Dungeon, data)
    
    DataController.Signals.DungeonChanged:Fire(cachedData.Dungeon)
    debugPrint("Dungeon aktualisiert: Level " .. cachedData.Dungeon.Level)
end

--[[
    Gibt Dungeon-Daten zurück
    @return: Dungeon-Daten
]]
function DataController.GetDungeon()
    return deepCopy(cachedData.Dungeon)
end

--[[
    Gibt Dungeon-Level zurück
    @return: Level
]]
function DataController.GetDungeonLevel()
    return cachedData.Dungeon.Level or 1
end

--[[
    Gibt Räume zurück
    @return: Array von Räumen
]]
function DataController.GetRooms()
    return deepCopy(cachedData.Dungeon.Rooms or {})
end

--[[
    Gibt einen bestimmten Raum zurück
    @param roomIndex: Index des Raums
    @return: Raum-Daten oder nil
]]
function DataController.GetRoom(roomIndex)
    local room = cachedData.Dungeon.Rooms[roomIndex]
    return room and deepCopy(room) or nil
end

--[[
    Prüft ob eine Falle freigeschaltet ist
    @param trapId: Fallen-ID
    @return: boolean
]]
function DataController.IsTrapUnlocked(trapId)
    return cachedData.Dungeon.UnlockedTraps[trapId] == true
end

--[[
    Prüft ob ein Monster freigeschaltet ist
    @param monsterId: Monster-ID
    @return: boolean
]]
function DataController.IsMonsterUnlocked(monsterId)
    return cachedData.Dungeon.UnlockedMonsters[monsterId] == true
end

--[[
    Prüft ob ein Raum-Typ freigeschaltet ist
    @param roomId: Raum-ID
    @return: boolean
]]
function DataController.IsRoomUnlocked(roomId)
    return cachedData.Dungeon.UnlockedRooms[roomId] == true
end

--[[
    Gibt alle freigeschalteten Fallen zurück
    @return: { [trapId] = true }
]]
function DataController.GetUnlockedTraps()
    return deepCopy(cachedData.Dungeon.UnlockedTraps or {})
end

--[[
    Gibt alle freigeschalteten Monster zurück
    @return: { [monsterId] = true }
]]
function DataController.GetUnlockedMonsters()
    return deepCopy(cachedData.Dungeon.UnlockedMonsters or {})
end

-------------------------------------------------
-- PUBLIC API - HEROES
-------------------------------------------------

--[[
    Aktualisiert Helden-Daten
    @param data: Partielle oder vollständige Helden-Daten
]]
function DataController.UpdateHeroes(data)
    if not data then return end
    
    mergeData(cachedData.Heroes, data)
    
    DataController.Signals.HeroesChanged:Fire(cachedData.Heroes)
    debugPrint("Helden aktualisiert")
end

--[[
    Gibt alle Helden im Besitz zurück
    @return: { [instanceId] = heroData }
]]
function DataController.GetOwnedHeroes()
    return deepCopy(cachedData.Heroes.Owned or {})
end

--[[
    Gibt einen bestimmten Helden zurück
    @param instanceId: Instance-ID des Helden
    @return: Helden-Daten oder nil
]]
function DataController.GetHero(instanceId)
    local hero = cachedData.Heroes.Owned[instanceId]
    return hero and deepCopy(hero) or nil
end

--[[
    Gibt das aktuelle Team zurück
    @return: Array von Instance-IDs
]]
function DataController.GetTeam()
    return deepCopy(cachedData.Heroes.Team or {})
end

--[[
    Gibt Team mit Details zurück
    @return: Array von { InstanceId, Hero, Config }
]]
function DataController.GetTeamDetails()
    local team = cachedData.Heroes.Team or {}
    local details = {}
    
    for i, instanceId in ipairs(team) do
        local hero = cachedData.Heroes.Owned[instanceId]
        if hero then
            local config = HeroConfig.GetHero(hero.HeroId)
            details[i] = {
                InstanceId = instanceId,
                Hero = deepCopy(hero),
                Config = config,
            }
        end
    end
    
    return details
end

--[[
    Prüft ob ein Held freigeschaltet ist
    @param heroId: Helden-Typ-ID
    @return: boolean
]]
function DataController.IsHeroUnlocked(heroId)
    return cachedData.Heroes.Unlocked[heroId] == true
end

--[[
    Gibt Anzahl der Helden im Besitz zurück
    @return: count
]]
function DataController.GetHeroCount()
    local count = 0
    for _ in pairs(cachedData.Heroes.Owned or {}) do
        count = count + 1
    end
    return count
end

-------------------------------------------------
-- PUBLIC API - PRESTIGE
-------------------------------------------------

--[[
    Aktualisiert Prestige-Daten
    @param data: Prestige-Daten
]]
function DataController.UpdatePrestige(data)
    if not data then return end
    
    mergeData(cachedData.Prestige, data)
    
    DataController.Signals.PrestigeChanged:Fire(cachedData.Prestige)
    debugPrint("Prestige aktualisiert: Level " .. cachedData.Prestige.Level)
end

--[[
    Gibt Prestige-Daten zurück
    @return: { Level, TotalBonusPercent }
]]
function DataController.GetPrestige()
    return deepCopy(cachedData.Prestige)
end

--[[
    Gibt Prestige-Level zurück
    @return: Level
]]
function DataController.GetPrestigeLevel()
    return cachedData.Prestige.Level or 0
end

--[[
    Gibt Prestige-Bonus zurück
    @return: Bonus als Dezimalzahl (0.1 = 10%)
]]
function DataController.GetPrestigeBonus()
    return cachedData.Prestige.TotalBonusPercent or 0
end

-------------------------------------------------
-- PUBLIC API - COOLDOWNS
-------------------------------------------------

--[[
    Aktualisiert Cooldown-Daten
    @param key: Cooldown-Key
    @param timestamp: Unix-Timestamp
]]
function DataController.UpdateCooldown(key, timestamp)
    cachedData.Cooldowns[key] = timestamp
end

--[[
    Gibt verbleibendes Raid-Cooldown zurück
    @return: Sekunden (0 wenn bereit)
]]
function DataController.GetRaidCooldown()
    local lastRaid = cachedData.Cooldowns.LastRaidTime or 0
    local cooldownTime = GameConfig.Raids.RaidCooldown
    local remaining = (lastRaid + cooldownTime) - os.time()
    
    return math.max(0, remaining)
end

--[[
    Gibt akkumuliertes Passiv-Einkommen zurück
    @return: Gold-Menge
]]
function DataController.GetPendingPassiveIncome()
    local lastCollect = cachedData.Cooldowns.LastPassiveCollect or os.time()
    local dungeonLevel = cachedData.Dungeon.Level or 1
    local prestigeLevel = cachedData.Prestige.Level or 0
    
    return CurrencyUtil.CalculateAccumulatedIncome(
        dungeonLevel,
        prestigeLevel,
        lastCollect,
        os.time()
    )
end

--[[
    Gibt Passiv-Einkommen pro Minute zurück
    @return: Gold pro Minute
]]
function DataController.GetPassiveIncomePerMinute()
    local dungeonLevel = cachedData.Dungeon.Level or 1
    local prestigeLevel = cachedData.Prestige.Level or 0
    
    return CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
end

-------------------------------------------------
-- PUBLIC API - SETTINGS
-------------------------------------------------

--[[
    Aktualisiert Settings
    @param data: Settings-Daten
]]
function DataController.UpdateSettings(data)
    if not data then return end
    
    mergeData(cachedData.Settings, data)
    
    DataController.Signals.SettingsChanged:Fire(cachedData.Settings)
end

--[[
    Gibt Settings zurück
    @return: Settings-Tabelle
]]
function DataController.GetSettings()
    return deepCopy(cachedData.Settings)
end

--[[
    Gibt einzelne Einstellung zurück
    @param key: Setting-Key
    @return: Wert
]]
function DataController.GetSetting(key)
    return cachedData.Settings[key]
end

--[[
    Setzt eine Einstellung (lokal)
    @param key: Setting-Key
    @param value: Neuer Wert
]]
function DataController.SetSetting(key, value)
    cachedData.Settings[key] = value
    DataController.Signals.SettingsChanged:Fire(cachedData.Settings)
end

-------------------------------------------------
-- PUBLIC API - INBOX
-------------------------------------------------

--[[
    Aktualisiert Inbox
    @param inbox: Inbox-Array
]]
function DataController.UpdateInbox(inbox)
    cachedData.Inbox = deepCopy(inbox or {})
    DataController.Signals.InboxChanged:Fire(cachedData.Inbox)
end

--[[
    Gibt Inbox zurück
    @return: Inbox-Array
]]
function DataController.GetInbox()
    return deepCopy(cachedData.Inbox)
end

--[[
    Gibt Anzahl ungelesener Inbox-Items zurück
    @return: count
]]
function DataController.GetUnreadInboxCount()
    local count = 0
    for _, item in ipairs(cachedData.Inbox or {}) do
        if not item.Claimed then
            count = count + 1
        end
    end
    return count
end

-------------------------------------------------
-- PUBLIC API - PROGRESS
-------------------------------------------------

--[[
    Aktualisiert Progress
    @param data: Progress-Daten
]]
function DataController.UpdateProgress(data)
    if not data then return end
    mergeData(cachedData.Progress, data)
end

--[[
    Prüft ob Tutorial-Schritt abgeschlossen
    @param stepName: Name des Schritts
    @return: boolean
]]
function DataController.IsTutorialComplete(stepName)
    return cachedData.Progress.Tutorial[stepName] == true
end

--[[
    Prüft ob Tutorial komplett abgeschlossen
    @return: boolean
]]
function DataController.IsTutorialFinished()
    local requiredSteps = { "Intro", "FirstRoom", "FirstTrap", "FirstMonster", "FirstRaid" }
    
    for _, step in ipairs(requiredSteps) do
        if not cachedData.Progress.Tutorial[step] then
            return false
        end
    end
    
    return true
end

-------------------------------------------------
-- PUBLIC API - UI STATE
-------------------------------------------------

--[[
    Setzt UI-State
    @param key: State-Key
    @param value: Neuer Wert
]]
function DataController.SetUIState(key, value)
    uiState[key] = value
    DataController.Signals.UIStateChanged:Fire(key, value)
end

--[[
    Gibt UI-State zurück
    @param key: State-Key
    @return: Wert
]]
function DataController.GetUIState(key)
    return uiState[key]
end

--[[
    Gibt gesamten UI-State zurück
    @return: UI-State-Tabelle
]]
function DataController.GetFullUIState()
    return deepCopy(uiState)
end

-------------------------------------------------
-- PUBLIC API - VOLLSTÄNDIGE DATEN
-------------------------------------------------

--[[
    Gibt alle gecachten Daten zurück
    @return: Vollständige Daten-Kopie
]]
function DataController.GetData()
    return deepCopy(cachedData)
end

--[[
    Setzt alle Daten (für initiales Laden)
    @param data: Vollständige Spielerdaten
]]
function DataController.SetFullData(data)
    if not data then return end
    
    if data.Currency then
        cachedData.Currency = deepCopy(data.Currency)
    end
    
    if data.Dungeon then
        cachedData.Dungeon = deepCopy(data.Dungeon)
    end
    
    if data.Heroes then
        cachedData.Heroes = deepCopy(data.Heroes)
    end
    
    if data.Prestige then
        cachedData.Prestige = deepCopy(data.Prestige)
    end
    
    if data.Progress then
        cachedData.Progress = deepCopy(data.Progress)
    end
    
    if data.Cooldowns then
        cachedData.Cooldowns = deepCopy(data.Cooldowns)
    end
    
    if data.Settings then
        cachedData.Settings = deepCopy(data.Settings)
    end
    
    if data.Inbox then
        cachedData.Inbox = deepCopy(data.Inbox)
    end
    
    if data.Stats then
        cachedData.Stats = deepCopy(data.Stats)
    end
    
    -- Alle Signals feuern
    DataController.Signals.CurrencyChanged:Fire(cachedData.Currency.Gold, cachedData.Currency.Gems)
    DataController.Signals.DungeonChanged:Fire(cachedData.Dungeon)
    DataController.Signals.HeroesChanged:Fire(cachedData.Heroes)
    DataController.Signals.PrestigeChanged:Fire(cachedData.Prestige)
    DataController.Signals.SettingsChanged:Fire(cachedData.Settings)
    DataController.Signals.InboxChanged:Fire(cachedData.Inbox)
    
    debugPrint("Vollständige Daten gesetzt")
end

-------------------------------------------------
-- PUBLIC API - RAID STATE
-------------------------------------------------

--[[
    Setzt aktiven Raid
    @param raidData: Raid-Daten
]]
function DataController.SetActiveRaid(raidData)
    uiState.IsInRaid = raidData ~= nil
    uiState.ActiveRaid = raidData and deepCopy(raidData) or nil
end

--[[
    Gibt aktiven Raid zurück
    @return: Raid-Daten oder nil
]]
function DataController.GetActiveRaid()
    return uiState.ActiveRaid and deepCopy(uiState.ActiveRaid) or nil
end

--[[
    Prüft ob Spieler in Raid ist
    @return: boolean
]]
function DataController.IsInRaid()
    return uiState.IsInRaid == true
end

return DataController
