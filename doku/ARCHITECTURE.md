# Atlas - Architektur

Dieses Dokument beschreibt den technischen Aufbau von Atlas.
Es richtet sich an Entwickler, die Atlas verstehen, erweitern oder
warten möchten.

---

## Architektur-Überblick

Atlas folgt einer **Drei-Schichten-Architektur**, in der jede Schicht
eine klar abgegrenzte Verantwortung hat. Die Schichten kommunizieren
ausschliesslich über eine zentrale SQLite-Datenbank — sie kennen sich
gegenseitig nicht.

```
+----------------------------------------------------------+
|                   SCHICHT 1: INDEXER                     |
|                                                          |
|  +-------------+  +-------------+  +-------------+       |
|  | index-files |  |index-chrome |  |index-recent |  ...  |
|  +-------------+  +-------------+  +-------------+       |
|         |                |                |              |
|         v                v                v              |
+----------------------------------------------------------+
|              ZENTRALE SQLITE-DATENBANK                   |
|                                                          |
|  Tabelle: records          Tabelle: picks                |
|  +-----------------+       +----------------+            |
|  | id              |       | record_id      |            |
|  | type            |       | picked_at      |            |
|  | title           |       +----------------+            |
|  | subtitle        |                                     |
|  | searchable      |       Tabelle: indexer_runs         |
|  | timestamp       |       +----------------+            |
|  | action_data     |       | indexer_name   |            |
|  | indexed_at      |       | last_run       |            |
|  +-----------------+       | item_count     |            |
|                            +----------------+            |
+----------------------------------------------------------+
|         SCHICHT 2: SUCH-ENGINE (lib-search.ps1)          |
|                                                          |
|  - Volltext-Suche mit LIKE                               |
|  - Type-Filter Parsing (@file, @web, ...)                |
|  - Ranking nach Score = w1*Text + w2*Recency             |
|                       + w3*Frequency + w4*Prefix         |
+----------------------------------------------------------+
|              SCHICHT 3: USER INTERFACE                   |
|                                                          |
|  +------------------+        +-------------------+       |
|  |   atlas-ui.ps1   |        |  quickopen.ps1    |       |
|  |  (WPF Spotlight) |        |  (Fallback)       |       |
|  +------------------+        +-------------------+       |
|                                                          |
|  - Eingabeentgegennahme                                  |
|  - Aufruf der Such-Engine                                |
|  - Anzeige der Ergebnisse                                |
|  - Action-Dispatcher (Datei oeffnen, URL oeffnen, ...)   |
+----------------------------------------------------------+
```

---

## Schicht 1: Indexer

Indexer sind voneinander unabhängige Skripte. Jeder Indexer:

- Hat eine bestimmte Datenquelle (Dateien, Chrome, Recent Docs, ...)
- Schreibt seine Funde in das einheitliche `records`-Schema
- Trackt seinen letzten Lauf in der `indexer_runs`-Tabelle
- Kann in zwei Modi laufen: `full` (alles neu) oder `incremental` (nur Änderungen)

### Datensatz-Schema (records-Tabelle)

Jeder Indexer schreibt Datensätze nach demselben Schema:

```sql
CREATE TABLE records (
    id          TEXT PRIMARY KEY,    -- Eindeutige ID, z.B. "file:c:\path\file.docx"
    type        TEXT NOT NULL,        -- "file", "history", "bookmark", "recent"
    title       TEXT NOT NULL,        -- Was der Nutzer sieht
    subtitle    TEXT,                 -- Zusatzinfo (Pfad, Datum, ...)
    searchable  TEXT NOT NULL,        -- Volltext zum Durchsuchen
    timestamp   INTEGER,              -- Unix-Timestamp für Recency-Ranking
    action_data TEXT NOT NULL,        -- JSON: was tun beim Auswählen
    indexed_at  INTEGER NOT NULL      -- Unix-Timestamp des letzten Indexierens
);
```

