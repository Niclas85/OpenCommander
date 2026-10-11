# Linux-Änderungsprotokoll

## 0.3.12 – 11. Oktober 2026

- Kopieraufträge vor Beginn in privater SQLite-Warteschlange speichern, einschließlich
  Quelle, Ziel, Konfliktmodus und wartender Aufträge. Keine Zugangsdaten im Journal.
- Pause und Fortsetzen im Hauptfenster. Pause bewahrt private Zwischenstände auf dem
  Ziellaufwerk; auch große Einzeldateien werden an der geprüften Byteposition fortgesetzt.
- Beim Schließen laufende Kopien sicher pausieren und Hintergrundzugriffe abwarten.
  Beim nächsten Start gespeicherte Kopien automatisch fortsetzen; fehlerhafte Aufträge
  bleiben mit Fehlerhinweis erhalten und lassen sich nach Verbindungsreparatur fortsetzen.
- Abbrechen beendet aktuelle Kopie und Warteschlange und entfernt unfertige Zwischenstände
  im Hintergrund. Fertige Ziele und Wiederherstellungskopien bleiben erhalten.
- Fertige Dateien im Zwischenstand per SHA-256 prüfen, Quellattribute vergleichen und
  angefangene Dateipräfixe mit der Quelle abgleichen. Keine erneute Kopie fertiger Dateien.
- Ziel-/Quell-Mounts identifizieren; bei fehlendem oder anderem Laufwerk stoppen,
  statt unbemerkt in einen lokalen Ersatzordner zu schreiben. Gespeicherte eigene
  Online-Verbindungen im Worker wieder einbinden; neue Anmeldungen bleiben Benutzeraktion.
- Veröffentlichung, Historie und Undo behalten ihre Schutzregeln. Unterbrochene,
  nicht eindeutig zuordenbare Veröffentlichungen stoppen zur manuellen Prüfung.
- Undo eines noch offenen Kopierauftrags erst nach Fortsetzen oder Abbrechen erlauben.
  Wiederaufgenommene Bytes zählen zum Gesamtfortschritt, nicht zur neuen Übertragungsrate.
- Persistenz gilt für Kopieren; Verschieben und andere Dateimutationen behalten ihre
  bisherige Verarbeitung und dürfen beim Schließen nicht unterbrochen werden.

## 0.3.11 – 11. Oktober 2026

- Einstellungen / Orte als eigenes, nicht modales Fenster öffnen und bestehendes
  Fenster bei erneutem Klick aktivieren. Dateibereiche bleiben gleichzeitig bedienbar,
  auch während eines laufenden Kopiervorgangs.
- Transfer-Signale ausdrücklich an den GUI-Thread zustellen; Fortschrittsdetails
  gebündelt alle 250 ms anzeigen statt zusätzlich bei jeder Worker-Meldung.
- Orte-Leiste enthält nur Ziele zum Öffnen einschließlich Papierkorb, gespeicherter
  Online-Orte und einbindbarer Datenträger. Verwaltungsbuttons dort entfernt.
- Online-Orte und Verbindungen ausschließlich unter Einstellungen / Orte verwalten;
  beide Zugänge in Deutsch und Englisch, auch während eines Transfers erreichbar.
- Desktop-Tests prüfen eine echte lokale Kopie mit parallel bedienbaren Einstellungen,
  Navigation, GUI-Ereignissen sowie Verwaltung aus den Einstellungen in beiden Sprachen.

## 0.3.10 – 11. Oktober 2026

- Externe rclone-Cloud-Mounts des eigenen Benutzers erkennen: Google Drive,
  OneDrive, Dropbox, iCloud. Remote-Unterordner und zugehörige Konfiguration aus
  dem laufenden Mountprozess übernehmen, ohne Zugangsdaten in Profile zu kopieren.
- Auch dort Cloud-Kontextmenü mit Linkfreigabe (Drive/OneDrive/Dropbox), Pfad
  kopieren und Provider-Website. Keine Freigabe allein beim Öffnen des Menüs.
