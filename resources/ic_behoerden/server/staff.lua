--[[
    ic_behoerden · Staff (OOC)
    Schlussprüfung, Entscheidung nach Aktenlage, Eingriff in das Register, Kapazitäten, Sperrliste, Einstellungen und Kennzahlen.
]]

IC = IC or {}
local R, U, S = IC.rules, IC.util, IC.store
local ok, fail = IC.ok, IC.fail
local A, D = IC.apps, IC.duty
local Sf = {}
IC.staff = Sf

local function actor(ctx) return 'Staff (' .. (ctx.staffName or '?') .. ')' end

-- Schlussprüfung: freigeben und eintragen oder zurückweisen
function Sf.gate(ctx, p)
    local a = S.get('applications', tostring(p.id or ''))
    if not a or a.status ~= 'staff_pruefung' then return fail('Dieser Antrag wartet nicht auf die Schlussprüfung.') end
    if p.decision == 'freigeben' then
        if a.ooc and a.ooc.category == 'untergrund' then
            local cap = IC.undergroundCap()
            if cap.used >= cap.max then return fail('Alle Untergrund-Plätze sind belegt. Erhöhen Sie die Kapazität oder weisen Sie den Antrag zurück.') end
        end
        IC.register.create(a, 'Registerführung')
        IC.audit(actor(ctx), 'staff', 'Freigabe', a.caseNo, a.name)
        return ok()
    end
    local note = U.ucut(U.trim(p.note or ''), 500)
    if U.ulen(note) < 10 then return fail('Bitte einen Grund angeben (mindestens 10 Zeichen).') end
    a.remark = 'Hinweis der Registerführung: ' .. note
    A.setStatus(a, 'nachbesserung', 'Registerführung', 'staff', 'Schlussprüfung nicht bestanden', note)
    IC.notify(a.applicant.charId, 'Für „' .. a.name .. '“ ist eine Nachbesserung erforderlich.', 'warn')
    IC.audit(actor(ctx), 'staff', 'Zurückgewiesen', a.caseNo, U.ucut(note, 60))
    return ok()
end

-- Notfallregel: Entscheidung nach Aktenlage für Anträge, die zu lange auf einen Termin warten (nach der Vorprüfung oder nach einem Einspruch)
function Sf.written(ctx, p)
    if not IC.settings.get('writtenProcedure') then return fail('Das schriftliche Verfahren ist abgeschaltet.') end
    local a = S.get('applications', tostring(p.id or ''))
    local since = a and A.waitingSince(a)
    if not since then return fail('Dieser Antrag ist nicht für das schriftliche Verfahren geeignet.') end
    if IC.now() - since <= Config.Rules.escalateHours * R.HOUR then
        return fail('Dieser Antrag ist noch nicht überfällig (Frist: ' .. Config.Rules.escalateHours .. ' Stunden).')
    end
    local objection = a.status == 'einspruch'
    local reason = U.ucut(U.trim(p.reason or ''), 1000)
    if U.ulen(reason) < 10 then return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).') end
    if p.decision ~= 'genehmigt' and p.decision ~= 'abgelehnt' then return fail('Bitte genehmigen oder ablehnen.') end
    a.decision = { decision = p.decision, reason = reason, by = 'Behörde (nach Aktenlage)', at = IC.now(), conditions = {} }
    if p.decision == 'genehmigt' then
        A.pushEvent(a, 'termin_laeuft', 'Behörde', 'staff', 'Entscheidung nach Aktenlage: genehmigt', reason)
        if R.staffGateNeeded(a) then
            A.setStatus(a, 'staff_pruefung', 'Registerführung', 'system', 'Schlussprüfung durch die Registerführung')
        else
            IC.register.create(a, 'Behörde')
        end
    else
        -- Nach einem Einspruch ist die Ablehnung endgültig
        a.objectionUntil = objection and 0 or (IC.now() + Config.Rules.objectionHours * R.HOUR)
        A.refund(a)
        A.setStatus(a, 'abgelehnt', 'Behörde', 'staff', 'Entscheidung nach Aktenlage: abgelehnt', reason)
    end
    IC.audit(actor(ctx), 'staff', 'Entscheidung nach Aktenlage', a.caseNo, p.decision .. ': ' .. U.ucut(reason, 50))
    for _, f in ipairs(a.founders) do
        IC.notify(f.charId, 'Entscheidung nach Aktenlage zu „' .. a.name .. '“: ' .. (p.decision == 'genehmigt' and 'Genehmigt' or 'Abgelehnt') .. '.', p.decision == 'genehmigt' and 'ok' or 'bad')
    end
    return ok()
end

function Sf.cap(ctx, p)
    local key = tostring(p.key or '')
    local label = key == 'untergrund' and 'Untergrund-Fraktionen' or (R.branch(key) or {}).label
    if not label then return fail('Branche nicht gefunden.') end
    local v = IC.setBranchCap(key, p.value)
    IC.audit(actor(ctx), 'staff', 'Kapazität', label, tostring(v))
    return ok()
end

