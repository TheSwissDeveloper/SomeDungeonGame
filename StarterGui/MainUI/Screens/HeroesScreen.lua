--[[
    HeroesScreen.lua
    Helden-Management und Team-Zusammenstellung
    Pfad: StarterGui/MainUI/Screens/HeroesScreen
    
    Dieses Script:
    - Zeigt alle rekrutierten Helden
    - Team-Zusammenstellung (5 Slots)
    - Rekrutierungs-Gacha System
    - Helden-Upgrades und Details
    
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
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

local HeroesScreen = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Layout
    HeroCardSize = UDim2.new(0, 140, 0, 180),
    TeamSlotSize = UDim2.new(0, 100, 0, 130),
    CardGap = 12,
    
    -- Team
    MaxTeamSize = 5,
    
    -- Recruitment Cost
    RecruitCostGold = 500,
    RecruitCostGems = 5,
    
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
        Border = Color3.fromRGB(71, 85, 105),
        
        -- Rarity
        Common = Color3.fromRGB(156, 163, 175),
        Uncommon = Color3.fromRGB(34, 197, 94),
        Rare = Color3.fromRGB(59, 130, 246),
        Epic = Color3.fromRGB(168, 85, 247),
        Legendary = Color3.fromRGB(251, 191, 36),
        
        -- Classes
        Warrior = Color3.fromRGB(239, 68, 68),
        Mage = Color3.fromRGB(139, 92, 246),
        Ranger = Color3.fromRGB(34, 197, 94),
        Tank = Color3.fromRGB(59, 130, 246),
        Healer = Color3.fromRGB(236, 72, 153),
        Assassin = Color3.fromRGB(107, 114, 128),
    },
}

