--[[
    RaidScreen.lua
    Raid-Vorbereitung und Kampf-Ansicht
    Pfad: StarterGui/MainUI/Screens/RaidScreen
    
    Dieses Script:
    - Zeigt Raid-Vorbereitung
    - Matchmaking und Gegner-Auswahl
    - Live-Combat Visualisierung
    - Raid-Ergebnisse und Belohnungen
    
    WICHTIG: Wird vom UIManager geladen!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

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

local RaidScreen = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Layout
    HeroSlotSize = UDim2.new(0, 80, 0, 100),
    EnemyCardSize = UDim2.new(0, 300, 0, 120),
    
    -- Combat Log
    MaxLogEntries = 50,
    LogEntryHeight = 24,
    
    -- Animation
    DamageNumberDuration = 1.5,
    ShakeIntensity = 5,
    
    -- Colors
    Colors = {
        Background = Color3.fromRGB(15, 23, 42),
        Surface = Color3.fromRGB(30, 41, 59),
        SurfaceLight = Color3.fromRGB(51, 65, 85),
        Primary = Color3.fromRGB(99, 102, 241),
        Success = Color3.fromRGB(34, 197, 94),
        Warning = Color3.fromRGB(234, 179, 8),
        Error = Color3.fromRGB(239, 68, 68),
        Gold = Color3.fromRGB(251, 191, 36),
        Gems = Color3.fromRGB(168, 85, 247),
        Text = Color3.fromRGB(248, 250, 252),
        TextMuted = Color3.fromRGB(148, 163, 184),
        Border = Color3.fromRGB(71, 85, 105),
        
        -- HP Colors
        HealthHigh = Color3.fromRGB(34, 197, 94),
        HealthMid = Color3.fromRGB(234, 179, 8),
        HealthLow = Color3.fromRGB(239, 68, 68),
        
        -- Rarity
        Common = Color3.fromRGB(156, 163, 175),
        Uncommon = Color3.fromRGB(34, 197, 94),
        Rare = Color3.fromRGB(59, 130, 246),
        Epic = Color3.fromRGB(168, 85, 247),
        Legendary = Color3.fromRGB(251, 191, 36),
        
        -- Combat
        DamagePhysical = Color3.fromRGB(239, 68, 68),
        DamageMagic = Color3.fromRGB(139, 92, 246),
        Healing = Color3.fromRGB(34, 197, 94),
        Critical = Color3.fromRGB(251, 191, 36),
    },
}

-------------------------------------------------
-- RAID STATES
-------------------------------------------------
local RAID_STATE = {
    Idle = "Idle",
    Searching = "Searching",
    Preparing = "Preparing",
    InProgress = "InProgress",
    Victory = "Victory",
    Defeat = "Defeat",
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local screenState = {
    CurrentState = RAID_STATE.Idle,
    
    -- Player Data
    Team = {},
    TeamStats = {},
    
    -- Raid Data
    RaidId = nil,
    TargetDungeon = nil,
    CurrentRoom = 0,
    TotalRooms = 0,
    
    -- Combat State
    HeroStates = {},      -- { [instanceId] = { CurrentHP, MaxHP, Status, ... } }
    EnemyStates = {},     -- { [index] = { CurrentHP, MaxHP, Type, ... } }
    CombatLog = {},
    
    -- Cooldown
    RaidCooldown = 0,
    CanRaid = true,
    
    -- Results
    RaidResult = nil,
}

-------------------------------------------------
-- UI REFERENCES
-------------------------------------------------
local screenFrame = nil
local contentFrame = nil
local preparationPanel = nil
local combatPanel = nil
local resultPanel = nil

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

local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

local function getRarityColor(rarity)
    return CONFIG.Colors[rarity] or CONFIG.Colors.Common
end

local function getHealthColor(percent)
    if percent > 0.6 then
        return CONFIG.Colors.HealthHigh
    elseif percent > 0.3 then
        return CONFIG.Colors.HealthMid
    else
        return CONFIG.Colors.HealthLow
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
-- HERO SLOT (Combat View)
-------------------------------------------------

local function createHeroCombatSlot(heroData, heroConfig, slotIndex)
    local slot = create("Frame", {
        Name = "HeroSlot_" .. slotIndex,
        Size = CONFIG.HeroSlotSize,
        BackgroundColor3 = CONFIG.Colors.Surface,
        LayoutOrder = slotIndex,
    }, {
        corner(10),
        stroke(getRarityColor(heroConfig.Rarity), 2, 0.3),
        
        -- Hero Icon
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(0, 50, 0, 50),
            Position = UDim2.new(0.5, -25, 0, 8),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(25),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = heroConfig.Icon or "⚔️",
                TextSize = 26,
            }),
        }),
        
        -- HP Bar Background
        create("Frame", {
            Name = "HPBarBg",
            Size = UDim2.new(1, -16, 0, 10),
            Position = UDim2.new(0, 8, 0, 62),
            BackgroundColor3 = CONFIG.Colors.Background,
        }, {
            corner(5),
            -- HP Bar Fill
            create("Frame", {
                Name = "HPBarFill",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = CONFIG.Colors.HealthHigh,
            }, {
                corner(5),
            }),
        }),
        
        -- HP Text
        create("TextLabel", {
            Name = "HPText",
            Size = UDim2.new(1, 0, 0, 14),
            Position = UDim2.new(0, 0, 0, 74),
            BackgroundTransparency = 1,
            Text = "100%",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 10,
            Font = Enum.Font.Gotham,
        }),
        
        -- Status Icons
        create("Frame", {
            Name = "StatusIcons",
            Size = UDim2.new(1, 0, 0, 16),
            Position = UDim2.new(0, 0, 1, -18),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                Padding = UDim.new(0, 2),
            }),
        }),
        
        -- Dead Overlay
        create("Frame", {
            Name = "DeadOverlay",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 10,
        }, {
            corner(10),
            create("TextLabel", {
                Name = "DeadIcon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "💀",
                TextSize = 30,
                ZIndex = 11,
            }),
        }),
    })
    
    return slot
