--[[
  FLOPPA AUTO JOINER v5.0 (networked)
  • Хоткей: T, JSON-конфиг как в v4.7
  • Подтягивает список лобби с твоего бэкенда и рендерит в AVAILABLE LOBBIES
  • Формат: NAME | **$X/s** | **P/M** | JOB_ID | TIMESTAMP
  • JOIN: TeleportService:TeleportToPlaceInstance(PLACE_ID, JOB_ID, LocalPlayer)
  • JOIN RETRY: число повторов, частота 10/сек (0.1s между попытками)
  • Очистка «старых» лобби: всё что старше 180 сек удаляется, «свежие» подсвечены, «стареющие» немного тускнеют
]]

---------------- USER/API SETTINGS ----------------
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY    = Enum.KeyCode.T
local SETTINGS_PATH   = "floppa_aj_settings.json"

-- API источник
local SERVER_URL = "https://server-eta-two-29.vercel.app/"
local API_KEY    = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"

-- игру куда телепортируем
local TARGET_PLACE_ID = 109983668079237

-- частота опроса и устаревание
local PULL_INTERVAL_SEC = 2.0
local ENTRY_TTL_SEC     = 180.0  -- 3 минуты
local FRESH_AGE_SEC     = 12.0   -- пока что считаем «новым» (для подсветки)

---------------------------------------------------

-- ====== Services / FS / JSON ======
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local HttpService  = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local function hasFS()
    return typeof(writefile)=="function" and typeof(readfile)=="function" and typeof(isfile)=="function"
end
local function saveJSON(path, t)
    if not hasFS() then return false end
    local ok, data = pcall(function() return HttpService:JSONEncode(t) end)
    if not ok then return false end
    pcall(writefile, path, data); return true
end
local function loadJSON(path)
    if not hasFS() or not isfile(path) then return nil end
    local ok, data = pcall(readfile, path)
    if not ok or type(data)~="string" then return nil end
    local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end)
    if not ok2 then return nil end
    return tbl
end

-- ====== Singleton cleanup ======
local function findGuiParent()
    local okH, hui = pcall(function() return gethui and gethui() end)
    if okH and hui then return hui end
    local okC, core = pcall(function() return game:GetService("CoreGui") end)
    if okC then return core end
    return Players.LocalPlayer and Players.LocalPlayer:FindChildOfClass("PlayerGui") or nil
end
do
    local par = findGuiParent()
    if par then
        local old = par:FindFirstChild("FloppaAutoJoinerGui")
        if old then pcall(function() old:Destroy() end) end
    end
    local G = (getgenv and getgenv()) or _G
    G.__FLOPPA_UI_ACTIVE = true
end

-- ====== State (загружаем ДО UI) ======
local State = {
    AutoJoin      = false,
    AutoInject    = false,
    IgnoreEnabled = false,
    JoinRetry     = 50,
    MinMS         = 100,
    IgnoreNames   = {}
}
do
    local cfg = loadJSON(SETTINGS_PATH)
    if cfg then
        State.AutoJoin      = cfg.AutoJoin and true or false
        State.AutoInject    = cfg.AutoInject and true or false
        State.IgnoreEnabled = cfg.IgnoreEnabled and true or false
        State.JoinRetry     = tonumber(cfg.JoinRetry) or State.JoinRetry
        State.MinMS         = tonumber(cfg.MinMS) or State.MinMS
        State.IgnoreNames   = type(cfg.IgnoreNames)=="table" and cfg.IgnoreNames or State.IgnoreNames
    end
end

-- ====== Style / helpers ======
local COLORS = {
    purpleDeep  = Color3.fromRGB(96, 63, 196),
    purple      = Color3.fromRGB(134, 102, 255),
    purpleSoft  = Color3.fromRGB(160, 135, 255),
    surface     = Color3.fromRGB(18, 18, 22),
    surface2    = Color3.fromRGB(26, 26, 32),
    textPrimary = Color3.fromRGB(238, 238, 245),
    textWeak    = Color3.fromRGB(190, 190, 200),
    on          = Color3.fromRGB(64, 222, 125),
    off         = Color3.fromRGB(120, 120, 130),
    joinBtn     = Color3.fromRGB(67, 232, 113),
    stroke      = Color3.fromRGB(70, 60, 140)
}
local ALPHA = { panel = 0.12, card = 0.18 }

