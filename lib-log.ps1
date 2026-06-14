
$script:LogFolder = "$env:LOCALAPPDATA\Atlas\logs"
$script:LogFile = Join-Path $script:LogFolder ("atlas_" + (Get-Date -Format "yyyy-MM-dd") + ".log")

if (-not (Test-Path $script:LogFolder)) {
    New-Item -ItemType Directory -Path $script:LogFolder -Force | Out-Null
}

function Write-AtlasLog {
  
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

 
    try {
        Add-Content -Path $script:LogFile -Value $logLine -Encoding UTF8
    }
    catch {
       
    }

  
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
    
    param([int]$DaysToKeep = 14)

    $cutoff = (Get-Date).AddDays(-$DaysToKeep)
    Get-ChildItem -Path $script:LogFolder -Filter "atlas_*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
