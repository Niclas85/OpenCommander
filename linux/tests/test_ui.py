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
        def exec(self, actions):
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
    assert '00:' in details
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
