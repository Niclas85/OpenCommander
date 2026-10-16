"""Content and structured data for the public platform and cloud guides."""
import json
from html import escape

BASE = 'https://opencommander.top'
GITHUB = 'https://github.com/Niclas85/OpenCommander'
PLATFORMS = [
    dict(slug='android', name='Android', os='Android 8+', status='Kostenlos auf Google Play',
         title='Dateimanager für Android – kostenlos & Open Source',
         intro='Dateien auswählen, kopieren und verschieben: OpenCommander bringt zwei Dateibereiche auf dein Android-Smartphone, Tablet und Android TV.',
         features=['Zwei Bereiche: nebeneinander im Querformat, untereinander im Hochformat', 'Dateien per Drag & Drop kopieren und verschieben', 'ZIP-Archive durchsuchen und erstellen', 'Mehrfachauswahl, Aktionshistorie und unterstützte Aktionen rückgängig machen', 'Helles und dunkles Design, 20 Sprachen und Navigation per TV-Fernbedienung'],
         setup=['Öffne den Google-Play-Eintrag und installiere OpenCommander auf einem kompatiblen Gerät.', 'Erlaube die benötigten Dateizugriffe und öffne einen Quellordner und einen Zielordner.', 'Wähle zunächst eine Testdatei, kopiere sie in den Zielordner und kontrolliere das Ergebnis.'],
         limit='Android gibt den Dateizugriff über seine Berechtigungen frei. Die Android-Version konzentriert sich auf lokale Dateiverwaltung; die vier eigenen Cloud-Verbindungen der Qt-Desktop-App sind hier nicht enthalten.',
         url='https://play.google.com/store/apps/details?id=com.opencommander', cta='Bei Google Play öffnen', source='/tree/main/app', free=True),
    dict(slug='iphone', name='iPhone & iPad', os='iOS 16+; iPadOS 16+', status='Kostenlos im App Store',
         title='Dateimanager für iPhone & iPad – Dateien und Medien',
         intro='Zwei Dateibereiche für deine freigegebenen Ordner. Organisiere Dateien und entdecke Fotos, Videos und Musik über „Speicherorte & Medien“.',
         features=['Zwei Dateibereiche und Drag & Drop', 'Freigegebene Ordner über Apples Dateien-Auswahl öffnen', 'Fotos durchwischen und Videos abspielen', 'Musikmediathek mit Suche, Alben und Künstlern', 'ZIP-Archive, Papierkorb und Aktionshistorie'],
         setup=['Installiere OpenCommander aus dem App Store auf deinem iPhone oder iPad.', 'Öffne „Speicherorte & Medien“ und gib den gewünschten Ordner oder die gewünschte Mediathek frei.', 'Öffne Quelle und Ziel in den beiden Bereichen. Kopiere eine Testdatei und prüfe sie am Ziel.'],
         limit='Die App kann auf ihren eigenen Bereich und ausdrücklich freigegebene Orte zugreifen. Private Daten anderer Apps und Systemordner bleiben geschützt. Cloud-Orte hängen von Apples Dateien-Auswahl und installierten Anbieter-Apps ab. Nur lokal verfügbare, ungeschützte Musiktitel lassen sich exportieren.',
         url='https://apps.apple.com/de/app/opencommander/id6804432999', cta='Im App Store öffnen', source='/tree/main/ios', free=True),
    dict(slug='windows', name='Windows', os='Windows 11 x64 (geprüft)', status='Entwicklungsversion · Anleitung & Quellcode',
         title='Dateimanager für Windows – Dateien, Clouds und Server',
         intro='OpenCommander verbindet zwei Dateibereiche mit Windows-Laufwerken, NAS, Cloud-Konten und Serververbindungen. Windows und Linux teilen sich den Qt-Funktionskern.',
         features=['Google Drive, OneDrive, Dropbox und iCloud direkt verbinden', 'SMB, SFTP, FTP/FTPS und WebDAV nutzen', 'Dateien suchen, Ordner vergleichen und mehrere Dateien umbenennen', 'Übertragungen pausieren und unterstützte Aufträge nach einem Neustart fortsetzen', 'Handys und Kameras über Windows Portable Devices / MTP einbinden'],
         setup=['Lies die Windows-Anleitung für die benötigte Umgebung und den Paketbau aus dem Quellcode.', 'Richte für Cloud- und MTP-Einbindungen WinFsp ein. Die Anleitung beschreibt die zusätzlichen Komponenten.', 'Starte OpenCommander und prüfe zunächst lokale Ordner. Verbinde anschließend die benötigten Clouds oder Server.'],
         limit='Geprüfter Stand: 0.3.25rc10 unter Windows 11 x64. Es gibt noch kein öffentliches Windows-Release auf GitHub; das lokal geprüfte Paket ist unsigniert. Windows 10, ARM64 und nicht getestete MTP-Geräte sind nicht zugesichert. Die öffentliche Google-OAuth-Prüfung ist noch offen.',
         url='/docs/#windows', cta='Windows-Anleitung öffnen', source='/tree/codex/linux-desktop/windows', image='desktop-dark.png',
         caption='Die gemeinsame Qt-Bedienung, hier in der Linux-Version abgebildet. Windows-Systemdialoge und Gerätezugriffe unterscheiden sich.'),
    dict(slug='linux', name='Linux', os='Linux x86_64; Paketbau auf Ubuntu 24.04', status='Entwicklungsversion · Handbuch & Quellcode',
         title='Dateimanager für Linux – zwei Bereiche, Cloud und NAS',
         intro='Ein nativer Qt-Dateimanager mit zwei unabhängigen Bereichen, Tastenkürzeln, Vorschau und Übertragungswarteschlange. Das vollständige Desktop-Handbuch ist direkt hier verfügbar.',
         features=['Gemeinsamer Qt-Funktionskern mit Windows', 'Cloud-Verbindungen über rclone und FUSE', 'USB, NAS und MTP über GNOME / GVFS', 'Dateisuche, Ordnervergleich und Mehrfachumbenennung', 'Persistente Historie, geprüfte Rücknahme und Offline-Handbuch'],
         setup=['Öffne die Linux-Build-Anleitung im Projektquellcode und installiere die dort genannten Abhängigkeiten für deine Distribution.', 'Baue beziehungsweise starte die Qt-Anwendung gemäß der Anleitung. Der Paketbau verwendet Ubuntu 24.04.', 'Folge dem Schnellstart im Handbuch und öffne zunächst zwei lokale Ordner. Richte weitere Speicherorte bei Bedarf ein.'],
         limit='Die erforderlichen Desktop-Dienste unterscheiden sich je nach Distribution. Die Qt-Version wird im Branch codex/linux-desktop entwickelt; aktuell ist kein öffentliches Linux-Paket auf GitHub verlinkt. Das Handbuch dokumentiert Linux 0.3.21. Die öffentliche Google-OAuth-Prüfung ist noch offen.',
         url='/docs/handbuch/', cta='Linux-Handbuch öffnen', source='/tree/codex/linux-desktop/linux', image='desktop-light.png', caption='OpenCommander unter Linux: Quelle und Ziel nebeneinander, mit eigenem Ordnerbaum und Dateiliste.'),
    dict(slug='macos', name='macOS', os='macOS, Apple Silicon (ARM64)', status='Öffentliche Vorschau · Version 1.2',
         title='Dateimanager für macOS – OpenCommander für Apple Silicon',
         intro='Die Mac-Catalyst-Version kombiniert zwei Dateibereiche mit Mac-Tastenkürzeln, Quick Look und dem Öffnen von Dateien in deinen Standardprogrammen.',
         features=['Ordnerbäume, Dateilisten und Drag & Drop', 'Quick Look und „Öffnen mit“', 'Mac-Tastenkürzel und Zwischenablage', 'Lokale Laufwerke und eingebundene Cloud-Ordner', 'ZIP-Archive und Wiederherstellung unterstützter Aktionen'],
         setup=['Öffne die GitHub-Veröffentlichung der macOS-Vorschau und lies die Hinweise zum ARM64-Paket.', 'Installiere die Vorschau nach den Release-Hinweisen auf deinem Mac mit Apple Silicon.', 'Gib die benötigten Ordner über macOS frei. Cloud-Ordner müssen von der jeweiligen Anbieter-App eingebunden sein.'],
         limit='Version 1.2 ist eine öffentliche ARM64-Vorschau, kein stabiles Release. Die Mac-Catalyst-App hat einen eigenen Funktionsumfang; die direkten Cloud-Verbindungen von Windows/Linux gehören nicht dazu. Der experimentelle NTFS-Schreibtreiber ist nicht produktionsreif.',
         url=GITHUB+'/releases/tag/macos-v1.2-preview.20260912', cta='macOS-Vorschau auf GitHub', source='/tree/main/ios'),
]


