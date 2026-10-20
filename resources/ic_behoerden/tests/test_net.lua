local T, H = ...
local S = IC.store

-- Attrappen für das, was FiveM bereitstellt ----------------------------------------
json = json or dofile('tests/json.lua')
local handlers, commands, sent, aces, timers = {}, {}, {}, {}, {}
local resourceFiles = {}
local gameTimer = 0

RegisterNetEvent = function(name, fn) handlers[name] = fn end
AddEventHandler = function(name, fn) handlers[name] = fn end
RegisterCommand = function(name, fn) commands[name] = fn end
TriggerClientEvent = function(name, target, ...) sent[#sent + 1] = { name = name, target = target, args = { ... } } end
GetGameTimer = function() return gameTimer end
IsPlayerAceAllowed = function(src, ace) return aces[src] == true and ace == Config.Staff.ace end
GetPlayerName = function(src) local p = H.bridge.players[src]; return p and p.name or nil end
GetCurrentResourceName = function() return 'ic_behoerden' end
LoadResourceFile = function(_, path) return resourceFiles[path] end
SetTimeout = function(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end
CreateThread = function() end
Wait = function() end

dofile('server/net.lua')
local N = IC.net

-- Orte aus der Config: Terminal am Gewerbeamt
local LOC = Config.Locations.gewerbeamt[1]
local DESK = Config.Locations.beamte[1]
local function at(loc, dx) return vector3(loc.coords.x + (dx or 0), loc.coords.y, loc.coords.z) end

local LENA, KELLER, ADMIN = 1, 10, 99

local function cast()
    H.reset()
    handlers, sent, timers, aces, gameTimer = handlers, {}, {}, {}, 0
    N.sessions, N.calls, N.seen = {}, {}, {}
    IC.started = true
    H.player(LENA, { charId = 'c-lena', name = 'Lena Brandt', coords = at(LOC) })
    H.player(KELLER, { charId = 'c-keller', name = 'Dr. Keller', rank = 'amtsleiter', coords = at(DESK) })
    H.player(ADMIN, { charId = 'c-admin', name = 'Admin Alex', coords = at(LOC, 40) })
end

-- Löst ein Netzwerkereignis aus, wie FiveM es tut (source ist während des Aufrufs gesetzt)
local function fire(src, name, ...)
    source = src
    handlers[name](...)
    source = nil
end

local function lastSent(name, target)
    for i = #sent, 1, -1 do
        if sent[i].name == name and (target == nil or sent[i].target == target) then return sent[i] end
    end
end

local function call(src, reqId, name, data)
    fire(src, 'ic_behoerden:server:call', reqId, name, data)
    local r = lastSent('ic_behoerden:client:reply', src)
    T.ok(r and r.args[1] == reqId, 'Antwort mit derselben Anfrage-Nummer')
    return r.args[2]
end

-- ===========================================================================================
T.test('Netz: Öffnen nur am Terminal, Antworten tragen die Anfrage-Nummer', function()
    cast()
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    local o = lastSent('ic_behoerden:client:open', LENA)
    T.ok(o and o.args[1] == 'gewerbeamt', 'Oberfläche wird geöffnet')

    local r = call(LENA, 7, 'bootstrap', { app = 'gewerbeamt' })
    T.eq(r.ok, true); T.eq(r.me.name, 'Lena Brandt')

    -- zu weit weg: kein Öffnen, Hinweis an den Spieler
    cast()
    H.bridge.players[LENA].coords = at(LOC, 30)
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    T.notok(lastSent('ic_behoerden:client:open', LENA))
    T.ok(H.lastNotice(LENA, 'zu weit'), 'Spieler erfährt den Grund')
end)

T.test('Netz: ohne Sitzung, mit unbekannter Aktion und mit falschen Typen passiert nichts', function()
    cast()
    local r = N.handle(LENA, 'bootstrap', { app = 'gewerbeamt' })
    T.fails(r, 'Terminal')
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    T.fails(N.handle(LENA, 'gibtEsNicht', {}), 'Unbekannte Aktion')
    -- Ereignisse mit falschen Typen werden ohne Antwort verworfen
    local before = #sent
    fire(LENA, 'ic_behoerden:server:call', 'x', 'bootstrap', {})
    fire(LENA, 'ic_behoerden:server:call', 1, 42, {})
    fire(LENA, 'ic_behoerden:server:open', 123, 1)
    T.eq(#sent, before)
    -- Daten, die keine Tabelle sind, gelten als leer
    T.eq(N.handle(LENA, 'bootstrap', 'unsinn').ok, true)
end)

T.test('Netz: Rolle prüft der Server, nicht der Client', function()
    cast()
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    -- Bürger-Sitzung darf keine Beamten-Aktion
    T.fails(N.handle(LENA, 'dutySet', { state = 'on', desk = 1 }), 'nicht befugt')
    T.fails(N.handle(LENA, 'staffSetting', { key = 'writtenProcedure', value = true }), 'nicht befugt')

    -- Beamten-Tablet: Bürger bekommen es nicht
    H.bridge.players[LENA].coords = at(DESK)
    fire(LENA, 'ic_behoerden:server:open', 'beamte', 1)
    T.notok(lastSent('ic_behoerden:client:open', LENA) and lastSent('ic_behoerden:client:open', LENA).args[1] == 'beamte')
    T.ok(H.lastNotice(LENA, 'nicht befugt'))

    -- Beamter am Schalter: ok. Verliert er den Job, endet die Sitzung beim nächsten Aufruf.
    fire(KELLER, 'ic_behoerden:server:open', 'beamte', 1)
    T.eq(lastSent('ic_behoerden:client:open', KELLER).args[1], 'beamte')
    T.succeeds(N.handle(KELLER, 'dutySet', { state = 'on', desk = 1 }))
    H.bridge.players[KELLER].rank = nil
    T.fails(N.handle(KELLER, 'dutySet', { state = 'off' }), 'nicht befugt')
    T.ok(lastSent('ic_behoerden:client:close', KELLER), 'Client wird zum Schließen aufgefordert')
    T.notok(N.sessions[KELLER])
end)

T.test('Netz: Entfernt sich der Spieler vom Terminal, endet die Sitzung', function()
    cast()
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    T.succeeds(N.handle(LENA, 'bootstrap', { app = 'gewerbeamt' }))
    H.bridge.players[LENA].coords = at(LOC, 50)
    T.fails(N.handle(LENA, 'bootstrap', { app = 'gewerbeamt' }), 'entfernt')
    T.ok(lastSent('ic_behoerden:client:close', LENA))
    T.fails(N.handle(LENA, 'bootstrap', { app = 'gewerbeamt' }), 'Terminal')
end)

T.test('Netz: Charakterwechsel beendet die Sitzung', function()
    cast()
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    H.bridge.players[LENA].charId = 'c-anderer'
    T.fails(N.handle(LENA, 'bootstrap', { app = 'gewerbeamt' }), 'gewechselt')
end)

T.test('Netz: Begrenzung der Aufrufe und der Datenmenge', function()
    cast()
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    local function limited(r) return r.error ~= nil and r.error:find('Zu viele', 1, true) ~= nil end
    local passed = 0
    for _ = 1, 60 do
        if not limited(N.handle(LENA, 'nameCheck', { name = 'Lenas Kiosk', legalForm = 'einzel' })) then passed = passed + 1 end
    end
    T.ok(passed <= 40 and passed >= 38, 'höchstens 40 Aufrufe je Fenster (erhalten: ' .. passed .. ')')
    T.fails(N.handle(LENA, 'nameCheck', {}), 'Zu viele')
    gameTimer = gameTimer + 11000
    T.notok(limited(N.handle(LENA, 'nameCheck', { name = 'Lenas Kiosk', legalForm = 'einzel' })), 'nach dem Fenster geht es wieder')

    gameTimer = gameTimer + 11000
    T.fails(N.handle(LENA, 'nameCheck', { name = string.rep('x', 50000), legalForm = 'einzel' }), 'zu groß')
end)

T.test('Netz: Staff-Panel nur mit ACE-Recht, das bei jedem Aufruf neu geprüft wird', function()
    cast()
    commands[Config.Staff.command](ADMIN)
    T.notok(lastSent('ic_behoerden:client:open', ADMIN), 'ohne Recht kein Panel')
    T.ok(H.lastNotice(ADMIN, 'nicht befugt'))

    aces[ADMIN] = true
    commands[Config.Staff.command](ADMIN)
    T.eq(lastSent('ic_behoerden:client:open', ADMIN).args[1], 'staff')
    local b = T.succeeds(N.handle(ADMIN, 'bootstrap', { app = 'staff' }))
    T.ok(b.staff, 'Staff-Übersicht ist dabei')
    T.succeeds(N.handle(ADMIN, 'staffSetting', { key = 'writtenProcedure', value = true }))
    aces[ADMIN] = false
    T.fails(N.handle(ADMIN, 'staffSetting', { key = 'writtenProcedure', value = true }), 'nicht befugt')

    -- Staff-Sitzung braucht keinen Ort, kann aber nicht über das Ereignis "open" erschlichen werden
    aces[ADMIN] = false
    fire(ADMIN, 'ic_behoerden:server:open', 'staff', 1)
    T.fails(N.handle(ADMIN, 'bootstrap', { app = 'staff' }), 'Terminal')
    -- Konsole kann das Panel nicht öffnen (die Meldung geht in die Konsole)
    local printed = T.capture(commands[Config.Staff.command], 0)
    T.ok(printed[1] and printed[1]:find('nur im Spiel', 1, true))
end)

T.test('Netz: Einladung beantworten läuft über den Server-Charakter', function()
    cast()
    H.player(2, { charId = 'c-tom', name = 'Tom Becker', coords = at(LOC) })
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    T.succeeds(N.handle(LENA, 'founderInvite', { charId = 'c-tom' }))
    T.eq(#H.bridge.invitesAsked, 1)
    fire(2, 'ic_behoerden:server:inviteAnswer', true)
    local st = N.handle(LENA, 'founderStatus', {})
    T.eq(st.statuses['c-tom'], 'ok')
    -- eine zweite Antwort ohne offene Einladung ändert nichts
    fire(2, 'ic_behoerden:server:inviteAnswer', false)
    T.eq(N.handle(LENA, 'founderStatus', {}).statuses['c-tom'], 'ok')
end)

T.test('Netz: Login zahlt Erstattungen aus und liefert fehlende Gewerbescheine nach, jeweils nur einmal', function()
    cast()
    S.put('refunds', { id = 'R-1', charId = 'c-lena', amount = 1250, reason = 'Test', ts = IC.now() })
    S.put('entities', { id = 'E-9', kind = 'unternehmen', regNo = 'HRA 1001', name = 'Test', status = 'aktiv', members = {}, history = {}, conditions = {} })
    S.put('chars', { id = 'c-lena', notifyOnDuty = false, pendingCerts = { 'E-9' } })
    local before = H.bridge.players[LENA].bank
    N.login(LENA)
    T.eq(H.bridge.players[LENA].bank, before + 1250, 'Erstattung ausgezahlt')
    T.eq(S.count('refunds'), 0)
    T.eq(#H.bridge.certificates, 1, 'Schein nachgeliefert')
    T.eq(#S.get('chars', 'c-lena').pendingCerts, 0)
    N.login(LENA)
    T.eq(#H.bridge.certificates, 1, 'zweiter Login-Aufruf ändert nichts')
    T.eq(H.bridge.players[LENA].bank, before + 1250)
end)

T.test('Netz: Abmeldung räumt Sitzung, Dienst und Wartenummer auf', function()
    cast()
    N.sessions[KELLER] = { app = 'beamte', index = 1, charId = 'c-keller' }
    T.succeeds(H.call(KELLER, 'beamte', 'dutySet', { state = 'on', desk = 1 }))
    T.eq(#IC.duty.list(), 1)
    IC.queue.list[1] = { no = 'A-001', who = 'Lena Brandt', charId = 'c-lena', typeId = 'beratung', at = IC.now() }
    N.seen[LENA] = 'c-lena'
    fire(KELLER, 'playerDropped')
    T.eq(#IC.duty.list(), 0, 'Beamter ist nicht mehr im Dienst')
    T.notok(N.sessions[KELLER])
    fire(LENA, 'playerDropped')
    T.eq(#IC.queue.list, 0, 'Wartenummer verfällt')
end)

T.test('Netz: Bestandsimport per Befehl, nur mit Recht, wiederholbar', function()
    cast()
    local file = json.encode({
        { ref = 'alt-1', name = 'Lenas Kiosk', kind = 'unternehmen', legalForm = 'einzel', branch = 'handel', hq = 'Vespucci', members = { { charId = 'c-lena', name = 'Lena Brandt', role = 'inhaber', share = 100 } } },
        { ref = 'alt-2', name = 'Kaputt', kind = 'unternehmen', legalForm = 'gibtsnicht' },
    })
    commands[Config.Staff.importCommand](LENA)
    T.ok(H.lastNotice(LENA, 'nicht befugt'), 'ohne Recht kein Import')
    T.eq(S.count('entities'), 0)

    local missing = T.capture(commands[Config.Staff.importCommand], 0) -- Konsole: Datei fehlt
    T.eq(S.count('entities'), 0)
    T.ok(missing[1]:find('fehlt', 1, true), 'Hinweis auf die fehlende Datei')
    resourceFiles['import/legacy.json'] = file
    local printed = T.capture(commands[Config.Staff.importCommand], 0)
    T.ok(table.concat(printed, '\n'):find('gibtsnicht', 1, true), 'Fehler der zweiten Zeile steht in der Konsole')
    T.eq(S.count('entities'), 1)
    local e = S.list('entities')[1]
    T.eq(e.legacy, true); T.eq(e.legacyConfirmed, false); T.ok(e.regNo:match('^HRA %d+$')); T.ok(e.legacyDue > IC.now())
    T.ok(H.lastNotice(LENA, 'übernommen'), 'Inhaberin wird benachrichtigt')
    T.capture(commands[Config.Staff.importCommand], 0)
    T.eq(S.count('entities'), 1, 'zweiter Lauf legt nichts doppelt an')
    resourceFiles['import/legacy.json'] = nil
end)

T.test('Netz: solange der Dienst startet, nimmt der Server keine Aufrufe an', function()
    cast()
    fire(LENA, 'ic_behoerden:server:open', 'gewerbeamt', 1)
    IC.started = false
    T.fails(N.handle(LENA, 'bootstrap', { app = 'gewerbeamt' }), 'startet')
    IC.started = true
end)
