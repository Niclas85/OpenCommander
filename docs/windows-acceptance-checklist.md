# OpenCommander auf Windows prüfen

Referenz ist die macOS-Abnahme von OpenCommander. Die Windows-Ergebnisse werden beim eigenen Durchlauf eingetragen. WebDAV gehört nicht zu diesem Durchlauf.

## Vollständige Prüfliste

- [158 Prüffälle für Windows](windows-acceptance-cases.csv) enthält pro Fall Voraussetzungen, Schritte, Soll und Felder für Build, Status, Ist-Ergebnis, Beleg und Fehler-ID. In Excel über **Daten → Aus Text/CSV** als UTF-8 mit Semikolon importieren. Der Windows-Status startet bei «Nicht ausgeführt».
- [Mac-Ergebnisse nach Fall-ID](macos-acceptance-findings-for-windows.json) enthält die dokumentierten Beobachtungen und die jeweilige Zahl der Belegverweise. Am 18. November 2026 waren 105 Fälle nativ belegt, 46 teilweise belegt und 7 von einer fehlenden Testumgebung abhängig.
- [24 gezielte Regressionsnachtests](windows-regressions-from-macos.md) beschreiben die Mac-Befunde und das erwartete Windows-Verhalten. Die Spalte «Mac-Regressionen» verweist aus der CSV auf diese Nachtests. Mehrere Fälle können auf dieselbe Regression verweisen. Zusätzliche Einzelbefunde stehen im Mac-Protokoll. Diese Zahl zählt die dokumentierten Nachtests und ist keine Gesamtzahl einzelner Fehler.

Jede benötigte Variante als eigene Zeile erfassen und die ursprüngliche Fall-ID beibehalten. Beispiel `FILE-03 / Explorer → App / Ctrl / exFAT`. Falls eine Funktion im Windows-Build fehlt, die Abweichung festhalten. «Blockiert» für tatsächlich fehlende Konten, Hardware oder Testumgebungen verwenden und den Grund angeben. «Nicht anwendbar» für belegte plattformspezifische Ausnahmen. Bei Bedientasten gelten Windows-Handbuch und sichtbare Menübefehle. Bei Finder-Fällen Windows-Explorer verwenden. Bei SERVER-08 nur SMB/NAS prüfen.

## Vorbereitung

- Windows-Version, OpenCommander-Build und Testsprache notieren. Für beide Cloud-Dienste die direkte Verbindung in OpenCommander verwenden.
- In Dropbox und Google Drive je einen eigenen Ordner mit demselben eindeutigen Namen erstellen, etwa `OpenCommander-QA-20261114-01`. Jeweils eine Datei namens `CrossMove.txt` anlegen. In Dropbox beispielsweise `Dropbox Original – Grüße 日本語`, in Google Drive `Drive Original – alte Fassung` speichern. Für Kopier-, Abbruch- und Belastungstests eigene Unterordner verwenden.
- Beide Dateien vor dem Test unabhängig von OpenCommander herunterladen und die SHA-256-Prüfsummen erfassen. Wenn der Anbieter die Datei-ID über seine API zugänglich macht, auch beide IDs notieren. Lokale Prüfsummen lassen sich mit `Get-FileHash -Algorithm SHA256 -LiteralPath '.\CrossMove.txt'` berechnen. Beim Prüfen dieselben Download-Verfahren verwenden.

### Datensätze und Varianten

