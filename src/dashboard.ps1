#Requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$Script:ScriptDir        = $PSScriptRoot
$Script:ToolsFile        = Join-Path $Script:ScriptDir "tools.json"
$Script:UsageFile        = Join-Path $Script:ScriptDir "usage.json"
$Script:CurrentMode      = "recent"
$Script:IgnoreModeChange = $false

# ---------------------------------------------------------------------------
# Datenzugriff
# ---------------------------------------------------------------------------

function Load-Tools {
    if (-not (Test-Path $Script:ToolsFile)) { return , @() }
    try {
        $json = Get-Content $Script:ToolsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.tools) { return , $json.tools } else { return , @() }
    } catch {
        [System.Windows.MessageBox]::Show(
            "tools.json konnte nicht geladen werden.`n`nHinweis: Windows-Pfade muessen in JSON doppelte Backslashes verwenden (C:\\Pfad\\Datei).`n`nFehler: $_",
            "Konfigurationsfehler",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return , @()
    }
}

function Save-Tools {
    param([System.Collections.ArrayList]$Tools)
    $obj  = [ordered]@{ tools = @($Tools) }
    $json = $obj | ConvertTo-Json -Depth 5
    $json | Set-Content -Path $Script:ToolsFile -Encoding UTF8
}

function Load-Usage {
    if (-not (Test-Path $Script:UsageFile)) { return @{} }
    try {
        $json = Get-Content $Script:UsageFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $ht   = @{}
        if ($json.lastUsed) {
            $json.lastUsed.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        }
        return $ht
    } catch { return @{} }
}

function Save-Usage {
    param([hashtable]$Usage)
    [ordered]@{ lastUsed = $Usage } | ConvertTo-Json -Depth 3 |
        Set-Content -Path $Script:UsageFile -Encoding UTF8
}

function Update-LastUsed {
    param([string]$ToolId)
    $usage           = Load-Usage
    $usage[$ToolId]  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    Save-Usage $usage
}

function Get-RecentTools {
    $usage  = Load-Usage
    $tools  = Load-Tools
    $result = [System.Collections.ArrayList]@()
    $usage.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            $id = $_.Name
            $t  = $tools | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if ($t) { $result.Add($t) | Out-Null }
        }
    return , $result
}

function Filter-Tools {
    param([string]$Query)
    $loaded = Load-Tools
    $all    = @($loaded | Sort-Object name)
    if ([string]::IsNullOrWhiteSpace($Query)) { return , $all }
    $q = $Query.ToLower()
    return , @($all | Where-Object {
        ($_.name        -and $_.name.ToLower().Contains($q))        -or
        ($_.doc         -and $_.doc.ToLower().Contains($q))         -or
        ($_.description -and $_.description.ToLower().Contains($q)) -or
        ($_.tags        -and ($_.tags | Where-Object { $_ -and $_.ToLower().Contains($q) }))
    })
}

# ---------------------------------------------------------------------------
# Haupt-XAML
# ---------------------------------------------------------------------------

