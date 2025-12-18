--[[
    ClientMain.lua
    Haupt-Entry-Point für den Client
    Pfad: StarterPlayer/StarterPlayerScripts/Client/ClientMain
    
    Dieses Script:
    - Initialisiert alle Client-Module
    - Verbindet Remote-Event-Listener
    - Koordiniert UI und Input
    
    WICHTIG: Dies ist ein LOCALSCRIPT!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterPlayer = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer

print("[ClientMain] Starte Client-Initialisierung...")

-------------------------------------------------
-- PFADE DEFINIEREN
-------------------------------------------------
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")
local RemotesPath = SharedPath:WaitForChild("Remotes")

local ClientPath = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
local ControllersPath = ClientPath:WaitForChild("Controllers")
local UIPath = ClientPath:WaitForChild("UI")

-------------------------------------------------
-- SHARED MODULES LADEN
-------------------------------------------------
print("[ClientMain] Lade Shared Modules...")

local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))

local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

print("[ClientMain] Shared Modules geladen!")

-------------------------------------------------
-- CLIENT MODULES LADEN
-------------------------------------------------
print("[ClientMain] Lade Client Modules...")

local DataController = require(ControllersPath:WaitForChild("DataController"))
local UIController = require(ControllersPath:WaitForChild("UIController"))
local InputController = require(ControllersPath:WaitForChild("InputController"))
local AudioController = require(ControllersPath:WaitForChild("AudioController"))
local CameraController = require(ControllersPath:WaitForChild("CameraController"))

print("[ClientMain] Client Modules geladen!")

-------------------------------------------------
-- CLIENT STATE
-------------------------------------------------
local ClientState = {
    IsInitialized = false,
    IsDataLoaded = false,
    CurrentScreen = "Loading",
    Platform = "Desktop",  -- Desktop, Mobile, Console
}

-- Plattform erkennen
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
    ClientState.Platform = "Mobile"
elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
    ClientState.Platform = "Console"
end

print("[ClientMain] Plattform erkannt: " .. ClientState.Platform)

-------------------------------------------------
-- INITIALISIERUNG
-------------------------------------------------
print("[ClientMain] Initialisiere Controller...")

-- 1. DataController (keine Abhängigkeiten)
DataController.Initialize()

-- 2. AudioController (keine Abhängigkeiten)
AudioController.Initialize()

-- 3. CameraController (keine Abhängigkeiten)
CameraController.Initialize()

-- 4. UIController (braucht DataController)
UIController.Initialize(DataController, ClientState)

-- 5. InputController (braucht UIController, CameraController)
InputController.Initialize(UIController, CameraController, ClientState)

print("[ClientMain] Controller initialisiert!")

-------------------------------------------------
-- REMOTE EVENT HANDLER
-------------------------------------------------
print("[ClientMain] Verbinde Remote Events...")

-- Currency Update
RemoteIndex.OnClient("Currency_Update", function(data)
    DataController.UpdateCurrency(data.Gold, data.Gems)
    UIController.UpdateCurrencyDisplay()
    
    if data.Source then
        -- Animation/Sound je nach Source
        if data.Source == "PassiveIncome" then
            AudioController.PlaySound("CoinCollect")
        elseif data.Source == "RaidReward" then
            AudioController.PlaySound("Reward")
        elseif data.Source == "Prestige" then
            AudioController.PlaySound("Prestige")
        end
    end
end)

-- Dungeon Update
RemoteIndex.OnClient("Dungeon_Update", function(data)
    DataController.UpdateDungeon(data)
    UIController.UpdateDungeonDisplay()
    
    if data.LevelUp then
        UIController.ShowLevelUpAnimation(data.Level)
        AudioController.PlaySound("LevelUp")
    end
end)

-- Heroes Update
RemoteIndex.OnClient("Heroes_Update", function(data)
    DataController.UpdateHeroes(data)
    UIController.UpdateHeroesDisplay()
end)

-- Raid Update
RemoteIndex.OnClient("Raid_Update", function(data)
    if data.Status == "Started" then
        UIController.ShowRaidScreen(data)
        AudioController.PlayMusic("RaidBattle")
    end
end)

-- Raid Combat Tick
RemoteIndex.OnClient("Raid_CombatTick", function(data)
    UIController.UpdateRaidCombat(data)
end)

-- Raid End
RemoteIndex.OnClient("Raid_End", function(data)
    UIController.ShowRaidResult(data)
    AudioController.StopMusic()
    
    if data.Status == "Victory" then
        AudioController.PlaySound("Victory")
    else
        AudioController.PlaySound("Defeat")
    end
end)

