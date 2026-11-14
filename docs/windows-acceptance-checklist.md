# OpenCommander auf Windows prüfen

Referenz ist die macOS-Abnahme von OpenCommander. Die Windows-Ergebnisse werden beim eigenen Durchlauf eingetragen. WebDAV gehört nicht zu diesem Durchlauf.

## Vorbereitung

- Windows-Version, OpenCommander-Build und Testsprache notieren. Für beide Cloud-Dienste die direkte Verbindung in OpenCommander verwenden.
- In Dropbox und Google Drive je einen eigenen Ordner mit demselben eindeutigen Namen erstellen, etwa `OpenCommander-QA-20261114-01`. Jeweils eine Datei namens `CrossMove.txt` anlegen. In Dropbox beispielsweise `Dropbox Original – Grüße 日本語`, in Google Drive `Drive Original – alte Fassung` speichern. Für Kopier-, Abbruch- und Belastungstests eigene Unterordner verwenden.
- Beide Dateien vor dem Test unabhängig von OpenCommander herunterladen und die SHA-256-Prüfsummen erfassen. Wenn der Anbieter die Datei-ID über seine API zugänglich macht, auch beide IDs notieren. Lokale Prüfsummen lassen sich mit `Get-FileHash -Algorithm SHA256 -LiteralPath '.\CrossMove.txt'` berechnen. Beim Prüfen dieselben Download-Verfahren verwenden.

## Dropbox → Google Drive bis Rückgängig

| Schritt | Erwartetes Ergebnis |
| --- | --- |
| 1. Eigenen Dropbox-Ordner links, eigenen Google-Drive-Ordner rechts öffnen. Links `CrossMove.txt` auswählen und «Verschieben» auslösen. | Beide Dateilisten öffnen im Hauptfenster. Der Konfliktdialog nennt die Datei und bietet die Konfliktoptionen an. |
| 2. Zuerst den Konfliktdialog abbrechen. Beide Anbieter separat prüfen. | Beide Originale sind unverändert. Die Historie meldet keinen erfolgreichen Verschiebevorgang. |
| 3. Erneut verschieben und «Ersetzen» wählen. Übertragungsanzeige öffnen. | Die Karte zeigt Quell- und Zielpfad, Phase und Dauer. 100 % erscheint erst nach Abschluss des gesamten Auftrags. |
| 4. Während des Auftrags «Pause» und anschliessend «Fortsetzen» wählen. | Dieselbe Karte bleibt bestehen. Ein Klick auf «Fortsetzen» legt keinen zweiten Auftrag an. |
| 5. Nach «Abgeschlossen» beide Anbieter ausserhalb der App aktualisieren. | Der öffentliche Quellname fehlt in Dropbox. Der Google-Drive-Zielname enthält exakt die Dropbox-Bytes. In der App steht genau ein erfolgreicher Verschiebeeintrag mit Uhrzeit und Rückgängig-Aktion. |
| 6. In genau diesem Historieneintrag «Rückgängig» wählen. Beide Anbieter erneut laden. | Die Historie meldet «Rückgängig». Beide Originalnamen und SHA-256-Prüfsummen stimmen mit dem Ausgangszustand überein. Bei verfügbarer Datei-ID zusätzlich dieselben Original-IDs prüfen. |
| 7. Beide Fenster und die Ansicht «Übertragungen» prüfen. «Abgeschlossene entfernen» wählen, falls angezeigt. | Die Dateilisten zeigen beide Originale. Abgeschlossene Karten verschwinden. Aktive oder pausierte Aufträge und der Historieneintrag bleiben verfügbar. |

Den Test separat für «Beide behalten» wiederholen. Das ursprüngliche Ziel bleibt erhalten, und der neue Name enthält die Quellbytes. Rückgängig stellt die Quelle wieder her und entfernt die neu angelegte Kopie vom öffentlichen Zielpfad.

## Weitere Prüffälle ohne WebDAV

