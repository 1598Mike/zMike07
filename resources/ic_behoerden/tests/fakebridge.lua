--[[
    Fake-Bridge und Test-Harness: bildet Spieler, Konten, Dienst und Benachrichtigungen im Speicher nach.
    So lässt sich die gesamte Server-Logik ohne FiveM durchspielen.
]]

local R = IC.rules
local H = {}

local B = {}
IC.bridge = B
H.bridge = B

local function resetBridge()
    B.players, B.notices, B.certificates, B.invitesAsked, B.treasury, B.emitted, B.hooks = {}, {}, {}, {}, 0, {}, {}
end
resetBridge()

-- p: { charId, name, age, playHours, hasId, bank, rank (Beamte), area (wer in derselben Gruppe steht, ist "in der Nähe") }
function H.player(src, p)
    p.hasId = p.hasId == nil and true or p.hasId
    p.age = p.age or 30
    p.playHours = p.playHours or 100
    p.bank = p.bank or 100000
    p.area = p.area or 1
    B.players[src] = p
    return src
end

function B.getChar(src) local p = B.players[src]; return p and { charId = p.charId, name = p.name, age = p.age, playHours = p.playHours, hasId = p.hasId } end
function B.charIdOf(src) local p = B.players[src]; return p and p.charId end
function B.srcOfChar(charId) for src, p in pairs(B.players) do if p.charId == charId then return src end end end
function B.getBank(src) return B.players[src].bank end
function B.removeBank(src, amount, reason)
    local p = B.players[src]
    if not p or p.bank < amount then return false end
    p.bank = p.bank - amount
    return true
end
function B.addBank(src, amount, reason) B.players[src].bank = B.players[src].bank + amount end
function B.treasuryAdd(amount, reason) B.treasury = B.treasury + amount end
function B.treasuryRemove(amount, reason)
    if B.treasury < amount then return false end
    B.treasury = B.treasury - amount
    return true
end
function B.coords(src) local p = B.players[src]; return p and p.coords end
function B.distance(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0); return math.sqrt(dx * dx + dy * dy + dz * dz) end
function B.online() local out = {}; for src in pairs(B.players) do out[#out + 1] = src end; table.sort(out); return out end
function B.getOfficial(src) local p = B.players[src]; if p and p.rank then return { rank = p.rank, dienstnr = 'T-' .. src } end end
function B.isNear(a, b, r) local x, y = B.players[a], B.players[b]; return x ~= nil and y ~= nil and x.area == y.area end
function B.getNearby(src, r)
    local out = {}
    for s, p in pairs(B.players) do
        if s ~= src and p.area == B.players[src].area then out[#out + 1] = { charId = p.charId, name = p.name, age = p.age, playHours = p.playHours, hasId = p.hasId, src = s } end
    end
    table.sort(out, function(a, b) return a.charId < b.charId end)
    return out
end
function B.notify(src, text, kind) B.notices[#B.notices + 1] = { src = src, text = text, kind = kind } end
function B.askInvite(targetSrc, fromName) B.invitesAsked[#B.invitesAsked + 1] = { src = targetSrc, from = fromName } end
function B.giveCertificate(src, e) B.certificates[#B.certificates + 1] = { src = src, regNo = e.regNo }; return true end
function B.emit(event, ...) B.emitted[#B.emitted + 1] = event end

-- Hilfen für Tests --------------------------------------------------------------
function H.lastNotice(src, pattern)
    for i = #B.notices, 1, -1 do
        local n = B.notices[i]
        if n.src == src and (not pattern or n.text:find(pattern, 1, true)) then return n end
    end
end

local MIN, HOUR, DAY = R.MIN, R.HOUR, R.DAY
H.MIN, H.HOUR, H.DAY = MIN, HOUR, DAY
H.clock = 0

function H.advance(ms) H.clock = H.clock + ms end

-- Setzt alles zurück: Speicher, Dienst, Warteschlange, Einladungen, Uhr (Starttag 18:00 Uhr Ortszeit)
function H.reset()
    resetBridge()
    IC.store.reset()
    IC.duty.byChar = {}
    IC.apps.invites = {}
    IC.queue = { list = {}, seq = 0, calling = nil, called = {} }
    IC.auditLog = {}
    IC.util.startOfDay(1) -- warm
    local base = IC.util.startOfDay(1760000000000)
    H.clock = base + 18 * HOUR
    IC.now = function() return H.clock end
    Config.Appointments.mode = 'hybrid'
    Config.Hooks.onApproved = function(e, a) B.hooks[#B.hooks + 1] = { 'onApproved', e.regNo } end
    Config.Hooks.onSanction = function(e, s) B.hooks[#B.hooks + 1] = { 'onSanction', e.regNo, s.level } end
    IC.staff.seed()
end

-- Kontext wie ihn net.lua baut ---------------------------------------------------
function H.ctx(src, session, extra)
    local char = B.getChar(src)
    local o = B.getOfficial(src)
    local ctx = { src = src, char = char, session = session or 'gewerbeamt', staffName = 'Admin' }
    if o then ctx.off = { id = char.charId, name = char.name, rank = o.rank, dienstnr = o.dienstnr, src = src } end
    for k, v in pairs(extra or {}) do ctx[k] = v end
    return ctx
end

function H.call(src, session, name, data, extra)
    return IC.api.call(H.ctx(src, session, extra), name, data or {})
end
function H.staff(name, data)
    if not B.players[99] then H.player(99, { charId = 'c-staff', name = 'Admin', area = 3 }) end
    return IC.api.call(H.ctx(99, 'staff', { staff = true }), name, data or {})
end

return H
