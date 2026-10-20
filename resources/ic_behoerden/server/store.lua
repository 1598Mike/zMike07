--[[
    ic_behoerden · Speicher
    Alle Daten liegen im Arbeitsspeicher und werden bei jeder Änderung in die Datenbank geschrieben (server/persist.lua).
    Das hält die Logik einfach: Zugriffe sind synchron, und weil Lua pro Ressource nur einen Faden nutzt, kann es keine
    Wettlaufsituationen zwischen zwei Buchungen geben. Beim Start lädt persist.lua alles aus der Datenbank.
    In den Tests ist persist nil, dann bleibt alles im Speicher.
]]

IC = IC or {}
local S = { t = {}, persist = nil }
IC.store = S

-- Tabellen (Schlüssel = Zeilen-ID). Die Spaltenzuordnung zur Datenbank steht in persist.lua.
S.names = { 'applications', 'entities', 'appointments', 'officeHours', 'blacklist', 'settings', 'strikes', 'chars', 'notices', 'refunds' }

function S.reset()
    for _, n in ipairs(S.names) do S.t[n] = {} end
end
S.reset()

function S.get(name, id)
    return S.t[name][id]
end

-- Fügt eine Zeile ein oder ersetzt sie. Wer eine Zeile verändert hat, ruft put/save danach erneut auf.
function S.put(name, row)
    assert(S.t[name], 'unbekannte Tabelle ' .. tostring(name))
    assert(row.id ~= nil, 'row.id fehlt in ' .. name)
    S.t[name][row.id] = row
    if S.persist then S.persist(name, row, false) end
    return row
end
S.save = S.put

function S.del(name, id)
    local row = S.t[name][id]
    S.t[name][id] = nil
    if S.persist and row then S.persist(name, row, true) end
end

-- Liefert eine Liste (ungeordnet) der Zeilen, für die pred wahr ist. Wer Reihenfolge braucht, sortiert selbst.
function S.list(name, pred)
    local out = {}
    for _, row in pairs(S.t[name]) do
        if not pred or pred(row) then out[#out + 1] = row end
    end
    return out
end

function S.count(name, pred)
    local n = 0
    for _, row in pairs(S.t[name]) do
        if not pred or pred(row) then n = n + 1 end
    end
    return n
end
