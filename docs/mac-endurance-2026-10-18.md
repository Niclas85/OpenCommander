# Dauerlauf und ergänzende Mac-Abnahme — 18. Oktober 2026

Umgebung: macOS 15.6 (24G84), arm64, 16 GiB RAM, zehn logische CPUs.
Andere Host-Prozesse liefen weiter; dies ist kein isolierter Benchmark-Rechner.

## Abgeschlossener Zweistundentest

Neustart des Testprozesses: **07:42:23 UTC / 09:42:23 Zürich**.
Status: `/private/tmp/OpenCommander-Endurance-LeZNRg/status.json`.
Geforderte monotone Laufzeit: 7.200 Sekunden. Ein Abschluss ist erst mit
`status: passed`, Endprotokoll und Prozess-Exit 0 bestätigt.

Ein langlebiger Prozess mit vier unabhängigen Strängen und acht langlebigen
produktiven `CloudFileClient`-Instanzen. Isolierte dateibasierte Testtransporte
injizieren Netzfehler und echte Task-Abbrüche. Jeder Zyklus prüft Vorbereitung,
Quellerhalt, erneutes Öffnen des Wiederaufnahmejournals, Cloud-zu-Cloud-
Verschieben, exakten Zielinhalt, serialisierte Rücknahme und wiederhergestellte
Quelle. Jeder dritte Zyklus enthält einen tatsächlichen laufenden Abbruch.
Keine Host-Netzwerkänderung, keine echten Provider-Ausfälle und kein Eingriff
in bestehende Konten. Der Test ist **kein zweistündiger Live-Internet-Test mit
vier echten Provider-Konten und kein durchgehender GUI-Langzeittest**.

Der kurze 15-Sekunden-Vorlauf bestand. Der erste 7.200-Sekunden-Versuch
(`/private/tmp/OpenCommander-Endurance-fhkEyd`) scheiterte nach **1.658,6 s**
mit NSCocoaErrorDomain 640 / ENOSPC: Macintosh HD voll. Jeder Strang hatte
287 vollständige Zyklen, aber dieser Versuch ist ausdrücklich **fehlgeschlagen**,
nicht als zweistündiger Lauf akzeptiert. Der Prozess verwendete zuletzt
19,8 MB maximalen RSS und drei offene Deskriptoren; seine isolierten Daten
belegten rund 1,2 MB. Host-Swap lag über 12 GB. Die Daten belegen keinen
Cloud-Prozess-Speicheranstieg als Ursache des vollen Host-Datenträgers.

Vier abgeschlossene, nicht eingehängte eigene NTFS-Testabbilder wurden
verlustfrei zu `test.ntfs.gz` komprimiert und mit `gzip -t` geprüft. Sie lassen
sich wieder auspacken; Quellen, Logs, Profile und App-Sicherungen blieben
erhalten. Der Benutzer schaffte zusätzlich freien Speicher. Vor dem zweiten
Versuch waren 6,2 GiB, anschließend über 8 GiB frei.

Der neu von null gestartete vollständige Lauf **bestand nach 7.204,059 Sekunden**
um **09:42:27 UTC / 11:42:27 Zürich**, `status: passed`, alle vier Stränge
`completed`, keine aktiven Requests, leeres Fehlerfeld und Prozess-Exit 0.
Das Endprotokoll enthält den PASS. Zeiten beider Versuche werden nicht addiert.
Zyklen pro Strang: **1.467 / 1.465 / 1.465 / 1.463**, zusammen **5.860**;
5.860 injizierte Ausfälle, 1.955 Pause-Vorgänge und 1.913 tatsächlich abgebrochene
Requests. Insgesamt 1.536.163.840 bytegenau geprüfte Bytes (einschließlich
Rücknahme), maximal 27.525.120 B RSS, zuletzt drei offene Deskriptoren unter 256
und 6.743.379.968 B freier Host-Speicher. Die Zahl der Requests ist keine Zahl
unabhängiger GUI-Testfälle. Der freie Speicher wurde alle fünf Sekunden
protokolliert. Native Bedienfälle wurden separat getestet.
`caffeinate -i` verhindert nur während des
Testprozesses den automatischen Ruhezustand; Sperre und Sicherheit bleiben
unverändert. Der Mac wird nicht neu gestartet.

