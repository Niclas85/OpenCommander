# Linux 0.3.21 – Bedienbarkeit aus Handbuch und Testplan

Vollständige Suite: **312 Tests erfolgreich (67,23 s)**. Paket-Smoke-Test
erfolgreich; Hilfe-Modul im Bundle, alle Handbuchkapitel und lokalen Ressourcen
vorhanden und statisch geprüft.
Fünf neue gezielte Fälle prüfen:

- F1-Hilfe ist nicht modal, wird wiederverwendet und öffnet das richtige lokale
  Handbuchkapitel; verständlicher Fallback bei fehlender HTML-Datei.
- Handbuchpfad im portablen Paket relativ zum tatsächlich gestarteten Programm.
- Aktiver Filter ohne Treffer, Rücksetzen per Esc/Knopf und unveränderte Dateien.
- Kopierbarer Auftragsbericht mit Version, Auftrag, Pfaden und gespeichertem Fehler;
  Knopf in kompakter Ansicht ausgeblendet.
- Entfernen nur eigener Ortsverknüpfungen, Hinweis auf Ausblenden für eingebaute
  Orte und konsistente Theme-Checkboxen ohne doppelte Umschaltung.

Alle 20 Handbuchbilder aus temporärem Profil und synthetischen Dateien neu
aufgenommen; keine echte Kontoanmeldung oder Netzwerkoperation. Neue F1-Hilfe
(720 × 560) und Filter-Leerzustand (1500 × 960) visuell kontrolliert.
Handbuchtexte auf 0.3.21 aktualisiert. Der separate Testplan bleibt ausdrücklich
auf seinen ursprünglichen Stand 0.3.19 bezogen.

# Linux 0.3.20 – Fortschritt beim Fortsetzen

Vollständige Suite: **307 Tests erfolgreich (64,15 s)**. Paket-Smoke-Test
erfolgreich (Desktop, JPEG/Online-Bild, TAR/7z, externes Drive-Menü und
gespeicherte Kopierpause/Fortsetzung).

Gezielte neue Regressionen verwenden ausschließlich temporäre lokale Testdaten:

- Simulierter EIO-Schreibfehler nach fertiger erster Datei; nach Neustart bleibt
  deren Byte-/Dateizähler erhalten. Kein erneuter Schreibzugriff auf diese Datei.
- Fehlende zweite Datei wird vor Inhaltsprüfung der fertigen ersten Datei kopiert.
- Pause mitten in der Prüfung behält den inzwischen fertigen Gesamtstand;
  Fortsetzen zählt keine Datei/Bytes doppelt.
- Manipulierter fertiger Zwischenstand gleicher Größe und mit zurückgesetzter
  Änderungszeit wird weiterhin durch Inhaltsprüfung abgewiesen.
- Fehlendes Laufwerk löscht weder den gespeicherten Fortschritt noch den Fehler.
- Auftragskarte zeigt während blockierter Vorprüfung gespeicherten Fortschritt,
  Prüfphase und früheren Fehler; Historie behält frühere Fehler nach Erfolg.

Der laufende produktive Auftrag wurde nur im lokalen SQLite-Journal lesend
untersucht. Zum Untersuchungszeitpunkt: 15.428 fertige reguläre Dateien,
95.877.522.511 Byte. Kein Schreiben auf Cloud-Daten, kein Prozessabbruch,
keine Mount-/Journaländerung. Ursprünglicher Fehlertext war bereits durch die
alte Fortsetzung gelöscht und lässt sich damit nicht verlässlich zuordnen.

# Linux 0.3.19 – Orte und Dienstsymbole

## Ausfüllbarer Testplan (keine neue Anwendungstest-Ausführung)

[HTML-Testplan](docs/testplan/index.html): 158 Fälle in 16 Funktionsbereichen,
85 P0-, 72 P1- und ein P2-Fall. Enthält Voraussetzungen, Schritte, Soll-Ergebnisse,
Provider-/Transfermatrix, Testdaten, Fehler-Schweregrade und Freigabekriterien.
Alle Fälle beginnen als **Nicht ausgeführt**; frühere Suite-Ergebnisse werden
nicht als manuelle Abnahme übernommen. Pro Backend/Variante einen eigenen Lauf
exportieren. CSV-Vorlage und JSON-Falldaten liegen im gleichen Verzeichnis.

