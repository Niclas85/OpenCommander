# OpenCommander auf Windows prüfen

Referenz ist die macOS-Abnahme von OpenCommander. Die Windows-Ergebnisse werden beim eigenen Durchlauf eingetragen. WebDAV gehört nicht zu diesem Durchlauf.

## Vollständige Prüfliste

- [158 Prüffälle für Windows](windows-acceptance-cases.csv) enthält pro Fall Voraussetzungen, Schritte, Soll und Felder für Build, Status, Ist-Ergebnis, Beleg und Fehler-ID. In Excel über **Daten → Aus Text/CSV** als UTF-8 mit Semikolon importieren. Der Windows-Status startet bei «Nicht ausgeführt».
- [Mac-Ergebnisse nach Fall-ID](macos-acceptance-findings-for-windows.json) enthält die dokumentierten Beobachtungen und die jeweilige Zahl der Belegverweise. Am 18. November 2026 waren 106 Fälle nativ belegt, 45 teilweise belegt und 7 von einer fehlenden Testumgebung abhängig.
- [54 gezielte Regressionsnachtests](windows-regressions-from-macos.md) beschreiben die Mac-Befunde und das erwartete Windows-Verhalten. Die Spalte «Mac-Regressionen» verweist aus der CSV auf diese Nachtests. Mehrere Fälle können auf dieselbe Regression verweisen. Zusätzliche Einzelbefunde stehen im Mac-Protokoll. Die Zahl zählt Nachtests. Sammelbefunde können mehrere Fehler enthalten.

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

Im sichtbaren Test mit dem signierten Mac-Build 321 blieb die Testdatei nach «Abbrechen» auf Google Drive und Dropbox privat. Erst die Bestätigung erstellte den Link. Getrennte abgemeldete Chrome-Sitzungen zeigten die Dateien und verweigerten den Zugriff nach dem Widerruf beim Anbieter. Der Dropbox-Download aus Chrome und der unabhängig abgerufene anonyme Google-Drive-Download waren bytegenau. Bei Google Drive war die Leserfreigabe per Link erreichbar und von der Suche ausgeschlossen.

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

Die erste fertige 2-GiB-Kopie dieses Laufs stimmte beim unabhängigen Lesen über eine zweite SMB-Verbindung exakt mit der ursprünglichen SHA-256-Liste überein. Auch die unbeteiligte Kontrolldatei blieb bytegenau erhalten. Nach rund 53 Minuten stoppte der Lauf wegen der Prüfsumme einer weiteren 2-GiB-Zieldatei. Zwei vollständige Lesevorgänge über eine zweite SMB-Verbindung fanden dieselben drei abweichenden Bytes. Die lokale Quelle entsprach in beiden Läufen der ursprünglichen Prüfsumme. Die App verbuchte für das betroffene Ziel keinen Abschluss. Die drei unterbrochenen Aufträge wurden mit ihren ursprünglichen Auftrags-IDs und Zwischenständen fortgesetzt. Eine separate Kopie mit dem macOS-Systemwerkzeug auf dieselbe Freigabe bestand zwei vollständige Rückleseprüfungen. Ein zweiter unabhängiger Transfer schrieb in 1-MiB-Blöcken, synchronisierte jeden Block und verglich ihn ohne Dateicache. Anschliessend stimmten auch zwei vollständige Prüfsummen überein. Beide Gegenproben liefen mit anderem Übertragungsablauf als der Dauerlauf. Im fortgesetzten Lauf scheiterten zwei weitere Zieldateien mit 2 GiB und 1 GiB. Zwei unabhängige Lesevorgänge bestätigten je ein abweichendes Byte bei unveränderter Quelle und ohne Abschlussbeleg. Ein zusätzlicher Lauf mit der OpenCommander-Übertragungslogik kopierte dieselbe 2-GiB-Datei zusammen mit einer kleinen Datei in einem separaten Testordner. Beide Ziele stimmten bei der unabhängigen Prüfung. Die Ursache im grossen Lauf bleibt offen. Bei einer vergleichbaren Abweichung unter Windows die Zielbytes separat lesen, den fehlenden Abschlussbeleg erfassen und eine Systemkopie in ein eigenes Testziel als Gegenprobe ausführen.

