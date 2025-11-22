-- CHILLI HUB AUTO JOIN + FLOPPA AUT0SEARCH (brainrot profit filter)
-- ETag feed + GameFull retry (20x 0.3s) + auto search of good server

local FEED_URL     = "https://server-eta-two-29.vercel.app/api/feed?limit=120"
local MIN_PROFIT_M = 50 -- минимальная прибыль (M/s) ДЛЯ СЕРВЕРА И ДЛЯ БРЕЙНРОТА

local Players         = game:GetService("Players")
local LP              = Players.LocalPlayer or Players.PlayerAdded:Wait()
local VIM             = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Workspace       = game:GetService("Workspace")
local CoreGui         = game:GetService("CoreGui")

print("=== CHILLI HUB AUTO JOIN — ETag + AutoSearch ===")

---------------------------------------------------------------------
-- КОНФИГ AUT0SEARCH (между перезаходами)
---------------------------------------------------------------------
local CFG_FILE = "chilli_autosearch.json"

local function hasfs()
    return typeof(isfile) == "function"
        and typeof(readfile) == "function"
        and typeof(writefile) == "function"
end

local AutoCfg = {
    autoSearchEnabled = false, -- кнопка AutoSearch (ON/OFF)
    searchActive      = false, -- сейчас идёт глобальный поиск
    badJobIds         = {},    -- jobId -> true (серверы, которые не подходят / фейлятся)
}

local function loadCfg()
    if not hasfs() then return end
    if not isfile(CFG_FILE) then return end

    local ok, raw = pcall(readfile, CFG_FILE)
    if not ok or not raw or raw == "" then return end

    local ok2, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not ok2 or type(data) ~= "table" then return end

    if type(data.autoSearchEnabled) == "boolean" then
        AutoCfg.autoSearchEnabled = data.autoSearchEnabled
    end
    if type(data.searchActive) == "boolean" then
        AutoCfg.searchActive = data.searchActive
    end
    if type(data.badJobIds) == "table" then
        AutoCfg.badJobIds = data.badJobIds
    end
end

local function saveCfg()
    if not hasfs() then return end
    local ok, raw = pcall(function()
        return HttpService:JSONEncode(AutoCfg)
    end)
    if not ok then return end
    pcall(writefile, CFG_FILE, raw)
end

loadCfg()

---------------------------------------------------------------------
-- ПОИСК ЛУЧШЕГО БРЕЙНРОТА (как во floppa)
---------------------------------------------------------------------
local PlotsFolder = nil

local function getPlotsFolder(timeout)
    if PlotsFolder and PlotsFolder.Parent then
        return PlotsFolder
    end

    local ok, result = pcall(function()
        return Workspace:FindFirstChild("Plots") or Workspace:WaitForChild("Plots", timeout or 5)
    end)

    if ok then
        PlotsFolder = result
    else
        PlotsFolder = nil
    end

    return PlotsFolder
end

local function parseProfitNumber(text)
    local s = (text or ""):upper()
    s = s:gsub("%s+", ""):gsub("%$", ""):gsub("/S", "")
    local mult = 1
    local suf = s:match("([KMB])$")
    if suf == "K" then
        mult = 1e3
    elseif suf == "M" then
        mult = 1e6
    elseif suf == "B" then
        mult = 1e9
    end
    if suf then
        s = s:sub(1, #s - 1)
    end
    local n = tonumber(s)
    return n and (n * mult) or nil
end

local function findProfitLabel(gui)
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text and d.Text:find("/s") then
            return d
        end
    end
    return nil
end

local function getServerBestProfit()
    local plots = getPlotsFolder(5)
    if not plots then
        return nil
    end

    local bestProfit = nil

    -- 1) по атрибутам
    for _, inst in ipairs(plots:GetDescendants()) do
        if inst:IsA("Model") then
            local profit = inst:GetAttribute("ProfitPerSecond")
            if typeof(profit) == "number" then
                if not bestProfit or profit > bestProfit then
                    bestProfit = profit
                end
            end
        end
    end

    -- 2) по GUI (AnimalOverhead)
    for _, gui in ipairs(plots:GetDescendants()) do
        if gui:IsA("BillboardGui") and gui.Name == "AnimalOverhead" then
            local lbl = findProfitLabel(gui)
            if lbl then
                local profit = parseProfitNumber(lbl.Text or "")
                if profit then
                    if not bestProfit or profit > bestProfit then
                        bestProfit = profit
                    end
                end
            end
        end
    end

    return bestProfit -- сырое $/s
