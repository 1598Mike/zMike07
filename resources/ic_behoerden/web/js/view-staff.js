/* IC-Behördenportal · Staff-Panel (OOC): Schlussprüfung, Kapazitäten, Sperrliste, Audit */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico, money } = IC;
  const c = IC.c, L = IC.L, S = IC.S;
  const cfg = () => S.d.config;
  const ST = () => S.d.staff;
  const formOf = (k) => cfg().legalForms.find((f) => f.key === k);
  const branchOf = (k) => cfg().branches.find((b) => b.key === k);
  const pressed = (cond) => raw('aria-pressed="' + (cond ? 'true' : 'false') + '"');
  const oocBadge = html`<span class="ooc-label" style="margin:0">${ico('lock')}OOC · nur Staff</span>`;

  function kpi(label, value, sub, kind) {
    return html`<div class="kpi"><div class="kl">${label}</div><div class="kv2 ${kind || ''}" style="${kind === 'bad' ? 'color:var(--bad)' : kind === 'warn' ? 'color:var(--warn)' : ''}">${value}</div><div class="ks">${sub}</div></div>`;
  }

  /* ---------- Übersicht ---------- */
  function overview() {
    const k = ST().kpi;
    const apps = ST().applicationsAll;
    const byStatus = {};
    apps.forEach((a) => { byStatus[a.status] = (byStatus[a.status] || 0) + 1; });
    const stat = L.OPEN_APP.map((s) => [s, byStatus[s] || 0]);
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Übersicht</div><h1>Übersicht</h1><p class="sub">Der Staff greift ein, wenn Regeln verletzt werden oder Kapazitäten ausgeschöpft sind, nicht weil ein Konzept nicht gefällt.</p></div>
        <div class="row sm">${oocBadge}<span class="chip">${ico('coin')}Stadtkasse ${money(k.treasury)}</span></div></div>
      <div class="grid g4">
        ${kpi('Offene Anträge', k.open, 'in allen Phasen')}
        ${kpi('Schlussprüfung', k.gate, k.gate ? 'warten auf Ihre Freigabe' : 'nichts offen', k.gate ? 'warn' : '')}
        ${kpi('Eskalationen', k.escalations, 'über ' + cfg().rules.escalateHours + ' Std. ohne Termin', k.escalations ? 'bad' : '')}
        ${kpi('Beamte im Dienst', k.onDuty, 'Ziel: mindestens 4 Std. pro Tag besetzt', k.onDuty ? '' : 'warn')}
        ${kpi('Durchlaufzeit', String(k.throughputDays).replace('.', ',') + ' Tg.', 'Einreichung bis Eintragung, Ziel ≤ 7 Tage')}
        ${kpi('Ablehnungsquote', k.rejectionRate + ' %', 'Ziel: 10 bis 25 %')}
        ${kpi('No-Show-Quote', k.noShowRate + ' %', 'Ziel: höchstens 10 %')}
        ${kpi('Beamten-Ausfälle', k.outageRate + ' %', 'Ziel: höchstens 5 %')}
      </div>
      <p class="small muted">${S.env.nui ? 'Quoten und Durchlaufzeit werden aus den abgeschlossenen Vorgängen berechnet. Mit wenigen Vorgängen schwanken sie stark.' : 'Quoten und Durchlaufzeit sind in der Vorschau Beispielwerte, bis genug abgeschlossene Vorgänge vorliegen.'}</p>
      <div class="grid g2">
        ${c.sheet('Offene Vorgänge nach Status', html`<div class="tbl-wrap"><table class="tbl"><tbody>${stat.map((x) => html`<tr><td>${c.appChip(x[0])}</td><td class="right num strong">${x[1]}</td></tr>`)}</tbody></table></div>`, { icon: 'chart', flush: true })}
        ${c.sheet('Zuletzt im Protokoll', html`<div class="tbl-wrap"><table class="tbl"><tbody>${ST().audit.slice(0, 6).map((a) => html`<tr><td class="nowrap muted small">${IC.ftime(a.ts)}</td><td><span class="strong">${a.action}</span> <span class="muted">${a.target}</span><div class="sub">${a.actor}</div></td></tr>`)}</tbody></table></div>`, { icon: 'list', flush: true })}
      </div>`;
  }

  /* ---------- Schlussprüfung ---------- */
  function gate() {
    const list = ST().gate;
    const uc = ST().undergroundCap;
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Schlussprüfung</div><h1>Freigaben</h1><p class="sub">Nach der IC-Genehmigung durch die Beamten prüfen Sie OOC-Kriterien: Konzept, Mitgliederzahl, Kapazität. Die Gründer sehen dies IC als „Schlussprüfung der Registerführung“.</p></div>${oocBadge}</div>
      ${list.length ? list.map((a) => {
        const f = formOf(a.legalForm), b = a.branch ? branchOf(a.branch) : null;
        const under = a.ooc && a.ooc.category === 'untergrund';
        return html`<article class="sheet"><div class="sheet-h">${ico('shield')}<h3>${a.caseNo}</h3><span class="sp"></span>${c.appChip(a.status)}</div>
          <div class="sheet-b stack">
            <div><h2>${a.name}</h2><p class="muted small">${f.label}${b ? ' · ' + b.label : ''} · Antragsteller ${a.applicant.name}</p></div>
            <div class="grid g2">
              <div class="stack sm"><h4>IC-Entscheidung</h4>${c.kv([['Beamter', a.decision ? a.decision.by : '–'], ['Begründung', a.decision ? a.decision.reason : '–'], ['Gründer', a.founders.map((x) => x.name).join(', ')], ['Sitz', IC.siteLabel(a.property)]])}</div>
              <div class="ooc"><div class="ooc-label">${ico('lock')}OOC-Angaben der Gründer</div>${a.ooc ? c.kv([['Fraktionsart', under ? c.chip('Untergrund', 'bad') : c.chip('Legal', 'ok')], ['Konzept', a.ooc.note || '–'], ['Mitglieder', a.ooc.members || '–']]) : html`<p class="small muted">Branche mit Staff-Gate: ${b ? b.label : ''}. Keine OOC-Angaben nötig.</p>`}</div>
            </div>
            <div class="grid g2">
              <div class="stack sm"><h4>Kapazität</h4>${under ? html`${c.meter(uc.used, uc.max)}<span class="small ${uc.used >= uc.max ? '' : 'muted'}">${uc.used} von ${uc.max} Untergrund-Plätzen belegt${uc.used >= uc.max ? '. Keine Plätze frei, Warteliste.' : '.'}</span>` : b ? html`${c.meter(b.used, b.cap)}<span class="small muted">${b.used} von ${b.cap} Plätzen in ${b.label} belegt.</span>` : html`<span class="small muted">Keine Kapazitätsgrenze.</span>`}</div>
              <div class="stack sm"><h4>Hinweise</h4><ul class="checklist">${['Spielzeit der Gründer erfüllt die Voraussetzung', 'Keine Mehrfach-Gründer-Verknüpfung gefunden', 'Name steht nicht auf der Sperrliste'].map((t) => html`<li><label style="cursor:default;padding:5px 4px"><span class="chip ok">${ico('check')}</span><span>${t}</span></label></li>`)}</ul></div>
            </div>
          </div>
          <div class="sheet-f"><button class="btn danger" data-act="gate-back" data-id="${a.id}">Zurückweisen</button><button class="btn ok" data-act="gate-ok" data-id="${a.id}">${ico('check')}Freigeben und eintragen</button></div>
        </article>`;
      }) : c.sheet('Freigaben', c.empty('check', 'Nichts zu prüfen', 'Genehmigte Anträge mit Staff-Gate erscheinen hier.'))}`;
  }

  /* ---------- Eskalationen ---------- */
  function esc() {
    const list = ST().escalations;
    const on = ST().settings.writtenProcedure;
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Notfallregel</div><h1>Eskalationen</h1><p class="sub">Anträge, die seit über ${cfg().rules.escalateHours} Stunden nach bestandener Vorprüfung auf einen Termin warten. Im schriftlichen Verfahren lässt sich nach Aktenlage entscheiden.</p></div>${oocBadge}</div>
      ${on ? '' : c.callout('warn', 'Schriftliches Verfahren abgeschaltet', 'Unter „Einstellungen“ lässt es sich einschalten.', 'lock')}
      ${c.sheet('Überfällige Anträge', list.length ? html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Aktenzeichen</th><th>Name</th><th>Wartet seit</th><th></th></tr></thead><tbody>${list.map((a) => html`<tr><td>${c.tag(a.caseNo)}</td><td><div class="strong">${a.name}</div><div class="sub">${a.applicant.name}</div></td><td>${IC.dur(IC.now() - (a.vorpruefungAt || a.submittedAt))} ${c.chip('Eskalation', 'bad')}</td><td class="act"><button class="btn sm primary" data-act="esc-open" data-id="${a.id}" ${on ? '' : raw('disabled')}>Nach Aktenlage entscheiden</button></td></tr>`)}</tbody></table></div>` : c.empty('check', 'Keine Eskalationen', 'Alle Anträge mit bestandener Vorprüfung haben einen Termin oder sind noch in der Frist.'), { icon: 'clock', flush: !!list.length })}`;
  }

  /* ---------- Kapazitäten ---------- */
  function caps() {
    const uc = ST().undergroundCap;
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Kapazitäten</div><h1>Kapazitäten</h1><p class="sub">Höchstzahl gleichzeitig aktiver Unternehmen je Branche. Freie Plätze sind für Gründer im Terminal sichtbar.</p></div>${oocBadge}</div>
      ${c.sheet('Branchen', html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Branche</th><th>Belegung</th><th class="right">Kapazität</th></tr></thead><tbody>${ST().caps.map((x) => html`<tr><td class="strong">${x.label}</td><td style="min-width:200px">${c.meter(x.used, x.cap)}<span class="xs muted">${x.used} von ${x.cap} belegt${x.used >= x.cap ? ', ausgelastet' : ''}</span></td>
        <td class="act"><div class="row sm" style="justify-content:flex-end"><button class="btn sm" data-act="cap-step" data-key="${x.key}" data-d="-1" aria-label="Kapazität von ${x.label} verringern">${ico('minus')}</button><output class="mono strong" style="min-width:30px;text-align:center">${x.cap}</output><button class="btn sm" data-act="cap-step" data-key="${x.key}" data-d="1" aria-label="Kapazität von ${x.label} erhöhen">${ico('plus')}</button></div></td></tr>`)}</tbody></table></div>`, { icon: 'layers', flush: true })}
      ${c.sheet('Untergrund-Fraktionen', html`<div class="stack sm">${c.meter(uc.used, uc.max)}<span class="small muted">${uc.used} von ${uc.max} Plätzen belegt. Sind alle Plätze belegt, bleiben neue Untergrund-Anträge in der Schlussprüfung und kommen auf die Warteliste.</span></div>`, { icon: 'flag' })}`;
  }

  /* ---------- Sperrliste und Namenstest ---------- */
  IC.partials['name-test'] = function () {
    const r = S.ui.nt;
    if (!r) return html`<div class="hint">Geben Sie einen Namen ein, um ihn gegen Sperrliste, Register und laufende Anträge zu prüfen.</div>`;
    return html`${r.ok ? c.msg('ok', 'Der Name wäre zulässig: ' + r.display) : ''}${r.issues.map((i) => c.msg(i.level === 'error' ? 'bad' : 'warn', i.text))}`;
  };
  function black() {
    const list = ST().blacklist;
    S.ui.bl = S.ui.bl || { term: '', reason: '' };
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Namensrecht</div><h1>Sperrliste</h1><p class="sub">Gesperrte Begriffe werden bei der Namensprüfung automatisch abgelehnt. Die Prüfung ignoriert Groß- und Kleinschreibung, Umlaute und Leetspeak.</p></div>${oocBadge}</div>
      <div class="split" style="grid-template-columns:minmax(0,1fr) 340px">
        ${c.sheet('Gesperrte Begriffe', html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Begriff</th><th>Grund</th><th></th></tr></thead><tbody>${list.map((b) => html`<tr><td class="strong">${b.term}</td><td>${b.reason}</td><td class="act"><button class="btn sm ghost" data-act="bl-del" data-id="${b.id}" aria-label="${b.term} entfernen">${ico('trash')}</button></td></tr>`)}</tbody></table></div>`, { icon: 'lock', flush: true })}
        <aside class="stack">
          ${c.sheet('Begriff sperren', html`<div class="stack">${c.field('bl-term', 'Begriff', html`<input id="bl-term" type="text" data-bind="ui.bl.term" value="${S.ui.bl.term}" placeholder="z. B. Weißes Haus">`)}${c.field('bl-reason', 'Grund', html`<input id="bl-reason" type="text" data-bind="ui.bl.reason" value="${S.ui.bl.reason}" placeholder="z. B. Reale Marke">`)}<button class="btn primary" data-act="bl-add">Sperren</button></div>`, { icon: 'plus' })}
          ${c.sheet('Namenstest', html`<div class="stack">${c.field('nt-in', 'Name prüfen', html`<input id="nt-in" type="text" data-bind="ui.ntq" data-after="nt-run" placeholder="Name eingeben" value="${S.ui.ntq || ''}">`)}<div data-partial="name-test">${IC.partials['name-test']()}</div></div>`, { icon: 'search' })}
        </aside>
      </div>`;
  }

  /* ---------- Audit ---------- */
  function audit() {
    const q = (S.ui.aq || '').toLowerCase();
    const kind = S.ui.ak || '';
    const rows = ST().audit.filter((a) => (!kind || a.kind === kind) && (!q || (a.actor + ' ' + a.action + ' ' + a.target + ' ' + a.detail).toLowerCase().indexOf(q) !== -1));
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Protokoll</div><h1>Audit-Log</h1><p class="sub">Jede Statusänderung mit Akteur, Zeit und Grund. Die Einträge lassen sich nicht ändern.</p></div>${oocBadge}</div>
      <div class="sheet"><div class="sheet-b"><div class="row" style="align-items:flex-end">
        <div class="field grow" style="min-width:220px"><label for="au-q">Suche</label><input id="au-q" type="search" data-bind="ui.aq" data-after="au-run" value="${S.ui.aq || ''}" placeholder="Akteur, Aktion, Aktenzeichen"></div>
        <div class="seg" role="group" aria-label="Akteur">${[['', 'Alle'], ['bürger', 'Bürger'], ['beamter', 'Beamte'], ['staff', 'Staff'], ['system', 'System']].map((k) => html`<button data-act="au-kind" data-kind="${k[0]}" ${pressed(kind === k[0])}>${k[1]}</button>`)}</div></div></div></div>
      <div class="sheet"><div class="sheet-b flush tbl-wrap" data-partial="audit-rows">${IC.partials['audit-rows']()}</div></div>`;
  }
  IC.partials['audit-rows'] = function () {
    const q = (S.ui.aq || '').toLowerCase();
    const kind = S.ui.ak || '';
    const rows = ST().audit.filter((a) => (!kind || a.kind === kind) && (!q || (a.actor + ' ' + a.action + ' ' + a.target + ' ' + a.detail).toLowerCase().indexOf(q) !== -1));
    if (!rows.length) return c.empty('search', 'Keine Einträge', 'Zu diesem Filter gibt es keine Protokolleinträge.');
    const kc = { bürger: '', beamter: 'info', staff: 'warn', system: '' };
    return html`<table class="tbl"><thead><tr><th>Zeit</th><th>Akteur</th><th>Aktion</th><th>Bezug</th><th>Detail</th></tr></thead><tbody>${rows.map((a) => html`<tr><td class="nowrap num">${IC.fdt(a.ts)}</td><td>${a.actor} ${c.chip(a.kind, kc[a.kind] || '')}</td><td class="strong">${a.action}</td><td>${c.tag(a.target)}</td><td>${a.detail}</td></tr>`)}</tbody></table>`;
  };

  /* ---------- Einstellungen ---------- */
  function settings() {
    const st = ST().settings;
    const items = [
      ['requireOfficials', 'Beamtenpflicht für Termine', 'Termine sind nur buchbar, wenn Beamte im Dienst sind oder Sprechzeiten bestehen. Das ist die Kernregel des Systems.'],
      ['writtenProcedure', 'Schriftliches Verfahren (Notfallregel)', 'Überfällige Anträge lassen sich nach Aktenlage entscheiden, wenn ' + cfg().rules.escalateHours + ' Stunden kein Termin möglich war.'],
      ['undergroundViaPortal', 'Untergrund-Fraktionen über das Portal', 'Gruppen melden eine legale Hülle an und geben OOC-Angaben ab. Aus: Untergrund-Fraktionen werden komplett OOC vergeben.'],
      ['fourEyes', 'Vier-Augen-Prinzip für Organisationen', 'Entscheidungen brauchen die Gegenzeichnung eines zweiten Beamten ab Rang Amtsleiter. Sinnvoll ab etwa fünf aktiven Beamten.', true],
    ];
    return html`
      <div class="page-head"><div><div class="crumbs">Staff-Panel · Einstellungen</div><h1>Einstellungen</h1><p class="sub">Funktionen ein- und ausschalten. Änderungen wirken sofort und werden protokolliert.</p></div>${oocBadge}</div>
      ${c.sheet('Funktionen', html`<ul class="checklist">${items.map((i) => html`<li><label ${i[3] ? raw('style="cursor:default;opacity:.7"') : ''}><input type="checkbox" data-act="set-toggle" data-key="${i[0]}" ${st[i[0]] ? raw('checked') : ''} ${i[3] ? raw('disabled') : ''}><span><span class="strong">${i[1]}</span>${i[3] ? html` ${c.chip('Geplant für Phase 2', 'info')}` : ''}<span class="ci-note" style="display:block;font-size:13.5px">${i[2]}</span></span></label></li>`)}</ul>`, { icon: 'gear' })}`;
  }

  /* ---------- Aktionen ---------- */
  Object.assign(IC.act, {
    'gate-ok': async (el) => {
      const a = ST().gate.find((x) => x.id === el.dataset.id);
      const yes = await IC.confirm({ title: '„' + a.name + '“ freigeben?', icon: 'shield', yes: 'Freigeben und eintragen', text: 'Das Unternehmen beziehungsweise die Organisation wird eingetragen, die Registernummer vergeben und der Gewerbeschein ausgestellt. Danach laufen die Provisioning-Hooks.' });
      if (yes) await IC.run('staffGate', { id: a.id, decision: 'freigeben' }, { ok: 'Freigegeben und eingetragen.' });
    },
    'gate-back': (el) => {
      S.ui.gb = { id: el.dataset.id, note: '' };
      IC.modal.open({ title: 'Schlussprüfung nicht bestanden', icon: 'shield',
        body: html`<div class="stack">${c.callout('info', 'Hinweis an die Gründer', 'Der Grund wird den Gründern als „Hinweis der Registerführung“ angezeigt. Formulieren Sie ihn verständlich und ohne IC-Bezug.')}${c.field('gb-note', 'Grund', html`<textarea id="gb-note" data-bind="ui.gb.note" placeholder="Was fehlt, oder was muss angepasst werden?"></textarea>`, { req: true })}</div>`,
        footer: html`<button class="btn" data-act="modal-close">Abbrechen</button><button class="btn danger solid" data-act="gate-back-send">Zurückweisen</button>` });
    },
    'gate-back-send': async () => { const r = await IC.run('staffGate', { id: S.ui.gb.id, decision: 'zurueck', note: S.ui.gb.note }, { ok: 'Zurückgewiesen. Die Gründer erhalten den Hinweis.' }); if (r.ok) IC.modal.close(true); },
    'esc-open': (el) => {
      const a = ST().escalations.find((x) => x.id === el.dataset.id);
      S.ui.ew = { id: a.id, decision: 'genehmigt', reason: '' };
      IC.modal.open({ title: 'Entscheidung nach Aktenlage', icon: 'doc',
        body: html`<div class="stack">${c.callout('info', a.name, 'IC ist das ein Bescheid der Behörde ohne Termin. Die Gründer sehen „Entscheidung nach Aktenlage“.')}
          ${c.field('ew-dec', 'Entscheidung', html`<select id="ew-dec" data-bind="ui.ew.decision"><option value="genehmigt">Genehmigen</option><option value="abgelehnt">Ablehnen</option></select>`)}
          ${c.field('ew-reason', 'Begründung', html`<textarea id="ew-reason" data-bind="ui.ew.reason" placeholder="Pflicht. Der Text steht im Bescheid."></textarea>`, { req: true })}</div>`,
        footer: html`<button class="btn" data-act="modal-close">Abbrechen</button><button class="btn primary" data-act="esc-send">Entscheidung treffen</button>` });
    },
    'esc-send': async () => { const w = S.ui.ew; const r = await IC.run('staffWritten', { id: w.id, decision: w.decision, reason: w.reason }, { ok: 'Entscheidung nach Aktenlage erteilt.' }); if (r.ok) IC.modal.close(true); },
    'cap-step': async (el) => {
      const x = ST().caps.find((k) => k.key === el.dataset.key);
      await IC.run('staffCap', { key: x.key, value: x.cap + Number(el.dataset.d) }, { noReload: false });
    },
    'bl-add': async () => { const r = await IC.run('staffBlacklistAdd', { term: S.ui.bl.term, reason: S.ui.bl.reason }, { ok: 'Begriff gesperrt.' }); if (r.ok) S.ui.bl = { term: '', reason: '' }; },
    'bl-del': async (el) => { await IC.run('staffBlacklistRemove', { id: el.dataset.id }, { ok: 'Sperre aufgehoben.' }); },
    'nt-run': IC.debounce(async () => {
      const q = (S.ui.ntq || '').trim();
      if (q.length < 3) { S.ui.nt = null; IC.refresh('name-test'); return; }
      const r = await IC.api('nameCheck', { name: q, legalForm: 'einzel' });
      S.ui.nt = r; IC.refresh('name-test');
    }, 250),
    'au-run': () => IC.refresh('audit-rows'),
    'au-kind': (el) => { S.ui.ak = el.dataset.kind; IC.render(); },
    'set-toggle': async (el) => { await IC.run('staffSetting', { key: el.dataset.key, value: el.checked }, { ok: 'Einstellung gespeichert.' }); },
  });

  IC.registerApp('staff', {
    title: 'Staff-Panel', icon: 'shield', def: 'overview',
    where: () => 'OOC · Verwaltung der IC-Gründung',
    nav: () => {
      const k = ST().kpi;
      return [
        { id: 'overview', label: 'Übersicht', icon: 'chart' },
        { id: 'gate', label: 'Freigaben', icon: 'shield', badge: k.gate || null, badgeKind: 'warn' },
        { id: 'esc', label: 'Eskalationen', icon: 'alert', badge: k.escalations || null, badgeKind: 'bad' },
        { head: 'Regeln' },
        { id: 'caps', label: 'Kapazitäten', icon: 'layers' },
        { id: 'black', label: 'Sperrliste', icon: 'lock' },
        { id: 'audit', label: 'Audit-Log', icon: 'list' },
        { id: 'settings', label: 'Einstellungen', icon: 'gear' },
      ];
    },
    railFoot: () => html`Dieser Bereich ist OOC. Beamte und Bürger sehen ihn nie.`,
    views: { overview, gate, esc, caps, black, audit, settings },
  });
})();
