

$ErrorActionPreference = 'Stop'

if ($env:PSModulePath -notlike "*C:\PSModules*") {
    $env:PSModulePath = "C:\PSModules;" + $env:PSModulePath
}

Import-Module PSSQLite

. "$PSScriptRoot\lib-log.ps1"
. "$PSScriptRoot\config.ps1"
$config = $Config
$script:dbPath = $config.DatabasePath

. "$PSScriptRoot\lib-search.ps1"

if (-not (Test-Path $script:dbPath)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Atlas database not found.`nRun .\db-init.ps1 and .\index-all.ps1 first.") | Out-Null
    exit 1
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Atlas - Universal Search"
        Width="700" Height="500"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="False"
        Topmost="True">
    <Border Background="#FF1E1E2E" CornerRadius="10" BorderBrush="#FF45475A" BorderThickness="1">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="20,15,20,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="Atlas" FontSize="22" Foreground="#FFCBA6F7"
                           FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,15,0"/>
                <TextBox Grid.Column="1" x:Name="SearchBox"
                         FontSize="20" Padding="8"
                         Background="#FF313244" Foreground="#FFCDD6F4"
                         BorderBrush="#FF45475A" BorderThickness="1"
                         CaretBrush="#FFCDD6F4"/>
            </Grid>

            <ListView Grid.Row="1" x:Name="ResultsList"
                      Margin="20,5,20,10"
                      Background="Transparent"
                      BorderThickness="0"
                      Foreground="#FFCDD6F4">
                <ListView.ItemContainerStyle>
                    <Style TargetType="ListViewItem">
                        <Setter Property="Padding" Value="10,6"/>
                        <Setter Property="Background" Value="Transparent"/>
                        <Setter Property="Foreground" Value="#FFCDD6F4"/>
                        <Setter Property="BorderThickness" Value="0"/>
                        <Style.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#FF45475A"/>
                                <Setter Property="Foreground" Value="#FFF5C2E7"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#FF313244"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </ListView.ItemContainerStyle>
                <ListView.ItemTemplate>
                    <DataTemplate>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="50"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="{Binding Icon}"
                                       FontFamily="Consolas" FontWeight="Bold" FontSize="11"
                                       Foreground="#FF89B4FA"
                                       VerticalAlignment="Center"/>
                            <StackPanel Grid.Column="1">
                                <TextBlock Text="{Binding Title}" FontSize="14" FontWeight="SemiBold"
                                           TextTrimming="CharacterEllipsis"/>
                                <TextBlock Text="{Binding Subtitle}" FontSize="11"
                                           Foreground="#FF7F849C"
                                           TextTrimming="CharacterEllipsis"/>
                            </StackPanel>
                        </Grid>
                    </DataTemplate>
                </ListView.ItemTemplate>
            </ListView>

            <Border Grid.Row="2" Background="#FF181825" CornerRadius="0,0,10,10" Padding="20,8">
                <TextBlock x:Name="StatusBar"
                           Text="Tip: @file, @web, @bookmark, @recent, @obsidian, @notion, or paste a URL"
                           Foreground="#FF6C7086" FontSize="11"/>
            </Border>
        </Grid>
    </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$searchBox  = $window.FindName('SearchBox')
$resultsList = $window.FindName('ResultsList')
$statusBar  = $window.FindName('StatusBar')

$searchTimer = New-Object System.Windows.Threading.DispatcherTimer
$searchTimer.Interval = [TimeSpan]::FromMilliseconds(200)

$script:CurrentResults = @()

function Update-Results {
    $query = $searchBox.Text

    if (Test-AtlasIsUrl -Query $query) {
        $statusBar.Text = "Press Enter to open URL: $query"
        $resultsList.ItemsSource = $null
        return
    }

    $parsed = Parse-AtlasQuery -Query $query
    $results = Search-AtlasIndex -Query $parsed.CleanQuery `
                                  -TypeFilter $parsed.Type `
                                  -MaxResults $config.MaxResults `
                                  -Weights $config.Weights

    $script:CurrentResults = @($results)
    $resultsList.ItemsSource = $script:CurrentResults

    if ($script:CurrentResults.Count -gt 0) {
        $resultsList.SelectedIndex = 0
    }

    $count = $script:CurrentResults.Count
    if ([string]::IsNullOrWhiteSpace($query)) {
        $statusBar.Text = "Showing recent and frequently picked items - $count results"
    } elseif ($parsed.Type) {
        $statusBar.Text = "Filter: $($parsed.Type) - $count results"
    } else {
        $statusBar.Text = "$count results"
    }
}

$searchTimer.Add_Tick({
    $searchTimer.Stop()
    Update-Results
})

$searchBox.Add_TextChanged({
    $searchTimer.Stop()
    $searchTimer.Start()
})

function Open-Selected {
    $query = $searchBox.Text

    if (Test-AtlasIsUrl -Query $query) {
        Write-AtlasLog -Component 'ui' -Level INFO -Message "Direct URL open: $query"
        try {
            Start-Process $query
        }
        catch {
            Write-AtlasLog -Component 'ui' -Level ERROR -Message "URL open failed: $_"
        }
        $window.Close()
        return
    }

    $selected = $resultsList.SelectedItem
    if ($null -eq $selected) { return }


    try {
        Invoke-AtlasAction -Record $selected
    }
    catch {
        Write-AtlasLog -Component 'ui' -Level ERROR -Message "Action failed: $_"
        [System.Windows.MessageBox]::Show("Konnte Aktion nicht ausfuehren:`n$_") | Out-Null
    }

  
    $window.Close()
}

$window.Add_KeyDown({
    param($sender, $e)
    switch ($e.Key) {
        'Escape' {
            $window.Close()
            $e.Handled = $true
        }
        'Enter' {
            Open-Selected
            $e.Handled = $true
        }
        'Down' {
            if ($resultsList.Items.Count -gt 0) {
                $newIndex = [Math]::Min($resultsList.SelectedIndex + 1, $resultsList.Items.Count - 1)
                $resultsList.SelectedIndex = $newIndex
                $resultsList.ScrollIntoView($resultsList.SelectedItem)
                $e.Handled = $true
            }
        }
        'Up' {
            if ($resultsList.Items.Count -gt 0) {
                $newIndex = [Math]::Max($resultsList.SelectedIndex - 1, 0)
                $resultsList.SelectedIndex = $newIndex
                $resultsList.ScrollIntoView($resultsList.SelectedItem)
                $e.Handled = $true
            }
        }
    }
})

$resultsList.Add_MouseDoubleClick({
    Open-Selected
})


$window.Add_Loaded({
    Update-Results
    $searchBox.Focus() | Out-Null
})

$null = $window.ShowDialog()
