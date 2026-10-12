# OpenCommander für Linux

Native Qt-Desktop-Version nach dem Vorbild der Mac-Catalyst-App. Keine Browser-
oder Electron-Hülle. Deutsch und Englisch; helles und dunkles Erscheinungsbild.

Aktueller Stand: **0.3.19**. Die Änderungen und der geprüfte Umfang stehen im
[Änderungsprotokoll](CHANGELOG.md).

**[Ausführliches HTML-Anwenderhandbuch öffnen](docs/handbuch/index.html)** —
18 Kapitel mit 18 Screenshots, lokaler Suche, Bildvergrößerung, Hell-/Dunkelmodus
und Druckansicht. Offline nutzbar: `docs/handbuch/index.html` im Browser öffnen.
Im portablen Paket wird das Handbuch unter demselben relativen Pfad mitgeliefert.

## Starten

Das fertige Archiv `OpenCommander-linux-x86_64.tar.gz` entpacken und die Datei
`opencommander/opencommander` ausführen. Python oder Qt müssen für dieses Paket
nicht separat installiert werden. Das Verzeichnis `_internal` muss neben der
Programmdatei bleiben.

```bash
tar -xzf OpenCommander-linux-x86_64.tar.gz
./opencommander/opencommander
```

Optional `./opencommander/install-local.sh` ausführen, um einen Starter im
persönlichen Anwendungsmenü anzulegen. Danach das entpackte Verzeichnis an seinem
Ort belassen. Es wird nichts systemweit installiert und kein Root-Zugriff benötigt.
Der Starter kann durch Entfernen von
`~/.local/share/applications/opencommander.desktop` wieder entfernt werden.

Der hier erzeugte x86_64-Build wird auf Ubuntu 24.04 gebaut und benötigt glibc 2.39
oder neuer sowie eine Wayland- oder X11-Desktop-Sitzung. Für andere Architekturen
oder ältere Distributionen auf dem Zielsystem aus dem Quellcode bauen. Es ist
kein universell auf allen Linux-Distributionen getestetes Paket.

## Orte und Dienstsymbole

Online-Orte zeigen farbige Symbole für OneDrive, Google Drive, Dropbox und iCloud;
FTP/FTPS und SFTP haben eigene Server-Symbole. Die Symbole werden lokal mitgeliefert.
Orte in der oberen Leiste durch Ziehen vor oder hinter einen anderen Ort umsortieren.
Eine blaue Markierung zeigt die Einfügeposition. Alternativ per Rechtsklick
„Nach links“ oder „Nach rechts“ wählen. Auch Papierkorb und Datenträger lassen
sich verschieben. Die Reihenfolge bleibt nach Neustarts und erneutem Verbinden
erhalten; die Aktion ändert ausschließlich Verknüpfungen.

## Aus dem Quellcode

Python 3.12 oder neuer mit `venv` sowie ein grafischer Linux-Desktop sind erforderlich.
Im Repository:

```bash
./linux/run.sh
```

Beim ersten Start richtet das Skript eine lokale virtuelle Python-Umgebung ein
und installiert `PySide6-Essentials` und `PySide6-Addons` aus `requirements.txt`. Danach funktioniert der
Start ohne Internetzugriff. Auf einem frischen Ubuntu-System kann das Paket
`python3-venv` zusätzlich benötigt werden. Für den Quellcodestart unter X11 benötigt Qt die üblichen XCB-
Laufzeitbibliotheken, insbesondere `libxcb-cursor0`; das portable Paket enthält
diese Cursor-Bibliothek bereits. Wayland benutzt das Qt-Wayland-Plugin.

Optional können Startverzeichnisse und ein separates Einstellungsprofil angegeben werden:

```bash
./linux/run.sh --left "$HOME" --right "$HOME/Downloads"
./linux/run.sh --state-dir /tmp/opencommander-testprofil
```

## Standard-Dateimanager

Beim ersten normalen Start fragt OpenCommander einmalig, ob es der Standard-
Dateimanager werden soll. Erst bei **Ja** wird die Benutzerzuordnung für
`inode/directory` mit `xdg-mime` geändert. **Nein** behält die aktuelle Zuordnung.
Bestehende Installationen erhalten diese Nachfrage beim ersten Start nach dem Update.
Der Menü-Starter muss zuvor mit `install-local.sh` registriert worden sein.

Ordnerpfade und lokale `file://`-URLs können an die Anwendung übergeben werden.
Läuft OpenCommander bereits, wird der Ordner an das vorhandene Fenster weitergereicht.
Dies betrifft die Standard-Zuordnung für Ordner, nicht jedes fest eingebaute
Dateimanager-Kommando anderer Anwendungen oder die Verwaltung des Desktops.

## Funktionen

- Zwei unabhängig navigierbare Bereiche mit Ordnerbaum, Pfadeingabe, Verlauf,
  sortierbarer Dateiliste, Namensfilter und Mehrfachauswahl.
- Kopieren, Verschieben, Umbenennen, neue Ordner und wiederherstellbares Entfernen.
- Drag-and-drop zwischen den Bereichen, in Ordner und aus anderen Desktop-Apps.
  Der Umschalter „Kopieren / Verschieben“ bestimmt die Aktion beim Loslassen per Drag-and-drop. F5 kopiert weiterhin direkt; F6 verschiebt direkt. Nach außen
  werden lokale Datei-URLs als Kopiervorgang angeboten.
- Desktop-Zwischenablage mit URI-Listen und GNOME-/KDE-Ausschneidekennzeichnung.
- ZIP erstellen, als Verzeichnis durchsuchen und ausgewählte Inhalte entpacken.
  „Entpacken“ erscheint nur bei ausgewählter ZIP-Datei oder im geöffneten Archiv.
  Archivpfade bleiben beim Entpacken erhalten; vorhandene Namen werden ergänzt.
- Bild- und Video-Thumbnails in der Dateiliste, im Hintergrund geladen und begrenzt
  zwischengespeichert. Video-Thumbnails benötigen das optionale Systemprogramm
  `ffmpeg`; fehlt es, bleibt das Dateisymbol sichtbar. ZIP-Einträge verwenden weiterhin Symbole.
