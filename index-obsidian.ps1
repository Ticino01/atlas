<#
.SYNOPSIS
    Atlas - Obsidian Indexer.

.DESCRIPTION
    Indexes all Markdown notes from an Obsidian vault into the Atlas
    database. Parses YAML frontmatter (tags, aliases), extracts inline
    tags (#tag) and Wiki-Links ([[Note]]) for richer search.

.NOTES
    Module: M431 - Auftraege im eigenen Berufsumfeld selbststaendig durchfuehren
    Autor:  Abbas Ehsani
    Datum:  Mai 2026
#>

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config

# Vault-Pfad: aus Config lesen, sonst Default
$VaultPath = if ($config.ObsidianVault) {
    $config.ObsidianVault
} else {
    "C:\Users\aehsani\OneDrive - bossinfo.ch AG\Dokumente\Obsidian\Abbas"
}

$DbPath = $config.DatabasePath

Write-AtlasLog -Component "obsidian" -Level INFO -Message "Starting Obsidian indexer"
Write-AtlasLog -Component "obsidian" -Level INFO -Message "Vault: $VaultPath"

if (-not (Test-Path $VaultPath)) {
    Write-AtlasLog -Component "obsidian" -Level ERROR -Message "Vault not found: $VaultPath"
    exit 1
}

# Bestehende Obsidian-Eintraege loeschen (Voll-Reindex)
Invoke-SqliteQuery -DataSource $DbPath -Query "DELETE FROM records WHERE type = 'obsidian'" | Out-Null

$mdFiles = Get-ChildItem -Path $VaultPath -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue

# .obsidian-Ordner und Trash ausschliessen
$mdFiles = $mdFiles | Where-Object {
    $_.FullName -notmatch '\\\.obsidian\\' -and
    $_.FullName -notmatch '\\\.trash\\'
}

Write-AtlasLog -Component "obsidian" -Level INFO -Message "Found $($mdFiles.Count) Markdown files"

$count = 0
$errors = 0

foreach ($file in $mdFiles) {
    try {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop

        # Titel ist der Dateiname ohne .md
        $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

        # Relativer Pfad als Subtitle (zeigt Ordner-Struktur)
        $relativePath = $file.FullName.Substring($VaultPath.Length).TrimStart('\')
        $folder = Split-Path $relativePath -Parent
        $subtitle = if ($folder) { "Obsidian / $folder" } else { "Obsidian" }

        # YAML-Frontmatter parsen (zwischen --- am Anfang)
        $frontmatterTags = @()
        $frontmatterAliases = @()

        if ($content -match '(?ms)^---\s*\r?\n(.*?)\r?\n---') {
            $frontmatter = $Matches[1]

            if ($frontmatter -match '(?m)^tags:\s*(.+)$') {
                $tagLine = $Matches[1]
                $frontmatterTags = $tagLine -split '[,\s\[\]]+' | Where-Object { $_ -and $_ -ne '-' }
            }

            if ($frontmatter -match '(?m)^aliases?:\s*(.+)$') {
                $aliasLine = $Matches[1]
                $frontmatterAliases = $aliasLine -split '[,\s\[\]]+' | Where-Object { $_ -and $_ -ne '-' }
            }
        }

        # Inline-Tags wie #tagname extrahieren
        $inlineTags = [regex]::Matches($content, '(?<![\w/])#([a-zA-Z][\w/-]*)') |
                      ForEach-Object { $_.Groups[1].Value } |
                      Select-Object -Unique

        # Wiki-Links wie [[Andere Notiz]] extrahieren
        $wikiLinks = [regex]::Matches($content, '\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]') |
                     ForEach-Object { $_.Groups[1].Value } |
                     Select-Object -Unique

        # Erste 200 Zeichen Plaintext fuer Vorschau
        $plainContent = $content -replace '(?ms)^---.*?---\s*', ''
        $plainContent = $plainContent -replace '#+\s*', ''
        $plainContent = $plainContent -replace '\[\[([^\]|]+?)(?:\|([^\]]+))?\]\]', '$1$2'
        $plainContent = $plainContent -replace '\*\*?([^\*]+)\*\*?', '$1'
        $plainContent = $plainContent -replace '\s+', ' '
        $plainContent = $plainContent.Trim()
        if ($plainContent.Length -gt 200) {
            $plainContent = $plainContent.Substring(0, 200)
        }

        # Searchable Text zusammenbauen: Titel + Aliases + Tags + Wiki-Links + Vorschau
        $searchableParts = @($title) + $frontmatterAliases + $frontmatterTags + $inlineTags + $wikiLinks + @($plainContent)
        $searchable = ($searchableParts -join ' ').ToLower()

        $timestamp = [int][double]::Parse((Get-Date -UFormat %s -Date $file.LastWriteTime))
        $indexedAt = [int][double]::Parse((Get-Date -UFormat %s))

        Invoke-SqliteQuery -DataSource $DbPath -Query @"
INSERT INTO records (type, title, subtitle, searchable, timestamp, action_data, indexed_at)
VALUES ('obsidian', @title, @subtitle, @searchable, @timestamp, @action, @indexed)
"@ -SqlParameters @{
            title      = $title
            subtitle   = $subtitle
            searchable = $searchable
            timestamp  = $timestamp
            action     = $file.FullName
            indexed    = $indexedAt
        } | Out-Null

        $count++
    }
    catch {
        $errors++
        Write-AtlasLog -Component "obsidian" -Level WARN -Message "Failed to index $($file.Name): $_"
    }
}

# indexer_runs aktualisieren
$now = [int][double]::Parse((Get-Date -UFormat %s))
Invoke-SqliteQuery -DataSource $DbPath -Query @"
INSERT OR REPLACE INTO indexer_runs (indexer_name, last_run, item_count)
VALUES ('obsidian', @run, @count)
"@ -SqlParameters @{ run = $now; count = $count } | Out-Null

Write-AtlasLog -Component "obsidian" -Level INFO -Message "Indexed $count notes ($errors errors)"