Das ist der **Vertrag** der die Architektur zusammenhält. Solange
ein Indexer Datensätze in diesem Format schreibt, funktioniert er
mit dem Rest des Systems — ohne dass die anderen Schichten verändert
werden müssen.

### Aktive Indexer

| Indexer            | Quelle                                 | Datentyp     |
|--------------------|----------------------------------------|--------------|
| `index-files.ps1`  | Dateisystem (konfigurierbare Ordner)   | `file`       |
| `index-chrome.ps1` | Chrome `History` SQLite + `Bookmarks`  | `history`, `bookmark` |
| `index-recent.ps1` | `%APPDATA%\Microsoft\Windows\Recent`   | `recent`     |

### Inkrementelle Indexierung

Der Performance-kritische Indexer `index-files.ps1` arbeitet inkrementell:

1. Holt aus `indexer_runs` den Zeitstempel des letzten Laufs
2. Listet alle Dateien (schnell, nur Metadata)
3. Vergleicht `LastWriteTime` jeder Datei mit dem Zeitstempel
4. Nur Dateien neuer als der Zeitstempel werden re-indexiert
5. Speichert neuen Zeitstempel in `indexer_runs`

Bei einem typischen Bestand von 1700 Dateien:
- **Erster Lauf (full):** ~17 Sekunden
- **Folgeläufe (incremental):** 1-3 Sekunden

---

## Schicht 2: Such-Engine

Die Such-Engine ist als wiederverwendbare Library implementiert
(`lib-search.ps1`). Sie kann von verschiedenen UIs aufgerufen werden.

### Such-Algorithmus

```
1. Eingabe parsen
   - Type-Filter erkennen (@file, @web, ...)
   - Verbleibende Such-Worte extrahieren
   - URL-Erkennung (https://...)

2. SQL-Query bauen
   - Pro Wort: WHERE LOWER(title|subtitle|searchable) LIKE LOWER(%wort%)
   - Mehrere Worte mit AND verknüpft (alle müssen vorkommen)
   - Optional: WHERE type = '<filter>'

3. Ergebnisse re-ranken
   - Composite Score (siehe unten)
   - Nach Score absteigend sortieren
   - Top N zurückgeben
```

### Ranking-Formel

```
score = w_text * text_match
      + w_recency * recency_decay
      + w_frequency * log(1 + pick_count)
      + w_prefix * prefix_bonus
```

| Komponente       | Berechnung                              | Standardgewicht |
|------------------|-----------------------------------------|-----------------|
| text_match       | Anteil der Wörter im Titel              | 1.0             |
| recency_decay    | exp(-age_days / 30)                     | 0.5             |
| frequency        | log(1 + Anzahl Picks aus History)       | 0.3             |
| prefix_bonus     | 1.0 wenn Titel mit Suche beginnt        | 2.0             |

Die Gewichte sind in `config.ps1` einstellbar. Die `picks`-Tabelle
trackt jeden Auswahlvorgang und macht Atlas mit der Zeit smarter.

---

## Schicht 3: User Interface

Zwei UIs sind verfügbar — beide nutzen dieselbe Such-Engine.

### Haupt-UI: `atlas-ui.ps1`

Modernes WPF-Fenster im Spotlight-Stil:

- **Live-Suche** mit 200ms Debounce-Timer
- **Catppuccin Mocha Farbschema** (dunkel, augenfreundlich)
- **Tastatur-First** (Pfeiltasten, Enter, Esc)
- **Auto-Schliessen** bei Fokusverlust
- **Type-Icons** im Picker (FILE, WEB, MARK, RCNT)

### Fallback-UI: `quickopen.ps1`

Klassisches Zwei-Fenster-UI für Notfälle:

- VisualBasic InputBox für Eingabe
- `Out-GridView` für Ergebnisse
- Funktioniert ohne WPF-Abhängigkeiten

### Action-Dispatcher

