--[[
    InputController.lua
    Zentrales Input-Handling
    Pfad: StarterPlayer/StarterPlayerScripts/Client/Controllers/InputController
    
    Verantwortlich für:
    - Plattform-Erkennung (Desktop, Mobile, Console)
    - Keyboard/Mouse Input
    - Touch Input
    - Gamepad Input
    - Action Mapping
    
    WICHTIG: Alle Inputs werden hier zentral verarbeitet!
]]

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared Modules
local SharedPath = ReplicatedStorage:WaitForChild("Shared")
local ModulesPath = SharedPath:WaitForChild("Modules")
local ConfigPath = SharedPath:WaitForChild("Config")

local SignalUtil = require(ModulesPath:WaitForChild("SignalUtil"))
local GameConfig = require(ConfigPath:WaitForChild("GameConfig"))

-- Controller Referenzen (werden bei Initialize gesetzt)
local UIController = nil
local CameraController = nil
local ClientState = nil

local InputController = {}

-------------------------------------------------
-- KONFIGURATION
-------------------------------------------------
local CONFIG = {
    -- Touch Settings
    DoubleTapTime = 0.3,        -- Sekunden für Double-Tap
    LongPressTime = 0.5,        -- Sekunden für Long-Press
    SwipeThreshold = 50,        -- Pixel für Swipe-Erkennung
    PinchThreshold = 20,        -- Pixel für Pinch-Erkennung
    
    -- Mouse Settings
    DragThreshold = 5,          -- Pixel bevor Drag startet
    
    -- Gamepad Settings
    DeadZone = 0.2,             -- Stick Deadzone
    
    -- Debug
    Debug = GameConfig.Debug.Enabled,
}

-------------------------------------------------
-- INPUT STATE
-------------------------------------------------
local inputState = {
    -- Plattform
    Platform = "Desktop",       -- Desktop, Mobile, Console
    
    -- Input Mode
    Mode = "Normal",            -- Normal, Build, Raid, Menu
    
    -- Mouse/Touch State
    IsMouseDown = false,
    IsTouching = false,
    IsDragging = false,
    DragStartPosition = nil,
    
    -- Touch Gestures
    TouchStartTime = 0,
    TouchStartPosition = nil,
    LastTapTime = 0,
    ActiveTouches = {},         -- { [touchId] = { Position, StartTime } }
    
    -- Keyboard State
    HeldKeys = {},              -- { [KeyCode] = true }
    
    -- Gamepad State
    GamepadConnected = false,
    LeftStick = Vector2.new(0, 0),
    RightStick = Vector2.new(0, 0),
}

-------------------------------------------------
-- ACTION BINDINGS
-------------------------------------------------
local actionBindings = {
    -- Keyboard Actions
    Keyboard = {
        [Enum.KeyCode.Escape] = "Cancel",
        [Enum.KeyCode.Tab] = "ToggleMenu",
        [Enum.KeyCode.E] = "Interact",
        [Enum.KeyCode.R] = "Rotate",
        [Enum.KeyCode.Delete] = "Delete",
        [Enum.KeyCode.One] = "QuickSlot1",
        [Enum.KeyCode.Two] = "QuickSlot2",
        [Enum.KeyCode.Three] = "QuickSlot3",
        [Enum.KeyCode.Four] = "QuickSlot4",
        [Enum.KeyCode.F] = "CollectIncome",
        [Enum.KeyCode.Space] = "Confirm",
    },
    
    -- Gamepad Actions
    Gamepad = {
        [Enum.KeyCode.ButtonA] = "Confirm",
        [Enum.KeyCode.ButtonB] = "Cancel",
        [Enum.KeyCode.ButtonX] = "Interact",
        [Enum.KeyCode.ButtonY] = "ToggleMenu",
        [Enum.KeyCode.ButtonL1] = "PrevTab",
        [Enum.KeyCode.ButtonR1] = "NextTab",
        [Enum.KeyCode.DPadUp] = "NavUp",
        [Enum.KeyCode.DPadDown] = "NavDown",
        [Enum.KeyCode.DPadLeft] = "NavLeft",
        [Enum.KeyCode.DPadRight] = "NavRight",
    },
}

