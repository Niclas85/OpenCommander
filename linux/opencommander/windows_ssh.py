"""Unauthenticated SSH identity discovery, isolated in the Windows helper."""
import base64
import hashlib
import logging
import re
import socket
import time


def scan(host, port):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.:-]*', host) or not 1 <= int(port) <= 65535:
        raise ValueError('Ungültiger SSH-Server / Invalid SSH host')
    import paramiko
    # Windows ssh-keyscan can advertise a KEX it cannot execute (Win32-OpenSSH
    # #2140). Use the bundled transport for discovery only; never authenticate,
    # execute commands, or update known_hosts here. Trust remains a separate step.
    logger = logging.getLogger('opencommander.ssh-scan')
    if not logger.handlers:
        logger.addHandler(logging.NullHandler())
    logger.propagate = False
    deadline = time.monotonic() + 12
    keys, fingerprints = [], []
    target = host if int(port) == 22 else f'[{host}]:{port}'
    groups = (('ssh-ed25519',), ('ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521'),
              ('rsa-sha2-512', 'rsa-sha2-256'))
    for group in groups:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        transport = None
        try:
            with socket.create_connection((host, int(port)), timeout=min(3, remaining)) as connection:
                transport = paramiko.Transport(connection)
                transport.set_log_channel(logger.name)
                transport.banner_timeout = min(3, remaining)
                transport.handshake_timeout = min(3, remaining)
                options = transport.get_security_options()
                options.key_types = tuple(kind for kind in group if kind in options.key_types)
                if not options.key_types:
                    continue
                transport.start_client(timeout=min(3, remaining))
                key = transport.get_remote_server_key()
                encoded = key.get_base64()
                keys.append(f'{target} {key.get_name()} {encoded}\n')
                digest = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')
                fingerprints.append(f'{key.get_bits()} SHA256:{digest} {target} ({key.get_name()})\n')
        except paramiko.ssh_exception.IncompatiblePeer:
            continue  # This server may not offer every host-key type.
        except (OSError, EOFError, paramiko.SSHException) as error:
            if keys:
                break  # Preserve already received keys; trust is still checked separately.
            endpoint = f'{host}:{port}'
            if isinstance(error, (TimeoutError, socket.timeout)):
                detail = 'Zeitüberschreitung. Serverstatus, Port und Firewall prüfen. / Timed out; check server, port and firewall.'
            elif isinstance(error, ConnectionRefusedError):
                detail = 'Verbindung abgelehnt. SSH-Dienst und Port prüfen. / Connection refused; check SSH service and port.'
            elif isinstance(error, socket.gaierror):
                detail = 'Servername nicht auflösbar. / Host name could not be resolved.'
            elif isinstance(error, OSError):
                detail = 'Server nicht erreichbar. Netzwerk und Serverstatus prüfen. / Server unreachable; check network and server status.'
            else:
                detail = 'SSH-Schlüsselaustausch fehlgeschlagen. SSH-Dienst, Port und unterstützte Algorithmen prüfen. / SSH handshake failed; check service, port and algorithms.'
            raise RuntimeError(f'SSH {endpoint}: {detail}\nNoch keine Passwortanmeldung versucht. / Password authentication has not started.') from None
        finally:
            if transport is not None:
                transport.close()
    if not keys:
        raise RuntimeError(f'SSH {host}:{port}: Kein gemeinsamer Hostschlüssel-/Schlüsselaustausch-Algorithmus. '
                           'SSH-Dienst und Algorithmen prüfen. / No compatible SSH host-key/key-exchange algorithm. '
                           'Password authentication has not started.')
    return dict(keys=''.join(keys), fingerprints=''.join(fingerprints))
