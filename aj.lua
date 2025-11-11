--[[
  FLOPPA AUTO JOINER - Luau-safe v4.4
  • Singleton: один экземпляр GUI
  • AUTO INJECT асинхронно (без фриза), queue_on_teleport
  • Не запускает сам себя, если URL = aj.lua (только queue)
  • Запоминает настройки между серверами через writefile/readfile
    (хоткей, AutoJoin, AutoInject, IgnoreEnabled, JoinRetry, MinMS, IgnoreNames)
]]

------------------ USER SETTINGS ------------------
-- Укажи здесь raw-URL скрипта, который должен авто-запускаться после телепорта.
-- РЕКОМЕНДОВАНО: ДРУГОЙ файл, не этот aj.lua.
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/refs/heads/main/aj.lua"  -- например: "https://raw.githubusercontent.com/user/repo/main/main.lua"
local DEFAULT_HOTKEY  = Enum.KeyCode.K
-- Имя файла, куда сохраняются настройки:
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
    pcall(writefile, path, data)
    return true
end
local function loadJSON(path)
    if not hasFS() or not isfile(path) then return nil end
    local ok, data = pcall(readfile, path)
    if not ok or type(data)~="string" then return nil end
    local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end)
    if not ok2 then return nil end
    return tbl
end

-- === Singleton guard (перезапуск-friendly) ===
local G = (getgenv and getgenv()) or _G
local function findGuiParent()
    local okH, hui = pcall(function() return gethui and gethui() end)
    if okH and hui then return hui end
    local okC, core = pcall(function() return game:GetService("CoreGui") end)
    if okC then return core end
    return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end
do
    local parent = findGuiParent()
    local old = parent:FindFirstChild("FloppaAutoJoinerGui")
    if old then pcall(function() old:Destroy() end) end
    G.__FLOPPA_UI_ACTIVE = true
end

-- === Services ===
local Players      = game:GetService("Players")
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

-- вернём apply-функцию, чтобы можно было программно выставлять состояние
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
    local box=Instance.new("TextBox")
    box.PlaceholderText = placeholder or ""; box.Text = defaultText or ""; box.ClearTextOnFocus=false
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
    handle=handle or frame; local dragging=false; local startPos; local startMouse
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
local parent = findGuiParent()
local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=1e6; gui.Parent=parent
local main=Instance.new("Frame"); main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(0.5,-490,0.5,-280)
main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui; roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, 0.35); padding(main,10,10,10,10)

