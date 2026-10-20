--[[
    ic_behoerden · Netzwerk
    Nimmt die Aufrufe der Oberfläche entgegen (Oberfläche -> Client -> Server), prüft Sitzung, Ort und Berechtigung und reicht sie an IC.api weiter.
    Der Server vertraut dem Client nur bei der Auswahl des Aufrufs, nie bei dessen Inhalt: Wer der Spieler ist, wo er steht und ob er
    Beamter oder Staff ist, ermittelt der Server bei jedem Aufruf selbst.

    Ereignisse vom Client:   ic_behoerden:server:open (app, index), :close, :call (reqId, name, data), :inviteAnswer (accept)
    Ereignisse zum Client:   ic_behoerden:client:open (app), :close, :reply (reqId, result), :notify (text, kind), :invite (fromName)
]]

IC = IC or {}
local N = { sessions = {}, calls = {}, seen = {} }
IC.net = N

local EV = 'ic_behoerden:'
local WINDOW_MS, MAX_CALLS = 10000, 40   -- höchstens 40 Aufrufe in 10 Sekunden je Spieler
local MAX_PAYLOAD = 40000                -- Zeichen, die ein Aufruf an Daten mitbringen darf
local PLAYER_APPS = { gewerbeamt = true, buergeramt = true, beamte = true }

local function say(src, text, kind)
    if src == 0 then print('[ic_behoerden] ' .. text) else IC.bridge.notify(src, text, kind or 'info') end
end

local function rateOk(src)
    local now = GetGameTimer()
    local list = N.calls[src]
    if not list then list = {}; N.calls[src] = list end
    while #list > 0 and now - list[1] > WINDOW_MS do table.remove(list, 1) end
    if #list >= MAX_CALLS then return false end
    list[#list + 1] = now
    return true
end

-- ---------------------------------------------------------------------------
-- Sitzungen
-- ---------------------------------------------------------------------------
-- Steht der Spieler noch am Terminal? Staff und frei geöffnete Tablets (Config.Officials.mustBeInOffice = false) brauchen keinen Ort.
local function atLocation(src, s)
    if s.app == 'staff' then return true end
    if s.app == 'beamte' and Config.Officials and Config.Officials.mustBeInOffice == false then return true end
    local loc = Config.Locations[s.app] and Config.Locations[s.app][s.index]
    local pos = IC.bridge.coords(src)
    if not loc or not pos then return false end
    return IC.bridge.distance(pos, loc.coords) <= (loc.radius or 2.0) + (Config.Tolerance or 3.0)
end

-- Öffnet eine Anwendung für den Spieler. Gibt true zurück oder false mit einem Text für den Spieler.
function N.open(src, app, index)
    if app ~= 'staff' and not PLAYER_APPS[app] then return false, 'Unbekannte Anwendung.' end
    local char = IC.bridge.getChar(src)
    if not char then return false, 'Es ist kein Charakter geladen.' end
    if app == 'staff' then
        if not IsPlayerAceAllowed(src, Config.Staff.ace) then return false, 'Dafür sind Sie nicht befugt.' end
        index = nil
    else
        index = math.floor(tonumber(index) or 1)
    end
    local s = { app = app, index = index, charId = char.charId }
    if not atLocation(src, s) then return false, 'Sie sind zu weit vom Terminal entfernt.' end
    if app == 'beamte' and not IC.bridge.getOfficial(src) then return false, 'Dafür sind Sie nicht befugt.' end
    N.sessions[src] = s
    return true
end

local function closeSession(src, text)
    N.sessions[src] = nil
    TriggerClientEvent(EV .. 'client:close', src)
    if text then IC.bridge.notify(src, text, 'warn') end
end

-- Baut den Kontext für IC.api.call aus dem, was der Server selbst weiß
function N.context(src, s)
    local char = IC.bridge.getChar(src)
    if not char then return nil, 'Es ist kein Charakter geladen.' end
    if s.charId ~= char.charId then return nil, 'Der Charakter hat gewechselt. Bitte öffnen Sie die Anwendung neu.' end
    if not atLocation(src, s) then return nil, 'Sie haben sich vom Terminal entfernt.' end
    local ctx = { src = src, char = char, session = s.app }
    if s.app == 'beamte' then
        local o = IC.bridge.getOfficial(src)
        if not o then return nil, 'Dafür sind Sie nicht befugt.' end
        ctx.off = { id = char.charId, name = char.name, rank = o.rank, dienstnr = o.dienstnr, src = src }
    elseif s.app == 'staff' then
        if not IsPlayerAceAllowed(src, Config.Staff.ace) then return nil, 'Dafür sind Sie nicht befugt.' end
        ctx.staff = true
        ctx.staffName = GetPlayerName(src)
    end
    return ctx
end

-- Ein Aufruf der Oberfläche. Gibt immer eine Antwort zurück (ok = true oder false mit error).
function N.handle(src, name, data)
    if not IC.started then return IC.fail('Der Dienst startet noch. Bitte versuchen Sie es gleich noch einmal.') end
    if not rateOk(src) then return IC.fail('Zu viele Anfragen. Bitte einen Moment warten.') end
    local s = N.sessions[src]
    if not s then return IC.fail('Bitte öffnen Sie die Anwendung an einem Terminal.') end
    if type(data) ~= 'table' then data = {} end
    local okEnc, enc = pcall(json.encode, data)
    if not okEnc or #enc > MAX_PAYLOAD then return IC.fail('Die Anfrage ist zu groß.') end
    local ctx, why = N.context(src, s)
    if not ctx then
        closeSession(src, why)
        return IC.fail(why)
    end
    return IC.api.call(ctx, name, data)
end

-- ---------------------------------------------------------------------------
-- Ereignisse vom Client
-- ---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'server:open', function(app, index)
    local src = source
    if type(app) ~= 'string' or not rateOk(src) then return end
    local ok, why = N.open(src, app, index)
    if ok then TriggerClientEvent(EV .. 'client:open', src, app)
    else IC.bridge.notify(src, why, 'bad') end
end)