- Bilder, Videos und Audio öffnen per Doppelklick, Enter oder Vorschau im integrierten
  Medienbetrachter. **Links/Rechts** wechselt zwischen Medien in der sichtbaren Sortier-
  und Filterreihenfolge des Ordners (auch innerhalb eines geöffneten ZIPs).
  **Leertaste** startet/pausiert Audio und Video. Wiedergabeknopf und Zeitleiste
  erscheinen nur bei Videos; Bilder zeigen ausschließlich die Navigation.
  **Escape** schließt den Betrachter und beendet die Wiedergabe. Bilder passen sich der
  Fenstergröße an. Nicht unterstützte Formate/Codecs zeigen eine Fehlermeldung.
- **Rechtsklick → Öffnen mit …** öffnet die GTK-Programmauswahl für eine einzelne
  Datei. Dafür werden System-Python, PyGObject und GTK 4 benötigt (siehe unten).
  ZIP-Dateiinhalte werden zunächst als Vorschaukopie entpackt; Änderungen durch
  externe Programme werden nicht in das Archiv zurückgeschrieben.
- Checkboxen für versteckte Dateien und dunkles Design; Kopieren/Verschieben als Umschalter.
- Versteckte Dateien, helles/dunkles Design, Deutsch/Englisch und gespeicherte Pfade.
- Gespeicherte Rückgängig-Historie, auch nach Neustart, mit eigenem
  Rückgängig-Button pro Vorgang.
  Die Historie zeigt Zeit, Quell-/Zielpfade, gesicherte Originale und Fehlerhinweise.
  Nur sichtbare Karten werden aufgebaut; beim Scrollen bleiben alle Einträge erreichbar.
  Sichtbare Medien-Einträge laden eine Vorschau der ersten passenden Datei; fehlt
  die Datei inzwischen, bleibt das Symbol. Die Rücknahme prüft weiterhin Änderungen.
- Zugriff auf bereits eingebundene Laufwerke, `/media`, `/run/media`, `/mnt` und
  lokale Cloud-Synchronisationsordner. Beliebige andere Pfade können eingegeben werden.
- Dateiaktionen laufen im Hintergrund und lassen sich während des Kopierens abbrechen.

Tastatur: **F5** Kopieren, **F6** Verschieben, **F2** Umbenennen,
**Strg-C/X/V** Zwischenablage, **Strg-A** alles auswählen, **Strg-Z** Rückgängig,
**Strg-Umschalt-N** neuer Ordner, **Entf** Entfernen, **Enter/Strg-O** öffnen,
**Leertaste/Strg-Y** Vorschau, **Strg-L** Pfad, **Alt-Auf** übergeordnet,
**Alt-Links/Rechts** Verlauf, **Strg-H** versteckte Dateien, **Strg-R** aktualisieren.

## Commander-Werkzeuge und Einstellungen

**Suchen / Strg-F** durchsucht den editierbaren absoluten Suchpfad rekursiv nach
Teilnamen oder `*`/`?`. Groß-/Kleinschreibung ist optional, Treffer zeigen vollständige
Pfade; Doppelklick öffnet den zugehörigen Ordner. Die Dateibereiche bleiben während
der Suche unverändert. **Werkzeuge → Ordner vergleichen / Strg-Alt-C** vergleicht
beide Bereiche einschließlich Dateiinhalt mit SHA-256. **Mehrfach umbenennen /
Strg-Umschalt-M** erstellt eine Vorschau für die aktive Auswahl: `[N]` Name ohne
Erweiterung, `[E]` Erweiterung mit Punkt, `[C]` Zähler, wörtliches Suchen/Ersetzen,
Start und Stellenzahl. Beispiel: `Foto-[C]-[N][E]`. Erst nach Vorschau kann angewendet
werden. Quellen und Zielnamen werden erneut geprüft; vorhandene Ziele werden nicht
absichtlich ersetzt. Fehler führen zur Rücknahme bereits ausgeführter Schritte,
soweit diese sicher überprüfbar sind. Verbleibende Schritte stehen in der Historie.

Suche/Vergleich laufen im Hintergrund, mit Ladeanzeige und Abbruch, maximal 100.000
Einträgen, ohne Verfolgen von Verzeichnislinks. Lesefehler markieren unvollständige
Ergebnisse. Inhaltsvergleich kann Cloud-Downloads auslösen. ZIP-Inhalte werden
von den Werkzeugen nicht unterstützt; Mehrfach-Umbenennen ist auf 10.000 Einträge
begrenzt. Bei blockierenden Provider-Lesezugriffen kann ein Abbruch verzögert greifen.

**Einstellungen / Orte / Strg-,** enthält Sprache, Erscheinungsbild und lokale
Verknüpfungen: Namen ändern, ausblenden und eigene Ordner hinzufügen. Änderungen
an Verknüpfungen löschen keine Dateien. **Online-Orte verwalten …** und
**Verbindungen verwalten …** befinden sich ebenfalls hier. Die Orte-Leiste zeigt
nur Ziele zum Öffnen; ein Klick öffnet den Ort beziehungsweise bindet ihn zuerst ein.
Das Einstellungsfenster ist nicht modal: Dateibereiche und Einstellungen bleiben
auch während eines Kopiervorgangs gleichzeitig bedienbar.

**Papierkorb** zeigt die von OpenCommander entfernten Dateien aus der persistenten
Historie mit Originalpfad, Zeitpunkt und Wiederherstellung des ausgewählten
Löschvorgangs. Das betreffende Laufwerk muss verbunden sein. Dies ist weiterhin
OpenCommanders eigener Wiederherstellungsbereich, getrennt vom System-Papierkorb.
Die Medien- und Textvorschau bietet **In Papierkorb**; nach Bestätigung wird die
aktuelle Datei entfernt. Der Medienbetrachter zeigt anschließend die nächste Datei
oder schließt sich, wenn keine Datei mehr übrig ist. ZIP-Vorschauen sind schreibgeschützt.

## Übertragungen anzeigen, pausieren und fortsetzen

