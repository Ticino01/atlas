# Atlas configuration
# Loaded via dot-sourcing - all variables become available afterwards.

$Config = @{
    # Where the SQLite database lives
    DatabasePath = "$env:LOCALAPPDATA\Atlas\index.db"

    # Folders to index for files.
    # Using GetFolderPath() so OneDrive redirection is handled automatically -
    # it returns the actual current path whether the folder is local or in OneDrive.
    FileFolders = @(
        [Environment]::GetFolderPath('MyDocuments')
        [Environment]::GetFolderPath('Desktop')
        "$env:USERPROFILE\Downloads"
        # Add specific OneDrive subfolders here if you want them indexed
        # Example: "$env:OneDriveCommercial\Projekte"
    )

    # File extensions to index
    FileExtensions = @(
        '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt'
        '.pdf', '.txt', '.md', '.rtf'
        '.png', '.jpg', '.jpeg'
        '.ps1', '.py', '.js', '.html', '.css', '.json', '.yaml', '.yml'
        '.csv', '.zip'
    )

    # Skip these folder names anywhere in path
    FileSkipFolders = @('node_modules', '.git', 'bin', 'obj', '__pycache__', '.venv')

    # How many days back to index Outlook emails
    EmailDaysBack = 90

    # Safety cap per Outlook folder
    EmailMaxItems = 5000

    # Ranking weights
    Weights = @{
        TextMatch    = 1.0
        Recency      = 0.5
        Frequency    = 0.3
        ExactPrefix  = 2.0
    }

    # Number of results in the picker
    MaxResults = 30
}
