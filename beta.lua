-- Zamorozka Auto Joiner
-- Roblox Lua Script with Winter-themed UI

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Configuration
local CONFIG = {
    API_ENDPOINT = "https://server-eta-two-29.vercel.app",
    API_KEY = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja",
    PLACE_ID = 109983668079237,
    SCRIPT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua",
    POLL_RATE = 0.1, -- 10 Hz (100ms)
    TTL = 180, -- seconds
    NEW_BADGE_TIME = 5, -- seconds
    JOIN_RETRY_RATE = 0.1, -- 10 attempts/sec
    KEYBIND = Enum.KeyCode.K
}

-- State
local state = {
    servers = {}, -- {jobId: serverData}
    serverOrder = {}, -- Array of jobIds in order of appearance
    config = {
        autoJoin = false,
        autoInject = false,
        moneyFilter = 0,
        retryAmount = 0,
        blacklist = {},
        whitelist = {}
    },
    guiVisible = true,
    lastPollTime = 0,
    retryAttempts = 0,
    retryTargetJobId = nil,
    retryConnection = nil,
    frameTimeHistory = {},
    lastFrameTime = tick()
}

-- Utility Functions
local function normalizeMoney(moneyStr)
    if not moneyStr then return 0 end
    moneyStr = moneyStr:gsub("$", ""):gsub("/s", ""):gsub(" ", ""):upper()
    
    local numStr = moneyStr:match("([%d%.]+)")
    if not numStr then return 0 end
    
    local num = tonumber(numStr)
    if not num then return 0 end
    
    if moneyStr:find("B") then
        return math.floor(num * 1_000_000_000)
    elseif moneyStr:find("M") then
        return math.floor(num * 1_000_000)
    elseif moneyStr:find("K") then
        return math.floor(num * 1_000)
    else
        return math.floor(num)
    end
end
    
local function formatMoney(money)
    if money >= 1_000_000_000 then
        return string.format("%.1fB/s", money / 1_000_000_000)
    elseif money >= 1_000_000 then
        return string.format("%.1fM/s", money / 1_000_000)
    elseif money >= 1_000 then
        return string.format("%.1fK/s", money / 1_000)
    else
        return string.format("%d/s", money)
    end
end

local function parseServerLine(line)
    -- Support both formats:
    -- "Name | $200K/s | 6/8 | jobId | timestamp"
    -- "Name | **$200K/s** | **6/8** | jobId | timestamp"
    
    line = line:gsub("%*%*", "") -- Remove bold markers
    local parts = {}
    for part in line:gmatch("([^|]+)") do
        table.insert(parts, part:match("^%s*(.-)%s*$")) -- Trim
    end
    
    if #parts < 5 then return nil end
    
    local name = parts[1]
    local moneyStr = parts[2]
    local playersStr = parts[3]
    local jobId = parts[4]
    local timestamp = parts[5]
    
    -- Parse money
    local moneyPerSec = normalizeMoney(moneyStr)
    
    -- Parse players
    local players, maxPlayers = playersStr:match("(%d+)/(%d+)")
    players = tonumber(players) or 0
    maxPlayers = tonumber(maxPlayers) or 0
    
    return {
        name = name,
        moneyPerSec = moneyPerSec,
        players = players,
        maxPlayers = maxPlayers,
        jobId = jobId,
        timestamp = timestamp,
        arrivalTime = tick()
    }
end

local function parseCSV(csvStr)
    if not csvStr or csvStr == "" then return {} end
    local result = {}
    for item in csvStr:gmatch("([^,]+)") do
        table.insert(result, item:match("^%s*(.-)%s*$"))
    end
    return result
end

local function saveConfig()
    local success, err = pcall(function()
        local json = HttpService:JSONEncode(state.config)
        -- Try executor filesystem functions
        if writefile then
            writefile("zamorozka_config.json", json)
        else
            -- Fallback: use ReplicatedStorage or save to a StringValue
            warn("writefile not available, config not saved to filesystem")
        end
    end)
    if not success then
        warn("Failed to save config:", err)
    end
end

