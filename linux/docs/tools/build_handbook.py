"""Build the offline German handbook from maintained HTML chapters (stdlib only)."""
from pathlib import Path
from html import escape
import struct
import shutil

ROOT = Path(__file__).resolve().parents[1] / 'handbuch'
ASSETS = ROOT / 'assets'
chapters = []


def figure(name, caption, alt=None):
    path = ASSETS / (name + '.png')
    width, height = struct.unpack('>II', path.read_bytes()[16:24])
    return (f'<figure><button class="screenshot" type="button" aria-label="Screenshot vergrößern: {escape(alt or caption, quote=True)}">'
            f'<img src="assets/{name}.png" width="{width}" height="{height}" loading="lazy" decoding="async" alt="{escape(alt or caption, quote=True)}">'
            '<span class="zoom-hint" aria-hidden="true">↗ Vergrößern</span></button>'
            f'<figcaption>{caption}</figcaption></figure>')


def chapter(identifier, title, intro, body):
    chapters.append((identifier, title, intro, body))


chapter('schnellstart', 'In fünf Minuten startklar', 'Dein erster Kopiervorgang – mit zwei Bereichen und einem klaren Ziel.', '''
<div class="callout"><strong>Dieses Handbuch gilt für OpenCommander Linux 0.3.19.</strong> Menünamen und Screenshots beziehen sich auf die deutsche Oberfläche. Die Beispiele verwenden ausschließlich angelegte Beispieldateien und ein separates Profil. Cloud-Namen sind Demonstrationsprofile; es wird keine echte Anmeldung abgebildet. Auftragswerte in den Transferbildern sind illustrative Zustände der echten Bedienelemente.</div>
<h3>Starten und installieren</h3>
<p>Entpacke das Linux-Paket vollständig. Öffne darin den Ordner <code>opencommander</code> und starte die gleichnamige Programmdatei. Das Verzeichnis <code>_internal</code> muss daneben liegen bleiben; es enthält die benötigten Bibliotheken. Für das fertige Paket brauchst du Python und Qt nicht zusätzlich einzurichten.</p>
<p>Mit <code>install-local.sh</code> aus diesem Paket legst du einen persönlichen Starter im Anwendungsmenü an. Verschiebe den Paketordner danach möglichst nicht. Falls du ihn verschiebst, führe das Installationsskript am neuen Ort erneut aus. Der aktuelle x86_64-Build ist für Ubuntu 24.04 mit glibc 2.39 oder neuer gebaut; andere Linux-Umgebungen können zusätzliche Systemkomponenten benötigen.</p>
<ol class="steps">
<li><strong>Quelle links öffnen.</strong> Wähle beispielsweise deinen Bilderordner. Die Pfadzeile zeigt, wo du bist.</li>
<li><strong>Ziel rechts öffnen.</strong> Wähle einen vorhandenen Zielordner, etwa „Ablage“. Die beiden Seiten navigieren unabhängig.</li>
<li><strong>Dateien links markieren.</strong> Ein Klick markiert eine Datei; mit <kbd>Strg</kbd> + Klick ergänzt du weitere.</li>
<li><strong>Modus „Kopieren“ wählen.</strong> Ziehe die Auswahl auf die rechte Dateiliste. Alternativ kopiert <kbd>F5</kbd> die aktive Auswahl auf die andere Seite.</li>
<li><strong>Abschluss kontrollieren.</strong> Öffne bei Bedarf die Übertragungsübersicht. Erst „Abgeschlossen“ bestätigt den abgeschlossenen Auftrag. In der Historie findest du den Vorgang wieder.</li>
</ol>
<h3>Als Standard-Dateimanager verwenden</h3>
<p>Beim ersten normalen Start fragt die App, ob sie der Standard-Dateimanager für Ordner werden soll. Bestätige nur, wenn du das möchtest. Der Menü-Starter muss bereits registriert sein. Die Einstellung betrifft die Ordnerzuordnung des Desktops; andere Anwendungen können weiterhin ihren fest eingebauten Dateimanager verwenden.</p>
<p>Wenn die Zuordnung nicht übernommen wurde, registriere den Starter erneut und prüfe die Standardanwendung für Ordner in deinem Linux-Desktop. Eine bereits laufende OpenCommander-Sitzung empfängt neu geöffnete Ordner.</p>
''')

chapter('oberflaeche', 'Die Oberfläche verstehen', 'Zwei Dateibereiche, eine Orte-Leiste und alle Aufträge im Blick.', figure('01-oberflaeche-dunkel', 'Hauptfenster im dunklen Modus. Links ist die Quelle aktiv, rechts der Zielordner geöffnet.') + '''
<div class="feature-grid">
<div><span class="number">01</span><h3>Kopfbereich</h3><p>Hier stehen Kopieren/Verschieben, die Checkbox „Dunkel“ und „Einstellungen / Orte“. Der Umschalter steuert Dateiaktionen per Drag &amp; Drop.</p></div>
<div><span class="number">02</span><h3>Werkzeugleiste</h3><p>Suchen, Umbenennen, Neuer Ordner, Entfernen, ZIP erstellen, Vorschau, Rückgängig und Historie. „Entpacken“ erscheint passend zur Archivauswahl.</p></div>
<div><span class="number">03</span><h3>Orte-Leiste</h3><p>Ein Klick öffnet den gewählten Ort. Cloud-Symbole helfen beim Erkennen des Dienstes. Die Reihenfolge lässt sich durch Ziehen ändern.</p></div>
<div><span class="number">04</span><h3>Dateibereiche</h3><p>Jede Seite besitzt Ordnerbaum, Pfadzeile, Filter und Dateiliste. „AKTIV“ kennzeichnet die Seite, auf deren Auswahl sich Tastaturaktionen beziehen.</p></div>
<div><span class="number">05</span><h3>Übertragungen</h3><p>Bei Kopier- und Verschiebeaufträgen erscheint die aufklappbare Übersicht mit Fortschritt und eigenen Bedienelementen je Auftrag.</p></div>
<div><span class="number">06</span><h3>Status und Historie</h3><p>Hinweise stehen im Fußbereich; die Historie blendest du bei Bedarf ein. Dort siehst du frühere Änderungen und deren Rücknahme.</p></div>
</div>
<p>Klicke in die gewünschte Seite, bevor du <kbd>F5</kbd>, <kbd>F6</kbd> oder eine Werkzeugaktion verwendest. Bei Online-Orten zeigt die Kopfzeile des Bereichs zusätzlich den gespeicherten Verbindungsnamen – auch in Unterordnern.</p>
''')

chapter('navigation', 'Ordner öffnen und Dateien auswählen', 'Schnell zum richtigen Pfad und zur richtigen Auswahl.', '''
<h3>Durch Ordner navigieren</h3>
<ul>
<li><strong>Doppelklick oder Enter:</strong> Ordner öffnen; Dateien je nach Typ anzeigen oder in einer Anwendung öffnen.</li>
<li><strong>Ordnerbaum:</strong> Mit dem kleinen Pfeil Unterordner aufklappen. Die Trennlinie zwischen Baum und Dateiliste lässt sich ziehen. Die Breite wird pro Bereich gespeichert; lange Namen lassen sich horizontal scrollen.</li>
<li><strong>Pfad eingeben:</strong> <kbd>Strg</kbd> + <kbd>L</kbd> fokussiert die Pfadzeile. Gib einen absoluten lokalen oder eingebundenen Pfad ein und bestätige mit Enter.</li>
<li><strong>Eine Ebene höher:</strong> Der Aufwärtspfeil oder <kbd>Alt</kbd> + <kbd>↑</kbd> öffnet den übergeordneten Ordner. Der gerade verlassene Ordner wird markiert.</li>
<li><strong>Zurück und vorwärts:</strong> Die Pfeile neben der Pfadzeile oder <kbd>Alt</kbd> + <kbd>←</kbd>/<kbd>→</kbd> wechseln durch den Navigationsverlauf.</li>
</ul>
<h3>Auswahl, Sortierung und Filter</h3>
<p>Mit <kbd>Strg</kbd> + Klick wählst du einzelne zusätzliche Einträge, mit <kbd>Umschalt</kbd> + Klick einen zusammenhängenden Bereich. <kbd>Strg</kbd> + <kbd>A</kbd> markiert alle Einträge der aktiven Dateiliste. Die Anzeige rechts oben im Bereich nennt Auswahl und Elementzahl.</p>
<p>Klicke auf die Spaltenüberschrift, um etwa nach Name, Größe, Typ oder Änderungsdatum zu sortieren. Das Feld „Dateien filtern…“ beschränkt die Ansicht im aktuellen Ordner. Es durchsucht keine Unterordner; dafür gibt es die separate <a href="#werkzeuge">Suche</a>.</p>
<p>„Versteckte Dateien“ oder <kbd>Strg</kbd> + <kbd>H</kbd> blendet versteckte Einträge ein. <kbd>Strg</kbd> + <kbd>R</kbd> aktualisiert die Dateibereiche. Auf Online-Speichern kann ein kurzzeitig gespeicherter Listenstand noch sichtbar sein.</p>
<div class="callout tip"><strong>Rechtsklick auf eine leere Fläche</strong> öffnet die Ordnerfunktionen, unter anderem „Neuer Ordner“, „Einfügen“ und „Aktualisieren“. Ein Rechtsklick auf eine Datei bezieht sich auf die Dateiauswahl.</div>
''')