Quellen: `ios/tests/CloudClientTests/Endurance.swift`,
`tests/run-cloud-endurance-tests.sh`.
Protokolle: `ntfs/NTFS3G/.build-native/endurance-2h-20261018.log` (fehlgeschlagen),
`ntfs/NTFS3G/.build-native/endurance-2h-r2-20261018.log` (neuer Lauf).
Neuer Build: `/private/tmp/OpenCommander-Endurance-Build-8TFtyW`.
Die protokollierten Cloud-/Remote-/OneDrive-/Undo-Implementierungen bleiben
während dieses Laufs unverändert. Die gleichzeitig bearbeitete Warteschlange,
Archiv-UI und ein ausschließlich die Warteschlangen-UI betreffender DE/EN-
Hinweistext werden getrennt neu gebaut/geprüft; letzterer ist die einzige
nachträgliche Änderung in der mitprotokollierten Localization.swift.

## Zusätzlich tatsächlich bedient

Isolierte native App und Testwurzel:
`/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-2sdjC5`.

- F5 kopierte `Alpha.txt` plus `Nested/Child.txt` trotz aktivem Verschieben-
  Schalter. Quelle und Ziele unabhängig bytegenau verglichen.
- F6 verschob `Image1.jpg` trotz Kopieren-Schalter. Quelle nicht mehr am
  ursprünglichen Pfad; Ziel-SHA256
  `2afd73e33a1d5318e331bbe60944e7565a80662549797f3b80deee692313d6eb`.
  Toolbar-Undo stellte die Quelle mit exakt diesem Hash wieder her und
  entfernte das sichtbare Ziel.
- Zwei Ordnerwechsel mit unverändertem rechten Bereich; zweimal zurück,
  einmal vorwärts; neue Navigation verwarf den alten Vorwärtszweig.
- Command-Umschalt-G öffnete einen Pfad mit Leerzeichen. Ein fehlender Pfad
  meldete „Path not found“ und behielt den tatsächlich geöffneten alten Pfad
  bei, statt alte Inhalte als neuen Ordner anzuzeigen. Command-L ist kein
  implementierter Mac-Kurzbefehl und wurde nicht als Erfolg gezählt.
- Namensfilter `image` zeigte sechs Bilder. Command-A wählte genau sechs;
  Command-Auswahl zweier Einträge und Umschalt-Bereichsauswahl von vier
  Einträgen waren korrekt. Escape im Filterfeld löschte den Filter; außerhalb
  des Felds löscht Escape die Auswahl.
- Name/Größe/Datum je zweimal sortiert und sichtbare Reihenfolge kontrolliert.
  Die Ansicht virtualisiert die letzte Zeile; der AX-Auszug allein ist keine
  vollständige Prüfung aller Metadaten sämtlicher Dateien.
- Versteckte Datei erschien nach Einblenden (16 statt 15 Einträge), verschwand
  nach Ausblenden. Extern angelegte `Externally Added.txt` erschien nach
  Command-R genau einmal (Filter: ein Treffer aus 16 Einträgen).
- Defektes JPG zeigte Dekodierfehler. Pfeil nach rechts zeigte gültiges JPG,
  zurück wieder den Fehler. Escape schloss. Binärdatei zeigte Systemvorschau;
  3,36-MB-Textdatei zeigte lesbaren Inhalt und schloss wieder.
- ZIP, TAR, TGZ, TAR.BZ2, TAR.XZ, 7z und echtes RAR5 im selben Bereich geöffnet.
  Ausgewählter ZIP-Ordner erfolgreich entpackt; Unicode-Datei unabhängig
  verglichen, leerer Unterordner erhalten.

## Entdeckte Archivfälle

