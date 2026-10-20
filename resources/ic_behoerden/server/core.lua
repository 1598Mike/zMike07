--[[
    ic_behoerden · Kern
    Zeit, Zähler, Einstellungen, Protokoll, Benachrichtigungen, Zahlungen, Webhooks und Hooks.
]]

IC = IC or {}
local S = IC.store
local R = IC.rules
local U = IC.util

-- ---------------------------------------------------------------------------
-- Zeit in Millisekunden. In den Tests lässt sich IC.now ersetzen.
-- ---------------------------------------------------------------------------
IC.now = function() return os.time() * 1000 end

function IC.debug(...)
    if Config.Debug then print('[ic_behoerden]', ...) end
end

-- ---------------------------------------------------------------------------
-- Einstellungen und Zähler (Tabelle settings, je Zeile ein JSON-Wert)
-- ---------------------------------------------------------------------------
local function setting(id, default)
    local row = S.get('settings', id)
    if not row then row = S.put('settings', { id = id, value = default }) end
    return row
end

-- Nächste Nummer einer Folge. start ist der Wert vor der ersten Vergabe.
function IC.nextSeq(key, start)
    local row = setting('seq', {})
    -- math.floor liefert eine ganze Zahl, auch wenn der Wert als Fließkommazahl aus JSON kam (sonst entstünde "T-6.0")
    local v = math.floor(row.value[key] or start or 0) + 1
    row.value[key] = v
    S.put('settings', row)
    return v
end

IC.settings = {}
local SETTING_DEFAULTS = function()
    return {
        requireOfficials = Config.Appointments.requireOfficials,
        writtenProcedure = Config.Appointments.writtenProcedure,
        undergroundViaPortal = Config.Organizations.undergroundViaPortal,
        fourEyes = Config.Decisions.fourEyes,
    }
end

function IC.settings.all()
    local out = SETTING_DEFAULTS()
    local row = S.get('settings', 'toggles')
    if row then for k, v in pairs(row.value) do if out[k] ~= nil then out[k] = v end end end
    return out
end

function IC.settings.get(key) return IC.settings.all()[key] end

function IC.settings.set(key, value)
    if SETTING_DEFAULTS()[key] == nil then return false end
    local row = setting('toggles', {})
    row.value[key] = value and true or false
    S.put('settings', row)
    return true
end

function IC.branchCap(b)
    local row = S.get('settings', 'caps')
    if row and row.value[b.key] ~= nil then return row.value[b.key] end
    return b.cap
end

function IC.setBranchCap(key, value)
    local row = setting('caps', {})
    row.value[key] = U.clamp(U.round(tonumber(value) or 0), 0, 99)
    S.put('settings', row)
    return row.value[key]
end

function IC.undergroundCap()
    local row = S.get('settings', 'caps')
    local max = (row and row.value.untergrund) or Config.Organizations.undergroundCap
    local used = S.count('entities', function(e) return e.ooc and e.ooc.category == 'untergrund' and e.status ~= 'aufgeloest' end)
    return { used = used, max = max }
end

-- Zahlungsströme dieses Systems (nur zur Anzeige im Staff-Panel und zur Buchführung)
function IC.ledger(key, delta)
    local row = setting('ledger', { treasury = 0, escrow = 0 })
    row.value[key] = (row.value[key] or 0) + delta
    S.put('settings', row)
    return row.value[key]
end

function IC.ledgerGet(key)
    local row = S.get('settings', 'ledger')
    return row and row.value[key] or 0
end

-- ---------------------------------------------------------------------------
-- Protokoll (Audit). Neueste zuerst, im Speicher die letzten 500, in der Datenbank alle.
-- ---------------------------------------------------------------------------
IC.auditLog = {}

function IC.audit(actor, kind, action, target, detail)
    local row = { ts = IC.now(), actor = actor, kind = kind, action = action, target = target or '', detail = detail or '' }
    table.insert(IC.auditLog, 1, row)
    if #IC.auditLog > 500 then table.remove(IC.auditLog) end
    if IC.persistAudit then IC.persistAudit(row) end
    return row
end

-- ---------------------------------------------------------------------------
-- Hooks und Ereignisse
-- ---------------------------------------------------------------------------
-- Ruft einen Hook aus Config.Hooks auf und gibt dessen Ergebnis zurück. Ein Fehler im Hook bricht nichts ab (Rückgabe nil).
function IC.hook(name, ...)
    local fn = Config.Hooks and Config.Hooks[name]
    if type(fn) ~= 'function' then return nil end
    local ok, res = pcall(fn, ...)
    if not ok then print('[ic_behoerden] Fehler im Hook ' .. name .. ': ' .. tostring(res)) return nil end
    return res
end

function IC.emit(event, ...)
    if IC.bridge and IC.bridge.emit then IC.bridge.emit(event, ...) end
end

