

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config
$dbPath = $config.DatabasePath
$weights = $config.Weights

if (-not (Test-Path $dbPath)) {
    Write-AtlasLog -Component 'search' -Level ERROR -Message "Database not found - run db-init and index-all first"
    [System.Windows.Forms.MessageBox]::Show("Atlas database not found. Run .\db-init.ps1 and .\index-all.ps1 first.") | Out-Null
    exit 1
}


$TypeIcons = @{
    'file'     = 'FILE'
    'history'  = 'WEB '
    'bookmark' = 'MARK'
    'recent'   = 'RCNT'
    'email'    = 'MAIL'
    'contact'  = 'PERS'
    'event'    = 'CAL '
}


$TypeFilters = @{
    '@file'     = 'file'
    '@files'    = 'file'
    '@web'      = 'history'
    '@history'  = 'history'
    '@bookmark' = 'bookmark'
    '@marks'    = 'bookmark'
    '@recent'   = 'recent'
}


function Parse-Query {
    param([string]$Query)

    $trimmed = $Query.Trim()

    foreach ($prefix in $TypeFilters.Keys) {
        if ($trimmed -match "^$prefix(\s+(.*))?$") {
            return @{
                Type       = $TypeFilters[$prefix]
                CleanQuery = if ($matches[2]) { $matches[2].Trim() } else { '' }
            }
        }
    }

    return @{
        Type       = $null
        CleanQuery = $trimmed
    }
}


function Test-IsUrl {
    param([string]$Query)
    return ($Query -match '^https?://\S+$')
}


function Search-Index {
    param(
        [string]$Query,
        [string]$TypeFilter
    )

    $now = [int][double]::Parse((Get-Date -UFormat %s))

    $whereClauses = @()
    $params = @{}

 
    if ($TypeFilter) {
        $whereClauses += "r.type = @typeFilter"
        $params['typeFilter'] = $TypeFilter
    }

  
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $words = $Query -split '\s+' | Where-Object { $_ }
        $i = 0
        foreach ($w in $words) {
            $key = "w$i"
            $params[$key] = "%$w%"
            $whereClauses += "(LOWER(r.title) LIKE LOWER(@$key) OR LOWER(r.subtitle) LIKE LOWER(@$key) OR LOWER(r.searchable) LIKE LOWER(@$key))"
            $i++
        }
    }

    if ($whereClauses.Count -gt 0) {
        $whereSql = $whereClauses -join ' AND '
        $sql = @"
SELECT r.id, r.type, r.title, r.subtitle, r.timestamp, r.action_data,
       (SELECT COUNT(*) FROM picks p WHERE p.record_id = r.id) AS pick_count
FROM records r
WHERE $whereSql
LIMIT 200;
"@
    }
    else {
        $sql = @"
SELECT r.id, r.type, r.title, r.subtitle, r.timestamp, r.action_data,
       (SELECT COUNT(*) FROM picks p WHERE p.record_id = r.id) AS pick_count
FROM records r
ORDER BY pick_count DESC, r.timestamp DESC
LIMIT $($config.MaxResults);
"@
    }

    try {
        $rows = if ($params.Count -gt 0) {
            Invoke-SqliteQuery -DataSource $dbPath -Query $sql -SqlParameters $params
        } else {
            Invoke-SqliteQuery -DataSource $dbPath -Query $sql
        }
    }
    catch {
        Write-AtlasLog -Component 'search' -Level ERROR -Message "Query failed: $_"
        return @()
    }

    if (-not $rows) { return @() }

  
    $queryLower = $Query.ToLower()
    $words = $queryLower -split '\s+' | Where-Object { $_ }

    $scored = foreach ($row in $rows) {
        $titleLower = $row.title.ToLower()

      
        $titleHits = 0
        foreach ($w in $words) {
            if ($titleLower.Contains($w)) { $titleHits++ }
        }
        $textScore = if ($words.Count -gt 0) { $titleHits / [double]$words.Count } else { 0.5 }

     
        $ageDays = if ($row.timestamp) {
            ($now - $row.timestamp) / 86400.0
        } else { 365 }
        $recencyScore = [Math]::Exp(-$ageDays / 30.0)

     
        $freqScore = [Math]::Log(1 + $row.pick_count)

    
        $prefixBonus = if ($queryLower -and $titleLower.StartsWith($queryLower)) { 1.0 } else { 0.0 }

        $total = ($weights.TextMatch   * $textScore) +
                 ($weights.Recency     * $recencyScore) +
                 ($weights.Frequency   * $freqScore) +
                 ($weights.ExactPrefix * $prefixBonus)

        [PSCustomObject]@{
            Id         = $row.id
            Type       = $row.type
            Title      = $row.title
            Subtitle   = $row.subtitle
            ActionData = $row.action_data
            Score      = $total
        }
    }

    return $scored | Sort-Object Score -Descending | Select-Object -First $config.MaxResults
}


