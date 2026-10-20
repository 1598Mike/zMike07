local T, H = ...
local R, U, S = IC.rules, IC.util, IC.store
local MIN, HOUR, DAY = H.MIN, H.HOUR, H.DAY

-- Figuren ------------------------------------------------------------------------
local LENA, TOM, MARCO, ANNA, KELLER, YILMAZ, NOVAK = 1, 2, 3, 4, 10, 11, 12

local function cast()
    H.reset()
    H.player(LENA, { charId = 'c-lena', name = 'Lena Brandt', age = 29, playHours = 63, bank = 184250 })
    H.player(TOM, { charId = 'c-tom', name = 'Tom Becker', age = 31, playHours = 48 })
    H.player(MARCO, { charId = 'c-marco', name = 'Marco Rossi', age = 34, playHours = 120 })
    H.player(ANNA, { charId = 'c-anna', name = 'Anna Kowalski', age = 27, playHours = 6 })       -- zu wenig Spielzeit
    -- Beamte stehen im Rathaus (area 2), die Gründer davor (area 1): "in der Nähe" betrifft nur Gründer
    H.player(KELLER, { charId = 'c-keller', name = 'Dr. Keller', rank = 'amtsleiter', bank = 5000, area = 2 })
    H.player(YILMAZ, { charId = 'c-yilmaz', name = 'Yilmaz', rank = 'sachbearbeiter', bank = 5000, area = 2 })
    H.player(NOVAK, { charId = 'c-novak', name = 'Novak', rank = 'anwaerter', bank = 5000, area = 2 })
end

local function duty(src, state, desk) return T.succeeds(H.call(src, 'beamte', 'dutySet', { state = state or 'on', desk = desk or 1 })) end

local function draftEinzel(name, extra)
    local d = {
        kind = 'unternehmen', legalForm = 'einzel', branch = 'handwerk', name = name or 'Mustermann Bau',
        founders = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber', share = 100 } },
        property = { mode = 'mobil' },
        concept = { idea = 'Wir übernehmen kleine Bau- und Renovierungsarbeiten für Privatkunden und Gewerbe in Los Santos. Schwerpunkt sind Trockenbau und Malerarbeiten.' },
    }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end

local function submit(src, draft)
    return H.call(src, 'gewerbeamt', 'appSubmit', { draft = draft })
end

local function appById(id) return S.get('applications', id) end

-- Bringt einen Antrag bis "Vorprüfung bestanden"
local function toPreChecked(src, draft)
    local r = T.succeeds(submit(src, draft), 'Einreichen')
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok' }), 'Vorprüfung')
    return r
end

-- Bucht den ersten freien Live-Termin und gibt die Termin-ID zurück
local function bookFirst(src, typeId, appId, attendees)
    local sl = T.succeeds(H.call(src, 'buergeramt', 'slotsList', { typeId = typeId, dayOffset = 0 }))
    local start
    for _, x in ipairs(sl.slots) do if x.free > 0 then start = x.start; break end end
    T.ok(start, 'es gibt einen freien Slot')
    local r = H.call(src, 'buergeramt', 'apptBook', { typeId = typeId, start = start, applicationId = appId, attendees = attendees or { H.bridge.getChar(src).charId } })
    return r, start
end

local function checkinAt(ap, src)
    H.clock = ap.start - 2 * MIN
    return H.call(src, 'buergeramt', 'apptCheckin', { id = ap.id })
end

-- ============================================================================ Kernablauf
T.test('Ablauf: Antrag, Vorprüfung, Termin, Check-in, Entscheidung, Eintragung', function()
    cast()
    duty(KELLER); duty(YILMAZ, 'on', 2)
    local before = H.bridge.players[LENA].bank
    local r = T.succeeds(submit(LENA, draftEinzel()))
    T.ok(r.caseNo:match('^GA%-%d%d%d%d%-0001$'), 'Aktenzeichen ' .. r.caseNo)
    T.eq(r.paid, 1000); T.eq(H.bridge.players[LENA].bank, before - 1000, 'Konto belastet')
    T.eq(IC.ledgerGet('escrow'), 750, 'Eintragungsgebühr liegt in Verwahrung')
    T.eq(IC.ledgerGet('treasury'), 250, 'Antragsgebühr bei der Stadtkasse')
    local app = appById(r.id)
    T.eq(app.status, 'eingereicht'); T.eq(app.name, 'Mustermann Bau'); T.eq(app.founders[1].consent, 'self')

    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok', message = 'Passt.' }))
    T.eq(app.status, 'vorpruefung_ok')
    T.ok(H.lastNotice(LENA, 'Vorprüfung'), 'Gründerin wurde benachrichtigt')

    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local ap = S.get('appointments', b.id)
    T.eq(ap.status, 'gebucht'); T.eq(app.status, 'termin_gebucht'); T.eq(app.restoreStatus, 'vorpruefung_ok')

    T.fails(H.call(LENA, 'buergeramt', 'apptCheckin', { id = ap.id }), 'Einchecken ist ab 10 Minuten', 'zu früh')
    T.succeeds(checkinAt(ap, LENA))
    T.eq(ap.status, 'eingecheckt')

    T.succeeds(H.call(KELLER, 'beamte', 'apptCall', { id = ap.id }))
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
    T.eq(app.status, 'termin_laeuft')
    local all = {}
    for _, i in ipairs(Config.Checklists.vorstellung_unternehmen) do all[i.key] = true end
    local pay = H.bridge.players[KELLER].bank
    local d = T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = all }))
    T.eq(d.outcome, 'eingetragen'); T.ok(d.regNo:match('^HRA 1%d%d%d$'), 'Registernummer ' .. tostring(d.regNo))
    T.eq(app.status, 'genehmigt')
    T.eq(H.bridge.players[KELLER].bank, pay + 150, 'Terminpauschale für den Beamten')
    T.eq(IC.ledgerGet('escrow'), 0, 'Verwahrung aufgelöst'); T.eq(IC.ledgerGet('treasury'), 250 + 750 - 150, 'Gebühren abzüglich Pauschale')
    local e = S.get('entities', app.entityId)
    T.eq(e.status, 'aktiv'); T.eq(e.hq, 'Ohne festen Standort'); T.eq(e.members[1].role, 'inhaber')
    T.eq(#H.bridge.certificates, 1, 'Gewerbeschein wurde ausgestellt')
    T.eq(H.bridge.hooks[1][1], 'onApproved', 'Hook wurde aufgerufen')
    T.ok(H.lastNotice(LENA, 'ist eingetragen'))
end)

T.test('bootstrap liefert die Daten für jede Anwendung', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel())
    local c = T.succeeds(H.call(LENA, 'gewerbeamt', 'bootstrap', { app = 'gewerbeamt' }))
    T.eq(c.me.name, 'Lena Brandt'); T.eq(c.me.bank, 183250); T.eq(#c.myApplications, 1); T.eq(c.myApplications[1].status, 'vorpruefung_ok')
    T.eq(c.duty.count, 1); T.eq(#c.nearby, 3, 'Tom, Marco und Anna stehen in der Nähe')
    local anna
    for _, x in ipairs(c.nearby) do if x.name == 'Anna Kowalski' then anna = x end end
    T.notok(anna.elig.ok, 'Anna hat zu wenig Spielzeit')
    T.eq(#c.config.branches, 12); T.ok(c.eligibility.unternehmen.ok)
    T.fails(H.call(LENA, 'gewerbeamt', 'bootstrap', { app = 'staff' }), 'nicht geöffnet')
    T.fails(H.call(LENA, 'gewerbeamt', 'bootstrap', { app = 'beamte' }), 'nicht geöffnet')
    T.succeeds(H.call(LENA, 'gewerbeamt', 'bootstrap', { app = 'buergeramt' }), 'Gewerbeamt und Bürgeramt sind ein Fenster')
    T.fails(H.call(KELLER, 'beamte', 'bootstrap', { app = 'gewerbeamt' }), 'nicht geöffnet')
    local o = T.succeeds(H.call(KELLER, 'beamte', 'bootstrap', { app = 'beamte' }))
    T.eq(o.official.rank, 'amtsleiter'); T.eq(o.official.onDuty, true); T.eq(#o.officialApps, 1)
    T.eq(o.officialApps[1].ooc, nil, 'Beamte sehen keine OOC-Angaben')
    local s = T.succeeds(H.staff('bootstrap', { app = 'staff' }))
    T.ok(s.staff ~= nil and s.staff.kpi ~= nil)
end)

-- ============================================================================ Kernregel: kein Beamter, kein Termin
T.test('Gating: ohne Beamte im Dienst gibt es keine Termine, Buchung und Wartenummer scheitern', function()
    cast()
    local r = T.succeeds(submit(LENA, draftEinzel()))
    -- Vorprüfung geht nur mit Beamten im Dienst, danach gehen sie wieder
    duty(KELLER)
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok' }))
    duty(KELLER, 'off')
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'vorstellung_unternehmen', dayOffset = 0 }))
    T.eq(#sl.slots, 0); T.eq(sl.eligible, 0); T.eq(sl.onDuty, 0)
    for _, d in ipairs(sl.days) do T.eq(d.free, 0, 'auch an keinem der nächsten Tage') end
    local t0 = H.clock + 30 * MIN
    T.fails(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'vorstellung_unternehmen', start = t0 - (t0 % (15 * MIN)) + 15 * MIN, applicationId = r.id }), 'kein Beamter verfügbar')
    T.fails(H.call(LENA, 'buergeramt', 'queueTake', {}), 'kein Beamter im Dienst')
    T.eq(IC.appt.nextFree(), nil)
    -- Ein Beamter geht in den Dienst: Termine sind sofort buchbar
    duty(YILMAZ, 'on', 2)
    sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'vorstellung_unternehmen', dayOffset = 0 }))
    T.ok(#sl.slots > 0 and sl.eligible == 1)
    T.ok(IC.appt.nextFree() ~= nil)
end)

