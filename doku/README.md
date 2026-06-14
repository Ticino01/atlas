# Atlas - Universal Search Tool für Windows

Atlas ist ein PowerShell-basiertes Suchwerkzeug, das verschiedene persönliche
Datenquellen — lokale Dateien, Chrome-Browserverlauf, Lesezeichen und kürzlich
geöffnete Dokumente — in einem zentralen Index zusammenführt. Über einen
globalen Hotkey kann von überall im System eine Suche gestartet werden,
deren Ergebnisse nach Relevanz, Aktualität und Nutzungshäufigkeit gewichtet
werden.

---

## Schulprojekt

| Feld    | Wert                              |
|---------|-----------------------------------|
| Modul   | M122 (Skripte erstellen) und M431 |
| Name    | Atlas                             |
| Sprache | PowerShell                        |
| Autor   | Abbas Ehsani                      |

---

## Problemstellung

Wissensarbeiter im Büroalltag verlieren täglich erhebliche Zeit beim Suchen
nach Informationen, die über mehrere isolierte Datenquellen verteilt sind:
lokale Dateien, Browser-Historie, Lesezeichen und mehr. Die in Windows
integrierte Suche ist langsam, deckt nicht alle Quellen ab und liefert oft
schlecht sortierte Ergebnisse. Das Hin- und Herwechseln zwischen verschiedenen
Anwendungen unterbricht den Arbeitsfluss.

Atlas löst dieses Problem durch eine einheitliche Suchoberfläche, die alle
relevanten Datenquellen indexiert und durchsuchbar macht.

---

## Hauptfunktionen

- **Datei-Suche** in konfigurierbaren Ordnern (inkl. OneDrive-Unterstützung)
- **Browser-Historie** aus Chrome (über lokale SQLite-Datenbank)
- **Browser-Lesezeichen** aus Chrome (über JSON-Datei)
- **Recent Documents** aus Windows (über .lnk-Auflösung)
- **Type-Filter** für gezielte Suche (`@file`, `@web`, `@bookmark`, `@recent`)
- **URL-Direct-Open** für sofortige URL-Eingabe ohne Picker
- **Lernende Rangfolge:** häufig gewählte Treffer erscheinen automatisch oben
- **Inkrementelle Indexierung** für konstante Performance auch bei grossen Datenmengen
- **Globaler Hotkey** über AutoHotkey (Strg+Alt+Leertaste)
- **Modernes WPF-UI** im Spotlight-Stil mit Live-Suche
- **Strukturiertes Logging** mit täglich rotierenden Log-Dateien

---

## Schnellstart

```powershell
# 1. PSSQLite Modul installieren (einmalig)
Save-Module -Name PSSQLite -Path "C:\PSModules"

# 2. Datenbank initialisieren
.\db-init.ps1

# 3. Erste Indexierung
.\index-all.ps1

# 4. Suche starten
.\atlas-ui.ps1
```

Detaillierte Installationsanleitung siehe [INSTALLATION.md](INSTALLATION.md).

---

## Verwendung

### Suche starten

- **Hotkey:** Strg + Alt + Leertaste (überall im System)
- **Manuell:** `.\atlas-ui.ps1`

### Such-Syntax

| Eingabe                | Verhalten                                |
|------------------------|------------------------------------------|
| `projekt`              | Sucht in allen Datenquellen              |
| `@file budget`         | Nur Datei-Treffer                        |
| `@web github`          | Nur Browser-Historie                     |
| `@bookmark`            | Alle Lesezeichen anzeigen                |
| `@recent`              | Zuletzt geöffnete Dokumente              |
| `https://example.com`  | URL direkt im Browser öffnen             |

### Tastatur-Bedienung

| Taste              | Aktion                            |
|--------------------|-----------------------------------|
| Pfeil hoch/runter  | Auswahl ändern                    |
| Enter              | Auswahl öffnen                    |
| Esc                | Fenster schliessen                |
| Klick ausserhalb   | Fenster schliessen                |

### Re-Indexierung

| Methode                              | Wann nutzen                              |
|--------------------------------------|------------------------------------------|
| Strg + Alt + R                       | Manuelle Aktualisierung                  |
| Aufgabenplanung (alle 30 Min)        | Automatisch im Hintergrund               |
| `.\index-files.ps1 -Full`            | Komplettes Neu-Indexieren erzwingen      |

---

## Projektstruktur

```
Atlas/
├── atlas-ui.ps1            # Haupt-UI (WPF Spotlight-Style Suche)
├── quickopen.ps1           # Fallback-UI (InputBox + Out-GridView)
├── atlas.ahk               # AutoHotkey-Skript für globalen Hotkey
├── atlas.ico               # App-Icon (256x256 multi-resolution)
│
├── db-init.ps1             # Datenbank-Schema initialisieren
├── config.ps1              # Benutzerkonfiguration
│
├── index-all.ps1           # Orchestrator (führt alle Indexer aus)
├── index-files.ps1         # Indexer: lokale Dateien
├── index-chrome.ps1        # Indexer: Chrome History + Bookmarks
├── index-recent.ps1        # Indexer: Windows Recent Documents
│
├── lib-log.ps1             # Logging-Bibliothek
├── lib-search.ps1          # Such- und Ranking-Logik
├── lib-incremental.ps1     # Inkrementelle Indexierung
│
├── README.md               # Dieses Dokument
├── ARCHITECTURE.md         # Architektur-Erklärung
├── INSTALLATION.md         # Detaillierte Installationsanleitung
└── DECISIONS.md            # Design-Entscheidungen mit Begründung
```

---

## Datenspeicherung

Atlas speichert alle Daten lokal auf dem Rechner des Benutzers:

| Was                  | Wo                                                |
|----------------------|---------------------------------------------------|
| Such-Index           | `%LOCALAPPDATA%\Atlas\index.db`                   |
| Logs                 | `%LOCALAPPDATA%\Atlas\logs\atlas_YYYY-MM-DD.log`  |
| Konfiguration        | `config.ps1` im Projektordner                     |

Es werden keine Daten an externe Server gesendet. Der gesamte Index liegt
ausschliesslich auf dem lokalen Rechner.

---

## Systemvoraussetzungen

- Windows 10 oder Windows 11
- PowerShell 5.1 oder neuer (in Windows enthalten)
- PSSQLite-Modul (kostenlos aus der PowerShell Gallery)
- AutoHotkey v1.1 (optional, für globalen Hotkey)
- Google Chrome (optional, für Browser-Indexierung)

---

## Lizenz und Verwendung

Atlas wurde als Schulprojekt für die Module M122 und M431 entwickelt.
Der Code steht zur freien Verfügung für Lernzwecke. Eine kommerzielle
Nutzung ist nicht vorgesehen.

---

## Weiterführende Dokumentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — Wie Atlas intern aufgebaut ist
- [INSTALLATION.md](INSTALLATION.md) — Schritt-für-Schritt-Installation
- [DECISIONS.md](DECISIONS.md) — Warum bestimmte Entscheidungen getroffen wurden
