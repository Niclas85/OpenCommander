"""Private rclone configuration wizard and on-demand provider mounts.

No sync client is required. Settings never touch the user's global rclone config.
Secrets are passed in the child environment, not command-line arguments or logs.
"""
import json
import configparser
import os
import shutil
import subprocess
import threading
import weakref
import time
import uuid
import re
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import Qt, Signal, Slot, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QComboBox, QPushButton, QProgressBar, QMessageBox, QWidget, QScrollArea, QLayout, QSizePolicy)
from .desktop import host_environment
from .filesystem import remote_location
from . import rclone_runtime
from . import server_connections as server
from .server_ui import ServerForm


PROVIDERS = [('OneDrive online', 'onedrive'), ('Google Drive online', 'drive'),
             ('Dropbox online', 'dropbox'), ('iCloud Drive online', 'iclouddrive'),
             ('FTP', 'ftp'), ('FTPS (TLS)', 'ftps'), ('SSH / SFTP', 'sftp')]


def automatic_auth_answer(kind, option):
    name = option.get('Name', '')
    if name == 'config_is_local':
        return 'true'  # Browser OAuth, never ask users to paste access tokens.
    if name == 'config_refresh_token':
        return 'true'  # Explicit reconnect must refresh the existing login.
    if kind == 'iclouddrive' and name == 'service':
        return 'drive'
    # Only harmless defaults are automatic. Credentials, 2FA, drive choice and
    # device approval remain explicit user decisions.
    if name in ('config_advanced', 'client_id', 'client_secret', 'region', 'encoding',
                'root_folder_id', 'team_drive', 'chunk_size', 'upload_cutoff',
                'list_chunk', 'pacer_min_sleep', 'pacer_burst', 'use_trash'):
        return str(option.get('DefaultStr', ''))
    return None


def private_config(state):
    path = Path(state) / 'online' / 'rclone.conf'
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    descriptor = os.open(path, os.O_CREAT | os.O_WRONLY, 0o600)
    os.close(descriptor)
    os.chmod(path, 0o600)
    return path


def save_drive_client(config, identifier, client_id, client_secret):
    """Persist user-supplied OAuth details only in the private backend config."""
    if not re.fullmatch(r'[A-Za-z0-9._-]+\.apps\.googleusercontent\.com', client_id) or not client_secret or any(
            ord(c) < 32 for c in client_secret):
        raise ValueError('Google OAuth-Client-ID und Client-Secret gemeinsam eingeben. / Enter both Google OAuth client fields')
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(config)
    section = dict(parser[identifier]) if parser.has_section(identifier) else {'type': 'drive'}
    if section.get('type') != 'drive':
        raise ValueError('Kein Google-Drive-Profil / Not a Google Drive profile')
    if section.get('client_id') != client_id or section.get('client_secret') != client_secret:
        section.pop('token', None)  # Tokens belong to the OAuth client that issued them.
    section.update(client_id=client_id, client_secret=client_secret)
    server.write_config(config, identifier, section)


def oauth_browser_url(stderr):
    """Accept only rclone's loopback OAuth endpoint, never provider/log URLs."""
    if isinstance(stderr, bytes):
        stderr = stderr.decode('utf-8', errors='replace')
    match = re.search(r'http://127\.0\.0\.1:53682/auth\?state=[A-Za-z0-9_-]{22}(?=\s|$)', stderr or '')
    return match.group() if match else None


def command_json(config, arguments, cancel, result=None, timeout=180, browser_callback=None):
    executable = rclone_runtime.binary()
    if not executable:
        raise RuntimeError('Für Online-Orte bitte rclone und FUSE installieren / Install rclone and FUSE')
    env = host_environment()
    if result is not None:
        env['RCLONE_RESULT'] = result
    arguments = list(arguments)
    if '--state' in arguments:
        index = arguments.index('--state')
        env['RCLONE_STATE'] = arguments[index + 1]
        del arguments[index:index + 2]
    if browser_callback is not None and len(arguments) >= 3 and arguments[:2] == ['config', 'update']:
        env['RCLONE_CONFIG_' + arguments[2].upper() + '_CONFIG_AUTH_NO_BROWSER'] = 'true'
    browser_sent = False
    command = [executable, '--config', str(config), *arguments]
    with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, env=env) as process:
        deadline = time.monotonic() + timeout
        try:
            while True:
                if cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                if time.monotonic() > deadline:
                    raise RuntimeError('Online-Anmeldung: Zeitüberschreitung / Authentication timed out')
                try:
                    output, _ = process.communicate(timeout=0.1)
                    break
                except subprocess.TimeoutExpired as waiting:
                    if browser_callback is not None and not browser_sent:
                        url = oauth_browser_url(waiting.stderr)
                        if url:
                            browser_sent = True
                            browser_callback(url)
                    continue
            if process.returncode:
                # rclone errors can echo configuration/token fragments; never expose them.
                raise RuntimeError('Online-Konfiguration fehlgeschlagen. Provider, rclone-Version und Netzwerk prüfen. / Online configuration failed.')
            return json.loads(output)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            os.chmod(config, 0o600)


def mount_path(state, identifier):
    # Keep remote user data outside recovery metadata protected by FileEngine.
    state = Path(state)
    return state.parent / (state.name + '-online-mounts') / identifier


