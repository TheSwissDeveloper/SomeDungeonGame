--[[
    HeroSystem.lua
    Zentrales System für Helden-Management
    Pfad: ServerScriptService/Server/Systems/HeroSystem
    
    Verantwortlich für:
    - Helden-Rekrutierung (mit Raritäts-Roll)
    - Team-Management
    - XP-Verteilung und Level-Ups
    - Helden-Entlassung
    
    WICHTIG: Nutzt CurrencyService für Transaktionen!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Auf Shared-Module warten
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")
local RemotesPath = SharedPath:WaitForChild("Remotes")

-- Module laden
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local DataTemplate = require(ModulesPath:WaitForChild("DataTemplate"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Service/Manager-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil
local CurrencyService = nil

local HeroSystem = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Maximale Helden im Besitz
    MaxOwnedHeroes = 50,
    
    -- XP-Verteilung nach Raid
    XPPerRaidParticipation = 50,
    XPPerMonsterKill = 10,
    XPPerRoomCleared = 25,
    XPBonusForVictory = 100,
    XPBonusForSurvival = 50,     -- Held überlebt den Raid
    
    -- Entlassungs-Rückerstattung (% der Rekrutierungskosten)
    DismissRefundPercent = 0.25,
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
HeroSystem.Signals = {
    HeroRecruited = SignalUtil.new(),       -- (player, heroInstanceId, heroData)
    HeroDismissed = SignalUtil.new(),       -- (player, heroInstanceId)
    HeroLevelUp = SignalUtil.new(),         -- (player, heroInstanceId, newLevel)
    TeamChanged = SignalUtil.new(),         -- (player, newTeam, synergies)
    XPGained = SignalUtil.new(),            -- (player, heroInstanceId, xpAmount)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[HeroSystem]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[HeroSystem]", ...)
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

--[[
    Würfelt eine Rarität basierend auf Drop-Chancen
    @return: Raritäts-String
]]
local function rollRarity()
    local roll = math.random()
    local cumulative = 0
    
    -- Sortiert nach Seltenheit (Legendary zuerst prüfen)
    local order = { "Legendary", "Epic", "Rare", "Uncommon", "Common" }
    
    for _, rarityName in ipairs(order) do
        local rarityData = HeroConfig.Rarities[rarityName]
        if rarityData then
            cumulative = cumulative + rarityData.DropChance
            if roll <= cumulative then
                return rarityName
            end
        end
    end
    
    return "Common"  -- Fallback
end

--[[
    Berechnet XP für Level-Up
    @param hero: Helden-Daten
    @param xpAmount: Hinzuzufügende XP
    @return: newLevel, newXP, leveledUp
]]
local function processHeroXP(hero, xpAmount)
    local currentLevel = hero.Level or 1
    local currentXP = hero.Experience or 0
    local maxLevel = HeroConfig.UpgradeSettings.MaxLevel
    
    if currentLevel >= maxLevel then
        return currentLevel, 0, false
    end
    
    local newXP = currentXP + xpAmount
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
    
    -- Bei Max-Level keine überschüssige XP
    if newLevel >= maxLevel then
        newXP = 0
    end
    
    return newLevel, newXP, leveledUp
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert das HeroSystem
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
    @param currencyServiceRef: Referenz zum CurrencyService
]]
function HeroSystem.Initialize(dataManagerRef, playerManagerRef, currencyServiceRef)
    debugPrint("Initialisiere HeroSystem...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    CurrencyService = currencyServiceRef
    
    debugPrint("HeroSystem initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - REKRUTIERUNG
-------------------------------------------------

--[[
    Rekrutiert einen neuen Helden
    @param player: Der Spieler
    @param heroId: ID des Helden-Typs
    @return: success, errorMessage/heroData
]]
function HeroSystem.RecruitHero(player, heroId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    -- Hero-Config prüfen
    local heroConfig = HeroConfig.GetHero(heroId)
    if not heroConfig then
        return false, "Ungültiger Held"
    end
    
    -- Freischaltung prüfen
    if not data.Heroes.Unlocked[heroId] then
        return false, "Held nicht freigeschaltet"
    end
    
    -- Max Helden prüfen
    local ownedCount = 0
    for _ in pairs(data.Heroes.Owned) do
        ownedCount = ownedCount + 1
    end
    
    if ownedCount >= CONFIG.MaxOwnedHeroes then
        return false, "Maximale Helden-Anzahl erreicht (" .. CONFIG.MaxOwnedHeroes .. ")"
    end
    
    -- Kosten berechnen
    local cost = {
        Gold = heroConfig.RecruitCost,
        Gems = heroConfig.RecruitGems,
    }
    cost = CurrencyService.CalculateCostWithDiscount(player, cost)
    
    -- Kauf durchführen
    local success, purchaseError = CurrencyService.Purchase(
        player,
        cost,
        CurrencyService.TransactionType.HeroRecruit,
        "Hero:" .. heroId
    )
    
    if not success then
        return false, purchaseError
    end
    
    -- Rarität würfeln
    local rarity = rollRarity()
    
    -- Einzigartige ID generieren
    local heroInstanceId = DataTemplate.GenerateUniqueId()
    
    -- Neuen Helden erstellen
    local newHero = {
        HeroId = heroId,
        Level = 1,
        Experience = 0,
        Rarity = rarity,
        RecruitedAt = os.time(),
    }
    
    -- Helden hinzufügen
    data.Heroes.Owned[heroInstanceId] = newHero
    DataManager.SetValue(player, "Heroes.Owned", data.Heroes.Owned)
    
    -- Client updaten
    sendHeroesUpdate(player, DataManager.GetData(player))
    
    -- Benachrichtigung mit Raritäts-Info
    local rarityData = HeroConfig.Rarities[rarity]
    local rarityName = rarityData and rarityData.Name or rarity
    
    if PlayerManager then
        local notificationType = "Success"
        if rarity == "Legendary" then
            notificationType = "Success"  -- Könnte spezielle Animation triggern
        elseif rarity == "Epic" then
            notificationType = "Success"
        end
        
        PlayerManager.SendNotification(
            player,
            "Held rekrutiert!",
            heroConfig.Name .. " (" .. rarityName .. ")",
            notificationType
        )
    end
    
    -- Signal feuern
    HeroSystem.Signals.HeroRecruited:Fire(player, heroInstanceId, newHero)
    
    debugPrint(player.Name .. " hat " .. heroConfig.Name .. " (" .. rarity .. ") rekrutiert")
    
    return true, {
        InstanceId = heroInstanceId,
        Hero = newHero,
        Rarity = rarity,
        RarityName = rarityName,
    }
end

--[[
    Entlässt einen Helden (mit Teil-Rückerstattung)
    @param player: Der Spieler
    @param heroInstanceId: Instance-ID des Helden
    @return: success, errorMessage, refund
]]
function HeroSystem.DismissHero(player, heroInstanceId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Held prüfen
    local hero = data.Heroes.Owned[heroInstanceId]
    if not hero then
        return false, "Held nicht gefunden", nil
    end
    
    -- Prüfen ob Held im Team ist
    for i, teamHeroId in ipairs(data.Heroes.Team or {}) do
        if teamHeroId == heroInstanceId then
            -- Aus Team entfernen
            table.remove(data.Heroes.Team, i)
            DataManager.SetValue(player, "Heroes.Team", data.Heroes.Team)
            break
        end
    end
    
    -- Hero-Config für Rückerstattung
    local heroConfig = HeroConfig.GetHero(hero.HeroId)
    local refund = { Gold = 0, Gems = 0 }
    
    if heroConfig then
        -- Basis-Rückerstattung
        refund.Gold = math.floor(heroConfig.RecruitCost * CONFIG.DismissRefundPercent)
        refund.Gems = math.floor(heroConfig.RecruitGems * CONFIG.DismissRefundPercent)
        
        -- Bonus basierend auf Level
        local levelBonus = (hero.Level - 1) * 0.05  -- +5% pro Level über 1
        refund.Gold = math.floor(refund.Gold * (1 + levelBonus))
        
        -- Rückerstattung geben
        if refund.Gold > 0 or refund.Gems > 0 then
            CurrencyService.GiveReward(
                player,
                refund,
                CurrencyService.TransactionType.Refund,
                "DismissHero:" .. heroInstanceId
            )
        end
    end
    
    -- Held entfernen
    data.Heroes.Owned[heroInstanceId] = nil
    DataManager.SetValue(player, "Heroes.Owned", data.Heroes.Owned)
    
    -- Client updaten
    sendHeroesUpdate(player, DataManager.GetData(player))
    
    -- Benachrichtigung
    if PlayerManager and heroConfig then
        PlayerManager.SendNotification(
            player,
            "Held entlassen",
            heroConfig.Name .. " wurde entlassen.",
            "Info"
        )
    end
    
    -- Signal feuern
    HeroSystem.Signals.HeroDismissed:Fire(player, heroInstanceId)
    
    debugPrint(player.Name .. " hat Held entlassen: " .. heroInstanceId)
    
    return true, nil, refund
end

-------------------------------------------------
-- PUBLIC API - TEAM-MANAGEMENT
-------------------------------------------------

--[[
    Setzt das Raid-Team
    @param player: Der Spieler
    @param teamIds: Array von Hero-Instance-IDs
    @return: success, errorMessage, synergies
]]
function HeroSystem.SetTeam(player, teamIds)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen", nil
    end
    
    -- Validierung
    if type(teamIds) ~= "table" then
        return false, "Ungültiges Team-Format", nil
    end
    
    -- Max Team-Größe
    local maxTeamSize = GameConfig.Heroes.MaxPartySize
    if #teamIds > maxTeamSize then
        return false, "Zu viele Helden im Team (max " .. maxTeamSize .. ")", nil
    end
    
    -- Duplikate prüfen
    local seen = {}
    for _, heroId in ipairs(teamIds) do
        if seen[heroId] then
            return false, "Held kann nicht mehrfach im Team sein", nil
        end
        seen[heroId] = true
    end
    
    -- Prüfen ob alle Helden dem Spieler gehören
    for _, heroInstanceId in ipairs(teamIds) do
        if not data.Heroes.Owned[heroInstanceId] then
            return false, "Held nicht im Besitz: " .. heroInstanceId, nil
        end
    end
    
    -- Team setzen
    DataManager.SetValue(player, "Heroes.Team", teamIds)
    
    -- Synergien berechnen
    local heroBaseIds = {}
    for _, heroInstanceId in ipairs(teamIds) do
        local hero = data.Heroes.Owned[heroInstanceId]
        if hero then
            table.insert(heroBaseIds, hero.HeroId)
        end
    end
    local synergies = HeroConfig.GetActivesynergies(heroBaseIds)
    
    -- Client updaten
    sendHeroesUpdate(player, DataManager.GetData(player))
    
    -- Signal feuern
    HeroSystem.Signals.TeamChanged:Fire(player, teamIds, synergies)
    
    -- Synergy-Benachrichtigung
    if PlayerManager and #synergies > 0 then
        local synergyNames = {}
        for _, syn in ipairs(synergies) do
            table.insert(synergyNames, syn.Name)
        end
        
        PlayerManager.SendNotification(
            player,
            "Team-Synergie aktiv!",
            table.concat(synergyNames, ", "),
            "Success"
        )
    end
    
    debugPrint(player.Name .. " hat Team gesetzt: " .. #teamIds .. " Helden, " .. #synergies .. " Synergien")
    
    return true, nil, synergies
end

--[[
    Fügt einen Helden zum Team hinzu
    @param player: Der Spieler
    @param heroInstanceId: Instance-ID des Helden
    @return: success, errorMessage
]]
function HeroSystem.AddToTeam(player, heroInstanceId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    -- Held prüfen
    if not data.Heroes.Owned[heroInstanceId] then
        return false, "Held nicht im Besitz"
    end
    
    -- Team prüfen
    local team = data.Heroes.Team or {}
    
    -- Bereits im Team?
    for _, id in ipairs(team) do
        if id == heroInstanceId then
            return false, "Held bereits im Team"
        end
    end
    
    -- Team voll?
    if #team >= GameConfig.Heroes.MaxPartySize then
        return false, "Team ist voll (max " .. GameConfig.Heroes.MaxPartySize .. ")"
    end
    
    -- Hinzufügen
    table.insert(team, heroInstanceId)
    
    return HeroSystem.SetTeam(player, team)
end

--[[
    Entfernt einen Helden aus dem Team
    @param player: Der Spieler
    @param heroInstanceId: Instance-ID des Helden
    @return: success, errorMessage
]]
function HeroSystem.RemoveFromTeam(player, heroInstanceId)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local team = data.Heroes.Team or {}
    local newTeam = {}
    local found = false
    
    for _, id in ipairs(team) do
        if id == heroInstanceId then
            found = true
        else
            table.insert(newTeam, id)
        end
    end
    
    if not found then
        return false, "Held nicht im Team"
    end
    
    return HeroSystem.SetTeam(player, newTeam)
end

--[[
    Tauscht die Position zweier Helden im Team
    @param player: Der Spieler
    @param position1: Erste Position (1-basiert)
    @param position2: Zweite Position (1-basiert)
    @return: success, errorMessage
]]
function HeroSystem.SwapTeamPositions(player, position1, position2)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local team = data.Heroes.Team or {}
    
    if position1 < 1 or position1 > #team or position2 < 1 or position2 > #team then
        return false, "Ungültige Position"
    end
    
    -- Tauschen
    team[position1], team[position2] = team[position2], team[position1]
    
    return HeroSystem.SetTeam(player, team)
end

-------------------------------------------------
-- PUBLIC API - XP & LEVEL
-------------------------------------------------

--[[
    Verteilt XP an alle Team-Helden nach einem Raid
    @param player: Der Spieler
    @param raidResult: Ergebnis des Raids
    @return: xpDistribution { [heroInstanceId] = { xp, leveledUp, newLevel } }
]]
function HeroSystem.DistributeRaidXP(player, raidResult)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return nil
    end
    
    local distribution = {}
    local team = data.Heroes.Team or {}
    
    for _, heroInstanceId in ipairs(team) do
        local hero = data.Heroes.Owned[heroInstanceId]
        if hero then
            -- Basis-XP
            local xp = CONFIG.XPPerRaidParticipation
            
            -- Bonus für Kills
            xp = xp + (raidResult.Stats.MonstersKilled or 0) * CONFIG.XPPerMonsterKill
            
            -- Bonus für Räume
            xp = xp + (raidResult.Stats.RoomsCleared or 0) * CONFIG.XPPerRoomCleared
            
            -- Bonus für Sieg
            if raidResult.Status == "Victory" then
                xp = xp + CONFIG.XPBonusForVictory
            end
            
            -- Bonus für Überleben (prüfen ob Held noch lebt)
            if raidResult.Heroes and raidResult.Heroes[heroInstanceId] then
                if raidResult.Heroes[heroInstanceId].IsAlive then
                    xp = xp + CONFIG.XPBonusForSurvival
                end
            end
            
            -- XP hinzufügen
            local newLevel, newXP, leveledUp = processHeroXP(hero, xp)
            
            hero.Level = newLevel
            hero.Experience = newXP
            
            distribution[heroInstanceId] = {
                XP = xp,
                LeveledUp = leveledUp,
                NewLevel = newLevel,
                HeroId = hero.HeroId,
            }
            
            -- Signal für Level-Up
            if leveledUp then
                HeroSystem.Signals.HeroLevelUp:Fire(player, heroInstanceId, newLevel)
                
                local heroConfig = HeroConfig.GetHero(hero.HeroId)
                if PlayerManager and heroConfig then
                    PlayerManager.SendNotification(
                        player,
                        "Held Level Up!",
                        heroConfig.Name .. " ist jetzt Level " .. newLevel,
                        "Success"
                    )
                end
            end
            
            -- XP Signal
            HeroSystem.Signals.XPGained:Fire(player, heroInstanceId, xp)
        end
    end
    
    -- Daten speichern
    DataManager.SetValue(player, "Heroes.Owned", data.Heroes.Owned)
    
    -- Client updaten
    sendHeroesUpdate(player, DataManager.GetData(player))
    
    debugPrint(player.Name .. " XP verteilt an " .. #team .. " Helden")
    
    return distribution
end

--[[
    Fügt XP zu einem einzelnen Helden hinzu
    @param player: Der Spieler
    @param heroInstanceId: Instance-ID des Helden
    @param xpAmount: XP-Menge
    @return: success, newLevel, leveledUp
]]
function HeroSystem.AddHeroXP(player, heroInstanceId, xpAmount)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, nil, false
    end
    
    local hero = data.Heroes.Owned[heroInstanceId]
    if not hero then
        return false, nil, false
    end
    
    local newLevel, newXP, leveledUp = processHeroXP(hero, xpAmount)
    
    hero.Level = newLevel
    hero.Experience = newXP
    
    DataManager.SetValue(player, "Heroes.Owned", data.Heroes.Owned)
    
    -- Client updaten
    sendHeroesUpdate(player, DataManager.GetData(player))
    
    -- Signals
    HeroSystem.Signals.XPGained:Fire(player, heroInstanceId, xpAmount)
    
    if leveledUp then
        HeroSystem.Signals.HeroLevelUp:Fire(player, heroInstanceId, newLevel)
    end
    
    return true, newLevel, leveledUp
end

-------------------------------------------------
-- PUBLIC API - ABFRAGEN
-------------------------------------------------

--[[
    Gibt alle Helden eines Spielers zurück
    @param player: Der Spieler
    @return: { [instanceId] = heroData }
]]
function HeroSystem.GetOwnedHeroes(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    return data.Heroes.Owned
end

--[[
    Gibt einen einzelnen Helden zurück
    @param player: Der Spieler
    @param heroInstanceId: Instance-ID
    @return: heroData oder nil
]]
function HeroSystem.GetHero(player, heroInstanceId)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    return data.Heroes.Owned[heroInstanceId]
end

--[[
    Gibt das aktuelle Team zurück
    @param player: Der Spieler
    @return: Array von Instance-IDs
]]
function HeroSystem.GetTeam(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    return data.Heroes.Team or {}
end

--[[
    Gibt Team-Details mit Stats zurück
    @param player: Der Spieler
    @return: { Heroes = {...}, Synergies = {...}, TotalStats = {...} }
]]
function HeroSystem.GetTeamDetails(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    local team = data.Heroes.Team or {}
    local heroes = {}
    local heroBaseIds = {}
    
    local totalStats = {
        Health = 0,
        Damage = 0,
        DPS = 0,
    }
    
    for i, heroInstanceId in ipairs(team) do
        local hero = data.Heroes.Owned[heroInstanceId]
        if hero then
            local heroConfig = HeroConfig.GetHero(hero.HeroId)
            local stats = HeroConfig.CalculateStatsAtLevel(hero.HeroId, hero.Level or 1)
            
            if heroConfig and stats then
                -- Raritäts-Multiplikator
                local rarityData = HeroConfig.Rarities[hero.Rarity or "Common"]
                local rarityMult = rarityData and rarityData.StatMultiplier or 1.0
                
                local heroHealth = math.floor(stats.Health * rarityMult)
                local heroDamage = math.floor(stats.Damage * rarityMult)
                local heroDPS = heroDamage / stats.AttackCooldown
                
                heroes[i] = {
                    InstanceId = heroInstanceId,
                    HeroId = hero.HeroId,
                    Name = heroConfig.Name,
                    Class = heroConfig.Class,
                    Level = hero.Level,
                    Rarity = hero.Rarity,
                    Stats = {
                        Health = heroHealth,
                        Damage = heroDamage,
                        DPS = heroDPS,
                        Speed = stats.Speed,
                    },
                    XPToNextLevel = HeroConfig.CalculateXPForLevel(hero.Level or 1),
                    CurrentXP = hero.Experience or 0,
                }
                
                totalStats.Health = totalStats.Health + heroHealth
                totalStats.Damage = totalStats.Damage + heroDamage
                totalStats.DPS = totalStats.DPS + heroDPS
                
                table.insert(heroBaseIds, hero.HeroId)
            end
        end
    end
    
    local synergies = HeroConfig.GetActivesynergies(heroBaseIds)
    
    return {
        Heroes = heroes,
        Synergies = synergies,
        TotalStats = totalStats,
        TeamSize = #team,
        MaxTeamSize = GameConfig.Heroes.MaxPartySize,
    }
end

--[[
    Gibt freigeschaltete Helden-Typen zurück
    @param player: Der Spieler
    @return: { [heroId] = true }
]]
function HeroSystem.GetUnlockedHeroes(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return nil end
    
    return data.Heroes.Unlocked
end

--[[
    Gibt die Anzahl der Helden im Besitz zurück
    @param player: Der Spieler
    @return: count, maxCount
]]
function HeroSystem.GetHeroCount(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return 0, CONFIG.MaxOwnedHeroes end
    
    local count = 0
    for _ in pairs(data.Heroes.Owned) do
        count = count + 1
    end
    
    return count, CONFIG.MaxOwnedHeroes
end

--[[
    Berechnet Rekrutierungskosten für einen Helden
    @param player: Der Spieler
    @param heroId: ID des Helden-Typs
    @return: cost oder nil
]]
function HeroSystem.GetRecruitCost(player, heroId)
    local heroConfig = HeroConfig.GetHero(heroId)
    if not heroConfig then return nil end
    
    local cost = {
        Gold = heroConfig.RecruitCost,
        Gems = heroConfig.RecruitGems,
    }
    
    return CurrencyService.CalculateCostWithDiscount(player, cost)
end

--[[
    Gibt Helden gefiltert zurück
    @param player: Der Spieler
    @param filter: { Class = "Tank", Rarity = "Epic", MinLevel = 5 }
    @return: Array von Helden
]]
function HeroSystem.GetFilteredHeroes(player, filter)
    local data = DataManager and DataManager.GetData(player)
    if not data then return {} end
    
    local result = {}
    
    for instanceId, hero in pairs(data.Heroes.Owned) do
        local heroConfig = HeroConfig.GetHero(hero.HeroId)
        if heroConfig then
            local matches = true
            
            if filter.Class and heroConfig.Class ~= filter.Class then
                matches = false
            end
            
            if filter.Rarity and hero.Rarity ~= filter.Rarity then
                matches = false
            end
            
            if filter.MinLevel and (hero.Level or 1) < filter.MinLevel then
                matches = false
            end
            
            if filter.MaxLevel and (hero.Level or 1) > filter.MaxLevel then
                matches = false
            end
            
            if filter.HeroId and hero.HeroId ~= filter.HeroId then
                matches = false
            end
            
            if matches then
                table.insert(result, {
                    InstanceId = instanceId,
                    Hero = hero,
                    Config = heroConfig,
                })
            end
        end
    end
    
    -- Sortieren nach Level (absteigend)
    table.sort(result, function(a, b)
        return (a.Hero.Level or 1) > (b.Hero.Level or 1)
    end)
    
    return result
end

return HeroSystem
