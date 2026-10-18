# Mac-Abnahme — 18. Oktober 2026

Referenz erneut abgerufen: `origin/codex/linux-desktop` bei
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`. Die Linux-CI dieses Stands
ist erfolgreich (Run 38872779010, Linux-Job 116880586373: 411 Tests bestanden).
Das ist kein Ersatz für die native Mac-Abnahme der 158 manuellen Referenzfälle.
Die Einzelzuordnung steht in `mac-linux-acceptance-ledger-2026-10-18.json`.

## Behobene Softwarefälle

- **Ordnernavigation:** Eine Ebene hoch markiert den verlassenen Unterordner und
  scrollt zu ihm. Der native Test mit 80 Unterordnern bestand per Schaltfläche
  und Command-Aufwärts. Die macOS-Aliasse `/tmp` und `/private/tmp` werden dabei
  verglichen, ohne gespeicherte Datei-Identitäten global zu verändern.
- **Orteleiste:** Umordnen per Maus, Kontextmenü und zugänglichen Aktionen.
  Versteckte Orte, eigene Namen und Bookmarks bleiben erhalten. Datei-Drags
  können keine Orte umordnen. Ein weiterer Negativtest entdeckte die
  Gegenrichtung: Ein Ort wurde im Dateifenster als Textdatei importiert.
  Statt öffentlichem Text nutzt der Orts-Drag jetzt ausschließlich eine private,
  prozesslokale Darstellung, die Dateiimporte explizit ablehnen. Die native
  Gegenprobe erzeugt damit keine Datei mehr; reguläres Umordnen funktioniert
  weiterhin. Die zunächst im Live-Test erkannte falsche
  Drag-End-Delegate-Methode ist korrigiert; Aktualisierung nach Loslassen,
  Escape, Neustart und Einhängen eines Testlaufwerks während des Drags geprüft.
- **Große Historie:** Höchstens 50 Einträge pro Seite, Neueste/Älteste sowie
  Vor-/Zurückblättern. Keine Kürzung gespeicherter Einträge; Undo verwendet
  weiterhin die ursprünglichen Indexnummern. Mit 1.022 Einträgen wurden erste
  und letzte Seite geprüft. In einem zweiten frischen Profil mit 1.000
  Einträgen wurde Undo auf der ältesten Seite tatsächlich ausgeführt:
  ausschließlich die zugehörige sichtbare Zieldatei verschwand; Quelle und
  Kontroll-Datei blieben exakt erhalten. Danach 999 Einträge, Rücksprung zur
  neuesten Seite erfolgreich. Die übrigen Seed-Einträge sind synthetische
  Audit-Daten ohne Undo; sie behaupten keine realen Cloud-Operationen.
- **Neue Ordner rückgängig:** Lokale Ordner werden mit Uhrzeit, Pfad und Undo
  protokolliert. Native Erstellung über das Flächen-Kontextmenü und Undo
  bestanden. Direkte Cloud-Ordner erhalten ebenfalls einen persistenten Undo-
  Nachweis. Automatisierte lokale und Cloud-Tests bestätigen Wiederherstellung
  nach Serialisierung und sichere Verweigerung, sobald später Inhalte
  hinzugefügt wurden. Der neue Cloud-UI-Aufruf wurde gebaut, aber nicht mit
  jedem echten Provider-Konto erneut ausgeführt.
- **Browser-Drags:** Safari lieferte eine versteckte temporäre
  `.com.apple.Foundation.NSItemProvider.…png`. Der Transfer war erfolgreich,
  aber die Datei dadurch unsichtbar. Solche Transportnamen werden nun zu
  sichtbaren `Dropped File.png`; echte Originale und absichtlich versteckte
  Namen bleiben unverändert. Safari und Chrome wurden mit einer eigenen
  lokalen HTML-Testseite geprüft; beide Ziele stimmen bytegenau mit dem
  synthetischen PNG überein. SHA-256:
  `6e17ddd487ce37d0c9e53f0b918ba3fc4639ffc21eaf15e039633cf1fbc5e327`.
  Explizites Verschieben einer reinen Browser-Kopie wurde korrekt abgelehnt:
  kein Original vorgetäuscht, nichts gelöscht. Das garantiert nicht die
  Übernahme beliebiger Inhalte jeder Fremdanwendung.

## Ausgeführte Prüfungen

Alle 14 regulären nativen Regressionstest-Skripte bestanden. Hinzu kommen
Datei-Provider-, Dateisicherheits-, isolierte NTFS- und echte lokale Server-
Tests. Zusammen 218 PASS-Gruppen in den datierten Logs, ohne den doppelten
Locations-Lauf mitzuzählen. Diese Gruppen sind keine 217 unterschiedlichen
Funktionen und keine vollständige manuelle Linux-Abnahme.

Wichtige Ergebnisse:

- Cloud-Clients: 57 Gruppen, einschließlich 22 separater Prozessphasen für
  Abbruch/Wiederaufnahme, Cloud-zu-Cloud-Verschieben und Rücknahme.
- OneDrive: 24 Gruppen; Datei-Sicherheit: 27; Datei-Provider: 15 Gruppen mit
  zusätzlich 32 Modifier-Policy-Kombinationen.
- 20 wiederhergestellte, explizit pausierte Aufträge wurden im Testfenster
  angezeigt und per „Resume all“ gestartet. Alle 20 Ziele sind exakt 65.536
  Bytes groß und entsprechen dem Quellhash
  `6229e62e16585b9f9e9ca939f053e9a1a831cf715e1f5ff5904a86bfa87a0b01`.
  Der erste Journal-Seed hatte `/tmp`-Symlinkvorfahren und wurde sicher
  abgelehnt; er zählt nicht als erfolgreicher Transfer. Der korrigierte Seed
  verwendet physische `/private/tmp`-Pfade.
- NTFS: neues, isoliertes Abbild bestand Engine-, Foundation-, Datei-/Baum-
  und vollständige Aus-/Einhänge-Wiederaufnahmetests. Abbild sauber ausgeworfen.
  Kein Zugriff auf Elements. Erster Versuch scheiterte am vollen Host-Datenträger;
  nach Bereinigung ausschließlich eigener Compiler-Caches bestand der Lauf.
- Echte Loopback-FTP-, FTPS-, SFTP-Schlüssel- und SFTP-Passwortserver bestanden
  Transfers, Fortschritt, rekursive Suche, Vergleich, Mehrfachumbenennung,
  Wiederherstellungs-Verschieben, Rollback, Abbruch und Authentifizierungsschutz.
- Vorschau, Dateieigenschaften und Einstellungen jeweils **50-mal** nativ
  geöffnet/geschlossen, mit Kontrolle des ausgewählten Testbilds, seiner
  Eigenschaften und Rückkehr zum Dateifenster. Kein Crash. Eine veraltete
  Steuerungs-ID nach Geräteänderung wurde im Testtreiber erkannt und durch
  erneute Ermittlung aus der sichtbaren Oberfläche ersetzt, nicht als
  Produktfehler gezählt. Unter Speicherdruck fehlgeschlagene Bildschirmaufnahme
  ebenfalls nicht als erfolgreich gezählt.

Ressourcen-Stichproben desselben Testprozesses: nach Aufwärmen 159, später
161 Zeilen in `lsof -Fn` (einschließlich geladener Bibliotheken, **nicht** nur
Dateideskriptoren); zuletzt fünf nummerierte Dateideskriptoren. Thread-
Stichproben 6–9; RSS unter stark wechselndem macOS-Speicherdruck ca. 10–90 MiB.
Kein pro Dialogzyklus wachsendes Handle-/Worker-Muster beobachtet. Das ersetzt
keine umfassende Heap-Analyse oder einen mehrstündigen Dauerlauf.

## Reproduzierbarkeit und Zustand

Logs: `ntfs/NTFS3G/.build-native/acceptance-20261018-*.log`.

Testdaten:

- `/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-pXhAx3`
  (Browser, 20 Aufträge, Navigation, Dialogzyklen).
- `/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-2sdjC5`
  (1.000 Einträge und echte Rücknahme auf der ältesten Seite).
- `/private/tmp/OpenCommander-NTFS-Queue-ILdSyy`
  (sauber ausgeworfenes NTFS-Abbild).

Der Gesamt-Build und die Signaturprüfung der isolierten Test-App bestanden.
Die Test-App registriert keine NTFS-Erweiterung; ihre erzeugten Erweiterungen
wurden aus dem Bundle herausgenommen und separat aufbewahrt. Der Maus-
Testtreiber akzeptiert Browser-/Dokumentfenster nur mit synthetischem
`OpenCommander-MacUITest-`-Titel, einschließlich des tatsächlich sichtbaren
Fensters. Die beiden neu geöffneten Browser-Testfenster wurden geschlossen;
bestehende Browserfenster und Anmeldungen bleiben unverändert.

Die installierte normale App wurde in dieser Runde nicht ersetzt. Kein Commit,
Push, Betriebssystem-Neustart, keine neue Sicherheitsfreigabe und keine
Änderung an bestehenden Konten. Unabhängige staged Linux-/Android-Änderungen
blieben erhalten. Die entfernten eigenen Compiler-Caches sind neu aufbaubar;
Quellen, Protokolle und App-Sicherungen wurden nicht entfernt.

## Noch kein vollständiger Abschluss

Die 158 Originalfälle enthalten weitere vollständige manuelle Sequenzen,
unter anderem einen zweistündigen Vier-Auftrags-Netzstörungs-Dauerlauf,
sämtliche Auflösungs-/Tastaturvarianten, frische Drei-Provider-Anmeldungen,
Mehrfach-Drive-Auswahl, iCloud-2FA, öffentliche Freigaben sowie externe
SMB/WebDAV-/Writeback-Mounts und die Hardware-/Dateisystemmatrix. Diese sind
nicht pauschal durch Unit-Tests oder Linux-CI bestanden. Für manche fehlen
konfigurierte Testkonten, Server oder Geräte; andere Bediensequenzen bleiben
noch auszuführen. Deshalb bleibt `complete_parity` ausdrücklich **false**.
