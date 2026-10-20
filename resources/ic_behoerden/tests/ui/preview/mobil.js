const { chromium } = require('playwright');
/* Vorschau-Test (Mock-Backend, ohne Server). Aufruf aus resources/ic_behoerden:  node tests/ui/preview/mobil.js
   Bildschirmfotos optional: SHOTS=/pfad/zum/ordner node … */
const path = require('path');
const WEB = 'file://' + path.resolve(__dirname, '..', '..', '..', 'web', 'index.html');
const SHOTS = process.env.SHOTS || '';
const shotPath = (n) => path.join(SHOTS, n);

const VIEWS = {
  gewerbeamt: ['home','wizard','apps','entities','register','fees'],
  buergeramt: ['book','appts','queue'],
  beamte: ['today','reviews','hours','breg','manual'],
  staff: ['overview','gate','esc','caps','black','audit','settings'],
  konzept: ['overview'],
};
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 400, height: 860 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', m => { if (['error','warning'].includes(m.type())) errors.push(m.type()+': '+m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  await page.goto(WEB);
  await page.waitForSelector('.win-body');
  let bad = 0;
  for (const [app, views] of Object.entries(VIEWS)) {
    for (const v of views) {
      await page.evaluate(([a, v]) => IC.go(a, v), [app, v]);
      await page.waitForTimeout(300);
      const r = await page.evaluate(() => {
        const vw = document.documentElement.clientWidth;
        const sw = document.documentElement.scrollWidth;
        const offenders = [];
        if (sw > vw + 1) {
          document.querySelectorAll('body *').forEach(el => {
            const b = el.getBoundingClientRect();
            if (b.right > vw + 1 && b.width > 0) {
              // ignorieren, wenn ein Vorfahre scrollt
              let p = el.parentElement, scroll = false;
              while (p && p !== document.body) { const o = getComputedStyle(p).overflowX; if (o === 'auto' || o === 'scroll' || o === 'hidden') { scroll = true; break; } p = p.parentElement; }
              if (!scroll) offenders.push(el.tagName.toLowerCase() + '.' + String(el.className).split(' ')[0] + ' (' + Math.round(b.right) + ')');
            }
          });
        }
        return { vw, sw, offenders: offenders.slice(0, 5) };
      });
      const flag = r.sw > r.vw + 1 ? 'OVERFLOW ' + JSON.stringify(r.offenders) : 'ok';
      if (flag !== 'ok') bad++;
      console.log(app.padEnd(11), v.padEnd(9), r.sw + '/' + r.vw, flag);
    }
  }
  // Wizard-Schritte mobil
  await page.evaluate(() => { IC.S.ui.wiz = null; IC.go('gewerbeamt', 'wizard'); }); await page.waitForTimeout(300);
  await (SHOTS ? page.screenshot({ path: shotPath('m-wizard0.png'), fullPage: true }) : null);
  await page.evaluate(() => IC.go('buergeramt', 'book')); await page.waitForTimeout(300);
  await (SHOTS ? page.screenshot({ path: shotPath('m-book.png'), fullPage: true }) : null);
  await page.evaluate(() => IC.go('gewerbeamt', 'home')); await page.waitForTimeout(300);
  await (SHOTS ? page.screenshot({ path: shotPath('m-home.png'), fullPage: true }) : null);
  console.log('Seiten mit horizontalem Überlauf:', bad);
  console.log('ERRORS', JSON.stringify(errors));
  await browser.close();
})();
