# Website verification — 15 October 2026

## Cloud presentation and automatic platform selection

- Added a prominent four-provider section and hero copy for OneDrive, Google Drive, Dropbox and iCloud, with accurate Windows/Linux scope and the existing Google verification notice.
- Checked 18 browser-input cases: Windows (including touch PCs), macOS, Linux, Android phones/tablets, iPhone, iPad mobile/desktop, reduced hints and unknown/unsupported systems.
- In the Windows browser, Windows is preselected. Manual Linux selection survives ordinary section navigation; an explicit `#ios` link overrides detection.
- Checked the provider section at desktop and 390-pixel mobile viewport sizes; all four icons load and mobile layout has no horizontal overflow.
- Detection uses browser-local hints without persistence or network requests; module loading also checked on the documentation and policy pages.

## Initial website publication

Published as version 3 of the existing public Sites project, with the existing domain and audience preserved.

- Public domain: https://opencommander.top
- Sites deployment URL: https://opencommander-desktop.nikki719610.chatgpt.site
- Sites source commit: `9fc0d8ba3512be20f792633b50cd7046618248e1`
- Main-branch GitHub homepage commit: `4eda92a`

## Checks completed

- Desktop and 390-pixel mobile rendering visually inspected in the browser.
- All five platform tabs, keyboard tab navigation, three screenshot tabs and FAQ disclosure checked.
- Mobile navigation opens and closes after choosing a destination.
- Homepage search for `SFTP` opens the original handbook, retains the query, finds two chapters and navigates to the server chapter.
- Documentation portal and clean `/privacy` and `/impressum` URLs open successfully.
- All 175 local HTML links, assets and fragment references resolve across six generated HTML pages.
- No browser JavaScript errors observed during the tested paths.
- Live domain shows the new five-platform homepage after deployment.
- Public default-branch GitHub README and About text verified; both README images load.
- Android and iOS links use the existing public store listings. macOS points to the existing Apple Silicon preview. Windows and Linux accurately link to build instructions rather than nonexistent public releases.

The website does not certify application feature parity or replace the platform-specific app test reports.

## Windows publishing environment

The official Sites helper requires Git Bash and Node on `PATH` for its packaging subprocess. With GNU tar on Windows, set `TAR_OPTIONS=--force-local` for the helper invocation so the drive letter in an absolute archive path is not treated as a remote host. These are process-local environment adjustments; credentials remain in memory and are supplied only through the helper's hidden stdin.
# Platform and cloud pages — 16 October 2026

- Added five static platform pages and one practical cloud guide, preserving the existing visual style and documented release limitations.
- Homepage title/H1 now identify OpenCommander as a file manager. Added crawlable links from the homepage and documentation; automatic OS selection remains active.
- Added SoftwareApplication/BreadcrumbList JSON-LD on platform pages, WebSite/CollectionPage data on the homepage, and WebPage data for the cloud guide. No fabricated ratings or desktop download offers.
- Build succeeded. Parsed all HTML: 362 local asset/link/fragment references valid, 11 sitemap URLs, one H1 and canonical per new page; JSON-LD parses successfully.
- Browser: desktop Windows page, mobile cloud and all five platform pages, navigation menu, homepage OS selection and Android tab link checked. At a 390px viewport, all six new pages and the homepage have no horizontal overflow. No browser JavaScript errors reported.
- Cloud screenshots are explicitly identified as Linux handbook images. Direct cloud access is scoped to Windows/Linux; provider authentication limitations and transfer behavior are explained.