local function loadConfig()
    local success, result = pcall(function()
        -- Try executor filesystem functions
        if isfile and readfile then
            if isfile("zamorozka_config.json") then
                local json = readfile("zamorozka_config.json")
                return HttpService:JSONDecode(json)
            end
        end
    end)
    if success and result then
        state.config = result
        -- Ensure arrays exist
        state.config.blacklist = state.config.blacklist or {}
        state.config.whitelist = state.config.whitelist or {}
        -- Ensure numbers are valid
        state.config.moneyFilter = state.config.moneyFilter or 0
        state.config.retryAmount = state.config.retryAmount or 0
    end
end

local function fetchServers()
    local success, response = pcall(function()
        -- Try game:HttpGet first (most executors support this)
        if game.HttpGet then
            local success1, result1 = pcall(function()
                return game:HttpGet(CONFIG.API_ENDPOINT, {
                    ["Authorization"] = "Bearer " .. CONFIG.API_KEY
                })
            end)
            if success1 and result1 then return result1 end
        end
        
        -- Try HttpService:GetAsync with headers
        local success2, result2 = pcall(function()
            return HttpService:GetAsync(CONFIG.API_ENDPOINT, true, {
                ["Authorization"] = "Bearer " .. CONFIG.API_KEY
        })
    end)
        if success2 and result2 then return result2 end
        
        -- Last resort: plain request
        return HttpService:GetAsync(CONFIG.API_ENDPOINT, true)
    end)
    
    if not success or not response then
        warn("Failed to fetch servers:", response)
        return {}
    end
    
    local servers = {}
    for line in response:gmatch("[^\r\n]+") do
        local server = parseServerLine(line)
        if server and server.jobId then
            table.insert(servers, server)
        end
    end
    
    return servers
end

local function shouldShowServer(server)
    -- Check TTL
    if tick() - server.arrivalTime > CONFIG.TTL then
        return false
    end
    
    -- Check money filter
    if state.config.moneyFilter > 0 and server.moneyPerSec < state.config.moneyFilter then
        return false
    end
    
    -- Whitelist priority
    if #state.config.whitelist > 0 then
        for _, name in ipairs(state.config.whitelist) do
            if server.name:lower():find(name:lower(), 1, true) then
                return true
            end
        end
        return false
    end
    
    -- Blacklist (only if whitelist is empty)
    for _, name in ipairs(state.config.blacklist) do
        if server.name:lower():find(name:lower(), 1, true) then
            return false
        end
    end
    
    return true
end

local function getFilteredServers()
    local filtered = {}
    for jobId, server in pairs(state.servers) do
        if shouldShowServer(server) then
            table.insert(filtered, server)
        end
    end
    
    -- Sort by moneyPerSec DESC
    table.sort(filtered, function(a, b)
        return a.moneyPerSec > b.moneyPerSec
    end)
    
    return filtered
end

local function joinServer(jobId)
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            CONFIG.PLACE_ID,
            jobId,
            LocalPlayer
        )
    end)
    
    if success then
        print("Successfully teleported to server:", jobId)
        if state.config.autoJoin then
            state.config.autoJoin = false
            saveConfig()
        end
        
        -- Auto inject after successful teleport
        if state.config.autoInject then
            spawn(function()
                wait(2) -- Wait a bit for teleport to process
                autoInjectLogic()
            end)
        end
        
        return true
    else
        warn("Failed to teleport:", err)
        return false
    end
end

local retryThread = nil
local function startJoinRetry(jobId)
    if state.config.retryAmount <= 0 then return end
    
    -- Stop existing retry if any
    if retryThread then
        state.retryTargetJobId = nil
        retryThread = nil
    end
    
    state.retryTargetJobId = jobId
    state.retryAttempts = 0
    
    -- Use spawn with wait to throttle at 10 attempts/sec
    retryThread = spawn(function()
        while state.retryTargetJobId == jobId and state.retryAttempts < state.config.retryAmount do
            state.retryAttempts = state.retryAttempts + 1
            print("Join retry", state.retryAttempts .. "/" .. state.config.retryAmount)
            
            if joinServer(jobId) then
                state.retryTargetJobId = nil
                retryThread = nil
                break
            end
            
            if state.retryAttempts >= state.config.retryAmount then
                state.retryTargetJobId = nil
                retryThread = nil
                break
            end
            
            wait(CONFIG.JOIN_RETRY_RATE)
        end
    end)
