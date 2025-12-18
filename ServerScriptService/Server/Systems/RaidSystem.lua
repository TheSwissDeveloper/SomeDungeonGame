--[[
    RaidSystem.lua
    Zentrales System für Raid-Operationen
    Pfad: ServerScriptService/Server/Systems/RaidSystem
    
    Verantwortlich für:
    - Raid-Matchmaking (Ziel finden)
    - Raid-Ablauf und Kampfsimulation
    - Belohnungsberechnung
    - Defense-Benachrichtigungen
    
    WICHTIG: Raids sind asynchron und tick-basiert!
]]

local Players = game:GetService("Players")
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
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Service/Manager-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil
local CurrencyService = nil
local DungeonSystem = nil

local RaidSystem = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Matchmaking
    LevelRangeMin = 5,              -- Mindest-Level-Differenz nach unten
    LevelRangeMax = 10,             -- Max-Level-Differenz nach oben
    MaxMatchmakingAttempts = 10,    -- Versuche ein Ziel zu finden
    
    -- Combat
    CombatTickRate = GameConfig.Timing.CombatTickRate,  -- 0.5 Sekunden
    RaidTimeLimit = GameConfig.Raids.RaidTimeLimit,     -- 120 Sekunden
    
    -- XP-Belohnungen
    XPPerRoomCleared = 30,
    XPPerMonsterKilled = 15,
    XPPerTrapSurvived = 5,
    
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- AKTIVE RAIDS
-------------------------------------------------
local activeRaids = {}  -- { [playerId] = RaidState }

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
RaidSystem.Signals = {
    RaidStarted = SignalUtil.new(),         -- (attacker, targetData)
    RaidEnded = SignalUtil.new(),           -- (attacker, result)
    RaidTick = SignalUtil.new(),            -- (attacker, raidState)
    
    HeroDefeated = SignalUtil.new(),        -- (attacker, heroInstanceId)
    MonsterDefeated = SignalUtil.new(),     -- (attacker, roomIndex, slotIndex)
    TrapTriggered = SignalUtil.new(),       -- (attacker, roomIndex, slotIndex)
    RoomCleared = SignalUtil.new(),         -- (attacker, roomIndex)
    
    DefenseTriggered = SignalUtil.new(),    -- (defender, attackerName)
    DefenseResult = SignalUtil.new(),       -- (defender, result)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[RaidSystem]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[RaidSystem]", ...)
end

--[[
    Generiert eine einzigartige Raid-ID
    @return: Raid-ID String
]]
local function generateRaidId()
    return "raid_" .. os.time() .. "_" .. math.random(100000, 999999)
end

--[[
    Berechnet Held-Stats für den Kampf
    @param heroData: Helden-Instanz Daten
    @return: Combat-Stats
]]
local function calculateHeroCombatStats(heroData)
    local heroConfig = HeroConfig.GetHero(heroData.HeroId)
    if not heroConfig then return nil end
    
    local baseStats = HeroConfig.CalculateStatsAtLevel(heroData.HeroId, heroData.Level or 1)
    if not baseStats then return nil end
    
    -- Raritäts-Bonus anwenden
    local rarityData = HeroConfig.Rarities[heroData.Rarity or "Common"]
    local rarityMultiplier = rarityData and rarityData.StatMultiplier or 1.0
    
    return {
        HeroId = heroData.HeroId,
        Name = heroConfig.Name,
        MaxHealth = math.floor(baseStats.Health * rarityMultiplier),
        CurrentHealth = math.floor(baseStats.Health * rarityMultiplier),
        Damage = math.floor(baseStats.Damage * rarityMultiplier),
        Speed = baseStats.Speed,
        AttackRange = baseStats.AttackRange,
        AttackCooldown = baseStats.AttackCooldown,
        AttackTimer = 0,
        Abilities = baseStats.Abilities or {},
        AbilityCooldowns = {},
        Status = {},  -- Buffs/Debuffs
        IsAlive = true,
    }
end

--[[
    Berechnet Monster-Stats für den Kampf
    @param monsterData: Monster-Platzierung Daten
    @param roomBonuses: Raum-Boni
    @return: Combat-Stats
]]
local function calculateMonsterCombatStats(monsterData, roomBonuses)
    local monsterConfig = MonsterConfig.GetMonster(monsterData.MonsterId)
    if not monsterConfig then return nil end
    
    local baseStats = MonsterConfig.CalculateStatsAtLevel(monsterData.MonsterId, monsterData.Level or 1)
    if not baseStats then return nil end
    
    -- Raum-Boni anwenden
    local healthBonus = 1.0
    local damageBonus = 1.0
    
    for _, bonus in ipairs(roomBonuses or {}) do
        if bonus.Type == "MonsterHealth" then
            healthBonus = healthBonus + (bonus.Value or 0)
        elseif bonus.Type == "MonsterDamage" then
            damageBonus = damageBonus + (bonus.Value or 0)
        elseif bonus.Type == "MonsterBuff" then
            -- Spezifische Monster-Buffs
            if bonus.MonsterIds then
                for _, buffedId in ipairs(bonus.MonsterIds) do
                    if buffedId == monsterData.MonsterId then
                        healthBonus = healthBonus + (bonus.StatBonus or 0)
                        damageBonus = damageBonus + (bonus.StatBonus or 0)
                        break
                    end
                end
            end
        end
    end
    
    return {
        MonsterId = monsterData.MonsterId,
        Name = monsterConfig.Name,
        MaxHealth = math.floor(baseStats.Health * healthBonus),
        CurrentHealth = math.floor(baseStats.Health * healthBonus),
        Damage = math.floor(baseStats.Damage * damageBonus),
        Speed = baseStats.Speed,
        Armor = baseStats.Armor or 0,
        AttackRange = baseStats.AttackRange,
        AttackCooldown = baseStats.AttackCooldown,
        AttackTimer = 0,
        Behavior = monsterConfig.Behavior,
        Abilities = baseStats.Abilities or {},
        AbilityCooldowns = {},
        Status = {},
        IsAlive = true,
    }
end

--[[
    Berechnet Fallen-Stats für den Kampf
    @param trapData: Fallen-Platzierung Daten
    @param roomBonuses: Raum-Boni
    @return: Combat-Stats
]]
local function calculateTrapCombatStats(trapData, roomBonuses)
    local trapConfig = TrapConfig.GetTrap(trapData.TrapId)
    if not trapConfig then return nil end
    
    local baseStats = TrapConfig.CalculateStatsAtLevel(trapData.TrapId, trapData.Level or 1)
    if not baseStats then return nil end
    
    -- Raum-Boni anwenden
    local damageBonus = 1.0
    local cooldownBonus = 1.0
    
    for _, bonus in ipairs(roomBonuses or {}) do
        if bonus.Type == "TrapDamage" then
            if bonus.TrapCategory == "All" or bonus.TrapCategory == trapConfig.Category then
                damageBonus = damageBonus + (bonus.Value or 0)
            end
        elseif bonus.Type == "TrapCooldown" then
            cooldownBonus = cooldownBonus + (bonus.Value or 0)
        end
    end
    
    return {
        TrapId = trapData.TrapId,
        Name = trapConfig.Name,
        Damage = math.floor(baseStats.Damage * damageBonus),
        Cooldown = baseStats.Cooldown * math.max(0.5, cooldownBonus),
        Range = baseStats.Range,
        Effects = baseStats.Effects or {},
        CooldownTimer = 0,
        IsActive = true,
    }
end

--[[
    Erstellt den initialen Raid-State
    @param attacker: Angreifender Spieler
    @param targetData: Dungeon-Daten des Ziels
    @param targetPlayer: Ziel-Spieler (kann nil sein für Offline)
    @return: RaidState
]]
local function createRaidState(attacker, targetData, targetPlayer)
    local attackerData = DataManager.GetData(attacker)
    if not attackerData then return nil end
    
    local raidId = generateRaidId()
    
    -- Helden-Team erstellen
    local heroes = {}
    for i, heroInstanceId in ipairs(attackerData.Heroes.Team or {}) do
        local heroData = attackerData.Heroes.Owned[heroInstanceId]
        if heroData then
            local combatStats = calculateHeroCombatStats(heroData)
            if combatStats then
                combatStats.InstanceId = heroInstanceId
                combatStats.Position = i
                heroes[heroInstanceId] = combatStats
            end
        end
    end
    
    -- Räume mit Combat-Stats erstellen
    local rooms = {}
    for roomIndex, room in ipairs(targetData.Dungeon.Rooms) do
        local roomConfig = RoomConfig.GetRoom(room.RoomId)
        local roomBonuses = roomConfig and RoomConfig.CalculateBonusesAtLevel(room.RoomId, room.Level or 1) or {}
        
        local roomState = {
            RoomId = room.RoomId,
            Level = room.Level or 1,
            Bonuses = roomBonuses,
            Traps = {},
            Monsters = {},
            IsCleared = false,
            EnvironmentDamage = 0,
        }
        
        -- Environment Damage aus Raum-Boni
        for _, bonus in ipairs(roomBonuses) do
            if bonus.Type == "EnvironmentDamage" then
                roomState.EnvironmentDamage = bonus.DamagePerSecond or 0
            end
        end
        
        -- Fallen erstellen
        for slotIndex, trap in pairs(room.Traps or {}) do
            local trapStats = calculateTrapCombatStats(trap, roomBonuses)
            if trapStats then
                trapStats.SlotIndex = slotIndex
                roomState.Traps[slotIndex] = trapStats
            end
        end
        
        -- Monster erstellen
        for slotIndex, monster in pairs(room.Monsters or {}) do
            local monsterStats = calculateMonsterCombatStats(monster, roomBonuses)
            if monsterStats then
                monsterStats.SlotIndex = slotIndex
                roomState.Monsters[slotIndex] = monsterStats
            end
        end
        
        rooms[roomIndex] = roomState
    end
    
    -- Team-Synergien berechnen
    local teamHeroIds = {}
    for _, heroInstanceId in ipairs(attackerData.Heroes.Team or {}) do
        local heroData = attackerData.Heroes.Owned[heroInstanceId]
        if heroData then
            table.insert(teamHeroIds, heroData.HeroId)
        end
    end
    local synergies = HeroConfig.GetActivesynergies(teamHeroIds)
    
    -- Synergy-Boni anwenden
    for _, synergy in ipairs(synergies) do
        for heroId, hero in pairs(heroes) do
            if synergy.Bonus.AllStats then
                hero.MaxHealth = math.floor(hero.MaxHealth * (1 + synergy.Bonus.AllStats))
                hero.CurrentHealth = hero.MaxHealth
                hero.Damage = math.floor(hero.Damage * (1 + synergy.Bonus.AllStats))
            end
            if synergy.Bonus.Health then
                hero.MaxHealth = math.floor(hero.MaxHealth * (1 + synergy.Bonus.Health))
                hero.CurrentHealth = hero.MaxHealth
            end
            if synergy.Bonus.Damage then
                hero.Damage = math.floor(hero.Damage * (1 + synergy.Bonus.Damage))
            end
        end
    end
    
    return {
        RaidId = raidId,
        AttackerId = attacker.UserId,
        AttackerName = attacker.Name,
        TargetId = targetData.UserId or 0,
        TargetName = targetData.Dungeon.Name or "Unbekannt",
        TargetLevel = targetData.Dungeon.Level or 1,
        TargetPlayer = targetPlayer,
        
        Heroes = heroes,
        Rooms = rooms,
        Synergies = synergies,
        
        CurrentRoom = 1,
        TotalRooms = #rooms,
        
        TimeElapsed = 0,
        TimeLimit = CONFIG.RaidTimeLimit,
        
        -- Statistiken
        Stats = {
            DamageDealt = 0,
            DamageTaken = 0,
            MonstersKilled = 0,
            TrapsTriggered = 0,
            RoomsCleared = 0,
            HeroesLost = 0,
        },
        
        -- Status
        Status = "InProgress",  -- InProgress, Victory, Defeat, Timeout
        StartTime = os.time(),
        EndTime = nil,
    }
end

--[[
    Führt einen Combat-Tick durch
    @param raidState: Aktueller Raid-State
    @param deltaTime: Zeit seit letztem Tick
    @return: Updated RaidState
]]
local function processCombatTick(raidState, deltaTime)
    if raidState.Status ~= "InProgress" then
        return raidState
    end
    
    -- Zeit aktualisieren
    raidState.TimeElapsed = raidState.TimeElapsed + deltaTime
    
    -- Timeout prüfen
    if raidState.TimeElapsed >= raidState.TimeLimit then
        raidState.Status = "Timeout"
        return raidState
    end
    
    -- Prüfen ob noch Helden leben
    local aliveHeroes = 0
    for _, hero in pairs(raidState.Heroes) do
        if hero.IsAlive then
            aliveHeroes = aliveHeroes + 1
        end
    end
    
    if aliveHeroes == 0 then
        raidState.Status = "Defeat"
        return raidState
    end
    
    -- Aktuellen Raum holen
    local currentRoom = raidState.Rooms[raidState.CurrentRoom]
    if not currentRoom then
        raidState.Status = "Victory"
        return raidState
    end
    
    -- Environment Damage anwenden
    if currentRoom.EnvironmentDamage > 0 then
        local envDamage = currentRoom.EnvironmentDamage * deltaTime
        for _, hero in pairs(raidState.Heroes) do
            if hero.IsAlive then
                hero.CurrentHealth = hero.CurrentHealth - envDamage
                raidState.Stats.DamageTaken = raidState.Stats.DamageTaken + envDamage
                
                if hero.CurrentHealth <= 0 then
                    hero.CurrentHealth = 0
                    hero.IsAlive = false
                    raidState.Stats.HeroesLost = raidState.Stats.HeroesLost + 1
                end
            end
        end
    end
    
    -- Fallen verarbeiten
    for slotIndex, trap in pairs(currentRoom.Traps) do
        if trap.IsActive then
            trap.CooldownTimer = trap.CooldownTimer + deltaTime
            
            if trap.CooldownTimer >= trap.Cooldown then
                trap.CooldownTimer = 0
                raidState.Stats.TrapsTriggered = raidState.Stats.TrapsTriggered + 1
                
                -- Schaden an zufälligen lebenden Helden
                local targetHero = nil
                local livingHeroes = {}
                for _, hero in pairs(raidState.Heroes) do
                    if hero.IsAlive then
                        table.insert(livingHeroes, hero)
                    end
                end
                
                if #livingHeroes > 0 then
                    targetHero = livingHeroes[math.random(1, #livingHeroes)]
                    
                    local damage = trap.Damage
                    targetHero.CurrentHealth = targetHero.CurrentHealth - damage
                    raidState.Stats.DamageTaken = raidState.Stats.DamageTaken + damage
                    
                    -- Effekte anwenden
                    for _, effect in ipairs(trap.Effects or {}) do
                        if effect.Type == "Stun" then
                            targetHero.Status.Stunned = effect.Duration
                        elseif effect.Type == "Slow" then
                            targetHero.Status.Slowed = { Duration = effect.Duration, Percent = effect.Percentage }
                        elseif effect.Type == "Poison" then
                            targetHero.Status.Poisoned = { Duration = effect.Duration, DPS = effect.DamagePerSecond }
                        elseif effect.Type == "Burn" then
                            targetHero.Status.Burning = { Duration = effect.Duration, DPS = effect.DamagePerSecond }
                        end
                    end
                    
                    if targetHero.CurrentHealth <= 0 then
                        targetHero.CurrentHealth = 0
                        targetHero.IsAlive = false
                        raidState.Stats.HeroesLost = raidState.Stats.HeroesLost + 1
                    end
                end
            end
        end
    end
    
    -- Monster verarbeiten
    local aliveMonsters = 0
    for slotIndex, monster in pairs(currentRoom.Monsters) do
        if monster.IsAlive then
            aliveMonsters = aliveMonsters + 1
            
            monster.AttackTimer = monster.AttackTimer + deltaTime
            
            if monster.AttackTimer >= monster.AttackCooldown then
                monster.AttackTimer = 0
                
                -- Ziel finden (niedrigstes HP oder zufällig)
                local targetHero = nil
                local lowestHP = math.huge
                
                for _, hero in pairs(raidState.Heroes) do
                    if hero.IsAlive and hero.CurrentHealth < lowestHP then
                        lowestHP = hero.CurrentHealth
                        targetHero = hero
                    end
                end
                
                if targetHero then
                    local damage = monster.Damage
                    targetHero.CurrentHealth = targetHero.CurrentHealth - damage
                    raidState.Stats.DamageTaken = raidState.Stats.DamageTaken + damage
                    
                    if targetHero.CurrentHealth <= 0 then
                        targetHero.CurrentHealth = 0
                        targetHero.IsAlive = false
                        raidState.Stats.HeroesLost = raidState.Stats.HeroesLost + 1
                    end
                end
            end
        end
    end
    
    -- Helden angreifen lassen
    for _, hero in pairs(raidState.Heroes) do
        if hero.IsAlive then
            -- Status-Effekte verarbeiten
            if hero.Status.Stunned and hero.Status.Stunned > 0 then
                hero.Status.Stunned = hero.Status.Stunned - deltaTime
                if hero.Status.Stunned <= 0 then
                    hero.Status.Stunned = nil
                end
            else
                hero.AttackTimer = hero.AttackTimer + deltaTime
                
                if hero.AttackTimer >= hero.AttackCooldown then
                    hero.AttackTimer = 0
                    
                    -- Ziel finden (erstes lebendes Monster)
                    local targetMonster = nil
                    for _, monster in pairs(currentRoom.Monsters) do
                        if monster.IsAlive then
                            targetMonster = monster
                            break
                        end
                    end
                    
                    if targetMonster then
                        local damage = hero.Damage
                        
                        -- Rüstung anwenden
                        local armor = targetMonster.Armor or 0
                        local damageReduction = armor / (armor + 100)
                        damage = damage * (1 - damageReduction)
                        
                        targetMonster.CurrentHealth = targetMonster.CurrentHealth - damage
                        raidState.Stats.DamageDealt = raidState.Stats.DamageDealt + damage
                        
                        if targetMonster.CurrentHealth <= 0 then
                            targetMonster.CurrentHealth = 0
                            targetMonster.IsAlive = false
                            raidState.Stats.MonstersKilled = raidState.Stats.MonstersKilled + 1
                        end
                    end
                end
            end
            
            -- DoT-Effekte (Poison, Burn)
            if hero.Status.Poisoned then
                local poisonDamage = hero.Status.Poisoned.DPS * deltaTime
                hero.CurrentHealth = hero.CurrentHealth - poisonDamage
                hero.Status.Poisoned.Duration = hero.Status.Poisoned.Duration - deltaTime
                
                if hero.Status.Poisoned.Duration <= 0 then
                    hero.Status.Poisoned = nil
                end
                
                if hero.CurrentHealth <= 0 then
                    hero.CurrentHealth = 0
                    hero.IsAlive = false
                    raidState.Stats.HeroesLost = raidState.Stats.HeroesLost + 1
                end
            end
            
            if hero.Status.Burning then
                local burnDamage = hero.Status.Burning.DPS * deltaTime
                hero.CurrentHealth = hero.CurrentHealth - burnDamage
                hero.Status.Burning.Duration = hero.Status.Burning.Duration - deltaTime
                
                if hero.Status.Burning.Duration <= 0 then
                    hero.Status.Burning = nil
                end
                
                if hero.CurrentHealth <= 0 then
                    hero.CurrentHealth = 0
                    hero.IsAlive = false
                    raidState.Stats.HeroesLost = raidState.Stats.HeroesLost + 1
                end
            end
        end
    end
    
    -- Prüfen ob Raum cleared
    local monstersAlive = 0
    for _, monster in pairs(currentRoom.Monsters) do
        if monster.IsAlive then
            monstersAlive = monstersAlive + 1
        end
    end
    
    if monstersAlive == 0 and not currentRoom.IsCleared then
        currentRoom.IsCleared = true
        raidState.Stats.RoomsCleared = raidState.Stats.RoomsCleared + 1
        
        -- Nächster Raum
        raidState.CurrentRoom = raidState.CurrentRoom + 1
        
        if raidState.CurrentRoom > raidState.TotalRooms then
            raidState.Status = "Victory"
        end
    end
    
    return raidState
end

--[[
    Berechnet Raid-Belohnungen
    @param raidState: Finaler Raid-State
    @param attackerData: Daten des Angreifers
    @return: rewards { Gold, Gems, XP }
]]
local function calculateRaidRewards(raidState, attackerData)
    local progressPercent = raidState.Stats.RoomsCleared / raidState.TotalRooms
    local prestigeLevel = attackerData.Prestige and attackerData.Prestige.Level or 0
    
    local baseReward = CurrencyUtil.CalculateRaidReward(
        raidState.TargetLevel,
        progressPercent,
        prestigeLevel
    )
    
    -- Bonus für Sieg
    if raidState.Status == "Victory" then
        baseReward.Gold = math.floor(baseReward.Gold * 1.5)
        baseReward.Gems = math.floor(baseReward.Gems * 1.5)
    end
    
    -- XP berechnen
    local xp = 0
    xp = xp + (raidState.Stats.RoomsCleared * CONFIG.XPPerRoomCleared)
    xp = xp + (raidState.Stats.MonstersKilled * CONFIG.XPPerMonsterKilled)
    xp = xp + (raidState.Stats.TrapsTriggered * CONFIG.XPPerTrapSurvived)
    
    return {
        Gold = baseReward.Gold,
        Gems = baseReward.Gems,
        XP = xp,
    }
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert das RaidSystem
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
    @param currencyServiceRef: Referenz zum CurrencyService
    @param dungeonSystemRef: Referenz zum DungeonSystem
]]
function RaidSystem.Initialize(dataManagerRef, playerManagerRef, currencyServiceRef, dungeonSystemRef)
    debugPrint("Initialisiere RaidSystem...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    CurrencyService = currencyServiceRef
    DungeonSystem = dungeonSystemRef
    
    debugPrint("RaidSystem initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - MATCHMAKING
-------------------------------------------------

--[[
    Findet ein passendes Raid-Ziel
    @param player: Der suchende Spieler
    @return: success, targetData oder errorMessage
]]
function RaidSystem.FindTarget(player)
    local attackerData = DataManager and DataManager.GetData(player)
    if not attackerData then
        return false, "Daten nicht geladen"
    end
    
    local attackerLevel = attackerData.Dungeon.Level or 1
    
    -- Mindest-Level prüfen
    if attackerLevel < GameConfig.Raids.MinDungeonLevelToRaid then
        return false, "Dungeon-Level " .. GameConfig.Raids.MinDungeonLevelToRaid .. " benötigt"
    end
    
    -- Team prüfen
    if not attackerData.Heroes.Team or #attackerData.Heroes.Team == 0 then
        return false, "Kein Helden-Team ausgewählt"
    end
    
    -- Online-Spieler durchsuchen
    local candidates = {}
    
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer.UserId ~= player.UserId then
            local otherData = DataManager.GetData(otherPlayer)
            if otherData then
                local otherLevel = otherData.Dungeon.Level or 1
                local levelDiff = otherLevel - attackerLevel
                
                if levelDiff >= -CONFIG.LevelRangeMin and levelDiff <= CONFIG.LevelRangeMax then
                    table.insert(candidates, {
                        Player = otherPlayer,
                        Data = otherData,
                        Level = otherLevel,
                        LevelDiff = math.abs(levelDiff),
                    })
                end
            end
        end
    end
    
    -- Falls keine Online-Kandidaten, NPC-Dungeon generieren
    if #candidates == 0 then
        debugPrint("Keine Online-Ziele, generiere NPC-Dungeon")
        
        -- Einfachen NPC-Dungeon erstellen
        local npcData = {
            UserId = 0,
            Dungeon = {
                Name = "Verlassener Dungeon",
                Level = math.max(1, attackerLevel - 2),
                Rooms = {},
            },
        }
        
        -- 3-5 Räume generieren
        local roomCount = math.random(3, 5)
        for i = 1, roomCount do
            local room = {
                RoomId = "stone_corridor",
                Level = 1,
                Traps = {},
                Monsters = {},
            }
            
            -- 1-2 Fallen pro Raum
            local trapCount = math.random(1, 2)
            for j = 1, trapCount do
                room.Traps[j] = {
                    TrapId = "spike_floor",
                    Level = math.max(1, math.floor(attackerLevel / 3)),
                }
            end
            
            -- 1-2 Monster pro Raum
            local monsterCount = math.random(1, 2)
            for j = 1, monsterCount do
                room.Monsters[j] = {
                    MonsterId = "skeleton",
                    Level = math.max(1, math.floor(attackerLevel / 2)),
                }
            end
            
            npcData.Dungeon.Rooms[i] = room
        end
        
        return true, {
            IsNPC = true,
            TargetPlayer = nil,
            TargetData = npcData,
        }
    end
    
    -- Zufälligen Kandidaten wählen (bevorzugt ähnliches Level)
    table.sort(candidates, function(a, b)
        return a.LevelDiff < b.LevelDiff
    end)
    
    local selectedIndex = math.random(1, math.min(3, #candidates))
    local selected = candidates[selectedIndex]
    
    return true, {
        IsNPC = false,
        TargetPlayer = selected.Player,
        TargetData = {
            UserId = selected.Player.UserId,
            Dungeon = selected.Data.Dungeon,
        },
    }
end

-------------------------------------------------
-- PUBLIC API - RAID-STEUERUNG
-------------------------------------------------

--[[
    Startet einen Raid
    @param player: Der Angreifer
    @param targetInfo: Ziel-Info von FindTarget
    @return: success, raidState oder errorMessage
]]
function RaidSystem.StartRaid(player, targetInfo)
    local attackerData = DataManager and DataManager.GetData(player)
    if not attackerData then
        return false, "Daten nicht geladen"
    end
    
    -- Bereits in einem Raid?
    if activeRaids[player.UserId] then
        return false, "Bereits in einem Raid"
    end
    
    -- Cooldown prüfen
    local currentTime = os.time()
    local lastRaidTime = attackerData.Cooldowns.LastRaidTime or 0
    local cooldownRemaining = (lastRaidTime + GameConfig.Raids.RaidCooldown) - currentTime
    
    if cooldownRemaining > 0 and not GameConfig.Debug.InstantCooldowns then
        return false, "Raid-Cooldown: Noch " .. math.ceil(cooldownRemaining / 60) .. " Minuten"
    end
    
    -- Raid-State erstellen
    local raidState = createRaidState(player, targetInfo.TargetData, targetInfo.TargetPlayer)
    if not raidState then
        return false, "Fehler beim Erstellen des Raids"
    end
    
    -- Aktiven Raid speichern
    activeRaids[player.UserId] = raidState
    
    -- Cooldown setzen
    DataManager.SetValue(player, "Cooldowns.LastRaidTime", currentTime)
    
    -- Stats aktualisieren
    DataManager.IncrementValue(player, "Stats.RaidsCompleted", 1)
    
    -- Defender benachrichtigen
    if targetInfo.TargetPlayer then
        RemoteIndex.FireClient("Defense_Notification", targetInfo.TargetPlayer, {
            AttackerName = player.Name,
            AttackerLevel = attackerData.Dungeon.Level,
        })
        
        RaidSystem.Signals.DefenseTriggered:Fire(targetInfo.TargetPlayer, player.Name)
    end
    
    -- Signal feuern
    RaidSystem.Signals.RaidStarted:Fire(player, targetInfo)
    
    -- Client updaten
    RemoteIndex.FireClient("Raid_Update", player, {
        Status = "Started",
        RaidId = raidState.RaidId,
        TargetName = raidState.TargetName,
        TargetLevel = raidState.TargetLevel,
        TotalRooms = raidState.TotalRooms,
        TimeLimit = raidState.TimeLimit,
        Heroes = raidState.Heroes,
        Synergies = raidState.Synergies,
    })
    
    debugPrint(player.Name .. " startet Raid gegen " .. raidState.TargetName)
    
    -- Raid-Loop starten
    task.spawn(function()
        RaidSystem._runRaidLoop(player)
    end)
    
    return true, raidState
end

--[[
    Raid-Loop (intern)
    @param player: Der Angreifer
]]
function RaidSystem._runRaidLoop(player)
    local raidState = activeRaids[player.UserId]
    if not raidState then return end
    
    local lastTick = os.clock()
    
    while raidState and raidState.Status == "InProgress" do
        task.wait(CONFIG.CombatTickRate)
        
        -- Prüfen ob Spieler noch da ist
        if not player or not player.Parent then
            raidState.Status = "Defeat"
            break
        end
        
        -- Prüfen ob Raid noch aktiv
        raidState = activeRaids[player.UserId]
        if not raidState then break end
        
        -- Delta berechnen
        local currentTick = os.clock()
        local deltaTime = currentTick - lastTick
        lastTick = currentTick
        
        -- Combat-Tick verarbeiten
        raidState = processCombatTick(raidState, deltaTime)
        activeRaids[player.UserId] = raidState
        
        -- Client updaten
        RemoteIndex.FireClient("Raid_CombatTick", player, {
            TimeElapsed = raidState.TimeElapsed,
            CurrentRoom = raidState.CurrentRoom,
            Heroes = raidState.Heroes,
            CurrentRoomState = raidState.Rooms[raidState.CurrentRoom],
            Stats = raidState.Stats,
        })
        
        -- Signal feuern
        RaidSystem.Signals.RaidTick:Fire(player, raidState)
    end
    
    -- Raid beenden
    if raidState then
        RaidSystem._endRaid(player, raidState)
    end
end

--[[
    Beendet einen Raid (intern)
    @param player: Der Angreifer
    @param raidState: Finaler Raid-State
]]
function RaidSystem._endRaid(player, raidState)
    raidState.EndTime = os.time()
    
    local attackerData = DataManager.GetData(player)
    if not attackerData then return end
    
    -- Belohnungen berechnen
    local rewards = calculateRaidRewards(raidState, attackerData)
    
    -- Belohnungen geben
    if rewards.Gold > 0 or rewards.Gems > 0 then
        CurrencyService.GiveReward(
            player,
            { Gold = rewards.Gold, Gems = rewards.Gems },
            CurrencyService.TransactionType.RaidReward,
            "Raid:" .. raidState.RaidId
        )
    end
    
    -- Stats aktualisieren
    if raidState.Status == "Victory" then
        DataManager.IncrementValue(player, "Stats.RaidsSuccessful", 1)
    else
        DataManager.IncrementValue(player, "Stats.RaidsFailed", 1)
    end
    
    DataManager.IncrementValue(player, "Stats.TotalRaidDamageDealt", math.floor(raidState.Stats.DamageDealt))
    DataManager.IncrementValue(player, "Stats.MonstersKilled", raidState.Stats.MonstersKilled)
    
    -- Defender Stats aktualisieren
    if raidState.TargetPlayer and raidState.TargetPlayer.Parent then
        local defenderData = DataManager.GetData(raidState.TargetPlayer)
        if defenderData then
            DataManager.IncrementValue(raidState.TargetPlayer, "Stats.TimesRaided", 1)
            
            if raidState.Status == "Victory" then
                DataManager.IncrementValue(raidState.TargetPlayer, "Stats.FailedDefenses", 1)
            else
                DataManager.IncrementValue(raidState.TargetPlayer, "Stats.SuccessfulDefenses", 1)
            end
            
            DataManager.IncrementValue(raidState.TargetPlayer, "Stats.TotalDefenseDamageDealt", 
                math.floor(raidState.Stats.DamageTaken))
            DataManager.IncrementValue(raidState.TargetPlayer, "Stats.HeroesKilled", 
                raidState.Stats.HeroesLost)
            
            -- Defense-Belohnung
            local defenseReward = CurrencyUtil.CalculateDefenseReward(
                raidState.Stats.HeroesLost,
                defenderData.Dungeon.Level or 1
            )
            
            if defenseReward.Gold > 0 or defenseReward.Gems > 0 then
                CurrencyService.GiveReward(
                    raidState.TargetPlayer,
                    defenseReward,
                    CurrencyService.TransactionType.DefenseReward,
                    "Defense:" .. raidState.RaidId
                )
            end
            
            -- Defender benachrichtigen
            RemoteIndex.FireClient("Defense_Result", raidState.TargetPlayer, {
                AttackerName = raidState.AttackerName,
                AttackerWon = raidState.Status == "Victory",
                RoomsCleared = raidState.Stats.RoomsCleared,
                HeroesKilled = raidState.Stats.HeroesLost,
                Reward = defenseReward,
            })
            
            RaidSystem.Signals.DefenseResult:Fire(raidState.TargetPlayer, {
                AttackerWon = raidState.Status == "Victory",
            })
        end
    end
    
    -- Raid aus aktiven Raids entfernen
    activeRaids[player.UserId] = nil
    
    -- Client benachrichtigen
    RemoteIndex.FireClient("Raid_End", player, {
        Status = raidState.Status,
        Stats = raidState.Stats,
        Rewards = rewards,
        TimeElapsed = raidState.TimeElapsed,
    })
    
    -- Signal feuern
    RaidSystem.Signals.RaidEnded:Fire(player, {
        Status = raidState.Status,
        Stats = raidState.Stats,
        Rewards = rewards,
    })
    
    -- Benachrichtigung
    if PlayerManager then
        local title = raidState.Status == "Victory" and "Raid erfolgreich!" or "Raid gescheitert"
        local message = string.format(
            "%d/%d Räume, %d Gold, %d Gems",
            raidState.Stats.RoomsCleared,
            raidState.TotalRooms,
            rewards.Gold,
            rewards.Gems
        )
        
        PlayerManager.SendNotification(player, title, message, 
            raidState.Status == "Victory" and "Success" or "Warning")
    end
    
    debugPrint(player.Name .. " Raid beendet: " .. raidState.Status)
end

--[[
    Bricht einen laufenden Raid ab
    @param player: Der Angreifer
    @return: success, errorMessage
]]
function RaidSystem.CancelRaid(player)
    local raidState = activeRaids[player.UserId]
    if not raidState then
        return false, "Kein aktiver Raid"
    end
    
    raidState.Status = "Defeat"
    
    return true, nil
end

-------------------------------------------------
-- PUBLIC API - ABFRAGEN
-------------------------------------------------

--[[
    Gibt den aktiven Raid eines Spielers zurück
    @param player: Der Spieler
    @return: RaidState oder nil
]]
function RaidSystem.GetActiveRaid(player)
    return activeRaids[player.UserId]
end

--[[
    Prüft ob ein Spieler in einem Raid ist
    @param player: Der Spieler
    @return: boolean
]]
function RaidSystem.IsInRaid(player)
    return activeRaids[player.UserId] ~= nil
end

--[[
    Gibt alle aktiven Raids zurück
    @return: Table mit Raids
]]
function RaidSystem.GetAllActiveRaids()
    return activeRaids
end

--[[
    Prüft ob ein Spieler raiden kann
    @param player: Der Spieler
    @return: canRaid, reason
]]
function RaidSystem.CanRaid(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    -- Bereits in Raid?
    if activeRaids[player.UserId] then
        return false, "Bereits in einem Raid"
    end
    
    -- Level prüfen
    if data.Dungeon.Level < GameConfig.Raids.MinDungeonLevelToRaid then
        return false, "Dungeon-Level " .. GameConfig.Raids.MinDungeonLevelToRaid .. " benötigt"
    end
    
    -- Team prüfen
    if not data.Heroes.Team or #data.Heroes.Team == 0 then
        return false, "Kein Helden-Team ausgewählt"
    end
    
    -- Cooldown prüfen
    local currentTime = os.time()
    local lastRaidTime = data.Cooldowns.LastRaidTime or 0
    local cooldownRemaining = (lastRaidTime + GameConfig.Raids.RaidCooldown) - currentTime
    
    if cooldownRemaining > 0 and not GameConfig.Debug.InstantCooldowns then
        return false, "Raid-Cooldown aktiv"
    end
    
    return true, nil
end

--[[
    Gibt verbleibendes Cooldown zurück
    @param player: Der Spieler
    @return: Sekunden (0 wenn bereit)
]]
function RaidSystem.GetRaidCooldown(player)
    local data = DataManager and DataManager.GetData(player)
    if not data then return 0 end
    
    if GameConfig.Debug.InstantCooldowns then
        return 0
    end
    
    local currentTime = os.time()
    local lastRaidTime = data.Cooldowns.LastRaidTime or 0
    
    return math.max(0, (lastRaidTime + GameConfig.Raids.RaidCooldown) - currentTime)
end

return RaidSystem
