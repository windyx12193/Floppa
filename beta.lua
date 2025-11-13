-- FLOPPA LAST-LINE AJ — auto order detect (newest TOP or BOTTOM), strict newest-only
local PLACE_ID      = 109983668079237
local FEED_BASE     = "https://server-eta-two-29.vercel.app/api/feed?limit=120"
local SETTINGS_FILE = "floppa_lastline_aj.json"

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ---------- log ----------
local function ts() return os.date("!%H:%M:%S").."Z" end
local function log(s)  print(("["..ts().."] "..tostring(s))) end
local function warnf(s) warn(("["..ts().."] "..tostring(s))) end

-- ---------- FS ----------
local function hasfs() return (isfile and writefile and readfile) and true or false end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- persist only minProfit; START always OFF
local Settings = { minProfitM = 1, started = false }
if hasfs() and isfile(SETTINGS_FILE) then
    local raw = readf(SETTINGS_FILE)
    if raw then
        local ok,t = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and typeof(t)=="table" and tonumber(t.minProfitM) then Settings.minProfitM = tonumber(t.minProfitM) end
    end
end
local function persist()
    if hasfs() then writef(SETTINGS_FILE, HttpService:JSONEncode({ minProfitM=Settings.minProfitM, started=false })) end
end
persist()

-- ---------- HTTP ----------
local function http_get(baseUrl)
    local url = ("%s&t=%d"):format(baseUrl, math.floor((os.clock()%1e6)*1000)) -- cache buster
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

-- ---------- parser ----------
local MULT = {K=1/1000, M=1, B=1000, T=1e6}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function clean(s) return (s:gsub("%*%*",""):gsub("\226\128\139","")) end
local function parse_profit_anywhere(line)
    local L = line:lower()
    for _,p in ipairs({
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*/%s*s",
        "%%?%$%s*([%d%.]+)%s*([kmbt]?)%s*&%#x2f;?%s*s",
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*\\%s*s",
        "%$%s*([%d%.]+)%s*([kmbt]?)%s+s",
    }) do
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
        local c2,m2 = line:match("(%d+)%s*[%x\2044/\\]+%s*(%d+)")
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
    local cur,max = parse_players_anywhere(line)
    local name    = parse_name_first_field(line)
    if jobId and profitM and cur and max then
        return { name=name, profitM=profitM, cur=cur, max=max, jobId=jobId }
    end
end

-- ---------- UI ----------
local gui = Instance.new("ScreenGui"); gui.Name="FloppaLastLineAJ"; gui.ResetOnSpawn=false
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.fromOffset(350,176); frame.Position=UDim2.new(0,20,0,100)
frame.BackgroundColor3=Color3.fromRGB(28,31,36); frame.BorderSizePixel=0
frame.Active=true; frame.Draggable=true

local title = Instance.new("TextLabel", frame)
title.Size=UDim2.new(1,-10,0,24); title.Position=UDim2.new(0,10,0,6)
title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=16
title.TextColor3=Color3.fromRGB(230,233,240)
title.Text="FLOPPA AJ — AUTO newest (TOP/BOTTOM)"
title.TextXAlignment=Enum.TextXAlignment.Left

local inputLabel = Instance.new("TextLabel", frame)
inputLabel.Position=UDim2.new(0,10,0,38); inputLabel.Size=UDim2.new(0,150,0,24)
inputLabel.BackgroundTransparency=1; inputLabel.Font=Enum.Font.Gotham; inputLabel.TextSize=14
inputLabel.TextColor3=Color3.fromRGB(180,186,196); inputLabel.TextXAlignment=Enum.TextXAlignment.Left
inputLabel.Text="Min profit (M/s):"

local input = Instance.new("TextBox", frame)
input.Size=UDim2.new(0,70,0,26); input.Position=UDim2.new(0,160,0,36)
input.BackgroundColor3=Color3.fromRGB(18,21,25); input.Text=tostring(Settings.minProfitM)
input.TextColor3=Color3.fromRGB(230,230,230); input.ClearTextOnFocus=false
input.Font=Enum.Font.Gotham; input.TextSize=14

local btn = Instance.new("TextButton", frame)
btn.Size=UDim2.new(1,-20,0,34); btn.Position=UDim2.new(0,10,0,72)
btn.BackgroundColor3=Color3.fromRGB(46,204,113); btn.Text="START"
btn.TextColor3=Color3.fromRGB(10,10,10); btn.Font=Enum.Font.GothamBold; btn.TextSize=16

local statusLbl = Instance.new("TextLabel", frame)
statusLbl.Size=UDim2.new(1,-20,0,50); statusLbl.Position=UDim2.new(0,10,0,112)
statusLbl.BackgroundTransparency=1; statusLbl.Font=Enum.Font.Gotham; statusLbl.TextSize=13
statusLbl.TextColor3=Color3.fromRGB(150,155,165); statusLbl.TextXAlignment=Enum.TextXAlignment.Left
statusLbl.TextWrapped=true; statusLbl.Text="idle (press START)"

-- ---------- state (сбрасываем при каждом START) ----------
local joining=false
local newestSide="auto"     -- "auto"|"top"|"bottom"
local lastTopId=nil
local lastBottomId=nil
local blockedNewestId=nil
local lastOrderLog=""
local function reset_state(reason)
    joining=false; newestSide="auto"
    lastTopId=nil; lastBottomId=nil; blockedNewestId=nil
    lastOrderLog=""
    statusLbl.Text="reset: "..(reason or "")
    log("state reset: "..(reason or ""))
end