- Fehler der GVFS-Desktop-Abfrage blenden erkannte rclone-Orte nicht aus.
- Ordner-Metadaten dieser Mounts direkt über das Cloud-Backend auflisten statt
  jedes Objekt durch den FUSE-Mount zu statten. Abbruch, Zeitlimits und verworfene
  alte Ergebnisse wie bei intern gespeicherten Cloud-Verbindungen.
- Namespace-Overrides, die ein anderes Cloud-Ziel freigeben könnten, werden
  nicht automatisch für Cloud-Aktionen übernommen; reine Fremd-Mounts unverändert.
- Ungültige/beschädigte Passwort-Konfiguration ebenfalls als Anmeldefehler mit
  Hinweis auf erneute Anmeldung melden; keine ungefilterten Backend-Zugangsdaten.
- Ordnerbaum standardmäßig rund 280 px breit statt 155 px; Ordnernamen ohne
  Auslassung mit horizontalem Scrollen. Splitterbreite je Bereich speichern.
- Drag-and-drop zeigt eine Vorschau am Mauszeiger mit Symbol/Vorschaubild,
  Dateiname, Anzahl und gewähltem Kopier-/Verschiebemodus.

## 0.3.9 – 11. Oktober 2026

- Angeschlossene, vom Desktop erkannte einbindbare Datenträger auch ohne
  Mountpfad in der Ortsliste anzeigen. Klick bindet im Hintergrund ein und
  öffnet direkt; keine vorgeschalteten Verbindungsoptionen.
- Stabile Volume-ID verbindet den Einbindungsauftrag mit dem danach sichtbaren
  Mount. Laufwerksnamen statt technischer Mountpfadnamen, auch im Bereichstitel.
- Fehlgeschlagene Einbindung lässt den bisherigen Ordner geöffnet und den
  Datenträger erneut auswählbar. Keine doppelten Einbindungsaufträge; Navigation
  während des Einbindens wird nicht durch verspätete Ergebnisse überschrieben.
- Automatische Desktop-Abfragen aktualisieren angeschlossene/entfernte Geräte.
  Beenden wartet auf laufende Einbindung; keine unterbrochenen Mountmutationen.
- OneDrive-Kontextmenü zusätzlich für Datei und Ordner im Desktop-Test geprüft.

## 0.3.8 – 11. Oktober 2026

- Kopfzeile jedes Dateibereichs zeigt den gespeicherten Online-Verbindungsnamen,
  auch in Unterordnern; Umbenennen aktualisiert die Anzeige sofort.

- Gespeicherte Orte per einfachem Klick direkt öffnen; bereits eingebundene
  Orte ohne Verbindungsdialog. Fehlende Einbindungen im Hintergrund herstellen,
  doppelte Öffnungsanfragen verhindern. Navigation während des Verbindens wird
  nicht durch ein verspätetes Ergebnis überschrieben.
- Rechtsklick auf Ort → Bearbeiten öffnet gezielt dessen Einstellungen.
  Anzeigenamen separat speichern, ohne neu anzumelden; Serverdaten vorbefüllt.
  Cloud-Anmeldung ändern bleibt eine ausdrückliche Aktion. Kein automatischer
  Wechsel zum Konfigurationsdialog bei Verbindungsfehlern.
- Nicht gespeicherte Server-Passwörter/Passphrasen bei Bedarf separat abfragen;
  bestehende Schlüsselbund-/SSH-Prüfungen bleiben erhalten.
- Cloud-Kontextmenü verwendet den tatsächlich gespeicherten Anzeigenamen.

## 0.3.7 – 10. Oktober 2026

- GitGuardian-Fundstelle geprüft: deutscher Hilfetext zum iCloud-Passwortfeld,
  kein Zugangswert. Hilfetext aus der Passwort-Schlüssel/Wert-Tabelle getrennt,
  damit die Benutzererklärung nicht wie ein eingebettetes Passwort aussieht.

- Dateien und Ordner in gespeicherten Cloud-Mounts haben ein Online-Kontextmenü:
  Teilen mit Link, Online-Pfad kopieren und Freigaben auf der Provider-Website.
