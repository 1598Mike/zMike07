--[[
    ic_behoerden · Regeln
    Reine Funktionen ohne Datenbank und ohne FiveM. Sie bekommen alles, was sie wissen müssen, als Parameter
    und lassen sich deshalb vollständig testen (tests/test_rules.lua).
    Die Meldungen stehen hier, damit Server und Oberfläche denselben Wortlaut zeigen.
]]

IC = IC or {}
local R = {}
IC.rules = R
local U = IC.util

R.MIN, R.HOUR, R.DAY = 60000, 3600000, 86400000

R.OPEN_APP = {
    eingereicht = true, nachbesserung = true, vorpruefung_ok = true, termin_gebucht = true,
    termin_laeuft = true, staff_pruefung = true, einspruch = true,
}
R.OPEN_APPT = { gebucht = true, eingecheckt = true, aufgerufen = true, laeuft = true }

-- Erlaubte Statusübergänge eines Antrags (siehe docs/KONZEPT.md, Abschnitt 5).
R.TRANSITIONS = {
    entwurf        = { eingereicht = true, zurueckgezogen = true },
    eingereicht    = { vorpruefung_ok = true, nachbesserung = true, abgelehnt = true, zurueckgezogen = true },
    nachbesserung  = { eingereicht = true, abgelaufen = true, zurueckgezogen = true },
    vorpruefung_ok = { termin_gebucht = true, abgelaufen = true, genehmigt = true, staff_pruefung = true, abgelehnt = true, zurueckgezogen = true },
    termin_gebucht = { vorpruefung_ok = true, einspruch = true, termin_laeuft = true, zurueckgezogen = true },
    termin_laeuft  = { genehmigt = true, staff_pruefung = true, nachbesserung = true, abgelehnt = true, vorpruefung_ok = true, einspruch = true },
    staff_pruefung = { genehmigt = true, nachbesserung = true },
    abgelehnt      = { einspruch = true },
    einspruch      = { termin_gebucht = true, genehmigt = true, staff_pruefung = true, abgelehnt = true, zurueckgezogen = true },
}

function R.canTransition(from, to)
    local t = R.TRANSITIONS[from]
    return t ~= nil and t[to] == true
end

function R.isOpenApp(app) return R.OPEN_APP[app.status] == true end
function R.isOpenAppt(appt) return R.OPEN_APPT[appt.status] == true end

function R.rankLevel(rank) return Config.Ranks[rank] or -1 end
function R.rankAtLeast(rank, min) return R.rankLevel(rank) >= R.rankLevel(min) end

function R.form(key)
    for _, f in ipairs(Config.LegalForms) do if f.key == key then return f end end
end
function R.branch(key)
    for _, b in ipairs(Config.Branches) do if b.key == key then return b end end
end
function R.apptType(key)
    for _, t in ipairs(Config.AppointmentTypes) do if t.key == key then return t end end
end

-- ---------------------------------------------------------------------------
-- Gebühren
-- ---------------------------------------------------------------------------
function R.fees(formKey, branchKey)
    local f = R.form(formKey)
    if not f then return nil end
    local b = branchKey and R.branch(branchKey) or nil
    local k = b and b.factor or 1
    local apply, register = U.round(f.feeApply * k), U.round(f.feeRegister * k)
    return { apply = apply, register = register, capital = f.capital, payNow = apply + register + f.capital, refundable = register + f.capital }
end

function R.staffGateNeeded(app)
    local b = app.branch and R.branch(app.branch) or nil
    return (b ~= nil and b.staffGate == true) or (app.ooc ~= nil and app.ooc.category == 'untergrund')
end

