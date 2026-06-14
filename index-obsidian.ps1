

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config

$VaultPath = if ($config.ObsidianVault) {
    $config.ObsidianVault
} else {
    "Path to Obsidian"
}

$DbPath = $config.DatabasePath

Write-AtlasLog -Component "obsidian" -Level INFO -Message "Starting Obsidian indexer"
Write-AtlasLog -Component "obsidian" -Level INFO -Message "Vault: $VaultPath"

if (-not (Test-Path $VaultPath)) {
    Write-AtlasLog -Component "obsidian" -Level ERROR -Message "Vault not found: $VaultPath"
    exit 1
}


Invoke-SqliteQuery -DataSource $DbPath -Query "DELETE FROM records WHERE type = 'obsidian'" | Out-Null

$mdFiles = Get-ChildItem -Path $VaultPath -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue


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

      
        $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

      
        $relativePath = $file.FullName.Substring($VaultPath.Length).TrimStart('\')
        $folder = Split-Path $relativePath -Parent
        $subtitle = if ($folder) { "Obsidian / $folder" } else { "Obsidian" }

      
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

       
        $inlineTags = [regex]::Matches($content, '(?<![\w/])#([a-zA-Z][\w/-]*)') |
                      ForEach-Object { $_.Groups[1].Value } |
                      Select-Object -Unique

       
        $wikiLinks = [regex]::Matches($content, '\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]') |
                     ForEach-Object { $_.Groups[1].Value } |
                     Select-Object -Unique

       
        $plainContent = $content -replace '(?ms)^---.*?---\s*', ''
        $plainContent = $plainContent -replace '#+\s*', ''
        $plainContent = $plainContent -replace '\[\[([^\]|]+?)(?:\|([^\]]+))?\]\]', '$1$2'
        $plainContent = $plainContent -replace '\*\*?([^\*]+)\*\*?', '$1'
        $plainContent = $plainContent -replace '\s+', ' '
        $plainContent = $plainContent.Trim()
        if ($plainContent.Length -gt 200) {
            $plainContent = $plainContent.Substring(0, 200)
        }

     
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

$now = [int][double]::Parse((Get-Date -UFormat %s))
Invoke-SqliteQuery -DataSource $DbPath -Query @"
INSERT OR REPLACE INTO indexer_runs (indexer_name, last_run, item_count)
VALUES ('obsidian', @run, @count)
"@ -SqlParameters @{ run = $now; count = $count } | Out-Null

Write-AtlasLog -Component "obsidian" -Level INFO -Message "Indexed $count notes ($errors errors)"
