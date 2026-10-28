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
import queue
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import Qt, Signal, Slot, QUrl, QTimer
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QComboBox, QPushButton, QProgressBar, QMessageBox, QWidget, QScrollArea, QLayout, QSizePolicy, QCheckBox)
from .desktop import host_environment
from .filesystem import remote_location
from . import rclone_runtime
from . import server_connections as server
from .server_ui import ServerForm
from .places_ui import provider_icon


PROVIDERS = [('OneDrive online', 'onedrive'), ('Google Drive online', 'drive'),
             ('Dropbox online', 'dropbox'), ('iCloud Drive online', 'iclouddrive'),
             ('FTP', 'ftp'), ('FTPS (TLS)', 'ftps'), ('SSH / SFTP', 'sftp')]


def automatic_auth_answer(kind, option):
    name = option.get('Name', '')
    if name == 'config_is_local':
        return 'true'  # Browser OAuth, never ask users to paste access tokens.
    if name == 'config_refresh_token':
        return 'true'  # Explicit reconnect must refresh the existing login.
    if kind == 'drive' and name == 'config_change_team_drive':
        return 'false'  # Keep personal Drive / existing shared-drive mapping.
    if kind == 'iclouddrive' and name == 'service':
        return 'drive'
    # Only harmless defaults are automatic. Credentials, 2FA, drive choice and
    # device approval remain explicit user decisions.
    if name in ('config_advanced', 'config_fs_advanced', 'client_id', 'client_secret', 'region', 'encoding',
                'root_folder_id', 'team_drive', 'chunk_size', 'upload_cutoff',
                'list_chunk', 'pacer_min_sleep', 'pacer_burst', 'use_trash'):
        return str(option.get('DefaultStr', ''))
    return None


def private_config(state):
    path = Path(state) / 'online' / 'rclone.conf'
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    if os.name == 'nt':
        from .windows_native import protect_private_directory
        protect_private_directory(path.parent)
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


def native_login(config, identifier, kind, client, cancel, browser_callback):
    from .native_oauth import authorize, PROVIDERS
    # Keep the previous login intact until the user has successfully authorized.
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(config)
    section = dict(parser[identifier]) if parser.has_section(identifier) else {'type': kind}
    if section.get('type') != kind:
        raise ValueError('Online-Profil gehört zu einem anderen Dienst / Provider mismatch')
    token = authorize(kind, client, cancel, browser_callback)
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    section.update(client_id=client['client_id'], client_secret='', oc_oauth_flow='pkce', token=json.dumps(token))
    if kind == 'onedrive':
        section.update(access_scopes=PROVIDERS[kind][2], disable_site_permission='true')
    server.write_config(config, identifier, section)


def oauth_browser_url(stderr):
    """Accept only rclone's loopback OAuth endpoint, never provider/log URLs."""
    if isinstance(stderr, bytes):
        stderr = stderr.decode('utf-8', errors='replace')
    match = re.search(r'http://127\.0\.0\.1:53682/auth\?state=[A-Za-z0-9_-]{22}(?=\s|$)', stderr or '')
    return match.group() if match else None


