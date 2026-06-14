
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
    Write-AtlasLog -Component 'index-recent' -Level ERROR -Message "Database not found. Run .\db-init.ps1 first."
    exit 1
}

$indexerName = 'index-recent'
$startTime = Get-Date
$now = [int][double]::Parse((Get-Date -UFormat %s))
$recentFolder = "$env:APPDATA\Microsoft\Windows\Recent"

if (-not (Test-Path $recentFolder)) {
    Write-AtlasLog -Component 'index-recent' -Level WARN -Message "Recent folder not found: $recentFolder"
    exit 0
}

$incremental = Test-IsIncremental -IndexerName $indexerName -ForceFull:$Full
$lastRunUnix = if ($incremental) { Get-LastRunTime -IndexerName $indexerName } else { 0 }
$lastRunDate = if ($lastRunUnix -gt 0) {
    [DateTimeOffset]::FromUnixTimeSeconds($lastRunUnix).LocalDateTime
} else {
    [DateTime]::MinValue
}

if ($incremental) {
    Write-AtlasLog -Component 'index-recent' -Level INFO -Message "Incremental run - changes since $($lastRunDate.ToString('yyyy-MM-dd HH:mm:ss'))"
} else {
    Write-AtlasLog -Component 'index-recent' -Level INFO -Message "Full run - processing all shortcuts"
}

$insertQuery = @"
DELETE FROM records WHERE id = @id;
INSERT INTO records (id, type, title, subtitle, searchable, timestamp, action_data, indexed_at)
VALUES (@id, 'recent', @title, @subtitle, @searchable, @timestamp, @action, @now);
"@


function Test-PathFast {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 1
    )

    if (-not $Path) { return $false }

    # Local path - instant
    if ($Path -notmatch '^\\\\') {
        return Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    }

    # Network path - use a job with timeout
    $job = Start-Job -ScriptBlock {
        param($p)
        Test-Path -LiteralPath $p -ErrorAction SilentlyContinue
    } -ArgumentList $Path

    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds

    if ($completed) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job -Force
        return [bool]$result
    } else {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return $false
    }
}

$shell = New-Object -ComObject WScript.Shell

$indexed = 0
$errors = 0
$skipped = 0
$unchanged = 0

$lnkFiles = Get-ChildItem -Path $recentFolder -Filter "*.lnk" -ErrorAction SilentlyContinue

Write-AtlasLog -Component 'index-recent' -Level INFO -Message "Found $($lnkFiles.Count) shortcuts to process"

foreach ($lnk in $lnkFiles) {
    try {
        # Incremental: skip .lnk files unchanged since last run
        # Windows updates a .lnk's LastWriteTime each time you open the target
        if ($incremental -and $lnk.LastWriteTime -le $lastRunDate) {
            $unchanged++
            continue
        }

        $shortcut = $shell.CreateShortcut($lnk.FullName)
        $targetPath = $shortcut.TargetPath

        if (-not $targetPath) {
            $skipped++
            continue
        }

        
        if (-not (Test-PathFast -Path $targetPath -TimeoutSeconds 1)) {
            $skipped++
            continue
        }

        # Skip folders - we want files only
        $item = Get-Item -LiteralPath $targetPath -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            $skipped++
            continue
        }

        $fileName = Split-Path $targetPath -Leaf
        $folderPath = Split-Path $targetPath -Parent
        $folderName = Split-Path $folderPath -Leaf

        $accessTime = $lnk.LastWriteTime
        $timestamp = [int][double]::Parse((Get-Date $accessTime -UFormat %s))

        $id = "recent:$($targetPath.ToLower())"
        $title = $fileName
        $subtitle = "Recently opened - $folderPath - $($accessTime.ToString('yyyy-MM-dd HH:mm'))"
        $searchable = "$fileName $folderName"

        $actionData = @{
            kind = 'open-file'
            path = $targetPath
        } | ConvertTo-Json -Compress

        Invoke-SqliteQuery -DataSource $script:dbPath -Query $insertQuery -SqlParameters @{
            id         = $id
            title      = $title
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
        Write-AtlasLog -Component 'index-recent' -Level DEBUG -Message "Error on $($lnk.Name): $_" -NoConsole
    }
}

[System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null


if (-not $incremental) {
    $staleCount = (Invoke-SqliteQuery -DataSource $script:dbPath `
        -Query "SELECT COUNT(*) AS n FROM records WHERE type = 'recent' AND indexed_at < @now" `
        -SqlParameters @{ now = $now }).n

    if ($staleCount -gt 0) {
        Invoke-SqliteQuery -DataSource $script:dbPath `
            -Query "DELETE FROM records WHERE type = 'recent' AND indexed_at < @now" `
            -SqlParameters @{ now = $now }
        Write-AtlasLog -Component 'index-recent' -Level INFO -Message "Removed $staleCount stale recent entries"
    }
}

$durationMs = [int]((Get-Date) - $startTime).TotalMilliseconds
Set-LastRunTime -IndexerName $indexerName -ItemCount $indexed -DurationMs $durationMs

$mode = if ($incremental) { 'incremental' } else { 'full' }
$summary = "Recent [$mode]: $indexed indexed"
if ($unchanged -gt 0) { $summary += ", $unchanged unchanged" }
if ($skipped -gt 0)   { $summary += ", $skipped skipped" }
if ($errors -gt 0)    { $summary += ", $errors errors" }

Write-AtlasLog -Component 'index-recent' -Level SUCCESS -Message $summary
