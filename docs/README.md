# JC-Dashboard

**Zentrale Steuerzentrale für Prozesse und Tools**  
Eine einfache, konfigurierbare WPF-GUI, die bestehende Anwendungen und Skripte zentral startet und verwaltet — ohne sie neu programmieren zu müssen.

---

## Ziel

Viele kleine Tools und Prozesse (PowerShell-Skripte, HTA-Anwendungen, Web-Apps) sollen über **eine übersichtliche Oberfläche** gestartet und verwaltet werden können. Neue Tools sollen **nur noch über die Einstellungen** hinzugefügt werden — ohne Code zu ändern.

Das Dashboard dient als **Launcher und zentrale Übersicht**, nicht als Ersatz für die bestehenden Tools.

---

## Features

- **3-Spalten-Layout**: Modus-Auswahl, Tool-Liste, Detail-Pane
- **Startseite-Button** oben links mit Willkommens-Pane und Hilfe-Zugang
- **Zuletzt verwendet** zeigt die fünf zuletzt gestarteten Tools (persistiert in `usage.json`)
- **Alle Tools (A-Z)** mit Suchfeld über Name, Tags, Beschreibung und Doku
- **PowerShell-** und **HTA-Tools** starten per `Start-Process`; Fehlermeldung wenn die Datei nicht gefunden wird
- **Web-Tools** öffnen die URL im Standard-Browser des Systems
- **Detail-Ansicht** mit Tags, Version, Markdown-Doku und Bilder-Galerie (Klick = Lightbox)
- **Einstellungen-Dialog**: Tools hinzufügen, bearbeiten, löschen — inkl. Tags, Version, Doku, Bildern
- **Hilfe-Dialog** mit gerendertem Markdown, direkt in der App **bearbeitbar und speicherbar** (`src/help.md`)
- **Änderungsprotokoll-Dialog** (`src/changes.md`), ebenfalls in der App editierbar
- **Werkseinstellungen**: setzt alle Tools auf Beispiel-Einträge zurück (mit Bestätigungsdialog)
- Konfiguration komplett über `src/tools.json` — kein Code-Änderung nötig

---

## Technologie

- **WPF** (PowerShell 5.1, keine externen Abhängigkeiten)
- Konfigurierbar über `tools.json` + Einstellungen-Dialog

---

## Schnellstart

```powershell
# Rechtsklick auf Start-Dashboard.ps1 → "Mit PowerShell ausführen"
src\Start-Dashboard.ps1
```

Oder direkt in PowerShell:

```powershell
& ".\src\Start-Dashboard.ps1"
```

---

## tools.json

Tools werden in `src/tools.json` gespeichert. Das Format:

```json
{
  "tools": [
    {
      "id":          "mein_tool",
      "name":        "Mein Tool",
      "type":        "powershell",
      "path":        "C:\\Pfad\\zum\\Skript.ps1",
      "icon":        "?",
      "description": "Kurzbeschreibung",
      "tags":        ["Demo"],
      "version":     "1.0.0",
      "versionDate": "2026-01-15",
      "doc":         "# Markdown-Doku\n\nUnterstuetzt **Fett**, Listen, Links."
    },
    {
      "id":          "meine_webapp",
      "name":        "Meine Web-App",
      "type":        "web",
      "url":         "https://example.com/",
      "icon":        "?",
      "description": "Eine Webanwendung"
    }
  ]
}
```

> **Hinweis:** Windows-Pfade in JSON benötigen doppelte Backslashes: `C:\\Ordner\\Datei.ps1`  
> Der Einstellungen-Dialog übernimmt das automatisch.

---

## Hilfe & Änderungsprotokoll (`help.md`, `changes.md`)

Beide Inhalte liegen als Markdown-Dateien neben der `dashboard.ps1` und können auf zwei Arten gepflegt werden:

- direkt im Texteditor öffnen und speichern, **oder**
- in der App: Welcome-Pane → **Hilfe öffnen** bzw. **Änderungen** → **Bearbeiten** → Text ändern → **Speichern**.

Unterstützt wird einfaches Markdown (`# Überschrift`, `**fett**`, Listen, `[Link](https://...)`).

---

## Ordnerstruktur

```
JC-Dashboard/
├── src/
│   ├── dashboard.ps1        # Haupt-GUI
│   ├── tools.json           # Tool-Konfiguration
│   ├── usage.json           # Historie für "Zuletzt verwendet"
│   ├── help.md              # Inhalt des Hilfe-Dialogs (editierbar in der App)
│   ├── changes.md           # Aenderungsprotokoll (editierbar in der App)
│   └── Start-Dashboard.ps1  # Starter
├── assets/                  # Bilder, Screenshots
├── docs/
│   ├── README.md
│   └── CLAUDE.md            # Regeln für KI-gestützte Weiterentwicklung
└── .gitignore
```
