--[[
    ic_behoerden · Server-Konfiguration

    Alle Zahlen sind Standardwerte aus docs/KONZEPT.md. Bitte an eure Serverwirtschaft anpassen.
    Diese Datei erreicht nie den Client. Hier dürfen Webhook-URLs und Hooks stehen.
]]

Config = Config or {}

Config.Currency = '$'

-- 'auto' erkennt qbx_core, qb-core und es_extended. Sonst: 'esx', 'qb', 'qbox' oder 'standalone' (nur zum Testen).
Config.Framework = 'auto'
Config.Debug = false

-- Legt die Tabellen beim Start selbst an (sql/install.sql, wiederholbar). false: ihr spielt die Datei selbst ein.
Config.AutoInstallSql = true

-- Woher die Ressource Alter, Spielzeit und Ausweis eines Charakters nimmt.
-- Ohne eigene Funktionen: Alter aus dem Geburtsdatum des Frameworks, Spielzeit wird nicht geprüft, Ausweis ist nicht nötig.
Config.Characters = {
    -- Name des Items, das als Personalausweis gilt (zum Beispiel 'id_card'). nil: kein Ausweis nötig.
    idItem = nil,
    -- Alter in Jahren. nil: aus dem Geburtsdatum des Frameworks (Datum der echten Welt minus Geburtsdatum).
    age = nil,        -- function(src, charId) return 29 end
    -- Spielzeit des Charakters in Stunden. nil: nicht geprüft (Config.Rules.minPlayHours wirkt dann nicht).
    playHours = nil,  -- function(src, charId) return exports.mein_playtime:hours(charId) end
}

-- ---------------------------------------------------------------------------
-- Regeln. Alle Werte erreichen auch die Oberfläche (Anzeige), erzwungen wird serverseitig.
-- Zeiten: Minuten, Stunden oder Tage wie im Namen angegeben.
-- ---------------------------------------------------------------------------
Config.Rules = {
    maxOpenApplications = 2,   -- offene Anträge je Charakter
    maxOpenAppointments = 2,   -- offene Termine je Charakter
    maxCompanies        = 2,   -- aktive Unternehmen als Inhaber oder Geschäftsführer
    maxOrgs             = 1,   -- Organisationen als Gründer oder Vorstand
    nameReserveDays     = 7,   -- Namensreservierung ab Einreichung
    fixDays             = 7,   -- Frist für Nachbesserung
    bookDays            = 14,  -- Frist für die Terminbuchung nach bestandener Vorprüfung
    objectionHours      = 48,  -- Einspruchsfrist nach Ablehnung
    cancelFreeMinutes   = 15,  -- Absage bis dahin vor Terminbeginn ist folgenlos
    checkinBefore       = 10,  -- Check-in ab Minuten vor Beginn
    checkinAfter        = 10,  -- Check-in bis Minuten nach Beginn, danach gilt der Termin als versäumt
    liveHorizon         = 60,  -- Live-Termine: so viele Minuten im Voraus buchbar
    slotStep            = 15,  -- Raster der Termine in Minuten
    leadMinutes         = 10,  -- frühestens so viele Minuten vor Beginn buchbar
    bookAheadDays       = 7,   -- Sprechzeiten und Buchungen so viele Tage im Voraus
    minAge              = 18,  -- IC-Alter
    minPlayHours        = 10,  -- Spielzeit des Charakters in Stunden
    strikeLimit         = 3,   -- Strikes, ab denen gesperrt wird
    strikeDays          = 14,  -- so lange zählt ein Strike
    banDays             = 3,   -- Dauer der Terminsperre
    escalateHours       = 72,  -- ab hier erscheint ein Antrag als Eskalation
    probationDays       = 14,  -- Probezeit bei Auflagen
    certDays            = 90,  -- Gültigkeit des Gewerbescheins
    feeChange           = 200, -- Änderungsgebühr
    feeDuplicate        = 100, -- Duplikat des Gewerbescheins
    officialPay         = 150, -- Terminpauschale je durchgeführtem Termin, aus der Stadtkasse
}

