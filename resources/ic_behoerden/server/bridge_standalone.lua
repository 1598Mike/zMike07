--[[
    ic_behoerden · Adapter ohne Framework (nur zum Testen)
    Jeder verbundene Spieler ist ein Charakter. Konten und Stadtkasse liegen nur im Speicher und sind nach einem Neustart weg.
    Beamte vergibt das ACE-System:
      add_ace identifier.license:XXXX ic_behoerden.official.sachbearbeiter allow
    Es gibt vier Stufen: anwaerter, sachbearbeiter, amtsleiter, leitung. Die höchste erlaubte Stufe zählt.
]]

IC = IC or {}
local B = IC.bridge
local A = {}
B.adapters.standalone = A

local bank, treasury = {}, 0

function A.detect() return true end

function A.charIdOf(src)
    if not GetPlayerName(src) then return nil end
    local id
    if GetPlayerIdentifierByType then id = GetPlayerIdentifierByType(src, 'license') end
    return id or ('src:' .. tostring(src))
end

function A.getChar(src)
    local id = A.charIdOf(src)
    if not id then return nil end
    local s = Config.Standalone or {}
    local age, hours, hasId = B.characterStats(src, id, s.age or 30, s.playHours or 100)
    return { charId = id, name = GetPlayerName(src), age = age, playHours = hours, hasId = hasId }
end

local function account(src)
    local id = A.charIdOf(src)
    if bank[id] == nil then bank[id] = (Config.Standalone and Config.Standalone.startBank) or 50000 end
    return id
end

function A.getBank(src) return bank[account(src)] end
function A.addBank(src, amount) local id = account(src); bank[id] = bank[id] + amount end
function A.removeBank(src, amount)
    local id = account(src)
    if bank[id] < amount then return false end
    bank[id] = bank[id] - amount
    return true
end

function A.treasuryAdd(amount) treasury = treasury + amount end
function A.treasuryRemove(amount)
    if treasury < amount then return false end
    treasury = treasury - amount
    return true
end

-- Höchste erlaubte Stufe laut ACE
function A.getOfficial(src)
    local id = A.charIdOf(src)
    if not id then return nil end
    local best, bestLevel = nil, -1
    for rank, level in pairs(Config.Ranks or {}) do
        if level > bestLevel and IsPlayerAceAllowed(src, 'ic_behoerden.official.' .. rank) then best, bestLevel = rank, level end
    end
    if not best then return nil end
    return { rank = best, dienstnr = B.dienstnr(id) }
end

-- Ohne Inventar gibt es keinen Schein; der Eintrag ist trotzdem gültig und in der Oberfläche einsehbar.
function A.addItem() return false end
function A.hasItem() return true end
