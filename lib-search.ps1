<#
.SYNOPSIS
    Atlas - Search logic library.
.DESCRIPTION
    Reusable search and ranking functions. Used by both the legacy
    quickopen.ps1 and the new WPF UI (atlas-ui.ps1).
    
    Dot-source this AFTER lib-log.ps1 and config.ps1.
    Requires $script:dbPath to be set by the caller.
#>

# Type-icon mapping
$script:TypeIcons = @{
    'file'     = 'FILE'
    'history'  = 'WEB '
    'bookmark' = 'MARK'
    'recent'   = 'RCNT'
    'email'    = 'MAIL'
    'contact'  = 'PERS'
    'event'    = 'CAL '
    'snippet'  = 'SNIP'
    'obsidian' = 'OBS'
    'notion'  =  'NOTION'
}

$script:TypeFilters = @{
    '@file'     = 'file'
    '@files'    = 'file'
    '@web'      = 'history'
    '@history'  = 'history'
    '@bookmark' = 'bookmark'
    '@marks'    = 'bookmark'
    '@recent'   = 'recent'
    '@obsidian' = 'obsidian'
    '@notion'   = 'notion'
}

function Get-AtlasTypeIcon {
    param([string]$Type)
    if ($script:TypeIcons.ContainsKey($Type)) {
        return $script:TypeIcons[$Type]
    }
    return '?   '
}

function Parse-AtlasQuery {
    <#
    .SYNOPSIS
        Splits a query into type filter and remaining text.
    .OUTPUTS
        @{ Type = 'file'|null ; CleanQuery = 'remaining text' }
    #>
    param([string]$Query)

    $trimmed = $Query.Trim()

    foreach ($prefix in $script:TypeFilters.Keys) {
        if ($trimmed -match "^$prefix(\s+(.*))?$") {
            return @{
                Type       = $script:TypeFilters[$prefix]
                CleanQuery = if ($matches[2]) { $matches[2].Trim() } else { '' }
            }
        }
    }

    return @{
        Type       = $null
        CleanQuery = $trimmed
    }
}

function Test-AtlasIsUrl {
    param([string]$Query)
    return ($Query -match '^https?://\S+$')
}

function Search-AtlasIndex {
    <#
    .SYNOPSIS
        Searches the index, returns ranked results.
    .PARAMETER Query
        Free-text search string.
    .PARAMETER TypeFilter
        Optional record type to restrict results.
    .PARAMETER MaxResults
        Maximum results to return.
    #>
    param(
        [string]$Query,
        [string]$TypeFilter,
        [int]$MaxResults = 30,
        [hashtable]$Weights = @{ TextMatch = 1.0; Recency = 0.5; Frequency = 0.3; ExactPrefix = 2.0 }
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
LIMIT $MaxResults;
"@
    }

    try {
        $rows = if ($params.Count -gt 0) {
            Invoke-SqliteQuery -DataSource $script:dbPath -Query $sql -SqlParameters $params
        } else {
            Invoke-SqliteQuery -DataSource $script:dbPath -Query $sql
        }
    }
    catch {
        Write-AtlasLog -Component 'search' -Level ERROR -Message "Query failed: $_"
        return @()
    }

    if (-not $rows) { return @() }

    # Re-rank
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

        $total = ($Weights.TextMatch   * $textScore) +
                 ($Weights.Recency     * $recencyScore) +
                 ($Weights.Frequency   * $freqScore) +
                 ($Weights.ExactPrefix * $prefixBonus)

        [PSCustomObject]@{
            Id         = $row.id
            Type       = $row.type
            Icon       = Get-AtlasTypeIcon -Type $row.type
            Title      = $row.title
            Subtitle   = $row.subtitle
            ActionData = $row.action_data
            Score      = $total
        }
    }

    return $scored | Sort-Object Score -Descending | Select-Object -First $MaxResults
}

function Invoke-AtlasAction {
    <#
    .SYNOPSIS
        Executes the action for a chosen record (open file, URL, etc.)
        and records the pick for frequency learning.
    #>
    param($Record)

    $action = $Record.ActionData | ConvertFrom-Json

    Write-AtlasLog -Component 'search' -Level INFO -Message "Opening: $($Record.Type) - $($Record.Title)"

    switch ($action.kind) {
        'open-file' {
            if (Test-Path $action.path) {
                Start-Process $action.path
            } else {
                [System.Windows.MessageBox]::Show("File not found:`n$($action.path)") | Out-Null
            }
        }
        'open-url' {
            try { Start-Process $action.url }
            catch { [System.Windows.MessageBox]::Show("Could not open URL:`n$($action.url)") | Out-Null }
        }
        'open-outlook' {
            try {
                $outlook = New-Object -ComObject Outlook.Application
                $namespace = $outlook.GetNamespace("MAPI")
                $item = $namespace.GetItemFromID($action.entryId)
                $item.Display()
            }
            catch {
                [System.Windows.MessageBox]::Show("Could not open Outlook item:`n$_") | Out-Null
            }
        }
        default {
            Write-AtlasLog -Component 'search' -Level WARN -Message "Unknown action kind: $($action.kind)"
        }
    }

    # Record the pick
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    Invoke-SqliteQuery -DataSource $script:dbPath `
        -Query "INSERT INTO picks (record_id, picked_at) VALUES (@id, @t)" `
        -SqlParameters @{ id = $Record.Id; t = $now }
}
