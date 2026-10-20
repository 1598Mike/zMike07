--[[
    ic_behoerden · Anträge
    Namensprüfung, Entwurf, Einreichen, Vorprüfung, Rückzug, Einspruch, Einladungen von Mitgründern und die Verwaltung
    bestehender Eintragungen. Alle Funktionen bekommen ctx (wer fragt) und data (was die Oberfläche schickt) und liefern
    { ok = true, ... } oder { ok = false, error = ... }, genau wie das Mock-Backend der Vorschau.
]]

IC = IC or {}
local R, U, S = IC.rules, IC.util, IC.store
local ok, fail = IC.ok, IC.fail
local A = {}
IC.apps = A

local INVITE_TTL = 5 * R.MIN
A.invites = {}   -- [Antragsteller-Charakter][eingeladener Charakter] = { state, name, at }

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------
function A.mine(app, charId)
    if app.applicant.charId == charId then return true end
    for _, f in ipairs(app.founders or {}) do if f.charId == charId then return true end end
    return false
end

function A.lastTs(app)
    local e = app.events and app.events[#app.events]
    return e and e.ts or app.createdAt
end

-- Seit wann wartet der Antrag auf einen Termin? Nur nach bestandener Vorprüfung und nach einem Einspruch (sonst nil).
function A.waitingSince(a)
    if a.status == 'vorpruefung_ok' then return a.vorpruefungAt or A.lastTs(a) end
    if a.status == 'einspruch' then return A.lastTs(a) end
end

function A.pushEvent(app, status, actor, actorKind, text, note)
    app.events[#app.events + 1] = { ts = IC.now(), status = status, actor = actor, actorKind = actorKind, text = text, note = note }
end

-- Wechselt den Status, prüft den Übergang und trägt ein Ereignis ein. eventStatus ändert nur das Symbol in der Zeitleiste.
function A.setStatus(app, to, actor, actorKind, text, note, eventStatus)
    if app.status ~= to and not R.canTransition(app.status, to) then
        print(('[ic_behoerden] Unzulässiger Statuswechsel %s: %s -> %s'):format(app.caseNo or app.id, app.status, to))
        return false
    end
    app.status = to
    app.escalationSent = nil
    if R.OPEN_APP[to] then app.reservedUntil = IC.now() + Config.Rules.nameReserveDays * R.DAY end
    if text then A.pushEvent(app, eventStatus or to, actor, actorKind, text, note) end
    S.put('applications', app)
    IC.emit('ic_behoerden:applicationStatusChanged', app)
    if to == 'staff_pruefung' then
        IC.webhook('staff', 'Schlussprüfung wartet: ' .. (app.caseNo or app.id), (app.name or '') .. ' wartet auf die Freigabe im Staff-Panel.')
    end
    return true
end

function A.openApps() return S.list('applications', R.isOpenApp) end

function A.properties()
    local list = Config.PropertyProvider and Config.PropertyProvider() or Config.Properties
    return list or {}
end

function A.property(id)
    for _, p in ipairs(A.properties()) do if p.id == id then return p end end
end

function A.propertyTaken(id)
    local p = A.property(id)
    if not p or p.status ~= 'frei' then return true end
    if S.count('applications', function(a) return R.isOpenApp(a) and a.property and a.property.id == id end) > 0 then return true end
    return S.count('entities', function(e) return e.propertyId == id and e.status ~= 'aufgeloest' end) > 0
end

-- Kontext für die Namensprüfung: Sperrliste, Register (aufgelöste Namen sind 7 Tage gesperrt) und
-- laufende Anträge (abgelehnte Namen sind 24 Stunden gesperrt).
function A.nameCtx(ignoreAppId, ignoreEntityId)
    local now = IC.now()
    local ctx = { blacklist = {}, entities = {}, openApps = {}, ignoreAppId = ignoreAppId, ignoreEntityId = ignoreEntityId }
    for _, b in ipairs(S.list('blacklist')) do ctx.blacklist[#ctx.blacklist + 1] = { term = b.term, reason = b.reason } end
    for _, e in ipairs(S.list('entities')) do
        local status = e.status
        if status == 'aufgeloest' and e.dissolvedAt and now - e.dissolvedAt < 7 * R.DAY then status = 'gesperrt' end
        ctx.entities[#ctx.entities + 1] = { id = e.id, name = e.name, status = status, regNo = e.regNo }
    end
    for _, a in ipairs(S.list('applications')) do
        local blocked = R.isOpenApp(a)
        if a.status == 'abgelehnt' and a.decision and now - (a.decision.at or 0) < 24 * R.HOUR then blocked = true end
        if blocked and a.name and a.name ~= '' then ctx.openApps[#ctx.openApps + 1] = { id = a.id, name = a.name, caseNo = a.caseNo or '' } end
    end
    return ctx
end

function A.eligibility(ctx, kind, excludeAppId)
    local c = ctx.char
    local companies, orgs = IC.register.counts(c.charId)
    local open = S.count('applications', function(a) return R.isOpenApp(a) and a.applicant.charId == c.charId and a.id ~= excludeAppId end)
    return R.eligibility(c, kind, { isMe = true, openApps = open, companies = companies, orgs = orgs, banUntil = IC.strikes.banUntil(c.charId) })
end

-- Erstattet verwahrte Beträge (Eintragungsgebühr und Kapital). Die Antragsgebühr bleibt bei der Stadtkasse.
function A.refund(app)
    if not app.fees or not app.fees.paid or app.fees.refunded then return 0 end
    local back = (app.fees.register or 0) + (app.fees.capital or 0)
    IC.pay.refund(app.applicant.charId, back, 'Gewerbeamt: Erstattung ' .. (app.caseNo or app.id))
    app.fees.refunded = back
    return back
end

-- Befangen: Wer selbst am Antrag beteiligt ist oder Befangenheit gemeldet hat, darf ihn nicht bearbeiten.
function A.conflicted(app, charId)
    if A.mine(app, charId) then return true end
    for _, id in ipairs(app.conflicts or {}) do if id == charId then return true end end
    return false
end

-- ---------------------------------------------------------------------------
-- Namensprüfung
-- ---------------------------------------------------------------------------
function A.nameCheck(ctx, p)
    local name, form = U.ucut(tostring(p.name or ''), 120), U.ucut(tostring(p.legalForm or ''), 20)
    local res = R.nameCheck(name, form, A.nameCtx(type(p.ignoreAppId) == 'string' and p.ignoreAppId or nil))
    -- Wie im Mock der Vorschau: "ok" bedeutet hier "Name ist zulässig", nicht "Anfrage gelungen".
    return { ok = res.ok, normalized = res.normalized, display = res.display, issues = res.issues }
end

-- ---------------------------------------------------------------------------
-- Einladungen von Mitgründern. Die Zustimmung entsteht nur hier, nie im Browser.
-- ---------------------------------------------------------------------------
function A.founderInvite(ctx, p)
    local me = ctx.char
    local targetId = tostring(p.charId or '')
    local targetSrc = IC.bridge.srcOfChar(targetId)
    if targetId == me.charId or not targetSrc or not IC.bridge.isNear(ctx.src, targetSrc, 15.0) then
        return fail('Diese Person ist nicht in Ihrer Nähe.')
    end
    local t = IC.bridge.getChar(targetSrc)
    local el = R.eligibility(t, 'unternehmen', {})
    if not el.ok then
        local bad = {}
        for _, c in ipairs(el.checks) do if not c.ok then bad[#bad + 1] = c.text end end
        return fail(t.name .. ' erfüllt die Voraussetzungen nicht: ' .. table.concat(bad, '; ') .. '.')
    end
    local mine = A.invites[me.charId] or {}
    A.invites[me.charId] = mine
    local ex = mine[targetId]
    if ex and ex.state == 'pending' and IC.now() - ex.at < INVITE_TTL then return ok() end
    mine[targetId] = { state = 'pending', name = t.name, at = IC.now(), from = me.name }
    IC.bridge.askInvite(targetSrc, me.name)
    return ok()
end

-- Antwort des eingeladenen Spielers (kommt vom Client des Eingeladenen). Beantwortet die jüngste offene Einladung.
function A.inviteAnswer(targetCharId, accept)
    local newest
    for _, list in pairs(A.invites) do
        local inv = list[targetCharId]
        if inv and inv.state == 'pending' and IC.now() - inv.at < INVITE_TTL then
            if not newest or inv.at > newest.at then newest = inv end
        end
    end
    if newest then newest.state = accept and 'ok' or 'no' end
    return newest ~= nil
end

function A.founderStatus(ctx)
    local statuses = {}
    for id, inv in pairs(A.invites[ctx.char.charId] or {}) do
        if inv.state == 'pending' and IC.now() - inv.at >= INVITE_TTL then inv.state = 'expired' end
        statuses[id] = inv.state
    end
    return ok({ statuses = statuses })
end

function A.founderCancel(ctx, p)
    local mine = A.invites[ctx.char.charId]
    if mine then mine[tostring(p.charId or '')] = nil end
    return ok()
end

-- Bildet die Gründerliste aus dem Entwurf: Name und Zustimmung bestimmt der Server.
function A.deriveFounders(ctx, d, prev)
    local out = {}
    for _, f in ipairs(d.founders) do
        local x = { charId = f.charId, name = f.name, role = f.role, share = f.share }
        if f.charId == ctx.char.charId then
            x.name, x.consent = ctx.char.name, 'self'
        else
            local inv = A.invites[ctx.char.charId] and A.invites[ctx.char.charId][f.charId]
            local old = prev and U.find(prev.founders or {}, function(o) return o.charId == f.charId end)
            if inv and inv.state == 'ok' then x.name, x.consent = inv.name, 'ok'
            elseif old and old.consent == 'ok' then x.name, x.consent = old.name, 'ok'
            else x.consent = 'pending' end
        end
        out[#out + 1] = x
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Entwurf und Einreichen
-- ---------------------------------------------------------------------------
local function ownApp(ctx, id)
    local a = id and S.get('applications', tostring(id)) or nil
    if a and a.applicant.charId == ctx.char.charId then return a end
end

function A.save(ctx, p)
    local d = R.sanitizeDraft(p.draft)
    local a = d.id and ownApp(ctx, d.id) or nil
    if d.id and not a then return fail('Antrag nicht gefunden.') end
    if a and a.status ~= 'entwurf' and a.status ~= 'nachbesserung' then return fail('Dieser Antrag kann nicht mehr bearbeitet werden.') end
    if not a then
        local drafts = S.count('applications', function(x) return x.status == 'entwurf' and x.applicant.charId == ctx.char.charId end)
        if drafts >= 5 then return fail('Sie haben bereits 5 Entwürfe. Löschen Sie einen, um einen neuen zu speichern.') end
        a = { id = 'A-' .. IC.nextSeq('app', 0), kind = d.kind, status = 'entwurf', applicant = { charId = ctx.char.charId, name = ctx.char.name }, createdAt = IC.now(), events = {}, founders = {} }
    end
    if a.kind ~= d.kind then return fail('Die Art eines Antrags lässt sich nicht ändern.') end
    a.legalForm, a.branch, a.name = d.legalForm, d.branch, d.name
    a.founders = A.deriveFounders(ctx, d, a)
    a.property, a.concept, a.statute, a.ooc = d.property, d.concept, d.statute, d.ooc
    local prop = d.property.id and A.property(d.property.id)
    if prop then a.property.label = prop.label .. ', ' .. prop.district end
    S.put('applications', a)
    return ok({ id = a.id })
end

function A.submit(ctx, p)
    local d = R.sanitizeDraft(p.draft)
    local char = ctx.char
    local prev = d.id and ownApp(ctx, d.id) or nil
    if d.id and not prev then return fail('Antrag nicht gefunden.') end
    if prev and prev.status ~= 'entwurf' and prev.status ~= 'nachbesserung' then return fail('Dieser Antrag kann nicht mehr bearbeitet werden.') end
    if prev and prev.kind ~= d.kind then return fail('Die Art eines Antrags lässt sich nicht ändern.') end
    local resubmit = prev ~= nil and prev.status == 'nachbesserung'

    d.founders = A.deriveFounders(ctx, d, prev)
    if not U.find(d.founders, function(f) return f.charId == char.charId end) then
        return fail('Sie müssen selbst als Gründer eingetragen sein.')
    end
    local prop = d.property.id and A.property(d.property.id)
    if prop then d.property.label = prop.label .. ', ' .. prop.district end

    local elig = A.eligibility(ctx, d.kind, resubmit and prev.id or nil)
    local nameRes = R.nameCheck(d.name, d.legalForm, A.nameCtx(prev and prev.id))
    local errors = R.validateDraft(d, {
        elig = elig, nameResult = nameRes, branchUsed = IC.register.branchUsed, branchCap = IC.branchCap, propertyTaken = A.propertyTaken,
        prev = prev, resubmit = resubmit, bank = IC.bridge.getBank(ctx.src), undergroundAllowed = IC.settings.get('undergroundViaPortal'),
    })
    if #errors > 0 then return fail('Der Antrag ist noch nicht vollständig.', { errors = errors }) end

    local fees = R.fees(d.legalForm, d.kind == 'unternehmen' and d.branch or nil)
    local payNow = resubmit and 0 or fees.payNow
    if not IC.pay.charge(ctx.src, payNow, 'Gewerbeamt: Antrag ' .. nameRes.display) then
        return fail('Die Zahlung ist fehlgeschlagen. Bitte prüfen Sie Ihren Kontostand.')
    end

    local a = prev
    if not a then
        a = { id = 'A-' .. IC.nextSeq('app', 0), kind = d.kind, status = 'entwurf', applicant = { charId = char.charId, name = char.name }, createdAt = IC.now(), events = {}, founders = {} }
    end
    a.legalForm, a.branch, a.name = d.legalForm, d.branch, nameRes.display
    a.founders, a.property, a.concept, a.statute, a.ooc = d.founders, d.property, d.concept, d.statute, d.ooc
    if not a.caseNo then
        local year = os.date('%Y', IC.now() // 1000)
        a.caseNo = 'GA-' .. year .. '-' .. U.pad4(IC.nextSeq('caseNo.' .. year, 0))
    end
    if not resubmit then
        a.fees = { apply = fees.apply, register = fees.register, capital = fees.capital, paid = true }
        IC.pay.toTreasury(fees.apply, 'Antragsgebühr ' .. a.caseNo)
        IC.pay.escrowIn(fees.register + fees.capital)
    end
    a.submittedAt = a.submittedAt or IC.now()
    a.remark = nil
    A.setStatus(a, 'eingereicht', char.name, 'bürger', resubmit and 'Antrag nach Nachbesserung erneut eingereicht' or 'Antrag eingereicht, Antragsgebühr bezahlt')
    A.invites[char.charId] = nil
    IC.audit(char.name, 'bürger', resubmit and 'Antrag erneut eingereicht' or 'Antrag eingereicht', a.caseNo, a.name)
    IC.webhook('staff', (resubmit and 'Antrag erneut eingereicht: ' or 'Neuer Antrag: ') .. a.caseNo, a.name .. ' · ' .. R.form(a.legalForm).label .. ' · ' .. char.name)
    return ok({ id = a.id, caseNo = a.caseNo, paid = payNow, name = a.name })
end

function A.withdraw(ctx, p)
    local a = ownApp(ctx, p.id)
    if not a then return fail('Antrag nicht gefunden.') end
    if a.status == 'entwurf' then
        S.del('applications', a.id)
        return ok({ deleted = true })
    end
    if not R.isOpenApp(a) then return fail('Dieser Antrag lässt sich nicht mehr zurückziehen.') end
    IC.appt.releaseFor(a, 'abgesagt')
    local back = A.refund(a)
    A.setStatus(a, 'zurueckgezogen', ctx.char.name, 'bürger', 'Antrag zurückgezogen',
        back > 0 and (U.money(back) .. ' wurden erstattet. Die Antragsgebühr ist nicht erstattbar.') or nil)
    IC.audit(ctx.char.name, 'bürger', 'Antrag zurückgezogen', a.caseNo, a.name)
    return ok({ refunded = back })
end

function A.objection(ctx, p)
    local a = ownApp(ctx, p.id)
    if not a or a.status ~= 'abgelehnt' then return fail('Gegen diesen Antrag ist kein Einspruch möglich.') end
    if IC.now() > (a.objectionUntil or 0) then return fail('Die Einspruchsfrist von ' .. Config.Rules.objectionHours .. ' Stunden ist abgelaufen.') end
    local text = U.trim(p.text or '')
    if U.ulen(text) < 20 then return fail('Bitte den Einspruch mit mindestens 20 Zeichen begründen.') end
    text = U.ucut(text, 1000)
    -- Wer abgelehnt hat, ist im Einspruchsverfahren befangen und darf nicht selbst darüber entscheiden
    if a.decision and a.decision.byId then
        a.conflicts = a.conflicts or {}
        if not U.contains(a.conflicts, a.decision.byId) then a.conflicts[#a.conflicts + 1] = a.decision.byId end
    end
    A.setStatus(a, 'einspruch', ctx.char.name, 'bürger', 'Einspruch eingelegt', text)
    IC.audit(ctx.char.name, 'bürger', 'Einspruch', a.caseNo, U.ucut(text, 80))
    return ok()
end

-- ---------------------------------------------------------------------------
-- Vorprüfung (Beamte)
-- ---------------------------------------------------------------------------
function A.needOnDuty(ctx)
    local d = IC.duty.get(ctx.off.id)
    if not d or d.state ~= 'on' then return fail('Sie müssen im Dienst sein, um diese Aktion auszuführen.') end
end

function A.needRank(ctx, rank)
    if not R.rankAtLeast(ctx.off.rank, rank) then
        return fail('Dafür ist mindestens der Rang „' .. Config.RankLabels[rank] .. '“ erforderlich.')
    end
end

function A.review(ctx, p)
    local e = A.needOnDuty(ctx) or A.needRank(ctx, 'sachbearbeiter')
    if e then return e end
    local a = S.get('applications', tostring(p.id or ''))
    if not a or a.status ~= 'eingereicht' then return fail('Dieser Antrag wartet nicht auf die Vorprüfung.') end
    if A.conflicted(a, ctx.off.id) then return fail('Sie sind befangen und dürfen diesen Antrag nicht bearbeiten.') end
    local msg = U.ucut(U.trim(p.message or ''), 1000)
    local name = ctx.off.name
    if p.result == 'ok' then
        a.vorpruefungAt = IC.now()
        A.setStatus(a, 'vorpruefung_ok', name, 'beamter', 'Vorprüfung bestanden', msg ~= '' and msg or nil)
        IC.notify(a.applicant.charId, 'Die Vorprüfung für „' .. a.name .. '“ ist bestanden. Sie können jetzt einen Termin im Bürgeramt buchen.', 'ok')
    elseif p.result == 'nachbesserung' then
        if U.ulen(msg) < 10 then return fail('Bitte beschreiben, was nachgebessert werden muss (mindestens 10 Zeichen).') end
        a.remark = msg
        A.setStatus(a, 'nachbesserung', name, 'beamter', 'Nachbesserung erforderlich', msg)
        IC.notify(a.applicant.charId, 'Für „' .. a.name .. '“ ist eine Nachbesserung erforderlich.', 'warn')
    elseif p.result == 'abgelehnt' then
        if U.ulen(msg) < 10 then return fail('Eine Ablehnung braucht eine Begründung (mindestens 10 Zeichen).') end
        a.objectionUntil = IC.now() + Config.Rules.objectionHours * R.HOUR
        a.decision = { decision = 'abgelehnt', reason = msg, by = name, byId = ctx.off.id, at = IC.now(), conditions = {} }
        A.refund(a)
        A.setStatus(a, 'abgelehnt', name, 'beamter', 'Antrag abgelehnt', msg)
        IC.notify(a.applicant.charId, 'Der Antrag „' .. a.name .. '“ wurde abgelehnt. Einspruch ist ' .. Config.Rules.objectionHours .. ' Stunden lang möglich.', 'bad')
    else
        return fail('Unbekanntes Ergebnis.')
    end
    IC.audit(name, 'beamter', 'Vorprüfung', a.caseNo, tostring(p.result) .. (msg ~= '' and (': ' .. U.ucut(msg, 60)) or ''))
    return ok()
end

function A.conflictReport(ctx, p)
    local a = S.get('applications', tostring(p.id or ''))
    if not a then return fail('Antrag nicht gefunden.') end
    a.conflicts = a.conflicts or {}
    if not U.contains(a.conflicts, ctx.off.id) then a.conflicts[#a.conflicts + 1] = ctx.off.id end
    S.put('applications', a)
    IC.audit(ctx.off.name, 'beamter', 'Befangenheit gemeldet', a.caseNo, 'Antrag wird an einen anderen Beamten übergeben')
    return ok()
end

-- ---------------------------------------------------------------------------
-- Fristen (wird regelmäßig aufgerufen)
-- ---------------------------------------------------------------------------
function A.tick()
    local now = IC.now()
    local r = Config.Rules
    for _, a in ipairs(S.list('applications')) do
        if a.status == 'nachbesserung' and now > A.lastTs(a) + r.fixDays * R.DAY then
            A.refund(a)
            A.setStatus(a, 'abgelaufen', 'System', 'system', 'Frist zur Nachbesserung abgelaufen')
        elseif a.status == 'vorpruefung_ok' and now > (a.vorpruefungAt or A.lastTs(a)) + r.bookDays * R.DAY then
            A.refund(a)
            A.setStatus(a, 'abgelaufen', 'System', 'system', 'Kein Termin innerhalb von ' .. r.bookDays .. ' Tagen gebucht')
        elseif not a.escalationSent and A.waitingSince(a) and now - A.waitingSince(a) > r.escalateHours * R.HOUR then
            -- Notfallregel: Der Staff erfährt es einmal per Webhook (im Panel steht der Antrag unter "Eskalationen")
            a.escalationSent = true
            S.put('applications', a)
            IC.webhook('staff', 'Eskalation: ' .. a.caseNo, a.name .. ' wartet seit über ' .. r.escalateHours .. ' Stunden auf einen Termin (Notfallregel).')
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bestehende Eintragungen
-- ---------------------------------------------------------------------------
local function ownEntity(ctx, id)
    local e = id and S.get('entities', tostring(id)) or nil
    if e and IC.register.leaderOf(e, ctx.char.charId) then return e end
end

function A.entityChange(ctx, p)
    local e = ownEntity(ctx, p.id)
    if not e then return fail('Eintrag nicht gefunden.') end
    if e.status == 'aufgeloest' or e.status == 'gesperrt' then return fail('Dieser Eintrag lässt sich nicht ändern.') end
    local fee = Config.Rules.feeChange
    local change
    if p.type == 'name' then
        local nc = R.nameCheck(U.ucut(tostring(p.value or ''), 120), e.legalForm, A.nameCtx(nil, e.id))
        if not nc.ok then return fail(R.firstError(nc.issues)) end
        change = { type = 'name', value = nc.display, at = IC.now() }
    elseif p.type == 'sitz' then
        local v = U.ucut(U.trim(p.value or ''), 60)
        if U.ulen(v) < 3 then return fail('Bitte einen gültigen neuen Sitz angeben.') end
        change = { type = 'sitz', value = v, at = IC.now() }
    else
        return fail('Unbekannte Änderung.')
    end
    if not IC.pay.charge(ctx.src, fee, 'Gewerbeamt: Änderung ' .. e.regNo) then return fail('Der Kontostand reicht nicht aus. Benötigt: ' .. U.money(fee) .. '.') end
    IC.pay.toTreasury(fee, 'Änderungsgebühr ' .. e.regNo)
    e.pendingChange = change
    S.put('entities', e)
    IC.audit(ctx.char.name, 'bürger', 'Änderungsantrag', e.regNo, change.type .. ': ' .. change.value)
    return ok({ fee = fee })
end

function A.entityDissolve(ctx, p)
    local e = ownEntity(ctx, p.id)
    if not e then return fail('Eintrag nicht gefunden.') end
    if e.status == 'aufgeloest' then return fail('Dieser Eintrag ist bereits aufgelöst.') end
    IC.register.dissolve(e, ctx.char.name)
    IC.audit(ctx.char.name, 'bürger', 'Auflösung', e.regNo, e.name)
    return ok()
end

function A.entityDuplicate(ctx, p)
    local e = ownEntity(ctx, p.id)
    if not e then return fail('Eintrag nicht gefunden.') end
    local fee = Config.Rules.feeDuplicate
    if not IC.pay.charge(ctx.src, fee, 'Gewerbeamt: Duplikat ' .. e.regNo) then return fail('Der Kontostand reicht nicht aus. Benötigt: ' .. U.money(fee) .. '.') end
    IC.pay.toTreasury(fee, 'Duplikat ' .. e.regNo)
    IC.bridge.giveCertificate(ctx.src, e)
    IC.audit(ctx.char.name, 'bürger', 'Duplikat Gewerbeschein', e.regNo, e.name)
    return ok({ fee = fee })
end

function A.legacyConfirm(ctx, p)
    local e = ownEntity(ctx, p.id)
    if not e or not e.legacy then return fail('Kein Bestandsschutz-Eintrag.') end
    e.legacyConfirmed = true
    S.put('entities', e)
    if e.legacyRested then
        e.legacyRested = nil
        IC.register.setStatus(e, 'aktiv', ctx.char.name, 'Bestandsbestätigung nachgeholt')
    end
    IC.audit(ctx.char.name, 'bürger', 'Bestandsbestätigung', e.regNo, e.name)
    return ok()
end

function A.registerSearch(ctx, p)
    local q = U.normName(p.q or '')
    local raw = tostring(p.q or ''):lower():gsub('%s', '')
    local rows = {}
    for _, e in ipairs(S.list('entities')) do
        local match = true
        if p.kind and p.kind ~= '' and e.kind ~= p.kind then match = false end
        if p.branch and p.branch ~= '' and e.branch ~= p.branch then match = false end
        if p.status and p.status ~= '' and e.status ~= p.status then match = false end
        if match and q ~= '' then
            match = U.normName(e.name):find(q, 1, true) ~= nil
                or e.regNo:lower():gsub('%s', ''):find(raw, 1, true) ~= nil
                or U.normName(e.owner):find(q, 1, true) ~= nil
        end
        if match then rows[#rows + 1] = IC.register.publicView(e) end
    end
    return ok({ rows = U.sortBy(rows, function(r) return r.name:lower() end) })
end
