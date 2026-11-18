# OpenCommander auf Windows prüfen

Referenz ist die macOS-Abnahme von OpenCommander. Die Windows-Ergebnisse werden beim eigenen Durchlauf eingetragen. WebDAV gehört nicht zu diesem Durchlauf.

## Vollständige Prüfliste

- [158 Prüffälle für Windows](windows-acceptance-cases.csv) enthält pro Fall Voraussetzungen, Schritte, Soll und Felder für Build, Status, Ist-Ergebnis, Beleg und Fehler-ID. In Excel über **Daten → Aus Text/CSV** als UTF-8 mit Semikolon importieren. Der Windows-Status startet bei «Nicht ausgeführt».
- [Mac-Ergebnisse nach Fall-ID](macos-acceptance-findings-for-windows.json) enthält die dokumentierten Beobachtungen und die jeweilige Zahl der Belegverweise. Am 18. November 2026 waren 105 Fälle nativ belegt, 46 teilweise belegt und 7 von einer fehlenden Testumgebung abhängig.
- [41 gezielte Regressionsnachtests](windows-regressions-from-macos.md) beschreiben die Mac-Befunde und das erwartete Windows-Verhalten. Die Spalte «Mac-Regressionen» verweist aus der CSV auf diese Nachtests. Mehrere Fälle können auf dieselbe Regression verweisen. Zusätzliche Einzelbefunde stehen im Mac-Protokoll. Die Zahl zählt Nachtests. Sammelbefunde können mehrere Fehler enthalten.

Jede benötigte Variante als eigene Zeile erfassen und die ursprüngliche Fall-ID beibehalten. Beispiel `FILE-03 / Explorer → App / Ctrl / exFAT`. Falls eine Funktion im Windows-Build fehlt, die Abweichung festhalten. «Blockiert» für tatsächlich fehlende Konten, Hardware oder Testumgebungen verwenden und den Grund angeben. «Nicht anwendbar» für belegte plattformspezifische Ausnahmen. Bei Bedientasten gelten Windows-Handbuch und sichtbare Menübefehle. Bei Finder-Fällen Windows-Explorer verwenden. Bei SERVER-08 nur SMB/NAS prüfen.

### Fehlende Voraussetzungen der Mac-Abnahme

| Fälle | Für den Windows-Nachtest vorbereiten |
| --- | --- |
| AUTH-01 | Separate Testkonten für OneDrive, Google Drive und Dropbox. Je Anbieter Erstanmeldung, App-Neustart und Wiederanmeldung getrennt erfassen. |
| AUTH-04 | OneDrive-Testkonto, das mehrere Laufwerke zur Auswahl anbietet. Die gewählte Laufwerks-ID nach dem Neustart prüfen. |
| AUTH-05, AUTH-06 | Apple-Testkonto und bestätigungsfähiges Gerät. Anmeldung, falschen Code, abgelaufenes Vertrauen und verweigerten Webzugriff in getrennten Läufen prüfen. |
| CLOUD-12 | Extern eingebundenes Cloud-Laufwerk mit Schreibcache, sofern der Windows-Build diese Einbindung unterstützt. Den Zustand direkt beim Anbieter und am Einbindungspfad vergleichen. |
| DEVICE-04, DEVICE-06 | Physische, entbehrliche NTFS- und exFAT-Testmedien, gegebenenfalls SMB. Windows-Dateisystemtreiber verwenden. Die Mac-FSKit-Abnahme hat eine eigene Umgebung. |

Diese sieben Fall-IDs haben unter macOS den Status «Testumgebung erforderlich». Die CSV nennt die Voraussetzungen und Prüfschritte für jeden einzelnen Fall.

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

