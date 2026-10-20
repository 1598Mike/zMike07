--[[
    ic_behoerden · Client
    Zeigt Marker und Hilfetext an den Terminals, öffnet die Oberfläche und leitet deren Aufrufe an den Server weiter.
    Der Client entscheidet nichts: Ob ein Aufruf erlaubt ist, prüft allein der Server (server/net.lua).
]]

local EV = 'ic_behoerden:'

local openApp = nil          -- gerade geöffnete Anwendung
local openCoords = nil       -- Ort des Terminals, an dem sie geöffnet wurde (nil: kein Ort, zum Beispiel Staff-Panel)
local openRadius = 2.0
local requested = nil        -- Terminal, für das gerade eine Öffnung beim Server angefragt ist
local pending = {}           -- Anfragen der Oberfläche, auf die der Server noch antworten muss
local reqId = 0
local invite = nil           -- offene Einladung als Mitgründer: { from, expires }

-- ---------------------------------------------------------------------------
-- Meldungen
-- ---------------------------------------------------------------------------
local function notify(text, kind)
    if openApp then
        SendNUIMessage({ action = 'notify', text = text, kind = kind })
        return
    end
    if type(Config.Notify) == 'function' then
        Config.Notify(text, kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent(EV .. 'client:notify', function(text, kind)
    notify(text, kind)
    -- Neue Nachrichten betreffen oft den Stand eines Antrags oder Termins: die offene Oberfläche lädt sich neu
    if openApp then SendNUIMessage({ action = 'refresh' }) end
end)

-- ---------------------------------------------------------------------------
-- Oberfläche öffnen und schließen
-- ---------------------------------------------------------------------------
local function openUi(app)
    openApp = app
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', app = app })
end

local function closeUi(tellServer)
    if not openApp then return end
    openApp, openCoords = nil, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if tellServer then TriggerServerEvent(EV .. 'server:close') end
end

-- Der Server hat zugestimmt
RegisterNetEvent(EV .. 'client:open', function(app)
    if openApp then return end
    if requested then
        openCoords, openRadius = requested.coords, requested.radius
    else
        openCoords = nil
    end
    requested = nil
    openUi(app)
end)

-- Der Server beendet die Sitzung (zu weit entfernt, Job verloren, Charakter gewechselt)
RegisterNetEvent(EV .. 'client:close', function()
    closeUi(false)
end)

local function requestOpen(group, index)
    if openApp or requested then return end
    local loc = Config.Locations[group] and Config.Locations[group][index]
    if not loc then return end
    requested = { coords = loc.coords, radius = loc.radius or 2.0 }
    TriggerServerEvent(EV .. 'server:open', group, index)
    -- Antwortet der Server nicht (zum Beispiel noch beim Start), wird die Anfrage verworfen
    SetTimeout(3000, function() requested = nil end)
end

-- Entfernt sich der Spieler oder stirbt er, schließt die Oberfläche
CreateThread(function()
    while true do
        Wait(openApp and 500 or 1500)
        if openApp then
            local ped = PlayerPedId()
            local away = openCoords and #(GetEntityCoords(ped) - openCoords) > openRadius + (Config.Tolerance or 3.0)
            if away or IsEntityDead(ped) then closeUi(true) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and openApp then SetNuiFocus(false, false) end
end)

-- ---------------------------------------------------------------------------
-- Aufrufe der Oberfläche -> Server -> Antwort
-- ---------------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    closeUi(true)
    cb({ ok = true })
end)

for _, name in ipairs(IC.protocol.names()) do
    RegisterNUICallback(name, function(data, cb)
        if not openApp then
            cb({ ok = false, error = 'Die Anwendung ist nicht geöffnet.' })
            return
        end
        reqId = reqId + 1
        local id = reqId
        pending[id] = cb
        TriggerServerEvent(EV .. 'server:call', id, name, data)
        SetTimeout(15000, function()
            local waiting = pending[id]
            if waiting then
                pending[id] = nil
                waiting({ ok = false, error = 'Der Server antwortet nicht.' })
            end
        end)
    end)