- Google Drive, OneDrive und Dropbox erstellen/holen Freigabelinks über rclone.
  Dialog erklärt vor Erstellung den Zugriff für jeden mit dem Link; Link erst
  auf Knopfdruck kopieren/öffnen. OneDrive fordert ausdrücklich einen Leselink.
- iCloud bietet Browser-Freigabeverwaltung; direkte Linkerstellung dort nicht
  verfügbar. Keine vorgetäuschte Freigabe-/Widerruf-Unterstützung.
- Linkerstellung mit Ladeanzeige, Abbruch und 30-Sekunden-Zeitlimit außerhalb
  des GUI-Threads; Backendfehler ohne ungefilterte Zugangsdaten. Abbruch/Timeout
  kann eine bereits beim Dienst erstellte Freigabe nicht zurücknehmen.
- Keine Cloud-Freigabeaktionen für lokale Dateien, Archiv-Inhalte, Symlinks
  oder gemischte Speicher-Auswahl. Linkerstellung für ein ausgewähltes Objekt.

## 0.3.6 – 10. Oktober 2026

- Online-Video-/Audiovorschau lädt die ausgewählte Datei sequenziell in einen
  privaten lokalen Zwischenspeicher, bevor Wiedergabe und Zeitleiste starten.
  Ladeanzeige mit Prozent, MiB, Dauer und Geschwindigkeit sowie Abbruch;
  Navigation/Schließen beendet den Download und entfernt den Zwischenspeicher.
  Maximal 2 GiB pro Medium, 30 Sekunden ohne Fortschritt/15 Minuten insgesamt;
  Fehlermeldungen geben keine Zugangsdaten aus. Keine Änderung der Quelldatei.

- Archive als Ordner öffnen: ZIP, TAR/TGZ, TAR.GZ/BZ2/XZ/ZST, 7z und RAR.
  Gleiches Browsen, Pfadnavigation, Vorschau/externe Öffnung einzelner Dateien
  und ausgewähltes Entpacken mit bestehender Historie/Undo. Native Formate über
  libarchive; keine externe 7z-/unrar-Installation nötig im portablen Paket.
- Archiv-Prüfung vor Veröffentlichung: relative Pfade ohne Traversal,
  keine Symlinks/Hardlinks/Spezialdateien, keine doppelten Namen;
  100.000 Einträge/4 GiB, Vorschau maximal 128 MiB mit tatsächlicher Byteprüfung.
  Native Entpackung liest nach der Headerprüfung sequenziell statt das ganze
  Archiv für jede Datei neu zu öffnen. Verschlüsselte Archive ohne Passwort-
  Assistent; nicht unterstützte Verschlüsselungen/Varianten melden einen Fehler.
- Rechtsklick auf leere Ordnerfläche: Neuer Ordner, Einfügen, Aktualisieren und
  versteckte Dateien. Aktiviert den geklickten Bereich und entfernt die alte
  Dateiauswahl; Archive bieten nur die lesenden Ordneraktionen.

- Gespeicherte, eingebundene Cloud-Orte (OneDrive, Google Drive, Dropbox, iCloud)
  lesen Ordner-Metadaten direkt über das rclone-Backend. Ein langsamer/staler
  FUSE-Daemon blockiert damit nicht mehr das Auflisten beim Start. Dateiaktionen
  und Mediendownloads verwenden weiter den Mount und ihre bestehenden Grenzen.
- Cloud-Leseprozesse sind abbrechbar und auf 30 Sekunden begrenzt; Verbindungs-/
  Anfrage-Zeitlimits und begrenzte Wiederholungen. Kein ungefiltertes Backend-
  stderr im UI. Abgelaufene Anmeldung bekommt einen verständlichen Hinweis.
- Netzwerk-/Cloud-Bereiche zeigen verstrichene Ladezeit und „Erneut laden“ nach
  Fehler oder Abbruch. Eigenes GUI-Zeitlimit greift auch vor einem durch volle
  Worker verzögerten Start. Navigation verwirft alte Ergebnisse.
