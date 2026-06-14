<#
.SYNOPSIS
    Atlas - Central logging library.
.DESCRIPTION
    Provides Write-AtlasLog function used by all other scripts.
    Writes to both the console (with colors) and a rolling log file.
    Dot-source this file at the top of any Atlas script:
        . "$PSScriptRoot\lib-log.ps1"
#>

# Where logs go - same folder as the database
$script:LogFolder = "$env:LOCALAPPDATA\Atlas\logs"
$script:LogFile = Join-Path $script:LogFolder ("atlas_" + (Get-Date -Format "yyyy-MM-dd") + ".log")

if (-not (Test-Path $script:LogFolder)) {
    New-Item -ItemType Directory -Path $script:LogFolder -Force | Out-Null
}

function Write-AtlasLog {
    <#
    .SYNOPSIS
        Logs a message to console and file.
    .PARAMETER Message
        The text to log.
    .PARAMETER Level
        INFO (default), WARN, ERROR, DEBUG, SUCCESS
    .PARAMETER Component
        Which component is logging (e.g. 'index-files', 'search')
    .PARAMETER NoConsole
        If set, only writes to file (no console output).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level = 'INFO',

        [string]$Component = 'atlas',

        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] [$Component] $Message"

    # Always write to file
    try {
        Add-Content -Path $script:LogFile -Value $logLine -Encoding UTF8
    }
    catch {
        # If we can't write to log file, don't crash the caller
    }

    # Optionally write to console with color
    if (-not $NoConsole) {
        $color = switch ($Level) {
            'ERROR'   { 'Red' }
            'WARN'    { 'Yellow' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Gray' }
            default   { 'White' }
        }
        Write-Host $logLine -ForegroundColor $color
    }
}

function Get-AtlasLogFile {
    return $script:LogFile
}

function Clear-OldAtlasLogs {
    <#
    .SYNOPSIS
        Deletes log files older than N days. Call from scheduled tasks.
    #>
    param([int]$DaysToKeep = 14)

    $cutoff = (Get-Date).AddDays(-$DaysToKeep)
    Get-ChildItem -Path $script:LogFolder -Filter "atlas_*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
