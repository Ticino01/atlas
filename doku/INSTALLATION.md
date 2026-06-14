# Atlas - Installationsanleitung

Diese Anleitung führt Schritt für Schritt durch die Einrichtung von
Atlas auf einem Windows-System. Komplette Installation dauert etwa
20-30 Minuten.

---

## Voraussetzungen

| Komponente              | Mindestversion       | Pflicht / Optional |
|-------------------------|----------------------|--------------------|
| Windows                 | 10 oder 11           | Pflicht            |
| PowerShell              | 5.1                  | Pflicht            |
| PSSQLite-Modul          | 1.1.0                | Pflicht            |
| AutoHotkey              | 1.1                  | Optional           |
| Google Chrome           | aktuelle Version     | Optional           |

---

## Schritt 1: Projektordner einrichten

Kopiere alle Atlas-Dateien in einen Projektordner, z.B.:

```
C:\school\M122 and M431 Projekt\
```

Erforderliche Dateien:

```
atlas-ui.ps1
quickopen.ps1
atlas.ahk
atlas.ico
db-init.ps1
config.ps1
index-all.ps1
index-files.ps1
index-chrome.ps1
index-recent.ps1
lib-log.ps1
lib-search.ps1
lib-incremental.ps1
```

---

## Schritt 2: PowerShell-Ausführungsrichtlinie

Atlas verwendet PowerShell-Skripte. In Windows ist deren Ausführung
standardmässig blockiert.

**Variante A** (wenn nicht durch Group Policy blockiert):

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

**Variante B** (empfohlen, funktioniert immer):

Statt die Policy zu ändern, alle Skript-Aufrufe mit `-ExecutionPolicy Bypass`
starten. Diese Variante wird in der `atlas.ahk` und in der Aufgabenplanung
bereits verwendet.

---

## Schritt 3: PSSQLite-Modul installieren

PSSQLite ermöglicht den Zugriff auf SQLite-Datenbanken.

### Bei Standard-Installation

```powershell
Install-Module PSSQLite -Scope CurrentUser
```

### Bei OneDrive-umgeleiteten Benutzerordnern

In Firmenumgebungen ist der Modul-Standardpfad oft im OneDrive-Ordner mit
Sonderzeichen, was zu Fehlern führt. Workaround:

```powershell
# Sauberen Modul-Pfad ausserhalb von OneDrive erstellen
New-Item -ItemType Directory -Path "C:\PSModules" -Force

# Modul direkt in diesen Ordner laden
Save-Module -Name PSSQLite -Path "C:\PSModules"
```

### Verifizieren

```powershell
$env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
Import-Module PSSQLite
Get-Command -Module PSSQLite
```

Sollte eine Liste mit Befehlen anzeigen, darunter `Invoke-SqliteQuery`.

---

## Schritt 4: Konfiguration anpassen

Öffne `config.ps1` mit einem Texteditor und passe die `FileFolders` an
deine Umgebung an. Die Standardkonfiguration nutzt `[Environment]::GetFolderPath()`,
was OneDrive-Umleitungen automatisch berücksichtigt:

```powershell
FileFolders = @(
    [Environment]::GetFolderPath('MyDocuments')
    [Environment]::GetFolderPath('Desktop')
    "$env:USERPROFILE\Downloads"
)
```

Für zusätzliche Ordner ergänzen, z.B.:

```powershell
FileFolders = @(
    [Environment]::GetFolderPath('MyDocuments')
    [Environment]::GetFolderPath('Desktop')
    "$env:USERPROFILE\Downloads"
    "$env:OneDriveCommercial\Projekte"
    "D:\Wichtige_Daten"
)
```

---

## Schritt 5: Datenbank initialisieren

Im Projektordner ausführen:

```powershell
cd "C:\school\M122 and M431 Projekt"
powershell.exe -ExecutionPolicy Bypass -File .\db-init.ps1
```

Erwartete Ausgabe:

```
[INFO] [db-init] Created folder: C:\Users\<name>\AppData\Local\Atlas
[INFO] [db-init] Initializing database at: C:\Users\<name>\AppData\Local\Atlas\index.db
[SUCCESS] [db-init] Database ready
```

---

## Schritt 6: Erste Indexierung

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\index-all.ps1
```

Dieser Lauf dauert je nach Datenmenge 10-60 Sekunden und indexiert:
- Dateien in den konfigurierten Ordnern
- Chrome-Browserverlauf (falls Chrome installiert)
- Chrome-Lesezeichen (falls vorhanden)
- Windows Recent Documents

Erwartete Ausgabe (Beispiel):

```
[INFO] [orchestrator] ===== Indexing run started =====
[SUCCESS] [index-files] Files [full]: 1703 processed
[SUCCESS] [index-chrome] Total: 1198 history + 4 bookmarks
[SUCCESS] [index-recent] Recent docs: 155 indexed
[SUCCESS] [orchestrator] ===== Done in 21s =====
```

---

## Schritt 7: Suche testen

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\atlas-ui.ps1
```

