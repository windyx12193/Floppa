-- FLOPPA AUTO JOINER - v4.8e (safe-boot, debug prints, TEA->XOR fallback)
local AUTO_INJECT_URL = "https://raw.githubusercontent.com/windyx12193/Floppa/main/aj.lua"
local FIXED_HOTKEY    = Enum.KeyCode.T

local function log(...) print("[Floppa]", ...) end
local function err(...) warn("[Floppa][ERR]", ...) end

local okTop, topErr = pcall(function()
    log("step 1: services")
    local Players      = game:GetService("Players")
    local UIS          = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local HttpService  = game:GetService("HttpService")

    -- === FS helpers
    log("step 2: fs check")
    local function hasFS()
        return typeof(writefile)=="function"
           and typeof(readfile)=="function"
           and typeof(isfile)=="function"
           and typeof(makefolder)=="function"
    end
    local CFG_DIR = "workspace/.floppa_aj"
    local CFG_BIN = CFG_DIR.."/config.bin"
    local CFG_TXT = CFG_DIR.."/config.txt"
    local SECRET  = "floppa_secure_key_v2"
    if hasFS() then pcall(makefolder, CFG_DIR) end

    -- === Base64
    local function b64enc(data)
        local t='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        local out, i = {}, 1
        while i <= #data do
            local a = data:byte(i) or 0; i=i+1
            local b = data:byte(i) or 0; i=i+1
            local c = data:byte(i) or 0; i=i+1
            local n = a*65536 + b*256 + c
            out[#out+1]=t:sub( (math.floor(n/262144)%64)+1, (math.floor(n/262144)%64)+1 )
            out[#out+1]=t:sub( (math.floor(n/4096)%64)+1  , (math.floor(n/4096)%64)+1 )
            out[#out+1]= (i-1>#data) and '=' or t:sub( (math.floor(n/64)%64)+1, (math.floor(n/64)%64)+1 )
            out[#out+1]= (i>#data)   and '=' or t:sub( (n%64)+1, (n%64)+1 )
        end
        return table.concat(out)
    end
    local function b64dec(data)
        local t='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        local d={} for i=1,#t do d[t:byte(i)]=i-1 end
        data=data:gsub('[^%w%+/=]','')
        local out, bytes, i = {}, {data:byte(1,#data)}, 1
        while i<=#bytes do
            local c1=d[bytes[i]]; i=i+1; local c2=d[bytes[i]]; i=i+1
            local c3b=bytes[i]; i=i+1; local c4b=bytes[i]; i=i+1
            if not c1 or not c2 then break end
            local c3=(c3b and c3b~=61) and d[c3b] or nil
            local c4=(c4b and c4b~=61) and d[c4b] or nil
            local n = (c1<<18) | (c2<<12) | ((c3 or 0)<<6) | (c4 or 0)
            out[#out+1]=string.char( (n>>16)&255 )
            if c3 then out[#out+1]=string.char( (n>>8)&255 ) end
            if c4 then out[#out+1]=string.char( n&255 ) end
        end
        return table.concat(out)
    end

    -- === Crypto: TEA (если есть bit32) или XOR fallback
    log("step 3: crypto init")
    local useTEA = (type(bit32)=="table" and bit32.bxor~=nil)
    local function encBytes(plain, key)
        if useTEA then
            local band, bor, bxor = bit32.band, bit32.bor, bit32.bxor
            local lshift, rshift  = bit32.lshift, bit32.rshift
            local function u32(x) return band(x, 0xFFFFFFFF) end
            local function be_u32(s,i) local b1,b2,b3,b4=s:byte(i,i+3); return u32(bor(lshift(b1 or 0,24), lshift(b2 or 0,16), lshift(b3 or 0,8), (b4 or 0))) end
            local function put_u32(x) return string.char(band(rshift(x,24),255), band(rshift(x,16),255), band(rshift(x,8),255), band(x,255)) end
            local function keyFrom(s)
                local b={s:byte(1,#s)} while #b<16 do b[#b+1]=0 end
                local k1=u32(bor(lshift(b[1],24),lshift(b[2],16),lshift(b[3],8),(b[4] or 0)))
                local k2=u32(bor(lshift(b[5],24),lshift(b[6],16),lshift(b[7],8),(b[8] or 0)))
                local k3=u32(bor(lshift(b[9],24),lshift(b[10],16),lshift(b[11],8),(b[12] or 0)))
                local k4=u32(bor(lshift(b[13],24),lshift(b[14],16),lshift(b[15],8),(b[16] or 0)))
                return {k1,k2,k3,k4}
            end
            local function teaBlock(v0,v1,k)
                local sum,delta=0,0x9E3779B9
                for _=1,32 do
                    sum=u32(sum+delta)
                    v0=u32(v0+bxor(bxor(lshift(v1,4)+k[1], v1+sum), rshift(v1,5)+k[2]))
                    v1=u32(v1+bxor(bxor(lshift(v0,4)+k[3], v0+sum), rshift(v0,5)+k[4]))
                end
                return v0,v1
            end
            local function ks(key, nonce8, counter)
                local n0=be_u32(nonce8,1); local n1=be_u32(nonce8,5)
                local c0=u32(rshift(counter,32)); local c1=u32(counter)
                local blk=put_u32(n0)..put_u32(n1)..put_u32(c0)..put_u32(c1)
                local v0=be_u32(blk,1); local v1=be_u32(blk,5)
                local y0,y1=teaBlock(v0,v1,key)
                return put_u32(y0)..put_u32(y1)
            end
            local function guid8()
                local g=HttpService:GenerateGUID(false):gsub("-",""):sub(1,16)
                local out={} for i=1,#g,2 do out[#out+1]=string.char(tonumber(g:sub(i,i+1),16) or 0) end
                return table.concat(out)
            end
            local K=keyFrom(key); local nonce=guid8()
            local out={nonce}; local i,ctr=1,0
            while i<=#plain do
                local stream=ks(K,nonce,ctr); ctr=ctr+1
                local chunk=plain:sub(i,i+7)
                local x={} for j=1,#chunk do x[j]=string.char(bit32.bxor(chunk:byte(j), stream:byte(j))) end
                out[#out+1]=table.concat(x); i=i+8
            end
            return "T"..b64enc(table.concat(out)) -- префикс T = TEA
        else
            -- XOR fallback
            local function prng(seed)
                local s=0; for i=1,#seed do s=(s+seed:byte(i))%0x7fffffff end; if s==0 then s=0x13579B end
                return function() s=(1103515245*s+12345)%0x7fffffff; return s & 0xFF end
            end
            local nonce = tostring(os.time())..":"..tostring(math.random(1,1e9))
            local stream = prng(key.."|"..nonce)
            local out={} for i=1,#plain do out[i]=string.char(bit32 and bit32.bxor(plain:byte(i), stream()) or ((plain:byte(i) ~ stream())%256)) end
            return "X"..nonce.."|"..b64enc(table.concat(out)) -- префикс X = XOR
        end
    end
    local function decBytes(blob, key)
        if not blob or #blob<1 then return nil end
        local tag = blob:sub(1,1)
        if tag=="T" then
            if not (type(bit32)=="table" and bit32.bxor) then return nil end
            blob = blob:sub(2)
            local data = b64dec(blob); if #data<8 then return nil end
            local band, bor, bxor = bit32.band, bit32.bor, bit32.bxor
            local lshift, rshift  = bit32.lshift, bit32.rshift
            local function u32(x) return band(x, 0xFFFFFFFF) end
            local function be_u32(s,i) local b1,b2,b3,b4=s:byte(i,i+3); return u32(bor(lshift(b1 or 0,24), lshift(b2 or 0,16), lshift(b3 or 0,8), (b4 or 0))) end
            local function put_u32(x) return string.char(band(rshift(x,24),255), band(rshift(x,16),255), band(rshift(x,8),255), band(x,255)) end
            local function keyFrom(s)
                local b={s:byte(1,#s)} while #b<16 do b[#b+1]=0 end
                local k1=u32(bor(lshift(b[1],24),lshift(b[2],16),lshift(b[3],8),(b[4] or 0)))
                local k2=u32(bor(lshift(b[5],24),lshift(b[6],16),lshift(b[7],8),(b[8] or 0)))
                local k3=u32(bor(lshift(b[9],24),lshift(b[10],16),lshift(b[11],8),(b[12] or 0)))
                local k4=u32(bor(lshift(b[13],24),lshift(b[14],16),lshift(b[15],8),(b[16] or 0)))
                return {k1,k2,k3,k4}
            end
            local function teaBlock(v0,v1,k)
                local sum,delta=0,0x9E3779B9
                for _=1,32 do
                    sum=u32(sum+delta)
                    v0=u32(v0+bxor(bxor(lshift(v1,4)+k[1], v1+sum), rshift(v1,5)+k[2]))
                    v1=u32(v1+bxor(bxor(lshift(v0,4)+k[3], v0+sum), rshift(v0,5)+k[4]))
                end
                return v0,v1
            end
            local function ks(key, nonce8, counter)
                local n0=be_u32(nonce8,1); local n1=be_u32(nonce8,5)
                local c0=u32(rshift(counter,32)); local c1=u32(counter)
                local blk=put_u32(n0)..put_u32(n1)..put_u32(c0)..put_u32(c1)
                local v0=be_u32(blk,1); local v1=be_u32(blk,5)
                local y0,y1=teaBlock(v0,v1,key)
                return put_u32(y0)..put_u32(y1)
            end
            local nonce = data:sub(1,8)
            local cipher= data:sub(9)
            local K=keyFrom(key)
            local out, i, ctr = {}, 1, 0
            while i<=#cipher do
                local stream=ks(K,nonce,ctr); ctr=ctr+1
                local chunk=cipher:sub(i,i+7)
                local x={} for j=1,#chunk do x[j]=string.char(bit32.bxor(chunk:byte(j), stream:byte(j))) end
                out[#out+1]=table.concat(x); i=i+8
            end
            return table.concat(out)
        elseif tag=="X" then
            blob = blob:sub(2)
            local sep = blob:find("|",1,true); if not sep then return nil end
            local nonce = blob:sub(1,sep-1)
            local payload = b64dec(blob:sub(sep+1))
            local function prng(seed)
                local s=0; for i=1,#seed do s=(s+seed:byte(i))%0x7fffffff end; if s==0 then s=0x13579B end
                return function() s=(1103515245*s+12345)%0x7fffffff; return s & 0xFF end
            end
            local stream = prng(key.."|"..nonce)
            local out={} for i=1,#payload do out[i]=string.char(bit32 and bit32.bxor(payload:byte(i), stream()) or ((payload:byte(i) ~ stream())%256)) end
            return table.concat(out)
        end
        return nil
    end

    -- === Config API
    local Config = {}
    function Config.Save(tbl)
        if not hasFS() then return false end
        local ok = pcall(function()
            local plain = HttpService:JSONEncode({
                MinMS         = tonumber(tbl.MinMS) or 0,
                AutoJoin      = tbl.AutoJoin and true or false,
                JoinRetry     = tonumber(tbl.JoinRetry) or 0,
                IgnoreEnabled = tbl.IgnoreEnabled and true or false,
                IgnoreNames   = tbl.IgnoreNames or {},
                AutoInject    = tbl.AutoInject and true or false,
            })
            local blob = encBytes(plain, SECRET)
            writefile(CFG_BIN, blob)
        end)
        if ok then return true end
        pcall(writefile, CFG_TXT, ("MIN M/S = %s\nA/J = %s\nJOIN RETRY = %s\nENABLE IGNORE LIST = %s\nIGNORE NAMES ='%s'\n"):format(
            tostring(tbl.MinMS or 0), tostring(tbl.AutoJoin and true or false), tostring(tbl.JoinRetry or 0),
            tostring(tbl.IgnoreEnabled and true or false), table.concat(tbl.IgnoreNames or {}, ",")
        ))
        return false
    end
    function Config.Load()
        if not hasFS() then return nil end
        if isfile(CFG_BIN) then
            local ok, blob = pcall(readfile, CFG_BIN)
            if ok and type(blob)=="string" and #blob>0 then
                local dec = decBytes(blob, SECRET)
                if dec then
                    local ok2,tbl = pcall(function() return HttpService:JSONDecode(dec) end)
                    if ok2 and type(tbl)=="table" then
                        tbl.MinMS         = tonumber(tbl.MinMS) or 0
                        tbl.AutoJoin      = tbl.AutoJoin and true or false
                        tbl.JoinRetry     = tonumber(tbl.JoinRetry) or 0
                        tbl.IgnoreEnabled = tbl.IgnoreEnabled and true or false
                        if type(tbl.IgnoreNames)~="table" then tbl.IgnoreNames={} end
                        tbl.AutoInject    = tbl.AutoInject and true or false
                        return tbl
                    end
                end
            end
        end
        if isfile(CFG_TXT) then
            local ok, txt = pcall(readfile, CFG_TXT)
            if ok and type(txt)=="string" then
                local cfg = {MinMS=0, AutoJoin=false, JoinRetry=0, IgnoreEnabled=false, IgnoreNames={}, AutoInject=false}
                for line in (txt.."\n"):gmatch("(.-)\n") do
                    local k,v = line:match("^%s*([%w%s/]+)%s*=%s*(.-)%s*$")
                    if k and v then
                        k=k:gsub("%s+"," "):upper()
                        if k=="MIN M/S" then cfg.MinMS=tonumber(v) or 0
                        elseif k=="A/J" then cfg.AutoJoin=(v=="true" or v=="True")
                        elseif k=="JOIN RETRY" then cfg.JoinRetry=tonumber(v) or 0
                        elseif k=="ENABLE IGNORE LIST" then cfg.IgnoreEnabled=(v=="true" or v=="True")
                        elseif k=="IGNORE NAMES" then
                            local s=v:gsub("^'%s*",""):gsub("%s*'$","")
                            for tok in s:gmatch("([^,%s]+)") do cfg.IgnoreNames[#cfg.IgnoreNames+1]=tok end
                        end
                    end
                end
                return cfg
            end
        end
        return nil
    end

    -- === GUI parent
    log("step 4: gui parent")
    local function getGuiParent()
        local okH, hui = pcall(function() return gethui and gethui() end)
        if okH and hui then return hui end
        local okC, core = pcall(function() return game:GetService("CoreGui") end)
        if okC then return core end
        return Players.LocalPlayer:WaitForChild("PlayerGui")
    end
    local parent = getGuiParent()
    local old = parent:FindFirstChild("FloppaAutoJoinerGui"); if old then pcall(function() old:Destroy() end) end

    -- === Style / helpers
    log("step 5: build ui")
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
    local function setFont(lbl, weight) local ok=pcall(function()
        if weight=="bold" then lbl.Font=Enum.Font.GothamBold
        elseif weight=="medium" then lbl.Font=Enum.Font.GothamMedium
        else lbl.Font=Enum.Font.Gotham end end)
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
        local t=mkLabel(h, text, 18, "bold", COLORS.textPrimary); t.Size=UDim2.new(1,0,1,0); return h
    end
    local function mkToggle(parent, text, default)
        local row=Instance.new("Frame"); row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
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
        local row=Instance.new("Frame"); row.BackgroundColor3=COLORS.surface2; row.BackgroundTransparency=ALPHA.card
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

    -- === Blur (лёгкий)
    local blur=Lighting:FindFirstChild("FloppaLightBlur") or Instance.new("BlurEffect")
    blur.Name="FloppaLightBlur"; blur.Size=0; blur.Enabled=false; blur.Parent=Lighting
    local function setBlur(e)
        if e then blur.Enabled=true; TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=4}):Play()
        else TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Size=0}):Play(); task.delay(0.16,function() blur.Enabled=false end) end
    end

    -- === GUI root
    log("step 6: gui create")
    local gui=Instance.new("ScreenGui"); gui.Name="FloppaAutoJoinerGui"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=1e6; gui.Parent=parent
    local main=Instance.new("Frame"); main.Name="Main"; main.Size=UDim2.new(0,980,0,560); main.Position=UDim2.new(0.5,-490,0.5,-280)
    main.BackgroundColor3=COLORS.surface; main.BackgroundTransparency=ALPHA.panel; main.Parent=gui
    roundify(main,14); stroke(main, COLORS.purpleSoft, 1.5, 0.35); padding(main,10,10,10,10)

    local header=Instance.new("Frame"); header.Size=UDim2.new(1,0,0,48); header.BackgroundColor3=COLORS.surface2; header.BackgroundTransparency=ALPHA.card; header.Parent=main
    roundify(header,10); stroke(header); padding(header,14,6,14,6)
    mkLabel(header,"FLOPPA AUTO JOINER",20,"bold",COLORS.textPrimary).Size=UDim2.new(0.65,0,1,0)
    local hk=mkLabel(header,"OPEN GUI KEY:  T",16,"medium",COLORS.textWeak); hk.AnchorPoint=Vector2.new(1,0.5); hk.Position=UDim2.new(1,-14,0.5,0); hk.Size=UDim2.new(0.32,0,1,0); hk.TextXAlignment=Enum.TextXAlignment.Right

    local left=Instance.new("ScrollingFrame"); left.Size=UDim2.new(0,300,1,-58); left.Position=UDim2.new(0,0,0,58); left.BackgroundTransparency=1
    left.ScrollBarThickness=6; left.ScrollingDirection=Enum.ScrollingDirection.Y; left.CanvasSize=UDim2.new(0,0,0,0); left.Parent=main
    local leftPad=padding(left,0,0,0,10)
    local leftList=Instance.new("UIListLayout"); leftList.Padding=UDim.new(0,10); leftList.SortOrder=Enum.SortOrder.LayoutOrder; leftList.Parent=left
    local function updateLeftCanvas() left.CanvasSize=UDim2.new(0,0,0,leftList.AbsoluteContentSize.Y+leftPad.PaddingBottom.Offset) end
    leftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLeftCanvas)

    local right=Instance.new("Frame"); right.Size=UDim2.new(1,-320,1,-58); right.Position=UDim2.new(0,320,0,58)
    right.BackgroundColor3=COLORS.surface2; right.BackgroundTransparency=ALPHA.card; right.Parent=main
    roundify(right,12); stroke(right); padding(right,12,12,12,12)

    mkHeader(left,"PRIORITY ACTIONS")
    local autoJoinRow, autoJoin, applyAutoJoin = mkToggle(left, "AUTO JOIN", false)
    local jrRow, joinRetryState, jrBox = mkStackInput(left, "JOIN RETRY", "50", "50", true)

    mkHeader(left,"MONEY FILTERS")
    local msRow, minMSState, msBox = mkStackInput(left, "MIN M/S", "100", "100", true)

    mkHeader(left,"НАСТРОЙКИ")
    local autoInjectRow, autoInject, applyAutoInject = mkToggle(left, "AUTO INJECT", false)
    local ignoreListRow, ignoreToggle, applyIgnoreToggle = mkToggle(left, "ENABLE IGNORE LIST", false)
    local ignoreRow, ignoreState, ignoreBox = mkStackInput(left, "IGNORE NAMES", "name1,name2,...", "", false)

    local listHeader=mkHeader(right,"AVAILABLE LOBBIES"); listHeader.Size=UDim2.new(1,0,0,40)
    local scroll=Instance.new("ScrollingFrame"); scroll.BackgroundTransparency=1; scroll.Size=UDim2.new(1,0,1,-50); scroll.Position=UDim2.new(0,0,0,46)
    scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.ScrollBarThickness=6; scroll.Parent=right
    local listLay=Instance.new("UIListLayout"); listLay.SortOrder=Enum.SortOrder.LayoutOrder; listLay.Padding=UDim.new(0,8); listLay.Parent=scroll
    local function addLobbyItem(nameText, moneyPerSec)
        local item=Instance.new("Frame"); item.Size=UDim2.new(1,-6,0,52); item.BackgroundColor3=COLORS.surface; item.BackgroundTransparency=ALPHA.panel
        item.Parent=scroll; roundify(item,10); stroke(item, COLORS.purpleSoft, 1, 0.35); padding(item,12,6,12,6)
        mkLabel(item, string.upper(nameText), 18, "bold", COLORS.textPrimary).Size=UDim2.new(0.5,-10,1,0)
        local moneyLbl=mkLabel(item, string.upper(moneyPerSec), 17, "medium", Color3.fromRGB(130,255,130))
        moneyLbl.AnchorPoint=Vector2.new(0.5,0.5); moneyLbl.Position=UDim2.new(0.62,0,0.5,0); moneyLbl.Size=UDim2.new(0.34,0,1,0); moneyLbl.TextXAlignment=Enum.TextXAlignment.Center
        local joinBtn=Instance.new("TextButton"); joinBtn.Text="JOIN"; setFont(joinBtn,"bold"); joinBtn.TextSize=18; joinBtn.TextColor3=Color3.fromRGB(22,22,22)
        joinBtn.AutoButtonColor=true; joinBtn.BackgroundColor3=Color3.fromRGB(67,232,113); joinBtn.Size=UDim2.new(0,84,0,36); joinBtn.AnchorPoint=Vector2.new(1,0.5); joinBtn.Position=UDim2.new(1,-8,0.5,0)
        roundify(joinBtn,10); stroke(joinBtn, Color3.fromRGB(0,0,0), 1, 0.7); joinBtn.Parent=item
        joinBtn.MouseButton1Click:Connect(function() log("[JOIN]", nameText) end)
        task.defer(function() scroll.CanvasSize=UDim2.new(0,0,0,listLay.AbsoluteContentSize.Y+10) end)
    end
    for i=1,6 do addLobbyItem("BRAINROT NAME "..i, "MONEY/SECOND") end

    -- === State + config
    log("step 7: state")
    local State = {
        AutoJoin=false, AutoInject=false, IgnoreEnabled=false,
        JoinRetry=tonumber(jrBox.Text) or 50,
        MinMS=tonumber(msBox.Text) or 100,
        IgnoreNames={}
    }
    local LOADING=true
    local function strToList(s) local t={} for tok in (s or ""):gmatch("([^,%s]+)") do t[#t+1]=tok end return t end
    local function listToStr(t) return table.concat(t or {}, ",") end
    local function applyConfigVisual()
        applyAutoJoin(State.AutoJoin, true)
        applyAutoInject(State.AutoInject, true)
        applyIgnoreToggle(State.IgnoreEnabled, true)
        jrBox.Text=tostring(State.JoinRetry); msBox.Text=tostring(State.MinMS)
        ignoreBox.Text=listToStr(State.IgnoreNames)
    end
    local cfg=Config.Load()
    if cfg then
        State.AutoJoin=cfg.AutoJoin; State.AutoInject=cfg.AutoInject; State.IgnoreEnabled=cfg.IgnoreEnabled
        State.JoinRetry=tonumber(cfg.JoinRetry) or State.JoinRetry
        State.MinMS=tonumber(cfg.MinMS) or State.MinMS
        State.IgnoreNames=cfg.IgnoreNames or {}
        applyConfigVisual()
    end
    LOADING=false
    local function saveNow()
        if LOADING then return end
        Config.Save({
            MinMS=State.MinMS, AutoJoin=State.AutoJoin, JoinRetry=State.JoinRetry,
            IgnoreEnabled=State.IgnoreEnabled, IgnoreNames=State.IgnoreNames, AutoInject=State.AutoInject
        })
    end
    autoJoin.Changed=function(v) State.AutoJoin=v; saveNow() end
    autoInject.Changed=function(v) State.AutoInject=v; saveNow() end
    ignoreToggle.Changed=function(v) State.IgnoreEnabled=v; saveNow() end
    jrBox.FocusLost:Connect(function() State.JoinRetry=tonumber(jrBox.Text) or State.JoinRetry; saveNow() end)
    msBox.FocusLost:Connect(function() State.MinMS=tonumber(msBox.Text) or State.MinMS; saveNow() end)
    ignoreState.Changed=function(t) State.IgnoreNames=strToList(t); saveNow() end

    -- === Auto inject queue
    log("step 8: autoinject")
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
        s=s.."  local src=safeget('"..url.."')\n"
        s=s.."  if src then local f=loadstring(src); if f then pcall(f) end end\n"
        s=s.."end)\n"
        return s
    end
    local function queueReinject(url) local q=pickQueue(); if q and url~="" then q(makeBootstrap(url)) end end
    if State.AutoInject then queueReinject(AUTO_INJECT_URL) end
    Players.LocalPlayer.OnTeleport:Connect(function(st)
        if State.AutoInject and st==Enum.TeleportState.Started then queueReinject(AUTO_INJECT_URL) end
    end)

    -- === Show/hide
    log("step 9: hotkey bind")
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
                frame.Position=UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end)
    end
    makeDraggable(main, header)
    task.defer(function() updateLeftCanvas(); setVisible(true,true); log("step 10: ready") end)
end)

if not okTop then
    warn("[Floppa][FATAL]", topErr)
end