T.test('Gating: Pause zählt nicht als Dienst, ein Anwärter allein ermöglicht nur Beratung', function()
    cast()
    duty(KELLER, 'pause')
    T.eq(#IC.duty.list(), 0)
    duty(NOVAK, 'on', 3)
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'beratung', dayOffset = 0 }))
    T.ok(#sl.slots > 0, 'Beratung geht mit einem Anwärter')
    sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'vorstellung_unternehmen', dayOffset = 0 }))
    T.eq(#sl.slots, 0, 'Vorstellung braucht mindestens einen Sachbearbeiter')
end)

T.test('Gating: Sprechzeiten machen spätere Termine buchbar, auch ohne Dienst', function()
    cast()
    duty(YILMAZ, 'on', 2)
    local tomorrow = U.startOfDay(H.clock + DAY) + 18 * HOUR
    T.succeeds(H.call(YILMAZ, 'beamte', 'hoursCreate', { start = tomorrow, ['end'] = tomorrow + 2 * HOUR }))
    duty(YILMAZ, 'off')
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'beratung', dayOffset = 1 }))
    T.ok(#sl.slots > 0); T.eq(sl.slots[1].source, 'plan'); T.eq(sl.slots[1].start, tomorrow)
    local b = T.succeeds(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'beratung', start = tomorrow }))
    -- Doppelbuchung desselben einzigen Beamten wird verhindert
    T.fails(H.call(MARCO, 'buergeramt', 'apptBook', { typeId = 'beratung', start = tomorrow }), 'schon vergeben')
    -- Sprechzeit liegt in der Vergangenheit oder zu weit in der Zukunft
    duty(YILMAZ, 'on', 2)
    T.fails(H.call(YILMAZ, 'beamte', 'hoursCreate', { start = H.clock - HOUR, ['end'] = H.clock + HOUR }), 'in der Zukunft')
    T.fails(H.call(YILMAZ, 'beamte', 'hoursCreate', { start = H.clock + 9 * DAY, ['end'] = H.clock + 9 * DAY + HOUR }), 'Tage im Voraus')
    T.fails(H.call(YILMAZ, 'beamte', 'hoursCreate', { start = tomorrow + HOUR, ['end'] = tomorrow + 3 * HOUR }), 'bereits eine Sprechzeit')
    T.fails(H.call(YILMAZ, 'beamte', 'hoursCreate', { start = tomorrow + DAY, ['end'] = tomorrow + DAY + 10 * MIN }), 'mindestens 30 Minuten')
end)

T.test('Gating: fällt zum Terminbeginn der Beamte aus, gibt es Vorrang und keinen Strike', function()
    cast()
    duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel())
    local b, start = bookFirst(LENA, 'vorstellung_unternehmen', r.id)
    T.succeeds(b)
    duty(KELLER, 'off')
    H.clock = start + 11 * MIN
    IC.tick()
    local ap = S.get('appointments', b.id)
    T.eq(ap.status, 'beamter_ausfall'); T.eq(appById(r.id).status, 'vorpruefung_ok'); T.eq(appById(r.id).priority, true)
    T.eq(#IC.strikes.active('c-lena'), 0, 'kein Strike für die Gründerin')
    T.ok(H.lastNotice(LENA, 'ausgefallen'))
end)

T.test('Termine: Absage, kurzfristige Absage zählt als Strike, drei Strikes sperren', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel())
    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local ap = S.get('appointments', b.id)
    H.clock = ap.start - 60 * MIN
    local c = T.succeeds(H.call(LENA, 'buergeramt', 'apptCancel', { id = ap.id }))
    T.eq(c.strike, false); T.eq(appById(r.id).status, 'vorpruefung_ok')
    for i = 1, 3 do
        H.clock = H.clock + 5 * MIN
        local bk = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
        local x = S.get('appointments', bk.id)
        H.clock = x.start - 5 * MIN
        T.eq(T.succeeds(H.call(LENA, 'buergeramt', 'apptCancel', { id = x.id })).strike, true, 'Absage ' .. i)
    end
    T.eq(#IC.strikes.active('c-lena'), 3)
    T.ok(IC.strikes.banUntil('c-lena') ~= nil)
    local sl = H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'vorstellung_unternehmen', start = H.clock + 20 * MIN, applicationId = r.id })
    T.fails(sl, 'gesperrt')
    H.advance(4 * DAY)
    T.eq(IC.strikes.banUntil('c-lena'), nil, 'nach drei Tagen ist die Sperre vorbei')
end)

T.test('Termine: nicht erschienen zählt als Strike, entschuldigt nicht; Limit offener Termine', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel())
    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local ap = S.get('appointments', b.id)
    T.fails(H.call(KELLER, 'beamte', 'apptNoShow', { id = ap.id }), 'Erst 10 Minuten nach Terminbeginn')
    H.clock = ap.start + 11 * MIN
    T.succeeds(H.call(KELLER, 'beamte', 'apptNoShow', { id = ap.id, excused = false }))
    T.eq(ap.status, 'nicht_erschienen'); T.eq(#IC.strikes.active('c-lena'), 1); T.eq(appById(r.id).status, 'vorpruefung_ok')
    -- zwei offene Termine sind das Limit
    local one = T.succeeds((bookFirst(LENA, 'beratung')))
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'beratung', dayOffset = 0 }))
    local starts = {}
    for _, x in ipairs(sl.slots) do if x.free > 0 then starts[#starts + 1] = x.start end end
    T.succeeds(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'beratung', start = starts[#starts] }))
    T.fails(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'beratung', start = starts[#starts - 1] }), 'bereits 2 offene Termine')
end)

T.test('Termine: Verschieben gibt den alten Slot frei und ist nur für eigene Termine möglich', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel())
    local b, start = bookFirst(LENA, 'vorstellung_unternehmen', r.id)
    T.succeeds(b)
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'vorstellung_unternehmen', dayOffset = 0, excludeApptId = b.id }))
    local newStart
    for _, x in ipairs(sl.slots) do if x.start >= start + 30 * MIN and x.free > 0 then newStart = x.start; break end end
    T.ok(newStart)
    T.fails(H.call(TOM, 'buergeramt', 'apptBook', { typeId = 'beratung', start = newStart, rescheduleId = b.id }), 'nicht verschieben')
    local nb = T.succeeds(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'vorstellung_unternehmen', start = newStart, applicationId = r.id, rescheduleId = b.id }))
    T.eq(S.get('appointments', b.id).status, 'abgesagt'); T.eq(S.get('appointments', nb.id).start, newStart); T.eq(appById(r.id).status, 'termin_gebucht')
    -- für denselben Antrag lässt sich kein zweiter Termin buchen
    T.fails(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'vorstellung_unternehmen', start = start, applicationId = r.id }), 'bereits ein Termin')
end)

T.test('Wartenummer: nur Beratung, eine je Person, Aufruf, Position und Aufräumen', function()
    cast(); duty(KELLER)
    T.fails(H.call(LENA, 'buergeramt', 'queueTake', { typeId = 'vorstellung_unternehmen' }), 'nur für die Beratung')
    local t1 = T.succeeds(H.call(LENA, 'buergeramt', 'queueTake', {}))
    T.eq(t1.no, 'A-001'); T.eq(t1.position, 1)
    T.eq(T.succeeds(H.call(TOM, 'buergeramt', 'queueTake', {})).position, 2)
    T.fails(H.call(LENA, 'buergeramt', 'queueTake', {}), 'bereits eine Wartenummer')
    local c = T.succeeds(H.call(LENA, 'buergeramt', 'bootstrap', { app = 'buergeramt' }))
    T.eq(c.myTicket.position, 1); T.eq(c.board.waiting, 2)
    T.succeeds(H.call(KELLER, 'beamte', 'queueNext', {}))
    c = T.succeeds(H.call(LENA, 'buergeramt', 'bootstrap', { app = 'buergeramt' }))
    T.eq(c.myTicket.called, true); T.eq(c.board.calling.no, 'A-001'); T.eq(c.board.waiting, 1)
    T.ok(H.lastNotice(LENA, 'wird aufgerufen'))
    T.succeeds(H.call(TOM, 'buergeramt', 'queueLeave', {}))
    T.fails(H.call(KELLER, 'beamte', 'queueNext', {}), 'leer')
end)