def structured(data):
    return '<script type="application/ld+json">'+json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')+'</script>'


def software(p):
    result = {'@type':'SoftwareApplication', '@id':BASE+'/'+p['slug']+'/#software',
              'name':'OpenCommander für '+p['name'], 'url':BASE+'/'+p['slug']+'/',
              'description':p['intro'], 'operatingSystem':p['os'], 'applicationCategory':'UtilitiesApplication',
              'license':'https://opensource.org/license/mit', 'isAccessibleForFree':True,
              'image':BASE+'/assets/icon.png', 'author':{'@type':'Person','name':'Niklaus Haenggi'},
              'featureList':p['features'], 'sameAs':GITHUB+p['source']}
    if p.get('free'):
        result['offers']={'@type':'Offer','price':'0','priceCurrency':'EUR','url':p['url']}
        result['installUrl']=p['url']
    if p['slug']=='macos':
        result['softwareVersion']='1.2 preview'
        result['releaseNotes']=p['url']
    return result


def head(title, description, path, data):
    return f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(title)} | OpenCommander</title><meta name="description" content="{escape(description, quote=True)}"><link rel="canonical" href="{BASE}{path}">
<meta property="og:title" content="{escape(title, quote=True)}"><meta property="og:description" content="{escape(description, quote=True)}"><meta property="og:type" content="website"><meta property="og:url" content="{BASE}{path}"><meta property="og:image" content="{BASE}/assets/desktop-dark.png">
<link rel="icon" href="/assets/icon.png"><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/guide.css"><script type="module" src="/site.js"></script>{structured(data)}</head><body class="detail-page">
<a class="skip" href="#inhalt">Zum Inhalt springen</a><header class="site-header"><a class="brand" href="/"><img src="/assets/icon.png" width="36" height="36" alt=""><span>OpenCommander</span></a><button class="menu-toggle" aria-expanded="false" aria-controls="navigation" aria-label="Navigation öffnen">Menü ☰</button><nav id="navigation" aria-label="Hauptnavigation"><a href="/#plattformen">Plattformen</a><a href="/cloud/">Cloud-Verwaltung</a><a href="/docs/">Dokumentation</a><a href="{GITHUB}">GitHub ↗</a></nav></header>'''


def footer():
    links=''.join(f'<a href="/{p["slug"]}/">{p["name"]}</a>' for p in PLATFORMS)
    return f'''<footer class="site-footer wrap"><div class="footer-top"><a class="brand" href="/">OpenCommander</a><nav aria-label="Plattformen">{links}</nav></div><div class="footer-bottom"><span>© 2026 Niklaus Haenggi · Open-Source-Dateimanager</span><nav aria-label="Rechtliches"><a href="/privacy">Datenschutz</a> · <a href="/impressum">Impressum</a> · <a href="{GITHUB}/issues">Support</a></nav></div></footer></body></html>'''


def breadcrumbs(label, path):
    return {'@type':'BreadcrumbList','itemListElement':[{'@type':'ListItem','position':1,'name':'OpenCommander','item':BASE+'/'},{'@type':'ListItem','position':2,'name':label,'item':BASE+path}]}


def render_platform(p):
    path='/'+p['slug']+'/'
    graph={'@context':'https://schema.org','@graph':[software(p),breadcrumbs(p['name'],path)]}
    features=''.join('<li>'+escape(f)+'</li>' for f in p['features'])
    setup=''.join('<li>'+escape(s)+'</li>' for s in p['setup'])
    image=''
    if p.get('image'):
        image=f'<figure class="guide-figure"><a href="/assets/{p["image"]}"><img src="/assets/{p["image"]}" width="1500" height="960" loading="lazy" alt="{escape(p["caption"],quote=True)}"></a><figcaption>{p["caption"]}</figcaption></figure>'
    return head(p['title'],p['intro'],path,graph)+f'''