Bei reproduzierbarer Byte-Abweichung die Quelle am lokalen Pfad beziehungsweise vor dem Transfer direkt auf SMB prüfen. Danach das Ziel über eine zweite SMB-Verbindung zweimal vollständig lesen. SHA-256 und die ersten abweichenden Byte-Positionen erfassen. In den Mac-Vergleichen traten zwei feste Positionen und Bitmasken innerhalb von 4-KiB-Blöcken sowohl bei einer vorab bereitgestellten SMB-Quelle als auch in drei SMB-Zieldateien auf. Bei der späteren Kontrolllesung über zwei Einbindungen waren zwei von fünf früher betroffenen Zielpositionen weiterhin abweichend. An den übrigen drei Positionen stimmten die gelesenen Blöcke wieder mit dem Original überein. Solche nachträglichen Stichproben mit Zeit und Lesegrösse aufzeichnen. Den Auftrag erst nach vollständigem Hash-Abgleich aller Daten als bestanden werten. Die Ursache ist offen.

Eine parallele Mac-Gegenprobe ausserhalb von OpenCommander reproduzierte dieselbe 4-KiB-Bitposition bei einer 1-GiB-Datei. Alle unmittelbar geprüften Schreibblöcke waren korrekt. Zwei vollständige Lesevorgänge nach dem Schliessen fanden dasselbe eine abweichende Bit. Eine weitere vollständige Lesung über eine zweite SMB-Einbindung bestätigte Bitposition und Prüfsumme. Die zwei anderen 2-GiB-Kopien, die lokalen Quellen und die Kontrolldatei stimmten. Für eine Windows-Gegenprobe denselben Testdatensatz gleichzeitig mit dem Betriebssystem in drei eigene SMB-Ziele kopieren. Nach dem Schliessen den vollständigen SHA-256 je Zieldatei zweimal prüfen, wenn möglich über zwei separate SMB-Verbindungen oder einen zweiten Computer. Prüfsummen der Quellen und die Zahl der bestätigten Abweichungen festhalten.

Ein fortgesetzter Mac-Auftrag erreichte 7’000 von 7’001 Dateien und stoppte in der letzten Datei ohne Abschlussbeleg. In einem gezielten Vergleich am Ende der unvollständigen Zieldatei lasen zwei frisch eingehängte Nur-Lese-Verbindungen dasselbe abweichende Bit bei Byteposition 368’476’508. Die vollständige Quellprüfsumme, das Auftragsjournal und die separate Kontrolldatei stimmten. Die Position innerhalb des 4-KiB-Blocks und die Bitmaske entsprachen einem früheren Befund.

Für den Test einzelner Auftragskarten die Karte zuerst in den sichtbaren Bereich der Warteschlange scrollen. Nach dem Klick auf «Pausieren» den gespeicherten Zustand und den weiteren Fortschritt der übrigen Aufträge prüfen. Anschliessend «Fortsetzen» einmal auslösen. Beim Mac-Nachtest beendete ein zweiter Aufruf des Prüftreibers die Test-App, nachdem die erste Bedienaktion bereits angenommen war. Beim erneuten Öffnen standen alle vier ursprünglichen Aufträge mit denselben IDs und Zwischenständen bereit. Nach «Alle fortsetzen» schrieben alle vier über ihre gespeicherten Prüfpunkte hinaus. Danach bestand der Test an einer einzelnen sichtbaren Karte im selben App-Prozess. Der pausierte Auftrag prüfte beim Fortsetzen zunächst 794 gespeicherte Einträge und schrieb dann weitere Dateien. Die drei anderen Aufträge liefen weiter.

### Quelle und Ziel beim SMB-Fortsetzen unterscheiden

