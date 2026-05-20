# JC-Dashboard – Icon/Badge Bug-Analyse

**Branch:** `claude/jc-dashboard-dev-RwfSi`
**Letzter Commit:** `629c3cb` ("fix(ui): Tool-Badge - Z-Order und Image-Clip korrigieren")
**Symptom:** Tool-Badges zeigen NUR den farbigen Kreis. Weder Emoji (z. B. 🌐, 💻, 🖔️) noch optionales Bild werden über/im Kreis dargestellt. Betrifft die Tool-Liste UND die Live-Vorschau im Einstellungen-Dialog.

---

## 1. Fakten aus dem Repo

- `src/tools.json` enthält für jedes Tool ein `icon`-Feld mit gültigem Emoji (`🌐`, `🖔️`, `🪟`, `💻`, `🍔`, `🧰`, `📚`).
- **Kein einziges Tool hat ein `iconPath`-Feld in der JSON.** D. h. der gesamte Bild-Zweig wird in `New-ToolBadge` gar nicht durchlaufen – `$bitmap` ist immer `$null` und es geht in den Emoji-Fallback.
- Der Emoji-Fallback baut einen `<TextBlock>` mit `Foreground="White"`, `FontSize=Round($Size*0.55)`, `FontFamily="Segoe UI Emoji"`, ZIndex=10. Der Kreis ist eine `<Ellipse>` mit ZIndex=0.
- Die Live-Vorschau im Einstellungen-Dialog (Bild 1) zeigt denselben Bug → es ist KEIN Datenproblem, sondern ein reiner Renderbug in `New-ToolBadge`.

→ **Der Bug liegt NICHT in der Logik „Bild vs. Emoji" und NICHT in `iconPath`. Der Bug ist, dass der Emoji-TextBlock unsichtbar bleibt.**

---

## 2. Wo es konkret hakt

`src/dashboard.ps1`, Funktion `New-ToolBadge` (Zeilen 888–1008).

Aktuell wird die XAML so zusammengebaut (Zeilen 918–925, 931–952):

```xml
<Grid Width="$Size" Height="$Size" ...>
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
    <TextBlock x:Name="badgeText" Text="$escEmoji"
               Foreground="White" FontWeight="SemiBold"
               FontSize="$fontSize" FontFamily="Segoe UI Emoji"
               HorizontalAlignment="Center" VerticalAlignment="Center"
               TextAlignment="Center" IsHitTestVisible="False"
               Panel.ZIndex="10"/>
</Grid>
```

`$escEmoji` kommt aus `[System.Security.SecurityElement]::Escape($emoji)` – das ist in Ordnung.

---

## 3. Verdächtige Hypothesen (sortiert nach Wahrscheinlichkeit)

### H1 (sehr wahrscheinlich): Encoding-Verlust beim XAML-Inlining

Der entscheidende Code-Pfad:

```powershell
$escEmoji = [System.Security.SecurityElement]::Escape($emoji)  # Emoji bleibt als Surrogate-Pair erhalten
$contentXaml = @"
<TextBlock ... Text="$escEmoji" ... />
"@
# ...
$xaml = @"
<Grid ...>
    ...
    $contentXaml
</Grid>
"@

$reader    = New-Object System.IO.StringReader($xaml)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
$root      = [System.Windows.Markup.XamlReader]::Load($xmlReader)
```

**Problem:** `[System.Xml.XmlReader]::Create($stringReader)` läuft mit Default-Settings. Wenn das Surrogate-Pair eines Emojis in den XmlReader fließt, kann `XmlReader` je nach .NET-Version `CheckCharacters=true` verwenden und High-Codepoint-Zeichen wegwerfen oder als Whitespace interpretieren. Insbesondere `🖔️` (Variation Selector U+FE0F) und ZWJ-Sequenzen sind anfällig.

**Symptom passt zu H1:** TextBlock existiert, ist aber leer ⇒ unsichtbar ⇒ nur Kreis sichtbar.

### H2 (möglich): Emoji wird gerendert, aber Glyph hat keine Farbinformation und keinen sichtbaren Schwarz-Weiß-Kontrast

