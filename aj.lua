--[[
  FLOPPA AUTO JOINER - Luau-safe v5.0 (API Integration)
  • Хоткей фикс.: T
  • queue_on_teleport bootstrap (без run-now), сброс __FLOPPA_UI_ACTIVE
  • Конфиг JSON читается ДО создания UI → тумблеры/поля рисуются сразу правильно
  • Финальный refreshUI() после показа окна
  • API интеграция с автоматическим обновлением списка серверов
  • Auto Join с retry функционалом
]]

local SCRIPT_VERSION = "5.0"

------------------ USER SETTINGS ------------------
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY    = Enum.KeyCode.T
local SETTINGS_PATH   = "floppa_aj_settings.json"
local API_URL         = "https://server-eta-two-29.vercel.app/"
local API_KEY         = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"
local UPDATE_INTERVAL = 3 -- секунды между обновлениями
---------------------------------------------------

-- === Services & FS ===
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local HttpService  = game:GetService("HttpService")

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

-- === Singleton-friendly очистка старого GUI ===
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
    G.__FLOPPA_UI_ACTIVE = true
end

-- === СНАЧАЛА загружаем конфиг ===
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

-- === Стиль/утилы UI ===
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

-- Header
local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
roundify(header,10); stroke(header); padding(header,14,6,14,6)
local titleLabel=mkLabel(header,"FLOPPA AUTO JOINER",20,"bold",COLORS.textPrimary)
titleLabel.Size=UDim2.new(0.5,0,1,0)
local versionLabel=mkLabel(header,"v"..SCRIPT_VERSION,12,"medium",COLORS.purpleSoft)
versionLabel.Position=UDim2.new(0,180,0,0)
versionLabel.Size=UDim2.new(0,50,1,0)
versionLabel.TextXAlignment=Enum.TextXAlignment.Left
local hotkeyInfo=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak)
hotkeyInfo.AnchorPoint=Vector2.new(1,0.5); hotkeyInfo.Position=UDim2.new(1,-14,0.5,0); hotkeyInfo.Size=UDim2.new(0.35,0,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right

-- Left / Right columns
local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1
left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
local leftPad=padding(left,0,0,0,10)
local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main
roundify(right,12); stroke(right); padding(right,12,12,12,12)

-- ==== Controls (используем значения State как дефолты) ====
mkHeader(left,"PRIORITY ACTIONS")
local _, autoJoin,     applyAutoJoin   = mkToggle(left, "AUTO JOIN", State.AutoJoin)
local _, _,            jrBox           = mkStackInput(left, "JOIN RETRY", "50", tostring(State.JoinRetry), true)

mkHeader(left,"MONEY FILTERS")
local _, _,            msBox           = mkStackInput(left, "MIN M/S", "100", tostring(State.MinMS), true)

mkHeader(left,"НАСТРОЙКИ")
local _, autoInject,   applyAutoInject = mkToggle(left, "AUTO INJECT", State.AutoInject)
local _, ignoreToggle, applyIgnoreTgl  = mkToggle(left, "ENABLE IGNORE LIST", State.IgnoreEnabled)
local _, ignoreState,  ignoreBox       = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", table.concat(State.IgnoreNames, ","), false)

-- Right header and server list
mkHeader(right,"AVAILABLE LOBBIES").Size=UDim2.new(1,0,0,40)

-- Server list scrolling frame
ServerListFrame = Instance.new("ScrollingFrame")
ServerListFrame.Name = "ServerList"
ServerListFrame.Size = UDim2.new(1, 0, 1, -52)
ServerListFrame.Position = UDim2.new(0, 0, 0, 52)
ServerListFrame.BackgroundTransparency = 1
ServerListFrame.BorderSizePixel = 0
ServerListFrame.ScrollBarThickness = 6
ServerListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ServerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ServerListFrame.Parent = right

ServerListLayout = Instance.new("UIListLayout")
ServerListLayout.Padding = UDim.new(0, 8)
ServerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ServerListLayout.Parent = ServerListFrame

local serverListPad = padding(ServerListFrame, 0, 0, 0, 10)
local function updateServerListCanvas()
    if ServerListLayout then
        ServerListFrame.CanvasSize = UDim2.new(0, 0, 0, ServerListLayout.AbsoluteContentSize.Y + serverListPad.PaddingBottom.Offset)
    end
end
ServerListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateServerListCanvas)

