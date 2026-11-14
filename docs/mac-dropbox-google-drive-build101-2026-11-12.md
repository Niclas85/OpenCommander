# Dropbox → Google Drive auf macOS, Build 101

Für r1857 wurden je ein eigener Ordner mit eindeutiger Kennung und eine Datei namens `CrossMove.txt` angelegt. Die beiden Dateien hatten unterschiedliche Inhalte. Ein unabhängiger Client erfasste vorab bei beiden Anbietern die Objekt-ID, Länge und SHA-256-Prüfsumme. Die signierte Test-App entsprach dem installierten Build 101 und verwendete ein separates lokales Profil.

In OpenCommander wurde die Dropbox-Datei gewählt und mit F6 nach Google Drive verschoben. Die App zeigte den Namenskonflikt an und bot «Ersetzen» an. Beim ersten Versuch meldete die App vor dem Einreihen ein Zeitlimit. Die Historie zeigte dafür «Gestoppt» und keine verfügbare Rückgängig-Aktion. Ein frischer unabhängiger Abruf bestätigte, dass beide Originale samt Objekt-IDs unverändert geblieben waren. Erst danach wurde F6 mit «Ersetzen» wiederholt. Dieser Versuch wurde als ein einzelner Cloud-Auftrag eingereiht; die native Karte zeigte «Dateipfade werden geprüft» und anschliessend «Datei herunterladen».

Die Fortschrittsanzeige vor dem Einreihen bezog ihre 100 Prozent auf einen einzelnen abgeschlossenen Download, obwohl weitere Prüfungen folgten. Die spätere Auftragskarte unterschied die Prüfphase vom Abschluss. Die Anzeige vor dem Einreihen kann dadurch mit einem Gesamtabschluss verwechselt werden; dieser Lauf ist kein vollständiger Fortschritts- oder Leistungstest.

Eine erneute Zeitüberschreitung stoppte den gespeicherten Auftrag nach 1.315 aktiven Sekunden während der Schlussprüfung bei 99 Prozent. Zu diesem Zeitpunkt fehlte der öffentliche Dropbox-Name bereits. Ein unabhängiger Client bestätigte, dass die exakten Dropbox-Bytes unter dem Zielnamen in Google Drive lagen und die Ziel-ID von der ursprünglichen Drive-ID abwich. Das war noch kein erfolgreicher Auftragsabschluss. «Fortsetzen» startete die Prüfung für dieselbe Auftrags-ID.

Die Wiederaufnahme meldete erneut ein Anbieter-Zeitlimit. Der Auftrag behielt seine ID und den Prüfstand von 99 Prozent; die App bestätigte keinen erfolgreichen Historienbeleg. Der Mac war bei der nächsten Oberflächenprüfung gesperrt. Der zugehörige Rückgängig-Test in Build 101 steht damit aus. Die Belege des früheren erfolgreichen Live-Tests in Build 97 bleiben davon getrennt.

Ein zweiter unabhängiger Abruf nach der gescheiterten Wiederaufnahme bestätigte die gleiche veröffentlichte Ziel-ID und die exakten Dropbox-Bytes. Beide ursprünglichen Objekte lagen weiterhin unter den erwarteten Wiederherstellungsnamen, mit unveränderten IDs und Prüfsummen. Dieser Nachweis belegt ihren Erhalt, aber noch keine Rückgängigmachung. Beleg: `native-cross-b101-resume-timeout-r1857.json`.

## Abschluss am 13. November

Nach der Wiederaufnahme über dieselbe Auftragskarte zeigte Build 101 «Abgeschlossen · 100 %» und einen erfolgreichen Verschiebungseintrag. Ein unabhängiger Client bestätigte dieselbe veröffentlichte Google-Drive-ID wie vor der Wiederaufnahme, den exakten Dropbox-Inhalt am Ziel und das Fehlen des öffentlichen Dropbox-Quellnamens. Der erste vorzeitig gestoppte Versuch blieb in der Historie gesondert sichtbar.

Der Klick auf «Rückgängig» im erfolgreichen Historieneintrag stellte beide Originale wieder her. Die App zeigte «Verschieben · Rückgängig» und beide Dateizeilen. Ein unabhängiger Anbieterabruf bestätigte bei Dropbox und Google Drive die ursprünglichen Objekt-IDs, Längen und SHA-256-Prüfsummen. Das Verschiebungsjournal war aufgeräumt. Belege: `native-cross-b101-moved-r1857.json` und `native-cross-b101-restored-r1857.json`.

Der Quellstand für Build 102 zeigt bei vorbereitenden Einzelabrufen nur Bytes an. Bei bereits erfolgter Quellverschiebung prüft die Wiederaufnahme beide Zielobjekte einmal vor dem Abschluss. Vor einem neuen Schreibschritt bleibt die vorgelagerte Zielprüfung bestehen. Der kontrollierte Regressionstest simuliert eine verlorene Dropbox-Antwort nach der Quellverschiebung, prüft zwei Zielabrufe ohne erneute Schreiboperation und stellt beide Originale mit Rückgängig wieder her.

