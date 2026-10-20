# Umsetzung: Vom Konzept zum Start auf dem Server

Fahrplan, Testplan, Go-live-Checkliste und der Umgang mit dem Bestand. Fachliche Regeln stehen im [Konzept](KONZEPT.md), der Einbau in der [Technik](TECHNIK.md).

> **Ehrlich vorweg:** Die Ressource ist ausgiebig **ohne Spiel** getestet, aber **noch nie im Spiel gelaufen**. Der Testtag in Phase 2 ist deshalb keine Formsache,
> sondern der Schritt, in dem sich zeigt, ob ESX, QBCore oder Qbox, euer Inventar, euer Banking-System und die Bedienung im Spiel so reagieren, wie ich es nach ihren Schnittstellen
> angenommen habe. Plant dafür einen Tag und einen Entwicklungsserver ein.

---

## Inhalt

1. [Überblick und Zeitplan](#1-überblick-und-zeitplan)
2. [Phase 0: Entscheidungen](#2-phase-0-entscheidungen)
3. [Phase 1: Einbau und Vorbereitung](#3-phase-1-einbau-und-vorbereitung)
4. [Phase 2: Testtag auf dem Entwicklungsserver](#4-phase-2-testtag-auf-dem-entwicklungsserver)
5. [Phase 3: Pilot](#5-phase-3-pilot)
6. [Phase 4: Stichtag und Bestandsübernahme](#6-phase-4-stichtag-und-bestandsübernahme)
7. [Betrieb und Kennzahlen](#7-betrieb-und-kennzahlen)
8. [Beamte gewinnen und schulen](#8-beamte-gewinnen-und-schulen)
9. [Go-live-Checkliste](#9-go-live-checkliste)
10. [Wenn es nicht läuft: Notbremse und Rückweg](#10-wenn-es-nicht-läuft-notbremse-und-rückweg)
11. [Spätere Ausbaustufen](#11-spätere-ausbaustufen)

---

## 1. Überblick und Zeitplan

| Phase | Inhalt | Dauer (Vorschlag) | Ergebnis |
|-------|--------|-------------------|----------|
| **0** Entscheidungen | Offene Fragen aus Konzept Abschnitt 18 beantworten | 1 Abend | Eine Config, die ihr vertreten könnt |
| **1** Einbau | Ressource einbauen, Orte, Beamte, Items, Hooks, Staff-Zugang | 2 bis 4 Tage | Läuft auf dem Entwicklungsserver |
| **2** Testtag | Testplan (Abschnitt 4) mit mindestens 4 Personen durchspielen | 1 Tag | Liste der Fehler und Anpassungen |
| **3** Pilot | Wenige Beamte, ausgewählte Gründer, noch **kein** Stichtag | 1 bis 2 Wochen | Kennzahlen, justierte Gebühren, geschulte Beamte |
| **4** Stichtag | Bestand übernehmen, ankündigen, altes Verfahren schließen | 1 Tag plus 4 Wochen Begleitung | IC-Gründung ist der einzige Weg |
| **5** Betrieb | Wöchentliche Auswertung, Anpassungen | laufend | |

Parallel läuft von Anfang an **Phase B: Beamte gewinnen** (Abschnitt 8). Ohne mindestens drei aktive Beamte kein Stichtag.

---

## 2. Phase 0: Entscheidungen

Zehn Fragen sind im Konzept offen, dazu kommen zwei technische. Mit den **Empfehlungen** funktioniert alles. Entscheidet bewusst, trägt sie hier ein und lasst die Config danach nicht mehr im Alltag ändern.

| # | Frage | Empfehlung | Wo einstellen | Entschieden |
|---|-------|-----------|---------------|-------------|
| 1 | Untergrund-Fraktionen über legale Hülle plus OOC-Angaben? | ja | `Config.Organizations.undergroundViaPortal` | ☐ |
| 2 | Welcher Job und welche Ränge sind die Beamten? | Job „gov“ oder eigener Job, vier Stufen | `Config.Officials.jobs` | ☐ |
| 3 | Terminmodus | `hybrid` | `Config.Appointments.mode` | ☐ |
| 4 | Vier-Augen-Prinzip | aus (ohne Wirkung in 1.0) | `Config.Decisions.fourEyes` | ☐ |
| 5 | Schriftliches Verfahren nach 72 Stunden | an | `Config.Appointments.writtenProcedure` | ☐ |
| 6 | Gebührenhöhe | Standardwerte, nach zwei Wochen prüfen | `Config.LegalForms` | ☐ |
| 7 | Strikes und Sperren | 3 Strikes in 14 Tagen, 3 Tage Sperre | `Config.Rules.strikeLimit` u. a. | ☐ |
| 8 | Bestandsschutz-Härte | nur Hinweis, nichts sanktionieren | `Config.Legacy.restAfterDays = nil` | ☐ |
| 9 | Framework und Zusatzressourcen | automatische Erkennung, `ox_inventory`, Banking-Ressource anbinden | `Config.Framework`, `Config.Treasury` | ☐ |
| 10 | Gewerbeschein-Verlängerung | später | `Config.Certificate` | ☐ |
| 11 | **Stammkapital**: Wohin mit dem Geld bei GmbH und Stiftung? | Firmenkonto über den Hook anbinden. Sonst GmbH und Stiftung zunächst **abschalten** (siehe unten). | `Config.Hooks.onApproved` | ☐ |
| 12 | **Spielzeit und Ausweis**: Woher kommen sie? | Quelle anbinden oder die Regel bewusst weglassen | `Config.Characters` | ☐ |

**Zu Frage 11:** Solange der Hook das Kapital nicht aufs Firmenkonto bucht und `true` zurückgibt, bekommen Antragsteller es **zurück**, und die GmbH hat kein Stammkapital.
Das ist sicher, aber nicht das, was ihr wollt. Entweder bindet ihr es an, oder ihr nehmt die GmbH und die Stiftung aus `Config.LegalForms`, bis es soweit ist.

**Dazu gehören Zahlen:** Wie viele Beamte? Welche **Branchen-Kapazitäten** (`Config.Branches[].cap`) passen zu eurer Serverwirtschaft? Die Standardwerte sind Vorschläge für einen mittelgroßen Server.

---

## 3. Phase 1: Einbau und Vorbereitung

### 3.1 Technik (Verantwortlich: Technik)

- [ ] Entwicklungsserver mit **Kopie** eurer Datenbank oder frischer Datenbank bereitstellen
- [ ] Ressource einbauen ([Technik, Abschnitt 2](TECHNIK.md#2-voraussetzungen-und-installation)): `ensure`-Reihenfolge, ACE-Recht für den Staff
- [ ] **Orte** in `config.lua`: Gewerbeamt, Bürgeramt, Beamten-Schalter (am besten im selben Gebäude). Koordinaten im Spiel abholen.
- [ ] **Beamten-Job** zuordnen (`Config.Officials.jobs`)
- [ ] **Items** anlegen: Gewerbeschein, gegebenenfalls Ausweis ([Technik 5.4](TECHNIK.md#54-items))
- [ ] **Stadtkasse**: Konto in `Config.Treasury.account` oder eigene Funktionen
- [ ] **Alter, Spielzeit, Ausweis** (`Config.Characters`)
- [ ] **Hook `onApproved`**: Job anlegen, Firmenkonto, Lager, Gang-Mechaniken bei Untergrund ([Technik, Abschnitt 6](TECHNIK.md#6-hooks-exporte-und-ereignisse))
- [ ] Optional: **Telefon** (`Config.Hooks.phoneMessage`), **Discord-Webhooks** (`Config.Webhooks`)
- [ ] **Branchen und Gebühren** gegen die Serverwirtschaft prüfen (Spielergehälter, übliche Preise)
- [ ] Zeitzone des Servers auf die eurer Spieler stellen

### 3.2 Staff (Verantwortlich: Staff-Leitung)

- [ ] Wer bekommt das ACE-Recht `ic_behoerden.staff`? Mindestens zwei Personen.
- [ ] Das Panel einmal durchgehen: Übersicht, Freigaben, Eskalationen, Register, Kapazitäten, Sperrliste, Audit, Einstellungen
- [ ] **Namenssperrliste** ergänzen (Staatsfraktionen, reale Marken, beleidigende Begriffe)
- [ ] **Kapazitäten** je Branche und für Untergrund-Fraktionen festlegen (und im Staff-Team begründen: Warum 12 Gastronomen?)
- [ ] Interne Regel für die **Schlussprüfung** (Untergrund, Sicherheit, Finanz, Sonstiges): Nach welchen OOC-Kriterien gebt ihr frei oder weist zurück? Schreibt sie auf.
- [ ] Abmachung für das **Notfallverfahren** (nach 72 Stunden): Wer schaut täglich in „Eskalationen“?

### 3.3 Beamte (Verantwortlich: Behördenleitung)

Siehe Abschnitt 8. Bis zum Testtag stehen mindestens **zwei** Beamte bereit (einer Sachbearbeiter, einer Amtsleiter).

### 3.4 Dokumente

- [ ] [Beamten-Handbuch](BEAMTEN-HANDBUCH.md) an die Beamten
- [ ] [Gründer-Leitfaden](GRUENDER-LEITFADEN.md) als Spielerhilfe (Discord, Forum, Wiki)
- [ ] Ankündigungen vorbereiten ([Vorlagen](DISCORD-ANKUENDIGUNG.md))

---

## 4. Phase 2: Testtag auf dem Entwicklungsserver

Ziel: Alles durchspielen, was ich nicht ohne Spiel testen konnte. Besetzung: **ein Gründer** (zwei Charaktere), **zwei Beamte** (Sachbearbeiter, Amtsleiter), **ein Staff**, **ein Beobachter** mit Konsole. Notiert bei jedem Punkt „geht“ oder „geht nicht“ und was ihr gesehen habt.

### 4.1 Start und Technik

| # | Test | Erwartet |
|---|------|----------|
| 1 | Ressource starten | Konsole: `Framework: esx` (oder qb/qbox), `Bereit: 0 Anträge, 0 Einträge, 0 Termine`. Kein `Datenbankfehler`. |
| 2 | Konsole `icstatus` | Zahlen und richtiges Framework |
| 3 | Tabellen prüfen | In der Datenbank gibt es `ic_applications` … `ic_audit` |
| 4 | Gewerbeamt-Marker | Marker und Hilfetext erscheinen am Terminal, Taste öffnet die Oberfläche |
| 5 | Oberfläche | Schriften und Layout stimmen, Esc und das Kreuz schließen. Die Maus steuert die Oberfläche, danach die Spielfigur wieder. |
| 6 | Von der Ferne | Terminal öffnen, wegbewegen: Fenster schließt sich |
| 7 | Staff-Panel | `/icstaff` öffnet es nur mit ACE-Recht |
| 8 | Charakterwechsel | Anderen Charakter laden: Sitzung geschlossen, Daten des richtigen Charakters |

### 4.2 Charakter-Daten und Konto

| # | Test | Erwartet |
|---|------|----------|
| 9 | Startseite „Ihre Voraussetzungen“ | Alter stimmt, Ausweis/Spielzeit wie in der Config |
| 10 | Kontostand oben rechts | entspricht dem Bankkonto |
| 11 | Antrag einreichen (Einzelunternehmen) | Konto wird um $1.000 belastet. Die Stadtkasse bekommt $250 (Antragsgebühr). |
| 12 | Antrag zurückziehen | Eintragungsgebühr ($750) zurück, Antragsgebühr bleibt weg |
| 13 | Zu wenig Geld | Verständliche Fehlermeldung, nichts wird abgebucht |

### 4.3 Beamte

| # | Test | Erwartet |
|---|------|----------|
| 14 | Spieler ohne Beamten-Job am Schalter | Tablet öffnet nicht, Hinweis „nicht befugt“ |
| 15 | Beamter am Schalter | Tablet öffnet, Rang und Dienstnummer stimmen |
| 16 | Dienst einschalten | Beim Gründer sind Live-Termine buchbar |
| 17 | Job entziehen (während das Tablet offen ist) | Nächster Klick: gesperrt |
| 18 | Beamter loggt aus | Gründer sieht „kein Beamter im Dienst“ |
| 19 | Terminpauschale | Nach einem Termin $150 auf dem Konto des Beamten, Stadtkasse sinkt |

### 4.4 Mitgründer

| # | Test | Erwartet |
|---|------|----------|
| 20 | Einladen (Mitgründer in der Nähe) | Meldung beim Mitgründer, **Y** nimmt an, **N** lehnt ab. Die Tasten lassen sich ändern. |
| 21 | Mitgründer weit weg | „nicht in Ihrer Nähe“ |
| 22 | Mitgründer ohne Ausweis oder zu jung | Einladung nicht möglich, mit Grund |

### 4.5 Ablauf von Anfang bis Ende

| # | Test | Erwartet |
|---|------|----------|
| 23 | Vollständige Gründung Einzelunternehmen | Antrag → Vorprüfung → Termin → Check-in → Entscheidung → Registernummer, **Gewerbeschein im Inventar** mit Beschriftung |
| 24 | Gründer offline bei der Eintragung | Beim nächsten Login kommt der Schein |
| 25 | GmbH mit Kapital | Kapital geht aufs Firmenkonto (Hook gibt `true`) oder zurück an den Antragsteller |
| 26 | Verein mit drei Mitgründern, **Untergrund** | Beamte sehen keine OOC-Angaben, Staff-Schlussprüfung, Untergrund-Platz verbraucht |
| 27 | Nachbesserung, Ablehnung, Einspruch | Meldungen kommen an, Erstattung stimmt, Einspruch führt ein Amtsleiter |
| 28 | Hook `onApproved` | Job, Konto, Lager wie gewünscht |
| 29 | Sanktion | Nur Amtsleiter, Hook `onSanction` läuft (Bußgeld abbuchen, falls gewünscht) |

### 4.6 Randfälle

| # | Test | Erwartet |
|---|------|----------|
| 30 | Server-Neustart mit offenem Antrag und gebuchtem Termin | Alles ist danach noch da, Beamte schalten Dienst neu ein |
| 31 | Termin verstreichen lassen, kein Beamter | Status „Beamten-Ausfall“, kein Strike, Vorrang |
| 32 | Gründer erscheint nicht | Nach 10 Minuten „Nicht erschienen“: Strike. Nach drei: Sperre. |
| 33 | Mehrere Spieler gleichzeitig | Keine Doppelbuchung desselben Slots |
| 34 | Discord-Webhook | Meldungen für Antrag, Entscheidung, Schlussprüfung, Eskalation, Eintragung |
| 35 | `icimport` mit Beispieldatei | siehe Abschnitt 6 |
| 36 | Controller/Bildschirmgrößen | Oberfläche nutzbar bei 1080p und kleineren Fenstern |

### 4.7 Auswertung

Sammelt alle Abweichungen. Schickt sie mit **Konsolenausgabe**, **Uhrzeit** und **Aktenzeichen** an die Entwicklung. Typische Anpassungen: Koordinaten, Radius, Item-Name, Konto-Anbindung, Rang-Zuordnung, ein Hook.

---

## 5. Phase 3: Pilot

**Ziel:** Unter echten Bedingungen lernen, **bevor** der Stichtag das alte Verfahren schließt.

- **Teilnehmer:** 2 bis 4 Beamte, 5 bis 10 Gründer (Leute, die ohnehin gründen wollten), Staff im Hintergrund
- **Dauer:** 1 bis 2 Wochen
- **Regeln:** Das alte Verfahren läuft **parallel** weiter. Piloten gründen über das neue System.
- **Beobachtet wird:**
  - Wie lange dauert die Vorprüfung, wie lange der Weg bis zur Eintragung?
  - Sind immer Beamte da? (Beamten-Verfügbarkeit im Staff-Panel)
  - Wo hängen Gründer? (Fragen im Discord sammeln und in den Leitfaden einarbeiten)
  - Sind Gebühren und Kapazitäten sinnvoll?
  - Wie reagiert der Staff-Aufwand?
- **Am Ende:** Entscheidung **Go oder Verlängern**. Kriterien in Abschnitt 9.

---

## 6. Phase 4: Stichtag und Bestandsübernahme

### 6.1 Zeitplan rund um den Stichtag

| Wann | Was |
|------|-----|
| **T minus 14 Tage** | Ankündigung im Discord: Was ändert sich, ab wann, was passiert mit bestehenden Unternehmen |
| **T minus 7 Tage** | Beamten-Aufruf, Leitfaden veröffentlicht, **Bestandsliste** vom Staff erfassen |
| **T minus 1 Tag** | Daten prüfen, Probeimport auf dem Entwicklungsserver |
| **Stichtag** | Import auf dem Livesystem, altes Bewerbungsverfahren schließen, Ankündigung |
| **T plus 14 Tage** | Erinnerung (automatisch), Auswertung der Bestätigungen |
| **T plus 28 Tage** | Bestätigungsfrist endet. Entscheidung über „ruhend“ (Konzept Abschnitt 13) |

### 6.2 Bestandsimport

**Prinzip:** Der Staff trägt alle bestehenden Fraktionen und Unternehmen **einmalig** ins neue Register ein. Der Import vergibt Registernummern, aktiviert die Einträge und markiert sie als „Bestand“. Die Inhaber **bestätigen** ihre Daten später kostenlos.

**Schritte**

1. **Liste erstellen.** Alle bestehenden Unternehmen und Fraktionen mit Inhaber, Mitgliedern und Branche. Meist stammt sie aus eurem alten Tabellenblatt oder der Datenbank eurer Job-Ressource.
2. Als `resources/ic_behoerden/import/legacy.json` ablegen. Die Vorlage `import/legacy.example.json` zeigt das Format.
3. **Probelauf auf dem Entwicklungsserver:** Konsole `icimport`. Die Ausgabe nennt, wie viele Einträge übernommen und übersprungen wurden und **welche Zeilen Fehler hatten**.
4. Fehler in der Datei beheben, erneut `icimport` (der Befehl lässt sich **gefahrlos wiederholen**: bereits vorhandene Einträge werden übersprungen).
5. Im **Staff-Panel → Register** prüfen: Namen, Nummern, Status, Inhaber.
6. Dasselbe **live am Stichtag**.

**Format** (eine Liste von Einträgen)

| Feld | Pflicht | Bedeutung |
|------|:-------:|-----------|
| `ref` | empfohlen | Eure eigene Kennung des Eintrags. Damit erkennt der Import Wiederholungen. |
| `name` | ja | Name. Der Rechtsformzusatz (GmbH, e.V.) wird ergänzt. Prüfungen wie bei neuen Anträgen gelten **nicht**, damit Bestandsnamen geschützt sind. Doppelte Namen werden übersprungen. |
| `kind` | nein | `"unternehmen"` (Standard) oder `"fraktion"` |
| `legalForm` | nein | `einzel`, `gbr`, `gmbh` (Unternehmen) oder `ev`, `ig`, `partei`, `verband`, `stiftung` (Fraktion). Standard: `einzel` beziehungsweise `ig`. |
| `branch` | nein | Branchenschlüssel (`gastro`, `handel` …). Standard: `sonstige`. Nur bei Unternehmen. |
| `hq` | nein | Sitz als Text |
| `founded` | nein | Gründungsdatum als Zeitstempel in Millisekunden |
| `ooc` | nein | `"untergrund"` oder `"legal"` (nur Fraktionen). Wird nur dem Staff gezeigt. |
| `members` | ja | Liste aus `charId` (Charakter-ID eures Frameworks), `name`, `role`, `share` |

**Rollen:** Unternehmen: `inhaber`, `geschaeftsfuehrer`, `gesellschafter`. Organisationen: `vorsitz`, `stellv`, `kasse`, `mitglied`. Unbekannte Rollen werden zu `gesellschafter` beziehungsweise `mitglied`. Fehlt ein Leiter,
wird das erste Mitglied Inhaber, Geschäftsführer beziehungsweise Vorsitz. **Anteile** müssen 100 ergeben. Fehlen sie oder stimmen sie nicht, verteilt der Import sie gleichmäßig.

**Charakter-IDs:** ESX nutzt `identifier` (zum Beispiel `char1:abc123…`), QBCore und Qbox `citizenid`. Nur mit der richtigen ID erkennt das System die Inhaber wieder.

**Was der Import bewirkt:** Registernummer (`HRA 1043`), Status **aktiv**, Zeichen „Bestand, Bestätigung offen“, Nachricht an die Leiter, **Gewerbeschein** (sofort, oder beim nächsten Login). Der Hook `onApproved` läuft **nicht**: Eure bestehenden Jobs, Konten und
Lager laufen weiter, ihr legt nichts doppelt an. Wer die Hooks nutzen will, ruft seine Funktion selbst auf.

**Was die Inhaber tun:** Im Gewerbeamt auf **„Jetzt bestätigen“** (kostenlos, 28 Tage). Nach 14 Tagen kommt **eine** Erinnerung. Standard: danach nichts, nur Hinweis. Wer härter vorgehen will, setzt `Config.Legacy.restAfterDays = 56`: Unbestätigte Einträge
werden dann ruhend, und die Bestätigung hebt das Ruhen sofort auf.

### 6.3 Altes Verfahren schließen

- Bewerbungsformular, Ticketkategorie und Discord-Kanal **schließen oder umleiten** (Hinweis mit Link auf den Leitfaden)
- Laufende alte Anträge: bis zum Stichtag abschließen oder bewusst ins Register übernehmen
- Einen **Ansprechpartner** im Discord für Fragen benennen (zwei Wochen lang)

---

## 7. Betrieb und Kennzahlen

### 7.1 Wöchentlicher Blick (10 Minuten, Staff-Panel → Übersicht)

| Kennzahl | Ziel | Wenn nicht erreicht |
|----------|------|---------------------|
| **Beamte im Dienst / Verfügbarkeit** | ≥ 4 Stunden je Tag mit mindestens einem Beamten | Mehr Beamte gewinnen, Sprechzeiten verabreden, Terminpauschale prüfen |
| **Durchlaufzeit** Einreichung → Eintragung | ≤ 7 Tage | Engpass suchen: Vorprüfung, Termine, Staff-Gate |
| **Ablehnungsquote** | 10 bis 25 % | Zu niedrig: Beamte zu weich oder Vorprüfung zu lasch. Zu hoch: Leitfaden verbessern, Beamte schulen. |
| **No-Show-Quote** | ≤ 10 % | Erinnerungen und Leitfaden prüfen, Strikes nicht lockern |
| **Beamten-Ausfälle** | ≤ 5 % | Mehr Sprechzeiten, mehr Beamte |
| **Eskalationen** | ≤ 5 % der Anträge | Beamtenzahl und Erreichbarkeit prüfen |
| **Schlussprüfungen offen** | täglich abarbeiten | Zuständigkeit im Staff klären |

Mit wenigen Vorgängen schwanken die Quoten stark. Wertet sie ab etwa 20 Anträgen aus.

### 7.2 Regelmäßig

- **Wöchentlich:** Kennzahlen, Eskalationen, Schlussprüfungen
- **Monatlich:** Gebühren und Kapazitäten gegen die Serverwirtschaft prüfen, Sperrliste ergänzen, Audit-Stichproben (zum Beispiel bei Ablehnungen und Maßnahmen)
- **Nach jedem Update der Ressource:** Datenbank sichern, Ressource ersetzen, `config*.lua` übernehmen, `icstatus` prüfen

### 7.3 Datenbank-Sicherung

Alle Daten liegen in `ic_*`-Tabellen. Nehmt sie in euer normales Backup auf. Zum Wiederherstellen: Ressource stoppen, Tabellen einspielen, Ressource starten.

---

## 8. Beamte gewinnen und schulen

Ohne Beamte keine Termine. Das ist die **größte Betriebsgefahr** des Systems.

### 8.1 Wie viele?

| Phase | Mindestens |
|-------|-----------|
| Testtag | 2 (Sachbearbeiter, Amtsleiter) |
| Pilot | 3 |
| Stichtag | **3 aktive**, davon ein Amtsleiter. Besser 5. |

### 8.2 Wie gewinnt man sie?

- Aufruf im Discord ([Vorlage](DISCORD-ANKUENDIGUNG.md)) mit Aufgabe, Zeitaufwand und **Terminpauschale**
- Menschen ansprechen, die **gerne Rollenspiel mit Verwaltung** machen (Bürgermeister-Typen, Beamte, Juristen)
- Klare **Bewerbung** (kurz) und ein Gespräch
- Der Job „Stadtverwaltung“ braucht auch **Gehalt und Ausstattung** (Büro, Fahrzeug, Kleidung), sonst bleibt er unattraktiv

### 8.3 Schulung (60 Minuten)

| Block | Inhalt | Dauer |
|-------|--------|-------|
| 1 | Aufgabe, Haltung, Neutralität, Befangenheit ([Handbuch 1 und 15](BEAMTEN-HANDBUCH.md)) | 10 Min |
| 2 | Tablet: Dienst, Heute, Vorprüfung, Sprechzeiten | 15 Min |
| 3 | **Probetermin** mit einem Testantrag: aufrufen, starten, Checkliste, entscheiden | 20 Min |
| 4 | Entscheidungsgrundsätze, Begründungen, Beispiele, Einspruch | 10 Min |
| 5 | Fragen, Nachfragen | 5 Min |

Neue Beamte starten als **Anwärter** (Beratungen, Wartenummern) und werden nach den ersten Terminen **Sachbearbeiter**. Befördert wird über euren Job-Mechanismus, das Tablet übernimmt die neue Stufe sofort.

### 8.4 Sicherheitsnetz

- **Terminpauschale** ($150, aus der Stadtkasse) trägt die Arbeit, auch wenn die Kasse leer ist.
- **Sprechzeiten** verteilen die Last auf Zeiten, die den Beamten passen.
- **Notfallregel:** Wenn sich nach 72 Stunden kein Termin ergibt, kann der Staff nach Aktenlage entscheiden. Sie sollte die Ausnahme bleiben.

---

## 9. Go-live-Checkliste

**Technik**

- [ ] Testtag abgeschlossen, alle Punkte aus Abschnitt 4 sind „geht“
- [ ] Config ist auf dem Livesystem dieselbe wie auf dem Entwicklungsserver (Orte, Jobs, Items, Konto, Hooks)
- [ ] Datenbank gesichert, Zeitzone gesetzt
- [ ] Webhooks gesetzt und getestet
- [ ] `icimport` auf dem Entwicklungsserver erfolgreich, Bestandsliste liegt bereit

**Personal**

- [ ] **Mindestens 3** Beamte geschult, einer davon Amtsleiter
- [ ] Staff: zwei Personen mit Panel-Zugang, Schlussprüfungs-Regel steht
- [ ] Wer prüft täglich „Eskalationen“ und „Freigaben“?

**Kommunikation**

- [ ] Ankündigung veröffentlicht (mindestens 7 Tage vorher)
- [ ] Leitfaden und Handbuch auffindbar
- [ ] Altes Verfahren: Schließtermin und Umleitung vorbereitet
- [ ] Ansprechpartner im Discord benannt

**Go oder No-Go** (nach dem Pilot)

| Kriterium | Go, wenn |
|-----------|----------|
| Technik | Keine offenen Fehler, die Geld oder Daten betreffen |
| Beamte | ≥ 3 aktiv, davon ≥ 1 Amtsleiter |
| Pilot-Durchlaufzeit | ≤ 7 Tage |
| Pilot-Stimmung | Gründer und Beamte würden es so einsetzen |

---

## 10. Wenn es nicht läuft: Notbremse und Rückweg

| Problem | Maßnahme |
|---------|----------|
| **Kein Beamter erreichbar, Gründer stauen sich** | Staff aktiviert die Notfallregel (nach 72 Stunden), veröffentlicht Sprechzeiten durch bestehende Beamte, ruft zur Mithilfe auf |
| **Falsche Gebühren oder Kapazitäten** | `config_server.lua` anpassen, Ressource neu starten. Bestehende Anträge behalten ihre bezahlten Beträge. |
| **Fehler, der Geld betrifft** | Ressource stoppen (`stop ic_behoerden`): Die Daten bleiben erhalten, Anträge und Termine sind weg von der Oberfläche, aber unverändert in der Datenbank. Fehler melden. |
| **Streit über eine Entscheidung** | Staff-Panel → Audit-Log zeigt, wer wann was entschieden hat. Der Staff kann im **Register** eingreifen (sperren, ruhend stellen, auflösen). |
| **Rückweg zum alten Verfahren** | Ressource stoppen, altes Formular wieder öffnen. Die Registereinträge bleiben in der Datenbank und lassen sich später wieder aktivieren. Vergebene Jobs und Konten liegen bei euch. |

Wichtig: **Die Ressource löscht nie Geld und nie Einträge ohne Spur.** Verwahrte Beträge gehen entweder an die Stadtkasse, an das Unternehmen oder zurück an den Antragsteller. Jede Statusänderung steht im Protokoll.

---

## 11. Spätere Ausbaustufen

Nicht in Version 0.1.0 enthalten, aber vorbereitet oder gedacht:

| Funktion | Nutzen | Hinweis |
|----------|--------|---------|
| **Vier-Augen-Prinzip** | Fraktionen bräuchten die Gegenzeichnung eines zweiten Amtsleiters | Einstellung existiert, ohne Wirkung. Sinnvoll ab etwa fünf aktiven Beamten. |
| **Verlängerung des Gewerbescheins** | Betriebe, die nicht mehr aktiv sind, werden ruhend | Die Gültigkeit (90 Tage) wird schon angezeigt |
| **Verordnungen der Behördenleitung** | Gebühren und Limits im Spiel ändern | Rolle ist angelegt |
| **Alt-Hinweis** | Mehrere Charaktere eines Spielers verknüpfen | Braucht eine Kennung des Spielers aus dem Framework |
| **Kennzahlen-Kacheln** | Durchlaufzeit der Vorprüfung, Eskalationsquote | Werte lassen sich aus dem Audit-Log berechnen |
| **Steuern und laufende Gebühren** | Wirtschaftliche Anbindung der Register | Eigenes Konzept nötig |
| **Mehrere Sprachen** | | Texte stehen deutsch im Code |
