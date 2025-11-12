--[[
    Zamorozka Auto Joiner
    Roblox Lua Script
    
    Features:
    - Fetches server list from external API
    - Auto Join with filters and retry support
    - Auto Inject script on join
    - Configurable filters (money, whitelist, blacklist)
    - Real-time server updates with TTL
    - Performance optimized with FPS throttling
    
    Usage:
    1. Execute this script in your Roblox executor
    2. Configure settings in the left panel
    3. Enable Auto Join to automatically join suitable servers
    4. Enable Auto Inject to auto-load script on join
    
    Config is saved to: zamorozka_config.json
--]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Configuration
local CONFIG = {
    API_ENDPOINT = "https://server-eta-two-29.vercel.app",
    API_KEY = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja",
    PLACE_ID = 109983668079237,
    INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua",
    POLL_RATE = 0.1, -- 10 Hz (100ms)
    TTL = 180, -- seconds
    NEW_BADGE_DURATION = 5, -- seconds
    RETRY_RATE = 0.1, -- 100ms between retries
    MAX_FRAME_TIME = 0.016, -- ~60 FPS threshold
}

-- State
local state = {
    servers = {}, -- {jobId: {name, moneyPerSec, players, maxPlayers, jobId, timestamp, order, ui}}
    config = {
        autoJoin = false,
        autoInject = false,
        moneyFilter = 0,
        retryAmount = 0,
        blacklist = {},
        whitelist = {}
    },
    orderCounter = 0,
    lastPollTime = 0,
    lastFrameTime = 0,
    retryAttempts = 0,
    retryJobId = nil,
    retryActive = false,
    networkError = false,
    currentJobId = nil,
    uiVisible = true,
    screenGui = nil,
}

-- Utility Functions
local function normalizeMoney(moneyStr)
    if not moneyStr then return 0 end
    -- Remove $, /s, spaces, and markdown markers
    moneyStr = tostring(moneyStr):gsub("$", ""):gsub("/s", ""):gsub(" ", ""):gsub("%*", "")
    
    -- Extract number (supports decimals like 12.5)
    local numStr = moneyStr:match("%d+%.?%d*")
    if not numStr then return 0 end
    
    local num = tonumber(numStr)
    if not num then return 0 end
    
    -- Extract suffix (K, M, B)
    local suffix = moneyStr:match("[kmbKMB]")
    if suffix then
        suffix = suffix:lower()
        if suffix == "k" then
            return num * 1000
        elseif suffix == "m" then
            return num * 1000000
        elseif suffix == "b" then
            return num * 1000000000
        end
    end
    
    return num
end

local function parseCSV(csvStr)
    if not csvStr or csvStr == "" then return {} end
    local result = {}
    for item in csvStr:gmatch("([^,]+)") do
        table.insert(result, item:match("^%s*(.-)%s*$"))
    end
    return result
end

local function parseTimestamp(dateTimeStr)
    -- Parse format: "DD.MM.YYYY, HH:MM:SS" or "DD.MM.YYYY, HH:MM:SS"
    -- Example: "11.11.2025, 22:21:05" or "12.11.2025, 17:07:43"
    
    if not dateTimeStr then return os.time() end
    
    -- Extract date and time parts
    local datePart, timePart = dateTimeStr:match("([^,]+),%s*(.+)")
    if not datePart or not timePart then
        -- Try to parse as Unix timestamp
        local ts = tonumber(dateTimeStr)
        if ts then return ts end
        return os.time() -- Fallback to current time
    end
    
    -- Parse date: DD.MM.YYYY
    local day, month, year = datePart:match("(%d+)%.(%d+)%.(%d+)")
    if not day or not month or not year then
        return os.time()
    end
    
    -- Parse time: HH:MM:SS
    local hour, minute, second = timePart:match("(%d+):(%d+):(%d+)")
    if not hour or not minute or not second then
        return os.time()
    end
    
    -- Convert to Unix timestamp
    -- Note: os.time expects {year, month, day, hour, min, sec}
    local success, timestamp = pcall(function()
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(minute),
            sec = tonumber(second)
        })
    end)
    
    if success and timestamp then
        return timestamp
    end
    
    return os.time() -- Fallback