end

local autoJoinCooldown = 0
local function autoJoinLogic()
    if not state.config.autoJoin then return end
    
    -- Cooldown to prevent spam
    local now = tick()
    if now - autoJoinCooldown < 1 then return end
    autoJoinCooldown = now
    
    local filtered = getFilteredServers()
    if #filtered == 0 then return end
    
    -- Prefer newly appeared servers
    local candidates = {}
    for _, server in ipairs(filtered) do
        local age = tick() - server.arrivalTime
        if age < CONFIG.NEW_BADGE_TIME then
            table.insert(candidates, server)
        end
    end
    
    if #candidates == 0 then
        candidates = filtered
    end
    
    -- Try to join the best server (already sorted by moneyPerSec DESC)
    for _, server in ipairs(candidates) do
        if server.players < server.maxPlayers then
            if not joinServer(server.jobId) then
                -- If full or failed, start retry
                startJoinRetry(server.jobId)
            end
            return
        end
    end
    
    -- All servers are full, try retry on first one
    if #candidates > 0 then
        startJoinRetry(candidates[1].jobId)
    end
end

local function autoInjectLogic()
    if not state.config.autoInject then return end
    
    -- This would be called after successful join
    -- In practice, you'd reload the script from the URL
    local success, scriptContent = pcall(function()
        return game:HttpGet(CONFIG.SCRIPT_URL)
    end)
    
    if success then
        loadstring(scriptContent)()
    end
end

