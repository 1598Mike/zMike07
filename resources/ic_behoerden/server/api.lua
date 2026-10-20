--[[
    ic_behoerden · API
    Setzt die Aufrufe der Oberfläche (shared/protocol.lua) auf die Domänenfunktionen um.
    IC.api.call prüft Rolle und Sitzung zentral. Die Funktionen selbst prüfen nur noch Fachregeln.

    ctx = {
        src      Spieler-ID
        char     { charId, name, age, playHours, hasId }  (Bridge)
        off      { id, name, rank, dienstnr, src } oder nil, wenn der Spieler kein Beamter ist (Bridge)
        staff    true, wenn der Spieler das ACE-Recht hat
        staffName  Name für das Protokoll
        session  geöffnete Anwendung: gewerbeamt, buergeramt, beamte oder staff
    }
]]

IC = IC or {}
local R, U, S = IC.rules, IC.util, IC.store
local ok, fail = IC.ok, IC.fail
local A, D, P, G, Sf = IC.apps, IC.duty, IC.appt, IC.register, IC.staff
local API = {}
IC.api = API

local function lastTs(a) return A.lastTs(a) end

-- ---------------------------------------------------------------------------
-- bootstrap: alles, was die Oberfläche der gewählten Anwendung braucht
-- ---------------------------------------------------------------------------
local function configPayload()
    local branches = {}
    for _, b in ipairs(Config.Branches) do
        local c = U.deepcopy(b)
        c.cap, c.used = IC.branchCap(b), G.branchUsed(b.key)
        branches[#branches + 1] = c
    end
    return {
        city = Config.City, currency = Config.Currency, rules = Config.Rules, legalForms = Config.LegalForms, branches = branches,
        orgRoles = Config.OrgRoles, companyRoles = Config.CompanyRoles, appointmentTypes = Config.AppointmentTypes,
        checklists = Config.Checklists, conditionPresets = Config.ConditionPresets, reasonPresets = Config.ReasonPresets,
    }
end

local function myAppointments(charId)
    local list = S.list('appointments', function(a)
        if a.booker == charId then return true end
        for _, x in ipairs(a.attendees or {}) do if x.charId == charId then return true end end
        return false
    end)
    return U.map(U.sortBy(list, function(a) return a.start end), P.view)
end

-- Gewerbeamt und Bürgeramt sind ein Fenster mit zwei Startseiten: Wer an einem der beiden Terminals sitzt, kann in der Oberfläche
-- zum anderen wechseln (die Kacheln "Termin im Bürgeramt" und "Meine Termine" führen dorthin). Tablet und Staff-Panel bleiben getrennt.
local CITIZEN_APP = { gewerbeamt = true, buergeramt = true }

function API.bootstrap(ctx, p)
    local app = ctx.session
    if p and p.app and p.app ~= ctx.session and not (CITIZEN_APP[p.app] and CITIZEN_APP[ctx.session]) then return fail('Diese Anwendung ist nicht geöffnet.') end
    IC.tick()
    local me = ctx.char
    local duty = D.list()
    local row = S.get('chars', me.charId)
    local nearby = {}
    for _, x in ipairs(IC.bridge.getNearby(ctx.src, 15.0)) do
        nearby[#nearby + 1] = { charId = x.charId, name = x.name, age = x.age, playHours = x.playHours, hasId = x.hasId, elig = R.eligibility(x, 'unternehmen', {}) }
    end
    local props = {}
    for _, x in ipairs(A.properties()) do
        local c = U.deepcopy(x)
        c.taken = A.propertyTaken(x.id)
        props[#props + 1] = c
    end
    local owned = U.map(G.ownedBy(me.charId, true), function(e) local c = G.stripOoc(e); c.myOwn = true; return c end)
    local mine = S.list('applications', function(a) return A.mine(a, me.charId) end)
    local out = {
        ok = true, now = IC.now(), config = configPayload(),
        me = {
            charId = me.charId, name = me.name, age = me.age, playHours = me.playHours, hasId = me.hasId, bank = IC.bridge.getBank(ctx.src),
            notifyOnDuty = row and row.notifyOnDuty or false, banUntil = IC.strikes.banUntil(me.charId), activeStrikes = #IC.strikes.active(me.charId),
        },
        duty = {
            count = #duty, nextFree = P.nextFree(), othersSetting = 0,
            officials = U.map(duty, function(o) return { id = o.id, name = o.name, rank = o.rank, desk = o.desk } end),
        },
        board = P.board(),
        myApplications = U.map(U.sortBy(mine, lastTs, true), U.deepcopy),
        myEntities = owned,
        myAppointments = myAppointments(me.charId),
        myTicket = P.myTicket(me.charId),
        nearby = nearby, properties = props,
        eligibility = { unternehmen = A.eligibility(ctx, 'unternehmen'), fraktion = A.eligibility(ctx, 'fraktion') },
        notices = IC.noticesFor(me.charId, 6),
        settings = { undergroundViaPortal = IC.settings.get('undergroundViaPortal') },
    }

    if app == 'beamte' and ctx.off then
        local mineD = D.get(ctx.off.id)
        out.official = {
            id = ctx.off.id, name = ctx.off.name, rank = ctx.off.rank, dienstnr = ctx.off.dienstnr,
            state = mineD and mineD.state or 'off', desk = mineD and mineD.desk or 1, onDuty = mineD ~= nil and mineD.state == 'on', level = R.rankLevel(ctx.off.rank),
        }
        local apps = S.list('applications', function(a) return not A.conflicted(a, ctx.off.id) end)
        out.officialApps = U.map(U.sortBy(apps, lastTs, true), IC.register.stripOoc)
        local cutoff = IC.now() - R.DAY
        local appts = S.list('appointments', function(a) return R.OPEN_APPT[a.status] or a.start > cutoff end)
        out.officialAppts = U.map(U.sortBy(appts, function(a) return a.start end), P.view)
        out.queue = U.deepcopy(IC.queue.list)
        out.hours = U.map(U.sortBy(S.list('officeHours', function(h) return h.finish > IC.now() end), function(h) return h.start end), function(h)
            return { id = h.id, officialId = h.officialId, official = h.officialName, start = h.start, ['end'] = h.finish, types = h.types, mine = h.officialId == ctx.off.id }
        end)
        out.register = U.map(S.list('entities'), G.stripOoc)
        out.coworkers = U.map(U.filter(duty, function(o) return o.id ~= ctx.off.id end), function(o) return { id = o.id, name = o.name, rank = o.rank, desk = o.desk } end)
    end
    if app == 'staff' and ctx.staff then out.staff = Sf.overview() end
    return out
end

-- ---------------------------------------------------------------------------
-- Zuordnung Name -> Funktion
-- ---------------------------------------------------------------------------
local H = {
    bootstrap = API.bootstrap,
    nameCheck = A.nameCheck,
    appSave = A.save, appSubmit = A.submit, appWithdraw = A.withdraw, appObjection = A.objection,
    entityChange = A.entityChange, entityDissolve = A.entityDissolve, entityDuplicate = A.entityDuplicate, legacyConfirm = A.legacyConfirm,
    registerSearch = A.registerSearch,
    founderInvite = A.founderInvite, founderStatus = A.founderStatus, founderCancel = A.founderCancel,
    slotsList = P.slotsList, apptBook = P.book, apptCancel = P.cancel, apptCheckin = P.checkin,
    queueTake = P.queueTake, queueLeave = P.queueLeave, notifyOnDuty = P.notifyOnDuty,

    dutySet = P.dutySet, appReview = A.review, conflictReport = A.conflictReport, apptCall = P.call, apptStart = P.start,
    apptNoShow = P.noShow, apptDecide = P.decide, queueNext = P.queueNext, hoursCreate = P.hoursCreate, hoursDelete = P.hoursDelete,
    sanctionIssue = P.sanction,

    staffGate = Sf.gate, staffWritten = Sf.written, staffCap = Sf.cap, staffBlacklistAdd = Sf.blacklistAdd,
    staffBlacklistRemove = Sf.blacklistRemove, staffSetting = Sf.setting, staffEntityStatus = Sf.entityStatus,
}
API.handlers = H

-- Antwort-Felder, die die Oberfläche anders nennt als der Server intern. hoursCreate bekommt "end" von der Oberfläche.
local function normalize(name, data)
    if name == 'hoursCreate' and data['end'] ~= nil and data.finish == nil then data.finish = data['end'] end
    return data
end

local GROUP_OF_APP = { gewerbeamt = 'citizen', buergeramt = 'citizen', beamte = 'official', staff = 'staff' }

function API.call(ctx, name, data)
    local group = IC.protocol.groups[name]
    local handler = H[name]
    if not group or not handler then return fail('Unbekannte Aktion.') end
    data = normalize(name, type(data) == 'table' and data or {})
    if not ctx.session or not GROUP_OF_APP[ctx.session] then return fail('Bitte öffnen Sie die Anwendung an einem Terminal.') end
    if not ctx.char then return fail('Kein Charakter geladen.') end
    if group == 'citizen' and GROUP_OF_APP[ctx.session] ~= 'citizen' then return fail('Diese Aktion ist hier nicht möglich.') end
    if group == 'official' then
        if ctx.session ~= 'beamte' or not ctx.off then return fail('Dafür sind Sie nicht befugt.') end
    end
    if group == 'staff' then
        if ctx.session ~= 'staff' or not ctx.staff then return fail('Dafür sind Sie nicht befugt.') end
    end
    local okc, res = pcall(handler, ctx, data)
    if not okc then
        print(('[ic_behoerden] Fehler in %s: %s'):format(name, tostring(res)))
        return fail('Interner Fehler. Bitte melden Sie dies dem Team.')
    end
    return res
end

-- Regelmäßig und vor jedem bootstrap: Fristen, Ausfälle
function IC.tick()
    A.tick()
    P.tick()
end