Für CLOUD-09 und CLOUD-10 vor der Bestätigung direkt beim Anbieter prüfen, dass die Testdatei keine öffentliche Freigabe hat. Nach dem Bestätigen den Link in einer abgemeldeten Sitzung öffnen und die Datei mit der vorbereiteten Prüfsumme vergleichen. Anschliessend die Freigabe beim Anbieter widerrufen und den alten Link erneut abgemeldet prüfen. Der rclone-Befehl `link --unlink` kann bei nicht unterstützten Anbietern das Flag ignorieren. Ein erfolgreicher Exitcode reicht als Widerrufsnachweis deshalb nicht aus. [rclone-Dokumentation](https://rclone.org/commands/rclone_link/)

In getrennten abgemeldeten Chrome-Profilen zeigten Google Drive und Dropbox die synthetische Datei nach der Freigabe und verweigerten den bisherigen Link nach dem Widerruf. Der Dropbox-Download aus Chrome und ein separat abgerufener anonymer Google-Drive-Download waren bytegenau.

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

Die Wiederaufnahme in zwei separaten Läufen prüfen. Einmal nach SMB kopieren und das Ziel trennen, einmal von SMB kopieren und die Quelle trennen. Bei getrennter Freigabe die Test-App neu öffnen und «Fortsetzen» wählen. Der Fortschritt muss erhalten bleiben, während die App auf die Freigabe wartet. Anschliessend dieselbe Freigabe wieder verbinden, denselben Auftrag abschliessen und beide SHA-256-Prüfsummen vergleichen. «Rückgängig» muss den öffentlichen Zielnamen entfernen und die Quelle sowie die Markierungsdatei erhalten. Falls die App dabei eine private Wiederherstellungskopie behält, auch deren Inhalt prüfen. Beide Richtungen wurden unter macOS mit 96-MiB-Testdateien und einer echten separaten SMB-Verbindung in der Übertragungslogik geprüft. Ein zusätzlicher 2-GiB-Test hielt denselben Auftrag nach 65 MiB bei getrennter Freigabe offen. Nach erneutem Einbinden bestand er den vollständigen SHA-256-Vergleich und Rückgängig. Der grosse D2-Lauf ist davon unabhängig.

Für die Kombination aus NTFS und SMB denselben Kopierauftrag bei getrenntem Ziel und anschliessend bei getrennter Quelle prüfen. Jeweils nur den anderen Endpunkt verbinden, die Test-App mit demselben Profil neu öffnen und «Fortsetzen» wählen. Die Meldung muss den fehlenden Endpunkt korrekt bezeichnen, und der gespeicherte Auftrag muss warten. Bei einem Ausfall während der abschliessenden Prüfung darf der Auftrag trotz vollständig übertragener Bytes noch keinen Erfolg melden. Sobald beide Endpunkte verbunden sind, denselben Auftrag abschliessen, die Prüfsummen vergleichen und «Rückgängig» ausführen. Für die Gegenrichtung wiederholen.

Für REC-10 einen Verschiebeauftrag mit «Ersetzen» in einer isolierten Testinstanz vorbereiten. Falls ein Testadapter vorhanden ist, den Testprozess beenden, nachdem das Ziel verifiziert und die Quelle an den Wiederherstellungspfad verschoben wurde. Der Auftrag darf seinen Abschluss noch nicht gespeichert haben. Am früheren Quellpfad eine neue Testdatei mit anderen Bytes anlegen. Nach dem Neustart muss der Auftrag den Konflikt melden. Die veröffentlichte Zieldatei, beide Originale im Wiederherstellungsbereich und die neue Datei müssen erhalten bleiben. Die neue Testdatei separat umbenennen, denselben Auftrag fortsetzen und «Rückgängig» ausführen. Der ursprüngliche Quell- und Zielinhalt muss wieder am jeweiligen Namen liegen. In beide Richtungen testen.

Für SAFE-06 vier unabhängige Ziele und ein separates SMB-Testlaufwerk pro Auftrag verwenden. Einen Auftrag pausieren und ein anderes Testlaufwerk während eines aktiven Schreibvorgangs trennen. Die App muss den fehlenden Zielort melden und dessen Zwischenstand behalten. Die zwei unabhängigen Aufträge müssen weiterlaufen. Das getrennte Laufwerk erneut einbinden, beide unterbrochenen Aufträge fortsetzen und alle vier Ziele unabhängig prüfen. Ein macOS-Lauf mit vier Dateien zu je 160 MiB bestätigte diesen Ablauf. Für den Dauerlauf die vollständigen D2-Daten und mindestens zwei Stunden Laufzeit verwenden. In einem weiteren macOS-Lauf wurden alle 20’004 Quelldateien mit insgesamt 7’522’886’128 Bytes nach erneutem Einbinden unabhängig geprüft und vier Aufträge mit getrennten SMB-Zielen gestartet. Dauer und vollständige Zielprüfung stehen noch aus.

Vor einem weiteren Dauerlauf die SMB-Quelldateien mit einer unabhängig erzeugten SHA-256-Liste vergleichen. Dazu die isolierte Freigabe neu verbinden und die Dateien auch ausserhalb von OpenCommander lesen. Ein neu vorbereiteter macOS-Testdatensatz scheiterte bei dieser Vorprüfung. Zwei zusätzliche vollständige Lesevorgänge mit unterschiedlichen Puffergrössen bestätigten zwei abweichende Bytes an denselben Positionen in einer 2-GiB-Quelldatei. Die Ursache ist offen. In Windows einen abweichenden Quelldatensatz als fehlgeschlagene Vorprüfung erfassen. Für die gezielte Gegenprobe eine eigene Quelldatei zwischen Pause und Fortsetzen verändern. OpenCommander muss den betroffenen Auftrag vor der Veröffentlichung stoppen und darf dafür keinen Abschluss verbuchen.

Ein separater macOS-Dauerlauf verwendet 20’004 ausgelesene und geprüfte lokale Quelldateien und vier getrennte SMB-Zielverbindungen. Bei 69 MiB wurde eine Zielverbindung getrennt. Der betroffene Auftrag pausierte, während die drei anderen weiterliefen. Nach dem erneuten Einbinden lief derselbe Auftrag mit mehr als 69 MiB weiter. Die Zwei-Stunden-Marke und die unabhängige Endprüfung aller Ziele sind noch offen.

Die erste fertige 2-GiB-Kopie dieses Laufs stimmte beim unabhängigen Lesen über eine zweite SMB-Verbindung exakt mit der ursprünglichen SHA-256-Liste überein. Auch die unbeteiligte Kontrolldatei blieb bytegenau erhalten. Nach rund 53 Minuten stoppte der Lauf wegen der Prüfsumme einer weiteren 2-GiB-Zieldatei. Zwei vollständige Lesevorgänge über eine zweite SMB-Verbindung fanden dieselben drei abweichenden Bytes. Die lokale Quelle entsprach in beiden Läufen der ursprünglichen Prüfsumme. Die App verbuchte für das betroffene Ziel keinen Abschluss. Die drei unterbrochenen Aufträge wurden mit ihren ursprünglichen Auftrags-IDs und Zwischenständen fortgesetzt. Eine separate Kopie mit dem macOS-Systemwerkzeug auf dieselbe Freigabe bestand zwei vollständige Rückleseprüfungen. Ein zweiter unabhängiger Transfer schrieb in 1-MiB-Blöcken, synchronisierte jeden Block und verglich ihn ohne Dateicache. Anschliessend stimmten auch zwei vollständige Prüfsummen überein. Beide Gegenproben liefen mit anderem Übertragungsablauf als der Dauerlauf. Die Ursache der Abweichung im Dauerlauf ist offen. Bei einer vergleichbaren Abweichung unter Windows die Zielbytes separat lesen, den fehlenden Abschlussbeleg erfassen und eine Systemkopie in ein eigenes Testziel als Gegenprobe ausführen.

### Quelle und Ziel beim SMB-Fortsetzen unterscheiden

1. Einen Kopierauftrag mit einer eigenen SMB-Datei und separater Kontrolldatei anlegen. Den SHA-256 der Quelle ausserhalb der App erfassen. Mit einem Testadapter nach vollständig gespeicherten Dateibytes und vor dem Abschlussbeleg pausieren. Quelle und Ziel müssen zu diesem Zeitpunkt denselben Hash haben.
2. In einem Lauf ein Byte der eigenen Quelle ändern, im zweiten Lauf ein Byte des eigenen Ziels. Die Grösse jeweils beibehalten. Die drei Prüfsummen vor dem Fortsetzen erfassen.
3. Denselben Auftrag fortsetzen. Beide Läufe müssen ohne Abschlussbeleg stoppen. Bei geänderter Quelle darf das bytegenaue Ziel nicht als fehlerhafte Datei ausgegeben werden. Bei geändertem Ziel muss der betroffene Zielpfad als fehlerhaft erscheinen, sofern der Windows-Build einen Pfadhinweis anzeigt. OpenCommander darf keine der beiden Dateien ändern. Die Prüfsummen von Quelle, Ziel und Kontrolldatei erneut ausserhalb der App vergleichen.

## Weitere Prüffälle ohne WebDAV

| Fall | Durchführung und Prüfkriterium |
| --- | --- |
| App-Neustart und Wiederaufnahme | Einen ausreichend langen Testtransfer pausieren, OpenCommander regulär schliessen und wieder öffnen. Verbindung, Ordneransicht und pausierte Karte prüfen. Denselben Auftrag fortsetzen, Zieldatei anhand ihrer Prüfsumme prüfen und über die Historie rückgängig machen. |
| Unterbrechung und Abbruch | Bei einem separaten Transfer die Verbindung gezielt unterbrechen, etwa an einer isolierten Testverbindung. Wartestatus und Meldung prüfen. Nach Wiederkehr einmal mit «Fortsetzen» abschliessen und in einem zweiten Lauf «Abbrechen» prüfen. Quelle, Ersatzdatei, Namenskonflikte und zurückgelassene Teildateien unabhängig kontrollieren. |
| Wiederholung nach erzwungenem Prozessende | Eine separate Testinstanz während eines Transfers beenden. Die App neu starten und denselben Auftrag wiederaufnehmen. Sichtbare Teildateien, doppelte Historieneinträge und Byte-Abweichungen erfassen. |
| Cloud-Verbindungen | Eingerichtete Dienste einzeln prüfen. Ordner wechseln, Dateien öffnen und Vorschau, Ladeanzeige, Upload, Download, Verschieben und Rückgängig mit eigenen Dateien prüfen. Direkte Verbindung und synchronisierten Ordner im Ergebnis benennen. Für CLOUD-07 beide Bereiche gleichzeitig denselben Ordner laden lassen und während der Abfrage nur links weg navigieren. Rechts muss der richtige Inhalt erscheinen. Links darf die vorherige Cloud-Liste nicht nachträglich erscheinen. Wenn sich Anfragezahlen im Testprotokoll sehen lassen, sollte die gemeinsame Abfrage genau einen Listenabruf auslösen. |
| Cloud-Netzausfall (CLOUD-04) | Zwei Bereiche auf denselben eigenen Cloud-Ordner setzen. In einer isolierten Testumgebung nur den Cloud-Transport unterbrechen. Beide Bereiche müssen dieselbe datierte Warnung zur gespeicherten Liste zeigen. Separat einen Download gezielt scheitern lassen. Ohne Erfolgsmeldung aufräumen und eine lokale Datei weiterhin öffnen oder kopieren können. Danach den Transport wieder freigeben, dieselbe Objekt-ID laden und die SHA-256-Prüfsumme unabhängig vergleichen. Separat die Verbindung trennen, sobald im Testprotokoll bereits Download-Daten sichtbar sind. Den Fehler, das entfernte Staging und den anschliessenden bytegenauen Download derselben Datei prüfen. Dieser Ablauf wurde unter macOS mit Google Drive und Dropbox je für eine 2‑MiB-Datei ausgeführt. Anschliessend je Anbieter einen wartenden Kopierauftrag mit «Ersetzen» prüfen. Nach der Trennung müssen die alte Zieldatei und eine separate Markierungsdatei erhalten bleiben. App neu öffnen, denselben Auftrag fortsetzen und genau einen Historieneintrag erwarten. In einem dritten Prozess «Rückgängig» ausführen und den ursprünglichen Zielinhalt prüfen. Beide Anbieter bestanden diesen Ablauf in der macOS-Übertragungslogik. |
| Cloud-Konfiguration und Freigabe | Für AUTH-09 und CLOUD-10 im separaten Testprofil einen eigenen Cloud-Ordner laden. Mit einem Testadapter einen erneuten Abruf nach der Serverantwort anhalten und die Konfiguration des Testprofils austauschen. Einen zuvor geöffneten Freigabedialog bestätigen und die alte Serverantwort freigeben. Die App muss den Konfigurationswechsel melden. Weder die alte Liste noch ein öffentlicher Link dürfen erscheinen. Nach Wiederherstellung der ursprünglichen Konfiguration neu laden und die Objekt-ID prüfen. Der Test lässt sich mit einem Adapter für Freigabeanfragen durchführen, der jeden externen Schreibzugriff verhindert. |
| Drag-and-drop | Zwischen beiden Bereichen sowie in beide Richtungen zwischen OpenCommander und Windows-Explorer ziehen. Standardgeste und angebotene Modifikatortasten je einmal für Datei, Ordner und Mehrfachauswahl prüfen. Tatsächlichen Kopier- oder Verschiebeeffekt, Übertragungsanzeige und Rückgängig anhand beider Dateilisten und Prüfsummen prüfen. Löst eine automatisierte Mausgeste keinen Auftrag aus, dieselbe Variante mit Maus oder Trackpad wiederholen und die Methode im Beleg nennen. |
| Datenträger und NAS | Mit eigenen Dateien NTFS, exFAT und, falls verfügbar, SMB prüfen. In beide Richtungen kopieren und verschieben. Ersetzen, Wiederaufnahme und Rückgängig prüfen. Beim Medienwechsel darf ein anderer Datenträger am selben Laufwerksbuchstaben keinen alten Auftrag übernehmen. |
| iPhone als Speicherort | Für DEVICE-01 ein entsperrtes Test-iPhone per Datenkabel verbinden und eine Vertrauensabfrage am Gerät bestätigen, falls sie erscheint. Unter «Orte» und bei den Laufwerken nach dem eindeutig benannten Gerät suchen, den angebotenen Medienzugriff öffnen, die Sichtbarkeit in den Einstellungen umschalten und die Anzeige nach dem Abziehen prüfen. Verhalten und unterstützten Zugriff dokumentieren. Der Mac-Nachweis umfasst Erkennung, Sichtbarkeitseinstellungen und Öffnen von Apple Image Capture. Medienimport und physisches Abziehen sind in diesem Nachweis offen. |
| Lokale Werkzeuge | Suche im aktiven Ordner und mit geändertem Pfad, Suchtreffer mit vollständigem Pfad, Gross-/Kleinschreibung standardmässig deaktiviert, Vergleichen, mehrfaches Umbenennen, ZIP und Rückgängig prüfen. |
| Belastung und Pfadreservierung | Mehrere Aufträge mit unabhängigen Zielen starten. Eine Kopie pausieren und eine Löschung derselben Quelle sowie eine unabhängige Löschung anfordern. Prüfen, dass nur die erste Löschung wartet. Die Kopie abbrechen, beide Löschungen nach Abschluss einzeln rückgängig machen und alle Prüfsummen vergleichen. Laufzeit und freien Speicher erfassen. Auf macOS schloss die wartende Löschung im D2-Lauf mit 20’004 Dateien ab und wurde in der Historie gespeichert. Der Löschauftrag erfasste rund 5 Stunden und 4 Minuten aktive Laufzeit. Der unabhängige SHA-256-Vergleich in der Wiederherstellungsablage bestätigte alle 20’004 Dateien und 107 Verzeichnisse. Rückgängig für beide Löschungen und der Hash-Vergleich an den wiederhergestellten Originalpfaden stehen aus. |

## Ergebnis festhalten

Pro Fall den Windows-Build, den Status, die Abweichung vom Soll und einen Beleg erfassen. Bei einem Fehler in «Fehler-ID» die ID des Windows-Issues eintragen und dort die Variante, Reproduktionsschritte, Uhrzeit und genaue Meldung festhalten. Die passende Mac-Regressions-ID kann im Windows-Issue als Referenz angegeben werden.

| Fall | Build / Umgebung | Ergebnis | Beleg oder Fehler |
| --- | --- | --- | --- |
| Dropbox → Google Drive, Ersetzen, Fortsetzen, Rückgängig |  |  |  |

Die macOS-Live-Läufe mit Builds 101 und 102 haben Wiederaufnahme und Rückgängig bis zum unabhängigen Nachweis beider ursprünglichen Anbieter-IDs und Prüfsummen abgeschlossen. Build 101 wurde nach einem Anbieter-Zeitlimit wiederaufgenommen, Build 102 nach einer manuellen Pause. Der Windows-Nachweis steht aus. [Mac-Testprotokoll](mac-dropbox-google-drive-build101-2026-11-12.md)

### Google-Docs-Export nach Prozessabbruch fortsetzen

1. Mit direkten Google-Drive- und Dropbox-Verbindungen in einer Test-VM arbeiten. In Google Drive ein eigenes natives Google-Dokument mit eindeutigem Text anlegen und die Google-ID und die ursprüngliche Dokumentart erfassen. In Dropbox einen eigenen leeren Zielordner anlegen.
2. Das Dokument nach Dropbox **kopieren**. Im instrumentierten Lauf den Testprozess direkt nach dem Speichern des vorbereiteten DOCX-Exports und vor dem ersten Upload beenden. SHA-256 der vorbereiteten Datei und Auftrags-ID über den Testadapter erfassen. Der Dropbox-Zielordner ist zu diesem Zeitpunkt leer. Ohne Testadapter lässt sich die normale Kopie prüfen. Den gezielten Abbruch separat als offen erfassen.
3. Das Google-Dokument direkt bei Google umbenennen und die gleiche ID kontrollieren. Die Test-App starten und denselben Auftrag fortsetzen. In Dropbox muss genau eine Kopie unter dem ursprünglich geplanten Namen erscheinen. Den Export unabhängig herunterladen, seinen Hash vergleichen und den Testtext im DOCX lesen.
4. Die App nochmals neu starten und den Kopiereintrag einmal rückgängig machen. Dropbox muss den Export entfernen. Das umbenannte Google-Dokument muss mit derselben ID, Dokumentart und demselben Text erhalten bleiben. Doppelte Zielobjekte oder Historieneinträge als Fehler dokumentieren.

Für die zusätzliche Prüfung vor dem Export im Testadapter die Google-Revision nach dem ersten Abruf ändern. Dateiname und Google-ID bleiben gleich. Die App muss den veralteten Auftrag vor dem Export abweisen. Dropbox bleibt leer. Die Google-Quelle bleibt mit der aktualisierten Fassung erhalten.

### Cloud-Ordner-Download mit Neustart und Rückgängig

1. Einen eigenen Dropbox-Testordner mit `Unterordner/Grüße.txt`, dem leeren Ordner `Unterordner/Leer` und der leeren Datei `Empty.txt` anlegen. Inhalt und SHA-256 von `Grüße.txt` unabhängig erfassen. Falls verfügbar, die Dropbox-IDs festhalten.
2. Den Ordner in einen leeren lokalen Testordner kopieren. Der Auftrag muss zwei Dateien als abgeschlossen anzeigen. Unicode-Name, Prüfsumme, leere Datei und leerer Ordner müssen erhalten bleiben. Die Historie muss genau eine Kopie erfassen.
3. In einer separaten Test-VM mit Testadapter direkt nach dem Speichern des lokalen Kopierbelegs und vor dem Abschluss der Warteschlange den App-Prozess beenden. Die App erneut starten und denselben Auftrag fortsetzen. Die bereits veröffentlichte Kopie muss bestätigt werden. Es darf weder eine zweite Kopie noch einen zweiten Historieneintrag geben. Wenn ein Adapter fehlt, den gezielten Abbruch als offen erfassen.
4. Nach erneutem Start die Kopie rückgängig machen. Nur der lokale Ordner muss verschwinden. Die Dropbox-IDs und die Dateiinhalte müssen gleich bleiben.

### Cloud-Download nach lokaler Veröffentlichung abbrechen

1. In einer Windows-Test-VM eine eigene Cloud-Datei sowie eine gleichnamige lokale Datei mit anderem Inhalt vorbereiten. Beide SHA-256-Prüfsummen und, falls verfügbar, die Cloud-ID notieren. Eine unbeteiligte lokale Kontrolldatei danebenlegen.
2. Die Cloud-Datei mit «Ersetzen» herunterladen. Mit einem Testadapter den App-Prozess direkt nach der Veröffentlichung der neuen lokalen Datei und vor dem Historieneintrag beenden. Den Versuch sowohl vor als auch nach dem Speichern des lokalen Kopierbelegs wiederholen. Ohne Testadapter den gezielten Prozessabbruch als offen erfassen.
3. OpenCommander neu starten und denselben Auftrag abbrechen. Wenn das lokale Ziel seit dem Abbruch unverändert ist, muss genau ein rückgängig machbarer Kopiereintrag erscheinen. Prüfsumme und Kontrolldatei müssen stimmen. In der Variante «Verschieben» den Prozess vor dem Sichern der Cloud-Quelle beenden. Die Cloud-Datei muss sichtbar bleiben und ihre ID sowie ihren Inhalt behalten.
4. Einen weiteren App-Neustart durchführen und «Rückgängig» wählen. Das frühere lokale Ziel muss mit seiner ursprünglichen Prüfsumme zurückkehren. Cloud-Quelle und Kontrolldatei erneut prüfen.
5. Als Gegenprobe das veröffentlichte Ziel nach dem erzwungenen Prozessende durch einen anderen Inhalt ersetzen. Der Abbruch muss den Konflikt und den offenen Wiederherstellungszustand melden. Ziel, Cloud-Quelle und Kontrolldatei müssen ihre jeweils zuletzt festgestellte Prüfsumme behalten.
6. «Verschieben» in zwei weiteren Läufen nach dem Schreiben des Wiederherstellungseintrags testen. Den App-Prozess einmal unmittelbar vor dem Verschieben der Cloud-Quelle in den Wiederherstellungsbereich beenden und einmal unmittelbar danach. Nach dem Neustart denselben Auftrag abbrechen. Im ersten Lauf muss die sichtbare Quelle erhalten bleiben und genau ein Kopiereintrag entstehen. Im zweiten Lauf muss genau ein Verschiebeeintrag entstehen. Der Abbruch darf an der Cloud-Quelle keine weitere Änderung auslösen. «Rückgängig» nach einem weiteren Neustart muss das frühere lokale Ziel und im zweiten Lauf auch die Cloud-Quelle unter ihrem ursprünglichen Namen wiederherstellen. Wenn möglich dieselbe Cloud-ID bestätigen.

### Externe Synchronisierung nach einem Cloud-Download prüfen

1. Dieselbe eigene Testdatei aus einer direkten Cloud-Verbindung einmal auf ein gewöhnliches lokales Laufwerk und einmal in einen externen Ort mit Schreibcache herunterladen. Für den Dateisystempfad zusätzlich einen SMB-Testordner verwenden und «Ersetzen» mit einer gleichnamigen Datei anderer Prüfsumme testen.
2. Die Karte des abgeschlossenen Auftrags prüfen und die App neu starten. Am externen Ziel muss der Status zwischen erfolgtem Dateisystemtransfer und unabhängig bestätigtem Anbieterinhalt unterscheiden. Ein erfolgreiches Sichern oder Lesen vom Cache allein reicht nicht als Anbieterbestätigung. Am gewöhnlichen lokalen Ziel soll kein Hinweis auf externe Synchronisierung erscheinen.
3. SHA-256 am Ziel und bei einem Cache zusätzlich unabhängig am Anbieter prüfen. Beim SMB-Ersetzen «Rückgängig» wählen. Die alte Zieldatei muss ihren früheren Hash zurückerhalten. Prüfe die unveränderte Cloud-Quelle und eine unbeteiligte Datei neben dem Ziel.

Für den zusätzlichen Schreibcache-Test ein eigenes rclone-Laufwerk mit verzögertem Writeback und einem unabhängig lesbaren Test-Backend einbinden. Direkt aus der Cloud zum Laufwerk kopieren. Sobald die Warteschlange fertig meldet, muss der Hash am Laufwerk stimmen und der Hinweis zur unbestätigten Synchronisierung sichtbar sein. Das unabhängige Backend darf in der eingestellten Wartezeit noch leer sein. Nach Ablauf der Wartezeit muss es genau dieselben Bytes enthalten. Die Cloud-Quelle währenddessen unabhängig prüfen. «Verschieben» mit einer separaten Testdatei wiederholen. Ohne bestätigte Übertragung zum Anbieter muss die Cloud-Quelle erhalten bleiben.

### Cloud-Download bei getrenntem Ziellaufwerk wiederaufnehmen

1. Einen eigenen Cloud-Download auf ein separates Testlaufwerk vorbereiten. Mit einem Testadapter nach erfolgreichem Dateisystemtransfer und vor dem Warteschlangenabschluss den App-Prozess beenden. Die Auftrags-ID und den SHA-256 der Testdatei erfassen. Anschliessend das Testlaufwerk trennen.
2. Die App neu öffnen. In getrennten Läufen «Fortsetzen» und «Abbrechen» am selben gespeicherten Auftrag wählen. Der Auftrag muss pausiert bleiben und auch in der kompakten Ansicht zum Wiederverbinden auffordern. Beim Abbruch muss die ausstehende Prüfung vermerkt bleiben. Am leeren Einbindungspfad dürfen keine Dateien entstehen. Solange die Verbindung fehlt, darf kein erfolgreicher Historieneintrag erscheinen.
3. Dasselbe Testlaufwerk wieder einbinden und denselben Auftrag fortsetzen. Im Abbruchlauf muss die App zuerst die ausstehende Prüfung abschliessen. Die bereits wirksame Kopie muss bytegenau bestätigt und genau einmal in der Historie erfasst werden. Die unabhängige Prüfsumme am Ziel, der unveränderte Inhalt der Quelle und die ursprüngliche Auftrags-ID müssen stimmen.

### Unvollständigen Cloud-Download nach Prozessabbruch bereinigen

1. Eine eigene Cloud-Testdatei von mindestens 4 MiB in einen eigenen SMB-Testordner kopieren. Eine unbeteiligte Kontrolldatei im selben Ordner anlegen. Den App-Prozess nach dem ersten gespeicherten Datenblock und vor dem Abschluss beenden. Der Zielname muss zu diesem Zeitpunkt eine Teilkopie enthalten.
2. OpenCommander neu öffnen und denselben Auftrag abbrechen. Die eigene Teilkopie muss aus dem Dateifenster verschwinden. Cloud-Quelle und Kontrolldatei müssen an ihren Orten bleiben und dieselben Prüfsummen behalten. Es darf keinen erfolgreichen Historieneintrag geben.
3. Mit «Ersetzen» wiederholen. Nach «Abbrechen» muss das vorherige Ziel unter seinem ursprünglichen Namen und mit seiner ursprünglichen Prüfsumme zurückkehren.
4. Als Gegenprobe die eigene Teilkopie im Testordner durch eine andere Testdatei ersetzen. Die App muss diese Datei erhalten und den Konflikt offen anzeigen. Die Prüfsumme dieser Datei und der Cloud-Quelle unabhängig bestätigen.

### Google-Bestätigung nach der Quellensicherung geht verloren

Mit einem entbehrlichen nativen Google-Dokument im eigenen Drive-Testordner prüfen. Google-ID, Dokumenttyp und einen eindeutigen Satz festhalten. Für den gezielten Prozessabbruch ist ein instrumentierter Testadapter erforderlich.

1. Den Wiederherstellungsnamen der Quellensicherung im Test aufzeichnen. In einem separaten Versuch diesen Namen vor der Sicherung mit einer eigenen anderen Datei belegen. Der Vorgang muss stoppen. Beide Objekte und Inhalte müssen erhalten bleiben.
2. Den Platzhalter entfernen und den Testprozess beenden, sobald Google die Quellensicherung bestätigt, bevor die App die Antwort verbucht. Den Wiederherstellungsnamen und die unveränderte Google-ID im Anbieter prüfen.
3. Den Testprozess neu starten. Die bereits ausgeführte Quellensicherung muss anhand der ursprünglichen ID erkannt werden. Der Testadapter darf keinen zweiten Schreibaufruf für die Quellensicherung verzeichnen. Nach einem weiteren Neustart muss Rückgängig den Originalnamen mit gleicher Google-ID, gleichem Typ und Inhalt wiederherstellen.
4. Einen gesonderten Versuch mit einer nach der Vorbereitung geänderten Google-Revision ausführen. Die Sicherung für die veraltete Revision muss abgewiesen werden. Das aktuelle Dokument muss erhalten bleiben.

Der Mac-Live-Test belegt die Quellensicherung und Wiederherstellung. Der vollständige Wechsel zu einem zweiten Cloud-Dienst hat eine eigene Abnahme.

### Google-Dokument nach Dropbox verschieben und rückgängig machen

1. Ein natives Google-Dokument im eigenen Testordner anlegen und ID, Typ und Text erfassen. In einen leeren Dropbox-Testordner **verschieben**. In Dropbox muss der DOCX-Export mit dem erwarteten Text erscheinen. Das ursprüngliche Google-Dokument muss unter einem internen Wiederherstellungsnamen mit derselben ID erhalten bleiben.
2. Mit dem Testadapter unmittelbar nach dem Speichern des privaten Exports abbrechen. Dropbox bleibt leer und das Google-Dokument behält seinen Namen. Die App erneut öffnen und denselben Auftrag fortsetzen.
3. Den Testprozess erneut beenden, sobald der geprüfte Dropbox-Export vorhanden und das native Original gesichert ist. In der Test-App nach dem Neustart denselben Auftrag fortsetzen. Der Auftrag muss mit derselben ID abschliessen und genau einen Verschiebeeintrag ergeben.
4. Rückgängig nach einem weiteren Neustart ausführen. In Google Drive müssen der Originalname, die gleiche ID, der native Typ und der Text wieder sichtbar sein. Der öffentliche Dropbox-Zielname muss verschwinden. Ein erneuter Aufruf desselben Rückgängig-Belegs durch den Testadapter muss denselben Zustand bestätigen.

### Google-Dokument beim Ersetzen nach Veröffentlichung abbrechen

1. Ein natives Google-Testdokument und eine gleichnamige Dropbox-Datei mit anderem Inhalt vorbereiten. Google-ID sowie Dropbox-ID und SHA-256 der alten Datei erfassen. **Verschieben → Ersetzen** starten.
2. Mit dem Testadapter den Prozess nach der Veröffentlichung des verifizierten Dropbox-Exports und vor der Sicherung der Google-Quelle beenden. Google muss die Quelle am Originalnamen zeigen. Dropbox muss den Export zeigen und die bisherige Datei mit derselben ID zur Wiederherstellung behalten.
3. Das Google-Testdokument über einen zweiten Client umbenennen und auf seinen alten Namen zurücksetzen. Die Google-ID muss gleich bleiben. Die App neu starten und den ursprünglichen Auftrag abbrechen. Der Adapter soll keine Schreibaufrufe an die Anbieter protokollieren. Der Verlauf muss genau einen Kopiereintrag mit Rückgängig zeigen.
4. Nach erneutem Programmstart Rückgängig ausführen und den Anbieter unabhängig prüfen. Die ursprüngliche Dropbox-ID und SHA-256 müssen am sichtbaren Zielnamen zurück sein. Google-ID, Typ und Inhalt bleiben erhalten. Denselben Beleg im Testadapter einmal erneut aufrufen und die IDs sowie Inhalte nochmals vergleichen.

#### Gegenprobe vor der Veröffentlichung

1. Dieselben beiden Testdateien erneut vorbereiten. Den Testprozess nach dem Speichern des privaten Exports und vor dem ersten Dropbox-Schreibaufruf beenden.
2. Mit einem zweiten Client den Text im Google-Dokument ändern. Den ursprünglichen Namen behalten. Google-ID, neuen Testtext und einen Nachweis für das geänderte Dokument erfassen, etwa eine geänderte ETag oder einen veränderten DOCX-Archivinhalt.
3. Nach dem Neustart denselben Auftrag fortsetzen. Der erwartete Versionskonflikt erscheint vor dem Ersetzen. Die alte Dropbox-ID, der sichtbare Name und die Prüfsumme bleiben erhalten.
4. Den Auftrag abbrechen und erneut öffnen. Es darf kein erfolgreicher Kopier- oder Verschiebeeintrag entstehen. Die Google-ID, der native Typ und der neue Text bleiben erhalten.

Der separate macOS-Live-Lauf vom 18. November 2026 änderte den Text des nativen Testdokuments über einen zweiten Client. Nach dem Neustart stoppte der alte Auftrag vor dem ersten Schreibzugriff. Der anschliessende Abbruch erzeugte keinen Historieneintrag. Beide Anbieter bestätigten unabhängig dieselben Objekt-IDs, den neuen Google-Text und die alten Dropbox-Bytes.

### Google-Dokument mit unverändertem Inhalt nach Dropbox verschieben und ersetzen

1. Ein eigenes Google-Dokument und eine gleichnamige Dropbox-Datei mit anderem Inhalt vorbereiten. Google-ID, Dateityp, Text sowie Dropbox-ID und SHA-256 des alten Zielinhalts erfassen. Mit dem Testadapter den privaten DOCX-Export festhalten und den Prozess vor der ersten Dropbox-Veröffentlichung beenden.
2. Einen zweiten Export desselben Google-Dokuments abrufen. Wenn der Testadapter Versionsänderungen steuern kann, eine Änderung der numerischen Google-Version bei stabiler ETag, Änderungszeit, ID und Ordnerzuordnung nachstellen. Für beide DOCX-Dateien die Namen sämtlicher ZIP-Einträge und den SHA-256 ihres unkomprimierten Inhalts vergleichen. Unterschiedliche ZIP-Rohbytes sind bei identischen Einträgen zulässig. Den Lauf ohne kontrollierte Versionsänderung als normale Ersetzen-Variante erfassen.
3. Die App neu öffnen und denselben Auftrag fortsetzen. Der veröffentlichte Dropbox-Export muss den zuvor gespeicherten Rohbytes entsprechen. Sobald Ziel und Sicherung des Google-Originals nachgewiesen sind, die App im Testadapter vor dem Warteschlangenabschluss nochmals beenden. Nach dem Neustart muss derselbe Auftrag genau einen Verschiebeeintrag erzeugen.
4. Rückgängig nach einem weiteren App-Neustart ausführen. Den ursprünglichen Google-Namen, dieselbe native ID, Typ und Text sowie die alte Dropbox-ID und deren exakten SHA-256 unabhängig prüfen. Bei erneutem Aufruf desselben Rückgängig-Belegs muss der wiederhergestellte Zustand erhalten bleiben.

Die Mac-Diagnose beobachtete eine geänderte numerische Google-Version auch bei einem unberührten Kontroll-Dokument. Zwei tatsächliche DOCX-Exporte desselben Dokuments hatten verschiedene ZIP-Rohbytes und identische SHA-256-Werte pro Archiveintrag. Für die [Gegenprobe mit tatsächlicher Inhaltsänderung](#gegenprobe-vor-der-veröffentlichung) einen separaten Lauf verwenden.

Der macOS-Live-Nachtest vom 18. November 2026 erreichte mit echten Google-Drive- und Dropbox-Testordnern beide Abbruchpunkte. Nach dem Neustart hatte der Auftrag dieselbe ID und genau einen Historieneintrag. Zweimaliges Rückgängig in separaten Prozessen stellte die alte Dropbox-ID und deren Bytes sowie Google-Name, ID, Typ und Text wieder her. Der Lauf prüfte die Übertragungslogik. Die Bedienung im App-Fenster ist ein eigener Nachtest.

In PowerShell lassen sich die Archiveinträge der beiden unveränderten Exporte direkt vergleichen. `Compare-Object` gibt keine Zeile aus, wenn Namen und Prüfsummen übereinstimmen.

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-DocxEntryHashes($Path) {
    $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        foreach ($entry in $archive.Entries) {
            $stream = $entry.Open()
            try {
                '{0}  {1}' -f (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash, $entry.FullName
            } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
}
Compare-Object @(Get-DocxEntryHashes '.\Export A.docx') @(Get-DocxEntryHashes '.\Export B.docx') -CaseSensitive
```
