<#
.SYNOPSIS
    Indexes Outlook emails, contacts, and calendar events.
#>

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite
. "$PSScriptRoot\config.ps1"
$config = $Config
$dbPath = $config.DatabasePath

if (-not (Test-Path $dbPath)) {
    Write-Error "Database not found. Run .\db-init.ps1 first."
    exit 1
}

$now = [int][double]::Parse((Get-Date -UFormat %s))
$daysBack = $config.EmailDaysBack
$maxItems = $config.EmailMaxItems
$cutoffDate = (Get-Date).AddDays(-$daysBack)

Write-Host "Connecting to Outlook..." -ForegroundColor Cyan

try {
    $outlook = New-Object -ComObject Outlook.Application
    $namespace = $outlook.GetNamespace("MAPI")
}
catch {
    Write-Error "Could not connect to Outlook. Is it installed and running?`n$_"
    exit 1
}

$olFolderInbox    = 6
$olFolderSentMail = 5
$olFolderContacts = 10
$olFolderCalendar = 9

function Save-Record {
    param($Id, $Type, $Title, $Subtitle, $Searchable, $Timestamp, $ActionData)

    $query = @"
INSERT INTO records (id, type, title, subtitle, searchable, timestamp, action_data, indexed_at)
VALUES (@id, @type, @title, @subtitle, @searchable, @timestamp, @action, @now)
ON CONFLICT(id) DO UPDATE SET
    title = excluded.title,
    subtitle = excluded.subtitle,
    searchable = excluded.searchable,
    timestamp = excluded.timestamp,
    action_data = excluded.action_data,
    indexed_at = excluded.indexed_at;
"@
    Invoke-SqliteQuery -DataSource $dbPath -Query $query -SqlParameters @{
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

function Index-EmailFolder {
    param($Folder, $Label)

    $count = 0
    Write-Host "  Indexing ${Label}..." -NoNewline

    try {
        $items = $Folder.Items
        $items.Sort("[ReceivedTime]", $true)

        $filterDate = $cutoffDate.ToString("g")
        $filtered = $items.Restrict("[ReceivedTime] >= '$filterDate'")

        foreach ($item in $filtered) {
            if ($count -ge $maxItems) { break }

            try {
                if ($item.Class -ne 43) { continue }

                $entryId = $item.EntryID
                $id = "email:$entryId"

                $subject = if ($item.Subject) { $item.Subject } else { '(no subject)' }
                $sender = if ($item.SenderName) { $item.SenderName } else { 'Unknown' }
                $date = $item.ReceivedTime

                $title = $subject
                $subtitle = "$Label - from $sender - $($date.ToString('yyyy-MM-dd HH:mm'))"
                $bodyPreview = if ($item.Body) { $item.Body.Substring(0, [Math]::Min(500, $item.Body.Length)) } else { '' }
                $searchable = "$subject $sender $bodyPreview"

                $actionData = @{
                    kind    = 'open-outlook'
                    entryId = $entryId
                } | ConvertTo-Json -Compress

                $timestamp = [int][double]::Parse((Get-Date $date -UFormat %s))

                Save-Record -Id $id -Type 'email' -Title $title -Subtitle $subtitle `
                    -Searchable $searchable -Timestamp $timestamp -ActionData $actionData

                $count++
            }
            catch {
                Write-Verbose "Email item error: $_"
            }
        }
    }
    catch {
        Write-Host " ERROR" -ForegroundColor Red
        Write-Host "    $_" -ForegroundColor Red
        return 0
    }

    Write-Host " $count" -ForegroundColor Green
    return $count
}

function Index-Contacts {
    Write-Host "  Indexing contacts..." -NoNewline
    $count = 0

    try {
        $folder = $namespace.GetDefaultFolder($olFolderContacts)
        foreach ($contact in $folder.Items) {
            try {
                if ($contact.Class -ne 40) { continue }

                $entryId = $contact.EntryID
                $id = "contact:$entryId"

                $name = $contact.FullName
                if (-not $name) { $name = $contact.CompanyName }
                if (-not $name) { continue }

                $email = $contact.Email1Address
                $company = $contact.CompanyName
                $phone = $contact.BusinessTelephoneNumber

                $title = $name
                $subtitleParts = @()
                if ($email)   { $subtitleParts += $email }
                if ($company) { $subtitleParts += $company }
                if ($phone)   { $subtitleParts += $phone }
                $subtitle = $subtitleParts -join ' - '

                $searchable = "$name $email $company"

                $actionData = @{
                    kind    = 'open-outlook'
                    entryId = $entryId
                } | ConvertTo-Json -Compress

                Save-Record -Id $id -Type 'contact' -Title $title -Subtitle $subtitle `
                    -Searchable $searchable -Timestamp $now -ActionData $actionData

                $count++
            }
            catch {
                Write-Verbose "Contact error: $_"
            }
        }
    }
    catch {
        Write-Host " ERROR" -ForegroundColor Red
        return 0
    }

    Write-Host " $count" -ForegroundColor Green
    return $count
}

function Index-Calendar {
    Write-Host "  Indexing calendar..." -NoNewline
    $count = 0

    try {
        $folder = $namespace.GetDefaultFolder($olFolderCalendar)
        $items = $folder.Items
        $items.IncludeRecurrences = $true
        $items.Sort("[Start]")

        $startDate = (Get-Date).AddDays(-30).ToString("g")
        $endDate   = (Get-Date).AddDays(90).ToString("g")
        $filtered = $items.Restrict("[Start] >= '$startDate' AND [Start] <= '$endDate'")

        foreach ($event in $filtered) {
            try {
                if ($event.Class -ne 26) { continue }

                $id = "event:$($event.EntryID):$($event.Start.Ticks)"

                $title = if ($event.Subject) { $event.Subject } else { '(untitled event)' }
                $when = $event.Start.ToString('yyyy-MM-dd HH:mm')
                $location = if ($event.Location) { " @ $($event.Location)" } else { '' }
                $subtitle = "$when$location"

                $searchable = "$title $($event.Location) $($event.Body)"

                $actionData = @{
                    kind    = 'open-outlook'
                    entryId = $event.EntryID
                } | ConvertTo-Json -Compress

                $timestamp = [int][double]::Parse((Get-Date $event.Start -UFormat %s))

                Save-Record -Id $id -Type 'event' -Title $title -Subtitle $subtitle `
                    -Searchable $searchable -Timestamp $timestamp -ActionData $actionData

                $count++
            }
            catch {
                Write-Verbose "Event error: $_"
            }
        }
    }
    catch {
        Write-Host " ERROR" -ForegroundColor Red
        return 0
    }

    Write-Host " $count" -ForegroundColor Green
    return $count
}

$inbox = $namespace.GetDefaultFolder($olFolderInbox)
$sent  = $namespace.GetDefaultFolder($olFolderSentMail)

$emailCount    = (Index-EmailFolder -Folder $inbox -Label 'Inbox') +
                 (Index-EmailFolder -Folder $sent  -Label 'Sent')
$contactCount  = Index-Contacts
$eventCount    = Index-Calendar

[System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null

Write-Host ""
Write-Host "Outlook indexed: $emailCount emails, $contactCount contacts, $eventCount events" -ForegroundColor Green
