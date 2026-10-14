# Windows-Prüfstand – 14. Oktober 2026

Geprüft auf Windows 11 Pro 25H2 x64, Python 3.12.14, Qt/PySide6 6.11.2,
OpenCommander 0.3.25rc10 und rclone 1.75.2. Ohne Administratorrechte und ohne
aktivierten Windows-Symlink-Modus.

## Automatisiert geprüft

- Aktueller vollständiger Windows-Lauf: **403 bestanden, 47 übersprungen**, keine Fehler.
  Ergebnis: `build/pytest.xml`; Protokoll: `build/google-demo-fixed-build.log`.
  Alle 23 Linux-Testmodule sind jetzt in der Windows-Suite vertreten; ihre
  plattformgebundenen Fälle werden begründet übersprungen, nicht als bestanden gezählt.
  Import-Inventar: `build/parity-test-inventory.json`, keine fehlenden Module.
- Vollständiger Linux-Lauf unter Ubuntu 24.04: **400 bestanden**, keine Ausnahmen;
  Linux-Paket erfolgreich gebaut.
  Aktueller Lauf für Commit `2e801e1`:
  [CI-Lauf 38592350691](https://github.com/Niclas85/OpenCommander/actions/runs/38592350691).
- Nach der Cloud-Snapshot-Korrektur: **405 Linux-Tests bestanden**, Paket-Smoke
  erfolgreich, Commit `5b48d01` in
  [CI-Lauf 38632485879](https://github.com/Niclas85/OpenCommander/actions/runs/38632485879).
  Der Windows-CI-Job dieses Laufs war beim Dokumentationsabschluss noch aktiv;
  der vollständige lokale Windows-Build mit 403 Tests ist bereits geprüft.
- Abschließender Windows-CI-Lauf: **406 bestanden, 39 übersprungen**;
  GUI, Helfer, Quellcode-/Paket-Smoke-Test und ZIP-Bau erfolgreich.
  Der CI-Host kann zusätzliche Linktests ausführen, für die dem lokalen Konto
  Windows-Rechte fehlen. Beide Desktop-Jobs sind grün:
  [CI-Lauf 38592350691](https://github.com/Niclas85/OpenCommander/actions/runs/38592350691),
  Commit `2e801e1`. Der unabhängige Android-Job ist fehlgeschlagen;
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
  `build/google-demo-fixed-build.log`.
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
- Herausgeber-/Langpfad-Build und anschließend Cloud-Rückgängig-Korrektur installiert. Die installierte EXE
  entspricht bytegenau dem frisch geprüften Paket:
  SHA-256 `f2348e5b3ad226ad90f6515b12d9bc279ed671eceb28dd62a89a0becd9694ae5`.
  Die vorherige Installation bleibt als Sicherung erhalten.
- Bei der OAuth-Demo erkannter Fehler: WinFsp/rclone vergibt nach Verzeichnis-
  aktualisierung neue virtuelle Inode-Werte für unveränderte Drive-Dateien.
  Neue Provider-Snapshots verwenden deshalb ein versioniertes Format ohne diese
  instabile Kennung. Namen, Mountkennung, Dateityp, Zeitstempel und vollständige
  Inhaltsprüfsummen bleiben geprüft; Änderungen während des Lesens stoppen die
  Überprüfung. Alte Historieneinträge werden nicht umgedeutet. Fünf Regressionen
  prüfen Cache-Aktualisierung, persistentes Rückgängig, echte Inhalts-/Metadaten-
  Änderung, fehlende Einbindung und die unveränderte Prüfung alter Einträge.
  Nach Neuinstallation in der tatsächlichen App erneut bestanden: Drive-Vorschau,
  70-Byte-Upload, Umbenennen, Verzeichnis aktualisieren, erfolgreiches Rückgängig;
  82-Byte-Download mit exaktem Bytevergleich sowie Umbenennen und Rücknahme einer
  vor der Anmeldung angelegten Drive-Testdatei. Ein Download ins eigene
  Wiederherstellungsprofil wurde korrekt abgewiesen; das endgültige Testziel
  liegt getrennt davon. Eigene synthetische Dateien, kein Zugriffstest mit
  persönlichen Dateiinhalten. Google-Demovideo lokal fertig, Upload noch offen.
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
- Google: Die früheren Fehler des gemeinsamen rclone-Clients wurden durch die
  eigene Herausgeber-Identität im vorhandenen OpenCommander-Projekt behoben.
  Ein zusätzlicher Schlüssel wurde mit ausdrücklicher Bestätigung erzeugt;
  Browseranmeldung und 256-KiB-Datei-Roundtrip im privaten Abnahmeprofil bestanden.
  Die bestehende Google-Verbindung wurde auf den neuen Client umgestellt; andere
  Provider-Konfigurationen und alle vier gespeicherten Profile bleiben erhalten.
  Der erste Test im langen MSIX-Profilpfad deckte einen Windows-MAX_PATH-Fehler
  beim Umbenennen in die Rückgängig-Ablage auf. Windows-Dateiumbenennung und
  temporäre Transfer-/Archiv-/Wiederherstellungsablagen verwenden nun erweiterte
  Pfade. Ein realer Regressionstest prüft Rückgängig über 260 Zeichen und
  überschreibungsfreie Umbenennung. Die globale Windows-Richtlinie bleibt unverändert.
  Die beiden eigenen Diagnose-Dateien wurden anhand von Name, Größe und exaktem
  Testinhalt geprüft und anschließend samt ihren Testordnern entfernt.
  Google-Freigabelink, anonymer HTTP-Download (2624 Byte), Aufheben und Bereinigung
  über dieselbe Herausgeberanbindung bestanden.
  Nach Installation des endgültigen Pakets im vorhandenen Benutzerprofil erneut
  bestanden: Auflisten (718 Einträge), WinFsp-Mount, 256-KiB-Upload und bytegenaues
  Lesen, eingefrorener Helfer, Eigenschaften, Unicode-Umbenennung samt Rücknahme,
  persistentes Rückgängig und Bereinigung des eigenen Testordners. Der lange
  MSIX-Pfad funktioniert jetzt auch mit der Rückgängig-Ablage über 260 Zeichen.
  Freigabelink und bytegenauer anonymer Download ebenfalls erneut bestanden;
  alle eigenen Freigabetest-Dateien und -Ordner wurden über dieselbe Anbindung entfernt.
  Installierte Herausgeber-Identität und tatsächlicher EXE-Helfer bestehen die
  abschließende Paketprüfung; persönliche Tokens sind nicht im App-Paket.
  Nach erneutem GUI-Start bleiben alle vier Cloud-Orte sichtbar. „Google Drive
  online“ öffnet die Dateiansicht ohne erneute Anmeldung, lädt 711 sichtbare
  Einträge und erreicht den Zustand „Bereit“ (versteckte Einträge werden gefiltert).
  Veröffentlichung mit konkreter Benutzerbestätigung: Projekt External/In
  Produktion. Homepage und Datenschutzerklärung unter `opencommander.top` anonym
  per HTTPS mit HTTP 200 geprüft. Dynadot-DNS gespeichert, Google-Domaininhaberschaft
  bestätigt; Branding automatisch geprüft und veröffentlicht. Der vollständige
  Drive-Scope bleibt ungeprüft: Begründung und lokales Demovideo fertig;
  YouTube-Upload/Link noch offen, Antrag noch nicht abgesendet. Details: [PUBLISHER.md](PUBLISHER.md).
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
Herausgeber-Abnahme: `build/publisher-google-final-build.log`,
`build/publisher-installed-package.log`, `build/google-publisher-installed-final.log`
und `build/google-publisher-installed-share.log`.
Der Live-Bericht enthält auch frühere fehlgeschlagene Versuche; maßgeblich ist
das jüngste Ergebnis je Testfall. Kontoanmeldungen gelten erst nach gespeichertem
Profil und erfolgreichem Dateizugriff als vollständig geprüft.

## Noch zu prüfen

| Bereich | Offener Nachweis |
| --- | --- |
| Cloud | Öffentliche Google-Marken-/Scope-Verifizierung, Hosting und HTTPS unter opencommander.top; weitere anbieterspezifische Kontenrichtlinien |
| Server | Externe Server mit abweichenden Richtlinien; persönlicher Windows-SSH-Agent. Eigene laufende FTP/FTPS/SFTP/WebDAV-Testserver und nativer WebClient sind geprüft |
| USB | Sicheres Auswerfen wurde auf Benutzerwunsch nicht getestet |
| Medien | Weitere Codec-/Hardwarekombinationen; PNG, WAV und H.264 sind praktisch geprüft |
| Betriebssysteme | Windows 10, ARM64 und weitere Windows-11-Versionen |
| Geräte | Kein Windows-WPD/MTP-Adapter für reine Kamera-/Telefon-Geräte; Linux kann solche Geräte über GVFS bereitstellen |

Der vollständige Funktionsvergleich steht in [PARITY.md](PARITY.md).
Die gemeinsame Implementierung übernimmt den Linux-Funktionskern. Vollständige
Live-Parität mit allen Providern, Geräten und Betriebssystemdiensten ist damit
noch nicht nachgewiesen.