Es öffnet sich ein dunkles Fenster mit Suchfeld. Tippe einen Begriff
ein, der in einer deiner Dateien oder Browser-Historie vorkommt.
Wähle einen Treffer mit den Pfeiltasten und drücke Enter.

---

## Schritt 8: AutoHotkey installieren (optional)

Für den globalen Hotkey wird AutoHotkey v1.1 benötigt.

1. Download: https://www.autohotkey.com/
2. Wähle **AutoHotkey 1.1** (nicht v2 — die Skript-Syntax ist unterschiedlich)
3. Installer mit "Express Installation" durchlaufen lassen

---

## Schritt 9: Hotkey aktivieren

In `atlas.ahk` die Pfade prüfen:

```ahk
AtlasScript := "C:\school\M122 and M431 Projekt\atlas-ui.ps1"
IndexScript := "C:\school\M122 and M431 Projekt\index-all.ps1"
```

Anpassen falls dein Pfad anders ist. Dann **Doppelklick auf `atlas.ahk`**.
Unten rechts im System-Tray erscheint das Atlas-Icon.

Test: **Strg + Alt + Leertaste** drücken — Atlas-Suchfenster öffnet sich.

---

## Schritt 10: Autostart einrichten

Damit der Hotkey nach jedem Windows-Neustart automatisch verfügbar ist:

1. **Win + R** drücken
2. `shell:startup` eingeben und Enter
3. Es öffnet sich der Autostart-Ordner
4. Im Datei-Explorer zur `atlas.ahk` navigieren
5. **Rechtsklick** → **Verknüpfung erstellen**
6. Die Verknüpfung in den Autostart-Ordner verschieben

---

## Schritt 11: Automatische Re-Indexierung

Damit der Suchindex aktuell bleibt, einen Task in der Aufgabenplanung erstellen:

1. **Win + R** → `taskschd.msc` → Enter
2. Rechts: **Aufgabe erstellen...** (NICHT "Einfache Aufgabe erstellen")

**Tab "Allgemein":**
- Name: `Atlas Reindex`
- "Mit höchsten Privilegien ausführen": **NICHT** ankreuzen

**Tab "Trigger" → Neu:**
- Aufgabe starten: **Bei Anmeldung**
- Verzögern für: **5 Minuten**
- Wiederholen alle: **30 Minuten**
- für die Dauer von: **1 Tag**

**Tab "Aktionen" → Neu:**
- Aktion: **Programm starten**
- Programm: `powershell.exe`
- Argumente:
  ```
  -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\school\M122 and M431 Projekt\index-all.ps1"
  ```
- Starten in: `C:\school\M122 and M431 Projekt`

**Tab "Bedingungen":**
- "Aufgabe nur starten, falls der Computer im Netzbetrieb ausgeführt wird": **abhaken**

OK klicken — Aufgabe ist eingerichtet. Test mit Rechtsklick → "Ausführen".

---

## Schritt 12: Verifikation

Nach abgeschlossener Installation sollten folgende Punkte funktionieren:

| Test                                              | Erwartetes Ergebnis              |
|---------------------------------------------------|----------------------------------|
| Strg+Alt+Leertaste drücken                        | Atlas-Suchfenster öffnet sich    |
| Begriff eingeben                                  | Live-Ergebnisse erscheinen       |
| Pfeiltasten + Enter                               | Datei wird geöffnet              |
| Strg+Alt+R drücken                                | Re-Indexierung startet           |
| `Get-Content "$env:LOCALAPPDATA\Atlas\logs\atlas_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 5` | Aktuelle Log-Einträge sichtbar |

---

## Troubleshooting

### "Modul PSSQLite nicht gefunden"

Der Modul-Pfad ist nicht in `$env:PSModulePath`. Lösung: in einem
Skript ausführen, nicht direkt in der Konsole. Atlas-Skripte fügen
den Pfad selbst hinzu.

### "Skript kann nicht geladen werden, da nicht digital signiert"

Group Policy erzwingt AllSigned. Lösung: alle Aufrufe mit
`-ExecutionPolicy Bypass` (siehe Schritt 2 Variante B).

### "Could not load icon"

Die `atlas.ico` ist nicht im Projektordner oder im falschen Format.
Stelle sicher dass es eine gültige Multi-Resolution-ICO ist mit
mehreren Auflösungen (16, 32, 48, 64, 128, 256 Pixel).

### Hotkey reagiert nicht

Prüfen ob AutoHotkey-Tray-Icon sichtbar ist. Falls nicht:
Doppelklick auf `atlas.ahk`.

### Outlook-Integration funktioniert nicht

Outlook-COM ist auf vielen Firmen-Rechnern blockiert (Citrix-Umgebungen).
Atlas zeigt dies durch deaktivierten `index-outlook.ps1` an.
Andere Datenquellen funktionieren weiterhin.
