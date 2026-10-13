"""Cancelable loopback OAuth with PKCE for public Microsoft/Dropbox clients."""
import base64
from datetime import datetime, timedelta, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import queue
import secrets
import threading
import time
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen
from .public_oauth import normalized_native

REDIRECT_URI = 'http://localhost:53682/'
PROVIDERS = {
    'onedrive': ('https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
                 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
                 'Files.ReadWrite.All offline_access User.Read'),
    'dropbox': ('https://www.dropbox.com/oauth2/authorize',
                'https://api.dropboxapi.com/oauth2/token',
                'account_info.read files.metadata.read files.metadata.write files.content.read files.content.write sharing.read sharing.write'),
}


def token_request(kind, values):
    # Fixed provider endpoints; errors must never expose codes, tokens or replies.
    try:
        request = Request(PROVIDERS[kind][1], data=urlencode(values).encode(),
                          headers={'Content-Type': 'application/x-www-form-urlencoded'})
        with urlopen(request, timeout=15) as response:
            payload = response.read(65537)
        if len(payload) > 65536:
            raise ValueError()
        value = json.loads(payload)
        if (not isinstance(value, dict) or value.get('error') or
                not isinstance(value.get('access_token'), str) or not value['access_token'] or
                not isinstance(value.get('refresh_token'), str) or not value['refresh_token']):
            raise ValueError()
        seconds = int(value['expires_in'])
        if not 0 < seconds <= 366 * 86400 or str(value.get('token_type', 'Bearer')).lower() != 'bearer':
            raise ValueError()
        return {'access_token': value['access_token'], 'refresh_token': value['refresh_token'],
                'token_type': 'Bearer',
                'expiry': (datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat()}
    except Exception:
        raise RuntimeError('Anmeldung konnte nicht abgeschlossen werden. Bitte erneut anmelden. / Sign-in failed; try again.') from None


def exchange_cancellable(kind, values, cancel):
    """Discard in-flight results immediately on cancel; never persist them."""
    outcome = queue.Queue(maxsize=1)
    def run():
        try:
            outcome.put((token_request(kind, values), None))
        except Exception as error:
            outcome.put((None, error))
    threading.Thread(target=run, daemon=True).start()
    deadline = time.monotonic() + 20
    while True:
        if cancel.is_set():
            raise RuntimeError('Abgebrochen / Cancelled')
        if time.monotonic() >= deadline:
            raise RuntimeError('Anmeldung: Netzwerk-Zeitüberschreitung. Erneut versuchen. / Sign-in network timed out.')
        try:
            result, error = outcome.get(timeout=0.1)
        except queue.Empty:
            continue
        if cancel.is_set():
            raise RuntimeError('Abgebrochen / Cancelled')
        if error:
            raise error
        return result


def authorize(kind, client, cancel, browser_callback, timeout=600):
    client = normalized_native(kind, client)
    auth_endpoint, _, scope = PROVIDERS[kind]
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    state = secrets.token_urlsafe(32)
    query = {'client_id': client['client_id'], 'redirect_uri': REDIRECT_URI,
             'response_type': 'code', 'scope': scope, 'state': state,
             'code_challenge': challenge, 'code_challenge_method': 'S256'}
    query.update({'token_access_type': 'offline'} if kind == 'dropbox' else {'prompt': 'select_account'})
    auth_url = auth_endpoint + '?' + urlencode(query)
    outcome = {}

    class BoundedServer(HTTPServer):
        def get_request(self):
            connection, address = super().get_request()
            connection.settimeout(0.5)
            return connection, address

        def handle_error(self, request, client_address):
            pass  # Never print callback request details.

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Callback URLs contain authorization codes.

        def reply(self, status, text, location=None):
            self.send_response(status)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Referrer-Policy', 'no-referrer')
            if location:
                self.send_header('Location', location)
            self.end_headers()
            self.wfile.write(text.encode())

        def do_GET(self):
            parsed = urlsplit(self.path)
            params = parse_qs(parsed.query)
            if self.headers.get('Host') not in ('localhost:53682', '127.0.0.1:53682'):
                self.reply(400, 'Invalid host'); return
            values = params.get('state', [])
            if len(values) != 1 or not secrets.compare_digest(values[0].encode(), state.encode()):
                self.reply(400, 'Invalid sign-in state'); return
            if parsed.path == '/auth':
                self.reply(302, 'OpenCommander sign-in', auth_url); return
            if parsed.path != '/':
                self.reply(404, 'Not found'); return
            if 'error' in params:
                outcome['error'] = True
                self.reply(200, 'Anmeldung abgebrochen. Zurueck zu OpenCommander. / Sign-in cancelled.'); return
            codes = params.get('code', [])
            if len(codes) != 1 or not codes[0] or len(codes[0]) > 8192:
                self.reply(400, 'Missing sign-in code'); return
            outcome['code'] = codes[0]
            self.reply(200, 'Anmeldung wird abgeschlossen. Zurueck zu OpenCommander. / Return to OpenCommander.')

    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    try:
        server = BoundedServer(('127.0.0.1', 53682), Handler)
    except OSError:
        raise RuntimeError('Eine andere Browser-Anmeldung ist noch offen. Diese zuerst abschließen oder abbrechen. / Another sign-in is using the login port.') from None
    with server:
        server.timeout = 0.25
        browser_callback('http://127.0.0.1:53682/auth?' + urlencode({'state': state}))
        deadline = time.monotonic() + timeout
        while not outcome:
            if cancel.is_set():
                raise RuntimeError('Abgebrochen / Cancelled')
            if time.monotonic() >= deadline:
                raise RuntimeError('Anmeldung abgelaufen. Erneut anmelden. / Sign-in timed out.')
            server.handle_request()
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    if outcome.get('error'):
        raise RuntimeError('Anmeldung nicht erlaubt oder abgebrochen. / Sign-in denied or cancelled.')
    token = exchange_cancellable(kind, {'client_id': client['client_id'], 'grant_type': 'authorization_code',
                                       'redirect_uri': REDIRECT_URI, 'code': outcome['code'], 'code_verifier': verifier}, cancel)
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    return token
