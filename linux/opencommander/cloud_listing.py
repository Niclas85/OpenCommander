"""Bounded, read-only cloud queries with coalescing and an explicit stale cache."""
from collections import OrderedDict
import json
import subprocess
import threading
import time
import weakref

from .desktop import host_environment


class CloudError(RuntimeError):
    def __init__(self, message, retryable=False):
        super().__init__(message)
        self.retryable = retryable


class CloudRows(list):
    def __init__(self, rows, warning=''):
        super().__init__(rows)
        self.warning = warning


def provider_error(stderr):
    # Only classify stderr: never display provider output or credential fragments.
    value = stderr.lower()
    if any(term in value for term in ('invalid_grant', 'unauthorized', '401', 'token expired',
                                      "couldn't decrypt password", 'invalid credentials', 'invalid session')):
        return CloudError('Cloud-Anmeldung abgelaufen oder ungültig. Unter Einstellungen → Online-Orte erneut anmelden. / Sign in again')
    if any(term in value for term in ('ratelimitexceeded', 'rate_limit_exceeded', 'userratelimitexceeded',
                                      'quota exceeded', '429', 'too many requests')):
        return CloudError('Cloud-Dienst begrenzt gerade die Anfragen. Bitte kurz warten und erneut laden. / Provider rate limit; retry shortly', True)
    if any(term in value for term in ('timeout', 'timed out', 'temporary failure', 'connection reset',
                                      'connection refused', 'network is unreachable', 'no such host',
                                      'server error', '503 service', '502 bad gateway', '504 gateway', '500 internal')):
        return CloudError('Cloud-Verbindung vorübergehend unterbrochen. Erneut laden. / Temporary cloud connection error', True)
    return CloudError('Cloud-Ordner nicht erreichbar. Verbindung und Zugriffsrechte prüfen. / Cloud folder unavailable')


def query(command, cancel, deadline):
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, env=host_environment()) as process:
        try:
            while True:
                if cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                if time.monotonic() >= deadline:
                    raise CloudError('Cloud antwortet nicht rechtzeitig. Erneut laden oder Verbindung prüfen. / Cloud request timed out', True)
                try:
                    output, error = process.communicate(timeout=min(.1, max(.001, deadline - time.monotonic())))
                    break
                except subprocess.TimeoutExpired:
                    continue
            if process.returncode:
                raise provider_error(error)
            try:
                rows = json.loads(output)
                if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
                    raise ValueError('Invalid listing')
            except (ValueError, TypeError):
                raise CloudError('Ungültige Antwort vom Cloud-Dienst. Erneut laden. / Invalid cloud response') from None
            return rows
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


class CloudListings:
    def __init__(self):
        self.lock = threading.Lock()
        self.locks = weakref.WeakValueDictionary()
        self.cache = OrderedDict()
        self.cooldowns = {}

    def read(self, key, command, cancel, timeout=30):
        requested = time.monotonic()
        deadline = requested + timeout
        with self.lock:
            serial = self.locks.setdefault(key, threading.Lock())
        while not serial.acquire(timeout=.05):
            if cancel.is_set():
                raise RuntimeError('Abgebrochen / Cancelled')
            if time.monotonic() >= deadline:
                raise CloudError('Cloud-Abfrage wartet zu lange. Erneut laden. / Cloud query timed out', True)
        try:
            if cancel.is_set():
                raise RuntimeError('Abgebrochen / Cancelled')
            now = time.monotonic()
            with self.lock:
                cached = self.cache.get(key)
                cooldown = self.cooldowns.get(key)
            # Repeated pane requests share one query; never present old data silently.
            if cached and cached[0] >= requested and not cooldown:
                return CloudRows(cached[1])
            if cooldown and now < cooldown[0]:
                return self.stale(key, cached, cooldown[1])
            for attempt in range(3):
                try:
                    rows = query(command, cancel, deadline)
                except CloudError as error:
                    if not error.retryable:
                        with self.lock:
                            self.cache.pop(key, None)
                            self.cooldowns.pop(key, None)
                        raise
                    if cached and time.monotonic() - cached[0] < 300:
                        with self.lock:
                            self.cooldowns[key] = (time.monotonic() + 10, error)
                        return self.stale(key, cached, error)
                    remaining = deadline - time.monotonic()
                    if attempt == 2 or remaining <= 2 ** (attempt + 1):
                        with self.lock:
                            self.cooldowns[key] = (time.monotonic() + 10, error)
                        raise
                    if cancel.wait(min(2 ** (attempt + 1), remaining)):
                        raise RuntimeError('Abgebrochen / Cancelled')
                else:
                    with self.lock:
                        self.cache[key] = (time.monotonic(), rows)
                        self.cache.move_to_end(key)
                        self.cooldowns.pop(key, None)
                        while len(self.cache) > 32:
                            old, _ = self.cache.popitem(last=False)
                            self.cooldowns.pop(old, None)
                    return CloudRows(rows)
        finally:
            serial.release()

    def stale(self, key, cached, error):
        if cached and time.monotonic() - cached[0] < 300:
            age = int(time.monotonic() - cached[0])
            return CloudRows(cached[1], f'Gespeicherte Dateiliste · {age} s alt · {error} / Cached listing')
        raise error
