--[[
    CurrencyUtil.lua
    Hilfsfunktionen für Währungsberechnungen
    Pfad: ReplicatedStorage/Shared/Modules/CurrencyUtil
    
    Wird von Server UND Client verwendet:
    - Server: Echte Transaktionen
    - Client: UI-Vorschauen & Validierung
    
    WICHTIG: Keine Daten-Manipulation hier!
    Nur Berechnungen und Formatierung.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Config laden
local ConfigPath = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))

local CurrencyUtil = {}

-------------------------------------------------
-- KONSTANTEN (aus GameConfig referenziert)
-------------------------------------------------
local CURRENCY = GameConfig.Currency
local PRESTIGE = GameConfig.Prestige
local TIMING = GameConfig.Timing

-------------------------------------------------
-- FORMATIERUNG
-------------------------------------------------

--[[
    Formatiert eine Zahl für die Anzeige
    Beispiele:
    - 999 -> "999"
    - 1500 -> "1.5K"
    - 1500000 -> "1.5M"
    - 1500000000 -> "1.5B"
]]
function CurrencyUtil.FormatNumber(amount)
    if amount < 1000 then
        return tostring(math.floor(amount))
    elseif amount < 1000000 then
        -- Tausender (K)
        local value = amount / 1000
        if value >= 100 then
            return string.format("%dK", math.floor(value))
        elseif value >= 10 then
            return string.format("%.1fK", value):gsub("%.0K", "K")
        else
            return string.format("%.2fK", value):gsub("%.00K", "K"):gsub("0K", "K")
        end
    elseif amount < 1000000000 then
        -- Millionen (M)
        local value = amount / 1000000
        if value >= 100 then
            return string.format("%dM", math.floor(value))
        elseif value >= 10 then
            return string.format("%.1fM", value):gsub("%.0M", "M")
        else
            return string.format("%.2fM", value):gsub("%.00M", "M"):gsub("0M", "M")
        end
    else
        -- Milliarden (B)
        local value = amount / 1000000000
        if value >= 100 then
            return string.format("%dB", math.floor(value))
        elseif value >= 10 then
            return string.format("%.1fB", value):gsub("%.0B", "B")
        else
            return string.format("%.2fB", value):gsub("%.00B", "B"):gsub("0B", "B")
        end
    end
end

--[[
    Formatiert Währung mit Symbol
    Beispiele:
    - FormatGold(1500) -> "💰 1.5K"
    - FormatGems(50) -> "💎 50"
]]
function CurrencyUtil.FormatGold(amount)
    return "💰 " .. CurrencyUtil.FormatNumber(amount)
end

function CurrencyUtil.FormatGems(amount)
    return "💎 " .. CurrencyUtil.FormatNumber(amount)
end

--[[
    Formatiert Kosten-Tabelle für Anzeige
    Input: { Gold = 500, Gems = 10 }
    Output: "💰 500  💎 10" oder "💰 500" (wenn Gems = 0)
]]
function CurrencyUtil.FormatCost(cost)
    local parts = {}
    
    if cost.Gold and cost.Gold > 0 then
        table.insert(parts, CurrencyUtil.FormatGold(cost.Gold))
    end
    
    if cost.Gems and cost.Gems > 0 then
        table.insert(parts, CurrencyUtil.FormatGems(cost.Gems))
    end
    
    if #parts == 0 then
        return "Kostenlos"
    end
    
    return table.concat(parts, "  ")
end

-------------------------------------------------
-- PASSIVE INCOME BERECHNUNGEN
-------------------------------------------------

--[[
    Berechnet passives Einkommen pro Minute
    Formel: Basis * (Multiplikator ^ (Level-1)) * (1 + PrestigeBonus)
    
    @param dungeonLevel: Aktuelles Dungeon-Level
    @param prestigeLevel: Aktuelles Prestige-Level
    @return: Gold pro Minute
]]
function CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
    local base = CURRENCY.PassiveIncomeBase
    local multiplier = CURRENCY.PassiveIncomeMultiplier
    local prestigeBonus = prestigeLevel * PRESTIGE.BonusPerPrestige
    
    -- Basis-Einkommen mit Level-Skalierung
    local income = base * (multiplier ^ (dungeonLevel - 1))
    
    -- Prestige-Bonus anwenden
    income = income * (1 + prestigeBonus)
    
    return math.floor(income)
end

