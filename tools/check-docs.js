#!/usr/bin/env node
/*
 * Prüft die Markdown-Dateien in docs/ und README.md: Zeigen alle relativen Links auf vorhandene Dateien,
 * und gibt es für jeden Anker (#abschnitt) eine passende Überschrift? Aufruf:  node tools/check-docs.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const files = [path.join(root, 'README.md')].concat(fs.readdirSync(path.join(root, 'docs')).filter((f) => f.endsWith('.md')).map((f) => path.join(root, 'docs', f)));

/* Anker wie bei GitHub: klein, ohne Satzzeichen, Leerzeichen zu Bindestrichen */
const slug = (h) => h.trim().toLowerCase().replace(/`/g, '').replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
const anchors = (md) => {
  const set = new Set();
  const seen = {};
  let inCode = false;
  md.split('\n').forEach((line) => {
    if (/^```/.test(line)) inCode = !inCode;
    const m = !inCode && /^#{1,6}\s+(.*)$/.exec(line);
    if (m) {
      let s = slug(m[1].replace(/\[([^\]]*)\]\([^)]*\)/g, '$1'));
      if (seen[s] != null) { seen[s]++; s += '-' + seen[s]; } else seen[s] = 0;
      set.add(s);
    }
  });
  return set;
};

let bad = 0;
for (const file of files) {
  const md = fs.readFileSync(file, 'utf8');
  const noCode = md.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
  for (const m of noCode.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
    const href = m[1];
    if (/^(https?:|mailto:|\[)/.test(href)) continue; /* Platzhalter wie [LINK] in den Vorlagen */
    const [rel, hash] = href.split('#');
    const target = rel ? path.resolve(path.dirname(file), rel) : file;
    if (!fs.existsSync(target)) { console.log(`${path.relative(root, file)}: Datei fehlt: ${href}`); bad++; continue; }
    if (hash && target.endsWith('.md') && !anchors(fs.readFileSync(target, 'utf8')).has(hash)) { console.log(`${path.relative(root, file)}: Anker fehlt: ${href}`); bad++; }
  }
}
console.log(bad ? `${bad} Problem(e)` : 'Alle Links und Anker stimmen (' + files.length + ' Dateien)');
process.exit(bad ? 1 : 0);
