"""Capture real Qt widgets in an isolated demo profile; no user accounts or transfers.
Run: QT_QPA_PLATFORM=offscreen PYTHONPATH=linux linux/.venv/bin/python linux/docs/tools/capture_handbook.py
Transfer metrics and connection entries are illustrative UI states, labelled in the guide.
"""
from pathlib import Path
import json
import tempfile
import time
import zipfile
from PySide6.QtCore import Qt, QEvent, QPointF
from PySide6.QtGui import QImage, QPainter, QColor, QPolygonF, QFont
from PySide6.QtWidgets import QApplication
from opencommander import ui
from opencommander.filesystem import Entry
from opencommander.online_ui import OnlineDialog
from opencommander.tools_ui import ToolsDialog
from opencommander.trash_ui import TrashDialog
from opencommander.cloud_actions import ShareDialog
from opencommander.connections_ui import ConnectionsDialog
from opencommander.properties_ui import PropertiesDialog

OUTPUT = Path(__file__).resolve().parents[1] / 'handbuch/assets'
OUTPUT.mkdir(parents=True, exist_ok=True)
app = QApplication([])
app.setStyle('Fusion')
# Discovery is deliberately disabled: documentation must not access personal mounts.
ui.MainWindow.scan_integrations = lambda self: None
ui.mounted_locations = lambda: []
ConnectionsDialog.refresh = lambda self: None


def settle(seconds=.25):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        app.processEvents()
        app.sendPostedEvents(None, QEvent.DeferredDelete)
        time.sleep(.01)


def wait(predicate, timeout=10):
    until = time.monotonic() + timeout
    while not predicate():
        settle(.05)
        if time.monotonic() > until:
            raise RuntimeError('Screenshot fixture did not settle')
    settle()


def shot(widget, name):
    widget.show()
    settle(.4)
    assert widget.grab().save(str(OUTPUT / (name + '.png')))
    print(name, widget.width(), widget.height())


