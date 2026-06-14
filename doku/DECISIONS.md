# Atlas - Design-Entscheidungen

Dieses Dokument erklärt die wichtigsten Entscheidungen während der
Entwicklung von Atlas und warum sie so getroffen wurden. Es zeigt
das Reflektieren über Trade-offs, das in echter Software-Entwicklung
zentral ist.

---

## 1. Warum PowerShell statt Python oder C#?

**Entscheidung:** PowerShell als primäre Sprache.

**Begründung:**
- Schulprojekt für M122 (Skripte erstellen) — PowerShell ist die
  natürliche Wahl in Windows-Umgebungen.
- Ohne zusätzliche Installation auf jedem Windows-System verfügbar.
- Excellente Integration mit Windows-Komponenten: COM-Objekte, WMI,
  Registry, WPF, .NET-Bibliotheken.
- WPF-UIs lassen sich direkt aus PowerShell heraus bauen.

**Alternativen die verworfen wurden:**
- **Python:** Hätte Installation und venv-Management erfordert.
- **C# (kompiliert):** Hätte Build-Step und Distribution erfordert.
  Schulprojekt soll als Skripte laufbar sein.

**Trade-off:** PowerShell ist langsamer als kompilierte Sprachen.
Bei der gegebenen Datenmenge (wenige tausend Records) jedoch nicht
spürbar.

---

## 2. Warum SQLite als Datenbank?

**Entscheidung:** SQLite über das PSSQLite-Modul.

**Begründung:**
- **Eingebettet:** Keine separate Datenbank-Installation nötig.
- **Zero-Configuration:** Eine Datei auf der Festplatte ist die ganze DB.
- **Schnell genug:** Bei <50.000 Records sind Queries unter 100ms.
- **Standard-SQL:** Erlaubt komplexe Queries mit Joins und Aggregationen.
- **Bewährt:** SQLite läuft in Smartphones, Browsern, IoT-Geräten —
  millionenfach getestet.

**Alternativen die verworfen wurden:**
- **JSON-Dateien:** Keine effiziente Suche möglich, schlechte Performance
  ab einigen tausend Einträgen.
- **CSV:** Keine Indizes, schwer zu filtern.
- **Volltext-Index in Memory:** Müsste bei jedem Skript-Aufruf neu geladen
  werden, was die Live-Suche verzögert.

---

## 3. Warum LIKE statt FTS5 für die Volltext-Suche?

**Entscheidung:** Einfache `LIKE '%wort%'`-Queries mit AND-Verknüpfung.

**Begründung:**
- Das in PSSQLite enthaltene SQLite ist eine ältere Version ohne
  FTS5-Support (siehe Fehlermeldung "no such module: fts5").
- Bei der gegebenen Datenmenge ist LIKE schnell genug (1700 Records,
  Suchen unter 100ms).
- Kein zusätzlicher Index-Wartungsaufwand: bei FTS5 müssten Trigger
  die Volltext-Tabelle synchron halten.

**Trade-off:**
- LIKE skaliert linear, bei >50.000 Records würde es spürbar langsamer.
- Keine Stemming-Unterstützung (z.B. "haus" findet nicht "häuser").

**Migration-Pfad:** Wenn der Datensatz wächst und Performance zum Problem
wird, könnte SQLite separat installiert werden (mit FTS5-Support kompiliert).
Die Architektur ist darauf vorbereitet — nur `lib-search.ps1` müsste angepasst
werden.

---

## 4. Warum Drei-Schichten-Architektur?

**Entscheidung:** Strikte Trennung in Indexer / Such-Engine / UI.

**Begründung:**
- **Erweiterbarkeit:** Neue Datenquellen (Outlook, Teams, OneNote, ...)
  lassen sich als neuer Indexer hinzufügen, ohne dass Such-Engine oder
  UI verändert werden müssen.
- **Testbarkeit:** Jede Schicht hat klar definierte Inputs und Outputs.
- **Robustheit:** Wenn ein Indexer ausfällt, funktioniert der Rest weiter.
- **Wiederverwendbarkeit:** Die Such-Engine wird vom WPF-UI und vom
  Fallback-UI gemeinsam genutzt.

**Praktischer Nutzen während der Entwicklung:**
- Als Outlook-Integration nicht funktionierte (Citrix), konnten andere
  Indexer ohne Änderung weiterarbeiten.
- Beim Wechsel von Out-GridView zu WPF musste keine Such-Logik geändert
  werden — nur die UI-Schicht.

---

## 5. Warum DELETE-INSERT statt UPSERT?

