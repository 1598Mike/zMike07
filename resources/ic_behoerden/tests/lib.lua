-- Minimales Test-Framework ohne Abhängigkeiten. Aufruf: lua tests/run.lua (aus dem Ressourcen-Ordner)
local T = { tests = {}, failed = 0, passed = 0, current = nil }

function T.test(name, fn)
    T.tests[#T.tests + 1] = { name = name, fn = fn }
end

local function fmt(v)
    if type(v) == 'table' then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. '=' .. fmt(x) end
        table.sort(parts)
        return '{' .. table.concat(parts, ', ') .. '}'
    end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'Werte sind verschieden') .. '\n    erwartet: ' .. fmt(expected) .. '\n    erhalten: ' .. fmt(actual), 2)
    end
end

function T.ok(cond, msg)
    if not cond then error(msg or 'Bedingung ist nicht erfüllt', 2) end
end

function T.notok(cond, msg)
    if cond then error(msg or 'Bedingung ist unerwartet erfüllt', 2) end
end

-- Prüft, ob eine Antwort { ok = false } mit einem Text ist, der das Muster enthält.
function T.fails(res, pattern, msg)
    if res == nil or res.ok ~= false then error((msg or 'Es wurde ein Fehler erwartet') .. ', erhalten: ' .. fmt(res), 2) end
    if pattern and not tostring(res.error or ''):find(pattern, 1, true) then
        error((msg or 'Fehlertext passt nicht') .. '\n    erwartet (enthält): ' .. pattern .. '\n    erhalten: ' .. tostring(res.error), 2)
    end
end

function T.succeeds(res, msg)
    if res == nil or res.ok ~= true then error((msg or 'Es wurde Erfolg erwartet') .. ', erhalten: ' .. fmt(res), 2) end
    return res
end

-- Führt fn aus und fängt ab, was dabei per print ausgegeben wird (auch wenn fn einen Fehler wirft, wird print zurückgesetzt).
-- Liefert die ausgegebenen Zeilen, danach die Rückgabewerte von fn.
function T.capture(fn, ...)
    local lines, realPrint = {}, print
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, ' ')
    end
    local res = table.pack(pcall(fn, ...))
    print = realPrint
    if not res[1] then error(res[2], 0) end
    return lines, table.unpack(res, 2, res.n)
end

function T.run()
    for _, t in ipairs(T.tests) do
        local ok, err = xpcall(t.fn, function(e) return e end)
        if ok then
            T.passed = T.passed + 1
            print('  ok    ' .. t.name)
        else
            T.failed = T.failed + 1
            print('  FEHLER ' .. t.name .. '\n    ' .. tostring(err))
        end
    end
    print(string.format('\n%d bestanden, %d fehlgeschlagen', T.passed, T.failed))
    return T.failed == 0
end

return T