Beim Auswählen eines Treffers wird `Invoke-AtlasAction` aufgerufen.
Diese Funktion liest das `action_data`-JSON-Feld und führt die
passende Aktion aus:

| action.kind     | Aktion                                |
|-----------------|---------------------------------------|
| `open-file`     | `Start-Process` mit Standardprogramm  |
| `open-url`      | `Start-Process` öffnet im Browser     |
| `open-outlook`  | Outlook-Item per COM (Citrix-deaktiv.) |

---

## Logging

Atlas verwendet ein zentrales Logging-System (`lib-log.ps1`):

- Tägliche Log-Dateien: `%LOCALAPPDATA%\Atlas\logs\atlas_YYYY-MM-DD.log`
- Logs älter als 14 Tage werden automatisch gelöscht
- Levels: INFO, WARN, ERROR, DEBUG, SUCCESS
- Format: `[Zeitstempel] [Level] [Komponente] Nachricht`

Beispiel-Logeintrag:
```
[2026-05-03 13:15:48] [SUCCESS] [index-files] Files [full]: 1703 processed
```

---

## Datenfluss-Beispiel

Ein typischer Suchvorgang von Tastendruck bis Datei-Öffnen:

```
Benutzer drückt Strg+Alt+Leertaste
        |
        v
AutoHotkey startet atlas-ui.ps1 mit -ExecutionPolicy Bypass
        |
        v
WPF-Fenster lädt, Suchfeld erhält Fokus
        |
        v
Benutzer tippt "@file budget"
        |
        v
TextChanged-Event startet 200ms Debounce-Timer
        |
        v
Timer feuert -> Update-Results wird aufgerufen
        |
        v
Parse-AtlasQuery: Type='file', CleanQuery='budget'
        |
        v
Search-AtlasIndex: SQL-Query mit type='file' AND title LIKE '%budget%'
        |
        v
Ranking: Composite-Score berechnen, Top 30 zurückgeben
        |
        v
ListView zeigt Ergebnisse, erste Zeile selektiert
        |
        v
Benutzer drückt Enter
        |
        v
Invoke-AtlasAction parst action_data JSON
        |
        v
Start-Process öffnet Datei im Standardprogramm
        |
        v
INSERT INTO picks zur Frequency-Learning
        |
        v
Fenster schliesst
```

---

## Erweiterbarkeit

Neue Datenquellen lassen sich ohne Änderung der Such-Engine oder UI hinzufügen.
Vorgehen:

1. Neue Datei `index-newsource.ps1` anlegen
2. `. "$PSScriptRoot\lib-log.ps1"`, `. "$PSScriptRoot\config.ps1"`,
   `. "$PSScriptRoot\lib-incremental.ps1"` einbinden
3. Datensätze ins `records`-Schema schreiben mit eigenem `type`-Wert
4. Optional: `Get-AtlasTypeIcon` in `lib-search.ps1` um neuen Typ ergänzen
5. Optional: `Parse-AtlasQuery` um neuen Type-Filter ergänzen
6. In `index-all.ps1` zur Indexer-Liste hinzufügen

Der gesamte restliche Code bleibt unverändert.

---

## Bekannte Einschränkungen

- **Keine Outlook-Integration** auf diesem System: Outlook läuft in
  einer Citrix-Umgebung, COM-Zugriff aus lokaler PowerShell ist
  nicht möglich. `index-outlook.ps1` ist daher in `index-all.ps1`
  auskommentiert.

- **Such-Performance ist linear** zur Datenbankgrösse, weil LIKE
  keine Indizes verwenden kann. Bei >50.000 Records wäre eine
  Migration auf SQLite FTS5 sinnvoll. PSSQLite enthält jedoch
  eine ältere SQLite-Version ohne FTS5-Support.

- **Keine Echtzeit-Updates** während die Suche offen ist. Neue
  Dateien erscheinen erst nach dem nächsten Indexer-Lauf.
