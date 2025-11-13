-- FLOPPA AUTO JOIN — WS push + safe fallback poll (anti-freeze, TOP)
local PLACE_ID      = 109983668079237
local WS_URL        = "wss://server-eta-two-29.vercel.app/api/ws"    -- <=== поменяй при необходимости
local FEED_URL      = "https://server-eta-two-29.vercel.app/api/feed?limit=120"
local SETTINGS_FILE = "floppa_push_or_pull.json"

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LP              = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ========== FS ==========
local function hasfs() return isfile and writefile and readfile end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- ========== Settings (START OFF) ==========
local S = { started=false, minProfitM=1 }
do local raw=hasfs() and isfile(SETTINGS_FILE) and readf(SETTINGS_FILE) or nil
   if raw then local ok,t=pcall(function() return HttpService:JSONDecode(raw) end)
      if ok and typeof(t)=="table" and tonumber(t.minProfitM) then S.minProfitM=tonumber(t.minProfitM) end
   end
end
local function persist()
    if not hasfs() then return end
    writef(SETTINGS_FILE, HttpService:JSONEncode({ started=false, minProfitM=S.minProfitM }))
end
persist()

-- ========== helpers ==========
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
  if not (pM and c and m) then return {jobId=id} end
  return { jobId=id, profitM=pM, cur=c, max=m, name=nm, line=line }
end

-- ========== UI ==========
local gui=Instance.new("ScreenGui"); gui.Name="FLOPPA_PUSH_PULL_AJ"; gui.ResetOnSpawn=false
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
statusLbl.Text="stopped"; local function setStatus(t) statusLbl.Text=t end

-- ========== auto-inject ==========
do
  local loader=[[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
  if queue_on_teleport then pcall(function() queue_on_teleport(loader) end)
  elseif syn and syn.queue_on_teleport then pcall(function() syn.queue_on_teleport(loader) end) end
end

-- ========== Teleport (30/сек, лог только ретраи) ==========
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

-- ========== HTTP fallback (non-blocking only) ==========
local function http_get(u, timeoutSec)
  local url = ("%s&t=%d"):format(u, math.floor(os.clock()*1000)%2147483647)
  local to = math.max(1, math.floor(timeoutSec or 3))
  local prov = {
    function() if syn and syn.request then local ok,r=pcall(syn.request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
    function() if http and http.request then local ok,r=pcall(http.request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
    function() if request then local ok,r=pcall(request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
    function() if fluxus and fluxus.request then local ok,r=pcall(fluxus.request,{Url=url,Method="GET",Timeout=to}); if ok and r and r.Body then return r.Body end end end,
  }
  for _,fn in ipairs(prov) do local body=fn(); if body then return body end end
  return nil  -- НИКАКОГО game:HttpGet -> никакого фриза
end

local function handle_feed_body(body)
  if not body or #body==0 then return end
  local top = body:match("([^\r\n]+)")
  local it = parse_line(top)
  if not it or not it.jobId then return end
  if it.cur and it.max and it.cur>=it.max then return end
  if it.profitM and it.profitM < S.minProfitM then return end
  setJoining(("joining: %s | %.1f M/s"):format(it.name or "?", it.profitM or 0))
  setStatus("joining…")
  local ok = attempt_join(it.jobId)
  if ok then S.started=false; btn.Text="START"; btn.BackgroundColor3=C.btnOff; setStatus("stopped"); persist()
  else setStatus("listening…") end
end

-- ========== WS client (мульти-API, без nil:Connect) ==========
local WS = {conn=nil, alive=false, mode="ws"} -- mode: "ws" or "pull"
local function ws_connect()
  if syn and syn.websocket and syn.websocket.connect then
    local ok,ws = pcall(syn.websocket.connect, WS_URL); if ok and ws then return ws end
  end
  if WebSocket and WebSocket.connect then
    local ok,ws = pcall(WebSocket.connect, WS_URL); if ok and ws then return ws end
  end
  if fluxus and fluxus.websocket and fluxus.websocket.connect then
    local ok,ws = pcall(fluxus.websocket.connect, WS_URL); if ok and ws then return ws end
  end
  return nil
end

local function hook_event(ws, eventNames, cb)
  for _,name in ipairs(eventNames) do
    local ev = ws[name]
    if typeof(ev)=="RBXScriptSignal" then
      local ok,conn=pcall(function() return ev:Connect(cb) end)
      if ok and conn then return conn end
    elseif type(ev)=="function" then
      -- некоторые API: ws.OnMessage(function(msg) ... end)
      local ok = pcall(function() ev(cb) end)
      if ok then return {Disconnect=function() end} end
    elseif ev==nil and type(ws["Set"..name])=="function" then
      -- редкие API: ws:SetOnMessage(cb)
      local ok = pcall(function() ws["Set"..name](ws, cb) end)
      if ok then return {Disconnect=function() end} end
    end
  end
  -- Попробуем прямую установку свойства (ws.onmessage = cb)
  for _,name in ipairs(eventNames) do
    local lower = name:lower()
    if ws[lower]==nil then
      local ok = pcall(function() ws[lower] = cb end)
      if ok then return {Disconnect=function() ws[lower]=nil end} end
    end
  end
  return nil
end

local function ws_start()
  if WS.conn then pcall(function() WS.conn:Close() end); WS.conn=nil end
  local conn = ws_connect()
  if not conn then
    -- нет ws -> fallback pull
    WS.mode="pull"; WS.alive=false; setStatus("polling…")
    task.spawn(function()
      while S.started and WS.mode=="pull" do
        local body = http_get(FEED_URL, 3)
        if S.started and body then handle_feed_body(body) end
        task.wait(1.2)
      end
    end)
    return
  end

  WS.conn = conn; WS.alive = true; WS.mode="ws"
  setStatus(S.started and "listening…" or "stopped")

  hook_event(conn, {"OnMessage","MessageReceived","Message","onmessage"}, function(msg)
    if not S.started then return end
    local okJ, obj = pcall(function() return HttpService:JSONDecode(msg) end)
    local line = nil
    if okJ and type(obj)=="table" and obj.type=="job" then
      local okInner, inner = pcall(function() return HttpService:JSONDecode(obj.data or "") end)
      if okInner and inner and inner.line then line = inner.line end
    end
    line = line or msg
    handle_feed_body(line)
  end)

  hook_event(conn, {"OnClose","Closed","onclose"}, function()
    WS.alive=false; WS.conn=nil
    if S.started then setStatus("ws reconnect…"); task.wait(1.0); ws_start() else setStatus("stopped") end
  end)

  hook_event(conn, {"OnError","Error","onerror"}, function()
    WS.alive=false; WS.conn=nil
    if S.started then setStatus("ws error → reconnect"); task.wait(1.0); ws_start() else setStatus("stopped") end
  end)

  -- мягкий пинг
  task.spawn(function()
    while S.started and WS.alive and WS.conn do
      task.wait(20)
      pcall(function() (WS.conn.Send or WS.conn.send or function() end)(WS.conn, "ping") end)
    end
  end)
end

-- ========== start/stop ==========
local function setStarted(on)
  S.started = on and true or false
  btn.Text = S.started and "STOP" or "START"
  btn.BackgroundColor3 = S.started and C.btnOn or C.btnOff
  setStatus(S.started and "connecting…" or "stopped")
  setJoining("joining: —")
  persist()
  if S.started then ws_start() end
end
setStarted(false)

btn.Activated:Connect(function() setStarted(not S.started) end)
input:GetPropertyChangedSignal("Text"):Connect(function()
  local v=tonumber(input.Text); if v and v>=0 then S.minProfitM=v; persist() end
end)
