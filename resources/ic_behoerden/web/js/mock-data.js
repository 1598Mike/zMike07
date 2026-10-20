/* IC-Behördenportal · Demodaten für die Vorschau
   Die Konfiguration entspricht der Struktur, die der Server in `bootstrap` liefert. */
(function () {
  'use strict';
  const IC = window.IC;
  const MIN = IC.MIN, HOUR = IC.HOUR, DAY = IC.DAY;

  const config = {
    city: 'Los Santos',
    currency: '$',
    rules: {
      maxOpenApplications: 2, maxOpenAppointments: 2, nameReserveDays: 7, fixDays: 7, bookDays: 14, objectionHours: 48,
      cancelFreeMinutes: 15, checkinBefore: 10, checkinAfter: 10, liveHorizon: 60, slotStep: 15, leadMinutes: 10, bookAheadDays: 7,
      minAge: 18, minPlayHours: 10, maxCompanies: 2, maxOrgs: 1, strikeLimit: 3, strikeDays: 14, banDays: 3, escalateHours: 72,
      probationDays: 14, certDays: 90, feeChange: 200, feeDuplicate: 100, officialPay: 150,
    },
    legalForms: [
      { key: 'einzel',   label: 'Einzelunternehmen', kind: 'unternehmen', minFounders: 1, feeApply: 250, feeRegister: 750,  capital: 0,     suffix: '', register: 'HRA', desc: 'Ein Inhaber, volle Verantwortung. Schnell und günstig.' },
      { key: 'gbr',      label: 'GbR',               kind: 'unternehmen', minFounders: 2, feeApply: 400, feeRegister: 1100, capital: 0,     suffix: 'GbR', register: 'HRA', desc: 'Zwei oder mehr Gesellschafter, kein Mindestkapital.' },
      { key: 'gmbh',     label: 'GmbH',              kind: 'unternehmen', minFounders: 1, feeApply: 800, feeRegister: 2700, capital: 25000, suffix: 'GmbH', register: 'HRB', desc: 'Haftungsbeschränkt. Das Stammkapital wird bis zur Eintragung treuhänderisch verwahrt.' },
      { key: 'ev',       label: 'Eingetragener Verein (e.V.)', kind: 'fraktion', minFounders: 3, feeApply: 300, feeRegister: 900,  capital: 0,     suffix: 'e.V.', register: 'VR', desc: 'Verein mit Satzung und Vorstand, mindestens 3 Gründungsmitglieder.' },
      { key: 'ig',       label: 'Interessengemeinschaft', kind: 'fraktion', minFounders: 3, feeApply: 200, feeRegister: 600,  capital: 0,     suffix: '', register: 'IG', desc: 'Loser Zusammenschluss ohne Vereinsregister. Für Clubs, Crews und Familien.' },
      { key: 'partei',   label: 'Partei / Wählergemeinschaft', kind: 'fraktion', minFounders: 5, feeApply: 500, feeRegister: 1500, capital: 0,     suffix: '', register: 'VR', desc: 'Politische Vereinigung, mindestens 5 Gründungsmitglieder.' },
      { key: 'verband',  label: 'Verband / Gewerkschaft', kind: 'fraktion', minFounders: 5, feeApply: 500, feeRegister: 1500, capital: 0,     suffix: '', register: 'VR', desc: 'Berufs- oder Interessenvertretung, mindestens 5 Gründungsmitglieder.' },
      { key: 'stiftung', label: 'Stiftung',          kind: 'fraktion',    minFounders: 1, feeApply: 800, feeRegister: 2200, capital: 50000, suffix: 'Stiftung', register: 'VR', desc: 'Zweckgebundenes Vermögen, $50.000 Stiftungskapital.' },
    ],
    branches: [
      { key: 'gastro',     label: 'Gastronomie',            desc: 'Restaurant, Bar, Club, Café',           needsProperty: true,  authority: null,             staffGate: false, cap: 12, factor: 1 },
      { key: 'handel',     label: 'Einzelhandel und Shops', desc: 'Läden, Boutiquen, Kioske',              needsProperty: true,  authority: null,             staffGate: false, cap: 10, factor: 1 },
      { key: 'kfz',        label: 'Fahrzeuge und Werkstatt', desc: 'Autohaus, Tuning, Abschleppdienst',    needsProperty: true,  authority: null,             staffGate: false, cap: 6,  factor: 1 },
      { key: 'transport',  label: 'Transport und Logistik', desc: 'Taxi, Kurier, Spedition',               needsProperty: false, authority: null,             staffGate: false, cap: 6,  factor: 1 },
      { key: 'handwerk',   label: 'Handwerk und Bau',       desc: 'Bau, Elektrik, Garten, Reinigung',      needsProperty: false, authority: null,             staffGate: false, cap: 8,  factor: 1 },
      { key: 'medien',     label: 'Medien und Unterhaltung', desc: 'Zeitung, Radio, Events',               needsProperty: true,  authority: null,             staffGate: false, cap: 4,  factor: 1 },
      { key: 'sicherheit', label: 'Sicherheit und Detektei', desc: 'Wachdienst, Personenschutz, Ermittlung', needsProperty: true, authority: 'Polizei',         staffGate: true,  cap: 3,  factor: 1.5 },
      { key: 'gesundheit', label: 'Gesundheit und Wellness', desc: 'Praxis, Apotheke, Fitness',            needsProperty: true,  authority: 'Rettungsdienst', staffGate: false, cap: 4,  factor: 1 },
      { key: 'immobilien', label: 'Immobilien und Makler',  desc: 'Vermittlung und Verwaltung',            needsProperty: true,  authority: null,             staffGate: false, cap: 3,  factor: 1 },
      { key: 'recht',      label: 'Recht und Beratung',     desc: 'Kanzlei, Steuerberatung',               needsProperty: true,  authority: 'Justiz',         staffGate: false, cap: 3,  factor: 1 },
      { key: 'finanz',     label: 'Finanzdienstleistungen', desc: 'Kredit, Treuhand, Vermögensverwaltung', needsProperty: true,  authority: null,             staffGate: true,  cap: 2,  factor: 2 },
      { key: 'sonstige',   label: 'Sonstiges',              desc: 'Alles, was nirgends passt',             needsProperty: false, authority: null,             staffGate: true,  cap: 5,  factor: 1 },
    ],
    orgRoles: ['vorsitz', 'stellv', 'kasse', 'mitglied'],
    companyRoles: ['inhaber', 'geschaeftsfuehrer', 'gesellschafter'],
    appointmentTypes: [
      { key: 'vorstellung_unternehmen', label: 'Vorstellungstermin Unternehmen', minutes: 30, minRank: 'sachbearbeiter', needs: 'application', appKind: 'unternehmen', forStatus: ['vorpruefung_ok'],
        desc: 'Sie stellen Ihr Unternehmen den Beamten persönlich vor. Pflichttermin nach bestandener Vorprüfung.' },
      { key: 'vorstellung_fraktion',    label: 'Vorstellungstermin Organisation', minutes: 45, minRank: 'sachbearbeiter', needs: 'application', appKind: 'fraktion', forStatus: ['vorpruefung_ok'],
        desc: 'Vorstand und Gründungsmitglieder stellen Zweck und Satzung vor. Pflichttermin nach bestandener Vorprüfung.' },
      { key: 'aenderung',     label: 'Änderung (Name, Sitz, Gesellschafter)', minutes: 15, minRank: 'sachbearbeiter', needs: 'entity',
        desc: 'Änderungen an einem bestehenden Eintrag besprechen und beurkunden lassen.' },
      { key: 'nachkontrolle', label: 'Nachkontrolle der Auflagen',      minutes: 20, minRank: 'sachbearbeiter', needs: 'entity', entityNeeds: 'conditions',
        desc: 'Erfüllte Auflagen nachweisen. Nur möglich, wenn Auflagen offen sind.' },
      { key: 'einspruch',     label: 'Einspruchsverhandlung',           minutes: 30, minRank: 'amtsleiter',     needs: 'application', forStatus: ['einspruch'],
        desc: 'Ein Amtsleiter überprüft die Ablehnung. Nur nach eingelegtem Einspruch.' },
      { key: 'beratung',      label: 'Gründungsberatung',               minutes: 15, minRank: 'anwaerter',      needs: null,
        desc: 'Unverbindliche Beratung vor dem Antrag. Kein Antrag nötig.' },
    ],
    checklists: {
      vorstellung_unternehmen: [
        { key: 'id',        text: 'Identität aller anwesenden Gründer geprüft (Personalausweis)' },
        { key: 'present',   text: 'Alle Pflichtteilnehmer sind anwesend' },
        { key: 'idea',      text: 'Geschäftsidee ist verständlich und für das Rollenspiel tragfähig' },
        { key: 'name',      text: 'Name ist zulässig (keine Verwechslungsgefahr, keine Verstöße)' },
        { key: 'property',  text: 'Standort ist zulässig, Mietvertrag liegt vor', optional: true, note: 'Nur, wenn die Branche einen festen Standort verlangt.' },
        { key: 'shares',    text: 'Anteile und Rollen sind plausibel' },
        { key: 'authority', text: 'Zulassung der Fachbehörde liegt vor', optional: true, note: 'Nur, wenn die Branche eine Zulassung verlangt (Polizei, Rettungsdienst, Justiz).' },
        { key: 'fees',      text: 'Gebühren und Kapital sind bezahlt' },
        { key: 'briefing',  text: 'Gründer wurden über Pflichten belehrt (Auflagen, Probezeit, Steuern)' },
      ],
      vorstellung_fraktion: [
        { key: 'id',        text: 'Identität aller Anwesenden geprüft' },
        { key: 'quorum',    text: 'Mindestzahl an Gründungsmitgliedern anwesend' },
        { key: 'statute',   text: 'Zweck und Satzung vorgetragen und zulässig' },
        { key: 'board',     text: 'Vorstand benannt' },
        { key: 'seat',      text: 'Sitz oder Vereinsheim angegeben' },
        { key: 'name',      text: 'Name ist zulässig' },
        { key: 'fees',      text: 'Gebühren sind bezahlt' },
        { key: 'briefing',  text: 'Belehrung über Pflichten erfolgt' },
      ],
      aenderung:     [{ key: 'id', text: 'Identität geprüft' }, { key: 'auth', text: 'Antragsteller ist vertretungsberechtigt' }, { key: 'valid', text: 'Änderung ist zulässig und plausibel' }, { key: 'fees', text: 'Gebühr bezahlt' }],
      nachkontrolle: [{ key: 'id', text: 'Identität geprüft' }, { key: 'cond', text: 'Offene Auflagen einzeln geprüft' }, { key: 'proof', text: 'Nachweise liegen vor' }],
      einspruch:     [{ key: 'id', text: 'Identität geprüft' }, { key: 'reason', text: 'Ablehnungsgrund erneut geprüft' }, { key: 'new', text: 'Neue Tatsachen oder Nachweise berücksichtigt' }],
      beratung:      [{ key: 'id', text: 'Identität geprüft' }, { key: 'info', text: 'Verfahren, Gebühren und Voraussetzungen erklärt' }],
    },
    properties: [
      { id: 'P-01', label: 'Vespucci Boulevard 12',       district: 'Vespucci',       size: 'S', rent: 900,  status: 'frei',      note: 'Ladenlokal mit Lagerraum' },
      { id: 'P-02', label: 'Pier 9',                       district: 'Del Perro',      size: 'M', rent: 1500, status: 'frei',      note: 'Strandnah, Außenterrasse möglich' },
      { id: 'P-03', label: 'Mirror Park Drive 41',         district: 'Mirror Park',    size: 'M', rent: 1300, status: 'frei',      note: 'Eckgebäude mit Schaufenster' },
      { id: 'P-04', label: 'Elgin Avenue 88',              district: 'Vinewood',       size: 'L', rent: 2400, status: 'frei',      note: 'Zwei Etagen, Tiefgarage' },
      { id: 'P-05', label: 'Hauptstraße 5',                district: 'Sandy Shores',   size: 'S', rent: 600,  status: 'frei',      note: 'Einfaches Ladenlokal' },
      { id: 'P-06', label: 'Industriepark 3',              district: 'Cypress Flats',  size: 'L', rent: 1800, status: 'frei',      note: 'Halle mit Rolltor' },
      { id: 'P-07', label: 'Rockford Plaza 2',             district: 'Rockford Hills', size: 'M', rent: 2000, status: 'vermietet', note: '' },
      { id: 'P-08', label: 'Werkstattgasse 17',            district: 'La Mesa',        size: 'M', rent: 1100, status: 'vermietet', note: '' },
    ],
    officials: [
      { id: 'o_keller', name: 'Dr. Keller', rank: 'amtsleiter',     dienstnr: 'A-0101' },
      { id: 'o_yilmaz', name: 'Yilmaz',     rank: 'sachbearbeiter', dienstnr: 'S-0412' },
      { id: 'o_novak',  name: 'Novak',      rank: 'anwaerter',      dienstnr: 'W-0207' },
    ],
    conditionPresets: [
      'Mietvertrag für den Standort innerhalb von 14 Tagen vorlegen',
      'Zulassung der Fachbehörde innerhalb von 14 Tagen nachreichen',
      'Gesellschaftsvertrag in unterzeichneter Fassung nachreichen',
      'Nachkontrolltermin nach 14 Tagen wahrnehmen',
      'Öffnungszeiten am Standort sichtbar aushängen',
    ],
    reasonPresets: {
      abgelehnt: [
        'Der Name verstößt gegen die Namensregeln und konnte nicht geheilt werden.',
        'Die gemachten Angaben waren nachweislich unwahr.',
        'Pflichtteilnehmer sind trotz zweier Termine nicht erschienen.',
        'Der Zweck ist aus Sicht der Behörde unzulässig.',
      ],
      vertagt: [
        'Es fehlen Unterlagen, die zum Termin hätten vorliegen müssen.',
        'Ein Pflichtteilnehmer war nicht anwesend.',
        'Das Konzept ist noch nicht ausreichend beschrieben.',
      ],
    },
  };

  const BLACKLIST = [
    ['polizei', 'Staatsfraktion'], ['lspd', 'Staatsfraktion'], ['rettungsdienst', 'Staatsfraktion'], ['feuerwehr', 'Staatsfraktion'],
    ['regierung', 'Staatsfraktion'], ['justiz', 'Staatsfraktion'], ['staatsanwalt', 'Staatsfraktion'], ['stadtverwaltung', 'Staatsfraktion'],
    ['admin', 'Staff-Begriff'], ['staff', 'Staff-Begriff'], ['support', 'Staff-Begriff'], ['coca cola', 'Reale Marke'], ['mcdonalds', 'Reale Marke'],
  ];

  /* ---------- Ausgangszustand, relativ zu jetzt ---------- */
  function seed() {
    const now = Date.now();
    const t = (min) => now + min * MIN;
    const q15 = (ts) => Math.ceil(ts / (15 * MIN)) * 15 * MIN;

    const me = { charId: 'LS-48213', name: 'Lena Brandt', age: 29, bank: 184250, playHours: 63, hasId: true, strikes: [], notifyOnDuty: false };
    const P = (charId, name, age, playHours) => ({ charId, name, age, playHours, hasId: true });
    const people = {
      rossi: P('LS-51377', 'Marco Rossi', 34, 120),
      becker: P('LS-50291', 'Tom Becker', 31, 48),
      kowalski: P('LS-49902', 'Anna Kowalski', 27, 75),
      krueger: P('LS-52110', 'Jonas Krüger', 36, 210),
      marin: P('LS-53004', 'Sofia Marin', 25, 6),
      vogt: P('LS-52388', 'Dennis Vogt', 33, 90),
      petrov: P('LS-52041', 'Ivan Petrov', 38, 150),
      demir: P('LS-50877', 'Hakan Demir', 30, 64),
      schulz: P('LS-51120', 'Mia Schulz', 28, 55),
    };
    const nearby = [people.rossi, people.becker, people.kowalski, people.krueger, people.marin].map((p) => ({ ...p }));

    const ev = (ts, status, actor, actorKind, text, note) => ({ ts, status, actor, actorKind, text, note: note || null });
    const F = (p, role, share, consent) => ({ charId: p.charId, name: p.name, role, share: share == null ? null : share, consent: consent || 'ok' });
    const feesFor = (form, branch) => {
      const lf = config.legalForms.find((x) => x.key === form);
      const f = (branch && config.branches.find((b) => b.key === branch)) ? config.branches.find((b) => b.key === branch).factor : 1;
      return { apply: Math.round(lf.feeApply * f), register: Math.round(lf.feeRegister * f), capital: lf.capital, paid: true };
    };

    const applications = [
      {
        id: 'A-1', caseNo: 'GA-2026-0138', kind: 'unternehmen', legalForm: 'einzel', branch: 'gastro', name: 'Hafenbar Santa Maria',
        applicant: { charId: me.charId, name: me.name }, founders: [F(me, 'inhaber', 100)],
        property: { mode: 'immobilie', id: 'P-02', label: 'Pier 9, Del Perro' },
        concept: {
          idea: 'Eine Hafenbar am Pier mit regionalen Snacks, Cocktails und Live-Musik am Wochenende. Wir wollen einen Treffpunkt für Anwohner und Touristen schaffen.',
          audience: 'Anwohner, Touristen, Gruppen nach Feierabend', offer: 'Getränke, kleine Gerichte, Veranstaltungen', staff: '3 Mitarbeiter in der Anfangszeit', hours: 'Do bis So ab 18 Uhr',
        },
        ooc: null, status: 'termin_gebucht', fees: feesFor('einzel', 'gastro'), createdAt: t(-60 * 26), submittedAt: t(-60 * 25), reservedUntil: t(60 * 24 * 6),
        remark: null, decision: null, apptId: 'T-1',
        events: [
          ev(t(-60 * 25), 'eingereicht', me.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt'),
          ev(t(-60 * 20), 'vorpruefung_ok', 'Yilmaz', 'beamter', 'Vorprüfung bestanden', 'Unterlagen vollständig, Standort plausibel.'),
          ev(t(-60 * 2), 'termin_gebucht', me.name, 'bürger', 'Vorstellungstermin gebucht'),
        ],
      },
      {
        id: 'A-0', caseNo: 'GA-2026-0127', kind: 'unternehmen', legalForm: 'gbr', branch: 'kfz', name: 'Vinewood Autoteile GbR',
        applicant: { charId: me.charId, name: me.name }, founders: [F(me, 'geschaeftsfuehrer', 50), F(people.becker, 'gesellschafter', 50)],
        property: { mode: 'immobilie', id: 'P-04', label: 'Elgin Avenue 88, Vinewood' },
        concept: { idea: 'Handel mit Ersatzteilen und Zubehör für Fahrzeuge, Lieferung an Werkstätten.', audience: 'Werkstätten und Privatkunden', offer: 'Teile, Zubehör, Lieferservice', staff: '2 Mitarbeiter', hours: 'Mo bis Fr' },
        ooc: null, status: 'abgelehnt', fees: feesFor('gbr', 'kfz'), createdAt: t(-60 * 24 * 6), submittedAt: t(-60 * 24 * 6), reservedUntil: null,
        remark: null, objectionUntil: t(60 * 30),
        decision: { decision: 'abgelehnt', reason: 'Der angegebene Standort ist an Dritte vermietet. Ein Mietvertrag konnte auch beim zweiten Termin nicht vorgelegt werden.', by: 'Dr. Keller', at: t(-60 * 18), conditions: [] },
        events: [
          ev(t(-60 * 24 * 6), 'eingereicht', me.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt'),
          ev(t(-60 * 24 * 5), 'vorpruefung_ok', 'Yilmaz', 'beamter', 'Vorprüfung bestanden'),
          ev(t(-60 * 24 * 2), 'nachbesserung', 'Dr. Keller', 'beamter', 'Vertagt', 'Mietvertrag fehlt. Bitte zum Folgetermin vorlegen.'),
          ev(t(-60 * 18), 'abgelehnt', 'Dr. Keller', 'beamter', 'Antrag abgelehnt', 'Der angegebene Standort ist an Dritte vermietet. Ein Mietvertrag konnte auch beim zweiten Termin nicht vorgelegt werden.'),
        ],
      },
      {
        id: 'A-3', caseNo: 'GA-2026-0144', kind: 'fraktion', legalForm: 'ev', branch: null, name: 'Motorradfreunde Sandy Shores e.V.',
        applicant: { charId: people.rossi.charId, name: people.rossi.name }, founders: [F(people.rossi, 'vorsitz'), F(people.becker, 'stellv'), F(people.krueger, 'kasse')],
        property: { mode: 'immobilie', id: 'P-05', label: 'Hauptstraße 5, Sandy Shores' },
        statute: { purpose: 'Pflege der Motorradkultur, gemeinsame Ausfahrten und Treffen sowie Unterstützung von Mitgliedern bei Reparaturen.', goals: 'Wöchentlicher Stammtisch, jährliche Benefizfahrt, Jugendarbeit', admission: 'Aufnahme nach Probezeit und Beschluss des Vorstands' },
        ooc: { category: 'legal', note: 'Klassischer Motorradclub, keine Reviere geplant.', members: '12' },
        status: 'eingereicht', fees: feesFor('ev'), createdAt: t(-60 * 9), submittedAt: t(-60 * 8), reservedUntil: t(60 * 24 * 7), remark: null, decision: null,
        events: [ev(t(-60 * 8), 'eingereicht', people.rossi.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt')],
      },
      {
        id: 'A-4', caseNo: 'GA-2026-0145', kind: 'unternehmen', legalForm: 'gmbh', branch: 'transport', name: 'Becker Logistik GmbH',
        applicant: { charId: people.becker.charId, name: people.becker.name }, founders: [F(people.becker, 'geschaeftsfuehrer', 100)],
        property: { mode: 'mobil', id: null, label: 'Mobil, ohne festen Standort' },
        concept: { idea: 'Regionale Lieferungen für Gewerbekunden mit eigenen Transportern, Schwerpunkt Baustoffe und Gastronomiebedarf.', audience: 'Gewerbekunden', offer: 'Transport, Lagerung auf Zeit', staff: '4 Fahrer', hours: 'Mo bis Sa' },
        ooc: null, status: 'eingereicht', fees: feesFor('gmbh', 'transport'), createdAt: t(-60 * 5), submittedAt: t(-60 * 5), reservedUntil: t(60 * 24 * 7), remark: null, decision: null,
        events: [ev(t(-60 * 5), 'eingereicht', people.becker.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt')],
      },
      {
        id: 'A-5', caseNo: 'GA-2026-0140', kind: 'fraktion', legalForm: 'ev', branch: null, name: 'Schwarzer Anker MC e.V.',
        applicant: { charId: people.krueger.charId, name: people.krueger.name }, founders: [F(people.krueger, 'vorsitz'), F(people.vogt, 'stellv'), F(people.petrov, 'kasse')],
        property: { mode: 'immobilie', id: 'P-06', label: 'Industriepark 3, Cypress Flats' },
        statute: { purpose: 'Gemeinschaft von Motorradfahrern, Pflege von Brauchtum und Zusammenhalt, Betrieb eines Vereinsheims.', goals: 'Vereinsheim, Ausfahrten, Mitgliederversammlung', admission: 'Aufnahme nur auf Einladung des Vorstands' },
        ooc: { category: 'untergrund', note: 'Geplanter MC mit illegalen Aktivitäten (Waffen- und Drogenhandel), Ziel: Revier in Cypress Flats.', members: '10' },
        status: 'staff_pruefung', fees: feesFor('ev'), createdAt: t(-60 * 40), submittedAt: t(-60 * 39), reservedUntil: t(60 * 24 * 7), remark: null,
        decision: { decision: 'genehmigt', reason: 'Alle Pflichtpunkte erfüllt, Satzung zulässig.', by: 'Dr. Keller', at: t(-60 * 3), conditions: [] },
        events: [
          ev(t(-60 * 39), 'eingereicht', people.krueger.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt'),
          ev(t(-60 * 30), 'vorpruefung_ok', 'Yilmaz', 'beamter', 'Vorprüfung bestanden'),
          ev(t(-60 * 3), 'staff_pruefung', 'Dr. Keller', 'beamter', 'Genehmigt, Schlussprüfung der Registerführung folgt', 'Alle Pflichtpunkte erfüllt, Satzung zulässig.'),
        ],
      },
      {
        id: 'A-6', caseNo: 'GA-2026-0143', kind: 'unternehmen', legalForm: 'einzel', branch: 'gastro', name: 'Café Kowalski',
        applicant: { charId: people.kowalski.charId, name: people.kowalski.name }, founders: [F(people.kowalski, 'inhaber', 100)],
        property: { mode: 'immobilie', id: 'P-03', label: 'Mirror Park Drive 41, Mirror Park' },
        concept: { idea: 'Ein kleines Café mit Frühstück und Kuchen, Fokus auf gemütliche Atmosphäre und Stammgäste.', audience: 'Anwohner, Berufstätige', offer: 'Frühstück, Kaffee, Kuchen', staff: '2 Mitarbeiter', hours: 'täglich 8 bis 18 Uhr' },
        ooc: null, status: 'termin_gebucht', fees: feesFor('einzel', 'gastro'), createdAt: t(-60 * 30), submittedAt: t(-60 * 29), reservedUntil: t(60 * 24 * 6), remark: null, decision: null, apptId: 'T-2',
        events: [
          ev(t(-60 * 29), 'eingereicht', people.kowalski.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt'),
          ev(t(-60 * 22), 'vorpruefung_ok', 'Dr. Keller', 'beamter', 'Vorprüfung bestanden'),
          ev(t(-60 * 4), 'termin_gebucht', people.kowalski.name, 'bürger', 'Vorstellungstermin gebucht'),
        ],
      },
      {
        id: 'A-7', caseNo: 'GA-2026-0136', kind: 'unternehmen', legalForm: 'gbr', branch: 'transport', name: 'Delta Taxi GbR',
        applicant: { charId: people.demir.charId, name: people.demir.name }, founders: [F(people.demir, 'geschaeftsfuehrer', 50), F(people.schulz, 'gesellschafter', 50)],
        property: { mode: 'mobil', id: null, label: 'Mobil, ohne festen Standort' },
        concept: { idea: 'Taxiunternehmen mit zwei Fahrzeugen, Schwerpunkt Flughafentransfers und Nachtfahrten.', audience: 'Reisende, Nachtschwärmer', offer: 'Personenbeförderung', staff: '3 Fahrer', hours: 'rund um die Uhr' },
        ooc: null, status: 'vorpruefung_ok', fees: feesFor('gbr', 'transport'), createdAt: t(-60 * 90), submittedAt: t(-60 * 89), reservedUntil: t(60 * 24 * 5), remark: null, decision: null, vorpruefungAt: t(-60 * 80),
        events: [
          ev(t(-60 * 89), 'eingereicht', people.demir.name, 'bürger', 'Antrag eingereicht, Antragsgebühr bezahlt'),
          ev(t(-60 * 80), 'vorpruefung_ok', 'Yilmaz', 'beamter', 'Vorprüfung bestanden'),
        ],
      },
    ];

    const appointments = [
      { id: 'T-1', typeId: 'vorstellung_unternehmen', applicationId: 'A-1', entityId: null, start: q15(t(10)) > t(5) ? q15(t(10)) : q15(t(25)), minutes: 30, status: 'gebucht',
        booker: me.charId, bookerName: me.name, attendees: [{ charId: me.charId, name: me.name, checkedIn: false, mandatory: true }], official: null, note: 'Wir bringen den Mietvertrag mit.', source: 'live', createdAt: t(-60 * 2) },
      { id: 'T-2', typeId: 'vorstellung_unternehmen', applicationId: 'A-6', entityId: null, start: q15(t(45)), minutes: 30, status: 'eingecheckt',
        booker: people.kowalski.charId, bookerName: people.kowalski.name, attendees: [{ charId: people.kowalski.charId, name: people.kowalski.name, checkedIn: true, mandatory: true }], official: null, note: '', source: 'live', createdAt: t(-60 * 4) },
    ];

    const entities = [];
    const E = (id, kind, reg, name, form, branch, status, hq, owner, ageDays, extra) => {
      entities.push({
        id, kind, regNo: reg, name, legalForm: form, branch, status, hq, owner, founded: t(-ageDays * 24 * 60), validUntil: t((90 - ageDays % 60) * 24 * 60),
        members: [{ name: owner, role: kind === 'fraktion' ? 'vorsitz' : (form === 'einzel' ? 'inhaber' : 'geschaeftsfuehrer'), share: kind === 'fraktion' ? null : 100 }],
        conditions: [], legacy: false, signedBy: 'Dr. Keller', ...extra,
      });
    };
    E('E-1',  'unternehmen', 'HRA 1042', "Lena's Kiosk",                      'einzel', 'handel',     'aktiv',     'Vespucci Boulevard 12, Vespucci', me.name, 38, { memberCount: 2, myOwn: true, legacy: true, legacyConfirmed: false, legacyDue: t(60 * 24 * 20) });
    E('E-2',  'unternehmen', 'HRB 0317', 'Los Santos Taxi GmbH',              'gmbh',   'transport',  'aktiv',     'Mobil',                           'Jan Hoffmann', 52, { memberCount: 9 });
    E('E-3',  'unternehmen', 'HRA 1051', 'Blue Moon Bar & Grill GbR',         'gbr',    'gastro',     'aktiv',     'Del Perro Pier 3, Del Perro',     'Nadia Aziz', 31, { memberCount: 6 });
    E('E-4',  'unternehmen', 'HRB 0322', 'Rockford Autohaus GmbH',            'gmbh',   'kfz',        'aktiv',     'Rockford Plaza 2, Rockford Hills', 'Viktor Lang', 44, { memberCount: 8 });
    E('E-5',  'unternehmen', 'HRA 1066', 'Sunset Radio GbR',                  'gbr',    'medien',     'aktiv',     'Elgin Avenue 20, Vinewood',       'Carla Meier', 20, { memberCount: 4 });
    E('E-6',  'unternehmen', 'HRB 0330', 'Santos Sicherheitsdienst GmbH',     'gmbh',   'sicherheit', 'probezeit', 'Industriepark 1, Cypress Flats',  'Oskar Brandt', 9, { memberCount: 5, conditions: [{ id: 'C-1', text: 'Zulassung der Polizei nachreichen', due: t(60 * 24 * 5), done: false }] });
    E('E-7',  'unternehmen', 'HRB 0341', 'Nordwacht Security GmbH',           'gmbh',   'sicherheit', 'aktiv',     'Palomino Avenue 7, Pillbox Hill', 'Emil Roth', 27, { memberCount: 7 });
    E('E-8',  'unternehmen', 'HRA 1079', 'Pro Guard Detektei GbR',            'gbr',    'sicherheit', 'aktiv',     'Strawberry Avenue 33, Strawberry', 'Lea Fuchs', 15, { memberCount: 3 });
    E('E-9',  'unternehmen', 'HRB 0299', 'Pacific Standard Treuhand GmbH',    'gmbh',   'finanz',     'aktiv',     'Rockford Plaza 9, Rockford Hills', 'Dr. Paul Weiss', 61, { memberCount: 5 });
    E('E-10', 'unternehmen', 'HRB 0310', 'Vespucci Kreditkontor GmbH',       'gmbh',   'finanz',     'aktiv',     'Vespucci Canals 4, Vespucci',     'Ines Baumann', 48, { memberCount: 4 });
    E('E-11', 'unternehmen', 'HRA 1060', 'Kanzlei Weiß & Partner GbR',        'gbr',    'recht',      'aktiv',     'Rockford Plaza 5, Rockford Hills', 'Maren Weiß', 33, { memberCount: 3 });
    E('E-12', 'unternehmen', 'HRA 1055', 'Praxis Dr. Lindner',                'einzel', 'gesundheit', 'aktiv',     'Mount Zonah 2, Rockford Hills',   'Dr. Felix Lindner', 36, { memberCount: 3 });
    E('E-13', 'unternehmen', 'HRA 1038', 'Pier 18 Fischhandel',               'einzel', 'handel',     'ruhend',    'Del Perro Pier 18, Del Perro',    'Karl Brandl', 70, { memberCount: 1 });
    E('E-14', 'unternehmen', 'HRA 1071', 'Brenner Bau GbR',                   'gbr',    'handwerk',   'aktiv',     'Mobil',                           'Sven Brenner', 18, { memberCount: 5 });
    E('E-15', 'fraktion',    'VR 0208',  'Sportverein Mirror Park e.V.',       'ev',     null,         'aktiv',     'Mirror Park Drive 2, Mirror Park', 'Hanna Lorenz', 55, { memberCount: 21 });
    E('E-16', 'fraktion',    'VR 0211',  'Zukunft Los Santos',                'partei', null,         'aktiv',     'Rockford Plaza 12, Rockford Hills', 'Dr. Olaf Brandt', 49, { memberCount: 14 });
    E('E-17', 'fraktion',    'IG 0042',  'Grapeseed Farmers Interessengemeinschaft', 'ig', null,     'aktiv',     'Grapeseed Main Street 9, Grapeseed', 'Walter Hahn', 40, { memberCount: 8 });

    const officeHours = [
      { id: 'H-1', officialId: 'o_keller', start: q15(t(120)), end: q15(t(240)), types: null },
      { id: 'H-2', officialId: 'o_yilmaz', start: q15(IC.startOfDay(now) + DAY + 18 * HOUR), end: q15(IC.startOfDay(now) + DAY + 21 * HOUR), types: null },
      { id: 'H-3', officialId: 'o_keller', start: q15(IC.startOfDay(now) + DAY + 19 * HOUR), end: q15(IC.startOfDay(now) + DAY + 22 * HOUR), types: null },
      { id: 'H-4', officialId: 'o_yilmaz', start: q15(IC.startOfDay(now) + 2 * DAY + 17 * HOUR), end: q15(IC.startOfDay(now) + 2 * DAY + 20 * HOUR), types: null },
      { id: 'H-5', officialId: 'o_keller', start: q15(IC.startOfDay(now) + 3 * DAY + 20 * HOUR), end: q15(IC.startOfDay(now) + 3 * DAY + 23 * HOUR), types: null },
    ];

    const audit = [
      { ts: t(-60 * 3), actor: 'Dr. Keller', kind: 'beamter', action: 'Entscheidung', target: 'GA-2026-0140', detail: 'Genehmigt, weiter an Schlussprüfung' },
      { ts: t(-60 * 5), actor: 'Tom Becker', kind: 'bürger', action: 'Antrag eingereicht', target: 'GA-2026-0145', detail: 'Becker Logistik GmbH' },
      { ts: t(-60 * 8), actor: 'Marco Rossi', kind: 'bürger', action: 'Antrag eingereicht', target: 'GA-2026-0144', detail: 'Motorradfreunde Sandy Shores e.V.' },
      { ts: t(-60 * 18), actor: 'Dr. Keller', kind: 'beamter', action: 'Entscheidung', target: 'GA-2026-0127', detail: 'Abgelehnt, Standort nicht nachgewiesen' },
      { ts: t(-60 * 20), actor: 'Yilmaz', kind: 'beamter', action: 'Vorprüfung', target: 'GA-2026-0138', detail: 'Bestanden' },
      { ts: t(-60 * 24), actor: 'System', kind: 'system', action: 'Eintragung', target: 'HRB 0341', detail: 'Nordwacht Security GmbH eingetragen' },
    ];

    return {
      now,
      officialsOthers: 1,
      me, nearby, people,
      meOfficial: { id: 'o_me', name: 'Sommer', rank: 'sachbearbeiter', dienstnr: 'S-0455', state: 'off', desk: 2 },
      applications, appointments, entities, officeHours,
      queue: [
        { no: 'A-012', who: 'Tom Becker', typeId: 'beratung', at: t(-6) },
        { no: 'A-013', who: 'Mia Schulz', typeId: 'beratung', at: t(-3) },
      ],
      calling: { no: 'A-011', desk: 2, at: t(-1) },
      queueSeq: 13,
      myTicket: null,
      staff: {
        blacklist: BLACKLIST.map((b, i) => ({ id: 'B-' + (i + 1), term: b[0], reason: b[1] })),
        capOverrides: {},
        undergroundCap: { used: 3, max: 8 },
        settings: { requireOfficials: true, writtenProcedure: true, undergroundViaPortal: true, fourEyes: false },
      },
      audit,
      notices: [], noticeSeq: 0, treasury: 48250,
      seq: { caseNo: 146, app: 8, appt: 3, entity: 18, hours: 6, reg: { HRA: 1080, HRB: 342, VR: 212, IG: 43 }, black: BLACKLIST.length + 1, cond: 2 },
    };
  }

  IC.mockConfig = config;
  IC.mockSeed = seed;
})();
