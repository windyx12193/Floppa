-- Zamorozka Auto Joiner
-- Roblox Lua script implementing winter UI auto joiner with filtering, retry, and auto inject

--//== Services ==//--
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LogService = game:GetService("LogService")

local LOCAL_PLAYER = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()

--//== Configuration ==//--
local SCRIPT_NAME = "Zamorozka Auto Joiner"
local SCRIPT_VERSION = "1.0.0"
local SETTINGS_FILE = "zamorozka_config.json"
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"
local DATA_ENDPOINT = "https://server-eta-two-29.vercel.app"
local DATA_API_KEY = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"
local PLACE_ID = 109983668079237
local POLL_MIN_INTERVAL = 0.1
local POLL_MAX_INTERVAL = 0.5
local TARGET_FPS_MIN = 40
local TARGET_FPS_MAX = 55
local ENTRY_TTL_SECONDS = 180
local NEW_BADGE_SECONDS = 5
local RETRY_DELAY = 0.1
local KEYBIND = Enum.KeyCode.K

--//== Utility: File IO ==//--
local function hasFileSystem()
    return typeof(isfile) == "function" and typeof(writefile) == "function" and typeof(readfile) == "function"
end

local function loadConfig()
    if not hasFileSystem() or not isfile(SETTINGS_FILE) then
        return {
            autoJoin = false,
            autoInject = false,
            moneyFilter = "0",
            retryAmount = 0,
            whitelist = {},
            blacklist = {}
        }
    end

    local ok, content = pcall(readfile, SETTINGS_FILE)
    if not ok or type(content) ~= "string" then
        return {
            autoJoin = false,
            autoInject = false,
            moneyFilter = "0",
            retryAmount = 0,
            whitelist = {},
            blacklist = {}
        }
    end

    local okJson, decoded = pcall(HttpService.JSONDecode, HttpService, content)
    if okJson and type(decoded) == "table" then
        decoded.autoJoin = decoded.autoJoin == true
        decoded.autoInject = decoded.autoInject == true
        decoded.moneyFilter = decoded.moneyFilter ~= nil and tostring(decoded.moneyFilter) or "0"
        decoded.retryAmount = tonumber(decoded.retryAmount) or 0
        decoded.whitelist = type(decoded.whitelist) == "table" and decoded.whitelist or {}
        decoded.blacklist = type(decoded.blacklist) == "table" and decoded.blacklist or {}
        return decoded
    end

    return {
        autoJoin = false,
        autoInject = false,
        moneyFilter = "0",
        retryAmount = 0,
        whitelist = {},
        blacklist = {}
    }
end

local function saveConfig(cfg)
    if not hasFileSystem() then
        return
    end
    local okEncode, json = pcall(HttpService.JSONEncode, HttpService, cfg)
    if okEncode then
        pcall(writefile, SETTINGS_FILE, json)
    end
end

local Config = loadConfig()

--//== Utility Helpers ==//--
local function splitCSV(str)
    local list = {}
    if type(str) ~= "string" then
        return list
    end
    for token in string.gmatch(str, "[^,]+") do
        local cleaned = token:gsub("^%s+", ""):gsub("%s+$", "")
        if #cleaned > 0 then
            list[#list + 1] = cleaned
        end
    end
    return list
end

local magnitudeMap = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
    t = 1e12
}

local function parseMoney(text)
    if type(text) ~= "string" then
        return 0
    end
    local cleaned = text:lower():gsub(",", "")
    local numberPart, suffix = cleaned:match("%$%s*([%d%.]+)%s*([kmbt]?)%s*/?s")
    if not numberPart then
        numberPart, suffix = cleaned:match("([%d%.]+)%s*([kmbt]?)")
    end
    local value = tonumber(numberPart or "0") or 0
    local multiplier = magnitudeMap[suffix or ""] or 1
    local normalized = math.floor(value * multiplier + 0.5)
    return normalized
end

local function formatMoneyShort(value)
    if value >= 1e9 then
        return string.format("$%.1fb/s", value / 1e9)
    elseif value >= 1e6 then
        return string.format("$%.1fm/s", value / 1e6)
    elseif value >= 1e3 then
        return string.format("$%.1fk/s", value / 1e3)
    else
        return string.format("$%d/s", value)
    end
end

local function parseTimestamp(text)
    if type(text) ~= "string" or #text == 0 then
        return os.time()
    end
    local day, month, year, hour, min, sec = text:match("(%d%d?)%.(%d%d?)%.(%d%d%d%d)[,%s]+(%d%d?):(%d%d):(%d%d)")
    if day and month and year and hour and min and sec then
        local success, value = pcall(os.time, {
            day = tonumber(day),
            month = tonumber(month),
            year = tonumber(year),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
        })
        if success and value then
            return value
        end
    end
    return os.time()
end

local function safeRequest(options)
    local req = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
    if req then
        local ok, result = pcall(req, options)
        if ok and result and result.StatusCode == 200 and type(result.Body) == "string" then
            return true, result.Body
        end
    end
    local fallbackUrl = options.Url
    if DATA_API_KEY and not fallbackUrl:lower():find("key=") then
        local joiner = fallbackUrl:find("?", 1, true) and "&" or "?"
        fallbackUrl = string.format("%s%ckey=%s", fallbackUrl, joiner, DATA_API_KEY)
    end
    local ok, body = pcall(function()
        return game:HttpGet(fallbackUrl, true)
    end)
    if ok and type(body) == "string" then
        return true, body
    end
    return false, nil
