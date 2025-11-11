--[[
  Floppa Config Manager (TEA encrypt, compact fallback)
  Поля:
    MinMS            (number)
    AutoJoin         (boolean)
    JoinRetry        (number)
    IgnoreEnabled    (boolean)
    IgnoreNames      (table of strings) -> 'name1,name2,...'
  Файлы:
    workspace/.floppa_cfg/config.bin  (зашифровано TEA + Base64)
    workspace/.floppa_cfg/config.txt  (минимальный текст, если нет FS/ошибка)
]]

------------------ ПУТЬ К ФАЙЛАМ ------------------
local DIR   = "workspace/.floppa_cfg"   -- не «Загрузки» и не «Рабочий стол»
local BIN   = DIR .. "/config.bin"
local TXT   = DIR .. "/config.txt"

------------------ КЛЮЧ ШИФРОВАНИЯ ----------------
-- Поменяй строку, если хочешь свой ключ (длина любая; берутся первые 16 байт)
local SECRET = "floppa_secure_key_v2"

------------------ HELPERS: FS ---------------------
local HttpService = game:GetService("HttpService")

local function hasFS()
    return typeof(writefile)=="function"
       and typeof(readfile)=="function"
       and typeof(isfile)=="function"
       and typeof(makefolder)=="function"
end

local function ensureDir()
    if hasFS() then pcall(makefolder, DIR) end
end