-------------------------------------------------
-- SIGNALS
-------------------------------------------------
InputController.Signals = {
    -- Basic Input
    ActionTriggered = SignalUtil.new(),     -- (actionName, inputState)
    
    -- Mouse/Touch
    Click = SignalUtil.new(),               -- (position, button)
    DragStart = SignalUtil.new(),           -- (startPosition)
    DragUpdate = SignalUtil.new(),          -- (currentPosition, delta)
    DragEnd = SignalUtil.new(),             -- (endPosition)
    
    -- Touch Gestures
    Tap = SignalUtil.new(),                 -- (position)
    DoubleTap = SignalUtil.new(),           -- (position)
    LongPress = SignalUtil.new(),           -- (position)
    Swipe = SignalUtil.new(),               -- (direction, velocity)
    Pinch = SignalUtil.new(),               -- (scale, center)
    
    -- Camera
    CameraRotate = SignalUtil.new(),        -- (deltaX, deltaY)
    CameraZoom = SignalUtil.new(),          -- (delta)
    CameraPan = SignalUtil.new(),           -- (delta)
    
    -- Selection
    ObjectSelected = SignalUtil.new(),      -- (object, position)
    ObjectHovered = SignalUtil.new(),       -- (object, position)
    
    -- Mode
    ModeChanged = SignalUtil.new(),         -- (newMode, oldMode)
}

-------------------------------------------------
-- PRIVATE HILFSFUNKTIONEN
-------------------------------------------------

local function debugPrint(...)
    if CONFIG.Debug then
        print("[InputController]", ...)
    end
end

--[[
    Erkennt die aktuelle Plattform
    @return: Platform-String
]]
local function detectPlatform()
    if GuiService:IsTenFootInterface() then
        return "Console"
    elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return "Mobile"
    else
        return "Desktop"
    end
end

--[[
    Wendet Deadzone auf Stick-Input an
    @param value: Input-Wert
    @return: Verarbeiteter Wert
]]
local function applyDeadzone(value)
    local magnitude = value.Magnitude
    if magnitude < CONFIG.DeadZone then
        return Vector2.new(0, 0)
    end
    
    local normalizedMagnitude = (magnitude - CONFIG.DeadZone) / (1 - CONFIG.DeadZone)
    return value.Unit * normalizedMagnitude
end

--[[
    Berechnet Swipe-Richtung
    @param startPos: Start-Position
    @param endPos: End-Position
    @return: direction (Up/Down/Left/Right), velocity
]]
local function calculateSwipe(startPos, endPos)
    local delta = endPos - startPos
    local magnitude = delta.Magnitude
    
    if magnitude < CONFIG.SwipeThreshold then
        return nil, 0
    end
    
    local normalized = delta.Unit
    local velocity = magnitude
    
    -- Richtung bestimmen
    if math.abs(normalized.X) > math.abs(normalized.Y) then
        if normalized.X > 0 then
            return "Right", velocity
        else
            return "Left", velocity
        end
    else
        if normalized.Y > 0 then
            return "Down", velocity
        else
            return "Up", velocity
        end
    end
end

--[[
    Verarbeitet Action für Key
    @param keyCode: Der gedrückte Key
    @param inputType: Keyboard oder Gamepad
    @param inputState: Began oder Ended
]]
local function processKeyAction(keyCode, inputType, inputStateType)
    local bindings = actionBindings[inputType]
    if not bindings then return end
    
    local action = bindings[keyCode]
    if not action then return end
    
    if inputStateType == Enum.UserInputState.Begin then
        InputController.Signals.ActionTriggered:Fire(action, "Began")
        InputController._handleAction(action, "Began")
    elseif inputStateType == Enum.UserInputState.End then
        InputController.Signals.ActionTriggered:Fire(action, "Ended")
        InputController._handleAction(action, "Ended")
    end
end

-------------------------------------------------
-- INPUT HANDLERS
-------------------------------------------------