end

-- true/false, bestM
local function currentServerHasGoodBrainrot()
    local best = getServerBestProfit()
    if not best then
        return false, nil
    end
    local bestM = best / 1e6
    return bestM >= MIN_PROFIT_M, bestM
end

---------------------------------------------------------------------
-- ГЛОБ СТЕЙТ
---------------------------------------------------------------------
local JoinButtonRef = nil
local retrying      = false
local CurrentJobId  = nil

local S = {
    started          = false,
    lastTopId        = "",
    skip             = {}, -- jobId -> true (в этой сессии)
    autoSearchEnabled = AutoCfg.autoSearchEnabled and true or false,
}

local autoSearchRunning = false

local function isJobIdGloballySkipped(jobId)
    if not jobId or jobId == "" then
        return false
    end
    if S.skip[jobId] then
        return true
    end
    if AutoCfg.badJobIds and AutoCfg.badJobIds[jobId] then
        return true
    end
    return false
end

local clickByVIM, clickJoinButton -- форвард

---------------------------------------------------------------------
-- GameFull: 20 криков по Join с кд 0.3с, потом skip
---------------------------------------------------------------------
local function startRejoinSpam()
    if retrying then return end
    if not JoinButtonRef or not JoinButtonRef.Parent then
        print("⚠️ No JoinButtonRef for rejoin spam")
        return
    end
    retrying = true

    task.spawn(function()
        print("🚫 Game full, starting rejoin spam (20 clicks)...")
        for i = 1, 20 do
            if not retrying then break end
            if not JoinButtonRef or not JoinButtonRef.Parent then break end

            print("↻ Rejoin click", i, "/ 20 for jobId:", CurrentJobId or "nil")
            clickJoinButton(JoinButtonRef)
            task.wait(0.3)
        end

        print("⏹ Rejoin spam finished")
        retrying = false

        if CurrentJobId then
            S.skip[CurrentJobId] = true
            AutoCfg.badJobIds[CurrentJobId] = true
            saveCfg()
            print("❌ Skipping jobId after 20 failed attempts:", CurrentJobId)
        end
    end)
end

TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
    if player ~= LP then return end

    local isGameFull = false
    if typeof(result) == "EnumItem" then
        isGameFull = (result == Enum.TeleportResult.GameFull)
    else
        local s = tostring(result)
        if s:find("GameFull") then
            isGameFull = true
        end
    end

    if isGameFull then
        print("⚠️ TeleportInitFailed: GameFull |", tostring(errorMessage or ""))
        startRejoinSpam()
    end
end)

