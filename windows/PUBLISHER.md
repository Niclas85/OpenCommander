# Google-Herausgeberanbindung für OpenCommander Desktop

Stand: 14. Oktober 2026. Das vorhandene Projekt `opencommander-511504`
und der native Client „OpenCommander Linux Desktop“ werden für beide Desktop-
Plattformen verwendet. Ein zusätzlicher Clientschlüssel wurde mit ausdrücklicher
Bestätigung des Herausgebers erstellt; der bisherige Schlüssel bleibt aktiv.
Der JSON-Download der Konsole lieferte keine Datei. Deshalb wurde die neue,
sichtbare App-Identität als Desktop-JSON außerhalb des Repositorys gespeichert,
gegen die Konsole geprüft und mit privaten Windows-NTFS-Rechten geschützt.
Dies ist kein heruntergeladener offizieller Export. Persönliche Tokens sind
getrennt im privaten Benutzerprofil gespeichert.

Die Browseranmeldung mit dieser Identität, 256-KiB-Dateizugriff, Helfer,
persistentes Rückgängig und anonyme Freigabelinks wurden praktisch bestätigt.
Das vorhandene Google-Profil wurde umgestellt; die übrigen Provider bleiben erhalten.

**Produktionsmodus und Branding veröffentlicht; Drive-Prüfantrag eingereicht.**
Die Zielgruppe ist External, der Veröffentlichungsstatus „In Produktion“.
Google hat das Branding geprüft; die Konsole bestätigt, dass es Nutzern angezeigt
wird. Das ist noch keine Genehmigung des eingeschränkten Drive-Scopes.
Bis zur Scope-Genehmigung gelten Warnhinweise und die Obergrenze von 100 Nutzern.
Eine Umstellung auf Produktion ist kein Nachweis, dass bereits im Testmodus
ausgestellte Tokens eine andere Laufzeit erhalten haben.

Homepage https://opencommander.top/ und Datenschutz
https://opencommander.top/privacy sind öffentlich per HTTPS erreichbar.
Domain und DNS werden bei Dynadot verwaltet; die statischen Seiten liegen bei
OpenAI Sites und werden über Cloudflare ausgeliefert. Es wurde kein gesonderter
kostenpflichtiger Hosting-Tarif gebucht und kein neuer Vertrag angenommen.
Sites ist während der öffentlichen Beta in berechtigten ChatGPT-Abos enthalten.
Eine dauerhafte kostenlose Bereitstellung oder der Weiterbetrieb nach Kündigung
des Abos ist dadurch nicht zugesichert.

Sites-Projekt: `appgprj_6acfd14405848191826b2e20926fe64d`, öffentliche Version 2,
Quellstand `e6583f7694cec722c6594f4ff64f295a9867c2ff`.
Die vier statischen Quelldateien sind zusätzlich in `release/linux/site` gesichert
und lassen sich auf unabhängiges Hosting übertragen.
Die fünf vorbereiteten DNS-Einträge wurden mit ausdrücklicher Bestätigung
gespeichert: zwei Apex-A-Einträge, Google-Inhaberschafts-TXT sowie Sites- und
Zertifikats-TXT. Google Search Console bestätigt die Domaininhaberschaft.
Homepage-/Datenschutz-URLs und autorisierte Domain sind in Google gespeichert.

**Drive-Prüfung läuft:** Kategorie „Drive-Produktivität“, Scope-Begründung und
YouTube-Demovideo sind gespeichert. Das 118 Sekunden lange Video ist nach
ausdrücklicher Freigabe einschließlich YouTube-Zustimmung auf „Nikki Haenggi“
als **Nicht gelistet** veröffentlicht: https://youtu.be/LQkSLbaxRpg . Es zeigt
eine kommentierte Schrittfolge aus echten Browser-/App-Aufnahmen mit Anmeldung,
Drive-Scope, Lesen, Upload, Download, Umbenennen und Rückgängig an synthetischen
Dateien. Kontoangaben und lokale Profilpfade sind verdeckt.
Der vollständige Antrag wurde am 14. Oktober 2026 eingereicht. Google bestätigt
den Eingang beim Trust-and-Safety-Team und zeigt den Datenzugriff als „wird
überprüft“. Das bereits autorisierte Testkonto und die Art der Aufnahme sind
im Antrag ausdrücklich erläutert. Die Anerkennung des Videos und die Freigabe
des eingeschränkten Scopes bleiben Googles Entscheidung.
Die Kenntnisnahme der jährlichen CASA-Sicherheitsbewertung im Fragebogen ist
protokolliert; eine Bewertung oder Zahlung wurde nicht beauftragt.

