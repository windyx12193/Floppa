--[[ 
  Zamorozka Auto Joiner  •  frosty UI + auto join/inject/retry
  Author: @chatgpt12193 (Евгений Виндикс)

  Data Source:
    Endpoint: https://server-eta-two-29.vercel.app
    API key:  autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja
    Line formats supported:
      "<name>  |  $22M/s  |  6/8  |  <uuid>  |  11.11.2025, 22:21:05"
      "<name>  |  **$500K/s**  |  **6/8**  |  <uuid>  |  11.11.2025, 22:21:05"
      (and numeric timestamp fallback)

  Teleport:
    game:GetService("TeleportService"):TeleportToPlaceInstance(109983668079237, "<JOB_ID>", game.Players.LocalPlayer)
]]

--============================[ Utility & Globals ]============================--

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LP = Players.LocalPlayer

-- Safe request() wrapper for common executors
local function get_request()
    return (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request) or nil
end

local http_request = get_request()
if not http_request then
    warn("[Zamorozka] This executor does not expose a request() function. Network fetch is required.")
end

-- FS helpers (executor filesystem)
local function isfile_safe(p) local ok, r = pcall(function() return isfile and isfile(p) end) return ok and r end
local function readfile_safe(p) local ok, r = pcall(function() return readfile(p) end) if ok then return r end end
local function writefile_safe(p, d) pcall(function() if writefile then writefile(p, d) end end) end

-- queue_on_teleport wrapper
local function queue_on_teleport_safe(code)
    if queue_on_teleport then queue_on_teleport(code)
    elseif syn and syn.queue_on_teleport then syn.queue_on_teleport(code)
    elseif fluxus and fluxus.queue_on_teleport then fluxus.queue_on_teleport(code)
    end
end

-- UDim helpers
local function px(x,y) return UDim2.new(0,x or 0,0,y or 0) end
local function pxy(ax,pxl, ay,pyl) return UDim2.new(ax or 0, pxl or 0, ay or 0, pyl or 0) end

-- Colors (icy theme)
local col = {
    bg = Color3.fromRGB(240, 244, 248),            -- light icy
    panel = Color3.fromRGB(230, 236, 242),         -- slightly darker
    glass = Color3.fromRGB(255, 255, 255),
    text = Color3.fromRGB(20, 28, 38),
    subtext = Color3.fromRGB(90, 100, 112),
    green = Color3.fromRGB(30, 200, 90),
    blue = Color3.fromRGB(60, 120, 220),
    join = Color3.fromRGB(90, 230, 120),
    danger = Color3.fromRGB(235, 75, 85),
    new = Color3.fromRGB(255, 215, 0)
}

-- Config (persistent JSON)
local CONFIG_PATH = "zamorozka_auto_joiner_config.json"
local Config = {
    autoJoin = false,
    autoInject = false,
    moneyFilter = 0,
    retryAmount = 0,
    blacklist = {},
    whitelist = {},
}
local function save_config()
    writefile_safe(CONFIG_PATH, HttpService:JSONEncode(Config))
end
local function load_config()
    local raw = readfile_safe(CONFIG_PATH)
    if raw and #raw > 0 then
        local ok, parsed = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(parsed)=="table" then
            Config.autoJoin = not not parsed.autoJoin
            Config.autoInject = not not parsed.autoInject
            Config.moneyFilter = tonumber(parsed.moneyFilter) or 0
            Config.retryAmount = math.max(0, tonumber(parsed.retryAmount) or 0)
            Config.blacklist = type(parsed.blacklist)=="table" and parsed.blacklist or {}
            Config.whitelist = type(parsed.whitelist)=="table" and parsed.whitelist or {}
        end
    else
        save_config()
    end
end
load_config()

-- CSV parsing -> array of trimmed strings
local function parse_csv(s)
    local t = {}
    s = tostring(s or "")
    for item in string.gmatch(s, "([^,]+)") do
        local trimmed = string.gsub(item, "^%s*(.-)%s*$", "%1")
        if #trimmed > 0 then table.insert(t, trimmed) end
    end
    return t
end

