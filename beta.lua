--[[ Floppa Auto Joiner — Minimal UI (headless) + Settings + Auto-Inject
     • Tiny menu (~260x190), rounded corners
     • Start/Stop Auto Join button
     • Min profit per second filter (in MILLIONS)
     • Settings persistence (JSON file)
     • Auto re-inject on teleport using provided GitHub URL
     • No heavy list rendering → no micro-freezes
     • Pulls site data (JSON or line format) → filters → tries to join
       If server is full (Teleport fails), retry up to 65 times at 10/s (every 0.1s), then skip
]]

---------------- USER/API SETTINGS ----------------
local SERVER_BASE       = "https://server-eta-two-29.vercel.app"
local API_KEY           = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"

-- Game target
local TARGET_PLACE_ID   = 109983668079237

-- Polling / retries
local PULL_INTERVAL_SEC = 2.5
local JOIN_RETRY_COUNT  = 65
local JOIN_RETRY_RATE   = 10       -- attempts per second

-- Settings & Auto-Inject
local SETTINGS_PATH     = "floppa_mini_aj_settings.json"
local AUTO_INJECT_URL   = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"

---------------------------------------------------

local Players          = game:GetService("Players")
local UIS              = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")

print("[MiniAJ] Booting")

-- ========= FS helpers =========
local function hasFS() return typeof(writefile)=="function" and typeof(readfile)=="function" and typeof(isfile)=="function" end
local function saveJSON(path, t)
    if not hasFS() then return false end
    local ok, data = pcall(function() return HttpService:JSONEncode(t) end)
    if not ok then return false end
    pcall(writefile, path, data); return true
end
local function loadJSON(path)
    if not hasFS() or not isfile(path) then return nil end
    local ok, data = pcall(readfile, path); if not ok or type(data)~="string" then return nil end
    local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end); if not ok2 then return nil end
    return tbl
end

-- ========= Auto-Inject (queue on teleport) =========
local function pickQueue()
    local q=nil
    pcall(function() if syn and type(syn.queue_on_teleport)=="function" then q=syn.queue_on_teleport end end)
    if not q and type(queue_on_teleport)=="function" then q=queue_on_teleport end
    if not q and type(queueteleport)=="function" then q=queueteleport end
    pcall(function() if not q and type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then q=fluxus.queue_on_teleport end end)
    return q
end

local function makeBootstrap()
    local src = [[
        task.spawn(function()
            if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
            local function g(u)
                for i=1,3 do
                    local ok,r = pcall(function() return game:HttpGet(u) end)
                    if ok and type(r)=='string' and #r>0 then return r end
                    task.wait(1)
                end
            end
            local s = g(']]..AUTO_INJECT_URL..[[')
            if s then local f=loadstring(s); if f then pcall(f) end end
        end)
    ]]
    return src
end

local function queueReinject()
    local q = pickQueue()
    if q then q(makeBootstrap()) end
end

-- queue bootstrap now and on teleport start
queueReinject()
Players.LocalPlayer.OnTeleport:Connect(function(st)
    if st == Enum.TeleportState.Started then
        queueReinject()
    end
end)

-- ========= Helpers =========
local function parseMoneyStr(s)
    s = tostring(s or ""):gsub(","," "):gsub(" ","")
    s = s:upper()
    local num, unit = s:match("%$%s*([%d%.]+)%s*([KMBT]?)%s*/%s*[Ss]")
    if not num then num, unit = s:match("%$%s*([%d%.]+)%s*([KMBT]?)") end
    local mult = {K=1e3, M=1e6, B=1e9, T=1e12}
    if not num then return 0 end
    return math.floor((tonumber(num) or 0) * (mult[unit or ""] or 1) + 0.5)
end

