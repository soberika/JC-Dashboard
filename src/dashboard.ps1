#Requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$Script:ScriptDir        = $PSScriptRoot
$Script:ToolsFile        = Join-Path $Script:ScriptDir "tools.json"
$Script:UsageFile        = Join-Path $Script:ScriptDir "usage.json"
$Script:HelpFile         = Join-Path $Script:ScriptDir "help.md"
$Script:HelpDir          = Join-Path $Script:ScriptDir "help"
$Script:ChangesFile      = Join-Path $Script:ScriptDir "changes.md"
$Script:PrefsFile        = Join-Path $Script:ScriptDir "prefs.json"
$Script:CurrentMode      = "recent"
$Script:ActiveTagFilters = [System.Collections.Generic.HashSet[string]]::new()
$Script:TagPanelOpen     = $false
$Script:CurrentTheme     = "light"
$Script:IgnoreModeChange = $false

# Farb-Map fuer Tool-Badges (erweiterbar). Schluessel = lowercase type / tag.
$Script:ToolTypeColors = [ordered]@{
    "powershell" = "#1E6DB5"   # Blau
    "web"        = "#16A34A"   # Gruen
    "hta"        = "#F59E0B"   # Orange
    "windows"    = "#7C3AED"   # Lila  (Windows-Admin-Tools, .msc)
    "program"    = "#DC2626"   # Rot   (.exe / .lnk)
    "folder"     = "#0891B2"   # Tuerkis (Ordner per Explorer)
    "ml"         = "#8B5CF6"   # Lila  (Tag-Fallback)
    "jc"         = "#14B8A6"   # Teal  (Tag-Fallback)
    "default"    = "#64748B"   # Grau  (Fallback)
}

$Script:DefaultHelpText = @'
# JC Dashboard - Hilfe

Das **JC Dashboard** buendelt PowerShell-Skripte, HTA-Anwendungen und Webseiten in einer aufgeraeumten Oberflaeche.

## Aufbau
- **Linke Spalte:** Modus-Auswahl (Startseite, Zuletzt verwendet, Alle Tools, Einstellungen).
- **Mittlere Spalte:** Tool-Liste, in "Alle Tools" mit Suchfeld.
- **Rechte Spalte:** Detail-Ansicht mit Tags, Version, Doku und Start-Button.

## Diese Hilfe anpassen
Im Hilfe-Dialog auf **Bearbeiten** klicken, Text aendern und **Speichern** druecken.
'@

$Script:DefaultChangesText = @'
# Aenderungsprotokoll

Hier landen alle wichtigen Aenderungen am JC Dashboard.
Neue Eintraege bitte mit Datum (`## YYYY-MM-DD`) ueberschreiben.
'@

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

function Load-MarkdownDoc {
    param([string]$File, [string]$Default)
    if (-not (Test-Path $File)) {
        try { $Default | Set-Content -Path $File -Encoding UTF8 } catch {}
        return $Default
    }
    try { return (Get-Content $File -Raw -Encoding UTF8) }
    catch { return $Default }
}

function Save-MarkdownDoc {
    param([string]$File, [string]$Text)
    try {
        $Text | Set-Content -Path $File -Encoding UTF8
        return $true
    } catch {
        [System.Windows.MessageBox]::Show(
            "Datei konnte nicht gespeichert werden:`n$_", "Fehler",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return $false
    }
}

# Hilfe-Bibliothek: Ordner src/help/ mit beliebig vielen .md-Dateien.
# Dateiname (ohne .md) = Anzeigename. Reihenfolge per Praefix steuerbar (z.B. 01_, 02_).
function Initialize-HelpDocs {
    if (-not (Test-Path $Script:HelpDir)) {
        try { New-Item -ItemType Directory -Path $Script:HelpDir -Force | Out-Null } catch { return }
    }
    $existing = @(Get-ChildItem -Path $Script:HelpDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
    if ($existing.Count -eq 0) {
        $seed = $Script:DefaultHelpText
        if (Test-Path $Script:HelpFile) {
            try { $seed = Get-Content $Script:HelpFile -Raw -Encoding UTF8 } catch {}
        }
        $target = Join-Path $Script:HelpDir "01_Uebersicht.md"
        try { $seed | Set-Content -Path $target -Encoding UTF8 } catch {}
    }
}

function Get-HelpDocs {
    if (-not (Test-Path $Script:HelpDir)) { return ,@() }
    $items = Get-ChildItem -Path $Script:HelpDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
             Sort-Object Name
    return @($items | ForEach-Object {
        [PSCustomObject]@{
            Name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            File = $_.FullName
        }
    })
}

function Test-HelpDocName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) { if ($Name.IndexOf($c) -ge 0) { return $false } }
    if ($Name.Length -gt 80) { return $false }
    return $true
}

function New-HelpDoc {
    param([string]$Name)
    if (-not (Test-HelpDocName $Name)) { return $null }
    $file = Join-Path $Script:HelpDir ($Name + ".md")
    if (Test-Path $file) { return $null }
    $tpl = "# $Name`r`n`r`nNeue Notiz - hier Inhalt einfuegen.`r`n"
    try { $tpl | Set-Content -Path $file -Encoding UTF8 } catch { return $null }
    return $file
}

function Rename-HelpDoc {
    param([string]$OldPath, [string]$NewName)
    if (-not (Test-HelpDocName $NewName)) { return $null }
    $dir = Split-Path -Path $OldPath -Parent
    $new = Join-Path $dir ($NewName + ".md")
    if ((Test-Path $new) -and ($new -ne $OldPath)) { return $null }
    try { Move-Item -Path $OldPath -Destination $new -Force } catch { return $null }
    return $new
}

function Remove-HelpDoc {
    param([string]$Path)
    if (Test-Path $Path) {
        try { Remove-Item -Path $Path -Force; return $true } catch { return $false }
    }
    return $false
}

function Load-Prefs {
    if (-not (Test-Path $Script:PrefsFile)) { return @{} }
    try {
        $json = Get-Content $Script:PrefsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $ht   = @{}
        $json.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        return $ht
    } catch { return @{} }
}

function Save-Prefs {
    param([hashtable]$Prefs)
    try {
        $Prefs | ConvertTo-Json -Depth 3 |
            Set-Content -Path $Script:PrefsFile -Encoding UTF8
    } catch {}
}

$Script:LightPalette = @{
    AppBg          = "#F0F4F8"
    AppText        = "#0F2030"
    AppTextStrong  = "#1A3347"
    AppTextMuted   = "#607D8B"
    AppTextFaint   = "#94A3B8"
    AppBorder      = "#CBD5E1"
    AppCardBg      = "#FFFFFF"
    AppChipBg      = "#DDE4EE"
    AppChipFg      = "#475569"
    DocText        = "#2D3748"
    HelpBtnBg      = "#E2EAF2"
    HelpBtnFg      = "#1A3347"
    HelpBtnHover   = "#CFDAE6"
    HelpBtnPress   = "#BCC8D6"
}

$Script:DarkPalette = @{
    AppBg          = "#0F1620"
    AppText        = "#F1F5F9"
    AppTextStrong  = "#E2EAF2"
    AppTextMuted   = "#94A3B8"
    AppTextFaint   = "#64748B"
    AppBorder      = "#1E3A52"
    AppCardBg      = "#1A2433"
    AppChipBg      = "#1E3A52"
    AppChipFg      = "#C8D8E8"
    DocText        = "#C8D8E8"
    HelpBtnBg      = "#1E3A52"
    HelpBtnFg      = "#E2EAF2"
    HelpBtnHover   = "#2A4A66"
    HelpBtnPress   = "#355A78"
}