System-libarchive nutzt hier für Zstandard einen externen `zstd`-Prozess.
Mit `PATH=/usr/bin:/bin` scheiterte die Initialisierung mit
„unable to run program zstd -d -qq“. Der Rechner hat zwar Homebrew-zstd;
darauf darf eine normal installierte App nicht angewiesen sein.

Ein gepinnter eingebauter Zstandard-Decoder wurde ergänzt (offiziell v1.5.7,
BSD-Lizenz samt App-Ressource). Die Sicherheitsprüfung ohne Homebrew im PATH
bestand: Unicode, leere Ordner, exakte Daten, an Inhaltsbytes erkannte
Kompression, fortlaufende Blöcke/Frames, beschädigte Daten, Ausgabebegrenzung,
64-MiB-Fensterlimit, laufender Abbruch und Aufräumen.

Der echte UI-Entpacktest für TAR/Zstandard meldete zunächst einen Fehler,
obwohl die native Dateiliste funktioniert. Diagnose: der Vergleich mittels
`standardizedFileURL` verwarf den gültigen Zielpfad im Catalyst-Laufzeitkontext.
Die gemeinsame Ausgabeprüfung vergleicht nun zuvor streng validierte lexische
Pfadkomponenten. Native TAR.ZST-Auswahl wurde danach erfolgreich entpackt:
Unicode-Inhalt unabhängig bytegenau verglichen, leerer Unterordner erhalten.
Die Ausbruchs-Gegenproben bleiben erfolgreich. ZIP verwendet dieselbe Prüfung.

Ein weiterer Abgleich mit Linux zeigte eine zusätzliche Archive-Namenshülle
im Mac-Entpacken. Die UI veröffentlicht jetzt die ausgewählten obersten
Einträge direkt, wie die Referenz; Konflikte behalten beide, Teilpublikationen
bleiben rücknehmbar. Die native Gegenprobe dieser Darstellungs-/
Veröffentlichungsänderung bestand anschließend.
Alle acht Formate wurden ohne Auswahl vollständig ins jeweils andere Ziel
entpackt, ohne zusätzliche Archivnamenshülle. Unicode-Inhalt, leere Ordner
und die RAR-Testdatei wurden unabhängig bytegenau geprüft. Zweites Entpacken
des ausgewählten Zstandard-Ordners behielt beide als `Ordner`/`Ordner (2)`;
Toolbar-Undo entfernte nur die zweite Ausgabe. Alle acht ursprünglichen
Archiv-SHA256 blieben unverändert.

Ein echter Mauszug über den freigegebenen, geschützten Testtreiber kopierte
den Zstandard-Archivordner in den leeren anderen Bereich. Unicode-Datei und
leerer Unterordner wurden unabhängig kontrolliert. Ein weiterer echter Zug
des einzelnen Unicode-Archivmitglieds in ein eigenes Finder-Testfenster
veröffentlichte exakt dieselben Bytes. Verdeckte Endpunkte wurden zunächst
vom Treiber abgelehnt (kein Mausereignis); erst nach sichtbarem Anheben und
Positionieren der Testfenster wurde die gültige Gegenprobe gezählt.

## Native Warteschlange und Korrektur

Vier unabhängige Bäume mit je 1.000 Dateien à 8 KiB. „Alle pausieren“ speicherte
zwei bereits teilweise kopierte und zwei wartende Aufträge. Ein Negativtest
entdeckte, dass eine Quelle trotzdem in den Papierkorb verschoben werden
konnte: Live-URL und gespeicherter Pfad verwendeten unterschiedliche macOS-
Alias-Schreibweisen. Reservierungsvergleich korrigiert für `/private/tmp`,
`/private/var`, `/private/etc`, abschließende Trenner, Vorfahren und Nachkommen;
gespeicherte Dateiidentitäten/Journale werden dabei nicht umgeschrieben.
Automatisierte Queue-Regression: zehn PASS-Gruppen.

Der Systempapierkorb enthielt den ersten synthetischen Lane1-Baum beim Undo
nicht mehr (ENOENT); die Ursache der externen Entfernung wurde nicht bewiesen.
Dieser Undo ist **kein Pass**. Ausschließlich der deterministische Testbaum
wurde mit 1.000 verifizierten Dateien aus seinem Ausgangsmuster rekonstruiert;
der alte Auftrag explizit abgebrochen (Teilstand erhalten), ein neuer angelegt.