[xml]$MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JC Dashboard" Height="720" Width="1200"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI">

    <Window.Resources>

        <Style x:Key="ModeItem" TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="#7C9AB8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="bd" Background="Transparent" CornerRadius="6" Margin="8,2">
                            <ContentPresenter Margin="16,10" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#162A3A"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1A3347"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ToolItem" TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="#C8D8E8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="bd" Background="Transparent"
                                BorderBrush="#1E3A52" BorderThickness="0,0,0,1">
                            <ContentPresenter Margin="14,10"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1E3A52"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1E4A6E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="StartButton" TargetType="Button">
            <Setter Property="Background" Value="#1E6DB5"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="28,12"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="7">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#2A80D0"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#155A9A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="200"/>
            <ColumnDefinition Width="300"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- COL 1: Modus-Auswahl -->
        <DockPanel Grid.Column="0" Background="#0D1F2D">
            <Border DockPanel.Dock="Top" Padding="20,18,20,14"
                    BorderBrush="#1A3347" BorderThickness="0,0,0,1">
                <StackPanel>
                    <TextBlock Text="JC Dashboard" Foreground="White"
                               FontSize="17" FontWeight="SemiBold"/>
                    <TextBlock Text="Tool-Steuerzentrale" Foreground="#4A6A85"
                               FontSize="11" Margin="0,3,0,0"/>
                </StackPanel>
            </Border>
            <ListBox x:Name="modeList" Background="Transparent"
                     BorderThickness="0" Margin="0,10,0,0">
                <ListBoxItem Style="{StaticResource ModeItem}" Tag="recent"
                             Content="Zuletzt verwendet"/>
                <ListBoxItem Style="{StaticResource ModeItem}" Tag="all"
                             Content="Alle Tools (A-Z)"/>
                <ListBoxItem Style="{StaticResource ModeItem}" Tag="settings"
                             Content="&#9881;  Einstellungen"/>
            </ListBox>
        </DockPanel>

        <!-- COL 2: Tool-Liste -->
        <Grid Grid.Column="1" Background="#152A3D">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Titelzeile (Modus "recent") -->
            <Border Grid.Row="0" x:Name="col2Header"
                    Padding="16,12" BorderBrush="#1E3A52" BorderThickness="0,0,0,1">
                <TextBlock x:Name="col2Title" Text="ZULETZT VERWENDET"
                           Foreground="#7C9AB8" FontSize="11" FontWeight="SemiBold"/>
            </Border>

            <!-- Suchfeld (Modus "all") -->
            <Border Grid.Row="0" x:Name="searchBorder" Visibility="Collapsed"
                    Background="#0F2030" Padding="12,9"
                    BorderBrush="#1E3A52" BorderThickness="0,0,0,1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="&#128269;" FontSize="12"
                               Foreground="#4A6A85" VerticalAlignment="Center"
                               Margin="0,0,8,0"/>
                    <TextBox Grid.Column="1" x:Name="txtSearch"
                             Background="Transparent" BorderThickness="0"
                             Foreground="#C8D8E8" FontSize="13"
                             CaretBrush="White" VerticalAlignment="Center"/>
                </Grid>
            </Border>

            <ListBox Grid.Row="1" x:Name="toolList"
                     Background="Transparent" BorderThickness="0"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
        </Grid>

        <!-- COL 3: Detail-Pane -->
        <Grid Grid.Column="2" Background="#F0F4F8">

            <!-- Welcome -->
            <StackPanel x:Name="welcomePanel"
                        HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock Text="&#128075;" FontSize="52"
                           HorizontalAlignment="Center"/>
                <TextBlock Text="Willkommen im JC Dashboard"
                           FontSize="22" FontWeight="SemiBold"
                           Foreground="#1A3347" HorizontalAlignment="Center"
                           Margin="0,14,0,6"/>
                <TextBlock Text="W&#228;hle links ein Tool aus."
                           Foreground="#607D8B" FontSize="14"
                           HorizontalAlignment="Center"/>
            </StackPanel>

            <!-- Details -->
            <ScrollViewer x:Name="detailScroll" Visibility="Collapsed"
                          VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">
                <StackPanel Margin="32,28,32,32">

                    <TextBlock x:Name="detailTitle"
                               FontSize="26" FontWeight="Bold"
                               Foreground="#0F2030" TextWrapping="Wrap"/>

                    <WrapPanel x:Name="detailMeta" Margin="0,10,0,14"/>

                    <WrapPanel x:Name="detailTags" Margin="0,0,0,16"/>

                    <Separator Background="#CBD5E1" Margin="0,0,0,16"/>

                    <RichTextBox x:Name="docViewer"
                                 IsReadOnly="True" BorderThickness="0"
                                 Background="Transparent"
                                 IsDocumentEnabled="True"
                                 Padding="0" FontSize="13"
                                 Foreground="#2D3748"
                                 Visibility="Collapsed"/>

                    <WrapPanel x:Name="imageGallery"
                               Margin="0,12,0,0" Visibility="Collapsed"/>

                    <Separator Background="#CBD5E1" Margin="0,24,0,20"/>

                    <Button x:Name="btnStartTool"
                            Style="{StaticResource StartButton}"
                            HorizontalAlignment="Left"
                            Content="Starten"/>

                </StackPanel>
            </ScrollViewer>

        </Grid>
    </Grid>
</Window>
'@

$reader                  = New-Object System.Xml.XmlNodeReader($MainXaml)
$Script:window           = [System.Windows.Markup.XamlReader]::Load($reader)

$Script:modeList         = $Script:window.FindName("modeList")
$Script:toolList         = $Script:window.FindName("toolList")
$Script:txtSearch        = $Script:window.FindName("txtSearch")
$Script:searchBorder     = $Script:window.FindName("searchBorder")
$Script:col2Header       = $Script:window.FindName("col2Header")
$Script:col2Title        = $Script:window.FindName("col2Title")
$Script:welcomePanel     = $Script:window.FindName("welcomePanel")
$Script:detailScroll     = $Script:window.FindName("detailScroll")
$Script:detailTitle      = $Script:window.FindName("detailTitle")
$Script:detailMeta       = $Script:window.FindName("detailMeta")
$Script:detailTags       = $Script:window.FindName("detailTags")
$Script:docViewer        = $Script:window.FindName("docViewer")
$Script:imageGallery     = $Script:window.FindName("imageGallery")
$Script:btnStartTool     = $Script:window.FindName("btnStartTool")

# ---------------------------------------------------------------------------
# Markdown -> FlowDocument
# ---------------------------------------------------------------------------

function Add-InlineContent {
    param($Paragraph, [string]$Text)
    $remaining = $Text
    while ($remaining.Length -gt 0) {
        if ($remaining -match '^(.*?)\*\*(.+?)\*\*(.*)$') {
            $before = $Matches[1]; $boldTxt = $Matches[2]; $after = $Matches[3]
            if ($before) {
                $Paragraph.Inlines.Add(
                    (New-Object System.Windows.Documents.Run($before))) | Out-Null
            }
            $b = New-Object System.Windows.Documents.Bold
            $b.Inlines.Add((New-Object System.Windows.Documents.Run($boldTxt))) | Out-Null
            $Paragraph.Inlines.Add($b) | Out-Null
            $remaining = $after
        } elseif ($remaining -match '^(.*?)\[(.+?)\]\((.+?)\)(.*)$') {
            $before = $Matches[1]; $lTxt = $Matches[2]
            $lUrl  = $Matches[3]; $after = $Matches[4]
            if ($before) {
                $Paragraph.Inlines.Add(
                    (New-Object System.Windows.Documents.Run($before))) | Out-Null
            }
            $lnk = New-Object System.Windows.Documents.Hyperlink
            $lnk.Inlines.Add((New-Object System.Windows.Documents.Run($lTxt))) | Out-Null
            try {
                $lnk.NavigateUri = New-Object System.Uri($lUrl)
                $lnk.Add_RequestNavigate({
                    Start-Process $args[1].Uri.AbsoluteUri
                    $args[1].Handled = $true
                })
            } catch {}
            $Paragraph.Inlines.Add($lnk) | Out-Null
            $remaining = $after
        } else {
            $Paragraph.Inlines.Add(
                (New-Object System.Windows.Documents.Run($remaining))) | Out-Null
            $remaining = ""
        }
    }
}