end

-------------------------------------------------
-- ENEMY DISPLAY
-------------------------------------------------

local function createEnemyDisplay()
    local display = create("Frame", {
        Name = "EnemyDisplay",
        Size = UDim2.new(1, 0, 0, 150),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(CONFIG.Colors.Error, 2, 0.5),
        padding(15),
        
        -- Room Header
        create("Frame", {
            Name = "RoomHeader",
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "RoomTitle",
                Size = UDim2.new(0.7, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "🏠 Raum 1 / 5",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 16,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("TextLabel", {
                Name = "RoomType",
                Size = UDim2.new(0.3, 0, 1, 0),
                Position = UDim2.new(0.7, 0, 0, 0),
                BackgroundTransparency = 1,
                Text = "Steinerner Korridor",
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 12,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Right,
            }),
        }),
        
        -- Enemies Container
        create("Frame", {
            Name = "EnemiesContainer",
            Size = UDim2.new(1, 0, 1, -40),
            Position = UDim2.new(0, 0, 0, 35),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, 15),
            }),
        }),
    })
    
    return display
end

-------------------------------------------------
-- ENEMY UNIT CARD
-------------------------------------------------

local function createEnemyUnit(enemyData, index)
    local isMonster = enemyData.Type == "Monster"
    local icon = enemyData.Icon or (isMonster and "👹" or "🪤")
    local hpPercent = enemyData.MaxHP > 0 and (enemyData.CurrentHP / enemyData.MaxHP) or 1
    
    local unit = create("Frame", {
        Name = "Enemy_" .. index,
        Size = UDim2.new(0, 80, 0, 90),
        BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        LayoutOrder = index,
    }, {
        corner(8),
        stroke(CONFIG.Colors.Error, 1, 0.5),
        
        -- Icon
        create("TextLabel", {
            Name = "Icon",
            Size = UDim2.new(1, 0, 0, 45),
            Position = UDim2.new(0, 0, 0, 5),
            BackgroundTransparency = 1,
            Text = icon,
            TextSize = 30,
        }),
        
        -- Name
        create("TextLabel", {
            Name = "Name",
            Size = UDim2.new(1, -8, 0, 14),
            Position = UDim2.new(0, 4, 0, 50),
            BackgroundTransparency = 1,
            Text = enemyData.Name or "Enemy",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 9,
            Font = Enum.Font.GothamBold,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }),
        
        -- HP Bar
        create("Frame", {
            Name = "HPBarBg",
            Size = UDim2.new(1, -12, 0, 8),
            Position = UDim2.new(0, 6, 0, 66),
            BackgroundColor3 = CONFIG.Colors.Background,
        }, {
            corner(4),
            create("Frame", {
                Name = "HPBarFill",
                Size = UDim2.new(hpPercent, 0, 1, 0),
                BackgroundColor3 = getHealthColor(hpPercent),
            }, {
                corner(4),
            }),
        }),
        
        -- HP Text
        create("TextLabel", {
            Name = "HPText",
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 0, 76),
            BackgroundTransparency = 1,
            Text = formatNumber(enemyData.CurrentHP) .. "/" .. formatNumber(enemyData.MaxHP),
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 8,
            Font = Enum.Font.Gotham,
        }),
    })
    
    return unit
end

-------------------------------------------------
-- COMBAT LOG
-------------------------------------------------

