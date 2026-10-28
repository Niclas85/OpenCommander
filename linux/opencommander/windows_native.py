"""Windows APIs; remote reads run in a killable helper, never on the GUI thread."""
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time
import ctypes
import functools
import pywintypes


# Missing drive/path, not-ready, no-media, and device-disconnected results.
# Access denied and sharing violations never prove successful safe removal.
_REMOVED_MEDIA_ERRORS = frozenset((2, 3, 15, 21, 1112, 1167))


def native_errors(callback):
    @functools.wraps(callback)
    def call(*args, **kwargs):
        try:
            return callback(*args, **kwargs)
        except pywintypes.error as error:
            raise ctypes.WinError(error.winerror) from None
    return call


def drive_roots():
    import win32api
    return [Path(root) for root in win32api.GetLogicalDriveStrings().split('\0') if root]


def lexical_remote_location(path):
    import win32file
    from .provider_mounts import managed
    path = Path(os.path.abspath(path))
    return managed(path) or str(path).startswith('\\\\') or win32file.GetDriveType(path.anchor) == 4


def remote_location(path):
    from .platform_support import canonical_path
    return lexical_remote_location(canonical_path(path))


def mount_identity(path):
    import win32api
    import win32file
    from .provider_mounts import _roots
    path = Path(os.path.abspath(path))
    for root in sorted(_roots, key=lambda p: len(p.parts), reverse=True):
        if root == path or root in path.parents:
            # Check the mount itself, never silently use its underlying C: volume.
            if not root.is_mount() and not root.is_junction():
                return None
            return dict(root=str(root), filesystem='fuse.rclone', device=str(root))
    root = path.anchor
    if str(path).startswith('\\\\') or win32file.GetDriveType(root) == 4:
        return dict(root=root, filesystem='smb', device=root.casefold())
    try:
        info = win32api.GetVolumeInformation(root)
        return dict(root=root, filesystem=info[4], device=str(info[1]))
    except (OSError, pywintypes.error):
        return None


@native_errors
def open_regular(path, flags):
    """Open without following final reparse points or truncating before validation."""
    import msvcrt
    import win32con
    import win32file
    from .operations import SafetyError
    writing = bool(flags & (os.O_WRONLY | os.O_RDWR))
    handle = win32file.CreateFile(str(path), win32con.GENERIC_WRITE if writing else win32con.GENERIC_READ,
                                 win32con.FILE_SHARE_READ | win32con.FILE_SHARE_WRITE | win32con.FILE_SHARE_DELETE,
                                 None, win32con.OPEN_EXISTING, 0x00200000, None)
    try:
        info = win32file.GetFileInformationByHandle(handle)
        name_surrogate = False
        if info[0] & win32con.FILE_ATTRIBUTE_REPARSE_POINT:
            import ctypes
            from ctypes import wintypes
            class AttributeTag(ctypes.Structure):
                _fields_ = [('attributes', wintypes.DWORD), ('tag', wintypes.DWORD)]
            data = AttributeTag()
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            query = kernel.GetFileInformationByHandleEx
            query.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
            query.restype = wintypes.BOOL
            if not query(int(handle), 9, ctypes.byref(data), ctypes.sizeof(data)):
                raise ctypes.WinError(ctypes.get_last_error())
            name_surrogate = bool(data.tag & 0x20000000)
        if info[0] & win32con.FILE_ATTRIBUTE_DIRECTORY or name_surrogate:
            raise SafetyError('Keine reguläre Datei / Not a regular file: ' + str(path))
        fd = msvcrt.open_osfhandle(handle.Detach(), flags & (os.O_RDONLY | os.O_WRONLY | os.O_RDWR | os.O_APPEND) | os.O_BINARY)
        try:
            if flags & os.O_TRUNC:
                os.ftruncate(fd, 0)
            if flags & os.O_APPEND:
                os.lseek(fd, 0, os.SEEK_END)
        except BaseException:
            os.close(fd)
            raise
        return fd
    finally:
        handle.Close()


