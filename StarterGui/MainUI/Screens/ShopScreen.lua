--[[
    ShopScreen.lua
    Shop für Unlocks und Upgrades
    Pfad: StarterGui/MainUI/Screens/ShopScreen
    
    Dieses Script:
    - Zeigt verfügbare Items zum Freischalten
    - Tab-Navigation für Kategorien
    - Kauf-System mit Bestätigung
    - Upgrade-Möglichkeiten
    
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
local TrapConfig = require(ConfigPath:WaitForChild("TrapConfig"))
local MonsterConfig = require(ConfigPath:WaitForChild("MonsterConfig"))
local RoomConfig = require(ConfigPath:WaitForChild("RoomConfig"))
local HeroConfig = require(ConfigPath:WaitForChild("HeroConfig"))
local CurrencyUtil = require(ModulesPath:WaitForChild("CurrencyUtil"))
local RemoteIndex = require(RemotesPath:WaitForChild("RemoteIndex"))

local ShopScreen = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Card Settings
    ItemCardSize = UDim2.new(0, 180, 0, 240),
    CardGap = 15,
    
    -- Tab Settings
    TabHeight = 45,
    
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
        
        -- Rarity
        Common = Color3.fromRGB(156, 163, 175),
        Uncommon = Color3.fromRGB(34, 197, 94),
        Rare = Color3.fromRGB(59, 130, 246),
        Epic = Color3.fromRGB(168, 85, 247),
        Legendary = Color3.fromRGB(251, 191, 36),
        
        -- Locked/Unlocked
        Locked = Color3.fromRGB(55, 65, 81),
        Unlocked = Color3.fromRGB(30, 41, 59),
    },
}

-------------------------------------------------
-- SHOP TABS
-------------------------------------------------
local SHOP_TABS = {
    { Id = "Traps", Name = "Fallen", Icon = "🪤" },
    { Id = "Monsters", Name = "Monster", Icon = "👹" },
    { Id = "Rooms", Name = "Räume", Icon = "🏠" },
    { Id = "Heroes", Name = "Helden", Icon = "⚔️" },
    { Id = "Premium", Name = "Premium", Icon = "💎" },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local screenState = {
    CurrentTab = "Traps",
    UnlockedItems = {
        Traps = {},
        Monsters = {},
        Rooms = {},
        Heroes = {},
    },
    PlayerCurrency = {
        Gold = 0,
        Gems = 0,
    },
    SelectedItem = nil,
}

-------------------------------------------------
-- UI REFERENCES
-------------------------------------------------
local screenFrame = nil
local contentFrame = nil
local tabContainer = nil
local itemGrid = nil
local detailPanel = nil

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
-- ITEM DATA GETTERS
-------------------------------------------------

local function getItemsForTab(tabId)
    if tabId == "Traps" then
        return TrapConfig.GetAllTraps()
    elseif tabId == "Monsters" then
        return MonsterConfig.GetAllMonsters()
    elseif tabId == "Rooms" then
        return RoomConfig.GetAllRooms()
    elseif tabId == "Heroes" then
        return HeroConfig.GetAllHeroes()
    elseif tabId == "Premium" then
        return ShopScreen.GetPremiumItems()
    end
    return {}
end

local function isItemUnlocked(tabId, itemId)
    local unlockedList = screenState.UnlockedItems[tabId]
    if unlockedList then
        return unlockedList[itemId] == true
    end
    return false
end

local function canAfford(cost, currency)
    currency = currency or "Gold"
    if currency == "Gold" then
        return screenState.PlayerCurrency.Gold >= cost
    elseif currency == "Gems" then
        return screenState.PlayerCurrency.Gems >= cost
    end
    return false
end

-------------------------------------------------
-- TAB CREATION
-------------------------------------------------

local function createTabBar()
    local tabBar = create("Frame", {
        Name = "TabBar",
        Size = UDim2.new(1, 0, 0, CONFIG.TabHeight + 10),
        BackgroundTransparency = 1,
    }, {
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8),
        }),
    })
    
    for i, tab in ipairs(SHOP_TABS) do
        local isActive = tab.Id == screenState.CurrentTab
        
        local tabButton = create("TextButton", {
            Name = tab.Id .. "Tab",
            Size = UDim2.new(0, 110, 0, CONFIG.TabHeight),
            BackgroundColor3 = isActive and CONFIG.Colors.Primary or CONFIG.Colors.Surface,
            Text = "",
            AutoButtonColor = true,
            LayoutOrder = i,
        }, {
            corner(10),
            stroke(isActive and CONFIG.Colors.Primary or CONFIG.Colors.Border, isActive and 0 or 1),
            
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(0, 30, 1, 0),
                Position = UDim2.new(0, 10, 0, 0),
                BackgroundTransparency = 1,
                Text = tab.Icon,
                TextSize = 18,
            }),
            
            create("TextLabel", {
                Name = "Label",
                Size = UDim2.new(1, -45, 1, 0),
                Position = UDim2.new(0, 40, 0, 0),
                BackgroundTransparency = 1,
                Text = tab.Name,
                TextColor3 = isActive and CONFIG.Colors.Text or CONFIG.Colors.TextMuted,
                TextSize = 14,
                Font = isActive and Enum.Font.GothamBold or Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
        })
        
        tabButton.MouseButton1Click:Connect(function()
            ShopScreen.SwitchTab(tab.Id)
        end)
        
        tabButton.Parent = tabBar
    end
    
    return tabBar