local function roundify(o, px) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0, px or 10); c.Parent=o; return c end
local function stroke(o, col, th, tr) local s=Instance.new("UIStroke"); s.Color=col or COLORS.stroke; s.Thickness=th or 1; s.Transparency=tr or 0.25; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o; return s end
local function padding(o,l,t,r,b) local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,l or 0); p.PaddingTop=UDim.new(0,t or 0); p.PaddingRight=UDim.new(0,r or 0); p.PaddingBottom=UDim.new(0,b or 0); p.Parent=o; return p end
local function setFont(lbl, weight)
    local ok = pcall(function()
        if weight=="bold" then lbl.Font=Enum.Font.GothamBold
        elseif weight=="medium" then lbl.Font=Enum.Font.GothamMedium
        else lbl.Font=Enum.Font.Gotham end
    end)
    if not ok then lbl.Font = (weight=="bold") and Enum.Font.SourceSansBold or Enum.Font.SourceSans end
end
local function mkLabel(parent, text, size, weight, color)
    local lbl=Instance.new("TextLabel"); lbl.BackgroundTransparency=1; lbl.Text=text; lbl.TextSize=size or 18
    lbl.TextColor3=color or COLORS.textPrimary; lbl.TextXAlignment=Enum.TextXAlignment.Left; setFont(lbl, weight); lbl.Parent=parent; return lbl
end
local function mkHeader(parent, text)
    local h=Instance.new("Frame"); h.BackgroundColor3=COLORS.surface2; h.BackgroundTransparency=ALPHA.card; h.Size=UDim2.new(1,0,0,38); h.Parent=parent
    roundify(h,8); stroke(h); padding(h,12,6,12,6)
    local g=Instance.new("UIGradient")
    g.Color=ColorSequence.new{ColorSequenceKeypoint.new(0,COLORS.purpleDeep),ColorSequenceKeypoint.new(1,COLORS.purple)}
    g.Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(1,0.4)}; g.Rotation=90; g.Parent=h
    mkLabel(h, text, 18, "bold", COLORS.textPrimary).Size=UDim2.new(1,0,1,0); return h
end
local function mkToggle(parent, text, default)
    local row=Instance.new("Frame"); row.Name=text.."_Row"; row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
    row.Size=UDim2.new(1,0,0,44); row.Parent=parent; roundify(row,10); stroke(row); padding(row,12,0,12,0)
    mkLabel(row, text, 17, "medium", COLORS.textPrimary).Size=UDim2.new(1,-80,1,0)
    local sw=Instance.new("TextButton"); sw.Text=""; sw.AutoButtonColor=false; sw.BackgroundColor3=Color3.fromRGB(40,40,48); sw.BackgroundTransparency=0.2
    sw.Size=UDim2.new(0,62,0,28); sw.AnchorPoint=Vector2.new(1,0.5); sw.Position=UDim2.new(1,-6,0.5,0); sw.Parent=row
    roundify(sw,14); stroke(sw, COLORS.purpleSoft, 1, 0.35)
    local dot=Instance.new("Frame"); dot.Size=UDim2.new(0,24,0,24); dot.Position=UDim2.new(0,2,0.5,-12); dot.BackgroundColor3=COLORS.off; dot.Parent=sw; roundify(dot,12)
    local state={Value=default and true or false, Changed=nil}
    local function apply(v, instant)
        state.Value=v
        local pos = v and UDim2.new(1,-26,0.5,-12) or UDim2.new(0,2,0.5,-12)
        local col = v and COLORS.on or COLORS.off
        if instant then
            dot.Position=pos; dot.BackgroundColor3=col
            sw.BackgroundColor3 = v and Color3.fromRGB(55,58,74) or Color3.fromRGB(40,40,48)
        else
            TweenService:Create(dot, TweenInfo.new(0.13, Enum.EasingStyle.Sine), {Position=pos}):Play()
            TweenService:Create(dot, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundColor3=col}):Play()
            TweenService:Create(sw,  TweenInfo.new(0.12, Enum.EasingStyle.Sine),
                {BackgroundColor3 = v and Color3.fromRGB(55,58,74) or Color3.fromRGB(40,40,48)}):Play()
        end
    end
    apply(state.Value,true)
    sw.MouseButton1Click:Connect(function()
        apply(not state.Value,false)
        if state.Changed then task.defer(function() pcall(state.Changed, state.Value) end) end
    end)
    return row, state, apply