--[[
    Keyboard Input Handler
]]
local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end
    
    -- Keyboard
    if input.UserInputType == Enum.UserInputType.Keyboard then
        inputState.HeldKeys[input.KeyCode] = true
        processKeyAction(input.KeyCode, "Keyboard", Enum.UserInputState.Begin)
    end
    
    -- Mouse Button
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        inputState.IsMouseDown = true
        inputState.DragStartPosition = input.Position
        inputState.IsDragging = false
    end
    
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        -- Rechtsklick für Kamera-Rotation
        inputState.IsRightMouseDown = true
    end
    
    if input.UserInputType == Enum.UserInputType.MouseButton3 then
        -- Mittelklick für Kamera-Pan
        inputState.IsMiddleMouseDown = true
    end
    
    -- Gamepad
    if input.UserInputType == Enum.UserInputType.Gamepad1 then
        processKeyAction(input.KeyCode, "Gamepad", Enum.UserInputState.Begin)
    end
end

local function onInputEnded(input, gameProcessed)
    -- Keyboard
    if input.UserInputType == Enum.UserInputType.Keyboard then
        inputState.HeldKeys[input.KeyCode] = nil
        processKeyAction(input.KeyCode, "Keyboard", Enum.UserInputState.End)
    end
    
    -- Mouse Button
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if inputState.IsDragging then
            InputController.Signals.DragEnd:Fire(input.Position)
        else
            -- Click
            InputController.Signals.Click:Fire(input.Position, 1)
        end
        
        inputState.IsMouseDown = false
        inputState.IsDragging = false
        inputState.DragStartPosition = nil
    end
    
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        inputState.IsRightMouseDown = false
    end
    
    if input.UserInputType == Enum.UserInputType.MouseButton3 then
        inputState.IsMiddleMouseDown = false
    end
    
    -- Gamepad
    if input.UserInputType == Enum.UserInputType.Gamepad1 then
        processKeyAction(input.KeyCode, "Gamepad", Enum.UserInputState.End)
    end
end

local function onInputChanged(input, gameProcessed)
    -- Mouse Movement
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if inputState.IsMouseDown and inputState.DragStartPosition then
            local delta = input.Position - inputState.DragStartPosition
            
            if not inputState.IsDragging and delta.Magnitude > CONFIG.DragThreshold then
                inputState.IsDragging = true
                InputController.Signals.DragStart:Fire(inputState.DragStartPosition)
            end
            
            if inputState.IsDragging then
                InputController.Signals.DragUpdate:Fire(input.Position, delta)
            end
        end
        
        -- Kamera-Rotation mit Rechtsklick
        if inputState.IsRightMouseDown then
            InputController.Signals.CameraRotate:Fire(input.Delta.X, input.Delta.Y)
        end
        
        -- Kamera-Pan mit Mittelklick
        if inputState.IsMiddleMouseDown then
            InputController.Signals.CameraPan:Fire(input.Delta)
        end
    end
    
    -- Mouse Wheel (Zoom)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        InputController.Signals.CameraZoom:Fire(input.Position.Z)
    end
    
    -- Gamepad Thumbsticks
    if input.UserInputType == Enum.UserInputType.Gamepad1 then
        if input.KeyCode == Enum.KeyCode.Thumbstick1 then
            inputState.LeftStick = applyDeadzone(Vector2.new(input.Position.X, input.Position.Y))
        elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
            inputState.RightStick = applyDeadzone(Vector2.new(input.Position.X, input.Position.Y))
            
            if inputState.RightStick.Magnitude > 0 then
                InputController.Signals.CameraRotate:Fire(
                    inputState.RightStick.X * 5,
                    inputState.RightStick.Y * 5
                )
            end
        end
    end
end

