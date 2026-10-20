const { chromium } = require('playwright');
/* Vorschau-Test (Mock-Backend, ohne Server). Aufruf aus resources/ic_behoerden:  node tests/ui/preview/ablauf.js
   Bildschirmfotos optional: SHOTS=/pfad/zum/ordner node … */
const path = require('path');
const WEB = 'file://' + path.resolve(__dirname, '..', '..', '..', 'web', 'index.html');
const SHOTS = process.env.SHOTS || '';
const shotPath = (n) => path.join(SHOTS, n);

const assert = require('assert');
const URL = WEB;
let step = 0;
const log = (m) => console.log(String(++step).padStart(2,'0') + ' ' + m);

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on('console', m => { if (['error','warning'].includes(m.type())) errors.push(m.type()+': '+m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  await page.goto(URL + '#gewerbeamt');
  await page.waitForSelector('.win-body');
  const shot = (n) => (SHOTS ? page.screenshot({ path: shotPath(`e2e-${n}.png`), fullPage: true }) : null);
  const settle = () => page.waitForTimeout(450);

  /* --- Wizard --- */
  await page.click('.tile >> text=Unternehmen gründen');
  await page.waitForSelector('.stepper');
  log('Wizard geöffnet');
  await page.click('[data-act="wiz-branch"][data-key="handwerk"]');
  await page.click('[data-act="wiz-next"]');
  await page.click('[data-act="wiz-form"][data-key="einzel"]');
  await page.fill('#wiz-name', 'Polizei Pizza');
  await page.waitForSelector('[data-partial="wiz-name"] .err');
  const err1 = await page.locator('[data-partial="wiz-name"] .err').first().innerText();
  assert(/gesperrt/.test(err1), 'Sperrliste greift: ' + err1);
  assert(await page.locator('[data-act="wiz-next"]').isDisabled(), 'Weiter bei gesperrtem Namen deaktiviert');
  log('Gesperrter Name wird abgelehnt: ' + err1);
  await page.fill('#wiz-name', 'Lena\'s Kiosk');
  await page.waitForSelector('[data-partial="wiz-name"] .err');
  log('Name "Lena\'s Kiosk" (vergeben): ' + (await page.locator('[data-partial="wiz-name"] .err').first().innerText()));
  await page.fill('#wiz-name', 'Mustermann Bau');
  await page.waitForSelector('[data-partial="wiz-name"] .okmsg');
  log('Name frei: ' + (await page.locator('[data-partial="wiz-name"] .okmsg').first().innerText()));
  await page.click('[data-act="wiz-next"]');                       // -> Gründer
  await page.click('[data-act="wiz-next"]');                       // -> Standort
  await page.click('[data-act="wiz-site-mode"][data-mode="mobil"]');
  await page.click('[data-act="wiz-next"]');                       // -> Konzept
  await page.fill('#wiz-idea', 'Wir übernehmen kleine Bau- und Renovierungsarbeiten für Privatkunden und Gewerbe in Los Santos. Schwerpunkt sind Trockenbau, Malerarbeiten und Bodenbeläge.');
  await page.click('[data-act="wiz-next"]');                       // -> Prüfen
  await page.check('#wiz-confirm');
  await shot('01-review');
  await page.click('[data-act="wiz-submit"]');
  await page.click('[data-act="modal-yes"]');
  await page.waitForSelector('.stamp');
  const h2 = await page.locator('h2').first().innerText();
  const caseNo = (h2.match(/GA-\d{4}-\d{4}/) || [])[0];
  assert(caseNo, 'Aktenzeichen vergeben: ' + h2);
  log('Antrag eingereicht: ' + caseNo);
  const bank = await page.evaluate(() => IC.S.d.me.bank);
  assert.strictEqual(bank, 184250 - 250 - 750, 'Konto belastet um 1.000');
  log('Kontostand nach Zahlung: ' + bank);

  /* --- Beamter: Dienst und Vorprüfung --- */
  await page.evaluate(() => IC.go('beamte', 'reviews')); await settle();
  await page.click('.seg [data-act="duty-set"][data-state="on"]'); await settle();
  await page.locator('tr', { hasText: 'Mustermann Bau' }).locator('[data-act="rev-open"]').click();
  await page.waitForSelector('.modal');
  await page.click('[data-act="rev-do"][data-result="ok"]'); await settle();
  const st1 = await page.evaluate(() => IC.S.d.officialApps.find(a => a.name === 'Mustermann Bau').status);
  assert.strictEqual(st1, 'vorpruefung_ok');
  log('Vorprüfung bestanden: Status ' + st1);

  /* --- Bürgeramt: Termin buchen (Beamte im Dienst) --- */
  await page.evaluate(() => IC.go('buergeramt', 'book')); await settle();
  await page.click('[data-act="book-type"][data-key="vorstellung_unternehmen"]');
  await page.waitForSelector('.slot:not([disabled])');
  await shot('02-slots');
  const nSlots = await page.locator('.slot:not([disabled])').count();
  log('Live-Slots verfügbar: ' + nSlots);
  await page.locator('.slot:not([disabled])').first().click();
  await page.click('[data-act="book-submit"]');
  await page.waitForSelector('.ticket');
  const apptId = (await page.locator('.ticket .tn').innerText()).trim();
  log('Termin gebucht: ' + apptId);

  /* --- Uhr vorstellen, einchecken --- */
  const start = await page.evaluate((id) => IC.S.d.myAppointments.find(a => a.id === id).start, apptId);
  const mins = Math.max(0, Math.ceil((start - await page.evaluate(() => IC.now()) - 2 * 60000) / 60000));
  await page.evaluate(async (m) => { await IC.api('pvAdvance', { minutes: m }); await IC.reload(); }, mins);
  await page.evaluate(() => IC.go('buergeramt', 'appts')); await settle();
  await page.click(`[data-act="appt-checkin"][data-id="${apptId}"]`); await settle();
  const checked = await page.evaluate((id) => IC.S.d.myAppointments.find(a => a.id === id).status, apptId);
  assert.strictEqual(checked, 'eingecheckt');
  log('Eingecheckt (Uhr +' + mins + ' Min)');
  await shot('03-appts');

  /* --- Beamter: aufrufen, starten, entscheiden --- */
  await page.evaluate(() => IC.go('beamte', 'today')); await settle();
  const card = page.locator('article', { hasText: 'Mustermann Bau' });
  await card.locator('[data-act="appt-call"]').click(); await settle();
  await card.locator('[data-act="appt-start"]').click(); await settle();
  await page.waitForSelector('[data-act="chk-toggle"]');
  for (const cb of await page.locator('[data-act="chk-toggle"]').all()) await cb.check();
  await shot('04-termin');
  await page.click('[data-act="dec-open"][data-dec="genehmigt"]');
  await page.click('[data-act="dec-confirm"]'); await settle();
  await page.waitForSelector('.stamp');
  const resTxt = await page.locator('.main').innerText();
  assert(/HRA 10\d\d/.test(resTxt), 'Registernummer im Bescheid: ' + resTxt.slice(0, 200));
  log('Entscheidung: ' + (resTxt.match(/HRA \d+/) || [])[0]);
  await shot('05-bescheid');

  /* --- Bürger: Eintragung --- */
  await page.evaluate(() => IC.go('gewerbeamt', 'entities')); await settle();
  const ent = await page.locator('article', { hasText: 'Mustermann Bau' }).innerText();
  assert(/HRA/.test(ent), 'Eintragung sichtbar');
  log('Eintragung sichtbar: ' + ent.split('\n').slice(0, 3).join(' | '));
  await page.locator('article', { hasText: 'Mustermann Bau' }).locator('[data-act="ent-cert"]').click();
  await page.waitForSelector('.cert');
  await shot('06-cert');
  await page.click('[data-act="modal-close"]');

  /* --- Gating: keine Beamten --- */
  await page.evaluate(async () => { await IC.api('dutySet', { state: 'off' }); await IC.api('pvSetOfficials', { n: 0 }); });
  await page.evaluate(() => IC.go('buergeramt', 'book')); await settle();
  await page.click('[data-act="book-type"][data-key="beratung"]');
  await page.waitForSelector('.duty.off');
  const banner = await page.locator('.duty.off').first().innerText();
  assert(/kein Beamter im Dienst/.test(banner), 'Banner: ' + banner);
  log('Ohne Beamte: "' + banner.replace(/\s+/g, ' ').slice(0, 90) + '"');
  await shot('07-no-officials');
  await page.evaluate(() => IC.go('buergeramt', 'queue')); await settle();
  assert(await page.locator('[data-act="queue-take"]').isDisabled(), 'Wartenummer ohne Beamte gesperrt');
  log('Wartenummer ohne Beamte gesperrt');

  /* --- Wartenummer mit Beamten --- */
  await page.evaluate(async () => { await IC.api('pvSetOfficials', { n: 2 }); await IC.reload(); }); await settle();
  await page.click('[data-act="queue-take"]'); await settle();
  assert(await page.locator('.ticket .tn').count() === 1, 'Ticket angezeigt');
  log('Wartenummer gezogen: ' + (await page.locator('.ticket .tn').innerText()).trim());

  console.log('\nKONSOLENFEHLER:', JSON.stringify(errors, null, 1));
  await browser.close();
  console.log('E2E OK');
})().catch(e => { console.error('E2E FEHLER:', e.message); process.exit(1); });
