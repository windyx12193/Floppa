-- Zamorozka Auto Joiner
-- Frosty themed auto joiner with UI, server polling, and config persistence.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local LOCAL_PLAYER = Players.LocalPlayer

local ENDPOINT = "https://server-eta-two-29.vercel.app"
local API_KEY = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"
local PLACE_ID = 109983668079237
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"
local CONFIG_PATH = "zamorozka_auto_joiner.json"
local TTL_SECONDS = 180
local NEW_BADGE_TIME = 5
local MAX_POLL_INTERVAL = 1
local MIN_POLL_INTERVAL = 0.1

local DEFAULT_CONFIG = {
    autoJoin = false,
    autoInject = false,
    moneyFilter = 0,
    retryAmount = 0,
    blacklist = {},
    whitelist = {},
}

local config = {}
local serverRecords = {}
local serverCards = {}
local averageFrameTime = 1 / 60
local networkBackoff = 0.2
local joinRetryThread = nil
local autoJoinInProgress = false
local guiVisible = true

local queueOnTeleport = queue_on_teleport or (syn and syn.queue_on_teleport)
if not queueOnTeleport and getgenv then
    local env = getgenv()
    queueOnTeleport = env.queue_on_teleport or env.QueueOnTeleport
end

local function tableClone(tbl)
    local clone = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            clone[k] = tableClone(v)
        else
            clone[k] = v
        end
    end
    return clone
end

local function loadConfig()
    config = tableClone(DEFAULT_CONFIG)
    if typeof(isfile) == "function" and isfile(CONFIG_PATH) then
        local success, data = pcall(readfile, CONFIG_PATH)
        if success and data and #data > 0 then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, data)
            if ok and type(decoded) == "table" then
                for key, value in pairs(DEFAULT_CONFIG) do
                    local incoming = decoded[key]
                    if incoming ~= nil then
                        if type(value) == "table" and type(incoming) == "table" then
                            config[key] = incoming
                        elseif type(value) ~= "table" then
                            config[key] = incoming
                        end
                    end
                end
            end
        end
    end
end

local function saveConfig()
    if typeof(writefile) ~= "function" then
        return
    end
    local serialized = HttpService:JSONEncode(config)
    local success, err = pcall(writefile, CONFIG_PATH, serialized)
    if not success then
        warn("[Zamorozka] Failed to save config:", err)
    end
end

local function sanitizeList(list)
    local result = {}
    local seen = {}
    for _, entry in ipairs(list) do
        local trimmed = string.gsub(entry, "^%s+", "")
        trimmed = string.gsub(trimmed, "%s+$", "")
        if #trimmed > 0 and not seen[string.lower(trimmed)] then
            table.insert(result, trimmed)
            seen[string.lower(trimmed)] = true
        end
    end
    return result
end

local function parseCsv(text)
    if not text or text == "" then
        return {}
    end
    local result = {}
    for token in string.gmatch(text, "[^,]+") do
        table.insert(result, token)
    end
    return sanitizeList(result)
end

local moneyMultipliers = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
}

local function parseMoney(text)
    if not text then
        return 0
    end
    text = string.lower(text)
    text = string.gsub(text, "[^%d%.kmb]", "")
    local numberPart = string.match(text, "%d+%.?%d*")
    if not numberPart then
        return 0
    end
    local value = tonumber(numberPart) or 0
    local suffix = string.match(text, "[kmb]")
    if suffix and moneyMultipliers[suffix] then
        value = value * moneyMultipliers[suffix]
    end
    return math.floor(value + 0.5)
end

local function parsePlayers(text)
    if not text then
        return 0, 0
    end
    local current, max = string.match(text, "(%d+)%s*/%s*(%d+)")
    current = tonumber(current) or 0
    max = tonumber(max) or 0
    return current, max
end