| Fall | Durchführung und Prüfkriterium |
| --- | --- |
| App-Neustart und Wiederaufnahme | Einen ausreichend langen Testtransfer pausieren, OpenCommander regulär schliessen und wieder öffnen. Verbindung, Ordneransicht und pausierte Karte prüfen. Denselben Auftrag fortsetzen, Zieldatei anhand ihrer Prüfsumme prüfen und über die Historie rückgängig machen. |
| Unterbrechung und Abbruch | Bei einem separaten Transfer die Verbindung gezielt unterbrechen, etwa an einer isolierten Testverbindung. Wartestatus und Meldung prüfen. Nach Wiederkehr einmal mit «Fortsetzen» abschliessen und in einem zweiten Lauf «Abbrechen» prüfen. Quelle, Ersatzdatei, Namenskonflikte und zurückgelassene Teildateien unabhängig kontrollieren. |
| Wiederholung nach erzwungenem Prozessende | Eine separate Testinstanz während eines Transfers beenden. Die App neu starten und denselben Auftrag wiederaufnehmen. Sichtbare Teildateien, doppelte Historieneinträge und Byte-Abweichungen erfassen. |
| Cloud-Verbindungen | Eingerichtete Dienste einzeln prüfen. Ordner wechseln, Dateien öffnen und Vorschau, Ladeanzeige, Upload, Download, Verschieben und Rückgängig mit eigenen Dateien prüfen. Direkte Verbindung und synchronisierten Ordner im Ergebnis benennen. |
| Drag-and-drop | Zwischen beiden Bereichen sowie in beide Richtungen zwischen OpenCommander und Windows-Explorer ziehen. Standardgeste und angebotene Modifikatortasten je einmal für Datei, Ordner und Mehrfachauswahl prüfen. Tatsächlichen Kopier- oder Verschiebeeffekt, Übertragungsanzeige und Rückgängig anhand beider Dateilisten und Prüfsummen prüfen. |
| Datenträger und NAS | Mit eigenen Dateien NTFS, exFAT und, falls verfügbar, SMB prüfen. In beide Richtungen kopieren und verschieben. Ersetzen, Wiederaufnahme und Rückgängig prüfen. Beim Medienwechsel darf ein anderer Datenträger am selben Laufwerksbuchstaben keinen alten Auftrag übernehmen. |
| Lokale Werkzeuge | Suche im aktiven Ordner und mit geändertem Pfad, Suchtreffer mit vollständigem Pfad, Gross-/Kleinschreibung standardmässig deaktiviert, Vergleichen, mehrfaches Umbenennen, ZIP und Rückgängig prüfen. |
| Belastung | Mehrere Aufträge mit unabhängigen Zielen starten. Währenddessen navigieren, pausieren und fortsetzen. Laufzeit, freien Speicher, Fehler und die abschliessenden Prüfsummen festhalten. Der vollständige D2-Referenzdatensatz umfasst 20.000 kleine und vier grosse Dateien. Quelle und Ziel belegen zusammen rund 14 GiB, die macOS-Vorprüfung verlangt 17,5 GiB. |

## Ergebnis festhalten

Pro Fall Build, Status («bestanden», «fehlgeschlagen», «teilweise» oder «blockiert»), Abweichung vom Soll und Beleg erfassen. Bei einem Fehler zusätzlich die Reproduktionsschritte, die Uhrzeit und die genaue Meldung notieren. Mehrere fehlgeschlagene Schritte können denselben Fehler betreffen.

| Fall | Build / Umgebung | Ergebnis | Beleg oder Fehler |
| --- | --- | --- | --- |
| Dropbox → Google Drive, Ersetzen, Fortsetzen, Rückgängig |  |  |  |

Die macOS-Live-Läufe mit Builds 101 und 102 haben Wiederaufnahme und Rückgängig bis zum unabhängigen Nachweis beider ursprünglichen Anbieter-IDs und Prüfsummen abgeschlossen. Build 101 wurde nach einem Anbieter-Zeitlimit wiederaufgenommen, Build 102 nach einer manuellen Pause. Der Windows-Nachweis steht aus. [Mac-Testprotokoll](mac-dropbox-google-drive-build101-2026-11-12.md)
