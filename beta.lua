-- FLOPPA LAST-LINE AJ — FEED (BOTTOM newest, mark after success)
local PLACE_ID      = 109983668079237
local FEED_URL      = "https://server-eta-two-29.vercel.app/api/feed?limit=120"
local SETTINGS_FILE = "floppa_lastline_aj.json"

-- Services
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer

-- Logging
local function ts() return os.date("!%H:%M:%S").."Z" end
local function log(s)  print(("["..ts().."] "..tostring(s))) end
local function warnf(s) warn(("["..ts().."] "..tostring(s))) end

-- FS
local function hasfs() return (isfile and writefile and readfile) and true or false end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- Settings: keep lastSeenId, start always OFF
local Settings = { minProfitM = 1, started = false, lastSeenId = nil }
if hasfs() and isfile(SETTINGS_FILE) then
    local raw = readf(SETTINGS_FILE)
    if raw then
        local ok,t = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and typeof(t)=="table" then
            if tonumber(t.minProfitM) then Settings.minProfitM = tonumber(t.minProfitM) end
            if type(t.lastSeenId)=="string" and #t.lastSeenId>0 then Settings.lastSeenId = t.lastSeenId end
        end
    end
end
local function persist()
    if hasfs() then
        writef(SETTINGS_FILE, HttpService:JSONEncode({
            minProfitM = Settings.minProfitM,
            started    = false,
            lastSeenId = Settings.lastSeenId
        }))
    end
end
persist()

-- HTTP
local function http_get(url)
    local HEADERS = {
        ["accept"]        = "text/plain",
        ["cache-control"] = "no-cache, no-store, must-revalidate",
        ["pragma"]        = "no-cache",
    }
    local providers = {
        function(u,h) if syn and syn.request then return syn.request({Url=u, Method="GET", Headers=h}) end end,
        function(u,h) if http and http.request then return http.request({Url=u, Method="GET", Headers=h}) end end,
        function(u,h) if request then return request({Url=u, Method="GET", Headers=h}) end end,
        function(u,h) if fluxus and fluxus.request then return fluxus.request({Url=u, Method="GET", Headers=h}) end end,
    }
    for _,fn in ipairs(providers) do
        local ok,res = pcall(fn, url, HEADERS)
        if ok and res and res.Body then return res.Body end
    end
    local ok2, body = pcall(function() return game:HttpGet(url) end)
    if ok2 then return body end
    return nil
end

-- Parser
local MULT = {K=1/1000, M=1, B=1000, T=1e6}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function clean(s) return (s:gsub("%*%*",""):gsub("\226\128\139","")) end
local function parse_profit_anywhere(line)
    local L = line:lower()
    local pats = {
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*/%s*s",
        "%%?%$%s*([%d%.]+)%s*([kmbt]?)%s*&%#x2f;?%s*s",
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*\\%s*s",
        "%$%s*([%d%.]+)%s*([%kmbt]?)%s+s",
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*s",
    }
    for _,p in ipairs(pats) do
        local a,_,num,suf = L:find(p)
        if a then
            local n = tonumber(num or "0") or 0
            return n * (MULT[(suf or ""):upper()] or 1)
        end
    end
end
local function parse_players_anywhere(line)
    local cur, max = line:match("(%d+)%s*/%s*(%d+)")
    if not cur then
        local c2, m2 = line:match("(%d+)%s*[%x\2044/\\]+%s*(%d+)")
        if c2 then return tonumber(c2), tonumber(m2) end
        return nil
    end
    return tonumber(cur), tonumber(max)
end
local function parse_uuid_anywhere(line)
    local pat = "([%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)"
    return line:match(pat)
end
local function parse_name_first_field(line)
    local first = line:match("^([^|]+)|") or line
    return trim(clean(first))
end
local function parse_line(line)
    line = clean(line)
    local jobId   = parse_uuid_anywhere(line)
    local profitM = parse_profit_anywhere(line)
    local cur, max = parse_players_anywhere(line)
    local name    = parse_name_first_field(line)
    if jobId and profitM and cur and max then
        return { name=name, profitM=profitM, cur=cur, max=max, jobId=jobId }
    end
