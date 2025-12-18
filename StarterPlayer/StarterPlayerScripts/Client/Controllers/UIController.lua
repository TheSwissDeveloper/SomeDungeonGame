--[[
    UIController.lua
    Zentrale UI-Steuerung
    Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController
    
    Verantwortlich für:
    - Screen-Management (Main, Shop, Heroes, Raid, etc.)
    - HUD-Updates
    - Popups und Notifications
    - UI-Animationen
    
    WICHTIG: Alle UI-Interaktionen laufen über diesen Controller!
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")
local RemotesPath = SharedPath:WaitForChild("Remotes")

local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

-- Referenzen (werden bei Initialize gesetzt)
local DataController = nil
local ClientState = nil

local UIController = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Animation Timings
    FadeTime = 0.3,
    SlideTime = 0.25,
    PopupTime = 0.2,
    
    -- Notification
    NotificationDuration = 3,
    MaxNotifications = 5,
    
    -- Colors
    Colors = {
        Primary = Color3.fromRGB(79, 70, 229),       -- Indigo
        Secondary = Color3.fromRGB(99, 102, 241),   -- Light Indigo
        Success = Color3.fromRGB(34, 197, 94),      -- Green
        Warning = Color3.fromRGB(234, 179, 8),      -- Yellow
        Error = Color3.fromRGB(239, 68, 68),        -- Red
        Info = Color3.fromRGB(59, 130, 246),        -- Blue
        Gold = Color3.fromRGB(251, 191, 36),        -- Amber
        Gems = Color3.fromRGB(168, 85, 247),        -- Purple
        Background = Color3.fromRGB(17, 24, 39),    -- Dark
        Surface = Color3.fromRGB(31, 41, 55),       -- Gray-800
        Text = Color3.fromRGB(243, 244, 246),       -- Gray-100
        TextMuted = Color3.fromRGB(156, 163, 175),  -- Gray-400
    },
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- UI REFERENCES
-------------------------------------------------
local screenGui = nil
local screens = {}          -- { [screenName] = Frame }
local activeScreen = nil
local activePopup = nil
local notifications = {}    -- Array von aktiven Notifications

-- HUD References
local hudFrame = nil
local currencyDisplay = nil
local passiveIncomeDisplay = nil
local raidCooldownDisplay = nil
local menuButtons = nil

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
UIController.Signals = {
    ScreenChanged = SignalUtil.new(),       -- (newScreen, oldScreen)
    PopupOpened = SignalUtil.new(),         -- (popupName)
    PopupClosed = SignalUtil.new(),         -- (popupName)
    ButtonClicked = SignalUtil.new(),       -- (buttonName, data)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[UIController]", ...)
    end
end

--[[
    Erstellt ein neues UI-Element
    @param className: Roblox-Klassenname
    @param properties: Properties-Table
    @param parent: Parent-Instance
    @return: Neue Instance
]]
local function create(className, properties, parent)
    local instance = Instance.new(className)
    
    for property, value in pairs(properties or {}) do
        if property ~= "Children" then
            instance[property] = value
        end
    end
    
    if properties and properties.Children then
        for _, child in ipairs(properties.Children) do
            child.Parent = instance
        end
    end
    
    if parent then
        instance.Parent = parent
    end
    
    return instance
end

--[[
    Erstellt einen UICorner
    @param radius: Corner-Radius
    @return: UICorner Instance
]]
local function createCorner(radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

--[[
    Erstellt einen UIStroke
    @param color: Stroke-Farbe
    @param thickness: Stroke-Dicke
    @return: UIStroke Instance
]]
local function createStroke(color, thickness)
    return create("UIStroke", {
        Color = color or CONFIG.Colors.Secondary,
        Thickness = thickness or 1,
        Transparency = 0.5,
    })
end

--[[
    Tween-Animation Helper
    @param instance: Zu animierende Instance
    @param properties: Ziel-Properties
    @param duration: Dauer in Sekunden
    @param easingStyle: EasingStyle
    @return: Tween
]]
local function tween(instance, properties, duration, easingStyle)
    local tweenInfo = TweenInfo.new(
        duration or CONFIG.FadeTime,
        easingStyle or Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tweenObj = TweenService:Create(instance, tweenInfo, properties)
    tweenObj:Play()
    return tweenObj
end

--[[
    Formatiert Zeit in MM:SS
    @param seconds: Sekunden
    @return: Formatierter String
]]
local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

-------------------------------------------------
-- UI CREATION - MAIN SCREENGUI
-------------------------------------------------

local function createScreenGui()
    screenGui = create("ScreenGui", {
        Name = "DungeonTycoonUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    }, PlayerGui)
    
    return screenGui
end

-------------------------------------------------
-- UI CREATION - HUD
-------------------------------------------------

local function createHUD()
    hudFrame = create("Frame", {
        Name = "HUD",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    }, screenGui)
    
    -- Top Bar (Währung)
    local topBar = create("Frame", {
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, 60),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = CONFIG.Colors.Background,
        BackgroundTransparency = 0.3,
    }, hudFrame)
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, topBar)
    
    -- Gold Display
    currencyDisplay = {}
    
    currencyDisplay.Gold = create("Frame", {
        Name = "GoldDisplay",
        Size = UDim2.new(0, 150, 0, 40),
        Position = UDim2.new(0, 20, 0, 10),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, topBar)
    createCorner(20).Parent = currencyDisplay.Gold
    
    create("TextLabel", {
        Name = "Icon",
        Size = UDim2.new(0, 30, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = "💰",
        TextSize = 20,
    }, currencyDisplay.Gold)
    
    currencyDisplay.GoldLabel = create("TextLabel", {
        Name = "Amount",
        Size = UDim2.new(1, -50, 1, 0),
        Position = UDim2.new(0, 40, 0, 0),
        BackgroundTransparency = 1,
        Text = "0",
        TextColor3 = CONFIG.Colors.Gold,
        TextSize = 18,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, currencyDisplay.Gold)
    
    -- Gems Display
    currencyDisplay.Gems = create("Frame", {
        Name = "GemsDisplay",
        Size = UDim2.new(0, 120, 0, 40),
        Position = UDim2.new(0, 180, 0, 10),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, topBar)
    createCorner(20).Parent = currencyDisplay.Gems
    
    create("TextLabel", {
        Name = "Icon",
        Size = UDim2.new(0, 30, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = "💎",
        TextSize = 20,
    }, currencyDisplay.Gems)
    
    currencyDisplay.GemsLabel = create("TextLabel", {
        Name = "Amount",
        Size = UDim2.new(1, -50, 1, 0),
        Position = UDim2.new(0, 40, 0, 0),
        BackgroundTransparency = 1,
        Text = "0",
        TextColor3 = CONFIG.Colors.Gems,
        TextSize = 18,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, currencyDisplay.Gems)
    
    -- Passive Income Display
    passiveIncomeDisplay = create("Frame", {
        Name = "PassiveIncome",
        Size = UDim2.new(0, 180, 0, 40),
        Position = UDim2.new(0.5, -90, 0, 10),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, topBar)
    createCorner(20).Parent = passiveIncomeDisplay
    
    create("TextLabel", {
        Name = "Label",
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = "Einkommen:",
        TextColor3 = CONFIG.Colors.TextMuted,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, passiveIncomeDisplay)
    
    passiveIncomeDisplay.AmountLabel = create("TextLabel", {
        Name = "Amount",
        Size = UDim2.new(0.5, -10, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = "+0/min",
        TextColor3 = CONFIG.Colors.Gold,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, passiveIncomeDisplay)
    
    -- Collect Button
    local collectButton = create("TextButton", {
        Name = "CollectButton",
        Size = UDim2.new(0, 100, 0, 40),
        Position = UDim2.new(0.5, 100, 0, 10),
        BackgroundColor3 = CONFIG.Colors.Success,
        Text = "Abholen",
        TextColor3 = CONFIG.Colors.Text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
    }, topBar)
    createCorner(20).Parent = collectButton
    
    collectButton.MouseButton1Click:Connect(function()
        UIController.Signals.ButtonClicked:Fire("CollectPassive")
        UIController.CollectPassiveIncome()
    end)
    
    -- Settings Button (rechts oben)
    local settingsButton = create("TextButton", {
        Name = "SettingsButton",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(1, -60, 0, 10),
        BackgroundColor3 = CONFIG.Colors.Surface,
        Text = "⚙️",
        TextSize = 20,
    }, topBar)
    createCorner(20).Parent = settingsButton
    
    settingsButton.MouseButton1Click:Connect(function()
        UIController.Signals.ButtonClicked:Fire("Settings")
        UIController.ShowPopup("Settings")
    end)
    
    -- Bottom Navigation
    local bottomNav = create("Frame", {
        Name = "BottomNav",
        Size = UDim2.new(1, 0, 0, 80),
        Position = UDim2.new(0, 0, 1, -80),
        BackgroundColor3 = CONFIG.Colors.Background,
        BackgroundTransparency = 0.2,
    }, hudFrame)
    createCorner(16).Parent = bottomNav
    
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 10),
    }, bottomNav)
    
    menuButtons = {}
    
    local navItems = {
        { Name = "Dungeon", Icon = "🏰", Screen = "Dungeon" },
        { Name = "Shop", Icon = "🛒", Screen = "Shop" },
        { Name = "Helden", Icon = "⚔️", Screen = "Heroes" },
        { Name = "Raid", Icon = "🎯", Screen = "Raid" },
        { Name = "Prestige", Icon = "⭐", Screen = "Prestige" },
    }
    
    for _, item in ipairs(navItems) do
        local button = create("TextButton", {
            Name = item.Name .. "Button",
            Size = UDim2.new(0, 70, 0, 60),
            BackgroundColor3 = CONFIG.Colors.Surface,
            BackgroundTransparency = 0.5,
            Text = "",
        }, bottomNav)
        createCorner(12).Parent = button
        
        create("TextLabel", {
            Name = "Icon",
            Size = UDim2.new(1, 0, 0, 30),
            Position = UDim2.new(0, 0, 0, 5),
            BackgroundTransparency = 1,
            Text = item.Icon,
            TextSize = 24,
        }, button)
        
        create("TextLabel", {
            Name = "Label",
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 0, 35),
            BackgroundTransparency = 1,
            Text = item.Name,
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 10,
            Font = Enum.Font.Gotham,
        }, button)
        
        button.MouseButton1Click:Connect(function()
            UIController.Signals.ButtonClicked:Fire("Nav_" .. item.Name)
            UIController.ShowScreen(item.Screen)
        end)
        
        menuButtons[item.Screen] = button
    end
    
    return hudFrame
end

-------------------------------------------------
-- UI CREATION - LOADING SCREEN
-------------------------------------------------

local function createLoadingScreen()
    local loading = create("Frame", {
        Name = "LoadingScreen",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = CONFIG.Colors.Background,
        ZIndex = 100,
    }, screenGui)
    
    create("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 60),
        Position = UDim2.new(0, 0, 0.35, 0),
        BackgroundTransparency = 1,
        Text = "🏰 DUNGEON TYCOON",
        TextColor3 = CONFIG.Colors.Text,
        TextSize = 48,
        Font = Enum.Font.GothamBold,
    }, loading)
    
    local loadingText = create("TextLabel", {
        Name = "LoadingText",
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundTransparency = 1,
        Text = "Lädt...",
        TextColor3 = CONFIG.Colors.TextMuted,
        TextSize = 18,
        Font = Enum.Font.Gotham,
    }, loading)
    
    -- Spinner
    local spinner = create("Frame", {
        Name = "Spinner",
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0.5, -20, 0.55, 0),
        BackgroundColor3 = CONFIG.Colors.Primary,
        Rotation = 0,
    }, loading)
    createCorner(20).Parent = spinner
    
    -- Spinner Animation
    task.spawn(function()
        while loading and loading.Parent do
            for i = 0, 360, 10 do
                if not loading or not loading.Parent then break end
                spinner.Rotation = i
                task.wait(0.02)
            end
        end
    end)
    
    screens.Loading = loading
    return loading
end

-------------------------------------------------
-- UI CREATION - NOTIFICATION CONTAINER
-------------------------------------------------

local function createNotificationContainer()
    local container = create("Frame", {
        Name = "NotificationContainer",
        Size = UDim2.new(0, 350, 1, -150),
        Position = UDim2.new(1, -370, 0, 70),
        BackgroundTransparency = 1,
        ZIndex = 90,
    }, screenGui)
    
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Padding = UDim.new(0, 10),
    }, container)
    
    return container
end

-------------------------------------------------
-- UI CREATION - POPUP OVERLAY
-------------------------------------------------

local function createPopupOverlay()
    local overlay = create("Frame", {
        Name = "PopupOverlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 50,
    }, screenGui)
    
    overlay.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            UIController.ClosePopup()
        end
    end)
    
    return overlay
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den UIController
    @param dataControllerRef: Referenz zum DataController
    @param clientStateRef: Referenz zum ClientState
]]
function UIController.Initialize(dataControllerRef, clientStateRef)
    debugPrint("Initialisiere UIController...")
    
    DataController = dataControllerRef
    ClientState = clientStateRef
    
    -- ScreenGui erstellen
    createScreenGui()
    
    -- Loading Screen erstellen
    createLoadingScreen()
    
    -- HUD erstellen
    createHUD()
    
    -- Notification Container
    createNotificationContainer()
    
    -- Popup Overlay
    createPopupOverlay()
    
    -- DataController Signals verbinden
    DataController.Signals.CurrencyChanged:Connect(function()
        UIController.UpdateCurrencyDisplay()
    end)
    
    DataController.Signals.DungeonChanged:Connect(function()
        UIController.UpdateDungeonDisplay()
    end)
    
    debugPrint("UIController initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - LOADING SCREEN
-------------------------------------------------

--[[
    Zeigt Loading Screen mit Text
    @param text: Anzuzeigender Text
]]
function UIController.ShowLoadingScreen(text)
    local loading = screens.Loading
    if not loading then return end
    
    local loadingText = loading:FindFirstChild("LoadingText")
    if loadingText then
        loadingText.Text = text or "Lädt..."
    end
    
    loading.Visible = true
    loading.BackgroundTransparency = 0
end

--[[
    Versteckt Loading Screen
]]
function UIController.HideLoadingScreen()
    local loading = screens.Loading
    if not loading then return end
    
    tween(loading, { BackgroundTransparency = 1 }, 0.5)
    task.delay(0.5, function()
        loading.Visible = false
    end)
end

-------------------------------------------------
-- PUBLIC API - HUD UPDATES
-------------------------------------------------

--[[
    Aktualisiert Währungsanzeige
]]
function UIController.UpdateCurrencyDisplay()
    if not currencyDisplay then return end
    
    local currency = DataController.GetFormattedCurrency()
    
    if currencyDisplay.GoldLabel then
        local newText = CurrencyUtil.FormatNumber(DataController.GetGold())
        currencyDisplay.GoldLabel.Text = newText
    end
    
    if currencyDisplay.GemsLabel then
        local newText = CurrencyUtil.FormatNumber(DataController.GetGems())
        currencyDisplay.GemsLabel.Text = newText
    end
end

--[[
    Aktualisiert Dungeon-Anzeige
]]
function UIController.UpdateDungeonDisplay()
    -- Wird von spezifischen Screens implementiert
end

--[[
    Aktualisiert Helden-Anzeige
]]
function UIController.UpdateHeroesDisplay()
    -- Wird von spezifischen Screens implementiert
end

--[[
    Aktualisiert Passiv-Einkommen Timer
]]
function UIController.UpdatePassiveIncomeTimer()
    if not passiveIncomeDisplay then return end
    
    local incomePerMin = DataController.GetPassiveIncomePerMinute()
    local pending = DataController.GetPendingPassiveIncome()
    
    local amountLabel = passiveIncomeDisplay:FindFirstChild("Amount")
    if amountLabel then
        amountLabel.Text = "+" .. CurrencyUtil.FormatNumber(incomePerMin) .. "/min"
    end
end

--[[
    Aktualisiert Cooldown-Timer
]]
function UIController.UpdateCooldownTimers()
    local raidCooldown = DataController.GetRaidCooldown()
    
    -- Update Raid Button wenn nötig
    if menuButtons and menuButtons.Raid then
        local label = menuButtons.Raid:FindFirstChild("Label")
        if label then
            if raidCooldown > 0 then
                label.Text = formatTime(raidCooldown)
                label.TextColor3 = CONFIG.Colors.Warning
            else
                label.Text = "Raid"
                label.TextColor3 = CONFIG.Colors.TextMuted
            end
        end
    end
end

-------------------------------------------------
-- PUBLIC API - SCREEN MANAGEMENT
-------------------------------------------------

--[[
    Zeigt einen Screen an
    @param screenName: Name des Screens
]]
function UIController.ShowScreen(screenName)
    debugPrint("Zeige Screen: " .. screenName)
    
    local oldScreen = activeScreen
    
    -- Alten Screen ausblenden
    if oldScreen and screens[oldScreen] then
        tween(screens[oldScreen], { BackgroundTransparency = 1 }, CONFIG.FadeTime)
        task.delay(CONFIG.FadeTime, function()
            if screens[oldScreen] then
                screens[oldScreen].Visible = false
            end
        end)
    end
    
    -- Neuen Screen anzeigen
    if screens[screenName] then
        screens[screenName].Visible = true
        screens[screenName].BackgroundTransparency = 1
        tween(screens[screenName], { BackgroundTransparency = 0 }, CONFIG.FadeTime)
    end
    
    -- Menu Buttons updaten
    for name, button in pairs(menuButtons or {}) do
        if name == screenName then
            button.BackgroundTransparency = 0
            button.BackgroundColor3 = CONFIG.Colors.Primary
        else
            button.BackgroundTransparency = 0.5
            button.BackgroundColor3 = CONFIG.Colors.Surface
        end
    end
    
    activeScreen = screenName
    UIController.Signals.ScreenChanged:Fire(screenName, oldScreen)
end

--[[
    Zeigt das Main HUD an
]]
function UIController.ShowMainHUD()
    if hudFrame then
        hudFrame.Visible = true
    end
    
    UIController.UpdateCurrencyDisplay()
    UIController.ShowScreen("Dungeon")
end

--[[
    Versteckt das Main HUD
]]
function UIController.HideMainHUD()
    if hudFrame then
        hudFrame.Visible = false
    end
end

-------------------------------------------------
-- PUBLIC API - NOTIFICATIONS
-------------------------------------------------

--[[
    Zeigt eine Notification an
    @param title: Titel
    @param message: Nachricht
    @param notifType: Typ (Success, Error, Warning, Info)
]]
function UIController.ShowNotification(title, message, notifType)
    local container = screenGui:FindFirstChild("NotificationContainer")
    if not container then return end
    
    -- Farbe basierend auf Typ
    local color = CONFIG.Colors.Info
    local icon = "ℹ️"
    
    if notifType == "Success" then
        color = CONFIG.Colors.Success
        icon = "✅"
    elseif notifType == "Error" then
        color = CONFIG.Colors.Error
        icon = "❌"
    elseif notifType == "Warning" then
        color = CONFIG.Colors.Warning
        icon = "⚠️"
    end
    
    -- Notification erstellen
    local notif = create("Frame", {
        Name = "Notification",
        Size = UDim2.new(1, 0, 0, 70),
        BackgroundColor3 = CONFIG.Colors.Surface,
        BackgroundTransparency = 0.1,
    }, container)
    createCorner(12).Parent = notif
    createStroke(color, 2).Parent = notif
    
    -- Icon
    create("TextLabel", {
        Name = "Icon",
        Size = UDim2.new(0, 40, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = icon,
        TextSize = 24,
    }, notif)
    
    -- Title
    create("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -70, 0, 25),
        Position = UDim2.new(0, 55, 0, 10),
        BackgroundTransparency = 1,
        Text = title or "Notification",
        TextColor3 = CONFIG.Colors.Text,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)
    
    -- Message
    create("TextLabel", {
        Name = "Message",
        Size = UDim2.new(1, -70, 0, 25),
        Position = UDim2.new(0, 55, 0, 35),
        BackgroundTransparency = 1,
        Text = message or "",
        TextColor3 = CONFIG.Colors.TextMuted,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, notif)
    
    -- Einblend-Animation
    notif.Position = UDim2.new(1, 50, 0, 0)
    tween(notif, { Position = UDim2.new(0, 0, 0, 0) }, CONFIG.SlideTime)
    
    -- In Liste einfügen
    table.insert(notifications, notif)
    
    -- Max Notifications begrenzen
    while #notifications > CONFIG.MaxNotifications do
        local oldest = table.remove(notifications, 1)
        if oldest and oldest.Parent then
            oldest:Destroy()
        end
    end
    
    -- Auto-Remove nach Dauer
    task.delay(CONFIG.NotificationDuration, function()
        if notif and notif.Parent then
            tween(notif, { Position = UDim2.new(1, 50, 0, 0) }, CONFIG.SlideTime)
            task.delay(CONFIG.SlideTime, function()
                if notif and notif.Parent then
                    notif:Destroy()
                end
                
                -- Aus Liste entfernen
                for i, n in ipairs(notifications) do
                    if n == notif then
                        table.remove(notifications, i)
                        break
                    end
                end
            end)
        end
    end)
end

-------------------------------------------------
-- PUBLIC API - POPUPS
-------------------------------------------------

--[[
    Zeigt ein Popup an
    @param popupName: Name des Popups
    @param data: Optionale Daten
]]
function UIController.ShowPopup(popupName, data)
    local overlay = screenGui:FindFirstChild("PopupOverlay")
    if not overlay then return end
    
    -- Overlay anzeigen
    overlay.Visible = true
    tween(overlay, { BackgroundTransparency = 0.7 }, CONFIG.FadeTime)
    
    activePopup = popupName
    UIController.Signals.PopupOpened:Fire(popupName)
    
    debugPrint("Popup geöffnet: " .. popupName)
end

--[[
    Schließt das aktive Popup
]]
function UIController.ClosePopup()
    if not activePopup then return end
    
    local overlay = screenGui:FindFirstChild("PopupOverlay")
    if overlay then
        tween(overlay, { BackgroundTransparency = 1 }, CONFIG.FadeTime)
        task.delay(CONFIG.FadeTime, function()
            overlay.Visible = false
        end)
    end
    
    local closedPopup = activePopup
    activePopup = nil
    
    UIController.Signals.PopupClosed:Fire(closedPopup)
    debugPrint("Popup geschlossen: " .. closedPopup)
end

-------------------------------------------------
-- PUBLIC API - SPEZIELLE SCREENS
-------------------------------------------------

--[[
    Zeigt Error-Screen an
    @param title: Titel
    @param message: Nachricht
]]
function UIController.ShowError(title, message)
    UIController.HideLoadingScreen()
    UIController.ShowNotification(title, message, "Error")
end

--[[
    Zeigt Level-Up Animation
    @param newLevel: Neues Level
]]
function UIController.ShowLevelUpAnimation(newLevel)
    UIController.ShowNotification(
        "Level Up!",
        "Dein Dungeon ist jetzt Level " .. newLevel .. "!",
        "Success"
    )
end

--[[
    Zeigt Tutorial-Schritt
    @param stepName: Name des Schritts
]]
function UIController.ShowTutorial(stepName)
    debugPrint("Tutorial-Schritt: " .. stepName)
    -- TODO: Implementiere Tutorial-UI
end

--[[
    Zeigt Raid-Screen
    @param raidData: Raid-Daten
]]
function UIController.ShowRaidScreen(raidData)
    DataController.SetActiveRaid(raidData)
    UIController.HideMainHUD()
    -- TODO: Implementiere Raid-Screen
end

--[[
    Aktualisiert Raid-Combat
    @param data: Combat-Tick Daten
]]
function UIController.UpdateRaidCombat(data)
    -- TODO: Implementiere Raid-Combat UI Updates
end

--[[
    Zeigt Raid-Ergebnis
    @param data: Ergebnis-Daten
]]
function UIController.ShowRaidResult(data)
    DataController.SetActiveRaid(nil)
    UIController.ShowMainHUD()
    
    local status = data.Status == "Victory" and "Sieg!" or "Niederlage"
    local message = string.format(
        "%d/%d Räume | %s Gold | %s Gems",
        data.Stats.RoomsCleared or 0,
        data.Stats.RoomsTotal or 0,
        CurrencyUtil.FormatNumber(data.Rewards.Gold or 0),
        CurrencyUtil.FormatNumber(data.Rewards.Gems or 0)
    )
    
    UIController.ShowNotification("Raid " .. status, message, data.Status == "Victory" and "Success" or "Warning")
end

--[[
    Zeigt Defense-Alert
    @param attackerName: Name des Angreifers
    @param attackerLevel: Level des Angreifers
]]
function UIController.ShowDefenseAlert(attackerName, attackerLevel)
    UIController.ShowNotification(
        "⚔️ Angriff!",
        attackerName .. " (Lv." .. attackerLevel .. ") greift deinen Dungeon an!",
        "Warning"
    )
end

--[[
    Zeigt Defense-Ergebnis
    @param data: Ergebnis-Daten
]]
function UIController.ShowDefenseResult(data)
    local status = data.AttackerWon and "Dungeon gefallen" or "Verteidigung erfolgreich!"
    local notifType = data.AttackerWon and "Warning" or "Success"
    
    local message = string.format(
        "%s hat %d Räume geschafft",
        data.AttackerName,
        data.RoomsCleared or 0
    )
    
    UIController.ShowNotification(status, message, notifType)
end

--[[
    Aktualisiert Inbox-Badge
]]
function UIController.UpdateInboxBadge()
    local count = DataController.GetUnreadInboxCount()
    -- TODO: Update Badge UI
end

-------------------------------------------------
-- PUBLIC API - ACTIONS
-------------------------------------------------

--[[
    Sammelt passives Einkommen
]]
function UIController.CollectPassiveIncome()
    local result = RemoteIndex.Invoke("Currency_CollectPassive")
    
    if result and result.Success then
        UIController.ShowNotification(
            "Einkommen gesammelt!",
            "+" .. CurrencyUtil.FormatNumber(result.Amount) .. " Gold",
            "Success"
        )
    elseif result then
        UIController.ShowNotification("Fehler", result.Error or "Unbekannter Fehler", "Error")
    end
end

return UIController
