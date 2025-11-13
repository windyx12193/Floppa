-- FLOPPA AUTO JOIN (pull-only, anti-freeze, NEWEST AT TOP, wait-for-new)
local PLACE_ID      = 109983668079237
local FEED_URL      = "https://server-eta-two-29.vercel.app/api/feed?limit=120"
local SETTINGS_FILE = "floppa_pull_wait_new.json"

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LP              = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ========= Files =========
local function hasfs() return isfile and writefile and readfile end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- ========= Settings =========
local S = { started=false, minProfitM=1, lastTopId="" } -- lastTopId = запомненный верхний ID
do
  local raw=hasfs() and isfile(SETTINGS_FILE) and readf(SETTINGS_FILE) or nil
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
      started=false,                 -- всегда OFF при рестарте
      minProfitM=S.minProfitM,
      lastTopId=S.lastTopId or ""
    }))
  end
end
persist()

-- ========= Utils / parse =========
local MULT={K=1/1000,M=1,B=1000,T=1e6}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function clean(s) return (s:gsub("%*%*",""):gsub("\226\128\139","")) end
local function uuid(s) return s and s:match("([%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)") end
local function profitM(line)
  local L=(line or ""):lower()
  local _,_,num,suf = L:find("%$%s*([%d%.]+)%s*([kmbt]?)%s*/%s*s")
  if not num then _,_,num,suf = L:find("%%?%$%s*([%d%.]+)%s*([kmbt]?)%s*&%#x2f;?%s*s") end
  if not num then _,_,num,suf = L:find("%$%s*([%d%.]+)%s*([kmbt]?)%s*\\%s*s") end
  if not num then _,_,num,suf = L:find("%$%s*([%d%.]+)%s*([kmbt]?)%s+s") end
  if not num then return nil end
  local n=tonumber(num or "0") or 0
  return n*(MULT[(suf or ""):upper()] or 1)
end
local function players(line)
  local c,m=(line or ""):match("(%d+)%s*/%s*(%d+)")
  if not c then local c2,m2=(line or ""):match("(%d+)%s*[%x\2044/\\]+%s*(%d+)"); if c2 then return tonumber(c2), tonumber(m2) end end
  return c and tonumber(c), m and tonumber(m)
end
local function name_of(line)
  local f=(line or ""):match("^([^|]+)|") or line
  return trim(clean(f or ""))
end
local function parse_line(line)
  line = clean(line or "")
  local id = uuid(line); if not id then return nil end
  local pM = profitM(line); local c,m = players(line); local nm = name_of(line)
  return { jobId=id, profitM=pM, cur=c, max=m, name=nm, line=line }
end

