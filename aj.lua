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
local SERVER_BASE      = "https://server-eta-two-29.vercel.app"
local API_KEY          = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"
local UPDATE_INTERVAL  = 2.5 -- секунды между обновлениями
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
local hotkeyInfo=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak)
hotkeyInfo.AnchorPoint=Vector2.new(1,0.5); hotkeyInfo.Position=UDim2.new(1,-14,0.5,0); hotkeyInfo.Size=UDim2.new(0.35,0,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right

-- Version badge в правом верхнем углу окна
local versionBadge=Instance.new("Frame")
versionBadge.Name="VersionBadge"
versionBadge.Size=UDim2.new(0,65,0,26)
versionBadge.Position=UDim2.new(1,-75,0,8)
versionBadge.AnchorPoint=Vector2.new(1,0)
versionBadge.BackgroundColor3=COLORS.purpleDeep
versionBadge.BackgroundTransparency=0
versionBadge.Parent=main
roundify(versionBadge,6)
stroke(versionBadge, COLORS.purple, 1.5, 0.2)
-- Градиент для версии
local versionGradient=Instance.new("UIGradient")
versionGradient.Color=ColorSequence.new{
    ColorSequenceKeypoint.new(0,COLORS.purpleDeep),
    ColorSequenceKeypoint.new(1,COLORS.purple)
}
versionGradient.Rotation=45
versionGradient.Parent=versionBadge
local versionText=mkLabel(versionBadge,"v"..SCRIPT_VERSION,13,"bold",Color3.new(1,1,1))
versionText.Size=UDim2.new(1,0,1,0)
versionText.TextXAlignment=Enum.TextXAlignment.Center
versionText.TextYAlignment=Enum.TextYAlignment.Center
versionText.ZIndex=2

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
local isJoining = false
local currentJoinAttempts = 0
local lastTeleportError = ""
local failedServers = {} -- Храним список мертвых серверов


-- Парсинг данных с API (поддержка разных форматов)
local function parseServerData(rawText)
    local servers = {}
    if not rawText or type(rawText) ~= "string" or #rawText == 0 then return servers end
    
    -- Попытка 1: JSON формат
    local jsonOk, jsonData = pcall(function()
        return HttpService:JSONDecode(rawText)
    end)
    if jsonOk and jsonData and type(jsonData) == "table" then
        local function processJsonItem(item)
            if type(item) ~= "table" then return end
            local name = tostring(item.name or item.Name or item.serverName or item.server_name or "")
            local moneyStr = tostring(item.moneyPerSec or item.money or item.moneyStr or item.moneyPerSecond or item.money_per_sec or "")
            local onlineStr = tostring(item.online or item.players or item.onlineStr or item.online_str or "0/8")
            local serverId = tostring(item.serverId or item.id or item.jobId or item.placeId or item.server_id or item.job_id or "")
            
            local current, max = onlineStr:match("(%d+)/(%d+)")
            if not current then
                current = tonumber(item.online or item.players or item.currentPlayers or 0) or 0
                max = tonumber(item.maxOnline or item.maxPlayers or item.max_players or 8) or 8
                onlineStr = current .. "/" .. max
            else
                current = tonumber(current) or 0
                max = tonumber(max) or 8
            end
            
            local moneyPerSec = tonumber(item.moneyPerSec or item.money_per_sec) or parseMoneyPerSecond(moneyStr)
            
            if #name > 0 and #serverId > 0 then
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
        
        -- Если это массив серверов
        if #jsonData > 0 then
            for _, item in ipairs(jsonData) do
                processJsonItem(item)
            end
        -- Если это объект с массивом servers/data/serversList
        elseif jsonData.servers and type(jsonData.servers) == "table" then
            for _, item in ipairs(jsonData.servers) do
                processJsonItem(item)
            end
        elseif jsonData.data and type(jsonData.data) == "table" then
            if #jsonData.data > 0 then
                for _, item in ipairs(jsonData.data) do
                    processJsonItem(item)
                end
            else
                processJsonItem(jsonData.data)
            end
        elseif jsonData.serversList and type(jsonData.serversList) == "table" then
            for _, item in ipairs(jsonData.serversList) do
                processJsonItem(item)
            end
        -- Если это один объект сервера
        else
            processJsonItem(jsonData)
        end
        
        if #servers > 0 then return servers end
    end
    
    -- Попытка 2: Формат с разделителем | (pipe)
    for line in rawText:gmatch("[^\r\n]+") do
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
    end
    
    -- Попытка 3: Формат с разделителем , (comma) или табуляцией
    if #servers == 0 then
        for line in rawText:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$")
            if #line > 0 then
                local parts = {}
                -- Пробуем табуляцию
                for part in line:gmatch("([^\t]+)") do
                    local trimmed = part:match("^%s*(.-)%s*$")
                    if trimmed and #trimmed > 0 then
                        table.insert(parts, trimmed)
                    end
                end
                -- Если не получилось, пробуем запятую
                if #parts < 4 then
                    parts = {}
                    for part in line:gmatch("([^,]+)") do
                        local trimmed = part:match("^%s*(.-)%s*$")
                        if trimmed and #trimmed > 0 then
                            table.insert(parts, trimmed)
                        end
                    end
                end
                
                if #parts >= 4 then
                    local name = (parts[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    local moneyStr = (parts[2] or ""):gsub("%*", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    local onlineStr = (parts[3] or ""):gsub("%*", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    local serverId = (parts[4] or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local current, max = onlineStr:match("(%d+)/(%d+)")
                    current = tonumber(current) or 0
                    max = tonumber(max) or 8
                    
                    local moneyPerSec = parseMoneyPerSecond(moneyStr)
                    
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
        end
    end
    
    return servers
end

-- Получение данных с API (оптимизированная версия)
local function getReqFn()
    return (syn and syn.request) or http_request or request or (fluxus and fluxus.request) or nil
end

local function apiGetJSON(limit)
    local req = getReqFn()
    local url = string.format("%s/api/jobs?limit=%d&_cb=%d", SERVER_BASE, limit or 200, math.random(10^6, 10^7))
    
    if req then
        local success, response = pcall(function()
            return req({
                Url = url,
                Method = "GET",
                Headers = {
                    ["x-api-key"] = API_KEY,
                    ["Accept"] = "application/json"
                }
            })
        end)
        
        if success and response and response.StatusCode == 200 and type(response.Body) == "string" and #response.Body > 0 then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(response.Body)
            end)
            if ok and data then
                return true, data
            end
        end
    end
    
    -- Fallback: game:HttpGet
    local ok, body = pcall(function()
        return game:HttpGet(url .. "&key=" .. API_KEY)
    end)
    
    if not ok or type(body) ~= "string" or #body == 0 then
        return false
    end
    
    local ok2, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    
    if not ok2 then
        return false
    end
    
    return true, data
end

-- Парсинг денег из строки (оптимизированная версия)
local multMap = {K = 1e3, M = 1e6, B = 1e9, T = 1e12}
local function parseMoneyStr(s)
    s = tostring(s or ""):gsub(",", ""):upper()
    local num, unit = s:match("%$%s*([%d%.]+)%s*([KMBT]?)%s*/%s*[Ss]")
    if not num then
        num, unit = s:match("%$%s*([%d%.]+)%s*([KMBT]?)")
    end
    if not num then return 0 end
    return math.floor((tonumber(num) or 0) * (multMap[unit or ""] or 1) + 0.5)
end

-- Фильтрация серверов (оптимизированная)
local function minThreshold()
    return (tonumber(msBox.Text) or State.MinMS or 0) * 1e6
end

local function passFilters(item)
    if item.mps < minThreshold() then return false end
    if ignoreToggle.Value and #State.IgnoreNames > 0 then
        for _, nm in ipairs(State.IgnoreNames) do
            if #nm > 0 and item.name:lower():find(nm:lower(), 1, true) then
                return false
            end
        end
    end
    return true
end

-- Парсинг данных из API формата
local function pickBestByServer(items)
    local bestById = {}
    if not items or type(items) ~= "table" then return bestById end
    
    for _, it in ipairs(items) do
        local id = tostring(it.id or it.job_id or "")
        local name = tostring(it.name or "")
        local moneyStr = tostring(it.money_per_second or it.money or "")
        local players = tostring(it.players or "")
        
        if id ~= "" and name ~= "" and moneyStr ~= "" and players ~= "" then
            local cur, max = players:match("(%d+)%s*/%s*(%d+)")
            cur = tonumber(cur or 0) or 0
            max = tonumber(max or 0) or 8
            
            local mps = parseMoneyStr(moneyStr)
            local item = {
                jobId = id,
                name = name,
                moneyStr = moneyStr,
                mps = mps,
                curPlayers = cur,
                maxPlayers = max,
                playersRaw = players
            }
            
            if passFilters(item) then
                local curBest = bestById[id]
                if (not curBest) or (item.mps > curBest.mps) then
                    bestById[id] = item
                end
            end
        end
    end
    
    return bestById
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

-- Хранилище записей и порядок отображения
local Entries = {}
local Order = {}
local SeenHashes = {}
local firstSnapshotDone = false

local function hashOf(item)
    return string.format("%s|%s|%s", item.jobId or "", item.moneyStr or "", item.playersRaw or "")
end

local function playersFmt(p, m)
    return string.format("%d/%d", p or 0, m or 0)
end

-- Создание/обновление карточки сервера (оптимизированная версия)
local function ensureItem(jobId, data)
    local e = Entries[jobId]
    if e and e.frame then return e.frame end
    
    local item = Instance.new("Frame")
    item.Name = "ServerCard_" .. jobId
    item.Size = UDim2.new(1, -6, 0, 52)
    item.BackgroundColor3 = COLORS.surface
    item.BackgroundTransparency = ALPHA.panel
    item.Parent = ServerListFrame
    roundify(item, 10)
    stroke(item, COLORS.purpleSoft, 1, 0.35)
    padding(item, 12, 6, 12, 6)
    
    local nameLbl = mkLabel(item, string.upper(data.name), 18, "bold", COLORS.textPrimary)
    nameLbl.Size = UDim2.new(0.44, -10, 1, 0)
    
    local moneyLbl = mkLabel(item, string.upper(data.moneyStr or ""), 17, "medium", Color3.fromRGB(130, 255, 130))
    moneyLbl.AnchorPoint = Vector2.new(0, 0.5)
    moneyLbl.Position = UDim2.new(0.46, 0, 0.5, 0)
    moneyLbl.Size = UDim2.new(0.22, 0, 1, 0)
    moneyLbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local playersLbl = mkLabel(item, playersFmt(data.curPlayers, data.maxPlayers), 16, "medium", COLORS.textWeak)
    playersLbl.AnchorPoint = Vector2.new(0, 0.5)
    playersLbl.Position = UDim2.new(0.69, 0, 0.5, 0)
    playersLbl.Size = UDim2.new(0.12, 0, 1, 0)
    playersLbl.TextXAlignment = Enum.TextXAlignment.Left
    
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
        local tries = tonumber(jrBox.Text) or State.JoinRetry or 0
        local dSec = 0.10
        joinBtn.Text = "JOIN…"
        
        for i = 1, math.max(tries, 1) do
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, Players.LocalPlayer)
            end)
            if ok then
                joinBtn.Text = "OK"
                break
            else
                joinBtn.Text = ("RETRY %d/%d"):format(i, tries)
                task.wait(dSec)
            end
        end
        
        task.delay(0.8, function()
            if joinBtn then joinBtn.Text = "JOIN" end
        end)
    end)
    
    Entries[jobId] = {
        data = data,
        frame = item,
        firstSeen = os.clock(),
        lastSeen = os.clock(),
        refs = {nameLbl = nameLbl, moneyLbl = moneyLbl, playersLbl = playersLbl}
    }
    
    return item
end

local function updateItem(jobId, data)
    local e = Entries[jobId]
    if not e then
        ensureItem(jobId, data)
        table.insert(Order, jobId)
        e = Entries[jobId]
    else
        if data.mps > (e.data.mps or 0) then
            e.data = data
        end
        e.lastSeen = os.clock()
    end
    
    local r = e.refs
    if r then
        r.nameLbl.Text = string.upper(e.data.name)
        r.moneyLbl.Text = string.upper(e.data.moneyStr or "")
        r.playersLbl.Text = playersFmt(e.data.curPlayers, e.data.maxPlayers)
    end
end

local function removeItem(jobId)
    local e = Entries[jobId]
    if not e then return end
    
    if e.frame then
        pcall(function() e.frame:Destroy() end)
    end
    
    Entries[jobId] = nil
    for i = #Order, 1, -1 do
        if Order[i] == jobId then
            table.remove(Order, i)
            break
        end
    end
end

local function resortPaint()
    table.sort(Order, function(a, b)
        local ea, eb = Entries[a], Entries[b]
        if not ea or not eb then return (a or "") < (b or "") end
        if ea.data.mps ~= eb.data.mps then
            return ea.data.mps > eb.data.mps
        end
        return ea.lastSeen > eb.lastSeen
    end)
    
    for idx, id in ipairs(Order) do
        local e = Entries[id]
        if e and e.frame then
            e.frame.LayoutOrder = idx
        end
    end
    
    task.defer(function()
        if ServerListLayout then
            ServerListFrame.CanvasSize = UDim2.new(0, 0, 0, ServerListLayout.AbsoluteContentSize.Y + 10)
        end
    end)
end

-- Инкрементальное обновление списка (оптимизированная версия)
local wantImmediate = false
local lastTick = 0

local function updateServerList()
    wantImmediate = true
end

-- Join сервера с retry (улучшенная обработка ошибок)
local function joinServer(serverId, maxRetries)
    if isJoining or not serverId or not player then return end
    isJoining = true
    currentJoinAttempts = 0
    maxRetries = maxRetries or State.JoinRetry
    lastTeleportError = ""
    
    local function attemptJoin()
        -- Проверяем, не выключили ли Auto Join
        if not State.AutoJoin then
            isJoining = false
            return
        end
        
        currentJoinAttempts = currentJoinAttempts + 1
        local ok, err = pcall(function()
            if not player or not serverId then return end
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, player)
        end)
        
        if not ok then
            -- Если ошибка при вызове, ждём и пробуем снова
            if currentJoinAttempts < maxRetries and State.AutoJoin then
                task.wait(1)
                attemptJoin()
            else
                isJoining = false
            end
        else
            -- Успешный вызов телепорта, ждём результата
            task.wait(2)
            
            -- Проверяем ошибку через lastTeleportError
            if lastTeleportError then
                local errorLower = lastTeleportError:lower()
                -- Проверяем на мертвый сервер (GameEnded, Could not find)
                if errorLower:find("gameended") or errorLower:find("could not find") or errorLower:find("game instance") then
                    -- Мертвый сервер - помечаем и останавливаем попытки
                    failedServers[serverId] = true
                    isJoining = false
                    lastTeleportError = ""
                    return
                elseif errorLower:find("full") or errorLower:find("gamefull") then
                    -- Сервер полный - пробуем снова
                    if currentJoinAttempts < maxRetries and State.AutoJoin then
                        lastTeleportError = ""
                        task.wait(1)
                        attemptJoin()
                    else
                        isJoining = false
                    end
                else
                    -- Другая ошибка - останавливаем
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

-- Auto Join логика (оптимизированная с проверкой мертвых серверов)
local function checkAutoJoin()
    -- Проверяем флаг перед каждой операцией
    if not State.AutoJoin then
        isJoining = false
        return
    end
    
    if isJoining then return end
    
    local ok, data = apiGetJSON(250)
    if not ok or type(data) ~= "table" or type(data.items) ~= "table" then return end
    
    local best = pickBestByServer(data.items)
    if not best or next(best) == nil then return end
    
    -- Находим сервер с максимальным mps, исключая мертвые
    local bestServer = nil
    local maxMps = 0
    for _, item in pairs(best) do
        -- Пропускаем мертвые серверы
        if not failedServers[item.jobId] then
            if item.mps > maxMps then
                maxMps = item.mps
                bestServer = item
            end
        end
    end
    
    if bestServer and bestServer.jobId then
        joinServer(bestServer.jobId, State.JoinRetry)
    end
end

-- Мониторинг ошибок телепорта (улучшенный)
pcall(function()
    if TeleportService.TeleportInitFailed then
        TeleportService.TeleportInitFailed:Connect(function(teleportPlayer, teleportResult, errorMessage)
            pcall(function()
                if teleportPlayer == player then
                    local err = errorMessage or tostring(teleportResult) or ""
                    lastTeleportError = err
                    -- Если сервер мертв, сразу останавливаем попытки
                    local errLower = err:lower()
                    if errLower:find("gameended") or errLower:find("could not find") or errLower:find("game instance") then
                        isJoining = false
                    end
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
                    if message then
                        local msgLower = message:lower()
                        if msgLower:find("teleport failed") or msgLower:find("gamefull") or msgLower:find("full") or msgLower:find("raiseteleportinitfailedevent") or msgLower:find("gameended") or msgLower:find("could not find") then
                            lastTeleportError = message
                            -- Если сервер мертв, останавливаем
                            if msgLower:find("gameended") or msgLower:find("could not find") or msgLower:find("game instance") then
                                isJoining = false
                            end
                        end
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
        -- Немедленное обновление
        task.spawn(function()
            updateServerList()
        end)
        -- Дополнительные обновления с задержкой
        task.delay(0.3, function()
            if updateServerList then
                updateServerList()
            end
        end)
        task.delay(1, function()
            if updateServerList then
                updateServerList()
            end
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
        -- Первое обновление списка - сразу и с задержкой
        task.spawn(function()
            task.wait(0.2)
            if updateServerList then
                updateServerList()
            end
        end)
        task.spawn(function()
            task.wait(1)
            if updateServerList then
                updateServerList()
            end
        end)
        task.spawn(function()
            task.wait(2)
            if updateServerList then
                updateServerList()
            end
        end)
    end)
end)

-- Основной цикл обновления (инкрементальный, оптимизированный)
task.spawn(function()
    local ENTRY_TTL_SEC = 180.0 -- авто-удаление старше 3 минут
    
    while gui and gui.Parent do
        local now = os.clock()
        
        if wantImmediate or (now - lastTick) >= UPDATE_INTERVAL then
            wantImmediate = false
            lastTick = now
            
            local ok, data = apiGetJSON(250)
            
            if ok and type(data) == "table" and type(data.items) == "table" then
                local best = pickBestByServer(data.items)
                
                if not firstSnapshotDone then
                    -- Первый снимок: только запоминаем, ничего не рисуем
                    for _, d in pairs(best) do
                        SeenHashes[hashOf({jobId = d.jobId, moneyStr = d.moneyStr, playersRaw = d.playersRaw})] = true
                    end
                    firstSnapshotDone = true
                else
                    -- Инкрементально добавляем ТОЛЬКО новые хэши
                    local anyChanged = false
                    
                    for _, d in pairs(best) do
                        local h = hashOf({jobId = d.jobId, moneyStr = d.moneyStr, playersRaw = d.playersRaw})
                        
                        if not SeenHashes[h] then
                            SeenHashes[h] = true
                            updateItem(d.jobId, d)
                            anyChanged = true
                        else
                            -- Если запись уже «видели», просто обновим цифры онлайна/таймштамп
                            if Entries[d.jobId] then
                                Entries[d.jobId].data.curPlayers = d.curPlayers
                                Entries[d.jobId].data.maxPlayers = d.maxPlayers
                                Entries[d.jobId].lastSeen = os.clock()
                            end
                        end
                    end
                    
                    -- Чистим протухшие
                    for id, e in pairs(Entries) do
                        if (os.clock() - e.lastSeen) > ENTRY_TTL_SEC then
                            removeItem(id)
                        end
                    end
                    
                    task.defer(resortPaint)
                end
            end
        end
        
        task.wait(0.05) -- мягкий цикл
    end
end)


-- Периодическая проверка Auto Join (с проверкой флага)
task.spawn(function()
    while true do
        pcall(function()
            task.wait(2)
            -- Проверяем флаг перед каждой попыткой
            if State.AutoJoin and not isJoining and checkAutoJoin then
                checkAutoJoin()
            elseif not State.AutoJoin then
                -- Если выключили - останавливаем все попытки
                isJoining = false
            end
        end)
    end
end)

-- Очистка списка мертвых серверов каждые 5 минут
task.spawn(function()
    while true do
        task.wait(300) -- 5 минут
        failedServers = {} -- Очищаем список мертвых серверов
    end
end)