Nach Neubau/Neustart blieb Lane2 mit 9 % ausdrücklich pausiert. Der erneute
Entfernen-Versuch wurde jetzt mit Reservierungshinweis abgelehnt; Quelle blieb.
Vier gültige Jobs erneut pausiert, danach „Alle fortsetzen“ mit Parallelität
1, 2 und 4 bedient. Bei Limit 2 liefen zwei, bei Limit 4 alle vier Bäume in
Planung bzw. Verifikation; alte abgebrochene Lane1 startete nicht. Einstellungen
ließen sich während der laufenden Arbeit öffnen. Anschließend wurden alle
4.000 Quelldateien mit allen 4.000 Zieldateien bytegenau verglichen: bestanden.

## Weitere Regressionen und Oberfläche

15 erneut ausgeführte native Regression-Skripte bestanden nach eingefrorenen
Quellen. Ein vorheriger Compilerlauf scheiterte, weil Localization.swift
während des Kompilierens geändert worden war; dieses Infrastrukturereignis
bleibt separat protokolliert und zählt nicht als Produkt-Pass. Zusätzlich
bestand die vollständige Swift-Sicherheitsprüfung mit `PATH=/usr/bin:/bin`.
Die echten Loopback-Protokolle FTP, FTPS, SFTP-Schlüssel und SFTP-Passwort
bestanden einschließlich Fortschritt, rekursiver Suche, Vergleich,
Umbenennung, Rücknahme, laufendem Abbruch sowie Zertifikat-/Hostkey-/
Authentifizierungs-Gegenproben. Erwartete Serverfehler im Log sind keine
erfolgreichen unsicheren Verbindungen.

Der dunkle Einstellungsdialog hat jetzt eine lesbare Navigation; Filterfelder
verwenden explizite Text-, Platzhalter- und Hintergrundfarben. Deutsche
Verzeichnisfehler zeigen eine eigene deutsche Erklärung plus unveränderlichen
Fehlercode statt einer englischen Cocoa-Satzkopie. Ein unlesbarer eigener
Testordner zeigte keine alten bedienbaren Zeilen; nach Wiederherstellen seiner
Rechte funktionierte „Erneut versuchen“ und zeigte den tatsächlich leeren
Ordner.

Die Neustart-Gegenprobe zeigte einen weiteren echten Unterschied: Sprache
und Theme blieben, aber normale Pfad-/Unterordnernavigation wurde nicht als
letzter besuchter Ordner gespeichert. Die Korrektur speichert diesen Pfad
getrennt vom bestehenden Zugriffs-Bookmark; ein besuchter Unterordner darf
keine übergeordnete Freigabe überschreiben. Die native Wiederholungsprüfung
dieser Korrektur bestand: beide gewählten Unterordner, Deutsch und Dunkelmodus
blieben nach geordnetem App-Neustart erhalten. Ein ausschließlich für die
Gegenprobe umbenannter leerer letzter Ordner führte beim nächsten Start zum
gespeicherten Ausgangsordner zurück; der andere Bereich blieb unverändert.

Die native Suche bestand mit `child` (Groß-/Kleinschreibung zunächst abgewählt),
aktivierter Groß-/Kleinschreibung (null statt einem Treffer), `Ch?ld.*` und
einem geänderten absoluten Startordner. Vollständige Trefferpfade und Öffnen
des richtigen Elternordners wurden in der Oberfläche geprüft. Ein lokaler
Vergleich erkannte gleiche, unterschiedliche und nur links vorhandene Dateien.

Mehrfach-Umbenennen: doppeltes Ziel wurde abgelehnt. `[N]-[C][E]`, Start 7,
Breite 2 und `a`→`X` ergaben die angekündigten Namen. Eine nach der Vorschau
veränderte Quelle verhinderte Anwenden; beide Ausgangsnamen und veränderte
Quellbytes blieben erhalten. Nach neuer Vorschau bestand Anwenden und danach
Toolbar-Undo. Beide Dateien wurden unabhängig per SHA256 kontrolliert.

