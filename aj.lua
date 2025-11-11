--[[ FLOPPA AUTO JOINER v5.7 (robust regex + debug)
     - MIN M/S в МИЛЛИОНАХ
     - Работает с: "Name  |  $22.5M/s  |  7/8  |  uuid  |  time"
]]

---------------- USER/API SETTINGS ----------------
local AUTO_INJECT_URL   = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY      = Enum.KeyCode.T
local SETTINGS_PATH     = "floppa_aj_settings.json"

local SERVER_URL        = "https://server-eta-two-29.vercel.app/"
local API_KEY           = "autojoiner_3b1e6b7f_ka97bj1x_8v4ln5ja"

local TARGET_PLACE_ID   = 109983668079237
local PULL_INTERVAL_SEC = 2.0
local ENTRY_TTL_SEC     = 180.0
local FRESH_AGE_SEC     = 12.0

local DEBUG_NETWORK     = true
---------------------------------------------------

local Players         = game:GetService("Players")
local UIS             = game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local Lighting        = game:GetService("Lighting")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- FS helpers
local function hasFS() return typeof(writefile)=="function" and typeof(readfile)=="function" and typeof(isfile)=="function" end
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

-- Singleton cleanup
local function findGuiParent()
    local okH, hui = pcall(function() return gethui and gethui() end)
    if okH and hui then return hui end
    local okC, core = pcall(function() return game:GetService("CoreGui") end)
    if okC then return core end
    return Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
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

-- Persisted state (load first)
local State = {
    AutoJoin      = false,
    AutoInject    = false,
    IgnoreEnabled = false,
    JoinRetry     = 50,
    MinMS         = 1,   -- МИЛЛИОНЫ
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

-- UI helpers/styles (коротко)
local COLORS = {
    purpleDeep=Color3.fromRGB(96,63,196), purple=Color3.fromRGB(134,102,255), purpleSoft=Color3.fromRGB(160,135,255),
    surface=Color3.fromRGB(18,18,22), surface2=Color3.fromRGB(26,26,32),
    textPrimary=Color3.fromRGB(238,238,245), textWeak=Color3.fromRGB(190,190,200),
    on=Color3.fromRGB(64,222,125), off=Color3.fromRGB(120,120,130),
    joinBtn=Color3.fromRGB(67,232,113), stroke=Color3.fromRGB(70,60,140)
}
local ALPHA={panel=0.12, card=0.18}
local function roundify(o, px) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0, px or 10); c.Parent=o; return c end
local function stroke(o, col, th, tr) local s=Instance.new("UIStroke"); s.Color=col or COLORS.stroke; s.Thickness=th or 1; s.Transparency=tr or 0.25; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o; return s end
local function padding(o,l,t,r,b) local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,l or 0); p.PaddingTop=UDim.new(0,t or 0); p.PaddingRight=UDim.new(0,r or 0); p.PaddingBottom=UDim.new(0,b or 0); p.Parent=o; return p end
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
    local g=Instance.new("UIGradient"); g.Color=ColorSequence.new{ColorSequenceKeypoint.new(0,COLORS.purpleDeep),ColorSequenceKeypoint.new(1,COLORS.purple)}
    g.Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(1,0.4)}; g.Rotation=90; g.Parent=h
    mkLabel(h, text, 18, "bold", COLORS.textPrimary).Size=UDim2.new(1,0,1,0); return h