-------------------------------------------------
-- FILTER OPTIONS
-------------------------------------------------
local FILTER_OPTIONS = {
    Rarity = { "Alle", "Common", "Uncommon", "Rare", "Epic", "Legendary" },
    Class = { "Alle", "Warrior", "Mage", "Ranger", "Tank", "Healer", "Assassin" },
    Sort = { "Level", "Rarity", "Name", "Power" },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local screenState = {
    -- Owned Heroes: { [instanceId] = { HeroId, Level, XP, ... } }
    OwnedHeroes = {},
    
    -- Team: Array of instanceIds
    Team = {},
    
    -- Filters
    CurrentFilter = {
        Rarity = "Alle",
        Class = "Alle",
        Sort = "Level",
    },
    
    -- Selection
    SelectedHeroId = nil,
    DraggingHero = nil,
    
    -- Currency
    PlayerCurrency = {
        Gold = 0,
        Gems = 0,
    },
}

-------------------------------------------------
-- UI REFERENCES
-------------------------------------------------
local screenFrame = nil
local contentFrame = nil
local teamPanel = nil
local heroGrid = nil
local detailPanel = nil
local recruitPanel = nil

-------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------

local function tween(instance, properties, duration, easingStyle)
    local tweenInfo = TweenInfo.new(duration or 0.2, easingStyle or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = TweenService:Create(instance, tweenInfo, properties)
    t:Play()
    return t
end

local function formatNumber(num)
    return CurrencyUtil.FormatNumber(num)
end

local function getRarityColor(rarity)
    return CONFIG.Colors[rarity] or CONFIG.Colors.Common
end

local function getClassColor(class)
    return CONFIG.Colors[class] or CONFIG.Colors.Warrior
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

--[[
    Berechnet Hero Power Score
]]
local function calculateHeroPower(heroData, heroConfig)
    if not heroData or not heroConfig then return 0 end
    
    local level = heroData.Level or 1
    local baseStats = heroConfig.BaseStats or {}
    
    local hp = (baseStats.Health or 100) * (1 + (level - 1) * 0.15)
    local dmg = (baseStats.Damage or 20) * (1 + (level - 1) * 0.15)
    
    return math.floor(hp * 0.5 + dmg * 2)
end

--[[
    Prüft ob Held im Team ist
]]
local function isHeroInTeam(instanceId)
    for _, teamMemberId in ipairs(screenState.Team) do
        if teamMemberId == instanceId then
            return true
        end
    end
    return false
end

--[[
    Gibt Rarity-Sortier-Wert zurück
]]
local function getRaritySortValue(rarity)
    local values = {
        Common = 1,
        Uncommon = 2,
        Rare = 3,
        Epic = 4,
        Legendary = 5,
    }
    return values[rarity] or 0
end

-------------------------------------------------
-- TEAM SLOT CREATION
-------------------------------------------------

local function createTeamSlot(slotIndex, heroInstanceId)
    local isEmpty = heroInstanceId == nil
    local heroData = not isEmpty and screenState.OwnedHeroes[heroInstanceId]
    local heroConfig = heroData and HeroConfig.GetHero(heroData.HeroId)
    
    local slot = create("TextButton", {
        Name = "TeamSlot_" .. slotIndex,
        Size = CONFIG.TeamSlotSize,
        BackgroundColor3 = isEmpty and CONFIG.Colors.SurfaceLight or CONFIG.Colors.Surface,
        Text = "",
        AutoButtonColor = true,
        LayoutOrder = slotIndex,
    }, {
        corner(12),
        stroke(isEmpty and CONFIG.Colors.Border or getRarityColor(heroConfig and heroConfig.Rarity or "Common"), isEmpty and 1 or 2),
    })
    
    if isEmpty then
        -- Empty Slot
        create("TextLabel", {
            Name = "EmptyIcon",
            Size = UDim2.new(1, 0, 0, 50),
            Position = UDim2.new(0, 0, 0, 25),
            BackgroundTransparency = 1,
            Text = "+",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 36,
            Font = Enum.Font.GothamBold,
        }).Parent = slot
        
        create("TextLabel", {
            Name = "SlotNumber",
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 0, 80),
            BackgroundTransparency = 1,
            Text = "Slot " .. slotIndex,
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 12,
            Font = Enum.Font.Gotham,
        }).Parent = slot
    else
        -- Filled Slot
        local rarityColor = getRarityColor(heroConfig.Rarity)
        
        -- Hero Icon
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(0, 60, 0, 60),
            Position = UDim2.new(0.5, -30, 0, 10),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(30),
            stroke(rarityColor, 2, 0.3),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = heroConfig.Icon or "⚔️",
                TextSize = 30,
            }),
        }).Parent = slot
        
        -- Hero Name
        create("TextLabel", {
            Name = "HeroName",
            Size = UDim2.new(1, -10, 0, 18),
            Position = UDim2.new(0, 5, 0, 75),
            BackgroundTransparency = 1,
            Text = heroConfig.Name or "Hero",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 11,
            Font = Enum.Font.GothamBold,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }).Parent = slot
        
        -- Level Badge
        create("Frame", {
            Name = "LevelBadge",
            Size = UDim2.new(0, 40, 0, 20),
            Position = UDim2.new(0.5, -20, 0, 95),
            BackgroundColor3 = CONFIG.Colors.Primary,
        }, {
            corner(10),
            create("TextLabel", {
                Name = "Level",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "Lv." .. (heroData.Level or 1),
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 11,
                Font = Enum.Font.GothamBold,
            }),
        }).Parent = slot
        
        -- Remove Button
        local removeBtn = create("TextButton", {
            Name = "RemoveButton",
            Size = UDim2.new(0, 24, 0, 24),
            Position = UDim2.new(1, -28, 0, 4),
            BackgroundColor3 = CONFIG.Colors.Error,
            Text = "✕",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            ZIndex = 5,
        }, {
            corner(12),
        })
        removeBtn.Parent = slot
        
        removeBtn.MouseButton1Click:Connect(function()
            HeroesScreen.RemoveFromTeam(slotIndex)
        end)
    end
    
    -- Click Handler (für leere Slots)
    if isEmpty then
        slot.MouseButton1Click:Connect(function()
            -- Öffne Hero-Auswahl
            HeroesScreen.ShowHeroSelector(slotIndex)
        end)
    else
        slot.MouseButton1Click:Connect(function()
            -- Zeige Hero Details
            HeroesScreen.SelectHero(heroInstanceId)
        end)
    end
    
    return slot
end

-------------------------------------------------
-- HERO CARD CREATION
-------------------------------------------------