def properties(path):
    import mimetypes
    import shutil
    import win32security
    path = Path(path)
    info = path.lstat()
    owner = None
    try:
        descriptor = win32security.GetFileSecurity(str(path), win32security.OWNER_SECURITY_INFORMATION)
        name, domain, _ = win32security.LookupAccountSid(None, descriptor.GetSecurityDescriptorOwner())
        owner = domain + '\\' + name
    except (OSError, pywintypes.error):
        pass
    result = dict(name=path.name, path=str(path), uri=path.absolute().as_uri(), size=info.st_size,
                  directory=stat.S_ISDIR(info.st_mode), type='directory' if stat.S_ISDIR(info.st_mode) else 'file',
                  created=info.st_birthtime, modified=info.st_mtime, accessed=info.st_atime,
                  owner=owner, content_type=mimetypes.guess_type(path.name)[0],
                  link=os.readlink(path) if path.is_symlink() or path.is_junction() else None)
    try:
        disk = shutil.disk_usage(path)
        result.update(filesystem_size=disk.total, filesystem_free=disk.free)
    except OSError:
        pass
    return result


def locations():
    import win32api
    import win32file
    result = []
    for root in drive_roots():
        kind = win32file.GetDriveType(str(root))
        name = str(root)
        # Network enumeration must not wait for disconnected servers.
        if kind in (2, 3, 5):
            try:
                label = win32api.GetVolumeInformation(str(root))[0]
                if label:
                    name = f'{label} ({root.drive})'
            except (OSError, pywintypes.error) as error:
                if kind == 2 and getattr(error, 'winerror', None) in _REMOVED_MEDIA_ERRORS:
                    continue  # Safe-ejected USB controllers can retain an empty drive letter.
        result.append(dict(id=str(root), path=str(root), name=name, mounted=True,
                           eject=kind in (2, 5), unmount=kind == 4,
                           kind={2: 'USB', 4: 'Network', 5: 'DVD'}.get(kind, 'Drive')))
    import win32wnet
    try:
        enumeration = win32wnet.WNetOpenEnum(1, 1, 0, None)  # RESOURCE_CONNECTED, disk
        try:
            while True:
                resources = win32wnet.WNetEnumResource(enumeration, 0)
                if not resources:
                    break
                for resource in resources:
                    if resource.lpRemoteName and not resource.lpLocalName:
                        name = resource.lpRemoteName
                        result.append(dict(id=name, path=name, name=name, mounted=True,
                                           eject=False, unmount=True, kind='Network'))
        finally:
            enumeration.Close()
    except pywintypes.error:
        pass
    from .windows_devices import locations as portable_locations
    try:
        result.extend(portable_locations())
    except OSError:
        # An unavailable WPD service must not hide ordinary disks and shares.
        # Explicit connection attempts still report their device error.
        pass
    return result


def directory_size(path):
    root = Path(path)
    if root.is_symlink() or root.is_junction() or not root.is_dir():
        raise ValueError('Not a directory, or a link: ' + str(root))
    result = dict(bytes=0, files=0, directories=0, errors=0, complete=True)
    queue = [root]
    deadline = time.monotonic() + 10
    while queue:
        try:
            with os.scandir(queue.pop()) as stream:
                for entry in stream:
                    if time.monotonic() > deadline or result['files'] + result['directories'] >= 100000:
                        result['complete'] = False
                        return result
                    info = entry.stat(follow_symlinks=False)
                    if entry.is_dir(follow_symlinks=False) and not entry.is_junction():
                        result['directories'] += 1
                        queue.append(Path(entry.path))
                    else:
                        result['files'] += 1
                        result['bytes'] += info.st_size
        except OSError:
            result['errors'] += 1
    result['complete'] = not result['errors']
    return result


def network_path(uri):
    from urllib.parse import urlsplit, unquote
    parsed = urlsplit(uri)
    if parsed.scheme == 'smb':
        return '\\\\' + parsed.hostname + unquote(parsed.path).replace('/', '\\')
    if parsed.scheme in ('dav', 'davs'):
        host = parsed.hostname + ('@SSL' if parsed.scheme == 'davs' else '')
        if parsed.port:
            host += '@' + str(parsed.port)
        return '\\\\' + host + '\\DavWWWRoot' + unquote(parsed.path).replace('/', '\\')
    raise ValueError('SFTP / FTP / FTPS: bitte über Online-Orte verbinden / Connect using Online locations')