--[[
    Touch Input Handlers
]]
local function onTouchStarted(touch, gameProcessed)
    if gameProcessed then return end
    
    local touchId = touch.Position
    inputState.ActiveTouches[tostring(touchId)] = {
        Position = touch.Position,
        StartTime = tick(),
        StartPosition = touch.Position,
    }
    
    inputState.IsTouching = true
    inputState.TouchStartTime = tick()
    inputState.TouchStartPosition = touch.Position
    
    -- Long Press Detection
    local startPos = touch.Position
    task.delay(CONFIG.LongPressTime, function()
        if inputState.IsTouching and inputState.TouchStartPosition then
            local currentPos = inputState.TouchStartPosition
            if (currentPos - startPos).Magnitude < CONFIG.SwipeThreshold then
                InputController.Signals.LongPress:Fire(startPos)
            end
        end
    end)
end

local function onTouchEnded(touch, gameProcessed)
    local touchId = tostring(touch.Position)
    local touchData = inputState.ActiveTouches[touchId]
    
    if touchData then
        inputState.ActiveTouches[touchId] = nil
    end
    
    if not inputState.IsTouching then return end
    
    local touchDuration = tick() - inputState.TouchStartTime
    local startPos = inputState.TouchStartPosition
    local endPos = touch.Position
    
    if startPos then
        -- Swipe Detection
        local swipeDir, velocity = calculateSwipe(startPos, endPos)
        if swipeDir then
            InputController.Signals.Swipe:Fire(swipeDir, velocity)
        else
            -- Tap Detection
            if touchDuration < CONFIG.LongPressTime then
                local currentTime = tick()
                
                -- Double Tap Detection
                if currentTime - inputState.LastTapTime < CONFIG.DoubleTapTime then
                    InputController.Signals.DoubleTap:Fire(endPos)
                else
                    InputController.Signals.Tap:Fire(endPos)
                    InputController.Signals.Click:Fire(endPos, 1)
                end
                
                inputState.LastTapTime = currentTime
            end
        end
    end
    
    -- Reset wenn keine Touches mehr aktiv
    local touchCount = 0
    for _ in pairs(inputState.ActiveTouches) do
        touchCount = touchCount + 1
    end
    
    if touchCount == 0 then
        inputState.IsTouching = false
        inputState.TouchStartPosition = nil
    end
end

local function onTouchMoved(touch, gameProcessed)
    -- Pinch Detection (2 Finger)
    local touches = {}
    for _, t in pairs(inputState.ActiveTouches) do
        table.insert(touches, t)
    end
    
    if #touches == 2 then
        local pos1 = touches[1].Position
        local pos2 = touches[2].Position
        local currentDistance = (pos1 - pos2).Magnitude
        
        local startPos1 = touches[1].StartPosition
        local startPos2 = touches[2].StartPosition
        local startDistance = (startPos1 - startPos2).Magnitude
        
        if math.abs(currentDistance - startDistance) > CONFIG.PinchThreshold then
            local scale = currentDistance / startDistance
            local center = (pos1 + pos2) / 2
            InputController.Signals.Pinch:Fire(scale, center)
            InputController.Signals.CameraZoom:Fire((scale - 1) * 10)
        end
    elseif #touches == 1 and inputState.IsTouching then
        -- Single finger drag
        local delta = touch.Position - (inputState.TouchStartPosition or touch.Position)
        
        if delta.Magnitude > CONFIG.DragThreshold then
            if not inputState.IsDragging then
                inputState.IsDragging = true
                InputController.Signals.DragStart:Fire(inputState.TouchStartPosition)
            end
            
            InputController.Signals.DragUpdate:Fire(touch.Position, delta)
        end
    end
    
    -- Update touch position
    local touchId = tostring(touch.Position)
    if inputState.ActiveTouches[touchId] then
        inputState.ActiveTouches[touchId].Position = touch.Position
    end
end

-------------------------------------------------
-- ACTION HANDLER
-------------------------------------------------

