"""Windows entry point, also dispatching isolated I/O helpers in frozen builds."""
from pathlib import Path
import runpy
import sys

if not getattr(sys, 'frozen', False):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'linux'))

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--internal-helper':
        if sys.argv[2] not in ('windows_bridge', 'media_fetch', 'device_bridge'):
            raise SystemExit('Unknown helper')
        runpy.run_module('opencommander.' + sys.argv[2], run_name='__main__')
    else:
        try:
            from opencommander.main import main
            raise SystemExit(main())
        except Exception:
            import json
            import os
            import traceback
            failure = traceback.format_exc()
            if '--smoke-report' in sys.argv:
                report = Path(sys.argv[sys.argv.index('--smoke-report') + 1])
                report.write_text(json.dumps(dict(ok=False, error=failure)), encoding='utf-8')
            else:
                folder = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'OpenCommander'
                folder.mkdir(parents=True, exist_ok=True)
                (folder / 'startup-error.log').write_text(failure, encoding='utf-8')
                if sys.stderr is not None:
                    sys.stderr.write(failure)
            raise SystemExit(1)
