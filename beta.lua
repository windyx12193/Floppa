--[[
    Zamorozka Auto Joiner
    Frost-themed Roblox auto joiner with filtering, retry logic, and persistent configuration.
]]
-- // Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
-- // Constants
local PLACE_ID = 109983668079237
local API_ENDPOINT = "https://server-eta-two-29.vercel.app"
local API_KEY = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"
local CONFIG_PATH = "zamorozka_auto_joiner.json"
local SCRIPT_NAME = "ZamorozkaAutoJoiner"
local JOB_TTL = 180 -- seconds
local NEW_BADGE_DURATION = 5
local BASE_POLL_INTERVAL = 0.15 -- ~6.6 Hz
local MIN_POLL_INTERVAL = 0.1
local MAX_POLL_INTERVAL = 0.5
local ERROR_INTERVALS = {0.2, 0.5, 1.0}
local RETRY_DELAY = 0.1 -- 10 attempts per second
local GUI_HOTKEY = Enum.KeyCode.K

-- // Feature flags
local hasFS = typeof(isfile) == "function" and typeof(readfile) == "function" and typeof(writefile) == "function"
local requestImpl = (typeof(http_request) == "function" and http_request)
    or (syn and syn.request)
    or (typeof(request) == "function" and request)
    or (http and typeof(http.request) == "function" and http.request)

-- // Runtime state
local LocalPlayer = Players.LocalPlayer
local GuiParent
local ScreenGui
local MainFrame
local ErrorBanner
local ServerList
local MoneyFilterBox
local RetryAmountBox
local WhitelistBox
local BlacklistBox
local AutoJoinToggle
local AutoInjectToggle
local ToggleStatus = {AutoJoin = false, AutoInject = false}
local Config = {
    autoJoin = false,
    autoInject = false,
    moneyFilter = 0,
    retryAmount = 0,
    blacklist = {},
    whitelist = {},
}
local AverageFrameTime = 1 / 60
local PollInterval = BASE_POLL_INTERVAL
local ErrorIntervalIndex = 1
local Servers = {}
local ServerOrder = 0
local NeedsRefresh = false
local RetryActive = false
local JoinBusy = false
local LastAutoJob
local LastAutoAttempt = 0
local BannerToken = 0

if not LocalPlayer then
    repeat
        task.wait()
        LocalPlayer = Players.LocalPlayer
    until LocalPlayer
end

-- Card pooling
local CardPool = {}
local ActiveCards = {}
local CardRefs = {}

-- Utility: safe pcall wrapper for spawn
local function defer(fn, ...)
    local args = table.pack(...)
    task.spawn(function()
        pcall(function()
            fn(table.unpack(args, 1, args.n))
        end)
    end)
end

-- // Utility helpers
local function trim(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseCSV(str)
    local results = {}
    if type(str) ~= "string" then
        return results
    end
    for token in str:gmatch("[^,]+") do
        local item = trim(token)
        if item ~= "" then
            table.insert(results, item)
        end
    end
    return results
end

local multipliers = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
}

local function parseMoney(value)
    if type(value) ~= "string" then return nil end
    local clean = value:lower()
    clean = clean:gsub("%$", "")
    clean = clean:gsub("/s", "")
    clean = clean:gsub(",", "")
    clean = clean:gsub("%s+", "")
    local number, suffix = clean:match("([%d%.]+)([kmb]?)")
    local num = tonumber(number)
    if not num then return nil end
    local mult = suffix ~= "" and multipliers[suffix] or 1
    return math.floor(num * mult + 0.5)
end

local function formatMoney(value)
    if not value then
        return "0/s"
    end

    local formatted
    if value >= 1e9 then
        formatted = string.format("%.1fb/s", value / 1e9)
    elseif value >= 1e6 then
        formatted = string.format("%.1fm/s", value / 1e6)
    elseif value >= 1e3 then
        formatted = string.format("%.1fk/s", value / 1e3)
    else
        formatted = string.format("%d/s", value)
    end

    formatted = formatted:gsub("%.0([kmb]/s)", "%1")
    return formatted
end

local function parseTimestamp(ts)
    if type(ts) ~= "string" then
        return nil
    end
    local day, month, year, hour, min, sec = ts:match("(%d+)%.(%d+)%.(%d+),%s*(%d+):(%d+):(%d+)")
    if not day then
        return nil
    end
    local success, epoch = pcall(os.time, {
        day = tonumber(day),
        month = tonumber(month),
        year = tonumber(year),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })
    if success then
        return epoch
    end
    return nil