local function parseTimestamp(text)
    if not text then
        return nil
    end
    local day, month, year, hour, min, sec = string.match(text, "(%d%d)%.(%d%d)%.(%d%d%d%d),%s*(%d%d):(%d%d):(%d%d)")
    if not day then
        return nil
    end
    local timestamp = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })
    return timestamp
end

local function normalizeLine(line)
    line = string.gsub(line, "%*%*", "")
    line = string.gsub(line, "%s+", " ")
    line = string.gsub(line, "%s+|%s+", " | ")
    return string.gsub(line, "^%s+", "")
end

local function parseLine(line)
    line = normalizeLine(line)
    if line == "" then
        return nil
    end
    local segments = {}
    for segment in string.gmatch(line, "[^|]+") do
        table.insert(segments, (string.gsub(segment, "^%s+", "")))
    end
    if #segments < 5 then
        return nil
    end
    local name = string.gsub(segments[1], "%s+$", "")
    local moneyPerSec = parseMoney(segments[2])
    local players, maxPlayers = parsePlayers(segments[3])
    local jobId = string.gsub(segments[4], "%s+$", "")
    local timestamp = parseTimestamp(segments[5])
    if jobId == "" then
        return nil
    end
    return {
        name = name,
        moneyPerSec = moneyPerSec,
        players = players,
        maxPlayers = maxPlayers,
        jobId = jobId,
        timestamp = timestamp,
    }
end

local function formatMoneyDisplay(value)
    if value >= 1e9 then
        return string.format("%.1fb/s", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.1fm/s", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.0fk/s", value / 1e3)
    else
        return string.format("%d/s", value)
    end
end

local networkBanner
local function setBanner(text)
    if not networkBanner then
        return
    end
    networkBanner.Text = text or ""
    networkBanner.Visible = text ~= nil and text ~= ""
end

local ui = {}

