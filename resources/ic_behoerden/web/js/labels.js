/* IC-Behördenportal · Beschriftungen und Statusmodelle (nur Anzeige, die Regeln liegen auf dem Server) */
(function () {
  'use strict';
  const IC = window.IC;

  /* Antragsstatus: label, chip-Art, aktuelle Phase (0..4), negativ = beendet ohne Eintragung */
  const APP = {
    entwurf:         { label: 'Entwurf',                      kind: '',     cur: 0 },
    eingereicht:     { label: 'Eingereicht',                  kind: 'info', cur: 1 },
    nachbesserung:   { label: 'Nachbesserung erforderlich',   kind: 'warn', cur: 1 },
    vorpruefung_ok:  { label: 'Vorprüfung bestanden',         kind: 'ok',   cur: 2 },
    termin_gebucht:  { label: 'Termin gebucht',               kind: 'info', cur: 2 },
    termin_laeuft:   { label: 'Vorstellung läuft',            kind: 'info', cur: 3 },
    staff_pruefung:  { label: 'Schlussprüfung',               kind: 'info', cur: 4 },
    genehmigt:       { label: 'Genehmigt und eingetragen',    kind: 'ok',   cur: 5 },
    abgelehnt:       { label: 'Abgelehnt',                    kind: 'bad',  cur: 3, neg: true },
    einspruch:       { label: 'Einspruch läuft',              kind: 'warn', cur: 3 },
    zurueckgezogen:  { label: 'Zurückgezogen',                kind: '',     cur: 1, neg: true },
    abgelaufen:      { label: 'Abgelaufen',                   kind: '',     cur: 1, neg: true },
  };
  const OPEN_APP = ['eingereicht', 'nachbesserung', 'vorpruefung_ok', 'termin_gebucht', 'termin_laeuft', 'staff_pruefung', 'einspruch'];
  const PHASES = ['Einreichung', 'Vorprüfung', 'Termin', 'Entscheidung', 'Eintragung'];

  const APPT = {
    gebucht:          { label: 'Gebucht',           kind: 'info' },
    eingecheckt:      { label: 'Im Wartebereich',   kind: 'ok' },
    aufgerufen:       { label: 'Aufgerufen',        kind: 'warn' },
    laeuft:           { label: 'Läuft',             kind: 'info' },
    abgeschlossen:    { label: 'Abgeschlossen',     kind: 'ok' },
    abgesagt:         { label: 'Abgesagt',          kind: '' },
    nicht_erschienen: { label: 'Nicht erschienen',  kind: 'bad' },
    beamter_ausfall:  { label: 'Beamten-Ausfall',   kind: 'warn' },
  };

  const ORG = {
    aktiv:     { label: 'Aktiv',       kind: 'ok' },
    probezeit: { label: 'Probezeit',   kind: 'info' },
    ruhend:    { label: 'Ruhend',      kind: 'warn' },
    gesperrt:  { label: 'Gesperrt',    kind: 'bad' },
    aufgeloest:{ label: 'Aufgelöst',   kind: '' },
  };

  const DECISION = {
    genehmigt: { label: 'Genehmigt',               kind: 'ok',   stamp: 'ok',   word: 'Genehmigt' },
    auflagen:  { label: 'Genehmigt mit Auflagen',  kind: 'warn', stamp: 'warn', word: 'Mit Auflagen' },
    vertagt:   { label: 'Vertagt (Nachbesserung)', kind: 'warn', stamp: 'blue', word: 'Vertagt' },
    abgelehnt: { label: 'Abgelehnt',               kind: 'bad',  stamp: 'bad',  word: 'Abgelehnt' },
  };

  const RANK = {
    anwaerter:      { label: 'Anwärter',        level: 0 },
    sachbearbeiter: { label: 'Sachbearbeiter',  level: 1 },
    amtsleiter:     { label: 'Amtsleiter',      level: 2 },
    leitung:        { label: 'Behördenleitung', level: 3 },
  };

  const MEMBER_ROLE = {
    inhaber: 'Inhaber', geschaeftsfuehrer: 'Geschäftsführer', gesellschafter: 'Gesellschafter',
    vorsitz: 'Vorsitz', stellv: 'Stellv. Vorsitz', kasse: 'Kassenführung', mitglied: 'Mitglied',
  };

  const SANCTION = {
    verwarnung: 'Verwarnung', bussgeld: 'Bußgeld', auflage: 'Neue Auflage', untersagung: 'Befristete Gewerbeuntersagung', entzug: 'Entzug der Eintragung',
  };

  IC.L = { APP, OPEN_APP, PHASES, APPT, ORG, DECISION, RANK, MEMBER_ROLE, SANCTION };
})();
