const { chromium } = require('playwright');
/* Vorschau-Test (Mock-Backend, ohne Server). Aufruf aus resources/ic_behoerden:  node tests/ui/preview/dunkel.js
   Bildschirmfotos optional: SHOTS=/pfad/zum/ordner node … */
const path = require('path');
const WEB = 'file://' + path.resolve(__dirname, '..', '..', '..', 'web', 'index.html');
const SHOTS = process.env.SHOTS || '';
const shotPath = (n) => path.join(SHOTS, n);

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: 'dark' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', m => { if (['error','warning'].includes(m.type())) errors.push(m.type()+': '+m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  await page.goto(WEB + '#gewerbeamt');
  await page.waitForSelector('.win-body');
  await page.waitForTimeout(500);
  console.log('Systemthema dunkel, Hintergrund:', await page.evaluate(() => getComputedStyle(document.body).backgroundColor));
  await (SHOTS ? page.screenshot({ path: shotPath('dark-home.png'), fullPage: false }) : null);
  await page.evaluate(() => IC.go('buergeramt', 'appts')); await page.waitForTimeout(400);
  await (SHOTS ? page.screenshot({ path: shotPath('dark-appts.png'), fullPage: false }) : null);
  await page.evaluate(() => { IC.S.ui.wiz = null; IC.go('gewerbeamt', 'wizard'); }); await page.waitForTimeout(400);
  await page.click('[data-act="wiz-kind"][data-kind="unternehmen"]');
  await page.waitForTimeout(300);
  await (SHOTS ? page.screenshot({ path: shotPath('dark-wizard.png'), fullPage: false }) : null);
  // Hell erzwingen und Kontrast gegenprüfen
  await page.click('[data-act="pv-theme"]'); await page.waitForTimeout(300);
  console.log('Nach Umschalten:', await page.evaluate(() => document.documentElement.getAttribute('data-theme') + ' / ' + getComputedStyle(document.body).backgroundColor));
  console.log('ERRORS', JSON.stringify(errors));
  await browser.close();
})();