1. Einen Kopierauftrag mit einer eigenen SMB-Datei und separater Kontrolldatei anlegen. Den SHA-256 der Quelle ausserhalb der App erfassen. Mit einem Testadapter nach vollständig gespeicherten Dateibytes und vor dem Abschlussbeleg pausieren. Quelle und Ziel müssen zu diesem Zeitpunkt denselben Hash haben.
2. In einem Lauf ein Byte der eigenen Quelle ändern, im zweiten Lauf ein Byte des eigenen Ziels. Die Grösse jeweils beibehalten. Die drei Prüfsummen vor dem Fortsetzen erfassen.
3. Denselben Auftrag fortsetzen. Beide Läufe müssen ohne Abschlussbeleg stoppen. Bei geänderter Quelle darf das bytegenaue Ziel nicht als fehlerhafte Datei ausgegeben werden. Bei geändertem Ziel muss der betroffene Zielpfad als fehlerhaft erscheinen, sofern der Windows-Build einen Pfadhinweis anzeigt. OpenCommander darf keine der beiden Dateien ändern. Die Prüfsummen von Quelle, Ziel und Kontrolldatei erneut ausserhalb der App vergleichen.

### SMB-Wiederherstellungsplan gegen die Historie prüfen

1. Auf einer eigenen SMB-Testfreigabe einen Ordner mit einer Unicode-Datei, einem weiteren Dokument und einem leeren Unterordner anlegen. Relative Pfade und SHA-256-Prüfsummen unabhängig erfassen. In OpenCommander löschen und den Historieneintrag prüfen.
2. Mit einem Testadapter bei «Rückgängig» nach der Bestätigung des Historiennachweises einen abweichenden Lesewert für eine Testdatei derselben Länge liefern. Den Lauf zusätzlich mit einem älteren Testjournal wiederholen, dessen gespeicherter Hash vom Historiennachweis abweicht. Für die Neustartvariante den Testprozess bei bestehendem Journal beenden und mit demselben Testprofil öffnen.
3. Eine neu gelesene Abweichung muss vor dem Anlegen des Plans stoppen. Bei einem bereits teilweise ausgeführten Plan die nächste Datei in getrennten Läufen einmal fehlen lassen und einmal durch eine eigene Markierungsdatei belegen. Nur im ersten Lauf darf «Rückgängig» die erwartete Prüfsumme aus der bestätigten Historie übernehmen. Die vorhandenen Dateien müssen vor weiteren Nutzdaten geprüft werden. Der belegte Name, der Wiederherstellungsordner und ein unabhängiger pausierter Auftrag bleiben erhalten. Den betroffenen Inhalt separat vollständig lesen und mit der ursprünglichen Liste und dem gespeicherten Plan vergleichen.
4. Mit dem Testadapter nach der gespeicherten Plankorrektur erneut unterbrechen. Beim Öffnen muss derselbe Auftrag die Korrektur anhand der Historie bestätigen und fortsetzen. Separat eine bereits wiederhergestellte Testdatei verändern und prüfen, dass die Fortsetzung vor weiteren Ausgaben stoppt. Bei konsistenten Daten müssen nach «Rückgängig» alle Dateien und der leere Unterordner am Originalpfad liegen. Prüfsummen, Historie und Meldung dokumentieren.

### Oberfläche bei einer verzögerten SMB-Pfadabfrage prüfen

1. Die Windows-Testinstanz mit einer eigenen SMB-Freigabe links und einem lokalen Testordner rechts öffnen. Die Freigabe muss erreichbar sein. Beide Ausgangspfade und je eine Markierungsdatei erfassen.
2. Nur die isolierte Testverbindung während einer Ordnerbaum-Abfrage verzögern. Den Test mit der bereits geöffneten App und mit Wiedereröffnung beider Orte ausführen. Wartezeit der SMB-Abfrage und Reaktionszeit der Bedienelemente separat messen.
3. Während der SMB-Ordner lädt, rechts einen lokalen Ordner öffnen und filtern. Die lokale Liste und Bedienelemente müssen reagieren. Den verzögerten Bereich zu einem lokalen Pfad wechseln, die Testverbindung wieder freigeben und prüfen, dass die frühere Antwort den neuen Pfad nicht überschreibt.
4. In einem getrennten Lauf einen gültigen Ordneralias mit Sonderzeichen wählen. Die Anzeige soll den gewählten Pfad behalten und der Baum nach der Auflösung zum passenden Ordner springen.

