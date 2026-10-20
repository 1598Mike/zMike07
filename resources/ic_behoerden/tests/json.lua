-- Kleines JSON-Modul nur für die Tests (FiveM stellt json.encode und json.decode selbst bereit).
local J = {}

local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function str(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format('\\u%04x', c:byte()) end) .. '"'
end

function J.encode(v)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' then return tostring(v) end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
        return string.format('%.14g', v)
    end
    if t == 'string' then return str(v) end
    if t == 'table' then
        local n, count = #v, 0
        for _ in pairs(v) do count = count + 1 end
        local out = {}
        if count == n then
            for i = 1, n do out[i] = J.encode(v[i]) end
            return '[' .. table.concat(out, ',') .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            out[#out + 1] = str(k) .. ':' .. J.encode(val)
        end
        return '{' .. table.concat(out, ',') .. '}'
    end
    error('nicht kodierbar: ' .. t)
end

local function utf8char(cp) return utf8.char(cp) end

function J.decode(s)
    local pos = 1
    local function ws() pos = s:find('[^ \t\r\n]', pos) or #s + 1 end
    local value
    local function string_()
        local out, i = {}, pos + 1
        while true do
            local c = s:sub(i, i)
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == '\\' then
                local n = s:sub(i + 1, i + 1)
                local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                if n == 'u' then
                    local cp = tonumber(s:sub(i + 2, i + 5), 16)
                    i = i + 6
                    if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == '\\u' then
                        local lo = tonumber(s:sub(i + 2, i + 5), 16)
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        i = i + 6
                    end
                    out[#out + 1] = utf8char(cp)
                else
                    out[#out + 1] = map[n]
                    i = i + 2
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == '{' then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == '}' then pos = pos + 1; return t end
            while true do
                ws(); local k = string_(); ws()
                pos = pos + 1 -- ':'
                t[k] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == '}' then return t end
            end
        elseif c == '[' then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == ']' then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == ']' then return t end
            end
        elseif c == '"' then return string_()
        elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
        else
            local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
            pos = pos + #num
            return tonumber(num)
        end
    end
    return value()
end

return J
