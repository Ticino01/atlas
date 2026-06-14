<#
.SYNOPSIS
    Atlas - Runs all indexers in sequence.
.DESCRIPTION
    Schedule this in Task Scheduler.
    Indexer failures are isolated - one breaking won't stop the others.
    All output goes to both console and log file.
#>

$ErrorActionPreference = 'Continue'

. "$PSScriptRoot\lib-log.ps1"
& "$PSScriptRoot\index-obsidian.ps1"

$start = Get-Date
Write-AtlasLog -Component 'orchestrator' -Level INFO -Message "===== Indexing run started ====="

# Active indexers - add or remove as your data sources change
$indexers = @(
    'index-files.ps1'
    'index-chrome.ps1'
    'index-recent.ps1'
    # 'index-outlook.ps1'   # disabled - Outlook runs in Citrix on this machine
)

$totalErrors = 0

foreach ($indexer in $indexers) {
    $path = Join-Path $PSScriptRoot $indexer
    if (-not (Test-Path $path)) {
        Write-AtlasLog -Component 'orchestrator' -Level WARN -Message "Missing indexer: $indexer"
        continue
    }

    $indexerStart = Get-Date
    Write-AtlasLog -Component 'orchestrator' -Level INFO -Message "Starting: $indexer"

    try {
        & $path
        $duration = [int]((Get-Date) - $indexerStart).TotalSeconds
        Write-AtlasLog -Component 'orchestrator' -Level SUCCESS -Message "Finished: $indexer (${duration}s)"
    }
    catch {
        $totalErrors++
        Write-AtlasLog -Component 'orchestrator' -Level ERROR -Message "Failed: $indexer - $_"
    }
}

# Clean up old logs once per run
Clear-OldAtlasLogs -DaysToKeep 14

$elapsed = (Get-Date) - $start
$seconds = [int]$elapsed.TotalSeconds

if ($totalErrors -gt 0) {
    Write-AtlasLog -Component 'orchestrator' -Level WARN -Message "===== Done in ${seconds}s with $totalErrors error(s) ====="
}
else {
    Write-AtlasLog -Component 'orchestrator' -Level SUCCESS -Message "===== Done in ${seconds}s ====="
}
