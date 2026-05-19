# Aenderungsprotokoll

Hier landen alle wichtigen Aenderungen am JC Dashboard.
Eintraege koennen ueber den Knopf **Bearbeiten** direkt in der App erweitert oder im Texteditor in `src/changes.md` gepflegt werden.

## 2026-05-19
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
