# Mac continuation — 24 October 2026 (WebDAV excluded)

Fetched `origin/codex/linux-desktop`: still
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`. No newer Linux commit to merge.
The 158-case ledger is not fully certified. Its 48 native / 102 partial /
8 environment-required classifications are not replaced by unit-test counts.

## Fresh software regression evidence

The following runners exited0; logs under ignored `ntfs/NTFS3G/.build-native/`.
Prefix `parity-20261023-final-` for the first twelve below, and
`parity-20261024-final-` for the last five. Suffix is runner name plus `.log`.

- run-swift-safety: 38 PASS groups.
- run-transfer-queue-tests: 33.
- run-cloud-client-tests: 86, including separate-process resume and actual own
  child SIGKILL after synthetic committed publication/retention, with/without
  replacement, changed-source refusal and two-sided Undo.
- run-file-drop-tests: 15 representation/staging groups, not mouse tests.
- run-remote-tests: parser-only run; separate `parity-20261024-final-remote-live.log`
  passed actual disposable loopback FTP/FTPS/SFTP-password/SFTP-key transfers,
  TCP loss/retry, search/compare/rename, progress, rollback/cancellation and
  encrypted SSH key agent expiry. No NAS/personal server accessed.
- run-commander-tools-tests: 18, including actual own rename crash/recovery.
- run-durable-copy-tests: 12.
- run-durable-tree-tests: 7.
- run-onedrive-tests: 24 protocol groups, not new account consent.
- run-cloud-runtime-tests: 15.
- run-handbook-tests: 2.
- run-image-preview-tests: 8.
- run-cloud-storage-tests, run-cloud-oauth-tests, run-profile-lease-tests,
  run-deletion-crash-tests and run-cloud-lease-tests: all exit0.

## Native XCTest and correction

Isolated clone `com.github.niklaus85.OpenCommander.MacUITests`, build root
`/private/tmp/OpenCommander-MacUITests.gpOD2X`. Its FSKit extension is detached
before ad-hoc signing, so it cannot shadow the installed production NTFS module.
Only fresh `/private/tmp/OpenCommander-MacUITest-<UUID>` fixtures are mutated.

Initial four-test run: connections refresh/close, copy/history/relaunch/Undo and
actual press-and-drag to the other pane's child folder passed. Search found the
file, but its cell's accessible label did not expose the complete path. This
failed assertion is retained, not counted as a pass. The result cell now exposes
both title and complete path explicitly to accessibility clients.

Fresh rebuild and repeat passed all four tests (0 failures, 43.383s), log
`parity-20261024-native-retest.log`, with retained xcresult. Search uses the active
pane path, default case-insensitive matching and exposes the complete result
path. Drag verifies exact source/destination content, not just a progress card.

An additional two-paused-job native test passed independent compact/details
controls, enabled Resume buttons, actual app restart and per-card persistence.
Neither paused job ran or created a destination. This is a bounded JOB-10
continuation, not the entire two-running-slow-jobs latency sequence.

## Large-directory measurement boundary

New 20,000-empty-file APFS fixture test initially timed out while recursively
requesting every offscreen accessibility cell. A one-second sample of the exact
test app showed its main thread inside XCTest/AX hierarchy materialization,
not a copy worker. RSS sample reached about 474 MiB (later broader-query sample
about 766 MiB). Narrowing the header query to a typed `firstMatch` immediately
read `/20000` at t=6.42s, but a later unscoped sort-button query repeated the
hierarchy problem. Full recursive AX snapshots are not a valid subsecond GUI
latency measurement. The test is being narrowed at every control query; neither
failed/aborted attempt is a SAFE-04 pass. No accessibility elements are hidden or
removed from the product merely to satisfy a test.

Final typed/firstMatch queries for each control passed the complete test in
25.421s: complete 20,000 list, sort button, last-entry filter, first-entry absence
while filtered, clear, parent navigation and warm reopening, right pane unchanged.
Retained xcresult `Test-OpenCommander-2026.10.24_00-06-26-+0200.xcresult` contains
timing attachment: cold2.708s / warm3.016s including XCTest input/observation.
This does not establish the original <=1s performance target or a physical
network/cloud benchmark; SAFE-04 remains partial. Intermediate broad sort-button
query run was explicitly aborted (exit75), not counted as a pass.

## Candidate and remaining boundaries

Release candidate uses `CURRENT_PROJECT_VERSION=15`; source project default
remains14. Build log `parity-20261024-accessibility-release-build.log` exit0.
Full NTFS candidate signed with the corrected native-module entitlements;
Apple accepted submission `49cf81e3-1e09-4157-9c57-78dc1488255c`.
Stapled ticket, direct Gatekeeper assessment and strengthened full distribution
gate passed. An initial immediately-after-staple validation failure was retried
and independently passed; no validation requirement was bypassed.

Remaining original cases include fresh personal OAuth/2FA/consent/reconnect,
multi-drive Microsoft selection, full physical filesystem/device matrix,
external writeback synchronization, full third-party drag/modifier combinations
and bounded performance/native UI sequences. Existing physical Elements/NAS and
all cloud account combinations are not inferred from loopback/image adapters.
No new sharing grant, OS restart, account revocation or personal-file deletion.

## Installation

Installed the signed/notarized Build15 candidate at `/Applications/OpenCommander.app`
after confirming the production queue contained no jobs and no OpenCommander
NTFS mount was active. Previous r2 preserved at
`.build-native/App-before-b15.As9itF/OpenCommander.previous`. Existing Elements
was discovered on Apple's read-only NTFS mount; it was not remounted or written.
The complete installed signature/profile/notarization/Gatekeeper gate passed.
Post-install `test-fskit.sh` exited0, log `parity-20261024-installed-b15-ntfs.log`:
mounted create/read/write/copy/rename/replace/delete/truncate/fsync, Unicode,
exact timestamps and independent Apple read-only reopen all passed. New test
virtual disk7 safely detached; no physical device format/repair/restart.
No new GitHub release was requested in this continuation; Build15 is locally
installed, while the published r2 remains unchanged.

## Further start/profile/favourite continuation

`parity-20261024-start-profile-native.log`: native history-plus-paused-job
coexistence passed15.283s. A real F5 copy supplies the History/completed job;
one explicitly paused synthetic job is appended only while the app is closed.
After relaunch both History Undo/time and Resume remain available, copied bytes
match and the paused destination does not exist. This does not prove migration
between two different binaries; START-08 stays partial.

XCTest's `open(URL)` attempt did not deliver the special folder as expected.
A speculative launch-options fallback was investigated then removed: no
production change is justified by that test alone. Separate actual macOS
LaunchServices handoff to the explicitly selected standalone app succeeded.
Own fixture `/private/tmp/OpenCommander-MacUITest-Remaining-20261024-umEL4S`,
copy at `Portable App/OpenCommander.app`, resource points to that same private
root, no FSKit extension registered. Native file list showed Proof.txt; after
explicit selection, F5 completed and independent cmp verified exact76-byte copy.
Info version1.3; strict deep signature verification passed. Quit and cold launch
with an encoded file URL opened the exact `Grüsse $(false) ; ' & # % 文件` folder
and listed Inside.txt in the left pane, preserving the right pane. No shell
interpretation used. START-01 is now a bounded native portable Mac pass;
START-06 remains partial for the full invalid-input/start-argument matrix.