- Synchrone GUI-is_dir-Abfragen für Startordner/Downloads entfernt. Lokale
  Symlinks auf Cloud-Mounts werden erkannt, ohne den Provider zu statten;
  remote Ordnerbäume bleiben von synchroner Qt-Pfadsynchronisation ausgenommen.
- Fehlendes Python-API `chmod(..., follow_symlinks=False)` verursacht beim
  Attributabschluss keinen Transferabbruch mehr. Nicht verfügbare Metadaten
  werden als Hinweis erfasst; kein unsicherer Fallback, der Symlinks folgt.
  Verfügbare Zeitstempel werden weiterhin übernommen.
- Tatsächlicher gespeicherter OneDrive-Root read-only geprüft: 28 Einträge in
  0,8 Sekunden, Anmeldung erreichbar. Regressionstests für Startup-Cloud-Stall,
  GUI-Zeitlimit/Navigation, CLI-Abbruch und Auth-Fehler-Sanitierung sowie den
  fehlenden chmod-API-Fall einschließlich vollständigem Transfer und Undo.

## 0.3.5 – 10. Oktober 2026

- Errno 95 beim Kopieren auf GVFS-SMB/NAS-Mounts behoben: nicht unterstütztes
  `fsync` und nicht unterstützte Dateiattribute auf erkannten GVFS-/rclone-
  Providern blockieren die Inhaltskopie nicht mehr. Flush und Schließen bleiben
  erforderlich; echte I/O-, Berechtigungs- und Speicherplatzfehler brechen ab.
- Nach fehlendem Attribut-Support werden Zeitstempel und Unix-Dateirechte getrennt
  versucht. Einschränkungen erscheinen im Transferabschluss und dauerhaft in
  der Historien-Info; ohne fsync kann die Dauerhaftigkeit auf dem Server nicht
  bestätigt werden. Normale lokale Dateisysteme behalten strikte Fehlerbehandlung.
- GVFS unterstützt ebenfalls den gegen vorhandene Ziele prüfenden Rename-Fallback,
  wenn RENAME_NOREPLACE nicht unterstützt wird. Die Erkennung trennt verschiedene
  GVFS-Freigaben und respektiert verschachtelte andere Mounts. Keine Atomizitäts-
  garantie gegenüber gleichzeitig schreibenden anderen Clients.
- Regressionstests: rekursiver JPG-Transfer trotz ENOTSUP bei fsync/chmod,
  erhaltene Bytes/Zeitstempel und Undo; EIO, ENOSPC und EACCES bleiben Fehler;
  lokales ENOTSUP wird nicht ignoriert. Keine Teständerungen an persönlichen
  NAS-Dateien.

## 0.3.4 – 10. Oktober 2026

- Server-Anmeldung mit einem Formular für SFTP, FTP und explizites FTPS:
  Server, Port, Benutzer, Passwort/SSH-Key/SSH-Agent und optionaler Startordner.
  Verbindungen werden gespeichert und im aktiven Bereich geöffnet. Gespeicherte
  Server lassen sich über „Erneut anmelden“ bearbeiten; eingebundene Verbindungen
  müssen dafür erst getrennt werden.
- Server-Passwörter/Key-Passphrasen standardmäßig nur im Sitzungsspeicher,
  optional im Linux Secret Service. Kein unsicherer Speicher-Fallback bei
  gesperrtem/fehlendem Schlüsselbund. Neue Server-Konfigurationen enthalten
  keine Passwörter; beim Bearbeiten werden alte rclone-Passwortfelder entfernt.
  Cloud-Konfiguration bleibt beim bisherigen privaten rclone-Profil.
- SSH-Hostprüfung integriert: SHA-256-Fingerabdruck neuer Server ausdrücklich
  bestätigen; geänderte bekannte Schlüssel blockieren die Verbindung.
  SFTP führt keine Shell-Kommandos auf dem Server aus. FTPS behält verpflichtende
  Zertifikatsprüfung; unverschlüsseltes FTP verlangt eine Warnbestätigung.
