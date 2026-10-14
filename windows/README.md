# OpenCommander für Windows

Native Windows-App mit derselben Qt-Oberfläche und demselben Funktionskern wie
Linux **0.3.25rc10**. Kein WSL und keine separate Python-Installation für das
fertige Paket nötig. Zielplattform: **Windows 11, x64**. Windows 10 und ARM64
sind mit diesem Paket nicht geprüft.

## Starten

`OpenCommander-windows-x64.zip` vollständig entpacken und `OpenCommander.exe`
öffnen. `_internal`, `helpers`, `tools` und `docs` neben der EXE belassen.
Das Paket ist portabel und benötigt für lokale Dateien keine Administratorrechte.
Es ist noch nicht mit einem Herausgeber-Zertifikat signiert.

Optional `install-local.ps1` im entpackten Ordner ausführen: Es legt einen
Startmenü-Eintrag und einen Explorer-Kontextmenüeintrag für das eigene Konto an.
Der erste reguläre App-Start fragt separat nach der Standardzuordnung für Ordner.
`uninstall-local.ps1` entfernt die Integration und stellt die vorherige Zuordnung
wieder her. Einstellungen und Wiederherstellungsdaten bleiben erhalten.

Für ein bereits vorhandenes Profil außerhalb des Standardpfads unterstützt das
Skript `-StateDirectory "C:\Pfad\zum\Profil"`. Startmenü und Kontextmenü öffnen
dann dasselbe Profil. Die Integration im normalen Windows-Benutzerkontext
ausführen; paketierte Entwicklungsumgebungen können Registry und AppData umleiten.
Der praktische Prüfstand steht in `TESTING.md`.

## Funktionsumfang

Der gemeinsame Code in `linux/opencommander/` stellt auf beiden Plattformen bereit:

- Zwei Dateibereiche mit Ordnerbäumen, Laufwerken, Suche, Filter und eigenen Pfaden.
- Kopieren, Verschieben, Konfliktdialoge, Mehrfachumbenennen, Ordnervergleich.
- Drag-and-drop, Zwischenablage, Tastenkürzel, Vorschau und Eigenschaften.
- Übertragungswarteschlange, parallele Aufträge, Pause, Abbruch und Fortsetzen nach Neustart.
- Persistente Historie, geprüfte Rücknahme und eigener wiederherstellbarer Papierkorb.
- ZIP-Erstellung; ZIP, TAR/TGZ, BZ2, XZ, ZST, 7z und RAR lesen und entpacken.
- Bild-, Audio- und Videovorschau, begrenzte Downloads für Online-Medien.
- Gespeicherte Orte, Deutsch/Englisch, helles/dunkles Design und Offline-Handbuch.
- Google Drive, OneDrive, Dropbox, iCloud und SFTP/FTP/FTPS mit den bestehenden
  Anmelde-, Freigabe- und Verbindungsdialogen.

| Linux-Anbindung | Windows-Umsetzung |
| --- | --- |
| `/`, `/media`, GVFS-Laufwerke | Laufwerksbuchstaben, UNC, Windows-Laufwerksnamen |
| GIO SMB/WebDAV-Anmeldung | Windows-Netzwerkanmeldung; SFTP/FTP über Online-Orte |
| FUSE/rclone | WinFsp/rclone, mitgelieferte rclone-EXE |
| Secret Service | Windows-Anmeldeinformationsverwaltung |
| `renameat2(RENAME_NOREPLACE)` | Windows-Umbenennung ohne Überschreiben |
| `O_NOFOLLOW` | Windows-Dateihandle mit Prüfung von Reparse-Tags |
| POSIX-Zugriffsrechte | NTFS-Zugriffssteuerung für private Cloud-Konfiguration |
| `xdg-mime` | Optionale Ordnerzuordnung für das aktuelle Windows-Konto |
| System-Python-Helfer | Mitgelieferter, unsichtbar gestarteter Windows-Helfer |

## Cloud und Netzwerk