<main id="inhalt"><section class="guide-hero wrap"><nav class="breadcrumbs" aria-label="Brotkrumennavigation"><a href="/">OpenCommander</a><span>/</span><span>{p['name']}</span></nav><div class="guide-hero-grid"><div><p class="eyebrow">OPENCOMMANDER FÜR {p['name'].upper()}</p><h1>{p['title']}</h1><p class="guide-lead">{p['intro']}</p><div class="actions"><a class="button" href="{p['url']}">{p['cta']} ↗</a><a class="text-link" href="{GITHUB+p['source']}">Quellcode ansehen →</a></div></div><aside class="release-card" aria-label="Verfügbarkeit"><img src="/assets/icon.png" width="70" height="70" alt=""><p class="eyebrow">DEINE VERSION</p><h2>{p['name']}</h2><strong>{p['status']}</strong><p>{p['os']}</p><a href="/docs/#unterschiede">Alle Plattformen vergleichen →</a></aside></div></section>
<section class="guide-section wrap"><div class="guide-columns"><div><p class="eyebrow">IM ALLTAG</p><h2>Was du damit machen kannst</h2><ul class="check-list">{features}</ul></div><div><p class="eyebrow">LOSLEGEN</p><h2>Dein Einstieg in drei Schritten</h2><ol class="guide-steps">{setup}</ol></div></div>{image}</section>
<section class="guide-section guide-soft"><div class="wrap guide-narrow"><p class="eyebrow">GUT ZU WISSEN</p><h2>Voraussetzungen & Grenzen</h2><p>{p['limit']}</p><p>Rückgängig ist nur für unterstützte Aktionen und verfügbare Wiederherstellungsdaten möglich. Es ersetzt keine Sicherung.</p><p class="source-note">Stand: 16. Oktober 2026. Grundlage: Projektquellcode, vorhandenes Handbuch und verlinkte Store- beziehungsweise Release-Seiten.</p></div></section>
<section class="guide-section wrap guide-next"><div><h2>Mehr aus deinen Dateien machen</h2><p>Die Dokumentation erklärt die Bedienung und die Unterschiede zwischen den Versionen.</p></div><div class="actions"><a class="button" href="/docs/">Dokumentation öffnen →</a><a class="text-link" href="/cloud/">Cloud-Verwaltung verstehen →</a></div></section></main>'''+footer()


def render_cloud():
    title='Google Drive, OneDrive, Dropbox & iCloud gemeinsam verwalten'
    description='Vier Cloud-Dienste in einem Dateimanager: OpenCommander für Windows und Linux. Konten verbinden, Dateien kopieren und Übertragungen prüfen.'
    graph={'@context':'https://schema.org','@graph':[{'@type':'WebPage','@id':BASE+'/cloud/#page','url':BASE+'/cloud/','name':title,'description':description,'inLanguage':'de','about':[{'@id':BASE+'/windows/#software'},{'@id':BASE+'/linux/#software'}]},breadcrumbs('Cloud-Verwaltung','/cloud/')]}
    return head(title,description,'/cloud/',graph)+'''
