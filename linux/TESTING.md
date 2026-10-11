# Linux 0.3.14 – Verbindungs- und Desktop-Prüfung

Stand: 11. Oktober 2026. Erneute Live-Prüfung von Google Drive und OneDrive
mit 0.3.14; weitere Live-Verbindungen wie unten dokumentiert. Gesamtsuite:
253 Tests erfolgreich.

| Bereich | Prüfung | Ergebnis / Grenze |
| --- | --- | --- |
| Google Drive | Bestehendes externes Laufwerk, direkte lesende Backend-Abfrage | `403 Quota exceeded / RATE_LIMIT_EXCEEDED` reproduziert. Neue Abfragen: 717 Einträge in 2,45 bzw. 2,12 s; keine Freigabe erstellt |
| OneDrive | Gespeichertes Konto, direkte lesende Backend-Abfrage | 30 Einträge, rund 0,90 s |
| NAS / SMB | Lesende Ordnerabfrage über GVFS | Erfolgreich, rund 0,55 s; geprüfter Ordner leer |
| iCloud | Bestehende Konfiguration lesend geprüft | Ungültige Passwort-Konfiguration; erneute Anmeldung nötig |
| Dropbox | Kein Konto vorhanden | Erkennung, Pfade, Fehler, Abbruch und Linkanfragen mit isoliertem Backend getestet |
| SFTP | Lokaler Testserver mit Passwort, Schlüssel und verschlüsseltem Schlüssel | Erfolgreich; keine persönlichen Server geändert |
| FTP / FTPS | Konfigurations-, Passwortübergabe-, TLS- und Fehlerpfade | Automatisiert geprüft; kein externer FTP-/FTPS-Testserver vorhanden |
| Externe Cloud-Mounts | Drive / OneDrive / Dropbox / iCloud | Zuordnung des laufenden Prozesses, Konfiguration, Remote-Unterordner, keine kopierten Zugangsdaten |
| Fehlerbehandlung | Abgelaufene/ungültige Anmeldung, blockiertes Backend, Abbruch, Wiederholung | Begrenzte Prozesse, verständliche Fehler ohne ungefilterte Secrets; GUI bleibt bedienbar |
| Cloud-Abfragelimits | Google Drive, OneDrive, Dropbox, iCloud; simulierte 403/429 und temporäre Fehler | Erster Abruf nach zwei Fehlern erfolgreich, begrenzte Versuche, Cooldown, alter Cache gekennzeichnet, erneute Verbindung, kein Cache bei Anmeldefehler |
| Parallele Abfragen | Zwei Dateibereiche und abgebrochene wartende Abfrage | Ein Backend-Abruf für identischen Ordner; Warte- und Retry-Phasen abbrechbar |
| Google OAuth-Client | Eigene Desktop-Client-Daten mit synthetischem Testprofil, echtes Backend nur bis zur Browser-Frage | Private Datei 0600, andere Profile erhalten, alter Token verworfen, Secret maskiert und aus UI-/Prozessdaten ferngehalten; kein echter neuer Google-Login |
| Dateiliste bei Fehler | Vorhandene Liste, temporärer Fehler, alter Cache, automatische Wiederholung, Ordnerwechsel | Dateien bleiben mit Hinweis sichtbar; keine verspätete Wiederholung im neuen Ordner |
| Cloud-Freigaben | Kontextmenü, Dialog, HTTPS-Link, Kopieren, Abbruch | Simulierter Provider; keine persönlichen Dateien öffentlich freigegeben |
| Laufwerke | Nicht eingebunden, Einbinden, Fehler, direkte Navigation | Separate Desktop-Fixtures; keine persönlichen Datenträger eingebunden/ausgeworfen |
| Transfer | Kopieren/Verschieben, Undo, NAS-/FUSE-Metadaten und echte Fehler | Separate Testdaten, teilweise echter lokaler rclone-/SFTP-Testserver |
| Altversion-Zwischenstände | Explizite Übernahme, fertige Datei ohne Schreiböffnung, Teilbytes, falsche Inhalte, Symlinks, vorige Originale, Mountpfad | Isolierte Testdaten; Altordner werden nicht automatisch angenommen |
| Kopier-Fortsetzung | Pause nach geschriebenem Datenblock, Neustart in neuem Prozess, fertige Dateien, Teilbytes, Queue, GUI-Schließen, Abbruch, Undo, fehlende Mounts, manipulierte Daten, uneindeutiger Publish | Isolierte lokale Testdaten; kein laufender Nutzertransfer geändert |
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
