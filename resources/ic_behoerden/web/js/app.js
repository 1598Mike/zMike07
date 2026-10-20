/* IC-Behördenportal · App-Hülle: Zustand, Rendering, Ereignisse, Vorschauleiste */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico } = IC;
  const L = IC.L;

  const S = (IC.S = {
    env: { nui: typeof window.GetParentResourceName === 'function' },
    app: 'gewerbeamt',
    nav: {},
    d: null,
    ui: {},
    busy: false,
    theme: null,
    open: true,
    guideOpen: IC.lsGet('ic.guide', '1') === '1',
    seenNotice: null,
    err: null,
  });
  IC.apps = {};
  IC.act = {};
  IC.partials = {};
  IC.registerApp = (key, def) => { IC.apps[key] = def; S.nav[key] = def.def; };

  const ORDER = [
    ['gewerbeamt', 'Gewerbeamt', 'building'],
    ['buergeramt', 'Bürgeramt', 'calendar'],
    ['beamte', 'Beamten-Tablet', 'stamp'],
    ['staff', 'Staff-Panel', 'shield'],
    ['konzept', 'Konzept', 'book'],
  ];

  /* ---------- Server-Aufrufe ---------- */
  IC.api = async function (name, data) {
    if (S.env.nui) {
      try {
        const res = await fetch('https://' + window.GetParentResourceName() + '/' + name, {
          method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}),
        });
        return await res.json();
      } catch (err) { return { ok: false, error: 'Keine Verbindung zum Server.' }; }
    }
    return IC.mock.handle(name, data);
  };

  /* Aufruf mit Rückmeldung und anschließendem Neuladen */
  IC.run = async function (name, data, o) {
    o = o || {};
    S.busy = true;
    let r;
    try { r = await IC.api(name, data); } finally { S.busy = false; }
    if (!r || !r.ok) {
      IC.toast((r && r.error) || 'Das hat nicht geklappt.', 'bad');
      if (o.render) render();
      return r || { ok: false };
    }
    if (o.ok) IC.toast(typeof o.ok === 'function' ? o.ok(r) : o.ok, 'ok');
    if (!o.noReload) await IC.reload();
    return r;
  };

  IC.reload = async function () {
    const d = await IC.api('bootstrap', { app: S.app });
    if (d && d.ok) {
      S.d = d; S.err = null;
      const ids = d.notices.map((n) => n.id);
      if (S.seenNotice == null) S.seenNotice = ids.length ? Math.max.apply(null, ids) : 0;
      d.notices.filter((n) => n.id > S.seenNotice).forEach((n) => {
        const away = S.app === 'beamte' || S.app === 'staff';
        IC.toast((away ? 'Benachrichtigung an ' + d.me.name + ': ' : '') + n.text, n.kind === 'ok' ? 'ok' : n.kind === 'bad' ? 'bad' : n.kind === 'warn' ? 'warn' : '');
        S.seenNotice = Math.max(S.seenNotice, n.id);
      });
    } else S.err = (d && d.error) || 'Keine Verbindung zum Server.';
    render();
  };

  /* Abgeschlossene Abläufe (Buchung, Gründung) zeigen beim erneuten Öffnen ein frisches Formular */
  function resetFinished(view) {
    if (view === 'book' && S.ui.book && S.ui.book.done) S.ui.book = null;
    if (view === 'wizard' && S.ui.wiz && S.ui.wiz.done) S.ui.wiz = null;
  }

  IC.go = async function (app, view) {
    IC.modal.close(true);
    const changed = app && app !== S.app;
    if (app) S.app = app;
    if (view) S.nav[S.app] = view;
    resetFinished(S.nav[S.app]);
    try { history.replaceState(null, '', '#' + S.app); } catch (e) { /* in Sandbox nicht möglich */ }
    if (changed) { S.d = null; render(); }
    await IC.reload();
  };
  IC.view = (view) => { resetFinished(view); S.nav[S.app] = view; render(); };

  IC.refresh = function () {
    Array.prototype.forEach.call(arguments, (name) => {
      const fn = IC.partials[name];
      if (!fn) return;
      document.querySelectorAll('[data-partial="' + name + '"]').forEach((el) => { el.innerHTML = String(fn()); });
    });
  };

  /* ---------- Theme ---------- */
  function effectiveTheme() {
    return document.documentElement.getAttribute('data-theme') || (window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  }
  function applyTheme() { if (S.theme) document.documentElement.setAttribute('data-theme', S.theme); }

  /* ---------- Vorschauleiste und Rundgang ---------- */
  function previewBar() {
    const d = S.d;
    const others = d ? d.duty.othersSetting : 1;
    const eff = effectiveTheme();
    const off = IC.clock.offset;
    return html`<header class="pv-bar"><div class="pv-in">
      <div class="pv-brand">${ico('building')}<span>IC-Behördenportal</span><span class="pv-tag">VORSCHAU</span></div>
      <nav class="pv-tabs" aria-label="Perspektive wählen">${ORDER.map((o) => html`<button class="pv-tab" data-act="go" data-app="${o[0]}" ${S.app === o[0] ? raw('aria-current="page"') : ''}>${ico(o[2])}${o[1]}</button>`)}</nav>
      <div class="pv-ctl">
        <label id="pv-others-l">Kollegen im Dienst</label>
        <div class="pv-step" role="group" aria-labelledby="pv-others-l">
          <button data-act="pv-others" data-n="-1" aria-label="Einen Beamten weniger" ${others <= 0 ? raw('disabled') : ''}>−</button>
          <output>${others}</output>
          <button data-act="pv-others" data-n="1" aria-label="Einen Beamten mehr" ${others >= 3 ? raw('disabled') : ''}>+</button>
        </div>
        <button class="pv-ico-btn" data-act="pv-advance" data-m="30" title="Simulierte Uhr um 30 Minuten vorstellen">${ico('clock')}+30 Min${off ? html` <span class="mono">(+${Math.round(off / IC.MIN)})</span>` : ''}</button>
        ${S.guideOpen ? '' : html`<button class="pv-ico-btn" data-act="pv-guide" title="Rundgang einblenden">${ico('list')}Rundgang</button>`}
        <button class="pv-ico-btn" data-act="pv-theme" title="Hell oder dunkel">${ico(eff === 'dark' ? 'sun' : 'moon')}${eff === 'dark' ? 'Hell' : 'Dunkel'}</button>
        <button class="pv-ico-btn" data-act="pv-reset" title="Demo-Daten zurücksetzen">${ico('refresh')}Zurücksetzen</button>
      </div>
    </div></header>`;
  }

  const GUIDE = [
    ['gewerbeamt', 'wizard', 'Antrag stellen', 'Als Gründerin Lena im Gewerbeamt einen Antrag in 6 Schritten ausfüllen und einreichen.'],
    ['beamte', 'reviews', 'Vorprüfung', 'Als Beamter in den Dienst gehen und den neuen Antrag in der Vorprüfung freigeben.'],
    ['buergeramt', 'book', 'Termin buchen', 'Im Bürgeramt einen Vorstellungstermin buchen. Mit 0 Kollegen im Dienst gibt es nur Sprechzeiten.'],
    ['buergeramt', 'appts', 'Einchecken', 'Zum Termin einchecken. Mit „+30 Min“ lässt sich die Uhr vorstellen, falls der Termin noch nicht begonnen hat.'],
    ['beamte', 'today', 'Vorstellen und entscheiden', 'Als Beamter aufrufen, Termin starten, Checkliste abarbeiten, entscheiden und stempeln.'],
    ['gewerbeamt', 'entities', 'Eintragung ansehen', 'Das neue Unternehmen erscheint mit Gewerbeschein unter „Meine Eintragungen“.'],
    ['staff', 'gate', 'Staff-Sicht', 'Schlussprüfung, Kapazitäten, Sperrliste und Eskalationen. Hier wartet bereits ein Antrag auf Freigabe.'],
  ];
  function guide() {
    if (!S.guideOpen) return '';
    const cur = GUIDE.findIndex((g) => g[0] === S.app && g[1] === S.nav[S.app]);
    const hint = cur >= 0 ? GUIDE[cur][3] : 'Die Schritte führen durch den kompletten Ablauf. Jeder Schritt springt in die passende Ansicht.';
    return html`<div class="pv-guide"><section class="guide" aria-label="Rundgang durch den Ablauf">
      <div class="guide-steps"><span class="guide-lab">Rundgang</span>${GUIDE.map((g, i) => html`<button class="gstep" data-act="go" data-app="${g[0]}" data-view="${g[1]}" ${cur === i ? raw('aria-current="step"') : ''}><span class="gn">${i + 1}</span>${g[2]}</button>`)}<button class="btn ghost sm" style="margin-left:auto" data-act="pv-guide" aria-label="Rundgang ausblenden">${ico('x')}</button></div>
      <p class="guide-hint">${ico('info')}<span>${hint}</span></p>
    </section></div>`;
  }

  /* ---------- Hülle ---------- */
  function whoChip() {
    const d = S.d;
    if (!d) return '';
    if (S.app === 'gewerbeamt' || S.app === 'buergeramt') return html`<span class="who">${ico('user')}${d.me.name}${S.app === 'gewerbeamt' ? html` · ${IC.money(d.me.bank)}` : ''}</span>`;
    if (S.app === 'beamte' && d.official) return html`<span class="who">${ico('badge')}${d.official.name} · ${L.RANK[d.official.rank].label}</span>`;
    if (S.app === 'staff') return html`<span class="who">${ico('shield')}Staff · OOC</span>`;
    return '';
  }

  function shell() {
    const A = IC.apps[S.app];
    const nui = S.env.nui;
    const view = S.nav[S.app];
    let nav = [], body;
    if (S.err) body = IC.c.callout('bad', 'Verbindung gestört', S.err);
    else if (S.app === 'konzept') { nav = A.nav(); body = A.views[view](); }
    else if (!S.d) body = html`<div class="empty">${ico('clock')}<h3>Verbindung zum Amtsserver …</h3></div>`;
    else { nav = A.nav(); body = A.views[view] ? A.views[view]() : ''; }
    return html`
      ${nui ? '' : previewBar()}
      ${nui ? '' : guide()}
      <main class="stage">
        <div class="win" role="application" aria-label="${A.title}">
          <div class="win-title">${ico(A.icon)}<span>${A.title}</span><span class="where">${S.d ? A.where() : ''}</span><span class="sp"></span>${whoChip()}<span class="clock">${IC.ftime(IC.now())}</span>${nui ? html`<button class="x" data-act="nui-close" aria-label="Schließen">${ico('x')}</button>` : ''}</div>
          <div class="win-body">
            <nav class="rail" aria-label="Bereiche">
              ${nav.map((n) => n.head ? html`<h4>${n.head}</h4>` : html`<button class="rail-item" data-act="view" data-view="${n.id}" ${view === n.id ? raw('aria-current="page"') : ''}>${ico(n.icon)}<span>${n.label}</span>${n.badge ? IC.c.badge(n.badge, n.badgeKind) : ''}</button>`)}
              ${A.railFoot && S.d ? html`<div class="rail-foot">${A.railFoot()}</div>` : ''}
            </nav>
            <div class="main" id="main">${body}</div>
          </div>
        </div>
      </main>`;
  }

  let lastKey = '';
  function render() {
    const root = document.getElementById('root');
    if (S.env.nui && !S.open) { root.innerHTML = ''; return; }
    const main = document.getElementById('main');
    const mt = main ? main.scrollTop : 0;
    const wy = window.scrollY;
    const key = S.app + ':' + S.nav[S.app];
    const active = document.activeElement;
    const focusId = active && active.id && root.contains(active) ? active.id : null;
    const sel = focusId && active.selectionStart != null ? [active.selectionStart, active.selectionEnd] : null;
    root.innerHTML = String(shell());
    if (key === lastKey) {
      const m = document.getElementById('main');
      if (m) m.scrollTop = mt;
      window.scrollTo(0, wy);
    } else {
      const st = document.querySelector('.stage');
      if (st && window.scrollY > st.offsetTop - 70) window.scrollTo(0, Math.max(0, st.offsetTop - 70));
    }
    lastKey = key;
    const cb = IC.afterQueue; IC.afterQueue = [];
    cb.forEach((fn) => { try { fn(); } catch (err) { console.error(err); } });
    if (focusId) {
      const el = document.getElementById(focusId);
      if (el) { el.focus(); if (sel && el.setSelectionRange) try { el.setSelectionRange(sel[0], sel[1]); } catch (e) { /* Typ ohne Auswahl */ } }
    }
  }
  IC.render = render;
  IC.afterQueue = [];
  IC.after = (fn) => { IC.afterQueue.push(fn); };

  /* ---------- Gemeinsame Aktionen ---------- */
  Object.assign(IC.act, {
    go: (el) => IC.go(el.dataset.app, el.dataset.view),
    view: (el) => IC.view(el.dataset.view),
    'modal-close': () => IC.modal.close(),
    'modal-yes': () => IC.modal.yes(),
    'nui-close': () => IC.api('close', {}),
    'pv-others': async (el) => {
      const cur = S.d ? S.d.duty.othersSetting : 1;
      await IC.api('pvSetOfficials', { n: cur + Number(el.dataset.n) });
      await IC.reload();
    },
    'pv-advance': async (el) => {
      await IC.api('pvAdvance', { minutes: Number(el.dataset.m) });
      IC.toast('Uhr um ' + el.dataset.m + ' Minuten vorgestellt: ' + IC.ftime(IC.now()) + ' Uhr.', '');
      await IC.reload();
    },
    'pv-guide': () => { S.guideOpen = !S.guideOpen; IC.lsSet('ic.guide', S.guideOpen ? '1' : '0'); render(); },
    'pv-theme': () => {
      S.theme = effectiveTheme() === 'dark' ? 'light' : 'dark';
      IC.lsSet('ic.theme', S.theme);
      applyTheme();
      render();
    },
    'pv-reset': async () => {
      await IC.api('pvReset', {});
      S.ui = {}; S.seenNotice = null;
      IC.toast('Demo-Daten zurückgesetzt.', 'ok');
      await IC.reload();
    },
  });

  /* ---------- Ereignisse ---------- */
  document.addEventListener('click', (e) => {
    if (e.target && e.target.id === 'modal-ov') { IC.modal.close(); return; }
    const el = e.target.closest ? e.target.closest('[data-act]') : null;
    if (!el || el.disabled || el.getAttribute('aria-disabled') === 'true') return;
    const fn = IC.act[el.dataset.act];
    if (!fn || S.busy) return;
    if (el.tagName !== 'INPUT') e.preventDefault();
    Promise.resolve(fn(el, e)).catch((err) => { console.error(err); IC.toast('Unerwarteter Fehler: ' + err.message, 'bad'); S.busy = false; });
  });
  document.addEventListener('input', (e) => {
    const el = e.target;
    const path = el.dataset && el.dataset.bind;
    if (!path) return;
    let v;
    if (el.type === 'checkbox') v = el.checked;
    else if (el.type === 'number') v = el.value === '' ? '' : Number(el.value);
    else v = el.value;
    IC.setPath(S, path, v);
    const after = el.dataset.after;
    if (after && IC.act[after]) IC.act[after](el, e);
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (IC.modal.cur) { e.preventDefault(); IC.modal.close(); }
      else if (S.env.nui && S.open) IC.api('close', {});
    }
  });
  window.addEventListener('hashchange', () => {
    const h = location.hash.replace('#', '');
    if (IC.apps[h] && h !== S.app) IC.go(h);
  });
  window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.action === 'open') {
      S.open = true; S.app = IC.apps[m.app] ? m.app : 'gewerbeamt';
      if (m.view) S.nav[S.app] = m.view;
      S.d = null; render(); IC.reload();
    } else if (m.action === 'close') { S.open = false; IC.modal.close(true); render(); }
    else if (m.action === 'notify') IC.toast(m.text, m.kind);
    else if (m.action === 'refresh' && S.open) IC.reload();
  });

  /* ---------- Start ---------- */
  IC.boot = async function () {
    document.documentElement.classList.toggle('nui', S.env.nui);
    const saved = IC.lsGet('ic.theme', null);
    if (saved === 'light' || saved === 'dark') { S.theme = saved; applyTheme(); }
    if (S.env.nui) { S.open = false; render(); return; }
    const h = location.hash.replace('#', '');
    if (IC.apps[h]) S.app = h;
    render();
    await IC.reload();
  };
})();