end
local function mkStackInput(parent, title, placeholder, defaultText, isNumeric)
    local row=Instance.new("Frame"); row.Name=title.."_Stacked"; row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
    row.Size=UDim2.new(1,0,0,70); row.Parent=parent; roundify(row,10); stroke(row); padding(row,12,8,12,12)
    mkLabel(row, title, 16, "medium", COLORS.textPrimary).Size=UDim2.new(1,0,0,18)
    local box=Instance.new("TextBox"); box.PlaceholderText=placeholder or ""; box.Text=defaultText or ""; box.ClearTextOnFocus=false
    box.TextSize=17; box.TextColor3=COLORS.textPrimary; box.PlaceholderColor3=COLORS.textWeak
    box.BackgroundColor3=Color3.fromRGB(32,32,38); box.BackgroundTransparency=0.15
    box.Size=UDim2.new(1,0,0,30); box.Position=UDim2.new(0,0,0,30); roundify(box,8); stroke(box, COLORS.purpleSoft, 1, 0.35); box.Parent=row
    if isNumeric then box:GetPropertyChangedSignal("Text"):Connect(function() box.Text=box.Text:gsub("[^%d]","") end) end
    local state={}
    box.FocusLost:Connect(function()
        state.Value = isNumeric and (tonumber(box.Text) or 0) or box.Text
        if state.Changed then pcall(state.Changed, state.Value) end
    end)
    return row, state, box
end

-- ====== Blur ======
local blur=Lighting:FindFirstChild("FloppaLightBlur") or Instance.new("BlurEffect")
blur.Name="FloppaLightBlur"; blur.Size=0; blur.Enabled=false; blur.Parent=Lighting
local function setBlur(e)
    if e then blur.Enabled=true; TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=4}):Play()
    else TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=0}):Play(); task.delay(0.16,function() blur.Enabled=false end) end
end

-- ====== Root GUI ======
local parent = findGuiParent() or Players.LocalPlayer:WaitForChild("PlayerGui")
local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=1e6; gui.Parent=parent
local main=Instance.new("Frame"); main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(0.5,-490,0.5,-280)
main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui
roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, 0.35); padding(main,10,10,10,10)

