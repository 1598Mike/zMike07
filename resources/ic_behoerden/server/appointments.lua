--[[
    ic_behoerden · Termine im Bürgeramt
    Dienst, Slots, Buchung, Check-in, Wartenummer, Durchführung und Entscheidung, Sprechzeiten, Sanktionen.
    Kernregel: Ohne Beamte im Dienst und ohne Sprechzeit gibt es keinen Termin (R.slots).
]]

IC = IC or {}
local R, U, S = IC.rules, IC.util, IC.store
local ok, fail = IC.ok, IC.fail
local A, D = IC.apps, IC.duty
local P = {}
IC.appt = P

-- ---------------------------------------------------------------------------
-- Strikes
-- ---------------------------------------------------------------------------
IC.strikes = {}

function IC.strikes.add(charId, reason)
    S.put('strikes', { id = IC.nextSeq('strike', 0), charId = charId, ts = IC.now(), reason = reason })
end

function IC.strikes.active(charId)
    local cutoff = IC.now() - Config.Rules.strikeDays * R.DAY
    return S.list('strikes', function(x) return x.charId == charId and x.ts > cutoff end)
end

function IC.strikes.banUntil(charId)
    local list = IC.strikes.active(charId)
    if #list < Config.Rules.strikeLimit then return nil end
    local last = 0
    for _, x in ipairs(list) do if x.ts > last then last = x.ts end end
    local untilTs = last + Config.Rules.banDays * R.DAY
    return untilTs > IC.now() and untilTs or nil
end

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------
local OPEN = R.OPEN_APPT

function P.openList() return S.list('appointments', function(a) return OPEN[a.status] end) end

function P.view(ap)
    local c = U.deepcopy(ap)
    c['end'] = ap.start + ap.minutes * R.MIN
    c.typeLabel = R.apptType(ap.typeId).label
    return c
end

local function ownEntity(ctx, id)
    local e = id and S.get('entities', tostring(id)) or nil
    if e and IC.register.leaderOf(e, ctx.char.charId) then return e end
end

-- Gibt einen Termin frei und stellt den Antrag auf den Status vor der Buchung zurück.
function P.release(ap, newStatus, actor, actorKind, text)
    ap.status = newStatus
    S.put('appointments', ap)
    local app = ap.applicationId and S.get('applications', ap.applicationId) or nil
    if app and app.status == 'termin_gebucht' then
        A.setStatus(app, app.restoreStatus or 'vorpruefung_ok', actor or 'System', actorKind or 'system', text)
    end
    return app
end