end

local function parseServerLine(line)
    -- Support formats:
    -- "<name> | $<money>/s | <players>/<max> | <jobId> | DD.MM.YYYY, HH:MM:SS"
    -- "<name> | **$<money>/s** | **<players>/<max>** | <jobId> | DD.MM.YYYY, HH:MM:SS"
    -- Examples:
    -- "Los Mobilis  |  $22M/s  |  6/8  |  31915a24-d258-4a8c-9ddb-e669b59b3b08   | 11.11.2025, 22:21:05"
    -- "Vulturino Skeletono  |  **$500K/s**  |  **6/8**  |  f4cbec62-f91e-45e1-99e3-a2809e975e3d   | 11.11.2025, 21:34:01"
    
    if not line or line == "" then return nil end
    
    -- Remove markdown bold markers
    line = line:gsub("%*%*", "")
    
    local parts = {}
    for part in line:gmatch("([^|]+)") do
        table.insert(parts, part:match("^%s*(.-)%s*$"))
    end
    
    if #parts < 5 then return nil end
    
    local name = parts[1]
    local moneyStr = parts[2]
    local playersStr = parts[3]
    local jobId = parts[4]:match("^%s*(.-)%s*$") -- Trim whitespace
    local timestampStr = parts[5]
    
    if not name or not jobId or name == "" or jobId == "" then return nil end
    
    -- Parse money (handle formats like "$22M/s", "$12.5M/s", "$500K/s")
    local moneyPerSec = normalizeMoney(moneyStr)
    
    -- Parse players (handle formats like "6/8", "**6/8**")
    local players, maxPlayers = playersStr:match("(%d+)/(%d+)")
    players = tonumber(players) or 0
    maxPlayers = tonumber(maxPlayers) or 0
    
    -- Parse timestamp
    local timestamp = parseTimestamp(timestampStr)
    
    return {
        name = name,
        moneyPerSec = moneyPerSec,
        players = players,
        maxPlayers = maxPlayers,
        jobId = jobId,
        timestamp = timestamp
    }
end

-- Config Storage
local function getConfigPath()
    -- Try to use executor's filesystem
    local success, path = pcall(function()
        return readfile and readfile("zamorozka_config.json") or nil
    end)
    return "zamorozka_config.json"
end

local function loadConfig()
    local success, content = pcall(function()
        if readfile then
            return readfile(getConfigPath())
        end
        return nil
    end)
    
    if success and content then
        local success2, config = pcall(function()
            return HttpService:JSONDecode(content)
        end)
        if success2 and config then
            state.config = config
            -- Ensure arrays exist
            state.config.blacklist = state.config.blacklist or {}
            state.config.whitelist = state.config.whitelist or {}
            return true
        end
    end
    return false
end

local function saveConfig()
    local success, json = pcall(function()
        return HttpService:JSONEncode(state.config)
    end)
    
    if success and json and writefile then
        pcall(function()
            writefile(getConfigPath(), json)
        end)
    end
end

