--[[
    CurrencyService.lua
    Zentraler Service für Währungstransaktionen
    Pfad: ServerScriptService/Server/Services/CurrencyService
    
    Verantwortlich für:
    - Sichere Gold/Gems Transaktionen
    - Validierung und Cap-Prüfung
    - Transaktions-Logging
    - Stats-Tracking
    
    WICHTIG: Alle Währungsänderungen sollten über diesen Service laufen!
]]

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
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Manager-Referenzen (werden bei Initialize gesetzt)
local DataManager = nil
local PlayerManager = nil

local CurrencyService = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Debug-Modus
    Debug = GameConfig.Debug.Enabled,
    
    -- Transaktions-Logging
    LogTransactions = true,
}

-------------------------------------------------
-- TRANSAKTIONS-TYPEN
-------------------------------------------------
CurrencyService.TransactionType = {
    -- Einnahmen
    PassiveIncome = "PassiveIncome",
    RaidReward = "RaidReward",
    DefenseReward = "DefenseReward",
    AchievementReward = "AchievementReward",
    DailyReward = "DailyReward",
    AdminGrant = "AdminGrant",
    
    -- Ausgaben
    RoomPurchase = "RoomPurchase",
    TrapPurchase = "TrapPurchase",
    MonsterPurchase = "MonsterPurchase",
    HeroRecruit = "HeroRecruit",
    Upgrade = "Upgrade",
    Unlock = "Unlock",
    
    -- Sonstiges
    Prestige = "Prestige",
    Refund = "Refund",
    Transfer = "Transfer",
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
CurrencyService.Signals = {
    GoldChanged = SignalUtil.new(),     -- (player, oldAmount, newAmount, transactionType, source)
    GemsChanged = SignalUtil.new(),     -- (player, oldAmount, newAmount, transactionType, source)
    TransactionFailed = SignalUtil.new(), -- (player, reason, transactionType)
    CapReached = SignalUtil.new(),      -- (player, currencyType)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

-- Debug-Logging
local function debugPrint(...)
    if CONFIG.Debug then
        print("[CurrencyService]", ...)
    end
end

-- Warnung ausgeben
local function debugWarn(...)
    warn("[CurrencyService]", ...)
end

--[[
    Loggt eine Transaktion
    @param player: Der Spieler
    @param currencyType: "Gold" oder "Gems"
    @param amount: Betrag (positiv oder negativ)
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details
]]
local function logTransaction(player, currencyType, amount, transactionType, source)
    if not CONFIG.LogTransactions then return end
    
    local sign = amount >= 0 and "+" or ""
    debugPrint(string.format(
        "[%s] %s %s%d %s (%s: %s)",
        player.Name,
        transactionType,
        sign,
        amount,
        currencyType,
        source or "unknown",
        tostring(amount)
    ))
end

--[[
    Sendet Currency-Update an Client
    @param player: Der Spieler
    @param gold: Aktuelles Gold
    @param gems: Aktuelle Gems
    @param source: Quelle der Änderung
    @param amount: Geänderter Betrag (optional)
]]
local function sendCurrencyUpdate(player, gold, gems, source, amount)
    RemoteIndex.FireClient("Currency_Update", player, {
        Gold = gold,
        Gems = gems,
        Source = source,
        Amount = amount,
    })
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den CurrencyService
    @param dataManagerRef: Referenz zum DataManager
    @param playerManagerRef: Referenz zum PlayerManager
]]
function CurrencyService.Initialize(dataManagerRef, playerManagerRef)
    debugPrint("Initialisiere CurrencyService...")
    
    DataManager = dataManagerRef
    PlayerManager = playerManagerRef
    
    debugPrint("CurrencyService initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - ABFRAGEN
-------------------------------------------------

--[[
    Gibt die aktuelle Währung eines Spielers zurück
    @param player: Der Spieler
    @return: { Gold = X, Gems = Y } oder nil
]]
function CurrencyService.GetCurrency(player)
    if not DataManager then return nil end
    
    local data = DataManager.GetData(player)
    if not data then return nil end
    
    return {
        Gold = data.Currency.Gold or 0,
        Gems = data.Currency.Gems or 0,
    }
end

--[[
    Gibt den Gold-Betrag eines Spielers zurück
    @param player: Der Spieler
    @return: Gold-Betrag oder 0
]]
function CurrencyService.GetGold(player)
    local currency = CurrencyService.GetCurrency(player)
    return currency and currency.Gold or 0
end

--[[
    Gibt den Gems-Betrag eines Spielers zurück
    @param player: Der Spieler
    @return: Gems-Betrag oder 0
]]
function CurrencyService.GetGems(player)
    local currency = CurrencyService.GetCurrency(player)
    return currency and currency.Gems or 0
end

--[[
    Prüft ob Spieler sich etwas leisten kann
    @param player: Der Spieler
    @param cost: { Gold = X, Gems = Y }
    @return: canAfford, errorMessage
]]
function CurrencyService.CanAfford(player, cost)
    local currency = CurrencyService.GetCurrency(player)
    if not currency then
        return false, "Daten nicht geladen"
    end
    
    return CurrencyUtil.CanAfford(currency, cost)
end

-------------------------------------------------
-- PUBLIC API - GOLD OPERATIONEN
-------------------------------------------------

--[[
    Fügt Gold hinzu
    @param player: Der Spieler
    @param amount: Betrag (muss positiv sein)
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details (optional)
    @return: success, actualAmount (kann wegen Cap niedriger sein)
]]
function CurrencyService.AddGold(player, amount, transactionType, source)
    if not DataManager then
        return false, 0
    end
    
    if amount <= 0 then
        debugWarn("AddGold: Betrag muss positiv sein")
        return false, 0
    end
    
    local data = DataManager.GetData(player)
    if not data then
        CurrencyService.Signals.TransactionFailed:Fire(player, "Daten nicht geladen", transactionType)
        return false, 0
    end
    
    local currentGold = data.Currency.Gold or 0
    local addable = CurrencyUtil.CalculateAddable(currentGold, amount, "Gold")
    
    if addable <= 0 then
        CurrencyService.Signals.CapReached:Fire(player, "Gold")
        return false, 0
    end
    
    -- Gold hinzufügen
    local newGold = currentGold + addable
    DataManager.SetValue(player, "Currency.Gold", newGold)
    DataManager.IncrementValue(player, "Stats.TotalGoldEarned", addable)
    
    -- Logging
    logTransaction(player, "Gold", addable, transactionType, source)
    
    -- Signal feuern
    CurrencyService.Signals.GoldChanged:Fire(player, currentGold, newGold, transactionType, source)
    
    -- Client updaten
    sendCurrencyUpdate(player, newGold, data.Currency.Gems, transactionType, addable)
    
    -- Cap-Warnung wenn nicht alles hinzugefügt werden konnte
    if addable < amount then
        CurrencyService.Signals.CapReached:Fire(player, "Gold")
        if PlayerManager then
            PlayerManager.SendNotification(player, "Gold-Limit!", "Dein Gold-Speicher ist voll.", "Warning")
        end
    end
    
    return true, addable
end

--[[
    Entfernt Gold
    @param player: Der Spieler
    @param amount: Betrag (muss positiv sein)
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details (optional)
    @return: success
]]
function CurrencyService.RemoveGold(player, amount, transactionType, source)
    if not DataManager then
        return false
    end
    
    if amount <= 0 then
        debugWarn("RemoveGold: Betrag muss positiv sein")
        return false
    end
    
    local data = DataManager.GetData(player)
    if not data then
        CurrencyService.Signals.TransactionFailed:Fire(player, "Daten nicht geladen", transactionType)
        return false
    end
    
    local currentGold = data.Currency.Gold or 0
    
    if currentGold < amount then
        CurrencyService.Signals.TransactionFailed:Fire(player, "Nicht genug Gold", transactionType)
        return false
    end
    
    -- Gold entfernen
    local newGold = currentGold - amount
    DataManager.SetValue(player, "Currency.Gold", newGold)
    DataManager.IncrementValue(player, "Stats.TotalGoldSpent", amount)
    
    -- Logging
    logTransaction(player, "Gold", -amount, transactionType, source)
    
    -- Signal feuern
    CurrencyService.Signals.GoldChanged:Fire(player, currentGold, newGold, transactionType, source)
    
    -- Client updaten
    sendCurrencyUpdate(player, newGold, data.Currency.Gems, transactionType, -amount)
    
    return true
end

--[[
    Setzt Gold auf einen bestimmten Wert (Admin/Debug)
    @param player: Der Spieler
    @param amount: Neuer Betrag
    @param source: Quelle/Details
    @return: success
]]
function CurrencyService.SetGold(player, amount, source)
    if not DataManager then
        return false
    end
    
    if amount < 0 then
        amount = 0
    end
    
    -- Cap anwenden
    amount = CurrencyUtil.ClampToMax(amount, "Gold")
    
    local data = DataManager.GetData(player)
    if not data then
        return false
    end
    
    local oldGold = data.Currency.Gold or 0
    DataManager.SetValue(player, "Currency.Gold", amount)
    
    -- Logging
    logTransaction(player, "Gold", amount - oldGold, CurrencyService.TransactionType.AdminGrant, source)
    
    -- Signal feuern
    CurrencyService.Signals.GoldChanged:Fire(player, oldGold, amount, CurrencyService.TransactionType.AdminGrant, source)
    
    -- Client updaten
    sendCurrencyUpdate(player, amount, data.Currency.Gems, "AdminSet", amount - oldGold)
    
    return true
end

-------------------------------------------------
-- PUBLIC API - GEMS OPERATIONEN
-------------------------------------------------

--[[
    Fügt Gems hinzu
    @param player: Der Spieler
    @param amount: Betrag (muss positiv sein)
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details (optional)
    @return: success, actualAmount
]]
function CurrencyService.AddGems(player, amount, transactionType, source)
    if not DataManager then
        return false, 0
    end
    
    if amount <= 0 then
        debugWarn("AddGems: Betrag muss positiv sein")
        return false, 0
    end
    
    local data = DataManager.GetData(player)
    if not data then
        CurrencyService.Signals.TransactionFailed:Fire(player, "Daten nicht geladen", transactionType)
        return false, 0
    end
    
    local currentGems = data.Currency.Gems or 0
    local addable = CurrencyUtil.CalculateAddable(currentGems, amount, "Gems")
    
    if addable <= 0 then
        CurrencyService.Signals.CapReached:Fire(player, "Gems")
        return false, 0
    end
    
    -- Gems hinzufügen
    local newGems = currentGems + addable
    DataManager.SetValue(player, "Currency.Gems", newGems)
    DataManager.IncrementValue(player, "Stats.TotalGemsEarned", addable)
    
    -- Logging
    logTransaction(player, "Gems", addable, transactionType, source)
    
    -- Signal feuern
    CurrencyService.Signals.GemsChanged:Fire(player, currentGems, newGems, transactionType, source)
    
    -- Client updaten
    sendCurrencyUpdate(player, data.Currency.Gold, newGems, transactionType, addable)
    
    if addable < amount then
        CurrencyService.Signals.CapReached:Fire(player, "Gems")
    end
    
    return true, addable
end

--[[
    Entfernt Gems
    @param player: Der Spieler
    @param amount: Betrag (muss positiv sein)
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details (optional)
    @return: success
]]
function CurrencyService.RemoveGems(player, amount, transactionType, source)
    if not DataManager then
        return false
    end
    
    if amount <= 0 then
        debugWarn("RemoveGems: Betrag muss positiv sein")
        return false
    end
    
    local data = DataManager.GetData(player)
    if not data then
        CurrencyService.Signals.TransactionFailed:Fire(player, "Daten nicht geladen", transactionType)
        return false
    end
    
    local currentGems = data.Currency.Gems or 0
    
    if currentGems < amount then
        CurrencyService.Signals.TransactionFailed:Fire(player, "Nicht genug Gems", transactionType)
        return false
    end
    
    -- Gems entfernen
    local newGems = currentGems - amount
    DataManager.SetValue(player, "Currency.Gems", newGems)
    DataManager.IncrementValue(player, "Stats.TotalGemsSpent", amount)
    
    -- Logging
    logTransaction(player, "Gems", -amount, transactionType, source)
    
    -- Signal feuern
    CurrencyService.Signals.GemsChanged:Fire(player, currentGems, newGems, transactionType, source)
    
    -- Client updaten
    sendCurrencyUpdate(player, data.Currency.Gold, newGems, transactionType, -amount)
    
    return true
end

--[[
    Setzt Gems auf einen bestimmten Wert (Admin/Debug)
    @param player: Der Spieler
    @param amount: Neuer Betrag
    @param source: Quelle/Details
    @return: success
]]
function CurrencyService.SetGems(player, amount, source)
    if not DataManager then
        return false
    end
    
    if amount < 0 then
        amount = 0
    end
    
    -- Cap anwenden
    amount = CurrencyUtil.ClampToMax(amount, "Gems")
    
    local data = DataManager.GetData(player)
    if not data then
        return false
    end
    
    local oldGems = data.Currency.Gems or 0
    DataManager.SetValue(player, "Currency.Gems", amount)
    
    -- Logging
    logTransaction(player, "Gems", amount - oldGems, CurrencyService.TransactionType.AdminGrant, source)
    
    -- Signal feuern
    CurrencyService.Signals.GemsChanged:Fire(player, oldGems, amount, CurrencyService.TransactionType.AdminGrant, source)
    
    -- Client updaten
    sendCurrencyUpdate(player, data.Currency.Gold, amount, "AdminSet", amount - oldGems)
    
    return true
end

-------------------------------------------------
-- PUBLIC API - KOMBINIERTE OPERATIONEN
-------------------------------------------------

--[[
    Führt einen Kauf durch (entfernt Gold und/oder Gems)
    @param player: Der Spieler
    @param cost: { Gold = X, Gems = Y }
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details (optional)
    @return: success, errorMessage
]]
function CurrencyService.Purchase(player, cost, transactionType, source)
    -- Validierung
    local canAfford, affordError = CurrencyService.CanAfford(player, cost)
    if not canAfford then
        CurrencyService.Signals.TransactionFailed:Fire(player, affordError, transactionType)
        return false, affordError
    end
    
    local data = DataManager.GetData(player)
    if not data then
        return false, "Daten nicht geladen"
    end
    
    local goldCost = cost.Gold or 0
    local gemsCost = cost.Gems or 0
    
    -- Beide Währungen auf einmal abziehen
    local currentGold = data.Currency.Gold or 0
    local currentGems = data.Currency.Gems or 0
    local newGold = currentGold - goldCost
    local newGems = currentGems - gemsCost
    
    -- Werte setzen
    if goldCost > 0 then
        DataManager.SetValue(player, "Currency.Gold", newGold)
        DataManager.IncrementValue(player, "Stats.TotalGoldSpent", goldCost)
        logTransaction(player, "Gold", -goldCost, transactionType, source)
        CurrencyService.Signals.GoldChanged:Fire(player, currentGold, newGold, transactionType, source)
    end
    
    if gemsCost > 0 then
        DataManager.SetValue(player, "Currency.Gems", newGems)
        DataManager.IncrementValue(player, "Stats.TotalGemsSpent", gemsCost)
        logTransaction(player, "Gems", -gemsCost, transactionType, source)
        CurrencyService.Signals.GemsChanged:Fire(player, currentGems, newGems, transactionType, source)
    end
    
    -- Ein Client-Update für beide
    sendCurrencyUpdate(player, newGold, newGems, transactionType)
    
    return true, nil
end

--[[
    Gibt eine Belohnung (fügt Gold und/oder Gems hinzu)
    @param player: Der Spieler
    @param reward: { Gold = X, Gems = Y }
    @param transactionType: Typ der Transaktion
    @param source: Quelle/Details (optional)
    @return: actualReward { Gold = X, Gems = Y }
]]
function CurrencyService.GiveReward(player, reward, transactionType, source)
    local actualReward = {
        Gold = 0,
        Gems = 0,
    }
    
    local data = DataManager.GetData(player)
    if not data then
        return actualReward
    end
    
    local goldReward = reward.Gold or 0
    local gemsReward = reward.Gems or 0
    
    local currentGold = data.Currency.Gold or 0
    local currentGems = data.Currency.Gems or 0
    
    -- Gold hinzufügen
    if goldReward > 0 then
        local addableGold = CurrencyUtil.CalculateAddable(currentGold, goldReward, "Gold")
        if addableGold > 0 then
            local newGold = currentGold + addableGold
            DataManager.SetValue(player, "Currency.Gold", newGold)
            DataManager.IncrementValue(player, "Stats.TotalGoldEarned", addableGold)
            actualReward.Gold = addableGold
            logTransaction(player, "Gold", addableGold, transactionType, source)
            CurrencyService.Signals.GoldChanged:Fire(player, currentGold, newGold, transactionType, source)
            currentGold = newGold
        end
    end
    
    -- Gems hinzufügen
    if gemsReward > 0 then
        local addableGems = CurrencyUtil.CalculateAddable(currentGems, gemsReward, "Gems")
        if addableGems > 0 then
            local newGems = currentGems + addableGems
            DataManager.SetValue(player, "Currency.Gems", newGems)
            DataManager.IncrementValue(player, "Stats.TotalGemsEarned", addableGems)
            actualReward.Gems = addableGems
            logTransaction(player, "Gems", addableGems, transactionType, source)
            CurrencyService.Signals.GemsChanged:Fire(player, currentGems, newGems, transactionType, source)
            currentGems = newGems
        end
    end
    
    -- Client updaten
    if actualReward.Gold > 0 or actualReward.Gems > 0 then
        sendCurrencyUpdate(player, currentGold, currentGems, transactionType)
    end
    
    return actualReward
end

--[[
    Berechnet Kosten mit Prestige-Rabatt
    @param player: Der Spieler
    @param baseCost: { Gold = X, Gems = Y }
    @return: { Gold = X, Gems = Y } mit Rabatt
]]
function CurrencyService.CalculateCostWithDiscount(player, baseCost)
    local data = DataManager and DataManager.GetData(player)
    local prestigeLevel = data and data.Prestige and data.Prestige.Level or 0
    
    return CurrencyUtil.ApplyPrestigeDiscount(baseCost, prestigeLevel)
end

--[[
    Gibt formatierte Währungsstrings zurück
    @param player: Der Spieler
    @return: { Gold = "💰 1.5K", Gems = "💎 50" }
]]
function CurrencyService.GetFormattedCurrency(player)
    local currency = CurrencyService.GetCurrency(player)
    if not currency then
        return { Gold = "💰 0", Gems = "💎 0" }
    end
    
    return {
        Gold = CurrencyUtil.FormatGold(currency.Gold),
        Gems = CurrencyUtil.FormatGems(currency.Gems),
    }
end

return CurrencyService
