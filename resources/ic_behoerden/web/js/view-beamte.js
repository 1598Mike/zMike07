/* IC-Behördenportal · Beamten-Tablet: Termine führen, Vorprüfung, Sprechzeiten, Register */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico, money } = IC;
  const c = IC.c, L = IC.L, S = IC.S;
  const cfg = () => S.d.config;
  const typeOf = (k) => cfg().appointmentTypes.find((t) => t.key === k);
  const formOf = (k) => cfg().legalForms.find((f) => f.key === k);
  const branchOf = (k) => cfg().branches.find((b) => b.key === k);
  const O = () => S.d.official;
  const lvl = (r) => L.RANK[r].level;
  const pressed = (cond) => raw('aria-pressed="' + (cond ? 'true' : 'false') + '"');
  const OPEN = ['gebucht', 'eingecheckt', 'aufgerufen', 'laeuft'];
  const apptOf = (id) => S.d.officialAppts.find((a) => a.id === id);
  const appOf = (id) => S.d.officialApps.find((a) => a.id === id);
  const sameDay = (a, b) => IC.startOfDay(a) === IC.startOfDay(b);

  const QUESTIONS = {
    unternehmen: ['Was ist Ihre Geschäftsidee in einem Satz?', 'Wer sind Ihre Kunden, und warum kommen sie zu Ihnen?', 'Wie viele Mitarbeiter planen Sie, und wer führt das Tagesgeschäft?', 'Wie sieht der Standort aus, und liegt ein Mietvertrag vor?', 'Wie sind die Anteile verteilt, und wer vertritt das Unternehmen?', 'Was passiert bei Streit unter den Gesellschaftern?', 'Welche Zulassungen anderer Behörden benötigen Sie?', 'Wie sichern Sie Kasse und Ware?'],
    fraktion: ['Was ist der Zweck der Organisation?', 'Wie wird man Mitglied, und wer entscheidet darüber?', 'Wer sitzt im Vorstand, und wie wird gewählt?', 'Wo treffen Sie sich, und wie oft?', 'Wie finanziert sich die Organisation?', 'Wie gehen Sie mit Konflikten unter Mitgliedern um?'],
  };

  /* ====================================================================
     Dienstleiste
     ==================================================================== */
  function dutyBar() {
    const o = O(), d = S.d;
    S.ui.deskSel = S.ui.deskSel || o.desk;
    return html`<div class="sheet"><div class="sheet-b stack sm">
      <div class="spread">
        <div class="row">
          <div class="seg" role="group" aria-label="Dienststatus">${[['on', 'Im Dienst'], ['pause', 'Pause'], ['off', 'Außer Dienst']].map((x) => html`<button data-act="duty-set" data-state="${x[0]}" ${pressed(o.state === x[0])}>${x[1]}</button>`)}</div>
          <div class="row sm"><label class="lbl" for="duty-desk">Schalter</label><select id="duty-desk" style="width:auto" data-bind="ui.deskSel" data-after="duty-desk">${[1, 2, 3, 4].map((n) => html`<option value="${n}" ${Number(S.ui.deskSel) === n ? raw('selected') : ''}>${n}</option>`)}</select></div>
        </div>
        <div class="row sm"><span class="lbl">Kollegen im Dienst</span>${d.coworkers.length ? d.coworkers.map((x) => c.chip(x.name + ' · ' + L.RANK[x.rank].label + ' · Schalter ' + x.desk, 'ok')) : html`<span class="muted small">niemand</span>`}</div>
      </div>
      ${o.state !== 'on' ? c.callout('warn', 'Sie sind nicht im Dienst', 'Bürger können keine Live-Termine bei Ihnen buchen, und Sie können keine Entscheidungen treffen. Treten Sie den Dienst an, um zu arbeiten.', 'clock', html`<button class="btn sm primary" data-act="duty-set" data-state="on">Dienst antreten</button>`) : ''}
    </div></div>`;
  }

  function who(a) { return a.applicant ? a.applicant.name : ''; }

  /* ====================================================================
     Heute
     ==================================================================== */
  function apptRow(ap) {
    const o = O(), t = typeOf(ap.typeId);
    const app = ap.applicationId ? S.d.officialApps.find((a) => a.id === ap.applicationId) : null;
    const ent = ap.entityId ? S.d.register.find((e) => e.id === ap.entityId) : null;
    const rankOk = lvl(o.rank) >= lvl(t.minRank);
    const miss = ap.attendees.filter((x) => x.mandatory && !x.checkedIn);
    const lateAt = ap.start + cfg().rules.checkinAfter * IC.MIN;
    const canNoShow = IC.now() >= lateAt;
    return html`<article class="sheet"><div class="sheet-h">${ico('clock')}<h3>${IC.ftime(ap.start)}–${IC.ftime(ap.end)}</h3><span class="sp"></span>${c.apptChip(ap.status)}</div>
      <div class="sheet-b stack sm">
        <div class="spread"><div><div class="strong" style="font-size:17px">${t.label}</div><div class="small muted">${app ? app.name + ' · ' : ent ? ent.name + ' · ' : ''}${app ? app.caseNo : ap.id}${ap.status === 'gebucht' || ap.status === 'eingecheckt' ? ' · ' + IC.rel(ap.start) : ''}</div></div>${rankOk ? '' : c.chip('ab ' + L.RANK[t.minRank].label, 'warn', 'badge')}</div>
        <div class="row sm">${ap.attendees.map((x) => html`<span class="chip ${x.checkedIn ? 'ok' : ''}">${x.checkedIn ? ico('check') : ico('clock')}${x.name}${x.mandatory ? ' · Pflicht' : ''}</span>`)}</div>
        ${miss.length && ap.status !== 'laeuft' && OPEN.indexOf(ap.status) !== -1 ? html`<div class="small muted">Wartet auf ${miss.map((m) => m.name).join(', ')}.</div>` : ''}
        ${ap.note ? html`<div class="small"><span class="muted">Anmerkung:</span> ${ap.note}</div>` : ''}
      </div>
      ${OPEN.indexOf(ap.status) !== -1 ? html`<div class="sheet-f">
        ${ap.status === 'laeuft' ? html`<button class="btn primary" data-act="term-open" data-id="${ap.id}">${ico('play')}Termin fortsetzen</button>` : html`
          <button class="btn" data-act="appt-call" data-id="${ap.id}" ${o.state === 'on' && ap.status !== 'aufgerufen' ? '' : raw('disabled')}>${ico('bell')}Aufrufen</button>
          <button class="btn primary" data-act="appt-start" data-id="${ap.id}" ${o.state === 'on' && rankOk && !miss.length ? '' : raw('disabled')} title="${miss.length ? 'Pflichtteilnehmer fehlen noch' : ''}">${ico('play')}Termin starten</button>
          <button class="btn danger" data-act="appt-noshow" data-id="${ap.id}" ${o.state === 'on' && canNoShow ? '' : raw('disabled')} title="${canNoShow ? '' : 'Erst ab ' + IC.ftime(lateAt) + ' Uhr'}">Nicht erschienen</button>`}
      </div>` : ''}
    </article>`;
  }

  function today() {
    const d = S.d, o = O();
    const list = d.officialAppts;
    const open = list.filter((a) => OPEN.indexOf(a.status) !== -1);
    const done = list.filter((a) => OPEN.indexOf(a.status) === -1 && sameDay(a.start, IC.now()));
    return html`
      <div class="page-head"><div><div class="crumbs">Beamten-Tablet · Heute</div><h1>Termine und Warteraum</h1><p class="sub">Aufrufen, Termin starten, Checkliste abarbeiten und entscheiden.</p></div></div>
      ${dutyBar()}
      <div class="split" style="grid-template-columns:minmax(0,1fr) 340px">
        <div class="stack">
          ${open.length ? open.map(apptRow) : c.sheet('Offene Termine', c.empty('calendar', 'Keine offenen Termine', 'Sobald Bürger Termine buchen, erscheinen sie hier.'))}
          ${done.length ? c.sheet('Erledigt heute', html`<div class="tbl-wrap"><table class="tbl"><tbody>${done.map((a) => html`<tr><td class="num">${IC.ftime(a.start)}</td><td>${typeOf(a.typeId).label}</td><td>${a.bookerName}</td><td>${c.apptChip(a.status)}</td></tr>`)}</tbody></table></div>`, { icon: 'check', flush: true }) : ''}
        </div>
        <aside class="stack">
          ${c.sheet('Aufrufanzeige', html`<div class="board"><div class="lab">Aufruf</div><div class="big num">${d.board.calling ? d.board.calling.no : '---'}</div><div class="lab">${d.board.calling ? 'Schalter ' + d.board.calling.desk : 'kein Aufruf'}</div></div>`, { icon: 'bell' })}
          ${c.sheet('Warteschlange', d.queue.length ? html`<div class="stack sm">${d.queue.map((q, i) => html`<div class="spread"><span><span class="tag">${q.no}</span> ${q.who}</span><span class="muted small">${IC.rel(q.at)}</span></div>`)}</div>` : html`<p class="small muted">Niemand wartet.</p>`, { icon: 'ticket', footer: html`<button class="btn primary" data-act="queue-next" ${o.state === 'on' && d.queue.length ? '' : raw('disabled')}>Nächste Nummer aufrufen</button>` })}
        </aside>
      </div>`;
  }

  /* ====================================================================
     Termin führen
     ==================================================================== */
  const T = () => S.ui.term;
  IC.partials['term-check'] = function () {
    const t = T(), ap = apptOf(t.id), type = typeOf(ap.typeId);
    const list = cfg().checklists[type.key] || [];
    const done = list.filter((i) => t.checklist[i.key]).length;
    const must = list.filter((i) => !i.optional);
    const need = must.filter((i) => !t.checklist[i.key]).length;
    return html`<div class="spread" style="margin-bottom:6px"><span class="chip ${need ? 'warn' : 'ok'}">${done} von ${list.length} erledigt</span><span class="small muted">${need ? need + ' Pflichtpunkte offen' : 'Alle Pflichtpunkte erfüllt'}</span></div>
      <ul class="checklist">${list.map((i) => html`<li><label><input type="checkbox" data-act="chk-toggle" data-key="${i.key}" ${t.checklist[i.key] ? raw('checked') : ''}><span><span>${i.text}</span>${i.note ? html`<span class="ci-note" style="display:block">${i.note}</span>` : ''}</span></label></li>`)}</ul>`;
  };

  function decisionButtons(type) {
    if (type.key === 'beratung') return [['genehmigt', 'Beratung abschließen', 'ok']];
    if (type.key === 'aenderung') return [['genehmigt', 'Änderung beurkunden', 'ok'], ['abgelehnt', 'Änderung ablehnen', 'danger']];
    if (type.key === 'nachkontrolle') return [['genehmigt', 'Auflagen als erfüllt bestätigen', 'ok'], ['vertagt', 'Nicht erfüllt, vertagen', '']];
    if (type.key === 'einspruch') return [['genehmigt', 'Einspruch stattgeben', 'ok'], ['abgelehnt', 'Einspruch zurückweisen', 'danger']];
    return [['genehmigt', 'Genehmigen', 'ok'], ['auflagen', 'Mit Auflagen genehmigen', ''], ['vertagt', 'Vertagen (Nachbesserung)', ''], ['abgelehnt', 'Ablehnen', 'danger']];
  }

  function termResult(t) {
    const r = t.result;
    const dec = L.DECISION[r.decision];
    const msg = {
      eingetragen: 'Die Eintragung wurde vollzogen' + (r.regNo ? ': ' + r.regNo : '') + '. Der Gewerbeschein wurde ausgestellt, der Gründer ist benachrichtigt.',
      staff: 'Die Genehmigung ist erteilt. Die Eintragung folgt nach der Schlussprüfung durch die Registerführung.',
      vertagt: 'Der Gründer erhält Ihre Begründung und kann nachbessern. Ein Folgetermin wird bevorzugt vergeben.',
      abgelehnt: 'Der Gründer erhält den Bescheid mit Ihrer Begründung und kann ' + cfg().rules.objectionHours + ' Stunden lang Einspruch einlegen.',
      geaendert: 'Die Änderung wurde beurkundet.', erfuellt: 'Die Auflagen gelten als erfüllt.', offen: 'Die Auflagen bleiben offen, der Gründer wird erinnert.', beratung: 'Die Beratung ist abgeschlossen.',
    }[r.outcome] || 'Der Termin ist abgeschlossen.';
    return html`<div class="page-head"><div><div class="crumbs">Beamten-Tablet · Termin</div><h1>Bescheid erteilt</h1></div></div>
      <div class="sheet"><div class="sheet-b" style="text-align:center;padding:38px 20px">${c.stamp(dec.stamp, dec.word, true)}
        <h2 style="margin-top:22px">${dec.label}</h2><p class="muted" style="margin-top:6px;max-width:60ch;margin-inline:auto">${msg}</p>
        ${r.caseNo ? html`<p style="margin-top:10px">${c.tag(r.caseNo)}</p>` : ''}</div></div>
      <div class="btn-row"><button class="btn primary" data-act="term-close">Zurück zu Heute</button></div>`;
  }

  function term() {
    const t = T();
    if (!t) return today();
    if (t.result) return termResult(t);
    const ap = apptOf(t.id);
    if (!ap) { S.ui.term = null; return today(); }
    const type = typeOf(ap.typeId);
    const app = ap.applicationId ? appOf(ap.applicationId) : null;
    const ent = ap.entityId ? S.d.register.find((e) => e.id === ap.entityId) : null;
    const f = app ? formOf(app.legalForm) : null, b = app && app.branch ? branchOf(app.branch) : null;
    const qs = QUESTIONS[app && app.kind === 'fraktion' ? 'fraktion' : 'unternehmen'];
    return html`
      <div class="page-head"><div><div class="crumbs">Beamten-Tablet · Termin läuft seit ${IC.ftime(ap.startedAt || ap.start)} Uhr</div><h1>${type.label}</h1>
        <div class="row sm" style="margin-top:6px">${app ? c.tag(app.caseNo) : c.tag(ap.id)}${c.apptChip(ap.status)}${app ? c.appChip(app.status) : ''}</div></div>
        <button class="btn" data-act="term-close">Zurück zu Heute</button></div>
      <div class="split" style="grid-template-columns:minmax(0,1fr) 380px">
        <div class="stack">
          ${app ? c.sheet('Antrag', html`<div class="stack">
            ${c.kv([['Name', app.name], [app.kind === 'fraktion' ? 'Art' : 'Rechtsform', f ? f.label : '–'], b ? ['Branche', html`${b.label} ${b.needsProperty ? c.chip('Standort Pflicht', '', 'pin') : ''} ${b.authority ? c.chip('Zulassung: ' + b.authority, 'warn', 'badge') : ''}`] : null, ['Standort', IC.siteLabel(app.property)], ['Gebühren', app.fees ? html`${c.chip('Antrag ' + money(app.fees.apply) + ' bezahlt', 'ok', 'check')} ${c.chip('Eintragung ' + money(app.fees.register) + ' hinterlegt', 'ok', 'check')} ${app.fees.capital ? c.chip('Kapital ' + money(app.fees.capital) + ' hinterlegt', 'ok', 'check') : ''}` : '–']])}
            <div class="tbl-wrap"><table class="tbl"><thead><tr><th>Gründer</th><th>Rolle</th><th class="right">Anteil</th><th>Anwesend</th></tr></thead><tbody>${app.founders.map((fd) => { const at = ap.attendees.find((x) => x.charId === fd.charId); return html`<tr><td class="strong">${fd.name}</td><td>${L.MEMBER_ROLE[fd.role]}</td><td class="right num">${fd.share != null ? fd.share + ' %' : '–'}</td><td>${at ? (at.checkedIn ? c.chip('ja', 'ok', 'check') : c.chip('nein', 'bad')) : c.chip('nicht eingeladen', '')}</td></tr>`; })}</tbody></table></div>
          </div>`, { icon: 'doc' }) : ent ? c.sheet('Eintragung', c.kv([['Name', ent.name], ['Nr.', ent.regNo], ['Status', c.orgChip(ent.status)], ['Sitz', ent.hq], ent.pendingChange ? ['Beantragte Änderung', (ent.pendingChange.type === 'name' ? 'Neuer Name: ' : 'Neuer Sitz: ') + ent.pendingChange.value] : null, ['Offene Auflagen', ent.conditions.filter((x) => !x.done).length ? html`<ul style="margin:0;padding-left:18px">${ent.conditions.filter((x) => !x.done).map((x) => html`<li>${x.text}</li>`)}</ul>` : 'keine']]), { icon: 'folder' }) : ''}
          ${app && app.kind === 'unternehmen' && app.concept ? c.sheet('Vorgestelltes Konzept', c.kv([['Geschäftsidee', app.concept.idea], ['Zielgruppe', app.concept.audience || '–'], ['Angebot', app.concept.offer || '–'], ['Personal', app.concept.staff || '–'], ['Öffnungszeiten', app.concept.hours || '–']]), { icon: 'book' }) : ''}
          ${app && app.kind === 'fraktion' && app.statute ? c.sheet('Zweck und Satzung', c.kv([['Zweck', app.statute.purpose], ['Ziele', app.statute.goals || '–'], ['Aufnahme', app.statute.admission || '–']]), { icon: 'book' }) : ''}
          ${app ? c.sheet('Fragenkatalog', html`<ul style="margin:0;padding-left:20px;display:flex;flex-direction:column;gap:6px">${qs.map((q) => html`<li>${q}</li>`)}</ul>`, { icon: 'info' }) : ''}
        </div>
        <aside class="stack sticky">
          ${c.sheet('Checkliste', html`<div data-partial="term-check">${IC.partials['term-check']()}</div>`, { icon: 'list' })}
          ${c.sheet('Notizen', html`<textarea id="term-notes" data-bind="ui.term.notes" placeholder="Eigene Notizen zum Termin (nur für Sie sichtbar)">${t.notes}</textarea>`, { icon: 'edit' })}
          ${c.sheet('Entscheidung', html`<div class="stack sm">${decisionButtons(type).map((x) => html`<button class="btn ${x[2] === 'ok' ? 'ok' : x[2]} lg" data-act="dec-open" data-dec="${x[0]}">${x[1]}</button>`)}</div>`, { icon: 'stamp', footer: html`<span class="small muted">Jede Entscheidung außer „Genehmigen“ braucht eine Begründung. Sie wird im Bescheid angezeigt.</span>` })}
        </aside>
      </div>`;
  }

  IC.partials['dec-conds'] = function () {
    const t = T();
    return html`<div class="stack sm">
      <div class="row sm">${cfg().conditionPresets.map((p) => html`<button class="chip ${t.conds.indexOf(p) !== -1 ? 'solid' : ''}" style="cursor:pointer" data-act="dec-cond-preset" data-text="${p}">${t.conds.indexOf(p) !== -1 ? ico('check') : ico('plus')}${p}</button>`)}</div>
      <div class="row"><input id="dec-cond-in" type="text" class="grow" style="min-width:200px" data-bind="ui.term.condIn" placeholder="Eigene Auflage hinzufügen" value="${t.condIn}"><button class="btn sm" data-act="dec-cond-add">Hinzufügen</button></div>
      ${t.conds.filter((x) => cfg().conditionPresets.indexOf(x) === -1).map((x) => html`<div class="spread"><span>${x}</span><button class="btn sm ghost" data-act="dec-cond-del" data-text="${x}">${ico('x')}</button></div>`)}
    </div>`;
  };

  function decisionModal(dec) {
    const t = T(), ap = apptOf(t.id), type = typeOf(ap.typeId);
    t.dec = dec; t.reason = ''; t.conds = []; t.condIn = '';
    const label = decisionButtons(type).find((x) => x[0] === dec)[1];
    const app = ap.applicationId ? appOf(ap.applicationId) : null;
    const presets = cfg().reasonPresets[dec] || [];
    const needReason = dec !== 'genehmigt';
    const info = {
      genehmigt: type.key === 'vorstellung_unternehmen' || type.key === 'vorstellung_fraktion' ? 'Der Antrag wird genehmigt. Das System trägt das Unternehmen ein, vergibt die Registernummer und stellt den Gewerbeschein aus.' : 'Der Vorgang wird bestätigt.',
      auflagen: 'Die Eintragung erfolgt mit Auflagen. Eine Probezeit beginnt, die Nachkontrolle wird terminiert.',
      vertagt: 'Der Gründer bekommt Ihre Begründung und kann nachbessern. Ein Folgetermin wird bevorzugt vergeben.',
      abgelehnt: 'Der Gründer erhält einen Bescheid mit Ihrer Begründung und kann ' + cfg().rules.objectionHours + ' Stunden lang Einspruch einlegen.' + (app && app.fees ? ' ' + money(app.fees.register + app.fees.capital) + ' werden erstattet, die Antragsgebühr nicht.' : ''),
    }[dec];
    IC.modal.open({
      title: label, icon: 'stamp', wide: true,
      body: html`<div class="stack">
        ${c.callout(dec === 'abgelehnt' ? 'bad' : dec === 'genehmigt' ? 'ok' : 'warn', 'Folgen dieser Entscheidung', info)}
        ${dec === 'auflagen' ? c.field('dec-cond-in', 'Auflagen', html`<div data-partial="dec-conds">${IC.partials['dec-conds']()}</div>`, { req: true }) : ''}
        ${c.field('dec-reason', 'Begründung' + (needReason ? '' : ' (optional)'), html`<textarea id="dec-reason" data-bind="ui.term.reason" placeholder="Was war ausschlaggebend? Der Gründer liest diesen Text im Bescheid."></textarea>`, { req: needReason })}
        ${presets.length ? html`<div class="stack sm"><span class="lbl">Bausteine</span><div class="row sm">${presets.map((p, i) => html`<button class="btn sm" data-act="dec-preset" data-dec="${dec}" data-i="${i}">${p}</button>`)}</div></div>` : ''}
      </div>`,
      footer: html`<button class="btn" data-act="modal-close">Abbrechen</button><button class="btn ${dec === 'abgelehnt' ? 'danger solid' : 'primary'}" data-act="dec-confirm">${ico('stamp')}Entscheidung verbindlich treffen</button>`,
    });
  }

  /* ====================================================================
     Vorprüfung
     ==================================================================== */
  function reviews() {
    const d = S.d;
    const wait = d.officialApps.filter((a) => a.status === 'eingereicht').sort((a, b) => a.submittedAt - b.submittedAt);
    const other = d.officialApps.filter((a) => L.OPEN_APP.indexOf(a.status) !== -1 && a.status !== 'eingereicht');
    return html`
      <div class="page-head"><div><div class="crumbs">Beamten-Tablet · Vorprüfung</div><h1>Anträge zur Vorprüfung</h1><p class="sub">Prüfen Sie Vollständigkeit und Plausibilität. Das Ziel ist eine Bearbeitung binnen 48 Stunden.</p></div></div>
      ${dutyBar()}
      ${c.sheet('Wartet auf Vorprüfung', wait.length ? html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Aktenzeichen</th><th>Name</th><th>Art</th><th>Antragsteller</th><th>Eingang</th><th></th></tr></thead><tbody>${wait.map((a) => {
        const f = formOf(a.legalForm), age = IC.now() - a.submittedAt, late = age > 48 * IC.HOUR;
        return html`<tr><td>${c.tag(a.caseNo)}</td><td><div class="strong">${a.name}</div><div class="sub">${a.branch ? branchOf(a.branch).label : 'Organisation'}</div></td><td>${f.label}</td><td>${who(a)}</td><td>${IC.dur(age)}${late ? html` ${c.chip('überfällig', 'bad')}` : ''}</td><td class="act"><button class="btn sm primary" data-act="rev-open" data-id="${a.id}">Prüfen</button></td></tr>`;
      })}</tbody></table></div>` : c.empty('check', 'Alles abgearbeitet', 'Es wartet kein Antrag auf die Vorprüfung.'), { icon: 'doc', flush: !!wait.length })}
      ${other.length ? c.sheet('Weitere laufende Anträge', html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Aktenzeichen</th><th>Name</th><th>Antragsteller</th><th>Status</th></tr></thead><tbody>${other.map((a) => html`<tr><td>${c.tag(a.caseNo)}</td><td class="strong">${a.name}</td><td>${who(a)}</td><td>${c.appChip(a.status)}</td></tr>`)}</tbody></table></div>`, { icon: 'list', flush: true }) : ''}`;
  }

  function reviewModal(a) {
    const f = formOf(a.legalForm), b = a.branch ? branchOf(a.branch) : null;
    S.ui.rev = { id: a.id, msg: '' };
    IC.modal.open({
      title: 'Vorprüfung ' + a.caseNo, icon: 'doc', wide: true,
      body: html`<div class="stack">
        ${c.kv([['Name', a.name], ['Antragsteller', who(a)], [a.kind === 'fraktion' ? 'Art' : 'Rechtsform', f.label], b ? ['Branche', html`${b.label} ${b.authority ? c.chip('Zulassung: ' + b.authority, 'warn', 'badge') : ''}`] : null, ['Standort', IC.siteLabel(a.property)], ['Gründer', a.founders.map((x) => x.name + ' (' + L.MEMBER_ROLE[x.role] + (x.share != null ? ', ' + x.share + ' %' : '') + ')').join(', ')]])}
        ${a.kind === 'unternehmen' && a.concept ? c.kv([['Geschäftsidee', a.concept.idea], ['Zielgruppe', a.concept.audience || '–'], ['Personal', a.concept.staff || '–']]) : a.statute ? c.kv([['Zweck', a.statute.purpose], ['Ziele', a.statute.goals || '–'], ['Aufnahme', a.statute.admission || '–']]) : ''}
        ${c.field('rev-msg', 'Hinweis an den Gründer', html`<textarea id="rev-msg" data-bind="ui.rev.msg" placeholder="Bei Nachbesserung oder Ablehnung Pflicht: Was fehlt, oder warum ist der Antrag unzulässig?"></textarea>`)}
      </div>`,
      footer: html`<button class="btn ghost" data-act="rev-conflict" style="margin-right:auto">Befangenheit melden</button><button class="btn danger" data-act="rev-do" data-result="abgelehnt">Ablehnen</button><button class="btn" data-act="rev-do" data-result="nachbesserung">Nachbesserung anfordern</button><button class="btn ok" data-act="rev-do" data-result="ok">${ico('check')}Vorprüfung bestanden</button>`,
    });
  }

  /* ====================================================================
     Sprechzeiten
     ==================================================================== */
  function hours() {
    const d = S.d, o = O();
    const h = S.ui.hrs || (S.ui.hrs = { day: 1, start: 18 * 60, dur: 120 });
    const mine = d.hours.filter((x) => x.mine);
    const dayTs = (n) => IC.startOfDay(IC.now() + n * IC.DAY);
    return html`
      <div class="page-head"><div><div class="crumbs">Beamten-Tablet · Sprechzeiten</div><h1>Sprechzeiten</h1><p class="sub">Veröffentlichte Sprechzeiten machen Termine auch dann buchbar, wenn Sie gerade nicht im Dienst sind. Bei Beginn müssen Sie im Dienst sein, sonst fällt der Termin aus.</p></div></div>
      <div class="split" style="grid-template-columns:minmax(0,1fr) 340px">
        <div class="stack">
          ${c.sheet('Alle Sprechzeiten', d.hours.length ? html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Beamter</th><th>Tag</th><th>Zeit</th><th></th></tr></thead><tbody>${d.hours.map((x) => html`<tr><td class="strong">${x.official}${x.mine ? html` ${c.chip('Sie', 'info')}` : ''}</td><td>${IC.fday(x.start)}</td><td class="num">${IC.ftime(x.start)}–${IC.ftime(x.end)} Uhr</td><td class="act">${x.mine || lvl(o.rank) >= lvl('amtsleiter') ? html`<button class="btn sm ghost" data-act="hours-del" data-id="${x.id}" aria-label="Sprechzeit löschen">${ico('trash')}</button>` : ''}</td></tr>`)}</tbody></table></div>` : c.empty('calendar', 'Keine Sprechzeiten', 'Ohne Sprechzeiten und ohne Beamte im Dienst kann niemand einen Termin buchen.'), { icon: 'calendar', flush: !!d.hours.length })}
        </div>
        <aside class="stack">
          ${c.sheet('Sprechzeit veröffentlichen', html`<div class="stack">
            ${c.field('hrs-day', 'Tag', html`<select id="hrs-day" data-bind="ui.hrs.day">${Array.from({ length: cfg().rules.bookAheadDays + 1 }, (_, n) => html`<option value="${n}" ${Number(h.day) === n ? raw('selected') : ''}>${IC.fdaylong(dayTs(n))}</option>`)}</select>`)}
            ${c.field('hrs-start', 'Beginn', html`<select id="hrs-start" data-bind="ui.hrs.start">${Array.from({ length: 72 }, (_, i) => 6 * 60 + i * 15).map((m) => html`<option value="${m}" ${Number(h.start) === m ? raw('selected') : ''}>${IC.pad(Math.floor(m / 60))}:${IC.pad(m % 60)} Uhr</option>`)}</select>`)}
            ${c.field('hrs-dur', 'Dauer', html`<select id="hrs-dur" data-bind="ui.hrs.dur">${[30, 60, 90, 120, 180, 240].map((m) => html`<option value="${m}" ${Number(h.dur) === m ? raw('selected') : ''}>${m >= 60 ? (m / 60) + ' Std.' : m + ' Min.'}</option>`)}</select>`)}
            <button class="btn primary" data-act="hours-add">Veröffentlichen</button>
          </div>`, { icon: 'plus' })}
          ${mine.length ? c.callout('info', 'Ihre Sprechzeiten', mine.length + ' ' + IC.plural(mine.length, 'Zeitfenster', 'Zeitfenster') + ' veröffentlicht.', 'calendar') : ''}
        </aside>
      </div>`;
  }

  /* ====================================================================
     Register mit Sanktionen
     ==================================================================== */
  function breg() {
    const d = S.d, o = O();
    const q = S.ui.bq || '';
    const n = IC.normName(q);
    const rows = d.register.filter((e) => !n || IC.normName(e.name).indexOf(n) !== -1 || e.regNo.toLowerCase().replace(/\s/g, '').indexOf(q.toLowerCase().replace(/\s/g, '')) !== -1);
    const can = lvl(o.rank) >= lvl('amtsleiter');
    return html`
      <div class="page-head"><div><div class="crumbs">Beamten-Tablet · Register</div><h1>Register und Aufsicht</h1><p class="sub">Auflagen und Sanktionen dürfen Amtsleiter verhängen. Jede Maßnahme braucht eine Begründung und lässt sich per Einspruch anfechten.</p></div></div>
      <div class="sheet"><div class="sheet-b"><div class="field" style="max-width:420px"><label for="breg-q">Suche</label><input id="breg-q" type="search" data-bind="ui.bq" data-after="breg-search" value="${q}" placeholder="Name oder Registernummer"></div></div></div>
      <div class="sheet"><div class="sheet-b flush tbl-wrap" data-partial="breg-rows">${IC.partials['breg-rows']()}</div></div>
      ${can ? '' : c.callout('info', 'Eingeschränkte Rechte', 'Sanktionen sind dem Rang Amtsleiter vorbehalten. In der Vorschau können Sie den Rang unten links wechseln.', 'lock')}`;
  }
  IC.partials['breg-rows'] = function () {
    const d = S.d, o = O();
    const q = S.ui.bq || '';
    const n = IC.normName(q);
    const can = lvl(o.rank) >= lvl('amtsleiter');
    const rows = d.register.filter((e) => !n || IC.normName(e.name).indexOf(n) !== -1 || e.regNo.toLowerCase().replace(/\s/g, '').indexOf(q.toLowerCase().replace(/\s/g, '')) !== -1);
    if (!rows.length) return c.empty('search', 'Keine Treffer', 'Zu Ihrer Suche gibt es keinen Eintrag.');
    return html`<table class="tbl"><thead><tr><th>Name</th><th>Nr.</th><th>Status</th><th>Auflagen</th><th></th></tr></thead><tbody>${rows.map((e) => {
      const open = e.conditions.filter((x) => !x.done).length;
      return html`<tr><td><div class="strong">${e.name}</div><div class="sub">${e.owner} · ${e.hq}</div></td><td>${c.tag(e.regNo)}</td><td>${c.orgChip(e.status)}</td><td>${open ? c.chip(open + ' offen', 'warn') : '–'}${e.history && e.history.length ? html` ${c.chip(e.history.length + ' Maßnahmen', '')}` : ''}</td>
        <td class="act"><button class="btn sm" data-act="sanction-open" data-id="${e.id}" ${can && e.status !== 'aufgeloest' ? '' : raw('disabled')}>Maßnahme</button></td></tr>`;
    })}</tbody></table>`;
  };

  /* ====================================================================
     Handbuch
     ==================================================================== */
  function manual() {
    return html`
      <div class="page-head"><div><div class="crumbs">Beamten-Tablet · Handbuch</div><h1>Kurzhandbuch</h1><p class="sub">Das ausführliche Handbuch liegt im Repository unter docs/BEAMTEN-HANDBUCH.md.</p></div></div>
      <div class="grid g2">
        ${c.sheet('Entscheidungsgrundsätze', html`<div class="stack sm">
          <div class="row top"><span class="chip ok">Genehmigen</span><span class="grow">Wenn alle Pflichtpunkte der Checkliste erfüllt sind.</span></div>
          <div class="row top"><span class="chip warn">Auflagen</span><span class="grow">Bei behebbaren Mängeln, die sich binnen einer Frist nachweisen lassen.</span></div>
          <div class="row top"><span class="chip info">Vertagen</span><span class="grow">Bei fehlenden Unterlagen oder fehlenden Pflichtteilnehmern.</span></div>
          <div class="row top"><span class="chip bad">Ablehnen</span><span class="grow">Nur bei nicht heilbarem Namensverstoß, eindeutig unzulässigem Zweck, bewusst falschen Angaben, aktiver Sperre oder wiederholt fehlenden Pflichtteilnehmern.</span></div></div>`, { icon: 'stamp' })}
        ${c.sheet('Neutralität und Befangenheit', html`<ul style="margin:0;padding-left:20px;display:flex;flex-direction:column;gap:6px"><li>Nie ablehnen, weil das Konzept „nicht gefällt“.</li><li>Nie ablehnen, um Konkurrenz zu schützen oder aus OOC-Gründen.</li><li>Sind Sie selbst Gründer, Gesellschafter oder Mitglied, ist der Antrag für Sie gesperrt.</li><li>Bei Verwandtschaft oder Konkurrenz im Rollenspiel: „Befangenheit melden“.</li><li>Jede Entscheidung außer „Genehmigen“ braucht eine Begründung.</li></ul>`, { icon: 'scale' })}
        ${c.sheet('Ablauf eines Vorstellungstermins', html`<ol class="timeline"><li class="tl-item"><span class="tl-dot">${ico('bell')}</span><div><div class="tl-t">Aufrufen und begrüßen</div></div></li><li class="tl-item"><span class="tl-dot">${ico('badge')}</span><div><div class="tl-t">Ausweise prüfen, Termin starten</div></div></li><li class="tl-item"><span class="tl-dot">${ico('users')}</span><div><div class="tl-t">Vorstellung anhören, Fragen stellen</div></div></li><li class="tl-item"><span class="tl-dot">${ico('list')}</span><div><div class="tl-t">Checkliste abarbeiten</div></div></li><li class="tl-item"><span class="tl-dot">${ico('stamp')}</span><div><div class="tl-t">Entscheiden, begründen, Bescheid aushändigen</div></div></li></ol>`, { icon: 'list' })}
        ${c.sheet('Dienst und Sprechzeiten', html`<ul style="margin:0;padding-left:20px;display:flex;flex-direction:column;gap:6px"><li>Nur im Dienst sind Termine live buchbar und Entscheidungen möglich.</li><li>Sprechzeiten machen spätere Termine buchbar. Bei Beginn müssen Sie im Dienst sein.</li><li>Fällt ein Termin wegen fehlender Beamter aus, bekommt der Gründer Vorrang und keinen Strike.</li><li>Pro durchgeführtem Termin zahlt die Stadtkasse ${money(cfg().rules.officialPay)}, unabhängig vom Ergebnis.</li></ul>`, { icon: 'clock' })}
      </div>`;
  }

  /* ====================================================================
     Aktionen
     ==================================================================== */
  Object.assign(IC.act, {
    'duty-set': async (el) => {
      const r = await IC.run('dutySet', { state: el.dataset.state, desk: Number(S.ui.deskSel || O().desk) }, { ok: el.dataset.state === 'on' ? 'Sie sind im Dienst.' : el.dataset.state === 'pause' ? 'Sie sind in der Pause.' : 'Sie sind außer Dienst.' });
    },
    'duty-desk': async () => { await IC.api('dutySet', { state: O().state, desk: Number(S.ui.deskSel) }); await IC.reload(); },
    'pv-rank': async (el) => { await IC.api('pvSetRank', { rank: el.value }); await IC.reload(); },
    'appt-call': async (el) => { await IC.run('apptCall', { id: el.dataset.id }, { ok: 'Aufgerufen. Die Anzeigetafel zeigt den Aufruf.' }); },
    'appt-start': async (el) => {
      const r = await IC.run('apptStart', { id: el.dataset.id }, { ok: 'Termin gestartet.' });
      if (r.ok) IC.act['term-open'](el);
    },
    'appt-noshow': async (el) => {
      const ap = apptOf(el.dataset.id);
      const yes = await IC.confirm({ title: 'Nicht erschienen?', danger: true, yes: 'Als nicht erschienen werten', text: ap.bookerName + ' ist ' + IC.dur(IC.now() - ap.start) + ' nach Terminbeginn nicht vollständig eingecheckt. Das zählt als Strike.',
        extra: html`<label class="check"><input id="ns-exc" type="checkbox" data-bind="ui.nsExcused"><span>Entschuldigt (zum Beispiel Verbindungsabbruch), kein Strike</span></label>` });
      if (yes) await IC.run('apptNoShow', { id: ap.id, excused: !!S.ui.nsExcused }, { ok: 'Termin geschlossen.' });
      S.ui.nsExcused = false;
    },
    'queue-next': async () => { await IC.run('queueNext', {}, { ok: (r) => 'Nummer ' + r.no + ' aufgerufen.' }); },
    'term-open': (el) => {
      S.ui.term = { id: el.dataset.id, checklist: {}, notes: '', result: null, dec: null, reason: '', conds: [], condIn: '' };
      IC.view('term');
    },
    'term-close': () => { S.ui.term = null; IC.view('today'); },
    'chk-toggle': (el) => { T().checklist[el.dataset.key] = el.checked; IC.refresh('term-check'); },
    'dec-open': (el) => decisionModal(el.dataset.dec),
    'dec-preset': (el) => {
      const t = cfg().reasonPresets[el.dataset.dec][Number(el.dataset.i)];
      T().reason = t;
      const ta = document.getElementById('dec-reason');
      if (ta) { ta.value = t; ta.focus(); }
    },
    'dec-cond-preset': (el) => {
      const t = T(), i = t.conds.indexOf(el.dataset.text);
      if (i === -1) t.conds.push(el.dataset.text); else t.conds.splice(i, 1);
      IC.refresh('dec-conds');
    },
    'dec-cond-add': () => {
      const t = T(), v = String(t.condIn || '').trim();
      if (!v) return;
      if (t.conds.indexOf(v) === -1) t.conds.push(v);
      t.condIn = '';
      IC.refresh('dec-conds');
    },
    'dec-cond-del': (el) => { const t = T(); t.conds = t.conds.filter((x) => x !== el.dataset.text); IC.refresh('dec-conds'); },
    'dec-confirm': async () => {
      const t = T();
      const r = await IC.run('apptDecide', { id: t.id, decision: t.dec, reason: t.reason, conditions: t.conds, checklist: t.checklist }, { noReload: true });
      if (!r.ok) return;
      IC.modal.close(true);
      t.result = r;
      await IC.reload();
    },
    'rev-open': (el) => reviewModal(appOf(el.dataset.id)),
    'rev-do': async (el) => {
      const r = await IC.run('appReview', { id: S.ui.rev.id, result: el.dataset.result, message: S.ui.rev.msg }, { ok: { ok: 'Vorprüfung bestanden. Der Gründer wurde benachrichtigt.', nachbesserung: 'Nachbesserung angefordert.', abgelehnt: 'Antrag abgelehnt.' }[el.dataset.result] });
      if (r.ok) IC.modal.close(true);
    },
    'rev-conflict': async () => {
      const yes = await IC.confirm({ title: 'Befangenheit melden?', yes: 'Befangenheit melden', text: 'Der Antrag wird aus Ihrer Liste entfernt und an einen anderen Beamten übergeben. Die Meldung wird protokolliert.' });
      if (yes) { const r = await IC.run('conflictReport', { id: S.ui.rev.id }, { ok: 'Befangenheit gemeldet. Der Antrag liegt nicht mehr bei Ihnen.' }); }
    },
    'hours-add': async () => {
      const h = S.ui.hrs;
      const start = IC.startOfDay(IC.now() + Number(h.day) * IC.DAY) + Number(h.start) * IC.MIN;
      await IC.run('hoursCreate', { start, end: start + Number(h.dur) * IC.MIN }, { ok: 'Sprechzeit veröffentlicht. Bürger können jetzt Termine buchen.' });
    },
    'hours-del': async (el) => { await IC.run('hoursDelete', { id: el.dataset.id }, { ok: 'Sprechzeit gelöscht.' }); },
    'breg-search': () => IC.refresh('breg-rows'),
    'sanction-open': (el) => {
      const e = S.d.register.find((x) => x.id === el.dataset.id);
      S.ui.sanc = { id: e.id, level: 'verwarnung', reason: '' };
      IC.modal.open({
        title: 'Maßnahme gegen ' + e.name, icon: 'scale',
        body: html`<div class="stack">
          ${c.field('sc-level', 'Maßnahme', html`<select id="sc-level" data-bind="ui.sanc.level">${Object.keys(L.SANCTION).map((k) => html`<option value="${k}">${L.SANCTION[k]}</option>`)}</select>`)}
          ${c.field('sc-reason', 'Begründung', html`<textarea id="sc-reason" data-bind="ui.sanc.reason" placeholder="Was wird beanstandet? Die Begründung steht im Bescheid."></textarea>`, { req: true })}
          ${c.callout('warn', 'Einspruch möglich', 'Jede Maßnahme lässt sich binnen ' + cfg().rules.objectionHours + ' Stunden anfechten. Befristete Untersagung und Entzug sind schwere Eingriffe.')}</div>`,
        footer: html`<button class="btn" data-act="modal-close">Abbrechen</button><button class="btn danger solid" data-act="sanction-send">Maßnahme verhängen</button>`,
      });
    },
    'sanction-send': async () => { const s = S.ui.sanc; const r = await IC.run('sanctionIssue', { entityId: s.id, level: s.level, reason: s.reason }, { ok: 'Maßnahme verhängt und protokolliert.' }); if (r.ok) IC.modal.close(true); },
  });

  IC.registerApp('beamte', {
    title: 'Beamten-Tablet', icon: 'stamp', def: 'today',
    where: () => S.d.config.city + ' · Rathaus · Schalter ' + O().desk,
    nav: () => {
      const d = S.d;
      const wait = d.officialApps.filter((a) => a.status === 'eingereicht').length;
      const openToday = d.officialAppts.filter((a) => OPEN.indexOf(a.status) !== -1).length;
      const list = [
        { id: 'today', label: 'Heute', icon: 'calendar', badge: openToday || null },
        { id: 'reviews', label: 'Vorprüfung', icon: 'doc', badge: wait || null, badgeKind: wait ? 'warn' : '' },
        { id: 'hours', label: 'Sprechzeiten', icon: 'clock' },
        { id: 'breg', label: 'Register', icon: 'folder' },
        { id: 'manual', label: 'Handbuch', icon: 'book' },
      ];
      if (S.ui.term && !S.ui.term.result) list.splice(1, 0, { id: 'term', label: 'Laufender Termin', icon: 'play' });
      return list;
    },
    railFoot: () => html`<div class="stack sm"><span class="lbl">Nur Vorschau: Rang</span><select id="pv-rank" aria-label="Rang in der Vorschau wechseln" style="width:100%">${['anwaerter', 'sachbearbeiter', 'amtsleiter'].map((r) => html`<option value="${r}" ${O().rank === r ? raw('selected') : ''}>${L.RANK[r].label}</option>`)}</select><span class="xs">Der Rang bestimmt, welche Termine und Maßnahmen erlaubt sind.</span></div>`,
    views: { today, term, reviews, hours, breg, manual },
  });

  /* Rangwechsel per Auswahlfeld: change-Ereignis, da data-act nur Klicks auslöst */
  document.addEventListener('change', (e) => {
    if (e.target && e.target.id === 'pv-rank') IC.act['pv-rank'](e.target);
  });
})();
