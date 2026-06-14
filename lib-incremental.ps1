<#
.SYNOPSIS
    Atlas - Helpers for incremental indexing.
.DESCRIPTION
    Tracks last-run timestamps per indexer in the indexer_runs table.
    Dot-source this in any indexer:
        . "$PSScriptRoot\lib-incremental.ps1"
    
    Usage pattern:
        $lastRun = Get-LastRunTime -IndexerName 'index-files'
        # ... do work, only processing items newer than $lastRun ...
        Set-LastRunTime -IndexerName 'index-files' -ItemCount $count -DurationMs $ms
#>

# This script assumes lib-log.ps1 and config.ps1 are already dot-sourced
# by the calling indexer. We don't load them here to avoid double-loading.

function Get-LastRunTime {
    <#
    .SYNOPSIS
        Returns the unix timestamp of the last successful run for an indexer.
    .OUTPUTS
        Integer unix timestamp, or 0 if the indexer has never run.
    #>
    param([Parameter(Mandatory)][string]$IndexerName)

    $row = Invoke-SqliteQuery -DataSource $script:dbPath `
        -Query "SELECT last_run FROM indexer_runs WHERE indexer_name = @name" `
        -SqlParameters @{ name = $IndexerName }

    if ($row) { return [int]$row.last_run }
    return 0
}

function Set-LastRunTime {
    <#
    .SYNOPSIS
        Records that an indexer just finished a successful run.
    #>
    param(
        [Parameter(Mandatory)][string]$IndexerName,
        [int]$ItemCount = 0,
        [int]$DurationMs = 0
    )

    $now = [int][double]::Parse((Get-Date -UFormat %s))

    # DELETE-then-INSERT (compatible with older SQLite, no UPSERT)
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
    <#
    .SYNOPSIS
        Determines if an indexer should run incrementally.
    .DESCRIPTION
        Returns $false (= full run needed) if:
        - The indexer has never run before
        - It hasn't run for more than $MaxAgeDays days
        - The user passed -Full to force a full re-index
        Otherwise returns $true.
    #>
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