-- UI Creation
local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ZamorozkaAutoJoiner"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui
    
    -- Main Container
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0.9, 0, 0.85, 0)
    mainFrame.Position = UDim2.new(0.05, 0, 0.075, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(240, 248, 255) -- Light icy blue
    mainFrame.BackgroundTransparency = 0.15
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Blur effect (light)
    local blur = Instance.new("BlurEffect")
    blur.Size = 2
    blur.Parent = mainFrame
    
    -- Top Bar
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0.12, 0)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    topBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    topBar.BackgroundTransparency = 0.1
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 1, 0)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ZAMOROZKA AUTO JOINER"
    title.TextColor3 = Color3.fromRGB(0, 0, 0)
    title.TextSize = 32
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Padding = Instance.new("UIPadding")
    title.Padding.PaddingLeft = UDim.new(0, 20)
    title.Parent = topBar
    
    -- Error Banner
    local errorBanner = Instance.new("TextLabel")
    errorBanner.Name = "ErrorBanner"
    errorBanner.Size = UDim2.new(1, 0, 0.08, 0)
    errorBanner.Position = UDim2.new(0, 0, 0.12, 0)
    errorBanner.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    errorBanner.BackgroundTransparency = 0.2
    errorBanner.BorderSizePixel = 0
    errorBanner.Text = "Network Error - Retrying..."
    errorBanner.TextColor3 = Color3.fromRGB(255, 255, 255)
    errorBanner.TextSize = 18
    errorBanner.Font = Enum.Font.GothamBold
    errorBanner.Visible = false
    errorBanner.Parent = mainFrame
    
    -- Content Container
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, 0, 0.8, 0)
    contentFrame.Position = UDim2.new(0, 0, 0.2, 0)
    contentFrame.BackgroundTransparency = 1
    contentFrame.BorderSizePixel = 0
    contentFrame.Parent = mainFrame
    
    -- Left Panel (Settings)
    local leftPanel = Instance.new("ScrollingFrame")
    leftPanel.Name = "LeftPanel"
    leftPanel.Size = UDim2.new(0.25, 0, 1, 0)
    leftPanel.Position = UDim2.new(0, 0, 0, 0)
    leftPanel.BackgroundColor3 = Color3.fromRGB(200, 220, 240)
    leftPanel.BackgroundTransparency = 0.2
    leftPanel.BorderSizePixel = 0
    leftPanel.ScrollBarThickness = 6
    leftPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
    leftPanel.Parent = contentFrame
    
    local leftLayout = Instance.new("UIListLayout")
    leftLayout.Padding = UDim.new(0, 10)
    leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
    leftLayout.Parent = leftPanel
    
    -- Right Panel (Server List)
    local rightPanel = Instance.new("ScrollingFrame")
    rightPanel.Name = "RightPanel"
    rightPanel.Size = UDim2.new(0.75, 0, 1, 0)
    rightPanel.Position = UDim2.new(0.25, 0, 0, 0)
    rightPanel.BackgroundColor3 = Color3.fromRGB(250, 250, 255)
    rightPanel.BackgroundTransparency = 0.1
    rightPanel.BorderSizePixel = 0
    rightPanel.ScrollBarThickness = 6
    rightPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
    rightPanel.Parent = contentFrame
    
    local rightLayout = Instance.new("UIListLayout")
    rightLayout.Padding = UDim.new(0, 8)
    rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rightLayout.Parent = rightPanel
    
    -- Settings UI Elements
    local toggleButtons = {}
    local function createToggle(name, key, yPos)
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Name = name .. "Toggle"
        toggleFrame.Size = UDim2.new(0.9, 0, 0, 50)
        toggleFrame.Position = UDim2.new(0.05, 0, 0, yPos)
        toggleFrame.BackgroundTransparency = 1
        toggleFrame.LayoutOrder = yPos
        toggleFrame.Parent = leftPanel
        
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(0.6, 0, 1, 0)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = Color3.fromRGB(0, 0, 0)
        label.TextSize = 18
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = toggleFrame
        
        local toggleButton = Instance.new("TextButton")
        toggleButton.Name = "Toggle"
        toggleButton.Size = UDim2.new(0.35, 0, 0.7, 0)
        toggleButton.Position = UDim2.new(0.6, 0, 0.15, 0)
        toggleButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
        toggleButton.BorderSizePixel = 0
        toggleButton.Text = "OFF"
        toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggleButton.TextSize = 16
        toggleButton.Font = Enum.Font.GothamBold
        toggleButton.Parent = toggleFrame
        
        toggleButton.MouseButton1Click:Connect(function()
            state.config[key] = not state.config[key]
            saveConfig()
            updateToggleUI(toggleButton, state.config[key])
        end)
        
        toggleButtons[key] = toggleButton
        updateToggleUI(toggleButton, state.config[key])
        return toggleFrame
    end
    
    local function createInput(name, key, yPos, isNumber)
        local inputFrame = Instance.new("Frame")
        inputFrame.Name = name .. "Input"
        inputFrame.Size = UDim2.new(0.9, 0, 0, 60)
        inputFrame.Position = UDim2.new(0.05, 0, 0, yPos)
        inputFrame.BackgroundTransparency = 1
        inputFrame.LayoutOrder = yPos
        inputFrame.Parent = leftPanel
        
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 0.4, 0)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = Color3.fromRGB(0, 0, 0)
        label.TextSize = 16
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = inputFrame
        
        local textBox = Instance.new("TextBox")
        textBox.Name = "Input"
        textBox.Size = UDim2.new(1, 0, 0.55, 0)
        textBox.Position = UDim2.new(0, 0, 0.45, 0)
        textBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        textBox.BackgroundTransparency = 0.3
        textBox.BorderSizePixel = 0
        textBox.Text = isNumber and tostring(state.config[key] or 0) or table.concat(state.config[key] or {}, ",")
        textBox.TextColor3 = Color3.fromRGB(0, 0, 0)
        textBox.TextSize = 14
        textBox.Font = Enum.Font.Gotham
        textBox.PlaceholderText = isNumber and "0" or "name1,name2,..."
        textBox.Parent = inputFrame
        
        textBox.FocusLost:Connect(function()
            if isNumber then
                local num = tonumber(textBox.Text) or 0
                if num < 0 then
                    num = 0
                    textBox.Text = "0"
                end
                state.config[key] = num
            else
                state.config[key] = parseCSV(textBox.Text)
            end
            saveConfig()
        end)
        
        return inputFrame
    end
    
    local yPos = 0
    createToggle("Auto Join", "autoJoin", yPos)
    yPos = yPos + 60
    createToggle("Auto Inject", "autoInject", yPos)
    yPos = yPos + 70
    createInput("Money Filter (m/s)", "moneyFilter", yPos, true)
    yPos = yPos + 70
    createInput("Join Retry Amount", "retryAmount", yPos, true)
    yPos = yPos + 70
    createInput("Whitelist (CSV)", "whitelist", yPos, false)
    yPos = yPos + 70
    createInput("Blacklist (CSV)", "blacklist", yPos, false)
    
    -- Update canvas size
    leftPanel.CanvasSize = UDim2.new(0, 0, 0, yPos + 70)
    
    return screenGui, leftPanel, rightPanel, errorBanner
