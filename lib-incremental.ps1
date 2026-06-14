

function Get-LastRunTime {
    param([Parameter(Mandatory)][string]$IndexerName)

    $row = Invoke-SqliteQuery -DataSource $script:dbPath `
        -Query "SELECT last_run FROM indexer_runs WHERE indexer_name = @name" `
        -SqlParameters @{ name = $IndexerName }

    if ($row) { return [int]$row.last_run }
    return 0
}

function Set-LastRunTime {
    param(
        [Parameter(Mandatory)][string]$IndexerName,
        [int]$ItemCount = 0,
        [int]$DurationMs = 0
    )

    $now = [int][double]::Parse((Get-Date -UFormat %s))

   
    $sql = @"
DELETE FROM indexer_runs WHERE indexer_name = @name;
INSERT INTO indexer_runs (indexer_name, last_run, item_count, duration_ms)
VALUES (@name, @now, @count, @duration);
"@

    Invoke-SqliteQuery -DataSource $script:dbPath -Query $sql -SqlParameters @{
        name     = $IndexerName
        now      = $now
        count    = $ItemCount
        duration = $DurationMs
    }
}

function Test-IsIncremental {
   
    param(
        [Parameter(Mandatory)][string]$IndexerName,
        [int]$MaxAgeDays = 7,
        [switch]$ForceFull
    )

    if ($ForceFull) { return $false }

    $lastRun = Get-LastRunTime -IndexerName $IndexerName
    if ($lastRun -eq 0) { return $false }

    $now = [int][double]::Parse((Get-Date -UFormat %s))
    $ageSeconds = $now - $lastRun
    $maxAge = $MaxAgeDays * 86400

    if ($ageSeconds -gt $maxAge) { return $false }

    return $true
}
