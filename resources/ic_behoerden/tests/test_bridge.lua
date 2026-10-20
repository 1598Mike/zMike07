local T, H = ...
local U = IC.util

--[[
    Prüft die Brücke zum Spiel (server/bridge*.lua) mit Attrappen für FiveM, ESX, QBCore und Qbox.
    Jede Dateigruppe wird in eine eigene Umgebung geladen, damit die Fake-Bridge der anderen Tests unberührt bleibt.
    Wichtig: Das sind Annahmen über die Schnittstellen der Frameworks. Ob sie in eurer Version stimmen, zeigt erst ein Test im Spiel.
]]

json = json or dofile('tests/json.lua')

local function exportsOf(map)
    local out = {}
    for res, fns in pairs(map) do
        out[res] = {}
        for name, fn in pairs(fns) do out[res][name] = function(_, ...) return fn(...) end end
    end
    return setmetatable(out, { __call = function() end })
end

-- Baut eine Umgebung mit Natives-Attrappen und lädt die genannten Dateien hinein
local function world(files, o)
    o = o or {}
    local st = { resources = o.resources or {}, players = o.players or {}, client = {}, triggered = {}, handlers = {}, http = {}, waited = 0 }
    local env = setmetatable({}, { __index = _G })
    env.IC = { util = IC.util, rules = IC.rules }
    env.Config = U.deepcopy(Config)
    for k, v in pairs(o.config or {}) do env.Config[k] = v end
    env.json = json
    env.exports = exportsOf(o.exports or {})
    env.GetResourceState = function(res) return st.resources[res] or 'missing' end
    env.GetPlayers = function() local l = {}; for id in pairs(st.players) do l[#l + 1] = tostring(id) end; table.sort(l); return l end
    env.GetPlayerPed = function(src) local p = st.players[src]; return p and p.ped or 0 end
    env.GetEntityCoords = function(ped) for _, p in pairs(st.players) do if p.ped == ped then return p.coords end end end
    env.GetPlayerName = function(src) local p = st.players[src]; return p and p.name or nil end
    env.GetPlayerIdentifierByType = function(src, kind) local p = st.players[src]; return p and p[kind] or nil end
    env.IsPlayerAceAllowed = function(src, ace) local p = st.players[src]; return p ~= nil and p.aces ~= nil and p.aces[ace] == true end
    env.TriggerClientEvent = function(name, target, ...) st.client[#st.client + 1] = { name = name, target = target, args = { ... } } end
    env.TriggerEvent = function(name, ...) st.triggered[#st.triggered + 1] = { name = name, args = { ... } }; if o.onEvent then o.onEvent(name, ...) end end
    env.AddEventHandler = function(name, fn) st.handlers[name] = fn end
    env.PerformHttpRequest = function(url, cb, method, body, headers) st.http[#st.http + 1] = { url = url, method = method, body = body, headers = headers } end
    env.Wait = function(ms) st.waited = st.waited + ms end
    for _, f in ipairs(files) do assert(loadfile(f, 't', env))() end
    return env, st
end

local BASE = { 'server/bridge.lua' }
local function withAdapter(o)
    return world({ 'server/bridge.lua', 'server/bridge_standalone.lua', 'server/bridge_esx.lua', 'server/bridge_qb.lua' }, o)
end

local function ped(id, x, y, z, name, extra)
    local p = { ped = 100 + id, coords = vector3(x, y, z), name = name }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

-- ===========================================================================================
T.test('Brücke: Alter aus Geburtsdatum in den üblichen Schreibweisen', function()
    local env = world(BASE)
    local B = env.IC.bridge
    local now = os.time({ year = 2026, month = 10, day = 20, hour = 12 })
    T.eq(B.ageFromDob('12/05/1995', now), 31, 'TT/MM/JJJJ, Geburtstag war schon')
    T.eq(B.ageFromDob('31.12.1995', now), 30, 'TT.MM.JJJJ, Geburtstag kommt noch')
    T.eq(B.ageFromDob('1995-12-31', now), 30, 'JJJJ-MM-TT')
    T.eq(B.ageFromDob('1995-10-20', now), 31, 'am Geburtstag zählt er')
    T.eq(B.ageFromDob('2030-01-01', now), nil, 'Zukunft ist kein Alter')
    T.eq(B.ageFromDob('gestern', now), nil)
    T.eq(B.ageFromDob(nil, now), nil)
end)

T.test('Brücke: Dienstnummer bleibt gleich, Rang kommt aus Job und Stufe', function()
    local env = world(BASE)
    local B = env.IC.bridge
    T.eq(B.dienstnr('char1:abc'), B.dienstnr('char1:abc'))
    T.ok(B.dienstnr('char1:abc'):match('^B%-%d%d%d%d$'))
    T.ok(B.dienstnr('char1:abc') ~= B.dienstnr('char2:xyz'))
    T.eq(B.rankOfJob('gov', 2), 'amtsleiter')
    T.eq(B.rankOfJob('gov', '3'), 'leitung', 'ESX liefert die Stufe teils als Text')
    T.eq(B.rankOfJob('gov', 9), nil)
    T.eq(B.rankOfJob('police', 0), nil)
end)

T.test('Brücke: Alter, Spielzeit und Ausweis aus Config.Characters', function()
    local items = { [1] = { id_card = 1 } }
    local env, st = world(BASE, { resources = { ox_inventory = 'started' }, exports = { ox_inventory = {
        Search = function(src, mode, item) return (items[src] or {})[item] or 0 end,
    } } })
    local B = env.IC.bridge
    local age, hours, hasId = B.characterStats(1, 'c1', 25)
    T.eq(age, 25); T.eq(hours, 9999, 'ohne Quelle wird die Spielzeit nicht geprüft'); T.eq(hasId, true, 'ohne Item kein Ausweis nötig')

    env.Config.Characters = {
        idItem = 'id_card',
        age = function(src, charId) return 41 end,
        playHours = function(src, charId) error('Quelle kaputt') end,
    }
    age, hours, hasId = B.characterStats(1, 'c1', 25)
    T.eq(age, 41, 'eigene Altersquelle'); T.eq(hours, 9999, 'eine fehlerhafte Quelle bricht nichts ab'); T.eq(hasId, true)
    T.eq(select(3, B.characterStats(2, 'c2', 25)), false, 'Charakter ohne Ausweis-Item')
    env.Config.Characters.playHours = function() return 12 end
    T.eq(select(2, B.characterStats(1, 'c1', 25)), 12)
end)

T.test('Brücke: Umgebung, Nachbarn und Entfernung', function()
    local env, st = world(BASE, { players = {
        [1] = ped(1, 0, 0, 0, 'Lena'), [2] = ped(2, 3, 4, 0, 'Tom'), [3] = ped(3, 40, 0, 0, 'Fern'), [4] = ped(4, 1, 1, 0, 'Ohne Charakter'),
    } })
    local B = env.IC.bridge
    local chars = { [1] = 'c-lena', [2] = 'c-tom', [3] = 'c-fern' }
    B.charIdOf = function(src) return chars[src] end
    B.getChar = function(src) return chars[src] and { charId = chars[src], name = 'x', age = 30, playHours = 10, hasId = true } or nil end
    T.ok(B.isNear(1, 2, 5.0)); T.notok(B.isNear(1, 3, 5.0)); T.notok(B.isNear(1, 99, 5.0), 'unbekannter Spieler')
    local near = B.getNearby(1, 15.0)
    T.eq(#near, 1, 'nur Tom: Fern ist zu weit, Spieler 4 hat keinen Charakter'); T.eq(near[1].charId, 'c-tom'); T.eq(near[1].src, 2)
    T.eq(B.srcOfChar('c-fern'), 3); T.eq(B.srcOfChar('c-niemand'), nil); T.eq(B.srcOfChar(nil), nil)
    T.eq(B.distance(vector3(0, 0, 0), vector3(3, 4, 0)), 5.0)
end)

T.test('Brücke: Meldungen, Ereignisse, Discord', function()
    local env, st = world(BASE)
    local B = env.IC.bridge
    B.notify(5, 'Hallo', nil)
    T.eq(st.client[1].name, 'ic_behoerden:client:notify'); T.eq(st.client[1].target, 5); T.eq(st.client[1].args[2], 'info')
    B.askInvite(6, 'Lena')
    T.eq(st.client[2].name, 'ic_behoerden:client:invite'); T.eq(st.client[2].args[1], 'Lena')
    B.emit('ic_behoerden:entityCreated', { regNo = 'HRA 1' })
    T.eq(st.triggered[1].name, 'ic_behoerden:entityCreated')
    B.http('https://example.invalid/hook', { username = 'x' })
    T.eq(st.http[1].method, 'POST'); T.eq(st.http[1].headers['Content-Type'], 'application/json'); T.eq(json.decode(st.http[1].body).username, 'x')
end)

T.test('Brücke: Gewerbeschein über ox_inventory, über den Adapter oder gar nicht', function()
    local e = { name = 'Lenas Kiosk', regNo = 'HRA 1001', owner = 'Lena Brandt', kind = 'unternehmen', legalForm = 'einzel', validUntil = os.time({ year = 2027, month = 1, day = 31, hour = 12 }) * 1000 }
    local added = {}
    local env, st = world(BASE, { resources = { ox_inventory = 'started' }, exports = { ox_inventory = {
        AddItem = function(src, item, n, meta) added[#added + 1] = { src, item, n, meta }; return src ~= 9 and { slot = 1 } or false end,
    } } })
    local B = env.IC.bridge
    T.eq(B.giveCertificate(1, e), true)
    T.eq(added[1][2], 'gewerbeschein'); T.eq(added[1][3], 1)
    T.ok(added[1][4].description:find('HRA 1001', 1, true) and added[1][4].description:find('31.01.2027', 1, true), 'Beschriftung: ' .. tostring(added[1][4].description))
    T.eq(B.giveCertificate(9, e), false, 'Inventar voll: false, damit der Schein beim Login nachgeliefert wird')

    -- ohne ox_inventory entscheidet der Adapter
    local env2 = world(BASE)
    local B2 = env2.IC.bridge
    T.eq(B2.giveCertificate(1, e), false, 'ohne Inventar und Adapter: false')
    B2.addItem = function(src, item, meta) added[#added + 1] = { src, item, 1, meta }; return true end
    T.eq(B2.giveCertificate(1, e), true)
    -- kein Item in der Config: nichts zu tun
    env2.Config.Certificate.item = nil
    local before = #added
    T.eq(B2.giveCertificate(1, e), true); T.eq(#added, before)
end)

T.test('Brücke: Wahl des Frameworks und eigene Stadtkasse', function()
    local function pick(resources, framework)
        local env, st = world({ 'server/bridge.lua', 'server/bridge_standalone.lua', 'server/bridge_esx.lua', 'server/bridge_qb.lua' }, {
            resources = resources, config = { Framework = framework or 'auto' },
            exports = { ['es_extended'] = { getSharedObject = function() return { GetPlayerFromId = function() end } end },
                        ['qb-core'] = { GetCoreObject = function() return { Functions = { GetPlayer = function() end } } end } },
        })
        local _, name = T.capture(env.IC.bridge.init)
        return name, env
    end
    T.eq(pick({ qbx_core = 'started', ['qb-core'] = 'started', es_extended = 'started' }), 'qbox', 'Qbox hat Vorrang vor QBCore')
    T.eq(pick({ ['qb-core'] = 'started' }), 'qb')
    T.eq(pick({ es_extended = 'started' }), 'esx')
    T.eq(pick({}), 'standalone')
    T.eq(pick({ es_extended = 'started' }, 'standalone'), 'standalone', 'fest eingestellt gilt vor der Erkennung')
    T.eq(pick({ es_extended = 'started' }, 'gibtsnicht'), 'standalone', 'unbekannter Name fällt zurück')

    -- Eigene Stadtkasse aus der Config ersetzt die des Adapters
    local env = world({ 'server/bridge.lua', 'server/bridge_standalone.lua' })
    local log = {}
    env.Config.Treasury.add = function(n, why) log[#log + 1] = 'add ' .. n end
    env.Config.Treasury.remove = function(n, why) log[#log + 1] = 'remove ' .. n; return n <= 100 end
    T.capture(env.IC.bridge.init)
    env.IC.bridge.treasuryAdd(50, 'x'); T.eq(env.IC.bridge.treasuryRemove(80, 'x'), true); T.eq(env.IC.bridge.treasuryRemove(500, 'x'), false)
    T.eq(log[1], 'add 50'); T.eq(log[3], 'remove 500')
    env.Config.Treasury.remove = function() error('kaputt') end
    T.capture(env.IC.bridge.init)
    T.eq(env.IC.bridge.treasuryRemove(1, 'x'), false, 'eine fehlerhafte Funktion gilt als nicht gedeckt')
end)

T.test('Brücke: auf das Framework warten', function()
    local env, st = world(BASE, { resources = {} })
    T.eq(env.IC.bridge.waitForFramework(2000), false)
    T.eq(st.waited, 2000, 'gewartet wurde bis zum Ende der Frist')
    st.resources['es_extended'] = 'started'
    T.eq(env.IC.bridge.waitForFramework(2000), true)
    env.Config.Framework = 'qb'
    T.eq(env.IC.bridge.waitForFramework(500), false)
    env.Config.Framework = 'standalone'
    T.eq(env.IC.bridge.waitForFramework(500), true, 'ohne Framework gibt es nichts zu warten')
end)

-- ===========================================================================================
local function fakeX(id, name, dob, bank, job)
    local x = { identifier = id, job = job, accounts = { bank = { money = bank } }, variables = { dateofbirth = dob }, items = {} }
    function x.getName() return name end
    function x.get(k) return x.variables[k] end
    function x.getAccount(n) return x.accounts[n] end
    function x.addAccountMoney(n, a) x.accounts[n].money = x.accounts[n].money + a end
    function x.removeAccountMoney(n, a) x.accounts[n].money = x.accounts[n].money - a end
    function x.canCarryItem(item, n) return not x.full end
    function x.addInventoryItem(item, n, meta) x.items[#x.items + 1] = { item = item, count = n, meta = meta } end
    function x.getInventoryItem(item) local c = 0; for _, i in ipairs(x.items) do if i.item == item then c = c + 1 end end; return { count = c } end
    return x
end

T.test('ESX: Charakter, Konto, Job, Stadtkasse und Inventar', function()
    local players = {
        [1] = fakeX('char1:aaa', 'Lena Brandt', '12/05/1995', 5000, { name = 'unemployed', grade = 0 }),
        [2] = fakeX('char1:bbb', 'Dr. Keller', '1980-01-01', 100, { name = 'gov', grade = 2 }),
    }
    local accounts = { society_gov = { money = 1000 } }
    accounts.society_gov.addMoney = function(n) accounts.society_gov.money = accounts.society_gov.money + n end
    accounts.society_gov.removeMoney = function(n) accounts.society_gov.money = accounts.society_gov.money - n end
    local env, st = withAdapter({
        resources = { es_extended = 'started' }, config = { Framework = 'esx', Characters = { idItem = 'id_card' } },
        exports = { es_extended = { getSharedObject = function() return { GetPlayerFromId = function(src) return players[src] end } end } },
        onEvent = function(name, account, cb) if name == 'esx_addonaccount:getSharedAccount' then cb(accounts[account]) end end,
    })
    local B = env.IC.bridge
    T.eq(select(2, T.capture(B.init)), 'esx')

    local c = B.getChar(1)
    T.eq(c.charId, 'char1:aaa'); T.eq(c.name, 'Lena Brandt'); T.ok(c.age >= 30, 'Alter aus Geburtsdatum'); T.eq(c.hasId, false, 'ohne Ausweis-Item')
    players[1].addInventoryItem('id_card', 1)
    T.eq(B.getChar(1).hasId, true)
    T.eq(B.getChar(77), nil, 'kein Spieler, kein Charakter')
    T.eq(B.charIdOf(2), 'char1:bbb')

    T.eq(B.getBank(1), 5000)
    T.eq(B.removeBank(1, 6000, 'x'), false); T.eq(B.getBank(1), 5000, 'bei zu wenig Guthaben wird nichts abgebucht')
    T.eq(B.removeBank(1, 1250, 'x'), true); T.eq(B.getBank(1), 3750)
    B.addBank(1, 250, 'x'); T.eq(B.getBank(1), 4000)

    T.eq(B.getOfficial(1), nil, 'Arbeitslose sind keine Beamten')
    local o = B.getOfficial(2)
    T.eq(o.rank, 'amtsleiter'); T.ok(o.dienstnr:match('^B%-%d%d%d%d$'))

    B.treasuryAdd(500, 'Gebühr'); T.eq(accounts.society_gov.money, 1500)
    T.eq(B.treasuryRemove(400, 'Pauschale'), true); T.eq(accounts.society_gov.money, 1100)
    T.eq(B.treasuryRemove(5000, 'Pauschale'), false, 'ungedeckt'); T.eq(accounts.society_gov.money, 1100)

    -- Gewerbeschein über das ESX-Inventar
    local e = { name = 'Lenas Kiosk', regNo = 'HRA 1001', owner = 'x', kind = 'unternehmen', legalForm = 'einzel', validUntil = IC.now() }
    T.eq(B.giveCertificate(1, e), true); T.eq(players[1].items[#players[1].items].item, 'gewerbeschein')
    players[1].full = true
    T.eq(B.giveCertificate(1, e), false, 'Inventar voll')

    -- Login-Ereignis des Frameworks leitet an net.lua weiter
    local logins = {}
    B.onLogin = function(src) logins[#logins + 1] = src end
    st.handlers['esx:playerLoaded']('7')
    T.eq(logins[1], 7)
end)

-- ===========================================================================================
local function fakeQb(id, first, last, birth, bank, job)
    local p = { PlayerData = { citizenid = id, source = 0, charinfo = { firstname = first, lastname = last, birthdate = birth }, job = job, money = { bank = bank } }, items = {} }
    p.Functions = {
        GetMoney = function(kind) return p.PlayerData.money[kind] end,
        AddMoney = function(kind, a) p.PlayerData.money[kind] = p.PlayerData.money[kind] + a; return true end,
        RemoveMoney = function(kind, a) if p.PlayerData.money[kind] < a then return false end; p.PlayerData.money[kind] = p.PlayerData.money[kind] - a; return true end,
        AddItem = function(item, n, slot, info) if p.full then return false end; p.items[#p.items + 1] = { item = item, amount = n, info = info }; return true end,
        GetItemByName = function(item) for _, i in ipairs(p.items) do if i.item == item then return i end end end,
    }
    return p
end

for _, variant in ipairs({ 'qb', 'qbox' }) do
    T.test(('%s: Charakter, Konto, Job, Stadtkasse und Inventar'):format(variant == 'qb' and 'QBCore' or 'Qbox'), function()
        local players = {
            [1] = fakeQb('ABC123', 'Lena', 'Brandt', '1995-05-12', 5000, { name = 'unemployed', grade = { level = 0 } }),
            [2] = fakeQb('XYZ789', 'Franz', 'Keller', '1980-01-01', 100, { name = 'gov', grade = { level = 1 } }),
        }
        local bank = { government = 900 }
        local banking = {
            AddMoney = function(acc, n) bank[acc] = (bank[acc] or 0) + n end,
            RemoveMoney = function(acc, n) if (bank[acc] or 0) < n then return false end; bank[acc] = bank[acc] - n; return true end,
        }
        local core = { Functions = { GetPlayer = function(src) return players[src] end } }
        local env, st = withAdapter({
            resources = { [variant == 'qb' and 'qb-core' or 'qbx_core'] = 'started', ['qb-banking'] = 'started' },
            config = { Framework = variant, Treasury = { account = 'government' }, Characters = { idItem = 'id_card' } },
            exports = {
                ['qb-core'] = { GetCoreObject = function() return core end },
                qbx_core = { GetPlayer = function(src) return players[src] end },
                ['qb-banking'] = banking,
            },
        })
        local B = env.IC.bridge
        T.eq(select(2, T.capture(B.init)), variant)

        local c = B.getChar(1)
        T.eq(c.charId, 'ABC123'); T.eq(c.name, 'Lena Brandt'); T.ok(c.age >= 30); T.eq(c.hasId, false)
        players[1].items[1] = { item = 'id_card', amount = 1 }
        T.eq(B.getChar(1).hasId, true)
        T.eq(B.getChar(5), nil)
        T.eq(B.charIdOf(2), 'XYZ789')

        T.eq(B.getBank(1), 5000)
        T.eq(B.removeBank(1, 6000, 'x'), false); T.eq(B.removeBank(1, 1000, 'x'), true); T.eq(B.getBank(1), 4000)
        B.addBank(1, 100, 'x'); T.eq(B.getBank(1), 4100)

        T.eq(B.getOfficial(1), nil)
        T.eq(B.getOfficial(2).rank, 'sachbearbeiter')

        B.treasuryAdd(300, 'Gebühr'); T.eq(bank.government, 1200)
        T.eq(B.treasuryRemove(1000, 'Pauschale'), true); T.eq(bank.government, 200)
        T.eq(B.treasuryRemove(1000, 'Pauschale'), false)

        local e = { name = 'Lenas Kiosk', regNo = 'HRA 1001', owner = 'x', kind = 'unternehmen', legalForm = 'einzel', validUntil = IC.now() }
        T.eq(B.giveCertificate(1, e), true)
        players[1].full = true
        T.eq(B.giveCertificate(1, e), false)

        local logins = {}
        B.onLogin = function(src) logins[#logins + 1] = src end
        st.handlers['QBCore:Server:PlayerLoaded']({ PlayerData = { source = 4 } })
        T.eq(logins[1], 4)
    end)
end

T.test('QBCore: Stadtkasse ohne Bank-Ressource meldet sich einmal und bucht nichts', function()
    local core = { Functions = { GetPlayer = function() end } }
    local env, st = withAdapter({ resources = { ['qb-core'] = 'started' }, config = { Framework = 'qb' },
        exports = { ['qb-core'] = { GetCoreObject = function() return core end } } })
    local B = env.IC.bridge
    local lines = T.capture(function()
        B.init()
        B.treasuryAdd(10, 'x'); T.eq(B.treasuryRemove(10, 'x'), false); B.treasuryAdd(10, 'x')
    end)
    local warnings = 0
    for _, l in ipairs(lines) do if l:find('Keine Bank%-Ressource') then warnings = warnings + 1 end end
    T.eq(warnings, 1, 'die Warnung erscheint nur einmal')
end)

-- ===========================================================================================
T.test('Standalone: Konten im Speicher, Beamte per ACE, Alter und Spielzeit aus der Config', function()
    local env, st = withAdapter({ config = { Framework = 'standalone' }, players = {
        [1] = ped(1, 0, 0, 0, 'Lena', { license = 'license:aaa' }),
        [2] = ped(2, 0, 0, 0, 'Keller', { license = 'license:bbb', aces = { ['ic_behoerden.official.anwaerter'] = true, ['ic_behoerden.official.amtsleiter'] = true } }),
        [3] = ped(3, 0, 0, 0, 'Ohne Lizenz'),
    } })
    local B = env.IC.bridge
    T.eq(select(2, T.capture(B.init)), 'standalone')

    local c = B.getChar(1)
    T.eq(c.charId, 'license:aaa'); T.eq(c.name, 'Lena'); T.eq(c.age, 30); T.eq(c.playHours, 100); T.eq(c.hasId, true)
    T.eq(B.charIdOf(3), 'src:3', 'ohne Lizenz dient die Spieler-ID')
    T.eq(B.getChar(9), nil)

    T.eq(B.getBank(1), 50000)
    T.eq(B.removeBank(1, 60000), false); T.eq(B.removeBank(1, 20000), true); T.eq(B.getBank(1), 30000)
    B.addBank(1, 5, 'x'); T.eq(B.getBank(1), 30005)
    T.eq(B.treasuryRemove(1), false, 'Kasse ist leer'); B.treasuryAdd(100); T.eq(B.treasuryRemove(60), true); T.eq(B.treasuryRemove(60), false)

    T.eq(B.getOfficial(1), nil)
    T.eq(B.getOfficial(2).rank, 'amtsleiter', 'die höchste erlaubte Stufe zählt')
    T.eq(B.giveCertificate(1, { name = 'x', regNo = 'HRA 1', validUntil = 0 }), false, 'ohne Inventar kein Schein, aber auch kein Fehler')
end)

T.test('Client-Sicht: Die gemeinsamen Dateien laden ohne die Server-Konfiguration', function()
    -- Spieler bekommen nur config.lua und die shared-Dateien. Nichts davon darf beim Laden config_server.lua voraussetzen.
    -- IC und Config sind in dieser Umgebung zunächst leer, nicht die der anderen Tests
    local env = setmetatable({ vector3 = vector3 }, { __index = function(_, k) if k ~= 'IC' and k ~= 'Config' then return _G[k] end end })
    for _, f in ipairs({ 'config.lua', 'shared/util.lua', 'shared/rules.lua', 'shared/protocol.lua' }) do assert(loadfile(f, 't', env))() end
    T.ok(env.IC.protocol and #env.IC.protocol.names() > 20, 'Protokoll ist verfügbar')
    T.eq(env.Config.Webhooks, nil, 'Webhooks erreichen den Client nicht')
    T.eq(env.Config.Hooks, nil)
    T.eq(env.Config.Rules, nil)
    T.eq(env.Config.Treasury, nil)
end)