function Sf.blacklistAdd(ctx, p)
    local term = U.ucut(U.trim(p.term or ''), 60)
    if U.ulen(term) < 3 then return fail('Der Begriff braucht mindestens 3 Zeichen.') end
    local n = U.normName(term)
    for _, b in ipairs(S.list('blacklist')) do
        if U.normName(b.term) == n then return fail('Dieser Begriff ist bereits gesperrt.') end
    end
    local reason = U.ucut(U.trim(p.reason or ''), 80)
    S.put('blacklist', { id = 'B-' .. IC.nextSeq('black', 0), term = term, reason = reason ~= '' and reason or 'Staff' })
    IC.audit(actor(ctx), 'staff', 'Sperrliste', term, 'hinzugefügt')
    return ok()
end

function Sf.blacklistRemove(ctx, p)
    local b = S.get('blacklist', tostring(p.id or ''))
    if not b then return fail('Eintrag nicht gefunden.') end
    IC.audit(actor(ctx), 'staff', 'Sperrliste', b.term, 'entfernt')
    S.del('blacklist', b.id)
    return ok()
end

local SETTING_LABEL = {
    requireOfficials = 'Beamtenpflicht für Termine',
    writtenProcedure = 'Schriftliches Verfahren (Notfallregel)',
    undergroundViaPortal = 'Untergrund-Fraktionen über das Portal',
    fourEyes = 'Vier-Augen-Prinzip für Organisationen',
}

function Sf.setting(ctx, p)
    local key = tostring(p.key or '')
    if key == 'fourEyes' then return fail('Das Vier-Augen-Prinzip kommt in Phase 2.') end
    if not IC.settings.set(key, p.value == true) then return fail('Unbekannte Einstellung.') end
    IC.audit(actor(ctx), 'staff', 'Einstellung', SETTING_LABEL[key] or key, p.value == true and 'eingeschaltet' or 'ausgeschaltet')
    return ok()
end

-- Eingriff des Staffs in das Register: Status eines Eintrags setzen (zum Beispiel sperren bei Regelverstößen). Immer mit Begründung.
-- Die Gründer erfahren IC nur, dass die Registerführung gehandelt hat.
local ENTITY_STATUS = { aktiv = 'wieder aktiv gesetzt', ruhend = 'ruhend gestellt', gesperrt = 'gesperrt', aufgeloest = 'aufgelöst' }

function Sf.entityStatus(ctx, p)
    local e = S.get('entities', tostring(p.id or ''))
    if not e then return fail('Eintrag nicht gefunden.') end
    local status = tostring(p.status or '')
    if not ENTITY_STATUS[status] then return fail('Unbekannter Status.') end
    if e.status == 'aufgeloest' then return fail('Ein aufgelöster Eintrag lässt sich nicht mehr ändern.') end
    if e.status == status then return fail('Der Eintrag hat diesen Status bereits.') end
    local reason = U.ucut(U.trim(p.reason or ''), 300)
    if U.ulen(reason) < 10 then return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).') end
    if status == 'aufgeloest' then e.dissolvedAt = IC.now() end
    IC.register.setStatus(e, status, 'Registerführung', reason)
    IC.audit(actor(ctx), 'staff', 'Eingriff Register', e.regNo, status .. ': ' .. U.ucut(reason, 60))
    for _, m in ipairs(e.members or {}) do
        if IC.register.isLeader(m.role) then
            IC.notify(m.charId, 'Die Registerführung hat „' .. e.name .. '“ ' .. ENTITY_STATUS[status] .. '. Begründung: ' .. reason, status == 'aktiv' and 'ok' or 'warn')
        end
    end
    return ok()
end

