--[[
    ClientMain.lua
    Zentraler Client-Einstiegspunkt
    Pfad: StarterPlayer/StarterPlayerScripts/Client/ClientMain
    
    Dieses Script:
    - Lädt alle Client-Module
    - Initialisiert Controller in korrekter Reihenfolge
    - Verbindet mit Server
    - Startet UI
    
    WICHTIG: Dies ist das EINZIGE Client-Script das direkt läuft!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

print("═══════════════════════════════════════════")
print("    🏰 DUNGEON TYCOON - CLIENT START")
print("═══════════════════════════════════════════")

-------------------------------------------------
-- PFADE
-------------------------------------------------
local ClientPath = script.Parent
local ControllersPath = ClientPath:WaitForChild("Controllers")

local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")
local RemotesPath = SharedPath:WaitForChild("Remotes")

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local DEBUG_MODE = true
local INIT_TIMEOUT = 30
local PRELOAD_ASSETS = true

local function log(category, message)
    if DEBUG_MODE then
        print(string.format("[Client:%s] %s", category, message))
    end
end

local function logError(category, message)
    warn(string.format("[Client:%s] ERROR: %s", category, message))
end

local function logSuccess(message)
    print("✅ " .. message)
end

-------------------------------------------------
-- MODUL-REFERENZEN
-------------------------------------------------
local Modules = {
    -- Shared Config
    GameConfig = nil,
    TrapConfig = nil,
    MonsterConfig = nil,
    HeroConfig = nil,
    RoomConfig = nil,
    
    -- Shared Utilities
    CurrencyUtil = nil,
    SignalUtil = nil,
    RemoteIndex = nil,
    
    -- Controllers
    DataController = nil,
    AudioController = nil,
    CameraController = nil,
    UIController = nil,
    InputController = nil,
}

-------------------------------------------------
-- UI SCREEN REFERENZEN
-------------------------------------------------
local Screens = {
    DungeonScreen = nil,
    ShopScreen = nil,
    HeroesScreen = nil,
    RaidScreen = nil,
    PrestigeScreen = nil,
}

-------------------------------------------------
-- CLIENT STATE
-------------------------------------------------
local ClientState = {
    IsInitialized = false,
    IsConnected = false,
    LoadingProgress = 0,
    LoadingStatus = "Starte...",
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
-- LOADING SCREEN UPDATE
-------------------------------------------------
local function updateLoadingScreen(progress, status)
    ClientState.LoadingProgress = progress
    ClientState.LoadingStatus = status
    
    -- UI Loading Screen updaten falls vorhanden
    local mainUI = PlayerGui:FindFirstChild("MainUI")
    if mainUI then
        local loadingScreen = mainUI:FindFirstChild("LoadingScreen")
        if loadingScreen then
            local loadingText = loadingScreen:FindFirstChild("LoadingText")
            if loadingText then
                loadingText.Text = status
            end
        end
    end
end

-------------------------------------------------
-- PHASE 1: SHARED MODULES LADEN
-------------------------------------------------
local function loadSharedModules()
    log("Phase 1", "Lade Shared Modules...")
    updateLoadingScreen(0.1, "Lade Konfigurationen...")
    
    -- Configs
    Modules.GameConfig = safeRequire(ConfigPath:WaitForChild("GameConfig"), "GameConfig")
    Modules.TrapConfig = safeRequire(ConfigPath:WaitForChild("TrapConfig"), "TrapConfig")
    Modules.MonsterConfig = safeRequire(ConfigPath:WaitForChild("MonsterConfig"), "MonsterConfig")
    Modules.HeroConfig = safeRequire(ConfigPath:WaitForChild("HeroConfig"), "HeroConfig")
    Modules.RoomConfig = safeRequire(ConfigPath:WaitForChild("RoomConfig"), "RoomConfig")
    
    updateLoadingScreen(0.15, "Lade Utilities...")
    
    -- Utilities
    Modules.CurrencyUtil = safeRequire(ModulesPath:WaitForChild("CurrencyUtil"), "CurrencyUtil")
    Modules.SignalUtil = safeRequire(ModulesPath:WaitForChild("SignalUtil"), "SignalUtil")
    Modules.RemoteIndex = safeRequire(RemotesPath:WaitForChild("RemoteIndex"), "RemoteIndex")
    
    -- Validierung
    if not Modules.GameConfig or not Modules.RemoteIndex then
        error("Kritische Shared Modules konnten nicht geladen werden!")
    end
    
    logSuccess("Phase 1 abgeschlossen: Shared Modules geladen")
end

-------------------------------------------------
-- PHASE 2: CONTROLLERS LADEN
-------------------------------------------------
local function loadControllers()
    log("Phase 2", "Lade Controllers...")
    updateLoadingScreen(0.2, "Lade Controller...")
    
    -- DataController (keine UI-Abhängigkeit)
    Modules.DataController = safeRequire(ControllersPath:WaitForChild("DataController"), "DataController")
    
    updateLoadingScreen(0.25, "Lade Audio-System...")
    
    -- AudioController (keine Abhängigkeit)
    Modules.AudioController = safeRequire(ControllersPath:WaitForChild("AudioController"), "AudioController")
    
    updateLoadingScreen(0.3, "Lade Kamera-System...")
    
    -- CameraController (keine Abhängigkeit)
    Modules.CameraController = safeRequire(ControllersPath:WaitForChild("CameraController"), "CameraController")
    
    updateLoadingScreen(0.35, "Lade UI-System...")
    
    -- UIController (braucht DataController)
    Modules.UIController = safeRequire(ControllersPath:WaitForChild("UIController"), "UIController")
    
    updateLoadingScreen(0.4, "Lade Input-System...")
    
    -- InputController (braucht UIController, CameraController)
    Modules.InputController = safeRequire(ControllersPath:WaitForChild("InputController"), "InputController")
    
    logSuccess("Phase 2 abgeschlossen: Controllers geladen")
end

-------------------------------------------------
-- PHASE 3: CONTROLLER INITIALISIERUNG
-------------------------------------------------
local function initializeControllers()
    log("Phase 3", "Initialisiere Controllers...")
    updateLoadingScreen(0.45, "Initialisiere Data...")
    
    -- DataController initialisieren (erste Priorität)
    if Modules.DataController and Modules.DataController.Initialize then
        Modules.DataController.Initialize(Modules.RemoteIndex)
        log("Init", "DataController initialisiert")
    end
    
    updateLoadingScreen(0.5, "Initialisiere Audio...")
    
    -- AudioController initialisieren
    if Modules.AudioController and Modules.AudioController.Initialize then
        Modules.AudioController.Initialize()
        log("Init", "AudioController initialisiert")
    end
    
    updateLoadingScreen(0.55, "Initialisiere Kamera...")
    
    -- CameraController initialisieren
    if Modules.CameraController and Modules.CameraController.Initialize then
        Modules.CameraController.Initialize()
        Modules.CameraController.SetMode("Overview")
        log("Init", "CameraController initialisiert")
    end
    
    updateLoadingScreen(0.6, "Initialisiere UI...")
    
    -- UIController initialisieren
    if Modules.UIController and Modules.UIController.Initialize then
        Modules.UIController.Initialize(Modules.DataController)
        log("Init", "UIController initialisiert")
    end
    
    updateLoadingScreen(0.65, "Initialisiere Input...")
    
    -- InputController initialisieren
    if Modules.InputController and Modules.InputController.Initialize then
        Modules.InputController.Initialize(Modules.UIController, Modules.CameraController)
        log("Init", "InputController initialisiert")
    end
    
    logSuccess("Phase 3 abgeschlossen: Controllers initialisiert")
end

-------------------------------------------------
-- PHASE 4: UI SCREENS LADEN
-------------------------------------------------
local function loadScreens()
    log("Phase 4", "Lade UI Screens...")
    updateLoadingScreen(0.7, "Lade Dungeon-Screen...")
    
    -- Warten bis MainUI existiert
    local mainUI = PlayerGui:WaitForChild("MainUI", 10)
    if not mainUI then
        logError("Screens", "MainUI nicht gefunden!")
        return
    end
    
    -- Screens Container
    local screensPath = mainUI:FindFirstChild("Screens")
    if not screensPath then
        logError("Screens", "Screens Container nicht gefunden!")
        return
    end
    
    -- Screen Module laden (falls als ModuleScripts implementiert)
    -- Diese werden bereits durch UISetup.lua erstellt
    -- Hier laden wir nur die Logik-Module
    
    local screenModulesPath = PlayerGui:FindFirstChild("MainUI")
    if screenModulesPath then
        local screensFolder = screenModulesPath:FindFirstChild("Screens")
        
        -- DungeonScreen
        local dungeonModule = screensFolder and screensFolder:FindFirstChild("DungeonScreen")
        if dungeonModule and dungeonModule:IsA("ModuleScript") then
            Screens.DungeonScreen = safeRequire(dungeonModule, "DungeonScreen")
        end
        
        updateLoadingScreen(0.75, "Lade Shop-Screen...")
        
        -- ShopScreen
        local shopModule = screensFolder and screensFolder:FindFirstChild("ShopScreen")
        if shopModule and shopModule:IsA("ModuleScript") then
            Screens.ShopScreen = safeRequire(shopModule, "ShopScreen")
        end
        
        updateLoadingScreen(0.8, "Lade Helden-Screen...")
        
        -- HeroesScreen
        local heroesModule = screensFolder and screensFolder:FindFirstChild("HeroesScreen")
        if heroesModule and heroesModule:IsA("ModuleScript") then
            Screens.HeroesScreen = safeRequire(heroesModule, "HeroesScreen")
        end
        
        updateLoadingScreen(0.85, "Lade Raid-Screen...")
        
        -- RaidScreen
        local raidModule = screensFolder and screensFolder:FindFirstChild("RaidScreen")
        if raidModule and raidModule:IsA("ModuleScript") then
            Screens.RaidScreen = safeRequire(raidModule, "RaidScreen")
        end
        
        updateLoadingScreen(0.9, "Lade Prestige-Screen...")
        
        -- PrestigeScreen
        local prestigeModule = screensFolder and screensFolder:FindFirstChild("PrestigeScreen")
        if prestigeModule and prestigeModule:IsA("ModuleScript") then
            Screens.PrestigeScreen = safeRequire(prestigeModule, "PrestigeScreen")
        end
    end
    
    logSuccess("Phase 4 abgeschlossen: UI Screens geladen")
end

-------------------------------------------------
-- PHASE 5: SERVER-VERBINDUNG
-------------------------------------------------
local function connectToServer()
    log("Phase 5", "Verbinde mit Server...")
    updateLoadingScreen(0.92, "Verbinde mit Server...")
    
    local RemoteIndex = Modules.RemoteIndex
    if not RemoteIndex then
        logError("Server", "RemoteIndex nicht verfügbar!")
        return false
    end
    
    -- Initiale Daten vom Server laden
    local success = pcall(function()
        -- Currency laden
        local currencyResult = RemoteIndex.Invoke("Currency_Request")
        if currencyResult and currencyResult.Success then
            if Modules.DataController then
                Modules.DataController.SetCurrency("Gold", currencyResult.Gold)
                Modules.DataController.SetCurrency("Gems", currencyResult.Gems)
            end
            log("Server", "Currency geladen: " .. currencyResult.Gold .. " Gold, " .. currencyResult.Gems .. " Gems")
        end
        
        -- Dungeon-Daten laden
        local dungeonResult = RemoteIndex.Invoke("Dungeon_GetData")
        if dungeonResult and dungeonResult.Success then
            if Modules.DataController then
                Modules.DataController.SetDungeonData(dungeonResult.Dungeon)
            end
            log("Server", "Dungeon-Daten geladen")
        end
        
        -- Helden laden
        local heroResult = RemoteIndex.Invoke("Hero_GetAll")
        if heroResult and heroResult.Success then
            if Modules.DataController then
                Modules.DataController.SetHeroData(heroResult.Heroes, heroResult.Team)
            end
            log("Server", "Helden-Daten geladen")
        end
        
        -- Prestige-Status laden
        local prestigeResult = RemoteIndex.Invoke("Prestige_GetStatus")
        if prestigeResult and prestigeResult.Success then
            if Modules.DataController then
                Modules.DataController.SetPrestigeData({
                    Level = prestigeResult.PrestigeLevel,
                    TotalBonus = prestigeResult.TotalBonus,
                    CanPrestige = prestigeResult.CanPrestige,
                })
            end
            log("Server", "Prestige-Daten geladen")
        end
    end)
    
    if success then
        ClientState.IsConnected = true
        logSuccess("Phase 5 abgeschlossen: Server-Verbindung hergestellt")
        return true
    else
        logError("Server", "Verbindung fehlgeschlagen")
        return false
    end
end

-------------------------------------------------
-- PHASE 6: SIGNAL VERBINDUNGEN
-------------------------------------------------
local function setupSignalConnections()
    log("Phase 6", "Verbinde Signals...")
    updateLoadingScreen(0.95, "Verbinde Events...")
    
    local RemoteIndex = Modules.RemoteIndex
    
    -- DataController -> UI Updates
    if Modules.DataController and Modules.DataController.Signals then
        -- Currency Changed
        Modules.DataController.Signals.CurrencyChanged:Connect(function(currencyType, newAmount)
            if Modules.UIController then
                Modules.UIController.UpdateCurrencyDisplay(currencyType, newAmount)
            end
        end)
        
        -- Dungeon Changed
        Modules.DataController.Signals.DungeonChanged:Connect(function(dungeonData)
            if Modules.UIController then
                Modules.UIController.UpdateDungeonDisplay(dungeonData)
            end
        end)
    end
    
    -- InputController -> Camera/UI
    if Modules.InputController and Modules.InputController.Signals then
        -- Zoom
        Modules.InputController.Signals.CameraZoom:Connect(function(delta)
            if Modules.CameraController then
                Modules.CameraController.Zoom(delta)
            end
        end)
        
        -- Rotate
        Modules.InputController.Signals.CameraRotate:Connect(function(deltaX, deltaY)
            if Modules.CameraController then
                Modules.CameraController.Rotate(deltaX, deltaY)
            end
        end)
        
        -- Pan
        Modules.InputController.Signals.CameraPan:Connect(function(delta)
            if Modules.CameraController then
                Modules.CameraController.Pan(delta)
            end
        end)
    end
    
    -- Server -> Client Remote Events
    if RemoteIndex then
        -- Currency Update
        RemoteIndex.OnClient("Currency_Update", function(data)
            if Modules.DataController then
                if data.Gold then
                    Modules.DataController.SetCurrency("Gold", data.Gold)
                end
                if data.Gems then
                    Modules.DataController.SetCurrency("Gems", data.Gems)
                end
            end
        end)
        
        -- Dungeon Update
        RemoteIndex.OnClient("Dungeon_Update", function(data)
            if Modules.DataController then
                Modules.DataController.UpdateDungeonData(data)
            end
            
            if data.LevelUp and Modules.UIController then
                Modules.UIController.ShowLevelUpAnimation(data.Level)
            end
            
            if data.LevelUp and Modules.AudioController then
                Modules.AudioController.PlaySound("LevelUp")
            end
        end)
        
        -- Notification
        RemoteIndex.OnClient("Notification", function(data)
            if Modules.UIController then
                Modules.UIController.ShowNotification(data.Title, data.Message, data.Type)
            end
            
            if Modules.AudioController then
                Modules.AudioController.PlayUISound("Notification")
            end
        end)
        
        -- Achievement
        RemoteIndex.OnClient("Achievement_Unlocked", function(data)
            if Modules.UIController then
                Modules.UIController.ShowNotification("🏆 " .. data.Name, data.Description, "Success")
            end
            
            if Modules.AudioController then
                Modules.AudioController.PlaySound("Achievement")
            end
        end)
        
        -- Raid Events
        RemoteIndex.OnClient("Raid_CombatTick", function(data)
            if Screens.RaidScreen and Screens.RaidScreen.UpdateCombat then
                Screens.RaidScreen.UpdateCombat(data)
            end
        end)
        
        RemoteIndex.OnClient("Raid_End", function(data)
            if Screens.RaidScreen and Screens.RaidScreen.ShowResults then
                Screens.RaidScreen.ShowResults(data)
            end
            
            if Modules.AudioController then
                local track = data.Status == "Victory" and "Victory" or "Defeat"
                Modules.AudioController.PlayMusic(track)
            end
        end)
        
        -- Stats Update (periodisch vom Server)
        RemoteIndex.OnClient("Stats_Update", function(data)
            if Modules.DataController then
                Modules.DataController.UpdateStats(data)
            end
            
            if Modules.UIController then
                Modules.UIController.UpdatePassiveIncomeTimer(data.AccumulatedIncome, data.IncomePerMinute)
            end
        end)
        
        -- Cooldown Update
        RemoteIndex.OnClient("Cooldown_Update", function(data)
            if Modules.DataController then
                Modules.DataController.UpdateCooldowns(data)
            end
        end)
        
        -- Defense Alert
        RemoteIndex.OnClient("Defense_Notification", function(data)
            if Modules.UIController then
                Modules.UIController.ShowDefenseAlert(data)
            end
            
            if Modules.AudioController then
                Modules.AudioController.PlaySound("Alert")
            end
        end)
        
        -- Defense Result
        RemoteIndex.OnClient("Defense_Result", function(data)
            if Modules.UIController then
                Modules.UIController.ShowDefenseResult(data)
            end
        end)
        
        -- Prestige Update
        RemoteIndex.OnClient("Prestige_Update", function(data)
            if Modules.DataController then
                Modules.DataController.SetPrestigeData(data)
            end
            
            if Screens.PrestigeScreen and Screens.PrestigeScreen.RefreshAll then
                Screens.PrestigeScreen.RefreshAll()
            end
        end)
        
        -- Heroes Update
        RemoteIndex.OnClient("Heroes_Update", function(data)
            if Modules.DataController then
                Modules.DataController.SetHeroData(data.Heroes, data.Team)
            end
        end)
        
        -- Shop Item Unlocked
        RemoteIndex.OnClient("Shop_ItemUnlocked", function(data)
            if Modules.DataController then
                Modules.DataController.UnlockShopItem(data.TabId, data.ItemId)
            end
        end)
    end
    
    logSuccess("Phase 6 abgeschlossen: Signals verbunden")
end

-------------------------------------------------
-- PHASE 7: FINALISIERUNG
-------------------------------------------------
local function finalize()
    log("Phase 7", "Finalisiere...")
    updateLoadingScreen(0.98, "Fast fertig...")
    
    -- Haupt-Musik starten
    if Modules.AudioController then
        Modules.AudioController.PlayMusic("MainTheme", true)
    end
    
    -- Kamera auf Übersicht setzen
    if Modules.CameraController then
        Modules.CameraController.SetMode("Overview", true)
    end
    
    -- Loading Screen ausblenden
    task.delay(0.5, function()
        updateLoadingScreen(1.0, "Bereit!")
        
        local mainUI = PlayerGui:FindFirstChild("MainUI")
        if mainUI then
            local loadingScreen = mainUI:FindFirstChild("LoadingScreen")
            if loadingScreen then
                -- Fade out
                local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local tween = game:GetService("TweenService"):Create(loadingScreen, tweenInfo, {
                    BackgroundTransparency = 1
                })
                tween:Play()
                
                -- Alle Kinder auch ausblenden
                for _, child in ipairs(loadingScreen:GetDescendants()) do
                    if child:IsA("TextLabel") or child:IsA("Frame") then
                        local childTween = game:GetService("TweenService"):Create(child, tweenInfo, {
                            BackgroundTransparency = 1,
                            TextTransparency = child:IsA("TextLabel") and 1 or nil,
                        })
                        childTween:Play()
                    end
                end
                
                task.delay(0.5, function()
                    loadingScreen.Visible = false
                end)
            end
        end
        
        -- Willkommens-Sound
        if Modules.AudioController then
            Modules.AudioController.PlayUISound("Success")
        end
    end)
    
    ClientState.IsInitialized = true
    
    logSuccess("Phase 7 abgeschlossen: Client bereit!")
end

-------------------------------------------------
-- ASSET PRELOADING (Optional)
-------------------------------------------------
local function preloadAssets()
    if not PRELOAD_ASSETS then return end
    
    log("Preload", "Lade Assets vor...")
    updateLoadingScreen(0.05, "Lade Assets...")
    
    local assetsToPreload = {}
    
    -- Sounds sammeln
    local soundsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if soundsFolder then
        local sounds = soundsFolder:FindFirstChild("Sounds")
        if sounds then
            for _, sound in ipairs(sounds:GetDescendants()) do
                if sound:IsA("Sound") then
                    table.insert(assetsToPreload, sound)
                end
            end
        end
    end
    
    -- Preload ausführen
    if #assetsToPreload > 0 then
        ContentProvider:PreloadAsync(assetsToPreload, function(contentId, status)
            -- Optional: Progress tracking
        end)
    end
    
    log("Preload", #assetsToPreload .. " Assets vorgeladen")
end

-------------------------------------------------
-- HAUPTINITIALISIERUNG
-------------------------------------------------
local function main()
    local startTime = os.clock()
    
    local success, error = pcall(function()
        -- Optional: Asset Preloading
        preloadAssets()
        
        -- Phase 1: Shared Modules
        loadSharedModules()
        
        -- Phase 2: Controllers laden
        loadControllers()
        
        -- Phase 3: Controllers initialisieren
        initializeControllers()
        
        -- Phase 4: UI Screens laden
        loadScreens()
        
        -- Phase 5: Server-Verbindung
        connectToServer()
        
        -- Phase 6: Signal Verbindungen
        setupSignalConnections()
        
        -- Phase 7: Finalisierung
        finalize()
    end)
    
    local endTime = os.clock()
    local duration = string.format("%.2f", endTime - startTime)
    
    if success then
        print("═══════════════════════════════════════════")
        print("  ✅ CLIENT ERFOLGREICH GESTARTET")
        print("  ⏱️  Dauer: " .. duration .. " Sekunden")
        print("  👤 Spieler: " .. LocalPlayer.Name)
        print("═══════════════════════════════════════════")
    else
        print("═══════════════════════════════════════════")
        print("  ❌ CLIENT START FEHLGESCHLAGEN")
        print("  Error: " .. tostring(error))
        print("═══════════════════════════════════════════")
        
        -- Fehler-UI anzeigen
        updateLoadingScreen(0, "Fehler beim Laden!")
    end
end

-------------------------------------------------
-- GLOBAL ACCESS (für Debugging)
-------------------------------------------------
if DEBUG_MODE then
    _G.DungeonTycoonClient = {
        Modules = Modules,
        Screens = Screens,
        State = ClientState,
        GetModule = function(name)
            return Modules[name]
        end,
        GetScreen = function(name)
            return Screens[name]
        end,
    }
end

-------------------------------------------------
-- ERROR HANDLING
-------------------------------------------------
local function onError(message)
    logError("Runtime", message)
    
    if Modules.UIController then
        Modules.UIController.ShowNotification("Fehler", "Ein Fehler ist aufgetreten", "Error")
    end
end

-- Globalen Error-Handler setzen (für unhandled errors)
if DEBUG_MODE then
    game:GetService("ScriptContext").Error:Connect(function(message, stackTrace)
        logError("Script", message)
        if DEBUG_MODE then
            print(stackTrace)
        end
    end)
end

-------------------------------------------------
-- RECONNECT HANDLING
-------------------------------------------------
local function setupReconnectHandling()
    -- Bei Verbindungsverlust
    Players.LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            log("Connection", "Verbindung verloren")
        end
    end)
end

setupReconnectHandling()

-------------------------------------------------
-- START
-------------------------------------------------

-- Kurz warten damit UI erstellt werden kann
task.wait(0.1)

-- Client starten
main()

-------------------------------------------------
-- CLEANUP BEI SPIELER-VERLASSEN
-------------------------------------------------
LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        -- Cleanup
        if Modules.AudioController then
            Modules.AudioController.StopAll()
        end
        
        if Modules.CameraController then
            Modules.CameraController.Reset()
        end
    end
end)

return Modules
