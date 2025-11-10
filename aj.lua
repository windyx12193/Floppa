

---------------------- НАСТРОЙКИ ----------------------
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"   -- <== ВСТАВЬ сюда свой raw URL (иначе Auto Inject ничего не загрузит)
local DEFAULT_HOTKEY  = Enum.KeyCode.K
-------------------------------------------------------

-- Сервисы
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")

local player   = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Палитра
local COLORS = {
    purpleDeep   = Color3.fromRGB(96, 63, 196),
    purple       = Color3.fromRGB(134, 102, 255),
    purpleSoft   = Color3.fromRGB(160, 135, 255),
    surface      = Color3.fromRGB(18, 18, 22),
    surface2     = Color3.fromRGB(26, 26, 32),
    textPrimary  = Color3.fromRGB(238, 238, 245),
    textWeak     = Color3.fromRGB(190, 190, 200),
    on           = Color3.fromRGB(64, 222, 125),
    off          = Color3.fromRGB(120, 120, 130),
    joinBtn      = Color3.fromRGB(67, 232, 113),
    stroke       = Color3.fromRGB(70, 60, 140)
}
local ALPHA = { panel = 0.12, card = 0.18 }

-- Утилиты UI
local function roundify(i, px) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,px or 10); c.Parent=i; return c end
local function stroke(i, col, th, tr) local s=Instance.new("UIStroke"); s.Thickness=th or 1; s.Color=col or COLORS.stroke; s.Transparency=tr or .25; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=i; return s end
local function padding(i,l,t,r,b) local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,l or 0); p.PaddingTop=UDim.new(0,t or 0); p.PaddingRight=UDim.new(0,r or 0); p.PaddingBottom=UDim.new(0,b or 0); p.Parent=i; return p end
local function label(parent, text, size, weight, color)
    local lbl=Instance.new("TextLabel"); lbl.BackgroundTransparency=1; lbl.Text=text
    lbl.FontFace=Font.fromEnum(Enum.Font.Gotham); lbl.TextSize=size or 18; lbl.TextColor3=color or COLORS.textPrimary
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.RichText=true
    if weight=="bold" then lbl.FontFace=Font.new(lbl.FontFace.Family, Enum.FontWeight.Bold)
    elseif weight=="medium" then lbl.FontFace=Font.new(lbl.FontFace.Family, Enum.FontWeight.Medium) end
    lbl.Parent=parent; return lbl
end
local function makeHeader(parent, text)
    local h=Instance.new("Frame"); h.BackgroundColor3=COLORS.surface2; h.BackgroundTransparency=ALPHA.card; h.Size=UDim2.new(1,0,0,38)
    h.Parent=parent; roundify(h,8); stroke(h); padding(h,12,6,12,6)
    local g=Instance.new("UIGradient"); g.Color=ColorSequence.new{ColorSequenceKeypoint.new(0,COLORS.purpleDeep),ColorSequenceKeypoint.new(1,COLORS.purple)}
    g.Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(1,.4)}; g.Rotation=90; g.Parent=h
    local t=label(h,text,18,"bold"); t.Size=UDim2.new(1,0,1,0); t.TextTransparency=0.05; return h
end

-- Тумблер
local function makeToggle(parent, text, default)
    local row=Instance.new("Frame"); row.Name=text.."_Row"; row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
    row.Size=UDim2.new(1,0,0,44); row.Parent=parent; roundify(row,10); stroke(row); padding(row,12,0,12,0)
    local lbl=label(row,text,17,"medium",COLORS.textPrimary); lbl.Size=UDim2.new(1,-80,1,0)

    local sw=Instance.new("TextButton"); sw.AutoButtonColor=false; sw.Text=""
    sw.BackgroundColor3=Color3.fromRGB(40,40,48); sw.BackgroundTransparency=.2; sw.Size=UDim2.new(0,62,0,28)
    sw.AnchorPoint=Vector2.new(1,.5); sw.Position=UDim2.new(1,-6,.5,0); sw.Parent=row
    roundify(sw,14); stroke(sw, COLORS.purpleSoft, 1, .35)

    local dot=Instance.new("Frame"); dot.Size=UDim2.new(0,24,0,24); dot.Position=UDim2.new(0,2,.5,-12); dot.BackgroundColor3=COLORS.off
    dot.Parent=sw; roundify(dot,12)

    local state={Value=default and true or false}
    local function apply(v,instant)
        state.Value=v
        local pos=v and UDim2.new(1,-26,.5,-12) or UDim2.new(0,2,.5,-12)
        local col=v and COLORS.on or COLORS.off
        if instant then
            dot.Position=pos; dot.BackgroundColor3=col
            sw.BackgroundColor3=v and Color3.fromRGB(55,58,74) or Color3.fromRGB(40,40,48)
        else
            TweenService:Create(dot,TweenInfo.new(.13,Enum.EasingStyle.Sine),{Position=pos}):Play()
            TweenService:Create(dot,TweenInfo.new(.12,Enum.EasingStyle.Sine),{BackgroundColor3=col}):Play()
            TweenService:Create(sw,TweenInfo.new(.12,Enum.EasingStyle.Sine),{BackgroundColor3=v and Color3.fromRGB(55,58,74) or Color3.fromRGB(40,40,48)}):Play()
        end
    end
    apply(state.Value,true)
    sw.MouseButton1Click:Connect(function() apply(not state.Value); if state.Changed then pcall(state.Changed,state.Value) end end)
    return row, state
