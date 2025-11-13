-- FLOPPA AJ — WebSocket push (TOP), zero polling (anti-freeze)
local PLACE_ID      = 109983668079237
local WS_URL        = "wss://server-eta-two-29.vercel.app/api/ws"  -- <<=== поменяй под себя
local SETTINGS_FILE = "floppa_push_prefs.json"

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LP              = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ===== FS =====
local function hasfs() return isfile and writefile and readfile end
local function readf(p) local ok,d=pcall(function() return readfile(p) end); return ok and d or nil end
local function writef(p,c) pcall(function() writefile(p,c) end) end

-- ===== Settings (START OFF) =====
local S = { started=false, minProfitM=1 }
do
  local raw = hasfs() and isfile(SETTINGS_FILE) and readf(SETTINGS_FILE) or nil
  if raw then
    local ok,t=pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and typeof(t)=="table" then
      if tonumber(t.minProfitM) then S.minProfitM=tonumber(t.minProfitM) end
    end
  end
end
local function persist()
  if not hasfs() then return end
  writef(SETTINGS_FILE, HttpService:JSONEncode({ started=false, minProfitM=S.minProfitM }))
end
persist()

-- ===== Parser for one line =====
local MULT={K=1/1000,M=1,B=1000,T=1e6}
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function clean(s) return (s:gsub("%*%*",""):gsub("\226\128\139","")) end
local function uuid(s) return s and s:match("([%x][%x][%x][%x][%x][%x][%x][%x]%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)") end
local function profitM(line)
  local L=line:lower()
  local _,_,num,suf = L:find("%$%s*([%d%.]+)%s*([kmbt]?)%s*/%s*s")
  if not num then _,_,num,suf = L:find("%%?%$%s*([%d%.]+)%s*([kmbt]?)%s*&%#x2f;?%s*s") end
  if not num then _,_,num,suf = L:find("%$%s*([%d%.]+)%s*([kmbt]?)%s*\\%s*s") end
  if not num then _,_,num,suf = L:find("%$%s*([%d%.]+)%s*([kmbt]?)%s+s") end
  if not num then return nil end
  local n=tonumber(num or "0") or 0
  return n*(MULT[(suf or ""):upper()] or 1)
end
local function players(line)
  local c,m=line:match("(%d+)%s*/%s*(%d+)")
  if not c then
    local c2,m2=line:match("(%d+)%s*[%x\2044/\\]+%s*(%d+)")
    if c2 then return tonumber(c2), tonumber(m2) end
  end
  return c and tonumber(c), m and tonumber(m)
end
local function name_of(line)
  local f=line:match("^([^|]+)|") or line
  return trim(clean(f or ""))
end
local function parse_line(line)
  line = clean(line or "")
  local id = uuid(line); if not id then return nil end
  local pM = profitM(line); local c,m = players(line); local nm = name_of(line)
  if not (pM and c and m) then return { jobId=id } end
  return { jobId=id, profitM=pM, cur=c, max=m, name=nm, line=line }
end

-- ===== UI (минимум перерисовок) =====
local gui=Instance.new("ScreenGui"); gui.Name="FLOPPA_PUSH_AJ"; gui.ResetOnSpawn=false
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end; gui.Parent=(gethui and gethui()) or game:GetService("CoreGui") end)
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
title.Text="FLOPPA AUTO JOIN"

local joiningLbl=Instance.new("TextLabel",card)
joiningLbl.Position=UDim2.new(0,12,0,24); joiningLbl.Size=UDim2.new(1,-24,0,14)
joiningLbl.BackgroundTransparency=1; joiningLbl.Font=Enum.Font.Gotham; joiningLbl.TextSize=12
joiningLbl.TextXAlignment=Enum.TextXAlignment.Left; joiningLbl.TextColor3=Color3.fromRGB(205,210,220)
joiningLbl.Text="joining: —"; local joiningPrev=joiningLbl.Text
local function setJoining(t) if t~=joiningPrev then joiningPrev=t; joiningLbl.Text=t end end

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
statusLbl.Text="stopped"; local statusPrev=statusLbl.Text
local function setStatus(t) if t~=statusPrev then statusPrev=t; statusLbl.Text=t end end

-- ===== auto-inject =====
do
  local loader=[[loadstring(game:HttpGet("https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/beta.lua"))()]]
  if queue_on_teleport then pcall(function() queue_on_teleport(loader) end)
  elseif syn and syn.queue_on_teleport then pcall(function() syn.queue_on_teleport(loader) end) end
end

