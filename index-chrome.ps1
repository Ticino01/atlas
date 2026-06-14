<#
.SYNOPSIS
    Indexes Chrome browser history and bookmarks into Atlas.
#>

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config
$dbPath = $config.DatabasePath

if (-not (Test-Path $dbPath)) {
    Write-AtlasLog -Component 'index-chrome' -Level ERROR -Message "Database not found. Run .\db-init.ps1 first."
    exit 1
}

$now = [int][double]::Parse((Get-Date -UFormat %s))

$chromeUserData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
$historyFile    = Join-Path $chromeUserData "History"
$bookmarksFile  = Join-Path $chromeUserData "Bookmarks"
$tempHistory    = Join-Path $env:TEMP "Atlas_ChromeHistory.db"

# DELETE-then-INSERT pattern (works on older SQLite versions)
$insertQuery = @"
DELETE FROM records WHERE id = @id;
INSERT INTO records (id, type, title, subtitle, searchable, timestamp, action_data, indexed_at)
VALUES (@id, @type, @title, @subtitle, @searchable, @timestamp, @action, @now);
"@

function Save-Record {
    param($Id, $Type, $Title, $Subtitle, $Searchable, $Timestamp, $ActionData)

    Invoke-SqliteQuery -DataSource $dbPath -Query $insertQuery -SqlParameters @{
        id         = $Id
        type       = $Type
        title      = $Title
        subtitle   = $Subtitle
        searchable = $Searchable
        timestamp  = $Timestamp
        action     = $ActionData
        now        = $now
    }
}

function Convert-ChromeTime {
    param([long]$ChromeTime)
    if ($ChromeTime -le 0) { return 0 }
    return [int](($ChromeTime / 1000000) - 11644473600)
}