def list_cloud(main, profile, directory, cancel, timeout=30):
    """Read provider metadata directly; a stale FUSE daemon cannot stall listing."""
    from .filesystem import Entry
    from .external_cloud import root_for, config_for, remote_for
    root = root_for(main, profile)
    relative = Path(directory).relative_to(root).as_posix()
    remote = remote_for(profile, '' if relative == '.' else relative)
    binary = rclone_runtime.binary()
    if not binary:
        raise RuntimeError('Cloud-Backend fehlt. Online-Orte öffnen und erneut anmelden. / Cloud backend unavailable')
    command = [binary, '--config', str(config_for(main, profile)),
               'lsjson', remote, '--no-mimetype', '--contimeout', '5s', '--timeout', '10s',
               '--retries', '1', '--low-level-retries', '1']
    from .cloud_listing import CloudListings, CloudRows
    # One cache per window/profile session; no credentials or listings on disk.
    main.__dict__.setdefault('cloud_listings', CloudListings())
    key = (profile['kind'], str(config_for(main, profile)), remote, str(root))
    rows = main.cloud_listings.read(key, command, cancel, timeout)
    result = []
    for row in rows:
        name = row.get('Name')
        if not isinstance(name, str) or name in ('.', '..') or '/' in name or '\x00' in name:
            continue
        if not isinstance(row.get('IsDir'), bool) or not isinstance(row.get('Size', 0), (int, float)):
            continue
        try:
            modified = datetime.fromisoformat(row.get('ModTime', '').replace('Z', '+00:00')).timestamp()
        except (ValueError, OverflowError, AttributeError):
            modified = 0
        result.append(Entry(name, Path(directory) / name, row['IsDir'], max(0, row.get('Size', 0)), modified))
    return CloudRows(result, rows.warning)


def ssh_fingerprints(host, port):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.:-]*', host) or not 1 <= int(port) <= 65535:
        raise ValueError('Ungültiger SSH-Server / Invalid SSH host')
    result = subprocess.run(['ssh-keyscan', '-T', '5', '-p', str(port), host],
                             capture_output=True, timeout=20, env=host_environment())
    if not result.stdout:
        raise RuntimeError('Keine SSH-Schlüssel empfangen / No SSH host keys received')
    fingerprints = subprocess.run(['ssh-keygen', '-lf', '-', '-E', 'sha256'], input=result.stdout,
                                  capture_output=True, timeout=5, env=host_environment(), check=True)
    return fingerprints.stdout.decode(), result.stdout


def save_hostkeys(target, keys):
    lines = [line.split() for line in keys.decode().splitlines() if line and not line.startswith('#')]
    if not lines or any(len(line) != 3 for line in lines):
        raise ValueError('Ungültige SSH-Schlüssel / Invalid SSH keys')
    if target.exists():
        existing = subprocess.run(['ssh-keygen', '-F', lines[0][0], '-f', str(target)],
                                  capture_output=True, timeout=5, env=host_environment())
        if existing.returncode not in (0, 1):
            raise RuntimeError('known_hosts nicht lesbar / Could not read known_hosts')
        recorded = [row.split() for row in existing.stdout.decode().splitlines() if row and not row.startswith('#')]
        if recorded:
            known = {tuple(row[-2:]) for row in recorded}
            incoming = {tuple(row[-2:]) for row in lines}
            if any(kind == other_kind and key != other_key for kind, key in known for other_kind, other_key in incoming):
                raise RuntimeError('SSH-Hostschlüssel geändert; nicht gespeichert / SSH host key changed; not saved')
            return
    target.parent.mkdir(mode=0o700, exist_ok=True)
    with target.open('ab') as stream:
        stream.write(b'\n' + keys)
    os.chmod(target, 0o600)


_mount_locks = weakref.WeakValueDictionary()
_mount_locks_guard = threading.Lock()


def mount_profile(main, profile, cancel):
    # Parallel transfers and pane navigation can request the same mount.
    # Only one daemon may be launched; waiting remains independently cancellable.
    key = (str(main.state_dir), profile['id'])
    with _mount_locks_guard:
        lock = _mount_locks.get(key)
        if lock is None:
            lock = threading.Lock()
            _mount_locks[key] = lock
    while not lock.acquire(timeout=.1):
        if cancel.is_set():
            raise RuntimeError('Abgebrochen / Cancelled')
    try:
        if cancel.is_set():
            raise RuntimeError('Abgebrochen / Cancelled')
        return _mount_profile(main, profile, cancel)
    finally:
        lock.release()


