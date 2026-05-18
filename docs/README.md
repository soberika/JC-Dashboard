# JC-Dashboard

**Zentrale Steuerzentrale für Prozesse und Tools**  
Eine einfache, konfigurierbare WPF-GUI, die bestehende Anwendungen und Skripte zentral startet und verwaltet — ohne sie neu programmieren zu müssen.

---

## Ziel

Viele kleine Tools und Prozesse (PowerShell-Skripte, HTA-Anwendungen, Web-Apps) sollen über **eine übersichtliche Oberfläche** gestartet und verwaltet werden können. Neue Tools sollen **nur noch über die Einstellungen** hinzugefügt werden — ohne Code zu ändern.

Das Dashboard dient als **Launcher und zentrale Übersicht**, nicht als Ersatz für die bestehenden Tools.

---

## Features

- Sidebar mit allen konfigurierten Tools (Name, Typ, Icon)
- **PowerShell-Tools** (`.hta`, `.ps1`, `.exe` usw.) starten in einem eigenen Fenster per `Start-Process`; Fehlermeldung wenn die Datei nicht gefunden wird
- **Web-Tools** öffnen die URL im Standard-Browser des Systems
- **Einstellungen-Dialog**: Tools hinzufügen, bearbeiten, löschen — Änderungen sind sofort in der Sidebar sichtbar
- **Werkseinstellungen**: setzt alle Tools auf zwei Beispiel-Einträge zurück (mit Bestätigungsdialog)
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
      "path":        "C:\\Pfad\\zum\\Skript.hta",
      "icon":        "?",
      "description": "Kurzbeschreibung"
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

> **Hinweis:** Windows-Pfade in JSON benötigen doppelte Backslashes: `C:\\Ordner\\Datei.hta`  
> Der Einstellungen-Dialog übernimmt das automatisch.

---

## Ordnerstruktur

```
JC-Dashboard/
├── src/
│   ├── dashboard.ps1        # Haupt-GUI
│   ├── tools.json           # Tool-Konfiguration
│   └── Start-Dashboard.ps1  # Starter
├── docs/
│   ├── README.md
│   └── CLAUDE.md            # Regeln für KI-gestützte Weiterentwicklung
└── .gitignore
```
