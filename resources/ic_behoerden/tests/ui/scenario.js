/*
  Ablauf einer Gründung durch mehrere Spieler gegen die echte Serverlogik:
  Lena (Gründerin), Tom und Marco (Mitgründer), Dr. Keller (Amtsleiter), Admin (Staff).
*/
module.exports = async ({ lua, actor, openApp, log, assert }) => {
  await lua.call('reset');
  const lena = await actor(1, 'lena');
  const keller = await actor(10, 'keller');
  const admin = await actor(99, 'admin');
  const S = (page, fn, arg) => page.evaluate(fn, arg);
  const go = async (page, a, v) => { await page.evaluate(([x, y]) => IC.go(x, y), [a, v]); await page.settle(); };

  /* ===== A: Einzelunternehmen gründen ===== */
  await openApp(lena, lua, 'gewerbeamt');
  log('Start: ' + (await lena.locator('h1, h2').first().innerText()));
  const faces = await S(lena, () => document.fonts.ready.then(() => [...document.fonts].filter((f) => f.status === 'loaded').map((f) => f.family.replace(/"/g, ''))));
  assert(faces.includes('Barlow'), 'Schriften kommen aus dem Ressourcen-Ordner: ' + JSON.stringify(faces));
  log('Lokale Schriften geladen: ' + [...new Set(faces)].join(', '));
  await lena.click('.tile >> text=Unternehmen gründen');
  await lena.waitForSelector('.stepper');
  await lena.click('[data-act="wiz-branch"][data-key="handwerk"]');
  await lena.click('[data-act="wiz-next"]');
  await lena.click('[data-act="wiz-form"][data-key="einzel"]');
  await lena.fill('#wiz-name', 'Polizei Pizza');
  await lena.waitForSelector('[data-partial="wiz-name"] .err');
  const err1 = await lena.locator('[data-partial="wiz-name"] .err').first().innerText();
  assert(/gesperrt/.test(err1), 'Sperrliste greift: ' + err1);
  assert(await lena.locator('[data-act="wiz-next"]').isDisabled(), 'Weiter bei gesperrtem Namen deaktiviert');
  log('Gesperrter Name wird vom Server abgelehnt: ' + err1);

  const imp = await lua.call('import', { list: [{ ref: 'x1', name: "Lena's Kiosk", kind: 'unternehmen', legalForm: 'einzel', branch: 'handel', members: [{ charId: 'c-marco', name: 'Marco Rossi', role: 'inhaber' }] }] });
  assert.strictEqual(imp.created, 1);
  await lena.fill('#wiz-name', "Lena's Kiosk");
  await lena.waitForSelector('[data-partial="wiz-name"] .err');
  log('Vergebener Name: ' + (await lena.locator('[data-partial="wiz-name"] .err').first().innerText()));

  await lena.fill('#wiz-name', 'Mustermann Bau');
  await lena.waitForSelector('[data-partial="wiz-name"] .okmsg');
  log('Name frei: ' + (await lena.locator('[data-partial="wiz-name"] .okmsg').first().innerText()));
  await lena.click('[data-act="wiz-next"]');                       // Gründer
  await lena.click('[data-act="wiz-next"]');                       // Standort
  await lena.click('[data-act="wiz-site-mode"][data-mode="mobil"]');
  await lena.click('[data-act="wiz-next"]');                       // Konzept
  await lena.fill('#wiz-idea', 'Wir übernehmen kleine Bau- und Renovierungsarbeiten für Privatkunden und Gewerbe in Los Santos. Schwerpunkt sind Trockenbau, Malerarbeiten und Bodenbeläge.');
  await lena.click('[data-act="wiz-next"]');                       // Prüfen
  await lena.check('#wiz-confirm');
  await lena.shot('01-review');
  await lena.click('[data-act="wiz-submit"]');
  await lena.click('[data-act="modal-yes"]');
  await lena.waitForSelector('.stamp');
  const caseNo = ((await lena.locator('h2').first().innerText()).match(/GA-\d{4}-\d{4}/) || [])[0];
  assert(caseNo, 'Aktenzeichen vergeben');
  log('Antrag eingereicht: ' + caseNo);
  assert.strictEqual(await S(lena, () => IC.S.d.me.bank), 184250 - 250 - 750, 'Konto belastet um 1.000');
  await lena.shot('02-eingereicht');

  /* ===== B: Beamter: Dienst und Vorprüfung ===== */
  await openApp(keller, lua, 'beamte');
  await go(keller, 'beamte', 'reviews');
  await keller.click('.seg [data-act="duty-set"][data-state="on"]'); await keller.settle();
  assert.strictEqual(await S(keller, () => IC.S.d.official.onDuty), true, 'Beamter ist im Dienst');
  await keller.locator('tr', { hasText: 'Mustermann Bau' }).locator('[data-act="rev-open"]').click();
  await keller.waitForSelector('.modal');
  await keller.click('[data-act="rev-do"][data-result="ok"]'); await keller.settle();
  assert.strictEqual(await S(keller, () => IC.S.d.officialApps.find((a) => a.name === 'Mustermann Bau').status), 'vorpruefung_ok');
  log('Vorprüfung bestanden (Beamter im Dienst)');

  /* ===== C: Termin buchen (Gewerbeamt-Fenster wechselt zum Bürgeramt) ===== */
  await lena.click('[data-act="view"][data-view="home"]').catch(() => {});
  await go(lena, 'gewerbeamt', 'home');
  await lena.click('.tile >> text=Termin im Bürgeramt');
  await lena.waitForSelector('[data-act="book-type"]');
  log('Wechsel von Gewerbeamt zu Bürgeramt im selben Fenster: ' + (await lena.locator('.win-title').innerText()).replace(/\s+/g, ' '));
  await lena.click('[data-act="book-type"][data-key="vorstellung_unternehmen"]');
  await lena.waitForSelector('.slot:not([disabled])');
  const nSlots = await lena.locator('.slot:not([disabled])').count();
  log('Live-Slots: ' + nSlots);
  await lena.shot('03-slots');
  await lena.locator('.slot:not([disabled])').first().click();
  await lena.click('[data-act="book-submit"]');
  await lena.waitForSelector('.ticket');
  const apptId = (await lena.locator('.ticket .tn').innerText()).trim();
  log('Termin gebucht: ' + apptId);

  /* ===== D: einchecken, aufrufen, entscheiden ===== */
  const start = await S(lena, (id) => IC.S.d.myAppointments.find((a) => a.id === id).start, apptId);
  const nowMs = await S(lena, () => IC.now());
  await lua.call('advance', { ms: Math.max(0, start - nowMs - 2 * 60000) });
  await go(lena, 'buergeramt', 'appts');
  await lena.click(`[data-act="appt-checkin"][data-id="${apptId}"]`); await lena.settle();
  assert.strictEqual(await S(lena, (id) => IC.S.d.myAppointments.find((a) => a.id === id).status, apptId), 'eingecheckt');
  log('Eingecheckt');
  await lena.shot('04-termine');

  await go(keller, 'beamte', 'today');
  const card = keller.locator('article', { hasText: 'Mustermann Bau' });
  await card.locator('[data-act="appt-call"]').click(); await keller.settle();
  await card.locator('[data-act="appt-start"]').click(); await keller.settle();
  await keller.waitForSelector('[data-act="chk-toggle"]');
  for (const cb of await keller.locator('[data-act="chk-toggle"]').all()) await cb.check();
  await keller.shot('05-termin');
  await keller.click('[data-act="dec-open"][data-dec="genehmigt"]');
  await keller.click('[data-act="dec-confirm"]'); await keller.settle();
  await keller.waitForSelector('.stamp');
  const resTxt = await keller.locator('.main').innerText();
  assert(/HRA 100\d/.test(resTxt), 'Registernummer im Bescheid: ' + resTxt.slice(0, 200));
  log('Entscheidung: ' + (resTxt.match(/HRA \d+/) || [])[0]);
  await keller.shot('06-bescheid');

  await go(lena, 'gewerbeamt', 'entities');
  const ent = await lena.locator('article', { hasText: 'Mustermann Bau' }).innerText();
  assert(/HRA 100\d/.test(ent), 'Eintragung sichtbar');
  await lena.locator('article', { hasText: 'Mustermann Bau' }).locator('[data-act="ent-cert"]').click();
  await lena.waitForSelector('.cert');
  await lena.shot('07-schein');
  await lena.click('[data-act="modal-close"]');
  const dump = await lua.call('dump');
  const cert = dump.certificates[dump.certificates.length - 1];
  assert(cert.src === 1 && cert.regNo === 'HRA 1002', 'Gewerbeschein ging an Lena: ' + JSON.stringify(cert));
  log('Eintragung sichtbar, Gewerbeschein im Inventar: ' + ent.split('\n').slice(0, 2).join(' | '));

  /* ===== E: Organisation mit Mitgründern, OOC-Angaben und Schlussprüfung durch den Staff ===== */
  const tom = await actor(2, 'tom');
  const marco = await actor(3, 'marco');
  await go(lena, 'gewerbeamt', 'home');
  await lena.click('.tile >> text=Fraktion oder Organisation gründen');
  await lena.click('[data-act="wiz-form"][data-key="ev"]');
  await lena.click('[data-act="wiz-next"]');
  await lena.fill('#wiz-name', 'Skater Club Mirror Park');
  await lena.waitForSelector('[data-partial="wiz-name"] .okmsg');
  assert(/e\.V\./.test(await lena.locator('[data-partial="wiz-name"] .okmsg').innerText()), 'Zusatz e.V.');
  await lena.click('[data-act="wiz-next"]');
  assert(await lena.locator('[data-act="wiz-next"]').isDisabled(), 'Weiter gesperrt: zu wenig Mitglieder');
  assert(await lena.locator('[data-act="wiz-add-founder"][data-id="c-anna"]').isDisabled(), 'Anna Kowalski (zu wenig Spielzeit) ist nicht einladbar');
  await lena.click('[data-act="wiz-add-founder"][data-id="c-tom"]');
  await lena.click('[data-act="wiz-add-founder"][data-id="c-marco"]');
  await lena.settle();
  const pend = await S(lena, () => IC.S.ui.wiz.founders.filter((f) => f.consent === 'pending').length);
  assert.strictEqual(pend, 2, 'beide Einladungen stehen aus');
  assert.strictEqual((await lua.call('dump')).applications.length, 1, 'Einladung legt noch keinen Antrag an');
  await lua.call('inviteAnswer', { src: 2, accept: true });
  await lua.call('inviteAnswer', { src: 3, accept: false });
  await lena.waitForFunction(() => IC.S.ui.wiz.founders.every((f) => f.consent !== 'pending'), null, { timeout: 15000 });
  const cons = await S(lena, () => IC.S.ui.wiz.founders.map((f) => f.name + ':' + f.consent).join(', '));
  log('Zustimmung der Mitgründer kommt vom Server: ' + cons + ' (Marco hat abgelehnt und ist aus der Liste)');
  assert.strictEqual(cons, 'Lena Brandt:self, Tom Becker:ok');
  assert(await lena.locator('[data-act="wiz-next"]').isDisabled(), 'Mit zwei Mitgliedern geht es beim Verein nicht weiter');
  // Marco überlegt es sich anders: neue Einladung
  await lena.click('[data-act="wiz-add-founder"][data-id="c-marco"]');
  await lua.call('inviteAnswer', { src: 3, accept: true });
  await lena.waitForFunction(() => IC.S.ui.wiz.founders.every((f) => f.consent === 'ok' || f.consent === 'self'), null, { timeout: 15000 });
  log('Marco hat nach der zweiten Einladung zugestimmt');
  await lena.click('[data-act="wiz-next"]');                       // Sitz
  await lena.click('[data-act="wiz-site-mode"][data-mode="mobil"]');
  await lena.click('[data-act="wiz-next"]');                       // Satzung
  await lena.fill('#wiz-purpose', 'Wir bringen Skater aus Mirror Park zusammen, organisieren Treffen, kleine Wettbewerbe und kümmern uns um einen sicheren Skatepark im Viertel.');
  await lena.click('[data-act="wiz-next"]');                       // Angaben für den Staff
  await lena.selectOption('#wiz-oocc', 'untergrund');
  await lena.fill('#wiz-oocn', 'Soll als Tarnung für eine Gang dienen.');
  await lena.check('#wiz-confirm');
  await lena.shot('08-verein-pruefen');
  await lena.click('[data-act="wiz-submit"]'); await lena.click('[data-act="modal-yes"]');
  await lena.waitForSelector('.stamp');
  log('Organisation eingereicht: ' + (await lena.locator('h2').first().innerText()));

  await go(keller, 'beamte', 'reviews');
  const rev = await S(keller, () => JSON.stringify(IC.S.d.officialApps.find((a) => a.name === 'Skater Club Mirror Park e.V.')));
  assert(!/untergrund|ooc/i.test(rev), 'OOC-Daten sind in der Beamten-Sicht nicht enthalten');
  log('Beamte sehen keine OOC-Angaben');
  await keller.locator('tr', { hasText: 'Skater Club' }).locator('[data-act="rev-open"]').click();
  await keller.click('[data-act="rev-do"][data-result="ok"]'); await keller.settle();

  await go(lena, 'buergeramt', 'book');
  await lena.click('[data-act="book-type"][data-key="vorstellung_fraktion"]');
  await lena.waitForSelector('.slot:not([disabled])');
  await lena.locator('.slot:not([disabled])').first().click();
  assert.strictEqual(await lena.locator('[data-act="book-attendee"][disabled]').count(), 3, 'Alle drei Gründungsmitglieder sind Pflichtteilnehmer');
  await lena.click('[data-act="book-submit"]');
  await lena.waitForSelector('.ticket');
  const vId = (await lena.locator('.ticket .tn').innerText()).trim();
  const vStart = await S(lena, (id) => IC.S.d.myAppointments.find((a) => a.id === id).start, vId);
  await lua.call('advance', { ms: Math.max(0, vStart - (await S(lena, () => IC.now())) - 2 * 60000) });
  // Jeder Pflichtteilnehmer checkt selbst ein, auch Tom und Marco über ihr eigenes Terminal
  for (const [who, label] of [[lena, 'Lena'], [tom, 'Tom'], [marco, 'Marco']]) {
    if (who !== lena) await openApp(who, lua, 'gewerbeamt');
    await go(who, 'buergeramt', 'appts');
    await who.click(`[data-act="appt-checkin"][data-id="${vId}"]`); await who.settle();
    assert.strictEqual(await S(who, (id) => IC.S.d.myAppointments.find((a) => a.id === id).status, vId), label === 'Marco' ? 'eingecheckt' : 'gebucht');
  }
  log('Alle drei Pflichtteilnehmer eingecheckt (Termin ' + vId + ')');

  await go(keller, 'beamte', 'today');
  const vcard = keller.locator('article', { hasText: 'Skater Club' });
  await vcard.locator('[data-act="appt-start"]').click(); await keller.settle();
  for (const cb of await keller.locator('[data-act="chk-toggle"]').all()) await cb.check();
  await keller.click('[data-act="dec-open"][data-dec="genehmigt"]'); await keller.click('[data-act="dec-confirm"]'); await keller.settle();
  const vres = await keller.locator('.main').innerText();
  assert(/Schlussprüfung/.test(vres), 'Staff-Gate greift: ' + vres.slice(0, 160).replace(/\n/g, ' '));
  log('Genehmigt, weiter zur Schlussprüfung');
  await keller.click('[data-act="term-close"]');

  await openApp(admin, lua, 'staff');
  await go(admin, 'staff', 'gate');
  const gate = await admin.locator('.main').innerText();
  assert(/Skater Club/.test(gate) && /Untergrund/.test(gate), 'Staff sieht die OOC-Angaben');
  assert(/Der Name ist frei/.test(gate) && /3 Gründungsmitglieder, erforderlich sind mindestens 3/.test(gate) && /Beteiligungen an anderen Einträgen/.test(gate), 'Hinweise zur Schlussprüfung kommen aus den Daten: ' + gate.replace(/\n/g, ' ').slice(0, 400));
  const used0 = await S(admin, () => IC.S.d.staff.undergroundCap.used);
  await admin.locator('article', { hasText: 'Skater Club' }).locator('[data-act="gate-ok"]').click();
  await admin.click('[data-act="modal-yes"]'); await admin.settle();
  const used1 = await S(admin, () => IC.S.d.staff.undergroundCap.used);
  assert.strictEqual(used1, used0 + 1, 'Untergrund-Platz verbraucht');
  log('Staff gibt frei, Untergrund-Plätze ' + used0 + ' -> ' + used1);
  await go(lena, 'gewerbeamt', 'entities');
  assert(/VR 02\d\d/.test(await lena.locator('article', { hasText: 'Skater Club' }).innerText()), 'Organisation ist eingetragen');
  const vDump = await lua.call('dump');
  assert(vDump.certificates.some((c) => c.regNo.startsWith('VR')), 'Vorsitzende hat die Urkunde bekommen');
  log('Organisation steht im Register, Urkunde ausgehändigt');

  /* ===== F: Nachbesserung, Ablehnung und Einspruch ===== */
  const wizardEinzel = async (who, branch, name, idea) => {
    await go(who, 'gewerbeamt', 'home');
    await who.click('.tile >> text=Unternehmen gründen');
    await who.click(`[data-act="wiz-branch"][data-key="${branch}"]`); await who.click('[data-act="wiz-next"]');
    await who.click('[data-act="wiz-form"][data-key="einzel"]');
    await who.fill('#wiz-name', name);
    await who.waitForSelector('[data-partial="wiz-name"] .okmsg');
    await who.click('[data-act="wiz-next"]'); await who.click('[data-act="wiz-next"]');
    await who.click('[data-act="wiz-site-mode"][data-mode="mobil"]'); await who.click('[data-act="wiz-next"]');
    await who.fill('#wiz-idea', idea); await who.click('[data-act="wiz-next"]');
    await who.check('#wiz-confirm'); await who.click('[data-act="wiz-submit"]'); await who.click('[data-act="modal-yes"]');
    await who.waitForSelector('.stamp');
  };
  const IDEA = 'Wir fahren Pakete und Möbel für Privatkunden und kleine Läden quer durch Los Santos, mit eigenem Transporter, festen Preisen und Zustellung am selben Tag.';
  await wizardEinzel(tom, 'transport', 'Becker Logistik', IDEA);
  await wizardEinzel(marco, 'handwerk', 'Rossi Reparaturen', IDEA);
  log('Zwei weitere Anträge eingereicht (Tom, Marco)');

  await go(keller, 'beamte', 'reviews');
  await keller.locator('tr', { hasText: 'Becker Logistik' }).locator('[data-act="rev-open"]').click();
  await keller.fill('#rev-msg', 'kurz');
  await keller.click('[data-act="rev-do"][data-result="nachbesserung"]'); await keller.settle();
  assert(await keller.locator('.toast.bad').count() >= 1, 'Zu kurze Begründung wird abgelehnt');
  await keller.fill('#rev-msg', 'Bitte Fahrzeugtyp und Einsatzgebiet genauer beschreiben.');
  await keller.click('[data-act="rev-do"][data-result="nachbesserung"]'); await keller.settle();
  assert.strictEqual(await S(keller, () => IC.S.d.officialApps.find((a) => a.name.startsWith('Becker Logistik')).status), 'nachbesserung');
  log('Nachbesserung verlangt (Begründung Pflicht)');

  await keller.locator('tr', { hasText: 'Rossi Reparaturen' }).locator('[data-act="rev-open"]').click();
  await keller.fill('#rev-msg', 'Der Zweck ist aus Sicht der Behörde unzulässig.');
  await keller.click('[data-act="rev-do"][data-result="abgelehnt"]'); await keller.settle();
  assert.strictEqual((await lua.call('dump')).applications.find((a) => a.name.startsWith('Rossi Reparaturen')).status, 'abgelehnt');
  assert(!(await S(keller, () => IC.S.d.officialApps.some((a) => a.name.startsWith('Rossi Reparaturen')))), 'abgeschlossene Anträge sind nicht mehr in der Antwort des Tablets');
  log('Antrag abgelehnt');

  // Tom bessert nach und reicht erneut ein
  await go(tom, 'gewerbeamt', 'apps');
  await tom.click('[data-act="app-open"]:has-text("Becker Logistik")'); await tom.settle();
  assert(/Fahrzeugtyp/.test(await tom.locator('.main').innerText()), 'Tom sieht den Hinweis der Beamten');
  await tom.click('[data-act="wiz-edit"]'); await tom.settle();
  for (let i = 0; i < 8 && !(await tom.locator('[data-act="wiz-submit"]').count()); i++) await tom.click('[data-act="wiz-next"]');
  await tom.check('#wiz-confirm');
  await tom.click('[data-act="wiz-submit"]');
  if (await tom.locator('[data-act="modal-yes"]').count()) await tom.click('[data-act="modal-yes"]');
  await tom.waitForSelector('.stamp');
  assert.strictEqual(await S(tom, () => IC.S.d.myApplications.find((a) => a.name.startsWith('Becker Logistik')).status), 'eingereicht');
  log('Tom hat nachgebessert und erneut eingereicht');
  await go(keller, 'beamte', 'reviews');
  await keller.locator('tr', { hasText: 'Becker Logistik' }).locator('[data-act="rev-open"]').click();
  await keller.click('[data-act="rev-do"][data-result="ok"]'); await keller.settle();

  // Marco legt Einspruch ein
  await go(marco, 'gewerbeamt', 'apps');
  await marco.click('[data-act="app-open"]:has-text("Rossi Reparaturen")'); await marco.settle();
  await marco.click('[data-act="app-objection-open"]');
  await marco.fill('#obj-text', 'Der Zweck ist legal: Wir reparieren Fahrzeuge und Geräte, der Mietvertrag liegt bei.');
  await marco.click('[data-act="app-objection-send"]'); await marco.settle();
  assert.strictEqual(await S(marco, () => IC.S.d.myApplications.find((a) => a.name.startsWith('Rossi')).status), 'einspruch');
  log('Einspruch eingelegt');

  /* ===== G: ohne Beamte keine Termine, Sprechzeiten füllen die Lücke ===== */
  await go(keller, 'beamte', 'reviews');
  await keller.click('.seg [data-act="duty-set"][data-state="off"]'); await keller.settle();
  await go(lena, 'buergeramt', 'book');
  await lena.click('[data-act="book-type"][data-key="beratung"]');
  await lena.waitForSelector('.duty.off');
  const banner = await lena.locator('.duty.off').first().innerText();
  assert(/kein Beamter im Dienst/.test(banner), 'Banner: ' + banner);
  assert.strictEqual(await lena.locator('.slot:not([disabled])').count(), 0, 'keine Slots ohne Beamte');
  await lena.shot('09-ohne-beamte');
  await go(lena, 'buergeramt', 'queue');
  assert(await lena.locator('[data-act="queue-take"]').isDisabled(), 'Wartenummer ohne Beamte gesperrt');
  log('Ohne Beamte: "' + banner.replace(/\s+/g, ' ').slice(0, 80) + '", Wartenummer gesperrt');

  await go(keller, 'beamte', 'hours');
  await keller.selectOption('#hrs-day', '1');
  await keller.selectOption('#hrs-start', String(10 * 60));
  await keller.selectOption('#hrs-dur', '120');
  await keller.click('[data-act="hours-add"]'); await keller.settle();
  assert((await S(keller, () => IC.S.d.hours.length)) >= 1, 'Sprechzeit veröffentlicht');
  await go(lena, 'buergeramt', 'book');
  await lena.click('[data-act="book-type"][data-key="beratung"]');
  await lena.click('[data-act="book-day"][data-off="1"]');
  await lena.waitForSelector('.slot:not([disabled])');
  const hs = await lena.locator('.slot:not([disabled])').count();
  assert(hs > 0, 'Sprechzeit erzeugt buchbare Slots');
  await lena.locator('.slot:not([disabled])').first().click();
  await lena.click('[data-act="book-submit"]'); await lena.waitForSelector('.ticket');
  const bId = (await lena.locator('.ticket .tn').innerText()).trim();
  log('Beratung in der Sprechzeit gebucht (' + hs + ' Slots am Folgetag): ' + bId);
  await go(lena, 'buergeramt', 'appts');
  await lena.click(`[data-act="appt-cancel"][data-id="${bId}"]`);
  if (await lena.locator('[data-act="modal-yes"]').count()) await lena.click('[data-act="modal-yes"]');
  await lena.settle();
  assert.strictEqual(await S(lena, (id) => IC.S.d.myAppointments.find((a) => a.id === id).status, bId), 'abgesagt');
  log('Termin folgenlos abgesagt');
  await go(keller, 'beamte', 'reviews');
  await keller.click('.seg [data-act="duty-set"][data-state="on"]'); await keller.settle();
  await go(lena, 'buergeramt', 'queue');
  await lena.click('[data-act="queue-take"]'); await lena.settle();
  assert.strictEqual(await lena.locator('.ticket .tn').count(), 1, 'Wartenummer mit Beamten');
  const ticket = (await lena.locator('.ticket .tn').innerText()).trim();
  await go(keller, 'beamte', 'today');
  await keller.click('[data-act="queue-next"]'); await keller.settle();
  await go(lena, 'buergeramt', 'queue');
  assert(/aufgerufen|Schalter/i.test(await lena.locator('.main').innerText()), 'Aufruf kommt bei Lena an');
  log('Wartenummer ' + ticket + ' gezogen und aufgerufen');

  /* ===== H: Fristen, Notfallregel des Staffs, Sanktion nur mit Rang ===== */
  await lua.call('advance', { ms: 4 * 24 * 3600 * 1000 });            // vier Tage später
  await go(admin, 'staff', 'esc');
  const esc = await admin.locator('.main').innerText();
  assert(/Becker Logistik/.test(esc) && /Eskalation/.test(esc), 'Eskalation sichtbar: ' + esc.slice(0, 200).replace(/\n/g, ' '));
  assert(/Rossi Reparaturen/.test(esc) && /Einspruch/.test(esc), 'auch der liegengebliebene Einspruch ist eine Eskalation');
  await admin.locator('tr', { hasText: 'Becker Logistik' }).locator('[data-act="esc-open"]').click();
  await admin.fill('#ew-reason', 'Nach Aktenlage unbedenklich, alle Unterlagen vollständig.');
  await admin.click('[data-act="esc-send"]'); await admin.settle();
  assert.strictEqual(await S(admin, () => IC.S.d.staff.applicationsAll.find((a) => a.name.startsWith('Becker Logistik')).status), 'genehmigt');
  log('Eskalation: Entscheidung nach Aktenlage, Becker Logistik eingetragen');
  await admin.locator('tr', { hasText: 'Rossi Reparaturen' }).locator('[data-act="esc-open"]').click();
  await admin.selectOption('#ew-dec', 'abgelehnt');
  await admin.fill('#ew-reason', 'Die Ablehnung bleibt nach Aktenlage bestehen.');
  await admin.click('[data-act="esc-send"]'); await admin.settle();
  const rossi = (await lua.call('dump')).applications.find((a) => a.name.startsWith('Rossi Reparaturen'));
  assert(rossi.status === 'abgelehnt' && rossi.objectionUntil === 0, 'Einspruch nach Aktenlage entschieden, endgültig: ' + rossi.status);
  log('Liegengebliebener Einspruch: Staff entscheidet nach Aktenlage, endgültig');

  await go(keller, 'beamte', 'breg');
  await keller.locator('tr', { hasText: 'Mustermann Bau' }).locator('[data-act="sanction-open"]').click();
  await keller.fill('#sc-reason', 'Wiederholte Lärmbeschwerden der Anwohner.');
  await keller.click('[data-act="sanction-send"]'); await keller.settle();
  const hist = await S(keller, () => IC.S.d.register.find((e) => e.name === 'Mustermann Bau').history.length);
  assert(hist >= 1, 'Maßnahme steht in der Historie');
  log('Maßnahme verhängt (Amtsleiter, mit Begründung)');

  const yilmaz = await actor(11, 'yilmaz');
  await openApp(yilmaz, lua, 'beamte');
  await go(yilmaz, 'beamte', 'breg');
  assert(await yilmaz.locator('[data-act="sanction-open"]').first().isDisabled(), 'Sachbearbeiter darf nicht sanktionieren');
  log('Sachbearbeiter sieht die Schaltfläche für Maßnahmen gesperrt');

  /* ===== I: Staff-Panel: Sperrliste, Kapazität, Einstellungen, Protokoll ===== */
  await go(admin, 'staff', 'black');
  await admin.fill('#bl-term', 'Weißes Haus');
  await admin.fill('#bl-reason', 'Reale Marke');
  await admin.click('[data-act="bl-add"]'); await admin.settle();
  const nc = await lena.evaluate(() => IC.api('nameCheck', { name: 'Weißes Haus Bar', legalForm: 'einzel' }));
  assert.strictEqual(nc.ok, false, 'Gesperrter Begriff greift sofort: ' + JSON.stringify(nc.issues));
  await admin.locator('tr', { hasText: 'Weißes Haus' }).locator('[data-act="bl-del"]').click(); await admin.settle();
  const nc2 = await lena.evaluate(() => IC.api('nameCheck', { name: 'Weißes Haus Bar', legalForm: 'einzel' }));
  assert.strictEqual(nc2.ok, true, 'Nach dem Entsperren ist der Name wieder frei');
  log('Sperrliste: sperren und entsperren wirkt sofort');

  await go(admin, 'staff', 'register');
  await admin.locator('tr', { hasText: 'Mustermann Bau' }).locator('[data-act="es-open"]').click();
  await admin.waitForSelector('#es-reason');
  await admin.fill('#es-reason', 'kurz');
  await admin.click('[data-act="es-send"]'); await admin.settle();
  assert(await admin.locator('.toast.bad').count() >= 1, 'Begründung ist Pflicht');
  await admin.selectOption('#es-status', 'gesperrt');
  await admin.fill('#es-reason', 'Wiederholte Verstöße gegen die Serverregeln.');
  await admin.click('[data-act="es-send"]'); await admin.settle();
  assert.strictEqual((await lua.call('dump')).entities.find((e) => e.name === 'Mustermann Bau').status, 'gesperrt');
  await go(lena, 'gewerbeamt', 'entities');
  assert(/gesperrt/i.test(await lena.locator('article', { hasText: 'Mustermann Bau' }).innerText()), 'Lena sieht die Sperre');
  assert(/Registerführung/.test(await S(lena, () => IC.S.d.notices.map((n) => n.text).join(' '))), 'Lena wird von der Registerführung informiert, nicht vom Staff');
  await admin.locator('tr', { hasText: 'Mustermann Bau' }).locator('[data-act="es-open"]').click();
  await admin.waitForSelector('#es-reason');
  await admin.fill('#es-reason', 'Nach Rücksprache wieder zugelassen.');
  await admin.click('[data-act="es-send"]'); await admin.settle();
  assert.strictEqual((await lua.call('dump')).entities.find((e) => e.name === 'Mustermann Bau').status, 'aktiv');
  log('Staff greift in das Register ein: sperren, Begründung Pflicht, wieder freigeben');

  await go(admin, 'staff', 'caps');
  const cap0 = await S(admin, () => IC.S.d.staff.caps.find((c) => c.key === 'gastro').cap);
  await admin.click('[data-act="cap-step"][data-key="gastro"][data-d="-1"]'); await admin.settle();
  const cap1 = await S(admin, () => IC.S.d.staff.caps.find((c) => c.key === 'gastro').cap);
  assert.strictEqual(cap1, cap0 - 1);
  log('Kapazität Gastronomie ' + cap0 + ' -> ' + cap1);

  await go(admin, 'staff', 'settings');
  assert(await admin.locator('[data-act="set-toggle"][data-key="fourEyes"]').isDisabled(), 'Vier-Augen-Prinzip ist als Phase 2 gesperrt');
  const before = await S(admin, () => IC.S.d.staff.settings.writtenProcedure);
  await admin.click('[data-act="set-toggle"][data-key="writtenProcedure"]'); await admin.settle();
  assert.strictEqual(await S(admin, () => IC.S.d.staff.settings.writtenProcedure), !before);
  await admin.click('[data-act="set-toggle"][data-key="writtenProcedure"]'); await admin.settle();
  log('Einstellung umgeschaltet und zurückgestellt');

  await go(admin, 'staff', 'audit');
  const au = await admin.locator('.main').innerText();
  assert(/Eintragung/.test(au) && /Entscheidung nach Aktenlage/.test(au) && /Sanktion/.test(au), 'Protokoll enthält die Ereignisse');
  log('Protokoll enthält Eintragung, Entscheidung nach Aktenlage und Sanktion');
  await admin.shot('10-audit');
  await go(admin, 'staff', 'overview');
  await admin.shot('11-uebersicht');

  /* ===== K: Rundgang durch alle Ansichten mit den echten Daten dieses Ablaufs ===== */
  const walk = async (page, app) => {
    const views = await S(page, (a) => Object.keys(IC.apps[a].views), app);
    for (const v of views) {
      const before = page.errors.length;
      await go(page, app, v);
      const text = (await page.locator('.main').innerText()).trim();
      assert(text.length > 40, `${page.label}: ${app}/${v} ist leer`);
      assert(!/undefined|NaN|\[object Object\]/.test(text), `${page.label}: ${app}/${v} zeigt kaputte Werte: ` + (text.match(/.{0,40}(undefined|NaN|\[object Object\]).{0,40}/) || [''])[0]);
      assert.strictEqual(page.errors.length, before, `${page.label}: ${app}/${v} wirft Fehler: ` + page.errors.slice(before).join(' | '));
    }
    return views.length;
  };
  let seen = 0;
  seen += await walk(lena, 'gewerbeamt');
  seen += await walk(lena, 'buergeramt');
  seen += await walk(keller, 'beamte');
  seen += await walk(admin, 'staff');
  // jeder Antrag und jede Eintragung im Detail
  for (const [who, name] of [[lena, 'Lena'], [tom, 'Tom'], [marco, 'Marco']]) {
    await go(who, 'gewerbeamt', 'apps');
    const ids = await who.locator('[data-act="app-open"]').evaluateAll((els) => els.map((e) => e.dataset.id));
    for (const id of [...new Set(ids)]) {
      const before = who.errors.length;
      await S(who, (i) => { IC.S.ui.appSel = i; IC.view('apps'); }, id);
      await who.settle();
      assert(!/undefined|NaN|\[object Object\]/.test(await who.locator('.main').innerText()), `${name}: Antrag ${id} zeigt kaputte Werte`);
      assert.strictEqual(who.errors.length, before, `${name}: Antrag ${id} wirft Fehler`);
      seen++;
    }
  }
  log('Rundgang: ' + seen + ' Ansichten und Antragsdetails ohne Fehler und ohne kaputte Werte');
  await lena.shot('12-eintragungen');

  /* ===== J: Berechtigung und Ort prüft der Server ===== */
  await lua.call('player', { src: 1, patch: { at: ['gewerbeamt', 50] } });
  await lena.evaluate(() => IC.reload());
  assert(/entfernt/.test(await S(lena, () => IC.S.err || '')), 'Wer das Terminal verlässt, wird abgewiesen: ' + await S(lena, () => IC.S.err));
  log('Entfernt sich Lena vom Terminal, endet ihre Sitzung: ' + await S(lena, () => IC.S.err));
  await lua.call('player', { src: 1, patch: { at: ['gewerbeamt', 0] } });
  const reopen = await lua.call('open', { src: 1, app: 'gewerbeamt', index: 1 });
  assert(reopen.opened, 'Am Terminal lässt es sich wieder öffnen');

  await lua.call('player', { src: 10, patch: { rank: false } });         // Keller verliert den Job
  await keller.evaluate(() => IC.reload());
  assert(/nicht befugt/.test(await S(keller, () => IC.S.err || '')), 'Ohne Job kein Tablet: ' + await S(keller, () => IC.S.err));
  log('Verliert Dr. Keller den Job, wird sein Tablet gesperrt');
  const noTablet = await lua.call('open', { src: 1, app: 'beamte', index: 1 });
  assert.strictEqual(noTablet.opened, false);
  await lua.call('ace', { src: 99, on: false });
  await admin.evaluate(() => IC.reload());
  assert(/nicht befugt/.test(await S(admin, () => IC.S.err || '')), 'Ohne ACE-Recht kein Staff-Panel');
  log('Entzug des ACE-Rechts sperrt das Staff-Panel sofort');
};