end

local function getGuiContainer()
    local parent
    local success, gui = pcall(function()
        return gethui and gethui()
    end)
    if success and gui then
        parent = gui
    end
    if not parent then
        local ok, core = pcall(function()
            return game:GetService("CoreGui")
        end)
        if ok and core then
            parent = core
        end
    end
    if not parent and LocalPlayer then
        parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end
    return parent
end

local function saveConfig()
    if not hasFS then
        return
    end
    local data = HttpService:JSONEncode(Config)
    defer(writefile, CONFIG_PATH, data)
end

local function loadConfig()
    if not hasFS or not isfile(CONFIG_PATH) then
        return
    end
    local ok, data = pcall(readfile, CONFIG_PATH)
    if not ok or type(data) ~= "string" then
        return
    end
    local success, decoded = pcall(function()
        return HttpService:JSONDecode(data)
    end)
    if success and type(decoded) == "table" then
        for key, value in pairs(decoded) do
            if Config[key] ~= nil then
                Config[key] = value
            end
        end
        Config.autoJoin = decoded.autoJoin and true or false
        Config.autoInject = decoded.autoInject and true or false
        Config.moneyFilter = math.max(0, tonumber(decoded.moneyFilter) or 0)
        local retry = tonumber(decoded.retryAmount) or 0
        Config.retryAmount = math.max(0, math.floor(retry + 0.5))
        Config.whitelist = type(decoded.whitelist) == "table" and decoded.whitelist or {}
        Config.blacklist = type(decoded.blacklist) == "table" and decoded.blacklist or {}
    end
end

local function queueTeleportScript()
    if not Config.autoInject then
        return
    end
    local queue = (syn and syn.queue_on_teleport)
        or queue_on_teleport
        or (fluxus and fluxus.queue_on_teleport)
        or (jjsploit and jjsploit.queue_on_teleport)
    if queue then
        local command = string.format("loadstring(game:HttpGet('%s'))()", AUTO_INJECT_URL)
        defer(queue, command)
    end
end

local function setAutoJoin(value, skipSave)
    Config.autoJoin = value and true or false
    ToggleStatus.AutoJoin = Config.autoJoin
    if AutoJoinToggle then
        AutoJoinToggle(Config.autoJoin)
    end
    if not Config.autoJoin then
        RetryActive = false
        LastAutoJob = nil
        LastAutoAttempt = 0
    end
    if not skipSave then
        saveConfig()
    end
end

local function setAutoInject(value, skipSave)
    Config.autoInject = value and true or false
    ToggleStatus.AutoInject = Config.autoInject
    if AutoInjectToggle then
        AutoInjectToggle(Config.autoInject)
    end
    if not skipSave then
        saveConfig()
    end
end

local function showBanner(message)
    if not ErrorBanner then
        return
    end
    BannerToken += 1
    local token = BannerToken
    local holder = ErrorBanner.Parent
    ErrorBanner.Text = message
    ErrorBanner.Visible = true
    ErrorBanner.TextTransparency = 1
    if holder then
        holder.BackgroundTransparency = 0.4
    end
    TweenService:Create(ErrorBanner, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        TextTransparency = 0
    }):Play()
    task.delay(3, function()
        if token ~= BannerToken then
            return
        end
        if not ErrorBanner then
            return
        end
        local tween = TweenService:Create(ErrorBanner, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
            TextTransparency = 1
        })
        tween.Completed:Connect(function()
            if ErrorBanner and token == BannerToken then
                ErrorBanner.Visible = false
                if holder then
                    holder.BackgroundTransparency = 1
                end
            end
        end)
        tween:Play()
    end)
end

local function scheduleRefresh()
    NeedsRefresh = true
end

local function releaseCard(entry)
    if entry.card then
        local card = entry.card
        entry.card = nil
        ActiveCards[card] = nil
        defer(function()
            local tween = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
                BackgroundTransparency = 1,
            })
            tween:Play()
            tween.Completed:Wait()
            local refs = CardRefs[card]
            if refs then
                refs.NewBadge.Visible = false
            end
            card:SetAttribute("JobId", nil)
            card.Visible = false
            card.Parent = nil
            CardPool[#CardPool + 1] = card
        end)
    end
end

local function removeServer(jobId)
    local entry = Servers[jobId]
    if not entry then
        return
    end
    releaseCard(entry)
    Servers[jobId] = nil
    scheduleRefresh()
end

