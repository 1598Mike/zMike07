/* IC-Behördenportal · Wiederverwendbare Oberflächenbausteine */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico } = IC;
  const L = IC.L;
  const c = (IC.c = {});

  /* ---------- Kleinteile ---------- */
  c.chip = (text, kind, icon) => html`<span class="chip ${kind || ''}">${icon ? ico(icon) : ''}${text}</span>`;
  c.appChip = (status) => { const s = L.APP[status] || { label: status, kind: '' }; return c.chip(s.label, s.kind); };
  c.apptChip = (status) => { const s = L.APPT[status] || { label: status, kind: '' }; return c.chip(s.label, s.kind); };
  c.orgChip = (status) => { const s = L.ORG[status] || { label: status, kind: '' }; return c.chip(s.label, s.kind); };
  c.tag = (t) => html`<span class="tag">${t}</span>`;
  c.badge = (n, kind) => html`<span class="badge ${kind || ''}">${n}</span>`;
  c.avatar = (name) => html`<span class="avatar" aria-hidden="true">${IC.initials(name)}</span>`;

  c.callout = (kind, title, body, icon, actions) => {
    const dflt = { info: 'info', ok: 'check', warn: 'alert', bad: 'alert' }[kind] || 'info';
    return html`<div class="callout ${kind}">${ico(icon || dflt)}<div class="grow"><div class="t">${title}</div>${body ? html`<div>${body}</div>` : ''}${actions ? html`<div class="btn-row" style="margin-top:8px">${actions}</div>` : ''}</div></div>`;
  };

  c.sheet = (title, body, o) => {
    o = o || {};
    return html`<section class="sheet"${o.id ? raw(' id="' + o.id + '"') : ''}>
      <div class="sheet-h">${o.icon ? ico(o.icon) : ''}<h3>${title}</h3><span class="sp"></span>${o.actions || ''}</div>
      <div class="sheet-b${o.flush ? ' flush' : ''}">${body}</div>
      ${o.footer ? html`<div class="sheet-f">${o.footer}</div>` : ''}
    </section>`;
  };

  c.empty = (icon, title, text, action) => html`<div class="empty">${ico(icon)}<h3>${title}</h3>${text ? html`<p>${text}</p>` : ''}${action || ''}</div>`;

  c.kv = (pairs) => html`<dl class="kv">${pairs.filter(Boolean).map((p) => html`<dt>${p[0]}</dt><dd>${p[1]}</dd>`)}</dl>`;

  c.meter = (used, cap) => {
    const pct = cap ? Math.min(100, Math.round((used / cap) * 100)) : 100;
    const cls = used >= cap ? 'full' : used / cap >= 0.75 ? 'warn' : '';
    return html`<div class="meter ${cls}" role="img" aria-label="${used} von ${cap} belegt"><i style="width:${pct}%"></i></div>`;
  };

  c.stamp = (kind, word, anim) => html`<span class="stamp ${kind}${anim ? ' anim' : ''}">${word}</span>`;

  c.person = (p, right, meta) => html`<div class="person">${c.avatar(p.name)}<div class="grow"><div class="pn">${p.name}</div><div class="pm">${meta || ''}</div></div><div>${right || ''}</div></div>`;

  /* ---------- Zeitleiste und Phasen ---------- */
  const TL = {
    eingereicht: ['doc', ''], vorpruefung_ok: ['check', 'ok'], nachbesserung: ['edit', 'warn'], termin_gebucht: ['calendar', ''],
    termin_laeuft: ['users', ''], staff_pruefung: ['shield', ''], genehmigt: ['check', 'ok'], abgelehnt: ['x', 'bad'],
    einspruch: ['scale', 'warn'], zurueckgezogen: ['x', ''], abgelaufen: ['clock', ''],
  };
  c.timeline = (events, terminal) => {
    const list = events.slice().sort((a, b) => a.ts - b.ts);
    return html`<ol class="timeline">${list.map((e, i) => {
      const t = TL[e.status] || ['info', ''];
      const cur = i === list.length - 1 && !terminal ? ' cur' : '';
      return html`<li class="tl-item ${t[1]}${cur}"><span class="tl-dot">${ico(t[0])}</span><div>
        <div class="tl-t">${e.text}</div>
        <div class="tl-m">${e.actor} · ${IC.fdt(e.ts)}</div>
        ${e.note ? html`<div class="tl-n">${e.note}</div>` : ''}
      </div></li>`;
    })}</ol>`;
  };

  c.phases = (app) => {
    const st = L.APP[app.status] || { cur: 0 };
    return html`<div class="phases" role="img" aria-label="Fortschritt: ${(L.APP[app.status] || {}).label || ''}">${L.PHASES.map((name, i) => {
      let cls = '';
      if (st.neg && i === st.cur) cls = st.kind === 'bad' ? 'bad' : '';
      else if (i < st.cur) cls = 'done';
      else if (i === st.cur) cls = 'cur';
      return html`<div class="phase ${cls}"><i></i>${name}</div>`;
    })}</div>`;
  };

  /* ---------- Gewerbeschein / Urkunde ---------- */
  function checksum(str) {
    let h = 7;
    for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) % 1679616;
    return h.toString(36).toUpperCase().padStart(4, '0');
  }
  c.cert = (e, cfg) => {
    const f = cfg.legalForms.find((x) => x.key === e.legalForm) || { label: '' };
    const b = e.branch ? cfg.branches.find((x) => x.key === e.branch) : null;
    const isOrg = e.kind === 'fraktion';
    const st = { aktiv: ['blue', 'Eingetragen'], probezeit: ['blue', 'Probezeit'], ruhend: ['warn', 'Ruhend'], gesperrt: ['bad', 'Gesperrt'], aufgeloest: ['bad', 'Aufgelöst'] }[e.status] || ['blue', 'Eingetragen'];
    return html`<div class="cert">
      <svg class="seal" viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="32" cy="32" r="29"/><circle cx="32" cy="32" r="23" stroke-dasharray="2 3"/><path d="M32 14l4.2 9.2 10 1-7.5 6.7 2.2 9.9L32 35.4l-8.9 5.4 2.2-9.9-7.5-6.7 10-1z" fill="currentColor" stroke="none"/></svg>
      <div class="c-top">Stadt ${cfg.city} · Amt für Gewerbe und Bürgerservice</div>
      <div class="c-title">${isOrg ? 'Eintragungsurkunde' : 'Gewerbeschein'}</div>
      <div class="c-sub">${isOrg ? 'Die Organisation wurde in das Register eingetragen' : 'Das Gewerbe wurde angemeldet und in das Register eingetragen'}</div>
      <div class="c-name">${e.name}</div>
      <div class="c-grid">
        <div><b>Registernummer</b>${e.regNo}</div>
        <div><b>${isOrg ? 'Organisationsart' : 'Rechtsform'}</b>${f.label}</div>
        <div><b>${isOrg ? 'Vorstand' : 'Branche'}</b>${isOrg ? e.owner : (b ? b.label : '–')}</div>
        <div><b>${isOrg ? 'Vorsitz' : 'Vertretung'}</b>${e.owner}</div>
        <div><b>Sitz</b>${e.hq}</div>
        <div><b>Eingetragen am</b>${IC.fdate(e.founded)}</div>
        <div><b>${isOrg ? 'Prüfung bis' : 'Gültig bis'}</b>${IC.fdate(e.validUntil)}</div>
        <div><b>Prüfcode</b><span class="mono">${checksum(e.regNo + e.name)}</span></div>
      </div>
      <div class="c-foot"><div class="c-sign"><i>gez. ${e.signedBy || 'Registerführung'}</i>Gewerbeamt</div><div>Dieses Dokument ist im Register hinterlegt und kann dort anhand der Registernummer geprüft werden.</div></div>
      <div class="c-stamp">${c.stamp(st[0], st[1], false)}</div>
    </div>`;
  };

  /* ---------- Aufrufanzeige ---------- */
  c.board = (d) => {
    const calling = d.board && d.board.calling;
    const next = d.duty.nextFree;
    return html`<div class="board" role="status" aria-label="Aufrufanzeige">
      <div class="board-grid">
        <div><div class="lab">Beamte im Dienst</div><div class="big num ${d.duty.count ? '' : 'dim'}">${String(d.duty.count).padStart(2, '0')}</div></div>
        <div><div class="lab">Aufruf</div><div class="big num">${calling ? calling.no : '---'}</div><div class="lab">${calling ? 'Schalter ' + calling.desk : 'kein Aufruf'}</div></div>
        <div><div class="lab">Wartend</div><div class="big num ${d.board.waiting ? '' : 'dim'}">${String(d.board.waiting).padStart(2, '0')}</div></div>
      </div>
      <div class="board-sub">${d.duty.count ? html`Live-Termine für die nächsten 60 Minuten sind buchbar.` : html`Zurzeit niemand im Dienst.`} ${next ? html`Nächster freier Termin: <b>${IC.fday(next).split(',')[0] === IC.fday(IC.now()).split(',')[0] ? 'heute' : IC.fday(next)} ${IC.ftime(next)} Uhr</b>.` : html`<b>Kein Termin buchbar.</b>`}</div>
    </div>`;
  };

  /* ---------- Toast ---------- */
  IC.toast = function (text, kind) {
    let wrap = document.getElementById('toasts');
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.id = 'toasts';
      wrap.className = 'toasts';
      wrap.setAttribute('role', 'status');
      wrap.setAttribute('aria-live', 'polite');
      document.body.appendChild(wrap);
    }
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || '');
    el.innerHTML = String(html`${ico(kind === 'ok' ? 'check' : kind === 'bad' || kind === 'warn' ? 'alert' : 'info')}<div>${text}</div>`);
    wrap.appendChild(el);
    while (wrap.children.length > 4) wrap.removeChild(wrap.firstChild);
    setTimeout(() => { if (el.parentNode) el.parentNode.removeChild(el); }, kind === 'bad' ? 7000 : 4800);
  };

  /* ---------- Modal und Bestätigung ---------- */
  const modal = (IC.modal = { cur: null, resolve: null });
  modal.open = function (o) {
    modal.close(true);
    const ov = document.createElement('div');
    ov.className = 'modal-ov';
    ov.id = 'modal-ov';
    ov.innerHTML = String(html`<div class="modal${o.wide ? ' wide' : ''}" role="dialog" aria-modal="true" aria-labelledby="modal-title">
      <div class="modal-h">${o.icon ? ico(o.icon, 'lg') : ''}<h2 id="modal-title">${o.title}</h2><button class="btn ghost sm" data-act="modal-close" aria-label="Schließen">${ico('x')}</button></div>
      <div class="modal-b" id="modal-b">${o.body}</div>
      ${o.footer ? html`<div class="modal-f" id="modal-f">${o.footer}</div>` : ''}
    </div>`);
    document.body.appendChild(ov);
    modal.cur = o;
    const focusEl = ov.querySelector('[autofocus]') || ov.querySelector('textarea, input, select, .btn.primary, .btn');
    if (focusEl) setTimeout(() => focusEl.focus(), 30);
    if (o.onOpen) o.onOpen(ov);
  };
  modal.close = function (silent) {
    const ov = document.getElementById('modal-ov');
    if (ov && ov.parentNode) ov.parentNode.removeChild(ov);
    const cur = modal.cur, res = modal.resolve;
    modal.cur = null; modal.resolve = null;
    if (!silent && cur && cur.onClose) cur.onClose();
    if (res) res(false);
  };
  IC.confirm = function (o) {
    return new Promise((resolve) => {
      modal.open({
        title: o.title, icon: o.icon || 'alert',
        body: html`<div class="stack sm"><p>${o.text}</p>${o.extra || ''}</div>`,
        footer: html`<button class="btn" data-act="modal-close">${o.cancel || 'Abbrechen'}</button><button class="btn ${o.danger ? 'danger solid' : 'primary'}" data-act="modal-yes">${o.yes || 'Bestätigen'}</button>`,
      });
      modal.resolve = resolve;
    });
  };
  modal.yes = function () { const res = modal.resolve; modal.resolve = null; modal.close(true); if (res) res(true); };

  /* ---------- Formularhilfen ---------- */
  c.field = (id, label, control, o) => {
    o = o || {};
    return html`<div class="field"><label for="${id}">${label}${o.req ? html` <span class="muted">(Pflicht)</span>` : ''}</label>${control}${o.hint ? html`<div class="hint">${o.hint}</div>` : ''}${o.msg || ''}</div>`;
  };
  c.msg = (kind, text) => html`<div class="${kind === 'ok' ? 'okmsg' : kind === 'warn' ? 'warnmsg' : 'err'}">${ico(kind === 'ok' ? 'check' : 'alert')}<span>${text}</span></div>`;
  c.counter = (len, min) => html`<div class="counter ${len >= min ? 'ok' : ''}">${len} / mind. ${min} Zeichen</div>`;
})();
