--[[
  FLOPPA AUTO JOINER - Luau-safe v4.2
  • Без двусмысленного синтаксиса (Ambiguous syntax)
  • Фиолетовая тема, лёгкий блюр, скролл слева, нормальная верстка IGNORE NAMES (заголовок сверху, поле ниже)
  • Ребайнд OPEN GUI KEY по клику (по умолчанию K)
  • AUTO INJECT: запускает указанный RAW-скрипт сразу и ставит в очередь на телепорт
  ----------------------------------------------------------------------
  ОБНОВИТЕ URL НИЖЕ:
]]
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua" -- <-- ПОСТАВЬТЕ сюда свой RAW URL если другой файл

-- ==== Services ====
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")

local player    = Players.LocalPlayer

-- ==== Palette ====
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

-- ==== UI helpers (без FontFace, без слипшихся операторов) ====
local function roundify(obj, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 10)
    c.Parent = obj
    return c
end

local function stroke(obj, col, th, tr)
    local s = Instance.new("UIStroke")
    s.Color = col or COLORS.stroke
    s.Thickness = th or 1
    s.Transparency = tr or 0.25
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

local function padding(obj, l, t, r, b)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, l or 0)
    p.PaddingTop = UDim.new(0, t or 0)
    p.PaddingRight = UDim.new(0, r or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.Parent = obj
    return p
end

local function setFont(lbl, weight)
    local ok = pcall(function()
        if weight == "bold" then
            lbl.Font = Enum.Font.GothamBold
        elseif weight == "medium" then
            lbl.Font = Enum.Font.GothamMedium
        else
            lbl.Font = Enum.Font.Gotham
        end
    end)
    if not ok then
        if weight == "bold" then
            lbl.Font = Enum.Font.SourceSansBold
        else
            lbl.Font = Enum.Font.SourceSans
        end
    end
end

local function mkLabel(parent, text, size, weight, color)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextSize = size or 18
    lbl.TextColor3 = color or COLORS.textPrimary
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    setFont(lbl, weight)
    lbl.Parent = parent
    return lbl
end

local function mkHeader(parent, text)
    local h = Instance.new("Frame")
    h.BackgroundColor3 = COLORS.surface2
    h.BackgroundTransparency = ALPHA.card
    h.Size = UDim2.new(1, 0, 0, 38)
    h.Parent = parent
    roundify(h, 8)
    stroke(h)
    padding(h, 12, 6, 12, 6)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, COLORS.purpleDeep),
        ColorSequenceKeypoint.new(1, COLORS.purple)
    }
    grad.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 0.4)
    }
    grad.Rotation = 90
    grad.Parent = h

    local t = mkLabel(h, text, 18, "bold", COLORS.textPrimary)
    t.Size = UDim2.new(1, 0, 1, 0)
    return h
end

local function mkToggle(parent, text, default)
    local row = Instance.new("Frame")
    row.Name = text .. "_Row"
    row.BackgroundColor3 = COLORS.surface2
    row.BackgroundTransparency = ALPHA.card
    row.Size = UDim2.new(1, 0, 0, 44)
    row.Parent = parent
    roundify(row, 10)
    stroke(row)
    padding(row, 12, 0, 12, 0)

    local lbl = mkLabel(row, text, 17, "medium", COLORS.textPrimary)
    lbl.Size = UDim2.new(1, -80, 1, 0)

    local sw = Instance.new("TextButton")
    sw.Text = ""
    sw.AutoButtonColor = false
    sw.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    sw.BackgroundTransparency = 0.2
    sw.Size = UDim2.new(0, 62, 0, 28)
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, -6, 0.5, 0)
    sw.Parent = row
    roundify(sw, 14)
    stroke(sw, COLORS.purpleSoft, 1, 0.35)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 24, 0, 24)
    dot.Position = UDim2.new(0, 2, 0.5, -12)
    dot.BackgroundColor3 = COLORS.off
    dot.Parent = sw
    roundify(dot, 12)

    local state = { Value = default and true or false }

    local function apply(v, instant)
        state.Value = v
        local goalPos = v and UDim2.new(1, -26, 0.5, -12) or UDim2.new(0, 2, 0.5, -12)
        local goalCol = v and COLORS.on or COLORS.off

        if instant then
            dot.Position = goalPos
            dot.BackgroundColor3 = goalCol
            sw.BackgroundColor3 = v and Color3.fromRGB(55, 58, 74) or Color3.fromRGB(40, 40, 48)
        else
            TweenService:Create(dot, TweenInfo.new(0.13, Enum.EasingStyle.Sine), { Position = goalPos }):Play()
            TweenService:Create(dot, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { BackgroundColor3 = goalCol }):Play()
            local bg = v and Color3.fromRGB(55, 58, 74) or Color3.fromRGB(40, 40, 48)
            TweenService:Create(sw, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { BackgroundColor3 = bg }):Play()
        end
    end

    apply(state.Value, true)

    sw.MouseButton1Click:Connect(function()
        apply(not state.Value, false)
        if state.Changed then
            pcall(state.Changed, state.Value)
        end
    end)

    return row, state