Am 12. Oktober 2026 wurde ausschließlich das neue Dokument geprüft:

- Browser: Suche/Einzelfallfilter, Aufklappen, Ergebniserfassung, Statuszähler,
  Speicherung über Reload, neuer leerer Lauf und JSON-Import mit Bestätigung.
- CSV und JSON tatsächlich über die Dokumentoberfläche exportiert; CSV enthält
  alle 158 Fälle und den eingegebenen Probewert. JSON-Rückimport stellt ihn wieder her.
- Probewerte abschließend zurückgesetzt: 0/158 bewertet. Keine Produktivdateien,
  Konten, Mounts oder laufenden Anwendungsübertragungen verändert.
- Desktopansicht 1280 px visuell geprüft; kein horizontaler Dokumentüberlauf,
  keine Warnungen/Fehler in der Browserkonsole.
- Eindeutige IDs, Anker, bestehende Testmodul-Zuordnungen, Offline-Ressourcenfreiheit,
  CSV-Zeilen und ZIP-Integrität geprüft; Python-, JavaScript- und Shell-Syntax gültig.
- Druckdarstellung vorbereitet; PDF-Export und direkte file://-Ausführung wurden
  nicht im Browser getestet. Responsives CSS vorhanden; kein eigener Mobil-Abnahmelauf.

Reproduzierbar erzeugen:

```bash
python3 linux/docs/tools/build_testplan.py
python3 -m http.server 8766 --bind 127.0.0.1 --directory linux/docs/testplan
```

## HTML-Anwenderhandbuch

18 Kapitel, 18 reale Qt-Screenshots mit isolierten Beispieldaten; rund 5.600 Wörter.
Transferwerte und Verbindungen sind ausdrücklich als Demonstrationszustände markiert.
Keine echten Anmeldungen, Cloud-Freigaben oder Nutzerdateiänderungen zur Aufnahme.

- Desktop (1440 × 1000), schmale Standardansicht und Mobilansicht (390 × 844)
  im Browser visuell geprüft; kein horizontaler Dokumentüberlauf.
- Suche nach Pause/iCloud, Kapitelverweise, Theme-Wechsel samt Speicherung,
  Bilddialog, Schließen und Originalgröße mit horizontaler Bildnavigation geprüft.
- 47 Links und 26 lokale Ressourcenreferenzen geprüft; keine fehlenden Anker,
  keine fehlenden Bilddateien und keine externen CSS-/JS-/Bildabhängigkeiten.
- Zusätzlich eine eigenständige HTML-Datei erzeugt: CSS, JavaScript und alle
  23 Bild-/Symbolverweise eingebettet; Base64-Inhalte und fehlende externe
  Abhängigkeiten statisch geprüft. ZIP-Ausgabe auf Integrität geprüft.
- Keine Browser-Konsolenfehler; JavaScript-Syntax, Python-Generatoren und
  Shell-Syntax der Paketierung geprüft. Druckstylesheet und Druck-Handler enthalten;
  ein PDF-Export wurde nicht ausgeführt.
- Browserprüfung über lokalen HTTP-Server. Ein direkter file://-Aufruf ist in der
  eingebetteten Browserumgebung gesperrt; die Offline-Dateistruktur wurde statisch geprüft.

Reproduzieren (Screenshot-Aufnahme verwendet nur ein temporäres Profil):

```bash
QT_QPA_PLATFORM=offscreen PYTHONPATH=linux linux/.venv/bin/python linux/docs/tools/capture_handbook.py
python3 linux/docs/tools/build_handbook.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory linux/docs/handbuch
```

## Anwendungsprüfung

