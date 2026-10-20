local T, H = ...
local S = IC.store

-- Fremdkörper, die FiveM sonst stellt
json = dofile('tests/json.lua')
local captured = {}
MySQL = { query = { await = function(sql, params) captured[#captured + 1] = { sql = sql, params = params } end } }
function CreateThread() end
function Wait() end
dofile('server/persist.lua')
local P = IC.persist

local function deepEq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

T.test('JSON-Modul: Rundlauf mit Umlauten, Sonderzeichen, Zahlen und leeren Tabellen', function()
    local v = { text = 'Müller & Söhne "Bar"\nZeile 2\t\\', n = 1760000000000, f = 0.5, ok = true, list = { 1, 2, { a = 'ß' } }, empty = {}, nested = { x = { y = { z = 'tief' } } } }
    local back = json.decode(json.encode(v))
    T.ok(deepEq(v, back), 'Rundlauf: ' .. json.encode(back))
    T.eq(json.decode('"\\u00e4\\u00f6"'), 'äö')
end)

T.test('Persistenz: Einfügen mit Platzhaltern, Nutzereingaben stehen nie im SQL-Text', function()
    local evil = "x'); DROP TABLE ic_entities; --"
    local sql, params = P.buildUpsert('applications', { id = 'A-1', caseNo = 'GA-2026-0001', kind = 'unternehmen', status = 'eingereicht', applicant = { charId = 'c-1' }, name = evil })
    T.ok(sql:find('INSERT INTO `ic_applications`', 1, true))
    T.ok(sql:find('ON DUPLICATE KEY UPDATE', 1, true))
    T.notok(sql:find('DROP', 1, true), 'der Name steht nur in den Parametern')
    local marks = select(2, sql:gsub('%?', ''))
    T.eq(marks, #params, 'so viele Platzhalter wie Parameter')
    T.eq(params[1], 'A-1')
    local found = false
    for _, p in ipairs(params) do if p == evil then found = true end end
    T.ok(found)
end)

T.test('Persistenz: fehlende Werte werden NULL, Wahrheitswerte 0 oder 1, jede Tabelle hat eine Definition', function()
    local sql = P.buildUpsert('applications', { id = 'A-2', kind = 'fraktion', status = 'entwurf', applicant = { charId = 'c-1' }, name = 'x' })
    T.ok(sql:find('NULL', 1, true), 'Aktenzeichen fehlt noch: NULL')
    local _, params = P.buildUpsert('chars', { id = 'c-1', notifyOnDuty = true })
    T.eq(params[2], 1)
    for _, name in ipairs(S.names) do T.ok(P.DEFS[name], 'Definition für ' .. name) end
end)

T.test('Persistenz: jede Änderung im Speicher landet in der Warteschlange, Löschen ebenso', function()
    H.reset()
    P.queue = {}
    S.persist = P.persist
    S.put('blacklist', { id = 'B-9', term = 'test', reason = 'x' })
    S.put('blacklist', { id = 'B-9', term = 'test2', reason = 'x' })
    S.del('blacklist', 'B-9')
    T.eq(#P.queue, 3)
    T.ok(P.queue[1].sql:find('INSERT', 1, true)); T.ok(P.queue[3].sql:find('DELETE', 1, true))
    P.flush()
    T.eq(#captured, 3, 'die Warteschlange wird der Reihe nach abgearbeitet'); T.eq(#P.queue, 0)
    T.ok(captured[2].params[#captured[2].params]:find('test2', 1, true), 'Reihenfolge bleibt erhalten')
    S.persist = nil
end)

T.test('Persistenz: beim Stoppen geht alles Offene in einer Transaktion hinaus, bereits Gesendetes nicht doppelt', function()
    H.reset()
    P.queue = {}
    S.persist = P.persist
    local transactions = {}
    MySQL.transaction = function(list) transactions[#transactions + 1] = list end
    S.put('blacklist', { id = 'B-20', term = 'a', reason = 'x' })
    S.put('blacklist', { id = 'B-21', term = 'b', reason = 'x' })
    P.queue[1].sent = true -- der erste Schreibvorgang ist schon bei der Datenbank
    T.eq(P.flushOnStop(), 1)
    T.eq(#transactions, 1); T.eq(#transactions[1], 1)
    T.ok(transactions[1][1].query:find('INSERT', 1, true)); T.ok(transactions[1][1].values[#transactions[1][1].values]:find('"b"', 1, true) or transactions[1][1].values[2] == 'b')
    T.eq(#P.queue, 0)
    T.eq(P.flushOnStop(), 0); T.eq(#transactions, 1, 'keine leere Transaktion')
    S.persist = nil
end)
