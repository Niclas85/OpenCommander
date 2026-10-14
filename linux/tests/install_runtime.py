"""Install the checksum-verified, pinned backend used by desktop CI tests."""
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from opencommander import rclone_runtime

fetch = rclone_runtime.fetch
def pinned_fetch(url, cancel, destination=None):
    if url.endswith('/version.txt'):
        return b'rclone v1.75.2\n'
    return fetch(url, cancel, destination)
rclone_runtime.fetch = pinned_fetch
print(Path(rclone_runtime.install(threading.Event())).parent)
