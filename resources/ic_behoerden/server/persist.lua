--[[
    ic_behoerden · Persistenz (oxmysql)
    Jede Zeile des Speichers landet als JSON in der Spalte "data". Dazu gibt es wenige Index-Spalten für Abfragen im SQL-Client.
    Neue Felder brauchen deshalb keine Migration. Das vollständige Schema steht in sql/install.sql.

    Schreibzugriffe laufen über eine Warteschlange, die der Reihe nach abgearbeitet wird. So kann eine ältere Änderung
    eine neuere nie überschreiben, auch wenn der Datenbankserver Anfragen parallel bearbeitet.
]]

IC = IC or {}
local P = {}
IC.persist = P

local function b(v) if v == true then return 1 elseif v == false then return 0 end return v end

-- Tabelle des Speichers -> SQL-Tabelle, feste Liste der Index-Spalten (cols) und deren Werte (index).
-- Die Liste ist fest, damit ein Wert, der nil wird, in der Datenbank auch wirklich NULL wird.
P.DEFS = {
    applications = { table = 'ic_applications', cols = { 'applicant_char', 'case_no', 'kind', 'name', 'status' },
        index = function(r) return { case_no = r.caseNo, kind = r.kind, status = r.status, applicant_char = r.applicant and r.applicant.charId, name = r.name } end },
    entities     = { table = 'ic_entities', cols = { 'kind', 'name', 'reg_no', 'status' },
        index = function(r) return { reg_no = r.regNo, kind = r.kind, status = r.status, name = r.name } end },
    appointments = { table = 'ic_appointments', cols = { 'booker_char', 'starts_at', 'status' },
        index = function(r) return { status = r.status, booker_char = r.booker, starts_at = r.start } end },
    officeHours  = { table = 'ic_office_hours', cols = { 'ends_at', 'official_char', 'starts_at' },
        index = function(r) return { official_char = r.officialId, starts_at = r.start, ends_at = r.finish } end },
    blacklist    = { table = 'ic_blacklist', cols = { 'reason', 'term' },
        index = function(r) return { term = r.term, reason = r.reason } end },
    settings     = { table = 'ic_settings', cols = {}, index = function() return {} end },
    strikes      = { table = 'ic_strikes', cols = { 'char_id', 'ts' },
        index = function(r) return { char_id = r.charId, ts = r.ts } end },
    chars        = { table = 'ic_chars', cols = { 'notify_on_duty' },
        index = function(r) return { notify_on_duty = b(r.notifyOnDuty) } end },
    notices      = { table = 'ic_notices', cols = { 'char_id', 'ts' },
        index = function(r) return { char_id = r.charId, ts = r.ts } end },
    refunds      = { table = 'ic_refunds', cols = { 'char_id', 'ts' },
        index = function(r) return { char_id = r.charId, ts = r.ts } end },
}

-- Baut die SQL-Anweisung für Einfügen oder Aktualisieren. Spaltennamen kommen nur aus dem Code, alle Werte laufen über Platzhalter.
function P.buildUpsert(name, row)
    local def = P.DEFS[name]
    local idx = def.index(row)
    local cols, marks, params, updates = { '`id`' }, { '?' }, { tostring(row.id) }, {}
    for _, k in ipairs(def.cols) do
        local v = idx[k]
        cols[#cols + 1] = '`' .. k .. '`'
        if v == nil then
            marks[#marks + 1] = 'NULL'
        else
            marks[#marks + 1] = '?'
            params[#params + 1] = v
        end
        updates[#updates + 1] = '`' .. k .. '` = VALUES(`' .. k .. '`)'
    end
    cols[#cols + 1] = '`data`'
    marks[#marks + 1] = '?'
    params[#params + 1] = json.encode(row)
    updates[#updates + 1] = '`data` = VALUES(`data`)'
    local sql = ('INSERT INTO `%s` (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s'):format(def.table, table.concat(cols, ', '), table.concat(marks, ', '), table.concat(updates, ', '))
    return sql, params
end

function P.buildDelete(name, row)
    return ('DELETE FROM `%s` WHERE `id` = ?'):format(P.DEFS[name].table), { tostring(row.id) }
end

-- ---------------------------------------------------------------------------
-- Warteschlange
-- ---------------------------------------------------------------------------
P.queue = {}

local function push(sql, params) P.queue[#P.queue + 1] = { sql = sql, params = params } end

function P.persist(name, row, deleted)
    if deleted then push(P.buildDelete(name, row)) else push(P.buildUpsert(name, row)) end
end

function IC.persistAudit(row)
    push('INSERT INTO `ic_audit` (`ts`, `actor`, `kind`, `action`, `target`, `detail`) VALUES (?, ?, ?, ?, ?, ?)',
        { row.ts, row.actor, row.kind, row.action, row.target, row.detail })
end

-- Arbeitet den ersten Eintrag ab. Er bleibt bis zum Ende in der Warteschlange (sent = an die Datenbank übergeben),
-- damit P.flushOnStop ihn beim Stoppen nicht doppelt schreibt und kein späterer Eintrag vorbeiziehen kann.
function P.flushOne()
    local q = P.queue[1]
    if not q then return false end
    q.sent = true
    local ok, err = pcall(MySQL.query.await, q.sql, q.params)
    if not ok then print('[ic_behoerden] Datenbankfehler: ' .. tostring(err)) end
    table.remove(P.queue, 1)
    return true
end

-- Beim Stoppen der Ressource: alles Offene in einer Transaktion abschicken, ohne auf die Antwort zu warten.
function P.flushOnStop()
    local list = {}
    for _, q in ipairs(P.queue) do
        if not q.sent then list[#list + 1] = { query = q.sql, values = q.params } end
    end
    P.queue = {}
    if #list > 0 then MySQL.transaction(list) end
    return #list
end

function P.flush()
    while P.flushOne() do end
end

function P.startWorker()
    CreateThread(function()
        while true do
            if not P.flushOne() then Wait(100) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Installation und Laden
-- ---------------------------------------------------------------------------
function P.install()
    local sql = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
    if not sql then print('[ic_behoerden] sql/install.sql nicht gefunden') return end
    sql = sql:gsub('%-%-[^\n]*', '')
    for stmt in sql:gmatch('[^;]+') do
        stmt = stmt:gsub('^%s+', ''):gsub('%s+$', '')
        if stmt ~= '' then MySQL.query.await(stmt) end
    end
end

function P.load()
    local S = IC.store
    S.reset()
    for name, def in pairs(P.DEFS) do
        local rows = MySQL.query.await(('SELECT `data` FROM `%s`'):format(def.table)) or {}
        for _, r in ipairs(rows) do
            local ok, row = pcall(json.decode, r.data)
            if ok and type(row) == 'table' and row.id ~= nil then S.t[name][row.id] = row end
        end
    end
    local audit = MySQL.query.await('SELECT `ts`, `actor`, `kind`, `action`, `target`, `detail` FROM `ic_audit` ORDER BY `id` DESC LIMIT 500') or {}
    IC.auditLog = {}
    for _, a in ipairs(audit) do IC.auditLog[#IC.auditLog + 1] = a end
end

function P.init()
    if Config.AutoInstallSql ~= false then P.install() end
    P.load()
    IC.store.persist = P.persist
    P.startWorker()
end
