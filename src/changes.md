# Aenderungsprotokoll

Hier landen alle wichtigen Aenderungen am JC Dashboard.
Eintraege koennen ueber den Knopf **Bearbeiten** direkt in der App erweitert oder im Texteditor in `src/changes.md` gepflegt werden.

## 2026-05-20 (Tool-Badge-Fix)

**Symptom:** Tool-Badges zeigten nur den farbigen Kreis — weder Emoji noch optionales Bild wurden dargestellt (Tool-Liste und Live-Vorschau im Einstellungen-Dialog).

**Ursache:** `[string]$OverrideIcon = $null` wird durch PowerShells Typ-Cast stillschweigend zu `""`. Da `"" -ne $null` in PowerShell `$true` ergibt, griff der Override-Zweig bei jedem Aufruf — auch ohne explizites `-OverrideIcon`. Dadurch wurde `$Tool.icon` nie ausgelesen.

**Fixes:**
- `$null -ne $OverrideIcon` → `[string]::IsNullOrEmpty($OverrideIcon)` (ebenso fuer `$OverrideIconPath`)
- Emoji-Text jetzt programmatisch per `$tb.Text = $emoji` statt als XAML-Attribut — verhindert Encoding-Verlust von Surrogate-Pairs durch den `XmlReader`
- Kleiner `DropShadowEffect` auf dem Badge-TextBlock fuer besseren Kontrast auf hellen Kreisfarben

## 2026-05-19 (Hilfe-Bibliothek)
- **Hilfe-Hub** mit Sidebar: Hilfe-Dialog verwaltet jetzt beliebig viele Markdown-Dokumente unter `src/help/` statt nur einer einzelnen Datei.
- **Sidebar-Aktionen**: **+ Neu**, **Umbenennen** und **Loeschen** direkt im Hilfe-Dialog; Suchfeld filtert die Dokumentliste live.
- **Reihenfolge** ueber Dateinamen-Praefix steuerbar (`01_`, `02_`, ...).
- **Migration**: vorhandene `src/help.md` wird beim ersten Oeffnen automatisch nach `src/help/01_Uebersicht.md` uebernommen.
- Beispiel-Docs ausgeliefert: `01_Uebersicht`, `02_Hilfe-Bibliothek`, `03_Eigene Notizen`.

## 2026-05-19
- **Dark-Mode-Switch** unten in Col1: schaltet zwischen Light- und Dark-Palette um, Praeferenz wird in `prefs.json` gespeichert.
- **Fix Dark-Mode**: `Apply-Theme` rief faelschlich `SolidColorBrush(Color)` mit einem `SolidColorBrush`-Argument auf - jetzt wird das vom `BrushConverter` zurueckgegebene Brush direkt verwendet.
- **Einstellungen** als Icon-Button in die untere Bottom-Reihe von Col1 verschoben (zusammen mit Hilfe und Aenderungsprotokoll).
- **Startseite-Button** in der linken Spalte hinzugefuegt.
- **Welcome-Pane** mit Kurzbeschreibung und Hilfe-Zugang ueberarbeitet.
- **Hilfe-Dialog** (Pop-up) mit Markdown-Anzeige und Inline-Editor eingefuehrt; Inhalt liegt in `src/help.md`.
- **Aenderungsprotokoll-Dialog** ergaenzt - diese Datei (`src/changes.md`) ist nun ebenfalls in der App editierbar.
- **README** und **CLAUDE.md** auf den aktuellen Funktionsstand gebracht.

## 2026-05-19 (frueher)
- **Bilder-Galerie**: Lightbox-Zoom mit Klick auf ein Bild, optionale Bildbeschreibung pro Eintrag.
- **3-Spalten-Inspector-Layout** (Konzept B): Modus | Tool-Liste | Detail-Pane.
- **Pipeline-Enumerierung** in `Build-ToolList` und Settings-Init gefixt.

## 2026-05-18
- **Werkseinstellungen-Reset**: setzt `tools.json` per Knopfdruck auf Beispiel-Tools zurueck.
- **ListBox-Layout** in der Sidebar repariert.
- **WebView2** aus dem Projekt entfernt - Web-Tools oeffnen wieder im Standardbrowser.
- **tools.json**: Schema um `tags`, `version`, `versionDate`, `doc` und `images` erweitert.

## Format-Tipp
Neue Eintraege bitte mit Datum (`## YYYY-MM-DD`) ueberschreiben.
Markdown-Listen mit `-` oder `*`, **Fettdruck** mit `**...**`, Links mit `[Text](https://...)`.