function Convert-MarkdownToFlowDocument {
    param([string]$Text)

    $doc            = New-Object System.Windows.Documents.FlowDocument
    $doc.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $doc.FontSize   = 13
    $doc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D3748")

    $listItems = [System.Collections.ArrayList]@()

    $flushList = {
        if ($listItems.Count -eq 0) { return }
        $lst = New-Object System.Windows.Documents.List
        $lst.MarkerStyle = [System.Windows.TextMarkerStyle]::Disc
        $lst.Margin      = New-Object System.Windows.Thickness(0, 4, 0, 4)
        foreach ($itemTxt in $listItems) {
            $li = New-Object System.Windows.Documents.ListItem
            $p  = New-Object System.Windows.Documents.Paragraph
            $p.Margin = New-Object System.Windows.Thickness(0)
            Add-InlineContent -Paragraph $p -Text $itemTxt
            $li.Blocks.Add($p) | Out-Null
            $lst.ListItems.Add($li) | Out-Null
        }
        $doc.Blocks.Add($lst) | Out-Null
        $listItems.Clear()
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^# (.+)$') {
            & $flushList
            $p = New-Object System.Windows.Documents.Paragraph
            $p.Margin = New-Object System.Windows.Thickness(0, 14, 0, 4)
            $r = New-Object System.Windows.Documents.Run($Matches[1])
            $r.FontSize   = 20
            $r.FontWeight = [System.Windows.FontWeights]::SemiBold
            $r.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F2030")
            $p.Inlines.Add($r) | Out-Null
            $doc.Blocks.Add($p) | Out-Null
        } elseif ($line -match '^## (.+)$') {
            & $flushList
            $p = New-Object System.Windows.Documents.Paragraph
            $p.Margin = New-Object System.Windows.Thickness(0, 10, 0, 3)
            $r = New-Object System.Windows.Documents.Run($Matches[1])
            $r.FontSize   = 15
            $r.FontWeight = [System.Windows.FontWeights]::SemiBold
            $r.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1A3347")
            $p.Inlines.Add($r) | Out-Null
            $doc.Blocks.Add($p) | Out-Null
        } elseif ($line -match '^[-\*] (.+)$') {
            $listItems.Add($Matches[1]) | Out-Null
        } elseif ($line.Trim() -eq '') {
            & $flushList
        } else {
            & $flushList
            $p = New-Object System.Windows.Documents.Paragraph
            $p.Margin = New-Object System.Windows.Thickness(0, 2, 0, 2)
            Add-InlineContent -Paragraph $p -Text $line
            $doc.Blocks.Add($p) | Out-Null
        }
    }
    & $flushList
    return $doc
}

# ---------------------------------------------------------------------------
# Hilfsfunktionen UI
# ---------------------------------------------------------------------------

function New-MetaChip {
    param([string]$Text, [string]$BgHex)
    $conv   = [System.Windows.Media.BrushConverter]::new()
    $border = New-Object System.Windows.Controls.Border
    $border.Background    = $conv.ConvertFromString($BgHex)
    $border.CornerRadius  = New-Object System.Windows.CornerRadius(4)
    $border.Padding       = New-Object System.Windows.Thickness(8, 3, 8, 3)
    $border.Margin        = New-Object System.Windows.Thickness(0, 0, 8, 4)
    $tb                   = New-Object System.Windows.Controls.TextBlock
    $tb.Text              = $Text
    $tb.Foreground        = [System.Windows.Media.Brushes]::White
    $tb.FontSize          = 11
    $border.Child         = $tb
    return $border
}

function New-TagChip {
    param([string]$Text)
    $border = New-Object System.Windows.Controls.Border
    $border.Background   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DDE4EE")
    $border.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $border.Padding      = New-Object System.Windows.Thickness(10, 4, 10, 4)
    $border.Margin       = New-Object System.Windows.Thickness(0, 0, 6, 6)
    $tb                  = New-Object System.Windows.Controls.TextBlock
    $tb.Text             = $Text
    $tb.Foreground       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569")
    $tb.FontSize         = 12
    $border.Child        = $tb
    return $border
}