| Kürzel | Windows-Testaufbau und Nachweis |
| --- | --- |
| D1 | Mindestens 30 synthetische Dateien mit leeren Dateien, Dateien mit 1 Byte und 1 MiB, Unicode, Leerzeichen, langen gültigen Namen, versteckten Dateien, leeren und verschachtelten Ordnern sowie kontrollierten Namenskonflikten. Reparse Points und Links separat in der Test-VM prüfen. Vorher und nachher relative Pfade, Typ, Grösse und SHA-256 vergleichen. |
| D2 | 20'000 kleine Dateien und vier grosse Dateien in einem gemischten Baum, darunter eine 2-GiB-Datei. Für Quelle und Ziel zusammen rund 14 GiB, plus Platz für Staging und Rückgängig vorsehen. Den vollständigen Run mit mindestens 17,5 GiB frei vorbereiten und den tatsächlichen freien Speicher am Ziel notieren. Für SAFE-05 zusätzlich 1'000 synthetische Historieneinträge. |
| D3 | JPEG, PNG, WebP und GIF, defektes und absichtlich grosses Bild, kurzes MP4, Audio, Text und Binärdatei. Inhalt, Reihenfolge, Wiedergabe, Positionswechsel und Bereinigung temporärer Dateien prüfen. |
| D4 | Unterstützte Archivformate mit demselben D1-Teilsatz. Leere, defekte, verschlüsselte und absichtlich unsichere Archive in einer isolierten Testumgebung prüfen. Nur entpacken und Hashes vergleichen. |
| C1 | OneDrive Personal, Google Drive, Dropbox und iCloud Drive separat. Geschäfts- und geteilte Bereiche bei Verfügbarkeit separat erfassen. Direkte Verbindung und synchronisierter Windows-Ordner ergeben getrennte Varianten. |
| T1 / T2 | Lokal, SMB, jedes eingerichtete Cloud-Ziel und die Cloud-zu-Cloud-Richtungen separat prüfen. Kopieren und Verschieben, direkte Verbindung und externe Einbindung mit Schreibcache, schreibgeschützt und offline separat erfassen. Sichtbare Daten und Hashes beim Anbieter unabhängig verifizieren. |
| S1 | Kontrolliertes SFTP mit Passwort, Schlüssel und Agent, FTP, explizites FTPS und SMB. Abgelehnter Host-Key, abgelehntes Zertifikat und falsches Testpasswort ergeben getrennte Fälle. |
| U1 | Deutsch und Englisch, Hell und Dunkel, 100/150/200 % Skalierung, schmale und breite Fenster, Maus und Tastatur. |

Bei Links oder Freigaben ein separates Testkonto und eine entbehrliche Datei verwenden. Kontrollierte Prozessabbrüche, Speichermangel und Netzverlust in einer Windows-Test-VM durchführen. Belege bitte ohne Kontonamen, öffentliche Freigabelinks, Zugangsdaten oder persönliche Pfade ablegen.

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

## SMB-Abbruch mit Kopie und Ersetzen

Eine separate Windows-Testinstanz mit eigener SMB-Freigabe verwenden. Eine ausreichend grosse lokale Quelldatei vorbereiten und ihren SHA-256 erfassen. In der Freigabe eine unabhängige Markierungsdatei anlegen und ebenfalls hashen. Die beiden Varianten in getrennten Ordnern ausführen. Bei «Ersetzen» vorab eine gleichnamige Zieldatei mit anderen Bytes anlegen und ihren Hash erfassen.

| Schritt | Erwartetes Ergebnis |
| --- | --- |
| 1. Kopie starten, bei «Ersetzen» den Konflikt bestätigen. Die separate SMB-Verbindung erst nach messbarem Fortschritt trennen. | Der laufende Auftrag bleibt mit seinem Fortschritt erhalten und wartet auf das Ziel. Am ehemaligen Einbindungspfad wird lokal keine Ersatzkopie angelegt. |
| 2. OpenCommander schliessen und mit demselben Testprofil wieder öffnen. Den unterbrochenen Auftrag bei weiterhin getrenntem Ziel abbrechen. | Die App zeigt ausstehende Bereinigung. Folgeaufträge auf denselben Pfaden bleiben bis zur Bereinigung geschützt. |
| 3. Dieselbe SMB-Freigabe wieder verbinden und die ausstehende Bereinigung fortsetzen, falls die App dazu auffordert. | Derselbe Auftrag endet als abgebrochen. Er erzeugt keinen erfolgreichen Kopiereintrag und der eigene Zwischenstand ist entfernt. Bei «Ersetzen» enthält der Zielname wieder die ursprünglichen Bytes. |
| 4. Dateiliste und Ergebnis zusätzlich im Explorer prüfen und alle vorhandenen Testdateien erneut hashen. | Die Quelle und die unabhängige Markierungsdatei sind bytegenau erhalten. In der Kopier-Variante fehlt der Zielname. In der Ersetzen-Variante stimmt der Hash des ursprünglichen Ziels. |