-- Terminvergabe
Config.Appointments = {
    -- 'hybrid': Live-Termine (Beamte im Dienst) und Sprechzeiten
    -- 'live':   nur Live-Termine
    -- 'plan':   nur Sprechzeiten
    mode = 'hybrid',
    -- Voreinstellungen. Der Staff kann beides im Panel ändern, die Änderung wird in der Datenbank gespeichert.
    requireOfficials = true,
    writtenProcedure = true,
}

Config.Organizations = {
    -- Untergrund-Fraktionen melden eine legale Hülle an und geben OOC-Angaben ab. Aus: komplett OOC vergeben.
    undergroundViaPortal = true,
    undergroundCap = 8,
}

-- Reserviert für Phase 2 (Gegenzeichnung durch einen zweiten Beamten). Hat in Version 0.1 keine Wirkung.
Config.Decisions = { fourEyes = false }

Config.Legacy = {
    confirmDays = 28,          -- Frist für die Bestandsbestätigung
    remindAfterDays = 14,
    restAfterDays = nil,       -- z. B. 56: danach "ruhend". nil: nie, nur Hinweis.
}

Config.Certificate = {
    item = 'gewerbeschein',    -- Item-Name. Beispiele für ox_inventory und qb-core stehen in docs/TECHNIK.md.
}

-- Stadtkasse: Alle Gebühren fließen dorthin, daraus wird die Terminpauschale gezahlt.
-- Ist die Kasse einmal leer, bekommt der Beamte seine Pauschale trotzdem; das wird im Protokoll vermerkt.
Config.Treasury = {
    account = 'society_gov',   -- ESX: esx_addonaccount, QB: Konto in qb-banking, qb-management oder Renewed-Banking
    -- Eigene Konto-Anbindung (ersetzt die automatische). Beide Funktionen laufen auf dem Server.
    add = nil,                 -- function(amount, reason) end
    remove = nil,              -- function(amount, reason) return true end  (false, wenn nicht gedeckt)
}

-- ---------------------------------------------------------------------------
-- Beamte: Job und Rang. Eine Zeile je Job, darin der Rang je Job-Grade.
-- Ränge: anwaerter, sachbearbeiter, amtsleiter, leitung
-- ANPASSEN: Job-Namen eurer Stadtverwaltung.
-- ---------------------------------------------------------------------------
Config.Officials = {
    jobs = {
        gov = { [0] = 'anwaerter', [1] = 'sachbearbeiter', [2] = 'amtsleiter', [3] = 'leitung' },
    },
    mustBeInOffice = true,     -- Das Tablet lässt sich nur an den Schaltern öffnen
    command = nil,             -- Befehl, der das Tablet überall öffnet. Nur wirksam, wenn mustBeInOffice = false.
    desks = 4,                 -- Anzahl Schalter für die Aufrufanzeige
}

Config.Ranks = {
    anwaerter = 0, sachbearbeiter = 1, amtsleiter = 2, leitung = 3,
}
Config.RankLabels = {
    anwaerter = 'Anwärter', sachbearbeiter = 'Sachbearbeiter', amtsleiter = 'Amtsleiter', leitung = 'Behördenleitung',
}

-- Staff: ACE-Recht für das Panel und den Import.
--   add_ace group.admin ic_behoerden.staff allow
Config.Staff = {
    ace = 'ic_behoerden.staff',
    command = 'icstaff',
    importCommand = 'icimport',
}

-- Discord. Leer lassen, um es abzuschalten.
Config.Webhooks = {
    staff = '',    -- Eingänge, Entscheidungen, Eskalationen
    public = '',   -- Bekanntmachung neuer Eintragungen
}

-- Ohne Framework (nur zum Testen)
Config.Standalone = {
    startBank = 50000,
    age = 30,
    playHours = 100,
}

