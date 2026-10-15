"""Console-subsystem helper: pipes work even though the GUI has no console."""
from pathlib import Path
import runpy
import sys

if not getattr(sys, 'frozen', False):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'linux'))

if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('windows_bridge', 'media_fetch', 'device_bridge'):
        raise SystemExit('Unknown helper')
    runpy.run_module('opencommander.' + sys.argv[1], run_name='__main__')