-- Money normalizer: "200k" "8m" "1b" or plain numbers
local suffix_factor = { k=1e3, K=1e3, m=1e6, M=1e6, b=1e9, B=1e9 }
local function normalize_money(token)
    if not token then return 0 end
    token = tostring(token)
    token = token:gsub("/s","")
    local num, suf = token:match("^%s*([%d%.]+)%s*([kKmMbB]?)%s*$")
    if not num then
        local clean = token:gsub(",","")
        local asnum = tonumber(clean)
        return asnum or 0
    end
    local base = tonumber(num) or 0
    local mul = suffix_factor[suf or ""] or 1
    return math.floor(base * mul + 0.5)
end

-- number formatter (short)
local function short_money(n)
    if n >= 1e9 then return string.format("%.0fb/s", n/1e9)
    elseif n >= 1e6 then return string.format("%.0fm/s", n/1e6)
    elseif n >= 1e3 then return string.format("%.0fk/s", n/1e3)
    else return string.format("%d/s", n)
    end
end

--============================[ UI Construction ]============================--

-- Root gui (CoreGui to avoid being parented into character reset)
local RootGui = Instance.new("ScreenGui")
RootGui.Name = "ZamorozkaAutoJoiner"
RootGui.ResetOnSpawn = false
RootGui.IgnoreGuiInset = true
RootGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
RootGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

-- Blur (subtle, performance-friendly)
local blur = Instance.new("BlurEffect")
blur.Name = "ZamorozkaBlur"
blur.Size = 0 -- off by default, we toggle to 4 on show
blur.Parent = workspace.CurrentCamera

-- Main container
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0.9,0,0.9,0)
Main.Position = UDim2.new(0.05,0,0.05,0)
Main.BackgroundColor3 = col.bg
Main.BackgroundTransparency = 0.1
Main.BorderSizePixel = 0
Main.Parent = RootGui
local uic = Instance.new("UICorner", Main); uic.CornerRadius = UDim.new(0,16)
local uiStroke = Instance.new("UIStroke", Main); uiStroke.Color = Color3.fromRGB(220, 228, 235); uiStroke.Thickness = 1

-- Top bar
local Top = Instance.new("Frame")
Top.Name = "TopBar"
Top.Size = UDim2.new(1,0,0.12,0)
Top.BackgroundColor3 = col.panel
Top.BackgroundTransparency = 0.15
Top.BorderSizePixel = 0
Top.Parent = Main
Instance.new("UICorner", Top).CornerRadius = UDim.new(0,16)

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.BackgroundTransparency = 1
Title.Text = "Zamorozka Auto Joiner"
Title.Font = Enum.Font.GothamBlack
Title.TextScaled = true
Title.TextColor3 = col.text
Title.Size = UDim2.new(0.65,0,1,0)
Title.Position = UDim2.new(0.02,0,0,0)
Title.Parent = Top

-- Error banner (non-blocking)
local Banner = Instance.new("TextLabel")
Banner.Name = "Banner"
Banner.BackgroundTransparency = 0.35
Banner.BackgroundColor3 = col.danger
Banner.TextColor3 = Color3.fromRGB(255,255,255)
Banner.Font = Enum.Font.GothamBold
Banner.TextScaled = true
Banner.Text = ""
Banner.Visible = false
Banner.Size = UDim2.new(0.33,0,0.6,0)
Banner.Position = UDim2.new(0.66,0,0.2,0)
Banner.Parent = Top
Instance.new("UICorner", Banner).CornerRadius = UDim.new(0,12)

local function show_banner(msg, dur)
    Banner.Text = msg
    Banner.Visible = true
    TweenService:Create(Banner, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency=0.15}):Play()
    task.delay(dur or 2.5, function()
        TweenService:Create(Banner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency=0.45}):Play()
        task.wait(0.26)
        Banner.Visible = false
    end)
end

-- Left panel (settings)
local Left = Instance.new("Frame")
Left.Name = "Left"
Left.Size = UDim2.new(0.32,0,0.86,0)
Left.Position = UDim2.new(0.02,0,0.12,0)
Left.BackgroundColor3 = col.panel
Left.BackgroundTransparency = 0.2
Left.BorderSizePixel = 0
Left.Parent = Main
Instance.new("UICorner", Left).CornerRadius = UDim.new(0,16)
Instance.new("UIStroke", Left).Color = Color3.fromRGB(220, 228, 235)