---------------------------------------------------------------------
-- ПОИСК ЭЛЕМЕНТОВ CHILLI HUB (Job-ID input + Join Job-ID)
---------------------------------------------------------------------
local function findChilliElements()
    local elements = {
        inputField = nil,
        joinButton = nil,
    }
    
    for _, gui in ipairs(CoreGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            local descendants = {}
            pcall(function()
                descendants = gui:GetDescendants()
            end)
            
            for _, obj in ipairs(descendants) do
                pcall(function()
                    -- INPUT
                    if obj:IsA("TextBox") then
                        local parent = obj.Parent
                        if parent then
                            for _, sibling in ipairs(parent:GetChildren()) do
                                if sibling:IsA("TextLabel") then
                                    local text = string.lower(sibling.Text or "")
                                    if text:find("job") and text:find("id") and text:find("input") then
                                        print("🎯 Found Job-ID input field!")
                                        elements.inputField = obj
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- JOIN кнопка
                    local function isJoinText(t)
                        t = string.lower(t or "")
                        return t:find("join") and t:find("job%-id")
                    end

                    if obj:IsA("TextButton") and isJoinText(obj.Text) then
                        print("🎯 Found Join Job-ID TextButton!")
                        elements.joinButton = obj
                        return
                    end

                    if obj:IsA("ImageButton") then
                        local label = obj:FindFirstChildOfClass("TextLabel")
                        if label and isJoinText(label.Text) then
                            print("🎯 Found Join Job-ID ImageButton!")
                            elements.joinButton = obj
                            return
                        end
                    end

                    if obj:IsA("TextLabel") and isJoinText(obj.Text) then
                        local parent = obj.Parent
                        local depth  = 0
                        local buttonCandidate = nil

                        while parent and depth < 5 do
                            if parent:IsA("TextButton") or parent:IsA("ImageButton") then
                                buttonCandidate = parent
                                break
                            end
                            parent = parent.Parent
                            depth = depth + 1
                        end

                        if buttonCandidate then
                            print("🎯 Found Join Job-ID via label -> parent button:", buttonCandidate:GetFullName())
                            elements.joinButton = buttonCandidate
                        else
                            print("🎯 Found Join Job-ID label (no button parent), using label:", obj:GetFullName())
                            elements.joinButton = obj
                        end
                    end
                end)
            end
        end
    end
    
    if elements.inputField then
        print("InputField:", elements.inputField:GetFullName())
    else
        print("InputField NOT FOUND")
    end

    if elements.joinButton then
        print("JoinButton:", elements.joinButton:GetFullName(), elements.joinButton.ClassName)
    else
        print("JoinButton NOT FOUND")
    end

    return elements
end

---------------------------------------------------------------------
-- ПАРСИНГ СТРОКИ ФИДА
---------------------------------------------------------------------
local function uuid(s)
    return (s or ""):match(
        "([%x][%x][%x][%x][%x][%x][%x][%x]%-" ..
        "%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)"
    )
end

local function parseServerLine(line)
    if not line then return nil end

    line = line:gsub("\226\128\139","") -- невидимые символы

    local profitPart = line:match("%*%*%$([%d%.]+[KMBT]?)M/s%*%*")

    local jobId = uuid(line)

    if not jobId then
        jobId = line:match("|%s*([%x]+)%s*$")
    end

    if profitPart and jobId then
        local multiplier = 1
        if profitPart:find("K") then
            multiplier = 0.001
            profitPart = profitPart:gsub("K","")
        elseif profitPart:find("B") then
            multiplier = 1000
            profitPart = profitPart:gsub("B","")
        elseif profitPart:find("T") then
            multiplier = 1000000
            profitPart = profitPart:gsub("T","")
        else
            profitPart = profitPart:gsub("M","")
        end

        local profit = tonumber(profitPart)
        if profit then
            profit = profit * multiplier
            return {
                profitM = profit,
                jobId   = jobId,
                rawLine = line
            }
        end
    end

    return nil
end

---------------------------------------------------------------------
-- HTTP с ETag
---------------------------------------------------------------------
local _etag = nil

local function http_get(u, timeoutSec)
    local url = ("%s&t=%d"):format(u, math.floor(os.clock()*1000)%2147483647)
    local to  = math.max(1, math.floor(timeoutSec or 3))
    local H   = {["accept"]="text/plain",["cache-control"]="no-cache",["pragma"]="no-cache"}
    if _etag then
        H["If-None-Match"] = _etag
    end

    local providers = {
        function()
            if syn and syn.request then
                local ok,r = pcall(syn.request,{
                    Url = url, Method = "GET", Headers = H, Timeout = to
                })
                if ok and r then
                    if r.Headers and r.Headers.ETag then
                        _etag = r.Headers.ETag
                    end
                    return r.StatusCode, r.Body
                end
            end
        end,
        function()
            if http and http.request then
                local ok,r = pcall(http.request,{
                    Url = url, Method = "GET", Headers = H, Timeout = to
                })
                if ok and r then
                    if r.Headers and r.Headers.ETag then
                        _etag = r.Headers.ETag
                    end
                    return r.StatusCode, r.Body
                end
            end
        end,
        function()
            if request then
                local ok,r = pcall(request,{
                    Url = url, Method = "GET", Headers = H, Timeout = to
                })
                if ok and r then
                    if r.Headers and r.Headers.ETag then
                        _etag = r.Headers.ETag
                    end
                    return r.StatusCode, r.Body
                end
            end
        end,
        function()
            if fluxus and fluxus.request then
                local ok,r = pcall(fluxus.request,{
                    Url = url, Method = "GET", Headers = H, Timeout = to
                })
                if ok and r then
                    if r.Headers and r.Headers.ETag then
                        _etag = r.Headers.ETag
                    end
                    return r.StatusCode, r.Body
                end
            end
        end,
    }

    for _,fn in ipairs(providers) do
        local sc,body = fn()
        if sc then return sc,body end
    end
    return nil,nil
end

local function fetch_top_item()
    local sc, body = http_get(FEED_URL, 3)
    if sc ~= 200 or not body or #body == 0 then
        return nil
    end
    local top = body:match("([^\r\n]+)")
    if not top or #top == 0 then
        return nil
    end
    return parseServerLine(top)
end

---------------------------------------------------------------------
-- ВВОД JOBID И КЛИК
---------------------------------------------------------------------
local function fastSetJobId(textBox, jobId)
    print("⚡ Fast inserting JobId:", jobId)

    pcall(function()
        textBox:CaptureFocus()
    end)

    pcall(function()
        textBox.Text = ""
        textBox.Text = jobId
    end)

    pcall(function()
        if textBox.ReleaseFocus then
            textBox:ReleaseFocus()
        end
    end)

    pcall(function()
        if textBox.FocusLost then
            firesignal(textBox.FocusLost)
        end
    end)
end

clickByVIM = function(obj)
    local pos  = obj.AbsolutePosition
    local size = obj.AbsoluteSize
    local x = pos.X + size.X / 2
    local y = pos.Y + size.Y / 2

    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.05)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