local function createCombatLog()
    local log = create("Frame", {
        Name = "CombatLog",
        Size = UDim2.new(0, 300, 1, 0),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(),
        padding(10),
        
        -- Header
        create("TextLabel", {
            Name = "Header",
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundTransparency = 1,
            Text = "📜 Kampflog",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 14,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Log Entries
        create("ScrollingFrame", {
            Name = "LogEntries",
            Size = UDim2.new(1, 0, 1, -30),
            Position = UDim2.new(0, 0, 0, 28),
            BackgroundTransparency = 1,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = CONFIG.Colors.Border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, {
            create("UIListLayout", {
                Padding = UDim.new(0, 2),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
        }),
    })
    
    return log
end

local function addCombatLogEntry(message, entryType)
    if not combatPanel then return end
    
    local logEntries = combatPanel:FindFirstChild("CombatLog")
    if not logEntries then return end
    
    local entriesScroll = logEntries:FindFirstChild("LogEntries")
    if not entriesScroll then return end
    
    -- Farbe basierend auf Typ
    local textColor = CONFIG.Colors.TextMuted
    if entryType == "Damage" then
        textColor = CONFIG.Colors.DamagePhysical
    elseif entryType == "Heal" then
        textColor = CONFIG.Colors.Healing
    elseif entryType == "Critical" then
        textColor = CONFIG.Colors.Critical
    elseif entryType == "Death" then
        textColor = CONFIG.Colors.Error
    elseif entryType == "Room" then
        textColor = CONFIG.Colors.Primary
    elseif entryType == "Victory" then
        textColor = CONFIG.Colors.Success
    end
    
    local entry = create("TextLabel", {
        Name = "Entry_" .. #screenState.CombatLog,
        Size = UDim2.new(1, 0, 0, CONFIG.LogEntryHeight),
        BackgroundTransparency = 1,
        Text = message,
        TextColor3 = textColor,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = #screenState.CombatLog,
    })
    entry.Parent = entriesScroll
    
    table.insert(screenState.CombatLog, message)
    
    -- Limit entries
    while #screenState.CombatLog > CONFIG.MaxLogEntries do
        table.remove(screenState.CombatLog, 1)
        local firstChild = entriesScroll:FindFirstChild("Entry_1")
        if firstChild then firstChild:Destroy() end
    end
    
    -- Auto-scroll
    entriesScroll.CanvasPosition = Vector2.new(0, entriesScroll.AbsoluteCanvasSize.Y)
end

-------------------------------------------------
-- PREPARATION PANEL
-------------------------------------------------

local function createPreparationPanel()
    local panel = create("Frame", {
        Name = "PreparationPanel",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    })
    
    -- Left Side: Team Overview
    local teamSection = create("Frame", {
        Name = "TeamSection",
        Size = UDim2.new(0.48, 0, 1, 0),
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
            Text = "⚔️ Dein Team",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Team Stats
        create("Frame", {
            Name = "TeamStats",
            Size = UDim2.new(1, 0, 0, 80),
            Position = UDim2.new(0, 0, 0, 40),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(8),
            padding(10),
            
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                Padding = UDim.new(0, 20),
            }),
        }),
        
        -- Team Members
        create("Frame", {
            Name = "TeamMembers",
            Size = UDim2.new(1, 0, 1, -140),
            Position = UDim2.new(0, 0, 0, 130),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Top,
                Padding = UDim.new(0, 10),
            }),
        }),
    })
    teamSection.Parent = panel
    
    -- Right Side: Target Selection
    local targetSection = create("Frame", {
        Name = "TargetSection",
        Size = UDim2.new(0.48, 0, 1, 0),
        Position = UDim2.new(0.52, 0, 0, 0),
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
            Text = "🎯 Ziel auswählen",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        
        -- Cooldown Display
        create("Frame", {
            Name = "CooldownDisplay",
            Size = UDim2.new(1, 0, 0, 40),
            Position = UDim2.new(0, 0, 0, 35),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            Visible = false,
        }, {
            corner(8),
            create("TextLabel", {
                Name = "CooldownText",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "⏱️ Nächster Raid in: 00:00",
                TextColor3 = CONFIG.Colors.Warning,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
            }),
        }),
        
        -- Search Button
        create("TextButton", {
            Name = "SearchButton",
            Size = UDim2.new(1, 0, 0, 50),
            Position = UDim2.new(0, 0, 0, 40),
            BackgroundColor3 = CONFIG.Colors.Primary,
            Text = "🔍 Gegner suchen",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
        }, {
            corner(25),
        }),
        
        -- Target Preview
        create("Frame", {
            Name = "TargetPreview",
            Size = UDim2.new(1, 0, 1, -110),
            Position = UDim2.new(0, 0, 0, 100),
            BackgroundTransparency = 1,
            Visible = false,
        }, {
            -- Target Info Card
            create("Frame", {
                Name = "TargetCard",
                Size = UDim2.new(1, 0, 0, 150),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            }, {
                corner(10),
                stroke(CONFIG.Colors.Error, 2, 0.5),
                padding(12),
                
                create("TextLabel", {
                    Name = "TargetName",
                    Size = UDim2.new(1, 0, 0, 25),
                    BackgroundTransparency = 1,
                    Text = "Gegner Dungeon",
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 16,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
                
                create("TextLabel", {
                    Name = "TargetLevel",
                    Size = UDim2.new(1, 0, 0, 20),
                    Position = UDim2.new(0, 0, 0, 25),
                    BackgroundTransparency = 1,
                    Text = "Level 5 | 5 Räume",
                    TextColor3 = CONFIG.Colors.TextMuted,
                    TextSize = 12,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
                
                create("Frame", {
                    Name = "DifficultyBar",
                    Size = UDim2.new(1, -24, 0, 20),
                    Position = UDim2.new(0, 0, 0, 55),
                    BackgroundTransparency = 1,
                }, {
                    create("TextLabel", {
                        Name = "Label",
                        Size = UDim2.new(0.4, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Text = "Schwierigkeit:",
                        TextColor3 = CONFIG.Colors.TextMuted,
                        TextSize = 11,
                        Font = Enum.Font.Gotham,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }),
                    create("Frame", {
                        Name = "BarBg",
                        Size = UDim2.new(0.55, 0, 0, 10),
                        Position = UDim2.new(0.4, 5, 0.5, -5),
                        BackgroundColor3 = CONFIG.Colors.Background,
                    }, {
                        corner(5),
                        create("Frame", {
                            Name = "BarFill",
                            Size = UDim2.new(0.6, 0, 1, 0),
                            BackgroundColor3 = CONFIG.Colors.Warning,
                        }, {
                            corner(5),
                        }),
                    }),
                }),
                
                create("Frame", {
                    Name = "RewardsPreview",
                    Size = UDim2.new(1, 0, 0, 35),
                    Position = UDim2.new(0, 0, 0, 85),
                    BackgroundTransparency = 1,
                }, {
                    create("TextLabel", {
                        Name = "GoldReward",
                        Size = UDim2.new(0.5, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Text = "💰 200-500",
                        TextColor3 = CONFIG.Colors.Gold,
                        TextSize = 14,
                        Font = Enum.Font.GothamBold,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }),
                    create("TextLabel", {
                        Name = "GemsReward",
                        Size = UDim2.new(0.5, 0, 1, 0),
                        Position = UDim2.new(0.5, 0, 0, 0),
                        BackgroundTransparency = 1,
                        Text = "💎 2-5",
                        TextColor3 = CONFIG.Colors.Gems,
                        TextSize = 14,
                        Font = Enum.Font.GothamBold,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }),
                }),
            }),
            
            -- Buttons
            create("Frame", {
                Name = "Buttons",
                Size = UDim2.new(1, 0, 0, 50),
                Position = UDim2.new(0, 0, 0, 165),
                BackgroundTransparency = 1,
            }, {
                create("TextButton", {
                    Name = "RerollButton",
                    Size = UDim2.new(0.48, 0, 1, 0),
                    BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                    Text = "🔄 Anderer",
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 14,
                    Font = Enum.Font.GothamBold,
                }, {
                    corner(25),
                }),
                create("TextButton", {
                    Name = "StartRaidButton",
                    Size = UDim2.new(0.48, 0, 1, 0),
                    Position = UDim2.new(0.52, 0, 0, 0),
                    BackgroundColor3 = CONFIG.Colors.Success,
                    Text = "⚔️ Angreifen!",
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 14,
                    Font = Enum.Font.GothamBold,
                }, {
                    corner(25),
                }),
            }),
        }),
    })
    targetSection.Parent = panel
    
    -- Button Handlers
    local searchBtn = targetSection:FindFirstChild("SearchButton")
    if searchBtn then
        searchBtn.MouseButton1Click:Connect(function()
            RaidScreen.SearchForTarget()
        end)
    end
    
    local targetPreview = targetSection:FindFirstChild("TargetPreview")
    if targetPreview then
        local rerollBtn = targetPreview.Buttons:FindFirstChild("RerollButton")
        local startBtn = targetPreview.Buttons:FindFirstChild("StartRaidButton")
        
        if rerollBtn then
            rerollBtn.MouseButton1Click:Connect(function()
                RaidScreen.SearchForTarget()
            end)
        end
        
        if startBtn then
            startBtn.MouseButton1Click:Connect(function()
                RaidScreen.StartRaid()
            end)
        end
    end
    
    return panel
end

-------------------------------------------------
-- COMBAT PANEL
-------------------------------------------------

local function createCombatPanel()
    local panel = create("Frame", {
        Name = "CombatPanel",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
    })
    
    -- Top: Progress Bar
    local progressBar = create("Frame", {
        Name = "ProgressBar",
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(),
        padding(10),
        
        -- Room Progress
        create("Frame", {
            Name = "RoomProgress",
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "Label",
                Size = UDim2.new(0.3, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "Raum 1 / 5",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("Frame", {
                Name = "BarBg",
                Size = UDim2.new(0.65, 0, 0, 12),
                Position = UDim2.new(0.3, 10, 0.5, -6),
                BackgroundColor3 = CONFIG.Colors.Background,
            }, {
                corner(6),
                create("Frame", {
                    Name = "BarFill",
                    Size = UDim2.new(0.2, 0, 1, 0),
                    BackgroundColor3 = CONFIG.Colors.Primary,
                }, {
                    corner(6),
                }),
            }),
        }),
    })
    progressBar.Parent = panel
    
    -- Middle: Combat View
    local combatView = create("Frame", {
        Name = "CombatView",
        Size = UDim2.new(1, -320, 1, -70),
        Position = UDim2.new(0, 0, 0, 60),
        BackgroundTransparency = 1,
    })
    combatView.Parent = panel
    
    -- Enemy Section
    local enemySection = createEnemyDisplay()
    enemySection.Position = UDim2.new(0, 0, 0, 0)
    enemySection.Parent = combatView
    
    -- VS Divider
    local vsDivider = create("TextLabel", {
        Name = "VSDivider",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 160),
        BackgroundTransparency = 1,
        Text = "⚔️ VS ⚔️",
        TextColor3 = CONFIG.Colors.Warning,
        TextSize = 20,
        Font = Enum.Font.GothamBold,
    })
    vsDivider.Parent = combatView
    
    -- Hero Section
    local heroSection = create("Frame", {
        Name = "HeroSection",
        Size = UDim2.new(1, 0, 0, 130),
        Position = UDim2.new(0, 0, 0, 210),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(CONFIG.Colors.Success, 2, 0.5),
        padding(10),
        
        create("Frame", {
            Name = "HeroSlots",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, 10),
            }),
        }),
    })
    heroSection.Parent = combatView
    
    -- Right: Combat Log
    local combatLog = createCombatLog()
    combatLog.Position = UDim2.new(1, -300, 0, 60)
    combatLog.Size = UDim2.new(0, 290, 1, -70)
    combatLog.Parent = panel
    
    -- Flee Button
    local fleeButton = create("TextButton", {
        Name = "FleeButton",
        Size = UDim2.new(0, 120, 0, 40),
        Position = UDim2.new(0, 10, 1, -50),
        BackgroundColor3 = CONFIG.Colors.Error,
        Text = "🏃 Fliehen",
        TextColor3 = CONFIG.Colors.Text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
    }, {
        corner(20),
    })
    fleeButton.Parent = panel
    
    fleeButton.MouseButton1Click:Connect(function()
        RaidScreen.FleeRaid()
    end)
    
    return panel
end

-------------------------------------------------
-- RESULT PANEL
-------------------------------------------------

local function createResultPanel()
    local panel = create("Frame", {
        Name = "ResultPanel",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
    })
    
    -- Result Card
    local resultCard = create("Frame", {
        Name = "ResultCard",
        Size = UDim2.new(0, 450, 0, 400),
        Position = UDim2.new(0.5, -225, 0.5, -200),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(16),
        stroke(CONFIG.Colors.Primary, 2),
        padding(20),
        
        -- Result Icon & Title
        create("TextLabel", {
            Name = "ResultIcon",
            Size = UDim2.new(1, 0, 0, 80),
            BackgroundTransparency = 1,
            Text = "🏆",
            TextSize = 60,
        }),
        
        create("TextLabel", {
            Name = "ResultTitle",
            Size = UDim2.new(1, 0, 0, 40),
            Position = UDim2.new(0, 0, 0, 80),
            BackgroundTransparency = 1,
            Text = "SIEG!",
            TextColor3 = CONFIG.Colors.Success,
            TextSize = 32,
            Font = Enum.Font.GothamBold,
        }),
        
        -- Stats
        create("Frame", {
            Name = "StatsSection",
            Size = UDim2.new(1, 0, 0, 80),
            Position = UDim2.new(0, 0, 0, 130),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(10),
            padding(10),
            
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                Padding = UDim.new(0, 30),
            }),
        }),
        
        -- Rewards
        create("Frame", {
            Name = "RewardsSection",
            Size = UDim2.new(1, 0, 0, 100),
            Position = UDim2.new(0, 0, 0, 220),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "RewardsTitle",
                Size = UDim2.new(1, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = "🎁 Belohnungen",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 16,
                Font = Enum.Font.GothamBold,
            }),
            
            create("Frame", {
                Name = "RewardsList",
                Size = UDim2.new(1, 0, 0, 60),
                Position = UDim2.new(0, 0, 0, 30),
                BackgroundTransparency = 1,
            }, {
                create("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalAlignment = Enum.HorizontalAlignment.Center,
                    Padding = UDim.new(0, 20),
                }),
            }),
        }),
        
        -- Continue Button
        create("TextButton", {
            Name = "ContinueButton",
            Size = UDim2.new(1, -40, 0, 50),
            Position = UDim2.new(0, 0, 1, -70),
            BackgroundColor3 = CONFIG.Colors.Primary,
            Text = "Weiter",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
        }, {
            corner(25),
        }),
    })
    resultCard.Parent = panel
    
    -- Continue Handler
    local continueBtn = resultCard:FindFirstChild("ContinueButton")
    if continueBtn then
        continueBtn.MouseButton1Click:Connect(function()
            RaidScreen.CloseResults()
        end)
    end
    
    return panel
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function RaidScreen.Initialize()
    print("[RaidScreen] Initialisiere...")
    
    local screens = MainUI:FindFirstChild("Screens")
    if not screens then return end
    
    screenFrame = screens:FindFirstChild("RaidScreen")
    if not screenFrame then return end
    
    contentFrame = screenFrame:FindFirstChild("Content")
    if not contentFrame then return end
    
    -- Clear existing
    for _, child in ipairs(contentFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    -- Create Panels
    preparationPanel = createPreparationPanel()
    preparationPanel.Parent = contentFrame
    
    combatPanel = createCombatPanel()
    combatPanel.Parent = contentFrame
    
    resultPanel = createResultPanel()
    resultPanel.Parent = contentFrame
    
    -- Load initial data
    RaidScreen.LoadRaidData()
    
    print("[RaidScreen] Initialisiert!")
end

function RaidScreen.LoadRaidData()
    local result = RemoteIndex.Invoke("Raid_GetStatus")
    
    if result then
        screenState.CanRaid = result.CanRaid
        screenState.RaidCooldown = result.Cooldown or 0
        screenState.Team = result.Team or {}
    end
    
    RaidScreen.RefreshPreparationPanel()
end

function RaidScreen.RefreshPreparationPanel()
    if not preparationPanel then return end
    
    -- Update cooldown display
    local targetSection = preparationPanel:FindFirstChild("TargetSection")
    if targetSection then
        local cooldownDisplay = targetSection:FindFirstChild("CooldownDisplay")
        local searchButton = targetSection:FindFirstChild("SearchButton")
        
        if cooldownDisplay and searchButton then
            if screenState.RaidCooldown > 0 then
                cooldownDisplay.Visible = true
                searchButton.Position = UDim2.new(0, 0, 0, 85)
                searchButton.BackgroundColor3 = CONFIG.Colors.SurfaceLight
                searchButton.Text = "⏱️ Warten..."
            else
                cooldownDisplay.Visible = false
                searchButton.Position = UDim2.new(0, 0, 0, 40)
                searchButton.BackgroundColor3 = CONFIG.Colors.Primary
                searchButton.Text = "🔍 Gegner suchen"
            end
        end
    end
    
    -- Update team display
    local teamSection = preparationPanel:FindFirstChild("TeamSection")
    if teamSection then
        local teamMembers = teamSection:FindFirstChild("TeamMembers")
        if teamMembers then
            -- Clear existing
            for _, child in ipairs(teamMembers:GetChildren()) do
                if child:IsA("Frame") then
                    child:Destroy()
                end
            end
            
            -- Add team members
            for i, heroData in ipairs(screenState.Team) do
                local heroConfig = HeroConfig.GetHero(heroData.HeroId)
                if heroConfig then
                    local slot = createHeroCombatSlot(heroData, heroConfig, i)
                    slot.Parent = teamMembers
                end
            end
        end
    end
end

function RaidScreen.SearchForTarget()
    if not screenState.CanRaid then
        if _G.UIManager then
            _G.UIManager.ShowNotification("Cooldown aktiv", "Warte bis der Cooldown abgelaufen ist", "Warning")
        end
        return
    end
    
    screenState.CurrentState = RAID_STATE.Searching
    
    local result = RemoteIndex.Invoke("Raid_FindTarget")
    
    if result and result.Success then
        screenState.TargetDungeon = result.Target
        RaidScreen.ShowTargetPreview(result.Target)
    else
        if _G.UIManager then
            _G.UIManager.ShowNotification("Kein Gegner gefunden", result and result.Error or "Versuche es später erneut", "Warning")
        end
    end
    
    screenState.CurrentState = RAID_STATE.Preparing
end

function RaidScreen.ShowTargetPreview(target)
    if not preparationPanel then return end
    
    local targetSection = preparationPanel:FindFirstChild("TargetSection")
    if not targetSection then return end
    
    local targetPreview = targetSection:FindFirstChild("TargetPreview")
    if not targetPreview then return end
    
    local targetCard = targetPreview:FindFirstChild("TargetCard")
    if targetCard then
        local nameLabel = targetCard:FindFirstChild("TargetName")
        if nameLabel then
            nameLabel.Text = target.Name or "Gegner Dungeon"
        end
        
        local levelLabel = targetCard:FindFirstChild("TargetLevel")
        if levelLabel then
            levelLabel.Text = "Level " .. (target.Level or 1) .. " | " .. (target.RoomCount or 3) .. " Räume"
        end
        
        -- Difficulty
        local difficultyBar = targetCard:FindFirstChild("DifficultyBar")
        if difficultyBar then
            local barBg = difficultyBar:FindFirstChild("BarBg")
            if barBg then
                local barFill = barBg:FindFirstChild("BarFill")
                if barFill then
                    local difficulty = math.clamp((target.Difficulty or 50) / 100, 0, 1)
                    tween(barFill, { Size = UDim2.new(difficulty, 0, 1, 0) }, 0.3)
                    
                    local diffColor = difficulty > 0.7 and CONFIG.Colors.Error or (difficulty > 0.4 and CONFIG.Colors.Warning or CONFIG.Colors.Success)
                    barFill.BackgroundColor3 = diffColor
                end
            end
        end
        
        -- Rewards
        local rewardsPreview = targetCard:FindFirstChild("RewardsPreview")
        if rewardsPreview then
            local goldReward = rewardsPreview:FindFirstChild("GoldReward")
            local gemsReward = rewardsPreview:FindFirstChild("GemsReward")
            
            if goldReward then
                goldReward.Text = "💰 " .. formatNumber(target.RewardGoldMin or 100) .. "-" .. formatNumber(target.RewardGoldMax or 300)
            end
            if gemsReward then
                gemsReward.Text = "💎 " .. (target.RewardGemsMin or 0) .. "-" .. (target.RewardGemsMax or 3)
            end
        end
    end
    
    targetPreview.Visible = true
end

function RaidScreen.StartRaid()
    if not screenState.TargetDungeon then
        if _G.UIManager then
            _G.UIManager.ShowNotification("Kein Ziel", "Suche zuerst einen Gegner!", "Warning")
        end
        return
    end
    
    local result = RemoteIndex.Invoke("Raid_Start", screenState.TargetDungeon.Id)
    
    if result and result.Success then
        screenState.CurrentState = RAID_STATE.InProgress
        screenState.RaidId = result.RaidId
        screenState.TotalRooms = result.TotalRooms or 5
        screenState.CurrentRoom = 0
        screenState.CombatLog = {}
        
        RaidScreen.ShowCombatPanel()
        
        addCombatLogEntry("⚔️ Raid gestartet!", "Room")
    else
        if _G.UIManager then
            _G.UIManager.ShowNotification("Fehler", result and result.Error or "Raid konnte nicht gestartet werden", "Error")
        end
    end
end

function RaidScreen.ShowCombatPanel()
    if preparationPanel then preparationPanel.Visible = false end
    if resultPanel then resultPanel.Visible = false end
    if combatPanel then combatPanel.Visible = true end
end

function RaidScreen.ShowPreparationPanel()
    if combatPanel then combatPanel.Visible = false end
    if resultPanel then resultPanel.Visible = false end
    if preparationPanel then preparationPanel.Visible = true end
end

function RaidScreen.FleeRaid()
    local result = RemoteIndex.Invoke("Raid_Flee", screenState.RaidId)
    
    if result then
        screenState.CurrentState = RAID_STATE.Defeat
        screenState.RaidResult = result
        
        addCombatLogEntry("🏃 Flucht!", "Death")
        
        RaidScreen.ShowResults(result)
    end
end

function RaidScreen.ShowResults(resultData)
    if not resultPanel then return end
    
    if preparationPanel then preparationPanel.Visible = false end
    if combatPanel then combatPanel.Visible = false end
    resultPanel.Visible = true
    
    local resultCard = resultPanel:FindFirstChild("ResultCard")
    if not resultCard then return end
    
    local isVictory = resultData.Status == "Victory"
    
    -- Update result display
    local icon = resultCard:FindFirstChild("ResultIcon")
    local title = resultCard:FindFirstChild("ResultTitle")
    
    if icon then
        icon.Text = isVictory and "🏆" or "💀"
    end
    
    if title then
        title.Text = isVictory and "SIEG!" or "NIEDERLAGE"
        title.TextColor3 = isVictory and CONFIG.Colors.Success or CONFIG.Colors.Error
    end
    
    -- Update stroke color
    local resultStroke = resultCard:FindFirstChildOfClass("UIStroke")
    if resultStroke then
        resultStroke.Color = isVictory and CONFIG.Colors.Success or CONFIG.Colors.Error
    end
    
    -- Update rewards
    local rewardsSection = resultCard:FindFirstChild("RewardsSection")
    if rewardsSection then
        local rewardsList = rewardsSection:FindFirstChild("RewardsList")
        if rewardsList then
            -- Clear existing
            for _, child in ipairs(rewardsList:GetChildren()) do
                if child:IsA("Frame") then
                    child:Destroy()
                end
            end
            
            -- Gold reward
            if resultData.Rewards and resultData.Rewards.Gold and resultData.Rewards.Gold > 0 then
                local goldFrame = create("Frame", {
                    Name = "GoldReward",
                    Size = UDim2.new(0, 120, 0, 50),
                    BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                }, {
                    corner(10),
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 25),
                        BackgroundTransparency = 1,
                        Text = "💰",
                        TextSize = 20,
                    }),
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 25),
                        Position = UDim2.new(0, 0, 0, 25),
                        BackgroundTransparency = 1,
                        Text = "+" .. formatNumber(resultData.Rewards.Gold),
                        TextColor3 = CONFIG.Colors.Gold,
                        TextSize = 16,
                        Font = Enum.Font.GothamBold,
                    }),
                })
                goldFrame.Parent = rewardsList
            end
            
            -- Gems reward
            if resultData.Rewards and resultData.Rewards.Gems and resultData.Rewards.Gems > 0 then
                local gemsFrame = create("Frame", {
                    Name = "GemsReward",
                    Size = UDim2.new(0, 120, 0, 50),
                    BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                }, {
                    corner(10),
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 25),
                        BackgroundTransparency = 1,
                        Text = "💎",
                        TextSize = 20,
                    }),
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 25),
                        Position = UDim2.new(0, 0, 0, 25),
                        BackgroundTransparency = 1,
                        Text = "+" .. formatNumber(resultData.Rewards.Gems),
                        TextColor3 = CONFIG.Colors.Gems,
                        TextSize = 16,
                        Font = Enum.Font.GothamBold,
                    }),
                })
                gemsFrame.Parent = rewardsList
            end
            
            -- XP reward
            if resultData.Rewards and resultData.Rewards.XP and resultData.Rewards.XP > 0 then
                local xpFrame = create("Frame", {
                    Name = "XPReward",
                    Size = UDim2.new(0, 120, 0, 50),
                    BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                }, {
                    corner(10),
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 25),
                        BackgroundTransparency = 1,
                        Text = "⭐",
                        TextSize = 20,
                    }),
                    create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 25),
                        Position = UDim2.new(0, 0, 0, 25),
                        BackgroundTransparency = 1,
                        Text = "+" .. formatNumber(resultData.Rewards.XP) .. " XP",
                        TextColor3 = CONFIG.Colors.Primary,
                        TextSize = 16,
                        Font = Enum.Font.GothamBold,
                    }),
                })
                xpFrame.Parent = rewardsList
            end
        end
    end
