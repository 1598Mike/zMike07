--[[
    Attrappen für das, was FiveM an Funktionen bereitstellt (Ereignisse, Befehle, Spieler, Zeit).
    Wird von den Netzwerktests und vom Testserver der Oberfläche genutzt. Aufruf:  local F = dofile('tests/fivem.lua')(H)
]]
return function(H)
    json = json or dofile('tests/json.lua')
    local F = { handlers = {}, commands = {}, sent = {}, aces = {}, timers = {}, files = {}, gameTimer = 0 }

    RegisterNetEvent = function(name, fn) F.handlers[name] = fn end
    AddEventHandler = function(name, fn) F.handlers[name] = fn end
    RegisterCommand = function(name, fn) F.commands[name] = fn end
    TriggerClientEvent = function(name, target, ...) F.sent[#F.sent + 1] = { name = name, target = target, args = { ... } } end
    GetGameTimer = function() return F.gameTimer end
    IsPlayerAceAllowed = function(src, ace) return F.aces[src] == true and ace == Config.Staff.ace end
    GetPlayerName = function(src) local p = H.bridge.players[src]; return p and p.name or nil end
    GetCurrentResourceName = function() return 'ic_behoerden' end
    LoadResourceFile = function(_, path) return F.files[path] end
    SetTimeout = function(ms, fn) F.timers[#F.timers + 1] = { ms = ms, fn = fn } end
    CreateThread = function() end
    Wait = function() end

    -- Löst ein Netzwerkereignis aus, wie FiveM es tut (source ist nur während des Aufrufs gesetzt)
    function F.fire(src, name, ...)
        source = src
        F.handlers[name](...)
        source = nil
    end

    function F.lastSent(name, target)
        for i = #F.sent, 1, -1 do
            if F.sent[i].name == name and (target == nil or F.sent[i].target == target) then return F.sent[i] end
        end
    end

    function F.reset()
        F.sent, F.timers, F.aces, F.gameTimer = {}, {}, {}, 0
    end

    return F
end
