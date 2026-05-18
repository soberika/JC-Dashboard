# CLAUDE.md – Regeln für Claude Code (Prozess-Dashboard)

**Projektziel:**
Eine **konfigurierbare WPF-GUI** als zentrale Steuerzentrale für verschiedene Tools und Prozesse (PowerShell-Skripte + Web-Apps). Neue Tools sollen **nur noch über die Oberfläche** hinzugefügt werden können — ohne Code zu ändern.

**Wichtige Regeln:**

1. **Immer zuerst diese Datei lesen** (CLAUDE.md) + die aktuelle `tools.json` Struktur.
2. **Niemals** das gesamte Repository auf einmal analysieren. Nur die relevanten Dateien lesen.
3. **Single-Maintainer**: Der Code muss einfach und gut lesbar bleiben. Keine übertriebene Komplexität.
4. **Konfigurierbarkeit hat Priorität**: Neue Tools kommen über einen Einstellungen-Dialog + `tools.json`. Nicht hardcodiert.
5. **PowerShell 5.1 kompatibel** halten.
6. **WebView2** für Web-Tools nutzen (nicht externen Browser, außer explizit gewünscht).
7. **Gutes, modernes Design** (ähnlich dem aktuellen Zahllauf-Prototypen).
8. Nach größeren Änderungen immer eine kurze Zusammenfassung schreiben.

**Aktueller Stand:**
- Die GUI soll Tools aus `tools.json` laden
- PowerShell-Tools werden mit `Start-Process` gestartet
- Web-Tools werden per WebView2 eingebettet
- Einstellungen-Dialog zum Hinzufügen/Bearbeiten/Löschen von Tools

**Token-Spar-Regel:**
- Immer nur die Dateien lesen, die für die aktuelle Aufgabe relevant sind.
- Bei großen Änderungen zuerst einen Plan (max. 8 Sätze) schreiben und abwarten.