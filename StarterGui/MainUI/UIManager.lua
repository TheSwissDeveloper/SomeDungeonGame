--[[
    UIManager.lua
    Zentrale UI-Steuerung und Logik
    Pfad: StarterGui/MainUI/UIManager
    
    Dieses Script:
    - Steuert Screen-Navigation
    - Verarbeitet Server-Updates
    - Verwaltet Popups und Notifications
    - Verbindet UI mit Remote-Events
    
    WICHTIG: Läuft nach UISetup!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Warten auf MainUI
local MainUI = PlayerGui:WaitForChild("MainUI")

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")
local RemotesPath = SharedPath:WaitForChild("Remotes")

local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

print("[UIManager] Initialisiere...")

-------------------------------------------------
-- UI REFERENZEN
-------------------------------------------------
local HUD = MainUI:WaitForChild("HUD")
local BottomNav = MainUI:WaitForChild("BottomNav")
local Screens = MainUI:WaitForChild("Screens")
local Notifications = MainUI:WaitForChild("Notifications")
local PopupOverlay = MainUI:WaitForChild("PopupOverlay")
local LoadingScreen = MainUI:WaitForChild("LoadingScreen")

-- HUD Elemente
local HUDContent = HUD:WaitForChild("Content")
local GoldDisplay = HUDContent:WaitForChild("GoldDisplay")
local GemsDisplay = HUDContent:WaitForChild("GemsDisplay")
local IncomeDisplay = HUDContent:WaitForChild("IncomeDisplay")
local LevelDisplay = HUDContent:WaitForChild("LevelDisplay")
local CollectButton = HUDContent:WaitForChild("CollectButton")
local SettingsButton = HUDContent:WaitForChild("SettingsButton")

-- Nav Buttons
local NavItems = BottomNav:WaitForChild("NavItems")

-------------------------------------------------
-- STATE
-------------------------------------------------
local UIState = {
    CurrentScreen = "Dungeon",
    IsTransitioning = false,
    IsPopupOpen = false,
    CurrentPopup = nil,
    
    -- Cached Data
    PlayerData = {
        Gold = 0,
        Gems = 0,
        DungeonLevel = 1,
        PrestigeLevel = 0,
        IncomePerMinute = 0,
        AccumulatedIncome = 0,
    },
    
    -- Notifications Queue
    NotificationQueue = {},
    MaxNotifications = 5,
}

-------------------------------------------------
-- UI CONFIG
-------------------------------------------------
local CONFIG = {
    -- Animation
    ScreenTransitionTime = 0.25,
    PopupAnimationTime = 0.2,
    NotificationDuration = 4,
    NotificationSlideTime = 0.3,
    
    -- Colors (müssen mit UISetup übereinstimmen)
    Colors = {
        Primary = Color3.fromRGB(99, 102, 241),
        Surface = Color3.fromRGB(30, 41, 59),
        Success = Color3.fromRGB(34, 197, 94),
        Warning = Color3.fromRGB(234, 179, 8),
        Error = Color3.fromRGB(239, 68, 68),
        Info = Color3.fromRGB(59, 130, 246),
        Gold = Color3.fromRGB(251, 191, 36),
        Gems = Color3.fromRGB(168, 85, 247),
        Text = Color3.fromRGB(248, 250, 252),
        TextMuted = Color3.fromRGB(148, 163, 184),
    },
}

-------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------

local function tween(instance, properties, duration, easingStyle)
    local tweenInfo = TweenInfo.new(
        duration or 0.3,
        easingStyle or Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    local t = TweenService:Create(instance, tweenInfo, properties)
    t:Play()
    return t
end

local function formatNumber(num)
    return CurrencyUtil.FormatNumber(num)
end

local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

-------------------------------------------------
-- HUD UPDATES
-------------------------------------------------

local function updateGoldDisplay(amount)
    UIState.PlayerData.Gold = amount
    local label = GoldDisplay:FindFirstChild("Amount")
    if label then
        label.Text = formatNumber(amount)
    end
end

local function updateGemsDisplay(amount)
    UIState.PlayerData.Gems = amount
    local label = GemsDisplay:FindFirstChild("Amount")
    if label then
        label.Text = formatNumber(amount)
    end
end

local function updateIncomeDisplay(incomePerMin, accumulated)
    UIState.PlayerData.IncomePerMinute = incomePerMin or UIState.PlayerData.IncomePerMinute
    UIState.PlayerData.AccumulatedIncome = accumulated or UIState.PlayerData.AccumulatedIncome
    
    local amountLabel = IncomeDisplay:FindFirstChild("Amount")
    if amountLabel then
        amountLabel.Text = "+" .. formatNumber(UIState.PlayerData.IncomePerMinute) .. "/min"
    end
    
    -- Collect Button Text updaten wenn accumulated > 0
    if UIState.PlayerData.AccumulatedIncome > 0 then
        CollectButton.Text = formatNumber(UIState.PlayerData.AccumulatedIncome)
        CollectButton.BackgroundColor3 = CONFIG.Colors.Success
    else
        CollectButton.Text = "Abholen"
        CollectButton.BackgroundColor3 = CONFIG.Colors.Surface
    end
end

local function updateLevelDisplay(level)
    UIState.PlayerData.DungeonLevel = level
    local valueLabel = LevelDisplay:FindFirstChild("Value")
    if valueLabel then
        valueLabel.Text = tostring(level)
    end
end

-------------------------------------------------
-- SCREEN NAVIGATION
-------------------------------------------------

local function switchScreen(screenName)
    if UIState.IsTransitioning then return end
    if UIState.CurrentScreen == screenName then return end
    
    UIState.IsTransitioning = true
    
    local oldScreen = Screens:FindFirstChild(UIState.CurrentScreen .. "Screen")
    local newScreen = Screens:FindFirstChild(screenName .. "Screen")
    
    if not newScreen then
        UIState.IsTransitioning = false
        return
    end
    
    -- Nav Buttons updaten
    for _, button in ipairs(NavItems:GetChildren()) do
        if button:IsA("TextButton") then
            local isActive = button.Name == screenName .. "Button"
            
            tween(button, {
                BackgroundColor3 = isActive and CONFIG.Colors.Primary or CONFIG.Colors.Surface,
                BackgroundTransparency = isActive and 0 or 0.5,
            }, 0.2)
            
            local label = button:FindFirstChild("Label")
            if label then
                tween(label, {
                    TextColor3 = isActive and CONFIG.Colors.Text or CONFIG.Colors.TextMuted,
                }, 0.2)
            end
        end
    end
    
    -- Screen Transition
    if oldScreen then
        tween(oldScreen, { BackgroundTransparency = 1 }, CONFIG.ScreenTransitionTime)
        task.delay(CONFIG.ScreenTransitionTime, function()
            oldScreen.Visible = false
            oldScreen.BackgroundTransparency = 0
        end)
    end
    
    newScreen.BackgroundTransparency = 1
    newScreen.Visible = true
    tween(newScreen, { BackgroundTransparency = 0 }, CONFIG.ScreenTransitionTime)
    
    UIState.CurrentScreen = screenName
    
    task.delay(CONFIG.ScreenTransitionTime, function()
        UIState.IsTransitioning = false
    end)
    
    print("[UIManager] Screen gewechselt zu: " .. screenName)
end

-------------------------------------------------
-- NOTIFICATIONS
-------------------------------------------------

local function createNotification(title, message, notifType)
    notifType = notifType or "Info"
    
    -- Farbe basierend auf Typ
    local colors = {
        Success = { bg = CONFIG.Colors.Success, icon = "✅" },
        Error = { bg = CONFIG.Colors.Error, icon = "❌" },
        Warning = { bg = CONFIG.Colors.Warning, icon = "⚠️" },
        Info = { bg = CONFIG.Colors.Info, icon = "ℹ️" },
    }
    
    local colorData = colors[notifType] or colors.Info
    
    -- Notification Frame erstellen
    local notif = Instance.new("Frame")
    notif.Name = "Notification"
    notif.Size = UDim2.new(1, 0, 0, 70)
    notif.BackgroundColor3 = CONFIG.Colors.Surface
    notif.BorderSizePixel = 0
    notif.Position = UDim2.new(1, 50, 0, 0)  -- Start außerhalb
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = notif
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = colorData.bg
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    stroke.Parent = notif
    
    -- Accent Bar
    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.Size = UDim2.new(0, 4, 1, -8)
    accent.Position = UDim2.new(0, 4, 0, 4)
    accent.BackgroundColor3 = colorData.bg
    accent.BorderSizePixel = 0
    accent.Parent = notif
    
    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(0, 2)
    accentCorner.Parent = accent
    
    -- Icon
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 30, 0, 30)
    icon.Position = UDim2.new(0, 16, 0.5, -15)
    icon.BackgroundTransparency = 1
    icon.Text = colorData.icon
    icon.TextSize = 20
    icon.Parent = notif
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -60, 0, 24)
    titleLabel.Position = UDim2.new(0, 50, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title or "Notification"
    titleLabel.TextColor3 = CONFIG.Colors.Text
    titleLabel.TextSize = 16
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = notif
    
    -- Message
    local messageLabel = Instance.new("TextLabel")
    messageLabel.Name = "Message"
    messageLabel.Size = UDim2.new(1, -60, 0, 24)
    messageLabel.Position = UDim2.new(0, 50, 0, 34)
    messageLabel.BackgroundTransparency = 1
    messageLabel.Text = message or ""
    messageLabel.TextColor3 = CONFIG.Colors.TextMuted
    messageLabel.TextSize = 14
    messageLabel.Font = Enum.Font.Gotham
    messageLabel.TextXAlignment = Enum.TextXAlignment.Left
    messageLabel.TextTruncate = Enum.TextTruncate.AtEnd
    messageLabel.Parent = notif
    
    notif.Parent = Notifications
    
    -- Animation: Reinsliden
    tween(notif, { Position = UDim2.new(0, 0, 0, 0) }, CONFIG.NotificationSlideTime)
    
    -- Max Notifications begrenzen
    local children = Notifications:GetChildren()
    local notifCount = 0
    for _, child in ipairs(children) do
        if child:IsA("Frame") then
            notifCount = notifCount + 1
        end
    end
    
    if notifCount > UIState.MaxNotifications then
        -- Älteste entfernen
        for _, child in ipairs(children) do
            if child:IsA("Frame") and child ~= notif then
                child:Destroy()
                break
            end
        end
    end
    
    -- Auto-Remove nach Duration
    task.delay(CONFIG.NotificationDuration, function()
        if notif and notif.Parent then
            tween(notif, { Position = UDim2.new(1, 50, 0, 0) }, CONFIG.NotificationSlideTime)
            task.delay(CONFIG.NotificationSlideTime, function()
                if notif and notif.Parent then
                    notif:Destroy()
                end
            end)
        end
    end)
    
    return notif
end

local function showNotification(title, message, notifType)
    return createNotification(title, message, notifType)
end

-------------------------------------------------
-- POPUPS
-------------------------------------------------

local function showPopup(popupContent, options)
    options = options or {}
    
    if UIState.IsPopupOpen then
        return
    end
    
    UIState.IsPopupOpen = true
    UIState.CurrentPopup = popupContent
    
    local container = PopupOverlay:FindFirstChild("PopupContainer")
    
    -- Alten Content entfernen
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    -- Neuen Content hinzufügen
    if popupContent then
        popupContent.Parent = container
    end
    
    -- Size anpassen
    if options.Size then
        container.Size = options.Size
        container.Position = UDim2.new(0.5, -options.Size.X.Offset/2, 0.5, -options.Size.Y.Offset/2)
    end
    
    -- Animation
    PopupOverlay.Visible = true
    PopupOverlay.BackgroundTransparency = 1
    container.Position = UDim2.new(0.5, -container.Size.X.Offset/2, 0.5, -container.Size.Y.Offset/2 + 50)
    
    tween(PopupOverlay, { BackgroundTransparency = 0.6 }, CONFIG.PopupAnimationTime)
    tween(container, { 
        Position = UDim2.new(0.5, -container.Size.X.Offset/2, 0.5, -container.Size.Y.Offset/2) 
    }, CONFIG.PopupAnimationTime, Enum.EasingStyle.Back)
end

local function hidePopup()
    if not UIState.IsPopupOpen then
        return
    end
    
    local container = PopupOverlay:FindFirstChild("PopupContainer")
    
    tween(PopupOverlay, { BackgroundTransparency = 1 }, CONFIG.PopupAnimationTime)
    tween(container, { 
        Position = UDim2.new(0.5, -container.Size.X.Offset/2, 0.5, -container.Size.Y.Offset/2 + 50) 
    }, CONFIG.PopupAnimationTime)
    
    task.delay(CONFIG.PopupAnimationTime, function()
        PopupOverlay.Visible = false
        UIState.IsPopupOpen = false
        UIState.CurrentPopup = nil
    end)
end

-- Popup Overlay Click to Close
PopupOverlay.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        -- Nur schließen wenn außerhalb des Containers geklickt
        local container = PopupOverlay:FindFirstChild("PopupContainer")
        local mouse = input.Position
        local containerPos = container.AbsolutePosition
        local containerSize = container.AbsoluteSize
        
        if mouse.X < containerPos.X or mouse.X > containerPos.X + containerSize.X or
           mouse.Y < containerPos.Y or mouse.Y > containerPos.Y + containerSize.Y then
            hidePopup()
        end
    end
end)

-------------------------------------------------
-- SETTINGS POPUP
-------------------------------------------------

local function showSettingsPopup()
    local content = Instance.new("Frame")
    content.Name = "SettingsContent"
    content.Size = UDim2.new(1, -32, 1, -32)
    content.Position = UDim2.new(0, 16, 0, 16)
    content.BackgroundTransparency = 1
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "⚙️ Einstellungen"
    title.TextColor3 = CONFIG.Colors.Text
    title.TextSize = 24
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = content
    
    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 36, 0, 36)
    closeBtn.Position = UDim2.new(1, -36, 0, 0)
    closeBtn.BackgroundColor3 = CONFIG.Colors.Error
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = CONFIG.Colors.Text
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = content
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 18)
    closeCorner.Parent = closeBtn
    
    closeBtn.MouseButton1Click:Connect(hidePopup)
    
    -- Settings List
    local settingsList = Instance.new("Frame")
    settingsList.Name = "SettingsList"
    settingsList.Size = UDim2.new(1, 0, 1, -60)
    settingsList.Position = UDim2.new(0, 0, 0, 50)
    settingsList.BackgroundTransparency = 1
    settingsList.Parent = content
    
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 10)
    layout.Parent = settingsList
    
    -- Setting Items (Beispiel)
    local settings = {
        { Name = "Musik", Key = "MusicEnabled", Default = true },
        { Name = "Soundeffekte", Key = "SFXEnabled", Default = true },
        { Name = "Benachrichtigungen", Key = "NotificationsEnabled", Default = true },
    }
    
    for _, setting in ipairs(settings) do
        local item = Instance.new("Frame")
        item.Name = setting.Key
        item.Size = UDim2.new(1, 0, 0, 50)
        item.BackgroundColor3 = CONFIG.Colors.Surface
        item.Parent = settingsList
        
        local itemCorner = Instance.new("UICorner")
        itemCorner.CornerRadius = UDim.new(0, 8)
        itemCorner.Parent = item
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, -20, 1, 0)
        label.Position = UDim2.new(0, 15, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = setting.Name
        label.TextColor3 = CONFIG.Colors.Text
        label.TextSize = 16
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = item
        
        local toggle = Instance.new("TextButton")
        toggle.Name = "Toggle"
        toggle.Size = UDim2.new(0, 60, 0, 30)
        toggle.Position = UDim2.new(1, -75, 0.5, -15)
        toggle.BackgroundColor3 = setting.Default and CONFIG.Colors.Success or CONFIG.Colors.Surface
        toggle.Text = setting.Default and "AN" or "AUS"
        toggle.TextColor3 = CONFIG.Colors.Text
        toggle.TextSize = 12
        toggle.Font = Enum.Font.GothamBold
        toggle.Parent = item
        
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(0, 15)
        toggleCorner.Parent = toggle
        
        local isOn = setting.Default
        toggle.MouseButton1Click:Connect(function()
            isOn = not isOn
            tween(toggle, {
                BackgroundColor3 = isOn and CONFIG.Colors.Success or CONFIG.Colors.Surface,
            }, 0.2)
            toggle.Text = isOn and "AN" or "AUS"
            
            -- Setting an Server senden
            RemoteIndex.Invoke("Player_SettingsUpdate", setting.Key, isOn)
        end)
    end
    
    showPopup(content, { Size = UDim2.new(0, 400, 0, 350) })
end

-------------------------------------------------
-- COLLECT PASSIVE INCOME
-------------------------------------------------

local function collectPassiveIncome()
    if UIState.PlayerData.AccumulatedIncome <= 0 then
        showNotification("Nichts zum Abholen", "Warte bis Einkommen gesammelt wurde.", "Warning")
        return
    end
    
    -- Button deaktivieren
    CollectButton.Active = false
    CollectButton.Text = "..."
    
    -- Server Request
    local result = RemoteIndex.Invoke("Currency_CollectPassive")
    
    CollectButton.Active = true
    
    if result and result.Success then
        showNotification(
            "Einkommen gesammelt!",
            "+" .. formatNumber(result.Amount) .. " Gold",
            "Success"
        )
        
        updateGoldDisplay(result.NewTotal)
        UIState.PlayerData.AccumulatedIncome = 0
        updateIncomeDisplay()
    else
        showNotification(
            "Fehler",
            result and result.Error or "Unbekannter Fehler",
            "Error"
        )
    end
end

-------------------------------------------------
-- BUTTON CONNECTIONS
-------------------------------------------------

-- Nav Buttons
for _, button in ipairs(NavItems:GetChildren()) do
    if button:IsA("TextButton") then
        local screenName = button.Name:gsub("Button", "")
        button.MouseButton1Click:Connect(function()
            switchScreen(screenName)
        end)
    end
end

-- Collect Button
CollectButton.MouseButton1Click:Connect(collectPassiveIncome)

-- Settings Button
SettingsButton.MouseButton1Click:Connect(showSettingsPopup)

-------------------------------------------------
-- REMOTE EVENT HANDLERS
-------------------------------------------------

-- Currency Update
RemoteIndex.OnClient("Currency_Update", function(data)
    if data.Gold then
        updateGoldDisplay(data.Gold)
    end
    if data.Gems then
        updateGemsDisplay(data.Gems)
    end
end)

-- Dungeon Update
RemoteIndex.OnClient("Dungeon_Update", function(data)
    if data.Level then
        updateLevelDisplay(data.Level)
    end
    
    if data.LevelUp then
        showNotification(
            "🎉 Level Up!",
            "Dein Dungeon ist jetzt Level " .. data.Level,
            "Success"
        )
    end
end)

-- Stats Update
RemoteIndex.OnClient("Stats_Update", function(data)
    if data.IncomePerMinute then
        UIState.PlayerData.IncomePerMinute = data.IncomePerMinute
    end
    if data.AccumulatedIncome then
        UIState.PlayerData.AccumulatedIncome = data.AccumulatedIncome
    end
    updateIncomeDisplay()
    
    if data.DungeonLevel then
        updateLevelDisplay(data.DungeonLevel)
    end
end)

-- Notification
RemoteIndex.OnClient("Notification", function(data)
    showNotification(data.Title, data.Message, data.Type)
end)

-- Achievement Unlocked
RemoteIndex.OnClient("Achievement_Unlocked", function(data)
    showNotification(
        "🏆 " .. data.Name,
        data.Description,
        "Success"
    )
end)

-- Raid Update
RemoteIndex.OnClient("Raid_Update", function(data)
    if data.Status == "Started" then
        switchScreen("Raid")
    end
end)

-- Raid End
RemoteIndex.OnClient("Raid_End", function(data)
    local status = data.Status == "Victory" and "Sieg!" or "Niederlage"
    local notifType = data.Status == "Victory" and "Success" or "Warning"
    
    showNotification(
        "Raid " .. status,
        formatNumber(data.Rewards.Gold) .. " Gold, " .. formatNumber(data.Rewards.Gems) .. " Gems",
        notifType
    )
end)

-- Defense Notification
RemoteIndex.OnClient("Defense_Notification", function(data)
    showNotification(
        "⚔️ Angriff!",
        data.AttackerName .. " greift an!",
        "Warning"
    )
end)

-- Defense Result
RemoteIndex.OnClient("Defense_Result", function(data)
    local status = data.AttackerWon and "Dungeon gefallen" or "Verteidigung erfolgreich!"
    local notifType = data.AttackerWon and "Warning" or "Success"
    
    showNotification(status, data.AttackerName .. " - " .. data.RoomsCleared .. " Räume", notifType)
end)

-------------------------------------------------
-- INITIAL DATA LOAD
-------------------------------------------------

local function loadInitialData()
    LoadingScreen:FindFirstChild("LoadingText").Text = "Lade Spielerdaten..."
    
    -- Currency laden
    local currencyResult = RemoteIndex.Invoke("Currency_Request")
    if currencyResult and currencyResult.Success then
        updateGoldDisplay(currencyResult.Gold)
        updateGemsDisplay(currencyResult.Gems)
    end
    
    LoadingScreen:FindFirstChild("LoadingText").Text = "Bereite Spiel vor..."
    task.wait(0.5)
    
    -- Loading Screen ausblenden
    tween(LoadingScreen, { BackgroundTransparency = 1 }, 0.5)
    task.delay(0.5, function()
        LoadingScreen.Visible = false
    end)
    
    -- Willkommens-Notification
    task.delay(1, function()
        showNotification("Willkommen!", "Baue deinen Dungeon und verteidige ihn!", "Info")
    end)
end

-------------------------------------------------
-- PERIODIC UPDATES
-------------------------------------------------

local lastUpdate = 0
local UPDATE_INTERVAL = 1

RunService.Heartbeat:Connect(function(dt)
    lastUpdate = lastUpdate + dt
    
    if lastUpdate >= UPDATE_INTERVAL then
        lastUpdate = 0
        
        -- Accumulated Income lokal hochzählen (approximiert)
        if UIState.PlayerData.IncomePerMinute > 0 then
            local incomePerSecond = UIState.PlayerData.IncomePerMinute / 60
            UIState.PlayerData.AccumulatedIncome = UIState.PlayerData.AccumulatedIncome + incomePerSecond
            updateIncomeDisplay()
        end
    end
end)

-------------------------------------------------
-- INITIALIZE
-------------------------------------------------

task.spawn(function()
    task.wait(0.5)  -- Kurz warten für Server-Verbindung
    loadInitialData()
end)

-------------------------------------------------
-- PUBLIC API (für andere Scripts)
-------------------------------------------------

local UIManager = {}

UIManager.ShowNotification = showNotification
UIManager.ShowPopup = showPopup
UIManager.HidePopup = hidePopup
UIManager.SwitchScreen = switchScreen
UIManager.UpdateGold = updateGoldDisplay
UIManager.UpdateGems = updateGemsDisplay
UIManager.UpdateLevel = updateLevelDisplay
UIManager.GetState = function() return UIState end

-- Global verfügbar machen
_G.UIManager = UIManager

print("[UIManager] Initialisiert!")

return UIManager