end

-- Вертикальный инпут (заголовок сверху, поле ниже). Без мелких подсказок.
local function mkStackInput(parent, title, placeholder, defaultText, isNumeric)
    local row = Instance.new("Frame")
    row.Name = title .. "_Stacked"
    row.BackgroundColor3 = COLORS.surface2
    row.BackgroundTransparency = ALPHA.card
    row.Size = UDim2.new(1, 0, 0, 70)
    row.Parent = parent
    roundify(row, 10)
    stroke(row)
    padding(row, 12, 8, 12, 12)

    local top = mkLabel(row, title, 16, "medium", COLORS.textPrimary)
    top.Size = UDim2.new(1, 0, 0, 18)

    local box = Instance.new("TextBox")
    box.PlaceholderText = placeholder or ""
    box.Text = defaultText or ""
    box.ClearTextOnFocus = false
    box.TextSize = 17
    box.TextColor3 = COLORS.textPrimary
    box.PlaceholderColor3 = COLORS.textWeak
    box.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
    box.BackgroundTransparency = 0.15
    box.Size = UDim2.new(1, 0, 0, 30)
    box.Position = UDim2.new(0, 0, 0, 30)
    roundify(box, 8)
    stroke(box, COLORS.purpleSoft, 1, 0.35)
    box.Parent = row

    local state = {}

    if isNumeric then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            box.Text = box.Text:gsub("[^%d]", "")
        end)
    end

    box.FocusLost:Connect(function()
        if isNumeric then
            state.Value = tonumber(box.Text) or 0
        else
            state.Value = box.Text
        end
        if state.Changed then
            pcall(state.Changed, state.Value)
        end
    end)

    return row, state, box
end

local function makeDraggable(frame, handle)
    local dragging = false
    local startPos = nil
    local startInputPos = nil
    handle = handle or frame

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            startPos = frame.Position
            startInputPos = input.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startInputPos
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- ==== Light blur (минимальная нагрузка) ====
local blur = Lighting:FindFirstChild("FloppaLightBlur")
if not blur then
    blur = Instance.new("BlurEffect")
    blur.Name = "FloppaLightBlur"
    blur.Size = 0
    blur.Enabled = false
    blur.Parent = Lighting
end

local function setBlur(enabled)
    if enabled then
        blur.Enabled = true
        TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Size = 4 }):Play()
    else
        TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Size = 0 }):Play()
        task.delay(0.16, function()
            blur.Enabled = false
        end)
    end
end

-- ==== Root GUI (парент в CoreGui/gethui, чтобы не удаляли) ====
local guiParent = nil
local okGetHui, hui = pcall(function()
    return gethui and gethui() or nil
end)
if okGetHui and hui then
    guiParent = hui
else
    local okCore, core = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and core then
        guiParent = core
    else
        guiParent = player:WaitForChild("PlayerGui")
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "FloppaAutoJoinerGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100000
gui.Parent = guiParent

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 980, 0, 560)
main.Position = UDim2.new(0.5, -490, 0.5, -280)
main.BackgroundColor3 = COLORS.surface
main.BackgroundTransparency = ALPHA.panel
main.Parent = gui
roundify(main, 14)
stroke(main, COLORS.purpleSoft, 1.5, 0.35)
padding(main, 10, 10, 10, 10)