T.test('Benachrichtigung: wer sich vormerkt, erfährt vom Dienstbeginn (einmalig)', function()
    cast()
    T.succeeds(H.call(LENA, 'buergeramt', 'notifyOnDuty', { enabled = true }))
    duty(KELLER)
    T.ok(H.lastNotice(LENA, 'Beamter ist jetzt im Dienst'))
    T.eq(S.get('chars', 'c-lena').notifyOnDuty, false, 'einmalig')
    local n = #H.bridge.notices
    duty(KELLER, 'off'); duty(KELLER)
    T.eq(#H.bridge.notices, n, 'keine zweite Nachricht')
end)

-- ============================================================================ Organisation, Einladungen, Staff-Gate
local function orgDraft(name, ooc)
    return {
        kind = 'fraktion', legalForm = 'ev', name = name or 'Skater Club Mirror Park',
        founders = {
            { charId = 'c-lena', name = 'Lena Brandt', role = 'vorsitz' },
            { charId = 'c-tom', name = 'Tom Becker', role = 'stellv' },
            { charId = 'c-marco', name = 'Marco Rossi', role = 'mitglied' },
        },
        property = { mode = 'mobil' },
        statute = { purpose = 'Wir bringen Skater aus Mirror Park zusammen, organisieren Treffen, kleine Wettbewerbe und kümmern uns um einen sicheren Skatepark im Viertel.' },
        ooc = ooc or { category = 'untergrund', note = 'Tarnung für eine Gang', members = '10' },
    }
end

T.test('Einladungen: Zustimmung kommt nur vom Eingeladenen, nicht vom Client', function()
    cast()
    local d = orgDraft()
    for _, f in ipairs(d.founders) do f.consent = 'ok' end         -- ein Cheater behauptet Zustimmung
    local r = submit(LENA, d)
    T.fails(r, 'nicht vollständig'); local msgs = {}
    for _, e in ipairs(r.errors) do msgs[#msgs + 1] = e.text end
    T.ok(table.concat(msgs, '|'):find('zugestimmt', 1, true), 'ohne echte Zustimmung geht nichts: ' .. table.concat(msgs, '|'))
    -- Einladung an jemanden, der nicht in der Nähe ist
    T.fails(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-keller' }), 'nicht in Ihrer Nähe')
    T.fails(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-lena' }), 'nicht in Ihrer Nähe')
    -- Anna hat zu wenig Spielzeit
    T.fails(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-anna' }), 'Spielzeit')
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-tom' }))
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-marco' }))
    T.eq(#H.bridge.invitesAsked, 2)
    local st = T.succeeds(H.call(LENA, 'gewerbeamt', 'founderStatus', {}))
    T.eq(st.statuses['c-tom'], 'pending')
    T.ok(IC.apps.inviteAnswer('c-tom', true)); T.ok(IC.apps.inviteAnswer('c-marco', false))
    st = T.succeeds(H.call(LENA, 'gewerbeamt', 'founderStatus', {}))
    T.eq(st.statuses['c-tom'], 'ok'); T.eq(st.statuses['c-marco'], 'no')
    -- Marco lehnt ab, Einreichen scheitert weiter
    T.fails(submit(LENA, orgDraft()), 'nicht vollständig')
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-marco' }))
    -- Eine Einladung läuft nach 5 Minuten ab
    H.advance(6 * MIN)
    st = T.succeeds(H.call(LENA, 'gewerbeamt', 'founderStatus', {}))
    T.eq(st.statuses['c-marco'], 'expired')
    T.eq(IC.apps.inviteAnswer('c-marco', true), false, 'abgelaufene Einladungen lassen sich nicht mehr annehmen')
end)

T.test('Organisation: Vorstellung mit allen Mitgliedern, Staff-Gate, Untergrund-Plätze', function()
    cast(); duty(KELLER)
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-tom' }))
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-marco' }))
    IC.apps.inviteAnswer('c-tom', true); IC.apps.inviteAnswer('c-marco', true)
    local r = T.succeeds(submit(LENA, orgDraft()))
    local app = appById(r.id)
    T.eq(app.name, 'Skater Club Mirror Park e.V.'); T.eq(app.founders[2].consent, 'ok'); T.eq(app.founders[2].name, 'Tom Becker')
    T.eq(r.paid, 1200)
    -- OOC-Angaben sind für Beamte unsichtbar
    local o = T.succeeds(H.call(KELLER, 'beamte', 'bootstrap', { app = 'beamte' }))
    for _, a in ipairs(o.officialApps) do T.eq(a.ooc, nil) end
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok' }))
    -- Buchung ohne alle Pflichtteilnehmer scheitert
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'vorstellung_fraktion', dayOffset = 0 }))
    local start = sl.slots[1].start
    T.fails(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'vorstellung_fraktion', start = start, applicationId = r.id, attendees = { 'c-lena', 'c-tom' } }), 'Pflichtteilnehmer: Marco Rossi')
    local b = T.succeeds(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'vorstellung_fraktion', start = start, applicationId = r.id, attendees = { 'c-lena', 'c-tom', 'c-marco' } }))
    local ap = S.get('appointments', b.id)
    T.eq(#ap.attendees, 3); T.ok(H.lastNotice(TOM, 'hat einen Termin'), 'Mitgründer wurden informiert')
    H.clock = ap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = ap.id }))
    T.eq(ap.status, 'gebucht', 'solange nicht alle da sind, bleibt der Termin im Wartezustand')
    T.fails(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }), 'Pflichtteilnehmer fehlen noch')
    T.succeeds(H.call(TOM, 'buergeramt', 'apptCheckin', { id = ap.id }))
    T.succeeds(H.call(MARCO, 'buergeramt', 'apptCheckin', { id = ap.id }))
    T.eq(ap.status, 'eingecheckt')
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
    local all = {}
    for _, i in ipairs(Config.Checklists.vorstellung_fraktion) do all[i.key] = true end
    local d = T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = all }))
    T.eq(d.outcome, 'staff'); T.eq(app.status, 'staff_pruefung')
    T.eq(S.count('entities'), 0, 'noch nicht eingetragen')
    -- Staff
    local s = T.succeeds(H.staff('bootstrap', { app = 'staff' }))
    T.eq(s.staff.kpi.gate, 1); T.eq(s.staff.gate[1].ooc.category, 'untergrund', 'der Staff sieht die OOC-Angaben')
    T.fails(H.staff('staffGate', { id = r.id, decision = 'zurueck', note = 'kurz' }), 'mindestens 10')
    IC.setBranchCap('untergrund', 0)
    T.fails(H.staff('staffGate', { id = r.id, decision = 'freigeben' }), 'Untergrund-Plätze')
    IC.setBranchCap('untergrund', 8)
    T.succeeds(H.staff('staffGate', { id = r.id, decision = 'freigeben' }))
    T.eq(app.status, 'genehmigt')
    local e = S.get('entities', app.entityId)
    T.ok(e.regNo:match('^VR 02%d%d$'), e.regNo); T.eq(e.ooc.category, 'untergrund'); T.eq(IC.undergroundCap().used, 1)
    T.eq(#e.members, 3)
    local c = T.succeeds(H.call(TOM, 'gewerbeamt', 'bootstrap', { app = 'gewerbeamt' }))
    T.eq(#c.myEntities, 0, 'Tom ist stellv. Vorsitz, nicht Leiter: kein Verwaltungsrecht')
    c = T.succeeds(H.call(LENA, 'gewerbeamt', 'bootstrap', { app = 'gewerbeamt' }))
    T.eq(#c.myEntities, 1); T.eq(c.myEntities[1].ooc, nil, 'Gründer erhalten die OOC-Angaben nicht zurück in der Eintragung')
end)

T.test('Untergrund-Weg lässt sich abschalten', function()
    cast()
    T.succeeds(H.staff('staffSetting', { key = 'undergroundViaPortal', value = false }))
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-tom' }))
    T.succeeds(H.call(LENA, 'gewerbeamt', 'founderInvite', { charId = 'c-marco' }))
    IC.apps.inviteAnswer('c-tom', true); IC.apps.inviteAnswer('c-marco', true)
    local r = submit(LENA, orgDraft())
    T.fails(r, 'nicht vollständig')
    T.ok(r.errors[1].text:find('nicht angenommen', 1, true))
    T.succeeds(submit(LENA, orgDraft('Wanderverein', { category = 'legal', note = '', members = '9' })))
    T.fails(H.staff('staffSetting', { key = 'fourEyes', value = true }), 'Phase 2')
end)

-- ============================================================================ Nachbesserung, Ablehnung, Einspruch, Erstattung
T.test('Nachbesserung: Hinweis, erneutes Einreichen ohne neue Gebühr, Frist läuft ab', function()
    cast(); duty(KELLER)
    local r = T.succeeds(submit(LENA, draftEinzel()))
    local app = appById(r.id)
    T.fails(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'nachbesserung', message = 'kurz' }), 'mindestens 10')
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'nachbesserung', message = 'Bitte die Geschäftsidee genauer beschreiben.' }))
    T.eq(app.status, 'nachbesserung'); T.eq(app.remark, 'Bitte die Geschäftsidee genauer beschreiben.')
    local bank = H.bridge.players[LENA].bank
    local d = draftEinzel(); d.id = r.id
    d.concept.idea = d.concept.idea .. ' Wir arbeiten ausschließlich mit geprüften Handwerkern zusammen.'
    local r2 = T.succeeds(submit(LENA, d))
    T.eq(r2.id, r.id); T.eq(r2.paid, 0); T.eq(H.bridge.players[LENA].bank, bank, 'keine zweite Zahlung')
    T.eq(app.status, 'eingereicht'); T.eq(app.remark, nil); T.eq(r2.caseNo, r.caseNo)
    T.ok(app.concept.idea:find('geprüften Handwerkern', 1, true))
    -- Frist: nach 7 Tagen ohne Nachbesserung verfällt der Antrag, verwahrte Beträge kommen zurück
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'nachbesserung', message = 'Nochmals bitte prüfen und ergänzen.' }))
    H.advance(8 * DAY)
    IC.tick()
    T.eq(app.status, 'abgelaufen'); T.eq(H.bridge.players[LENA].bank, bank + 750, 'Eintragungsgebühr erstattet, Antragsgebühr nicht')
    T.eq(IC.ledgerGet('escrow'), 0)
    T.fails(H.call(LENA, 'gewerbeamt', 'appWithdraw', { id = r.id }), 'nicht mehr zurückziehen')
