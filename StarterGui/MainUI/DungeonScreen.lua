--[[
    DungeonScreen.lua
    Dungeon-Bau und Verwaltung Screen
    Pfad: StarterGui/MainUI/Screens/DungeonScreen
    
    Dieses Script:
    - Zeigt interaktives Raum-Grid
    - Ermöglicht Raum-Auswahl und Bearbeitung
    - Fallen/Monster Platzierung
    - Dungeon-Statistiken
    
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
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

local DungeonScreen = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Grid Settings
    RoomCardSize = UDim2.new(0, 160, 0, 200),
    RoomCardGap = 12,
    
    -- Slot Settings
    SlotSize = UDim2.new(0, 50, 0, 50),
    SlotGap = 8,
    
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
        Text = Color3.fromRGB(248, 250, 252),
        TextMuted = Color3.fromRGB(148, 163, 184),
        Border = Color3.fromRGB(71, 85, 105),
        
        -- Rarity Colors
        Common = Color3.fromRGB(156, 163, 175),
        Uncommon = Color3.fromRGB(34, 197, 94),
        Rare = Color3.fromRGB(59, 130, 246),
        Epic = Color3.fromRGB(168, 85, 247),
        Legendary = Color3.fromRGB(251, 191, 36),
    },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local screenState = {
    Rooms = {},
    SelectedRoomIndex = nil,
    SelectedSlotType = nil,  -- "Trap" oder "Monster"
    SelectedSlotIndex = nil,
    IsPlacementMode = false,
    DungeonStats = {
        Level = 1,
        RoomCount = 0,
        TrapCount = 0,
        MonsterCount = 0,
        TotalDPS = 0,
    },
}

-------------------------------------------------
-- UI REFERENCES
-------------------------------------------------
local screenFrame = nil
local contentFrame = nil
local roomGrid = nil
local statsPanel = nil
local detailPanel = nil
local placementPanel = nil

-------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------

local function tween(instance, properties, duration)
    local tweenInfo = TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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

local function stroke(color, thickness)
    return create("UIStroke", {
        Color = color or CONFIG.Colors.Border,
        Thickness = thickness or 1,
        Transparency = 0.5,
    })
end

-------------------------------------------------
-- ROOM CARD CREATION
-------------------------------------------------

local function createRoomCard(roomData, roomIndex)
    local roomConfig = RoomConfig.GetRoom(roomData.RoomId)
    if not roomConfig then return nil end
    
    local isSelected = screenState.SelectedRoomIndex == roomIndex
    
    local card = create("TextButton", {
        Name = "Room_" .. roomIndex,
        Size = CONFIG.RoomCardSize,
        BackgroundColor3 = isSelected and CONFIG.Colors.Primary or CONFIG.Colors.Surface,
        Text = "",
        AutoButtonColor = true,
        LayoutOrder = roomIndex,
    }, {
        corner(12),
        stroke(isSelected and CONFIG.Colors.Primary or CONFIG.Colors.Border, isSelected and 2 or 1),
        
        -- Room Icon/Image
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(1, -20, 0, 80),
            Position = UDim2.new(0, 10, 0, 10),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(8),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = roomConfig.Icon or "🏠",
                TextSize = 40,
            }),
        }),
        
        -- Room Name
        create("TextLabel", {
            Name = "RoomName",
            Size = UDim2.new(1, -20, 0, 20),
            Position = UDim2.new(0, 10, 0, 95),
            BackgroundTransparency = 1,
            Text = roomConfig.Name,
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 14,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }),
        
        -- Room Level
        create("TextLabel", {
            Name = "RoomLevel",
            Size = UDim2.new(0, 50, 0, 20),
            Position = UDim2.new(1, -60, 0, 95),
            BackgroundTransparency = 1,
            Text = "Lv." .. (roomData.Level or 1),
            TextColor3 = CONFIG.Colors.Primary,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Right,
        }),
        
        -- Slots Info
        create("Frame", {
            Name = "SlotsInfo",
            Size = UDim2.new(1, -20, 0, 50),
            Position = UDim2.new(0, 10, 0, 120),
            BackgroundTransparency = 1,
        }, {
            -- Trap Slots
            create("Frame", {
                Name = "TrapSlots",
                Size = UDim2.new(0.5, -5, 1, 0),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            }, {
                corner(6),
                create("TextLabel", {
                    Name = "Icon",
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = UDim2.new(0, 5, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "🪤",
                    TextSize = 14,
                }),
                create("TextLabel", {
                    Name = "Count",
                    Size = UDim2.new(1, -30, 1, 0),
                    Position = UDim2.new(0, 25, 0, 0),
                    BackgroundTransparency = 1,
                    Text = (roomData.TrapCount or 0) .. "/" .. (roomConfig.TrapSlots or 0),
                    TextColor3 = CONFIG.Colors.TextMuted,
                    TextSize = 12,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
            }),
            
            -- Monster Slots
            create("Frame", {
                Name = "MonsterSlots",
                Size = UDim2.new(0.5, -5, 1, 0),
                Position = UDim2.new(0.5, 5, 0, 0),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            }, {
                corner(6),
                create("TextLabel", {
                    Name = "Icon",
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = UDim2.new(0, 5, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "👹",
                    TextSize = 14,
                }),
                create("TextLabel", {
                    Name = "Count",
                    Size = UDim2.new(1, -30, 1, 0),
                    Position = UDim2.new(0, 25, 0, 0),
                    BackgroundTransparency = 1,
                    Text = (roomData.MonsterCount or 0) .. "/" .. (roomConfig.MonsterSlots or 0),
                    TextColor3 = CONFIG.Colors.TextMuted,
                    TextSize = 12,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }),
            }),
        }),
        
        -- Room Number Badge
        create("Frame", {
            Name = "RoomBadge",
            Size = UDim2.new(0, 28, 0, 28),
            Position = UDim2.new(0, -5, 0, -5),
            BackgroundColor3 = CONFIG.Colors.Primary,
        }, {
            corner(14),
            create("TextLabel", {
                Name = "Number",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = tostring(roomIndex),
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
            }),
        }),
    })
    
    -- Click Handler
    card.MouseButton1Click:Connect(function()
        DungeonScreen.SelectRoom(roomIndex)
    end)
    
    return card
end

-------------------------------------------------
-- ADD ROOM BUTTON
-------------------------------------------------

local function createAddRoomButton()
    local button = create("TextButton", {
        Name = "AddRoomButton",
        Size = CONFIG.RoomCardSize,
        BackgroundColor3 = CONFIG.Colors.Surface,
        BackgroundTransparency = 0.5,
        Text = "",
        AutoButtonColor = true,
        LayoutOrder = 999,
    }, {
        corner(12),
        stroke(CONFIG.Colors.Border, 1),
        
        create("TextLabel", {
            Name = "Icon",
            Size = UDim2.new(1, 0, 0, 60),
            Position = UDim2.new(0, 0, 0.3, 0),
            BackgroundTransparency = 1,
            Text = "➕",
            TextSize = 40,
            TextColor3 = CONFIG.Colors.TextMuted,
        }),
        
        create("TextLabel", {
            Name = "Label",
            Size = UDim2.new(1, 0, 0, 30),
            Position = UDim2.new(0, 0, 0.6, 0),
            BackgroundTransparency = 1,
            Text = "Raum hinzufügen",
            TextSize = 14,
            TextColor3 = CONFIG.Colors.TextMuted,
            Font = Enum.Font.GothamBold,
        }),
    })
    
    button.MouseButton1Click:Connect(function()
        DungeonScreen.ShowAddRoomPopup()
    end)
    
    return button
end

-------------------------------------------------
-- STATS PANEL
-------------------------------------------------

local function createStatsPanel()
    local panel = create("Frame", {
        Name = "StatsPanel",
        Size = UDim2.new(1, 0, 0, 80),
        BackgroundColor3 = CONFIG.Colors.Surface,
    }, {
        corner(12),
        stroke(),
        
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 20),
        }),
    })
    
    local stats = {
        { Key = "RoomCount", Label = "Räume", Icon = "🏠", Value = "0" },
        { Key = "TrapCount", Label = "Fallen", Icon = "🪤", Value = "0" },
        { Key = "MonsterCount", Label = "Monster", Icon = "👹", Value = "0" },
        { Key = "TotalDPS", Label = "DPS", Icon = "⚔️", Value = "0" },
        { Key = "Difficulty", Label = "Schwierigkeit", Icon = "💀", Value = "0" },
    }
    
    for _, stat in ipairs(stats) do
        local statFrame = create("Frame", {
            Name = stat.Key,
            Size = UDim2.new(0, 100, 0, 60),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = stat.Icon,
                TextSize = 20,
            }),
            create("TextLabel", {
                Name = "Value",
                Size = UDim2.new(1, 0, 0, 20),
                Position = UDim2.new(0, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = stat.Value,
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 16,
                Font = Enum.Font.GothamBold,
            }),
            create("TextLabel", {
                Name = "Label",
                Size = UDim2.new(1, 0, 0, 15),
                Position = UDim2.new(0, 0, 0, 45),
                BackgroundTransparency = 1,
                Text = stat.Label,
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 11,
                Font = Enum.Font.Gotham,
            }),
        })
        
        statFrame.Parent = panel
    end
    
    return panel
