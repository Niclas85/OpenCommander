# Cloud continuation, Build19 — 25 October 2026

Scope: Linux/cloud special cases, excluding WebDAV. No account revocation,
personal-data edits, new permissions or OS restart. Existing work is preserved.

## Findings and corrections

Online Preview/Open previously used a listing-only busy state: the label said
"Loading folder", without the normal cancellable operation progress. The shared
OneDrive/Google/Dropbox/iCloud/server browser now distinguishes opening a file
from listing a folder. It shows the existing indeterminate progress/cancel UI,
observes download byte progress where the client supports it, and resets UI and
observers on both success and failure. It does not claim a percentage when the
provider supplies none.

Read-only opening is not a transfer mutation: it does not add a copy job or a
history record, nor refresh all panes as if a file had been changed. Selection
actions are recomputed after releasing the foreground-operation guard, avoiding
disabled Rename/Delete/ZIP controls after a preview/cancel. A cancelled transport
NSError is treated as cancellation when its owning task was cancelled, not shown
as an unrelated provider-error alert.

A downloaded temporary file is explicitly cleaned if cancellation happens before
handoff to the viewer/export picker. The existing viewer lease/export owner then
owns cleanup after a successful handoff. Sources are never deleted by Preview.

## Completed evidence

- `tests/run-cloud-client-tests.sh`: exit0,86 PASS groups. Includes independent
  processes, interrupted upload/download/moves, cross-cloud replacement,
  reconciliation, two-sided Undo, and actual isolated SIGKILL after a backend
  mutation commits but before acknowledgment. These are synthetic backends and
  disposable fixtures, not fresh transfers on every personal online account.
- `tests/run-onedrive-tests.sh`: exit0,24 PASS groups; version-safe downloads,
  conflicts, retries, shared reads and refresh/disconnect generation guards.
- Cloud OAuth:8 PASS groups; cloud configuration leases:5 PASS groups.
  Existing account files/credentials are not altered by these isolated tests.
- Live installed Build18: existing Google Drive connection listed normally,
  with an honest duplicate-name warning at its root. Only the already-owned
  `OpenCommander-LiveQA-Size12-wUvOA0` test folder was entered. Preview of its
  `a.txt` showed the expected synthetic `1234` text and German read-only message.
  It was closed with Escape. Navigating to `Sub/b.txt`, quitting normally and
  launching a fresh process restored that exact folder and file, without a new
  login. Session-local item IDs changed, so this exercised name-based restore.
  No live cloud file was renamed/deleted/shared in this sequence.

## Native regression fixture and honest failure accounting

The DEBUG clone has an explicit opt-in delayed read-only cloud fixture, requiring
its exact test bundle ID, the existing validated private test root and the new
test launch flag. It never reads a real cloud configuration or sends a network
request. Only its named Proof.txt download, own diagnostic marker and generated
temporary container can be written. Release builds exclude this fixture.

The first full-suite attempt passed nine existing cases before the new test
looked for the wrong macOS accessibility element type (Button vs Catalyst cell).
The real Proof.txt was independently visible and correctly listed. XCTest then
stalled collecting failure diagnostics; its own process was interrupted. This
is not a full-suite pass and not evidence of a provider outage. The corrected
query matches the stable identifier irrespective of native element type.

Corrected native test passed24.520s on the final source, including exact opening
status, a visible Cancel control, no cancellation error alert, removal of the
cancelled download container, successful retry/exact Unicode preview, removal
of the successful viewer's temporary container on Escape, re-enabled Rename
after both paths, and an actually empty History panel. It passed again22.464s
during the final full-suite run. Neither native test used a real account.
`/tmp/opencommander-b19-native-cloud-preview.log` and
`.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_10-32-45-+0100.xcresult`.

Release1.3 Build19, full writable NTFS2 and helper, is Developer-ID signed;
Apple notarization `8c404e6c-b3a8-42fd-bc6d-5cf043a8ee7e` was Accepted.
Stapling and the full distribution/Gatekeeper gate passed on
`ntfs/NTFS3G/.build-native/developer-id-signed-20261025-b19-final/OpenCommander.app`.
The DEBUG fixture entry point is absent from the Release executable. The earlier
non-final signing output was not submitted or installed.

## Final test gate and installed version

- Final-source complete native desktop suite: **14 tests, zero failures,
  282.122 seconds**. This includes the new delayed cloud-cancel/retry test and
  all13 earlier desktop cases (archives, drag/drop, Undo/history/restarts,
  location customization, search, special paths and20,000 entries).
  `/tmp/opencommander-b19-final-desktop-suite.log` and
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_10-33-55-+0100.xcresult`.
- Production queue independently observed empty; normal quit and no active
  NTFS mount before installation. Exact signed/notarized Build19 installed to
  `/Applications/OpenCommander.app`, then distribution gate passed again on
  the installed copy. Recoverable Build18 backup:
  `.build-native/App-before-b19.1IpMBC/OpenCommander.previous`.
- Installed Build19 restored Google QA `Sub/b.txt` without login. Its actual
  Preview showed German "Datei wird geöffnet …", elapsed time and a real
  Abbrechen control. The tiny download completed before a subsequent attempted
  Cancel click; the UI tool refused that obsolete element. **This is not a live
  cancellation pass.** Completed preview displayed the expected synthetic
  `123456` text. Escape closed it; Rename/Delete/ZIP were enabled afterward.
  Native delayed-fixture tests above supply actual cancellation evidence.
- Installed NTFS driver: `test-fskit.sh` exit0,22 PASS groups on an own new
  64MiB image. FSKit writes and independent Apple read-only reopen both passed,
  including exact bytes/timestamps and rename/delete persistence. Both mounts
  detached. `/tmp/opencommander-b19-installed-ntfs.log`. No physical Elements or
  NAS test is implied.
- All27 localization dictionaries pass duplicate-key validation; source diff
  whitespace checks and ledger JSON validation pass.
- Installed Build19 Dropbox live: existing login listed its own QA folder;
  Preview of `OpenCommander-LiveQA-Size12-wUvOA0/a.txt` displayed its current
  synthetic `ABCD` text with the German read-only message. Escape closed it and
  Rename was enabled. After regular quit/fresh process, that exact Dropbox
  folder, Sub and five-byte a.txt were restored without login, with new
  session-local IDs. No Dropbox file was changed, shared or deleted. No live
  Dropbox cancellation/overwrite matrix is implied. Left pane then restored to
  `/`; original right iCloud pane retained throughout.

Logs: `/tmp/opencommander-b19-cloud-client.log`,
`/tmp/opencommander-b19-onedrive.log`,
`/tmp/opencommander-b19-cloud-oauth.log`,
`/tmp/opencommander-b19-cloud-lease.log`,
`/tmp/opencommander-b19-native-desktop-suite.log`.

Complete Linux/all-provider parity is not asserted. Fresh personal OAuth/2FA,
multi-drive accounts, external-cache writeback and the complete physical-device
matrix remain separate prerequisites. WebDAV stays excluded.
