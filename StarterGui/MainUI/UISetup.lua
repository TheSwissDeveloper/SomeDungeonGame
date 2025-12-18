--[[
    UISetup.lua
    Erstellt die komplette UI-Struktur
    Pfad: StarterGui/MainUI/UISetup
    
    Dieses Script:
    - Erstellt alle UI-Frames und Komponenten
    - Initialisiert Screen-Module
    - Verbindet Events
    
    WICHTIG: Dies ist ein LOCALSCRIPT in StarterGui!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")

local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))

print("[UISetup] Starte UI-Erstellung...")

-------------------------------------------------
-- UI KONFIGURATION
-------------------------------------------------
local UI_CONFIG = {
    -- Farben (Dark Theme)
    Colors = {
        Background = Color3.fromRGB(15, 23, 42),        -- Slate-900
        Surface = Color3.fromRGB(30, 41, 59),           -- Slate-800
        SurfaceLight = Color3.fromRGB(51, 65, 85),      -- Slate-700
        Primary = Color3.fromRGB(99, 102, 241),         -- Indigo-500
        PrimaryDark = Color3.fromRGB(79, 70, 229),      -- Indigo-600
        Secondary = Color3.fromRGB(139, 92, 246),       -- Violet-500
        Success = Color3.fromRGB(34, 197, 94),          -- Green-500
        Warning = Color3.fromRGB(234, 179, 8),          -- Yellow-500
        Error = Color3.fromRGB(239, 68, 68),            -- Red-500
        Info = Color3.fromRGB(59, 130, 246),            -- Blue-500
        Gold = Color3.fromRGB(251, 191, 36),            -- Amber-400
        Gems = Color3.fromRGB(168, 85, 247),            -- Purple-500
        Text = Color3.fromRGB(248, 250, 252),           -- Slate-50
        TextMuted = Color3.fromRGB(148, 163, 184),      -- Slate-400
        TextDark = Color3.fromRGB(100, 116, 139),       -- Slate-500
        Border = Color3.fromRGB(71, 85, 105),           -- Slate-600
    },
    
    -- Fonts
    Fonts = {
        Title = Enum.Font.GothamBold,
        Body = Enum.Font.Gotham,
        Button = Enum.Font.GothamMedium,
    },
    
    -- Sizes
    Sizes = {
        CornerRadius = 12,
        CornerRadiusSmall = 8,
        CornerRadiusLarge = 16,
        Padding = 12,
        PaddingSmall = 8,
        PaddingLarge = 16,
    },
}

-------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------

-- Erstellt UI-Element mit Properties
local function create(className, properties, children)
    local instance = Instance.new(className)
    
    for prop, value in pairs(properties or {}) do
        instance[prop] = value
    end
    
    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end
    
    return instance
end

-- Erstellt UICorner
local function corner(radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or UI_CONFIG.Sizes.CornerRadius)
    })
end

-- Erstellt UIPadding
local function padding(all, top, bottom, left, right)
    if type(all) == "number" and not top then
        return create("UIPadding", {
            PaddingTop = UDim.new(0, all),
            PaddingBottom = UDim.new(0, all),
            PaddingLeft = UDim.new(0, all),
            PaddingRight = UDim.new(0, all),
        })
    end
    return create("UIPadding", {
        PaddingTop = UDim.new(0, top or all or 0),
        PaddingBottom = UDim.new(0, bottom or all or 0),
        PaddingLeft = UDim.new(0, left or all or 0),
        PaddingRight = UDim.new(0, right or all or 0),
    })
end

-- Erstellt UIStroke
local function stroke(color, thickness, transparency)
    return create("UIStroke", {
        Color = color or UI_CONFIG.Colors.Border,
        Thickness = thickness or 1,
        Transparency = transparency or 0.5,
    })
end

