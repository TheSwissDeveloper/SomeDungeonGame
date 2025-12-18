--[[
    CombatSystem.lua
    Zentrale Kampfberechnung
    Pfad: ServerScriptService/Server/Systems/CombatSystem
    
    Verantwortlich für:
    - Schadenberechnung (physisch, magisch, elementar)
    - Rüstung und Resistenzen
    - Kritische Treffer
    - Statuseffekte (DoT, CC, Buffs, Debuffs)
    - Fähigkeiten und Cooldowns
    - Zielauswahl und Aggro
    
    WICHTIG: Wird vom RaidSystem für Kampf-Ticks verwendet!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Auf Shared-Module warten
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")

-- Module laden
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))

local CombatSystem = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Schadensberechnung
    BaseArmorReduction = 100,           -- Armor / (Armor + BaseArmorReduction)
    BaseMagicResist = 50,               -- Ähnlich wie Armor
    
    -- Kritische Treffer
    BaseCritChance = 0.05,              -- 5% Basis
    BaseCritMultiplier = 1.5,           -- 150% Schaden
    MaxCritChance = 0.75,               -- Max 75%
    
    -- Elementar-Schaden
    ElementalMultipliers = {
        -- Angreifer -> Verteidiger = Multiplikator
        Fire = { Nature = 1.5, Ice = 0.75, Fire = 0.5 },
        Ice = { Fire = 1.5, Nature = 0.75, Ice = 0.5 },
        Nature = { Ice = 1.5, Fire = 0.75, Nature = 0.5 },
        Lightning = { Water = 1.5, Earth = 0.75, Lightning = 0.5 },
        Water = { Fire = 1.25, Lightning = 0.5, Water = 0.5 },
        Earth = { Lightning = 1.5, Water = 0.75, Earth = 0.5 },
        Dark = { Light = 1.5, Dark = 0.5 },
        Light = { Dark = 1.5, Light = 0.5 },
        Physical = {},  -- Kein Elementar-Bonus
    },
    
    -- Statuseffekte
    MaxStacksPerEffect = 5,
    
    -- Aggro
    DamageAggroMultiplier = 1.0,
    HealAggroMultiplier = 0.5,
    TauntAggroBonus = 1000,
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- DAMAGE TYPES
-------------------------------------------------
CombatSystem.DamageType = {
    Physical = "Physical",
    Fire = "Fire",
    Ice = "Ice",
    Nature = "Nature",
    Lightning = "Lightning",
    Water = "Water",
    Earth = "Earth",
    Dark = "Dark",
    Light = "Light",
    True = "True",  -- Ignoriert Rüstung
}

