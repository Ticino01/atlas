
$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config
$dbPath = $config.DatabasePath

$dbFolder = Split-Path $dbPath -Parent
if (-not (Test-Path $dbFolder)) {
    New-Item -ItemType Directory -Path $dbFolder -Force | Out-Null
    Write-AtlasLog -Component 'db-init' -Level INFO -Message "Created folder: $dbFolder"
}

Write-AtlasLog -Component 'db-init' -Level INFO -Message "Initializing database at: $dbPath"

$schema = @"
-- Main records table - every indexer writes rows in this shape
CREATE TABLE IF NOT EXISTS records (
    id          TEXT PRIMARY KEY,
    type        TEXT NOT NULL,
    title       TEXT NOT NULL,
    subtitle    TEXT,
    searchable  TEXT NOT NULL,
    timestamp   INTEGER,
    action_data TEXT NOT NULL,
    indexed_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_records_type ON records(type);
CREATE INDEX IF NOT EXISTS idx_records_timestamp ON records(timestamp DESC);

-- Click tracking - learns which results you actually pick
CREATE TABLE IF NOT EXISTS picks (
    record_id TEXT NOT NULL,
    picked_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_picks_record ON picks(record_id);

-- Indexer runs - tracks last successful run per indexer for incremental indexing
CREATE TABLE IF NOT EXISTS indexer_runs (
    indexer_name TEXT PRIMARY KEY,
    last_run     INTEGER NOT NULL,
    item_count   INTEGER,
    duration_ms  INTEGER
);
"@

Invoke-SqliteQuery -DataSource $dbPath -Query $schema
Write-AtlasLog -Component 'db-init' -Level SUCCESS -Message "Database ready"
Write-Host ""
Write-Host "Next: run .\index-all.ps1 to populate the index."