end

local function showConsole(msg)
    print(string.format("[%s] %s", SCRIPT_NAME, msg))
end

--//== Network Error Banner ==//--
local errorBanner
local function displayBanner(text, duration)
    if not errorBanner then
        local parent
        local ok, hui = pcall(function()
            return gethui and gethui()
        end)
        if ok and hui then
            parent = hui
        else
            parent = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui") or LOCAL_PLAYER:WaitForChild("PlayerGui")
        end

        errorBanner = Instance.new("ScreenGui")
        errorBanner.IgnoreGuiInset = true
        errorBanner.ResetOnSpawn = false
        errorBanner.DisplayOrder = 1_000_000
        errorBanner.Name = "ZamorozkaBanner"
        errorBanner.Parent = parent

        local frame = Instance.new("Frame")
        frame.Name = "BannerFrame"
        frame.AnchorPoint = Vector2.new(0.5, 0)
        frame.Position = UDim2.new(0.5, 0, 0, -60)
        frame.Size = UDim2.new(0.4, 0, 0, 40)
        frame.BackgroundColor3 = Color3.fromRGB(255, 110, 110)
        frame.BackgroundTransparency = 0.2
        frame.Parent = errorBanner

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = frame

        local label = Instance.new("TextLabel")
        label.Name = "Message"
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.TextWrapped = true
        label.Size = UDim2.new(1, -20, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.Parent = frame
    end

    local frame = errorBanner:FindFirstChild("BannerFrame")
    local label = frame and frame:FindFirstChild("Message")
    if frame and label then
        label.Text = text
        frame.Position = UDim2.new(0.5, 0, 0, -60)
        frame.Visible = true
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0, 10)
        }):Play()

        task.delay(duration or 2.5, function()
            if frame then
                TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Position = UDim2.new(0.5, 0, 0, -60)
                }):Play()
            end
        end)
    end
end

--//== Cleanup previous UI ==//--
local function getGuiParent()
    local ok, ui = pcall(function()
        return gethui and gethui()
    end)
    if ok and ui then
        return ui
    end
    local ok2, core = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok2 and core then
        return core
    end
    return LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui") or LOCAL_PLAYER:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
local existing = guiParent:FindFirstChild("ZamorozkaAutoJoiner")
if existing then
    existing:Destroy()
end

--//== UI Colors & Theme ==//--
local COLORS = {
    background = Color3.fromRGB(240, 245, 250),
    panel = Color3.fromRGB(225, 235, 245),
    accent = Color3.fromRGB(150, 180, 210),
    accentBright = Color3.fromRGB(110, 160, 210),
    accentDark = Color3.fromRGB(70, 110, 150),
    text = Color3.fromRGB(30, 40, 50),
    textMuted = Color3.fromRGB(90, 110, 130),
    green = Color3.fromRGB(70, 200, 140),
    blue = Color3.fromRGB(90, 140, 210),
    joinButton = Color3.fromRGB(170, 230, 200)
}

local function applyCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = instance
    return corner
end

local function applyStroke(instance, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = thickness or 1
    stroke.Color = color or COLORS.accent
    stroke.Transparency = 0.3
    stroke.Parent = instance
    return stroke
end

local function createLabel(parent, text, size, weight, color)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Text = text
    label.Font = weight == "bold" and Enum.Font.GothamBold or weight == "medium" and Enum.Font.GothamMedium or Enum.Font.Gotham
    label.TextSize = size or 18
    label.TextColor3 = color or COLORS.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

--//== Blur ==//--
local blur = Lighting:FindFirstChild("ZamorozkaBlur") or Instance.new("BlurEffect")
blur.Name = "ZamorozkaBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local function setBlur(enabled)
    if enabled then
        blur.Enabled = true
        TweenService:Create(blur, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = 6 }):Play()
    else
        TweenService:Create(blur, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = 0 }):Play()
        task.delay(0.22, function()
            if blur then
                blur.Enabled = false
            end
        end)
    end
end

--//== Root GUI ==//--
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZamorozkaAutoJoiner"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 900000
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 960, 0, 560)
mainFrame.Position = UDim2.new(0.5, -480, 0.5, -280)
mainFrame.BackgroundColor3 = COLORS.background
mainFrame.BackgroundTransparency = 0.15
mainFrame.Parent = screenGui
applyCorner(mainFrame, 18)
applyStroke(mainFrame, COLORS.accentDark, 1.5)

local mainPadding = Instance.new("UIPadding")
mainPadding.PaddingTop = UDim.new(0, 10)
mainPadding.PaddingBottom = UDim.new(0, 10)
mainPadding.PaddingLeft = UDim.new(0, 10)
mainPadding.PaddingRight = UDim.new(0, 10)
mainPadding.Parent = mainFrame

-- Header (10-15% height)
local headerHeight = 0.12
local headerFrame = Instance.new("Frame")
headerFrame.Name = "Header"
headerFrame.Size = UDim2.new(1, 0, headerHeight, -10)
headerFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
headerFrame.BackgroundTransparency = 0.1
headerFrame.Parent = mainFrame
applyCorner(headerFrame, 14)
applyStroke(headerFrame, COLORS.accent, 1)

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 240, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 225, 245))
})
headerGradient.Parent = headerFrame

local headerPadding = Instance.new("UIPadding")
headerPadding.PaddingLeft = UDim.new(0, 24)
headerPadding.PaddingRight = UDim.new(0, 24)
headerPadding.PaddingTop = UDim.new(0, 10)
headerPadding.Parent = headerFrame