-- UI Creation
local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ZamorozkaAutoJoiner"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = CoreGui
    
    -- Main Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0.8, 0, 0.8, 0)
    mainFrame.Position = UDim2.new(0.1, 0, 0.1, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(240, 248, 255)
    mainFrame.BackgroundTransparency = 0.15
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Blur effect
    local blur = Instance.new("BlurEffect")
    blur.Size = 5
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
    title.Text = "Zamorozka Auto Joiner"
    title.TextColor3 = Color3.fromRGB(70, 130, 180)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = topBar
    
    -- Left Panel (Settings)
    local leftPanel = Instance.new("ScrollingFrame")
    leftPanel.Name = "LeftPanel"
    leftPanel.Size = UDim2.new(0.25, 0, 0.88, 0)
    leftPanel.Position = UDim2.new(0, 0, 0.12, 0)
    leftPanel.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
    leftPanel.BackgroundTransparency = 0.1
    leftPanel.BorderSizePixel = 0
    leftPanel.ScrollBarThickness = 6
    leftPanel.Parent = mainFrame
    
    local leftContent = Instance.new("Frame")
    leftContent.Name = "Content"
    leftContent.Size = UDim2.new(1, -20, 1, 0)
    leftContent.Position = UDim2.new(0, 10, 0, 0)
    leftContent.BackgroundTransparency = 1
    leftContent.Parent = leftPanel
    leftPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
    
    -- Right Panel (Server List)
    local rightPanel = Instance.new("ScrollingFrame")
    rightPanel.Name = "RightPanel"
    rightPanel.Size = UDim2.new(0.75, 0, 0.88, 0)
    rightPanel.Position = UDim2.new(0.25, 0, 0.12, 0)
    rightPanel.BackgroundColor3 = Color3.fromRGB(250, 250, 255)
    rightPanel.BackgroundTransparency = 0.2
    rightPanel.BorderSizePixel = 0
    rightPanel.ScrollBarThickness = 6
    rightPanel.Parent = mainFrame
    
    local rightContent = Instance.new("Frame")
    rightContent.Name = "Content"
    rightContent.Size = UDim2.new(1, -20, 1, 0)
    rightContent.Position = UDim2.new(0, 10, 0, 0)
    rightContent.BackgroundTransparency = 1
    rightContent.Parent = rightPanel
    rightPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
    
    -- UI Layout
    local uiLayout = Instance.new("UIListLayout")
    uiLayout.Padding = UDim.new(0, 10)
    uiLayout.SortOrder = Enum.SortOrder.LayoutOrder
    uiLayout.Parent = leftContent
    
    local function createToggle(name, value, callback)
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Name = name .. "Toggle"
        toggleFrame.Size = UDim2.new(1, 0, 0, 40)
        toggleFrame.BackgroundTransparency = 1
        toggleFrame.LayoutOrder = #leftContent:GetChildren()
        toggleFrame.Parent = leftContent
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name .. ":"
        label.TextColor3 = Color3.fromRGB(50, 50, 50)
        label.TextSize = 16
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.Parent = toggleFrame
        
        local toggleButton = Instance.new("TextButton")
        toggleButton.Size = UDim2.new(0.25, 0, 0.6, 0)
        toggleButton.Position = UDim2.new(0.7, 0, 0.2, 0)
        toggleButton.Text = value and "ON" or "OFF"
        toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggleButton.TextSize = 14
        toggleButton.Font = Enum.Font.GothamBold
        toggleButton.BackgroundColor3 = value and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(150, 150, 150)
        toggleButton.BorderSizePixel = 0
        toggleButton.Parent = toggleFrame
        
        toggleButton.MouseButton1Click:Connect(function()
            value = not value
            toggleButton.Text = value and "ON" or "OFF"
            toggleButton.BackgroundColor3 = value and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(150, 150, 150)
            callback(value)
        end)
        
        return toggleButton
    end
    
    local function createInput(name, value, callback)
        local inputFrame = Instance.new("Frame")
        inputFrame.Name = name .. "Input"
        inputFrame.Size = UDim2.new(1, 0, 0, 50)
        inputFrame.BackgroundTransparency = 1
        inputFrame.LayoutOrder = #leftContent:GetChildren()
        inputFrame.Parent = leftContent
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 20)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name .. ":"
        label.TextColor3 = Color3.fromRGB(50, 50, 50)
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.Parent = inputFrame
        
        local textBox = Instance.new("TextBox")
        textBox.Size = UDim2.new(1, 0, 0, 25)
        textBox.Position = UDim2.new(0, 0, 0, 25)
        textBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        textBox.BackgroundTransparency = 0.3
        textBox.BorderSizePixel = 1
        textBox.BorderColor3 = Color3.fromRGB(200, 200, 200)
        textBox.Text = tostring(value)
        textBox.TextColor3 = Color3.fromRGB(0, 0, 0)
        textBox.TextSize = 14
        textBox.Font = Enum.Font.Gotham
        textBox.ClearTextOnFocus = false
        textBox.Parent = inputFrame
        
        textBox.FocusLost:Connect(function()
            callback(textBox.Text)
        end)
        
        return textBox
    end
    
    -- Create UI elements
    local autoJoinToggle = createToggle("Auto Join", state.config.autoJoin, function(val)
        state.config.autoJoin = val
        saveConfig()
    end)
    
    local autoInjectToggle = createToggle("Auto Inject", state.config.autoInject, function(val)
        state.config.autoInject = val
        saveConfig()
    end)
    
    local moneyFilterInput = createInput("Money Filter (k/m/b)", state.config.moneyFilter, function(val)
        local num = normalizeMoney(val)
        state.config.moneyFilter = math.max(0, num)
        saveConfig()
    end)
    
    local retryAmountInput = createInput("Join Retry Amount", state.config.retryAmount, function(val)
        local num = tonumber(val) or 0
                if num < 0 then
                    num = 0
            warn("Retry amount cannot be negative, clamped to 0")
                end
        state.config.retryAmount = num
            saveConfig()
        end)
        
    local whitelistInput = createInput("Whitelist (CSV)", table.concat(state.config.whitelist, ","), function(val)
        state.config.whitelist = parseCSV(val)
        saveConfig()
    end)
    
    local blacklistInput = createInput("Blacklist (CSV)", table.concat(state.config.blacklist, ","), function(val)
        state.config.blacklist = parseCSV(val)
        saveConfig()
    end)
    
    -- Update left panel canvas size
    leftContent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        leftPanel.CanvasSize = UDim2.new(0, 0, 0, leftContent.AbsoluteSize.Y + 20)
    end)
    
    -- Server card creation function
    local function createServerCard(server)
    local card = Instance.new("Frame")
        card.Name = server.jobId
        card.Size = UDim2.new(1, -20, 0, 80)
    card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        card.BackgroundTransparency = 0.2
        card.BorderSizePixel = 1
        card.BorderColor3 = Color3.fromRGB(200, 200, 220)
        
        -- Name
    local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.Size = UDim2.new(0.4, 0, 0.5, 0)
        nameLabel.Position = UDim2.new(0.05, 0, 0.1, 0)
    nameLabel.BackgroundTransparency = 1
        nameLabel.Text = server.name
        nameLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
    nameLabel.TextSize = 18
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card
    
        -- Money (green)
    local moneyLabel = Instance.new("TextLabel")
        moneyLabel.Name = "MoneyLabel"
        moneyLabel.Size = UDim2.new(0.2, 0, 0.4, 0)
        moneyLabel.Position = UDim2.new(0.45, 0, 0.15, 0)
    moneyLabel.BackgroundTransparency = 1
        moneyLabel.Text = formatMoney(server.moneyPerSec)
        moneyLabel.TextColor3 = Color3.fromRGB(0, 150, 0)
        moneyLabel.TextSize = 16
        moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
    moneyLabel.Font = Enum.Font.GothamBold
        moneyLabel.Parent = card
        
        -- Players (blue)
    local playersLabel = Instance.new("TextLabel")
        playersLabel.Name = "PlayersLabel"
        playersLabel.Size = UDim2.new(0.15, 0, 0.4, 0)
        playersLabel.Position = UDim2.new(0.65, 0, 0.15, 0)
    playersLabel.BackgroundTransparency = 1
        playersLabel.Text = server.players .. "/" .. server.maxPlayers
        playersLabel.TextColor3 = Color3.fromRGB(0, 100, 200)
        playersLabel.TextSize = 16
        playersLabel.TextXAlignment = Enum.TextXAlignment.Left
    playersLabel.Font = Enum.Font.GothamBold
        playersLabel.Parent = card
        
        -- Join button
    local joinButton = Instance.new("TextButton")
        joinButton.Size = UDim2.new(0.1, 0, 0.6, 0)
        joinButton.Position = UDim2.new(0.85, 0, 0.2, 0)
        joinButton.Text = "Join"
    joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        joinButton.TextSize = 14
    joinButton.Font = Enum.Font.GothamBold
        joinButton.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
        joinButton.BorderSizePixel = 0
    joinButton.Parent = card
    
    joinButton.MouseButton1Click:Connect(function()
            joinServer(server.jobId)
        end)
        
        -- NEW badge
        local newBadge = Instance.new("TextLabel")
        newBadge.Name = "NewBadge"
        newBadge.Size = UDim2.new(0, 50, 0, 20)
        newBadge.Position = UDim2.new(0.05, 0, 0.6, 0)
        newBadge.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
        newBadge.BorderSizePixel = 0
        newBadge.Text = "NEW"
        newBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
        newBadge.TextSize = 12
        newBadge.Font = Enum.Font.GothamBold
        newBadge.Visible = false
        newBadge.Parent = card
    
    return card