RegisterNetEvent(EV .. 'server:close', function()
    N.sessions[source] = nil
end)

RegisterNetEvent(EV .. 'server:call', function(reqId, name, data)
    local src = source
    if type(reqId) ~= 'number' or type(name) ~= 'string' then return end
    TriggerClientEvent(EV .. 'client:reply', src, reqId, N.handle(src, name, data))
end)

-- Antwort des eingeladenen Mitgründers
RegisterNetEvent(EV .. 'server:inviteAnswer', function(accept)
    local src = source
    local charId = IC.bridge.charIdOf(src)
    if charId and rateOk(src) then IC.apps.inviteAnswer(charId, accept == true) end
end)

-- ---------------------------------------------------------------------------
-- Login, Abmeldung, Takt
-- ---------------------------------------------------------------------------
-- Läuft für jeden Spieler mit geladenem Charakter genau einmal je Charakter: zahlt Erstattungen aus, liefert Gewerbescheine nach
function N.login(src)
    if not src or not GetPlayerName(src) then return end
    local charId = IC.bridge.charIdOf(src)
    if not charId then N.seen[src] = nil return end
    if N.seen[src] == charId then return end
    N.seen[src] = charId
    IC.pay.flushRefunds(charId, src)
    IC.register.deliverPending(charId, src)
end

AddEventHandler('playerDropped', function()
    local src = source
    N.sessions[src], N.calls[src] = nil, nil
    IC.duty.removeBySrc(src)
    if N.seen[src] then IC.appt.dropChar(N.seen[src]) end
    N.seen[src] = nil
end)

-- Startet die Dauerarbeit (nach dem Laden der Daten): Login-Erkennung alle 10 Sekunden, Fristen und Dienstzeit alle 30 Sekunden.
function N.start()
    -- Das Framework meldet den Login oft, bevor das Inventar bereit ist. Kurz warten, dann abarbeiten.
    IC.bridge.onLogin = function(src) SetTimeout(5000, function() N.login(src) end) end
    CreateThread(function()
        local seconds = 0
        while true do
            Wait(10000)
            seconds = seconds + 10
            local ok, err = pcall(function()
                for _, src in ipairs(IC.bridge.online()) do N.login(src) end
                if seconds >= 30 then
                    seconds = 0
                    IC.tick()
                    IC.staff.trackDuty(30)
                end
            end)
            if not ok then print('[ic_behoerden] Fehler im Takt: ' .. tostring(err)) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Befehle
-- ---------------------------------------------------------------------------
local function allowed(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.Staff.ace)
end

-- Staff-Panel
RegisterCommand(Config.Staff.command or 'icstaff', function(src)
    if src == 0 then say(0, 'Das Staff-Panel lässt sich nur im Spiel öffnen.') return end
    local ok, why = N.open(src, 'staff')
    if ok then TriggerClientEvent(EV .. 'client:open', src, 'staff') else say(src, why, 'bad') end
end, false)

-- Tablet überall öffnen (nur, wenn Config.Officials.mustBeInOffice = false und ein Befehl eingetragen ist)
if Config.Officials and Config.Officials.mustBeInOffice == false and Config.Officials.command then
    RegisterCommand(Config.Officials.command, function(src)
        if src == 0 then return end
        local ok, why = N.open(src, 'beamte')
        if ok then TriggerClientEvent(EV .. 'client:open', src, 'beamte') else say(src, why, 'bad') end
    end, false)
end

-- Übernahme des Bestands aus import/legacy.json (siehe docs/UMSETZUNG.md). Lässt sich gefahrlos wiederholen.
RegisterCommand(Config.Staff.importCommand or 'icimport', function(src)
    if not allowed(src) then say(src, 'Dafür sind Sie nicht befugt.', 'bad') return end
    local text = LoadResourceFile(GetCurrentResourceName(), 'import/legacy.json')
    if not text then say(src, 'Die Datei import/legacy.json fehlt. Eine Vorlage liegt unter import/legacy.example.json.') return end
    local ok, list = pcall(json.decode, text)
    if not ok or type(list) ~= 'table' then say(src, 'import/legacy.json ist kein gültiges JSON.') return end
    local res = IC.register.importLegacy(list, src == 0 and 'Konsole' or GetPlayerName(src))
    say(src, ('Import fertig: %d übernommen, %d übersprungen, %d mit Fehler.'):format(res.created, res.skipped, #res.errors))
    for _, line in ipairs(res.errors) do print('[ic_behoerden]   ' .. line) end
end, false)

-- Kurzer Zustandsbericht für die Konsole oder Staff
RegisterCommand('icstatus', function(src)
    if not allowed(src) then return end
    local S = IC.store
    say(src, ('Anträge: %d, Einträge: %d, Termine: %d, Beamte im Dienst: %d, offene Datenbankschreibvorgänge: %d, Framework: %s.'):format(
        S.count('applications'), S.count('entities'), S.count('appointments'), #IC.duty.list(), IC.persist and #IC.persist.queue or 0, tostring(IC.bridge.name)))
end, false)