local headerLabel = createLabel(headerFrame, SCRIPT_NAME, 28, "bold", COLORS.text)
headerLabel.Size = UDim2.new(0.7, 0, 1, -10)
headerLabel.Position = UDim2.new(0, 0, 0, 0)

local versionLabel = createLabel(headerFrame, "v" .. SCRIPT_VERSION, 16, "medium", COLORS.textMuted)
versionLabel.AnchorPoint = Vector2.new(1, 0)
versionLabel.Position = UDim2.new(1, 0, 0, 4)
versionLabel.Size = UDim2.new(0, 120, 0, 20)
versionLabel.TextXAlignment = Enum.TextXAlignment.Right

local keybindLabel = createLabel(headerFrame, "Press 'K' to toggle", 16, "medium", COLORS.textMuted)
keybindLabel.AnchorPoint = Vector2.new(1, 1)
keybindLabel.Position = UDim2.new(1, 0, 1, -8)
keybindLabel.Size = UDim2.new(0, 180, 0, 20)
keybindLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Content Frame
local contentFrame = Instance.new("Frame")
contentFrame.Name = "Content"
contentFrame.Size = UDim2.new(1, 0, 1 - headerHeight, -20)
contentFrame.Position = UDim2.new(0, 0, headerHeight, 10)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

-- Left Settings Panel
local leftPanel = Instance.new("Frame")
leftPanel.Name = "SettingsPanel"
leftPanel.AnchorPoint = Vector2.new(0, 0)
leftPanel.Position = UDim2.new(0, 0, 0, 0)
leftPanel.Size = UDim2.new(0.25, -10, 1, -10)
leftPanel.BackgroundColor3 = COLORS.panel
leftPanel.BackgroundTransparency = 0.1
leftPanel.Parent = contentFrame
applyCorner(leftPanel, 14)
applyStroke(leftPanel, COLORS.accent, 1)

local leftPadding = Instance.new("UIPadding")
leftPadding.PaddingLeft = UDim.new(0, 16)
leftPadding.PaddingRight = UDim.new(0, 12)
leftPadding.PaddingTop = UDim.new(0, 16)
leftPadding.PaddingBottom = UDim.new(0, 16)
leftPadding.Parent = leftPanel

local leftListLayout = Instance.new("UIListLayout")
leftListLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftListLayout.Padding = UDim.new(0, 12)
leftListLayout.Parent = leftPanel

local function createSectionTitle(parent, text)
    local label = createLabel(parent, text, 20, "bold", COLORS.text)
    label.Size = UDim2.new(1, 0, 0, 24)
    return label
end

local function createToggle(parent, text, initial)
    local container = Instance.new("Frame")
    container.Name = text .. "Toggle"
    container.Size = UDim2.new(1, 0, 0, 48)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = createLabel(container, text, 18, "medium", COLORS.text)
    label.Size = UDim2.new(0.6, 0, 1, 0)

    local button = Instance.new("TextButton")
    button.Name = "ToggleButton"
    button.AnchorPoint = Vector2.new(1, 0.5)
    button.Position = UDim2.new(1, 0, 0.5, 0)
    button.Size = UDim2.new(0, 68, 0, 28)
    button.Text = ""
    button.AutoButtonColor = false
    button.BackgroundColor3 = Color3.fromRGB(210, 220, 235)
    button.Parent = container
    applyCorner(button, 14)

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 24, 0, 24)
    knob.Position = UDim2.new(0, 2, 0.5, -12)
    knob.BackgroundColor3 = Color3.fromRGB(180, 190, 205)
    knob.Parent = button
    applyCorner(knob, 12)

    local state = { value = initial == true }

    local function applyVisual(animated)
        local goalPosition = state.value and UDim2.new(1, -26, 0.5, -12) or UDim2.new(0, 2, 0.5, -12)
        local knobColor = state.value and COLORS.green or Color3.fromRGB(180, 190, 205)
        local buttonColor = state.value and Color3.fromRGB(200, 230, 220) or Color3.fromRGB(210, 220, 235)
        if animated then
            TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                Position = goalPosition,
                BackgroundColor3 = knobColor
            }):Play()
            TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                BackgroundColor3 = buttonColor
            }):Play()
        else
            knob.Position = goalPosition
            knob.BackgroundColor3 = knobColor
            button.BackgroundColor3 = buttonColor
        end
    end

    local function setValue(newValue, silent, animated)
        local boolValue = newValue and true or false
        if state.value ~= boolValue then
            state.value = boolValue
            applyVisual(animated ~= false)
            if not silent and state.changed then
                task.defer(state.changed, state.value)
            end
        else
            applyVisual(animated ~= false)
        end
    end

    state.set = function(_, newValue, silent)
        setValue(newValue, silent, true)
    end

    state.get = function()
        return state.value
    end

    applyVisual(false)

    button.MouseButton1Click:Connect(function()
        setValue(not state.value, false, true)
    end)

    return state
end