Stand: 12. Oktober 2026. Dienstsymbole werden als eigene lokale SVG-Grafiken
mitgeliefert. OneDrive, Google Drive, Dropbox und iCloud in der Orte-Leiste sowie
FTP/SFTP im Assistenten erkennen; Benutzer-Anzeigenamen bleiben erhalten.
Die obere Leiste lässt sich mit Ziehbild und blauer Einfügemarkierung umsortieren,
alternativ über „Nach links“/„Nach rechts“ im Kontextmenü.

Vollständige Suite: **300 Tests erfolgreich (64,10 s)**. Nach der abschließenden
Darstellungs-Korrektur zusätzlich **10 gezielte Desktop-Tests erfolgreich (3,41 s)**,
einschließlich eines neuen Tests für ausbleibende Aktivierung nach dem Ziehen.
Damit 301 unterschiedliche Testfälle geprüft. Hell-/Dunkeldarstellung und
Einfügemarkierung mit synthetischen Online-Profilen visuell kontrolliert.
Paket-Smoke-Test erfolgreich; SVG-Icon-Engine und alle sechs Dienstgrafiken
im portablen Paket enthalten.

- Reihenfolge in settings.ini gespeichert und nach erneutem Aufbau der Leiste geprüft.
- Fehlende Orte behalten ihren gespeicherten Platz beim Wiedererscheinen.
- Umsortieren öffnet keinen Ort; Datei-URL-Drops werden abgewiesen.
- Ziehen verwendet ausschließlich ein internes Verknüpfungsformat und ein Ziehbild.
- Geräte-Aktualisierungen werden bis zum Abschluss der Ziehaktion zurückgestellt.
- Alte Buttons beim Ersetzen sofort ausgeblendet; keine überlagerten Elemente.
- Vorhandene Online-Orte weiterhin mit direkter Öffnungsaktion; externe Cloud-Mounts
  ebenfalls mit passendem Symbol. Keine Kontoanmeldung für diese UI-Prüfung geändert.

## Vorherige Prüfung: 0.3.18 – Dropbox-Entfernen

Stand: 12. Oktober 2026. Zweite Analyse nach den Verbesserungen in 0.3.17.
Vollständige Suite nach abschließender Scheduler-Korrektur: **296 Tests erfolgreich
(60,86 s)**. Hell-/Dunkeldarstellung mit zwei parallelen Aufträgen, kompakter
Karte, Pause, Historie und Vorschau erneut visuell geprüft. Auch der Abbruch einer
wartenden Vorschau-Löschung gibt die Bedienelemente wieder frei. Paket-Smoke-Test
erfolgreich: Desktop, JPEG/Online-Bild, TAR/7z, externes Drive-Menü und gespeicherte
Pause/Fortsetzung.

| Befund | Änderung und Nachweis |
| --- | --- |
| Alle Dateiaktionen warteten hinter vollständigen Kopien; unabhängiges Entfernen konnte stundenlang warten | Separater Engine-Worker für Entfernen, reservierte Pfade, sichtbarer Wartegrund, eigene Cancel-/Fortschrittsdaten; echte Kopie im Test läuft unverändert weiter |
| Pausierte Kopien könnten bei Erweiterung der Parallelität ihre Quelle verlieren | Auch wartende/pausierte/fehlerhafte Aufträge reservieren ihre Pfade; Entfernen wartet bis Freigabe. Abbruch des betroffenen Kopierjobs gibt den Pfad frei, ohne andere Kopien fortzusetzen |
| Alter Cloud-Cache konnte nach Entfernen wieder erscheinen | Mutation invalidiert Cache/Cooldown; laufende ältere Abfrage wird neu abgefragt, statt alte Daten einzusetzen |
| Vorschau wartete auf beliebiges globales operation_finished-Signal | Eigener Abschluss-Callback pro Löschaktion; fremder Kopierabschluss ändert das Medium nicht |
| Sichtbare Historie erzeugte alle Widgets und untersuchte beim Scrollen jeden Eintrag | Leichte Listeneinträge, Suche nach sichtbarer Region, begrenzte Widgets; Test mit 1.000 Vorgängen und Scrollen bis Eintrag 900 |
| Online-Trennen änderte GUI-Schedulerstatus aus dem Worker | Erfolgs-/Fehlerabschluss im GUI-Thread; Test mit fehlgeschlagenem Trennen |

