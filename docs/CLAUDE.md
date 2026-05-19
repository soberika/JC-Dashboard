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
6. **Kein Emoji und keine HTML-Entities** direkt in PowerShell-Strings — nur in XAML-Here-Strings (`@'...'@`), wo XamlReader sie verarbeitet.
7. **Alle UI-Variablen mit `$Script:` prefixen** (`$Script:window`, `$Script:toolList` etc.), damit sie aus WPF-Event-Handlern und Funktionen heraus erreichbar sind.
8. **Keine Closures via `.GetNewClosure()`** für WPF-Click-Handler. Stattdessen Tool-Daten im `.Tag` des Buttons speichern, per `$args[0].Tag` abrufen.
9. **JSON-Pfade**: Windows-Backslashes in `tools.json` müssen escaped sein (`C:\\Pfad\\Datei`). Der Einstellungen-Dialog macht das automatisch via `ConvertTo-Json`.
10. Nach größeren Änderungen eine kurze Zusammenfassung schreiben.

---

## Ordnerstruktur

```
JC-Dashboard/
├── src/
│   ├── dashboard.ps1          # Haupt-GUI (XAML + Code-Behind)
│   ├── tools.json             # Tool-Konfiguration (wird von der GUI gelesen/geschrieben)
│   ├── usage.json             # Nutzungs-Historie für "Zuletzt verwendet"
│   ├── help.md                # Inhalt des Hilfe-Dialogs (in der App editierbar)
│   ├── changes.md             # Aenderungsprotokoll (in der App editierbar)
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
- **Startseite-Button** oben in Col 1 zeigt die Welcome-Pane mit Kurzbeschreibung und Hilfe-Button
- Sidebar lädt Tools dynamisch aus `src/tools.json`
- **PowerShell-Tools** (`type: "powershell"`): starten per `Start-Process`, absoluter oder relativer Pfad; Fehlermeldung wenn Datei nicht gefunden
- **HTA-Tools** (`type: "hta"`): starten ebenfalls per `Start-Process` (Windows öffnet sie mit `mshta.exe`)
- **Web-Tools** (`type: "web"`): öffnen URL im Standard-Browser des Systems per `Start-Process`
- **Zuletzt verwendet**: zeigt die fünf zuletzt gestarteten Tools, persistiert in `usage.json`
- **Alle Tools (A-Z)** mit Suchfeld über Name, Tags, Beschreibung und Doku
- **Detail-Pane**: Tags, Version + Versionsdatum, Markdown-Doku, Bilder-Galerie mit Lightbox-Zoom
- **Einstellungen-Dialog**: Tools hinzufügen / bearbeiten / löschen inkl. Tags, Version, Doku, Bildern → speichert sofort in `tools.json` + aktualisiert Sidebar
- **Hilfe-Dialog** (Pop-up): rendert `help.md` als Markdown; **Bearbeiten/Speichern** direkt in der App, Inhalt persistiert in `src/help.md`
- **Werkseinstellungen-Reset**: setzt `tools.json` auf Beispiel-Tools zurück (mit Bestätigungsdialog)
- Fehlermeldungen (Datei nicht gefunden, JSON-Fehler, Runtime-Fehler) als MessageBox

### Bekannte Einschränkungen
- Web-Tools öffnen im Standard-Browser (kein eingebetteter Browser). Ein WebView2-Upgrade wurde versucht, aber verworfen da zu komplex für den aktuellen Einsatzzweck.
- Icons in der Sidebar kommen aus dem `icon`-Feld in `tools.json` (Emoji). Emoji werden in PS-Strings nicht direkt geschrieben — nur aus JSON gelesen und im WPF-TextBlock angezeigt.

### tools.json Schema
```json
{
  "tools": [
    {
      "id":          "eindeutiger_bezeichner",
      "name":        "Anzeigename",
      "type":        "powershell",
      "path":        "C:\\absoluter\\oder\\relativer\\Pfad.ps1",
      "icon":        "?",
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
      "icon":        "?",
      "description": "Eine Webanwendung"
    }
  ]
}
```

### Markdown-Dokumente (`help.md`, `changes.md`)
- Beide liegen unter `src/` und werden vom generischen `Show-MarkdownDocDialog` gelesen/geschrieben.
- `help.md` → Hilfe-Dialog (Button **„❔ Hilfe öffnen"** auf der Startseite).
- `changes.md` → Änderungsprotokoll-Dialog (Button **„📝 Änderungen"** auf der Startseite).
- Falls eine Datei fehlt, wird sie aus `$Script:DefaultHelpText` bzw. `$Script:DefaultChangesText` in `dashboard.ps1` neu angelegt.
- Im Dialog: **Bearbeiten** öffnet einen Markdown-Editor, **Speichern** persistiert und rendert neu.

---

## Token-Spar-Regel
- Immer nur die für die Aufgabe nötigen Dateien lesen.
- Bei Änderungen > 50 Zeilen: erst Plan (max. 8 Sätze) schreiben und auf Bestätigung warten.
