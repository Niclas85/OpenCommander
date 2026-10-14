# Windows-Prüfstand – 14. Oktober 2026

Geprüft auf Windows 11 Pro 25H2 x64, Python 3.12.14, Qt/PySide6 6.11.2,
OpenCommander 0.3.25rc10 und rclone 1.75.2. Ohne Administratorrechte und ohne
aktivierten Windows-Symlink-Modus.

## Automatisiert geprüft

- Aktueller vollständiger Windows-Lauf: **394 bestanden, 47 übersprungen**, keine Fehler.
  Ergebnis: `build/pytest.xml`; Protokoll: `build/parity-installed-build.log`.
  Alle 23 Linux-Testmodule sind jetzt in der Windows-Suite vertreten; ihre
  plattformgebundenen Fälle werden begründet übersprungen, nicht als bestanden gezählt.
  Import-Inventar: `build/parity-test-inventory.json`, keine fehlenden Module.
- Vollständiger Linux-Lauf unter Ubuntu 24.04: **397 bestanden**, keine Ausnahmen;
  Linux-Paket erfolgreich gebaut.
- Abschließender Windows-CI-Lauf: **402 bestanden, 39 übersprungen**;
  GUI, Helfer, Quellcode-/Paket-Smoke-Test und ZIP-Bau erfolgreich.
  Der CI-Host kann zusätzliche Linktests ausführen, für die dem lokalen Konto
  Windows-Rechte fehlen. Beide Desktop-Jobs sind grün:
  [CI-Lauf 38522129270](https://github.com/Niclas85/OpenCommander/actions/runs/38522129270),
  Commit `5679aaf`. Der unabhängige Android-Job scheitert bereits beim SDK-Setup;
  das betrifft weder den Windows- noch den Linux-Desktop-Build.
- Nach zusätzlicher Absicherung von Windows-Junctions: **84 bestanden,
  16 übersprungen** im Datei-/Wiederaufnahme-/Windows-Sicherheitstestlauf.
  Dieser Lauf enthält einen neuen Test für einen manipulierten Zwischenordner.
  Ergebnis: `build/windows-safety.xml`; Protokoll: `build-safety.log`.
- Quellcode-Smoke-Test: Qt-Fenster, JPEG, isolierter Download, TAR/7z,
  Cloud-Kontextmenü und Kopie nach Pause/Neustart erfolgreich.
- Paket-Smoke-Test: tatsächliche `OpenCommander.exe`, mitgelieferter Helfer,
  Unicode-Pfade, bytegenaue Downloads und rclone-EXE erfolgreich.
  Ergebnis: `build/package-smoke.json`; Protokoll des abschließenden Builds:
  `build/parity-installed-build.log`.
- Die Windows-Tests umfassen Explorer-Zwischenablageformat, überschreibungsfreie
  Umbenennung, gefährliche Archivnamen/NTFS-Datenströme, Binärdateien,
  Dateieigenschaften, verborgene Dateien, private NTFS-ACLs,
  Windows-Anmeldeinformationen und verschlüsselte OpenSSH-Schlüssel.
- Native Qt-Darstellung zusätzlich über `QT_QPA_PLATFORM=windows` geprüft.
  `offscreen` rendert hier mangels eigener Schriftbibliothek Platzhalter;
  das native Windows-Backend zeigt die Schrift korrekt.

Übersprungen werden ausdrücklich Linux-Dienste/FIFO-/POSIX-Rechte-Prüfungen,
GVFS, `/proc`, Secret Service und Symlink-Erstellung ohne erforderliches Windows-Recht.
Linux-Tests mit exakten Betriebssystem-Fehlertexten werden nicht
als Windows-Integrationstest ausgegeben. Gemeinsame Qt-Tests verwenden dieselben
Testfunktionen wie unter Linux; Warteschritte wurden auf tatsächlich geladene
Einträge ausgerichtet, statt lediglich auf eine unveränderte Zeilenzahl.

## Praktisch auf diesem Computer geprüft

- Installation für den aktuellen Benutzer mit Startmenü-Verknüpfung und
  Explorer-Kontextmenü; WinFsp 2.1.25156 installiert.
- Letzte Anmeldekorrektur installiert und SHA-256 der installierten EXE mit dem
  geprüften Build abgeglichen. Abgelaufene Anmeldungen und Fehler ohne weitere
  Provider-Frage beenden den Dialog sauber; eine neue Anmeldung entfernt alte
  Antworten und Fehlermeldungen. Zwei zusätzliche Qt-Regressionstests bestanden.
- Abschließende Paritäts-/WebDAV-Korrektur installiert. Die installierte EXE
  entspricht bytegenau dem frisch geprüften Paket:
  SHA-256 `71b58b81e70515f981f85d5200fbe7fd1bddf5ac220d9ff79691befe9044a6b8`.
  Die vorherige Installation bleibt als Sicherung erhalten.
- Explorer-Zwischenablage praktisch in beiden Richtungen geprüft: eine Datei
  mit Umlauten und japanischen Zeichen kopiert und alle drei Exemplare per
  SHA-256 bytegenau verglichen (47 Byte).
- Tatsächliches Explorer-Kontextmenü unter „Weitere Optionen anzeigen“ aufgerufen:
  der gewählte Prüfungsordner öffnet sich im aktiven Bereich des bestehenden
  OpenCommander-Fensters; gespeicherte Cloud-Einträge bleiben erhalten.
- Im nativen Dialog OpenCommander vorübergehend als Standard-Dateimanager gewählt
  und einen Ordner über die Windows-Shell geöffnet. Der anschließende Registry-
  Rundlauf außerhalb der Entwicklungsumgebung bestätigt: vorherige Zuordnung
  wiederhergestellt, Kontextmenü und Startmenü-Verknüpfung durch das mitgelieferte
  Deinstallationsskript entfernt und erneut eingerichtet. Auch ein ursprünglich
  fehlender Standardwert wurde exakt wiederhergestellt. OpenCommander bleibt
  nach dem Test nicht als Standard-Dateimanager ausgewählt.
- Die Entwicklungsumgebung leitet Teile von Benutzerprofil und Registry um.
  Deshalb wurde die Shell-Integration zusätzlich außerhalb dieser Umgebung
  installiert und geprüft. Startmenü und Kontextmenü verwenden hier ausdrücklich
  das vorhandene Profil über `--state-dir`; das Installationsskript unterstützt
  dafür optional `-StateDirectory`. Der einmalige Prüfauftrag wurde entfernt.
- Lokale Dateiaktionen einschließlich Konfliktbehandlung, Verschieben,
  Umbenennen, Ordnern, Wiederherstellungskopien und Rückgängig nach Neustart.
- 16-MiB-Kopie mit Pause/Wiederaufnahme; Rückgängig verweigert das Entfernen
  einer zwischenzeitlich geänderten Zieldatei.
- Tatsächliches Verschieben zwischen NTFS auf C: und exFAT auf SanDisk D:,
  danach Rückgängig und bytegenauer Vergleich. D: bleibt verbunden;
  es wurde kein USB-Auswurf ausgelöst.
- SMB-NAS `\\192.168.0.22\Test`: Unicode-Dateinamen, 256-KiB-Binärdatei,
  Kopieren/Verschieben/Entfernen mit Wiederherstellung und Rückgängig,
  Verzeichnisabfrage durch den mitgelieferten Helfer und Dateieigenschaften.
  Schreibtests verwenden ausschließlich den eigenen Prüfungsordner.
- ZIP erstellen/lesen sowie TAR, GZIP, BZIP2, XZ, Zstandard, 7z und RAR5 lesen
  und entpacken; Suche, Inhaltsvergleich und Mehrfachumbenennung mit Rückgängig.
- Tatsächlicher rclone-/WinFsp-Verzeichnismount mit Auflisten, Upload,
  Rückgängig und authentifiziertem ordentlichem Trennen. Dabei entdeckte
  Windows-Fehler 1005 bei Pfad- und Anmeldeinformationsabfragen korrigiert.
- OneDrive und Dropbox: echte Browseranmeldung durch den Benutzer, gespeichertes
  Profil, Verzeichnisabfrage, WinFsp-Mount, 256-KiB-Upload, bytegenaues Lesen,
  mitgelieferter Helfer und Rückgängig mit neu geöffnetem FileEngine bestanden.
- FTP, SFTP und WebDAV gegen eigene laufende Loopback-Testserver: 256-KiB-Upload,
  Lesen, Helfer, persistente Rücknahme, Verbindungsabbruch und ordentliches Trennen
  bestanden. SFTP weist einen geänderten Hostschlüssel ab. Dieser WebDAV-Lauf
  prüft rclone/WinFsp; der native Windows-Test ist nachfolgend separat aufgeführt.
- Nativer Windows-WebClient nach ausdrücklicher UAC-Bestätigung gestartet,
  Starttyp bleibt „Manuell“. Anonymer, ausschließlich an `127.0.0.1` gebundener
  WebDAV-Server: UNC-Verzeichnisabfrage, Ordner, 256-KiB-Upload, bytegenaues Lesen,
  mitgelieferter Helfer, Eigenschaften, persistente Rücknahme und Trennen bestanden.
  Ein echter Kopierfehler bei der Zeitstempelübernahme wurde durch die native
  Windows-Datei-API korrigiert. Der abschließende Lauf benutzt die korrigierte
  installierte Ausgabe: `build/native-webdav-installed-final.log`.
- Private SSH-Schlüssel werden unter Windows anhand ihrer tatsächlichen NTFS-
  Leserechte geprüft. Ein eigener Test mit einer ausschließlich synthetischen
  Schlüsseldatei bestätigt die Ablehnung öffentlich lesbarer Schlüssel und
  eines Schlüssels, auf den eine fremde Anmeldesitzung Leserechte erhält.
- Lokale Verknüpfungen auf Cloud-Verzeichnisse werden vor der Provider-Erkennung
  normalisiert. Windows-Regressionstests prüfen beide nativen Pfadpräfixe ohne
  vorausgesetztes Symlink-Recht und verbieten das Abfragen von Provider-Links.
- FTPS erneut mit der aktualisierten Installation gegen Apache FtpServer 1.2.1
  bestanden: 256-KiB-Upload, bytegenaues Lesen, Helfer, Rückgängig nach Neustart,
  Ablehnung eines nicht vertrauten Zertifikats, Verbindungsabbruch in 0,16 Sekunden
  und ordentliches Trennen. Der eigene Test-CA wurde nur für diesen Test verwendet;
  die Zertifikatsprüfung blieb aktiv. Frühere TLS-Übertragungsfehler betrafen den
  Python-Testserver; der unabhängige Apache-Server bestätigt den FTPS-Datenpfad.
- Native Bild-/WAV-/H.264-Vorschau sowie Vor/Zurück, Videowiedergabe, Zeitsuche
  und Neustart der Wiedergabe geprüft. F5 kopiert die Unicode-Prüfdatei vollständig.
- Google-OAuth mit echtem rclone bis zum Browserübergang geprüft, ohne
  Benutzeranmeldung: Browseradresse während der laufenden Anmeldung empfangen,
  lokaler HTTP-Endpunkt und Weiterleitung zu Google bestätigt. Windows liefert
  bei `communicate(timeout)` keine Zwischenstände von stderr; der korrigierte
  Ablauf liest die Ausgaben fortlaufend. Ein eigener Windows-Regressionstest
  prüft den Link vor Prozessende. Weitere sieben gezielte gemeinsame Tests
  für Passwortübergabe, Browseradressen und OAuth sind erfolgreich.
- Die tatsächliche Google-Browseranmeldung ist gespeichert. Mount und Auflisten
  bestanden einmal mit 718 Einträgen; Upload und Freigabelink-Erstellung gelangen
  ebenfalls zeitweise. Der reine 2624-Byte-Testinhalt war im anonymen Browser
  ohne Anmeldung sichtbar. Andere Aufrufe und der vollständige 256-KiB-Roundtrip
  scheitern weiterhin mit HTTP 403 und Meldungen zu gemeinsamem OAuth-Client,
  Einstellung und Quota. Stabiler Google-Dateizugriff bleibt offen.
  Entfernen über die App-Anbindung war ebenfalls durch die Provider-Quota blockiert.
  Die eigene synthetische Freigabetestdatei wurde deshalb über den bereits
  verbundenen Google-Drive-Connector anhand ihrer exakten ID und ihres Testinhalts
  entfernt. Der eigene Ordner wurde erst nach bestätigtem Leerstand entfernt;
  anschließende Metadatenabfragen bestätigen „nicht gefunden“ für beide IDs.
  Keine öffentliche Testfreigabe bleibt zurück. Dies ist ausdrücklich kein
  bestandener Google-Datei-Roundtrip der OpenCommander-App.
  Eine eigene zugelassene OAuth-Anwendung des **Herausgebers** kann im vorhandenen
  Build eingebettet werden; Benutzer melden sich dann weiter nur im Browser an.
- Dropbox-Browserübergang und frischer lokaler OAuth-Endpunkt bestätigt.
  Nach dem ursprünglichen `ERR_CONNECTION_REFUSED` wurde eine neue Anmeldung
  mit laufendem lokalem Server durchgeführt und der vollständige Dateizugriff
  erfolgreich geprüft.
- iCloud: Benutzer hat Apple-ID und Zwei-Faktor-Anmeldung selbst abgeschlossen.
  Gespeichertes Profil, Auflisten, WinFsp-Mount, 256-KiB-Upload, bytegenaues Lesen,
  mitgelieferter Helfer und Rückgängig mit neuer FileEngine bestanden; nach der
  abschließenden Installation erneut vollständig bestanden.
- Dropbox-Freigabe: eigene 2624-Byte-Datei, Linkerstellung und bytegenauer anonymer
  HTTP-Download bestanden; Datei und Ordner entfernt.
- OneDrive-Freigabe: eigener Testinhalt im nicht angemeldeten Browser sichtbar;
  Link-Entfernen meldet Erfolg, Testdatei und Ordner entfernt. Der ältere anonyme
  API-Download-Endpunkt verweigerte Zugriff und ist kein Gegenbeweis zur sichtbaren
  erfolgreichen Webfreigabe. iCloud-Linkerstellung ist wie unter Linux nicht
  implementiert; Freigaben können im Provider-Browser verwaltet werden.

Ergebnisse: `build/live-results.json`, `build/cloud-live-results.json`,
`build/protocol-live-results.json`, `build/ftps-installed-final.log`,
`build/browser-probe.json`, `build/browser-probe-dropbox.json`,
`build/explorer-clipboard-results.json`, `build/explorer-context-results.json`
und `build/explorer-shell-results.json`.
Zusätzliche Ergebnisse: `build/native-webdav-results.json`,
`build/icloud-installed-final.log`, `build/google-installed-final.log`,
`build/share-live-results.json` (erster Dropbox-Erfolg),
`build/share-live-onedrive.json` und `build/share-live-drive.json`.
Der Live-Bericht enthält auch frühere fehlgeschlagene Versuche; maßgeblich ist
das jüngste Ergebnis je Testfall. Kontoanmeldungen gelten erst nach gespeichertem
Profil und erfolgreichem Dateizugriff als vollständig geprüft.

## Noch zu prüfen

| Bereich | Offener Nachweis |
| --- | --- |
| Cloud | Stabiler Google-Dateizugriff mit zugelassener Herausgeber-OAuth-Anwendung; weitere anbieterspezifische Kontenrichtlinien |
| Server | Externe Server mit abweichenden Richtlinien; persönlicher Windows-SSH-Agent. Eigene laufende FTP/FTPS/SFTP/WebDAV-Testserver und nativer WebClient sind geprüft |
| USB | Sicheres Auswerfen wurde auf Benutzerwunsch nicht getestet |
| Medien | Weitere Codec-/Hardwarekombinationen; PNG, WAV und H.264 sind praktisch geprüft |
| Betriebssysteme | Windows 10, ARM64 und weitere Windows-11-Versionen |
| Geräte | Kein Windows-WPD/MTP-Adapter für reine Kamera-/Telefon-Geräte; Linux kann solche Geräte über GVFS bereitstellen |

Der vollständige Funktionsvergleich steht in [PARITY.md](PARITY.md).
Die gemeinsame Implementierung übernimmt den Linux-Funktionskern. Vollständige
Live-Parität mit allen Providern, Geräten und Betriebssystemdiensten ist damit
noch nicht nachgewiesen.