Die aufklappbare **Übertragungen**-Leiste zeigt jeden Kopier- und Verschiebeauftrag
mit Quelle, Ziel, Prozent, Datenmenge, Dateizahl, aktueller Datei, Zeit und Geschwindigkeit.
Laufende, wartende, gespeicherte und abgeschlossene Aufträge bleiben getrennt sichtbar.
Mit **Minimieren** lässt sich jeder Auftrag einzeln kompakt darstellen: Status, Prozent,
Datenmenge, Fortschrittsbalken und Pause/Fortsetzen/Abbrechen bleiben sichtbar. Der
Auftrag läuft unverändert weiter. **Details** blendet Pfade und ausführliche Werte wieder
ein. Die kompakte Ansicht wird für gespeicherte Aufträge nach Neustart übernommen.

Bei mehreren Aufträgen öffnet sich die Übersicht automatisch, sofern noch keine eigene
Einstellung zum Aufklappen gespeichert wurde. Abgeschlossene Einträge lassen sich ausblenden.

Standardmäßig laufen **zwei** unabhängige Aufträge gleichzeitig; **Gleichzeitig** lässt
sich zwischen eins und vier einstellen. Überlappende Quell-/Zielpfade, lokale Pfad-Aliase
und Namen möglicher „Beide behalten“-Kopien werden vorsichtig nacheinander bearbeitet.
Pausierte oder wegen Fehlern gespeicherte Aufträge reservieren ihre Pfade weiter.
**Entfernen** unabhängiger Dateien ist während einer Kopie möglich, einschließlich
Dropbox/anderer Online-Orte und der Vorschau. Quell-/Zielpfade laufender, wartender
und pausierter Aufträge bleiben geschützt. Betroffene Löschaktionen zeigen den
Wartegrund und werden nach Freigabe des Pfads ausgeführt. Andere Mutationen wie
Umbenennen oder Entpacken warten weiterhin auf laufende Übertragungen.
Löschaktionen werden als wiederherstellbare OpenCommander-Papierkorb-Verschiebungen
ausgeführt; die Rücknahmekopie belegt weiterhin Speicher auf dem betreffenden Laufwerk.

Jeder Auftrag bietet **Pause**, **Fortsetzen** und **Abbrechen**. Die Fußzeile steuert
alle Aufträge. **Pause angefordert** und **Abbruch angefordert** erscheinen sofort;
bei einem bereits laufenden Dateisystem-/Netzwerkzugriff muss dessen Rückkehr
abgewartet werden. Erst **Pausiert – gespeichert** bestätigt den dauerhaften Zwischenstand.
Die Oberfläche wartet dabei nicht im GUI-Thread. Beim Schließen werden alle laufenden
Kopier-/Verschiebeaufträge pausiert; gespeicherte Aufträge laufen beim nächsten Start
automatisch weiter. Aufträge mit Fehlern benötigen bewusstes Fortsetzen.

Bereits laufende
Aufträge einer älteren Programmversion werden nicht automatisch übernommen;
ein erhaltener Zwischenordner kann nach eindeutiger Quellzuordnung gezielt als
Wiederherstellungsauftrag vorbereitet werden. Auch dabei werden vorhandene Daten
vor Nutzung mit der Quelle verglichen.

Fertige Dateien im privaten Zwischenordner werden geprüft und nicht erneut geschrieben.
Bei einer angefangenen Datei wird das vorhandene Präfix mit der Quelle verglichen,
anschließend nur der Rest kopiert. Die Prüfung kann bei Online-Dateien Lesezugriffe
und Zeit benötigen; der Fortschritt zeigt diese Prüfphase an. Geänderte Quellattribute,
manipulierte Zwischenstände und fehlende/andere Laufwerke stoppen den Auftrag.

**Abbrechen** am Auftrag entfernt nur diesen; die Fußzeile bricht alle ab, samt unfertigen
Zwischenständen. Fertige Ziele und verdrängte Originale bleiben erhalten. Während
eines blockierten NAS-/Cloud-Zugriffs wird der Abbruch angezeigt; das Fenster bleibt
bedienbar, der Zugriff muss aber erst zurückkehren. Keine erzwungenen Thread-Abbrüche.
Ist das Ziellaufwerk nicht verfügbar, bleibt der Auftrag erhalten, bis es zum sicheren
Entfernen wieder verbunden werden kann.

Nicht erreichbare Kopien bleiben gespeichert; Details und Fehler stehen im Hinweis
in der jeweiligen Auftragskarte. Nach dem Verbinden des Laufwerks oder erneuter Anmeldung
**Fortsetzen** wählen. Eigene gespeicherte Online-Verbindungen werden vor der Kopie im
Hintergrund wieder eingebunden. Externe Mounts und NAS-Freigaben müssen verfügbar sein.

Das private Journal liegt unter `$XDG_DATA_HOME/opencommander/transfers.sqlite3`
(Dateirechte 0600), Zwischenstände unter `.OpenCommanderTransfer-*` auf dem Ziellaufwerk.
Zwischenordner nicht verändern oder löschen, solange ein Auftrag offen ist. Aufträge
enthalten Pfade und Prüfwerte, keine Passwörter oder Tokens. Undo ist nach Abschluss
oder Abbruch möglich; nicht verifizierbare Ziele bleiben gegen automatisches Undo geschützt.

Diese Fortsetzung gilt für **Kopieren und Verschieben**. Verschieben auf demselben
Laufwerk verwendet möglichst Umbenennen. Über Laufwerksgrenzen wird erst vollständig
kopiert und geprüft; die Quelle wird danach in einem privaten Quell-Zwischenordner
`.OpenCommanderMove-*` schrittweise bereinigt. Bei einer Pause während der Bereinigung
bleibt das vollständige Ziel erhalten. Geänderte Quelldaten werden nicht gelöscht.
Ein Abbruch während dieser Phase lässt den Auftrag zur sicheren Fertigstellung gespeichert;
**Fortsetzen** schließt die Bereinigung ab. Entpacken und andere Mutationen müssen vor
dem Schließen abgeschlossen oder regulär abgebrochen sein. Nach einem Prozessabsturz
bleiben uneindeutige Veröffentlichungen oder Quell-Umbenennungen zur manuellen Prüfung
stehen. Das ersetzt keine Sicherung bei Stromausfall.