-- ---------------------------------------------------------------------------
-- Rechtsformen und Branchen
-- ---------------------------------------------------------------------------
Config.LegalForms = {
    { key = 'einzel',   label = 'Einzelunternehmen',            kind = 'unternehmen', minFounders = 1, feeApply = 250, feeRegister = 750,  capital = 0,     suffix = '',         register = 'HRA', desc = 'Ein Inhaber, volle Verantwortung. Schnell und günstig.' },
    { key = 'gbr',      label = 'GbR',                          kind = 'unternehmen', minFounders = 2, feeApply = 400, feeRegister = 1100, capital = 0,     suffix = 'GbR',      register = 'HRA', desc = 'Zwei oder mehr Gesellschafter, kein Mindestkapital.' },
    { key = 'gmbh',     label = 'GmbH',                         kind = 'unternehmen', minFounders = 1, feeApply = 800, feeRegister = 2700, capital = 25000, suffix = 'GmbH',     register = 'HRB', desc = 'Haftungsbeschränkt. Das Stammkapital wird bis zur Eintragung treuhänderisch verwahrt.' },
    { key = 'ev',       label = 'Eingetragener Verein (e.V.)',  kind = 'fraktion',    minFounders = 3, feeApply = 300, feeRegister = 900,  capital = 0,     suffix = 'e.V.',     register = 'VR',  desc = 'Verein mit Satzung und Vorstand, mindestens 3 Gründungsmitglieder.' },
    { key = 'ig',       label = 'Interessengemeinschaft',       kind = 'fraktion',    minFounders = 3, feeApply = 200, feeRegister = 600,  capital = 0,     suffix = '',         register = 'IG',  desc = 'Loser Zusammenschluss ohne Vereinsregister. Für Clubs, Crews und Familien.' },
    { key = 'partei',   label = 'Partei / Wählergemeinschaft',  kind = 'fraktion',    minFounders = 5, feeApply = 500, feeRegister = 1500, capital = 0,     suffix = '',         register = 'VR',  desc = 'Politische Vereinigung, mindestens 5 Gründungsmitglieder.' },
    { key = 'verband',  label = 'Verband / Gewerkschaft',       kind = 'fraktion',    minFounders = 5, feeApply = 500, feeRegister = 1500, capital = 0,     suffix = '',         register = 'VR',  desc = 'Berufs- oder Interessenvertretung, mindestens 5 Gründungsmitglieder.' },
    { key = 'stiftung', label = 'Stiftung',                     kind = 'fraktion',    minFounders = 1, feeApply = 800, feeRegister = 2200, capital = 50000, suffix = 'Stiftung', register = 'VR',  desc = 'Zweckgebundenes Vermögen, $50.000 Stiftungskapital.' },
}

