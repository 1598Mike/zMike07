--[[
    ic_behoerden · Hilfsfunktionen (Client, Server und Tests)
    Reines Lua ohne FiveM-Aufrufe.
]]

IC = IC or {}
local U = {}
IC.util = U

function U.trim(s)
    s = tostring(s == nil and '' or s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

function U.round(n) return math.floor((n or 0) + 0.5) end

function U.clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

function U.contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function U.find(list, pred)
    for i = 1, #list do
        if pred(list[i], i) then return list[i], i end
    end
    return nil
end

function U.filter(list, pred)
    local out = {}
    for i = 1, #list do
        if pred(list[i], i) then out[#out + 1] = list[i] end
    end
    return out
end

function U.map(list, fn)
    local out = {}
    for i = 1, #list do out[i] = fn(list[i], i) end
    return out
end

function U.keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- Stabile Sortierung (table.sort ist es nicht). key: Funktion, die einen vergleichbaren Wert liefert.
function U.sortBy(list, key, desc)
    local idx = {}
    for i, v in ipairs(list) do idx[i] = { v = v, k = key(v), i = i } end
    table.sort(idx, function(a, b)
        if a.k == b.k then return a.i < b.i end
        if desc then return a.k > b.k end
        return a.k < b.k
    end)
    local out = {}
    for i, e in ipairs(idx) do out[i] = e.v end
    return out
end

function U.deepcopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = U.deepcopy(x) end
    return out
end

function U.pad4(n) return string.format('%04d', n) end

-- 184250 -> "$184.250" (deutsche Tausenderpunkte)
function U.money(n, symbol)
    n = U.round(n or 0)
    local neg = n < 0
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    if out:sub(1, 1) == '.' then out = out:sub(2) end
    return (neg and '-' or '') .. (symbol or '$') .. out
end

-- ---------------------------------------------------------------------------
-- Namensregeln. Die Normalisierung muss exakt zu normName() in web/js/util.js passen,
-- weil die Oberfläche denselben Namen anzeigt, den der Server prüft (tests/test_util.lua vergleicht beides).
-- ---------------------------------------------------------------------------
local LOWER_MAP = {
    ['\xC3\x84'] = '\xC3\xA4', ['\xC3\x96'] = '\xC3\xB6', ['\xC3\x9C'] = '\xC3\xBC',
    ['\xC3\x89'] = '\xC3\xA9', ['\xC3\x88'] = '\xC3\xA8', ['\xC3\x81'] = '\xC3\xA1',
    ['\xC3\x80'] = '\xC3\xA0', ['\xC3\x93'] = '\xC3\xB3', ['\xC3\x91'] = '\xC3\xB1', ['\xC3\x87'] = '\xC3\xA7',
}
local UMLAUT = {
    ['\xC3\xA4'] = 'ae', ['\xC3\xB6'] = 'oe', ['\xC3\xBC'] = 'ue', ['\xC3\x9F'] = 'ss',
    ['\xC3\xA9'] = 'e', ['\xC3\xA8'] = 'e', ['\xC3\xA1'] = 'a', ['\xC3\xA0'] = 'a',
    ['\xC3\xB3'] = 'o', ['\xC3\xB1'] = 'n', ['\xC3\xA7'] = 'c',
}
local LEET = { ['0'] = 'o', ['1'] = 'i', ['3'] = 'e', ['4'] = 'a', ['5'] = 's', ['7'] = 't', ['@'] = 'a', ['$'] = 's' }
local SUFFIXES = { 'gmbh', 'gbr', 'ug', 'ag', 'ohg', 'kg', 'eg', 'stiftung', 'ev', 'e.v', 'e v', 'e. v' }

local function lowerUtf8(s)
    s = s:lower()
    for up, lo in pairs(LOWER_MAP) do s = s:gsub(up, lo) end
    return s
end

local function stripSuffix(s)
    local t = s
    if t:sub(-1) == '.' then t = t:sub(1, -2) end
    for _, suf in ipairs(SUFFIXES) do
        local n = #suf
        if #t >= n and t:sub(-n) == suf then
            local before = t:sub(-n - 1, -n - 1)
            if #t == n or not before:match('[%w_]') then
                return U.trim(t:sub(1, #t - n))
            end
        end
    end
    return s
end

function U.normName(name)
    local s = U.trim(lowerUtf8(U.trim(name)))
    s = stripSuffix(s)
    for k, v in pairs(UMLAUT) do s = s:gsub(k, v) end
    s = s:gsub('[013457@$]', LEET)
    s = s:gsub('[^a-z]', '')
    return s
end

function U.levenshtein(a, b)
    if a == b then return 0 end
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = { [0] = i }
        local ca = a:sub(i, i)
        for j = 1, lb do
            local cost = (ca == b:sub(j, j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[lb]
end

-- Hängt den Rechtsformzusatz an, falls er noch fehlt.
function U.withSuffix(name, suffix)
    name = U.trim(name)
    if suffix == nil or suffix == '' then return name end
    if name:lower():sub(-#suffix) == suffix:lower() then return name end
    return name .. ' ' .. suffix
end

-- Zeichen, die ein Name enthalten darf: Buchstaben (auch Umlaute), Ziffern, Leerzeichen und & ' . -
function U.nameCharsOk(name)
    local rest = name:gsub('[%w ]', '')
    rest = rest:gsub("[&'%.%-]", '')
    -- übrig bleiben nur Bytes von UTF-8-Zeichen: erlaubt sind genau Ä Ö Ü ä ö ü ß
    rest = rest:gsub('\xC3[\x84\x96\x9C\xA4\xB6\xBC\x9F]', '')
    return rest == ''
end

-- Kürzt auf höchstens max Bytes, ohne ein UTF-8-Zeichen zu zerschneiden (ein halber Umlaut würde die Datenbank und die Oberfläche stören)
function U.ucut(s, max)
    s = tostring(s == nil and '' or s)
    if #s <= max then return s end
    s = s:sub(1, max)
    for _ = 1, 3 do
        if utf8.len(s) then break end
        s = s:sub(1, -2)
    end
    return s
end

-- Länge in Zeichen (nicht Bytes) für UTF-8
function U.ulen(s)
    local n = 0
    for _ in tostring(s):gmatch('[^\x80-\xBF]') do n = n + 1 end
    return n
end

-- Anzeigetext für einen Standort (identisch zu IC.siteLabel in der Oberfläche)
function U.siteLabel(p)
    if not p then return '–' end
    if p.mode == 'mobil' then return 'Ohne festen Standort' end
    return (p.label and p.label ~= '') and p.label or '–'
end

-- Beginn des Tages (Serverzeit) für einen Zeitstempel in Millisekunden
function U.startOfDay(ts)
    local d = os.date('*t', ts // 1000)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d) * 1000
end

function U.fdt(ts)
    return os.date('%d.%m.%Y · %H:%M', ts // 1000)
end

function U.ftime(ts)
    return os.date('%H:%M', ts // 1000)
end
