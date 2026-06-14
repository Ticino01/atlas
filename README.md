# 🔍 Atlas — Universal Search for Windows

> A Spotlight-inspired search tool for Windows. Press `Ctrl+Alt+Space` and instantly search across your files, Chrome history, bookmarks, Obsidian notes and Notion pages — all in one place.

---

## 📸 Screenshot

<img width="702" height="503" alt="image" src="https://github.com/user-attachments/assets/5c810692-9660-4158-8d14-df5dd784ada7" />



---

## ✨ Features

- **Global Hotkey** — Open Atlas from anywhere with `Ctrl+Alt+Space`
- **File Search** — Searches your Documents, Desktop and Downloads folders
- **Chrome Integration** — Search your browser history and bookmarks
- **Obsidian** — Search your Obsidian vault notes in real time
- **Notion** — Search your Notion pages via the Notion API
- **Type Filters** — Filter by source with `@chrome`, `@obsidian`, `@notion`, `@files`
- **Dark Theme** — Beautiful Catppuccin Mocha dark UI
- **Fast** — 200ms debounced search, local SQLite index
- **Auto Re-index** — Task Scheduler re-indexes every 30 minutes in the background

---

## 🚀 Getting Started

### Requirements

- Windows 10 / 11
- PowerShell 5.1+
- [AutoHotkey v1.1](https://www.autohotkey.com/)
- [PSSQLite Module](https://github.com/RamblingCookieMonster/PSSQLite) installed at `C:\PSModules\PSSQLite\1.1.0`

### Installation

1. Clone the repository:
```powershell
git clone https://github.com/YOUR-USERNAME/atlas.git
cd atlas
```

2. Copy the secrets template and add your Notion token:
```powershell
Copy-Item secrets.example.ps1 secrets.ps1
notepad secrets.ps1
```

3. Initialize the database:
```powershell
powershell -ExecutionPolicy Bypass -File db-init.ps1
```

4. Run the first index:
```powershell
powershell -ExecutionPolicy Bypass -File index-all.ps1
```

5. Launch Atlas:
```powershell
powershell -ExecutionPolicy Bypass -File atlas-ui.ps1
```

Or simply double-click `atlas.ahk` to start with the global hotkey.

---

## 🗂️ Project Structure

```
atlas/
├── atlas-ui.ps1          # WPF UI — main application window
├── atlas.ahk             # AutoHotkey — global hotkey (Ctrl+Alt+Space)
├── db-init.ps1           # SQLite database setup
├── index-all.ps1         # Runs all indexers
├── index-chrome.ps1      # Chrome history & bookmarks indexer
├── index-files.ps1       # File system indexer (incremental)
├── index-obsidian.ps1    # Obsidian vault indexer
├── index-notion.ps1      # Notion API indexer
├── index-recent.ps1      # Windows Recent Documents indexer
├── lib-search.ps1        # Search engine & query parser
├── lib-log.ps1           # Shared logging library
├── lib-incremental.ps1   # Incremental indexing logic
├── config.ps1            # Configuration (paths, settings)
├── secrets.example.ps1   # Token template (copy as secrets.ps1)
└── quickopen.ps1         # Fallback UI (no WPF)
```

---

## 🔧 How It Works

1. **Indexers** run in the background via Task Scheduler every 30 minutes
2. All results are stored in a local **SQLite database** at `%LOCALAPPDATA%\Atlas\index.db`
3. When you type in the search box, Atlas queries the database with a **200ms debounce timer**
4. Press `Enter` to open the selected result

---

## ⌨️ Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+Alt+Space` | Open / close Atlas |
| `↑` / `↓` | Navigate results |
| `Enter` | Open selected result |
| `Escape` | Close Atlas |

---

## 🔍 Type Filters

| Filter | Description |
|--------|-------------|
| `@files` | Search only files |
| `@chrome` | Search Chrome history & bookmarks |
| `@obsidian` | Search Obsidian notes |
| `@notion` | Search Notion pages |
| `@recent` | Search recent documents |

---

## 🛠️ Built With

- **PowerShell** — Core scripting and indexers
- **WPF / XAML** — UI framework
- **SQLite** — Local search index (via PSSQLite)
- **AutoHotkey** — Global hotkey
- **Notion REST API** — Notion integration
- **Catppuccin Mocha** — Color theme

---

## 📋 Known Limitations

- Notion indexer requires a valid Notion integration token in `secrets.ps1`
- Outlook indexer is disabled (Citrix COM access not supported)
- Group Policy may require `-ExecutionPolicy Bypass` flag

---

## 📚 School Project

This project was developed as part of my IT apprenticeship (Lernender Informatiker EFZ) at bossinfo.ch AG in Switzerland, covering:

- **M122** — Scripting & Automation
- **M431** — Project Management (IPERKA methodology)

---

## 👤 Author

**Abbas Ehsani**  
IT Apprentice @ bossinfo.ch AG  
Switzerland

---

## 📄 License

MIT License — feel free to use and adapt.