local function createTextBox(parent, labelText, placeholder, defaultText)
    local container = Instance.new("Frame")
    container.Name = labelText .. "Input"
    container.Size = UDim2.new(1, 0, 0, 70)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = createLabel(container, labelText, 18, "medium", COLORS.text)
    label.Size = UDim2.new(1, 0, 0, 24)

    local box = Instance.new("TextBox")
    box.Name = "InputBox"
    box.Size = UDim2.new(1, 0, 0, 36)
    box.Position = UDim2.new(0, 0, 0, 30)
    box.Text = defaultText or ""
    box.PlaceholderText = placeholder or ""
    box.Font = Enum.Font.Gotham
    box.TextColor3 = COLORS.text
    box.TextSize = 16
    box.BackgroundColor3 = Color3.fromRGB(240, 245, 250)
    box.BackgroundTransparency = 0.15
    box.ClearTextOnFocus = false
    box.Parent = container
    applyCorner(box, 10)
    applyStroke(box, COLORS.accent, 1)

    return box
end

local function createInfoLabel(parent, text)
    local label = createLabel(parent, text, 16, "medium", COLORS.textMuted)
    label.Size = UDim2.new(1, 0, 0, 20)
    return label
end

-- Settings UI
createSectionTitle(leftPanel, "Automation")
local autoJoinToggle = createToggle(leftPanel, "Auto Join", Config.autoJoin)
local autoInjectToggle = createToggle(leftPanel, "Auto Inject", Config.autoInject)

createSectionTitle(leftPanel, "Filters")
local moneyFilterBox = createTextBox(leftPanel, "Minimum $/s", "e.g. 5m", tostring(Config.moneyFilter or "0"))
local retryAmountBox = createTextBox(leftPanel, "Join Retry Amount", "0 = off", tostring(Config.retryAmount or 0))
local whitelistBox = createTextBox(leftPanel, "Whitelist (CSV)", "name1,name2", table.concat(Config.whitelist or {}, ","))
local blacklistBox = createTextBox(leftPanel, "Blacklist (CSV)", "name1,name2", table.concat(Config.blacklist or {}, ","))
createInfoLabel(leftPanel, "Whitelist overrides blacklist when not empty.")

local statusLabel = createLabel(leftPanel, "Status: Idle", 16, "medium", COLORS.textMuted)
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel:SetAttribute("RetryCount", 0)

-- Right Panel (Server List)
local rightPanel = Instance.new("Frame")
rightPanel.Name = "ServerPanel"
rightPanel.AnchorPoint = Vector2.new(1, 0)
rightPanel.Position = UDim2.new(1, 0, 0, 0)
rightPanel.Size = UDim2.new(0.73, 0, 1, -10)
rightPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
rightPanel.BackgroundTransparency = 0.08
rightPanel.Parent = contentFrame
applyCorner(rightPanel, 14)
applyStroke(rightPanel, COLORS.accent, 1)

local rightPadding = Instance.new("UIPadding")
rightPadding.PaddingTop = UDim.new(0, 16)
rightPadding.PaddingBottom = UDim.new(0, 16)
rightPadding.PaddingLeft = UDim.new(0, 16)
rightPadding.PaddingRight = UDim.new(0, 16)
rightPadding.Parent = rightPanel

local listTitle = createLabel(rightPanel, "Server Lobbies", 22, "bold", COLORS.text)
listTitle.Size = UDim2.new(1, -120, 0, 28)

local refreshInfo = createLabel(rightPanel, "Fetching...", 16, "medium", COLORS.textMuted)
refreshInfo.AnchorPoint = Vector2.new(1, 0)
refreshInfo.Position = UDim2.new(1, 0, 0, 4)
refreshInfo.Size = UDim2.new(0, 140, 0, 20)
refreshInfo.TextXAlignment = Enum.TextXAlignment.Right

local serverList = Instance.new("ScrollingFrame")
serverList.Name = "ServerList"
serverList.Size = UDim2.new(1, 0, 1, -40)
serverList.Position = UDim2.new(0, 0, 0, 34)
serverList.BackgroundTransparency = 1
serverList.BorderSizePixel = 0
serverList.ScrollBarThickness = 8
serverList.CanvasSize = UDim2.new()
serverList.Parent = rightPanel

local serverLayout = Instance.new("UIListLayout")
serverLayout.SortOrder = Enum.SortOrder.LayoutOrder
serverLayout.Padding = UDim.new(0, 10)
serverLayout.Parent = serverList

local function updateServerCanvas()
    serverList.CanvasSize = UDim2.new(0, 0, 0, serverLayout.AbsoluteContentSize.Y + 8)
end
serverLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateServerCanvas)

-- NEW badge template
local function createNewBadge(parent)
    local badge = Instance.new("TextLabel")
    badge.Name = "NewBadge"
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -90, 0, 6)
    badge.Size = UDim2.new(0, 52, 0, 22)
    badge.BackgroundColor3 = Color3.fromRGB(190, 230, 255)
    badge.Text = "NEW"
    badge.Font = Enum.Font.GothamBold
    badge.TextColor3 = COLORS.blue
    badge.TextSize = 14
    badge.BackgroundTransparency = 0.1
    badge.Parent = parent
    applyCorner(badge, 10)
    applyStroke(badge, COLORS.accent, 1)
    return badge
end

--//== Dragging ==//--
local dragging = false
local dragStart
local startPos

local function startDrag(input)
    dragging = true
    dragStart = input.Position
    startPos = mainFrame.Position
    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            dragging = false
        end
    end)
end

local function updateDrag(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end

headerFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        startDrag(input)
    end
end)
UIS.InputChanged:Connect(updateDrag)