end

-- GUI
local gui = Instance.new("ScreenGui")
gui.Name = "FloppaLastLineAJ"; gui.ResetOnSpawn = false
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.fromOffset(340, 168); frame.Position = UDim2.new(0,20,0,100)
frame.BackgroundColor3 = Color3.fromRGB(28,31,36); frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1,-10,0,24); title.Position = UDim2.new(0,10,0,6)
title.BackgroundTransparency = 1; title.Text = "FLOPPA LAST-LINE AJ (BOTTOM newest)"
title.Font = Enum.Font.GothamBold; title.TextSize = 16; title.TextColor3 = Color3.fromRGB(230,233,240)
title.TextXAlignment = Enum.TextXAlignment.Left

local inputLabel = Instance.new("TextLabel", frame)
inputLabel.Position = UDim2.new(0,10,0,38); inputLabel.Size = UDim2.new(0,150,0,24)
inputLabel.BackgroundTransparency = 1; inputLabel.Text = "Min profit (M/s):"
inputLabel.Font = Enum.Font.Gotham; inputLabel.TextSize = 14; inputLabel.TextColor3 = Color3.fromRGB(180,186,196)
inputLabel.TextXAlignment = Enum.TextXAlignment.Left

local input = Instance.new("TextBox", frame)
input.Size = UDim2.new(0,70,0,26); input.Position = UDim2.new(0,160,0,36)
input.BackgroundColor3 = Color3.fromRGB(18,21,25); input.Text = tostring(Settings.minProfitM)
input.TextColor3 = Color3.fromRGB(230,230,230); input.ClearTextOnFocus = false
input.Font = Enum.Font.Gotham; input.TextSize = 14

local btn = Instance.new("TextButton", frame)
btn.Size = UDim2.new(1,-20,0,34); btn.Position = UDim2.new(0,10,0,72)
btn.BackgroundColor3 = Color3.fromRGB(46,204,113); btn.Text = "START"
btn.TextColor3 = Color3.fromRGB(10,10,10); btn.Font = Enum.Font.GothamBold; btn.TextSize = 16

local statusLbl = Instance.new("TextLabel", frame)
statusLbl.Size = UDim2.new(1,-20,0,44); statusLbl.Position = UDim2.new(0,10,0,112)
statusLbl.BackgroundTransparency = 1; statusLbl.Text = "idle (press START)"
statusLbl.TextColor3 = Color3.fromRGB(150,155,165); statusLbl.Font = Enum.Font.Gotham; statusLbl.TextSize = 13
statusLbl.TextXAlignment = Enum.TextXAlignment.Left; statusLbl.TextWrapped = true

local function setStarted(on)
    Settings.started = on and true or false
    btn.Text = Settings.started and "STOP" or "START"
    btn.BackgroundColor3 = Settings.started and Color3.fromRGB(46,204,113) or Color3.fromRGB(90,90,90)
    persist()
    log("state -> "..(Settings.started and "STARTED" or "STOPPED"))
end
setStarted(false)

btn.Activated:Connect(function() setStarted(not Settings.started) end)
input:GetPropertyChangedSignal("Text"):Connect(function()
    local v = tonumber(input.Text)
    if v and v >= 0 then
        Settings.minProfitM = v
        persist()
        log("minProfitM -> "..v.." M/s")
    end
end)

-- Auto-inject on teleport
do
    local loader = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
    local ok=false
    if queue_on_teleport then
        pcall(function() queue_on_teleport(loader); ok=true end)
    elseif syn and syn.queue_on_teleport then
        pcall(function() syn.queue_on_teleport(loader); ok=true end)
    end
    persist()
    log("queue_on_teleport set: "..tostring(ok))
end

-- Teleport attempt (65 tries @ 10/s)
local joining=false
local triedJob = {}

