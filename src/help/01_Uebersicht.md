# JC Dashboard - Hilfe

Das **JC Dashboard** ist deine zentrale Anlaufstelle fuer wichtige Werkzeuge. Es buendelt PowerShell-Skripte, HTA-Anwendungen und Webseiten in einer aufgeraeumten Oberflaeche und merkt sich, welche Tools du zuletzt verwendet hast.

## Aufbau der Oberflaeche
- **Linke Spalte:** Auswahl des Modus - **Startseite**, **Zuletzt verwendet**, **Alle Tools (A-Z)** und **Einstellungen**.
- **Mittlere Spalte:** Liste der Tools im aktuellen Modus. In "Alle Tools" steht zusaetzlich ein Suchfeld zur Verfuegung.
- **Rechte Spalte:** Detail-Ansicht mit Tags, Version, Dokumentation, Bildern und dem **Starten**-Button.

## Ein Tool anlegen oder bearbeiten
1. Links auf **Einstellungen** klicken.
2. **+ Neu** waehlen oder ein bestehendes Tool aus der Liste markieren.
3. Felder ausfuellen - Pflicht sind: Name, Typ und Pfad bzw. URL.
4. Optional Tags, Version, Versionsdatum, Bilder und Doku ergaenzen.
5. Mit **Speichern** uebernehmen - die Tools-Datei wird automatisch aktualisiert.

## Markdown in den Doku-Feldern
Die Doku-Felder der Tools (und diese Hilfe) unterstuetzen einfaches Markdown:
- `# Ueberschrift 1` und `## Ueberschrift 2`
- **Fettdruck** mit `**Text**`
- Listen mit `-` oder `*`
- Verweise mit `[Text](https://example.com)`

## Tipp: Windows-Pfade in JSON
Backslashes muessen in JSON-Dateien doppelt geschrieben werden:

`C:\\Programme\\MeinTool\\start.exe`

## Tipp: Werkseinstellungen
Im Einstellungs-Dialog setzt der Button **Werkseinstellungen** alle Tools auf die mitgelieferten Beispiele zurueck - praktisch zum Ausprobieren und Testen.