chapter('dateien', 'Kopieren, verschieben und verwalten', 'Wähle Quelle und Ziel bewusst – die App zeigt anschließend den Auftrag.', '''
<h3>Drag &amp; Drop</h3>
<ol class="steps"><li>Öffne Quelle und Ziel in den beiden Bereichen.</li><li>Markiere die gewünschten Dateien oder Ordner.</li><li>Stelle oben „Kopieren“ oder „Verschieben“ ein.</li><li>Ziehe die Auswahl in die andere Dateiliste oder direkt auf einen Zielordner. Am Mauszeiger erscheint eine Karte mit Auswahl und Modus.</li><li>Lasse los und beantworte gegebenenfalls die Frage zu vorhandenen Namen.</li></ol>
<p>Eine zusätzliche Schaltfläche „Ausführen“ ist dafür nicht nötig. Ein Drag &amp; Drop auf einen Ordner legt die Auswahl in diesem Ordner ab. Auf die leere Dateifläche gezogen, wird der aktuell geöffnete Ordner zum Ziel.</p>
<div class="callout"><strong>F5 und F6 sind eindeutig:</strong> <kbd>F5</kbd> kopiert und <kbd>F6</kbd> verschiebt die aktive Auswahl in den anderen Bereich – unabhängig von der Stellung des Drag-&amp;-Drop-Umschalters.</div>
<h3>Zwischenablage</h3>
<p><kbd>Strg</kbd> + <kbd>C</kbd> kopiert die Auswahl in die Zwischenablage, <kbd>Strg</kbd> + <kbd>X</kbd> merkt sie zum Verschieben vor. Öffne das Ziel und drücke <kbd>Strg</kbd> + <kbd>V</kbd>. Ausschneiden allein entfernt noch keine Datei. Beim Ziehen aus OpenCommander in andere Anwendungen werden lokale Datei-URLs als Kopierangebot übergeben; die Zielanwendung entscheidet über die Verarbeitung.</p>
<h3>Wenn ein Name schon existiert</h3>
<p>Bei erkannten lokalen Namenskonflikten fragt die App nach. Sobald Quelle oder Ziel auf einem erkannten Online-/Netzlaufwerk liegen, verwendet diese Version automatisch „Beide behalten“ und löst den Namen im Hintergrund auf; dort erscheint kein Überschreiben-Dialog.</p>
<div class="table-wrap"><table><thead><tr><th>Auswahl</th><th>Was geschieht?</th></tr></thead><tbody><tr><td>Beide behalten</td><td>Die neue Datei erhält einen ergänzten, freien Namen. Das bestehende Ziel bleibt erhalten.</td></tr><tr><td>Ersetzen</td><td>Das vorhandene Original wird für eine mögliche Rücknahme gesichert; die neue Datei übernimmt den Zielnamen.</td></tr><tr><td>Abbrechen</td><td>Dieser neue Vorgang wird nicht gestartet.</td></tr></tbody></table></div>
<h3>Weitere Dateiaktionen</h3>
<ul><li><strong>Neuer Ordner:</strong> In den gewünschten Bereich klicken, „Neuer Ordner“ oder <kbd>Strg</kbd> + <kbd>Umschalt</kbd> + <kbd>N</kbd> wählen und einen Namen eingeben.</li><li><strong>Umbenennen:</strong> Eine Datei auswählen, <kbd>F2</kbd> drücken und bestätigen. Für mehrere Dateien nutze <a href="#werkzeuge">Mehrfach umbenennen</a>.</li><li><strong>Öffnen mit:</strong> Eine Datei rechts anklicken und „Öffnen mit …“ wählen. Die Programmauswahl stammt vom Linux-Desktop.</li><li><strong>Entfernen:</strong> „Entfernen“ oder <kbd>Entf</kbd> verschiebt die Auswahl nach Bestätigung in OpenCommanders Wiederherstellungsbereich.</li></ul>
<p>Beim Verschieben auf demselben Laufwerk kann die App direkt umbenennen. Über Laufwerksgrenzen wird zuerst kopiert und geprüft, danach die Quelle bereinigt. Darum kann ein Verschiebeauftrag nach dem eigentlichen Datentransfer noch weiterarbeiten.</p>
''')

chapter('uebertragungen', 'Aufträge, Fortschritt und Pause', 'Mehrere Vorgänge verwalten, ohne den Überblick zu verlieren.', '''
<p>Klicke auf die Leiste „Übertragungen“, um die Übersicht aufzuklappen. Jeder Kopier- oder Verschiebeauftrag hat eine eigene Karte mit Quelle, Ziel, Status und Bedienelementen. Bei vielen Karten kannst du innerhalb der Übersicht scrollen.</p>
''' + figure('07-uebertragungen', 'Ausschnitt der Auftragsübersicht mit zwei echten Transferkarten. Prozent, Mengen und Laufzeiten sind illustrative Beispieldaten.') + '''
<div class="table-wrap"><table><thead><tr><th>Anzeige</th><th>Bedeutung</th></tr></thead><tbody>
<tr><td>Prozent und Datenmenge</td><td>Bearbeitete gegenüber insgesamt geplanten Daten. Vor der Übertragung werden Dateien und Größe zunächst ermittelt.</td></tr>
<tr><td>Dateien</td><td>Abgeschlossene Dateien gegenüber geplanter Dateizahl. Eine große, noch offene Datei kann viele Bytes übertragen, während der Dateizähler gleich bleibt.</td></tr>
<tr><td>Zeit / Geschwindigkeit</td><td>Verstrichene Zeit in Sekunden, Minuten, Stunden oder Tagen und die durchschnittliche Übertragungsrate.</td></tr>
<tr><td>Rest ca.</td><td>Schätzung für den verbleibenden Datentransfer. Verbindungswechsel und anschließende Prüfungen können sie verändern.</td></tr>
<tr><td>Prüfen und abschließen / Upload</td><td>Die App schließt Schreibvorgänge oder Prüfungen ab. 99 % bedeutet noch nicht „fertig“.</td></tr></tbody></table></div>
<h3>Parallelität und wartende Aufträge</h3>
<p>„Gleichzeitig“ erlaubt einen bis vier Aufträge; standardmäßig sind es zwei. Unabhängige Aufträge können parallel laufen. Berühren sie dieselben Quell- oder Zielpfade, wartet ein Auftrag, bis der andere den Pfad freigibt. Das schützt auch Quellen pausierter Aufträge. Mehr Parallelität ist auf einer langsamen Cloud-Verbindung nicht automatisch schneller.</p>
<p>Navigation, Einstellungen, Vorschau und weitere Kopieraufträge bleiben verfügbar. Unabhängige Dateien können entfernt werden. Löschen an reservierten Quell- oder Zielpfaden wartet; Umbenennen und Entpacken warten auf den Abschluss laufender Übertragungen. Rückgängig und Trennen sind während laufender Dateiaktionen gesperrt.</p>
<h3>Minimieren, pausieren, abbrechen</h3>
<ul><li><strong>Minimieren:</strong> Macht nur die Karte kompakt. Der Auftrag läuft weiter. „Details“ blendet die ausführlichen Angaben wieder ein.</li><li><strong>Pause:</strong> Fordert eine Unterbrechung dieses Auftrags an. Warte auf „Pausiert – gespeichert“.</li><li><strong>Fortsetzen:</strong> Setzt einen gespeicherten Auftrag fort. Quelle, Laufwerk und Zwischenstand werden zuerst geprüft.</li><li><strong>Abbrechen:</strong> Beendet diesen Auftrag und bereinigt unfertige Zwischenstände, soweit das Ziellaufwerk erreichbar ist. Es ist keine Pause für später.</li></ul>
''' + figure('08-pause-kompakt', 'Gespeicherte Pause mit „Fortsetzen“. Die zweite Karte ist minimiert; ihre Bedienung bleibt sichtbar. Demonstrationszustand.') + '''
<div class="callout important"><strong>„Angefordert“ ist noch nicht „gespeichert“.</strong> Bei einem blockierten NAS- oder Cloud-Zugriff kann Pause oder Abbruch erst greifen, wenn der Dateizugriff zurückkehrt. Die Statusmeldung zeigt diesen Zwischenzustand. Beende den Prozess in dieser Phase nicht gewaltsam, wenn du den Zwischenstand erhalten willst.</div>
<h3>Schließen und später weiterarbeiten</h3>
<p>Beim regulären Schließen werden laufende Kopier- und Verschiebeaufträge pausiert und gespeichert. Lass den Vorgang abschließen. Beim nächsten Start setzt die App gespeicherte Aufträge automatisch fort; nach Fehlern wählst du bewusst „Fortsetzen“. Eigene gespeicherte Online-Orte werden bei Bedarf verbunden. Externe NAS-Freigaben oder fremde Mounts müssen wieder verfügbar sein.</p>
<p>Fertige Dateien werden geprüft, bevor sie wiederverwendet werden. Auf lokalen Dateisystemen kann eine unvollständige Datei nach Prüfung ihres vorhandenen Anfangs weitergeschrieben werden. Auf rclone-Mounts wird die angefangene Datei aus Kompatibilitätsgründen neu geschrieben; vollständig geprüfte Dateien bleiben erhalten. Prüfungen können bei Cloud-Dateien zusätzliche Zeit und Downloads kosten.</p>
<p>Die Schaltflächen im Fußbereich gelten für alle Aufträge; die Schaltflächen in einer Karte nur für diesen Auftrag. „Abgeschlossene ausblenden“ räumt die Übersicht auf. Es löscht keine kopierten Dateien. Bei einem Fehler bleiben Details in der Karte sichtbar. Verbinde das benötigte Laufwerk oder erneuere die Anmeldung und wähle danach „Fortsetzen“.</p>
''')

