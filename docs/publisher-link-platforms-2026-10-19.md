# Publisher website link on current platforms

Fixed destination: https://haenggi.vip/. User-triggered only; no automatic
website loads or tracking added. Historical release source snapshots and already
published binaries are not rewritten; new builds contain these additions.

- macOS: native Help panel and Settings / Locations row, German/English.
- iPhone/iPad: Help dialog action using the same shared Apple URL constant.
- Android phone/tablet and Android TV: shared MainActivity Help dialog action;
  resource fallback English, German translation. Missing browser is reported
  with website-specific guidance (particularly relevant to TV devices).
- Linux/Windows: shared Qt Help and Settings dialogs, shared URL/opener module,
  German/English. Platform browser selected by QDesktopServices.

Checks:
- macOS signed build and extension preflight passed (`more-apps-platforms-apple.log`).
- Swift syntax parse and 27-dictionary localization checks passed.
- Apple offline handbook tests passed; HTML remains entirely offline.
- Qt targeted suite: 3 passed in 9.15 s (`more-apps-desktop.log`). Verifies both
  language labels, both entry points, exact URL, no implicit open, browser failure.
- Android resource XML parsed. Full Android compile not passed: Gradle offline
  cache lacks Android plugin 8.10.1; local SDK/build environment is incomplete.
  No Android/iOS physical-device launch is claimed.

Storage pressure interrupted installation of the temporary Qt dependency set;
required Qt modules loaded and all three tests subsequently completed. The own
temporary dependency environments were removed afterwards (~620 MB recoverable
by reinstalling dependencies). Logs and source tests remain in the repository.
No user environment or personal file was removed. Existing installed Mac app
and its pending iCloud login are not replaced by this source change.
