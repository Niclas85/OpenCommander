"""Standalone entry point for cancellable Windows filesystem requests."""
import json
from pathlib import Path
import sys


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from opencommander.windows_native import dispatch
    try:
        request = json.load(sys.stdin)
        print(json.dumps({'locations': dispatch(request['action'], request['id'])}))
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