Den Abbruch zusätzlich bei durchgehend verbundener Freigabe prüfen. Nach erfolgreicher Bereinigung muss der Eintrag der sichtbaren Teilkopie ohne manuelles Aktualisieren verschwinden.

Die Wiederaufnahme in zwei separaten Läufen prüfen. Einmal nach SMB kopieren und das Ziel trennen, einmal von SMB kopieren und die Quelle trennen. Bei getrennter Freigabe die Test-App neu öffnen und «Fortsetzen» wählen. Der Fortschritt muss erhalten bleiben, während die App auf die Freigabe wartet. Anschliessend dieselbe Freigabe wieder verbinden, denselben Auftrag abschliessen und beide SHA-256-Prüfsummen vergleichen. «Rückgängig» muss den öffentlichen Zielnamen entfernen und die Quelle sowie die Markierungsdatei erhalten. Falls die App dabei eine private Wiederherstellungskopie behält, auch deren Inhalt prüfen. Beide Richtungen wurden unter macOS mit 96-MiB-Testdateien und einer echten separaten SMB-Verbindung in der Übertragungslogik geprüft. Der grosse D2-Lauf ist davon unabhängig.

Für die Kombination aus NTFS und SMB denselben Kopierauftrag bei getrenntem Ziel und anschliessend bei getrennter Quelle prüfen. Jeweils nur den anderen Endpunkt verbinden, die Test-App mit demselben Profil neu öffnen und «Fortsetzen» wählen. Die Meldung muss den fehlenden Endpunkt korrekt bezeichnen, und der gespeicherte Auftrag muss warten. Bei einem Ausfall während der abschliessenden Prüfung darf der Auftrag trotz vollständig übertragener Bytes noch keinen Erfolg melden. Sobald beide Endpunkte verbunden sind, denselben Auftrag abschliessen, die Prüfsummen vergleichen und «Rückgängig» ausführen. Für die Gegenrichtung wiederholen.

Für REC-10 einen Verschiebeauftrag mit «Ersetzen» in einer isolierten Testinstanz vorbereiten. Falls ein Testadapter vorhanden ist, den Testprozess beenden, nachdem das Ziel verifiziert und die Quelle an den Wiederherstellungspfad verschoben wurde. Der Auftrag darf seinen Abschluss noch nicht gespeichert haben. Am früheren Quellpfad eine neue Testdatei mit anderen Bytes anlegen. Nach dem Neustart muss der Auftrag den Konflikt melden. Die veröffentlichte Zieldatei, beide Originale im Wiederherstellungsbereich und die neue Datei müssen erhalten bleiben. Die neue Testdatei separat umbenennen, denselben Auftrag fortsetzen und «Rückgängig» ausführen. Der ursprüngliche Quell- und Zielinhalt muss wieder am jeweiligen Namen liegen. In beide Richtungen testen.

## Weitere Prüffälle ohne WebDAV