-------------------------------------------------
-- STATUS EFFECT TYPES
-------------------------------------------------
CombatSystem.StatusType = {
    -- Crowd Control
    Stun = "Stun",
    Slow = "Slow",
    Root = "Root",
    Silence = "Silence",
    Blind = "Blind",
    Fear = "Fear",
    
    -- Damage over Time
    Poison = "Poison",
    Burn = "Burn",
    Bleed = "Bleed",
    Frostbite = "Frostbite",
    
    -- Buffs
    Shield = "Shield",
    Regeneration = "Regeneration",
    AttackBuff = "AttackBuff",
    DefenseBuff = "DefenseBuff",
    SpeedBuff = "SpeedBuff",
    CritBuff = "CritBuff",
    
    -- Debuffs
    AttackDebuff = "AttackDebuff",
    DefenseDebuff = "DefenseDebuff",
    SpeedDebuff = "SpeedDebuff",
    Vulnerable = "Vulnerable",
    
    -- Special
    Taunt = "Taunt",
    Invulnerable = "Invulnerable",
    Marked = "Marked",
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
CombatSystem.Signals = {
    DamageDealt = SignalUtil.new(),          -- (attacker, target, damageInfo)
    DamageReceived = SignalUtil.new(),       -- (target, attacker, damageInfo)
    CriticalHit = SignalUtil.new(),          -- (attacker, target, damage)
    StatusApplied = SignalUtil.new(),        -- (target, statusEffect)
    StatusRemoved = SignalUtil.new(),        -- (target, statusType)
    StatusTick = SignalUtil.new(),           -- (target, statusEffect, tickDamage)
    EntityKilled = SignalUtil.new(),         -- (killer, victim)
    AbilityUsed = SignalUtil.new(),          -- (caster, ability, targets)
    HealApplied = SignalUtil.new(),          -- (healer, target, amount)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[CombatSystem]", ...)
    end
end

--[[
    Berechnet Elementar-Multiplikator
    @param attackerElement: Element des Angreifers
    @param defenderElement: Element des Verteidigers
    @return: Multiplikator
]]
local function calculateElementalMultiplier(attackerElement, defenderElement)
    if not attackerElement or attackerElement == "Physical" then
        return 1.0
    end
    
    local elementData = CONFIG.ElementalMultipliers[attackerElement]
    if not elementData then
        return 1.0
    end
    
    return elementData[defenderElement] or 1.0
end

--[[
    Berechnet Rüstungsreduktion
    @param armor: Rüstungswert
    @return: Schadensreduktion (0-1)
]]
local function calculateArmorReduction(armor)
    if armor <= 0 then
        return 0
    end
    
    return armor / (armor + CONFIG.BaseArmorReduction)
end

--[[
    Berechnet Magieresistenz-Reduktion
    @param magicResist: Magieresistenz-Wert
    @return: Schadensreduktion (0-1)
]]
local function calculateMagicResistReduction(magicResist)
    if magicResist <= 0 then
        return 0
    end
    
    return magicResist / (magicResist + CONFIG.BaseMagicResist)
end

--[[
    Würfelt kritischen Treffer
    @param critChance: Kritische Trefferchance
    @return: isCrit, multiplier
]]
local function rollCritical(critChance)
    local actualChance = math.min(critChance or CONFIG.BaseCritChance, CONFIG.MaxCritChance)
    
    if math.random() < actualChance then
        return true, CONFIG.BaseCritMultiplier
    end
    
    return false, 1.0
end

--[[
    Berechnet Statuseffekt-Modifikatoren für ein Entity
    @param entity: Das Entity mit Status-Tabelle
    @return: Modifikatoren-Tabelle
]]
local function calculateStatusModifiers(entity)
    local modifiers = {
        DamageDealt = 1.0,
        DamageReceived = 1.0,
        AttackSpeed = 1.0,
        MoveSpeed = 1.0,
        CritChance = 0,
        Armor = 0,
        CanAct = true,
        CanMove = true,
        CanUseAbilities = true,
    }
    
    if not entity or not entity.Status then
        return modifiers
    end
    
    for statusType, statusData in pairs(entity.Status) do
        -- CC-Effekte
        if statusType == CombatSystem.StatusType.Stun then
            modifiers.CanAct = false
            modifiers.CanMove = false
            modifiers.CanUseAbilities = false
        elseif statusType == CombatSystem.StatusType.Root then
            modifiers.CanMove = false
        elseif statusType == CombatSystem.StatusType.Silence then
            modifiers.CanUseAbilities = false
        elseif statusType == CombatSystem.StatusType.Slow then
            local slowPercent = statusData.Percent or 0.3
            modifiers.AttackSpeed = modifiers.AttackSpeed * (1 - slowPercent)
            modifiers.MoveSpeed = modifiers.MoveSpeed * (1 - slowPercent)
        elseif statusType == CombatSystem.StatusType.Blind then
            -- Miss-Chance wird separat behandelt
        elseif statusType == CombatSystem.StatusType.Fear then
            modifiers.CanAct = false
        
        -- Buffs
        elseif statusType == CombatSystem.StatusType.AttackBuff then
            local buffPercent = statusData.Percent or 0.2
            modifiers.DamageDealt = modifiers.DamageDealt * (1 + buffPercent)
        elseif statusType == CombatSystem.StatusType.DefenseBuff then
            local buffPercent = statusData.Percent or 0.2
            modifiers.DamageReceived = modifiers.DamageReceived * (1 - buffPercent)
        elseif statusType == CombatSystem.StatusType.SpeedBuff then
            local buffPercent = statusData.Percent or 0.2
            modifiers.AttackSpeed = modifiers.AttackSpeed * (1 + buffPercent)
            modifiers.MoveSpeed = modifiers.MoveSpeed * (1 + buffPercent)
        elseif statusType == CombatSystem.StatusType.CritBuff then
            modifiers.CritChance = modifiers.CritChance + (statusData.Bonus or 0.15)
        
        -- Debuffs
        elseif statusType == CombatSystem.StatusType.AttackDebuff then
            local debuffPercent = statusData.Percent or 0.2
            modifiers.DamageDealt = modifiers.DamageDealt * (1 - debuffPercent)
        elseif statusType == CombatSystem.StatusType.DefenseDebuff then
            local debuffPercent = statusData.Percent or 0.2
            modifiers.Armor = modifiers.Armor - (statusData.FlatReduction or 0)
        elseif statusType == CombatSystem.StatusType.Vulnerable then
            local vulnPercent = statusData.Percent or 0.25
            modifiers.DamageReceived = modifiers.DamageReceived * (1 + vulnPercent)
        
        -- Special
        elseif statusType == CombatSystem.StatusType.Invulnerable then
            modifiers.DamageReceived = 0
        end
    end
    
    return modifiers
end

-------------------------------------------------
-- PUBLIC API - SCHADENSBERECHNUNG
-------------------------------------------------

--[[
    Berechnet und wendet Schaden an
    @param attacker: Angreifendes Entity
    @param target: Ziel-Entity
    @param baseDamage: Basis-Schaden
    @param damageType: Schadenstyp
    @param options: Zusätzliche Optionen { CanCrit, IgnoreArmor, BonusMultiplier }
    @return: damageInfo { FinalDamage, IsCrit, WasBlocked, DamageType, etc. }
]]
function CombatSystem.CalculateDamage(attacker, target, baseDamage, damageType, options)
    options = options or {}
    damageType = damageType or CombatSystem.DamageType.Physical
    
    local damageInfo = {
        BaseDamage = baseDamage,
        FinalDamage = 0,
        DamageType = damageType,
        IsCrit = false,
        CritMultiplier = 1.0,
        ArmorReduction = 0,
        ElementalMultiplier = 1.0,
        WasBlocked = false,
        WasDodged = false,
        WasMissed = false,
        Attacker = attacker,
        Target = target,
    }
    
    -- Prüfen ob Ziel Invulnerable ist
    if target.Status and target.Status[CombatSystem.StatusType.Invulnerable] then
        damageInfo.WasBlocked = true
        return damageInfo
    end
    
    -- Modifikatoren berechnen
    local attackerMods = calculateStatusModifiers(attacker)
    local targetMods = calculateStatusModifiers(target)
    
    -- Prüfen ob Angreifer handeln kann
    if not attackerMods.CanAct then
        damageInfo.FinalDamage = 0
        return damageInfo
    end
    
    -- Blind-Check (Miss-Chance)
    if attacker.Status and attacker.Status[CombatSystem.StatusType.Blind] then
        local missChance = attacker.Status[CombatSystem.StatusType.Blind].MissChance or 0.5
        if math.random() < missChance then
            damageInfo.WasMissed = true
            return damageInfo
        end
    end
    
    local damage = baseDamage
    
    -- Angreifer-Schaden-Modifikator
    damage = damage * attackerMods.DamageDealt
    
    -- Bonus-Multiplikator (z.B. von Fähigkeiten)
    if options.BonusMultiplier then
        damage = damage * options.BonusMultiplier
    end
    
    -- Kritischer Treffer
    if options.CanCrit ~= false then
        local critChance = (attacker.CritChance or CONFIG.BaseCritChance) + attackerMods.CritChance
        local isCrit, critMult = rollCritical(critChance)
        
        if isCrit then
            damage = damage * critMult
            damageInfo.IsCrit = true
            damageInfo.CritMultiplier = critMult
        end
    end
    
    -- Elementar-Multiplikator
    local attackerElement = attacker.Element or damageType
    local targetElement = target.Element or "Physical"
    local elementMult = calculateElementalMultiplier(attackerElement, targetElement)
    damage = damage * elementMult
    damageInfo.ElementalMultiplier = elementMult
    
    -- Rüstung (außer True Damage)
    if damageType ~= CombatSystem.DamageType.True and not options.IgnoreArmor then
        local armor = (target.Armor or 0) + targetMods.Armor
        armor = math.max(0, armor)  -- Keine negative Rüstung
        
        local isPhysical = damageType == CombatSystem.DamageType.Physical
        local reduction
        
        if isPhysical then
            reduction = calculateArmorReduction(armor)
        else
            local magicResist = target.MagicResist or 0
            reduction = calculateMagicResistReduction(magicResist)
        end
        
        damageInfo.ArmorReduction = reduction
        damage = damage * (1 - reduction)
    end
    
    -- Ziel-Schaden-Modifikator
    damage = damage * targetMods.DamageReceived
    
    -- Shield absorbieren
    if target.Status and target.Status[CombatSystem.StatusType.Shield] then
        local shield = target.Status[CombatSystem.StatusType.Shield]
        local shieldAmount = shield.Amount or 0
        
        if shieldAmount >= damage then
            shield.Amount = shieldAmount - damage
            damage = 0
            damageInfo.WasBlocked = true
            
            -- Shield aufgebraucht?
            if shield.Amount <= 0 then
                target.Status[CombatSystem.StatusType.Shield] = nil
            end
        else
            damage = damage - shieldAmount
            target.Status[CombatSystem.StatusType.Shield] = nil
        end
    end
    
    -- Finale Schadenswert (mindestens 1, außer geblockt)
    if not damageInfo.WasBlocked then
        damageInfo.FinalDamage = math.max(1, math.floor(damage))
    end
    
    return damageInfo
end

--[[
    Wendet berechneten Schaden auf Ziel an
    @param target: Ziel-Entity
    @param damageInfo: Ergebnis von CalculateDamage
    @return: isDead
]]
function CombatSystem.ApplyDamage(target, damageInfo)
    if damageInfo.WasBlocked or damageInfo.WasMissed or damageInfo.WasDodged then
        return false
    end
    
    local finalDamage = damageInfo.FinalDamage
    
    -- Schaden anwenden
    target.CurrentHealth = (target.CurrentHealth or target.MaxHealth) - finalDamage
    
    -- Signals feuern
    CombatSystem.Signals.DamageDealt:Fire(damageInfo.Attacker, target, damageInfo)
    CombatSystem.Signals.DamageReceived:Fire(target, damageInfo.Attacker, damageInfo)
    
    if damageInfo.IsCrit then
        CombatSystem.Signals.CriticalHit:Fire(damageInfo.Attacker, target, finalDamage)
    end
    
    -- Tod prüfen
    if target.CurrentHealth <= 0 then
        target.CurrentHealth = 0
        target.IsAlive = false
        
        CombatSystem.Signals.EntityKilled:Fire(damageInfo.Attacker, target)
        
        return true
    end
    
    return false
end

--[[
    Kombinierte Funktion: Berechnet und wendet Schaden an
    @return: damageInfo, isDead
]]
function CombatSystem.DealDamage(attacker, target, baseDamage, damageType, options)
    local damageInfo = CombatSystem.CalculateDamage(attacker, target, baseDamage, damageType, options)
    local isDead = CombatSystem.ApplyDamage(target, damageInfo)
    
    return damageInfo, isDead
end

-------------------------------------------------
-- PUBLIC API - HEILUNG
-------------------------------------------------

--[[
    Wendet Heilung an
    @param healer: Heilendes Entity (kann nil sein)
    @param target: Ziel-Entity
    @param amount: Heilungsmenge
    @param canCrit: Kann kritisch heilen
    @return: actualHealing
]]
function CombatSystem.ApplyHealing(healer, target, amount, canCrit)
    if not target.IsAlive then
        return 0
    end
    
    local healing = amount
    
    -- Kritische Heilung
    if canCrit and healer then
        local critChance = healer.CritChance or CONFIG.BaseCritChance
        local isCrit, critMult = rollCritical(critChance)
        
        if isCrit then
            healing = healing * critMult
        end
    end
    
    -- Heilung anwenden
    local oldHealth = target.CurrentHealth
    target.CurrentHealth = math.min(target.MaxHealth, target.CurrentHealth + healing)
    local actualHealing = target.CurrentHealth - oldHealth
    
    -- Signal feuern
    if actualHealing > 0 then
        CombatSystem.Signals.HealApplied:Fire(healer, target, actualHealing)
    end
    
    return actualHealing
end

-------------------------------------------------
-- PUBLIC API - STATUSEFFEKTE
-------------------------------------------------

--[[
    Wendet Statuseffekt an
    @param target: Ziel-Entity
    @param statusType: Typ des Effekts
    @param statusData: Effekt-Daten { Duration, Percent, DPS, Stacks, etc. }
    @param source: Quelle des Effekts (optional)
    @return: success
]]
function CombatSystem.ApplyStatus(target, statusType, statusData, source)
    if not target.IsAlive then
        return false
    end
    
    -- Status-Tabelle initialisieren
    if not target.Status then
        target.Status = {}
    end
    
    statusData = statusData or {}
    statusData.Source = source
    statusData.AppliedAt = os.clock()
    statusData.Duration = statusData.Duration or 5
    statusData.Stacks = statusData.Stacks or 1
    
    -- Prüfen ob bereits aktiv
    local existingStatus = target.Status[statusType]
    
    if existingStatus then
        -- Stacking-Logik
        if statusData.Stackable then
            existingStatus.Stacks = math.min(
                (existingStatus.Stacks or 1) + 1,
                CONFIG.MaxStacksPerEffect
            )
            existingStatus.Duration = statusData.Duration  -- Refresh Duration
        else
            -- Überschreiben wenn stärker oder refresh
            if (statusData.Percent or 0) >= (existingStatus.Percent or 0) then
                target.Status[statusType] = statusData
            else
                -- Nur Duration refreshen
                existingStatus.Duration = math.max(existingStatus.Duration, statusData.Duration)
            end
        end
    else
        -- Neuen Status hinzufügen
        target.Status[statusType] = statusData
    end
    
    CombatSystem.Signals.StatusApplied:Fire(target, statusType, statusData)
    
    return true
end

--[[
    Entfernt Statuseffekt
    @param target: Ziel-Entity
    @param statusType: Typ des Effekts
    @return: success
]]
function CombatSystem.RemoveStatus(target, statusType)
    if not target.Status or not target.Status[statusType] then
        return false
    end
    
    target.Status[statusType] = nil
    
    CombatSystem.Signals.StatusRemoved:Fire(target, statusType)
    
    return true
end

--[[
    Verarbeitet Statuseffekte (pro Tick)
    @param target: Das Entity
    @param deltaTime: Zeit seit letztem Tick
    @return: totalDamage, effects { removed = {}, triggered = {} }
]]
function CombatSystem.ProcessStatusEffects(target, deltaTime)
    if not target.Status then
        return 0, { removed = {}, triggered = {} }
    end
    
    local totalDamage = 0
    local effects = { removed = {}, triggered = {} }
    
    local toRemove = {}
    
    for statusType, statusData in pairs(target.Status) do
        -- Duration reduzieren
        statusData.Duration = statusData.Duration - deltaTime
        
        -- DoT-Effekte verarbeiten
        if statusType == CombatSystem.StatusType.Poison or
           statusType == CombatSystem.StatusType.Burn or
           statusType == CombatSystem.StatusType.Bleed or
           statusType == CombatSystem.StatusType.Frostbite then
            
            local dps = statusData.DPS or 10
            local stacks = statusData.Stacks or 1
            local tickDamage = dps * deltaTime * stacks
            
            totalDamage = totalDamage + tickDamage
            target.CurrentHealth = target.CurrentHealth - tickDamage
            
            table.insert(effects.triggered, {
                Type = statusType,
                Damage = tickDamage,
            })
            
            CombatSystem.Signals.StatusTick:Fire(target, statusType, tickDamage)
        end
        
        -- Regeneration verarbeiten
        if statusType == CombatSystem.StatusType.Regeneration then
            local hps = statusData.HPS or 10
            local healing = hps * deltaTime
            
            target.CurrentHealth = math.min(target.MaxHealth, target.CurrentHealth + healing)
            
            table.insert(effects.triggered, {
                Type = statusType,
                Healing = healing,
            })
        end
        
        -- Abgelaufene Effekte markieren
        if statusData.Duration <= 0 then
            table.insert(toRemove, statusType)
        end
    end
    
    -- Abgelaufene Effekte entfernen
    for _, statusType in ipairs(toRemove) do
        target.Status[statusType] = nil
        table.insert(effects.removed, statusType)
        
        CombatSystem.Signals.StatusRemoved:Fire(target, statusType)
    end
    
    -- Tod durch DoT prüfen
    if target.CurrentHealth <= 0 then
        target.CurrentHealth = 0
        target.IsAlive = false
        
        CombatSystem.Signals.EntityKilled:Fire(nil, target)
    end
    
    return totalDamage, effects
end

--[[
    Entfernt alle negativen Statuseffekte (Cleanse)
    @param target: Ziel-Entity
    @return: removedCount
]]
function CombatSystem.CleanseLegativeEffects(target)
    if not target.Status then
        return 0
    end
    
    local negativeEffects = {
        CombatSystem.StatusType.Stun,
        CombatSystem.StatusType.Slow,
        CombatSystem.StatusType.Root,
        CombatSystem.StatusType.Silence,
        CombatSystem.StatusType.Blind,
        CombatSystem.StatusType.Fear,
        CombatSystem.StatusType.Poison,
        CombatSystem.StatusType.Burn,
        CombatSystem.StatusType.Bleed,
        CombatSystem.StatusType.Frostbite,
        CombatSystem.StatusType.AttackDebuff,
        CombatSystem.StatusType.DefenseDebuff,
        CombatSystem.StatusType.SpeedDebuff,
        CombatSystem.StatusType.Vulnerable,
    }
    
    local removedCount = 0
    
    for _, effectType in ipairs(negativeEffects) do
        if CombatSystem.RemoveStatus(target, effectType) then
            removedCount = removedCount + 1
        end
    end
    
    return removedCount
end

-------------------------------------------------
-- PUBLIC API - ZIELAUSWAHL
-------------------------------------------------

--[[
    Findet bestes Ziel für einen Angreifer
    @param attacker: Angreifendes Entity
    @param targets: Array von möglichen Zielen
    @param strategy: Zielauswahl-Strategie
    @return: Bestes Ziel oder nil
]]
function CombatSystem.FindTarget(attacker, targets, strategy)
    strategy = strategy or "Nearest"
    
    local validTargets = {}
    
    for _, target in ipairs(targets) do
        if target.IsAlive then
            table.insert(validTargets, target)
        end
    end
    
    if #validTargets == 0 then
        return nil
    end
    
    -- Taunt-Check
    for _, target in ipairs(validTargets) do
        if target.Status and target.Status[CombatSystem.StatusType.Taunt] then
            local tauntSource = target.Status[CombatSystem.StatusType.Taunt].Source
            if tauntSource == attacker then
                return target
            end
        end
    end
    
    -- Strategie anwenden
    if strategy == "LowestHealth" then
        table.sort(validTargets, function(a, b)
            return a.CurrentHealth < b.CurrentHealth
        end)
        return validTargets[1]
        
    elseif strategy == "LowestHealthPercent" then
        table.sort(validTargets, function(a, b)
            local aPercent = a.CurrentHealth / a.MaxHealth
            local bPercent = b.CurrentHealth / b.MaxHealth
            return aPercent < bPercent
        end)
        return validTargets[1]
        
    elseif strategy == "HighestDamage" then
        table.sort(validTargets, function(a, b)
            return (a.Damage or 0) > (b.Damage or 0)
        end)
        return validTargets[1]
        
    elseif strategy == "HighestThreat" then
        table.sort(validTargets, function(a, b)
            return (a.Threat or 0) > (b.Threat or 0)
        end)
        return validTargets[1]
        
    elseif strategy == "Random" then
        return validTargets[math.random(1, #validTargets)]
        
    else  -- "Nearest" oder default
        -- Für dieses Spiel: Erstes verfügbares Ziel
        return validTargets[1]
    end
end

--[[
    Findet mehrere Ziele (für AoE)
    @param attacker: Angreifendes Entity
    @param targets: Array von möglichen Zielen
    @param maxTargets: Maximale Anzahl Ziele
    @param strategy: Zielauswahl-Strategie
    @return: Array von Zielen
]]
function CombatSystem.FindMultipleTargets(attacker, targets, maxTargets, strategy)
    maxTargets = maxTargets or 3
    
    local validTargets = {}
    
    for _, target in ipairs(targets) do
        if target.IsAlive then
            table.insert(validTargets, target)
        end
    end
    
    -- Nach Strategie sortieren
    if strategy == "LowestHealth" then
        table.sort(validTargets, function(a, b)
            return a.CurrentHealth < b.CurrentHealth
        end)
    elseif strategy == "HighestHealth" then
        table.sort(validTargets, function(a, b)
            return a.CurrentHealth > b.CurrentHealth
        end)
    end
    
    -- Maximal maxTargets zurückgeben
    local result = {}
    for i = 1, math.min(maxTargets, #validTargets) do
        table.insert(result, validTargets[i])
    end
    
    return result
end

-------------------------------------------------
-- PUBLIC API - FÄHIGKEITEN
-------------------------------------------------

--[[
    Prüft ob Fähigkeit einsatzbereit ist
    @param caster: Das Entity
    @param abilityId: ID der Fähigkeit
    @return: canUse, reason
]]
function CombatSystem.CanUseAbility(caster, abilityId)
    -- Modifikatoren prüfen
    local mods = calculateStatusModifiers(caster)
    
    if not mods.CanUseAbilities then
        return false, "Silenced"
    end
    
    if not mods.CanAct then
        return false, "Stunned"
    end
    
    -- Cooldown prüfen
    if caster.AbilityCooldowns and caster.AbilityCooldowns[abilityId] then
        if caster.AbilityCooldowns[abilityId] > 0 then
            return false, "OnCooldown"
        end
    end
    
    return true, nil
end

--[[
    Setzt Fähigkeits-Cooldown
    @param caster: Das Entity
    @param abilityId: ID der Fähigkeit
    @param cooldown: Cooldown in Sekunden
]]
function CombatSystem.SetAbilityCooldown(caster, abilityId, cooldown)
    if not caster.AbilityCooldowns then
        caster.AbilityCooldowns = {}
    end
    
    caster.AbilityCooldowns[abilityId] = cooldown
end

--[[
    Aktualisiert alle Fähigkeits-Cooldowns
    @param caster: Das Entity
    @param deltaTime: Zeit seit letztem Update
]]
function CombatSystem.UpdateAbilityCooldowns(caster, deltaTime)
    if not caster.AbilityCooldowns then
        return
    end
    
    for abilityId, remaining in pairs(caster.AbilityCooldowns) do
        caster.AbilityCooldowns[abilityId] = math.max(0, remaining - deltaTime)
    end
end

-------------------------------------------------
-- PUBLIC API - UTILITY
-------------------------------------------------

--[[
    Prüft ob Entity handeln kann
    @param entity: Das Entity
    @return: canAct, reason
]]
function CombatSystem.CanAct(entity)
    if not entity.IsAlive then
        return false, "Dead"
    end
    
    local mods = calculateStatusModifiers(entity)
    
    if not mods.CanAct then
        if entity.Status then
            if entity.Status[CombatSystem.StatusType.Stun] then
                return false, "Stunned"
            elseif entity.Status[CombatSystem.StatusType.Fear] then
                return false, "Feared"
            end
        end
        return false, "Incapacitated"
    end
    
    return true, nil
end

--[[
    Berechnet effektiven Attack-Speed
    @param entity: Das Entity
    @return: attacksPerSecond
]]
function CombatSystem.GetEffectiveAttackSpeed(entity)
    local baseSpeed = 1 / (entity.AttackCooldown or 1)
    local mods = calculateStatusModifiers(entity)
    
    return baseSpeed * mods.AttackSpeed
end

--[[
    Erstellt Schadens-Summary für Logging
    @param damageInfo: DamageInfo-Tabelle
    @return: String-Summary
]]
function CombatSystem.FormatDamageInfo(damageInfo)
    local parts = {}
    
    table.insert(parts, damageInfo.FinalDamage .. " " .. damageInfo.DamageType)
    
    if damageInfo.IsCrit then
        table.insert(parts, "CRIT!")
    end
    
    if damageInfo.ElementalMultiplier > 1 then
        table.insert(parts, "Effective!")
    elseif damageInfo.ElementalMultiplier < 1 then
        table.insert(parts, "Resisted")
    end
    
    if damageInfo.WasBlocked then
        table.insert(parts, "Blocked")
    end
    
    if damageInfo.WasMissed then
        table.insert(parts, "Missed")
    end
    
    return table.concat(parts, " | ")
end

return CombatSystem
