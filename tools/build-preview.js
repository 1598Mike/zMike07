#!/usr/bin/env node
/*
 * Bündelt die Oberfläche (resources/ic_behoerden/web) zu einer einzelnen HTML-Datei.
 *
 *   node tools/build-preview.js              -> vorschau/ic-behoerden-vorschau.html (vollständiges Dokument, per Doppelklick öffnen)
 *   node tools/build-preview.js --fragment   -> vorschau/ic-behoerden-vorschau.fragment.html (ohne html/head/body, zum Veröffentlichen)
 *
 * Es sind keine Abhängigkeiten nötig, nur Node 16 oder neuer.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const web = path.join(root, 'resources', 'ic_behoerden', 'web');
const outDir = path.join(root, 'vorschau');
const fragment = process.argv.includes('--fragment');

const index = fs.readFileSync(path.join(web, 'index.html'), 'utf8');

const css = fs.readFileSync(path.join(web, 'css', 'app.css'), 'utf8');
const scripts = [...index.matchAll(/<script src="(js\/[^"]+)"><\/script>/g)].map((m) => m[1]);
if (!scripts.length) throw new Error('Keine Skripte in index.html gefunden.');
const js = scripts
  .map((rel) => '/* ' + rel + ' */\n' + fs.readFileSync(path.join(web, rel), 'utf8'))
  .join('\n')
  .replace(/<\/script/gi, '<\\/script');
/* Die Vorschau lädt die Schriften von Google Fonts. Im Spiel liegen sie lokal in web/fonts (tools/fetch-fonts.js). */
const fontLinks = require('./fonts.json')
  .map((f) => '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?' + f + '&display=swap">')
  .join('\n');
const title = (index.match(/<title>([^<]+)<\/title>/) || [, 'IC-Behördenportal'])[1];

let out;
if (fragment) {
  /* Die Veröffentlichungsumgebung ergänzt Doctype, head und body selbst. */
  out = [
    '<title>' + title + '</title>',
    '<meta name="claude:viewport-fit-sides" content="cover">',
    fontLinks,
    '<style>\n' + css + '\n</style>',
    '<div id="root"></div>',
    '<script>\n' + js + '\nIC.boot();\n</script>',
    '',
  ].join('\n');
} else {
  out = [
    '<!doctype html>',
    '<html lang="de">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
    '<title>' + title + '</title>',
    fontLinks,
    '<style>\n' + css + '\n</style>',
    '</head>',
    '<body>',
    '<div id="root"></div>',
    '<script>\n' + js + '\nIC.boot();\n</script>',
    '</body>',
    '</html>',
    '',
  ].join('\n');
}

fs.mkdirSync(outDir, { recursive: true });
const name = fragment ? 'ic-behoerden-vorschau.fragment.html' : 'ic-behoerden-vorschau.html';
fs.writeFileSync(path.join(outDir, name), out);
console.log('geschrieben: vorschau/' + name + ' (' + Math.round(out.length / 1024) + ' KB)');
