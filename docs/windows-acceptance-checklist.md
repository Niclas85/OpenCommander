# OpenCommander auf Windows prüfen

Referenz ist die macOS-Abnahme von OpenCommander. Die Windows-Ergebnisse werden beim eigenen Durchlauf eingetragen. WebDAV gehört nicht zu diesem Durchlauf.

## Vollständige Prüfliste

- [158 Prüffälle für Windows](windows-acceptance-cases.csv) enthält pro Fall Voraussetzungen, Schritte, Soll und Felder für Build, Status, Ist-Ergebnis, Beleg und Fehler-ID. In Excel über **Daten → Aus Text/CSV** als UTF-8 mit Semikolon importieren. Der Windows-Status startet bei «Nicht ausgeführt».
- [Mac-Ergebnisse nach Fall-ID](macos-acceptance-findings-for-windows.json) enthält die dokumentierten Beobachtungen und die jeweilige Zahl der Belegverweise. Am 20. November 2026 waren 108 Fälle nativ belegt, 43 teilweise belegt und 7 von einer fehlenden Testumgebung abhängig.
- [126 gezielte Regressionsnachtests](windows-regressions-from-macos.md) beschreiben die Mac-Befunde und das erwartete Windows-Verhalten. Die Spalte «Mac-Regressionen» verweist aus der CSV auf diese Nachtests. Mehrere Fälle können auf dieselbe Regression verweisen. Zusätzliche Einzelbefunde stehen im Mac-Protokoll. Die Zahl zählt Nachtests. Sammelbefunde können mehrere Fehler enthalten.

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

### Cloud-Ordner bei gesperrter Kontokonfiguration prüfen (REG-CLOUD-37)

1. In einem eigenen Cloud-Testprofil einen bereits geladenen Ordner öffnen. Die Kontokonfiguration mit einem Testadapter sperren, bevor die nächste Ordnerliste den Anbieter erreicht. Dieselbe Ansicht in beiden Bereichen aktualisieren. Einen Bereich verlassen und die Sperre dann freigeben. Die andere Ansicht muss dieselbe aktuelle Liste über genau einen Anbieterabruf erhalten.
2. Die Sperre erneut halten. Den einzigen wartenden Bereich verlassen. Der Testadapter muss den Abbruch der wartenden Kontoprüfung melden. Der andere Prozess muss die Sperre weiterhin halten können.
3. Mit weiter gehaltener Sperre einen Zeitablauf auslösen. Die Fehlermeldung muss «Erneut versuchen» anbieten. Anbieterabruf und Anmeldeaufforderung bleiben aus. Die Sperre freigeben, erneut abrufen und die aktuelle Liste sowie unveränderte Cloud-Objekte unabhängig prüfen.

Der Code von Mac-Build 421 nutzt für die Kontoprüfung eine Frist von 30 Sekunden pro Prüfung. Mit verkürzter Frist im Live-Test bestanden Google Drive und Dropbox alle drei Varianten bei einer real gehaltenen Konfigurationssperre. Der überlebende Abruf und die spätere Wiederholung lieferten je eine frische Liste. Unabhängige Anbieterabrufe bestätigten dieselben Datei-IDs und Inhalte. Ein separater Regressionstest prüfte, dass der Timeout keine sofortige Aktualisierung auslöst. Der Live-Lauf verwendete die Anwendungslogik ohne App-Fenster.

### Verspätete Cloud-Ordnerantwort prüfen (REG-CLOUD-39)

1. Einen eigenen Testordner in Google Drive und Dropbox mit einer Datei öffnen. Namen, Datei-ID und Inhalt unabhängig abrufen. Den Ordner in beiden App-Bereichen laden.
2. Beide Ansichten aktualisieren. Der Testadapter hält die nächste Anbieterantwort zurück und bestätigt den Abbruch vorerst nicht. Beide Ansichten müssen nach der Lesefrist dieselbe datierte Ersatzliste mit Warnung und Wiederholhinweis anzeigen. Genau einen gemeinsamen Anbieterabruf zählen.
3. Innerhalb der Wartezeit erneut aktualisieren und den unveränderten Zähler prüfen. Nach der Wartezeit erneut laden. Die aktuelle Liste muss erscheinen, während die alte Antwort noch zurückgehalten wird.
4. Die alte Antwort freigeben. Die aktuelle Liste und den Warnstatus erneut prüfen. Anbieterseitig müssen Datei-ID und Inhalt den Ausgangswerten entsprechen. Für den Test ohne vorherige Liste zusätzlich eine wiederholbare Fehlermeldung erwarten.

Mac-Build 424 nutzt im normalen Betrieb 30 Sekunden für den eigentlichen Ordnerabruf. Im Live-Nachtest mit einer auf 8 Sekunden verkürzten Frist bestanden Google Drive und Dropbox den Ablauf mit vorhandener Liste. Die beiden Aufrufer erhielten sie nach 8,122 bzw. 8,133 Sekunden. Der Nachtest verwendete die Anwendungslogik mit echten Anbieterantworten. Build 425 meldete ohne vorherige Liste bei beiden Anbietern nach 8,399 bzw. 8,510 Sekunden Zeitlimit-Fehler mit Wiederholhinweis. Der erste erfolgreiche Abruf war fertig, während die ursprüngliche Antwort noch zurückgehalten wurde.

### Cloud-Zeitlimit bei unveränderter Systemzeit prüfen (REG-CLOUD-40)

1. In einem eigenen Testprofil einen Cloud-Unterordner ohne gespeicherte Dateiliste öffnen. Im Testadapter nur die Uhr für Zeitstempel anhalten. Die Uhr des Rechners muss dafür nicht geändert werden.
2. Die Antwort des ersten Listenabrufs zurückhalten, auch wenn die App den Abbruch anfordert. Nach dem Zeitlimit muss eine Meldung mit Wiederholhinweis erscheinen. Genau einen Anbieterabruf zählen.
3. Während der Wartefrist erneut öffnen. Die App muss dieselbe Fehlermeldung ohne Dateiliste und ohne weiteren Abruf liefern. Die Testuhr bis zum Ende der Wartefrist vorsetzen.
4. Den Ordner erneut öffnen und die aktuelle Liste anzeigen lassen. Die zurückgehaltene Antwort erst danach freigeben. Ein weiterer Abruf muss dieselben aktuellen Dateieinträge liefern. Datei-ID und Inhalt unabhängig beim Anbieter prüfen.

Im Live-Vergleich benötigte Build 424 bei angehaltener Testuhr 12,362 Sekunden und zwei Google-Drive-Abrufe. Nach der Korrektur antwortete Build 425 bei einer Prüffrist von 8 Sekunden nach 8,399 Sekunden für Google Drive und 8,510 Sekunden für Dropbox. Der Nachtest verwendete die Anwendungslogik mit echten Anbieterantworten.

Im Fenster des isolierten Mac-Builds 425 zeigte ein simulierter OneDrive-Abruf über rclone nach 30,159 Sekunden die Zeitlimit-Meldung mit Schaltfläche und Countdown. Eine Datei im lokalen Bereich liess sich per Mausklick auswählen. Der automatische Wiederabruf zeigte die erste aktuelle Dateiliste. Der Testadapter zählte genau einen ursprünglichen Abruf und genau einen Wiederabruf.

Mit demselben Testadapter startete Befehl-R für beide Cloud-Ansichten einen gemeinsamen Abruf. Nach 30,31 Sekunden zeigten beide dieselbe datierte Ersatzliste mit Zeitlimit-Warnung und Countdown. Ein Klick auf Schliessen führte links in den lokalen Ordner zurück. Nur der rechte Bereich zeigte nach genau einem automatischen Wiederabruf die neue Datei. In beiden Läufen blieben die Kontrolldateien und die leere Historie unverändert.

### Ausbleibende OneDrive-Freigabebestätigung prüfen

1. In einem separaten Testprofil mit einer eigenen Datei den Freigabedialog öffnen und abbrechen. Der Testadapter muss null Freigabeanfragen sehen.
2. Die Freigabe ausdrücklich bestätigen. In getrennten Läufen den Testadapter erst den Versand annehmen und anschliessend die Verbindung unterbrechen, mit HTTP 503 antworten oder eine unbrauchbare Linkbestätigung liefern lassen. Die App muss darauf hinweisen, dass der Freigabelink beim Anbieter bereits aktiv sein kann. Für jeden Lauf genau eine Anfrage zählen. Der Dialog darf keinen Link zum Kopieren oder Öffnen anbieten.
3. Die Kontrollläufe mit einer gültigen Bestätigung, HTTP 429 und HTTP 403 wiederholen. Die App muss den bestätigten Link anbieten beziehungsweise die Drosselung oder fehlende Berechtigung erklären.

Die sechs Antwortvarianten bestanden im Mac-Nachtest mit simulierten Microsoft-Graph-Antworten. Der frühere Zustand zeigte bei Verbindungsverlust und HTTP 503 keinen Hinweis auf eine mögliche Freigabe. Die sichtbare Prüfung mit einem echten OneDrive-Testkonto steht noch aus.

### Unklaren Ausgang eines rclone-Freigabeversuchs prüfen

1. Eine eigene Datei im separaten Testprofil auswählen. Das Kontextmenü zuerst nur öffnen, dann den Freigabedialog öffnen und abbrechen. Der Adapter muss bis dahin null Linkanfragen sehen.
2. In separaten Läufen den Linkversuch ausdrücklich bestätigen. Sobald das rclone-Kommando gestartet ist, den Testadapter eine Zeitüberschreitung, einen Verbindungsabbruch oder HTTP 503 melden lassen. Der Fehler muss den Hinweis enthalten, dass beim Anbieter bereits ein Link bestehen kann. Keine URL zum Kopieren oder Öffnen, kein automatischer Wiederholungsversuch.
3. Als Gegenprobe vor dem Kommando abbrechen sowie HTTP 401 und 429 auslösen. Die jeweilige Abbruch-, Anmelde- oder Drosselungsmeldung prüfen. Prüfsumme der ursprünglichen Datei kontrollieren.

Der rclone-Weg zeigte bei einem Ausfall nach Start des Freigabebefehls bisher nur den allgemeinen Fehler. Build 392 gibt zusätzlich an, dass beim Anbieter bereits ein Link bestehen kann. Der Test mit einem eigenen rclone-Hilfsprozess prüfte Zeitüberschreitung, Verbindungsabbruch, HTTP 503 und unbestimmten Ausgang. HTTP 401 und 429 behielten ihren eigenen Fehler. Die kontrollierte Cloud-Datei blieb bytegenau, und der Client sendete genau einen Linkversuch. Im signierten Build 392 öffnete das native Kontextmenü die Freigabebestätigung für genau die angeklickte Testdatei. Menüöffnung und Abbrechen erzeugten ausschliesslich Lesezugriffe. Beide Dateibereiche blieben verfügbar. Die lokalen und simulierten Cloud-Dateien blieben bytegenau. Die Historie blieb leer. Bei zwei ausgewählten Dateien bot das Kontextmenü keine öffentliche Freigabe an.

Für die sichtbare Wiederholung nach dem Start der Anfrage zusätzlich die Fortschrittsanzeige prüfen. Einmal während des laufenden Versuchs abbrechen. Die Warnung muss auch hier erklären, dass ein Link bestehen bleiben kann. Mit einer bestätigten, erlaubten HTTPS-Adresse muss die App Kopieren und Öffnen anbieten. Bei unklarem oder abgelehntem Ausgang fehlen diese Linkaktionen.

Vier sichtbare Durchläufe im isolierten Mac-Testbuild 394 ergänzten die Prozess- und Client-Prüfungen. Nach Timeout und nach Abbrechen eines bereits gestarteten Auftrags erschien der Hinweis auf einen möglicherweise aktiven Link. Die Drosselungsmeldung erschien ohne diesen Zusatz. Nur bei bestätigter Antwort bot die App «Link kopieren» und «Link öffnen» an. Jeder Lauf erzeugte genau einen Linkversuch. Die Kontrolldateien blieben bytegenau und die Historie leer. Die Antworten waren simuliert. Der entsprechende Test mit einem echten Anbieterkonto bleibt offen.

### Browser-Anmeldung ablehnen, abbrechen und erneut starten (AUTH-03)

1. In einem eigenen Testprofil eine Verbindung einrichten. Den Testadapter in separaten Läufen eine ausdrückliche Ablehnung der Browser-Anmeldung oder einen Ablauf melden lassen. Die App muss den jeweiligen Grund und den Weg zu einer neuen Anmeldung anzeigen. Vor dem nächsten Anlauf prüfen, dass keine Verbindung gespeichert wurde.
2. Den vorigen Anlauf im Assistenten abbrechen, während der Testserver noch wartet. Die ausstehende Antwort erst danach ausliefern. Der geschlossene Assistent darf dadurch weder wieder erscheinen noch eine Verbindung speichern.
3. Je Testlauf eine neue Anmeldung beginnen und nur die neue Antwort bestätigen. In den Einstellungen muss genau die neu bestätigte Verbindung vorhanden sein. Ein alter Browser-Tab darf den neuen Anlauf nicht abschliessen. Fehlermeldungen und Belege dürfen keine Providerdetails mit Anmeldedaten enthalten.