clickJoinButton = function(button)
    print("🖱️ Clicking Join Job-ID...")

    local clicked = false

    pcall(function()
        if button.MouseButton1Down then
            firesignal(button.MouseButton1Down)
            clicked = true
        end
    end)
    pcall(function()
        if button.MouseButton1Up then
            firesignal(button.MouseButton1Up)
            clicked = true
        end
    end)
    pcall(function()
        if button.MouseButton1Click then
            firesignal(button.MouseButton1Click)
            clicked = true
        end
    end)

    local okClick, clickConnections = pcall(function()
        return getconnections(button.MouseButton1Click)
    end)
    if okClick and clickConnections then
        for _, conn in ipairs(clickConnections) do
            pcall(function()
                conn:Fire()
                clicked = true
            end)
        end
    end

    local okActivate = pcall(function()
        button:Activate()
    end)
    if okActivate then
        clicked = true
    end

    if not clicked then
        local okVIM = pcall(function()
            clickByVIM(button)
        end)
        if okVIM then
            print("✅ Clicked via VirtualInputManager")
            clicked = true
        end
    end

    if clicked then
        print("✅ Join Job-ID click sent")
        return true
    else
        print("❌ Failed to click Join Job-ID")
        return false
    end
end

---------------------------------------------------------------------
-- ПОИСК ТАБА "Server" ТОЛЬКО ДЛЯ CHILLI HUB
---------------------------------------------------------------------
local function isServerTabText(t)
    t = string.lower(t or "")
    return t:find("server") ~= nil
end

local function isInsideOurAutoJoinGui(obj)
    local p = obj
    while p do
        if p:IsA("ScreenGui") and p.Name == "ChilliHubAutoJoin_ETag" then
            return true
        end
        p = p.Parent
    end
    return false
end

local function isBadRootGui(gui)
    if not gui or not gui:IsA("ScreenGui") then return true end

    local n = string.lower(gui.Name)

    if n == "robloxgui"
        or n == "devconsolemaster"
        or n:find("devconsole")
        or n:find("settings")
        or n:find("chat")
        or n:find("topbar") then
        return true
    end

    return false
end