end

function updateToggleUI(toggleButton, isOn)
    if isOn then
        toggleButton.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
        toggleButton.Text = "ON"
    else
        toggleButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
        toggleButton.Text = "OFF"
    end
end

-- Server Card Creation
local function createServerCard(serverData, order)
    local card = Instance.new("Frame")
    card.Name = serverData.jobId
    card.Size = UDim2.new(0.95, 0, 0, 60)
    card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    card.BackgroundTransparency = 0.2
    card.BorderSizePixel = 0
    card.LayoutOrder = order
    
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 15)
    padding.PaddingRight = UDim.new(0, 15)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = card
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(0.4, 0, 1, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = serverData.name
    nameLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextSize = 18
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card
    
    local moneyLabel = Instance.new("TextLabel")
    moneyLabel.Name = "Money"
    moneyLabel.Size = UDim2.new(0.15, 0, 1, 0)
    moneyLabel.Position = UDim2.new(0.4, 0, 0, 0)
    moneyLabel.BackgroundTransparency = 1
    local moneyStr = serverData.moneyPerSec >= 1000000000 and string.format("%.1fb/s", serverData.moneyPerSec / 1000000000)
        or serverData.moneyPerSec >= 1000000 and string.format("%.1fm/s", serverData.moneyPerSec / 1000000)
        or serverData.moneyPerSec >= 1000 and string.format("%.1fk/s", serverData.moneyPerSec / 1000)
        or string.format("%.0f/s", serverData.moneyPerSec)
    moneyLabel.Text = "$" .. moneyStr
    moneyLabel.TextColor3 = Color3.fromRGB(0, 200, 0)
    moneyLabel.TextSize = 16
    moneyLabel.Font = Enum.Font.GothamBold
    moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
    moneyLabel.Parent = card
    
    local playersLabel = Instance.new("TextLabel")
    playersLabel.Name = "Players"
    playersLabel.Size = UDim2.new(0.1, 0, 1, 0)
    playersLabel.Position = UDim2.new(0.55, 0, 0, 0)
    playersLabel.BackgroundTransparency = 1
    playersLabel.Text = string.format("%d/%d", serverData.players, serverData.maxPlayers)
    playersLabel.TextColor3 = Color3.fromRGB(0, 150, 255)
    playersLabel.TextSize = 16
    playersLabel.Font = Enum.Font.GothamBold
    playersLabel.TextXAlignment = Enum.TextXAlignment.Left
    playersLabel.Parent = card
    
    local joinButton = Instance.new("TextButton")
    joinButton.Name = "Join"
    joinButton.Size = UDim2.new(0.15, 0, 0.7, 0)
    joinButton.Position = UDim2.new(0.8, 0, 0.15, 0)
    joinButton.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
    joinButton.BorderSizePixel = 0
    joinButton.Text = "JOIN"
    joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    joinButton.TextSize = 16
    joinButton.Font = Enum.Font.GothamBold
    joinButton.Parent = card
    
    local newBadge = Instance.new("TextLabel")
    newBadge.Name = "NewBadge"
    newBadge.Size = UDim2.new(0.12, 0, 0.5, 0)
    newBadge.Position = UDim2.new(0.65, 0, 0.25, 0)
    newBadge.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    newBadge.BackgroundTransparency = 0.2
    newBadge.BorderSizePixel = 0
    newBadge.Text = "NEW"
    newBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
    newBadge.TextSize = 12
    newBadge.Font = Enum.Font.GothamBold
    newBadge.Visible = false
    newBadge.Parent = card
    
    joinButton.MouseButton1Click:Connect(function()
        joinServer(serverData.jobId)
    end)
    
    return card
end

-- Network Functions
local function fetchServers()
    local success, response = pcall(function()
        -- Use HttpGet with headers
        local headers = {
            ["Authorization"] = "Bearer " .. CONFIG.API_KEY
        }
        return game:HttpGet(CONFIG.API_ENDPOINT, false, headers)
    end)
    
    if not success or not response then
        return nil, "Network error"
    end
    
    local lines = {}
    for line in response:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    
    return lines, nil
end

-- Filtering & Sorting
local function passesFilters(serverData)
    -- Money filter
    if state.config.moneyFilter > 0 then
        local filterValue = normalizeMoney(tostring(state.config.moneyFilter))
        if serverData.moneyPerSec < filterValue then
            return false
        end
    end
    
    -- Whitelist (priority)
    if #state.config.whitelist > 0 then
        local found = false
        for _, name in ipairs(state.config.whitelist) do
            if serverData.name:lower():find(name:lower(), 1, true) then
                found = true
                break
            end
        end
        if not found then return false end
    else
        -- Blacklist (only if whitelist is empty)
        for _, name in ipairs(state.config.blacklist) do
            if serverData.name:lower():find(name:lower(), 1, true) then
                return false
            end
        end
    end
    
    return true
end

local function sortServers()
    local sorted = {}
    for jobId, server in pairs(state.servers) do
        table.insert(sorted, server)
    end
    
    table.sort(sorted, function(a, b)
        return a.moneyPerSec > b.moneyPerSec
    end)
    
    return sorted
end

-- Join Functions
local function joinServer(jobId)
    local server = state.servers[jobId]
    if not server then return end
    
    if server.players >= server.maxPlayers then
        -- Trigger retry
        if state.config.retryAmount > 0 then
            state.retryJobId = jobId
            state.retryAttempts = 0
            state.retryActive = true
            print("Server full, starting retry...")
        else
            warn("Server is full!")
        end
        return
    end
    
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            CONFIG.PLACE_ID,
            jobId,
            LocalPlayer
        )
    end)
    
    if success then
        state.currentJobId = jobId
        if state.config.autoJoin then
            state.config.autoJoin = false
            saveConfig()
        end
        print("Joining server:", server.name)
    else
        warn("Failed to join:", err)
        -- Retry on failure if enabled
        if state.config.retryAmount > 0 and not state.retryActive then
            state.retryJobId = jobId
            state.retryAttempts = 0
            state.retryActive = true
        end
    end