-- ===== Teleport fast-retry (≈30/сек) =====
local RETRY_SLEEP = 0.033
local STATE_STEP  = 0.02
local STATE_WIN   = 0.60
local function attempt_join(jobId)
  local tpState=nil
  local lastLog=0
  local onTp = LP.OnTeleport and LP.OnTeleport:Connect(function(st) tpState=st end)
  local onFail = TeleportService.TeleportInitFailed:Connect(function(player, _pid, _jid, _err)
    if player==LP then tpState = tpState or Enum.TeleportState.Failed end
  end)
  local tries, started = 0, false
  while tries < 65 and not started and S.started do
    tries += 1
    pcall(function() TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LP) end)
    local t=0
    while t<STATE_WIN and S.started do
      if tpState==Enum.TeleportState.Started or tpState==Enum.TeleportState.InProgress then started=true; break end
      task.wait(STATE_STEP); t+=STATE_STEP
    end
    if not started and S.started then
      if os.clock() - lastLog > 0.5 then lastLog=os.clock(); print(("retry %d/65 (server full?) %s"):format(tries, jobId)) end
      task.wait(RETRY_SLEEP)
    end
  end
  if onTp then onTp:Disconnect() end
  if onFail then onFail:Disconnect() end
  return started, tries
end

-- ===== WS client =====
local WS = { conn=nil, alive=false }

local function ws_connect()
  -- несколько популярных API у исполнителей
  if syn and syn.websocket and syn.websocket.connect then
    local ok, ws = pcall(syn.websocket.connect, WS_URL)
    if ok and ws then return ws end
  end
  if WebSocket and WebSocket.connect then
    local ok, ws = pcall(WebSocket.connect, WS_URL)
    if ok and ws then return ws end
  end
  if fluxus and fluxus.websocket and fluxus.websocket.connect then
    local ok, ws = pcall(fluxus.websocket.connect, WS_URL)
    if ok and ws then return ws end
  end
  return nil
end

local function ws_start()
  if WS.conn then pcall(function() WS.conn:Close() end); WS.conn=nil end
  local conn = ws_connect()
  if not conn then
    setStatus("no WS support in executor")
    return
  end
  WS.conn = conn; WS.alive = true
  setStatus(S.started and "listening…" or "stopped")

  -- ping/pong (если api поддерживает Send) — не обязательно
  task.spawn(function()
    while WS.alive and WS.conn do
      task.wait(20)
      pcall(function() if WS.conn.Send then WS.conn:Send("ping") end end)
    end
  end)

  local function safe_json_decode(s)
    local ok,t=pcall(function() return HttpService:JSONDecode(s) end)
    return ok and t or nil
  end

  conn.OnMessage:Connect(function(msg)
    if not S.started then return end
    local obj = safe_json_decode(msg)
    -- сервер шлёт {type:"job", data:"<json-string>"} где data — строка JSON { line, ts }
    local line = nil
    if obj and obj.type == "job" then
      local inner = safe_json_decode(obj.data)
      line = (inner and inner.line) or nil
    end
    line = line or msg -- на всякий, если шлёшь сразу raw line

    local it = parse_line(line)
    if not it or not it.jobId then return end

    -- фильтры
    if it.cur and it.max and it.cur >= it.max then return end
    if it.profitM and it.profitM < S.minProfitM then return end

    setJoining(("joining: %s | %.1f M/s"):format(it.name or "?", it.profitM or 0))
    setStatus("joining…")
    local ok = attempt_join(it.jobId)
    if ok then
      -- на новом сервере auto-inject загрузит всё заново
      S.started=false
      btn.Text="START"; btn.BackgroundColor3=C.btnOff
      setStatus("stopped")
      persist()
    else
      setStatus("listening…")
    end
  end)

  conn.OnClose:Connect(function()
    WS.alive=false; WS.conn=nil
    if S.started then
      setStatus("ws reconnect…")
      task.wait(1.0)
      ws_start()
    else
      setStatus("stopped")
    end
  end)

  conn.OnError:Connect(function()
    WS.alive=false; WS.conn=nil
    if S.started then
      setStatus("ws error → reconnect")
      task.wait(1.0)
      ws_start()
    else
      setStatus("stopped")
    end
  end)
end

-- ===== start/stop =====
local function setStarted(on)
  S.started = on and true or false
  btn.Text = S.started and "STOP" or "START"
  btn.BackgroundColor3 = S.started and C.btnOn or C.btnOff
  setStatus(S.started and (WS.conn and "listening…" or "connecting…") or "stopped")
  setJoining("joining: —")
  persist()
  if S.started then
    if not WS.conn then ws_start() end
  end
end
setStarted(false)

btn.Activated:Connect(function() setStarted(not S.started) end)
input:GetPropertyChangedSignal("Text"):Connect(function()
  local v=tonumber(input.Text); if v and v>=0 then S.minProfitM=v; persist() end
end)