### Reale Dropbox-Prüfung

Bestehendes Konto lesend erreichbar: ein Eintrag in 0,31 s, kein Fehlerhinweis.
Danach neu angelegter privater Testordner mit synthetischer Textdatei: Datei vor
Entfernen direkt über Dropbox-Backend gelistet, in OpenCommander-Papierkorb verschoben,
ursprünglicher Pfad direkt beim Provider nicht mehr gelistet, Rücknahmekopie mit
richtigem Inhalt geprüft, per Undo wiederhergestellt und erneut beim Provider gelistet.
Testlauf 13,12 s; eigener Testordner anschließend entfernt. Keine vorhandene
Nutzerdatei wurde für diese Prüfung verändert. Die laufende „Weltreise“-Kopie
wurde nicht pausiert, neu gestartet oder umkonfiguriert.

Entfernen bleibt eine wiederherstellbare Verschiebung in den OpenCommander-Papierkorb.
Die Sicherung liegt weiterhin auf dem betreffenden Laufwerk; sie entspricht nicht
permanentem Löschen oder dem nativen Papierkorb des Cloud-Anbieters.

### Historien-Messung

1.000 synthetische Vorgänge in Qt/offscreen, gleiche sichtbare Fenstergröße,
Ausgangsmethode von Commit 6f5762b. Aufbau der sichtbaren Historienliste:

| Methode | Laufzeit | Erzeugte Karten |
| --- | --- | --- |
| 0.3.17 | 1,943 s | 1.000 |
| Optimierte Ansicht | 0,055 s | 4 sichtbare Karten |

Einzelmessung des Aufbaus, keine allgemeine Geschwindigkeitsgarantie.
Alle 1.000 Vorgänge bleiben durch Scrollen zugänglich; unsichtbare Widgets werden
freigegeben. Die JSON-Verlaufsspeicherung bleibt vollständig erhalten.

## Vorherige Analyse: 0.3.17


Stand: 11. Oktober 2026. Die Prüfung umfasst Dateimodell, Auftragssteuerung,
Abbruch/Fortsetzung, Historie, Vorschau und Providerzugriffe der Linux-App.
Vollständige Testsuite: **287 Tests erfolgreich (55,71 s)**.
Nach der abschließenden Archiv-Dateityp-Korrektur: sieben relevante Desktop-Tests
erneut erfolgreich. Paket-Smoke-Test erfolgreich (Desktop, JPEG, Online-Bild,
TAR/7z, externes Drive-Menü und gespeicherte Pause/Fortsetzung).
Die Änderungen wurden mit isolierten Dateien und Testprofilen geprüft. Der laufende
Nutzerauftrag „Weltreise“ blieb unangetastet; sein Journal meldete weiterhin
`running`, keinen Fehler und zunehmende Dateicheckpoints.

## Analyse und behobene Ursachen