- Private OpenSSH-/PEM-Schlüssel bleiben an ihrem Speicherort, nur bei privaten
  Dateirechten verwendbar. Verschlüsselte OpenSSH-Schlüssel werden über ein
  Askpass-Hilfsprogramm im vorhandenen SSH-Agent für eine Stunde entsperrt.
  Passphrasen gehen nicht in Prozessargumente oder Logs. Kein SCP-only-Backend,
  kein direkter PuTTY-PPK-Import. SSH-Agent und libsecret sind Host-Abhängigkeiten.
- Navigation nach oben markiert den verlassenen Ordner nach dem asynchronen
  Laden und scrollt ihn in den sichtbaren Bereich; ebenso in ZIP-Ordnern und beim
  Verlassen eines ZIP-Archivs.
- Kopieren/Verschieben blockiert Vorschau, Öffnen, Eigenschaften, Suche und
  Einstellungen nicht mehr. Weitere Datei-Aufträge warten in FIFO-Reihenfolge;
  Quell-/Zielpfade und Aktion sind beim Einreihen festgelegt. Eigener Worker-Pool
  für Datei-Aufträge hält die Lesezugriffe frei. Anzeige der wartenden Aufträge;
  Abbrechen verwirft auch die Warteschlange. Undo und Aushängen bleiben während
  einer Dateioperation gesperrt.
- Lokaler echter SFTP-Test mit Passwort, privatem Key und verschlüsseltem
  OpenSSH-Key/isoliertem Agent; Ablehnung ungeprüfter Hostschlüssel getestet.
  Kein Test mit persönlichen Server-Zugangsdaten.

## 0.3.3 – 10. Oktober 2026

- JPG-/Bild-Thumbnails auch auf Online-/NAS-Mounts: sichtbare Bilder werden im
  Hintergrund geladen, maximal zwei Online-Anfragen gleichzeitig. Größenlimit
  32 MiB für Thumbnails; keine automatischen Online-Video-Downloads.
- Online-Bildvorschau liest sequenziell in eine private temporäre Datei und
  dekodiert lokal, statt auf Cloud-Dateien zu suchen. Fortschrittsanzeige,
  128-MiB-Downloadlimit, Zeitlimits und Abbruch bei Navigation/Schließen;
  temporäre Downloads werden nach dem Dekodieren entfernt.
- Bild-Ergebnisse und Fortschritt werden über den GUI-Thread verarbeitet.
  Gleiches-Verzeichnis-Aktualisierung behält die letzte Dateiliste bis zum neuen
  Ergebnis; Schließen stoppt Timer, Ordnerüberwachung und neue Ladeanfragen.
- Kopieren/Verschieben zeigt Prozent, Datenmenge, Anzahl Dateien, aktuellen Namen,
  Dauer, mittlere Rate und geschätzte Restzeit. Vorbereiten, Upload-Abschluss und
  Prüfen sind eigene Phasen; 100 Prozent erst nach erfolgreichem Abschluss.
- Darkmode-Checkbox jetzt sichtbar im Kopfbereich; Auswahl bleibt gespeichert.
- EINVAL/Errno 22 beim Wiederherstellungsordner auf externen rclone-Mounts behoben:
  erkannte fuse.rclone-Mounts verwenden ebenfalls den Provider-Umbenennungsweg
  mit Zielprüfung. Normale/externe andere Dateisysteme behalten RENAME_NOREPLACE.
  Keine Atomizitätsgarantie gegenüber gleichzeitigen Änderungen anderer Clients.

## 0.3.2 – 10. Oktober 2026

- Browser-Anmeldung für OneDrive, Google Drive und Dropbox mit erklärten Schritten.
  OpenCommander öffnet den Standardbrowser über Qt; unter Wayland wird eine
  XDG-Vordergrundaktivierung angefordert. Der Desktop kann den Fokus ablehnen;
  dafür bleibt während der Anmeldung ein Knopf zum erneuten Öffnen verfügbar.
- Nur der lokale rclone-OAuth-Endpunkt wird aus dem laufenden Backend übernommen;
  Anmelde-URLs werden nicht protokolliert oder gespeichert. Kein doppelter Browserstart.
