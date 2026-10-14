import json
import secrets
import pytest
from desktop_test_support import assert_private_file
from opencommander import public_oauth


def client():
    return dict(client_id='123-fixture.apps.googleusercontent.com', client_secret=secrets.token_urlsafe(20))


def test_desktop_export_is_reduced_to_application_identity(tmp_path):
    data = client()
    source, target = tmp_path/'export.json', tmp_path/'assets/google-oauth.json'
    source.write_text(json.dumps({'installed':dict(data,project_id='fixture',redirect_uris=['http://localhost'])}))
    public_oauth.prepare(source,target)
    assert json.loads(target.read_text()) == data
    assert_private_file(target)


@pytest.mark.parametrize('bad',['web','refresh_token','access_token','password','extra'])
def test_account_credentials_and_web_clients_never_enter_public_package(bad):
    data = client()
    if bad == 'web':data = {'web':data}
    elif bad == 'extra':data = {'installed':data, 'token':'forbidden'}
    else:data[bad] = 'forbidden'
    with pytest.raises(ValueError):public_oauth.normalized(data)


def test_shared_client_is_default_but_explicit_and_existing_clients_survive(tmp_path,monkeypatch):
    data=client();monkeypatch.setattr(public_oauth,'bundled_client',lambda:data)
    assert public_oauth.select_client('','') == (data['client_id'],data['client_secret'])
    assert public_oauth.select_client('explicit','value') == ('explicit','value')
    config=tmp_path/'config';config.write_text('[oc_fixture]\nclient_id=existing\n')
    assert public_oauth.select_client('','',config,'oc_fixture') == ('','')
    config.write_text('[oc_fixture]\ntype=drive\n')
    assert public_oauth.select_client('','',config,'oc_fixture') == (data['client_id'],data['client_secret'])


def test_build_requires_official_desktop_export_not_untyped_client_fields(tmp_path):
    source=tmp_path/'export.json';source.write_text(json.dumps(client()))
    with pytest.raises(ValueError,match='Desktop export required'):
        public_oauth.prepare(source,tmp_path/'output.json')
    assert not (tmp_path/'output.json').exists()