--//== Visibility Toggle ==//--
local uiVisible = true
local function setUIVisible(visible, instant)
    uiVisible = visible
    if visible then
        setBlur(true)
        mainFrame.Visible = true
        local goal = UDim2.new(0.5, -480, 0.5, -280)
        if instant then
            mainFrame.Position = goal
            mainFrame.BackgroundTransparency = 0.15
        else
            mainFrame.Position = UDim2.new(0.5, -480, 0.5, -240)
            mainFrame.BackgroundTransparency = 1
            TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = goal,
                BackgroundTransparency = 0.15
            }):Play()
        end
    else
        setBlur(false)
        if instant then
            mainFrame.Visible = false
        else
            local tween = TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, -480, 0.5, -220),
                BackgroundTransparency = 1
            })
            tween.Completed:Connect(function()
                mainFrame.Visible = false
            end)
            tween:Play()
        end
    end
end

UIS.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == KEYBIND then
        setUIVisible(not uiVisible, false)
    end
end)

setUIVisible(true, true)

--//== Server Data Structures ==//--
local servers = {}
local cards = {}
local pollingInterval = 0.2
local lastPoll = 0
local joinInProgress = false
local retryTask
local joinTargetJobId = nil
local averageFrameDt = 0

local function resetRetryState()
    if retryTask then
        retryTask:Disconnect()
        retryTask = nil
    end
    joinInProgress = false
    if statusLabel then
        statusLabel:SetAttribute("RetryCount", 0)
    end
end