## Weitere Prüfungen ohne WebDAV

Neun gezielte Suiten endeten erfolgreich. Die Protokolle zählen 39 exFAT-, 25 NTFS/exFAT-, 62 Cloud-Warteschlangen-, 15 Karten-, 18 Drag-and-drop-, 62 Historienlokalisierungs-, 500 Cloud-Checkpoint-, 3 Remote- und 113 CloudClient-PASS-Zeilen. Die Zähler beschreiben Prüfschritte der Suiten, keine zusätzlich vollständig abgenommenen Fälle des 158-Fälle-Protokolls. Der NTFS/exFAT-Test verwendete die installierte FSKit-Erweiterung und frische Abbilder; der physische Datenträger und ein NAS waren nicht eingebunden. Beide Abbilder wurden ausgehängt. Die Drag-and-drop-Suite prüfte die Implementierung automatisiert; daraus folgt keine vollständige Fremdprogramm-Abnahme.

Der D2-Start scheiterte bereits in der Vorprüfung am verfügbaren Speicher und legte keine Testdaten an. WebDAV wurde nicht geprüft. Nachweise für die Suite-Ergebnisse liegen in `regression-results-r1857.json` und den dazugehörigen `*-b101-r1857.log` unter `ntfs/NTFS3G/.build-native/acceptance-20261030`.

## Installierte Fassung

Am 14. November wurde Build 102 installiert und gestartet. Entwickler-Signatur, Notarisierung und Gatekeeper wurden am installierten Paket geprüft. Historie, beide Warteschlangen und gespeicherte Fensterbereiche waren nach dem Start erhalten. Der im Leerlauf verbliebene alte App-Prozess wurde für den Austausch beendet. macOS blieb in derselben Boot-Sitzung.

Die Cloud-Checkpoint-Suite zählte 501 erfolgreiche Prüfschritte, darunter die gezielt reproduzierte Wiederaufnahme nach verlorener Dropbox-Antwort. Die Warteschlangen- und Auftragskarten-Suiten bestanden ebenfalls. Der anschliessende Test der installierten FSKit-Erweiterung bestand 25 Schritte mit isolierten NTFS- und exFAT-Abbildern. Nach erneutem Einbinden liessen sich Verschiebungen in beide Richtungen fortsetzen und mit exakten Bytes rückgängig machen. Beide Abbilder wurden ausgehängt.

Der vollständige Live-Durchgang mit Dropbox, Google Drive und Rückgängig lief in Build 101. Build 102 bestand die kontrollierte Regression und die Installationsprüfung. Das frühere Live-Testprofil wurde nach dem Rückgängig geschlossen und seine temporären Zugangsdatenkopien wurden entfernt. Der vollständige D2-Lauf bleibt offen. Die erneute Vorprüfung fand 13,58 GB verfügbar bei 18,79 GB Bedarf. Es war kein physisches Testlaufwerk und kein NAS eingebunden.

Nachweise sind `postinstall-b102-r1858.json`, `installed-distribution-b102-r1858.log`, `cloud-checkpoint-retirement-final-r1858.log`, `ntfs-exfat-b102-r1859.log` und `d2-capacity-r1859.json`.

Die zusätzliche Speicher- und Ordnerprüfung bestand 18 Schritte. Die Registrierungsprüfung der NTFS-Erweiterung bestand drei Schritte. Die XCTest-Vorprüfung meldete, dass macOS für den Automationsmodus eine Benutzerauthentifizierung verlangt. Sie startete keinen Oberflächentest. Nachweise sind `cloud-storage-b102-r1859.log` und `ntfs-registration-b102-r1859.log`.

## Weitere Prüfungen für Build 102

Im separaten Profil zeigte die native Textvorschau die genaue UTF-8-Testzeile mit Umlauten und japanischen Zeichen. Zwei kurze Ziehversuche mit der Computersteuerung lieferten keine Kopie. Der bereits freigegebene Maus-Testtreiber prüfte den Prozess und beide sichtbaren Fensterpunkte und löste eine Ziehgeste zwischen den lokalen Bereichen aus. Die 47-Byte-Kopie hatte dieselbe SHA-256-Prüfsumme wie die Quelle. Rückgängig über die Historie entfernte die Kopie, und die Quelle blieb bytegleich.