-- Defense Notification (jemand greift an)
RemoteIndex.OnClient("Defense_Notification", function(data)
    UIController.ShowDefenseAlert(data.AttackerName, data.AttackerLevel)
    AudioController.PlaySound("Alert")
end)

-- Defense Result
RemoteIndex.OnClient("Defense_Result", function(data)
    UIController.ShowDefenseResult(data)
end)

-- Notification
RemoteIndex.OnClient("Notification", function(data)
    UIController.ShowNotification(data.Title, data.Message, data.Type)
    
    if data.Type == "Success" then
        AudioController.PlaySound("Success")
    elseif data.Type == "Error" then
        AudioController.PlaySound("Error")
    elseif data.Type == "Warning" then
        AudioController.PlaySound("Warning")
    end
end)

-- Inbox Update
RemoteIndex.OnClient("Inbox_Update", function(inbox)
    DataController.UpdateInbox(inbox)
    UIController.UpdateInboxBadge()
end)

print("[ClientMain] Remote Events verbunden!")

-------------------------------------------------
-- INITIALE DATEN LADEN
-------------------------------------------------
print("[ClientMain] Lade initiale Daten...")

-- Zeige Loading Screen
UIController.ShowLoadingScreen("Verbinde mit Server...")

-- Währung abfragen
local currencyResult = RemoteIndex.Invoke("Currency_Request")
if currencyResult and currencyResult.Success then
    DataController.UpdateCurrency(currencyResult.Gold, currencyResult.Gems)
    print("[ClientMain] Währung geladen: " .. currencyResult.Gold .. " Gold, " .. currencyResult.Gems .. " Gems")
else
    warn("[ClientMain] Währung konnte nicht geladen werden")
end

-- Warte auf Server-Signal dass Daten bereit sind
UIController.ShowLoadingScreen("Lade Spielerdaten...")

-- Kurze Verzögerung für Server-Initialisierung
task.wait(1)

-- Versuche Daten zu laden
local maxAttempts = 10
local attempt = 0

repeat
    attempt = attempt + 1
    local result = RemoteIndex.Invoke("Currency_Request")
    
    if result and result.Success then
        ClientState.IsDataLoaded = true
        DataController.UpdateCurrency(result.Gold, result.Gems)
    else
        task.wait(0.5)
    end
until ClientState.IsDataLoaded or attempt >= maxAttempts

if not ClientState.IsDataLoaded then
    warn("[ClientMain] Daten konnten nicht geladen werden nach " .. maxAttempts .. " Versuchen")
    UIController.ShowError("Verbindung fehlgeschlagen", "Bitte starte das Spiel neu.")
    return
end

print("[ClientMain] Daten geladen!")

-------------------------------------------------
-- LOADING ABSCHLIESSEN
-------------------------------------------------
UIController.ShowLoadingScreen("Bereite Spiel vor...")
task.wait(0.5)

-- Kamera positionieren
CameraController.SetMode("Overview")

-- Musik starten
AudioController.PlayMusic("MainTheme")

-- Loading Screen ausblenden
UIController.HideLoadingScreen()

-- Hauptmenü oder Spiel anzeigen
local playerData = DataController.GetData()
if playerData and playerData.Progress and not playerData.Progress.Tutorial.Intro then
    -- Erstes Mal - Tutorial starten
    UIController.ShowTutorial("Intro")
else
    -- Normaler Start - HUD anzeigen
    UIController.ShowMainHUD()
end

ClientState.IsInitialized = true
ClientState.CurrentScreen = "Main"

print("[ClientMain] ========================================")
print("[ClientMain] Dungeon Tycoon Client bereit!")
print("[ClientMain] Plattform: " .. ClientState.Platform)
print("[ClientMain] ========================================")

-------------------------------------------------
-- CLIENT LOOP
-------------------------------------------------
local RunService = game:GetService("RunService")
local lastUpdate = 0
local UPDATE_INTERVAL = 1  -- Sekunden

RunService.Heartbeat:Connect(function(deltaTime)
    if not ClientState.IsInitialized then return end
    
    lastUpdate = lastUpdate + deltaTime
    
    if lastUpdate >= UPDATE_INTERVAL then
        lastUpdate = 0
        
        -- Periodische UI-Updates
        UIController.UpdatePassiveIncomeTimer()
        UIController.UpdateCooldownTimers()
    end
end)

-------------------------------------------------
-- CLEANUP BEI DISCONNECT
-------------------------------------------------
LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        -- Spieler verlässt
        AudioController.StopAll()
    end
end)