local function createBaseGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ZamorozkaAutoJoiner"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    screenGui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainContainer"
    mainFrame.Size = UDim2.new(0.45, 0, 0.6, 0)
    mainFrame.Position = UDim2.new(0.275, 0, 0.2, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(235, 241, 247)
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(200, 220, 240)
    stroke.Parent = mainFrame

    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.BackgroundColor3 = Color3.fromRGB(248, 251, 255)
    topBar.BackgroundTransparency = 0.05
    topBar.Size = UDim2.new(1, 0, 0.15, 0)
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame

    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 12)
    topCorner.Parent = topBar

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = "Zamorozka Auto Joiner"
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.TextColor3 = Color3.fromRGB(50, 80, 120)
    title.Size = UDim2.new(0.7, 0, 0.8, 0)
    title.Position = UDim2.new(0.02, 0, 0.1, 0)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = topBar

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Text = "Frosty server tracker"
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextScaled = true
    subtitle.TextColor3 = Color3.fromRGB(120, 150, 190)
    subtitle.Size = UDim2.new(0.25, 0, 0.6, 0)
    subtitle.Position = UDim2.new(0.73, 0, 0.2, 0)
    subtitle.BackgroundTransparency = 1
    subtitle.TextXAlignment = Enum.TextXAlignment.Right
    subtitle.Parent = topBar

    networkBanner = Instance.new("TextLabel")
    networkBanner.Name = "Banner"
    networkBanner.Visible = false
    networkBanner.BackgroundTransparency = 1
    networkBanner.TextColor3 = Color3.fromRGB(200, 80, 80)
    networkBanner.Font = Enum.Font.Gotham
    networkBanner.TextScaled = true
    networkBanner.Size = UDim2.new(0.6, 0, 0.5, 0)
    networkBanner.Position = UDim2.new(0.2, 0, 0.5, 0)
    networkBanner.Text = ""
    networkBanner.Parent = topBar

    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.BackgroundTransparency = 1
    contentFrame.Size = UDim2.new(1, -20, 0.85, -20)
    contentFrame.Position = UDim2.new(0, 10, 0.15, 10)
    contentFrame.Parent = mainFrame

    local settingsPanel = Instance.new("Frame")
    settingsPanel.Name = "SettingsPanel"
    settingsPanel.BackgroundTransparency = 0.15
    settingsPanel.BackgroundColor3 = Color3.fromRGB(240, 245, 250)
    settingsPanel.Size = UDim2.new(0.28, 0, 1, 0)
    settingsPanel.BorderSizePixel = 0
    settingsPanel.Parent = contentFrame

    local settingsCorner = Instance.new("UICorner")
    settingsCorner.CornerRadius = UDim.new(0, 12)
    settingsCorner.Parent = settingsPanel

    local settingsLayout = Instance.new("UIListLayout")
    settingsLayout.Padding = UDim.new(0, 8)
    settingsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    settingsLayout.Parent = settingsPanel

    local serverPanel = Instance.new("Frame")
    serverPanel.Name = "ServerPanel"
    serverPanel.BackgroundTransparency = 0.2
    serverPanel.BackgroundColor3 = Color3.fromRGB(245, 249, 255)
    serverPanel.Size = UDim2.new(0.7, 0, 1, 0)
    serverPanel.Position = UDim2.new(0.3, 10, 0, 0)
    serverPanel.BorderSizePixel = 0
    serverPanel.Parent = contentFrame

    local serverCorner = Instance.new("UICorner")
    serverCorner.CornerRadius = UDim.new(0, 12)
    serverCorner.Parent = serverPanel

    local serverLayout = Instance.new("UIListLayout")
    serverLayout.Padding = UDim.new(0, 6)
    serverLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    serverLayout.SortOrder = Enum.SortOrder.LayoutOrder
    serverLayout.Parent = serverPanel

    local serverScroller = Instance.new("ScrollingFrame")
    serverScroller.Name = "ServerScroller"
    serverScroller.BackgroundTransparency = 1
    serverScroller.BorderSizePixel = 0
    serverScroller.Size = UDim2.new(1, -20, 1, -20)
    serverScroller.Position = UDim2.new(0, 10, 0, 10)
    serverScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
    serverScroller.ScrollBarThickness = 6
    serverScroller.ScrollBarImageColor3 = Color3.fromRGB(180, 210, 240)
    serverScroller.Parent = serverPanel

    local scrollerLayout = Instance.new("UIListLayout")
    scrollerLayout.Padding = UDim.new(0, 6)
    scrollerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scrollerLayout.Parent = serverScroller

    ui.screenGui = screenGui
    ui.mainFrame = mainFrame
    ui.settingsPanel = settingsPanel
    ui.serverScroller = serverScroller
    ui.scrollerLayout = scrollerLayout
    ui.topBar = topBar
    ui.serverPanel = serverPanel
end

local function makeSettingHeader(text)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.9, 0, 0, 28)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(70, 105, 150)
    label.Text = text
    return label
end

local function makeToggle(name, initial, callback)
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(0.9, 0, 0, 40)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 0, 0, 0)
    label.Size = UDim2.new(0.65, 0, 1, 0)
    label.Font = Enum.Font.Gotham
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(80, 110, 150)
    label.Text = name
    label.Parent = container

    local button = Instance.new("TextButton")
    button.BackgroundColor3 = initial and Color3.fromRGB(120, 200, 140) or Color3.fromRGB(150, 160, 170)
    button.AutoButtonColor = false
    button.Text = initial and "ON" or "OFF"
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Size = UDim2.new(0.3, 0, 0.8, 0)
    button.Position = UDim2.new(0.7, 0, 0.1, 0)
    button.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = button

    button.MouseButton1Click:Connect(function()
        local newState = not initial
        initial = newState
        button.Text = newState and "ON" or "OFF"
        button.BackgroundColor3 = newState and Color3.fromRGB(120, 200, 140) or Color3.fromRGB(150, 160, 170)
        callback(newState)
    end)

    return container, function(newValue)
        initial = newValue
        button.Text = newValue and "ON" or "OFF"
        button.BackgroundColor3 = newValue and Color3.fromRGB(120, 200, 140) or Color3.fromRGB(150, 160, 170)
    end