function Add-ToolListItem {
    param($Tool)
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Style = $Script:window.FindResource("ToolItem")
    $item.Tag   = $Tool

    $sp = New-Object System.Windows.Controls.StackPanel

    $nameBlock              = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text         = "$($Tool.icon)  $($Tool.name)"
    $nameBlock.FontSize     = 13
    $nameBlock.FontWeight   = "SemiBold"
    $nameBlock.Foreground   = "#E2EAF2"
    $nameBlock.TextTrimming = "CharacterEllipsis"

    $typeLabel = switch ($Tool.type) {
        "web"   { "Webanwendung"   }
        "hta"   { "HTA-Anwendung"  }
        default { "PowerShell"     }
    }
    $typeBlock           = New-Object System.Windows.Controls.TextBlock
    $typeBlock.Text      = $typeLabel
    $typeBlock.FontSize  = 11
    $typeBlock.Foreground = "#4A6A85"
    $typeBlock.Margin    = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $sp.Children.Add($nameBlock) | Out-Null
    $sp.Children.Add($typeBlock) | Out-Null
    $item.Content = $sp
    $Script:toolList.Items.Add($item) | Out-Null
}

function Add-EmptyStateItem {
    param([string]$Text)
    $item            = New-Object System.Windows.Controls.ListBoxItem
    $item.IsEnabled  = $false
    $tb              = New-Object System.Windows.Controls.TextBlock
    $tb.Text         = $Text
    $tb.Foreground   = "#4A6A85"
    $tb.FontStyle    = "Italic"
    $tb.TextWrapping = "Wrap"
    $tb.Margin       = New-Object System.Windows.Thickness(14, 16, 14, 0)
    $item.Content    = $tb
    $Script:toolList.Items.Add($item) | Out-Null
}

function Show-WelcomePane {
    $Script:welcomePanel.Visibility = "Visible"
    $Script:detailScroll.Visibility = "Collapsed"
}

# ---------------------------------------------------------------------------
# Tool-Liste aufbauen (Col 2)
# ---------------------------------------------------------------------------

function Build-ToolList {
    param([string]$Mode)
    $Script:CurrentMode = $Mode
    $Script:toolList.Items.Clear()
    Show-WelcomePane

    if ($Mode -eq "recent") {
        $Script:col2Header.Visibility  = "Visible"
        $Script:searchBorder.Visibility = "Collapsed"
        $Script:col2Title.Text          = "ZULETZT VERWENDET"
        $tools = Get-RecentTools
        if ($tools.Count -eq 0) {
            Add-EmptyStateItem "Noch kein Tool gestartet."
        } else {
            foreach ($t in $tools) { Add-ToolListItem $t }
        }
    } else {
        $Script:col2Header.Visibility   = "Collapsed"
        $Script:searchBorder.Visibility = "Visible"
        $Script:txtSearch.Text          = ""
        $loaded = Load-Tools
        $tools  = @($loaded | Sort-Object name)
        if ($tools.Count -eq 0) {
            Add-EmptyStateItem "Keine Tools konfiguriert."
        } else {
            foreach ($t in $tools) { Add-ToolListItem $t }
        }
    }
}

# ---------------------------------------------------------------------------
# Detail-Pane befuellen (Col 3)
# ---------------------------------------------------------------------------

