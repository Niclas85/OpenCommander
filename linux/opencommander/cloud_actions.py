"""Provider actions for saved cloud mounts; never resolve remote paths on the GUI thread."""
import os
from pathlib import Path
import subprocess
import threading
import time
from urllib.parse import urlsplit
from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton, QProgressBar, QApplication
from .desktop import host_environment
from .online_ui import mount_path, private_config
from . import rclone_runtime

WEBSITES = {'drive': 'https://drive.google.com/drive/my-drive',
            'onedrive': 'https://onedrive.live.com/', 'dropbox': 'https://www.dropbox.com/home',
            'iclouddrive': 'https://www.icloud.com/iclouddrive/'}
LINK_PROVIDERS = {'drive', 'onedrive', 'dropbox'}


def cloud_target(main, entry):
    if entry.member or entry.link:
        return None
    path = Path(os.path.abspath(entry.path))
    for profile in main.online_profiles:
        if profile['kind'] not in WEBSITES:
            continue
        root = mount_path(main.state_dir, profile['id'])
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            continue
        return dict(profile), '' if relative == '.' else relative
    return None


def share_link(main, profile, relative, cancel, timeout=30):
    if profile['kind'] not in LINK_PROVIDERS:
        raise ValueError('Dieser Dienst unterstützt Linkfreigaben nur im Browser. / Share using the provider website.')
    # Keep the target within the saved remote, including when called outside the menu.
    if not relative or relative.startswith('/') or '..' in Path(relative).parts or '\x00' in relative:
        raise ValueError('Ungültiger Cloud-Pfad / Invalid cloud path')
    binary = rclone_runtime.binary()
    if not binary:
        raise RuntimeError('Cloud-Backend fehlt / Cloud backend unavailable')
    command = [binary, '--config', str(private_config(main.state_dir)), 'link',
               profile['id'] + ':' + relative, '--contimeout', '5s', '--timeout', '10s',
               '--retries', '1', '--low-level-retries', '1']
    if profile['kind'] == 'onedrive':
        command += ['--onedrive-link-type', 'view', '--onedrive-link-scope', 'anonymous']
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, env=host_environment()) as process:
        deadline = time.monotonic() + timeout
        try:
            while True:
                if cancel.is_set():
                    raise RuntimeError('Abgebrochen. Eine bereits erstellte Freigabe kann beim Dienst bestehen bleiben. / Cancelled; an already created share may remain.')
                if time.monotonic() >= deadline:
                    raise RuntimeError('Zeitüberschreitung. Freigaben gegebenenfalls beim Dienst prüfen. / Timed out; check sharing on the provider website.')
                try:
                    output, _ = process.communicate(timeout=.1)
                    break
                except subprocess.TimeoutExpired:
                    continue
            if process.returncode:
                raise RuntimeError('Link konnte nicht erstellt werden. Anmeldung und Freigaberechte beim Dienst prüfen. / Check sign-in and sharing permissions.')
            link = output.strip().splitlines()[-1] if output.strip() else ''
            parsed = urlsplit(link)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or any(ord(c) < 32 for c in link):
                raise RuntimeError('Der Dienst hat keinen gültigen HTTPS-Link geliefert. / No valid HTTPS link returned.')
            return link
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


