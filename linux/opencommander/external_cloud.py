"""Discover current-user rclone mounts without probing cloud files or copying secrets."""
import configparser
import hashlib
import os
from pathlib import Path

KINDS = {'drive', 'onedrive', 'dropbox', 'iclouddrive'}


def root_for(main, profile):
    if profile.get('external'):
        return Path(profile['mount_root'])
    from .online_ui import mount_path
    return mount_path(main.state_dir, profile['id'])


def config_for(main, profile):
    if profile.get('external'):
        return Path(profile['config_path'])
    from .online_ui import private_config
    return private_config(main.state_dir)


def remote_for(profile, relative):
    base = profile.get('remote_base', profile['id'] + ':')
    return base + relative if base.endswith(':') else base.rstrip('/') + ('/' + relative if relative else '')


def discover(proc=Path('/proc'), home=None):
    from .provider_mounts import rclone_mount
    result = []
    home = Path(home or Path.home())
    try:
        processes = list(proc.iterdir())
    except OSError:
        return []
    for process in processes:
        if not process.name.isdigit():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            args = (process / 'cmdline').read_bytes().decode().rstrip('\0').split('\0')
            if Path(args[0]).name != 'rclone' or 'mount' not in args:
                continue
            index = args.index('mount')
            remote, root = args[index + 1:index + 3]
            if ':' not in remote or not os.path.isabs(root):
                continue
            # Command-line namespace overrides must not accidentally share a different object.
            if any(a.split('=')[0] in {'--drive-root-folder-id', '--drive-shared-with-me', '--drive-team-drive',
                                      '--onedrive-drive-id', '--onedrive-root-folder-id'} for a in args):
                continue
            root = Path(os.path.abspath(root))
            mounted = rclone_mount(root)
            if not mounted or mounted[0] != root:
                continue
            config = home / '.config/rclone/rclone.conf'
            if '--config' in args:
                config = Path(args[args.index('--config') + 1])
            else:
                configured = next((a.split('=', 1)[1] for a in args if a.startswith('--config=')), None)
                if configured:
                    config = Path(configured)
            if not config.is_absolute() or config.stat().st_uid != os.getuid():
                continue
            parser = configparser.ConfigParser(interpolation=None)
            parser.read(config)
            section = remote.split(':', 1)[0]
            kind = parser[section].get('type')
            if kind not in KINDS:
                continue
            result.append(dict(id='external_' + hashlib.sha256(str(root).encode()).hexdigest()[:16],
                               kind=kind, name=root.name, external=True, mount_root=str(root),
                               config_path=str(config), remote_base=remote))
        except (OSError, ValueError, IndexError, KeyError, configparser.Error, UnicodeError):
            continue
    return list({row['mount_root']: row for row in result}.values())