end

local function makeTextbox(labelText, defaultText, placeholder, callback)
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(0.9, 0, 0, 56)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0.45, 0)
    label.Font = Enum.Font.Gotham
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(90, 120, 160)
    label.Text = labelText
    label.Parent = container

    local box = Instance.new("TextBox")
    box.BackgroundTransparency = 0.15
    box.BackgroundColor3 = Color3.fromRGB(230, 236, 244)
    box.Size = UDim2.new(1, 0, 0.5, 0)
    box.Position = UDim2.new(0, 0, 0.5, 0)
    box.Font = Enum.Font.Gotham
    box.TextScaled = true
    box.ClearTextOnFocus = false
    box.PlaceholderText = placeholder or ""
    box.TextColor3 = Color3.fromRGB(60, 90, 130)
    box.Text = defaultText or ""
    box.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = box

    local function submit()
        callback(box.Text)
    end

    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            submit()
        else
            submit()
        end
    end)

    return container, function(newText)
        box.Text = newText
    end
end

local toggleHandlers = {}
local textboxHandlers = {}
local updateToggle
local updateTextbox

local function initializeSettings()
    local panel = ui.settingsPanel
    panel:ClearAllChildren()
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = panel

    local togglesHeader = makeSettingHeader("Toggles")
    togglesHeader.LayoutOrder = 1
    togglesHeader.Parent = panel

    local autoJoinToggle, updateAutoJoinToggle = makeToggle("Auto Join", config.autoJoin, function(state)
        config.autoJoin = state
        saveConfig()
    end)
    autoJoinToggle.LayoutOrder = 2
    autoJoinToggle.Parent = panel
    toggleHandlers.autoJoin = updateAutoJoinToggle

    local autoInjectToggle, updateAutoInjectToggle = makeToggle("Auto Inject", config.autoInject, function(state)
        config.autoInject = state
        saveConfig()
    end)
    autoInjectToggle.LayoutOrder = 3
    autoInjectToggle.Parent = panel
    toggleHandlers.autoInject = updateAutoInjectToggle

    local filtersHeader = makeSettingHeader("Filters")
    filtersHeader.LayoutOrder = 4
    filtersHeader.Parent = panel

    local moneyFilterBox, updateMoneyBox = makeTextbox("Minimum money (k/m/b)", config.moneyFilter > 0 and formatMoneyDisplay(config.moneyFilter) or "0", "e.g. 500k", function(text)
        local value = parseMoney(text)
        if value < 0 then
            value = 0
        end
        config.moneyFilter = value
        saveConfig()
        updateTextbox("money", value > 0 and formatMoneyDisplay(value) or "0")
    end)
    moneyFilterBox.LayoutOrder = 5
    moneyFilterBox.Parent = panel
    textboxHandlers.money = updateMoneyBox

    local retryBox, updateRetryBox = makeTextbox("Join retry amount", tostring(config.retryAmount or 0), "0 disables", function(text)
        local numberValue = tonumber(text)
        if not numberValue or numberValue < 0 then
            numberValue = math.max(0, tonumber(text) or 0)
        end
        numberValue = math.floor(numberValue)
        if numberValue < 0 then
            numberValue = 0
        end
        config.retryAmount = numberValue
        saveConfig()
        updateTextbox("retry", tostring(numberValue))
    end)
    retryBox.LayoutOrder = 6
    retryBox.Parent = panel
    textboxHandlers.retry = updateRetryBox

    local whitelistBox, updateWhitelist = makeTextbox("Whitelist (CSV)", table.concat(config.whitelist or {}, ","), "name1,name2", function(text)
        local parsed = parseCsv(text)
        config.whitelist = parsed
        saveConfig()
        updateTextbox("whitelist", table.concat(parsed, ","))
    end)
    whitelistBox.LayoutOrder = 7
    whitelistBox.Parent = panel
    textboxHandlers.whitelist = updateWhitelist

    local blacklistBox, updateBlacklist = makeTextbox("Blacklist (CSV)", table.concat(config.blacklist or {}, ","), "name1,name2", function(text)
        local parsed = parseCsv(text)
        config.blacklist = parsed
        saveConfig()
        updateTextbox("blacklist", table.concat(parsed, ","))
    end)
    blacklistBox.LayoutOrder = 8
    blacklistBox.Parent = panel
    textboxHandlers.blacklist = updateBlacklist

    local infoLabel = Instance.new("TextLabel")
    infoLabel.BackgroundTransparency = 1
    infoLabel.Size = UDim2.new(0.9, 0, 0, 40)
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextScaled = true
    infoLabel.TextColor3 = Color3.fromRGB(110, 140, 180)
    infoLabel.TextWrapped = true
    infoLabel.Text = "Press K to toggle the UI"
    infoLabel.LayoutOrder = 9
    infoLabel.Parent = panel