end
local function mkToggle(parent, text, default)
    local row=Instance.new("Frame"); row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card; row.Size=UDim2.new(1,0,0,44); row.Parent=parent
    roundify(row,10); stroke(row); padding(row,12,0,12,0)
    mkLabel(row, text, 17, "medium", COLORS.textPrimary).Size=UDim2.new(1,-80,1,0)
    local sw=Instance.new("TextButton"); sw.Text=""; sw.AutoButtonColor=false; sw.BackgroundColor3=Color3.fromRGB(40,40,48); sw.BackgroundTransparency=0.2
    sw.Size=UDim2.new(0,62,0,28); sw.AnchorPoint=Vector2.new(1,0.5); sw.Position=UDim2.new(1,-6,0.5,0); sw.Parent=row
    roundify(sw,14); stroke(sw, COLORS.purpleSoft, 1, 0.35)
    local dot=Instance.new("Frame"); dot.Size=UDim2.new(0,24,0,24); dot.Position=UDim2.new(0,2,0.5,-12); dot.BackgroundColor3=COLORS.off; dot.Parent=sw; roundify(dot,12)
    local state={Value=default and true or false, Changed=nil}
    local function apply(v, instant)
        state.Value=v
        local pos=v and UDim2.new(1,-26,0.5,-12) or UDim2.new(0,2,0.5,-12)
        local col=v and COLORS.on or COLORS.off
        if instant then dot.Position=pos; dot.BackgroundColor3=col; sw.BackgroundColor3=v and Color3.fromRGB(55,58,74) or Color3.fromRGB(40,40,48)
        else
            TweenService:Create(dot, TweenInfo.new(0.13, Enum.EasingStyle.Sine), {Position=pos}):Play()
            TweenService:Create(dot, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundColor3=col}):Play()
            TweenService:Create(sw, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundColor3=v and Color3.fromRGB(55,58,74) or Color3.fromRGB(40,40,48)}):Play()
        end
    end
    apply(state.Value,true)
    sw.MouseButton1Click:Connect(function() apply(not state.Value,false); if state.Changed then task.defer(function() pcall(state.Changed,state.Value) end) end end)
    return row, state, apply
end
local function mkStackInput(parent, title, placeholder, defaultText, isNumeric)
    local row=Instance.new("Frame"); row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card; row.Size=UDim2.new(1,0,0,70); row.Parent=parent
    roundify(row,10); stroke(row); padding(row,12,8,12,12)
    mkLabel(row, title, 16, "medium", COLORS.textPrimary).Size=UDim2.new(1,0,0,18)
    local box=Instance.new("TextBox"); box.PlaceholderText=placeholder or ""; box.Text=defaultText or ""; box.ClearTextOnFocus=false
    box.TextSize=17; box.TextColor3=COLORS.textPrimary; box.PlaceholderColor3=COLORS.textWeak; box.BackgroundColor3=Color3.fromRGB(32,32,38); box.BackgroundTransparency=0.15
    box.Size=UDim2.new(1,0,0,30); box.Position=UDim2.new(0,0,0,30); roundify(box,8); stroke(box, COLORS.purpleSoft, 1, 0.35); box.Parent=row
    if isNumeric then box:GetPropertyChangedSignal("Text"):Connect(function() box.Text=box.Text:gsub("[^%d]","") end) end
    local state={}
    box.FocusLost:Connect(function() state.Value=isNumeric and (tonumber(box.Text) or 0) or box.Text; if state.Changed then pcall(state.Changed,state.Value) end end)
    return row, state, box
end

-- Blur
local blur=Lighting:FindFirstChild("FloppaLightBlur") or Instance.new("BlurEffect"); blur.Name="FloppaLightBlur"; blur.Size=0; blur.Enabled=false; blur.Parent=Lighting
local function setBlur(e) if e then blur.Enabled=true; TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=4}):Play()
    else TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=0}):Play(); task.delay(0.16,function() blur.Enabled=false end) end end

-- Root GUI
local parent = findGuiParent() or Players.LocalPlayer:WaitForChild("PlayerGui")
local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=1e6; gui.Parent=parent
local main=Instance.new("Frame"); main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(0.5,-490,0.5,-280)
main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui; roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, 0.35); padding(main,10,10,10,10)

local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
roundify(header,10); stroke(header); padding(header,14,6,14,6)
mkLabel(header,"FLOPPA AUTO JOINER",20,"bold",COLORS.textPrimary).Size=UDim2.new(0.6,0,1,0)
local hotkeyInfo=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak); hotkeyInfo.AnchorPoint=Vector2.new(1,0.5); hotkeyInfo.Position=UDim2.new(1,-14,0.5,0); hotkeyInfo.Size=UDim2.new(0.35,0,1,0); hotkeyInfo.TextXAlignment=Enum.TextXAlignment.Right

local refreshBtn=Instance.new("TextButton"); refreshBtn.Text="Refresh"; setFont(refreshBtn,"medium"); refreshBtn.TextSize=14; refreshBtn.TextColor3=COLORS.textPrimary
refreshBtn.BackgroundColor3=COLORS.surface; refreshBtn.BackgroundTransparency=0.1; refreshBtn.Size=UDim2.new(0,80,0,28); refreshBtn.AnchorPoint=Vector2.new(1,0.5); refreshBtn.Position=UDim2.new(1,-180,0.5,0); refreshBtn.AutoButtonColor=true
roundify(refreshBtn,8); stroke(refreshBtn, COLORS.purpleSoft, 1, 0.4); refreshBtn.Parent=header

