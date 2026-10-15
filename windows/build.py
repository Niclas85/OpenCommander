"""Reproducible native Windows bundle; no system installation or account changes."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
SOURCE = REPO / 'linux'


def run(*args, **kwargs):
    kwargs.setdefault('stdout', sys.stdout)
    kwargs.setdefault('stderr', sys.stderr)
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-tests', action='store_true')
    parser.add_argument('--require-publisher-google', action='store_true',
                        help='Fail unless a publisher Desktop OAuth export is provided and packaged.')
    args = parser.parse_args()
    if sys.platform != 'win32' or sys.maxsize < 2**32:
        raise SystemExit('Build on Windows with 64-bit Python 3.12 or newer.')
    if args.require_publisher_google and not os.environ.get('OPENCOMMANDER_GOOGLE_OAUTH_FILE'):
        raise SystemExit('Publisher Google Desktop OAuth export required: set OPENCOMMANDER_GOOGLE_OAUTH_FILE.')
    build, dist = ROOT / 'build', ROOT / 'dist'
    build.mkdir(exist_ok=True)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', PYTHONUTF8='1', PYTHONPATH=str(SOURCE))
    sys.path.insert(0, str(SOURCE))
    from opencommander import rclone_runtime
    import threading
    rclone_runtime.runtime_root = lambda: build / 'runtime'
    backend = Path(rclone_runtime.ensure_cloud_backend(threading.Event()))
    env['PATH'] = str(backend.parent) + os.pathsep + env.get('PATH', '')
    if not args.skip_tests:
        run(sys.executable, '-m', 'pytest', ROOT / 'tests', '-q', '--tb=short',
            '--junitxml=' + str(build / 'pytest.xml'), env=env, cwd=REPO)
    run(sys.executable, ROOT / 'launcher.py', '--smoke-test', env=env)
    from PySide6.QtGui import QImage
    image = QImage(str(SOURCE / 'opencommander/assets/opencommander.png'))
    icon = build / 'opencommander.ico'
    if not image.save(str(icon)):
        raise RuntimeError('Could not generate Windows icon')
    common = [sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onedir',
              '--workpath', str(build), '--distpath', str(dist), '--specpath', str(build),
              '--paths', str(SOURCE), '--hidden-import', 'win32timezone']
    oauth = []
    for provider, variable in [('google', 'GOOGLE'), ('onedrive', 'ONEDRIVE'), ('dropbox', 'DROPBOX')]:
        source = os.environ.get('OPENCOMMANDER_' + variable + '_OAUTH_FILE')
        if source:
            target = build / 'public-oauth' / (provider + '-oauth.json')
            command = [sys.executable, '-m', 'opencommander.public_oauth']
            if provider != 'google':
                command.append(provider)
            run(*command, source, target, env=env)
            oauth.extend(['--add-data', str(target) + ';opencommander/assets'])
    run(*common, '--name', 'OpenCommander', '--windowed', '--icon', icon,
        '--manifest', ROOT / 'app.manifest',
        '--add-data', str(SOURCE / 'opencommander/assets') + ';opencommander/assets',
        '--copy-metadata', 'PySide6-Addons', '--copy-metadata', 'PySide6-Essentials',
        '--copy-metadata', 'shiboken6', '--copy-metadata', 'libarchive-c',
        '--copy-metadata', 'pywin32', '--copy-metadata', 'psutil', '--copy-metadata', 'cryptography',
        '--copy-metadata', 'bcrypt', '--copy-metadata', 'cffi', '--copy-metadata', 'pycparser',
        '--copy-metadata', 'paramiko', '--copy-metadata', 'invoke', '--copy-metadata', 'PyNaCl',
        '--hidden-import', 'opencommander.windows_bridge', '--hidden-import', 'opencommander.media_fetch',
        '--hidden-import', 'opencommander.device_bridge',
        *oauth, ROOT / 'launcher.py', env=env)
    run(*common, '--name', 'OpenCommanderHelper', '--console', '--manifest', ROOT / 'app.manifest',
        '--exclude-module', 'PySide6', '--exclude-module', 'libarchive',
        '--hidden-import', 'opencommander.windows_bridge', '--hidden-import', 'opencommander.media_fetch',
        '--hidden-import', 'opencommander.device_bridge',
        ROOT / 'helper.py', env=env)
    bundle = dist / 'OpenCommander'
    # Qt's Windows wheel links the unversioned OS ICU API. A foreign ICU from
    # the developer's PATH can be picked up by PyInstaller and shadow it.
    # Let Windows load its own System32 ICU; never redistribute that system DLL.
    (bundle / '_internal/icuuc.dll').unlink(missing_ok=True)
    (bundle / 'tools').mkdir(exist_ok=True)
    shutil.copy2(backend, bundle / 'tools/rclone.exe')
    if (backend.parent / 'rclone-README.txt').is_file():
        shutil.copy2(backend.parent / 'rclone-README.txt', bundle / 'tools/rclone-README.txt')
    shutil.copytree(dist / 'OpenCommanderHelper', bundle / 'helpers', dirs_exist_ok=True)
    for name in ('README.md', 'TESTING.md', 'PARITY.md', 'PUBLISHER.md', 'GOOGLE-VERIFICATION.md', 'install-local.ps1', 'uninstall-local.ps1'):
        shutil.copy2(ROOT / name, bundle / name)
    shutil.copy2(REPO / 'LICENSE', bundle / 'LICENSE')
    shutil.copy2(SOURCE / 'THIRD-PARTY.md', bundle / 'THIRD-PARTY-LINUX.md')
    shutil.copytree(SOURCE / 'licenses', bundle / 'licenses', dirs_exist_ok=True)
    shutil.copytree(SOURCE / 'docs/handbuch', bundle / 'docs/handbuch', dirs_exist_ok=True)
    shutil.copytree(REPO / 'release/linux', bundle / 'docs/public-release', dirs_exist_ok=True)
    shutil.copytree(SOURCE / 'opencommander', bundle / 'source/linux/opencommander', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*-oauth.json'))
    import paramiko
    shutil.copytree(Path(paramiko.__file__).parent, bundle / 'source/vendor/paramiko', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__'))
    (bundle / 'source/windows').mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / 'requirements.txt', bundle / 'source/linux/requirements.txt')
    for name in ('launcher.py', 'helper.py', 'requirements.txt', 'requirements-dev.txt', 'build.py', 'build.ps1', 'app.manifest'):
        shutil.copy2(ROOT / name, bundle / 'source/windows' / name)
    run(sys.executable, '-m', 'pip', 'freeze', stdout=(bundle / 'dependencies.txt').open('w'))
    # Test the actual GUI executable including the separately frozen helper.
    report = build / 'package-smoke.json'
    if report.exists():
        report.unlink()
    smoke = subprocess.run([str(bundle / 'OpenCommander.exe'), '--smoke-test', '--smoke-report', str(report)], env=env, timeout=60)
    if smoke.returncode:
        raise RuntimeError('Packaged application smoke test failed')
    import json
    if not json.loads(report.read_text(encoding='utf-8'))['ok']:
        raise RuntimeError('Packaged application did not confirm smoke test success')
    publisher_check = ['--require-publisher-google'] if args.require_publisher_google else []
    run(sys.executable, ROOT / 'tests/package_check.py', bundle, *publisher_check, env=env)
    artifacts = ROOT / 'artifacts'
    artifacts.mkdir(exist_ok=True)
    archive = artifacts / 'OpenCommander-windows-x64.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(bundle.rglob('*')):
            if path.is_file():
                output.write(path, path.relative_to(dist))
    checksum = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
    (artifacts / 'SHA256SUMS').write_text(checksum + '  ' + archive.name + '\n', encoding='ascii')
    print('Windows application: ' + str(bundle / 'OpenCommander.exe'))


if __name__ == '__main__':
    main()