local function acquireCard()
    if #CardPool > 0 then
        local card = table.remove(CardPool)
        card.Visible = true
        card.BackgroundTransparency = 1
        TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.15,
        }):Play()
        return card
    end

    local card = Instance.new("Frame")
    card.Name = "ServerCard"
    card.Size = UDim2.new(1, -12, 0, 70)
    card.BackgroundColor3 = Color3.fromRGB(240, 244, 255)
    card.BackgroundTransparency = 0.15
    card.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(200, 210, 230)
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = card

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.Parent = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(0.45, 0, 0.5, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 20
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextColor3 = Color3.fromRGB(35, 45, 60)
    nameLabel.Text = ""
    nameLabel.Parent = card

    local moneyLabel = Instance.new("TextLabel")
    moneyLabel.Name = "MoneyLabel"
    moneyLabel.BackgroundTransparency = 1
    moneyLabel.Size = UDim2.new(0.25, 0, 0.5, 0)
    moneyLabel.Position = UDim2.new(0.46, 0, 0, 0)
    moneyLabel.Font = Enum.Font.GothamBold
    moneyLabel.TextSize = 18
    moneyLabel.TextColor3 = Color3.fromRGB(56, 160, 96)
    moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
    moneyLabel.Text = ""
    moneyLabel.Parent = card

    local playersLabel = Instance.new("TextLabel")
    playersLabel.Name = "PlayersLabel"
    playersLabel.BackgroundTransparency = 1
    playersLabel.Size = UDim2.new(0.2, 0, 0.5, 0)
    playersLabel.Position = UDim2.new(0.46, 0, 0.5, 0)
    playersLabel.Font = Enum.Font.Gotham
    playersLabel.TextSize = 17
    playersLabel.TextColor3 = Color3.fromRGB(64, 120, 200)
    playersLabel.TextXAlignment = Enum.TextXAlignment.Left
    playersLabel.Text = ""
    playersLabel.Parent = card

    local newBadge = Instance.new("TextLabel")
    newBadge.Name = "NewBadge"
    newBadge.BackgroundColor3 = Color3.fromRGB(180, 225, 255)
    newBadge.BackgroundTransparency = 0.05
    newBadge.Size = UDim2.new(0, 60, 0, 24)
    newBadge.Position = UDim2.new(0, 0, 1, -24)
    newBadge.Text = "NEW"
    newBadge.TextColor3 = Color3.fromRGB(20, 90, 180)
    newBadge.TextScaled = true
    newBadge.Visible = false
    newBadge.Font = Enum.Font.GothamSemibold
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0)
    badgeCorner.Parent = newBadge
    newBadge.Parent = card

    local joinButton = Instance.new("TextButton")
    joinButton.Name = "Join"
    joinButton.Size = UDim2.new(0, 110, 0, 36)
    joinButton.AnchorPoint = Vector2.new(1, 0.5)
    joinButton.Position = UDim2.new(1, -6, 0.5, 0)
    joinButton.BackgroundColor3 = Color3.fromRGB(180, 235, 200)
    joinButton.TextColor3 = Color3.fromRGB(40, 100, 60)
    joinButton.Font = Enum.Font.GothamBold
    joinButton.TextSize = 18
    joinButton.Text = "Join"
    joinButton.AutoButtonColor = false
    local joinCorner = Instance.new("UICorner")
    joinCorner.CornerRadius = UDim.new(0, 10)
    joinCorner.Parent = joinButton
    joinButton.Parent = card

    local joinStroke = Instance.new("UIStroke")
    joinStroke.Color = Color3.fromRGB(120, 200, 140)
    joinStroke.Thickness = 1
    joinStroke.Parent = joinButton

    joinButton.MouseButton1Click:Connect(function()
        local jobId = card:GetAttribute("JobId")
        if not jobId then
            return
        end
        queueTeleportScript()
        defer(function()
            JoinBusy = true
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LocalPlayer)
            end)
            JoinBusy = false
            if not ok and err then
                showBanner("Teleport failed: " .. tostring(err))
            end
        end)
    end)

    CardRefs[card] = {
        NameLabel = nameLabel,
        MoneyLabel = moneyLabel,
        PlayersLabel = playersLabel,
        NewBadge = newBadge,
    }

    return card
end