function Apply-Theme {
    param([string]$Mode)
    if ($Mode -ne "dark") { $Mode = "light" }
    $palette = if ($Mode -eq "dark") { $Script:DarkPalette } else { $Script:LightPalette }
    $conv = [System.Windows.Media.BrushConverter]::new()
    foreach ($key in $palette.Keys) {
        $brush = $conv.ConvertFromString($palette[$key])
        $brush.Freeze()
        $Script:window.Resources[$key] = $brush
    }
    $Script:CurrentTheme = $Mode
    if ($Script:btnTheme) {
        $Script:btnTheme.Content = if ($Mode -eq "dark") { [char]0x2600 } else { [char]0x263D }
        $Script:btnTheme.ToolTip = if ($Mode -eq "dark") { "Light-Mode" } else { "Dark-Mode" }
    }
    # Aktive Tool-Details neu rendern, damit dynamisch erzeugte Elemente die neuen Farben uebernehmen
    $current = $Script:btnStartTool.Tag
    if ($current -and $Script:detailScroll.Visibility -eq "Visible") {
        Show-ToolDetails -Tool $current
    }
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

        <!-- Theme-Brushes (werden zur Laufzeit getauscht) -->
        <SolidColorBrush x:Key="AppBg"          Color="#F0F4F8"/>
        <SolidColorBrush x:Key="AppText"        Color="#0F2030"/>
        <SolidColorBrush x:Key="AppTextStrong"  Color="#1A3347"/>
        <SolidColorBrush x:Key="AppTextMuted"   Color="#607D8B"/>
        <SolidColorBrush x:Key="AppTextFaint"   Color="#94A3B8"/>
        <SolidColorBrush x:Key="AppBorder"      Color="#CBD5E1"/>
        <SolidColorBrush x:Key="AppCardBg"      Color="#FFFFFF"/>
        <SolidColorBrush x:Key="AppChipBg"      Color="#DDE4EE"/>
        <SolidColorBrush x:Key="AppChipFg"      Color="#475569"/>
        <SolidColorBrush x:Key="DocText"        Color="#2D3748"/>
        <SolidColorBrush x:Key="HelpBtnBg"      Color="#E2EAF2"/>
        <SolidColorBrush x:Key="HelpBtnFg"      Color="#1A3347"/>
        <SolidColorBrush x:Key="HelpBtnHover"   Color="#CFDAE6"/>
        <SolidColorBrush x:Key="HelpBtnPress"   Color="#BCC8D6"/>

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
                            <ContentPresenter Margin="14,13"/>
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

        <Style x:Key="HomeButton" TargetType="Button">
            <Setter Property="Background" Value="#0D1F2D"/>
            <Setter Property="Foreground" Value="#C8D8E8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,12"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="#1A3347" BorderThickness="0,0,0,1">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#162A3A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1A3347"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BottomNavButton" TargetType="Button" BasedOn="{StaticResource HomeButton}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="#1A3347" BorderThickness="0,1,0,0">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#162A3A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1A3347"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="IconNavButton" TargetType="Button">
            <Setter Property="Background" Value="#0D1F2D"/>
            <Setter Property="Foreground" Value="#7C9AB8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Width" Value="44"/>
            <Setter Property="Height" Value="36"/>
            <Setter Property="Margin" Value="4,0,4,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1A3347"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1E4A6E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="HelpButton" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource HelpBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource HelpBtnFg}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="22,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource HelpBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource HelpBtnPress}"/>
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
            <Button DockPanel.Dock="Top" x:Name="btnHome"
                    Style="{StaticResource HomeButton}"
                    Content="&#127968;  Startseite"/>

            <Border DockPanel.Dock="Bottom"
                    Background="#0A1822" BorderBrush="#1A3347"
                    BorderThickness="0,1,0,0" Padding="0,10,0,10">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnSettings"
                            Style="{StaticResource IconNavButton}"
                            Content="&#9881;" ToolTip="Einstellungen"/>
                    <Button x:Name="btnHelpMini"
                            Style="{StaticResource IconNavButton}"
                            Content="&#10068;" ToolTip="Hilfe"/>
                    <Button x:Name="btnChangesMini"
                            Style="{StaticResource IconNavButton}"
                            Content="&#128221;" ToolTip="&#196;nderungsprotokoll"/>
                    <Button x:Name="btnTheme"
                            Style="{StaticResource IconNavButton}"
                            Content="&#9789;" ToolTip="Dark-Mode"/>
                </StackPanel>
            </Border>

            <ListBox x:Name="modeList" Background="Transparent"
                     BorderThickness="0" Margin="0,10,0,0">
                <ListBoxItem Style="{StaticResource ModeItem}" Tag="recent"
                             Content="Zuletzt verwendet"/>
                <ListBoxItem Style="{StaticResource ModeItem}" Tag="all"
                             Content="Alle Tools (A-Z)"/>
            </ListBox>
        </DockPanel>

        <!-- COL 2: Tool-Liste -->
        <Grid Grid.Column="1" Background="#152A3D">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
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

            <!-- Tag-Filter (Modus "all") -->
            <Border Grid.Row="1" x:Name="tagFilterSection" Visibility="Collapsed"
                    Background="#0F2030" BorderBrush="#1E3A52" BorderThickness="0,0,0,1">
                <StackPanel>
                    <Button x:Name="btnTagToggle" Background="Transparent"
                            BorderThickness="0" HorizontalContentAlignment="Left"
                            Padding="16,7" Cursor="Hand">
                        <TextBlock x:Name="txtTagToggle" Text="&#9656; Tags filtern"
                                   Foreground="#7C9AB8" FontSize="11" FontWeight="SemiBold"/>
                    </Button>
                    <Border x:Name="tagChipBorder" Visibility="Collapsed"
                            Padding="12,0,12,8">
                        <WrapPanel x:Name="tagChipPanel" Orientation="Horizontal"/>
                    </Border>
                </StackPanel>
            </Border>

            <ListBox Grid.Row="2" x:Name="toolList"
                     Background="Transparent" BorderThickness="0"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
        </Grid>

        <!-- COL 3: Detail-Pane -->
        <Grid Grid.Column="2" Background="{DynamicResource AppBg}">

            <!-- Welcome -->
            <StackPanel x:Name="welcomePanel"
                        HorizontalAlignment="Center" VerticalAlignment="Center"
                        MaxWidth="560">
                <TextBlock Text="&#128075;" FontSize="52"
                           HorizontalAlignment="Center"/>
                <TextBlock Text="Willkommen im JC Dashboard"
                           FontSize="22" FontWeight="SemiBold"
                           Foreground="{DynamicResource AppTextStrong}" HorizontalAlignment="Center"
                           Margin="0,14,0,10"/>
                <TextBlock Foreground="{DynamicResource AppTextMuted}" FontSize="14"
                           HorizontalAlignment="Center"
                           TextWrapping="Wrap" TextAlignment="Center"
                           Margin="20,0,20,6"
                           Text="Deine zentrale Anlaufstelle f&#252;r Skripte, HTA- und Web-Tools. W&#228;hle links den Modus, in der Mitte ein Tool - rechts findest du Details, Doku und den Start-Button."/>
                <TextBlock Foreground="{DynamicResource AppTextFaint}" FontSize="12"
                           HorizontalAlignment="Center"
                           TextWrapping="Wrap" TextAlignment="Center"
                           Margin="20,4,20,22"
                           Text="Tipp: &#252;ber 'Hilfe &#246;ffnen' findest du eine kurze Anleitung - die du selbst erg&#228;nzen kannst."/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnHelp"
                            Style="{StaticResource HelpButton}"
                            Content="&#10068;  Hilfe &#246;ffnen"/>
                    <Button x:Name="btnChanges"
                            Style="{StaticResource HelpButton}"
                            Margin="10,0,0,0"
                            Content="&#128221;  &#196;nderungen"/>
                </StackPanel>
            </StackPanel>

            <!-- Details -->
            <ScrollViewer x:Name="detailScroll" Visibility="Collapsed"
                          VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">
                <StackPanel Margin="32,28,32,32">

                    <StackPanel Orientation="Horizontal">
                        <ContentControl x:Name="detailBadgeHost"
                                        VerticalAlignment="Center"
                                        Margin="0,0,18,0"/>
                        <TextBlock x:Name="detailTitle"
                                   FontSize="26" FontWeight="Bold"
                                   VerticalAlignment="Center"
                                   Foreground="{DynamicResource AppText}" TextWrapping="Wrap"/>
                    </StackPanel>

                    <WrapPanel x:Name="detailMeta" Margin="0,10,0,14"/>

                    <WrapPanel x:Name="detailTags" Margin="0,0,0,16"/>

                    <Separator Background="{DynamicResource AppBorder}" Margin="0,0,0,16"/>

                    <RichTextBox x:Name="docViewer"
                                 IsReadOnly="True" BorderThickness="0"
                                 Background="Transparent"
                                 IsDocumentEnabled="True"
                                 Padding="0" FontSize="13"
                                 Foreground="{DynamicResource DocText}"
                                 Visibility="Collapsed"/>

                    <WrapPanel x:Name="imageGallery"
                               Margin="0,12,0,0" Visibility="Collapsed"/>

                    <Separator Background="{DynamicResource AppBorder}" Margin="0,24,0,20"/>

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
$Script:tagFilterSection = $Script:window.FindName("tagFilterSection")
$Script:tagChipBorder    = $Script:window.FindName("tagChipBorder")
$Script:tagChipPanel     = $Script:window.FindName("tagChipPanel")
$Script:btnTagToggle     = $Script:window.FindName("btnTagToggle")
$Script:txtTagToggle     = $Script:window.FindName("txtTagToggle")
$Script:welcomePanel     = $Script:window.FindName("welcomePanel")
$Script:detailScroll     = $Script:window.FindName("detailScroll")
$Script:detailTitle      = $Script:window.FindName("detailTitle")
$Script:detailBadgeHost  = $Script:window.FindName("detailBadgeHost")
$Script:detailMeta       = $Script:window.FindName("detailMeta")
$Script:detailTags       = $Script:window.FindName("detailTags")
$Script:docViewer        = $Script:window.FindName("docViewer")
$Script:imageGallery     = $Script:window.FindName("imageGallery")
$Script:btnStartTool     = $Script:window.FindName("btnStartTool")
$Script:btnHome          = $Script:window.FindName("btnHome")
$Script:btnHelp          = $Script:window.FindName("btnHelp")
$Script:btnChanges       = $Script:window.FindName("btnChanges")
$Script:btnSettings      = $Script:window.FindName("btnSettings")
$Script:btnHelpMini      = $Script:window.FindName("btnHelpMini")
$Script:btnChangesMini   = $Script:window.FindName("btnChangesMini")
$Script:btnTheme         = $Script:window.FindName("btnTheme")

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

    $bDoc = $Script:window.FindResource("DocText")
    $bH1  = $Script:window.FindResource("AppText")
    $bH2  = $Script:window.FindResource("AppTextStrong")

    $doc            = New-Object System.Windows.Documents.FlowDocument
    $doc.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $doc.FontSize   = 13
    $doc.Foreground = $bDoc

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
            $r.Foreground = $bH1
            $p.Inlines.Add($r) | Out-Null
            $doc.Blocks.Add($p) | Out-Null
        } elseif ($line -match '^## (.+)$') {
            & $flushList
            $p = New-Object System.Windows.Documents.Paragraph
            $p.Margin = New-Object System.Windows.Thickness(0, 10, 0, 3)
            $r = New-Object System.Windows.Documents.Run($Matches[1])
            $r.FontSize   = 15
            $r.FontWeight = [System.Windows.FontWeights]::SemiBold
            $r.Foreground = $bH2
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

# Liefert die Hex-Farbe fuer den Badge eines Tools.
# Erst Typ-Match, dann Tag-Fallback (ML/JC), sonst Default-Grau.
function Get-ToolBadgeColor {
    param($Tool)
    if (-not $Tool) { return $Script:ToolTypeColors["default"] }
    $type = if ($Tool.type) { ([string]$Tool.type).ToLower() } else { "" }
    if ($type -and $Script:ToolTypeColors.Contains($type)) {
        return $Script:ToolTypeColors[$type]
    }
    if ($Tool.tags) {
        foreach ($t in $Tool.tags) {
            $low = ([string]$t).ToLower()
            if ($Script:ToolTypeColors.Contains($low)) {
                return $Script:ToolTypeColors[$low]
            }
        }
    }
    return $Script:ToolTypeColors["default"]
}

# Loest einen Icon-Bildpfad auf (relativ zu Script-Dir oder absolut). Gibt
# den absoluten Pfad zurueck wenn die Datei existiert, sonst $null.
function Resolve-ToolIconPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $abs = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } `
           else { Join-Path $Script:ScriptDir $Path }
    if (Test-Path -LiteralPath $abs) { return $abs }
    return $null
}

# Laedt ein Bild (.ico/.png/.jpg/.bmp) als gefrorenes BitmapImage. CacheOption
# OnLoad sorgt dafuer, dass die Datei nicht durch WPF gesperrt bleibt.
function Get-ToolIconBitmap {
    param([string]$AbsolutePath)
    try {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource   = New-Object System.Uri($AbsolutePath, [System.UriKind]::Absolute)
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.EndInit()
        $bi.Freeze()
        return $bi
    } catch {
        return $null
    }
}

# Erzeugt einen runden, "premium" wirkenden Tool-Badge.
#
# Reihenfolge fuer den Inhalt:
#   1. Bild aus $Tool.iconPath (.ico/.png/.jpg...) - kreisrund geclippt
#   2. Emoji/Text aus $Tool.icon
#   3. Fallback "?"
#
# Wichtig fuer das Rendering:
#   - Die XAML wird KONDITIONAL gebaut (nur Image ODER nur TextBlock im Grid),
#     kein Visibility-Switching - das vermeidet Layout-Caching-Effekte.
#   - Panel.ZIndex wird auf allen Children explizit gesetzt. Sonst kann der
#     DropShadowEffect auf der Ellipse dazu fuehren, dass Geschwister
#     darunter statt darueber rendern (bekannter WPF-Quirk).
#   - Fill und Text werden direkt im XAML eingebettet, damit alle Properties
#     vor dem ersten Layout-Pass gesetzt sind. Image.Source/Clip werden danach
#     per Property gesetzt (URI-Konvertierung ist im Attribut umstaendlich).
function New-ToolBadge {
    param(
        $Tool,
        [int]$Size = 48,
        [string]$OverrideIcon = $null,
        [string]$OverrideColor = $null,
        [string]$OverrideIconPath = $null
    )
    $color = if ($OverrideColor) { $OverrideColor } else { Get-ToolBadgeColor -Tool $Tool }
    # Wichtig: [string]$OverrideIcon = $null in der Parameter-Deklaration wird
    # zu "" gecastet - daher hier explizit auf nicht-leer pruefen, sonst greift
    # der Override-Zweig immer und $Tool.icon wird nie gelesen.
    $emoji = if (-not [string]::IsNullOrEmpty($OverrideIcon)) { $OverrideIcon } `
             elseif ($Tool -and $Tool.icon -and -not [string]::IsNullOrWhiteSpace([string]$Tool.icon)) { [string]$Tool.icon } `
             else { "?" }

    # Bildpfad bestimmen (Override > Tool.iconPath) und ggf. laden.
    $rawPath = if (-not [string]::IsNullOrEmpty($OverrideIconPath)) { $OverrideIconPath } `
               elseif ($Tool -and $Tool.iconPath) { [string]$Tool.iconPath } `
               else { "" }
    $imgPath = Resolve-ToolIconPath -Path $rawPath
    $bitmap  = if ($imgPath) { Get-ToolIconBitmap -AbsolutePath $imgPath } else { $null }

    $fontSize = [Math]::Round($Size * 0.55)

    # Konditionale Content-XAML: nur das Element, das wir wirklich brauchen.
    if ($bitmap) {
        $contentXaml = '<Image x:Name="badgeImage" Stretch="Uniform" IsHitTestVisible="False" Panel.ZIndex="10"/>'
    } else {
        # TextBlock leer im XAML anlegen, Text wird programmatisch gesetzt
        # (sonst wuerde der XmlReader Surrogate-Pairs aus Emojis verschlucken).
        $contentXaml = @"
<TextBlock x:Name="badgeText"
           Foreground="White" FontWeight="SemiBold"
           FontSize="$fontSize" FontFamily="Segoe UI Emoji"
           HorizontalAlignment="Center" VerticalAlignment="Center"
           TextAlignment="Center" IsHitTestVisible="False"
           Panel.ZIndex="10">
    <TextBlock.Effect>
        <DropShadowEffect BlurRadius="3" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </TextBlock.Effect>
</TextBlock>
"@
    }

    # Inline-XAML: Grid mit Ellipse + Inhalt. Effekt nur auf der Ellipse,
    # ScaleTransform auf dem Grid. ZIndex explizit, damit der Inhalt sicher
    # ueber der schatten-behafteten Disc liegt.
    $xaml = @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Width="$Size" Height="$Size"
      Background="Transparent"
      HorizontalAlignment="Center" VerticalAlignment="Center"
      SnapsToDevicePixels="True" UseLayoutRounding="True"
      RenderTransformOrigin="0.5,0.5">
    <Grid.RenderTransform>
        <ScaleTransform ScaleX="1" ScaleY="1"/>
    </Grid.RenderTransform>
    <Ellipse x:Name="badgeDisc"
             Fill="$color" Stroke="White" StrokeThickness="2.5"
             IsHitTestVisible="False" Panel.ZIndex="0">
        <Ellipse.Effect>
            <DropShadowEffect BlurRadius="10" ShadowDepth="2"
                              Direction="270" Opacity="0.4" Color="#000000"/>
        </Ellipse.Effect>
    </Ellipse>
    $contentXaml
</Grid>
"@

    $reader    = New-Object System.IO.StringReader($xaml)
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $root      = [System.Windows.Markup.XamlReader]::Load($xmlReader)
    $xmlReader.Close()

    $tb = $root.FindName("badgeText")

    if ($bitmap) {
        # Image fuellt das gesamte Grid (48x48) und wird kreisrund geclippt.
        # Clip-Koordinaten sind in Image-LOKALEN Koordinaten - da Image kein
        # Margin hat, sind sie identisch mit den Grid-Koordinaten.
        $image = $root.FindName("badgeImage")
        $r = ($Size - 5.0) / 2.0   # Radius = halbe Groesse - StrokeThickness (=2.5)
        $c = $Size / 2.0           # Mittelpunkt = halbe Groesse
        $image.Clip   = New-Object System.Windows.Media.EllipseGeometry(
            (New-Object System.Windows.Point($c, $c)), $r, $r)
        $image.Source = $bitmap
    } else {
        # Emoji programmatisch setzen - umgeht XmlReader-Encoding-Probleme
        # mit Surrogate-Pairs (z. B. 🌐, 💻).
        if ($tb) { $tb.Text = $emoji }
    }

    # Hover-Farbe in Tag merken (Color-Struct, kein Brush)
    $bConv     = [System.Windows.Media.BrushConverter]::new()
    $fillBrush = $bConv.ConvertFromString($color)
    $root.Tag  = ([System.Windows.Media.SolidColorBrush]$fillBrush).Color

    # Hover: farbiger Glow auf der Disc + 1.08x Skalierung des Grids
    $root.Add_MouseEnter({
        $g = $args[0]
        $d = $g.FindName("badgeDisc")
        $e = New-Object System.Windows.Media.Effects.DropShadowEffect
        $e.BlurRadius  = 18
        $e.ShadowDepth = 0
        $e.Opacity     = 0.85
        $e.Color       = $g.Tag
        $d.Effect      = $e
        if ($g.RenderTransform -is [System.Windows.Media.ScaleTransform]) {
            $g.RenderTransform.ScaleX = 1.08
            $g.RenderTransform.ScaleY = 1.08
        }
    })
    $root.Add_MouseLeave({
        $g = $args[0]
        $d = $g.FindName("badgeDisc")
        $e = New-Object System.Windows.Media.Effects.DropShadowEffect
        $e.BlurRadius  = 10
        $e.ShadowDepth = 2
        $e.Direction   = 270
        $e.Opacity     = 0.40
        $e.Color       = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
        $d.Effect      = $e
        if ($g.RenderTransform -is [System.Windows.Media.ScaleTransform]) {
            $g.RenderTransform.ScaleX = 1.0
            $g.RenderTransform.ScaleY = 1.0
        }
    })

    return $root
}

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
    $border.Background   = $Script:window.FindResource("AppChipBg")
    $border.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $border.Padding      = New-Object System.Windows.Thickness(10, 4, 10, 4)
    $border.Margin       = New-Object System.Windows.Thickness(0, 0, 6, 6)
    $tb                  = New-Object System.Windows.Controls.TextBlock
    $tb.Text             = $Text
    $tb.Foreground       = $Script:window.FindResource("AppChipFg")
    $tb.FontSize         = 12
    $border.Child        = $tb
    return $border
}

function Add-ToolListItem {
    param($Tool)
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Style = $Script:window.FindResource("ToolItem")
    $item.Tag   = $Tool

    # 2-Spalten-Grid: Badge | Texte
    $grid = New-Object System.Windows.Controls.Grid
    $colBadge = New-Object System.Windows.Controls.ColumnDefinition
    $colBadge.Width = [System.Windows.GridLength]::Auto
    $colText  = New-Object System.Windows.Controls.ColumnDefinition
    $colText.Width  = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($colBadge) | Out-Null
    $grid.ColumnDefinitions.Add($colText)  | Out-Null

    $badge = New-ToolBadge -Tool $Tool -Size 40
    $badge.Margin = New-Object System.Windows.Thickness(0, 0, 14, 0)
    [System.Windows.Controls.Grid]::SetColumn($badge, 0)
    $grid.Children.Add($badge) | Out-Null
    # Hover-Glow + ScaleTransform werden zentral in New-ToolBadge gesetzt.

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)

    $nameBlock              = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text         = [string]$Tool.name
    $nameBlock.FontSize     = 13
    $nameBlock.FontWeight   = "SemiBold"
    $nameBlock.Foreground   = "#E2EAF2"
    $nameBlock.TextTrimming = "CharacterEllipsis"

    $typeLabel = switch ($Tool.type) {
        "web"     { "Webanwendung"      }
        "hta"     { "HTA-Anwendung"     }
        "windows" { "Windows-Anwendung" }
        "program" { "Programm"          }
        "folder"  { "Ordner"            }
        default   { "PowerShell"        }
    }
    $typeBlock            = New-Object System.Windows.Controls.TextBlock
    $typeBlock.Text       = $typeLabel
    $typeBlock.FontSize   = 11
    $typeBlock.Foreground = "#7C9AB8"
    $typeBlock.Margin     = New-Object System.Windows.Thickness(0, 2, 0, 0)

    $sp.Children.Add($nameBlock) | Out-Null
    $sp.Children.Add($typeBlock) | Out-Null
    $grid.Children.Add($sp) | Out-Null

    $item.Content = $grid
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
# Bild-Lightbox
# ---------------------------------------------------------------------------

function Show-ImageLightbox {
    param([string]$ImagePath, [string]$Caption)
    if (-not (Test-Path $ImagePath)) { return }

    [xml]$LbxXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" WindowState="Maximized"
        Background="#1A1A1A" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner">
    <Grid x:Name="root" Cursor="Hand">
        <Image x:Name="lbxImg" Stretch="Uniform" Margin="40,40,40,90"/>
        <TextBlock x:Name="lbxCap" Visibility="Collapsed"
                   HorizontalAlignment="Center" VerticalAlignment="Bottom"
                   Margin="40,0,40,38" MaxWidth="900"
                   Foreground="#E2EAF2" FontSize="14"
                   TextWrapping="Wrap" TextAlignment="Center"/>
        <TextBlock Text="(Klick oder ESC zum Schliessen)"
                   HorizontalAlignment="Right" VerticalAlignment="Top"
                   Margin="0,16,24,0" Foreground="#7C9AB8" FontSize="11"/>
    </Grid>
</Window>
'@
    $r              = New-Object System.Xml.XmlNodeReader($LbxXaml)
    $Script:lbxWin  = [System.Windows.Markup.XamlReader]::Load($r)
    $Script:lbxWin.Owner = $Script:window

    $lbxImg  = $Script:lbxWin.FindName("lbxImg")
    $lbxCap  = $Script:lbxWin.FindName("lbxCap")
    $lbxRoot = $Script:lbxWin.FindName("root")

    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource   = New-Object System.Uri($ImagePath)
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $lbxImg.Source = $bmp
    } catch { return }

    if ($Caption) {
        $lbxCap.Text = $Caption
        $lbxCap.Visibility = "Visible"
    }

    $lbxRoot.Add_MouseLeftButtonDown({ $Script:lbxWin.Close() })
    $Script:lbxWin.Add_KeyDown({
        if ($args[1].Key -eq [System.Windows.Input.Key]::Escape) {
            $Script:lbxWin.Close()
        }
    })

    $Script:lbxWin.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
# Tag-Filter (Col 2)
# ---------------------------------------------------------------------------

function Build-TagChips {
    param([array]$AllTools)
    $Script:tagChipPanel.Children.Clear()
    $allTags = @($AllTools | ForEach-Object { $_.tags } | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($tag in $allTags) {
        $isActive = $Script:ActiveTagFilters.Contains($tag)
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content         = $tag
        $btn.Tag             = $tag
        $btn.Margin          = New-Object System.Windows.Thickness(0, 0, 4, 4)
        $btn.Padding         = New-Object System.Windows.Thickness(8, 3, 8, 3)
        $btn.FontSize        = 11
        $btn.Cursor          = [System.Windows.Input.Cursors]::Hand
        $btn.BorderThickness = New-Object System.Windows.Thickness(1)
        if ($isActive) {
            $btn.Background  = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#1E6DB5")
            $btn.Foreground  = [System.Windows.Media.Brushes]::White
            $btn.BorderBrush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#1E6DB5")
        } else {
            $btn.Background  = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground  = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#7C9AB8")
            $btn.BorderBrush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString("#2A4A65")
        }
        $btn.Add_Click({
            $t = $args[0].Tag
            if ($Script:ActiveTagFilters.Contains($t)) {
                $Script:ActiveTagFilters.Remove($t) | Out-Null
            } else {
                $Script:ActiveTagFilters.Add($t) | Out-Null
            }
            Refresh-ToolListFiltered
        })
        $Script:tagChipPanel.Children.Add($btn) | Out-Null
    }
}

function Refresh-ToolListFiltered {
    $Script:toolList.Items.Clear()
    $loaded = @(Load-Tools | Sort-Object name)

    $q = $Script:txtSearch.Text
    $tools = if ([string]::IsNullOrWhiteSpace($q)) { $loaded } else {
        $ql = $q.ToLower()
        @($loaded | Where-Object {
            ($_.name        -and $_.name.ToLower().Contains($ql))        -or
            ($_.doc         -and $_.doc.ToLower().Contains($ql))         -or
            ($_.description -and $_.description.ToLower().Contains($ql)) -or
            ($_.tags        -and ($_.tags | Where-Object { $_ -and $_.ToLower().Contains($ql) }))
        })
    }

    if ($Script:ActiveTagFilters.Count -gt 0) {
        $tools = @($tools | Where-Object {
            $_.tags | Where-Object { $Script:ActiveTagFilters.Contains($_) }
        })
    }

    Build-TagChips -AllTools $loaded

    if ($tools.Count -eq 0) {
        Add-EmptyStateItem "Keine Treffer."
    } else {
        foreach ($t in $tools) { Add-ToolListItem $t }
    }
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
        $Script:col2Header.Visibility       = "Visible"
        $Script:searchBorder.Visibility     = "Collapsed"
        $Script:tagFilterSection.Visibility = "Collapsed"
        $Script:ActiveTagFilters.Clear()
        $Script:TagPanelOpen                = $false
        $Script:col2Title.Text = "ZULETZT VERWENDET"
        $tools = Get-RecentTools
        if ($tools.Count -eq 0) {
            Add-EmptyStateItem "Noch kein Tool gestartet."
        } else {
            foreach ($t in $tools) { Add-ToolListItem $t }
        }
    } else {
        $Script:col2Header.Visibility       = "Collapsed"
        $Script:searchBorder.Visibility     = "Visible"
        $Script:tagFilterSection.Visibility = "Visible"
        $Script:tagChipBorder.Visibility    = if ($Script:TagPanelOpen) { "Visible" } else { "Collapsed" }
        $Script:txtTagToggle.Text           = if ($Script:TagPanelOpen) { "$([char]0x25BE) Tags filtern" } else { "$([char]0x25B8) Tags filtern" }
        $Script:txtSearch.Text              = ""
        Refresh-ToolListFiltered
    }
}

# ---------------------------------------------------------------------------
# Detail-Pane befuellen (Col 3)
# ---------------------------------------------------------------------------

function Show-ToolDetails {
    param($Tool)
    $Script:welcomePanel.Visibility = "Collapsed"
    $Script:detailScroll.Visibility = "Visible"

    $Script:detailTitle.Text = [string]$Tool.name
    $Script:detailBadgeHost.Content = New-ToolBadge -Tool $Tool -Size 54

    # Meta-Chips
    $Script:detailMeta.Children.Clear()
    $catText = switch ($Tool.type) {
        "web"     { "Webanwendung"      }
        "hta"     { "HTA-Anwendung"     }
        "windows" { "Windows-Anwendung" }
        "program" { "Programm"          }
        "folder"  { "Ordner"            }
        default   { "PowerShell"        }
    }
    $Script:detailMeta.Children.Add((New-MetaChip -Text $catText -BgHex (Get-ToolBadgeColor -Tool $Tool))) | Out-Null

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
        foreach ($entry in $Tool.images) {
            if ($entry -is [string]) {
                $imgPath = $entry
                $imgCap  = ""
            } else {
                $imgPath = $entry.path
                $imgCap  = if ($entry.caption) { $entry.caption } else { "" }
            }
            $full = if ([System.IO.Path]::IsPathRooted($imgPath)) { $imgPath } `
                    else { Join-Path $Script:ScriptDir $imgPath }

            $container = New-Object System.Windows.Controls.StackPanel
            $container.Margin = New-Object System.Windows.Thickness(0, 0, 14, 14)
            $container.Width  = 360

            $border = New-Object System.Windows.Controls.Border
            $border.BorderThickness = New-Object System.Windows.Thickness(1)
            $border.BorderBrush     = $Script:window.FindResource("AppBorder")
            $border.CornerRadius    = New-Object System.Windows.CornerRadius(4)

            $clickable = $false
            if (Test-Path $full) {
                try {
                    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bmp.BeginInit()
                    $bmp.UriSource   = New-Object System.Uri($full)
                    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                    $bmp.EndInit()
                    $img            = New-Object System.Windows.Controls.Image
                    $img.Source     = $bmp
                    $img.MaxWidth   = 360
                    $img.MaxHeight  = 260
                    $img.Stretch    = "Uniform"
                    $border.Child   = $img
                    $clickable      = $true
                } catch {
                    $tb = New-Object System.Windows.Controls.TextBlock
                    $tb.Text       = "[Bild konnte nicht geladen werden]"
                    $tb.Foreground = $Script:window.FindResource("AppTextFaint")
                    $tb.Margin     = New-Object System.Windows.Thickness(10, 6, 10, 6)
                    $border.Child  = $tb
                }
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text       = "[Nicht gefunden: $imgPath]"
                $tb.Foreground = $Script:window.FindResource("AppTextFaint")
                $tb.Margin     = New-Object System.Windows.Thickness(10, 6, 10, 6)
                $border.Child  = $tb
            }

            if ($clickable) {
                $border.Cursor = [System.Windows.Input.Cursors]::Hand
                $border.Tag    = [PSCustomObject]@{ Path = $full; Caption = $imgCap }
                $border.Add_MouseLeftButtonDown({
                    $data = $args[0].Tag
                    Show-ImageLightbox -ImagePath $data.Path -Caption $data.Caption
                })
            }
            $container.Children.Add($border) | Out-Null

            if ($imgCap) {
                $capBlock              = New-Object System.Windows.Controls.TextBlock
                $capBlock.Text         = $imgCap
                $capBlock.Foreground   = $Script:window.FindResource("AppChipFg")
                $capBlock.FontSize     = 11
                $capBlock.FontStyle    = "Italic"
                $capBlock.Margin       = New-Object System.Windows.Thickness(2, 5, 2, 0)
                $capBlock.TextWrapping = "Wrap"
                $capBlock.TextAlignment = "Center"
                $container.Children.Add($capBlock) | Out-Null
            }

            $Script:imageGallery.Children.Add($container) | Out-Null
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
        if ($Tool.type -eq "folder") {
            $folderPath = $Tool.path
            Start-Process "explorer.exe" -ArgumentList $folderPath
            Update-LastUsed -ToolId $Tool.id
            if ($Script:CurrentMode -eq "recent") { Build-ToolList -Mode "recent" }
            return
        }
        $path = if ([System.IO.Path]::IsPathRooted($Tool.path)) {
            $Tool.path } else { Join-Path $Script:ScriptDir $Tool.path }
        if (Test-Path $path) {
            if ($Tool.type -eq "powershell") {
                Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$path`""
            } else {
                Start-Process $path
            }
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
# Markdown-Dokument-Dialog (Hilfe / Aenderungen)
# ---------------------------------------------------------------------------

function Show-MarkdownDocDialog {
    param(
        [string]$Title    = "Dokument",
        [string]$Subtitle = "Dokument",
        [string]$File,
        [string]$Default  = ""
    )

    [xml]$HXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Height="640" Width="820"
        WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI"
        Background="{DynamicResource AppBg}">

    <Window.Resources>
        <Style x:Key="HBtn" TargetType="Button">
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
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Toolbar -->
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
                <TextBlock Text="$Subtitle"
                           FontWeight="SemiBold" FontSize="16"
                           Foreground="{DynamicResource AppTextStrong}"/>
                <TextBlock x:Name="hHint"
                           Text="Lese-Modus &#8211; klicke auf 'Bearbeiten', um den Text zu &#228;ndern."
                           Foreground="{DynamicResource AppTextMuted}" FontSize="11" Margin="0,3,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
                <Button x:Name="hBtnEdit" Content="&#9998;  Bearbeiten"
                        Style="{StaticResource HBtn}" Background="#1E6DB5"/>
                <Button x:Name="hBtnSave" Content="&#128190;  Speichern"
                        Style="{StaticResource HBtn}" Background="#16A34A"
                        Margin="8,0,0,0" Visibility="Collapsed"/>
                <Button x:Name="hBtnCancel" Content="Abbrechen"
                        Style="{StaticResource HBtn}" Background="#94A3B8"
                        Margin="8,0,0,0" Visibility="Collapsed"/>
            </StackPanel>
        </Grid>

        <!-- Lese-Ansicht -->
        <Border Grid.Row="1" x:Name="hViewBorder"
                Background="{DynamicResource AppCardBg}"
                BorderBrush="{DynamicResource AppBorder}" BorderThickness="1"
                CornerRadius="4">
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled" Padding="20,14">
                <RichTextBox x:Name="hViewer" IsReadOnly="True"
                             BorderThickness="0" Background="Transparent"
                             IsDocumentEnabled="True"
                             Padding="0" FontSize="13"
                             Foreground="{DynamicResource DocText}"/>
            </ScrollViewer>
        </Border>

        <!-- Bearbeiten-Ansicht -->
        <TextBox Grid.Row="1" x:Name="hEditor" Visibility="Collapsed"
                 AcceptsReturn="True" TextWrapping="Wrap"
                 VerticalScrollBarVisibility="Auto"
                 BorderBrush="{DynamicResource AppBorder}" BorderThickness="1"
                 Background="{DynamicResource AppCardBg}"
                 Foreground="{DynamicResource AppText}"
                 CaretBrush="{DynamicResource AppText}"
                 Padding="12,10"
                 FontFamily="Consolas" FontSize="12"/>

        <!-- Footer -->
        <StackPanel Grid.Row="2" HorizontalAlignment="Right"
                    Orientation="Horizontal" Margin="0,12,0,0">
            <Button x:Name="hBtnClose" Content="Schlie&#223;en"
                    Style="{StaticResource HBtn}" Background="#64748B" Padding="20,9"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $hr           = New-Object System.Xml.XmlNodeReader($HXaml)
    $hWin         = [System.Windows.Markup.XamlReader]::Load($hr)
    $hWin.Owner   = $Script:window

    foreach ($k in @("AppBg","AppText","AppTextStrong","AppTextMuted","AppTextFaint",
                     "AppBorder","AppCardBg","DocText")) {
        $hWin.Resources[$k] = $Script:window.FindResource($k)
    }

    $hViewer      = $hWin.FindName("hViewer")
    $hViewBorder  = $hWin.FindName("hViewBorder")
    $hEditor      = $hWin.FindName("hEditor")
    $hBtnEdit     = $hWin.FindName("hBtnEdit")
    $hBtnSave     = $hWin.FindName("hBtnSave")
    $hBtnCancel   = $hWin.FindName("hBtnCancel")
    $hBtnClose    = $hWin.FindName("hBtnClose")
    $hHint        = $hWin.FindName("hHint")

    $docFile    = $File
    $docDefault = $Default

    $renderDoc = {
        $txt = Load-MarkdownDoc -File $docFile -Default $docDefault
        $hViewer.Document = Convert-MarkdownToFlowDocument -Text $txt
        $hEditor.Text     = $txt
    }
    & $renderDoc

    $enterEdit = {
        $hViewBorder.Visibility = "Collapsed"
        $hEditor.Visibility     = "Visible"
        $hBtnEdit.Visibility    = "Collapsed"
        $hBtnSave.Visibility    = "Visible"
        $hBtnCancel.Visibility  = "Visible"
        $hHint.Text             = "Bearbeiten - Markdown wird beim Speichern wieder formatiert dargestellt."
        $hEditor.Focus() | Out-Null
    }

    $exitEdit = {
        $hEditor.Visibility     = "Collapsed"
        $hViewBorder.Visibility = "Visible"
        $hBtnEdit.Visibility    = "Visible"
        $hBtnSave.Visibility    = "Collapsed"
        $hBtnCancel.Visibility  = "Collapsed"
        $hHint.Text             = "Lese-Modus - klicke auf 'Bearbeiten', um den Text zu aendern."
    }

    $hBtnEdit.Add_Click({ & $enterEdit })

    $hBtnSave.Add_Click({
        if (Save-MarkdownDoc -File $docFile -Text $hEditor.Text) {
            & $renderDoc
            & $exitEdit
        }
    })

    $hBtnCancel.Add_Click({
        $hEditor.Text = Load-MarkdownDoc -File $docFile -Default $docDefault
        & $exitEdit
    })

    $hBtnClose.Add_Click({ $hWin.Close() })

    $hWin.ShowDialog() | Out-Null
}

function Show-InputDialog {
    param(
        [string]$Title   = "Eingabe",
        [string]$Prompt  = "Wert eingeben:",
        [string]$Default = ""
    )

    [xml]$IXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Height="180" Width="440"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI"
        Background="{DynamicResource AppBg}">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="$Prompt"
                   Foreground="{DynamicResource AppText}" Margin="0,0,0,8"/>
        <TextBox Grid.Row="1" x:Name="iText" Padding="6,5" FontSize="13"
                 Background="{DynamicResource AppCardBg}"
                 Foreground="{DynamicResource AppText}"
                 CaretBrush="{DynamicResource AppText}"
                 BorderBrush="{DynamicResource AppBorder}"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="iOk" Content="OK" Padding="20,6" Margin="0,0,8,0" IsDefault="True"/>
            <Button x:Name="iCancel" Content="Abbrechen" Padding="14,6" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $ir = New-Object System.Xml.XmlNodeReader($IXaml)
    $Script:InpWin = [System.Windows.Markup.XamlReader]::Load($ir)
    if ($Script:window) { $Script:InpWin.Owner = $Script:window }
    foreach ($k in @("AppBg","AppText","AppCardBg","AppBorder")) {
        try { $Script:InpWin.Resources[$k] = $Script:window.FindResource($k) } catch {}
    }
    $Script:InpText  = $Script:InpWin.FindName("iText")
    $Script:InpText.Text = $Default
    $Script:InpText.SelectAll()
    $Script:InpResult = $null
    $Script:InpWin.FindName("iOk").Add_Click({
        $Script:InpResult = $Script:InpText.Text
        $Script:InpWin.Close()
    })
    $Script:InpWin.FindName("iCancel").Add_Click({
        $Script:InpResult = $null
        $Script:InpWin.Close()
    })
    $Script:InpText.Focus() | Out-Null
    $Script:InpWin.ShowDialog() | Out-Null
    return $Script:InpResult
}

# ---------------------------------------------------------------------------
# Hilfe-Hub (mehrere .md-Dateien aus src/help/)
# ---------------------------------------------------------------------------

function HelpHub-Render {
    if (-not $Script:HelpHubCurrentFile -or -not (Test-Path $Script:HelpHubCurrentFile)) {
        $Script:HelpHubViewer.Document = New-Object System.Windows.Documents.FlowDocument
        $Script:HelpHubEditor.Text     = ""
        $Script:HelpHubTitle.Text      = "Kein Dokument ausgewaehlt"
        return
    }
    $txt = Get-Content $Script:HelpHubCurrentFile -Raw -Encoding UTF8
    if ($null -eq $txt) { $txt = "" }
    $Script:HelpHubViewer.Document = Convert-MarkdownToFlowDocument -Text $txt
    $Script:HelpHubEditor.Text     = $txt
    $Script:HelpHubTitle.Text      = [System.IO.Path]::GetFileNameWithoutExtension($Script:HelpHubCurrentFile)
}

function HelpHub-RefreshList {
    param([string]$SelectFile = "")
    $docs = Get-HelpDocs
    $filter = ""
    if ($Script:HelpHubSearch) { $filter = $Script:HelpHubSearch.Text }
    if ($filter) {
        $docs = @($docs | Where-Object { $_.Name -match [regex]::Escape($filter) })
    }
    $Script:HelpHubDocs = $docs
    $Script:HelpHubList.ItemsSource = $docs
    if (-not $SelectFile -and $Script:HelpHubCurrentFile) { $SelectFile = $Script:HelpHubCurrentFile }
    $sel = $null
    if ($SelectFile) {
        $sel = $docs | Where-Object { $_.File -eq $SelectFile } | Select-Object -First 1
    }
    if (-not $sel) { $sel = $docs | Select-Object -First 1 }
    if ($sel) {
        $Script:HelpHubCurrentFile = $sel.File
        $Script:HelpHubList.SelectedItem = $sel
    } else {
        $Script:HelpHubCurrentFile = $null
    }
    HelpHub-Render
}

function HelpHub-EnterEdit {
    $Script:HelpHubIsEditing       = $true
    $Script:HelpHubViewBorder.Visibility = "Collapsed"
    $Script:HelpHubEditor.Visibility     = "Visible"
    $Script:HelpHubBtnEdit.Visibility    = "Collapsed"
    $Script:HelpHubBtnSave.Visibility    = "Visible"
    $Script:HelpHubBtnCancel.Visibility  = "Visible"
    $Script:HelpHubHint.Text             = "Bearbeiten - Markdown wird beim Speichern wieder formatiert dargestellt."
    $Script:HelpHubEditor.Focus() | Out-Null
}

function HelpHub-ExitEdit {
    $Script:HelpHubIsEditing       = $false
    $Script:HelpHubEditor.Visibility     = "Collapsed"
    $Script:HelpHubViewBorder.Visibility = "Visible"
    $Script:HelpHubBtnEdit.Visibility    = "Visible"
    $Script:HelpHubBtnSave.Visibility    = "Collapsed"
    $Script:HelpHubBtnCancel.Visibility  = "Collapsed"
    $Script:HelpHubHint.Text             = "Lese-Modus - klicke auf 'Bearbeiten', um den Text zu aendern."
}

function Show-HelpHubDialog {
    Initialize-HelpDocs

    [xml]$HXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hilfe - JC Dashboard"
        Height="680" Width="1040"
        WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI"
        Background="{DynamicResource AppBg}">

    <Window.Resources>
        <Style x:Key="HBtn" TargetType="Button">
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
        <Style x:Key="HSideBtn" TargetType="Button" BasedOn="{StaticResource HBtn}">
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>
        <Style x:Key="DocItem" TargetType="ListBoxItem">
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Foreground" Value="{DynamicResource AppText}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="db" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="db" Property="Background" Value="{DynamicResource AppCardBg}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="db" Property="Background" Value="#1E6DB5"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="260"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Grid.Row="0"
                Background="{DynamicResource AppCardBg}"
                BorderBrush="{DynamicResource AppBorder}" BorderThickness="1"
                CornerRadius="4" Padding="10" Margin="0,0,12,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Text="Dokumente"
                           FontWeight="SemiBold" FontSize="14"
                           Foreground="{DynamicResource AppTextStrong}" Margin="2,0,0,8"/>

                <TextBox Grid.Row="1" x:Name="hSearch" Padding="6,5" Margin="0,0,0,8"
                         Background="{DynamicResource AppBg}"
                         Foreground="{DynamicResource AppText}"
                         CaretBrush="{DynamicResource AppText}"
                         BorderBrush="{DynamicResource AppBorder}"
                         ToolTip="Dokumente durchsuchen"/>

                <ListBox Grid.Row="2" x:Name="hList"
                         Background="Transparent"
                         BorderThickness="0"
                         ItemContainerStyle="{StaticResource DocItem}"
                         ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                         ScrollViewer.VerticalScrollBarVisibility="Auto"
                         DisplayMemberPath="Name"/>

                <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,0">
                    <Button x:Name="hBtnNew"    Content="+ Neu"
                            Style="{StaticResource HSideBtn}" Background="#16A34A"
                            ToolTip="Neues Hilfe-Dokument anlegen"/>
                    <Button x:Name="hBtnRename" Content="Umbenennen"
                            Style="{StaticResource HSideBtn}" Background="#1E6DB5"
                            Margin="6,0,0,0" ToolTip="Aktuelles Dokument umbenennen"/>
                    <Button x:Name="hBtnDelete" Content="Loeschen"
                            Style="{StaticResource HSideBtn}" Background="#B91C1C"
                            Margin="6,0,0,0" ToolTip="Aktuelles Dokument loeschen"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Content -->
        <Grid Grid.Column="1" Grid.Row="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock x:Name="hTitle" Text="Hilfe"
                               FontWeight="SemiBold" FontSize="16"
                               Foreground="{DynamicResource AppTextStrong}"/>
                    <TextBlock x:Name="hHint"
                               Text="Lese-Modus - klicke auf 'Bearbeiten', um den Text zu aendern."
                               Foreground="{DynamicResource AppTextMuted}" FontSize="11" Margin="0,3,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="hBtnEdit"   Content="Bearbeiten"
                            Style="{StaticResource HBtn}" Background="#1E6DB5"/>
                    <Button x:Name="hBtnSave"   Content="Speichern"
                            Style="{StaticResource HBtn}" Background="#16A34A"
                            Margin="8,0,0,0" Visibility="Collapsed"/>
                    <Button x:Name="hBtnCancel" Content="Abbrechen"
                            Style="{StaticResource HBtn}" Background="#94A3B8"
                            Margin="8,0,0,0" Visibility="Collapsed"/>
                </StackPanel>
            </Grid>

            <Border Grid.Row="1" x:Name="hViewBorder"
                    Background="{DynamicResource AppCardBg}"
                    BorderBrush="{DynamicResource AppBorder}" BorderThickness="1"
                    CornerRadius="4">
                <ScrollViewer VerticalScrollBarVisibility="Auto"
                              HorizontalScrollBarVisibility="Disabled" Padding="20,14">
                    <RichTextBox x:Name="hViewer" IsReadOnly="True"
                                 BorderThickness="0" Background="Transparent"
                                 IsDocumentEnabled="True"
                                 Padding="0" FontSize="13"
                                 Foreground="{DynamicResource DocText}"/>
                </ScrollViewer>
            </Border>

            <TextBox Grid.Row="1" x:Name="hEditor" Visibility="Collapsed"
                     AcceptsReturn="True" TextWrapping="Wrap"
                     VerticalScrollBarVisibility="Auto"
                     BorderBrush="{DynamicResource AppBorder}" BorderThickness="1"
                     Background="{DynamicResource AppCardBg}"
                     Foreground="{DynamicResource AppText}"
                     CaretBrush="{DynamicResource AppText}"
                     Padding="12,10"
                     FontFamily="Consolas" FontSize="12"/>
        </Grid>

        <!-- Footer -->
        <StackPanel Grid.Column="1" Grid.Row="1" HorizontalAlignment="Right"
                    Orientation="Horizontal" Margin="0,12,0,0">
            <Button x:Name="hBtnClose" Content="Schliessen"
                    Style="{StaticResource HBtn}" Background="#64748B" Padding="20,9"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $hr = New-Object System.Xml.XmlNodeReader($HXaml)
    $Script:HelpHubWin = [System.Windows.Markup.XamlReader]::Load($hr)
    $Script:HelpHubWin.Owner = $Script:window

    foreach ($k in @("AppBg","AppText","AppTextStrong","AppTextMuted","AppTextFaint",
                     "AppBorder","AppCardBg","DocText")) {
        $Script:HelpHubWin.Resources[$k] = $Script:window.FindResource($k)
    }

    $Script:HelpHubList       = $Script:HelpHubWin.FindName("hList")
    $Script:HelpHubSearch     = $Script:HelpHubWin.FindName("hSearch")
    $Script:HelpHubViewer     = $Script:HelpHubWin.FindName("hViewer")
    $Script:HelpHubViewBorder = $Script:HelpHubWin.FindName("hViewBorder")
    $Script:HelpHubEditor     = $Script:HelpHubWin.FindName("hEditor")
    $Script:HelpHubTitle      = $Script:HelpHubWin.FindName("hTitle")
    $Script:HelpHubHint       = $Script:HelpHubWin.FindName("hHint")
    $Script:HelpHubBtnEdit    = $Script:HelpHubWin.FindName("hBtnEdit")
    $Script:HelpHubBtnSave    = $Script:HelpHubWin.FindName("hBtnSave")
    $Script:HelpHubBtnCancel  = $Script:HelpHubWin.FindName("hBtnCancel")
    $Script:HelpHubBtnNew     = $Script:HelpHubWin.FindName("hBtnNew")
    $Script:HelpHubBtnRename  = $Script:HelpHubWin.FindName("hBtnRename")
    $Script:HelpHubBtnDelete  = $Script:HelpHubWin.FindName("hBtnDelete")
    $Script:HelpHubBtnClose   = $Script:HelpHubWin.FindName("hBtnClose")
    $Script:HelpHubIsEditing  = $false
    $Script:HelpHubCurrentFile = $null

    HelpHub-RefreshList

    $Script:HelpHubList.Add_SelectionChanged({
        $sel = $Script:HelpHubList.SelectedItem
        if (-not $sel) { return }
        if ($sel.File -eq $Script:HelpHubCurrentFile) { return }
        if ($Script:HelpHubIsEditing) {
            $ans = [System.Windows.MessageBox]::Show(
                "Aenderungen am aktuellen Dokument verwerfen und wechseln?",
                "Ungespeicherte Aenderungen",
                [System.Windows.MessageBoxButton]::OKCancel,
                [System.Windows.MessageBoxImage]::Question)
            if ($ans -ne "OK") {
                $prev = $Script:HelpHubDocs | Where-Object { $_.File -eq $Script:HelpHubCurrentFile } | Select-Object -First 1
                if ($prev) { $Script:HelpHubList.SelectedItem = $prev }
                return
            }
            HelpHub-ExitEdit
        }
        $Script:HelpHubCurrentFile = $sel.File
        HelpHub-Render
    })

    $Script:HelpHubSearch.Add_TextChanged({ HelpHub-RefreshList })

    $Script:HelpHubBtnEdit.Add_Click({
        if (-not $Script:HelpHubCurrentFile) { return }
        HelpHub-EnterEdit
    })

    $Script:HelpHubBtnSave.Add_Click({
        if (-not $Script:HelpHubCurrentFile) { return }
        if (Save-MarkdownDoc -File $Script:HelpHubCurrentFile -Text $Script:HelpHubEditor.Text) {
            HelpHub-Render
            HelpHub-ExitEdit
        }
    })

    $Script:HelpHubBtnCancel.Add_Click({
        HelpHub-Render
        HelpHub-ExitEdit
    })

    $Script:HelpHubBtnNew.Add_Click({
        $name = Show-InputDialog -Title "Neues Hilfe-Dokument" `
                                 -Prompt "Name (ohne .md):" `
                                 -Default "Neue Notiz"
        if (-not $name) { return }
        $name = $name.Trim()
        if (-not (Test-HelpDocName $name)) {
            [System.Windows.MessageBox]::Show("Ungueltiger Dateiname.","Hinweis",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $file = New-HelpDoc -Name $name
        if (-not $file) {
            [System.Windows.MessageBox]::Show("Dokument konnte nicht angelegt werden (Name evtl. schon vergeben).",
                "Hinweis",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        HelpHub-RefreshList -SelectFile $file
        HelpHub-EnterEdit
    })

    $Script:HelpHubBtnRename.Add_Click({
        if (-not $Script:HelpHubCurrentFile) { return }
        $old = [System.IO.Path]::GetFileNameWithoutExtension($Script:HelpHubCurrentFile)
        $name = Show-InputDialog -Title "Umbenennen" `
                                 -Prompt "Neuer Name (ohne .md):" `
                                 -Default $old
        if (-not $name) { return }
        $name = $name.Trim()
        if ($name -eq $old) { return }
        if (-not (Test-HelpDocName $name)) {
            [System.Windows.MessageBox]::Show("Ungueltiger Dateiname.","Hinweis",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $new = Rename-HelpDoc -OldPath $Script:HelpHubCurrentFile -NewName $name
        if (-not $new) {
            [System.Windows.MessageBox]::Show("Umbenennen fehlgeschlagen (Name evtl. schon vergeben).",
                "Hinweis",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $Script:HelpHubCurrentFile = $new
        HelpHub-RefreshList -SelectFile $new
    })

    $Script:HelpHubBtnDelete.Add_Click({
        if (-not $Script:HelpHubCurrentFile) { return }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Script:HelpHubCurrentFile)
        $ans = [System.Windows.MessageBox]::Show(
            "Dokument '$name' wirklich loeschen?",
            "Loeschen bestaetigen",
            [System.Windows.MessageBoxButton]::OKCancel,
            [System.Windows.MessageBoxImage]::Warning)
        if ($ans -ne "OK") { return }
        if (Remove-HelpDoc -Path $Script:HelpHubCurrentFile) {
            $Script:HelpHubCurrentFile = $null
            if ($Script:HelpHubIsEditing) { HelpHub-ExitEdit }
            HelpHub-RefreshList
        }
    })

    $Script:HelpHubBtnClose.Add_Click({ $Script:HelpHubWin.Close() })

    $Script:HelpHubWin.ShowDialog() | Out-Null
}

function Show-HelpDialog { Show-HelpHubDialog }

function Show-ChangesDialog {
    Show-MarkdownDocDialog `
        -Title    "Aenderungsprotokoll - JC Dashboard" `
        -Subtitle "JC Dashboard - Aenderungen" `
        -File     $Script:ChangesFile `
        -Default  $Script:DefaultChangesText
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
        Height="780" Width="860"
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
                    <ComboBoxItem Content="windows"/>
                    <ComboBoxItem Content="program"/>
                    <ComboBoxItem Content="folder"/>
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
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <TextBox x:Name="txtIcon"
                                 Style="{StaticResource Txt}" MaxLength="4"
                                 VerticalAlignment="Top"/>
                        <TextBlock Style="{StaticResource Lbl}"
                                   Text="Bild (optional, .ico/.png/.jpg)"
                                   Margin="0,8,0,3"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Grid.Column="0" x:Name="txtIconPath"
                                     Style="{StaticResource Txt}"
                                     IsReadOnly="True" Background="#F1F5F9"/>
                            <Button Grid.Column="1" x:Name="btnIconBrowse"
                                    Content="..."
                                    Style="{StaticResource Btn}" Background="#64748B"
                                    Margin="6,0,0,0" Padding="10,6"
                                    ToolTip="Bild auswaehlen"/>
                            <Button Grid.Column="2" x:Name="btnIconClear"
                                    Content="X"
                                    Style="{StaticResource Btn}" Background="#94A3B8"
                                    Margin="6,0,0,0" Padding="10,6"
                                    ToolTip="Bild entfernen"/>
                        </Grid>
                        <TextBlock FontSize="11" Foreground="#94A3B8"
                                   Margin="0,4,0,0" TextWrapping="Wrap"
                                   Text="Bild ueberschreibt das Emoji. Relative Pfade beziehen sich auf den Skript-Ordner."/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Margin="16,0,4,0"
                                VerticalAlignment="Top">
                        <Border BorderBrush="#CBD5E1" BorderThickness="1"
                                CornerRadius="8" Padding="10,8" Background="#F8FAFC">
                            <StackPanel>
                                <ContentControl x:Name="iconPreviewHost"
                                                HorizontalAlignment="Center"
                                                Width="48" Height="48"/>
                                <TextBlock Text="Live-Vorschau"
                                           FontSize="11" Foreground="#94A3B8"
                                           HorizontalAlignment="Center"
                                           Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Grid>

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

                <TextBlock Style="{StaticResource Lbl}" Text="Bilder"/>
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
                <TextBlock Style="{StaticResource Lbl}" Text="Bildbeschreibung (fuer ausgewaehltes Bild)"/>
                <TextBox x:Name="txtImageCaption" Style="{StaticResource Txt}"
                         IsEnabled="False"/>

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
    $sTxtIcoPath = $sWin.FindName("txtIconPath")
    $sBtnIcoBrw  = $sWin.FindName("btnIconBrowse")
    $sBtnIcoClr  = $sWin.FindName("btnIconClear")
    $sIcoPrev   = $sWin.FindName("iconPreviewHost")
    $sTxtTags   = $sWin.FindName("txtTags")
    $sTxtVer    = $sWin.FindName("txtVersion")
    $sDpDate    = $sWin.FindName("dpVersionDate")
    $sTxtDoc    = $sWin.FindName("txtDoc")
    $sLstImg    = $sWin.FindName("lstImages")
    $sBtnAddImg = $sWin.FindName("btnAddImage")
    $sBtnRmImg  = $sWin.FindName("btnRemoveImage")
    $sTxtImgCap = $sWin.FindName("txtImageCaption")
    $sTxtDsc    = $sWin.FindName("txtDesc")

    $Script:dlgTools  = [System.Collections.ArrayList]@()
    foreach ($t in (Load-Tools)) { $Script:dlgTools.Add($t) | Out-Null }
    $Script:dlgSelIdx = -1
    $Script:dlgImages = [System.Collections.ArrayList]@()

    function S-RefreshList {
        $sLst.Items.Clear()
        foreach ($t in $Script:dlgTools) {
            $sLst.Items.Add("$($t.icon)  $($t.name)") | Out-Null
        }
    }

    function S-RefreshImageList {
        $sLstImg.Items.Clear()
        foreach ($img in $Script:dlgImages) {
            $name = [System.IO.Path]::GetFileName($img.path)
            $cap  = if ($img.caption) { "  -  $($img.caption)" } else { "" }
            $sLstImg.Items.Add("$name$cap") | Out-Null
        }
    }

    # Live-Vorschau-Badge im Einstellungen-Dialog aktualisieren.
    function S-UpdateIconPreview {
        $typeKey = if ($sCmbTyp.SelectedItem) { [string]$sCmbTyp.SelectedItem.Content } else { "powershell" }
        $previewTool = [PSCustomObject]@{
            icon     = $sTxtIco.Text
            iconPath = $sTxtIcoPath.Text
            type     = $typeKey
        }
        $sIcoPrev.Content = New-ToolBadge -Tool $previewTool -Size 48
    }

    function S-UpdatePathLabel {
        $t = if ($sCmbTyp.SelectedItem) { [string]$sCmbTyp.SelectedItem.Content } else { "powershell" }
        $sLblPath.Text = switch ($t) {
            "hta"     { "Pfad zur .hta"          }
            "web"     { "URL"                    }
            "windows" { "Pfad zur .msc / .exe"   }
            "program" { "Pfad zur .exe / .lnk"   }
            "folder"  { "Pfad zum Ordner"         }
            default   { "Pfad zur .ps1"           }
        }
        $sBtnBrw.Visibility = if ($t -eq "web" -or $t -eq "folder") { "Collapsed" } else { "Visible" }
    }

    function S-ClearForm {
        $sTxtNam.Text          = ""
        $sTxtPth.Text          = ""
        $sTxtIco.Text          = ""
        $sTxtIcoPath.Text      = ""
        $sTxtTags.Text         = ""
        $sTxtVer.Text          = ""
        $sDpDate.SelectedDate  = $null
        $sTxtDoc.Text          = ""
        $sTxtDsc.Text          = ""
        $Script:dlgImages.Clear()
        $sLstImg.Items.Clear()
        $sTxtImgCap.Text       = ""
        $sTxtImgCap.IsEnabled  = $false
        $sCmbTyp.SelectedIndex = 0
        S-UpdatePathLabel
        $Script:dlgSelIdx      = -1
        $sLst.SelectedIndex    = -1
    }

    function S-LoadForm {
        param($t)
        $sTxtNam.Text     = $t.name
        $sTxtIco.Text     = $t.icon
        $sTxtIcoPath.Text = if ($t.iconPath) { [string]$t.iconPath } else { "" }
        $sTxtDsc.Text     = $t.description
        $sTxtTags.Text = if ($t.tags) { $t.tags -join ", " } else { "" }
        $sTxtVer.Text  = if ($t.version) { $t.version } else { "" }
        $sTxtDoc.Text  = if ($t.doc)     { $t.doc     } else { "" }
        if ($t.versionDate -and $t.versionDate -ne "") {
            try { $sDpDate.SelectedDate = [datetime]::Parse($t.versionDate) } catch { $sDpDate.SelectedDate = $null }
        } else { $sDpDate.SelectedDate = $null }
        $Script:dlgImages.Clear()
        if ($t.images) {
            foreach ($img in $t.images) {
                if ($img -is [string]) {
                    $Script:dlgImages.Add([PSCustomObject]@{ path = $img; caption = "" }) | Out-Null
                } else {
                    $cap = if ($img.caption) { $img.caption } else { "" }
                    $Script:dlgImages.Add([PSCustomObject]@{ path = $img.path; caption = $cap }) | Out-Null
                }
            }
        }
        S-RefreshImageList
        $sTxtImgCap.Text      = ""
        $sTxtImgCap.IsEnabled = $false
        $typeStr = if ($t.type) { [string]$t.type } else { "powershell" }
        $sCmbTyp.SelectedItem = ($sCmbTyp.Items | Where-Object { $_.Content -eq $typeStr } | Select-Object -First 1)
        if (-not $sCmbTyp.SelectedItem) { $sCmbTyp.SelectedIndex = 0 }
        S-UpdatePathLabel
        $sTxtPth.Text = if ($t.type -eq "web") { $t.url } else { $t.path }
    }

    $sCmbTyp.Add_SelectionChanged({ S-UpdatePathLabel; S-UpdateIconPreview })
    $sTxtIco.Add_TextChanged({ S-UpdateIconPreview })
    $sTxtIcoPath.Add_TextChanged({ S-UpdateIconPreview })

    $sBtnIcoBrw.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Bilder/Icons (*.ico;*.png;*.jpg;*.jpeg;*.bmp)|*.ico;*.png;*.jpg;*.jpeg;*.bmp|Alle Dateien (*.*)|*.*"
        $ofd.Title  = "Bild fuer Tool-Badge auswaehlen"
        if ($ofd.ShowDialog() -eq "OK") { $sTxtIcoPath.Text = $ofd.FileName }
    })

    $sBtnIcoClr.Add_Click({ $sTxtIcoPath.Text = "" })

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
        $bt = if ($sCmbTyp.SelectedItem) { [string]$sCmbTyp.SelectedItem.Content } else { "powershell" }
        $ofd.Filter = switch ($bt) {
            "hta"     { "HTA-Dateien (*.hta)|*.hta|Alle Dateien (*.*)|*.*" }
            "windows" { "MMC-Snap-Ins (*.msc)|*.msc|Ausfuehrbare Dateien (*.exe)|*.exe|Alle Dateien (*.*)|*.*" }
            "program" { "Ausfuehrbare Dateien (*.exe)|*.exe|Verkuepfungen (*.lnk)|*.lnk|Alle Dateien (*.*)|*.*" }
            default   { "PowerShell-Skripte (*.ps1)|*.ps1|Alle Dateien (*.*)|*.*" }
        }
        $ofd.Title = "Datei auswaehlen"
        if ($ofd.ShowDialog() -eq "OK") { $sTxtPth.Text = $ofd.FileName }
    })

    $sBtnAddImg.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Bilder (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif"
        $ofd.Title  = "Bild auswaehlen"
        if ($ofd.ShowDialog() -eq "OK") {
            $Script:dlgImages.Add(
                [PSCustomObject]@{ path = $ofd.FileName; caption = "" }) | Out-Null
            S-RefreshImageList
            $sLstImg.SelectedIndex = $Script:dlgImages.Count - 1
        }
    })

    $sBtnRmImg.Add_Click({
        $i = $sLstImg.SelectedIndex
        if ($i -ge 0 -and $i -lt $Script:dlgImages.Count) {
            $Script:dlgImages.RemoveAt($i)
            S-RefreshImageList
            $sTxtImgCap.Text      = ""
            $sTxtImgCap.IsEnabled = $false
        }
    })

    $sLstImg.Add_SelectionChanged({
        $i = $sLstImg.SelectedIndex
        if ($i -ge 0 -and $i -lt $Script:dlgImages.Count) {
            $sTxtImgCap.Text      = $Script:dlgImages[$i].caption
            $sTxtImgCap.IsEnabled = $true
        } else {
            $sTxtImgCap.Text      = ""
            $sTxtImgCap.IsEnabled = $false
        }
    })

    $sTxtImgCap.Add_LostFocus({
        $i = $sLstImg.SelectedIndex
        if ($i -ge 0 -and $i -lt $Script:dlgImages.Count) {
            $Script:dlgImages[$i].caption = $sTxtImgCap.Text
            S-RefreshImageList
            $sLstImg.SelectedIndex = $i
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
        $type = if ($sCmbTyp.SelectedItem) { [string]$sCmbTyp.SelectedItem.Content } else { "powershell" }
        $id   = ($sTxtNam.Text.ToLower() -replace '[^a-z0-9]', '_')

        $rawTags = ($sTxtTags.Text -split ',') |
                   ForEach-Object { $_.Trim() } |
                   Where-Object   { $_ -ne "" }

        # Aktuelle Caption uebernehmen falls Fokus noch im Textfeld
        $iSel = $sLstImg.SelectedIndex
        if ($iSel -ge 0 -and $iSel -lt $Script:dlgImages.Count) {
            $Script:dlgImages[$iSel].caption = $sTxtImgCap.Text
        }
        $rawImgs = [System.Collections.ArrayList]@()
        foreach ($img in $Script:dlgImages) {
            $rawImgs.Add([PSCustomObject]@{
                path    = $img.path
                caption = $img.caption
            }) | Out-Null
        }

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
        $iconPathTrim = $sTxtIcoPath.Text.Trim()
        if ($iconPathTrim) {
            $entry | Add-Member -MemberType NoteProperty -Name "iconPath" -Value $iconPathTrim
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
    S-UpdateIconPreview
    $sWin.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
# Event-Handler
# ---------------------------------------------------------------------------

$Script:modeList.Add_SelectionChanged({
    if ($Script:IgnoreModeChange) { return }
    $item = $Script:modeList.SelectedItem
    if (-not $item) { return }
    Build-ToolList -Mode $item.Tag
})

$Script:toolList.Add_SelectionChanged({
    $item = $Script:toolList.SelectedItem
    if (-not $item -or -not $item.Tag) { return }
    Show-ToolDetails -Tool $item.Tag
})

$Script:txtSearch.Add_TextChanged({
    if ($Script:CurrentMode -ne "all") { return }
    Refresh-ToolListFiltered
})

$Script:btnTagToggle.Add_Click({
    $Script:TagPanelOpen = -not $Script:TagPanelOpen
    if ($Script:TagPanelOpen) {
        $Script:tagChipBorder.Visibility = "Visible"
        $Script:txtTagToggle.Text = "$([char]0x25BE) Tags filtern"
    } else {
        $Script:tagChipBorder.Visibility = "Collapsed"
        $Script:txtTagToggle.Text = "$([char]0x25B8) Tags filtern"
    }
})

$Script:btnStartTool.Add_Click({
    $tool = $args[0].Tag
    if ($tool) { Start-Tool $tool }
})

$Script:btnHome.Add_Click({
    $Script:IgnoreModeChange = $true
    $Script:modeList.SelectedIndex = -1
    $Script:IgnoreModeChange = $false
    $Script:toolList.Items.Clear()
    $Script:col2Header.Visibility   = "Visible"
    $Script:searchBorder.Visibility = "Collapsed"
    $Script:col2Title.Text          = "STARTSEITE"
    Add-EmptyStateItem "Waehle links 'Zuletzt verwendet' oder 'Alle Tools'."
    Show-WelcomePane
})

$Script:btnHelp.Add_Click({ Show-HelpDialog })

$Script:btnChanges.Add_Click({ Show-ChangesDialog })

$Script:btnHelpMini.Add_Click({ Show-HelpDialog })

$Script:btnChangesMini.Add_Click({ Show-ChangesDialog })

$Script:btnSettings.Add_Click({
    Show-SettingsDialog
    Build-ToolList -Mode $Script:CurrentMode
})

$Script:btnTheme.Add_Click({
    $next = if ($Script:CurrentTheme -eq "dark") { "light" } else { "dark" }
    Apply-Theme -Mode $next
    $prefs = Load-Prefs
    $prefs["theme"] = $next
    Save-Prefs $prefs
})

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------

$savedTheme = (Load-Prefs)["theme"]
if (-not $savedTheme) { $savedTheme = "light" }
Apply-Theme -Mode $savedTheme

$Script:modeList.SelectedIndex = 0
$Script:window.ShowDialog() | Out-Null