-- === Сохранение настроек ===
local LOADING = false
local function parseIgnore(s) local r={} for token in string.gmatch(s or "", "([^,%s]+)") do r[#r+1]=token end return r end
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
ignoreToggle.Changed = function(v) State.IgnoreEnabled=v; saveSettings(); task.defer(function() if updateServerList then updateServerList() end end) end
jrBox.FocusLost:Connect(function() State.JoinRetry=tonumber(jrBox.Text) or State.JoinRetry; saveSettings() end)
msBox.FocusLost:Connect(function() State.MinMS=tonumber(msBox.Text) or State.MinMS; saveSettings(); task.defer(function() if updateServerList then updateServerList() end end) end)
ignoreState.Changed  = function(txt) State.IgnoreNames=parseIgnore(txt); saveSettings(); task.defer(function() if updateServerList then updateServerList() end end) end

-- === API & Server Data ===
local TeleportService = game:GetService("TeleportService")
local LogService = game:GetService("LogService")
local player = Players.LocalPlayer
if not player then
    player = Players:WaitForChild("LocalPlayer", 10)
end

local ServerData = {} -- {name, moneyPerSec, online, serverId, timestamp}
local ServerListFrame = nil
local ServerListLayout = nil
local isJoining = false
local currentJoinAttempts = 0
local lastTeleportError = ""

-- Парсинг денег из строки ($875K/s, $26M/s, etc)
local function parseMoneyPerSecond(str)
    if not str or type(str) ~= "string" then return 0 end
    str = str:gsub("%$", ""):gsub("/s", ""):gsub(" ", ""):lower()
    local num = tonumber(str:match("([%d%.]+)"))
    if not num then return 0 end
    if str:find("m") then num = num * 1000000
    elseif str:find("k") then num = num * 1000 end
    return math.floor(num)
end

-- Парсинг данных с API
local function parseServerData(rawText)
    local servers = {}
    local ok, err = pcall(function()
        if not rawText or type(rawText) ~= "string" or #rawText == 0 then return servers end
        
        -- Разбиваем на строки
        for line in rawText:gmatch("[^\r\n]+") do
            local lineOk, lineErr = pcall(function()
                line = line:match("^%s*(.-)%s*$") -- trim
                if #line > 0 and line:find("|") then
                    local parts = {}
                    -- Разбиваем по разделителю |
                    for part in line:gmatch("([^|]+)") do
                        local trimmed = part:match("^%s*(.-)%s*$")
                        if trimmed and #trimmed > 0 then
                            table.insert(parts, trimmed)
                        end
                    end
                    if #parts >= 4 then
                        local name = (parts[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        local moneyStr = (parts[2] or ""):gsub("%*", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        local onlineStr = (parts[3] or ""):gsub("%*", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        local serverId = (parts[4] or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        
                        -- Парсинг online (7/8, 6/8)
                        local current, max = onlineStr:match("(%d+)/(%d+)")
                        current = tonumber(current) or 0
                        max = tonumber(max) or 8
                        
                        local moneyPerSec = parseMoneyPerSecond(moneyStr)
                        
                        -- Проверяем, что есть имя и serverId
                        if name and #name > 0 and serverId and #serverId > 0 then
                            table.insert(servers, {
                                name = name,
                                moneyPerSec = moneyPerSec,
                                online = current,
                                maxOnline = max,
                                serverId = serverId,
                                onlineStr = onlineStr
                            })
                        end
                    end
                end
            end)
        end
    end)
    return servers
end

-- Получение данных с API
local function fetchServerData()
    local ok, result = pcall(function()
        local headers = {}
        if API_KEY and #API_KEY > 0 then
            headers["X-API-Key"] = API_KEY
            headers["Authorization"] = "Bearer " .. API_KEY
        end
        
        -- Пробуем разные способы HTTP запросов
        if syn and syn.request then
            local response = syn.request({
                Url = API_URL,
                Method = "GET",
                Headers = headers
            })
            if response and response.Body and type(response.Body) == "string" then
                return response.Body
            end
        elseif request then
            local response = request({
                Url = API_URL,
                Method = "GET",
                Headers = headers
            })
            if response and response.Body and type(response.Body) == "string" then
                return response.Body
            end
        elseif HttpService and HttpService.RequestAsync then
            local response = HttpService:RequestAsync({
                Url = API_URL,
                Method = "GET",
                Headers = headers
            })
            if response and response.Body and type(response.Body) == "string" then
                return response.Body
            end
        elseif game.HttpGet then
            -- Правильный вызов HttpGet
            local success, body = pcall(function()
                return game:HttpGet(API_URL, true, headers)
            end)
            if success and body and type(body) == "string" then
                return body
            end
        end
        return nil
    end)
    if ok and result and type(result) == "string" and #result > 0 then
        -- Проверяем, что это не HTML
        if not result:find("<!DOCTYPE") and not result:find("<html") and not result:find("<body") then
            return parseServerData(result)
        end
    end
    return {}
end

-- Фильтрация серверов
local function filterServers(servers)
    local filtered = {}
    if not servers or type(servers) ~= "table" then return filtered end
    for _, srv in ipairs(servers) do
        pcall(function()
            if srv and srv.moneyPerSec and srv.moneyPerSec >= (State.MinMS or 0) then
                -- Фильтр по Ignore Names
                local shouldIgnore = false
                if State.IgnoreEnabled and State.IgnoreNames and #State.IgnoreNames > 0 and srv.name then
                    for _, ignoreName in ipairs(State.IgnoreNames) do
                        if ignoreName and srv.name:lower():find(ignoreName:lower(), 1, true) then
                            shouldIgnore = true
                            break
                        end
                    end
                end
                if not shouldIgnore then
                    table.insert(filtered, srv)
                end
            end
        end)
    end
    return filtered
end

-- Форматирование денег
local function formatMoney(amount)
    if amount >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("%.1fK", amount / 1000)
    else
        return tostring(amount)
    end
end

-- Создание карточки сервера
local function createServerCard(server, parent, index)
    if not server or not parent or not server.serverId then return nil end
    local ok, card = pcall(function()
        local card = Instance.new("Frame")
        card.Name = "ServerCard_" .. (server.serverId or "unknown")
        card.BackgroundColor3 = COLORS.surface2
        card.BackgroundTransparency = ALPHA.card
        card.Size = UDim2.new(1, -4, 0, 60)
        card.LayoutOrder = index or 0
        card.Parent = parent
        roundify(card, 10)
        stroke(card)
        padding(card, 12, 8, 12, 8)
        
        -- Name
        local nameLabel = mkLabel(card, server.name or "Unknown", 16, "medium", COLORS.textPrimary)
        nameLabel.Size = UDim2.new(0.35, -4, 0, 20)
        nameLabel.Position = UDim2.new(0, 0, 0, 0)
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        
        -- Money/Second
        local moneyLabel = mkLabel(card, "$" .. formatMoney(server.moneyPerSec or 0) .. "/s", 15, "medium", COLORS.joinBtn)
        moneyLabel.Position = UDim2.new(0.35, 4, 0, 0)
        moneyLabel.Size = UDim2.new(0.25, -4, 0, 20)
        
        -- Online
        local onlineLabel = mkLabel(card, server.onlineStr or "0/8", 15, "medium", COLORS.textWeak)
        onlineLabel.Position = UDim2.new(0.6, 4, 0, 0)
        onlineLabel.Size = UDim2.new(0.2, -88, 0, 20)
        
        -- Join Button
        local joinBtn = Instance.new("TextButton")
        joinBtn.Text = "JOIN"
        joinBtn.TextSize = 14
        joinBtn.Font = Enum.Font.GothamBold
        joinBtn.TextColor3 = Color3.new(1, 1, 1)
        joinBtn.BackgroundColor3 = COLORS.joinBtn
        joinBtn.BackgroundTransparency = 0
        joinBtn.Size = UDim2.new(0, 80, 0, 32)
        joinBtn.Position = UDim2.new(1, -88, 0.5, -16)
        joinBtn.AnchorPoint = Vector2.new(1, 0.5)
        joinBtn.AutoButtonColor = false
        joinBtn.Parent = card
        roundify(joinBtn, 8)
        
        joinBtn.MouseButton1Click:Connect(function()
            pcall(function()
                if not isJoining and server.serverId then
                    joinServer(server.serverId, State.JoinRetry)
                end
            end)
        end)
        
        -- Hover эффект для кнопки
        joinBtn.MouseEnter:Connect(function()
            pcall(function()
                TweenService:Create(joinBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(55, 242, 100)}):Play()
            end)
        end)
        joinBtn.MouseLeave:Connect(function()
            pcall(function()
                TweenService:Create(joinBtn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.joinBtn}):Play()
            end)
        end)
        
        return card
    end)
    return ok and card or nil
end

-- Обновление списка серверов
local function updateServerList()
    local ok, err = pcall(function()
        if not ServerListFrame then return end
        
        -- Очистка старых карточек
        local children = ServerListFrame:GetChildren()
        for _, child in ipairs(children) do
            if child:IsA("Frame") and child.Name:find("ServerCard_") then
                pcall(function() child:Destroy() end)
            end
        end
        
        -- Получение и фильтрация серверов
        local allServers = fetchServerData()
        if not allServers or #allServers == 0 then
            -- Если серверов нет, обновляем canvas и выходим
            task.wait(0.1)
            if updateServerListCanvas then
                pcall(updateServerListCanvas)
            end
            return
        end
        
        local filtered = filterServers(allServers)
        
        if #filtered > 0 then
            -- Сортировка по moneyPerSec (по убыванию)
            pcall(function()
                table.sort(filtered, function(a, b) 
                    return (a.moneyPerSec or 0) > (b.moneyPerSec or 0) 
                end)
            end)
            
            -- Создание карточек
            for i, server in ipairs(filtered) do
                if server and server.serverId then
                    pcall(function() 
                        local card = createServerCard(server, ServerListFrame, i)
                        if not card then
                            -- Если карточка не создалась, пропускаем
                        end
                    end)
                end
            end
        end
        
        -- Обновление размера canvas
        task.wait(0.1)
        if updateServerListCanvas then
            pcall(updateServerListCanvas)
        end
    end)
    if not ok then
        -- Тихая ошибка, не крашим скрипт
    end
end

-- Join сервера с retry
local function joinServer(serverId, maxRetries)
    if isJoining or not serverId or not player then return end
    isJoining = true
    currentJoinAttempts = 0
    maxRetries = maxRetries or State.JoinRetry
    lastTeleportError = ""
    
    local function attemptJoin()
        currentJoinAttempts = currentJoinAttempts + 1
        local ok, err = pcall(function()
            if not player or not serverId then return end
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, player)
        end)
        
        if not ok then
            -- Если ошибка при вызове, ждём и пробуем снова
            if currentJoinAttempts < maxRetries then
                task.wait(1)
                attemptJoin()
            else
                isJoining = false
            end
        else
            -- Успешный вызов телепорта, ждём результата
            task.wait(3)
            -- Проверяем ошибку через lastTeleportError
            if lastTeleportError and (lastTeleportError:find("full") or lastTeleportError:find("GameFull") or lastTeleportError:find("Teleport failed")) then
                if currentJoinAttempts < maxRetries then
                    lastTeleportError = ""
                    task.wait(1)
                    attemptJoin()
                else
                    isJoining = false
                end
            else
                -- Успешный телепорт или нет ошибки
                isJoining = false
            end
        end
    end
    
    task.spawn(attemptJoin)
end

-- Auto Join логика
local function checkAutoJoin()
    local ok, err = pcall(function()
        if not State.AutoJoin or isJoining then return end
        
        local allServers = fetchServerData()
        local filtered = filterServers(allServers)
        
        if #filtered > 0 then
            -- Берём сервер с максимальным m/s
            table.sort(filtered, function(a, b) return a.moneyPerSec > b.moneyPerSec end)
            local bestServer = filtered[1]
            if bestServer and bestServer.serverId then
                joinServer(bestServer.serverId, State.JoinRetry)
            end
        end
    end)
    if not ok then
        -- Тихая ошибка
    end
end

-- Мониторинг ошибок телепорта
pcall(function()
    if TeleportService.TeleportInitFailed then
        TeleportService.TeleportInitFailed:Connect(function(teleportPlayer, teleportResult, errorMessage)
            pcall(function()
                if teleportPlayer == player then
                    lastTeleportError = errorMessage or tostring(teleportResult) or ""
                end
            end)
        end)
    end
end)

-- Мониторинг консоли для ошибок телепорта (резервный метод)
pcall(function()
    if LogService and LogService.MessageOut then
        LogService.MessageOut:Connect(function(message, messageType)
            pcall(function()
                if messageType == Enum.MessageType.MessageOutput or messageType == Enum.MessageType.MessageError then
                    if message and (message:find("Teleport failed") or message:find("GameFull") or message:find("full") or message:find("raiseTeleportInitFailedEvent")) then
                        lastTeleportError = message
                    end
                end
            end)
        end)
    end
end)

-- === Auto Inject (только очередь) ===
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
    s=s.."  local function safeget(u)\n"
    s=s.."    for i=1,3 do local ok,res=pcall(function() return game:HttpGet(u) end); if ok and type(res)=='string' and #res>0 then return res end; task.wait(1) end\n"
    s=s.."  end\n"
    s=s.."  local src=safeget('"..AUTO_INJECT_URL.."')\n"
    s=s.."  if src then local f=loadstring(src); if f then pcall(f) end end\n"
    s=s.."end)\n"
    return s
end
local function queueReinject(url)
    local q = pickQueue()
    if q and url~="" then q(makeBootstrap(url)) end
end
-- Если в конфиге был включён — ставим очередь прямо сейчас
if autoInject.Value then queueReinject(AUTO_INJECT_URL) end
-- И дублируем при телепорте
player.OnTeleport:Connect(function(st)
    if autoInject.Value and st==Enum.TeleportState.Started then
        queueReinject(AUTO_INJECT_URL)
    end
end)

-- === Показ/скрытие (T) + drag ===
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
    -- Обновляем список при открытии окна
    if v and updateServerList then
        task.delay(0.2, function()
            pcall(updateServerList)
        end)
    end
end

UIS.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode==FIXED_HOTKEY then
        setVisible(not opened, false)
    end
end)
makeDraggable(main, header)

-- финальный рефреш после показа — на случай редких гонок
local function refreshUI()
    -- применяем актуальные значения ещё раз (визуал only)
    applyAutoJoin(autoJoin.Value, true)
    applyAutoInject(autoInject.Value, true)
    applyIgnoreTgl(ignoreToggle.Value, true)
end

task.defer(function()
    pcall(function()
        updateLeftCanvas()
        setVisible(true,true)
        task.delay(0.05, function()
            pcall(refreshUI)
        end)
        -- Первое обновление списка с задержкой
        task.delay(0.5, function()
            pcall(function()
                if updateServerList then
                    updateServerList()
                end
            end)
        end)
    end)
end)

-- Периодическое обновление списка серверов
task.spawn(function()
    while true do
        pcall(function()
            task.wait(UPDATE_INTERVAL)
            if opened and updateServerList then
                updateServerList()
            end
        end)
    end
end)

-- Периодическая проверка Auto Join
task.spawn(function()
    while true do
        pcall(function()
            task.wait(2)
            if State.AutoJoin and not isJoining and checkAutoJoin then
                checkAutoJoin()
            end
        end)
    end
end)