chapter('wiederherstellen', 'Papierkorb und Rückgängig', 'Änderungen nachvollziehen und überprüfbar zurücknehmen.', '''
<h3>Dateien wiederfinden</h3>
<p>OpenCommander verwendet einen eigenen Papierkorb. „Entfernen“ verschiebt die Daten in versteckte Wiederherstellungsordner auf dem betreffenden Laufwerk. Die Dateien werden dadurch aus ihrem ursprünglichen Ordner entfernt, belegen aber weiter Speicherplatz. Dieser Papierkorb ist unabhängig vom Linux-Systempapierkorb und vom Papierkorb auf der Website eines Cloud-Dienstes.</p>
<ol class="steps"><li>Klicke in der Orte-Leiste auf „Papierkorb“.</li><li>Wähle einen Eintrag und prüfe den ursprünglichen Pfad sowie den Zeitpunkt.</li><li>Klicke auf „Löschvorgang wiederherstellen“. Bei einer gemeinsamen Löschaktion betrifft dies den zugehörigen Vorgang, nicht nur einen beliebigen Ausschnitt.</li><li>Das ursprüngliche Laufwerk muss verbunden und der ursprüngliche Name frei sein.</li></ol>
''' + figure('10-papierkorb', 'Der eigene Papierkorb mit einer tatsächlich im isolierten Beispielprofil entfernten Datei.') + '''
<h3>Die Historie verwenden</h3>
<p>„Historie“ blendet frühere Dateivorgänge ein. Jede Karte enthält Zeitpunkt, Aktion und weitere Informationen. Über „Info“ findest du Quell- und Zielpfade, gesicherte Originale und mögliche Hinweise. „Rückgängig“ an einer Karte nimmt genau diesen Vorgang zurück. <kbd>Strg</kbd> + <kbd>Z</kbd> startet die allgemeine Rückgängig-Funktion.</p>
''' + figure('09-historie', 'Historie nach echten Dateiaktionen mit Beispieldaten: Kopieren, Umbenennen und Entfernen.') + '''
<p>Die Historie bleibt nach einem Neustart erhalten. Die App prüft vor der Rücknahme, ob Dateien seitdem verändert wurden oder der ursprüngliche Pfad inzwischen belegt ist. Solche Konflikte können die Rücknahme stoppen. Geänderte Inhalte werden nicht einfach überschrieben. Bereits erfolgreich zurückgenommene Teilschritte werden gespeichert.</p>
<div class="callout important"><strong>Platz freigeben ist eine andere Entscheidung.</strong> Im Papierkorb gibt es derzeit keine komfortable Schaltfläche „Alles endgültig leeren“. Entferne Wiederherstellungsordner nicht nebenbei: Damit verlierst du die betreffende Rücknahme. Auch die Datei-Historie allein ist kein Backup.</div>
''')

chapter('orte', 'Orte und Dienstsymbole', 'Häufige Ziele so anordnen, wie du arbeitest.', '''
<div class="provider-row"><span><img src="assets/onedrive.svg" alt="">OneDrive</span><span><img src="assets/drive.svg" alt="">Google Drive</span><span><img src="assets/dropbox.svg" alt="">Dropbox</span><span><img src="assets/iclouddrive.svg" alt="">iCloud</span></div>
<p>Die Orte-Leiste enthält anklickbare Ziele: persönliche Ordner, Datenträger, Online-Orte und Papierkorb. Ein einfacher Klick öffnet den Ort im aktiven Bereich. Eine gespeicherte, noch nicht eingebundene Verbindung wird zunächst im Hintergrund hergestellt.</p>
<h3>Reihenfolge ändern</h3>
<ol class="steps"><li>Ziehe einen Ort auf einen anderen Ort.</li><li>Bewege den Zeiger auf dessen linke oder rechte Hälfte. Die blaue Linie markiert die Einfügestelle.</li><li>Lasse los. Alternativ wähle per Rechtsklick „Nach links“ oder „Nach rechts“.</li></ol>
<p>Die Reihenfolge wird gespeichert und bleibt nach einem Neustart erhalten. Auch Papierkorb und Datenträger lassen sich verschieben. Ausgeblendete oder vorübergehend fehlende Orte behalten ihren gespeicherten Platz. Das Umsortieren verschiebt keine Dateien.</p>
<h3>Verknüpfungen bearbeiten</h3>
<p>Unter „Einstellungen / Orte“ kannst du Namen ändern, Orte ausblenden und mit „Ordner hinzufügen…“ eine eigene Verknüpfung anlegen. „Nur Verknüpfung entfernen“ entfernt eine selbst hinzugefügte Verknüpfung. Bei automatisch erkannten Orten verwende die Sichtbarkeits-Checkbox.</p>
<p>Rechtsklick auf einen Online-Ort → „Bearbeiten …“ öffnet seine Verwaltung. Den Anzeigenamen kannst du dort speichern, ohne das Konto neu einzurichten. Online-Verknüpfungen zu entfernen löscht keine Dateien beim Anbieter und entfernt nicht automatisch die gespeicherten Zugangsdaten.</p>
''')