local SettingsTitle = Instance.new("TextLabel")
SettingsTitle.BackgroundTransparency = 1
SettingsTitle.Text = "Settings"
SettingsTitle.Font = Enum.Font.GothamBlack
SettingsTitle.TextScaled = true
SettingsTitle.TextColor3 = col.text
SettingsTitle.Size = UDim2.new(1, -20, 0, 36)
SettingsTitle.Position = UDim2.new(0,10, 0,10)
SettingsTitle.Parent = Left

local SettingsScroll = Instance.new("ScrollingFrame")
SettingsScroll.BackgroundTransparency = 1
SettingsScroll.Size = UDim2.new(1,-20, 1,-56)
SettingsScroll.Position = UDim2.new(0,10, 0,50)
SettingsScroll.ScrollBarThickness = 4
SettingsScroll.Parent = Left
local SettingsLayout = Instance.new("UIListLayout", SettingsScroll)
SettingsLayout.Padding = UDim.new(0,10)

local function add_section_label(text)
    local lab = Instance.new("TextLabel")
    lab.BackgroundTransparency = 1
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.Font = Enum.Font.GothamBold
    lab.TextScaled = true
    lab.TextColor3 = col.subtext
    lab.Text = text
    lab.Size = UDim2.new(1,0,0,26)
    lab.Parent = SettingsScroll
end

local function make_toggle(labelText, init, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1,0,0,40)
    holder.BackgroundTransparency = 1
    holder.Parent = SettingsScroll

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = Enum.Font.Gotham
    l.TextScaled = true
    l.TextColor3 = col.text
    l.Text = labelText
    l.Size = UDim2.new(0.7,0,1,0)
    l.Parent = holder

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.25,0,1,0)
    btn.Position = UDim2.new(0.73,0,0,0)
    btn.Font = Enum.Font.GothamBold
    btn.TextScaled = true
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Text = init and "ON" or "OFF"
    btn.BackgroundColor3 = init and col.green or Color3.fromRGB(160,165,170)
    btn.AutoButtonColor = false
    btn.Parent = holder
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,10)

    btn.MouseButton1Click:Connect(function()
        init = not init
        btn.Text = init and "ON" or "OFF"
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = init and col.green or Color3.fromRGB(160,165,170)}):Play()
        callback(init)
    end)
end

local function make_textbox(labelText, placeholder, init, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1,0,0,50)
    holder.BackgroundTransparency = 1
    holder.Parent = SettingsScroll

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = Enum.Font.Gotham
    l.TextScaled = true
    l.TextColor3 = col.text
    l.Text = labelText
    l.Size = UDim2.new(1,0,0,20)
    l.Parent = holder

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,0,0,28)
    box.Position = UDim2.new(0,0,0,22)
    box.Font = Enum.Font.Gotham
    box.TextScaled = true
    box.PlaceholderText = placeholder
    box.Text = init or ""
    box.BackgroundColor3 = col.glass
    box.TextColor3 = col.text
    box.ClearTextOnFocus = false
    box.Parent = holder
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,8)
    Instance.new("UIStroke", box).Color = Color3.fromRGB(210,220,230)

    box.FocusLost:Connect(function()
        callback(box.Text)
    end)
end

-- Right panel (server list)
local Right = Instance.new("Frame")
Right.Name = "Right"
Right.Size = UDim2.new(0.64,0,0.86,0)
Right.Position = UDim2.new(0.34,0,0.12,0)
Right.BackgroundColor3 = col.panel
Right.BackgroundTransparency = 0.15
Right.BorderSizePixel = 0
Right.Parent = Main
Instance.new("UICorner", Right).CornerRadius = UDim.new(0,16)
Instance.new("UIStroke", Right).Color = Color3.fromRGB(220, 228, 235)

local List = Instance.new("ScrollingFrame")
List.Name = "List"
List.BackgroundTransparency = 1
List.Size = UDim2.new(1,-20, 1,-20)
List.Position = UDim2.new(0,10,0,10)
List.ScrollBarThickness = 6
List.Parent = Right
local ListLayout = Instance.new("UIListLayout", List)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0,8)

