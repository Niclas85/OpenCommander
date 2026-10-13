# Linux-Veröffentlichung – Vorbereitung, keine Freigabe

Stand: 13. Oktober 2026. Ziel: öffentliche Linux-Testversion; macOS behält seinen
bestehenden separaten Vorschau-Release. Es wird kein GitHub-Release veröffentlicht,
kein Tag erzeugt, keine produktive Einbindung neu gestartet.

## Anbieterstatus der Vorbereitung 0.3.25rc3

| Dienst | App-Umsetzung | Externe Einrichtung / reale Abnahme |
| --- | --- | --- |
| Google Drive | Gemeinsame Desktop-Identität, Browser-Assistent, eigenes Benutzerprofil | Eigene App im Testmodus und ein Testkonto vorhanden; echter Login und öffentliche Verifizierung offen |
| OneDrive | Öffentliche App-ID, PKCE/S256, gespeicherte Tokens, persönliche/Firmen-Laufwerkswahl | Microsoft-Herausgeber-Konsole benötigt Anmeldung; Registrierung und echter PKCE-/Refresh-Test offen |
| Dropbox | Öffentlicher App-Key, PKCE/S256, Offline-Token, gespeichertes Benutzerprofil | App im Entwicklungsmodus erstellt; bestätigte Datei-/Freigabe-Scopes und localhost-Rückleitung gespeichert. Echte persönliche Anmeldung und PKCE-/Refresh-Test noch laufend |
| iCloud | Schrittweiser Apple-ID-/Passwort-/Geräte-/SMS-Assistent, privates Profil | Echtes Apple-Konto mit Bestätigung und Wiederanmeldung weiterhin offen |
| FTP/FTPS/SFTP | Persönliche Server-Anmeldung, Schlüssel/Agent, optional Linux-Schlüsselbund | Bestehende Konfigurations-/Anmeldemodi gezielt geprüft; vollständige externe Servermatrix offen |
| NAS/SMB | Vorhandene Systemeinbindung mit persönlichen NAS-Zugangsdaten | Keine zentrale OAuth-App nötig; öffentliche Plattformmatrix weiterhin offen |

Die unterstützten Anmeldewege sind implementiert. Eine vollständige öffentliche
Freigabe oder Abnahme aller Kontotypen ist damit noch nicht erfolgt.

## Gemeinsame Google-Anwendung

Einmalig durch den Herausgeber im Codex-Browser einzurichten:

1. Eigenes Google-Cloud-Projekt für OpenCommander; bestehende Projekte unverändert lassen.
2. Google Drive API aktivieren. Google Auth Platform mit Marke OpenCommander,
   Supportkontakt, öffentlich erreichbarer Homepage und Datenschutzerklärung einrichten.
3. Zielgruppe Extern, Desktop-OAuth-Client. Während der Vorbereitung nur Testnutzer.
4. Nur benötigten Drive-Zugriff beantragen. Vollständige Dateiverwaltung benötigt
   `https://www.googleapis.com/auth/drive`; das ist ein eingeschränkter Scope.
   Vor öffentlicher Nutzung Googles Marken-/Scope-Verifizierung und Quoten prüfen.
5. Google-Desktop-Client-JSON außerhalb des Repos speichern. Kein Web-Client,
   Service-Account-Schlüssel, Apple-Passwort, Zugriffs- oder Refresh-Token im Paket.
6. Build über `OPENCOMMANDER_GOOGLE_OAUTH_FILE` starten. Der Build übernimmt
   ausschließlich Desktop-Client-ID und zugehörige Desktop-Client-Konfiguration.
   Diese identifizieren die native App; Benutzer-Tokens bleiben lokal pro Benutzer.

```sh
OPENCOMMANDER_GOOGLE_OAUTH_FILE=/absoluter/privater/pfad/desktop-client.json ./linux/build.sh
```

Mit gebündeltem Client bietet der App-Assistent direkt „Mit Google im Browser
anmelden“. Client-ID-/Console-Einrichtung entfällt für Endnutzer. Explizite bzw.
bereits konfigurierte eigene OAuth-Anwendungen werden beim erneuten Anmelden
bewahrt. Ohne Herausgeber-Client bleibt der bisherige private Expertenweg erhalten;
das ist noch keine allgemein freigegebene Google-Anmeldung.

Quelle: https://developers.google.com/identity/protocols/oauth2/native-app
Verifizierung: https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
Testmodus/Tokenlaufzeit: https://developers.google.com/identity/protocols/oauth2

## iCloud für jeden Benutzer

