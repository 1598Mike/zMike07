--[[
    ic_behoerden · Register
    Eintragungen (Unternehmen und Organisationen), Gewerbeschein, Statuswechsel, Auflösung.
]]

IC = IC or {}
local R, U, S = IC.rules, IC.util, IC.store
local G = {}
IC.register = G

local LEADER = { inhaber = true, geschaeftsfuehrer = true, vorsitz = true }
function G.isLeader(role) return LEADER[role] == true end

function G.leaderOf(e, charId)
    for _, m in ipairs(e.members or {}) do
        if m.charId == charId and LEADER[m.role] then return true end
    end
    return false
end

-- Einträge, bei denen der Charakter Inhaber, Geschäftsführer oder Vorsitz ist
function G.ownedBy(charId, includeGone)
    return U.sortBy(S.list('entities', function(e)
        return G.leaderOf(e, charId) and (includeGone or e.status ~= 'aufgeloest')
    end), function(e) return e.founded end)
end

function G.counts(charId)
    local companies, orgs = 0, 0
    for _, e in ipairs(G.ownedBy(charId, false)) do
        if e.kind == 'fraktion' then orgs = orgs + 1 else companies = companies + 1 end
    end
    return companies, orgs
end

function G.publicView(e)
    return { id = e.id, regNo = e.regNo, name = e.name, kind = e.kind, legalForm = e.legalForm, branch = e.branch, status = e.status, hq = e.hq, owner = e.owner, founded = e.founded, memberCount = e.memberCount }
end

-- Für Beamte und Bürger: alles außer den OOC-Angaben
function G.stripOoc(e)
    local c = U.deepcopy(e)
    c.ooc = nil
    return c
end

-- Wie viele aktive Einträge es in einer Branche gibt (zählt auch Anträge, die auf die Schlussprüfung warten)
function G.branchUsed(key)
    local n = S.count('entities', function(e) return e.branch == key and e.status ~= 'aufgeloest' end)
    n = n + S.count('applications', function(a) return a.branch == key and a.status == 'staff_pruefung' end)
    return n
end