local function parseLine(line)
    local parts = {}
    for segment in line:gmatch("([^|]+)") do
        parts[#parts + 1] = segment:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%*", "")
    end
    if #parts < 5 then
        return {}
    end
    local results = {}
    local index = 1
    while index + 4 <= #parts do
        local name = parts[index]
        local moneyText = parts[index + 1]
        local playersText = parts[index + 2]
        local jobId = parts[index + 3]
        local timestamp = parts[index + 4]
        if name and jobId and #name > 0 and #jobId > 0 then
            local current, maximum = playersText:match("(%d+)%s*/%s*(%d+)")
            results[#results + 1] = {
                name = name,
                moneyPerSec = parseMoney(moneyText),
                players = tonumber(current) or 0,
                maxPlayers = tonumber(maximum) or 0,
                jobId = jobId,
                timestamp = parseTimestamp(timestamp),
                rawMoney = moneyText,
                rawPlayers = playersText
            }
        end
        index = index + 5
    end
    return results
end

local function normalizeApiItem(item)
    local jobId = tostring(item.jobId or item.id or "")
    if jobId == "" then
        return nil
    end
    local name = tostring(item.name or item.serverName or "")
    local moneyField = tostring(item.moneyPerSec or item.money or item.money_per_second or item.moneyRate or item.moneyRatePerSec or item["money/s"] or "")
    local playersField = tostring(item.players or item.playerCount or item.online or "")
    local maxPlayersField = tonumber(item.maxPlayers or item.max or item.playerCap or 0) or 0
    local timestampField = tostring(item.timestamp or item.time or "")

    local players, maxPlayers = playersField:match("(%d+)%s*/%s*(%d+)")
    local data = {
        name = name,
        moneyPerSec = parseMoney(moneyField),
        players = tonumber(players) or tonumber(playersField) or 0,
        maxPlayers = tonumber(maxPlayers) or tonumber(maxPlayersField) or 0,
        jobId = jobId,
        rawMoney = moneyField ~= "" and moneyField or formatMoneyShort(parseMoney(moneyField)),
        rawPlayers = playersField ~= "" and playersField or string.format("%d/%d", tonumber(players) or tonumber(playersField) or 0, tonumber(maxPlayers) or tonumber(maxPlayersField) or 0),
        timestamp = #timestampField > 0 and parseTimestamp(timestampField) or os.time()
    }
    return data
end

local function decodeResponse(body)
    local list = {}
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if ok and decoded then
        if decoded.items and type(decoded.items) == "table" then
            for _, item in ipairs(decoded.items) do
                local data = normalizeApiItem(item)
                if data then
                    list[#list + 1] = data
                end
            end
        elseif decoded.data and type(decoded.data) == "table" then
            for _, item in ipairs(decoded.data) do
                local data = normalizeApiItem(item)
                if data then
                    list[#list + 1] = data
                end
            end
        elseif typeof(decoded) == "table" and #decoded > 0 then
            for _, item in ipairs(decoded) do
                local data = normalizeApiItem(item)
                if data then
                    list[#list + 1] = data
                end
            end
        end
    end

    if #list > 0 then
        return list
    end

    for line in body:gmatch("[^\r\n]+") do
        local parsedEntries = parseLine(line)
        for _, parsed in ipairs(parsedEntries) do
            list[#list + 1] = parsed
        end
    end

    return list
end

local function getRequestUrl()
    local nonce = math.random(1, 10_000_000)
    return string.format("%s/api/jobs?_cb=%d", DATA_ENDPOINT, nonce)
end

local function fetchServerData()
    local success, body = safeRequest({
        Url = getRequestUrl(),
        Method = "GET",
        Headers = {
            ["x-api-key"] = DATA_API_KEY,
            ["Accept"] = "application/json"
        }
    })
    if not success or type(body) ~= "string" then
        return false, {}
    end
    local entries = decodeResponse(body)
    return true, entries
end

--//== Filtering ==//--
local function parseMoneyFilter()
    local text = moneyFilterBox.Text
    if text == nil or text == "" then
        return 0
    end
    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return 0
    end
    local value = parseMoney("$" .. cleaned .. "/s")
    return value
end

local function isWhitelisted(name)
    if not name or name == "" then
        return false
    end
    if Config.whitelist and #Config.whitelist > 0 then
        for _, entry in ipairs(Config.whitelist) do
            if name:lower() == entry:lower() then
                return true
            end
        end
        return false
    end
    return true
end

local function isBlacklisted(name)
    if not name or name == "" then
        return false
    end
    if Config.whitelist and #Config.whitelist > 0 then
        return false
    end
    if Config.blacklist then
        for _, entry in ipairs(Config.blacklist) do
            if name:lower() == entry:lower() then
                return true
            end
        end
    end
    return false
end

local function applyFilters(entry)
    if entry.moneyPerSec < parseMoneyFilter() then
        return false
    end
    if not isWhitelisted(entry.name) then
        return false
    end
    if isBlacklisted(entry.name) then
        return false
    end
    return true
end

--//== Card Management ==//--
local function createServerCard(entry)
    local card = Instance.new("Frame")
    card.Name = entry.jobId
    card.Size = UDim2.new(1, -6, 0, 78)
    card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    card.BackgroundTransparency = 0.1
    card.Parent = serverList
    card.LayoutOrder = -entry.moneyPerSec
    applyCorner(card, 12)
    applyStroke(card, COLORS.accent, 1)

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 14)
    padding.PaddingRight = UDim.new(0, 14)
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.Parent = card

    local nameLabel = createLabel(card, entry.name, 20, "bold", COLORS.text)
    nameLabel.Size = UDim2.new(0.45, 0, 0, 24)

    local moneyLabel = createLabel(card, entry.rawMoney or formatMoneyShort(entry.moneyPerSec), 18, "bold", Color3.fromRGB(60, 170, 90))
    moneyLabel.AnchorPoint = Vector2.new(0, 0)
    moneyLabel.Position = UDim2.new(0.46, 0, 0, 0)
    moneyLabel.Size = UDim2.new(0.22, 0, 0, 24)

    local playersLabel = createLabel(card, entry.rawPlayers or string.format("%d/%d", entry.players, entry.maxPlayers), 18, "medium", COLORS.blue)
    playersLabel.AnchorPoint = Vector2.new(0, 0)
    playersLabel.Position = UDim2.new(0.69, 0, 0, 0)
    playersLabel.Size = UDim2.new(0.16, 0, 0, 24)

    local joinButton = Instance.new("TextButton")
    joinButton.Name = "JoinButton"
    joinButton.AnchorPoint = Vector2.new(1, 0.5)
    joinButton.Position = UDim2.new(1, -8, 0.5, 0)
    joinButton.Size = UDim2.new(0, 92, 0, 36)
    joinButton.Text = "JOIN"
    joinButton.Font = Enum.Font.GothamBold
    joinButton.TextColor3 = COLORS.text
    joinButton.TextSize = 18
    joinButton.AutoButtonColor = false
    joinButton.BackgroundColor3 = COLORS.joinButton
    joinButton.Parent = card
    applyCorner(joinButton, 10)
    applyStroke(joinButton, Color3.fromRGB(150, 210, 180), 1)

    local badge = createNewBadge(card)
    badge.Visible = true

    cards[entry.jobId] = {
        frame = card,
        nameLabel = nameLabel,
        moneyLabel = moneyLabel,
        playersLabel = playersLabel,
        button = joinButton,
        badge = badge
    }

    joinButton.MouseButton1Click:Connect(function()
        resetRetryState()
        statusLabel.Text = "Status: Joining " .. entry.name
        joinTargetJobId = entry.jobId
        statusLabel:SetAttribute("RetryCount", 0)
        local attempts = math.max(0, tonumber(retryAmountBox.Text) or Config.retryAmount or 0)
        joinInProgress = true
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, entry.jobId, LOCAL_PLAYER)
        end)
        if not ok then
            displayBanner("Teleport failed: " .. tostring(err), 3)
            if attempts == 0 then
                resetRetryState()
            end
        end
        if attempts > 0 then
            local accumulated = 0
            retryTask = RunService.Heartbeat:Connect(function(dt)
                if not joinInProgress then
                    resetRetryState()
                    return
                end
                accumulated = accumulated + dt
                while accumulated >= RETRY_DELAY do
                    accumulated = accumulated - RETRY_DELAY
                    local attemptNumber = (statusLabel:GetAttribute("RetryCount") or 0) + 1
                    statusLabel:SetAttribute("RetryCount", attemptNumber)
                    showConsole(string.format("join retry %d/%d", attemptNumber, attempts))
                    local ok2, err2 = pcall(function()
                        TeleportService:TeleportToPlaceInstance(PLACE_ID, entry.jobId, LOCAL_PLAYER)
                    end)
                    if ok2 then
                        resetRetryState()
                        return
                    elseif attemptNumber >= attempts then
                        displayBanner("Join retries exhausted", 2.5)
                        resetRetryState()
                        return
                    elseif err2 then
                        -- if server full keep trying until attempts reached
                        if tostring(err2):lower():find("full") then
                            -- continue loop
                        end
                    end
                end
            end)
        end
    end)

    return card
end

local function updateServerCard(entry)
    local card = cards[entry.jobId]
    if not card then
        return createServerCard(entry)
    end
    card.nameLabel.Text = entry.name
    card.moneyLabel.Text = entry.rawMoney or formatMoneyShort(entry.moneyPerSec)
    card.playersLabel.Text = entry.rawPlayers or string.format("%d/%d", entry.players, entry.maxPlayers)
    card.frame.LayoutOrder = -entry.moneyPerSec
    if card.badge then
        card.badge.Visible = os.clock() - entry.firstSeen < NEW_BADGE_SECONDS
    end
    return card.frame
end

local function removeServerCard(jobId)
    local card = cards[jobId]
    if card then
        if card.frame then
            TweenService:Create(card.frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundTransparency = 1,
                Size = UDim2.new(card.frame.Size.X.Scale, card.frame.Size.X.Offset, 0, 0)
            }):Play()
            task.delay(0.25, function()
                if card.frame then
                    card.frame:Destroy()
                end
            end)
        end
        cards[jobId] = nil
    end
end

--//== Auto Inject ==//--
local function getQueueFunction()
    if syn and syn.queue_on_teleport then
        return syn.queue_on_teleport
    end
    if queue_on_teleport then
        return queue_on_teleport
    end
    if fluxus and fluxus.queue_on_teleport then
        return fluxus.queue_on_teleport
    end
    if queueteleport then
        return queueteleport
    end
    return nil
end

local function queueAutoInject()
    local fn = getQueueFunction()
    if not fn then
        return
    end
    local scriptText = string.format([[task.defer(function()
        local function safeGet(url)
            for i = 1, 3 do
                local ok, result = pcall(function()
                    return game:HttpGet(url)
                end)
                if ok and type(result) == "string" and #result > 0 then
                    return result
                end
                task.wait(1)
            end
            return nil
        end
        local src = safeGet("%s")
        if src then
            local f = loadstring(src)
            if f then
                pcall(f)
            end
        end
    end)
    ]], AUTO_INJECT_URL)
    fn(scriptText)
end

if Config.autoInject then
    queueAutoInject()
end

LOCAL_PLAYER.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then
        if Config.autoInject then
            queueAutoInject()
        end
        if Config.autoJoin then
            Config.autoJoin = false
            resetAutoJoin()
            autoJoinToggle:set(false, true)
            saveConfig(Config)
        end
        resetRetryState()
    end
end)

