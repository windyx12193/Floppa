local AUTO_INJECT_URL   = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY      = Enum.KeyCode.T
local SETTINGS_PATH     = "floppa_aj_settings.json"

local SERVER_BASE       = "https://server-eta-two-29.vercel.app"
local API_KEY           = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"

local TARGET_PLACE_ID   = 109983668079237
local PULL_INTERVAL_SEC = 2.0         -- Reduced interval
local ENTRY_TTL_SEC     = 180.0       -- Auto-delete older than 3 minutes
local FRESH_AGE_SEC     = 12.0        -- Highlight "new" entries
local DEBUG             = false

-- Services
local Players          = game:GetService("Players")
local UIS              = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")

-- Utility Functions for File System
local function hasFS() 
    return typeof(writefile) == "function" and 
           typeof(readfile) == "function" and 
           typeof(isfile) == "function" 
end

local function saveJSON(path, t)
    if not hasFS() then return false end
    local ok, data = pcall(function() return HttpService:JSONEncode(t) end)
    return ok and pcall(writefile, path, data)
end

local function loadJSON(path)
    if not hasFS() or not isfile(path) then return nil end
    local ok, data = pcall(readfile, path)
    if not ok or type(data) ~= "string" then return nil end
    local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end)
    return ok2 and tbl or nil
end

-- Persistent State Management
local State = {
    AutoJoin = false, 
    AutoInject = false, 
    IgnoreEnabled = false, 
    JoinRetry = 50, 
    MinMS = 1, 
    IgnoreNames = {}
}

-- Load saved settings
local savedConfig = loadJSON(SETTINGS_PATH)
if savedConfig then
    State.AutoJoin = savedConfig.AutoJoin or false
    State.AutoInject = savedConfig.AutoInject or false
    State.IgnoreEnabled = savedConfig.IgnoreEnabled or false
    State.JoinRetry = tonumber(savedConfig.JoinRetry) or 50
    State.MinMS = tonumber(savedConfig.MinMS) or 1
    State.IgnoreNames = type(savedConfig.IgnoreNames) == "table" and savedConfig.IgnoreNames or {}
end

-- Money Parser and Filters
local mult = {K = 1e3, M = 1e6, B = 1e9, T = 1e12}
local function parseMoneyStr(s)
    s = tostring(s or ""):gsub(",", ""):upper()
    local num, unit = s:match("%$%s*([%d%.]+)%s*([KMBT]?)%s*/%s*[Ss]") 
    if not num then num, unit = s:match("%$%s*([%d%.]+)%s*([KMBT]?)") end
    return math.floor((tonumber(num) or 0) * (mult[unit or ""] or 1) + 0.5)
end

-- Main Filtering Logic
local function minThreshold() 
    return (tonumber(State.MinMS) or 1) * 1e6 
end

local function passFilters(data)
    if data.mps < minThreshold() then return false end
    
    if State.IgnoreEnabled and #State.IgnoreNames > 0 then
        for _, nm in ipairs(State.IgnoreNames) do 
            if #nm > 0 and data.name:lower():find(nm:lower(), 1, true) then 
                return false 
            end 
        end
    end
    
    return true
end

-- Entry Management
local Entries, Order = {}, {}
local SeenHashes = {}
local firstSnapshotDone = false

local function hashOf(item)
    return string.format("%s|%s|%s", 
        tostring(item.jobId or ""), 
        tostring(item.moneyStr or ""), 
        tostring(item.playersRaw or "")
    )
end

-- Network Request Handler
local function getReqFn()
    return (syn and syn.request) or 
           http_request or 
           request or 
           (fluxus and fluxus.request)
end

local function apiGetJSON(limit)
    local req = getReqFn()
    local url = string.format("%s/api/jobs?limit=%d&_cb=%d", 
        SERVER_BASE, limit or 200, math.random(10^6, 10^7))
    
    local function safeRequest()
        local res = req({
            Url = url, 
            Method = "GET", 
            Headers = { 
                ["x-api-key"] = API_KEY, 
                ["Accept"] = "application/json" 
            }
        })
        
        return res and res.StatusCode == 200 and 
               type(res.Body) == "string" and 
               HttpService:JSONDecode(res.Body)
    end
    
    local ok, data = pcall(safeRequest)
    return ok and data
end

-- Entry Processing
local function processEntries(bestServers)
    if not firstSnapshotDone then
        for _, d in pairs(bestServers) do 
            SeenHashes[hashOf(d)] = true 
        end
        firstSnapshotDone = true
        return
    end
    
    local anyChanged = false
    for _, d in pairs(bestServers) do
        local hash = hashOf(d)
        if not SeenHashes[hash] then
            SeenHashes[hash] = true
            updateItem(d.jobId, d)
            anyChanged = true
        else
            updateExistingEntry(d)
        end
    end
    
    cleanupOldEntries()
    
    if anyChanged then 
        task.defer(resortPaint) 
    end
end

local function updateExistingEntry(data)
    local entry = Entries[data.jobId]
    if entry then
        entry.data.curPlayers = data.curPlayers
        entry.data.maxPlayers = data.maxPlayers
        entry.lastSeen = os.clock()
    end
end

local function cleanupOldEntries()
    for id, entry in pairs(Entries) do 
        if (os.clock() - entry.lastSeen) > ENTRY_TTL_SEC then 
            removeItem(id) 
        end 
    end
end

-- Main Processing Loop
local function startProcessingLoop()
    local lastTick = 0
    task.spawn(function()
        while true do
            local now = os.clock()
            if now - lastTick >= PULL_INTERVAL_SEC then
                lastTick = now
                local bestServers = processServerData()
                if bestServers then
                    processEntries(bestServers)
                end
            end
            task.wait(0.05)end
    end)
end

-- User Interface Functions
local function resortPaint()
    local sortedEntries = {}
    for _, entry in pairs(Entries) do
        table.insert(sortedEntries, entry)
    end
    
    table.sort(sortedEntries, function(a, b)
        return a.data.curPlayers > b.data.curPlayers
    end)
    
    -- Potentially update UI based on sorted entries
end

-- Initialization
local function initialize()
    SeenHashes = {}
    Entries = {}
    firstSnapshotDone = false
    
    -- Setup any necessary UI elements
    setupUI()
    
    startProcessingLoop()
end

-- Error Handling Wrapper
local function safeInitialize()
    local success, err = pcall(initialize)
    if not success then
        warn("Initialization failed: " .. tostring(err))
    end
end

-- Expose Public Interface
return {
    start = safeInitialize,
    getEntries = function() return Entries end,
    resetState = function()
        SeenHashes = {}
        Entries = {}
        firstSnapshotDone = false
    end
}
