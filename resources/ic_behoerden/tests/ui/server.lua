--[[
    Testserver für die Oberfläche: die echte Serverlogik (inklusive net.lua) mit Fake-Bridge, ansprechbar über Textzeilen.
    Jede Zeile auf stdin ist ein JSON-Objekt { id, op, ... }, die Antwort kommt als eine Zeile { id, res } auf stdout.
    Gestartet wird er von tests/ui/e2e-server.js, aus dem Ordner resources/ic_behoerden:   lua tests/ui/server.lua

    Damit lässt sich die echte Oberfläche (web/) im Browser gegen die echte Serverlogik prüfen, ohne FiveM.
    Aufruf wie im Spiel: open (Terminal öffnen), call (Aufruf der Oberfläche), close, inviteAnswer.
]]
package.path = './?.lua;' .. package.path
function vector3(x, y, z) return { x = x, y = y, z = z } end

dofile('config.lua'); dofile('config_server.lua')
dofile('shared/util.lua'); dofile('shared/rules.lua'); dofile('shared/protocol.lua')
for _, f in ipairs({ 'server/store.lua', 'server/core.lua', 'server/duty.lua', 'server/register.lua', 'server/applications.lua', 'server/appointments.lua', 'server/staff.lua', 'server/api.lua' }) do dofile(f) end
local H = dofile('tests/fakebridge.lua')
local F = dofile('tests/fivem.lua')(H)
dofile('server/net.lua')
local N = IC.net
json = dofile('tests/json.lua')

local function at(group, dx) local c = Config.Locations[group][1].coords; return vector3(c.x + (dx or 0), c.y, c.z) end

-- Spielfiguren wie in den Tests: Gründer vor dem Rathaus, Beamte an den Schaltern
local CAST = {
    [1]  = { charId = 'c-lena',   name = 'Lena Brandt',   age = 29, playHours = 63,  bank = 184250, group = 'gewerbeamt' },
    [2]  = { charId = 'c-tom',    name = 'Tom Becker',    age = 31, playHours = 48,  bank = 100000, group = 'gewerbeamt' },
    [3]  = { charId = 'c-marco',  name = 'Marco Rossi',   age = 34, playHours = 120, bank = 100000, group = 'gewerbeamt' },
    [4]  = { charId = 'c-anna',   name = 'Anna Kowalski', age = 27, playHours = 6,   bank = 100000, group = 'gewerbeamt' },
    [10] = { charId = 'c-keller', name = 'Dr. Keller',    rank = 'amtsleiter',      bank = 5000, group = 'beamte' },
    [11] = { charId = 'c-yilmaz', name = 'Yilmaz',        rank = 'sachbearbeiter',  bank = 5000, group = 'beamte' },
    [12] = { charId = 'c-novak',  name = 'Novak',         rank = 'anwaerter',       bank = 5000, group = 'beamte' },
    [99] = { charId = 'c-admin',  name = 'Admin Alex',    bank = 100000, group = 'gewerbeamt', staff = true },
}

local function reset()
    H.reset()
    F.reset()
    N.sessions, N.calls, N.seen = {}, {}, {}
    IC.started = true
    for src, c in pairs(CAST) do
        local p = { charId = c.charId, name = c.name, age = c.age, playHours = c.playHours, bank = c.bank, rank = c.rank, area = c.rank and 2 or 1 }
        p.coords = at(c.group)
        H.player(src, p)
        F.aces[src] = c.staff == true
    end
end

local OPS = {}

function OPS.reset() reset(); return { ok = true, now = IC.now() } end

function OPS.open(m)
    local before = #F.sent
    F.fire(m.src, 'ic_behoerden:server:open', m.app, m.index or 1)
    for i = before + 1, #F.sent do
        local e = F.sent[i]
        if e.name == 'ic_behoerden:client:open' and e.target == m.src then return { opened = true, app = e.args[1] } end
    end
    local n = H.lastNotice(m.src)
    return { opened = false, notice = n and n.text }
end

function OPS.staffOpen(m)
    F.commands[Config.Staff.command](m.src)
    local e = F.lastSent('ic_behoerden:client:open', m.src)
    return { opened = e ~= nil and e.args[1] == 'staff' }
end

function OPS.close(m) F.fire(m.src, 'ic_behoerden:server:close'); return { ok = true } end

function OPS.call(m)
    F.gameTimer = F.gameTimer + 300
    return N.handle(m.src, m.name, m.data)
end

function OPS.inviteAnswer(m) F.fire(m.src, 'ic_behoerden:server:inviteAnswer', m.accept == true); return { ok = true } end

function OPS.advance(m) H.advance(m.ms); F.gameTimer = F.gameTimer + m.ms; return { now = IC.now() } end

function OPS.setClock(m) H.clock = m.ts; return { now = IC.now() } end

-- Spieler verändern (zum Beispiel Rang entziehen oder Position wechseln)
function OPS.player(m)
    local p = H.bridge.players[m.src]
    for k, v in pairs(m.patch or {}) do
        if k == 'at' then p.coords = at(v[1], v[2]) else p[k] = v end
    end
    return { ok = true }
end

-- Bestand übernehmen, wie der Befehl icimport
function OPS.import(m) return IC.register.importLegacy(m.list, 'Test') end

function OPS.ace(m) F.aces[m.src] = m.on == true; return { ok = true } end

-- Zustand für Prüfungen im Test
function OPS.dump()
    return {
        applications = IC.store.list('applications'), entities = IC.store.list('entities'), appointments = IC.store.list('appointments'),
        notices = H.bridge.notices, certificates = H.bridge.certificates, treasury = H.bridge.treasury, now = IC.now(),
        banks = (function() local t = {}; for src, p in pairs(H.bridge.players) do t[tostring(src)] = p.bank end; return t end)(),
    }
end

reset()
io.stdout:setvbuf('line')
for line in io.lines() do
    local ok, msg = pcall(json.decode, line)
    local out
    if not ok or type(msg) ~= 'table' then
        out = { error = 'ungültige Zeile' }
    else
        local fn = OPS[msg.op]
        if not fn then
            out = { id = msg.id, error = 'unbekannte Operation ' .. tostring(msg.op) }
        else
            local okc, res = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, msg)
            if okc then out = { id = msg.id, res = res } else out = { id = msg.id, error = res } end
        end
    end
    io.write(json.encode(out), '\n')
end
