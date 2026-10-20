/* IC-Behördenportal · Grundfunktionen
   Alles läuft ohne Build-Schritt und ohne externe Bibliotheken (NUI-tauglich). */
(function () {
  'use strict';
  const IC = (window.IC = window.IC || {});

  /* ---------- Sicheres HTML-Templating ----------
     Jeder interpolierte Wert wird escaped, außer er stammt aus html`` oder raw(). */
  class Safe {
    constructor(s) { this.s = s; }
    toString() { return this.s; }
  }
  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ESC[c]);
  function part(v) {
    if (v == null || v === false || v === true) return '';
    if (v instanceof Safe) return v.s;
    if (Array.isArray(v)) return v.map(part).join('');
    return esc(v);
  }
  function html(strings, ...vals) {
    let out = strings[0];
    for (let i = 0; i < vals.length; i++) out += part(vals[i]) + strings[i + 1];
    return new Safe(out);
  }
  const raw = (s) => new Safe(String(s));

  /* ---------- Zeit und Zahlen ---------- */
  const MIN = 60000, HOUR = 3600000, DAY = 86400000;
  /* Die Vorschau kann die Uhr vorspulen (Termine erreichen, Fristen ablaufen lassen). Im Spiel bleibt der Offset 0. */
  const clock = { offset: 0 };
  const now = () => Date.now() + clock.offset;
  const nfMoney = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 });
  const money = (n) => '$' + nfMoney.format(Math.round(n || 0));
  const pad = (n) => String(n).padStart(2, '0');
  const ftime = (ts) => { const d = new Date(ts); return pad(d.getHours()) + ':' + pad(d.getMinutes()); };
  const WD = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  const WDL = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
  const fdate = (ts) => { const d = new Date(ts); return pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.' + d.getFullYear(); };
  const fday = (ts) => { const d = new Date(ts); return WD[d.getDay()] + ', ' + pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.'; };
  const fdaylong = (ts) => { const d = new Date(ts); return WDL[d.getDay()] + ', ' + pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.' + d.getFullYear(); };
  const fdt = (ts) => fdate(ts) + ' · ' + ftime(ts);
  const startOfDay = (ts) => { const d = new Date(ts); d.setHours(0, 0, 0, 0); return d.getTime(); };
  function rel(ts, ref) {
    ref = ref || now();
    const d = ts - ref, a = Math.abs(d);
    let t;
    if (a < MIN) t = 'jetzt';
    else if (a < HOUR) t = Math.round(a / MIN) + ' Min.';
    else if (a < DAY) t = Math.round(a / HOUR) + ' Std.';
    else t = Math.round(a / DAY) + ' Tg.';
    if (t === 'jetzt') return t;
    return d >= 0 ? 'in ' + t : 'vor ' + t;
  }
  function dur(ms) {
    const a = Math.abs(ms);
    if (a < HOUR) return Math.max(1, Math.round(a / MIN)) + ' Min.';
    if (a < DAY) return Math.round(a / HOUR) + ' Std.';
    return Math.round(a / DAY) + ' Tg.';
  }
  const siteLabel = (p) => (!p ? '–' : p.mode === 'mobil' ? 'Ohne festen Standort' : (p.label || '–'));
  const initials = (name) => String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((s) => s[0].toUpperCase()).join('');
  const plural = (n, one, many) => (n === 1 ? one : many);
  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const clone = (o) => JSON.parse(JSON.stringify(o));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

  /* ---------- Pfadzugriff (data-bind="wiz.name") ---------- */
  function getPath(obj, path) {
    return String(path).split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
  }
  function setPath(obj, path, val) {
    const keys = String(path).split('.');
    let o = obj;
    for (let i = 0; i < keys.length - 1; i++) {
      if (o[keys[i]] == null || typeof o[keys[i]] !== 'object') o[keys[i]] = {};
      o = o[keys[i]];
    }
    o[keys[keys.length - 1]] = val;
  }

  /* ---------- Icons (Strichsymbole, 24er Raster) ---------- */
  const ICONS = {
    building: '<path d="M4 21V5l8-3 8 3v16"/><path d="M9 21v-5h6v5"/><path d="M8 9h2M14 9h2M8 13h2M14 13h2"/>',
    doc: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4"/><path d="M9 12h6M9 16h6"/>',
    users: '<circle cx="9" cy="8" r="3"/><path d="M3 20v-1a5 5 0 0 1 5-5h2a5 5 0 0 1 5 5v1"/><circle cx="17" cy="9" r="2.5"/><path d="M17 14a4 4 0 0 1 4 4v2"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="1"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    search: '<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>',
    shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
    coin: '<circle cx="12" cy="12" r="9"/><path d="M14.5 9.5c-.5-1-1.5-1.5-2.5-1.5-1.5 0-2.5.8-2.5 2s1 1.7 2.5 2 2.5.8 2.5 2-1 2-2.5 2c-1.1 0-2.1-.6-2.5-1.5M12 6v2M12 16v2"/>',
    pin: '<path d="M12 21s-6-5.5-6-11a6 6 0 0 1 12 0c0 5.5-6 11-6 11z"/><circle cx="12" cy="10" r="2.2"/>',
    bell: '<path d="M6 17v-6a6 6 0 0 1 12 0v6l1.5 2h-15z"/><path d="M10 21h4"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.01"/>',
    alert: '<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.01"/>',
    stamp: '<rect x="4" y="17" width="16" height="3"/><path d="M7 17c0-4 2-4 2-7a3 3 0 1 1 6 0c0 3 2 3 2 7"/>',
    list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="1"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    back: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    ticket: '<path d="M3 8a2 2 0 0 1 0 0V6h18v2a2 2 0 0 0 0 8v2H3v-2a2 2 0 0 0 0-8z"/><path d="M14 6v2M14 11v2M14 16v2"/>',
    folder: '<path d="M3 6h6l2 2h10v11H3z"/>',
    flag: '<path d="M5 21V4M5 5h12l-2 4 2 4H5"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
    book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5"/>',
    chart: '<path d="M4 20V4M4 20h16M8 16v-5M12 16V8M16 16v-3"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M16 7l3 3"/>',
    home: '<path d="M3 11l9-8 9 8M5 10v10h14V10"/>',
    refresh: '<path d="M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5"/>',
    moon: '<path d="M20 14A8 8 0 0 1 10 4a8 8 0 1 0 10 10z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
    chev: '<path d="M9 6l6 6-6 6"/>',
    play: '<path d="M7 4l13 8-13 8z"/>',
    pause: '<path d="M8 5v14M16 5v14"/>',
    phone: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
    scale: '<path d="M12 4v16M7 20h10M4 7h16"/><path d="M4 7l-2.5 6h5zM20 7l-2.5 6h5z"/>',
    badge: '<circle cx="12" cy="9" r="5"/><path d="M8.5 13L7 21l5-3 5 3-1.5-8"/>',
    tool: '<path d="M14 6a4 4 0 0 0 5 5l-9 9a2.1 2.1 0 0 1-3-3l9-9a4 4 0 0 0-2-2z"/>',
    layers: '<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="1"/><path d="M3 7l9 6 9-6"/>',
  };
  function ico(name, cls) {
    const body = ICONS[name] || ICONS.info;
    return raw('<svg class="ico' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + body + '</svg>');
  }

  /* ---------- DOM-Helfer ---------- */
  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  const lsGet = (k, d) => { try { const v = localStorage.getItem(k); return v == null ? d : v; } catch (e) { return d; } };
  const lsSet = (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* Speicher gesperrt, egal */ } };

  /* ---------- Namensregeln (identisch zum Server) ---------- */
  const UMLAUT = { 'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss', 'é': 'e', 'è': 'e', 'á': 'a', 'à': 'a', 'ó': 'o', 'ñ': 'n', 'ç': 'c' };
  const LEET = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's' };
  const FORM_SUFFIX = /\b(gmbh|gbr|ug|ag|e\.?\s?v\.?|ev|ohg|kg|eg|stiftung)\b\.?\s*$/i;
  function normName(name) {
    let s = String(name || '').toLowerCase().trim();
    s = s.replace(FORM_SUFFIX, '').trim();
    s = s.replace(/[äöüßéèáàóñç]/g, (c) => UMLAUT[c]);
    s = s.replace(/[013457@$]/g, (c) => LEET[c]);
    return s.replace(/[^a-z]/g, '');
  }
  function lev(a, b) {
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
    for (let i = 1; i <= a.length; i++) {
      const cur = [i];
      for (let j = 1; j <= b.length; j++) {
        cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  Object.assign(IC, {
    Safe, html, raw, esc, MIN, HOUR, DAY, clock, now, money, pad, ftime, fdate, fday, fdaylong, fdt, startOfDay, rel, dur,
    siteLabel, initials, plural, clamp, clone, sleep, debounce, getPath, setPath, ICONS, ico, $, $$, lsGet, lsSet, normName, lev,
  });
})();