end

-- Вертикальный инпут (заголовок сверху, поле ниже). Без подсказок.
local function makeStackedInput(parent, title, placeholder, defaultText, isNumeric)
    local row=Instance.new("Frame"); row.Name=title.."_Stacked"; row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
    row.Size=UDim2.new(1,0,0,70); row.Parent=parent; roundify(row,10); stroke(row); padding(row,12,8,12,12)

    local top=label(row, title, 16, "medium", COLORS.textPrimary)
    top.Size=UDim2.new(1, 0, 0, 18)

    local box=Instance.new("TextBox")
    box.PlaceholderText = placeholder or ""
    box.Text = defaultText or ""
    box.ClearTextOnFocus=false
    box.FontFace=Font.fromEnum(Enum.Font.Gotham)
    box.TextSize=17
    box.TextColor3=COLORS.textPrimary
    box.PlaceholderColor3=COLORS.textWeak
    box.BackgroundColor3=Color3.fromRGB(32,32,38)
    box.BackgroundTransparency=0.15
    box.Size=UDim2.new(1, 0, 0, 30)
    box.Position=UDim2.new(0, 0, 0, 30)
    roundify(box,8); stroke(box, COLORS.purpleSoft, 1, .35)
    box.Parent=row

    if isNumeric then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            box.Text = box.Text:gsub("[^%d]", "")
        end)
    end

    local state={}
    box.FocusLost:Connect(function()
        state.Value = isNumeric and (tonumber(box.Text) or 0) or box.Text
        if state.Changed then pcall(state.Changed, state.Value) end
    end)

    return row, state, box
end

-- Перетаскивание окна
local function makeDraggable(frame, handle)
    handle=handle or frame
    local dragging=false; local startPos; local startInputPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; startPos=frame.Position; startInputPos=input.Position
            input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local d=input.Position-startInputPos
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
end

-- Лёгкий блюр
local blur=Lighting:FindFirstChild("FloppaLightBlur") or Instance.new("BlurEffect")
blur.Name="FloppaLightBlur"; blur.Size=0; blur.Enabled=false; blur.Parent=Lighting
local function setBlur(e)
    if e then blur.Enabled=true; TweenService:Create(blur,TweenInfo.new(.15,Enum.EasingStyle.Sine),{Size=4}):Play()
    else TweenService:Create(blur,TweenInfo.new(.15,Enum.EasingStyle.Sine),{Size=0}):Play(); task.delay(.16,function() blur.Enabled=false end) end
end

---------------------- GUI ----------------------
local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.Parent=playerGui

local main=Instance.new("Frame")
main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(.5,-490,.5,-280)
main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui
roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, .35); padding(main,10,10,10,10)

-- Шапка
local CURRENT_HOTKEY = DEFAULT_HOTKEY
local header=Instance.new("Frame")
header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card
header.Parent=main; roundify(header,10); stroke(header); padding(header,14,6,14,6)

local title=label(header,"FLOPPA AUTO JOINER",20,"bold"); title.Size=UDim2.new(1,-220,1,0)
local hotkeyInfo=label(header,"OPEN GUI KEY  ",16,"medium",COLORS.textWeak)
hotkeyInfo.AnchorPoint=Vector2.new(1,.5); hotkeyInfo.Position=UDim2.new(1,-60,.5,0)
hotkeyInfo.Size=UDim2.new(0,220,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right

-- Плашка ребинда
local keyButton=Instance.new("TextButton")
keyButton.Size=UDim2.new(0,36,0,32); keyButton.AnchorPoint=Vector2.new(1,.5); keyButton.Position=UDim2.new(1,-18,.5,0)
keyButton.BackgroundColor3=COLORS.surface; keyButton.BackgroundTransparency=.1; keyButton.Text=""; keyButton.AutoButtonColor=false
keyButton.Parent=header; roundify(keyButton,8); stroke(keyButton, COLORS.purple, 1, .4)
local keyLbl=label(keyButton, CURRENT_HOTKEY.Name, 18, "bold"); keyLbl.Size=UDim2.new(1,0,1,0); keyLbl.TextXAlignment=Enum.TextXAlignment.Center

-- Левая колонка (скролл)
local left=Instance.new("ScrollingFrame")
left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58)
left.BackgroundTransparency=1; left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y
left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
local leftPad = padding(left, 0, 0, 0, 10)
local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