-- Hinweise für die Schlussprüfung. Nur, was sich aus den Daten ergibt.
function Sf.gateHints(a)
    local hints = {}
    -- Länge und Zeichen waren schon beim Einreichen geprüft (der Anzeigename enthält außerdem den Rechtsformzusatz). Wichtig ist, ob sich seither etwas geändert hat.
    local nc = R.nameCheck(a.name, a.legalForm, A.nameCtx(a.id))
    local problem
    for _, i in ipairs(nc.issues) do
        if i.level == 'error' and (i.code == 'blacklist' or i.code == 'taken' or i.code == 'reserved' or i.code == 'similar') then problem = i.text break end
    end
    hints[#hints + 1] = problem and { ok = false, text = problem } or { ok = true, text = 'Der Name ist frei und steht nicht auf der Sperrliste.' }

    local lines = {}
    for _, f in ipairs(a.founders or {}) do
        local others = S.list('entities', function(e)
            if e.status == 'aufgeloest' then return false end
            for _, m in ipairs(e.members or {}) do if m.charId == f.charId then return true end end
            return false
        end)
        if #others > 0 then lines[#lines + 1] = f.name .. ': ' .. table.concat(U.map(U.sortBy(others, function(e) return e.regNo end), function(e) return e.regNo end), ', ') end
    end
    hints[#hints + 1] = #lines == 0 and { ok = true, text = 'Die Gründer sind an keinem anderen aktiven Eintrag beteiligt.' }
        or { ok = false, text = 'Beteiligungen an anderen Einträgen: ' .. table.concat(lines, '; ') .. '.' }

    local f = R.form(a.legalForm)
    local n = #(a.founders or {})
    hints[#hints + 1] = { ok = n >= f.minFounders, text = ('%d Gründungsmitglieder, erforderlich sind mindestens %d.'):format(n, f.minFounders) }
    return hints
end

-- Startet die Sperrliste mit den Begriffen aus der Config. Läuft nur einmal: Wer die Liste später leert, bekommt sie nach einem Neustart nicht zurück.
function Sf.seed()
    if S.get('settings', 'seeded') or S.count('blacklist') > 0 then return end
    for _, b in ipairs(Config.Blacklist or {}) do
        S.put('blacklist', { id = 'B-' .. IC.nextSeq('black', 0), term = b[1], reason = b[2] })
    end
    S.put('settings', { id = 'seeded', value = true })
end

-- Beamten-Verfügbarkeit: zählt Sekunden mit mindestens einem Beamten im Dienst, je Tag (für die Kennzahl)
function Sf.trackDuty(seconds)
    if #D.list() == 0 then return end
    local row = S.get('settings', 'dutyStats') or { id = 'dutyStats', value = {} }
    local day = os.date('%Y-%m-%d', IC.now() // 1000)
    row.value[day] = (row.value[day] or 0) + seconds
    local keys = U.keys(row.value)
    while #keys > 14 do row.value[table.remove(keys, 1)] = nil end
    S.put('settings', row)
end

function Sf.availabilityHours()
    local row = S.get('settings', 'dutyStats')
    if not row then return 0 end
    local sum, n = 0, 0
    for _, secs in pairs(row.value) do sum = sum + secs; n = n + 1 end
    return n > 0 and math.floor(sum / n / 360) / 10 or 0
end

function Sf.overview()
    local now = IC.now()
    local apps = S.list('applications')
    local decided, rejected, done, days = 0, 0, 0, 0
    for _, a in ipairs(apps) do
        if a.status == 'genehmigt' or a.status == 'abgelehnt' then
            decided = decided + 1
            if a.status == 'abgelehnt' then rejected = rejected + 1 end
        end
        if a.status == 'genehmigt' and a.submittedAt then done = done + 1; days = days + (A.lastTs(a) - a.submittedAt) / R.DAY end
    end
    local esc = U.sortBy(U.filter(apps, function(a) local since = A.waitingSince(a); return since ~= nil and now - since > Config.Rules.escalateHours * R.HOUR end), function(a) return A.waitingSince(a) end)
    local gate = U.sortBy(U.filter(apps, function(a) return a.status == 'staff_pruefung' end), function(a) return A.lastTs(a) end)
    local finished = S.list('appointments', function(a) return a.status == 'abgeschlossen' or a.status == 'nicht_erschienen' or a.status == 'beamter_ausfall' end)
    local noShow, outage = 0, 0
    for _, a in ipairs(finished) do
        if a.status == 'nicht_erschienen' then noShow = noShow + 1 end
        if a.status == 'beamter_ausfall' then outage = outage + 1 end
    end
    local function pct(n, of) return of > 0 and U.round(n / of * 100) or 0 end
    local caps = {}
    for _, b in ipairs(Config.Branches) do caps[#caps + 1] = { key = b.key, label = b.label, used = IC.register.branchUsed(b.key), cap = IC.branchCap(b) } end
    local blacklist = U.sortBy(S.list('blacklist'), function(b) return b.term end)
    local open = 0
    for _, a in ipairs(apps) do if R.isOpenApp(a) then open = open + 1 end end
    return {
        kpi = {
            open = open, gate = #gate, escalations = #esc, onDuty = #D.list(), treasury = IC.ledgerGet('treasury'),
            rejectionRate = pct(rejected, decided), noShowRate = pct(noShow, #finished), outageRate = pct(outage, #finished),
            throughputDays = done > 0 and math.floor(days / done * 10 + 0.5) / 10 or 0, availabilityHours = Sf.availabilityHours(),
        },
        gate = U.map(gate, function(a) local c = U.deepcopy(a); c.hints = Sf.gateHints(a); return c end), escalations = U.map(esc, function(a) local c = IC.register.stripOoc(a); c.waitingSince = A.waitingSince(a); return c end),
        entities = U.map(U.sortBy(S.list('entities'), function(e) return e.name:lower() end), U.deepcopy),
        caps = caps, undergroundCap = IC.undergroundCap(), blacklist = blacklist, settings = IC.settings.all(),
        audit = (function() local out = {} for i = 1, math.min(80, #IC.auditLog) do out[i] = IC.auditLog[i] end return out end)(),
        -- nur, was die Übersicht zum Zählen braucht (die Listen für Schlussprüfung und Eskalationen stehen oben vollständig)
        applicationsAll = U.map(apps, function(a) return { id = a.id, caseNo = a.caseNo, name = a.name, kind = a.kind, status = a.status } end),
    }
end