end

RegisterNetEvent(EV .. 'client:reply', function(id, result)
    local cb = pending[id]
    if cb then
        pending[id] = nil
        cb(result)
    end
end)

-- ---------------------------------------------------------------------------
-- Einladung als Mitgründer: Y nimmt an, N lehnt ab (in den Tasteneinstellungen änderbar)
-- ---------------------------------------------------------------------------
RegisterNetEvent(EV .. 'client:invite', function(fromName)
    invite = { from = fromName, expires = GetGameTimer() + 30000 }
    notify(('%s lädt Sie als Mitgründer ein. Y: annehmen, N: ablehnen (30 Sekunden).'):format(tostring(fromName)), 'warn')
end)

local function answerInvite(accept)
    if not invite then return end
    local valid = GetGameTimer() <= invite.expires
    invite = nil
    if not valid then return end
    TriggerServerEvent(EV .. 'server:inviteAnswer', accept)
    notify(accept and 'Sie haben die Einladung angenommen.' or 'Sie haben die Einladung abgelehnt.', accept and 'ok' or 'info')
end

RegisterCommand('ic_invite_yes', function() answerInvite(true) end, false)
RegisterCommand('ic_invite_no', function() answerInvite(false) end, false)
RegisterKeyMapping('ic_invite_yes', 'Gründungseinladung annehmen', 'keyboard', 'Y')
RegisterKeyMapping('ic_invite_no', 'Gründungseinladung ablehnen', 'keyboard', 'N')

-- ---------------------------------------------------------------------------
-- Terminals: ox_target oder Marker mit Taste
-- ---------------------------------------------------------------------------
local function setupTargets()
    if GetResourceState('ox_target') ~= 'started' then
        print('[ic_behoerden] Config.Interact.mode = "target", aber ox_target läuft nicht. Es werden Marker verwendet.')
        return false
    end
    for group, list in pairs(Config.Locations) do
        for index, loc in ipairs(list) do
            exports.ox_target:addSphereZone({
                coords = loc.coords, radius = loc.radius or 1.5, debug = false,
                options = { {
                    name = ('ic_behoerden_%s_%d'):format(group, index), icon = 'fa-solid fa-building-columns', label = loc.label,
                    onSelect = function() requestOpen(group, index) end,
                } },
            })
        end
    end
    return true
end

CreateThread(function()
    if Config.Interact.mode == 'target' and setupTargets() then return end
    local ia = Config.Interact
    local mk = ia.marker
    while true do
        local sleep = 800
        if not openApp then
            local pos = GetEntityCoords(PlayerPedId())
            for group, list in pairs(Config.Locations) do
                for index, loc in ipairs(list) do
                    local d = #(pos - loc.coords)
                    if d < ia.drawDistance then
                        sleep = 0
                        DrawMarker(mk.type, loc.coords.x, loc.coords.y, loc.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, mk.r, mk.g, mk.b, mk.a, false, true, 2, false, nil, nil, false)
                        if d < (loc.radius or 1.8) then
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName(ia.helpText:format(loc.label))
                            EndTextCommandDisplayHelp(0, false, true, -1)
                            if IsControlJustReleased(0, ia.key) then requestOpen(group, index) end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ---------------------------------------------------------------------------
-- Kartensymbol am Gewerbeamt
-- ---------------------------------------------------------------------------
CreateThread(function()
    local def = Config.Blips
    local loc = Config.Locations.gewerbeamt and Config.Locations.gewerbeamt[1]
    if not def or not def.enabled or not def.gewerbeamt or not loc then return end
    local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
    SetBlipSprite(blip, def.gewerbeamt.sprite)
    SetBlipColour(blip, def.gewerbeamt.colour)
    SetBlipScale(blip, def.gewerbeamt.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(def.gewerbeamt.label)
    EndTextCommandSetBlipName(blip)
end)