Favourite test's first seed failed because a runner's named UserDefaults suite
is not the Catalyst app's own preference domain. Corrected fixture import is
DEBUG-only, exact test bundle/root guarded, max16 entries/16KiB, custom local
directories only with canonical own-root containment and no bookmark/account
data. It imports once per root so native edits can survive restart. Production
Release behavior is unchanged by this fixture helper. Favourite rename/visibility/
remove test remains pending; its failed seed was not a product failure or pass.

Further attempts failed at app activation (Running Background) before assertions.
Computer Use then explicitly reported: Mac locked, automatic unlock paused after
physical input; manual unlock required. No unlock bypass attempted. The current
UI run was stopped; aborted/activation-blocked runs are not passes. Only the
owned temporary app's LaunchServices registration was removed/replaced during
diagnosis; no global registry reset or production registration was changed.

Build16 Release rebuild from final source succeeded, but it is not installed:
the remaining native checks are blocked by the lock. The tested, notarized
Build15 remains installed; its account settings/data remain unchanged.
Ledger now49 native_verified /101 partial /8 environment_required,158 total;
complete=false, WebDAV excluded. Logs retain the unsuccessful attempts.

## Unlocked continuation, 24 October

The Mac is reachable again. The targeted native runs are retained in
`parity-20261024-unlocked-native.log`, `parity-20261024-favourite-clean-retest.log`,
`parity-20261024-physical-fixture-retest.log` and
`parity-20261024-diagnostic-retest.log`. These are failed diagnostic runs, not
passes. A stale, owned portable test process was terminated (not the installed
app). The DEBUG favourite containment fixture needed physical-path comparison;
the resulting native snapshot shows the imported favourite with `/tmp` in its
bar identifier, while the fixture supplied `/private/tmp`. The test now uses
the canonical bar identifier. The settings cell and encoded special-character
file-URL sequences are still being diagnosed. Plain special-character local
path navigation already reached its actual Proof.txt listing.