chapter('cloud', 'Cloud-Konten einrichten', 'OneDrive, Google Drive, Dropbox und iCloud im normalen Dateibereich öffnen.', '''
<p>Öffne <strong>Einstellungen / Orte → Online-Orte verwalten …</strong>. Vergib einen verständlichen Anzeigenamen, beispielsweise „OneDrive Privat“ oder „Dropbox Arbeit“, und wähle den Dienst. Nach erfolgreicher Einrichtung wird der Name gespeichert und der Ort im aktiven Bereich geöffnet.</p>
<h3>OneDrive</h3>
<ol class="steps"><li>Wähle „OneDrive online“ und gib einen Anzeigenamen ein.</li><li>Klicke auf „Mit Microsoft im Browser anmelden“.</li><li>Melde dich im Browser mit dem gewünschten Konto an und erlaube den Zugriff.</li><li>Falls der Assistent mehrere Laufwerke anbietet, wähle das Laufwerk mit deinen gewünschten Dateien. Für ein persönliches Konto ist dies üblicherweise der als „OneDrive (personal)“ bezeichnete Hauptbereich. Technische Einträge wie Archive oder Bundles solltest du nicht ohne konkreten Grund auswählen.</li><li>Bestätige die Auswahl und kontrolliere die angezeigten Ordner.</li></ol>
''' + figure('04-onedrive', 'OneDrive-Einrichtung mit Dienstsymbol und Browser-Anmeldeschaltfläche. Das angezeigte Profil ist ein Beispiel.') + '''
<p>Der Browser wird über den Desktop geöffnet und um Aktivierung gebeten. Ob er sofort im Vordergrund erscheint, entscheidet die Desktop-Umgebung. Während der Anmeldung hilft „Anmeldebrowser nach vorne holen“, den Anmeldedialog wieder zu öffnen.</p>
<h3>Google Drive</h3>
<p>Wähle „Google Drive online“. Der Assistent bietet Felder für eine eigene Google-OAuth-Client-ID und das Client-Secret sowie „Eigene Google-Anmeldung einrichten: Anleitung“. Folge dieser Anleitung für eine Desktop-Anwendung, wenn du eigene Client-Daten einrichtest; trage beide Werte ein und starte danach die Browser-Anmeldung.</p>
<p>Bei Abfragelimits oder Meldungen wie „Quota exceeded“ kann der verwendete OAuth-Client eine Rolle spielen. Eine eigene Konfiguration kann erforderlich sein. Bei einem Wechsel des Clients muss die Anmeldung erneuert werden. Eine vorhandene eigene Client-Konfiguration bleibt erhalten, wenn du keine neuen Werte angibst.</p>
''' + figure('05-google-drive', 'Google-Drive-Assistent mit Feldern für eigene OAuth-Client-Daten. Im Beispiel sind keine Zugangsdaten eingetragen.') + '''
<h3>Dropbox</h3>
<p>Wähle „Dropbox online“, benenne die Verbindung und starte die angebotene Anmeldung. Bestätige das gewünschte Konto und den Zugriff im Browser. Anschließend kannst du den gespeicherten Ort wie einen Ordner öffnen. Auch auf Dropbox nutzt „Entfernen“ den eigenen OpenCommander-Wiederherstellungsbereich; dadurch wird nicht automatisch Speicher beim Anbieter frei.</p>
<h3>iCloud Drive</h3>
<p>Wähle „iCloud Drive online“ und „Mit Apple-ID verbinden“. Dieses Backend benötigt die Apple-ID, das reguläre Apple-ID-Passwort und die Zwei-Faktor-Bestätigung. App-spezifische Passwörter werden hier nicht unterstützt. Gib den Bestätigungscode vom vertrauenswürdigen Gerät ein; der Assistent erklärt auch die SMS-Option.</p>
<p>Ein Browserlogin allein richtet iCloud in dieser Linux-Version nicht ein. Der Webzugriff auf iCloud-Daten muss im Apple-Konto erlaubt sein; gegebenenfalls musst du ihn auf einem vertrauenswürdigen Gerät bestätigen. Freigaben verwaltest du für iCloud auf der Provider-Website.</p>
<h3>Erneut verbinden oder anmelden</h3>
<p>Nach einem Neustart bleiben die Namen in der Orte-Leiste. Ein Klick verbindet und öffnet den Ort. Wird ein Zugriff widerrufen oder läuft eine Anmeldung ab, öffne die Online-Verwaltung. Trenne einen noch eingebundenen Ort nach Abschluss der Dateiaktionen und verwende „Erneut anmelden“. Richte nicht bei jeder vorübergehenden Störung ein weiteres Konto ein.</p>
<h3>Was bedeutet direkter Online-Zugriff?</h3>
<p>Die Linux-App verwendet rclone und FUSE, um Cloud-Inhalte als Dateipfade bereitzustellen. Es wird nicht automatisch der gesamte Cloud-Speicher lokal synchronisiert. Ordnerlisten werden kurz zwischengespeichert; Vorschauen laden einzelne Dateien herunter. Bei Kopien werden die benötigten Inhalte übertragen. Für app-eigene Mounts ist der verzögerte VFS-Schreibcache ausgeschaltet.</p>
<p>Eine Dateiliste ist deshalb keine lückenlose Echtzeitansicht. Bei Störungen kann die App einen kürzlich gelesenen Stand mit Alter und Fehlerhinweis anzeigen. „Erneut laden“ oder <kbd>Strg</kbd> + <kbd>R</kbd> fordert eine Aktualisierung an. Externe rclone-Mounts und Sync-Programme können eigene Caches oder Upload-Warteschlangen haben.</p>
<div class="callout"><strong>Zugangsdaten:</strong> Cloud-Tokens und Konfiguration liegen im privaten Benutzerprofil mit eingeschränkten Dateirechten. Das ist keine Schlüsselbund-Verschlüsselung. Gib dieses Profil nicht als Teil eines Fehlerberichts weiter. Server-Passwörter haben eine gesonderte, optionale Schlüsselbundfunktion.</div>
''')

chapter('teilen', 'Cloud-Dateien per Link teilen', 'Eine Freigabe bewusst erstellen und anschließend kontrollieren.', '''
<ol class="steps"><li>Öffne den eingerichteten Cloud-Ort.</li><li>Wähle genau eine Datei oder einen Ordner.</li><li>Rechtsklick → „Online · Verbindungsname“ → „Teilen mit Link …“.</li><li>Lies den Freigabehinweis. Erst „Link erstellen“ erstellt oder holt den Link.</li><li>Nutze danach „Link kopieren“ oder „Link öffnen“.</li></ol>
''' + figure('17-teilen', 'Freigabedialog vor dem Erstellen eines Links. Für diese Aufnahme wurde keine Freigabe angelegt.') + '''
<p>Die direkte Linkfunktion steht für Google Drive, OneDrive und Dropbox zur Verfügung, soweit Konto und Anbieter sie erlauben. Bei OneDrive werden anonyme Leserechte angefordert. Jeder mit dem Link kann die freigegebene Datei beziehungsweise den Ordnerinhalt lesen. Es gibt kein automatisch gesetztes Ablaufdatum.</p>
<p>Im Online-Untermenü findest du außerdem „Online-Pfad kopieren“ und „Freigaben im Cloud-Browser verwalten …“. Der Browser öffnet die Website des Dienstes; melde dich dort gegebenenfalls an und wähle das betreffende Objekt. Für iCloud erfolgt die Freigabe dort.</p>
<div class="callout important"><strong>Abbrechen widerruft keine bereits angelegte Freigabe.</strong> Wenn eine Linkanfrage zu lange dauert oder geschlossen wird, kontrolliere bestehende Freigaben beim Anbieter. Dort kannst du Berechtigungen oder einen Link wieder entfernen.</div>
<p>Fehlt das Online-Untermenü, prüfe, ob du im eingerichteten Cloud-Mount arbeitest. Ein gewöhnlicher lokaler Sync-Ordner hat nicht automatisch alle Provider-Aktionen. Erkannte externe rclone-Mounts können die Aktionen ebenfalls anbieten; spezielle Konfigurationen werden nicht immer zugeordnet.</p>
''')

chapter('server', 'SFTP, FTP und FTPS verbinden', 'Anmelden mit Passwort, privatem Schlüssel oder SSH-Agent.', '''
<p>Öffne <strong>Einstellungen / Orte → Verbindungen verwalten … → SFTP / FTP / FTPS – Passwort oder SSH-Key …</strong>. Alternativ wählst du das gewünschte Protokoll direkt in der Online-Verwaltung.</p>
<div class="table-wrap"><table><thead><tr><th>Feld</th><th>Eingabe</th></tr></thead><tbody>
<tr><td>Server</td><td>Hostname ohne vorangestelltes Protokoll, zum Beispiel <code>nas.example.org</code>.</td></tr>
<tr><td>Port</td><td>Standard: 22 für SFTP, 21 für FTP oder explizites FTPS. Verwende bei Bedarf den vom Betreiber genannten Port.</td></tr>
<tr><td>Benutzer</td><td>Dein Benutzername auf dem Server.</td></tr>
<tr><td>Anmeldung</td><td>Passwort; bei SFTP auch private SSH-Schlüsseldatei oder bereits entsperrter SSH-Agent.</td></tr>
<tr><td>Startordner</td><td>Optionaler Bereich auf dem Server. Leer bedeutet Benutzerordner, beispielsweise <code>/data</code> für einen konkreten Startpfad.</td></tr></tbody></table></div>
''' + figure('06-sftp', 'SFTP-Formular mit einer beispielhaften privaten Schlüsseldatei. Es wurde keine Verbindung aufgebaut.') + '''
<h3>Passwort verwenden</h3><p>Wähle „Passwort“, gib es in das verdeckte Feld ein und verbinde. Standardmäßig bleibt es nur in der Sitzung verfügbar. Nach einem Neustart wird es bei Bedarf erneut abgefragt.</p>
<h3>Privaten SSH-Key verwenden</h3><p>Wähle die private OpenSSH- oder PEM-Datei, nicht die öffentliche <code>.pub</code>-Datei. Bei verschlüsselten Schlüsseln ist zusätzlich die Passphrase erforderlich. Die Schlüsseldatei bleibt an ihrem bisherigen Ort und muss private Dateirechte haben. PuTTY-Schlüssel im Format <code>.ppk</code> müssen zuvor in ein unterstütztes OpenSSH-Format exportiert werden.</p>
<p>Verschlüsselte OpenSSH-Schlüssel werden über einen vorhandenen SSH-Agent zeitlich begrenzt entsperrt. Der Agent muss verfügbar sein. Reine SCP-Server ohne SFTP-Unterstützung sind mit diesem Verbindungsweg nicht nutzbar.</p>
<h3>Serveridentität und Speichern</h3><p>Bei einem neuen SSH-Server zeigt die App Fingerabdrücke. Vergleiche sie mit einer unabhängigen Angabe des Betreibers, bevor du bestätigst. Ein geänderter bekannter Serverschlüssel wird abgewiesen und nicht automatisch ersetzt.</p>
<p>„Passwort/Passphrase im Linux-Schlüsselbund speichern“ nutzt optional den Secret Service deines Desktops. Ist er nicht verfügbar oder wird der Zugriff abgelehnt, speichert die App nicht ersatzweise Klartext im Profil. FTPS verwendet explizites TLS mit Zertifikatsprüfung. Einfaches FTP ist unverschlüsselt und unterstützt keine SSH-Keys.</p>
''')

