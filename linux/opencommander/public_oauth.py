"""Publisher-provided Google Desktop OAuth identity; never account tokens."""
import configparser
import json
from pathlib import Path
import re


def normalized(value):
    if not isinstance(value, dict) or 'web' in value:
        raise ValueError('Google-Konfiguration muss eine Desktop-Anwendung sein / Desktop OAuth configuration required')
    desktop = value.get('installed', value)
    allowed = {'client_id', 'client_secret', 'project_id', 'auth_uri', 'token_uri', 'auth_provider_x509_cert_url', 'redirect_uris'}
    if not isinstance(desktop, dict) or set(desktop) - allowed:
        raise ValueError('Keine Kontodaten oder Tokens im öffentlichen OAuth-Paket / Account tokens are forbidden')
    identifier, secret = desktop.get('client_id'), desktop.get('client_secret')
    if not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9._-]+\.apps\.googleusercontent\.com', identifier):
        raise ValueError('Ungültige Desktop-Client-ID / Invalid Desktop client ID')
    if not isinstance(secret, str) or not secret or len(secret) > 1024 or any(ord(c) < 32 for c in secret):
        raise ValueError('Ungültige Desktop-Client-Konfiguration / Invalid Desktop client configuration')
    if 'installed' in value and set(value) != {'installed'}:
        raise ValueError('Zusätzliche Kontodaten nicht erlaubt / Additional account data forbidden')
    return {'client_id': identifier, 'client_secret': secret}


def prepare(source, destination):
    source, destination = Path(source), Path(destination)
    if source.stat().st_size > 16384:
        raise ValueError('OAuth-Konfiguration zu groß / OAuth configuration too large')
    exported = json.loads(source.read_text())
    if not isinstance(exported, dict) or set(exported) != {'installed'}:
        raise ValueError('Offizieller Google-Desktop-Export erforderlich / Google Desktop export required')
    client = normalized(exported)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(client, indent=2) + '\n')
    destination.chmod(0o600)


def bundled_client():
    path = Path(__file__).parent / 'assets/google-oauth.json'
    try:
        if path.stat().st_size > 16384:
            return None
        return normalized(json.loads(path.read_text()))
    except (OSError, ValueError, TypeError):
        return None


def select_client(identifier, secret, config=None, remote=None):
    if identifier or secret:
        return identifier, secret
    if config and remote:
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(config)
        if parser.has_section(remote) and parser[remote].get('client_id'):
            # Reconnect must preserve the user's own OAuth application and token.
            return '', ''
    client = bundled_client()
    return (client['client_id'], client['client_secret']) if client else ('', '')


NATIVE_KINDS = ('onedrive', 'dropbox')


def normalized_native(kind, value):
    """Only public PKCE app identifiers, never confidential/server secrets."""
    if kind not in NATIVE_KINDS or not isinstance(value, dict) or set(value) != {'client_id', 'flow'} or value['flow'] != 'pkce':
        raise ValueError('Public native PKCE application required; account tokens and server secrets forbidden')
    identifier = value['client_id']
    pattern = r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}' if kind == 'onedrive' else r'[A-Za-z0-9]{10,64}'
    if not isinstance(identifier, str) or not re.fullmatch(pattern, identifier):
        raise ValueError('Invalid public application identifier')
    return {'client_id': identifier, 'flow': 'pkce'}


def native_client(kind):
    if kind not in NATIVE_KINDS:
        return None
    try:
        path = Path(__file__).parent / f'assets/{kind}-oauth.json'
        if path.stat().st_size > 16384:
            return None
        return normalized_native(kind, json.loads(path.read_text()))
    except (OSError, ValueError, TypeError):
        return None


def prepare_native(kind, source, destination):
    source, destination = Path(source), Path(destination)
    if source.stat().st_size > 16384:
        raise ValueError('OAuth configuration too large')
    client = normalized_native(kind, json.loads(source.read_text()))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(client, indent=2) + '\n')
    destination.chmod(0o600)


def select_native(kind, identifier='', config=None, remote=None):
    if identifier:
        return normalized_native(kind, {'client_id': identifier, 'flow': 'pkce'})
    if config and remote:
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(config)
        if parser.has_section(remote) and parser[remote].get('client_id'):
            if parser[remote].get('oc_oauth_flow') == 'pkce':
                return normalized_native(kind, {'client_id': parser[remote]['client_id'], 'flow': 'pkce'})
            return None  # Never migrate existing custom clients silently.
    return native_client(kind)


if __name__ == '__main__':
    import sys
    if len(sys.argv) not in (3, 4):
        raise SystemExit('Usage: python -m opencommander.public_oauth [onedrive|dropbox] INPUT.json OUTPUT.json')
    try:
        if len(sys.argv) == 4:
            prepare_native(sys.argv[1], sys.argv[2], sys.argv[3])
        else:
            prepare(sys.argv[1], sys.argv[2])
    except (OSError, ValueError, TypeError):
        raise SystemExit('Desktop-OAuth-Konfiguration ungültig; Build gestoppt. / Invalid Desktop OAuth configuration; build stopped.')