-- START/STOP
local function setStarted(on)
    Settings.started = on and true or false
    btn.Text = Settings.started and "STOP" or "START"
    btn.BackgroundColor3 = Settings.started and Color3.fromRGB(46,204,113) or Color3.fromRGB(90,90,90)
    persist()
    log("state -> "..(Settings.started and "STARTED" or "STOPPED"))
    if Settings.started then reset_state("START clicked") end
end
setStarted(false)

btn.Activated:Connect(function() setStarted(not Settings.started) end)
input:GetPropertyChangedSignal("Text"):Connect(function()
    local v = tonumber(input.Text)
    if v and v >= 0 then Settings.minProfitM=v; persist(); log("minProfitM -> "..v.." M/s") end
end)

-- ---------- auto-inject ----------
do
    local loader = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
    local ok=false
    if queue_on_teleport then pcall(function() queue_on_teleport(loader); ok=true end)
    elseif syn and syn.queue_on_teleport then pcall(function() syn.queue_on_teleport(loader); ok=true end) end
    persist(); log("queue_on_teleport set: "..tostring(ok))
end

-- ---------- teleport ----------
local function attempt_join(jobId)
    local lp = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local tries, tpState = 0, nil
    local started=false

    local onTp
    if lp and lp.OnTeleport then
        local ok,conn = pcall(function()
            return lp.OnTeleport:Connect(function(state) tpState = state end)
        end)
        if ok then onTp=conn else log("OnTeleport connect failed: "..tostring(conn)) end
    else
        log("OnTeleport not available; blind mode")
    end

    local failConn = TeleportService.TeleportInitFailed:Connect(function(player, _placeId, _jobId, err)
        if player == lp then warnf("TeleportInitFailed: "..tostring(err)) end
    end)

    while tries < 65 and not started and Settings.started do
        tries += 1
        local ok,err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, lp)
        end)
        if not ok then warnf("Teleport error: "..tostring(err)) end

        local t=0
        while t < 3 and Settings.started do
            if tpState == Enum.TeleportState.Started or tpState == Enum.TeleportState.InProgress then
                started=true; break
            end
            task.wait(0.05); t += 0.05
        end

        if not started and Settings.started then task.wait(0.1) end
    end

    if onTp then onTp:Disconnect() end
    if failConn then failConn:Disconnect() end
    return started, tries
end

-- ---------- helpers ----------
local function split_lines(body)
    local arr={}
    for s in string.gmatch(body, "[^\r\n]+") do s=trim(s); if #s>0 then table.insert(arr,s) end end
    return arr
end
local function parse_id(line) return parse_uuid_anywhere(line or "") end

-- авто-детект порядка (что меняется — то новое)
local function detect_order(topId, bottomId)
    local changedTop   = (topId and topId ~= lastTopId)
    local changedBottom= (bottomId and bottomId ~= lastBottomId)
    if changedTop and not changedBottom then newestSide="top"
    elseif changedBottom and not changedTop then newestSide="bottom"
    elseif changedTop and changedBottom then
        -- если изменились оба — ориентируемся по последнему логу (не критично)
        newestSide = newestSide == "top" and "top" or "bottom"
    end
    lastTopId, lastBottomId = topId or lastTopId, bottomId or lastBottomId

    local cur = "newest="..(newestSide=="auto" and "AUTO?" or string.upper(newestSide))
    if cur ~= lastOrderLog then lastOrderLog = cur; log("order -> "..cur) end
end

local function pick_newest(lines)
    if #lines == 0 then return nil,nil,nil end
    local topLine    = lines[1]
    local bottomLine = lines[#lines]
    detect_order(parse_id(topLine), parse_id(bottomLine))

    local chosenLine = (newestSide=="bottom") and bottomLine or topLine
    local it = parse_line(chosenLine)
    local id = parse_id(chosenLine)
    return it, id, chosenLine
end

-- ---------- main loop ----------
local function run_loop()
    if joining then return end
    joining=true
    while Settings.started do
        statusLbl.Text="fetch feed…"
        local body = http_get(FEED_BASE)

        if body and #body>0 then
            local lines = split_lines(body)
            local it, newestId, preview = pick_newest(lines)

            if blockedNewestId and newestId == blockedNewestId then
                statusLbl.Text="newest blocked (last fail), waiting next…"
                task.wait(0.6)
            elseif not it or not it.jobId then
                statusLbl.Text="newest parse fail"
                task.wait(0.6)
            elseif it.cur >= it.max then
                statusLbl.Text=("newest full %d/%d, wait…"):format(it.cur,it.max)
                log(("newest skip: full %d/%d | %s"):format(it.cur,it.max,it.jobId))
                task.wait(0.6)
            elseif it.profitM < Settings.minProfitM then
                statusLbl.Text=("newest < %.2f M/s, wait…"):format(Settings.minProfitM)
                log(("newest skip: profit %.2fM/s < %.2f"):format(it.profitM,Settings.minProfitM))
                task.wait(0.6)
            else
                local msg = ("join NEWEST %s | %.2fM/s | %d/%d | %s"):format(
                    it.name or "?", it.profitM or 0, it.cur or 0, it.max or 0, it.jobId)
                statusLbl.Text=msg; log(msg)

                local ok, tries = attempt_join(it.jobId)
                if ok then
                    log("TELEPORT STARTED ✔ (tries: "..tries..")")
                    setStarted(false); statusLbl.Text="teleporting…"; joining=false; return
                else
                    log("newest join failed after "..tries.." tries — blocking until next id")
                    blockedNewestId = newestId
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
    while task.wait(0.4) do
        if Settings.started and not joining then run_loop()
        else statusLbl.Text="idle (press START)" end
    end
end)