chapter('laufwerke', 'USB, NAS und Netzlaufwerke', 'Angeschlossene Laufwerke öffnen und Netzwerkfreigaben einbinden.', '''
<h3>Datenträger öffnen und auswerfen</h3><p>Einbindbare Datenträger erscheinen in der Orte-Leiste, auch wenn sie noch nicht eingehängt sind. Ein Klick bindet sie ein und öffnet sie. Notwendige Freigaben oder Passwörter fragt der Linux-Desktop ab. Die regelmäßige Erkennung kann einige Sekunden benötigen.</p>
<p>Unter „Verbindungen verwalten …“ findest du zusätzlich „Öffnen / Einbinden“, „Trennen / Auswerfen“ und „Aktualisieren“. Beende Dateiaktionen vor dem Auswerfen. Unformatierte Datenträger werden dabei nicht automatisch formatiert.</p>
''' + figure('18-verbindungen', 'Verbindungsverwaltung mit beispielhafter SSD und eingegebener NAS-Adresse. Die Einträge sind Demonstrationsdaten.') + '''
<h3>Ein NAS per SMB öffnen</h3><ol class="steps"><li>Öffne „Einstellungen / Orte → Verbindungen verwalten …“.</li><li>Trage eine Adresse wie <code>smb://nas.example.org/Fotos</code> ein.</li><li>Klicke auf „Netzlaufwerk verbinden“ und melde dich im Systemdialog an.</li><li>Öffne den danach eingebundenen Ort. Ein eingehängter GVFS-Pfad kann technisch unter <code>/run/user/…/gvfs/</code> liegen.</li></ol>
<p>Auch <code>sftp://server/pfad</code> und <code>davs://server/pfad</code> lassen sich über den Desktop anbinden. Für gezielte Passwort- oder SSH-Key-Verwaltung ist das eigene SFTP-Formular geeigneter.</p>
<h3>NTFS und Schreibrechte</h3><p>OpenCommander verwendet die Linux-Treiber und die Rechte des eingebundenen Laufwerks. Auf NTFS ist Schreiben möglich, wenn es mit einem schreibfähigen Treiber schreibbar eingebunden ist und du die nötigen Rechte hast. Ein schreibgeschütztes Laufwerk wird nicht automatisch schreibbar gemacht. Bei Einhängefehlern muss zuerst die Laufwerksursache im Betriebssystem geklärt werden.</p>
<h3>Desktop-Integration</h3><p>Einbinden, Auswerfen, System-Anmeldedialoge und „Öffnen mit“ benötigen passende Linux-Dienste. Unter Ubuntu gehören dazu GTK/PyGObject, GVFS und UDisks; die zusätzliche Kontoverwaltung verwendet GNOME Online-Konten. Auf anderen Desktops bleiben bereits eingebundene Pfade nutzbar, während einzelne Assistenten fehlen können.</p>
''')

chapter('medien', 'Bilder, Videos und Vorschau', 'Medien durchblättern, ohne jedes Mal eine weitere Anwendung zu öffnen.', '''
<p>Doppelklick oder Enter öffnet unterstützte Bilder, Videos und Audio im integrierten Betrachter. Mit „Vorschau“, <kbd>Leertaste</kbd> oder <kbd>Strg</kbd> + <kbd>Y</kbd> öffnest du die Vorschau der ausgewählten Datei. Im Dateibereich erstellt die App Bild-Thumbnails im Hintergrund; Videos benötigen dafür das optionale Systemprogramm <code>ffmpeg</code>.</p>
''' + figure('11-bildvorschau', 'Der Bildbetrachter mit zwei Beispieldateien, Pfeilnavigation und „In Papierkorb“. Bilder haben keine Video-Zeitleiste.') + '''
<div class="table-wrap"><table><thead><tr><th>Bedienung</th><th>Wirkung</th></tr></thead><tbody><tr><td><kbd>←</kbd> / <kbd>→</kbd></td><td>Vorheriges oder nächstes Medium in der sichtbaren Sortier- und Filterreihenfolge.</td></tr><tr><td><kbd>Leertaste</kbd></td><td>Audio oder Video starten/pausieren.</td></tr><tr><td><kbd>Esc</kbd></td><td>Betrachter schließen und Wiedergabe beenden.</td></tr><tr><td>In Papierkorb</td><td>Aktuelle Datei nach Bestätigung entfernen; danach erscheint das nächste Medium oder der Betrachter schließt.</td></tr></tbody></table></div>
<p>Bilder passen sich an die Fenstergröße an. Wiedergabeknopf und Zeitleiste erscheinen bei Videos. Nicht unterstützte Formate oder Codecs melden einen Fehler. Über „Öffnen mit …“ kannst du eine andere Anwendung verwenden.</p>
<h3>Medien auf Online-Speichern</h3><p>Online-Videos und Audio werden vor der Wiedergabe vollständig in einen privaten temporären Speicher geladen. Das ermöglicht danach zuverlässigeres Springen in der Zeitleiste. Währenddessen zeigt die Vorschau Fortschritt, Datenmenge, Zeit und Geschwindigkeit. „Laden abbrechen“, ein Medienwechsel oder Schließen beendet den Ladevorgang.</p>
<p>Für Online-Video und Audio gilt eine Grenze von 2 GiB pro Medium; es wird ausreichend lokaler temporärer Speicher benötigt. Die Bildvorschau lädt bis zu 128 MiB pro Datei. Online-Thumbnails können ganze Bilddateien bis 32 MiB herunterladen; automatische Online-Video-Thumbnails sind nicht vorgesehen. Der Bilddecoder begrenzt den Speicherbedarf, weshalb auch komprimiert kleine, extrem hoch aufgelöste Bilder scheitern können.</p>
<p>Ein Download wird bei länger ausbleibendem Fortschritt beendet. Bilder haben zusätzlich eine kürzere Gesamtzeitgrenze als Video/Audio. Die Ladeanzeige bedeutet deshalb nicht, dass die gesamte Cloud lokal synchronisiert wird.</p>
''')

chapter('archive', 'Archive öffnen und entpacken', 'In ZIP, TGZ, 7z und RAR wie in Ordnern navigieren.', '''
<p>Öffne ein Archiv per Doppelklick. Unterstützt werden ZIP, TAR, TGZ/TAR.GZ, TAR.BZ2, TAR.XZ/TAR.ZST, 7z und RAR, soweit die jeweilige Formatvariante vom enthaltenen Backend gelesen werden kann. In Unterordnern navigierst du wie in der normalen Dateiliste.</p>
''' + figure('12-archiv', 'Ein geöffnetes ZIP mit Ordnern und Dateien. „Entpacken“ wird passend zum Archiv eingeblendet.') + '''
<h3>Einzelne Dateien entnehmen</h3><ol class="steps"><li>Öffne rechts den gewünschten Zielordner.</li><li>Markiere links im Archiv die gewünschten Einträge.</li><li>Verwende <kbd>F5</kbd> oder „Entpacken“.</li><li>Prüfe das Ergebnis im Ziel. Pfade aus dem Archiv bleiben beim Entpacken erhalten.</li></ol>
<p>Archivinhalt ist schreibgeschützt: direktes Umbenennen, Löschen oder Verschieben darin ist nicht vorgesehen. Wenn du einen Archiveintrag extern öffnest, wird eine entpackte Vorschaukopie verwendet. Änderungen an dieser Kopie werden nicht zurück ins Archiv geschrieben.</p>
<h3>Ein neues ZIP erstellen</h3><p>Markiere die Dateien und Ordner, wähle „ZIP erstellen“ und gib den Archivnamen ein. Die App erstellt ZIP-Dateien; das Lesen anderer Archivformate bedeutet nicht, dass sie auch in diesen Formaten schreiben kann.</p>
<div class="callout"><strong>Grenzen:</strong> bis zu 100.000 Einträge und insgesamt 4 GiB unkomprimierter Inhalt; Vorschau bis 128 MiB. Gefährliche Pfade, Links und Spezialdateien werden abgewiesen. Für verschlüsselte Archive gibt es keinen Passwort-Assistenten; je nach Format erscheint eine Fehlermeldung.</div>
''')