-- cap: Höchstzahl gleichzeitig aktiver Unternehmen. factor: Gebührenfaktor.
-- authority: Zulassung einer Fachbehörde (Punkt auf der Checkliste). staffGate: Schlussprüfung durch den Staff.
Config.Branches = {
    { key = 'gastro',     label = 'Gastronomie',             desc = 'Restaurant, Bar, Club, Café',             needsProperty = true,  authority = nil,              staffGate = false, cap = 12, factor = 1.0 },
    { key = 'handel',     label = 'Einzelhandel und Shops',  desc = 'Läden, Boutiquen, Kioske',                needsProperty = true,  authority = nil,              staffGate = false, cap = 10, factor = 1.0 },
    { key = 'kfz',        label = 'Fahrzeuge und Werkstatt', desc = 'Autohaus, Tuning, Abschleppdienst',       needsProperty = true,  authority = nil,              staffGate = false, cap = 6,  factor = 1.0 },
    { key = 'transport',  label = 'Transport und Logistik',  desc = 'Taxi, Kurier, Spedition',                 needsProperty = false, authority = nil,              staffGate = false, cap = 6,  factor = 1.0 },
    { key = 'handwerk',   label = 'Handwerk und Bau',        desc = 'Bau, Elektrik, Garten, Reinigung',        needsProperty = false, authority = nil,              staffGate = false, cap = 8,  factor = 1.0 },
    { key = 'medien',     label = 'Medien und Unterhaltung', desc = 'Zeitung, Radio, Events',                  needsProperty = true,  authority = nil,              staffGate = false, cap = 4,  factor = 1.0 },
    { key = 'sicherheit', label = 'Sicherheit und Detektei', desc = 'Wachdienst, Personenschutz, Ermittlung',  needsProperty = true,  authority = 'Polizei',        staffGate = true,  cap = 3,  factor = 1.5 },
    { key = 'gesundheit', label = 'Gesundheit und Wellness', desc = 'Praxis, Apotheke, Fitness',              needsProperty = true,  authority = 'Rettungsdienst', staffGate = false, cap = 4,  factor = 1.0 },
    { key = 'immobilien', label = 'Immobilien und Makler',   desc = 'Vermittlung und Verwaltung',              needsProperty = true,  authority = nil,              staffGate = false, cap = 3,  factor = 1.0 },
    { key = 'recht',      label = 'Recht und Beratung',      desc = 'Kanzlei, Steuerberatung',                 needsProperty = true,  authority = 'Justiz',         staffGate = false, cap = 3,  factor = 1.0 },
    { key = 'finanz',     label = 'Finanzdienstleistungen',  desc = 'Kredit, Treuhand, Vermögensverwaltung',   needsProperty = true,  authority = nil,              staffGate = true,  cap = 2,  factor = 2.0 },
    { key = 'sonstige',   label = 'Sonstiges',               desc = 'Alles, was nirgends passt',               needsProperty = false, authority = nil,              staffGate = true,  cap = 5,  factor = 1.0 },
}

-- Erste vergebene Registernummern: Die nächste Eintragung bekommt Start + 1 (HRA 1001, HRB 0301, VR 0201, IG 0001).
Config.RegisterStart = { HRA = 1000, HRB = 300, VR = 200, IG = 0 }

Config.OrgRoles = { 'vorsitz', 'stellv', 'kasse', 'mitglied' }
Config.CompanyRoles = { 'inhaber', 'geschaeftsfuehrer', 'gesellschafter' }

-- ---------------------------------------------------------------------------
-- Terminarten. needs: 'application' | 'entity' | nil. minRank: Mindestrang des Beamten.
-- ---------------------------------------------------------------------------
Config.AppointmentTypes = {
    { key = 'vorstellung_unternehmen', label = 'Vorstellungstermin Unternehmen',      minutes = 30, minRank = 'sachbearbeiter', needs = 'application', appKind = 'unternehmen', forStatus = { 'vorpruefung_ok' },
      desc = 'Sie stellen Ihr Unternehmen den Beamten persönlich vor. Pflichttermin nach bestandener Vorprüfung.' },
    { key = 'vorstellung_fraktion',    label = 'Vorstellungstermin Organisation',     minutes = 45, minRank = 'sachbearbeiter', needs = 'application', appKind = 'fraktion',    forStatus = { 'vorpruefung_ok' },
      desc = 'Vorstand und Gründungsmitglieder stellen Zweck und Satzung vor. Pflichttermin nach bestandener Vorprüfung.' },
    { key = 'aenderung',               label = 'Änderung (Name, Sitz, Gesellschafter)', minutes = 15, minRank = 'sachbearbeiter', needs = 'entity',
      desc = 'Änderungen an einem bestehenden Eintrag besprechen und beurkunden lassen.' },
    { key = 'nachkontrolle',           label = 'Nachkontrolle der Auflagen',          minutes = 20, minRank = 'sachbearbeiter', needs = 'entity', entityNeeds = 'conditions',
      desc = 'Erfüllte Auflagen nachweisen. Nur möglich, wenn Auflagen offen sind.' },
    { key = 'einspruch',               label = 'Einspruchsverhandlung',               minutes = 30, minRank = 'amtsleiter',     needs = 'application', forStatus = { 'einspruch' },
      desc = 'Ein Amtsleiter überprüft die Ablehnung. Nur nach eingelegtem Einspruch.' },
    { key = 'beratung',                label = 'Gründungsberatung',                   minutes = 15, minRank = 'anwaerter',
      desc = 'Unverbindliche Beratung vor dem Antrag. Kein Antrag nötig.' },
}