## Online-Orte ohne Sync-App

**Einstellungen / Orte → Online-Orte verwalten …**
führt durch die Einrichtung von OneDrive, Google Drive, Dropbox, iCloud Drive,
FTP, explizitem FTPS oder SFTP. Linux verwendet dazu das installierte `rclone` und
FUSE, keinen portierten Swift-/Graph-Client. Die Konfiguration läuft als grafischer
Frage-/Antwort-Assistent. Für OneDrive, Google Drive und Dropbox öffnet OpenCommander den Standardbrowser
über Qt mit Desktop-Aktivierungsanforderung. Unter Wayland wird die native
Qt-Plattform bevorzugt; der Desktop entscheidet über die Vordergrundaktivierung.
Während der Anmeldung kann **Anmeldebrowser nach vorne holen** den Browser erneut öffnen.
Eine Anmeldung bei Benutzerkonten wird nicht ohne Benutzereingabe durchgeführt.
**Mit Microsoft im Browser anmelden** startet OneDrive-OAuth direkt; technische
Client-ID-/Secret-Fragen entfallen. Nach erfolgreicher Anmeldung und Laufwerkswahl
wird der Ordner automatisch im aktiven Bereich geöffnet. **Erneut anmelden**
aktualisiert abgelaufene Verbindungen; vorher einen aktiven Mount trennen.

