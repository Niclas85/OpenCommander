import base64
import hashlib
import io
import json
import secrets
import socket
import threading
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, build_opener, urlopen
import pytest
from desktop_test_support import assert_private_file
from opencommander import native_oauth, online_ui, public_oauth


def identity(kind):
    identifier = '12345678-1234-1234-1234-123456789abc' if kind == 'onedrive' else 'fixtureappkey123'
    return {'client_id': identifier, 'flow': 'pkce'}


def token():
    return {'access_token': secrets.token_urlsafe(24), 'refresh_token': secrets.token_urlsafe(24),
            'token_type': 'Bearer', 'expiry': '2030-01-01T00:00:00Z'}


@pytest.mark.parametrize('kind', ['onedrive', 'dropbox'])
def test_public_native_build_rejects_secrets_and_preserves_existing_clients(kind, tmp_path, monkeypatch):
    client = identity(kind)
    source, output = tmp_path/'publisher.json', tmp_path/'assets/native.json'
    source.write_text(json.dumps(client)); public_oauth.prepare_native(kind, source, output)
    assert json.loads(output.read_text()) == client
    assert_private_file(output)
    for field in ('client_secret', 'refresh_token', 'password'):
        with pytest.raises(ValueError): public_oauth.normalized_native(kind, dict(client, **{field: secrets.token_urlsafe(16)}))
    monkeypatch.setattr(public_oauth, 'native_client', lambda k: client)
    config = tmp_path/'config'
    config.write_text('[oc_fixture]\nclient_id=existing\n')
    assert public_oauth.select_native(kind, config=config, remote='oc_fixture') is None
    config.write_text('[oc_fixture]\nclient_id='+client['client_id']+'\noc_oauth_flow=pkce\n')
    assert public_oauth.select_native(kind, config=config, remote='oc_fixture') == client


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


@pytest.mark.parametrize('kind', ['onedrive', 'dropbox'])
def test_loopback_pkce_checks_state_and_exchanges_code_without_secret(kind, monkeypatch):
    cancel = threading.Event(); result = {}; errors = []; exchange = {}
    expected = token()
    def fake_exchange(provider, values):
        exchange.update(values); assert provider == kind
        assert 'client_secret' not in values
        return expected
    monkeypatch.setattr(native_oauth, 'token_request', fake_exchange)
    def callback(url):
        def browser():
            try:
                with pytest.raises(HTTPError) as redirect:
                    build_opener(NoRedirect).open(url, timeout=2)
                assert redirect.value.code == 302
                query = parse_qs(urlsplit(redirect.value.headers['Location']).query)
                assert query['code_challenge_method'] == ['S256']
                assert query['redirect_uri'] == [native_oauth.REDIRECT_URI]
                assert 'client_secret' not in query
                from urllib.request import Request
                with pytest.raises(HTTPError) as host:
                    urlopen(Request(url,headers={'Host':'example.invalid:53682'}),timeout=2)
                assert host.value.code==400
                with pytest.raises(HTTPError) as wrong:
                    urlopen('http://127.0.0.1:53682/?code=fixture&state=wrong', timeout=2)
                assert wrong.value.code == 400
                urlopen('http://127.0.0.1:53682/?'+urlencode({'state':query['state'][0], 'code':'fixture-code'}),timeout=2).close()
                result.update(query)
            except BaseException as error:
                errors.append(error); cancel.set()
        thread=threading.Thread(target=browser); thread.start(); result['thread']=thread
    obtained = native_oauth.authorize(kind, identity(kind), cancel, callback, timeout=5)
    result['thread'].join(2)
    assert not errors and obtained == expected
    challenge = base64.urlsafe_b64encode(hashlib.sha256(exchange['code_verifier'].encode()).digest()).rstrip(b'=').decode()
    assert result['code_challenge'] == [challenge]
    assert exchange['code'] == 'fixture-code'


def test_cancel_closes_loopback_even_when_client_sends_incomplete_request():
    cancel, ready = threading.Event(), threading.Event(); errors=[]
    def run():
        try: native_oauth.authorize('dropbox', identity('dropbox'), cancel, lambda url:ready.set())
        except RuntimeError as error: errors.append(str(error))
    worker=threading.Thread(target=run); worker.start()
    assert ready.wait(2)
    with socket.create_connection(('127.0.0.1',53682),timeout=2) as connection:
        connection.sendall(b'GET / HTTP/1.1\r\n')
        cancel.set(); worker.join(2)
    assert not worker.is_alive() and errors == ['Abgebrochen / Cancelled']
    # The next sign-in can reuse the port.
    server=native_oauth.HTTPServer(('127.0.0.1',53682),native_oauth.BaseHTTPRequestHandler); server.server_close()


def test_token_errors_are_redacted_and_requests_have_no_server_secret(monkeypatch):
    captured={}; credential=secrets.token_urlsafe(24)
    class Response(io.BytesIO):
        def __enter__(self):return self
        def __exit__(self,*args):self.close()
    def fake_open(request, timeout):
        captured.update(parse_qs(request.data.decode()))
        return Response(json.dumps(dict(access_token=credential,refresh_token=secrets.token_urlsafe(24),expires_in=3600,token_type='bearer')).encode())
    monkeypatch.setattr(native_oauth,'urlopen',fake_open)
    obtained=native_oauth.token_request('dropbox',{'client_id':'fixtureappkey123','code_verifier':credential})
    assert obtained['access_token']==credential and 'client_secret' not in captured
    monkeypatch.setattr(native_oauth,'urlopen',lambda *a,**k: (_ for _ in ()).throw(ValueError(credential)))
    with pytest.raises(RuntimeError) as failed:native_oauth.token_request('dropbox',{})
    assert credential not in str(failed.value)


def test_failed_reauthentication_preserves_previous_config(tmp_path,monkeypatch):
    config=tmp_path/'config'; previous='[oc_fixture]\ntype=dropbox\ntoken=previous\nclient_id=old\n'
    config.write_text(previous)
    monkeypatch.setattr(native_oauth,'authorize',lambda *a: (_ for _ in ()).throw(RuntimeError('denied')))
    with pytest.raises(RuntimeError):online_ui.native_login(config,'oc_fixture','dropbox',identity('dropbox'),threading.Event(),lambda url:None)
    assert config.read_text()==previous


def test_cancel_during_token_exchange_does_not_wait_for_provider(monkeypatch):
    entered,release,cancel=threading.Event(),threading.Event(),threading.Event()
    result=[]
    def slow(*args):
        entered.set();release.wait(3);return token()
    monkeypatch.setattr(native_oauth,'token_request',slow)
    def run():
        try:native_oauth.exchange_cancellable('dropbox',{},cancel)
        except RuntimeError as error:result.append(str(error))
    worker=threading.Thread(target=run);worker.start()
    assert entered.wait(2)
    cancel.set();worker.join(1);release.set()
    assert not worker.is_alive() and result==['Abgebrochen / Cancelled']
