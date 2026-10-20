/* IC-Behördenportal · Bürgeramt (Sicht der Bürger): Termine, Check-in, Wartenummer */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico, money } = IC;
  const c = IC.c, L = IC.L, S = IC.S;
  const cfg = () => S.d.config;
  const typeOf = (k) => cfg().appointmentTypes.find((t) => t.key === k);
  const pressed = (cond) => raw('aria-pressed="' + (cond ? 'true' : 'false') + '"');
  const OPEN = ['gebucht', 'eingecheckt', 'aufgerufen', 'laeuft'];

  const B = () => S.ui.book || (S.ui.book = { typeId: null, applicationId: null, entityId: null, day: 0, slot: null, attendees: null, note: '', done: null, slotsData: null, rescheduleId: null, dayTouched: false });

  /* ---------- Verfügbarkeit einer Terminart für den Bürger ---------- */
  function typeAvail(t) {
    const d = S.d;
    if (d.me.banUntil) return { ok: false, reason: 'Terminsperre bis ' + IC.fdt(d.me.banUntil) + '.' };
    if (t.needs === 'application') {
      const apps = d.myApplications.filter((a) => t.forStatus.indexOf(a.status) !== -1 && (!t.appKind || a.kind === t.appKind));
      if (!apps.length) {
        const booked = d.myApplications.some((a) => a.status === 'termin_gebucht' && (!t.appKind || a.kind === t.appKind));
        return { ok: false, reason: t.key === 'einspruch' ? 'Nur nach eingelegtem Einspruch.' : booked ? 'Für Ihren Antrag ist bereits ein Termin gebucht.' : 'Voraussetzung: bestandene Vorprüfung Ihres Antrags.' };
      }
      return { ok: true, apps };
    }
    if (t.needs === 'entity') {
      const ents = d.myEntities.filter((e) => e.status !== 'aufgeloest' && (t.entityNeeds !== 'conditions' || e.conditions.some((x) => !x.done)));
      if (!ents.length) return { ok: false, reason: t.entityNeeds === 'conditions' ? 'Nur mit offenen Auflagen.' : 'Voraussetzung: eine Eintragung.' };
      return { ok: true, ents };
    }
    return { ok: true };
  }

  function mandatory(app) {
    if (!app) return [S.d.me.charId];
    return app.founders.filter((f) => f.role === 'geschaeftsfuehrer' || f.role === 'inhaber' || f.role === 'vorsitz' || (f.share || 0) >= 25 || app.kind === 'fraktion').map((f) => f.charId);
  }

  const dayLabel = (ts) => {
    const off = Math.round((IC.startOfDay(ts) - IC.startOfDay(IC.now())) / IC.DAY);
    return off === 0 ? 'Heute' : off === 1 ? 'Morgen' : IC.fday(ts).split(',')[0];
  };

  /* ====================================================================
     Termin buchen
     ==================================================================== */
  IC.partials['book-slots'] = function () {
    const b = B(), d = S.d;
    if (!b.typeId) return html`<div class="hint">Wählen Sie zuerst eine Terminart.</div>`;
    const sd = b.slotsData;
    if (!sd) return html`<div class="hint">${ico('clock')} Termine werden geladen …</div>`;
    const t = typeOf(b.typeId);
    const anyFree = sd.days.some((x) => x.free > 0);
    const banner = d.duty.count
      ? (sd.eligible
        ? html`<div class="duty on"><span class="big">${String(d.duty.count).padStart(2, '0')}</span><div><div class="strong">${d.duty.count} ${IC.plural(d.duty.count, 'Beamter', 'Beamte')} im Dienst</div><div class="small">Live-Termine gibt es für die nächsten ${cfg().rules.liveHorizon} Minuten. Spätere Termine nur in veröffentlichten Sprechzeiten.</div></div></div>`
        : html`<div class="duty off"><span class="big">${String(d.duty.count).padStart(2, '0')}</span><div><div class="strong">Niemand mit der nötigen Befugnis im Dienst</div><div class="small">Für „${t.label}“ ist mindestens der Rang ${L.RANK[t.minRank].label} nötig. Buchbar sind nur veröffentlichte Sprechzeiten.</div></div></div>`)
      : html`<div class="duty off"><span class="big">00</span><div><div class="strong">Zurzeit ist kein Beamter im Dienst</div><div class="small">Live-Termine sind nicht möglich. Buchbar sind nur veröffentlichte Sprechzeiten.</div></div></div>`;
    const notify = !d.duty.count ? html`<label class="check"><input id="notify-chk" type="checkbox" data-act="notify-toggle" ${d.me.notifyOnDuty ? raw('checked') : ''}><span>Benachrichtigen, sobald ein Beamter im Dienst ist <span class="muted small">(höchstens eine Nachricht pro 30 Minuten)</span></span></label>` : '';
    if (!anyFree) {
      return html`<div class="stack">${banner}${c.callout('warn', 'Zurzeit ist kein Termin buchbar', 'Es ist kein Beamter im Dienst und keine Sprechzeit veröffentlicht. Ihr Antrag bleibt gültig, solange die Frist von ' + cfg().rules.bookDays + ' Tagen nach der Vorprüfung läuft.', 'clock')}${notify}</div>`;
    }
    const day = sd.days.find((x) => x.offset === sd.dayOffset);
    return html`<div class="stack">
      ${banner}${notify}
      <div class="daystrip" role="group" aria-label="Tag wählen">${sd.days.map((x) => html`<button class="day" data-act="book-day" data-off="${x.offset}" ${pressed(x.offset === sd.dayOffset)}><span class="dn">${dayLabel(x.ts)}</span><span class="dd">${new Date(x.ts).getDate()}.</span><span class="dc">${x.free ? x.free + ' frei' : '–'}</span></button>`)}</div>
      ${sd.slots.length ? html`<div class="slots" role="group" aria-label="Uhrzeit wählen">${sd.slots.map((sl) => html`<button class="slot" data-act="book-slot" data-start="${sl.start}" ${pressed(b.slot === sl.start)} ${sl.free ? '' : raw('disabled')}>
        <span class="st">${IC.ftime(sl.start)}</span>
        <span class="sm"><span class="pips" aria-hidden="true">${Array.from({ length: Math.min(4, sl.cap) }, (_, i) => html`<i class="${i < sl.free ? '' : 'off'}"></i>`)}</span>${sl.free ? sl.free + ' frei' : 'belegt'}</span>
        <span class="src">${sl.source === 'live' ? 'Live' : 'Sprechzeit'} · ${t.minutes} Min</span></button>`)}</div>`
        : c.empty('calendar', 'Kein Termin an diesem Tag', day && day.total ? 'Alle Termine an diesem Tag sind vergeben. Wählen Sie einen anderen Tag.' : 'An diesem Tag hat kein Beamter Sprechzeit. Wählen Sie einen anderen Tag.')}
    </div>`;
  };

  IC.partials['book-final'] = function () {
    const b = B(), d = S.d;
    const t = b.typeId ? typeOf(b.typeId) : null;
    if (!t) return html``;
    const app = b.applicationId ? d.myApplications.find((a) => a.id === b.applicationId) : null;
    const ent = b.entityId ? d.myEntities.find((e) => e.id === b.entityId) : null;
    const must = mandatory(app);
    const people = app ? app.founders : [{ charId: d.me.charId, name: d.me.name }];
    const att = b.attendees || must;
    const missingVorgang = (t.needs === 'application' && !app) || (t.needs === 'entity' && !ent);
    const ready = b.slot && !missingVorgang && must.every((m) => att.indexOf(m) !== -1);
    const when = b.slot ? IC.fday(b.slot) + ' · ' + IC.ftime(b.slot) + '–' + IC.ftime(b.slot + t.minutes * IC.MIN) + ' Uhr' : 'noch nicht gewählt';
    return html`<div class="stack">
      ${t.needs === 'application' ? html`<div class="stack sm"><h4>Teilnehmer</h4><p class="small muted">Pflichtteilnehmer müssen zum Termin eingecheckt sein, sonst kann er nicht beginnen.</p>
        ${people.map((p) => html`<label class="check person" style="grid-template-columns:20px 36px minmax(0,1fr) auto;cursor:${must.indexOf(p.charId) !== -1 ? 'default' : 'pointer'}"><input type="checkbox" data-act="book-attendee" data-id="${p.charId}" ${att.indexOf(p.charId) !== -1 ? raw('checked') : ''} ${must.indexOf(p.charId) !== -1 ? raw('disabled') : ''}>${c.avatar(p.name)}<span class="grow"><span class="pn">${p.name}</span><span class="pm" style="display:block">${L.MEMBER_ROLE[p.role] || ''}</span></span>${must.indexOf(p.charId) !== -1 ? c.chip('Pflicht', 'warn') : c.chip('freiwillig', '')}</label>`)}</div>` : ''}
      ${c.field('book-note', 'Anmerkung für die Beamten', html`<input id="book-note" type="text" maxlength="200" data-bind="ui.book.note" value="${b.note}" placeholder="Optional, zum Beispiel was Sie mitbringen">`)}
      <div class="sheet"><div class="sheet-b"><dl class="kv"><dt>Termin</dt><dd>${t.label}</dd><dt>Zeit</dt><dd>${when}</dd>${app ? html`<dt>Antrag</dt><dd>${app.name} ${c.tag(app.caseNo)}</dd>` : ''}${ent ? html`<dt>Eintragung</dt><dd>${ent.name} ${c.tag(ent.regNo)}</dd>` : ''}</dl></div>
        <div class="sheet-f"><button class="btn primary lg" data-act="book-submit" ${ready ? '' : raw('disabled')}>${ico('calendar')}${b.rescheduleId ? 'Verbindlich verschieben' : 'Verbindlich buchen'}</button></div></div>
    </div>`;
  };

  function loadSlots() {
    const b = B();
    if (!b.typeId) return Promise.resolve();
    return IC.api('slotsList', { typeId: b.typeId, dayOffset: b.day, excludeApptId: b.rescheduleId }).then((r) => {
      if (!r.ok) { IC.toast(r.error, 'bad'); return; }
      b.slotsData = r;
      if (!b.dayTouched && r.slots.every((x) => x.free === 0)) {
        const first = r.days.find((x) => x.free > 0);
        if (first && first.offset !== b.day) { b.day = first.offset; return loadSlots(); }
      }
      b.day = r.dayOffset;
      IC.refresh('book-slots', 'book-final');
    });
  }

  function bookingCard(b) {
    const d = S.d;
    const ap = d.myAppointments.find((x) => x.id === b.done.id) || {};
    const t = typeOf(ap.typeId || b.typeId);
    return html`<div class="stack lg">
      <div class="sheet"><div class="sheet-b" style="text-align:center;padding:32px 20px">${c.stamp('ok', 'Gebucht', true)}<h2 style="margin-top:20px">Ihr Termin ist gebucht</h2><p class="muted" style="margin-top:6px">${t.label} · ${ap.start ? IC.fdaylong(ap.start) + ', ' + IC.ftime(ap.start) + ' Uhr' : ''}</p></div></div>
      <div class="ticket"><div class="tn">${b.done.id}</div><div><div class="strong">Terminkarte</div><div class="small muted">Einchecken am Empfang ab ${ap.start ? IC.ftime(ap.start - cfg().rules.checkinBefore * IC.MIN) : ''} Uhr. Bitte erscheinen Sie pünktlich: ${cfg().rules.checkinAfter} Minuten nach Beginn gilt der Termin als versäumt.</div></div></div>
      ${t.key.indexOf('vorstellung') === 0 ? c.callout('info', 'So bereiten Sie sich vor', 'Stellen Sie in drei bis fünf Minuten Ihr Konzept vor: Geschäftsidee, Zielgruppe, Standort, Personal. Bringen Sie Ausweis und, falls verlangt, Mietvertrag und Zulassung der Fachbehörde mit.', 'book') : ''}
      <div class="btn-row"><button class="btn primary" data-act="view" data-view="appts">Meine Termine</button><button class="btn" data-act="book-again">Weiteren Termin buchen</button></div>
    </div>`;
  }

  function book() {
    const d = S.d, b = B();
    if (b.done) return html`<div class="page-head"><div><div class="crumbs">Bürgeramt · Termine</div><h1>Termin gebucht</h1></div></div>${bookingCard(b)}`;
    if (b.typeId && !b.slotsData) IC.after(() => loadSlots());
    const t = b.typeId ? typeOf(b.typeId) : null;
    const av = t ? typeAvail(t) : null;
    const openAppts = d.myAppointments.filter((a) => OPEN.indexOf(a.status) !== -1).length;
    return html`
      <div class="page-head"><div><div class="crumbs">Bürgeramt · Termine</div><h1>${b.rescheduleId ? 'Termin verschieben' : 'Termin buchen'}</h1><p class="sub">Termine gibt es nur, wenn Beamte im Dienst sind oder Sprechzeiten veröffentlicht haben.</p></div></div>
      ${c.board(d)}
      ${d.me.banUntil ? c.callout('bad', 'Terminsperre', 'Wegen versäumter Termine sind Sie bis ' + IC.fdt(d.me.banUntil) + ' für Buchungen gesperrt.', 'lock') : ''}
      ${!d.me.banUntil && openAppts >= cfg().rules.maxOpenAppointments && !b.rescheduleId ? c.callout('warn', 'Grenze offener Termine erreicht', 'Sie haben ' + openAppts + ' offene Termine. Sagen Sie einen ab, um einen neuen zu buchen.', 'calendar') : ''}
      ${b.rescheduleId ? c.callout('info', 'Verschieben', 'Der bisherige Termin wird erst mit der Neubuchung freigegeben.', 'refresh') : ''}
      ${c.sheet('Terminart', html`<div class="grid g3">${cfg().appointmentTypes.map((tp) => {
        const a = typeAvail(tp);
        return html`<button class="pick" data-act="book-type" data-key="${tp.key}" ${pressed(b.typeId === tp.key)} ${a.ok && !b.rescheduleId ? '' : (b.rescheduleId && b.typeId === tp.key ? '' : raw('disabled'))}>
          <span class="pk-t">${tp.label}</span><span class="pk-d">${a.ok ? tp.desc : a.reason}</span>
          <span class="pk-m">${c.chip(tp.minutes + ' Min', '', 'clock')}${c.chip('ab ' + L.RANK[tp.minRank].label, '', 'badge')}</span></button>`;
      })}</div>`, { icon: 'list', id: 'sh-type' })}
      ${t && (t.needs === 'application' || t.needs === 'entity') ? c.sheet(t.needs === 'application' ? 'Antrag wählen' : 'Eintragung wählen', html`<div class="grid g2">${(t.needs === 'application' ? av.apps : av.ents).map((x) => html`<button class="pick" data-act="book-vorgang" data-id="${x.id}" ${pressed((t.needs === 'application' ? b.applicationId : b.entityId) === x.id)} ${b.rescheduleId ? raw('disabled') : ''}>
        <span class="pk-t">${x.name}</span><span class="pk-m">${t.needs === 'application' ? html`${c.appChip(x.status)}${c.tag(x.caseNo)}` : html`${c.orgChip(x.status)}${c.tag(x.regNo)}`}</span></button>`)}</div>`, { icon: t.needs === 'application' ? 'doc' : 'folder' }) : ''}
      ${t ? c.sheet('Datum und Uhrzeit', html`<div data-partial="book-slots">${IC.partials['book-slots']()}</div>`, { icon: 'calendar' }) : ''}
      ${t ? c.sheet('Teilnehmer und Buchung', html`<div data-partial="book-final">${IC.partials['book-final']()}</div>`, { icon: 'users' }) : ''}`;
  }

  /* ====================================================================
     Meine Termine
     ==================================================================== */
  function checkinState(ap) {
    const R = cfg().rules, now = IC.now();
    const me = ap.attendees.find((x) => x.charId === S.d.me.charId);
    if (!me) return { can: false, text: '' };
    if (me.checkedIn) return { can: false, done: true, text: 'Sie sind eingecheckt und warten im Wartebereich.' };
    if (['gebucht', 'eingecheckt'].indexOf(ap.status) === -1) return { can: false, text: '' };
    if (now < ap.start - R.checkinBefore * IC.MIN) return { can: false, text: 'Einchecken ab ' + IC.ftime(ap.start - R.checkinBefore * IC.MIN) + ' Uhr.' };
    if (now > ap.start + R.checkinAfter * IC.MIN) return { can: false, text: 'Das Check-in-Fenster ist geschlossen.' };
    return { can: true, text: 'Check-in ist jetzt möglich.' };
  }

  function apptCard(ap) {
    const t = typeOf(ap.typeId);
    const ci = checkinState(ap);
    const app = ap.applicationId ? S.d.myApplications.find((a) => a.id === ap.applicationId) : null;
    const ent = ap.entityId ? S.d.myEntities.find((e) => e.id === ap.entityId) : null;
    const open = OPEN.indexOf(ap.status) !== -1;
    return html`<article class="sheet"><div class="sheet-h">${ico('calendar')}<h3>${ap.id}</h3><span class="sp"></span>${c.apptChip(ap.status)}</div>
      <div class="sheet-b stack">
        <div><h2>${t.label}</h2><p class="muted" style="margin-top:2px">${IC.fdaylong(ap.start)}, ${IC.ftime(ap.start)}–${IC.ftime(ap.end)} Uhr${open ? html` · <b>${IC.rel(ap.start)}</b>` : ''}</p></div>
        ${c.kv([app ? ['Antrag', html`${app.name} ${c.tag(app.caseNo)}`] : null, ent ? ['Eintragung', html`${ent.name} ${c.tag(ent.regNo)}`] : null, ['Teilnehmer', ap.attendees.map((x) => html`<span class="chip ${x.checkedIn ? 'ok' : ''}" style="margin:0 4px 4px 0">${x.checkedIn ? ico('check') : ''}${x.name}${x.mandatory ? ' · Pflicht' : ''}</span>`)], ap.note ? ['Anmerkung', ap.note] : null, ['Beamter', ap.official ? ap.official.name : 'wird zugewiesen']])}
        ${ci.text ? c.callout(ci.done ? 'ok' : ci.can ? 'info' : '', ci.done ? 'Eingecheckt' : ci.can ? 'Einchecken möglich' : 'Check-in', ci.text, ci.done ? 'check' : 'clock') : ''}
        ${ap.status === 'aufgerufen' ? c.callout('warn', 'Sie werden aufgerufen', 'Bitte gehen Sie zum Schalter des Beamten.', 'bell') : ''}
        ${ap.status === 'beamter_ausfall' ? c.callout('warn', 'Termin ausgefallen', 'Es war kein Beamter im Dienst. Das ist kein Versäumnis Ihrerseits, es gibt keinen Strike. Buchen Sie einen Ersatztermin, Sie werden bevorzugt behandelt.', 'alert') : ''}
        ${ap.status === 'nicht_erschienen' ? c.callout('bad', 'Nicht erschienen', 'Dieser Termin wurde als versäumt gewertet und zählt als Strike.', 'x') : ''}
      </div>
      ${open && ap.status !== 'laeuft' ? html`<div class="sheet-f">${ci.can ? html`<button class="btn primary" data-act="appt-checkin" data-id="${ap.id}">${ico('check')}Einchecken</button>` : ''}<button class="btn" data-act="appt-resched" data-id="${ap.id}">Verschieben</button><button class="btn danger" data-act="appt-cancel" data-id="${ap.id}">Absagen</button></div>` : ''}
      ${ap.status === 'beamter_ausfall' && app ? html`<div class="sheet-f"><button class="btn primary" data-act="app-book" data-id="${app.id}">Ersatztermin buchen</button></div>` : ''}
    </article>`;
  }

  function appts() {
    const d = S.d;
    const open = d.myAppointments.filter((a) => OPEN.indexOf(a.status) !== -1);
    const past = d.myAppointments.filter((a) => OPEN.indexOf(a.status) === -1).sort((a, b) => b.start - a.start);
    return html`
      <div class="page-head"><div><div class="crumbs">Bürgeramt · Termine</div><h1>Meine Termine</h1><p class="sub">Einchecken ist ${cfg().rules.checkinBefore} Minuten vor bis ${cfg().rules.checkinAfter} Minuten nach Terminbeginn möglich. Absagen bis ${cfg().rules.cancelFreeMinutes} Minuten vorher sind folgenlos.</p></div>
        <button class="btn primary" data-act="book-fresh">${ico('plus')}Termin buchen</button></div>
      ${c.board(d)}
      ${d.me.activeStrikes ? c.callout('warn', d.me.activeStrikes + ' ' + IC.plural(d.me.activeStrikes, 'Strike', 'Strikes') + ' aktiv', 'Bei ' + cfg().rules.strikeLimit + ' Strikes innerhalb von ' + cfg().rules.strikeDays + ' Tagen sind Sie ' + cfg().rules.banDays + ' Tage für Termine gesperrt.', 'alert') : ''}
      ${open.length ? html`<div class="grid g2">${open.map(apptCard)}</div>` : c.sheet('Offene Termine', c.empty('calendar', 'Keine offenen Termine', 'Buchen Sie einen Vorstellungstermin, sobald Ihre Vorprüfung bestanden ist.', html`<button class="btn primary" data-act="book-fresh">Termin buchen</button>`))}
      ${past.length ? c.sheet('Vergangene Termine', html`<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Termin</th><th>Zeit</th><th>Status</th></tr></thead><tbody>${past.map((a) => html`<tr><td><div class="strong">${typeOf(a.typeId).label}</div><div class="sub">${a.id}</div></td><td>${IC.fdt(a.start)}</td><td>${c.apptChip(a.status)}</td></tr>`)}</tbody></table></div>`, { icon: 'clock', flush: true }) : ''}`;
  }

  /* ====================================================================
     Wartenummer
     ==================================================================== */
  function queue() {
    const d = S.d;
    const tk = d.myTicket;
    S.ui.qtype = S.ui.qtype || 'beratung';
    const opts = cfg().appointmentTypes.filter((t) => t.key === 'beratung');
    return html`
      <div class="page-head"><div><div class="crumbs">Bürgeramt · Spontan</div><h1>Wartenummer</h1><p class="sub">Ohne Termin vorbeigekommen? Mit einer Wartenummer werden Sie der Reihe nach aufgerufen, solange ein Beamter im Dienst ist. Für eine Vorstellung buchen Sie einen Live-Termin.</p></div></div>
      ${c.board(d)}
      ${tk ? html`<div class="stack">
          ${tk.called ? c.callout('warn', 'Sie werden aufgerufen', 'Ihre Nummer ' + tk.no + ' wird an Schalter ' + d.board.calling.desk + ' bedient. Bitte dorthin gehen.', 'bell') : ''}
          <div class="ticket"><div class="tn">${tk.no}</div><div><div class="strong">Ihre Wartenummer</div><div class="small muted">${typeOf(tk.typeId).label} · ${tk.called ? 'wird aufgerufen' : 'Position ' + tk.position + ' in der Schlange, geschätzt ' + Math.max(3, Math.round((tk.position * 8) / Math.max(1, d.duty.count))) + ' Minuten'}</div></div></div>
          <div class="btn-row"><button class="btn danger" data-act="queue-leave">Nummer abgeben</button></div></div>`
        : c.sheet('Nummer ziehen', html`<div class="stack">
          ${d.duty.count ? '' : c.callout('warn', 'Zurzeit ist kein Beamter im Dienst', 'Eine Wartenummer ist nicht möglich. Buchen Sie einen Termin in einer Sprechzeit oder lassen Sie sich benachrichtigen.', 'clock', html`<button class="btn sm" data-act="view" data-view="book">Zur Terminbuchung</button>`)}
          ${c.field('q-type', 'Anliegen', html`<select id="q-type" data-bind="ui.qtype">${opts.map((t) => html`<option value="${t.key}" ${S.ui.qtype === t.key ? raw('selected') : ''}>${t.label}</option>`)}</select>`)}
          <div class="btn-row"><button class="btn primary lg" data-act="queue-take" ${d.duty.count ? '' : raw('disabled')}>${ico('ticket')}Wartenummer ziehen</button></div></div>`, { icon: 'ticket' })}`;
  }

  /* ====================================================================
     Aktionen
     ==================================================================== */
  Object.assign(IC.act, {
    'book-fresh': () => { S.ui.book = null; IC.view('book'); },
    'book-again': () => { S.ui.book = null; IC.view('book'); },
    'book-type': (el) => {
      const b = B();
      const t = typeOf(el.dataset.key);
      const av = typeAvail(t);
      b.typeId = t.key; b.slot = null; b.slotsData = null; b.day = 0; b.dayTouched = false;
      b.applicationId = t.needs === 'application' && av.apps.length === 1 ? av.apps[0].id : null;
      b.entityId = t.needs === 'entity' && av.ents.length === 1 ? av.ents[0].id : null;
      b.attendees = null;
      IC.render();
    },
    'book-vorgang': (el) => {
      const b = B(), t = typeOf(b.typeId);
      if (t.needs === 'application') { b.applicationId = el.dataset.id; b.attendees = null; } else b.entityId = el.dataset.id;
      IC.render();
    },
    'book-day': (el) => { const b = B(); b.day = Number(el.dataset.off); b.dayTouched = true; b.slot = null; IC.api('slotsList', { typeId: b.typeId, dayOffset: b.day, excludeApptId: b.rescheduleId }).then((r) => { if (r.ok) { b.slotsData = r; IC.refresh('book-slots', 'book-final'); } }); },
    'book-slot': (el) => { const b = B(); b.slot = Number(el.dataset.start); IC.refresh('book-slots', 'book-final'); },
    'book-attendee': (el) => {
      const b = B();
      const app = b.applicationId ? S.d.myApplications.find((a) => a.id === b.applicationId) : null;
      const cur = (b.attendees || mandatory(app)).slice();
      const i = cur.indexOf(el.dataset.id);
      if (i === -1) cur.push(el.dataset.id); else cur.splice(i, 1);
      b.attendees = cur;
      IC.refresh('book-final');
    },
    'book-submit': async () => {
      const b = B();
      const app = b.applicationId ? S.d.myApplications.find((a) => a.id === b.applicationId) : null;
      const r = await IC.run('apptBook', {
        typeId: b.typeId, start: b.slot, applicationId: b.applicationId, entityId: b.entityId, attendees: b.attendees || mandatory(app), note: b.note,
        rescheduleId: b.rescheduleId, rescheduleAppId: app ? app.id : null,
      }, { noReload: true });
      if (!r.ok) { b.slotsData = null; await loadSlots(); return; }
      b.done = { id: r.id };
      await IC.reload();
    },
    'notify-toggle': async (el) => {
      const r = await IC.api('notifyOnDuty', { enabled: el.checked });
      if (r.ok) { S.d.me.notifyOnDuty = r.enabled; IC.toast(r.enabled ? 'Sie werden benachrichtigt, sobald ein Beamter im Dienst ist.' : 'Benachrichtigung ausgeschaltet.', 'ok'); }
    },
    'appt-checkin': async (el) => { await IC.run('apptCheckin', { id: el.dataset.id }, { ok: (r) => (r.allIn ? 'Eingecheckt. Alle Pflichtteilnehmer sind da' + (r.othersIn ? ' (in der Vorschau treffen Ihre Mitgründer gemeinsam mit Ihnen ein)' : '') + ', bitte warten Sie auf den Aufruf.' : 'Eingecheckt. Es fehlen noch Pflichtteilnehmer.') }); },
    'appt-cancel': async (el) => {
      const ap = S.d.myAppointments.find((x) => x.id === el.dataset.id);
      const late = ap.start - IC.now() < cfg().rules.cancelFreeMinutes * IC.MIN;
      const yes = await IC.confirm({ title: 'Termin absagen?', danger: true, yes: 'Termin absagen',
        text: 'Der Termin am ' + IC.fday(ap.start) + ' um ' + IC.ftime(ap.start) + ' Uhr wird abgesagt.',
        extra: late ? c.callout('warn', 'Kurzfristige Absage', 'Es sind weniger als ' + cfg().rules.cancelFreeMinutes + ' Minuten bis zum Termin. Das zählt als Strike.') : '' });
      if (yes) await IC.run('apptCancel', { id: ap.id }, { ok: (r) => (r.strike ? 'Termin abgesagt. Die kurzfristige Absage zählt als Strike.' : 'Termin abgesagt.') });
    },
    'appt-resched': (el) => {
      const ap = S.d.myAppointments.find((x) => x.id === el.dataset.id);
      S.ui.book = { typeId: ap.typeId, applicationId: ap.applicationId, entityId: ap.entityId, day: 0, slot: null, attendees: ap.attendees.map((x) => x.charId), note: ap.note || '', done: null, slotsData: null, rescheduleId: ap.id, dayTouched: false };
      IC.view('book');
    },
    'queue-take': async () => {
      const r = await IC.run('queueTake', { typeId: S.ui.qtype }, { ok: (x) => 'Ihre Wartenummer: ' + x.no + '. Position ' + x.position + ', etwa ' + x.etaMin + ' Minuten.' });
    },
    'queue-leave': async () => { await IC.run('queueLeave', {}, { ok: 'Wartenummer abgegeben.' }); },
  });

  IC.registerApp('buergeramt', {
    title: 'Bürgeramt', icon: 'calendar', def: 'book',
    where: () => S.d.config.city + (S.env.nui ? '' : ' · Rathaus · Empfang'),
    nav: () => {
      const n = S.d.myAppointments.filter((a) => OPEN.indexOf(a.status) !== -1).length;
      return [
        { id: 'book', label: 'Termin buchen', icon: 'plus' },
        { id: 'appts', label: 'Meine Termine', icon: 'calendar', badge: n || null },
        { id: 'queue', label: 'Wartenummer', icon: 'ticket', badge: S.d.myTicket ? S.d.myTicket.no : null },
      ];
    },
    railFoot: () => html`Termine gibt es nur, wenn Beamte im Dienst sind oder Sprechzeiten bestehen.`,
    views: { book, appts, queue },
  });
})();