end

local function updateToggleInternal(name, state)
    if toggleHandlers[name] then
        toggleHandlers[name](state)
    end
end

updateToggle = updateToggleInternal

local function updateTextboxInternal(name, text)
    if textboxHandlers[name] then
        textboxHandlers[name](text)
    end
end

updateTextbox = updateTextboxInternal

local function createServerCard(record)
    local frame = Instance.new("Frame")
    frame.Name = record.jobId
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, -10, 0, 70)
    frame.LayoutOrder = 1

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(200, 215, 235)
    stroke.Parent = frame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0.03, 0, 0.15, 0)
    nameLabel.Size = UDim2.new(0.4, 0, 0.35, 0)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextScaled = true
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextColor3 = Color3.fromRGB(60, 90, 130)
    nameLabel.Text = record.name
    nameLabel.Parent = frame

    local moneyLabel = Instance.new("TextLabel")
    moneyLabel.Name = "MoneyLabel"
    moneyLabel.BackgroundTransparency = 1
    moneyLabel.Position = UDim2.new(0.03, 0, 0.55, 0)
    moneyLabel.Size = UDim2.new(0.25, 0, 0.35, 0)
    moneyLabel.Font = Enum.Font.GothamBold
    moneyLabel.TextScaled = true
    moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
    moneyLabel.TextColor3 = Color3.fromRGB(80, 170, 100)
    moneyLabel.Text = "$" .. formatMoneyDisplay(record.moneyPerSec)
    moneyLabel.Parent = frame

    local playersLabel = Instance.new("TextLabel")
    playersLabel.Name = "PlayersLabel"
    playersLabel.BackgroundTransparency = 1
    playersLabel.Position = UDim2.new(0.3, 0, 0.55, 0)
    playersLabel.Size = UDim2.new(0.2, 0, 0.35, 0)
    playersLabel.Font = Enum.Font.GothamBold
    playersLabel.TextScaled = true
    playersLabel.TextXAlignment = Enum.TextXAlignment.Left
    playersLabel.TextColor3 = Color3.fromRGB(90, 140, 200)
    playersLabel.Text = string.format("%d/%d", record.players, record.maxPlayers)
    playersLabel.Parent = frame

    local newBadge = Instance.new("TextLabel")
    newBadge.Name = "NewBadge"
    newBadge.BackgroundColor3 = Color3.fromRGB(180, 220, 255)
    newBadge.BackgroundTransparency = 0.2
    newBadge.Size = UDim2.new(0, 60, 0, 24)
    newBadge.Position = UDim2.new(0.52, 0, 0.1, 0)
    newBadge.Visible = false
    newBadge.Font = Enum.Font.GothamBold
    newBadge.TextScaled = true
    newBadge.TextColor3 = Color3.fromRGB(60, 90, 130)
    newBadge.Text = "NEW"
    newBadge.Parent = frame

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 8)
    badgeCorner.Parent = newBadge

    local joinButton = Instance.new("TextButton")
    joinButton.Name = "JoinButton"
    joinButton.BackgroundColor3 = Color3.fromRGB(150, 220, 170)
    joinButton.BackgroundTransparency = 0.05
    joinButton.Size = UDim2.new(0, 120, 0, 36)
    joinButton.Position = UDim2.new(0.72, 0, 0.5, 0)
    joinButton.Font = Enum.Font.GothamBold
    joinButton.TextScaled = true
    joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    joinButton.Text = "Join"
    joinButton.Parent = frame

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 12)
    buttonCorner.Parent = joinButton

    joinButton.MouseButton1Click:Connect(function()
        local data = serverRecords[record.jobId]
        if data then
            local success = false
            if data.players >= data.maxPlayers then
                if config.retryAmount and config.retryAmount > 0 then
                    print(string.format("[Zamorozka] Server full, starting retry %s", data.jobId))
                    task.spawn(function()
                        local ok = false
                        local reason = "Instance full"
                        local function attempt()
                            local attemptSuccess, err = pcall(function()
                                if config.autoInject and queueOnTeleport then
                                    queueOnTeleport(string.format("loadstring(game:HttpGet(%q))()", AUTO_INJECT_URL))
                                end
                                TeleportService:TeleportToPlaceInstance(PLACE_ID, data.jobId, LOCAL_PLAYER)
                            end)
                            if attemptSuccess then
                                ok = true
                                setBanner("")
                                config.autoJoin = false
                                updateToggle("autoJoin", false)
                                saveConfig()
                                return true
                            else
                                reason = tostring(err)
                            end
                        end
                        local maxAttempts = config.retryAmount
                        for attemptIndex = 1, maxAttempts do
                            print(string.format("[Zamorozka] join retry %d/%d", attemptIndex, maxAttempts))
                            if attempt() then
                                return
                            end
                            task.wait(0.1)
                        end
                        if not ok then
                            setBanner(reason)
                        end
                    end)
                else
                    setBanner("Server is full. Increase retry amount.")
                end
            else
                success = pcall(function()
                    if config.autoInject and queueOnTeleport then
                        queueOnTeleport(string.format("loadstring(game:HttpGet(%q))()", AUTO_INJECT_URL))
                    end
                    TeleportService:TeleportToPlaceInstance(PLACE_ID, data.jobId, LOCAL_PLAYER)
                end)
                if success then
                    config.autoJoin = false
                    updateToggle("autoJoin", false)
                    saveConfig()
                    setBanner("")
                end
            end
        end
    end)

    return frame
