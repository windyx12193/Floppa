-- FLOPPA AJ — pick NEWEST from TOP/BOTTOM (toggle)
local PLACE_ID      = 109983668079237
local FEED_URL      = "https://server-eta-two-29.vercel.app/api/feed?limit=200"
local SETTINGS_FILE = "floppa_aj_prefs.json"

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LP              = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ====== logging ======
local function ts() return os.date("!%H:%M:%S").."Z" end
local function log(s)  print("["..ts().."] "..tostring(s)) end
local function warnf(s) warn("["..ts().."] "..tostring(s)) end

-- ====== FS ======
local function hasfs() return isfile and writefile and readfile end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- user settings
local S = { minProfitM=1, started=false, lastSeenId="", newestAtBottom=true }
if hasfs() and isfile(SETTINGS_FILE) then
    local raw=readf(SETTINGS_FILE)
    if raw then
        local ok,t=pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and typeof(t)=="table" then
            if tonumber(t.minProfitM) then S.minProfitM=tonumber(t.minProfitM) end
            if type(t.lastSeenId)=="string" then S.lastSeenId=t.lastSeenId end
            if type(t.newestAtBottom)=="boolean" then S.newestAtBottom=t.newestAtBottom end
        end
    end
end
local function persist()
    if hasfs() then
        writef(SETTINGS_FILE, HttpService:JSONEncode({
            minProfitM=S.minProfitM, lastSeenId=S.lastSeenId or "",
            newestAtBottom=S.newestAtBottom, started=false
        }))
    end
end
persist()

-- ====== HTTP (cache-buster) ======
local function http_get(u)
    local url = ("%s&t=%d"):format(u, math.floor(os.clock()*1000)%2147483647)
    local H = { ["accept"]="text/plain", ["cache-control"]="no-cache", ["pragma"]="no-cache" }
    local providers = {
        function(U,HH) if syn and syn.request then return syn.request({Url=U,Method="GET",Headers=HH}) end end,
        function(U,HH) if http and http.request then return http.request({Url=U,Method="GET",Headers=HH}) end end,
        function(U,HH) if request then return request({Url=U,Method="GET",Headers=HH}) end end,
        function(U,HH) if fluxus and fluxus.request then return fluxus.request({Url=U,Method="GET",Headers=HH}) end end,
    }
    for _,fn in ipairs(providers) do
        local ok,res=pcall(fn,url,H); if ok and res and res.Body then return res.Body end
    end
    local ok2,body=pcall(function() return game:HttpGet(url) end)
    if ok2 then return body end
    return nil
end

-- ====== parse ======
local MULT={K=1/1000,M=1,B=1000,T=1e6}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function clean(s) return (s:gsub("%*%*",""):gsub("\226\128\139","")) end
local function uuid(s) return (s:match("([%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)")) end
local function profit(line)
    local L=line:lower()
    for _,p in ipairs({
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*/%s*s",
        "%%?%$%s*([%d%.]+)%s*([kmbt]?)%s*&%#x2f;?%s*s",
        "%$%s*([%d%.]+)%s*([kmbt]?)%s*\\%s*s",
        "%$%s*([%d%.]+)%s*([kmbt]?)%s+s",
    }) do
        local i,_,num,suf=L:find(p)
        if i then local n=tonumber(num or "0") or 0; return n*(MULT[(suf or ""):upper()] or 1) end
    end
end
local function players(line)
    local c,m=line:match("(%d+)%s*/%s*(%d+)")
    if not c then local c2,m2=line:match("(%d+)%s*[%x\2044/\\]+%s*(%d+)"); if c2 then return tonumber(c2),tonumber(m2) end end
    return c and tonumber(c), m and tonumber(m)
end
local function name1(line) local f=line:match("^([^|]+)|") or line; return trim(clean(f)) end
local function parse_line(line)
    line=clean(line)
    local id=uuid(line); local m=profit(line); local c,d=players(line); local n=name1(line)
    if id and m and c and d then return {jobId=id, profitM=m, cur=c, max=d, name=n} end
end
local function split_lines(body)
    local t={} for s in string.gmatch(body,"[^\r\n]+") do s=trim(s); if #s>0 then t[#t+1]=s end end; return t
