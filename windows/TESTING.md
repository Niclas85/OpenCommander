# Windows-Prüfstand – 15. Oktober 2026

Geprüft auf Windows 11 Pro 25H2 x64, Python 3.12.14, Qt/PySide6 6.11.2,
OpenCommander 0.3.25rc10 und rclone 1.75.2. Ohne Administratorrechte und ohne
aktivierten Windows-Symlink-Modus.

## Automatisiert geprüft

- Neue WPD/MTP-Anbindung: native 64-Bit-COM-Aufrufe einschließlich Unicode und
  großen Dateigrößen; sichere Namen, eindeutige Objektzuordnung, Pfad-/Root-Schutz,
  Kennwort-/Origin-Prüfung, überschreibungsfreie Uploads und Gerätefehler.
  Echtes rclone/WebDAV und WinFsp mit synthetischem Geräteadapter: Datei-Roundtrip,
  Umbenennen, wiederherstellbares Entfernen, Pause und Fortsetzen einer 2-MiB-Datei,
  Rückgängig nach erneutem Laden sowie nach Mount-Neustart. Der vollständig
  gegen die Quelle geprüfte eigene Teil-Upload wird exklusiv neu angelegt;
  fremde/volle Objekte werden nicht per PUT überschrieben. Geänderte Inhalte
  stoppen Rückgängig weiterhin. Ein schreibgeschützter Geräteadapter verweigert
  Kopieren und Verschieben mit Fehler; die lokale Quelle bleibt bytegleich.
  Ergebnisse: `build/portable-devices-tests.xml`, `build/portable-native-tests.xml`.
  Der synthetische Adapter ergänzt die unten beschriebene echte Pixel-Hardwareabnahme.

- Aktueller vollständiger Windows-Lauf nach den Pixel-/USB-Korrekturen:
  **448 bestanden, 47 übersprungen**, keine Fehler (157,35 s).
  Ergebnis: `build/pytest-usb-final.xml`;
  Protokoll: `build/usb-ui-final-build.log`.
  Neue Regressionen prüfen Windows-Zustandswechsel beim sicheren Auswerfen,
  den Schutz bei dauerhaft verweigertem Zugriff, das Ausblenden leerer USB-
  Laufwerksbuchstaben und die Unterscheidung von WPD-MTP und USB-Massenspeicher.
  Gezielte Geräte-/Datei-/Wiederaufnahmeprüfung: **94 bestanden, 16 übersprungen**;
  fünf zusätzliche Pause/Fortsetzen-Wiederholungen am echten Pixel bestanden.
  Nach der Trennung der GUI-/Helfer-Abhängigkeiten zusätzlich **77 native Tests**
  bestanden; nach der Geräte-Wiederaufnahme und vereinheitlichten Provider-
  Nachweisprüfung **89 bestanden, 16 übersprungen** im gezielten Lauf.
  Alle 23 Linux-Testmodule sind jetzt in der Windows-Suite vertreten; ihre
  plattformgebundenen Fälle werden begründet übersprungen, nicht als bestanden gezählt.
  Import-Inventar: `build/parity-test-inventory.json`, keine fehlenden Module.