end

local function updateServerCard(card, record)
    if not card or not card.Parent then
        return
    end
    local nameLabel = card:FindFirstChild("NameLabel")
    local moneyLabel = card:FindFirstChild("MoneyLabel")
    local playersLabel = card:FindFirstChild("PlayersLabel")
    local newBadge = card:FindFirstChild("NewBadge")

    if nameLabel then
        nameLabel.Text = record.name
    end
    if moneyLabel then
        moneyLabel.Text = "$" .. formatMoneyDisplay(record.moneyPerSec)
    end
    if playersLabel then
        playersLabel.Text = string.format("%d/%d", record.players, record.maxPlayers)
    end
    if newBadge then
        local age = os.clock() - record.arrivalUnix
        newBadge.Visible = age <= NEW_BADGE_TIME
    end
end

local function removeServerCard(jobId)
    local card = serverCards[jobId]
    if not card then
        return
    end
    serverCards[jobId] = nil
    local tween = TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1,
        Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, 0, 0),
    })
    tween:Play()
    tween.Completed:Connect(function()
        card:Destroy()
    end)
end

local function filterServer(record)
    if config.whitelist and #config.whitelist > 0 then
        local ok = false
        for _, name in ipairs(config.whitelist) do
            if string.lower(name) == string.lower(record.name) then
                ok = true
                break
            end
        end
        if not ok then
            return false
        end
    elseif config.blacklist and #config.blacklist > 0 then
        for _, name in ipairs(config.blacklist) do
            if string.lower(name) == string.lower(record.name) then
                return false
            end
        end
    end
    if config.moneyFilter and config.moneyFilter > 0 and record.moneyPerSec < config.moneyFilter then
        return false
    end
    return true