--[[
    Berechnet angesammeltes passives Einkommen seit letzter Abholung
    
    @param dungeonLevel: Aktuelles Dungeon-Level
    @param prestigeLevel: Aktuelles Prestige-Level
    @param lastCollectTime: Unix Timestamp der letzten Abholung
    @param currentTime: Aktueller Unix Timestamp (optional, default = os.time())
    @return: Angesammeltes Gold
]]
function CurrencyUtil.CalculateAccumulatedIncome(dungeonLevel, prestigeLevel, lastCollectTime, currentTime)
    currentTime = currentTime or os.time()
    
    -- Zeit seit letzter Abholung in Minuten
    local elapsedSeconds = math.max(0, currentTime - lastCollectTime)
    local elapsedMinutes = elapsedSeconds / 60
    
    -- Max 24 Stunden ansammeln (1440 Minuten)
    local maxMinutes = 24 * 60
    elapsedMinutes = math.min(elapsedMinutes, maxMinutes)
    
    -- Einkommen berechnen
    local incomePerMinute = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
    local totalIncome = incomePerMinute * elapsedMinutes
    
    return math.floor(totalIncome)
end

--[[
    Berechnet maximales ansammelbares Einkommen (24h Cap)
    
    @param dungeonLevel: Aktuelles Dungeon-Level
    @param prestigeLevel: Aktuelles Prestige-Level
    @return: Maximales Gold nach 24 Stunden
]]
function CurrencyUtil.CalculateMaxAccumulation(dungeonLevel, prestigeLevel)
    local incomePerMinute = CurrencyUtil.CalculatePassiveIncome(dungeonLevel, prestigeLevel)
    local maxMinutes = 24 * 60  -- 24 Stunden
    
    return math.floor(incomePerMinute * maxMinutes)
end

-------------------------------------------------
-- VALIDIERUNG
-------------------------------------------------

--[[
    Prüft ob Spieler genug Währung hat
    
    @param playerCurrency: { Gold = X, Gems = Y }
    @param cost: { Gold = X, Gems = Y }
    @return: boolean, string (Fehlergrund wenn false)
]]
function CurrencyUtil.CanAfford(playerCurrency, cost)
    local goldNeeded = cost.Gold or 0
    local gemsNeeded = cost.Gems or 0
    
    local playerGold = playerCurrency.Gold or 0
    local playerGems = playerCurrency.Gems or 0
    
    if playerGold < goldNeeded then
        local missing = goldNeeded - playerGold
        return false, "Nicht genug Gold! Es fehlen " .. CurrencyUtil.FormatNumber(missing) .. " Gold."
    end
    
    if playerGems < gemsNeeded then
        local missing = gemsNeeded - playerGems
        return false, "Nicht genug Gems! Es fehlen " .. CurrencyUtil.FormatNumber(missing) .. " Gems."
    end
    
    return true, nil
end

--[[
    Prüft ob ein Wert die Währungs-Caps überschreitet
    
    @param amount: Zu prüfender Betrag
    @param currencyType: "Gold" oder "Gems"
    @return: Gecappter Betrag
]]
function CurrencyUtil.ClampToMax(amount, currencyType)
    if currencyType == "Gold" then
        return math.min(amount, CURRENCY.MaxGold)
    elseif currencyType == "Gems" then
        return math.min(amount, CURRENCY.MaxGems)
    end
    return amount
end

--[[
    Berechnet wie viel tatsächlich hinzugefügt werden kann (bis zum Cap)
    
    @param currentAmount: Aktueller Betrag
    @param addAmount: Zu addierender Betrag
    @param currencyType: "Gold" oder "Gems"
    @return: Tatsächlich addierbarer Betrag
]]
function CurrencyUtil.CalculateAddable(currentAmount, addAmount, currencyType)
    local maxAmount = currencyType == "Gold" and CURRENCY.MaxGold or CURRENCY.MaxGems
    local spaceLeft = maxAmount - currentAmount
    
    return math.min(addAmount, math.max(0, spaceLeft))
end

-------------------------------------------------
-- KOSTEN-BERECHNUNGEN
-------------------------------------------------

--[[
    Berechnet Kosten für einen neuen Dungeon-Raum
    Formel: Basis * (Multiplikator ^ AnzahlRäume)
    
    @param currentRoomCount: Anzahl der aktuellen Räume
    @return: { Gold = X, Gems = 0 }
]]
function CurrencyUtil.CalculateNewRoomCost(currentRoomCount)
    local base = GameConfig.Dungeon.RoomCostBase
    local multiplier = GameConfig.Dungeon.RoomCostMultiplier
    
    local cost = base * (multiplier ^ currentRoomCount)
    
    return {
        Gold = math.floor(cost),
        Gems = 0,
    }