end

-- ====== UI ======
local gui=Instance.new("ScreenGui"); gui.Name="FloppaAJ"; gui.ResetOnSpawn=false
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end; gui.Parent=(gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local f=Instance.new("Frame",gui); f.Size=UDim2.fromOffset(380,190); f.Position=UDim2.new(0,20,0,100)
f.BackgroundColor3=Color3.fromRGB(28,31,36); f.BorderSizePixel=0; f.Active=true; f.Draggable=true

local title=Instance.new("TextLabel",f); title.Size=UDim2.new(1,-10,0,24); title.Position=UDim2.new(0,10,0,6)
title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=16; title.TextXAlignment=Enum.TextXAlignment.Left
title.TextColor3=Color3.fromRGB(230,233,240); title.Text="FLOPPA AJ — NEWEST FROM TOP/BOTTOM"

local lbl=Instance.new("TextLabel",f); lbl.Position=UDim2.new(0,10,0,38); lbl.Size=UDim2.new(0,150,0,22)
lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.Gotham; lbl.TextSize=14; lbl.TextXAlignment=Enum.TextXAlignment.Left
lbl.TextColor3=Color3.fromRGB(180,186,196); lbl.Text="Min profit (M/s):"

local input=Instance.new("TextBox",f); input.Position=UDim2.new(0,160,0,36); input.Size=UDim2.new(0,70,0,26)
input.BackgroundColor3=Color3.fromRGB(18,21,25); input.Text=tostring(S.minProfitM)
input.TextColor3=Color3.fromRGB(230,230,230); input.ClearTextOnFocus=false; input.Font=Enum.Font.Gotham; input.TextSize=14

local toggle=Instance.new("TextButton",f); toggle.Position=UDim2.new(0,240,0,36); toggle.Size=UDim2.new(0,130,0,26)
local function renderToggle()
    toggle.BackgroundColor3=Color3.fromRGB(58,62,70); toggle.Font=Enum.Font.Gotham; toggle.TextSize=13
    toggle.TextColor3=Color3.fromRGB(230,230,230)
    toggle.Text = S.newestAtBottom and "Newest at BOTTOM ✅" or "Newest at TOP ✅"
end
renderToggle()

local btn=Instance.new("TextButton",f); btn.Position=UDim2.new(0,10,0,70); btn.Size=UDim2.new(1,-20,0,34)
btn.BackgroundColor3=Color3.fromRGB(46,204,113); btn.Text="START"; btn.TextColor3=Color3.fromRGB(10,10,10)
btn.Font=Enum.Font.GothamBold; btn.TextSize=16

local status=Instance.new("TextLabel",f); status.Position=UDim2.new(0,10,0,110); status.Size=UDim2.new(1,-20,0,70)
status.BackgroundTransparency=1; status.Font=Enum.Font.Gotham; status.TextSize=13
status.TextColor3=Color3.fromRGB(150,155,165); status.TextWrapped=true; status.TextXAlignment=Enum.TextXAlignment.Left
status.Text="idle (press START)"

local joining=false
local debounce=false
local lastSig=""

local function persistAndRender() persist(); renderToggle() end

-- ====== auto-inject ======
do
  local loader=[[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
  local ok=false
  if queue_on_teleport then pcall(function() queue_on_teleport(loader); ok=true end)
  elseif syn and syn.queue_on_teleport then pcall(function() syn.queue_on_teleport(loader); ok=true end) end
  log("queue_on_teleport set: "..tostring(ok))
end

-- ====== teleport ======
local function attempt_join(jobId)
    local lp=LP; local tries, tpState = 0, nil; local started=false
    local tpConn = lp.OnTeleport and lp.OnTeleport:Connect(function(st) tpState=st end)
    local failConn = TeleportService.TeleportInitFailed:Connect(function(player, _pid, _jid, err)
        if player==lp then warnf("TeleportInitFailed: "..tostring(err)) end
    end)
    while tries<65 and not started and S.started do
        tries += 1
        local ok,err=pcall(function() TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, lp) end)
        if not ok then warnf("Teleport error: "..tostring(err)) end
        local t=0
        while t<3 and S.started do
            if tpState==Enum.TeleportState.Started or tpState==Enum.TeleportState.InProgress then started=true; break end
            task.wait(0.05); t+=0.05
        end
        if not started and S.started then task.wait(0.1) end -- 10/сек
    end
    if tpConn then tpConn:Disconnect() end
    if failConn then failConn:Disconnect() end
    return started, tries
end

-- ====== helpers ======
local function pick_newest(lines)
    if #lines==0 then return nil,nil,nil end
    local idx = S.newestAtBottom and #lines or 1
    local line = lines[idx]
    local id = uuid(line or "")
    local it = line and parse_line(line) or nil
    return it, id, line, idx
end

-- ====== START/STOP ======
local function setStarted(on)
    S.started = on and true or false
    btn.Text = S.started and "STOP" or "START"
    btn.BackgroundColor3 = S.started and Color3.fromRGB(46,204,113) or Color3.fromRGB(90,90,90)
    joining=false; lastSig=""
    persist()
    log("state -> "..(S.started and "STARTED" or "STOPPED"))
    status.Text = S.started and "running…" or "idle (press START)"
end

btn.Activated:Connect(function()
    if debounce then return end; debounce=true
    setStarted(not S.started)
    task.delay(0.25,function() debounce=false end)
end)

toggle.Activated:Connect(function()
    S.newestAtBottom = not S.newestAtBottom
    persistAndRender()
    log("mode -> "..(S.newestAtBottom and "BOTTOM" or "TOP"))
end)

input:GetPropertyChangedSignal("Text"):Connect(function()
    local v=tonumber(input.Text); if v and v>=0 then S.minProfitM=v; persist(); log("minProfitM -> "..v) end
end)

-- ====== loop ======
local function run_loop()
    if joining or not S.started then return end
    joining=true
    while S.started do
        status.Text="fetch feed…"
        local body=http_get(FEED_URL)
        if not body or #body==0 then status.Text="feed empty/error"; task.wait(0.8)
        else
            local lines=split_lines(body)
            local it, id, preview, idx = pick_newest(lines)
            local sig = tostring(#lines).."|"..tostring(id).."|"..tostring(idx)
            if sig ~= lastSig then
                lastSig=sig
                log(("pick[%s]=%s | top='%s' | bottom='%s'")
                    :format(idx or "?", tostring(id or "?"):sub(1,8), (lines[1] or ""):sub(1,60), (lines[#lines] or ""):sub(1,60)))
            end

            if not id then
                status.Text="parse fail (no id)"; task.wait(0.5)
            elseif id == S.lastSeenId then
                status.Text = (S.newestAtBottom and "no NEW bottom (" or "no NEW top (")..id:sub(1,8)..")"
                task.wait(0.45)
            else
                -- новый «новый»
                log(((S.newestAtBottom and "bottom" or "top").." changed: "..tostring(S.lastSeenId).." -> "..id))
                S.lastSeenId=id; persist()

                if not it then status.Text="parse fail (no data)"; task.wait(0.5)
                elseif it.cur>=it.max then status.Text=("full %d/%d — wait…"):format(it.cur,it.max); log("skip full: "..preview); task.wait(0.5)
                elseif it.profitM < S.minProfitM then status.Text=("profit < %.2f — wait…"):format(S.minProfitM); log(("skip low: %.2f"):format(it.profitM)); task.wait(0.5)
                else
                    local msg=("JOIN %s | %.2fM/s | %d/%d | %s"):format(it.name or "?", it.profitM, it.cur, it.max, it.jobId)
                    status.Text=msg; log(msg)
                    local ok, tries = attempt_join(it.jobId)
                    if ok then
                        log("TELEPORT STARTED ✔ (tries: "..tries..")")
                        setStarted(false); status.Text="teleporting…"; joining=false; return
                    else
                        log("join failed after "..tries.." tries — waiting next new")
                        task.wait(0.6)
                    end
                end
            end
        end
    end
    joining=false
end

task.spawn(function()
    log("script loaded; place="..tostring(game.PlaceId).."; PLACE_ID="..PLACE_ID.."; newestAt="..(S.newestAtBottom and "BOTTOM" or "TOP"))
    while task.wait(0.35) do
        if S.started and not joining then run_loop() end
    end
end)
