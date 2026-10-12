import time
from pathlib import Path

import pytest
from PySide6.QtCore import Qt, QUrl, QMimeData, QPointF, QEvent
from PySide6.QtGui import QDropEvent
from PySide6.QtTest import QTest, QSignalSpy
from PySide6.QtWidgets import QApplication

from opencommander.ui import MainWindow


@pytest.fixture(scope='session')
def app():
    return QApplication.instance() or QApplication([])


def wait(app, predicate, timeout=5):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        app.processEvents()
        if predicate():
            return
        QTest.qWait(10)
    raise AssertionError('Timed out waiting for desktop event')


@pytest.fixture
def window(tmp_path, app):
    left, right = tmp_path / 'left', tmp_path / 'right'
    left.mkdir()
    right.mkdir()
    (left / 'Grüße.txt').write_text('Hello from OpenCommander')
    main = MainWindow(tmp_path / 'state', left, right)
    main.transfers.parallel.setValue(1)  # Existing cases explicitly exercise serial queue behavior.
    main.show()
    wait(app, lambda: main.panes[0].proxy.rowCount() == 1)
    yield main
    wait(app, lambda: not main.busy)
    QApplication.clipboard().clear()
    main.close()
    wait(app, lambda: not main.isVisible(), timeout=20)
    main.deleteLater()
    app.sendPostedEvents(None, QEvent.DeferredDelete)
    app.processEvents()


def test_toolbar_copy_and_undo(window, app):
    left, right = window.panes
    window.activate(left)
    left.table.selectRow(0)
    result = QSignalSpy(window.operation_finished)
    window.actions['copy'].trigger()
    wait(app, lambda: result.count() == 1)
    assert result.at(0)[0] is None
    assert (right.directory / 'Grüße.txt').exists()
    window.actions['undo'].trigger()
    wait(app, lambda: result.count() == 2)
    assert result.at(1)[0] is None
    assert not (right.directory / 'Grüße.txt').exists()


def test_clipboard_cut_paste_uses_active_destination(window, app):
    left, right = window.panes
    window.activate(left)
    left.table.selectRow(0)
    window.copy_clipboard(True)
    window.activate(right)
    window.paste_clipboard()
    wait(app, lambda: not window.busy)
    assert (right.directory / 'Grüße.txt').exists()
    assert not (left.directory / 'Grüße.txt').exists()
    assert QApplication.clipboard().mimeData() is None or not QApplication.clipboard().mimeData().hasUrls()


def test_drop_uses_selected_transfer_mode(window, app):
    left, right = window.panes
    window.mode.setCurrentIndex(1)
    mime = QMimeData()
    mime.setUrls([QUrl.fromLocalFile(str(left.directory / 'Grüße.txt'))])
    event = QDropEvent(QPointF(20, 250), Qt.CopyAction, mime, Qt.LeftButton, Qt.NoModifier)
    right.table.dropEvent(event)
    wait(app, lambda: not window.busy)
    assert event.isAccepted()
    assert event.dropAction() == Qt.CopyAction  # The engine already moved; sender must not delete again.
    assert (right.directory / 'Grüße.txt').exists()
    assert not (left.directory / 'Grüße.txt').exists()


def test_path_delete_is_text_editing_not_file_removal(window, app):
    pane = window.panes[0]
    pane.table.selectRow(0)
    window.activate(pane)
    window.actions['trash'].triggered.disconnect()
    spy = QSignalSpy(window.actions['trash'].triggered)
    pane.path_edit.setFocus()
    pane.path_edit.selectAll()
    QTest.keyClick(pane.path_edit, Qt.Key_Delete)
    app.processEvents()
    assert spy.count() == 0
    assert pane.path_edit.text() == ''
    assert (pane.directory / 'Grüße.txt').exists()


def test_filter_language_and_theme(window, app):
    pane = window.panes[0]
    pane.filter.setText('missing')
    assert pane.proxy.rowCount() == 0
    pane.filter.clear()
    assert pane.proxy.rowCount() == 1
    window.change_language('de')
    assert window.actions['copy'].text() == 'Kopieren'
    window.change_language('en')
    assert window.actions['copy'].text() == 'Copy'
    previous = window.dark
    window.toggle_theme()
    assert window.dark != previous


def test_missing_folder_is_reported_not_shown_as_empty(window, app):
    pane = window.panes[0]
    pane.navigate(pane.directory / 'missing')
    wait(app, lambda: 'No such file' in pane.message.text())
    assert pane.proxy.rowCount() == 0


def test_operation_failure_unlocks_actions(window, app):
    def failure():
        raise PermissionError('fixture read-only destination')
    result = QSignalSpy(window.operation_finished)
    window.run_operation(failure)
    wait(app, lambda: result.count() == 1)
    assert not window.busy
    assert window.actions['copy'].isEnabled()
    assert 'fixture read-only' in window.status.text()


def test_browse_zip_and_copy_selected_member(window, app):
    import zipfile
    left, right = window.panes
    archive = left.directory / 'fixture.zip'
    with zipfile.ZipFile(archive, 'w') as stream:
        stream.writestr('folder/note.txt', 'inside archive')
    left.refresh()
    wait(app, lambda: left.proxy.rowCount() == 2)
    entry = next(e for e in left.model.entries if e.name == 'fixture.zip')
    left.open_entry(entry)
    wait(app, lambda: len(left.model.entries) == 1 and left.model.entries[0].name == 'folder')
    left.open_entry(left.model.entries[0])
    wait(app, lambda: len(left.model.entries) == 1 and left.model.entries[0].name == 'note.txt')
    left.table.selectRow(0)
    window.activate(left)
    window.actions['copy'].trigger()
    wait(app, lambda: not window.busy)
    assert (right.directory / 'folder' / 'note.txt').read_text() == 'inside archive'


def test_text_preview(window, app):
    from PySide6.QtWidgets import QTextEdit
    left = window.panes[0]
    window.activate(left)
    left.table.selectRow(0)
    window.actions['preview'].trigger()
    wait(app, lambda: hasattr(window, 'preview_dialog'))
    area = window.preview_dialog.findChild(QTextEdit)
    wait(app, lambda: area.toPlainText() == 'Hello from OpenCommander')
    window.preview_dialog.close()


def test_connections_open_mount_and_busy_eject(window, app, monkeypatch, tmp_path):
    from opencommander import integrations
    from opencommander.connections_ui import ConnectionsDialog
    mount = tmp_path / 'Google Drive'
    mount.mkdir()
    records = [dict(id='cloud://test', name='Google Drive', kind='Cloud', path=str(mount),
                    mounted=True, eject=False, unmount=True),
               dict(id='usb-test', name='USB', kind='USB', path=None,
                    mounted=False, eject=False, unmount=False)]
    calls = []
    def invoke(action='list', identifier=''):
        calls.append((action, identifier))
        return records
    monkeypatch.setattr(integrations, 'invoke', invoke)
    dialog = ConnectionsDialog(window)
    wait(app, lambda: not dialog.pending)
    assert dialog.items.count() == 2
    dialog.items.setCurrentRow(0)
    dialog.open_selected()
    assert window.active.directory == mount
    window.busy = True
    dialog.disconnect()
    assert not any(action == 'unmount' for action, _ in calls)
    window.busy = False
    dialog.items.setCurrentRow(1)
    dialog.open_selected()
    wait(app, lambda: not dialog.pending)
    assert ('mount', 'usb-test') in calls
    dialog.address.setText('smb://nas/share')
    dialog.connect_network()
    wait(app, lambda: not dialog.pending)
    assert ('connect', 'smb://nas/share') in calls
    dialog.close()


def test_connections_disconnect_failure_clears_busy(window, app, monkeypatch, tmp_path):
    from opencommander import integrations
    from opencommander.connections_ui import ConnectionsDialog
    from PySide6.QtWidgets import QMessageBox
    mount = tmp_path / 'USB'
    mount.mkdir()
    record = dict(id='file:///test', name='USB', kind='USB', path=str(mount),
                  mounted=True, eject=True, unmount=True)
    def invoke(action='list', identifier=''):
        if action == 'eject':
            raise RuntimeError('Device busy')
        return [record]
    monkeypatch.setattr(integrations, 'invoke', invoke)
    monkeypatch.setattr(QMessageBox, 'question', lambda *args: QMessageBox.Yes)
    dialog = ConnectionsDialog(window)
    wait(app, lambda: not dialog.pending)
    dialog.items.setCurrentRow(0)
    window.active.navigate(mount)
    dialog.disconnect()
    wait(app, lambda: not dialog.pending)
    assert not window.busy
    assert 'Device busy' in dialog.status.text()
    assert window.active.directory == Path.home()
    dialog.close()


@pytest.mark.parametrize('suffix', ['png', 'jpg'])
def test_open_image_uses_internal_viewer(window, app, tmp_path, monkeypatch, suffix):
    from PySide6.QtGui import QImage, QColor, QDesktopServices
    from PySide6.QtWidgets import QLabel
    from opencommander.filesystem import Entry
    image = QImage(80, 60, QImage.Format_RGB32)
    image.fill(QColor('coral'))
    path = tmp_path / ('Bild.' + suffix)
    assert image.save(str(path))
    external = []
    monkeypatch.setattr(QDesktopServices, 'openUrl', lambda url: external.append(url))
    window.active.open_entry(Entry(path.name, path, False))
    wait(app, lambda: hasattr(window, 'preview_dialog'))
    wait(app, lambda: not window.preview_dialog.current_image.isNull())
    labels = window.preview_dialog.findChildren(QLabel)
    assert any(not label.pixmap().isNull() for label in labels)
    assert not external
    assert window.preview_dialog.play.isHidden()
    assert window.preview_dialog.seek.isHidden()
    window.preview_dialog.close()


def test_broken_image_shows_error(window, app, tmp_path):
    from PySide6.QtWidgets import QLabel
    from opencommander.filesystem import Entry
    path = tmp_path / 'broken.png'
    path.write_bytes(b'not a PNG image')
    window.open_entry(Entry(path.name, path, False))
    wait(app, lambda: hasattr(window, 'preview_dialog'))
    wait(app, lambda: window.preview_dialog.message.text() not in ('', 'Loading …', 'Laden …'))
    assert window.preview_dialog.current_image.isNull()
    assert not window.busy
    window.preview_dialog.close()


@pytest.mark.parametrize('accept', [False, True])
def test_default_manager_prompt_once(window, monkeypatch, tmp_path, accept):
    from opencommander import desktop
    from PySide6.QtWidgets import QMessageBox
    from types import SimpleNamespace
    applications = tmp_path / 'applications'
    applications.mkdir()
    (applications / 'opencommander.desktop').write_text('[Desktop Entry]\n')
    monkeypatch.setenv('XDG_DATA_HOME', str(tmp_path))
    questions, calls = [], []
    def question(*args):
        questions.append(args)
        return QMessageBox.Yes if accept else QMessageBox.No
    def run(command, **kwargs):
        calls.append(command)
        return SimpleNamespace(stdout='opencommander.desktop\n')
    monkeypatch.setattr(QMessageBox, 'question', question)
    monkeypatch.setattr(desktop.subprocess, 'run', run)
    desktop.ask_default(window)
    desktop.ask_default(window)
    assert len(questions) == 1
    assert len(calls) == (2 if accept else 0)
    if accept:
        assert calls[0] == ['xdg-mime', 'default', 'opencommander.desktop', 'inode/directory']
        assert calls[1][:2] == ['/usr/bin/python3', '-c']
        assert 'Gio.AppInfo.get_default_for_type' in calls[1][2]


def test_default_manager_failure_can_retry(window, monkeypatch):
    from opencommander import desktop
    from PySide6.QtWidgets import QMessageBox
    import subprocess
    monkeypatch.setattr(QMessageBox, 'question', lambda *args: QMessageBox.Yes)
    warnings = []
    monkeypatch.setattr(QMessageBox, 'warning', lambda *args: warnings.append(args))
    def fail(*args, **kwargs):
        raise subprocess.CalledProcessError(1, 'xdg-mime')
    monkeypatch.setattr(desktop.subprocess, 'run', fail)
    desktop.ask_default(window)
    assert warnings
    assert not window.settings.value('default_manager_prompted', False, type=bool)


def test_media_navigation_thumbnails_and_toggle(window, app):
    from PySide6.QtGui import QImage, QColor
    from PySide6.QtWidgets import QComboBox
    pane = window.panes[0]
    for name, color in [('01.png', 'red'), ('02.png', 'blue')]:
        image = QImage(120, 60, QImage.Format_RGB32)
        image.fill(QColor(color))
        assert image.save(str(pane.directory / name))
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 3)
    entry = next(e for e in pane.model.entries if e.name == '01.png')
    row = pane.model.entries.index(entry)
    pane.model.data(pane.model.index(row, 0), Qt.DecorationRole)
    key = (str(entry.path), entry.size, entry.modified)
    wait(app, lambda: key in window.thumbnails.cache)
    assert window.thumbnails.cache[key] is not None
    assert not isinstance(window.mode, QComboBox)
    QTest.mouseClick(window.mode.switch, Qt.LeftButton)
    assert window.mode.currentData() == 'move'
    window.activate(pane)
    window.open_entry(entry)
    viewer = window.preview_dialog
    wait(app, lambda: not viewer.current_image.isNull())
    assert viewer.current_image.pixelColor(0, 0).red() == 255
    viewer.activateWindow()
    viewer.setFocus()
    QTest.keyClick(viewer, Qt.Key_Right)
    wait(app, lambda: viewer.index == 1 and not viewer.current_image.isNull())
    assert viewer.current_image.pixelColor(0, 0).blue() == 255
    QTest.keyClick(viewer, Qt.Key_Left)
    wait(app, lambda: viewer.index == 0 and not viewer.current_image.isNull())
    viewer.close()


