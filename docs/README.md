# Prozess-Dashboard

**Zentrale Steuerzentrale für Prozesse und Tools**  
Eine einfache, konfigurierbare WPF-GUI, die bestehende Anwendungen und Skripte zentral steuert — ohne sie neu programmieren zu müssen.

---

## Ziel

Viele kleine Tools und Prozesse (PowerShell-Skripte, HTA-Anwendungen, Web-Apps) sollen über **eine übersichtliche Oberfläche** gestartet und verwaltet werden können. Neue Tools sollen **nur noch über die Einstellungen** hinzugefügt werden können — ohne Code zu ändern.

Das Dashboard dient als **Launcher + zentrale Übersicht**, nicht als Ersatz für die bestehenden Tools.

---

## Features (aktuell im Prototyp)

- Sidebar mit allen verfügbaren Tools
- PowerShell-Tools (z. B. `Zahllauf.hta`) starten in einem eigenen Fenster
- Web-Tools (z. B. Mittagsbestellung) werden direkt im Dashboard über WebView2 eingebettet
- Einfacher Einstellungen-Dialog zum Hinzufügen, Bearbeiten und Löschen von Tools
- Tools werden in einer `tools.json` gespeichert → sofort sichtbar nach dem Speichern

---

## Technologie

- **WPF** (PowerShell 5.1)
- **WebView2** für Web-Tools
- Konfigurierbar über `tools.json` + Einstellungen-Dialog

---

## Schnellstart (nachdem der Prototyp steht)

```powershell
# Im Repository-Ordner ausführen
.\Start-Dashboard.ps1