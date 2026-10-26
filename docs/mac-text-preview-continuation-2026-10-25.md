# macOS continuation: bounded text preview — 25 October 2026

Scope: continue Linux parity without WebDAV, preserving personal files,
configured accounts and the existing uncommitted work. No OS restart.

## Correction

Linux MEDIA-10 explicitly provides bounded read-only text preview. The Mac
previously delegated non-media previews to Quick Look without its own bounded
UTF-8 text viewer. Mac Catalyst now previews common text/source/configuration
extensions in a read-only selectable monospaced view, loaded off the main thread.
PDF and other rich document types retain Quick Look. Unsupported binary or
invalid UTF-8 content gets an honest message directing the user to the existing
Open/Open With actions after closing the preview; no fake external-open button
is supplied for a provider's temporary file.

The reader reads at most 2 MiB of file content plus one detection byte, using
a 64 KiB read buffer. It distinguishes an exactly 2 MiB file from truncated
content, omits a trailing split UTF-8 character, and does not repair invalid
encoding. It opens nonblocking and checks for a regular file before reading,
so a FIFO cannot hang waiting for a writer. Access/read errors remain distinct
from unsupported encoding. Provider/archive leases survive the dialog and any
in-flight read; no source content is written.

## Evidence

- `sh tests/run-image-preview-tests.sh`: passed, including Unicode/empty/exact
  limit/over-limit text, 2/3/4-byte UTF-8 boundaries, NUL binary, invalid UTF-8
  including the byte-limit boundary, FIFO, directory, missing source, unchanged
  source bytes and PDF routing; existing image and temporary-ownership tests pass.
- `sh tests/run-swift-safety.sh`: passed (existing archive, copy, cancellation,
  rollback and provider error regressions), log `/tmp/opencommander-b18-safety.log`.
- `python3 tests/check-swift-localization.py`: all 27 dictionaries have no
  duplicate keys. New preview messages are English/German, other languages use
  the existing English fallback.
- `sh tests/run-cloud-runtime-tests.sh`: passed configuration identity,
  credential-safe diagnostics, quotas, provider setup and environment isolation.
  This is not a fresh live cloud transfer or account-consent test.
- Initial native run did not initialize macOS automation mode within its
  timeout; no test body ran and this is NOT a pass.
  `/tmp/opencommander-b18-native-preview.log`.
- Retry ran the real Mac test
  `testBoundedTextPreviewIsReadonlyAndReportsBinaryAndTruncation`: passed in
  31.552 seconds. Unicode contents matched; the over-limit notice and binary
  explanation appeared; button and Escape closing worked; exact original
  fixture bytes remained unchanged after every preview.
  `/tmp/opencommander-b18-native-preview-retry.log` and
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_09-55-05-+0100.xcresult`.

## Distribution

Release 1.3 Build 18 includes the unchanged full writable NTFS 2 extension and
privileged helper, with the same production identities and Keychain groups.
Developer ID signing succeeded. Apple notarization
`aaee3030-4958-452e-8546-66fac9a1984a` was Accepted; ticket stapling and the
complete NTFS distribution/Gatekeeper gate passed.

Candidate:
`ntfs/NTFS3G/.build-native/developer-id-signed-20261025-b18/OpenCommander.app`.

## Final gate and installation

- Full `MacDesktopParityTests` run: **13 tests, zero failures, 270.536 seconds**.
  Includes positive ZIP creation/browse/extraction; malformed, encrypted and
  unsafe archives; bounded text; saved connections; real pane-to-pane dragging;
  copy/history/Undo and relaunch; independent transfer cards and paused jobs;
  custom-location rename/hide/show/remove; search result paths; special paths;
  20,000-entry filtering/navigation. Log
  `/tmp/opencommander-b18-native-desktop-suite.log`; result
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_09-56-37-+0100.xcresult`.
- Transfer queue: 33 PASS groups, including interrupted/cancelled copies,
  completed-only removal, persistence, damaged/full queue refusal and all
  1,000 cards/newest-first pages/page clamping. Cloud storage discovery: four
  PASS groups. File drops: 15 PASS groups. Tools: 18 PASS groups including
  deliberate isolated crash-recovery child kills. NTFS access policy/helper:
  three PASS groups. These are software regressions, not fresh physical-device
  or every-provider native acceptance.
- Production queue inspected in the real app: empty, with all bulk transfer
  controls disabled. App quit normally. No active openntfs mount was present.
- Build18 installed at `/Applications/OpenCommander.app`; full distribution
  gate passed on that exact installed copy. Previous Build17 is recoverable at
  `ntfs/NTFS3G/.build-native/App-before-b18.bWyFCq/OpenCommander.previous`.
  App launched normally, retaining German, existing configured online locations
  and the right iCloud pane. A disposable local file in
  `.build-native/Preview-b18-installed/Pruefung.txt` displayed the exact Unicode
  text and German read-only explanation in the installed signed Release app;
  Escape closed it. Left pane was restored to `/` after the test.
  Native accessibility button activations initially did not take effect
  immediately; the settled visible navigation and preview were independently
  observed before recording success. No claim of an instant automation action.
- `sh ntfs/NTFS3G/test-fskit.sh` on the installed driver: exit0, **22 PASS
  groups**. Own newly generated64MiB image only, `fskit-fixture.rjnu38/test.ntfs`:
  writes/reads, Unicode, case handling, rename/replace/delete, truncate, fsync,
  timestamps and persistence passed. Apple NTFS independently reopened it
  read-only and verified exact persisted bytes/timestamps. Both mounts were
  detached; no physical Elements or NAS test is claimed.

No personal data, account credentials or publisher keys were deleted/reset.
No OS reboot, new permissions or GitHub publication were performed.

MEDIA-10 remains partial: local native bounded-preview behavior is now verified,
but its original prerequisite sequence across every real online provider is not
individually re-signed off. Complete Linux parity is not asserted. Physical
Elements/NAS and new personal account-consent tests are not implied by these
software checks. WebDAV remains excluded.
