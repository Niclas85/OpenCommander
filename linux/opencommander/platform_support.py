"""Small platform boundary shared by both desktop builds."""
import os
from pathlib import Path
import sys

WINDOWS = sys.platform == 'win32'
PLATFORM_NAME = 'Windows' if WINDOWS else 'Linux'


def data_directory():
    if WINDOWS:
        return Path(os.environ.get('LOCALAPPDATA', Path.home() / 'AppData/Local')) / 'OpenCommander'
    return Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'opencommander'


def root_directory():
    return Path(Path.home().anchor) if WINDOWS else Path('/')


def helper_command(name):
    if WINDOWS:
        if getattr(sys, 'frozen', False):
            return [str(Path(sys.executable).parent / 'helpers/OpenCommanderHelper.exe'), name]
        return [sys.executable, str(Path(__file__).with_name(name + '.py'))]
    return ['/usr/bin/python3', str(Path(__file__).with_name(name + '.py'))]


def initialize():
    if not WINDOWS:
        return
    # Qt's FFmpeg encoder probing can hang on Windows HEVC extensions even
    # during playback. Use the native playback backend; allow explicit override.
    os.environ.setdefault('QT_MEDIA_BACKEND', 'windows')
    # Never resolve this DLL against the current directory or an untrusted PATH.
    bundled = Path(getattr(sys, '_MEIPASS', Path(__file__).parent)) / 'archive.dll'
    system = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32/archiveint.dll'
    if 'LIBARCHIVE' not in os.environ:
        os.environ['LIBARCHIVE'] = str(bundled if bundled.is_file() else system)
    # Child tools must not flash console windows from the GUI executable.
    import subprocess
    original = subprocess.Popen
    if not getattr(original, '_opencommander', False):
        class HiddenProcess(original):
            _opencommander = True

            def __init__(self, *args, **kwargs):
                kwargs['creationflags'] = kwargs.get('creationflags', 0) | subprocess.CREATE_NO_WINDOW
                if kwargs.get('text') or kwargs.get('universal_newlines'):
                    kwargs.setdefault('encoding', 'utf-8')
                super().__init__(*args, **kwargs)
        subprocess.Popen = HiddenProcess


def is_link(path):
    return path.is_symlink() or (WINDOWS and path.is_junction())


def native_path(path):
    """Use Windows extended paths without requiring a machine-wide policy."""
    if not WINDOWS:
        return Path(path)
    value = os.path.abspath(path)
    if value.startswith('\\\\?\\'):
        return Path(value)
    if value.startswith('\\\\'):
        return Path('\\\\?\\UNC\\' + value[2:])
    return Path('\\\\?\\' + value)


def validate_component(name):
    if WINDOWS:
        from pathlib import PureWindowsPath
        if (PureWindowsPath(name).is_reserved() or name.endswith((' ', '.')) or
                any(c in '<>:"/\\|?*' or ord(c) < 32 for c in name)):
            from .operations import SafetyError
            raise SafetyError('Ungültiger Windows-Dateiname / Invalid Windows filename: ' + name)


def canonical_path(path):
    """Resolve local aliases without GetFinalPathNameByHandle on WinFsp volumes.

    WinFsp directory mounts can support normal I/O while Windows rejects final
    path queries with ERROR_UNRECOGNIZED_VOLUME. Preserve the registered provider
    namespace and resolve only its local ancestors for containment checks.
    """
    if not WINDOWS:
        return Path(path).resolve()
    from .windows_native import lexical_remote_location as remote_location
    path = Path(os.path.abspath(path))
    for _ in range(32):
        prefix = Path(path.anchor)
        if remote_location(prefix):
            return path
        for index, part in enumerate(path.parts[1:], 1):
            prefix /= part
            if remote_location(prefix):
                return prefix.joinpath(*path.parts[index + 1:])
            if prefix.is_symlink() or prefix.is_junction():
                destination = os.readlink(prefix)
                if destination.startswith('\\\\?\\UNC\\'):
                    destination = '\\\\' + destination[8:]
                elif destination.startswith(('\\\\?\\', '\\??\\')):
                    destination = destination[4:]
                target = Path(destination)
                if not target.is_absolute():
                    target = prefix.parent / target
                path = Path(os.path.abspath(target.joinpath(*path.parts[index + 1:])))
                break
        else:
            return path
    from .operations import SafetyError
    raise SafetyError('Zyklische Verknüpfung / Cyclic path alias: ' + str(path))