local function createHeroCard(instanceId, heroData)
    local heroConfig = HeroConfig.GetHero(heroData.HeroId)
    if not heroConfig then return nil end
    
    local rarityColor = getRarityColor(heroConfig.Rarity)
    local classColor = getClassColor(heroConfig.Class)
    local inTeam = isHeroInTeam(instanceId)
    local power = calculateHeroPower(heroData, heroConfig)
    
    local card = create("TextButton", {
        Name = "Hero_" .. instanceId,
        Size = CONFIG.HeroCardSize,
        BackgroundColor3 = CONFIG.Colors.Surface,
        Text = "",
        AutoButtonColor = true,
    }, {
        corner(12),
        stroke(rarityColor, 2, inTeam and 0 or 0.5),
        
        -- In Team Indicator
        create("Frame", {
            Name = "TeamIndicator",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = CONFIG.Colors.Success,
            BackgroundTransparency = inTeam and 0.85 or 1,
            ZIndex = 0,
        }, {
            corner(12),
        }),
        
        -- Rarity Banner
        create("Frame", {
            Name = "RarityBanner",
            Size = UDim2.new(1, 0, 0, 4),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = rarityColor,
        }, {
            corner(2),
        }),
        
        -- Hero Icon
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(0, 70, 0, 70),
            Position = UDim2.new(0.5, -35, 0, 15),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(35),
            stroke(rarityColor, 2, 0.3),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = heroConfig.Icon or "⚔️",
                TextSize = 35,
            }),
        }),
        
        -- Class Badge
        create("Frame", {
            Name = "ClassBadge",
            Size = UDim2.new(0, 24, 0, 24),
            Position = UDim2.new(0, 8, 0, 8),
            BackgroundColor3 = classColor,
        }, {
            corner(12),
            create("TextLabel", {
                Name = "ClassIcon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = HeroesScreen.GetClassIcon(heroConfig.Class),
                TextSize = 12,
            }),
        }),
        
        -- Level Badge
        create("Frame", {
            Name = "LevelBadge",
            Size = UDim2.new(0, 36, 0, 20),
            Position = UDim2.new(1, -44, 0, 8),
            BackgroundColor3 = CONFIG.Colors.Primary,
        }, {
            corner(10),
            create("TextLabel", {
                Name = "Level",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "Lv." .. (heroData.Level or 1),
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 10,
                Font = Enum.Font.GothamBold,
            }),
        }),
        
        -- Hero Name
        create("TextLabel", {
            Name = "HeroName",
            Size = UDim2.new(1, -16, 0, 20),
            Position = UDim2.new(0, 8, 0, 92),
            BackgroundTransparency = 1,
            Text = heroConfig.Name,
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Rarity Text
        create("TextLabel", {
            Name = "RarityText",
            Size = UDim2.new(1, -16, 0, 16),
            Position = UDim2.new(0, 8, 0, 112),
            BackgroundTransparency = 1,
            Text = heroConfig.Rarity,
            TextColor3 = rarityColor,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Power Score
        create("Frame", {
            Name = "PowerFrame",
            Size = UDim2.new(1, -16, 0, 28),
            Position = UDim2.new(0, 8, 1, -36),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(6),
            create("TextLabel", {
                Name = "PowerIcon",
                Size = UDim2.new(0, 24, 1, 0),
                Position = UDim2.new(0, 4, 0, 0),
                BackgroundTransparency = 1,
                Text = "⚡",
                TextSize = 14,
            }),
            create("TextLabel", {
                Name = "PowerValue",
                Size = UDim2.new(1, -32, 1, 0),
                Position = UDim2.new(0, 28, 0, 0),
                BackgroundTransparency = 1,
                Text = formatNumber(power),
                TextColor3 = CONFIG.Colors.Warning,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
        }),
        
        -- In Team Badge
        create("Frame", {
            Name = "InTeamBadge",
            Size = UDim2.new(0, 60, 0, 20),
            Position = UDim2.new(0.5, -30, 1, -58),
            BackgroundColor3 = CONFIG.Colors.Success,
            Visible = inTeam,
        }, {
            corner(10),
            create("TextLabel", {
                Name = "Text",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "Im Team",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 10,
                Font = Enum.Font.GothamBold,
            }),
        }),
    })
    
    -- Click Handler
    card.MouseButton1Click:Connect(function()
        HeroesScreen.SelectHero(instanceId)
    end)
    
    -- Hover Effect
    card.MouseEnter:Connect(function()
        tween(card, { BackgroundColor3 = CONFIG.Colors.SurfaceHover }, 0.15)
    end)
    
    card.MouseLeave:Connect(function()
        tween(card, { BackgroundColor3 = CONFIG.Colors.Surface }, 0.15)
    end)
    
    return card
end

-------------------------------------------------
-- RECRUIT PANEL
-------------------------------------------------

local function createRecruitPanel()
    local panel = create("Frame", {
        Name = "RecruitPanel",
        Size = UDim2.new(0, 280, 0, 180),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(CONFIG.Colors.Primary, 2, 0.3),
        padding(15),
        
        -- Title
        create("TextLabel", {
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundTransparency = 1,
            Text = "🎲 Helden rekrutieren",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Description
        create("TextLabel", {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 35),
            Position = UDim2.new(0, 0, 0, 30),
            BackgroundTransparency = 1,
            Text = "Rekrutiere zufällige Helden für dein Team!",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }),
        
        -- Drop Rates Info
        create("Frame", {
            Name = "DropRates",
            Size = UDim2.new(1, 0, 0, 40),
            Position = UDim2.new(0, 0, 0, 65),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "Common 50% | Uncommon 30% | Rare 15% | Epic 4% | Legendary 1%",
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 9,
                Font = Enum.Font.Gotham,
                TextWrapped = true,
            }),
        }),
        
        -- Recruit Buttons
        create("Frame", {
            Name = "ButtonsFrame",
            Size = UDim2.new(1, 0, 0, 45),
            Position = UDim2.new(0, 0, 1, -60),
            BackgroundTransparency = 1,
        }, {
            -- Gold Recruit
            create("TextButton", {
                Name = "RecruitGold",
                Size = UDim2.new(0.48, 0, 1, 0),
                BackgroundColor3 = CONFIG.Colors.Gold,
                Text = "",
            }, {
                corner(22),
                create("TextLabel", {
                    Name = "Icon",
                    Size = UDim2.new(0, 24, 1, 0),
                    Position = UDim2.new(0, 10, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "💰",
                    TextSize = 16,
                }),
                create("TextLabel", {
                    Name = "Cost",
                    Size = UDim2.new(1, -40, 1, 0),
                    Position = UDim2.new(0, 34, 0, 0),
                    BackgroundTransparency = 1,
                    Text = formatNumber(CONFIG.RecruitCostGold),
                    TextColor3 = CONFIG.Colors.Background,
                    TextSize = 14,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
            }),
            
            -- Gem Recruit
            create("TextButton", {
                Name = "RecruitGems",
                Size = UDim2.new(0.48, 0, 1, 0),
                Position = UDim2.new(0.52, 0, 0, 0),
                BackgroundColor3 = CONFIG.Colors.Gems,
                Text = "",
            }, {
                corner(22),
                create("TextLabel", {
                    Name = "Icon",
                    Size = UDim2.new(0, 24, 1, 0),
                    Position = UDim2.new(0, 10, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "💎",
                    TextSize = 16,
                }),
                create("TextLabel", {
                    Name = "Cost",
                    Size = UDim2.new(1, -40, 1, 0),
                    Position = UDim2.new(0, 34, 0, 0),
                    BackgroundTransparency = 1,
                    Text = formatNumber(CONFIG.RecruitCostGems),
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 14,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
            }),
        }),
    })
    
    -- Button Handlers
    local goldBtn = panel.ButtonsFrame:FindFirstChild("RecruitGold")
    local gemsBtn = panel.ButtonsFrame:FindFirstChild("RecruitGems")
    
    if goldBtn then
        goldBtn.MouseButton1Click:Connect(function()
            HeroesScreen.RecruitHero("Gold")
        end)
    end
    
    if gemsBtn then
        gemsBtn.MouseButton1Click:Connect(function()
            HeroesScreen.RecruitHero("Gems")
        end)
    end
    
    return panel
end

-------------------------------------------------
-- DETAIL PANEL
-------------------------------------------------

local function createDetailPanel()
    local panel = create("Frame", {
        Name = "DetailPanel",
        Size = UDim2.new(0, 300, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = CONFIG.Colors.Surface,
        Visible = false,
    }, {
        corner(12),
        stroke(CONFIG.Colors.Border),
        padding(15),
        
        -- Close Button
        create("TextButton", {
            Name = "CloseButton",
            Size = UDim2.new(0, 32, 0, 32),
            Position = UDim2.new(1, -47, 0, 0),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            Text = "✕",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
        }, {
            corner(16),
        }),
        
        -- Hero Icon Large
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(0, 100, 0, 100),
            Position = UDim2.new(0.5, -50, 0, 10),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(50),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "⚔️",
                TextSize = 50,
            }),
        }),
        
        -- Hero Name
        create("TextLabel", {
            Name = "HeroName",
            Size = UDim2.new(1, 0, 0, 28),
            Position = UDim2.new(0, 0, 0, 120),
            BackgroundTransparency = 1,
            Text = "Hero Name",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 20,
            Font = Enum.Font.GothamBold,
        }),
        
        -- Rarity & Class
        create("TextLabel", {
            Name = "RarityClass",
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 0, 148),
            BackgroundTransparency = 1,
            Text = "Legendary Warrior",
            TextColor3 = CONFIG.Colors.Legendary,
            TextSize = 14,
            Font = Enum.Font.GothamBold,
        }),
        
        -- Level & XP Bar
        create("Frame", {
            Name = "LevelSection",
            Size = UDim2.new(1, 0, 0, 50),
            Position = UDim2.new(0, 0, 0, 180),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(8),
            padding(10),
            
            create("TextLabel", {
                Name = "LevelText",
                Size = UDim2.new(0.5, 0, 0, 20),
                BackgroundTransparency = 1,
                Text = "Level 1",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            
            create("TextLabel", {
                Name = "XPText",
                Size = UDim2.new(0.5, 0, 0, 20),
                Position = UDim2.new(0.5, 0, 0, 0),
                BackgroundTransparency = 1,
                Text = "0 / 100 XP",
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 12,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Right,
            }),
            
            -- XP Bar
            create("Frame", {
                Name = "XPBarBg",
                Size = UDim2.new(1, -20, 0, 8),
                Position = UDim2.new(0, 0, 1, -18),
                BackgroundColor3 = CONFIG.Colors.Background,
            }, {
                corner(4),
                create("Frame", {
                    Name = "XPBarFill",
                    Size = UDim2.new(0.5, 0, 1, 0),
                    BackgroundColor3 = CONFIG.Colors.Primary,
                }, {
                    corner(4),
                }),
            }),
        }),
        
        -- Stats Section
        create("Frame", {
            Name = "StatsSection",
            Size = UDim2.new(1, 0, 0, 100),
            Position = UDim2.new(0, 0, 0, 245),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(8),
            padding(10),
            
            create("TextLabel", {
                Name = "StatsTitle",
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                Text = "📊 Statistiken",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 13,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            
            create("Frame", {
                Name = "StatsList",
                Size = UDim2.new(1, 0, 1, -25),
                Position = UDim2.new(0, 0, 0, 25),
                BackgroundTransparency = 1,
            }, {
                create("UIListLayout", {
                    Padding = UDim.new(0, 4),
                }),
            }),
        }),
        
        -- Action Buttons
        create("Frame", {
            Name = "Actions",
            Size = UDim2.new(1, 0, 0, 45),
            Position = UDim2.new(0, 0, 1, -60),
            BackgroundTransparency = 1,
        }, {
            create("TextButton", {
                Name = "TeamButton",
                Size = UDim2.new(0.48, 0, 1, 0),
                BackgroundColor3 = CONFIG.Colors.Success,
                Text = "Ins Team",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
            }, {
                corner(22),
            }),
            
            create("TextButton", {
                Name = "DismissButton",
                Size = UDim2.new(0.48, 0, 1, 0),
                Position = UDim2.new(0.52, 0, 0, 0),
                BackgroundColor3 = CONFIG.Colors.Error,
                Text = "Entlassen",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
            }, {
                corner(22),
            }),
        }),
    })
    
    -- Button Handlers
    local closeBtn = panel:FindFirstChild("CloseButton")
    if closeBtn then
        closeBtn.MouseButton1Click:Connect(function()
            HeroesScreen.CloseDetailPanel()
        end)
    end
    
    local teamBtn = panel.Actions:FindFirstChild("TeamButton")
    if teamBtn then
        teamBtn.MouseButton1Click:Connect(function()
            HeroesScreen.ToggleTeamMembership()
        end)
    end
    
    local dismissBtn = panel.Actions:FindFirstChild("DismissButton")
    if dismissBtn then
        dismissBtn.MouseButton1Click:Connect(function()
            HeroesScreen.DismissSelectedHero()
        end)
    end
    
    return panel
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function HeroesScreen.Initialize()
    print("[HeroesScreen] Initialisiere...")
    
    local screens = MainUI:FindFirstChild("Screens")
    if not screens then return end
    
    screenFrame = screens:FindFirstChild("HeroesScreen")
    if not screenFrame then return end
    
    contentFrame = screenFrame:FindFirstChild("Content")
    if not contentFrame then return end
    
    -- Clear existing
    for _, child in ipairs(contentFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("ScrollingFrame") then
            child:Destroy()
        end
    end
    
    -- Layout erstellen
    -- Top Section: Team Panel + Recruit Panel
    local topSection = create("Frame", {
        Name = "TopSection",
        Size = UDim2.new(1, 0, 0, 180),
        BackgroundTransparency = 1,
    })
    topSection.Parent = contentFrame
    
    -- Team Panel
    teamPanel = create("Frame", {
        Name = "TeamPanel",
        Size = UDim2.new(0, 600, 1, 0),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(),
        padding(15),
        
        create("TextLabel", {
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundTransparency = 1,
            Text = "⚔️ Dein Team",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        create("Frame", {
            Name = "TeamSlots",
            Size = UDim2.new(1, 0, 1, -35),
            Position = UDim2.new(0, 0, 0, 35),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, 10),
            }),
        }),
    })
    teamPanel.Parent = topSection
    
    -- Recruit Panel
    recruitPanel = createRecruitPanel()
    recruitPanel.Position = UDim2.new(1, -280, 0, 0)
    recruitPanel.Parent = topSection
    
    -- Hero Grid
    heroGrid = create("ScrollingFrame", {
        Name = "HeroGrid",
        Size = UDim2.new(1, 0, 1, -200),
        Position = UDim2.new(0, 0, 0, 190),
        BackgroundTransparency = 1,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = CONFIG.Colors.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, {
        padding(10),
        create("UIGridLayout", {
            CellSize = CONFIG.HeroCardSize,
            CellPadding = UDim2.new(0, CONFIG.CardGap, 0, CONFIG.CardGap),
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    heroGrid.Parent = contentFrame
    
    -- Detail Panel
    detailPanel = createDetailPanel()
    detailPanel.Parent = contentFrame
    
    -- Load Data
    HeroesScreen.LoadHeroData()
    
    print("[HeroesScreen] Initialisiert!")
end

function HeroesScreen.GetClassIcon(class)
    local icons = {
        Warrior = "⚔️",
        Mage = "🔮",
        Ranger = "🏹",
        Tank = "🛡️",
        Healer = "💚",
        Assassin = "🗡️",
    }
    return icons[class] or "⚔️"
end

function HeroesScreen.LoadHeroData()
    local result = RemoteIndex.Invoke("Hero_GetAll")
    
    if result and result.Success then
        screenState.OwnedHeroes = result.Heroes or {}
        screenState.Team = result.Team or {}
    end
    
    HeroesScreen.RefreshTeamSlots()
    HeroesScreen.RefreshHeroGrid()
end

function HeroesScreen.RefreshTeamSlots()
    if not teamPanel then return end
    
    local slotsContainer = teamPanel:FindFirstChild("TeamSlots")
    if not slotsContainer then return end
    
    -- Clear
    for _, child in ipairs(slotsContainer:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    -- Create slots
    for i = 1, CONFIG.MaxTeamSize do
        local heroId = screenState.Team[i]
        local slot = createTeamSlot(i, heroId)
        slot.Parent = slotsContainer
    end
end

function HeroesScreen.RefreshHeroGrid()
    if not heroGrid then return end
    
    -- Clear
    for _, child in ipairs(heroGrid:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    -- Collect and sort heroes
    local heroList = {}
    for instanceId, heroData in pairs(screenState.OwnedHeroes) do
        local heroConfig = HeroConfig.GetHero(heroData.HeroId)
        if heroConfig then
            table.insert(heroList, {
                InstanceId = instanceId,
                Data = heroData,
                Config = heroConfig,
                Power = calculateHeroPower(heroData, heroConfig),
            })
        end
    end
    
    -- Sort
    local sortKey = screenState.CurrentFilter.Sort
    table.sort(heroList, function(a, b)
        if sortKey == "Level" then
            return (a.Data.Level or 1) > (b.Data.Level or 1)
        elseif sortKey == "Rarity" then
            return getRaritySortValue(a.Config.Rarity) > getRaritySortValue(b.Config.Rarity)
        elseif sortKey == "Power" then
            return a.Power > b.Power
        else
            return a.Config.Name < b.Config.Name
        end
    end)
    
    -- Filter & Create cards
    local layoutOrder = 1
    for _, hero in ipairs(heroList) do
        local passFilter = true
        
        -- Rarity Filter
        if screenState.CurrentFilter.Rarity ~= "Alle" then
            passFilter = passFilter and hero.Config.Rarity == screenState.CurrentFilter.Rarity
        end
        
        -- Class Filter
        if screenState.CurrentFilter.Class ~= "Alle" then
            passFilter = passFilter and hero.Config.Class == screenState.CurrentFilter.Class
        end
        
        if passFilter then
            local card = createHeroCard(hero.InstanceId, hero.Data)
            if card then
                card.LayoutOrder = layoutOrder
                card.Parent = heroGrid
                layoutOrder = layoutOrder + 1
            end
        end
    end
end

function HeroesScreen.SelectHero(instanceId)
    screenState.SelectedHeroId = instanceId
    HeroesScreen.UpdateDetailPanel()
    HeroesScreen.OpenDetailPanel()
end

function HeroesScreen.UpdateDetailPanel()
    if not detailPanel or not screenState.SelectedHeroId then return end
    
    local heroData = screenState.OwnedHeroes[screenState.SelectedHeroId]
    if not heroData then return end
    
    local heroConfig = HeroConfig.GetHero(heroData.HeroId)
    if not heroConfig then return end
    
    local inTeam = isHeroInTeam(screenState.SelectedHeroId)
    local rarityColor = getRarityColor(heroConfig.Rarity)
    
    -- Update UI
    local iconFrame = detailPanel:FindFirstChild("IconFrame")
    if iconFrame then
        local icon = iconFrame:FindFirstChild("Icon")
        if icon then icon.Text = heroConfig.Icon or "⚔️" end
        
        local iconStroke = iconFrame:FindFirstChildOfClass("UIStroke")
        if not iconStroke then
            iconStroke = stroke(rarityColor, 3, 0.3)
            iconStroke.Parent = iconFrame
        else
            iconStroke.Color = rarityColor
        end
    end
    
    local nameLabel = detailPanel:FindFirstChild("HeroName")
    if nameLabel then nameLabel.Text = heroConfig.Name end
    
    local rarityLabel = detailPanel:FindFirstChild("RarityClass")
    if rarityLabel then
        rarityLabel.Text = heroConfig.Rarity .. " " .. heroConfig.Class
        rarityLabel.TextColor3 = rarityColor
    end
    
    -- Level & XP
    local levelSection = detailPanel:FindFirstChild("LevelSection")
    if levelSection then
        local levelText = levelSection:FindFirstChild("LevelText")
        if levelText then levelText.Text = "Level " .. (heroData.Level or 1) end
        
        local xpNeeded = (heroData.Level or 1) * 100
        local currentXP = heroData.XP or 0
        
        local xpText = levelSection:FindFirstChild("XPText")
        if xpText then xpText.Text = currentXP .. " / " .. xpNeeded .. " XP" end
        
        local xpBarBg = levelSection:FindFirstChild("XPBarBg")
        if xpBarBg then
            local fill = xpBarBg:FindFirstChild("XPBarFill")
            if fill then
                local percent = math.clamp(currentXP / xpNeeded, 0, 1)
                tween(fill, { Size = UDim2.new(percent, 0, 1, 0) }, 0.3)
            end
        end
    end
    
    -- Team Button
    local teamBtn = detailPanel.Actions:FindFirstChild("TeamButton")
    if teamBtn then
        if inTeam then
            teamBtn.Text = "Aus Team"
            teamBtn.BackgroundColor3 = CONFIG.Colors.Warning
        else
            teamBtn.Text = "Ins Team"
            teamBtn.BackgroundColor3 = CONFIG.Colors.Success
        end
    end
end

function HeroesScreen.OpenDetailPanel()
    if not detailPanel then return end
    
    detailPanel.Visible = true
    tween(detailPanel, { Position = UDim2.new(1, -300, 0, 0) }, 0.25, Enum.EasingStyle.Back)
    tween(heroGrid, { Size = UDim2.new(1, -320, 1, -200) }, 0.2)
end

function HeroesScreen.CloseDetailPanel()
    if not detailPanel then return end
    
    tween(detailPanel, { Position = UDim2.new(1, 0, 0, 0) }, 0.2)
    task.delay(0.2, function()
        detailPanel.Visible = false
    end)
    
    tween(heroGrid, { Size = UDim2.new(1, 0, 1, -200) }, 0.2)
    screenState.SelectedHeroId = nil
end

function HeroesScreen.ToggleTeamMembership()
    if not screenState.SelectedHeroId then return end
    
    local inTeam = isHeroInTeam(screenState.SelectedHeroId)
    
    if inTeam then
        HeroesScreen.RemoveHeroFromTeam(screenState.SelectedHeroId)
    else
        HeroesScreen.AddHeroToTeam(screenState.SelectedHeroId)
    end
end

function HeroesScreen.AddHeroToTeam(instanceId)
    if #screenState.Team >= CONFIG.MaxTeamSize then
        if _G.UIManager then
            _G.UIManager.ShowNotification("Team voll", "Max " .. CONFIG.MaxTeamSize .. " Helden im Team!", "Warning")
        end
        return
    end
    
    local result = RemoteIndex.Invoke("Hero_AddToTeam", instanceId)
    
    if result and result.Success then
        table.insert(screenState.Team, instanceId)
        HeroesScreen.RefreshTeamSlots()
        HeroesScreen.RefreshHeroGrid()
        HeroesScreen.UpdateDetailPanel()
        
        if _G.UIManager then
            _G.UIManager.ShowNotification("Zum Team hinzugefügt!", "", "Success")
        end
    end
end

function HeroesScreen.RemoveHeroFromTeam(instanceId)
    local result = RemoteIndex.Invoke("Hero_RemoveFromTeam", instanceId)
    
    if result and result.Success then
        for i, id in ipairs(screenState.Team) do
            if id == instanceId then
                table.remove(screenState.Team, i)
                break
            end
        end
        
        HeroesScreen.RefreshTeamSlots()
        HeroesScreen.RefreshHeroGrid()
        HeroesScreen.UpdateDetailPanel()
    end
end

function HeroesScreen.RemoveFromTeam(slotIndex)
    local instanceId = screenState.Team[slotIndex]
    if instanceId then
        HeroesScreen.RemoveHeroFromTeam(instanceId)
    end
end

function HeroesScreen.RecruitHero(currency)
    local result = RemoteIndex.Invoke("Hero_Recruit", currency)
    
    if result and result.Success then
        local newHero = result.Hero
        screenState.OwnedHeroes[newHero.InstanceId] = newHero
        
        HeroesScreen.RefreshHeroGrid()
        
        local heroConfig = HeroConfig.GetHero(newHero.HeroId)
        if heroConfig and _G.UIManager then
            _G.UIManager.ShowNotification(
                "🎉 Neuer Held!",
                heroConfig.Name .. " (" .. heroConfig.Rarity .. ")",
                "Success"
            )
        end
    else
        if _G.UIManager then
            _G.UIManager.ShowNotification("Fehler", result and result.Error or "Rekrutierung fehlgeschlagen", "Error")
        end
    end
end

function HeroesScreen.DismissSelectedHero()
    if not screenState.SelectedHeroId then return end
    
    -- TODO: Bestätigungs-Dialog
    local result = RemoteIndex.Invoke("Hero_Dismiss", screenState.SelectedHeroId)
    
    if result and result.Success then
        screenState.OwnedHeroes[screenState.SelectedHeroId] = nil
        
        -- Aus Team entfernen falls drin
        for i, id in ipairs(screenState.Team) do
            if id == screenState.SelectedHeroId then
                table.remove(screenState.Team, i)
                break
            end
        end
        
        HeroesScreen.CloseDetailPanel()
        HeroesScreen.RefreshTeamSlots()
        HeroesScreen.RefreshHeroGrid()
        
        if _G.UIManager then
            _G.UIManager.ShowNotification("Held entlassen", "", "Info")
        end
    end
end

function HeroesScreen.ShowHeroSelector(slotIndex)
    -- TODO: Popup für Heldenauswahl
    if _G.UIManager then
        _G.UIManager.ShowNotification("Held auswählen", "Klicke auf einen Helden unten!", "Info")
    end
end

-------------------------------------------------
-- REMOTE EVENT HANDLERS
-------------------------------------------------

RemoteIndex.OnClient("Heroes_Update", function(data)
    if data.Heroes then
        screenState.OwnedHeroes = data.Heroes
    end
    if data.Team then
        screenState.Team = data.Team
    end
    
    HeroesScreen.RefreshTeamSlots()
    HeroesScreen.RefreshHeroGrid()
end)

-------------------------------------------------
-- AUTO-INITIALIZE
-------------------------------------------------

task.spawn(function()
    task.wait(0.7)
    HeroesScreen.Initialize()
end)

return HeroesScreen