- OneDrive-Laufwerksauswahl zeigt lesbare Namen und bevorzugt „OneDrive – persönliche
  Dateien“. Zusätzliche/interne Laufwerke bleiben auswählbar; echte IDs bleiben erhalten.
- Gespeicherte Verbindungen bleiben nach Neustart in der Seitenleiste sichtbar,
  auch ohne aktiven Mount. Ein Klick verbindet mit den gespeicherten Zugangsdaten.
- Assistent erklärt Online-Zugriff, kurze Ordnercache-Zeit und die iCloud-Anmeldung
  mit Apple-ID/Passwort/2FA. iCloud bietet im verwendeten Backend kein Browser-OAuth.
- Bei app-eigenen FUSE-Mounts wird die Rücknahme-Prüfsumme erst nach stabilen
  Attributen aufgezeichnet; Änderungen während der Prüfung werden abgewiesen.

## 0.3.1 – 10. Oktober 2026

- OneDrive-Anmeldeknopf startet Browser-OAuth direkt; technische Konfigurationsfragen
  entfallen. Erfolgreich eingerichtete Cloud-Orte öffnen automatisch den aktiven Bereich.
- Aktuelles rclone app-intern installiert (geprüft mit 1.75.2). Offizieller HTTPS-
  Download, SHA-256-Prüfung vor Ausführung; Systeminstallation und Mounts bleiben erhalten.
- iCloud-Backend verfügbar: Apple-ID, reguläres Passwort und 2FA im Dialog.
  Keine falsche Browser-OAuth-Zusage für Apple; Unterstützung und Anforderungen
  stehen sichtbar im Dialog und in der Anleitung.
- Erneute Anmeldung für abgelaufene Verbindungen; Profile werden nicht dupliziert.
- Abbrechen greift auf den aktuellen Vorgang; Passwort/2FA bleiben verdeckt.
- Ohne Konto geprüft: echter OneDrive-Backend-Aufruf fordert Browserstart an und
  lässt sich abbrechen; aktueller iCloud-Assistent liefert die Apple-Konfigurationsfragen.
  Keine persönlichen Zugangsdaten, Kontozugriffe oder Cloud-Dateiänderungen getestet.

## 0.3.0 – 10. Oktober 2026

Abgleich mit `origin/codex/mac-linux-parity` bei Commit `2f96726`:

- Rekursive Suche mit editierbarem Pfad, Platzhaltern, optionaler Groß-/Kleinschreibung,
  vollständigen Trefferpfaden, Ladeanzeige und Abbruch.
- SHA-256-Ordnervergleich und Vorschau vor Mehrfach-Umbenennen mit Mustern,
  Zähler, Suchen/Ersetzen, Kollisionsschutz und persistenter Rücknahme.
- Orte-Einstellungen aus dem Paritätsbranch übernommen: Sprache, Erscheinungsbild,
  Namen/Sichtbarkeit und benutzerdefinierte Verknüpfungen.
- Grafischer Online-Einrichtungsassistent für rclone/FUSE: OneDrive, Google Drive,
  Dropbox, iCloud (passende rclone-Version erforderlich), FTP, FTPS und SFTP.
  Eigene Konfiguration und kein Eingriff in vorhandene Benutzerkonten.
- Registrierung app-eigener Provider-Mounts mit gesondertem Umbenennungspfad;
  keine falsche Behauptung atomarer Online-Transaktionen. Details: PARITY.md.
- Kompaktere Historienkarten mit Info-Dialog und eigener Rücknahme.
- Papierkorb-Ansicht mit Wiederherstellung bisheriger OpenCommander-Löschvorgänge.
- Löschmöglichkeit in Medien-/Textvorschau. Mediennavigation geht nach Entfernen
  zur nächsten Datei; letzter Eintrag schließt den Betrachter.
- Ordner-Ladebalken und Abbruch, veraltete Ergebnisse werden verworfen;
  Remote-Listings bleiben auf 15 Sekunden begrenzt.