function G.setStatus(e, status, actor, reason)
    local old = e.status
    if old == status then return end
    e.status = status
    e.history = e.history or {}
    e.history[#e.history + 1] = { ts = IC.now(), level = 'status', reason = (reason or '') .. ' (' .. old .. ' → ' .. status .. ')', by = actor or 'System' }
    S.put('entities', e)
    IC.audit(actor or 'System', 'system', 'Status', e.regNo, old .. ' → ' .. status)
    IC.hook('onStatusChanged', e, old, status)
    IC.emit('ic_behoerden:entityStatusChanged', e, old, status)
end

function G.dissolve(e, actor)
    e.dissolvedAt = IC.now()
    G.setStatus(e, 'aufgeloest', actor, 'Auflösung')
end

-- Nächste freie Registernummer der Rechtsform, zum Beispiel "HRB 0301"
function G.nextRegNo(f)
    local start = (Config.RegisterStart and Config.RegisterStart[f.register]) or 0
    return f.register .. ' ' .. U.pad4(IC.nextSeq('reg.' .. f.register, start))
end

-- Gewerbeschein an einen Charakter aushändigen. Ist er offline oder klappt es nicht (Inventar voll), wird es beim nächsten Login nachgeholt.
function G.handOverCertificate(charId, e)
    local src = IC.bridge.srcOfChar(charId)
    if src and IC.bridge.giveCertificate(src, e) then return true end
    local row = S.get('chars', charId) or { id = charId, notifyOnDuty = false, lastNotified = 0 }
    row.pendingCerts = row.pendingCerts or {}
    if not U.contains(row.pendingCerts, e.id) then row.pendingCerts[#row.pendingCerts + 1] = e.id end
    S.put('chars', row)
    return false
end

-- Wird beim Login aufgerufen: liefert Gewerbescheine nach, die vorher nicht ausgehändigt werden konnten.
function G.deliverPending(charId, src)
    local row = S.get('chars', charId)
    if not row or not row.pendingCerts or #row.pendingCerts == 0 then return end
    local rest = {}
    for _, id in ipairs(row.pendingCerts) do
        local e = S.get('entities', id)
        if e and e.status ~= 'aufgeloest' and not IC.bridge.giveCertificate(src, e) then rest[#rest + 1] = id end
    end
    row.pendingCerts = rest
    S.put('chars', row)
end

--[[
    Trägt einen genehmigten Antrag ein. via ist der Name der entscheidenden Stelle, falls nicht die Beamten
    (zum Beispiel "Registerführung" nach der Schlussprüfung).
]]
function G.create(app, via)
    local f = R.form(app.legalForm)
    local regNo = G.nextRegNo(f)

    local conds = {}
    for _, text in ipairs(app.decision and app.decision.conditions or {}) do
        conds[#conds + 1] = { id = 'C-' .. IC.nextSeq('cond', 0), text = text, due = IC.now() + 14 * R.DAY, done = false }
    end

    local leader = U.find(app.founders, function(x) return LEADER[x.role] end) or app.founders[1]
    local members = U.map(app.founders, function(x) return { charId = x.charId, name = x.name, role = x.role, share = x.share } end)
    local e = {
        id = 'E-' .. IC.nextSeq('entity', 0), kind = app.kind, regNo = regNo, name = app.name, legalForm = app.legalForm, branch = app.branch,
        status = #conds > 0 and 'probezeit' or 'aktiv', hq = U.siteLabel(app.property), propertyId = app.property and app.property.id or nil,
        owner = leader.name, signedBy = via or (app.decision and app.decision.by) or 'Registerführung', founded = IC.now(),
        validUntil = IC.now() + Config.Rules.certDays * R.DAY, memberCount = #app.founders, members = members, conditions = conds, history = {}, legacy = false, applicationId = app.id,
        ooc = app.ooc and U.deepcopy(app.ooc) or nil,
    }
    S.put('entities', e)

    local held = (app.fees.register or 0) + (app.fees.capital or 0)
    IC.pay.escrowOut(held)
    IC.pay.toTreasury(app.fees.register or 0, 'Eintragungsgebühr ' .. regNo)

    app.entityId = e.id
    IC.apps.setStatus(app, 'genehmigt', via or 'System', via and 'staff' or 'system', 'Eintragung vollzogen',
        'Registernummer ' .. regNo .. '. Der Gewerbeschein wurde ausgestellt.')
    IC.audit(via or 'System', via and 'staff' or 'system', 'Eintragung', regNo, e.name .. ' eingetragen')

    for _, m in ipairs(members) do
        if LEADER[m.role] then G.handOverCertificate(m.charId, e) end
        IC.notify(m.charId, '„' .. e.name .. '“ ist eingetragen. Registernummer ' .. regNo .. '.', 'ok')
    end

    IC.hook('onApproved', e, app)
    IC.emit('ic_behoerden:entityCreated', e)
    IC.webhook('public', 'Neueintragung im Handelsregister', e.name .. ' · ' .. regNo .. ' · ' .. f.label)
    return e
end

-- Auflagen eines Eintrags, die noch offen sind
function G.openConditions(e)
    return U.filter(e.conditions or {}, function(c) return not c.done end)
end

-- ---------------------------------------------------------------------------
-- Bestandsschutz: Übernahme aus dem alten System
-- ---------------------------------------------------------------------------
local function importMembers(it, kind)
    local roles = kind == 'fraktion' and Config.OrgRoles or Config.CompanyRoles
    local fallback = kind == 'fraktion' and 'mitglied' or 'gesellschafter'
    local members, seen = {}, {}
    for _, m in ipairs(type(it.members) == 'table' and it.members or {}) do
        if type(m) == 'table' and m.charId ~= nil and tostring(m.charId) ~= '' and not seen[tostring(m.charId)] then
            local charId = tostring(m.charId)
            seen[charId] = true
            members[#members + 1] = {
                charId = charId, name = U.trim(tostring(m.name or charId)):sub(1, 80),
                role = U.contains(roles, m.role) and m.role or fallback, share = tonumber(m.share),
            }
        end
    end
    if #members == 0 then return nil end
    if not U.find(members, function(m) return LEADER[m.role] end) then
        members[1].role = kind == 'fraktion' and 'vorsitz' or (#members == 1 and 'inhaber' or 'geschaeftsfuehrer')
    end
    if kind == 'unternehmen' then
        -- Anteile müssen 100 ergeben. Fehlen sie oder stimmen sie nicht, wird gleichmäßig verteilt (der Rest geht an den ersten).
        local sum, valid = 0, true
        for _, m in ipairs(members) do
            if not m.share or m.share < 1 or m.share ~= math.floor(m.share) then valid = false end
            sum = sum + (m.share or 0)
        end
        if not valid or sum ~= 100 then
            local each = math.floor(100 / #members)
            for i, m in ipairs(members) do m.share = each end
            members[1].share = members[1].share + (100 - each * #members)
        end
    else
        for _, m in ipairs(members) do m.share = nil end
    end
    return members
end

-- it: { ref, name, kind, legalForm, branch, hq, founded (ms), ooc ('untergrund' | 'legal'), members = { { charId, name, role, share } } }
-- Liefert den Eintrag oder nil, Grund, übersprungen (true, wenn es den Eintrag schon gibt).
function G.importOne(it, actor)
    if type(it) ~= 'table' then return nil, 'kein Eintrag' end
    local kind = it.kind == 'fraktion' and 'fraktion' or 'unternehmen'
    local f = R.form(it.legalForm or (kind == 'fraktion' and 'ig' or 'einzel'))
    if not f then return nil, 'unbekannte Rechtsform ' .. tostring(it.legalForm) end
    if f.kind ~= kind then return nil, 'Rechtsform ' .. f.key .. ' passt nicht zur Art ' .. kind end
    local name = U.withSuffix(U.trim(tostring(it.name or '')), f.suffix)
    if U.ulen(name) < 2 or U.ulen(name) > 100 then return nil, 'Name fehlt oder ist zu lang' end
    local branch
    if kind == 'unternehmen' then
        branch = it.branch or 'sonstige'
        if not R.branch(branch) then return nil, 'unbekannte Branche ' .. tostring(branch) end
    end
    local ref = it.ref ~= nil and tostring(it.ref) or nil
    local norm = U.normName(name)
    for _, e in ipairs(S.list('entities')) do
        if (ref and e.importRef == ref) or (e.status ~= 'aufgeloest' and U.normName(e.name) == norm) then return nil, 'ist schon eingetragen', true end
    end
    local members = importMembers(it, kind)
    if not members then return nil, 'keine Mitglieder mit charId' end
    local leader = U.find(members, function(m) return LEADER[m.role] end)
    local now = IC.now()
    local ooc
    local oocIn = type(it.ooc) == 'table' and it.ooc.category or it.ooc
    if kind == 'fraktion' and oocIn == 'untergrund' then ooc = { category = 'untergrund', note = '' } end
    local e = {
        id = 'E-' .. IC.nextSeq('entity', 0), kind = kind, regNo = G.nextRegNo(f), name = name, legalForm = f.key, branch = branch,
        status = 'aktiv', hq = it.hq and U.trim(tostring(it.hq)):sub(1, 80) or 'Ohne festen Standort', owner = leader.name, signedBy = 'Registerführung',
        founded = tonumber(it.founded) or now, validUntil = now + Config.Rules.certDays * R.DAY, memberCount = #members,
        members = members, conditions = {}, history = {}, legacy = true, legacyConfirmed = false,
        legacyDue = now + (Config.Legacy and Config.Legacy.confirmDays or 28) * R.DAY, importRef = ref, ooc = ooc,
    }
    S.put('entities', e)
    IC.audit(actor or 'Import', 'staff', 'Bestandsimport', e.regNo, e.name)
    for _, m in ipairs(members) do
        if LEADER[m.role] then
            IC.notify(m.charId, '„' .. e.name .. '“ wurde in das neue Register übernommen. Bitte bestätigen Sie Ihre Daten im Gewerbeamt (kostenlos).', 'info')
            G.handOverCertificate(m.charId, e)
        end
    end
    IC.emit('ic_behoerden:entityImported', e)
    return e
end

-- Übernimmt eine Liste. Der Import lässt sich wiederholen: vorhandene Einträge werden übersprungen.
function G.importLegacy(items, actor)
    local res = { created = 0, skipped = 0, errors = {} }
    if type(items) ~= 'table' then res.errors[1] = 'Die Datei enthält keine Liste.' return res end
    for i, it in ipairs(items) do
        local e, why, skipped = G.importOne(it, actor)
        if e then res.created = res.created + 1
        elseif skipped then res.skipped = res.skipped + 1
        else res.errors[#res.errors + 1] = ('Nr. %d (%s): %s'):format(i, type(it) == 'table' and tostring(it.name) or '?', why) end
    end
    return res
end
