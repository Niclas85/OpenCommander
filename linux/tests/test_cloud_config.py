import configparser
import secrets
import threading

import pytest

from opencommander import cloud_config, online_ui, rclone_runtime


@pytest.mark.parametrize('error,expected', [
    ('SRP complete: HTTP error 401 Unauthorized', '401'),
    ('Missing PCS cookies from the request', 'Webzugriff'),
    ('password: base64 decode failed when revealing password - is it obscured?', 'Passwort'),
])
def test_icloud_auth_failure_explains_category_without_echoing_reply(error, expected):
    private = 'synthetic-private-provider-reply'
    message = cloud_config.login_error('iclouddrive', error + '\n' + private)
    assert expected in message
    assert private not in message


@pytest.mark.parametrize('length', [8, 22])
def test_actual_icloud_password_question_stores_encoded_value(tmp_path, length):
    if not rclone_runtime.binary():
        pytest.skip('rclone unavailable')
    config = online_ui.private_config(tmp_path / 'state')
    cancel = threading.Event()
    secret = secrets.token_urlsafe(32)[:length]
    value = online_ui.command_json(config, ['config', 'create', 'oc_fixture', 'iclouddrive', '--all', '--non-interactive'], cancel)
    for name, answer in [('service', 'drive'), ('apple_id', 'test@example.invalid'), ('password', secret)]:
        assert value['Option']['Name'] == name
        value = online_ui.command_json(config, ['config', 'update', 'oc_fixture', '--all', '--non-interactive', '--continue', '--state', value['State']],
                                       cancel, result=answer, password_result=name == 'password', timeout=5)
    # Stop before Apple's authentication: all-set must store rclone wire format,
    # and plaintext of either short or base64-shaped length must never persist.
    assert value['Option']['Name'] == 'config_fs_advanced'
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(config)
    assert parser['oc_fixture']['password'] != secret
    assert cloud_config.obscured(parser['oc_fixture']['password'])
    assert config.stat().st_mode & 0o777 == 0o600


def test_incomplete_onedrive_requires_login_and_drive_selection(tmp_path):
    config = tmp_path / 'config'
    config.write_text('[oc_test]\ntype = onedrive\n')
    with pytest.raises(cloud_config.CloudSetupError, match='Anmeldung nicht abgeschlossen'):
        cloud_config.validate(config, 'oc_test')
    config.write_text('[oc_test]\ntype = onedrive\ntoken = {"access_token":"synthetic-fixture"}\n')
    with pytest.raises(cloud_config.CloudSetupError, match='Laufwerk'):
        cloud_config.validate(config, 'oc_test')
    config.write_text(config.read_text() + 'drive_id = fixture-drive\ndrive_type = personal\n')
    cloud_config.validate(config, 'oc_test')


def test_icloud_cannot_complete_before_device_verification(tmp_path):
    config = tmp_path / 'config'
    value = cloud_config.obscure(secrets.token_urlsafe(12), threading.Event())
    config.write_text('[oc_test]\ntype = iclouddrive\napple_id = test@example.invalid\npassword = ' + value + '\n')
    with pytest.raises(cloud_config.CloudSetupError, match='Bestätigung'):
        cloud_config.validate(config, 'oc_test')
    config.write_text(config.read_text() + 'trust_token = synthetic-fixture\ncookies = synthetic-fixture\n')
    cloud_config.validate(config, 'oc_test')
