# Linux-Abgleich mit dem Mac-Paritätsbranch

Referenz: `codex/mac-linux-parity`, `2f96726e07ccd687e825740c71ab255bb023ca3f`,
abgerufen am 10.10.2026. Die letzten beiden Commits ergänzen Commander-Werkzeuge,
Historienansicht und FTP/FTPS/SFTP samt Online-Werkzeugen. Frühere Commits ergänzen
Orte-Einstellungen, OneDrive-Online und Desktop-Bedienung. Linux übernimmt die
benutzbaren Funktionen mit Linux-Backends, nicht den Swift-/AppKit-Code.

| Funktion | Linux 0.3.20 | Prüfung / Unterschied |
| --- | --- | --- |
| ZIP/TAR/TGZ/7z/RAR öffnen und entpacken | libarchive, sichere Prüfung und Undo | TAR/7z-Roundtrips, echtes RAR5-Fixture, Traversal-/Link-/Spezialdatei-Ablehnung |
| Zwei Bereiche, Baum, Sortierung, Filter, Navigation | Vorhanden, auch für Online-Mounts | Bestehende UI-Tests |
| Kopieren-/Verschieben-Umschalter, Drag-and-drop, Zwischenablage | Vorhanden | Bestehende Transfer-/UI-Tests |
| Bilder/Video/Audio und Navigation | Vorhanden; zusätzliche Papierkorb-Aktion | Vorschau-Löschen, Abbruch und Wiederherstellung getestet |
| Öffnen mit, Eigenschaften, USB | Linux-GTK/GIO statt AppKit | Bestehende Host-/Eigenschaftentests |
| Suche, Pfadwechsel, Unicode, Muster, Groß-/Kleinschreibung | Neu, Strg-F | Grenzen/Links/Hidden/Abbruch getestet |
| Ordnervergleich mit Inhalt | Neu, Strg-Alt-C | Gleich große unterschiedliche Dateien getestet |
| Mehrfach-Umbenennen, Zähler, Vorschau, Rücknahme | Neu, Strg-Umschalt-M | Veraltete Vorschau, Kollision, Teilfehler und persistente Rücknahme getestet |
| Kopieraufträge pausieren und nach Neustart fortsetzen | Private persistente Warteschlange und geprüfte Zwischenstände | Lokale Prozess-/Desktop-Tests; Netzwerkzugriffe können Abbruch verzögern |
| Orte hinzufügen, umbenennen, ausblenden, umsortieren | Einstellungen, Dienstsymbole, Drag & Drop oder Rechtsklick; gespeicherte Reihenfolge | Präferenz-/Sprachtests, Persistenz, fehlende Orte, keine Aktivierung beim Ziehen |
| Kompakte Historie und Info-Schaltfläche | Neu | Rücknahme und Detaildaten bleiben erhalten |
| Online-Ladeanzeige / Abbruch | Pane-Ladebalken, Verbindungs-/Konfigurationsanzeige, Transferanzeige | Verzögerte/alte Ergebnisse getestet; Byteanzeige beim Kopieren |
| OneDrive ohne lokalen Sync-Client | Neuer rclone-Einrichtungsassistent und FUSE-Mount | Konfigurationsprotokoll ohne Konto getestet; keine echte Microsoft-Anmeldung |
| FTP, explizites FTPS, SFTP | Serverformular mit Passwort/Key/Agent, optional Secret Service, FUSE-Mount | Echter lokaler SFTP-Test für drei Anmeldearten; TLS-/Hostkey-Schutz getestet, keine persönlichen FTP/FTPS-Server |
| Online-Suche/Vergleich/Umbenennen/ZIP/Vorschau/Transfers | Gleiche Linux-Werkzeuge auf eingerichteten Mounts | Isolierter echter rclone/FUSE-Test; kein vollständiger Protokolltest gegen FTP/FTPS/SFTP/Graph |
| Google Drive, Dropbox, iCloud | Vorhandene Mounts/Sync-Ordner plus Online-Assistent | iCloud benötigt rclone mit passendem Backend; Benutzeranmeldung erforderlich |

## Grenzen, die keine identische Portierung darstellen

- Linux benutzt rclone/FUSE statt des Mac-Graph-Clients. Graph-spezifische bedingte
  Lösch-/Versionsanforderungen werden nicht gleichwertig nachgebildet. Die eigene
  Wiederherstellungskopie ersetzt nicht den OneDrive-Web-Papierkorb.
- Konfigurierte app-eigene sowie erkannte externe fuse.rclone-Mounts verwenden eine auf Zielbelegung
  prüfende Umbenennung statt `RENAME_NOREPLACE`. Andere Clients können trotzdem
  zwischen Prüfung und Umbenennung schreiben. Kein automatischer Sync-Modus.
- Die private Konfiguration hat Rechte 0600, aber keine Keychain-Verschlüsselung.
  Konfigurationsantworten/State werden nur im Kindprozess-Environment übergeben.
  Konfigurationsfehler werden ohne mögliche Credential-Fragmente angezeigt.
- Linux bietet eine eigene SSH-Fingerprint-Anzeige über `ssh-keyscan`/`ssh-keygen`,
  mit ausdrücklicher Bestätigung erst nach unabhängigem Vergleich. Bestehende
  geänderte Schlüssel werden nicht hinzugefügt. Linux/rclone verlangt geprüfte
  `known_hosts`; die Mac-Askpass-Komponente ist nicht erforderlich. Zertifikats-/
  Hostkey-Prüfung wird nicht deaktiviert.
- Ein aktuelles rclone wird bei Bedarf app-intern geladen und anhand der offiziellen
  SHA-256-Prüfsumme geprüft. System-rclone und vorhandene Mounts bleiben unverändert.
  Benutzerkonten werden nicht automatisch angemeldet. OneDrive startet Browser-OAuth;
  iCloud verwendet Apple-ID/Passwort/2FA. Browserlogin allein reicht dort nicht.
- Remote-Listings sind begrenzt und abbrechbar. Einzelne blockierende Dateisystem-
  Lese-/Schreibaufrufe während Inhaltsprüfung/Transfer können einen Abbruch verzögern.
- iOS-Fotobibliothek, Android-Launcher-Artwork, AppKit-/Quick-Look-/NTFS-Komponenten
  sind plattformspezifisch und keine Linux-Desktop-Funktionen.

Quellstand, Installation, Sicherheitsmodell und genaue Bedienung: [README](README.md).
Backend-Dokumentation: [rclone-Konfigurationsprotokoll](https://rclone.org/commands/rclone_config_create/),
[Mount](https://rclone.org/commands/rclone_mount/), [OneDrive](https://rclone.org/onedrive/).


Nachtrag 0.3.3: Online-Bild-Thumbnails und sequenzielle JPG-Vorschau ergänzt;
Transferanzeige um Prozent/Datenmenge/Dateien/Zeit erweitert, Darkmode-Checkbox
sichtbar. Provider-Umbenennung unterstützt erkannte externe fuse.rclone-Mounts.