### Eingegebenen Netzpfad während der Prüfung ersetzen

1. Beide Paneele einer Testinstanz in lokalen Testordnern öffnen. Rechts zwei Dateien mit unterscheidbaren Namen anlegen. Einen bisher in dieser Instanz nicht geöffneten Ordner einer eigenen Testfreigabe vorbereiten.
2. Nur die Testfreigabe verzögern und ihren Pfad links eingeben. Während die Abfrage wartet, rechts einen Dateinamen filtern. Das Fenster muss reagieren und nur den passenden Treffer anzeigen.
3. Links einen anderen lokalen Ordner eingeben und seine Markierungsdatei prüfen. Erst dann die Testfreigabe wieder freigeben. Nach ihrer Antwort muss links weiterhin der zuletzt gewählte lokale Ordner stehen. Rechts müssen Pfad und Filter erhalten bleiben.
4. Den Netzpfad bei erreichbarer Testfreigabe erneut öffnen. Getrennt einen gültigen Archivpfad, eine gewöhnliche Datei und einen fehlenden Pfad prüfen. Den sichtbaren Ordner oder die jeweilige Fehlermeldung erfassen.

### Start mit gespeichertem Netzordner prüfen

1. In einem eigenen Testprofil links einen Ordner auf einer Testfreigabe öffnen und rechts einen lokalen Ordner mit zwei unterscheidbaren Dateien. Die App beenden und die gespeicherten Pfade dokumentieren.
2. Nur die Testfreigabe verzögern und die App neu starten. Das Fenster und der rechte Ordner müssen sofort bedienbar sein. Rechts einen Dateinamen filtern, während links die Abfrage wartet.
3. Die Abfrage enden lassen, ohne einen anderen linken Ordner zu wählen. Wenn links ein Ausweichordner erscheint, muss der gespeicherte Netzpfad für den nächsten Start erhalten bleiben. Die Freigabe wieder freigeben und mit demselben Profil erneut starten. Links muss der gespeicherte Netzordner wieder öffnen.
4. In einem frischen Lauf den Netzordner und den lokalen Ordner als Startargumente übergeben. Während der Netzpfad wartet, muss der lokale Pfad im richtigen Paneel laden. Einen anderen lokalen Pfad wählen, die Freigabe wieder freigeben und prüfen, dass die alte Antwort diesen Pfad nicht ersetzt.

### Ordnerübergabe aus einer zweiten Instanz prüfen