local function filterPasses(entry)
    if not entry then
        return false
    end
    if Config.moneyFilter and Config.moneyFilter > 0 and entry.money < Config.moneyFilter then
        return false
    end

    local whitelist = Config.whitelist or {}
    local blacklist = Config.blacklist or {}
    local nameLower = entry.nameLower

    if #whitelist > 0 then
        for _, allowed in ipairs(whitelist) do
            if nameLower == allowed:lower() then
                return true
            end
        end
        return false
    end

    for _, blocked in ipairs(blacklist) do
        if nameLower == blocked:lower() then
            return false
        end
    end

    return true
end

local function updateServerCards()
    if not ServerList then
        return
    end

    local now = os.clock()
    local filtered = {}
    for _, entry in pairs(Servers) do
        entry.displayed = false
        if filterPasses(entry) then
            table.insert(filtered, entry)
        end
    end

    table.sort(filtered, function(a, b)
        if a.money == b.money then
            return a.order < b.order
        end
        return a.money > b.money
    end)

    local index = 0
    for _, entry in ipairs(filtered) do
        index += 1
        entry.displayed = true
        local card = entry.card
        if not card then
            card = acquireCard()
            card.Parent = ServerList
            entry.card = card
        end
        ActiveCards[card] = entry
        card.LayoutOrder = index
        card:SetAttribute("JobId", entry.jobId)
        local refs = CardRefs[card]
        local isNew = now < entry.firstSeen + NEW_BADGE_DURATION
        if refs then
            refs.NewBadge.Visible = isNew
            refs.NameLabel.Text = entry.name
            refs.MoneyLabel.Text = "$" .. entry.displayMoney
            refs.PlayersLabel.Text = string.format("%d/%d", entry.players, entry.maxPlayers)
        end
        if entry._isNewState ~= isNew then
            entry._isNewState = isNew
            local targetColor = isNew and Color3.fromRGB(235, 245, 255) or Color3.fromRGB(240, 244, 255)
            TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
                BackgroundColor3 = targetColor
            }):Play()
        end
    end

    for jobId, entry in pairs(Servers) do
        if not entry.displayed and entry.card then
            releaseCard(entry)
        end
    end
end

local function considerAutoJoin()
    if not Config.autoJoin or JoinBusy or RetryActive then
        return
    end

    local now = os.clock()
    local candidatesNew = {}
    local candidatesExisting = {}

    for _, entry in pairs(Servers) do
        if filterPasses(entry) then
            if now - entry.firstSeen <= NEW_BADGE_DURATION then
                table.insert(candidatesNew, entry)
            else
                table.insert(candidatesExisting, entry)
            end
        end
    end

    local function sorter(a, b)
        if a.money == b.money then
            return a.order < b.order
        end
        return a.money > b.money
    end

    table.sort(candidatesNew, sorter)
    table.sort(candidatesExisting, sorter)

    local candidate = candidatesNew[1] or candidatesExisting[1]
    if not candidate then
        return
    end

    if LastAutoJob == candidate.jobId and (now - LastAutoAttempt) < 5 then
        return
    end

    local function attemptTeleport()
        queueTeleportScript()
        JoinBusy = true
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, candidate.jobId, LocalPlayer)
        end)
        JoinBusy = false
        if ok then
            setAutoJoin(false)
            RetryActive = false
            return true
        else
            if err then
                showBanner("Teleport failed: " .. tostring(err))
            end
            return false
        end
    end

    LastAutoJob = candidate.jobId
    LastAutoAttempt = now

    if candidate.players >= candidate.maxPlayers and Config.retryAmount and Config.retryAmount > 0 then
        RetryActive = true
        defer(function()
            for attempt = 1, Config.retryAmount do
                if not RetryActive then
                    break
                end
                print(string.format("join retry %d/%d", attempt, Config.retryAmount))
                queueTeleportScript()
                local ok, err = pcall(function()
                    TeleportService:TeleportToPlaceInstance(PLACE_ID, candidate.jobId, LocalPlayer)
                end)
                if ok then
                    setAutoJoin(false)
                    RetryActive = false
                    return
                else
                    if err then
                        showBanner("Retry failed: " .. tostring(err))
                    end
                end
                task.wait(RETRY_DELAY)
            end
            RetryActive = false
        end)
    else
        if attemptTeleport() then
            return
        end
        if Config.retryAmount and Config.retryAmount > 0 then
            RetryActive = true
            defer(function()
                for attempt = 1, Config.retryAmount do
                    if not RetryActive then
                        break
                    end
                    print(string.format("join retry %d/%d", attempt, Config.retryAmount))
                    queueTeleportScript()
                    local ok, err = pcall(function()
                        TeleportService:TeleportToPlaceInstance(PLACE_ID, candidate.jobId, LocalPlayer)
                    end)
                    if ok then
                        setAutoJoin(false)
                        RetryActive = false
                        return
                    else
                        if err then
                            showBanner("Retry failed: " .. tostring(err))
                        end
                    end
                    task.wait(RETRY_DELAY)
                end
                RetryActive = false
            end)
        end
    end
