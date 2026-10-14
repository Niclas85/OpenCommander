# Windows und Linux: vollständiger Desktop-Funktionsvergleich

Stand: 14. Oktober 2026, gemeinsamer Anwendungskern 0.3.25rc10.
Referenz ist die Linux-Version dieses Repositorys, nicht die macOS- oder
Mobil-App. Windows startet dieselben Qt-Dialoge, Werkzeuge und Dateioperationen
aus `linux/opencommander`; Betriebssystemdienste haben eigene Adapter.

**Kein uneingeschränktes 1:1-Versprechen:** Der Funktionskern ist gemeinsam,
aber GNOME/GVFS, Windows-Shell, Dateirechte, Geräte und Provider-Regeln unterscheiden
sich. Insbesondere ist stabiler Google-Dateizugriff mit dem gemeinsam genutzten
rclone-OAuth-Client aktuell nicht bestätigt.

## Oberfläche und Dateiwerkzeuge

| Funktion der Linux-Version | Windows | Nachweis / praktische Grenze |
| --- | --- | --- |
| Zwei Bereiche, Ordnerbaum, Pfadleiste, Zurück/Vorwärts, übergeordneter Ordner | Gleicher Qt-Code | Gemeinsame UI-Tests |
| Sortierung, Filter, Auswahl, Unicode-Namen, verborgene Dateien | Gleicher Qt-Code | Tests; Unicode-Dateien praktisch kopiert. Windows-Hidden-Attribut zusätzlich berücksichtigt |
| Kopieren F5, Verschieben F6, Modus-Umschalter | Gleicher Kern | Lokale, NAS- und Cloud-Transfers; Wechsel NTFS/exFAT praktisch geprüft |
| Konfliktdialog, Überspringen, Umbenennen, Ersetzen mit Sicherung | Gleicher Kern | Tests und lokale Konfliktprüfung |
| Ordner anlegen, Umbenennen F2, Entfernen | Gleicher Kern | Tests und Live-Dateiaktionen |
| Eigene wiederherstellbare Löschablage | Gleicher Kern | Originale bleiben in `.OpenCommander*`-Ordnern; kein Ersatz für Provider-Web-Papierkörbe |
| Persistente Historie, Detailanzeige, Rückgängig nach Neustart | Gleicher Kern | Lokal, SMB und Cloud; veränderte Ziele werden geschützt |
| Warteschlange und mehrere parallele Aufträge | Gleicher Kern | Gemeinsame Tests prüfen Inhalte, Konflikte und getrennten Abbruch |
| Pause, Fortsetzen und Wiederaufnahme nach Neustart | Gleicher Kern | 16-MiB-Live-Kopie und gemeinsame Wiederaufnahme-Tests |
| Fortschritt, Dateien/Bytes/Prozent/Zeit, Verbindungsabbruch | Gleicher Kern | Tests; ein blockierender Dateisystemaufruf kann Abbruch verzögern |
| Drag-and-drop und interne Zwischenablage | Gleicher Qt-Code | Gemeinsame UI-Tests |
| Austausch mit System-Dateimanager | Windows-Dateiformate statt GNOME-Formate | Explorer-Kopie in beiden Richtungen bytegenau geprüft |
| Suche: Muster, Groß-/Kleinschreibung, Rekursion, Abbruch | Gleicher Kern | Tests und praktische Suche |
| Ordnervergleich einschließlich Dateiinhalt | Gleicher Kern | Gleich große unterschiedliche Dateien und praktischer Vergleich |
| Mehrfachumbenennen: Vorschau, Zähler, Konflikte, Rücknahme | Gleicher Kern | Tests und praktische Umbenennung |
| ZIP erstellen | Gleicher Kern | Praktisch erstellt und gelesen |
| ZIP, TAR/TGZ, BZ2, XZ, ZST, 7z, RAR lesen/entpacken | Gleicher libarchive-Kern | Alle Formate einschließlich echtem RAR5 praktisch geprüft |
| Archiv-Schutz vor Traversal, Links und Spezialdateien | Gemeinsame Prüfungen plus Windows-Namensregeln | Windows reservierte Namen, NTFS-Datenströme und Namenskollisionen zusätzlich getestet |
| Bildvorschau, nächstes/vorheriges Bild, Thumbnail-Downloads | Gleicher Qt-Code | PNG/JPEG und Online-Download-Smoke-Test |
| Audio-/Videovorschau, Wiedergabe, Zeitsuche, Neustart | Gleicher Qt-Code, Windows-Medienbackend | WAV und H.264 praktisch; weitere Codecs abhängig vom System |
| Öffnen und Öffnen mit | Windows-Shell statt GIO/xdg-open | Native Integration; verfügbare Programme bestimmt Windows |
| Eigenschaften und Ordnergröße | Windows-Adapter statt GIO | Live-Prüfung; NTFS-Erstellzeit vorhanden, POSIX-Modus nicht gleichwertig |
| Gespeicherte Orte: hinzufügen, bearbeiten, umsortieren, ausblenden | Gleicher Qt-Code | Gemeinsame Präferenz- und Persistenztests |
| Deutsch/Englisch, hell/dunkel, Tastenkürzel | Gleicher Qt-Code | Gemeinsame UI-/Sprachtests und native Darstellung |
| Offline-Handbuch, Info und Hilfe F1 | Gemeinsame Inhalte | Handbuch im Windows-Paket enthalten |