def command_json(config, arguments, cancel, result=None, timeout=180, browser_callback=None, password_result=False):
    executable = rclone_runtime.binary()
    if not executable:
        raise RuntimeError('Für Online-Orte bitte rclone und FUSE installieren / Install rclone and FUSE')
    env = host_environment()
    # rclone's *all-set wrapper writes answers verbatim, unlike the backend
    # authentication states. IsPassword answers need the stored wire format.
    if password_result and '--state' in arguments and arguments[arguments.index('--state') + 1].startswith('*all-set,'):
        from .cloud_config import obscure
        result = obscure(result, cancel)
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
        # Windows communicate(timeout) does not expose partial stderr. Drain both
        # pipes ourselves so the browser URL arrives while OAuth is still waiting.
        output_parts, error_parts, read_errors = [], [], []
        messages = queue.SimpleQueue()
        def read_output():
            try:
                output_parts.append(process.stdout.read())
            except Exception as error:
                read_errors.append(error)
        def read_errors_stream():
            try:
                for line in process.stderr:
                    error_parts.append(line)
                    messages.put(line)
            except Exception as error:
                read_errors.append(error)
        readers = [threading.Thread(target=read_output, daemon=True),
                   threading.Thread(target=read_errors_stream, daemon=True)]
        for reader in readers:
            reader.start()
        def deliver_browser():
            nonlocal browser_sent
            while not messages.empty():
                line = messages.get()
                if browser_callback is not None and not browser_sent:
                    url = oauth_browser_url(line)
                    if url:
                        browser_sent = True
                        browser_callback(url)
        deadline = time.monotonic() + timeout
        try:
            while True:
                deliver_browser()
                if cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                if time.monotonic() > deadline:
                    raise RuntimeError('Browser-Anmeldung abgelaufen. „Neue Anmeldung beginnen“ wählen und nur den neu geöffneten Browser-Tab verwenden. '
                                       'Die alte Rückleitungsadresse ist nicht mehr erreichbar. / Authentication timed out. Start a new sign-in and use the new browser tab.')
                try:
                    process.wait(timeout=0.1)
                    break
                except subprocess.TimeoutExpired:
                    continue
            for reader in readers:
                reader.join()
            if read_errors:
                raise read_errors[0]
            output, error_output = ''.join(output_parts), ''.join(error_parts)
            if process.returncode:
                # rclone errors can echo configuration/token fragments; never expose them.
                from .cloud_config import config_login_error
                raise RuntimeError(config_login_error(config, arguments[2] if len(arguments) >= 3 else '', error_output))
            value = json.loads(output)
            if not value.get('State') and not value.get('Error') and len(arguments) >= 3 and arguments[:2] in (['config', 'create'], ['config', 'update']):
                from .cloud_config import validate
                validate(config, arguments[2])
            return value
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            for reader in readers:
                reader.join()
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
    if os.name == 'nt':
        from .windows_native import invoke
        try:
            result = invoke('ssh-fingerprints', dict(host=host, port=int(port)))
        except subprocess.TimeoutExpired:
            raise RuntimeError(f'SSH {host}:{port}: Zeitüberschreitung bei der Serveridentität. '
                               'Server, Port und Firewall prüfen. / SSH identity discovery timed out. '
                               'Check server, port and firewall; password authentication has not started.') from None
        return result['fingerprints'], result['keys'].encode('utf-8')
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
    if profile['kind'] in ('drive', 'onedrive', 'dropbox', 'iclouddrive'):
        from .cloud_config import validate
        validate(config, profile['id'])
    settings = configparser.ConfigParser(interpolation=None)
    settings.read(config)
    section = settings[profile['id']]
    if profile['kind'] == 'ftps' and (section.get('explicit_tls') != 'true' or
                                     section.get('tls', 'false') == 'true' or
                                     section.get('no_check_certificate', 'false') == 'true'):
        raise RuntimeError('FTPS benötigt explizites TLS und gültige Zertifikate / FTPS requires verified TLS')
    if profile['kind'] == 'sftp' and section.get('known_hosts_file') != str(Path.home() / '.ssh/known_hosts'):
        raise RuntimeError('SSH benötigt geprüfte Hostschlüssel / SSH requires verified host keys')
    if os.name == 'nt':
        from .windows_mounts import mount_profile as windows_mount
        return windows_mount(main, profile, cancel)
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
                             # Avoid ten internal attempts keeping a FUSE read blocked
                             # for minutes after Pause. Recovery remains checkpointed.
                             '--low-level-retries', '2', '--retries', '1',
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
        self.auth_option_name = ''
        self.icloud_sms_requested_at = None
        self.connected_profile_id = None
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
            self.provider.addItem(provider_icon(kind), label, kind)
        layout.addWidget(self.provider)
        self.provider.currentIndexChanged.connect(self.provider_changed)
        self.icloud_web_button = QPushButton('iCloud.com ansehen (keine App-Verbindung)' if self.de else 'View iCloud.com (does not connect the app)')
        self.icloud_web_button.setFlat(True)
        self.icloud_web_button.setAutoDefault(False)
        self.icloud_web_button.clicked.connect(self.open_icloud_web)
        layout.addWidget(self.icloud_web_button)
        self.icloud_web_hint = QLabel('Webansicht: Hier erfolgt die Anmeldung auf iCloud.com. '
            'Eine Dateiverbindung in OpenCommander wird dadurch nicht eingerichtet; '
            'dafür unten „Mit Apple-ID verbinden“ verwenden.' if self.de else
            'Web view: sign in on iCloud.com. This does not configure an OpenCommander file connection; '
            'use “Connect with Apple ID” below for that.')
        self.icloud_web_hint.setWordWrap(True)
        self.icloud_web_hint.setTextFormat(Qt.PlainText)
        layout.addWidget(self.icloud_web_hint)
        self.google_custom = QCheckBox('Eigene Google-Anwendung verwenden (optional)' if self.de else 'Use your own Google application (optional)')
        layout.addWidget(self.google_custom)
        self.google_custom.toggled.connect(self.google_mode_changed)
        self.google_client_id = QLineEdit()
        self.google_client_id.setPlaceholderText('Eigene Google OAuth-Client-ID / Own Google OAuth client ID')
        layout.addWidget(self.google_client_id)
        self.google_client_secret = QLineEdit()
        self.google_client_secret.setEchoMode(QLineEdit.Password)
        self.google_client_secret.setPlaceholderText('Google OAuth Client-Secret (nur privates Profil / private profile only)')
        layout.addWidget(self.google_client_secret)
        self.google_guide = QPushButton('Eigene Google-Anmeldung einrichten: Anleitung' if self.de else 'Set up your own Google sign-in: guide')
        self.google_guide.clicked.connect(self.open_oauth_guide)
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
        if os.name == 'nt':
            self.note.setText(self.note.text().replace('rclone/FUSE', 'rclone/WinFsp')
                              .replace('Linux-Schlüsselbund', 'Windows-Anmeldeinformationen')
                              .replace('Linux keyring', 'Windows Credential Manager'))
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
        layout = outer  # Keep login/progress/cancel reachable while reading long instructions.
        self.auth_field_label = QLabel()
        self.auth_field_label.setTextFormat(Qt.PlainText)
        self.auth_field_label.hide()
        layout.addWidget(self.auth_field_label)
        layout.addWidget(self.answer)
        self.icloud_sms_button = QPushButton()
        self.icloud_sms_button.setAutoDefault(False)
        self.icloud_sms_button.clicked.connect(self.request_icloud_sms)
        self.icloud_sms_button.hide()
        layout.addWidget(self.icloud_sms_button)
        self.icloud_sms_timer = QTimer(self)
        self.icloud_sms_timer.setInterval(1000)
        self.icloud_sms_timer.timeout.connect(self.update_icloud_sms_button)
        self.next_button = QPushButton('Ort einrichten' if self.de else 'Configure location')
        self.next_button.setDefault(True)
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
                self.auth_option_name = ''
                self.icloud_sms_requested_at = None
                self.update_icloud_sms_button()
                self.auth_field_label.hide()
                self.provider.setEnabled(True)
                self.profile = None
                self.connected_profile_id = None
                self.editing_profile = None
                self.server_form.identifier = None
                self.server_form.existing_secret = False
                self.server_form.secret.clear()
                self.server_form.secret.setPlaceholderText('')
                self.answer.clear()
                self.answer.hide()
                self.status.clear()
                self.provider_changed()
        restart.clicked.connect(reset)
        layout.addWidget(restart)
        self.provider_changed()

    def reload(self, select_id=None):
        current = self.saved.currentData()
        selected = select_id or (current or {}).get('id')
        self.saved.clear()
        for profile in self.main.online_profiles:
            self.saved.addItem(provider_icon(profile.get('kind')), profile['name'], profile)
            if profile['id'] == selected:
                self.saved.setCurrentIndex(self.saved.count() - 1)

    def work(self, callback, after, finished=None):
        if self.pending:
            return
        from .ui import Task
        self.pending = True
        self.update_icloud_sms_button()
        self.cancel = threading.Event()
        self.browser_url = None
        self.browser_button.hide()
        self.progress.show()
        self.next_button.setEnabled(False)
        self.open_button.setEnabled(False)
        self.provider.setEnabled(False)
        self.server_form.setEnabled(False)
        self.answer.setEnabled(False)
        self.icloud_web_button.setEnabled(False)
        for field in (self.google_custom, self.google_client_id, self.google_client_secret, self.google_guide):
            field.setEnabled(False)
        self.status.setText('Bitte warten … / Please wait …')
        task = Task(callback)
        def done(value, error):
            if finished:
                finished()
            self.pending = False
            self.browser_url = None
            self.browser_button.hide()
            self.progress.hide()
            self.next_button.setEnabled(True)
            self.open_button.setEnabled(True)
            self.provider.setEnabled(True)
            self.server_form.setEnabled(True)
            self.answer.setEnabled(True)
            self.icloud_web_button.setEnabled(True)
            for field in (self.google_custom, self.google_client_id, self.google_client_secret, self.google_guide):
                field.setEnabled(True)
            self.status.setText(str(error) if error else '')
            expired = error and ('Authentication timed out' in str(error) or 'Sign-in timed out' in str(error))
            if error and self.profile and self.state and (self.profile['kind'] == 'iclouddrive' or expired):
                # Fatal backend sign-in failures cannot resume an advanced-option
                # state as though it were another password question.
                self.state = ''
                self.auth_option_name = ''
                self.auth_field_label.hide()
                self.answer.clear()
                self.answer.hide()
                self.provider_changed()
            self.update_icloud_sms_button()
            if not error:
                after(value)
        task.signals.result.connect(done, Qt.QueuedConnection)
        self.main.start_background(task)

    def next(self):
        if self.pending:
            return
        if not self.state and self.connected_profile_id:
            self.open_saved()
            return
        if self.state and self.profile and self.profile['kind'] == 'drive' and self.auth_option_name == 'config_shared_client_id':
            if self.answer.currentData() == 'false':
                # rclone asks for a client after No. Generic automatic defaults
                # would submit empty values and return to the same warning.
                self.state = ''
                self.auth_option_name = ''
                self.provider.setEnabled(True)
                self.answer.hide()
                self.google_custom.setChecked(True)
                self.provider_changed()
                self.status.setText('Google-Client-ID und Client-Secret eingeben. Die Anleitung oben erklärt die Einrichtung.' if self.de else
                                    'Enter your Google client ID and client secret. Use the guide above to set them up.')
                self.google_client_id.setFocus()
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
            if kind == 'drive' and self.google_custom.isChecked() and (not client_id or not client_secret):
                self.status.setText('Google-Client-ID und Client-Secret eingeben, bevor die Browser-Anmeldung startet.' if self.de else
                                    'Enter the Google client ID and client secret before starting browser sign-in.')
                return
            if kind == 'drive':
                from .public_oauth import select_client
                client_id, client_secret = select_client(client_id, client_secret)
            from .public_oauth import select_native
            try:
                if kind in ('onedrive', 'dropbox') and self.google_custom.isChecked() and not self.google_client_id.text().strip():
                    raise ValueError('Client-ID / App key eingeben / Enter the public application ID')
                native = select_native(kind, self.google_client_id.text().strip()) if kind in ('onedrive', 'dropbox') else None
            except ValueError as error:
                self.status.setText(str(error)); return
            self.native_authenticated = False
            self.google_client_secret.clear()
            def start():
                if self.cloud_auth:
                    rclone_runtime.ensure_cloud_backend(self.cancel)
                if native:
                    native_login(self.config, self.profile['id'], kind, native, self.cancel,
                                 lambda url: self.browser_requested.emit(self.cancel, url))
                    value = command_json(self.config, ['config', 'update', self.profile['id'], '--non-interactive'], self.cancel)
                    value['_oc_native_authenticated'] = True
                    return value
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
                self.server_form.secret.clear()
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
                          lambda path: (self.main.connection_opened(path, pane),
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

    def continue_auth(self, answer, *, state=None):
        if self.pending:
            return
        if self.profile['kind'] == 'iclouddrive':
            field = self.auth_option_name
            if field in ('apple_id', 'config_2fa', 'config_2fa_sms', 'config_2fa_phone'):
                answer = answer.strip()
            missing = not answer and not (field == 'password' and getattr(self, 'password_default', ''))
            if missing and field in ('apple_id', 'password', 'config_2fa', 'config_2fa_sms'):
                labels = {'apple_id': ('Apple-ID', 'Apple ID'), 'password': ('reguläres Apple-Passwort', 'regular Apple password'),
                          'config_2fa': ('Bestätigungscode oder sms', 'verification code or sms'),
                          'config_2fa_sms': ('SMS-Bestätigungscode', 'SMS verification code')}
                self.status.setText('Bitte ' + labels[field][0] + ' eingeben.' if self.de else 'Enter ' + labels[field][1] + '.')
                self.answer.setFocus()
                return
        arguments = ['config', 'update', self.profile['id'], '--continue', '--non-interactive', '--state', self.state if state is None else state]
        if self.profile['kind'] not in ('onedrive', 'drive', 'dropbox'):
            arguments += ['--all']
        password_result = getattr(self, 'answer_is_password', False)
        if password_result and not answer and getattr(self, 'password_default', ''):
            answer = self.password_default
            password_result = False  # Reuse the existing stored value verbatim.
        if self.answer.lineEdit():
            self.answer.lineEdit().clear()
        def authenticate():
            cancel = self.cancel
            return command_json(self.config, arguments, cancel, result=answer, timeout=600,
                                browser_callback=lambda url: self.browser_requested.emit(cancel, url),
                                password_result=password_result)
        self.work(authenticate, self.question)
        if self.profile['kind'] in ('drive', 'onedrive', 'dropbox') and answer == 'true':
            self.status.setText('Bitte im Browser anmelden. Das Fenster bleibt währenddessen geöffnet. / Sign in in your browser.')

    def update_icloud_sms_button(self):
        available = bool(self.profile and self.profile['kind'] == 'iclouddrive' and (
            self.auth_option_name == 'config_2fa' and self.state == '2fa_do' or
            self.auth_option_name == 'config_2fa_sms' and re.fullmatch(r'2fa_sms_\d+_(sms|voice)', self.state)))
        self.icloud_sms_button.setVisible(available)
        remaining = max(0, 30 - int(time.monotonic() - self.icloud_sms_requested_at)) if self.icloud_sms_requested_at is not None else 0
        caption = ('SMS-Code erneut senden' if self.de else 'Resend SMS code') if self.auth_option_name == 'config_2fa_sms' else ('SMS-Code anfordern' if self.de else 'Request SMS code')
        self.icloud_sms_button.setText(caption + (f' ({remaining} s)' if remaining else ''))
        self.icloud_sms_button.setEnabled(available and not self.pending and not remaining)
        if available and remaining:
            self.icloud_sms_timer.start()
        else:
            self.icloud_sms_timer.stop()

    def request_icloud_sms(self):
        self.update_icloud_sms_button()
        if not self.icloud_sms_button.isEnabled():
            return
        self.icloud_sms_requested_at = time.monotonic()
        # rclone 1.75.2 preserves _auth_session through both code questions.
        # Its 2fa_do + sms branch requests a code without a new SRP/password
        # login. Never send "sms" to 2fa_sms_* (that branch validates a code).
        self.continue_auth('sms', state='2fa_do')
        self.update_icloud_sms_button()

    @Slot(object, str)
    def browser_ready(self, cancel, url):
        if cancel is self.cancel and self.pending and not cancel.is_set():
            self.browser_url = url
            self.browser_button.show()
            self.open_browser()

    def open_browser(self):
        if not self.pending or self.cancel.is_set() or not self.browser_url:
            return
        self.open_browser_url(self.browser_url)

    def open_icloud_web(self):
        if self.pending or self.provider.currentData() != 'iclouddrive':
            return
        if self.open_browser_url('https://www.icloud.com/iclouddrive/'):
            self.status.setText('iCloud-Webansicht geöffnet. Die Dateiverbindung wird separat mit „Mit Apple-ID verbinden“ eingerichtet.' if self.de else
                                'iCloud web view opened. Configure the file connection separately with “Connect with Apple ID”.')

    def open_browser_url(self, url):
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
            opened = QDesktopServices.openUrl(QUrl(url))
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        if not opened:
            self.status.setText('Browser konnte nicht geöffnet werden. Bitte Standardbrowser prüfen und erneut versuchen.' if self.de else
                                'Could not open browser. Check your default browser and try again.')
        return opened

    def google_mode_changed(self, checked):
        if not checked:
            self.google_client_id.clear()
            self.google_client_secret.clear()
        self.provider_changed()

    def open_oauth_guide(self):
        urls = {'drive': 'https://rclone.org/drive/#making-your-own-client-id',
                'onedrive': 'https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration',
                'dropbox': 'https://developers.dropbox.com/oauth-guide'}
        if self.provider.currentData() in urls:
            QDesktopServices.openUrl(QUrl(urls[self.provider.currentData()]))

    def provider_changed(self, *args):
        if self.state or self.pending:
            return
        self.connected_profile_id = None
        kind = self.provider.currentData()
        self.icloud_web_button.setVisible(kind == 'iclouddrive')
        self.icloud_web_hint.setVisible(kind == 'iclouddrive')
        if getattr(self, '_client_provider', kind) != kind:
            self.google_client_id.clear()
            self.google_client_secret.clear()
            self.google_custom.blockSignals(True)
            self.google_custom.setChecked(False)
            self.google_custom.blockSignals(False)
        self._client_provider = kind
        from .public_oauth import bundled_client, native_client
        public_google = bundled_client() is not None if kind == 'drive' else native_client(kind) is not None
        oauth_kind = kind in ('drive', 'onedrive', 'dropbox')
        brand = {'drive': 'Google', 'onedrive': 'Microsoft', 'dropbox': 'Dropbox'}.get(kind, '')
        self.google_custom.setText(('Eigene Anwendung verwenden (optional)' if self.de else 'Use your own application (optional)'))
        self.google_custom.setVisible(oauth_kind)
        expert = oauth_kind and (self.google_custom.isChecked() or (kind == 'drive' and not public_google))
        self.google_client_id.setVisible(expert)
        self.google_client_secret.setVisible(expert and kind == 'drive')
        self.google_guide.setVisible(expert)
        self.google_client_id.setPlaceholderText(f'{brand} – Client-ID / App key')
        self.google_guide.setText(('Eigene Anmeldung einrichten: Anleitung' if self.de else 'Set up your own sign-in: guide'))
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
            if public_google:
                self.help.setText(self.help.text() + (f'\nDie {brand}-Anwendung von OpenCommander ist bereits eingerichtet. Du meldest dich mit deinem eigenen Konto an; Dateien und Zugriffsrechte bleiben bei deinem Konto.' if self.de else
                    f'\nOpenCommander’s {brand} application is configured. Sign in with your own account; your files and permissions belong to your account.'))
            elif kind == 'drive':
                self.help.setText(self.help.text() + ('\nGoogle: Für dauerhaften Zugriff eine eigene OAuth-Anwendung vom Typ Desktop-App einrichten (Anleitung oben). Die gemeinsam genutzte rclone-Anwendung hat geteilte Abfragelimits und wird 2026 eingestellt. Client-ID und Secret bleiben im privaten Profil; anschließend im Browser anmelden.' if self.de else
                    '\nGoogle: For continued access, create your own Desktop app OAuth client (guide above). The shared rclone app has shared rate limits and is being retired in 2026. Client ID and secret stay in the private profile; then sign in using your browser.'))
            elif self.google_custom.isChecked():
                self.help.setText(self.help.text() + ('\nNur die öffentliche Desktop-Client-ID / den App-Key eingeben. Die Anmeldung verwendet PKCE; kein Server-Secret erforderlich. Rückleitungsadresse: http://localhost:53682/.' if self.de else
                    '\nEnter only the public desktop client ID / app key. Sign-in uses PKCE without a server secret. Redirect URI: http://localhost:53682/.'))
            else:
                self.help.setText(self.help.text() + ('\nDieses Paket verwendet derzeit die gemeinsame rclone-Anwendung. Die eigene OpenCommander-Registrierung ist noch nicht eingebettet.' if self.de else
                    '\nThis package currently uses the shared rclone application. OpenCommander’s own registration has not yet been bundled.'))
        elif kind == 'iclouddrive':
            self.next_button.setText('Mit Apple-ID verbinden' if self.de else 'Connect with Apple ID')
            self.help.setText('1. Auf dem iPhone: Einstellungen → Apple Account → iCloud → „Auf iCloud-Daten im Internet zugreifen“ aktivieren.\n'
                              '2. Hier deine Apple-ID und dein reguläres Apple-Passwort eingeben. App-spezifische Passwörter funktionieren nicht.\n'
                              '3. Anmeldung auf deinem Apple-Gerät bestätigen und den Code hier eingeben. Alternativ „SMS-Code anfordern“ wählen. Ein SMS-Code kann erneut angefordert werden.\n'
                              '4. Verbindung abschließen; nach einem Neustart den gespeicherten Ort links öffnen.\n'
                              'iCloud verwendet diesen Assistenten statt einer Browseranmeldung. Apple kann nach Ablauf der Sitzung erneut einen Code verlangen. '
                              'Jeder Benutzer verbindet sein eigenes Konto; Zugangsdaten bleiben im privaten lokalen Profil.' if self.de else
                              '1. On iPhone: Settings → Apple Account → iCloud → enable “Access iCloud Data on the Web”.\n'
                              '2. Enter your Apple ID and regular Apple password here. App-specific passwords do not work.\n'
                              '3. Approve on your Apple device and enter its code here. Alternatively choose “Request SMS code”. You can request another SMS code.\n'
                              '4. Complete setup; after restarting, open the saved location on the left.\n'
                              'iCloud uses this assistant instead of browser sign-in. Apple may request another code after session expiry. '
                              'Each user connects their own account; credentials stay in the private local profile.')
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
        if value.get('_oc_native_authenticated'):
            self.native_authenticated = True
        if value.get('Error') and (not value.get('State') or not value.get('Option')):
            from .cloud_config import login_error
            self.status.setText(login_error('iclouddrive', value['Error']) if self.profile['kind'] == 'iclouddrive' else
                                'Anmeldung nicht abgeschlossen. „Neue Anmeldung beginnen“ wählen und den neuen Browser-Tab verwenden. / Start a new sign-in and use the new browser tab.')
            if self.profile['kind'] in ('drive', 'onedrive', 'dropbox', 'iclouddrive'):
                self.state = ''
                self.auth_option_name = ''
                self.auth_field_label.hide()
                self.answer.clear()
                self.answer.hide()
                self.update_icloud_sms_button()
                self.provider_changed()
            self.provider.setEnabled(not bool(self.state))
            return
        self.state = value.get('State', '')
        self.provider.setEnabled(not bool(self.state))
        if not self.state:
            self.auth_option_name = ''
            self.icloud_sms_requested_at = None
            self.update_icloud_sms_button()
            self.auth_field_label.hide()
            self.main.__dict__.pop('cloud_listings', None)
            self.main.online_profiles.append(self.profile)
            # Re-authentication updates the existing shortcut, never duplicates it.
            self.main.online_profiles = list({row['id']: row for row in self.main.online_profiles}.values())
            self.main.save_online_profiles()
            self.connected_profile_id = self.profile['id']
            self.reload(select_id=self.profile['id'])
            self.status.setText('Verbindung gespeichert. Beim nächsten Start den Ort links öffnen; keine neue Anmeldung nötig, solange die Sitzung gültig ist.' if self.de else
                                'Connection saved. Open this location on the left after restarting; no new sign-in is needed while the session is valid.')
            self.next_button.setText('Gespeicherten Ort öffnen' if self.de else 'Open saved location')
            self.help.clear()
            self.answer.clear()
            self.answer.hide()
            if self.cloud_auth:
                profile, pane = dict(self.profile), self.main.active
                def opened(path):
                    self.main.connection_opened(path, pane)
                    self.status.setText('Verbunden und gespeichert: ' + profile['name'] if self.de else 'Connected and saved: ' + profile['name'])
                self.work(lambda: mount_profile(self.main, profile, self.cancel), opened)
            return
        option = value.get('Option') or {}
        self.auth_option_name = option.get('Name', '')
        self.update_icloud_sms_button()
        # Each question owns its password semantics, including automatic answers.
        # A new login must not inherit the previous password question's flag.
        self.answer_is_password = bool(option.get('IsPassword'))
        self.password_default = ''
        auto = automatic_auth_answer(self.profile['kind'], option) if self.cloud_auth and not value.get('Error') else None
        if option.get('Name') == 'config_refresh_token' and getattr(self, 'native_authenticated', False) and not value.get('Error'):
            auto = 'false'  # The PKCE flow just obtained this token; do not authenticate twice.
        if self.profile['kind'] == 'onedrive' and option.get('Name') == 'config_type' and getattr(self, 'native_authenticated', False) and not value.get('Error'):
            auto = 'onedrive'  # Personal/business files; no broad SharePoint site search scope.
        if auto is not None:
            self.continue_auth(auto)
            return
        self.answer.show()
        labels = {'apple_id': ('Apple-ID', 'Apple ID'),
                  'password': ('Reguläres Apple-Passwort', 'Regular Apple password'),
                  'config_2fa': ('Apple-Bestätigungscode', 'Apple verification code'),
                  'config_2fa_sms': ('SMS-Bestätigungscode', 'SMS verification code'),
                  'config_2fa_phone': ('Telefonnummer für den SMS-Code', 'Phone number for SMS code')}
        label = labels.get(self.auth_option_name) if self.profile['kind'] == 'iclouddrive' else None
        self.auth_field_label.setVisible(label is not None)
        if label:
            self.auth_field_label.setText(label[0 if self.de else 1])
            self.answer.setAccessibleName(self.auth_field_label.text())
        self.help.setText(option.get('Help', option.get('Name', '')))
        if self.de and self.profile['kind'] == 'iclouddrive':
            prompts = {'apple_id': 'Apple-ID (E-Mail-Adresse)',
                       'config_2fa': 'Bestätige die Anmeldung auf deinem Apple-Gerät und gib den dort angezeigten Code ein. Kein Code erhalten? „SMS-Code anfordern“ wählen.',
                       'config_2fa_sms': 'Gib den zuletzt erhaltenen SMS-Code ein. Kein Code erhalten? Nach der kurzen Wartezeit „SMS-Code erneut senden“ wählen. Bei mehreren hinterlegten Telefonnummern wirst du erneut nach der Nummer gefragt.',
                       'config_2fa_phone': 'Wähle eine bei deinem Apple Account hinterlegte Telefonnummer. Apple sendet den Bestätigungscode dorthin.'}
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
        is_icloud_phone = self.profile['kind'] == 'iclouddrive' and self.auth_option_name == 'config_2fa_phone'
        self.answer.setEditable(not ((is_drive or is_icloud_phone) and examples))
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
        elif self.profile['kind'] == 'onedrive' and option.get('Name') == 'config_type':
            self.help.setText('Für normale Dateien „OneDrive Personal or Business“ wählen. SharePoint-Suche benötigt eine gesonderte Firmenfreigabe; bei gesperrter Firmenanmeldung den Administrator kontaktieren.' if self.de else
                              'Choose “OneDrive Personal or Business” for ordinary files. SharePoint search requires separate company permissions; contact your administrator if company sign-in is blocked.')
        default = str(option.get('DefaultStr', ''))
        self.answer_is_password = bool(option.get('IsPassword'))
        from .cloud_config import obscured
        self.password_default = default if self.answer_is_password and self.state.startswith('*all-set,') and obscured(default) else ''
        if self.answer_is_password:
            default = ''
        index = self.answer.findData(default)
        if index >= 0:
            self.answer.setCurrentIndex(index)
        else:
            self.answer.setEditText(default)
        secret = option.get('IsPassword') or any(key in option.get('Name', '').lower() for key in ('token', 'secret', 'pass', '2fa'))
        if self.answer.lineEdit():
            self.answer.lineEdit().setEchoMode(QLineEdit.Password if secret else QLineEdit.Normal)
            self.answer.lineEdit().setPlaceholderText(('Leer lassen: gespeichertes Passwort behalten' if self.de else 'Leave empty to keep the saved password') if self.password_default else '')
        if is_drive and examples:
            preferred = next((i for i, row in enumerate(examples) if row.get('Help', '').casefold().startswith('onedrive (')), None)
            if preferred is not None:
                self.answer.setCurrentIndex(preferred)
        self.next_button.setText(('Verbinden und öffnen' if self.de else 'Connect and open') if is_drive else ('Weiter' if self.de else 'Next'))
        if self.profile['kind'] == 'drive' and self.auth_option_name == 'config_shared_client_id':
            self.help.setText('Vor dem Öffnen des Browsers den Anmeldeweg wählen. Google stellt die gemeinsame rclone-Anwendung im Jahr 2026 ein. '
                              'Mit ihr lässt sich die Browser-Anmeldung noch versuchen; für dauerhaften Zugriff eine eigene Google-Anwendung einrichten.' if self.de else
                              'Choose a sign-in method before the browser opens. Google is retiring rclone’s shared application during 2026. '
                              'You can try browser sign-in with it, or set up your own Google application for continued access.')
            self.answer.clear()
            self.answer.setEditable(False)
            self.answer.addItem('Eigene Google-Anwendung einrichten' if self.de else 'Set up my own Google application', 'false')
            self.answer.addItem('Browser-Anmeldung mit gemeinsamer Anwendung versuchen' if self.de else 'Try browser sign-in with the shared application', 'true')
            self.next_button.setText('Ausgewählten Anmeldeweg starten' if self.de else 'Start selected sign-in method')
        if self.profile['kind'] == 'iclouddrive':
            buttons = {'apple_id': ('Weiter zum Passwort', 'Continue to password'),
                       'password': ('Anmeldung prüfen', 'Check sign-in'),
                       'config_2fa': ('Bestätigungscode senden', 'Submit verification code'),
                       'config_2fa_sms': ('SMS-Code bestätigen', 'Verify SMS code'),
                       'config_2fa_phone': ('SMS-Code senden', 'Send SMS code')}
            if self.auth_option_name in buttons:
                self.next_button.setText(buttons[self.auth_option_name][0 if self.de else 1])

    def edit_saved(self):
        profile = self.saved.currentData()
        if not profile or self.pending:
            return
        self.state = ''
        self.connected_profile_id = None
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
        self.connected_profile_id = None
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
        matching_provider = self.provider.currentData() == profile['kind']
        client_id = self.google_client_id.text().strip() if profile['kind'] == 'drive' and matching_provider else ''
        client_secret = self.google_client_secret.text() if profile['kind'] == 'drive' and matching_provider else ''
        if profile['kind'] == 'drive':
            from .public_oauth import select_client
            client_id, client_secret = select_client(client_id, client_secret, self.config, profile['id'])
        from .public_oauth import select_native
        try:
            native = select_native(profile['kind'], self.google_client_id.text().strip() if matching_provider else '', self.config, profile['id']) if profile['kind'] in ('onedrive', 'dropbox') else None
        except ValueError as error:
            self.status.setText(str(error)); return
        self.native_authenticated = False
        self.google_client_secret.clear()
        def start():
            if client_id or client_secret:
                save_drive_client(self.config, profile['id'], client_id, client_secret)
            if self.cloud_auth:
                rclone_runtime.ensure_cloud_backend(self.cancel)
            if native:
                native_login(self.config, profile['id'], profile['kind'], native, self.cancel,
                             lambda url: self.browser_requested.emit(self.cancel, url))
            value = command_json(self.config, arguments, self.cancel)
            if native:
                value['_oc_native_authenticated'] = True
            return value
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
            if os.name == 'nt':
                from .windows_mounts import unmount as windows_unmount
                return windows_unmount(root)
            binary = shutil.which('fusermount3') or shutil.which('fusermount')
            if not binary:
                raise RuntimeError('FUSE fehlt / FUSE unavailable')
            result = subprocess.run([binary, '-u', str(root)], capture_output=True,
                                    timeout=15, env=host_environment())
            if result.returncode:
                raise RuntimeError('Ort noch in Benutzung; nicht getrennt / Location still in use; not disconnected')
        # Busy belongs to the GUI scheduler; release it on the GUI thread on
        # both success and failure, after the worker's result is delivered.
        self.work(unmount, lambda _: (self.main.update_places(), self.status.setText('Getrennt / Disconnected')),
                  finished=lambda: setattr(self.main, 'busy', False))

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
