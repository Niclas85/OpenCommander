# OpenCommander Linux – öffentliche Testversion (Entwurf)

Noch nicht freigegeben. Versionsnummer und Download werden vor Freigabe finalisiert.

- Zwei Dateibereiche mit Ordnerbaum, Drag & Drop und Kopieren-/Verschieben-Schalter.
- Dateivorschau, Archive, Kontextmenüs, Eigenschaften und „Öffnen mit“.
- Gespeicherte Übertragungen mit Fortschritt, Pause, Wiederaufnahme und Fehlerdetails.
- Helles/dunkles Design, sortierbare Orte und Anbieter-Icons.
- Lokale und eingebundene Netzwerk-/Cloud-Orte; Cloud-Zugriff freiwillig.
- Quellcode, Lizenzhinweise, Offline-Handbuch und Testplan im Paket.

Erstprüfung: Ubuntu 24.04, x86_64. ARM64 und andere Distributionen noch nicht
vollständig abgenommen. Direkte Cloud-Verbindungen bleiben experimentell bis
zur Konto-/Dauerlauf-Abnahme. Gemeinsame Google-Anmeldung wird durch den Herausgeber
vorbereitet; öffentliche OAuth-Freigabe fehlt noch. iCloud benötigt Apple-ID,
reguläres Passwort, Geräte-/SMS-Code und erlaubten iCloud-Web-Zugriff.

Installation: Paket entpacken und `install-local.sh` aus dem entpackten Ordner
starten. Für Online-Einbindungen werden FUSE und eine Netzwerkverbindung benötigt.
Die Anmeldung kann eine private aktuelle rclone-Version herunterladen.

Dies ist eine Testversion, keine Zusicherung fehlerfreier Cloud-Dateioperationen.
Fehlerberichte bitte mit Version, Betriebssystem und anonymisiertem Fehlertext;
keine Passwörter, Tokens oder privaten Dateien in öffentliche Issues hochladen.
