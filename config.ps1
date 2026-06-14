


$Config = @{
  
    DatabasePath = "$env:LOCALAPPDATA\PATH TO Database"


    FileFolders = @(
        [Environment]::GetFolderPath('MyDocuments')
        [Environment]::GetFolderPath('Desktop')
        "$env:USERPROFILE\Downloads"
       
    )

 
    FileExtensions = @(
        '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt'
        '.pdf', '.txt', '.md', '.rtf'
        '.png', '.jpg', '.jpeg'
        '.ps1', '.py', '.js', '.html', '.css', '.json', '.yaml', '.yml'
        '.csv', '.zip'
    )

   
    FileSkipFolders = @('node_modules', '.git', 'bin', 'obj', '__pycache__', '.venv')

   
    EmailDaysBack = 90


    EmailMaxItems = 5000

    
    Weights = @{
        TextMatch    = 1.0
        Recency      = 0.5
        Frequency    = 0.3
        ExactPrefix  = 2.0
    }

 
    MaxResults = 30
}