local function getServerTabButtonFromObj(obj)
    if obj:IsA("TextButton") then
        if isServerTabText(obj.Text) then
            return obj
        end
        return nil
    end

    if obj:IsA("ImageButton") then
        local label = obj:FindFirstChildOfClass("TextLabel")
        if label and isServerTabText(label.Text) then
            return obj
        end
        return nil
    end

    if obj:IsA("TextLabel") and isServerTabText(obj.Text) then
        local parent = obj.Parent
        local depth  = 0
        while parent and depth < 5 do
            if parent:IsA("TextButton") or parent:IsA("ImageButton") then
                return parent
            end
            parent = parent.Parent
            depth  = depth + 1
        end
        return obj
    end

    return nil
end

local function findServerTabButton()
    for _, root in ipairs(CoreGui:GetChildren()) do
        if root:IsA("ScreenGui") and not isBadRootGui(root) then
            local descendants = {}
            pcall(function()
                descendants = root:GetDescendants()
            end)

            for _, obj in ipairs(descendants) do
                if not isInsideOurAutoJoinGui(obj) then
                    local candidate = getServerTabButtonFromObj(obj)
                    if candidate then
                        print("🎯 Found ChilliHub Server tab:", candidate:GetFullName())
                        return candidate
                    end
                end
            end
        end
    end

    print("Server tab NOT FOUND (Chilli Hub)")
    return nil
end

-- Открыть Server и дождаться появления Job-ID UI
local function ensureServerTabAndChilliElements(statusLabel)
    while S.started do
        local serverBtn = findServerTabButton()
        if not serverBtn then
            if statusLabel then
                statusLabel.Text = "AutoSearch: Server tab not found, retrying in 5s..."
            end
            local t = 0
            while t < 5 and S.started do
                task.wait(0.5)
                t = t + 0.5
            end
        else
            if statusLabel then
                statusLabel.Text = "AutoSearch: clicking Server tab..."
            end
            pcall(function()
                clickByVIM(serverBtn)
            end)

            local timeout = os.clock() + 10
            while S.started and os.clock() < timeout do
                local elements = findChilliElements()
                if elements.inputField and elements.joinButton then
                    if statusLabel then
                        statusLabel.Text = ("AutoSearch: Server tab ready.\nWaiting new servers ≥ %.1f M/s...")
                            :format(MIN_PROFIT_M)
                    end
                    return elements
                end
                task.wait(0.4)
            end

            if statusLabel then
                statusLabel.Text = "AutoSearch: Join Job-ID UI not found, try again in 5s..."
            end
            local t2 = 0
            while t2 < 5 and S.started do
                task.wait(0.5)
                t2 = t2 + 0.5
            end
        end
    end

    return nil
end

