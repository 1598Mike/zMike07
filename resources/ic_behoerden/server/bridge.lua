--[[
    ic_behoerden · Brücke zum Spiel (Basis)
    Alles, was die Ressource vom Spiel braucht, läuft über IC.bridge. Die Fachlogik kennt weder ESX noch QBCore noch Natives.
    Diese Datei enthält den Teil, der unabhängig vom Framework ist (Ort, Benachrichtigung, Webhook, Inventar-Auswahl).
    Die Adapter in bridge_esx.lua, bridge_qb.lua und bridge_standalone.lua liefern Charakter, Konto, Job, Stadtkasse und Inventar.
    IC.bridge.init() wählt beim Start den passenden Adapter (Config.Framework).

    Das muss ein Adapter bieten (alle Funktionen laufen auf dem Server):
      detect()                          läuft das Framework?
      charIdOf(src)                     Charakter-ID oder nil, solange kein Charakter geladen ist
      getChar(src)                      { charId, name, age, playHours, hasId } oder nil
      getBank(src)                      Kontostand
      addBank(src, amount, reason)
      removeBank(src, amount, reason)   true, wenn abgebucht wurde
      getOfficial(src)                  { rank, dienstnr } oder nil, wenn der Spieler kein Beamter ist (Config.Officials.jobs)
      treasuryAdd(amount, reason)
      treasuryRemove(amount, reason)    true, wenn die Kasse gedeckt war
      addItem(src, item, metadata)      true, wenn das Item im Inventar ist (nur ohne ox_inventory nötig)
      hasItem(src, item)                (nur ohne ox_inventory nötig)
      setup()                           optional, einmal beim Start
]]

IC = IC or {}
local U = IC.util

local B = { adapters = {}, name = nil }
IC.bridge = B

-- ---------------------------------------------------------------------------
-- Ort
-- ---------------------------------------------------------------------------
local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
B.distance = dist

-- Position des Spielers laut Server (der Client kann sie nicht fälschen)
function B.coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function B.isNear(a, b, radius)
    local pa, pb = B.coords(a), B.coords(b)
    return pa ~= nil and pb ~= nil and dist(pa, pb) <= radius
end

