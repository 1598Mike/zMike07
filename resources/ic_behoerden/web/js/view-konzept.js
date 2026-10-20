/* IC-Behördenportal · Konzept auf einen Blick (nur Vorschau, kein Teil des Spiels) */
(function () {
  'use strict';
  const IC = window.IC;
  const { html, raw, ico } = IC;
  const c = IC.c, L = IC.L, S = IC.S;

  /* ---------- Bahnendiagramm ---------- */
  function lanes() {
    const laneTop = [20, 128, 236, 344];
    const labels = [['Gründer', 'Spieler am Terminal'], ['Terminal', 'System, automatisch'], ['Bürgeramt', 'Beamte, Spieler'], ['Registerführung', 'Staff, OOC']];
    const node = (x, lane, t1, t2, cls) => {
      const y = laneTop[lane] + 25;
      return `<g class="nd-g ${cls || ''}"><rect class="nd" x="${x}" y="${y}" width="140" height="54" rx="3"/><text class="t1" x="${x + 70}" y="${y + 23}" text-anchor="middle">${t1}</text><text class="t2" x="${x + 70}" y="${y + 40}" text-anchor="middle">${t2}</text></g>`;
    };
    let svg = '<svg viewBox="0 0 1080 468" role="img" aria-labelledby="lane-t lane-d" xmlns="http://www.w3.org/2000/svg"><title id="lane-t">Gründungsablauf</title><desc id="lane-d">Vom Antrag am Terminal über Vorprüfung, Vorstellungstermin und Entscheidung bis zur Eintragung, mit optionaler Schlussprüfung durch den Staff.</desc>';
    svg += '<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" style="fill:var(--ink-2)"/></marker></defs>';
    laneTop.forEach((y, i) => {
      svg += `<rect x="0" y="${y}" width="1080" height="104" class="${i % 2 ? 'lane b' : 'lane a'}"/>`;
      svg += `<text class="lt" x="14" y="${y + 40}">${labels[i][0]}</text><text class="t2" x="14" y="${y + 58}">${labels[i][1]}</text>`;
    });
    // Verbindungen
    const P = (d, dash, arrow) => `<path class="ln${dash ? ' dash' : ''}" d="${d}" ${arrow === false ? '' : 'marker-end="url(#ah)"'}/>`;
    svg += P('M290,72 H375 V153');
    svg += P('M445,180 H530 V261');
    svg += P('M600,288 H685 V99');
    svg += P('M755,72 H840 V261');
    svg += P('M840,315 V369', true);
    svg += P('M910,288 H995 V207');
    svg += P('M910,396 H995 V288', true, false);
    svg += P('M460,288 H240 V99', true);
    svg += '<text class="t3" x="250" y="276">Nachbesserung, 7 Tage Frist</text>';
    svg += '<text class="t3" x="852" y="346">falls Staff-Gate</text>';
    // Knoten
    svg += node(150, 0, 'Antrag ausfüllen', '6 Schritte, Live-Prüfung');
    svg += node(305, 1, 'Prüfen und bezahlen', 'Name, Limits, Gebühren');
    svg += node(460, 2, 'Vorprüfung', 'Ziel: 48 Stunden', 'off');
    svg += node(615, 0, 'Termin buchen', 'nur mit Beamten da', 'key');
    svg += node(770, 2, 'Vorstellung', 'Checkliste, Entscheidung', 'off');
    svg += node(770, 3, 'Schlussprüfung', 'Untergrund, Branchen', 'ooc');
    svg += node(925, 1, 'Eintragung', 'Nummer, Gewerbeschein');
    svg += '</svg>';
    return raw(svg);
  }

  const RULES = [
    ['Kein Beamter, kein Termin', 'Termine gibt es nur, wenn Beamte im Dienst sind oder Sprechzeiten veröffentlicht haben. Gründer lassen sich benachrichtigen. Fällt ein Termin aus, gibt es Vorrang und keinen Strike.'],
    ['IC zuerst, Staff als Netz', 'Gründer und Beamte spielen den Prozess. Der Staff prüft nur OOC-Kriterien in der Schlussprüfung und pflegt Kapazitäten und Sperrliste.'],
    ['Begründung und Einspruch', 'Jede Ablehnung, Auflage und Vertagung braucht eine Begründung. Nach einer Ablehnung bleiben 48 Stunden für den Einspruch. Ein Amtsleiter entscheidet.'],
    ['Kapazitäten statt Einzelfälle', 'Branchen haben Höchstzahlen, freie Plätze sind im Terminal sichtbar. Untergrund-Fraktionen brauchen zusätzlich einen Slot.'],
    ['Schutz vor Missbrauch', 'Antragsgebühr, Namensreservierung, Strikes, Limits je Charakter, Befangenheitssperre und ein lückenloses Audit-Log.'],
    ['Bestandsschutz', 'Bestehende Fraktionen und Unternehmen werden eingetragen und bestätigen kostenlos innerhalb von 28 Tagen. Es gibt keine Sanktion.'],
  ];

  const DECISIONS = [
    ['Untergrund-Fraktionen: wie gründen?', 'Config.Organizations.undergroundViaPortal', 'Legale Hülle (IG oder Verein) plus OOC-Angaben und Staff-Gate'],
    ['Wer sind die Beamten?', 'Config.Officials', 'Eigene Fraktion mit vier Rängen, mindestens 3 aktive Beamte vor dem Start'],
    ['Terminmodus', 'Config.Appointments.mode', 'hybrid: Live-Termine plus Sprechzeiten'],
    ['Vier-Augen-Prinzip', 'Config.Decisions.fourEyes', 'Aus. Vorgesehen für Phase 2, in Version 1.0 ohne Wirkung'],
    ['Schriftliches Verfahren', 'Config.Appointments.writtenProcedure', 'An. Der Staff entscheidet nach 72 Stunden ohne Termin'],
    ['Gebührenhöhe', 'Config.LegalForms', 'Mit den Standardwerten starten, nach zwei Wochen prüfen'],
    ['Strikes und Sperren', 'Config.Rules.strikeLimit, strikeDays, banDays', '3 Strikes in 14 Tagen, 3 Tage Sperre'],
    ['Härte beim Bestandsschutz', 'Config.Legacy', 'Nur Hinweis, keine Sanktion'],
    ['Framework und Zusatzressourcen', 'Config.Framework', 'ESX, QBCore und Qbox werden erkannt. ox_inventory wird bevorzugt, ein Telefon hängt ihr über einen Hook an'],
    ['Stammkapital und Firmenkonto', 'Config.Hooks.onApproved', 'Der Hook bucht das Kapital aufs Firmenkonto und gibt true zurück, sonst geht es an den Antragsteller zurück'],
    ['Gewerbeschein-Verlängerung', 'Config.Certificate', 'In Phase 2 nachziehen'],
  ];

  function statusFlow() {
    const A = L.APP;
    const main = ['entwurf', 'eingereicht', 'vorpruefung_ok', 'termin_gebucht', 'termin_laeuft', 'staff_pruefung', 'genehmigt'];
    const side = ['nachbesserung', 'abgelehnt', 'einspruch', 'zurueckgezogen', 'abgelaufen'];
    return html`<div class="stack">
      <div class="row sm">${main.map((k, i) => html`${i ? html`<span class="muted">${ico('chev')}</span>` : ''}${c.chip(A[k].label, A[k].kind)}`)}</div>
      <div class="row sm"><span class="lbl">Seitenwege</span>${side.map((k) => c.chip(A[k].label, A[k].kind))}</div>
      <p class="small muted">Nachbesserung führt zurück in die Vorprüfung. Eine Ablehnung lässt sich 48 Stunden lang per Einspruch anfechten. „Schlussprüfung“ gibt es nur bei Untergrund-Fraktionen und sensiblen Branchen.</p>
    </div>`;
  }

  function overview() {
    return html`
      <div class="page-head"><div><div class="crumbs">Konzept · Auf einen Blick</div><h1>So läuft die IC-Gründung</h1>
        <p class="sub">Fraktionen und Unternehmen entstehen im Spiel: am Gewerbeamt-Terminal beantragen, im Bürgeramt den Beamten vorstellen, nach der Entscheidung eintragen. Der Staff bleibt das Sicherheitsnetz.</p></div></div>
      <section class="stack sm" aria-labelledby="k-flow"><h2 id="k-flow">Ablauf</h2><div class="lane-wrap">${lanes()}</div></section>
      <section class="stack sm" aria-labelledby="k-rules"><h2 id="k-rules">Kernregeln</h2>
        <div class="rules">${RULES.map((r, i) => html`<div class="rule"><h3>${r[0]}</h3><p>${r[1]}</p></div>`)}</div></section>
      <section class="stack sm" aria-labelledby="k-status"><h2 id="k-status">Status eines Antrags</h2>${c.sheet('Lebenszyklus', statusFlow(), { icon: 'list' })}</section>
      <section class="stack sm" aria-labelledby="k-dec"><h2 id="k-dec">Offene Entscheidungen</h2>
        <p class="small muted">Für jede Frage gibt es eine Empfehlung. Bis zu Ihrer Entscheidung gelten die Standardwerte.</p>
        <div class="sheet"><div class="decisions" role="table" aria-label="Offene Entscheidungen">
          <div class="dh" role="row"><span role="columnheader">#</span><span role="columnheader">Frage</span><span role="columnheader">Einstellung</span><span role="columnheader">Empfehlung</span></div>
          ${DECISIONS.map((d, i) => html`<div role="row"><span class="mono muted" role="cell">${i + 1}</span><span class="strong" role="cell">${d[0]}</span><span class="mono small" role="cell">${raw(IC.esc(d[1]).replace(/\./g, '.<wbr>'))}</span><span role="cell">${d[2]}</span></div>`)}
        </div></div></section>
      <section class="stack sm" aria-labelledby="k-pack"><h2 id="k-pack">Was im Paket ist</h2>
        <div class="grid g3">
          ${c.sheet('Dokumente', html`<ul style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px"><li>Konzept</li><li>Technik und Datenmodell</li><li>Beamten-Handbuch</li><li>Gründer-Leitfaden</li><li>Umsetzung und Go-Live</li><li>Discord-Ankündigung</li></ul>`, { icon: 'book' })}
          ${c.sheet('Oberfläche', html`<ul style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px"><li>Gewerbeamt-Terminal</li><li>Bürgeramt mit Aufrufanzeige</li><li>Beamten-Tablet</li><li>Staff-Panel</li></ul><p class="small muted" style="margin-top:8px">Diese Vorschau ist dieselbe Oberfläche, die im Spiel läuft.</p>`, { icon: 'layers' })}
          ${c.sheet('Server-Ressource', html`<ul style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px"><li>FiveM-Ressource ic_behoerden</li><li>SQL-Schema</li><li>Framework-Bridge ESX, QBCore, Standalone</li><li>Getestete Kernlogik</li></ul>`, { icon: 'tool' })}
        </div></section>`;
  }

  IC.registerApp('konzept', {
    title: 'Konzept', icon: 'book', def: 'overview',
    where: () => 'Auf einen Blick',
    nav: () => [{ id: 'overview', label: 'Auf einen Blick', icon: 'book' }],
    railFoot: () => html`Das vollständige Konzept steht in docs/KONZEPT.md.`,
    views: { overview },
  });
})();
