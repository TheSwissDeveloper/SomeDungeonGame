--[[
    PrestigeScreen.lua
    Prestige-System und Reset-Optionen
    Pfad: StarterGui/MainUI/Screens/PrestigeScreen
    
    Dieses Script:
    - Zeigt aktuellen Prestige-Status
    - Listet alle Prestige-Boni auf
    - Anforderungen und Fortschritt
    - Prestige-Reset mit Bestätigung
    
    WICHTIG: Wird vom UIManager geladen!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local MainUI = PlayerGui:WaitForChild("MainUI")

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ConfigPath = SharedPath:WaitForChild("Config")
local ModulesPath = SharedPath:WaitForChild("Modules")
local RemotesPath = SharedPath:WaitForChild("Remotes")

local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

local PrestigeScreen = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Layout
    BonusCardSize = UDim2.new(0, 280, 0, 100),
    RequirementHeight = 50,
    
    -- Prestige Settings (aus GameConfig)
    MinLevelForPrestige = GameConfig.Prestige.MinLevel or 25,
    BonusPerPrestige = GameConfig.Prestige.BonusPerPrestige or 0.05,
    MaxPrestige = GameConfig.Prestige.MaxPrestige or 100,
    
    -- Colors
    Colors = {
        Background = Color3.fromRGB(15, 23, 42),
        Surface = Color3.fromRGB(30, 41, 59),
        SurfaceLight = Color3.fromRGB(51, 65, 85),
        SurfaceHover = Color3.fromRGB(71, 85, 105),
        Primary = Color3.fromRGB(99, 102, 241),
        PrimaryDark = Color3.fromRGB(79, 70, 229),
        Success = Color3.fromRGB(34, 197, 94),
        Warning = Color3.fromRGB(234, 179, 8),
        Error = Color3.fromRGB(239, 68, 68),
        Gold = Color3.fromRGB(251, 191, 36),
        Gems = Color3.fromRGB(168, 85, 247),
        Text = Color3.fromRGB(248, 250, 252),
        TextMuted = Color3.fromRGB(148, 163, 184),
        TextDark = Color3.fromRGB(100, 116, 139),
        Border = Color3.fromRGB(71, 85, 105),
        
        -- Prestige Colors (Gradient basierend auf Level)
        PrestigeBronze = Color3.fromRGB(205, 127, 50),
        PrestigeSilver = Color3.fromRGB(192, 192, 192),
        PrestigeGold = Color3.fromRGB(255, 215, 0),
        PrestigePlatinum = Color3.fromRGB(229, 228, 226),
        PrestigeDiamond = Color3.fromRGB(185, 242, 255),
        PrestigeMaster = Color3.fromRGB(255, 0, 128),
    },
}

-------------------------------------------------
-- PRESTIGE BONUSES
-------------------------------------------------
local PRESTIGE_BONUSES = {
    {
        Id = "income_boost",
        Name = "Einkommen-Boost",
        Description = "+5% passives Einkommen pro Prestige",
        Icon = "💰",
        ValuePerPrestige = 5,
        Unit = "%",
        Color = CONFIG.Colors.Gold,
    },
    {
        Id = "raid_rewards",
        Name = "Raid-Belohnungen",
        Description = "+3% mehr Raid-Belohnungen pro Prestige",
        Icon = "🎯",
        ValuePerPrestige = 3,
        Unit = "%",
        Color = CONFIG.Colors.Success,
    },
    {
        Id = "hero_xp",
        Name = "Helden-XP",
        Description = "+2% mehr Helden-XP pro Prestige",
        Icon = "⚔️",
        ValuePerPrestige = 2,
        Unit = "%",
        Color = CONFIG.Colors.Primary,
    },
    {
        Id = "trap_damage",
        Name = "Fallen-Schaden",
        Description = "+2% mehr Fallen-Schaden pro Prestige",
        Icon = "🪤",
        ValuePerPrestige = 2,
        Unit = "%",
        Color = CONFIG.Colors.Error,
    },
    {
        Id = "monster_hp",
        Name = "Monster-HP",
        Description = "+2% mehr Monster-HP pro Prestige",
        Icon = "👹",
        ValuePerPrestige = 2,
        Unit = "%",
        Color = CONFIG.Colors.Warning,
    },
    {
        Id = "unlock_discount",
        Name = "Freischalt-Rabatt",
        Description = "-1% Freischaltkosten pro Prestige",
        Icon = "🏷️",
        ValuePerPrestige = 1,
        Unit = "%",
        Color = CONFIG.Colors.Gems,
    },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local screenState = {
    CurrentPrestige = 0,
    DungeonLevel = 1,
    CanPrestige = false,
    TotalBonusPercent = 0,
    
    -- Requirements
    RequirementsMet = {
        Level = false,
        Rooms = false,
    },
    
    -- Confirmation State
    ShowingConfirmation = false,
}

-------------------------------------------------
-- UI REFERENCES
-------------------------------------------------
local screenFrame = nil
local contentFrame = nil
local statusPanel = nil
local bonusesPanel = nil
local requirementsPanel = nil
local prestigeButton = nil
local confirmationOverlay = nil

-------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------

local function tween(instance, properties, duration, easingStyle)
    local tweenInfo = TweenInfo.new(duration or 0.3, easingStyle or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = TweenService:Create(instance, tweenInfo, properties)
    t:Play()
    return t
end

local function formatNumber(num)
    return CurrencyUtil.FormatNumber(num)
end

local function getPrestigeColor(prestigeLevel)
    if prestigeLevel >= 50 then
        return CONFIG.Colors.PrestigeMaster
    elseif prestigeLevel >= 40 then
        return CONFIG.Colors.PrestigeDiamond
    elseif prestigeLevel >= 30 then
        return CONFIG.Colors.PrestigePlatinum
    elseif prestigeLevel >= 20 then
        return CONFIG.Colors.PrestigeGold
    elseif prestigeLevel >= 10 then
        return CONFIG.Colors.PrestigeSilver
    else
        return CONFIG.Colors.PrestigeBronze
    end
end

local function getPrestigeTitle(prestigeLevel)
    if prestigeLevel >= 50 then
        return "Meister"
    elseif prestigeLevel >= 40 then
        return "Diamant"
    elseif prestigeLevel >= 30 then
        return "Platin"
    elseif prestigeLevel >= 20 then
        return "Gold"
    elseif prestigeLevel >= 10 then
        return "Silber"
    elseif prestigeLevel >= 1 then
        return "Bronze"
    else
        return "Neuling"
    end
end

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

local function corner(radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(color, thickness, transparency)
    return create("UIStroke", {
        Color = color or CONFIG.Colors.Border,
        Thickness = thickness or 1,
        Transparency = transparency or 0.5,
    })
end

local function padding(all)
    return create("UIPadding", {
        PaddingTop = UDim.new(0, all),
        PaddingBottom = UDim.new(0, all),
        PaddingLeft = UDim.new(0, all),
        PaddingRight = UDim.new(0, all),
    })
end

-------------------------------------------------
-- STATUS PANEL
-------------------------------------------------

local function createStatusPanel()
    local prestigeColor = getPrestigeColor(screenState.CurrentPrestige)
    local prestigeTitle = getPrestigeTitle(screenState.CurrentPrestige)
    
    local panel = create("Frame", {
        Name = "StatusPanel",
        Size = UDim2.new(1, 0, 0, 200),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(16),
        stroke(prestigeColor, 2, 0.3),
        padding(20),
        
        -- Prestige Badge
        create("Frame", {
            Name = "PrestigeBadge",
            Size = UDim2.new(0, 120, 0, 120),
            Position = UDim2.new(0, 20, 0.5, -60),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(60),
            stroke(prestigeColor, 3, 0),
            
            -- Star Icon
            create("TextLabel", {
                Name = "StarIcon",
                Size = UDim2.new(1, 0, 0, 60),
                Position = UDim2.new(0, 0, 0, 15),
                BackgroundTransparency = 1,
                Text = "⭐",
                TextSize = 50,
            }),
            
            -- Prestige Level
            create("TextLabel", {
                Name = "PrestigeLevel",
                Size = UDim2.new(1, 0, 0, 35),
                Position = UDim2.new(0, 0, 0, 70),
                BackgroundTransparency = 1,
                Text = tostring(screenState.CurrentPrestige),
                TextColor3 = prestigeColor,
                TextSize = 28,
                Font = Enum.Font.GothamBold,
            }),
        }),
        
        -- Info Section
        create("Frame", {
            Name = "InfoSection",
            Size = UDim2.new(1, -180, 1, 0),
            Position = UDim2.new(0, 160, 0, 0),
            BackgroundTransparency = 1,
        }, {
            -- Title
            create("TextLabel", {
                Name = "Title",
                Size = UDim2.new(1, 0, 0, 35),
                BackgroundTransparency = 1,
                Text = "Prestige " .. prestigeTitle,
                TextColor3 = prestigeColor,
                TextSize = 26,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            
            -- Subtitle
            create("TextLabel", {
                Name = "Subtitle",
                Size = UDim2.new(1, 0, 0, 20),
                Position = UDim2.new(0, 0, 0, 35),
                BackgroundTransparency = 1,
                Text = "Level " .. screenState.CurrentPrestige .. " / " .. CONFIG.MaxPrestige,
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 14,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            
            -- Progress Bar
            create("Frame", {
                Name = "ProgressBar",
                Size = UDim2.new(1, -20, 0, 16),
                Position = UDim2.new(0, 0, 0, 65),
                BackgroundColor3 = CONFIG.Colors.Background,
            }, {
                corner(8),
                create("Frame", {
                    Name = "Fill",
                    Size = UDim2.new(screenState.CurrentPrestige / CONFIG.MaxPrestige, 0, 1, 0),
                    BackgroundColor3 = prestigeColor,
                }, {
                    corner(8),
                }),
            }),
            
            -- Total Bonus Display
            create("Frame", {
                Name = "TotalBonus",
                Size = UDim2.new(1, 0, 0, 60),
                Position = UDim2.new(0, 0, 0, 95),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            }, {
                corner(10),
                padding(12),
                
                create("TextLabel", {
                    Name = "BonusLabel",
                    Size = UDim2.new(0.5, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "Gesamt-Bonus:",
                    TextColor3 = CONFIG.Colors.TextMuted,
                    TextSize = 14,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
                
                create("TextLabel", {
                    Name = "BonusValue",
                    Size = UDim2.new(0.5, 0, 1, 0),
                    Position = UDim2.new(0.5, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "+" .. (screenState.CurrentPrestige * CONFIG.BonusPerPrestige * 100) .. "%",
                    TextColor3 = CONFIG.Colors.Success,
                    TextSize = 24,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Right,
                }),
            }),
        }),
    })
    
    return panel
end

-------------------------------------------------
-- BONUSES PANEL
-------------------------------------------------

local function createBonusCard(bonusData, prestigeLevel)
    local currentValue = bonusData.ValuePerPrestige * prestigeLevel
    local nextValue = bonusData.ValuePerPrestige * (prestigeLevel + 1)
    
    local card = create("Frame", {
        Name = "Bonus_" .. bonusData.Id,
        Size = CONFIG.BonusCardSize,
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(bonusData.Color, 1, 0.5),
        padding(12),
        
        -- Icon
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(0, 50, 0, 50),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(25),
            stroke(bonusData.Color, 2, 0.3),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = bonusData.Icon,
                TextSize = 26,
            }),
        }),
        
        -- Info
        create("Frame", {
            Name = "Info",
            Size = UDim2.new(1, -65, 1, 0),
            Position = UDim2.new(0, 60, 0, 0),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "Name",
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                Text = bonusData.Name,
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            
            create("TextLabel", {
                Name = "Description",
                Size = UDim2.new(1, 0, 0, 30),
                Position = UDim2.new(0, 0, 0, 20),
                BackgroundTransparency = 1,
                Text = bonusData.Description,
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 11,
                Font = Enum.Font.Gotham,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
            }),
            
            -- Current Value
            create("Frame", {
                Name = "ValueDisplay",
                Size = UDim2.new(1, 0, 0, 22),
                Position = UDim2.new(0, 0, 1, -22),
                BackgroundTransparency = 1,
            }, {
                create("TextLabel", {
                    Name = "CurrentLabel",
                    Size = UDim2.new(0.5, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "Aktuell:",
                    TextColor3 = CONFIG.Colors.TextMuted,
                    TextSize = 11,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
                create("TextLabel", {
                    Name = "CurrentValue",
                    Size = UDim2.new(0.25, 0, 1, 0),
                    Position = UDim2.new(0.35, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "+" .. currentValue .. bonusData.Unit,
                    TextColor3 = bonusData.Color,
                    TextSize = 13,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
                create("TextLabel", {
                    Name = "Arrow",
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = UDim2.new(0.6, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "→",
                    TextColor3 = CONFIG.Colors.TextMuted,
                    TextSize = 14,
                }),
                create("TextLabel", {
                    Name = "NextValue",
                    Size = UDim2.new(0.2, 0, 1, 0),
                    Position = UDim2.new(0.75, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "+" .. nextValue .. bonusData.Unit,
                    TextColor3 = CONFIG.Colors.Success,
                    TextSize = 13,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
            }),
        }),
    })
    
    return card
end

local function createBonusesPanel()
    local panel = create("Frame", {
        Name = "BonusesPanel",
        Size = UDim2.new(0.6, -10, 1, -220),
        Position = UDim2.new(0, 0, 0, 210),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(),
        padding(15),
        
        -- Title
        create("TextLabel", {
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            Text = "🎁 Prestige-Boni",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Bonuses Grid
        create("ScrollingFrame", {
            Name = "BonusesGrid",
            Size = UDim2.new(1, 0, 1, -40),
            Position = UDim2.new(0, 0, 0, 35),
            BackgroundTransparency = 1,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = CONFIG.Colors.Border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, {
            create("UIGridLayout", {
                CellSize = CONFIG.BonusCardSize,
                CellPadding = UDim2.new(0, 10, 0, 10),
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
            }),
        }),
    })
    
    return panel
end

-------------------------------------------------
-- REQUIREMENTS PANEL
-------------------------------------------------

local function createRequirementRow(icon, label, current, required, isMet)
    local row = create("Frame", {
        Name = label,
        Size = UDim2.new(1, 0, 0, CONFIG.RequirementHeight),
        BackgroundColor3 = CONFIG.Colors.SurfaceLight,
    }, {
        corner(8),
        
        -- Status Icon
        create("Frame", {
            Name = "StatusIcon",
            Size = UDim2.new(0, 36, 0, 36),
            Position = UDim2.new(0, 8, 0.5, -18),
            BackgroundColor3 = isMet and CONFIG.Colors.Success or CONFIG.Colors.Error,
        }, {
            corner(18),
            create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = isMet and "✓" or "✗",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 18,
                Font = Enum.Font.GothamBold,
            }),
        }),
        
        -- Icon
        create("TextLabel", {
            Name = "Icon",
            Size = UDim2.new(0, 30, 1, 0),
            Position = UDim2.new(0, 52, 0, 0),
            BackgroundTransparency = 1,
            Text = icon,
            TextSize = 22,
        }),
        
        -- Label
        create("TextLabel", {
            Name = "Label",
            Size = UDim2.new(0.4, 0, 1, 0),
            Position = UDim2.new(0, 85, 0, 0),
            BackgroundTransparency = 1,
            Text = label,
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 14,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Progress
        create("TextLabel", {
            Name = "Progress",
            Size = UDim2.new(0.3, -20, 1, 0),
            Position = UDim2.new(0.7, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = current .. " / " .. required,
            TextColor3 = isMet and CONFIG.Colors.Success or CONFIG.Colors.Warning,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Right,
        }),
    })
    
    return row
end

local function createRequirementsPanel()
    local panel = create("Frame", {
        Name = "RequirementsPanel",
        Size = UDim2.new(0.4, -10, 1, -220),
        Position = UDim2.new(0.6, 10, 0, 210),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(),
        padding(15),
        
        -- Title
        create("TextLabel", {
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            Text = "📋 Anforderungen",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Requirements List
        create("Frame", {
            Name = "RequirementsList",
            Size = UDim2.new(1, 0, 0, 130),
            Position = UDim2.new(0, 0, 0, 40),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", {
                Padding = UDim.new(0, 10),
            }),
        }),
        
        -- Warning Text
        create("Frame", {
            Name = "WarningSection",
            Size = UDim2.new(1, 0, 0, 80),
            Position = UDim2.new(0, 0, 0, 185),
            BackgroundColor3 = CONFIG.Colors.Warning,
            BackgroundTransparency = 0.9,
        }, {
            corner(8),
            stroke(CONFIG.Colors.Warning, 1, 0.5),
            padding(10),
            
            create("TextLabel", {
                Name = "WarningIcon",
                Size = UDim2.new(1, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = "⚠️ Achtung!",
                TextColor3 = CONFIG.Colors.Warning,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
            }),
            
            create("TextLabel", {
                Name = "WarningText",
                Size = UDim2.new(1, 0, 1, -25),
                Position = UDim2.new(0, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = "Prestige setzt deinen Dungeon zurück!\nDu behältst: Helden, Freischaltungen, Achievements",
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 11,
                Font = Enum.Font.Gotham,
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
            }),
        }),
        
        -- Prestige Button
        create("TextButton", {
            Name = "PrestigeButton",
            Size = UDim2.new(1, 0, 0, 55),
            Position = UDim2.new(0, 0, 1, -70),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            Text = "⭐ PRESTIGE",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = false,
        }, {
            corner(27),
            stroke(CONFIG.Colors.Border, 2),
        }),
    })
    
    return panel
end

-------------------------------------------------
-- CONFIRMATION OVERLAY
-------------------------------------------------

local function createConfirmationOverlay()
    local overlay = create("Frame", {
        Name = "ConfirmationOverlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 50,
    }, {
        -- Confirmation Card
        create("Frame", {
            Name = "ConfirmCard",
            Size = UDim2.new(0, 400, 0, 320),
            Position = UDim2.new(0.5, -200, 0.5, -160),
            BackgroundColor3 = CONFIG.Colors.Surface,
            ZIndex = 51,
        }, {
            corner(16),
            stroke(CONFIG.Colors.Warning, 2),
            padding(20),
            
            -- Warning Icon
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 0, 60),
                BackgroundTransparency = 1,
                Text = "⚠️",
                TextSize = 50,
                ZIndex = 52,
            }),
            
            -- Title
            create("TextLabel", {
                Name = "Title",
                Size = UDim2.new(1, 0, 0, 35),
                Position = UDim2.new(0, 0, 0, 60),
                BackgroundTransparency = 1,
                Text = "Prestige bestätigen?",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 22,
                Font = Enum.Font.GothamBold,
                ZIndex = 52,
            }),
            
            -- Message
            create("TextLabel", {
                Name = "Message",
                Size = UDim2.new(1, 0, 0, 80),
                Position = UDim2.new(0, 0, 0, 100),
                BackgroundTransparency = 1,
                Text = "Dein Dungeon wird zurückgesetzt!\n\n✓ Behältst: Helden, Freischaltungen, Achievements\n✗ Verlierst: Räume, Gold, Dungeon-Level",
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 13,
                Font = Enum.Font.Gotham,
                TextWrapped = true,
                ZIndex = 52,
            }),
            
            -- Reward Preview
            create("Frame", {
                Name = "RewardPreview",
                Size = UDim2.new(1, 0, 0, 50),
                Position = UDim2.new(0, 0, 0, 185),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                ZIndex = 52,
            }, {
                corner(8),
                create("TextLabel", {
                    Name = "RewardText",
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "🎁 Belohnung: +5% Gesamt-Bonus",
                    TextColor3 = CONFIG.Colors.Success,
                    TextSize = 16,
                    Font = Enum.Font.GothamBold,
                    ZIndex = 53,
                }),
            }),
            
            -- Buttons
            create("Frame", {
                Name = "Buttons",
                Size = UDim2.new(1, 0, 0, 50),
                Position = UDim2.new(0, 0, 1, -65),
                BackgroundTransparency = 1,
                ZIndex = 52,
            }, {
                create("TextButton", {
                    Name = "CancelButton",
                    Size = UDim2.new(0.48, 0, 1, 0),
                    BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                    Text = "Abbrechen",
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 16,
                    Font = Enum.Font.GothamBold,
                    ZIndex = 53,
                }, {
                    corner(25),
                }),
                
                create("TextButton", {
                    Name = "ConfirmButton",
                    Size = UDim2.new(0.48, 0, 1, 0),
                    Position = UDim2.new(0.52, 0, 0, 0),
                    BackgroundColor3 = CONFIG.Colors.Success,
                    Text = "⭐ Bestätigen",
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 16,
                    Font = Enum.Font.GothamBold,
                    ZIndex = 53,
                }, {
                    corner(25),
                }),
            }),
        }),
    })
    
    -- Button Handlers
    local confirmCard = overlay:FindFirstChild("ConfirmCard")
    if confirmCard then
        local buttons = confirmCard:FindFirstChild("Buttons")
        if buttons then
            local cancelBtn = buttons:FindFirstChild("CancelButton")
            local confirmBtn = buttons:FindFirstChild("ConfirmButton")
            
            if cancelBtn then
                cancelBtn.MouseButton1Click:Connect(function()
                    PrestigeScreen.HideConfirmation()
                end)
            end
            
            if confirmBtn then
                confirmBtn.MouseButton1Click:Connect(function()
                    PrestigeScreen.ConfirmPrestige()
                end)
            end
        end
    end
    
    return overlay
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function PrestigeScreen.Initialize()
    print("[PrestigeScreen] Initialisiere...")
    
    local screens = MainUI:FindFirstChild("Screens")
    if not screens then return end
    
    screenFrame = screens:FindFirstChild("PrestigeScreen")
    if not screenFrame then return end
    
    contentFrame = screenFrame:FindFirstChild("Content")
    if not contentFrame then return end
    
    -- Clear existing
    for _, child in ipairs(contentFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    -- Load data first
    PrestigeScreen.LoadPrestigeData()
    
    -- Create panels
    statusPanel = createStatusPanel()
    statusPanel.Parent = contentFrame
    
    bonusesPanel = createBonusesPanel()
    bonusesPanel.Parent = contentFrame
    
    requirementsPanel = createRequirementsPanel()
    requirementsPanel.Parent = contentFrame
    
    confirmationOverlay = createConfirmationOverlay()
    confirmationOverlay.Parent = contentFrame
    
    -- Populate bonuses
    PrestigeScreen.RefreshBonuses()
    
    -- Populate requirements
    PrestigeScreen.RefreshRequirements()
    
    -- Setup button handlers
    PrestigeScreen.SetupButtonHandlers()
    
    print("[PrestigeScreen] Initialisiert!")
end

function PrestigeScreen.LoadPrestigeData()
    local result = RemoteIndex.Invoke("Prestige_GetStatus")
    
    if result and result.Success then
        screenState.CurrentPrestige = result.PrestigeLevel or 0
        screenState.DungeonLevel = result.DungeonLevel or 1
        screenState.CanPrestige = result.CanPrestige or false
        screenState.TotalBonusPercent = result.TotalBonus or 0
        
        screenState.RequirementsMet = {
            Level = result.DungeonLevel >= CONFIG.MinLevelForPrestige,
        }
    end
end

function PrestigeScreen.RefreshBonuses()
    if not bonusesPanel then return end
    
    local bonusesGrid = bonusesPanel:FindFirstChild("BonusesGrid")
    if not bonusesGrid then return end
    
    -- Clear existing
    for _, child in ipairs(bonusesGrid:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    -- Create bonus cards
    for _, bonusData in ipairs(PRESTIGE_BONUSES) do
        local card = createBonusCard(bonusData, screenState.CurrentPrestige)
        card.Parent = bonusesGrid
    end
end

function PrestigeScreen.RefreshRequirements()
    if not requirementsPanel then return end
    
    local requirementsList = requirementsPanel:FindFirstChild("RequirementsList")
    if not requirementsList then return end
    
    -- Clear existing
    for _, child in ipairs(requirementsList:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    -- Level Requirement
    local levelMet = screenState.DungeonLevel >= CONFIG.MinLevelForPrestige
    local levelRow = createRequirementRow(
        "📊",
        "Dungeon Level",
        screenState.DungeonLevel,
        CONFIG.MinLevelForPrestige,
        levelMet
    )
    levelRow.Parent = requirementsList
    
    -- Update Can Prestige state
    screenState.CanPrestige = levelMet and screenState.CurrentPrestige < CONFIG.MaxPrestige
    
    -- Update Prestige Button
    PrestigeScreen.UpdatePrestigeButton()
end

function PrestigeScreen.UpdatePrestigeButton()
    if not requirementsPanel then return end
    
    local prestigeBtn = requirementsPanel:FindFirstChild("PrestigeButton")
    if not prestigeBtn then return end
    
    local prestigeColor = getPrestigeColor(screenState.CurrentPrestige + 1)
    
    if screenState.CurrentPrestige >= CONFIG.MaxPrestige then
        prestigeBtn.Text = "✓ MAX PRESTIGE"
        prestigeBtn.BackgroundColor3 = CONFIG.Colors.Success
        prestigeBtn.TextColor3 = CONFIG.Colors.Text
        prestigeBtn.AutoButtonColor = false
        
        local btnStroke = prestigeBtn:FindFirstChildOfClass("UIStroke")
        if btnStroke then btnStroke.Color = CONFIG.Colors.Success end
        
    elseif screenState.CanPrestige then
        prestigeBtn.Text = "⭐ PRESTIGE"
        prestigeBtn.BackgroundColor3 = prestigeColor
        prestigeBtn.TextColor3 = CONFIG.Colors.Text
        prestigeBtn.AutoButtonColor = true
        
        local btnStroke = prestigeBtn:FindFirstChildOfClass("UIStroke")
        if btnStroke then btnStroke.Color = prestigeColor end
        
    else
        prestigeBtn.Text = "⭐ PRESTIGE"
        prestigeBtn.BackgroundColor3 = CONFIG.Colors.SurfaceLight
        prestigeBtn.TextColor3 = CONFIG.Colors.TextMuted
        prestigeBtn.AutoButtonColor = false
        
        local btnStroke = prestigeBtn:FindFirstChildOfClass("UIStroke")
        if btnStroke then btnStroke.Color = CONFIG.Colors.Border end
    end
end

function PrestigeScreen.SetupButtonHandlers()
    if not requirementsPanel then return end
    
    local prestigeBtn = requirementsPanel:FindFirstChild("PrestigeButton")
    if prestigeBtn then
        prestigeBtn.MouseButton1Click:Connect(function()
            if screenState.CanPrestige then
                PrestigeScreen.ShowConfirmation()
            elseif screenState.CurrentPrestige >= CONFIG.MaxPrestige then
                if _G.UIManager then
                    _G.UIManager.ShowNotification("Max Prestige", "Du hast das maximale Prestige-Level erreicht!", "Info")
                end
            else
                if _G.UIManager then
                    _G.UIManager.ShowNotification("Nicht möglich", "Erfülle alle Anforderungen für Prestige!", "Warning")
                end
            end
        end)
    end
end

function PrestigeScreen.ShowConfirmation()
    if not confirmationOverlay then return end
    
    screenState.ShowingConfirmation = true
    confirmationOverlay.Visible = true
    
    -- Animate in
    tween(confirmationOverlay, { BackgroundTransparency = 0.6 }, 0.3)
    
    local confirmCard = confirmationOverlay:FindFirstChild("ConfirmCard")
    if confirmCard then
        confirmCard.Position = UDim2.new(0.5, -200, 0.5, -200)
        tween(confirmCard, { Position = UDim2.new(0.5, -200, 0.5, -160) }, 0.3, Enum.EasingStyle.Back)
    end
end

function PrestigeScreen.HideConfirmation()
    if not confirmationOverlay then return end
    
    screenState.ShowingConfirmation = false
    
    -- Animate out
    tween(confirmationOverlay, { BackgroundTransparency = 1 }, 0.2)
    
    local confirmCard = confirmationOverlay:FindFirstChild("ConfirmCard")
    if confirmCard then
        tween(confirmCard, { Position = UDim2.new(0.5, -200, 0.5, -200) }, 0.2)
    end
    
    task.delay(0.2, function()
        confirmationOverlay.Visible = false
    end)
end

function PrestigeScreen.ConfirmPrestige()
    -- Hide confirmation first
    PrestigeScreen.HideConfirmation()
    
    -- Send request to server
    local result = RemoteIndex.Invoke("Prestige_Execute")
    
    if result and result.Success then
        -- Update local state
        screenState.CurrentPrestige = result.NewPrestigeLevel
        screenState.DungeonLevel = 1
        screenState.CanPrestige = false
        
        -- Refresh UI
        PrestigeScreen.RefreshAll()
        
        -- Show success notification
        if _G.UIManager then
            _G.UIManager.ShowNotification(
                "⭐ Prestige erfolgreich!",
                "Du bist jetzt Prestige " .. result.NewPrestigeLevel .. "!",
                "Success"
            )
        end
        
        -- Celebration effect could go here
        PrestigeScreen.PlayPrestigeEffect()
        
    else
        if _G.UIManager then
            _G.UIManager.ShowNotification(
                "Fehler",
                result and result.Error or "Prestige fehlgeschlagen",
                "Error"
            )
        end
    end
end

function PrestigeScreen.RefreshAll()
    -- Recreate all panels with new data
    if statusPanel then statusPanel:Destroy() end
    if bonusesPanel then bonusesPanel:Destroy() end
    if requirementsPanel then requirementsPanel:Destroy() end
    
    statusPanel = createStatusPanel()
    statusPanel.Parent = contentFrame
    
    bonusesPanel = createBonusesPanel()
    bonusesPanel.Parent = contentFrame
    
    requirementsPanel = createRequirementsPanel()
    requirementsPanel.Parent = contentFrame
    
    PrestigeScreen.RefreshBonuses()
    PrestigeScreen.RefreshRequirements()
    PrestigeScreen.SetupButtonHandlers()
end

function PrestigeScreen.PlayPrestigeEffect()
    -- Simple star particle effect
    if not contentFrame then return end
    
    for i = 1, 20 do
        task.spawn(function()
            local star = create("TextLabel", {
                Name = "Star_" .. i,
                Size = UDim2.new(0, 30, 0, 30),
                Position = UDim2.new(0.5, math.random(-200, 200), 0.3, 0),
                BackgroundTransparency = 1,
                Text = "⭐",
                TextSize = math.random(20, 40),
                ZIndex = 100,
            })
            star.Parent = contentFrame
            
            local targetY = UDim2.new(0.5, math.random(-200, 200), 1.2, 0)
            local rotation = math.random(-360, 360)
            
            tween(star, {
                Position = targetY,
                Rotation = rotation,
                TextTransparency = 1,
            }, 2, Enum.EasingStyle.Quad)
            
            task.delay(2, function()
                star:Destroy()
            end)
        end)
        
        task.wait(0.05)
    end
end

-------------------------------------------------
-- REMOTE EVENT HANDLERS
-------------------------------------------------

RemoteIndex.OnClient("Prestige_Update", function(data)
    if data.PrestigeLevel then
        screenState.CurrentPrestige = data.PrestigeLevel
    end
    if data.DungeonLevel then
        screenState.DungeonLevel = data.DungeonLevel
    end
    if data.CanPrestige ~= nil then
        screenState.CanPrestige = data.CanPrestige
    end
    
    PrestigeScreen.RefreshAll()
end)

RemoteIndex.OnClient("Dungeon_Update", function(data)
    if data.Level then
        screenState.DungeonLevel = data.Level
        screenState.RequirementsMet.Level = data.Level >= CONFIG.MinLevelForPrestige
        
        PrestigeScreen.RefreshRequirements()
    end
end)

-------------------------------------------------
-- AUTO-INITIALIZE
-------------------------------------------------

task.spawn(function()
    task.wait(0.9)
    PrestigeScreen.Initialize()
end)

return PrestigeScreen