end

local function processLine(line)
    line = trim(line)
    if line == "" then
        return
    end

    line = line:gsub("%*%*", "")
    local name, moneyPart, playersStr, maxPlayersStr, jobId, timestampStr = line:match("^(.-)%s*|%s*%$?([^|]+)%s*|%s*(%d+)%s*/%s*(%d+)%s*|%s*([0-9a-fA-F%-]+)%s*|%s*(%d+%.%d+%.%d+,%s*%d+:%d+:%d+)")
    if not name then
        return
    end

    local money = parseMoney(moneyPart)
    local players = tonumber(playersStr)
    local maxPlayers = tonumber(maxPlayersStr)
    if not (money and players and maxPlayers and jobId) then
        return
    end

    local timestampEpoch = parseTimestamp(timestampStr)
    local now = os.clock()

    local entry = Servers[jobId]
    if entry then
        entry.name = trim(name)
        entry.nameLower = entry.name:lower()
        entry.money = money
        entry.displayMoney = trim(moneyPart):gsub("%s+", ""):lower()
        entry.players = players
        entry.maxPlayers = maxPlayers
        entry.timestampEpoch = timestampEpoch
        entry.lastUpdate = now
    else
        ServerOrder += 1
        entry = {
            jobId = jobId,
            name = trim(name),
            nameLower = trim(name):lower(),
            money = money,
            displayMoney = trim(moneyPart):gsub("%s+", ""):lower(),
            players = players,
            maxPlayers = maxPlayers,
            timestampEpoch = timestampEpoch,
            firstSeen = now,
            lastUpdate = now,
            order = ServerOrder,
        }
        Servers[jobId] = entry
    end
end

local function parseResponse(body)
    if type(body) ~= "string" then
        return
    end
    body = body:gsub("\r", "")
    body = body:gsub("%*%*", "")
    body = body:gsub("(%d+%.%d+%.%d+,%s*%d+:%d+:%d+)%s+", "%1\n")

    for line in body:gmatch("[^\n]+") do
        processLine(line)
    end

    scheduleRefresh()
    considerAutoJoin()
end

local function cleanupLoop()
    while task.wait(1) do
        local now = os.clock()
        for jobId, entry in pairs(Servers) do
            local ttlElapsed = now - entry.lastUpdate
            local serverTTL
            if entry.timestampEpoch then
                serverTTL = os.time() - entry.timestampEpoch
            end
            if ttlElapsed > JOB_TTL or (serverTTL and serverTTL > JOB_TTL) then
                removeServer(jobId)
            end
        end
    end
end