| Befund | Änderung / Nachweis |
| --- | --- |
| Jede Tabellenzelle berechnete alle vier Spalten, einschließlich Datum/Größe | Nur angeforderte Spalte formatieren; formatierte Werte bei Listenwechsel invalidieren. Tests für Wiederverwendung, Dateigröße, Archiv-Dateityp und ungültige Provider-Zeitstempel |
| Abgeschlossene Karten wurden alle 250 ms erneut formatiert; Größenberechnung über alle Karten | Unveränderte Karten überspringen, Größenberechnung am sichtbaren Maximum beenden, Timer ohne aktive Übertragungen stoppen |
| Auch unsichtbare Historie baute sämtliche Widgets nach jeder Operation neu auf | Aufbau bis zum Öffnen verschieben; Undo-Aktion weiterhin aktuell |
| Lokale Dateiliste ignorierte ihren Abbruch-Event; Undo-Prüfung las große Dateien ohne Abbruchprüfung | Abbruch zwischen Verzeichniseinträgen bzw. Datenblöcken; Test bestätigt erhaltene Dateien und später erfolgreiches Undo |
| Zusätzliche Dateivorgänge sendeten Fortschritt als Qt-Signale | Wie bei dauerhaften Kopien nur neuesten Snapshot auf dem GUI-Timer anzeigen; Ergebnisse für Historie/Verbindungen ausdrücklich im GUI-Thread |
| rclone ohne Schreibcache nahm Append-Öffnung an, scheiterte erst beim Schreiben mit ESPIPE; Schließen meldete zusätzlich EPERM | Auf echtem lokalem rclone/FUSE reproduziert. Nach Präfixprüfung nur unvollständige Datei neu schreiben, fertige Dateien erhalten. Geändertes Präfix wird vor Schreiböffnung abgewiesen |
| Lange Zeiten als rohe Sekunden oder unbegrenzt wachsende Minutenangabe | Einheiten s/min/h und ab 24 Stunden Tage, auch für Restzeit und Medien-Downloads; Grenzwerte und Deutsch/Englisch geprüft |
| Status schwerer unterscheidbar; Abschluss setzte Geschwindigkeit auf null | Zusätzliche Statusfarben in Hell/Dunkel; durchschnittliche Geschwindigkeit der abgeschlossenen Sitzung erhalten |

### Messung des Dateimodells

20.000 synthetische Dateien, vier Display-Zellen je Datei, drei Durchläufe in
isoliertem Qt/offscreen-Prozess auf diesem Rechner. Ausgangspunkt: Commit 71e2586.

| Stand | Erster Durchlauf | Weitere Durchläufe |
| --- | --- | --- |
| 0.3.16 | 1,588 s | 1,427 / 1,441 s |
| Optimiertes Dateimodell | 1,166 s | 1,069 / 1,118 s |

Rund 25 % kürzere wiederholte Zellabfragen. Das ist ein Modell-Mikrobenchmark,
keine Aussage über Kopierbandbreite, Cloud-Ladezeit oder alle GUI-Aktionen.
Zusätzlich in isolierter laufender GUI geprüft: zwei parallele Aufträge, ein Auftrag
minimiert/pausiert, langer Zeitwert, Hell- und Dunkeldarstellung. Keine echte Nutzerdatei
wurde dafür übertragen oder gelöscht.

### Verbleibende Architekturgrenzen

- Inhaltsprüfungen für sichere Rücknahme und Fortsetzung lesen Dateien erneut.
  Auf großen Cloud-Ordnern bleibt das teuer. Diese Prüfung wurde nicht abgeschwächt.
- Die aktuelle Übertragung läuft über das Dateisystem/FUSE. Direkte, separat
  steuerbare rclone-Transfers mit explizitem Uploadabschluss sind noch nicht implementiert.
- Bei externen rclone-Mounts mit Schreibcache kann der Dateiabschluss vor dem tatsächlichen
  Cloud-Upload liegen; die App bestätigt damit keinen gesonderten Provider-Uploadstatus.
- Ein bereits blockierender Dateisystemaufruf kann erst nach Rückkehr reagieren.
  Der GUI-Button setzt den Abbruch sofort, garantiert aber keinen sofort beendeten
  Kernel-/Providerzugriff. Mounts werden nicht gewaltsam getrennt.
- Auf rclone wird bei Fortsetzung die unvollständige Datei neu geschrieben, auch wenn
  der externe Mount Append mit Cache unterstützen könnte. Fertige Dateien bleiben
  nach Prüfung erhalten; lokale Teilkopien werden weiterhin byteweise fortgesetzt.
- Die Historie erzeugt ab 0.3.18 nur sichtbare Karten. Das Laden/Speichern der
  vollständigen JSON-Historie und die Konfliktprüfung sehr großer Mehrfachauswahlen
  bleiben mögliche Engpässe; sehr große Verläufe benötigen weitere Langzeittests.