def test_audio_opens_in_media_viewer_and_stops_on_close(window, app):
    import wave
    from opencommander.filesystem import Entry
    from PySide6.QtMultimedia import QMediaPlayer
    path = window.panes[0].directory / 'tone.wav'
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        output.writeframes(b'\x00\x00' * 8000)
    window.open_entry(Entry(path.name, path, False))
    viewer = window.preview_dialog
    wait(app, lambda: viewer.player.source().toLocalFile() == str(path))
    assert viewer.play.isEnabled()
    wait(app, lambda: viewer.player.duration() > 0)
    viewer.shutdown()
    assert viewer.player.playbackState() == QMediaPlayer.StoppedState
    assert viewer.player.source().isEmpty()
    viewer.close()


def test_video_plays_in_viewer(window, app, tmp_path):
    import shutil
    import subprocess
    from opencommander.filesystem import Entry
    if not shutil.which('ffmpeg'):
        pytest.skip('ffmpeg fixture generator not installed')
    path = tmp_path / 'movie.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=160x90:d=1',
                    '-c:v', 'mpeg4', str(path)], check=True, timeout=10)
    window.open_entry(Entry(path.name, path, False))
    viewer = window.preview_dialog
    wait(app, lambda: viewer.video.videoSink().videoFrame().isValid())
    assert viewer.stack.currentWidget() == viewer.video
    assert not viewer.play.isHidden()
    assert not viewer.seek.isHidden()
    assert viewer.player.duration() > 0
    viewer.close()


@pytest.mark.parametrize('move', [False, True])
@pytest.mark.parametrize('folder_target', [False, True])
def test_mouse_gesture_starts_drag_and_transfers(window, app, monkeypatch, move, folder_target):
    from PySide6.QtCore import QEvent, QPoint
    from PySide6.QtGui import QMouseEvent
    from opencommander import ui
    left, right = window.panes
    window.mode.setCurrentIndex(int(move))
    destination = right.directory
    drop_position = QPointF(20, 250)
    if folder_target:
        destination = right.directory / 'Destination'
        destination.mkdir()
        right.refresh()
        wait(app, lambda: right.proxy.rowCount() == 1)
        target_index = right.proxy.index(0, 0)
        assert target_index.flags() & Qt.ItemIsDropEnabled
        drop_position = QPointF(right.table.visualRect(target_index).center())
    gestures = []
    class Drag:
        def __init__(self, source):
            self.source = source
        def setMimeData(self, mime):
            self.mime = mime
        def setPixmap(self, pixmap):
            assert not pixmap.isNull() and pixmap.width() >= 250
            self.pixmap = pixmap
        def setHotSpot(self, point):
            assert point.x() > 0 and point.y() > 0
        def exec(self, actions):
            assert not self.pixmap.isNull()
            gestures.append(self.mime.urls())
            event = QDropEvent(drop_position, actions, self.mime, Qt.LeftButton, Qt.NoModifier)
            right.table.dropEvent(event)
            assert event.isAccepted()
            return Qt.CopyAction
    monkeypatch.setattr(ui, 'QDrag', Drag)
    index = left.proxy.index(0, 0)
    assert index.flags() & Qt.ItemIsDragEnabled
    viewport = left.table.viewport()
    start = left.table.visualRect(index).center()
    QTest.mousePress(viewport, Qt.LeftButton, Qt.NoModifier, start)
    for distance in (2, QApplication.startDragDistance() + 20, QApplication.startDragDistance() + 40):
        point = start + QPoint(distance, 0)
        event = QMouseEvent(QEvent.MouseMove, QPointF(point), QPointF(viewport.mapToGlobal(point)),
                            Qt.NoButton, Qt.LeftButton, Qt.NoModifier)
        QApplication.sendEvent(viewport, event)
    QTest.mouseRelease(viewport, Qt.LeftButton, Qt.NoModifier, start)
    wait(app, lambda: not window.busy)
    assert len(gestures) == 1
    assert (destination / 'Grüße.txt').read_text() == 'Hello from OpenCommander'
    assert (left.directory / 'Grüße.txt').exists() == (not move)


def test_history_details_thumbnail_and_individual_undo(window, app):
    from PySide6.QtGui import QImage, QColor
    left, right = window.panes
    image_path = left.directory / 'Photo.png'
    image = QImage(96, 64, QImage.Format_RGB32)
    image.fill(QColor('gold'))
    image.save(str(image_path))
    window.engine.transfer([image_path], right.directory)
    window.engine.transfer([left.directory / 'Grüße.txt'], right.directory)
    window.reload_history()
    window.history_dock.show()
    app.processEvents()
    assert window.history_list.count() == 2
    image_item = window.history_list.item(1)
    card = window.history_list.itemWidget(image_item)
    assert str(image_path) in card.details.toPlainText()
    assert str(right.directory / 'Photo.png') in card.details.toPlainText()
    window.history_list.scrollToItem(image_item)
    window.load_history_previews()
    wait(app, lambda: not card.thumbnail_label.pixmap().isNull())
    QTest.mouseClick(card.undo_button, Qt.LeftButton)
    wait(app, lambda: not window.busy)
    assert not (right.directory / 'Photo.png').exists()
    assert image_path.exists()
    assert (right.directory / 'Grüße.txt').exists()
    assert window.history_list.count() == 1


def test_context_properties_uses_clicked_file_and_fresh_metadata(window, app, monkeypatch):
    from PySide6.QtWidgets import QMenu
    from opencommander import properties_ui
    pane = window.panes[0]
    (pane.directory / 'Zweite.txt').write_text('different')
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 2)
    pane.table.selectRow(0)
    from PySide6.QtCore import QTimer
    QTimer.singleShot(30, lambda: app.activePopupWidget().close() if app.activePopupWidget() else None)
    index = pane.proxy.index(1, 0)
    clicked = pane.entry_at(index)
    pane.table.context_menu(pane.table.visualRect(index).center())
    assert pane.selected() == [clicked]
    monkeypatch.setattr(properties_ui, 'invoke', lambda *args:
                        dict(name=clicked.name, path=str(clicked.path), size=12345, directory=False))
    window.info()
    wait(app, lambda: '12,345 Bytes' in window.properties_dialog.details.toPlainText())
    assert clicked.name in window.properties_dialog.details.toPlainText()
    window.properties_dialog.close()


def test_toolbar_extract_only_for_archive_and_no_folder_button(window, app):
    import zipfile
    pane = window.panes[0]
    window.activate(pane)
    pane.table.selectRow(0)
    assert not window.actions['extract'].isVisible()
    assert window.actions['folder'] not in window.toolbar.actions()
    path = pane.directory / 'test.zip'
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('a.txt', 'text')
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 2)
    row = next(row for row in range(2) if pane.entry_at(pane.proxy.index(row, 0)).name == 'test.zip')
    pane.table.selectRow(row)
    assert window.actions['extract'].isVisible()
    window.activate(window.panes[1])
    assert not window.actions['extract'].isVisible()
    window.activate(pane)
    pane.open_entry(pane.selected()[0])
    wait(app, lambda: pane.archive == path and pane.proxy.rowCount() == 1)
    assert window.actions['extract'].isVisible()


def test_open_with_selected_application_and_cancel(window, app, monkeypatch):
    from opencommander import integrations
    pane = window.panes[0]
    window.activate(pane)
    pane.table.selectRow(0)
    calls = []
    def invoke(action, identifier):
        calls.append((action, identifier))
        return {'launched': False}
    monkeypatch.setattr(integrations, 'invoke', invoke)
    window.actions['open_with'].trigger()
    wait(app, lambda: window.status.text() in ('Abgebrochen', 'Cancelled'))
    assert calls == [('open-with', str(pane.directory / 'Grüße.txt'))]
    assert not window.engine.history
    assert window.status.text() in ('Abgebrochen', 'Cancelled')
    assert (pane.directory / 'Grüße.txt').exists()


def test_preview_delete_moves_to_recoverable_trash_and_advances(window, app, monkeypatch):
    from PySide6.QtGui import QImage, QColor
    from PySide6.QtWidgets import QMessageBox
    pane = window.panes[0]
    paths = [pane.directory / name for name in ('first.png', 'second.png')]
    for path in paths:
        image = QImage(20, 20, QImage.Format_RGB32)
        image.fill(QColor('red'))
        assert image.save(str(path))
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 3)
    entry = next(entry for entry in pane.model.entries if entry.name == 'first.png')
    window.open_media(entry)
    viewer = window.preview_dialog
    wait(app, lambda: not viewer.current_image.isNull())
    monkeypatch.setattr(QMessageBox, 'question', lambda *args: QMessageBox.Yes)
    viewer.trash_current()
    wait(app, lambda: not window.busy and not viewer.deleting)
    wait(app, lambda: not viewer.current_image.isNull())
    assert not paths[0].exists()
    assert viewer.entries[viewer.index].path == paths[1]
    assert window.engine.history[-1]['label'] == 'trash'
    window.show_trash()
    trash = window.trash_dialog
    assert trash.items.topLevelItemCount() == 1
    trash.items.setCurrentItem(trash.items.topLevelItem(0))
    trash.restore()
    wait(app, lambda: not window.busy and paths[0].exists())
    assert trash.items.topLevelItemCount() == 0
    viewer.close(); trash.close()


def test_preview_delete_cancel_preserves_file(window, app, monkeypatch):
    from PySide6.QtGui import QImage
    from PySide6.QtWidgets import QMessageBox
    path = window.panes[0].directory / 'keep.png'
    image = QImage(20, 20, QImage.Format_RGB32); image.fill(Qt.green); image.save(str(path))
    window.panes[0].refresh()
    wait(app, lambda: window.panes[0].proxy.rowCount() == 2)
    entry = next(entry for entry in window.panes[0].model.entries if entry.name == path.name)
    window.open_media(entry)
    viewer = window.preview_dialog
    wait(app, lambda: not viewer.current_image.isNull())
    monkeypatch.setattr(QMessageBox, 'question', lambda *args: QMessageBox.No)
    viewer.trash_current()
    assert path.exists() and not window.engine.history and not window.busy
    viewer.close()


def test_search_dialog_and_settings_language(window, app):
    window.show_tools('search')
    dialog = window.tools_dialog
    assert dialog.path.text() == str(window.active.directory)
    assert not dialog.sensitive.isChecked()
    dialog.query.setText('Grüße')
    dialog.run()
    wait(app, lambda: not dialog.pending)
    assert dialog.items.topLevelItemCount() == 1
    assert str(window.active.directory) in dialog.items.topLevelItem(0).text(0)
    dialog.close()
    from opencommander.location_settings import LocationSettingsDialog
    settings = LocationSettingsDialog(window, window.known_locations)
    settings.language_combo.setCurrentIndex(0)
    assert window.language == 'de'
    settings.close()


def test_cancelled_folder_load_ignores_stale_result(window, app, monkeypatch):
    import threading
    import opencommander.ui as ui
    entered, released = threading.Event(), threading.Event()
    def slow(*args, **kwargs):
        entered.set()
        released.wait(2)
        return []
    monkeypatch.setattr(ui, 'listing', slow)
    pane = window.panes[0]
    pane.refresh()
    wait(app, entered.is_set)
    assert pane.loading_bar.isVisible()
    pane.cancel_loading()
    assert not pane.loading_bar.isVisible()
    released.set()
    wait(app, lambda: not window.tasks)
    assert pane.message.text() == 'Abgebrochen / Cancelled'


def test_onedrive_button_starts_browser_flow_without_expert_questions(window, app, monkeypatch):
    from opencommander import online_ui
    calls = []
    monkeypatch.setattr(online_ui.rclone_runtime, 'ensure_cloud_backend', lambda _: 'fixture')
    def command(config, arguments, cancel, result=None, **kwargs):
        calls.append((list(arguments), result))
        if arguments[1] == 'create':
            return {'State': 'oauth-start', 'Option': {'Name': 'config_is_local', 'DefaultStr': 'false'}}
        return {'State': 'drive-choice', 'Option': {'Name': 'config_driveid', 'Help': 'Select drive',
                'DefaultStr': 'drive1', 'Examples': [{'Value': 'drive1', 'Help': 'Personal drive'}]}}
    monkeypatch.setattr(online_ui, 'command_json', command)
    window.online_locations()
    dialog = window.online_dialog
    assert dialog.provider.currentData() == 'onedrive'
    assert 'Browser' in dialog.next_button.text() or 'browser' in dialog.next_button.text()
    dialog.next()
    wait(app, lambda: not dialog.pending and dialog.state == 'drive-choice')
    assert calls[1][1] == 'true'
    assert '--all' not in calls[0][0]
    assert dialog.answer.currentData() == 'drive1'
    assert not window.online_profiles
    dialog.close()