class ShareDialog(QDialog):
    def __init__(self, main, profile, relative, entry):
        super().__init__(main)
        self.main, self.profile, self.relative = main, profile, relative
        self.cancel = threading.Event()
        self.closed = False
        self.setWindowTitle('Teilen mit Link' if main.language == 'de' else 'Share with link')
        self.resize(620, 240)
        de = main.language == 'de'
        layout = QVBoxLayout(self)
        title = QLabel(f'{profile.get("name", profile.get("label", "Cloud"))} · {entry.name}')
        title.setTextFormat(Qt.PlainText)
        layout.addWidget(title)
        self.message = QLabel('„Link erstellen“ erstellt oder verwendet eine Freigabe. Jeder mit dem Link kann lesen; bei Ordnern auch deren Inhalt. Kein automatisches Ablaufdatum. Rechte lassen sich auf der Website des Dienstes verwalten.' if de else
                             'Create link creates or retrieves a share. Anyone with the link can read the file or folder contents. No automatic expiry. Manage permissions on the provider website.')
        self.message.setWordWrap(True)
        self.message.setTextFormat(Qt.PlainText)
        layout.addWidget(self.message)
        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.hide()
        layout.addWidget(self.progress)
        self.url = QLineEdit()
        self.url.setReadOnly(True)
        self.url.setPlaceholderText('Freigabelink / Share link')
        layout.addWidget(self.url)
        row = QHBoxLayout()
        self.create = QPushButton('Link erstellen' if de else 'Create link')
        self.create.clicked.connect(self.start)
        row.addWidget(self.create)
        self.copy = QPushButton('Link kopieren' if de else 'Copy link')
        self.copy.setEnabled(False)
        self.copy.clicked.connect(lambda: QApplication.clipboard().setText(self.url.text()))
        row.addWidget(self.copy)
        self.open = QPushButton('Link öffnen' if de else 'Open link')
        self.open.setEnabled(False)
        self.open.clicked.connect(lambda: QDesktopServices.openUrl(QUrl(self.url.text())))
        row.addWidget(self.open)
        close = QPushButton('Schließen / Abbrechen' if de else 'Close / Cancel')
        close.clicked.connect(self.reject)
        row.addWidget(close)
        layout.addLayout(row)

    def start(self):
        from .ui import Task
        if self.closed or not self.create.isEnabled():
            return
        self.create.setEnabled(False)
        self.progress.show()
        self.message.setText('Freigabelink wird erstellt … / Creating share link …')
        task = Task(lambda: share_link(self.main, self.profile, self.relative, self.cancel))
        def done(link, error):
            if self.closed or self.main.closing:
                return
            self.progress.hide()
            self.create.setEnabled(bool(error))
            self.message.setText(str(error) if error else 'Freigabelink bereit. Jeder mit dem Link kann lesen. / Share link ready; anyone with the link can read.')
            if not error:
                self.url.setText(link)
                self.copy.setEnabled(True)
                self.open.setEnabled(True)
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.main.start_background(task)

    def done(self, result):
        self.closed = True
        self.cancel.set()
        super().done(result)


def add_cloud_actions(menu, pane):
    if pane.archive:
        return
    entries = pane.selected()
    targets = [cloud_target(pane.main, entry) for entry in entries]
    if not targets or not all(targets):
        return
    profile, relative = targets[0]
    if any(target[0]['id'] != profile['id'] for target in targets):
        return
    main = pane.main
    de = main.language == 'de'
    menu.addSeparator()
    submenu = menu.addMenu('Online · ' + profile.get('name', profile.get('label', 'Cloud')))
    share = submenu.addAction('Teilen mit Link …' if de else 'Share with link …')
    supported = profile['kind'] in LINK_PROVIDERS
    share.setEnabled(supported and len(entries) == 1 and bool(relative) and not main.closing)
    if not supported:
        share.setToolTip('Für diesen Dienst Freigaben im Browser verwalten. / Manage sharing on the provider website.')
    elif len(entries) != 1:
        share.setToolTip('Eine Datei oder einen Ordner auswählen. / Select one file or folder.')
    share.triggered.connect(lambda: ShareDialog(main, profile, relative, entries[0]).exec())
    copy = submenu.addAction('Online-Pfad kopieren' if de else 'Copy online path')
    copy.triggered.connect(lambda: QApplication.clipboard().setText('\n'.join('/' + target[1] for target in targets)))
    browser = submenu.addAction('Freigaben im Cloud-Browser verwalten …' if de else 'Manage sharing on provider website …')
    browser.triggered.connect(lambda: QDesktopServices.openUrl(QUrl(WEBSITES[profile['kind']])))