def _mount_profile(main, profile, cancel):
    config = private_config(main.state_dir)
    settings = configparser.ConfigParser(interpolation=None)
    settings.read(config)
    section = settings[profile['id']]
    if profile['kind'] == 'ftps' and (section.get('explicit_tls') != 'true' or
                                     section.get('tls', 'false') == 'true' or
                                     section.get('no_check_certificate', 'false') == 'true'):
        raise RuntimeError('FTPS benötigt explizites TLS und gültige Zertifikate / FTPS requires verified TLS')
    if profile['kind'] == 'sftp' and section.get('known_hosts_file') != str(Path.home() / '.ssh/known_hosts'):
        raise RuntimeError('SSH benötigt geprüfte Hostschlüssel / SSH requires verified host keys')
    mount = mount_path(main.state_dir, profile['id'])
    if remote_location(mount):
        from .provider_mounts import register
        register(mount)
        return mount
    mount.mkdir(parents=True, mode=0o700, exist_ok=True)
    if not rclone_runtime.binary() or not (shutil.which('fusermount3') or shutil.which('fusermount')):
        raise RuntimeError('rclone und FUSE benötigt / rclone and FUSE required')
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    # Cache-off keeps upload completion tied to close(), avoiding false success from
    # queued write-back. Provider operations still have their own atomicity limits.
    env = server.credential_environment(main, profile)
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    result = subprocess.run([rclone_runtime.binary(), '--config', str(config), 'mount', profile['id'] + ':' + profile.get('remote_directory', ''), str(mount),
                             '--daemon', '--daemon-wait', '15s', '--vfs-cache-mode', 'off',
                             '--dir-cache-time', '5s', '--contimeout', '10s', '--timeout', '20s',
                             '--umask', '077'], capture_output=True, timeout=25, env=env)
    if result.returncode or not remote_location(mount):
        raise RuntimeError('Online-Ort nicht eingebunden. Anmeldung, FUSE oder SSH-Hostschlüssel prüfen. / Mount failed.')
    from .provider_mounts import register
    register(mount)
    return mount


