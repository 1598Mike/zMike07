--[[
    ic_behoerden · Start
    Wartet auf die Datenbank und das Framework, lädt alles in den Speicher und startet die Dauerarbeit.
    Danach nehmen die Ereignisse aus net.lua Aufrufe an.
]]

IC = IC or {}
local U, S, G = IC.util, IC.store, IC.register

-- ---------------------------------------------------------------------------
-- Funktionen für andere Ressourcen:  exports.ic_behoerden:getEntity('HRB 0301')
-- ---------------------------------------------------------------------------
IC.public = {}

local function key(s) return (tostring(s or ''):lower():gsub('%s', '')) end

-- Registereintrag nach Registernummer. Ohne OOC-Angaben, mit withOoc = true auch mit der Fraktionsart (nur für Server-Skripte).
function IC.public.getEntity(regNo, withOoc)
    local k = key(regNo)
    for _, e in ipairs(S.list('entities')) do
        if key(e.regNo) == k then return withOoc and U.deepcopy(e) or G.stripOoc(e) end
    end
end

-- Alle nicht aufgelösten Einträge, in denen der Charakter Mitglied ist, mit seiner Rolle
function IC.public.getEntitiesOf(charId)
    local out = {}
    for _, e in ipairs(S.list('entities', function(x) return x.status ~= 'aufgeloest' end)) do
        for _, m in ipairs(e.members or {}) do
            if m.charId == charId then
                out[#out + 1] = { regNo = e.regNo, name = e.name, kind = e.kind, legalForm = e.legalForm, branch = e.branch, status = e.status, role = m.role, share = m.share }
            end
        end
    end
    return U.sortBy(out, function(x) return x.regNo end)
end

-- Rolle des Charakters im Eintrag ('inhaber', 'geschaeftsfuehrer', 'vorsitz', 'mitglied' ...) oder nil
function IC.public.getMemberRole(charId, regNo)
    local e = IC.public.getEntity(regNo)
    if not e or e.status == 'aufgeloest' then return nil end
    for _, m in ipairs(e.members or {}) do
        if m.charId == charId then return m.role end
    end
end

function IC.public.getOfficialsOnDuty()
    return U.map(IC.duty.list(), function(o) return { charId = o.id, name = o.name, rank = o.rank, desk = o.desk } end)
end

for name, fn in pairs(IC.public) do exports(name, fn) end

-- ---------------------------------------------------------------------------
-- Start und Stopp
-- ---------------------------------------------------------------------------
MySQL.ready(function()
    local ok, err = pcall(function()
        IC.persist.init()
        if not IC.bridge.waitForFramework(20000) then print('[ic_behoerden] Kein Framework gefunden (Config.Framework = "' .. tostring(Config.Framework) .. '").') end
        IC.bridge.init()
        IC.staff.seed()
        IC.net.start()
        IC.started = true
    end)
    if not ok then
        print('[ic_behoerden] Start fehlgeschlagen: ' .. tostring(err))
        return
    end
    print(('[ic_behoerden] Bereit: %d Anträge, %d Einträge, %d Termine.'):format(S.count('applications'), S.count('entities'), S.count('appointments')))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local n = IC.persist.flushOnStop()
    if n > 0 then print(('[ic_behoerden] %d offene Schreibvorgänge an die Datenbank übergeben.'):format(n)) end
end)