-- ==== Header + rebind key ====
local CURRENT_HOTKEY = Enum.KeyCode.K

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = COLORS.surface2
header.BackgroundTransparency = ALPHA.card
header.Parent = main
roundify(header, 10)
stroke(header)
padding(header, 14, 6, 14, 6)

local title = mkLabel(header, "FLOPPA AUTO JOINER", 20, "bold", COLORS.textPrimary)
title.Size = UDim2.new(1, -220, 1, 0)

local hotkeyInfo = mkLabel(header, "OPEN GUI KEY  ", 16, "medium", COLORS.textWeak)
hotkeyInfo.AnchorPoint = Vector2.new(1, 0.5)
hotkeyInfo.Position = UDim2.new(1, -60, 0.5, 0)
hotkeyInfo.Size = UDim2.new(0, 220, 1, 0)
hotkeyInfo.TextXAlignment = Enum.TextXAlignment.Right

local keyButton = Instance.new("TextButton")
keyButton.Size = UDim2.new(0, 36, 0, 32)
keyButton.AnchorPoint = Vector2.new(1, 0.5)
keyButton.Position = UDim2.new(1, -18, 0.5, 0)
keyButton.BackgroundColor3 = COLORS.surface
keyButton.BackgroundTransparency = 0.1
keyButton.Text = ""
keyButton.AutoButtonColor = false
keyButton.Parent = header
roundify(keyButton, 8)
stroke(keyButton, COLORS.purple, 1, 0.4)

local keyLbl = mkLabel(keyButton, CURRENT_HOTKEY.Name, 18, "bold", COLORS.textPrimary)
keyLbl.Size = UDim2.new(1, 0, 1, 0)
keyLbl.TextXAlignment = Enum.TextXAlignment.Center

-- ==== Left column (scroll) ====
local left = Instance.new("ScrollingFrame")
left.Size = UDim2.new(0, 300, 1, -58)
left.Position = UDim2.new(0, 0, 0, 58)
left.BackgroundTransparency = 1
left.ScrollBarThickness = 6
left.ScrollingDirection = Enum.ScrollingDirection.Y
left.CanvasSize = UDim2.new(0, 0, 0, 0)
left.Parent = main
local leftPad = padding(left, 0, 0, 0, 10)

local leftList = Instance.new("UIListLayout")
leftList.Padding = UDim.new(0, 10)
leftList.SortOrder = Enum.SortOrder.LayoutOrder
leftList.Parent = left

local function updateLeftCanvas()
    left.CanvasSize = UDim2.new(0, 0, 0, leftList.AbsoluteContentSize.Y + leftPad.PaddingBottom.Offset)
end
leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

-- ==== Right panel ====
local right = Instance.new("Frame")
right.Size = UDim2.new(1, -320, 1, -58)
right.Position = UDim2.new(0, 320, 0, 58)
right.BackgroundColor3 = COLORS.surface2
right.BackgroundTransparency = ALPHA.card
right.Parent = main
roundify(right, 12)
stroke(right)
padding(right, 12, 12, 12, 12)

-- ==== Left blocks ====
mkHeader(left, "PRIORITY ACTIONS")
local autoJoinRow, autoJoin = mkToggle(left, "AUTO JOIN", false)
local jrRow, joinRetryState, jrBox = mkStackInput(left, "JOIN RETRY", "50", "50", true)

mkHeader(left, "MONEY FILTERS")
local msRow, minMSState, msBox = mkStackInput(left, "MIN M/S", "100", "100", true)

mkHeader(left, "НАСТРОЙКИ")
local autoInjectRow, autoInject = mkToggle(left, "AUTO INJECT", false)
local ignoreListRow, ignoreToggle = mkToggle(left, "ENABLE IGNORE LIST", false)

-- IGNORE NAMES: заголовок + поле ниже
local ignoreRow, ignoreState, ignoreBox = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", "", false)