-- Schließt alle offenen Termine eines Antrags (beim Rückzug), ohne den Antragsstatus anzufassen.
function P.releaseFor(app, newStatus)
    for _, ap in ipairs(S.list('appointments', function(a) return a.applicationId == app.id and OPEN[a.status] end)) do
        ap.status = newStatus
        S.put('appointments', ap)
    end
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------
function P.slotCtx(excludeId)
    local officeHours = {}
    for _, h in ipairs(S.list('officeHours')) do
        officeHours[#officeHours + 1] = { officialId = h.officialId, start = h.start, finish = h.finish, types = h.types, snapshotRank = h.officialRank }
    end
    local live = U.map(D.list(), function(o) return { id = o.id, rank = o.rank } end)
    local snapshot = {}
    for _, h in ipairs(officeHours) do snapshot[h.officialId] = h.snapshotRank end
    return {
        now = IC.now(), liveOfficials = live, officeHours = officeHours, appointments = P.openList(), excludeId = excludeId,
        rankOf = function(id) return D.rankOf(id, snapshot[id]) end,
    }
end

function P.slotsFor(type, dayOffset, excludeId)
    local now = IC.now()
    local dayStart = U.startOfDay(now + dayOffset * R.DAY)
    local dayEnd = U.startOfDay(dayStart + 30 * R.HOUR)
    return R.slots(type, dayStart, dayEnd, P.slotCtx(excludeId)), dayStart
end

function P.nextFree()
    local t = R.apptType('beratung')
    for d = 0, Config.Rules.bookAheadDays do
        for _, sl in ipairs((P.slotsFor(t, d))) do if sl.free > 0 then return sl.start end end
    end
    return nil
end

function P.slotsList(ctx, p)
    local t = R.apptType(tostring(p.typeId or ''))
    if not t then return fail('Unbekannte Terminart.') end
    local excl = p.excludeApptId and S.get('appointments', tostring(p.excludeApptId)) or nil
    if excl and excl.booker ~= ctx.char.charId then excl = nil end
    local exclId = excl and excl.id or nil
    local days = {}
    for d = 0, Config.Rules.bookAheadDays do
        local sl, dayStart = P.slotsFor(t, d, exclId)
        local free = 0
        for _, x in ipairs(sl) do if x.free > 0 then free = free + 1 end end
        days[#days + 1] = { offset = d, ts = dayStart, free = free, total = #sl }
    end
    local off = U.clamp(U.round(tonumber(p.dayOffset) or 0), 0, Config.Rules.bookAheadDays)
    return ok({ days = days, slots = (P.slotsFor(t, off, exclId)), dayOffset = off, eligible = #D.eligible(t), onDuty = #D.list() })
end

-- ---------------------------------------------------------------------------
-- Buchen, Absagen, Einchecken
-- ---------------------------------------------------------------------------
function P.book(ctx, p)
    local me = ctx.char
    local t = R.apptType(tostring(p.typeId or ''))
    if not t then return fail('Unbekannte Terminart.') end
    local ban = IC.strikes.banUntil(me.charId)
    if ban then return fail('Sie sind für Termine gesperrt bis ' .. U.fdt(ban) .. '.') end

    local old = p.rescheduleId and S.get('appointments', tostring(p.rescheduleId)) or nil
    if p.rescheduleId and (not old or old.booker ~= me.charId or not OPEN[old.status] or old.status == 'laeuft') then return fail('Der Termin lässt sich nicht verschieben.') end
    local openCount = S.count('appointments', function(a) return OPEN[a.status] and a.booker == me.charId and (not old or a.id ~= old.id) end)
    if openCount >= Config.Rules.maxOpenAppointments then return fail('Sie haben bereits ' .. Config.Rules.maxOpenAppointments .. ' offene Termine.') end

    local app, ent
    if t.needs == 'application' then
        app = S.get('applications', tostring(p.applicationId or ''))
        if not app or not A.mine(app, me.charId) then return fail('Bitte einen Antrag auswählen.') end
        local rescheduling = old ~= nil and old.applicationId == app.id and app.status == 'termin_gebucht'
        if app.status == 'termin_gebucht' and not rescheduling then return fail('Für diesen Antrag ist bereits ein Termin gebucht.') end
        if not U.contains(t.forStatus, app.status) and not rescheduling then
            return fail('Für diesen Antrag ist der Termin noch nicht möglich (Status: ' .. app.status .. ').')
        end
        if t.appKind and app.kind ~= t.appKind then return fail('Diese Terminart passt nicht zum Antrag.') end
        if not rescheduling and S.count('appointments', function(a) return a.applicationId == app.id and OPEN[a.status] end) > 0 then
            return fail('Für diesen Antrag ist bereits ein Termin gebucht.')
        end
    elseif t.needs == 'entity' then
        ent = ownEntity(ctx, p.entityId)
        if not ent then return fail('Bitte einen Eintrag auswählen.') end
        if t.entityNeeds == 'conditions' and #IC.register.openConditions(ent) == 0 then return fail('Für diesen Eintrag sind keine Auflagen offen.') end
    end

    local start = tonumber(p.start)
    if not start then return fail('Bitte einen Termin wählen.') end
    local dayOffset = U.round((U.startOfDay(start) - U.startOfDay(IC.now())) / R.DAY)
    if dayOffset < 0 or dayOffset > Config.Rules.bookAheadDays then return fail('Dieser Tag liegt außerhalb des Buchungszeitraums.') end
    local slot
    for _, x in ipairs((P.slotsFor(t, dayOffset, old and old.id or nil))) do if x.start == start then slot = x end end
    if not slot then return fail('Zu diesem Zeitpunkt ist kein Beamter verfügbar.') end
    if slot.free < 1 then return fail('Dieser Termin ist leider schon vergeben.') end

    -- Teilnehmer: nur der Bürger selbst und (bei Anträgen) die Gründer des Antrags
    local wanted = {}
    for _, id in ipairs(type(p.attendees) == 'table' and p.attendees or {}) do wanted[tostring(id)] = true end
    wanted[me.charId] = true
    local att = {}
    if app then
        local must = R.mandatory(app)
        for _, f in ipairs(app.founders) do
            if wanted[f.charId] then
                att[#att + 1] = { charId = f.charId, name = f.name, checkedIn = false, mandatory = U.contains(must, f.charId) }
            end
        end
        local missing = {}
        for _, id in ipairs(must) do
            if not U.find(att, function(x) return x.charId == id end) then
                missing[#missing + 1] = (U.find(app.founders, function(f) return f.charId == id end) or {}).name or id
            end
        end
        if #missing > 0 then return fail('Es fehlen Pflichtteilnehmer: ' .. table.concat(missing, ', ') .. '.') end
    else
        att[1] = { charId = me.charId, name = me.name, checkedIn = false, mandatory = true }
    end
    if not U.find(att, function(x) return x.charId == me.charId end) then
        att[#att + 1] = { charId = me.charId, name = me.name, checkedIn = false, mandatory = true }
    end

    if old then
        old.status = 'abgesagt'
        S.put('appointments', old)
    end
    local ap = {
        id = 'T-' .. IC.nextSeq('appt', 0), typeId = t.key, applicationId = app and app.id or nil, entityId = ent and ent.id or nil,
        start = start, minutes = t.minutes, status = 'gebucht', booker = me.charId, bookerName = me.name, attendees = att,
        note = U.trim(p.note or ''):sub(1, 200), source = slot.source, createdAt = IC.now(),
    }
    S.put('appointments', ap)
    if app then
        if app.status ~= 'termin_gebucht' then app.restoreStatus = app.status end
        app.apptId, app.priority = ap.id, false
        A.setStatus(app, 'termin_gebucht', me.name, 'bürger', 'Vorstellungstermin gebucht', U.fdt(ap.start) .. ' Uhr')
    end
    IC.audit(me.name, 'bürger', 'Termin gebucht', ap.id, t.label .. ', ' .. U.fdt(ap.start))
    -- Mitgründer informieren
    for _, x in ipairs(att) do
        if x.charId ~= me.charId then IC.notify(x.charId, me.name .. ' hat einen Termin im Bürgeramt gebucht: ' .. t.label .. ', ' .. U.fdt(ap.start) .. ' Uhr. Bitte erscheinen Sie pünktlich.', 'info') end
    end
    return ok({ id = ap.id })
end

function P.cancel(ctx, p)
    local ap = S.get('appointments', tostring(p.id or ''))
    if not ap or ap.booker ~= ctx.char.charId then return fail('Termin nicht gefunden.') end
    if ap.status ~= 'gebucht' and ap.status ~= 'eingecheckt' then return fail('Dieser Termin lässt sich nicht mehr absagen.') end
    local late = ap.start - IC.now() < Config.Rules.cancelFreeMinutes * R.MIN
    if late then IC.strikes.add(ctx.char.charId, 'Kurzfristige Absage ' .. ap.id) end
    P.release(ap, 'abgesagt', ctx.char.name, 'bürger', 'Termin abgesagt')
    IC.audit(ctx.char.name, 'bürger', 'Termin abgesagt', ap.id, late and 'Kurzfristig, 1 Strike' or 'Rechtzeitig')
    return ok({ strike = late })
end

function P.checkin(ctx, p)
    local ap = S.get('appointments', tostring(p.id or ''))
    if not ap then return fail('Termin nicht gefunden.') end
    local me = U.find(ap.attendees, function(x) return x.charId == ctx.char.charId end)
    if not me then return fail('Sie sind für diesen Termin nicht eingetragen.') end
    if ap.status ~= 'gebucht' and ap.status ~= 'eingecheckt' then return fail('Einchecken ist für diesen Termin nicht mehr möglich.') end
    local st = R.checkinState(ap, ctx.char.charId, IC.now())
    if st.early then return fail('Einchecken ist ab ' .. Config.Rules.checkinBefore .. ' Minuten vor Terminbeginn möglich (ab ' .. U.ftime(ap.start - Config.Rules.checkinBefore * R.MIN) .. ' Uhr).') end
    if st.late then return fail('Das Check-in-Fenster ist geschlossen.') end
    me.checkedIn = true
    local all = true
    for _, x in ipairs(ap.attendees) do if x.mandatory and not x.checkedIn then all = false end end
    if all then ap.status = 'eingecheckt' end
    S.put('appointments', ap)
    return ok({ allIn = ap.status == 'eingecheckt', othersIn = 0 })
end

-- ---------------------------------------------------------------------------
-- Wartenummer (nur Beratung) und Aufrufanzeige
-- ---------------------------------------------------------------------------
IC.queue = { list = {}, seq = 0, calling = nil, called = {} }

local function queueEta(position) return math.max(3, U.round((position * 8) / math.max(1, #D.list()))) end

function P.queueTake(ctx, p)
    local me = ctx.char
    local q = IC.queue
    if p.typeId and p.typeId ~= 'beratung' then return fail('Eine Wartenummer gibt es nur für die Beratung. Für eine Vorstellung buchen Sie einen Live-Termin.') end
    if U.find(q.list, function(x) return x.charId == me.charId end) or q.called[me.charId] then return fail('Sie haben bereits eine Wartenummer.') end
    if #D.eligible(R.apptType('beratung')) < 1 then return fail('Zurzeit ist kein Beamter im Dienst. Eine Wartenummer ist nicht möglich.') end
    q.seq = q.seq + 1
    local no = string.format('A-%03d', q.seq)
    q.list[#q.list + 1] = { no = no, who = me.name, charId = me.charId, typeId = 'beratung', at = IC.now() }
    return ok({ no = no, position = #q.list, etaMin = queueEta(#q.list) })
end

function P.dropChar(charId)
    local q = IC.queue
    for i = #q.list, 1, -1 do if q.list[i].charId == charId then table.remove(q.list, i) end end
    q.called[charId] = nil
end

function P.queueLeave(ctx)
    P.dropChar(ctx.char.charId)
    return ok()
end

function P.queueNext(ctx)
    local e = A.needOnDuty(ctx)
    if e then return e end
    local q = IC.queue
    local t = table.remove(q.list, 1)
    if not t then return fail('Die Warteschlange ist leer.') end
    local desk = D.get(ctx.off.id).desk
    q.calling = { no = t.no, desk = desk, at = IC.now() }
    q.called[t.charId] = { no = t.no, typeId = t.typeId, at = t.at, calledAt = IC.now() }
    IC.notify(t.charId, 'Ihre Wartenummer ' .. t.no .. ' wird aufgerufen: Schalter ' .. desk .. '.', 'warn')
    return ok({ no = t.no })
end

-- Ticket des Bürgers für die Oberfläche (auch nach dem Aufruf, bis zu 10 Minuten)
function P.myTicket(charId)
    local q = IC.queue
    for i, t in ipairs(q.list) do
        if t.charId == charId then return { no = t.no, typeId = t.typeId, at = t.at, position = i, called = false } end
    end
    local c = q.called[charId]
    if c then
        if IC.now() - c.calledAt > 10 * R.MIN then q.called[charId] = nil return nil end
        return { no = c.no, typeId = c.typeId, at = c.at, position = 0, called = true }
    end
    return nil
end

function P.board()
    local q = IC.queue
    local calling = q.calling and (IC.now() - q.calling.at < 10 * R.MIN) and q.calling or nil
    return { calling = calling, waiting = #q.list }
end

-- ---------------------------------------------------------------------------
-- Benachrichtigung, sobald ein Beamter im Dienst ist
-- ---------------------------------------------------------------------------
local function charRow(charId)
    local row = S.get('chars', charId)
    if not row then row = { id = charId, notifyOnDuty = false, lastNotified = 0 } end
    return row
end

function P.notifyOnDuty(ctx, p)
    local row = charRow(ctx.char.charId)
    row.notifyOnDuty = p.enabled == true
    S.put('chars', row)
    return ok({ enabled = row.notifyOnDuty })
end

function P.notifySubscribers()
    local now = IC.now()
    for _, row in ipairs(S.list('chars', function(c) return c.notifyOnDuty end)) do
        if now - (row.lastNotified or 0) > 30 * R.MIN then
            IC.notify(row.id, 'Ein Beamter ist jetzt im Dienst. Termine sind buchbar.', 'ok')
            row.notifyOnDuty, row.lastNotified = false, now
            S.put('chars', row)
        end
    end
end

function P.dutySet(ctx, p)
    local state = tostring(p.state or '')
    if state ~= 'on' and state ~= 'pause' and state ~= 'off' then return fail('Unbekannter Dienststatus.') end
    local was = D.set(ctx.off, state, p.desk)
    IC.audit(ctx.off.name, 'beamter', 'Dienststatus', ctx.off.dienstnr, was .. ' → ' .. state)
    if state == 'on' and was ~= 'on' then P.notifySubscribers() end
    return ok({ state = state })
end

-- ---------------------------------------------------------------------------
-- Durchführung (Beamte)
-- ---------------------------------------------------------------------------
function P.call(ctx, p)
    local e = A.needOnDuty(ctx)
    if e then return e end
    local ap = S.get('appointments', tostring(p.id or ''))
    if not ap or (ap.status ~= 'gebucht' and ap.status ~= 'eingecheckt') then return fail('Dieser Termin lässt sich nicht aufrufen.') end
    e = A.needRank(ctx, R.apptType(ap.typeId).minRank)
    if e then return e end
    ap.status = 'aufgerufen'
    S.put('appointments', ap)
    local desk = D.get(ctx.off.id).desk
    IC.queue.calling = { no = ap.id, desk = desk, at = IC.now() }
    for _, x in ipairs(ap.attendees) do IC.notify(x.charId, 'Sie werden aufgerufen: Schalter ' .. desk .. '.', 'warn') end
    return ok()
end

function P.start(ctx, p)
    local e = A.needOnDuty(ctx)
    if e then return e end
    local ap = S.get('appointments', tostring(p.id or ''))
    if not ap or (ap.status ~= 'gebucht' and ap.status ~= 'eingecheckt' and ap.status ~= 'aufgerufen') then return fail('Dieser Termin lässt sich nicht starten.') end
    local t = R.apptType(ap.typeId)
    e = A.needRank(ctx, t.minRank)
    if e then return e end
    local app = ap.applicationId and S.get('applications', ap.applicationId) or nil
    if app and A.conflicted(app, ctx.off.id) then return fail('Sie sind befangen und dürfen diesen Termin nicht führen.') end
    local missing = U.filter(ap.attendees, function(x) return x.mandatory and not x.checkedIn end)
    if #missing > 0 then return fail('Pflichtteilnehmer fehlen noch: ' .. table.concat(U.map(missing, function(m) return m.name end), ', ') .. '.') end
    ap.status, ap.official, ap.startedAt = 'laeuft', { id = ctx.off.id, name = ctx.off.name }, IC.now()
    S.put('appointments', ap)
    if app and app.status == 'termin_gebucht' then A.setStatus(app, 'termin_laeuft', ctx.off.name, 'beamter', 'Vorstellungstermin begonnen') end
    return ok()
end

function P.noShow(ctx, p)
    local e = A.needOnDuty(ctx)
    if e then return e end
    local ap = S.get('appointments', tostring(p.id or ''))
    if not ap or not OPEN[ap.status] or ap.status == 'laeuft' then return fail('Dieser Termin lässt sich nicht als „nicht erschienen“ markieren.') end
    local lateAt = ap.start + Config.Rules.checkinAfter * R.MIN
    if IC.now() < lateAt then return fail('Erst ' .. Config.Rules.checkinAfter .. ' Minuten nach Terminbeginn möglich (ab ' .. U.ftime(lateAt) .. ' Uhr).') end
    local excused = p.excused == true
    if not excused then IC.strikes.add(ap.booker, 'Nicht erschienen ' .. ap.id) end
    P.release(ap, excused and 'abgesagt' or 'nicht_erschienen', ctx.off.name, 'beamter', excused and 'Termin entschuldigt' or 'Gründer nicht erschienen')
    IC.audit(ctx.off.name, 'beamter', excused and 'Entschuldigt' or 'Nicht erschienen', ap.id, ap.bookerName)
    return ok()
end

local function decisionLabel(dec)
    return ({ genehmigt = 'Genehmigt', auflagen = 'Genehmigt mit Auflagen', vertagt = 'Vertagt (Nachbesserung)', abgelehnt = 'Abgelehnt' })[dec]
end

function P.decide(ctx, p)
    local e = A.needOnDuty(ctx)
    if e then return e end
    local ap = S.get('appointments', tostring(p.id or ''))
    if not ap or ap.status ~= 'laeuft' then return fail('Der Termin muss laufen, bevor entschieden werden kann.') end
    if not ap.official or ap.official.id ~= ctx.off.id then return fail('Dieser Termin wird von einem anderen Beamten geführt.') end
    local t = R.apptType(ap.typeId)
    e = A.needRank(ctx, 'sachbearbeiter') or A.needRank(ctx, t.minRank)
    if e then return e end

    local dec = tostring(p.decision or '')
    if not decisionLabel(dec) then return fail('Bitte eine Entscheidung wählen.') end
    local reason = U.trim(p.reason or ''):sub(1, 1000)
    local conds = {}
    for _, c in ipairs(type(p.conditions) == 'table' and p.conditions or {}) do
        local x = U.trim(c):sub(1, 200)
        if x ~= '' and #conds < 10 then conds[#conds + 1] = x end
    end
    local checked = type(p.checklist) == 'table' and p.checklist or {}
    if dec == 'genehmigt' then
        local open = R.checklistMissing(t.key, checked)
        if #open > 0 then return fail('Für eine Genehmigung müssen alle Pflichtpunkte der Checkliste erfüllt sein (offen: ' .. #open .. ').') end
    end
    if dec == 'auflagen' and #conds == 0 then return fail('Bitte mindestens eine Auflage angeben.') end
    if dec ~= 'genehmigt' and U.ulen(reason) < 10 then return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).') end

    local app = ap.applicationId and S.get('applications', ap.applicationId) or nil
    local ent = ap.entityId and S.get('entities', ap.entityId) or nil
    if app and A.conflicted(app, ctx.off.id) then return fail('Sie sind befangen und dürfen hier nicht entscheiden.') end

    local name = ctx.off.name
    ap.status = 'abgeschlossen'
    ap.result = { decision = dec, reason = reason, conditions = conds, by = name, at = IC.now() }
    S.put('appointments', ap)
    IC.pay.official(ctx.src, Config.Rules.officialPay, 'Terminpauschale ' .. ap.id)

    local outcome
    if t.key == 'beratung' then
        outcome = 'beratung'
    elseif t.key == 'aenderung' and ent then
        if dec == 'genehmigt' and ent.pendingChange then
            if ent.pendingChange.type == 'name' then ent.name = ent.pendingChange.value else ent.hq = ent.pendingChange.value end
            ent.pendingChange = nil
            outcome = 'geaendert'
        elseif dec ~= 'genehmigt' then
            ent.pendingChange = nil
            outcome = 'abgelehnt'
        end
        S.put('entities', ent)
    elseif t.key == 'nachkontrolle' and ent then
        if dec == 'genehmigt' then
            for _, c in ipairs(ent.conditions) do c.done = true end
            S.put('entities', ent)
            if ent.status == 'probezeit' then IC.register.setStatus(ent, 'aktiv', name, 'Auflagen erfüllt') end
            outcome = 'erfuellt'
        else
            outcome = 'offen'
        end
    elseif app then
        app.decision = { decision = dec, reason = reason, by = name, at = IC.now(), conditions = conds }
        if t.key == 'einspruch' then
            if dec == 'genehmigt' or dec == 'auflagen' then
                A.pushEvent(app, 'einspruch', name, 'beamter', 'Einspruch stattgegeben', reason ~= '' and reason or nil)
                if R.staffGateNeeded(app) then
                    A.setStatus(app, 'staff_pruefung', 'Registerführung', 'system', 'Schlussprüfung durch die Registerführung', 'Die Eintragung wird nach der Schlussprüfung vollzogen.')
                    outcome = 'staff'
                else
                    IC.register.create(app)
                    outcome = 'eingetragen'
                end
            else
                app.objectionUntil = 0
                A.setStatus(app, 'abgelehnt', name, 'beamter', 'Einspruch zurückgewiesen', reason)
                outcome = 'abgelehnt'
            end
        elseif dec == 'genehmigt' or dec == 'auflagen' then
            A.pushEvent(app, 'termin_laeuft', name, 'beamter', dec == 'auflagen' and 'Genehmigt mit Auflagen' or 'Genehmigt', reason ~= '' and reason or nil)
            if R.staffGateNeeded(app) then
                A.setStatus(app, 'staff_pruefung', 'Registerführung', 'system', 'Schlussprüfung durch die Registerführung', 'Die Eintragung wird nach der Schlussprüfung vollzogen.')
                outcome = 'staff'
            else
                IC.register.create(app)
                outcome = 'eingetragen'
            end
        elseif dec == 'vertagt' then
            app.remark, app.priority = reason, true
            A.setStatus(app, 'nachbesserung', name, 'beamter', 'Vertagt, Nachbesserung erforderlich', reason)
            outcome = 'vertagt'
        else
            app.objectionUntil = IC.now() + Config.Rules.objectionHours * R.HOUR
            A.refund(app)
            A.setStatus(app, 'abgelehnt', name, 'beamter', 'Antrag abgelehnt', reason)
            outcome = 'abgelehnt'
        end
        local kind = dec == 'abgelehnt' and 'bad' or dec == 'vertagt' and 'warn' or 'ok'
        for _, f in ipairs(app.founders) do
            IC.notify(f.charId, 'Entscheidung zu „' .. app.name .. '“: ' .. decisionLabel(dec) .. '.', kind)
        end
    end
    IC.audit(name, 'beamter', 'Entscheidung', app and app.caseNo or ap.id, decisionLabel(dec) .. (reason ~= '' and (': ' .. reason:sub(1, 60)) or ''))
    IC.webhook('staff', 'Entscheidung ' .. (app and app.caseNo or ap.id), (app and app.name or t.label) .. ' · ' .. decisionLabel(dec) .. ' · ' .. name)
    local regNo
    if app and app.entityId then local en = S.get('entities', app.entityId); regNo = en and en.regNo end
    return ok({ outcome = outcome, decision = dec, caseNo = app and app.caseNo or nil, regNo = regNo })
end

-- ---------------------------------------------------------------------------
-- Sprechzeiten
-- ---------------------------------------------------------------------------
function P.hoursCreate(ctx, p)
    local e = A.needRank(ctx, 'sachbearbeiter')
    if e then return e end
    local start, finish = tonumber(p.start), tonumber(p.finish or p['end'])
    if not start or not finish or not (finish > start) then return fail('Das Ende muss nach dem Beginn liegen.') end
    if finish - start < 30 * R.MIN then return fail('Eine Sprechzeit dauert mindestens 30 Minuten.') end
    if finish - start > 12 * R.HOUR then return fail('Eine Sprechzeit dauert höchstens 12 Stunden.') end
    if start < IC.now() then return fail('Sprechzeiten müssen in der Zukunft liegen.') end
    if start > IC.now() + Config.Rules.bookAheadDays * R.DAY then return fail('Sprechzeiten sind höchstens ' .. Config.Rules.bookAheadDays .. ' Tage im Voraus möglich.') end
    local clash = S.count('officeHours', function(h) return h.officialId == ctx.off.id and h.start < finish and h.finish > start end)
    if clash > 0 then return fail('Sie haben in diesem Zeitraum bereits eine Sprechzeit.') end
    local h = { id = 'H-' .. IC.nextSeq('hours', 0), officialId = ctx.off.id, officialName = ctx.off.name, officialRank = ctx.off.rank, start = start, finish = finish }
    S.put('officeHours', h)
    IC.audit(ctx.off.name, 'beamter', 'Sprechzeit veröffentlicht', h.id, U.fdt(start) .. ' bis ' .. U.ftime(finish))
    return ok({ id = h.id })
end

function P.hoursDelete(ctx, p)
    local h = S.get('officeHours', tostring(p.id or ''))
    if not h then return fail('Sprechzeit nicht gefunden.') end
    if h.officialId ~= ctx.off.id and not R.rankAtLeast(ctx.off.rank, 'amtsleiter') then return fail('Fremde Sprechzeiten kann nur ein Amtsleiter löschen.') end
    S.del('officeHours', h.id)
    IC.audit(ctx.off.name, 'beamter', 'Sprechzeit gelöscht', h.id, U.fdt(h.start))
    return ok()
end

-- ---------------------------------------------------------------------------
-- Sanktionen (Amtsleiter)
-- ---------------------------------------------------------------------------
local SANCTION = { verwarnung = 'Verwarnung', bussgeld = 'Bußgeld', auflage = 'Neue Auflage', untersagung = 'Befristete Gewerbeuntersagung', entzug = 'Entzug der Eintragung' }

function P.sanction(ctx, p)
    local e = A.needOnDuty(ctx) or A.needRank(ctx, 'amtsleiter')
    if e then return e end
    local ent = S.get('entities', tostring(p.entityId or ''))
    if not ent then return fail('Eintrag nicht gefunden.') end
    if not SANCTION[p.level] then return fail('Unbekannte Maßnahme.') end
    local reason = U.trim(p.reason or ''):sub(1, 500)
    if U.ulen(reason) < 10 then return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).') end
    local entry = { ts = IC.now(), level = p.level, reason = reason, by = ctx.off.name }
    if p.level == 'bussgeld' then entry.amount = U.clamp(U.round(tonumber(p.amount) or 500), 100, 10000) end
    ent.history = ent.history or {}
    ent.history[#ent.history + 1] = entry
    if p.level == 'auflage' then
        ent.conditions[#ent.conditions + 1] = { id = 'C-' .. IC.nextSeq('cond', 0), text = reason, due = IC.now() + 14 * R.DAY, done = false }
    end
    S.put('entities', ent)
    if p.level == 'untersagung' then IC.register.setStatus(ent, 'gesperrt', ctx.off.name, reason) end
    if p.level == 'entzug' then IC.register.dissolve(ent, ctx.off.name) end
    IC.audit(ctx.off.name, 'beamter', 'Sanktion: ' .. SANCTION[p.level], ent.regNo, reason:sub(1, 60))
    IC.hook('onSanction', ent, entry)
    for _, m in ipairs(ent.members or {}) do
        if IC.register.isLeader(m.role) then IC.notify(m.charId, 'Gegen „' .. ent.name .. '“ wurde eine Maßnahme verhängt: ' .. SANCTION[p.level] .. '.', 'warn') end
    end
    return ok()
end

-- ---------------------------------------------------------------------------
-- Zeitliche Übergänge: Ausfälle, wenn zum Terminbeginn kein Beamter da ist
-- ---------------------------------------------------------------------------
function P.tick()
    local now = IC.now()
    for _, ap in ipairs(S.list('appointments', function(a) return a.status == 'gebucht' or a.status == 'eingecheckt' end)) do
        if now > ap.start + Config.Rules.checkinAfter * R.MIN and #D.eligible(R.apptType(ap.typeId)) == 0 then
            local app = ap.applicationId and S.get('applications', ap.applicationId) or nil
            if app then app.priority = true end
            P.release(ap, 'beamter_ausfall', 'System', 'system', 'Termin ausgefallen: kein Beamter im Dienst')
            IC.audit('System', 'system', 'Beamten-Ausfall', ap.id, 'Kein Beamter zum Terminbeginn im Dienst, kein Strike')
            IC.notify(ap.booker, 'Ihr Termin um ' .. U.ftime(ap.start) .. ' Uhr ist ausgefallen, weil kein Beamter im Dienst war. Sie erhalten Vorrang bei einem Ersatztermin.', 'warn')
        end
    end
    -- Beamter während des Termins verschwunden (Verbindungsabbruch, Dienstende)
    local onDuty = {}
    for _, o in ipairs(D.list()) do onDuty[o.id] = true end
    for _, ap in ipairs(S.list('appointments', function(a) return a.status == 'laeuft' end)) do
        if ap.official and not onDuty[ap.official.id] and now - (ap.startedAt or now) > 2 * R.MIN then
            local app = ap.applicationId and S.get('applications', ap.applicationId) or nil
            if app then app.priority = true end
            P.release(ap, 'beamter_ausfall', 'System', 'system', 'Termin unterbrochen: Beamter nicht mehr im Dienst')
            IC.audit('System', 'system', 'Termin unterbrochen', ap.id, 'Der Beamte war nicht mehr im Dienst, Vorrang für den Ersatztermin')
            IC.notify(ap.booker, 'Ihr Termin wurde unterbrochen. Sie erhalten Vorrang bei einem Ersatztermin.', 'warn')
        end
    end
end