function Show-ToolDetails {
    param($Tool)
    $Script:welcomePanel.Visibility = "Collapsed"
    $Script:detailScroll.Visibility = "Visible"

    $Script:detailTitle.Text = "$($Tool.icon)  $($Tool.name)"

    # Meta-Chips
    $Script:detailMeta.Children.Clear()
    $catText = switch ($Tool.type) {
        "web"   { "Webanwendung"  }
        "hta"   { "HTA-Anwendung" }
        default { "PowerShell"    }
    }
    $Script:detailMeta.Children.Add((New-MetaChip -Text $catText -BgHex "#1E6DB5")) | Out-Null

    $versionDisplay = ""
    if ($Tool.version -and $Tool.version -ne "") {
        $versionDisplay = "v$($Tool.version)"
    }
    $dateDisplay = ""
    if ($Tool.versionDate -and $Tool.versionDate -ne "") {
        try {
            $dateDisplay = ([datetime]::Parse($Tool.versionDate)).ToString("dd.MM.yyyy")
        } catch { $dateDisplay = $Tool.versionDate }
    } elseif ($Tool.type -ne "web") {
        $p = if ([System.IO.Path]::IsPathRooted($Tool.path)) {
            $Tool.path } else { Join-Path $Script:ScriptDir $Tool.path }
        if ($p -and (Test-Path $p)) {
            $dateDisplay = (Get-Item $p).LastWriteTime.ToString("dd.MM.yyyy")
        }
    }
    $metaStr = @($versionDisplay, $dateDisplay) | Where-Object { $_ -ne "" }
    if ($metaStr.Count -gt 0) {
        $Script:detailMeta.Children.Add(
            (New-MetaChip -Text ($metaStr -join "  |  ") -BgHex "#475569")) | Out-Null
    }

    # Tags
    $Script:detailTags.Children.Clear()
    if ($Tool.tags) {
        foreach ($tag in $Tool.tags) {
            if (-not [string]::IsNullOrWhiteSpace($tag)) {
                $Script:detailTags.Children.Add((New-TagChip -Text $tag.Trim())) | Out-Null
            }
        }
    }

    # Dokument
    $docText = if ($Tool.doc -and $Tool.doc -ne "") { $Tool.doc } `
               elseif ($Tool.description -and $Tool.description -ne "") { $Tool.description } `
               else { "" }
    if ($docText) {
        $Script:docViewer.Document   = Convert-MarkdownToFlowDocument -Text $docText
        $Script:docViewer.Visibility = "Visible"
    } else {
        $Script:docViewer.Visibility = "Collapsed"
    }

    # Bilder-Galerie
    $Script:imageGallery.Children.Clear()
    if ($Tool.images -and $Tool.images.Count -gt 0) {
        foreach ($imgPath in $Tool.images) {
            $full   = if ([System.IO.Path]::IsPathRooted($imgPath)) { $imgPath } `
                      else { Join-Path $Script:ScriptDir $imgPath }
            $border = New-Object System.Windows.Controls.Border
            $border.Margin          = New-Object System.Windows.Thickness(0, 0, 12, 12)
            $border.BorderThickness = New-Object System.Windows.Thickness(1)
            $border.BorderBrush     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
            $border.CornerRadius    = New-Object System.Windows.CornerRadius(4)
            if (Test-Path $full) {
                try {
                    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bmp.BeginInit()
                    $bmp.UriSource = New-Object System.Uri($full)
                    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                    $bmp.EndInit()
                    $img            = New-Object System.Windows.Controls.Image
                    $img.Source     = $bmp
                    $img.MaxWidth   = 360
                    $img.MaxHeight  = 260
                    $img.Stretch    = "Uniform"
                    $border.Child   = $img
                } catch {
                    $tb = New-Object System.Windows.Controls.TextBlock
                    $tb.Text = "[Bild konnte nicht geladen werden]"
                    $tb.Foreground = "#94A3B8"
                    $tb.Margin = New-Object System.Windows.Thickness(10, 6, 10, 6)
                    $border.Child = $tb
                }
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = "[Nicht gefunden: $imgPath]"
                $tb.Foreground = "#94A3B8"
                $tb.Margin = New-Object System.Windows.Thickness(10, 6, 10, 6)
                $border.Child = $tb
            }
            $Script:imageGallery.Children.Add($border) | Out-Null
        }
        $Script:imageGallery.Visibility = "Visible"
    } else {
        $Script:imageGallery.Visibility = "Collapsed"
    }

    $Script:btnStartTool.Tag = $Tool
}

# ---------------------------------------------------------------------------
# Tool starten
# ---------------------------------------------------------------------------

function Start-Tool {
    param($Tool)
    try {
        if ($Tool.type -eq "web") {
            Start-Process $Tool.url
            Update-LastUsed -ToolId $Tool.id
            if ($Script:CurrentMode -eq "recent") { Build-ToolList -Mode "recent" }
            return
        }
        $path = if ([System.IO.Path]::IsPathRooted($Tool.path)) {
            $Tool.path } else { Join-Path $Script:ScriptDir $Tool.path }
        if (Test-Path $path) {
            Start-Process $path
            Update-LastUsed -ToolId $Tool.id
            if ($Script:CurrentMode -eq "recent") { Build-ToolList -Mode "recent" }
        } else {
            [System.Windows.MessageBox]::Show(
                "Datei nicht gefunden:`n$path", "Fehler",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
    } catch {
        [System.Windows.MessageBox]::Show(
            "Fehler beim Starten von '$($Tool.name)':`n$_", "Fehler",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Einstellungen-Dialog
# ---------------------------------------------------------------------------

function Get-DefaultTools {
    return @(
        [PSCustomObject]@{
            id          = "beispiel_web"
            name        = "Beispiel Webanwendung"
            type        = "web"
            icon        = "WEB"
            description = "Eine Beispiel-Webseite"
            url         = "https://www.example.com"
            tags        = @("Info", "Demo")
            version     = "1.0.0"
            versionDate = "2026-01-15"
            doc         = "# Beispiel Webanwendung`n`nDies ist ein **Beispiel-Eintrag** fuer ein Web-Tool.`n`n## Funktionen`n- Oeffnet eine Webseite im Standard-Browser`n- Demonstriert Tags, Version und Markdown-Doku`n`nMehr Infos unter [example.com](https://www.example.com)."
            images      = @()
        },
        [PSCustomObject]@{
            id          = "beispiel_ps"
            name        = "Beispiel PowerShell-Skript"
            type        = "powershell"
            icon        = "PS"
            description = "Ein Beispiel PowerShell-Skript"
            path        = "C:\\Beispiel\\Skript.ps1"
            tags        = @("Fun", "Demo")
            version     = "0.2"
            versionDate = "2026-03-22"
            doc         = "# Beispiel PowerShell-Skript`n`nStartet ein lokales **.ps1**-Skript via Start-Process.`n`n## Hinweise`n- Pfad in den Einstellungen anpassen`n- Backslashes muessen in JSON doppelt sein (C:\\Pfad\\Datei.ps1)"
            images      = @()
        },
        [PSCustomObject]@{
            id          = "beispiel_hta"
            name        = "Beispiel HTA-Anwendung"
            type        = "hta"
            icon        = "HTA"
            description = "Eine Beispiel HTML-Application"
            path        = "C:\\Beispiel\\Anwendung.hta"
            tags        = @("OPEN/Prosoz", "Info")
            version     = "2.1"
            versionDate = "2026-05-10"
            doc         = "# Beispiel HTA-Anwendung`n`nHTA-Dateien werden ueber **mshta.exe** geoeffnet.`n`n## Details`n- Wird in eigenem Fenster ausgefuehrt`n- Ideal fuer Legacy-Tools mit HTML+VBScript`n- Kategorie wird in der Detail-Ansicht als **HTA-Anwendung** angezeigt"
            images      = @()
        }
    )
}

function Show-SettingsDialog {

    [xml]$SXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Einstellungen &#8211; Tools verwalten"
        Height="720" Width="860"
        WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI"
        Background="#F8FAFC">

    <Window.Resources>
        <Style x:Key="Btn" TargetType="Button">
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="Lbl" TargetType="TextBlock">
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="#475569"/>
            <Setter Property="Margin" Value="0,10,0,3"/>
        </Style>
        <Style x:Key="Txt" TargetType="TextBox">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Background" Value="White"/>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="210"/>
            <ColumnDefinition Width="16"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Linke Spalte: Tool-Liste -->
        <Grid Grid.Column="0" Grid.Row="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="Tools" FontWeight="SemiBold"
                       FontSize="14" Foreground="#1A3347" Margin="0,0,0,8"/>
            <ListBox Grid.Row="1" x:Name="lstTools" FontSize="13"
                     BorderBrush="#CBD5E1" BorderThickness="1"/>
            <StackPanel Grid.Row="2" Margin="0,8,0,0">
                <StackPanel Orientation="Horizontal">
                    <Button x:Name="btnNew" Content="+ Neu" Style="{StaticResource Btn}"
                            Background="#1E6DB5" Width="95"/>
                    <Button x:Name="btnDelete" Content="L&#246;schen" Style="{StaticResource Btn}"
                            Background="#EF4444" Width="95" Margin="8,0,0,0"/>
                </StackPanel>
                <Button x:Name="btnReset" Content="Werkseinstellungen"
                        Style="{StaticResource Btn}"
                        Background="#94A3B8" HorizontalAlignment="Stretch" Margin="0,6,0,0"/>
            </StackPanel>
        </Grid>

        <!-- Rechte Spalte: Formular -->
        <ScrollViewer Grid.Column="2" Grid.Row="0" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <TextBlock Text="Tool bearbeiten" FontWeight="SemiBold"
                           FontSize="14" Foreground="#1A3347"/>

                <TextBlock Style="{StaticResource Lbl}" Text="Name"/>
                <TextBox x:Name="txtName" Style="{StaticResource Txt}"/>

                <TextBlock Style="{StaticResource Lbl}" Text="Typ"/>
                <ComboBox x:Name="cmbType" FontSize="13" Padding="8,6"
                          BorderBrush="#CBD5E1">
                    <ComboBoxItem Content="powershell"/>
                    <ComboBoxItem Content="hta"/>
                    <ComboBoxItem Content="web"/>
                </ComboBox>

                <TextBlock x:Name="lblPath" Style="{StaticResource Lbl}"
                           Text="Pfad zur .ps1"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox Grid.Column="0" x:Name="txtPath" Style="{StaticResource Txt}"/>
                    <Button Grid.Column="1" x:Name="btnBrowse" Content="..."
                            Style="{StaticResource Btn}" Background="#64748B"
                            Margin="6,0,0,0" Padding="10,6"/>
                </Grid>

                <TextBlock Style="{StaticResource Lbl}" Text="Icon (Emoji)"/>
                <TextBox x:Name="txtIcon" Style="{StaticResource Txt}" MaxLength="4"/>

                <TextBlock Style="{StaticResource Lbl}" Text="Tags (Komma-getrennt)"/>
                <TextBox x:Name="txtTags" Style="{StaticResource Txt}"/>

                <Grid Margin="0,10,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="16"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <TextBlock Style="{StaticResource Lbl}" Text="Version" Margin="0,0,0,3"/>
                        <TextBox x:Name="txtVersion" Style="{StaticResource Txt}"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2">
                        <TextBlock Style="{StaticResource Lbl}" Text="Versionsdatum" Margin="0,0,0,3"/>
                        <DatePicker x:Name="dpVersionDate" FontSize="13"
                                    SelectedDateFormat="Short"/>
                    </StackPanel>
                </Grid>

                <TextBlock Style="{StaticResource Lbl}" Text="Dokumentation (Markdown)"/>
                <TextBox x:Name="txtDoc" Style="{StaticResource Txt}"
                         Height="160" AcceptsReturn="True" TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         FontFamily="Consolas" FontSize="12"/>

                <TextBlock Style="{StaticResource Lbl}" Text="Bilder (Pfade)"/>
                <ListBox x:Name="lstImages" Height="80" FontSize="12"
                         BorderBrush="#CBD5E1" BorderThickness="1"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                    <Button x:Name="btnAddImage" Content="Hinzuf&#252;gen..."
                            Style="{StaticResource Btn}" Background="#1E6DB5"
                            Padding="10,5"/>
                    <Button x:Name="btnRemoveImage" Content="Entfernen"
                            Style="{StaticResource Btn}" Background="#EF4444"
                            Margin="8,0,0,0" Padding="10,5"/>
                </StackPanel>

                <TextBlock Style="{StaticResource Lbl}" Text="Beschreibung (kurz, optional)"/>
                <TextBox x:Name="txtDesc" Style="{StaticResource Txt}"
                         Height="50" AcceptsReturn="True" TextWrapping="Wrap"/>

                <Button x:Name="btnSave" Content="&#128190;  Speichern"
                        Style="{StaticResource Btn}" Background="#16A34A"
                        HorizontalAlignment="Left" Margin="0,16,0,0"
                        FontSize="14" Padding="18,9"/>
            </StackPanel>
        </ScrollViewer>

        <!-- Schliessen -->
        <StackPanel Grid.Column="0" Grid.ColumnSpan="3" Grid.Row="1"
                    HorizontalAlignment="Right" Orientation="Horizontal" Margin="0,12,0,0">
            <Button x:Name="btnClose" Content="Schlie&#223;en"
                    Style="{StaticResource Btn}" Background="#64748B" Padding="20,9"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $sr      = New-Object System.Xml.XmlNodeReader($SXaml)
    $sWin    = [System.Windows.Markup.XamlReader]::Load($sr)
    $sWin.Owner = $Script:window

    $sLst       = $sWin.FindName("lstTools")
    $sBtnNew    = $sWin.FindName("btnNew")
    $sBtnDel    = $sWin.FindName("btnDelete")
    $sBtnRst    = $sWin.FindName("btnReset")
    $sBtnSav    = $sWin.FindName("btnSave")
    $sBtnCls    = $sWin.FindName("btnClose")
    $sTxtNam    = $sWin.FindName("txtName")
    $sCmbTyp    = $sWin.FindName("cmbType")
    $sLblPath   = $sWin.FindName("lblPath")
    $sTxtPth    = $sWin.FindName("txtPath")
    $sBtnBrw    = $sWin.FindName("btnBrowse")
    $sTxtIco    = $sWin.FindName("txtIcon")
    $sTxtTags   = $sWin.FindName("txtTags")
    $sTxtVer    = $sWin.FindName("txtVersion")
    $sDpDate    = $sWin.FindName("dpVersionDate")
    $sTxtDoc    = $sWin.FindName("txtDoc")
    $sLstImg    = $sWin.FindName("lstImages")
    $sBtnAddImg = $sWin.FindName("btnAddImage")
    $sBtnRmImg  = $sWin.FindName("btnRemoveImage")
    $sTxtDsc    = $sWin.FindName("txtDesc")

    $Script:dlgTools  = [System.Collections.ArrayList]@()
    foreach ($t in (Load-Tools)) { $Script:dlgTools.Add($t) | Out-Null }
    $Script:dlgSelIdx = -1

    function S-RefreshList {
        $sLst.Items.Clear()
        foreach ($t in $Script:dlgTools) {
            $sLst.Items.Add("$($t.icon)  $($t.name)") | Out-Null
        }
    }

    function S-UpdatePathLabel {
        $sLblPath.Text = switch ($sCmbTyp.SelectedIndex) {
            1       { "Pfad zur .hta" }
            2       { "URL"           }
            default { "Pfad zur .ps1" }
        }
        $sBtnBrw.Visibility = if ($sCmbTyp.SelectedIndex -eq 2) { "Collapsed" } else { "Visible" }
    }

    function S-ClearForm {
        $sTxtNam.Text          = ""
        $sTxtPth.Text          = ""
        $sTxtIco.Text          = ""
        $sTxtTags.Text         = ""
        $sTxtVer.Text          = ""
        $sDpDate.SelectedDate  = $null
        $sTxtDoc.Text          = ""
        $sTxtDsc.Text          = ""
        $sLstImg.Items.Clear()
        $sCmbTyp.SelectedIndex = 0
        S-UpdatePathLabel
        $Script:dlgSelIdx      = -1
        $sLst.SelectedIndex    = -1
    }

    function S-LoadForm {
        param($t)
        $sTxtNam.Text = $t.name
        $sTxtIco.Text = $t.icon
        $sTxtDsc.Text = $t.description
        $sTxtTags.Text = if ($t.tags) { $t.tags -join ", " } else { "" }
        $sTxtVer.Text  = if ($t.version) { $t.version } else { "" }
        $sTxtDoc.Text  = if ($t.doc)     { $t.doc     } else { "" }
        if ($t.versionDate -and $t.versionDate -ne "") {
            try { $sDpDate.SelectedDate = [datetime]::Parse($t.versionDate) } catch { $sDpDate.SelectedDate = $null }
        } else { $sDpDate.SelectedDate = $null }
        $sLstImg.Items.Clear()
        if ($t.images) { foreach ($img in $t.images) { $sLstImg.Items.Add($img) | Out-Null } }
        $sCmbTyp.SelectedIndex = switch ($t.type) { "hta" { 1 } "web" { 2 } default { 0 } }
        S-UpdatePathLabel
        $sTxtPth.Text = if ($t.type -eq "web") { $t.url } else { $t.path }
    }

    $sCmbTyp.Add_SelectionChanged({ S-UpdatePathLabel })

    $sLst.Add_SelectionChanged({
        $i = $sLst.SelectedIndex
        if ($i -ge 0 -and $i -lt $Script:dlgTools.Count) {
            $Script:dlgSelIdx = $i
            S-LoadForm $Script:dlgTools[$i]
        }
    })

    $sBtnNew.Add_Click({ S-ClearForm })

    $sBtnBrw.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = switch ($sCmbTyp.SelectedIndex) {
            1       { "HTA-Dateien (*.hta)|*.hta|Alle Dateien (*.*)|*.*" }
            default { "PowerShell-Skripte (*.ps1;*.hta)|*.ps1;*.hta|Alle Dateien (*.*)|*.*" }
        }
        $ofd.Title = "Datei auswaehlen"
        if ($ofd.ShowDialog() -eq "OK") { $sTxtPth.Text = $ofd.FileName }
    })

    $sBtnAddImg.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Bilder (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif"
        $ofd.Title  = "Bild auswaehlen"
        if ($ofd.ShowDialog() -eq "OK") { $sLstImg.Items.Add($ofd.FileName) | Out-Null }
    })

    $sBtnRmImg.Add_Click({
        if ($sLstImg.SelectedIndex -ge 0) {
            $sLstImg.Items.RemoveAt($sLstImg.SelectedIndex)
        }
    })

    $sBtnRst.Add_Click({
        $res = [System.Windows.MessageBox]::Show(
            "Alle Tools loeschen und Beispiel-Tools wiederherstellen?",
            "Auf Werkseinstellungen zuruecksetzen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($res -eq "Yes") {
            $Script:dlgTools.Clear()
            foreach ($t in Get-DefaultTools) { $Script:dlgTools.Add($t) | Out-Null }
            Save-Tools $Script:dlgTools
            S-RefreshList
            S-ClearForm
        }
    })

    $sBtnDel.Add_Click({
        $i = $Script:dlgSelIdx
        if ($i -lt 0) { return }
        $res = [System.Windows.MessageBox]::Show(
            "Tool '$($Script:dlgTools[$i].name)' wirklich loeschen?",
            "Loeschen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($res -eq "Yes") {
            $Script:dlgTools.RemoveAt($i)
            Save-Tools $Script:dlgTools
            S-RefreshList
            S-ClearForm
        }
    })

    $sBtnSav.Add_Click({
        if ([string]::IsNullOrWhiteSpace($sTxtNam.Text)) {
            [System.Windows.MessageBox]::Show(
                "Bitte einen Namen eingeben.", "Fehler") | Out-Null
            return
        }
        $type = switch ($sCmbTyp.SelectedIndex) { 1 { "hta" } 2 { "web" } default { "powershell" } }
        $id   = ($sTxtNam.Text.ToLower() -replace '[^a-z0-9]', '_')

        $rawTags = ($sTxtTags.Text -split ',') |
                   ForEach-Object { $_.Trim() } |
                   Where-Object   { $_ -ne "" }

        $rawImgs = [System.Collections.ArrayList]@()
        foreach ($img in $sLstImg.Items) { $rawImgs.Add($img) | Out-Null }

        $vDate = if ($sDpDate.SelectedDate) {
            $sDpDate.SelectedDate.ToString("yyyy-MM-dd") } else { "" }

        $entry = [PSCustomObject]@{
            id          = $id
            name        = $sTxtNam.Text.Trim()
            type        = $type
            icon        = if ($sTxtIco.Text.Trim()) { $sTxtIco.Text.Trim() } else { "?" }
            description = $sTxtDsc.Text.Trim()
            tags        = @($rawTags)
            version     = $sTxtVer.Text.Trim()
            versionDate = $vDate
            doc         = $sTxtDoc.Text
            images      = @($rawImgs)
        }
        if ($type -eq "web") {
            $entry | Add-Member -MemberType NoteProperty -Name "url"  -Value $sTxtPth.Text.Trim()
        } else {
            $entry | Add-Member -MemberType NoteProperty -Name "path" -Value $sTxtPth.Text.Trim()
        }

        if ($Script:dlgSelIdx -ge 0) {
            $Script:dlgTools[$Script:dlgSelIdx] = $entry
        } else {
            $Script:dlgTools.Add($entry) | Out-Null
        }
        Save-Tools $Script:dlgTools
        S-RefreshList
    })

    $sBtnCls.Add_Click({ $sWin.Close() })

    S-RefreshList
    $sWin.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
# Event-Handler
# ---------------------------------------------------------------------------

$Script:modeList.Add_SelectionChanged({
    if ($Script:IgnoreModeChange) { return }
    $item = $Script:modeList.SelectedItem
    if (-not $item) { return }
    $mode = $item.Tag

    if ($mode -eq "settings") {
        $Script:IgnoreModeChange = $true
        $Script:modeList.SelectedIndex = -1
        $Script:IgnoreModeChange = $false
        Show-SettingsDialog
        Build-ToolList -Mode $Script:CurrentMode
        $Script:IgnoreModeChange = $true
        $Script:modeList.SelectedIndex = if ($Script:CurrentMode -eq "all") { 1 } else { 0 }
        $Script:IgnoreModeChange = $false
        return
    }

    Build-ToolList -Mode $mode
})

$Script:toolList.Add_SelectionChanged({
    $item = $Script:toolList.SelectedItem
    if (-not $item -or -not $item.Tag) { return }
    Show-ToolDetails -Tool $item.Tag
})

$Script:txtSearch.Add_TextChanged({
    if ($Script:CurrentMode -ne "all") { return }
    $filtered = Filter-Tools -Query $Script:txtSearch.Text
    $Script:toolList.Items.Clear()
    if ($filtered.Count -eq 0) {
        Add-EmptyStateItem "Keine Treffer."
    } else {
        foreach ($t in $filtered) { Add-ToolListItem $t }
    }
})

$Script:btnStartTool.Add_Click({
    $tool = $args[0].Tag
    if ($tool) { Start-Tool $tool }
})

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------

$Script:modeList.SelectedIndex = 0
$Script:window.ShowDialog() | Out-Null