**iCloud: Mit Apple-ID verbinden** benötigt das reguläre Apple-Passwort und 2FA
(vertrauenswürdiges Gerät oder SMS). App-spezifische Passwörter werden nicht akzeptiert.
Ein Browserlogin allein verbindet iCloud nicht mit diesem Backend: Apple wird über
SRP und einen Vertrauens-Token angebunden, nicht über Microsoft-artiges OAuth.
Web-Zugriff auf iCloud-Daten muss im Apple-Konto erlaubt sein; gegebenenfalls den
Zugriff auf einem vertrauenswürdigen Gerät bestätigen. Siehe
[rclone iCloud-Anmeldung](https://rclone.org/iclouddrive/).

Ein aktuelles Backend wird bei Bedarf automatisch **nur für OpenCommander** geladen:
`~/.local/share/opencommander/runtime/rclone` (beziehungsweise unter `XDG_DATA_HOME`).
Download erfolgt vom offiziellen rclone-Server über HTTPS; vor Ausführung wird die
veröffentlichte SHA-256-Prüfsumme geprüft. System-rclone und bestehende Mounts werden
nicht ersetzt. Am 10.10.2026 wurde rclone 1.75.2 installiert und mit dem Assistenten geprüft.
Für diesen ersten Download ist Internetzugang erforderlich. Abbrechen stoppt die
Vorbereitung/Anmeldung; Passwörter, Bestätigungscodes und Tokens bleiben verdeckt.

Verbindungen und Zugangsdaten werden im Benutzerprofil gespeichert. Die gespeicherten
Namen erscheinen nach einem Neustart auch ohne aktiven Mount links in der Seitenleiste.
Ein Klick verbindet und öffnet den Ort, ohne erneut die gesamte Einrichtung zu verlangen.
Abgelaufene oder widerrufene Zugangsdaten können eine erneute Anmeldung erfordern.
Direkter Online-Zugriff ist keine kontinuierliche Echtzeitansicht: Ordnerlisten werden
für 5 Sekunden gecacht, **Strg+R** lädt die Ansicht neu (innerhalb des Caches ggf.
noch dessen Stand).

Nach Einrichtung beziehungsweise **Im aktiven Bereich öffnen**: der Online-Ort erscheint als
Dateisystem-Mount im selben Dateibereich, mit Navigation, Filter, Vorschau,
Eigenschaften, Zwischenablage, Drag-and-drop, ZIP und Commander-Werkzeugen.
Diese Operationen können Downloads auslösen. Bild-Thumbnails werden für sichtbare Zeilen auch auf Remote-Mounts geladen,
mit maximal zwei gleichzeitigen Online-Anfragen. Dazu können ganze Bilder
heruntergeladen werden (maximal 32 MiB je Thumbnail). Videos erhalten online
keine automatischen Thumbnails. Die Bildvorschau lädt sequenziell in eine private
Temporärdatei (maximal 128 MiB), zeigt Downloadfortschritt und entfernt die Datei
nach dem Dekodieren. Pfeilnavigation/Schließen bricht laufende Downloads ab;
30 Sekunden ohne übertragenen Block beziehungsweise 180 Sekunden insgesamt
beenden einen blockierten Download. Der Bilddecoder bleibt auf 64 MiB begrenzt.

Die separate Konfiguration liegt unter `~/.local/share/opencommander/online/rclone.conf`
(bei eigenem Profil entsprechend dort), Verzeichnisrechte 0700, Dateirechte 0600.
Passwörter/OAuth-Tokens werden nicht in Prozessargumenten oder Logs ausgegeben;
Konfigurationsantworten werden über die Kindprozess-Umgebung übergeben.
**Für Cloud-Zugangsdaten ist dies keine Schlüsselbund-Verschlüsselung.** rclone-Passwortverschleierung ist
keine Verschlüsselung. Die bestehende globale rclone-Konfiguration wird nicht verändert.
Mounts liegen neben dem Profil in `opencommander-online-mounts`, damit die
Schutzregeln für Wiederherstellungsmetadaten keine Remote-Dateiaktionen blockieren.
Mounts bleiben nach Schließen der App verfügbar; es wird keine Synchronisation gestartet.

Für Server: **Einstellungen / Orte → Verbindungen verwalten → SFTP / FTP / FTPS – Passwort oder SSH-Key** oder
in **Online-Orte** das Protokoll auswählen. Server ohne `sftp://` eingeben,
Port (SFTP 22, FTP/FTPS 21), Benutzer und Anmeldeart wählen, dann **Verbinden und
öffnen**. Ein optionaler Startordner begrenzt den eingebundenen Bereich; leer
bedeutet Benutzerordner. Nach Neustart links den gespeicherten Namen öffnen.
Ohne gespeicherte Zugangsdaten erscheint das vorausgefüllte Formular erneut.
**Erneut anmelden** erlaubt Änderungen nach dem Trennen.

Server-Passwörter und Key-Passphrasen werden standardmäßig nur während der
App-Sitzung gehalten. Optional speichert **Linux-Schlüsselbund** sie über
Secret Service; erforderlich sind Host-Python mit PyGObject, `gir1.2-secret-1`
und ein laufender Schlüsselbund wie GNOME Keyring. Fehlt er oder wird der Zugriff
abgelehnt, wird nichts ersatzweise im App-Profil gespeichert. Neue Serverprofile
enthalten keine Passwortfelder. Bisherige Serverprofile behalten ihre alten
rclone-Zugangsdaten, bis sie über das neue Formular bearbeitet werden.

SFTP unterstützt Passwort, private OpenSSH-/PEM-Datei oder einen vorhandenen
SSH-Agent. Schlüsseldateien bleiben unverändert an ihrem Ort und müssen private
Dateirechte besitzen (`chmod 600 <Schlüsseldatei>`). Bei verschlüsseltem OpenSSH
entsperrt die Passphrase den Schlüssel im vorhandenen Agent für eine Stunde;
der Schlüssel ist dann auch anderen lokalen SSH-Clients dieses Benutzers
verfügbar. Nach Ablauf bei Bedarf trennen und erneut verbinden. PEM-Passphrasen
werden direkt an das Backend übergeben. PuTTY `.ppk` vorher in OpenSSH exportieren.
Reine SCP-Server ohne SFTP-Unterstützung werden nicht unterstützt.

FTPS verlangt explizites TLS und Zertifikatsprüfung. SFTP prüft
`~/.ssh/known_hosts` vor der Anmeldung: neue Server zeigen SHA-256-Fingerabdrücke,
die unabhängig beim Betreiber verglichen und bestätigt werden müssen.
Geänderte bekannte Schlüssel werden abgewiesen und niemals automatisch ersetzt.
SFTP führt keine entfernten Shell-Kommandos aus. FTP warnt vor unverschlüsselter
Übertragung und benötigt Benutzer/Passwort, keine SSH-Keys.

Während Kopieren/Verschieben bleiben Navigation, Öffnen, Vorschau, Eigenschaften,
Suche und Einstellungen verfügbar. Weitere Kopier-/Verschiebeaufträge werden mit ihren
jetzigen Quell-/Zielpfaden gespeichert und nach der eingestellten Parallelität gestartet.
Die aufklappbare Übersicht zeigt eigene Kontrollen und Fortschrittsdaten pro Auftrag.
Undo und Trennen
bleiben bis zum Abschluss gesperrt. Beim Navigieren nach oben wird der gerade
verlassene Ordner automatisch markiert und sichtbar gemacht, auch in ZIPs.

**Trennen** hängt einen app-eigenen Mount ohne Zwang aus, sofern kein Dateivorgang läuft. Entfernen einer Online-
Verknüpfung entfernt weder die gespeicherten Zugangsdaten noch Serverdateien.

App-eigene rclone-Mounts nutzen einen gesonderten, auf vorhandene Ziele prüfenden
Umbenennungspfad, da rclone kein `RENAME_NOREPLACE` unterstützt. Dieser bietet
**keine atomare Absicherung gegen andere gleichzeitig schreibende Clients**.
Diese Ausnahme gilt für registrierte app-eigene Online-Mounts und anhand von
/proc/self/mountinfo erkannte fuse.rclone-Mounts;
gewöhnliche lokale Laufwerke und andere externe Mounts behalten den bisherigen Schutz.
Der VFS-Schreibcache ist ausgeschaltet: es gibt keine verzögerte Upload-Warteschlange.
Die Mac-Graph-spezifischen ETag-/If-Match-Bedingungen und dessen OneDrive-Papierkorb
werden dadurch nicht nachgebildet. Entfernen verwendet die eigenen Rücknahmekopien.
Die Linux-Datei-Historie und Inhaltsprüfung bleiben aktiv; bei Netzwerkfehlern
können unvollständige temporäre Online-Dateien zurückbleiben.

Feature-Vergleich und Prüfgrenzen: [PARITY.md](PARITY.md).

## USB, Netzwerk, Google Drive und OneDrive

**Einstellungen / Orte → Verbindungen verwalten …** zeigt eingehängte Laufwerke
und noch nicht eingebundene Volumes.
Doppelklick oder **Öffnen / Einbinden** öffnet einen eingebundenen Ort im aktiven
Bereich. Ein noch nicht eingebundenes Volume wird zuerst eingebunden; anschließend
kann es geöffnet werden. **Trennen / Auswerfen** verwendet die sichere Linux-
Auswerf-Funktion, ohne erzwungenes Unmount. Während eines Dateivorgangs ist dies gesperrt.
Die Liste und die Schnellzugriffe werden alle fünf Sekunden aktualisiert.

Netzlaufwerke mit `smb://server/freigabe`, `sftp://server/pfad` oder
`davs://server/pfad` verbinden. Zugangsdaten werden im Systemdialog eingegeben.
OpenCommander speichert keine Passwörter oder OAuth-Tokens.

**Google Drive / OneDrive – Konto hinzufügen** öffnet GNOME Online-Konten.
Google beziehungsweise Microsoft 365 hinzufügen und den Dateizugriff aktivieren.
Die Bereitstellung hängt von den installierten GNOME/GVFS-Providern ab.
Vorhandene rclone-Mounts, auch außerhalb von `/media`, werden ebenfalls erkannt;
rclone-Konten werden weiterhin mit rclone eingerichtet. Lokale Sync-Ordner bleiben
über die Pfadeingabe erreichbar.

Für diese Desktop-Integrationen benötigt auch das portable Paket die Systemdienste.
Unter Ubuntu 24.04 sind dies `python3`, `python3-gi`, `gir1.2-gtk-4.0`,
`gvfs-backends`, `gvfs-fuse`, `udisks2`, `gnome-online-accounts` und
`gnome-control-center`. Ohne diese Dienste funktionieren lokale Dateiaktionen weiter;
der Verbindungsdialog meldet fehlende Unterstützung. Auf anderen Desktops können
bereits eingebundene Orte genutzt werden; der Konto-Assistent benötigt GNOME.

GVFS stellt Netzwerk- und Cloud-Orte als lokale FUSE-Pfade bereit. Schreibzugriffe
hängen von den Rechten und Dateisystemfunktionen des Providers ab. Unterstützt ein
Provider die für sichere Dateiaktionen benötigten atomaren Umbenennungen nicht,
bricht die Aktion mit einem Fehler ab. Für andere externe Mounts gibt es keinen Überschreib-Fallback. Die ausdrücklich eingerichteten app-eigenen Online-Mounts verwenden den oben beschriebenen Provider-Pfad.
Eine lokale Erfolgsmeldung ist keine Bestätigung einer abgeschlossenen Cloud-
Synchronisation; diese wird vom jeweiligen Provider verwaltet.

## Eigenschaften und Cloud-Prüfung

Rechtsklick → Eigenschaften bezieht sich auf die angeklickte Datei. Metadaten werden
frisch und im Hintergrund gelesen. Für GVFS-NAS-Pfade wird die ursprüngliche
SMB-/Provider-Adresse abgefragt, damit fehlende FUSE-Metadaten nicht als falsche
Größe, Rechte oder Eigentümer ausgegeben werden. Nicht gemeldete Werte bleiben
explizit unbekannt. POSIX-Rechte können bei NAS und Cloud synthetisch sein.

Ordner zeigen nicht mehr die Größe ihres Verzeichniseintrags als Inhaltsgröße.
**Ordnergröße berechnen** liest auf Wunsch rekursiv, ohne symbolischen Links zu folgen.
Nach zehn Sekunden oder 100.000 Einträgen wird ein Teilergebnis gekennzeichnet;
Zugriffsfehler zählen ebenfalls als unvollständig. Einzelne hängende Provider-
Anfragen werden nach 15 Sekunden beendet. ZIP-Eigenschaften beziehen sich auf den
gewählten Archiveintrag, nicht auf die Größe des gesamten Archivs.

Google Drive/OneDrive können über vorhandene GVFS-/rclone-Mounts benutzt werden.
Dropbox-Sync-Ordner werden auch über die lokale `.dropbox/info.json` erkannt.
iCloud-Ordner und vorhandene iCloud-Mounts werden ebenfalls angezeigt; eine eigene
Apple-Anmeldung ist nicht implementiert. Für einen iCloud-Drive-Mount mit rclone
ist mindestens eine Version mit dem `iclouddrive`-Backend nötig (ab 1.69).
Siehe [rclone iCloud Drive](https://rclone.org/iclouddrive/),
[rclone OneDrive](https://rclone.org/onedrive/) und
[Dropbox-Systemanforderungen](https://help.dropbox.com/installs/system-requirements).
Das Vorhandensein eines Ordners bestätigt weder eine aktive Synchronisation noch
Schreibfähigkeit oder eine erfolgreiche Anmeldung beim Cloud-Anbieter.

## Dateisicherheit und Grenzen

Kopien werden in einem privaten temporären Verzeichnis auf dem Ziellaufwerk
vorbereitet und mit Linux `renameat2(RENAME_NOREPLACE)` veröffentlicht. Das
verhindert das Überschreiben zwischenzeitlich neu angelegter Ziele. Bei Ersetzen
bleibt die vorherige Version als Wiederherstellungskopie erhalten. Scheitert nach
einem vollständigen Kopieren das Löschen der Quelle, bleibt das vollständige Ziel
stehen; die Fehlermeldung nennt den Ort.

Rückgängig vergleicht Inhalt, Metadaten und Dateidentität. Nachträgliche Änderungen
oder belegte ursprüngliche Pfade stoppen die betroffene Rücknahme. Bereits erledigte
Teilrücknahmen werden gespeichert und bei einem erneuten Versuch nicht wiederholt.
Symbolische Links werden beim Kopieren als Links erhalten, nicht rekursiv verfolgt.
ZIP-Pfade mit `..`, absoluten Pfaden, doppelten Namen oder symbolischen Links werden
abgelehnt. ZIP-Entpacken ist auf 100.000 Einträge und insgesamt 4 GiB begrenzt;
verschlüsselte ZIP-Dateien werden nicht unterstützt.

**Entfernen verwendet eigene `.OpenCommanderTrash-*`-Wiederherstellungsordner,
nicht den System-Papierkorb.** Zurückgenommene Kopien liegen in
`.OpenCommanderUndo-*`; ersetzte Originale gegebenenfalls in
`.OpenCommanderTransfer-*/previous`. Diese Ordner bleiben auf dem jeweiligen
Laufwerk erhalten und belegen Speicher, bis sie bewusst manuell entfernt werden.
Die Historie und Einstellungen liegen in `$XDG_DATA_HOME/opencommander`, gewöhnlich
`~/.local/share/opencommander`. Entpackte externe Vorschaukopien bleiben dort unter
`previews`, damit externe Anwendungen sie weiter bearbeiten können.

Inhaltsprüfungen lesen Dateien erneut und können bei großen Dateien dauern.
Ein Abbruch betrifft die nächste Kopier-/Archiviteration; eine bereits begonnene
Quellbereinigung wird nicht absichtlich unterbrochen. Wiederherstellung ist kein
Dateisystem-Journal und kein Schutz gegen Stromausfall oder beliebige gleichzeitige
Änderungen durch andere Programme. Ein Backup bleibt notwendig.

Linux verwendet vorhandene Treiber und Zugriffsrechte. NTFS kann geschrieben
werden, wenn das Laufwerk mit einem schreibfähigen Linux-Treiber (beispielsweise
ntfs3 oder ntfs-3g) schreibbar eingebunden ist und die Benutzerrechte es erlauben.
OpenCommander bindet ein schreibgeschütztes NTFS-Laufwerk nicht automatisch
schreibbar um; ein NTFS-Schreibtest gehört nicht zum unten dokumentierten Testumfang. Die experimentelle macOS-
NTFS-Erweiterung wird nicht portiert, installiert oder aktiviert. Quick Look und vollständige Parität
mit allen Mac-Funktionen gehören nicht zu dieser ersten Linuxversion.

## Prüfen und paketieren

```bash
linux/.venv/bin/python -m pip install -r linux/requirements-dev.txt
QT_QPA_PLATFORM=offscreen linux/.venv/bin/python -m pytest linux/tests -q
QT_QPA_PLATFORM=offscreen ./linux/run.sh --smoke-test
./linux/build.sh
```

Das Paketierungsskript setzt Ubuntu/Debian mit `apt-get` und `dpkg-deb` voraus.
Es lädt die kleine XCB-Cursor-Bibliothek herunter und entpackt sie ausschließlich
im Bauverzeichnis, ohne Systempakete zu installieren.

Die Paketierung erzeugt `linux/dist/opencommander/` und ein Archiv plus Prüfsumme
unter `linux/artifacts/`. Mit `OPENCOMMANDER_BUILD_ROOT` und
`OPENCOMMANDER_DIST_ROOT` können Zwischen- und Paketverzeichnisse auf ein anderes
Laufwerk gelegt werden. Das Bundle enthält die Python-Anwendungsquellen,
Abhängigkeitsversionen und Lizenzhinweise; siehe `THIRD-PARTY.md`.


Kopieren/Verschieben ermittelt im Hintergrund zuerst Dateizahl und Datenmenge.
Die Anzeige enthält Prozent, bearbeitete/gesamte Bytes und Dateien, aktuellen Namen,
verstrichene Zeit, mittlere Rate und eine geschätzte Restzeit. Ordnergrößen können
bei Änderungen durch andere Programme von der Vorbereitung abweichen. Gleichzeitige
Änderungen anderer Cloud-Clients werden dadurch nicht verhindert. Upload-Abschluss
und Prüfung bleiben unter 100 Prozent, bis der ganze Vorgang erfolgreich abgeschlossen
ist; die Restzeit schätzt nur den verbleibenden Datentransfer. Bei Umbenennungen auf
demselben Laufwerk zählen die angezeigten Bytes die logisch verschobenen Daten.
Die Darkmode-Checkbox steht im Kopfbereich und speichert ihre Auswahl.

### NAS/GVFS-Kompatibilität (0.3.15)

Auf erkannten GVFS-/rclone-Mounts blockieren ausdrücklich nicht unterstützte
`fsync`-/Metadatenfunktionen die Inhaltskopie nicht. Zeitstempel und Dateirechte
werden getrennt versucht; Einschränkungen stehen im Transferabschluss und in der
Historien-Info. Ohne fsync bestätigt OpenCommander nicht die Dauerhaftigkeit auf
dem Server. Flush/Schließen müssen gelingen; echte Schreib-, Verbindungs-, Rechte-
und Speicherplatzfehler bleiben Fehler. Lokale Dateisysteme bleiben strikt.
GVFS-Umbenennungen ohne RENAME_NOREPLACE prüfen das Ziel vorab innerhalb derselben
Freigabe; gegenüber anderen gleichzeitig schreibenden Clients ist dies nicht atomar.

### Cloud-Start und Ladegrenzen (0.3.15)

Eingerichtete Cloud-Mounts laden ihre Ordnerliste direkt über das Provider-Backend,
statt beim Start auf einen möglicherweise blockierten FUSE-Daemon zu warten.
Die Ladeanzeige zeigt verstrichene Sekunden. Cloud-Abfragen enden spätestens
nach 30 Sekunden; bei Fehler/Abbruch ist „Erneut laden“ verfügbar. Die Oberfläche
bleibt navigierbar und alte Ergebnisse überschreiben keinen neuen Ordner.
Dateioperationen und Vorschau verwenden weiterhin den Mount. Die Erreichbarkeit
der Cloud hängt vom Anbieter, Netz und gültiger Anmeldung ab; bei abgelaufener
Anmeldung unter „Online-Orte“ erneut anmelden. Plattformseitig fehlendes
No-follow-chmod wird beim Kopieren als Metadatenhinweis behandelt, ohne Links
zu folgen oder Inhaltsfehler zu verbergen.

### Archive (0.3.15)

ZIP, TAR, TGZ/TAR.GZ, TAR.BZ2, TAR.XZ/TAR.ZST, 7z und RAR lassen sich per
Doppelklick wie Ordner öffnen. In Unterordner navigieren, einzelne Dateien ansehen
oder mit F5/Entpacken in den anderen Bereich kopieren; Entpacken bleibt über die
Historie rückgängig machbar. Archivänderungen und Verschieben aus Archiven bleiben
schreibgeschützt. Archiv-Erstellung erzeugt weiterhin ZIP.
Libarchive und die Python-Anbindung sind im portablen Paket enthalten. Grenzen:
100.000 Einträge, insgesamt 4 GiB unkomprimiert, Vorschau 128 MiB; keine
Links/Spezialdateien oder Pfade außerhalb des Zielordners. Kein Passwort-Assistent
für verschlüsselte Archive; je nach Format/Variante wird eine Fehlermeldung angezeigt.
Rechtsklick in eine leere Ordnerfläche bietet Neuer Ordner, Einfügen und Aktualisieren.

Online-Videos und Audio werden vor der Wiedergabe lokal zwischengespeichert,
damit Wiedergabe und Springen in der Zeitleiste nicht von einzelnen langsamen
Netzwerkzugriffen abhängen. Die Vorschau zeigt Prozent, übertragene MiB, Dauer
und Geschwindigkeit; „Laden abbrechen“ beendet den Vorgang. Schließen oder
Wechseln entfernt den privaten Zwischenspeicher. Grenze: 2 GiB je Medium,
30 Sekunden ohne Fortschritt und 15 Minuten insgesamt. Die Wiedergabe beginnt
erst nach dem vollständigen Laden; ausreichend lokaler temporärer Speicher ist
nötig. Bildvorschauen behalten ihre kleineren Downloadgrenzen.

### Cloud-Aktionen im Kontextmenü

In gespeicherten Google-Drive-, OneDrive-, Dropbox- und iCloud-Mounts erscheint
bei Dateien und Ordnern ein Online-Untermenü. „Teilen mit Link“ erstellt oder
holt bei Drive/OneDrive/Dropbox einen öffentlichen Freigabelink. Der Dialog
erklärt den Zugriff vor „Link erstellen“; Kopieren und Öffnen erfolgen separat.
Bei OneDrive werden Leserechte angefordert. Es gibt kein automatisch gesetztes
Ablaufdatum. Der Dienst bzw. die Organisation kann öffentliche Freigaben sperren.
Bei iCloud erfolgt die Freigabe über die Provider-Website. Der Browserzugang
öffnet die Cloud-Startseite; dort gegebenenfalls anmelden und das Objekt wählen.
„Online-Pfad kopieren“ kopiert den Pfad innerhalb des Cloud-Speichers.

Linkanfragen laufen mit Ladeanzeige außerhalb des GUI-Threads und sind auf
30 Sekunden begrenzt. Schließen bricht die Anfrage ab, kann aber eine bereits
beim Dienst angelegte Freigabe nicht zurücknehmen. Freigaben und Rechte auf
der Website des Dienstes verwalten. Keine automatische Freigabe beim Öffnen
des Menüs und kein persönlicher Cloud-Inhalt in automatisierten Tests.
Backendgrundlage: https://rclone.org/commands/rclone_link/

Gespeicherte Orte links werden mit einem einfachen Klick direkt geöffnet.
Noch nicht eingebundene Online-Orte verbinden sich im Hintergrund. Die Optionen
sind über Rechtsklick auf den Ort → „Bearbeiten“ erreichbar. Dort kann der
Anzeigename ohne neue Anmeldung gespeichert werden; Serverdaten werden geladen.
„Erneut anmelden“ ändert die Cloud-Anmeldung. Änderungen an eingebundenen
Server-Verbindungen erst nach „Trennen“ speichern. Nicht gespeicherte
Server-Passwörter werden beim Öffnen separat abgefragt.

Die Kopfzeile jedes Dateibereichs zeigt bei Online-Orten den gespeicherten
Verbindungsnamen, auch innerhalb von Unterordnern.

Angeschlossene, vom Desktop erkannte einbindbare Datenträger erscheinen auch
vor dem Einbinden in der Ortsliste. Ein Klick bindet sie im Hintergrund ein
und öffnet sie direkt. Nötige Systemfreigaben/Passwörter erscheinen im
Desktop-Dialog. Bereits eingebundene Datenträger zeigen ihren Laufwerksnamen,
auch im Dateibereich. Die regelmäßige Desktop-Abfrage aktualisiert die Liste
nach Anschließen oder Entfernen. Unformatierte Datenträger ohne einbindbares
Dateisystem werden durch diese Funktion nicht formatiert.

Externe rclone-Mounts (beispielsweise `google-drive-live`) werden für Cloud-
Aktionen erkannt, sofern der Mountprozess dem aktuellen Benutzer gehört und
die zugehörige Konfiguration lesbar ist. Remote-Unterordner bleiben erhalten;
Zugangsdaten werden nicht in OpenCommander-Profile kopiert. Namespace-Overrides
wie `--drive-shared-with-me` oder ein abweichendes Root-ID-Flag werden aus
Sicherheitsgründen nicht automatisch für Freigabelinks übernommen. Die Liste
wird asynchron aus dem Backend gelesen. Mount und Quelldateien bleiben bestehen.

Bei temporären Cloud-Fehlern oder Abfragelimits werden lesende Ordnerabfragen
höchstens dreimal mit Wartezeit wiederholt, insgesamt höchstens 30 Sekunden.
Parallel angeforderte identische Listen teilen sich eine Abfrage. Bis zu 32
Listen bleiben ausschließlich im Sitzungsspeicher. Nach einem Verbindungsfehler
kann eine höchstens fünf Minuten alte Liste angezeigt werden: mit Alter,
Fehlerhinweis und „Erneut laden“. Das ist kein Offline-Dateispeicher; Datei-
aktionen benötigen weiterhin die Verbindung. Bei Anmelde-/Berechtigungsfehlern
wird keine alte Backend-Liste verwendet. Automatische Aktualisierungen sind
auf drei Versuche nach 10/20/30 Sekunden begrenzt und stoppen beim Ordnerwechsel,
Abbrechen oder Schließen. Uploads und Freigaben werden nicht blind wiederholt.

Google Drive kann wegen des gemeinsam genutzten rclone-OAuth-Clients `Quota
exceeded / rateLimitExceeded` zurückgeben, obwohl der Mount weiter arbeitet.
Die [rclone-Dokumentation](https://rclone.org/drive/#making-your-own-client-id)
kündigt die Einstellung dieses geteilten Clients im Jahr 2026 an. Für dauerhaften
Zugriff unter **Einstellungen / Orte → Online-Orte verwalten → Google Drive**
eine eigene Google-OAuth-Anwendung vom Typ **Desktop-App** einrichten und
Client-ID sowie Client-Secret eingeben; anschließend den Zugriff im Browser
freigeben. Beides bleibt im privaten Backend-Profil; das Secret steht weder
in den UI-Einstellungen noch in Prozessargumenten. Bei einem Wechsel des
Clients wird ein bisheriger Token verworfen. Ohne neue Werte bleibt eine
vorhandene eigene Client-Konfiguration erhalten. Externe rclone-Mounts verwenden
weiter ihre externe Konfiguration; deren OAuth-Client muss im zugehörigen
rclone-Profil geändert werden, nach Abschluss laufender Übertragungen.

Der Ordnerbaum ist standardmäßig breiter, lange Namen können horizontal
gescrollt werden. Die eingestellte Breite wird je Bereich gespeichert. Beim
Drag-and-drop zeigt eine Karte am Mauszeiger Dateiname, Anzahl und Modus.
