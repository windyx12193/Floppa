-- FLOPPA AJ (TOP only, light) — newest from TOP, fast retries (~30/s)
local PLACE_ID      = 109983668079237
local FEED_URL      = "https://server-eta-two-29.vercel.app/api/feed?limit=200"
local SETTINGS_FILE = "floppa_top_prefs.json"

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LP              = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ========== filesystem ==========
local function hasfs() return isfile and writefile and readfile end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- ========== settings (START OFF, TOP по дефолту) ==========
local S = { started=false, minProfitM=1, lastTopId="" }
if hasfs() and isfile(SETTINGS_FILE) then
    local raw=readf(SETTINGS_FILE)
    if raw then
        local ok,t=pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and typeof(t)=="table" then
            if tonumber(t.minProfitM) then S.minProfitM=tonumber(t.minProfitM) end
            if type(t.lastTopId)=="string" then S.lastTopId=t.lastTopId end
        end
    end
end
local function persist()
    if hasfs() then
        writef(SETTINGS_FILE, HttpService:JSONEncode({
            started=false, minProfitM=S.minProfitM, lastTopId=S.lastTopId or ""
        }))
    end
end
persist()

-- ========== HTTP ==========
local function http_get(u)
    local url = ("%s&t=%d"):format(u, math.floor(os.clock()*1000)%2147483647)
    local providers = {
        function(U) if syn and syn.request then return syn.request({Url=U,Method="GET"}) end end,
        function(U) if http and http.request then return http.request({Url=U,Method="GET"}) end end,
        function(U) if request then return request({Url=U,Method="GET"}) end end,
        function(U) if fluxus and fluxus.request then return fluxus.request({Url=U,Method="GET"}) end end,
    }
    for _,fn in ipairs(providers) do
        local ok,res=pcall(fn,url); if ok and res and res.Body then return res.Body end
    end
    local ok2,body=pcall(function() return game:HttpGet(url) end)
    if ok2 then return body end
    return nil
end

-- ========== parsing ==========
local MULT={K=1/1000,M=1,B=1000,T=1e6}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function clean(s) return (s:gsub("%*%*",""):gsub("\226\128\139","")) end
local function uuid(s) return (s and s:match("([%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)")) end
local function profitM(line)
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
    if not c then local c2,m2=line:match("(%d+)%s*[%x\2044/\\]+%s*(%d+)"); if c2 then return tonumber(c2), tonumber(m2) end end
    return c and tonumber(c), m and tonumber(m)
end
local function name_of(line)
    local f=line:match("^([^|]+)|") or line
    return trim(clean(f or ""))
end

local function first_line(body)
    for s in string.gmatch(body,"[^\r\n]+") do
        local t=trim(s); if #t>0 then return t end
    end
end

local function parse_top(body)
    local line = first_line(body)
    if not line then return nil,nil end
    line=clean(line)
    local id=uuid(line); if not id then return nil,nil end
    local pM=profitM(line); local c,m=players(line); local nm=name_of(line)
    if not (pM and c and m) then return nil,id end
    return {jobId=id, profitM=pM, cur=c, max=m, name=nm, line=line}, id
end

-- ========== UI (как на твоём скрине) ==========
local gui=Instance.new("ScreenGui")
gui.Name="FLOPPA_AJ_TOP"
gui.ResetOnSpawn=false
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
    gui.Parent=(gethui and gethui()) or game:GetService("CoreGui")
end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local C = {
    cardBG = Color3.fromRGB(28,31,36),
    title  = Color3.fromRGB(236,239,244),
    text   = Color3.fromRGB(180,186,196),
    inputBG= Color3.fromRGB(18,21,25),
    btnOn  = Color3.fromRGB(46,204,113),
    btnOff = Color3.fromRGB(72,76,82),
    stroke = Color3.fromRGB(70,78,92),
}

local card=Instance.new("Frame",gui)
card.Size=UDim2.fromOffset(285,150)
card.Position=UDim2.new(0,20,0,80)
card.BackgroundColor3=C.cardBG
card.BorderSizePixel=0
card.Active=true; card.Draggable=true
Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
local st=Instance.new("UIStroke",card); st.Color=C.stroke; st.Thickness=1; st.Transparency=0.4

local title=Instance.new("TextLabel",card)
title.Position=UDim2.new(0,12,0,8); title.Size=UDim2.new(1,-24,0,20)
title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=16
title.TextXAlignment=Enum.TextXAlignment.Left; title.TextColor3=C.title
title.Text="FLOPPA LAST-LINE AJ"

local joiningLbl=Instance.new("TextLabel",card)
joiningLbl.Position=UDim2.new(0,12,0,24); joiningLbl.Size=UDim2.new(1,-24,0,14)
joiningLbl.BackgroundTransparency=1; joiningLbl.Font=Enum.Font.Gotham; joiningLbl.TextSize=12
joiningLbl.TextXAlignment=Enum.TextXAlignment.Left; joiningLbl.TextColor3=Color3.fromRGB(205,210,220)
joiningLbl.Text="joining: —"

