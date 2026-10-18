"""Authenticated loopback filesystem protocol for a single WPD device.

The serial HTTP server runs in the device's COM apartment. rclone/WinFsp exposes
it as an ordinary mount, so search, preview, archives and recoverable operations
use the existing file engine. This server is never bound to a network interface.
"""
from email.utils import formatdate
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import hmac
from pathlib import Path
import re
import shutil
import tempfile
from urllib.parse import quote, unquote, urlsplit
import xml.etree.ElementTree as ET


def component(name):
    """Expose Windows-illegal device names without silently hiding their files."""
    if not name or name in ('.', '..'):
        raise OSError('Invalid device filename')
    result = ''.join(f'%{ord(c):02X}' if c in '%<>:"/\\|?*' or ord(c) < 32 else c for c in name)
    while result.endswith((' ', '.')):
        result = result[:-1] + f'%{ord(result[-1]):02X}'
    from pathlib import PureWindowsPath
    if PureWindowsPath(result).is_reserved():
        result = f'%{ord(result[0]):02X}' + result[1:]
    return result


class Namespace:
    def __init__(self, device):
        self.device = device

    def children(self, parent):
        rows = [dict(row, display=component(row['name'])) for row in self.device.children(parent['id'])]
        groups = {}
        for row in rows:
            groups.setdefault(row['display'].casefold(), []).append(row)
        for group in groups.values():
            if len(group) > 1:
                for row in group:
                    row['display'] += '~' + hashlib.sha256(row['id'].encode()).hexdigest()[:16]
        if len({row['display'].casefold() for row in rows}) != len(rows):
            raise OSError('Ambiguous portable device names')
        return rows

    def resolve(self, parts):
        current = dict(id='DEVICE', name='', display='', directory=True, storage=True, size=0, modified=0)
        for part in parts:
            if not current['directory']:
                raise NotADirectoryError(part)
            matches = [row for row in self.children(current) if row['display'].casefold() == part.casefold()]
            if not matches:
                raise FileNotFoundError(part)
            if len(matches) != 1:
                raise OSError('Ambiguous portable device path')
            current = matches[0]
        return current

    def destination(self, parts):
        if not parts:
            raise PermissionError('Device root is read-only')
        parent = self.resolve(parts[:-1])
        if not parent['directory'] or parent['id'] == 'DEVICE':
            raise PermissionError('Choose a folder inside device storage')
        from .platform_support import validate_component
        validate_component(parts[-1])
        if any(row['display'].casefold() == parts[-1].casefold() for row in self.children(parent)):
            raise FileExistsError(parts[-1])
        return parent, parts[-1]

    def mkdir(self, parts):
        parent, name = self.destination(parts)
        self.device.mkdir(parent['id'], name)

    def create(self, parts, stream, size):
        parent, name = self.destination(parts)
        self.device.create(parent['id'], name, stream, size)

    def delete(self, parts):
        row = self.resolve(parts)
        if row['storage'] or not parts:
            raise PermissionError('Device storage cannot be removed')
        if row['directory'] and self.children(row):
            raise OSError('Directory is not empty')
        self.device.delete(row['id'])

    def move(self, source, target):
        row = self.resolve(source)
        if row['storage'] or not source:
            raise PermissionError('Device storage cannot be moved')
        if source == target:
            return
        if len(target) > len(source) and [p.casefold() for p in target[:len(source)]] == [p.casefold() for p in source]:
            raise PermissionError('A folder cannot be moved into itself')
        parent, name = self.destination(target)
        original_parent = self.resolve(source[:-1])
        # Preserve the real device name when moving a Windows-safe alias.
        name = row['name'] if target[-1] == source[-1] else name
        try:
            if original_parent['id'] != parent['id']:
                self.device.move(row['id'], parent['id'])
            if row['name'] != name:
                self.device.rename(row['id'], name)
            actual = self.resolve(target)
            if actual['id'] != row['id']:
                raise OSError('Device move could not be verified')
        except OSError as failure:
            # A compound device move/rename is not atomic. Restore the original
            # location after a partial failure when it is still unoccupied.
            # Never delete data or replace an external writer's object to do so.
            try:
                current = self.device.info(row['id'])
                siblings = self.device.children(original_parent['id'])
                if any(item['id'] != row['id'] and item['name'].casefold() in
                       {row['name'].casefold(), current['name'].casefold()} for item in siblings):
                    raise OSError('Original location is occupied')
                if current['parent'] != original_parent['id']:
                    self.device.move(row['id'], original_parent['id'])
                if current['name'] != row['name']:
                    self.device.rename(row['id'], row['name'])
            except OSError as recovery:
                raise OSError('Device action failed; complete object retained on device. '
                              'Reconnect and inspect the source and destination folders before retrying.') from recovery
            raise failure