Fünf NFS-Szenarien auf lokalen rclone-Testfreigaben bestanden mit 24 PASS-Zeilen. Geprüft wurden Wiederaufnahme nach Offline-Zustand, Abbruch mit verändertem Ersatzziel, eine fremde Freigabe am selben Endpunkt, Wiederaufnahme nach erneutem Einbinden und ein FTP-Ziel, das Anhängen verweigert. Beim FTP-Test wurde nur die unvollständige Datei erneut vollständig geschrieben. Der Abschluss meldete nicht erhaltene Zeitstempel. Die Freigaben wurden ausgehängt. Die Suiten für Cloud-Bindung, Speicheridentität, Drag-and-drop und Vorschau bestanden ebenfalls.

Der 7.200-Sekunden-Dauerlauf läuft mit vier unabhängigen Cloud-Adaptern im selben Testprozess. Die Prozessprüfung bestätigte alle vier laufenden Testaufträge mit verifizierten Zyklen. Die Adapter simulieren Verbindungsabbrüche. Der Abschluss, der vollständige D2-Ablauf und die physische Netzwechselprüfung stehen aus.

Nachweise sind `native-local-drag-preview-b102-r1860.json`, `nfs-recovery-b102-r1860.log`, `cloud-endurance-b102-r1860.log` und `cloud-endurance-b102-observation-r1860.json`.

## Ersatzmedium und NTFS-Sicherheit

Im Test r1864 lehnte die installierte Build-102-Erweiterung zusammen mit der Produktionslogik der Warteschlange die Wiederaufnahme und den ausstehenden Abbruch auf einem anderen NTFS-Abbild ab. Das Ersatzabbild lag am selben Mountpfad und enthielt die gleichen Journaldaten, hatte aber eine andere NTFS-Seriennummer. Fortschritt und Reservierungen blieben erhalten. Nach erneutem Einbinden des ursprünglichen Abbilds beendete ein neuer Prozess die Datei- und Ordnerkopien bytegenau. Rückgängig liess die Quelle unverändert. Beide Abbilder wurden ausgehängt.

Der separate NTFS-Engine-Test verwendete eigene ungemountete Abbilder. Dirty-Flag, Windows-Ruhezustand und nicht lesbare Metadaten wurden erkannt. Der Test bestätigte die jeweiligen Schutzprüfungen und den Erhalt der Abbilddaten. Der Cloud-Runtime-Test bestand unter anderem bei falscher ZIP-Prüfsumme, unterbrochenem Download und zu offenen Konfigurationsrechten.

Nachweise sind `ntfs-wrong-volume-b102-r1864.log`, `ntfs-safety-b102-r1864.log` und `cloud-runtime-b102-r1864.log`.

## Live-Wiederholung mit installiertem Build 102

Am 14. November wurde der Test mit neuen Testdateien und einem separaten Profil wiederholt. Der in der Test-App ausgeführte Build 102 hatte dasselbe App-Binary wie die installierte Fassung. F6 zeigte den Namenskonflikt. Nach «Ersetzen» zeigte die Vorbereitung die übertragenen Bytes. In der Auftragskarte führten «Pause» und «Fortsetzen» zum Zustandswechsel derselben Auftrags-ID. Die Karte blieb während der Schlussprüfung bei 99 % und zeigte anschliessend «Abgeschlossen · 100 %». Die Karte mass rund 423 aktive Sekunden. Ein separater Anbieterabruf bestätigte die Dropbox-Bytes in Google Drive und den fehlenden öffentlichen Quellnamen.

«Rückgängig» im erfolgreichen Historieneintrag stellte beide Dateizeilen wieder her. Die App zeigte «Verschieben · Rückgängig» und meldete eine rückgängig gemachte Aktion. Der unabhängige Anbieterabruf bestätigte beide ursprünglichen IDs, Längen und SHA-256-Prüfsummen. Die Verschiebungsjournale waren aufgeräumt. Dieser Durchgang verwendete eine manuelle Pause. Die echte Anbieter-Unterbrechung mit anschliessendem Rückgängig ist für Build 101 oben belegt. Der Mac blieb in derselben Boot-Sitzung.

Acht zusätzliche Suiten endeten erfolgreich mit 140 PASS-Zeilen. Darunter waren sechs echte Prozessabbrüche bei lokalen Papierkorbvorgängen, die Wiederaufnahme eines unterbrochenen lokalen Kopiervorgangs sowie die punktgenaue Inhaltsprüfung von 12.000 kopierten Dateien. Die 140 Prüfschritte sind ergänzende Nachweise zum 158-Fälle-Protokoll. Dessen Stand bleibt bei 97 vollständig, 54 teilweise und 7 umgebungsabhängig geprüften Fällen. Der D2-Start blieb bei 6,67 GB freiem Speicher und 18,79 GB Bedarf in der Vorprüfung. Der separate zweistündige Dauerlauf mit simulierten Verbindungsausfällen war weiterhin aktiv.

Nachweise sind `native-cross-b102-phase-r1865.jsonl`, `native-cross-b102-moved-r1865.json`, `native-cross-b102-restored-r1865.json`, `acceptance-supplemental-r1865.json` und `d2-capacity-r1865.json`.