---------------------------------------------------------------------
-- АВТОПОДКЛЮЧЕНИЕ ПО JOBID
---------------------------------------------------------------------
local function automateJoin(server, elements)
    if not elements.inputField then
        print("❌ No input field found")
        return false
    end
    if not elements.joinButton then
        print("❌ No join button found")
        return false
    end

    JoinButtonRef = elements.joinButton
    CurrentJobId  = server.jobId

    print(("🤖 Auto-joining: %.3f M/s | %s (#%d)")
        :format(server.profitM or 0, server.jobId or "?", #(server.jobId or "")))

    fastSetJobId(elements.inputField, server.jobId)
    task.wait(0.5)

    local clicked = clickJoinButton(elements.joinButton)
    if clicked then
        print("🎉 FIRST JOIN CLICK SENT!")
        task.wait(2)
        return true
    end
    return false
end

---------------------------------------------------------------------
-- ПУЛЛЕР ФИДА
---------------------------------------------------------------------
local function baseline_snapshot()
    local it = fetch_top_item()
    if it and it.jobId then
        S.lastTopId = it.jobId
        print("📌 Baseline lastTopId =", S.lastTopId, "profit:", it.profitM)
    end
end

local function poll_loop(elements, statusLabel)
    baseline_snapshot()

    while S.started do
        local it = fetch_top_item()

        if it and it.jobId and it.jobId ~= S.lastTopId then
            S.lastTopId = it.jobId

            if isJobIdGloballySkipped(it.jobId) then
                print("⏭ Skipped previously failed/bad server:", it.jobId)
            else
                print("🆕 New top server:", it.jobId, it.profitM or 0, "M/s")

                if it.profitM and it.profitM >= MIN_PROFIT_M then
                    if statusLabel then
                        statusLabel.Text = ("New server: %.1f M/s\nJobId: %s\nJoining...")
                            :format(it.profitM, it.jobId)
                    end
                    local ok = automateJoin(it, elements)
                    if not ok then
                        if statusLabel then
                            statusLabel.Text = "Join failed (UI click problem), waiting next..."
                        end
                    end
                else
                    print("⏭ New server but profit too low:", it.profitM or 0, "M/s")
                end
            end
        end

        if S.started then
            if statusLabel then
                statusLabel.Text = ("Waiting new servers ≥ %.1f M/s..."):format(MIN_PROFIT_M)
            end
            local t = 0
            while t < 2.2 and S.started do
                task.wait(0.1)
                t = t + 0.1
            end
        end
    end
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local function createUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "ChilliHubAutoJoin_ETag"
    gui.ResetOnSpawn = false

    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
        gui.Parent = (gethui and gethui()) or CoreGui
    end)
    if not gui.Parent then
        gui.Parent = LP:WaitForChild("PlayerGui")
    end
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 340, 0, 190)
    frame.Position = UDim2.new(0, 10, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(28,31,36)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 20)
    title.Position = UDim2.new(0, 10, 0, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.Text = "Chilli Hub Auto Join (ETag)"
    title.TextColor3 = Color3.fromRGB(236,239,244)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 80)
    status.Position = UDim2.new(0, 10, 0, 35)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextColor3 = Color3.fromRGB(190,196,206)
    status.Text = ("Min profit: %.1f M/s\nPress START to wait for new servers.")
        :format(MIN_PROFIT_M)
    status.Parent = frame

    local autoBtn = Instance.new("TextButton")
    autoBtn.Size = UDim2.new(1, -20, 0, 30)
    autoBtn.Position = UDim2.new(0, 10, 1, -80)
    autoBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
    autoBtn.Text = "AutoSearch: OFF"
    autoBtn.Font = Enum.Font.GothamBold
    autoBtn.TextSize = 14
    autoBtn.TextColor3 = Color3.fromRGB(10,10,10)
    autoBtn.Parent = frame

    local autoCorner = Instance.new("UICorner")
    autoCorner.CornerRadius = UDim.new(0, 8)
    autoCorner.Parent = autoBtn

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, -20, 0, 30)
    startBtn.Position = UDim2.new(0, 10, 1, -40)
    startBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
    startBtn.Text = "START"
    startBtn.Font = Enum.Font.GothamBold
    startBtn.TextSize = 16
    startBtn.TextColor3 = Color3.fromRGB(10,10,10)
    startBtn.Parent = frame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = startBtn

    return gui, status, startBtn, autoBtn
end

---------------------------------------------------------------------
-- AUT0SEARCH ЛОГИКА
---------------------------------------------------------------------
local function updateAutoBtnVisual(autoBtn)
    if not autoBtn then return end
    if S.autoSearchEnabled then
        autoBtn.Text = "AutoSearch: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(46,204,113)
    else
        autoBtn.Text = "AutoSearch: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
    end
end