<main id="inhalt"><section class="guide-hero wrap"><nav class="breadcrumbs" aria-label="Brotkrumennavigation"><a href="/">OpenCommander</a><span>/</span><span>Cloud-Verwaltung</span></nav><p class="eyebrow">VIER CLOUDS. EIN DATEIMANAGER.</p><h1>Google Drive, OneDrive,<br>Dropbox & iCloud.<br><em>Gemeinsam im Blick.</em></h1><p class="guide-lead">Verbinde deine Cloud-Konten in OpenCommander für Windows und Linux. Öffne die Quelle links, das Ziel rechts – und verwalte deine Online-Dateien mit derselben Bedienung wie lokale Ordner.</p><div class="actions"><a class="button" href="#verbinden">Cloud-Konten verbinden ↓</a><a class="text-link" href="/docs/handbuch/#cloud">Zum vollständigen Handbuch →</a></div><div class="provider-strip" aria-label="Unterstützte Cloud-Dienste"><span><img src="/assets/drive.svg" width="36" height="36" alt="">Google Drive</span><span><img src="/assets/onedrive.svg" width="36" height="36" alt="">OneDrive</span><span><img src="/assets/dropbox.svg" width="36" height="36" alt="">Dropbox</span><span><img src="/assets/iclouddrive.svg" width="36" height="36" alt="">iCloud Drive</span></div></section>
<section class="guide-section guide-soft"><div class="wrap guide-columns"><div><p class="eyebrow">DEIN WORKFLOW</p><h2>Quelle links.<br>Ziel rechts.</h2><p>Ein Dokument von Google Drive nach OneDrive kopieren, einen Dropbox-Ordner auf dem Computer sichern oder Dateien nach iCloud Drive übertragen: Wähle in jedem Dateibereich den gewünschten verbundenen Ort.</p></div><div><h3>Was „Cloud zu Cloud“ hier bedeutet</h3><p>OpenCommander ist eine Desktop-App. Die Dateiübertragung läuft über deinen Computer und dessen Internetverbindung; sie ist kein garantierter direkter Transfer zwischen den Servern der Anbieter. Für laufende Aufträge muss der Computer verbunden bleiben.</p><p>Das Öffnen einer Cloud richtet keinen automatischen Abgleich aller Ordner ein. Dateikopien und Verschiebeaktionen startest du selbst. Anbieterlimits und mögliche Kosten deines Cloud-Kontos gelten weiterhin.</p></div></div></section>
<section class="guide-section wrap" id="verbinden"><p class="eyebrow">KONTEN EINRICHTEN</p><h2>Vier Dienste, klare Anmeldung</h2><p class="section-intro">Öffne „Einstellungen / Orte → Online-Orte verwalten …“. Benenne jede Verbindung verständlich, etwa „OneDrive Privat“, und wähle den Dienst. Unter Windows benötigen die Einbindungen WinFsp; Linux verwendet rclone und FUSE.</p><div class="provider-guides">
<article><img src="/assets/drive.svg" width="38" height="38" alt=""><h3>Google Drive verbinden</h3><p>Wähle „Google Drive online“ und starte die angebotene Browser-Anmeldung. Bestätige das gewünschte Google-Konto und den Zugriff.</p><p><strong>Aktueller Stand:</strong> Die öffentliche Google-OAuth-Prüfung ist noch offen. Warnhinweise und Nutzergrenzen können auftreten. Das Handbuch beschreibt bei Bedarf die Einrichtung mit eigenen Desktop-OAuth-Client-Daten.</p><a href="/docs/handbuch/#cloud">Google-Einrichtung im Handbuch →</a></article>
<article><img src="/assets/onedrive.svg" width="38" height="38" alt=""><h3>OneDrive verbinden</h3><p>Wähle „OneDrive online“ und „Mit Microsoft im Browser anmelden“. Bestätige Konto und Zugriffsfreigabe. Wenn mehrere Laufwerke angeboten werden, wähle den Bereich mit deinen Dateien.</p><p>Kontrolliere anschließend die angezeigten Ordner. So erkennst du, ob du das gewünschte private oder geschäftliche Konto verbunden hast.</p><a href="/docs/handbuch/#cloud">OneDrive-Einrichtung im Handbuch →</a></article>
<article><img src="/assets/dropbox.svg" width="38" height="38" alt=""><h3>Dropbox verbinden</h3><p>Wähle „Dropbox online“, benenne die Verbindung und starte die Anmeldung. Bestätige im neu geöffneten Browserfenster dein Konto und den Zugriff.</p><p>Lass OpenCommander während der Anmeldung geöffnet: Der Browser muss das Ergebnis an den lokalen Anmeldedialog zurückgeben können. Nutze bei einem erneuten Versuch den neu erzeugten Link.</p><a href="/docs/handbuch/#cloud">Dropbox-Einrichtung im Handbuch →</a></article>
<article><img src="/assets/iclouddrive.svg" width="38" height="38" alt=""><h3>iCloud Drive verbinden</h3><p>Wähle „iCloud Drive online“ und „Mit Apple-ID verbinden“. Gib Apple-ID, Passwort und Zwei-Faktor-Bestätigung im App-Dialog ein. App-spezifische Passwörter werden von diesem Backend nicht unterstützt.</p><p>Der Webzugriff auf iCloud-Daten muss erlaubt sein. Eine Anmeldung auf iCloud.com allein verbindet den Dateibereich von OpenCommander noch nicht.</p><a href="/docs/handbuch/#cloud">iCloud-Einrichtung im Handbuch →</a></article></div>
<figure class="guide-figure compact"><img src="/docs/handbuch/assets/04-onedrive.png" width="1080" height="620" loading="lazy" alt="OneDrive-Einrichtung in OpenCommander unter Linux mit Browser-Anmeldung; Beispielprofil."><figcaption>Echter Dialog aus dem Linux-Handbuch. Die gemeinsame Desktop-Bedienung ist vergleichbar; Dialogdetails hängen von Version und Plattform ab.</figcaption></figure></section>
<section class="guide-section guide-soft" id="kopieren"><div class="wrap guide-narrow"><p class="eyebrow">BEISPIEL: GOOGLE DRIVE → ONEDRIVE</p><h2>Dateien zwischen Clouds kopieren</h2><ol class="guide-steps"><li><strong>Beide Konten verbinden.</strong> Kontrolliere, dass die passenden Ordner sichtbar sind. Falls Google die Anmeldung blockiert, kläre zuerst die oben beschriebenen OAuth-Voraussetzungen.</li><li><strong>Quelle und Ziel öffnen.</strong> Öffne Google Drive links und den gewünschten OneDrive-Zielordner rechts.</li><li><strong>Mit einer Testdatei beginnen.</strong> Markiere eine normale lokal beziehungsweise als Datei übertragbare Datei und starte „Kopieren“. Google-native Dokumente können Export oder Konvertierung erfordern; sie sind nicht immer wie gewöhnliche Dateien kopierbar.</li><li><strong>Den Auftrag abschließen lassen.</strong> Beobachte den Fortschritt. Eine Dateiliste allein beweist noch keinen abgeschlossenen Upload.</li><li><strong>Das Ergebnis prüfen.</strong> Aktualisiere den Zielordner und öffne die kopierte Datei, bei Bedarf auch auf der Anbieter-Website. Lösche die Quelle erst, wenn das Ergebnis geprüft ist.</li></ol><p>Dasselbe Prinzip gilt für andere verbundene Cloud-Orte und lokale Ordner. Rechte, Dateitypen, Speicherplatz und Anbieterbeschränkungen können einzelne Aktionen begrenzen.</p></div></section>
<section class="guide-section wrap"><div class="guide-columns"><div><h2>Welche Plattform kann was?</h2><div class="table-scroll"><table><thead><tr><th>Plattform</th><th>Cloud-Zugriff</th></tr></thead><tbody><tr><td><a href="/windows/">Windows</a> / <a href="/linux/">Linux</a></td><td>Eigene Verbindungen zu den vier Anbietern.</td></tr><tr><td><a href="/iphone/">iPhone & iPad</a></td><td>Vom System und Anbieter freigegebene Orte in Apples Dateien-Auswahl.</td></tr><tr><td><a href="/macos/">macOS</a></td><td>Cloud-Ordner, die eine Anbieter-App auf dem Mac einbindet.</td></tr><tr><td><a href="/android/">Android</a></td><td>Lokale Dateiverwaltung; keine Zusage der vier Desktop-Cloud-Verbindungen.</td></tr></tbody></table></div></div><div><h2>Deine Daten & Zugriffe</h2><p>OpenCommander leitet deine Dateien nicht über einen eigenen OpenCommander-Server. Die App verbindet sich mit den gewählten Diensten. Anmeldedaten und Tokens gehören nicht in Screenshots oder Fehlerberichte.</p><p>Die Speicherung und Absicherung unterscheiden sich nach Plattform und Verbindungsart. Das Handbuch beschreibt die Konfiguration; ein privates Benutzerprofil ist nicht automatisch eine verschlüsselte Schlüsselbundablage.</p><p><a href="/privacy">Datenschutzerklärung lesen →</a><br><a href="/docs/handbuch/#probleme">Verbindungsprobleme im Handbuch lösen →</a></p></div></div><p class="source-note">Stand: 16. Oktober 2026. Grundlage: Desktop-Handbuch und geprüfter Windows-Entwicklungsstand. Anbieter-Anmeldungen und Freigabebedingungen können sich ändern.</p></section></main>'''+footer()


def write_pages(output):
    for p in PLATFORMS:
        folder=output/p['slug']
        folder.mkdir(parents=True, exist_ok=True)
        (folder/'index.html').write_text(render_platform(p),encoding='utf-8')
    folder=output/'cloud'
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'index.html').write_text(render_cloud(),encoding='utf-8')
