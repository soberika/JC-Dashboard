#Requires -Version 5.1
<#
.SYNOPSIS
    Systemie - Das offizielle Maskottchen für Systembetreuer
    Landkreis Meißen | JC-Dashboard

.DESCRIPTION
    Startet ein kleines, freundliches, rahmenloses WPF-Fenster
    mit dem runden Roboter-Pinguin "Systemie".
    Immer oben, verschiebbar, minimierbar.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# === XAML für das süße Systemie-Fenster ===
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Systemie"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        Topmost="True"
        Width="220" Height="260"
        ResizeMode="NoResize"
        ShowInTaskbar="False">

    <Border Background="#003366"
            CornerRadius="20"
            BorderBrush="#4A90D9"
            BorderThickness="3"
            Padding="10">

        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">

            <!-- Systemie - Roboter-Pinguin -->
            <Grid Width="140" Height="160">

                <!-- Körper (rund, blau) -->
                <Ellipse Width="130" Height="130"
                         Fill="#003366"
                         Stroke="#1E3A5F"
                         StrokeThickness="2"
                         HorizontalAlignment="Center"
                         VerticalAlignment="Center"/>

                <!-- Weißer Bauch -->
                <Ellipse Width="90" Height="95"
                         Fill="White"
                         HorizontalAlignment="Center"
                         VerticalAlignment="Center"
                         Margin="0,25,0,0"/>

                <!-- Name "Systemie" -->
                <TextBlock Text="Systemie"
                           FontSize="18"
                           FontWeight="Bold"
                           Foreground="#003366"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"
                           Margin="0,55,0,0"/>

                <!-- Linkes Auge -->
                <Ellipse Width="22" Height="26"
                         Fill="White"
                         Stroke="#003366"
                         StrokeThickness="1.5"
                         HorizontalAlignment="Left"
                         VerticalAlignment="Top"
                         Margin="35,38,0,0"/>
                <Ellipse Width="10" Height="12"
                         Fill="#003366"
                         HorizontalAlignment="Left"
                         VerticalAlignment="Top"
                         Margin="42,45,0,0"/>

                <!-- Rechtes Auge -->
                <Ellipse Width="22" Height="26"
                         Fill="White"
                         Stroke="#003366"
                         StrokeThickness="1.5"
                         HorizontalAlignment="Right"
                         VerticalAlignment="Top"
                         Margin="0,38,35,0"/>
                <Ellipse Width="10" Height="12"
                         Fill="#003366"
                         HorizontalAlignment="Right"
                         VerticalAlignment="Top"
                         Margin="0,45,42,0"/>

                <!-- Schnabel (orange) -->
                <Polygon Points="70,72 85,82 70,92"
                         Fill="#FF8C00"
                         HorizontalAlignment="Center"
                         VerticalAlignment="Top"
                         Margin="0,65,0,0"/>

                <!-- Roboter-Antenne -->
                <Line X1="70" Y1="25" X2="70" Y2="8"
                      Stroke="#4A90D9" StrokeThickness="3"
                      HorizontalAlignment="Center"/>
                <Ellipse Width="12" Height="12"
                         Fill="#4A90D9"
                         HorizontalAlignment="Center"
                         VerticalAlignment="Top"
                         Margin="0,0,0,0"/>

                <!-- Linke mechanische Flosse -->
                <Rectangle Width="28" Height="14"
                           Fill="#1E3A5F"
                           HorizontalAlignment="Left"
                           VerticalAlignment="Center"
                           Margin="-8,0,0,0"
                           RenderTransformOrigin="0.5,0.5">
                    <Rectangle.RenderTransform>
                        <RotateTransform Angle="-25"/>
                    </Rectangle.RenderTransform>
                </Rectangle>

                <!-- Rechte mechanische Flosse -->
                <Rectangle Width="28" Height="14"
                           Fill="#1E3A5F"
                           HorizontalAlignment="Right"
                           VerticalAlignment="Center"
                           Margin="0,0,-8,0"
                           RenderTransformOrigin="0.5,0.5">
                    <Rectangle.RenderTransform>
                        <RotateTransform Angle="25"/>
                    </Rectangle.RenderTransform>
                </Rectangle>

            </Grid>

            <!-- Buttons -->
            <StackPanel Orientation="Horizontal"
                        HorizontalAlignment="Center"
                        Margin="0,12,0,0">

                <Button x:Name="btnHide"
                        Content="Hide"
                        Width="70"
                        Height="26"
                        Margin="4,0"
                        Background="#4A90D9"
                        Foreground="White"
                        FontWeight="SemiBold"
                        BorderThickness="0"/>

                <Button x:Name="btnTalk"
                        Content="Talk"
                        Width="70"
                        Height="26"
                        Margin="4,0"
                        Background="#FF8C00"
                        Foreground="White"
                        FontWeight="SemiBold"
                        BorderThickness="0"/>

            </StackPanel>

        </StackPanel>
    </Border>
</Window>
'@ 

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Event-Handler
$btnHide = $window.FindName("btnHide")
$btnTalk = $window.FindName("btnTalk")

$btnHide.Add_Click({
    $window.Hide()
})

$btnTalk.Add_Click({
    $messages = @(
        "Alles im grünen Bereich! ✅",
        "CPU läuft ruhig, RAM ist happy 😊",
        "Keine kritischen Events heute!",
        "Systemie sagt: Du machst das super!",
        "Patch-Status: Aktuell & sicher 🔒",
        "Möchtest du einen Kaffee? ☕"
    )
    $msg = $messages | Get-Random
    [System.Windows.MessageBox]::Show($msg, "Systemie", "OK", "Information")
})

# Fenster zentrieren + Drag & Drop ermöglichen
$window.WindowStartupLocation = "CenterScreen"

$window.Add_MouseLeftButtonDown({
    $window.DragMove()
})

# Fenster anzeigen
$window.ShowDialog() | Out-Null