| Fall | Durchführung und Prüfkriterium |
| --- | --- |
| App-Neustart und Wiederaufnahme | Einen ausreichend langen Testtransfer pausieren, OpenCommander regulär schliessen und wieder öffnen. Verbindung, Ordneransicht und pausierte Karte prüfen. Denselben Auftrag fortsetzen, Zieldatei anhand ihrer Prüfsumme prüfen und über die Historie rückgängig machen. |
| Unterbrechung und Abbruch | Bei einem separaten Transfer die Verbindung gezielt unterbrechen, etwa an einer isolierten Testverbindung. Wartestatus und Meldung prüfen. Nach Wiederkehr einmal mit «Fortsetzen» abschliessen und in einem zweiten Lauf «Abbrechen» prüfen. Quelle, Ersatzdatei, Namenskonflikte und zurückgelassene Teildateien unabhängig kontrollieren. |
| Wiederholung nach erzwungenem Prozessende | Eine separate Testinstanz während eines Transfers beenden. Die App neu starten und denselben Auftrag wiederaufnehmen. Sichtbare Teildateien, doppelte Historieneinträge und Byte-Abweichungen erfassen. |
| Cloud-Verbindungen | Eingerichtete Dienste einzeln prüfen. Ordner wechseln, Dateien öffnen und Vorschau, Ladeanzeige, Upload, Download, Verschieben und Rückgängig mit eigenen Dateien prüfen. Direkte Verbindung und synchronisierten Ordner im Ergebnis benennen. Für CLOUD-07 beide Bereiche gleichzeitig denselben Ordner laden lassen und während der Abfrage nur links weg navigieren. Rechts muss der richtige Inhalt erscheinen. Links darf die vorherige Cloud-Liste nicht nachträglich erscheinen. Wenn sich Anfragezahlen im Testprotokoll sehen lassen, sollte die gemeinsame Abfrage genau einen Listenabruf auslösen. |
| Drag-and-drop | Zwischen beiden Bereichen sowie in beide Richtungen zwischen OpenCommander und Windows-Explorer ziehen. Standardgeste und angebotene Modifikatortasten je einmal für Datei, Ordner und Mehrfachauswahl prüfen. Tatsächlichen Kopier- oder Verschiebeeffekt, Übertragungsanzeige und Rückgängig anhand beider Dateilisten und Prüfsummen prüfen. |
| Datenträger und NAS | Mit eigenen Dateien NTFS, exFAT und, falls verfügbar, SMB prüfen. In beide Richtungen kopieren und verschieben. Ersetzen, Wiederaufnahme und Rückgängig prüfen. Beim Medienwechsel darf ein anderer Datenträger am selben Laufwerksbuchstaben keinen alten Auftrag übernehmen. |
| iPhone als Speicherort | Für DEVICE-01 ein entsperrtes Test-iPhone per Datenkabel verbinden und eine Vertrauensabfrage am Gerät bestätigen, falls sie erscheint. Unter «Orte» und bei den Laufwerken nach dem eindeutig benannten Gerät suchen, den angebotenen Medienzugriff öffnen, die Sichtbarkeit in den Einstellungen umschalten und die Anzeige nach dem Abziehen prüfen. Verhalten und unterstützten Zugriff dokumentieren. Der Mac-Nachweis umfasst Erkennung, Sichtbarkeitseinstellungen und Öffnen von Apple Image Capture. Medienimport und physisches Abziehen sind in diesem Nachweis offen. |
| Lokale Werkzeuge | Suche im aktiven Ordner und mit geändertem Pfad, Suchtreffer mit vollständigem Pfad, Gross-/Kleinschreibung standardmässig deaktiviert, Vergleichen, mehrfaches Umbenennen, ZIP und Rückgängig prüfen. |
| Belastung und Pfadreservierung | Mehrere Aufträge mit unabhängigen Zielen starten. Eine Kopie pausieren und eine Löschung derselben Quelle sowie eine unabhängige Löschung anfordern. Prüfen, dass nur die erste Löschung wartet. Die Kopie abbrechen, beide Löschungen nach Abschluss einzeln rückgängig machen und alle Prüfsummen vergleichen. Laufzeit und freien Speicher erfassen. Auf macOS ist der D2-Lauf bis zur Freigabe der wartenden Löschung dokumentiert. Die endgültige Löschung, Rückgängig und der vollständige Hash-Vergleich sind dort noch offen. |

## Ergebnis festhalten

Pro Fall den Windows-Build, den Status, die Abweichung vom Soll und einen Beleg erfassen. Bei einem Fehler in «Fehler-ID» die ID des Windows-Issues eintragen und dort die Variante, Reproduktionsschritte, Uhrzeit und genaue Meldung festhalten. Die passende Mac-Regressions-ID kann im Windows-Issue als Referenz angegeben werden.

| Fall | Build / Umgebung | Ergebnis | Beleg oder Fehler |
| --- | --- | --- | --- |
| Dropbox → Google Drive, Ersetzen, Fortsetzen, Rückgängig |  |  |  |

Die macOS-Live-Läufe mit Builds 101 und 102 haben Wiederaufnahme und Rückgängig bis zum unabhängigen Nachweis beider ursprünglichen Anbieter-IDs und Prüfsummen abgeschlossen. Build 101 wurde nach einem Anbieter-Zeitlimit wiederaufgenommen, Build 102 nach einer manuellen Pause. Der Windows-Nachweis steht aus. [Mac-Testprotokoll](mac-dropbox-google-drive-build101-2026-11-12.md)