local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1; left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
local leftPad=padding(left,0,0,0,10); local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end; leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58); right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main
roundify(right,12); stroke(right); padding(right,12,12,12,12)

local statsLbl = mkLabel(right, "", 13, "medium", COLORS.textWeak)
statsLbl.AnchorPoint=Vector2.new(1,0); statsLbl.Position=UDim2.new(1,-10,0,8); statsLbl.Size=UDim2.new(0,280,0,16); statsLbl.TextXAlignment=Enum.TextXAlignment.Right

mkHeader(left,"PRIORITY ACTIONS")
local _, autoJoin,     _  = mkToggle(left, "AUTO JOIN", State.AutoJoin)
local _, _,            jrBox = mkStackInput(left, "JOIN RETRY", "50", tostring(State.JoinRetry), true)
mkHeader(left,"MONEY FILTERS")
local _, _,            msBox = mkStackInput(left, "MIN M/S", "1 (= $1M/s)", tostring(State.MinMS), true)
mkHeader(left,"НАСТРОЙКИ")
local _, autoInject,   _  = mkToggle(left, "AUTO INJECT", State.AutoInject)
local _, ignoreToggle, _  = mkToggle(left, "ENABLE IGNORE LIST", State.IgnoreEnabled)
local _, ignoreState,  ignoreBox = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", table.concat(State.IgnoreNames, ","), false)

local listHeader=mkHeader(right,"AVAILABLE LOBBIES"); listHeader.Size=UDim2.new(1,0,0,40)
local scroll=Instance.new("ScrollingFrame"); scroll.BackgroundTransparency=1; scroll.Size=UDim2.new(1,0,1,-50); scroll.Position=UDim2.new(0,0,0,46); scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.ScrollBarThickness=6; scroll.Parent=right
local listLay=Instance.new("UIListLayout"); listLay.SortOrder=Enum.SortOrder.LayoutOrder; listLay.Padding=UDim.new(0,8); listLay.Parent=scroll