-- === Header & rebind ===
local CURRENT_HOTKEY = G.__FLOPPA_HOTKEY or DEFAULT_HOTKEY
local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
roundify(header,10); stroke(header); padding(header,14,6,14,6)
local title=mkLabel(header,"FLOPPA AUTO JOINER",20,"bold",COLORS.textPrimary); title.Size=UDim2.new(1,-220,1,0)
local hotkeyInfo=mkLabel(header,"OPEN GUI KEY  ",16,"medium",COLORS.textWeak); hotkeyInfo.AnchorPoint=Vector2.new(1,0.5); hotkeyInfo.Position=UDim2.new(1,-60,0.5,0); hotkeyInfo.Size=UDim2.new(0,220,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right
local keyButton=Instance.new("TextButton"); keyButton.Size=UDim2.new(0,36,0,32); keyButton.AnchorPoint=Vector2.new(1,0.5); keyButton.Position=UDim2.new(1,-18,0.5,0)
keyButton.BackgroundColor3=COLORS.surface; keyButton.BackgroundTransparency=0.1; keyButton.Text=""; keyButton.AutoButtonColor=false; keyButton.Parent=header
roundify(keyButton,8); stroke(keyButton, COLORS.purple, 1, 0.4)
local keyLbl=mkLabel(keyButton, CURRENT_HOTKEY.Name, 18, "bold", COLORS.textPrimary); keyLbl.Size=UDim2.new(1,0,1,0); keyLbl.TextXAlignment=Enum.TextXAlignment.Center

-- === Left column ===
local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1
left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
local leftPad=padding(left,0,0,0,10)
local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

-- === Right panel ===
local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main; roundify(right,12); stroke(right); padding(right,12,12,12,12)

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
local scroll=Instance.new("ScrollingFrame"); scroll.BackgroundTransparency=1; scroll.Size=UDim2.new(1,0,1,-50); scroll.Position=UDim2.new(0,0,0,46)
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.ScrollBarThickness=6; scroll.Parent=right
local listLay=Instance.new("UIListLayout"); listLay.SortOrder=Enum.SortOrder.LayoutOrder; listLay.Padding=UDim.new(0,8); listLay.Parent=scroll
local function addLobbyItem(nameText, moneyPerSec)
    local item=Instance.new("Frame"); item.Size=UDim2.new(1,-6,0,52); item.BackgroundColor3=COLORS.surface; item.BackgroundTransparency=ALPHA.panel
    item.Parent=scroll; roundify(item,10); stroke(item, COLORS.purpleSoft, 1, 0.35); padding(item,12,6,12,6)
    local nameLbl=mkLabel(item, string.upper(nameText), 18, "bold", COLORS.textPrimary); nameLbl.Size=UDim2.new(0.5,-10,1,0)
    local moneyLbl=mkLabel(item, string.upper(moneyPerSec), 17, "medium", Color3.fromRGB(130,255,130))
    moneyLbl.AnchorPoint=Vector2.new(0.5,0.5); moneyLbl.Position=UDim2.new(0.62,0,0.5,0); moneyLbl.Size=UDim2.new(0.34,0,1,0); moneyLbl.TextXAlignment=Enum.TextXAlignment.Center
    local joinBtn=Instance.new("TextButton"); joinBtn.Text="JOIN"; setFont(joinBtn,"bold"); joinBtn.TextSize=18; joinBtn.TextColor3=Color3.fromRGB(22,22,22)
    joinBtn.AutoButtonColor=true; joinBtn.BackgroundColor3=COLORS.joinBtn; joinBtn.Size=UDim2.new(0,84,0,36); joinBtn.AnchorPoint=Vector2.new(1,0.5); joinBtn.Position=UDim2.new(1,-8,0.5,0)
    roundify(joinBtn,10); stroke(joinBtn, Color3.fromRGB(0,0,0), 1, 0.7); joinBtn.Parent=item
    joinBtn.MouseButton1Click:Connect(function() print("[JOIN] ->", nameText) end)
    task.defer(function() scroll.CanvasSize=UDim2.new(0,0,0,listLay.AbsoluteContentSize.Y+10) end)
end
for i=1,10 do addLobbyItem("BRAINROT NAME "..i, "MONEY/SECOND") end

-- === State + persistence ===
local State = {
    AutoJoin=false, AutoInject=false, IgnoreEnabled=false,
    JoinRetry=tonumber(jrBox.Text) or 50,
    MinMS=tonumber(msBox.Text) or 100,
    IgnoreNames={}
}
local LOADING = true  -- флаг, чтобы не триггерить сохранение при первичной инициализации

local function parseIgnore(s) local r={} for token in string.gmatch(s or "", "([^,%s]+)") do table.insert(r, token) end return r end
local function joinIgnore(t) return table.concat(t or {}, ",") end

local function EnumKeyByName(name)
    if not name then return nil end
    local ok, val = pcall(function() return Enum.KeyCode[name] end)
    if ok and val then return val end
    -- fallback: перебор
    for _,kc in ipairs(Enum.KeyCode:GetEnumItems()) do
        if kc.Name == name then return kc end
    end
    return nil
end

local function saveSettings()
    if LOADING then return end
    local payload = {
        Hotkey       = (G.__FLOPPA_HOTKEY or DEFAULT_HOTKEY).Name,
        AutoJoin     = State.AutoJoin,
        AutoInject   = State.AutoInject,
        IgnoreEnabled= State.IgnoreEnabled,
        JoinRetry    = State.JoinRetry,
        MinMS        = State.MinMS,
        IgnoreNames  = State.IgnoreNames,
    }
    saveJSON(SETTINGS_PATH, payload)
end

-- подцепим обработчики, чтобы сохранять на изменения
autoJoin.Changed      = function(v) State.AutoJoin = v; saveSettings() end
autoInject.Changed    = function(v) State.AutoInject = v; saveSettings() end
ignoreToggle.Changed  = function(v) State.IgnoreEnabled = v; saveSettings() end
jrBox.FocusLost:Connect(function() State.JoinRetry = tonumber(jrBox.Text) or State.JoinRetry; saveSettings() end)
msBox.FocusLost:Connect(function() State.MinMS    = tonumber(msBox.Text) or State.MinMS;    saveSettings() end)
ignoreState.Changed   = function(text) State.IgnoreNames = parseIgnore(text); saveSettings() end

-- загрузим сохранённые настройки (если есть)
do
    local cfg = loadJSON(SETTINGS_PATH)
    if cfg then
        -- хоткей
        local hk = EnumKeyByName(cfg.Hotkey)
        if hk then G.__FLOPPA_HOTKEY = hk; CURRENT_HOTKEY = hk; end
        -- тумблеры
        applyAutoJoin(   cfg.AutoJoin     and true or false, true)
        applyAutoInject( cfg.AutoInject   and true or false, true)
        applyIgnoreToggle(cfg.IgnoreEnabled and true or false, true)
        State.AutoJoin      = cfg.AutoJoin and true or false
        State.AutoInject    = cfg.AutoInject and true or false
        State.IgnoreEnabled = cfg.IgnoreEnabled and true or false
        -- поля
        State.JoinRetry = tonumber(cfg.JoinRetry) or State.JoinRetry
        State.MinMS     = tonumber(cfg.MinMS) or State.MinMS
        State.IgnoreNames = type(cfg.IgnoreNames)=="table" and cfg.IgnoreNames or State.IgnoreNames
        jrBox.Text = tostring(State.JoinRetry)
        msBox.Text = tostring(State.MinMS)
        ignoreBox.Text = joinIgnore(State.IgnoreNames)
        keyLbl.Text = (G.__FLOPPA_HOTKEY or DEFAULT_HOTKEY).Name
    end
end
-- первая запись на диск (если файл ещё не создан)
saveSettings()
LOADING = false

-- === Auto Inject (async) ===
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
local function isSelfUrl(url)
    url = string.lower(url or "")
    return string.find(url, "/aj.lua", 1, true) ~= nil
end
local function queueReinject(url)
    local q=pickQueue()
    if q and url~="" then q(makeBootstrap(url)) end
end

local aiBusy=false
autoInject.Changed=function(v)
    State.AutoInject=v; saveSettings()
    if not v or aiBusy then return end
    aiBusy=true
    task.spawn(function()
        if AUTO_INJECT_URL ~= "" then
            if not isSelfUrl(AUTO_INJECT_URL) then
                local ok,src = pcall(function() return game:HttpGet(AUTO_INJECT_URL) end)
                if ok and type(src)=="string" and #src>0 then local f=loadstring(src); if f then pcall(f) end end
            end
            queueReinject(AUTO_INJECT_URL)
        else
            warn("[Floppa] AUTO_INJECT_URL не задан.")
        end
        aiBusy=false
    end)
end
player.OnTeleport:Connect(function(st)
    if State.AutoInject and st==Enum.TeleportState.Started then
        queueReinject(AUTO_INJECT_URL)
    end
end)

-- === Show/hide + rebind (с сохранением хоткея) ===
local opened=true
local function setBlurState(v) if v then setBlur(true) else setBlur(false) end end
local function setVisible(v,instant)
    opened=v; setBlurState(v)
    local goal=v and UDim2.new(0.5,-490,0.5,-280) or UDim2.new(0.5,-490,1,30)
    if instant then main.Position=goal; main.Visible=v
    else
        if v then main.Visible=true end
        local t=TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=goal})
        t:Play(); if not v then t.Completed:Wait(); main.Visible=false end
    end
