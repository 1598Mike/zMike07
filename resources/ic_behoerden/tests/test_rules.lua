local T = ...
local R, U = IC.rules, IC.util
local MIN, HOUR, DAY = R.MIN, R.HOUR, R.DAY

-- ---------------------------------------------------------------- Gebühren
T.test('Gebühren: Einzelunternehmen $1.000, GmbH $3.500 plus Kapital, Branchenfaktor wirkt', function()
    local e = R.fees('einzel', 'handwerk')
    T.eq(e.apply, 250); T.eq(e.register, 750); T.eq(e.payNow, 1000); T.eq(e.refundable, 750)
    local g = R.fees('gmbh', 'transport')
    T.eq(g.apply, 800); T.eq(g.register, 2700); T.eq(g.capital, 25000); T.eq(g.payNow, 28500); T.eq(g.refundable, 27700)
    local s = R.fees('gbr', 'sicherheit')          -- Faktor 1,5
    T.eq(s.apply, 600); T.eq(s.register, 1650)
    local f = R.fees('gmbh', 'finanz')             -- Faktor 2
    T.eq(f.apply, 1600); T.eq(f.register, 5400)
    local o = R.fees('ev', nil)
    T.eq(o.payNow, 1200)
    T.eq(R.fees('gibtsnicht', nil), nil)
end)

T.test('Staff-Gate: sensible Branche oder Untergrund-Kennzeichen', function()
    T.ok(R.staffGateNeeded({ branch = 'sicherheit' }))
    T.ok(R.staffGateNeeded({ branch = 'finanz' }))
    T.notok(R.staffGateNeeded({ branch = 'gastro' }))
    T.ok(R.staffGateNeeded({ ooc = { category = 'untergrund' } }))
    T.notok(R.staffGateNeeded({ ooc = { category = 'legal' } }))
end)

-- ---------------------------------------------------------------- Namensprüfung
local ctx = {
    blacklist = { { term = 'polizei', reason = 'Staatsfraktion' }, { term = 'coca cola', reason = 'Reale Marke' } },
    entities = {
        { name = "Lena's Kiosk", status = 'aktiv', regNo = 'HRA 1042' },
        { name = 'Nordwacht Security GmbH', status = 'aktiv', regNo = 'HRB 0341' },
        { name = 'Alte Bar', status = 'aufgeloest', regNo = 'HRA 0001' },
    },
    openApps = { { id = 'A-1', name = 'Hafenbar Santa Maria', caseNo = 'GA-2026-0138' } },
}

