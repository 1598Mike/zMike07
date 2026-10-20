--[[
    ic_behoerden · Protokoll zwischen Oberfläche, Client und Server

    Jeder Aufruf der Oberfläche hat einen Namen. Der Client reicht ihn unverändert an den Server weiter.
    Der Server entscheidet anhand dieser Tabelle, wer ihn ausführen darf. Unbekannte Namen werden abgelehnt.

    Gruppen:
      any      jeder Spieler mit geöffneter Oberfläche
      citizen  Sitzung am Gewerbeamt oder Bürgeramt
      official Sitzung am Beamten-Schalter, Spieler hat einen Beamten-Job
      staff    Sitzung über den Befehl des Staffs, Spieler hat das ACE-Recht
]]

IC = IC or {}

IC.protocol = {
    groups = {
        bootstrap = 'any', nameCheck = 'any',

        appSave = 'citizen', appSubmit = 'citizen', appWithdraw = 'citizen', appObjection = 'citizen',
        entityChange = 'citizen', entityDissolve = 'citizen', entityDuplicate = 'citizen', legacyConfirm = 'citizen',
        registerSearch = 'citizen', slotsList = 'citizen', apptBook = 'citizen', apptCancel = 'citizen', apptCheckin = 'citizen',
        queueTake = 'citizen', queueLeave = 'citizen', notifyOnDuty = 'citizen',
        founderInvite = 'citizen', founderStatus = 'citizen', founderCancel = 'citizen',

        dutySet = 'official', appReview = 'official', conflictReport = 'official', apptCall = 'official', apptStart = 'official',
        apptNoShow = 'official', apptDecide = 'official', queueNext = 'official', hoursCreate = 'official', hoursDelete = 'official',
        sanctionIssue = 'official',

        staffGate = 'staff', staffWritten = 'staff', staffCap = 'staff', staffBlacklistAdd = 'staff',
        staffBlacklistRemove = 'staff', staffSetting = 'staff', staffEntityStatus = 'staff',
    },
    -- Anwendungen, die sich öffnen lassen, und welche Gruppe dafür nötig ist
    apps = {
        gewerbeamt = 'citizen', buergeramt = 'citizen', beamte = 'official', staff = 'staff',
    },
}

-- Namen als Liste (für die NUI-Rückrufe des Clients)
function IC.protocol.names()
    local out = {}
    for name in pairs(IC.protocol.groups) do out[#out + 1] = name end
    table.sort(out)
    return out
end