end

local rebinding=false
local keyStroke=keyButton:FindFirstChildWhichIsA("UIStroke")
local function setRebindVisual(a)
    if not keyStroke then return end
    if a then TweenService:Create(keyStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Transparency=0.05}):Play(); keyLbl.Text="Press..."
    else TweenService:Create(keyStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Transparency=0.4}):Play(); keyLbl.Text=(G.__FLOPPA_HOTKEY or DEFAULT_HOTKEY).Name end
end
keyButton.MouseButton1Click:Connect(function() if not rebinding then rebinding=true; setRebindVisual(true) end end)
UIS.InputBegan:Connect(function(input,gp)
    if rebinding and input.UserInputType==Enum.UserInputType.Keyboard then
        if input.KeyCode==Enum.KeyCode.Escape then rebinding=false; setRebindVisual(false); return end
        if input.KeyCode~=Enum.KeyCode.Unknown then
            G.__FLOPPA_HOTKEY = input.KeyCode
            keyLbl.Text = G.__FLOPPA_HOTKEY.Name
            rebinding=false; setRebindVisual(false)
            saveSettings()
        end
        return
    end
    if not gp and input.KeyCode==(G.__FLOPPA_HOTKEY or DEFAULT_HOTKEY) then setVisible(not opened,false) end
end)

makeDraggable(main, header)
task.defer(function() updateLeftCanvas(); setVisible(true,true) end)