-- Правая панель
local right=Instance.new("Frame")
right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card
right.Parent=main; roundify(right,12); stroke(right); padding(right,12,12,12,12)

-- Левая колонка: блоки
makeHeader(left,"PRIORITY ACTIONS")
local autoJoinRow, autoJoin = makeToggle(left,"AUTO JOIN",false)
local jrRow, joinRetryState = makeStackedInput(left,"JOIN RETRY","50","50", true)

makeHeader(left,"MONEY FILTERS")
local msRow, minMSState    = makeStackedInput(left,"MIN M/S","100","100", true)

makeHeader(left,"НАСТРОЙКИ")
local autoInjectRow, autoInject = makeToggle(left,"AUTO INJECT",false)
local ignoreListRow, ignoreToggle = makeToggle(left,"ENABLE IGNORE LIST",false)

local ignoreRow, ignoreState, ignoreBox =
    makeStackedInput(left,"IGNORE NAMES","name1,name2,...","", false)

-- Правая колонка: список
local listHeader=makeHeader(right,"AVAILABLE LOBBIES"); listHeader.Size=UDim2.new(1,0,0,40)
local scroll=Instance.new("ScrollingFrame")
scroll.BackgroundTransparency=1; scroll.Size=UDim2.new(1,0,1,-50); scroll.Position=UDim2.new(0,0,0,46)
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.ScrollBarThickness=6; scroll.Parent=right
local listLay=Instance.new("UIListLayout"); listLay.SortOrder=Enum.SortOrder.LayoutOrder; listLay.Padding=UDim.new(0,8); listLay.Parent=scroll

local function addLobbyItem(nameText, moneyPerSec)
    local item=Instance.new("Frame"); item.Size=UDim2.new(1,-6,0,52); item.BackgroundColor3=COLORS.surface; item.BackgroundTransparency=ALPHA.panel
    item.Parent=scroll; roundify(item,10); stroke(item, COLORS.purpleSoft, 1, .35); padding(item,12,6,12,6)
    local nameLbl=label(item,string.upper(nameText),18,"bold"); nameLbl.Size=UDim2.new(0.5,-10,1,0)
    local moneyLbl=label(item,string.upper(moneyPerSec),17,"medium",Color3.fromRGB(130,255,130))
    moneyLbl.AnchorPoint=Vector2.new(.5,.5); moneyLbl.Position=UDim2.new(.62,0,.5,0); moneyLbl.Size=UDim2.new(.34,0,1,0); moneyLbl.TextXAlignment=Enum.TextXAlignment.Center
    local joinBtn=Instance.new("TextButton"); joinBtn.Text="JOIN"; joinBtn.FontFace=Font.fromEnum(Enum.Font.GothamBold); joinBtn.TextSize=18
    joinBtn.TextColor3=Color3.fromRGB(22,22,22); joinBtn.AutoButtonColor=true; joinBtn.BackgroundColor3=COLORS.joinBtn
    joinBtn.Size=UDim2.new(0,84,0,36); joinBtn.AnchorPoint=Vector2.new(1,.5); joinBtn.Position=UDim2.new(1,-8,.5,0)
    roundify(joinBtn,10); stroke(joinBtn, Color3.fromRGB(0,0,0), 1, .7); joinBtn.Parent=item
    joinBtn.MouseButton1Click:Connect(function() print("[JOIN] ->", nameText) end)
    task.defer(function() scroll.CanvasSize=UDim2.new(0,0,0,listLay.AbsoluteContentSize.Y+10) end)
end
for i=1,12 do addLobbyItem("BRAINROT NAME "..i,"MONEY/SECOND") end

-- Состояние
local State = {
    AutoJoin       = false,
    AutoInject     = false,
    IgnoreEnabled  = false,
    JoinRetry      = tonumber((jrRow:FindFirstChildOfClass("TextBox") or {Text="50"}).Text) or 50,
    MinMS          = tonumber((msRow:FindFirstChildOfClass("TextBox") or {Text="100"}).Text) or 100,
    IgnoreNames    = {}
}
local function parseIgnore(t) local r={} for token in string.gmatch(t or "","([^,%s]+)") do table.insert(r,token) end return r end
autoJoin.Changed      = function(v) State.AutoJoin=v end
ignoreToggle.Changed  = function(v) State.IgnoreEnabled=v end
(jrRow:FindFirstChildOfClass("TextBox")).FocusLost:Connect(function(b) State.JoinRetry = tonumber((jrRow:FindFirstChildOfClass("TextBox")).Text) or State.JoinRetry end)
(msRow:FindFirstChildOfClass("TextBox")).FocusLost:Connect(function(b) State.MinMS   = tonumber((msRow:FindFirstChildOfClass("TextBox")).Text) or State.MinMS   end)
ignoreState.Changed   = function(text) State.IgnoreNames=parseIgnore(text) end

