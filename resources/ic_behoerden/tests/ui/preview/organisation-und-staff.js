const { chromium } = require('playwright');
/* Vorschau-Test (Mock-Backend, ohne Server). Aufruf aus resources/ic_behoerden:  node tests/ui/preview/organisation-und-staff.js
   Bildschirmfotos optional: SHOTS=/pfad/zum/ordner node … */
const path = require('path');
const WEB = 'file://' + path.resolve(__dirname, '..', '..', '..', 'web', 'index.html');
const SHOTS = process.env.SHOTS || '';
const shotPath = (n) => path.join(SHOTS, n);

const assert = require('assert');
const URL = WEB;
let step = 0; const log = (m) => console.log(String(++step).padStart(2,'0') + ' ' + m);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on('console', m => { if (['error','warning'].includes(m.type())) errors.push(m.type()+': '+m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  await page.goto(URL + '#gewerbeamt');
  await page.waitForSelector('.win-body');
  const settle = (ms) => page.waitForTimeout(ms || 450);
  const go = async (a, v) => { await page.evaluate(([a, v]) => IC.go(a, v), [a, v]); await settle(); };
  const shot = (n) => (SHOTS ? page.screenshot({ path: shotPath(`e2e2-${n}.png`), fullPage: true }) : null);
  const S = (fn, arg) => page.evaluate(fn, arg);

  /* ===== Flow B: Organisation mit Untergrund-Kennzeichen und Staff-Gate ===== */
  await page.click('.tile >> text=Fraktion oder Organisation gründen');
  await page.click('[data-act="wiz-form"][data-key="ev"]');
  await page.click('[data-act="wiz-next"]');
  await page.fill('#wiz-name', 'Skater Club Mirror Park');
  await page.waitForSelector('[data-partial="wiz-name"] .okmsg');
  assert(/e\.V\./.test(await page.locator('[data-partial="wiz-name"] .okmsg').innerText()), 'Zusatz e.V.');
  await page.click('[data-act="wiz-next"]');
  assert(await page.locator('[data-act="wiz-next"]').isDisabled(), 'Weiter gesperrt: zu wenig Mitglieder');
  log('Verein: mind. 3 Mitglieder erzwungen');
  await page.click('[data-act="wiz-add-founder"][data-id="LS-51377"]');
  await page.click('[data-act="wiz-add-founder"][data-id="LS-50291"]');
  assert(await page.locator('[data-act="wiz-add-founder"][data-id="LS-53004"]').isDisabled(), 'Sofia Marin (zu wenig Spielzeit) nicht einladbar');
  await page.waitForFunction(() => IC.S.ui.wiz.founders.every(f => f.consent !== 'pending'), null, { timeout: 5000 });
  log('Mitgründer haben zugestimmt, Spielzeit-Prüfung greift');
  await page.click('[data-act="wiz-next"]');
  await page.click('[data-act="wiz-site-mode"][data-mode="mobil"]');
  await page.click('[data-act="wiz-next"]');
  await page.fill('#wiz-purpose', 'Wir bringen Skater aus Mirror Park zusammen, organisieren Treffen, kleine Wettbewerbe und kümmern uns um einen sicheren Skatepark im Viertel.');
  await page.click('[data-act="wiz-next"]');
  await page.selectOption('#wiz-oocc', 'untergrund');
  await page.fill('#wiz-oocn', 'Soll als Tarnung für eine Gang dienen.');
  await page.check('#wiz-confirm');
  await shot('01-fraktion-review');
  await page.click('[data-act="wiz-submit"]'); await page.click('[data-act="modal-yes"]');
  await page.waitForSelector('.stamp');
  log('Organisation eingereicht: ' + (await page.locator('h2').first().innerText()));

  await go('beamte', 'reviews');
  await page.click('.seg [data-act="duty-set"][data-state="on"]'); await settle();
  const rev = await S(() => JSON.stringify(IC.S.d.officialApps.find(a => a.name === 'Skater Club Mirror Park e.V.')));
  assert(!/untergrund|ooc/i.test(rev), 'OOC-Daten sind in Beamten-Sicht nicht enthalten');
  log('Beamte sehen keine OOC-Angaben');
  await page.locator('tr', { hasText: 'Skater Club' }).locator('[data-act="rev-open"]').click();
  await page.click('[data-act="rev-do"][data-result="ok"]'); await settle();

  await go('buergeramt', 'book');
  await page.click('[data-act="book-type"][data-key="vorstellung_fraktion"]');
  await page.waitForSelector('.slot:not([disabled])');
  await page.locator('.slot:not([disabled])').first().click();
  const must = await page.locator('[data-act="book-attendee"][disabled]').count();
  assert.strictEqual(must, 3, 'Alle 3 Gründungsmitglieder sind Pflichtteilnehmer');
  await page.click('[data-act="book-submit"]');
  await page.waitForSelector('.ticket');
  const apptId = (await page.locator('.ticket .tn').innerText()).trim();
  const start = await S((id) => IC.S.d.myAppointments.find(a => a.id === id).start, apptId);
  const mins = Math.max(0, Math.ceil((start - await S(() => IC.now()) - 2 * 60000) / 60000));
  await S(async (m) => { await IC.api('pvAdvance', { minutes: m }); await IC.reload(); }, mins);
  await go('buergeramt', 'appts');
  await page.click(`[data-act="appt-checkin"][data-id="${apptId}"]`); await settle();
  assert.strictEqual(await S((id) => IC.S.d.myAppointments.find(a => a.id === id).status, apptId), 'eingecheckt');
  log('Vorstellungstermin Organisation gebucht und eingecheckt (' + apptId + ')');

  await go('beamte', 'today');
  const card = page.locator('article', { hasText: 'Skater Club' });
  await card.locator('[data-act="appt-start"]').click(); await settle();
  for (const cb of await page.locator('[data-act="chk-toggle"]').all()) await cb.check();
  await page.click('[data-act="dec-open"][data-dec="genehmigt"]'); await page.click('[data-act="dec-confirm"]'); await settle();
  const res = await page.locator('.main').innerText();
  assert(/Schlussprüfung/.test(res), 'Staff-Gate greift: ' + res.slice(0, 160).replace(/\n/g, ' '));
  log('Genehmigt, weiter zur Schlussprüfung (Staff-Gate)');
  await page.click('[data-act="term-close"]');

  await go('staff', 'gate');
  const gateTxt = await page.locator('.main').innerText();
  assert(/Skater Club/.test(gateTxt) && /Untergrund/.test(gateTxt), 'Staff sieht OOC-Angaben');
  const used0 = await S(() => IC.S.d.staff.undergroundCap.used);
  await page.locator('article', { hasText: 'Skater Club' }).locator('[data-act="gate-ok"]').click();
  await page.click('[data-act="modal-yes"]'); await settle();
  const used1 = await S(() => IC.S.d.staff.undergroundCap.used);
  assert.strictEqual(used1, used0 + 1, 'Untergrund-Slot verbraucht');
  log('Staff gibt frei, Untergrund-Plätze ' + used0 + ' -> ' + used1);
  await go('gewerbeamt', 'entities');
  assert(/VR 02\d\d/.test(await page.locator('article', { hasText: 'Skater Club' }).innerText()), 'Organisation eingetragen');
  log('Organisation im Register');

  /* ===== Flow C: Nachbesserung und Ablehnung durch Beamte ===== */
  await go('beamte', 'reviews');
  await page.locator('tr', { hasText: 'Becker Logistik' }).locator('[data-act="rev-open"]').click();
  await page.fill('#rev-msg', 'kurz');
  await page.click('[data-act="rev-do"][data-result="nachbesserung"]'); await settle(200);
  assert(await page.locator('.toast.bad').count() >= 1, 'Zu kurze Begründung wird abgelehnt');
  await page.fill('#rev-msg', 'Bitte den Gesellschaftsvertrag nachreichen und Fahrzeuge angeben.');
  await page.click('[data-act="rev-do"][data-result="nachbesserung"]'); await settle();
  assert.strictEqual(await S(() => IC.S.d.officialApps.find(a => a.name.startsWith('Becker Logistik')).status), 'nachbesserung');
  log('Nachbesserung verlangt (Begründung Pflicht)');
  await page.locator('tr', { hasText: 'Motorradfreunde' }).locator('[data-act="rev-open"]').click();
  await page.fill('#rev-msg', 'Der Zweck ist aus Sicht der Behörde unzulässig.');
  await page.click('[data-act="rev-do"][data-result="abgelehnt"]'); await settle();
  assert.strictEqual(await S(() => IC.S.d.officialApps.find(a => a.name.startsWith('Motorradfreunde')).status), 'abgelehnt');
  log('Antrag abgelehnt');

  /* ===== Einspruch gegen eigene Ablehnung ===== */
  await go('gewerbeamt', 'apps');
  await page.click('[data-act="app-open"]:has-text("Vinewood Autoteile")'); await settle();
  await page.click('[data-act="app-objection-open"]');
  await page.fill('#obj-text', 'Der Mietvertrag liegt inzwischen vor und wird mitgebracht.');
  await page.click('[data-act="app-objection-send"]'); await settle();
  assert.strictEqual(await S(() => IC.S.d.myApplications.find(a => a.name.startsWith('Vinewood')).status), 'einspruch');
  log('Einspruch eingelegt');

  /* ===== Notfallregel (Eskalation, schriftliches Verfahren) ===== */
  await go('staff', 'esc');
  const esc = await page.locator('.main').innerText();
  assert(/Delta Taxi/.test(esc) && /Eskalation/.test(esc), 'Eskalation sichtbar');
  await page.click('[data-act="esc-open"]');
  await page.fill('#ew-reason', 'Nach Aktenlage unbedenklich, alle Unterlagen vollständig.');
  await page.click('[data-act="esc-send"]'); await settle();
  assert.strictEqual(await S(() => IC.S.d.staff.applicationsAll.find(a => a.name.startsWith('Delta Taxi')).status), 'genehmigt');
  log('Eskalation: Entscheidung nach Aktenlage, Delta Taxi eingetragen');

  /* ===== Sanktion (nur Amtsleiter) ===== */
  await go('beamte', 'breg');
  await S(async () => { await IC.api('pvSetRank', { rank: 'sachbearbeiter' }); await IC.reload(); }); await settle();
  assert(await page.locator('[data-act="sanction-open"]').first().isDisabled(), 'Sachbearbeiter darf nicht sanktionieren');
  await S(async () => { await IC.api('pvSetRank', { rank: 'amtsleiter' }); await IC.reload(); }); await settle();
  await page.locator('tr', { hasText: 'Blue Moon' }).locator('[data-act="sanction-open"]').click();
  await page.fill('#sc-reason', 'Wiederholte Lärmbeschwerden der Anwohner.');
  await page.click('[data-act="sanction-send"]'); await settle();
  log('Sanktion nur mit Rang Amtsleiter und Begründung');

  /* ===== Rang Anwärter darf nicht entscheiden ===== */
  await S(async () => { await IC.api('pvSetRank', { rank: 'anwaerter' }); await IC.reload(); }); await settle();
  await go('beamte', 'today');
  const dis = await page.locator('[data-act="appt-start"]').first().isDisabled();
  assert(dis, 'Anwärter kann Vorstellungstermin nicht starten');
  log('Anwärter kann keinen Vorstellungstermin führen');

  /* ===== Audit enthält die Ereignisse ===== */
  await go('staff', 'audit');
  const au = await page.locator('.main').innerText();
  assert(/Eintragung/.test(au) && /Freigabe/.test(au) && /Sanktion/.test(au), 'Audit vollständig');
  log('Audit-Log enthält Eintragung, Freigabe, Sanktion');

  console.log('\nKONSOLENFEHLER:', JSON.stringify(errors, null, 1));
  await browser.close();
  console.log('E2E2 OK');
})().catch(e => { console.error('E2E2 FEHLER:', e.message); process.exit(1); });