- Cloud-Pfadprüfungen und ZIP-Zielprüfung aus dem UI-Thread verlagert,
  keine automatischen Remote-Thumbnails/Historiendownloads, Textvorschau im Hintergrund.
- Beim Beenden wartet die App asynchron auf Hintergrundzugriffe.
- Zusätzliche Regressionstests und echter isolierter rclone-/FUSE-Test für Kopieren,
  Konfliktnamen, Rücknahme, Entfernen und Wiederherstellung. Keine persönlichen
  Cloud-Dateien oder Zugangsdaten für Tests verwendet.

## 0.2.4 – 30. September 2026

Erster zusammengeführter Linux-Quellstand im Repository. Dieser Eintrag dokumentiert
auch die zuvor lokal installierten Iterationen; diese waren keine separaten
GitHub-Releases. Android-, iOS- und macOS-Anwendungscode wird dabei nicht geändert.

### Oberfläche und Bedienung

- Native PySide6-/Qt-Anwendung nach dem Vorbild der Mac-Version, mit zwei Bereichen,
  Ordnerbäumen, Dateilisten, Pfadeingabe, Sortierung, Filter und Mehrfachauswahl.
- Deutsche und englische Oberfläche, farbige Akzente, helles/dunkles Design,
  Checkboxen und ein Kopieren-/Verschieben-Umschalter.
- Drag-and-drop führt die gewählte Aktion direkt aus, auch beim Ablegen in einen
  Unterordner. Die Drag-Freigabe der Dateieinträge wurde korrigiert. Externe
  Dateiquellen erhalten eine Kopierbestätigung, damit sie Quellen nicht zusätzlich löschen.
- Der überflüssige „Ausführen“-Button wurde entfernt (lokale Version 0.2.2).
- „Ordner auswählen“ wurde aus der Werkzeugleiste entfernt; Navigation erfolgt
  direkt im Fenster. „Entpacken“ erscheint nur im ZIP-Kontext (0.2.3).
- „Öffnen mit …“ im Rechtsklick-Menü verwendet die native GTK-Programmauswahl;
  Abbruch und Startfehler werden behandelt. ZIP-Dateieninhalte können als externe
  Kopie geöffnet werden, ohne Änderungen automatisch ins ZIP zurückzuschreiben (0.2.4).
- Kontextaktionen beziehen sich auf den angeklickten Eintrag und erhalten eine
  vorhandene Mehrfachauswahl, wenn innerhalb dieser Auswahl geklickt wird.

### Vorschau und Medien

- Integrierter Bild-, Video- und Audiobetrachter mit Links-/Rechts-Navigation in
  der aktuellen sichtbaren Sortier- und Filterreihenfolge, auch innerhalb von ZIPs.
- Begrenzte Bilddekodierung im Hintergrund und Behandlung defekter Dateien;
  abgesicherte Lebensdauer der Vorschaufenster und asynchronen Ergebnisse.
- Bild- und Video-Thumbnails mit begrenztem Cache; Video-Thumbnails benötigen
  optional das Systemprogramm ffmpeg. ZIP-Einträge behalten Dateisymbole.
- Wiedergabeknopf und Zeitleiste nur bei Videos (0.2.3). Audio lässt sich mit
  der Leertaste steuern; Schließen beendet die Wiedergabe.

### Dateiaktionen und Historie

- Kopieren, Verschieben, Umbenennen, neue Ordner, Entfernen, ZIP-Erstellung und
  geschütztes Entpacken; Desktop-Zwischenablage und Hintergrundverarbeitung.
- Atomare Veröffentlichung vorbereiteter Kopien ohne Überschreiben neu belegter
  Ziele; Sicherung ersetzter Originale und Erhalt vollständig kopierter Ziele,
  wenn die anschließende Quellbereinigung scheitert.
- Persistente Historie mit Zeit, Quelle, Ziel, Fehlern, Wiederherstellungspfaden
  und Vorschau der ersten verfügbaren Mediendatei. Eigene Rücknahme pro Vorgang.
- Rücknahme prüft Inhalt, Metadaten und Dateidentität. Teilrücknahmen werden
  gespeichert; geänderte Dateien oder belegte Originalpfade werden nicht blind ersetzt.
