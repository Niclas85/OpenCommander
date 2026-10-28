"""Assemble the static public site and reuse the existing desktop handbook."""
import argparse
import shutil
from pathlib import Path
from pages import write_pages

SOURCE = Path(__file__).resolve().parent
REPO = SOURCE.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=SOURCE / 'build')
    args = parser.parse_args()
    output = args.output.resolve()
    if output == SOURCE or output == REPO:
        raise SystemExit('Use a separate output directory.')
    output.mkdir(parents=True, exist_ok=True)
    for name in ('index.html', 'style.css', 'site.js', 'privacy.html', 'impressum.html',
                 '404.html', 'robots.txt', 'sitemap.xml', 'handbook-bridge.js', 'platform.mjs', 'guide.css'):
        shutil.copy2(SOURCE / name, output / name)
    for name in ('assets', 'docs'):
        shutil.copytree(SOURCE / name, output / name, dirs_exist_ok=True)
    manual = output / 'docs/handbuch'
    shutil.copytree(REPO / 'linux/docs/handbuch', manual, dirs_exist_ok=True)
    index = (manual / 'index.html').read_text(encoding='utf-8')
    index = index.replace('</head>', '<link rel="canonical" href="https://opencommander.top/docs/handbuch/">'
                          '<script src="/handbook-bridge.js" defer></script></head>')
    index = index.replace('<span class="version">LINUX 0.3.21</span>',
                          '<a href="/docs/">Projekt &amp; Windows-Hinweise</a><span class="version">LINUX 0.3.21</span>')
    (manual / 'index.html').write_text(index, encoding='utf-8')
    write_pages(output)
    print(f'Static site built: {output}')


if __name__ == '__main__':
    main()
