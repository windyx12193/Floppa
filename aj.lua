--[[
  FLOPPA AUTO JOINER v5.2 (robust)
  • Фиолетовый GUI, лёгкий блюр, хоткей T
  • AUTO INJECT: очередь с ретраями в бутстрапе + keep-alive + хук на Teleport
  • Локальный конфиг: floppa_aj/config.txt (минимальный текст)
]]

---------------- USER SETTINGS ----------------
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY    = Enum.KeyCode.T
------------------------------------------------

local function log(...) print("[Floppa]", ...) end
local function err(...) warn("[Floppa][ERR]", ...) end

local ok_main, topErr = pcall(function()
    -- ==== Services ====
    local Players      = game:GetService("Players")
    local UIS          = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")

    -- =================================================================================
    -- CONFIG (plain text, maximum compatibility)
    -- =================================================================================
    local CFG_DIR = "floppa_aj"                  -- <— корень экзекутора
    local CFG_TXT = CFG_DIR .. "/config.txt"

    local function hasFS()
        return typeof(writefile)=="function"
            and typeof(readfile)=="function"
            and typeof(isfile)=="function"
            and typeof(makefolder)=="function"
    end

    if hasFS() then pcall(makefolder, CFG_DIR) end

    local function cfg_compose(cfg)
        return table.concat({
            "MIN M/S = "..tostring(cfg.MinMS or 0),
            "A/J = "..tostring(cfg.AutoJoin and true or false),
            "JOIN RETRY = "..tostring(cfg.JoinRetry or 0),
            "ENABLE IGNORE LIST = "..tostring(cfg.IgnoreEnabled and true or false),
            "IGNORE NAMES ='"..table.concat(cfg.IgnoreNames or {}, ",").."'",
            "AUTO INJECT = "..tostring(cfg.AutoInject and true or false),
            ""
        },"\n")
    end

    local function cfg_parse(txt)
        local cfg = {MinMS=100, AutoJoin=false, JoinRetry=50, IgnoreEnabled=false, IgnoreNames={}, AutoInject=false}
        for line in (txt.."\n"):gmatch("(.-)\n") do
            local k,v = line:match("^%s*([%w%s/]+)%s*=%s*(.-)%s*$")
            if k and v then
                k = k:gsub("%s+"," "):upper()
                if k=="MIN M/S" then
                    cfg.MinMS = tonumber(v) or cfg.MinMS
                elseif k=="A/J" then
                    cfg.AutoJoin = (v=="true" or v=="True")
                elseif k=="JOIN RETRY" then
                    cfg.JoinRetry = tonumber(v) or cfg.JoinRetry
                elseif k=="ENABLE IGNORE LIST" then
                    cfg.IgnoreEnabled = (v=="true" or v=="True")
                elseif k=="IGNORE NAMES" then
                    local s = v:gsub("^'%s*", ""):gsub("%s*'$", "")
                    cfg.IgnoreNames = {}
                    for tok in s:gmatch("([^,%s]+)") do cfg.IgnoreNames[#cfg.IgnoreNames+1]=tok end
                elseif k=="AUTO INJECT" then
                    cfg.AutoInject = (v=="true" or v=="True")
                end
            end
        end
        return cfg
    end

    local function cfg_save(cfg)
        if not hasFS() then return false end
        local ok, e = pcall(writefile, CFG_TXT, cfg_compose(cfg))
        if not ok then err("writefile:", e) end
        return ok
    end

    local function cfg_load()
        if not hasFS() or not isfile(CFG_TXT) then return nil end
        local ok, txt = pcall(readfile, CFG_TXT)
        if not ok or type(txt)~="string" then return nil end
        return cfg_parse(txt)
    end

    -- =================================================================================
    -- GUI helpers / style
    -- =================================================================================
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

    local function roundify(obj, px)
        local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0, px or 10); c.Parent=obj; return c
    end
    local function stroke(obj, col, th, tr)
        local s=Instance.new("UIStroke"); s.Color=col or COLORS.stroke; s.Thickness=th or 1; s.Transparency=tr or 0.25; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=obj; return s
    end
    local function padding(obj, l,t,r,b)
        local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,l or 0); p.PaddingTop=UDim.new(0,t or 0); p.PaddingRight=UDim.new(0,r or 0); p.PaddingBottom=UDim.new(0,b or 0); p.Parent=obj; return p
    end
    local function setFont(lbl, weight)
        local ok=pcall(function()
            if weight=="bold" then lbl.Font=Enum.Font.GothamBold
            elseif weight=="medium" then lbl.Font=Enum.Font.GothamMedium
            else lbl.Font=Enum.Font.Gotham end
        end)
        if not ok then lbl.Font=(weight=="bold") and Enum.Font.SourceSansBold or Enum.Font.SourceSans end
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
        mkLabel(h, text, 18, "bold", COLORS.textPrimary).Size=UDim2.new(1,0,1,0)
        return h
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

    local function getGuiParent()
        local okH, hui = pcall(function() return gethui and gethui() end)
        if okH and hui then return hui end
        local okC, core = pcall(function() return game:GetService("CoreGui") end)
        if okC then return core end
        return Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    -- cleanup previous instance if exists
    do
        local par = getGuiParent()
        local old = par:FindFirstChild("FloppaAutoJoinerGui")
        if old then pcall(function() old:Destroy() end) end
        pcall(function() if getgenv then getgenv().__FLOPPA_UI_ACTIVE=nil end end)
    end

    -- ==== Blur (light) ====
    local blur=Lighting:FindFirstChild("FloppaLightBlur") or Instance.new("BlurEffect")
    blur.Name="FloppaLightBlur"; blur.Size=0; blur.Enabled=false; blur.Parent=Lighting
    local function setBlur(e)
        if e then
            blur.Enabled=true
            TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=4}):Play()
        else
            TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=0}):Play()
            task.delay(0.16,function() blur.Enabled=false end)
        end
    end

    -- =================================================================================
    -- Build GUI
    -- =================================================================================
    local parent = getGuiParent()
    local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=1e6; gui.Parent=parent

    local main=Instance.new("Frame"); main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(0.5,-490,0.5,-280)
    main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui
    roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, 0.35); padding(main,10,10,10,10)

    local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
    roundify(header,10); stroke(header); padding(header,14,6,14,6)
    mkLabel(header,"FLOPPA AUTO JOINER v5.2",20,"bold",COLORS.textPrimary).Size=UDim2.new(0.7,0,1,0)
    local hk=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak); hk.AnchorPoint=Vector2.new(1,0.5); hk.Position=UDim2.new(1,-14,0.5,0); hk.Size=UDim2.new(0.28,0,1,0); hk.TextXAlignment=Enum.TextXAlignment.Right

    local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1
    left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
    local leftPad=padding(left,0,0,0,10)
    local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
    local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
    leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

    local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
    right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main
    roundify(right,12); stroke(right); padding(right,12,12,12,12)

    -- Left controls
    mkHeader(left,"PRIORITY ACTIONS")
    local _, st_AutoJoin, apply_AutoJoin = mkToggle(left, "AUTO JOIN", false)
    local _, st_JoinRetry, box_JoinRetry = mkStackInput(left, "JOIN RETRY", "50", "50", true)

    mkHeader(left,"MONEY FILTERS")
    local _, st_MinMS, box_MinMS = mkStackInput(left, "MIN M/S", "100", "100", true)

    mkHeader(left,"НАСТРОЙКИ")
    local _, st_AutoInject, apply_AutoInject = mkToggle(left, "AUTO INJECT", false)
    local _, st_IgnoreEn, apply_IgnoreEn     = mkToggle(left, "ENABLE IGNORE LIST", false)
    local _, st_IgnoreNames, box_IgnoreNames = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", "", false)

    -- Right (пример списка)
    mkHeader(right,"AVAILABLE LOBBIES").Size=UDim2.new(1,0,0,40)

    -- =================================================================================
    -- STATE + persistence
    -- =================================================================================
    local State = {
        MinMS=100, AutoJoin=false, JoinRetry=50,
        IgnoreEnabled=false, IgnoreNames={}, AutoInject=false
    }
    do
        local cfg = cfg_load()
        if cfg then State = cfg end
    end

    -- apply to UI (instant)
    local function applyAll()
        apply_AutoJoin(State.AutoJoin, true)
        apply_AutoInject(State.AutoInject, true)
        apply_IgnoreEn(State.IgnoreEnabled, true)
        box_JoinRetry.Text  = tostring(State.JoinRetry)
        box_MinMS.Text      = tostring(State.MinMS)
        box_IgnoreNames.Text= table.concat(State.IgnoreNames, ",")
    end
    applyAll()

    local function persist() cfg_save(State) end

    -- on-change => save
    st_AutoJoin.Changed   = function(v) State.AutoJoin=v; persist() end
    st_AutoInject.Changed = function(v) State.AutoInject=v; persist() end
    st_IgnoreEn.Changed   = function(v) State.IgnoreEnabled=v; persist() end
    box_JoinRetry.FocusLost:Connect(function() State.JoinRetry=tonumber(box_JoinRetry.Text) or State.JoinRetry; persist() end)
    box_MinMS.FocusLost:Connect(function() State.MinMS=tonumber(box_MinMS.Text) or State.MinMS; persist() end)
    st_IgnoreNames.Changed= function(s)
        State.IgnoreNames={}
        for tok in (s or ""):gmatch("([^,%s]+)") do State.IgnoreNames[#State.IgnoreNames+1]=tok end
        persist()
    end

    -- =================================================================================
    -- AUTO INJECT (robust queue + keep-alive + teleport hook)
    -- =================================================================================
    local function pickQueue()
        local q=nil
        pcall(function() if syn and type(syn.queue_on_teleport)=="function" then q=syn.queue_on_teleport end end)
        if not q and type(queue_on_teleport)=="function" then q=queue_on_teleport end
        if not q and type(queueteleport)=="function" then q=queueteleport end
        if not q and type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then q=fluxus.queue_on_teleport end
        return q
    end

    -- Мини-бутстрап с ретраями до 30с (на новом сервере)
    local function makeBootstrap(url)
        url = tostring(url or "")
        local s=""
        s=s.."task.spawn(function()\n"
        s=s.."  if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end\n"
        s=s.."  local okP,Pl=pcall(function() return game:GetService('Players') end)\n"
        s=s.."  if okP and Pl then local t0=os.clock(); while not Pl.LocalPlayer and os.clock()-t0<15 do task.wait(0.05) end end\n"
        s=s.."  pcall(function() getgenv().__FLOPPA_UI_ACTIVE=nil end)\n"
        s=s.."  local deadline=os.clock()+30\n"
        s=s.."  while os.clock()<deadline do\n"
        s=s.."    local ok,res=pcall(function() return game:HttpGet('"..AUTO_INJECT_URL.."') end)\n"
        s=s.."    if ok and type(res)=='string' and #res>0 then local f=loadstring(res); if f then local ok2,er=pcall(f); if ok2 then break end end end\n"
        s=s.."    task.wait(3)\n"
        s=s.."  end\n"
        s=s.."end)\n"
        return s
    end

    local lastQueued = 0
    local function safeQueue(url, reason)
        local q = pickQueue()
        if not q or not url or url=="" then
            err("queue_on_teleport недоступен или URL пуст")
            return
        end
        lastQueued = os.clock()
        q(makeBootstrap(url))
        log("queued ("..(reason or "?")..")")
    end

    -- queue on startup + keep-alive refresher
    task.defer(function()
        if State.AutoInject then
            safeQueue(AUTO_INJECT_URL, "startup")
            -- keep-alive (на случай, если экзекутор теряет очередь)
            task.spawn(function()
                while gui and gui.Parent and State.AutoInject do
                    if os.clock() - lastQueued > 12 then
                        safeQueue(AUTO_INJECT_URL, "keepalive")
                    end
                    task.wait(4)
                end
            end)
        end
    end)

    -- queue again right before teleport
    Players.LocalPlayer.OnTeleport:Connect(function(st)
        if State.AutoInject and st==Enum.TeleportState.Started then
            safeQueue(AUTO_INJECT_URL, "teleport")
        end
    end)

    -- =================================================================================
    -- Show/Hide (T) + Drag
    -- =================================================================================
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
    local function setVisible(v, instant)
        opened=v
        if v then
            -- ВАЖНО: показываем GUI при каждом старте
            TweenService:Create(Lighting, TweenInfo.new(0, Enum.EasingStyle.Linear), {}):Play()
            setBlur(true)
        else
            setBlur(false)
        end
        local goal=v and UDim2.new(0.5,-490,0.5,-280) or UDim2.new(0.5,-490,1,30)
        if instant then
            main.Position=goal; main.Visible=v
        else
            if v then main.Visible=true end
            local t=TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=goal})
            t:Play(); if not v then t.Completed:Wait(); main.Visible=false end
        end
    end
    UIS.InputBegan:Connect(function(input,gp)
        if not gp and input.KeyCode==FIXED_HOTKEY then setVisible(not opened,false) end
    end)
    makeDraggable(main, header)

    -- автопоказ при запуске
    task.defer(function() updateLeftCanvas(); setVisible(true,true) end)
end)

if not ok_main then
    warn("[Floppa][FATAL]", topErr)
end
