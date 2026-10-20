/*
  Oberfläche gegen die echte Serverlogik: Der Browser lädt web/index.html im NUI-Modus, alle Aufrufe gehen an
  tests/ui/server.lua (Serverlogik mit Fake-Bridge). Mehrere Spieler öffnen je eine eigene Seite.
  Aufruf aus resources/ic_behoerden:   node tests/ui/e2e-server.js        (Node mit Playwright, Lua 5.4)
*/
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
const assert = require('assert');

const RES = path.resolve(__dirname, '..', '..');
const INDEX = 'file://' + path.join(RES, 'web', 'index.html');
const SHOTS = process.env.SHOTS || '';

let step = 0;
const log = (m) => console.log(String(++step).padStart(2, '0') + ' ' + m);

class Lua {
  constructor() {
    this.p = spawn(process.env.LUA || 'lua5.4', ['tests/ui/server.lua'], { cwd: RES });
    this.id = 0; this.wait = new Map(); this.buf = '';
    this.p.stdout.setEncoding('utf8');
    this.p.stdout.on('data', (d) => {
      this.buf += d;
      let i;
      while ((i = this.buf.indexOf('\n')) >= 0) {
        const line = this.buf.slice(0, i); this.buf = this.buf.slice(i + 1);
        if (!line.trim()) continue;
        const m = JSON.parse(line);
        const w = this.wait.get(m.id); this.wait.delete(m.id);
        if (!w) continue;
        if (m.error) w.reject(new Error(m.error)); else w.resolve(m.res);
      }
    });
    this.p.stderr.on('data', (d) => process.stderr.write(d));
  }
  call(op, args = {}) {
    return new Promise((resolve, reject) => {
      const id = ++this.id; this.wait.set(id, { resolve, reject });
      this.p.stdin.write(JSON.stringify({ id, op, ...args }) + '\n');
    });
  }
  stop() { this.p.stdin.end(); }
}

const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST, OPTIONS' };

async function actor(browser, lua, src, label) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'de-DE', timezoneId: 'Europe/Berlin' });
  const page = await ctx.newPage();
  page.label = label; page.src = src; page.errors = []; page.calls = []; page.external = [];
  /* Im Spiel gibt es keine Verbindung ins Internet: die Oberfläche darf nur eigene Dateien und den Server ansprechen. */
  page.on('request', (r) => { const u = r.url(); if (!u.startsWith('file:') && !u.startsWith('https://ic_behoerden/') && !u.startsWith('data:')) page.external.push(u); });
  page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) page.errors.push(`${label}: ${m.type()}: ${m.text()}`); });
  page.on('pageerror', (e) => page.errors.push(`${label}: PAGEERROR: ${e.message}`));
  await page.addInitScript(() => { window.GetParentResourceName = () => 'ic_behoerden'; });
  await page.route('https://ic_behoerden/**', async (route) => {
    const req = route.request();
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
    const name = new URL(req.url()).pathname.slice(1);
    let data = {};
    try { data = JSON.parse(req.postData() || '{}'); } catch (e) { /* leer */ }
    let res;
    if (name === 'close') res = (await lua.call('close', { src }), { ok: true });
    else { res = await lua.call('call', { src, name, data }); page.calls.push({ name, data, res }); }
    await route.fulfill({ status: 200, headers: CORS, contentType: 'application/json', body: JSON.stringify(res) });
  });
  await page.goto(INDEX);
  page.shot = (n) => SHOTS ? page.screenshot({ path: path.join(SHOTS, `${label}-${n}.png`), fullPage: true }) : null;
  page.settle = () => page.waitForTimeout(350);
  return page;
}

async function openApp(page, lua, app, index = 1) {
  const r = app === 'staff' ? await lua.call('staffOpen', { src: page.src }) : await lua.call('open', { src: page.src, app, index });
  assert(r.opened, `${page.label}: ${app} lässt sich nicht öffnen (${r.notice || 'kein Hinweis'})`);
  await page.evaluate((a) => window.postMessage({ action: 'open', app: a }, '*'), app);
  await page.waitForSelector('.win-body');
  await page.waitForFunction(() => window.IC && IC.S && IC.S.d && IC.S.d.ok);
}

module.exports = { Lua, actor, openApp, log, assert, RES };

if (require.main === module) {
  (async () => {
    const lua = new Lua();
    const browser = await chromium.launch();
    const pages = [];
    try {
      await require('./scenario')({ lua, browser, actor: (...a) => actor(browser, lua, ...a).then((p) => (pages.push(p), p)), openApp: (...a) => openApp(...a), log, assert });
    } catch (e) {
      console.error('E2E FEHLER:', e.stack || e.message);
      process.exitCode = 1;
    } finally {
      const errors = pages.flatMap((p) => p.errors.concat(p.external.map((u) => `${p.label}: Zugriff auf Fremdserver ${u}`)));
      if (errors.length) { console.error('\nKONSOLENFEHLER:\n' + errors.join('\n')); process.exitCode = 1; }
      await browser.close(); lua.stop();
    }
    if (!process.exitCode) console.log('\nE2E OK');
  })();
}