function B.online()
    local out = {}
    for _, id in ipairs(GetPlayers()) do out[#out + 1] = tonumber(id) end
    return out
end

function B.srcOfChar(charId)
    if charId == nil then return nil end
    for _, src in ipairs(B.online()) do
        if B.charIdOf(src) == charId then return src end
    end
end

-- Spieler im Umkreis mit geladenem Charakter, sortiert nach Charakter-ID
function B.getNearby(src, radius)
    local out, me = {}, B.coords(src)
    if not me then return out end
    for _, other in ipairs(B.online()) do
        if other ~= src then
            local pos = B.coords(other)
            if pos and dist(me, pos) <= radius then
                local c = B.getChar(other)
                if c then c.src = other; out[#out + 1] = c end
            end
        end
    end
    table.sort(out, function(a, b) return a.charId < b.charId end)
    return out
end

-- ---------------------------------------------------------------------------
-- Nachrichten an den Client, Ereignisse, Discord
-- ---------------------------------------------------------------------------
function B.notify(src, text, kind)
    TriggerClientEvent('ic_behoerden:client:notify', src, text, kind or 'info')
end

function B.askInvite(targetSrc, fromName)
    TriggerClientEvent('ic_behoerden:client:invite', targetSrc, fromName)
end

-- Ereignis für andere Ressourcen (AddEventHandler('ic_behoerden:entityCreated', ...))
function B.emit(event, ...)
    TriggerEvent(event, ...)
end

function B.http(url, payload)
    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- ---------------------------------------------------------------------------
-- Inventar und Gewerbeschein. ox_inventory hat Vorrang, sonst entscheidet der Adapter.
-- ---------------------------------------------------------------------------
local function oxStarted() return GetResourceState('ox_inventory') == 'started' end

function B.addItemTo(src, item, metadata)
    if oxStarted() then
        local ok, res = pcall(function() return exports.ox_inventory:AddItem(src, item, 1, metadata) end)
        return ok and res ~= nil and res ~= false
    end
    if B.addItem then
        local ok, res = pcall(B.addItem, src, item, metadata)
        return ok and res == true
    end
    return false
end

function B.hasItemIn(src, item)
    if oxStarted() then
        local ok, n = pcall(function() return exports.ox_inventory:Search(src, 'count', item) end)
        return ok and (tonumber(n) or 0) > 0
    end
    if B.hasItem then
        local ok, res = pcall(B.hasItem, src, item)
        return ok and res == true
    end
    return false
end

-- Beschriftung des Gewerbescheins im Inventar
function B.certificateMeta(e)
    return {
        description = ('%s · %s · gültig bis %s'):format(e.name, e.regNo, os.date('%d.%m.%Y', math.floor((e.validUntil or 0) / 1000))),
        regNo = e.regNo, name = e.name, owner = e.owner, kind = e.kind, legalForm = e.legalForm,
    }
end

-- Ohne Item in der Config gibt es den Schein nur in der Oberfläche. true heißt: nichts weiter zu tun.
function B.giveCertificate(src, e)
    local item = Config.Certificate and Config.Certificate.item
    if not item or item == '' then return true end
    return B.addItemTo(src, item, B.certificateMeta(e))
end

-- Alter aus einem Geburtsdatum der echten Welt. Versteht 31/12/1999, 31.12.1999 und 1999-12-31.
function B.ageFromDob(dob, now)
    if type(dob) ~= 'string' then return nil end
    local a, b, c = dob:match('^%s*(%d+)[%-%./](%d+)[%-%./](%d+)')
    if not a then return nil end
    local year, month, day
    if #a == 4 then year, month, day = tonumber(a), tonumber(b), tonumber(c)
    elseif #c == 4 then day, month, year = tonumber(a), tonumber(b), tonumber(c)
    else return nil end
    local t = os.date('*t', now or os.time())
    local age = t.year - year
    if t.month < month or (t.month == month and t.day < day) then age = age - 1 end
    return age >= 0 and age or nil
end

-- Alter und Spielzeit nach Config.Characters, sonst die Standardwerte des Adapters
function B.characterStats(src, charId, defaultAge, defaultHours)
    local cfg = Config.Characters or {}
    local age, hours = defaultAge, defaultHours or 9999
    if type(cfg.age) == 'function' then
        local ok, v = pcall(cfg.age, src, charId)
        if ok and tonumber(v) then age = tonumber(v) end
    end
    if type(cfg.playHours) == 'function' then
        local ok, v = pcall(cfg.playHours, src, charId)
        if ok and tonumber(v) then hours = tonumber(v) end
    end
    local hasId = true
    if cfg.idItem and cfg.idItem ~= '' then hasId = B.hasItemIn(src, cfg.idItem) end
    if age == nil and not B.warnedAge then
        B.warnedAge = true
        print(('[ic_behoerden] Kein Alter für Charakter %s gefunden (Geburtsdatum fehlt oder ist nicht lesbar). Solche Charaktere gelten als zu jung. Abhilfe: Config.Characters.age.'):format(tostring(charId)))
    end
    return age or 0, hours, hasId
end

-- Eine vierstellige Dienstnummer, die für einen Charakter immer gleich bleibt
function B.dienstnr(charId)
    local h = 5381
    for i = 1, #tostring(charId) do h = (h * 33 + tostring(charId):byte(i)) % 9000 end
    return ('B-%04d'):format(h + 1000)
end

-- Rang aus Job und Stufe laut Config.Officials.jobs, sonst nil
function B.rankOfJob(job, grade)
    local map = Config.Officials and Config.Officials.jobs and Config.Officials.jobs[job]
    if not map then return nil end
    return map[tonumber(grade) or 0]
end

-- ---------------------------------------------------------------------------
-- Auswahl des Adapters
-- ---------------------------------------------------------------------------
B.ORDER = { 'qbox', 'qb', 'esx' }
local FRAMEWORK_RESOURCE = { qbox = 'qbx_core', qb = 'qb-core', esx = 'es_extended' }

-- Das Framework startet je nach Reihenfolge in der server.cfg später als diese Ressource. Wartet bis zu timeoutMs darauf.
function B.waitForFramework(timeoutMs)
    local want, waited = Config.Framework or 'auto', 0
    while waited < timeoutMs do
        if want == 'auto' then
            for _, res in pairs(FRAMEWORK_RESOURCE) do
                if GetResourceState(res) == 'started' then return true end
            end
        elseif FRAMEWORK_RESOURCE[want] == nil or GetResourceState(FRAMEWORK_RESOURCE[want]) == 'started' then
            return true
        end
        Wait(500)
        waited = waited + 500
    end
    return false
end

function B.init()
    local want = Config.Framework or 'auto'
    local pick
    if want == 'auto' then
        for _, key in ipairs(B.ORDER) do
            local a = B.adapters[key]
            if a and a.detect() then pick = key break end
        end
        pick = pick or 'standalone'
    else
        pick = want
    end
    local adapter = B.adapters[pick]
    if not adapter then
        print(('[ic_behoerden] Unbekanntes Framework "%s". Erlaubt: auto, esx, qb, qbox, standalone.'):format(tostring(pick)))
        pick, adapter = 'standalone', B.adapters.standalone
    end
    for key, fn in pairs(adapter) do
        if type(fn) == 'function' and key ~= 'detect' and key ~= 'setup' then B[key] = fn end
    end
    -- Eigene Stadtkasse aus der Config hat Vorrang vor der automatischen Anbindung
    local tr = Config.Treasury or {}
    if type(tr.add) == 'function' then
        B.treasuryAdd = function(amount, reason) pcall(tr.add, amount, reason) end
    end
    if type(tr.remove) == 'function' then
        B.treasuryRemove = function(amount, reason)
            local ok, res = pcall(tr.remove, amount, reason)
            return ok and res == true
        end
    end
    B.name = pick
    if adapter.setup then adapter.setup() end
    if pick == 'standalone' then
        print('[ic_behoerden] Läuft ohne Framework (Standalone). Das ist nur zum Testen gedacht: Konten und Stadtkasse liegen im Speicher.')
    else
        print('[ic_behoerden] Framework: ' .. pick)
    end
    return pick
end