Die 20.000-Dateien-Liste zeigte zunächst während eines Ordnerwechsels einen
weiteren Fall: Filtern konnte alte `allEntries` wieder sichtbar machen. Neue
Ordner löschen nun beide Listen; während Laden heißt die Leermeldung weiter
„Ordner wird geladen“, nicht „Keine Treffer“. Unveränderliche Namen und
Archiv-Endungen werden einmal berechnet; die bereits im Worker erzeugte
Namenssortierung wird nicht nochmals auf dem UI-Thread berechnet. Die native
Gegenprobe zeigte zunächst Laden ohne alte Zeilen und nach 3,5 s den korrekten
letzten gefilterten Eintrag. Danach 20.000 Zeilen, auf-/absteigende erste
Zeilen und Filterlöschen geprüft (letzte Beobachtung 739 ms). Dies sind
Beobachtungsobergrenzen bei warmen Host-Caches, kein kontrollierter universeller
Geschwindigkeitsvergleich mit dem vorherigen Kaltlauf (13–39 s).

Echter Drag-and-drop-Test: Ablegen auf eine Ordnerzeile publizierte exakt die
Quelldatei im betreffenden Ordner und behielt die Quelle. Fünf Sekunden an
der unteren Dateilistenkante scrollten von Folder-000 bis Row-044; fünf
Sekunden oben zurück zu Folder-000. Beide mit Escape abgebrochen, kein
gleichnamiger Export irgendwo im Zielbaum. Hover über den eigenen Baumzweig
`Target` klappte ihn auf, danach Hover über `Folder-000` auch `Child`. Der
sichtbare Anker blieb bei `Movies`/dem Testzweig; kein Rücksprung zur Mac-Wurzel.
Die Dateiliste selbst navigiert bei Hover nicht spring-loaded; das ist keine
behauptete Finder-Funktionsgleichheit und wurde nicht als Ordneröffnung gezählt.

Der TextEdit-Fenster-Test wurde zunächst vom vorhandenen Sichtbarkeitswächter
wegen verdecktem Endpunkt abgelehnt (kein Mausereignis). Eine neue rein
diagnostische Ausgabe identifiziert nur App/Geometrie und Fixture-Flag, nie
fremde Dokumenttitel/Inhalte. Ein Ablagepunkt lag unter dem 126×126-Punkte-
Fenster der Computersteuerung. Mit einem anderen tatsächlich freien Punkt
bestand anschließend der echte Zug des synthetischen TextEdit-Dokumentproxys
ins NTFS-Dateifenster: exakte Bytes, unverändertes Original. Keine Wächter-
abschwächung. Die Gegenrichtung bleibt ohne freigestellte Fenster offen;
Codex selbst wird von der Computersteuerung gesperrt und nicht über einen
anderen Weg minimiert/bedient. Der Benutzer wurde nicht blockierend um
freigestellte Testfenster gebeten. Fremde Dokumente wurden nicht geändert.

NTFS-Vorabprüfung: neue 64-MiB-Datei
`/private/tmp/OpenCommander-NTFS-Queue-x2tlCR/test.ntfs`, installierter bestehender
V2-Treiber. Engine-Gegenproben, Foundation-Datei-/Ordnerkopie, Durable-Datei/-Baum,
Pause, vollständiges Ab- und Wiederanhängen und exakte Wiederaufnahme bestanden;
Testgerät anschließend ausgeworfen. Das ersetzt nicht die abschließende
Prüfung mit dem tatsächlich neu installierten Build.