end

--[[
    Wendet Prestige-Rabatt auf Kosten an
    
    @param baseCost: { Gold = X, Gems = Y }
    @param prestigeLevel: Aktuelles Prestige-Level
    @param discountPercent: Rabatt pro Prestige (default: 0.02 = 2%)
    @return: { Gold = X, Gems = Y } mit Rabatt
]]
function CurrencyUtil.ApplyPrestigeDiscount(baseCost, prestigeLevel, discountPercent)
    discountPercent = discountPercent or 0.02  -- 2% Rabatt pro Prestige
    
    local totalDiscount = math.min(prestigeLevel * discountPercent, 0.5)  -- Max 50% Rabatt
    local multiplier = 1 - totalDiscount
    
    return {
        Gold = math.floor((baseCost.Gold or 0) * multiplier),
        Gems = math.floor((baseCost.Gems or 0) * multiplier),
    }
end

-------------------------------------------------
-- RAID-BELOHNUNGEN
-------------------------------------------------

--[[
    Berechnet Basis-Belohnung für einen Raid
    
    @param targetDungeonLevel: Level des angegriffenen Dungeons
    @param progressPercent: Wie weit kam der Spieler (0.0 - 1.0)
    @param prestigeLevel: Prestige-Level des Angreifers
    @return: { Gold = X, Gems = Y }
]]
function CurrencyUtil.CalculateRaidReward(targetDungeonLevel, progressPercent, prestigeLevel)
    local baseGold = 50
    local baseGems = 1
    
    -- Level-Bonus
    local levelMultiplier = GameConfig.Raids.RewardMultiplierBase + 
        (GameConfig.Raids.RewardMultiplierPerLevel * (targetDungeonLevel - 1))
    
    -- Progress-Bonus (mehr Belohnung je weiter man kommt)
    local progressMultiplier = 0.2 + (progressPercent * 0.8)  -- Min 20%, Max 100%
    
    -- Prestige-Bonus
    local prestigeBonus = 1 + (prestigeLevel * PRESTIGE.BonusPerPrestige)
    
    -- Komplett-Bonus (100% durchgelaufen)
    local completionBonus = progressPercent >= 1.0 and 1.5 or 1.0
    
    -- Berechnung
    local gold = baseGold * levelMultiplier * progressMultiplier * prestigeBonus * completionBonus
    local gems = baseGems * levelMultiplier * completionBonus
    
    -- Gems nur bei signifikantem Fortschritt
    if progressPercent < 0.5 then
        gems = 0
    end
    
    return {
        Gold = math.floor(gold),
        Gems = math.floor(gems),
    }
end

--[[
    Berechnet Defense-Belohnung (wenn jemand deinen Dungeon angreift)
    
    @param attackerKilled: Anzahl getöteter Helden
    @param dungeonLevel: Eigenes Dungeon-Level
    @return: { Gold = X, Gems = Y }
]]
function CurrencyUtil.CalculateDefenseReward(attackerKilled, dungeonLevel)
    local goldPerKill = 10 * dungeonLevel
    local gemsPerKill = 0.5
    
    return {
        Gold = math.floor(attackerKilled * goldPerKill),
        Gems = math.floor(attackerKilled * gemsPerKill),
    }
end

-------------------------------------------------
-- HILFSFUNKTIONEN
-------------------------------------------------

--[[
    Erstellt eine leere Kosten-Tabelle
]]
function CurrencyUtil.EmptyCost()
    return {
        Gold = 0,
        Gems = 0,
    }
end

--[[
    Addiert zwei Kosten-Tabellen
]]
function CurrencyUtil.AddCosts(cost1, cost2)
    return {
        Gold = (cost1.Gold or 0) + (cost2.Gold or 0),
        Gems = (cost1.Gems or 0) + (cost2.Gems or 0),
    }
end

--[[
    Multipliziert Kosten mit einem Faktor
]]
function CurrencyUtil.MultiplyCost(cost, factor)
    return {
        Gold = math.floor((cost.Gold or 0) * factor),
        Gems = math.floor((cost.Gems or 0) * factor),
    }
end

--[[
    Prüft ob Kosten-Tabelle leer ist (beide 0)
]]
function CurrencyUtil.IsFree(cost)
    return (cost.Gold or 0) == 0 and (cost.Gems or 0) == 0
end

return CurrencyUtil