-- server card factory
local function make_card()
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -8, 0, 44)
    f.BackgroundColor3 = col.glass
    f.BackgroundTransparency = 0.1
    f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,10)
    local stroke = Instance.new("UIStroke", f); stroke.Color = Color3.fromRGB(210,220,230)

    local name = Instance.new("TextLabel")
    name.Name = "Name"
    name.BackgroundTransparency = 1
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Text = ""
    name.Font = Enum.Font.GothamBold
    name.TextScaled = true
    name.TextColor3 = col.text
    name.Size = UDim2.new(0.42,0,1,0)
    name.Position = UDim2.new(0.02,0,0,0)
    name.Parent = f

    local money = Instance.new("TextLabel")
    money.Name = "Money"
    money.BackgroundTransparency = 1
    money.TextXAlignment = Enum.TextXAlignment.Left
    money.Text = ""
    money.Font = Enum.Font.GothamBold
    money.TextScaled = true
    money.TextColor3 = col.green
    money.Size = UDim2.new(0.18,0,1,0)
    money.Position = UDim2.new(0.45,0,0,0)
    money.Parent = f

    local ppl = Instance.new("TextLabel")
    ppl.Name = "Players"
    ppl.BackgroundTransparency = 1
    ppl.TextXAlignment = Enum.TextXAlignment.Left
    ppl.Text = ""
    ppl.Font = Enum.Font.GothamBold
    ppl.TextScaled = true
    ppl.TextColor3 = col.blue
    ppl.Size = UDim2.new(0.12,0,1,0)
    ppl.Position = UDim2.new(0.62,0,0,0)
    ppl.Parent = f

    local newb = Instance.new("TextLabel")
    newb.Name = "NewBadge"
    newb.BackgroundTransparency = 0.2
    newb.BackgroundColor3 = col.new
    newb.Text = "NEW"
    newb.Font = Enum.Font.GothamBlack
    newb.TextScaled = true
    newb.TextColor3 = Color3.fromRGB(20,20,20)
    newb.Size = UDim2.new(0, 56, 0, 24)
    newb.Position = UDim2.new(0.76,0,0.22,0)
    newb.Visible = false
    newb.Parent = f
    Instance.new("UICorner", newb).CornerRadius = UDim.new(0,8)

    local join = Instance.new("TextButton")
    join.Name = "Join"
    join.Text = "JOIN"
    join.Font = Enum.Font.GothamBlack
    join.TextScaled = true
    join.TextColor3 = Color3.fromRGB(20,30,20)
    join.AutoButtonColor = false
    join.Size = UDim2.new(0.18, -8, 0.8, 0)
    join.Position = UDim2.new(0.82, 0, 0.1, 0)
    join.BackgroundColor3 = col.join
    join.Parent = f
    Instance.new("UICorner", join).CornerRadius = UDim.new(0,10)
    Instance.new("UIStroke", join).Color = Color3.fromRGB(180,210,190)

    return f
end

--============================[ Data & State ]============================--

local ENDPOINT = "https://server-eta-two-29.vercel.app"
local API_KEY = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"
local PLACE_ID = 109983668079237

-- jobId -> entry
local entries = {}
-- appearance order & time for NEW badge
local appearTimes = {} -- jobId -> tick()
-- card pool
local cardByJob = {}
local cardPool = {}

-- adaptive polling / UI tick
local pollInterval = 0.15 -- 5–10 Hz target
local minInterval, maxInterval = 0.1, 1.5
local backoff = 0 -- ms extra throttle on errors
local lastFPSCheck = tick()
local avgDt = 1/60

--============================[ Filters & Toggles ]============================--

local function set_money_filter(s)
    local v = tonumber(s)
    if not v then
        v = normalize_money((s or ""):gsub("/s",""))
    end
    v = math.max(0, v or 0)
    Config.moneyFilter = v
    save_config()
end

local function set_retry_amount(s)
    local n = tonumber(s) or 0
    if n < 0 then
        n = 0
        show_banner("Retry amount can't be negative. Clamped to 0.", 2.2)
    end
    Config.retryAmount = math.floor(n)
    save_config()
end

local function set_whitelist(s)
    Config.whitelist = parse_csv(s)
    save_config()
end
local function set_blacklist(s)
    Config.blacklist = parse_csv(s)
    save_config()
end

-- initial UI controls
add_section_label("Toggles")
make_toggle("Auto Join", Config.autoJoin, function(v)
    Config.autoJoin = v; save_config()
end)
make_toggle("Auto Inject", Config.autoInject, function(v)
    Config.autoInject = v; save_config()
end)

