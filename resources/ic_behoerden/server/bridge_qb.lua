--[[
    ic_behoerden · Adapter für QBCore (qb-core) und Qbox (qbx_core)
    Beide teilen sich PlayerData und Functions, nur das Laden des Spielers unterscheidet sich.
    Konto: Bankkonto des Spielers. Stadtkasse: qb-banking, Renewed-Banking oder qb-management mit Config.Treasury.account
    (oder Config.Treasury.add/remove). Job: Config.Officials.jobs. Inventar: ox_inventory, sonst das Inventar von QBCore.
]]

IC = IC or {}
local B = IC.bridge

local warnedTreasury = false

-- Welche Bank-Ressource die Stadtkasse führt, in dieser Reihenfolge
local TREASURY = {
    { res = 'qb-banking',      add = function(acc, n, why) exports['qb-banking']:AddMoney(acc, n, why) end,       remove = function(acc, n, why) return exports['qb-banking']:RemoveMoney(acc, n, why) end },
    { res = 'Renewed-Banking', add = function(acc, n) exports['Renewed-Banking']:addAccountMoney(acc, n) end,     remove = function(acc, n) return exports['Renewed-Banking']:removeAccountMoney(acc, n) end },
    { res = 'qb-management',   add = function(acc, n) exports['qb-management']:AddMoney(acc, n) end,              remove = function(acc, n) return exports['qb-management']:RemoveMoney(acc, n) end },
}

local function treasuryBackend()
    for _, t in ipairs(TREASURY) do
        if GetResourceState(t.res) == 'started' then return t end
    end
    if not warnedTreasury then
        warnedTreasury = true
        print('[ic_behoerden] Keine Bank-Ressource für die Stadtkasse gefunden (qb-banking, Renewed-Banking, qb-management). Gebühren werden nicht verbucht. Alternative: Config.Treasury.add und .remove.')
    end
end

local function make(getPlayer)
    local A = {}

    function A.charIdOf(src)
        local p = getPlayer(src)
        return p and p.PlayerData and p.PlayerData.citizenid or nil
    end

    function A.getChar(src)
        local p = getPlayer(src)
        if not p or not p.PlayerData then return nil end
        local d = p.PlayerData
        local info = d.charinfo or {}
        local age, hours, hasId = B.characterStats(src, d.citizenid, B.ageFromDob(info.birthdate))
        return { charId = d.citizenid, name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''), age = age, playHours = hours, hasId = hasId }
    end

    function A.getBank(src)
        local p = getPlayer(src)
        return p and p.Functions.GetMoney('bank') or 0
    end

    function A.addBank(src, amount, reason)
        local p = getPlayer(src)
        if p then p.Functions.AddMoney('bank', amount, reason) end
    end

    function A.removeBank(src, amount, reason)
        local p = getPlayer(src)
        return p ~= nil and p.Functions.RemoveMoney('bank', amount, reason) == true
    end

    function A.getOfficial(src)
        local p = getPlayer(src)
        local job = p and p.PlayerData and p.PlayerData.job
        if not job then return nil end
        local grade = type(job.grade) == 'table' and job.grade.level or job.grade
        local rank = B.rankOfJob(job.name, grade)
        if not rank then return nil end
        return { rank = rank, dienstnr = B.dienstnr(p.PlayerData.citizenid) }
    end

    function A.treasuryAdd(amount, reason)
        local t = treasuryBackend()
        if t then pcall(t.add, Config.Treasury.account, amount, reason) end
    end

    function A.treasuryRemove(amount, reason)
        local t = treasuryBackend()
        if not t then return false end
        local ok, res = pcall(t.remove, Config.Treasury.account, amount, reason)
        return ok and res == true
    end

    function A.addItem(src, item, metadata)
        local p = getPlayer(src)
        return p ~= nil and p.Functions.AddItem(item, 1, false, metadata) == true
    end

    function A.hasItem(src, item)
        local p = getPlayer(src)
        local it = p and p.Functions.GetItemByName(item)
        return it ~= nil and (it.amount or it.count or 0) > 0
    end

    return A
end

-- QBCore
do
    local QBCore
    local A = make(function(src) return QBCore and QBCore.Functions.GetPlayer(src) or nil end)
    B.adapters.qb = A
    function A.detect() return GetResourceState('qb-core') == 'started' and GetResourceState('qbx_core') ~= 'started' end
    function A.setup()
        QBCore = exports['qb-core']:GetCoreObject()
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            local src = player and player.PlayerData and player.PlayerData.source
            if src and B.onLogin then B.onLogin(src) end
        end)
    end
end

-- Qbox
do
    local A = make(function(src) return exports.qbx_core:GetPlayer(src) end)
    B.adapters.qbox = A
    function A.detect() return GetResourceState('qbx_core') == 'started' end
    function A.setup()
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            local src = player and player.PlayerData and player.PlayerData.source
            if src and B.onLogin then B.onLogin(src) end
        end)
    end
end