def dispatch(action, identifier):
    if action == 'ssh-fingerprints':
        from .windows_ssh import scan
        return scan(identifier['host'], identifier['port'])
    if action == 'mount' and identifier.startswith('wpd:'):
        from .windows_devices import mount
        mount(identifier)
        return locations()
    if action == 'unmount' and identifier.startswith('wpd:'):
        from .windows_devices import unmount
        unmount(identifier)
        return locations()
    if action == 'scan':
        result = []
        with os.scandir(identifier) as entries:
            for entry in entries:
                try:
                    info = entry.stat(follow_symlinks=False)
                    result.append(dict(name=entry.name, path=entry.path, directory=entry.is_dir(),
                                       size=info.st_size, modified=info.st_mtime,
                                       link=entry.is_symlink() or entry.is_junction()))
                except FileNotFoundError:
                    continue
                except PermissionError as error:
                    result.append(dict(name=entry.name, path=entry.path, directory=False, error=str(error)))
        return result
    if action == 'properties':
        return properties(identifier)
    if action == 'directory-size':
        return directory_size(identifier)
    if action == 'list':
        return locations()
    if action == 'open-with':
        import ctypes
        from ctypes import wintypes
        class OPENASINFO(ctypes.Structure):
            _fields_ = [('path', wintypes.LPCWSTR), ('class_name', wintypes.LPCWSTR), ('flags', wintypes.DWORD)]
        info = OPENASINFO(identifier, None, 4)  # OAIF_EXEC: no association change.
        result = ctypes.windll.shell32.SHOpenWithDialog(None, ctypes.byref(info))
        if result not in (0, -2147023673):  # HRESULT_FROM_WIN32(ERROR_CANCELLED)
            raise OSError('Open with failed: ' + hex(result & 0xffffffff))
        return dict(launched=result == 0)
    if action == 'connect':
        import win32netcon
        import win32wnet
        resource = win32wnet.NETRESOURCE()
        resource.dwType = win32netcon.RESOURCETYPE_DISK
        resource.lpRemoteName = network_path(identifier)
        win32wnet.WNetAddConnection3(0, resource, None, None, 8 | 16)  # INTERACTIVE | PROMPT
        rows = locations()
        rows.append(dict(id=resource.lpRemoteName, name=resource.lpRemoteName, path=resource.lpRemoteName,
                         mounted=True, eject=False, unmount=True, kind='Network'))
        return rows
    if action == 'unmount':
        import win32wnet
        win32wnet.WNetCancelConnection2(identifier.rstrip('\\') if len(identifier) <= 3 else identifier, 0, False)
        return locations()
    if action == 'eject':
        import pythoncom
        import win32api
        import win32com.client
        # Let the shell perform safe removal; never force-dismount a busy volume.
        pythoncom.CoInitialize()
        try:
            item = win32com.client.Dispatch('Shell.Application').Namespace(17).ParseName(identifier)
            if item is None:
                raise OSError('Drive unavailable')
            item.InvokeVerb('Eject')
            for _ in range(100):
                try:
                    win32api.GetVolumeInformation(identifier)
                except pywintypes.error as error:
                    if error.winerror in _REMOVED_MEDIA_ERRORS:
                        return locations()
                    if error.winerror not in (5, 32):
                        raise
                    # Windows can deny access while safe removal is in progress.
                    # Retry; permission/sharing errors alone are never success.
                time.sleep(.1)
            raise OSError('Laufwerk noch verbunden. Windows „Hardware sicher entfernen“ verwenden. / Drive still connected; use Windows Safely Remove Hardware.')
        finally:
            pythoncom.CoUninitialize()
    raise ValueError('Unsupported Windows integration: ' + action)


def invoke(action='list', identifier='', cancel=None):
    from .platform_support import helper_command
    command = helper_command('windows_bridge')
    request = json.dumps(dict(action=action, id=identifier))
    timeout = 15 if action in ('list', 'scan', 'properties', 'directory-size', 'ssh-fingerprints') else None
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, encoding='utf-8') as process:
        start, first = time.monotonic(), True
        try:
            while True:
                if cancel is not None and cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                if timeout and time.monotonic() - start > timeout:
                    raise subprocess.TimeoutExpired(command, timeout)
                try:
                    output, errors = process.communicate(request if first else None, timeout=.1)
                    break
                except subprocess.TimeoutExpired:
                    first = False
            value = json.loads(output)
            if process.returncode or 'error' in value:
                raise RuntimeError(value.get('error', errors))
            return value['locations']
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