class OnlineDialog(QDialog):
    browser_requested = Signal(object, str)

    def __init__(self, main):
        super().__init__(main)
        self.main = main
        self.de = main.language == 'de'
        self.pending = False
        self.cancel = threading.Event()
        self.profile = None
        self.state = ''
        self.cloud_auth = False
        self.browser_url = None
        self.browser_requested.connect(self.browser_ready)
        self.config = private_config(main.state_dir)
        self.setWindowTitle('Online-Orte' if self.de else 'Online locations')
        self.resize(760, 520)
        outer = QVBoxLayout(self)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        body = QWidget()
        body.setObjectName('onlineBody')
        layout = QVBoxLayout(body)
        layout.setSizeConstraint(QLayout.SetMinAndMaxSize)
        scroll.setWidget(body)
        outer.addWidget(scroll, 1)
        self.saved = QComboBox()
        self.reload()
        layout.addWidget(self.saved)
        row = QHBoxLayout()
        open_button = QPushButton('Im aktiven Bereich öffnen' if self.de else 'Open in active pane')
        open_button.clicked.connect(self.open_saved)
        row.addWidget(open_button)
        self.open_button = open_button
        login_button = QPushButton('Erneut anmelden' if self.de else 'Sign in again')
        login_button.clicked.connect(self.reconnect_saved)
        row.addWidget(login_button)
        edit_button = QPushButton('Bearbeiten' if self.de else 'Edit')
        edit_button.clicked.connect(self.edit_saved)
        row.addWidget(edit_button)
        disconnect_button = QPushButton('Trennen' if self.de else 'Disconnect')
        disconnect_button.clicked.connect(self.disconnect_saved)
        row.addWidget(disconnect_button)
        hide_button = QPushButton('Verknüpfung entfernen' if self.de else 'Remove shortcut')
        hide_button.clicked.connect(self.remove_saved)
        row.addWidget(hide_button)
        layout.addLayout(row)
        trust_button = QPushButton('SSH-Serverschlüssel prüfen …' if self.de else 'Check SSH host key …')
        trust_button.clicked.connect(self.check_hostkey)
        self.trust_button = trust_button
        layout.addWidget(trust_button)
        self.name = QLineEdit()
        self.name.setPlaceholderText('Anzeigename / Display name')
        layout.addWidget(self.name)
        save_name = QPushButton('Anzeigename speichern' if self.de else 'Save display name')
        save_name.clicked.connect(self.save_display_name)
        layout.addWidget(save_name)
        self.provider = QComboBox()
        for label, kind in PROVIDERS:
            self.provider.addItem(label, kind)
        layout.addWidget(self.provider)
        self.provider.currentIndexChanged.connect(self.provider_changed)
        self.google_client_id = QLineEdit()
        self.google_client_id.setPlaceholderText('Eigene Google OAuth-Client-ID / Own Google OAuth client ID')
        layout.addWidget(self.google_client_id)
        self.google_client_secret = QLineEdit()
        self.google_client_secret.setEchoMode(QLineEdit.Password)
        self.google_client_secret.setPlaceholderText('Google OAuth Client-Secret (nur privates Profil / private profile only)')
        layout.addWidget(self.google_client_secret)
        self.google_guide = QPushButton('Eigene Google-Anmeldung einrichten: Anleitung' if self.de else 'Set up your own Google sign-in: guide')
        self.google_guide.clicked.connect(lambda: QDesktopServices.openUrl(QUrl('https://rclone.org/drive/#making-your-own-client-id')))
        layout.addWidget(self.google_guide)
        self.server_form = ServerForm(self)
        layout.addWidget(self.server_form)
        self.note = QLabel('Direkter Online-Zugriff über rclone/FUSE, ohne Sync-App. Anmeldung öffnet gegebenenfalls den Browser.\n'
                           'Cloud-Zugangsdaten: nur für deinen Benutzer lesbares Profil, keine Schlüsselbund-Verschlüsselung.\n'
                           'Server-Passwörter: nur Sitzung oder optional Linux-Schlüsselbund; SSH-Keys bleiben in ihrer Datei.\n'
                           'SSH verwendet ~/.ssh/known_hosts; unbekannte/geänderte Hostschlüssel werden abgewiesen.' if self.de else
                           'Direct online access through rclone/FUSE without a sync app. Authentication may open a browser.\n'
                           'Cloud credentials: user-only OpenCommander profile; no keychain encryption.\n'
                           'Server passwords: session only or optional Linux keyring; SSH keys stay in their file.\n'
                           'SSH uses ~/.ssh/known_hosts and rejects unknown/changed host keys.')
        self.note.setWordWrap(True)
        layout.addWidget(self.note)
        safety = QLabel('Online-Aktionen prüfen vorhandene Ziele, sind aber keine atomaren Transaktionen mit anderen Clients. '
                        'Uploads werden ohne verzögerte Schreibwarteschlange ausgeführt. Entfernen nutzt Wiederherstellungskopien.' if self.de else
                        'Online actions check existing targets but are not atomic transactions with other clients. '
                        'Uploads use no deferred write-back queue. Removal uses recovery copies.')
        safety.setWordWrap(True)
        layout.addWidget(safety)
        self.help = QLabel()
        self.help.setWordWrap(True)
        self.help.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Minimum)
        self.help.setTextFormat(Qt.PlainText)
        layout.addWidget(self.help)
        self.answer = QComboBox()
        self.answer.setEditable(True)
        self.answer.hide()
        layout.addWidget(self.answer)
        layout = outer  # Keep login/progress/cancel reachable while reading long instructions.
        self.next_button = QPushButton('Ort einrichten' if self.de else 'Configure location')
        self.next_button.clicked.connect(self.next)
        layout.addWidget(self.next_button)
        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.hide()
        layout.addWidget(self.progress)
        self.status = QLabel()
        self.status.setWordWrap(True)
        self.status.setTextFormat(Qt.PlainText)
        layout.addWidget(self.status)
        self.browser_button = QPushButton('Anmeldebrowser nach vorne holen' if self.de else 'Show sign-in browser')
        self.browser_button.clicked.connect(self.open_browser)
        self.browser_button.hide()
        layout.addWidget(self.browser_button)
        cancel_button = QPushButton('Abbrechen / Cancel')
        cancel_button.setObjectName('cancelOnlineLogin')
        cancel_button.clicked.connect(lambda: self.cancel.set())
        layout.addWidget(cancel_button)
        restart = QPushButton('Neue Anmeldung beginnen' if self.de else 'Start a new sign-in')
        def reset():
            if not self.pending:
                self.state = ''
                self.profile = None
                self.editing_profile = None
                self.server_form.identifier = None
                self.server_form.existing_secret = False
                self.server_form.secret.clear()
                self.server_form.secret.setPlaceholderText('')
                self.answer.clear()
                self.provider_changed()
        restart.clicked.connect(reset)
        layout.addWidget(restart)
        self.provider_changed()

    def reload(self):
        self.saved.clear()
        for profile in self.main.online_profiles:
            self.saved.addItem(profile['name'], profile)

    def work(self, callback, after):
        if self.pending:
            return
        from .ui import Task
        self.pending = True
        self.cancel = threading.Event()
        self.browser_url = None
        self.browser_button.hide()
        self.progress.show()
        self.next_button.setEnabled(False)
        self.open_button.setEnabled(False)
        self.provider.setEnabled(False)
        self.server_form.setEnabled(False)
        self.status.setText('Bitte warten … / Please wait …')
        task = Task(callback)
        def done(value, error):
            self.pending = False
            self.browser_url = None
            self.browser_button.hide()
            self.progress.hide()
            self.next_button.setEnabled(True)
            self.open_button.setEnabled(True)
            self.provider.setEnabled(True)
            self.server_form.setEnabled(True)
            self.status.setText(str(error) if error else '')
            if not error:
                after(value)
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.main.start_background(task)

    def next(self):
        if self.pending:
            return
        editing = getattr(self, 'editing_profile', None)
        if not self.state and editing and editing['kind'] not in server.SERVER_KINDS and self.provider.currentData() == editing['kind']:
            self.reconnect_saved()
            return
        if not self.state:
            kind = self.provider.currentData()
            if kind in server.SERVER_KINDS:
                self.connect_server()
                return
            if kind == 'ftp' and QMessageBox.question(self, 'FTP', 'FTP überträgt Zugangsdaten unverschlüsselt. Fortfahren? / FTP is unencrypted. Continue?') != QMessageBox.Yes:
                return
            self.profile = dict(id='oc_' + uuid.uuid4().hex, name=self.name.text().strip() or self.provider.currentText(), kind=kind)
            self.cloud_auth = kind in ('onedrive', 'drive', 'dropbox', 'iclouddrive')
            arguments = ['config', 'create', self.profile['id'], 'ftp' if kind == 'ftps' else kind,
                         '--non-interactive']
            if kind not in ('onedrive', 'drive', 'dropbox'):
                arguments += ['--all']
            if kind == 'ftps':
                arguments += ['explicit_tls', 'true']
            if kind == 'sftp':
                arguments += ['known_hosts_file', str(Path.home() / '.ssh/known_hosts')]
            client_id = self.google_client_id.text().strip() if kind == 'drive' else ''
            client_secret = self.google_client_secret.text() if kind == 'drive' else ''
            self.google_client_secret.clear()
            def start():
                if self.cloud_auth:
                    rclone_runtime.ensure_cloud_backend(self.cancel)
                if kind == 'drive' and (client_id or client_secret):
                    save_drive_client(self.config, self.profile['id'], client_id, client_secret)
                    return command_json(self.config, ['config', 'update', self.profile['id'], '--non-interactive'], self.cancel)
                return command_json(self.config, arguments, self.cancel)
            self.work(start, self.question)
            if self.cloud_auth:
                self.status.setText('Anmeldung wird vorbereitet; aktuelles Backend wird bei Bedarf geladen … / Preparing sign-in …')
        else:
            answer = (str(self.answer.currentData()) if self.answer.currentData() is not None and
                      self.answer.currentText() == self.answer.itemText(self.answer.currentIndex()) else self.answer.currentText())
            self.continue_auth(answer)

    def connect_server(self):
        kind = self.provider.currentData()
        try:
            section, extra = self.server_form.values(kind)
        except (ValueError, OSError) as error:
            self.status.setText(str(error))
            return
        if kind == 'ftp' and QMessageBox.question(self, 'FTP',
                'FTP sendet Passwort und Dateien unverschlüsselt. Besser SFTP oder FTPS verwenden. Trotzdem verbinden? / FTP is unencrypted. Continue?',
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No) != QMessageBox.Yes:
            return
        profile = dict(id=self.server_form.identifier or 'oc_' + uuid.uuid4().hex,
                       name=self.name.text().strip() or section['user'] + '@' + section['host'], kind=kind, **extra)
        if remote_location(mount_path(self.main.state_dir, profile['id'])):
            self.status.setText('Vor Änderungen an der Anmeldung bitte Trennen wählen / Disconnect before editing login')
            return
        secret = self.server_form.secret.text()
        existing_secret = self.server_form.existing_secret
        if any(c in secret for c in '\r\n\x00'):
            self.status.setText('Passwort/Passphrase darf keinen Zeilenumbruch enthalten / Credentials cannot contain newlines')
            return
        remember = self.server_form.remember.isChecked() and extra['auth_mode'] != 'agent'
        use_existing = not secret and existing_secret and self.server_form.loaded_mode == extra['auth_mode']
        if extra['secret_required'] and not secret and not use_existing:
            self.status.setText('Passwort/Passphrase eingeben / Enter password or passphrase')
            return
        self.server_form.secret.clear()
        def save_and_open():
            def save():
                if self.cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                password = server.keyring(self.main.state_dir, profile['id'], 'lookup') if use_existing else secret
                if password is None and extra['auth_mode'] != 'agent':
                    raise RuntimeError('Passwort/Passphrase erneut eingeben / Enter credentials again')
                if remember:
                    server.keyring(self.main.state_dir, profile['id'], 'store', password)
                elif existing_secret:
                    server.keyring(self.main.state_dir, profile['id'], 'clear')
                if self.cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                server.write_config(self.config, profile['id'], section)
                profile['remember_secret'] = remember
                return password
            def saved(password):
                if not hasattr(self.main, 'server_secrets'):
                    self.main.server_secrets = {}
                self.main.server_secrets[profile['id']] = password
                self.main.online_profiles = [row for row in self.main.online_profiles if row['id'] != profile['id']] + [profile]
                self.main.save_online_profiles()
                self.reload()
                self.saved.setCurrentIndex(self.saved.findData(profile))
                self.server_form.identifier = profile['id']
                self.server_form.existing_secret = remember
                self.server_form.loaded_mode = profile['auth_mode']
                self.server_form.secret.setPlaceholderText('Leer = gespeicherte Anmeldung verwenden' if remember else '')
                pane = self.main.active
                self.work(lambda: mount_profile(self.main, profile, self.cancel),
                          lambda path: (pane.navigate(path), self.main.update_places(),
                                        self.status.setText('Verbunden: ' + profile['name'])))
            self.work(save, saved)
        if kind != 'sftp':
            save_and_open()
            return
        def check():
            fingerprints, keys = ssh_fingerprints(section['host'], section['port'])
            status = server.hostkey_status(Path.home() / '.ssh/known_hosts', keys)
            return status, fingerprints, keys
        def checked(value):
            status, fingerprints, keys = value
            if self.cancel.is_set():
                return
            if status == 'known':
                save_and_open()
                return
            message = (f"Server: {section['host']}:{section['port']}\n\n" + fingerprints +
                       '\nFingerabdruck unabhängig beim Serverbetreiber vergleichen. Nur bei Übereinstimmung vertrauen. / Verify with the server administrator. Trust this server?')
            if QMessageBox.question(self, 'SSH – Serveridentität', message,
                                   QMessageBox.Yes | QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
                self.work(lambda: save_hostkeys(Path.home() / '.ssh/known_hosts', keys), lambda _: save_and_open())
            else:
                self.status.setText('Verbindung abgebrochen; Server nicht vertraut / Server not trusted')
        self.work(check, checked)

    def continue_auth(self, answer):
        arguments = ['config', 'update', self.profile['id'], '--continue', '--non-interactive', '--state', self.state]
        if self.profile['kind'] not in ('onedrive', 'drive', 'dropbox'):
            arguments += ['--all']
        if self.answer.lineEdit():
            self.answer.lineEdit().clear()
        def authenticate():
            cancel = self.cancel
            return command_json(self.config, arguments, cancel, result=answer, timeout=600,
                                browser_callback=lambda url: self.browser_requested.emit(cancel, url))
        self.work(authenticate, self.question)
        if self.cloud_auth and answer == 'true':
            self.status.setText('Bitte im Browser anmelden. Das Fenster bleibt währenddessen geöffnet. / Sign in in your browser.')

    @Slot(object, str)
    def browser_ready(self, cancel, url):
        if cancel is self.cancel and self.pending and not cancel.is_set():
            self.browser_url = url
            self.browser_button.show()
            self.open_browser()

    def open_browser(self):
        if not self.pending or self.cancel.is_set() or not self.browser_url:
            return
        # Qt requests an XDG activation token from the focused Wayland window.
        # Restore host libraries for the desktop launcher in packaged builds.
        keys = ('LD_LIBRARY_PATH', 'QT_PLUGIN_PATH', 'QT_QPA_PLATFORM_PLUGIN_PATH')
        previous = {key: os.environ.get(key) for key in keys}
        env = host_environment()
        try:
            for key in keys:
                if key in env:
                    os.environ[key] = env[key]
                else:
                    os.environ.pop(key, None)
            opened = QDesktopServices.openUrl(QUrl(self.browser_url))
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        if not opened:
            self.status.setText('Browser konnte nicht geöffnet werden. Bitte Standardbrowser prüfen und erneut versuchen.' if self.de else
                                'Could not open browser. Check your default browser and try again.')

    def provider_changed(self, *args):
        if self.state or self.pending:
            return
        kind = self.provider.currentData()
        for field in (self.google_client_id, self.google_client_secret, self.google_guide):
            field.setVisible(kind == 'drive')
        self.trust_button.hide()
        self.server_form.setVisible(kind in server.SERVER_KINDS)
        self.server_form.protocol_changed(kind)
        if kind in ('onedrive', 'drive', 'dropbox'):
            brand = {'onedrive': 'Microsoft', 'drive': 'Google', 'dropbox': 'Dropbox'}[kind]
            self.next_button.setText(f'Mit {brand} im Browser anmelden' if self.de else f'Sign in with {brand} in browser')
            self.help.setText((f'1. Anzeigename eingeben und Anmeldung starten.\n2. Im Browser bei {brand} anmelden und Zugriff erlauben.\n'
                               '3. Falls gefragt, das gewünschte Laufwerk auswählen und bestätigen.\n'
                               'Die Verbindung wird gespeichert und automatisch geöffnet. Nach einem Neustart links auf den gespeicherten Namen klicken. '
                               'Direkter Online-Zugriff; Ordnerlisten kurz zwischengespeichert (5 Sekunden). Strg+R aktualisiert die Ansicht.') if self.de else
                              (f'1. Enter a display name and start sign-in.\n2. Sign in to {brand} in your browser and allow access.\n'
                               '3. Select and confirm your drive if asked.\n'
                               'The connection is saved and opened automatically. After restarting, click its saved name on the left. '
                               'Direct online access; directory lists cached briefly (5 seconds). Ctrl+R refreshes the view.'))
            if kind == 'drive':
                self.help.setText(self.help.text() + ('\nGoogle: Für dauerhaften Zugriff eine eigene OAuth-Anwendung vom Typ Desktop-App einrichten (Anleitung oben). Die gemeinsam genutzte rclone-Anwendung hat geteilte Abfragelimits und wird 2026 eingestellt. Client-ID und Secret bleiben im privaten Profil; anschließend im Browser anmelden.' if self.de else
                    '\nGoogle: For continued access, create your own Desktop app OAuth client (guide above). The shared rclone app has shared rate limits and is being retired in 2026. Client ID and secret stay in the private profile; then sign in using your browser.'))
        elif kind == 'iclouddrive':
            self.next_button.setText('Mit Apple-ID verbinden' if self.de else 'Connect with Apple ID')
            self.help.setText('Apple-ID, reguläres Apple-Passwort und Bestätigungscode werden benötigt. '
                              'Das Backend unterstützt keine reine Browser-OAuth-Anmeldung. '
                              'Bei Apple muss der Web-Zugriff auf iCloud-Daten erlaubt sein. Nach Abschluss wird die Verbindung gespeichert; '
                              'nach einem Neustart links auf den gespeicherten Namen klicken.' if self.de else
                              'Apple ID, regular Apple password and verification code are required. '
                              'The backend does not support browser-only OAuth. Enable iCloud web data access in your Apple settings. '
                              'The connection is saved; after restarting, click its saved name on the left.')
        else:
            self.next_button.setText('Verbinden und öffnen' if self.de else 'Connect and open')
            self.help.setText('Server, Benutzer und Anmeldung eingeben. SFTP ist verschlüsselt und unterstützt Passwort, SSH-Key und SSH-Agent. '
                              'Verschlüsselte OpenSSH-Keys werden für eine Stunde im bestehenden SSH-Agent entsperrt. '
                              'FTPS prüft TLS-Zertifikate; FTP ist unverschlüsselt. Reine SCP-Server ohne SFTP werden nicht unterstützt. '
                              'Die Verbindung bleibt gespeichert; ohne Schlüsselbund wird die Anmeldung nach Neustart erneut abgefragt.' if self.de else
                              'Enter server, user and credentials. SFTP supports password, private key or SSH agent. '
                              'Encrypted OpenSSH keys are unlocked in your existing SSH agent for one hour. '
                              'FTPS validates TLS certificates; FTP is unencrypted. SCP-only servers are unsupported. '
                              'Connections are saved; credentials are requested again after restarting unless saved in the keyring.')

    def question(self, value):
        self.state = value.get('State', '')
        if not self.state:
            self.main.__dict__.pop('cloud_listings', None)
            self.main.online_profiles.append(self.profile)
            # Re-authentication updates the existing shortcut, never duplicates it.
            self.main.online_profiles = list({row['id']: row for row in self.main.online_profiles}.values())
            self.main.save_online_profiles()
            self.reload()
            self.status.setText('Ort gespeichert. Oben öffnen. / Location saved. Open it above.')
            self.next_button.setText('Ort einrichten / Configure location')
            self.help.clear()
            self.answer.clear()
            self.answer.hide()
            if self.cloud_auth:
                profile, pane = dict(self.profile), self.main.active
                def opened(path):
                    pane.navigate(path)
                    self.main.update_places()
                    self.status.setText('Verbunden: ' + profile['name'] if self.de else 'Connected: ' + profile['name'])
                self.work(lambda: mount_profile(self.main, profile, self.cancel), opened)
            return
        option = value.get('Option') or {}
        auto = automatic_auth_answer(self.profile['kind'], option) if self.cloud_auth and not value.get('Error') else None
        if auto is not None:
            self.continue_auth(auto)
            return
        self.answer.show()
        self.help.setText(option.get('Help', option.get('Name', '')))
        if self.de and self.profile['kind'] == 'iclouddrive':
            prompts = {'apple_id': 'Apple-ID (E-Mail-Adresse)',
                       'config_2fa': 'Apple-Bestätigungscode vom vertrauenswürdigen Gerät eingeben. Für SMS: sms eingeben.'}
            if option.get('Name') in prompts:
                self.help.setText(prompts[option['Name']])
            if option.get('Name') == 'password':
                # UI help only; never a credential stored in source.
                self.help.setText('Reguläres Apple-ID-Passwort. App-spezifische Passwörter werden nicht unterstützt.')
        self.status.setText('Eingabe nicht akzeptiert / Input not accepted' if value.get('Error') else '')
        self.answer.clear()
        is_drive = self.profile['kind'] == 'onedrive' and option.get('Name') == 'config_driveid'
        examples = option.get('Examples', [])
        if is_drive:
            examples = sorted(examples, key=lambda row: not row.get('Help', '').casefold().startswith('onedrive ('))
        self.answer.setEditable(not is_drive or not examples)
        for example in examples:
            name = example.get('Help', '')
            label = (('OneDrive – persönliche Dateien' if self.de else 'OneDrive – personal files')
                     if is_drive and name.casefold() == 'onedrive (personal)' else name)
            self.answer.addItem((label or str(example['Value'])) if is_drive else str(example['Value']) + ' · ' + name,
                                str(example['Value']))
            if is_drive:
                self.answer.setItemData(self.answer.count() - 1, str(example['Value']), Qt.ToolTipRole)
        if is_drive:
            self.help.setText('Wähle „OneDrive – persönliche Dateien“ für deine normalen Dateien. Andere Einträge sind zusätzliche oder interne Bereiche. '
                              'Mit „Verbinden und öffnen“ wird die Verbindung gespeichert.' if self.de else
                              'Select “OneDrive – personal files” for your ordinary files. Other entries are additional or internal areas. '
                              '“Connect and open” saves the connection.')
        default = str(option.get('DefaultStr', ''))
        index = self.answer.findData(default)
        if index >= 0:
            self.answer.setCurrentIndex(index)
        else:
            self.answer.setEditText(default)
        secret = option.get('IsPassword') or any(key in option.get('Name', '').lower() for key in ('token', 'secret', 'pass', '2fa'))
        if self.answer.lineEdit():
            self.answer.lineEdit().setEchoMode(QLineEdit.Password if secret else QLineEdit.Normal)
        if is_drive and examples:
            preferred = next((i for i, row in enumerate(examples) if row.get('Help', '').casefold().startswith('onedrive (')), None)
            if preferred is not None:
                self.answer.setCurrentIndex(preferred)
        self.next_button.setText(('Verbinden und öffnen' if self.de else 'Connect and open') if is_drive else ('Weiter' if self.de else 'Next'))

    def edit_saved(self):
        profile = self.saved.currentData()
        if not profile or self.pending:
            return
        self.state = ''
        self.provider.setCurrentIndex(self.provider.findData(profile['kind']))
        self.provider_changed()
        self.name.setText(profile['name'])
        self.editing_profile = dict(profile)
        if profile['kind'] not in server.SERVER_KINDS:
            self.next_button.setText('Erneut anmelden' if self.de else 'Sign in again')
            self.help.setText('Gespeicherten Ort bearbeiten / Edit saved location')
        if profile['kind'] in server.SERVER_KINDS:
            self.server_form.load(profile)
        self.answer.hide()
        self.status.setText('Anzeigename speichern; für Zugangsdaten Erneut anmelden wählen. Server-Einstellungen vor dem Speichern trennen. / Save display name; sign in again to change credentials. Disconnect before saving server settings.')

    def save_display_name(self):
        profile = self.saved.currentData()
        name = self.name.text().strip()
        if not profile or self.pending or not name:
            return
        updated = dict(profile, name=name)
        self.main.online_profiles = [updated if row['id'] == profile['id'] else row for row in self.main.online_profiles]
        self.main.save_online_profiles()
        self.reload()
        index = next((i for i in range(self.saved.count()) if self.saved.itemData(i)['id'] == profile['id']), -1)
        self.saved.setCurrentIndex(index)
        self.status.setText('Anzeigename gespeichert / Display name saved')

    def open_saved(self):
        profile = self.saved.currentData()
        if profile and not self.pending:
            self.main.open_online_profile(profile)

    def reconnect_saved(self):
        profile = self.saved.currentData()
        if not profile or self.pending:
            return
        if remote_location(mount_path(self.main.state_dir, profile['id'])):
            self.status.setText('Vor erneuter Anmeldung bitte Trennen wählen. / Disconnect before signing in again.')
            return
        if profile['kind'] in server.SERVER_KINDS:
            self.state = ''
            self.provider.setCurrentIndex(self.provider.findData(profile['kind']))
            self.provider_changed()
            self.name.setText(profile['name'])
            self.server_form.load(profile)
            self.answer.hide()
            self.status.setText('Anmeldung bearbeiten und Verbinden wählen / Edit login and connect')
            return
        self.profile = dict(profile)
        self.cloud_auth = profile['kind'] in ('onedrive', 'drive', 'dropbox', 'iclouddrive')
        self.state = ''
        arguments = ['config', 'update', profile['id'], '--non-interactive']
        if profile['kind'] not in ('onedrive', 'drive', 'dropbox'):
            arguments += ['--all']
        client_id = self.google_client_id.text().strip() if profile['kind'] == 'drive' else ''
        client_secret = self.google_client_secret.text() if profile['kind'] == 'drive' else ''
        self.google_client_secret.clear()
        def start():
            if client_id or client_secret:
                save_drive_client(self.config, profile['id'], client_id, client_secret)
            if self.cloud_auth:
                rclone_runtime.ensure_cloud_backend(self.cancel)
            return command_json(self.config, arguments, self.cancel)
        self.work(start, self.question)

    def check_hostkey(self):
        if self.pending:
            return
        from PySide6.QtWidgets import QInputDialog
        host, accepted = QInputDialog.getText(self, 'SSH', 'Server / Host')
        if not accepted:
            return
        port, accepted = QInputDialog.getInt(self, 'SSH', 'Port', 22, 1, 65535)
        if accepted:
            self.work(lambda: ssh_fingerprints(host, port), self.confirm_hostkey)

    def confirm_hostkey(self, value):
        fingerprints, keys = value
        # Only explicit user confirmation after independent comparison records trust.
        message = ('Diese Fingerabdrücke unabhängig beim Serverbetreiber prüfen. Nur bei Übereinstimmung vertrauen.\n'
                   'Geänderte bestehende Schlüssel werden nicht ersetzt.\n\n' if self.de else
                   'Verify these fingerprints independently with the server administrator before trusting.\n'
                   'Changed existing host keys are not replaced.\n\n') + fingerprints
        if QMessageBox.question(self, 'SSH', message, QMessageBox.Yes | QMessageBox.No, QMessageBox.No) != QMessageBox.Yes:
            return
        self.work(lambda: save_hostkeys(Path.home() / '.ssh/known_hosts', keys),
                  lambda _: self.status.setText('SSH-Schlüssel geprüft / SSH host keys checked'))

    def remove_saved(self):
        profile = self.saved.currentData()
        if not profile or self.pending:
            return
        self.main.online_profiles = [row for row in self.main.online_profiles if row['id'] != profile['id']]
        self.main.save_online_profiles()
        self.reload()
        self.status.setText('Verknüpfung entfernt; Zugangsdaten und Serverdateien erhalten. / Shortcut removed; credentials and server files retained.')

    def disconnect_saved(self):
        profile = self.saved.currentData()
        if not profile or self.pending:
            return
        if self.main.busy:
            self.status.setText('Zuerst laufende Dateivorgänge pausieren oder abschließen. / Pause or finish file operations first.')
            return
        root = mount_path(self.main.state_dir, profile['id'])
        if not remote_location(root):
            return
        for pane in self.main.panes:
            if pane.directory == root or root in pane.directory.parents:
                pane.navigate(Path.home())
        self.main.busy = True
        def unmount():
            try:
                binary = shutil.which('fusermount3') or shutil.which('fusermount')
                if not binary:
                    raise RuntimeError('FUSE fehlt / FUSE unavailable')
                result = subprocess.run([binary, '-u', str(root)], capture_output=True,
                                        timeout=15, env=host_environment())
                if result.returncode:
                    raise RuntimeError('Ort noch in Benutzung; nicht getrennt / Location still in use; not disconnected')
            finally:
                # Clear even on failure; no forced unmount or interruption of writes.
                self.main.busy = False
        self.work(unmount, lambda _: (self.main.update_places(), self.status.setText('Getrennt / Disconnected')))

    def reject(self):
        if self.pending:
            self.cancel.set()
        else:
            super().reject()

    def closeEvent(self, event):
        if self.pending:
            self.cancel.set()
            event.ignore()
        else:
            super().closeEvent(event)
