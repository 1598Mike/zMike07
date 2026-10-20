/* IC-Behördenportal · Mock-Backend (nur für die Vorschau im Browser)
   Bildet die Regeln aus docs/KONZEPT.md nach. Im Spiel ersetzt der Server dieses Modul vollständig. */
(function () {
  'use strict';
  const IC = window.IC;
  const L = IC.L, cfg = IC.mockConfig, R = cfg.rules;
  const { MIN, HOUR, DAY } = IC;
  const now = () => IC.now();

  let s = IC.mockSeed();

  /* ---------- Helfer ---------- */
  const form = (k) => cfg.legalForms.find((f) => f.key === k);
  const branchOf = (k) => cfg.branches.find((b) => b.key === k);
  const typeOf = (k) => cfg.appointmentTypes.find((t) => t.key === k);
  const lvl = (rank) => L.RANK[rank].level;
  const ok = (o) => Object.assign({ ok: true }, o || {});
  const fail = (error, o) => Object.assign({ ok: false, error }, o || {});
  const pad4 = (n) => String(n).padStart(4, '0');
  const nextNo = (key) => s.seq[key]++;
  const isOpenApp = (a) => L.OPEN_APP.includes(a.status);
  const appById = (id) => s.applications.find((a) => a.id === id);
  const apptById = (id) => s.appointments.find((a) => a.id === id);
  const entById = (id) => s.entities.find((e) => e.id === id);
  const OPEN_APPT = ['gebucht', 'eingecheckt', 'aufgerufen', 'laeuft'];
  const audit = (actor, kind, action, target, detail) => s.audit.unshift({ ts: now(), actor, kind, action, target, detail });
  const notice = (text, kind) => s.notices.push({ id: ++s.noticeSeq, ts: now(), text, kind: kind || 'info' });
  const lastTs = (a) => (a.events.length ? a.events[a.events.length - 1].ts : a.createdAt);
  const pushEvent = (a, status, actor, actorKind, text, note) => a.events.push({ ts: now(), status, actor, actorKind, text, note: note || null });
  const mine = (a) => a.applicant.charId === s.me.charId || a.founders.some((f) => f.charId === s.me.charId);
  const stripOoc = (a) => { const c = IC.clone(a); delete c.ooc; return c; };
  const delay = () => IC.sleep(60 + Math.random() * 90);

  function withSuffix(name, f) {
    const suf = f && f.suffix;
    if (!suf) return name;
    const n = name.trim();
    return n.toLowerCase().endsWith(suf.toLowerCase()) ? n : n + ' ' + suf;
  }

  /* ---------- Dienst und Verfügbarkeit ---------- */
  function dutyList() {
    const list = cfg.officials.slice(0, s.officialsOthers).map((o, i) => Object.assign({}, o, { desk: i + 1 }));
    if (s.meOfficial.state === 'on') list.push(Object.assign({}, s.meOfficial));
    return list;
  }
  function eligibleOfficials(type) { return dutyList().filter((o) => lvl(o.rank) >= lvl(type.minRank)); }
  const eligibleCount = (type) => eligibleOfficials(type).length;
  function officialById(id) {
    if (id === s.meOfficial.id) return s.meOfficial;
    return cfg.officials.find((o) => o.id === id);
  }

  /* ---------- Voraussetzungen ---------- */
  function activeStrikes() {
    return s.me.strikes.filter((ts) => now() - ts < R.strikeDays * DAY);
  }
  function banUntil() {
    const a = activeStrikes();
    if (a.length < R.strikeLimit) return null;
    const until = Math.max.apply(null, a) + R.banDays * DAY;
    return until > now() ? until : null;
  }
  function eligibility(p, kind, isMe, excludeAppId) {
    const open = s.applications.filter((a) => isOpenApp(a) && a.applicant.charId === p.charId && a.id !== excludeAppId).length;
    const checks = [
      { key: 'id', ok: !!p.hasId, text: 'Gültiger Personalausweis' },
      { key: 'age', ok: p.age >= R.minAge, text: 'Mindestalter ' + R.minAge + ' Jahre (IC)' },
      { key: 'play', ok: p.playHours >= R.minPlayHours, text: 'Mindestens ' + R.minPlayHours + ' Stunden Spielzeit mit diesem Charakter' },
    ];
    if (isMe) {
      const b = banUntil();
      checks.push({ key: 'ban', ok: !b, text: b ? 'Terminsperre bis ' + IC.fdt(b) : 'Keine Terminsperre' });
      checks.push({ key: 'apps', ok: open < R.maxOpenApplications, text: 'Offene Anträge: ' + open + ' von ' + R.maxOpenApplications });
      if (kind === 'fraktion') {
        const n = s.entities.filter((e) => e.myOwn && e.kind === 'fraktion' && e.status !== 'aufgeloest').length;
        checks.push({ key: 'orgs', ok: n < R.maxOrgs, text: 'Organisationen als Gründer: ' + n + ' von ' + R.maxOrgs });
      } else {
        const n = s.entities.filter((e) => e.myOwn && e.kind === 'unternehmen' && e.status !== 'aufgeloest').length;
        checks.push({ key: 'companies', ok: n < R.maxCompanies, text: 'Aktive Unternehmen als Inhaber: ' + n + ' von ' + R.maxCompanies });
      }
    }
    return { ok: checks.every((c) => c.ok), checks };
  }

  /* ---------- Namensprüfung ---------- */
  function nameCheck(nameIn, legalForm, ignoreAppId) {
    const raw = String(nameIn || '').trim();
    const issues = [];
    const err = (code, text) => issues.push({ level: 'error', code, text });
    const warn = (code, text) => issues.push({ level: 'warn', code, text });
    if (raw.length < 3) err('short', 'Der Name braucht mindestens 3 Zeichen.');
    if (raw.length > 40) err('long', 'Der Name darf höchstens 40 Zeichen lang sein.');
    if (raw && !/^[A-Za-zÄÖÜäöüß0-9 &'.\-]+$/.test(raw)) err('chars', "Erlaubt sind Buchstaben, Ziffern, Leerzeichen und die Zeichen & ' . -");
    const n = IC.normName(raw);
    if (raw.length >= 3 && n.length < 3) err('short', 'Der Name enthält zu wenige Buchstaben.');
    if (n.length >= 3) {
      s.staff.blacklist.forEach((b) => {
        const bn = IC.normName(b.term);
        if (bn && n.indexOf(bn) !== -1) err('blacklist', 'Der Begriff „' + b.term + '“ ist gesperrt (' + b.reason + ').');
      });
      s.entities.forEach((e) => {
        if (e.status === 'aufgeloest') return;
        const en = IC.normName(e.name);
        if (en === n) err('taken', 'Der Name ist bereits im Register eingetragen (' + e.regNo + ').');
        else if (IC.lev(n, en) <= 1) err('similar', 'Zu ähnlich zu „' + e.name + '“ (' + e.regNo + '). Verwechslungsgefahr.');
        else if (IC.lev(n, en) === 2) warn('similar', 'Ähnlich zu „' + e.name + '“. Die Beamten prüfen die Verwechslungsgefahr.');
      });
      s.applications.forEach((a) => {
        if (!isOpenApp(a) || a.id === ignoreAppId) return;
        const an = IC.normName(a.name);
        if (an === n) err('reserved', 'Der Name ist für einen laufenden Antrag reserviert (' + a.caseNo + ').');
        else if (IC.lev(n, an) <= 1) err('similar', 'Zu ähnlich zu einem laufenden Antrag („' + a.name + '“).');
      });
    }
    const display = raw ? withSuffix(raw, form(legalForm)) : '';
    return { ok: !issues.some((i) => i.level === 'error'), normalized: n, display, issues };
  }

  /* ---------- Gebühren ---------- */
  function feesOf(legalForm, branch) {
    const f = form(legalForm);
    const b = branch ? branchOf(branch) : null;
    const k = b ? b.factor : 1;
    const apply = Math.round(f.feeApply * k), register = Math.round(f.feeRegister * k), capital = f.capital;
    return { apply, register, capital, payNow: apply + register + capital, refundable: register + capital };
  }
  const staffGateNeeded = (a) => {
    const b = a.branch ? branchOf(a.branch) : null;
    return !!((b && b.staffGate) || (a.ooc && a.ooc.category === 'untergrund'));
  };
  function branchUsed(key) {
    return s.entities.filter((e) => e.branch === key && e.status !== 'aufgeloest').length
      + s.applications.filter((a) => a.branch === key && ['staff_pruefung'].includes(a.status)).length;
  }
  const branchCap = (b) => (s.staff.capOverrides[b.key] != null ? s.staff.capOverrides[b.key] : b.cap);
  function propertyTaken(id) {
    const p = cfg.properties.find((x) => x.id === id);
    if (!p || p.status !== 'frei') return true;
    return s.applications.some((a) => isOpenApp(a) && a.property && a.property.id === id) || s.entities.some((e) => e.propertyId === id && e.status !== 'aufgeloest');
  }

  /* ---------- Eintragung ---------- */
  function registerEntity(a, via) {
    const f = form(a.legalForm);
    s.seq.reg[f.register] = (s.seq.reg[f.register] || 0) + 1;
    const regNo = f.register + ' ' + pad4(s.seq.reg[f.register]);
    const conds = (a.decision && a.decision.conditions) || [];
    const ent = {
      id: 'E-' + nextNo('entity'), kind: a.kind, regNo, name: a.name, legalForm: a.legalForm, branch: a.branch,
      status: conds.length ? 'probezeit' : 'aktiv', hq: IC.siteLabel(a.property), propertyId: a.property ? a.property.id : null,
      owner: a.founders[0].name, signedBy: via || (a.decision && a.decision.by) || 'Registerführung', founded: now(), validUntil: now() + R.certDays * DAY, memberCount: a.founders.length,
      members: a.founders.map((x) => ({ name: x.name, role: x.role, share: x.share })),
      conditions: conds.map((text) => ({ id: 'C-' + nextNo('cond'), text, due: now() + 14 * DAY, done: false })),
      legacy: false, myOwn: a.founders.some((x) => x.charId === s.me.charId), applicationId: a.id,
      ooc: a.ooc ? Object.assign({}, a.ooc) : null,
    };
    s.entities.push(ent);
    s.treasury += a.fees.register;
    a.status = 'genehmigt';
    a.entityId = ent.id;
    pushEvent(a, 'genehmigt', via || 'System', via ? 'staff' : 'system', 'Eintragung vollzogen', 'Registernummer ' + regNo + '. Der Gewerbeschein wurde ausgestellt.');
    audit('System', 'system', 'Eintragung', regNo, ent.name + ' eingetragen');
    if (a.ooc && a.ooc.category === 'untergrund') s.staff.undergroundCap.used++;
    if (ent.myOwn) notice('„' + ent.name + '“ ist eingetragen. Registernummer ' + regNo + '.', 'ok');
    return ent;
  }
  function refund(a) {
    if (!a.fees || !a.fees.paid) return 0;
    const back = a.fees.register + a.fees.capital;
    if (a.applicant.charId === s.me.charId) s.me.bank += back;
    a.fees.refunded = back;
    return back;
  }

  /* ---------- Zeitliche Übergänge (Ausfälle, Fristen) ---------- */
  function tick() {
    const t = now();
    s.appointments.forEach((ap) => {
      if (['gebucht', 'eingecheckt'].indexOf(ap.status) === -1) return;
      if (t <= ap.start + R.checkinAfter * MIN) return;
      if (eligibleCount(typeOf(ap.typeId)) > 0) return;
      ap.status = 'beamter_ausfall';
      const a = ap.applicationId ? appById(ap.applicationId) : null;
      if (a && a.status === 'termin_gebucht') {
        a.status = a.restoreStatus || 'vorpruefung_ok';
        a.priority = true;
        pushEvent(a, a.status, 'System', 'system', 'Termin ausgefallen: kein Beamter im Dienst', 'Ein Ersatztermin kann mit Vorrang gebucht werden.');
      }
      audit('System', 'system', 'Beamten-Ausfall', ap.id, 'Kein Beamter zum Terminbeginn im Dienst, kein Strike');
      if (ap.booker === s.me.charId) notice('Ihr Termin um ' + IC.ftime(ap.start) + ' Uhr ist ausgefallen, weil kein Beamter im Dienst war. Sie erhalten Vorrang bei einem Ersatztermin.', 'warn');
    });
    s.applications.forEach((a) => {
      if (a.status === 'nachbesserung' && t > lastTs(a) + R.fixDays * DAY) {
        refund(a);
        a.status = 'abgelaufen'; pushEvent(a, 'abgelaufen', 'System', 'system', 'Frist zur Nachbesserung abgelaufen', 'Verwahrte Beträge wurden erstattet, die Antragsgebühr nicht.');
      } else if (a.status === 'vorpruefung_ok' && t > (a.vorpruefungAt || lastTs(a)) + R.bookDays * DAY) {
        refund(a);
        a.status = 'abgelaufen'; pushEvent(a, 'abgelaufen', 'System', 'system', 'Kein Termin innerhalb von ' + R.bookDays + ' Tagen gebucht', 'Verwahrte Beträge wurden erstattet, die Antragsgebühr nicht.');
      }
    });
  }

  /* ---------- Slots ---------- */
  function slotsFor(type, dayOffset, excludeApptId) {
    const t0 = now();
    const dayStart = IC.startOfDay(t0 + dayOffset * DAY);
    const dayEnd = IC.startOfDay(dayStart + 30 * HOUR);
    const step = R.slotStep * MIN, len = type.minutes * MIN, lead = R.leadMinutes * MIN;
    const liveOff = eligibleOfficials(type);
    const out = [];
    for (let st = dayStart; st < dayEnd; st += step) {
      if (st < t0 + lead) continue;
      const set = {};
      let live = false;
      if (st <= t0 + R.liveHorizon * MIN) liveOff.forEach((o) => { set[o.id] = 1; live = true; });
      s.officeHours.forEach((h) => {
        const o = officialById(h.officialId);
        if (!o || lvl(o.rank) < lvl(type.minRank)) return;
        if (h.types && h.types.indexOf(type.key) === -1) return;
        if (h.start <= st && st + len <= h.end) set[h.officialId] = 1;
      });
      const cap = Object.keys(set).length;
      if (!cap) continue;
      let booked = 0;
      s.appointments.forEach((ap) => {
        if (OPEN_APPT.indexOf(ap.status) === -1 || ap.id === excludeApptId) return;
        if (ap.start < st + len && ap.start + ap.minutes * MIN > st) booked++;
      });
      out.push({ start: st, end: st + len, cap, booked, free: Math.max(0, cap - booked), source: live ? 'live' : 'plan' });
    }
    return out;
  }

  function nextFree() {
    const type = typeOf('beratung');
    for (let d = 0; d <= R.bookAheadDays; d++) {
      const f = slotsFor(type, d).find((x) => x.free > 0);
      if (f) return f.start;
    }
    return null;
  }

  /* ---------- Antworten für die Oberfläche ---------- */
  function publicEntity(e) {
    return { id: e.id, regNo: e.regNo, name: e.name, kind: e.kind, legalForm: e.legalForm, branch: e.branch, status: e.status, hq: e.hq, owner: e.owner, founded: e.founded, memberCount: e.memberCount };
  }
  function viewAppt(ap) {
    const type = typeOf(ap.typeId);
    return Object.assign({}, ap, { typeLabel: type.label, end: ap.start + ap.minutes * MIN });
  }

  function bootstrap(p) {
    tick();
    const app = (p && p.app) || 'gewerbeamt';
    const t = now();
    const duty = dutyList();
    const branches = cfg.branches.map((b) => Object.assign({}, b, { cap: branchCap(b), used: branchUsed(b.key) }));
    const out = {
      ok: true, now: t,
      config: Object.assign({}, cfg, { branches }),
      me: Object.assign({}, s.me, { banUntil: banUntil(), activeStrikes: activeStrikes().length }),
      duty: { count: duty.length, officials: duty.map((o) => ({ id: o.id, name: o.name, rank: o.rank, desk: o.desk })), nextFree: nextFree(), othersSetting: s.officialsOthers },
      board: { calling: s.calling && t - s.calling.at < 10 * MIN ? s.calling : null, waiting: s.queue.length },
      myApplications: s.applications.filter(mine).map((a) => IC.clone(a)).sort((a, b) => lastTs(b) - lastTs(a)),
      myEntities: s.entities.filter((e) => e.myOwn).map((e) => IC.clone(e)),
      myAppointments: s.appointments.filter((a) => a.booker === s.me.charId || a.attendees.some((x) => x.charId === s.me.charId)).map(viewAppt).sort((a, b) => a.start - b.start),
      myTicket: s.myTicket ? Object.assign({}, s.myTicket, { position: s.queue.findIndex((q) => q.no === s.myTicket.no) + 1, called: !!(s.calling && s.calling.no === s.myTicket.no) }) : null,
      nearby: s.nearby.map((x) => Object.assign({}, x, { elig: eligibility(x, 'unternehmen', false) })),
      properties: cfg.properties.map((x) => Object.assign({}, x, { taken: propertyTaken(x.id) })),
      eligibility: { unternehmen: eligibility(s.me, 'unternehmen', true), fraktion: eligibility(s.me, 'fraktion', true) },
      notices: s.notices.slice(-6),
      settings: { undergroundViaPortal: s.staff.settings.undergroundViaPortal },
    };
    if (app === 'beamte') {
      const meO = s.meOfficial;
      const conflicts = (a) => (a.conflicts || []).indexOf(meO.id) !== -1;
      out.official = Object.assign({}, meO, { onDuty: meO.state === 'on', level: lvl(meO.rank) });
      out.officialApps = s.applications.map(stripOoc).filter((a) => !conflicts(a)).sort((a, b) => lastTs(b) - lastTs(a));
      out.officialAppts = s.appointments.map(viewAppt).sort((a, b) => a.start - b.start);
      out.queue = s.queue.slice();
      out.hours = s.officeHours.map((h) => Object.assign({}, h, { official: (officialById(h.officialId) || {}).name, mine: h.officialId === meO.id })).sort((a, b) => a.start - b.start);
      out.register = s.entities.map((e) => { const c = IC.clone(e); delete c.ooc; return c; });
      out.coworkers = duty.filter((o) => o.id !== meO.id);
    }
    if (app === 'staff') out.staff = staffOverview();
    return out;
  }

  function staffOverview() {
    const t = now();
    const apps = s.applications;
    const decided = apps.filter((a) => ['genehmigt', 'abgelehnt'].indexOf(a.status) !== -1);
    const rejected = decided.filter((a) => a.status === 'abgelehnt').length;
    const escalations = apps.filter((a) => a.status === 'vorpruefung_ok' && t - (a.vorpruefungAt || lastTs(a)) > R.escalateHours * HOUR);
    const gate = apps.filter((a) => a.status === 'staff_pruefung');
    const finished = s.appointments.filter((a) => ['abgeschlossen', 'nicht_erschienen', 'beamter_ausfall'].indexOf(a.status) !== -1);
    const noShow = finished.filter((a) => a.status === 'nicht_erschienen').length;
    const outage = finished.filter((a) => a.status === 'beamter_ausfall').length;
    const caps = cfg.branches.map((b) => ({ key: b.key, label: b.label, used: branchUsed(b.key), cap: branchCap(b) }));
    return {
      kpi: {
        open: apps.filter(isOpenApp).length,
        gate: gate.length,
        escalations: escalations.length,
        onDuty: dutyList().length,
        treasury: s.treasury,
        rejectionRate: decided.length ? Math.round((rejected / decided.length) * 100) : 18,
        noShowRate: finished.length ? Math.round((noShow / finished.length) * 100) : 8,
        outageRate: finished.length ? Math.round((outage / finished.length) * 100) : 3,
        throughputDays: 4.8,
        availabilityHours: 5.2,
      },
      gate: gate.map((a) => Object.assign(IC.clone(a), { hints: gateHints(a) })),
      entities: s.entities.map((e) => IC.clone(e)).sort((a, b) => a.name.localeCompare(b.name, 'de')),
      escalations: escalations.map((a) => stripOoc(a)),
      caps, undergroundCap: s.staff.undergroundCap,
      blacklist: s.staff.blacklist.slice(),
      settings: Object.assign({}, s.staff.settings),
      audit: s.audit.slice(0, 80),
      applicationsAll: apps.map(stripOoc),
    };
  }

  /* Hinweise zur Schlussprüfung, wie sie der Server aus den Daten ableitet */
  function gateHints(a) {
    const f = form(a.legalForm);
    const nc = nameCheck(a.name, a.legalForm, a.id);
    const problem = nc.issues.find((i) => i.level === 'error' && ['blacklist', 'taken', 'reserved', 'similar'].indexOf(i.code) !== -1);
    const hints = [problem ? { ok: false, text: problem.text } : { ok: true, text: 'Der Name ist frei und steht nicht auf der Sperrliste.' }];
    const lines = [];
    a.founders.forEach((x) => {
      const others = s.entities.filter((e) => e.status !== 'aufgeloest' && (e.members || []).some((m) => m.charId === x.charId || m.name === x.name));
      if (others.length) lines.push(x.name + ': ' + others.map((e) => e.regNo).sort().join(', '));
    });
    hints.push(lines.length ? { ok: false, text: 'Beteiligungen an anderen Einträgen: ' + lines.join('; ') + '.' } : { ok: true, text: 'Die Gründer sind an keinem anderen aktiven Eintrag beteiligt.' });
    hints.push({ ok: a.founders.length >= f.minFounders, text: a.founders.length + ' Gründungsmitglieder, erforderlich sind mindestens ' + f.minFounders + '.' });
    return hints;
  }

  /* ---------- Handler ---------- */
  const H = {};

  H.bootstrap = (p) => bootstrap(p);

  H.nameCheck = (p) => Object.assign({ ok: true }, nameCheck(p.name, p.legalForm, p.ignoreAppId));

  H.appSave = (p) => {
    const d = p.draft;
    let a = d.id ? appById(d.id) : null;
    if (!a) {
      a = { id: 'A-' + nextNo('app'), caseNo: null, kind: d.kind, status: 'entwurf', applicant: { charId: s.me.charId, name: s.me.name }, createdAt: now(), events: [], fees: null, founders: [] };
      s.applications.push(a);
    }
    if (a.status !== 'entwurf' && a.status !== 'nachbesserung') return fail('Dieser Antrag kann nicht mehr bearbeitet werden.');
    Object.assign(a, IC.clone(d), { id: a.id, status: a.status, applicant: a.applicant, createdAt: a.createdAt, events: a.events, caseNo: a.caseNo, fees: a.fees });
    return ok({ id: a.id });
  };

  H.appSubmit = (p) => {
    const d = p.draft;
    const f = form(d.legalForm);
    const errors = [];
    if (!f) return fail('Rechtsform fehlt.');
    const prev = d.id ? appById(d.id) : null;
    const resubmit = !!(prev && prev.status === 'nachbesserung');
    const el = eligibility(s.me, d.kind, true, resubmit ? prev.id : null);
    if (!el.ok) errors.push({ field: 'elig', text: 'Voraussetzungen nicht erfüllt: ' + el.checks.filter((c) => !c.ok).map((c) => c.text).join('; ') });
    const nc = nameCheck(d.name, d.legalForm, d.id);
    if (!nc.ok) errors.push({ field: 'name', text: nc.issues.filter((i) => i.level === 'error').map((i) => i.text)[0] });
    const b = d.branch ? branchOf(d.branch) : null;
    if (d.kind === 'unternehmen') {
      if (!b) errors.push({ field: 'branch', text: 'Bitte eine Branche wählen.' });
      else if (!resubmit && branchUsed(b.key) >= branchCap(b)) errors.push({ field: 'branch', text: 'In der Branche „' + b.label + '“ sind alle Plätze vergeben.' });
      const sum = d.founders.reduce((n, x) => n + (Number(x.share) || 0), 0);
      if (sum !== 100) errors.push({ field: 'founders', text: 'Die Anteile müssen zusammen 100 % ergeben (aktuell ' + sum + ' %).' });
      if (!d.concept || String(d.concept.idea || '').trim().length < 80) errors.push({ field: 'concept', text: 'Bitte die Geschäftsidee ausführlicher beschreiben (mindestens 80 Zeichen).' });
    } else if (!d.statute || String(d.statute.purpose || '').trim().length < 80) {
      errors.push({ field: 'concept', text: 'Bitte den Zweck der Organisation ausführlicher beschreiben (mindestens 80 Zeichen).' });
    }
    if (d.founders.length < f.minFounders) errors.push({ field: 'founders', text: 'Mindestens ' + f.minFounders + ' ' + IC.plural(f.minFounders, 'Gründer', 'Gründer') + ' erforderlich.' });
    if (d.founders.some((x) => x.consent !== 'ok' && x.consent !== 'self')) errors.push({ field: 'founders', text: 'Nicht alle Mitgründer haben zugestimmt.' });
    if (b && b.needsProperty && !(d.property && d.property.mode === 'immobilie' && d.property.id)) errors.push({ field: 'property', text: 'Diese Branche verlangt einen festen Standort.' });
    if (d.property && d.property.mode === 'immobilie' && d.property.id && propertyTaken(d.property.id) && !(prev && prev.property && prev.property.id === d.property.id)) errors.push({ field: 'property', text: 'Die gewählte Immobilie ist nicht mehr frei.' });
    if (d.kind === 'fraktion' && !d.ooc) errors.push({ field: 'ooc', text: 'Bitte die OOC-Angaben ausfüllen.' });
    const fees = feesOf(d.legalForm, d.branch);
    const payNow = resubmit ? 0 : fees.payNow;
    if (payNow > s.me.bank) errors.push({ field: 'bank', text: 'Der Kontostand reicht nicht aus. Benötigt: ' + IC.money(payNow) + '.' });
    if (errors.length) return fail('Der Antrag ist noch nicht vollständig.', { errors });

    let a = prev;
    if (!a) {
      a = { id: 'A-' + nextNo('app'), kind: d.kind, applicant: { charId: s.me.charId, name: s.me.name }, createdAt: now(), events: [] };
      s.applications.push(a);
    }
    Object.assign(a, IC.clone(d), { id: a.id, applicant: a.applicant, createdAt: a.createdAt, events: a.events });
    a.name = nc.display;
    if (!a.caseNo) a.caseNo = 'GA-' + new Date(now()).getFullYear() + '-' + pad4(nextNo('caseNo'));
    s.me.bank -= payNow;
    if (!resubmit) {
      a.fees = { apply: fees.apply, register: fees.register, capital: fees.capital, paid: true };
      s.treasury += fees.apply;
    }
    a.status = 'eingereicht';
    a.submittedAt = a.submittedAt || now();
    a.reservedUntil = now() + R.nameReserveDays * DAY;
    a.remark = null;
    pushEvent(a, 'eingereicht', s.me.name, 'bürger', resubmit ? 'Antrag nach Nachbesserung erneut eingereicht' : 'Antrag eingereicht, Antragsgebühr bezahlt');
    audit(s.me.name, 'bürger', resubmit ? 'Antrag erneut eingereicht' : 'Antrag eingereicht', a.caseNo, a.name);
    return ok({ id: a.id, caseNo: a.caseNo, paid: payNow, name: a.name });
  };

  H.appWithdraw = (p) => {
    const a = appById(p.id);
    if (!a || !mine(a)) return fail('Antrag nicht gefunden.');
    if (a.status === 'entwurf') { s.applications.splice(s.applications.indexOf(a), 1); return ok({ deleted: true }); }
    if (!isOpenApp(a)) return fail('Dieser Antrag lässt sich nicht mehr zurückziehen.');
    s.appointments.forEach((ap) => { if (ap.applicationId === a.id && OPEN_APPT.indexOf(ap.status) !== -1) ap.status = 'abgesagt'; });
    const back = refund(a);
    a.status = 'zurueckgezogen';
    pushEvent(a, 'zurueckgezogen', s.me.name, 'bürger', 'Antrag zurückgezogen', back ? IC.money(back) + ' wurden erstattet. Die Antragsgebühr ist nicht erstattbar.' : null);
    audit(s.me.name, 'bürger', 'Antrag zurückgezogen', a.caseNo, a.name);
    return ok({ refunded: back });
  };

  H.appObjection = (p) => {
    const a = appById(p.id);
    if (!a || !mine(a) || a.status !== 'abgelehnt') return fail('Gegen diesen Antrag ist kein Einspruch möglich.');
    if (now() > a.objectionUntil) return fail('Die Einspruchsfrist von ' + R.objectionHours + ' Stunden ist abgelaufen.');
    if (String(p.text || '').trim().length < 20) return fail('Bitte den Einspruch mit mindestens 20 Zeichen begründen.');
    a.status = 'einspruch';
    pushEvent(a, 'einspruch', s.me.name, 'bürger', 'Einspruch eingelegt', p.text.trim());
    audit(s.me.name, 'bürger', 'Einspruch', a.caseNo, p.text.trim().slice(0, 80));
    return ok();
  };

  H.entityChange = (p) => {
    const e = entById(p.id);
    if (!e || !e.myOwn) return fail('Eintrag nicht gefunden.');
    if (e.status === 'aufgeloest' || e.status === 'gesperrt') return fail('Dieser Eintrag lässt sich nicht ändern.');
    if (s.me.bank < R.feeChange) return fail('Der Kontostand reicht nicht aus. Benötigt: ' + IC.money(R.feeChange) + '.');
    if (p.type === 'name') {
      const nc = nameCheck(p.value, e.legalForm);
      if (!nc.ok) return fail(nc.issues.filter((i) => i.level === 'error')[0].text);
      e.pendingChange = { type: 'name', value: nc.display, at: now() };
    } else {
      if (String(p.value || '').trim().length < 3) return fail('Bitte einen gültigen neuen Sitz angeben.');
      e.pendingChange = { type: 'sitz', value: p.value.trim(), at: now() };
    }
    s.me.bank -= R.feeChange;
    s.treasury += R.feeChange;
    audit(s.me.name, 'bürger', 'Änderungsantrag', e.regNo, e.pendingChange.type + ': ' + e.pendingChange.value);
    return ok({ fee: R.feeChange });
  };

  H.entityDissolve = (p) => {
    const e = entById(p.id);
    if (!e || !e.myOwn) return fail('Eintrag nicht gefunden.');
    e.status = 'aufgeloest';
    e.dissolvedAt = now();
    audit(s.me.name, 'bürger', 'Auflösung', e.regNo, e.name);
    return ok();
  };

  H.entityDuplicate = (p) => {
    const e = entById(p.id);
    if (!e || !e.myOwn) return fail('Eintrag nicht gefunden.');
    if (s.me.bank < R.feeDuplicate) return fail('Der Kontostand reicht nicht aus. Benötigt: ' + IC.money(R.feeDuplicate) + '.');
    s.me.bank -= R.feeDuplicate;
    s.treasury += R.feeDuplicate;
    audit(s.me.name, 'bürger', 'Duplikat Gewerbeschein', e.regNo, e.name);
    return ok({ fee: R.feeDuplicate });
  };

  H.legacyConfirm = (p) => {
    const e = entById(p.id);
    if (!e || !e.myOwn || !e.legacy) return fail('Kein Bestandsschutz-Eintrag.');
    e.legacyConfirmed = true;
    audit(s.me.name, 'bürger', 'Bestandsbestätigung', e.regNo, e.name);
    return ok();
  };

  H.registerSearch = (p) => {
    const q = IC.normName(p.q || '');
    const rows = s.entities.filter((e) => {
      if (p.kind && e.kind !== p.kind) return false;
      if (p.branch && e.branch !== p.branch) return false;
      if (p.status && e.status !== p.status) return false;
      if (!q) return true;
      return IC.normName(e.name).indexOf(q) !== -1 || e.regNo.toLowerCase().replace(/\s/g, '').indexOf(String(p.q).toLowerCase().replace(/\s/g, '')) !== -1 || IC.normName(e.owner).indexOf(q) !== -1;
    }).map(publicEntity).sort((a, b) => a.name.localeCompare(b.name, 'de'));
    return ok({ rows });
  };

  /* ----- Mitgründer einladen (im Spiel antwortet der eingeladene Spieler, hier nach kurzer Zeit automatisch) ----- */
  H.founderInvite = (p) => {
    const person = s.nearby.find((x) => x.charId === p.charId);
    if (!person) return fail('Diese Person ist nicht in Ihrer Nähe.');
    const el = eligibility(person, 'unternehmen', false);
    if (!el.ok) return fail(person.name + ' erfüllt die Voraussetzungen nicht: ' + el.checks.filter((c) => !c.ok).map((c) => c.text).join('; ') + '.');
    s.invites = s.invites || {};
    s.invites[p.charId] = { at: Date.now() };
    return ok();
  };
  H.founderStatus = () => {
    const statuses = {};
    Object.keys(s.invites || {}).forEach((id) => { statuses[id] = Date.now() - s.invites[id].at >= 1200 ? 'ok' : 'pending'; });
    return ok({ statuses });
  };
  H.founderCancel = (p) => { if (s.invites) delete s.invites[p.charId]; return ok(); };

  /* ----- Bürgeramt ----- */
  H.slotsList = (p) => {
    const type = typeOf(p.typeId);
    if (!type) return fail('Unbekannte Terminart.');
    const days = [];
    for (let d = 0; d <= R.bookAheadDays; d++) {
      const sl = slotsFor(type, d, p.excludeApptId);
      const dayTs = IC.startOfDay(now() + d * DAY);
      days.push({ offset: d, ts: dayTs, free: sl.filter((x) => x.free > 0).length, total: sl.length });
    }
    const off = Math.max(0, Math.min(R.bookAheadDays, p.dayOffset || 0));
    return ok({ days, slots: slotsFor(type, off, p.excludeApptId), dayOffset: off, eligible: eligibleCount(type), onDuty: dutyList().length });
  };

  H.apptBook = (p) => {
    const type = typeOf(p.typeId);
    if (!type) return fail('Unbekannte Terminart.');
    const b = banUntil();
    if (b) return fail('Sie sind für Termine gesperrt bis ' + IC.fdt(b) + '.');
    const openAppts = s.appointments.filter((a) => OPEN_APPT.indexOf(a.status) !== -1 && a.booker === s.me.charId && a.id !== p.rescheduleId).length;
    if (openAppts >= R.maxOpenAppointments) return fail('Sie haben bereits ' + R.maxOpenAppointments + ' offene Termine.');
    let app = null, ent = null;
    if (type.needs === 'application') {
      app = appById(p.applicationId);
      if (!app || !mine(app)) return fail('Bitte einen Antrag auswählen.');
      if (type.forStatus.indexOf(app.status) === -1 && !(app.id === (p.rescheduleAppId) && app.status === 'termin_gebucht')) return fail('Für diesen Antrag ist der Termin noch nicht möglich (Status: ' + L.APP[app.status].label + ').');
      if (type.appKind && app.kind !== type.appKind) return fail('Diese Terminart passt nicht zum Antrag.');
    } else if (type.needs === 'entity') {
      ent = entById(p.entityId);
      if (!ent || !ent.myOwn) return fail('Bitte einen Eintrag auswählen.');
      if (type.entityNeeds === 'conditions' && !ent.conditions.some((c) => !c.done)) return fail('Für diesen Eintrag sind keine Auflagen offen.');
    }
    const dayOffset = Math.round((IC.startOfDay(p.start) - IC.startOfDay(now())) / DAY);
    if (dayOffset < 0 || dayOffset > R.bookAheadDays) return fail('Dieser Tag liegt außerhalb des Buchungszeitraums.');
    const slot = slotsFor(type, dayOffset, p.rescheduleId).find((x) => x.start === p.start);
    if (!slot) return fail('Zu diesem Zeitpunkt ist kein Beamter verfügbar.');
    if (slot.free < 1) return fail('Dieser Termin ist leider schon vergeben.');
    const att = (p.attendees || []).map((id) => {
      const person = id === s.me.charId ? s.me : (s.nearby.find((x) => x.charId === id) || Object.keys(s.people).map((k) => s.people[k]).find((x) => x.charId === id));
      return person ? { charId: person.charId, name: person.name, checkedIn: false, mandatory: false } : null;
    }).filter(Boolean);
    if (!att.some((x) => x.charId === s.me.charId)) att.unshift({ charId: s.me.charId, name: s.me.name, checkedIn: false, mandatory: true });
    if (app && type.needs === 'application') {
      const must = app.founders.filter((f) => f.role === 'geschaeftsfuehrer' || f.role === 'inhaber' || f.role === 'vorsitz' || (f.share || 0) >= 25 || app.kind === 'fraktion');
      const missing = must.filter((f) => !att.some((x) => x.charId === f.charId));
      if (missing.length) return fail('Es fehlen Pflichtteilnehmer: ' + missing.map((m) => m.name).join(', ') + '.');
      att.forEach((x) => { x.mandatory = must.some((f) => f.charId === x.charId); });
    } else att.forEach((x) => { x.mandatory = x.charId === s.me.charId; });
    if (p.rescheduleId) {
      const old = apptById(p.rescheduleId);
      if (old) old.status = 'abgesagt';
    }
    const ap = {
      id: 'T-' + nextNo('appt'), typeId: type.key, applicationId: app ? app.id : null, entityId: ent ? ent.id : null, start: p.start, minutes: type.minutes,
      status: 'gebucht', booker: s.me.charId, bookerName: s.me.name, attendees: att, official: null, note: String(p.note || '').slice(0, 200), source: slot.source, createdAt: now(),
    };
    s.appointments.push(ap);
    if (app) { if (app.status !== 'termin_gebucht') app.restoreStatus = app.status; app.status = 'termin_gebucht'; app.apptId = ap.id; app.priority = false; pushEvent(app, 'termin_gebucht', s.me.name, 'bürger', 'Vorstellungstermin gebucht', IC.fdt(ap.start) + ' Uhr'); }
    audit(s.me.name, 'bürger', 'Termin gebucht', ap.id, type.label + ', ' + IC.fdt(ap.start));
    return ok({ id: ap.id });
  };

  H.apptCancel = (p) => {
    const ap = apptById(p.id);
    if (!ap || ap.booker !== s.me.charId) return fail('Termin nicht gefunden.');
    if (['gebucht', 'eingecheckt'].indexOf(ap.status) === -1) return fail('Dieser Termin lässt sich nicht mehr absagen.');
    const late = ap.start - now() < R.cancelFreeMinutes * MIN;
    if (late) s.me.strikes.push(now());
    ap.status = 'abgesagt';
    const a = ap.applicationId ? appById(ap.applicationId) : null;
    if (a && a.status === 'termin_gebucht') { a.status = a.restoreStatus || 'vorpruefung_ok'; pushEvent(a, a.status, s.me.name, 'bürger', 'Termin abgesagt'); }
    audit(s.me.name, 'bürger', 'Termin abgesagt', ap.id, late ? 'Kurzfristig, 1 Strike' : 'Rechtzeitig');
    return ok({ strike: late });
  };

  H.apptCheckin = (p) => {
    const ap = apptById(p.id);
    if (!ap) return fail('Termin nicht gefunden.');
    const me = ap.attendees.find((x) => x.charId === s.me.charId);
    if (!me) return fail('Sie sind für diesen Termin nicht eingetragen.');
    if (['gebucht', 'eingecheckt'].indexOf(ap.status) === -1) return fail('Einchecken ist für diesen Termin nicht mehr möglich.');
    if (now() < ap.start - R.checkinBefore * MIN) return fail('Einchecken ist ab ' + R.checkinBefore + ' Minuten vor Terminbeginn möglich (ab ' + IC.ftime(ap.start - R.checkinBefore * MIN) + ' Uhr).');
    if (now() > ap.start + R.checkinAfter * MIN) return fail('Das Check-in-Fenster ist geschlossen.');
    me.checkedIn = true;
    /* Vorschau: Mitgründer sind echte Spieler. Hier treffen sie gemeinsam mit Ihnen ein. */
    const others = ap.attendees.filter((x) => x.charId !== s.me.charId && !x.checkedIn);
    others.forEach((x) => { x.checkedIn = true; });
    if (ap.attendees.filter((x) => x.mandatory).every((x) => x.checkedIn)) ap.status = 'eingecheckt';
    return ok({ allIn: ap.status === 'eingecheckt', othersIn: others.length });
  };

  H.queueTake = (p) => {
    const type = typeOf(p.typeId || 'beratung');
    if (s.myTicket) return fail('Sie haben bereits die Wartenummer ' + s.myTicket.no + '.');
    if (eligibleCount(type) < 1) return fail('Zurzeit ist kein Beamter im Dienst. Eine Wartenummer ist nicht möglich.');
    s.queueSeq++;
    const no = 'A-' + String(s.queueSeq).padStart(3, '0');
    s.queue.push({ no, who: s.me.name, typeId: type.key, at: now(), mine: true });
    s.myTicket = { no, typeId: type.key, at: now() };
    const pos = s.queue.length;
    return ok({ no, position: pos, etaMin: Math.max(3, Math.round((pos * 8) / Math.max(1, dutyList().length))) });
  };
  H.queueLeave = () => {
    if (!s.myTicket) return ok();
    s.queue = s.queue.filter((q) => q.no !== s.myTicket.no);
    s.myTicket = null;
    return ok();
  };
  H.notifyOnDuty = (p) => { s.me.notifyOnDuty = !!p.enabled; return ok({ enabled: s.me.notifyOnDuty }); };

  /* ----- Beamte ----- */
  const needOnDuty = () => (s.meOfficial.state !== 'on' ? fail('Sie müssen im Dienst sein, um diese Aktion auszuführen.') : null);
  const needRank = (r) => (lvl(s.meOfficial.rank) < lvl(r) ? fail('Dafür ist mindestens der Rang „' + L.RANK[r].label + '“ erforderlich.') : null);

  H.dutySet = (p) => {
    const o = s.meOfficial;
    const was = o.state;
    o.state = p.state;
    if (p.desk) o.desk = p.desk;
    audit(o.name, 'beamter', 'Dienststatus', o.dienstnr, was + ' → ' + p.state);
    if (p.state === 'on' && was !== 'on' && s.me.notifyOnDuty) {
      s.me.notifyOnDuty = false;
      notice('Ein Beamter ist jetzt im Dienst. Termine sind buchbar.', 'ok');
    }
    return ok({ state: o.state });
  };

  H.appReview = (p) => {
    const e = needOnDuty() || needRank('sachbearbeiter');
    if (e) return e;
    const a = appById(p.id);
    if (!a || a.status !== 'eingereicht') return fail('Dieser Antrag wartet nicht auf die Vorprüfung.');
    const msg = String(p.message || '').trim();
    const o = s.meOfficial;
    if (p.result === 'ok') {
      a.status = 'vorpruefung_ok';
      a.vorpruefungAt = now();
      pushEvent(a, 'vorpruefung_ok', o.name, 'beamter', 'Vorprüfung bestanden', msg || null);
      if (mine(a)) notice('Die Vorprüfung für „' + a.name + '“ ist bestanden. Sie können jetzt einen Termin im Bürgeramt buchen.', 'ok');
    } else if (p.result === 'nachbesserung') {
      if (msg.length < 10) return fail('Bitte beschreiben, was nachgebessert werden muss (mindestens 10 Zeichen).');
      a.status = 'nachbesserung';
      a.remark = msg;
      pushEvent(a, 'nachbesserung', o.name, 'beamter', 'Nachbesserung erforderlich', msg);
      if (mine(a)) notice('Für „' + a.name + '“ ist eine Nachbesserung erforderlich.', 'warn');
    } else if (p.result === 'abgelehnt') {
      if (msg.length < 10) return fail('Eine Ablehnung braucht eine Begründung (mindestens 10 Zeichen).');
      a.status = 'abgelehnt';
      a.objectionUntil = now() + R.objectionHours * HOUR;
      a.decision = { decision: 'abgelehnt', reason: msg, by: o.name, at: now(), conditions: [] };
      refund(a);
      pushEvent(a, 'abgelehnt', o.name, 'beamter', 'Antrag abgelehnt', msg);
      if (mine(a)) notice('Der Antrag „' + a.name + '“ wurde abgelehnt. Einspruch ist ' + R.objectionHours + ' Stunden lang möglich.', 'bad');
    } else return fail('Unbekanntes Ergebnis.');
    audit(o.name, 'beamter', 'Vorprüfung', a.caseNo, p.result + (msg ? ': ' + msg.slice(0, 60) : ''));
    return ok();
  };

  H.conflictReport = (p) => {
    const a = appById(p.id);
    if (!a) return fail('Antrag nicht gefunden.');
    a.conflicts = (a.conflicts || []).concat(s.meOfficial.id);
    audit(s.meOfficial.name, 'beamter', 'Befangenheit gemeldet', a.caseNo, 'Antrag wird an einen anderen Beamten übergeben');
    return ok();
  };

  H.apptCall = (p) => {
    const e = needOnDuty();
    if (e) return e;
    const ap = apptById(p.id);
    if (!ap || ['gebucht', 'eingecheckt'].indexOf(ap.status) === -1) return fail('Dieser Termin lässt sich nicht aufrufen.');
    ap.status = 'aufgerufen';
    s.calling = { no: ap.id, desk: s.meOfficial.desk, at: now() };
    if (ap.booker === s.me.charId) notice('Sie werden aufgerufen: Schalter ' + s.meOfficial.desk + '.', 'warn');
    return ok();
  };

  H.apptStart = (p) => {
    const e = needOnDuty();
    if (e) return e;
    const ap = apptById(p.id);
    if (!ap || ['gebucht', 'eingecheckt', 'aufgerufen'].indexOf(ap.status) === -1) return fail('Dieser Termin lässt sich nicht starten.');
    const type = typeOf(ap.typeId);
    const r = needRank(type.minRank);
    if (r) return r;
    const missing = ap.attendees.filter((x) => x.mandatory && !x.checkedIn);
    if (missing.length) return fail('Pflichtteilnehmer fehlen noch: ' + missing.map((m) => m.name).join(', ') + '.');
    ap.status = 'laeuft';
    ap.official = { id: s.meOfficial.id, name: s.meOfficial.name };
    ap.startedAt = now();
    const a = ap.applicationId ? appById(ap.applicationId) : null;
    if (a && a.status === 'termin_gebucht') { a.status = 'termin_laeuft'; pushEvent(a, 'termin_laeuft', s.meOfficial.name, 'beamter', 'Vorstellungstermin begonnen'); }
    return ok();
  };

  H.apptNoShow = (p) => {
    const e = needOnDuty();
    if (e) return e;
    const ap = apptById(p.id);
    if (!ap || OPEN_APPT.indexOf(ap.status) === -1 || ap.status === 'laeuft') return fail('Dieser Termin lässt sich nicht als „nicht erschienen“ markieren.');
    if (now() < ap.start + R.checkinAfter * MIN && !p.force) return fail('Erst ' + R.checkinAfter + ' Minuten nach Terminbeginn möglich (ab ' + IC.ftime(ap.start + R.checkinAfter * MIN) + ' Uhr).');
    ap.status = p.excused ? 'abgesagt' : 'nicht_erschienen';
    if (!p.excused && ap.booker === s.me.charId) s.me.strikes.push(now());
    const a = ap.applicationId ? appById(ap.applicationId) : null;
    if (a && a.status === 'termin_gebucht') { a.status = a.restoreStatus || 'vorpruefung_ok'; pushEvent(a, a.status, s.meOfficial.name, 'beamter', p.excused ? 'Termin entschuldigt' : 'Gründer nicht erschienen'); }
    audit(s.meOfficial.name, 'beamter', p.excused ? 'Entschuldigt' : 'Nicht erschienen', ap.id, ap.bookerName);
    return ok();
  };

  H.queueNext = () => {
    const e = needOnDuty();
    if (e) return e;
    const q = s.queue.shift();
    if (!q) return fail('Die Warteschlange ist leer.');
    s.calling = { no: q.no, desk: s.meOfficial.desk, at: now() };
    if (s.myTicket && s.myTicket.no === q.no) notice('Ihre Wartenummer ' + q.no + ' wird aufgerufen: Schalter ' + s.meOfficial.desk + '.', 'warn');
    return ok({ no: q.no });
  };

  H.apptDecide = (p) => {
    const e = needOnDuty();
    if (e) return e;
    const ap = apptById(p.id);
    if (!ap || ap.status !== 'laeuft') return fail('Der Termin muss laufen, bevor entschieden werden kann.');
    const type = typeOf(ap.typeId);
    const r = needRank('sachbearbeiter') || needRank(type.minRank);
    if (r) return r;
    const reason = String(p.reason || '').trim();
    const conds = (p.conditions || []).map((c) => String(c).trim()).filter(Boolean);
    const list = cfg.checklists[type.key] || [];
    const checked = p.checklist || {};
    const a = ap.applicationId ? appById(ap.applicationId) : null;
    const ent = ap.entityId ? entById(ap.entityId) : null;
    const dec = p.decision;
    if (['genehmigt', 'auflagen', 'vertagt', 'abgelehnt'].indexOf(dec) === -1) return fail('Bitte eine Entscheidung wählen.');
    if (dec === 'genehmigt' || dec === 'auflagen') {
      const open = list.filter((i) => !i.optional && !checked[i.key]);
      if (dec === 'genehmigt' && open.length) return fail('Für eine Genehmigung müssen alle Pflichtpunkte der Checkliste erfüllt sein (offen: ' + open.length + ').');
    }
    if (dec === 'auflagen' && !conds.length) return fail('Bitte mindestens eine Auflage angeben.');
    if (dec !== 'genehmigt' && reason.length < 10) return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).');
    const o = s.meOfficial;
    ap.status = 'abgeschlossen';
    ap.result = { decision: dec, reason, conditions: conds, by: o.name, at: now() };
    s.treasury -= R.officialPay;
    let outcome = null;
    if (type.key === 'beratung') {
      outcome = 'beratung';
    } else if (type.key === 'aenderung' && ent) {
      if (dec === 'genehmigt' && ent.pendingChange) {
        if (ent.pendingChange.type === 'name') ent.name = ent.pendingChange.value; else ent.hq = ent.pendingChange.value;
        ent.pendingChange = null; outcome = 'geaendert';
      } else if (dec !== 'genehmigt') { ent.pendingChange = null; outcome = 'abgelehnt'; }
    } else if (type.key === 'nachkontrolle' && ent) {
      if (dec === 'genehmigt') { ent.conditions.forEach((c) => { c.done = true; }); if (ent.status === 'probezeit') ent.status = 'aktiv'; outcome = 'erfuellt'; }
      else outcome = 'offen';
    } else if (a) {
      a.decision = { decision: dec, reason, by: o.name, at: now(), conditions: conds };
      if (type.key === 'einspruch') {
        if (dec === 'genehmigt' || dec === 'auflagen') {
          pushEvent(a, 'einspruch', o.name, 'beamter', 'Einspruch stattgegeben', reason || null);
          if (staffGateNeeded(a)) { a.status = 'staff_pruefung'; outcome = 'staff'; } else { registerEntity(a); outcome = 'eingetragen'; }
        } else { a.status = 'abgelehnt'; a.objectionUntil = 0; pushEvent(a, 'abgelehnt', o.name, 'beamter', 'Einspruch zurückgewiesen', reason); outcome = 'abgelehnt'; }
      } else if (dec === 'genehmigt' || dec === 'auflagen') {
        pushEvent(a, 'termin_laeuft', o.name, 'beamter', dec === 'auflagen' ? 'Genehmigt mit Auflagen' : 'Genehmigt', reason || null);
        if (staffGateNeeded(a)) {
          a.status = 'staff_pruefung';
          pushEvent(a, 'staff_pruefung', 'Registerführung', 'system', 'Schlussprüfung durch die Registerführung', 'Die Eintragung wird nach der Schlussprüfung vollzogen.');
          outcome = 'staff';
        } else { registerEntity(a); outcome = 'eingetragen'; }
      } else if (dec === 'vertagt') {
        a.status = 'nachbesserung'; a.remark = reason; a.priority = true;
        pushEvent(a, 'nachbesserung', o.name, 'beamter', 'Vertagt, Nachbesserung erforderlich', reason);
        outcome = 'vertagt';
      } else {
        a.status = 'abgelehnt'; a.objectionUntil = now() + R.objectionHours * HOUR; refund(a);
        pushEvent(a, 'abgelehnt', o.name, 'beamter', 'Antrag abgelehnt', reason);
        outcome = 'abgelehnt';
      }
      if (mine(a)) notice('Entscheidung zu „' + a.name + '“: ' + L.DECISION[dec].label + '.', dec === 'abgelehnt' ? 'bad' : dec === 'vertagt' ? 'warn' : 'ok');
    }
    audit(o.name, 'beamter', 'Entscheidung', a ? a.caseNo : ap.id, L.DECISION[dec].label + (reason ? ': ' + reason.slice(0, 60) : ''));
    return ok({ outcome, decision: dec, caseNo: a ? a.caseNo : null, regNo: a && a.entityId ? entById(a.entityId).regNo : null });
  };

  H.hoursCreate = (p) => {
    const e = needRank('sachbearbeiter');
    if (e) return e;
    const start = Number(p.start), end = Number(p.end);
    if (!(end > start)) return fail('Das Ende muss nach dem Beginn liegen.');
    if (end - start < 30 * MIN) return fail('Eine Sprechzeit dauert mindestens 30 Minuten.');
    if (start < now()) return fail('Sprechzeiten müssen in der Zukunft liegen.');
    if (start > now() + R.bookAheadDays * DAY) return fail('Sprechzeiten sind höchstens ' + R.bookAheadDays + ' Tage im Voraus möglich.');
    if (s.officeHours.some((h) => h.officialId === s.meOfficial.id && h.start < end && h.end > start)) return fail('Sie haben in diesem Zeitraum bereits eine Sprechzeit.');
    const h = { id: 'H-' + nextNo('hours'), officialId: s.meOfficial.id, start, end, types: null };
    s.officeHours.push(h);
    audit(s.meOfficial.name, 'beamter', 'Sprechzeit veröffentlicht', h.id, IC.fdt(start) + ' bis ' + IC.ftime(end));
    return ok({ id: h.id });
  };
  H.hoursDelete = (p) => {
    const h = s.officeHours.find((x) => x.id === p.id);
    if (!h) return fail('Sprechzeit nicht gefunden.');
    if (h.officialId !== s.meOfficial.id && lvl(s.meOfficial.rank) < lvl('amtsleiter')) return fail('Fremde Sprechzeiten kann nur ein Amtsleiter löschen.');
    s.officeHours.splice(s.officeHours.indexOf(h), 1);
    audit(s.meOfficial.name, 'beamter', 'Sprechzeit gelöscht', h.id, IC.fdt(h.start));
    return ok();
  };

  H.sanctionIssue = (p) => {
    const e = needOnDuty() || needRank('amtsleiter');
    if (e) return e;
    const ent = entById(p.entityId);
    if (!ent) return fail('Eintrag nicht gefunden.');
    const reason = String(p.reason || '').trim();
    if (reason.length < 10) return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).');
    ent.history = ent.history || [];
    ent.history.push({ ts: now(), level: p.level, reason, by: s.meOfficial.name });
    if (p.level === 'auflage') ent.conditions.push({ id: 'C-' + nextNo('cond'), text: reason, due: now() + 14 * DAY, done: false });
    if (p.level === 'untersagung') ent.status = 'gesperrt';
    if (p.level === 'entzug') { ent.status = 'aufgeloest'; ent.dissolvedAt = now(); }
    if (p.level === 'bussgeld') { s.treasury += 500; }
    audit(s.meOfficial.name, 'beamter', 'Sanktion: ' + L.SANCTION[p.level], ent.regNo, reason.slice(0, 60));
    return ok();
  };

  /* ----- Staff ----- */
  H.staffGate = (p) => {
    const a = appById(p.id);
    if (!a || a.status !== 'staff_pruefung') return fail('Dieser Antrag wartet nicht auf die Schlussprüfung.');
    if (p.decision === 'freigeben') {
      if (a.ooc && a.ooc.category === 'untergrund' && s.staff.undergroundCap.used >= s.staff.undergroundCap.max) return fail('Alle Untergrund-Plätze sind belegt. Erhöhen Sie die Kapazität oder weisen Sie den Antrag zurück.');
      registerEntity(a, 'Registerführung');
      audit('Staff', 'staff', 'Freigabe', a.caseNo, a.name);
      return ok();
    }
    const note = String(p.note || '').trim();
    if (note.length < 10) return fail('Bitte einen Grund angeben (mindestens 10 Zeichen).');
    a.status = 'nachbesserung';
    a.remark = 'Hinweis der Registerführung: ' + note;
    pushEvent(a, 'nachbesserung', 'Registerführung', 'staff', 'Schlussprüfung nicht bestanden', note);
    audit('Staff', 'staff', 'Zurückgewiesen', a.caseNo, note.slice(0, 60));
    return ok();
  };
  H.staffEntityStatus = (p) => {
    const e = s.entities.find((x) => x.id === p.id);
    if (!e) return fail('Eintrag nicht gefunden.');
    if (['aktiv', 'ruhend', 'gesperrt', 'aufgeloest'].indexOf(p.status) === -1) return fail('Unbekannter Status.');
    if (e.status === 'aufgeloest') return fail('Ein aufgelöster Eintrag lässt sich nicht mehr ändern.');
    if (e.status === p.status) return fail('Der Eintrag hat diesen Status bereits.');
    const reason = String(p.reason || '').trim();
    if (reason.length < 10) return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).');
    const old = e.status;
    e.status = p.status;
    if (p.status === 'aufgeloest') e.dissolvedAt = now();
    e.history = e.history || [];
    e.history.push({ ts: now(), level: 'status', reason: reason + ' (' + old + ' → ' + p.status + ')', by: 'Registerführung' });
    audit('Staff', 'staff', 'Eingriff Register', e.regNo, p.status + ': ' + reason.slice(0, 60));
    return ok();
  };
  H.staffWritten = (p) => {
    if (!s.staff.settings.writtenProcedure) return fail('Das schriftliche Verfahren ist abgeschaltet.');
    const a = appById(p.id);
    if (!a || a.status !== 'vorpruefung_ok') return fail('Dieser Antrag ist nicht für das schriftliche Verfahren geeignet.');
    const reason = String(p.reason || '').trim();
    if (reason.length < 10) return fail('Bitte eine Begründung angeben (mindestens 10 Zeichen).');
    a.decision = { decision: p.decision, reason, by: 'Behörde (nach Aktenlage)', at: now(), conditions: [] };
    if (p.decision === 'genehmigt') {
      pushEvent(a, 'termin_laeuft', 'Behörde', 'staff', 'Entscheidung nach Aktenlage: genehmigt', reason);
      if (staffGateNeeded(a)) { a.status = 'staff_pruefung'; pushEvent(a, 'staff_pruefung', 'Registerführung', 'system', 'Schlussprüfung durch die Registerführung'); } else registerEntity(a, 'Behörde');
    } else {
      a.status = 'abgelehnt'; a.objectionUntil = now() + R.objectionHours * HOUR; refund(a);
      pushEvent(a, 'abgelehnt', 'Behörde', 'staff', 'Entscheidung nach Aktenlage: abgelehnt', reason);
    }
    audit('Staff', 'staff', 'Entscheidung nach Aktenlage', a.caseNo, p.decision + ': ' + reason.slice(0, 50));
    if (mine(a)) notice('Entscheidung nach Aktenlage zu „' + a.name + '“: ' + L.DECISION[p.decision].label + '.', p.decision === 'genehmigt' ? 'ok' : 'bad');
    return ok();
  };
  H.staffCap = (p) => {
    const b = branchOf(p.key);
    if (!b) return fail('Branche nicht gefunden.');
    s.staff.capOverrides[p.key] = IC.clamp(Math.round(Number(p.value) || 0), 0, 99);
    audit('Staff', 'staff', 'Kapazität', b.label, String(s.staff.capOverrides[p.key]));
    return ok();
  };
  H.staffBlacklistAdd = (p) => {
    const term = String(p.term || '').trim();
    if (term.length < 3) return fail('Der Begriff braucht mindestens 3 Zeichen.');
    if (s.staff.blacklist.some((b) => IC.normName(b.term) === IC.normName(term))) return fail('Dieser Begriff ist bereits gesperrt.');
    s.staff.blacklist.push({ id: 'B-' + nextNo('black'), term, reason: String(p.reason || 'Staff').trim() || 'Staff' });
    audit('Staff', 'staff', 'Sperrliste', term, 'hinzugefügt');
    return ok();
  };
  H.staffBlacklistRemove = (p) => {
    const i = s.staff.blacklist.findIndex((b) => b.id === p.id);
    if (i < 0) return fail('Eintrag nicht gefunden.');
    audit('Staff', 'staff', 'Sperrliste', s.staff.blacklist[i].term, 'entfernt');
    s.staff.blacklist.splice(i, 1);
    return ok();
  };
  const SETTING_LABEL = {
    requireOfficials: 'Beamtenpflicht für Termine', writtenProcedure: 'Schriftliches Verfahren (Notfallregel)',
    undergroundViaPortal: 'Untergrund-Fraktionen über das Portal', fourEyes: 'Vier-Augen-Prinzip für Organisationen',
  };
  H.staffSetting = (p) => {
    if (!(p.key in s.staff.settings)) return fail('Unbekannte Einstellung.');
    s.staff.settings[p.key] = !!p.value;
    audit('Staff', 'staff', 'Einstellung', SETTING_LABEL[p.key] || p.key, p.value ? 'eingeschaltet' : 'ausgeschaltet');
    return ok();
  };

  /* ----- Nur Vorschau ----- */
  H.pvSetOfficials = (p) => { s.officialsOthers = IC.clamp(Math.round(p.n), 0, cfg.officials.length); return ok(); };
  H.pvSetRank = (p) => { s.meOfficial.rank = p.rank; return ok(); };
  H.pvAdvance = (p) => { IC.clock.offset += p.minutes * MIN; tick(); return ok(); };
  H.pvReset = () => { IC.clock.offset = 0; s = IC.mockSeed(); return ok(); };

  async function handle(name, data) {
    await delay();
    const fn = H[name];
    if (!fn) return fail('Unbekannte Aktion: ' + name);
    try { return fn(data || {}); } catch (err) { console.error(err); return fail('Interner Fehler: ' + err.message); }
  }

  IC.mock = { handle, state: () => s };
})();