add_section_label("Filters")
make_textbox("Money filter (m/s)", "e.g., 200k / 8m / 1b", (Config.moneyFilter>0) and (short_money(Config.moneyFilter):gsub("/s","")) or "", function(txt)
    set_money_filter(txt)
end)
make_textbox("Join retry amount", "0 = off", tostring(Config.retryAmount or 0), function(txt)
    set_retry_amount(txt)
end)
make_textbox("Whitelist (CSV)", "name1,name2,…", table.concat(Config.whitelist, ","), function(txt)
    set_whitelist(txt)
end)
make_textbox("Blacklist (CSV)", "nameA,nameB,…", table.concat(Config.blacklist, ","), function(txt)
    set_blacklist(txt)
end)

--============================[ Networking ]============================--

local function fetch_lines()
    if not http_request then return nil, "request() not available" end
    local res = http_request({
        Url = ENDPOINT,
        Method = "GET",
        Headers = {
            ["x-api-key"] = API_KEY,
            ["Authorization"] = "Bearer "..API_KEY,
            ["Accept"] = "text/plain",
        }
    })
    if not res or (res.StatusCode or 0) >= 400 then
        return nil, ("HTTP error %s"):format(res and res.StatusCode or "nil")
    end
    local body = res.Body or res.body or ""
    local lines = {}
    for ln in body:gmatch("([^\r\n]+)") do table.insert(lines, ln) end
    return lines
end

--============================[ Line Parsing (UPDATED) ]============================--

-- "<name> |  $22M/s  |  6/8  |  <uuid>  |  11.11.2025, 22:21:05"
local function parse_line(line)
    if not line or #line < 5 then return nil end

    -- strip markdown bold & $ signs, normalize spaces
    local cleaned = line:gsub("%*%*", ""):gsub("%$","")
    local parts = {}
    for part in cleaned:gmatch("([^|]+)") do
        table.insert(parts, (part:gsub("^%s*(.-)%s*$","%1")))
    end
    if #parts < 5 then return nil end

    local name        = parts[1]
    local mps_raw     = parts[2]            -- e.g. "22M/s" or "500K/s"
    local players_raw = parts[3]            -- e.g. "6/8"
    local jobId       = parts[4]
    local ts_raw      = parts[5]            -- e.g. "11.11.2025, 22:21:05" (dd.mm.yyyy, HH:MM:SS)

    local mps = normalize_money(mps_raw)

    local p, maxp = players_raw:match("^(%d+)%s*/%s*(%d+)$")
    p, maxp = tonumber(p or 0) or 0, tonumber(maxp or 0) or 0

    -- try human-readable date first
    local d, mo, y, hh, mm, ss = ts_raw:match("^(%d%d)%.(%d%d)%.(%d%d%d%d),%s*(%d%d):(%d%d):(%d%d)$")
    local ts_num = 0
    if d and mo and y and hh and mm and ss then
        ts_num = os.time({
            year  = tonumber(y),
            month = tonumber(mo),
            day   = tonumber(d),
            hour  = tonumber(hh),
            min   = tonumber(mm),
            sec   = tonumber(ss)
        }) or 0
    else
        -- fallback: support numeric timestamps if the endpoint ever sends them
        ts_num = tonumber(ts_raw) or 0
    end

    if not (jobId and #jobId > 15) then return nil end

    return {
        name = tostring(name or ""),
        moneyPerSec = mps,
        players = p,
        maxPlayers = maxp,
        jobId = jobId,
        timestamp = ts_num,  -- epoch seconds (local time zone)
    }
end

--============================[ Join / Retry / Inject ]============================--

local AutoJoinInProgress = false

local function perform_teleport(jobId)
    if not jobId then return false end
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LP)
    end)
    if ok then
        return true
    else
        warn("[Zamorozka] Teleport failed: "..tostring(err))
        return false
    end
end

local function join_with_retry(jobId, maxAttempts)
    if (maxAttempts or 0) <= 0 then
        return perform_teleport(jobId)
    end
    for i=1, maxAttempts do
        print(string.format("[Zamorozka] join retry %d/%d", i, maxAttempts))
        if perform_teleport(jobId) then
            return true
        end
        task.wait(0.10) -- 10 attempts/sec
    end
    return false
