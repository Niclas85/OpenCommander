"""Explicit, per-user shell integration; never changes system-wide registry keys."""
from pathlib import Path
import subprocess
import sys


def register():
    import winreg
    command = [sys.executable]
    if not getattr(sys, 'frozen', False):
        command.append(str(Path(__file__).resolve().parents[2] / 'windows/launcher.py'))
    # %1 must remain quoted even for paths with spaces and shell metacharacters.
    value = subprocess.list2cmdline(command) + ' "%1"'
    for kind in ('Directory', 'Drive'):
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, rf'Software\Classes\{kind}\shell\OpenCommander') as key:
            winreg.SetValueEx(key, '', 0, winreg.REG_SZ, 'OpenCommander')
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, rf'Software\Classes\{kind}\shell\OpenCommander\command') as key:
            winreg.SetValueEx(key, '', 0, winreg.REG_SZ, value)


def ask_default(window):
    from PySide6.QtWidgets import QMessageBox
    import winreg
    settings = window.settings
    if settings.value('windows_default_prompted', False, type=bool):
        return
    de = window.language == 'de'
    answer = QMessageBox.question(window, 'OpenCommander',
        'Ordner standardmäßig mit OpenCommander öffnen? Die Änderung gilt nur für dein Windows-Benutzerkonto. Rückgängig mit uninstall-local.ps1 im Anwendungspaket.' if de else
        'Open folders with OpenCommander by default? This applies only to your Windows account. Revert using uninstall-local.ps1 in the application package.',
        QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
    if answer == QMessageBox.Yes:
        try:
            register()
            with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r'Software\Classes\Directory\shell') as key:
                try:
                    previous = winreg.QueryValueEx(key, '')[0]
                except FileNotFoundError:
                    previous = ''
                if previous != 'OpenCommander':
                    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r'Software\OpenCommander') as backup:
                        winreg.SetValueEx(backup, 'PreviousDirectoryVerb', 0, winreg.REG_SZ, previous)
                winreg.SetValueEx(key, '', 0, winreg.REG_SZ, 'OpenCommander')
        except OSError as error:
            QMessageBox.warning(window, 'OpenCommander', str(error))
            return
    settings.setValue('windows_default_prompted', True)
    settings.sync()