--[[
    Verarbeitet getriggerte Actions
    @param action: Action-Name
    @param state: Began oder Ended
]]
function InputController._handleAction(action, state)
    if state ~= "Began" then return end
    
    debugPrint("Action: " .. action)
    
    -- UI Actions
    if action == "Cancel" then
        if UIController then
            UIController.ClosePopup()
        end
        
    elseif action == "ToggleMenu" then
        if UIController then
            UIController.Signals.ButtonClicked:Fire("ToggleMenu")
        end
        
    elseif action == "CollectIncome" then
        if UIController then
            UIController.CollectPassiveIncome()
        end
        
    -- Navigation Actions
    elseif action == "NavUp" or action == "NavDown" or action == "NavLeft" or action == "NavRight" then
        -- Gamepad Navigation
        if UIController then
            UIController.Signals.ButtonClicked:Fire("Navigate", action)
        end
        
    elseif action == "PrevTab" then
        if UIController then
            UIController.Signals.ButtonClicked:Fire("PrevTab")
        end
        
    elseif action == "NextTab" then
        if UIController then
            UIController.Signals.ButtonClicked:Fire("NextTab")
        end
        
    -- Build Actions
    elseif action == "Rotate" then
        InputController.Signals.ActionTriggered:Fire("Rotate", "Began")
        
    elseif action == "Delete" then
        InputController.Signals.ActionTriggered:Fire("Delete", "Began")
        
    elseif action == "Interact" then
        InputController.Signals.ActionTriggered:Fire("Interact", "Began")
        
    -- Quick Slots
    elseif action:match("^QuickSlot%d$") then
        local slot = tonumber(action:match("%d"))
        InputController.Signals.ActionTriggered:Fire("QuickSlot", slot)
    end
end

-------------------------------------------------
-- PUBLIC API - INITIALISIERUNG
-------------------------------------------------

--[[
    Initialisiert den InputController
    @param uiControllerRef: Referenz zum UIController
    @param cameraControllerRef: Referenz zum CameraController
    @param clientStateRef: Referenz zum ClientState
]]
function InputController.Initialize(uiControllerRef, cameraControllerRef, clientStateRef)
    debugPrint("Initialisiere InputController...")
    
    UIController = uiControllerRef
    CameraController = cameraControllerRef
    ClientState = clientStateRef
    
    -- Plattform erkennen
    inputState.Platform = detectPlatform()
    debugPrint("Plattform: " .. inputState.Platform)
    
    -- Input Events verbinden
    UserInputService.InputBegan:Connect(onInputBegan)
    UserInputService.InputEnded:Connect(onInputEnded)
    UserInputService.InputChanged:Connect(onInputChanged)
    
    -- Touch Events (Mobile)
    if UserInputService.TouchEnabled then
        UserInputService.TouchStarted:Connect(onTouchStarted)
        UserInputService.TouchEnded:Connect(onTouchEnded)
        UserInputService.TouchMoved:Connect(onTouchMoved)
    end
    
    -- Gamepad Connection
    UserInputService.GamepadConnected:Connect(function(gamepad)
        if gamepad == Enum.UserInputType.Gamepad1 then
            inputState.GamepadConnected = true
            debugPrint("Gamepad verbunden")
        end
    end)
    
    UserInputService.GamepadDisconnected:Connect(function(gamepad)
        if gamepad == Enum.UserInputType.Gamepad1 then
            inputState.GamepadConnected = false
            debugPrint("Gamepad getrennt")
        end
    end)
    
    -- Initial Gamepad Check
    inputState.GamepadConnected = UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
    
    debugPrint("InputController initialisiert!")
end

-------------------------------------------------
-- PUBLIC API - INPUT STATE
-------------------------------------------------

--[[
    Gibt aktuelle Plattform zurück
    @return: Platform-String
]]
function InputController.GetPlatform()
    return inputState.Platform
end

--[[
    Prüft ob Mobile-Plattform
    @return: boolean
]]
function InputController.IsMobile()
    return inputState.Platform == "Mobile"
end

--[[
    Prüft ob Gamepad verbunden
    @return: boolean
]]
function InputController.IsGamepadConnected()
    return inputState.GamepadConnected
end

--[[
    Prüft ob Key gedrückt ist
    @param keyCode: KeyCode
    @return: boolean
]]
function InputController.IsKeyDown(keyCode)
    return inputState.HeldKeys[keyCode] == true
end

--[[
    Gibt Mouse-Position zurück
    @return: Vector2
]]
function InputController.GetMousePosition()
    return UserInputService:GetMouseLocation()
end

