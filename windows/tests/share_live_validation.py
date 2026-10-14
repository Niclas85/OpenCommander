"""Create and revoke public links for synthetic fixtures only; never log link secrets."""
from pathlib import Path
from types import SimpleNamespace
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from PySide6.QtCore import QSettings

REPO = Path(__file__).resolve().parents[2]
CONTEXT = json.loads((REPO / 'windows/build/live-context.json').read_text(encoding='utf-8-sig'))
INSTALLED = Path(CONTEXT['installed'])
sys.path.insert(0, str(INSTALLED / 'source/linux'))
from opencommander import cloud_actions, rclone_runtime
from opencommander.desktop import host_environment
from opencommander.online_ui import private_config
rclone_runtime.binary = lambda: str(INSTALLED / 'tools/rclone.exe')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--provider', choices=('drive', 'onedrive', 'dropbox'), required=True)
    parser.add_argument('--browser', action='store_true')
    args = parser.parse_args()
    state = Path(os.environ['LOCALAPPDATA']) / 'OpenCommander'
    settings = QSettings(str(state / 'settings.ini'), QSettings.IniFormat)
    profiles = json.loads(settings.value('online_profiles', '[]'))
    profile = next(row for row in profiles if row['kind'] == args.provider)
    config = private_config(state)
    identifier = uuid.uuid4().hex
    folder = REPO / 'windows/build/share-fixtures' / identifier
    folder.mkdir(parents=True)
    source = folder / 'Freigabe Grüße 日本語.txt'
    data = b'OpenCommander public sharing test fixture. No user files or personal information.\n' * 32
    source.write_bytes(data)
    relative = 'OpenCommander-Freigabepruefung-' + identifier + '/' + source.name
    remote = profile['id'] + ':' + relative
    (folder / 'fixture.json').write_text(json.dumps(dict(provider=args.provider, remote=remote)), encoding='utf-8')
    base = [rclone_runtime.binary(), '--config', str(config)]
    limits = ['--contimeout', '5s', '--timeout', '15s', '--retries', '1', '--low-level-retries', '1']
    result = dict(provider=args.provider, synthetic_fixture=True)
    uploaded = False
    linked = False
    try:
        copy = subprocess.run(base + ['copyto', str(source), remote] + limits,
                              capture_output=True, text=True, env=host_environment(), timeout=40)
        if copy.returncode:
            raise RuntimeError('Synthetic upload failed; provider access or quota unavailable')
        uploaded = True
        main_window = SimpleNamespace(state_dir=state)
        link = cloud_actions.share_link(main_window, profile, relative, threading.Event())
        linked = True
        result['link_created'] = True
        if args.browser:
            (folder / 'browser-fixture.json').write_text(json.dumps(dict(link=link, provider=args.provider)), encoding='utf-8')
            print(json.dumps(dict(status='awaiting-browser', provider=args.provider, fixture=str(folder), link=link)), flush=True)
            deadline = time.monotonic() + 300
            confirmation = folder / 'browser-checked.json'
            while not confirmation.exists() and time.monotonic() < deadline:
                time.sleep(.5)
            if not confirmation.exists():
                raise RuntimeError('Browser verification did not complete within five minutes')
            checked = json.loads(confirmation.read_text())
            if not checked.get('anonymous_content_verified'):
                raise RuntimeError('Anonymous browser could not display the synthetic content')
            result.update(status='pass', anonymous_browser_content=True, bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            return 0
        parsed = urlsplit(link)
        if args.provider == 'drive':
            identifier = (parsed.path.split('/file/d/', 1)[1].split('/', 1)[0]
                          if '/file/d/' in parsed.path else dict(parse_qsl(parsed.query))['id'])
            download = 'https://drive.google.com/uc?' + urlencode(dict(export='download', id=identifier))
        elif args.provider == 'onedrive':
            encoded = base64.urlsafe_b64encode(link.encode()).decode().rstrip('=')
            download = 'https://api.onedrive.com/v1.0/shares/u!' + encoded + '/root/content'
        else:
            query = dict(parse_qsl(parsed.query))
            query['dl'] = '1'
            download = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), parsed.fragment))
        with urlopen(Request(download, headers={'User-Agent': 'OpenCommander validation'}), timeout=20) as response:
            body = response.read(len(data) + 1)
            result['anonymous_http_status'] = response.status
        result['anonymous_byte_comparison'] = body == data
        if body != data:
            raise RuntimeError('Public link response was not the synthetic payload; browser rendering may be required')
        result.update(status='pass', bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    except Exception as error:
        result.update(status='failed', error_type=type(error).__name__, error=str(error) if isinstance(error, RuntimeError) else 'Public link request failed')
    finally:
        if linked:
            removal = subprocess.run(base + ['link', '--unlink', remote] + limits,
                                     capture_output=True, text=True, env=host_environment(), timeout=40)
            result['unlink_command_succeeded'] = removal.returncode == 0
        if uploaded:
            deletion = subprocess.run(base + ['deletefile', remote] + limits,
                                      capture_output=True, text=True, env=host_environment(), timeout=40)
            result['synthetic_file_removed'] = deletion.returncode == 0
            empty_directory = remote.rsplit('/', 1)[0]
            cleanup = subprocess.run(base + ['rmdir', empty_directory] + limits,
                                     capture_output=True, text=True, env=host_environment(), timeout=40)
            result['synthetic_folder_removed'] = cleanup.returncode == 0
        if uploaded and not result.get('synthetic_file_removed'):
            result['cleanup_pending'] = True
        report = REPO / ('windows/build/share-live-' + args.provider + '.json')
        history = json.loads(report.read_text()) if report.exists() else []
        report.write_text(json.dumps(history + [result], indent=2), encoding='utf-8')
        print(json.dumps(result), flush=True)
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
