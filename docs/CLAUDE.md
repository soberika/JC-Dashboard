# CLAUDE.md – Regeln für Claude Code (Prozess-Dashboard)

**Projektziel:**
Eine **konfigurierbare WPF-GUI** als zentrale Steuerzentrale für verschiedene Tools und Prozesse (PowerShell-Skripte + Web-Apps). Neue Tools sollen **nur noch über die Oberfläche** hinzugefügt werden können — ohne Code zu ändern.

---

## Wichtige Regeln

1. **Immer zuerst diese Datei lesen** + `src/tools.json` — nie blind drauflosschreiben.
2. **Nur relevante Dateien lesen** — kein vollständiges Repo-Scan.
3. **Single-Maintainer**: Code muss einfach und lesbar bleiben. Keine unnötige Abstraktion.
4. **Konfigurierbarkeit hat Priorität**: Neue Tools kommen über den Einstellungen-Dialog + `tools.json`. Nie hardcoded.
5. **PowerShell 5.1 kompatibel** halten. Kein PS 7-only Syntax.
6. **Emojis nie als XAML-Attribut-Wert via String-Interpolation** — `XmlReader` verschluckt Surrogate-Pairs (z.B. 🌐, 💻). TextBlock stattdessen ohne `Text=`-Attribut im XAML anlegen und danach `$tb.Text = $emoji` programmatisch setzen.
7. **`[string]$null`-Falle**: PowerShell castet `[string]$null` stillschweigend zu `""`. Bei optionalen String-Parametern deshalb immer `[string]::IsNullOrEmpty()` statt `$null -ne` prüfen — sonst greifen leere Override-Werte, obwohl kein Override übergeben wurde.
8. **Alle UI-Variablen mit `$Script:` prefixen** (`$Script:window`, `$Script:toolList` etc.), damit sie aus WPF-Event-Handlern und Funktionen heraus erreichbar sind.
9. **Keine Closures via `.GetNewClosure()`** für WPF-Click-Handler. Stattdessen Tool-Daten im `.Tag` des Buttons speichern, per `$args[0].Tag` abrufen.
10. **JSON-Pfade**: Windows-Backslashes in `tools.json` müssen escaped sein (`C:\\Pfad\\Datei`). Der Einstellungen-Dialog macht das automatisch via `ConvertTo-Json`.
11. Nach größeren Änderungen eine kurze Zusammenfassung schreiben.

---

## Ordnerstruktur

```
JC-Dashboard/
├── src/
│   ├── dashboard.ps1          # Haupt-GUI (XAML + Code-Behind)
│   ├── tools.json             # Tool-Konfiguration (wird von der GUI gelesen/geschrieben)
│   ├── usage.json             # Nutzungs-Historie für "Zuletzt verwendet"
│   ├── help/                  # Hilfe-Bibliothek: beliebig viele .md-Dateien (in der App editierbar)
│   ├── changes.md             # Aenderungsprotokoll (in der App editierbar)
│   ├── prefs.json             # Lokale Praeferenzen (Theme etc.) - in .gitignore
│   └── Start-Dashboard.ps1    # Einstiegs-Skript → Rechtsklick "Mit PowerShell ausführen"
├── assets/                    # Bilder, Icons (optional)
├── docs/
│   ├── README.md
│   └── CLAUDE.md
└── .gitignore
```

---

## Aktueller Stand (Branch: main)

### Was funktioniert
- GUI startet via `src/Start-Dashboard.ps1` (Rechtsklick → Mit PowerShell ausführen)
- **3-Spalten-Layout** (Inspector-Stil): Modus (Col 1) → Tool-Liste (Col 2) → Detail-Ansicht (Col 3)
- **Startseite-Button** oben in Col 1 zeigt die Welcome-Pane mit Kurzbeschreibung und Hilfe-Buttons
- **Bottom-Icon-Bar in Col 1**: kompakte Icons für ⚙ Einstellungen, ❔ Hilfe, 📝 Änderungsprotokoll und ☾/☀ Theme-Toggle (mit Tooltips)
- Sidebar lädt Tools dynamisch aus `src/tools.json`
- **PowerShell-Tools** (`type: "powershell"`): starten per `Start-Process`, absoluter oder relativer Pfad; Fehlermeldung wenn Datei nicht gefunden
- **HTA-Tools** (`type: "hta"`): starten ebenfalls per `Start-Process` (Windows öffnet sie mit `mshta.exe`)
- **Web-Tools** (`type: "web"`): öffnen URL im Standard-Browser des Systems per `Start-Process`
- **Zuletzt verwendet**: zeigt die fünf zuletzt gestarteten Tools, persistiert in `usage.json`
- **Alle Tools (A-Z)** mit Suchfeld über Name, Tags, Beschreibung und Doku
- **Detail-Pane**: Tags, Version + Versionsdatum, Markdown-Doku, Bilder-Galerie mit Lightbox-Zoom
- **Tool-Badges**: farbige Kreise mit Emoji (aus `tools.json`-Feld `icon`) oder optionalem Bild (`iconPath`). Badge-Größe skaliert mit Kontext (Tool-Liste 40px, Detail-Header 54px, Einstellungen-Vorschau 48px). Hover-Effekt (Glow + 1.08× Scale).
- **Einstellungen-Dialog**: Tools hinzufügen / bearbeiten / löschen inkl. Tags, Version, Doku, Bildern, Icon-Emoji und optionalem Bild-Pfad → speichert sofort in `tools.json` + aktualisiert Sidebar
- **Hilfe-Dialog** (Pop-up, Hub-Layout): linke Sidebar listet alle `.md`-Dateien aus `src/help/`, rechts die Lese-/Bearbeiten-Ansicht. **Neu / Umbenennen / Loeschen** direkt in der Sidebar, **Bearbeiten/Speichern** persistiert die jeweilige Datei. Reihenfolge per Dateinamen-Praefix (`01_`, `02_`).
- **Änderungsprotokoll-Dialog**: gleicher generischer `Show-MarkdownDocDialog`, Inhalt in `src/changes.md`
- **Dark-Mode-Switch**: ☾/☀-Icon in der Bottom-Bar; Brushes via `DynamicResource`, Apply-Theme tauscht zur Laufzeit, Auswahl in `prefs.json` persistiert
- **Werkseinstellungen-Reset**: setzt `tools.json` auf Beispiel-Tools zurück (mit Bestätigungsdialog)
- Fehlermeldungen (Datei nicht gefunden, JSON-Fehler, Runtime-Fehler) als MessageBox