Keine gemeinsame Apple-Anmeldung. Jeder Benutzer gibt im App-Assistenten seine
Apple-ID, sein reguläres Passwort und seinen Geräte-/SMS-Code ein. Web-Datenzugriff
in den Apple-Einstellungen erforderlich; app-spezifische Passwörter ungeeignet.
Passwörter, Cookies und Tokens werden in seinem lokalen Profil (Verzeichnis 0700,
Konfiguration 0600) gespeichert; rclone-Passwortkodierung ist keine Schlüsselbund-
Verschlüsselung. Die Sitzung kann eine erneute Gerätebestätigung benötigen.

Quelle: https://rclone.org/iclouddrive/

## Vor Freigabe konkret offen

- Eigene OneDrive-/Dropbox-Registrierungen abschließen. Die App unterstützt
  öffentliche Client-IDs mit PKCE/S256 ohne Server-Secret; Anleitung und ungültige
  Platzhaltervorlagen unter [oauth/](oauth/README.md). Google-/Dropbox-Identitäten
  sind für den nächsten lokalen Kandidaten eingerichtet. Microsoft-Identität fehlt
  noch. iCloud/Server verwenden persönliche Zugangsdaten.
- Öffentliche Google-Freigabe abschließen. Herausgeber-Desktop-Client und lokales
  Paket sind vorbereitet; ein Projekt oder Testnutzer ersetzt diese Freigabe nicht.
- Mit zwei getrennten Google-Testkonten prüfen: Anmeldung, Neustart, getrennte
  Dateilisten, Abmeldung/Widerruf, Kopieren und Wiederaufnahme; Quotenfehler sichtbar.
- iCloud mit echtem Apple-Konto und Bestätigung sowie erneutem App-Start prüfen.
- Öffentlich erreichbare Linux-Datenschutzerklärung bereitstellen; bestehende
  Mobil-Datenschutzerklärung deckt direkte Linux-Cloud-Verbindungen nicht ab.
- Download als experimentelle Testversion kennzeichnen; Kompatibilität bisher
  Ubuntu 24.04 x86_64. Andere Distributionen, ARM64 und macOS nicht mitabnehmen.
- Finales Paket auf Kontokonfigurationen, Journale, Schlüssel und persönliche
  Protokolle prüfen. Lizenztexte, Source, Prüfsumme und Installation beilegen.
- Erst nach ausdrücklicher Freigabe ein GitHub-Release und öffentliches Tag erzeugen.

## Vorhandene Prüfnachweise

0.3.24: 338 automatisierte Tests und Paket-Smoke-Test bestanden. Einzelne
Google-Datei mit direktem Server-SHA-256 erfolgreich lesend geprüft. Keine vollständige
Cloud-Dauerlauf-Abnahme. Siehe linux/TESTING.md. Kleine Folgeänderungen gezielt prüfen;
keine vollständige Suite nach jeder Text- oder Formularänderung.

## Paketprüfung ohne Ausführen

```sh
python3 release/linux/check-package.py linux/artifacts/OpenCommander-linux-x86_64.tar.gz
# Vor einer öffentlichen Version mit zentraler Google-Anmeldung:
python3 release/linux/check-package.py linux/artifacts/OpenCommander-linux-x86_64.tar.gz --require-publisher-google
```

Die Prüfung extrahiert und startet keine Dateien. Sie kontrolliert Paketpfade,
Links, notwendige Distributionsdateien und verbotene Konto-/Signierungsdateien.
Der Google-Schalter bestätigt nur die Anwesenheit der App-Identität; er ersetzt
keine Google-Verifizierung und keinen echten Anmeldungstest.

## Stand der Publisher-Einrichtung

Separates Cloud-Projekt und Drive API wurden im Codex-Browser eingerichtet.
Die Marke OpenCommander ist mit Zustimmung zur Google-Nutzerdatenrichtlinie
im Testmodus gespeichert. Ein nativer Desktop-Client wurde erstellt und die
einzige Berechtigung `https://www.googleapis.com/auth/drive` mit Zustimmung
gespeichert. Die Zielgruppe ist Extern, der Status Test; ein bestätigtes Testkonto ist eingetragen.
Das lokale Paket 0.3.25rc1 enthält die gemeinsame Desktop-App-Identität und hat
Paket-Smoke-Test sowie strukturelle Publisher-Prüfung bestanden. Dies erteilt
der App allein noch keinen Zugriff auf Benutzerdateien.
Vor einer tatsächlichen Kontoanmeldung ist die persönliche OAuth-Zustimmung
des Kontoinhabers erforderlich. Es bleibt bei einer Vorbereitung ohne Release.