def test_icloud_dialog_explains_apple_credentials_and_masks_password(window, app):
    window.online_locations()
    dialog = window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData('iclouddrive'))
    assert 'Apple' in dialog.next_button.text()
    dialog.profile = dict(id='oc_fixture', kind='iclouddrive', name='iCloud')
    dialog.cloud_auth = True
    dialog.question({'State': 'password', 'Option': {'Name': 'password', 'IsPassword': True, 'DefaultStr': ''}})
    from PySide6.QtWidgets import QLineEdit
    assert dialog.answer.lineEdit().echoMode() == QLineEdit.Password
    dialog.close()


def test_cancel_button_stops_current_online_login_worker(window, app, monkeypatch):
    import threading
    from PySide6.QtWidgets import QPushButton
    from opencommander import online_ui
    entered = threading.Event()
    monkeypatch.setattr(online_ui.rclone_runtime, 'ensure_cloud_backend', lambda _: 'fixture')
    def command(config, arguments, cancel, **kwargs):
        entered.set()
        if not cancel.wait(3):
            raise AssertionError('Cancel button did not stop the current login')
        raise RuntimeError('Abgebrochen / Cancelled')
    monkeypatch.setattr(online_ui, 'command_json', command)
    window.online_locations()
    dialog = window.online_dialog
    dialog.next()
    wait(app, entered.is_set)
    dialog.findChild(QPushButton, 'cancelOnlineLogin').click()
    wait(app, lambda: not dialog.pending)
    assert 'Cancelled' in dialog.status.text()
    assert not window.online_profiles
    dialog.close()


@pytest.mark.parametrize('kind,brand', [('onedrive', 'Microsoft'), ('drive', 'Google'), ('dropbox', 'Dropbox')])
def test_all_oauth_providers_explain_browser_and_saved_connection(window, kind, brand):
    window.online_locations()
    dialog = window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData(kind))
    assert brand in dialog.next_button.text()
    assert 'browser' in dialog.next_button.text().lower()
    assert 'restart' in dialog.help.text().lower() or 'Neustart' in dialog.help.text()
    dialog.close()


def test_onedrive_selection_labels_keep_actual_ids(window):
    window.online_locations()
    dialog = window.online_dialog
    dialog.profile = dict(id='oc_fixture', name='fixture', kind='onedrive')
    dialog.question({'State': 'drive-choice', 'Option': {'Name': 'config_driveid', 'DefaultStr': 'internal',
        'Examples': [{'Value': 'internal', 'Help': 'OCMetadataArchive (personal)'},
                     {'Value': 'real-drive-id', 'Help': 'OneDrive (personal)'}]}})
    assert dialog.answer.currentData() == 'real-drive-id'
    assert dialog.answer.currentText().startswith('OneDrive')
    assert 'real-drive-id' not in dialog.answer.currentText()
    assert not dialog.answer.isEditable()
    assert dialog.answer.count() == 2
    dialog.close()


def test_browser_signal_runs_on_gui_and_ignores_cancelled_flow(window, monkeypatch):
    import threading
    from opencommander import online_ui
    opened = []
    monkeypatch.setattr(online_ui.QDesktopServices, 'openUrl', lambda url: opened.append(url.toString()) or True)
    window.online_locations()
    dialog = window.online_dialog
    dialog.pending = True
    url = 'http://127.0.0.1:53682/auth?state=' + 'a' * 22
    dialog.browser_ready(threading.Event(), url)
    assert not opened
    dialog.browser_ready(dialog.cancel, url)
    assert opened == [url]
    assert not dialog.browser_button.isHidden()
    dialog.cancel.set()
    dialog.open_browser()
    assert opened == [url]
    dialog.pending = False
    dialog.close()


def test_saved_connection_survives_restart_and_opens_from_sidebar(window, app, monkeypatch):
    from PySide6.QtWidgets import QPushButton
    from opencommander import online_ui
    profile = dict(id='oc_persistentfixture', name='Saved Cloud Fixture', kind='onedrive')
    window.online_profiles = [profile]
    window.save_online_profiles()
    restarted = MainWindow(window.state_dir, window.panes[0].directory, window.panes[1].directory)
    restarted.show()
    try:
        assert restarted.online_profiles == [profile]
        button = next(button for button in restarted.findChildren(QPushButton, 'place') if button.text() == profile['name'])
        calls = []
        target = window.panes[1].directory
        monkeypatch.setattr(online_ui, 'mount_profile', lambda main, selected, cancel: calls.append(selected) or target)
        button.click()
        wait(app, lambda: not restarted.tasks)
        wait(app, lambda: restarted.active.directory == target)
        assert calls == [profile]
    finally:
        restarted.close()
        wait(app, lambda: not restarted.isVisible(), timeout=20)


def test_darkmode_checkbox_is_visible_and_persisted(window, app):
    from PySide6.QtWidgets import QCheckBox
    checkbox = window.findChild(QCheckBox, 'darkModeCheckbox')
    assert checkbox.isVisible()
    previous = window.dark
    checkbox.click()
    assert window.dark is not previous
    assert checkbox.isChecked() == window.dark
    assert window.settings.value('dark', type=bool) == window.dark


def test_remote_jpg_thumbnails_and_viewer_navigation(window, app, monkeypatch):
    from PySide6.QtGui import QImage, QColor
    from opencommander import filesystem
    pane = window.panes[0]
    for name, color in [('one.jpg', 'red'), ('two.JPG', 'blue')]:
        image = QImage(100, 50, QImage.Format_RGB32)
        image.fill(QColor(color))
        assert image.save(str(pane.directory / name))
    pane.remote = True
    real_remote = filesystem.remote_location
    monkeypatch.setattr(filesystem, 'remote_location', lambda path: pane.directory == path or pane.directory in path.parents or real_remote(path))
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 3)
    entries = [entry for entry in pane.model.entries if entry.name == 'one.jpg']
    entry = entries[0]
    key = (str(entry.path), entry.size, entry.modified)
    row = pane.model.entries.index(entry)
    window.thumbnails.get(entry, pane.model, row)
    wait(app, lambda: key in window.thumbnails.cache)
    assert window.thumbnails.cache[key] is not None
    try:
        wait(app, lambda: pane.proxy.rowCount() == 3 and not pane.loading_bar.isVisible())
    except AssertionError:
        raise AssertionError((str(pane.directory), pane.proxy.rowCount(), pane.message.text(), pane.loading_bar.isVisible(), [item.name for item in pane.model.entries], len(window.tasks), window.pool.activeThreadCount()))
    entry = next(item for item in pane.model.entries if item.name == 'one.jpg')
    window.activate(pane)
    window.open_media(entry)
    viewer = window.preview_dialog
    try:
        wait(app, lambda: not viewer.current_image.isNull(), timeout=15)
    except AssertionError:
        raise AssertionError((viewer.message.text(), viewer.closed, viewer.generation, [item.name for item in viewer.entries], len(window.tasks), window.pool.activeThreadCount()))
    assert viewer.current_image.pixelColor(0, 0).red() > 200
    blue_index = next(i for i, item in enumerate(viewer.entries) if item.name == 'two.JPG')
    viewer.step(blue_index - viewer.index)
    try:
        wait(app, lambda: not viewer.current_image.isNull(), timeout=15)
    except AssertionError:
        raise AssertionError((viewer.message.text(), viewer.closed, viewer.generation, [item.name for item in viewer.entries], len(window.tasks), window.pool.activeThreadCount()))
    assert viewer.current_image.pixelColor(0, 0).blue() > 200
    assert viewer.download_progress.isHidden()
    viewer.close()


def test_copy_progress_has_totals_and_keeps_summary(window, app):
    from PySide6.QtCore import Qt
    left, right = window.panes
    left.table.selectRow(0)
    window.activate(left)
    window.transfer(False)
    wait(app, lambda: not window.busy)
    details = window.transfer_details.text()
    assert '100%' in details
    assert '1 / 1' in details
    assert '/s' in details
    assert 'Zeit ' in details or 'Time ' in details
    assert ' s' in details
    assert window.transfer_details.isVisible()
    assert (right.directory / 'Grüße.txt').exists()


def test_refresh_keeps_media_neighbors_until_new_listing(window, app, monkeypatch):
    import threading
    import opencommander.ui as ui
    pane = window.panes[0]
    before = list(pane.model.entries)
    released = threading.Event()
    monkeypatch.setattr(ui, 'listing', lambda *args, **kwargs: released.wait(2) and before)
    pane.refresh()
    assert pane.model.entries == before
    released.set()
    wait(app, lambda: not pane.loading_bar.isVisible())


def test_up_selects_previous_folder_after_async_listing(window, app):
    pane = window.panes[0]
    child = pane.directory / 'previous folder'
    child.mkdir()
    pane.navigate(child)
    wait(app, lambda: getattr(pane, 'listed_location', None) == pane.location())
    pane.up()
    wait(app, lambda: bool(pane.selected()))
    assert [entry.path for entry in pane.selected()] == [child]
    assert pane.entry_at(pane.table.currentIndex()).path == child


def test_up_selects_archive_folder_and_archive_file(window, app):
    import zipfile
    pane = window.panes[0]
    archive = pane.directory / 'fixture.zip'
    with zipfile.ZipFile(archive, 'w') as stream:
        stream.writestr('folder/inside/file.txt', 'fixture')
    pane.navigate(pane.directory, archive, 'folder/inside/')
    wait(app, lambda: getattr(pane, 'listed_location', None) == pane.location())
    pane.up()
    wait(app, lambda: bool(pane.selected()))
    assert pane.selected()[0].member == 'folder/inside/'
    pane.navigate(pane.directory, archive)
    wait(app, lambda: getattr(pane, 'listed_location', None) == pane.location())
    pane.up()
    wait(app, lambda: bool(pane.selected()))
    assert pane.selected()[0].path == archive


def test_copy_keeps_navigation_preview_and_queue_available(window, app):
    import threading
    from PySide6.QtGui import QImage
    pane, target = window.panes
    image = QImage(20, 20, QImage.Format_RGB32)
    image.fill(Qt.red)
    photo = pane.directory / 'photo.jpg'
    image.save(str(photo))
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 2)
    started, release = threading.Event(), threading.Event()
    original = window.engine.transfer
    calls = []
    def slow_transfer(*args):
        calls.append(args)
        if len(calls) == 1:
            started.set()
            assert release.wait(10)
        return original(*args)
    window.engine.transfer = slow_transfer
    try:
        source = pane.directory / 'Grüße.txt'
        window.transfer(paths=[source], directory=target.directory)
        wait(app, started.is_set)
        assert window.busy
        assert window.actions['preview'].isEnabled()
        assert window.actions['search'].isEnabled()
        assert window.actions['info'].isEnabled()
        window.open_entry(next(entry for entry in pane.model.entries if entry.path == photo))
        assert window.preview_dialog.isVisible()
        window.transfer(paths=[photo], directory=target.directory)
        assert len(window.operation_queue) == 1
        assert len(calls) == 1
        assert window.queue_label.text()
        pane.navigate(target.directory)
        wait(app, lambda: getattr(pane, 'listed_location', None) == pane.location())
        assert window.busy
    finally:
        release.set()
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert (target.directory / 'Grüße.txt').exists()
    assert (target.directory / 'photo.jpg').exists()
    assert len(window.engine.history) == 2
    assert not window.queue_label.text()


def test_server_form_has_password_key_agent_and_saved_values(window, app):
    from opencommander.online_ui import OnlineDialog
    from opencommander.server_connections import settings, write_config
    dialog = OnlineDialog(window)
    dialog.provider.setCurrentIndex(dialog.provider.findData('sftp'))
    dialog.show()
    assert dialog.server_form.isVisible()
    assert dialog.server_form.port.value() == 22
    from PySide6.QtWidgets import QLineEdit
    assert dialog.server_form.secret.echoMode() == QLineEdit.Password
    assert not dialog.server_form.remember.isChecked()
    dialog.server_form.mode.setCurrentIndex(dialog.server_form.mode.findData('key'))
    assert dialog.server_form.key_row.isVisible()
    dialog.provider.setCurrentIndex(dialog.provider.findData('ftps'))
    assert dialog.server_form.mode.currentData() == 'password'
    assert not dialog.server_form.mode.isEnabled()
    section, extra = settings('sftp', 'nas.example.org', 2222, 'alice', 'password', directory='/data')
    profile = dict(id='oc_fixture', name='Test NAS', kind='sftp', **extra)
    write_config(dialog.config, profile['id'], section)
    window.online_profiles = [profile]
    window.save_online_profiles()
    dialog.reload()
    dialog.edit_saved()
    assert dialog.server_form.host.text() == 'nas.example.org'
    assert dialog.server_form.port.value() == 2222
    assert dialog.server_form.directory.text() == '/data'
    assert not dialog.pending
    dialog.close()


def test_cancel_discards_waiting_operations(window, app):
    import threading
    started, release = threading.Event(), threading.Event()
    following = []
    def slow():
        started.set()
        assert release.wait(10)
    try:
        window.run_operation(slow)
        wait(app, started.is_set)
        window.run_operation(lambda: following.append('must not run'))
        assert len(window.operation_queue) == 1
        window.cancel_button.click()
        assert window.engine.cancel.is_set()
        assert not window.operation_queue
    finally:
        release.set()
    wait(app, lambda: not window.busy)
    assert not following