- Google-Quoten, Konto-/Serverregeln und Anmeldestatus bleiben externe Einflüsse.
  Die bisherigen realen Kontoprüfungen stehen unten mit ihrem tatsächlichen Umfang.
  In dieser Runde wurde kein neuer Login und keine öffentliche Freigabe ausgelöst.

## Bisherige Verbindungsprüfungen und abgedeckte Funktionen

Lesende Google-Drive-/OneDrive-Prüfungen stammen von 0.3.14; die zugehörigen
automatisierten Regressionstests werden mit der vollständigen Suite erneut ausgeführt.

| Bereich | Prüfung | Ergebnis / Grenze |
| --- | --- | --- |
| Google Drive | Bestehendes externes Laufwerk, direkte lesende Backend-Abfrage | `403 Quota exceeded / RATE_LIMIT_EXCEEDED` reproduziert. Neue Abfragen: 717 Einträge in 2,45 bzw. 2,12 s; keine Freigabe erstellt |
| OneDrive | Gespeichertes Konto, direkte lesende Backend-Abfrage | 30 Einträge, rund 0,90 s |
| NAS / SMB | Lesende Ordnerabfrage über GVFS | Erfolgreich, rund 0,55 s; geprüfter Ordner leer |
| iCloud | Bestehende Konfiguration lesend geprüft | Ungültige Passwort-Konfiguration; erneute Anmeldung nötig |
| Dropbox | Bestehendes Konto, neue synthetische Testdatei in eigenem Testordner (0.3.18) | Entfernen direkt beim Provider geprüft, Rücknahmekopie, Undo und Aufräumen erfolgreich; keine vorhandene Nutzerdatei verändert |
| SFTP | Lokaler Testserver mit Passwort, Schlüssel und verschlüsseltem Schlüssel | Erfolgreich; keine persönlichen Server geändert |
| FTP / FTPS | Konfigurations-, Passwortübergabe-, TLS- und Fehlerpfade | Automatisiert geprüft; kein externer FTP-/FTPS-Testserver vorhanden |
| Externe Cloud-Mounts | Drive / OneDrive / Dropbox / iCloud | Zuordnung des laufenden Prozesses, Konfiguration, Remote-Unterordner, keine kopierten Zugangsdaten |
| Fehlerbehandlung | Abgelaufene/ungültige Anmeldung, blockiertes Backend, Abbruch, Wiederholung | Begrenzte Prozesse, verständliche Fehler ohne ungefilterte Secrets; GUI bleibt bedienbar |
| Cloud-Abfragelimits | Google Drive, OneDrive, Dropbox, iCloud; simulierte 403/429 und temporäre Fehler | Erster Abruf nach zwei Fehlern erfolgreich, begrenzte Versuche, Cooldown, alter Cache gekennzeichnet, erneute Verbindung, kein Cache bei Anmeldefehler |
| Parallele Abfragen | Zwei Dateibereiche und abgebrochene wartende Abfrage | Ein Backend-Abruf für identischen Ordner; Warte- und Retry-Phasen abbrechbar |
| Google OAuth-Client | Eigene Desktop-Client-Daten mit synthetischem Testprofil, echtes Backend nur bis zur Browser-Frage | Private Datei 0600, andere Profile erhalten, alter Token verworfen, Secret maskiert und aus UI-/Prozessdaten ferngehalten; kein echter neuer Google-Login |
| Dateiliste bei Fehler | Vorhandene Liste, temporärer Fehler, alter Cache, automatische Wiederholung, Ordnerwechsel | Dateien bleiben mit Hinweis sichtbar; keine verspätete Wiederholung im neuen Ordner |
| Live-GUI bei Google-Limit | Isoliertes Testprofil, reale Drive-/OneDrive-Mounts, externe Backend-Erkennung | Abfragelimit erneut aufgetreten; 708/27 sichtbare Einträge erhalten (versteckte ausgeblendet). 682 GUI-Timer-Ereignisse in 6,92 s, längste Lücke 27 ms; laufende Nutzerkopie nicht unterbrochen |
| Cloud-Freigaben | Kontextmenü, Dialog, HTTPS-Link, Kopieren, Abbruch | Simulierter Provider; keine persönlichen Dateien öffentlich freigegeben |
| Laufwerke | Nicht eingebunden, Einbinden, Fehler, direkte Navigation | Separate Desktop-Fixtures; keine persönlichen Datenträger eingebunden/ausgeworfen |
| Transfer | Kopieren/Verschieben, Undo, NAS-/FUSE-Metadaten und echte Fehler | Separate Testdaten, teilweise echter lokaler rclone-/SFTP-Testserver |
| Altversion-Zwischenstände | Explizite Übernahme, fertige Datei ohne Schreiböffnung, Teilbytes, falsche Inhalte, Symlinks, vorige Originale, Mountpfad | Isolierte Testdaten; Altordner werden nicht automatisch angenommen |
| Kopier-Fortsetzung | Pause nach geschriebenem Datenblock, Neustart in neuem Prozess, fertige Dateien, Teilbytes, Queue, GUI-Schließen, Abbruch, Undo, fehlende Mounts, manipulierte Daten, uneindeutiger Publish | Isolierte lokale Testdaten; kein laufender Nutzertransfer geändert |
| Minimierte Aufträge | Einzelne laufende Karte kompakt, andere Karte unverändert, Fortschritt/Controls sichtbar, Details wiederherstellen, Neustart | Bestehende Parallel-/Neustarttests erweitert; synthetische Testdaten |
| Parallele Übertragungen | Zwei echte Kopien gleichzeitig, Pause/Abbruch einzeln, alle beim Schließen speichern, Neustart, Einstellungen/Navigation, GUI-Heartbeat | Isolierte Testdateien; blockierte Providerzugriffe mit Events nachgebildet |
| Pfadkonflikte | Kopieren gegen Verschieben, pausierte Quellen, lokale Aliase, Behalten-Namensfamilien | Konflikte warten; Providerpfade im GUI nicht gestattet |
| Dauerhaftes Verschieben | Native Umbenennung/Undo, Laufwerksgrenze, Pause/Neustart, Quelländerung, Pause während Bereinigung | Vollständiges Ziel erhalten, geänderte Quellen geschützt, Historie gemeinsam serialisiert |
| Paralleles Einbinden | Gleicher Online-Ort in zwei Workern, Abbruch eines Wartenden | Nur ein Daemon gestartet, unabhängiger Abbruch |
| GUI während Transfer | Echte lokale Kopie, parallele Einstellungen, Themenwechsel, Navigation, GUI-Heartbeat und Thread-Zustellung | Automatisierter Desktop-Test; laufende Nutzerkopie nicht unterbrochen |
| Orte-Leiste und Verwaltung | Nur Öffnungsziele in der Leiste; Online-Orte und Verbindungen aus Einstellungen | Desktop-Tests in Deutsch und Englisch |
| Ordnerbaum | Breite, vollständige Namen und gespeicherter Splitter | Automatisierter Desktop-Test |
| Drag-and-drop | Sichtbare Pixmap, Hotspot, Copy/Move, Datei-/Ordnerziele | Automatisierte Mausgesten und Testdaten-Transfers |

Die Laufzeiten sind Einzelmessungen und keine Geschwindigkeitsgarantie. Die
Tests ersetzen keine Prüfung jeder Konto- oder Serverrichtlinie. Insbesondere
öffentliche Freigaben können durch den Anbieter bzw. Administrator gesperrt sein.
Ein neuer iCloud-Login benötigt Apple-ID/2FA und wurde nicht automatisch gestartet.

Prüfungen:

```sh
QT_QPA_PLATFORM=offscreen linux/.venv/bin/python -m pytest linux/tests -q
OPENCOMMANDER_BUILD_ROOT=/dev/shm/opencommander-linux-build ./linux/build.sh
```

Der Paket-Smoke-Test prüft zusätzlich GUI-Start, JPG-Vorschau, isolierten
Online-Bilddownload, TAR/7z, das externe Google-Drive-Kontextmenü sowie
persistente Kopier-Pause und Wiederaufnahme mit dem gebündelten Python/SQLite.