end)

T.test('Ablehnung: Begründung Pflicht, Erstattung, Namenssperre 24 Stunden, Einspruch', function()
    cast(); duty(KELLER)
    local r = T.succeeds(submit(LENA, draftEinzel('Erster Versuch Bau')))
    local app = appById(r.id)
    T.fails(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'abgelehnt', message = '' }), 'Begründung')
    local bank = H.bridge.players[LENA].bank
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'abgelehnt', message = 'Der Zweck ist aus Sicht der Behörde unzulässig.' }))
    T.eq(app.status, 'abgelehnt'); T.eq(H.bridge.players[LENA].bank, bank + 750, 'verwahrte Beträge zurück')
    T.ok(app.objectionUntil > IC.now())
    -- derselbe Name ist 24 Stunden gesperrt
    local again = submit(LENA, draftEinzel('Erster Versuch Bau'))
    T.fails(again, 'nicht vollständig')
    H.advance(25 * HOUR)
    T.eq(H.call(LENA, 'gewerbeamt', 'nameCheck', { name = 'Erster Versuch Bau', legalForm = 'einzel' }).ok, true, 'nach 24 Stunden ist der Name wieder frei')
    T.ok(app.objectionUntil > IC.now(), 'der Einspruch ist noch möglich')
    H.advance(24 * HOUR)
    T.fails(H.call(LENA, 'gewerbeamt', 'appObjection', { id = r.id, text = 'Das ist ungerecht, bitte prüfen Sie den Fall noch einmal.' }), 'Einspruchsfrist')
end)

T.test('Einspruch: Verhandlung mit Amtsleiter, Absage stellt den Status wieder her, Stattgabe trägt ein', function()
    cast(); duty(YILMAZ, 'on', 2)
    local r = T.succeeds(submit(LENA, draftEinzel('Einspruch Bau')))
    T.succeeds(H.call(YILMAZ, 'beamte', 'appReview', { id = r.id, result = 'abgelehnt', message = 'Der Standort konnte nicht nachgewiesen werden.' }))
    local app = appById(r.id)
    T.fails(H.call(LENA, 'gewerbeamt', 'appObjection', { id = r.id, text = 'zu kurz' }), 'mindestens 20')
    T.succeeds(H.call(LENA, 'gewerbeamt', 'appObjection', { id = r.id, text = 'Der Mietvertrag liegt inzwischen vor und wird mitgebracht.' }))
    T.eq(app.status, 'einspruch')
    -- nur ein Sachbearbeiter im Dienst: keine Termine für die Einspruchsverhandlung
    T.eq(#T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'einspruch', dayOffset = 0 })).slots, 0)
    duty(KELLER)
    local b, start = bookFirst(LENA, 'einspruch', r.id)
    T.succeeds(b); T.eq(app.status, 'termin_gebucht')
    -- Absage stellt "einspruch" wieder her, nicht "vorpruefung_ok"
    H.clock = start - 60 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCancel', { id = b.id }))
    T.eq(app.status, 'einspruch', 'kein Umweg an der Vorprüfung vorbei')
    local b2 = T.succeeds((bookFirst(LENA, 'einspruch', r.id)))
    local ap = S.get('appointments', b2.id)
    H.clock = ap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = ap.id }))
    -- ein Sachbearbeiter darf die Verhandlung nicht führen
    T.fails(H.call(YILMAZ, 'beamte', 'apptStart', { id = ap.id }), 'Amtsleiter')
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
    local all = {}
    for _, i in ipairs(Config.Checklists.einspruch) do all[i.key] = true end
    local d = T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = all }))
    T.eq(d.outcome, 'eingetragen'); T.eq(app.status, 'genehmigt')
end)

T.test('Rückzug: Erstattung ohne Antragsgebühr, Termin wird geschlossen, Name wird frei', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel('Rückzug Bau'))
    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local bank = H.bridge.players[LENA].bank
    local w = T.succeeds(H.call(LENA, 'gewerbeamt', 'appWithdraw', { id = r.id }))
    T.eq(w.refunded, 750); T.eq(H.bridge.players[LENA].bank, bank + 750)
    T.eq(appById(r.id).status, 'zurueckgezogen'); T.eq(S.get('appointments', b.id).status, 'abgesagt')
    T.succeeds(submit(LENA, draftEinzel('Rückzug Bau')), 'derselbe Name ist wieder frei')
    -- Entwürfe lassen sich löschen
    local dr = T.succeeds(H.call(LENA, 'gewerbeamt', 'appSave', { draft = draftEinzel('Entwurf Bau') }))
    T.eq(appById(dr.id).status, 'entwurf')
    T.eq(T.succeeds(H.call(LENA, 'gewerbeamt', 'appWithdraw', { id = dr.id })).deleted, true)
    T.eq(appById(dr.id), nil)
end)

T.test('Erstattung an einen Spieler, der gerade offline ist, wird beim nächsten Login ausgezahlt', function()
    cast(); duty(KELLER)
    local r = T.succeeds(submit(LENA, draftEinzel('Offline Bau')))
    local lena = H.bridge.players[LENA]
    H.bridge.players[LENA] = nil                      -- Lena verlässt den Server
    T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'abgelehnt', message = 'Der Name verstößt gegen die Namensregeln.' }))
    T.eq(S.count('refunds'), 1)
    H.bridge.players[LENA] = lena
    local before = lena.bank
    IC.pay.flushRefunds('c-lena', LENA)
    T.eq(lena.bank, before + 750); T.eq(S.count('refunds'), 0)
    T.ok(H.lastNotice(LENA, 'erstattet'))
end)

T.test('Notfallregel: überfällige Anträge lassen sich nach Aktenlage entscheiden', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel('Aktenlage Bau'))
    duty(KELLER, 'off')
    T.fails(H.staff('staffWritten', { id = r.id, decision = 'genehmigt', reason = 'Nach Aktenlage unbedenklich.' }), 'noch nicht überfällig')
    local s = T.succeeds(H.staff('bootstrap', { app = 'staff' }))
    T.eq(s.staff.kpi.escalations, 0)
    H.advance(73 * HOUR)
    s = T.succeeds(H.staff('bootstrap', { app = 'staff' }))
    T.eq(s.staff.kpi.escalations, 1); T.eq(s.staff.escalations[1].id, r.id)
    T.fails(H.staff('staffWritten', { id = r.id, decision = 'genehmigt', reason = 'kurz' }), 'Begründung')
    T.succeeds(H.staff('staffSetting', { key = 'writtenProcedure', value = false }))
    T.fails(H.staff('staffWritten', { id = r.id, decision = 'genehmigt', reason = 'Nach Aktenlage unbedenklich.' }), 'abgeschaltet')
    T.succeeds(H.staff('staffSetting', { key = 'writtenProcedure', value = true }))
    T.succeeds(H.staff('staffWritten', { id = r.id, decision = 'genehmigt', reason = 'Nach Aktenlage unbedenklich.' }))
    T.eq(appById(r.id).status, 'genehmigt'); T.eq(S.count('entities'), 1)
end)

T.test('Fristen: ohne Terminbuchung verfällt der Antrag nach 14 Tagen', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel('Frist Bau'))
    local bank = H.bridge.players[LENA].bank
    H.advance(13 * DAY); IC.tick()
    T.eq(appById(r.id).status, 'vorpruefung_ok')
    H.advance(2 * DAY); IC.tick()
    T.eq(appById(r.id).status, 'abgelaufen'); T.eq(H.bridge.players[LENA].bank, bank + 750)
end)

-- ============================================================================ Rechte und Manipulation
T.test('Rechte: Bürger können keine Beamten- oder Staff-Aufrufe ausführen, Sitzung ist Pflicht', function()
    cast(); duty(KELLER)
    local r = T.succeeds(submit(LENA, draftEinzel('Rechte Bau')))
    T.fails(H.call(LENA, 'gewerbeamt', 'appReview', { id = r.id, result = 'ok' }), 'nicht befugt')
    T.fails(H.call(LENA, 'beamte', 'appReview', { id = r.id, result = 'ok' }), 'nicht befugt', 'Sitzung "beamte" ohne Beamten-Job')
    T.fails(H.call(LENA, 'gewerbeamt', 'staffGate', { id = r.id }), 'nicht befugt')
    T.fails(H.call(LENA, 'staff', 'staffSetting', { key = 'fourEyes' }), 'nicht befugt', 'Sitzung "staff" ohne ACE-Recht')
    T.fails(H.call(KELLER, 'gewerbeamt', 'appReview', { id = r.id, result = 'ok' }), 'nicht befugt', 'Beamte in der Bürger-Sitzung')
    T.fails(H.call(LENA, nil, 'bootstrap', {}, { session = false }), 'öffnen')
    T.fails(H.call(LENA, 'gewerbeamt', 'gibtEsNicht', {}), 'Unbekannte Aktion')
    T.fails(H.call(LENA, 'gewerbeamt', 'pvReset', {}), 'Unbekannte Aktion', 'Vorschau-Aufrufe gibt es auf dem Server nicht')
    T.fails(H.call(LENA, 'beamte', 'dutySet', { state = 'on' }), 'nicht befugt')
    T.fails(H.call(KELLER, 'beamte', 'dutySet', { state = 'fliegen' }), 'Unbekannter Dienststatus')
    -- Citizen-Aufrufe in der Beamten-Sitzung
    T.fails(H.call(KELLER, 'beamte', 'appSubmit', { draft = {} }), 'nicht möglich')
end)

