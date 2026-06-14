<#
.SYNOPSIS
    Atlas - Indexes files from configured folders. Incremental by default.
.DESCRIPTION
    Two modes:
    - Incremental (default): only files modified since last run are re-indexed.
      Much faster on subsequent runs.
    - Full: scans everything. Use -Full or run after schema/config changes.
.PARAMETER Full
    Forces a full re-scan, ignoring the last-run timestamp.
.EXAMPLE
    .\index-files.ps1
    .\index-files.ps1 -Full
#>

param(
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config
$script:dbPath = $config.DatabasePath

. "$PSScriptRoot\lib-incremental.ps1"

if (-not (Test-Path $script:dbPath)) {
    Write-AtlasLog -Component 'index-files' -Level ERROR -Message "Database not found. Run .\db-init.ps1 first."
    exit 1
}

$indexerName = 'index-files'
$startTime = Get-Date
$now = [int][double]::Parse((Get-Date -UFormat %s))

# Decide: incremental or full?
$incremental = Test-IsIncremental -IndexerName $indexerName -ForceFull:$Full
$lastRunUnix = if ($incremental) { Get-LastRunTime -IndexerName $indexerName } else { 0 }
$lastRunDate = if ($lastRunUnix -gt 0) {
    [DateTimeOffset]::FromUnixTimeSeconds($lastRunUnix).LocalDateTime
} else {
    [DateTime]::MinValue
}

if ($incremental) {
    Write-AtlasLog -Component 'index-files' -Level INFO -Message "Incremental run - changes since $($lastRunDate.ToString('yyyy-MM-dd HH:mm:ss'))"
} else {
    Write-AtlasLog -Component 'index-files' -Level INFO -Message "Full run - scanning everything"
}

$extensions = $config.FileExtensions
$skipFolders = $config.FileSkipFolders
$indexed = 0
$skipped = 0
$errors = 0

# DELETE-then-INSERT (compatible with older SQLite)
$insertQuery = @"
DELETE FROM records WHERE id = @id;
INSERT INTO records (id, type, title, subtitle, searchable, timestamp, action_data, indexed_at)
VALUES (@id, 'file', @title, @subtitle, @searchable, @timestamp, @action, @now);
"@

# In incremental mode, also track which files we saw so we can detect deletions
# (only if doing a full run - in incremental we don't trust the file list to be complete)
$seenIds = @{}

foreach ($folder in $config.FileFolders) {
    if (-not (Test-Path $folder)) {
        Write-AtlasLog -Component 'index-files' -Level WARN -Message "Skipping (not found): $folder"
        continue
    }

    Write-AtlasLog -Component 'index-files' -Level INFO -Message "Scanning: $folder"

    try {
        $files = Get-ChildItem -Path $folder -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $ext = $_.Extension.ToLower()
                if ($extensions -notcontains $ext) { return $false }
                foreach ($skip in $skipFolders) {
                    if ($_.FullName -match "\\$skip\\") { return $false }
                }
                return $true
            }

        foreach ($file in $files) {
            $id = "file:$($file.FullName.ToLower())"

            if (-not $incremental) {
                # Full mode - track everything we saw for delete detection at the end
                $seenIds[$id] = $true
            }

            # Incremental: skip files unchanged since last run
            if ($incremental -and $file.LastWriteTime -le $lastRunDate) {
                $skipped++
                # Still bump indexed_at so the GC at the end doesn't delete this record
                Invoke-SqliteQuery -DataSource $script:dbPath `
                    -Query "UPDATE records SET indexed_at = @now WHERE id = @id" `
                    -SqlParameters @{ now = $now; id = $id }
                continue
            }

            try {
                $folderName = Split-Path $file.DirectoryName -Leaf
                $searchable = "$($file.BaseName) $folderName $($file.Extension)"
                $subtitle = "$($file.DirectoryName) - $($file.LastWriteTime.ToString('yyyy-MM-dd'))"

                $actionData = @{
                    kind = 'open-file'
                    path = $file.FullName
                } | ConvertTo-Json -Compress

                $timestamp = [int][double]::Parse((Get-Date $file.LastWriteTime -UFormat %s))

                Invoke-SqliteQuery -DataSource $script:dbPath -Query $insertQuery -SqlParameters @{
                    id         = $id
                    title      = $file.Name
                    subtitle   = $subtitle
                    searchable = $searchable
                    timestamp  = $timestamp
                    action     = $actionData
                    now        = $now
                }
                $indexed++
            }
            catch {
                $errors++
                Write-AtlasLog -Component 'index-files' -Level DEBUG -Message "Skipped $($file.FullName): $_" -NoConsole
            }
        }
    }
    catch {
        Write-AtlasLog -Component 'index-files' -Level ERROR -Message "Error scanning ${folder}: $_"
    }
}

# Garbage collection for deleted files
# Only safe in full-run mode. In incremental mode we can't tell whether a record
# is missing because the file was deleted, or because it just wasn't in scope this run.
if (-not $incremental) {
    $staleCount = (Invoke-SqliteQuery -DataSource $script:dbPath `
        -Query "SELECT COUNT(*) AS n FROM records WHERE type = 'file' AND indexed_at < @now" `
        -SqlParameters @{ now = $now }).n

    if ($staleCount -gt 0) {
        Invoke-SqliteQuery -DataSource $script:dbPath `
            -Query "DELETE FROM records WHERE type = 'file' AND indexed_at < @now" `
            -SqlParameters @{ now = $now }
        Write-AtlasLog -Component 'index-files' -Level INFO -Message "Removed $staleCount stale file entries"
    }
}

# Record this successful run
$durationMs = [int]((Get-Date) - $startTime).TotalMilliseconds
Set-LastRunTime -IndexerName $indexerName -ItemCount $indexed -DurationMs $durationMs

# Final report
$mode = if ($incremental) { 'incremental' } else { 'full' }
$summary = "Files [$mode]: $indexed processed"
if ($skipped -gt 0) { $summary += ", $skipped unchanged" }
if ($errors -gt 0) { $summary += ", $errors errors" }

if ($errors -gt 0) {
    Write-AtlasLog -Component 'index-files' -Level WARN -Message $summary
} else {
    Write-AtlasLog -Component 'index-files' -Level SUCCESS -Message $summary
}