## Registrierung prüfen und abschließen

1. Im Herausgeberkonto die Google-Cloud-Konsole öffnen und das vorhandene
   OpenCommander-Projekt auswählen. Nicht auf ein fremdes Projekt ausweichen.
2. Google Drive API muss aktiviert sein. In Google Auth Platform Marke,
   Zielgruppe, Datenzugriff und vorhandene Clients prüfen.
3. App-Name OpenCommander; für Windows und Linux einen nativen Desktop-OAuth-Client
   verwenden. Kein Web-Client und kein Service-Account-Schlüssel.
4. Für vollständige Dateiverwaltung ist ausschließlich der Drive-Scope
   `https://www.googleapis.com/auth/drive` erforderlich. Dieser erlaubt die vom
   Benutzer ausgelösten Datei-, Wiederherstellungs- und Freigabeaktionen.
   Benutzer stimmen dem Zugriff selbst im Systembrowser zu.
5. Für die erste Abnahme das eigene Konto als Testnutzer eintragen. Das ist
   keine öffentliche Freigabe. Neue Clients, zusätzliche Zugriffsrechte und
   rechtliche Zustimmungen erst nach konkreter Bestätigung speichern.
6. Den Desktop-Client-JSON-Export außerhalb des Repositorys speichern.
   Nicht in Chats, Issues oder Git einfügen. Build und Normalisierung übernehmen
   nur die Desktop-App-Identität; Konto-/Refresh-Tokens werden abgewiesen.

Die öffentliche Homepage und Datenschutzerklärung sind abgenommen. Der
Herausgeber, die Kontaktadressen und die bestätigte Domain bleiben dem bestehenden
Google-Projekt zugeordnet. Google entscheidet über die Scope-Genehmigung;
erfolgreiche lokale Dateitests und die Branding-Freigabe ersetzen diese Prüfung
nicht. Die Vorbereitung des Videonachweises steht in
[GOOGLE-VERIFICATION.md](GOOGLE-VERIFICATION.md).

## Windows-Paket mit verpflichtender Herausgeberanbindung

```powershell
$env:OPENCOMMANDER_GOOGLE_OAUTH_FILE = 'C:\privater-pfad\google-desktop.json'
.\windows\build.ps1 -RequirePublisherGoogle
```

Ohne Export stoppt dieser Build. Die Paketprüfung verlangt anschließend die
bereinigte Identität in `_internal/opencommander/assets/google-oauth.json` und
weist zusätzliche Datenfelder zurück. Desktop-Client-ID und Desktop-Client-Secret
identifizieren die native App; persönliche Benutzer-Tokens bleiben im privaten
Benutzerprofil. Den geheimen Quellexport nicht mit dem fertigen Paket verteilen.

Der normale Entwicklungs-/CI-Build bleibt ohne Herausgeber-Export möglich und
ist dadurch kein Nachweis einer funktionierenden öffentlichen Google-Anmeldung.

## Installation und reale Abnahme

- Paketsmoke und Publisher-Prüfung bestehen lassen, dann die neue App installieren.
- Die bestehende Google-Verbindung auf die Herausgeberanmeldung umstellen;
  der Benutzer erteilt neue OAuth-Zustimmung im Browser. Ein Token der gemeinsamen
  rclone-Anwendung kann nicht als Token der neuen Anwendung wiederverwendet werden.
- Alte Google-Einbindung nach Abschluss laufender Dateiaktionen ordentlich
  trennen und mit der neuen Identität verbinden. Andere Provider erhalten.
- Auflisten, synthetischen Upload, bytegenaues Lesen, Umbenennen, Rückgängig,
  anonymen Freigabelink, eigene Testbereinigung und erneuten App-Start prüfen.
- Erst nach realer Abnahme Google in TESTING/PARITY als stabil bestätigt markieren.
  Testmodus und öffentliche Verifizierung getrennt protokollieren.

Quellen: [Google Desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app),
[Google OAuth-Testmodus und Token-Laufzeit](https://developers.google.com/identity/protocols/oauth2#expiration),
[Google-Verifizierung eingeschränkter Scopes](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification),
[rclone Google Drive](https://rclone.org/drive/#making-your-own-client-id).

Hosting: [Sites-Verfügbarkeit und Limits](https://learn.chatgpt.com/docs/sites?surface=web), [Sites-Preise in der Beta](https://learn.chatgpt.com/docs/pricing#how-much-does-sites-cost).
