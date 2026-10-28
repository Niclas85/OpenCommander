"""Local preview with the same clean HTML URLs as the public static host."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        request = urlsplit(self.path)
        candidate = Path(self.translate_path(request.path))
        if not candidate.exists() and not candidate.suffix and candidate.with_suffix('.html').is_file():
            self.path = urlunsplit(('', '', request.path + '.html', request.query, ''))
        super().do_GET()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, default=Path(__file__).parent / 'build')
    parser.add_argument('--port', type=int, default=8766)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=str(args.directory.resolve())))
    print(f'Preview: http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()