-- ==== Right list (пример) ====
local listHeader = mkHeader(right, "AVAILABLE LOBBIES")
listHeader.Size = UDim2.new(1, 0, 0, 40)

local scroll = Instance.new("ScrollingFrame")
scroll.BackgroundTransparency = 1
scroll.Size = UDim2.new(1, 0, 1, -50)
scroll.Position = UDim2.new(0, 0, 0, 46)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 6
scroll.Parent = right

local listLay = Instance.new("UIListLayout")
listLay.SortOrder = Enum.SortOrder.LayoutOrder
listLay.Padding = UDim.new(0, 8)
listLay.Parent = scroll

local function addLobbyItem(nameText, moneyPerSec)
    local item = Instance.new("Frame")
    item.Size = UDim2.new(1, -6, 0, 52)
    item.BackgroundColor3 = COLORS.surface
    item.BackgroundTransparency = ALPHA.panel
    item.Parent = scroll
    roundify(item, 10)
    stroke(item, COLORS.purpleSoft, 1, 0.35)
    padding(item, 12, 6, 12, 6)

    local nameLbl = mkLabel(item, string.upper(nameText), 18, "bold", COLORS.textPrimary)
    nameLbl.Size = UDim2.new(0.5, -10, 1, 0)

    local moneyLbl = mkLabel(item, string.upper(moneyPerSec), 17, "medium", Color3.fromRGB(130, 255, 130))
    moneyLbl.AnchorPoint = Vector2.new(0.5, 0.5)
    moneyLbl.Position = UDim2.new(0.62, 0, 0.5, 0)
    moneyLbl.Size = UDim2.new(0.34, 0, 1, 0)
    moneyLbl.TextXAlignment = Enum.TextXAlignment.Center

    local joinBtn = Instance.new("TextButton")
    joinBtn.Text = "JOIN"
    setFont(joinBtn, "bold")
    joinBtn.TextSize = 18
    joinBtn.TextColor3 = Color3.fromRGB(22, 22, 22)
    joinBtn.AutoButtonColor = true
    joinBtn.BackgroundColor3 = COLORS.joinBtn
    joinBtn.Size = UDim2.new(0, 84, 0, 36)
    joinBtn.AnchorPoint = Vector2.new(1, 0.5)
    joinBtn.Position = UDim2.new(1, -8, 0.5, 0)
    roundify(joinBtn, 10)
    stroke(joinBtn, Color3.fromRGB(0, 0, 0), 1, 0.7)
    joinBtn.Parent = item

    joinBtn.MouseButton1Click:Connect(function()
        print("[JOIN] ->", nameText)
    end)

    task.defer(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, listLay.AbsoluteContentSize.Y + 10)
    end)
end

for i = 1, 10 do
    addLobbyItem("BRAINROT NAME " .. i, "MONEY/SECOND")
end

-- ==== State ====
local State = {
    AutoJoin = false,
    AutoInject = false,
    IgnoreEnabled = false,
    JoinRetry = tonumber(jrBox.Text) or 50,
    MinMS = tonumber(msBox.Text) or 100,
    IgnoreNames = {}
}

local function parseIgnore(t)
    local r = {}
    for token in string.gmatch(t or "", "([^,%s]+)") do
        table.insert(r, token)
    end
    return r
end

autoJoin.Changed = function(v)
    State.AutoJoin = v
end

ignoreToggle.Changed = function(v)
    State.IgnoreEnabled = v
end

jrBox.FocusLost:Connect(function()
    State.JoinRetry = tonumber(jrBox.Text) or State.JoinRetry
end)

msBox.FocusLost:Connect(function()
    State.MinMS = tonumber(msBox.Text) or State.MinMS
end)

ignoreState.Changed = function(text)
    State.IgnoreNames = parseIgnore(text)
end

-- ==== AUTO INJECT (без двусмысленных строк) ====
local function pickQueue()
    local q = nil
    local ok1 = pcall(function()
        if syn and type(syn.queue_on_teleport) == "function" then
            q = syn.queue_on_teleport
        end
    end)
    ok1 = ok1 -- silence
    if not q and type(queue_on_teleport) == "function" then
        q = queue_on_teleport
    end
    if not q and type(queueteleport) == "function" then
        q = queueteleport
    end
    if not q and type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
        q = fluxus.queue_on_teleport
    end
    return q