Zusätzliche native NTFS-Abnahme auf neuer eigener 64-MiB-Datei
`/private/tmp/OpenCommander-NTFS-MacUITest-1lYMLs/test.ntfs`: Ordner `NativeUI`
in der Oberfläche erzeugt; Datei plus Ordner mit F6 APFS→NTFS verschoben,
exakte Bytes und Quellrücknahme nach Publikation geprüft. Beide Toolbar-Undo
stellten APFS-Originale exakt wieder her. Danach F5 auf NTFS und F6 in der
Gegenrichtung NTFS→APFS, wieder beide Daten und zurückgenommene Quellpfade
kontrolliert. Beide Undo stellten jetzt die NTFS-Originale korrekt wieder her.
Vollständig ausgehängt, neu angehängt und alle Datei-/Ordner-/TextEdit-
Testdaten erneut bytegenau verglichen: bestanden. Gerät anschließend normal
ausgeworfen. Nur das neue Abbild wurde formatiert, nie ein physisches Gerät.

Native Eigenschaften: vorher Alpha ausgewählt, Kontextmenü auf beta zeigte
beta.txt mit 4 Bytes und exakt dessen Pfad. Dateityp-Fallback und Datum folgen
nun der gewählten UI-Sprache statt englischer Systemtexte. Gegenprobe auf
NTFS Alpha: `TXT — Datei`, `18.10.2026`, richtige Größe/Attribute und NTFS-Pfad.

Frische F5-Datei-/Ordnerkopie zeigte zwei individuelle Queue-Abschluss-Einträge
in der Historie mit exakt zugehörigen Quell-/Zielpfaden, deutscher Uhrzeit
`18.10.2026, 10:32:11` und je aktivierter Rücknahme. Filter-Gegenprobe kopierte
nur das gewählte sichtbare Bild, nicht die zuvor markierte ausgefilterte Alpha.
Explizite einzelne Zstandard-Mitgliedextraktion erhielt den relativen Pfad,
exakte Unicode-Bytes und ließ das nicht ausgewählte `Empty/` weg. Ausschneiden
und Einfügen in den Archivbereich wurden verweigert; Archiv-Hash unverändert.

## Medien und abschließender Softwarestand

Eigene begrenzte Testdaten: sechs Sekunden WAV und H.264-MP4 (Dauer unabhängig
mit AVFoundation geprüft), echter Zwei-Frame-GIF und verlustloses WebP aus
dem eigenen PNG. Der externe WebP-Encoder wurde nur zur Fixture-Erzeugung
verwendet; die App verwendet ihren eigenen Systemdecoder. PNG/WebP/GIF-Poster
erschienen korrekt, ein nur in JPG umbenanntes Binärfile meldete einen deutschen
Dekodierfehler. GIF-Animation wird ausdrücklich nicht als getestet/implementiert
behauptet; die Referenz verwendet ebenfalls Bildvorschau statt QMovie.

Video: Leertaste pausierte bei 0,791402 s; die Position blieb während Pause
stehen. Ein AX-SetValue änderte nur den dargestellten Sliderwert, nicht die
Wiedergabe — **kein Seek-Pass**. Der echte Zeitleistenklick sprang auf 1,511371 s,
danach Wiedergabe bei 1,836972 s. Ende/Leertaste war zunächst fehlerhaft; die
Korrektur sucht nun vor erneutem Play den Anfang. Native Gegenprobe: blaues
Endbild wurde nach Leertaste wieder rotes Startbild, erneute Leertaste pausierte.
Play/Pause während Warten pausiert ebenfalls statt erneut Play anzufordern.

Audio hatte zuvor absichtlich ausgeblendete AVPlayer-Bedienelemente; diese
werden jetzt auch für Audio eingeblendet. Native WAV-Gegenprobe zeigte
Play/Pause und Zeitleiste; Leertaste pausierte bei 0,3605276 s und die Position
blieb stehen. Ein AX-Slider-Press ist kein bestätigter Audio-Seek und wird nicht
als solcher gezählt. Audioqualität/Lautsprecher wurden nicht akustisch bewertet.
Wechsel auf GIF/WebP/PNG entfernte Player-Bedienelemente. Schnelle Pfeilwechsel
und beide Bereichsgrenzen blieben korrekt (1/6, 6/6); kein alter Videofehler
überschrieb das neue Bild.

