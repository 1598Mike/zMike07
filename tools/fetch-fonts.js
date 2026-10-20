#!/usr/bin/env node
/*
 * Lädt die Schriften der Oberfläche von Google Fonts und legt sie in resources/ic_behoerden/web/fonts ab,
 * dazu die Stylesheet-Datei web/css/fonts.css. Damit braucht die Oberfläche im Spiel keine Verbindung zu Google
 * (Datenschutz, Ausfallsicherheit). Die Dateien sind im Repository enthalten, das Skript ist nur zum Aktualisieren gedacht.
 *
 *   node tools/fetch-fonts.js
 *
 * Es werden nur die Zeichen der Teilmenge "latin" geladen (Deutsch, Anführungszeichen, Euro). Alle Schriften stehen unter der SIL Open Font License.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

const web = path.resolve(__dirname, '..', 'resources', 'ic_behoerden', 'web');
const fontsDir = path.join(web, 'fonts');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

const FAMILIES = require('./fonts.json');

function get(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': UA } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) return resolve(get(res.headers.location));
      if (res.statusCode !== 200) return reject(new Error(res.statusCode + ' ' + url));
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

(async () => {
  fs.mkdirSync(fontsDir, { recursive: true });
  const blocks = [];
  const byHash = new Map(); /* Variable Schriften liefert Google je Schnitt als dieselbe Datei: nur einmal speichern */
  for (const fam of FAMILIES) {
    const css = (await get('https://fonts.googleapis.com/css2?' + fam + '&display=swap')).toString('utf8');
    const re = /\/\*\s*([\w-]+)\s*\*\/\s*(@font-face\s*\{[^}]*\})/g;
    let m;
    while ((m = re.exec(css))) {
      if (m[1] !== 'latin') continue;
      let block = m[2];
      const family = /font-family:\s*'([^']+)'/.exec(block)[1];
      const style = /font-style:\s*(\w+)/.exec(block)[1];
      const weight = /font-weight:\s*([\d ]+)/.exec(block)[1].trim().replace(/\s+/g, '-');
      const url = /url\((https:[^)]+\.woff2)\)/.exec(block)[1];
      const data = await get(url);
      const hash = crypto.createHash('md5').update(data).digest('hex');
      let file = byHash.get(hash);
      if (!file) {
        file = family.toLowerCase().replace(/\s+/g, '-') + '-' + style + '-' + weight + '.woff2';
        byHash.set(hash, file);
        fs.writeFileSync(path.join(fontsDir, file), data);
        console.log('geladen: ' + file);
      }
      block = block.replace(url, '../fonts/' + file);
      blocks.push(block);
    }
  }
  const header = '/* Von tools/fetch-fonts.js erzeugt. Schriften: Barlow, Barlow Semi Condensed, IBM Plex Mono, Source Serif 4, Doto (SIL Open Font License, siehe fonts/LICENSE.txt). */\n';
  fs.writeFileSync(path.join(web, 'css', 'fonts.css'), header + blocks.join('\n') + '\n');
  console.log('geschrieben: web/css/fonts.css (' + blocks.length + ' Schriftschnitte)');
})().catch((e) => { console.error('Fehler:', e.message); process.exit(1); });