T.test('Beamte: nur im Dienst, nur mit Rang, nie bei eigenen Anträgen', function()
    cast()
    local r = T.succeeds(submit(LENA, draftEinzel('Rang Bau')))
    T.fails(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok' }), 'im Dienst sein')
    duty(NOVAK, 'on', 3)
    T.fails(H.call(NOVAK, 'beamte', 'appReview', { id = r.id, result = 'ok' }), 'Sachbearbeiter')
    duty(KELLER)
    -- Beamte bewirbt sich selbst: gesperrt
    H.player(20, { charId = 'c-selbst', name = 'Selbst Antrag', rank = 'sachbearbeiter', bank = 100000, area = 1 })
    local own = T.succeeds(submit(20, draftEinzel('Selbstantrag Bau', { founders = { { charId = 'c-selbst', name = 'x', role = 'inhaber', share = 100 } } })))
    duty(20, 'on', 2)
    T.fails(H.call(20, 'beamte', 'appReview', { id = own.id, result = 'ok' }), 'befangen')
    local o = T.succeeds(H.call(20, 'beamte', 'bootstrap', { app = 'beamte' }))
    for _, a in ipairs(o.officialApps) do T.notok(a.id == own.id, 'der eigene Antrag ist in der Liste nicht sichtbar') end
    -- Befangenheit melden: Antrag verschwindet aus der Liste, ein anderer Beamter bearbeitet
    T.succeeds(H.call(KELLER, 'beamte', 'conflictReport', { id = r.id }))
    o = T.succeeds(H.call(KELLER, 'beamte', 'bootstrap', { app = 'beamte' }))
    local found = false
    for _, a in ipairs(o.officialApps) do if a.id == r.id then found = true end end
    T.notok(found, 'nach der Meldung nicht mehr in Kellers Liste')
    T.fails(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok' }), 'befangen')
    T.succeeds(H.call(20, 'beamte', 'appReview', { id = r.id, result = 'ok' }))
end)

T.test('Entscheidung: Pflichtpunkte, Begründung, Auflagen, nur der führende Beamte', function()
    cast(); duty(KELLER); duty(YILMAZ, 'on', 2)
    local r = toPreChecked(LENA, draftEinzel('Entscheid Bau'))
    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local ap = S.get('appointments', b.id)
    H.clock = ap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = ap.id }))
    T.fails(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt' }), 'laufen')
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
    T.fails(H.call(YILMAZ, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = {} }), 'anderen Beamten')
    T.fails(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = { id = true } }), 'Pflichtpunkte')
    T.fails(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'auflagen', reason = 'Mietvertrag fehlt noch.' }), 'mindestens eine Auflage')
    T.fails(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'abgelehnt', reason = 'zu kurz' }), 'Begründung')
    T.fails(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'egal' }), 'Entscheidung wählen')
    local d = T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'auflagen', reason = 'Mietvertrag fehlt noch.', conditions = { 'Mietvertrag innerhalb von 14 Tagen vorlegen', '  ' }, checklist = { id = true } }))
    T.eq(d.outcome, 'eingetragen')
    local e = S.get('entities', appById(r.id).entityId)
    T.eq(e.status, 'probezeit'); T.eq(#e.conditions, 1, 'leere Auflagen werden verworfen')
    -- Nachkontrolle bestätigt die Auflagen und beendet die Probezeit
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'nachkontrolle', dayOffset = 0 }))
    local nb = T.succeeds(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'nachkontrolle', start = sl.slots[#sl.slots].start, entityId = e.id }))
    local nap = S.get('appointments', nb.id)
    H.clock = nap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = nap.id }))
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = nap.id }))
    local all = {}
    for _, i in ipairs(Config.Checklists.nachkontrolle) do all[i.key] = true end
    T.eq(T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = nap.id, decision = 'genehmigt', checklist = all })).outcome, 'erfuellt')
    T.eq(e.status, 'aktiv'); T.eq(#IC.register.openConditions(e), 0)
end)

T.test('Manipulation: Preise, fremde Anträge, doppelte Gründer und fehlender Antragsteller', function()
    cast(); duty(KELLER)
    -- Der Client kann den Preis nicht beeinflussen
    local d = draftEinzel('Billig Bau', { fees = { payNow = 1 }, price = 1 })
    local bank = H.bridge.players[LENA].bank
    local r = T.succeeds(submit(LENA, d))
    T.eq(H.bridge.players[LENA].bank, bank - 1000)
    -- Fremde Anträge sind unantastbar
    T.fails(H.call(TOM, 'gewerbeamt', 'appWithdraw', { id = r.id }), 'nicht gefunden')
    T.fails(H.call(TOM, 'gewerbeamt', 'appObjection', { id = r.id, text = string.rep('x', 30) }), 'kein Einspruch')
    local d2 = draftEinzel('Billig Bau Zwei'); d2.id = r.id
    T.fails(submit(TOM, d2), 'nicht gefunden')
    T.fails(H.call(TOM, 'gewerbeamt', 'appSave', { draft = d2 }), 'nicht gefunden')
    -- Der Antragsteller muss selbst Gründer sein
    local d3 = draftEinzel('Strohmann Bau', { founders = { { charId = 'c-tom', name = 'Tom Becker', role = 'inhaber', share = 100 } } })
    T.fails(submit(LENA, d3), 'selbst als Gründer')
    -- Kontostand
    H.bridge.players[TOM].bank = 500
    T.fails(submit(TOM, draftEinzel('Arm Bau', { founders = { { charId = 'c-tom', name = 'Tom Becker', role = 'inhaber', share = 100 } } })), 'nicht vollständig')
    T.eq(H.bridge.players[TOM].bank, 500)
    -- Nach Ablauf lässt sich ein eingereichter Antrag nicht mehr verändern
    T.fails(H.call(LENA, 'gewerbeamt', 'appSave', { draft = (function() local x = draftEinzel('Billig Bau'); x.id = r.id; return x end)() }), 'nicht mehr bearbeitet')
    -- Termin anderer: nicht absagen, nicht einchecken
    H.bridge.players[TOM].bank = 100000
    local pre = toPreChecked(TOM, draftEinzel('Tom Bau', { founders = { { charId = 'c-tom', name = 'Tom Becker', role = 'inhaber', share = 100 } } }))
    local b = T.succeeds((bookFirst(TOM, 'beratung')))
    T.fails(H.call(LENA, 'buergeramt', 'apptCancel', { id = b.id }), 'nicht gefunden')
    T.fails(H.call(LENA, 'buergeramt', 'apptCheckin', { id = b.id }), 'nicht eingetragen')
    -- Zu viele Entwürfe
    for i = 1, 5 do T.succeeds(H.call(MARCO, 'gewerbeamt', 'appSave', { draft = draftEinzel('Entwurf Nr ' .. i, { founders = { { charId = 'c-marco', name = 'Marco', role = 'inhaber', share = 100 } } }) })) end
    T.fails(H.call(MARCO, 'gewerbeamt', 'appSave', { draft = draftEinzel('Entwurf Sechs', { founders = { { charId = 'c-marco', name = 'Marco', role = 'inhaber', share = 100 } } }) }), '5 Entwürfe')
end)