Ein eigener Ein-Bild-Ordner bestand 1/1, beide Pfeilrichtungen, Löschabbruch,
bestätigtes Papierkorb-Löschen (Vorschau schließt, Ordner leer) und Toolbar-Undo.
Original-SHA256 nach Abbruch und Wiederherstellung identisch:
`6e17ddd487ce37d0c9e53f0b918ba3fc4639ffc21eaf15e039633cf1fbc5e327`.
Dies ersetzt nicht den zusätzlichen gleichzeitigen Kopierabschluss-Fall.

Native ZIP-Erzeugung mit Datei und leerem Ordner über die echte Speichermaske
im aktiven Testverzeichnis bestand. Externe ZIP-Liste: genau `Only.png` und
`Empty/`, PNG-SHA256 wie Original. Erneut im Bereich geöffnet, dreimal
schreibgeschützte Mitglied-Bildvorschau mit 1/1, Pfeilen und Schließen: bestanden,
kein Löschknopf. Mitglied-Eigenschaften zeigten `PNG — Datei`, 602 Bytes,
vollständigen `!/Only.png`-Pfad und „nur Lesen“. ZIP-Hash vor/nach allen Zyklen
identisch: `b38622904def8ab4efd230607df8b3caae2001d077e9940297dfd19c46c98ffe`.

Temporäre Archivmaterialisierungen hatten keinen Besitzer für das Ende einer
internen Vorschau. Neu registriert `PreviewTemporaryFiles` ausschließlich den
gerade neu erzeugten UUID-Unterordner, nie einen Providerpfad oder eine alte
Cache-Sammlung. Bilder geben ihn nach vollständiger Dekodierung frei; AVPlayer
hält ihn bis Wechsel/Schließen; Quick Look bindet ihn an dessen Schließcallback.
Fehler, veraltete Ergebnisse und Abbruch geben denselben Besitzer frei.
Externe „Öffnen mit“-Exporte werden nicht voreilig gelöscht, solange die
Lebensdauer der Empfänger-App unbekannt ist.

Unit-Gegenproben: eigener Root entfernt, unregistrierter Nachbar, Quelle und
gemeinsamer Elternordner erhalten. Native Gegenprobe mit ZIP-Video: während
Wiedergabe existierte genau der neue Root
`OpenCommanderPreview/7D74F98D-E3AC-4FD8-8D57-6DD862229D92/Synthetic.mp4`,
nach Escape vollständig entfernt, Originalvideo/ZIP erhalten. Nach drei
ZIP-Bildzyklen war derselbe Vorschau-Cache wieder 0 B. Außerdem wird nur ein
tatsächlich aufgelisteter physischer Ordner als letzter Ordner gespeichert;
Neustart aus offenem Archiv stellte dessen letzten physischen Elternordner
statt einer Archivdatei oder unbeteiligten Standardwurzel her.

Zusätzlicher nativer Image-/Playback-Runner: acht PASS-Gruppen, inklusive
ungültiger/indefiniter Dauer, sehr kurzer Clips, Koordination, Grenzen,
Vorbereitungsfehler und Root-Lebensdauer. Finaler nativer Clone und signierter
normaler Installationskandidat wurden als Revision r20 neu gebaut. Der normale
Kandidat enthält keine `MacUITestRoot.txt`; Clone-FSKit-Erweiterungen bleiben
außerhalb des Test-App-Bundles, damit sie den installierten Treiber nicht
überschatten.

Vor dem App-Tausch wurden die vorhandenen produktiven Google-Drive- und
OneDrive-Verbindungen nur lesend geöffnet: echte Dateilisten ohne Anmeldung.
OneDrive zeigte 15 sichtbare Zeilen. Die ursprünglichen Dateibereiche
(iCloud Drive/Downloads) wurden wiederhergestellt. Beide App-Pakete verwenden
dieselbe normale Bundle-ID und dasselbe Apple-Development-Team. Das tatsächliche
Update wurde anschließend mit dem unveränderten signierten r20-Kandidaten
ausgeführt: `/Applications/OpenCommander.app`. Die alte App ist wiederherstellbar
unter `ntfs/NTFS3G/.build-native/App-before-install.5nFz69/OpenCommander.saved`.
Tiefe/strikte Signaturprüfung bestand nach dem Austausch; gestarteter neuer
Prozess 74363 stammt aus `/Applications`. Installierte `OpenCommander.debug.dylib`
ist identisch zum Kandidaten, SHA256
`a87aa5cbfa2ab222aa34ec448bc290f6009979d1e1eb770a7925f6a5fbfe3436`.
Keine Testwurzel-Markierung im normalen Paket und keine neue Sicherheitsfreigabe.