@native_errors
def keyring(state, identifier, action, secret=None):
    import hashlib
    import win32cred
    # A control credential is created before mount and read after mount. Its
    # identity must not depend on Windows resolving the mounted volume.
    namespace = Path(os.path.abspath(state))
    # Resolve only the local parent: this also preserves existing credentials
    # when Windows canonicalizes a short directory name or its casing.
    namespace = namespace.parent.resolve() / namespace.name
    target = 'OpenCommander/' + hashlib.sha256(os.fsencode(namespace)).hexdigest() + '/' + identifier
    if action == 'store':
        win32cred.CredWrite(dict(Type=win32cred.CRED_TYPE_GENERIC, TargetName=target,
                                UserName='OpenCommander', CredentialBlob=secret,
                                Persist=win32cred.CRED_PERSIST_LOCAL_MACHINE), 0)
        return True
    try:
        if action == 'lookup':
            return win32cred.CredRead(target, win32cred.CRED_TYPE_GENERIC)['CredentialBlob'].decode('utf-16-le')
        if action == 'clear':
            win32cred.CredDelete(target, win32cred.CRED_TYPE_GENERIC)
            return True
    except (OSError, pywintypes.error) as error:
        if error.winerror == 1168:
            return None
        raise
    raise ValueError('Unknown credential operation')


@native_errors
def set_times(path, info):
    import win32file
    from ctypes import wintypes
    handle = win32file.CreateFile(str(path), 0x100, 7, None, 3, 0x02200000, None)
    try:
        def stamp(ns):
            ticks = ns // 100 + 116444736000000000
            return wintypes.FILETIME(ticks & 0xffffffff, ticks >> 32)
        access, modified = stamp(info.st_atime_ns), stamp(info.st_mtime_ns)
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        callback = kernel.SetFileTime
        callback.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        callback.restype = wintypes.BOOL
        if not callback(int(handle), None, ctypes.byref(access), ctypes.byref(modified)):
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        handle.Close()


def protect_private_directory(path):
    """Windows chmod does not restrict readers; give private backend data a DACL."""
    import win32api
    import win32con
    import win32security
    import ntsecuritycon
    token = win32security.OpenProcessToken(win32api.GetCurrentProcess(), win32con.TOKEN_QUERY)
    try:
        user = win32security.GetTokenInformation(token, win32security.TokenUser)[0]
    finally:
        token.Close()
    system = win32security.CreateWellKnownSid(win32security.WinLocalSystemSid, None)
    acl = win32security.ACL()
    for sid in (user, system):
        acl.AddAccessAllowedAceEx(win32security.ACL_REVISION_DS,
                                 win32con.OBJECT_INHERIT_ACE | win32con.CONTAINER_INHERIT_ACE,
                                 ntsecuritycon.FILE_ALL_ACCESS, sid)
    win32security.SetNamedSecurityInfo(str(path), win32security.SE_FILE_OBJECT,
        win32security.DACL_SECURITY_INFORMATION | win32security.PROTECTED_DACL_SECURITY_INFORMATION,
        None, None, acl, None)


def private_key_readers(path):
    """Only this user, SYSTEM and local administrators may read a private key."""
    import win32api
    import win32con
    import win32security
    import ntsecuritycon
    token = win32security.OpenProcessToken(win32api.GetCurrentProcess(), win32con.TOKEN_QUERY)
    try:
        user = win32security.GetTokenInformation(token, win32security.TokenUser)[0]
        session_readers = {str(sid) for sid, flags in
                           win32security.GetTokenInformation(token, win32security.TokenGroups)
                           if flags & 0xC0000000 == 0xC0000000}  # SE_GROUP_LOGON_ID
    finally:
        token.Close()
    allowed = {str(user), str(win32security.CreateWellKnownSid(win32security.WinLocalSystemSid, None)),
               str(win32security.CreateWellKnownSid(win32security.WinBuiltinAdministratorsSid, None))}
    allowed.update(session_readers)
    acl = win32security.GetNamedSecurityInfo(str(path), win32security.SE_FILE_OBJECT,
                                            win32security.DACL_SECURITY_INFORMATION).GetSecurityDescriptorDacl()
    if acl is None:
        return False
    for index in range(acl.GetAceCount()):
        header, mask, sid = acl.GetAce(index)
        if header[0] == win32security.ACCESS_ALLOWED_ACE_TYPE and mask & ntsecuritycon.FILE_READ_DATA:
            identity = str(sid)
            if identity not in allowed:
                return False
    return True