end

-- Auto Join Logic
local function tryAutoJoin()
    if not state.config.autoJoin then return end
    
    -- Don't auto join if already retrying
    if state.retryActive then return end
    
    local sorted = sortServers()
    local newestSuitable = nil
    local currentTime = tick()
    
    for _, server in ipairs(sorted) do
        if passesFilters(server) then
            local age = currentTime - (server.orderTime or server.timestamp)
            if age < CONFIG.NEW_BADGE_DURATION then
                newestSuitable = server
                break
            end
            if not newestSuitable then
                newestSuitable = server
            end
        end
    end
    
    if newestSuitable then
        joinServer(newestSuitable.jobId)
    end
end

-- Join Retry Logic
local function processRetry()
    if not state.retryActive or not state.retryJobId then return end
    
    if state.config.retryAmount <= 0 then
        state.retryActive = false
        state.retryJobId = nil
        return
    end
    
    if state.retryAttempts >= state.config.retryAmount then
        state.retryActive = false
        state.retryJobId = nil
        print("Retry limit reached")
        return
    end
    
    state.retryAttempts = state.retryAttempts + 1
    print(string.format("Join retry %d/%d", state.retryAttempts, state.config.retryAmount))
    
    local server = state.servers[state.retryJobId]
    if server then
        if server.players < server.maxPlayers then
            joinServer(state.retryJobId)
            state.retryActive = false
            state.retryJobId = nil
        end
    else
        -- Server no longer exists, stop retry
        state.retryActive = false
        state.retryJobId = nil
    end