**Entscheidung:** Beim Indexieren wird zuerst gelöscht, dann eingefügt.

**Begründung:**
- Das moderne `INSERT ... ON CONFLICT DO UPDATE` (UPSERT) gibt es erst
  ab SQLite 3.24 (Juni 2018).
- PSSQLite enthält eine ältere SQLite-Version, in der UPSERT zu einem
  Syntax-Fehler führt (`near "ON": syntax error`).
- DELETE-INSERT funktioniert mit jeder SQLite-Version.

**Performance-Auswirkung:** Vernachlässigbar bei den gegebenen Datenmengen.
Bei einer typischen Indexierung von 1700 Dateien dauert der gesamte Lauf
unter 20 Sekunden — die Differenz zwischen UPSERT und DELETE-INSERT liegt
im Millisekundenbereich pro Datensatz.

---

## 6. Warum inkrementelle Indexierung?

**Entscheidung:** Nur geänderte Dateien re-indexieren, statt jedes Mal alles.

**Begründung:**
- **Skalierung:** Bei einer Aufgabenplanung die alle 30 Minuten läuft,
  wären volle Scans bei wachsendem Datensatz unzumutbar.
- **Akku-Schonung:** Notebook-Nutzer verlieren weniger Akku.
- **Reduzierte CPU-Last:** Atlas läuft im Hintergrund unauffällig.

**Implementation:**
- Eine `indexer_runs`-Tabelle trackt pro Indexer den letzten Lauf-Zeitstempel.
- Im inkrementellen Modus wird `LastWriteTime` jeder Datei mit diesem
  Zeitstempel verglichen.
- Nur neuere Dateien werden tatsächlich re-indexiert.

**Performance-Vergleich:**
- Erster Lauf (1703 Dateien, Full-Modus): ~17 Sekunden
- Folgelauf bei keinen Änderungen (incremental): 1-3 Sekunden
- Bei einer geänderten Datei: 1-3 Sekunden (gleich schnell, weil nur
  diese eine indexiert wird)

**Trade-off:** Die GC (Erkennung gelöschter Dateien) funktioniert nur im
Full-Modus zuverlässig. Workaround: einmal pro Woche (oder via `-Full`-Flag)
einen Full-Run erzwingen.

---

## 7. Warum WPF statt WinForms oder Out-GridView?

**Entscheidung:** Die Haupt-UI ist eine WPF-Anwendung, deklariert in XAML.

**Begründung:**
- **Modern:** WPF rendert vektorbasiert, unterstützt abgerundete Ecken,
  Transparenz, moderne Animationen.
- **Spotlight-Style:** Nur WPF erlaubt randlose, transparente Fenster wie
  bei macOS Spotlight oder PowerToys-Run.
- **Live-Suche:** WPF-Events erlauben einfache Implementation eines
  Debounce-Timers für die Live-Suche.
- **Dark Mode:** Catppuccin-Farbschema integriert sich harmonisch in
  moderne Windows-Themes.

**Alternativen die verworfen wurden:**
- **WinForms:** Zu altmodisch, kein randloses Design ohne komplexe Tricks.
- **Out-GridView:** Funktioniert (wird als Fallback bereitgehalten), aber
  nicht modern, keine Live-Suche, separates Eingabe-Fenster nötig.

**Beibehaltung als Fallback:** `quickopen.ps1` mit Out-GridView ist als
Backup vorhanden, falls WPF in einer eingeschränkten Umgebung nicht läuft.

---

## 8. Warum Outlook-Integration deaktiviert?

**Entscheidung:** `index-outlook.ps1` ist in `index-all.ps1` auskommentiert.

**Hintergrund:**
- Outlook auf dem Test-Rechner läuft in einer Citrix/Remote-Desktop-Umgebung.
- COM-Objekte aus lokaler PowerShell können nicht auf Citrix-Outlook
  zugreifen (Fehler: `0x80080005 CO_E_SERVER_EXEC_FAILURE`).
- Selbst `Get-Process OUTLOOK` zeigt keinen lokalen Prozess, obwohl Outlook
  scheinbar läuft.

**Lehre:** In Firmenumgebungen muss man mit virtualisierten Anwendungen
rechnen. Atlas dokumentiert diese Einschränkung transparent statt zu
versuchen, sie zu umgehen.

**Migration-Pfad:** Wenn Atlas auf einem System mit lokal installiertem
Outlook läuft, kann der Indexer einfach reaktiviert werden (Auskommentierung
in `index-all.ps1` entfernen).

---

## 9. Warum Test-Path mit Timeout?