end

-------------------------------------------------
-- ITEM CARD CREATION
-------------------------------------------------

local function createItemCard(itemData, tabId, itemId)
    local isUnlocked = isItemUnlocked(tabId, itemId)
    local cost = itemData.UnlockCost or itemData.Cost or 100
    local currency = itemData.Currency or "Gold"
    local affordable = canAfford(cost, currency)
    
    local cardBgColor = isUnlocked and CONFIG.Colors.Unlocked or CONFIG.Colors.Locked
    local rarityColor = getRarityColor(itemData.Rarity or "Common")
    
    local card = create("TextButton", {
        Name = "Item_" .. itemId,
        Size = CONFIG.ItemCardSize,
        BackgroundColor3 = cardBgColor,
        Text = "",
        AutoButtonColor = true,
    }, {
        corner(12),
        stroke(rarityColor, 2, isUnlocked and 0.3 or 0.6),
        
        -- Locked Overlay
        create("Frame", {
            Name = "LockedOverlay",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = isUnlocked and 1 or 0.5,
            ZIndex = 5,
        }, {
            corner(12),
            create("TextLabel", {
                Name = "LockIcon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = isUnlocked and "" or "🔒",
                TextSize = 40,
                TextTransparency = isUnlocked and 1 or 0,
                ZIndex = 6,
            }),
        }),
        
        -- Rarity Badge
        create("Frame", {
            Name = "RarityBadge",
            Size = UDim2.new(0, 70, 0, 22),
            Position = UDim2.new(0.5, -35, 0, 8),
            BackgroundColor3 = rarityColor,
        }, {
            corner(11),
            create("TextLabel", {
                Name = "RarityText",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = itemData.Rarity or "Common",
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 10,
                Font = Enum.Font.GothamBold,
            }),
        }),
        
        -- Icon Frame
        create("Frame", {
            Name = "IconFrame",
            Size = UDim2.new(0, 80, 0, 80),
            Position = UDim2.new(0.5, -40, 0, 40),
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        }, {
            corner(40),
            stroke(rarityColor, 2, 0.5),
            create("TextLabel", {
                Name = "Icon",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = itemData.Icon or "❓",
                TextSize = 40,
            }),
        }),
        
        -- Item Name
        create("TextLabel", {
            Name = "ItemName",
            Size = UDim2.new(1, -20, 0, 22),
            Position = UDim2.new(0, 10, 0, 130),
            BackgroundTransparency = 1,
            Text = itemData.Name or "Unknown",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 14,
            Font = Enum.Font.GothamBold,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }),
        
        -- Item Description
        create("TextLabel", {
            Name = "Description",
            Size = UDim2.new(1, -20, 0, 30),
            Position = UDim2.new(0, 10, 0, 152),
            BackgroundTransparency = 1,
            Text = itemData.Description or "",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }),
        
        -- Price/Status Bar
        create("Frame", {
            Name = "PriceBar",
            Size = UDim2.new(1, -20, 0, 36),
            Position = UDim2.new(0, 10, 1, -46),
            BackgroundColor3 = isUnlocked and CONFIG.Colors.Success or (affordable and CONFIG.Colors.Primary or CONFIG.Colors.SurfaceLight),
        }, {
            corner(18),
            
            create("TextLabel", {
                Name = "PriceIcon",
                Size = UDim2.new(0, 24, 1, 0),
                Position = UDim2.new(0, 8, 0, 0),
                BackgroundTransparency = 1,
                Text = isUnlocked and "✓" or (currency == "Gold" and "💰" or "💎"),
                TextSize = 16,
            }),
            
            create("TextLabel", {
                Name = "PriceText",
                Size = UDim2.new(1, -40, 1, 0),
                Position = UDim2.new(0, 32, 0, 0),
                BackgroundTransparency = 1,
                Text = isUnlocked and "Freigeschaltet" or formatNumber(cost),
                TextColor3 = CONFIG.Colors.Text,
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
            }),
        }),
    })
    
    -- Click Handler
    card.MouseButton1Click:Connect(function()
        ShopScreen.SelectItem(tabId, itemId, itemData)
    end)
    
    -- Hover Effects
    card.MouseEnter:Connect(function()
        if not isUnlocked then
            tween(card, { BackgroundColor3 = CONFIG.Colors.SurfaceHover }, 0.15)
        end
    end)
    
    card.MouseLeave:Connect(function()
        if not isUnlocked then
            tween(card, { BackgroundColor3 = cardBgColor }, 0.15)
        end
    end)
    
    return card