- Vollständiger Linux-Lauf unter Ubuntu 24.04: **400 bestanden**, keine Ausnahmen;
  Linux-Paket erfolgreich gebaut.
  Früherer Lauf für Commit `2e801e1`:
  [CI-Lauf 38592350691](https://github.com/Niclas85/OpenCommander/actions/runs/38592350691).
- Nach der Cloud-Snapshot-Korrektur: **405 Linux-Tests bestanden**, Paket-Smoke
  erfolgreich, Commit `5b48d01` in
  [CI-Lauf 38632485879](https://github.com/Niclas85/OpenCommander/actions/runs/38632485879).
  Im Windows-Job gab es zwei Zeitüberschreitungen beim Abschluss wiederaufgenommener
  GUI-Transfers (409 bestanden, 39 übersprungen). Der folgende Lauf derselben
  Anwendungskorrektur mit ausschließlich Dokumentationsänderungen besteht diese
  Tests unverändert; es wurde kein Timeout erhöht oder Test deaktiviert.
- Abschließender Windows-CI-Lauf: **411 bestanden, 39 übersprungen**;
  GUI, Helfer, Quellcode-/Paket-Smoke-Test und ZIP-Bau erfolgreich.
  Der CI-Host kann zusätzliche Linktests ausführen, für die dem lokalen Konto
  Windows-Rechte fehlen. Beide Desktop-Jobs sind grün:
  [CI-Lauf 38633342659](https://github.com/Niclas85/OpenCommander/actions/runs/38633342659),
  Commit `31167f2`, Linux **405 bestanden**. Der unabhängige Android-Job ist
  beim Einrichten des Android-SDK fehlgeschlagen;
  das betrifft weder den Windows- noch den Linux-Desktop-Build.
- WPD-/Medien-Stand `3168d00`: Ubuntu-CI **407 bestanden**, Linux-Paket und
  Desktop-Smoke erfolgreich. Windows-CI **442 bestanden, 40 übersprungen**;
  Quell-/Paket-Smoke, gefrorener WPD-Helfer und ZIP erfolgreich. Apple-Job
  ebenfalls erfolgreich:
  [CI-Lauf 38661156491](https://github.com/Niclas85/OpenCommander/actions/runs/38661156491).
  Der CI-Host führt zusätzliche privilegierte Linktests aus; der reale
  WinFsp-Geräteadapterlauf wird dort mangels installiertem WinFsp übersprungen
  und ist lokal bestanden. Der lokale Publisher-Build und die Installation
  sind zusätzlich bestätigt.
  Android scheitert weiterhin unabhängig beim Einrichten des SDK.
- Nach zusätzlicher Absicherung von Windows-Junctions: **84 bestanden,
  16 übersprungen** im Datei-/Wiederaufnahme-/Windows-Sicherheitstestlauf.
  Dieser Lauf enthält einen neuen Test für einen manipulierten Zwischenordner.
  Ergebnis: `build/windows-safety.xml`; Protokoll: `build-safety.log`.
- Quellcode-Smoke-Test: Qt-Fenster, JPEG, isolierter Download, TAR/7z,
  Cloud-Kontextmenü und Kopie nach Pause/Neustart erfolgreich.
- Paket-Smoke-Test: tatsächliche `OpenCommander.exe`, mitgelieferter Helfer,
  Unicode-Pfade, bytegenaue Downloads und rclone-EXE erfolgreich.
  Ergebnis: `build/package-smoke.json`; Protokoll des abschließenden Builds:
  `build/usb-ui-final-build.log`.
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

- **Pixel 8 Pro, echter WPD/MTP-Speicher:** eigener, eindeutig markierter
  Testordner; keine persönlichen Dateien geöffnet oder verändert. Unicode-Datei
  mit 256 KiB hochgeladen, vollständig zurückgelesen und SHA-256 verglichen;
  Download, Umbenennen, wiederherstellbares Entfernen und persistentes Rückgängig
  geprüft. 2-MiB-Auftrag nach 1 MiB pausiert und mit neuem FileEngine fortgesetzt;
  Verschieben bereinigt die lokale Quelle erst nach geprüftem Upload und lässt
  sich rückgängig machen. Logisches Trennen/erneutes Einbinden erhält den
  Rückgängig-Nachweis. Verschachtelte Ordnerkopie, Suche, Inhaltsvergleich sowie
  direkt auf dem Handy erstelltes und entpacktes ZIP bestanden.
  Dabei drei reale Fehler korrigiert: Androids schreibgeschützter Ordneranzeigename
  wird über die vorhandene Dateinamen-Eigenschaft umbenannt; Zwischenstände werden
  vor der Prüfung des Lesehandles auf tatsächliche Gerätemetadaten aktualisiert;
  ZIP-Dateien verwenden eine fortlaufende Ausgabe ohne Rückwärtssprünge.
  Gerätezugriffsfehler und nachträglich geänderte Zwischenstände bleiben gesperrt.
  Alle elf Prüfpunkte mit dem installierten, eingefrorenen Gerätehelfer bestanden;
  dessen tatsächlicher Prozesspfad wurde vor dem Schreibtest geprüft.
  Geräteknopf, Speicheransicht, Testordner und UTF-8-Textvorschau zusätzlich per
  Computersteuerung in der installierten EXE geprüft. Die erzeugten Dateien und
  Testordner wurden nach Eigentumsprüfung vollständig entfernt. USB-Debugging
  blieb eingeschaltet, ein physischer USB-Auswurf wurde nicht ausgelöst.
  Wiederholbarer, ausdrücklich freizugebender Hardwaretest:
  `tests/mtp_live_validation.py --allow-device-writes` (Windows-venv-Python).
  Ergebnisse: `build/mtp-hardware-results.json`,
  `build/mtp-hardware-installed-final.log`, `build/mtp-installed-ui-results.json`,
  `build/mtp-installed-text-preview.png` und `build/mtp-partial-corrected.log`.
  Erste fehlgeschlagene Versuche bleiben in den getrennten Diagnoseprotokollen erhalten.

- Installation für den aktuellen Benutzer mit Startmenü-Verknüpfung und
  Explorer-Kontextmenü; WinFsp 2.1.25156 installiert.
- Letzte Anmeldekorrektur installiert und SHA-256 der installierten EXE mit dem
  geprüften Build abgeglichen. Abgelaufene Anmeldungen und Fehler ohne weitere
  Provider-Frage beenden den Dialog sauber; eine neue Anmeldung entfernt alte
  Antworten und Fehlermeldungen. Zwei zusätzliche Qt-Regressionstests bestanden.
- Vorheriger Herausgeber-/Langpfad-Build mit Cloud-Rückgängig-Korrektur:
  SHA-256 der damaligen EXE
  SHA-256 `f2348e5b3ad226ad90f6515b12d9bc279ed671eceb28dd62a89a0becd9694ae5`.
  Die vorherige Installation bleibt als Sicherung erhalten.
- Pixel-/WPD-Korrekturen installiert, vorherige Programmversion gesichert.
  Die installierte EXE und das geprüfte Paket sind bytegleich:
  SHA-256 `9ca9e4376c973d87add4c51b595e960cfef3307eb91f14bb052defecb3d95aae`.
  Die bestehende Verbindungsdatei ist vor/nach dem Dateiaustausch bytegleich;
  ursprüngliche Startparameter wiederverwendet, alle vier Cloud-Orte sichtbar,
  App erreicht „Bereit“. Ergebnis: `build/portable-installed-results.json`.
  Gefrorener Gerätehelfer und tatsächliche WPD-Fehlermeldung bei einem nicht
  existierenden Gerät im Paket geprüft, ohne GUI-Abhängigkeit oder neuen
  Laufzeitdownload. Der kompilierte Code enthält die aktuellen Geräte-
  Wiederaufnahme- und Provider-Verschiebekorrekturen.
- Zusätzlicher Schutz für fortsetzbare Provider-Verschiebungen: Die
  Quellbereinigung verwendet dasselbe gespeicherte Nachweisformat wie Rückgängig.
  Unveränderte Version-2-Ziele erlauben den Abschluss; bei nachträglicher
  Inhaltsänderung bleibt die vollständige Quellsicherung erhalten. Zwei neue
  gemeinsame Regressionen und der echte WinFsp-Geräteadapterlauf bestätigen dies.
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
  persönlichen Dateiinhalten. Google-Demovideo (1:58) mit ausdrücklicher Freigabe
  einschließlich YouTube-Zustimmung als „Nicht gelistet“ veröffentlicht:
  https://youtu.be/LQkSLbaxRpg . Der vollständige Prüfantrag ist eingereicht.
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
  danach Rückgängig und bytegenauer Vergleich bestanden.
- Erneute SanDisk-Abnahme mit ausdrücklicher Auswurf-Freigabe: 1-MiB-Unicode-
  Roundtrip samt SHA-256, Auflistung durch den installierten EXE-Helfer sowie
  Verschieben mit Quellbereinigung und persistentem Rückgängig bestanden.
  Ausschließlich der eigene markierte Testordner wurde anschließend entfernt.
  Danach in der installierten App „Verbindungen → SanDisk (D:) → Trennen /
  Auswerfen“ bestätigt. Windows meldet `ERROR_NOT_READY` (21) und „No Media“;
  die Verbindung verschwindet ohne Fehlermeldung. Der USB-Controller und sein
  leerer Laufwerksbuchstabe dürfen dabei vorhanden bleiben.
  Die frühere falsche Fehlermeldung bei vorübergehendem „Zugriff verweigert“
  wurde korrigiert: Erfolg erfordert einen nativen Entfernt-/Kein-Medium-Status;
  dauerhafte Zugriffs-/Freigabefehler gelten weiterhin als Fehler. Kein erzwungenes
  Aushängen, Offline-Schalten oder Entfernen eines Laufwerksbuchstabens.
  WPDs Dateisystemtreiber erzeugt keinen zusätzlichen MTP-Eintrag mehr. Die
  Ortsleiste nutzt verfügbare Laufwerke aus dem Hintergrundhelfer und zeigt
  nach dem Auswurf auch keinen leeren Ordnerknopf für D:.
  Opt-in-Skript: `tests/usb_live_validation.py --drive 'D:\' --expected-label SanDisk --allow-device-writes`;
  `--eject` führt nach erfolgreicher Prüfung und Bereinigung zusätzlich den
  Auswurf über den installierten Helfer aus. Der dokumentierte Live-Auswurf
  wurde separat über die tatsächliche Oberfläche ausgelöst.
  Ergebnisse: `build/usb-hardware-results.json`, `build/usb-installed-eject-results.json`,
  `build/usb-installed-ui-results.json` und `build/usb-installed-eject.png`.
  Die abschließend installierte EXE und das geprüfte Paket sind bytegleich:
  SHA-256 `e895f5a5496f792b42ec439083122c85a5b9510c777a6cbcb2417d8a279cb1f5`.
  Alle fünf gespeicherten Verbindungen sind erhalten; die Verbindungsdatei
  blieb bytegleich, alle vier Cloud-Orte sind sichtbar und die App erreicht „Bereit“.
  Weitere USB-Controller bleiben separat zu prüfen.
- SMB-NAS `\\192.168.0.22\Test`: Unicode-Dateinamen, 256-KiB-Binärdatei,
  Kopieren/Verschieben/Entfernen mit Wiederherstellung und Rückgängig,
  Verzeichnisabfrage durch den mitgelieferten Helfer und Dateieigenschaften.
  Schreibtests verwenden ausschließlich den eigenen Prüfungsordner.
- Erweiterte Abnahme desselben realen SMB-NAS mit der aktuellen Installation:
  **acht Prüfpunkte bestanden**. 1-MiB-Unicode-Datei hoch-/heruntergeladen und
  vollständig per SHA-256 verglichen; installierter Helfer prüft Auflistung und
  Eigenschaften. Beibehalten beider Konfliktdateien und Ersetzen mit exakter
  Rücknahme bestanden. Eine gleich große externe Inhaltsänderung blockiert
  Rückgängig; ein exklusiver SMB-Lesehandle verhindert das Entfernen, der
  Dateiinhalt bleibt erhalten. 4-MiB-Auftrag nach 1 MiB pausiert und mit neuem
  FileEngine fortgesetzt; auftragsbasiertes Verschieben zwischen C: und NAS mit
  Quellbereinigung und Rückgängig bestanden. Verschachtelte Ordner, Suche,
  Inhaltsvergleich und direkt auf dem NAS erstelltes/entpacktes ZIP bestanden.
  Der einmalig erzeugte, markierte Testordner wurde vollständig entfernt.
  Opt-in-Skript: `tests/nas_live_validation.py --share "\\192.168.0.22\Test" --allow-share-writes`.
  Ergebnisse: `build/nas-expanded-results.json`, `build/nas-expanded-validation.log`.
  Reine Verbindungsdiagnose: SSH/22 antwortet, HTTPS/443 bietet ein
  selbstsigniertes Zertifikat; kein authentifizierter SFTP-/WebDAV-Nachweis.
  Dafür fehlen Anmelde-/Endpunktangaben. Bei der erneuten Inventur waren kein
  WPD-Handy, keine externe Dateikamera und kein USB-Datenträger angeschlossen;
  die interne Webcam ist kein MTP-Dateispeicher. Kein Auswurf ausgelöst.
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
- Zusätzliche isolierte Medienmatrix mit tatsächlichen Qt-Decodern: WAV, MP3,
  AAC/M4A, FLAC, Vorbis/OGG, Opus, WMA, H.264, MPEG-4/AVI, VP9/WebM und HEVC.
  Alle elf bestehen Wiedergabe, Pause/Fortsetzen, Zeitsuche und Neustart;
  bei Videos ist ein tatsächlich dekodierter Frame nachgewiesen.
  Der native Windows-Backend scheiterte beim Fortsetzen nach der Zeitsuche.
  Der mitgelieferte FFmpeg-Backend besteht dieselben Abläufe und ist nun unter
  Windows standardmäßig mit Software-Dekodierung aktiviert. Keine zusätzlichen
  System-Codecs installiert. Ergebnis: `build/media-live-results.json`,
  Protokoll: `build/media-live-validation-ffmpeg.log`.
  Die installierte EXE zusätzlich per Computersteuerung geöffnet: VP9-WebM
  wird intern sichtbar dekodiert, erreicht 3000 ms und startet erneut mit
  sichtbarem Testbild. Nachweis: `build/installed-vp9-playback.png`.
- Pageant 0.85 aus der offiziellen PuTTY-Quelle, SHA-256 und gültige
  Herausgebersignatur geprüft. Anmeldung an eigenem Loopback-SFTP-Server allein
  über den Agenten: kein Passwort und kein privater Client-Schlüssel in rclone.
  WinFsp, 256-KiB-Upload, bytegenaues Lesen, persistentes Rückgängig,
  Hostschlüssel-Ablehnung und ordentliches Trennen bestanden. Agent und Server
  anschließend beendet, erzeugte private Testschlüssel entfernt. Persönliche
  Schlüssel und ein vorhandener Agent wurden nicht verwendet oder verändert.
  Ergebnis: `build/agent-live-results.json`; `build/agent-live-validation.log`.
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
  Drive-Scope ist noch nicht genehmigt: Begründung und Videolink gespeichert,
  vollständiger Antrag abgesendet. Die Konsole bestätigt den Eingang beim
  Trust-and-Safety-Team und zeigt „wird überprüft“. Details: [PUBLISHER.md](PUBLISHER.md).
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
| Cloud | Google-Drive-Scope-Genehmigung und gegebenenfalls CASA-Schritte nach Google-Rückmeldung; Antrag eingereicht. Branding, Hosting und HTTPS unter opencommander.top sind bestätigt; weitere anbieterspezifische Kontenrichtlinien |
| Server | Externe Server mit abweichenden Richtlinien und persönliche Agenten-/Hardware-Schlüsselkonfigurationen. Der bereitgestellte VPS war vor Anmeldung nicht erreichbar (SSH-Timeout, VNC-Verbindung verweigert). Nach ausdrücklich freigegebenem einmaligem Contabo-Neustart antworten SSH/22 und VNC; PowerShell-TCP-Test und SSH-Schlüsselaushandlung bestanden, Server bietet Passwort und Public Key an. Der strenge OpenSSH-Aufruf stoppt am nicht bestätigten Hostschlüssel. Keine Firewall-/Kennwort-/Known-Hosts-Änderung. Ursprüngliche Ausfallursache und authentifizierter SFTP-Dateitest bleiben offen. Pageant mit synthetischem Schlüssel, eigene FTP/FTPS/SFTP/WebDAV-Server und nativer WebClient sind praktisch geprüft |
| USB | SanDisk/exFAT einschließlich sicherem Auswurf in der installierten App bestanden; weitere USB-Controller und Verhalten bei abruptem Abziehen bleiben offen |
| Medien | Weitere Hardware-/Codec-Kombinationen. WAV, MP3, AAC, FLAC, Vorbis, Opus, WMA, H.264, MPEG-4, VP9 und HEVC bestehen Wiedergabe, Pause/Fortsetzen, Zeitsuche und Neustart mit dem mitgelieferten FFmpeg-Backend |
| Betriebssysteme | Windows 10, ARM64 und weitere Windows-11-Versionen |
| Geräte | Pixel 8 Pro per MTP praktisch geprüft; weitere Handy-/Kameramodelle, gerätespezifische Rechte und Verhalten bei physischer USB-Unterbrechung bleiben offen. USB-Debugging blieb eingeschaltet; Appium-Sitzungen wurden nicht geprüft |

Der vollständige Funktionsvergleich steht in [PARITY.md](PARITY.md).
Die gemeinsame Implementierung übernimmt den Linux-Funktionskern. Vollständige
Live-Parität mit allen Providern, Geräten und Betriebssystemdiensten ist damit
noch nicht nachgewiesen.
