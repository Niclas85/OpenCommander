"""Exercise the Windows WebClient redirector against an anonymous loopback DAV server."""
from pathlib import Path
from types import SimpleNamespace
import json
import socket
import subprocess
import sys
import threading
import time
import traceback

REPO = Path(__file__).resolve().parents[2]
CONTEXT = json.loads((REPO / 'windows/build/live-context.json').read_text(encoding='utf-8-sig'))
INSTALLED = Path(CONTEXT['installed'])
sys.path.insert(0, str(REPO / 'linux' if '--source' in sys.argv else INSTALLED / 'source/linux'))
from opencommander import platform_support, windows_native
from opencommander.operations import FileEngine
platform_support.helper_command = lambda name: [str(INSTALLED / 'helpers/OpenCommanderHelper.exe'), name]


def main():
    from wsgidav.wsgidav_app import WsgiDAVApp
    from cheroot.wsgi import Server
    import win32netcon
    import win32wnet
    folder = REPO / 'windows/build/native-webdav' / str(time.time_ns())
    folder.mkdir(parents=True)
    backing = folder / 'server-data'
    backing.mkdir()
    data = bytes(range(256)) * 1024
    source = folder / 'Grüße 日本語.bin'
    source.write_bytes(data)
    (backing / 'read.txt').write_bytes(b'OpenCommander native Windows WebDAV fixture')
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    config = dict(provider_mapping={'/': str(backing)},
                  simple_dc={'user_mapping': {'*': True}}, verbose=0,
                  logging={'enable': False},
                  http_authenticator={'accept_basic': False, 'accept_digest': False, 'default_to_digest': False})
    server = Server(('127.0.0.1', port), WsgiDAVApp(config))
    worker = threading.Thread(target=server.start, daemon=True)
    worker.start()
    remote = Path(windows_native.network_path(f'dav://127.0.0.1:{port}/'))
    result = dict(protocol='native-windows-webdav', anonymous_loopback=True, port=port)
    connected = False
    try:
        deadline = time.monotonic() + 10
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.2):
                    break
            except OSError:
                if time.monotonic() > deadline:
                    raise RuntimeError('Loopback WebDAV server did not start')
                time.sleep(.1)
        resource = win32wnet.NETRESOURCE()
        resource.dwType = win32netcon.RESOURCETYPE_DISK
        resource.lpRemoteName = str(remote)
        win32wnet.WNetAddConnection2(resource, None, None, 0)
        connected = True
        result['stage'] = 'initial-listing'
        rows = windows_native.invoke('scan', str(remote))
        assert any(row['name'] == 'read.txt' for row in rows)
        result['initial_listing'] = True
        engine = FileEngine(folder / 'operations')
        directory = remote / 'OpenCommander-native-WebDAV-test'
        result['stage'] = 'mkdir'
        engine.mkdir(remote, directory.name)
        creation_id = engine.history[-1]['id']
        result['mkdir'] = True
        result['stage'] = 'upload'
        operation = engine.transfer([source], directory)
        result['upload'] = True
        result['stage'] = 'byte-comparison'
        assert (directory / source.name).read_bytes() == data
        assert (backing / directory.name / source.name).read_bytes() == data
        assert any(row['name'] == source.name for row in windows_native.invoke('scan', str(directory)))
        result['stage'] = 'properties'
        properties = windows_native.invoke('properties', str(directory / source.name))
        assert properties['size'] == len(data)
        result['stage'] = 'persistent-undo'
        restarted = FileEngine(engine.state_dir)
        restarted.undo(operation['id'])
        assert not (directory / source.name).exists()
        # Adding and removing a child changes the directory snapshot; undo of
        # its earlier creation must not be used as general folder cleanup.
        # Recovery metadata remains in this disposable server fixture.
        result.update(status='pass', bytes=len(data), frozen_helper_listing=True,
                      byte_comparison=True, persistent_undo=True, properties=True)
    except Exception as error:
        result.update(status='failed', error_type=type(error).__name__, error=str(error))
        (folder / 'failure.log').write_text(traceback.format_exc(), encoding='utf-8')
    finally:
        if connected:
            win32wnet.WNetCancelConnection2(str(remote), 0, False)
            result['native_disconnect'] = True
        server.stop()
        worker.join(timeout=5)
        report = REPO / 'windows/build/native-webdav-results.json'
        history = json.loads(report.read_text()) if report.exists() else []
        report.write_text(json.dumps(history + [result], ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
