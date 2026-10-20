local T, H = ...
local U = IC.util

--[[
    Prüft client/main.lua mit Attrappen für die Spiel-Funktionen. Die Fäden (CreateThread) laufen als Koroutinen und werden
    im Test Schritt für Schritt weitergeschaltet. Ob Marker, Hilfetext und Oberfläche im Spiel gut aussehen, zeigt nur ein Test im Spiel.
]]

local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }, V) end
V.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end

local function client(o)
    o = o or {}
    local st = {
        threads = {}, callbacks = {}, nui = {}, focus = {}, server = {}, events = {}, commands = {}, keys = {}, timers = {}, drawn = 0, help = {},
        feed = {}, blips = {}, targets = {}, resources = o.resources or {}, pos = vec(0, 0, 0), dead = false, key = false, timer = 0, notified = {},
    }
    local env = setmetatable({}, { __index = _G })
    env.IC = { protocol = IC.protocol }
    env.Config = U.deepcopy(Config)
    for k, v in pairs(o.config or {}) do env.Config[k] = v end
    env.vector3 = vec
    env.CreateThread = function(fn) st.threads[#st.threads + 1] = coroutine.create(fn) end
    env.Wait = function(ms) coroutine.yield(ms) end
    env.SetTimeout = function(ms, fn) st.timers[#st.timers + 1] = { ms = ms, fn = fn } end
    env.GetGameTimer = function() return st.timer end
    env.RegisterNUICallback = function(name, fn) st.callbacks[name] = fn end
    env.SendNUIMessage = function(m) st.nui[#st.nui + 1] = m end
    env.SetNuiFocus = function(a, b) st.focus[#st.focus + 1] = { a, b } end
    env.TriggerServerEvent = function(name, ...) st.server[#st.server + 1] = { name = name, args = { ... } } end
    env.RegisterNetEvent = function(name, fn) st.events[name] = fn end
    env.AddEventHandler = function(name, fn) st.events[name] = fn end
    env.RegisterCommand = function(name, fn) st.commands[name] = fn end
    env.RegisterKeyMapping = function(cmd, label, kind, key) st.keys[cmd] = { label = label, key = key } end
    env.GetCurrentResourceName = function() return 'ic_behoerden' end
    env.GetResourceState = function(res) return st.resources[res] or 'missing' end
    env.PlayerPedId = function() return 1 end
    env.GetEntityCoords = function() return st.pos end
    env.IsEntityDead = function() return st.dead end
    env.DrawMarker = function() st.drawn = st.drawn + 1 end
    env.BeginTextCommandDisplayHelp = function() end
    env.AddTextComponentSubstringPlayerName = function(t) st.last = t end
    env.EndTextCommandDisplayHelp = function() st.help[#st.help + 1] = st.last end
    env.IsControlJustReleased = function() return st.key end
    env.BeginTextCommandThefeedPost = function() end
    env.EndTextCommandThefeedPostTicker = function() st.feed[#st.feed + 1] = st.last end
    env.AddBlipForCoord = function(x, y, z) st.blips[#st.blips + 1] = { x = x, y = y, z = z }; return #st.blips end
    env.SetBlipSprite = function(b, v) st.blips[b].sprite = v end
    env.SetBlipColour = function(b, v) st.blips[b].colour = v end
    env.SetBlipScale = function(b, v) st.blips[b].scale = v end
    env.SetBlipAsShortRange = function() end
    env.BeginTextCommandSetBlipName = function() end
    env.EndTextCommandSetBlipName = function(b) st.blips[b].label = st.last end
    env.exports = setmetatable({ ox_target = { addSphereZone = function(_, def) st.targets[#st.targets + 1] = def end } }, { __call = function() end })
    assert(loadfile('client/main.lua', 't', env))()

    -- Alle Fäden einmal bis zum nächsten Warten weiterschalten
    function st.step(n)
        for _ = 1, n or 1 do
            for _, co in ipairs(st.threads) do
                if coroutine.status(co) == 'suspended' then
                    local ok, err = coroutine.resume(co)
                    if not ok then error(err, 0) end
                end
            end
        end
    end
    -- Ereignis vom Server
    function st.fromServer(name, ...) st.events[name](...) end
    function st.lastNui(action)
        for i = #st.nui, 1, -1 do if st.nui[i].action == action then return st.nui[i] end end
    end
    function st.serverEvents(name)
        local out = {}
        for _, e in ipairs(st.server) do if e.name == name then out[#out + 1] = e end end
        return out
    end
    st.env = env
    return st
end

local function atLocation(st, group, dx)
    local c = Config.Locations[group][1].coords
    st.pos = vec(c.x + (dx or 0), c.y, c.z)
end

-- ===========================================================================================
T.test('Client: Für jeden Aufruf der Oberfläche gibt es einen Rückruf, auch zum Schließen', function()
    local st = client()
    for _, name in ipairs(IC.protocol.names()) do T.ok(st.callbacks[name], 'Rückruf für ' .. name) end
    T.ok(st.callbacks.close)
    local got
    st.callbacks.bootstrap({ app = 'gewerbeamt' }, function(r) got = r end)
    T.eq(got.ok, false, 'ohne geöffnete Anwendung wird nichts an den Server geschickt')
    T.eq(#st.serverEvents('ic_behoerden:server:call'), 0)
end)

T.test('Client: Marker nur in der Nähe, Taste fragt den Server, Antwort öffnet die Oberfläche', function()
    local st = client()
    st.pos = vec(0, 0, 0)
    st.step(3)
    T.eq(st.drawn, 0, 'weit weg wird nichts gezeichnet')
    atLocation(st, 'gewerbeamt', 5.0)       -- im Sichtbereich, noch nicht am Terminal
    st.step(); T.ok(st.drawn > 0, 'Marker erscheint'); T.eq(#st.help, 0, 'Hilfetext erst direkt am Terminal')
    atLocation(st, 'gewerbeamt', 0.5)
    st.step(); T.ok(st.help[#st.help]:find('Gewerbeamt-Terminal', 1, true), 'Hilfetext nennt das Terminal')
    st.key = true
    st.step()
    local asks = st.serverEvents('ic_behoerden:server:open')
    T.eq(#asks, 1); T.eq(asks[1].args[1], 'gewerbeamt'); T.eq(asks[1].args[2], 1)
    st.step()
    T.eq(#st.serverEvents('ic_behoerden:server:open'), 1, 'solange die Anfrage läuft, wird nicht erneut gefragt')
    T.notok(st.lastNui('open'), 'ohne Zustimmung des Servers öffnet sich nichts')

    st.fromServer('ic_behoerden:client:open', 'gewerbeamt')
    T.eq(st.lastNui('open').app, 'gewerbeamt'); T.eq(st.focus[#st.focus][1], true)
    local before = st.drawn
    st.step(); T.eq(st.drawn, before, 'bei geöffneter Oberfläche keine Marker')
end)

T.test('Client: Aufrufe der Oberfläche gehen mit Nummer an den Server, die Antwort geht zurück', function()
    local st = client()
    st.fromServer('ic_behoerden:client:open', 'staff')
    local got1, got2
    st.callbacks.bootstrap({ app = 'staff' }, function(r) got1 = r end)
    st.callbacks.nameCheck({ name = 'X' }, function(r) got2 = r end)
    local calls = st.serverEvents('ic_behoerden:server:call')
    T.eq(#calls, 2); T.ok(calls[1].args[1] ~= calls[2].args[1], 'jede Anfrage hat eine eigene Nummer')
    T.eq(calls[1].args[2], 'bootstrap'); T.eq(calls[2].args[3].name, 'X')
    -- Antworten kommen in beliebiger Reihenfolge
    st.fromServer('ic_behoerden:client:reply', calls[2].args[1], { ok = true, normalized = 'x' })
    T.eq(got2.normalized, 'x'); T.eq(got1, nil)
    st.fromServer('ic_behoerden:client:reply', calls[1].args[1], { ok = true, now = 5 })
    T.eq(got1.now, 5)
    -- eine zweite, späte Antwort ändert nichts
    st.fromServer('ic_behoerden:client:reply', calls[1].args[1], { ok = false })
    T.eq(got1.ok, true)

    -- Antwortet der Server nicht, bekommt die Oberfläche nach der Frist einen Fehler
    local got3
    st.callbacks.bootstrap({}, function(r) got3 = r end)
    for _, t in ipairs(st.timers) do t.fn() end
    T.eq(got3.ok, false); T.ok(got3.error:find('antwortet nicht', 1, true))
end)

T.test('Client: Schließen durch die Oberfläche, durch den Server, durch Entfernen und durch Tod', function()
    local st = client()
    local function open(group)
        atLocation(st, group, 0.5)
        st.key = true; st.step(); st.key = false
        st.fromServer('ic_behoerden:client:open', group)
    end
    -- Oberfläche schließt: Server erfährt es
    open('gewerbeamt')
    local ok
    st.callbacks.close({}, function(r) ok = r end)
    T.eq(ok.ok, true); T.eq(st.lastNui('close') ~= nil, true); T.eq(st.focus[#st.focus][1], false)
    T.eq(#st.serverEvents('ic_behoerden:server:close'), 1)
    -- Doppeltes Schließen sendet nichts
    st.callbacks.close({}, function() end)
    T.eq(#st.serverEvents('ic_behoerden:server:close'), 1)

    -- Server beendet die Sitzung: der Server weiß es schon, keine Meldung zurück
    open('gewerbeamt')
    st.fromServer('ic_behoerden:client:close')
    T.eq(st.focus[#st.focus][1], false); T.eq(#st.serverEvents('ic_behoerden:server:close'), 1)

    -- Spieler geht weg
    open('gewerbeamt')
    st.step(2)
    T.ok(#st.nui > 0)
    local closes = #st.serverEvents('ic_behoerden:server:close')
    st.pos = vec(st.pos.x + 30, st.pos.y, st.pos.z)
    st.step(3)
    T.eq(#st.serverEvents('ic_behoerden:server:close'), closes + 1, 'Entfernen schließt und meldet es dem Server')
    T.eq(st.lastNui('close') ~= nil, true)

    -- Spieler stirbt
    open('buergeramt')
    closes = #st.serverEvents('ic_behoerden:server:close')
    st.dead = true
    st.step(3)
    T.eq(#st.serverEvents('ic_behoerden:server:close'), closes + 1)
    st.dead = false
end)

T.test('Client: Staff-Panel hat keinen Ort und bleibt auch weit vom Rathaus offen', function()
    local st = client()
    st.pos = vec(5000, 5000, 0)
    st.fromServer('ic_behoerden:client:open', 'staff')
    local closes = #st.serverEvents('ic_behoerden:server:close')
    st.step(4)
    T.eq(#st.serverEvents('ic_behoerden:server:close'), closes)
end)

T.test('Client: Meldungen erscheinen in der Oberfläche oder am Bildschirmrand, eigene Meldung hat Vorrang', function()
    local st = client()
    st.fromServer('ic_behoerden:client:notify', 'Hallo', 'ok')
    T.eq(st.feed[1], 'Hallo', 'ohne Oberfläche: Meldung am Bildschirmrand')
    st.fromServer('ic_behoerden:client:open', 'gewerbeamt')
    st.fromServer('ic_behoerden:client:notify', 'Termin bestätigt', 'ok')
    T.eq(st.lastNui('notify').text, 'Termin bestätigt'); T.ok(st.lastNui('refresh'), 'die Oberfläche lädt sich neu')
    T.eq(#st.feed, 1)
    st.fromServer('ic_behoerden:client:close')

    local custom = {}
    local st2 = client({ config = { Notify = function(text, kind) custom[#custom + 1] = { text, kind } end } })
    st2.fromServer('ic_behoerden:client:notify', 'Hallo', 'warn')
    T.eq(custom[1][1], 'Hallo'); T.eq(custom[1][2], 'warn'); T.eq(#st2.feed, 0)
end)

T.test('Client: Einladung als Mitgründer mit Taste Y oder N, nur innerhalb von 30 Sekunden', function()
    local st = client()
    T.eq(st.keys.ic_invite_yes.key, 'Y'); T.eq(st.keys.ic_invite_no.key, 'N')
    st.commands.ic_invite_yes()
    T.eq(#st.serverEvents('ic_behoerden:server:inviteAnswer'), 0, 'ohne Einladung passiert nichts')

    st.fromServer('ic_behoerden:client:invite', 'Lena Brandt')
    T.ok(st.feed[#st.feed]:find('Lena Brandt', 1, true))
    st.commands.ic_invite_yes()
    local a = st.serverEvents('ic_behoerden:server:inviteAnswer')
    T.eq(#a, 1); T.eq(a[1].args[1], true)
    st.commands.ic_invite_no()
    T.eq(#st.serverEvents('ic_behoerden:server:inviteAnswer'), 1, 'eine Einladung lässt sich nur einmal beantworten')

    st.fromServer('ic_behoerden:client:invite', 'Lena Brandt')
    st.commands.ic_invite_no()
    T.eq(st.serverEvents('ic_behoerden:server:inviteAnswer')[2].args[1], false)

    st.fromServer('ic_behoerden:client:invite', 'Lena Brandt')
    st.timer = 31000
    st.commands.ic_invite_yes()
    T.eq(#st.serverEvents('ic_behoerden:server:inviteAnswer'), 2, 'abgelaufene Einladung wird nicht mehr beantwortet')
end)

T.test('Client: Kartensymbol am Gewerbeamt, abschaltbar', function()
    local st = client()
    st.step()
    T.eq(#st.blips, 1); T.eq(st.blips[1].label, Config.Blips.gewerbeamt.label)
    T.eq(st.blips[1].x, Config.Locations.gewerbeamt[1].coords.x)
    local off = client({ config = { Blips = { enabled = false } } })
    off.step()
    T.eq(#off.blips, 0)
end)

T.test('Client: ox_target statt Markern, mit Rückfall auf Marker, wenn ox_target fehlt', function()
    local st = client({ resources = { ox_target = 'started' }, config = { Interact = { mode = 'target', key = 38, helpText = '%s', drawDistance = 8.0, marker = Config.Interact.marker } } })
    st.step()
    local total = 0
    for _, list in pairs(Config.Locations) do total = total + #list end
    T.eq(#st.targets, total, 'für jedes Terminal eine Zone')
    atLocation(st, 'gewerbeamt', 0.5)
    st.step(2); T.eq(st.drawn, 0, 'im Zielmodus keine Marker')
    st.targets[1].options[1].onSelect()
    T.eq(#st.serverEvents('ic_behoerden:server:open'), 1)

    local lines = T.capture(function()
        local fallback = client({ resources = {}, config = { Interact = { mode = 'target', key = 38, helpText = '%s', drawDistance = 8.0, marker = Config.Interact.marker } } })
        atLocation(fallback, 'gewerbeamt', 0.5)
        fallback.step(2)
        T.ok(fallback.drawn > 0, 'ohne ox_target gibt es Marker')
    end)
    T.ok(lines[1] and lines[1]:find('ox_target', 1, true), 'Hinweis in der Konsole')
end)
