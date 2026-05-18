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
│   ├── Start-Dashboard.ps1    # Einstiegs-Skript → Rechtsklick "Mit PowerShell ausführen"
│   └── modules/               # Platzhalter für spätere wiederverwendbare Funktionen
├── assets/                    # Bilder, Icons (optional)
├── docs/
│   ├── README.md
│   └── CLAUDE.md
└── .gitignore
```

---

## Aktueller Stand (Branch: claude/wpf-gui-prototype-3TqxC)

### Was funktioniert
- GUI startet via `src/Start-Dashboard.ps1` (Rechtsklick → Mit PowerShell ausführen)
- Sidebar lädt Tools dynamisch aus `src/tools.json`
- **PowerShell-Tools** (`type: "powershell"`): starten per `Start-Process`, absoluter oder relativer Pfad
- **Web-Tools** (`type: "web"`): öffnen URL im eingebetteten WPF-`WebBrowser`-Control (IE-Engine)
- **Einstellungen-Dialog**: Tools hinzufügen / bearbeiten / löschen → speichert sofort in `tools.json` + aktualisiert Sidebar
- Fehlermeldungen (Datei nicht gefunden, JSON-Fehler, Runtime-Fehler) als MessageBox

### Bekannte Einschränkungen
- WebBrowser-Control nutzt IE-Engine (kein modernes JS). WebView2-Upgrade ist geplant, aber noch nicht umgesetzt.
- Icons in der Sidebar kommen aus dem `icon`-Feld in `tools.json` (Emoji). Emoji werden in PS-Strings nicht direkt geschrieben — nur aus JSON gelesen und im WPF-TextBlock angezeigt.

### tools.json Schema
```json
{
  "tools": [
    {
      "id":          "eindeutiger_bezeichner",
      "name":        "Anzeigename",
      "type":        "powershell",
      "path":        "C:\\absoluter\\oder\\relativer\\Pfad.hta",
      "icon":        "⚙️",
      "description": "Kurzbeschreibung"
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

---

## Token-Spar-Regel
- Immer nur die für die Aufgabe nötigen Dateien lesen.
- Bei Änderungen > 50 Zeilen: erst Plan (max. 8 Sätze) schreiben und auf Bestätigung warten.
