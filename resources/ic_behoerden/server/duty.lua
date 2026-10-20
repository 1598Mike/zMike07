--[[
    ic_behoerden · Dienst der Beamten
    Wer im Dienst ist, bestimmt, ob es Live-Termine gibt. Der Dienststatus liegt in diesem System und nur im Arbeitsspeicher:
    Nach einem Neustart sind alle außer Dienst. Das ist gewollt, niemand soll unbemerkt "im Dienst" bleiben.
]]

IC = IC or {}
local R, U, S = IC.rules, IC.util, IC.store
local D = { byChar = {} }
IC.duty = D

-- state: 'on' | 'pause' | 'off'. off: { id, src, name, rank, dienstnr }
function D.set(off, state, desk)
    local cur = D.byChar[off.id]
    local was = cur and cur.state or 'off'
    local maxDesk = (Config.Officials and Config.Officials.desks) or 4
    D.byChar[off.id] = {
        id = off.id, src = off.src, name = off.name, rank = off.rank, dienstnr = off.dienstnr, state = state,
        desk = U.clamp(U.round(tonumber(desk) or (cur and cur.desk) or 1), 1, maxDesk),
        since = (state ~= was) and IC.now() or (cur and cur.since) or IC.now(),
    }
    return was
end

function D.get(charId) return D.byChar[charId] end
function D.remove(charId) D.byChar[charId] = nil end

function D.removeBySrc(src)
    for id, d in pairs(D.byChar) do
        if d.src == src then D.byChar[id] = nil end
    end
end

-- Beamte, die jetzt bedienen können. Prüft bei jedem Aufruf, ob der Spieler noch online ist und seinen Job hat.
function D.list()
    local out = {}
    for id, d in pairs(D.byChar) do
        if d.state == 'on' then
            local cur = IC.bridge.getOfficial(d.src)
            if cur and IC.bridge.charIdOf(d.src) == id then
                d.rank = cur.rank
                out[#out + 1] = { id = id, src = d.src, name = d.name, rank = d.rank, desk = d.desk, dienstnr = d.dienstnr }
            else
                D.byChar[id] = nil
            end
        end
    end
    return U.sortBy(out, function(o) return string.format('%02d%s', o.desk, o.id) end)
end

function D.eligible(type)
    return U.filter(D.list(), function(o) return R.rankAtLeast(o.rank, type.minRank) end)
end

-- Rang eines Beamten für die Slot-Berechnung. Online: aktueller Rang (nil, wenn er den Job verloren hat).
-- Offline: der Rang aus der Sprechzeit, weil sich ein Offline-Rang nicht prüfen lässt.
function D.rankOf(officialId, snapshotRank)
    local src = IC.bridge.srcOfChar(officialId)
    if src then
        local o = IC.bridge.getOfficial(src)
        return o and o.rank or nil
    end
    return snapshotRank
end