end

-------------------------------------------------
-- DETAIL PANEL
-------------------------------------------------

local function createDetailPanel()
    local panel = create("Frame", {
        Name = "DetailPanel",
        Size = UDim2.new(0, 320, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),  -- Startet außerhalb
        BackgroundColor3 = CONFIG.Colors.Surface,
        ClipsDescendants = true,
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
        
        -- Item Icon (groß)
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
                Text = "❓",
                TextSize = 50,
            }),
        }),
        
        -- Item Name
        create("TextLabel", {
            Name = "ItemName",
            Size = UDim2.new(1, 0, 0, 30),
            Position = UDim2.new(0, 0, 0, 120),
            BackgroundTransparency = 1,
            Text = "Item Name",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 20,
            Font = Enum.Font.GothamBold,
        }),
        
        -- Rarity
        create("TextLabel", {
            Name = "Rarity",
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 0, 150),
            BackgroundTransparency = 1,
            Text = "Common",
            TextColor3 = CONFIG.Colors.Common,
            TextSize = 14,
            Font = Enum.Font.GothamBold,
        }),
        
        -- Description
        create("TextLabel", {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 60),
            Position = UDim2.new(0, 0, 0, 180),
            BackgroundTransparency = 1,
            Text = "Item description goes here...",
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 13,
            Font = Enum.Font.Gotham,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
        }),
        
        -- Stats Section
        create("Frame", {
            Name = "StatsSection",
            Size = UDim2.new(1, 0, 0, 120),
            Position = UDim2.new(0, 0, 0, 250),
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
                TextSize = 14,
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
                    Padding = UDim.new(0, 5),
                }),
            }),
        }),
        
        -- Purchase Button
        create("TextButton", {
            Name = "PurchaseButton",
            Size = UDim2.new(1, 0, 0, 50),
            Position = UDim2.new(0, 0, 1, -65),
            BackgroundColor3 = CONFIG.Colors.Primary,
            Text = "Freischalten",
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
        }, {
            corner(25),
        }),
    })
    
    -- Close Button Handler
    local closeBtn = panel:FindFirstChild("CloseButton")
    if closeBtn then
        closeBtn.MouseButton1Click:Connect(function()
            ShopScreen.CloseDetailPanel()
        end)
    end
    
    -- Purchase Button Handler
    local purchaseBtn = panel:FindFirstChild("PurchaseButton")
    if purchaseBtn then
        purchaseBtn.MouseButton1Click:Connect(function()
            ShopScreen.PurchaseSelectedItem()
        end)
    end
    
    return panel
end

-------------------------------------------------
-- STAT ROW CREATION
-------------------------------------------------

