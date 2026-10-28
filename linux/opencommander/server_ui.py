"""Simple server form shared by new and saved connections."""
import configparser
from pathlib import Path
from PySide6.QtWidgets import (QWidget, QFormLayout, QHBoxLayout, QLineEdit,
                              QComboBox, QSpinBox, QCheckBox, QPushButton, QFileDialog)
from . import server_connections as server


class ServerForm(QWidget):
    def __init__(self, owner):
        super().__init__(owner)
        self.owner = owner
        self.identifier = None
        self.existing_secret = False
        self.loaded_mode = None
        self.profile_kind = None
        de = owner.de
        form = QFormLayout(self)
        form.setVerticalSpacing(8)
        self.host = QLineEdit()
        self.host.setPlaceholderText('nas.example.org')
        form.addRow('Server', self.host)
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        form.addRow('Port', self.port)
        self.user = QLineEdit()
        form.addRow('Benutzer' if de else 'User', self.user)
        self.mode = QComboBox()
        self.mode.addItem('Passwort' if de else 'Password', 'password')
        self.mode.addItem('Private SSH-Schlüsseldatei' if de else 'Private SSH key file', 'key')
        self.mode.addItem('SSH-Agent (bereits geladene Schlüssel)' if de else 'SSH agent (loaded keys)', 'agent')
        form.addRow('Anmeldung' if de else 'Authentication', self.mode)
        self.key_row = QWidget()
        row = QHBoxLayout(self.key_row)
        row.setContentsMargins(0, 0, 0, 0)
        self.key = QLineEdit()
        row.addWidget(self.key)
        browse = QPushButton('Auswählen …' if de else 'Browse …')
        browse.clicked.connect(self.browse)
        row.addWidget(browse)
        form.addRow('SSH-Key', self.key_row)
        self.secret = QLineEdit()
        self.secret.setEchoMode(QLineEdit.Password)
        self.secret_label = 'Passwort / Key-Passphrase' if de else 'Password / key passphrase'
        form.addRow(self.secret_label, self.secret)
        self.remember = QCheckBox('Passwort/Passphrase im Linux-Schlüsselbund speichern' if de else
                                 'Save password/passphrase in Linux keyring')
        from .platform_support import WINDOWS
        if WINDOWS:
            self.remember.setText('Passwort/Passphrase in Windows-Anmeldeinformationen speichern' if de else
                                  'Save password/passphrase in Windows Credential Manager')
        form.addRow(self.remember)
        self.directory = QLineEdit()
        self.directory.setPlaceholderText('Leer = Benutzerordner; z. B. /volume1/Daten' if de else
                                          'Empty = home directory; e.g. /data')
        form.addRow('Startordner' if de else 'Initial folder', self.directory)
        for field in (self.host, self.port, self.user, self.mode, self.key, self.secret, self.directory):
            field.setMinimumHeight(34)
        self.mode.currentIndexChanged.connect(self.authentication_changed)
        self.authentication_changed()

    def browse(self):
        path, _ = QFileDialog.getOpenFileName(self, 'Private SSH key', str(Path.home() / '.ssh'))
        if path:
            self.key.setText(path)

    def authentication_changed(self):
        mode = self.mode.currentData()
        self.key_row.setVisible(mode == 'key')
        self.layout().labelForField(self.key_row).setVisible(mode == 'key')
        self.secret.setEnabled(mode != 'agent')
        self.remember.setEnabled(mode != 'agent')
        if mode == 'agent':
            self.secret.clear()
            self.remember.setChecked(False)

    def protocol_changed(self, kind):
        if self.profile_kind is not None and self.profile_kind != kind:
            self.identifier = None
            self.existing_secret = False
            self.secret.clear()
            self.secret.setPlaceholderText('')
        self.profile_kind = kind
        self.mode.setEnabled(kind == 'sftp')
        if kind != 'sftp':
            self.mode.setCurrentIndex(0)
        self.port.setValue(22 if kind == 'sftp' else 21)

    def load(self, profile):
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(self.owner.config)
        section = parser[profile['id']]
        self.identifier = profile['id']
        self.host.setText(section.get('host', ''))
        self.port.setValue(section.getint('port', 22 if profile['kind'] == 'sftp' else 21))
        self.user.setText(section.get('user', ''))
        mode = profile.get('auth_mode', 'key' if section.get('key_file') else
                           'agent' if section.getboolean('key_use_agent', False) else 'password')
        self.mode.setCurrentIndex(self.mode.findData(mode))
        self.loaded_mode = mode
        self.key.setText(profile.get('key_path', section.get('key_file', '')))
        self.directory.setText(profile.get('remote_directory', ''))
        self.secret.clear()
        self.existing_secret = bool(profile.get('remember_secret'))
        self.secret.setPlaceholderText('Leer = gespeicherte Anmeldung verwenden' if self.existing_secret else '')
        self.remember.setChecked(self.existing_secret)

    def values(self, kind):
        return server.settings(kind, self.host.text(), self.port.value(), self.user.text(),
                               self.mode.currentData(), self.key.text(), self.directory.text())