end

function RaidScreen.CloseResults()
    screenState.CurrentState = RAID_STATE.Idle
    screenState.RaidId = nil
    screenState.TargetDungeon = nil
    screenState.RaidResult = nil
    
    RaidScreen.LoadRaidData()
    RaidScreen.ShowPreparationPanel()
    
    -- Target Preview ausblenden
    if preparationPanel then
        local targetSection = preparationPanel:FindFirstChild("TargetSection")
        if targetSection then
            local targetPreview = targetSection:FindFirstChild("TargetPreview")
            if targetPreview then
                targetPreview.Visible = false
            end
        end
    end
end

function RaidScreen.UpdateCombat(combatData)
    if not combatPanel then return end
    
    -- Update room progress
    if combatData.CurrentRoom then
        screenState.CurrentRoom = combatData.CurrentRoom
        
        local progressBar = combatPanel:FindFirstChild("ProgressBar")
        if progressBar then
            local roomProgress = progressBar:FindFirstChild("RoomProgress")
            if roomProgress then
                local label = roomProgress:FindFirstChild("Label")
                if label then
                    label.Text = "Raum " .. combatData.CurrentRoom .. " / " .. screenState.TotalRooms
                end
                
                local barBg = roomProgress:FindFirstChild("BarBg")
                if barBg then
                    local barFill = barBg:FindFirstChild("BarFill")
                    if barFill then
                        local progress = combatData.CurrentRoom / screenState.TotalRooms
                        tween(barFill, { Size = UDim2.new(progress, 0, 1, 0) }, 0.3)
                    end
                end
            end
        end
    end
    
    -- Update hero HP
    if combatData.HeroStates then
        local combatView = combatPanel:FindFirstChild("CombatView")
        if combatView then
            local heroSection = combatView:FindFirstChild("HeroSection")
            if heroSection then
                local heroSlots = heroSection:FindFirstChild("HeroSlots")
                if heroSlots then
                    for instanceId, state in pairs(combatData.HeroStates) do
                        local slot = heroSlots:FindFirstChild("HeroSlot_" .. instanceId)
                        if slot then
                            local hpBarBg = slot:FindFirstChild("HPBarBg")
                            if hpBarBg then
                                local hpBarFill = hpBarBg:FindFirstChild("HPBarFill")
                                if hpBarFill then
                                    local hpPercent = state.MaxHP > 0 and (state.CurrentHP / state.MaxHP) or 0
                                    tween(hpBarFill, {
                                        Size = UDim2.new(hpPercent, 0, 1, 0),
                                        BackgroundColor3 = getHealthColor(hpPercent),
                                    }, 0.2)
                                end
                            end
                            
                            local hpText = slot:FindFirstChild("HPText")
                            if hpText then
                                local hpPercent = state.MaxHP > 0 and math.floor((state.CurrentHP / state.MaxHP) * 100) or 0
                                hpText.Text = hpPercent .. "%"
                            end
                            
                            -- Dead overlay
                            local deadOverlay = slot:FindFirstChild("DeadOverlay")
                            if deadOverlay then
                                if state.CurrentHP <= 0 then
                                    deadOverlay.Visible = true
                                    tween(deadOverlay, { BackgroundTransparency = 0.7 }, 0.3)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Combat log entries
    if combatData.LogEntries then
        for _, entry in ipairs(combatData.LogEntries) do
            addCombatLogEntry(entry.Message, entry.Type)
        end
    end