---------------------- AUTO INJECT (с вшитым URL) ----------------------
-- На многих экзекуторах очередь должна получить готовую строку, которая сама знает URL.
local function pickQueueFn()
    local f
    pcall(function() if syn and type(syn.queue_on_teleport)=="function" then f=syn.queue_on_teleport end end)
    if not f and type(queue_on_teleport)=="function" then f=queue_on_teleport end
    if not f and type(queueteleport)=="function" then f=queueteleport end
    if not f and type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then f=fluxus.queue_on_teleport end
    return f
end

local function makeBootstrap(url)
    -- Вшиваем URL внутрь — не зависим от getgenv на новом сервере.
    url = tostring(url or "")
    local code = ([[task.spawn(function()
        local function safeget(u)
            for i=1,3 do
                local ok,res = pcall(function() return game:HttpGet(u) end)
                if ok and type(res)=="string" and #res>0 then return res end
                task.wait(1)
            end
        end
        if #"%s" > 0 then
            local src = safeget("%s")
            if src then local f=loadstring(src); if f then pcall(f) end end
        end
    end)]]):format(url, url)
    return code
end

local queuedCooldown = false
local function queueReinjectNow()
    local q = pickQueueFn()
    if q then
        q(makeBootstrap(AUTO_INJECT_URL))
        print("[Floppa] AutoInject queued.")
    else
        -- Если скрипт стоит LocalScript'ом в StarterPlayerScripts — он и так перезапустится.
        print("[Floppa] queue_on_teleport не найден (вероятно LocalScript/Studio).")
    end
end

local function setAutoInject(v)
    State.AutoInject = v
    if v then
        if AUTO_INJECT_URL == "" then
            warn("[Floppa] Укажи AUTO_INJECT_URL вверху файла — без него нечего инжектить.")
            return
        end
        if not queuedCooldown then
            queuedCooldown = true
            queueReinjectNow()
            task.delay(2, function() queuedCooldown = false end)
        end
    end
end
autoInject.Changed = setAutoInject

Players.LocalPlayer.OnTeleport:Connect(function(tpState)
    if State.AutoInject and tpState == Enum.TeleportState.Started and not queuedCooldown then
        queuedCooldown = true
        queueReinjectNow()
        task.delay(2, function() queuedCooldown = false end)
    end
end)

---------------------- ОТКРЫТИЕ/СКРЫТИЕ + РЕБАЙНД ----------------------
local opened=true
local function setVisible(v, instant)
    opened=v; if v then setBlur(true) else setBlur(false) end
    local goal=v and UDim2.new(.5,-490,.5,-280) or UDim2.new(.5,-490,1,30)
    if instant then main.Position=goal; main.Visible=v
    else
        if v then main.Visible=true end
        local t=TweenService:Create(main,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=goal})
        t:Play(); if not v then t.Completed:Wait(); main.Visible=false end
    end
end

local rebinding=false; local keyStroke=keyButton:FindFirstChildWhichIsA("UIStroke")
local function setRebindVisual(a)
    if not keyStroke then return end
    if a then TweenService:Create(keyStroke,TweenInfo.new(.15,Enum.EasingStyle.Sine),{Transparency=.05}):Play(); keyLbl.Text="Press..."
    else TweenService:Create(keyStroke,TweenInfo.new(.15,Enum.EasingStyle.Sine),{Transparency=.4}):Play(); keyLbl.Text=CURRENT_HOTKEY.Name end
end
keyButton.MouseButton1Click:Connect(function() if not rebinding then rebinding=true; setRebindVisual(true) end end)
UIS.InputBegan:Connect(function(input,gp)
    if rebinding and input.UserInputType==Enum.UserInputType.Keyboard then
        if input.KeyCode==Enum.KeyCode.Escape then rebinding=false; setRebindVisual(false); return end
        if input.KeyCode~=Enum.KeyCode.Unknown then CURRENT_HOTKEY=input.KeyCode; rebinding=false; setRebindVisual(false) end
        return
    end
    if not gp and input.KeyCode==CURRENT_HOTKEY then setVisible(not opened,false) end
end)

makeDraggable(main, header)
task.defer(function() updateLeftCanvas(); setVisible(true,true) end)

-- Доступно из State: AutoJoin, AutoInject, IgnoreEnabled, JoinRetry, MinMS, IgnoreNames