end

local function prepare_auto_inject_on_teleport()
    if not Config.autoInject then return end
    local remote = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"
    local code = ([[
        local function fetch(u)
            local req = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
            local r = req and req({Url=u, Method="GET"}) or nil
            return r and (r.Body or r.body) or ""
        end
        local src = fetch("%s")
        if src and #src > 0 then
            local ok, err = pcall(function() loadstring(src)() end)
            if not ok then warn("[Zamorozka][AutoInject] failed: "..tostring(err)) end
        end
    ]]):format(remote)
    queue_on_teleport_safe(code)
end

--============================[ Filtering / Sorting ]============================--

local wlset, blset = {}, {}
local function rebuild_sets()
    wlset = {}; for _,v in ipairs(Config.whitelist or {}) do wlset[string.lower(v)] = true end
    blset = {}; for _,v in ipairs(Config.blacklist or {}) do blset[string.lower(v)] = true end
end
rebuild_sets()

local function pass_filters(ent)
    if not ent then return false end
    if Config.moneyFilter and ent.moneyPerSec < Config.moneyFilter then return false end
    if next(wlset) ~= nil then
        return wlset[string.lower(ent.name or "")] == true
    else
        if blset[string.lower(ent.name or "")] then return false end
    end
    return true
end

local function sort_entries(list)
    table.sort(list, function(a,b)
        if a.moneyPerSec ~= b.moneyPerSec then return a.moneyPerSec > b.moneyPerSec end
        local ta, tb = appearTimes[a.jobId] or 1e9, appearTimes[b.jobId] or 1e9
        return ta < tb
    end)
end

--============================[ UI Binding ]============================--

local function get_card()
    local c = table.remove(cardPool)
    if c then return c end
    return make_card()
end

local function recycle_card(card)
    if not card then return end
    card.Parent = nil
    table.insert(cardPool, card)
end

local function update_card(card, ent, isNew)
    card.Name.Text = ent.name
    card.Money.Text = ("$%s"):format(short_money(ent.moneyPerSec))
    card.Players.Text = ("%d/%d"):format(ent.players, ent.maxPlayers)
    card.LayoutOrder = -ent.moneyPerSec -- high first
    local showNew = (tick() - (appearTimes[ent.jobId] or tick())) <= 5
    card.NewBadge.Visible = showNew

    if isNew then
        card.BackgroundTransparency = 0.6
        TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.1}):Play()
    end

    if not card.Join._connected then
        card.Join._connected = true
        card.Join.MouseButton1Click:Connect(function()
            AutoJoinInProgress = true
            local retryAmount = math.max(0, Config.retryAmount or 0)
            local ok = join_with_retry(ent.jobId, retryAmount)
            if ok then
                Config.autoJoin = false; save_config()
                if Config.autoInject then prepare_auto_inject_on_teleport() end
            else
                show_banner("Teleport failed / retries exhausted.", 2.2)
            end
            AutoJoinInProgress = false
        end)
    end
end

local function rebuild_list()
    local arr = {}
    for _, ent in pairs(entries) do
        if pass_filters(ent) then table.insert(arr, ent) end
    end
    sort_entries(arr)

    local inUse = {}
    for _, ent in ipairs(arr) do
        local card = cardByJob[ent.jobId]
        local freshAttach = false
        if not card then
            card = get_card()
            cardByJob[ent.jobId] = card
            card.Parent = List
            freshAttach = true
        end
        update_card(card, ent, freshAttach)
        inUse[ent.jobId] = true
    end

    for jobId, card in pairs(cardByJob) do
        if not inUse[jobId] then
            TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {BackgroundTransparency = 0.8}):Play()
            task.delay(0.2, function()
                recycle_card(card)
            end)
            cardByJob[jobId] = nil
        end
    end
end

--============================[ Polling / TTL / Throttle ]============================--

local TTL_SECONDS = 180

local function process_lines(lines)
    local now = tick()
    if not lines then return end
    for _, line in ipairs(lines) do
        local ent = parse_line(line)
        if ent and ent.jobId then
            if not entries[ent.jobId] then
                entries[ent.jobId] = ent
                appearTimes[ent.jobId] = now
            else
                local ex = entries[ent.jobId]
                ex.name = ent.name
                ex.moneyPerSec = ent.moneyPerSec
                ex.players = ent.players
                ex.maxPlayers = ent.maxPlayers
                ex.timestamp = ent.timestamp
            end
        end
    end