with tempfile.TemporaryDirectory(prefix='OC-Handbuch-') as temp:
    root = Path(temp)
    source, target = root / 'Reiseplanung', root / 'Ablage'
    source.mkdir(); target.mkdir()
    for name in ['Bilder', 'Dokumente', 'Rechnungen']:
        (source / name).mkdir()
    (target / 'Archiv').mkdir()
    (target / 'Freigaben').mkdir()
    (source / 'Reiseplan.txt').write_text('ALPENREISE 2026\n\nTag 1: Anreise und Spaziergang am See\nTag 2: Wanderung zur Berghütte\nTag 3: Fotografieren und Rückreise\n')
    (source / 'Budget.csv').write_text('Posten,Betrag\nBahn,120\nUnterkunft,280\nVerpflegung,95\n')
    (source / 'Packliste.md').write_text('# Packliste\n\n- Wanderschuhe\n- Kamera\n- Regenjacke\n')
    (source / 'Dokumente' / 'Buchung.txt').write_text('Beispieldokument für das Anwenderhandbuch.\n')
    (target / 'Reiseplan.txt').write_text('Reiseplanung – frühere Version\n')
    image = QImage(1200, 760, QImage.Format_RGB32)
    image.fill(QColor('#d5e9f2'))
    painter = QPainter(image)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setPen(Qt.NoPen)
    painter.setBrush(QColor('#ffe4a8')); painter.drawEllipse(880, 80, 145, 145)
    for points, color in [([(0,510),(300,130),(600,510)],'#648797'), ([(270,530),(680,70),(1100,530)],'#335c71'), ([(710,530),(1080,220),(1300,530)],'#4b7383'), ([(0,505),(1200,505),(1200,760),(0,760)],'#429ca9')]:
        painter.setBrush(QColor(color)); painter.drawPolygon(QPolygonF([QPointF(x,y) for x,y in points]))
    painter.setBrush(QColor('#f1f6f8')); painter.drawPolygon(QPolygonF([QPointF(574,188),QPointF(680,70),QPointF(775,179),QPointF(707,156),QPointF(671,194),QPointF(629,166)]))
    painter.setPen(QColor('#fff')); painter.setFont(QFont('DejaVu Sans', 26)); painter.drawText(52, 690, 'ALPENREISE 2026  /  BEISPIELBILD')
    painter.end()
    image.save(str(source / 'Bilder' / 'Alpenblick.jpg'))
    image.save(str(source / 'Bilder' / 'Seeufer.png'))
    image.save(str(source / 'Alpenblick.jpg'))
    with zipfile.ZipFile(source / 'Reiseunterlagen.zip', 'w') as archive:
        archive.write(source / 'Reiseplan.txt', 'Dokumente/Reiseplan.txt')
        archive.write(source / 'Packliste.md', 'Packliste.md')
        archive.write(source / 'Bilder' / 'Alpenblick.jpg', 'Bilder/Alpenblick.jpg')
    main = ui.MainWindow(root / 'Profil', source, target)
    main.integration_timer.stop()
    main.change_language('de')
    main.online_profiles = [dict(id='oc_demo'+str(i),name=name,kind=kind) for i,(name,kind) in enumerate([
        ('OneDrive Privat','onedrive'),('Google Drive','drive'),('Dropbox','dropbox'),('iCloud','iclouddrive')])]
    main.location_preferences = [dict(name='Beispiele',path=str(source),enabled=True,custom=True)]
    main.update_places()
    main.resize(1500,960)
    main.show()
    wait(lambda: len(main.panes[0].model.entries) >= 8)
    for pane in main.panes:
        pane.tree.setRootIndex(pane.tree_model.index(str(root)))
    def select(names):
        pane=main.panes[0]; pane.table.clearSelection()
        for row in range(pane.proxy.rowCount()):
            entry=pane.model.entries[pane.proxy.mapToSource(pane.proxy.index(row,0)).row()]
            if entry.name in names:
                pane.table.selectionModel().select(pane.proxy.index(row,0),ui.QItemSelectionModel.Select|ui.QItemSelectionModel.Rows)
        main.activate(pane)
    select(['Alpenblick.jpg','Reiseplan.txt'])
    shot(main,'01-oberflaeche-dunkel')
    main.help()
    shot(main.help_dialog, '19-hilfe')
    main.help_dialog.close()
    main.panes[0].filter.setText('kein-treffer')
    shot(main, '20-filter')
    main.panes[0].filter.clear()
    select(['Alpenblick.jpg','Reiseplan.txt'])
    main.toggle_theme(); shot(main,'02-oberflaeche-hell'); main.toggle_theme()
    main.location_settings(); main.location_settings_dialog.resize(920,500)
    shot(main.location_settings_dialog,'03-einstellungen'); main.location_settings_dialog.close()
    online=OnlineDialog(main); online.resize(1080,620); online.name.setText('OneDrive Privat')
    shot(online,'04-onedrive')
    online.provider.setCurrentIndex(online.provider.findData('drive')); online.name.setText('Google Drive')
    shot(online,'05-google-drive')
    online.provider.setCurrentIndex(online.provider.findData('sftp')); online.name.setText('Mein Server')
    online.server_form.host.setText('nas.example.org'); online.server_form.user.setText('demo')
    online.server_form.mode.setCurrentIndex(online.server_form.mode.findData('key'))
    online.server_form.key.setText('/home/demo/.ssh/id_ed25519')
    online.resize(1080,860); shot(online,'06-sftp'); online.close()
    # Actual transfer widgets with illustrative metrics only; no worker is started.
    cards=[]
    for i,(name,elapsed,done,total,files,allfiles) in enumerate([
            ('Bilder',7385,6*1024**3,10*1024**3,240,400), ('Dokumente',122,27*1024**2,90*1024**2,18,60)]):
        job=dict(id='demo'+str(i),created=time.time()+i,status='queued',sources=[str(source/name)],directory=str(target/name),move=False)
        card=main.transfers.add(job); card.state='running'; card.started=time.monotonic()-elapsed
        card.metrics=dict(bytes_done=done,bytes_total=total,files_done=files,files_total=allfiles,phase='copying',name='Alpenblick.jpg' if i==0 else 'Buchung.txt')
        main.transfers.active[job['id']]=card; cards.append(card)
    main.transfers.toggle.setChecked(True); main.transfers.render(); main.transfers.timer.stop()
    settle(); shot(main.transfers.items,'07-uebertragungen')
    for card in cards:
        card.previous_elapsed=time.monotonic()-card.started; card.started=None; card.state='paused'
    main.transfers.active.clear(); cards[1].minimize.setChecked(True); main.transfers.render()
    settle(); shot(main.transfers.items,'08-pause-kompakt')
    for card in cards: card.state='complete'
    main.transfers.clear_completed()
    main.transfer_details.hide(); main.progress.hide(); main.queue_label.clear()
    main.pause_button.hide(); main.resume_button.hide(); main.cancel_button.hide()
    main.engine.transfer([source/'Alpenblick.jpg'],target)
    main.engine.rename(source/'Packliste.md','Packliste-Reise.md')
    disposable=source/'Notizen-alt.txt'; disposable.write_text('Nur eine Beispieldatei.\n')
    main.engine.trash([disposable])
    main.refresh_all(); main.reload_history(); main.history_dock.show(); settle(.8)
    shot(main,'09-historie'); main.history_dock.hide()
    trash=TrashDialog(main); trash.items.setCurrentItem(trash.items.topLevelItem(0))
    shot(trash,'10-papierkorb'); trash.close()
    main.panes[0].navigate(source/'Bilder'); wait(lambda: len(main.panes[0].model.entries)==2)
    entry=next(e for e in main.panes[0].model.entries if e.name=='Alpenblick.jpg')
    main.open_entry(entry); wait(lambda: not main.preview_dialog.current_image.isNull())
    main.preview_dialog.resize(1150,820); shot(main.preview_dialog,'11-bildvorschau'); main.preview_dialog.close()
    main.panes[0].navigate(source,source/'Reiseunterlagen.zip')
    wait(lambda: main.panes[0].archive is not None and len(main.panes[0].model.entries)==3)
    shot(main,'12-archiv')
    main.panes[0].navigate(source); wait(lambda: main.panes[0].archive is None and len(main.panes[0].model.entries)>=8)
    main.activate(main.panes[0])
    search=ToolsDialog(main,'search'); search.query.setText('*.txt'); search.show(); search.run()
    wait(lambda: not search.pending); shot(search,'13-suchen'); search.close()
    select(['Reiseplan.txt','Budget.csv','Alpenblick.jpg'])
    rename=ToolsDialog(main,'rename'); rename.pattern.setText('Reise-[C]-[N][E]'); rename.show(); rename.run()
    wait(lambda: not rename.pending); shot(rename,'14-mehrfach-umbenennen'); rename.close()
    compare=ToolsDialog(main,'compare'); compare.show(); compare.run()
    wait(lambda: not compare.pending); shot(compare,'15-vergleichen'); compare.close()
    props=PropertiesDialog(main,next(e for e in main.panes[0].model.entries if e.name=='Reiseplan.txt'))
    props.show(); wait(lambda: props.details.toPlainText()!='Laden …')
    shot(props,'16-eigenschaften'); props.close()
    share=ShareDialog(main,main.online_profiles[2],'Alpenblick.jpg',Entry('Alpenblick.jpg',source/'Alpenblick.jpg',False))
    share.resize(780,300); shot(share,'17-teilen'); share.close()
    conn=ConnectionsDialog(main); conn.timer.stop(); conn.resize(980,630)
    conn.populate([dict(id='demo-disk',name='Foto-SSD',kind='volume',mounted=False,path='',eject=True,unmount=False)])
    conn.address.setText('smb://nas.example.org/Fotos')
    shot(conn,'18-verbindungen'); conn.close()
    main.transfers.active.clear(); main.transfers.cards.clear(); main.close()
    wait(lambda: not main.isVisible())
    main.pool.waitForDone(10000)
    settle()
print('Finished: synthetic files only; no network operations.')