end

local function rebuildServerList()
    if not ui.serverScroller then
        return
    end
    local nowClock = os.clock()
    local entries = {}

    for jobId, record in pairs(serverRecords) do
        if nowClock - record.lastSeen > TTL_SECONDS then
            removeServerCard(jobId)
            serverRecords[jobId] = nil
        else
            if filterServer(record) then
                table.insert(entries, record)
            else
                removeServerCard(jobId)
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.moneyPerSec ~= b.moneyPerSec then
            return a.moneyPerSec > b.moneyPerSec
        end
        return a.arrivalUnix > b.arrivalUnix
    end)

    local order = 0
    for _, record in ipairs(entries) do
        local card = serverCards[record.jobId]
        if not card or not card.Parent then
            card = createServerCard(record)
            card.Parent = ui.serverScroller
            serverCards[record.jobId] = card
            card.BackgroundTransparency = 1
            card.Size = UDim2.new(1, -10, 0, 0)
            TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 0.25,
                Size = UDim2.new(1, -10, 0, 70),
            }):Play()
        else
            updateServerCard(card, record)
        end
        order += 1
        card.LayoutOrder = order
    end

    ui.serverScroller.CanvasSize = UDim2.new(0, 0, 0, order * 76)

    for jobId, card in pairs(serverCards) do
        if not serverRecords[jobId] then
            removeServerCard(jobId)
        end
    end
end

local function queueAutoInject()
    if config.autoInject and queueOnTeleport then
        queueOnTeleport(string.format("loadstring(game:HttpGet(%q))()", AUTO_INJECT_URL))
    end
end

local function attemptTeleport(record)
    local success, err = pcall(function()
        queueAutoInject()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, record.jobId, LOCAL_PLAYER)
    end)
    if success then
        config.autoJoin = false
        updateToggle("autoJoin", false)
        saveConfig()
        setBanner("")
    else
        warn("[Zamorozka] Teleport failed:", err)
    end
    return success
end

local function startJoinRetry(record)
    if joinRetryThread then
        return
    end
    local maxAttempts = math.max(0, config.retryAmount or 0)
    if maxAttempts == 0 then
        return
    end
    joinRetryThread = coroutine.create(function()
        for attempt = 1, maxAttempts do
            print(string.format("[Zamorozka] join retry %d/%d", attempt, maxAttempts))
            if attemptTeleport(record) then
                joinRetryThread = nil
                return
            end
            task.wait(0.1)
        end
        joinRetryThread = nil
    end)
    coroutine.resume(joinRetryThread)
end

local function getAutoJoinTarget()
    if not config.autoJoin then
        return nil
    end
    local nowClock = os.clock()
    local newCandidates = {}
    local otherCandidates = {}

    for _, record in pairs(serverRecords) do
        if filterServer(record) and record.players < record.maxPlayers then
            if nowClock - record.arrivalUnix <= NEW_BADGE_TIME then
                table.insert(newCandidates, record)
            else
                table.insert(otherCandidates, record)
            end
        end
    end

    local function sortCandidates(list)
        table.sort(list, function(a, b)
            if a.moneyPerSec ~= b.moneyPerSec then
                return a.moneyPerSec > b.moneyPerSec
            end
            return a.arrivalUnix > b.arrivalUnix
        end)
    end

    if #newCandidates > 0 then
        sortCandidates(newCandidates)
        return newCandidates[1]
    elseif #otherCandidates > 0 then
        sortCandidates(otherCandidates)
        return otherCandidates[1]
    end
    return nil
end