end

-------------------------------------------------
-- REMOTE EVENT HANDLERS
-------------------------------------------------

RemoteIndex.OnClient("Raid_CombatTick", function(data)
    RaidScreen.UpdateCombat(data)
end)

RemoteIndex.OnClient("Raid_RoomCleared", function(data)
    addCombatLogEntry("✅ Raum " .. data.RoomIndex .. " geschafft!", "Room")
    screenState.CurrentRoom = data.RoomIndex
end)

RemoteIndex.OnClient("Raid_End", function(data)
    screenState.CurrentState = data.Status == "Victory" and RAID_STATE.Victory or RAID_STATE.Defeat
    screenState.RaidResult = data
    
    local resultMsg = data.Status == "Victory" and "🏆 SIEG!" or "💀 Niederlage"
    addCombatLogEntry(resultMsg, data.Status == "Victory" and "Victory" or "Death")
    
    task.delay(1, function()
        RaidScreen.ShowResults(data)
    end)
end)

RemoteIndex.OnClient("Cooldown_Update", function(data)
    if data.RaidCooldownRemaining then
        screenState.RaidCooldown = data.RaidCooldownRemaining
        screenState.CanRaid = data.RaidReady
        
        if preparationPanel and preparationPanel.Visible then
            RaidScreen.RefreshPreparationPanel()
        end
    end
end)

-------------------------------------------------
-- COOLDOWN UPDATE LOOP
-------------------------------------------------

task.spawn(function()
    while true do
        task.wait(1)
        
        if screenState.RaidCooldown > 0 then
            screenState.RaidCooldown = screenState.RaidCooldown - 1
            
            if screenState.RaidCooldown <= 0 then
                screenState.CanRaid = true
                RaidScreen.RefreshPreparationPanel()
            else
                -- Update cooldown display
                if preparationPanel and preparationPanel.Visible then
                    local targetSection = preparationPanel:FindFirstChild("TargetSection")
                    if targetSection then
                        local cooldownDisplay = targetSection:FindFirstChild("CooldownDisplay")
                        if cooldownDisplay then
                            local cooldownText = cooldownDisplay:FindFirstChild("CooldownText")
                            if cooldownText then
                                cooldownText.Text = "⏱️ Nächster Raid in: " .. formatTime(screenState.RaidCooldown)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-------------------------------------------------
-- AUTO-INITIALIZE
-------------------------------------------------

task.spawn(function()
    task.wait(0.8)
    RaidScreen.Initialize()
end)

return RaidScreen
