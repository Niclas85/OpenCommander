# Cloud-Anmeldung für öffentliche Linux-Pakete

Alle Benutzer verbinden ihr eigenes Konto. Die Herausgeber-Konfiguration enthält
nur die App-Identität, niemals ein Benutzerpasswort oder Konto-/Refresh-Token.
Bestehende Verbindungen werden durch einen Build nicht verändert. Vor einem
Wechsel aktiver Einbindungen Kopiervorgänge sicher pausieren und speichern.

## Microsoft / OneDrive

In Microsoft Entra eine App **OpenCommander** registrieren:

- Unterstützte Konten: organisatorische Konten aus mehreren Verzeichnissen und
  persönliche Microsoft-Konten.
- Plattform **Mobile and desktop applications**, Rückleitung
  `http://localhost:53682/`. Keine Web-/Daemon-App und kein Client-Secret erzeugen.
- Delegierte Microsoft-Graph-Berechtigungen: `Files.ReadWrite.All`, `User.Read`,
  `offline_access`. Keine Application-Berechtigungen und kein tenantweiter
  Administratorzugriff. Der Zugriff erfolgt immer als angemeldeter Nutzer.
- Die normale Dateiansicht benötigt keine Suche über alle SharePoint-Sites;
  diese zusätzliche Berechtigung wird nicht angefragt. Firmenrichtlinien können
  trotzdem Administratorzustimmung bzw. einen verifizierten Herausgeber verlangen.
- Öffentliche Homepage, Datenschutz-URL und Herausgeberverifizierung vor der
  allgemeinen Freigabe vorbereiten; kein bezahltes Azure-Abo für die App buchen.

Die öffentliche Application-ID in eine private Kopie der Beispieldatei einsetzen.
Beim Build `OPENCOMMANDER_ONEDRIVE_OAUTH_FILE` auf diese Datei setzen.

## Dropbox

In der Dropbox App Console **Scoped access**, **Full Dropbox**, **OpenCommander**
einrichten. Full Dropbox ist für die vom Benutzer ausgewählte Dateiverwaltung
nötig; App folder würde nur einen eigenen App-Unterordner zugänglich machen.

- User-Scopes: `account_info.read`, `files.metadata.read`, `files.metadata.write`,
  `files.content.read`, `files.content.write`, `sharing.read`, `sharing.write`.
- Rückleitung `http://localhost:53682/`.
- Die aktuelle Dropbox-Konsole fasst „Implicit Grant & PKCE“ unter
  „Allow public clients“ zusammen; dieser Schalter muss für PKCE auf Allow bleiben.
  OpenCommander nutzt ausschließlich Authorization Code mit PKCE/S256 und
  Offline-Refresh-Token, keinen Implicit Grant. Keine Team-/Mitglieder-Verwaltung.
- App-Key in eine private Kopie der Beispieldatei einsetzen. Das **App secret
  wird nicht benötigt und darf nicht im öffentlichen Paket liegen**.
- Beim Build `OPENCOMMANDER_DROPBOX_OAUTH_FILE` setzen.
- Entwicklung und Produktionsprüfung sind getrennte Schritte. Vor öffentlicher
  Nutzung Dropbox-Produktion beantragen und Kontoabnahme durchführen.

## Google / iCloud / Server

Google verwendet die bereits vorbereitete Desktop-App-Konfiguration über
`OPENCOMMANDER_GOOGLE_OAUTH_FILE`; öffentliche Google-Verifizierung steht aus.
iCloud nutzt persönliche Apple-ID, reguläres Passwort und Geräte-/SMS-Code im
Assistenten. Es gibt dafür keinen gemeinsamen Apple-Kontozugang. FTP/FTPS/SFTP
und NAS benötigen persönliche Server-Zugangsdaten, keine zentrale OAuth-App.
SFTP prüft Hostschlüssel; FTPS prüft TLS-Zertifikate. Server-Passwörter werden auf
Wunsch im Linux-Schlüsselbund gespeichert, sonst nur für die Sitzung gehalten.

## Paket bauen und prüfen

```sh
OPENCOMMANDER_GOOGLE_OAUTH_FILE=/private/google-desktop.json \
OPENCOMMANDER_ONEDRIVE_OAUTH_FILE=/private/onedrive-public.json \
OPENCOMMANDER_DROPBOX_OAUTH_FILE=/private/dropbox-public.json \
./linux/build.sh

python3 release/linux/check-package.py linux/artifacts/OpenCommander-linux-x86_64.tar.gz \
  --require-publisher google --require-publisher onedrive --require-publisher dropbox
```

Die Beispieldateien enthalten absichtlich ungültige Platzhalter. Die Strukturprüfung
ersetzt weder einen echten Login noch die Prüfung von Neustart/Token-Erneuerung
mit getrennten Benutzerkonten.

## Abnahme pro Dienst

1. Frisches isoliertes App-Profil: Browser bzw. Apple-Assistent startet, Abbruch
   und verweigerte Zustimmung reagieren ohne GUI-Blockade.
2. Mit eigenem Testkonto verbinden, Liste lesen, App schließen und erneut öffnen.
3. Zweites Konto separat verbinden; Profile und Berechtigungen bleiben getrennt.
4. Kleine ausdrücklich eigene Testdatei kopieren, umbenennen, teilen, zurücknehmen.
   Lösch-/Aufräumaktionen nur auf dem exakt selbst erstellten Testobjekt durchführen.
5. Abgelaufener Token, offline, Quotenfehler und Firmen-Sperre müssen verständlich
   gemeldet werden; kein stiller Kontowechsel und keine endlose Ladeanzeige.
6. Anmeldung bearbeiten: bisherige Verbindung bis zur erfolgreichen neuen
   PKCE-Zustimmung behalten; eigene frühere Client-IDs nicht still ersetzen.
7. Aktiven Transfer pausieren/fortsetzen; fertige Dateien nicht erneut kopieren.
   Keine produktiven Mounts für Tests neu starten.

Quellen:
- https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration
- https://docs.dropboxapi.com/dropbox-api/docs/oauth
- https://rclone.org/onedrive/
- https://rclone.org/iclouddrive/