local function createStatRow(statName, statValue)
    local row = create("Frame", {
        Name = statName,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
    }, {
        create("TextLabel", {
            Name = "StatName",
            Size = UDim2.new(0.6, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = statName,
            TextColor3 = CONFIG.Colors.TextMuted,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),
        create("TextLabel", {
            Name = "StatValue",
            Size = UDim2.new(0.4, 0, 1, 0),
            Position = UDim2.new(0.6, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = tostring(statValue),
            TextColor3 = CONFIG.Colors.Text,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Right,
        }),
    })
    
    return row
end

-------------------------------------------------
-- PREMIUM ITEMS
-------------------------------------------------

function ShopScreen.GetPremiumItems()
    return {
        gem_pack_small = {
            Id = "gem_pack_small",
            Name = "Kleine Gem-Packung",
            Description = "50 Gems für deine Sammlung",
            Icon = "💎",
            Rarity = "Rare",
            Cost = 99,  -- Robux
            Currency = "Robux",
            GemAmount = 50,
        },
        gem_pack_medium = {
            Id = "gem_pack_medium",
            Name = "Mittlere Gem-Packung",
            Description = "150 Gems + 20% Bonus",
            Icon = "💎",
            Rarity = "Epic",
            Cost = 249,
            Currency = "Robux",
            GemAmount = 180,
        },
        gem_pack_large = {
            Id = "gem_pack_large",
            Name = "Große Gem-Packung",
            Description = "500 Gems + 50% Bonus",
            Icon = "💎",
            Rarity = "Legendary",
            Cost = 699,
            Currency = "Robux",
            GemAmount = 750,
        },
        vip_pass = {
            Id = "vip_pass",
            Name = "VIP-Pass",
            Description = "+25% Einkommen, exklusive Items",
            Icon = "⭐",
            Rarity = "Legendary",
            Cost = 499,
            Currency = "Robux",
        },
        starter_pack = {
            Id = "starter_pack",
            Name = "Starter-Paket",
            Description = "10.000 Gold + 50 Gems + Rare Held",
            Icon = "🎁",
            Rarity = "Epic",
            Cost = 149,
            Currency = "Robux",
        },
    }
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function ShopScreen.Initialize()
    print("[ShopScreen] Initialisiere...")
    
    -- Screen Frame finden
    local screens = MainUI:FindFirstChild("Screens")
    if not screens then return end
    
    screenFrame = screens:FindFirstChild("ShopScreen")
    if not screenFrame then return end
    
    contentFrame = screenFrame:FindFirstChild("Content")
    if not contentFrame then return end
    
    -- Clear existing content
    for _, child in ipairs(contentFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("ScrollingFrame") then
            child:Destroy()
        end
    end
    
    -- Tab Bar erstellen
    tabContainer = createTabBar()
    tabContainer.Parent = contentFrame
    
    -- Item Grid Container
    itemGrid = create("ScrollingFrame", {
        Name = "ItemGrid",
        Size = UDim2.new(1, 0, 1, -CONFIG.TabHeight - 20),
        Position = UDim2.new(0, 0, 0, CONFIG.TabHeight + 15),
        BackgroundTransparency = 1,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = CONFIG.Colors.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, {
        padding(10),
        create("UIGridLayout", {
            CellSize = CONFIG.ItemCardSize,
            CellPadding = UDim2.new(0, CONFIG.CardGap, 0, CONFIG.CardGap),
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    itemGrid.Parent = contentFrame
    
    -- Detail Panel erstellen
    detailPanel = createDetailPanel()
    detailPanel.Parent = contentFrame
    
    -- Initial Load
    ShopScreen.LoadShopData()
    ShopScreen.RefreshItemGrid()
    
    print("[ShopScreen] Initialisiert!")
end

function ShopScreen.LoadShopData()
    -- Unlocked Items vom Server laden
    local result = RemoteIndex.Invoke("Shop_GetUnlocked")
    
    if result and result.Success then
        screenState.UnlockedItems = result.Unlocked or screenState.UnlockedItems
    end
    
    -- Currency updaten
    local currencyResult = RemoteIndex.Invoke("Currency_Request")
    if currencyResult and currencyResult.Success then
        screenState.PlayerCurrency.Gold = currencyResult.Gold or 0
        screenState.PlayerCurrency.Gems = currencyResult.Gems or 0
    end
end

function ShopScreen.SwitchTab(tabId)
    if screenState.CurrentTab == tabId then return end
    
    screenState.CurrentTab = tabId
    
    -- Tab Buttons updaten
    if tabContainer then
        for _, button in ipairs(tabContainer:GetChildren()) do
            if button:IsA("TextButton") then
                local isActive = button.Name == tabId .. "Tab"
                
                tween(button, {
                    BackgroundColor3 = isActive and CONFIG.Colors.Primary or CONFIG.Colors.Surface,
                }, 0.2)
                
                local btnStroke = button:FindFirstChildOfClass("UIStroke")
                if btnStroke then
                    btnStroke.Color = isActive and CONFIG.Colors.Primary or CONFIG.Colors.Border
                    btnStroke.Transparency = isActive and 1 or 0.5
                end
                
                local label = button:FindFirstChild("Label")
                if label then
                    tween(label, {
                        TextColor3 = isActive and CONFIG.Colors.Text or CONFIG.Colors.TextMuted,
                    }, 0.2)
                    label.Font = isActive and Enum.Font.GothamBold or Enum.Font.Gotham
                end
            end
        end
    end
    
    -- Detail Panel schließen
    ShopScreen.CloseDetailPanel()
    
    -- Grid neu laden
    ShopScreen.RefreshItemGrid()
end

function ShopScreen.RefreshItemGrid()
    if not itemGrid then return end
    
    -- Clear existing items
    for _, child in ipairs(itemGrid:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    -- Items für aktuellen Tab laden
    local items = getItemsForTab(screenState.CurrentTab)
    
    local layoutOrder = 1
    for itemId, itemData in pairs(items) do
        local card = createItemCard(itemData, screenState.CurrentTab, itemId)
        if card then
            card.LayoutOrder = layoutOrder
            card.Parent = itemGrid
            layoutOrder = layoutOrder + 1
        end
    end
end

function ShopScreen.SelectItem(tabId, itemId, itemData)
    screenState.SelectedItem = {
        TabId = tabId,
        ItemId = itemId,
        Data = itemData,
    }
    
    ShopScreen.UpdateDetailPanel(itemData, tabId, itemId)
    ShopScreen.OpenDetailPanel()
end

function ShopScreen.UpdateDetailPanel(itemData, tabId, itemId)
    if not detailPanel then return end
    
    local isUnlocked = isItemUnlocked(tabId, itemId)
    local cost = itemData.UnlockCost or itemData.Cost or 100
    local currency = itemData.Currency or "Gold"
    local affordable = canAfford(cost, currency)
    local rarityColor = getRarityColor(itemData.Rarity or "Common")
    
    -- Icon updaten
    local iconFrame = detailPanel:FindFirstChild("IconFrame")
    if iconFrame then
        local icon = iconFrame:FindFirstChild("Icon")
        if icon then
            icon.Text = itemData.Icon or "❓"
        end
        
        local iconStroke = iconFrame:FindFirstChildOfClass("UIStroke")
        if not iconStroke then
            iconStroke = stroke(rarityColor, 3, 0.3)
            iconStroke.Parent = iconFrame
        else
            iconStroke.Color = rarityColor
        end
    end
    
    -- Name
    local nameLabel = detailPanel:FindFirstChild("ItemName")
    if nameLabel then
        nameLabel.Text = itemData.Name or "Unknown"
    end
    
    -- Rarity
    local rarityLabel = detailPanel:FindFirstChild("Rarity")
    if rarityLabel then
        rarityLabel.Text = itemData.Rarity or "Common"
        rarityLabel.TextColor3 = rarityColor
    end
    
    -- Description
    local descLabel = detailPanel:FindFirstChild("Description")
    if descLabel then
        descLabel.Text = itemData.Description or ""
    end
    
    -- Stats
    local statsSection = detailPanel:FindFirstChild("StatsSection")
    if statsSection then
        local statsList = statsSection:FindFirstChild("StatsList")
        if statsList then
            -- Clear existing stats
            for _, child in ipairs(statsList:GetChildren()) do
                if child:IsA("Frame") then
                    child:Destroy()
                end
            end
            
            -- Stats basierend auf Tab
            local stats = {}
            if tabId == "Traps" then
                stats = {
                    { "Schaden", itemData.Damage or 0 },
                    { "Cooldown", (itemData.Cooldown or 0) .. "s" },
                    { "Element", itemData.Element or "Physical" },
                }
            elseif tabId == "Monsters" then
                stats = {
                    { "HP", itemData.Health or 0 },
                    { "Schaden", itemData.Damage or 0 },
                    { "Geschwindigkeit", itemData.Speed or 0 },
                }
            elseif tabId == "Rooms" then
                stats = {
                    { "Fallen-Slots", itemData.TrapSlots or 0 },
                    { "Monster-Slots", itemData.MonsterSlots or 0 },
                    { "Bonus", (itemData.Bonus or 0) .. "%" },
                }
            elseif tabId == "Heroes" then
                stats = {
                    { "HP", itemData.Health or 0 },
                    { "Schaden", itemData.Damage or 0 },
                    { "Klasse", itemData.Class or "Warrior" },
                }
            end
            
            for _, stat in ipairs(stats) do
                local row = createStatRow(stat[1], stat[2])
                row.Parent = statsList
            end
        end
    end
    
    -- Purchase Button
    local purchaseBtn = detailPanel:FindFirstChild("PurchaseButton")
    if purchaseBtn then
        if isUnlocked then
            purchaseBtn.Text = "✓ Freigeschaltet"
            purchaseBtn.BackgroundColor3 = CONFIG.Colors.Success
            purchaseBtn.Active = false
        elseif affordable then
            local currencyIcon = currency == "Gold" and "💰" or (currency == "Gems" and "💎" or "R$")
            purchaseBtn.Text = currencyIcon .. " " .. formatNumber(cost) .. " freischalten"
            purchaseBtn.BackgroundColor3 = CONFIG.Colors.Primary
            purchaseBtn.Active = true
        else
            purchaseBtn.Text = "Nicht genug " .. currency
            purchaseBtn.BackgroundColor3 = CONFIG.Colors.Error
            purchaseBtn.Active = false
        end
    end
end

function ShopScreen.OpenDetailPanel()
    if not detailPanel then return end
    
    detailPanel.Visible = true
    tween(detailPanel, { Position = UDim2.new(1, -320, 0, 0) }, 0.25, Enum.EasingStyle.Back)
    
    -- Item Grid verkleinern
    tween(itemGrid, { Size = UDim2.new(1, -340, 1, -CONFIG.TabHeight - 20) }, 0.2)
end

function ShopScreen.CloseDetailPanel()
    if not detailPanel then return end
    
    tween(detailPanel, { Position = UDim2.new(1, 0, 0, 0) }, 0.2)
    
    task.delay(0.2, function()
        detailPanel.Visible = false
    end)
    
    -- Item Grid wieder vergrößern
    tween(itemGrid, { Size = UDim2.new(1, 0, 1, -CONFIG.TabHeight - 20) }, 0.2)
    
    screenState.SelectedItem = nil
end

function ShopScreen.PurchaseSelectedItem()
    if not screenState.SelectedItem then return end
    
    local item = screenState.SelectedItem
    local isUnlocked = isItemUnlocked(item.TabId, item.ItemId)
    
    if isUnlocked then
        if _G.UIManager then
            _G.UIManager.ShowNotification("Bereits freigeschaltet", "Dieses Item hast du schon!", "Info")
        end
        return
    end
    
    -- Server Request
    local result = RemoteIndex.Invoke("Shop_Unlock", item.TabId, item.ItemId)
    
    if result and result.Success then
        -- Lokalen State updaten
        if not screenState.UnlockedItems[item.TabId] then
            screenState.UnlockedItems[item.TabId] = {}
        end
        screenState.UnlockedItems[item.TabId][item.ItemId] = true
        
        -- Currency updaten
        if result.NewGold then
            screenState.PlayerCurrency.Gold = result.NewGold
        end
        if result.NewGems then
            screenState.PlayerCurrency.Gems = result.NewGems
        end
        
        -- UI updaten
        ShopScreen.RefreshItemGrid()
        ShopScreen.UpdateDetailPanel(item.Data, item.TabId, item.ItemId)
        
        if _G.UIManager then
            _G.UIManager.ShowNotification(
                "Freigeschaltet!",
                item.Data.Name .. " wurde freigeschaltet!",
                "Success"
            )
        end
    else
        if _G.UIManager then
            _G.UIManager.ShowNotification(
                "Fehler",
                result and result.Error or "Kauf fehlgeschlagen",
                "Error"
            )
        end
    end
end

-------------------------------------------------
-- REMOTE EVENT HANDLERS
-------------------------------------------------

RemoteIndex.OnClient("Currency_Update", function(data)
    if data.Gold then
        screenState.PlayerCurrency.Gold = data.Gold
    end
    if data.Gems then
        screenState.PlayerCurrency.Gems = data.Gems
    end
    
    -- Grid neu laden um Preise zu aktualisieren
    if screenState.CurrentTab and itemGrid then
        ShopScreen.RefreshItemGrid()
    end
end)

RemoteIndex.OnClient("Shop_ItemUnlocked", function(data)
    if data.TabId and data.ItemId then
        if not screenState.UnlockedItems[data.TabId] then
            screenState.UnlockedItems[data.TabId] = {}
        end
        screenState.UnlockedItems[data.TabId][data.ItemId] = true
        
        ShopScreen.RefreshItemGrid()
    end
end)

-------------------------------------------------
-- AUTO-INITIALIZE
-------------------------------------------------

task.spawn(function()
    task.wait(0.6)  -- Warten bis UI aufgebaut ist
    ShopScreen.Initialize()
end)

return ShopScreen
