#Requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$Script:ScriptDir = $PSScriptRoot
$Script:ToolsFile = Join-Path $Script:ScriptDir "tools.json"

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

        <Style x:Key="StartButton" TargetType="Button">
            <Setter Property="Background" Value="#1E6DB5"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="5">
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

        <Style x:Key="SettingsBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#7C9AB8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,11"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6" Margin="8,2">
                            <ContentPresenter Margin="{TemplateBinding Padding}"
                                              HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#162A3A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="240"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <DockPanel Grid.Column="0" Background="#0D1F2D">

            <!-- Kopfzeile -->
            <Border DockPanel.Dock="Top" Padding="20,18,20,14"
                    BorderBrush="#1A3347" BorderThickness="0,0,0,1">
                <StackPanel>
                    <TextBlock Text="JC Dashboard" Foreground="White"
                               FontSize="17" FontWeight="SemiBold"/>
                    <TextBlock Text="Tool-Steuerzentrale" Foreground="#4A6A85"
                               FontSize="11" Margin="0,3,0,0"/>
                </StackPanel>
            </Border>

            <!-- Einstellungen-Button unten -->
            <Border DockPanel.Dock="Bottom" BorderBrush="#1A3347" BorderThickness="0,1,0,0" Padding="0,6,0,6">
                <Button x:Name="btnSettings" Style="{StaticResource SettingsBtn}"
                        Content="&#9881;  Einstellungen"/>
            </Border>

            <!-- Tool-Liste (dynamisch befüllt) -->
            <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,10,0,0">
                <StackPanel x:Name="toolList"/>
            </ScrollViewer>

        </DockPanel>

        <!-- Inhaltsbereich -->
        <Grid Grid.Column="1" Background="#F0F4F8">

            <!-- Willkommens-Panel -->
            <StackPanel x:Name="welcomePanel"
                        HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock Text="&#128075;" FontSize="52" HorizontalAlignment="Center"/>
                <TextBlock Text="Willkommen im JC Dashboard"
                           FontSize="22" FontWeight="SemiBold"
                           Foreground="#1A3347" HorizontalAlignment="Center"
                           Margin="0,14,0,6"/>
                <TextBlock Text="W&#228;hle links ein Tool aus, um es zu starten."
                           Foreground="#607D8B" FontSize="14"
                           HorizontalAlignment="Center"/>
            </StackPanel>

            <!-- WebBrowser (f&#252;r Web-Tools) -->
            <WebBrowser x:Name="webBrowser" Visibility="Collapsed"/>

        </Grid>

    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader($MainXaml)
$Script:window       = [System.Windows.Markup.XamlReader]::Load($reader)

$Script:toolList     = $Script:window.FindName("toolList")
$Script:btnSettings  = $Script:window.FindName("btnSettings")
$Script:welcomePanel = $Script:window.FindName("welcomePanel")
$Script:webBrowser   = $Script:window.FindName("webBrowser")

# ---------------------------------------------------------------------------
# Tool starten
# ---------------------------------------------------------------------------

function Start-Tool {
    param($Tool)
    try {
        if ($Tool.type -eq "web") {
            $Script:welcomePanel.Visibility = "Collapsed"
            $Script:webBrowser.Visibility   = "Visible"
            $Script:webBrowser.Navigate($Tool.url)
            return
        }

        if ($Tool.type -eq "powershell") {
            $path = if ([System.IO.Path]::IsPathRooted($Tool.path)) {
                $Tool.path
            } else {
                Join-Path $Script:ScriptDir $Tool.path
            }
            if (Test-Path $path) {
                Start-Process $path
            } else {
                [System.Windows.MessageBox]::Show(
                    "Datei nicht gefunden:`n$path",
                    "Fehler",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show(
            "Fehler beim Starten von '$($Tool.name)':`n$_",
            "Fehler",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Sidebar aufbauen
# ---------------------------------------------------------------------------

function Build-Sidebar {
    $Script:toolList.Children.Clear()
    $tools = Load-Tools

    foreach ($tool in $tools) {
        $card             = New-Object System.Windows.Controls.Border
        $card.CornerRadius = "7"
        $card.Margin      = New-Object System.Windows.Thickness(8, 3, 8, 3)
        $card.Background  = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0x1A, 0x35, 0x4F)
        $card.Padding     = New-Object System.Windows.Thickness(12, 10, 12, 10)

        $grid = New-Object System.Windows.Controls.Grid
        $c1   = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c2   = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($c1)
        $grid.ColumnDefinitions.Add($c2)

        $info             = New-Object System.Windows.Controls.StackPanel
        $info.Orientation = "Vertical"

        $lblName            = New-Object System.Windows.Controls.TextBlock
        $lblName.Text       = "$($tool.icon)  $($tool.name)"
        $lblName.Foreground = "#E2EAF2"
        $lblName.FontSize   = 14
        $lblName.FontWeight = "SemiBold"

        $lblType            = New-Object System.Windows.Controls.TextBlock
        $lblType.Text       = if ($tool.type -eq "web") { "Webanwendung" } else { "PowerShell" }
        $lblType.Foreground = "#4A6A85"
        $lblType.FontSize   = 11
        $lblType.Margin     = New-Object System.Windows.Thickness(0, 2, 0, 0)

        $info.Children.Add($lblName) | Out-Null
        $info.Children.Add($lblType) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($info, 0)
        $grid.Children.Add($info) | Out-Null

        $btn                   = New-Object System.Windows.Controls.Button
        $btn.Content           = "Starten"
        $btn.Style             = $Script:window.FindResource("StartButton")
        $btn.VerticalAlignment = "Center"
        $btn.Tag               = $tool

        $btn.Add_Click({
            $t = $args[0].Tag
            Start-Tool $t
        })

        [System.Windows.Controls.Grid]::SetColumn($btn, 1)
        $grid.Children.Add($btn) | Out-Null

        $card.Child = $grid
        $Script:toolList.Children.Add($card) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Einstellungen-Dialog
# ---------------------------------------------------------------------------

function Show-SettingsDialog {

    [xml]$SXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Einstellungen &#8211; Tools verwalten"
        Height="560" Width="800"
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
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
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
        <DockPanel Grid.Column="0" Grid.Row="0">
            <TextBlock DockPanel.Dock="Top" Text="Tools" FontWeight="SemiBold"
                       FontSize="14" Foreground="#1A3347" Margin="0,0,0,8"/>
            <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
                <Button x:Name="btnNew"    Content="+ Neu"    Style="{StaticResource Btn}"
                        Background="#1E6DB5" Width="95"/>
                <Button x:Name="btnDelete" Content="L&#246;schen" Style="{StaticResource Btn}"
                        Background="#EF4444" Width="95" Margin="8,0,0,0"/>
            </StackPanel>
            <ListBox x:Name="lstTools" FontSize="13"
                     BorderBrush="#CBD5E1" BorderThickness="1"/>
        </DockPanel>

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
                    <ComboBoxItem Content="web"/>
                </ComboBox>

                <TextBlock Style="{StaticResource Lbl}" Text="Pfad (PowerShell) / URL (Web)"/>
                <TextBox x:Name="txtPath" Style="{StaticResource Txt}"/>

                <TextBlock Style="{StaticResource Lbl}" Text="Icon (Emoji)"/>
                <TextBox x:Name="txtIcon" Style="{StaticResource Txt}" MaxLength="4"/>

                <TextBlock Style="{StaticResource Lbl}" Text="Beschreibung (optional)"/>
                <TextBox x:Name="txtDesc" Style="{StaticResource Txt}"
                         Height="60" AcceptsReturn="True" TextWrapping="Wrap"/>

                <Button x:Name="btnSave" Content="&#128190;  Speichern"
                        Style="{StaticResource Btn}" Background="#16A34A"
                        HorizontalAlignment="Left" Margin="0,16,0,0"
                        FontSize="14" Padding="18,9"/>
            </StackPanel>
        </ScrollViewer>

        <!-- Schließen -->
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
    $sWin.Owner = $window

    $sLst    = $sWin.FindName("lstTools")
    $sBtnNew = $sWin.FindName("btnNew")
    $sBtnDel = $sWin.FindName("btnDelete")
    $sBtnSav = $sWin.FindName("btnSave")
    $sBtnCls = $sWin.FindName("btnClose")
    $sTxtNam = $sWin.FindName("txtName")
    $sCmbTyp = $sWin.FindName("cmbType")
    $sTxtPth = $sWin.FindName("txtPath")
    $sTxtIco = $sWin.FindName("txtIcon")
    $sTxtDsc = $sWin.FindName("txtDesc")

    $Script:dlgTools   = [System.Collections.ArrayList]@(Load-Tools)
    $Script:dlgSelIdx  = -1

    function S-RefreshList {
        $sLst.Items.Clear()
        foreach ($t in $Script:dlgTools) {
            $sLst.Items.Add("$($t.icon)  $($t.name)") | Out-Null
        }
    }

    function S-ClearForm {
        $sTxtNam.Text       = ""
        $sTxtPth.Text       = ""
        $sTxtIco.Text       = ""
        $sTxtDsc.Text       = ""
        $sCmbTyp.SelectedIndex = 0
        $Script:dlgSelIdx   = -1
        $sLst.SelectedIndex = -1
    }

    function S-LoadForm {
        param($t)
        $sTxtNam.Text = $t.name
        $sTxtIco.Text = $t.icon
        $sTxtDsc.Text = $t.description
        if ($t.type -eq "web") {
            $sCmbTyp.SelectedIndex = 1
            $sTxtPth.Text = $t.url
        } else {
            $sCmbTyp.SelectedIndex = 0
            $sTxtPth.Text = $t.path
        }
    }

    $sLst.Add_SelectionChanged({
        $i = $sLst.SelectedIndex
        if ($i -ge 0 -and $i -lt $Script:dlgTools.Count) {
            $Script:dlgSelIdx = $i
            S-LoadForm $Script:dlgTools[$i]
        }
    })

    $sBtnNew.Add_Click({ S-ClearForm })

    $sBtnDel.Add_Click({
        $i = $Script:dlgSelIdx
        if ($i -lt 0) { return }
        $res = [System.Windows.MessageBox]::Show(
            "Tool '$($Script:dlgTools[$i].name)' wirklich loeschen?",
            "Loeschen",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($res -eq "Yes") {
            $Script:dlgTools.RemoveAt($i)
            Save-Tools $Script:dlgTools
            Build-Sidebar
            S-RefreshList
            S-ClearForm
        }
    })

    $sBtnSav.Add_Click({
        if ([string]::IsNullOrWhiteSpace($sTxtNam.Text)) {
            [System.Windows.MessageBox]::Show("Bitte einen Namen eingeben.", "Fehler") | Out-Null
            return
        }

        $type = if ($sCmbTyp.SelectedIndex -eq 1) { "web" } else { "powershell" }
        $id   = ($sTxtNam.Text.ToLower() -replace '[^a-z0-9]', '_')

        $entry = [PSCustomObject]@{
            id          = $id
            name        = $sTxtNam.Text.Trim()
            type        = $type
            icon        = if ($sTxtIco.Text.Trim()) { $sTxtIco.Text.Trim() } else { "?" }
            description = $sTxtDsc.Text.Trim()
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
        Build-Sidebar
        S-RefreshList
    })

    $sBtnCls.Add_Click({ $sWin.Close() })

    S-RefreshList
    $sWin.ShowDialog() | Out-Null
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------

$Script:btnSettings.Add_Click({ Show-SettingsDialog })

Build-Sidebar

$Script:window.ShowDialog() | Out-Null