local function evaluateAutoJoin()
    if autoJoinInProgress or not config.autoJoin then
        return
    end
    local target = getAutoJoinTarget()
    if not target then
        return
    end
    autoJoinInProgress = true
    if target.players >= target.maxPlayers then
        if (config.retryAmount or 0) > 0 then
            startJoinRetry(target)
        else
            setBanner("Best server full. Increase retry amount for auto join.")
        end
    else
        if not attemptTeleport(target) then
            if (config.retryAmount or 0) > 0 then
                startJoinRetry(target)
            end
        end
    end
    autoJoinInProgress = false
end

local function processResponse(body)
    local lines = {}
    for line in string.gmatch(body, "[^\n]+") do
        table.insert(lines, line)
    end
    local nowClock = os.clock()
    for _, rawLine in ipairs(lines) do
        local parsed = parseLine(rawLine)
        if parsed then
            local record = serverRecords[parsed.jobId]
            if record then
                record.name = parsed.name
                record.moneyPerSec = parsed.moneyPerSec
                record.players = parsed.players
                record.maxPlayers = parsed.maxPlayers
                record.timestamp = parsed.timestamp or record.timestamp
                record.lastSeen = nowClock
            else
                serverRecords[parsed.jobId] = {
                    name = parsed.name,
                    moneyPerSec = parsed.moneyPerSec,
                    players = parsed.players,
                    maxPlayers = parsed.maxPlayers,
                    jobId = parsed.jobId,
                    timestamp = parsed.timestamp,
                    arrivalUnix = nowClock,
                    lastSeen = nowClock,
                }
            end
        end
    end
end

local function pollServers()
    while true do
        local start = os.clock()
        local requestPayload = {
            Url = ENDPOINT,
            Method = "GET",
            Headers = {
                ["x-api-key"] = API_KEY,
            },
        }
        local success, response = pcall(function()
            return HttpService:RequestAsync(requestPayload)
        end)
        if success and response and response.Success and response.StatusCode == 200 then
            networkBackoff = math.max(MIN_POLL_INTERVAL, networkBackoff * 0.8)
            setBanner("")
            processResponse(response.Body or "")
            rebuildServerList()
            evaluateAutoJoin()
        else
            local status = success and (response.StatusCode .. " ") or ""
            setBanner(string.format("Network error %s- backing off", status))
            networkBackoff = math.min(MAX_POLL_INTERVAL, networkBackoff * 1.5)
        end
        local elapsed = os.clock() - start
        local waitTime = math.max(networkBackoff - elapsed, MIN_POLL_INTERVAL)
        task.wait(waitTime)
    end
end

local function handleFrameTime(dt)
    averageFrameTime += (dt - averageFrameTime) * 0.1
    if averageFrameTime > 1 / 50 then
        networkBackoff = math.min(MAX_POLL_INTERVAL, networkBackoff * 1.1)
    elseif averageFrameTime < 1 / 70 then
        networkBackoff = math.max(MIN_POLL_INTERVAL, networkBackoff * 0.95)
    end
end

local function bindKeyToggle()
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == Enum.KeyCode.K then
            guiVisible = not guiVisible
            if ui.mainFrame then
                ui.mainFrame.Visible = guiVisible
            end
        end
    end)
end

local function initialize()
    loadConfig()
    createBaseGui()
    initializeSettings()
    updateToggle("autoJoin", config.autoJoin)
    updateToggle("autoInject", config.autoInject)
    updateTextbox("money", config.moneyFilter > 0 and formatMoneyDisplay(config.moneyFilter) or "0")
    updateTextbox("retry", tostring(config.retryAmount or 0))
    updateTextbox("whitelist", table.concat(config.whitelist or {}, ","))
    updateTextbox("blacklist", table.concat(config.blacklist or {}, ","))

    bindKeyToggle()

    RunService.Heartbeat:Connect(handleFrameTime)

    task.spawn(pollServers)

    queueAutoInject()
end

initialize()
