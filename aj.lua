--[[
  FLOPPA AUTO JOINER - Luau-safe v4.6 (with JSON config)
  • Горячая клавиша фиксирована: T (англ.), ребинда нет
  • Надёжный авто-реинжект: только queue_on_teleport (без "run now")
  • Bootstrap ждёт game:IsLoaded() и LocalPlayer, сбрасывает __FLOPPA_UI_ACTIVE → без дублей и крашей
  • Сохранение настроек (кроме хоткея) в JSON, если writefile/readfile доступны
]]

------------------ USER SETTINGS ------------------
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY    = Enum.KeyCode.T
local SETTINGS_PATH   = "floppa_aj_settings.json"
---------------------------------------------------

-- === FS helpers ===
local HttpService = game:GetService("HttpService")
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

-- === Singleton-friendly очистка ===
local Players = game:GetService("Players")
local function findGuiParent()
    local okH, hui = pcall(function() return gethui and gethui() end)
    if okH and hui then return hui end
    local okC, core = pcall(function() return game:GetService("CoreGui") end)
    if okC then return core end
    return Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui") or nil
end
do
    local parent = findGuiParent()
    if parent then
        local old = parent:FindFirstChild("FloppaAutoJoinerGui")
        if old then pcall(function() old:Destroy() end) end
    end
    local G = (getgenv and getgenv()) or _G
    G.__FLOPPA_UI_ACTIVE = true -- информативно
end

-- === Services ===
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local player       = Players.LocalPlayer

-- === Style ===
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

-- === UI helpers ===
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
    local t=mkLabel(h, text, 18, "bold", COLORS.textPrimary); t.Size=UDim2.new(1,0,1,0); return h
end
local function mkToggle(parent, text, default)
    local row=Instance.new("Frame"); row.Name=text.."_Row"; row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
    row.Size=UDim2.new(1,0,0,44); row.Parent=parent; roundify(row,10); stroke(row); padding(row,12,0,12,0)
    local lbl=mkLabel(row, text, 17, "medium", COLORS.textPrimary); lbl.Size=UDim2.new(1,-80,1,0)
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
    local top=mkLabel(row, title, 16, "medium", COLORS.textPrimary); top.Size=UDim2.new(1,0,0,18)
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

-- === Blur ===
local blur=Lighting:FindFirstChild("FloppaLightBlur") or Instance.new("BlurEffect")
blur.Name="FloppaLightBlur"; blur.Size=0; blur.Enabled=false; blur.Parent=Lighting
local function setBlur(e)
    if e then blur.Enabled=true; TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=4}):Play()
    else TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=0}):Play(); task.delay(0.16,function() blur.Enabled=false end) end
end

-- === Root GUI ===
local parent = findGuiParent() or Players.LocalPlayer:WaitForChild("PlayerGui")
local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=1e6; gui.Parent=parent
local main=Instance.new("Frame"); main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(0.5,-490,0.5,-280)
main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui
roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, 0.35); padding(main,10,10,10,10)