--//== Auto Join Logic ==//--
local seenJobIds = {}
local function resetAutoJoin()
    seenJobIds = {}
    joinTargetJobId = nil
end

local function pickBestServer()
    local sorted = {}
    for _, entry in pairs(servers) do
        if applyFilters(entry) then
            sorted[#sorted + 1] = entry
        end
    end
    table.sort(sorted, function(a, b)
        if math.abs(a.firstSeen - b.firstSeen) < 0.001 then
            if a.moneyPerSec ~= b.moneyPerSec then
                return a.moneyPerSec > b.moneyPerSec
            end
            return a.name < b.name
        end
        return a.firstSeen > b.firstSeen
    end)
    if #sorted == 0 then
        return nil
    end
    for _, entry in ipairs(sorted) do
        if not seenJobIds[entry.jobId] then
            return entry
        end
    end
    return sorted[1]
end

local function attemptAutoJoin()
    if not Config.autoJoin or joinInProgress then
        return
    end
    local candidate = pickBestServer()
    if not candidate then
        return
    end

    resetRetryState()
    seenJobIds[candidate.jobId] = true
    joinTargetJobId = candidate.jobId
    statusLabel.Text = "Status: Auto joining " .. candidate.name
    statusLabel:SetAttribute("RetryCount", 0)
    joinInProgress = true
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, candidate.jobId, LOCAL_PLAYER)
    end)
    if not success then
        displayBanner("Auto join failed: " .. tostring(err), 3)
    end
    local attempts = math.max(0, Config.retryAmount or 0)
    if not success and attempts == 0 then
        resetRetryState()
    end
    if attempts > 0 then
        joinInProgress = true
        local accumulated = 0
        retryTask = RunService.Heartbeat:Connect(function(dt)
            if not joinInProgress then
                resetRetryState()
                return
            end
            accumulated = accumulated + dt
            while accumulated >= RETRY_DELAY do
                accumulated = accumulated - RETRY_DELAY
                local attemptIndex = (statusLabel:GetAttribute("RetryCount") or 0) + 1
                statusLabel:SetAttribute("RetryCount", attemptIndex)
                showConsole(string.format("join retry %d/%d", attemptIndex, attempts))
                local ok = pcall(function()
                    TeleportService:TeleportToPlaceInstance(PLACE_ID, candidate.jobId, LOCAL_PLAYER)
                end)
                if ok then
                    resetRetryState()
                    if Config.autoJoin then
                        Config.autoJoin = false
                        autoJoinToggle:set(false, true)
                        saveConfig(Config)
                    end
                    return
                elseif attemptIndex >= attempts then
                    displayBanner("Auto join retries exhausted", 2.5)
                    resetRetryState()
                    return
                end
            end
        end)
    end
end

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
    if player ~= LOCAL_PLAYER then
        return
    end
    resetRetryState()
    displayBanner("Teleport failed: " .. tostring(message), 2.5)
end)

LogService.MessageOut:Connect(function(text)
    if not joinInProgress then
        return
    end
    local lowered = string.lower(text)
    if lowered:find("teleport") and lowered:find("failed") then
        displayBanner(text, 2.5)
        if lowered:find("gameended") or lowered:find("could not find") or lowered:find("game instance") then
            resetRetryState()
        end
    end
end)

RunService.Heartbeat:Connect(function()
    statusLabel.Text = joinInProgress and "Status: Teleporting..." or (Config.autoJoin and "Status: Auto Join on" or "Status: Idle")
end)