- Eigene Wiederherstellungsverzeichnisse statt System-Papierkorb; deren Speicher
  wird nicht automatisch bereinigt. Archivgrenzen und weitere Details: [README](README.md).

### Desktop, Laufwerke und Eigenschaften

- Nachfrage beim ersten Start zur Standardzuordnung für Ordner, mit ausdrücklicher
  Zustimmung vor Änderung; korrigierte Starterregistrierung und GIO-Verifikation.
- Einzelinstanz pro Profil und Weitergabe von Ordnerpfaden an das vorhandene Fenster.
- Verbindungsdialog für USB, bestehende Mounts, SMB, SFTP und WebDAV über GIO/GVFS;
  sicheres Trennen/Auswerfen ist während Dateioperationen gesperrt.
- GNOME-Online-Konten für verfügbare Google-/Microsoft-Provider, Erkennung vorhandener
  rclone-Mounts und lokaler Cloud-Ordner, einschließlich benutzerdefinierter Dropbox-Pfade.
- Keine eigene Apple-Anmeldung: iCloud erfordert einen separat eingerichteten
  Sync-Ordner oder Mount. Provider-Anmeldung und Cloud-Synchronisation bleiben extern.
- Frische asynchrone Eigenschaften; bei NAS/GVFS Abfrage der ursprünglichen
  Provider-Adresse statt irreführender FUSE-Metadaten. Fehlende Angaben bleiben unbekannt.
- Ordner-Inhaltsgröße nur auf ausdrückliche Berechnung, mit begrenzter Laufzeit,
  gekennzeichneten Teilergebnissen und ohne Verfolgen symbolischer Links.
- ZIP-Eigenschaften beziehen sich auf den ausgewählten Archiveintrag.

### Paketierung und Entwicklung

- Start-, Build- und Benutzerinstallationsskripte; PyInstaller-Verzeichnisbundle
  für Ubuntu 24.04/x86_64, Archiv und SHA-256-Prüfsumme.
- Festgelegte Python-Abhängigkeiten, mitgelieferte Quellen, Lizenztexte und Hinweise
  zu Qt, FFmpeg und der gebündelten XCB-Cursor-Bibliothek.
- Bereinigte Umgebungsvariablen beim Aufruf von Systemprogrammen aus dem Bundle.
- Linux-Tests und Paketierung in GitHub Actions; generierte Pakete, virtuelle
  Umgebungen und lokale Testbilder bleiben außerhalb der Versionsverwaltung.

### Verifikation und verbleibende Grenzen

- Gesamte Linux-Testsuite am 30. September 2026: **75 Tests bestanden**. Abgedeckt
  sind Dateiaktionen/Rücknahme, Desktop-Zuordnung, Integrationen, Eigenschaften,
  Medien, Kontextaktionen und Drag-and-drop. Aufruf siehe [README](README.md).
- Der lokal installierte Build 0.2.4 bestand den Paket-Smoke-Test einschließlich
  Start des Medienbetrachters und Bilddekodierung.
- NAS/SMB und vorhandener Google-Drive-rclone-Mount wurden lesend geprüft.
  Keine echten Schreib-/Löschtests auf NAS, Cloud oder NTFS durchgeführt.
- OneDrive, Dropbox und iCloud waren nicht als authentifizierte Testkonten
  verfügbar; ihre tatsächliche Anmeldung und Synchronisation sind nicht end-to-end geprüft.
- „Öffnen mit …“ ist durch automatisierte Aufruf-/Abbruchtests und GTK-API-Prüfung
  abgedeckt; ein interaktiver Start sämtlicher installierter Programme wurde nicht getestet.
- Tests ohne Bildschirm ersetzen keine vollständige visuelle Prüfung aller
  Desktop-Umgebungen. Andere Distributionen, Architekturen und sämtliche Codecs
  sind nicht umfassend getestet. Cloud-Provider ohne erforderliche sichere
  Dateisystemoperationen können Schreibaktionen ablehnen.