**Entscheidung:** Im Recent-Documents-Indexer wird `Test-Path` für
Netzwerkpfade in einem Background-Job mit hartem Timeout ausgeführt.

**Hintergrund:**
- Standard-`Test-Path` blockiert bei nicht erreichbaren Netzwerk-UNC-Pfaden
  (`\\server\share\...`) bis zum SMB-Timeout (kann 30+ Sekunden sein).
- Bei 401 toten Pfaden in Recent Documents wären das mehrere Stunden
  Wartezeit pro Indexer-Lauf.

**Lösung:**
- Lokale Pfade durchlaufen den Schnellpfad ohne Job-Overhead.
- Netzwerkpfade werden in einem `Start-Job` ausgeführt, mit `Wait-Job -Timeout 1`.
- Wenn der Job nicht in 1 Sekunde antwortet, wird er abgebrochen und
  der Pfad als unerreichbar behandelt.

**Performance-Verbesserung:**
- Vorher: 56 Sekunden bei vielen toten Netzwerkpfaden
- Nachher: unter 5 Sekunden, unabhängig von der Anzahl toter Pfade

---

## 10. Warum lokales Logging mit eigenem Format?

**Entscheidung:** Eigenes Logging-System, kein PowerShell-Standard
(`Write-Host`, `Write-Verbose`).

**Begründung:**
- **Strukturiertes Format:** `[Zeitstempel] [Level] [Komponente] Nachricht`
  ist maschinenlesbar und gut filterbar.
- **Nachvollziehbarkeit:** Bei Background-Aufgabenplanung muss nachträglich
  geprüft werden können, was passiert ist. `Write-Host` schreibt nur in
  den temporären Konsolenpuffer.
- **Rotation:** Eine Log-Datei pro Tag verhindert unbegrenztes Wachstum.
  Logs älter als 14 Tage werden automatisch gelöscht.
- **Debug-Level für Detailmeldungen:** Verbose-Logs landen im File aber
  nicht in der Konsole — die normale Ausgabe bleibt sauber.

---

## 11. Warum Catppuccin Mocha als Farbschema?

**Entscheidung:** Catppuccin Mocha (dunkles Schema mit lila/rosa Akzenten)
für die WPF-UI.

**Begründung:**
- **Augenfreundlich:** Dunkles Schema reduziert Augenermüdung, besonders
  bei häufiger Nutzung.
- **Moderne Ästhetik:** Catppuccin ist eines der populärsten Farbschemata
  in der Entwickler-Community (https://catppuccin.com/).
- **Wiederverwendung:** Die gleichen Farben werden im Atlas-Icon verwendet —
  einheitliches visuelles Design.
- **Open Source:** Das Schema ist frei verwendbar und gut dokumentiert.

---

## 12. Warum AutoHotkey für den globalen Hotkey?

**Entscheidung:** Externes Tool AutoHotkey statt eigener PowerShell-Lösung.

**Begründung:**
- PowerShell kann zwar globale Hotkeys über die Win32-API registrieren,
  aber der Code dafür ist komplex und nicht besonders robust.
- AutoHotkey ist die bewährte Lösung für globale Hotkeys auf Windows —
  millionen-fach im Einsatz, auch in Power-User-Tools wie Espanso oder
  AutoHotkey-Selber.
- Bietet zusätzlich: Tray-Icon, Tooltips, einfaches Hotkey-Management.

**Trade-off:** Eine zusätzliche Abhängigkeit. Aber AutoHotkey ist klein
(~1 MB), kostenlos und seit Jahrzehnten stabil.

---

## 13. Lehrwerte des Projekts

Atlas vereint mehrere Themen aus den Modulen M122 und M431:

- **Skript-Programmierung mit PowerShell** (M122)
- **Datenbank-Design mit SQLite** (M431)
- **Drei-Schichten-Architektur** (Software-Engineering)
- **Asynchrone Verarbeitung** (Background-Jobs für Test-Path-Timeout)
- **Performance-Optimierung** (inkrementelle Indexierung)
- **WPF-UI-Programmierung** (XAML, Event-Handling)
- **Umgang mit Restriktionen** (Group Policy, Citrix, OneDrive-Pfade)

Das wertvollste Lerngut war dabei nicht der Code selbst, sondern das
**Lösen unerwarteter Probleme** während der Entwicklung: kaputte Encodings,
fehlende SQLite-Features, Citrix-Umgebungen, OneDrive-Pfad-Umleitungen.
Genau diese Probleme sind in echter IT-Praxis tagtäglich präsent.