function Invoke-Action {
    param($Record)

    $action = $Record.ActionData | ConvertFrom-Json

    Write-AtlasLog -Component 'search' -Level INFO -Message "Opening: $($Record.Type) - $($Record.Title)"

    switch ($action.kind) {
        'open-file' {
            if (Test-Path $action.path) {
                Start-Process $action.path
            } else {
                [System.Windows.Forms.MessageBox]::Show("File not found:`n$($action.path)") | Out-Null
            }
        }
        'open-url' {
            try {
                Start-Process $action.url
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Could not open URL:`n$($action.url)") | Out-Null
            }
        }
        'open-outlook' {
            try {
                $outlook = New-Object -ComObject Outlook.Application
                $namespace = $outlook.GetNamespace("MAPI")
                $item = $namespace.GetItemFromID($action.entryId)
                $item.Display()
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Could not open Outlook item:`n$_") | Out-Null
            }
        }
        default {
            Write-AtlasLog -Component 'search' -Level WARN -Message "Unknown action kind: $($action.kind)"
        }
    }

  
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    Invoke-SqliteQuery -DataSource $dbPath `
        -Query "INSERT INTO picks (record_id, picked_at) VALUES (@id, @t)" `
        -SqlParameters @{ id = $Record.Id; t = $now }
}


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

$promptText = @"
Search files, browser history, bookmarks, recent docs.

Tips:
  @file <text>      - only files
  @web <text>       - only browser history
  @bookmark <text>  - only bookmarks
  @recent <text>    - only recent documents
  https://...       - open URL directly
"@

$query = [Microsoft.VisualBasic.Interaction]::InputBox(
    $promptText,
    "Atlas",
    ""
)

if ($null -eq $query -or [string]::IsNullOrWhiteSpace($query)) {
    exit 0
}


if (Test-IsUrl -Query $query) {
    Write-AtlasLog -Component 'search' -Level INFO -Message "Direct URL open: $query"
    Start-Process $query
    exit 0
}

$parsed = Parse-Query -Query $query
$typeFilter = $parsed.Type
$cleanQuery = $parsed.CleanQuery

if ($typeFilter) {
    Write-AtlasLog -Component 'search' -Level INFO -Message "Filter=$typeFilter Query='$cleanQuery'"
}

$results = Search-Index -Query $cleanQuery -TypeFilter $typeFilter

if (-not $results -or $results.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("No results for: $query") | Out-Null
    exit 0
}

$display = $results | ForEach-Object {
    $icon = if ($TypeIcons.ContainsKey($_.Type)) { $TypeIcons[$_.Type] } else { '???' }

    [PSCustomObject]@{
        '#'      = $icon
        Title    = $_.Title
        Where    = $_.Subtitle
        _Record  = $_
    }
}

$pickerTitle = if ($typeFilter) {
    "Atlas - $typeFilter results for '$cleanQuery'"
} else {
    "Atlas - results for '$query'"
}

$picked = $display |
    Out-GridView -Title $pickerTitle -OutputMode Single

if ($picked) {
    Invoke-Action -Record $picked._Record
}
