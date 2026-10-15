# OpenCommander website

Source for [opencommander.top](https://opencommander.top): static HTML, CSS and JavaScript, with no framework, external fonts or analytics.

## Build and preview

Run from the repository root on `codex/linux-desktop` (the desktop handbook is not yet on `main`):

```powershell
python website/build.py
python website/serve.py
```

Open http://127.0.0.1:8766. The generated `website/build/` directory is ignored by Git. Use `--output PATH` to assemble into another directory.

The build copies the original `linux/docs/handbuch` and adds a link to the platform guide and a search-query bridge. It does not modify the handbook source. The local server supports clean URLs such as `/privacy`, as does the public host.

## Content

- `index.html`: platform overview, verified store/release links, screenshots and FAQs.
- `docs/index.html`: documentation portal, platform instructions and differences.
- `privacy.html` and `impressum.html`: existing public policy and publisher details.
- `assets/`: actual desktop screenshots, project icon and GitHub banner.
- `site.js`: accessible platform/screenshot tabs and mobile navigation.

Keep platform availability accurate: Android and iOS have store listings; macOS has an Apple Silicon preview; Windows and Linux currently link to documentation and source. Do not add download buttons until corresponding public release artifacts exist.

## Publication

The existing public Sites project is `appgprj_6acfd14405848191826b2e20926fe64d`. Its hosting manifest declares `dist` as the static directory. Assemble there using `build.py --output`, package with the official Sites source workflow, save the exact pushed source version, and deploy it to the existing project. Keep the public audience and `opencommander.top` domain unchanged. Preserve `/privacy` and `/privacy.html` for OAuth and store references.

Credentials belong only in the publishing tool's in-memory input, never in this repository or build output.