## Cloud, Netzwerk und Geräte

| Funktion der Linux-Version | Windows | Nachweis / praktische Grenze |
| --- | --- | --- |
| OneDrive per Browser-OAuth ohne Sync-Client | Gleicher Assistent; WinFsp statt FUSE | Anmeldung, gespeichertes Profil, 256-KiB-Upload, Lesen, Helfer und persistente Rücknahme bestanden |
| Dropbox per Browser-OAuth | Gleicher Assistent; WinFsp statt FUSE | Vollständiger Datei-Roundtrip bestanden; Browserübergang und lokaler OAuth-Server korrigiert |
| Google per rclone-Browser-OAuth | Gleicher Assistent; WinFsp statt FUSE | Anmeldung gespeichert, Mount und Auflisten erfolgreich; Upload/Freigabe zeitweise möglich, weitere Aufrufe HTTP 403/Quota. Kein stabiler vollständiger Nachweis |
| Google über GNOME Online Accounts / GVFS | Kein entsprechender Windows-Systemdienst | Linux kann zusätzlich ein vom Desktop eingerichtetes GVFS-Laufwerk benutzen. Diese separate GNOME-OAuth-Anwendung ist nicht die rclone-Anmeldung |
| iCloud per Apple-ID und Zwei-Faktor-Code | Gleicher Assistent | Benutzeranmeldung, Mount, 256-KiB-Upload, bytegenaues Lesen, Helfer und Rücknahme bestanden. Apple verwendet hier keinen reinen Browser-OAuth-Ablauf |
| Freigabelink Dropbox | Gleiche Provider-Aktion | Anonymer HTTP-Download bytegenau bestanden; synthetische Datei und Ordner entfernt |
| Freigabelink OneDrive | Gleiche Provider-Aktion | Dateiinhalt im nicht angemeldeten Browser sichtbar; synthetische Datei und Ordner entfernt |
| Freigabelink Google | Gleiche Provider-Aktion | Linkerstellung und anonymer Dateiinhalt im Browser bestätigt; Entfernen der synthetischen Testdatei durch Provider-Quota blockiert |
| Freigaben im Provider-Browser verwalten; Online-Pfad kopieren | Gleiche Aktionen | Gemeinsame Tests; iCloud-Linkerstellung ist auf beiden Plattformen nicht implementiert, Browser-Verwaltung bleibt verfügbar |
| Online-Suche, Vergleich, Umbenennen, ZIP, Vorschau und Transfers | Gemeinsame Werkzeuge auf dem Mount | Gemeinsame Tests und echte Mounts; einzelne Provider können Attribute/Funktionen einschränken |
| FTP | Gleicher Assistent; WinFsp statt FUSE | Eigener Loopback-Server: 256-KiB-Datei, Helfer, Rücknahme, Abbruch und Trennen bestanden |
| Explizites FTPS mit aktiver Zertifikatsprüfung | Gleicher Assistent | Apache FtpServer 1.2.1: kompletter Datei-Roundtrip und Zertifikatsablehnung bestanden |
| SFTP mit Passwort, privatem Schlüssel oder verschlüsseltem Schlüssel | Gleicher Assistent | Echter SFTP-Test für diese drei Anmeldearten; geänderter Hostschlüssel abgewiesen |
| SSH-Agent | Linux ssh-agent; Windows Pageant laut rclone-Backend | Windows-Agent-Anmeldung nicht mit einem persönlichen Agenten live geprüft |
| SFTP-Hostschlüsselprüfung und bekannte Hosts | Windows-OpenSSH statt Linux-OpenSSH | Schutztests; vorhandener geänderter Schlüssel wird nicht automatisch akzeptiert |
| SMB/NAS | Windows-Netzwerkanmeldung/UNC statt GVFS | Reales NAS: Unicode, 256-KiB-Datei, Helfer, Eigenschaften und persistente Rücknahme bestanden |
| WebDAV über rclone | WinFsp statt FUSE | Eigener WebDAV-Server: vollständiger Datei-Roundtrip bestanden |
| WebDAV über Systemdienst | Windows WebClient statt GVFS | Nativer UNC-Redirector gegen anonymen Loopback-Server geprüft; Zeitstempel-Kopierfehler korrigiert. Externe Authentifizierungsrichtlinien nicht mitgeprüft |
| Externe rclone-Mounts / lokale Sync-Ordner | Windows-Laufwerke/Verzeichnisse statt Linux-Mountinfo | Gemeinsame Werkzeuge; Linux `/proc`-Erkennung wird nicht nachgebildet |
| Lokale Laufwerke, USB-Speicher und Netzlaufwerke | Laufwerksbuchstaben und UNC statt `/media` und GVFS | NTFS, exFAT und SMB live geprüft |
| Sicheres Trennen / Auswerfen | Windows-Shell-/Geräte-API statt GIO | Umsetzung vorhanden; physischer SanDisk-Auswurf auf ausdrücklichen Benutzerwunsch nicht getestet |
| Andere von GVFS bereitgestellte Geräte, z. B. MTP-Kamera/Telefon | Kein Windows-WPD/MTP-Adapter | Windows verarbeitet dateisystemfähige Laufwerke. Eine reine Explorer-MTP-Ansicht ist kein nutzbarer Pfad; hier besteht keine 1:1-Geräteparität |

