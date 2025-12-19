--[[
    ServerMain.lua
    Zentraler Server-Einstiegspunkt
    Pfad: ServerScriptService/Server/ServerMain
    
    Dieses Script:
    - Lädt alle Server-Module
    - Initialisiert in korrekter Reihenfolge
    - Verbindet Dependencies
    - Startet GameLoop
    
    WICHTIG: Dies ist das EINZIGE Server-Script das direkt läuft!
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("═══════════════════════════════════════════")
print("    🏰 DUNGEON TYCOON - SERVER START")
print("═══════════════════════════════════════════")

-------------------------------------------------
-- PFADE
-------------------------------------------------
local ServerPath = ServerScriptService:WaitForChild("Server")
local CorePath = ServerPath:WaitForChild("Core")
local ServicesPath = ServerPath:WaitForChild("Services")
local SystemsPath = ServerPath:WaitForChild("Systems")

local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")
local RemotesPath = SharedPath:WaitForChild("Remotes")

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local DEBUG_MODE = true
local INIT_TIMEOUT = 30  -- Sekunden

local function log(category, message)
    if DEBUG_MODE then
        print(string.format("[%s] %s", category, message))
    end
end

local function logError(category, message)
    warn(string.format("[%s] ERROR: %s", category, message))
end

local function logSuccess(message)
    print("✅ " .. message)
end

-------------------------------------------------
-- MODUL-REFERENZEN
-------------------------------------------------
local Modules = {
    -- Config
    GameConfig = nil,
    TrapConfig = nil,
    MonsterConfig = nil,
    HeroConfig = nil,
    RoomConfig = nil,
    
    -- Shared Utilities
    DataTemplate = nil,
    CurrencyUtil = nil,
    SignalUtil = nil,
    RemoteIndex = nil,
    
    -- Core
    DataManager = nil,
    PlayerManager = nil,
    GameLoop = nil,
    
    -- Services
    CurrencyService = nil,
    ShopService = nil,
    
    -- Systems
    DungeonSystem = nil,
    RaidSystem = nil,
    HeroSystem = nil,
    CombatSystem = nil,
    RewardSystem = nil,
}

-------------------------------------------------
-- SAFE REQUIRE
-------------------------------------------------
local function safeRequire(moduleInstance, moduleName)
    local success, result = pcall(function()
        return require(moduleInstance)
    end)
    
    if success then
        log("Loader", "Geladen: " .. moduleName)
        return result
    else
        logError("Loader", "Fehler beim Laden von " .. moduleName .. ": " .. tostring(result))
        return nil
    end
end

-------------------------------------------------
-- PHASE 1: SHARED MODULES LADEN
-------------------------------------------------
local function loadSharedModules()
    log("Phase 1", "Lade Shared Modules...")
    
    -- Configs
    Modules.GameConfig = safeRequire(ConfigPath:WaitForChild("GameConfig"), "GameConfig")
    Modules.TrapConfig = safeRequire(ConfigPath:WaitForChild("TrapConfig"), "TrapConfig")
    Modules.MonsterConfig = safeRequire(ConfigPath:WaitForChild("MonsterConfig"), "MonsterConfig")
    Modules.HeroConfig = safeRequire(ConfigPath:WaitForChild("HeroConfig"), "HeroConfig")
    Modules.RoomConfig = safeRequire(ConfigPath:WaitForChild("RoomConfig"), "RoomConfig")
    
    -- Utilities
    Modules.DataTemplate = safeRequire(ModulesPath:WaitForChild("DataTemplate"), "DataTemplate")
    Modules.CurrencyUtil = safeRequire(ModulesPath:WaitForChild("CurrencyUtil"), "CurrencyUtil")
    Modules.SignalUtil = safeRequire(ModulesPath:WaitForChild("SignalUtil"), "SignalUtil")
    Modules.RemoteIndex = safeRequire(RemotesPath:WaitForChild("RemoteIndex"), "RemoteIndex")
    
    -- Validate critical modules
    if not Modules.GameConfig or not Modules.RemoteIndex then
        error("Kritische Shared Modules konnten nicht geladen werden!")
    end
    
    logSuccess("Phase 1 abgeschlossen: Shared Modules geladen")
end

-------------------------------------------------
-- PHASE 2: CORE MODULES LADEN
-------------------------------------------------
local function loadCoreModules()
    log("Phase 2", "Lade Core Modules...")
    
    Modules.DataManager = safeRequire(CorePath:WaitForChild("DataManager"), "DataManager")
    Modules.PlayerManager = safeRequire(CorePath:WaitForChild("PlayerManager"), "PlayerManager")
    Modules.GameLoop = safeRequire(CorePath:WaitForChild("GameLoop"), "GameLoop")
    
    if not Modules.DataManager then
        error("DataManager konnte nicht geladen werden!")
    end
    
    logSuccess("Phase 2 abgeschlossen: Core Modules geladen")
end

-------------------------------------------------
-- PHASE 3: SERVICES LADEN
-------------------------------------------------
local function loadServices()
    log("Phase 3", "Lade Services...")
    
    Modules.CurrencyService = safeRequire(ServicesPath:WaitForChild("CurrencyService"), "CurrencyService")
    Modules.ShopService = safeRequire(ServicesPath:WaitForChild("ShopService"), "ShopService")
    
    logSuccess("Phase 3 abgeschlossen: Services geladen")
end

-------------------------------------------------
-- PHASE 4: SYSTEMS LADEN
-------------------------------------------------
local function loadSystems()
    log("Phase 4", "Lade Systems...")
    
    Modules.DungeonSystem = safeRequire(SystemsPath:WaitForChild("DungeonSystem"), "DungeonSystem")
    Modules.RaidSystem = safeRequire(SystemsPath:WaitForChild("RaidSystem"), "RaidSystem")
    Modules.HeroSystem = safeRequire(SystemsPath:WaitForChild("HeroSystem"), "HeroSystem")
    Modules.CombatSystem = safeRequire(SystemsPath:WaitForChild("CombatSystem"), "CombatSystem")
    Modules.RewardSystem = safeRequire(SystemsPath:WaitForChild("RewardSystem"), "RewardSystem")
    
    logSuccess("Phase 4 abgeschlossen: Systems geladen")
end

-------------------------------------------------
-- PHASE 5: INITIALISIERUNG
-------------------------------------------------
local function initializeModules()
    log("Phase 5", "Initialisiere Module...")
    
    -- DataManager initialisieren (keine Dependencies)
    if Modules.DataManager and Modules.DataManager.Initialize then
        Modules.DataManager.Initialize()
        log("Init", "DataManager initialisiert")
    end
    
    -- PlayerManager initialisieren (braucht DataManager)
    if Modules.PlayerManager and Modules.PlayerManager.Initialize then
        Modules.PlayerManager.Initialize(Modules.DataManager)
        log("Init", "PlayerManager initialisiert")
    end
    
    -- CurrencyService initialisieren (braucht DataManager)
    if Modules.CurrencyService and Modules.CurrencyService.Initialize then
        Modules.CurrencyService.Initialize(Modules.DataManager)
        log("Init", "CurrencyService initialisiert")
    end
    
    -- ShopService initialisieren (braucht DataManager, CurrencyService)
    if Modules.ShopService and Modules.ShopService.Initialize then
        Modules.ShopService.Initialize(Modules.DataManager, Modules.CurrencyService)
        log("Init", "ShopService initialisiert")
    end
    
    -- DungeonSystem initialisieren (braucht DataManager, CurrencyService)
    if Modules.DungeonSystem and Modules.DungeonSystem.Initialize then
        Modules.DungeonSystem.Initialize(Modules.DataManager, Modules.CurrencyService)
        log("Init", "DungeonSystem initialisiert")
    end
    
    -- HeroSystem initialisieren (braucht DataManager, CurrencyService)
    if Modules.HeroSystem and Modules.HeroSystem.Initialize then
        Modules.HeroSystem.Initialize(Modules.DataManager, Modules.CurrencyService)
        log("Init", "HeroSystem initialisiert")
    end
    
    -- CombatSystem initialisieren (keine Dependencies)
    if Modules.CombatSystem and Modules.CombatSystem.Initialize then
        Modules.CombatSystem.Initialize()
        log("Init", "CombatSystem initialisiert")
    end
    
    -- RewardSystem initialisieren (braucht DataManager, PlayerManager, CurrencyService)
    if Modules.RewardSystem and Modules.RewardSystem.Initialize then
        Modules.RewardSystem.Initialize(
            Modules.DataManager,
            Modules.PlayerManager,
            Modules.CurrencyService
        )
        log("Init", "RewardSystem initialisiert")
    end
    
    -- RaidSystem initialisieren (braucht alles)
    if Modules.RaidSystem and Modules.RaidSystem.Initialize then
        Modules.RaidSystem.Initialize(
            Modules.DataManager,
            Modules.CurrencyService,
            Modules.HeroSystem,
            Modules.DungeonSystem,
            Modules.CombatSystem,
            Modules.RewardSystem
        )
        log("Init", "RaidSystem initialisiert")
    end
    
    -- GameLoop initialisieren und starten (braucht DataManager, PlayerManager)
    if Modules.GameLoop and Modules.GameLoop.Initialize then
        Modules.GameLoop.Initialize(Modules.DataManager, Modules.PlayerManager)
        Modules.GameLoop.Start()
        log("Init", "GameLoop initialisiert und gestartet")
    end
    
    logSuccess("Phase 5 abgeschlossen: Alle Module initialisiert")
end

-------------------------------------------------
-- PHASE 6: REMOTE EVENTS VERBINDEN
-------------------------------------------------
local function setupRemoteEvents()
    log("Phase 6", "Verbinde Remote Events...")
    
    local RemoteIndex = Modules.RemoteIndex
    if not RemoteIndex then
        logError("Remotes", "RemoteIndex nicht verfügbar!")
        return
    end
    
    -------------------------------------------
    -- CURRENCY REMOTES
    -------------------------------------------
    
    -- Currency anfragen
    RemoteIndex.OnServerInvoke("Currency_Request", function(player)
        if not Modules.CurrencyService then
            return { Success = false, Error = "Service nicht verfügbar" }
        end
        
        local gold = Modules.CurrencyService.GetGold(player)
        local gems = Modules.CurrencyService.GetGems(player)
        
        return {
            Success = true,
            Gold = gold,
            Gems = gems,
        }
    end)
    
    -- Passives Einkommen abholen
    RemoteIndex.OnServerInvoke("Currency_CollectPassive", function(player)
        if not Modules.CurrencyService then
            return { Success = false, Error = "Service nicht verfügbar" }
        end
        
        local amount = Modules.CurrencyService.CollectPassiveIncome(player)
        local newTotal = Modules.CurrencyService.GetGold(player)
        
        return {
            Success = amount > 0,
            Amount = amount,
            NewTotal = newTotal,
        }
    end)
    
    -------------------------------------------
    -- SHOP REMOTES
    -------------------------------------------
    
    -- Unlocked Items anfragen
    RemoteIndex.OnServerInvoke("Shop_GetUnlocked", function(player)
        if not Modules.ShopService then
            return { Success = false, Error = "Service nicht verfügbar" }
        end
        
        local unlocked = Modules.ShopService.GetUnlockedItems(player)
        
        return {
            Success = true,
            Unlocked = unlocked,
        }
    end)
    
    -- Item freischalten
    RemoteIndex.OnServerInvoke("Shop_Unlock", function(player, category, itemId)
        if not Modules.ShopService then
            return { Success = false, Error = "Service nicht verfügbar" }
        end
        
        local success, error = Modules.ShopService.UnlockItem(player, category, itemId)
        
        if success then
            return {
                Success = true,
                NewGold = Modules.CurrencyService.GetGold(player),
                NewGems = Modules.CurrencyService.GetGems(player),
            }
        else
            return { Success = false, Error = error }
        end
    end)
    
    -------------------------------------------
    -- DUNGEON REMOTES
    -------------------------------------------
    
    -- Dungeon-Daten anfragen
    RemoteIndex.OnServerInvoke("Dungeon_GetData", function(player)
        if not Modules.DungeonSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local dungeonData = Modules.DungeonSystem.GetDungeonData(player)
        
        return {
            Success = true,
            Dungeon = dungeonData,
        }
    end)
    
    -- Raum hinzufügen
    RemoteIndex.OnServerInvoke("Dungeon_AddRoom", function(player, roomId)
        if not Modules.DungeonSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local success, error = Modules.DungeonSystem.AddRoom(player, roomId)
        
        return {
            Success = success,
            Error = error,
        }
    end)
    
    -- Falle platzieren
    RemoteIndex.OnServerInvoke("Dungeon_PlaceTrap", function(player, roomIndex, slotIndex, trapId)
        if not Modules.DungeonSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local success, error = Modules.DungeonSystem.PlaceTrap(player, roomIndex, slotIndex, trapId)
        
        return {
            Success = success,
            Error = error,
        }
    end)
    
    -- Monster platzieren
    RemoteIndex.OnServerInvoke("Dungeon_PlaceMonster", function(player, roomIndex, slotIndex, monsterId)
        if not Modules.DungeonSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local success, error = Modules.DungeonSystem.PlaceMonster(player, roomIndex, slotIndex, monsterId)
        
        return {
            Success = success,
            Error = error,
        }
    end)
    
    -------------------------------------------
    -- HERO REMOTES
    -------------------------------------------
    
    -- Alle Helden anfragen
    RemoteIndex.OnServerInvoke("Hero_GetAll", function(player)
        if not Modules.HeroSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local heroes = Modules.HeroSystem.GetAllHeroes(player)
        local team = Modules.HeroSystem.GetTeam(player)
        
        return {
            Success = true,
            Heroes = heroes,
            Team = team,
        }
    end)
    
    -- Held rekrutieren
    RemoteIndex.OnServerInvoke("Hero_Recruit", function(player, currency)
        if not Modules.HeroSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local hero, error = Modules.HeroSystem.RecruitHero(player, currency)
        
        if hero then
            return {
                Success = true,
                Hero = hero,
            }
        else
            return { Success = false, Error = error }
        end
    end)
    
    -- Held ins Team
    RemoteIndex.OnServerInvoke("Hero_AddToTeam", function(player, instanceId)
        if not Modules.HeroSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local success, error = Modules.HeroSystem.AddToTeam(player, instanceId)
        
        return {
            Success = success,
            Error = error,
        }
    end)
    
    -- Held aus Team entfernen
    RemoteIndex.OnServerInvoke("Hero_RemoveFromTeam", function(player, instanceId)
        if not Modules.HeroSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local success, error = Modules.HeroSystem.RemoveFromTeam(player, instanceId)
        
        return {
            Success = success,
            Error = error,
        }
    end)
    
    -- Held entlassen
    RemoteIndex.OnServerInvoke("Hero_Dismiss", function(player, instanceId)
        if not Modules.HeroSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local success, error = Modules.HeroSystem.DismissHero(player, instanceId)
        
        return {
            Success = success,
            Error = error,
        }
    end)
    
    -------------------------------------------
    -- RAID REMOTES
    -------------------------------------------
    
    -- Raid-Status anfragen
    RemoteIndex.OnServerInvoke("Raid_GetStatus", function(player)
        if not Modules.RaidSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local canRaid, cooldown = Modules.RaidSystem.CanStartRaid(player)
        local team = Modules.HeroSystem and Modules.HeroSystem.GetTeamData(player) or {}
        
        return {
            Success = true,
            CanRaid = canRaid,
            Cooldown = cooldown,
            Team = team,
        }
    end)
    
    -- Gegner suchen
    RemoteIndex.OnServerInvoke("Raid_FindTarget", function(player)
        if not Modules.RaidSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local target, error = Modules.RaidSystem.FindTarget(player)
        
        if target then
            return {
                Success = true,
                Target = target,
            }
        else
            return { Success = false, Error = error }
        end
    end)
    
    -- Raid starten
    RemoteIndex.OnServerInvoke("Raid_Start", function(player, targetId)
        if not Modules.RaidSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local raidId, totalRooms, error = Modules.RaidSystem.StartRaid(player, targetId)
        
        if raidId then
            return {
                Success = true,
                RaidId = raidId,
                TotalRooms = totalRooms,
            }
        else
            return { Success = false, Error = error }
        end
    end)
    
    -- Raid fliehen
    RemoteIndex.OnServerInvoke("Raid_Flee", function(player, raidId)
        if not Modules.RaidSystem then
            return { Success = false, Error = "System nicht verfügbar" }
        end
        
        local result = Modules.RaidSystem.FleeRaid(player, raidId)
        
        return result
    end)
    
    -------------------------------------------
    -- PRESTIGE REMOTES
    -------------------------------------------
    
    -- Prestige-Status anfragen
    RemoteIndex.OnServerInvoke("Prestige_GetStatus", function(player)
        local data = Modules.DataManager and Modules.DataManager.GetData(player)
        if not data then
            return { Success = false, Error = "Daten nicht verfügbar" }
        end
        
        local prestigeLevel = data.Prestige.Level or 0
        local dungeonLevel = data.Dungeon.Level or 1
        local minLevel = Modules.GameConfig.Prestige.MinLevel or 25
        
        return {
            Success = true,
            PrestigeLevel = prestigeLevel,
            DungeonLevel = dungeonLevel,
            CanPrestige = dungeonLevel >= minLevel,
            TotalBonus = prestigeLevel * (Modules.GameConfig.Prestige.BonusPerPrestige or 0.05) * 100,
        }
    end)
    
    -- Prestige ausführen
    RemoteIndex.OnServerInvoke("Prestige_Execute", function(player)
        local data = Modules.DataManager and Modules.DataManager.GetData(player)
        if not data then
            return { Success = false, Error = "Daten nicht verfügbar" }
        end
        
        local dungeonLevel = data.Dungeon.Level or 1
        local minLevel = Modules.GameConfig.Prestige.MinLevel or 25
        local maxPrestige = Modules.GameConfig.Prestige.MaxPrestige or 100
        local currentPrestige = data.Prestige.Level or 0
        
        -- Prüfungen
        if dungeonLevel < minLevel then
            return { Success = false, Error = "Dungeon-Level zu niedrig" }
        end
        
        if currentPrestige >= maxPrestige then
            return { Success = false, Error = "Maximales Prestige erreicht" }
        end
        
        -- Prestige ausführen
        local newPrestigeLevel = currentPrestige + 1
        
        -- Prestige erhöhen
        Modules.DataManager.SetValue(player, "Prestige.Level", newPrestigeLevel)
        Modules.DataManager.SetValue(player, "Prestige.LastPrestigeAt", os.time())
        
        -- Dungeon zurücksetzen
        Modules.DataManager.SetValue(player, "Dungeon.Level", 1)
        Modules.DataManager.SetValue(player, "Dungeon.XP", 0)
        Modules.DataManager.SetValue(player, "Dungeon.Rooms", {})
        
        -- Gold zurücksetzen (Gems behalten)
        Modules.DataManager.SetValue(player, "Currency.Gold", Modules.GameConfig.Currency.StartGold or 100)
        
        -- Stats tracken
        local totalPrestiges = (data.Progress.TotalPrestiges or 0) + 1
        Modules.DataManager.SetValue(player, "Progress.TotalPrestiges", totalPrestiges)
        
        -- Achievement checken
        if Modules.RewardSystem then
            Modules.RewardSystem.CheckAchievementProgress(player, "PrestigeLevel", newPrestigeLevel)
            Modules.RewardSystem.GrantLevelUpReward(player, 1) -- Starter-Bonus nach Prestige
        end
        
        -- Client benachrichtigen
        RemoteIndex.FireClient("Prestige_Update", player, {
            PrestigeLevel = newPrestigeLevel,
            DungeonLevel = 1,
            CanPrestige = false,
        })
        
        RemoteIndex.FireClient("Currency_Update", player, {
            Gold = Modules.GameConfig.Currency.StartGold or 100,
            Gems = data.Currency.Gems,
        })
        
        return {
            Success = true,
            NewPrestigeLevel = newPrestigeLevel,
        }
    end)
    
    -------------------------------------------
    -- PLAYER SETTINGS
    -------------------------------------------
    
    RemoteIndex.OnServerInvoke("Player_SettingsUpdate", function(player, settingKey, value)
        if not Modules.DataManager then
            return { Success = false }
        end
        
        -- Validiere Setting-Key
        local validSettings = {
            "MusicEnabled", "SFXEnabled", "NotificationsEnabled",
            "AutoCollect", "ShowDamageNumbers"
        }
        
        local isValid = false
        for _, valid in ipairs(validSettings) do
            if settingKey == valid then
                isValid = true
                break
            end
        end
        
        if not isValid then
            return { Success = false, Error = "Ungültige Einstellung" }
        end
        
        Modules.DataManager.SetValue(player, "Settings." .. settingKey, value)
        
        return { Success = true }
    end)
    
    logSuccess("Phase 6 abgeschlossen: Remote Events verbunden")
end

-------------------------------------------------
-- PHASE 7: PLAYER HANDLING
-------------------------------------------------
local function setupPlayerHandling()
    log("Phase 7", "Richte Player-Handling ein...")
    
    -- Bereits verbundene Spieler verarbeiten
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if Modules.DataManager then
                Modules.DataManager.LoadPlayerData(player)
            end
        end)
    end
    
    -- PlayerAdded wird bereits vom DataManager/PlayerManager gehandelt
    -- Hier nur zusätzliche Logik falls nötig
    
    Players.PlayerAdded:Connect(function(player)
        log("Player", player.Name .. " ist beigetreten")
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        log("Player", player.Name .. " hat verlassen")
    end)
    
    logSuccess("Phase 7 abgeschlossen: Player-Handling eingerichtet")
end

-------------------------------------------------
-- PHASE 8: SIGNAL VERBINDUNGEN
-------------------------------------------------
local function setupSignalConnections()
    log("Phase 8", "Verbinde Signals...")
    
    -- PlayerManager Signals
    if Modules.PlayerManager and Modules.PlayerManager.Signals then
        Modules.PlayerManager.Signals.PlayerReady:Connect(function(player)
            log("Signal", player.Name .. " ist bereit")
            
            -- Willkommens-Daten senden
            if Modules.CurrencyService then
                local gold = Modules.CurrencyService.GetGold(player)
                local gems = Modules.CurrencyService.GetGems(player)
                
                Modules.RemoteIndex.FireClient("Currency_Update", player, {
                    Gold = gold,
                    Gems = gems,
                })
            end
            
            if Modules.DungeonSystem then
                local dungeonData = Modules.DungeonSystem.GetDungeonData(player)
                
                Modules.RemoteIndex.FireClient("Dungeon_Update", player, {
                    Level = dungeonData.Level,
                    Rooms = dungeonData.Rooms,
                })
            end
        end)
    end
    
    -- CurrencyService Signals
    if Modules.CurrencyService and Modules.CurrencyService.Signals then
        Modules.CurrencyService.Signals.CurrencyChanged:Connect(function(player, currencyType, newAmount, delta)
            Modules.RemoteIndex.FireClient("Currency_Update", player, {
                [currencyType] = newAmount,
            })
        end)
    end
    
    -- DungeonSystem Signals
    if Modules.DungeonSystem and Modules.DungeonSystem.Signals then
        Modules.DungeonSystem.Signals.LevelUp:Connect(function(player, newLevel)
            Modules.RemoteIndex.FireClient("Dungeon_Update", player, {
                Level = newLevel,
                LevelUp = true,
            })
            
            -- Level-Up Belohnung
            if Modules.RewardSystem then
                Modules.RewardSystem.GrantLevelUpReward(player, newLevel)
            end
        end)
    end
    
    -- RaidSystem Signals
    if Modules.RaidSystem and Modules.RaidSystem.Signals then
        Modules.RaidSystem.Signals.RaidStarted:Connect(function(player, raidId)
            log("Signal", "Raid gestartet: " .. raidId)
        end)
        
        Modules.RaidSystem.Signals.RaidEnded:Connect(function(player, raidId, result)
            log("Signal", "Raid beendet: " .. raidId .. " - " .. result.Status)
            
            -- Belohnungen geben
            if Modules.RewardSystem then
                Modules.RewardSystem.GrantRaidReward(player, result)
            end
        end)
    end
    
    -- RewardSystem Signals
    if Modules.RewardSystem and Modules.RewardSystem.Signals then
        Modules.RewardSystem.Signals.AchievementUnlocked:Connect(function(player, achievementId, achievement)
            log("Signal", player.Name .. " hat Achievement freigeschaltet: " .. achievement.Name)
        end)
    end
    
    logSuccess("Phase 8 abgeschlossen: Signals verbunden")
end

-------------------------------------------------
-- HAUPTINITIALISIERUNG
-------------------------------------------------
local function main()
    local startTime = os.clock()
    
    local success, error = pcall(function()
        -- Phase 1: Shared Modules
        loadSharedModules()
        
        -- Phase 2: Core Modules
        loadCoreModules()
        
        -- Phase 3: Services
        loadServices()
        
        -- Phase 4: Systems
        loadSystems()
        
        -- Phase 5: Initialisierung
        initializeModules()
        
        -- Phase 6: Remote Events
        setupRemoteEvents()
        
        -- Phase 7: Player Handling
        setupPlayerHandling()
        
        -- Phase 8: Signal Verbindungen
        setupSignalConnections()
    end)
    
    local endTime = os.clock()
    local duration = string.format("%.2f", endTime - startTime)
    
    if success then
        print("═══════════════════════════════════════════")
        print("  ✅ SERVER ERFOLGREICH GESTARTET")
        print("  ⏱️  Dauer: " .. duration .. " Sekunden")
        print("  📊 Module geladen: " .. tostring(#Players:GetPlayers()) .. " Spieler online")
        print("═══════════════════════════════════════════")
    else
        print("═══════════════════════════════════════════")
        print("  ❌ SERVER START FEHLGESCHLAGEN")
        print("  Error: " .. tostring(error))
        print("═══════════════════════════════════════════")
    end
end

-- Server starten
main()

-------------------------------------------------
-- GLOBAL ACCESS (für Debugging)
-------------------------------------------------
if DEBUG_MODE then
    _G.DungeonTycoon = {
        Modules = Modules,
        GetModule = function(name)
            return Modules[name]
        end,
    }
end

return Modules