Config.Checklists = {
    vorstellung_unternehmen = {
        { key = 'id',        text = 'Identität aller anwesenden Gründer geprüft (Personalausweis)' },
        { key = 'present',   text = 'Alle Pflichtteilnehmer sind anwesend' },
        { key = 'idea',      text = 'Geschäftsidee ist verständlich und für das Rollenspiel tragfähig' },
        { key = 'name',      text = 'Name ist zulässig (keine Verwechslungsgefahr, keine Verstöße)' },
        { key = 'property',  text = 'Standort ist zulässig, Mietvertrag liegt vor', optional = true, note = 'Nur, wenn die Branche einen festen Standort verlangt.' },
        { key = 'shares',    text = 'Anteile und Rollen sind plausibel' },
        { key = 'authority', text = 'Zulassung der Fachbehörde liegt vor', optional = true, note = 'Nur, wenn die Branche eine Zulassung verlangt (Polizei, Rettungsdienst, Justiz).' },
        { key = 'fees',      text = 'Gebühren und Kapital sind bezahlt' },
        { key = 'briefing',  text = 'Gründer wurden über Pflichten belehrt (Auflagen, Probezeit, Steuern)' },
    },
    vorstellung_fraktion = {
        { key = 'id',      text = 'Identität aller Anwesenden geprüft' },
        { key = 'quorum',  text = 'Mindestzahl an Gründungsmitgliedern anwesend' },
        { key = 'statute', text = 'Zweck und Satzung vorgetragen und zulässig' },
        { key = 'board',   text = 'Vorstand benannt' },
        { key = 'seat',    text = 'Sitz oder Vereinsheim angegeben' },
        { key = 'name',    text = 'Name ist zulässig' },
        { key = 'fees',    text = 'Gebühren sind bezahlt' },
        { key = 'briefing', text = 'Belehrung über Pflichten erfolgt' },
    },
    aenderung     = { { key = 'id', text = 'Identität geprüft' }, { key = 'auth', text = 'Antragsteller ist vertretungsberechtigt' }, { key = 'valid', text = 'Änderung ist zulässig und plausibel' }, { key = 'fees', text = 'Gebühr bezahlt' } },
    nachkontrolle = { { key = 'id', text = 'Identität geprüft' }, { key = 'cond', text = 'Offene Auflagen einzeln geprüft' }, { key = 'proof', text = 'Nachweise liegen vor' } },
    einspruch     = { { key = 'id', text = 'Identität geprüft' }, { key = 'reason', text = 'Ablehnungsgrund erneut geprüft' }, { key = 'new', text = 'Neue Tatsachen oder Nachweise berücksichtigt' } },
    beratung      = { { key = 'id', text = 'Identität geprüft' }, { key = 'info', text = 'Verfahren, Gebühren und Voraussetzungen erklärt' } },
}

Config.ConditionPresets = {
    'Mietvertrag für den Standort innerhalb von 14 Tagen vorlegen',
    'Zulassung der Fachbehörde innerhalb von 14 Tagen nachreichen',
    'Gesellschaftsvertrag in unterzeichneter Fassung nachreichen',
    'Nachkontrolltermin nach 14 Tagen wahrnehmen',
    'Öffnungszeiten am Standort sichtbar aushängen',
}

Config.ReasonPresets = {
    abgelehnt = {
        'Der Name verstößt gegen die Namensregeln und konnte nicht geheilt werden.',
        'Die gemachten Angaben waren nachweislich unwahr.',
        'Pflichtteilnehmer sind trotz zweier Termine nicht erschienen.',
        'Der Zweck ist aus Sicht der Behörde unzulässig.',
    },
    vertagt = {
        'Es fehlen Unterlagen, die zum Termin hätten vorliegen müssen.',
        'Ein Pflichtteilnehmer war nicht anwesend.',
        'Das Konzept ist noch nicht ausreichend beschrieben.',
    },
}