-- Header
local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
roundify(header,10); stroke(header); padding(header,14,6,14,6)
mkLabel(header,"FLOPPA AUTO JOINER",20,"bold",COLORS.textPrimary).Size=UDim2.new(0.6,0,1,0)
local hotkeyInfo=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak)
hotkeyInfo.AnchorPoint=Vector2.new(1,0.5); hotkeyInfo.Position=UDim2.new(1,-14,0.5,0); hotkeyInfo.Size=UDim2.new(0.35,0,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right

-- Columns
local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1
left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
local leftPad=padding(left,0,0,0,10)
local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main
roundify(right,12); stroke(right); padding(right,12,12,12,12)

-- Left blocks
mkHeader(left,"PRIORITY ACTIONS")
local _, autoJoin,     applyAutoJoin   = mkToggle(left, "AUTO JOIN", State.AutoJoin)
local _, _,            jrBox           = mkStackInput(left, "JOIN RETRY", "50", tostring(State.JoinRetry), true)

mkHeader(left,"MONEY FILTERS")
local _, _,            msBox           = mkStackInput(left, "MIN M/S", "100", tostring(State.MinMS), true)

mkHeader(left,"НАСТРОЙКИ")
local _, autoInject,   applyAutoInject = mkToggle(left, "AUTO INJECT", State.AutoInject)
local _, ignoreToggle, applyIgnoreTgl  = mkToggle(left, "ENABLE IGNORE LIST", State.IgnoreEnabled)
local _, ignoreState,  ignoreBox       = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", table.concat(State.IgnoreNames, ","), false)

-- Right list
local listHeader=mkHeader(right,"AVAILABLE LOBBIES"); listHeader.Size=UDim2.new(1,0,0,40)
local scroll=Instance.new("ScrollingFrame"); scroll.BackgroundTransparency=1; scroll.Size=UDim2.new(1,0,1,-50); scroll.Position=UDim2.new(0,0,0,46)
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.ScrollBarThickness=6; scroll.Parent=right
local listLay=Instance.new("UIListLayout"); listLay.SortOrder=Enum.SortOrder.LayoutOrder; listLay.Padding=UDim.new(0,8); listLay.Parent=scroll

-- ====== Persist settings ======
local LOADING=false
local function parseIgnore(s) local r={} for tok in (s or ""):gmatch("([^,%s]+)") do r[#r+1]=tok end return r end
local function saveSettings()
    if LOADING then return end
    saveJSON(SETTINGS_PATH, {
        AutoJoin      = autoJoin.Value,
        AutoInject    = autoInject.Value,
        IgnoreEnabled = ignoreToggle.Value,
        JoinRetry     = tonumber(jrBox.Text) or State.JoinRetry,
        MinMS         = tonumber(msBox.Text) or State.MinMS,
        IgnoreNames   = parseIgnore(ignoreBox.Text),
    })
end
autoJoin.Changed     = function(v) State.AutoJoin=v;      saveSettings() end
autoInject.Changed   = function(v) State.AutoInject=v;    saveSettings() end
ignoreToggle.Changed = function(v) State.IgnoreEnabled=v; saveSettings() end
jrBox.FocusLost:Connect(function() State.JoinRetry=tonumber(jrBox.Text) or State.JoinRetry; saveSettings() end)
msBox.FocusLost:Connect(function() State.MinMS=tonumber(msBox.Text) or State.MinMS; saveSettings() end)
ignoreState.Changed  = function(txt) State.IgnoreNames=parseIgnore(txt); saveSettings() end

-- ====== AutoInject queue (как в v4.7) ======
local function pickQueue()
    local q=nil
    pcall(function() if syn and type(syn.queue_on_teleport)=="function" then q=syn.queue_on_teleport end end)
    if not q and type(queue_on_teleport)=="function" then q=queue_on_teleport end
    if not q and type(queueteleport)=="function" then q=queueteleport end
    if not q and type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then q=fluxus.queue_on_teleport end
    return q
end
local function makeBootstrap(url)
    url=tostring(url or "")
    local s=""
    s=s.."task.spawn(function()\n"
    s=s.."  if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end\n"
    s=s.."  local okP,Pl=pcall(function() return game:GetService('Players') end)\n"
    s=s.."  if okP and Pl then local t0=os.clock(); while not Pl.LocalPlayer and os.clock()-t0<10 do task.wait(0.05) end end\n"
    s=s.."  pcall(function() getgenv().__FLOPPA_UI_ACTIVE=nil end)\n"
    s=s.."  local function safeget(u) for i=1,3 do local ok,res=pcall(function() return game:HttpGet(u) end); if ok and type(res)=='string' and #res>0 then return res end; task.wait(1) end end\n"
    s=s.."  local src=safeget('"..AUTO_INJECT_URL.."')\n"
    s=s.."  if src then local f=loadstring(src); if f then pcall(f) end end\n"
    s=s.."end)\n"
    return s
end
local function queueReinject(url)
    local q = pickQueue()
    if q and url~="" then q(makeBootstrap(url)) end
end
if autoInject.Value then queueReinject(AUTO_INJECT_URL) end
Players.LocalPlayer.OnTeleport:Connect(function(st)
    if autoInject.Value and st==Enum.TeleportState.Started then
        queueReinject(AUTO_INJECT_URL)
    end
end)

-- ====== Network parsing / rendering ======

local function buildURL()
    -- если у тебя не корневой путь — замени здесь, напр. SERVER_URL.."api/list?key="..API_KEY
    local sep = SERVER_URL:find("?") and "&" or "?"
    return SERVER_URL .. sep .. "key=" .. tostring(API_KEY)
end

-- "$780K/s" -> 780000; "$1.2M/s" -> 1200000; "$1.5B/s" -> 1500000000
local multipliers = {K=1e3, M=1e6, B=1e9, T=1e12}
local function parseMoney(text)
    text = tostring(text or ""):upper()
    local num, unit = text:match("%$%s*([%d%.]+)%s*([KMBT]?)%s*/S")
    num = tonumber(num or "0") or 0
    local mul = unit and multipliers[unit] or 1
    return math.floor(num * mul + 0.5)
end

-- строка в формате: name | **$X/s** | **p/m** | job | ts
local function parseLine(line)
    local parts = {}
    for token in tostring(line):gmatch("([^|]+)") do
        parts[#parts+1] = (token:gsub("^%s+",""):gsub("%s+$",""))
    end
    if #parts < 5 then return nil end
    local name = parts[1]
    local moneyStr = parts[2]  -- **$780K/s**
    local playersStr = parts[3] -- **6/8**
    local jobId = parts[4]
    local ts = parts[5]        -- текстовая дата, можно не парсить

    local pNow, pMax = playersStr:match("%*%*(%d+)%s*/%s*(%d+)%*%*")
    if not pNow then pNow, pMax = playersStr:match("(%d+)%s*/%s*(%d+)") end
    pNow = tonumber(pNow or "0") or 0
    pMax = tonumber(pMax or "0") or 0

    local mps = parseMoney(moneyStr)

    return {
        name = name,
        moneyStr = (moneyStr:gsub("%*","")),
        mps = mps,
        players = pNow,
        max = pMax,
        jobId = jobId,
        ts = ts
    }
end

-- хранение и UI-элементы
local Entries = {}   -- by jobId -> {data, frame, firstSeen, lastSeen}
local Order = {}     -- массив jobIds (для сортировки)

local function visibleByFilters(d)
    if State.IgnoreEnabled then
        for _,nm in ipairs(State.IgnoreNames) do
            if #nm>0 and d.name:lower():find(nm:lower(),1,true) then
                return false
            end
        end
    end
    if d.mps < (tonumber(msBox.Text) or State.MinMS)*1000 then
        -- ВАЖНО: msBox — это «мин/мс» в текстовом виде: если пользователь вводит "100", это 100K/s?
        -- Мы трактуем как $/s в ЧИСЛЕ, поэтому умножаем на 1000 (K). При желании убери "*1000".
    end
    return d.mps >= ((tonumber(msBox.Text) or State.MinMS) * 1000)
end

local function formatPlayers(p,m)
    return string.format("%d/%d", p or 0, m or 0)
end

local function ensureEntryFrame(jobId, data)
    local e = Entries[jobId]
    if e and e.frame then return e.frame end

    local item=Instance.new("Frame"); item.Size=UDim2.new(1,-6,0,52); item.BackgroundColor3=COLORS.surface; item.BackgroundTransparency=ALPHA.panel
    item.Parent=scroll; roundify(item,10); stroke(item, COLORS.purpleSoft, 1, 0.35); padding(item,12,6,12,6)

    local nameLbl=mkLabel(item, string.upper(data.name), 18, "bold", COLORS.textPrimary)
    nameLbl.Size=UDim2.new(0.44,-10,1,0)

    local moneyLbl=mkLabel(item, string.upper((data.moneyStr or "")), 17, "medium", Color3.fromRGB(130,255,130))
    moneyLbl.AnchorPoint=Vector2.new(0,0.5); moneyLbl.Position=UDim2.new(0.46,0,0.5,0)
    moneyLbl.Size=UDim2.new(0.22,0,1,0); moneyLbl.TextXAlignment=Enum.TextXAlignment.Left

    local playersLbl=mkLabel(item, formatPlayers(data.players, data.max), 16, "medium", COLORS.textWeak)
    playersLbl.AnchorPoint=Vector2.new(0,0.5); playersLbl.Position=UDim2.new(0.69,0,0.5,0)
    playersLbl.Size=UDim2.new(0.12,0,1,0); playersLbl.TextXAlignment=Enum.TextXAlignment.Left

    local joinBtn=Instance.new("TextButton"); joinBtn.Text="JOIN"; setFont(joinBtn,"bold"); joinBtn.TextSize=18; joinBtn.TextColor3=Color3.fromRGB(22,22,22)
    joinBtn.AutoButtonColor=true; joinBtn.BackgroundColor3=COLORS.joinBtn; joinBtn.Size=UDim2.new(0,84,0,36); joinBtn.AnchorPoint=Vector2.new(1,0.5); joinBtn.Position=UDim2.new(1,-8,0.5,0)
    roundify(joinBtn,10); stroke(joinBtn, Color3.fromRGB(0,0,0), 1, 0.7); joinBtn.Parent=item

    joinBtn.MouseButton1Click:Connect(function()
        -- ограниченная по времени серия попыток: State.JoinRetry, 10/сек
        local tries = tonumber(jrBox.Text) or State.JoinRetry or 0
        local delaySec = 0.10
        joinBtn.Text = "JOIN…"
        for i=1, math.max(tries,1) do
            local ok, tpErr = pcall(function()
                TeleportService:TeleportToPlaceInstance(TARGET_PLACE_ID, jobId, Players.LocalPlayer)
            end)
            if ok then
                joinBtn.Text = "OK"
                break
            else
                -- если сервер полон/ошибка — просто ждём и пробуем снова
                joinBtn.Text = ("RETRY %d/%d"):format(i, tries)
                task.wait(delaySec)
            end
        end
        task.delay(0.8, function() if joinBtn then joinBtn.Text="JOIN" end end)
    end)

    if not e then Entries[jobId] = {data=data, frame=item, firstSeen=os.clock(), lastSeen=os.clock()} end
    return item
end

local function updateEntry(jobId, data)
    local e = Entries[jobId]
    if not e then
        ensureEntryFrame(jobId, data)
        e = Entries[jobId]
        table.insert(Order, jobId)
    else
        e.data = data
        e.lastSeen = os.clock()
        -- обновим текст
        local item = e.frame
        if item and item.Parent then
            local kids = item:GetChildren()
            -- 1: name, 2: money, 3: players, 4: button (по созданию выше)
            if kids[1] and kids[1].ClassName=="TextLabel" then kids[1].Text = string.upper(data.name) end
            if kids[2] and kids[2].ClassName=="TextLabel" then kids[2].Text = string.upper((data.moneyStr or "")) end
            if kids[3] and kids[3].ClassName=="TextLabel" then kids[3].Text = formatPlayers(data.players, data.max) end
        end
    end
end

local function removeEntry(jobId)
    local e = Entries[jobId]
    if not e then return end
    if e.frame then pcall(function() e.frame:Destroy() end) end
    Entries[jobId] = nil
    for i=#Order,1,-1 do if Order[i]==jobId then table.remove(Order,i) break end end
end

local function refreshListVisual()
    -- сортируем: сперва по mps (по убыв.), затем по свежести
    table.sort(Order, function(a,b)
        local ea, eb = Entries[a], Entries[b]
        if not ea or not eb then return a<b end
        if ea.data.mps ~= eb.data.mps then return ea.data.mps > eb.data.mps end
        return ea.lastSeen > eb.lastSeen
    end)
    for idx, jobId in ipairs(Order) do
        local e = Entries[jobId]
        if e and e.frame and e.frame.Parent == scroll then
            e.frame.LayoutOrder = idx
            -- свежесть: новая — легкая зелёная подсветка, старая — немного темнее
            local age = os.clock() - e.firstSeen
            local alpha = 0.0
            if age <= FRESH_AGE_SEC then
                alpha = 0.0
                e.frame.BackgroundColor3 = Color3.fromRGB(22, 28, 26) -- чуть зеленит фон для «новых»
            else
                e.frame.BackgroundColor3 = COLORS.surface
                local staleness = math.clamp((os.clock()-e.lastSeen)/ENTRY_TTL_SEC, 0, 1)
                e.frame.BackgroundTransparency = ALPHA.panel + 0.05*staleness
            end
        end
    end
    task.defer(function() scroll.CanvasSize=UDim2.new(0,0,0,listLay.AbsoluteContentSize.Y+10) end)
end

local function parseAll(text)
    local now = os.clock()
    for line in tostring(text or ""):gmatch("(.-)\n") do
        if line:match("%S") then
            local d = parseLine(line)
            if d then
                if visibleByFilters(d) then
                    updateEntry(d.jobId, d)
                end
            end
        end
    end
    -- чистим устаревшие
    for jobId, e in pairs(Entries) do
        if (now - e.lastSeen) > ENTRY_TTL_SEC then
            removeEntry(jobId)
        end
    end
    refreshListVisual()
end

local function pullOnce()
    local url = buildURL()
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body)=="string" and #body>0 then
        parseAll(body.."\n") -- гарантируем финальный \n
    end
end

-- ====== Poll loop ======
task.spawn(function()
    while gui and gui.Parent do
        -- фильтры могли измениться → лёгкая ресинхронизация:
        pullOnce()
        task.wait(PULL_INTERVAL_SEC)
    end
end)

-- ====== Show/Hide + drag ======
local function makeDraggable(frame, handle)
    handle=handle or frame
    local dragging=false; local startPos; local startMouse
    handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; startPos=frame.Position; startMouse=input.Position
            input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local d=input.Position-startMouse
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
        end
    end)
end

local opened=true
local function setVisible(v,instant)
    opened=v; if v then setBlur(true) else setBlur(false) end
    local goal=v and UDim2.new(0.5,-490,0.5,-280) or UDim2.new(0.5,-490,1,30)
    if instant then main.Position=goal; main.Visible=v
    else
        if v then main.Visible=true end
        local t=TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=goal})
        t:Play(); if not v then t.Completed:Wait(); main.Visible=false end
    end
end
UIS.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode==FIXED_HOTKEY then setVisible(not opened,false) end
end)
makeDraggable(main, header)

task.defer(function() updateLeftCanvas(); setVisible(true,true) end)