end

-- Auto Inject Logic
local function checkAutoInject()
    if not state.config.autoInject then return end
    
    local currentPlaceId = game.PlaceId
    if currentPlaceId == CONFIG.PLACE_ID then
        -- Check if we just joined
        if state.currentJobId then
            -- We're in the target place, inject script
            local success, scriptContent = pcall(function()
                return game:HttpGet(CONFIG.INJECT_URL)
            end)
            
            if success and scriptContent then
                local success2, err = pcall(function()
                    loadstring(scriptContent)()
                end)
                
                if success2 then
                    print("Auto-injected script successfully")
                else
                    warn("Failed to execute injected script:", err)
                end
            else
                warn("Failed to fetch injection script")
            end
            
            state.currentJobId = nil -- Reset to avoid re-injecting
        end
    end
end

-- UI Update Functions
local function updateServerList(rightPanel)
    local sorted = sortServers()
    local currentTime = tick()
    
    -- Track existing cards
    local existingCards = {}
    for _, child in ipairs(rightPanel:GetChildren()) do
        if child:IsA("Frame") and child.Name ~= "UIListLayout" then
            existingCards[child.Name] = child
        end
    end
    
    -- Update or create cards
    for i, server in ipairs(sorted) do
        local card = existingCards[server.jobId]
        
        if not card then
            -- Create new card
            server.ui = createServerCard(server, i)
            server.ui.Parent = rightPanel
            server.orderTime = currentTime
            card = server.ui
        else
            -- Reuse existing card
            server.ui = card
            card.LayoutOrder = i
            card.Parent = rightPanel
        end
        
        -- Update card content
        local nameLabel = card:FindFirstChild("Name")
        if nameLabel then
            nameLabel.Text = server.name
        end
        
        local moneyLabel = card:FindFirstChild("Money")
        if moneyLabel then
            local moneyStr = server.moneyPerSec >= 1000000000 and string.format("%.1fb/s", server.moneyPerSec / 1000000000)
                or server.moneyPerSec >= 1000000 and string.format("%.1fm/s", server.moneyPerSec / 1000000)
                or server.moneyPerSec >= 1000 and string.format("%.1fk/s", server.moneyPerSec / 1000)
                or string.format("%.0f/s", server.moneyPerSec)
            moneyLabel.Text = "$" .. moneyStr
        end
        
        local playersLabel = card:FindFirstChild("Players")
        if playersLabel then
            playersLabel.Text = string.format("%d/%d", server.players, server.maxPlayers)
        end
        
        -- Update NEW badge
        local newBadge = card:FindFirstChild("NewBadge")
        if newBadge then
            local age = currentTime - (server.orderTime or server.timestamp)
            newBadge.Visible = age < CONFIG.NEW_BADGE_DURATION
        end
    end
    
    -- Remove cards for servers that no longer exist
    for jobId, card in pairs(existingCards) do
        if not state.servers[jobId] then
            card:Destroy()
        end
    end
    
    -- Update canvas size
    rightPanel.CanvasSize = UDim2.new(0, 0, 0, #sorted * 68)
end

local function updateServers()
    local lines, err = fetchServers()
    
    if not lines then
        state.networkError = true
        return
    end
    
    state.networkError = false
    local currentTime = tick()
    local newServers = {}
    
    for _, line in ipairs(lines) do
        local serverData = parseServerLine(line)
        if serverData then
            local jobId = serverData.jobId
            
            if state.servers[jobId] then
                -- Update existing
                state.servers[jobId].name = serverData.name
                state.servers[jobId].moneyPerSec = serverData.moneyPerSec
                state.servers[jobId].players = serverData.players
                state.servers[jobId].maxPlayers = serverData.maxPlayers
                state.servers[jobId].timestamp = serverData.timestamp
            else
                -- New server
                state.orderCounter = state.orderCounter + 1
                state.servers[jobId] = {
                    name = serverData.name,
                    moneyPerSec = serverData.moneyPerSec,
                    players = serverData.players,
                    maxPlayers = serverData.maxPlayers,
                    jobId = jobId,
                    timestamp = serverData.timestamp,
                    order = state.orderCounter,
                    orderTime = currentTime,
                    ui = nil
                }
                newServers[jobId] = true
            end
        end
    end
    
    -- Remove expired servers (TTL)
    for jobId, server in pairs(state.servers) do
        local age = currentTime - server.timestamp
        if age > CONFIG.TTL then
            if server.ui then
                server.ui:Destroy()
            end
            state.servers[jobId] = nil
        end
    end
    
    -- Trigger auto join for new servers
    if state.config.autoJoin then
        for jobId, _ in pairs(newServers) do
            if passesFilters(state.servers[jobId]) then
                tryAutoJoin()
                break
            end
        end
    end
end

-- Main Loop
local function main()
    -- Load config
    loadConfig()
    
    -- Create UI
    local screenGui, leftPanel, rightPanel, errorBanner = createUI()
    state.screenGui = screenGui
    
    -- Toggle UI visibility with K key
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == Enum.KeyCode.K then
            state.uiVisible = not state.uiVisible
            if screenGui then
                screenGui.Enabled = state.uiVisible
            end
        end
    end)
    
    -- Retry timer
    local lastRetryTime = 0
    
    -- Main update loop
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local currentTime = tick()
        local deltaTime = tick() - state.lastFrameTime
        state.lastFrameTime = currentTime
        
        -- Throttle based on frame time
        if deltaTime > CONFIG.MAX_FRAME_TIME then
            wait(0.05) -- Slow down if FPS drops
        end
        
        -- Only update UI if visible
        if state.uiVisible then
            -- Poll servers
            if currentTime - state.lastPollTime >= CONFIG.POLL_RATE then
                state.lastPollTime = currentTime
                updateServers()
                updateServerList(rightPanel)
            end
            
            -- Update error banner
            errorBanner.Visible = state.networkError
        else
            -- Still poll servers in background (but don't update UI)
            if currentTime - state.lastPollTime >= CONFIG.POLL_RATE then
                state.lastPollTime = currentTime
                updateServers()
            end
        end
        
        -- Process retry (every 100ms)
        if currentTime - lastRetryTime >= CONFIG.RETRY_RATE then
            lastRetryTime = currentTime
            processRetry()
        end
        
        -- Check auto inject
        checkAutoInject()
    end)
    
    -- Initial update
    updateServers()
    if state.uiVisible then
        updateServerList(rightPanel)
    end
end

-- Start
main()
 