local lab=Instance.new("TextLabel",card)
lab.Position=UDim2.new(0,12,0,40); lab.Size=UDim2.new(0,140,0,18)
lab.BackgroundTransparency=1; lab.Font=Enum.Font.Gotham; lab.TextSize=13
lab.TextXAlignment=Enum.TextXAlignment.Left; lab.TextColor3=C.text
lab.Text="Min profit (M/s):"

local input=Instance.new("TextBox",card)
input.Position=UDim2.new(0,12,0,58); input.Size=UDim2.new(1,-24,0,26)
input.BackgroundColor3=C.inputBG; input.Text=tostring(S.minProfitM)
input.TextScaled=true; input.ClearTextOnFocus=false; input.Font=Enum.Font.GothamSemibold
input.TextColor3=Color3.fromRGB(230,230,230)
Instance.new("UICorner",input).CornerRadius=UDim.new(0,8)

local btn=Instance.new("TextButton",card)
btn.Position=UDim2.new(0,12,0,90); btn.Size=UDim2.new(1,-24,0,30)
btn.BackgroundColor3=C.btnOff; btn.Text="START"; btn.TextColor3=Color3.fromRGB(10,10,10)
btn.Font=Enum.Font.GothamBold; btn.TextSize=16
Instance.new("UICorner",btn).CornerRadius=UDim.new(0,10)

local statusLbl=Instance.new("TextLabel",card)
statusLbl.Position=UDim2.new(0,12,1,-22); statusLbl.Size=UDim2.new(1,-24,0,16)
statusLbl.BackgroundTransparency=1; statusLbl.Font=Enum.Font.Gotham; statusLbl.TextSize=12
statusLbl.TextXAlignment=Enum.TextXAlignment.Left; statusLbl.TextColor3=C.text
statusLbl.Text="stopped"

-- ========== auto-inject ==========
do
  local loader=[[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
  if queue_on_teleport then pcall(function() queue_on_teleport(loader) end)
  elseif syn and syn.queue_on_teleport then pcall(function() syn.queue_on_teleport(loader) end) end
end

-- ========== teleport (ускоренные повторы) ==========
-- Было ~10/сек (delay ~0.10), стало ~30/сек (delay ~0.033) + более короткое окно ожидания.
local RETRY_SLEEP = 0.033     -- 30 попыток/сек
local STATE_STEP  = 0.02      -- опрос состояния телепорта
local STATE_WIN   = 0.60      -- окно ожидания «стартанул телепорт» (раньше 1.2)

local function attempt_join(jobId)
    local tpState=nil
    local onTp = LP.OnTeleport and LP.OnTeleport:Connect(function(st) tpState=st end)
    local onFail = TeleportService.TeleportInitFailed:Connect(function(player, _pid, _jid, _err)
        if player==LP then tpState = tpState or Enum.TeleportState.Failed end
    end)

    local tries, started = 0, false
    while tries < 65 and not started and S.started do
        tries += 1
        pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LP)
        end)
        -- более частая проверка статуса и меньшее окно
        local t=0
        while t<STATE_WIN and S.started do
            if tpState==Enum.TeleportState.Started or tpState==Enum.TeleportState.InProgress then
                started=true; break
            end
            task.wait(STATE_STEP); t+=STATE_STEP
        end
        if not started and S.started then
            print(("retry %d/65 (server full?) %s"):format(tries, jobId))
            task.wait(RETRY_SLEEP)
        end
    end

    if onTp then onTp:Disconnect() end
    if onFail then onFail:Disconnect() end
    return started, tries
end

-- ========== start/stop ==========
local joining=false
local function setStarted(on)
    S.started = on and true or false
    btn.Text = S.started and "STOP" or "START"
    btn.BackgroundColor3 = S.started and C.btnOn or C.btnOff
    statusLbl.Text = S.started and "finding" or "stopped"
    joining=false
    joiningLbl.Text="joining: —"
    persist()
end
setStarted(false)

btn.Activated:Connect(function() setStarted(not S.started) end)
input:GetPropertyChangedSignal("Text"):Connect(function()
    local v=tonumber(input.Text); if v and v>=0 then S.minProfitM=v; persist() end
end)

-- ========== main loop (TOP only) ==========
local function run_loop()
    if joining or not S.started then return end
    joining=true
    while S.started do
        local body = http_get(FEED_URL)
        if not body or #body==0 then
            statusLbl.Text="fetch error / empty"; task.wait(0.7)
        else
            local it, id = parse_top(body)  -- берём TOP
            if not id then
                statusLbl.Text="parse error"; task.wait(0.5)
            elseif id == S.lastTopId then
                statusLbl.Text="finding"; task.wait(0.5)
            else
                S.lastTopId = id; persist()
                if it and it.cur < it.max and it.profitM >= S.minProfitM then
                    joiningLbl.Text = ("joining: %s | %.1f M/s"):format(it.name or "?", it.profitM or 0)
                    statusLbl.Text = "joining…"
                    local ok = attempt_join(it.jobId)
                    if ok then
                        setStarted(false) -- на новом сервере автоподгрузится
                        joining=false
                        return
                    else
                        statusLbl.Text="finding"
                    end
                else
                    statusLbl.Text="finding"; task.wait(0.5)
                end
            end
        end
    end
    joining=false
end

task.spawn(function()
    while task.wait(0.35) do
        if S.started and not joining then run_loop() end
    end
end)