## Systemunterschiede und Sicherheit

| Linux | Windows | Auswirkung |
| --- | --- | --- |
| Atomare `renameat2(RENAME_NOREPLACE)` | Windows-Umbenennung ohne Überschreiben | Lokaler Zielschutz auf beiden Plattformen; Provider-Rennen mit anderen Clients bleiben möglich |
| POSIX `O_NOFOLLOW`, Dateimodi und Links | Geprüfte Windows-Handles, NTFS-ACLs, Reparse-Tags | Junctions werden beim rekursiven Kopieren/Archivieren abgewiesen; Symlink-Erstellung benötigt Windows-Rechte |
| Lokale Verknüpfung auf entfernten Provider | Lokale Aliase vor der Provider-Erkennung normalisieren | Eigene Windows-Tests für beide nativen Pfadpräfixe; Provider-Verzeichnisse werden dabei nicht abgefragt |
| Konfigurationsdateien 0600, private Ordner 0700 | Private NTFS-DACLs | Gleiche Absicht, verschiedene Rechte. Tests prüfen unter Windows tatsächliche Leser statt numerischer POSIX-Modi |
| Private SSH-Schlüssel gegen andere Unix-Leser schützen | Öffentliche NTFS-Leserechte abweisen | Neuer Windows-Regressionsnachweis; bestehende Benutzerschlüssel werden nicht umgeschrieben |
| Secret Service | Windows-Anmeldeinformationsverwaltung | Optional gespeicherte Server-Passwörter im jeweiligen Systemdienst |
| GIO/GTK-Anmeldedialoge, GNOME-Orte | Native Windows-Netzwerkanmeldung und Shell | Unterschiedliche Systemdialoge; Qt-Anwendungsdialoge bleiben gemeinsam |
| `xdg-mime` und Desktop-Datei | Startmenü, Explorer-Kontextmenü und optionale Ordnerzuordnung | Reversible Windows-Integration praktisch geprüft; vorherige Ordnerzuordnung wiederhergestellt |
| System-Python-Helfer, FUSE | Mitgelieferter EXE-Helfer, WinFsp | Fertiges Windows-Paket benötigt weder Python noch WSL |

## Vergleichsverfahren und Ergebnis

Alle Linux-Testmodule werden auch vom Windows-Testpaket importiert. Ausschließlich
plattformgebundene Fälle erhalten begründete Ausnahmen, etwa `/proc`, GVFS,
Secret Service, FIFO, POSIX-Rechte und Symlink-Erstellung ohne Windows-Recht.
Diese Ausnahmen sind kein bestandener Windows-Nachweis. Die Windows-Adapter
haben eigene Tests und die oben beschriebenen Live-Prüfungen.

Der vollständige Ubuntu-24.04-Lauf hat **397 Tests bestanden** und das Linux-Paket
gebaut (CI-Lauf 38521261807, Commit `15b3c56`). Der vollständige lokale Windows-Lauf besteht
**394 Tests mit 47 begründeten Ausnahmen**. Der abschließende Prüfstand und
die installierte Version stehen in [TESTING.md](TESTING.md).

Für zuverlässigen Google-Zugriff benötigt der Herausgeber eine zugelassene eigene
Desktop-OAuth-Registrierung, die der vorhandene Build bereits einbetten kann.
Endbenutzer melden sich dann weiterhin ausschließlich im Browser an; eine eigene
Google-Cloud-Anwendung pro Benutzer ist nicht das gewünschte Produktmodell.
Ohne eine solche bereitgestellte Registrierung kann die Windows-Portierung die
Quota des gemeinsamen rclone-Projekts nicht reparieren. Hintergrund:
[rclone Google Drive](https://rclone.org/drive/#making-your-own-client-id).
