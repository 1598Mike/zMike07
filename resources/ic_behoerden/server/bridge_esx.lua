--[[
    ic_behoerden · Adapter für ESX (es_extended ab Version 1.9, "Legacy")
    Konto: Bankkonto des Spielers. Stadtkasse: esx_addonaccount mit Config.Treasury.account (oder Config.Treasury.add/remove).
    Job: Config.Officials.jobs. Inventar: ox_inventory, sonst das ESX-Inventar.
]]

IC = IC or {}
local B = IC.bridge
local A = {}
B.adapters.esx = A

local ESX

function A.detect() return GetResourceState('es_extended') == 'started' end

function A.setup()
    ESX = exports['es_extended']:getSharedObject()
    AddEventHandler('esx:playerLoaded', function(playerId)
        if B.onLogin then B.onLogin(tonumber(playerId)) end
    end)
end

local function player(src) return ESX and ESX.GetPlayerFromId(src) or nil end

function A.charIdOf(src)
    local x = player(src)
    return x and x.identifier or nil
end

function A.getChar(src)
    local x = player(src)
    if not x then return nil end
    local dob = x.get and x.get('dateofbirth') or (x.variables and x.variables.dateofbirth)
    local age, hours, hasId = B.characterStats(src, x.identifier, B.ageFromDob(dob))
    return { charId = x.identifier, name = x.getName(), age = age, playHours = hours, hasId = hasId }
end

function A.getBank(src)
    local x = player(src)
    local acc = x and x.getAccount('bank')
    return acc and acc.money or 0
end

function A.addBank(src, amount, reason)
    local x = player(src)
    if x then x.addAccountMoney('bank', amount, reason) end
end

-- ESX meldet keinen Erfolg zurück, deshalb wird der Kontostand vorher geprüft
function A.removeBank(src, amount, reason)
    local x = player(src)
    if not x or A.getBank(src) < amount then return false end
    x.removeAccountMoney('bank', amount, reason)
    return true
end

function A.getOfficial(src)
    local x = player(src)
    if not x or not x.job then return nil end
    local rank = B.rankOfJob(x.job.name, x.job.grade)
    if not rank then return nil end
    return { rank = rank, dienstnr = B.dienstnr(x.identifier) }
end

-- Das Callback von esx_addonaccount läuft sofort, also direkt im selben Aufruf
local function withAccount(fn)
    local called = false
    TriggerEvent('esx_addonaccount:getSharedAccount', Config.Treasury and Config.Treasury.account, function(acc)
        called = true
        fn(acc)
    end)
    if not called then print('[ic_behoerden] esx_addonaccount antwortet nicht. Läuft die Ressource, und stimmt Config.Treasury.account?') end
end

function A.treasuryAdd(amount)
    withAccount(function(acc) if acc then acc.addMoney(amount) end end)
end

function A.treasuryRemove(amount)
    local done = false
    withAccount(function(acc)
        if acc and acc.money >= amount then acc.removeMoney(amount); done = true end
    end)
    return done
end

function A.addItem(src, item, metadata)
    local x = player(src)
    if not x then return false end
    if x.canCarryItem and not x.canCarryItem(item, 1) then return false end
    x.addInventoryItem(item, 1, metadata)
    return true
end

function A.hasItem(src, item)
    local x = player(src)
    local it = x and x.getInventoryItem(item)
    return it ~= nil and (it.count or 0) > 0
end
