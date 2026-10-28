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
- `pages.py`: content and renderer for `/android/`, `/iphone/`, `/windows/`, `/linux/`, `/macos/` and `/cloud/`. `build.py` generates their static HTML; do not edit generated pages in `build/`.
- `guide.css`: responsive layouts for the platform and cloud guides.
- `docs/index.html`: documentation portal, platform instructions and differences.
- `privacy.html` and `impressum.html`: existing public policy and publisher details.
- `assets/`: actual desktop screenshots, project icon and GitHub banner.
- `site.js`: accessible platform/screenshot tabs and mobile navigation.
- `platform.mjs`: browser-local platform detection. Client Hints have a user-agent fallback; touch-enabled iPad desktop browsers are handled before macOS. Explicit platform links and manual selection take precedence. No detection data is stored or sent to a server.

Keep platform availability accurate: Android and iOS have store listings; macOS has an Apple Silicon preview; Windows and Linux currently link to documentation and source. Do not add download buttons until corresponding public release artifacts exist.

Platform pages include `SoftwareApplication` and `BreadcrumbList` JSON-LD. The homepage identifies the website and its platform collection; the cloud guide is a `WebPage`. Prices are included only for the verified free mobile store listings. Do not invent ratings, reviews, release downloads or feature parity. Update visible copy and structured data together. All eleven public content URLs are in `sitemap.xml`; the existing Search Console submission continues to use the same sitemap address.

## Publication

The existing public Sites project is `appgprj_6acfd14405848191826b2e20926fe64d`. Its hosting manifest declares `dist` as the static directory. Assemble there using `build.py --output`, package with the official Sites source workflow, save the exact pushed source version, and deploy it to the existing project. Keep the public audience and `opencommander.top` domain unchanged. Preserve `/privacy` and `/privacy.html` for OAuth and store references.

Credentials belong only in the publishing tool's in-memory input, never in this repository or build output.