-- ---------------------------------------------------------------------------
-- Benachrichtigungen. Gespeichert (für Spieler, die gerade offline sind) und, falls online, sofort zugestellt.
-- ---------------------------------------------------------------------------
function IC.notify(charId, text, kind)
    if not charId then return end
    local id = IC.nextSeq('notice', 0)
    S.put('notices', { id = id, charId = charId, text = text, kind = kind or 'info', ts = IC.now() })
    local src = IC.bridge.srcOfChar(charId)
    if src then
        local phone = Config.Hooks and Config.Hooks.phoneMessage
        if type(phone) == 'function' then pcall(phone, charId, 'Gewerbeamt und Bürgeramt', text) end
        IC.bridge.notify(src, text, kind or 'info')
    end
    -- alte Nachrichten aufräumen (30 Tage)
    local cutoff = IC.now() - 30 * R.DAY
    if id % 50 == 0 then
        for _, n in ipairs(S.list('notices', function(x) return x.ts < cutoff end)) do S.del('notices', n.id) end
    end
end

function IC.noticesFor(charId, limit)
    local list = U.sortBy(S.list('notices', function(n) return n.charId == charId end), function(n) return n.id end)
    local out = {}
    for i = math.max(1, #list - (limit or 6) + 1), #list do out[#out + 1] = list[i] end
    return out
end

-- ---------------------------------------------------------------------------
-- Zahlungen. Der Spieler zahlt beim Einreichen:
--   Antragsgebühr      -> Stadtkasse (endgültig)
--   Eintragungsgebühr  -> Verwahrung, bei Genehmigung Stadtkasse, sonst zurück
--   Kapital            -> Verwahrung, bei Genehmigung per Hook an das Unternehmen, sonst zurück
-- ---------------------------------------------------------------------------
IC.pay = {}

function IC.pay.charge(src, amount, reason)
    if amount <= 0 then return true end
    return IC.bridge.removeBank(src, amount, reason) == true
end

function IC.pay.toTreasury(amount, reason)
    if amount <= 0 then return end
    IC.bridge.treasuryAdd(amount, reason)
    IC.ledger('treasury', amount)
end

function IC.pay.escrowIn(amount) IC.ledger('escrow', amount) end
function IC.pay.escrowOut(amount) IC.ledger('escrow', -amount) end

-- Erstattung an einen Charakter. Ist er offline, wird sie gemerkt und beim nächsten Login ausgezahlt.
function IC.pay.refund(charId, amount, reason)
    if amount <= 0 then return end
    IC.pay.escrowOut(amount)
    local src = IC.bridge.srcOfChar(charId)
    if src then
        IC.bridge.addBank(src, amount, reason)
        IC.notify(charId, U.money(amount) .. ' wurden Ihnen erstattet.', 'ok')
    else
        S.put('refunds', { id = IC.nextSeq('refund', 0), charId = charId, amount = amount, reason = reason, ts = IC.now() })
    end
end

-- Zahlt offene Erstattungen aus, sobald ein Charakter online ist (wird beim Login aufgerufen).
function IC.pay.flushRefunds(charId, src)
    for _, r in ipairs(S.list('refunds', function(x) return x.charId == charId end)) do
        IC.bridge.addBank(src, r.amount, r.reason)
        IC.notify(charId, U.money(r.amount) .. ' wurden Ihnen erstattet.', 'ok')
        S.del('refunds', r.id)
    end
end

-- Terminpauschale für den Beamten, aus der Stadtkasse. Ist die Kasse nicht gedeckt, wird trotzdem gezahlt (wie ein Gehalt)
-- und im Protokoll vermerkt, damit kein Beamter für leere Stadtfinanzen büßt.
function IC.pay.official(src, amount, reason)
    if amount <= 0 then return end
    local covered = IC.bridge.treasuryRemove == nil or IC.bridge.treasuryRemove(amount, reason) == true
    if not covered then IC.audit('System', 'system', 'Stadtkasse nicht gedeckt', '', U.money(amount) .. ' ohne Deckung gezahlt: ' .. tostring(reason)) end
    IC.bridge.addBank(src, amount, reason)
    IC.ledger('treasury', -amount)
end

-- ---------------------------------------------------------------------------
-- Discord. url leer = aus.
-- ---------------------------------------------------------------------------
function IC.webhook(kind, title, text)
    local url = Config.Webhooks and Config.Webhooks[kind]
    if not url or url == '' or not IC.bridge.http then return end
    IC.bridge.http(url, { username = 'Gewerbeamt', embeds = { { title = title, description = text, color = 1004161, footer = { text = Config.City } } } })
end

-- ---------------------------------------------------------------------------
-- Antworten an die Oberfläche
-- ---------------------------------------------------------------------------
function IC.ok(t)
    t = t or {}
    t.ok = true
    return t
end

function IC.fail(message, t)
    t = t or {}
    t.ok = false
    t.error = message
    return t
end