-- Namenssperrliste (Startwerte, der Staff pflegt sie danach im Panel). {Begriff, Grund}
Config.Blacklist = {
    { 'polizei', 'Staatsfraktion' }, { 'lspd', 'Staatsfraktion' }, { 'rettungsdienst', 'Staatsfraktion' }, { 'feuerwehr', 'Staatsfraktion' },
    { 'regierung', 'Staatsfraktion' }, { 'justiz', 'Staatsfraktion' }, { 'staatsanwalt', 'Staatsfraktion' }, { 'stadtverwaltung', 'Staatsfraktion' },
    { 'admin', 'Staff-Begriff' }, { 'staff', 'Staff-Begriff' }, { 'support', 'Staff-Begriff' },
}

-- Gewerbeverzeichnis. Wer eine eigene Immobilien-Ressource nutzt, setzt Config.PropertyProvider (siehe unten).
-- status: 'frei' oder 'vermietet'. Die Ressource markiert Immobilien mit offenen Anträgen oder Eintragungen zusätzlich als belegt.
Config.Properties = {
    { id = 'P-01', label = 'Vespucci Boulevard 12', district = 'Vespucci',       size = 'S', rent = 900,  status = 'frei', note = 'Ladenlokal mit Lagerraum' },
    { id = 'P-02', label = 'Pier 9',                district = 'Del Perro',      size = 'M', rent = 1500, status = 'frei', note = 'Strandnah, Außenterrasse möglich' },
    { id = 'P-03', label = 'Mirror Park Drive 41',  district = 'Mirror Park',    size = 'M', rent = 1300, status = 'frei', note = 'Eckgebäude mit Schaufenster' },
    { id = 'P-04', label = 'Elgin Avenue 88',       district = 'Vinewood',       size = 'L', rent = 2400, status = 'frei', note = 'Zwei Etagen, Tiefgarage' },
    { id = 'P-05', label = 'Hauptstraße 5',         district = 'Sandy Shores',   size = 'S', rent = 600,  status = 'frei', note = 'Einfaches Ladenlokal' },
    { id = 'P-06', label = 'Industriepark 3',       district = 'Cypress Flats',  size = 'L', rent = 1800, status = 'frei', note = 'Halle mit Rolltor' },
}

-- Optional: eine Funktion, die die Liste aus eurer Immobilien-Ressource liefert (gleiche Felder wie oben).
Config.PropertyProvider = nil

-- ---------------------------------------------------------------------------
-- Hooks: Hier hängt ihr eure bestehende Job-, Gang-, Konto- und Lagerlogik an.
-- Alle Hooks laufen auf dem Server und dürfen fehlen.
-- ---------------------------------------------------------------------------
Config.Hooks = {
    -- Eine Organisation oder ein Unternehmen wurde eingetragen und ist aktiv.
    -- entity: Registereintrag. application: der Antrag. ooc ist nur gesetzt, wenn der Staff die Fraktionsart kennt.
    -- Beispiel: Job anlegen, Konto eröffnen, Lager erstellen, bei ooc.category == 'untergrund' die Gang-Mechaniken freischalten.
    onApproved = function(entity, application)
    end,
    -- Der Status eines Eintrags hat sich geändert (aktiv, probezeit, ruhend, gesperrt, aufgeloest).
    onStatusChanged = function(entity, oldStatus, newStatus)
    end,
    -- Ein Beamter hat eine Maßnahme verhängt. sanction: { level = 'verwarnung' | 'bussgeld' | 'auflage' | 'untersagung' | 'entzug', reason, amount, by, ts }
    -- Beispiel: bei 'bussgeld' den Betrag vom Firmenkonto abbuchen.
    onSanction = function(entity, sanction)
    end,
    -- Optional: Nachricht auf das Telefon eines Charakters. Ohne Hook kommt die Nachricht als Benachrichtigung.
    -- phoneMessage = function(charId, subject, text) end,
}