-- === Header (фиксированный хоткей T, без ребинда) ===
local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
roundify(header,10); stroke(header); padding(header,14,6,14,6)
local title=mkLabel(header,"FLOPPA AUTO JOINER",20,"bold",COLORS.textPrimary); title.Size=UDim2.new(0.6,0,1,0)
local hotkeyInfo=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak)
hotkeyInfo.AnchorPoint=Vector2.new(1,0.5); hotkeyInfo.Position=UDim2.new(1,-14,0.5,0); hotkeyInfo.Size=UDim2.new(0.35,0,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right

-- === Left column ===
local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1
left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
local leftPad=padding(left,0,0,0,10)
local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

-- === Right panel ===
local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main
roundify(right,12); stroke(right); padding(right,12,12,12,12)

-- === Blocks ===
mkHeader(left,"PRIORITY ACTIONS")
local autoJoinRow, autoJoin, applyAutoJoin = mkToggle(left, "AUTO JOIN", false)
local jrRow, joinRetryState, jrBox = mkStackInput(left, "JOIN RETRY", "50", "50", true)

mkHeader(left,"MONEY FILTERS")
local msRow, minMSState, msBox = mkStackInput(left, "MIN M/S", "100", "100", true)

mkHeader(left,"НАСТРОЙКИ")
local autoInjectRow, autoInject, applyAutoInject = mkToggle(left, "AUTO INJECT", false)
local ignoreListRow, ignoreToggle, applyIgnoreToggle = mkToggle(left, "ENABLE IGNORE LIST", false)
local ignoreRow, ignoreState, ignoreBox = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", "", false)

-- === Demo list ===
local listHeader=mkHeader(right,"AVAILABLE LOBBIES"); listHeader.Size=UDim2.new(1,0,0,40)

-- === State + persistence ===
local State = {
    AutoJoin=false, AutoInject=false, IgnoreEnabled=false,
    JoinRetry=tonumber(jrBox.Text) or 50,
    MinMS=tonumber(msBox.Text) or 100,
    IgnoreNames={}
}
local LOADING = true
local function parseIgnore(s) local r={} for token in string.gmatch(s or "", "([^,%s]+)") do table.insert(r, token) end return r end
local function joinIgnore(t) return table.concat(t or {}, ",") end

-- загрузка конфига и ПРИМЕНЕНИЕ К UI
do
    local cfg = loadJSON(SETTINGS_PATH)
    if cfg then
        State.AutoJoin      = cfg.AutoJoin and true or false
        State.AutoInject    = cfg.AutoInject and true or false
        State.IgnoreEnabled = cfg.IgnoreEnabled and true or false
        State.JoinRetry     = tonumber(cfg.JoinRetry) or State.JoinRetry
        State.MinMS         = tonumber(cfg.MinMS) or State.MinMS
        State.IgnoreNames   = type(cfg.IgnoreNames)=="table" and cfg.IgnoreNames or State.IgnoreNames

        -- применяем визуально:
        applyAutoJoin(State.AutoJoin, true)
        applyAutoInject(State.AutoInject, true)
        applyIgnoreToggle(State.IgnoreEnabled, true)
        jrBox.Text = tostring(State.JoinRetry)
        msBox.Text = tostring(State.MinMS)
        ignoreBox.Text = joinIgnore(State.IgnoreNames)
    end
end

local function saveSettings()
    if LOADING then return end
    local payload = {
        AutoJoin     = State.AutoJoin,
        AutoInject   = State.AutoInject,
        IgnoreEnabled= State.IgnoreEnabled,
        JoinRetry    = State.JoinRetry,
        MinMS        = State.MinMS,
        IgnoreNames  = State.IgnoreNames,
    }
    saveJSON(SETTINGS_PATH, payload)
end

autoJoin.Changed      = function(v) State.AutoJoin = v; saveSettings() end
autoInject.Changed    = function(v) State.AutoInject = v; saveSettings() end
ignoreToggle.Changed  = function(v) State.IgnoreEnabled = v; saveSettings() end
jrBox.FocusLost:Connect(function() State.JoinRetry = tonumber(jrBox.Text) or State.JoinRetry; saveSettings() end)
msBox.FocusLost:Connect(function() State.MinMS    = tonumber(msBox.Text) or State.MinMS;    saveSettings() end)
ignoreState.Changed   = function(text) State.IgnoreNames = parseIgnore(text); saveSettings() end

LOADING=false; saveSettings()

-- === Auto Inject (Только очередь, без "run now") ===
local function pickQueue()
    local q=nil
    pcall(function() if syn and type(syn.queue_on_teleport)=="function" then q=syn.queue_on_teleport end end)
    if not q and type(queue_on_teleport)=="function" then q=queue_on_teleport end
    if not q and type(queueteleport)=="function" then q=queueteleport end
    if not q and type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then q=fluxus.queue_on_teleport end
    return q
end
local function makeBootstrap(url)
    url = tostring(url or "")
    local s=""
    s=s.."task.spawn(function()\n"
    s=s.."  -- надёжная инициализация\n"
    s=s.."  if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end\n"
    s=s.."  local okP, Pl = pcall(function() return game:GetService('Players') end)\n"
    s=s.."  if okP and Pl then local t0=os.clock(); while not Pl.LocalPlayer and os.clock()-t0<10 do task.wait(0.05) end end\n"
    s=s.."  -- сброс флага, чтобы GUI разрешил перезапуск\n"
    s=s.."  pcall(function() getgenv().__FLOPPA_UI_ACTIVE=nil end)\n"
    s=s.."  local function safeget(u)\n"
    s=s.."    for i=1,3 do\n"
    s=s.."      local ok,res=pcall(function() return game:HttpGet(u) end)\n"
    s=s.."      if ok and type(res)=='string' and #res>0 then return res end\n"
    s=s.."      task.wait(1)\n"
    s=s.."    end\n"
    s=s.."  end\n"
    s=s.."  local src=safeget('"..url.."')\n"
    s=s.."  if src then local f=loadstring(src); if f then pcall(f) end end\n"
    s=s.."end)\n"
    return s
end
local function queueReinject(url)
    local q = pickQueue()
    if q and url~="" then q(makeBootstrap(url)) end
end

-- ставим/снимаем очередь при клике (без немедленного запуска)
autoInject.Changed = function(v)
    State.AutoInject = v; saveSettings()
    -- если включили — очередь уже поставится при следующем телепорте
end

-- При старте, если тумблер был включён — ставим очередь на следующий телепорт
if State.AutoInject then queueReinject(AUTO_INJECT_URL) end

-- Телепорт → ставим очередь ещё раз
player.OnTeleport:Connect(function(st)
    if State.AutoInject and st==Enum.TeleportState.Started then
        queueReinject(AUTO_INJECT_URL)
    end
end)

-- === Show/hide: фиксированный хоткей T ===
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

-- Горячая клавиша: T
UIS.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode==FIXED_HOTKEY then
        setVisible(not opened, false)
    end
end)

-- Drag
makeDraggable(main, header)
task.defer(function() updateLeftCanvas(); setVisible(true,true) end)