Die rclone-Rückgabe führt den Ablehnungsgrund der Browser-Anmeldung in einem eigenen Feld innerhalb der Fehlerbeschreibung. [rclone-Implementierung](https://github.com/rclone/rclone/blob/master/lib/oauthutil/oauthutil.go#L1078-L1093)

Im signierten Mac-Build 357 erschien die Ablehnung als unvollständige Einrichtung. Build 358 zeigte Ablehnung und Ablauf getrennt an. Eine nach dem Abbruch gelieferte Antwort wurde verworfen. In allen drei Varianten speicherte erst der nächste bestätigte Anlauf eine Verbindung und öffnete deren Testordner. Die Oberfläche wurde mit einem simulierten Anbieter geprüft. Separate Tests mit einem lokalen OAuth-Callback wiesen nach, dass der nächste Anlauf nur den eigenen Anmeldestatus akzeptiert. Die erneute Freigabe bei Microsoft bleibt ein Live-Test.

### Persönlichen OneDrive-Speicher auswählen (AUTH-04)

1. In einem separaten Profil mit einem Testkonto oder einem Testadapter mehrere Laufwerke anbieten. Den technischen Speicher zuerst und den persönlichen OneDrive-Speicher später in der Liste liefern. Für beide Einträge eindeutige Testdateien verwenden. Der Assistent muss den persönlichen Speicher kennzeichnen und bevorzugt anzeigen.
2. Die Auswahl ausdrücklich bestätigen. Prüfen, ob die Testdatei des gewählten Laufwerks sichtbar ist. Die App schliessen und das gespeicherte Profil erneut öffnen. Die Konfiguration muss dieselbe Laufwerks-ID enthalten und wieder die Testdatei desselben Laufwerks zeigen.
3. Die Einrichtung mit ausschliesslich technischen Einträgen sowie mit mehreren gleich bezeichneten persönlichen Einträgen wiederholen. Vor der ausdrücklichen Auswahl darf keine Laufwerks-ID als Antwort gesendet werden. Eine manuell gewählte technische Bibliothek muss sich weiterhin verbinden lassen.

Im sichtbaren Vergleich mit demselben Testadapter wählte Build 356 die zuvor angebotene technische Bibliothek vor. Build 357 zeigte den persönlichen Speicher als Empfehlung, öffnete nach Bestätigung die richtige Testdatei und verwendete nach dem Neustart dieselbe Laufwerks-ID. Im zweiten Lauf sandte «Weiter» bei leerer Auswahl keine Laufwerks-ID. Nach manueller Wahl der Bibliothek bestand auch sie den Neustart. Die Prüfung mit einem echten Konto und mehreren Microsoft-Laufwerken steht aus. [Auswahlformat im rclone-Backend](https://github.com/rclone/rclone/blob/master/backend/onedrive/onedrive.go)

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

### Cloud-Ordner auf SMB kopieren (FILE-12)

1. D1 mit einer lesbaren JPEG- und einer WebP-Datei, einer versteckten Datei und einem leeren Unterordner in einem eigenen Cloud-Testordner vorbereiten. Die Cloud-Objekt-IDs und das Manifest aus relativen Pfaden, Typen, Grössen und SHA-256 erfassen.
2. Den Ordner auf eine eigene SMB-Freigabe kopieren. In einer separaten Nur-Lese-Verbindung die Ordnerstruktur und alle Prüfsummen mit dem Manifest vergleichen. Beide Bilder im Ziel öffnen. Danach im selben OpenCommander-Profil nach Neustart «Rückgängig» wählen. In der separaten Verbindung müssen der Zielordner fehlen und die Kontrollmarkierung erhalten bleiben. Beim Cloud-Anbieter müssen IDs und Inhalte unverändert sein.
3. Mit einem instrumentierten Testadapter zwei Fehler am SMB-Ziel getrennt auslösen. Meldet der Server eine optionale Metadatenoperation als nicht unterstützt, müssen belegte Nutzdaten und ein Hinweis auf die Einschränkung erhalten bleiben. Bei einem echten E/A-Fehler beim Sichern der Nutzdaten muss der Auftrag ohne Erfolgsbeleg und ohne erfolgreichen Historieneintrag stoppen. Danach die E/A-Störung entfernen und denselben Auftrag fortsetzen. Erst nach unabhängiger Prüfung den endgültigen Abschluss erfassen.

Im Mac-Nachtest vom 20. November 2026 gelang die Kopie von Google Drive und Dropbox auf eine echte SMB-Freigabe mit je 35 Dateien und fünf Unterordnern. Der Testadapter simulierte `ENOTSUP` für Zeitstempel und das Sichern der Nutzdaten. Die gespeicherten Abschlüsse behielten die Hinweise auf diese Einschränkungen. Ein separat ausgelöster `EIO` stoppte je einen Auftrag vor dem Erfolgsbeleg. Ohne Störung liessen sich dieselben Aufträge abschliessen. Frische Nur-Lese-SMB-Verbindungen bestätigten beide Zielbäume pro Anbieter anhand vollständiger Manifeste. Nach «Rückgängig» aus der gespeicherten Historie blieben je die zweite Kopie, die Kontrollmarkierung sowie alle Cloud-Objekte mit denselben IDs und Bytes erhalten. Die Läufe prüften die Übertragungslogik und das Dateisystem. Die sichtbare Bedienung auf SMB steht noch aus.

Im Fenstertest vom 20. November 2026 kopierte Build 426 per F5 alle 35 Dateien und fünf Unterordner aus Google Drive auf APFS. Der gespeicherte Cloud-Beleg gehörte zum ursprünglichen Auftrag und die Historie enthielt genau einen Kopiereintrag. Der unabhängige Vergleich prüfte alle Pfade und SHA-256-Werte. JPEG und WebP liessen sich vollständig dekodieren. Nach einem Neustart der Test-App entfernte «Rückgängig» den Zielordner. Die Kontrolldatei blieb bytegenau und ein separater Anbieterabruf bestätigte dieselben Cloud-IDs und Inhalte. Anschliessend wurde der eigene Cloud-Testordner entfernt.

Beim Versuch auf der echten SMB-Freigabe war derselbe Cloud-Ordner sichtbar. Die Dateiliste des NAS-Ziels blieb aus. Die Prozessprobe zeigte wartende Dateivorgänge in `stat` und `getattrlistbulk`. Der Test schickte deshalb keinen Kopierbefehl. Der isolierte Auftragspeicher und die Historie enthielten keinen Transfer. Der sichtbare SMB-Lauf bleibt offen.

Für die Gegenprobe zu REC-10 zwei verschiedene Testvolumes und einen kleinen Ordner mit zwei bekannten Dateien verwenden. Vor dem Start die SHA-256-Werte beider Dateien mit `Get-FileHash -Algorithm SHA256` erfassen.

1. Mit F6 in ein leeres Ziel verschieben. Nur mit einem Testadapter in einer isolierten Windows-Testinstanz gezielt unterbrechen, nachdem das Ziel geprüft und der Zustand gespeichert wurde und bevor die Quelle weggelegt wird. Die Test-App im selben Profil öffnen. Der ursprüngliche Auftrag muss noch auf «Fortsetzen» warten. Zu diesem Zeitpunkt müssen beide sichtbaren Ordner die ursprünglichen Prüfsummen haben.
2. Unveränderte Quelle fortsetzen. Genau ein Verschiebeeintrag muss erscheinen. «Rückgängig» muss die Quelle bytegenau wiederherstellen und den sichtbaren Zielordner entfernen.
3. Den Lauf mit neuen Testdateien wiederholen. Bei geschlossener Test-App ein Byte an der Quelle ändern und die ursprüngliche Änderungszeit wiederherstellen. Die Dateigrösse muss gleich bleiben. Nach «Fortsetzen» muss der Auftrag stoppen. Unter «Details» muss eine Integritätsmeldung erscheinen. SHA-256 muss die geänderte Quelle und das unveränderte Ziel bestätigen. Es darf keinen erfolgreichen Historieneintrag geben.

Die Mac-App bestand diese beiden Varianten mit Debug-Build 395 und einem über FSKit eingebundenen NTFS-Abbild.

Für REC-10 einen Verschiebeauftrag mit «Ersetzen» in einer isolierten Testinstanz vorbereiten. Falls ein Testadapter vorhanden ist, den Testprozess beenden, nachdem das Ziel verifiziert und die Quelle an den Wiederherstellungspfad verschoben wurde, aber bevor das Dateisystemjournal den Vorgang als abgeschlossen gespeichert hat. Der Auftrag darf seinen Abschluss noch nicht gespeichert haben. Am früheren Quellpfad eine neue Testdatei mit anderen Bytes anlegen. Nach dem Neustart muss der Auftrag den Konflikt melden. Die veröffentlichte Zieldatei, beide Originale im Wiederherstellungsbereich und die neue Datei müssen erhalten bleiben. Die neue Testdatei separat umbenennen, denselben Auftrag fortsetzen und «Rückgängig» ausführen. Der ursprüngliche Quell- und Zielinhalt muss wieder am jeweiligen Namen liegen. In beide Richtungen testen. Debug-Build 397 bestand diesen Ablauf in beiden Richtungen zwischen APFS und einem über FSKit eingebundenen NTFS-Abbild. Nach der ersten verweigerten Wiederaufnahme gab es keinen Abschlussbeleg und keinen Historieneintrag.

REC-10 und TRASH-06 zusätzlich direkt nach dem Festschreiben des Verschiebens prüfen. In beiden Richtungen zwischen den Testvolumes mit F6 und «Ersetzen» starten. Die isolierte Test-App nach dauerhaftem Speichern des Dateisystemzustands und vor dem Abschluss in der Warteschlange unterbrechen. Dann eine unabhängige Datei am früheren Quellpfad anlegen. Beim Fortsetzen muss derselbe Auftrag genau einen Verschiebeeintrag erzeugen und die neue Datei erhalten.

1. Auf «Rückgängig» klicken. Eine Integritätsmeldung muss erscheinen. Die neue Datei, das sichtbare Ziel und die beiden gesicherten Originale müssen ihre Prüfsummen behalten.
2. Die neue Datei umbenennen und «Rückgängig» am selben Eintrag wiederholen. Quelle und vorheriges Ziel müssen jeweils den ursprünglichen Inhalt zurückerhalten. Die unabhängige Datei muss unter ihrem neuen Namen erhalten bleiben. Der Verschiebeeintrag muss verschwinden.

Debug-Build 396 bestand diesen Ablauf in beiden Richtungen zwischen APFS und einem NTFS-Abbild.

Für SAFE-06 vier unabhängige Ziele und ein separates SMB-Testlaufwerk pro Auftrag verwenden. Einen Auftrag pausieren und ein anderes Testlaufwerk während eines aktiven Schreibvorgangs trennen. Die App muss den fehlenden Zielort melden und dessen Zwischenstand behalten. Die zwei unabhängigen Aufträge müssen weiterlaufen. Das getrennte Laufwerk erneut einbinden, beide unterbrochenen Aufträge fortsetzen und alle vier Ziele unabhängig prüfen. Ein macOS-Lauf mit vier Dateien zu je 160 MiB bestätigte diesen Ablauf. Für den Dauerlauf die vollständigen D2-Daten und mindestens zwei Stunden Laufzeit verwenden.

Zwischen der ersten und der letzten Beobachtung mit vier aktiven Aufträgen in Build 363 lagen 2 Stunden, 11 Minuten und 23 Sekunden. In dieser Zeit lagen auch die geplante Pause und die Trennung einer Einbindung. Jeder Auftrag meldete 20’004 geschriebene Dateien und anschliessende Zielprüfung. Ein Auftrag erkannte eine abweichende 2‑GiB-Zieldatei, speicherte ihren relativen Pfad und blieb ohne Abschlussbeleg. Zwei unabhängige Leseprüfungen nach frischer SMB-Einbindung bestätigten dasselbe einzelne abweichende Bit. Die Ursache und der Endnachweis für alle vier Aufträge bleiben offen.

An der betroffenen, eindeutig dem Testlauf zugeordneten Datei wurden das abweichende Byte und in einem separaten Versuch der ganze zugehörige 1‑MiB-Block mit den geprüften Quellbytes geschrieben. Der Vergleich am offenen Dateihandle war jeweils erfolgreich. Nach Schliessen und erneuter SMB-Einbindung war dasselbe Bit abweichend. Die App-Aufträge und ihre Journale blieben erhalten. Die Wiederaufnahme wurde nach diesem Befund nicht ausgelöst.

Eine spätere Nur-Lese-Stichprobe am selben Ziel verglich ohne Dateicache den 4‑KiB-Block an der bekannten Fehlerposition. Das abweichende Bit war weiterhin vorhanden. Das ursprüngliche Auftragsjournal hatte denselben SHA‑256-Wert und weiterhin keinen Abschlussbeleg. Die frühere lokale Testquelle war nach geprüfter Archivierung nicht mehr am ursprünglichen Pfad verfügbar. Für einen neuen Versuch mit wiederhergestellten Testdaten neue Aufträge anlegen und die Quelldateien vor dem Start vollständig gemäss Manifest prüfen.

Vor einem weiteren Dauerlauf die SMB-Quelldateien mit einer unabhängig erzeugten SHA-256-Liste vergleichen. Dazu die isolierte Freigabe neu verbinden und die Dateien auch ausserhalb von OpenCommander lesen. Ein neu vorbereiteter macOS-Testdatensatz scheiterte bei dieser Vorprüfung. Zwei zusätzliche vollständige Lesevorgänge mit unterschiedlichen Puffergrössen bestätigten zwei abweichende Bytes an denselben Positionen in einer 2-GiB-Quelldatei. Die Ursache ist offen. In Windows einen abweichenden Quelldatensatz als fehlgeschlagene Vorprüfung erfassen. Für die gezielte Gegenprobe eine eigene Quelldatei zwischen Pause und Fortsetzen verändern. OpenCommander muss den betroffenen Auftrag vor der Veröffentlichung stoppen und darf dafür keinen Abschluss verbuchen.

Die Wiederherstellung aus dem Archiv schuf einen weiteren isolierten SMB-Quelldatensatz. Der Archivstrom und die aus dem Archiv entpackten Inhalte aller 20’004 Dateien entsprachen dem Manifest. Die unabhängige Vorprüfung der gespeicherten Quelle stoppte bei `Large2GiB.bin`. Zwei frische Nur-Lese-Verbindungen lasen danach die gesamten 2 GiB mit derselben abweichenden Prüfsumme. Gegenüber der direkt aus dem Archiv gelesenen Fassung wichen die Bytes an den nullbasierten Positionen 1’007’042’908 und 2’092’733’017 jeweils um Bitmaske 0x02 ab. Ein separates Programm hatte die Quelle geschrieben. Der vorbereitete Vier-Aufträge-Lauf in der App wartete auf die Vorprüfung und wurde nicht gestartet.

Der vollständige unabhängige Vergleich auf SMB umfasste 20’004 Dateien und 107 Unterordner. Zwei Originaldateien wichen vom Manifest ab. Von zwei separat neu geschriebenen Testdateien bestand die 1‑GiB-Datei beide vollständigen Leseläufe. Die neue 2‑GiB-Datei zeigte in beiden frischen Nur-Lese-Verbindungen dasselbe abweichende Byte an Position 2’041’270’620. OpenCommander schrieb diese Dateien nicht. Der Dauerlauf bleibt offen. Auch nach dem gezielten, unmittelbar verifizierten Überschreiben des betroffenen 4‑KiB-Blocks zeigten zwei frische Nur-Lese-Verbindungen dieselbe Abweichung in der separaten 2‑GiB-Testdatei. Die SMB-Quelle wurde für den Dauerlauf nicht freigegeben.

Mit dem signierten Build 384 startete der Dauerlauf von einer lokal rekonstruierten APFS-Quelle. Der unabhängige SHA-256-Vergleich bestätigte alle 20’004 Dateien. Vier getrennte SMB-Zielverbindungen nahmen je den vollständigen Baum an. Das gezielt getrennte Ziel setzte mit derselben Auftrags-ID und Teildatei fort. Die Zwei-Stunden-Marke wurde in diesem Durchgang nicht erreicht.

In Build 384 stoppte einer der vier laufenden Aufträge bei der Zielprüfung einer 2‑GiB-Datei. Zwei vollständige unabhängige Nur-Lese-SMB-Verbindungen bestätigten dieselbe Abweichung an Dateiposition 1’873’781’084 (Blockposition 348, XOR 0x02). Die lokale Quelle entsprach dem SHA-256-Manifest. Für das betroffene Ziel gab es weder Abschlussbeleg noch Historieneintrag.

Bei der Wiederaufnahme von drei erhaltenen Aufträgen stoppte ein weiterer Auftrag bei der Prüfung der Teildatei. Zwei vollständige Lesevorgänge über unabhängige Nur-Lese-Verbindungen bestätigten in den 2’081’423’360 vorhandenen Bytes genau ein abweichendes Byte an Dateiposition 880’452’185 (Blockposition 601, XOR 0x02). Die gesamte lokale Quelle entsprach wieder dem Manifest. Für den gestoppten Auftrag gab es weder Abschlussbeleg noch Historieneintrag.

Der dritte Auftrag stoppte nach 20’004 geschriebenen Dateien bei der abschliessenden Prüfung derselben 2‑GiB-Zieldatei. Zwei neue Nur-Lese-Verbindungen bestätigten unabhängig genau ein abweichendes Bit an Dateiposition 129’179’996 (Blockposition 348, XOR 0x02). Die APFS-Quelle entsprach dem Manifest. Für den betroffenen Auftrag fehlten Abschlussbeleg und Historieneintrag. Der vierte Auftrag prüfte sein Ziel weiterhin. Die Ursache der wiederholten Abweichungen ist offen.

Die Prozessprobe des letzten laufenden Mac-Auftrags zeigte den Worker bei der SMB-Auflistung eines Zielordners. Ein gezielter Komponententest mit der überarbeiteten Ordnerprüfung bestand auf der echten Freigabe. Vor der abschliessenden Prüfung einen unabhängigen Eintrag in einem eigenen Testziel ergänzen. Die Übertragung muss dann ohne erfolgreichen Abschluss stoppen und den Eintrag unverändert lassen. Nach Entfernen der Testdatei denselben Auftrag fortsetzen. Einen ursprünglich vorhandenen leeren Unterordner nach Abschluss vor einem weiteren Prüfversuch aus dem Ziel verschieben. Diese Änderung muss beim Prüfen des Abschlussbelegs auffallen.

### Ausstehende Ordnerprüfung beim SMB-Kopieren

1. Einen eigenen Baum mit dem Unterordner `Ordner-日本語` auf ein isoliertes SMB-Testziel kopieren. Falls die Testumgebung es unterstützt, die Namensauflistung dieses Ordners während der Zielprüfung gezielt zurückhalten.
2. Während des ausstehenden Zugriffs die Transferkarte in beiden Ansichten prüfen. Sie soll Zielseite und relativen Ordnerpfad anzeigen. «Pause» muss als angefordert sichtbar bleiben. Der Auftrag behält seine Reservierung. Andere Bereiche bleiben bedienbar.
3. Den Testzugriff freigeben. Erst nach Rückkehr aus dem Dateisystemzugriff muss derselbe Auftrag pausiert erscheinen. Den Auftrag nach App-Neustart fortsetzen. Beide Bäume unabhängig vergleichen und genau einen Abschlussbeleg erwarten. Der vorherige Prüfort darf im pausierten oder abgeschlossenen Zustand nicht als aktiv erscheinen.
4. Die Anzeige auch bei der Verifikation des Abschlussbelegs prüfen. Bei einem gezielt gehaltenen Verzeichniszugriff muss der genaue Zielordner sichtbar sein. Ein zurückgehaltener Zugriff darf noch keinen Abschluss bestätigen.

Im Mac-Dauerlauf wartete Build 384 beim Auflisten auf das Dateisystem. In einer separaten schreibgeschützten SMB-Sitzung blieb auch ein Reader für Verzeichnisnamen im Systemaufruf hängen. Die erneute unabhängige Prüfung der APFS-Quelle bestätigte die SHA-256-Werte aller 20’004 Dateien. Der isolierte Warteschlangentest für Build 418 bestätigte den gemeldeten Prüfort, Pause, Wiederaufnahme und Abschlussbeleg mit einem gezielt gehaltenen Prüfschritt. Der vollständige SMB-Dauerlauf bleibt offen.

Für REG-NAS-19 eine isolierte Testfreigabe verwenden, die während der Schreibberechtigungsprüfung verzögert antwortet. Einen lokalen Ordner wählen und F5 auslösen. Die Oberfläche, der lokale Bereich und die Transferübersicht müssen bedienbar bleiben. Nach Wiederkehr der Freigabe darf höchstens ein Auftrag mit dem ursprünglich gewählten Ziel entstehen. Der Mac-Build 399 blockierte bei dieser Prüfung vor der Aufnahme des Auftrags. In zwei echten SMB-Läufen mit Build 400 blieben Transferübersicht und lokale Navigation bedienbar. Je ein Auftrag mit dem ursprünglich gewählten Ziel erreichte die Warteschlange. Der vollständige SMB-Transfer bleibt offen.

Für FILE-05 dieselbe verzögerte Zielprüfung mit Strg+C und Strg+V nachstellen. In einem zweiten Lauf eine Datei mit Strg+X markieren und auf das wartende Ziel einfügen. Die Prüfung einmal per Escape und einmal per Schaltfläche abbrechen. Die Datei danach in einen anderen lokalen Ordner einfügen, während der erste Lesevorgang noch wartet. Nur dieser zweite Auftrag darf entstehen. Nach der verspäteten Antwort müssen der zuerst gewählte Zielordner und die Historie unverändert bleiben. Während eines separaten wartenden Einfügens eine andere Datei ausschneiden. Nach dem ersten Abschluss muss das nächste Einfügen die neu markierte Datei verschieben. Bei einer inzwischen fehlenden Quelle muss die App die fehlende Datei melden.

Build 401 bestand alle fünf isolierten App-Varianten. Auf der echten SMB-Freigabe kopierten F5 und ⌘C/⌘V je einen Baum mit sechs Dateien. Eine frische Nur-Lese-Einbindung bestätigte alle SHA-256-Werte. Rückgängig nach App-Neustart entfernte jeweils den Zielordner. Eine weitere unabhängige Einbindung bestätigte das Ergebnis. Der vollständige D2-Dauerlauf bleibt offen.

Die Zielbindung separat prüfen. Während die erste Zielprüfung wartet, den eigenen Zielordner umbenennen und am alten Pfad einen anderen Testordner anlegen. In einem weiteren Lauf «Ersetzen» wählen, nachdem der Zielordner bei offenem Konfliktdialog ausgetauscht wurde. Die App muss den Wechsel melden. Alle Testdateien müssen bytegenau erhalten bleiben und es darf kein Auftrag für den Ersatzordner entstehen. Für die Gegenprobe nur im Dateibereich zu einem anderen Ordner navigieren. Nach der Freigabe muss der einmalige Auftrag beim ursprünglich gewählten Ordner ankommen.

Die beiden Abweichungen in der ursprünglichen SMB-Quelldatei lagen an Position 348 beziehungsweise 601 innerhalb des jeweiligen 4‑KiB-Blocks. Diese Positionen und die Bitmaske stimmen mit früheren SMB-Befunden überein. Bei einem vergleichbaren Windows-Befund zusätzlich zur absoluten Byteposition auch die Position im Block und die Bitmaske notieren.

Ein separater macOS-Dauerlauf verwendet 20’004 ausgelesene und geprüfte lokale Quelldateien und vier getrennte SMB-Zielverbindungen. Bei 69 MiB wurde eine Zielverbindung getrennt. Der betroffene Auftrag pausierte, während die drei anderen weiterliefen. Nach dem erneuten Einbinden lief derselbe Auftrag mit mehr als 69 MiB weiter. Die Zwei-Stunden-Marke und die unabhängige Endprüfung aller Ziele sind noch offen.

Im nächsten SMB-Lauf vom 19. November pausierte der betroffene Auftrag nach 76’546’048 Bytes und setzte mit derselben ID fort. Ein zweiter Auftrag wurde manuell pausiert und fortgesetzt. Alle vier Aufträge erhielten einen Abschlussbeleg. Separate nur lesende SMB-Verbindungen bestätigten SHA-256, Ordnerstruktur und Kontrollmarkierungen für alle vier Ziele mit zusammen 20’004 Dateien und 7’522’886’128 Bytes. Die Übertragungsphase dauerte rund 73 Minuten. Die zweistündige Belastungsprüfung mit der sichtbaren App bleibt offen.

In einem weiteren Vier-Aufträge-Lauf vom 19. November setzte der Auftrag für eine 2-GiB-Datei nach dem Trennen und erneuten Einbinden seiner Testverbindung mit derselben ID fort. Bei der abschliessenden Inhaltsprüfung stoppte er ohne Abschlussbeleg. Eine unabhängige vollständige Leseprüfung fand genau ein abweichendes Byte an Position 634’258’009 ab Dateianfang (nullbasiert, XOR 0x02). Eine zweite neu eingehängte Nur-Lese-Verbindung bestätigte den Wert an genau dieser Stelle. Die Quelle entsprach dem Manifest. Die drei Ordneraufträge liefen zu diesem Zeitpunkt weiter. Die Ursache der Abweichung und die vollständige Dauerlaufabnahme sind offen.

Die erste fertige 2-GiB-Kopie dieses Laufs stimmte beim unabhängigen Lesen über eine zweite SMB-Verbindung exakt mit der ursprünglichen SHA-256-Liste überein. Auch die unbeteiligte Kontrolldatei blieb bytegenau erhalten. Nach rund 53 Minuten stoppte der Lauf wegen der Prüfsumme einer weiteren 2-GiB-Zieldatei. Zwei vollständige Lesevorgänge über eine zweite SMB-Verbindung fanden dieselben drei abweichenden Bytes. Die lokale Quelle entsprach in beiden Läufen der ursprünglichen Prüfsumme. Die App verbuchte für das betroffene Ziel keinen Abschluss. Die drei unterbrochenen Aufträge wurden mit ihren ursprünglichen Auftrags-IDs und Zwischenständen fortgesetzt. Eine separate Kopie mit dem macOS-Systemwerkzeug auf dieselbe Freigabe bestand zwei vollständige Rückleseprüfungen. Ein zweiter unabhängiger Transfer schrieb in 1-MiB-Blöcken, synchronisierte jeden Block und verglich ihn ohne Dateicache. Anschliessend stimmten auch zwei vollständige Prüfsummen überein. Beide Gegenproben liefen mit anderem Übertragungsablauf als der Dauerlauf. Im fortgesetzten Lauf scheiterten zwei weitere Zieldateien mit 2 GiB und 1 GiB. Zwei unabhängige Lesevorgänge bestätigten je ein abweichendes Byte bei unveränderter Quelle und ohne Abschlussbeleg. Ein zusätzlicher Lauf mit der OpenCommander-Übertragungslogik kopierte dieselbe 2-GiB-Datei zusammen mit einer kleinen Datei in einem separaten Testordner. Beide Ziele stimmten bei der unabhängigen Prüfung. Die Ursache im grossen Lauf bleibt offen. Bei einer vergleichbaren Abweichung unter Windows die Zielbytes separat lesen, den fehlenden Abschlussbeleg erfassen und eine Systemkopie in ein eigenes Testziel als Gegenprobe ausführen.

Bei reproduzierbarer Byte-Abweichung die Quelle am lokalen Pfad beziehungsweise vor dem Transfer direkt auf SMB prüfen. Danach das Ziel über eine zweite SMB-Verbindung zweimal vollständig lesen. SHA-256 und die ersten abweichenden Byte-Positionen erfassen. In den Mac-Vergleichen traten zwei feste Positionen und Bitmasken innerhalb von 4-KiB-Blöcken sowohl bei einer vorab bereitgestellten SMB-Quelle als auch in drei SMB-Zieldateien auf. Bei der späteren Kontrolllesung über zwei Einbindungen waren zwei von fünf früher betroffenen Zielpositionen weiterhin abweichend. An den übrigen drei Positionen stimmten die gelesenen Blöcke wieder mit dem Original überein. Solche nachträglichen Stichproben mit Zeit und Lesegrösse aufzeichnen. Den Auftrag erst nach vollständigem Hash-Abgleich aller Daten als bestanden werten. Die Ursache ist offen.

Eine parallele Mac-Gegenprobe ausserhalb von OpenCommander reproduzierte dieselbe 4-KiB-Bitposition bei einer 1-GiB-Datei. Alle unmittelbar geprüften Schreibblöcke waren korrekt. Zwei vollständige Lesevorgänge nach dem Schliessen fanden dasselbe eine abweichende Bit. Eine weitere vollständige Lesung über eine zweite SMB-Einbindung bestätigte Bitposition und Prüfsumme. Die zwei anderen 2-GiB-Kopien, die lokalen Quellen und die Kontrolldatei stimmten. Für eine Windows-Gegenprobe denselben Testdatensatz gleichzeitig mit dem Betriebssystem in drei eigene SMB-Ziele kopieren. Nach dem Schliessen den vollständigen SHA-256 je Zieldatei zweimal prüfen, wenn möglich über zwei separate SMB-Verbindungen oder einen zweiten Computer. Prüfsummen der Quellen und die Zahl der bestätigten Abweichungen festhalten.

Ein fortgesetzter Mac-Auftrag erreichte 7’000 von 7’001 Dateien und stoppte in der letzten Datei ohne Abschlussbeleg. In einem gezielten Vergleich am Ende der unvollständigen Zieldatei lasen zwei frisch eingehängte Nur-Lese-Verbindungen dasselbe abweichende Bit bei Byteposition 368’476’508. Die vollständige Quellprüfsumme, das Auftragsjournal und die separate Kontrolldatei stimmten. Die Position innerhalb des 4-KiB-Blocks und die Bitmaske entsprachen einem früheren Befund.

Für den Test einzelner Auftragskarten die Karte zuerst in den sichtbaren Bereich der Warteschlange scrollen. Nach dem Klick auf «Pausieren» den gespeicherten Zustand und den weiteren Fortschritt der übrigen Aufträge prüfen. Anschliessend «Fortsetzen» einmal auslösen. Beim Mac-Nachtest beendete ein zweiter Aufruf des Prüftreibers die Test-App, nachdem die erste Bedienaktion bereits angenommen war. Beim erneuten Öffnen standen alle vier ursprünglichen Aufträge mit denselben IDs und Zwischenständen bereit. Nach «Alle fortsetzen» schrieben alle vier über ihre gespeicherten Prüfpunkte hinaus. Danach bestand der Test an einer einzelnen sichtbaren Karte im selben App-Prozess. Der pausierte Auftrag prüfte beim Fortsetzen zunächst 794 gespeicherte Einträge und schrieb dann weitere Dateien. Die drei anderen Aufträge liefen weiter.

Für JOB-01 die angezeigten Bytes, Dateizahlen, aktive Zeit, Transferrate und Restzeit mit dem gespeicherten Auftragsstand vergleichen. Build 322 zeigte bei drei laufenden gemischten Verzeichniskopien die Dateizahlen und eine beobachtete Transferrate. Bei unbekannter Restzeit erschien ein Strich. Der Auftrag mit vollständig geschriebenen, aber fehlerhaft zurückgelesenen 2 GiB zeigte 99 Prozent, den Dateinamen und die Fehlermeldung zur Zielprüfung. Ein Abschlussbeleg war nicht vorhanden.

Zwei vollständige Lesevorgänge ohne Dateicache über separat eingehängte Nur-Lese-Verbindungen ergaben für diese 2-GiB-Datei dieselbe Zielprüfsumme und dieselbe Abweichung von der Quelle. Betroffen war genau ein Bit an Byteposition 1’718’428’249 mit XOR-Maske 0x02. Position 601 innerhalb des 4-KiB-Blocks entspricht einem früheren Befund an einer anderen Datei. Die Quelle entsprach dem ursprünglichen Manifest. Das Journal und die Kontrolldatei wurden bei beiden Lesevorgängen unverändert bestätigt.

Im selben fortgesetzten D2-Lauf schrieb ein zweiter Auftrag sämtliche Bytes und stoppte beim Zurücklesen der 1-GiB-Datei `Chunk.bin`. Das Journal benannte die Datei. Ein Abschlussbeleg und ein Historieneintrag fehlten. Nach Ende des Vier-Aufträge-Laufs verglichen zwei separat eingehängte Nur-Lese-Verbindungen die vollständige Datei ohne Dateicache. Beide bestätigten dasselbe einzelne abweichende Bit bei Byteposition 361’129’166 mit XOR-Maske 0x04. Die Quellprüfsumme, das Journal und die Kontrolldatei stimmten. Die Ursache der Zielabweichung bleibt offen.

Ein dritter Auftrag stoppte beim Schreiben von `Chunk.bin` nach 7’000 von 7’001 Dateien. Zwei separat eingehängte Nur-Lese-Verbindungen fanden im geprüften 2-MiB-Endbereich dasselbe abweichende Bit an Byteposition 1’121’583’452 mit XOR-Maske 0x02. Position 348 innerhalb des 4-KiB-Blocks entspricht einem früheren Befund an einer anderen Zieldatei. Die Quellprüfsumme entsprach dem Journal. Die Stichprobe belegt die Abweichung im geprüften Bereich. Ein Auftrag lief weiter.

Nach zwei Stunden im fortgesetzten Lauf hatte der letzte Auftrag alle 7’001 Dateien geschrieben und 3’348 von 7’038 Zieleinträgen geprüft. Der Abschlussbeleg stand noch aus. Die Prüfuhr begann beim Fortsetzen nach der früheren Unterbrechung des Steuerprogramms. Die vollständige Abnahme mit vier parallelen Aufträgen bleibt offen.

Beim letzten Auftrag startete der Eintragszähler nach der Strukturprüfung erneut. Die gespeicherten Auftragsdaten kennzeichneten den zweiten Durchlauf als Prüfung des Abschlussbelegs. Eine Stichprobe des laufenden Prozesses bestätigte diese Phase. Für den Windows-Nachtest beim Wechsel den Phasennamen und den Zähler gemeinsam erfassen und den Auftrag erst nach dem gespeicherten Abschlussbeleg als erledigt werten.

Der letzte Auftrag speicherte nach 2 Stunden 29 Minuten einen Abschlussbeleg und genau einen Historieneintrag für 7’001 Dateien. Nach erneutem Einhängen verglich ein separates Prüfprogramm die Ordnerstruktur und alle 2’149’826’768 Bytes von Quelle und Ziel per SHA-256 mit dem Ausgangsmanifest. Die Kontrolldatei war unverändert. Die drei anderen Aufträge blieben ohne Abschlussbeleg. Der Zweistundenlauf mit vier erfolgreichen Aufträgen bleibt offen.

Ein unabhängiges Prüfprogramm schrieb auf derselben SMB-Freigabe über vier getrennte Einhängungen 7 GiB aus denselben grossen Quelldateien. Es verwendete direkte Systemaufrufe mit 1‑MiB-Blöcken und verglich nach jedem Schreibvorgang den Block. Alle unmittelbaren Vergleiche stimmten. Erst beim vollständigen SHA‑256-Vergleich nach erneutem Einhängen zeigte eine 2‑GiB-Datei ein abweichendes Bit bei Byteposition 1’437’254’233 mit XOR-Maske 0x02. Zwei weitere Nur-Lese-Einhängungen bestätigten dasselbe Bit. Die übrigen drei grossen Dateien und alle Quellprüfsummen stimmten. Für den Windows-Nachtest den unabhängigen Kopierlauf und den App-Lauf separat protokollieren und jeweils nach einer neuen Verbindung vergleichen. Die genaue Schicht, in der die Abweichung entsteht, bleibt offen.

Im noch laufenden D2-Versuch mit Build 384 bewegte sich der Inhaltszähler eines Auftrags nach einem längeren Stillstand wieder und erreichte in der letzten Stichprobe vor dem Phasenwechsel 7’506’108’912 Bytes. Derselbe Auftrag begann danach die Prüfung von 20’112 Metadateneinträgen. Eine Prozessprobe erfasste dabei Zugriffe auf erweiterte Dateiattribute. Der Abschlussbeleg und der unabhängige Zielvergleich stehen für diesen Auftrag noch aus.

20. November 2026. Der ursprüngliche D2-Auftrag aus Build 384 wechselte nach der Prüfung der Metadaten in die Prüfung des Abschlussbelegs. Eine Prozessprobe bei vier geprüften Einträgen zeigte, dass die Verzeichnisabfrage in der macOS-Funktion getattrlistbulk wartete. Die unabhängige Quellenprüfung glich 20’004 Dateien und 108 Verzeichnisse sowie 7’522’886’128 Bytes anhand des ursprünglichen Manifests ab. Bei der Stichprobe fehlten der Abschlussbeleg und der unabhängige Zielvergleich. Drei weitere Aufträge desselben Dauerlaufs sind fehlgeschlagen.

### Lokale Grössenanzeige bei wartendem NAS prüfen (REG-NAS-24)

1. Links einen eigenen lokalen Ordner mit zwei Dateien zu 17 und 24 Bytes öffnen. Eine Datei liegt im Unterordner. Rechts einen eigenen lokalen Ordner mit einer Datei zu 5 Bytes öffnen.
2. In einer separaten Testumgebung die systemweite Laufwerksabfrage an einer wartenden NAS-Einbindung beobachten. Die beiden lokalen Ordner aktualisieren. In der Grössenanzeige müssen 41 und 5 Bytes erscheinen, während die Abfrage noch wartet. Die beiden lokalen Pfade und die drei Prüfsummen erfassen.

Build 426 zeigte im Mac-Fenstertest beide exakten Werte nach 1,449 Sekunden bei weiter wartender macOS-Laufwerksabfrage. Im Vergleich antwortete die alte Foundation-Abfrage in rund 81 ms. Die direkte APFS-Abfrage benötigte weniger als 1 ms. Die Probe belegt die lokale Anzeige bei diesem Zustand. Der vollständige NAS-Dauerlauf bleibt offen.

### Kleine und grosse SMB-Dateiattribute prüfen (REG-NAS-23)

Mit einem eigenen Baum aus mindestens 20 Dateien auf SMB testen. Soweit der Server und das Prüfprogramm erweiterte Attribute anbieten, mehrere kurze Werte und einen Wert mit genau 1’024 Bytes sowie einen Wert mit mehr als 1’024 Bytes anlegen. Wenn verfügbar, zusätzlich eine Datei mit Ressourcen-Fork verwenden. Die Attributwerte mit einem separaten Nur-Lese-Zugriff vor und nach dem Kopieren vergleichen und dazu die vollständigen Dateiprüfsummen erfassen. Ein auf dem Server automatisch erzeugter Begleiteintrag gehört zum Leseprotokoll. Bei instrumentierten Builds die Anzahl der Aufrufe zum Lesen der Attribute und die Laufzeit getrennt erfassen.

Für den Mac-Nachtest mit Build 420 lasen der frühere und der korrigierte Stand denselben 20-Dateien-Baum über getrennte Nur-Lese-Verbindungen. Beide lieferten identische Inhalts- und Metadaten-Prüfsummen. Die instrumentierten Läufe zählten 130 beziehungsweise 70 `fgetxattr`-Aufrufe. Separate Abfragen bestätigten alle gezielt gesetzten Testattribute und die unveränderte AppleDouble-Begleitdatei. Die Laufzeit schwankte zwischen den Läufen. In der SMB-Suite blieben unter anderem Finder-Infos, Tags, ein Ressourcen-Fork mit 3’089 Bytes und ein Attribut mit 8’193 Bytes beim Kopieren in beide Richtungen erhalten. Ein überlanges Attribut für die portablen POSIX-Rechte stoppte das Verschieben vor der Zielanlage.

Die Journal-Suite prüfte zusätzlich die Statusdaten zum Zielordner während der Belegprüfung. Sie meldeten den Ordner bei null geprüften Einträgen. Danach zählte der Auftrag jeden erfolgreich geprüften Eintrag einmal.

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

### Speicherorte bei einer nicht antwortenden SMB-Freigabe aktualisieren

Eine separate SMB-Testfreigabe und zwei eigene Ordner verwenden. In einem Bereich die Testfreigabe öffnen, im anderen einen lokalen Ordner. Ausschliesslich die Testverbindung während der Aktualisierung der Speicherorte verzögern. Die lokale Navigation und die Cloud-Liste müssen bedienbar bleiben. Prüfen, dass nur Einträge unter dem tatsächlich getrennten Speicherort zurückgesetzt werden. Einen ähnlich benannten Nachbarordner als Gegenprobe verwenden.

Beim Versuch eines Cloud-Transfers auf SMB wartete der Hauptthread von Mac-Build 405 beim Abgleichen der Speicherorte in `faccessat`. Build 406 vergleicht die bereits bekannten Pfadkomponenten. Beim erneuten Versuch blieb der Hauptthread in der normalen Ereignisschleife. Die SMB-Abfrage wartete weiterhin im Hintergrund. Die Freigabe lieferte keine Zielzeile, daher bleibt der Transfer offen. Die Pfadtests decken den Originalpfad, den aufgelösten Pfad, lokale Pfadaliase und benachbarte Namen ab.

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

### Fehlgeschlagene Aufträge gemeinsam fortsetzen

1. In einem eigenen Testprofil eine Kopie durch ein vorübergehend nicht erreichbares Ziel scheitern lassen. Die Auftrags-ID notieren und das Ziel wieder verbinden. Die App schliessen und mit demselben Profil öffnen. Den Zustand vor der ersten Eingabe prüfen.
2. Nur «Alle fortsetzen» wählen. Der Button muss auch bei ausschliesslich fehlgeschlagenen Aufträgen verfügbar sein. Der Auftrag muss mit derselben ID weiterlaufen und nach Erfolg genau einmal in der Historie stehen. Zielbytes unabhängig prüfen.
3. Mit einem fehlgeschlagenen, einem pausierten und einem endgültig abgebrochenen Auftrag wiederholen. Nur die ersten beiden dürfen weiterlaufen. Den Ablauf für lokale Dateien und für den Testadapter eines Online-Anbieters prüfen.
4. Einen getrennten Gegenversuch mit einem fehlgeschlagenen Auftrag durchführen, dessen teilweise veröffentlichtes Ziel unabhängig durch andere Bytes ersetzt wurde. «Alle fortsetzen» muss die Ersetzung erkennen. Das vorhandene Ziel und der ursprüngliche Auftrag bleiben erhalten. Für dieses Ziel darf die App keinen Erfolg melden. Ein unabhängiger Auftrag soll trotzdem abschliessen.
5. In einem isolierten Profil einen fehlgeschlagenen Online-Auftrag ohne gültige Kontobindung und einen abgebrochenen Online-Auftrag laden. «Alle fortsetzen» muss verfügbar sein. Der Versuch muss an der Kontoprüfung stoppen. Auftrags-IDs, Zieldateien und Historie prüfen.

In Build 388 war «Alle fortsetzen» bei ausschliesslich fehlgeschlagenen und abgebrochenen Aufträgen deaktiviert. Bei einem zusätzlich pausierten Auftrag startete die App nur diesen. Build 389 setzte nach dem ausdrücklichen Klick die pausierten und zuvor fehlgeschlagenen Aufträge mit ihren ursprünglichen IDs fort. Die App verbuchte exakt einen Historieneintrag je erfolgreichem Auftrag und liess den abgebrochenen Auftrag unverändert. Beim automatisierten Nachtest bewahrte die lokale Warteschlange einen gleichnamigen fremden Zielinhalt bytegenau und verbuchte dafür keinen Abschluss. Die simulierte Cloud-Warteschlange bewahrte den bisherigen Fehler und versuchte nur fortsetzbare Aufträge erneut. In einem separaten App-Nachtest mit ausschliesslich Cloud-Aufträgen aktivierte Build 389 den Button ebenfalls. Nach dem Klick blieb der Auftrag ohne gültige Kontobindung unter derselben ID blockiert. Die App bewahrte den vorigen Fehler. Der abgebrochene Auftrag, der Zielordner und die leere Historie blieben unverändert.

**Tastatur-Nachtest.** Die Transferübersicht mit der dafür vorgesehenen Tastenkombination öffnen und Escape drücken. Die Übersicht muss schliessen. Erneut öffnen, den fehlgeschlagenen Auftrag über den Tastaturbefehl für «Alle fortsetzen» starten und nach dem Abschluss erneut mit Escape schliessen. Danach den Tastaturbefehl für die Ordnernavigation prüfen. Bei automatisierter Eingabe einen uneinheitlichen Tastendruck separat festhalten.

Im signierten Build 389 öffnete ⌘⇧T die Transferübersicht. Escape schloss sie vor und nach dem Fortsetzen. ⇧R führte einen gespeicherten fehlgeschlagenen Auftrag unter derselben ID bis zu bytegenauem Ziel und genau einem Historieneintrag fort. Der abgebrochene Auftrag blieb beendet. Nach dem Schliessen war die Ordnernavigation mit ⌘L wieder erreichbar. Die automatisierte Escape-Zustellung war im gemischten Versuch uneinheitlich. Deshalb ist für diese Variante kein Tastaturergebnis eingetragen.

### Zwei Kopien bei einem Online-Namenskonflikt prüfen (FILE-07)

1. Eine eigene Datei auf dem Cloud-Ziel vorbereiten und ihre Datei-ID sowie Prüfsumme erfassen. Lokal eine gleichnamige Datei mit anderen Bytes im D1-Testordner anlegen.
2. Die lokale Datei ins Online-Ziel kopieren. Den Vorschlag «Beide behalten» mit der Eingabetaste bestätigen. Nach dem Abschluss müssen das Original und die erste Kopie vorhanden sein.
3. OpenCommander im selben Testprofil neu öffnen und die Kopie wiederholen. Die zweite Kopie muss einen anderen Namen erhalten. Beide Kopien müssen der Quelle entsprechen. Die IDs und Prüfsummen des Originals und der ersten Kopie dürfen sich beim zweiten Lauf nicht ändern. Zwei abgeschlossene Aufträge und die zugehörigen Historieneinträge prüfen.

Dieser Prüffall ist für Mac-Build 426 mit Google Drive und Dropbox belegt. Beide Anbieter lieferten im separaten Kontrollabruf das unveränderte Original sowie Kopien mit den Zusätzen «(2)» und «(3)». Das lokale Manifest mit je 35 Dateien blieb exakt.

### Pausierten Auftrag mit F5 oder F6 erneut auswählen

1. In zwei eigenen lokalen Testordnern gleichnamige Dateien mit unterschiedlichen Inhalten anlegen. Die SHA-256-Prüfsummen beider Dateien notieren. Die Quelldatei gross genug wählen, damit der Transfer pausiert werden kann. Wenn nötig, einen verzögerten Testdatenträger verwenden.
2. Die Quelle auswählen, F5 drücken und «Beide behalten» wählen. Pausieren, die Auftrags-ID notieren und die App neu öffnen. Im selben Quellordner erneut dieselbe Datei auswählen und F5 mit demselben Ziel auslösen.
3. Die Warteschlange muss den vorhandenen Auftrag auswählen und fortsetzen. Die ursprüngliche Auftrags-ID und der bereits gewählte Zielname bleiben erhalten. Die ursprüngliche Zieldatei und die Quelle müssen ihre Prüfsummen behalten. Die neu benannte Kopie muss der Quelle entsprechen.
4. Die App nochmals öffnen und «Rückgängig» aus der Historie auswählen. Die neu benannte Kopie muss verschwinden. Den Ablauf getrennt mit F6 prüfen. Nach erfolgreichem Verschieben darf die Quelle fehlen. «Rückgängig» muss sie unter ihrem ursprünglichen Namen mit denselben Bytes zurückbringen.
5. Ohne gespeicherten Auftrag eine weitere Datei mit Namenskonflikt kopieren und den Dialog abbrechen. Der Dialog muss erscheinen, und der Abbruch muss beide Dateien unverändert lassen. Bei einer gemischten Auswahl aus pausierter und neuer Datei mit Konflikt muss ein Abbruch auch den pausierten Auftrag in Ruhe lassen.

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
| iPhone als Speicherort | Für DEVICE-01 ein entsperrtes Test-iPhone per Datenkabel verbinden und eine Vertrauensabfrage am Gerät bestätigen, falls sie erscheint. Unter «Orte» nach dem Gerät suchen, es in den Einstellungen ausblenden und die App neu starten. Der Ort muss ausgeblendet bleiben. Den Ort wieder einschalten, den angebotenen Medienzugriff öffnen und die Anzeige beim Abziehen und erneuten Anschliessen prüfen. In den signierten Mac-Builds 358 und 384 war das angeschlossene Gerät sichtbar. Die Einstellung blieb nach normalem App-Neustart erhalten. Nach dem Wiedereinblenden öffnete der Ort Apples «Digitale Bilder». Medienimport und physisches Abziehen bleiben offen. |
| Lokale Werkzeuge | Suche im aktiven Ordner und mit geändertem Pfad, Suchtreffer mit vollständigem Pfad, Gross-/Kleinschreibung standardmässig deaktiviert, Vergleichen, mehrfaches Umbenennen, ZIP und Rückgängig prüfen. |
| Belastung und Pfadreservierung | Mehrere Aufträge mit unabhängigen Zielen starten. Eine Kopie pausieren und eine Löschung derselben Quelle sowie eine unabhängige Löschung anfordern. Prüfen, dass nur die erste Löschung wartet. Die Kopie abbrechen, beide Löschungen nach Abschluss einzeln rückgängig machen und alle Prüfsummen vergleichen. Laufzeit und freien Speicher erfassen. Für JOB-05 drei unabhängige Ziele verwenden. Beim Pausieren und Abbrechen die Zeit vom Klick bis zur ersten sichtbaren Statusänderung erfassen. Build 306 bestand den Ablauf mit APFS-Quelle und SMB-Ziel. Nach beiden Rückgängig-Aktionen stimmten am Originalpfad alle 20’004 Dateien und 107 Unterordner mit dem Manifest überein. Bei der Variante mit langsamer SMB-Quelle wurde die wartende Löschung erfolgreich freigegeben und ihr Wiederherstellungsbestand geprüft. Die Wiederherstellung am ursprünglichen SMB-Pfad stoppte nach 7’001 Dateien mit widersprüchlichen Prüfsummen im Plan. Der [separate Wiederherstellungstest](#smb-wiederherstellungsplan-gegen-die-historie-prüfen) beschreibt den Nachtest. |

Der signierte Mac-Build 356 bestand den sichtbaren Suchnachtest. ⌘F öffnete die Suche im aktiven Ordner. Der Pfad liess sich ändern, die Treffer zeigten den absoluten Pfad und die standardmässig abgewählte Gross-/Kleinschreibung liess sich einschalten. Mit zwei eigenen Dateien, etwa `Links\Mixed.txt` und `Rechts\mixed.txt`, lässt sich derselbe Wechsel auf Windows mit der dortigen Such-Tastenkombination prüfen.

### Tastaturfokus zwischen Hilfe und Dateiliste

1. Eine eigene Textdatei markieren, mit F2 den Umbenennen-Dialog öffnen und ihn mit Escape schliessen. Dateiname und Historie prüfen.
2. F1 drücken. Während die Hilfe den Tastaturfokus hat, F2 drücken. Die Hilfe bleibt sichtbar. Es erscheint kein Datei-Dialog.
3. Bei geöffneter Hilfe wieder auf die markierte Datei im Dateifenster klicken. Mit F2 umbenennen und über die Tastatur rückgängig machen. Die Hilfe bleibt geöffnet. Der ursprüngliche Name, die Dateibytes und der ursprüngliche Historienzustand werden wiederhergestellt.
4. In das Suchfeld der Hilfe wechseln und einen Begriff eingeben. F2 darf weiterhin keine Dateiaktion auslösen. Danach wieder die Dateiliste anklicken, mit F1 zur bereits offenen Hilfe zurückkehren und diese mit Escape schliessen.

Im signierten Mac-Build 366 bestand der Ablauf mit der aktiven Tastaturbelegung. Nach dem Rückgängig stimmten der Dateiname und die Bytes, und die Testhistorie war wieder leer. F1 brachte den Fokus zur bereits offenen Hilfe zurück. Escape schloss die Hilfe.

### Zwischen Dateifenstern und Explorer ziehen (FILE-03)

1. Zwei vorbereitete Testordner in OpenCommander öffnen. Eine Datei direkt auf eine Ordnerzeile im Ziel ziehen. Im Kopiermodus muss die Quelle erhalten bleiben. Im Verschiebemodus muss sie an den Zielort wechseln. Die Zieldatei darf ausschliesslich im gewählten Unterordner erscheinen. Für beide Läufe den Historieneintrag und «Rückgängig» prüfen.
2. In Windows-Explorer einen separaten Testordner daneben öffnen. Eine Testdatei von dort auf dieselbe Ordnerzeile ziehen. Die Standardgeste, den Verschiebemodifikator vor und während des Ziehens sowie den Kopiermodifikator bei aktivem Verschiebemodus jeweils separat prüfen. Quelle und Ziel nach dem Ablegen und nach «Rückgängig» per Prüfsumme kontrollieren.
3. Eine eigene Datei in Gegenrichtung nach Explorer ziehen und mit dem Kopiermodifikator ablegen. Beide Dateien müssen bytegleich sein. Bei sichtbarem Ziel mit Escape abbrechen und prüfen, dass kein Auftrag entsteht. Die Modifikatortasten für eine Verknüpfung separat testen und das Verhalten des Windows-Builds erfassen. Mac-Build 356 wies diese Geste beim Eingang von Finder zurück.
4. Eine Datei über dem unteren Rand einer langen Zielliste halten. Sichtbare Zeilennamen vor und nach dem automatischen Scrollen festhalten. Während des Ziehens Escape drücken. Quelle, Zielordner und Auftragsliste müssen ihren ursprünglichen Zustand behalten.
5. Eine Datei über einem eingeklappten Ordner im Ordnerbaum halten. Dessen Unterordner müssen nach kurzer Zeit sichtbar werden. Mit Escape abbrechen. Prüfen, dass dadurch kein Kopier- oder Verschiebeauftrag entsteht.

Im signierten Mac-Build 356 bestanden die Standardgeste, Verschieben vom Finder mit ⌘ vor oder während des Ziehens, Kopieren mit Option bei aktivem Verschiebemodus, Export in den Finder und Escape. Die Zielliste scrollte beim Halten der Maus und der Ordnerbaum klappte das gehaltene Ziel auf. F5 und F6 bestanden separat mit lokalen Zielordnern, bytegenauem Ergebnis, Historie und «Rückgängig».

Der Finder-Nachtest in Build 389 prüfte vier echte Ziehvorgänge von einem eigenen Finder-Ordner auf einen sichtbaren OpenCommander-Unterordner. Escape und die kombinierte Geste ⌥⌘ liessen Quelle, Ziel und Auftragsliste unverändert. ⌥ bei aktivem Verschiebemodus kopierte, nach Beginn des Ziehens gedrücktes ⌘ verschob. Die Zieldateien stimmten bytegenau. Rückgängig stellte in beiden Fällen den Ausgangszustand wieder her. Beim ersten automatisierten Versuch mit ⌘ nach Beginn des Ziehens blieb der Mauszeiger am Ziel stehen. Die App kopierte. Beim Nachtest bewegte der Testtreiber den Zeiger nochmals innerhalb derselben Zielzeile und hielt ⌘ bis nach dem Loslassen. Die App verschob die Datei. Der App-Code war in beiden Versuchen identisch.

### Ziehen auf einen langsam antwortenden Zielordner

1. In einer separaten OpenCommander-Instanz zwei eigene Zielordner öffnen. Einen Testadapter oder eine eigene Testfreigabe verwenden, die die Zielprüfung nach der ersten Identifikation des rechten Ordners verzögert. Eine Testdatei aus dem Explorer auf eine gewöhnliche Dateizeile im rechten Bereich ziehen. Bei einer automatisierten Geste die Zielzeile nach Aktivierung beider Fenster am Bildschirm erneut ermitteln.
2. Während die Prüfung wartet, die Transferübersicht öffnen und im rechten Bereich in einen anderen Ordner wechseln. Prüfung freigeben. Die Datei muss ausschliesslich im ursprünglich gewählten Ordner erscheinen. Ein Abschluss und ein Historieneintrag mit «Rückgängig» werden erwartet.
3. Aus dem ursprünglichen Testzustand erneut ziehen. Während derselben Prüfphase den ursprünglichen Zielordner umbenennen und einen anderen Ordner unter seinem bisherigen Pfad anlegen. Prüfung freigeben. Die App muss das geänderte Ziel melden. Beide Ordner und die Quelle müssen unverändert bleiben. Es darf keinen Auftrag und keinen Historieneintrag geben.
4. In einem weiteren Durchgang die laufende Prüfung abbrechen und anschliessend erneut auf einen anderen Zielordner ziehen. Erst danach die alte Prüfung freigeben. Nur der zweite Versuch darf einen Auftrag und einen Historieneintrag erzeugen. Für den Test mit nachträglich gedrückter Verschiebetaste den Zeiger danach noch innerhalb derselben Zielzeile bewegen und die Taste bis nach dem Loslassen halten.
5. Dieselbe Explorer-Kopie mit einem echten SMB-Testordner wiederholen. Nach Abschluss über eine neue Nur-Lese-Verbindung den SHA-256-Wert der öffentlichen Zieldatei prüfen. OpenCommander neu öffnen, «Rückgängig» wählen und mit einer weiteren Nur-Lese-Verbindung prüfen, dass der öffentliche Zielname fehlt und die Kontrolldatei unverändert ist. Falls die App eine Kopie zur Wiederherstellung zurückhält, diese und den belegten Speicherplatz separat erfassen.

Mac-Testbuild 402 bestand vier lokale Versuche mit tatsächlicher Mausgeste vom Finder. Beim verzögerten Test blieben Transferübersicht und Navigation bedienbar. Der Test lehnte den getauschten Zielordner ab. Nach dem Abbruch erzeugte ausschliesslich der zweite Versuch einen Auftrag. ⌘ während des Ziehens verschob die Datei, und «Rückgängig» stellte die Quelle wieder her. Auf der echten SMB-Freigabe bestätigten neue Nur-Lese-Verbindungen die Zielbytes und das Ergebnis von «Rückgängig» nach App-Neustart. Die private Wiederherstellungskopie enthielt weiterhin exakt die Testbytes. Der vollständige D2-Dauerlauf bleibt offen.

### Cloud-Dateien in einen lokalen Bereich oder in den Explorer ziehen

1. Ein eigenes Testkonto oder einen kontrollierten Cloud-Testadapter und eine Testdatei mit bekanntem SHA-256-Wert verwenden. Eine wirkliche Mausgeste aus dem Online-Bereich auf einen lokalen Zielordner ausführen. Während einer kontrolliert gehaltenen Zielprüfung die danebenliegende Dateiansicht und die Transferübersicht bedienen. Der interne Drop sollte in dieser Phase keine zweite Dateibereitstellung für den Explorer auslösen. Nach Freigabe Auftragszahl, Historie, Zielinhalt und «Rückgängig» prüfen.
2. Den ursprünglich gewählten Ordner in zwei getrennten Läufen am gleichen Pfad ersetzen. Den Austausch zuerst während der Zielprüfung und danach während der Anfrage beim Testanbieter ausführen. Die Veröffentlichung muss in beiden Fällen stoppen. Die Kontrolldateien in beiden lokalen Ordnern und die Cloud-Quelle müssen bytegenau erhalten bleiben. Prüfen, ob die vorgesehene Fehlermeldung erscheint und sich der fehlgeschlagene Vorgang gegebenenfalls in der Historie nachvollziehen lässt.
3. Die Prüfung in einem weiteren Lauf abbrechen und erneut auf einen anderen Ordner ziehen. Die alte Prüfung erst danach freigeben. Die gewählte Datei auch direkt aus dem Online-Bereich in ein separates Explorer-Fenster ziehen. Dateiinhalt und Name prüfen. Der Explorer-Export muss über die Dateibereitstellung weiterhin funktionieren.

In Build 404 forderte Catalyst nach einem internen Drop zusätzlich die Finder-Dateibereitstellung an. Der simulierte Anbieter erhielt dadurch schon während der Zielprüfung eine Download-Anfrage. Build 405 fing diese zweite Anforderung ab. Native Maus-Tests bestätigten den abgewiesenen Ordneraustausch vor dem Download und während der Anbieterabfrage. Im Wartefall liessen sich ein anderer Ordner und die Transferübersicht öffnen. Die Datei erschien im ursprünglich gewählten Ziel, und «Rückgängig» entfernte die öffentliche Kopie. Der separate Export in den Finder enthielt exakt die Testbytes. Die Komponentenprüfungen deckten sowohl die Warteschlange als auch die direkte Veröffentlichung ab.

### Bedienelemente direkt nach einem Cloud-Drop benutzen

1. Eine eigene Online-Testdatei auf eine Unterordnerzeile im lokalen Dateibereich ziehen. Nach Abschluss direkt «Rückgängig» in der Werkzeugleiste anklicken, ohne vorher eine Dateizeile anzuklicken. Die öffentliche Kopie muss verschwinden. Kontrollinhalt und gegebenenfalls die zurückbehaltene Version per Prüfsumme prüfen.
2. In einem neuen Lauf die erste Zielprüfung mit einer kontrollierten Verzögerung halten und «Abbrechen» anklicken. Die Datei erneut auf den Unterordner ziehen und das Ergebnis abwarten. Die ursprüngliche Prüfung freigeben. Nur der zweite Drop darf in der Historie stehen. Ohne weiteren Klick in der Dateiliste die Historie öffnen und exakt diesen Eintrag rückgängig machen.
3. Im gleichen Ablauf die App nach der erfolgreichen zweiten Übertragung beenden und mit demselben Testprofil öffnen. «Rückgängig» am wiederhergestellten Historieneintrag muss das gleiche Ergebnis liefern. Danach den Export einer Cloud-Datei und einer Datei aus einem lokalen ZIP in den Explorer mit Name und Prüfsumme kontrollieren.

In Build 407 blieben die sichtbaren Schaltflächen nach dem Cloud-Drop ohne Wirkung, bis ein Klick in die Dateiliste die Bedienung wiederherstellte. Build 408 schloss den ursprünglichen Mausdruck vor dem Start des nativen Drags ab. In drei nativen Tests funktionierten Rückgängig aus der Werkzeugleiste, Abbrechen und erneutes Ziehen mit anschliessendem Rückgängig aus der Historie sowie Rückgängig nach App-Neustart. In allen drei Läufen blieben die zurückbehaltenen Testbytes und die Kontrollinhalte exakt. Beide Exporte in Finder bestanden. Der Cloud-Anbieter war simuliert.

### Kalter und warmer Cloud-Ordnerabruf (CLOUD-01)

In einem frischen Testprofil einen eigenen Cloud-Ordner mit einer Testdatei auf oberster Ebene und einer anderen Datei in einem Unterordner öffnen. Die Zeit vom Klick bis zur richtigen Dateiliste erfassen. Dann den Unterordner öffnen, mit «Zurück» zum Hauptordner wechseln, den Cloud-Bereich schliessen und denselben Ort erneut öffnen. Kalten Erstabruf und warmes Wiederöffnen separat protokollieren. Ladeanzeige, Möglichkeit zum Schliessen und die unveränderte Ansicht im zweiten Bereich prüfen. Objekt-IDs und Dateiinhalte unabhängig beim Anbieter vergleichen.

Im signierten Mac-Build 322 lagen die gemessenen Zeiten inklusive Bedienautomation bei Dropbox bei 3,13 s für den Erstabruf und 1,95 s für das Wiederöffnen. Bei Google Drive waren es 2,93 s und 1,91 s. Die Werte beschreiben den Testaufbau.

Für den Abbruchnachtest den Listenabruf eines eigenen Testordners gezielt verzögern. Während die Ladeanzeige sichtbar ist, den Cloud-Bereich schliessen. Der lokale Ordner muss sofort wieder erreichbar sein. Sobald der verzögerte Abruf beendet ist, darf keine alte Cloud-Liste die lokale Ansicht ersetzen. Denselben Cloud-Ort erneut öffnen und die Dateiliste unabhängig prüfen.

### Anfragedrosselung beim Ordnerabruf prüfen (CLOUD-06)

1. Einen eigenen Ordner über die direkte Cloud-Verbindung laden. Nur beim Listenabruf für diesen Testordner den Testadapter mit `HTTP 429: too_many_requests` antworten lassen. Die App muss die bisherige Liste mit Zeitangabe und einem Hinweis auf die Drosselung zeigen. Den anderen Dateibereich auf einer lokalen Kontrolldatei lassen.
2. Während der Wartezeit zweimal manuell aktualisieren. Die Zahl der Anbieteranfragen muss gleich bleiben. In einer separaten Sitzung eine neue Testdatei im Cloud-Ordner ablegen und die Störung aufheben. Ein automatischer Abruf muss die neue Datei anzeigen und den Warnhinweis entfernen.
3. Die Drosselung erneut auslösen und den Cloud-Bereich vor dem geplanten Abruf verlassen. Über mindestens zwei Warteintervalle die Anfragen zählen. Der frühere Ordner darf keinen weiteren Abruf auslösen. Erst das erneute Öffnen soll wieder genau eine Liste laden. Die IDs und Prüfsummen der Testdateien unabhängig vergleichen.
4. In einem separaten Lauf die Drosselung bestehen lassen und alle automatischen Versuche bis zum Erreichen des Wiederholungslimits zählen. Danach müssen die Warnung und die zuletzt geladene Liste erhalten bleiben. Nach Aufheben der Störung muss ein manuelles Aktualisieren wieder funktionieren.

Der signierte Mac-Build 322 bestand diese Varianten für Dropbox und Google Drive. Beim ersten Test lud die App nach rund 15,6 Sekunden einmal erneut. Bei anhaltender Drosselung wurden drei automatische Versuche mit Abständen von rund 16, 21 und 32 Sekunden beobachtet. Während der anschliessenden 32 Sekunden kam kein weiterer Abruf hinzu.

Build 384 behandelte die explizite Diagnose «HTTP 503: serviceNotAvailable» im rclone-Transport als allgemeinen Fehler. Build 385 zeigte die datierte letzte Liste und den Wiederholungszeitpunkt. Ein einziger automatischer Abruf lud danach die neuen Daten. Nach HTTP 429 beendete das Verlassen des Ordners weitere Abrufe. Der App-Test verwendete einen simulierten OneDrive-Transport. Den Adapter für diese Variante mit `HTTP 503: serviceNotAvailable` antworten lassen.

### Verzögerter Abruf in beiden Bereichen (CLOUD-07)

Den ersten Abruf des eigenen Cloud-Ordners anhalten und denselben Ort rechts öffnen. Beide Bereiche müssen den Ladezustand zeigen. Links den Cloud-Bereich schliessen und prüfen, dass links wieder der lokale Ordner und rechts weiterhin die Ladeanzeige erscheint. Den Abruf freigeben. Die Cloud-Dateien müssen nur rechts erscheinen.

Den Ort danach in beiden Bereichen öffnen und mit einem zweiten Client eine neue Testdatei anlegen. Manuell links aktualisieren, den Abruf verzögern und rechts ebenfalls aktualisieren. Sobald beide Bereiche laden, den Abruf freigeben. Die neue Datei muss in beiden Listen erscheinen. Falls der Testaufbau Anbieteraufrufe protokolliert, die Zahl der Listenabrufe während der Überlappung erfassen. Build 322 bestand beide Varianten mit Dropbox und Google Drive.

Ein separater App-Test mit Build 384 und simuliertem OneDrive-Transport protokollierte je einen Abruf beim Öffnen desselben Ordners in beiden Bereichen, beim manuellen Aktualisieren beider Bereiche und beim späteren Verlassen des linken Bereichs. Der rechte Bereich erhielt die verspätete Liste. Links blieb der eigene lokale Ordner sichtbar.

### Beide Bereiche mit einem Tastendruck aktualisieren

1. Zwei eigene Online-Ordner in den Dateibereichen öffnen. Ausserhalb von OpenCommander in jedem Testordner eine eindeutig benannte neue Datei anlegen. Nur einmal den im Menü angegebenen Befehl «Aktualisieren» per Tastatur auslösen. Beide Bereiche müssen ihre jeweiligen neuen Einträge zeigen.
2. Denselben Online-Ordner in beiden Bereichen öffnen. Einen Abruf im Testadapter anhalten. Ein Tastendruck muss in beiden Bereichen den Ladezustand anzeigen. Für den gemeinsamen Ordner muss ein einziger Abruf reichen.
3. Während des gemeinsamen Abrufs links zum lokalen Testordner zurückkehren. Die verspätete Antwort darf nur rechts erscheinen. Separat mit aktivem lokalem Bereich und inaktiver Online-Liste wiederholen. Auch die inaktive Liste muss aktualisiert werden.

Einmal ⌘R aktualisierte in Mac-Build 387 nur den aktiven Bereich. Dadurch fehlte ein neuer Cloud-Eintrag im anderen Bereich. Der signierte Build 388 aktualisierte mit derselben Geste beide Bereiche. Im simulierten OneDrive gingen für denselben Ordner genau ein Abruf und für zwei verschiedene Orte je ein Abruf an den Testadapter. Im gemischten Betrieb aktualisierte auch ein lokaler aktiver Bereich die Online-Liste rechts. Beim Verlassen der linken Liste während des Abrufs blieb der rechte Abruf erhalten. Bei einer gemeinsam genutzten Konfigurationsdatei wartete der zweite Abruf auf die Dateisperre und aktualisierte anschliessend seinen Bereich.

### Anmeldewiederherstellung mit abgelehntem Cloud-Token (CLOUD-05)

1. In einem separaten Testprofil einen eigenen Dropbox- oder Google-Drive-Ordner mit einer Testdatei einrichten. Deren Objekt-ID und SHA-256-Prüfsumme unabhängig erfassen. Im zweiten Bereich einen lokalen Testordner öffnen.
2. In einer Kopie der Testkonfiguration ein absichtlich ungültiges Token ohne funktionierendes Erneuerungstoken hinterlegen. Diese Verbindung öffnen. Der betroffene Bereich muss zur Wiederverbindung auffordern und darf keine Dateiliste als aktuell anzeigen. Der lokale Bereich muss bedienbar bleiben.
3. Über die App die gültige Testkonfiguration erneut auswählen und prüfen lassen. Die erwartete Datei muss wieder erscheinen. Objekt-ID und Prüfsumme erneut unabhängig vergleichen.

Der signierte Mac-Build 322 bestand diese Variante mit echten Anbieterantworten für Dropbox und Google Drive. Für den vollständigen Fall den Token-Widerruf am dedizierten Testkonto aus der CSV und die weiteren Anbieter separat prüfen.

Für den parallelen Nachtest mit einem kontrollierten Testadapter zwei Bereiche mit derselben Verbindung öffnen. Beide Listen zuerst laden, dann die nächste Aktualisierung mit HTTP 401 beantworten. Abrufzahl, alte Zeilen und Anmeldeaktion in beiden Bereichen prüfen. Den Wiederverbindungsdialog öffnen und abbrechen. Nach einem App-Neustart den weiterhin abgelehnten Zustand prüfen. Anschliessend dem Adapter wieder Zugriff gewähren und den Abruf ausdrücklich wiederholen. Danach den Ablauf mit zwei getrennten Testkonten durchführen. Die zweite Verbindung muss ihre aktuelle Liste behalten und normal aktualisieren können.

Im signierten Mac-Build 392 simulierte der rclone-Testadapter HTTP 401 nach einer erfolgreichen ersten Liste. Bei zwei Ansichten derselben Verbindung genügte pro App-Prozess eine Anfrage. Beide Ansichten entfernten die alten Zeilen und zeigten den Anmeldehinweis. Mit getrennten synthetischen Konten aktualisierte die zweite Verbindung ihre Liste weiterhin. Die Wiederverbindung öffnete die korrekte gespeicherte Konfiguration. Abbrechen erhielt beide Testprofile. Während des Beobachtungsfensters von rund elf Sekunden startete kein automatischer neuer Abruf. Nach dem Neustart blieb die Ablehnung sichtbar. Sobald der Testadapter den Zugriff wieder gewährte, erschien die neue Dateiliste nach «Erneut versuchen». Konfigurationen und Testdateien stimmten bytegenau. Die Historie blieb leer. Der Token-Widerruf an einem echten Konto ist weiterhin offen.

### Cloud-Dateiaktionen nach App-Neustart rückgängig machen (CLOUD-03, TRASH-05)

1. In einem eigenen Cloud-Testordner zwei Dateien mit unterschiedlichen Inhalten ablegen. Objekt-IDs und SHA-256-Prüfsummen mit einem zweiten Client erfassen.
2. In der App einen leeren Ordner anlegen, eine Datei umbenennen und eine Datei in die Cloud-Wiederherstellung verschieben. Die drei Aktionen in separaten Durchläufen prüfen. Den jeweiligen Zwischenzustand direkt beim Anbieter bestätigen.
3. Die App nach jeder Aktion neu starten und den zugehörigen Historieneintrag rückgängig machen. Der neu angelegte Ordner muss aus der normalen Ansicht verschwinden. Nach Umbenennen und Wiederherstellung müssen ursprünglicher Name, Objekt-ID und Prüfsumme wieder stimmen. Die unabhängige Kontrolldatei muss unverändert sein.

Der signierte Mac-Build 322 bestand alle drei Varianten mit echten Dropbox- und Google-Drive-Testordnern. Nach dem Rückgängigmachen der Ordneranlage liess sich derselbe leere Ordner im Wiederherstellungsbereich nachweisen.

Für die beiden Archivvarianten zuerst aus einer normalen Quelldatei ein ZIP erzeugen. Die Ergebnisdatei unabhängig herunterladen, die CRCs prüfen und archivierte Dateinamen und Inhalte vergleichen. Zum Entpacken separat ein ausserhalb der App erzeugtes ZIP mit einer Unicode-Datei im Unterordner verwenden. Die entpackten Dateien direkt beim Anbieter prüfen. Nach jeder Aktion die App neu starten und den zugehörigen Historieneintrag rückgängig machen. Das erzeugte ZIP beziehungsweise der entpackte Ordner muss aus der normalen Ansicht verschwinden. Die Eingabedateien und ihre Objekt-IDs müssen erhalten bleiben.

Build 322 bestand ZIP und Entpacken samt Rückgängig mit Dropbox und Google Drive. Beim Rückgängigmachen der Entpackung auf Google Drive endete das erste Beobachtungsfenster nach 75 Sekunden. In einer neuen Testinstanz war die Prüfung noch nach 167 Sekunden aktiv und schloss anschliessend erfolgreich ab. Die Objekt-ID und der Inhalt des Eingabearchivs stimmten beim unabhängigen Anbieterabruf weiterhin überein.

Für den D1-Upload den vorbereiteten lokalen Ordner per Drag-and-drop direkt in einen eigenen Cloud-Testordner kopieren. Den einen gespeicherten Auftrag und seine ID erfassen. Nach dem Abschluss den Zielordner mit einem zweiten Client herunterladen und alle relativen Pfade, Typen, Grössen und SHA-256-Prüfsummen mit der Quelle vergleichen. Danach die App neu starten, den einzelnen Historieneintrag rückgängig machen und Quelle, Ziel sowie benachbarte Kontrolldateien erneut prüfen.

Im signierten Mac-Build 322 erzeugte der echte Ziehvorgang zu Google Drive einen gespeicherten Auftrag für 37 Dateien und vier Unterordner. Das erste Beobachtungsfenster von 650 Sekunden endete während der Bearbeitung. Die App führte denselben Auftrag weiter. Eine Stichprobe über 45 Sekunden erfasste 19 Listenabrufe, zwei Kopieraufrufe und zwei Verschiebeaufrufe des Transferwerkzeugs. Vollständiger Anbieterabgleich und Rückgängig standen zum Stichprobenzeitpunkt aus. Beim Windows-Test nach Ablauf des Beobachtungsfensters die ursprüngliche Auftrags-ID weiterverfolgen und die Zeit bis zum Abschlussbeleg erfassen.

Bei einem kontrollierten Mac-Nachtest des Arbeitsstands für Build 323 entfiel beim Datei-Rücklesen die erneute Listenabfrage vor dem Download, sofern der Aufrufer den Eintrag gerade beim Anbieter abgerufen hatte. Die Listenabfrage nach dem Download prüfte weiterhin Objekt-ID, Version und Grösse. Ein während des Rücklesens gegen ein bytegleiches Objekt ausgetauschter Eintrag wurde abgewiesen. Für den Windows-Nachtest in einem eigenen Testordner den Austausch gezielt auslösen und prüfen, dass der Auftrag keinen Abschluss oder Rückgängig-Eintrag für das fremde Objekt erzeugt. Die Laufzeitwirkung bei einem echten Anbieter ist noch offen.

Im Live-Nachtest mit dem signierten Build 323 speicherte der Google-Drive-Auftrag für zwei Dateien und zwei Unterordner seinen Historieneintrag nach 698 Sekunden. Ein unabhängiger Download bestätigte beide SHA‑256-Prüfsummen sowie den leeren und den verschachtelten Unterordner. Nach App-Neustart entfernte «Rückgängig» den ursprünglichen Zielnamen und behielt dieselben Daten im ausgewiesenen Wiederherstellungsordner. Die Quelle und die synthetischen Kontrolldateien blieben bytegenau. Ein leerer auftragsbezogener Ordner `.OpenCommander-Tree-Files-…` war neben dem Ziel sichtbar und blieb auch nach «Rückgängig» vorhanden. Für den Windows-Nachtest nach Abschluss und nach Rückgängig zusätzlich die Geschwistereinträge im Zielordner erfassen.

Der separate D1-Upload mit Build 322 speicherte einen Abschlussbeleg für alle 37 Dateien. Ein unabhängiger Download bestätigte alle relativen Pfade, Dateitypen, Grössen und SHA‑256-Prüfsummen sowie die vier Unterordner. Nach dem App-Neustart wurde der ursprüngliche Historieneintrag rückgängig gemacht. Der öffentliche Zielname verschwand, und ein zweiter unabhängiger Download bestätigte alle Dateien und Unterordner in der zurückbehaltenen Wiederherstellungskopie. Die lokale Quelle und beide Cloud-Kontrolldateien blieben unverändert. Ein leerer Arbeitsordner `.OpenCommander-Tree-Files-…` blieb nach dem Abschluss und nach «Rückgängig» sichtbar. Den Befund unter REG-CLOUD-16 festhalten.

Der korrigierte Mac-Code legt für neue Ordneraufträge bei rclone-gestützten Verbindungen einzelne temporäre Dateien im Zielordner an. In kontrollierten Nachtests blieb dort nach einer regulären Kopie und nach «Rückgängig» kein Arbeitsordner zurück. Wurde ein Upload nach seiner Ausführung beim Anbieter unterbrochen, bevor die App die Bestätigung erhielt, blieb die unbestätigte Datei separat erhalten. Der ursprüngliche Auftrag liess sich nach App-Neustart korrekt fortsetzen. Die Verlaufsdetails zeigten den getrennten Wiederherstellungspfad. «Rückgängig» erhielt diese Datei und die gleichartig benannte Datei eines anderen Auftrags bytegenau. Der Nachtest eines älteren gespeicherten Auftrags bestätigte Wiederaufnahme und Rückgängig mit dessen bestehendem Arbeitsordner.

Am 19. November bestand die Übertragungslogik von Build 326 zusätzlich einen Live-Nachtest mit einer Unicode-Datei und zwei Unterordnern in Google Drive, davon einer leer. Die unabhängige Anbieterauflistung zeigte nach der Kopie nur den Zielordner und die Kontrolldatei. Nach «Rückgängig» in einem neuen Testprozess war der veröffentlichte Ordner unter seinem vorgesehenen Wiederherstellungsnamen vorhanden. Die Objekt-IDs und SHA-256-Prüfsummen stimmten bei beiden Prüfungen. Dieser Live-Lauf prüfte die Übertragungslogik. Der sichtbare Ziehvorgang mit Build 326 steht aus.

Für REC-03 und REG-CLOUD-16 den isolierten Testprozess beenden, nachdem Dropbox die private Testdatei gespeichert hat und bevor die Warteschlange die Bestätigung erhält. Direkt beim Anbieter prüfen, dass die private Datei vorhanden ist und der veröffentlichte Zielname fehlt. Die App erneut öffnen. Die ursprüngliche Auftrags-ID muss pausiert vorliegen und darf erst nach «Fortsetzen» wieder arbeiten. Nach Abschluss muss die Historie genau einen Kopiereintrag anzeigen und den Pfad der unbestätigten Datei nennen. In einem weiteren Prozess «Rückgängig» ausführen. Anschliessend bei Dropbox die Wiederherstellungskopie, die unbestätigte Datei und die unabhängige Kontrolldatei anhand ihrer Objekt-IDs und SHA-256-Prüfsummen vergleichen.

Der separate Dropbox-Live-Lauf mit dem Code von Build 326 bestand diesen Ablauf mit einer Unicode-Datei und zwei Unterordnern. Die Wiederaufnahme übernahm die ursprüngliche Auftrags-ID. «Rückgängig» las den gespeicherten Kopiereintrag in einem dritten Prozess. Die unbestätigte Datei, die Kontrolldatei und der vollständige kopierte Ordner waren nachweisbar. Ein leerer Arbeitsordner blieb dabei aus. Der Lauf verwendete die Anwendungswarteschlange ohne sichtbares App-Fenster. Die vollständige D2- und Anbieter-Matrix zu REC-03 bleibt offen.

### Bestätigung für einen neu angelegten Cloud-Ordner geht verloren

1. Einen eigenen Testbaum mit einer Unicode-Datei und einem leeren Unterordner vorbereiten. In zwei separaten Läufen den isolierten Testprozess direkt nach dem Anlegen des temporären Hauptordners beziehungsweise eines temporären Unterordners beenden. Den Aufruf im Testadapter erst nach der Bestätigung des Anbieters unterbrechen, bevor die Warteschlange die Antwort erhält.
2. Direkt beim Anbieter die Objekt-ID des unbestätigten Ordners erfassen. Eine eigene Kontrolldatei darin ergänzen und ihre ID und SHA-256-Prüfsumme notieren. Der veröffentlichte Zielname und ein erfolgreicher Historieneintrag müssen zu diesem Zeitpunkt fehlen.
3. Nach dem Neustart denselben pausierten Auftrag fortsetzen. Der erneute Versuch verwendet einen eigenen temporären Ordner. Ist der alte Ordner wegen einer veralteten Liste zunächst unsichtbar, darf der Auftrag seinen Namen trotzdem nicht erneut verwenden. Die bereits bestätigten Ordner müssen ihre Objekt-ID behalten.
4. Den veröffentlichten Testbaum unabhängig herunterladen und Pfade, IDs und Prüfsummen vergleichen. Der Verlauf muss einen Kopiereintrag mit Hinweis auf den unbestätigten Ordner enthalten. Nach erneutem Prozessstart «Rückgängig» ausführen und sicherstellen, dass der separate unbestätigte Ordner samt Kontrolldatei weiterhin dieselben IDs und Inhalte hat.

Am 19. November bestätigten zwei Live-Läufe mit der macOS-Übertragungslogik den Prozessabbruch, die Wiederaufnahme und «Rückgängig». Bei Google Drive ging die Antwort für den Hauptordner verloren. Bei Dropbox betraf der Abbruch einen Unterordner. Beide Prozesse setzten dieselbe Auftrags-ID fort und schrieben genau einen Kopiereintrag. Bei Dropbox behielt der zuvor bestätigte Hauptordner seine Objekt-ID. Die unabhängigen Anbieterprüfungen bestätigten beide vollständigen Testbäume, ihre Wiederherstellungskopien und die unveränderten unbestätigten Ordner samt Kontrolldateien. Die Bedienung im App-Fenster bleibt eine eigene Prüfung.

Der abschliessende kontrollierte Lauf bestätigte zusätzlich die vorübergehend veraltete Liste für beide Ordnerstufen und die verlorene Bestätigung beim Verschieben eines bereits identifizierten Unterordners. Ein älterer gespeicherter Auftrag mit unbestätigtem Hauptordner liess sich ebenfalls fortsetzen.

Für ältere Mac-Aufträge mit bereits bestätigten Dateien und einem unbestätigten Unterordner den vorherigen Prüfstand und die Objekt-ID einer bestätigten Datei erfassen. Nach der Wiederaufnahme muss dieselbe Datei mit derselben Objekt-ID im vollständigen Zielbaum liegen. Der Anbieter darf nur noch die ausstehende Datei als neuen Upload erhalten. Den früheren Arbeitsordner und die darin ergänzte Kontrolldatei direkt beim Anbieter prüfen. Auch eine verlorene Bestätigung beim Übernehmen der bereits bestätigten Datei darf keinen erneuten Upload auslösen. Die kontrollierten Mac-Tests bestanden für beide zuvor eingesetzten Varianten der Dateiablage, einschliesslich bereits vorhandener Inhalte in einem separaten Arbeitsordner.

Im Google-Drive-Live-Test vom 19. November setzte der Mac-Code für Build 328 den alten Auftrag mit seiner ursprünglichen ID fort. Die bestätigte Datei behielt ihre Objekt-ID. Die Anbieterprotokolle zeigten genau einen neuen Upload für die ausstehende Datei. Unabhängige Downloads bestätigten nach der Kopie und nach «Rückgängig» in einem dritten Prozess beide SHA-256-Prüfsummen. Der unbestätigte Ordner und seine Kontrolldatei behielten ihre Objekt-IDs und Inhalte. Der Lauf prüfte die Übertragungslogik in separaten Testprozessen.

Für TRASH-07 eine neue Entpackung auf Google Drive ausführen. «Rückgängig» starten und abbrechen, sobald die Zielprüfung läuft. Den unveränderten Historieneintrag sowie Objekt-IDs und Prüfsummen des ZIP und der entpackten Dateien prüfen. Die App neu starten und genau denselben Eintrag erneut rückgängig machen. Build 322 bestand diesen Ablauf mit zwei Dateien, darunter eine Unicode-Datei im Unterordner.

Für die grosse lokale Variante 20’000 eigene kleine Dateien aus D2 verwenden und vorab ein Manifest aus relativen Pfaden und SHA-256-Prüfsummen erstellen. Den Testbaum in den OpenCommander-Papierkorb verschieben, «Rückgängig» starten und während der Prüfung abbrechen. Prüfen, dass der Bestand im privaten Papierkorb unverändert bleibt und derselbe Historieneintrag erhalten ist. Die App neu starten, den Eintrag erneut rückgängig machen und den wiederhergestellten Baum mit dem Manifest vergleichen. Build 322 bestand diese Variante auf APFS. Die vollständige Wiederherstellung des D2-Testbaums auf SMB steht noch aus.

### Cloud-Ordnerdownload bei der zweiten Datei unterbrechen

1. Für REC-01 und REC-03 einen eigenen Online-Ordner mit zwei Dateien und einem leeren Unterordner vorbereiten. Eine Datei mit Unicode-Namen und eine versteckte Datei verwenden, sofern der getestete Anbieter das unterstützt. Objekt-IDs und SHA-256-Prüfsummen der Quelle unabhängig erfassen.
2. Kopie zu einem lokalen Testordner starten. Im Testadapter nach der bestätigten ersten Datei die Antwort für die zweite Datei unterbrechen. Den Fall mit Schliessen und den Fall mit Prozessabbruch getrennt durchführen. Vor dem Öffnen der App die ursprüngliche Auftrags-ID, den lokalen Zwischenstand und die fehlende Erfolgsmeldung prüfen.
3. Den ursprünglichen Auftrag nach dem Öffnen fortsetzen. Das Anbieterprotokoll soll nur den erneuten Download der noch fehlenden Datei zeigen. Beide Dateien und der leere Unterordner müssen am lokalen Ziel vorhanden sein. SHA-256 abgleichen und genau einen erfolgreichen Kopiereintrag erwarten.
4. In getrennten Gegenproben die bereits bestätigte lokale Zwischendatei ändern oder das zugehörige Anbieterobjekt durch eine andere Datei mit denselben Bytes ersetzen. Der Auftrag muss abbrechen. Vor der weiteren Prüfung die ursprünglichen Testobjekte wiederherstellen. Abschliessend «Rückgängig» in einem weiteren Prozess prüfen und die Quellen sowie eine unabhängige lokale Kontrolldatei erneut vergleichen.

Für die OneDrive-Variante den Ort «OneDrive Online» wählen. Die Prüfung zusätzlich mit einem erhaltenen Ordnerauftrag aus einem älteren Windows-Build durchführen, sofern ein solches Testprofil verfügbar ist. Vom älteren Auftrag gespeicherte Objekt-IDs und Versionskennungen müssen beim Fortsetzen weiterhin gelten.

Im Live-Test vom 19. November setzte der Mac-Code für Build 329 einen Google-Drive-Ordnerdownload nach einem Prozessabbruch fort. Drei Download-Starts im Transportprotokoll belegen, dass nur die unterbrochene zweite Datei erneut geladen wurde. Beide SHA-256-Prüfsummen und der leere Unterordner stimmten. «Rückgängig» in einem dritten Prozess entfernte den Ordner vom sichtbaren lokalen Ziel. Ein erneuter unabhängiger Lesevorgang bestätigte die Inhalte der Google-Drive-Dateien. Dieser Lauf verwendete separate Testprozesse. In späteren Live-Läufen mit Build 333 stoppte das normale Schliessen des Mac-Fensters bei Google Drive und Dropbox jeweils den zweiten laufenden Download. Der ursprüngliche Auftrag wurde pausiert gespeichert und erschien beim nächsten Öffnen mit «Fortsetzen». Die erste Zwischenkopie behielt Dateikennung und Bytes. Der vollständige Ordner, ein Historieneintrag und «Rückgängig» wurden im App-Fenster geprüft. Beide Läufe verwendeten je zwei kleine Dateien. Die Abnahme mit D2 steht aus.

Der Mac-Nachtest mit Microsoft-Graph-Testadapter bestätigte auch für OneDrive Online, dass beim Fortsetzen nur die unterbrochene Datei erneut geladen wird. Ein Auftrag im früheren Speicherformat bestand ebenfalls. Die Prüfung mit einem echten OneDrive-Konto und sichtbarem App-Neustart steht für diese Variante aus.

### Fortschritt während eines OneDrive-Downloads

1. Eine eigene ausreichend grosse Datei über «OneDrive Online» in den lokalen Testordner kopieren. Die Übertragung mit einem Testadapter oder einer langsamen Testverbindung so verzögern, dass der Inhalt in mindestens zwei getrennten Abschnitten eintrifft. Grösse und SHA-256 der Quelldatei vorher erfassen.
2. Während der Download läuft die Auftragskarte öffnen. Die empfangenen Bytes müssen bereits nach dem ersten Abschnitt steigen. Ist die Dateigrösse bekannt, zeigt die Karte die feste Gesamtgrösse. Der Dateizähler bleibt bis zur geprüften Veröffentlichung bei 0 von 1. «100 %» und «Abgeschlossen» erscheinen erst nach dem bestätigten Kopiervorgang.
3. Den vollständig übertragenen Inhalt mit der erwarteten Prüfsumme vergleichen. Den Ablauf für einen Ordner mit mindestens zwei Dateien wiederholen. Bei bekanntem Eingang von Teildaten steigen die Bytes, bevor die laufende Datei als geprüft gezählt wird.
4. Als Gegenprobe einen begonnenen Testdownload abbrechen. Am Ziel darf keine vollständige Datei erscheinen. Fortschrittsmeldungen aus dem beendeten Versuch dürfen einen neuen Auftrag nicht überschreiben.

Der macOS-Nachtest verwendete einen verzögerten Microsoft-Graph-Testtransport. Er bestätigte Zwischenwerte vor der Inhaltsprüfung, die Metadaten der Auftragskarte und einen Abbruch ohne bestätigten Abschluss. Ein sichtbarer Live-Download mit angemeldetem OneDrive-Konto steht für diesen Nachtest noch aus.

### Prozessabbruch nach geprüftem Download

1. Eine eigene Datei aus einem Online-Ort in einen leeren lokalen Testordner kopieren. Quelle, Grösse und SHA-256 festhalten. Einen Prüfstopp nach dem Speichern des internen Inhaltsnachweises und vor dem Anlegen des lokalen Kopierjournals einrichten.
2. Nur die Test-App am Prüfstopp beenden. Es darf noch keine sichtbare Zieldatei und keinen erfolgreichen Historieneintrag geben. Bei Neustart muss der ursprüngliche Auftrag pausiert erscheinen.
3. Den Auftrag fortsetzen. Eine Transportaufzeichnung muss zeigen, dass kein zweiter Inhaltsdownload erfolgt. Die Zieldatei muss bytegenau sein. Genau einen erfolgreichen Kopiereintrag erwarten und «Rückgängig» prüfen.
4. In getrennten Durchgängen vor dem Fortsetzen die privaten Testbytes ändern oder im gespeicherten Downloadplan die Kontobindung austauschen. Der Auftrag muss den Konflikt melden und das sichtbare Ziel leer lassen. Das Original auf dem Anbieter und eine lokale Kontrolldatei müssen erhalten bleiben.

Bei einem älteren Auftrag, der nur einen Inhaltsnachweis der Quelle speichert, kann eine erneute Quellenprüfung einen separaten Lesevorgang erfordern. Die bereits geprüfte lokale Zwischenkopie muss erhalten bleiben.

Im macOS-Live-Test auf Google Drive endete der erste Testprozess genau zwischen den beiden Journalen. Der ursprüngliche Auftrag verwendete die bereits geprüften Bytes und speicherte genau einen Kopiereintrag. Ein weiterer Prozess verwendete den gespeicherten Eintrag für «Rückgängig». Objekt-ID und SHA-256 der Quelle blieben gleich. Dieser Lauf verwendete separate Testprozesse.

### Fortschritt nach einem Prozessabbruch prüfen

1. Aus einem Online-Ort einen eigenen Ordner mit zwei Testdateien kopieren. Dateigrössen und SHA-256 vorher festhalten. Über einen kontrollierten Transport die erste Datei vollständig prüfen lassen und den Prozess beenden, während Bytes der zweiten Datei bereits in der Auftragskarte stehen, ihre Inhaltsprüfung aber noch aussteht.
2. Die Test-App neu öffnen und die Auftragskarte vor «Fortsetzen» prüfen. Erwartet werden derselbe pausierte Auftrag, Grösse und Anzahl der bestätigten ersten Datei, ein Wert unter 100 % und kein erfolgreicher Kopiereintrag. Eine Transportaufzeichnung darf beim blossen Öffnen keinen Anbieteraufruf zeigen.
3. «Fortsetzen» wählen. Nur die zweite Datei erneut herunterladen lassen. Beide lokalen Dateien und ihre SHA-256-Werte prüfen. Der Abschluss erscheint erst nach Veröffentlichung des Zielordners.
4. Den Test mit einer einzelnen Datei wiederholen und den Prozess nach ihrem Inhaltsnachweis beenden, bevor die lokale Veröffentlichung beginnt. Die ganze Dateigrösse darf bereits erscheinen. Der Kopiervorgang bleibt offen und der Dateizähler bei 0 von 1.

Der Mac-Nachtest stoppte einen isolierten Downloadprozess mit einem kontrollierten Transport. Die zweite Datei war im Transport bereits angekommen und noch ohne bestätigten Inhaltsnachweis. Nach dem Neustart enthielt der pausierte Auftrag nur den Fortschritt der bestätigten ersten Datei. Beim Fortsetzen wurde nur die zweite Datei erneut geladen. Ein zusätzlicher Google-Drive-Test mit echten Dateien bestätigte denselben Fortschritt, genau einen Historieneintrag und Rückgängig aus einem frischen Prozess.

### Dateizähler beim Schreiben eines Cloud-Ordners prüfen

1. In einem eigenen Cloud-Ordner eine kleine und eine grössere Datei bereitstellen. Beide SHA-256-Prüfsummen festhalten. Den Ordner erst auf ein lokales Testziel und in einem zweiten Durchgang auf ein SMB-Testziel kopieren.
2. Nach dem Anbieter-Download das Schreiben am Ziel mit einem Testadapter in der zweiten Datei anhalten. Die erste Datei muss am Ziel bereits intern geprüft sein. Die aufgeklappte Auftragskarte soll **1 von 2 Dateien**, die bekannten Gesamtbytes und die bereits am Ziel geschriebenen Bytes zeigen. Der Auftrag ist noch aktiv und steht unter 100 %.
3. Pausieren und prüfen, dass der Auftrag bei **1 von 2** bleibt und noch keinen erfolgreichen Historieneintrag hat. Denselben Auftrag fortsetzen. Einen zusätzlichen Inhaltsdownload vom Anbieter ausschliessen.
4. Erst nach Abschluss **2 von 2 Dateien** und **100 %** erwarten. Beide Zieldateien und ihre SHA-256-Prüfsummen vergleichen. Prüfen, dass die beiden Quelldateien weiter vorhanden sind.

### Schreiben und Prüfen am Cloud-Downloadziel beobachten

1. Einen eigenen Cloud-Ordner mit einer kleinen und einer deutlich grösseren Datei auf ein lokales Testziel kopieren. Den Anbieter-Download und das Schreiben am Ziel soweit verlangsamen, dass beide Phasen sichtbar sind.
2. Beim Schreiben am Ziel müssen der Kopierstatus und ein Fortschrittswert unter 100 % erscheinen, sofern die Gesamtbytes bekannt sind. Die Geschwindigkeit muss aus den Bytes am Ziel berechnet werden. Beim Phasenwechsel wartet die Anzeige auf neue Messwerte.
3. Den Auftrag in der zweiten Datei pausieren und fortsetzen. Beim Prüfen bereits geschriebener Teildaten und des vollständigen Inhalts müssen die Details kopierte Gesamtbytes und aktuell geprüfte Bytes separat anzeigen. Die Metadatenprüfung soll Einträge zählen. Die Prozentzahl des gesamten Auftrags bleibt unter 100 %, auch wenn die Inhaltsprüfung alle Bytes umfasst.
4. In der Abschlussphase die Veröffentlichung beobachten. 100 % und der erfolgreiche Historieneintrag erscheinen erst nach bestätigtem Abschluss. Beide SHA-256-Prüfsummen vergleichen. Die Prüfung auf SMB mit einer eigenen Freigabe wiederholen.

### Grosse Cloud-Datei extern öffnen

1. In einem eigenen Testanbieter eine Textdatei bereitstellen, deren Länge das integrierte Vorschau-Limit um ein Byte überschreitet. Zwei bekannte Bytefolgen am Anfang und am Ende hinterlegen. Der automatisierte Mac-Test verwendete einen simulierten Anbieter und eine Sparse-Datei mit 2’147’483’649 Byte logischer Länge.
2. Die integrierte Vorschau wählen. Die Grössenmeldung muss erscheinen. Das Transportprotokoll darf dabei keinen Inhaltsdownload zeigen.
3. Auf derselben Datei «Öffnen» wählen. Der Vorgang muss den vollständigen Download vorbereiten und eine Kopie zum Speichern anbieten. Nach «Abbrechen» muss die temporäre Kopie entfernt sein. In einer Wiederholung die Kopie speichern und Dateilänge sowie Bytefolgen vor dem externen Öffnen prüfen.
4. Die Grössenmeldung bei der integrierten Vorschau eines zu grossen Videos ebenfalls prüfen. Über «Öffnen mit …» muss eine vollständige Kopie zur Wahl einer externen Anwendung angeboten werden. Die Anbieterdateien bleiben unverändert.

### Fehlerhafte Zieldatei beim Cloud-Download auf SMB finden

1. Einen eigenen Cloud-Testordner mit zwei Dateien und einem verschachtelten Unicode-Pfad anlegen. Beide SHA-256-Prüfsummen und eine separate Kontrolldatei auf einer SMB-Testfreigabe erfassen.
2. Den Ordner auf die Testfreigabe kopieren. Über den Fehleradapter in genau einer eigenen Zieldatei nach dem Schreiben und vor der abschliessenden Inhaltsprüfung ein Byte ändern. Die Karte muss den betroffenen Zielpfad und die fehlgeschlagene Inhaltsprüfung melden. Es darf kein erfolgreicher Historieneintrag entstehen.
3. Einen neuen Testprozess starten. Dort müssen derselbe Auftrag und derselbe Fehlerpfad sichtbar sein. Mit einer separaten Nur-Lese-Verbindung den geänderten Inhalt feststellen. «Fortsetzen» bei weiterhin geänderten Zieldaten muss mit demselben Fehler stoppen. Quellordner, Zielbytes und Kontrolldatei bleiben prüfbar.
4. Nur das absichtlich geänderte Byte des Testauftrags wiederherstellen und denselben Auftrag fortsetzen. Die bereits geprüfte zweite Datei wird weder erneut geladen noch neu geschrieben. Beide Zielprüfsummen müssen stimmen. Ein erfolgreicher Historieneintrag muss «Rückgängig» ermöglichen. Per neuer Nur-Lese-Verbindung prüfen, dass die Kontrolldatei erhalten und die Testkopie entfernt ist.

### Nach einer SMB-Wiederverbindung erneut pausieren

1. Eine eigene Datei mit mindestens 8 MiB auf eine dedizierte SMB-Testfreigabe kopieren. Quell-SHA-256, Auftrags-ID und eine unabhängige Kontrolldatei festhalten.
2. Die Testverbindung während der Kopie trennen. Der ursprüngliche Auftrag muss pausiert sein und die Wiederverbindung angeben. Der vorhandene Teilstand bleibt erhalten. Den Ablauf separat mit «Pausieren» während des Verbindungsunterbruchs wiederholen. Solange die Verbindung fehlt, bleibt der Wiederverbindungshinweis erforderlich.
3. Dieselbe Freigabe verbinden und den ursprünglichen Auftrag fortsetzen. Nach der Prüfung bereits geschriebener Daten manuell pausieren. Die Karte meldet nun die manuelle Pause. Ein früherer Wiederverbindungshinweis darf nicht wieder erscheinen. ID und Teilstand müssen erhalten bleiben.
4. Fortsetzen, den Abschlussbeleg prüfen und die SHA-256-Prüfsumme des Ziels über eine neue Nur-Lese-Verbindung vergleichen. Quelle und Kontrolldatei müssen unverändert sein. Den Wiederverbindungshinweis für ein getrenntes NTFS-Testlaufwerk separat prüfen.

Für den kurzen Vier-Aufträge-Nachtest denselben eigenen Ordner auf vier getrennte SMB-Testziele kopieren. Im signierten Mac-Build 363 stoppte einer der Aufträge beim Trennen seiner Testverbindung nach 10 MiB. Nach dem Einbinden setzte ein Klick auf das sichtbare «Fortsetzen» denselben Auftrag fort. Eine anschliessende manuelle Pause blieb ohne alten Wiederverbindungshinweis. Alle vier Aufträge erhielten je einen Abschluss- und Historieneintrag. Die unabhängige Prüfung über neu eingehängte Nur-Lese-Verbindungen bestätigte 580 Dateien mit insgesamt 134’445’824 Byte sowie die vier Kontrolldateien. Die Zweistunden-Abnahme hat einen eigenen Lauf.

### Verkürzte SMB-Teilkopie kontrolliert fortsetzen

1. Eine eigene Datei mit mindestens 8 MiB auf eine separate SMB-Testfreigabe kopieren. Nach 4 MiB pausieren. Auftrags-ID, gespeicherten Zwischenstand und die SHA-256-Prüfsummen der Quelle und einer Kontrolldatei erfassen.
2. Mit dem Testadapter ausschliesslich die eigene Teildatei am Ende auf 2,5 MiB kürzen. Freigabe aushängen und erneut einhängen. In einem neuen Prozess denselben Auftrag fortsetzen. Die App muss die Identität der Teildatei und alle verbliebenen Bytes bis zum neuen Zwischenstand prüfen, bevor sie fehlende Bytes ergänzt.
3. Den Test einmal unmittelbar nach dem neu geprüften Zwischenstand pausieren. Nach Prozessneustart muss derselbe Auftrag mit dem korrigierten Zwischenstand fortsetzen. Beim erfolgreichen Abschluss die vollständige Zielprüfsumme über eine separate Nur-Lese-Verbindung, den Abschlussbeleg und die unveränderte Kontrolldatei prüfen.
4. Je eine Negativvariante mit einem geänderten Byte im verbliebenen Teil, einem unter dem gleichen Namen eingesetzten anderen Objekt und einer nach dem Abschluss gekürzten Datei durchführen. Jede Variante muss den bestehenden Inhalt erhalten und ohne neuen Abschlussbeleg stoppen.

### Fehlende Eigentumsmarkierung am SMB-Ziel erkennen

1. In einem eigenen SMB-Testordner zwei Testdateien kopieren, darunter eine Datei in einem verschachtelten Unicode-Pfad. Den Auftrag nach der ersten fertigen Datei und vor dem Schreiben der zweiten pausieren.
2. Mit dem Dateisystem-Testadapter nur die gespeicherte Eigentumsmarkierung der ersten Zieldatei entfernen. Die Dateidaten unverändert lassen. Dieselbe Auftrags-ID fortsetzen. Der Auftrag muss den exakten Zielpfad und die fehlende Zuordnung zum Auftrag melden. Es darf keinen Abschlussbeleg geben und die zweite Datei darf noch nicht angelegt sein.
3. Die Test-App neu starten und die Sprache wechseln. Der genaue Pfad und der lokalisierte Grund müssen erhalten bleiben. Quelle und bereits vorhandene Zieldatei müssen unabhängig verglichen werden können. Einen neuen Kopierauftrag in einem leeren Testordner als Gegenprobe abschliessen.

Zwei gestoppte Mac-D2-Aufträge zeigten dieses Muster nach dem erneuten Einhängen auch bei unverändertem Dateiinhalt. Die separate Nur-Lese-Prüfung fand auf beiden Zielen weitere Dateien mit derselben Kennung und null Bytes. Die Ursache für den Verlust der Markierungen und Daten bleibt offen.

### SMB-Zieldatei bei der Prüfung des Abschlussbelegs finden

1. Einen eigenen lokalen Ordner mit einer verschachtelten Unicode-Datei und einer zweiten Datei vorbereiten. Beide SHA-256-Prüfsummen erfassen. Den Ordner auf eine eigene SMB-Testfreigabe kopieren und dort zuvor eine unabhängige Kontrolldatei anlegen.
2. Den Testauftrag nach dem Schreiben und der ersten Inhaltsprüfung anhalten, bevor er den Abschlussbeleg prüft. Mit dem Testadapter genau ein Byte der verschachtelten Testdatei am Ziel ändern und die Belegprüfung weiterlaufen lassen.
3. Die Transferkarte muss den genauen Zielpfad und den fehlgeschlagenen Inhaltsvergleich nennen. Der Auftrag darf keinen erfolgreichen Abschlussbeleg und keinen Rückgängig-Eintrag erhalten. Nach einem Neustart der Test-App müssen dieselbe Auftrags-ID und derselbe gemeldete Pfad sichtbar sein.
4. Die geänderte Zieldatei über eine separate Nur-Lese-Verbindung prüfen. Die zweite Zieldatei, die Kontrolldatei und die Quelle müssen ihre erwarteten Prüfsummen behalten. Der Mac-Nachtest bestand mit echtem SMB und einem kontrollierten Eingriff an der Beleggrenze. Die sichtbare Windows-Prüfung erfolgt in der Windows-Test-App.

### Inhaltsänderung während der NAS-Belegprüfung erkennen

1. Im Testprofil einen Ordner mit einer eigenen Datei über 1 MiB und einer kleineren Kontrolldatei auf eine SMB-Testfreigabe kopieren. Dateikennung, Grösse, Schreibzeit und SHA-256 des Ziels erfassen.
2. Für den zeitgenauen Nachtest einen Prüfpunkt nach dem Hashen der Zieldatei für den Abschlussbeleg und vor der letzten Prüfung ihrer Dateimerkmale verwenden. Über einen separaten Dateizugriff ein Byte derselben Datei ändern und den vorherigen Schreibzeitpunkt wiederherstellen. Die Dateikennung und Grösse müssen gleich bleiben.
3. Den Auftrag weiterlaufen lassen. Die App muss den betroffenen relativen Pfad nennen und darf keinen erfolgreichen Abschlussbeleg schreiben. Über eine unabhängige Verbindung die geänderte Zieldatei, unveränderte Quelle und Kontrolldatei prüfen.
4. Für die Variante ohne Prüfpunkt eine bestätigte Kopie nachträglich wie in Schritt 2 ändern. Die App neu starten und «Rückgängig» wählen. Die geänderte Datei muss sichtbar erhalten bleiben. In einem ausschliesslich diesem Test gehörenden Ordner das ursprüngliche Byte sowie die ursprüngliche Erstellungs- und Schreibzeit wiederherstellen und die Testfreigabe neu verbinden. Danach muss derselbe Historieneintrag die Kopie rückgängig machen können.

Im physischen SMB-Nachtest meldete der Server nach der Änderung dieselbe Schreib- und Statusänderungszeit. Die erste Mac-Korrektur akzeptierte den Nachweis trotz des abweichenden Bytes. Mit der erneuten Inhaltsprüfung über einen frisch geöffneten Zugriff ohne Lesecache wurde die Änderung abgewiesen. Eine eigene Nur-Lese-Verbindung bestätigte das abweichende Byte und die intakten Kontrolldaten.

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

Für die Inhaltsprüfung vor einer Ordneroperation im Testadapter zunächst zwei normale Dateien und einen leeren Unterordner melden. Im nächsten Verzeichnisabruf eine der Dateien unter demselben Namen als natives Google-Dokument melden. Die App muss die Inhaltsprüfung abbrechen. Im Testprotokoll darf für dieses Objekt kein Export stehen. Mit unverändertem Inventar müssen sämtliche Pfade und Prüfsummen stimmen. Der kontrollierte Mac-Test reproduzierte zuvor den fehlerhaften Export im Prüfablauf. Der korrigierte Arbeitsstand wies ihn ab und las die beiden regulären Dateien korrekt. Der oben beschriebene normale Export über «Öffnen mit …» bleibt verfügbar.

### Google-Docs-Export nach Prozessabbruch fortsetzen

1. Mit direkten Google-Drive- und Dropbox-Verbindungen in einer Test-VM arbeiten. In Google Drive ein eigenes natives Google-Dokument mit eindeutigem Text anlegen und die Google-ID und die ursprüngliche Dokumentart erfassen. In Dropbox einen eigenen leeren Zielordner anlegen.
2. Das Dokument nach Dropbox **kopieren**. Im instrumentierten Lauf den Testprozess direkt nach dem Speichern des vorbereiteten DOCX-Exports und vor dem ersten Upload beenden. SHA-256 der vorbereiteten Datei und Auftrags-ID über den Testadapter erfassen. Der Dropbox-Zielordner ist zu diesem Zeitpunkt leer. Ohne Testadapter lässt sich die normale Kopie prüfen. Den gezielten Abbruch separat als offen erfassen.
3. Das Google-Dokument direkt bei Google umbenennen und die gleiche ID kontrollieren. Die Test-App starten und denselben Auftrag fortsetzen. In Dropbox muss genau eine Kopie unter dem ursprünglich geplanten Namen erscheinen. Den Export unabhängig herunterladen, seinen Hash vergleichen und den Testtext im DOCX lesen.
4. Die App nochmals neu starten und den Kopiereintrag einmal rückgängig machen. Dropbox muss den Export entfernen. Das umbenannte Google-Dokument muss mit derselben ID, Dokumentart und demselben Text erhalten bleiben. Doppelte Zielobjekte oder Historieneinträge als Fehler dokumentieren.

Für die zusätzliche Prüfung vor dem Export im Testadapter die Google-Revision nach dem ersten Abruf ändern. Dateiname und Google-ID bleiben gleich. Die App muss den veralteten Auftrag vor dem Export abweisen. Dropbox bleibt leer. Die Google-Quelle bleibt mit der aktualisierten Fassung erhalten.

### Cloud-Download mit Ersetzen nach Verbindungsabbruch fortsetzen

1. Eine eigene Datei im direkt verbundenen Dropbox- oder Google-Drive-Testordner ablegen. Der Mac-Test verwendete 2 MiB und einen Testadapter. Für einen manuellen Test eine grössere Datei oder eine gedrosselte Testverbindung verwenden, damit Zeit für die Unterbrechung bleibt. Lokal eine gleichnamige Datei mit anderem Inhalt und eine separate Kontrolldatei anlegen. Die Prüfsummen und, sofern verfügbar, die Cloud-Datei-ID notieren.
2. Die Cloud-Datei in den lokalen Bereich ziehen und «Ersetzen» wählen. Warten, bis der Auftrag in der Warteschlange steht und der Download Daten überträgt. Dann die Verbindung in der isolierten Testumgebung trennen. Solange die Verbindung unterbrochen ist, im lokalen Bereich die Kontrolldatei auswählen und prüfen, ob die Auswahl sichtbar wechselt.
3. Die App muss am ursprünglichen Auftrag einen wiederholbaren Fehler anzeigen. Die alte Zieldatei und die Kontrolldatei müssen unverändert bleiben. Es darf noch keinen erfolgreichen Historieneintrag geben.
4. Die Verbindung wiederherstellen, die App neu starten und am ursprünglichen Auftrag «Fortsetzen» wählen. Zielprüfsumme und genau einen neuen rückgängig machbaren Historieneintrag prüfen. Nach einem weiteren App-Neustart «Rückgängig» wählen. Die alte Zieldatei muss bytegenau zurückkehren. Die Kontrolldatei sowie ID und Inhalt der Cloud-Quelle unabhängig prüfen.

Der signierte macOS-Build 322 hat bei Dropbox und Google Drive das Ziehen, die Unterbrechung, das Fortsetzen nach App-Neustart und das Rückgängig bestanden. Bei beiden Diensten wurde die Auswahl im lokalen Bereich während des gehaltenen Downloads mit der macOS-Bedienungshilfe ausgelöst und sichtbar bestätigt.

Für die Listenvariante zuerst den eigenen Cloud-Testordner laden und dann die Verbindung beim Aktualisieren dieses Bereichs unterbrechen. Die bisherige Liste muss sichtbar und als gespeicherter Stand erkennbar bleiben. Im lokalen Bereich eine Testdatei auswählen. Über eine separate, weiterhin verbundene Sitzung eine zweite eigene Datei in den Cloud-Testordner legen. Diese darf erst nach der Wiederverbindung und dem erneuten Abruf in der App erscheinen. Danach beide Namen und, sofern verfügbar, die Anbieter-IDs und Prüfsummen vergleichen. In der App dürfen dabei keine Historien- oder Warteschlangeneinträge hinzukommen.

### Grössenlimit und Stillstand der Medienvorschau (MEDIA-04, MEDIA-09, MEDIA-10)

1. Mit einer synthetischen lokalen JPEG-Datei von 128 MiB plus einem Byte die Vorschau öffnen. Die App muss das Grössenlimit anzeigen. Danach die unveränderte Dateiliste prüfen. Dieselbe Datei in einen eigenen Ordner bei Dropbox oder Google Drive laden und die Vorschau über die direkte Verbindung aufrufen. Der Hinweis muss erscheinen, bevor die App den Dateiinhalt herunterlädt. Sofern der Testadapter Inhaltsanfragen erfasst, muss deren Zahl null bleiben. Die ursprüngliche Cloud-Datei anhand ihrer ID, Grösse und Prüfsumme bestätigen.
2. Eine UTF-8-Datei von mehr als 2 MiB in der Vorschau öffnen. Der Hinweis auf die begrenzte Textmenge und «Öffnen» müssen sichtbar sein. Mit einer separaten Binärdatei mit der Endung `.txt` wiederholen. Hier muss die App den ungeeigneten Inhalt erklären und das externe Öffnen anbieten. Für alle drei Dateien die Prüfsummen vor und nach dem Test vergleichen.
3. Ein eigenes synthetisches H.264-Video aus einer direkten Cloud-Verbindung in der App öffnen. In einer isolierten Testumgebung den bereits laufenden Download anhalten und die Verbindung offen lassen. Das Zeitlimit, die sichtbare Fehlermeldung und «Erneut versuchen» prüfen. Den betreffenden Downloadprozess und dessen temporäre Dateien nach dem Abbruch kontrollieren.
4. Die Verbindung wiederherstellen und «Erneut versuchen» wählen. Das Video abspielen, zu einer anderen Zeit springen, fortsetzen und pausieren. Nach dem Schliessen der Vorschau die Dateiliste, die unveränderte Historie und die ursprüngliche Cloud-Datei anhand ihrer ID und Prüfsumme bestätigen.

Der signierte macOS-Build 322 bestätigte die drei lokalen Eingaben und das Cloud-Bildlimit bei Dropbox und Google Drive. Beim Stillstandstest erschien in beiden Diensten nach rund 30 Sekunden der Hinweis. Die App entfernte die unvollständigen temporären Daten, und die Wiedergabe war beim erneuten Versuch möglich.

Für FTP auf einem lokalen Testserver zusätzlich ein synthetisches MP4 mit genau 2’147’483’649 Bytes anbieten. Eine Sparse-Datei genügt für diese Prüfung. In der App die Vorschau öffnen und die Meldung zur Grenze von 2’048 MiB prüfen. Das Serverprotokoll darf für diese Datei keinen `RETR`-Befehl enthalten.

Mit einem kleinen, abspielbaren H.264-Testvideo den ersten `RETR` auf dem lokalen Server annehmen und die Datenverbindung ohne Nutzdaten offen halten. Ladezustand und Abbruchmöglichkeit müssen sichtbar sein. Nach dem Timeout «Erneut versuchen» wählen und den zweiten `RETR` normal bedienen. Die Wiedergabe muss starten, und nach dem Schliessen muss dieselbe Datei sichtbar sein. Der signierte Mac-Build 322 bestand beide FTP-Varianten. Der Server bestätigte die Trennung der blockierten Verbindung nach 30,0 Sekunden und lieferte das kleine Video genau einmal vollständig aus. Beide Quelldateien und die Kontrolldatei blieben bytegenau erhalten, die Historie blieb leer.

Für den Wiedergabetest ein 18 Sekunden langes FTP-Testvideo verwenden. Zuerst pausieren, auf etwa 55 % der Zeitleiste klicken, wieder abspielen und erneut pausieren. Im signierten Mac-Build 366 sprang der Abspielkopf auf 9,9 Sekunden. Er lief beim Fortsetzen weiter und hielt beim Pausieren wieder an. Nach dem Schliessen erschien dieselbe Datei. Der Server lieferte das kleine Video einmal und meldete für das grosse Video keinen `RETR`. Beide Quelldateien und die lokale Kontrolle blieben bytegenau erhalten.

### Textvorschau mit unbekannter Endung und UTF-8-Grenzfällen

Diese PowerShell-Befehle erzeugen vier eigene Dateien im temporären Testordner.

```powershell
$root = Join-Path ([IO.Path]::GetTempPath()) ("OpenCommander-QA-Preview-" + [Guid]::NewGuid())
[IO.Directory]::CreateDirectory($root) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $root ".gitignore"), "Grüße 日本語", $utf8)
[IO.File]::WriteAllText((Join-Path $root "Notiz.opencommander-unknown-format"), "Grüße 日本語", $utf8)
$prefix = [Text.Encoding]::ASCII.GetBytes("A" * (2MB - 1))
[IO.File]::WriteAllBytes((Join-Path $root "Gueltig.txt"), [byte[]]($prefix + $utf8.GetBytes("👋ENDE")))
[IO.File]::WriteAllBytes((Join-Path $root "Ungueltig.txt"), [byte[]]($prefix + @(0xE2, 0x41)))
$root
```

1. Die Vorschau von `.gitignore` und der Datei mit unbekannter Endung öffnen. Beide müssen den Unicode-Text lesbar anzeigen und das externe Öffnen anbieten.
2. `Gueltig.txt` öffnen. Die Vorschau soll die Kürzung anzeigen und vor dem geteilten Emoji enden. Bei `Ungueltig.txt` muss sie den ungeeigneten Inhalt erklären und externes Öffnen anbieten.
3. In einem isolierten Netzwerk-Testordner den Dateizugriff kontrolliert zurückhalten. Die Vorschau muss bedienbar bleiben und nach der Wartefrist einen Hinweis zeigen. Die Vorschau schliessen, eine andere Testdatei öffnen und die zurückgehaltene Antwort freigeben. Die zweite Vorschau darf ihren Inhalt behalten. Die SHA-256-Werte der vier Dateien vor und nach den Tests vergleichen.

Der Mac-Nachtest vom 20. November 2026 prüfte alle vier Dateien lokal und mit je einem Satz aus Google Drive und Dropbox. Für beide Cloud-Sätze lagen unabhängige Downloads mit identischen SHA-256-Werten und unveränderten Objekt-IDs vor. Der Test verwendete den Textleser aus Build 419. Der neue Wartehinweis wurde in allen 20 App-Sprachen geprüft. Die Bedienung im Mac-Fenster und der absichtlich verzögerte Dateizugriff stehen für diesen Build noch aus.

### Kleine Fenster und lange Dateinamen prüfen (PROP-06)

1. In einem eigenen Testordner eine kleine Textdatei mit langem Unicode-Namen erstellen. OpenCommander auf die kleinste unterstützte Fenstergrösse bringen. In den Einstellungen die Sprachauswahl öffnen und schliessen. Symbolleiste und Dateipfade müssen erreichbar sein.
2. Die lange Datei auswählen und ihre Informationen öffnen. Den vollständigen Namen und die genaue Bytezahl prüfen, dann den Dialog schliessen.
3. Einen eigenen pausierten Kopierauftrag in der Transferübersicht mit «Alle fortsetzen» starten. «Alle abgeschlossenen entfernen» wählen. Die Karte muss verschwinden, die gespeicherte Historie und die Zieldatei müssen erhalten bleiben.
4. Den Ablauf bei den im Prüffall vorgesehenen Auflösungen und Skalierungen wiederholen. Fenstergrösse, Sprache und Darstellungsmodus je Lauf protokollieren.

Im signierten Mac-Build 392 bestanden sechs sichtbare Läufe bei 900 × 600 Fensterpunkten mit deutschen Einstellungen und Dunkelmodus sowie bei 1366 × 768 Fensterpunkten mit englischen Einstellungen und heller Ansicht. Die gemessenen Bedienelemente der Symbolleiste, die Pfadfelder und die geprüften globalen Transferbuttons lagen innerhalb des App-Fensters. Der Sprachdialog liess sich öffnen. Die Auflösung und Skalierung des Monitors blieben wie vor dem Test eingestellt. Die restlichen Auflösungs- und Skalierungsvarianten stehen aus. In zwei sichtbaren Läufen von Build 392 zeigte der Info-Dialog den vollständigen langen Unicode-Namen und die exakte Grösse von 47 Bytes. Die Schaltfläche zum Schliessen war innerhalb des Fensters erreichbar. Die Transferübersicht im signierten Build 392 war in beiden Fenstergrössen bedienbar. «Alle fortsetzen» schloss den eigenen gespeicherten Auftrag unter derselben ID ab. «Alle abgeschlossenen entfernen» entfernte die Karte. Die 47 Zielbytes und der gespeicherte Historieneintrag blieben erhalten.

### Info-Dialog mit der Tastatur bedienen

1. Einen eigenen Ordner mit zwei Testdateien von 187 und 368 Bytes anlegen. Den Ordner auswählen und über den im Menü angegebenen Tastaturbefehl «Informationen» öffnen. Die Ordnergrösse muss als unberechnet erscheinen.
2. Mit Tab und Umschalt-Tab zwischen «Berechnen» und «OK» wechseln. Den Fokus in der hellen und in der dunklen Darstellung prüfen. «Berechnen» zuerst per Enter und nach erneutem Öffnen per Leertaste auslösen. Beide Ergebnisse müssen 555 Bytes und zwei Dateien ergeben.
3. «OK» per Enter aktivieren. Den Dialog in einem separaten Durchgang per Escape schliessen. Der ursprüngliche Dateibereich muss jeweils wieder bedienbar sein.
4. Mit einem isolierten Online-Ordner wiederholen. Den Abruf der untergeordneten Liste verzögern und während der Berechnung erneut Enter drücken. Es darf kein zweiter Abruf beginnen. Den Dialog per Tastatur schliessen und prüfen, ob der laufende Abruf beendet wird. Anschliessend normal erneut berechnen und die Summe prüfen.
5. Eine separate Datei auswählen und für eine andere Datei das Kontextmenü «Informationen» öffnen. Name, Pfad, Grösse, Typ und Zeitstempel müssen zur angeklickten Datei gehören. Wenn ein Testadapter dieselbe Datei-ID beibehält und nur die Metadaten aktualisiert, müssen die neuen Werte erscheinen. Bei einer neuen Anbieter-ID unter demselben Namen darf die App die Ersatzwerte während dieses Abrufs nicht als Eigenschaften der ursprünglichen Datei anzeigen.

Im Info-Dialog von Build 385 erreichte Tab die Grössenberechnung nicht. Build 386 wechselte mit Tab und Umschalt-Tab zwischen «Berechnen» und «OK». Die Markierung wurde in der hellen und in der dunklen Ansicht auf dem Bildschirm nachgewiesen. Enter und Leertaste berechneten 555 B aus zwei Dateien. Enter auf «OK» sowie Escape schlossen den Dialog. Ein isolierter App-Test in Build 386 mit simuliertem OneDrive zeigte die Ordnerinformationen vor jeder rekursiven Abfrage. Beim verzögerten Listenabruf löste erneutes Enter keine zweite Berechnung aus. Das Schliessen per Tastatur beendete den ursprünglichen Leseprozess. Nach erneutem Öffnen lieferte die Berechnung 555 B. In Build 386 meldete die Bedienhilfe «Berechnen» beim laufenden Abruf als verfügbar. Build 387 meldete den deaktivierten Zustand im App-Nachtest und behielt den Abbruch per Tastatur bei.

Zwei native App-Durchläufe von Build 385 verwendeten einen simulierten OneDrive-Ordner. Nach Auswahl einer anderen Datei zeigte «Informationen» aus dem Kontextmenü die frisch gelesenen 99 B, den korrekten Namen, Pfad, Typ und Zeitstempel der angeklickten Datei. Ein gleichnamiges Ersatzobjekt mit anderer Anbieter-ID wurde abgewiesen. Die Testdaten und die leere Historie wurden unabhängig geprüft.

### Ordnergrösse mit Zugriffsfehler und symbolischen Links prüfen (PROP-01, PROP-03)

1. In einem eigenen Testordner zwölf Unterordner mit je 500 Dateien zu 336 Bytes anlegen. In einem dreizehnten Unterordner eine Datei mit 199 Bytes anlegen und den lesenden Zugriff auf diesen Unterordner für das Testkonto sperren. Zwei symbolische Links erstellen. Einer verweist auf den Testordner selbst, der andere auf einen separaten, bekannten Testordner.
2. Eine andere Datei markieren und den Testordner per Rechtsklick öffnen. «Eigenschaften» muss den angeklickten Ordner betreffen. Die rekursive Grösse muss als unberechnet erscheinen, bis die Berechnung ausdrücklich gestartet wird.
3. Die Grösse berechnen. Das Teilresultat muss 6’000 Dateien, 2’016’000 Bytes und einen Lesefehler anzeigen. Die Inhalte der verlinkten Ordner dürfen nicht mitgezählt werden.
4. Den Zugriff auf den gesperrten Testordner wieder erlauben und erneut berechnen. Erwartet sind 6’001 Dateien, 13 Unterordner und 2’016’199 Bytes. Beim signierten Mac-Build 322 stimmten beide Resultate. Nach beiden Scans war der andere Dateibereich bedienbar. Die Testdateien und die separate Kontrolldatei behielten ihren Inhalt.

### Verzögerte Ordnergrösse und Wiederholung prüfen (PROP-03)

1. Auf einem eigenen Testserver drei Unterordner mit je drei Dateien zu 651 Bytes anlegen. Die Eigenschaften des übergeordneten Ordners öffnen und erst dann «Grösse berechnen» wählen. Im Testadapter die Verzeichnisabfrage nach den ersten drei Dateien länger als die Berechnungsfrist anhalten. Der Dialog muss 1’953 Bytes, drei Dateien und den Grund für das Teilresultat ausweisen. Nach Freigabe der Abfrage erneut berechnen und 5’859 Bytes, neun Dateien und drei Unterordner erwarten.
2. In einem frischen Testordner eine Verzeichnisantwort länger als die gesamte Wartefrist des Dialogs anhalten. Die App soll die unbekannte Ordnergrösse und die Möglichkeit zum Wiederholen anzeigen. Die verspätete Antwort des ersten Auftrags darf diese Meldung nicht überschreiben. Erst die neue Berechnung soll das vollständige und unabhängig geprüfte Ergebnis anzeigen.
3. Einen Dialog mit noch blockierter Berechnung per Escape schliessen. Der andere Dateibereich muss wieder bedienbar sein. Nach Freigabe der verzögerten Antwort muss der Dialog geschlossen bleiben. Anschliessend denselben Ordner öffnen, erneut berechnen und die Testdateien unabhängig prüfen.

Der signierte Mac-Build 363 zeigte über den lokal eingebundenen NFS-Testserver nach rund 12 Sekunden das erwartete Teilresultat. Bei längerem Verbindungsstillstand erschien nach rund 15 Sekunden die Meldung zur unbekannten Ordnergrösse. Wiederholung und Schliessen per Escape bestanden. Die verspätete Antwort änderte die Meldung nicht und öffnete den geschlossenen Dialog nicht wieder. Alle Testdateien blieben bytegenau erhalten. Die genaue Wartefrist und die Fehlermeldung der Windows-Version anhand ihrer sichtbaren Einstellungen und des Testergebnisses erfassen.

Für REG-CLOUD-38 einen eigenen Online-Ordner mit einer Datei zu 5 Bytes und einem Unterordner mit einer Datei zu 7 Bytes vorbereiten. Die Antwort auf die Liste des Unterordners im Testadapter zurückhalten, auch nachdem die App den Abbruch angefordert hat. Die Grössenberechnung muss bei Fristablauf 5 Bytes als Teilresultat melden. Noch bevor die alte Antwort freigegeben wird, erneut berechnen. Das neue Ergebnis muss 12 Bytes betragen. Dann die alte Antwort freigeben und prüfen, dass weder das neue Ergebnis noch die aktuelle Dateiliste geändert wird. Die Original-IDs und Inhalte unabhängig beim Anbieter vergleichen. Bei einem getrennten Versuch die erste Metadatenprüfung anhalten. Zu diesem Zeitpunkt sind noch keine Dateibytes verifiziert.

Der Live-Test mit dem Code von Mac-Build 423 hielt echte Antworten von Google Drive und Dropbox nach dem Anbieterabruf zurück. Die Berechnung meldete 5 Bytes nach rund 8,2 Sekunden. Die Wiederholung lieferte bei weiterhin zurückgehaltener Antwort 12 Bytes. Nach Freigabe der alten Antwort blieb die aktuelle Liste korrekt. Separate Anbieterabrufe bestätigten alle ursprünglichen IDs und Dateiinhalte. Der Komponententest deckte zusätzlich die verzögerte erste Metadatenprüfung ab. Die Abnahme im sichtbaren App-Fenster steht noch aus.

### Miniaturen beim Scrollen und Ordnerwechsel prüfen (MEDIA-12)

1. In einem eigenen Cloud-Testordner 30 nummerierte, synthetische PNGs mit unterschiedlichen Farben ablegen. Daneben einen leeren Ordner anlegen. IDs und Prüfsummen der Bilder erfassen.
2. Den Bilderordner über die direkte Verbindung in OpenCommander öffnen. Zwei sichtbare Miniaturen mit ihren Dateien vergleichen. Mit dem Mausrad nach unten scrollen und zwei weitere sichtbare Miniaturen vergleichen.
3. Den leeren Ordner öffnen und warten, bis er vollständig geladen ist. Die Bildzeilen des vorherigen Ordners dürfen dort nicht auftauchen. Den Bilderordner erneut öffnen und dieselben vier Miniaturen überprüfen.
4. Wenn ein Testadapter Inhaltsanfragen erfasst, die Zähler für die vier bereits vollständig geladenen Miniaturen vor und nach dem Wiederöffnen vergleichen. Sie müssen gleich bleiben. Bei pixelgenauen Vergleichen Bildschirmaufnahmen anhand ihres Farbprofils nach sRGB umrechnen. IDs und Prüfsummen aller Testbilder am Anbieter erneut prüfen.
5. Eines der sichtbaren Testbilder über einen unabhängigen Client durch ein andersfarbiges PNG gleicher Grösse ersetzen. Nach Möglichkeit Objekt-ID und Änderungsdatum beibehalten. Die geänderte Prüfsumme erfassen, den Ordner neu laden und beide Miniaturen vergleichen. Das ersetzte Bild muss seine neue Farbe zeigen. Beim unveränderten Nachbarbild darf der Zähler für Inhaltsanfragen gleich bleiben.

Der signierte Mac-Build 322 zeigte bei Dropbox und Google Drive vier geprüfte Miniaturen nach dem Wiederöffnen ohne erneuten Download. Beim separaten Google-Drive-Test aktualisierte die App das geänderte Bild mit einem Download und verwendete für das unveränderte Nachbarbild weiter den Cache.

### Schreibschutz in den NTFS-Dateieigenschaften prüfen

1. Ein eigenes sauberes NTFS-Testabbild mit einer Referenzdatei beschreibbar einhängen. In OpenCommander die Dateieigenschaften öffnen. Das Dateisystem muss als beschreibbar erscheinen. Einen Schreibvorgang mit einer separaten Testdatei ausführen und das Ergebnis unabhängig lesen.
2. Dasselbe Abbild aushängen und schreibgeschützt einhängen. Die Referenzdatei muss lesbar bleiben. Ihre Eigenschaften müssen das Dateisystem als schreibgeschützt und Schreibzugriff für den aktuellen Prozess als verweigert ausweisen. Der Versuch, im Testordner eine neue Datei anzulegen, muss eindeutig scheitern. Die Referenzdatei und das Abbild müssen unverändert bleiben.
3. Auf einem beschreibbar eingehängten Testvolume eine Datei mit eingeschränkter Schreibberechtigung separat prüfen. Das Feld für das Dateisystem muss weiter einen beschreibbaren Datenträger anzeigen. Die Berechtigung der einzelnen Datei kann davon abweichen.

Auf dem Mac verweigerte FSKit Schreibzugriff auch dann, wenn die Systemmetadaten den Einhängemodus als beschreibbar meldeten. Der korrigierte Dateieigenschaften-Test bestätigte beide Modi. Sechs zusätzliche unsichere NTFS-Testabbilder blieben beim abgelehnten Schreibmount und beim anschliessenden Lesen schreibgeschützt und bytegenau unverändert. Dazu gehörten simulierte Windows-Ruhezustände und nicht abgeschlossene Journale.

### NTFS-Schreibschutz bei Dateiaktionen prüfen

1. Ein eigenes NTFS-Testabbild beschreibbar einhängen. Von einem lokalen Testordner eine Datei auf das Abbild kopieren. Die Kopie umbenennen. Die Umbenennung über die Historie rückgängig machen.
2. Dieselbe Kopie in den privaten OpenCommander-Papierkorb verschieben und über die Historie wiederherstellen. Danach die ursprüngliche Kopie über ihren eigenen Historieneintrag rückgängig machen. Nach jeder Aktion Dateinamen, Inhalte und Historie prüfen. Eine separate Referenzdatei auf dem Abbild muss erhalten bleiben.
3. Die Test-App schliessen und dasselbe Abbild schreibgeschützt einhängen. Die Referenzdatei vom Abbild in den lokalen Ordner kopieren, ihren Hash unabhängig prüfen und die lokale Kopie rückgängig machen.
4. Eine separate lokale Datei auf das schreibgeschützte Abbild kopieren. Anschliessend versuchen, die Referenzdatei auf dem Abbild umzubenennen. Beide Aktionen müssen den Schreibschutz ausdrücklich melden. Es darf keine neue Datei, keinen abgeschlossenen Auftrag und keinen Erfolgseintrag in der Historie geben. Nach dem Aushängen den SHA-256-Wert des Abbilds mit dem Wert vor dem Nur-Lese-Test vergleichen.
5. Die Referenzdatei auf dem erneut schreibgeschützt eingebundenen Abbild zum Löschen auswählen und den privaten OpenCommander-Papierkorb wählen. Die Auftragskarte muss den Schreibschutz direkt anzeigen. Die Test-App schliessen und mit demselben Profil erneut öffnen. Dieselbe Auftrags-ID und die Meldung müssen bereits in der kompakten Karte erscheinen. «Abbrechen» wählen. Die Referenzdatei und das Abbild behalten ihre Prüfsummen, die Historie bleibt leer.

Der signierte Mac-Build 370 bestand die Dateiaktionen und Rückgängig auf dem beschreibbaren Abbild. Im Nur-Lese-Modus blieb das Abbild bytegenau erhalten. Die Meldungen beim verweigerten Kopieren und Umbenennen benannten den bestätigten Schreibschutz nur indirekt oder als mögliche Ursache.

Der signierte Mac-Build 371 meldete den Schreibschutz bei beiden Dateiaktionen ausdrücklich. Auf dem beschreibbar eingehängten NTFS-Abbild bestanden Kopieren, Umbenennen, privater Papierkorb und die drei einzelnen Rückgängig-Aktionen. Im Nur-Lese-Modus liess sich die Referenzdatei bytegenau kopieren und die lokale Kopie rückgängig machen. Weder der blockierte Schreibversuch noch das verweigerte Umbenennen erzeugte einen Historieneintrag. Der SHA-256-Wert des NTFS-Abbilds blieb über den Nur-Lese-Test identisch. Beim separaten APFS-Ordner mit fehlender Schreibberechtigung blieb die gewöhnliche Berechtigungsmeldung erhalten. Für die virtuellen Abbilder war der installierte FSKit-Treiber aus Build 268 aktiv.

Build 384 bestand die Schritte 1 bis 4 erneut mit dem installierten FSKit-Treiber aus Build 268. Die Meldung bei fehlender Schreibberechtigung auf APFS blieb vom NTFS-Schreibschutz unterscheidbar. Dieser Nachtest verwendete ein Testabbild.

Der signierte Build 388 wiederholte die NTFS-Dateiaktionen auf einem virtuellen Testabbild mit dem installierten FSKit-Treiber aus Build 268. Schreiben, Lesen, Umbenennen, privates Löschen und Rückgängig bestanden. Das schreibgeschützt eingehängte Abbild behielt seine SHA-256-Prüfsumme.

Build 371 stoppte die private Löschaktion auf dem schreibgeschützten NTFS-Abbild sicher und zeigte einen allgemeinen Löschfehler. Nach einem App-Neustart stand der Fehler unter den Auftragsdetails. Im signierten Build 372 war der bestätigte Schreibschutz sofort in der kompakten Auftragskarte sichtbar, auch nach dem Neustart. Die App übernahm dieselbe Auftrags-ID. «Abbrechen» liess die Referenzdatei, die gespeicherte Historie und das gesamte Abbild unverändert. Der Test verwendete den installierten FSKit-Treiber aus Build 268. 81 Warteschlangenprüfungen und 62 Lokalisierungsprüfungen bestanden. Die Lokalisierungssuite prüfte beide Schreibschutz-Fehlercodes in allen 20 App-Sprachen.

### Kopie auf vollem exFAT-Testlaufwerk fortsetzen

1. Ein virtuelles exFAT-Laufwerk mit 96 MiB anlegen und eine eigene Kontroll-Datei darauf speichern. Mit einer weiteren Testdatei den freien Platz auf rund 19 MiB reduzieren. Eine getrennte lokale Quelle mit 48 MiB und bekannter SHA‑256-Prüfsumme vorbereiten.
2. Die Kopie über die Dateiliste starten. Auf der Karte des gestoppten Auftrags den Dateinamen, die Meldung zum fehlenden Speicherplatz und «Fortsetzen» prüfen. Der Hinweis muss zum lokalen Ziel passen. Quelle und Kontroll-Datei müssen stimmen. Für den unvollständigen Auftrag darf kein erfolgreicher Historieneintrag erscheinen.
3. Die Test-App normal schliessen. Im selben Testprofil das andere Farbschema und die andere Sprache wählen. Nach dem Neustart denselben Auftrag und die lesbare, übersetzte Meldung prüfen.
4. Die eigene Fülldatei entfernen und «Fortsetzen» wählen. Die Auftrags-ID und die SHA‑256-Prüfsummen vergleichen. «Rückgängig» muss die neue Kopie entfernen. Quelle und Kontroll-Datei bleiben bytegenau erhalten.

Der signierte Mac-Build 367 zeigte im hellen englischen und dunklen deutschen Farbschema den korrigierten Hinweis zum unvollständigen Ziel und die Speicherplatzmeldung. Der gestoppte Auftrag blieb mit derselben ID über den Neustart erhalten. Nach dem Freigeben von Platz kopierte er die 48 MiB bytegenau. «Rückgängig» entfernte den Zielnamen und erhielt Quelle und Kontroll-Datei.

### Getrenntes und ersetztes exFAT-Laufwerk unterscheiden

1. Den gestoppten exFAT-Auftrag aus dem vorigen Test verwenden. Die eigene Fülldatei entfernen, die Test-App normal schliessen und das Testabbild aushängen. Die App mit demselben Profil wieder öffnen und «Fortsetzen» wählen. Der Auftrag soll pausiert bleiben und zum erneuten Verbinden desselben Laufwerks auffordern. Das leere Einhängeverzeichnis und die Historie prüfen.
2. Ein zweites exFAT-Testlaufwerk mit anderer Volume-ID am selben Pfad einbinden. Den sichtbaren Namen und eine bytegleiche Kopie der Teildatei verwenden. «Fortsetzen» erneut wählen. Die Meldung soll das andere Laufwerk benennen. Prüfsummen der Teildatei und einer separaten Kontroll-Datei auf dem zweiten Volume kontrollieren.
3. Das Original wieder einhängen und den Auftrag mit derselben ID fortsetzen. Nach dem Abschluss SHA‑256 von Quelle und Ziel sowie den einzelnen Historieneintrag prüfen. «Rückgängig» ausführen und Quelle sowie Kontroll-Datei nochmals prüfen.
4. In einem separaten Durchlauf bei abgezogenem Original «Abbrechen» wählen. Die ausstehende Prüfung muss sichtbar bleiben. Anschliessend das zweite Volume und danach das Original einhängen. Am zweiten Volume bleiben alle Testdateien unverändert. Am Original muss die App den Abbruch abschliessen und den unvollständigen Zielnamen entfernen. Falls sie die Teildatei in einem Wiederherstellungsordner behält, deren Prüfsumme mit der Teildatei vor dem Abbruch vergleichen.

Im signierten Mac-Build 368 blieb der Auftrag bei leerem Einhängepfad pausiert und zeigte die Meldung für das getrennte Laufwerk. Beim zweiten Volume erschien die Meldung zum abweichenden Volume. Das leere Verzeichnis und die Dateien auf dem zweiten Volume blieben unverändert. Mit dem Original setzte dieselbe ID den Auftrag bytegenau fort. «Rückgängig» erhielt Quelle und Kontroll-Datei. Im getrennten Abbruchlauf enthielt der Wiederherstellungsordner auf dem Original die unveränderte Teildatei.

Beim Versionswechsel von Build 367 auf 368 verwendete die signierte Test-App eine echte ältere Warteschlange mit einer Teildatei und einem bereits abgeschlossenen Auftrag. Ein erneuter Versuch am eingebundenen exFAT-Laufwerk ergänzte den gespeicherten Einhängepfad. Nach erneutem App-Start mit abgezogenem Laufwerk erschien die passende Meldung. Mit dem Original wurde derselbe Auftrag fortgesetzt und bytegenau abgeschlossen. Beide Kopien liessen sich über ihre Historieneinträge rückgängig machen.

### exFAT-Quelllaufwerk nach einem Prozessabbruch prüfen

1. Eine Testdatei mit 320 MiB und bekannter SHA-256-Prüfsumme auf einem eigenen exFAT-Testabbild ablegen. In einem separaten App-Profil die Kopie auf das lokale Laufwerk starten. Nur den Testprozess beenden, sobald das Ziel nachweislich bereits Daten enthält und der Auftrag noch läuft.
2. Das Quellabbild aushängen und die App im selben Profil starten. Dieselbe Auftrags-ID und «Fortsetzen» müssen verfügbar sein. «Fortsetzen» muss bei fehlender Quelle anhalten und zum erneuten Verbinden auffordern. Die lokale Teildatei muss dieselben Bytes enthalten. Ein Erfolgseintrag in der Historie darf noch nicht erscheinen.
3. Ein anderes exFAT-Abbild mit eigener Volume-ID am selben Pfad einhängen. Darauf eine Datei gleichen Namens und gleicher Länge verwenden. Den Versuch auch mit identischen Bytes wiederholen. Die Meldung muss das falsche Quelllaufwerk benennen und auch nach einem App-Neustart verständlich sein. Die Teildatei am Ziel und die Datei auf dem fremden Laufwerk müssen ihren vorherigen SHA-256-Wert behalten.
4. Das Original wieder einhängen. Denselben Auftrag fortsetzen, die fertige Kopie unabhängig hashen und genau einen Historieneintrag prüfen. «Rückgängig» wählen. Das Ziel muss entfernt werden. Die Quelle und die separate lokale Kontrolldatei bleiben unverändert.

Build 369 verweigerte die Fortsetzung mit dem fremden Laufwerk und liess die Teildatei intakt. In der Oberfläche und nach einem Neustart erschien dafür nur ein allgemeiner Integritätsfehler.

Im signierten Mac-Build 370 erschien bei fehlendem exFAT-Quelllaufwerk die Aufforderung zur Wiederverbindung. Bei einem anderen Volume am selben Pfad forderte die App dazu auf, das ursprüngliche Quelllaufwerk wieder zu verbinden. Die Meldung blieb nach einem App-Neustart sichtbar. Mit dem Original setzte die App denselben Auftrag fort. Die 320 MiB stimmten im unabhängigen SHA-256-Vergleich. Genau ein Historieneintrag entstand und Rückgängig entfernte nur die Kopie. Die 42 exFAT-Prüfungen umfassten auch einen getrennten Versuch mit völlig identischer Quelldatei auf dem fremden Volume. 79 Journalprüfungen bestanden ebenfalls.

### Lokale Miniatur nach Dateiersatz prüfen

1. Zwei kleine BMP-Testbilder mit identischen Abmessungen und identischer Dateigrösse erzeugen, eines rot und eines blau. Das rote Bild ins Testverzeichnis legen. Den Ordner in OpenCommander öffnen und die rote Miniatur abwarten.
2. Das rote Bild über einen externen Dateivorgang atomar durch das blaue ersetzen. Name und letzter Schreibzeitpunkt müssen gleich bleiben. Den Ordner neu laden. Die Miniatur muss blau sein. Für einen zweiten Durchlauf die Bytes der sichtbaren Datei direkt überschreiben und den alten Schreibzeitpunkt wiederherstellen.
3. Während eines verzögerten Miniaturauftrags aus der Bildzeile herausscrollen und eine andere Bildzeile anzeigen. Ein spätes Ergebnis darf weder das Bild der anderen Zeile noch eine neu geladene Version überschreiben. Ein unverändertes Nachbarbild soll weiterhin aus dem Cache erscheinen.

Der macOS-Komponententest mit Quick Look bestätigte die Cache-Identität und die erzeugten Pixel. Im sichtbaren Nachtest scrollte der signierte Build 358 von den ersten neun der 40 eigenen PNGs bis zum Listenende und zeigte in Zeile 36 die erwartete grüne Miniatur. Nach einem Wechsel in einen leeren Nachbarordner und zurück zeigte Build 338 nach atomarem Ersatz mit gleicher Dateigrösse und Schreibzeit weiterhin die alte magentafarbene Miniatur. Build 358 zeigte die blaue Ersatzversion und die unveränderte magentafarbene Nachbarminiatur. Auch beim direkten Umschreiben derselben Datei mit erhaltener Grösse und Schreibzeit erschien die neue Farbe. Der gezielt verzögerte Auftrag aus Schritt 3 bleibt ein eigener Nachtest.

### Miniaturen auf Netzlaufwerken begrenzen

Für REG-THUMB-06 zwei eigene PNGs in unterschiedlichen Ordnern derselben SMB-Einhängung vorbereiten. Den ersten Miniaturabruf im Testadapter anhalten und den zweiten einreihen. Danach eine Miniatur über eine direkte Cloud-Verbindung abrufen. Diese muss fertig werden, während der erste SMB-Abruf angehalten bleibt. Der zweite SMB-Abruf beginnt erst nach dem tatsächlichen Ende des ersten. Wenn die App den ersten inzwischen abgebrochen hat, darf das verspätete Ergebnis keine andere Bildzeile überschreiben. Beide PNGs und die Cloud-Quelle danach unabhängig mit ihren ursprünglichen Prüfsummen vergleichen.

Der Mac-Live-Test mit dem Code von Build 422 dekodierte ein echtes Google-Drive- und ein echtes Dropbox-PNG, während der Testadapter den ersten Auftrag derselben SMB-Einhängung anhielt. Der zweite Auftrag derselben Einhängung blieb jeweils in der Warteschlange. Beide SMB-Bilder wurden nach Freigabe bytegenau gelesen und dekodiert. Der Komponententest bestätigte zusätzlich, dass ein Abbruch den Platz bis zum tatsächlichen Ende des laufenden Auftrags belegt. Ein separater Prozess bestätigte die beiden SMB-Prüfsummen durch direktes Öffnen der bekannten Dateinamen auf der ursprünglichen Einhängung. Unabhängige Anbieterabrufe bestätigten die Cloud-Bilddaten. Die zusätzliche Ordnerauflistung über die Nur-Lese-Einhängung wartete bei der Prozessprobe in `readdir`. Die gemischte Prüfung im sichtbaren App-Fenster steht noch aus.

1. Einen eigenen lokalen Ordner und einen Ordner auf einer SMB-Testfreigabe mit denselben zwölf unterscheidbaren PNGs, zwei kleinen Videos und einem PNG über 32 MiB vorbereiten. Beide Dateibereiche mit diesen Ordnern öffnen. Die lokalen Videos sollen bei verfügbarem Decoder eine Miniatur erhalten. Auf dem Netzlaufwerk sollen geeignete Bilder eine Miniatur erhalten. Bei den Netzvideos und dem übergrossen Bild bleibt das Dateitypsymbol sichtbar.
2. Mit einem Testadapter zwei begonnene Miniaturaufträge anhalten. Schnell über mehrere Bildzeilen scrollen. Es sollen höchstens zwei Dateilistenaufträge gleichzeitig laufen. Aus der Ansicht gescrollte, noch wartende Zeilen sollen keinen Leseauftrag auslösen. Der zweite Dateibereich muss währenddessen bedienbar bleiben.
3. Einen laufenden Auftrag über den Zeilenwechsel abbrechen. Prüfen, dass das späte Ergebnis keinem neuen Eintrag zugewiesen wird und danach wieder eine sichtbare Miniatur fertig wird. Im Testadapter kontrollieren, dass die Netzvideos durch das blosse Anzeigen der Liste keinen Inhaltsdownload auslösen. Ohne Testadapter die Auftrags- und Lesezähler offen erfassen.
4. Parallel eine direkte Cloud-Verbindung und ein Netzlaufwerk anzeigen. Beide müssen sich die zwei Plätze für Online-Miniaturen teilen. Lokale Miniaturen sollen auch weiter geladen werden können, wenn die Online-Plätze belegt sind.

Auf macOS bestätigte der Test mit Quick Look, dass ein Abbruch einen Platz freigibt und die zwei anderen Bildresultate die richtigen Farben haben. Quick Look renderte auch ein Testbild von einem schreibgeschützt eingebundenen lokalen NFS-Testserver. Ein Warteschlangentest mit blockierten Aufträgen bestätigte das gemeinsame Limit für direkte Cloud-Verbindungen und Netzlaufwerke. Im signierten Build 359 zeigte die App auf einer echten SMB-Freigabe die erwartete Miniatur nach dem Scrollen. Ein Netzvideo und ein Bild über 32 MiB behielten ihre Dateitypsymbole. Dasselbe Video erhielt im lokalen Dateibereich eine Miniatur. Der sichtbare SMB-Test mit zwei gezielt angehaltenen Aufträgen bleibt offen.

Für den separaten FTP-Nachtest einen eigenen lokalen Testserver mit 40 PNGs in einem Ordner und einem andersfarbigen PNG im Nachbarordner verwenden. Die ersten zwei Dateiabrufe serverseitig anhalten. Zum Nachbarordner wechseln und dort die korrekte Miniatur prüfen. Beide angehaltenen FTP-Abrufe müssen enden. Den ersten Ordner erneut öffnen und bis zur letzten Zeile scrollen. Beim nächsten Öffnen die bereits geprüfte erste Miniatur anzeigen und im Serverprotokoll kontrollieren, dass dafür kein weiterer `RETR` erfolgt. Ein PNG mit 32 MiB plus einem Byte und ein Video dürfen beim Anzeigen der Liste keinen `RETR` auslösen. Der signierte Mac-Build 366 bestand diesen Ablauf. Bei vier Bildschirmproben stimmte die erwartete Miniaturfarbe. Der FTP-Server sah höchstens zwei gleichzeitige Inhaltsabrufe.

### Bild wird während des Wartens zu gross oder ersetzt

1. Auf einer eigenen Testfreigabe ein kleines rotes PNG und ein blaues PNG derselben Dateigrösse vorbereiten. Das rote PNG in OpenCommander listen. Mit einem Testadapter seinen Miniaturauftrag nach der Auflistung und vor dem Lesen anhalten.
2. Das rote Testbild auf mehr als 32 MiB vergrössern. Den Auftrag freigeben. Das Dateitypsymbol muss erhalten bleiben. Der Testadapter muss bestätigen, dass die übergrosse Datei keinem Decoder übergeben wurde.
3. Aus getrennten Ausgangszuständen das Testbild atomar durch das blaue ersetzen. Grösse und letzter Schreibzeitpunkt müssen gleich bleiben. In einem weiteren Durchlauf bei vorhandener Unterstützung einen symbolischen Link an den vorherigen Pfad setzen. Die alte Miniatur darf aus diesen Bytes weder angezeigt noch in den Cache geschrieben werden. Nach Neuladen mit einem gültigen regulären Testbild muss dessen eigene Miniatur erscheinen.
4. Mit einem Testadapter nach der geprüften Übernahme der Bytes pausieren und den Netzpfad ändern. Der Decoder soll nur die bereits begrenzte Kopie lesen. Das Ergebnis einer seitdem veränderten Quelle darf die aktuelle Zeile nicht überschreiben. Nach dem Auftrag muss die temporäre Kopie verschwinden. Ohne Testadapter die gezielten Zeitpunkte als offen erfassen.

Die macOS-Komponententests bestätigten die Ablehnung von Grössenzunahme, gleich grossem Umschreiben, symbolischem Link und FIFO. Vier echte Durchläufe auf einem lokal eingebundenen NFS-Testserver wiesen die nachträglich vergrösserte Datei ab. Quick Look konnte danach aus der bereits erstellten Kopie die ursprünglichen roten Pixel rendern. Die SMB-Variante mit gezielt verzögertem Inhaltsabruf bleibt offen.

### SMB-Miniatur nach geänderten Dateimetadaten

1. Einen eigenen SMB-Ordner mit kleinen unterschiedlichen PNGs öffnen, darunter ein frisch geschriebenes Bild. Mit einem Testadapter einen geänderten Zeitstempel zwischen Dateiliste und erstem Öffnen nachstellen. Den Ordner in der App geöffnet lassen und weder manuell aktualisieren noch die Ansicht wechseln.
2. Die veraltete Miniatur darf nicht verwendet werden. Die App soll die betroffene Zeile automatisch erneut prüfen und die aktuelle Miniatur anzeigen. Stimmen Dateikennung, Grösse oder Erstellungszeit nicht mehr überein, braucht sie eine frische Auflistung. Ein gleichzeitig geöffneter lokaler Testordner muss bedienbar bleiben.
3. Den Ordner während der ausstehenden Aktualisierung verlassen. Die verzögerte Aktualisierung darf den neuen Ordner und seine Auswahl nicht verändern. Beim Wiederöffnen das richtige Bild sowie ein unverändertes Nachbarbild prüfen.

Auf der echten SMB-Freigabe zeigte der signierte Mac-Build 358 nach dem ersten Öffnen weiterhin das Dateitypsymbol. Eine separate Prüfung zeigte, dass macOS beim Öffnen den Zeitstempel der gelisteten Datei aktualisierte. Der signierte Build 363 zeigte ohne manuelle Aktualisierung die richtige Miniatur beim ersten Öffnen und nach dem Scrollen. Der gezielte Ordnerwechsel während genau dieser ausstehenden Aktualisierung steht noch aus.

### SMB-Cachetreffer nach gleichem Schreibzeitpunkt prüfen

1. Eine blaue PNG-Datei auf SMB anzeigen und das Laden ihrer Miniatur abwarten. In einen leeren Nachbarordner wechseln. Dieselbe Datei direkt mit einer gleich grossen magentafarbenen PNG überschreiben. Den alten Schreibzeitpunkt wiederherstellen und bestätigen, dass die Dateikennung und die Länge gleich blieben.
2. Den ursprünglichen Ordner öffnen. Sobald eine Miniatur erscheint, muss sie die aktuelle magentafarbene Datei zeigen. Die unveränderte Nachbarminiatur muss korrekt bleiben. Den Inhalt der umgeschriebenen Datei unabhängig prüfen.
3. Wenn der Testadapter Dateimetadaten getrennt für Pfad und geöffnetes Objekt liefert, am Pfad zunächst die alte Version melden. Beim erneuten Einlesen muss die App den aktuellen Dateiinhalt prüfen. Danach dieselbe unveränderte Bildzeile innerhalb derselben Dateiliste aus dem sichtbaren Bereich und zurück scrollen. Dabei soll der Miniaturcache einen weiteren vollständigen Inhaltsabruf vermeiden.

Der signierte Mac-Build 359 zeigte beim Wiederöffnen weiterhin die blaue Miniatur. Ein SMB-Metadatentest bestätigte, dass der Pfad zunächst denselben Stand wie vor dem Umschreiben meldete. Build 363 zeigte im gleichen Ablauf die magentafarbene Miniatur. Die Dateikennung, Grösse und zunächst gemeldete Schreibzeit blieben gleich. Der unabhängige Inhaltsvergleich bestätigte die Änderung sowie die unveränderten Nachbardateien. Die Zahl der Inhaltsabrufe beim erneuten Scrollen bleibt offen.

### Cloud-Ordner-Download mit Neustart und Rückgängig

1. Einen eigenen Dropbox-Testordner mit `Unterordner/Grüße.txt`, dem leeren Ordner `Unterordner/Leer` und der leeren Datei `Empty.txt` anlegen. Inhalt und SHA-256 von `Grüße.txt` unabhängig erfassen. Falls verfügbar, die Dropbox-IDs festhalten.
2. Den Ordner in einen leeren lokalen Testordner kopieren. Der Auftrag muss zwei Dateien als abgeschlossen anzeigen. Unicode-Name, Prüfsumme, leere Datei und leerer Ordner müssen erhalten bleiben. Die Historie muss genau eine Kopie erfassen.
3. In einer separaten Test-VM mit Testadapter direkt nach dem Speichern des lokalen Kopierbelegs und vor dem Abschluss der Warteschlange den App-Prozess beenden. Die App erneut starten und denselben Auftrag fortsetzen. Die bereits veröffentlichte Kopie muss bestätigt werden. Es darf weder eine zweite Kopie noch einen zweiten Historieneintrag geben. Wenn ein Adapter fehlt, den gezielten Abbruch als offen erfassen.
4. Nach erneutem Start die Kopie rückgängig machen. Nur der lokale Ordner muss verschwinden. Die Dropbox-IDs und die Dateiinhalte müssen gleich bleiben.

### Dateizähler nach zwei Prozessabbrüchen prüfen

1. Einen Cloud-Testordner mit zwei Dateien von 5 und 7 Bytes vorbereiten. Den Download in eine separate Testinstanz starten. Den Testprozess beenden, nachdem der lokale Inhalt der zweiten Datei mit seinem Beleg gespeichert ist und bevor der gemeinsame Fortschrittsbeleg ersetzt wird.
2. Im ersten Neustart den bisherigen Beleg mit einer Datei und 5 Bytes bestätigen. Denselben Auftrag fortsetzen. Mit einem Testadapter nach der erneuten lokalen Prüfsummenprüfung beider Dateien den Prozess erneut beenden, bevor eine Kopie im endgültigen Ziel erscheint.
3. Beim nächsten Neustart muss die Warteschlange zwei bestätigte Dateien und 12 Bytes anzeigen. Beide Dateien müssen bytegenau erhalten sein. Prüfen, dass die Wiederaufnahme keinen zweiten Inhaltsdownload für diese Dateien auslöst. Der Auftrag muss bis zur bestätigten Veröffentlichung als unvollständig gelten.

Der Mac-Komponententest verwendete zwei echte Prozessabbrüche mit eigenen lokalen Prüfdaten. Zuvor blieb der zweite Beleg bei 5 Bytes und einer Datei. Mit der Korrektur enthielt er 12 Bytes und zwei Dateien. Die sichtbare Cloud- und SMB-Abnahme dieses Ablaufs bleibt offen.

### Cloud-Download nach lokaler Veröffentlichung abbrechen

1. In einer Windows-Test-VM eine eigene Cloud-Datei sowie eine gleichnamige lokale Datei mit anderem Inhalt vorbereiten. Beide SHA-256-Prüfsummen und, falls verfügbar, die Cloud-ID notieren. Eine unbeteiligte lokale Kontrolldatei danebenlegen.
2. Die Cloud-Datei mit «Ersetzen» herunterladen. Mit einem Testadapter den App-Prozess direkt nach der Veröffentlichung der neuen lokalen Datei und vor dem Historieneintrag beenden. Den Versuch sowohl vor als auch nach dem Speichern des lokalen Kopierbelegs wiederholen. Ohne Testadapter den gezielten Prozessabbruch als offen erfassen.
3. OpenCommander neu starten und denselben Auftrag abbrechen. Wenn das lokale Ziel seit dem Abbruch unverändert ist, muss genau ein rückgängig machbarer Kopiereintrag erscheinen. Prüfsumme und Kontrolldatei müssen stimmen. In der Variante «Verschieben» den Prozess vor dem Sichern der Cloud-Quelle beenden. Die Cloud-Datei muss sichtbar bleiben und ihre ID sowie ihren Inhalt behalten.
4. Einen weiteren App-Neustart durchführen und «Rückgängig» wählen. Das frühere lokale Ziel muss mit seiner ursprünglichen Prüfsumme zurückkehren. Cloud-Quelle und Kontrolldatei erneut prüfen.
5. Als Gegenprobe das veröffentlichte Ziel nach dem erzwungenen Prozessende durch einen anderen Inhalt ersetzen. Der Abbruch muss den Konflikt und den offenen Wiederherstellungszustand melden. Ziel, Cloud-Quelle und Kontrolldatei müssen ihre jeweils zuletzt festgestellte Prüfsumme behalten.
6. «Verschieben» in zwei weiteren Läufen nach dem Schreiben des Wiederherstellungseintrags testen. Den App-Prozess einmal unmittelbar vor dem Verschieben der Cloud-Quelle in den Wiederherstellungsbereich beenden und einmal unmittelbar danach. Nach dem Neustart denselben Auftrag abbrechen. Im ersten Lauf muss die sichtbare Quelle erhalten bleiben und genau ein Kopiereintrag entstehen. Im zweiten Lauf muss genau ein Verschiebeeintrag entstehen. Der Abbruch darf an der Cloud-Quelle keine weitere Änderung auslösen. «Rückgängig» nach einem weiteren Neustart muss das frühere lokale Ziel und im zweiten Lauf auch die Cloud-Quelle unter ihrem ursprünglichen Namen wiederherstellen. Wenn möglich dieselbe Cloud-ID bestätigen.

### Kontobindung nach abgebrochenem Tokenwechsel bestätigen

1. Eine isolierte Cloud-Testverbindung mit bekannten Prüfdaten verwenden. Beim Tokenwechsel einen Prozessabbruch zuerst nach dem Speichern der ausstehenden Bindung und dann nach dem Veröffentlichen der neuen Konfiguration auslösen. Beide Fälle mit einem frischen Prozess prüfen.
2. Die Vorschau für die erneute Bestätigung öffnen. Sie darf die Konfiguration oder die gespeicherte Bindung nicht verändern. Nach Bestätigung muss bei beiden nachweislich zum Auftrag gehörenden Tokenständen dieselbe Kontobindung erhalten bleiben.
3. In einer getrennten Testinstanz eine Konfiguration einsetzen, die zu keinem der beiden gespeicherten Stände passt. Der normale Verbindungsversuch muss stoppen. Nach ausdrücklicher Bestätigung muss die App eine neue Identität anlegen, die frühere Bindung archivieren und die Konfiguration unverändert lassen. Frühere Aufträge und Rückgängig-Belege bleiben der bisherigen Identität zugeordnet. Einen zwischen Vorschau und Bestätigung geänderten Stand separat prüfen. Diese Bestätigung muss abgelehnt werden.

### Cloud-Ordner nach Zielveröffentlichung abbrechen

1. Auf Google Drive einen eigenen Testordner mit zwei Dateien, einem Unicode-Namen und einem leeren Unterordner vorbereiten. Die Prüfsummen der Quelle und den leeren Dropbox-Testordner bestätigen. «Verschieben» starten.
2. Mit einem Testadapter unmittelbar nach der Veröffentlichung des Zielordners und vor dem Sichern der Quelle «Abbrechen» wählen. Der Testadapter soll die Bestätigung des Ziels zulassen und den App-Prozess vor dem Speichern des Warteschlangenbelegs beenden. Falls der Testadapter fehlt, diesen gezielten Zeitpunkt als offen erfassen.
3. Nach Neustart denselben Auftrag fortsetzen. Der Abbruch muss als Prüfung der bereits vorhandenen Kopie fortgesetzt werden. Es darf weder einen neuen Upload noch eine Änderung an der Quelle geben. Die Historie muss genau eine Kopie mit funktionierendem «Rückgängig» zeigen. Beide Ordner müssen bis zum Rückgängigmachen vollständig bleiben.
4. «Rückgängig» ausführen und Quelle und Ziel erneut unabhängig prüfen. Nur die bestätigte Zielkopie muss verschwinden. Den Ablauf auch von Dropbox zu Google Drive und separat mit «Ersetzen» am Ziel prüfen.

Auf dem Mac bestätigten isolierte Tests mit simulierten Anbietern und echten Prozessabbrüchen beide Übertragungsrichtungen sowie «Ersetzen». Nach dem Neustart entstand genau ein Kopiereintrag. Die Quelle behielt ihren Inhalt und «Rückgängig» entfernte die veröffentlichte Kopie. Die Live-Abnahme mit beiden Konten bleibt offen.

### Geänderten Zielordner beim Wiederholen des Cloud-Abbruchs schützen

1. Den vorherigen Test mit leerem Ziel vorbereiten. Den Prozess nach der Veröffentlichung des Zielordners beenden, während die Quelle noch unter ihrem ursprünglichen Namen liegt.
2. Auf dem Testanbieter den veröffentlichten Zielordner unter einem anderen Namen sichern. Am bisherigen Zielpfad eine Kopie mit denselben Bytes und einer eigenen Anbieter-ID platzieren. OpenCommander neu starten und am ursprünglichen Verschiebeauftrag «Abbrechen» wählen.
3. Der Auftrag muss mit ausstehender Prüfung sichtbar bleiben. Die Quelle und der Ersatzordner müssen unverändert bleiben. Es darf keinen Kopier- oder Verschiebeeintrag für den ungeklärten Zustand geben.
4. OpenCommander erneut starten. Den eigenen Ersatzordner entfernen und genau den vorher veröffentlichten Zielordner mit seiner ursprünglichen Anbieter-ID zurückbringen. Den Auftrag erneut prüfen lassen. Die Historie muss genau eine Kopie erfassen. Die Cloud-Quelle muss an ihrem ursprünglichen Ort bleiben. «Rückgängig» darf nur die bestätigte Zielkopie betreffen.

Mit den simulierten Anbietern setzte der frühere Mac-Code nach Schritt 4 das Verschieben fort. Im korrigierten Ablauf blieb der Abbruch über den Neustart gespeichert. Der Ersatzordner blieb unangetastet, die Quelle blieb am ursprünglichen Ort und der Kopiereintrag liess sich exakt rückgängig machen. Der Live-Nachtest bleibt offen.

### Abbruch nach Cloud-Ersetzen mit geänderter Zielkopie oder Sicherung

1. Eine eigene Cloud-Verschiebung mit «Ersetzen» vorbereiten. Die Prüfwerte der Quelle und der früheren Zielversion festhalten. Den Prozess nach der Veröffentlichung des neuen Zielordners beenden. Quelle und gesicherte Vorgängerversion müssen weiterhin vorhanden sein.
2. In getrennten Läufen den neuen Zielordner oder die gesicherte Vorgängerversion durch einen eigenen Ordner mit denselben Dateien und einer anderen Anbieter-ID ersetzen. In einer weiteren Variante den neuen Zielordner vorübergehend aus der Liste entfernen. Am ursprünglichen Auftrag «Abbrechen» wählen.
3. Der Auftrag muss die ausstehende Abbruchprüfung speichern. Die App darf während der Prüfung weder die Quelle verschieben noch einen Zielordner überschreiben. Nach Neustart den betreffenden Ordner mit seiner ursprünglichen ID zurückbringen und die Abbruchprüfung wiederholen.
4. Genau einen Kopiereintrag und die unveränderte Quelle bestätigen. «Rückgängig» ausführen. Die Vorgängerversion muss am ursprünglichen Ziel mit ihrer früheren Prüfsumme erscheinen. Die Cloud-Quelle muss während des ganzen Tests erhalten bleiben.
5. In einem Kontrolllauf den Prozess nach dem Sichern der Vorgängerversion und vor der Veröffentlichung des neuen Ziels beenden. «Abbrechen» muss die vorhandene Sicherung und den offenen Zustand anzeigen. Eine ausdrücklich gewählte Fortsetzung muss den unvollständigen Auftrag weiterführen können.

Mit simulierten Anbietern bestanden der Austausch der Zielkopie, der Austausch der Sicherung und das vorübergehend fehlende Ziel nach einem echten Prozessabbruch. Der Kopiereintrag stellte beim Rückgängigmachen die Vorgängerversion wieder her. Die getrennten Kontrollläufe bestätigten die ausdrückliche Fortsetzung vor der Veröffentlichung. Die Live-Abnahme bleibt offen.

### Abbruch einer einzelnen Cloud-Datei nach Veröffentlichung prüfen

1. Eine eigene Datei von einem Testanbieter zu einem zweiten verschieben. Den App-Prozess beenden, wenn die Zieldatei bereits öffentlich sichtbar ist und die Quelldatei noch am ursprünglichen Ort liegt. Den Test einmal mit leerem Ziel und einmal mit einer gleichnamigen Datei anderer Prüfsumme vorbereiten.
2. In getrennten Läufen die Zieldatei vorübergehend entfernen oder durch eine Datei mit identischem Inhalt und eigener Anbieter-ID ersetzen. Bei «Ersetzen» zusätzlich die gesicherte Vorgängerversion in einem separaten Lauf austauschen. Für den ursprünglichen Auftrag «Abbrechen» wählen.
3. Solange der Nachweis fehlt, muss die Abbruchprüfung ausstehend bleiben. Prüfen, dass die Quelle und alle aktuell vorhandenen Zieldateien unverändert bleiben und kein Historieneintrag entsteht.
4. OpenCommander erneut starten, das ursprüngliche Objekt mit seiner Anbieter-ID zurückbringen und die Abbruchprüfung wiederholen. Genau einen Kopiereintrag erwarten. Die Quellversion muss am ursprünglichen Ort bleiben. «Rückgängig» muss das leere Ziel beziehungsweise die frühere Zieldatei bytegenau wiederherstellen.

Alle fünf Varianten bestanden auf dem Mac mit simulierten Anbietern und echten Prozessabbrüchen. Die Quelle blieb am ursprünglichen Ort. Ein Vergleichslauf mit der früheren Fassung setzte nach Rückkehr der ursprünglichen Zieldatei noch das Verschieben fort. Die Live-Abnahme bleibt offen.

### Abbruch nach bestätigtem OneDrive-Upload prüfen

1. Eine eigene Datei von einem anderen Cloud-Anbieter nach OneDrive Online verschieben. Die Prüfsumme der Quelle und bei «Ersetzen» die Prüfsumme der bisherigen OneDrive-Datei festhalten. Im Testlauf den Auftrag nach Bestätigung der Zieldatei durch OneDrive und vor dem Entfernen der Quelle unterbrechen.
2. In einer kontrollierten Testumgebung die bestätigte OneDrive-Datei vorübergehend aus der Zielauflistung ausblenden. In einem zweiten Lauf eine namens- und inhaltsgleiche Datei mit anderer OneDrive-ID zurückgeben. Den zweiten Lauf mit und ohne «Ersetzen» prüfen. «Abbrechen» wählen und sicherstellen, dass Quelle, Zieldateien und gegebenenfalls die Sicherung erhalten bleiben.
3. Die App neu starten. Den ursprünglichen OneDrive-Eintrag mit identischer ID und Version wieder bereitstellen. Die Abbruchprüfung wiederholen. Genau einen Kopiereintrag erwarten. Die Quelle muss am ursprünglichen Ort bleiben. «Rückgängig» muss bei leerem Ziel den ursprünglichen Zustand wiederherstellen. Bei «Ersetzen» muss die frühere Datei wieder unter dem öffentlichen Namen erscheinen und die bestätigte Kopie unter einem Wiederherstellungsnamen erhalten bleiben.
4. Als Kontrolle auch nach dem Sichern der bisherigen OneDrive-Datei und während eines noch unbestätigten Uploads abbrechen. Die App muss die Sicherung behalten. Eine unbestätigte Datei darf keinen abgeschlossenen Kopiereintrag erzeugen.

Die sechs isolierten macOS-Varianten bestanden mit simulierten Microsoft-Graph-Antworten. Die Warteschlange und die Historie wurden von der Festplatte neu geöffnet. Die drei Varianten mit vorübergehend fehlender oder fremder Zieldatei behielten den Abbruch und prüften die korrekte Kopie bis «Rückgängig». Der Live-Test mit einem OneDrive-Konto bleibt offen.

### Cloud-Rückgängig nach Prozessabbruch fortsetzen

1. Mit eigenen Testdateien eine Cloud-zu-Cloud-Verschiebung mit «Ersetzen» abschliessen und die ursprünglichen Objekt-IDs sowie die Prüfsummen von Quelle und altem Ziel erfassen.
2. «Rückgängig» starten. Den Testprozess beenden, nachdem die Quelle zurückgekehrt ist und der Anbieter die veröffentlichte Kopie unter dem Wiederherstellungsnamen gesichert hat. Der vorherige Zielinhalt darf zu diesem Zeitpunkt noch nicht unter dem öffentlichen Namen stehen.
3. Nach Neustart denselben Rückgängig-Eintrag ausführen. Nur der fehlende letzte Umbenennungsschritt darf gesendet werden. Die beiden Originale müssen mit ihren IDs und Prüfsummen zurückkehren. Erneutes Prüfen in einem weiteren Prozess darf keine Mutation wiederholen. Der Mac-Nachtest hat diese Prozessgrenze mit simulierten Anbietern geprüft.

### Rückgängig für sieben lokale Dateiaktionen prüfen (TRASH-05)

Für jeden Durchlauf zwei frische Testordner und ein eigenes App-Profil verwenden. Den D1-Baum mit 33 Testdateien vorbereiten und relative Pfade, Dateitypen, SHA-256-Werte, leere Ordner und gegebenenfalls Linkziele erfassen. In beiden Dateibereichen je eine unbeteiligte Kontrolldatei ablegen.

| Aktion | Prüfung vor Rückgängig | Prüfung nach Rückgängig |
| --- | --- | --- |
| Kopieren | Der Zielbaum entspricht dem Quellmanifest. | Der Zielbaum verschwindet. Die Quelle bleibt erhalten. |
| Verschieben | Der Zielbaum entspricht dem Quellmanifest und der alte Quellpfad ist frei. | Der frühere Quellpfad enthält wieder den vollständigen Baum. |
| Ersetzen | Ein vorhandener gleichnamiger Zielordner mit anderer Testdatei wird nach ausdrücklicher Bestätigung ersetzt. | Der frühere Zielordner mit seiner ursprünglichen Datei kommt zurück. |
| Umbenennen | Der Baum liegt unter dem neuen Namen und hat unveränderten Inhalt. | Der alte Name und das ursprüngliche Manifest sind wieder vorhanden. |
| Ordner anlegen | Der neue Ordner existiert und ist leer. | Der neue Ordner verschwindet. |
| ZIP erstellen | Das gespeicherte ZIP unabhängig öffnen. Alle Einträge und Prüfsummen müssen stimmen. Hierfür reguläre Dateien und Ordner aus D1 verwenden. | Das ZIP verschwindet und der gepackte Quellbaum bleibt erhalten. |
| Entpacken | Ein separat erstelltes ZIP in den anderen Dateibereich entpacken. Die entpackten Pfade und Prüfsummen entsprechen dem Archiv. | Die entpackten Einträge verschwinden. Das Quellarchiv bleibt bytegenau erhalten. |

Jeweils genau einen passenden Historieneintrag prüfen und dessen eigene Schaltfläche «Rückgängig» verwenden. Bei Ordner, ZIP-Erstellung und Entpacken vor dem Rückgängig die App normal neu starten. Anschliessend die beiden Ausgangsmanifeste vergleichen und prüfen, dass der Eintrag aus der aktiven Historie verschwunden ist.

Der signierte Mac-Build 372 bestand diese sieben getrennten Durchläufe auf APFS. Beide Dateibereiche entsprachen nach jedem Rückgängig exakt dem jeweiligen Ausgangsmanifest. Bei den drei Neustartvarianten blieb genau der ursprüngliche Historieneintrag verfügbar.

### Leere und beschädigte Archive am Online-Ort prüfen (ARCH-07)

1. An einem eigenen beschreibbaren Testort ein gültiges leeres ZIP, eine beschädigte ZIP-Datei und ein gültiges ZIP mit einem leeren Ordner und einer Unicode-Datei ablegen. Die Originale und eine Kontrolldatei unabhängig hashen.
2. Das leere ZIP entpacken. Die App muss melden, dass das Archiv keine Einträge enthält. Der Ort bleibt frei von neuen Dateien und Ordnern. Anschliessend das beschädigte ZIP entpacken. Die App muss melden, dass es nicht gelesen werden konnte. Den Ort über einen zweiten Client oder direkt am Testserver überprüfen.
3. Das gültige ZIP entpacken und die neue Struktur, den leeren Ordner und den SHA-256-Wert der Unicode-Datei unabhängig prüfen. Die App normal neu starten und den zugehörigen Historieneintrag rückgängig machen. Alle Originale und die Kontrolldatei müssen den Ausgangswerten entsprechen.

Build 372 legte beim Entpacken eines gültigen leeren ZIPs auf einem echten lokalen FTP-Testserver einen leeren Ordner an. Build 374 erklärte leere und beschädigte Archive getrennt. Das Serverprotokoll enthielt in beiden Fällen keine Ordnererstellung und keinen Upload. Ein gültiges ZIP ergab die erwartete Unicode-Datei und einen leeren Unterordner. Der ursprüngliche Historieneintrag blieb nach App-Neustart verfügbar. Rückgängig entfernte den veröffentlichten Ordner. Die unabhängige Prüfung bestätigte die Originalarchive sowie die lokalen und serverseitigen Kontrolldateien. Der Lauf belegt den gemeinsamen Online-Entpackpfad mit FTP als Gegenstelle. Beim separaten lokalen APFS-Test mit Build 373 erschien die Meldung zum leeren Archiv ebenfalls und der Zielordner blieb unverändert.

### Entpacken in den gegenüberliegenden Dateibereich prüfen

1. Ein ZIP mit `Plain.txt` und `Docs` anlegen. `Docs` enthält eine Unicode-Datei und einen leeren Ordner. Im gegenüberliegenden Bereich `Plain.txt` und `Docs` bereits mit anderen Inhalten anlegen. Die Ausgangsordner und ihre Prüfsummen erfassen.
2. «Entpacken» getrennt für FTP → lokal, lokal → FTP und zwischen zwei FTP-Orten ausführen. `Plain (2).txt` und `Docs (2)` müssen direkt im gewählten Zielordner liegen. In den vorhandenen gleichnamigen Einträgen und neben dem Quellarchiv darf sich nichts ändern. Unicode-Datei und leeren Unterordner im Ziel unabhängig prüfen.
3. OpenCommander normal neu starten und die passenden Historieneinträge rückgängig machen. Das Ziel muss wieder dem Ausgangsstand entsprechen. Der Mac-Build 375 legte für das lokale Ziel einen gemeinsamen Eintrag und für FTP-Ziele einen Eintrag pro veröffentlichtem Objekt an.
4. Für die Gegenprobe das Lesen des Quellarchivs am eigenen FTP-Testserver verzögern. Währenddessen den gewählten lokalen Zielordner umbenennen und seinen alten Pfad durch einen neuen Ordner mit einer Kontrolldatei belegen. Den Server freigeben. Die App muss den Zielwechsel melden. Beide Ordner und das Quellarchiv müssen unverändert bleiben.
5. Das ZIP auf der lokalen Seite öffnen, `Plain.txt` auswählen und nach FTP entpacken. Nur `Plain (2).txt` darf hinzukommen. In einem getrennten Lauf im ZIP zu `Docs` wechseln und ohne Dateiauswahl entpacken. Nur der Inhalt von `Docs` darf in `Docs (2)` erscheinen. Beide Durchläufe nach App-Neustart rückgängig machen.

Der signierte Mac-Build 375 bestand alle sechs Durchläufe in der App. Die drei Entpackrichtungen und die beiden Varianten der Archivauswahl wurden über einen lokalen FTP-Testserver und APFS geprüft. Für direkte Cloud-Verbindungen ist ein eigener Durchlauf erforderlich.

### Ein ganzes Archiv mit einem Klick rückgängig machen

1. Das Testarchiv mit beiden Einträgen aus dem vorherigen Test nach FTP entpacken. Die App neu starten. Eine gemeinsame Karte in der Historie muss beide neu veröffentlichten Pfade nennen. Ein Klick auf «Rückgängig» muss den ursprünglichen Zielinhalt wiederherstellen.
2. Den Test wiederholen und vor «Rückgängig» die zuvor entpackte Unicode-Datei auf dem Testserver ändern. Der unveränderte Eintrag darf rückgängig gemacht werden. Der geänderte Ordner muss mit seinen neuen Bytes erhalten bleiben. Nach Wiederherstellen der ursprünglichen Bytes und App-Neustart muss derselbe Historieneintrag die ausstehende Aktion ausführen.
3. In einem getrennten Durchlauf den letzten Upload am eigenen FTP-Testserver vor dem Schreiben vorübergehend ablehnen. Die App neu starten, den Server freigeben und «Fortsetzen» wählen. Nach erneutem Start müssen beide erfolgreich veröffentlichten Einträge dieselbe Rückgängig-Aktion anbieten. Deren Ausführung muss den ursprünglichen Zielinhalt wiederherstellen.

Der signierte Mac-Build 376 bestand diese Nachtests auf einem lokalen FTP-Testserver. Die App speichert den Rückgängig-Stand pro Eintrag. Bei einem Konflikt bleiben bereits abgeschlossene Rückgängig-Schritte erhalten. App-eigene Wiederherstellungspfade werden separat in der Historie angezeigt.

### Archiv am Online-Ort im selben Bereich öffnen

1. Ein eigenes ZIP mit einem Unterordner und zwei Textdateien auf den FTP-Testserver legen. Die Prüfsumme des Archivs erfassen. Daneben eine Kontrolldatei ablegen.
2. Das ZIP in der FTP-Dateiliste doppelt anklicken. Im selben Dateibereich sollen die Archiveinträge und der Online-Pfad erscheinen. Den Unterordner öffnen und eine einzelne Textdatei in der Vorschau anzeigen. Dieselbe Datei in den gegenüberliegenden Bereich entpacken. Dort dürfen nur der benötigte Unterordner und die gewählte Datei hinzukommen.
3. Über «Zurück» aus dem Archiv zum FTP-Ordner wechseln und das Archiv über «Vorwärts» wieder öffnen. Auch «Übergeordnet» im Archiv-Unterordner und danach im Archivstamm prüfen. Die temporäre Archivkopie soll nach dem Verlassen verschwinden, sobald laufende Zugriffe beendet sind.
4. «Rückgängig» für das gezielt entpackte Mitglied ausführen. Der gegenüberliegende Dateibereich muss wieder den ursprünglichen Inhalt haben. Die Server-Prüfsumme und die Kontrolldateien vergleichen. App neu starten und den zuletzt aktiven FTP-Ordner prüfen.
5. In getrennten Durchläufen ein beschädigtes ZIP öffnen und «Öffnen mit …» bei einem gültigen ZIP wählen. Das beschädigte ZIP muss eine lesbare Fehlermeldung im FTP-Bereich ergeben. «Öffnen mit …» muss den gewohnten Speichern-Dialog anbieten. Den Dialog abbrechen und den Online-Ordner prüfen.
6. Den Abruf des Testarchivs am FTP-Server vorübergehend anhalten. Im betroffenen Bereich einen lokalen Testordner öffnen und erst dann den Abruf freigeben. Der lokale Bereich muss ausgewählt bleiben. In einem getrennten Lauf aus einem bereits geöffneten Archiv zum lokalen Testordner wechseln. Die App neu starten und prüfen, dass der zuletzt gewählte lokale Ort erhalten bleibt.

Mac-Build 376 öffnete beim Doppelklick den Speichern-Dialog. Der signierte Build 379 öffnete ZIP und TAR.GZ im gewählten Dateibereich. Der App-Nachtest bestätigte die Dateivorschau, gezieltes Entpacken mit Rückgängig, «Zurück», «Vorwärts» und «Übergeordnet». Nach dem Verlassen und beim regulären Beenden wurde die jeweilige temporäre Kopie aufgeräumt. Ein beschädigtes ZIP blieb mit sichtbarer Meldung in der FTP-Dateiliste. «Öffnen mit …» bot weiterhin den Speichern-Dialog an, und Abbrechen führte zum FTP-Ordner zurück. Beide Versuche mit einem Wechsel zum lokalen Ort bestanden. Eigene Abnahmeläufe mit direkten Cloud-Konten stehen aus.

### F5 im geöffneten Archiv prüfen

1. Das Archiv und die gleichnamigen Ziele aus dem [Entpacktest](#entpacken-in-den-gegenüberliegenden-dateibereich-prüfen) verwenden. Das Archiv auf dem FTP-Testserver im Dateibereich öffnen, zu `Docs` wechseln und die Unicode-Datei auswählen. **F6** muss den Schreibschutz des Archivs melden. Quelle, Ziel und Historie bleiben unverändert.
2. Mit derselben Auswahl **F5** drücken. Im lokalen Ziel müssen `Docs (2)` und darin die ausgewählte Datei erscheinen. Der leere Nachbarordner darf dabei nicht mitkopiert werden. Die früheren Zieleinträge und das Quellarchiv unabhängig prüfen. Die App neu starten, den neuen Historieneintrag rückgängig machen und das Ausgangsmanifest des Ziels vergleichen.
3. Dasselbe Archiv lokal öffnen. Innerhalb von `Docs` ohne Auswahl **F5** drücken. `Docs (2)` muss die Datei und den leeren Ordner enthalten. `Plain.txt` bleibt unverändert. Nach App-Neustart Rückgängig und die Prüfsummen bestätigen.
4. Für vollständiges Kopieren ohne Auswahl im Archivstamm **F5** auslösen. Die Varianten lokal → FTP und FTP → FTP getrennt prüfen. `Docs (2)` und `Plain (2).txt` müssen direkt im Ziel erscheinen und nach App-Neustart über dieselbe Historienkarte rückgängig zu machen sein.
5. In getrennten Gegenproben eine lokale Datei per **F5** in ein bereits geöffnetes Archiv kopieren und anschliessend ein ZIP in einer normalen Ordnerliste markieren und per **F5** in einen gewöhnlichen Zielordner kopieren. Das Archiv als Ziel muss mit einer Schreibschutzmeldung abgewiesen werden. Die ZIP-Datei als Quelle muss mit unveränderter Prüfsumme im normalen Ziel erscheinen und rückgängig zu machen sein.

Build 379 wies F5 aus dem in der App geöffneten FTP-Archiv mit einer Schreibschutzmeldung ab. Im signierten Build 380 bestanden alle sechs Varianten mit APFS und einem eigenen FTP-Testserver. Die unabhängige Prüfung bestätigte die Zielstruktur und SHA-256-Werte sowie die ursprünglichen Inhalte nach Rückgängig und App-Neustart. Direkte Cloud-Orte brauchen einen eigenen Nachtest.

### Zielordner während des Entpackens austauschen

1. Ein ZIP und ein TAR.GZ mit `Docs/Prüfung 日本語.txt`, einem leeren Unterordner und einer Datei im Archivstamm erstellen. Im gegenüberliegenden Testordner eine gleichnamige Struktur mit anderen Bytes sowie eine Kontrolldatei ablegen. Die SHA-256-Werte der Originale erfassen.
2. Für den gezielten Durchlauf das Archiv öffnen, im Archiv zu `Docs` wechseln und den nächsten Lesezugriff auf das Testarchiv über einen Testadapter anhalten. **F5** drücken und die sichtbare Fortschrittsanzeige abwarten. Den Zielordner umbenennen und seinen alten Pfad durch einen neuen Ordner mit einer anderen Kontrolldatei belegen. Dann das Lesen freigeben. Den Durchlauf für beide Archivformate wiederholen.
3. Die App muss den ausgetauschten Zielordner melden. Die beiden Ordner, das Archiv und die Historie unabhängig prüfen. Im Ersatzordner darf kein entpackter Inhalt erscheinen, und es darf keinen erfolgreichen Historieneintrag geben.
4. In einem getrennten Lauf das Lesen ebenfalls anhalten und **Abbrechen** wählen, bevor der Adapter es freigibt. Ohne Ordnerwechsel müssen beide Ausgangsmanifeste und die leere Historie erhalten bleiben.
5. Als Kontrolle das Archiv bei unverändertem Ziel normal per F5 kopieren. `Docs (2)` muss ausschliesslich den Inhalt des aktuellen Archivordners enthalten. Die App neu starten, den passenden Eintrag rückgängig machen und beide Ausgangsmanifeste vergleichen. Bei einem Laufwerkstest für das Ziel ein separates Testmedium verwenden.

Mac-Build 380 entpackte ZIP und TAR.GZ in den Ersatzordner und meldete Erfolg. In Build 381 blieben nach dem Zielordnerwechsel beide Ordner und die Historie unverändert. Zwei Abbruchtests erhielten dieselben Ausgangsdaten. Normales Kopieren mit Namenskonflikt und Rückgängig nach App-Neustart bestand auf APFS, SMB sowie je einem frisch erzeugten exFAT- und FSKit-NTFS-Abbild. Die unabhängige Nachprüfung bestätigte auch die Bytes im privaten Rückgängig-Ordner. Die beiden Abbilder wurden nach der Prüfung wieder ausgehängt.

### Cloud-Archiv mit gleicher Grösse und neuer Version prüfen

1. Zwei eigene ZIP-Dateien mit identischem Dateinamen und exakt gleicher Länge vorbereiten. Das ausgewählte Textmitglied muss unterschiedliche Bytes haben. Für beide Archive Objekt-ID, Version und SHA-256 festhalten. Am lokalen Ziel einen Ordner mit demselben Namen und eine Kontrolldatei anlegen.
2. Die erste Version in OpenCommander auflisten. Im kontrollierten Testtransport erst nach dieser Auflistung unter gleichem Namen und gleicher Grösse die zweite Version bereitstellen. Beim Doppelklick auf die alte Zeile muss die App die Änderung melden und im Online-Ordner bleiben. Der Testtransport darf keinen Archivdownload melden. Das lokale Ziel und die Historie unabhängig prüfen.
3. Den Test zurücksetzen. Die Version diesmal erst nach dem Abruf der ersten Archivbytes und vor der letzten Versionsprüfung wechseln. Die App muss auch dann im Online-Ordner bleiben. Den temporären Download und den leeren Verlauf prüfen. Das Ziel und die Kontrolldatei müssen weiterhin ihre ursprünglichen Prüfsummen haben.
4. Die Dateiliste mit der neuen Version aktualisieren und das ZIP erneut öffnen. Ein einzelnes Mitglied per **F5** in den anderen Dateibereich kopieren. Nur dessen Bytes und der benötigte Unterordner dürfen im Ziel erscheinen. Nach App-Neustart den Kopiereintrag rückgängig machen und beide Ordner unabhängig prüfen.
5. Die beiden Versionswechsel getrennt mit **Entpacken** direkt aus der Online-Dateiliste wiederholen. Bei einem Wechsel vor dem Abruf bleiben Archivdownload und Ausgabe aus. Bei einem Wechsel während des Downloads muss die App die Arbeitskopie entfernen. Der sichtbare Fehler darf keinen erfolgreichen Historieneintrag mit «Rückgängig» erzeugen. Je eine frisch gelistete Version zur Kontrolle vollständig entpacken. Bei gleichnamigen Ordnern die Originale erhalten und beide neuen Einträge nach App-Neustart gemeinsam rückgängig machen.

Mit simuliertem Dropbox-Transport öffnete Build 381 nach dem Austausch die neue Datei aus der alten Zeile. Der signierte Build 382 stoppte vor dem Download und räumte bei einem Wechsel während des Downloads die temporäre Datei auf. Zwei weitere App-Läufe öffneten je eine frisch gelistete Archivversion und bestanden die gezielte Kopie mit Rückgängig nach Neustart. Diese Nachtests verwendeten eigene Testdaten und eine isolierte App-Konfiguration.

Bei «Entpacken» direkt aus der Online-Dateiliste konnte Build 382 noch aus der Ersatzdatei schreiben. Der signierte Build 383 bestand die beiden Wechselvarianten und die beiden Kontrollläufe mit simuliertem Dropbox-Transport. Die Fehlerfälle hinterliessen einen Historieneintrag ohne «Rückgängig». Die Kontrollläufe bestätigten Archiveinträge, Unicode-Namen, leere Ordner und gemeinsames Rückgängig nach einem App-Neustart. Ein separater simulierter OneDrive-API-Test bestätigte den Versionsschutz für dieselbe Aktion.

### Online-Vorschau während eines Downloads wechseln und schliessen (MEDIA-06)

1. Drei eigene, klar unterscheidbare Bilder in einen Online-Testordner legen. Für FTP das rote Bild über der automatischen Miniaturgrenze und innerhalb der Vorschaugrenze anlegen. Auf dem Testserver ausschliesslich dessen Inhaltsabrufe verzögern.
2. Das rote Bild in der Vorschau öffnen und die Ladeanzeige sowie den begonnenen Abruf bestätigen. Mit Rechts, Links, Rechts und nochmals Rechts blättern. Die dritte Vorschau muss sofort nach der Dekodierung und einige Sekunden später dasselbe blaue Bild zeigen.
3. Zweimal nach links zum roten Bild blättern. Einen weiteren laufenden Abruf beobachten und die Vorschau über ihre Schaltfläche schliessen. Der Testserver muss für jeden verzögerten Abruf den Verbindungsabbruch verzeichnen. Die Dateiliste muss wieder sichtbar sein. Originaldateien, Kontrolldateien und leere Historie unabhängig prüfen.

Der signierte Mac-Build 376 bestand den Durchlauf am lokalen FTP-Testserver. Die Vorschau zeigte bei beiden Messungen die erwarteten blauen Pixel. Der Server bestätigte, dass alle drei absichtlich verzögerten Abrufe abgebrochen wurden. Der Nachweis ergänzt die getrennten Google-Drive- und Dropbox-Durchläufe.

### Online-Video bei einem Stillstand erneut laden (MEDIA-04 und MEDIA-09)

1. Ein kurzes eigenes MP4 und eine Datei mit einer Grösse von 2 GiB plus einem Byte am FTP-Testserver bereitstellen. Den ersten Inhaltsabruf des kurzen Videos bestätigen und anschliessend ohne Datenübertragung offen halten.
2. Das kurze Video öffnen. Ladeanzeige und Abbrechen müssen sichtbar sein. Nach der Zeitgrenze muss die App den Stillstand melden und «Erneut versuchen» anbieten. Am Server prüfen, dass die erste Verbindung beendet wurde.
3. «Erneut versuchen» anklicken. Der zweite Abruf muss zur Wiedergabe führen. Mit Zeitleiste, Wiedergabe und Pause prüfen, ob sich die Abspielposition wie erwartet ändert. Danach die Vorschau schliessen und prüfen, ob die Dateiliste wieder sichtbar ist.
4. Die Datei über 2 GiB zur Vorschau wählen. Die App muss ihre Grössengrenze melden. Der Server darf für diese Datei keinen Inhaltsabruf sehen. Beide SHA-256-Werte, die lokale Kontrolldatei und die leere Historie prüfen.

Im signierten Mac-Build 376 endete der gehaltene FTP-Abruf nach 30,03 Sekunden. «Erneut versuchen» startete die Wiedergabe. Springen in der Zeitleiste, Wiedergabe und Pause funktionierten. Der Server erhielt zwei Abrufe für das kurze Video. Die App lehnte die Datei über 2 GiB vor dem ersten Abruf ab.

### Rückgängig nach einer Änderung am lokalen Cloud-Kopierziel prüfen (TRASH-06)

1. Eine eigene Datei über eine direkte Cloud-Verbindung in einen lokalen Testordner ziehen und die gleichnamige lokale Datei mit «Ersetzen» überschreiben. Die Prüfsummen der drei Dateien festhalten: Cloud-Quelle, frühere lokale Version und separate Kontrolldatei. Vor dem nächsten Schritt den erfolgreichen Auftrag und seinen Historieneintrag bestätigen.
2. OpenCommander schliessen. Mit einem unabhängigen Werkzeug ein Byte in der heruntergeladenen Datei ändern. Die Länge und nach Möglichkeit den Änderungszeitpunkt beibehalten. Die neue Prüfsumme erfassen.
3. OpenCommander öffnen und den abgeschlossenen Auftrag rückgängig machen. Die App muss die geänderte Zieldatei melden und den Historieneintrag behalten. Zieldatei, Kontrolldatei und Cloud-Quelle anhand ihrer Prüfsummen prüfen. Bei Zugriff auf die Sicherung auch die frühere lokale Version prüfen.

Der signierte Mac-Build 322 stoppte «Rückgängig» für beide isoliert getesteten Kopien aus Dropbox und Google Drive und meldete die Änderung. Die bearbeitete Version, die ursprüngliche lokale Sicherung, die Kontrolldatei und die Cloud-Quelle blieben bytegenau erhalten.

Für den Gegenversuch eine eigene lokale Datei per F6 verschieben und die gleichnamige Zieldatei ersetzen. Danach am ursprünglichen Quellpfad eine andere eigene Datei anlegen. «Rückgängig» muss den Konflikt melden und Quelle, Ziel und Sicherung bitgenau erhalten. Die neu angelegte Datei aus dem Quellpfad weglegen und denselben Historieneintrag erneut rückgängig machen.

Beide Varianten sind in Mac-Build 426 mit eigenen D1-Testdateien belegt. Beim bearbeiteten Google-Drive-Kopierziel blieb sogar bei gleicher Grösse, gleichem Inode und gleicher Änderungszeit die neue Version geschützt. Im Verschiebeversuch blieb der neu belegte Quellpfad erhalten. «Rückgängig» stellte in beiden Fällen nach Behebung des Konflikts die vorherigen Inhalte bytegenau wieder her.

### Lokalen Ersatz nach einem Cloud-Verschieben rückgängig machen

1. Eine eigene Online-Datei aus einem isolierten Konto in einen lokalen Testordner verschieben und dort eine gleichnamige andere Version ersetzen. Identität und SHA-256 der Online-Datei, Prüfsumme der vorherigen lokalen Version und eine Kontrolldatei erfassen. Den Historieneintrag des Verschiebens prüfen.
2. «Rückgängig» wählen. Den Testprozess unterbrechen, nachdem der ursprüngliche Name online wieder sichtbar und die neuere lokale Datei weggelegt ist. Die App neu starten und feststellen, dass der alte lokale Inhalt noch aussteht. Derselbe Historieneintrag muss weiter verfügbar sein.
3. In einer separaten Variante die ursprüngliche Online-Datei während der Unterbrechung in einen anderen eigenen Testordner verschieben. Beim erneuten «Rückgängig» muss die App die Abweichung melden. Online-Objekt und lokale Sicherungen müssen erhalten bleiben. Anschliessend dieselbe Online-Datei mit ihrem ursprünglichen Namen zurücklegen.
4. «Rückgängig» erneut wählen. Die frühere lokale Version muss exakt zurückkehren. Die Online-Datei muss ihre ursprüngliche Objekt-ID und Prüfsumme behalten. Bei einer weiteren Unterbrechung nach dem lokalen Wiederherstellen muss der nächste Versuch denselben Abschluss erkennen. Für die bereits wiederhergestellte Online-Datei darf kein weiterer Umbenennungsauftrag gesendet werden.
5. Den Fall mit Google Drive und Dropbox wiederholen. Vor dem erneuten «Rückgängig» eine zweite Testdatei mit identischem Namen und Inhalt, aber anderer Provider-ID an den Originalpfad legen. Die App muss die fremde Datei, das lokale Ziel und die Sicherung unverändert lassen. Danach das ursprüngliche Online-Objekt unter demselben Namen zurücklegen. Mit einer neuen App-Sitzung muss «Rückgängig» die frühere lokale Version wiederherstellen, auch wenn die App dem Online-Objekt beim Auflisten eine neue interne Pfad-ID gegeben hat.

Der macOS-Nachtest für Build 416 lud den gespeicherten Historieneintrag mit kontrollierten OneDrive-Antworten und echten APFS-Testdateien. Er bestätigte beide Wiederaufnahmepunkte und den sicheren Stopp bei fehlender Online-Datei. Zwei ergänzende automatisierte Nachtests für Build 417 bestätigten die Fälle mit geänderter Pfad-ID und fremder Datei für Google Drive und Dropbox mit kontrollierten Provider-Antworten.

Mit echten Google-Drive- und Dropbox-Testdateien bestand der Ablauf auch im Transfer- und Historiencode. Pro Dienst wurde ein isolierter Testprozess nach dem Speichern des Wiederherstellungsstands und ein weiterer nach dem Weglegen der neueren lokalen Datei beendet. Ein neuer Prozess lehnte das gleichnamige Ersatzobjekt ab. Nach Rückkehr der ursprünglichen Provider-ID stellte «Rückgängig» die vorherige lokale Version bytegenau aus derselben Historie wieder her. Der anschliessende Kontrolllauf löste keinen weiteren Provider-Schreibzugriff aus. Der Durchlauf über die sichtbare App steht aus.

### Rückgängig bei einer Änderung der Sicherung während der Wiederherstellung

1. In einem isolierten Windows-Testprofil eine eigene lokale Testdatei durch eine gleichnamige Datei mit anderem Inhalt ersetzen. Prüfsummen der Quelle, des sichtbaren Ziels und der erstellten Sicherung erfassen. Eine unabhängige Kontrolldatei daneben anlegen.
2. «Rückgängig» aus der Historie starten. In einem instrumentierten Test-Build den Vorgang nach der ersten erfolgreichen Prüfung der Sicherung und vor dem Lesen für die Wiederherstellung anhalten, etwa am Prüfpunkt im Debugger. Unabhängig ein Byte in der Sicherung ändern und den Vorgang fortsetzen. Ohne einen kontrollierbaren Prüfpunkt lässt sich die Abbruchvariante mit einer bereits vor «Rückgängig» geänderten Sicherung separat prüfen.
3. Die App muss die Wiederherstellung ablehnen und die sichtbare Zieldatei, Quelle, Kontrolldatei sowie den Historieneintrag erhalten. Prüfsummen und verständliche Fehlermeldung erfassen. Im gespeicherten Historieneintrag muss der fehlgeschlagene Versuch nachvollziehbar bleiben.
4. Die Originalbytes der Testsicherung wiederherstellen, OpenCommander neu öffnen und denselben Eintrag rückgängig machen. Prüfen, dass der Zielpfad wieder exakt die vorherige Dateiversion enthält und die Quelle und Kontrolldatei unverändert sind.

### Rückgängig während des Kopierens der Sicherung abbrechen

1. In einem isolierten Profil einen lokalen Testordner mit vielen Dateien durch eine andere Version ersetzen. SHA-256 und Inventar beider Versionen festhalten und eine unabhängige Kontrolldatei daneben ablegen. Für eine grössere einzelne Datei kann dieselbe Variante wiederholt werden.
2. «Rückgängig» in der Historie wählen. Abbrechen, sobald die App die vorherige Version für die Wiederherstellung kopiert. Den Beginn und den Abbruch anhand der Grösse der noch unvollständigen Kopie im Arbeitsordner oder mit einem Prüfpunkt im Test-Build bestätigen.
3. Das sichtbare Ziel, die Sicherung und die Kontrolldatei anhand ihrer Prüfsummen prüfen. Der angefangene private Kopierstand muss bereinigt sein. Der Vorgang muss mit verständlichem Abbruchstatus in der Historie stehen bleiben.
4. OpenCommander schliessen, neu öffnen und denselben Historieneintrag erneut rückgängig machen. Vorherige Version, Dateianzahl und SHA-256 am Ziel prüfen. Die Kontrolldatei und die Quelle der Kopie bleiben unverändert.

Im isolierten Mac-Build 410 waren beim Maus-Abbruch 258 von 4’800 Dateien im Zwischenstand sichtbar. Die App bereinigte den Zwischenstand, erhielt das sichtbare Ziel und speicherte den Abbruch in der Historie. Nach dem Neustart der App stellte derselbe Eintrag alle 4’800 Dateien mit den ursprünglichen SHA-256-Prüfsummen wieder her.

### Rückgängig nach einem Prozessabbruch fortsetzen

1. In einem separaten Testprofil eine lokale Datei oder einen Ordner per Kopie ersetzen. Die beiden Dateiversionen mit SHA-256 und getrennten Inventaren prüfen. Einen unabhängigen Kontrollinhalt hinzufügen.
2. «Rückgängig» aus der Historie starten. Den isolierten Testprozess einmal direkt nach dem Weglegen der aktuellen Version beenden und in einem separaten Lauf direkt nach dem Sichtbarwerden der früheren Version. Jeweils vor dem Abschluss des Historieneintrags unterbrechen. Die Zeitpunkte mit einem Prüfpunkt im Test-Build oder durch Beobachtung des sichtbaren Zielpfads bestätigen.
3. OpenCommander neu öffnen und den ursprünglichen Historieneintrag prüfen. Für die Konfliktvariante eine unabhängige Testdatei am Zielpfad ablegen, bei Bedarf die bereits wiederhergestellte Version vorher separat weglegen. Auch eine neue Datei mit identischen Bytes darf als fremdes Objekt erhalten bleiben.
4. Die unabhängige Datei weglegen. Falls die frühere Version vor dem Prozessende bereits sichtbar geworden war, genau das ursprüngliche wiederhergestellte Objekt zurücklegen. Denselben Historieneintrag erneut rückgängig machen. Ziel, Kopierquelle und die weggelegte neuere Version anhand ihrer Prüfsummen prüfen. Es darf nur ein Abschluss für die ursprüngliche Aktion entstehen.

Im isolierten Mac-Build 411 wurden beide Prozessabbrüche nach echten Mausaufrufen von «Rückgängig» auf APFS ausgeführt. Nach dem erneuten Öffnen hielt ein fremdes Objekt am Ziel die Wiederherstellung an. Nach Behebung des Konflikts stellte derselbe Historieneintrag alle 4’800 Dateien der vorherigen Version mit exakten SHA-256-Prüfsummen wieder her. Die neuere Version und der unabhängige Kontrollinhalt blieben erhalten.

### Verschiebegruppe nach einem Prozessabbruch rückgängig machen

1. In einem isolierten Profil zwei eigene Testobjekte gemeinsam verschieben und am Ziel jeweils eine andere frühere Version ersetzen. Vor dem Verschieben Dateikennungen und SHA-256-Prüfsummen für Quelle, frühere Zielversion und eine separate Kontrolldatei erfassen.
2. «Rückgängig» für die Gruppe starten. Sobald das erste Objekt wiederhergestellt ist, den Testprozess während des zweiten Objekts gezielt beenden. Die drei Zeitpunkte separat prüfen. Die neue Zielversion wurde weggelegt, die Quelle wurde bereits wiederhergestellt oder die frühere Zielversion ist bereits wieder sichtbar.
3. Die Test-App neu öffnen. Am ursprünglichen Quellpfad des zweiten Objekts einen unabhängigen Inhalt ablegen. Falls die Quelle bereits wiederhergestellt war, genau dieses Objekt vorher vorübergehend weglegen. «Rückgängig» muss den belegten Quellpfad melden. Für das erste Objekt muss genau eine Wiederherstellung festgehalten sein.
4. Den fremden Testinhalt beiseitelegen und eine bereits wiederhergestellte Originalquelle mit ihrer ursprünglichen Kennung zurücklegen. Denselben Historieneintrag erneut wählen. Beide Quell- und Zielversionen müssen ihre ursprünglichen Prüfsummen haben. Der unabhängige Inhalt muss erhalten bleiben, und die Historie darf keinen zweiten Abschluss für die Gruppe erzeugen.

Mac-Build 414 bestand alle drei Unterbrechungsvarianten auf APFS. Zwei tatsächliche Verschiebevorgänge mit Ersetzen wurden für den Test in einem Historieneintrag zusammengefasst. Nach dem Prozessneustart hielt der belegte Quellpfad die Wiederherstellung an. Nach Behebung des Konflikts stimmten die ursprüngliche Quellkennung und die SHA-256-Prüfsummen sämtlicher 1’800 Dateien je Ordnerversion. Auch die zweite, bereits wiederhergestellte Datei und die Kontrolldatei blieben erhalten.

### Rückgängig nach erneutem Einhängen des ursprünglichen Laufwerks

1. Ein entbehrliches Testvolume und ein zweites eigenes Volume mit anderer Kennung bereitstellen. Zwei Testordner mit unterschiedlichen Inhalten zwischen einem lokalen Ordner und dem Testvolume verschieben. Bei «Ersetzen» die Prüfsummen der ursprünglichen Quelle, des früheren Ziels und einer Kontrolldatei erfassen.
2. «Rückgängig» starten und den Testprozess nach dem Wiederherstellen der Quelle, aber vor dem Wiederherstellen des vorherigen Ziels beenden. Das Testvolume aushängen. In der neu gestarteten App muss «Rückgängig» das fehlende ursprüngliche Laufwerk melden. Der leere Einhängepfad muss leer bleiben.
3. Das zweite Volume am selben Pfad einhängen und dort einen unabhängigen Testordner anlegen. «Rückgängig» muss das ursprüngliche Laufwerk anfordern. Das Inventar und die Prüfsummen auf dem zweiten Volume müssen unverändert bleiben.
4. Das ursprüngliche Volume am gewohnten Pfad mit neuer vorübergehender Gerätekennung einhängen und seine unveränderte Volume-ID separat prüfen. «Rückgängig» für denselben Historieneintrag erneut wählen. Dateikennungen und SHA-256 der wiederhergestellten Quelle, der früheren Zielversion und der unabhängigen Dateien prüfen. Den gesamten Ablauf jeweils mit dem Quell- und dem Ziellaufwerk wiederholen.

Mac-Build 415 bestand beide Varianten mit APFS-Abbildern. Am leeren Einhängepfad entstanden beim Rückgängig-Versuch keine Dateien. Die App meldete das fehlende ursprüngliche Laufwerk auch bei einem anderen Volume mit derselben vorübergehenden Gerätenummer. Nach dem erneuten Einhängen des Originals mit einer neuen Gerätenummer stellte sie je 1’800 Dateien der beiden Ordnerversionen mit exakten SHA-256-Prüfsummen wieder her. Der ursprüngliche Historieneintrag und die Daten auf dem zweiten Volume wurden separat geprüft.

### Rückgängig bei verändertem exFAT-Ziel oder belegter Quelle

1. Eine eigene Datei auf ein exFAT-Testlaufwerk kopieren. Danach direkt auf dem Laufwerk ein Byte der Zieldatei ändern. Länge, Dateikennung und den letzten Schreibzeitpunkt beibehalten. «Rückgängig» wählen. Die Meldung soll sich auf die Rückgängig-Aktion beziehen. Die geänderte Zieldatei und der Historieneintrag bleiben erhalten.
2. Die Test-App schliessen und den gespeicherten Historieneintrag nach dem Neustart öffnen. Auch dort muss dieselbe Ursache verständlich angezeigt werden. Die ursprünglichen Zielbytes aus der Testdatei wiederherstellen und «Rückgängig» erneut ausführen.
3. In einem separaten Durchlauf eine Testdatei auf exFAT verschieben und ihren früheren Quellpfad danach mit einer eigenen Datei belegen. «Rückgängig» muss stoppen. Prüfsummen der verschobenen Datei und des neuen Inhalts vergleichen. Die neue Datei an einen anderen Ort verschieben und «Rückgängig» erneut wählen. Die ursprüngliche Datei muss unter ihrem alten Namen zurückkehren. Die neue Datei bleibt am separaten Ort erhalten.

Im signierten Mac-Build 369 zeigte der bereits in Build 368 gespeicherte Historieneintrag nach dem Versionswechsel den Grund für das gestoppte Rückgängig. Auch ein erneuter Versuch zeigte denselben Grund in der Statuszeile. Der gespeicherte Fehlercode blieb erhalten. Beim veränderten Ziel und beim belegten Quellpfad blieben alle betroffenen Dateien erhalten. Nach dem Wiederherstellen der Zielbytes und dem Freigeben des Quellpfads gelang Rückgängig in beiden Fällen.

### Externe Synchronisierung nach einem Cloud-Download prüfen

1. Dieselbe eigene Testdatei aus einer direkten Cloud-Verbindung einmal auf ein gewöhnliches lokales Laufwerk und einmal in einen externen Ort mit Schreibcache herunterladen. Für den Dateisystempfad zusätzlich einen SMB-Testordner verwenden und «Ersetzen» mit einer gleichnamigen Datei anderer Prüfsumme testen.
2. Die Karte des abgeschlossenen Auftrags prüfen und die App neu starten. Am externen Ziel muss der Status zwischen erfolgtem Dateisystemtransfer und unabhängig bestätigtem Anbieterinhalt unterscheiden. Ein erfolgreiches Sichern oder Lesen vom Cache allein reicht nicht als Anbieterbestätigung. Am gewöhnlichen lokalen Ziel soll kein Hinweis auf externe Synchronisierung erscheinen.
3. SHA-256 am Ziel und bei einem Cache zusätzlich unabhängig am Anbieter prüfen. Beim SMB-Ersetzen «Rückgängig» wählen. Die alte Zieldatei muss ihren früheren Hash zurückerhalten. Prüfe die unveränderte Cloud-Quelle und eine unbeteiligte Datei neben dem Ziel.

Für den zusätzlichen Schreibcache-Test ein eigenes rclone-Laufwerk mit verzögertem Writeback und einem unabhängig lesbaren Test-Backend einbinden. Direkt aus der Cloud zum Laufwerk kopieren. Sobald die Warteschlange fertig meldet, muss der Hash am Laufwerk stimmen und der Hinweis zur unbestätigten Synchronisierung sichtbar sein. Das unabhängige Backend darf in der eingestellten Wartezeit noch leer sein. Nach Ablauf der Wartezeit muss es genau dieselben Bytes enthalten. Die Cloud-Quelle währenddessen unabhängig prüfen. «Verschieben» mit einer separaten Testdatei wiederholen. Ohne bestätigte Übertragung zum Anbieter muss die Cloud-Quelle erhalten bleiben.

Der Mac-Nachtest mit einem eingebundenen lokalen NFS-Export bestätigte den Hinweis zur ausstehenden Synchronisierung. Die 256 KiB wurden später unabhängig am Test-Backend bytegenau bestätigt. Das geschützte Verschieben und «Rückgängig» wurden während des offenen Synchronisationszustands mit einer Erklärung abgelehnt. Die Abnahme an einem Cloud-Anbieter und auf echtem SMB bleibt offen.

### Statuszeile beim Kopieren auf einen Schreibcache

1. Eine eigene 256-KiB-Testdatei auf das zuvor beschriebene eingebundene Testlaufwerk kopieren. Für das Writeback beispielsweise 75 Sekunden Verzögerung einstellen. Sobald die Karte 100 % zeigt, die Zielbytes am eingebundenen Pfad prüfen und den unabhängigen Speicher des Testanbieters kontrollieren.
2. Während die Datei nur im Schreibcache vorliegt, müssen die globale Statuszeile und die Karte auf die unbestätigte externe Synchronisierung hinweisen. Den Auftrag schliessen und die App normal neu öffnen. Die geprüfte Karte und genau ein Historieneintrag sollen zur ursprünglichen Auftrags-ID erhalten bleiben.
3. Vor dem Writeback «Rückgängig» versuchen. Wenn die App die aktuelle Anbieterversion über diesen Mount nicht sicher prüfen kann, muss sie den Vorgang verständlich ablehnen und Quelle, Ziel und Historieneintrag erhalten. Nach dem Upload den SHA-256 zusätzlich über das vom Mount unabhängige Backend prüfen.
4. Eine zweite Testdatei in einen gewöhnlichen lokalen Ordner kopieren. Die Statuszeile soll «Abgeschlossen» anzeigen. «Rückgängig» muss die Zielkopie entfernen und das Original erhalten.

Im signierten Mac-Build 364 waren die Warnung in der Statuszeile und in der kompakten Karte sichtbar, bevor das separate lokale NFS-Test-Backend die Datei enthielt. Nach normalem App-Neustart blieben die Karte und der Historieneintrag erhalten. «Rückgängig» wurde während der ausstehenden Synchronisierung abgelehnt. Die unabhängige Kontrolle bestätigte die 256 KiB rund 75 Sekunden nach Abschluss im Dateisystem. Kopieren und «Rückgängig» auf APFS bestanden als Gegenprobe. Der Nachtest der Statuszeile mit einem direkten Cloud-Konto bleibt offen.

### Cloud-Download bei getrenntem Ziellaufwerk wiederaufnehmen

1. Einen eigenen Cloud-Download auf ein separates Testlaufwerk vorbereiten. Mit einem Testadapter nach erfolgreichem Dateisystemtransfer und vor dem Warteschlangenabschluss den App-Prozess beenden. Die Auftrags-ID und den SHA-256 der Testdatei erfassen. Anschliessend das Testlaufwerk trennen.
2. Die App neu öffnen. In getrennten Läufen «Fortsetzen» und «Abbrechen» am selben gespeicherten Auftrag wählen. Der Auftrag muss pausiert bleiben und auch in der kompakten Ansicht zum Wiederverbinden auffordern. Beim Abbruch muss die ausstehende Prüfung vermerkt bleiben. Am leeren Einbindungspfad dürfen keine Dateien entstehen. Solange die Verbindung fehlt, darf kein erfolgreicher Historieneintrag erscheinen.
3. Dasselbe Testlaufwerk wieder einbinden und denselben Auftrag fortsetzen. Im Abbruchlauf muss die App zuerst die ausstehende Prüfung abschliessen. Die bereits wirksame Kopie muss bytegenau bestätigt und genau einmal in der Historie erfasst werden. Die unabhängige Prüfsumme am Ziel, der unveränderte Inhalt der Quelle und die ursprüngliche Auftrags-ID müssen stimmen.
4. Den Ablauf mit einem Ordner mit zwei Dateien, einem Unicode-Dateinamen und einem leeren Unterordner wiederholen. Für «Fortsetzen» den Prozess während des Lesens der zweiten Datei beenden. Beim Neustart darf der Zähler nur die erste bestätigte Datei umfassen. Nach Wiederverbinden soll nur die zweite Datei nochmals angefordert werden. Für «Abbrechen» den Prozess direkt nach dem lokalen Kopierbeleg beenden. Der Abbruch soll nach Wiederverbinden die vorhandene Kopie mit genau einem Historieneintrag bestätigen. Beide Dateien und der leere Unterordner müssen erhalten bleiben.

Der Mac-Integrationstest mit einem simulierten Cloud-Anbieter und einem tatsächlich eingebundenen lokalen NFS-Export bestätigte beide Abläufe. Beim Wiederaufnehmen wurde genau eine Datei erneut angefordert. Beim Abbruch nach dem Kopierbeleg gab es keinen erneuten Inhaltsdownload. Eine unabhängige Kontrolle am Test-Backend bestätigte die beiden Dateien und den leeren Unterordner. Der Lauf mit echtem SMB und die sichtbare Bedienung bleiben offen.

### Ausgewählte NTFS-Quelldatei nach Medienwechsel fortsetzen

1. In einer Test-VM ein beschreibbares NTFS-Testabbild mit einer Datei vorbereiten. Ein zweites Testabbild mit eigenen Volumekennzeichen sowie demselben Ordnernamen und derselben Datei bereitstellen. Die Datei aus dem ersten Abbild kopieren und den Auftrag pausieren.
2. Das erste Abbild aushängen. «Fortsetzen» wählen und prüfen, dass der Auftrag pausiert bleibt. Das zweite Abbild am gleichen Laufwerksbuchstaben einbinden. Auch dieser Versuch muss stoppen.
3. Das Original wieder einbinden. Denselben Auftrag fortsetzen, Quell- und Zielprüfsummen vergleichen und den Auftrag rückgängig machen. Der Zielordner muss wieder seinem Ausgangszustand entsprechen.

Auf dem Mac bestand der Fall mit virtuellen NTFS-Testabbildern und dem installierten FSKit-Treiber. Das zweite Abbild hatte eine andere Seriennummer. Nach Wiederanschluss des Originals unter einer neuen Gerätekennung wurde derselbe Auftrag korrekt fortgesetzt und rückgängig gemacht. Der Nachtest mit einem physischen NTFS-Gerät steht aus.

Am 19. November bestanden ergänzend 17 Prüfungen der NTFS-Engine und 10 Sicherheitsprüfungen mit frischen Abbildern. Für DEVICE-04 insbesondere die unveränderten vorhandenen Daten nach Platzmangel oder fehlgeschlagenem Ersetzen, genaue Zeitstempel nach erneutem Öffnen und den Nur-Lese-Zugriff bei einem Ruhezustandsabbild nachprüfen. Fehlendes Schreiben auf ein als unsicher erkanntes Abbild ist erwartetes Schutzverhalten. Diese Engine-Prüfungen liefen ausserhalb der App.

### Unvollständigen Cloud-Download nach Prozessabbruch bereinigen

1. Eine eigene Cloud-Testdatei von mindestens 4 MiB in einen eigenen SMB-Testordner kopieren. Eine unbeteiligte Kontrolldatei im selben Ordner anlegen. Den App-Prozess nach dem ersten gespeicherten Datenblock und vor dem Abschluss beenden. Der Zielname muss zu diesem Zeitpunkt eine Teilkopie enthalten.
2. OpenCommander neu öffnen und denselben Auftrag abbrechen. Die eigene Teilkopie muss aus dem Dateifenster verschwinden. Cloud-Quelle und Kontrolldatei müssen an ihren Orten bleiben und dieselben Prüfsummen behalten. Es darf keinen erfolgreichen Historieneintrag geben.
3. Mit «Ersetzen» wiederholen. Nach «Abbrechen» muss das vorherige Ziel unter seinem ursprünglichen Namen und mit seiner ursprünglichen Prüfsumme zurückkehren.
4. Als Gegenprobe die eigene Teilkopie im Testordner durch eine andere Testdatei ersetzen. Die App muss diese Datei erhalten und den Konflikt offen anzeigen. Die Prüfsumme dieser Datei und der Cloud-Quelle unabhängig bestätigen.

### Binärdownload und natives Google-Dokument unterscheiden

1. Im eigenen Google-Drive-Testordner eine gewöhnliche Datei mit der Endung `.docx` hochladen. In einem zweiten Testordner ein natives Google-Dokument mit einem eindeutigen Text anlegen, das der Anbieter unter demselben DOCX-Exportnamen darstellt. Beide Objekt-IDs, die Prüfsumme der gewöhnlichen Datei und den Text des nativen Dokuments erfassen.
2. Die gewöhnliche Datei herunterladen und SHA-256 vergleichen. Danach beim nativen Dokument «Öffnen mit …» oder den vorgesehenen Export verwenden. Der Inhalt des DOCX-Exports muss mit dem Google-Dokument übereinstimmen.
3. Mit einem kontrollierten Testadapter unmittelbar vor dem Lesen den hinterlegten gewöhnlichen Eintrag durch eine Antwort für das native Dokument mit demselben sichtbaren Namen ersetzen. Der gewöhnliche Download oder die Überprüfung einer Kopie muss abbrechen. Es darf keine fertige Zielkopie und keinen erfolgreichen Kopier- oder Rückgängig-Beleg für den Ersatz geben. Beide ursprünglichen Anbieterobjekte bleiben erhalten.

Die frühere macOS-Version des rclone-Befehls für gewöhnliche Downloads exportierte ein echtes Google-Dokument stillschweigend. Im Live-Nachtest vom 19. November 2026 wies der korrigierte Befehl den nativen Eintrag ohne lokale Ausgabe ab. Die normale Datei blieb bytegenau abrufbar. Der ausdrückliche Export lieferte weiterhin den erwarteten Text. Eine unabhängige Anbieterauflistung bestätigte unveränderte Objekt-IDs und Dateimetadaten. Der Live-Nachtest lief mit dem von OpenCommander geprüften rclone-Binary direkt beim Anbieter. Der konkurrierende Austausch in der App hat einen eigenen kontrollierten Regressionstest. [rclone-Dokumentation](https://rclone.org/drive/#drive-skip-gdocs)

Im signierten Mac-Build 325 bestand «Öffnen mit …» auch in der App für beide echten Google-Drive-Objekttypen. Die gewöhnliche Datei wurde bytegenau gespeichert, und der DOCX-Export enthielt den vollständigen Text des nativen Dokuments. Die macOS-App-Auswahl öffnete sich in beiden Fällen. Ihr Abbruch liess die geprüften lokalen Kopien bestehen. Separate Anbieterabfragen bestätigten beide Original-IDs und Inhalte.

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
