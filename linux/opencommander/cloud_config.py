"""Validate cloud setup without logging or probing personal remote files."""
import base64
import configparser
import json
import subprocess

from . import rclone_runtime
from .desktop import host_environment


class CloudSetupError(RuntimeError):
    """Saved configuration needs the login assistant, rather than another mount."""


def obscured(value):
    try:
        return len(base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))) >= 16
    except (ValueError, TypeError):
        return False


def obscure(value, cancel):
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    result = subprocess.run([rclone_runtime.binary(), 'obscure', '-'],
                            input=value + '\n', text=True, capture_output=True,
                            timeout=10, env=host_environment())
    if result.returncode or not obscured(result.stdout.strip()):
        raise CloudSetupError('Passwort konnte nicht vorbereitet werden. / Could not prepare password.')
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    return result.stdout.strip()


def validate(config, identifier):
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(config)
    section = parser[identifier] if identifier in parser else {}
    kind = section.get('type')
    if kind in ('onedrive', 'drive', 'dropbox'):
        try:
            token = json.loads(section.get('token', ''))
            logged_in = isinstance(token, dict) and bool(token.get('access_token'))
        except (ValueError, TypeError):
            logged_in = False
        if not logged_in:
            raise CloudSetupError('Anmeldung nicht abgeschlossen. „Erneut anmelden“ öffnet den Browser. / Sign-in incomplete; sign in again.')
        if kind == 'onedrive' and not all(section.get(key) for key in ('drive_id', 'drive_type')):
            raise CloudSetupError('OneDrive-Laufwerk noch nicht ausgewählt. Anmeldung im Assistenten abschließen. / Finish selecting your OneDrive drive.')
    elif kind == 'iclouddrive':
        if not section.get('apple_id') or not obscured(section.get('password', '')):
            raise CloudSetupError('iCloud-Anmeldung unvollständig: Apple-ID und reguläres Apple-Passwort erneut eingeben. / Enter your Apple ID and regular password again.')
        if not section.get('trust_token') or not section.get('cookies'):
            raise CloudSetupError('iCloud-Bestätigung fehlt. „Erneut anmelden“ wählen und Apple-Bestätigungscode eingeben. / Complete Apple verification in the login assistant.')