local function codes(res) local out = {} for _, i in ipairs(res.issues) do out[#out + 1] = i.level .. ':' .. i.code end return table.concat(out, ',') end

T.test('Namensprüfung: freier Name, Zusatz wird ergänzt', function()
    local r = R.nameCheck('Mustermann Bau', 'gmbh', ctx)
    T.ok(r.ok); T.eq(r.display, 'Mustermann Bau GmbH'); T.eq(r.normalized, 'mustermannbau')
    T.eq(R.nameCheck('Mustermann Bau GmbH', 'gmbh', ctx).display, 'Mustermann Bau GmbH')
    T.eq(R.nameCheck('Skater Club', 'ev', ctx).display, 'Skater Club e.V.')
    T.eq(R.nameCheck('Skater Club', 'ig', ctx).display, 'Skater Club')
end)

T.test('Namensprüfung: Länge, Zeichen und zu wenige Buchstaben', function()
    T.eq(codes(R.nameCheck('ab', 'einzel', ctx)), 'error:short')
    T.eq(codes(R.nameCheck(string.rep('a', 41), 'einzel', ctx)), 'error:long')
    T.ok(codes(R.nameCheck('Bar <b>', 'einzel', ctx)):find('chars', 1, true))
    T.eq(codes(R.nameCheck('2222', 'einzel', ctx)), 'error:short')      -- Ziffern ohne Buchstaben-Entsprechung: zu wenige Buchstaben
    T.eq(R.nameCheck('1234', 'einzel', ctx).normalized, 'iea', 'Leetspeak macht aus 1, 3, 4 die Buchstaben i, e, a')
    T.ok(R.nameCheck('Bärenstark', 'einzel', ctx).ok, 'Umlaute sind erlaubt')
    T.eq(R.nameCheck(string.rep('ä', 40), 'einzel', ctx).ok, true, '40 Umlaute sind 40 Zeichen')
    T.eq(codes(R.nameCheck(string.rep('ä', 41), 'einzel', ctx)), 'error:long')
end)

T.test('Namensprüfung: Sperrliste ignoriert Schreibweise, Umlaute und Leetspeak', function()
    T.ok(codes(R.nameCheck('Polizei Pizza', 'einzel', ctx)):find('blacklist', 1, true))
    T.ok(codes(R.nameCheck('P0L1ZE1 Pizza', 'einzel', ctx)):find('blacklist', 1, true))
    T.ok(codes(R.nameCheck('Meine Coca-Cola Bar', 'einzel', ctx)):find('blacklist', 1, true))
    T.ok(R.nameCheck('Zolizei', 'einzel', ctx).ok)
end)

T.test('Namensprüfung: vergeben, ähnlich, reserviert, aufgelöst ist frei', function()
    T.ok(codes(R.nameCheck('Lenas Kiosk', 'einzel', ctx)):find('taken', 1, true))
    T.ok(codes(R.nameCheck('LENA S KIOSK', 'einzel', ctx)):find('taken', 1, true))
    T.ok(codes(R.nameCheck('Nordwacht Security', 'gmbh', ctx)):find('taken', 1, true), 'Rechtsformzusatz wird ignoriert')
    T.ok(codes(R.nameCheck('Nordwach Security', 'gmbh', ctx)):find('error:similar', 1, true), 'Abstand 1 blockiert')
    T.eq(codes(R.nameCheck('Nordwacht Securitee', 'gmbh', ctx)), 'warn:similar', 'Abstand 2 warnt nur')
    T.ok(codes(R.nameCheck('Hafenbar Santa Maria', 'einzel', ctx)):find('reserved', 1, true))
    T.ok(R.nameCheck('Hafenbar Santa Maria', 'einzel', { openApps = ctx.openApps, ignoreAppId = 'A-1' }).ok, 'eigener Antrag blockiert sich nicht')
    T.ok(R.nameCheck('Alte Bar', 'einzel', ctx).ok, 'aufgelöste Einträge geben den Namen frei')
end)

-- ---------------------------------------------------------------- Voraussetzungen
T.test('Voraussetzungen: alles erfüllt, dann je ein Verstoß', function()
    local p = { hasId = true, age = 29, playHours = 63 }
    local base = { isMe = true, openApps = 1, companies = 1, orgs = 0 }
    T.ok(R.eligibility(p, 'unternehmen', base).ok)
    T.notok(R.eligibility({ hasId = false, age = 29, playHours = 63 }, 'unternehmen', base).ok)
    T.notok(R.eligibility({ hasId = true, age = 17, playHours = 63 }, 'unternehmen', base).ok)
    T.notok(R.eligibility({ hasId = true, age = 29, playHours = 9 }, 'unternehmen', base).ok)
    T.notok(R.eligibility(p, 'unternehmen', { isMe = true, openApps = 2, companies = 0 }).ok, 'zwei offene Anträge sind das Limit')
    T.notok(R.eligibility(p, 'unternehmen', { isMe = true, openApps = 0, companies = 2 }).ok, 'zwei Unternehmen sind das Limit')
    T.ok(R.eligibility(p, 'fraktion', { isMe = true, openApps = 0, companies = 2, orgs = 0 }).ok, 'Unternehmenslimit gilt nicht für Organisationen')
    T.notok(R.eligibility(p, 'fraktion', { isMe = true, openApps = 0, orgs = 1 }).ok)
    T.notok(R.eligibility(p, 'unternehmen', { isMe = true, openApps = 0, companies = 0, banUntil = 123 }).ok, 'Terminsperre')
    T.ok(R.eligibility(p, 'unternehmen', {}).ok, 'Mitgründer: nur Ausweis, Alter, Spielzeit')
end)

-- ---------------------------------------------------------------- Statusübergänge
T.test('Statusübergänge folgen dem Konzept', function()
    T.ok(R.canTransition('entwurf', 'eingereicht'))
    T.ok(R.canTransition('eingereicht', 'vorpruefung_ok'))
    T.ok(R.canTransition('vorpruefung_ok', 'termin_gebucht'))
    T.ok(R.canTransition('termin_gebucht', 'termin_laeuft'))
    T.ok(R.canTransition('termin_laeuft', 'staff_pruefung'))
    T.ok(R.canTransition('staff_pruefung', 'genehmigt'))
    T.ok(R.canTransition('abgelehnt', 'einspruch'))
    T.notok(R.canTransition('eingereicht', 'genehmigt'), 'ohne Termin keine Genehmigung')
    T.notok(R.canTransition('genehmigt', 'abgelehnt'), 'genehmigt ist endgültig')
    T.notok(R.canTransition('abgelaufen', 'eingereicht'))
    T.notok(R.canTransition('abgelehnt', 'genehmigt'), 'nach Ablehnung nur über den Einspruch')
    T.notok(R.canTransition('entwurf', 'vorpruefung_ok'))
end)

-- ---------------------------------------------------------------- Slots (Kernregel: kein Beamter, kein Termin)
local NOW = 1760000000000 - (1760000000000 % DAY) + 18 * HOUR      -- 18:00 UTC an einem Tag
local DAY0 = NOW - (NOW % DAY)
local typeVU = R.apptType('vorstellung_unternehmen')
local typeBeratung = R.apptType('beratung')
local typeEinspruch = R.apptType('einspruch')

local function slotCtx(over)
    local c = {
        now = NOW,
        liveOfficials = {},
        officeHours = {},
        rankOf = function(id) return ({ keller = 'amtsleiter', yilmaz = 'sachbearbeiter', novak = 'anwaerter' })[id] end,
        appointments = {},
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

T.test('Slots: ohne Beamte im Dienst und ohne Sprechzeit gibt es keinen Termin', function()
    T.eq(#R.slots(typeVU, DAY0, DAY0 + DAY, slotCtx()), 0)
    T.eq(#R.slots(typeBeratung, DAY0, DAY0 + DAY, slotCtx()), 0)
end)

T.test('Slots: mit einem Beamten im Dienst gibt es Live-Termine für die nächsten 60 Minuten', function()
    local s = R.slots(typeVU, DAY0, DAY0 + DAY, slotCtx({ liveOfficials = { { id = 'yilmaz', rank = 'sachbearbeiter' } } }))
    -- ab 18:10 (Vorlaufzeit), Raster 15 Minuten: 18:15 bis 19:00
    T.eq(s[1].start, NOW + 15 * MIN); T.eq(s[#s].start, NOW + 60 * MIN)
    T.eq(#s, 4)
    T.eq(s[1].source, 'live'); T.eq(s[1].cap, 1); T.eq(s[1].free, 1)
    T.eq(s[1]['end'] - s[1].start, 30 * MIN)
end)

T.test('Slots: Vorlaufzeit wird eingehalten', function()
    local s = R.slots(typeBeratung, DAY0, DAY0 + DAY, slotCtx({ liveOfficials = { { id = 'keller', rank = 'amtsleiter' } } }))
    T.ok(s[1].start >= NOW + 10 * MIN, 'frühestens 10 Minuten vor Beginn buchbar')
    T.eq(s[1].start, NOW + 15 * MIN)
end)

T.test('Slots: Rang entscheidet, wer einen Termin bedienen darf', function()
    local onlyNovak = slotCtx({ liveOfficials = { { id = 'novak', rank = 'anwaerter' } } })
    T.eq(#R.slots(typeVU, DAY0, DAY0 + DAY, onlyNovak), 0, 'Anwärter dürfen keine Vorstellung führen')
    T.ok(#R.slots(typeBeratung, DAY0, DAY0 + DAY, onlyNovak) > 0, 'Beratung ist ab Anwärter erlaubt')
    local sach = slotCtx({ liveOfficials = { { id = 'yilmaz', rank = 'sachbearbeiter' } } })
    T.eq(#R.slots(typeEinspruch, DAY0, DAY0 + DAY, sach), 0, 'Einspruch braucht einen Amtsleiter')
    local leiter = slotCtx({ liveOfficials = { { id = 'keller', rank = 'amtsleiter' } } })
    T.ok(#R.slots(typeEinspruch, DAY0, DAY0 + DAY, leiter) > 0)
end)

T.test('Slots: Kapazität ist die Zahl der Beamten, Buchungen verbrauchen sie', function()
    local two = slotCtx({ liveOfficials = { { id = 'keller', rank = 'amtsleiter' }, { id = 'yilmaz', rank = 'sachbearbeiter' } } })
    local s = R.slots(typeVU, DAY0, DAY0 + DAY, two)
    T.eq(s[1].cap, 2); T.eq(s[1].free, 2)
    two.appointments = { { id = 'T-1', start = NOW + 15 * MIN, minutes = 30, status = 'gebucht' } }
    s = R.slots(typeVU, DAY0, DAY0 + DAY, two)
    T.eq(s[1].free, 1, 'ein Termin belegt einen der zwei Beamten')
    T.eq(s[2].free, 1, 'auch der überlappende Slot um 18:30')
    T.eq(s[3].free, 2, 'um 18:45 ist der Termin vorbei')
    two.appointments[2] = { id = 'T-2', start = NOW + 30 * MIN, minutes = 30, status = 'eingecheckt' }
    s = R.slots(typeVU, DAY0, DAY0 + DAY, two)
    T.eq(s[2].free, 0, 'beide Beamte sind um 18:30 belegt')
    two.appointments[1].status = 'abgesagt'
    two.appointments[2].status = 'abgesagt'
    s = R.slots(typeVU, DAY0, DAY0 + DAY, two)
    T.eq(s[1].free, 2, 'abgesagte Termine geben den Slot frei')
    two.appointments[2].status = 'nicht_erschienen'
    T.eq(R.slots(typeVU, DAY0, DAY0 + DAY, two)[2].free, 2, 'auch versäumte Termine belegen nichts mehr')
end)

T.test('Slots: Verschieben ignoriert den eigenen Termin', function()
    local c = slotCtx({ liveOfficials = { { id = 'yilmaz', rank = 'sachbearbeiter' } }, appointments = { { id = 'T-1', start = NOW + 15 * MIN, minutes = 30, status = 'gebucht' } } })
    T.eq(R.slots(typeVU, DAY0, DAY0 + DAY, c)[1].free, 0)
    c.excludeId = 'T-1'
    T.eq(R.slots(typeVU, DAY0, DAY0 + DAY, c)[1].free, 1)
end)

T.test('Slots: Sprechzeiten machen spätere Termine buchbar, auch ohne Beamte im Dienst', function()
    local c = slotCtx({ officeHours = { { officialId = 'yilmaz', start = DAY0 + DAY + 18 * HOUR, finish = DAY0 + DAY + 20 * HOUR } } })
    T.eq(#R.slots(typeVU, DAY0, DAY0 + DAY, c), 0, 'heute nichts')
    local s = R.slots(typeVU, DAY0 + DAY, DAY0 + 2 * DAY, c)
    T.eq(s[1].start, DAY0 + DAY + 18 * HOUR); T.eq(s[1].source, 'plan')
    T.eq(s[#s].start, DAY0 + DAY + 19 * HOUR + 30 * MIN, 'der letzte Termin endet mit der Sprechzeit')
    T.eq(#s, 7, 'von 18:00 bis 19:30 im 15-Minuten-Raster')
end)

T.test('Slots: Sprechzeit eines Beamten, der den Job verlassen hat, zählt nicht', function()
    local c = slotCtx({ officeHours = { { officialId = 'weg', start = DAY0 + DAY + 18 * HOUR, finish = DAY0 + DAY + 20 * HOUR } } })
    T.eq(#R.slots(typeVU, DAY0 + DAY, DAY0 + 2 * DAY, c), 0)
end)

T.test('Slots: derselbe Beamte zählt in Live-Termin und Sprechzeit nur einmal', function()
    local c = slotCtx({
        liveOfficials = { { id = 'yilmaz', rank = 'sachbearbeiter' } },
        officeHours = { { officialId = 'yilmaz', start = NOW, finish = NOW + 3 * HOUR } },
    })
    T.eq(R.slots(typeVU, DAY0, DAY0 + DAY, c)[1].cap, 1)
end)

T.test('Slots: Modus "plan" ignoriert Live-Beamte, Modus "live" ignoriert Sprechzeiten', function()
    local saved = Config.Appointments.mode
    local both = slotCtx({
        liveOfficials = { { id = 'yilmaz', rank = 'sachbearbeiter' } },
        officeHours = { { officialId = 'keller', start = DAY0 + DAY + 18 * HOUR, finish = DAY0 + DAY + 20 * HOUR } },
    })
    Config.Appointments.mode = 'plan'
    T.eq(#R.slots(typeVU, DAY0, DAY0 + DAY, both), 0)
    T.ok(#R.slots(typeVU, DAY0 + DAY, DAY0 + 2 * DAY, both) > 0)
    Config.Appointments.mode = 'live'
    T.ok(#R.slots(typeVU, DAY0, DAY0 + DAY, both) > 0)
    T.eq(#R.slots(typeVU, DAY0 + DAY, DAY0 + 2 * DAY, both), 0)
    Config.Appointments.mode = saved
end)

T.test('Slots: Live-Termine gibt es nur im Horizont von 60 Minuten', function()
    local s = R.slots(typeBeratung, DAY0, DAY0 + DAY, slotCtx({ liveOfficials = { { id = 'keller', rank = 'amtsleiter' } } }))
    T.ok(s[#s].start <= NOW + 60 * MIN)
    for _, x in ipairs(s) do T.eq(x.source, 'live') end
end)

-- ---------------------------------------------------------------- Check-in
T.test('Check-in: Fenster von 10 Minuten vor bis 10 Minuten nach Beginn', function()
    local ap = { start = NOW + 60 * MIN, status = 'gebucht', attendees = { { charId = 'c1', checkedIn = false } } }
    T.ok(R.checkinState(ap, 'c1', NOW).early, 'zu früh')
    T.ok(R.checkinState(ap, 'c1', ap.start - 10 * MIN).can, 'ab 10 Minuten vorher')
    T.ok(R.checkinState(ap, 'c1', ap.start + 10 * MIN).can, 'bis 10 Minuten danach')
    T.ok(R.checkinState(ap, 'c1', ap.start + 10 * MIN + 1).late, 'danach geschlossen')
    T.notok(R.checkinState(ap, 'fremd', ap.start).can, 'Fremde können nicht einchecken')
    ap.attendees[1].checkedIn = true
    T.ok(R.checkinState(ap, 'c1', ap.start).done)
end)

-- ---------------------------------------------------------------- Pflichtteilnehmer und Checkliste
T.test('Pflichtteilnehmer: Leitung und ab 25 % Anteil, bei Organisationen alle', function()
    local app = { kind = 'unternehmen', founders = {
        { charId = 'a', role = 'geschaeftsfuehrer', share = 40 }, { charId = 'b', role = 'gesellschafter', share = 35 },
        { charId = 'c', role = 'gesellschafter', share = 25 }, { charId = 'd', role = 'gesellschafter', share = 0 } } }
    local m = R.mandatory(app)
    T.eq(table.concat(m, ','), 'a,b,c')
    local org = { kind = 'fraktion', founders = { { charId = 'x', role = 'vorsitz' }, { charId = 'y', role = 'mitglied' } } }
    T.eq(table.concat(R.mandatory(org), ','), 'x,y')
end)

T.test('Checkliste: nur Pflichtpunkte zählen, optionale dürfen fehlen', function()
    local all = {}
    for _, i in ipairs(Config.Checklists.vorstellung_unternehmen) do all[i.key] = true end
    T.eq(#R.checklistMissing('vorstellung_unternehmen', all), 0)
    all.property = nil; all.authority = nil
    T.eq(#R.checklistMissing('vorstellung_unternehmen', all), 0, 'Standort und Fachbehörde sind optional')
    all.fees = nil
    local m = R.checklistMissing('vorstellung_unternehmen', all)
    T.eq(#m, 1); T.eq(m[1].key, 'fees')
end)

-- ---------------------------------------------------------------- Entwurf: Bereinigung und Prüfung
local function goodDraft()
    return {
        kind = 'unternehmen', legalForm = 'einzel', branch = 'handwerk', name = 'Mustermann Bau',
        founders = { { charId = 'c1', name = 'Lena Brandt', role = 'inhaber', share = 100, consent = 'self' } },
        property = { mode = 'mobil' },
        concept = { idea = string.rep('Wir bauen gut. ', 8) }, statute = {},
    }
end
-- Wie die Domäne: Die Zustimmung setzt der Server anhand der Einladungen, nie der Client.
local function prep(d, pendingFrom)
    local c = R.sanitizeDraft(d)
    for i, f in ipairs(c.founders) do f.consent = (i == 1) and 'self' or ((pendingFrom and i >= pendingFrom) and 'pending' or 'ok') end
    return c
end
local function vctx(over)
    local c = {
        elig = { ok = true, checks = {} }, nameResult = { ok = true, issues = {} },
        branchUsed = function() return 0 end, branchCap = function(b) return b.cap end, propertyTaken = function() return false end,
        bank = 184250, undergroundAllowed = true,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end
local function fields(errs) local o = {} for _, e in ipairs(errs) do o[#o + 1] = e.field end return table.concat(o, ',') end

T.test('Entwurf: ein vollständiger Antrag besteht die Prüfung', function()
    T.eq(#R.validateDraft(prep(goodDraft()), vctx()), 0)
end)

T.test('Entwurf: typische Mängel werden einzeln gemeldet', function()
    local d = goodDraft(); d.concept.idea = 'zu kurz'
    T.eq(fields(R.validateDraft(prep(d), vctx())), 'concept')
    d = goodDraft(); d.branch = nil
    T.ok(fields(R.validateDraft(prep(d), vctx())):find('branch', 1, true))
    d = goodDraft(); d.founders[1].share = 60
    T.ok(fields(R.validateDraft(prep(d), vctx())):find('founders', 1, true))
    d = goodDraft(); d.property = { mode = nil }
    T.ok(fields(R.validateDraft(prep(d), vctx())):find('property', 1, true))
    d = goodDraft()
    T.ok(fields(R.validateDraft(prep(d), vctx({ bank = 999 }))):find('bank', 1, true), 'Kontostand reicht nicht')
    T.eq(#R.validateDraft(prep(d), vctx({ bank = 0, resubmit = true })), 0, 'bei Nachbesserung wird nichts erneut bezahlt')
    T.ok(fields(R.validateDraft(prep(d), vctx({ branchUsed = function() return 8 end }))):find('branch', 1, true), 'Branche ausgelastet')
    T.eq(#R.validateDraft(prep(d), vctx({ branchUsed = function() return 8 end, resubmit = true })), 0, 'Nachbesserung behält ihren Platz')
end)

T.test('Entwurf: Rollen und Gründerzahl werden serverseitig geprüft', function()
    local d = goodDraft(); d.legalForm = 'gbr'
    T.ok(fields(R.validateDraft(prep(d), vctx())):find('founders', 1, true), 'GbR braucht 2 Gründer')
    d.founders[2] = { charId = 'c2', name = 'Tom Becker', role = 'gesellschafter', share = 50, consent = 'ok' }
    d.founders[1].share = 50; d.founders[1].role = 'geschaeftsfuehrer'
    T.eq(#R.validateDraft(prep(d), vctx()), 0)
    T.ok(#R.validateDraft(prep(d, 2), vctx()) > 0, 'ohne Zustimmung geht es nicht')
    d.founders[2].role = 'hacker'
    T.ok(#R.validateDraft(prep(d), vctx()) > 0, 'unbekannte Rolle')
    d.founders[2].role = 'gesellschafter'; d.founders[2].charId = 'c1'
    T.ok(#R.validateDraft(prep(d), vctx()) > 0, 'doppelter Gründer')
    d = goodDraft(); d.kind = 'fraktion'
    T.ok(#R.validateDraft(prep(d), vctx()) > 0, 'Rechtsform passt nicht zur Art')
end)

T.test('Entwurf: Organisation braucht Vorsitz, Zweck, Mindestzahl und OOC-Angaben', function()
    local d = {
        kind = 'fraktion', legalForm = 'ev', name = 'Skater Club',
        founders = {
            { charId = 'c1', name = 'A', role = 'vorsitz', consent = 'self' },
            { charId = 'c2', name = 'B', role = 'stellv', consent = 'ok' },
            { charId = 'c3', name = 'C', role = 'mitglied', consent = 'ok' } },
        property = { mode = 'mobil' }, statute = { purpose = string.rep('Wir skaten zusammen. ', 6) }, ooc = { category = 'untergrund', note = 'x', members = '10' },
    }
    T.eq(#R.validateDraft(prep(d), vctx()), 0)
    T.ok(fields(R.validateDraft(prep(d), vctx({ undergroundAllowed = false }))):find('ooc', 1, true), 'Untergrund-Weg abgeschaltet')
    d.founders[2].role = 'vorsitz'
    T.ok(#R.validateDraft(prep(d), vctx()) > 0, 'zwei Vorsitzende')
    d.founders[2].role = 'stellv'; d.founders[3] = nil
    T.ok(#R.validateDraft(prep(d), vctx()) > 0, 'nur 2 von 3 Gründungsmitgliedern')
    d.founders[3] = { charId = 'c3', name = 'C', role = 'mitglied', consent = 'ok' }; d.ooc = nil
    T.ok(fields(R.validateDraft(prep(d), vctx())):find('ooc', 1, true))
end)

T.test('Entwurf: Standort, Pflicht und belegte Immobilie', function()
    local d = goodDraft(); d.branch = 'gastro'; d.property = { mode = 'mobil' }
    T.ok(fields(R.validateDraft(prep(d), vctx())):find('property', 1, true), 'Gastronomie braucht einen festen Standort')
    d.property = { mode = 'immobilie', id = 'P-02' }
    T.eq(#R.validateDraft(prep(d), vctx()), 0)
    T.ok(fields(R.validateDraft(prep(d), vctx({ propertyTaken = function() return true end }))):find('property', 1, true))
    local prev = { property = { id = 'P-02' } }
    T.eq(#R.validateDraft(prep(d), vctx({ propertyTaken = function() return true end, prev = prev })), 0, 'die eigene reservierte Immobilie bleibt frei')
end)

T.test('sanitizeDraft: feste Typen, Längen, keine fremden Felder', function()
    local dirty = {
        kind = 'sonstwas', legalForm = 12345, name = string.rep('x', 500), evil = 'DROP TABLE',
        founders = { { charId = 'c1', name = 'A', role = 'inhaber', share = '60', consent = 'ok', isAdmin = true } },
        concept = { idea = 'Zeile 1\nZeile 2\r\n' .. string.rep('ä', 3000) },
        ooc = { category = 'irgendwas' },
    }
    local c = R.sanitizeDraft(dirty)
    T.eq(c.kind, 'unternehmen'); T.eq(c.legalForm, '12345'); T.eq(#c.name, 80)
    T.eq(c.evil, nil); T.eq(c.founders[1].isAdmin, nil); T.eq(c.founders[1].share, 60)
    T.eq(c.founders[1].consent, nil, 'die Zustimmung kommt nie vom Client')
    T.ok(c.concept.idea:find('\n', 1, true), 'Zeilenumbrüche bleiben erhalten')
    T.ok(utf8.len(c.concept.idea) ~= nil, 'gekürzter Text ist gültiges UTF-8')
    T.ok(#c.concept.idea <= 2000)
    T.eq(c.ooc.category, 'legal')
    T.eq(R.sanitizeDraft('kein Tisch').kind, 'unternehmen')
end)