def path_parts(value):
    parsed = urlsplit(value)
    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
        raise ValueError('Only local device paths are accepted')
    if not parsed.path.startswith('/'):
        raise ValueError('Absolute path required')
    decoded = unquote(parsed.path, encoding='utf-8', errors='strict')
    if '\\' in decoded or '\0' in decoded or any(ord(c) < 32 for c in decoded):
        raise ValueError('Invalid device path')
    parts = decoded.strip('/').split('/') if decoded.strip('/') else []
    if any(part in ('', '.', '..') for part in parts):
        raise ValueError('Invalid device path')
    return parts


class DeviceServer(HTTPServer):
    allow_reuse_address = False

    def __init__(self, device, password, cache):
        self.namespace, self.password, self.cache = Namespace(device), password, Path(cache)
        self.stopping = False
        super().__init__(('127.0.0.1', 0), DeviceHandler)
        self.timeout = .5


class DeviceHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'OpenCommander-Device'

    def log_message(self, *_):
        pass  # Never log private device paths or Authorization headers.

    def handle_one_request(self):
        self.connection.settimeout(30)
        try:
            super().handle_one_request()
        except (TimeoutError, ConnectionError):
            self.close_connection = True

    def reply(self, status, body=b'', headers=None):
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def authorized(self):
        expected = 'Basic ' + base64.b64encode(('OpenCommander:' + self.server.password).encode()).decode()
        host = self.headers.get('Host', '')
        if (host != f'127.0.0.1:{self.server.server_port}' or
                not hmac.compare_digest(self.headers.get('Authorization', ''), expected)):
            self.close_connection = True
            self.reply(401, headers={'WWW-Authenticate': 'Basic realm="OpenCommander device"'})
            return False
        # Browser requests cannot mutate a device, even with guessed credentials.
        if self.headers.get('Origin') or self.headers.get('Sec-Fetch-Site'):
            self.close_connection = True
            self.reply(403)
            return False
        return True

    def execute(self, callback):
        # A serial COM apartment cannot leave an idle keep-alive client blocking
        # all other filesystem requests or the mount-readiness check.
        self.close_connection = True
        if not self.authorized():
            return
        try:
            callback()
        except FileNotFoundError:
            self.close_connection = True
            self.reply(404)
        except FileExistsError:
            self.close_connection = True
            self.reply(412)
        except PermissionError:
            self.close_connection = True
            self.reply(403)
        except (ValueError, UnicodeError):
            self.close_connection = True
            self.reply(400)
        except (OSError, EOFError):
            self.close_connection = True
            self.reply(409)

    def parts(self):
        return path_parts(self.path)

    def read_body(self, target):
        """Bounded streaming decoder; WPD needs the final size before creation."""
        transfer = self.headers.get('Transfer-Encoding', '').lower()
        length = self.headers.get('Content-Length')
        if transfer and (transfer != 'chunked' or length is not None):
            raise ValueError('Unsupported transfer framing')
        if not transfer and (length is None or not re.fullmatch(r'[0-9]+', length)):
            raise ValueError('Content-Length required')
        total = 0

        def read_exact(amount):
            nonlocal total
            while amount:
                block = self.rfile.read(min(amount, 1024 * 1024))
                if not block:
                    raise EOFError('Incomplete request')
                if shutil.disk_usage(self.server.cache).free < len(block) + 16 * 1024 * 1024:
                    raise OSError('Not enough upload staging space')
                target.write(block)
                amount -= len(block)
                total += len(block)

        if transfer:
            while True:
                line = self.rfile.readline(128)
                if not re.fullmatch(rb'[0-9a-fA-F]+\r\n', line):
                    raise ValueError('Invalid upload chunk')
                size = int(line, 16)
                if not size:
                    if self.rfile.readline(8192) != b'\r\n':
                        raise ValueError('Upload trailers are not accepted')
                    break
                read_exact(size)
                if self.rfile.read(2) != b'\r\n':
                    raise ValueError('Invalid upload framing')
        else:
            read_exact(int(length))
        target.seek(0)
        return total

    def do_OPTIONS(self):
        self.execute(lambda: self.reply(200, headers={'DAV': '1', 'Allow':
            'OPTIONS, PROPFIND, GET, HEAD, PUT, MKCOL, MOVE, DELETE, PROPPATCH'}))

    def do_PROPFIND(self):
        def run():
            # Do not leave XML request bodies in a persistent connection.
            self.close_connection = True
            depth = self.headers.get('Depth', '1')
            if depth not in ('0', '1'):
                raise PermissionError('Recursive PROPFIND not supported')
            parts = self.parts()
            row = self.server.namespace.resolve(parts)
            rows = [(parts, row)]
            if row['directory'] and depth == '1':
                rows += [(parts + [child['display']], child) for child in self.server.namespace.children(row)]
            ET.register_namespace('d', 'DAV:')
            root = ET.Element('{DAV:}multistatus')
            for path, item in rows:
                response = ET.SubElement(root, '{DAV:}response')
                ET.SubElement(response, '{DAV:}href').text = '/' + '/'.join(quote(p, safe='') for p in path) + ('/' if item['directory'] and path else '')
                propstat = ET.SubElement(response, '{DAV:}propstat')
                props = ET.SubElement(propstat, '{DAV:}prop')
                ET.SubElement(props, '{DAV:}displayname').text = item['display']
                kind = ET.SubElement(props, '{DAV:}resourcetype')
                if item['directory']:
                    ET.SubElement(kind, '{DAV:}collection')
                else:
                    ET.SubElement(props, '{DAV:}getcontentlength').text = str(item['size'])
                    ET.SubElement(props, '{DAV:}getcontenttype').text = 'application/octet-stream'
                ET.SubElement(props, '{DAV:}getlastmodified').text = formatdate(item['modified'], usegmt=True)
                ET.SubElement(propstat, '{DAV:}status').text = 'HTTP/1.1 200 OK'
            self.reply(207, ET.tostring(root, encoding='utf-8', xml_declaration=True),
                       {'Content-Type': 'application/xml; charset=utf-8', 'Connection': 'close'})
        self.execute(run)

    def do_GET(self):
        def run():
            row = self.server.namespace.resolve(self.parts())
            if row['directory']:
                raise PermissionError('Not a file')
            start, end, status = 0, row['size'], 200
            ranges = self.headers.get('Range')
            if ranges:
                match = re.fullmatch(r'bytes=([0-9]+)-([0-9]*)', ranges)
                if not match:
                    self.reply(416)
                    return
                start = int(match[1])
                end = min(end, int(match[2]) + 1) if match[2] else end
                if start >= end:
                    self.reply(416)
                    return
                status = 206
            with self.server.namespace.device.read(row['id']) as stream:
                # Some cameras do not implement IStream::Seek. Skip bounded blocks.
                skip = start
                while skip:
                    block = stream.read(min(skip, 1024 * 1024))
                    if not block:
                        raise EOFError('Device returned an incomplete file')
                    skip -= len(block)
                self.send_response(status)
                self.send_header('Content-Length', str(end - start))
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Connection', 'close')
                self.send_header('Last-Modified', formatdate(row['modified'], usegmt=True))
                if status == 206:
                    self.send_header('Content-Range', f'bytes {start}-{end - 1}/{row["size"]}')
                self.end_headers()
                if self.command != 'HEAD':
                    left = end - start
                    try:
                        while left:
                            block = stream.read(min(left, 1024 * 1024))
                            if not block:
                                raise EOFError('Device disconnected or returned an incomplete file')
                            self.wfile.write(block)
                            left -= len(block)
                    except (OSError, EOFError):
                        # Headers have been sent: terminate, never send a second
                        # response which could look like successful file bytes.
                        self.close_connection = True
        self.execute(run)

    do_HEAD = do_GET

    def do_PUT(self):
        def run():
            parts = self.parts()
            self.server.namespace.destination(parts)  # Reject conflicts before reading an upload.
            with tempfile.TemporaryFile(dir=self.server.cache) as stream:
                size = self.read_body(stream)
                self.server.namespace.create(parts, stream, size)  # Recheck after upload.
            self.reply(201)
        self.execute(run)

    def do_MKCOL(self):
        def run():
            if self.headers.get('Transfer-Encoding') or self.headers.get('Content-Length', '0') != '0':
                raise ValueError('MKCOL body not supported')
            self.server.namespace.mkdir(self.parts())
            self.reply(201)
        self.execute(run)

    def do_MOVE(self):
        def run():
            destination = urlsplit(self.headers.get('Destination', ''))
            if (destination.scheme != 'http' or destination.netloc != f'127.0.0.1:{self.server.server_port}' or
                    destination.query or destination.fragment):
                raise ValueError('MOVE destination must stay on this device')
            self.server.namespace.move(self.parts(), path_parts(destination.path))
            self.reply(201)
        self.execute(run)

    def do_DELETE(self):
        def run():
            self.server.namespace.delete(self.parts())
            self.reply(204)
        self.execute(run)

    def do_PROPPATCH(self):
        # WPD timestamp mutation is device-specific; never pretend it succeeded.
        self.execute(lambda: (setattr(self, 'close_connection', True), self.reply(403)))

    def do_POST(self):
        def run():
            if self.path != '/.opencommander-control/quit':
                raise PermissionError('Unsupported control request')
            self.server.stopping = True
            self.reply(200)
        self.execute(run)