chapter('werkzeuge', 'Suchen, vergleichen, gesammelt umbenennen', 'Größere Dateibestände mit Vorschau und gezielten Werkzeugen bearbeiten.', '''
<h3>Dateien suchen</h3><p>„Suchen“ oder <kbd>Strg</kbd> + <kbd>F</kbd> öffnet die rekursive Suche. Prüfe den Suchpfad, gib einen Teilnamen oder ein Muster mit <code>*</code> und <code>?</code> ein und klicke „Starten“. <code>*.jpg</code> findet etwa passende JPG-Namen. Optional wird Groß-/Kleinschreibung berücksichtigt.</p><p>Die Treffer zeigen vollständige Pfade. Ein Doppelklick öffnet den zugehörigen Ordner im aktiven Bereich. „Abbrechen“ beendet eine laufende Suche, sobald der Dateizugriff zurückkehrt. Die Dateibereiche werden durch den Start der Suche nicht umgestellt.</p>
''' + figure('13-suchen', 'Suche nach *.txt im Beispielordner mit Ergebnissen aus Unterordnern.') + '''
<h3>Ordner vergleichen</h3><p>Öffne die zu vergleichenden Ordner links und rechts. Wähle „Werkzeuge → Ordner vergleichen“ oder <kbd>Strg</kbd> + <kbd>Alt</kbd> + <kbd>C</kbd>, dann „Starten“. Das Ergebnis unterscheidet „Gleich“, „Unterschiedlich“, „Nur links“, „Nur rechts“ und nicht lesbare Einträge.</p><p>Der Vergleich prüft auch Inhalte mit SHA-256. Bei Online-Dateien können dadurch umfangreiche Downloads entstehen. Er ist ein Vergleichswerkzeug und startet keine automatische Synchronisation.</p>
''' + figure('15-vergleichen', 'Vergleich der Beispielordner: gleiche Datei, unterschiedliche Datei und einseitig vorhandene Einträge.') + '''
<h3>Mehrfach umbenennen</h3><ol class="steps"><li>Markiere die betreffenden Dateien.</li><li>Öffne „Werkzeuge → Mehrfach umbenennen“ oder <kbd>Strg</kbd> + <kbd>Umschalt</kbd> + <kbd>M</kbd>.</li><li>Gib ein Muster ein, zum Beispiel <code>Reise-[C]-[N][E]</code>.</li><li>Lege Startwert und Stellenzahl des Zählers fest. Optional kannst du Text suchen und ersetzen.</li><li>Klicke „Vorschau“ und prüfe jede neue Bezeichnung.</li><li>Erst „Umbenennen anwenden“ führt die Änderung aus.</li></ol>
<div class="table-wrap"><table><thead><tr><th>Platzhalter</th><th>Bedeutung</th></tr></thead><tbody><tr><td><code>[N]</code></td><td>Alter Name ohne Erweiterung.</td></tr><tr><td><code>[E]</code></td><td>Erweiterung einschließlich Punkt, beispielsweise <code>.jpg</code>.</td></tr><tr><td><code>[C]</code></td><td>Laufender Zähler mit gewähltem Startwert und Stellenzahl.</td></tr></tbody></table></div>
''' + figure('14-mehrfach-umbenennen', 'Vorschau neuer Dateinamen. Für die Aufnahme wurde die Umbenennung nicht angewendet.') + '''
<p>Änderst du die Regel nach der Vorschau, musst du erneut prüfen. Die App kontrolliert Quellen und Ziele vor dem Anwenden. Suche und Vergleich sind auf 100.000 Einträge begrenzt, Mehrfach-Umbenennen auf 10.000. Verzeichnislinks werden nicht rekursiv verfolgt. Lesefehler kennzeichnen unvollständige Ergebnisse; Archiv-Inhalte werden von diesen Werkzeugen nicht unterstützt.</p>
''')

chapter('einstellungen', 'Einstellungen und Eigenschaften', 'Darstellung anpassen und Dateiinformationen richtig lesen.', '''
<h3>Sprache und Erscheinungsbild</h3><p>„Einstellungen / Orte“ oder <kbd>Strg</kbd> + <kbd>,</kbd> öffnet das Einstellungsfenster. Wähle Deutsch oder Englisch und das gewünschte Erscheinungsbild. Die Checkbox „Dunkel“ findest du zusätzlich direkt im Hauptfenster. Diese Einstellungen werden gespeichert.</p>
''' + figure('03-einstellungen', 'Einstellungen für Sprache, dunkles Design und Verknüpfungen. Die Cloud-Verwaltung ist hier erreichbar.') + figure('02-oberflaeche-hell', 'Dieselbe Anwendung im hellen Erscheinungsbild.') + '''
<h3>Datei- und Ordnereigenschaften</h3><p>Klicke einen Eintrag rechts an und wähle „Eigenschaften“. Die App liest die Angaben im Hintergrund neu ein. Bei NAS- und Cloud-Dateien können einzelne Angaben fehlen oder vom Anbieter nur eingeschränkt gemeldet werden. „Nicht vom Dateisystem gemeldet“ ist deshalb kein Wert von null.</p>
''' + figure('16-eigenschaften', 'Eigenschaften einer lokalen Beispieldatei. Angezeigte Benutzer- und Pfadwerte stammen aus der Aufnahmeumgebung.') + '''
<p>Bei Ordnern ist die Größe des Verzeichniseintrags nicht die Größe aller enthaltenen Dateien. „Ordnergröße berechnen“ startet eine zusätzliche rekursive Abfrage. Bei Zeitgrenzen, sehr vielen Dateien oder Zugriffsfehlern wird ein Teilergebnis als unvollständig gekennzeichnet. POSIX-Rechte auf NAS- oder Cloud-Mounts können synthetische Angaben sein.</p>
''')

chapter('tastatur', 'Tastenkürzel zum Nachschlagen', 'Die wichtigsten Aktionen für die aktive Dateiliste.', '''
<div class="table-wrap"><table><thead><tr><th>Tasten</th><th>Aktion</th></tr></thead><tbody>
<tr><td><kbd>F5</kbd> / <kbd>F6</kbd></td><td>In den anderen Bereich kopieren / verschieben.</td></tr>
<tr><td><kbd>F2</kbd></td><td>Eine Datei oder einen Ordner umbenennen.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>C</kbd> / <kbd>X</kbd> / <kbd>V</kbd></td><td>Kopieren / Ausschneiden / Einfügen über die Zwischenablage.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>A</kbd></td><td>Alle Einträge der aktiven Dateiliste auswählen.</td></tr>
<tr><td><kbd>Entf</kbd></td><td>Auswahl wiederherstellbar entfernen.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>Z</kbd></td><td>Rückgängig.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>Umschalt</kbd> + <kbd>N</kbd></td><td>Neuen Ordner erstellen.</td></tr>
<tr><td><kbd>Enter</kbd> / <kbd>Strg</kbd> + <kbd>O</kbd></td><td>Ausgewählten Eintrag öffnen.</td></tr>
<tr><td><kbd>Leertaste</kbd> / <kbd>Strg</kbd> + <kbd>Y</kbd></td><td>Vorschau öffnen.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>L</kbd></td><td>Pfadzeile fokussieren.</td></tr>
<tr><td><kbd>Alt</kbd> + <kbd>↑</kbd></td><td>Übergeordneten Ordner öffnen.</td></tr>
<tr><td><kbd>Alt</kbd> + <kbd>←</kbd> / <kbd>→</kbd></td><td>Zurück / vorwärts im Ordnerverlauf.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>H</kbd></td><td>Versteckte Dateien ein-/ausblenden.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>R</kbd></td><td>Dateibereiche aktualisieren.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>F</kbd></td><td>Rekursive Suche öffnen.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>Alt</kbd> + <kbd>C</kbd></td><td>Ordner vergleichen.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>Umschalt</kbd> + <kbd>M</kbd></td><td>Mehrfach umbenennen.</td></tr>
<tr><td><kbd>Strg</kbd> + <kbd>,</kbd></td><td>Einstellungen / Orte.</td></tr>
<tr><td><kbd>F1</kbd></td><td>Kurzhilfe in der App.</td></tr>
</tbody></table></div>
<p>In Textfeldern gelten die üblichen Texteingaben: <kbd>Entf</kbd> in der Pfadzeile löscht beispielsweise Text. Im Medienbetrachter haben Pfeiltasten, Leertaste und Escape ihre eigene <a href="#medien">Medienfunktion</a>.</p>
''')

