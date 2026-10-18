"""Frozen-helper entry point for the native portable-device mount."""
import json
from pathlib import Path
import sys


def main():
    if not getattr(sys, 'frozen', False):
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from opencommander.windows_devices import serve
    try:
        request = json.loads(sys.stdin.readline())
        serve(request)
        return 0
    except Exception as error:
        print(json.dumps(dict(error=str(error))), flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