--[[
    Gibt Left Stick Wert zurück
    @return: Vector2
]]
function InputController.GetLeftStick()
    return inputState.LeftStick
end

--[[
    Gibt Right Stick Wert zurück
    @return: Vector2
]]
function InputController.GetRightStick()
    return inputState.RightStick
end

-------------------------------------------------
-- PUBLIC API - INPUT MODE
-------------------------------------------------

--[[
    Setzt Input-Modus
    @param mode: Normal, Build, Raid, Menu
]]
function InputController.SetMode(mode)
    local oldMode = inputState.Mode
    inputState.Mode = mode
    
    if oldMode ~= mode then
        InputController.Signals.ModeChanged:Fire(mode, oldMode)
        debugPrint("Mode gewechselt: " .. oldMode .. " -> " .. mode)
    end
end

--[[
    Gibt aktuellen Input-Modus zurück
    @return: Mode-String
]]
function InputController.GetMode()
    return inputState.Mode
end

-------------------------------------------------
-- PUBLIC API - ACTION BINDING
-------------------------------------------------

--[[
    Bindet eine Action an einen Key
    @param keyCode: KeyCode
    @param action: Action-Name
    @param inputType: "Keyboard" oder "Gamepad"
]]
function InputController.BindAction(keyCode, action, inputType)
    inputType = inputType or "Keyboard"
    
    if not actionBindings[inputType] then
        actionBindings[inputType] = {}
    end
    
    actionBindings[inputType][keyCode] = action
    debugPrint("Action gebunden: " .. action .. " -> " .. tostring(keyCode))
end

--[[
    Entfernt Action-Binding
    @param keyCode: KeyCode
    @param inputType: "Keyboard" oder "Gamepad"
]]
function InputController.UnbindAction(keyCode, inputType)
    inputType = inputType or "Keyboard"
    
    if actionBindings[inputType] then
        actionBindings[inputType][keyCode] = nil
    end
end

--[[
    Gibt alle Bindings für eine Action zurück
    @param action: Action-Name
    @return: Array von { KeyCode, InputType }
]]
function InputController.GetBindingsForAction(action)
    local bindings = {}
    
    for inputType, keys in pairs(actionBindings) do
        for keyCode, boundAction in pairs(keys) do
            if boundAction == action then
                table.insert(bindings, {
                    KeyCode = keyCode,
                    InputType = inputType,
                })
            end
        end
    end
    
    return bindings
end

-------------------------------------------------
-- PUBLIC API - CURSOR
-------------------------------------------------

--[[
    Setzt Cursor-Icon
    @param icon: Asset-ID oder Standard
]]
function InputController.SetCursor(icon)
    if icon == "Default" then
        UserInputService.MouseIcon = ""
    else
        UserInputService.MouseIcon = icon
    end
end

--[[
    Sperrt/Entsperrt Mouse
    @param locked: boolean
]]
function InputController.SetMouseLocked(locked)
    UserInputService.MouseBehavior = locked 
        and Enum.MouseBehavior.LockCurrentPosition 
        or Enum.MouseBehavior.Default
end

--[[
    Zeigt/Versteckt Cursor
    @param visible: boolean
]]
function InputController.SetCursorVisible(visible)
    UserInputService.MouseIconEnabled = visible
end

-------------------------------------------------
-- PUBLIC API - VIBRATION (Gamepad)
-------------------------------------------------

--[[
    Vibriert Gamepad
    @param motor: Small oder Large
    @param intensity: 0-1
    @param duration: Sekunden
]]
function InputController.Vibrate(motor, intensity, duration)
    if not inputState.GamepadConnected then return end
    
    local motorType = motor == "Small" 
        and Enum.VibrationMotor.Small 
        or Enum.VibrationMotor.Large
    
    pcall(function()
        UserInputService:SetMotor(Enum.UserInputType.Gamepad1, motorType, intensity)
        
        task.delay(duration or 0.2, function()
            pcall(function()
                UserInputService:SetMotor(Enum.UserInputType.Gamepad1, motorType, 0)
            end)
        end)
    end)
end

return InputController