function Index-ChromeHistory {
    if (-not (Test-Path $historyFile)) {
        Write-AtlasLog -Component 'index-chrome' -Level WARN -Message "Chrome history not found - skipped"
        return 0
    }

    try {
        Copy-Item -Path $historyFile -Destination $tempHistory -Force
    }
    catch {
        Write-AtlasLog -Component 'index-chrome' -Level ERROR -Message "Could not copy history DB: $_"
        return 0
    }

    $count = 0
    $errors = 0

    try {
        $sql = @"
SELECT url, title, visit_count, last_visit_time
FROM urls
WHERE last_visit_time > 0
  AND title IS NOT NULL
  AND title != ''
ORDER BY visit_count DESC, last_visit_time DESC
LIMIT 2000;
"@
        $rows = Invoke-SqliteQuery -DataSource $tempHistory -Query $sql

        foreach ($row in $rows) {
            try {
                $url = $row.url
                $title = $row.title

                if ($url -like "chrome://*") { continue }
                if ($url -like "chrome-extension://*") { continue }
                if ($url -like "about:*") { continue }
                if ($title.Length -lt 2) { continue }

                $id = "chrome-history:$url"

                $domain = try { ([System.Uri]$url).Host } catch { '' }

                $visits = $row.visit_count
                $lastVisitUnix = Convert-ChromeTime -ChromeTime $row.last_visit_time
                $lastVisitDate = if ($lastVisitUnix -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($lastVisitUnix).LocalDateTime.ToString('yyyy-MM-dd')
                } else { 'unknown' }

                $subtitle = "$domain - $visits visits - last $lastVisitDate"
                $searchable = "$title $domain $url"

                $actionData = @{
                    kind = 'open-url'
                    url  = $url
                } | ConvertTo-Json -Compress

                Save-Record -Id $id -Type 'history' -Title $title -Subtitle $subtitle `
                    -Searchable $searchable -Timestamp $lastVisitUnix -ActionData $actionData

                $count++
            }
            catch {
                $errors++
                Write-AtlasLog -Component 'index-chrome' -Level DEBUG -Message "History row error: $_" -NoConsole
            }
        }
    }
    catch {
        Write-AtlasLog -Component 'index-chrome' -Level ERROR -Message "History indexing failed: $_"
        return 0
    }
    finally {
        Remove-Item $tempHistory -ErrorAction SilentlyContinue
    }

    if ($errors -gt 0) {
        Write-AtlasLog -Component 'index-chrome' -Level WARN -Message "History entries: $count (with $errors skipped)"
    }
    else {
        Write-AtlasLog -Component 'index-chrome' -Level SUCCESS -Message "History entries: $count"
    }
    return $count
}

function Walk-Bookmarks {
    param($Node, [string]$FolderPath)

    $results = @()
    if (-not $Node) { return $results }

    if ($Node.type -eq 'url') {
        $results += [PSCustomObject]@{
            Title  = $Node.name
            Url    = $Node.url
            Folder = $FolderPath
            Added  = $Node.date_added
        }
    }
    elseif ($Node.type -eq 'folder' -and $Node.children) {
        $newPath = if ($FolderPath) { "$FolderPath / $($Node.name)" } else { $Node.name }
        foreach ($child in $Node.children) {
            $results += Walk-Bookmarks -Node $child -FolderPath $newPath
        }
    }

    return $results
}

function Index-ChromeBookmarks {
    if (-not (Test-Path $bookmarksFile)) {
        Write-AtlasLog -Component 'index-chrome' -Level WARN -Message "Chrome bookmarks not found - skipped"
        return 0
    }

    $count = 0
    $errors = 0

    try {
        $json = Get-Content -Path $bookmarksFile -Raw -Encoding UTF8 | ConvertFrom-Json

        $roots = @($json.roots.bookmark_bar, $json.roots.other, $json.roots.synced)

        # Deduplicate by URL - bookmarks can appear in multiple roots (synced!)
        $seen = @{}

        foreach ($root in $roots) {
            if (-not $root) { continue }
            $bookmarks = Walk-Bookmarks -Node $root -FolderPath ''

            foreach ($bm in $bookmarks) {
                try {
                    if (-not $bm.Url) { continue }
                    if ($seen.ContainsKey($bm.Url)) { continue }
                    $seen[$bm.Url] = $true

                    $title = if ($bm.Title) { $bm.Title } else { $bm.Url }

                    $id = "chrome-bookmark:$($bm.Url)"
                    $domain = try { ([System.Uri]$bm.Url).Host } catch { '' }

                    $subtitle = if ($bm.Folder) {
                        "Bookmark in $($bm.Folder) - $domain"
                    } else {
                        "Bookmark - $domain"
                    }

                    $searchable = "$title $domain $($bm.Url) $($bm.Folder)"

                    $addedUnix = if ($bm.Added) {
                        Convert-ChromeTime -ChromeTime ([long]$bm.Added)
                    } else { $now }

                    $actionData = @{
                        kind = 'open-url'
                        url  = $bm.Url
                    } | ConvertTo-Json -Compress

                    Save-Record -Id $id -Type 'bookmark' -Title $title -Subtitle $subtitle `
                        -Searchable $searchable -Timestamp $addedUnix -ActionData $actionData

                    $count++
                }
                catch {
                    $errors++
                    Write-AtlasLog -Component 'index-chrome' -Level DEBUG -Message "Bookmark error: $_" -NoConsole
                }
            }
        }
    }
    catch {
        Write-AtlasLog -Component 'index-chrome' -Level ERROR -Message "Bookmarks indexing failed: $_"
        return 0
    }

    if ($errors -gt 0) {
        Write-AtlasLog -Component 'index-chrome' -Level WARN -Message "Bookmarks: $count (with $errors skipped)"
    }
    else {
        Write-AtlasLog -Component 'index-chrome' -Level SUCCESS -Message "Bookmarks: $count"
    }
    return $count
}

Write-AtlasLog -Component 'index-chrome' -Level INFO -Message "Starting Chrome indexing"

$historyCount  = Index-ChromeHistory
$bookmarkCount = Index-ChromeBookmarks

Write-AtlasLog -Component 'index-chrome' -Level SUCCESS -Message "Total: $historyCount history + $bookmarkCount bookmarks"
