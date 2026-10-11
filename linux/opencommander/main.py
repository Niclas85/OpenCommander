import argparse
import os
from pathlib import Path
import sys
import tempfile

from PySide6.QtCore import QLockFile, QTimer
from PySide6.QtWidgets import QApplication
from .ui import MainWindow
from . import __version__
from .desktop import ask_default, folder_argument, socket_name, forward, listen


def main():
    parser = argparse.ArgumentParser(description='OpenCommander for Linux')
    parser.add_argument('folder', nargs='?', help='Folder path or file:// URL to open')
    parser.add_argument('--version', action='version', version='OpenCommander Linux ' + __version__)
    parser.add_argument('--left', type=Path)
    parser.add_argument('--right', type=Path)
    parser.add_argument('--state-dir', type=Path)
    parser.add_argument('--screenshot', type=Path)
    parser.add_argument('--smoke-test', action='store_true')
    args = parser.parse_args()
    if args.folder:
        try:
            args.left = folder_argument(args.folder)
        except ValueError as error:
            parser.error(str(error))
    fixture = tempfile.TemporaryDirectory(prefix='opencommander-smoke-') if args.smoke_test else None
    if fixture:
        root = Path(fixture.name)
        args.state_dir = args.state_dir or root / 'state'
        args.left = args.left or root / 'left'
        args.right = args.right or root / 'right'
        for directory in (args.left, args.right):
            directory.mkdir(parents=True, exist_ok=True)
    state = args.state_dir or Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'opencommander'
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.environ.get("WAYLAND_DISPLAY"):
        os.environ.setdefault("QT_QPA_PLATFORM", "wayland;xcb")
    app = QApplication(sys.argv[:1])
    app.setDesktopFileName("opencommander")
    app.setApplicationName('OpenCommander')
    app.setOrganizationName('OpenCommander')
    app.setStyle('Fusion')
    lock = QLockFile(str(state / 'session.lock'))
    if not lock.tryLock(0):
        if forward(socket_name(state), args.left):
            return 0
        print('OpenCommander is already using this profile. Please close the older version and restart.', file=sys.stderr)
        return 1
    window = MainWindow(state, args.left, args.right)
    server = listen(window, socket_name(state))
    window.show()
    if not args.smoke_test and not args.screenshot:
        QTimer.singleShot(500, lambda: ask_default(window))
    exit_status = [0]
    if args.smoke_test:
        import libarchive
        from .archives import open_archive
        from .operations import checked_members
        for kind, compression, suffix in (('ustar', 'gzip', '.tgz'), ('7zip', None, '.7z')):
            archive_path = Path(fixture.name) / ('archive-smoke' + suffix)
            with libarchive.file_writer(str(archive_path), kind, compression) as writer:
                writer.add_file_from_memory('hello.txt', 5, b'hello')
            with open_archive(archive_path) as archive:
                member = checked_members(archive)[0]
                with archive.open(member) as stream:
                    assert stream.read() == b'hello'
        from PySide6.QtGui import QImage, QColor
        from .filesystem import Entry
        sample = QImage(120, 80, QImage.Format_RGB32)
        sample.fill(QColor('#408acb'))
        sample_path = Path(fixture.name) / 'preview.JPG'
        sample.save(str(sample_path))
        entry = Entry(sample_path.name, sample_path, False, sample_path.stat().st_size)
        from PySide6.QtWidgets import QMenu
        from types import SimpleNamespace
        from .cloud_actions import add_cloud_actions
        window.external_cloud_profiles = [dict(id='external_smoke', kind='drive', name='Google Drive smoke',
            external=True, mount_root=str(sample_path.parent), remote_base='smoke:', config_path=str(sample_path.parent / 'unused.conf'))]
        cloud_menu = QMenu(window)
        add_cloud_actions(cloud_menu, SimpleNamespace(main=window, archive=None, selected=lambda: [entry]))
        assert cloud_menu.actions()[-1].menu().actions()[0].isEnabled()
        window.external_cloud_profiles = []
        window.open_entry(entry)
        from .media import online_image
        from .ui import Task
        from PySide6.QtCore import QSize
        import threading
        smoke_download = [False]
        task = Task(lambda: online_image(entry, QSize(96, 64), threading.Event()))
        task.signals.result.connect(lambda value, error: smoke_download.__setitem__(0, not error and not value.isNull()))
        window.start_background(task)
    if args.screenshot or args.smoke_test:
        def finish():
            if args.screenshot:
                args.screenshot.parent.mkdir(parents=True, exist_ok=True)
                if not window.grab().save(str(args.screenshot)):
                    exit_status[0] = 1
            if args.smoke_test:
                if window.preview_dialog.current_image.isNull() or not smoke_download[0]:
                    exit_status[0] = 1
                    print('FAIL: media preview did not load')
                else:
                    print('PASS: Linux desktop, JPEG viewer, isolated online-image download TAR/7z archive readers and external Drive context menu')
                window.close()
        QTimer.singleShot(2000, finish)
    result = app.exec()
    server.close()
    lock.unlock()
    if fixture:
        fixture.cleanup()
    return result or exit_status[0]


if __name__ == '__main__':
    raise SystemExit(main())