T.test('Limits: zwei offene Anträge, Branchenkapazität, Unternehmenslimit', function()
    cast()
    T.succeeds(submit(LENA, draftEinzel('Limit Eins')))
    T.succeeds(submit(LENA, draftEinzel('Limit Zwei')))
    local r = submit(LENA, draftEinzel('Limit Drei'))
    T.fails(r, 'nicht vollständig')
    local txt = {}
    for _, e in ipairs(r.errors) do txt[#txt + 1] = e.text end
    T.ok(table.concat(txt, '|'):find('Offene Anträge: 2 von 2', 1, true))
    -- Kapazität einer Branche
    H.reset(); cast()
    H.staff('staffCap', { key = 'handwerk', value = 0 })
    r = submit(LENA, draftEinzel('Ausgelastet Bau'))
    T.fails(r, 'nicht vollständig')
    T.ok(r.errors[1].text:find('Plätze vergeben', 1, true))
end)

T.test('Eintragungen: Änderung, Duplikat, Auflösung, Namenssperre nach Auflösung', function()
    cast(); duty(KELLER)
    local r = toPreChecked(LENA, draftEinzel('Verwaltung Bau'))
    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local ap = S.get('appointments', b.id)
    H.clock = ap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = ap.id }))
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
    local all = {}
    for _, i in ipairs(Config.Checklists.vorstellung_unternehmen) do all[i.key] = true end
    T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = all }))
    local e = S.get('entities', appById(r.id).entityId)
    -- Duplikat
    local bank = H.bridge.players[LENA].bank
    T.succeeds(H.call(LENA, 'gewerbeamt', 'entityDuplicate', { id = e.id }))
    T.eq(H.bridge.players[LENA].bank, bank - 100); T.eq(#H.bridge.certificates, 2)
    T.fails(H.call(TOM, 'gewerbeamt', 'entityDuplicate', { id = e.id }), 'nicht gefunden')
    -- Änderung beantragen und beurkunden
    T.fails(H.call(LENA, 'gewerbeamt', 'entityChange', { id = e.id, type = 'name', value = 'Polizei Bau' }), 'gesperrt')
    T.succeeds(H.call(LENA, 'gewerbeamt', 'entityChange', { id = e.id, type = 'name', value = 'Verwaltung Bau Süd' }))
    T.eq(e.pendingChange.value, 'Verwaltung Bau Süd')
    local sl = T.succeeds(H.call(LENA, 'buergeramt', 'slotsList', { typeId = 'aenderung', dayOffset = 0 }))
    local cb = T.succeeds(H.call(LENA, 'buergeramt', 'apptBook', { typeId = 'aenderung', start = sl.slots[#sl.slots].start, entityId = e.id }))
    local cap = S.get('appointments', cb.id)
    H.clock = cap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = cap.id }))
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = cap.id }))
    local all2 = {}
    for _, i in ipairs(Config.Checklists.aenderung) do all2[i.key] = true end
    T.eq(T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = cap.id, decision = 'genehmigt', checklist = all2 })).outcome, 'geaendert')
    T.eq(e.name, 'Verwaltung Bau Süd'); T.eq(e.pendingChange, nil)
    -- Auflösung, danach ist der Name 7 Tage gesperrt
    T.succeeds(H.call(LENA, 'gewerbeamt', 'entityDissolve', { id = e.id }))
    T.eq(e.status, 'aufgeloest')
    local nc = H.call(LENA, 'gewerbeamt', 'nameCheck', { name = 'Verwaltung Bau Süd', legalForm = 'einzel' })
    T.eq(nc.ok, false, 'sieben Tage Sperre nach Auflösung')
    H.advance(8 * DAY)
    nc = H.call(LENA, 'gewerbeamt', 'nameCheck', { name = 'Verwaltung Bau Süd', legalForm = 'einzel' })
    T.eq(nc.ok, true)
    -- Register: öffentlich, ohne OOC
    local rr = T.succeeds(H.call(TOM, 'gewerbeamt', 'registerSearch', { q = 'verwaltung' }))
    T.eq(#rr.rows, 1); T.eq(rr.rows[1].ooc, nil); T.eq(rr.rows[1].status, 'aufgeloest')
    T.eq(#T.succeeds(H.call(TOM, 'gewerbeamt', 'registerSearch', { kind = 'fraktion' })).rows, 0)
end)

T.test('Sanktionen: nur Amtsleiter im Dienst, Begründung Pflicht, Wirkung je Stufe', function()
    cast(); duty(KELLER); duty(YILMAZ, 'on', 2)
    local r = toPreChecked(LENA, draftEinzel('Sanktion Bau'))
    local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
    local ap = S.get('appointments', b.id)
    H.clock = ap.start - 2 * MIN
    T.succeeds(H.call(LENA, 'buergeramt', 'apptCheckin', { id = ap.id }))
    T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
    local all = {}
    for _, i in ipairs(Config.Checklists.vorstellung_unternehmen) do all[i.key] = true end
    T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = all }))
    local e = S.get('entities', appById(r.id).entityId)
    T.fails(H.call(YILMAZ, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'verwarnung', reason = 'Lärmbeschwerden der Anwohner.' }), 'Amtsleiter')
    T.fails(H.call(KELLER, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'verwarnung', reason = 'kurz' }), 'Begründung')
    T.fails(H.call(KELLER, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'hinrichtung', reason = 'Lärmbeschwerden der Anwohner.' }), 'Unbekannte Maßnahme')
    T.succeeds(H.call(KELLER, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'verwarnung', reason = 'Lärmbeschwerden der Anwohner.' }))
    T.succeeds(H.call(KELLER, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'auflage', reason = 'Öffnungszeiten am Standort sichtbar aushängen' }))
    T.eq(#IC.register.openConditions(e), 1)
    T.succeeds(H.call(KELLER, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'untersagung', reason = 'Wiederholte Verstöße gegen die Auflagen.' }))
    T.eq(e.status, 'gesperrt')
    T.succeeds(H.call(KELLER, 'beamte', 'sanctionIssue', { entityId = e.id, level = 'entzug', reason = 'Eintragung wird endgültig entzogen.' }))
    T.eq(e.status, 'aufgeloest'); T.eq(#e.history >= 4, true)
    local hooks = 0
    for _, h in ipairs(H.bridge.hooks) do if h[1] == 'onSanction' then hooks = hooks + 1 end end
    T.eq(hooks, 4, 'Hook wird je Maßnahme aufgerufen')
    T.ok(H.lastNotice(LENA, 'Maßnahme'))
end)