-- Erstellt UIListLayout
local function listLayout(direction, alignment, vAlignment, gap)
    return create("UIListLayout", {
        FillDirection = direction or Enum.FillDirection.Vertical,
        HorizontalAlignment = alignment or Enum.HorizontalAlignment.Center,
        VerticalAlignment = vAlignment or Enum.VerticalAlignment.Top,
        Padding = UDim.new(0, gap or UI_CONFIG.Sizes.PaddingSmall),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
end

-- Erstellt UIGridLayout
local function gridLayout(cellSize, gap)
    return create("UIGridLayout", {
        CellSize = cellSize or UDim2.new(0, 100, 0, 100),
        CellPadding = UDim2.new(0, gap or 10, 0, gap or 10),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
end

-------------------------------------------------
-- MAIN SCREENGUI
-------------------------------------------------

local mainUI = create("ScreenGui", {
    Name = "MainUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, {})

mainUI.Parent = PlayerGui

-------------------------------------------------
-- HUD (Top Bar)
-------------------------------------------------

local hud = create("Frame", {
    Name = "HUD",
    Size = UDim2.new(1, 0, 0, 70),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundTransparency = 1,
    ZIndex = 10,
}, {
    -- Hintergrund mit Gradient
    create("Frame", {
        Name = "Background",
        Size = UDim2.new(1, 0, 1, 20),
        BackgroundColor3 = UI_CONFIG.Colors.Background,
    }, {
        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.7, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    }),
    
    -- Content Container
    create("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 20, 0, 0),
        BackgroundTransparency = 1,
    }, {
        -- Gold Display
        create("Frame", {
            Name = "GoldDisplay",
            Size = UDim2.new(0, 140, 0, 44),
            Position = UDim2.new(0, 0, 0.5, -22),
            BackgroundColor3 = UI_CONFIG.Colors.Surface,
        }, {
            corner(22),
            stroke(),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(0, 36, 0, 36),
                Position = UDim2.new(0, 4, 0.5, -18),
                BackgroundTransparency = 1,
                Text = "💰",
                TextSize = 22,
            }),
            create("TextLabel", {
                Name = "Amount",
                Size = UDim2.new(1, -48, 1, 0),
                Position = UDim2.new(0, 44, 0, 0),
                BackgroundTransparency = 1,
                Text = "0",
                TextColor3 = UI_CONFIG.Colors.Gold,
                TextSize = 18,
                Font = UI_CONFIG.Fonts.Title,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
        }),
        
        -- Gems Display
        create("Frame", {
            Name = "GemsDisplay",
            Size = UDim2.new(0, 120, 0, 44),
            Position = UDim2.new(0, 150, 0.5, -22),
            BackgroundColor3 = UI_CONFIG.Colors.Surface,
        }, {
            corner(22),
            stroke(),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(0, 36, 0, 36),
                Position = UDim2.new(0, 4, 0.5, -18),
                BackgroundTransparency = 1,
                Text = "💎",
                TextSize = 22,
            }),
            create("TextLabel", {
                Name = "Amount",
                Size = UDim2.new(1, -48, 1, 0),
                Position = UDim2.new(0, 44, 0, 0),
                BackgroundTransparency = 1,
                Text = "0",
                TextColor3 = UI_CONFIG.Colors.Gems,
                TextSize = 18,
                Font = UI_CONFIG.Fonts.Title,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
        }),
        
        -- Passive Income Display (Mitte)
        create("Frame", {
            Name = "IncomeDisplay",
            Size = UDim2.new(0, 200, 0, 44),
            Position = UDim2.new(0.5, -100, 0.5, -22),
            BackgroundColor3 = UI_CONFIG.Colors.Surface,
        }, {
            corner(22),
            stroke(UI_CONFIG.Colors.Gold, 1, 0.7),
            create("TextLabel", {
                Name = "Label",
                Size = UDim2.new(0.5, 0, 1, 0),
                Position = UDim2.new(0, 12, 0, 0),
                BackgroundTransparency = 1,
                Text = "Einkommen:",
                TextColor3 = UI_CONFIG.Colors.TextMuted,
                TextSize = 12,
                Font = UI_CONFIG.Fonts.Body,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("TextLabel", {
                Name = "Amount",
                Size = UDim2.new(0.5, -12, 1, 0),
                Position = UDim2.new(0.5, 0, 0, 0),
                BackgroundTransparency = 1,
                Text = "+0/min",
                TextColor3 = UI_CONFIG.Colors.Gold,
                TextSize = 14,
                Font = UI_CONFIG.Fonts.Title,
                TextXAlignment = Enum.TextXAlignment.Right,
            }),
        }),
        
        -- Collect Button
        create("TextButton", {
            Name = "CollectButton",
            Size = UDim2.new(0, 100, 0, 44),
            Position = UDim2.new(0.5, 110, 0.5, -22),
            BackgroundColor3 = UI_CONFIG.Colors.Success,
            Text = "Abholen",
            TextColor3 = UI_CONFIG.Colors.Text,
            TextSize = 14,
            Font = UI_CONFIG.Fonts.Button,
            AutoButtonColor = true,
        }, {
            corner(22),
        }),
        
        -- Level Display (Rechts)
        create("Frame", {
            Name = "LevelDisplay",
            Size = UDim2.new(0, 100, 0, 44),
            Position = UDim2.new(1, -220, 0.5, -22),
            BackgroundColor3 = UI_CONFIG.Colors.Surface,
        }, {
            corner(22),
            stroke(UI_CONFIG.Colors.Primary, 1, 0.5),
            create("TextLabel", {
                Name = "Label",
                Size = UDim2.new(1, 0, 0.5, 0),
                Position = UDim2.new(0, 0, 0, 2),
                BackgroundTransparency = 1,
                Text = "LEVEL",
                TextColor3 = UI_CONFIG.Colors.TextMuted,
                TextSize = 10,
                Font = UI_CONFIG.Fonts.Body,
            }),
            create("TextLabel", {
                Name = "Value",
                Size = UDim2.new(1, 0, 0.5, 0),
                Position = UDim2.new(0, 0, 0.5, -2),
                BackgroundTransparency = 1,
                Text = "1",
                TextColor3 = UI_CONFIG.Colors.Primary,
                TextSize = 20,
                Font = UI_CONFIG.Fonts.Title,
            }),
        }),
        
        -- Settings Button (Rechts außen)
        create("TextButton", {
            Name = "SettingsButton",
            Size = UDim2.new(0, 44, 0, 44),
            Position = UDim2.new(1, -44, 0.5, -22),
            BackgroundColor3 = UI_CONFIG.Colors.Surface,
            Text = "⚙️",
            TextSize = 22,
            AutoButtonColor = true,
        }, {
            corner(22),
            stroke(),
        }),
    }),
})

hud.Parent = mainUI

-------------------------------------------------
-- BOTTOM NAVIGATION
-------------------------------------------------

local bottomNav = create("Frame", {
    Name = "BottomNav",
    Size = UDim2.new(1, 0, 0, 90),
    Position = UDim2.new(0, 0, 1, -90),
    BackgroundColor3 = UI_CONFIG.Colors.Background,
    ZIndex = 10,
}, {
    corner(UI_CONFIG.Sizes.CornerRadiusLarge),
    stroke(UI_CONFIG.Colors.Border, 1, 0.7),
    
    -- Nav Items Container
    create("Frame", {
        Name = "NavItems",
        Size = UDim2.new(1, -20, 1, -10),
        Position = UDim2.new(0, 10, 0, 5),
        BackgroundTransparency = 1,
    }, {
        listLayout(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center, 8),
    }),
})

-- Nav Items erstellen
local navItems = {
    { Name = "Dungeon", Icon = "🏰", Label = "Dungeon" },
    { Name = "Shop", Icon = "🛒", Label = "Shop" },
    { Name = "Heroes", Icon = "⚔️", Label = "Helden" },
    { Name = "Raid", Icon = "🎯", Label = "Raid" },
    { Name = "Prestige", Icon = "⭐", Label = "Prestige" },
}

for i, item in ipairs(navItems) do
    local navButton = create("TextButton", {
        Name = item.Name .. "Button",
        Size = UDim2.new(0, 70, 0, 70),
        BackgroundColor3 = i == 1 and UI_CONFIG.Colors.Primary or UI_CONFIG.Colors.Surface,
        BackgroundTransparency = i == 1 and 0 or 0.5,
        Text = "",
        AutoButtonColor = true,
        LayoutOrder = i,
    }, {
        corner(UI_CONFIG.Sizes.CornerRadius),
        create("TextLabel", {
            Name = "Icon",
            Size = UDim2.new(1, 0, 0, 32),
            Position = UDim2.new(0, 0, 0, 8),
            BackgroundTransparency = 1,
            Text = item.Icon,
            TextSize = 26,
        }),
        create("TextLabel", {
            Name = "Label",
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 1, -24),
            BackgroundTransparency = 1,
            Text = item.Label,
            TextColor3 = i == 1 and UI_CONFIG.Colors.Text or UI_CONFIG.Colors.TextMuted,
            TextSize = 11,
            Font = UI_CONFIG.Fonts.Body,
        }),
    })
    
    navButton.Parent = bottomNav.NavItems
end

bottomNav.Parent = mainUI

-------------------------------------------------
-- SCREENS CONTAINER
-------------------------------------------------

local screensContainer = create("Frame", {
    Name = "Screens",
    Size = UDim2.new(1, 0, 1, -160),  -- Abzüglich HUD und BottomNav
    Position = UDim2.new(0, 0, 0, 70),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
})

screensContainer.Parent = mainUI

-- Einzelne Screens erstellen
local screenNames = { "Dungeon", "Shop", "Heroes", "Raid", "Prestige" }

for i, screenName in ipairs(screenNames) do
    local screen = create("Frame", {
        Name = screenName .. "Screen",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = UI_CONFIG.Colors.Background,
        Visible = i == 1,  -- Nur erster Screen sichtbar
    }, {
        padding(UI_CONFIG.Sizes.Padding),
        
        -- Screen Title
        create("TextLabel", {
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
            Text = screenName,
            TextColor3 = UI_CONFIG.Colors.Text,
            TextSize = 28,
            Font = UI_CONFIG.Fonts.Title,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Content Area
        create("Frame", {
            Name = "Content",
            Size = UDim2.new(1, 0, 1, -50),
            Position = UDim2.new(0, 0, 0, 50),
            BackgroundTransparency = 1,
        }),
    })
    
    screen.Parent = screensContainer
end

-------------------------------------------------
-- NOTIFICATION CONTAINER
-------------------------------------------------

local notificationContainer = create("Frame", {
    Name = "Notifications",
    Size = UDim2.new(0, 350, 1, -180),
    Position = UDim2.new(1, -360, 0, 80),
    BackgroundTransparency = 1,
    ZIndex = 50,
}, {
    listLayout(Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top, 10),
})

notificationContainer.Parent = mainUI

-------------------------------------------------
-- POPUP OVERLAY
-------------------------------------------------

local popupOverlay = create("Frame", {
    Name = "PopupOverlay",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 1,
    Visible = false,
    ZIndex = 100,
}, {
    -- Popup Container (zentriert)
    create("Frame", {
        Name = "PopupContainer",
        Size = UDim2.new(0, 400, 0, 300),
        Position = UDim2.new(0.5, -200, 0.5, -150),
        BackgroundColor3 = UI_CONFIG.Colors.Surface,
        ZIndex = 101,
    }, {
        corner(UI_CONFIG.Sizes.CornerRadiusLarge),
        stroke(UI_CONFIG.Colors.Border),
        padding(UI_CONFIG.Sizes.PaddingLarge),
    }),
})

popupOverlay.Parent = mainUI

-------------------------------------------------
-- LOADING SCREEN
-------------------------------------------------

local loadingScreen = create("Frame", {
    Name = "LoadingScreen",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = UI_CONFIG.Colors.Background,
    ZIndex = 200,
}, {
    -- Logo/Title
    create("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 80),
        Position = UDim2.new(0, 0, 0.3, 0),
        BackgroundTransparency = 1,
        Text = "🏰 DUNGEON TYCOON",
        TextColor3 = UI_CONFIG.Colors.Text,
        TextSize = 48,
        Font = UI_CONFIG.Fonts.Title,
    }),
    
    -- Loading Text
    create("TextLabel", {
        Name = "LoadingText",
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundTransparency = 1,
        Text = "Lädt...",
        TextColor3 = UI_CONFIG.Colors.TextMuted,
        TextSize = 18,
        Font = UI_CONFIG.Fonts.Body,
    }),
    
    -- Loading Spinner
    create("Frame", {
        Name = "Spinner",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0.5, -25, 0.55, 0),
        BackgroundColor3 = UI_CONFIG.Colors.Primary,
    }, {
        corner(25),
    }),
    
    -- Version
    create("TextLabel", {
        Name = "Version",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 1, -30),
        BackgroundTransparency = 1,
        Text = "Version 1.0.0",
        TextColor3 = UI_CONFIG.Colors.TextDark,
        TextSize = 12,
        Font = UI_CONFIG.Fonts.Body,
    }),
})

loadingScreen.Parent = mainUI

-- Spinner Animation
task.spawn(function()
    local spinner = loadingScreen:FindFirstChild("Spinner", true)
    while spinner and spinner.Parent do
        for i = 0, 360, 15 do
            if not spinner or not spinner.Parent then break end
            spinner.Rotation = i
            task.wait(0.03)
        end
    end
end)

-------------------------------------------------
-- EXPORT UI CONFIG FÜR ANDERE MODULE
-------------------------------------------------

local UISetupModule = {}
UISetupModule.Config = UI_CONFIG
UISetupModule.MainUI = mainUI

-- Helper Functions exportieren
UISetupModule.Create = create
UISetupModule.Corner = corner
UISetupModule.Padding = padding
UISetupModule.Stroke = stroke
UISetupModule.ListLayout = listLayout
UISetupModule.GridLayout = gridLayout

-- UI Referenzen
UISetupModule.HUD = hud
UISetupModule.BottomNav = bottomNav
UISetupModule.Screens = screensContainer
UISetupModule.Notifications = notificationContainer
UISetupModule.PopupOverlay = popupOverlay
UISetupModule.LoadingScreen = loadingScreen

print("[UISetup] UI-Struktur erstellt!")

return UISetupModule