def test_startup_cloud_uses_direct_listing_and_can_be_cancelled(tmp_path, app, monkeypatch):
    import threading
    from PySide6.QtCore import QSettings
    from opencommander import online_ui, ui
    from opencommander.filesystem import Entry
    state = tmp_path / 'state'; state.mkdir()
    local = tmp_path / 'local'; local.mkdir()
    profile = dict(id='oc_fixture', name='OneDrive fixture', kind='onedrive')
    root = online_ui.mount_path(state, profile['id'])
    settings = QSettings(str(state / 'settings.ini'), QSettings.IniFormat)
    import json
    settings.setValue('online_profiles', json.dumps([profile]))
    settings.setValue('pane1', str(root)); settings.setValue('pane2', str(local)); settings.sync()
    original_remote = ui.remote_location
    monkeypatch.setattr(ui, 'remote_location', lambda path: Path(path) == root or root in Path(path).parents or original_remote(path))
    started = threading.Event()
    def stalled(main, row, directory, cancel):
        started.set()
        assert cancel.wait(5)
        raise RuntimeError('Cancelled fixture')
    monkeypatch.setattr(online_ui, 'list_cloud', stalled)
    main = MainWindow(state)
    main.show()
    try:
        wait(app, started.is_set)
        pane = main.panes[0]
        assert pane.loading_bar.isVisible()
        from PySide6.QtCore import QTimer
        original_clock = time.monotonic
        with monkeypatch.context() as patch:
            patch.setattr(ui.time, 'monotonic', lambda: original_clock() + 60)
            for timer in pane.findChildren(QTimer):
                if timer.isActive() and not timer.isSingleShot() and timer.interval() == 250:
                    timer.timeout.emit()
        assert pane.load_cancel.is_set()
        assert 'antwortet nicht' in pane.message.text()
        assert pane.retry_loading.isVisible()
        pane.navigate(local)
        wait(app, lambda: getattr(pane, 'listed_location', None) == pane.location())
        assert not pane.loading_bar.isVisible()
        assert not main.busy
    finally:
        main.close()
        wait(app, lambda: not main.isVisible(), timeout=20)
        main.deleteLater()
        app.sendPostedEvents(None, QEvent.DeferredDelete)


def test_blank_space_context_menu_activates_pane_and_offers_folder_actions(window, app, monkeypatch):
    from PySide6.QtWidgets import QMenu
    from PySide6.QtCore import QPoint
    pane=window.panes[1]
    actions=[]
    from opencommander import ui
    menus=[]
    class Menu:
        def __init__(self,parent):
            self.real=QMenu(parent)
            menus.append(self)
        def __getattr__(self,name):
            return getattr(self.real,name)
        def exec(self,*args):
            actions.extend(self.real.actions())
    monkeypatch.setattr(ui,'QMenu',Menu)
    point=QPoint(10,pane.table.viewport().height()-2)
    assert not pane.table.indexAt(point).isValid()
    pane.table.context_menu(point)
    assert window.active is pane
    assert window.actions['new_folder'] in actions
    assert any(action.text() in ('Einfügen','Paste') for action in actions)
    assert any(action.text()==window.tr_key('refresh') for action in actions)
    assert window.actions['trash'] not in actions


@pytest.mark.parametrize('format,suffix', [('ustar','.tar'),('7zip','.7z')])
def test_native_archive_opens_in_pane_and_materializes_member(window, app, format, suffix):
    import libarchive
    pane=window.panes[0]
    archive_path=pane.directory/('fixture'+suffix)
    with libarchive.file_writer(str(archive_path),format) as writer:
        writer.add_file_from_memory('folder/hello.txt',5,b'hello')
    pane.refresh()
    wait(app,lambda:any(entry.path==archive_path for entry in pane.model.entries))
    pane.open_entry(next(entry for entry in pane.model.entries if entry.path==archive_path))
    wait(app,lambda:pane.archive==archive_path and pane.proxy.rowCount()==1)
    pane.open_entry(pane.model.entries[0])
    wait(app,lambda:bool(pane.model.entries) and pane.model.entries[0].member=='folder/hello.txt')
    member=pane.model.entries[0]
    assert window.materialize(member).read_bytes()==b'hello'
    assert window.actions['extract'].isVisible()