Build16 signed package passed the complete distribution gate. Apple accepted
notarization `86bb2834-3622-4b96-b511-85d8b7ff5c5e`; its ticket is stapled.
It is not yet installed. DEBUG-only fixture refinements do not change this
Release binary. Publisher credentials remain outside source and app bundles.

### Final results and installed Build16

The temporary pending results above are superseded by the following actual
results, not retroactively counted as successful runs:

- `parity-20261024-unlocked-final-native.log`: eight of nine native sequences
  passed (connections8.751s; F5/history/Undo13.117s; history plus paused queue
 13.674s; independent compact cards/restart12.659s; native pane drag11.255s;
  search10.600s; literal/encoded paths and invalid-input refusal; 20,000 local
  entries23.950s). The one failure was the immediate assertion after favourite
  removal, before asynchronous location-bar refresh.
- `parity-20261024-favourite-removal-retest.log`: the full ninth favourite
  sequence passed23.487s, including rename, hide/show, restart, shortcut removal,
  refresh, second restart, and exact sentinel bytes preserved. Querying the
  rename field by its actual value accommodates Catalyst's native sheet rather
  than assuming an iOS alert container. Actual switch-centre clicks avoid
  Catalyst XCTest's false not-hittable result. The bounded DEBUG import reports
  success only inside the owned fixture root.
- `parity-20261024-native-key-retest.log` independently passed typed paths17.211s.
  Exact pre-submit text comparison revealed XCTest `typeText` omitted the colon
  from `file://`; explicit colon-key input fixed the automation, with no path
  parser production change or acceptance of malformed input.
- `parity-20261024-unlocked-cloud-client-retest.log`: exit0,86 PASS groups,
  including actual child-process loss/recovery, changed-source protection,
  replacement and two-sided Undo. These are controlled protocol/engine tests,
  not fresh personal-provider consent or live account reauthorization.

Normal installed-app queue preflight displayed no saved jobs. Quit normally;
no active OpenCommander NTFS mount was present. Previous Build15 is recoverable
at `.build-native/App-before-b16.DYchdn/OpenCommander.previous`. Copied signed,
stapled Build16 into `/Applications/OpenCommander.app`; installed distribution
gate passed, Info CFBundleVersion16. Native startup showed the preserved German
UI, previous root/iCloud panes and configured Google Drive/Dropbox online places.
No account reset or personal file deletion. No OS restart. No new GitHub release
was made during this continuation; the published r2 remains unchanged.

`parity-20261024-installed-b16-ntfs.log`: exit0,22 PASS groups against a newly
created disposable NTFS image only. Actual installed FSKit driver mounted it
and passed create/read/write/copy/rename/replace/delete/truncate/fsync,
case-preserving/case-insensitive names and timestamp precision. After detach,
Apple's independent read-only NTFS driver reopened it and verified exact Unicode
content,517-byte data, rename/delete persistence and timestamps. Both mounts
detached successfully. This does not certify physical Elements/NAS or the full
hardware/filesystem matrix.

Ledger:50 native_verified /100 partial /8 environment_required,158 total,
complete=false. PLACE-08 is now bounded native-verified; START-06 retains partial
status despite the newly passed typed-path subset. Full Linux manual parity is
still not certified. WebDAV remains excluded; missing account/device prerequisites
and remaining original manual-step matrices are not silently marked passed.