end

local function makeBootstrap(url)
    url = tostring(url or "")
    local code = ""
    code = code .. "task.spawn(function()\n"
    code = code .. "  local function safeget(u)\n"
    code = code .. "    for i=1,3 do\n"
    code = code .. "      local ok,res = pcall(function() return game:HttpGet(u) end)\n"
    code = code .. "      if ok and type(res)==\"string\" and #res>0 then return res end\n"
    code = code .. "      task.wait(1)\n"
    code = code .. "    end\n"
    code = code .. "  end\n"
    code = code .. "  local src = nil\n"
    code = code .. "  if #\"" .. url .. "\" > 0 then\n"
    code = code .. "    src = safeget(\"" .. url .. "\")\n"
    code = code .. "  end\n"
    code = code .. "  if src then local f=loadstring(src); if f then pcall(f) end end\n"
    code = code .. "end)\n"
    return code
end

local function runNow(url)
    if not url or url == "" then
        warn("[Floppa] AUTO_INJECT_URL пустой")
        return
    end
    local ok, src = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(src) == "string" and #src > 0 then
        local f = loadstring(src)
        if f then
            local ok2, err = pcall(f)
            if not ok2 then
                warn("[Floppa] Ошибка при выполнении загруженного скрипта: ", err)
            end
        end
    else
        warn("[Floppa] Не удалось получить скрипт по URL")
    end
end

local queuedCooldown = false

local function queueReinject(url)
    local q = pickQueue()
    if q then
        q(makeBootstrap(url))
        print("[Floppa] AutoInject queued.")
    else
        print("[Floppa] queue_on_teleport не найден (LocalScript/Studio)")
    end
end

autoInject.Changed = function(v)
    State.AutoInject = v
    if v then
        runNow(AUTO_INJECT_URL)
        if not queuedCooldown then
            queuedCooldown = true
            queueReinject(AUTO_INJECT_URL)
            task.delay(2.0, function()
                queuedCooldown = false
            end)
        end
    end
end

Players.LocalPlayer.OnTeleport:Connect(function(tpState)
    if State.AutoInject and tpState == Enum.TeleportState.Started and not queuedCooldown then
        queuedCooldown = true
        queueReinject(AUTO_INJECT_URL)
        task.delay(2.0, function()
            queuedCooldown = false
        end)
    end
end)

-- ==== Show/hide + rebind ====
local opened = true

local function setVisible(v, instant)
    opened = v
    if v then
        setBlur(true)
    else
        setBlur(false)
    end
    local goal = v and UDim2.new(0.5, -490, 0.5, -280) or UDim2.new(0.5, -490, 1, 30)
    if instant then
        main.Position = goal
        main.Visible = v
    else
        if v then
            main.Visible = true
        end
        local t = TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal })
        t:Play()
        if not v then
            t.Completed:Wait()
            main.Visible = false
        end
    end
end

local rebinding = false
local keyStroke = keyButton:FindFirstChildWhichIsA("UIStroke")

local function setRebindVisual(active)
    if not keyStroke then
        return
    end
    if active then
        TweenService:Create(keyStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Transparency = 0.05 }):Play()
        keyLbl.Text = "Press..."
    else
        TweenService:Create(keyStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Transparency = 0.4 }):Play()
        keyLbl.Text = CURRENT_HOTKEY.Name
    end
end

keyButton.MouseButton1Click:Connect(function()
    if not rebinding then
        rebinding = true
        setRebindVisual(true)
    end
end)

UIS.InputBegan:Connect(function(input, gp)
    if rebinding and input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Escape then
            rebinding = false
            setRebindVisual(false)
            return
        end
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            CURRENT_HOTKEY = input.KeyCode
            rebinding = false
            setRebindVisual(false)
        end
        return
    end

    if not gp and input.KeyCode == CURRENT_HOTKEY then
        setVisible(not opened, false)
    end
end)

makeDraggable(main, header)
task.defer(function()
    updateLeftCanvas()
    setVisible(true, true)
end)