Für Cloud-/SFTP-/FTP-Laufwerke einmal **[WinFsp](https://winfsp.dev/)** installieren.
Das ist die Windows-Entsprechung der FUSE-Voraussetzung unter Linux. WinFsp wird
nicht ungefragt installiert. Die App erklärt eine fehlende Installation beim
Verbinden. Siehe auch die [rclone-Windows-Anleitung](https://rclone.org/commands/rclone_mount/#installing-on-windows).

Cloud-Konten bleiben persönlich. Öffentliche Herausgeber-OAuth-IDs werden beim
Bauen mit denselben `OPENCOMMANDER_*_OAUTH_FILE`-Variablen wie unter Linux eingebettet.
Ohne diese Registrierung gelten die bestehenden Experten-/Provider-Verfahren.
SMB verwendet Windows-Anmeldedaten; WebDAV benötigt den Windows-WebClient-Dienst
und dessen unterstützte Authentifizierung. SFTP-Hostschlüssel werden weiterhin
explizit geprüft. Dafür müssen die Windows-OpenSSH-Werkzeuge installiert sein.
Verschlüsselte OpenSSH-Schlüssel werden für rclone ausschließlich im Arbeitsspeicher
entsperrt. Der SSH-Agent-Modus verwendet den von rclone unterstützten Windows-Agenten
(Pageant); siehe [rclone SFTP](https://rclone.org/sftp/).

NTFS wird direkt über Windows gelesen und geschrieben. Normale Windows-Dateirechte
gelten weiterhin. Symbolische Links erfordern gegebenenfalls Windows-Entwicklermodus;
Verzeichnis-Junctions werden beim rekursiven Kopieren und Archivieren abgewiesen,
damit die App keine fremden Verzeichnisbäume unbeabsichtigt durchläuft.
Windows-reservierte Namen, alternative Datenströme und kollidierende Archivnamen
werden bei der Extraktion abgewiesen. Video-Thumbnails benötigen wie unter Linux
optional `ffmpeg`; die Wiedergabe benutzt Qt Multimedia.
Die Windows-Ausgabe verwendet dabei den nativen Windows-Medienbackend. Unterstützte
Audio-/Video-Codecs hängen daher von der Windows-Installation ab; der Qt-Backend
kann bei Bedarf über `QT_MEDIA_BACKEND` umgestellt werden.

## Daten und Wiederherstellung

Einstellungen, Historie und Warteschlange: `%LOCALAPPDATA%\OpenCommander`.
Cloud-Token liegen im zugriffsbeschränkten Unterordner `online`; optionale
Server-Passwörter in Windows-Anmeldeinformationen. Wiederherstellbare Originale
bleiben wie unter Linux in `.OpenCommander*`-Ordnern auf dem jeweiligen Laufwerk.
Den App-Ordner zu löschen entfernt diese Daten nicht.

## Entwickeln und Bauen

Python 3.12+ x64 verwenden:

```powershell
.\windows\run.ps1
.\windows\run.ps1 --left C:\ --right "$env:USERPROFILE\Downloads"
.\windows\build.ps1
```

Der Build führt die Windows-Tests und einen Quellcode-Smoke-Test aus, erstellt
GUI und Helfer mit PyInstaller und prüft dann das fertige Paket. Das ZIP und
seine SHA-256-Prüfsumme liegen unter `windows/artifacts/`.

```powershell
windows/.venv/Scripts/python.exe -m pytest windows/tests -q
windows/.venv/Scripts/python.exe windows/launcher.py --smoke-test
```

Die Windows-Tests übernehmen die gemeinsamen Datei-, Archiv-, Medien-, Transfer-
und UI-Regressionstests und ergänzen native Windows-Prüfungen. Linux-spezifische
Tests werden begründet übersprungen; Linktests ohne Symlink-Recht ebenfalls.
Echte Provider-Anmeldungen, Live-NAS-Zugriff, USB-Auswurf, Explorer-Standardzuordnung
und Wiedergabe sämtlicher Codec-Varianten bleiben manuelle Integrationstests.
Ein erfolgreicher lokaler Build bestätigt daher noch keine vollständige Live-Parität.

## Lizenzen

OpenCommander: MIT. PySide6/Qt: LGPLv3/GPL bzw. die mitgelieferten Modulhinweise;
Bibliotheken liegen austauschbar in `_internal`, Anwendungsquellen in `source`.
pywin32: PSF-Lizenz, psutil: BSD-3-Clause, cryptography: Apache-2.0/BSD-3-Clause,
rclone: MIT (Hinweise unter `tools`). Windows stellt libarchive über die eigene
Systembibliothek `System32\archiveint.dll` bereit; diese DLL wird nicht kopiert.
Das Paket benötigt eine Windows-Version mit dieser Bibliothek. Weitere gemeinsame
Lizenztexte stehen unter `licenses` und `THIRD-PARTY-LINUX.md`.