local function attempt_join(jobId)
    local tries, tpState = 0, nil
    local onTp = LocalPlayer.OnTeleport:Connect(function(state) tpState = state end)
    local started=false
    while tries < 65 and not started do
        tries += 1
        local ok,err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LocalPlayer)
        end)
        if not ok then warnf("Teleport error: "..tostring(err)) end
        local t=0
        while t < 0.12 do
            if tpState == Enum.TeleportState.Started or tpState == Enum.TeleportState.InProgress then
                started=true; break
            end
            task.wait(0.02); t += 0.02
        end
        if not started then task.wait(0.1) end -- 10/сек
    end
    if onTp then onTp:Disconnect() end
    return started, tries
end

-- Helpers
local function split_lines(body)
    local arr = {}
    for s in string.gmatch(body, "[^\r\n]+") do
        s = trim(s)
        if #s>0 then table.insert(arr, s) end
    end
    return arr
end

-- ищем кандидата снизу-вверх; возвращаем it и bottomId
local function pick_newest(lines, minProfitM, lastSeenId)
    local bottomLine = lines[#lines]
    local bottomId = bottomLine and parse_uuid_anywhere(bottomLine) or nil
    if bottomId then log("bottomId="..bottomId) else log("bottomId=nil") end
    if lastSeenId then log("lastSeenId="..lastSeenId) else log("lastSeenId=nil") end

    -- если нижний тот же, что уже успешно обработан — ждём обновы
    if bottomId and lastSeenId and bottomId == lastSeenId then
        return nil, bottomId
    end

    for i = #lines, 1, -1 do
        local it = parse_line(lines[i])
        if it then
            if it.profitM >= minProfitM and it.cur < it.max then
                if not triedJob[it.jobId] then
                    return it, bottomId
                end
            end
        end
    end
    return nil, bottomId
end

-- Main loop
local lastFeedSig = ""

local function run_loop()
    if joining then return end
    joining=true
    while Settings.started do
        statusLbl.Text="fetch feed…"
        local body = http_get(FEED_URL)

        if body and #body>0 then
            local lines = split_lines(body)
            local topPreview    = lines[1] or "<empty>"
            local bottomPreview = lines[#lines] or "<empty>"
            local feedSig = tostring(#body).."|"..(topPreview).."#"..(bottomPreview)

            if feedSig ~= lastFeedSig then
                triedJob = {}          -- позволяем ещё раз попробовать новый низ
                lastFeedSig = feedSig
            end

            log(("feed lines=%d | top='%s' | bottom='%s'"):format(#lines, topPreview:sub(1,70), bottomPreview:sub(1,70)))

            local cand, bottomId = pick_newest(lines, Settings.minProfitM, Settings.lastSeenId)
            if not cand then
                if bottomId and Settings.lastSeenId and bottomId == Settings.lastSeenId then
                    statusLbl.Text = "waiting for new bottom…"
                else
                    statusLbl.Text = "no matches (≥ "..Settings.minProfitM.." M/s)"
                end
                task.wait(0.8)
            else
                triedJob[cand.jobId] = true
                local msg = ("join (BOTTOM-new) %s | %.2fM/s | %d/%d | %s"):format(
                    cand.name or "?", cand.profitM or 0, cand.cur or 0, cand.max or 0, cand.jobId)
                statusLbl.Text = msg; log(msg)

                local ok, tries = attempt_join(cand.jobId)
                if ok then
                    -- ✅ помечаем как увиденный ТОЛЬКО ПОСЛЕ успешного старта
                    Settings.lastSeenId = cand.jobId
                    persist()
                    log("TELEPORT STARTED ✔ (tries: "..tries..") | lastSeenId set")
                    setStarted(false); statusLbl.Text="teleporting…"; joining=false; return
                else
                    log("server full? retry limit reached ("..tries..") — wait newer bottom")
                end
                task.wait(0.7)
            end
        else
            statusLbl.Text="feed error / empty"
            warnf("feed error/empty")
            task.wait(1.0)
        end
    end
    joining=false
end

task.spawn(function()
    log("script loaded; started=OFF; place="..tostring(game.PlaceId).."; PLACE_ID="..tostring(PLACE_ID))
    if Settings.lastSeenId then log("remembered lastSeenId="..Settings.lastSeenId) end
    while task.wait(0.45) do
        if Settings.started and not joining then
            run_loop()
        else
            statusLbl.Text="idle (press START)"
        end
    end
end)