chapter('probleme', 'Wenn etwas nicht wie erwartet funktioniert', 'Vom sichtbaren Symptom zum nächsten sinnvollen Schritt.', '''
<details open><summary>Die Cloud-Dateiliste lädt lange oder bleibt stehen.</summary><div><p>Prüfe die Lade- oder Fehlermeldung im betroffenen Bereich. Nutze „Erneut laden“, wenn es angeboten wird. Bei einem abgelaufenen Konto öffne die Online-Verwaltung und melde dich erneut an. Vermeide viele gleichzeitige Wiederholungen bei Abfragelimits.</p><p>Ein alter Listenstand wird mit Hinweis und Alter angezeigt. Er bestätigt keine aktuelle Verbindung. Eigene Cloud-Abfragen sind zeitlich begrenzt; andere Dateizugriffe auf einem Mount können weiterhin länger blockieren.</p></div></details>
<details><summary>Eine entfernte Dropbox-Datei bleibt sichtbar.</summary><div><p>Prüfe zuerst, welche Version tatsächlich läuft. Eine neu installierte Version ist erst nach dem Neustart aktiv. Ab 0.3.18 werden unabhängige Löschaktionen neben Kopien ausgeführt und bestätigte Entfernungen aus der Ansicht genommen.</p><p>Bei einer reservierten Quelle oder einem Ziel kann die Aktion warten. Kontrolliere die Übertragungsübersicht und die Statusmeldung. Aktualisiere die Ansicht nach Abschluss. Suche die Datei gegebenenfalls im OpenCommander-Papierkorb – sie bleibt dort als Wiederherstellungskopie erhalten.</p></div></details>
<details><summary>Pause oder Abbrechen reagiert nicht sofort.</summary><div><p>Achte auf „Pause angefordert“ beziehungsweise „Abbruch angefordert“. Der Wunsch ist dann registriert, der aktuelle Dateizugriff aber noch nicht zurückgekehrt. Warte auf den gespeicherten Pausenstatus oder die abgeschlossene Bereinigung.</p><p>Die aktive Programmversion steht im Kopfbereich. Eine bereits lange laufende ältere Sitzung übernimmt Korrekturen aus einer neuen Installation erst nach einem regulären Neustart.</p></div></details>
<details><summary>Ein Auftrag bleibt bei 99 % stehen.</summary><div><p>Prüfe die Phase in der Karte. Schreiben, Upload-Abschluss, Inhaltsprüfung oder Quellbereinigung können noch laufen. Bytefortschritt allein ist kein Abschlussnachweis. Ein gemeldeter Fehler muss behoben werden, bevor du einen gespeicherten Auftrag fortsetzt.</p></div></details>
<details><summary>Es fehlen Thumbnails oder die Online-Vorschau ist leer.</summary><div><p>Bei Online-Bildern werden Thumbnails im Hintergrund geladen; große Dateien und fehlende Bilddecoder können dies verhindern. Online-Videos bekommen keine automatischen Thumbnails. Ihre Vorschau lädt das Medium erst vollständig herunter.</p><p>Kontrolliere Dateigröße, Verbindung und freien lokalen Speicher. Bei nicht unterstützten Formaten oder Codecs nutze „Öffnen mit …“. Für lokale Video-Thumbnails muss ffmpeg verfügbar sein.</p></div></details>
<details><summary>„Teilen mit Link“ fehlt oder ist deaktiviert.</summary><div><p>Wähle genau eine Datei oder einen Ordner in einem zugeordneten Online-Ort. Archive, symbolische Links und gewöhnliche lokale Ordner haben diese Provider-Aktion nicht. Bei iCloud werden Freigaben auf der Website verwaltet. Firmenrichtlinien oder fehlende Kontorechte können öffentliche Links verbieten.</p></div></details>
<details><summary>Ein USB-/NTFS-Laufwerk lässt sich nicht einbinden oder beschreiben.</summary><div><p>Öffne die Verbindungsverwaltung und lies die Systemmeldung. „Wrong fs type“, „bad superblock“ oder „missing helper“ sind mögliche Hinweise des Betriebssystems, keine Aufforderung zum Formatieren. Prüfe das Laufwerk zunächst mit den passenden Systemwerkzeugen.</p><p>Schreibgeschützte Mounts und fehlende Rechte bleiben auch in OpenCommander schreibgeschützt. Die Anwendung ändert keine Treiber oder Dateisystem-Reparaturflags automatisch.</p></div></details>
<details><summary>Eine gespeicherte Serververbindung fragt wieder nach dem Passwort.</summary><div><p>Ohne Schlüsselbund-Option bleiben Server-Passwörter nur in der Sitzung. Nach einem Neustart ist eine neue Eingabe normal. Prüfe bei gewünschter Speicherung, ob der Linux-Schlüsselbund verfügbar und entsperrt ist. Eine Schlüsseldatei muss weiterhin am gespeicherten Pfad liegen.</p></div></details>
<details><summary>Rückgängig ist gesperrt oder meldet einen Konflikt.</summary><div><p>Während Dateiaktionen ist Rückgängig gesperrt. Danach können veränderte Inhalte, fehlende Laufwerke oder ein belegter ursprünglicher Name eine Rücknahme verhindern. Verbinde zuerst das passende Laufwerk und prüfe die Details der Historie. Entferne keine neueren Daten nur, um die Prüfung zu umgehen.</p></div></details>
<details><summary>„Öffnen mit“ oder ein System-Anmeldedialog funktioniert nicht.</summary><div><p>Diese Funktionen benötigen die jeweiligen Linux-Desktop-Komponenten, unter anderem GTK/PyGObject und für Netzwerkfreigaben GVFS. Prüfe die angezeigte Meldung. Bereits eingebundene Dateipfade können weiterhin verwendet werden.</p></div></details>
<h3>Ein Problem nachvollziehbar melden</h3><p>Notiere die tatsächlich laufende Version, die gewählte Aktion, lokalen oder Online-Speicher, Quelle/Ziel in gekürzter Form und den genauen Fehlertext. Gib an, ob ein Kopierauftrag läuft und welcher Status angezeigt wird. Entferne persönliche Pfade aus öffentlich geteilten Aufnahmen und sende keine Passwörter, Tokens oder rclone-Konfigurationen.</p>
''')

chapter('wissen', 'Begriffe und gespeicherte Daten', 'Ein kurzer Blick auf das, was im Hintergrund passiert.', '''
<dl class="glossary"><dt>Aktiver Bereich</dt><dd>Die ausgewählte linke oder rechte Seite. Ihre Dateiauswahl ist die Quelle für Tastatur- und Werkzeugaktionen.</dd><dt>Ort / Verknüpfung</dt><dd>Ein schneller Zugang zu einem Ordner, Datenträger oder Online-Konto. Eine Verknüpfung umzubenennen ändert nicht den eigentlichen Ordnernamen.</dd><dt>Mount / Einbindung</dt><dd>Ein vom Betriebssystem bereitgestellter Dateipfad für ein Laufwerk oder einen Online-Dienst.</dd><dt>rclone / FUSE</dt><dd>Die Komponenten, die eigene Cloud- und Serververbindungen als Dateisystem bereitstellen. Die Bedienung erfolgt weiterhin in OpenCommander.</dd><dt>Cache</dt><dd>Ein zeitweiliger Zwischenspeicher für Listen oder Vorschauen. Er ist keine vollständige Offline-Kopie des Cloud-Kontos.</dd><dt>Historie / Rückgängig</dt><dd>Aufzeichnung von Dateiänderungen mit geprüfter Rücknahme. Sie hängt von den noch vorhandenen Dateien und Wiederherstellungsdaten ab.</dd></dl>
<h3>Wo die Einstellungen liegen</h3><p>Das Standardprofil liegt unter <code>~/.local/share/opencommander</code>, bei gesetztem <code>XDG_DATA_HOME</code> entsprechend darunter. Dort befinden sich Einstellungen, Historie, Auftragsjournal und private Online-Konfiguration. Vorschaukopien für externe Anwendungen können im Unterordner <code>previews</code> verbleiben.</p>
<p>Auf den jeweiligen Laufwerken können versteckte Ordner wie <code>.OpenCommanderTransfer-*</code>, <code>.OpenCommanderMove-*</code>, <code>.OpenCommanderTrash-*</code> und <code>.OpenCommanderUndo-*</code> liegen. Sie enthalten Zwischenstände oder Rücknahmedaten. Verändere sie nicht, während ein zugehöriger Auftrag offen ist. Das Löschen benötigter Rücknahmedaten macht eine Wiederherstellung unmöglich.</p>
<h3>Zum Handbuch</h3><p>Stand: 12. Oktober 2026 · OpenCommander Linux 0.3.19. Die Abbildungen zeigen reale Qt-Oberflächen mit Beispieldaten, angepassten Fenstergrößen und teilweise vorbereiteten Demonstrationszuständen. Browser-Anmeldung, Verbindungserfolg und Cloud-Freigaben werden durch die Screenshots nicht behauptet.</p><p>Dieses Handbuch funktioniert offline: Öffne <code>index.html</code> in einem Browser und behalte den Ordner <code>assets</code> sowie die CSS-/JavaScript-Dateien daneben. Die Suche durchsucht die Kapitel lokal. Über „Drucken / PDF“ kannst du die Druckansicht des Browsers verwenden. Die Gestaltungseinstellung dieses Handbuchs ist unabhängig vom Erscheinungsbild der App.</p>
''')