-- ---------------------------------------------------------------------------
-- Namensprüfung. ctx: { blacklist = {{term, reason}}, entities = {{name, status, regNo}}, openApps = {{id, name, caseNo}}, ignoreAppId }
-- ---------------------------------------------------------------------------
function R.nameCheck(nameIn, formKey, ctx)
    ctx = ctx or {}
    local raw = U.trim(nameIn)
    local issues = {}
    local function err(code, text) issues[#issues + 1] = { level = 'error', code = code, text = text } end
    local function warn(code, text) issues[#issues + 1] = { level = 'warn', code = code, text = text } end

    local len = U.ulen(raw)
    if len < 3 then err('short', 'Der Name braucht mindestens 3 Zeichen.') end
    if len > 40 then err('long', 'Der Name darf höchstens 40 Zeichen lang sein.') end
    if raw ~= '' and not U.nameCharsOk(raw) then err('chars', "Erlaubt sind Buchstaben, Ziffern, Leerzeichen und die Zeichen & ' . -") end

    local n = U.normName(raw)
    if len >= 3 and #n < 3 then err('short', 'Der Name enthält zu wenige Buchstaben.') end

    if #n >= 3 then
        for _, b in ipairs(ctx.blacklist or {}) do
            local bn = U.normName(b.term)
            if bn ~= '' and n:find(bn, 1, true) then
                err('blacklist', 'Der Begriff „' .. b.term .. '“ ist gesperrt (' .. b.reason .. ').')
            end
        end
        for _, e in ipairs(ctx.entities or {}) do
            if e.status ~= 'aufgeloest' and (ctx.ignoreEntityId == nil or e.id ~= ctx.ignoreEntityId) then
                local en = U.normName(e.name)
                if en == n then
                    err('taken', 'Der Name ist bereits im Register eingetragen (' .. e.regNo .. ').')
                else
                    local d = U.levenshtein(n, en)
                    if d <= 1 then err('similar', 'Zu ähnlich zu „' .. e.name .. '“ (' .. e.regNo .. '). Verwechslungsgefahr.')
                    elseif d == 2 then warn('similar', 'Ähnlich zu „' .. e.name .. '“. Die Beamten prüfen die Verwechslungsgefahr.') end
                end
            end
        end
        for _, a in ipairs(ctx.openApps or {}) do
            if a.id ~= ctx.ignoreAppId then
                local an = U.normName(a.name)
                if an == n then err('reserved', 'Der Name ist für einen laufenden Antrag reserviert (' .. a.caseNo .. ').')
                elseif U.levenshtein(n, an) <= 1 then err('similar', 'Zu ähnlich zu einem laufenden Antrag („' .. a.name .. '“).') end
            end
        end
    end

    local ok = true
    for _, i in ipairs(issues) do if i.level == 'error' then ok = false end end
    local f = R.form(formKey)
    local display = raw ~= '' and U.withSuffix(raw, f and f.suffix or '') or ''
    return { ok = ok, normalized = n, display = display, issues = issues }
end

function R.firstError(issues)
    for _, i in ipairs(issues) do if i.level == 'error' then return i.text end end
end

-- ---------------------------------------------------------------------------
-- Voraussetzungen. p: { hasId, age, playHours }. ctx (nur für den Antragsteller): { isMe, openApps, companies, orgs, banUntil }
-- ---------------------------------------------------------------------------
function R.eligibility(p, kind, ctx)
    ctx = ctx or {}
    local c = Config.Rules
    local checks = {}
    local function add(key, ok, text) checks[#checks + 1] = { key = key, ok = ok and true or false, text = text } end
    add('id', p.hasId, 'Gültiger Personalausweis')
    add('age', (p.age or 0) >= c.minAge, 'Mindestalter ' .. c.minAge .. ' Jahre (IC)')
    add('play', (p.playHours or 0) >= c.minPlayHours, 'Mindestens ' .. c.minPlayHours .. ' Stunden Spielzeit mit diesem Charakter')
    if ctx.isMe then
        add('ban', not ctx.banUntil, ctx.banUntil and 'Terminsperre aktiv' or 'Keine Terminsperre')
        add('apps', (ctx.openApps or 0) < c.maxOpenApplications, 'Offene Anträge: ' .. (ctx.openApps or 0) .. ' von ' .. c.maxOpenApplications)
        if kind == 'fraktion' then
            add('orgs', (ctx.orgs or 0) < c.maxOrgs, 'Organisationen als Gründer: ' .. (ctx.orgs or 0) .. ' von ' .. c.maxOrgs)
        else
            add('companies', (ctx.companies or 0) < c.maxCompanies, 'Aktive Unternehmen als Inhaber: ' .. (ctx.companies or 0) .. ' von ' .. c.maxCompanies)
        end
    end
    local all = true
    for _, k in ipairs(checks) do if not k.ok then all = false end end
    return { ok = all, checks = checks }
end

-- ---------------------------------------------------------------------------
-- Termine
-- ---------------------------------------------------------------------------

-- Pflichtteilnehmer eines Vorstellungstermins (Charakter-IDs)
function R.mandatory(app)
    local out = {}
    for _, f in ipairs(app.founders or {}) do
        if f.role == 'geschaeftsfuehrer' or f.role == 'inhaber' or f.role == 'vorsitz' or (f.share or 0) >= 25 or app.kind == 'fraktion' then
            out[#out + 1] = f.charId
        end
    end
    return out
end

--[[
    Berechnet die buchbaren Slots eines Tages.
    type:       Terminart
    dayStart/dayEnd: Beginn und Ende des Tages in Millisekunden
    ctx: {
        now,
        liveOfficials = { { id, rank } },            -- Beamte, die jetzt im Dienst sind
        officeHours   = { { officialId, start, finish, types } },
        rankOf        = function(officialId) -> rank | nil,   -- Rang zum Zeitpunkt der Berechnung (nil: kein Beamter mehr)
        appointments  = { { id, start, minutes, status } },
        excludeId     = Termin-ID, die ignoriert wird (beim Verschieben)
    }
    Kernregel: Ohne Beamte im Dienst und ohne Sprechzeit gibt es keinen Slot.
    Die Kapazität eines Slots ist die Zahl der verschiedenen Beamten, die ihn bedienen können.
]]
function R.slots(type, dayStart, dayEnd, ctx)
    local rules = Config.Rules
    local mode = Config.Appointments.mode
    local t0 = ctx.now
    local step, len, lead = rules.slotStep * R.MIN, type.minutes * R.MIN, rules.leadMinutes * R.MIN
    local minLvl = R.rankLevel(type.minRank)
    local live = {}
    if mode ~= 'plan' then
        for _, o in ipairs(ctx.liveOfficials or {}) do
            if R.rankLevel(o.rank) >= minLvl then live[#live + 1] = o end
        end
    end
    local out = {}
    local st = dayStart
    while st < dayEnd do
        if st >= t0 + lead then
            local set, isLive = {}, false
            if st <= t0 + rules.liveHorizon * R.MIN then
                for _, o in ipairs(live) do set[o.id] = true; isLive = true end
            end
            if mode ~= 'live' then
                for _, h in ipairs(ctx.officeHours or {}) do
                    local rank = ctx.rankOf and ctx.rankOf(h.officialId) or nil
                    if rank and R.rankLevel(rank) >= minLvl and (not h.types or U.contains(h.types, type.key)) and h.start <= st and st + len <= h.finish then
                        set[h.officialId] = true
                    end
                end
            end
            local cap = 0
            for _ in pairs(set) do cap = cap + 1 end
            if cap > 0 then
                local booked = 0
                for _, ap in ipairs(ctx.appointments or {}) do
                    if R.OPEN_APPT[ap.status] and ap.id ~= ctx.excludeId and ap.start < st + len and ap.start + ap.minutes * R.MIN > st then
                        booked = booked + 1
                    end
                end
                out[#out + 1] = { start = st, ['end'] = st + len, cap = cap, booked = booked, free = math.max(0, cap - booked), source = isLive and 'live' or 'plan' }
            end
        end
        st = st + step
    end
    return out
end

-- Check-in-Fenster. Liefert { can, done, text }.
function R.checkinState(ap, charId, now)
    local r = Config.Rules
    local me
    for _, a in ipairs(ap.attendees or {}) do if a.charId == charId then me = a end end
    if not me then return { can = false, text = '' } end
    if me.checkedIn then return { can = false, done = true, text = 'Sie sind eingecheckt und warten im Wartebereich.' } end
    if ap.status ~= 'gebucht' and ap.status ~= 'eingecheckt' then return { can = false, text = '' } end
    if now < ap.start - r.checkinBefore * R.MIN then return { can = false, early = true, text = 'Einchecken ist ab ' .. r.checkinBefore .. ' Minuten vor Terminbeginn möglich.' } end
    if now > ap.start + r.checkinAfter * R.MIN then return { can = false, late = true, text = 'Das Check-in-Fenster ist geschlossen.' } end
    return { can = true, text = 'Check-in ist jetzt möglich.' }
end

-- Offene Pflichtpunkte der Checkliste. checked: { [key] = true }
function R.checklistMissing(typeKey, checked)
    local out = {}
    for _, i in ipairs(Config.Checklists[typeKey] or {}) do
        if not i.optional and not (checked and checked[i.key]) then out[#out + 1] = i end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Antrag: Bereinigung und Prüfung
-- ---------------------------------------------------------------------------
local LIMIT = { name = 40, short = 120, long = 2000, label = 160 }

-- Kürzt UTF-8-sicher (schneidet nie mitten in einem Umlaut). multiline erhält Zeilenumbrüche.
local function str(v, max, multiline)
    v = tostring(v == nil and '' or v)
    if multiline then
        v = v:gsub('\r', ''):gsub('[\0-\8\11-\31\127]', ' ')
    else
        v = v:gsub('[%c]', ' ')
    end
    v = U.trim(v)
    if #v > max then
        v = v:sub(1, max)
        while #v > 0 and not utf8.len(v) do v = v:sub(1, -2) end
    end
    return v
end

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- Macht aus dem, was der Client schickt, einen sauberen Entwurf: feste Typen, begrenzte Längen, nur bekannte Felder.
function R.sanitizeDraft(d)
    d = type(d) == 'table' and d or {}
    local out = {
        id = d.id ~= nil and str(d.id, 20) or nil,
        kind = d.kind == 'fraktion' and 'fraktion' or 'unternehmen',
        legalForm = str(d.legalForm, 20),
        branch = d.branch and str(d.branch, 20) or nil,
        name = str(d.name, 80),
        founders = {},
        property = { mode = nil, id = nil, label = '' },
        concept = {}, statute = {}, ooc = nil,
    }
    if out.branch == '' then out.branch = nil end
    for _, f in ipairs(type(d.founders) == 'table' and d.founders or {}) do
        out.founders[#out.founders + 1] = {
            charId = str(f.charId, 64), name = str(f.name, LIMIT.label), role = str(f.role, 20),
            share = f.share ~= nil and tonumber(f.share) or nil,
        }
    end
    local p = type(d.property) == 'table' and d.property or {}
    out.property.mode = (p.mode == 'immobilie' or p.mode == 'mobil') and p.mode or nil
    out.property.id = p.id and str(p.id, 20) or nil
    local c = type(d.concept) == 'table' and d.concept or {}
    out.concept = { idea = str(c.idea, LIMIT.long, true), audience = str(c.audience, LIMIT.short), offer = str(c.offer, LIMIT.short), staff = str(c.staff, LIMIT.short), hours = str(c.hours, LIMIT.short) }
    local s = type(d.statute) == 'table' and d.statute or {}
    out.statute = { purpose = str(s.purpose, LIMIT.long, true), goals = str(s.goals, LIMIT.long, true), admission = str(s.admission, LIMIT.short) }
    if type(d.ooc) == 'table' then
        out.ooc = { category = d.ooc.category == 'untergrund' and 'untergrund' or 'legal', note = str(d.ooc.note, LIMIT.long, true), members = str(d.ooc.members, 20) }
    end
    return out
end

--[[
    Prüft einen eingereichten Antrag. d ist bereinigt (sanitizeDraft), die Gründer sind bereits gegen die Einladungen geprüft.
    ctx: { elig, nameResult, branchUsed = fn(key), branchCap = fn(branch), propertyTaken = fn(id), prev = bisheriger Antrag | nil,
           resubmit, bank, undergroundAllowed }
    Liefert eine Liste { field, text }.
]]
function R.validateDraft(d, ctx)
    local errors = {}
    local function e(field, text) errors[#errors + 1] = { field = field, text = text } end
    local f = R.form(d.legalForm)
    if not f then return { { field = 'legalForm', text = 'Rechtsform fehlt.' } } end
    if f.kind ~= d.kind then e('legalForm', 'Die Rechtsform passt nicht zur Art des Antrags.') end

    if not ctx.elig.ok then
        local bad = {}
        for _, c in ipairs(ctx.elig.checks) do if not c.ok then bad[#bad + 1] = c.text end end
        e('elig', 'Voraussetzungen nicht erfüllt: ' .. table.concat(bad, '; '))
    end
    if not ctx.nameResult.ok then e('name', R.firstError(ctx.nameResult.issues)) end

    local b = d.branch and R.branch(d.branch) or nil
    if d.kind == 'unternehmen' then
        if not b then e('branch', 'Bitte eine Branche wählen.')
        elseif not ctx.resubmit and ctx.branchUsed(b.key) >= ctx.branchCap(b) then e('branch', 'In der Branche „' .. b.label .. '“ sind alle Plätze vergeben.') end
        local sum = 0
        for _, x in ipairs(d.founders) do sum = sum + (x.share or 0) end
        if sum ~= 100 then e('founders', 'Die Anteile müssen zusammen 100 % ergeben (aktuell ' .. sum .. ' %).') end
        for _, x in ipairs(d.founders) do
            if not x.share or x.share < 1 or x.share ~= math.floor(x.share) then e('founders', 'Jeder Gesellschafter braucht einen ganzzahligen Anteil von mindestens 1 %.'); break end
        end
        if U.ulen(d.concept.idea) < 80 then e('concept', 'Bitte die Geschäftsidee ausführlicher beschreiben (mindestens 80 Zeichen).') end
        local leaders = 0
        for _, x in ipairs(d.founders) do
            if not inList(Config.CompanyRoles, x.role) then e('founders', 'Unbekannte Rolle: ' .. tostring(x.role)); break end
            if x.role == 'inhaber' or x.role == 'geschaeftsfuehrer' then leaders = leaders + 1 end
        end
        if leaders < 1 then e('founders', 'Es braucht mindestens einen Inhaber oder Geschäftsführer.') end
        if d.legalForm == 'einzel' and #d.founders ~= 1 then e('founders', 'Ein Einzelunternehmen hat genau einen Inhaber.') end
    else
        if U.ulen(d.statute.purpose) < 80 then e('concept', 'Bitte den Zweck der Organisation ausführlicher beschreiben (mindestens 80 Zeichen).') end
        local chairs = 0
        for _, x in ipairs(d.founders) do
            if not inList(Config.OrgRoles, x.role) then e('founders', 'Unbekannte Rolle: ' .. tostring(x.role)); break end
            if x.role == 'vorsitz' then chairs = chairs + 1 end
        end
        if chairs ~= 1 then e('founders', 'Es muss genau einen Vorsitz geben.') end
        if not d.ooc then e('ooc', 'Bitte die OOC-Angaben ausfüllen.')
        elseif d.ooc.category == 'untergrund' and not ctx.undergroundAllowed then e('ooc', 'Untergrund-Fraktionen werden auf diesem Weg nicht angenommen.') end
    end
    if #d.founders < f.minFounders then e('founders', 'Mindestens ' .. f.minFounders .. ' Gründer erforderlich.') end
    local seen = {}
    for _, x in ipairs(d.founders) do
        if seen[x.charId] then e('founders', 'Ein Gründer ist doppelt eingetragen.'); break end
        seen[x.charId] = true
    end
    for _, x in ipairs(d.founders) do
        if x.consent ~= 'ok' and x.consent ~= 'self' then e('founders', 'Nicht alle Mitgründer haben zugestimmt.'); break end
    end
    if b and b.needsProperty and not (d.property.mode == 'immobilie' and d.property.id) then e('property', 'Diese Branche verlangt einen festen Standort.') end
    if d.property.mode == 'immobilie' and d.property.id and ctx.propertyTaken(d.property.id) and not (ctx.prev and ctx.prev.property and ctx.prev.property.id == d.property.id) then
        e('property', 'Die gewählte Immobilie ist nicht mehr frei.')
    end
    if not d.property.mode then e('property', 'Bitte einen Standort wählen oder „ohne festen Standort“ angeben.') end
    local fees = R.fees(d.legalForm, d.kind == 'unternehmen' and d.branch or nil)
    local payNow = ctx.resubmit and 0 or fees.payNow
    if payNow > (ctx.bank or 0) then e('bank', 'Der Kontostand reicht nicht aus. Benötigt: ' .. U.money(payNow) .. '.') end
    return errors
end