local function pollLoop()
    while true do
        local waitTime = math.max(PollInterval, ERROR_INTERVALS[ErrorIntervalIndex] or PollInterval)
        task.wait(waitTime)

        local start = os.clock()
        local ok, response = pcall(function()
            if requestImpl then
                local headers = {
                    ["Content-Type"] = "application/json",
                    ["x-api-key"] = API_KEY,
                }
                local result = requestImpl({
                    Url = API_ENDPOINT,
                    Method = "GET",
                    Headers = headers,
                })
                if not result then
                    error("No response")
                end
                return result.Body or result.body
            else
                local url = string.format("%s?key=%s", API_ENDPOINT, API_KEY)
                return HttpService:GetAsync(url)
            end
        end)

        if ok and type(response) == "string" then
            ErrorIntervalIndex = 1
            parseResponse(response)
        else
            ErrorIntervalIndex = math.min(ErrorIntervalIndex + 1, #ERROR_INTERVALS)
            local message = ok and "Empty response" or tostring(response)
            showBanner("Network error: " .. message)
        end

        local elapsed = os.clock() - start
        if elapsed > PollInterval then
            PollInterval = math.clamp(PollInterval + 0.02, MIN_POLL_INTERVAL, MAX_POLL_INTERVAL)
        end
    end
end

local function heartbeatMonitor()
    RunService.Heartbeat:Connect(function(delta)
        AverageFrameTime = AverageFrameTime * 0.9 + delta * 0.1
        if AverageFrameTime > (1 / 45) then
            PollInterval = math.clamp(PollInterval + 0.02, MIN_POLL_INTERVAL, MAX_POLL_INTERVAL)
        elseif AverageFrameTime < (1 / 75) then
            PollInterval = math.clamp(PollInterval - 0.02, MIN_POLL_INTERVAL, MAX_POLL_INTERVAL)
        end
        if NeedsRefresh then
            NeedsRefresh = false
            updateServerCards()
        end
    end)
end

local function clearExisting()
    GuiParent = getGuiContainer()
    if not GuiParent then
        return false
    end
    local existing = GuiParent:FindFirstChild(SCRIPT_NAME)
    if existing then
        existing:Destroy()
    end
    return true
end

local function createToggle(parent, label, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    row.BackgroundTransparency = 0.18
    row.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = row

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(200, 210, 225)
    stroke.Transparency = 0.3
    stroke.Parent = row

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = row

    local labelObj = Instance.new("TextLabel")
    labelObj.BackgroundTransparency = 1
    labelObj.Size = UDim2.new(1, -100, 1, 0)
    labelObj.Font = Enum.Font.GothamMedium
    labelObj.TextColor3 = Color3.fromRGB(40, 55, 70)
    labelObj.TextSize = 19
    labelObj.TextXAlignment = Enum.TextXAlignment.Left
    labelObj.Text = label
    labelObj.Parent = row

    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 64, 0, 28)
    button.AnchorPoint = Vector2.new(1, 0.5)
    button.Position = UDim2.new(1, -6, 0.5, 0)
    button.BackgroundColor3 = Color3.fromRGB(220, 226, 236)
    button.AutoButtonColor = false
    button.Text = ""
    button.Parent = row

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 14)
    buttonCorner.Parent = button

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 26, 0, 26)
    knob.Position = UDim2.new(0, 2, 0.5, -13)
    knob.BackgroundColor3 = Color3.fromRGB(160, 170, 185)
    knob.Parent = button

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function update(state, instant)
        local pos = state and UDim2.new(1, -28, 0.5, -13) or UDim2.new(0, 2, 0.5, -13)
        local knobColor = state and Color3.fromRGB(130, 200, 160) or Color3.fromRGB(160, 170, 185)
        local buttonColor = state and Color3.fromRGB(210, 240, 220) or Color3.fromRGB(220, 226, 236)
        if instant then
            knob.Position = pos
            knob.BackgroundColor3 = knobColor
            button.BackgroundColor3 = buttonColor
        else
            TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
                Position = pos,
                BackgroundColor3 = knobColor,
            }):Play()
            TweenService:Create(button, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
                BackgroundColor3 = buttonColor,
            }):Play()
        end
    end

    button.MouseButton1Click:Connect(function()
        local newState = not button:GetAttribute("State")
        button:SetAttribute("State", newState)
        update(newState, false)
        if callback then
            callback(newState)
        end
    end)

    local function setState(state)
        button:SetAttribute("State", state)
        update(state, true)
    end

    row.Parent = parent
    return setState
end

local function createInput(parent, label, placeholder, callback)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 78)
    container.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    container.BackgroundTransparency = 0.18
    container.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = container

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(200, 210, 225)
    stroke.Transparency = 0.3
    stroke.Parent = container

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = container

    local labelObj = Instance.new("TextLabel")
    labelObj.BackgroundTransparency = 1
    labelObj.Size = UDim2.new(1, 0, 0, 24)
    labelObj.Font = Enum.Font.GothamMedium
    labelObj.TextSize = 18
    labelObj.TextColor3 = Color3.fromRGB(40, 55, 70)
    labelObj.TextXAlignment = Enum.TextXAlignment.Left
    labelObj.Text = label
    labelObj.Parent = container

    local box = Instance.new("TextBox")
    box.BackgroundTransparency = 0.1
    box.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
    box.Size = UDim2.new(1, 0, 0, 32)
    box.Position = UDim2.new(0, 0, 0, 34)
    box.Font = Enum.Font.Gotham
    box.TextSize = 17
    box.TextColor3 = Color3.fromRGB(40, 55, 70)
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(150, 165, 185)
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 8)
    boxCorner.Parent = box
    box.Parent = container

    box.FocusLost:Connect(function(enterPressed)
        if callback then
            callback(box.Text, enterPressed)
        end
    end)

    container.Parent = parent
    return box
end

local function setBoxText(box, text)
    if box then
        box.Text = text or ""
    end
end