1. Eine Testinstanz mit zwei lokalen Testordnern öffnen. In einer eigenen Testfreigabe einen weiteren Ordner anlegen. Nur diese Freigabe verzögern.
2. Die App mit demselben Testprofil und dem verzögerten Ordner erneut aufrufen. Die zweite Instanz muss die Übergabe abschliessen. Die bestehende Instanz muss bedienbar bleiben und darf bis zur erfolgreichen Prüfung keine Dateien des Netzordners anzeigen.
3. Im anderen Paneel eine Datei filtern. Danach im Paneel mit der wartenden Anfrage einen neuen lokalen Ordner öffnen. Die Freigabe wieder freigeben und prüfen, dass die ältere Anfrage den neuen Ordner nicht ersetzt.
4. Einen verfügbaren Ordner über die Shell an die laufende Testinstanz übergeben. Separat eine gewöhnliche Datei und einen fehlenden Ordner prüfen. Ungeeignete Pfade müssen eine sichtbare Meldung ergeben. Im Testprofil darf nur eine Instanz schreiben.

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
| Belastung und Pfadreservierung | Mehrere Aufträge mit unabhängigen Zielen starten. Eine Kopie pausieren und eine Löschung derselben Quelle sowie eine unabhängige Löschung anfordern. Prüfen, dass nur die erste Löschung wartet. Die Kopie abbrechen, beide Löschungen nach Abschluss einzeln rückgängig machen und alle Prüfsummen vergleichen. Laufzeit und freien Speicher erfassen. Für JOB-05 drei unabhängige Ziele verwenden. Beim Pausieren und Abbrechen die Zeit vom Klick bis zur ersten sichtbaren Statusänderung erfassen. Build 306 bestand den Ablauf mit APFS-Quelle und SMB-Ziel. Nach beiden Rückgängig-Aktionen stimmten am Originalpfad alle 20’004 Dateien und 107 Unterordner mit dem Manifest überein. Bei der Variante mit langsamer SMB-Quelle wurde die wartende Löschung erfolgreich freigegeben und ihr Wiederherstellungsbestand geprüft. Die Wiederherstellung am ursprünglichen SMB-Pfad stoppte nach 7’001 Dateien mit widersprüchlichen Prüfsummen im Plan. Der [separate Wiederherstellungstest](#smb-wiederherstellungsplan-gegen-die-historie-prüfen) beschreibt den Nachtest. |

### Kalter und warmer Cloud-Ordnerabruf (CLOUD-01)

In einem frischen Testprofil einen eigenen Cloud-Ordner mit einer Testdatei auf oberster Ebene und einer anderen Datei in einem Unterordner öffnen. Die Zeit vom Klick bis zur richtigen Dateiliste erfassen. Dann den Unterordner öffnen, mit «Zurück» zum Hauptordner wechseln, den Cloud-Bereich schliessen und denselben Ort erneut öffnen. Kalten Erstabruf und warmes Wiederöffnen separat protokollieren. Ladeanzeige, Möglichkeit zum Schliessen und die unveränderte Ansicht im zweiten Bereich prüfen. Objekt-IDs und Dateiinhalte unabhängig beim Anbieter vergleichen.

Im signierten Mac-Build 322 lagen die gemessenen Zeiten inklusive Bedienautomation bei Dropbox bei 3,13 s für den Erstabruf und 1,95 s für das Wiederöffnen. Bei Google Drive waren es 2,93 s und 1,91 s. Die Werte beschreiben den Testaufbau.

Für den Abbruchnachtest den Listenabruf eines eigenen Testordners gezielt verzögern. Während die Ladeanzeige sichtbar ist, den Cloud-Bereich schliessen. Der lokale Ordner muss sofort wieder erreichbar sein. Sobald der verzögerte Abruf beendet ist, darf keine alte Cloud-Liste die lokale Ansicht ersetzen. Denselben Cloud-Ort erneut öffnen und die Dateiliste unabhängig prüfen.

### Verzögerter Abruf in beiden Bereichen (CLOUD-07)

Den ersten Abruf des eigenen Cloud-Ordners anhalten und denselben Ort rechts öffnen. Beide Bereiche müssen den Ladezustand zeigen. Links den Cloud-Bereich schliessen und prüfen, dass links wieder der lokale Ordner und rechts weiterhin die Ladeanzeige erscheint. Den Abruf freigeben. Die Cloud-Dateien müssen nur rechts erscheinen.

Den Ort danach in beiden Bereichen öffnen und mit einem zweiten Client eine neue Testdatei anlegen. Manuell links aktualisieren, den Abruf verzögern und rechts ebenfalls aktualisieren. Sobald beide Bereiche laden, den Abruf freigeben. Die neue Datei muss in beiden Listen erscheinen. Falls der Testaufbau Anbieteraufrufe protokolliert, die Zahl der Listenabrufe während der Überlappung erfassen. Build 322 bestand beide Varianten mit Dropbox und Google Drive.

### Anmeldewiederherstellung mit abgelehntem Cloud-Token (CLOUD-05)

1. In einem separaten Testprofil einen eigenen Dropbox- oder Google-Drive-Ordner mit einer Testdatei einrichten. Deren Objekt-ID und SHA-256-Prüfsumme unabhängig erfassen. Im zweiten Bereich einen lokalen Testordner öffnen.
2. In einer Kopie der Testkonfiguration ein absichtlich ungültiges Token ohne funktionierendes Erneuerungstoken hinterlegen. Diese Verbindung öffnen. Der betroffene Bereich muss zur Wiederverbindung auffordern und darf keine Dateiliste als aktuell anzeigen. Der lokale Bereich muss bedienbar bleiben.
3. Über die App die gültige Testkonfiguration erneut auswählen und prüfen lassen. Die erwartete Datei muss wieder erscheinen. Objekt-ID und Prüfsumme erneut unabhängig vergleichen.

Der signierte Mac-Build 322 bestand diese Variante mit echten Anbieterantworten für Dropbox und Google Drive. Für den vollständigen Fall den Token-Widerruf am dedizierten Testkonto aus der CSV und die weiteren Anbieter separat prüfen.

### Cloud-Dateiaktionen nach App-Neustart rückgängig machen (CLOUD-03, TRASH-05)

1. In einem eigenen Cloud-Testordner zwei Dateien mit unterschiedlichen Inhalten ablegen. Objekt-IDs und SHA-256-Prüfsummen mit einem zweiten Client erfassen.
2. In der App einen leeren Ordner anlegen, eine Datei umbenennen und eine Datei in die Cloud-Wiederherstellung verschieben. Die drei Aktionen in separaten Durchläufen prüfen. Den jeweiligen Zwischenzustand direkt beim Anbieter bestätigen.
3. Die App nach jeder Aktion neu starten und den zugehörigen Historieneintrag rückgängig machen. Der neu angelegte Ordner muss aus der normalen Ansicht verschwinden. Nach Umbenennen und Wiederherstellung müssen ursprünglicher Name, Objekt-ID und Prüfsumme wieder stimmen. Die unabhängige Kontrolldatei muss unverändert sein.

Der signierte Mac-Build 322 bestand alle drei Varianten mit echten Dropbox- und Google-Drive-Testordnern. Nach dem Rückgängigmachen der Ordneranlage liess sich derselbe leere Ordner im Wiederherstellungsbereich nachweisen.

## Ergebnis festhalten

Pro Fall den Windows-Build, den Status, die Abweichung vom Soll und einen Beleg erfassen. Bei einem Fehler in «Fehler-ID» die ID des Windows-Issues eintragen und dort die Variante, Reproduktionsschritte, Uhrzeit und genaue Meldung festhalten. Die passende Mac-Regressions-ID kann im Windows-Issue als Referenz angegeben werden.

| Fall | Build / Umgebung | Ergebnis | Beleg oder Fehler |
| --- | --- | --- | --- |
| Dropbox → Google Drive, Ersetzen, Fortsetzen, Rückgängig |  |  |  |

Die macOS-Live-Läufe mit Builds 101 und 102 haben Wiederaufnahme und Rückgängig bis zum unabhängigen Nachweis beider ursprünglichen Anbieter-IDs und Prüfsummen abgeschlossen. Build 101 wurde nach einem Anbieter-Zeitlimit wiederaufgenommen, Build 102 nach einer manuellen Pause. Der Windows-Nachweis steht aus. [Mac-Testprotokoll](mac-dropbox-google-drive-build101-2026-11-12.md)

### Natives Google-Dokument mit «Öffnen mit …» exportieren

1. Im eigenen Google-Drive-Testordner ein natives Google-Dokument mit einem kurzen Text anlegen, der Umlaute und japanische Zeichen enthält. Dateinamen und Dokument-ID erfassen.
2. Im Online-Bereich des Dateimanagers per Rechtsklick «Öffnen mit …» wählen. Den angebotenen DOCX-Export im eigenen lokalen Testordner speichern. Dateiname mit Endung prüfen und den Inhalt im gespeicherten Dokument lesen.
3. Die App-Auswahl einmal abbrechen. Die gespeicherte Kopie muss weiterhin vorhanden sein. In einem separaten Durchgang eine verfügbare DOCX-Anwendung wählen und prüfen, dass sie genau die gespeicherte Kopie öffnet.
4. Den Anbieterordner separat neu laden. Dokument-ID und Text mit dem Ausgangsstand vergleichen und bestätigen, dass das Original weiterhin ein natives Google-Dokument ist.

Der sichtbare Mac-Nachtest in Build 321 bestätigte den Export bis zur App-Auswahl und deren Abbruch. Eine unabhängige Prüfung des DOCX-Archivs bestätigte den vollständigen Testtext. Die Google-ID und das native Original blieben erhalten.

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