local function startAutoSearch(statusLabel, startBtn)
    if autoSearchRunning then
        return
    end
    autoSearchRunning = true

    S.started           = true
    AutoCfg.searchActive = true
    saveCfg()

    if startBtn then
        startBtn.Text = "STOP"
        startBtn.BackgroundColor3 = Color3.fromRGB(46,204,113)
    end

    task.spawn(function()
        if statusLabel then
            statusLabel.Text = "AutoSearch: waiting 7s for brainrots to load..."
        end

        local waitTime = 7
        local elapsed  = 0
        while S.started and elapsed < waitTime do
            task.wait(0.5)
            elapsed = elapsed + 0.5
        end

        if not S.started then
            autoSearchRunning = false
            return
        end

        local hasGood, bestM = currentServerHasGoodBrainrot()
        if hasGood then
            local msg = ("✅ Found brainrot: %.2f M/s ≥ %.2f M/s.\nAutoSearch stopped.")
                :format(bestM or 0, MIN_PROFIT_M)
            print(msg)
            if statusLabel then
                statusLabel.Text = msg
            end

            AutoCfg.searchActive = false
            saveCfg()

            S.started = false
            if startBtn then
                startBtn.Text = "START"
                startBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
            end

            autoSearchRunning = false
            return
        else
            local msg
            if bestM then
                msg = ("❌ Best brainrot here: %.2f M/s < %.2f M/s.\nSearching new server...")
                    :format(bestM, MIN_PROFIT_M)
            else
                msg = ("❌ No brainrot ≥ %.2f M/s on this server.\nSearching new server...")
                    :format(MIN_PROFIT_M)
            end
            print(msg)
            if statusLabel then
                statusLabel.Text = msg
            end

            local myJobId = game.JobId
            if myJobId and myJobId ~= "" then
                AutoCfg.badJobIds[myJobId] = true
                saveCfg()
            end
        end

        local elements = ensureServerTabAndChilliElements(statusLabel)
        if not S.started then
            autoSearchRunning = false
            return
        end

        if not elements or not elements.inputField or not elements.joinButton then
            if statusLabel then
                statusLabel.Text = "❌ AutoSearch: failed to open Server/Join UI.\nStopping search."
            end
            AutoCfg.searchActive = false
            saveCfg()
            S.started = false
            if startBtn then
                startBtn.Text = "START"
                startBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
            end
            autoSearchRunning = false
            return
        end

        if statusLabel then
            statusLabel.Text = ("AutoSearch: hopping servers ≥ %.1f M/s..."):format(MIN_PROFIT_M)
        end

        poll_loop(elements, statusLabel)

        AutoCfg.searchActive = false
        saveCfg()
        if startBtn then
            startBtn.Text = "START"
            startBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
        end
        autoSearchRunning = false
    end)
end

---------------------------------------------------------------------
-- MAIN
---------------------------------------------------------------------
task.wait(1)

local gui, statusLabel, startBtn, autoBtn = createUI()

S.autoSearchEnabled = AutoCfg.autoSearchEnabled and true or false
updateAutoBtnVisual(autoBtn)

autoBtn.Activated:Connect(function()
    S.autoSearchEnabled       = not S.autoSearchEnabled
    AutoCfg.autoSearchEnabled = S.autoSearchEnabled
    if not S.autoSearchEnabled then
        AutoCfg.searchActive = false
    end
    saveCfg()
    updateAutoBtnVisual(autoBtn)
end)

startBtn.Activated:Connect(function()
    if S.started then
        S.started    = false
        retrying     = false
        CurrentJobId = nil

        AutoCfg.searchActive = false
        saveCfg()

        startBtn.Text = "START"
        startBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
        if statusLabel then
            statusLabel.Text = "Stopped."
        end
        return
    end

    retrying     = false
    CurrentJobId = nil

    if S.autoSearchEnabled then
        startAutoSearch(statusLabel, startBtn)
    else
        S.started = true
        if statusLabel then
            statusLabel.Text = "Searching Chilli Hub UI..."
        end

        local elements = findChilliElements()
        if not elements.inputField or not elements.joinButton then
            if statusLabel then
                statusLabel.Text = "❌ Chilli Hub elements not found.\nOpen Server tab first."
            end
            S.started = false
            return
        end

        startBtn.Text = "STOP"
        startBtn.BackgroundColor3 = Color3.fromRGB(46,204,113)
        if statusLabel then
            statusLabel.Text = ("Waiting NEW servers ≥ %.1f M/s..."):format(MIN_PROFIT_M)
        end

        task.spawn(function()
            poll_loop(elements, statusLabel)
            startBtn.Text = "START"
            startBtn.BackgroundColor3 = Color3.fromRGB(72,76,82)
        end)
    end
end)

-- автопродолжение автопоиска после телепорта
if AutoCfg.autoSearchEnabled and AutoCfg.searchActive then
    print("🔁 AutoSearch state restored: continuing search on this server...")
    task.spawn(function()
        task.wait(1.5)
        if not S.started then
            startAutoSearch(statusLabel, startBtn)
        end
    end)
end

print("=== CHILLI HUB AUTO JOIN LOADED (GameFull retry + skip + AutoSearch) ===")
