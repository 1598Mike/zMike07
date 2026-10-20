/* IC-Behördenportal · Gewerbeamt (Sicht der Bürger) */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico, money } = IC;
  const c = IC.c, L = IC.L, S = IC.S;
  const cfg = () => S.d.config;
  const formOf = (k) => cfg().legalForms.find((f) => f.key === k);
  const branchOf = (k) => cfg().branches.find((b) => b.key === k);
  const sel = (cond) => (cond ? raw('selected') : '');
  const pressed = (cond) => raw('aria-pressed="' + (cond ? 'true' : 'false') + '"');

  /* ====================================================================
     Start
     ==================================================================== */
  function tile(icon, title, desc, attrs, badge) {
    return html`<button class="tile" ${raw(attrs)}>${badge ? IC.c.badge(badge, 'warn') : ''}<span class="tile-ico">${ico(icon, 'lg')}</span><h3>${title}</h3><p>${desc}</p></button>`;
  }

  function nextStep(a) {
    const st = a.status;
    if (st === 'entwurf') return { text: 'Der Entwurf ist noch nicht eingereicht.', act: html`<button class="btn sm primary" data-act="wiz-edit" data-id="${a.id}">Fortsetzen</button>` };
    if (st === 'eingereicht') return { text: 'Wartet auf die Vorprüfung durch die Beamten (Ziel: 48 Stunden).', act: '' };
    if (st === 'nachbesserung') return { text: a.remark || 'Bitte den Antrag überarbeiten.', act: html`<button class="btn sm primary" data-act="wiz-edit" data-id="${a.id}">Antrag bearbeiten</button>` };
    if (st === 'vorpruefung_ok') return { text: 'Buchen Sie jetzt Ihren Vorstellungstermin im Bürgeramt.', act: html`<button class="btn sm primary" data-act="app-book" data-id="${a.id}">Termin buchen</button>` };
    if (st === 'termin_gebucht') {
      const ap = S.d.myAppointments.find((x) => x.applicationId === a.id && ['gebucht', 'eingecheckt', 'aufgerufen'].indexOf(x.status) !== -1);
      return { text: ap ? 'Vorstellungstermin am ' + IC.fday(ap.start) + ' um ' + IC.ftime(ap.start) + ' Uhr.' : 'Termin gebucht.', act: html`<button class="btn sm" data-act="go" data-app="buergeramt" data-view="appts">Meine Termine</button>` };
    }
    if (st === 'termin_laeuft') return { text: 'Die Vorstellung läuft gerade.', act: '' };
    if (st === 'staff_pruefung') return { text: 'Genehmigt. Die Registerführung führt die Schlussprüfung durch.', act: '' };
    if (st === 'einspruch') return { text: 'Der Einspruch wird geprüft. Eine Einspruchsverhandlung kann gebucht werden.', act: html`<button class="btn sm primary" data-act="app-book" data-id="${a.id}">Verhandlung buchen</button>` };
    if (st === 'abgelehnt') return { text: a.decision ? a.decision.reason : 'Abgelehnt.', act: a.objectionUntil > IC.now() ? html`<button class="btn sm" data-act="app-open" data-id="${a.id}">Einspruch möglich</button>` : '' };
    return { text: '', act: '' };
  }

  function home() {
    const d = S.d;
    const open = d.myApplications.filter((a) => L.OPEN_APP.indexOf(a.status) !== -1 || a.status === 'entwurf');
    const legacy = d.myEntities.filter((e) => e.legacy && !e.legacyConfirmed && e.status !== 'aufgeloest');
    const needs = d.myApplications.filter((a) => a.status === 'nachbesserung' || a.status === 'vorpruefung_ok').length;
    const el = d.eligibility.unternehmen;
    return html`
      <div class="page-head">
        <div><div class="crumbs">Gewerbeamt · Start</div><h1>Willkommen, ${d.me.name}</h1>
          <p class="sub">Gründung, Änderung und Auflösung von Unternehmen und Organisationen. Alles an einem Ort. Die Entscheidung treffen die Beamten im persönlichen Termin.</p></div>
        <div class="duty ${d.duty.count ? 'on' : 'off'}"><span class="big">${String(d.duty.count).padStart(2, '0')}</span><div><div class="strong">Beamte im Dienst</div><div class="small muted">${d.duty.count ? 'Live-Termine sind buchbar' : 'Termine nur in Sprechzeiten'}</div></div></div>
      </div>
      ${legacy.map((e) => c.callout('warn', 'Bestandsbestätigung offen: ' + e.name,
        'Ihr Eintrag wurde aus dem alten System übernommen. Bitte bestätigen Sie Ihre Daten kostenlos bis zum ' + IC.fdate(e.legacyDue) + '. Der Eintrag ist bis dahin nicht gefährdet.', 'shield',
        html`<button class="btn sm primary" data-act="legacy-confirm" data-id="${e.id}">Jetzt bestätigen</button><button class="btn sm" data-act="ent-cert" data-id="${e.id}">Gewerbeschein ansehen</button>`))}
      <div class="grid g3">
        ${tile('building', 'Unternehmen gründen', 'Gewerbe anmelden: Einzelunternehmen, GbR oder GmbH.', 'data-act="wiz-start" data-kind="unternehmen"')}
        ${tile('flag', 'Fraktion oder Organisation gründen', 'Verein, Interessengemeinschaft, Partei, Verband oder Stiftung.', 'data-act="wiz-start" data-kind="fraktion"')}
        ${tile('doc', 'Meine Anträge', 'Status, Hinweise der Beamten, Einspruch.', 'data-act="view" data-view="apps"', needs || null)}
        ${tile('folder', 'Meine Eintragungen', 'Gewerbeschein, Änderungen, Auflagen, Auflösung.', 'data-act="view" data-view="entities"')}
        ${tile('calendar', 'Termin im Bürgeramt', 'Vorstellungstermin buchen, einchecken, Wartenummer ziehen.', 'data-act="go" data-app="buergeramt" data-view="book"')}
        ${tile('search', 'Handelsregister', 'Unternehmen und Organisationen öffentlich nachschlagen.', 'data-act="view" data-view="register"')}
      </div>
      <div class="split">
        <div class="stack">
          ${c.sheet('Ihre laufenden Vorgänge', open.length ? html`<div class="stack sm">${open.map((a) => {
            const n = nextStep(a);
            return html`<div class="person" style="grid-template-columns:minmax(0,1fr) auto">
              <div class="grow"><div class="row sm"><span class="pn">${a.name || 'Entwurf ohne Namen'}</span>${a.caseNo ? c.tag(a.caseNo) : ''}${c.appChip(a.status)}</div>
              <div class="pm" style="margin-top:4px">${n.text}</div></div><div class="btn-row">${n.act}<button class="btn sm ghost" data-act="app-open" data-id="${a.id}">Details</button></div></div>`;
          })}</div>` : c.empty('doc', 'Keine laufenden Vorgänge', 'Starten Sie eine Gründung, um hier den Fortschritt zu verfolgen.'), { icon: 'doc', flush: false })}
        </div>
        <aside class="stack">
          ${c.sheet('Ihre Voraussetzungen', html`<ul class="checklist">${el.checks.map((k) => html`<li><label style="cursor:default"><span class="chip ${k.ok ? 'ok' : 'bad'}" style="margin-top:1px">${ico(k.ok ? 'check' : 'x')}</span><span>${k.text}</span></label></li>`)}</ul>`, { icon: 'shield' })}
        </aside>
      </div>`;
  }

  /* ====================================================================
     Gründungs-Wizard
     ==================================================================== */
  const STEPS = {
    unternehmen: ['Art und Branche', 'Rechtsform und Name', 'Gründer und Anteile', 'Standort', 'Konzept', 'Prüfen und bezahlen'],
    fraktion: ['Art der Organisation', 'Name', 'Gründungsmitglieder', 'Sitz', 'Zweck und Satzung', 'Prüfen und bezahlen'],
  };

  function newWiz(kind) {
    const me = S.d.me;
    return {
      step: 0, maxStep: 0, kind: kind || null, legalForm: null, branch: null, name: '', nameResult: null, nameFor: null,
      founders: [{ charId: me.charId, name: me.name, role: kind === 'fraktion' ? 'vorsitz' : 'inhaber', share: kind === 'fraktion' ? null : 100, consent: 'self' }],
      property: { mode: null, id: null, label: '' },
      concept: { idea: '', audience: '', offer: '', staff: '', hours: '' },
      statute: { purpose: '', goals: '', admission: '' },
      ooc: { category: 'legal', note: '', members: '' },
      confirm: false, id: null, done: null, errors: [], resubmit: false,
    };
  }
  const W = () => S.ui.wiz || (S.ui.wiz = newWiz(null));

  function fees(w) {
    const f = formOf(w.legalForm);
    if (!f) return null;
    const b = w.branch ? branchOf(w.branch) : null;
    const k = b ? b.factor : 1;
    const apply = Math.round(f.feeApply * k), register = Math.round(f.feeRegister * k);
    return { apply, register, capital: f.capital, payNow: apply + register + f.capital, refundable: register + f.capital };
  }

  function rawName(name, form) {
    const suf = form && form.suffix;
    if (suf && name.toLowerCase().endsWith(' ' + suf.toLowerCase())) return name.slice(0, name.length - suf.length - 1);
    return name;
  }

  function issues(w, step) {
    const out = [];
    const f = formOf(w.legalForm);
    const b = w.branch ? branchOf(w.branch) : null;
    if (step === 0) {
      if (!w.kind) out.push('Bitte wählen, was Sie gründen möchten.');
      else if (w.kind === 'unternehmen') {
        if (!b) out.push('Bitte eine Branche wählen.');
        else if (b.used >= b.cap && !w.resubmit) out.push('In der Branche „' + b.label + '“ sind alle Plätze vergeben.');
      } else if (!f) out.push('Bitte die Art der Organisation wählen.');
    }
    if (step === 1) {
      if (w.kind === 'unternehmen' && !f) out.push('Bitte eine Rechtsform wählen.');
      const key = w.name.trim() + '|' + w.legalForm;
      if (w.name.trim().length < 3) out.push('Bitte einen Namen eingeben (mindestens 3 Zeichen).');
      else if (w.nameFor !== key || !w.nameResult) out.push('Der Name wird geprüft …');
      else if (!w.nameResult.ok) out.push(w.nameResult.issues.filter((i) => i.level === 'error')[0].text);
    }
    if (step === 2 && f) {
      if (w.founders.length < f.minFounders) out.push('Mindestens ' + f.minFounders + ' ' + (w.kind === 'fraktion' ? 'Gründungsmitglieder' : 'Gründer') + ' erforderlich (aktuell ' + w.founders.length + ').');
      if (w.kind === 'unternehmen') {
        const sum = w.founders.reduce((n, x) => n + (Number(x.share) || 0), 0);
        if (sum !== 100) out.push('Die Anteile müssen zusammen 100 % ergeben (aktuell ' + sum + ' %).');
        if (w.founders.some((x) => !(Number(x.share) > 0))) out.push('Jeder Gesellschafter braucht einen Anteil über 0 %.');
      } else if (w.founders.filter((x) => x.role === 'vorsitz').length !== 1) out.push('Es muss genau einen Vorsitz geben.');
      if (w.founders.some((x) => x.consent === 'pending')) out.push('Es fehlt noch die Zustimmung von Mitgründern.');
    }
    if (step === 3) {
      const need = b && b.needsProperty;
      if (need && !(w.property.mode === 'immobilie' && w.property.id)) out.push('Diese Branche verlangt einen festen Standort.');
      else if (!w.property.mode) out.push('Bitte einen Standort wählen oder „ohne festen Standort“ angeben.');
      else if (w.property.mode === 'immobilie' && !w.property.id) out.push('Bitte eine Immobilie auswählen.');
    }
    if (step === 4) {
      if (w.kind === 'unternehmen' && w.concept.idea.trim().length < 80) out.push('Bitte die Geschäftsidee beschreiben (mindestens 80 Zeichen, aktuell ' + w.concept.idea.trim().length + ').');
      if (w.kind === 'fraktion' && w.statute.purpose.trim().length < 80) out.push('Bitte den Zweck beschreiben (mindestens 80 Zeichen, aktuell ' + w.statute.purpose.trim().length + ').');
    }
    if (step === 5) {
      const el = S.d.eligibility[w.kind || 'unternehmen'];
      el.checks.filter((k) => !k.ok).forEach((k) => out.push('Voraussetzung nicht erfüllt: ' + k.text));
      const fe = fees(w);
      if (fe && !w.resubmit && fe.payNow > S.d.me.bank) out.push('Der Kontostand reicht nicht aus (benötigt ' + money(fe.payNow) + ').');
      if (!w.confirm) out.push('Bitte die Richtigkeit der Angaben bestätigen.');
    }
    return out;
  }
  const allIssues = (w) => [0, 1, 2, 3, 4].reduce((n, i) => n.concat(issues(w, i)), []);

  function draftOf(w) {
    return {
      id: w.id, kind: w.kind, legalForm: w.legalForm, branch: w.kind === 'unternehmen' ? w.branch : null, name: w.name.trim(),
      founders: IC.clone(w.founders), property: IC.clone(w.property), concept: IC.clone(w.concept), statute: IC.clone(w.statute), ooc: w.kind === 'fraktion' ? IC.clone(w.ooc) : null,
    };
  }

  /* ----- Teilansichten (werden ohne Neuaufbau der Seite aktualisiert) ----- */
  IC.partials['wiz-name'] = function () {
    const w = W();
    const key = w.name.trim() + '|' + w.legalForm;
    if (w.name.trim().length < 3) return html`<div class="hint">Mindestens 3, höchstens 40 Zeichen. Der Rechtsformzusatz wird automatisch ergänzt.</div>`;
    if (w.nameFor !== key || !w.nameResult) return html`<div class="hint">${ico('clock')} Name wird geprüft …</div>`;
    const r = w.nameResult;
    return html`${r.ok ? c.msg('ok', 'Der Name ist frei. Eintrag im Register als: ' + r.display) : ''}${r.issues.map((i) => c.msg(i.level === 'error' ? 'bad' : 'warn', i.text))}`;
  };

  IC.partials['wiz-c1'] = function () {
    const w = W();
    return c.counter((w.kind === 'fraktion' ? w.statute.purpose : w.concept.idea).trim().length, 80);
  };

  IC.partials['wiz-side'] = function () {
    const w = W();
    const f = formOf(w.legalForm), b = w.branch ? branchOf(w.branch) : null, fe = fees(w);
    const labels = STEPS[w.kind || 'unternehmen'];
    return html`<div class="stack">
      ${c.sheet('Ihr Antrag', html`${c.kv([
        ['Art', w.kind === 'unternehmen' ? 'Unternehmen' : w.kind === 'fraktion' ? 'Organisation' : '–'],
        w.kind === 'unternehmen' ? ['Branche', b ? b.label : '–'] : null,
        [w.kind === 'fraktion' ? 'Organisationsart' : 'Rechtsform', f ? f.label : '–'],
        ['Name', w.nameResult && w.nameResult.ok && w.nameFor === w.name.trim() + '|' + w.legalForm ? w.nameResult.display : (w.name.trim() || '–')],
        ['Gründer', w.founders.length],
        ['Standort', w.property.mode === 'immobilie' ? w.property.label : w.property.mode === 'mobil' ? 'Ohne festen Standort' : '–'],
      ])}`, { icon: 'doc' })}
      ${c.sheet('Gebühren', fe ? html`
        <div class="sum-row"><span>Antragsgebühr <span class="xs muted">(nicht erstattbar)</span></span><span class="v">${money(w.resubmit ? 0 : fe.apply)}</span></div>
        <div class="sum-row"><span>Eintragungsgebühr <span class="xs muted">(erstattbar)</span></span><span class="v">${money(w.resubmit ? 0 : fe.register)}</span></div>
        ${fe.capital ? html`<div class="sum-row"><span>Kapital in Verwahrung <span class="xs muted">(erstattbar)</span></span><span class="v">${money(w.resubmit ? 0 : fe.capital)}</span></div>` : ''}
        <div class="sum-row total"><span>Jetzt fällig</span><span class="v">${money(w.resubmit ? 0 : fe.payNow)}</span></div>
        <div class="xs muted" style="margin-top:6px">Kontostand: ${money(S.d.me.bank)}${w.resubmit ? '. Gebühren wurden bereits gezahlt.' : ''}</div>` : html`<p class="small muted">Wählen Sie eine Rechtsform, um die Gebühren zu sehen.</p>`, { icon: 'coin' })}
      ${c.sheet('Fortschritt', html`<ul class="checklist">${labels.map((l, i) => {
        const bad = i < 5 ? issues(w, i).length : 0;
        const ok = i < 5 ? !bad && i <= w.maxStep : false;
        return html`<li><label style="cursor:default;padding:7px 4px"><span class="chip ${ok ? 'ok' : i === w.step ? 'info' : ''}">${i === 5 ? ico('check') : ok ? ico('check') : i + 1}</span><span class="${i === w.step ? 'strong' : ''}">${l}</span></label></li>`;
      })}</ul>`, { icon: 'list' })}
    </div>`;
  };

  IC.partials['wiz-nav'] = function () {
    const w = W();
    const iss = issues(w, w.step);
    const last = w.step === 5;
    return html`${iss.length ? html`<div class="callout warn" role="alert">${ico('alert')}<div><div class="t">Das fehlt noch</div><ul>${iss.map((i) => html`<li>${i}</li>`)}</ul></div></div>` : ''}
      ${w.errors.length ? html`<div class="callout bad" role="alert">${ico('alert')}<div><div class="t">Der Antrag wurde vom Amt abgelehnt, bitte prüfen</div><ul>${w.errors.map((e) => html`<li>${e.text}</li>`)}</ul></div></div>` : ''}
      <div class="spread">
        <div class="btn-row">${w.step > 0 ? html`<button class="btn" data-act="wiz-prev">${ico('back')}Zurück</button>` : ''}<button class="btn ghost" data-act="wiz-save">Entwurf speichern</button></div>
        <div class="btn-row">${last
          ? html`<button class="btn primary lg" data-act="wiz-submit" ${iss.length ? raw('disabled') : ''}>${ico('stamp')}Verbindlich einreichen</button>`
          : html`<button class="btn primary" data-act="wiz-next" ${iss.length ? raw('disabled') : ''}>Weiter${ico('arrow')}</button>`}</div>
      </div>`;
  };

  IC.partials['wiz-share'] = function () {
    const w = W();
    const sum = w.founders.reduce((n, x) => n + (Number(x.share) || 0), 0);
    return html`<span class="chip ${sum === 100 ? 'ok' : 'warn'}">Summe ${sum} %</span>`;
  };

  IC.partials['wiz-founders'] = function () {
    const w = W();
    const org = w.kind === 'fraktion';
    const roles = org ? cfg().orgRoles : cfg().companyRoles;
    const f = formOf(w.legalForm);
    const single = f && f.key === 'einzel';
    return html`<div class="stack sm">${w.founders.map((fd, i) => {
      const isMe = fd.consent === 'self';
      const cons = isMe ? c.chip('Sie', 'info') : fd.consent === 'ok' ? c.chip('Zugestimmt', 'ok', 'check') : c.chip('Zustimmung ausstehend', 'warn', 'clock');
      return html`<div class="person" style="grid-template-columns:36px minmax(0,1fr) auto">
        ${c.avatar(fd.name)}
        <div class="grow"><div class="pn">${fd.name}</div><div class="pm">${cons}</div></div>
        <div class="row sm">
          <select id="wf-role-${i}" style="width:auto;min-width:160px" data-bind="ui.wiz.founders.${i}.role" data-after="wiz-light" aria-label="Rolle von ${fd.name}">${(single ? ['inhaber'] : roles).map((r) => html`<option value="${r}" ${sel(fd.role === r)}>${L.MEMBER_ROLE[r]}</option>`)}</select>
          ${org ? '' : html`<div class="input-suffix share"><input id="wf-share-${i}" type="number" min="1" max="100" value="${fd.share}" data-bind="ui.wiz.founders.${i}.share" data-after="wiz-light" aria-label="Anteil von ${fd.name} in Prozent"><span>%</span></div>`}
          ${isMe ? '' : html`<button class="btn sm danger" data-act="wiz-remove-founder" data-idx="${i}" aria-label="${fd.name} entfernen">${ico('x')}</button>`}
        </div></div>`;
    })}</div>`;
  };

  /* ----- Schritte ----- */
  function stepArt(w) {
    const d = S.d;
    return html`
      <div class="grid g2">
        <button class="pick pick-big" data-act="wiz-kind" data-kind="unternehmen" ${pressed(w.kind === 'unternehmen')}><span class="pk-t">${ico('building', 'lg')}Unternehmen</span><span class="pk-d">Ein Gewerbe mit Gewinnabsicht: Laden, Gastronomie, Werkstatt, Dienstleistung.</span></button>
        <button class="pick pick-big" data-act="wiz-kind" data-kind="fraktion" ${pressed(w.kind === 'fraktion')}><span class="pk-t">${ico('flag', 'lg')}Fraktion oder Organisation</span><span class="pk-d">Verein, Interessengemeinschaft, Partei, Verband oder Stiftung.</span></button>
      </div>
      ${w.kind === 'unternehmen' ? html`<div class="stack sm"><h4>Branche</h4>
        <div class="grid g-auto">${d.config.branches.map((b) => {
          const full = b.used >= b.cap && !w.resubmit;
          return html`<button class="pick" data-act="wiz-branch" data-key="${b.key}" ${pressed(w.branch === b.key)} ${full ? raw('disabled') : ''}>
            <span class="pk-t">${b.label}</span><span class="pk-d">${b.desc}</span>
            <span class="pk-m">${b.needsProperty ? c.chip('Standort nötig', '', 'pin') : ''}${b.authority ? c.chip('Zulassung: ' + b.authority, 'warn', 'badge') : ''}${b.staffGate ? c.chip('Schlussprüfung', 'info', 'shield') : ''}${b.factor > 1 ? c.chip('Gebühr ×' + String(b.factor).replace('.', ','), '') : ''}</span>
            ${c.meter(b.used, b.cap)}<span class="xs muted">${full ? 'Keine Plätze frei' : (b.cap - b.used) + ' von ' + b.cap + ' Plätzen frei'}</span></button>`;
        })}</div></div>` : ''}
      ${w.kind === 'fraktion' ? html`<div class="stack sm"><h4>Art der Organisation</h4>
        <div class="grid g-auto">${d.config.legalForms.filter((f) => f.kind === 'fraktion').map((f) => html`<button class="pick" data-act="wiz-form" data-key="${f.key}" ${pressed(w.legalForm === f.key)}>
          <span class="pk-t">${f.label}</span><span class="pk-d">${f.desc}</span>
          <span class="pk-m">${c.chip('mind. ' + f.minFounders + ' Gründer', '', 'users')}${c.chip(money(f.feeApply + f.feeRegister), '', 'coin')}${f.capital ? c.chip(money(f.capital) + ' Kapital', 'warn') : ''}</span></button>`)}</div></div>` : ''}`;
  }

  function stepName(w) {
    const d = S.d;
    const f = formOf(w.legalForm);
    return html`
      ${w.kind === 'unternehmen' ? html`<div class="stack sm"><h4>Rechtsform</h4><div class="grid g3">${d.config.legalForms.filter((x) => x.kind === 'unternehmen').map((x) => html`<button class="pick" data-act="wiz-form" data-key="${x.key}" ${pressed(w.legalForm === x.key)}>
        <span class="pk-t">${x.label}</span><span class="pk-d">${x.desc}</span>
        <span class="pk-m">${c.chip('mind. ' + x.minFounders + ' Gründer', '', 'users')}${c.chip(money(x.feeApply + x.feeRegister) + ' Gebühren', '', 'coin')}${x.capital ? c.chip(money(x.capital) + ' Kapital', 'warn') : ''}</span></button>`)}</div></div>` : ''}
      <div class="stack sm">
        ${c.field('wiz-name', 'Name' + (f && f.suffix ? ' (ohne „' + f.suffix + '“)' : ''), html`<input id="wiz-name" type="text" maxlength="40" autocomplete="off" placeholder="${w.kind === 'fraktion' ? 'z. B. Motorradfreunde Sandy Shores' : 'z. B. Hafenbar Santa Maria'}" value="${w.name}" data-bind="ui.wiz.name" data-after="wiz-name-input">`, { req: true })}
        <div data-partial="wiz-name">${IC.partials['wiz-name']()}</div>
      </div>
      ${c.callout('info', 'Namensrecht', html`Namen müssen eindeutig sein. Ähnliche Namen, reservierte Begriffe (zum Beispiel Behörden) und Beleidigendes sind nicht zulässig. Während Ihres Antrags ist der Name ${IC.S.d.config.rules.nameReserveDays} Tage für Sie reserviert.`)}`;
  }

  function stepFounders(w) {
    const d = S.d;
    const f = formOf(w.legalForm);
    const org = w.kind === 'fraktion';
    const canAdd = f && f.key !== 'einzel';
    const avail = d.nearby.filter((p) => !w.founders.some((x) => x.charId === p.charId));
    return html`
      <div class="stack sm">
        <div class="spread"><h4>${org ? 'Gründungsmitglieder' : 'Gründer und Gesellschafter'}</h4>${org ? '' : html`<div class="row sm"><span data-partial="wiz-share">${IC.partials['wiz-share']()}</span><button class="btn sm" data-act="wiz-even">Anteile gleichmäßig</button></div>`}</div>
        <div data-partial="wiz-founders">${IC.partials['wiz-founders']()}</div>
      </div>
      ${canAdd ? html`<div class="stack sm"><h4>Personen in Ihrer Nähe</h4>
        <p class="small muted">Mitgründer erhalten eine Einladung und müssen zustimmen. Erst dann lässt sich der Antrag einreichen.</p>
        ${avail.length ? html`<div class="stack sm">${avail.map((p) => html`<div class="person">${c.avatar(p.name)}<div class="grow"><div class="pn">${p.name}</div>
          <div class="pm">${p.elig.ok ? html`${p.age} Jahre · ${p.playHours} Std. Spielzeit` : html`<span style="color:var(--bad)">${p.elig.checks.filter((k) => !k.ok).map((k) => k.text).join('; ')}</span>`}</div></div>
          <button class="btn sm" data-act="wiz-add-founder" data-id="${p.charId}" ${p.elig.ok ? '' : raw('disabled')}>${ico('plus')}Einladen</button></div>`)}</div>` : html`<p class="small muted">Niemand mehr in der Nähe.</p>`}</div>`
        : html`<div class="callout info">${ico('info')}<div>Ein Einzelunternehmen hat genau einen Inhaber. Wählen Sie eine GbR oder GmbH, um Mitgründer aufzunehmen.</div></div>`}`;
  }

  function stepSite(w) {
    const d = S.d;
    const b = w.branch ? branchOf(w.branch) : null;
    const need = b && b.needsProperty;
    const org = w.kind === 'fraktion';
    return html`
      <div class="grid g2">
        <button class="pick" data-act="wiz-site-mode" data-mode="immobilie" ${pressed(w.property.mode === 'immobilie')}><span class="pk-t">${ico('pin')}Feste Immobilie</span><span class="pk-d">Ein Standort aus dem Gewerbeverzeichnis.</span></button>
        <button class="pick" data-act="wiz-site-mode" data-mode="mobil" ${pressed(w.property.mode === 'mobil')} ${need ? raw('disabled') : ''}><span class="pk-t">${ico('tool')}${org ? 'Ohne festen Sitz' : 'Mobil, ohne festen Standort'}</span><span class="pk-d">${need ? 'Für diese Branche nicht zulässig.' : 'Zum Beispiel Lieferdienst, Handwerk oder Taxi.'}</span></button>
      </div>
      ${w.property.mode === 'immobilie' ? html`<div class="stack sm"><h4>Gewerbeverzeichnis</h4><div class="grid g-auto">${d.properties.map((p) => {
        const mine = w.property.id === p.id;
        return html`<button class="pick" data-act="wiz-prop" data-id="${p.id}" ${pressed(mine)} ${p.taken && !mine ? raw('disabled') : ''}>
          <span class="pk-t">${p.label}</span><span class="pk-d">${p.district}${p.note ? ' · ' + p.note : ''}</span>
          <span class="pk-m">${c.chip('Größe ' + p.size, '')}${c.chip(money(p.rent) + ' Miete', '', 'coin')}${p.taken && !mine ? c.chip(p.status === 'frei' ? 'Reserviert' : 'Vermietet', 'bad') : c.chip('Frei', 'ok')}</span></button>`;
      })}</div><p class="small muted">Den Mietvertrag schließen Sie nach der Eintragung beim Immobilienmakler. Die Beamten fragen im Termin danach.</p></div>` : ''}`;
  }

  function stepConcept(w) {
    if (w.kind === 'fraktion') {
      const s = w.statute;
      return html`<div class="stack">
        ${c.field('wiz-purpose', 'Zweck der Organisation', html`<textarea id="wiz-purpose" data-bind="ui.wiz.statute.purpose" data-after="wiz-light" placeholder="Wofür gibt es die Organisation? Was tun die Mitglieder gemeinsam?">${s.purpose}</textarea>`, { req: true, hint: html`<span data-partial="wiz-c1">${c.counter(s.purpose.trim().length, 80)}</span>` })}
        ${c.field('wiz-goals', 'Ziele und Aktivitäten', html`<textarea id="wiz-goals" data-bind="ui.wiz.statute.goals" placeholder="Treffen, Veranstaltungen, Projekte …">${s.goals}</textarea>`)}
        ${c.field('wiz-adm', 'Aufnahme von Mitgliedern', html`<input id="wiz-adm" type="text" data-bind="ui.wiz.statute.admission" value="${s.admission}" placeholder="Wie wird man Mitglied?">`)}
        ${c.callout('info', 'Vorbereitung auf den Vorstellungstermin', 'Der Vorstand trägt Zweck und Satzung den Beamten persönlich vor. Alle Gründungsmitglieder müssen anwesend sein.')}
      </div>`;
    }
    const s = w.concept;
    return html`<div class="stack">
      ${c.field('wiz-idea', 'Geschäftsidee', html`<textarea id="wiz-idea" data-bind="ui.wiz.concept.idea" data-after="wiz-light" placeholder="Was bieten Sie an, und warum wird es gebraucht?">${s.idea}</textarea>`, { req: true, hint: html`<span data-partial="wiz-c1">${c.counter(s.idea.trim().length, 80)}</span>` })}
      <div class="grid g2">
        ${c.field('wiz-aud', 'Zielgruppe', html`<input id="wiz-aud" type="text" data-bind="ui.wiz.concept.audience" value="${s.audience}" placeholder="Wer sind Ihre Kunden?">`)}
        ${c.field('wiz-offer', 'Angebot', html`<input id="wiz-offer" type="text" data-bind="ui.wiz.concept.offer" value="${s.offer}" placeholder="Produkte und Leistungen">`)}
        ${c.field('wiz-staff', 'Geplantes Personal', html`<input id="wiz-staff" type="text" data-bind="ui.wiz.concept.staff" value="${s.staff}" placeholder="Wie viele Mitarbeiter?">`)}
        ${c.field('wiz-hours', 'Öffnungszeiten', html`<input id="wiz-hours" type="text" data-bind="ui.wiz.concept.hours" value="${s.hours}" placeholder="Wann sind Sie erreichbar?">`)}
      </div>
      ${c.callout('info', 'Vorbereitung auf den Vorstellungstermin', 'Sie stellen Ihr Unternehmen den Beamten persönlich vor. Rechnen Sie mit Fragen zu Geschäftsmodell, Standort, Personal und Gesellschaftsvertrag.')}
    </div>`;
  }

  function stepReview(w) {
    const d = S.d;
    const fe = fees(w);
    const el = d.eligibility[w.kind];
    const f = formOf(w.legalForm), b = w.branch ? branchOf(w.branch) : null;
    return html`<div class="stack lg">
      <div class="grid g2">
        ${c.sheet('Angaben', c.kv([
          ['Name', w.nameResult ? w.nameResult.display : w.name],
          [w.kind === 'fraktion' ? 'Art' : 'Rechtsform', f.label],
          b ? ['Branche', b.label] : null,
          ['Gründer', w.founders.map((x) => x.name + ' (' + L.MEMBER_ROLE[x.role] + (x.share != null ? ', ' + x.share + ' %' : '') + ')').join(', ')],
          ['Standort', w.property.mode === 'immobilie' ? w.property.label : 'Ohne festen Standort'],
        ]), { icon: 'doc' })}
        ${c.sheet('Zahlung', html`
          <div class="sum-row"><span>Antragsgebühr <span class="xs muted">(nicht erstattbar)</span></span><span class="v">${money(w.resubmit ? 0 : fe.apply)}</span></div>
          <div class="sum-row"><span>Eintragungsgebühr <span class="xs muted">(Vorauszahlung, erstattbar)</span></span><span class="v">${money(w.resubmit ? 0 : fe.register)}</span></div>
          ${fe.capital ? html`<div class="sum-row"><span>Kapital in Verwahrung <span class="xs muted">(erstattbar)</span></span><span class="v">${money(w.resubmit ? 0 : fe.capital)}</span></div>` : ''}
          <div class="sum-row total"><span>Jetzt fällig</span><span class="v">${money(w.resubmit ? 0 : fe.payNow)}</span></div>
          <div class="xs muted" style="margin-top:6px">Kontostand ${money(d.me.bank)}, danach ${money(d.me.bank - (w.resubmit ? 0 : fe.payNow))}.</div>`, { icon: 'coin' })}
      </div>
      ${c.sheet('Voraussetzungen', html`<ul class="checklist">${el.checks.map((k) => html`<li><label style="cursor:default"><span class="chip ${k.ok ? 'ok' : 'bad'}">${ico(k.ok ? 'check' : 'x')}</span><span>${k.text}</span></label></li>`)}</ul>`, { icon: 'shield' })}
      ${w.kind === 'fraktion' ? html`<div class="ooc" role="group" aria-label="OOC-Angaben">
        <div class="ooc-label">${ico('lock')}OOC-Angaben · nur für den Staff sichtbar</div>
        <p class="small muted" style="margin-bottom:12px">Diese Angaben sehen Beamte nie. Sie helfen dem Staff bei Kapazitäten und Freischaltungen. Sie sind kein Teil Ihres Rollenspiels.</p>
        <div class="stack">
          ${c.field('wiz-oocc', 'Fraktionsart', html`<select id="wiz-oocc" data-bind="ui.wiz.ooc.category" data-after="wiz-ooc-cat"><option value="legal" ${sel(w.ooc.category === 'legal')}>Legale Organisation</option>${d.settings.undergroundViaPortal ? html`<option value="untergrund" ${sel(w.ooc.category === 'untergrund')}>Untergrund-Gruppierung (Gang, MC, Mafia, Kartell)</option>` : ''}</select>`)}
          <div data-partial="wiz-ooc-hint">${IC.partials['wiz-ooc-hint']()}</div>
          ${c.field('wiz-oocn', 'Konzept in Stichpunkten', html`<textarea id="wiz-oocn" data-bind="ui.wiz.ooc.note" placeholder="Geplante Aktivitäten, Ziele, Revierwunsch …">${w.ooc.note}</textarea>`)}
          ${c.field('wiz-oocm', 'Geplante Mitgliederzahl', html`<input id="wiz-oocm" type="text" data-bind="ui.wiz.ooc.members" value="${w.ooc.members}" placeholder="z. B. 12">`)}
        </div></div>` : ''}
      <label class="check"><input id="wiz-confirm" type="checkbox" data-bind="ui.wiz.confirm" data-after="wiz-light" ${w.confirm ? raw('checked') : ''}><span>Ich versichere, dass meine Angaben wahrheitsgemäß sind. Mir ist bekannt, dass falsche Angaben zur Ablehnung oder zum Entzug der Eintragung führen können.</span></label>
    </div>`;
  }
  IC.partials['wiz-ooc-hint'] = function () {
    const w = W();
    return w.ooc.category === 'untergrund'
      ? c.callout('warn', 'Untergrund-Gruppierung', 'Sie melden IC eine legale Hülle an (zum Beispiel einen Verein). Die Freischaltung der Fraktionsmechaniken erfolgt erst nach einer Schlussprüfung durch den Staff und hängt von freien Plätzen ab.')
      : html``;
  };

  function wizDone(w) {
    const dn = w.done;
    return html`<div class="stack lg">
      <div class="sheet"><div class="sheet-b" style="text-align:center;padding:38px 20px">
        ${c.stamp('blue', 'Eingereicht', true)}
        <h2 style="margin-top:22px">Antrag ${dn.caseNo} ist eingegangen</h2>
        <p class="muted" style="margin-top:6px">Der Name „${dn.name}“ ist ${S.d.config.rules.nameReserveDays} Tage für Sie reserviert. ${dn.paid ? money(dn.paid) + ' wurden von Ihrem Konto abgebucht.' : 'Es wurden keine weiteren Gebühren erhoben.'}</p>
      </div></div>
      ${c.sheet('Wie geht es weiter?', html`<ol class="timeline">
        <li class="tl-item cur"><span class="tl-dot">${ico('doc')}</span><div><div class="tl-t">Vorprüfung durch die Beamten</div><div class="tl-m">Ziel: innerhalb von 48 Stunden. Sie werden benachrichtigt.</div></div></li>
        <li class="tl-item todo"><span class="tl-dot">${ico('calendar')}</span><div><div class="tl-t">Vorstellungstermin im Bürgeramt buchen</div><div class="tl-m">Nur möglich, wenn Beamte im Dienst sind oder Sprechzeiten bestehen.</div></div></li>
        <li class="tl-item todo"><span class="tl-dot">${ico('users')}</span><div><div class="tl-t">Termin wahrnehmen und vorstellen</div><div class="tl-m">Alle Pflichtteilnehmer müssen anwesend sein.</div></div></li>
        <li class="tl-item todo"><span class="tl-dot">${ico('stamp')}</span><div><div class="tl-t">Entscheidung und Eintragung</div><div class="tl-m">Bei Genehmigung erhalten Sie Registernummer und Gewerbeschein.</div></div></li>
      </ol>`, { icon: 'list' })}
      <div class="btn-row"><button class="btn primary" data-act="app-open" data-id="${dn.id}">Antrag ansehen</button><button class="btn" data-act="wiz-restart">Weiteren Antrag stellen</button><button class="btn ghost" data-act="view" data-view="home">Zur Startseite</button></div>
    </div>`;
  }

  function wizard() {
    const w = W();
    if (w.done) return html`<div class="page-head"><div><div class="crumbs">Gewerbeamt · Gründung</div><h1>Antrag eingereicht</h1></div></div>${wizDone(w)}`;
    const labels = STEPS[w.kind || 'unternehmen'];
    const body = [stepArt, stepName, stepFounders, stepSite, stepConcept, stepReview][w.step](w);
    return html`
      <div class="page-head"><div><div class="crumbs">Gewerbeamt · Gründung${w.resubmit ? ' · Nachbesserung' : ''}</div><h1>${w.kind === 'fraktion' ? 'Organisation gründen' : w.kind === 'unternehmen' ? 'Unternehmen gründen' : 'Gründung starten'}</h1>
        <p class="sub">${w.resubmit ? 'Bitte überarbeiten Sie den Antrag entsprechend dem Hinweis der Beamten und reichen Sie ihn erneut ein.' : 'In sechs Schritten zum Antrag. Alle Eingaben werden sofort geprüft. Sie können jederzeit einen Entwurf speichern.'}</p></div></div>
      ${w.resubmit && S.ui.wizRemark ? c.callout('warn', 'Hinweis der Beamten', S.ui.wizRemark) : ''}
      <nav class="stepper" aria-label="Schritte">${labels.map((l, i) => html`${i ? html`<span class="step-link ${i <= w.step ? 'done' : ''}"></span>` : ''}<button class="step ${i < w.step ? 'done' : i === w.step ? 'cur' : ''}" data-act="wiz-goto" data-step="${i}" ${i > w.maxStep ? raw('disabled') : ''} ${i === w.step ? raw('aria-current="step"') : ''}><span class="sn">${i < w.step ? ico('check') : i + 1}</span><span class="hide-sm">${l}</span></button>`)}</nav>
      <div class="split">
        <div class="stack">
          ${c.sheet((w.step + 1) + '. ' + labels[w.step], html`<div class="stack">${body}</div>`, { icon: ['building', 'edit', 'users', 'pin', 'doc', 'stamp'][w.step] })}
          <div class="stack sm" data-partial="wiz-nav">${IC.partials['wiz-nav']()}</div>
        </div>
        <aside class="sticky" data-partial="wiz-side">${IC.partials['wiz-side']()}</aside>
      </div>`;
  }

  /* ----- Aktionen des Wizards ----- */
  const lightRefresh = () => IC.refresh('wiz-side', 'wiz-nav', 'wiz-share', 'wiz-c1');
  const nameTimer = { t: null };
  function runNameCheck() {
    const w = W();
    const key = w.name.trim() + '|' + w.legalForm;
    if (w.name.trim().length < 3) { w.nameResult = null; w.nameFor = null; IC.refresh('wiz-name', 'wiz-side', 'wiz-nav'); return; }
    IC.api('nameCheck', { name: w.name.trim(), legalForm: w.legalForm, ignoreAppId: w.id }).then((r) => {
      const cur = W();
      if (cur !== w || cur.name.trim() + '|' + cur.legalForm !== key) return;
      cur.nameResult = r; cur.nameFor = key;
      IC.refresh('wiz-name', 'wiz-side', 'wiz-nav');
    });
  }
  function evenShares(w) {
    if (w.kind !== 'unternehmen') return;
    const n = w.founders.length, base = Math.floor(100 / n);
    w.founders.forEach((x) => { x.share = base; });
    w.founders[0].share += 100 - base * n;
  }
  /* Fragt solange nach, bis jeder eingeladene Mitgründer geantwortet hat. Die Antwort kommt vom Server, nie aus dem Browser. */
  const pollTimer = { t: null };
  function pollFounders() {
    clearTimeout(pollTimer.t);
    const w = W();
    if (!w.founders.some((x) => x.consent === 'pending')) return;
    pollTimer.t = setTimeout(async () => {
      if (W() !== w || S.app !== 'gewerbeamt') return;
      const r = await IC.api('founderStatus', {});
      if (r && r.ok && W() === w) {
        let changed = false;
        w.founders.slice().forEach((f) => {
          const st = r.statuses[f.charId];
          if (f.consent !== 'pending') return;
          if (st === 'ok') { f.consent = 'ok'; changed = true; IC.toast(f.name + ' hat zugestimmt.', 'ok'); }
          else if (st === 'no' || st === 'expired') {
            w.founders = w.founders.filter((x) => x !== f); evenShares(w); changed = 'render';
            IC.toast(f.name + (st === 'no' ? ' hat die Einladung abgelehnt.' : ' hat nicht rechtzeitig geantwortet.'), 'warn');
          }
        });
        if (changed === 'render') IC.render(); else if (changed) IC.refresh('wiz-founders', 'wiz-side', 'wiz-nav');
      }
      pollFounders();
    }, 800);
  }

  function fixRoles(w) {
    if (w.kind !== 'unternehmen') return;
    const single = w.legalForm === 'einzel';
    w.founders.forEach((x, i) => {
      if (single) x.role = 'inhaber';
      else if (x.role === 'inhaber') x.role = i === 0 ? 'geschaeftsfuehrer' : 'gesellschafter';
    });
  }

  Object.assign(IC.act, {
    'wiz-start': (el) => { S.ui.wiz = newWiz(el.dataset.kind); S.ui.wizRemark = null; IC.view('wizard'); },
    'wiz-restart': () => { S.ui.wiz = newWiz(null); IC.view('wizard'); },
    'wiz-kind': (el) => {
      const w = W();
      if (w.kind === el.dataset.kind) return;
      const keep = { id: w.id };
      Object.assign(w, newWiz(el.dataset.kind), keep);
      IC.render();
    },
    'wiz-branch': (el) => { const w = W(); w.branch = el.dataset.key; IC.render(); },
    'wiz-form': (el) => {
      const w = W();
      w.legalForm = el.dataset.key;
      const f = formOf(w.legalForm);
      if (f.key === 'einzel') { w.founders = w.founders.slice(0, 1); w.founders[0].share = 100; }
      fixRoles(w); evenShares(w);
      w.nameResult = null; w.nameFor = null;
      IC.render();
      if (w.name.trim().length >= 3) runNameCheck();
    },
    'wiz-name-input': () => {
      const w = W();
      w.nameResult = null; w.nameFor = null;
      IC.refresh('wiz-name', 'wiz-side', 'wiz-nav');
      clearTimeout(nameTimer.t);
      nameTimer.t = setTimeout(runNameCheck, 280);
    },
    'wiz-light': lightRefresh,
    'wiz-ooc-cat': () => { IC.refresh('wiz-ooc-hint'); },
    'wiz-add-founder': async (el) => {
      const w = W();
      const p = S.d.nearby.find((x) => x.charId === el.dataset.id);
      if (!p || w.founders.some((x) => x.charId === p.charId)) return;
      const r = await IC.api('founderInvite', { charId: p.charId });
      if (!r.ok) { IC.toast(r.error || 'Die Einladung ist nicht möglich.', 'bad'); return; }
      w.founders.push({ charId: p.charId, name: p.name, role: w.kind === 'fraktion' ? 'mitglied' : 'gesellschafter', share: w.kind === 'fraktion' ? null : 0, consent: 'pending' });
      evenShares(w);
      IC.render();
      IC.toast('Einladung an ' + p.name + ' gesendet. Die Zustimmung kommt direkt vom Mitgründer.', '');
      pollFounders();
    },
    'wiz-remove-founder': (el) => {
      const w = W();
      const f = w.founders[Number(el.dataset.idx)];
      if (f && f.consent !== 'self') IC.api('founderCancel', { charId: f.charId });
      w.founders.splice(Number(el.dataset.idx), 1); evenShares(w); IC.render();
    },
    'wiz-even': () => { evenShares(W()); IC.render(); },
    'wiz-site-mode': (el) => { const w = W(); w.property = { mode: el.dataset.mode, id: null, label: '' }; IC.render(); },
    'wiz-prop': (el) => {
      const w = W();
      const p = S.d.properties.find((x) => x.id === el.dataset.id);
      w.property = { mode: 'immobilie', id: p.id, label: p.label + ', ' + p.district };
      IC.render();
    },
    'wiz-goto': (el) => { const w = W(); const n = Number(el.dataset.step); if (n <= w.maxStep) { w.step = n; IC.render(); } },
    'wiz-prev': () => { const w = W(); if (w.step > 0) { w.step--; IC.render(); } },
    'wiz-next': () => {
      const w = W();
      const iss = issues(w, w.step);
      if (iss.length) { IC.toast(iss[0], 'warn'); return; }
      w.step++; w.maxStep = Math.max(w.maxStep, w.step);
      IC.render();
      if (w.step === 1 && w.name.trim().length >= 3 && !w.nameResult) runNameCheck();
    },
    'wiz-save': async () => {
      const w = W();
      if (!w.kind) { IC.toast('Wählen Sie zuerst, was Sie gründen möchten.', 'warn'); return; }
      const r = await IC.run('appSave', { draft: draftOf(w) }, { ok: 'Entwurf gespeichert. Sie finden ihn unter „Meine Anträge“.', noReload: true });
      if (r.ok) { w.id = r.id; await IC.reload(); }
    },
    'wiz-submit': async () => {
      const w = W();
      const fe = fees(w);
      const pay = w.resubmit ? 0 : fe.payNow;
      const yes = await IC.confirm({
        title: 'Antrag verbindlich einreichen?', icon: 'stamp', yes: pay ? money(pay) + ' bezahlen und einreichen' : 'Erneut einreichen',
        text: pay ? 'Es werden ' + money(pay) + ' von Ihrem Konto abgebucht. Die Antragsgebühr von ' + money(fe.apply) + ' wird nicht erstattet. ' + money(fe.refundable) + ' erhalten Sie zurück, wenn der Antrag abgelehnt oder zurückgezogen wird.' : 'Der Antrag geht erneut zur Vorprüfung. Es entstehen keine weiteren Gebühren.',
      });
      if (!yes) return;
      w.errors = [];
      S.busy = true;
      const r = await IC.api('appSubmit', { draft: draftOf(w) });
      S.busy = false;
      if (!r.ok) {
        w.errors = r.errors || [{ text: r.error }];
        IC.toast(r.error || 'Das hat nicht geklappt.', 'bad');
        IC.refresh('wiz-nav');
        return;
      }
      w.done = { id: r.id, caseNo: r.caseNo, name: r.name, paid: r.paid };
      await IC.reload();
    },
    'wiz-edit': async (el) => {
      const a = S.d.myApplications.find((x) => x.id === el.dataset.id);
      if (!a) return;
      const w = newWiz(a.kind);
      const f = formOf(a.legalForm);
      Object.assign(w, {
        id: a.id, legalForm: a.legalForm, branch: a.branch, name: rawName(a.name || '', f), founders: IC.clone(a.founders).map((x) => Object.assign(x, { consent: x.charId === S.d.me.charId ? 'self' : 'ok' })),
        property: a.property ? IC.clone(a.property) : w.property, concept: a.concept ? IC.clone(a.concept) : w.concept, statute: a.statute ? IC.clone(a.statute) : w.statute, ooc: a.ooc ? IC.clone(a.ooc) : w.ooc,
        resubmit: a.status === 'nachbesserung', maxStep: 5, step: 0,
      });
      S.ui.wiz = w;
      S.ui.wizRemark = a.status === 'nachbesserung' ? a.remark : null;
      IC.view('wizard');
      runNameCheck();
    },
  });

  /* ====================================================================
     Meine Anträge
     ==================================================================== */
  function appDetail(a) {
    const d = S.d;
    const dec = a.decision;
    const canObject = a.status === 'abgelehnt' && a.objectionUntil > IC.now();
    const f = formOf(a.legalForm), b = a.branch ? branchOf(a.branch) : null;
    return html`<div class="stack">
      <div class="spread"><div><h2>${a.name || 'Entwurf'}</h2><div class="row sm" style="margin-top:6px">${a.caseNo ? c.tag(a.caseNo) : ''}${c.appChip(a.status)}${a.priority ? c.chip('Vorrang', 'info') : ''}</div></div></div>
      ${a.status !== 'entwurf' ? c.phases(a) : ''}
      ${a.status === 'nachbesserung' ? c.callout('warn', 'Nachbesserung erforderlich', a.remark, 'edit', html`<button class="btn sm primary" data-act="wiz-edit" data-id="${a.id}">Antrag bearbeiten</button>`) : ''}
      ${a.status === 'vorpruefung_ok' ? c.callout('ok', 'Vorprüfung bestanden', 'Buchen Sie jetzt Ihren Vorstellungstermin im Bürgeramt.', 'calendar', html`<button class="btn sm primary" data-act="app-book" data-id="${a.id}">Termin buchen</button>`) : ''}
      ${dec ? html`<div class="sheet"><div class="sheet-b"><div class="row top" style="gap:20px"><div class="grow">
          <h4>Bescheid</h4><p style="margin-top:6px">${dec.reason || 'Ohne Begründung genehmigt.'}</p>
          ${dec.conditions && dec.conditions.length ? html`<h4 style="margin-top:12px">Auflagen</h4><ul>${dec.conditions.map((x) => html`<li>${x}</li>`)}</ul>` : ''}
          <p class="small muted" style="margin-top:8px">${dec.by} · ${IC.fdt(dec.at)}</p></div>
          <div>${c.stamp(L.DECISION[dec.decision].stamp, L.DECISION[dec.decision].word, false)}</div></div></div></div>` : ''}
      ${canObject ? c.callout('warn', 'Einspruch möglich bis ' + IC.fdt(a.objectionUntil), 'Sie können der Ablehnung widersprechen. Ein Amtsleiter prüft den Fall in einer Einspruchsverhandlung.', 'scale', html`<button class="btn sm primary" data-act="app-objection-open" data-id="${a.id}">Einspruch einlegen</button>`) : ''}
      ${c.sheet('Angaben', c.kv([
        ['Art', f ? f.label : '–'], b ? ['Branche', b.label] : null,
        ['Gründer', a.founders.map((x) => x.name + ' (' + L.MEMBER_ROLE[x.role] + (x.share != null ? ', ' + x.share + ' %' : '') + ')').join(', ')],
        ['Standort', IC.siteLabel(a.property)],
        a.fees ? ['Gebühren', money(a.fees.apply) + ' Antrag, ' + money(a.fees.register) + ' Eintragung' + (a.fees.capital ? ', ' + money(a.fees.capital) + ' Kapital' : '')] : null,
        a.reservedUntil && L.OPEN_APP.indexOf(a.status) !== -1 ? ['Name reserviert bis', IC.fdate(a.reservedUntil)] : null,
      ]), { icon: 'doc' })}
      ${a.events.length ? c.sheet('Verlauf', c.timeline(a.events, L.APP[a.status] && (L.APP[a.status].neg || a.status === 'genehmigt')), { icon: 'clock' }) : ''}
      <div class="btn-row">${a.status === 'entwurf' ? html`<button class="btn primary" data-act="wiz-edit" data-id="${a.id}">Entwurf fortsetzen</button><button class="btn danger" data-act="app-withdraw" data-id="${a.id}">Entwurf löschen</button>` : ''}
        ${L.OPEN_APP.indexOf(a.status) !== -1 ? html`<button class="btn danger" data-act="app-withdraw" data-id="${a.id}">Antrag zurückziehen</button>` : ''}</div>
    </div>`;
  }

  function apps() {
    const d = S.d;
    const list = d.myApplications;
    const selId = S.ui.appSel && list.some((a) => a.id === S.ui.appSel) ? S.ui.appSel : (list[0] && list[0].id);
    const cur = list.find((a) => a.id === selId);
    return html`
      <div class="page-head"><div><div class="crumbs">Gewerbeamt · Anträge</div><h1>Meine Anträge</h1><p class="sub">Alle Gründungsanträge mit Status, Hinweisen und Bescheiden.</p></div>
        <div class="btn-row"><button class="btn primary" data-act="wiz-start" data-kind="unternehmen">${ico('plus')}Unternehmen</button><button class="btn" data-act="wiz-start" data-kind="fraktion">${ico('plus')}Organisation</button></div></div>
      ${list.length ? html`<div class="split" style="grid-template-columns:340px minmax(0,1fr)">
        <div class="stack sm" role="list" aria-label="Anträge">${list.map((a) => html`<button class="pick" role="listitem" data-act="app-open" data-id="${a.id}" ${pressed(a.id === selId)}>
          <span class="pk-t">${a.name || 'Entwurf'}</span><span class="pk-m">${c.appChip(a.status)}${a.caseNo ? c.tag(a.caseNo) : ''}</span>
          <span class="pk-d">${nextStep(a).text}</span></button>`)}</div>
        <div>${cur ? appDetail(cur) : ''}</div></div>`
        : c.sheet('Keine Anträge', c.empty('doc', 'Noch keine Anträge', 'Starten Sie eine Gründung. Sie können jederzeit einen Entwurf speichern.', html`<button class="btn primary" data-act="wiz-start" data-kind="unternehmen">Unternehmen gründen</button>`))}`;
  }

  Object.assign(IC.act, {
    'app-open': (el) => { S.ui.appSel = el.dataset.id; if (S.app !== 'gewerbeamt') IC.go('gewerbeamt', 'apps'); else IC.view('apps'); },
    'app-book': (el) => {
      const a = S.d.myApplications.find((x) => x.id === el.dataset.id);
      S.ui.book = { typeId: a.status === 'einspruch' ? 'einspruch' : a.kind === 'fraktion' ? 'vorstellung_fraktion' : 'vorstellung_unternehmen', applicationId: a.id, entityId: null, day: 0, slot: null, attendees: null, note: '' };
      IC.go('buergeramt', 'book');
    },
    'app-withdraw': async (el) => {
      const a = S.d.myApplications.find((x) => x.id === el.dataset.id);
      const draft = a.status === 'entwurf';
      const back = a.fees ? a.fees.register + a.fees.capital : 0;
      const yes = await IC.confirm({ title: draft ? 'Entwurf löschen?' : 'Antrag zurückziehen?', danger: true, yes: draft ? 'Löschen' : 'Zurückziehen',
        text: draft ? 'Der Entwurf wird endgültig gelöscht.' : 'Der Antrag wird beendet, der Name wird frei. Die Antragsgebühr' + (a.fees ? ' von ' + money(a.fees.apply) : '') + ' wird nicht erstattet' + (back ? ', ' + money(back) + ' erhalten Sie zurück.' : '.') });
      if (yes) await IC.run('appWithdraw', { id: a.id }, { ok: (r) => (r.deleted ? 'Entwurf gelöscht.' : 'Antrag zurückgezogen.') });
    },
    'app-objection-open': (el) => {
      S.ui.objText = '';
      IC.modal.open({
        title: 'Einspruch einlegen', icon: 'scale',
        body: html`<div class="stack">${c.field('obj-text', 'Begründung', html`<textarea id="obj-text" data-bind="ui.objText" placeholder="Warum ist die Ablehnung nicht gerechtfertigt? Gibt es neue Nachweise?"></textarea>`, { hint: 'Mindestens 20 Zeichen. Ein Amtsleiter prüft den Einspruch.' })}</div>`,
        footer: html`<button class="btn" data-act="modal-close">Abbrechen</button><button class="btn primary" data-act="app-objection-send" data-id="${el.dataset.id}">Einspruch absenden</button>`,
      });
    },
    'app-objection-send': async (el) => {
      const r = await IC.run('appObjection', { id: el.dataset.id, text: S.ui.objText }, { ok: 'Einspruch eingelegt. Sie können jetzt eine Verhandlung buchen.' });
      if (r.ok) IC.modal.close(true);
    },
  });

  /* ====================================================================
     Meine Eintragungen
     ==================================================================== */
  function entities() {
    const d = S.d;
    const list = d.myEntities.filter((e) => e.status !== 'aufgeloest');
    const gone = d.myEntities.filter((e) => e.status === 'aufgeloest');
    return html`
      <div class="page-head"><div><div class="crumbs">Gewerbeamt · Eintragungen</div><h1>Meine Eintragungen</h1><p class="sub">Unternehmen und Organisationen, bei denen Sie Inhaber, Geschäftsführer oder Vorstand sind.</p></div></div>
      ${list.length ? html`<div class="grid g2">${list.map((e) => {
        const f = formOf(e.legalForm), b = e.branch ? branchOf(e.branch) : null;
        const open = e.conditions.filter((x) => !x.done);
        return html`<article class="sheet"><div class="sheet-h">${ico(e.kind === 'fraktion' ? 'flag' : 'building')}<h3>${e.regNo}</h3><span class="sp"></span>${c.orgChip(e.status)}</div>
          <div class="sheet-b stack">
            <div><h2>${e.name}</h2><p class="muted small">${f ? f.label : ''}${b ? ' · ' + b.label : ''}</p></div>
            ${c.kv([['Sitz', e.hq], ['Eingetragen', IC.fdate(e.founded)], [e.kind === 'fraktion' ? 'Prüfung bis' : 'Gewerbeschein bis', IC.fdate(e.validUntil)], ['Mitglieder', e.memberCount]])}
            ${e.pendingChange ? c.callout('info', 'Änderung beantragt', 'Neuer ' + (e.pendingChange.type === 'name' ? 'Name' : 'Sitz') + ': ' + e.pendingChange.value + '. Wird im Änderungstermin beurkundet.', 'edit') : ''}
            ${e.legacy && !e.legacyConfirmed ? c.callout('warn', 'Bestandsbestätigung offen', 'Bitte bis ' + IC.fdate(e.legacyDue) + ' bestätigen.', 'shield', html`<button class="btn sm primary" data-act="legacy-confirm" data-id="${e.id}">Jetzt bestätigen</button>`) : ''}
            ${open.length ? c.callout('warn', open.length + ' offene ' + IC.plural(open.length, 'Auflage', 'Auflagen'), html`<ul>${open.map((x) => html`<li>${x.text} <span class="muted">(bis ${IC.fdate(x.due)})</span></li>`)}</ul>`, 'alert', html`<button class="btn sm" data-act="ent-nachkontrolle" data-id="${e.id}">Nachkontrolle buchen</button>`) : ''}
          </div>
          <div class="sheet-f"><button class="btn sm" data-act="ent-cert" data-id="${e.id}">${ico('doc')}Gewerbeschein</button><button class="btn sm" data-act="ent-change-open" data-id="${e.id}">${ico('edit')}Änderung</button><button class="btn sm danger" data-act="ent-dissolve" data-id="${e.id}">Auflösen</button></div>
        </article>`;
      })}</div>` : c.sheet('Keine Eintragungen', c.empty('folder', 'Noch nichts eingetragen', 'Nach der Genehmigung Ihres Antrags erscheint Ihr Unternehmen hier mit Gewerbeschein.', html`<button class="btn primary" data-act="view" data-view="wizard">Gründung starten</button>`))}
      ${gone.length ? c.sheet('Aufgelöst', html`<div class="stack sm">${gone.map((e) => html`<div class="spread"><span>${e.name} ${c.tag(e.regNo)}</span><span class="muted small">aufgelöst ${IC.fdate(e.dissolvedAt || e.founded)}</span></div>`)}</div>`, { icon: 'folder' }) : ''}`;
  }

  Object.assign(IC.act, {
    'legacy-confirm': async (el) => { await IC.run('legacyConfirm', { id: el.dataset.id }, { ok: 'Danke, Ihre Bestandsdaten sind bestätigt.' }); },
    'ent-cert': (el) => {
      const e = S.d.myEntities.find((x) => x.id === el.dataset.id) || (S.ui.regRows || []).find((x) => x.id === el.dataset.id);
      if (!e) return;
      IC.modal.open({ title: e.kind === 'fraktion' ? 'Eintragungsurkunde' : 'Gewerbeschein', icon: 'doc', wide: true, body: c.cert(e, cfg()),
        footer: e.myOwn ? html`<button class="btn" data-act="modal-close">Schließen</button><button class="btn primary" data-act="ent-duplicate" data-id="${e.id}">${ico('doc')}Duplikat für ${money(cfg().rules.feeDuplicate)} ausstellen</button>` : html`<button class="btn" data-act="modal-close">Schließen</button>` });
    },
    'ent-duplicate': async (el) => { const r = await IC.run('entityDuplicate', { id: el.dataset.id }, { ok: 'Duplikat ausgestellt und Ihrem Inventar hinzugefügt.' }); if (r.ok) IC.modal.close(true); },
    'ent-change-open': (el) => {
      S.ui.chg = { type: 'name', value: '' };
      IC.modal.open({
        title: 'Änderung beantragen', icon: 'edit',
        body: html`<div class="stack"><div class="callout info">${ico('info')}<div>Die Änderung kostet ${money(cfg().rules.feeChange)} und wird in einem Änderungstermin im Bürgeramt beurkundet.</div></div>
          ${c.field('chg-type', 'Was soll geändert werden?', html`<select id="chg-type" data-bind="ui.chg.type"><option value="name">Name</option><option value="sitz">Sitz</option></select>`)}
          ${c.field('chg-value', 'Neuer Wert', html`<input id="chg-value" type="text" maxlength="60" data-bind="ui.chg.value" placeholder="Neuer Name oder neuer Sitz">`)}</div>`,
        footer: html`<button class="btn" data-act="modal-close">Abbrechen</button><button class="btn primary" data-act="ent-change-send" data-id="${el.dataset.id}">${money(cfg().rules.feeChange)} bezahlen und beantragen</button>`,
      });
    },
    'ent-change-send': async (el) => {
      const r = await IC.run('entityChange', { id: el.dataset.id, type: S.ui.chg.type, value: S.ui.chg.value }, { ok: 'Änderung beantragt. Buchen Sie den Änderungstermin im Bürgeramt.' });
      if (r.ok) IC.modal.close(true);
    },
    'ent-dissolve': async (el) => {
      const e = S.d.myEntities.find((x) => x.id === el.dataset.id);
      const yes = await IC.confirm({ title: '„' + e.name + '“ auflösen?', danger: true, yes: 'Endgültig auflösen', text: 'Der Eintrag wird beendet und der Name nach ' + 7 + ' Tagen wieder frei. Das lässt sich nicht rückgängig machen.' });
      if (yes) await IC.run('entityDissolve', { id: e.id }, { ok: 'Der Eintrag wurde aufgelöst.' });
    },
    'ent-nachkontrolle': (el) => {
      S.ui.book = { typeId: 'nachkontrolle', applicationId: null, entityId: el.dataset.id, day: 0, slot: null, attendees: null, note: '' };
      IC.go('buergeramt', 'book');
    },
  });

  /* ====================================================================
     Handelsregister
     ==================================================================== */
  function register() {
    const r = S.ui.reg || (S.ui.reg = { q: '', kind: '' });
    IC.after(() => { if (!S.ui.regRows) IC.act['reg-search'](); });
    return html`
      <div class="page-head"><div><div class="crumbs">Gewerbeamt · Auskunft</div><h1>Handelsregister</h1><p class="sub">Öffentliche Auskunft über alle eingetragenen Unternehmen und Organisationen.</p></div></div>
      <div class="sheet"><div class="sheet-b"><div class="row" style="align-items:flex-end">
        <div class="field grow" style="min-width:220px"><label for="reg-q">Suche</label><input id="reg-q" type="search" placeholder="Name, Registernummer oder Inhaber" value="${r.q}" data-bind="ui.reg.q" data-after="reg-search-debounced"></div>
        <div class="seg" role="group" aria-label="Art">${[['', 'Alle'], ['unternehmen', 'Unternehmen'], ['fraktion', 'Organisationen']].map((k) => html`<button data-act="reg-kind" data-kind="${k[0]}" ${pressed(r.kind === k[0])}>${k[1]}</button>`)}</div>
      </div></div></div>
      <div class="sheet"><div class="sheet-b flush tbl-wrap" data-partial="reg-rows">${IC.partials['reg-rows']()}</div></div>`;
  }
  IC.partials['reg-rows'] = function () {
    const rows = S.ui.regRows;
    if (!rows) return html`<div class="empty">${ico('clock')}<h3>Register wird geladen …</h3></div>`;
    if (!rows.length) return c.empty('search', 'Keine Treffer', 'Zu Ihrer Suche gibt es keinen Eintrag.');
    return html`<table class="tbl"><thead><tr><th>Name</th><th>Nr.</th><th>Art</th><th>Sitz</th><th>Status</th><th></th></tr></thead><tbody>${rows.map((e) => {
      const f = formOf(e.legalForm), b = e.branch ? branchOf(e.branch) : null;
      return html`<tr><td><div class="strong">${e.name}</div><div class="sub">${e.owner}</div></td><td>${c.tag(e.regNo)}</td><td>${f ? f.label : ''}<div class="sub">${b ? b.label : 'Organisation'}</div></td><td>${e.hq}</td><td>${c.orgChip(e.status)}</td><td class="act"><button class="btn sm ghost" data-act="ent-cert" data-id="${e.id}">Auszug</button></td></tr>`;
    })}</tbody></table>`;
  };
  const regDebounce = IC.debounce(() => IC.act['reg-search'](), 250);
  Object.assign(IC.act, {
    'reg-search': async () => {
      const r = S.ui.reg || (S.ui.reg = { q: '', kind: '' });
      const res = await IC.api('registerSearch', { q: r.q, kind: r.kind });
      if (res.ok) { S.ui.regRows = res.rows; IC.refresh('reg-rows'); }
    },
    'reg-search-debounced': () => regDebounce(),
    'reg-kind': async (el) => { S.ui.reg.kind = el.dataset.kind; await IC.act['reg-search'](); IC.render(); },
  });

  /* ====================================================================
     Gebühren und Regeln
     ==================================================================== */
  function feesView() {
    const d = S.d, R = cfg().rules;
    return html`
      <div class="page-head"><div><div class="crumbs">Gewerbeamt · Auskunft</div><h1>Gebühren und Regeln</h1><p class="sub">Alles, was Sie vor einer Gründung wissen sollten. Alle Gebühren fließen in die Stadtkasse.</p></div></div>
      ${c.sheet('Rechtsformen und Gebühren', html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Rechtsform</th><th class="right">Mind. Gründer</th><th class="right">Antrag</th><th class="right">Eintragung</th><th class="right">Kapital</th><th>Register</th></tr></thead><tbody>${cfg().legalForms.map((f) => html`<tr><td><div class="strong">${f.label}</div><div class="sub">${f.kind === 'fraktion' ? 'Organisation' : 'Unternehmen'}</div></td><td class="right num">${f.minFounders}</td><td class="right num">${money(f.feeApply)}</td><td class="right num">${money(f.feeRegister)}</td><td class="right num">${f.capital ? money(f.capital) : '–'}</td><td>${c.tag(f.register)}</td></tr>`)}</tbody></table></div>`, { icon: 'coin', flush: true })}
      ${c.sheet('Branchen', html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Branche</th><th>Standort</th><th>Zulassung</th><th>Prüfung</th><th class="right">Faktor</th><th>Plätze</th></tr></thead><tbody>${cfg().branches.map((b) => html`<tr><td><div class="strong">${b.label}</div><div class="sub">${b.desc}</div></td><td>${b.needsProperty ? 'Pflicht' : 'Optional'}</td><td>${b.authority || '–'}</td><td>${b.staffGate ? 'Schlussprüfung' : '–'}</td><td class="right num">×${String(b.factor).replace('.', ',')}</td><td style="min-width:150px">${c.meter(b.used, b.cap)}<span class="xs muted">${b.cap - b.used > 0 ? (b.cap - b.used) + ' von ' + b.cap + ' frei' : 'ausgelastet'}</span></td></tr>`)}</tbody></table></div>`, { icon: 'list', flush: true })}
      <div class="grid g2">
        ${c.sheet('Fristen', c.kv([
          ['Name reserviert', R.nameReserveDays + ' Tage ab Einreichung'], ['Nachbesserung', R.fixDays + ' Tage'], ['Termin buchen nach Vorprüfung', R.bookDays + ' Tage'],
          ['Einspruch nach Ablehnung', R.objectionHours + ' Stunden'], ['Gewerbeschein gültig', R.certDays + ' Tage'], ['Probezeit bei Auflagen', R.probationDays + ' Tage'],
        ]), { icon: 'clock' })}
        ${c.sheet('Voraussetzungen und Grenzen', c.kv([
          ['Mindestalter', R.minAge + ' Jahre'], ['Mindest-Spielzeit', R.minPlayHours + ' Stunden'], ['Offene Anträge', 'höchstens ' + R.maxOpenApplications], ['Aktive Unternehmen', 'höchstens ' + R.maxCompanies + ' als Inhaber'],
          ['Organisationen', 'höchstens ' + R.maxOrgs + ' als Gründer'], ['Offene Termine', 'höchstens ' + R.maxOpenAppointments],
          ['Strikes', R.strikeLimit + ' innerhalb von ' + R.strikeDays + ' Tagen führen zu ' + R.banDays + ' Tagen Sperre'],
        ]), { icon: 'shield' })}
      </div>`;
  }

  /* ====================================================================
     Registrierung der App
     ==================================================================== */
  IC.registerApp('gewerbeamt', {
    title: 'Gewerbeamt', icon: 'building', def: 'home',
    where: () => S.d.config.city + (S.env.nui ? '' : ' · Rathaus · Terminal 2'),
    nav: () => {
      const d = S.d;
      const open = d.myApplications.filter((a) => L.OPEN_APP.indexOf(a.status) !== -1).length;
      const needs = d.myApplications.some((a) => a.status === 'nachbesserung' || a.status === 'vorpruefung_ok');
      return [
        { id: 'home', label: 'Start', icon: 'home' },
        { id: 'wizard', label: 'Gründung starten', icon: 'plus' },
        { id: 'apps', label: 'Meine Anträge', icon: 'doc', badge: open || null, badgeKind: needs ? 'warn' : '' },
        { id: 'entities', label: 'Meine Eintragungen', icon: 'folder' },
        { head: 'Auskunft' },
        { id: 'register', label: 'Handelsregister', icon: 'search' },
        { id: 'fees', label: 'Gebühren und Regeln', icon: 'coin' },
      ];
    },
    railFoot: () => html`Das Terminal ist rund um die Uhr nutzbar. Entscheidungen treffen die Beamten nach Dienstplan.`,
    views: { home, wizard, apps, entities, register, fees: feesView },
  });
})();