end

-------------------------------------------------
-- DETAIL PANEL (Selected Room)
-------------------------------------------------

local function createDetailPanel()
    local panel = create("Frame", {
        Name = "DetailPanel",
        Size = UDim2.new(0, 320, 1, 0),
        Position = UDim2.new(1, -320, 0, 0),
        BackgroundColor3 = CONFIG.Colors.Surface,
        Visible = false,
    }, {
        corner(12),
        stroke(),
        
        create("UIPadding", {
            PaddingTop = UDim.new(0, 15),
            PaddingBottom = UDim.new(0, 15),
            PaddingLeft = UDim.new(0, 15),
            PaddingRight = UDim.new(0, 15),
        }),
        
        -- Header
        create("Frame", {
            Name = "Header",
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "Title",
                Size = UDim2.new(1, -40, 1, 0),
                BackgroundTransparency = 1,
                Text = "Raum Details",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 18,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("TextButton", {
                Name = "CloseButton",
                Size = UDim2.new(0, 30, 0, 30),
                Position = UDim2.new(1, -30, 0, 5),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                Text = "✕",
                TextColor3 = CONFIG.Colors.TextMuted,
                TextSize = 16,
            }, {
                corner(15),
            }),
        }),
        
        -- Room Info
        create("Frame", {
            Name = "RoomInfo",
            Size = UDim2.new(1, 0, 0, 80),
            Position = UDim2.new(0, 0, 0, 50),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(8),
            create("TextLabel", {
                Name = "RoomName",
                Size = UDim2.new(1, -20, 0, 25),
                Position = UDim2.new(0, 10, 0, 10),
                BackgroundTransparency = 1,
                Text = "Steinerner Korridor",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 16,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("TextLabel", {
                Name = "RoomLevel",
                Size = UDim2.new(1, -20, 0, 20),
                Position = UDim2.new(0, 10, 0, 35),
                BackgroundTransparency = 1,
                Text = "Level 1",
                TextColor3 = CONFIG.Colors.Primary,
                TextSize = 14,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("TextButton", {
                Name = "UpgradeButton",
                Size = UDim2.new(0, 80, 0, 30),
                Position = UDim2.new(1, -90, 0.5, -15),
                BackgroundColor3 = CONFIG.Colors.Success,
                Text = "Upgrade",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 12,
                Font = Enum.Font.GothamBold,
            }, {
                corner(15),
            }),
        }),
        
        -- Trap Slots Section
        create("Frame", {
            Name = "TrapSection",
            Size = UDim2.new(1, 0, 0, 120),
            Position = UDim2.new(0, 0, 0, 145),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "SectionTitle",
                Size = UDim2.new(1, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = "🪤 Fallen-Slots",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("Frame", {
                Name = "SlotsContainer",
                Size = UDim2.new(1, 0, 0, 85),
                Position = UDim2.new(0, 0, 0, 30),
                BackgroundTransparency = 1,
            }, {
                create("UIGridLayout", {
                    CellSize = CONFIG.SlotSize,
                    CellPadding = UDim2.new(0, CONFIG.SlotGap, 0, CONFIG.SlotGap),
                    HorizontalAlignment = Enum.HorizontalAlignment.Left,
                }),
            }),
        }),
        
        -- Monster Slots Section
        create("Frame", {
            Name = "MonsterSection",
            Size = UDim2.new(1, 0, 0, 120),
            Position = UDim2.new(0, 0, 0, 275),
            BackgroundTransparency = 1,
        }, {
            create("TextLabel", {
                Name = "SectionTitle",
                Size = UDim2.new(1, 0, 0, 25),
                BackgroundTransparency = 1,
                Text = "👹 Monster-Slots",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
            create("Frame", {
                Name = "SlotsContainer",
                Size = UDim2.new(1, 0, 0, 85),
                Position = UDim2.new(0, 0, 0, 30),
                BackgroundTransparency = 1,
            }, {
                create("UIGridLayout", {
                    CellSize = CONFIG.SlotSize,
                    CellPadding = UDim2.new(0, CONFIG.SlotGap, 0, CONFIG.SlotGap),
                    HorizontalAlignment = Enum.HorizontalAlignment.Left,
                }),
            }),
        }),
        
        -- Actions
        create("Frame", {
            Name = "Actions",
            Size = UDim2.new(1, 0, 0, 40),
            Position = UDim2.new(0, 0, 1, -40),
            BackgroundTransparency = 1,
        }, {
            create("TextButton", {
                Name = "RenameButton",
                Size = UDim2.new(0.48, 0, 1, 0),
                BackgroundColor3 = CONFIG.Colors.SurfaceLight,
                Text = "Umbenennen",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 12,
                Font = Enum.Font.GothamBold,
            }, {
                corner(8),
            }),
            create("TextButton", {
                Name = "RemoveButton",
                Size = UDim2.new(0.48, 0, 1, 0),
                Position = UDim2.new(0.52, 0, 0, 0),
                BackgroundColor3 = CONFIG.Colors.Error,
                Text = "Entfernen",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 12,
                Font = Enum.Font.GothamBold,
            }, {
                corner(8),
            }),
        }),
    })
    
    -- Close Button Handler
    local closeBtn = panel.Header:FindFirstChild("CloseButton")
    if closeBtn then
        closeBtn.MouseButton1Click:Connect(function()
            DungeonScreen.DeselectRoom()
        end)
    end
    
    return panel
end

-------------------------------------------------
-- SLOT CREATION
-------------------------------------------------

local function createSlot(slotType, slotIndex, slotData)
    local isEmpty = slotData == nil or slotData.Id == nil
    
    local slot = create("TextButton", {
        Name = slotType .. "Slot_" .. slotIndex,
        Size = CONFIG.SlotSize,
        BackgroundColor3 = isEmpty and CONFIG.Colors.SurfaceLight or CONFIG.Colors.Surface,
        Text = "",
        AutoButtonColor = true,
    }, {
        corner(8),
        stroke(CONFIG.Colors.Border),
    })
    
    if isEmpty then
        -- Empty slot - Plus icon
        local plusLabel = create("TextLabel", {
            Name = "Plus",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "+",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 24,
            Font = Enum.Font.GothamBold,
        })
        plusLabel.Parent = slot
    else
        -- Filled slot
        local config
        if slotType == "Trap" then
            config = TrapConfig.GetTrap(slotData.TrapId or slotData.Id)
        else
            config = MonsterConfig.GetMonster(slotData.MonsterId or slotData.Id)
        end
        
        if config then
            -- Icon
            local icon = create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 0.7, 0),
                BackgroundTransparency = 1,
                Text = config.Icon or "?",
                TextSize = 22,
            })
            icon.Parent = slot
            
            -- Level Badge
            local levelBadge = create("Frame", {
                Name = "LevelBadge",
                Size = UDim2.new(0, 20, 0, 14),
                Position = UDim2.new(1, -22, 1, -16),
                BackgroundColor3 = getRarityColor(config.Rarity),
            }, {
                corner(4),
                create("TextLabel", {
                    Name = "Level",
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = tostring(slotData.Level or 1),
                    TextColor3 = CONFIG.Colors.Text,
                    TextSize = 10,
                    Font = Enum.Font.GothamBold,
                }),
            })
            levelBadge.Parent = slot
            
            -- Rarity Border
            slot:FindFirstChildOfClass("UIStroke").Color = getRarityColor(config.Rarity)
            slot:FindFirstChildOfClass("UIStroke").Transparency = 0.3
        end
    end
    
    -- Click Handler
    slot.MouseButton1Click:Connect(function()
        DungeonScreen.SelectSlot(slotType, slotIndex)
    end)
    
    return slot
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function DungeonScreen.Initialize()
    print("[DungeonScreen] Initialisiere...")
    
    -- Screen Frame finden
    local screens = MainUI:FindFirstChild("Screens")
    if not screens then return end
    
    screenFrame = screens:FindFirstChild("DungeonScreen")
    if not screenFrame then return end
    
    contentFrame = screenFrame:FindFirstChild("Content")
    if not contentFrame then return end
    
    -- Clear existing content
    for _, child in ipairs(contentFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("ScrollingFrame") then
            child:Destroy()
        end
    end
    
    -- Stats Panel erstellen
    statsPanel = createStatsPanel()
    statsPanel.Parent = contentFrame
    
    -- Room Grid Container
    local gridContainer = create("ScrollingFrame", {
        Name = "RoomGridContainer",
        Size = UDim2.new(1, -340, 1, -100),
        Position = UDim2.new(0, 0, 0, 90),
        BackgroundTransparency = 1,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = CONFIG.Colors.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, {
        create("UIPadding", {
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        }),
        create("UIGridLayout", {
            CellSize = CONFIG.RoomCardSize,
            CellPadding = UDim2.new(0, CONFIG.RoomCardGap, 0, CONFIG.RoomCardGap),
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    gridContainer.Parent = contentFrame
    roomGrid = gridContainer
    
    -- Detail Panel erstellen
    detailPanel = createDetailPanel()
    detailPanel.Parent = contentFrame
    
    -- Initial Data laden
    DungeonScreen.LoadDungeonData()
    
    print("[DungeonScreen] Initialisiert!")
end

function DungeonScreen.LoadDungeonData()
    -- Vom Server laden (oder aus Cache)
    -- Hier nutzen wir erstmal Beispieldaten
    
    screenState.Rooms = {
        { RoomId = "stone_corridor", Level = 1, Traps = {}, Monsters = {}, TrapCount = 0, MonsterCount = 0 },
        { RoomId = "stone_corridor", Level = 2, Traps = { [1] = { TrapId = "spike_floor", Level = 1 } }, Monsters = {}, TrapCount = 1, MonsterCount = 0 },
        { RoomId = "guard_chamber", Level = 1, Traps = {}, Monsters = { [1] = { MonsterId = "skeleton", Level = 1 } }, TrapCount = 0, MonsterCount = 1 },
    }
    
    DungeonScreen.RefreshRoomGrid()
    DungeonScreen.UpdateStats()
end

function DungeonScreen.RefreshRoomGrid()
    if not roomGrid then return end
    
    -- Clear existing cards
    for _, child in ipairs(roomGrid:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    -- Create room cards
    for i, roomData in ipairs(screenState.Rooms) do
        local card = createRoomCard(roomData, i)
        if card then
            card.Parent = roomGrid
        end
    end
    
    -- Add "Add Room" button
    local maxRooms = GameConfig.Dungeon.MaxRooms or 20
    if #screenState.Rooms < maxRooms then
        local addButton = createAddRoomButton()
        addButton.Parent = roomGrid
    end
end

function DungeonScreen.UpdateStats()
    if not statsPanel then return end
    
    local stats = {
        RoomCount = #screenState.Rooms,
        TrapCount = 0,
        MonsterCount = 0,
        TotalDPS = 0,
        Difficulty = 0,
    }
    
    for _, room in ipairs(screenState.Rooms) do
        stats.TrapCount = stats.TrapCount + (room.TrapCount or 0)
        stats.MonsterCount = stats.MonsterCount + (room.MonsterCount or 0)
    end
    
    -- Difficulty berechnen (vereinfacht)
    stats.Difficulty = stats.TrapCount * 10 + stats.MonsterCount * 15 + #screenState.Rooms * 5
    stats.TotalDPS = stats.TrapCount * 25 + stats.MonsterCount * 15
    
    screenState.DungeonStats = stats
    
    -- UI updaten
    for statKey, value in pairs(stats) do
        local statFrame = statsPanel:FindFirstChild(statKey)
        if statFrame then
            local valueLabel = statFrame:FindFirstChild("Value")
            if valueLabel then
                valueLabel.Text = formatNumber(value)
            end
        end
    end
end

function DungeonScreen.SelectRoom(roomIndex)
    -- Vorherige Auswahl aufheben
    if screenState.SelectedRoomIndex then
        local oldCard = roomGrid:FindFirstChild("Room_" .. screenState.SelectedRoomIndex)
        if oldCard then
            tween(oldCard, { BackgroundColor3 = CONFIG.Colors.Surface })
            local oldStroke = oldCard:FindFirstChildOfClass("UIStroke")
            if oldStroke then
                oldStroke.Color = CONFIG.Colors.Border
                oldStroke.Thickness = 1
            end
        end
    end
    
    screenState.SelectedRoomIndex = roomIndex
    
    -- Neue Auswahl markieren
    local newCard = roomGrid:FindFirstChild("Room_" .. roomIndex)
    if newCard then
        tween(newCard, { BackgroundColor3 = CONFIG.Colors.Primary })
        local newStroke = newCard:FindFirstChildOfClass("UIStroke")
        if newStroke then
            newStroke.Color = CONFIG.Colors.Primary
            newStroke.Thickness = 2
        end
    end
    
    -- Detail Panel aktualisieren und anzeigen
    DungeonScreen.UpdateDetailPanel(roomIndex)
    detailPanel.Visible = true
    
    -- Room Grid verkleinern
    tween(roomGrid, { Size = UDim2.new(1, -340, 1, -100) })
end

function DungeonScreen.DeselectRoom()
    if screenState.SelectedRoomIndex then
        local oldCard = roomGrid:FindFirstChild("Room_" .. screenState.SelectedRoomIndex)
        if oldCard then
            tween(oldCard, { BackgroundColor3 = CONFIG.Colors.Surface })
            local oldStroke = oldCard:FindFirstChildOfClass("UIStroke")
            if oldStroke then
                oldStroke.Color = CONFIG.Colors.Border
                oldStroke.Thickness = 1
            end
        end
    end
    
    screenState.SelectedRoomIndex = nil
    detailPanel.Visible = false
    
    -- Room Grid wieder vergrößern
    tween(roomGrid, { Size = UDim2.new(1, -20, 1, -100) })
end

function DungeonScreen.UpdateDetailPanel(roomIndex)
    if not detailPanel then return end
    
    local roomData = screenState.Rooms[roomIndex]
    if not roomData then return end
    
    local roomConfig = RoomConfig.GetRoom(roomData.RoomId)
    if not roomConfig then return end
    
    -- Room Info updaten
    local roomInfo = detailPanel:FindFirstChild("RoomInfo")
    if roomInfo then
        local nameLabel = roomInfo:FindFirstChild("RoomName")
        if nameLabel then
            nameLabel.Text = roomConfig.Name
        end
        
        local levelLabel = roomInfo:FindFirstChild("RoomLevel")
        if levelLabel then
            levelLabel.Text = "Level " .. (roomData.Level or 1)
        end
    end
    
    -- Trap Slots updaten
    local trapSection = detailPanel:FindFirstChild("TrapSection")
    if trapSection then
        local slotsContainer = trapSection:FindFirstChild("SlotsContainer")
        if slotsContainer then
            -- Clear existing slots
            for _, child in ipairs(slotsContainer:GetChildren()) do
                if child:IsA("TextButton") then
                    child:Destroy()
                end
            end
            
            -- Create slots
            local trapSlots = roomConfig.TrapSlots or 3
            for i = 1, trapSlots do
                local slotData = roomData.Traps and roomData.Traps[i]
                local slot = createSlot("Trap", i, slotData)
                slot.Parent = slotsContainer
            end
        end
    end
    
    -- Monster Slots updaten
    local monsterSection = detailPanel:FindFirstChild("MonsterSection")
    if monsterSection then
        local slotsContainer = monsterSection:FindFirstChild("SlotsContainer")
        if slotsContainer then
            -- Clear existing slots
            for _, child in ipairs(slotsContainer:GetChildren()) do
                if child:IsA("TextButton") then
                    child:Destroy()
                end
            end
            
            -- Create slots
            local monsterSlots = roomConfig.MonsterSlots or 2
            for i = 1, monsterSlots do
                local slotData = roomData.Monsters and roomData.Monsters[i]
                local slot = createSlot("Monster", i, slotData)
                slot.Parent = slotsContainer
            end
        end
    end
end

function DungeonScreen.SelectSlot(slotType, slotIndex)
    screenState.SelectedSlotType = slotType
    screenState.SelectedSlotIndex = slotIndex
    
    -- Placement Popup öffnen
    DungeonScreen.ShowPlacementPopup(slotType, slotIndex)
end

function DungeonScreen.ShowAddRoomPopup()
    if _G.UIManager then
        _G.UIManager.ShowNotification("Raum hinzufügen", "Feature kommt bald!", "Info")
    end
end

function DungeonScreen.ShowPlacementPopup(slotType, slotIndex)
    if _G.UIManager then
        local typeName = slotType == "Trap" and "Falle" or "Monster"
        _G.UIManager.ShowNotification(typeName .. " platzieren", "Feature kommt bald!", "Info")
    end
end

-- Remote Event Handler
RemoteIndex.OnClient("Dungeon_Update", function(data)
    if data.Rooms then
        screenState.Rooms = data.Rooms
        DungeonScreen.RefreshRoomGrid()
        DungeonScreen.UpdateStats()
        
        if screenState.SelectedRoomIndex then
            DungeonScreen.UpdateDetailPanel(screenState.SelectedRoomIndex)
        end
    end
end)

-- Auto-Initialize
task.spawn(function()
    task.wait(0.5)  -- Warten bis UI aufgebaut ist
    DungeonScreen.Initialize()
end)

return DungeonScreen
