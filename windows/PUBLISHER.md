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

**Öffentliche Freigabe bleibt offen:** Zielgruppe External, Status Test.
Nur eingetragene Testnutzer können sich anmelden; Google begrenzt im Testmodus
die Refresh-Token-Laufzeit auf sieben Tage. Eine erneute Browseranmeldung kann
danach erforderlich sein. Dies ist keine dauerhaft verifizierte öffentliche App.
Der Benutzer hat `opencommander.top` gewählt, hat aber noch keinen Hosting-Zugang.
Die Domain lieferte bei der Prüfung keine funktionierende HTTPS-Seite.
Homepage, Datenschutzerklärung und bestätigte Domain fehlen daher weiterhin in
der Google-Konsole. Es wurde keine unzutreffende URL eingetragen oder öffentliche
Freigabe beantragt.

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

Für öffentliche Nutzung sind eine tatsächlich erreichbare Homepage und eine
zutreffende Desktop-Datenschutzerklärung nötig. Der bestehende Website-Entwurf
beschreibt jetzt auch Windows-NTFS-Rechte und die Anmeldeinformationsverwaltung,
ist aber weiterhin kein bestätigter öffentlicher OAuth-Endpunkt.
App-Herausgeber, Kontakte und Domain-Zugriff müssen
zum verwendeten Google-Cloud-Projekt passen. Google entscheidet über die
Marken-/Scope-Verifizierung; eine lokale Einrichtung ersetzt diese Prüfung nicht.

Für `opencommander.top` sind als nächste Schritte Hosting und Domain-Verwaltung
bereitzustellen, eine gültige HTTPS-Konfiguration einzurichten und die Homepage
sowie eine für Windows und Linux zutreffende Datenschutzerklärung zu veröffentlichen.
Der vorhandene Desktop-Entwurf liegt weiterhin in `release/linux/site` und wurde
um Windows-NTFS-DACLs und Windows-Anmeldeinformationen ergänzt. Anbieterangaben
und Veröffentlichungsinhalt müssen vor der öffentlichen Freigabe geprüft werden.
Erst anschließend Domain-Eigentum bestätigen, die erreichbaren URLs in Google
Auth Platform speichern und die Marken-/Drive-Scope-Verifizierung einreichen.
Es wurden kein kostenpflichtiges Hosting gebucht und keine neuen Verträge angenommen.

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