def test_online_video_loading_progress_local_playback_and_cleanup(window, app, monkeypatch, tmp_path):
    import shutil
    import subprocess
    import threading
    from opencommander import media, filesystem
    if not shutil.which('ffmpeg'):
        pytest.skip('ffmpeg required for playback fixture')
    source = tmp_path / 'online.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=160x90:d=1',
                    '-c:v', 'mpeg4', str(source)], check=True, timeout=10)
    entry = filesystem.Entry(source.name, source, False, source.stat().st_size)
    monkeypatch.setattr(filesystem, 'remote_location', lambda path: True)
    release = threading.Event()
    original = media.download_online
    def delayed(entry, target, cancel, report):
        report(entry.size // 2, entry.size)
        while not release.wait(.01):
            if cancel.is_set():
                raise RuntimeError('Cancelled')
        return original(entry, target, cancel, report)
    monkeypatch.setattr(media, 'download_online', delayed)
    viewer = media.MediaViewer(window, [entry], 0)
    viewer.show()
    try:
        wait(app, lambda: viewer.download_progress.value() >= 49)
        assert not viewer.download_progress.isHidden()
        assert not viewer.cancel_download.isHidden()
        assert 'MiB' in viewer.message.text()
        assert viewer.player.source().isEmpty()
        cache = Path(viewer.media_cache.name)
        release.set()
        wait(app, lambda: viewer.video.videoSink().videoFrame().isValid(), timeout=10)
        local = Path(viewer.player.source().toLocalFile())
        assert local.parent == cache and local.suffix == '.mp4' and local != source
        assert viewer.download_progress.isHidden()
        viewer.shutdown()
        assert not cache.exists()
    finally:
        release.set()
        viewer.close()


def test_online_video_cancel_keeps_player_empty(window, app, monkeypatch, tmp_path):
    from opencommander import media, filesystem
    monkeypatch.setattr(filesystem, 'remote_location', lambda path: True)
    def blocked(entry, target, cancel, report):
        cancel.wait(3)
        raise RuntimeError('Cancelled')
    monkeypatch.setattr(media, 'download_online', blocked)
    viewer = media.MediaViewer(window, [filesystem.Entry('blocked.mp4', tmp_path / 'blocked.mp4', False)], 0)
    viewer.show()
    cache = Path(viewer.media_cache.name)
    viewer.cancel_download.click()
    wait(app, lambda: viewer.download_progress.isHidden())
    assert viewer.player.source().isEmpty()
    assert not cache.exists()
    viewer.close()


def test_cloud_share_dialog_async_progress_result_and_cancel(window, app, monkeypatch):
    import threading
    from opencommander import cloud_actions as cloud
    from opencommander.filesystem import Entry
    profile = dict(id='oc_fixture', kind='drive', label='Fixture cloud')
    entry = Entry('folder', Path('/not-read/folder'), True)
    release = threading.Event()
    def delayed(main, profile, relative, cancel):
        while not release.wait(.01):
            if cancel.is_set():
                raise RuntimeError('Cancelled')
        return 'https://example.org/fixture-share'
    monkeypatch.setattr(cloud, 'share_link', delayed)
    dialog = cloud.ShareDialog(window, profile, 'folder', entry)
    dialog.show()
    assert dialog.url.text() == ''
    dialog.create.click()
    assert not dialog.progress.isHidden()
    assert not dialog.create.isEnabled()
    app.processEvents()
    release.set()
    wait(app, lambda: dialog.copy.isEnabled())
    assert dialog.progress.isHidden()
    dialog.copy.click()
    assert QApplication.clipboard().text() == 'https://example.org/fixture-share'
    dialog.reject()
    assert dialog.cancel.is_set() and dialog.closed
    release.clear()
    cancelled = cloud.ShareDialog(window, profile, 'folder', entry)
    cancelled.show()
    cancelled.create.click()
    cancelled.close()
    wait(app, lambda: cancelled.cancel.is_set() and not window.tasks)
    assert cancelled.url.text() == ''


def test_saved_online_place_opens_directly_without_settings(window, app, monkeypatch):
    from opencommander import online_ui
    import opencommander.ui as ui
    profile = dict(id='oc_fixture', kind='drive', name='Saved cloud')
    root = online_ui.mount_path(window.state_dir, profile['id'])
    root.mkdir(parents=True)
    window.online_profiles = [profile]
    monkeypatch.setattr(window, 'online_locations', lambda: pytest.fail('Opening must not show settings'))
    calls = []
    monkeypatch.setattr(online_ui, 'mount_profile', lambda main, row, cancel: calls.append(row['id']) or root)
    monkeypatch.setattr(ui, 'remote_location', lambda path: False)
    window.update_places()
    button = next(window.places.itemAt(i).widget() for i in range(window.places.count())
                  if window.places.itemAt(i).widget() and window.places.itemAt(i).widget().text() == profile['name'])
    button.click()
    wait(app, lambda: window.active.directory == root and not window.opening_online)
    assert calls == ['oc_fixture']
    monkeypatch.setattr(ui, 'remote_location', lambda path: path == root)
    window.open_online_profile(profile)
    assert calls == ['oc_fixture']


def test_edit_saved_place_preserves_connection_and_saves_name(window, app, monkeypatch):
    from opencommander import online_ui
    profile = dict(id='oc_fixture', kind='drive', name='Original cloud')
    window.online_profiles = [profile]
    monkeypatch.setattr(online_ui, 'mount_profile', lambda *_: pytest.fail('Editing must not connect'))
    window.edit_online_profile(profile)
    dialog = window.online_dialog
    assert dialog.isVisible()
    assert dialog.name.text() == 'Original cloud'
    assert dialog.provider.currentData() == 'drive'
    dialog.name.setText('Renamed cloud')
    dialog.save_display_name()
    assert window.online_profiles == [dict(profile, name='Renamed cloud')]
    assert 'Renamed cloud' in window.settings.value('online_profiles')
    dialog.close()


def test_pane_header_shows_saved_connection_in_subfolders_and_updates_name(window, app):
    from opencommander.online_ui import mount_path
    profile = dict(id='oc_fixture', kind='sftp', name='OneDrive Nikki')
    window.online_profiles = [profile]
    root = mount_path(window.state_dir, profile['id'])
    subfolder = root / 'Weltreise'
    subfolder.mkdir(parents=True)
    left, right = window.panes
    left.navigate(root)
    assert 'OneDrive Nikki' in left.title.text()
    assert 'OneDrive Nikki' not in right.title.text()
    left.navigate(subfolder)
    assert 'OneDrive Nikki' in left.title.text()
    profile['name'] = 'Nikki online'
    window.save_online_profiles()
    assert 'Nikki online' in left.title.text() and 'OneDrive Nikki' not in left.title.text()
    window.activate(right)
    assert 'Nikki online' in left.title.text()
    left.navigate(window.state_dir.parent)
    assert 'Nikki online' not in left.title.text()


def test_onedrive_context_menu_opens_for_remote_file_and_folder(window, app, monkeypatch):
    from opencommander.online_ui import mount_path
    from opencommander.filesystem import Entry
    from PySide6.QtWidgets import QMenu
    from PySide6.QtCore import QTimer
    profile = dict(id='oc_fixture', kind='onedrive', name='OneDrive Nikki')
    window.online_profiles = [profile]
    pane = window.panes[0]
    root = mount_path(window.state_dir, profile['id'])
    wait(app, lambda: not window.integration_scanning)
    window.integration_timer.stop()
    pane.load_cancel.set()
    pane.generation += 1
    pane.directory = root
    pane.remote = True
    pane.model.replace([Entry('file.jpg', root / 'file.jpg', False), Entry('folder', root / 'folder', True)])
    recorded = []
    def inspect():
        menu = app.activePopupWidget()
        if menu:
            online = next((a.menu() for a in menu.actions() if a.text() == 'Online · OneDrive Nikki'), None)
            recorded.append(online.actions()[0].text() if online else 'missing')
            menu.close()
    for row in range(2):
        QTimer.singleShot(30, inspect)
        index = pane.proxy.index(row, 0)
        pane.table.context_menu(pane.table.visualRect(index).center())
    assert recorded == ['Teilen mit Link …', 'Teilen mit Link …']


def test_sidebar_shows_unmounted_drive_mounts_and_opens_without_dialog(window, app, monkeypatch):
    from opencommander import integrations
    mount = window.state_dir.parent / 'USB-test'
    mount.mkdir()
    device = dict(id='fixture-volume', name='Reise USB', path=None, mounted=False, kind='Drive', eject=False, unmount=False)
    mounted = dict(device, id=mount.as_uri(), volume_id=device['id'], path=str(mount), mounted=True)
    window.integration_locations = [device]
    calls = []
    monkeypatch.setattr(integrations, 'invoke', lambda action, identifier: calls.append((action, identifier)) or [mounted])
    monkeypatch.setattr(window, 'connections', lambda: pytest.fail('Must open directly'))
    window.update_places()
    button = next(window.places.itemAt(i).widget() for i in range(window.places.count())
                  if window.places.itemAt(i).widget() and window.places.itemAt(i).widget().objectName() == 'unmountedDevice')
    assert 'Reise USB' in button.text()
    button.click()
    wait(app, lambda: window.active.directory == mount and not window.opening_devices)
    assert calls == [('mount', 'fixture-volume')]
    assert 'Reise USB' in window.active.title.text()
    assert not any(window.places.itemAt(i).widget().objectName() == 'unmountedDevice'
                   for i in range(window.places.count()) if window.places.itemAt(i).widget())


def test_sidebar_mount_failure_keeps_device_and_does_not_navigate(window, app, monkeypatch):
    from opencommander import integrations
    device = dict(id='fixture-volume', name='USB fixture', path=None, mounted=False, kind='Drive')
    window.integration_locations = [device]
    original = window.active.directory
    def failed(*args):
        raise RuntimeError('Device disconnected')
    monkeypatch.setattr(integrations, 'invoke', failed)
    window.open_device(device)
    wait(app, lambda: not window.opening_devices)
    assert window.active.directory == original
    assert 'Device disconnected' in window.status.text()


def test_external_google_drive_context_and_direct_listing(window, app, monkeypatch):
    from opencommander import online_ui
    from opencommander.filesystem import Entry
    from opencommander.cloud_actions import add_cloud_actions
    from PySide6.QtWidgets import QMenu
    import opencommander.ui as ui
    wait(app, lambda: not window.integration_scanning)
    window.integration_timer.stop()
    root = window.state_dir.parent / 'google-drive-live'
    profile = dict(id='external_fixture', kind='drive', name='Google Drive Nikki', external=True,
                   mount_root=str(root), config_path=str(window.state_dir.parent / 'external.conf'), remote_base='gdrive:')
    window.external_cloud_profiles = [profile]
    calls = []
    monkeypatch.setattr(ui, 'remote_location', lambda path: root == path or root in path.parents)
    def cloud_list(main, received, directory, cancel):
        calls.append(received)
        return [Entry('photo.jpg', directory / 'photo.jpg', False)]
    monkeypatch.setattr(online_ui, 'list_cloud', cloud_list)
    pane = window.panes[0]
    pane.navigate(root)
    wait(app, lambda: pane.proxy.rowCount() == 1 and pane.model.entries[0].name == 'photo.jpg')
    assert calls == [profile]
    assert 'Google Drive Nikki' in pane.title.text()
    pane.table.selectRow(0)
    menu = QMenu()
    add_cloud_actions(menu, pane)
    submenu = menu.actions()[-1].menu()
    assert submenu.title() == 'Online · Google Drive Nikki'
    assert submenu.actions()[0].isEnabled()


def test_folder_tree_wider_unelided_and_width_persisted(window, app):
    pane = window.panes[0]
    assert pane.tree.textElideMode() == Qt.ElideNone
    sizes = pane.tree_splitter.sizes()
    assert sizes[0] >= 220
    pane.tree_splitter.setSizes([320, 340])
    pane.tree_splitter.splitterMoved.emit(320, 1)
    assert window.settings.value('pane1_tree_sizes') == pane.tree_splitter.sizes()


def test_external_drive_survives_failed_desktop_scan(window, app, monkeypatch):
    from opencommander import external_cloud, integrations
    wait(app, lambda: not window.integration_scanning)
    window.integration_timer.stop()
    profile = dict(id='external_fixture', kind='drive', name='Google Drive', external=True,
                   mount_root=str(window.state_dir.parent / 'drive'), config_path='/unused.conf', remote_base='gdrive:')
    def unavailable(*args):
        raise RuntimeError('GVFS unavailable')
    monkeypatch.setattr(integrations, 'invoke', unavailable)
    monkeypatch.setattr(external_cloud, 'discover', lambda: [profile])
    window.scan_integrations()
    wait(app, lambda: not window.integration_scanning)
    assert window.external_cloud_profiles == [profile]


def test_cloud_list_retains_files_on_transient_error_and_stops_retry_after_navigation(window, app, monkeypatch):
    from opencommander import online_ui
    from opencommander.cloud_listing import CloudError, CloudRows
    from opencommander.filesystem import Entry
    from PySide6.QtCore import QTimer
    import opencommander.ui as ui
    wait(app, lambda: not window.integration_scanning)
    window.integration_timer.stop()
    pane = window.panes[0]
    local = pane.directory
    root = window.state_dir.parent / 'drive'
    profile = dict(id='external_fixture', kind='drive', name='Google Drive', external=True,
                   mount_root=str(root), config_path='/unused.conf', remote_base='gdrive:')
    window.external_cloud_profiles = [profile]
    monkeypatch.setattr(ui, 'remote_location', lambda path: root == path or root in path.parents)
    rows = CloudRows([Entry('photo.jpg', root / 'photo.jpg', False)])
    replies = [rows, CloudError('Provider rate limit', True), CloudRows(rows, 'Gespeicherte Dateiliste')]
    def cloud_list(*args):
        reply = replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply
    monkeypatch.setattr(online_ui, 'list_cloud', cloud_list)
    scheduled = []
    monkeypatch.setattr(QTimer, 'singleShot', lambda delay, *args: scheduled.append((delay, args[-1])))
    pane.navigate(root)
    wait(app, lambda: pane.proxy.rowCount() == 1 and not pane.loading_bar.isVisible())
    pane.refresh()
    wait(app, lambda: not pane.loading_bar.isVisible())
    assert pane.proxy.rowCount() == 1 and 'Last loaded listing' in pane.message.text()
    assert pane.retry_loading.isVisible() and scheduled[-1][0] == 10000
    scheduled[-1][1]()
    wait(app, lambda: not pane.loading_bar.isVisible())
    assert pane.proxy.rowCount() == 1 and 'Gespeicherte Dateiliste' in pane.message.text()
    assert scheduled[-1][0] == 20000
    pane.navigate(local)
    wait(app, lambda: getattr(pane, 'listed_location', None) == pane.location())
    scheduled[-1][1]()
    assert pane.directory == local and not pane.loading_bar.isVisible()


def test_google_oauth_fields_are_provider_specific_and_stay_out_of_profile_settings(window, app, monkeypatch):
    from opencommander import online_ui
    from PySide6.QtWidgets import QLineEdit
    window.online_locations()
    dialog = window.online_dialog
    assert dialog.google_client_id.isHidden()
    dialog.provider.setCurrentIndex(dialog.provider.findData('drive'))
    assert not dialog.google_client_id.isHidden()
    assert dialog.google_client_secret.echoMode() == QLineEdit.Password
    assert '2026' in dialog.help.text()
    dialog.google_client_id.setText('fixture.apps.googleusercontent.com')
    dialog.google_client_secret.setText('fixture-client-value')
    monkeypatch.setattr(online_ui.rclone_runtime, 'ensure_cloud_backend', lambda cancel: '/fixture')
    calls = []
    def command(config, arguments, cancel):
        import configparser
        saved = configparser.ConfigParser(interpolation=None)
        saved.read(config)
        assert saved[arguments[2]]['client_id'] == 'fixture.apps.googleusercontent.com'
        assert saved[arguments[2]]['client_secret'] == 'fixture-client-value'
        calls.append(arguments)
        return {'State': 'fixture-wait', 'Option': {'Name': 'scope'}}
    monkeypatch.setattr(online_ui, 'command_json', command)
    dialog.next()
    wait(app, lambda: not dialog.pending)
    assert calls and 'fixture-client-value' not in str(calls)
    assert not dialog.google_client_secret.text()
    assert 'fixture-client-value' not in str(dialog.profile)
    assert 'fixture-client-value' not in str(window.settings.value('online_profiles'))
    dialog.state = ''
    dialog.close()


def test_settings_and_gui_stay_usable_during_real_transfer(window, app):
    import threading
    from PySide6.QtCore import QTimer
    source_pane, target = window.panes
    source = source_pane.directory / 'Grüße.txt'
    destination = target.directory / source.name
    original = window.engine.copy_file
    started, release = threading.Event(), threading.Event()
    def paused_copy(src, dst):
        started.set()
        assert release.wait(10)
        return original(src, dst)
    window.engine.copy_file = paused_copy
    ticks = []
    heartbeat = QTimer(window)
    heartbeat.setInterval(10)
    heartbeat.timeout.connect(lambda: ticks.append(True))
    heartbeat.start()
    try:
        window.transfer(paths=[source], directory=target.directory)
        wait(app, started.is_set)
        assert window.busy
        window.location_settings_button.click()
        settings = window.location_settings_dialog
        assert settings.isVisible() and not settings.isModal()
        assert app.activeModalWidget() is None
        initial = window.dark
        settings.theme_checkbox.click()
        assert window.dark != initial
        window.location_settings_button.click()
        assert window.location_settings_dialog is settings
        window.activate(target)
        target.navigate(source_pane.directory)
        wait(app, lambda: len(ticks) >= 5)
        assert window.busy and window.active is target
        settings.close()
    finally:
        release.set()
        heartbeat.stop()
    wait(app, lambda: not window.busy)
    assert destination.read_text() == source.read_text()
    assert len(window.engine.history) == 1


def test_transfer_ui_updates_run_on_application_thread(window, app, monkeypatch):
    from PySide6.QtCore import QThread
    threads = []
    original = window.status.setText
    def track(text):
        threads.append(QThread.currentThread())
        original(text)
    monkeypatch.setattr(window.status, 'setText', track)
    source, target = window.panes
    window.transfer(paths=[source.directory / 'Grüße.txt'], directory=target.directory)
    wait(app, lambda: not window.busy)
    assert threads and all(thread == app.thread() for thread in threads)


@pytest.mark.parametrize('language', ['de', 'en'])
def test_places_only_open_locations_and_management_is_in_settings(window, app, monkeypatch, language):
    from PySide6.QtWidgets import QPushButton
    calls = []
    monkeypatch.setattr(window, 'online_locations', lambda: calls.append('online'))
    monkeypatch.setattr(window, 'connections', lambda: calls.append('connections'))
    window.change_language(language)
    forbidden = {'Online-Orte …', 'Online locations …', 'Verbindungen …', 'Connections …'}
    buttons = [window.places.itemAt(i).widget() for i in range(window.places.count())]
    assert all(button.text() not in forbidden for button in buttons if isinstance(button, QPushButton))
    assert any(button.objectName() == 'place' for button in buttons if button)
    window.location_settings()
    settings = window.location_settings_dialog
    assert settings.online_button.text() == ('Online-Orte verwalten …' if language == 'de' else 'Manage online locations …')
    settings.online_button.click()
    assert calls == ['online'] and not settings.isVisible()
    app.sendPostedEvents(None, QEvent.DeferredDelete)
    window.location_settings()
    settings = window.location_settings_dialog
    assert settings.connections_button.text() == ('Verbindungen verwalten …' if language == 'de' else 'Manage connections …')
    settings.connections_button.click()
    assert calls == ['online', 'connections'] and not settings.isVisible()


def test_pause_resume_buttons_keep_pending_queue(window, app):
    import threading
    source, target = window.panes
    large = source.directory / 'large.bin'
    large.write_bytes(b'a' * 3 * 1024**2)
    small = source.directory / 'later.txt'
    small.write_text('queued copy')
    original = window.engine.copy_file
    entered = threading.Event()
    def pause_in_copy(src, dst):
        report = window.engine.progress
        def blocked_progress(count, name):
            entered.set()
            assert window.engine.cancel.wait(5)
            report(count, name)
        window.engine.progress = blocked_progress
        return original(src, dst)
    window.engine.copy_file = pause_in_copy
    window.transfer(paths=[large], directory=target.directory)
    wait(app, entered.is_set)
    window.transfer(paths=[small], directory=target.directory)
    assert window.pause_button.isVisible()
    window.pause_button.click()
    wait(app, lambda: not window.busy)
    assert window.resume_button.isVisible() and window.resume_button.isEnabled()
    assert len(window.engine.transfers.jobs()) == 2
    paused = next(job for job in window.engine.transfers.jobs() if job['status'] == 'paused')
    payload = Path(paused['roots'][0]['staging']) / 'payload'
    assert payload.stat().st_size == 1024**2
    assert not (target.directory / small.name).exists()
    window.engine.copy_file = original
    window.resume_button.click()
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert (target.directory / large.name).read_bytes() == large.read_bytes()
    assert (target.directory / small.name).read_text() == 'queued copy'
    assert not window.engine.transfers.jobs()
    assert not window.resume_button.isVisible()


def test_close_saves_current_and_queued_copies_then_restart_resumes(window, app):
    import threading
    source, target = window.panes
    first = source.directory / 'first.bin'
    first.write_bytes(b'a' * 3 * 1024**2)
    second = source.directory / 'later.txt'
    second.write_text('queued copy')
    destination, state = target.directory, window.state_dir
    entered = threading.Event()
    original = window.engine.copy_file
    def wait_for_close(src, dst):
        report = window.engine.progress
        def blocked_progress(count, name):
            entered.set()
            assert window.engine.cancel.wait(5)
            report(count, name)
        window.engine.progress = blocked_progress
        return original(src, dst)
    window.engine.copy_file = wait_for_close
    window.transfer(paths=[first], directory=destination)
    wait(app, entered.is_set)
    window.transfer(paths=[second], directory=destination)
    window.close()
    wait(app, lambda: not window.isVisible(), timeout=10)
    assert not window.busy
    assert len(window.engine.transfers.jobs()) == 2
    restarted = MainWindow(state, source.directory, destination)
    restarted.show()
    try:
        wait(app, lambda: not restarted.busy and not restarted.engine.transfers.jobs(), timeout=10)
        assert (destination / first.name).read_bytes() == first.read_bytes()
        assert (destination / second.name).read_text() == 'queued copy'
        assert not list(destination.glob('.OpenCommanderTransfer-*'))
    finally:
        restarted.close()
        wait(app, lambda: not restarted.isVisible(), timeout=10)
        restarted.deleteLater()


def test_cancel_button_stops_real_copy_and_discards_queue(window, app):
    import threading
    source, target = window.panes
    first = source.directory / 'first.bin'
    first.write_bytes(b'a' * 2 * 1024**2)
    second = source.directory / 'later.txt'
    second.write_text('queued copy')
    entered = threading.Event()
    original = window.engine.copy_file
    def wait_for_cancel(src, dst):
        report = window.engine.progress
        def blocked_progress(count, name):
            entered.set()
            assert window.engine.cancel.wait(5)
            report(count, name)
        window.engine.progress = blocked_progress
        return original(src, dst)
    window.engine.copy_file = wait_for_cancel
    window.transfer(paths=[first], directory=target.directory)
    wait(app, entered.is_set)
    window.transfer(paths=[second], directory=target.directory)
    window.cancel_button.click()
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert not window.engine.transfers.jobs()
    assert not list(target.directory.iterdir())
    assert first.exists() and second.exists()


def test_unavailable_restored_copy_remains_saved_for_retry(window, app):
    source, target = window.panes
    destination = target.directory / 'not-connected'
    job = window.engine.transfers.create([source.directory / 'Grüße.txt'], destination, 'keep')
    window.resume_saved_transfers()
    wait(app, lambda: not window.busy)
    assert window.engine.transfers.get(job['id'])['status'] == 'blocked'
    assert window.resume_button.isVisible()
    destination.mkdir()
    window.resume_button.click()
    wait(app, lambda: not window.busy)
    assert (destination / 'Grüße.txt').exists()
    assert not window.engine.transfers.jobs()


def test_parallel_transfers_have_independent_controls_and_responsive_gui(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    from PySide6.QtCore import QTimer
    source, target = window.panes
    first, second = source.directory / 'first.bin', source.directory / 'second.bin'
    first.write_bytes(b'a' * 2 * 1024**2)
    second.write_bytes(b'b' * 2 * 1024**2)
    entered = {first.name: threading.Event(), second.name: threading.Event()}
    release = {first.name: threading.Event(), second.name: threading.Event()}
    original = FileEngine.copy_file
    def blocked_copy(engine, src, dst):
        if src.name in entered and engine.resuming_copy:
            entered[src.name].set()
            assert release[src.name].wait(10)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', blocked_copy)
    window.transfers.parallel.setValue(2)
    ticks = []
    timer = QTimer(window)
    timer.setInterval(10)
    timer.timeout.connect(lambda: ticks.append(time.monotonic()))
    timer.start()
    try:
        window.transfer(paths=[first], directory=target.directory)
        window.transfer(paths=[second], directory=target.directory)
        wait(app, lambda: all(event.is_set() for event in entered.values()))
        assert len(window.transfers.active) == 2
        cards = {Path(card.job['sources'][0]).name: card for card in window.transfers.cards.values()}
        one, two = cards[first.name], cards[second.name]
        window.transfers.toggle.click() if not window.transfers.toggle.isChecked() else None
        assert window.transfers.body.isVisible()
        QTest.mouseClick(one.minimize, Qt.LeftButton)
        assert not one.route.isVisible() and not one.details.isVisible()
        assert one.progress.isVisible() and one.pause.isVisible() and one.cancel.isVisible()
        assert two.route.isVisible() and two.details.isVisible()
        assert one.state == two.state == 'running'
        assert not one.engine.cancel.is_set() and not two.engine.cancel.is_set()
        QTest.mouseClick(one.minimize, Qt.LeftButton)
        assert one.route.isVisible() and one.details.isVisible()
        QTest.mouseClick(one.pause, Qt.LeftButton)
        assert one.state == 'pausing' and one.engine.pause.is_set() and one.engine.cancel.is_set()
        assert not two.engine.cancel.is_set()
        assert 'warte' in one.title.text() or 'waiting' in one.title.text()
        window.location_settings()
        assert window.location_settings_dialog.isVisible()
        window.location_settings_dialog.close()
        source.navigate(target.directory)
        wait(app, lambda: len(ticks) >= 5)
        assert max(b-a for a, b in zip(ticks, ticks[1:])) < .5
        release[first.name].set()
        wait(app, lambda: one.state == 'paused')
        assert two.state == 'running' and not two.engine.cancel.is_set()
        release[second.name].set()
        wait(app, lambda: two.state == 'complete' and not window.busy)
        assert not (target.directory / first.name).exists()
        assert (target.directory / second.name).read_bytes() == second.read_bytes()
        QTest.mouseClick(one.resume, Qt.LeftButton)
        wait(app, lambda: one.state == 'complete' and not window.busy)
        assert (target.directory / first.name).read_bytes() == first.read_bytes()
        assert len(window.engine.history) == 2
        window.transfers.clear_button.click()
        assert not window.transfers.cards
    finally:
        for event in release.values():
            event.set()
        timer.stop()


def test_parallel_conflicting_copy_and_move_wait_for_same_path(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    source, target = window.panes
    file = source.directory / 'Grüße.txt'
    third = source.directory / 'third'
    third.mkdir()
    entered, release = threading.Event(), threading.Event()
    original = FileEngine.copy_file
    def blocked_copy(engine, src, dst):
        if src == file and not entered.is_set():
            entered.set()
            assert release.wait(10)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', blocked_copy)
    window.transfers.parallel.setValue(2)
    try:
        window.transfer(paths=[file], directory=target.directory)
        wait(app, entered.is_set)
        window.transfer(True, paths=[file], directory=third)
        assert len(window.transfers.active) == 1 and len(window.operation_queue) == 1
        pending = next(card for card in window.transfers.cards.values() if card.job.get('move'))
        assert pending.state == 'waiting'
        assert file.exists()
    finally:
        release.set()
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert (target.directory / file.name).exists() and (third / file.name).exists() and not file.exists()


def test_parallel_cancel_one_preserves_other_transfer(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    source, target = window.panes
    files = [source.directory / name for name in ('cancel.bin', 'keep.bin')]
    for file in files:
        file.write_bytes(b'a' * 2 * 1024**2)
    entered = [threading.Event(), threading.Event()]
    release = threading.Event()
    original = FileEngine.copy_file
    def blocked_copy(engine, src, dst):
        if src in files:
            entered[files.index(src)].set()
            assert release.wait(10)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', blocked_copy)
    window.transfers.parallel.setValue(2)
    try:
        for file in files:
            window.transfer(paths=[file], directory=target.directory)
        wait(app, lambda: all(event.is_set() for event in entered))
        card = next(card for card in window.transfers.cards.values() if card.job['sources'] == [str(files[0])])
        QTest.mouseClick(card.cancel, Qt.LeftButton)
        assert card.state == 'cancelling' and card.engine.cancel.is_set()
        other = next(c for c in window.transfers.active.values() if c is not card)
        assert not other.engine.cancel.is_set()
    finally:
        release.set()
    wait(app, lambda: not window.busy)
    assert card.state == 'cancelled' and other.state == 'complete'
    assert not (target.directory / files[0].name).exists()
    assert (target.directory / files[1].name).exists()


def test_parallel_close_saves_all_active_transfers(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    source, target = window.panes
    files = [source.directory / name for name in ('first.bin', 'second.bin')]
    for file in files:
        file.write_bytes(b'a' * 2 * 1024**2)
    entered = [threading.Event(), threading.Event()]
    original = FileEngine.copy_file
    def wait_for_pause(engine, src, dst):
        if src in files:
            entered[files.index(src)].set()
            assert engine.cancel.wait(10)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', wait_for_pause)
    window.transfers.parallel.setValue(2)
    for file in files:
        window.transfer(paths=[file], directory=target.directory)
    wait(app, lambda: all(event.is_set() for event in entered))
    minimized = next(iter(window.transfers.cards.values()))
    minimized.minimize.click()
    minimized_id = minimized.job['id']
    window.close()
    wait(app, lambda: not window.isVisible(), timeout=10)
    assert len(window.engine.transfers.jobs()) == 2
    assert all(job['status'] == 'paused' for job in window.engine.transfers.jobs())
    monkeypatch.setattr(FileEngine, 'copy_file', original)
    restored = MainWindow(window.state_dir, source.directory, target.directory)
    restored.show()
    try:
        assert restored.transfers.parallel.value() == 2
        wait(app, lambda: minimized_id in restored.transfers.cards)
        assert restored.transfers.cards[minimized_id].minimize.isChecked()
        wait(app, lambda: not restored.busy and not restored.engine.transfers.jobs(), timeout=10)
        assert all((target.directory / file.name).read_bytes() == file.read_bytes() for file in files)
    finally:
        restored.close()
        wait(app, lambda: not restored.isVisible(), timeout=10)
        restored.deleteLater()


def test_transfer_resource_checks_never_probe_provider_paths(tmp_path, monkeypatch):
    import opencommander.filesystem as fs
    from opencommander.transfers_ui import resources, conflicts
    remote = tmp_path / 'provider'
    remote.mkdir()
    monkeypatch.setattr(fs, 'remote_location', lambda path: remote == Path(path) or remote in Path(path).parents)
    probe = Path.is_symlink
    def local_only(path):
        assert not fs.remote_location(path), 'GUI must not stat a provider'
        return probe(path)
    monkeypatch.setattr(Path, 'is_symlink', local_only)
    alias = tmp_path / 'alias'
    alias.symlink_to(remote, target_is_directory=True)
    copy = dict(sources=[str(remote / 'source')], directory=str(tmp_path / 'destination'))
    move = dict(sources=[str(alias / 'source')], directory=str(tmp_path / 'other'), move=True)
    assert conflicts(resources(copy), resources(move))


def test_parallel_paused_job_reserves_source_against_later_move(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    source, target = window.panes
    file = source.directory / 'Grüße.txt'
    other = source.directory / 'other'
    other.mkdir()
    entered = threading.Event()
    original = FileEngine.copy_file
    def wait_pause(engine, src, dst):
        entered.set()
        assert engine.cancel.wait(10)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', wait_pause)
    window.transfers.parallel.setValue(2)
    window.transfer(paths=[file], directory=target.directory)
    wait(app, entered.is_set)
    card = next(iter(window.transfers.cards.values()))
    card.pause.click()
    wait(app, lambda: not window.busy)
    monkeypatch.setattr(FileEngine, 'copy_file', original)
    window.transfer(True, paths=[file], directory=other)
    move = next(card for card in window.transfers.cards.values() if card.job.get('move'))
    assert move.state == 'waiting' and not window.busy and file.exists()
    card.resume.click()
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert card.state == move.state == 'complete'
    assert (target.directory / file.name).exists() and (other / file.name).exists()


def test_parallel_reserves_keep_both_filename_family(tmp_path):
    from opencommander.transfers_ui import conflicts, resources
    a = dict(sources=[str(tmp_path / 'a' / 'photo.jpg')], directory=str(tmp_path / 'target'))
    b = dict(sources=[str(tmp_path / 'b' / 'photo (2).jpg')], directory=str(tmp_path / 'target'))
    assert conflicts(resources(a), resources(b))
    b['sources'] = [str(tmp_path / 'b' / 'other.jpg')]
    assert not conflicts(resources(a), resources(b))


def test_refresh_preserves_selection_while_copy_changes_directory(window, app):
    pane = window.panes[0]
    selected = pane.directory / 'Grüße.txt'
    pane.table.selectRow(0)
    (pane.directory / 'new.txt').write_text('arrived during copy')
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 2 and not pane.loading_bar.isVisible())
    assert [entry.path for entry in pane.selected()] == [selected]
    assert pane.entry_at(pane.table.currentIndex()).path == selected
    selected.unlink()
    pane.refresh()
    wait(app, lambda: pane.proxy.rowCount() == 1 and not pane.loading_bar.isVisible())
    assert not pane.selected()


def test_file_model_formats_only_requested_cells_and_handles_invalid_dates(window, monkeypatch):
    from opencommander import ui
    from opencommander.filesystem import Entry
    pane = window.panes[0]
    entries = [Entry('example.txt', pane.directory / 'example.txt', False, 2048, 1e30)]
    pane.model.replace(entries)
    calls = []
    original = ui.human_size
    monkeypatch.setattr(ui, 'human_size', lambda size: (calls.append(size), original(size))[1])
    assert pane.model.data(pane.model.index(0, 0)) == 'example.txt'
    assert pane.model.data(pane.model.index(0, 3)) == '—'
    assert not calls
    for _ in range(10):
        assert pane.model.data(pane.model.index(0, 1)) == '2.0 KiB'
    assert calls == [2048]
    entries[0].path = pane.directory / 'archive.zip'
    entries[0].member = 'example.txt'
    assert pane.model.data(pane.model.index(0, 2)) == 'TXT'
    assert pane.model.data(pane.model.index(0, 2), Qt.UserRole) == '.txt'
    entries[0].size = 4096
    pane.model.replace(entries)
    assert pane.model.data(pane.model.index(0, 1)) == '4.0 KiB'


def test_transfer_duration_and_idle_rendering(window, monkeypatch):
    job = window.engine.transfers.create([window.panes[0].directory / 'Grüße.txt'],
                                        window.panes[1].directory, 'keep', [])
    card = window.transfers.add(job)
    card.state = 'paused'
    card.previous_elapsed = 7385
    card.metrics = dict(bytes_done=1024, bytes_total=2048, files_done=0, files_total=1,
                        phase='copying', name='Grüße.txt')
    window.change_language('de')
    window.transfers.render()
    assert 'Zeit insgesamt (aktiv) 2 h 3 min 5 s' in card.details.text()
    assert not window.transfers.timer.isActive()
    calls = []
    original = card.details.setText
    monkeypatch.setattr(card.details, 'setText', lambda text: (calls.append(text), original(text)))
    for _ in range(10):
        window.transfers.render()
    assert not calls
    window.change_language('en')
    window.transfers.render()
    assert 'Total active time 2 h 3 min 5 s' in card.details.text()
    assert calls
    window.engine.transfers.delete(job['id'])
    card.state = 'cancelled'
    window.transfers.clear_completed()


def test_hidden_history_defers_widget_rebuild(window, app):
    window.history_dock.hide()
    source = window.panes[0].directory / 'Grüße.txt'
    window.engine.transfer([source], window.panes[1].directory)
    window.reload_history()
    assert window.history_dirty
    assert window.history_list.count() == 0
    window.history_dock.show()
    app.processEvents()
    assert not window.history_dirty
    assert window.history_list.count() == 1
    assert window.history_list.itemWidget(window.history_list.item(0)) is not None


def test_independent_removal_runs_during_copy_and_preserves_worker_state(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    from opencommander.cloud_listing import CloudListings
    source, target = window.panes
    file = source.directory / 'Grüße.txt'
    removed = source.directory / 'remove.txt'
    removed.write_text('recover this independently')
    entered, release = threading.Event(), threading.Event()
    original = FileEngine.copy_file
    def copying(engine, src, dst):
        if src == file:
            entered.set()
            assert release.wait(5)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', copying)
    window.cloud_listings = CloudListings()
    window.transfer(paths=[file], directory=target.directory)
    wait(app, entered.is_set)
    try:
        window.run_trash([removed])
        wait(app, lambda: not window.transfers.generic_running)
        assert not removed.exists()
        assert window.busy and window.transfers.active
        assert not window.engine.cancel.is_set()
        assert window.cloud_listings.revision > 0
        record = next(op for op in window.engine.history if op['label'] == 'trash')
        assert Path(record['records'][0]['destination']).read_text() == 'recover this independently'
    finally:
        release.set()
    wait(app, lambda: not window.busy)
    assert (target.directory / file.name).read_bytes() == file.read_bytes()
    window.undo(record['id'])
    wait(app, lambda: not window.busy)
    assert removed.read_text() == 'recover this independently'


def test_removing_copy_source_waits_until_copy_completes(window, app, monkeypatch):
    import threading
    from opencommander.operations import FileEngine
    source, target = window.panes
    file = source.directory / 'Grüße.txt'
    entered, release = threading.Event(), threading.Event()
    original = FileEngine.copy_file
    def copying(engine, src, dst):
        entered.set()
        assert release.wait(5)
        return original(engine, src, dst)
    monkeypatch.setattr(FileEngine, 'copy_file', copying)
    window.transfer(paths=[file], directory=target.directory)
    wait(app, entered.is_set)
    try:
        window.run_trash([file])
        assert len(window.operation_queue) == 1
        assert 'Wartet' in window.status.text()
        assert 'wartend' in window.transfers.toggle.text()
        assert file.exists()
    finally:
        release.set()
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert not file.exists()
    assert (target.directory / file.name).read_text() == 'Hello from OpenCommander'


def test_paused_transfer_source_is_protected_from_removal(window, app):
    source, target = window.panes
    file = source.directory / 'Grüße.txt'
    job = window.engine.transfers.create([file], target.directory, 'keep')
    card = window.transfers.add(job)
    card.state = 'paused'
    window.run_trash([file])
    app.processEvents()
    assert file.exists() and len(window.operation_queue) == 1
    assert not window.transfers.generic_running
    window.transfers_paused = True
    window.transfers.cancel_one(job['id'])
    wait(app, lambda: not window.busy and not window.operation_queue)
    assert not file.exists()
    assert window.transfers_paused  # Cancelling the conflicting job releases removal, not the copy pause.
    window.transfers.clear_completed()


def test_large_history_creates_only_visible_cards_and_releases_old_cards(window, app):
    original = window.engine.history[:]
    window.engine.history[:] = [dict(id=f'fixture-{i}', label='copy', time=1700000000+i,
                                    records=[], inputs=[]) for i in range(1000)]
    try:
        window.reload_history()
        window.history_dock.show()
        wait(app, lambda: bool(window.history_cards))
        assert window.history_list.count() == 1000
        assert len(window.history_cards) <= 6
        item = window.history_list.item(900)
        window.history_list.scrollToItem(item)
        window.load_history_previews()
        wait(app, lambda: 900 in window.history_cards)
        assert len(window.history_cards) <= 6
        assert 0 not in window.history_cards
        from opencommander.history_ui import HistoryCard
        app.sendPostedEvents(None, QEvent.DeferredDelete)
        assert len(window.history_list.findChildren(HistoryCard)) <= 6
    finally:
        window.engine.history[:] = original
        window.reload_history()


def test_failed_online_disconnect_releases_scheduler_in_gui_thread(window, app, monkeypatch):
    from types import SimpleNamespace
    from PySide6.QtCore import QThread
    from opencommander import online_ui
    profile = dict(id='oc_disconnect_fixture', kind='dropbox', name='Fixture')
    window.online_profiles = [profile]
    dialog = online_ui.OnlineDialog(window)
    monkeypatch.setattr(online_ui, 'remote_location', lambda _: True)
    monkeypatch.setattr(online_ui.shutil, 'which', lambda _: '/fixture/fusermount3')
    observed = []
    def unmount(*args, **kwargs):
        observed.append((QThread.currentThread(), window.busy))
        return SimpleNamespace(returncode=1)
    monkeypatch.setattr(online_ui.subprocess, 'run', unmount)
    dialog.disconnect_saved()
    wait(app, lambda: not dialog.pending)
    assert observed[0][0] != app.thread() and observed[0][1]
    assert not window.busy
    assert 'nicht getrennt' in dialog.status.text()
    dialog.close()


def test_media_removal_waits_for_its_own_operation(window, app, monkeypatch):
    import threading
    from PySide6.QtGui import QImage, QColor
    from PySide6.QtWidgets import QMessageBox
    from opencommander.media import MediaViewer
    from opencommander.filesystem import Entry
    from opencommander.operations import FileEngine
    directory = window.panes[0].directory
    entries = []
    for name in ['first.jpg', 'second.jpg']:
        path = directory / name
        image = QImage(20, 20, QImage.Format_RGB32)
        image.fill(QColor('blue'))
        assert image.save(str(path))
        entries.append(Entry(name, path, False, path.stat().st_size))
    viewer = MediaViewer(window, entries, 0)
    viewer.show()
    entered, release = threading.Event(), threading.Event()
    original = FileEngine.trash
    def removing(engine, paths):
        entered.set()
        assert release.wait(5)
        return original(engine, paths)
    monkeypatch.setattr(FileEngine, 'trash', removing)
    monkeypatch.setattr(QMessageBox, 'question', lambda *args: QMessageBox.Yes)
    viewer.trash_current()
    wait(app, entered.is_set)
    try:
        window.operation_finished.emit(None)  # Completion of an unrelated copy.
        app.processEvents()
        assert viewer.deleting and len(viewer.entries) == 2
        assert entries[0].path.exists()
    finally:
        release.set()
    wait(app, lambda: not viewer.deleting)
    assert len(viewer.entries) == 1 and viewer.entries[0].name == 'second.jpg'
    assert not entries[0].path.exists()
    viewer.close()


def test_cancel_queued_preview_removal_restores_viewer_controls(window, app, monkeypatch):
    from PySide6.QtGui import QImage, QColor
    from PySide6.QtWidgets import QMessageBox
    from opencommander.media import MediaViewer
    from opencommander.filesystem import Entry
    source, target = window.panes
    path = source.directory / 'queued.jpg'
    image = QImage(20, 20, QImage.Format_RGB32)
    image.fill(QColor('green'))
    assert image.save(str(path))
    job = window.engine.transfers.create([path], target.directory, 'keep')
    card = window.transfers.add(job)
    card.state = 'paused'
    viewer = MediaViewer(window, [Entry(path.name, path, False, path.stat().st_size)], 0)
    viewer.show()
    monkeypatch.setattr(QMessageBox, 'question', lambda *args: QMessageBox.Yes)
    viewer.trash_current()
    assert viewer.deleting and window.operation_queue
    window.cancel_operations()
    assert not viewer.deleting
    assert path.exists() and len(viewer.entries) == 1
    assert not window.operation_queue
    wait(app, lambda: not window.busy)
    viewer.close()


def test_place_drop_reorders_persists_and_does_not_open(window, app, monkeypatch):
    from PySide6.QtGui import QDragEnterEvent
    from PySide6.QtCore import QPoint, QSettings
    from opencommander.places_ui import PLACE_MIME, load_order
    buttons = window.place_buttons
    source, target = buttons[-1], buttons[0]
    clicked = QSignalSpy(source.clicked)
    mime = QMimeData()
    mime.setData(PLACE_MIME, source.place_key.encode())

    class Enter(QDragEnterEvent):
        def source(self):
            return source

    class Drop(QDropEvent):
        def source(self):
            return source

    enter = Enter(QPoint(1, 10), Qt.MoveAction, mime, Qt.LeftButton, Qt.NoModifier)
    target.dragEnterEvent(enter)
    assert enter.isAccepted() and target.drop_before is True
    drop = Drop(QPointF(1, 10), Qt.MoveAction, mime, Qt.LeftButton, Qt.NoModifier)
    target.dropEvent(drop)
    assert drop.isAccepted() and clicked.count() == 0
    assert window.place_buttons[0] is source
    saved = QSettings(str(window.state_dir / 'settings.ini'), QSettings.IniFormat)
    assert load_order(saved.value('place_order'))[0] == source.place_key
    # Device scans and language/theme rebuilds retain the new order.
    window.update_places()
    assert window.place_buttons[0].place_key == source.place_key
    assert clicked.count() == 0


def test_places_reject_file_transfer_drops(window):
    mime = QMimeData()
    mime.setUrls([QUrl.fromLocalFile(str(window.panes[0].directory / 'Grüße.txt'))])
    drop = QDropEvent(QPointF(1, 10), Qt.CopyAction, mime, Qt.LeftButton, Qt.NoModifier)
    before = [button.place_key for button in window.place_buttons]
    window.place_buttons[0].dropEvent(drop)
    assert not drop.isAccepted()
    assert before == [button.place_key for button in window.place_buttons]
    assert not window.busy


def test_online_place_icons_keep_names_and_unavailable_order(window, app, monkeypatch, tmp_path):
    from opencommander.online_ui import mount_path
    profiles = [dict(id='oc_' + str(index), name=name, kind=kind)
                for index, (name, kind) in enumerate([
                    ('OneDrive Nikki', 'onedrive'), ('Drive Reisen', 'drive'),
                    ('Dropbox Fotos', 'dropbox'), ('iCloud', 'iclouddrive')])]
    window.online_profiles = profiles
    window.external_cloud_profiles = [dict(id='external_fixture', name='Google extern', kind='drive',
                                           external=True, mount_root=str(tmp_path / 'external'))]
    window.update_places()
    for profile in profiles:
        button = next(b for b in window.place_buttons if b.text() == profile['name'])
        assert not button.icon().pixmap(24, 24).isNull()
    assert not next(b for b in window.place_buttons if b.text() == 'Google extern').icon().isNull()
    source = 'online:' + profiles[2]['id']
    window.reorder_place(source, 'trash', True)
    window.online_profiles = profiles[:2] + profiles[3:]
    window.update_places()
    window.reorder_place('trash', 'online:' + profiles[0]['id'], False)
    window.online_profiles = profiles
    window.update_places()
    assert window.place_buttons[0].place_key == source
    opened = []
    monkeypatch.setattr(window, 'open_online_profile', opened.append)
    next(b for b in window.place_buttons if b.place_key == source).click()
    assert opened == [profiles[2]]


def test_place_rebuild_waits_for_active_drag(window):
    before = list(window.place_buttons)
    window.place_drag_active = True
    window.update_places()
    assert window.places_update_pending and window.place_buttons == before
    window.place_drag_active = False
    window.update_places()
    assert window.place_buttons != before


def test_place_drag_release_never_activates_shortcut(window, app, monkeypatch):
    from PySide6.QtCore import QPoint
    from PySide6.QtGui import QMouseEvent
    from opencommander import places_ui
    source = window.place_buttons[0]
    clicked = QSignalSpy(source.clicked)
    captured = {}

    class Drag:
        def __init__(self, parent):
            assert parent is source
        def setMimeData(self, mime):
            captured['mime'] = mime
        def setPixmap(self, pixmap):
            assert not pixmap.isNull()
        def setHotSpot(self, point):
            pass
        def exec(self, action):
            assert action == Qt.MoveAction
            window.update_places()
            assert window.place_drag_active and window.places_update_pending

    monkeypatch.setattr(places_ui, 'QDrag', Drag)
    QTest.mousePress(source, Qt.LeftButton, pos=QPoint(2, 2))
    move = QMouseEvent(QEvent.MouseMove, QPointF(30, 2), QPointF(30, 2),
                       Qt.NoButton, Qt.LeftButton, Qt.NoModifier)
    source.mouseMoveEvent(move)
    QTest.mouseRelease(source, Qt.LeftButton, pos=QPoint(30, 2))
    assert clicked.count() == 0
    assert captured['mime'].hasFormat(places_ui.PLACE_MIME)
    assert not captured['mime'].hasUrls()
    assert not window.place_drag_active
    app.processEvents()


def test_resume_card_keeps_progress_during_preflight_and_retains_error(window, app, monkeypatch):
    import threading
    job = window.engine.transfers.create([window.panes[0].directory / 'Grüße.txt'],
                                        window.panes[1].directory, 'keep')
    job.update(status='blocked', error='Test: provider unavailable',
               progress=dict(phase='copying', name='Grüße.txt', bytes_done=1024,
                             bytes_total=2048, files_done=1, files_total=2))
    window.engine.transfers.save(job)
    card = window.transfers.add(job)
    entered, release = threading.Event(), threading.Event()
    def preflight(identifier, engine):
        entered.set()
        assert release.wait(10)
        engine.transfers.delete(identifier)
        return {}
    monkeypatch.setattr(window, 'run_copy_job', preflight)
    window.change_language('de')
    try:
        card.resume.click()
        wait(app, entered.is_set)
        window.transfers.render()
        assert card.progress.value() == 50
        assert 'Gespeicherten Stand prüfen' in card.details.text()
        assert 'Letzter Fehler vor Fortsetzung: Test: provider unavailable' in card.details.text()
        assert '0.0 B/s' in card.details.text() or '0 B/s' in card.details.text()
        card.pending_metrics[0] = dict(card.metrics, resume_files_total=1,
            resume_files_checked=0, resume_bytes_total=1024, resume_bytes_checked=512)
        window.transfers.render()
        assert 'Geprüft: 0 / 1 gespeicherte Dateien' in card.details.text()
    finally:
        release.set()
        wait(app, lambda: not window.busy)


def test_history_keeps_previous_transfer_failure_after_success():
    from opencommander.history_ui import describe
    operation = dict(records=[], transfer_errors=[dict(time=123, message='Test: offline')])
    assert 'Früherer Übertragungsfehler: Test: offline' in describe(operation)
    assert 'Earlier transfer error: Test: offline' in describe(operation, False)


def test_help_is_nonmodal_reused_and_links_to_offline_chapter(window, app, monkeypatch):
    from opencommander import help_ui
    opened = []
    monkeypatch.setattr(help_ui.QDesktopServices, 'openUrl', lambda url: opened.append(url) or True)
    window.help()
    dialog = window.help_dialog
    assert dialog.isVisible() and not dialog.isModal()
    window.help()
    assert window.help_dialog is dialog
    dialog.buttons['uebertragungen'].click()
    assert opened[-1].isLocalFile()
    assert opened[-1].fragment() == 'uebertragungen'
    assert Path(opened[-1].toLocalFile()).is_file()
    monkeypatch.setattr(help_ui, 'handbook_path', lambda: window.state_dir / 'missing.html')
    dialog.retranslate()
    assert not dialog.buttons['anfang'].isEnabled()
    assert 'fehlt' in dialog.notice.text() if window.language == 'de' else 'missing' in dialog.notice.text()
    assert 'F5 / F6' in dialog.shortcuts.toPlainText()
    dialog.close()


def test_handbook_path_in_portable_installation(tmp_path, monkeypatch):
    from opencommander import help_ui
    monkeypatch.setattr(help_ui.sys, 'frozen', True, raising=False)
    monkeypatch.setattr(help_ui.sys, 'executable', str(tmp_path / 'opencommander'))
    assert help_ui.handbook_path() == tmp_path / 'docs/handbuch/index.html'


def test_filter_has_clear_empty_state_and_escape_does_not_remove_files(window, app):
    pane = window.panes[0]
    window.change_language('de')
    pane.filter.setText('no-such-file')
    assert pane.proxy.rowCount() == 0
    assert pane.filter_hint.isVisible() and pane.clear_filter.isVisible()
    assert 'Keine Treffer' in pane.filter_hint.text()
    pane.filter.setFocus()
    QTest.keyClick(pane.filter, Qt.Key_Escape)
    assert pane.filter.text() == ''
    assert not pane.filter_hint.isVisible()
    assert pane.proxy.rowCount() == 1
    assert (pane.directory / 'Grüße.txt').exists()
    pane.filter.setText('Grüße')
    assert '1 von 1' in pane.filter_hint.text()
    pane.clear_filter.click()
    assert not pane.filter.text()
    assert 'Strg+F' in pane.filter.toolTip()


def test_transfer_details_copy_includes_saved_error_and_route(window):
    job = window.engine.transfers.create([window.panes[0].directory / 'Grüße.txt'],
                                        window.panes[1].directory, 'keep')
    job.update(status='paused', last_error='Test: Verbindung unterbrochen')
    window.engine.transfers.save(job)
    card = window.transfers.add(job)
    card.copy_details.click()
    text = QApplication.clipboard().text()
    assert job['id'] in text and job['sources'][0] in text
    assert job['directory'] in text and job['last_error'] in text
    assert 'OpenCommander Linux' in text
    card.minimize.click()
    assert card.copy_details.isHidden()
    window.engine.transfers.delete(job['id'])
    card.state = 'cancelled'
    window.transfers.clear_completed()


def test_location_settings_removal_guidance_and_theme_sync(window):
    from opencommander.location_settings import LocationSettingsDialog
    window.change_language('de')
    window.location_preferences = [dict(name='Custom', path=str(window.state_dir), enabled=True, custom=True)]
    dialog = LocationSettingsDialog(window, [('Builtin', window.panes[0].directory)])
    window.location_settings_dialog = dialog
    dialog.show()
    dialog.table.selectRow(1)
    assert not dialog.buttons[1].isEnabled()
    assert 'ausblenden' in dialog.buttons[1].toolTip()
    dialog.table.selectRow(0)
    assert dialog.buttons[1].isEnabled()
    before = window.dark
    window.toggle_theme()
    assert dialog.theme_checkbox.isChecked() == window.dark != before
    dialog.theme_checkbox.click()
    assert dialog.theme_checkbox.isChecked() == window.dark == before
    dialog.buttons[1].click()
    assert len(dialog.rows) == 1 and not dialog.rows[0]['custom']
    assert window.state_dir.exists()
    dialog.close()


def test_pause_request_is_immediate_and_explains_unsaved_wait(window):
    import threading
    from types import SimpleNamespace
    job = window.engine.transfers.create([window.panes[0].directory / 'Grüße.txt'],
                                        window.panes[1].directory, 'keep')
    card = window.transfers.add(job)
    card.engine = SimpleNamespace(pause=threading.Event(), cancel=threading.Event())
    card.state = 'running'
    card.started = time.monotonic()
    window.transfers.active[job['id']] = card
    try:
        window.transfers.pause_one(job['id'])
        assert card.engine.pause.is_set() and card.engine.cancel.is_set()
        assert card.state == 'pausing' and not card.pause.isEnabled()
        card.pause_requested_at -= 65
        card._render_key = None
        assert 'Wartezeit' in card.render() and 'gesicherten Stand' in card.details.text()
        assert '1 min' in card.details.text()
        assert window.engine.transfers.get(job['id'])['status'] != 'paused'
    finally:
        window.transfers.active.pop(job['id'])
        window.engine.transfers.delete(job['id'])
        card.state = 'cancelled'
        window.transfers.clear_completed()


def test_expanded_transfer_has_one_summary_and_visible_controls(window, app):
    job = window.engine.transfers.create([window.panes[0].directory / 'Grüße.txt'],
                                        window.panes[1].directory, 'keep')
    job['sources'] = ['/cloud/' + 'very-long-folder-name-' * 35 + '/Weltreise']
    card = window.transfers.add(job)
    card.state = 'running'
    card.started = time.monotonic()
    card.metrics = dict(phase='copying', bytes_done=100, bytes_resumed=0,
                        bytes_total=200, files_done=1, files_total=2, name='photo.jpg')
    window.transfers.active[job['id']] = card
    try:
        window.resize(980, 800)
        window.transfers.toggle.setChecked(True)
        window.transfers.render()
        for _ in range(5):
            app.processEvents()
        assert not window.transfer_details.isVisible()
        assert not window.progress.isVisible()
        assert card.width() <= window.transfers.scroll.viewport().width()
        for control in (card.pause, card.cancel, card.minimize):
            assert control.isVisible()
            assert control.geometry().right() < card.width()
        assert 'Zeit insgesamt (aktiv)' in card.details.text()
        window.transfers.toggle.setChecked(False)
        assert window.transfer_details.isVisible()
        assert window.progress.isVisible()
        assert '50%' in window.transfer_details.text()
    finally:
        window.transfers.active.pop(job['id'])
        window.engine.transfers.delete(job['id'])
        card.state = 'cancelled'
        window.transfers.clear_completed()


def test_terminal_cloud_auth_error_does_not_save_or_mount(window, app, monkeypatch):
    from opencommander import online_ui
    window.online_locations()
    dialog = window.online_dialog
    dialog.profile = {'id': 'oc_incomplete', 'kind': 'onedrive', 'name': 'Incomplete'}
    dialog.cloud_auth = True
    mounted = []
    monkeypatch.setattr(online_ui, 'mount_profile', lambda *args: mounted.append(args))
    before = list(window.online_profiles)
    dialog.question({'Error': 'provider internal error', 'State': ''})
    assert window.online_profiles == before
    assert not mounted
    assert 'nicht abgeschlossen' in dialog.status.text()
    assert 'provider internal error' not in dialog.status.text()
    dialog.close()


def test_icloud_password_field_does_not_reuse_plaintext_default(window, app, monkeypatch):
    from opencommander import online_ui, cloud_config
    import threading
    window.online_locations()
    dialog = window.online_dialog
    dialog.profile = {'id': 'oc_fixture', 'kind': 'iclouddrive', 'name': 'Fixture'}
    dialog.cloud_auth = True
    option = {'Name': 'password', 'IsPassword': True, 'DefaultStr': 'short'}
    dialog.question({'State': '*all-set,password', 'Option': option})
    assert not dialog.answer.currentText() and not dialog.password_default
    calls = []
    monkeypatch.setattr(dialog, 'work', lambda operation, done: operation())
    monkeypatch.setattr(online_ui, 'command_json', lambda *a, **kw: calls.append(kw))
    dialog.continue_auth('new value')
    assert calls[-1]['password_result'] is True
    encoded = cloud_config.obscure('test input', threading.Event())
    dialog.question({'State': '*all-set,password', 'Option': dict(option, DefaultStr=encoded)})
    assert not dialog.answer.currentText() and dialog.password_default == encoded
    dialog.continue_auth('')
    assert calls[-1]['password_result'] is False and calls[-1]['result'] == encoded
    dialog.state = ''
    dialog.close()


def test_incomplete_cloud_place_opens_repair_assistant(window, app, monkeypatch):
    from opencommander import online_ui, cloud_config
    profile = {'id': 'oc_incomplete', 'kind': 'onedrive', 'name': 'Incomplete'}
    window.online_profiles = [profile]
    def incomplete(*args):
        raise cloud_config.CloudSetupError('Sign-in incomplete')
    monkeypatch.setattr(online_ui, 'mount_profile', incomplete)
    window.online_locations()
    dialog = window.online_dialog
    repaired = []
    monkeypatch.setattr(dialog, 'reconnect_saved', lambda: repaired.append(dict(dialog.editing_profile)))
    window.open_online_profile(profile)
    wait(app, lambda: bool(repaired))
    assert repaired == [profile]
    assert not window.opening_online
    dialog.close()


def test_automatic_cloud_answer_does_not_inherit_previous_password_question(window, app, monkeypatch):
    from opencommander import online_ui
    window.online_locations()
    dialog = window.online_dialog
    dialog.profile = {'id': 'oc_fixture', 'kind': 'iclouddrive', 'name': 'Fixture'}
    dialog.cloud_auth = True
    dialog.answer_is_password = True
    dialog.password_default = 'previous question value'
    calls = []
    monkeypatch.setattr(dialog, 'work', lambda operation, done: operation())
    monkeypatch.setattr(online_ui, 'command_json', lambda *a, **kw: calls.append(kw))
    dialog.question({'State': '*all-set,service', 'Option': {'Name': 'service'}})
    assert calls[-1]['result'] == 'drive'
    assert calls[-1]['password_result'] is False
    dialog.state = ''
    dialog.close()