RunService.Heartbeat:Connect(function(dt)
    if dt > 0 then
        if averageFrameDt == 0 then
            averageFrameDt = dt
        else
            averageFrameDt = averageFrameDt * 0.9 + dt * 0.1
        end
    end
end)

--//== Data Polling ==//--
local consecutiveErrors = 0

local function refreshServers()
    if os.clock() - lastPoll < pollingInterval then
        return
    end
    lastPoll = os.clock()
    refreshInfo.Text = "Refreshing..."
    local success, entries = fetchServerData()
    if not success then
        consecutiveErrors = consecutiveErrors + 1
        displayBanner("Network error, retrying...", 2)
        pollingInterval = math.min(POLL_MAX_INTERVAL, pollingInterval + 0.1 * consecutiveErrors)
        return
    end

    consecutiveErrors = 0
    refreshInfo.Text = string.format("Last update: %s", os.date("%H:%M:%S"))

    local currentTime = os.time()
    local seenThisCycle = {}

    for _, entry in ipairs(entries) do
        if entry.jobId and entry.jobId ~= "" then
            local key = entry.jobId
            local existing = servers[key]
            if existing then
                entry.firstSeen = existing.firstSeen
            else
                entry.firstSeen = os.clock()
            end
            entry.lastSeen = os.clock()
            servers[key] = entry
            seenThisCycle[key] = true
            if applyFilters(entry) then
                updateServerCard(entry)
            else
                removeServerCard(key)
            end
        end
    end

    for jobId, data in pairs(servers) do
        if not seenThisCycle[jobId] then
            local serverAge = math.max(0, currentTime - (data.timestamp or currentTime))
            local localAge = os.clock() - (data.lastSeen or os.clock())
            if serverAge > ENTRY_TTL_SECONDS or localAge > ENTRY_TTL_SECONDS then
                servers[jobId] = nil
                removeServerCard(jobId)
            end
        end
    end

    local sortedCards = {}
    for jobId, entry in pairs(servers) do
        if applyFilters(entry) then
            sortedCards[#sortedCards + 1] = entry
        else
            removeServerCard(jobId)
        end
    end
    table.sort(sortedCards, function(a, b)
        if a.moneyPerSec ~= b.moneyPerSec then
            return a.moneyPerSec > b.moneyPerSec
        end
        return a.firstSeen > b.firstSeen
    end)

    for index, entry in ipairs(sortedCards) do
        local card = cards[entry.jobId]
        if card and card.frame then
            card.frame.LayoutOrder = index
            if card.badge then
                card.badge.Visible = os.clock() - entry.firstSeen < NEW_BADGE_SECONDS
            end
        end
    end

    if Config.autoJoin then
        attemptAutoJoin()
    end
end

-- Poll loop
task.spawn(function()
    while screenGui.Parent do
        if averageFrameDt > 0 then
            local currentFps = 1 / averageFrameDt
            if currentFps < TARGET_FPS_MIN then
                pollingInterval = math.min(POLL_MAX_INTERVAL, pollingInterval + 0.02)
            elseif currentFps > TARGET_FPS_MAX then
                pollingInterval = math.max(POLL_MIN_INTERVAL, pollingInterval - 0.01)
            end
        end
        pollingInterval = math.clamp(pollingInterval, POLL_MIN_INTERVAL, POLL_MAX_INTERVAL)
        refreshServers()
        task.wait(pollingInterval)
    end
end)

-- UI updates for TTL fade
task.spawn(function()
    while screenGui.Parent do
        for jobId, entry in pairs(servers) do
            local card = cards[jobId]
            if card and card.badge then
                card.badge.Visible = os.clock() - entry.firstSeen < NEW_BADGE_SECONDS
            end
        end
        task.wait(0.1)
    end
end)

--//== Input Handling for Settings ==//--
local function sanitizeNonNegativeNumber(text)
    local value = tonumber(text) or 0
    if value < 0 then
        displayBanner("Negative values are clamped to 0", 2)
    end
    value = math.max(0, value)
    return value
end

moneyFilterBox.FocusLost:Connect(function()
    local value = moneyFilterBox.Text or ""
    if type(value) ~= "string" then
        value = ""
    end
    local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        trimmed = "0"
    end
    moneyFilterBox.Text = trimmed
    Config.moneyFilter = trimmed
    saveConfig(Config)
    refreshServers()
end)

retryAmountBox.FocusLost:Connect(function()
    local sanitized = sanitizeNonNegativeNumber(retryAmountBox.Text)
    Config.retryAmount = sanitized
    retryAmountBox.Text = tostring(sanitized)
    saveConfig(Config)
end)

whitelistBox.FocusLost:Connect(function()
    Config.whitelist = splitCSV(whitelistBox.Text)
    saveConfig(Config)
    resetAutoJoin()
    refreshServers()
end)

blacklistBox.FocusLost:Connect(function()
    Config.blacklist = splitCSV(blacklistBox.Text)
    saveConfig(Config)
    resetAutoJoin()
    refreshServers()
end)

autoJoinToggle.changed = function(value)
    Config.autoJoin = value
    if value then
        resetAutoJoin()
        for jobId in pairs(servers) do
            seenJobIds[jobId] = true
        end
    else
        resetAutoJoin()
        resetRetryState()
    end
    saveConfig(Config)
end

autoInjectToggle.changed = function(value)
    Config.autoInject = value
    if value then
        queueAutoInject()
    end
    saveConfig(Config)
end

-- refresh once at start
refreshServers()