local function http_get(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok or type(body) ~= "string" or #body == 0 then return false end
    return true, body
end

local function parse_lines_payload(body)
    local items = {}
    local raw = tostring(body or "")
    for _, line in ipairs(string.split(raw, "\n")) do
        line = line:gsub("\r$", "")
        local a,b,c,d = line:match("^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
        if a and b and c and d then
            local name = tostring(a)
            local money = tostring(b):gsub("%*","")
            local players = tostring(c):gsub("%*","")
            local id = tostring(d)
            local cur,max = players:match("(%d+)%s*/%s*(%d+)")
            cur = tonumber(cur or 0) or 0
            max = tonumber(max or 0) or 0
            table.insert(items, { id=id, job_id=id, name=name, money=money, money_per_second=money, players=string.format("%d/%d",cur,max) })
        end
    end
    return items
end

local function fetch_items(limit)
    local url = string.format("%s/api/jobs?limit=%d&_cb=%d&key=%s", SERVER_BASE, limit or 200, math.random(10^6,10^7), API_KEY)
    local ok, body = http_get(url)
    if not ok then return false end
    local okJ, data = pcall(function() return HttpService:JSONDecode(body) end)
    if okJ and type(data) == "table" and type(data.items) == "table" then
        return true, data.items
    end
    local items = parse_lines_payload(body)
    if #items > 0 then return true, items end
    return false
end

local function pick_best_by_server(items)
    local best = {}
    for i = 1, #items do
        local it = items[i]
        local id = tostring(it.id or it.job_id or "")
        local name = tostring(it.name or "")
        local moneyStr = tostring(it.money_per_second or it.money or "")
        local players  = tostring(it.players or "")
        if id ~= "" and name ~= "" and moneyStr ~= "" and players ~= "" then
            local cur,max = players:match("(%d+)%s*/%s*(%d+)")
            cur = tonumber(cur or 0) or 0
            max = tonumber(max or 0) or 0
            local mps = parseMoneyStr(moneyStr)
            local obj = { jobId=id, name=name, moneyStr=moneyStr, mps=mps, curPlayers=cur, maxPlayers=max }
            local prev = best[id]
            if (not prev) or (obj.mps > prev.mps) then best[id] = obj end
        end
    end
    return best
end

-- ========= Minimal UI =========
local function uiRoot()
    local okH, hui = pcall(function() return gethui and gethui() end)
    if okH and hui then return hui end
    local okC, core = pcall(function() return game:GetService("CoreGui") end)
    if okC then return core end
    return Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
end

-- remove old
local _root = uiRoot()
if _root then local old = _root:FindFirstChild("MiniAJGui"); if old then pcall(function() old:Destroy() end) end end

local COLORS = {
    bg = Color3.fromRGB(20,22,26),
    panel = Color3.fromRGB(28,30,36),
    text = Color3.fromRGB(235,235,245),
    weak = Color3.fromRGB(170,175,190),
    btn  = Color3.fromRGB(67,232,113),
}

local gui = Instance.new("ScreenGui"); gui.Name = "MiniAJGui"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn=false; gui.DisplayOrder=9e5; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = _root
local frame = Instance.new("Frame"); frame.Name="Panel"; frame.Size = UDim2.new(0, 260, 0, 190); frame.Position = UDim2.new(0, 20, 0, 120); frame.BackgroundColor3 = COLORS.panel; frame.BackgroundTransparency = 0.08; frame.Parent = gui
local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = frame
local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(80,80,110); stroke.Thickness=1; stroke.Transparency=0.35; stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke.Parent=frame
local pad = Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.PaddingTop=UDim.new(0,10); pad.PaddingBottom=UDim.new(0,10); pad.Parent=frame

local function label(parent,text,size,bold)
    local l = Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Text = text; l.TextColor3 = COLORS.text; l.TextSize = size or 16; l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.Parent = parent; return l
end

local title = label(frame, "FLOPPA MINI AJ", 18, true); title.Size = UDim2.new(1,0,0,22)

local minRow = Instance.new("Frame"); minRow.Size = UDim2.new(1,0,0,56); minRow.Position = UDim2.new(0,0,0,28); minRow.BackgroundTransparency=1; minRow.Parent=frame
local minLbl = label(minRow, "Min profit (M/s):", 14, false); minLbl.Position = UDim2.new(0,0,0,0); minLbl.Size = UDim2.new(1,0,0,20); minLbl.TextColor3 = COLORS.weak
local minBox = Instance.new("TextBox"); minBox.PlaceholderText = "e.g. 5"; minBox.Text = "5"; minBox.ClearTextOnFocus=false; minBox.TextSize=16; minBox.TextColor3=COLORS.text; minBox.PlaceholderColor3=COLORS.weak; minBox.BackgroundColor3=COLORS.bg; minBox.BackgroundTransparency=0.1; minBox.Size=UDim2.new(1,0,0,28); minBox.Position=UDim2.new(0,0,0,24); minBox.Parent=minRow
local cc = Instance.new("UICorner"); cc.CornerRadius=UDim.new(0,8); cc.Parent=minBox
minBox:GetPropertyChangedSignal("Text"):Connect(function() minBox.Text = minBox.Text:gsub("[^%d]","") end)

local startBtn = Instance.new("TextButton"); startBtn.Text = "START AUTO JOIN"; startBtn.TextColor3 = Color3.fromRGB(20,20,20); startBtn.TextSize=16; startBtn.Font=Enum.Font.GothamBold; startBtn.AutoButtonColor=true; startBtn.BackgroundColor3=COLORS.btn; startBtn.Size=UDim2.new(1,0,0,32); startBtn.Position=UDim2.new(0,0,0,92); startBtn.Parent=frame
local bc = Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,10); bc.Parent=startBtn

local status = label(frame, "status: idle", 14, false); status.Position = UDim2.new(0,0,0,134); status.Size = UDim2.new(1,0,0,20); status.TextColor3 = COLORS.weak

-- ========= Settings load/apply =========
local Settings = { MinM = 5, AutoStart = false }
local cfg = loadJSON(SETTINGS_PATH)
if cfg then
    if tonumber(cfg.MinM) then Settings.MinM = tonumber(cfg.MinM) end
    if type(cfg.AutoStart)=="boolean" then Settings.AutoStart = cfg.AutoStart end
end
minBox.Text = tostring(Settings.MinM)
if Settings.AutoStart then startBtn.Text = "STOP" end

local function persist()
    saveJSON(SETTINGS_PATH, { MinM = tonumber(minBox.Text) or Settings.MinM, AutoStart = (startBtn.Text=="STOP") })
end

-- drag
local dragging=false; local startPos; local startMouse
frame.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; startPos=frame.Position; startMouse=input.Position; input.Changed:Connect(function()
        if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
        local d=input.Position-startMouse; frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

-- ========= Core logic (headless) =========
local running = false
local seenKey = {}

local function hash_key(d)
    return string.format("%s|%s|%d/%d", d.jobId or "", d.moneyStr or "", d.curPlayers or 0, d.maxPlayers or 0)
end

local function min_threshold()
    local v = tonumber(minBox.Text) or 0
    return v * 1e6
end

local function try_join(jobId)
    local tries = JOIN_RETRY_COUNT
    local dt = 1 / math.max(JOIN_RETRY_RATE,1)
    for i=1,tries do
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(TARGET_PLACE_ID, jobId, Players.LocalPlayer)
        end)
        if ok then return true end
        task.wait(dt)
    end
    return false
end

local function loop()
    running = true
    status.Text = "status: running"
    while running do
        local ok, items = fetch_items(220)
        if ok then
            local best = pick_best_by_server(items)
            local mind = min_threshold()
            local any = false
            for _, d in pairs(best) do
                if d.mps >= mind then
                    local key = hash_key(d)
                    if not seenKey[key] then
                        seenKey[key] = true
                        any = true
                        status.Text = string.format("joining: %s ($%s)", tostring(d.name or "?"), tostring(d.moneyStr or ""))
                        local joined = try_join(d.jobId)
                        if joined then
                            status.Text = "joined successfully"
                            running = false
                            break
                        else
                            status.Text = "join failed; skipping"
                        end
                    end
                end
            end
            if not any then status.Text = "status: running (no candidates)" end
        else
            status.Text = "fetch error; retrying"
        end
        persist()
        for t=1, math.floor(PULL_INTERVAL_SEC/0.05) do if not running then break end task.wait(0.05) end
    end
    status.Text = "status: stopped"
    persist()
end

startBtn.MouseButton1Click:Connect(function()
    if running then
        running = false
        startBtn.Text = "START AUTO JOIN"
        status.Text = "status: stopped"
    else
        startBtn.Text = "STOP"
        persist()
        task.spawn(loop)
    end
end)

-- AutoStart (if enabled)
if Settings.AutoStart then
    task.spawn(loop)
end

print("[MiniAJ] Ready")