local function buildUI()
    if not clearExisting() then
        return
    end

    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = SCRIPT_NAME
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = false
    ScreenGui.Parent = GuiParent

    MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 860, 0, 520)
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.BackgroundColor3 = Color3.fromRGB(235, 240, 250)
    MainFrame.BackgroundTransparency = 0.12
    MainFrame.BorderSizePixel = 0
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 18)
    mainCorner.Parent = MainFrame
    MainFrame.Parent = ScreenGui

    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.ZIndex = 0
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://1316045217"
    shadow.ImageColor3 = Color3.fromRGB(160, 180, 210)
    shadow.ImageTransparency = 0.65
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    shadow.Size = UDim2.new(1, 60, 1, 60)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Parent = MainFrame

    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.ZIndex = 2
    topBar.Size = UDim2.new(1, -40, 0, 68)
    topBar.Position = UDim2.new(0, 20, 0, 18)
    topBar.BackgroundTransparency = 1
    topBar.Parent = MainFrame

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 1, 0)
    title.Font = Enum.Font.GothamBlack
    title.TextColor3 = Color3.fromRGB(40, 60, 90)
    title.TextScaled = true
    title.Text = "Zamorozka Auto Joiner"
    title.Parent = topBar

    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, -40, 1, -116)
    contentFrame.Position = UDim2.new(0, 20, 0, 96)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = MainFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 20)
    layout.Parent = contentFrame

    local settingsPanel = Instance.new("Frame")
    settingsPanel.Name = "Settings"
    settingsPanel.Size = UDim2.new(0.33, -10, 1, 0)
    settingsPanel.BackgroundColor3 = Color3.fromRGB(248, 250, 255)
    settingsPanel.BackgroundTransparency = 0.1
    settingsPanel.BorderSizePixel = 0
    settingsPanel.LayoutOrder = 1
    local settingsCorner = Instance.new("UICorner")
    settingsCorner.CornerRadius = UDim.new(0, 16)
    settingsCorner.Parent = settingsPanel
    local settingsStroke = Instance.new("UIStroke")
    settingsStroke.Color = Color3.fromRGB(200, 210, 230)
    settingsStroke.Transparency = 0.3
    settingsStroke.Parent = settingsPanel
    local settingsPadding = Instance.new("UIPadding")
    settingsPadding.PaddingTop = UDim.new(0, 18)
    settingsPadding.PaddingBottom = UDim.new(0, 18)
    settingsPadding.PaddingLeft = UDim.new(0, 18)
    settingsPadding.PaddingRight = UDim.new(0, 18)
    settingsPadding.Parent = settingsPanel
    settingsPanel.Parent = contentFrame

    local settingsList = Instance.new("UIListLayout")
    settingsList.Padding = UDim.new(0, 12)
    settingsList.SortOrder = Enum.SortOrder.LayoutOrder
    settingsList.Parent = settingsPanel

    AutoJoinToggle = createToggle(settingsPanel, "Auto Join", function(state)
        setAutoJoin(state, true)
        saveConfig()
        considerAutoJoin()
    end)

    AutoInjectToggle = createToggle(settingsPanel, "Auto Inject", function(state)
        setAutoInject(state, true)
        saveConfig()
    end)

    MoneyFilterBox = createInput(settingsPanel, "Minimum $/s", "e.g. 2m", function(text)
        local value = parseMoney(text)
        if not value then
            value = 0
        end
        Config.moneyFilter = math.max(value, 0)
        setBoxText(MoneyFilterBox, Config.moneyFilter > 0 and formatMoney(Config.moneyFilter) or "")
        saveConfig()
        scheduleRefresh()
        considerAutoJoin()
    end)

    RetryAmountBox = createInput(settingsPanel, "Join retry amount", "0", function(text)
        local num = tonumber(text)
        if not num then
            num = 0
        end
        if num < 0 then
            num = 0
            showBanner("Retry amount cannot be negative; clamped to 0.")
        end
        Config.retryAmount = math.floor(num + 0.5)
        setBoxText(RetryAmountBox, tostring(Config.retryAmount))
        saveConfig()
    end)

    WhitelistBox = createInput(settingsPanel, "Whitelist (CSV)", "name1,name2", function(text)
        Config.whitelist = parseCSV(text)
        setBoxText(WhitelistBox, table.concat(Config.whitelist, ","))
        saveConfig()
        scheduleRefresh()
        considerAutoJoin()
    end)

    BlacklistBox = createInput(settingsPanel, "Blacklist (CSV)", "name1,name2", function(text)
        Config.blacklist = parseCSV(text)
        setBoxText(BlacklistBox, table.concat(Config.blacklist, ","))
        saveConfig()
        scheduleRefresh()
        considerAutoJoin()
    end)

    local serverPanel = Instance.new("Frame")
    serverPanel.Name = "Servers"
    serverPanel.Size = UDim2.new(0.67, -10, 1, 0)
    serverPanel.BackgroundColor3 = Color3.fromRGB(248, 250, 255)
    serverPanel.BackgroundTransparency = 0.1
    serverPanel.BorderSizePixel = 0
    serverPanel.LayoutOrder = 2
    local serverCorner = Instance.new("UICorner")
    serverCorner.CornerRadius = UDim.new(0, 16)
    serverCorner.Parent = serverPanel
    local serverStroke = Instance.new("UIStroke")
    serverStroke.Color = Color3.fromRGB(200, 210, 230)
    serverStroke.Transparency = 0.3
    serverStroke.Parent = serverPanel
    serverPanel.Parent = contentFrame

    local serverPadding = Instance.new("UIPadding")
    serverPadding.PaddingTop = UDim.new(0, 18)
    serverPadding.PaddingBottom = UDim.new(0, 18)
    serverPadding.PaddingLeft = UDim.new(0, 18)
    serverPadding.PaddingRight = UDim.new(0, 18)
    serverPadding.Parent = serverPanel

    ServerList = Instance.new("ScrollingFrame")
    ServerList.CanvasSize = UDim2.new(0, 0, 0, 0)
    ServerList.ScrollBarThickness = 6
    ServerList.ScrollBarImageTransparency = 0.4
    ServerList.BackgroundTransparency = 1
    ServerList.BorderSizePixel = 0
    ServerList.Size = UDim2.new(1, 0, 1, 0)
    ServerList.Parent = serverPanel

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 8)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = ServerList

    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ServerList.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
    end)

    local bannerHolder = Instance.new("Frame")
    bannerHolder.Name = "BannerHolder"
    bannerHolder.Size = UDim2.new(1, 0, 0, 32)
    bannerHolder.Position = UDim2.new(0, 0, 0, -38)
    bannerHolder.BackgroundTransparency = 1
    bannerHolder.Parent = topBar

    local bannerLabel = Instance.new("TextLabel")
    bannerLabel.BackgroundTransparency = 1
    bannerLabel.TextColor3 = Color3.fromRGB(200, 60, 70)
    bannerLabel.TextSize = 18
    bannerLabel.Font = Enum.Font.GothamMedium
    bannerLabel.Text = ""
    bannerLabel.Visible = false
    bannerLabel.Parent = bannerHolder
    ErrorBanner = bannerLabel

    local function applyConfigToUI()
        setAutoJoin(Config.autoJoin, true)
        setAutoInject(Config.autoInject, true)
        setBoxText(MoneyFilterBox, Config.moneyFilter > 0 and formatMoney(Config.moneyFilter) or "")
        setBoxText(RetryAmountBox, tostring(Config.retryAmount or 0))
        setBoxText(WhitelistBox, table.concat(Config.whitelist or {}, ","))
        setBoxText(BlacklistBox, table.concat(Config.blacklist or {}, ","))
    end

    applyConfigToUI()
    scheduleRefresh()

    local visible = true
    local basePosition = MainFrame.Position
    local hiddenPosition = UDim2.new(basePosition.X.Scale, basePosition.X.Offset, basePosition.Y.Scale, basePosition.Y.Offset + 20)

    local function setVisible(state)
        if state == visible then
            return
        end
        visible = state
        if state then
            MainFrame.Visible = true
            MainFrame.Position = hiddenPosition
            MainFrame.BackgroundTransparency = 1
            TweenService:Create(MainFrame, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                Position = basePosition,
                BackgroundTransparency = 0.12,
            }):Play()
        else
            local tween = TweenService:Create(MainFrame, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
                Position = hiddenPosition,
                BackgroundTransparency = 1,
            })
            tween.Completed:Connect(function()
                if not visible then
                    MainFrame.Visible = false
                end
                MainFrame.Position = basePosition
            end)
            tween:Play()
        end
    end

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == GUI_HOTKEY and not UserInputService:GetFocusedTextBox() then
            setVisible(not visible)
        end
    end)
end

-- Initialization
loadConfig()
buildUI()
heartbeatMonitor()
defer(cleanupLoop)
defer(pollLoop)

-- Inform about hotkey
print("[Zamorozka] Loaded. Press 'K' to toggle the interface.")