for kind in ['onedrive','drive','dropbox','iclouddrive']:
    shutil.copy2(ROOT.parents[1]/'opencommander/assets/providers'/f'{kind}.svg', ASSETS/f'{kind}.svg')
shutil.copy2(ROOT.parents[1]/'opencommander/assets/opencommander.png', ASSETS/'opencommander.png')
nav=''.join(f'<a href="#{identifier}"><span>{index:02d}</span>{escape(title)}</a>' for index,(identifier,title,_,_) in enumerate(chapters,1))
articles=''.join(f'<section class="chapter" id="{identifier}" aria-labelledby="title-{identifier}"><div class="chapter-heading"><span class="eyebrow">KAPITEL {index:02d}</span><h2 id="title-{identifier}">{title}</h2><p class="lead">{intro}</p></div>{body}<a class="back-top" href="#anfang">↑ Zum Anfang</a></section>' for index,(identifier,title,intro,body) in enumerate(chapters,1))
html='''<!doctype html>
<html lang="de" data-theme="light">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><meta name="description" content="Das ausführliche Anwenderhandbuch für OpenCommander Linux 0.3.19: Dateien verwalten, Cloud-Konten einrichten, Übertragungen steuern und Dateien wiederherstellen."><title>OpenCommander · Anwenderhandbuch Linux</title><link rel="icon" href="assets/opencommander.png"><link rel="stylesheet" href="handbuch.css"><script src="handbuch.js" defer></script></head>
<body><a class="skip-link" href="#inhalt">Zum Inhalt springen</a><div class="reading-progress" aria-hidden="true"></div>
<header class="topbar"><a class="brand" href="#anfang"><img src="assets/opencommander.png" width="34" height="34" alt=""><span>OpenCommander<small>ANWENDERHANDBUCH</small></span></a><div class="top-actions"><span class="version">LINUX 0.3.19</span><button type="button" id="theme-toggle" aria-label="Dunkle Darstellung einschalten">◐ <span>Darstellung</span></button><button type="button" id="print-button">Drucken / PDF</button><button type="button" id="menu-toggle" aria-expanded="false" aria-controls="sidebar">Kapitel</button></div></header>
<aside class="sidebar" id="sidebar"><label class="search-label" for="search">IM HANDBUCH SUCHEN</label><div class="search-wrap"><span aria-hidden="true">⌕</span><input id="search" type="search" autocomplete="off" placeholder="z. B. OneDrive, Pause …"><kbd aria-hidden="true">/</kbd></div><div id="search-status" role="status" aria-live="polite"></div><div id="search-results" hidden></div><nav aria-label="Kapitel">NAVIGATION</nav><div class="sidebar-foot"><span class="status-dot"></span>Offline verfügbar<br><small>18 Kapitel · 18 Screenshots<br>Stand: 12. Oktober 2026</small></div></aside>
<main id="inhalt"><div id="anfang" class="hero"><div class="hero-top"><span class="eyebrow">DEIN DATEIMANAGER. DEIN WORKFLOW.</span><span class="edition">AUSGABE 01 / LINUX</span></div><h1>Dateien im Griff.<br><span>Schritt für Schritt.</span></h1><p class="hero-intro">Vom ersten Kopieren bis zur Cloud-Verbindung: das praktische Handbuch für OpenCommander. Mit klaren Abläufen, echten Screenshots und Antworten für den Alltag.</p><div class="hero-actions"><a class="primary" href="#schnellstart">Jetzt loslegen <span>↗</span></a><a href="#probleme">Ein Problem lösen →</a></div><div class="flow" aria-label="Mit zwei Bereichen arbeiten"><div><span class="flow-label">LINKS · QUELLE</span><strong>Deine Auswahl</strong><small>Ordner öffnen · Dateien markieren</small></div><span class="flow-arrow" aria-hidden="true">→</span><div><span class="flow-label">RECHTS · ZIEL</span><strong>Dein nächster Ort</strong><small>Kopieren · Verschieben · Prüfen</small></div></div><div class="quick-links"><a href="#uebertragungen">01 <span>Aufträge &amp; Pause</span> ↗</a><a href="#cloud">02 <span>Cloud verbinden</span> ↗</a><a href="#wiederherstellen">03 <span>Wiederherstellen</span> ↗</a></div></div>
<div class="guide-note"><span>SO NUTZT DU DAS HANDBUCH</span><p>Wähle ein Kapitel links oder suche nach einem Begriff. Klicke auf Screenshots zum Vergrößern. Alle Anleitungen beziehen sich auf die Linux-Version 0.3.19.</p></div>
ARTICLES
<footer><strong>OpenCommander</strong><span>Linux-Anwenderhandbuch · 12. Oktober 2026</span><a href="#anfang">Zurück nach oben ↑</a></footer></main>
<dialog id="lightbox" aria-labelledby="lightbox-caption"><div class="lightbox-toolbar"><p id="lightbox-caption"></p><button id="zoom-lightbox" type="button" aria-pressed="false">Originalgröße</button><button id="close-lightbox" type="button" autofocus aria-label="Screenshot schließen">Schließen <kbd>Esc</kbd></button></div><div class="lightbox-image"><img id="lightbox-image" alt=""></div></dialog><noscript><div class="noscript">Alle Kapitel sind ohne JavaScript lesbar. Für Suche, Bildvergrößerung und Darstellungswechsel aktiviere JavaScript im Browser. Drucken ist über das Browsermenü möglich.</div></noscript>
</body></html>'''.replace('NAVIGATION',nav).replace('ARTICLES',articles)
(ROOT/'index.html').write_text(html)
print(f'Built {len(chapters)} chapters and {html.count("<figure>")} screenshot figures.')

# A second delivery format is a single HTML file: no extraction or asset folder needed.
import base64
import mimetypes
import re
single = html.replace('<link rel="stylesheet" href="handbuch.css">',
                      '<style>' + (ROOT/'handbuch.css').read_text() + '</style>')
single = single.replace('<script src="handbuch.js" defer></script>', '')
single = single.replace('</body>', '<script>' + (ROOT/'handbuch.js').read_text() + '</script></body>')
def embed_asset(match):
    attribute, name = match.groups()
    mime = mimetypes.guess_type(name)[0] or 'application/octet-stream'
    data = base64.b64encode((ROOT/name).read_bytes()).decode('ascii')
    return f'{attribute}="data:{mime};base64,{data}"'
single = re.sub(r'(src|href)="(assets/[^\"]+)"', embed_asset, single)
single = single.replace('Öffne <code>index.html</code> in einem Browser und behalte den Ordner <code>assets</code> sowie die CSS-/JavaScript-Dateien daneben.',
                        'In dieser Einzeldatei sind alle Screenshots, Symbole und Bedienelemente bereits enthalten. Öffne die HTML-Datei direkt in einem Browser; weitere Dateien werden nicht benötigt.')
artifacts = ROOT.parents[1] / 'artifacts'
artifacts.mkdir(exist_ok=True)
standalone = artifacts/'OpenCommander-Handbuch-Linux-0.3.19.html'
standalone.write_text(single)
print(f'Standalone HTML: {standalone.name} ({standalone.stat().st_size:,} bytes)')
