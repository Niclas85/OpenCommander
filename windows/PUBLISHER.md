# Google-Herausgeberanbindung für OpenCommander Desktop

Stand: 14. Oktober 2026. Die Cloud-Konsole ist zur Anmeldung geöffnet.
Auf diesem Windows-Computer liegt noch kein offizieller Desktop-Client-Export
vor. Eine neue Registrierung oder öffentliche Google-Verifizierung ist damit
noch nicht abgeschlossen. Die Release-Unterlagen erwähnen ein bereits erstelltes
OpenCommander-Projekt im Testmodus; dieses zuerst prüfen und wiederverwenden.

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
6. Den offiziellen Desktop-Client-JSON-Export außerhalb des Repositorys speichern.
   Nicht in Chats, Issues oder Git einfügen. Build und Normalisierung übernehmen
   nur die Desktop-App-Identität; Konto-/Refresh-Tokens werden abgewiesen.

Für öffentliche Nutzung sind eine tatsächlich erreichbare Homepage und eine
zutreffende Desktop-Datenschutzerklärung nötig. Der bestehende Linux-Entwurf
beschreibt Windows-NTFS-Rechte noch nicht und ist bislang kein bestätigter
öffentlicher OAuth-Endpunkt. App-Herausgeber, Kontakte und Domain-Zugriff müssen
zum verwendeten Google-Cloud-Projekt passen. Google entscheidet über die
Marken-/Scope-Verifizierung; eine lokale Einrichtung ersetzt diese Prüfung nicht.

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
[Google-Verifizierung eingeschränkter Scopes](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification),
[rclone Google Drive](https://rclone.org/drive/#making-your-own-client-id).