T.test('Staff: Sperrliste, Bestandsbestätigung, Kennzahlen', function()
    cast()
    T.succeeds(H.staff('staffBlacklistAdd', { term = 'Weißes Haus', reason = 'Reale Marke' }))
    T.fails(H.staff('staffBlacklistAdd', { term = 'weisses haus' }), 'bereits gesperrt')
    T.fails(H.staff('staffBlacklistAdd', { term = 'ab' }), 'mindestens 3')
    T.eq(H.call(LENA, 'gewerbeamt', 'nameCheck', { name = 'Mein Weißes Haus Bar', legalForm = 'einzel' }).ok, false, 'gesperrter Begriff steckt im Namen')
    local id
    for _, b in ipairs(S.list('blacklist')) do if b.term == 'Weißes Haus' then id = b.id end end
    T.succeeds(H.staff('staffBlacklistRemove', { id = id }))
    T.eq(H.call(LENA, 'gewerbeamt', 'nameCheck', { name = 'Mein Weißes Haus Bar', legalForm = 'einzel' }).ok, true, 'nach dem Entfernen wieder zulässig')
    -- Bestandsschutz: übernommener Eintrag wird bestätigt
    S.put('entities', { id = 'E-L1', kind = 'unternehmen', regNo = 'HRA 0999', name = 'Alter Kiosk', legalForm = 'einzel', branch = 'handel', status = 'aktiv', hq = 'Mobil', owner = 'Lena Brandt', founded = IC.now(), validUntil = IC.now() + 90 * DAY, memberCount = 1, members = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber', share = 100 } }, conditions = {}, history = {}, legacy = true, legacyConfirmed = false })
    T.succeeds(H.call(LENA, 'gewerbeamt', 'legacyConfirm', { id = 'E-L1' }))
    T.eq(S.get('entities', 'E-L1').legacyConfirmed, true)
    T.fails(H.call(TOM, 'gewerbeamt', 'legacyConfirm', { id = 'E-L1' }), 'Bestandsschutz')
    -- Kapazität
    T.succeeds(H.staff('staffCap', { key = 'gastro', value = 20 }))
    T.fails(H.staff('staffCap', { key = 'raumschiffe', value = 5 }), 'nicht gefunden')
    local s = T.succeeds(H.staff('bootstrap', { app = 'staff' }))
    local gastro
    for _, c in ipairs(s.staff.caps) do if c.key == 'gastro' then gastro = c end end
    T.eq(gastro.cap, 20)
    T.ok(#s.staff.audit > 0)
end)

-- ============================================================================ Protokoll
T.test('Protokoll: jeder Aufruf der Oberfläche ist bekannt und hat einen Handler', function()
    local names = {}
    local dir = io.popen('ls web/js/*.js')
    for f in dir:lines() do
        local fh = io.open(f, 'r'); local src = fh:read('a'); fh:close()
        for n in src:gmatch("IC%.api%('([%w]+)'") do names[n] = true end
        for n in src:gmatch("IC%.run%('([%w]+)'") do names[n] = true end
    end
    dir:close()
    local count = 0
    for n in pairs(names) do
        if not n:match('^pv') and n ~= 'close' then
            count = count + 1
            T.ok(IC.protocol.groups[n], 'Protokoll kennt "' .. n .. '"')
            T.ok(IC.api.handlers[n], 'Handler für "' .. n .. '"')
        end
    end
    T.ok(count >= 36, 'es wurden ' .. count .. ' Aufrufe gefunden')
    for n in pairs(IC.protocol.groups) do T.ok(IC.api.handlers[n], 'Handler für Protokollname "' .. n .. '"') end
    for n in pairs(IC.api.handlers) do T.ok(IC.protocol.groups[n], 'Protokoll für Handler "' .. n .. '"') end
end)

-- ============================================================================ Bestand, Schein, Kasse
T.test('Gewerbeschein: ist der Inhaber offline oder das Inventar voll, wird er beim Login nachgeliefert', function()
    cast()
    local e = { id = 'E-5', kind = 'unternehmen', regNo = 'HRB 0301', name = 'Test GmbH', status = 'aktiv', members = {}, history = {}, conditions = {}, validUntil = IC.now() + DAY }
    S.put('entities', e)
    T.eq(IC.register.handOverCertificate('c-offline', e), false, 'Charakter ist nicht online')
    T.eq(S.get('chars', 'c-offline').pendingCerts[1], 'E-5')
    T.eq(IC.register.handOverCertificate('c-offline', e), false)
    T.eq(#S.get('chars', 'c-offline').pendingCerts, 1, 'kein Doppeleintrag')
    T.eq(IC.register.handOverCertificate('c-lena', e), true, 'online: sofort ausgehändigt')
    T.eq(#H.bridge.certificates, 1)

    -- Inventar voll: false, der Schein wird gemerkt
    local realGive = H.bridge.giveCertificate
    H.bridge.giveCertificate = function() return false end
    T.eq(IC.register.handOverCertificate('c-tom', e), false)
    T.eq(S.get('chars', 'c-tom').pendingCerts[1], 'E-5')
    H.bridge.giveCertificate = realGive

    -- Login: nachgeliefert; gibt es den Eintrag nicht mehr, verfällt der Vermerk
    H.player(7, { charId = 'c-offline', name = 'Offline Olli' })
    IC.register.deliverPending('c-offline', 7)
    T.eq(#H.bridge.certificates, 2); T.eq(#S.get('chars', 'c-offline').pendingCerts, 0)
    S.get('chars', 'c-tom').pendingCerts = { 'E-5', 'E-404' }
    S.del('entities', 'E-5')
    H.player(8, { charId = 'c-tom', name = 'Tom Becker' })
    IC.register.deliverPending('c-tom', 8)
    T.eq(#S.get('chars', 'c-tom').pendingCerts, 0, 'unbekannte Einträge fallen weg')
    T.eq(#H.bridge.certificates, 2)
end)

T.test('Bestandsimport: Registernummern, Anteile, Rollen, Dubletten und Fehler', function()
    cast()
    local list = {
        { ref = 'a1', name = "Lena's Kiosk", kind = 'unternehmen', legalForm = 'einzel', branch = 'handel', hq = 'Vespucci', founded = 1700000000000,
          members = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber' } } },
        { ref = 'a2', name = 'Rossi Bau', kind = 'unternehmen', legalForm = 'gmbh', branch = 'handwerk',
          members = { { charId = 'c-marco', name = 'Marco Rossi', share = 60 }, { charId = 'c-tom', name = 'Tom Becker', share = 30 }, { charId = 'c-lena', name = 'Lena Brandt', share = 7 } } },
        { ref = 'a3', name = 'Hafenclub', kind = 'fraktion', legalForm = 'ig', ooc = 'untergrund',
          members = { { charId = 'c-tom', role = 'mitglied' }, { charId = 'c-marco', role = 'vorsitz' }, { charId = 'c-lena', role = 'hauptmann' } } },
        { ref = 'a1', name = 'Ganz anders', members = { { charId = 'c-lena' } } },                              -- gleiche Referenz: übersprungen
        { ref = 'a5', name = 'lenas  kiosk', kind = 'unternehmen', members = { { charId = 'c-tom' } } },       -- gleicher Name nach Normalisierung
        { ref = 'a6', name = 'Kaputt', legalForm = 'gibtsnicht', members = { { charId = 'c-tom' } } },
        { ref = 'a7', name = 'Passt nicht', kind = 'fraktion', legalForm = 'gmbh', members = { { charId = 'c-tom' } } },
        { ref = 'a8', name = 'Ohne Leute', members = {} },
        { ref = 'a9', name = 'X', members = { { charId = 'c-tom' } } },
        { ref = 'a10', name = 'Falsche Branche', branch = 'raumfahrt', members = { { charId = 'c-tom' } } },
        'kein Eintrag',
    }
    local res = IC.register.importLegacy(list, 'Test')
    T.eq(res.created, 3); T.eq(res.skipped, 2); T.eq(#res.errors, 6, table.concat(res.errors, ' | '))

    local byName = {}
    for _, e in ipairs(S.list('entities')) do byName[e.name] = e end
    local kiosk, bau, club = byName["Lena's Kiosk"], byName['Rossi Bau GmbH'], byName['Hafenclub']
    T.ok(kiosk and bau and club, 'Name bekommt den Rechtsformzusatz: Rossi Bau GmbH')
    T.eq(kiosk.regNo, 'HRA 1001'); T.eq(bau.regNo, 'HRB 0301'); T.eq(club.regNo, 'IG 0001')
    T.eq(kiosk.legacy, true); T.eq(kiosk.legacyConfirmed, false); T.eq(kiosk.status, 'aktiv'); T.eq(kiosk.founded, 1700000000000)
    T.eq(kiosk.legacyDue, IC.now() + 28 * DAY); T.eq(kiosk.hq, 'Vespucci'); T.eq(kiosk.owner, 'Lena Brandt')

    -- Anteile ergaben 97: gleichmäßig verteilt, Rest geht an den ersten. Kein Geschäftsführer angegeben: der erste wird es.
    T.eq(bau.members[1].share + bau.members[2].share + bau.members[3].share, 100)
    T.eq(bau.members[1].share, 34); T.eq(bau.members[1].role, 'geschaeftsfuehrer'); T.eq(bau.owner, 'Marco Rossi')
    -- Organisation: unbekannte Rolle wird Mitglied, Anteile entfallen, Fraktionsart ist nur für Staff sichtbar
    T.eq(club.members[3].role, 'mitglied'); T.eq(club.members[1].share, nil); T.eq(club.owner, 'c-marco')
    T.eq(club.ooc.category, 'untergrund')
    local boot = T.succeeds(H.call(LENA, 'gewerbeamt', 'bootstrap', { app = 'gewerbeamt' }))
    local mine = {}
    for _, e in ipairs(boot.myEntities) do mine[e.name] = e end
    T.ok(mine["Lena's Kiosk"] and mine["Lena's Kiosk"].legacy, 'Inhaberin sieht ihren Bestandseintrag')
    T.eq(mine['Hafenclub'], nil, 'als bloßes Mitglied sieht sie die Organisation nicht als eigene')
    T.notok(mine["Lena's Kiosk"].ooc)
    T.ok(H.lastNotice(LENA, 'übernommen'))
    T.succeeds(H.call(LENA, 'gewerbeamt', 'legacyConfirm', { id = kiosk.id }))

    -- Zweiter Lauf: nichts passiert doppelt, Nummern laufen weiter
    local again = IC.register.importLegacy(list, 'Test')
    T.eq(again.created, 0); T.eq(again.skipped, 5)
    T.eq(S.count('entities'), 3)
    T.eq(IC.register.importLegacy('keine Liste').errors[1], 'Die Datei enthält keine Liste.')
end)

T.test('Stadtkasse: Pauschale wird abgebucht, bei leerer Kasse trotzdem gezahlt und vermerkt', function()
    cast()
    H.bridge.treasury = 400
    local before = H.bridge.players[KELLER].bank
    IC.pay.official(KELLER, 150, 'Termin')
    T.eq(H.bridge.treasury, 250); T.eq(H.bridge.players[KELLER].bank, before + 150)
    IC.pay.official(KELLER, 150, 'Termin')
    T.eq(H.bridge.treasury, 100)
    IC.pay.official(KELLER, 150, 'Termin')
    T.eq(H.bridge.treasury, 100, 'ungedeckt: Kasse bleibt unverändert'); T.eq(H.bridge.players[KELLER].bank, before + 450, 'der Beamte bekommt die Pauschale trotzdem')
    T.ok(IC.auditLog[1].action:find('nicht gedeckt', 1, true), 'Eintrag im Protokoll')
end)

T.test('Start: die Sperrliste wird nur einmal angelegt', function()
    cast()
    local n = S.count('blacklist')
    T.ok(n > 5)
    for _, b in ipairs(S.list('blacklist')) do S.del('blacklist', b.id) end
    IC.staff.seed()
    T.eq(S.count('blacklist'), 0, 'wer die Liste leert, bekommt sie nach einem Neustart nicht zurück')
end)

T.test('Stammkapital der GmbH: bleibt in Verwahrung, geht an das Unternehmen oder zurück an den Antragsteller', function()
    local function approveGmbh(hookResult)
        cast()
        duty(KELLER)
        Config.Hooks.onApproved = function(e, a)
            H.bridge.hooks[#H.bridge.hooks + 1] = { 'onApproved', e.regNo, e.capital }
            if type(hookResult) == 'function' then return hookResult(e, a) end
            return hookResult
        end
        local d = draftEinzel('Rossi Bau', { legalForm = 'gmbh', branch = 'handwerk' })
        local before = H.bridge.players[LENA].bank
        local r = T.succeeds(submit(LENA, d), 'GmbH einreichen')
        T.eq(r.paid, 800 + 2700 + 25000, 'Antragsgebühr, Eintragungsgebühr und Kapital werden fällig')
        T.eq(IC.ledgerGet('escrow'), 2700 + 25000)
        T.succeeds(H.call(KELLER, 'beamte', 'appReview', { id = r.id, result = 'ok' }))
        local b = T.succeeds((bookFirst(LENA, 'vorstellung_unternehmen', r.id)))
        local ap = S.get('appointments', b.id)
        T.succeeds(checkinAt(ap, LENA))
        T.succeeds(H.call(KELLER, 'beamte', 'apptCall', { id = ap.id }))
        T.succeeds(H.call(KELLER, 'beamte', 'apptStart', { id = ap.id }))
        local all = {}
        for _, i in ipairs(Config.Checklists.vorstellung_unternehmen) do all[i.key] = true end
        local res = T.succeeds(H.call(KELLER, 'beamte', 'apptDecide', { id = ap.id, decision = 'genehmigt', checklist = all }))
        T.eq(res.outcome, 'eingetragen')
        return before, r, S.get('applications', r.id)
    end

    -- Der Hook bucht das Kapital auf das Firmenkonto und meldet es mit true: das Geld verlässt die Verwahrung, es gibt keine Erstattung
    local before, r, app = approveGmbh(true)
    T.eq(H.bridge.hooks[#H.bridge.hooks][3], 25000, 'der Hook sieht das Kapital')
    T.eq(IC.ledgerGet('escrow'), 0, 'Verwahrung ist leer')
    T.eq(H.bridge.players[LENA].bank, before - 28500, 'Lena bekommt nichts zurück')
    T.eq(app.fees.capitalTo, 'unternehmen')

    -- Kein Firmenkonto angebunden (Hook gibt nichts zurück): das Kapital geht an den Antragsteller zurück, es verschwindet nicht
    before, r, app = approveGmbh(nil)
    T.eq(IC.ledgerGet('escrow'), 0)
    T.eq(H.bridge.players[LENA].bank, before - 3500, 'nur die Gebühren sind weg, das Kapital kommt zurück')
    T.eq(app.fees.capitalTo, 'antragsteller')
    T.ok(H.lastNotice(LENA, '25.000'), 'Hinweis auf die Erstattung')

    -- Ein Fehler im Hook ist kein Grund, das Geld zu behalten
    local lines
    lines, before = T.capture(approveGmbh, function() error('kaputt') end)
    T.ok(lines[1] and lines[1]:find('Fehler im Hook onApproved', 1, true), 'der Fehler wird gemeldet')
    T.eq(H.bridge.players[LENA].bank, before - 3500)
    Config.Hooks.onApproved = function() end
end)

T.test('Staff: Eingriff in das Register mit Begründung, Hinweise zur Schlussprüfung aus echten Daten', function()
    cast()
    S.put('entities', { id = 'E-7', kind = 'unternehmen', regNo = 'HRA 1007', name = 'Test Bau', legalForm = 'einzel', branch = 'handwerk', status = 'aktiv', owner = 'Lena Brandt', founded = IC.now(), validUntil = IC.now() + 90 * DAY, memberCount = 1,
        members = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber', share = 100 } }, conditions = {}, history = {}, ooc = { category = 'untergrund' } })
    T.fails(H.call(LENA, 'gewerbeamt', 'staffEntityStatus', { id = 'E-7', status = 'gesperrt', reason = 'Regelverstoß wiederholt' }), 'nicht befugt')
    T.fails(H.staff('staffEntityStatus', { id = 'E-9', status = 'gesperrt', reason = 'Regelverstoß wiederholt' }), 'nicht gefunden')
    T.fails(H.staff('staffEntityStatus', { id = 'E-7', status = 'unsinn', reason = 'Regelverstoß wiederholt' }), 'Unbekannter Status')
    T.fails(H.staff('staffEntityStatus', { id = 'E-7', status = 'gesperrt', reason = 'kurz' }), 'Begründung')
    T.fails(H.staff('staffEntityStatus', { id = 'E-7', status = 'aktiv', reason = 'Alles in Ordnung hier' }), 'bereits')

    T.succeeds(H.staff('staffEntityStatus', { id = 'E-7', status = 'gesperrt', reason = 'Wiederholte Regelverstöße im Rollenspiel.' }))
    local e = S.get('entities', 'E-7')
    T.eq(e.status, 'gesperrt'); T.ok(e.history[#e.history].reason:find('aktiv → gesperrt', 1, true), 'Statuswechsel steht in der Historie')
    T.eq(e.history[#e.history].by, 'Registerführung', 'IC tritt die Registerführung auf, nie der Staff')
    T.ok(H.lastNotice(LENA, 'Registerführung'), 'Inhaberin wird informiert'); T.notok(H.lastNotice(LENA, 'Admin'), 'ohne Namen des Staffs')
    T.ok(IC.auditLog[1].actor:find('Admin', 1, true) and IC.auditLog[1].action == 'Eingriff Register', 'das Protokoll nennt den Staff')
    T.succeeds(H.staff('staffEntityStatus', { id = 'E-7', status = 'aktiv', reason = 'Nach Rücksprache wieder zugelassen.' }))
    T.eq(e.status, 'aktiv')
    T.succeeds(H.staff('staffEntityStatus', { id = 'E-7', status = 'aufgeloest', reason = 'Endgültige Schließung wegen Verstoß.' }))
    T.eq(e.status, 'aufgeloest'); T.ok(e.dissolvedAt)
    T.fails(H.staff('staffEntityStatus', { id = 'E-7', status = 'aktiv', reason = 'Doch wieder zurück bitte.' }), 'aufgelöst')

    -- Übersicht: der Staff sieht die Einträge mit OOC-Angaben, Beamte nie
    local ov = T.succeeds(H.staff('bootstrap', { app = 'staff' }))
    T.eq(#ov.staff.entities, 1); T.eq(ov.staff.entities[1].ooc.category, 'untergrund')
    duty(KELLER)
    local off = T.succeeds(H.call(KELLER, 'beamte', 'bootstrap', { app = 'beamte' }))
    T.notok(off.register[1].ooc, 'Beamte sehen keine OOC-Angaben')

    -- Hinweise zur Schlussprüfung
    S.put('entities', { id = 'E-8', kind = 'unternehmen', regNo = 'HRA 1008', name = 'Zweite Firma', status = 'aktiv', members = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber' } }, conditions = {}, history = {} })
    local a = { id = 'A-90', caseNo = 'GA-2025-0090', kind = 'fraktion', legalForm = 'ev', name = 'Polizeifreunde e.V.', status = 'staff_pruefung', applicant = { charId = 'c-lena', name = 'Lena Brandt' },
        founders = { { charId = 'c-lena', name = 'Lena Brandt', role = 'vorsitz' }, { charId = 'c-tom', name = 'Tom Becker', role = 'mitglied' } }, events = {}, fees = { apply = 0, register = 0, capital = 0, paid = true } }
    S.put('applications', a)
    local hints = IC.staff.gateHints(a)
    T.eq(#hints, 3)
    T.eq(hints[1].ok, false); T.ok(hints[1].text:find('gesperrt', 1, true), 'Sperrliste: ' .. hints[1].text)
    T.eq(hints[2].ok, false); T.ok(hints[2].text:find('HRA 1008', 1, true) and hints[2].text:find('Lena Brandt', 1, true), 'Beteiligung: ' .. hints[2].text)
    T.eq(hints[3].ok, false); T.ok(hints[3].text:find('2 Gründungsmitglieder', 1, true) and hints[3].text:find('mindestens 3', 1, true), 'Mitgliederzahl: ' .. hints[3].text)
    a.name, a.founders = 'Skater Club e.V.', { { charId = 'c-tom', name = 'Tom Becker', role = 'vorsitz' }, { charId = 'c-marco', name = 'Marco Rossi', role = 'mitglied' }, { charId = 'c-anna', name = 'Anna K.', role = 'mitglied' } }
    hints = IC.staff.gateHints(a)
    T.eq(hints[1].ok, true); T.eq(hints[2].ok, true); T.eq(hints[3].ok, true)
end)

T.test('Bestandsschutz: Erinnerung nach 14 Tagen, auf Wunsch "ruhend", Bestätigung macht wieder aktiv', function()
    cast()
    IC.register.importLegacy({ { ref = 'b1', name = 'Lenas Kiosk', legalForm = 'einzel', branch = 'handel', members = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber' } } } }, 'Test')
    local e = S.list('entities')[1]
    local function reminders() local n = 0; for _, x in ipairs(H.bridge.notices) do if x.text:find('bestätigen Sie die Daten', 1, true) then n = n + 1 end end return n end
    IC.register.tickLegacy()
    T.eq(reminders(), 0, 'nach dem Import noch keine Erinnerung')
    H.advance(15 * DAY)
    IC.register.tickLegacy(); IC.register.tickLegacy()
    T.eq(reminders(), 1, 'genau eine Erinnerung nach 14 Tagen'); T.eq(e.status, 'aktiv', 'ohne restAfterDays bleibt der Eintrag aktiv')
    H.advance(60 * DAY)
    IC.register.tickLegacy()
    T.eq(e.status, 'aktiv', 'Standard: nur Hinweis, keine Sanktion')

    Config.Legacy.restAfterDays = 56
    IC.register.tickLegacy()
    T.eq(e.status, 'ruhend'); T.eq(e.legacyRested, true)
    T.succeeds(H.call(LENA, 'gewerbeamt', 'legacyConfirm', { id = e.id }))
    T.eq(e.status, 'aktiv', 'die Bestätigung hebt das Ruhen auf'); T.eq(e.legacyConfirmed, true); T.eq(e.legacyRested, nil)
    IC.register.tickLegacy()
    T.eq(e.status, 'aktiv')
    Config.Legacy.restAfterDays = nil
end)