-- ========= HTTP (no game:HttpGet => no freeze) =========
local function http_get(u, timeoutSec)
  local url = ("%s&t=%d"):format(u, math.floor(os.clock()*1000)%2147483647)
  local to = math.max(1, math.floor(timeoutSec or 3))
  local providers = {
    function() if syn and syn.request then local ok,r=pcall(syn.request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
    function() if http and http.request then local ok,r=pcall(http.request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
    function() if request then local ok,r=pcall(request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
    function() if fluxus and fluxus.request then local ok,r=pcall(fluxus.request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
  }
  for _,fn in ipairs(providers) do local body=fn(); if body then return body end end
  return nil
end

-- ========= UI =========
local gui=Instance.new("ScreenGui"); gui.Name="FLOPPA_AJ_WAITNEW"; gui.ResetOnSpawn=false
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end; gui.Parent=(gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local C = {
  cardBG = Color3.fromRGB(28,31,36), title=Color3.fromRGB(236,239,244),
  text   = Color3.fromRGB(180,186,196), inputBG=Color3.fromRGB(18,21,25),
  btnOn  = Color3.fromRGB(46,204,113),  btnOff = Color3.fromRGB(72,76,82),
  stroke = Color3.fromRGB(70,78,92),
}

local card=Instance.new("Frame",gui)
card.Size=UDim2.fromOffset(285,150); card.Position=UDim2.new(0,20,0,80)
card.BackgroundColor3=C.cardBG; card.BorderSizePixel=0; card.Active=true; card.Draggable=true
Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
local st=Instance.new("UIStroke",card); st.Color=C.stroke; st.Thickness=1; st.Transparency=0.4

local title=Instance.new("TextLabel",card)
title.Position=UDim2.new(0,12,0,8); title.Size=UDim2.new(1,-24,0,20)
title.BackgroundTransparency=1; title.Font=Enum.Font.GothamBold; title.TextSize=16
title.TextXAlignment=Enum.TextXAlignment.Left; title.TextColor3=C.title
title.Text="FLOPPA AUTO JOIN"

local joiningLbl=Instance.new("TextLabel",card)
joiningLbl.Position=UDim2.new(0,12,0,24); joiningLbl.Size=UDim2.new(1,-24,0,14)
joiningLbl.BackgroundTransparency=1; joiningLbl.Font=Enum.Font.Gotham; joiningLbl.TextSize=12
joiningLbl.TextXAlignment=Enum.TextXAlignment.Left; joiningLbl.TextColor3=Color3.fromRGB(205,210,220)
joiningLbl.Text="joining: —"; local function setJoining(t) joiningLbl.Text=t end

local lab=Instance.new("TextLabel",card)
lab.Position=UDim2.new(0,12,0,40); lab.Size=UDim2.new(0,140,0,18)
lab.BackgroundTransparency=1; lab.Font=Enum.Font.Gotham; lab.TextSize=13
lab.TextXAlignment=Enum.TextXAlignment.Left; lab.TextColor3=C.text
lab.Text="Min profit (M/s):"

local input=Instance.new("TextBox",card)
input.Position=UDim2.new(0,12,0,58); input.Size=UDim2.new(1,-24,0,26)
input.BackgroundColor3=C.inputBG; input.Text=tostring(S.minProfitM); input.TextScaled=true
input.ClearTextOnFocus=false; input.Font=Enum.Font.GothamSemibold; input.TextColor3=Color3.fromRGB(230,230,230)
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
local function setStatus(t) statusLbl.Text=t end

-- ========= Auto-inject =========
do
  local loader=[[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
  if queue_on_teleport then pcall(function() queue_on_teleport(loader) end)
  elseif syn and syn.queue_on_teleport then pcall(function() syn.queue_on_teleport(loader) end) end
end

-- ========= Teleport (быстрые ретраи ~30/сек) =========
local RETRY_SLEEP = 0.033
local STATE_STEP  = 0.02
local STATE_WIN   = 0.60
local function attempt_join(jobId)
  local tpState=nil
  local onTp = LP.OnTeleport and LP.OnTeleport:Connect(function(st) tpState=st end)
  local onFail = TeleportService.TeleportInitFailed:Connect(function(player) if player==LP then tpState = tpState or Enum.TeleportState.Failed end end)
  local tries, started = 0, false
  while tries<65 and not started and S.started do
    tries += 1
    pcall(function() TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LP) end)
    local t=0
    while t<STATE_WIN and S.started do
      if tpState==Enum.TeleportState.Started or tpState==Enum.TeleportState.InProgress then started=true; break end
      task.wait(STATE_STEP); t+=STATE_STEP
    end
    if not started and S.started then
      if tries%15==0 then print(("retry %d/65 (server full?) %s"):format(tries, jobId)) end
      task.wait(RETRY_SLEEP)
    end
  end
  if onTp then onTp:Disconnect() end
  if onFail then onFail:Disconnect() end
  return started
end

-- ========= Pull helpers =========
local function first_line(body)
  return body and body:match("([^\r\n]+)") or nil
end

local function fetch_top_line()
  local body = http_get(FEED_URL, 3)
  if not body or #body==0 then return nil end
  local top = first_line(body)
  if not top or #trim(top)==0 then return nil end
  return parse_line(top) -- {jobId, profitM, cur, max, name}
end

-- ========= Pull loop =========
local pulling=false

-- базовая инициализация lastTopId при старте (чтобы ждать новую строку)
local function baseline_snapshot()
  local it = fetch_top_line()
  if it and it.jobId then
    S.lastTopId = it.jobId
    persist()
  end
end

local function try_new_top()
  local it = fetch_top_line()
  if not it or not it.jobId then setStatus("waiting new…"); return end

  -- ждём именно новую верхнюю строку
  if it.jobId == (S.lastTopId or "") then setStatus("waiting new…"); return end

  -- фильтры
  if it.cur and it.max and it.cur>=it.max then setStatus("waiting new…"); S.lastTopId = it.jobId; persist(); return end
  if it.profitM and it.profitM < S.minProfitM then setStatus("waiting new…"); S.lastTopId = it.jobId; persist(); return end

  -- пытаемся зайти
  setJoining(("joining: %s | %.1f M/s"):format(it.name or "?", it.profitM or 0))
  setStatus("joining…")
  local ok = attempt_join(it.jobId)
  -- запоминаем как последний увиденный top в любом случае, чтобы дальше ждать следующий
  S.lastTopId = it.jobId; persist()
  if ok then
    S.started=false; btn.Text="START"; btn.BackgroundColor3=C.btnOff; setStatus("teleporting…")
  else
    setStatus("waiting new…")
  end
end

local function start_pulling()
  if pulling then return end
  pulling=true
  task.spawn(function()
    while S.started do
      try_new_top()
      local dt = 1.2
      for _=1, math.floor(dt/0.1) do
        if not S.started then break end
        task.wait(0.1)
      end
    end
    pulling=false
  end)
end

-- ========= Start/Stop =========
local function setStarted(on)
  S.started = on and true or false
  btn.Text = S.started and "STOP" or "START"
  btn.BackgroundColor3 = S.started and C.btnOn or C.btnOff
  setJoining("joining: —")
  if S.started then
    setStatus("waiting new…")
    baseline_snapshot()     -- <== важное: запоминаем текущий TOP и ждём следующий
    start_pulling()
  else
    setStatus("stopped")
  end
  persist()
end
setStarted(false)

btn.Activated:Connect(function() setStarted(not S.started) end)
input:GetPropertyChangedSignal("Text"):Connect(function()
  local v=tonumber(input.Text); if v and v>=0 then S.minProfitM=v; persist() end
end)
