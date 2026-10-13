import concurrent.futures
import json
import threading
import time
from types import SimpleNamespace

import pytest

from opencommander import cloud_listing, online_ui
from opencommander.cloud_listing import CloudError, CloudListings


class FastCancel(threading.Event):
    def wait(self, timeout=None):
        return self.is_set()


@pytest.mark.parametrize('kind', ['drive', 'onedrive', 'dropbox', 'iclouddrive'])
def test_first_cloud_listing_recovers_after_provider_rate_limits(tmp_path, monkeypatch, kind):
    script = tmp_path / 'rclone'
    counter = tmp_path / 'calls'
    script.write_text('#!/usr/bin/python3\nfrom pathlib import Path\nimport sys,json\n'
                      f'p=Path({str(counter)!r})\n'
                      'n=int(p.read_text()) if p.exists() else 0\np.write_text(str(n+1))\n'
                      'if n<2:\n print("403 Quota exceeded RATE_LIMIT_EXCEEDED PRIVATE_FIXTURE",file=sys.stderr)\n sys.exit(1)\n'
                      'print(json.dumps([{"Name":"photo.jpg","IsDir":False,"Size":12}]))\n')
    script.chmod(0o700)
    monkeypatch.setattr(online_ui.rclone_runtime, 'binary', lambda: str(script))
    main = SimpleNamespace(state_dir=tmp_path / 'state')
    profile = dict(id='oc_fixture', kind=kind)
    root = online_ui.mount_path(main.state_dir, profile['id'])
    rows = online_ui.list_cloud(main, profile, root, FastCancel())
    assert [row.name for row in rows] == ['photo.jpg'] and not rows.warning
    assert counter.read_text() == '3'


def test_cache_survives_quota_cooldown_and_recovers_but_never_hides_auth_error(monkeypatch):
    listing = CloudListings()
    calls = []
    clock = [100.0]
    monkeypatch.setattr(cloud_listing.time, 'monotonic', lambda: clock[0])
    responses = [[{'Name': 'old'}], CloudError('Provider rate limit', True),
                 [{'Name': 'new'}], CloudError('Sign in again')]
    def query(*args):
        calls.append(1)
        value = responses.pop(0)
        if isinstance(value, Exception):
            raise value
        return value
    monkeypatch.setattr(cloud_listing, 'query', query)
    assert listing.read('drive', [], threading.Event())[0]['Name'] == 'old'
    clock[0] += 5
    stale = listing.read('drive', [], threading.Event())
    assert stale[0]['Name'] == 'old' and 'Gespeicherte Dateiliste' in stale.warning
    assert listing.read('drive', [], threading.Event()).warning and len(calls) == 2
    clock[0] += 11
    fresh = listing.read('drive', [], threading.Event())
    assert fresh[0]['Name'] == 'new' and not fresh.warning
    clock[0] += 1
    with pytest.raises(CloudError, match='Sign in again'):
        listing.read('drive', [], threading.Event())
    assert not listing.cache


def test_parallel_panes_share_one_request_and_wait_can_be_cancelled(monkeypatch):
    listing = CloudListings()
    started, release, queued = threading.Event(), threading.Event(), threading.Event()
    calls = []
    def query(*args):
        calls.append(1)
        started.set()
        assert release.wait(3)
        return [{'Name': 'photo'}]
    monkeypatch.setattr(cloud_listing, 'query', query)
    with concurrent.futures.ThreadPoolExecutor(3) as pool:
        first = pool.submit(listing.read, 'drive', [], threading.Event())
        assert started.wait(3)
        def read():
            queued.set()
            return listing.read('drive', [], threading.Event())
        second = pool.submit(read)
        assert queued.wait(3)
        cancel = threading.Event()
        third = pool.submit(listing.read, 'drive', [], cancel)
        cancel.set()
        with pytest.raises(RuntimeError, match='Abgebrochen'):
            third.result(3)
        release.set()
        assert first.result(3) == second.result(3) == [{'Name': 'photo'}]
    assert len(calls) == 1


def test_exhausted_rate_limit_is_bounded_and_never_repeated_during_cooldown(monkeypatch):
    listing = CloudListings()
    calls = []
    def limited(*args):
        calls.append(1)
        raise cloud_listing.provider_error('403 rateLimitExceeded PRIVATE_FIXTURE')
    monkeypatch.setattr(cloud_listing, 'query', limited)
    for _ in range(2):
        with pytest.raises(CloudError, match='begrenzt') as error:
            listing.read('drive', [], FastCancel())
        assert 'PRIVATE_FIXTURE' not in str(error.value)
    assert len(calls) == 3