Nach Installation: Google-Drive-Online-Wurzel mit 14 sichtbaren Zeilen und
OneDrive mit 15 sichtbaren Zeilen ohne Anmeldemaske. Frischer separater
NTFS-64-MiB-Test unter `/private/tmp/OpenCommander-NTFS-Queue-2b661D` bestand
Engine-, Foundation-Datei/Ordner-, dauerhafte Datei/Baum-Kopien und Pause mit
vollständigem Detach/Reattach und bytegenauer Wiederaufnahme. Prozess-Exit 0,
beide Geräte normal ausgeworfen, kein openntfs2-Mount zurückgelassen.
Protokoll: `ntfs/NTFS3G/.build-native/acceptance-20261018-postinstall-ntfs-transfer.log`.

Zusätzlicher normaler App-Neustart nach dem Update: Prozessende vor erneutem
Start geprüft; Google Drive zeigte wieder 14 sichtbare Zeilen, OneDrive wieder
15, beide ohne neue Anmeldung. Die ursprünglichen Bereiche iCloud Drive links
und Downloads rechts sind abschließend wiederhergestellt. Kein OS-Neustart.
Die installierte App bleibt geöffnet. Die alte App-Sicherung bleibt erhalten.

Abnahmegrenze: 158 Linux-Referenzfälle werden einzeln im Ledger geführt, davon
26 mit tatsächlich ausgeführter begrenzter nativer Sequenz. Die übrigen Fälle
bleiben ehrlich `partial` oder `environment_required`; insbesondere die gesamte
Konto-/Server-/Geräte-/Auflösungsmatrix und beliebige externe App-Repräsentationen
sind nicht vollständig abgenommen. Zwei Stunden injizierter Cloud-Fehler und
die erfolgreichen nativen Bedienfälle sind kein Beleg für vollständige
Linux-Gleichheit. `complete_parity` bleibt deshalb `false`.

Elements ist nicht angeschlossen. Keine neue physische NTFS-Abnahme behauptet.
Kein Commit/Push beauftragt; unabhängige staged Änderungen werden erhalten.

## Nachgeholte externe Gegenprobe

Nach „Fenster sind freigestellt“ wurde der zuvor verdeckte TextEdit-Zieltest
erneut versucht. Zunächst deckte die normale OpenCommander-App das Ziel ab;
der Guard verweigerte vor jeglichen Mausereignissen. Der Testtreiber hebt nun
auch bei externem Ziel dessen exakt benannte Test-App zuerst hinter die Quelle,
wie zuvor bereits bei externen Quellen. Eigentümer-, Sichtbarkeits- und
Fixture-Prüfungen bleiben unverändert. Danach führte der echte Ziehvorgang
von der isolierten App in das eigene TextEdit-Dokument zum exakten originalen
`file:///Users/niklaus/OpenCommander-MacUITest-Hover-20261017/External/OpenCommander-MacUITest-Document.txt`-
Verweis im Text. Quelle erhalten. Die erste Undo/Save-Aktionsfolge schien im
kurzen UI-Auszug erfolgreich, aber die unabhängige Dateigröße betrug noch
138 Bytes; daher kein Undo-Pass. Explizites Wiederherstellen des ausschließlich
eigenen Testtexts und Save ergab anschließend wieder genau 32 Bytes. Dies bestätigt diese
Datei-URL-Repräsentation, keine beliebige Fremdprogramm-Anhangsmatrix.