end

    -- Create layout once
    local rightLayout = Instance.new("UIListLayout")
    rightLayout.Padding = UDim.new(0, 10)
    rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rightLayout.Parent = rightContent
    
    rightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        rightPanel.CanvasSize = UDim2.new(0, 0, 0, rightLayout.AbsoluteContentSize.Y + 20)
    end)
    
    -- Server card cache
    local cardCache = {}
    
    -- Update server list
    local function updateServerList()
        local filtered = getFilteredServers()
        local existingCards = {}
        
        -- Collect existing cards
        for _, child in ipairs(rightContent:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "Content" and cardCache[child.Name] then
                existingCards[child.Name] = child
        end
    end
    
        -- Remove cards that are no longer in filtered list
        for jobId, card in pairs(existingCards) do
        local found = false
            for _, server in ipairs(filtered) do
                if server.jobId == jobId then
                found = true
                break
            end
        end
            if not found then
                card:Destroy()
                cardCache[jobId] = nil
        end
    end
    
        -- Update or create cards
        for i, server in ipairs(filtered) do
            local card = existingCards[server.jobId]
            if card then
                -- Update existing card
                card.LayoutOrder = i
                local nameLabel = card:FindFirstChild("NameLabel")
                local moneyLabel = card:FindFirstChild("MoneyLabel")
                local playersLabel = card:FindFirstChild("PlayersLabel")
                local newBadge = card:FindFirstChild("NewBadge")
                
                if nameLabel then nameLabel.Text = server.name end
                if moneyLabel then moneyLabel.Text = formatMoney(server.moneyPerSec) end
                if playersLabel then playersLabel.Text = server.players .. "/" .. server.maxPlayers end
                
                -- Update NEW badge
                local age = tick() - server.arrivalTime
                if newBadge then
                    newBadge.Visible = age < CONFIG.NEW_BADGE_TIME
                end
            else
                -- Create new card
                card = createServerCard(server)
                card.LayoutOrder = i
                card.Parent = rightContent
                cardCache[server.jobId] = card
                
                -- Show NEW badge if recent
                local age = tick() - server.arrivalTime
                if age < CONFIG.NEW_BADGE_TIME then
                    local badge = card:FindFirstChild("NewBadge")
                    if badge then
                        badge.Visible = true
                    end
                end
        end
    end
end

    -- Cleanup old servers
    local function cleanupOldServers()
        local now = tick()
        for jobId, server in pairs(state.servers) do
            if now - server.arrivalTime > CONFIG.TTL then
                state.servers[jobId] = nil
                -- Remove from order
                for i, id in ipairs(state.serverOrder) do
                    if id == jobId then
                        table.remove(state.serverOrder, i)
                break
            end
            end
        end
    end
    end
    
    -- Polling loop
    local lastPoll = 0
    RunService.Heartbeat:Connect(function()
        local now = tick()
        local deltaTime = now - lastPoll
        
        -- Throttle based on frame time
        local frameTime = tick() - state.lastFrameTime
        state.lastFrameTime = tick()
        table.insert(state.frameTimeHistory, frameTime)
        if #state.frameTimeHistory > 10 then
            table.remove(state.frameTimeHistory, 1)
        end
        
        local avgFrameTime = 0
        for _, ft in ipairs(state.frameTimeHistory) do
            avgFrameTime = avgFrameTime + ft
        end
        avgFrameTime = avgFrameTime / #state.frameTimeHistory
        
        -- Adjust poll rate if FPS drops
        local targetPollRate = CONFIG.POLL_RATE
        if avgFrameTime > 0.02 then -- If frame time > 20ms (50 FPS)
            targetPollRate = targetPollRate * 1.5 -- Slow down
        end
        
        if deltaTime >= targetPollRate then
            lastPoll = now
            
            -- Fetch servers
            local newServers = fetchServers()
            local hasNew = false
            
            for _, server in ipairs(newServers) do
                if not state.servers[server.jobId] then
                    state.servers[server.jobId] = server
                    table.insert(state.serverOrder, server.jobId)
                    hasNew = true
                else
                    -- Update existing
                    state.servers[server.jobId] = server
                end
            end
            
            cleanupOldServers()
            updateServerList()
            
            -- Auto join check (throttled, only on new servers)
            if hasNew and state.config.autoJoin then
                autoJoinLogic()
            end
        end
    end)
    
    -- Keybind toggle
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == CONFIG.KEYBIND then
            state.guiVisible = not state.guiVisible
            screenGui.Enabled = state.guiVisible
        end
    end)
    
    return screenGui
end

-- Initialize
loadConfig()
local ui = createUI()

print("Zamorozka Auto Joiner loaded! Press K to toggle GUI.")