def test_cancel_during_retry_wait_does_not_restart_query(monkeypatch):
    started = threading.Event()
    calls = []
    def query(*args):
        started.set()
        calls.append(1)
        raise CloudError('Temporary error', True)
    monkeypatch.setattr(cloud_listing, 'query', query)
    cancel = threading.Event()
    with concurrent.futures.ThreadPoolExecutor(1) as pool:
        task = pool.submit(CloudListings().read, 'drive', [], cancel)
        assert started.wait(3)
        cancel.set()
        with pytest.raises(RuntimeError, match='Abgebrochen'):
            task.result(3)
    assert len(calls) == 1


@pytest.mark.parametrize('message,retryable', [('429 Too Many Requests', True),
    ('403 rateLimitExceeded', True), ('503 Service Unavailable', True),
    ('403 permission denied', False), ('401 Unauthorized', False), ('invalid_grant', False)])
def test_provider_errors_distinguish_throttling_from_permissions_and_login(message, retryable):
    error = cloud_listing.provider_error(message + ' PRIVATE_FIXTURE')
    assert error.retryable is retryable and 'PRIVATE_FIXTURE' not in str(error)


def test_own_google_client_is_private_preserves_other_profiles_and_invalidates_old_token(tmp_path):
    import configparser
    import stat
    config = online_ui.private_config(tmp_path / 'state')
    config.write_text('[oc_drive]\ntype = drive\ntoken = OLD_FIXTURE\nroot_folder_id = folder-id\n'
                      '[oc_other]\ntype = onedrive\ntoken = UNRELATED_FIXTURE\n')
    # Deliberately synthetic values; never authenticate a real account in this test.
    client = 'fixture.apps.googleusercontent.com'
    secret = 'fixture-client-value'
    online_ui.save_drive_client(config, 'oc_drive', client, secret)
    saved = configparser.ConfigParser(interpolation=None)
    saved.read(config)
    assert saved['oc_drive']['client_id'] == client and saved['oc_drive']['client_secret'] == secret
    assert 'token' not in saved['oc_drive'] and saved['oc_drive']['root_folder_id'] == 'folder-id'
    assert saved['oc_other']['token'] == 'UNRELATED_FIXTURE'
    assert stat.S_IMODE(config.stat().st_mode) == 0o600
    with pytest.raises(ValueError):
        online_ui.save_drive_client(config, 'oc_other', client, secret)
    with pytest.raises(ValueError):
        online_ui.save_drive_client(config, 'oc_drive', client, '')


def test_mutation_invalidates_old_list_and_cooldown(monkeypatch):
    listing = CloudListings()
    responses = [[{'Name': 'deleted.txt'}], CloudError('Rate limited', True), []]
    def query(*args):
        value = responses.pop(0)
        if isinstance(value, Exception):
            raise value
        return value
    monkeypatch.setattr(cloud_listing, 'query', query)
    assert listing.read('dropbox', [], threading.Event())
    stale = listing.read('dropbox', [], threading.Event())
    assert stale.warning
    listing.invalidate()
    assert not listing.read('dropbox', [], threading.Event())
    assert not responses


def test_inflight_listing_before_deletion_cannot_restore_removed_file(monkeypatch):
    listing = CloudListings()
    entered, release = threading.Event(), threading.Event()
    calls = []
    def query(*args):
        calls.append(1)
        if len(calls) == 1:
            entered.set()
            assert release.wait(3)
            return [{'Name': 'deleted.txt'}]
        return []
    monkeypatch.setattr(cloud_listing, 'query', query)
    with concurrent.futures.ThreadPoolExecutor(1) as pool:
        request = pool.submit(listing.read, 'dropbox', [], threading.Event())
        assert entered.wait(3)
        listing.invalidate()
        release.set()
        assert request.result(3) == []
    assert len(calls) == 2
    assert listing.cache['dropbox'][1] == []


def test_google_project_quota_has_actionable_help_and_no_immediate_retries(monkeypatch):
    listing = CloudListings()
    calls = []
    def limited(*args):
        calls.append(1)
        raise cloud_listing.provider_error('403 rateLimitExceeded defaultPerMinutePerProject PRIVATE_FIXTURE')
    monkeypatch.setattr(cloud_listing, 'query', limited)
    for _ in range(2):
        with pytest.raises(CloudError, match='Google-Client-ID') as error:
            listing.read('google', [], FastCancel())
        assert 'PRIVATE_FIXTURE' not in str(error.value)
        assert error.value.cooldown == 60
    assert len(calls) == 1
def test_authentication_denial_takes_priority_over_quota_in_mixed_output():
    from opencommander.cloud_listing import provider_error
    failure = provider_error('defaultPerMinutePerProject invalid_grant synthetic-fixture')
    assert failure.retryable is False
    assert 'Anmeldung' in str(failure) and 'synthetic-fixture' not in str(failure)