------------------ HELPERS: Base64 ----------------
local B64 = (function()
    local enc_tbl = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local dec_tbl = {}
    for i=1,#enc_tbl do dec_tbl[string.byte(enc_tbl,i)] = i-1 end
    local function encode(data)
        local bytes = {string.byte(data,1,#data)}
        local out, n = {}, #bytes
        local i=1
        while i<=n do
            local b1 = bytes[i]   or 0; i=i+1
            local b2 = bytes[i]   or 0; i=i+1
            local b3 = bytes[i]   or 0; i=i+1
            local triple = b1*65536 + b2*256 + b3
            local c1 = math.floor(triple/262144) % 64
            local c2 = math.floor(triple/4096)   % 64
            local c3 = math.floor(triple/64)     % 64
            local c4 = triple % 64
            local p3 = (i-1>n+1)  -- сколько «пустых» байтов
            local p4 = (i-1>n)
            out[#out+1] = string.sub(enc_tbl,c1+1,c1+1)
            out[#out+1] = string.sub(enc_tbl,c2+1,c2+1)
            out[#out+1] = p3 and '=' or string.sub(enc_tbl,c3+1,c3+1)
            out[#out+1] = p4 and '=' or string.sub(enc_tbl,c4+1,c4+1)
        end
        return table.concat(out)
    end
    local function decode(data)
        local out, bytes, n = {}, {string.byte(data,1,#data)}, #data
        local i=1
        while i<=n do
            local c1 = dec_tbl[bytes[i]];   i=i+1
            local c2 = dec_tbl[bytes[i]];   i=i+1
            local c3b= bytes[i];            i=i+1
            local c4b= bytes[i];            i=i+1
            if not c1 or not c2 then break end
            local c3 = (c3b and c3b~=61) and dec_tbl[c3b] or nil
            local c4 = (c4b and c4b~=61) and dec_tbl[c4b] or nil
            local triple = (c1<<18) | (c2<<12) | ((c3 or 0)<<6) | (c4 or 0)
            local b1 = (triple>>16) & 255
            local b2 = (triple>>8)  & 255
            local b3 = triple       & 255
            out[#out+1] = string.char(b1)
            if c3 then out[#out+1] = string.char(b2) end
            if c4 then out[#out+1] = string.char(b3) end
        end
        return table.concat(out)
    end
    return {enc=encode, dec=decode}
end)()

------------------ HELPERS: TEA -------------------
-- Классический TEA: 64-битный блок, 128-битный ключ, 32 раунда.
-- Режим: CTR (счётчик), так что нет паддингов и можно шифровать любой размер.
local TEA = {}

local function to_u32(x) return x & 0xFFFFFFFF end
local function pack_u32_be(a,b,c,d)
    return string.char(
        (a>>24)&255, (a>>16)&255, (a>>8)&255, a&255,
        (b>>24)&255, (b>>16)&255, (b>>8)&255, b&255,
        (c>>24)&255, (c>>16)&255, (c>>8)&255, c&255,
        (d>>24)&255, (d>>16)&255, (d>>8)&255, d&255
    )
end
local function unpack_u32_be(s, i)
    local b1,b2,b3,b4 = s:byte(i,i+3)
    return ((b1<<24)|(b2<<16)|(b3<<8)|b4) & 0xFFFFFFFF
end

function TEA.keyFromString(str)
    -- первые 16 байт -> 4 u32
    local b = {string.byte(str,1,#str)}
    while #b<16 do b[#b+1]=0 end
    local k1 = ((b[1] <<24)|(b[2] <<16)|(b[3] <<8)| (b[4] or 0)) & 0xFFFFFFFF
    local k2 = ((b[5] <<24)|(b[6] <<16)|(b[7] <<8)| (b[8] or 0)) & 0xFFFFFFFF
    local k3 = ((b[9] <<24)|(b[10]<<16)|(b[11]<<8)| (b[12] or 0))& 0xFFFFFFFF
    local k4 = ((b[13]<<24)|(b[14]<<16)|(b[15]<<8)| (b[16] or 0))& 0xFFFFFFFF
    return {k1,k2,k3,k4}
end

function TEA.encryptBlock(v0,v1,key)
    local sum=0; local delta=0x9E3779B9
    local k1,k2,k3,k4 = key[1],key[2],key[3],key[4]
    for _=1,32 do
        sum = to_u32(sum + delta)
        v0  = to_u32(v0 + (((v1<<4)+k1) ~ (v1 + sum) ~ ((v1>>5) + k2)))
        v1  = to_u32(v1 + (((v0<<4)+k3) ~ (v0 + sum) ~ ((v0>>5) + k4)))
    end
    return v0,v1
end

-- CTR-поток: шифруем счётчик, затем XOR с данными
local function tea_keystream(key, nonce, counter)
    -- nonce: 8 байт, counter: 8 байт -> 16 байт -> 2x u32
    local v0 = unpack_u32_be(nonce,1)
    local v1 = unpack_u32_be(nonce,5)
    -- "counter" как 64-бит: high,low
    local c0 = (counter>>32) & 0xFFFFFFFF
    local c1 = counter & 0xFFFFFFFF
    local b  = pack_u32_be(v0, v1, c0, c1)
    local x0 = unpack_u32_be(b,1)
    local x1 = unpack_u32_be(b,5)
    local y0,y1 = TEA.encryptBlock(x0,x1,key)
    return pack_u32_be(0,0,y0,y1)  -- берём 8 байт keystream (нижние)
end

local function secureRandom8()
    -- простой nonce: GUID -> берём 8 байт
    local g = HttpService:GenerateGUID(false) -- "xxxxxxxx-xxxx-..."
    -- уберём дефисы, возьмём первые 16 hex -> 8 байт
    local hex = g:gsub("-", ""):sub(1,16)
    local out = {}
    for i=1,#hex,2 do
        local byte = tonumber(hex:sub(i,i+1),16) or 0
        out[#out+1] = string.char(byte)
    end
    return table.concat(out)
end

local function tea_encrypt_bytes(plain, keyStr)
    local key = TEA.keyFromString(keyStr)
    local nonce = secureRandom8()
    local out = {nonce} -- сохраним nonce в начале
    local counter = 0
    local i=1
    while i<=#plain do
        local ks = tea_keystream(key, nonce, counter)
        counter = counter + 1
        local chunk = plain:sub(i, i+7)
        local xored = table.create(#chunk)
        for j=1,#chunk do
            xored[j] = string.char( (chunk:byte(j) ~ ks:byte(j)) & 255 )
        end
        out[#out+1] = table.concat(xored)
        i = i + 8
    end
    return B64.enc(table.concat(out))
end

local function tea_decrypt_bytes(b64, keyStr)
    local data = B64.dec(b64 or "")
    if #data < 8 then return nil end
    local nonce = data:sub(1,8)
    local cipher= data:sub(9)
    local key   = TEA.keyFromString(keyStr)
    local out   = {}
    local counter=0
    local i=1
    while i<=#cipher do
        local ks = tea_keystream(key, nonce, counter)
        counter = counter + 1
        local chunk = cipher:sub(i, i+7)
        local xored = table.create(#chunk)
        for j=1,#chunk do
            xored[j] = string.char( (chunk:byte(j) ~ ks:byte(j)) & 255 )
        end
        out[#out+1] = table.concat(xored)
        i = i + 8
    end
    return table.concat(out)
end

------------------ API: SAVE / LOAD ----------------
local function compactText(cfg)
    -- Минимальный формат из твоего примера
    return table.concat({
        "MIN M/S = "..tostring(cfg.MinMS or 0),
        "A/J = "..tostring(cfg.AutoJoin and true or false),
        "JOIN RETRY = "..tostring(cfg.JoinRetry or 0),
        "ENABLE IGNORE LIST = "..tostring(cfg.IgnoreEnabled and true or false),
        "IGNORE NAMES ='"..table.concat(cfg.IgnoreNames or {}, ",").."'",  -- одинарные кавычки
        ""
    },"\n")
end

local Config = {}

function Config.Save(cfg)
    ensureDir()
    if not hasFS() then
        -- Нет доступа к FS — ничего не делаем
        return false, "no-fs"
    end
    -- Пытаемся сохранить зашифровано
    local okEnc, err = pcall(function()
        local plain = HttpService:JSONEncode({
            MinMS         = tonumber(cfg.MinMS) or 0,
            AutoJoin      = cfg.AutoJoin and true or false,
            JoinRetry     = tonumber(cfg.JoinRetry) or 0,
            IgnoreEnabled = cfg.IgnoreEnabled and true or false,
            IgnoreNames   = cfg.IgnoreNames or {},
        })
        local blob = tea_encrypt_bytes(plain, SECRET)
        writefile(BIN, blob)
    end)
    if okEnc then return true end

    -- На крайний случай — компактный текст (как просил)
    pcall(function()
        writefile(TXT, compactText(cfg))
    end)
    return false, "enc-fallback"
end

function Config.Load()
    if not hasFS() then return nil, "no-fs" end
    -- Сначала пытаемся прочитать зашифрованный бинарник
    if isfile(BIN) then
        local ok, data = pcall(readfile, BIN)
        if ok and type(data)=="string" and #data>0 then
            local dec = tea_decrypt_bytes(data, SECRET)
            if dec then
                local ok2, tbl = pcall(function() return HttpService:JSONDecode(dec) end)
                if ok2 and type(tbl)=="table" then
                    -- нормализуем
                    tbl.MinMS         = tonumber(tbl.MinMS) or 0
                    tbl.AutoJoin      = tbl.AutoJoin and true or false
                    tbl.JoinRetry     = tonumber(tbl.JoinRetry) or 0
                    tbl.IgnoreEnabled = tbl.IgnoreEnabled and true or false
                    if type(tbl.IgnoreNames)~="table" then tbl.IgnoreNames = {} end
                    return tbl
                end
            end
        end
    end
    -- Иначе — прочитаем компактный текст (fallback)
    if isfile(TXT) then
        local ok, data = pcall(readfile, TXT)
        if ok and type(data)=="string" then
            local cfg = {
                MinMS=0, AutoJoin=false, JoinRetry=0, IgnoreEnabled=false, IgnoreNames={}
            }
            for line in (data.."\n"):gmatch("(.-)\n") do
                local k,v = line:match("^%s*([%w%s/]+)%s*=%s*(.-)%s*$")
                if k and v then
                    k = k:gsub("%s+"," "):upper()
                    if k=="MIN M/S" then cfg.MinMS=tonumber(v) or 0
                    elseif k=="A/J" then cfg.AutoJoin=(v=="true" or v=="True")
                    elseif k=="JOIN RETRY" then cfg.JoinRetry=tonumber(v) or 0
                    elseif k=="ENABLE IGNORE LIST" then cfg.IgnoreEnabled=(v=="true" or v=="True")
                    elseif k=="IGNORE NAMES" then
                        local s = v
                        -- снять одинарные кавычки
                        s = s:gsub("^'%s*",""):gsub("%s*'$","")
                        cfg.IgnoreNames = {}
                        for token in s:gmatch("([^,%s]+)") do
                            table.insert(cfg.IgnoreNames, token)
                        end
                    end
                end
            end
            return cfg
        end
    end
    return nil, "not-found"
end

---------------------------------------------------
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
-- (раскомментируй и запусти один раз, чтобы проверить)

--[[
-- Сохранить:
local ok, why = Config.Save({
    MinMS = 100,
    AutoJoin = true,
    JoinRetry = 50,
    IgnoreEnabled = false,
    IgnoreNames = {"name1","name2","names3"},
})
print("Save:", ok, why or "")

-- Загрузить:
local cfg, err = Config.Load()
print("Load:", cfg and "ok" or "fail", err or "")
if cfg then
    print("MIN M/S =", cfg.MinMS)
    print("A/J =", cfg.AutoJoin)
    print("JOIN RETRY =", cfg.JoinRetry)
    print("ENABLE IGNORE LIST =", cfg.IgnoreEnabled)
    print("IGNORE NAMES ='"..table.concat(cfg.IgnoreNames,",").."'")
end
]]
---------------------------------------------------

return Config
