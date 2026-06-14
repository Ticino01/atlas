# QuickOpen — Universal Search for Windows

A unified search across files, Outlook emails, contacts, and calendar events.
One hotkey → fuzzy search everything → open the right thing in the right app.

## Architecture

Three layers, kept strictly separate:

1. **Indexers** — background scripts that scan data sources and write to SQLite
2. **Search** — queries the index, ranks results, shows the picker
3. **Actions** — opens the chosen result in the appropriate app

## Files

- `db-init.ps1` — creates the SQLite database and schema (run once)
- `index-files.ps1` — indexes your Documents, Desktop, OneDrive folders
- `index-outlook.ps1` — indexes Outlook emails, contacts, calendar
- `index-all.ps1` — runs all indexers (schedule this in Task Scheduler)
- `quickopen.ps1` — the main entry point: search box → pick → open
- `config.psd1` — your settings (folders to index, etc.)

## Setup

1. Install PSSQLite: `Install-Module PSSQLite -Scope CurrentUser`
2. Edit `config.psd1` to point at your folders
3. Run `.\db-init.ps1` once to create the database
4. Run `.\index-all.ps1` to do the first indexing (takes a few minutes)
5. Run `.\quickopen.ps1` to search

## Hotkey (optional, recommended)

Install AutoHotkey, then create `quickopen.ahk`:

```
^!Space::Run, powershell.exe -WindowStyle Hidden -File "C:\path\to\quickopen.ps1"
```

Now Ctrl+Alt+Space opens QuickOpen from anywhere.

## Scheduled re-indexing

Open Task Scheduler → Create Task → trigger every 30 minutes →
action: `powershell.exe -File "C:\path\to\index-all.ps1"`