-- Save settings
local function parseIgnore(s) local r={} for tok in (s or ""):gmatch("([^,%s]+)") do r[#r+1]=tok end return r end
local function saveSettings()
    saveJSON(SETTINGS_PATH, { AutoJoin=autoJoin.Value, AutoInject=autoInject.Value, IgnoreEnabled=ignoreToggle.Value,
        JoinRetry=tonumber(jrBox.Text) or State.JoinRetry, MinMS=tonumber(msBox.Text) or State.MinMS, IgnoreNames=parseIgnore(ignoreBox.Text) })
end
autoJoin.Changed     = function(v) State.AutoJoin=v; saveSettings() end
autoInject.Changed   = function(v) State.AutoInject=v; saveSettings() end
ignoreToggle.Changed = function(v) State.IgnoreEnabled=v; saveSettings() end
jrBox.FocusLost:Connect(function() State.JoinRetry=tonumber(jrBox.Text) or State.JoinRetry; saveSettings() end)
msBox.FocusLost:Connect(function() State.MinMS=tonumber(msBox.Text) or State.MinMS; saveSettings() end)
ignoreState.Changed  = function(txt) State.IgnoreNames=parseIgnore(txt); saveSettings() end

-- AutoInject (queue only)
local function pickQueue()
    local q=nil; pcall(function() if syn and type(syn.queue_on_teleport)=="function" then q=syn.queue_on_teleport end end)
    if not q and type(queue_on_teleport)=="function" then q=queue_on_teleport end
    if not q and type(queueteleport)=="function" then q=queueteleport end
    if not q and type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then q=fluxus.queue_on_teleport end
    return q
end
local function makeBootstrap()
    local s=""; s=s.."task.spawn(function()\n"
    s=s.."if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end\n"
    s=s.."local okP,Pl=pcall(function() return game:GetService('Players') end)\n"
    s=s.."if okP and Pl then local t0=os.clock(); while not Pl.LocalPlayer and os.clock()-t0<10 do task.wait(0.05) end end\n"
    s=s.."pcall(function() getgenv().__FLOPPA_UI_ACTIVE=nil end)\n"
    s=s.."local function safeget(u) for i=1,3 do local ok,res=pcall(function() return game:HttpGet(u) end); if ok and type(res)=='string' and #res>0 then return res end; task.wait(1) end end\n"
    s=s.."local src=safeget('"..AUTO_INJECT_URL.."')\n"
    s=s.."if src then local f=loadstring(src); if f then pcall(f) end end\n"
    s=s.."end)\n"; return s
end
local function queueReinject() local q=pickQueue(); if q then q(makeBootstrap()) end end
if State.AutoInject then queueReinject() end
Players.LocalPlayer.OnTeleport:Connect(function(st) if autoInject.Value and st==Enum.TeleportState.Started then queueReinject() end end)

-- Money parser
local multipliers={K=1e3,M=1e6,B=1e9,T=1e12}
local function parseMoney(text)
    local s=tostring(text or "")
    s=s:gsub("\194\160"," "):gsub(",", ""):gsub("%*%*",""):gsub("%s+",""):upper()
    local num,unit=s:match("%$(%d+%.?%d*)([KMBT]?)/S")
    if not num then num,unit=s:match("%$(%d+%.?%d*)([KMBT]?)") end
    if not num then return 0 end
    return math.floor((tonumber(num) or 0) * (multipliers[unit or ""] or 1) + 0.5)
end
local function minThreshold() return (tonumber(msBox.Text) or State.MinMS or 0) * 1e6 end

-- Filters
local function visibleByFilters(d)
    if d.mps < minThreshold() then return false end
    if ignoreToggle.Value and #State.IgnoreNames>0 then
        for _,nm in ipairs(State.IgnoreNames) do if #nm>0 and d.name:lower():find(nm:lower(),1,true) then return false end end
    end
    return true
end

-- Entries
local Entries, Order = {}, {}
local function formatPlayers(p,m) return string.format("%d/%d", p or 0, m or 0) end

local function ensureEntryFrame(jobId, data)
    local e=Entries[jobId]; if e and e.frame then return e.frame end
    local item=Instance.new("Frame"); item.Size=UDim2.new(1,-6,0,52); item.BackgroundColor3=COLORS.surface; item.BackgroundTransparency=ALPHA.panel; item.Parent=scroll
    roundify(item,10); stroke(item, COLORS.purpleSoft, 1, 0.35); padding(item,12,6,12,6)
    local nameLbl=mkLabel(item, string.upper(data.name), 18, "bold", COLORS.textPrimary); nameLbl.Size=UDim2.new(0.44,-10,1,0)
    local moneyLbl=mkLabel(item, string.upper(data.moneyStr or ""), 17, "medium", Color3.fromRGB(130,255,130))
    moneyLbl.AnchorPoint=Vector2.new(0,0.5); moneyLbl.Position=UDim2.new(0.46,0,0.5,0); moneyLbl.Size=UDim2.new(0.22,0,1,0); moneyLbl.TextXAlignment=Enum.TextXAlignment.Left
    local playersLbl=mkLabel(item, formatPlayers(data.players,data.max), 16, "medium", COLORS.textWeak)
    playersLbl.AnchorPoint=Vector2.new(0,0.5); playersLbl.Position=UDim2.new(0.69,0,0.5,0); playersLbl.Size=UDim2.new(0.12,0,1,0); playersLbl.TextXAlignment=Enum.TextXAlignment.Left
    local joinBtn=Instance.new("TextButton"); joinBtn.Text="JOIN"; setFont(joinBtn,"bold"); joinBtn.TextSize=18; joinBtn.TextColor3=Color3.fromRGB(22,22,22)
    joinBtn.AutoButtonColor=true; joinBtn.BackgroundColor3=COLORS.joinBtn; joinBtn.Size=UDim2.new(0,84,0,36); joinBtn.AnchorPoint=Vector2.new(1,0.5); joinBtn.Position=UDim2.new(1,-8,0.5,0)
    roundify(joinBtn,10); stroke(joinBtn, Color3.fromRGB(0,0,0), 1, 0.7); joinBtn.Parent=item
    joinBtn.MouseButton1Click:Connect(function()
        local tries=tonumber(jrBox.Text) or State.JoinRetry or 0
        local delaySec=0.10; joinBtn.Text="JOIN…"
        for i=1,math.max(tries,1) do
            local ok=pcall(function() TeleportService:TeleportToPlaceInstance(TARGET_PLACE_ID, jobId, Players.LocalPlayer) end)
            if ok then joinBtn.Text="OK"; break else joinBtn.Text=("RETRY %d/%d"):format(i,tries); task.wait(delaySec) end
        end
        task.delay(0.8,function() if joinBtn then joinBtn.Text="JOIN" end end)
    end)
    Entries[jobId]={data=data, frame=item, firstSeen=os.clock(), lastSeen=os.clock()}
    return item
end
local function updateEntry(jobId, data)
    local e=Entries[jobId]
    if not e then ensureEntryFrame(jobId, data); table.insert(Order,jobId); e=Entries[jobId]
    else if data.mps>(e.data.mps or 0) then e.data=data end; e.lastSeen=os.clock() end
    local item=e.frame; if item and item.Parent then
        local kids=item:GetChildren()
        if kids[1] and kids[1].ClassName=="TextLabel" then kids[1].Text=string.upper(e.data.name) end
        if kids[2] and kids[2].ClassName=="TextLabel" then kids[2].Text=string.upper(e.data.moneyStr or "") end
        if kids[3] and kids[3].ClassName=="TextLabel" then kids[3].Text=formatPlayers(e.data.players,e.data.max) end
    end
end
local function removeEntry(jobId)
    local e=Entries[jobId]; if not e then return end
    if e.frame then pcall(function() e.frame:Destroy() end) end
    Entries[jobId]=nil; for i=#Order,1,-1 do if Order[i]==jobId then table.remove(Order,i) break end end
end
local function refreshListVisual()
    table.sort(Order,function(a,b) local ea,eb=Entries[a],Entries[b]; if not ea or not eb then return a<b end
        if ea.data.mps~=eb.data.mps then return ea.data.mps>eb.data.mps end; return ea.lastSeen>eb.lastSeen end)
    local visibleCount=0
    for idx,jobId in ipairs(Order) do
        local e=Entries[jobId]; if e and e.frame and e.frame.Parent==scroll then
            e.frame.LayoutOrder=idx; local age=os.clock()-e.firstSeen
            if age<=FRESH_AGE_SEC then e.frame.BackgroundColor3=Color3.fromRGB(22,28,26); e.frame.BackgroundTransparency=ALPHA.panel
            else
                e.frame.BackgroundColor3=COLORS.surface
                local staleness=math.clamp((os.clock()-e.lastSeen)/ENTRY_TTL_SEC,0,1)
                e.frame.BackgroundTransparency=ALPHA.panel+0.05*staleness
            end
            visibleCount+=1
        end
    end
    local minM=tonumber(msBox.Text) or State.MinMS or 0
    statsLbl.Text=string.format("fetched: %s • shown: %d • min: %dM/s", "—", visibleCount, minM)
    task.defer(function() scroll.CanvasSize=UDim2.new(0,0,0,listLay.AbsoluteContentSize.Y+10) end)
end

-- trim
local function trimSpaces(s) s=tostring(s or ""):gsub("\226\128\139",""):gsub("\194\160"," "); s=s:gsub("^%s+",""):gsub("%s+$",""); return s end

-- ROBUST parseLine: чистая регэксп-схема
local function parseLine(line)
    if not line or not line:match("%S") then return nil end
    local raw=line
    line=line:gsub("%*%*",""):gsub("\t"," "):gsub("\194\160"," "):gsub("%s+"," ")
    -- 1) точный матч: Name | $11.2M/s | 7/8 | uuid |
    local name, num, unit, pNow, pMax, jobId =
        line:match("^%s*(.-)%s*|%s*%$%s*([%d%.]+)%s*([KMBTkmbt]?)%s*/%s*[sS]%s*|%s*(%d+)%s*/%s*(%d+)%s*|%s*([%w%-]+)")
    if not name then
        -- 2) попробуем мягкий split по |
        local parts={} for token in line:gmatch("([^|]+)") do parts[#parts+1]=trimSpaces(token) end
        if #parts>=4 then
            name=parts[1]
            local mstr=parts[2]
            num,unit=mstr:match("%$%s*([%d%.]+)%s*([KMBTkmbt]?)%s*/%s*[sS]")
            if not num then num,unit=mstr:match("%$%s*([%d%.]+)%s*([KMBTkmbt]?)") end
            local p1,p2=parts[3]:match("(%d+)%s*/%s*(%d+)"); pNow=tonumber(p1 or "0") or 0; pMax=tonumber(p2 or "0") or 0
            jobId=parts[4]:match("([%w%-]+)")
        end
    end
    if not (name and num and jobId) then
        if DEBUG_NETWORK then
            print("[Floppa][skip] cannot parse line:", raw)
        end
        return nil
    end
    local unitUp=(unit or ""):upper()
    local money = math.floor((tonumber(num) or 0) * (multipliers[unitUp] or 1) + 0.5)
    return { name=name, moneyStr=string.format("$%s%s/s", num, unitUp), mps=money,
             players=tonumber(pNow or 0) or 0, max=tonumber(pMax or 0) or 0, jobId=jobId }
end

-- counters
local last_total_lines, last_kept = 0, 0

-- parse all
local function parseAll(raw)
    local body=tostring(raw or "")
    body=body:gsub("^\239\187\191",""):gsub("\r\n","\n"):gsub("\r","\n"):gsub("<[Bb][Rr]%s*/?>","\n"):gsub("</?%w+[^>]*>",""):gsub("&nbsp;"," "):gsub("\194\160"," ")
    local now=os.clock()
    local best={}
    local cnt=0
    for line in body:gmatch("[^\n]+") do
        if line:match("%S") then
            cnt+=1
            local d=parseLine(line)
            if d and visibleByFilters(d) then
                local cur=best[d.jobId]
                if (not cur) or d.mps>cur.mps then best[d.jobId]=d end
            end
        end
    end
    last_total_lines = cnt
    for jobId,d in pairs(best) do updateEntry(jobId,d) end
    for jobId,e in pairs(Entries) do if (now-e.lastSeen)>ENTRY_TTL_SEC then removeEntry(jobId) end end
    refreshListVisual()
    last_kept=0 for _ in pairs(best) do last_kept+=1 end
    if DEBUG_NETWORK then
        local totalNow=0 for _ in pairs(Entries) do totalNow+=1 end
        print(string.format("[Floppa] parseAll: totalEntries=%d keptNow=%d", totalNow, last_kept))
    end
end

-- URL (cache-buster БЕЗ опечаток)
local function buildURL(useKey)
    local base=SERVER_URL
    local sep = base:find("%?") and "&" or "?"
    local url = string.format("%s%s_cb=%d%d", base, sep, os.time(), math.random(1000,9999))
    if useKey ~= false then url = url .. "&key=" .. tostring(API_KEY) end
    return url
end

-- pull once
local function pullOnce()
    local ok, body = pcall(function() return game:HttpGet(buildURL(true)) end)
    if (not ok) or (type(body)~="string") or (#body==0) then
        if DEBUG_NETWORK then warn("[Floppa] with-key failed; fallback no-key") end
        ok, body = pcall(function() return game:HttpGet(buildURL(false)) end)
    end
    if ok and type(body)=="string" and #body>0 then
        local lines=0 for _ in body:gmatch("[^\r\n]+") do lines+=1 end
        if DEBUG_NETWORK then print("[Floppa] fetched bytes:", #body, "lines:", lines) end
        parseAll(body)
        statsLbl.Text=string.format("fetched: %d • shown: %d • min: %dM/s", last_total_lines, last_kept, tonumber(msBox.Text) or State.MinMS or 0)
    else
        for id in pairs(Entries) do removeEntry(id) end
        statsLbl.Text="Network error"
        if DEBUG_NETWORK then warn("[Floppa] pullOnce failed") end
    end
end

-- polling loop
task.spawn(function()
    while gui and gui.Parent do
        local ok=pcall(pullOnce)
        if not ok and DEBUG_NETWORK then warn("[Floppa] pullOnce crashed") end
        task.wait(PULL_INTERVAL_SEC)
    end
end)
refreshBtn.MouseButton1Click:Connect(function() if DEBUG_NETWORK then print("[Floppa] manual_refresh") end; pcall(pullOnce) end)

-- show/hide & drag
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
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
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
UIS.InputBegan:Connect(function(input,gp) if not gp and input.KeyCode==FIXED_HOTKEY then setVisible(not opened,false) end end)
makeDraggable(main, header)
task.defer(function() updateLeftCanvas(); setVisible(true,true) end)