WPF rendert „Segoe UI Emoji" **monochrom** (keine Color-Emoji-Unterstützung in Standard-WPF!). Mit `Foreground="White"` auf weißem Stroke kann das gut versteckt sein, aber auf dem farbigen Kreis-Fill sollten weiße Glyph-Outlines sichtbar sein. Trotzdem: bestimmte Emojis (z. B. 🌐) haben kaum monochrome Form und können wirklich unsichtbar werden. **Aber:** „?" als Fallback wäre dann sichtbar – wir sehen aber keine Fallbacks → H2 erklärt das Bild nur teilweise.

### H3 (wahrscheinlich, sekundär): `iconPath` wird nie gespeichert

Beim Anklicken von „Bild auswählen" im Settings-Dialog wird `txtIconPath` zwar befüllt, aber wenn beim Speichern (Save-Logik im Settings-Dialog) `iconPath` nicht ins PSCustomObject übernommen wird, landet es nicht in `tools.json`. Das erklärt, warum ein hinzugefügtes Bild keinen Effekt zeigt – aber NICHT, warum Emojis nicht sichtbar sind.

→ **Bug 3 separat checken**, ist aber sekundär.

### H4 (unwahrscheinlich, aber leicht auszuschließen): ZIndex/Effect-Quirk

Der vorherige Commit erwähnt einen „WPF-Quirk" mit DropShadowEffect und ZIndex. Der Fix wurde mit `Panel.ZIndex` auf beiden Children eingebaut. Das sollte funktionieren. Trotzdem: Sicherheitshalber testen, ob es ohne `DropShadowEffect` auf der Ellipse klappt.

---

## 4. Konkrete nächste Schritte für Claude Code

### Schritt A: Beweis sichern – ist der TextBlock wirklich leer?

In `New-ToolBadge` direkt nach `$root = ...XamlReader::Load(...)`:

```powershell
$tb = $root.FindName("badgeText")
if ($tb) {
    Write-Host "[Badge-Debug] tool=$($Tool.name) emojiIn=$emoji textOut='$($tb.Text)' len=$($tb.Text.Length)"
} elseif (-not $bitmap) {
    Write-Host "[Badge-Debug] tool=$($Tool.name) NO badgeText found!"
}
```

Damit sehen wir nach `Start-Dashboard.ps1` in der Konsole sofort, ob die Emoji-Strings beim Eintreffen im TextBlock noch da sind. Wenn `textOut` leer/verstümmelt → H1 bestätigt.

### Schritt B (wenn H1 bestätigt): XAML-Parser robust machen

**Empfohlene Lösung:** TextBlock nicht via inline-XAML bauen, sondern wie das `Image`-Objekt programmatisch befüllen:

```powershell
if ($bitmap) {
    $contentXaml = '<Image x:Name="badgeImage" Stretch="Uniform" IsHitTestVisible="False" Panel.ZIndex="10"/>'
} else {
    # KEIN Emoji-Text in XAML-Attribut, sondern leerer TextBlock - Text wird programmatisch gesetzt.
    $contentXaml = @"
<TextBlock x:Name="badgeText"
           Foreground="White" FontWeight="SemiBold"
           FontSize="$fontSize" FontFamily="Segoe UI Emoji"
           HorizontalAlignment="Center" VerticalAlignment="Center"
           TextAlignment="Center" IsHitTestVisible="False"
           Panel.ZIndex="10"/>
"@
}

# ... XamlReader.Load(...) wie bisher ...

if ($bitmap) {
    # bestehender Bild-Code
} else {
    $tb = $root.FindName("badgeText")
    if ($tb) { $tb.Text = $emoji }   # direkt setzen, KEIN XAML-Escaping
}
```

Das umgeht Encoding-Probleme komplett, weil der Emoji-String nie mehr durch einen XML-Parser läuft.

**Alternativ** (wenn man am inline-XAML festhalten will): `XmlReaderSettings` mit `CheckCharacters=$false` verwenden:

```powershell
$settings = New-Object System.Xml.XmlReaderSettings
$settings.CheckCharacters = $false
$xmlReader = [System.Xml.XmlReader]::Create($reader, $settings)
```

### Schritt C: Color-Emoji-Problem entschärfen

WPF rendert nur monochrome Glyphs aus `Segoe UI Emoji`. Damit das auf farbigem Kreis besser sichtbar wird:

- `Foreground="White"` ist OK (besser als das Default-Schwarz auf Farbkreisen).
- Zusätzliche `Effect` mit kleinem `DropShadowEffect` (Schwarz, BlurRadius 2-3, ShadowDepth 0) auf dem TextBlock gibt der weißen Silhouette Kontrast und Lesbarkeit:

```xml
<TextBlock ...>
    <TextBlock.Effect>
        <DropShadowEffect BlurRadius="3" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </TextBlock.Effect>
</TextBlock>
```

### Schritt D: `iconPath` Save-Pfad prüfen

Datei: `src/dashboard.ps1`, im Settings-Dialog-Block (~Zeile 2300–2620). Suchen nach der Save-Funktion (`btnSave` oder `S-Save` oder ähnlichem) und sicherstellen, dass `iconPath = $sTxtIcoPath.Text` ins PSCustomObject übernommen wird. Aktuell deutet die `tools.json` (keine `iconPath`-Felder) darauf hin, dass das Feld beim Speichern verloren geht.

Symptom: Wenn man im Dialog ein Bild auswählt, sieht man es in der Live-Vorschau (sobald H1 gefixt ist), aber nach „Schließen" + erneutem Öffnen ist das Feld leer.

### Schritt E: Beispiel-Bild zum Manuel-Test bereitstellen

Lege im Repo ein winziges Test-PNG ab (z. B. `assets/test_icon.png`) und setze in `tools.json` für ein Tool versuchsweise:

```json
"iconPath": "..\\assets\\test_icon.png"
```

Damit kann der Bild-Pfad in `New-ToolBadge` und `Resolve-ToolIconPath` isoliert getestet werden, ohne erst durch den Settings-Dialog zu müssen.

---

## 5. Was am Code GUT ist und so bleiben sollte

- Die konditionale XAML-Bauweise (Image **oder** TextBlock, nicht beide mit Visibility) ist sauber.
- Die Clip-Berechnung für das Bild (Radius = (Size-5)/2, Center = Size/2) ist korrekt.
- `BitmapImage` mit `CacheOption=OnLoad` + `Freeze()` ist Best-Practice (Datei wird nicht gesperrt, Cross-Thread-safe).
- `Resolve-ToolIconPath` mit absolutem/relativem Pfad-Fallback ist robust.
- ZIndex auf beiden Children explizit gesetzt – defensive Programmierung gegen den WPF-DropShadow-Quirk.

---

## 6. Reihenfolge der Fixes (priorisiert)

1. **Sofort:** Debug-Log aus Schritt A einbauen → herausfinden, ob der TextBlock-Text leer ist.
2. **Hauptfix:** Schritt B (programmatisches Setzen von `TextBlock.Text`). Das ist *der* wahrscheinliche Fix für den Emoji-Bug.
3. **Lesbarkeit:** Schritt C (Schatten am Text).
4. **Bild-Workflow:** Schritt D (Save-Pfad für `iconPath`) und Schritt E (Test-Asset).
5. Nach Fix Debug-Logs aus Schritt A wieder entfernen.

---

## 7. Schnelles Sanity-Check-Skript für isolierten Test

Bevor du am Dashboard rumdokterst – ein minimales PS1 zum Testen, dass Emojis im TextBlock überhaupt rendern:

```powershell
Add-Type -AssemblyName PresentationFramework
$w = New-Object System.Windows.Window
$w.Width = 200; $w.Height = 200
$g = New-Object System.Windows.Controls.Grid
$g.Background = [System.Windows.Media.Brushes]::CornflowerBlue
$tb = New-Object System.Windows.Controls.TextBlock
$tb.Text = "🌐"
$tb.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI Emoji")
$tb.FontSize = 64
$tb.Foreground = [System.Windows.Media.Brushes]::White
$tb.HorizontalAlignment = "Center"
$tb.VerticalAlignment = "Center"
$g.Children.Add($tb) | Out-Null
$w.Content = $g
$w.ShowDialog() | Out-Null
```

Wenn das Globus-Emoji sichtbar ist (auch nur als weiße Silhouette), funktioniert die Font-Pipeline. Wenn nicht → tieferes Problem mit dem System.
