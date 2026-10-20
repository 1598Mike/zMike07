const { chromium } = require('playwright');
/* Vorschau-Test (Mock-Backend, ohne Server). Aufruf aus resources/ic_behoerden:  node tests/ui/preview/nui.js
   Bildschirmfotos optional: SHOTS=/pfad/zum/ordner node … */
const path = require('path');
const WEB = 'file://' + path.resolve(__dirname, '..', '..', '..', 'web', 'index.html');
const SHOTS = process.env.SHOTS || '';
const shotPath = (n) => path.join(SHOTS, n);

const assert = require('assert');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [];
  page.on('console', m => { if (['error','warning'].includes(m.type())) errors.push(m.type()+': '+m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  await page.addInitScript(() => {
    window.GetParentResourceName = () => 'ic_behoerden';
    window.__calls = [];
    window.fetch = async (url, opts) => {
      const name = String(url).split('/').pop();
      const body = opts && opts.body ? JSON.parse(opts.body) : {};
      window.__calls.push([String(url), name, body]);
      const r = await IC.mock.handle(name, body);   // Mock als Stellvertreter für den Server
      return { json: async () => r };
    };
  });
  await page.goto(WEB);
  await page.waitForTimeout(400);
  assert.strictEqual(await page.locator('.win').count(), 0, 'Im Spiel ist vor dem Öffnen nichts sichtbar');
  assert.strictEqual(await page.locator('.pv-bar').count(), 0, 'Keine Vorschauleiste im Spiel');
  console.log('NUI: vor dem Öffnen leer, keine Vorschauleiste');
  await page.evaluate(() => window.postMessage({ action: 'open', app: 'buergeramt', view: 'book' }, '*'));
  await page.waitForSelector('.win-body');
  await page.waitForTimeout(400);
  const calls = await page.evaluate(() => window.__calls.map(c => c[0] + ' ' + JSON.stringify(c[2])));
  console.log('NUI-Aufrufe:', calls);
  assert(calls.some(c => c.startsWith('https://ic_behoerden/bootstrap')), 'bootstrap über NUI-URL');
  assert(await page.locator('.win-title .x').count() === 1, 'Schließen-Knopf vorhanden');
  assert(await page.evaluate(() => document.documentElement.classList.contains('nui')), 'html.nui gesetzt');
  const box = await page.locator('.win').boundingBox();
  console.log('Fenstergröße im Spiel:', Math.round(box.width) + 'x' + Math.round(box.height));
  assert(box.height <= 900 && box.width <= 1600, 'Fenster passt auf den Bildschirm');
  await (SHOTS ? page.screenshot({ path: shotPath('nui-book.png') }) : null);
  await page.click('.win-title .x');
  await page.waitForTimeout(200);
  assert((await page.evaluate(() => window.__calls.map(c => c[1]))).includes('close'), 'close-Callback wird gesendet');
  await page.evaluate(() => window.postMessage({ action: 'close' }, '*'));
  await page.waitForTimeout(200);
  assert.strictEqual(await page.locator('.win').count(), 0, 'Nach close verschwindet das Fenster');
  console.log('NUI: close-Callback gesendet, Fenster geschlossen');
  await page.evaluate(() => window.postMessage({ action: 'open', app: 'gewerbeamt', view: 'home' }, '*'));
  await page.waitForSelector('.win-body');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  assert((await page.evaluate(() => window.__calls.filter(c => c[1] === 'close').length)) >= 2, 'ESC sendet close');
  console.log('NUI: ESC schließt');
  console.log('ERRORS', JSON.stringify(errors));
  await browser.close();
  console.log('NUI OK');
})().catch(e => { console.error('NUI FEHLER:', e.message); process.exit(1); });