end

-- TTL that compares epoch-to-epoch (server timestamp) or tick fallback
local function prune_ttl()
    local now_tick = tick()
    local now_epoch = os.time()

    for jobId, ent in pairs(entries) do
        local born_epoch = (ent.timestamp and ent.timestamp > 0) and ent.timestamp or nil
        local age_sec

        if born_epoch then
            age_sec = math.max(0, now_epoch - born_epoch)
        else
            local born_tick = appearTimes[jobId] or now_tick
            age_sec = math.max(0, now_tick - born_tick)
        end

        if age_sec >= TTL_SECONDS then
            entries[jobId] = nil
            appearTimes[jobId] = nil
            local card = cardByJob[jobId]
            if card then
                TweenService:Create(card, TweenInfo.new(0.18), {BackgroundTransparency=0.8}):Play()
                task.delay(0.2, function() recycle_card(card) end)
                cardByJob[jobId] = nil
            end
        end
    end
end

-- Auto-join selection: prefer newly appeared suitable server if multiple
local function pick_best_for_autojoin()
    local candidates = {}
    for _, ent in pairs(entries) do
        if pass_filters(ent) then
            table.insert(candidates, ent)
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a,b)
        local ta, tb = appearTimes[a.jobId] or 0, appearTimes[b.jobId] or 0
        if ta ~= tb then return ta > tb end -- newest first
        if a.moneyPerSec ~= b.moneyPerSec then return a.moneyPerSec > b.moneyPerSec end
        return a.jobId < b.jobId
    end)
    return candidates[1]
end

--============================[ Main Loop ]============================--

-- gentle entrance
blur.Size = 0
TweenService:Create(blur, TweenInfo.new(0.25), {Size = 4}):Play()

local lastPoll = 0
local errorStreak = 0

-- Heartbeat to adapt poll rate from FPS
RunService.Heartbeat:Connect(function(dt)
    avgDt = avgDt*0.9 + dt*0.1
    local fps = 1 / math.max(avgDt, 1e-3)
    if tick() - lastFPSCheck > 1.0 then
        if fps < 30 then
            pollInterval = math.min(maxInterval, pollInterval + 0.10)
        elseif fps < 50 then
            pollInterval = math.min(maxInterval, pollInterval + 0.05)
        else
            pollInterval = math.max(minInterval, pollInterval - 0.02)
        end
        lastFPSCheck = tick()
    end
end)

task.spawn(function()
    while RootGui.Parent do
        local now = tick()
        if now - lastPoll >= pollInterval + (backoff/1000) then
            lastPoll = now
            local lines, err = fetch_lines()
            if lines then
                if errorStreak > 0 then
                    show_banner("Network recovered.", 1.4)
                end
                errorStreak = 0
                backoff = 0
                process_lines(lines)
                prune_ttl()
                rebuild_sets()
                rebuild_list()

                if Config.autoJoin and not AutoJoinInProgress then
                    local target = pick_best_for_autojoin()
                    if target then
                        local attempts = math.max(0, Config.retryAmount or 0)
                        AutoJoinInProgress = true
                        local ok = join_with_retry(target.jobId, attempts)
                        if ok then
                            Config.autoJoin = false; save_config()
                            if Config.autoInject then prepare_auto_inject_on_teleport() end
                        end
                        AutoJoinInProgress = false
                    end
                end
            else
                errorStreak += 1
                backoff = (errorStreak == 1 and 200) or (errorStreak == 2 and 500) or 1000
                show_banner("Network error: "..tostring(err or "unknown").." • backing off", 1.8)
            end
        end
        task.wait(0.01)
    end
end)

-- Clean up blur on script end (best effort)
local function on_close()
    TweenService:Create(blur, TweenInfo.new(0.25), {Size = 0}):Play()
    task.delay(0.3, function()
        if blur and blur.Parent then pcall(function() blur:Destroy() end) end
    end)
end

RootGui.AncestryChanged:Connect(function(_, parent)
    if not parent then on_close() end
end)

print("[Zamorozka] Loaded. UI ready. Config:", HttpService:JSONEncode(Config))