### Bekannte Einschränkungen
- Web-Tools öffnen im Standard-Browser (kein eingebetteter Browser). Ein WebView2-Upgrade wurde versucht, aber verworfen da zu komplex für den aktuellen Einsatzzweck.
- WPF rendert `Segoe UI Emoji` nur monochrom (keine Color-Emoji). Emojis erscheinen als weiße Silhouetten auf dem farbigen Kreis — lesbar, aber nicht bunt.

### tools.json Schema
```json
{
  "tools": [
    {
      "id":          "eindeutiger_bezeichner",
      "name":        "Anzeigename",
      "type":        "powershell",
      "path":        "C:\\absoluter\\oder\\relativer\\Pfad.ps1",
      "icon":        "🛠️",
      "iconPath":    "assets\\mein_icon.png",
      "description": "Kurzbeschreibung",
      "tags":        ["Demo", "Info"],
      "version":     "1.0.0",
      "versionDate": "2026-01-15",
      "doc":         "# Markdown-Doku\n\nUnterstuetzt **Fett**, Listen, Links.",
      "images":      [
        { "path": "assets\\screenshot.png", "caption": "Hauptansicht" }
      ]
    },
    {
      "id":          "web_tool",
      "name":        "Web Tool",
      "type":        "web",
      "url":         "https://example.com/",
      "icon":        "🌐",
      "description": "Eine Webanwendung"
    }
  ]
}
```

> `icon`: Emoji-Zeichen aus `tools.json` (direkt aus JSON gelesen, nie im PS-Code als Literal).  
> `iconPath`: Optionaler Pfad zu einer Bilddatei (.png/.jpg/.ico) — wird kreisrund geclippt. Überschreibt das Emoji. Absolut oder relativ zum `src/`-Verzeichnis.

### Theme (Light / Dark)
- Toggle ueber das Mond-/Sonne-Icon unten in Col1.
- Brushes liegen als `DynamicResource` in `Window.Resources`; `Apply-Theme` tauscht sie zur Laufzeit aus.
- Palettes: `$Script:LightPalette` / `$Script:DarkPalette` in `dashboard.ps1`.
- Dynamisch erzeugte Inhalte (Markdown-FlowDocument, Tag-Chips, Bilder-Galerie) lesen die Brushes via `FindResource` - bei Theme-Wechsel rendert `Apply-Theme` die aktive Detail-Ansicht neu.
- Praeferenz wird in `src/prefs.json` gespeichert (in `.gitignore`).
- Col1/Col2 bleiben absichtlich immer dunkel; getauscht wird der Detail-Bereich (Col3) und der Hilfe-/Aenderungen-Dialog. Der Einstellungen-Dialog bleibt hell.

### Hilfe-Bibliothek (`src/help/*.md`)
- Ordner `src/help/` enthaelt beliebig viele Markdown-Dateien. Dateiname (ohne `.md`) = Anzeigename.
- Sortierung alphabetisch - Reihenfolge per Praefix steuern (`01_Uebersicht.md`, `02_Hilfe-Bibliothek.md`, ...).
- Hilfe-Dialog (`Show-HelpHubDialog`): zweispaltiges Layout mit Doc-Liste links (Suchfeld, **+ Neu / Umbenennen / Loeschen**) und Reader/Editor rechts. **Bearbeiten / Speichern / Abbrechen** wirken auf das ausgewaehlte Dokument.
- Migration: fehlt `src/help/`, wird der Ordner beim Oeffnen angelegt. Wenn er leer ist und eine alte `src/help.md` existiert, wird deren Inhalt als `01_Uebersicht.md` uebernommen, sonst `$Script:DefaultHelpText`.
- Aenderungsprotokoll (`src/changes.md`) bleibt unveraendert: einzelnes Dokument, generischer `Show-MarkdownDocDialog`.

---

## Token-Spar-Regel
- Immer nur die für die Aufgabe nötigen Dateien lesen.
- Bei Änderungen > 50 Zeilen: erst Plan (max. 8 Sätze) schreiben und auf Bestätigung warten.
