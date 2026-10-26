# Cloud preview budgets and pointer diagnosis — Build22 continuation

Reference independently rechecked: remote `codex/linux-desktop` is still
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`. No reset/merge/branch change.
WebDAV excluded. Existing edits, accounts and personal files preserved.

## Pointer finding

The previously inconclusive production pointer attempts were performed while
the foreground application was Codex. The guarded existing mouse driver's
read-only inspection independently observed that ownership and the production
window behind it (1212x800 logical points versus its2424x1600 Retina screenshot).
An ordinary LaunchServices activation of the existing OpenCommander installation
made it the foreground application. Then actual CUA clicks on Search and the
dialog's Close control succeeded. No file-action implementation, permissions,
Codex window, OS security or personal data were altered to manufacture a pass.

The native automated UI suite also initialized successfully again. Its first
full Build22-source run passed all17 existing tests in347.966 seconds, including
real pointer drag, image refusal/retry, text, ZIP, cancellation, queue/history,
settings and path checks. `/tmp/opencommander-b22-desktop-suite.log`.
This does not imply every external application/ghost/hover matrix was executed.

## Software corrections

- Added preview-only download budgets: images128MiB/180s; other online previews
  (including audio/video)2GiB/900s;30s no-progress protection where observed.
  Normal copy/move/tree downloads remain unrestricted by preview policy.
- Check listed size before network work, fresh metadata before body transfer,
  and actual final bytes before publishing a preview. OneDrive's production
  URLSession download delegate cancels over-budget advertised/received bytes;
  a per-request inactivity timeout and overall cancellable deadline apply.
- Cloud/server preview monitors its owned staging file every100ms, cancels its
  exact transport on excessive growth or stalled progress, and removes owned
  temporary output. This is NOT a byte-perfect disk quota: the child process can
  write between polls. Cancellation cooperates with the existing transport's
  cancellation/acknowledgment contract; it is not an arbitrary unkillable-plugin
  execution sandbox. No live network interface was disconnected.
- Completed-download/timeout races also release owned output, including a
  completed result that loses the task-group race. Cancellation/errors do not
  add read-only preview history, delete source files or retain a fake success.
- Native local thumbnail requests require a known cached input size at most
 32MiB; unknown size is not silently converted to zero. Oversized inputs keep
  their normal type icon rather than triggering Quick Look hydration.
- SVG gets a coordinated, bounded, immutable owned snapshot before Quick Look.
  The snapshot lease survives asynchronous rendering, is released on completion,
  and a30s UI deadline cancels/stales the request with a retryable explanation.
  Existing4096-pixel raster output cap remains. Neither output cap nor input
  budgets claim a hard64MiB ImageIO/QuickLook process allocation quota.

## Fresh core and actual loopback evidence

All exit0 unless explicitly described as skipped/failed below. Counts are test
groups, not manual cases or individual live-account actions.

| Runner/log suffix | PASS groups |
|---|---:|
| cloud-final |87|
| onedrive-final |25|
| images-final |13|
| remote-loopback |8|
| run-file-drop-tests |15|
| run-transfer-queue-tests |33|
| run-durable-copy-tests |12|
| run-durable-tree-tests |7|
| run-deletion-crash-tests |13|
| run-profile-lease-tests |5|
| run-remote-tests |1|
| run-commander-tools-tests |19|
| run-swift-safety |40|
| run-cloud-oauth-tests |8|
| run-cloud-lease-tests |5|
| run-cloud-runtime-tests |15|
| run-cloud-storage-tests |9|
| run-ntfs-transfer-tests |22|

Logs have prefix `/tmp/opencommander-b22-` and suffix `.log`. Cloud87 includes
the new preview boundary/stall/growth/cleanup checks and existing real disposable
child-process kill/recovery sequences; SIGKILL messages are intentional cases.
The OneDrive injected-download tests cover stale/fresh size, body overflow cleanup
and deadline cancellation, not an external Microsoft CDN overflow experiment.
SVG snapshot tests verify exact immutable bytes after source change and root
cleanup, plus oversize refusal before allocating a snapshot.

`remote-loopback` installed pinned fixture dependencies into an owned temporary
venv and exercised actual FTP/FTPS/SFTP transports, transfers, byte progress,
recursive tools, authentication refusals, encrypted-key isolated agent lock,
expiry, explicit unlock/reconnect and unchanged encrypted key. It did not use
the personal NAS or require personal passwords.

The aggregate runner's NAS-exclusive invocation omitted its required physical
fixture arguments and exited1 at usage validation. No NAS test ran and no volume
was touched; it is NOT a product regression or a hardware pass. The physical
runner intentionally refuses ordinary `/tmp` substitutes for `/Volumes` targets.

## New native test corrections (no failed run counted as passed)

The initial extended suite incorrectly expected a one-shot listing failure to
remain failed, but the provider's bounded retry recovered. It was interrupted
during failure diagnostic collection. The fixture now holds a real synthetic
outage flag until explicitly removed by the test.

The first four-case targeted run passed SVG10.497s but failed three tests:
one stale AX identity after editing a path, and two queries for Alert when
Catalyst exposed its dialog as Sheet. Tests now relaunch the own prepared drag
fixture and query actual message/OK controls across those native representations.
No broad production change was made just to satisfy those mistaken queries.

Independent visible CUA acceptance of the exact new DEBUG fixture showed the
actual timeout sheet and explanatory text, no retained download container, a
usable listing after OK, a new Opening file… progress/Cancel control, then the
exact successful Unicode text after retry. Escape/normal quit worked. No real
provider/configuration/network was involved.

Further native regression and installation results are recorded below when
complete; full Linux parity is not asserted by this continuation.

## Nonblocking cloud read errors and actual additional native passes

Further investigation identified a real usability gap in addition to the test
query issues: failed initial cloud listings lacked a direct pointer Retry, while
read-only preview failures blocked the app through a system sheet. The shared
browser now shows a clearly identified inline error and Retry in the affected
pane for listing/navigation/preview reads. Existing items are explicitly marked
as retained, not refreshed by the failed operation. Retry repeats the failed
preview/navigation or reloads the initial list. Account reset clears retained
retry state. Write-operation errors and warnings retain their existing handling.
Read-only errors do not create mutation-history entries. Ordinary operations
clear stale banners; errors never silently change another pane/account.

- Actual copy-toggle drag, move-toggle drag and readonly destination refusal
  passed32.991s. Exact independent source/destination bytes checked; source of
  move absent only after target publication, readonly target empty/source intact.
  The first attempt failed before these gestures because a path-field AX token
  rebound to UserNotificationCenter; relaunching the prepared own fixture avoided
  that unrelated identity. `/tmp/opencommander-b22-new-native-corrected.log`.
- SVG oversize/refused → replace own fixture with valid SVG → Retry → actual
  completed render/no error → Escape/unchanged exact source passed11.231s in the
  same corrected targeted run. No stale/error run counted as full-suite success.
- Final inline initial synthetic outage → error shown → remove ONLY its own
  outage flag → actual pointer Retry → Proof.txt list with no login or download
  passed9.611s. Synthetic preview deadline → inline timeout/exact cleaned staging
  → pointer Retry → exact Unicode text → Escape → empty mutation history passed
 18.784s. `/tmp/opencommander-b22-inline-native.log`.
- Original modal-expecting extended attempts, including the two-case
  `...new-native-retry3.log`, remain failed test runs, not acceptance evidence.

The final read monitor reserves100% progress for completed integrity checking.
The full21-case regression after the inline change and the final independent
large-media/quota cases must be reported separately, not inferred from these
targeted pass counts.

## Completed Build22 acceptance and actual installation

- Full21 cases passed425.014s on the inline-error source. The extra two native
  cases passed34.099s (large image/video12.241s; quota21.859s), separately.
- Exact final Build22 source then passed the complete23-case Mac desktop suite,
  zero failures,458.003s. `/tmp/opencommander-b22-verified-native.log` and
  `.../ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_13-50-33-+0100.xcresult`.
- Final raster/vector preflight reads fresh metadata before asking a physical
  File Provider for coordinated body access. The archive preparation path does
  not mistake a large container's size for a small member's size. The new core
  preparation-hook/large-container regression passed; image suite now14 groups.
- Final Build22 candidate `developer-id-signed-20261025-b22-verified` was signed,
  accepted by Apple (`6650fa2d-19be-484b-b5a3-8fb0a400b795`), stapled, and passed
  full distribution/Gatekeeper checks. Synthetic cloud adapter marker strings
  are absent from the Release executable. Earlier22 candidates were NOT installed.
- Empty queue and no active openntfs mount were independently confirmed; old
  app quit normally. Exact installed version22 passed the same distribution gate.
  Build21 backup remains `ntfs/NTFS3G/.build-native/App-before-b22.gGNCMK/OpenCommander.previous`.
- Installed NTFS:22 PASS groups, new64MiB image only, full FSKit operations and
  independent Apple NTFS read-only reopen/exact bytes/timestamps. Both mounts
  detached. `/tmp/opencommander-b22-installed-ntfs.log`. Not physical Elements/NAS.
- Production AX helper attempts remained unreliable even with foreground app
  observed. A real guarded driver click at the screenshot/window-bounds-derived
  Preview button successfully opened only own757-byte Valid.png, actual image
  visible/no error; Escape returned normally. Thus foreground alone is NOT
  asserted as the complete explanation, nor is a product mouse patch claimed.
  `/tmp/opencommander-b22-installed-pointer.log`.
- Existing Dropbox account opened without login. Only own preexisting
  `OpenCommander-LiveQA-Size12-wUvOA0/a.txt` was previewed: actual text `ABCD`
  newline, German read-only status. Normal quit/process absence/fresh launch
  restored the exact QA folder without login and reenumerated a.txt with a new
  session-local item ID. Right original iCloud path persisted.
- Existing Google account listed711 items without login, with an honest
  duplicate-name warning; no personal item was opened or modified.

## Live native online name conflict, then discovered Mac path bug

Using only the existing own fixture `google-live-9hIyW4/Quelle`, created a NEW
51-byte a.txt (never overwrote a prior local file). SHA256:
`a13f8e4be1921fbccf928de6eb0f73f9f23b52e57461f8c1e256b073697e11e8`.
Right pane was exactly the Dropbox QA folder above, whose a.txt already held
different contents. Copy toggle0, left own a.txt explicitly selected; actual F5
opened the native same-name conflict naming both a.txt and proposed a (2).txt.
Selected Keep Both; visible real transfer progress completed and new a (2).txt
appeared. Actual cloud preview showed `OpenCommander Build22 own collision proof:
Grüße` newline. Separately previewing original cloud a.txt still showed `ABCD`
newline. Local source SHA256 remained identical after completion. No replacement,
delete, sharing or personal-file action was performed. New own cloud copy and
local fixture are retained deliberately as evidence; no cleanup was disguised
as another successful transfer. Both original root/iCloud pane locations restored.

This is a real Dropbox/UI conflict case, not a fresh Microsoft/Google conflict
matrix. Pointer helpers use their existing strict installed-fixture, foreground,
window-owner and endpoint guards. Logs `...b22-dropbox-tree-pointer.log`,
`...b22-source-pane-pointer.log`, `...b22-keepboth-preview-pointer.log` and
`...b22-keepboth-original-pointer.log` in `/tmp/opencommander-`.

The sequence exposed a genuine Mac path-display bug: documents were abbreviated
to iOS's virtual `/Documents` even on macOS. Internal copy URLs remained correct,
but the displayed path was not an actual Finder/terminal path. Build23 now uses
absolute native host paths. iOS retains its virtual Documents alias, including
Unicode and proper component-boundary checks. The new pure Foundation regression
passes; safety suite now41 groups. This changes presentation, not stored bookmarks
or source/destination identities. Final23 regression/installation follows below.

OneDrive's actual URLSession download/per-task delegate path was also exercised
through isolated HTTPS URLProtocol, without the injected downloadFile closure:
exact successful bytes, over-budget refusal, and no Graph bearer to download URL.
It passed; OneDrive suite now26 groups.
`/tmp/opencommander-b23-onedrive-native-session.log`.

## Final Build23 acceptance and installation

- Exact production-source desktop UI suite passed all23 tests, zero failures,
 453.530s. `/tmp/opencommander-b23-native.log`, result
  `ntfs/NTFS3G/.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_14-39-42-+0100.xcresult`.
- Fresh23 core suites:87 cloud,26 OneDrive (including real URLSession delegate
  via HTTPS URLProtocol),41 file safety and14 image groups, all exit0.
  `/tmp/opencommander-b23-cloud-client.log`, `...b23-onedrive-native-session.log`,
  `...b23-file-safety.log`, `...b23-images.log`. Other unchanged subsystem and
  actual loopback passes above retain their precise Build22 timing/scope.
- Full writable NTFS Build23 signed, Apple Accepted
  (`8ebd5fb0-46c5-42b6-b8f7-b08cd572eec6`), stapled; full distribution gate passed
  before installation and on exact `/Applications/OpenCommander.app` afterward.
- Queue explicitly empty, no active NTFS mount, normal old-app quit/process
  absence. Build22 backup retained:
  `ntfs/NTFS3G/.build-native/App-before-b23.T5plsn/OpenCommander.previous`.
  Installed version independently reads23. Language, locations, root/iCloud paths
  and existing history retained. No publisher key/secret bundled.
- Actual installed23 own Documents fixture path reads
  `/Users/niklaus/Documents/OpenCommander/ntfs/NTFS3G/.build-native/google-live-9hIyW4/Quelle`,
  not virtual `/Documents/...`; a.txt appears. Returned to left `/` and right
  original iCloud afterward. No personal directory data changed.
- Existing direct OneDrive also loaded its root after installation without
  a new login (actual count0/29, no loading/error banner afterward). No personal
  item names were emitted or opened. Original root/iCloud views restored again.
- Installed23 driver:22 PASS groups with only a new64MiB image, full real FSKit
  write/read/rename/replace/delete/truncate/fsync, Unicode/timestamps, then
  independent Apple NTFS readonly reopen. Both mounts detached.
  `/tmp/opencommander-b23-installed-ntfs.log`.
- Read-only hardware inventory found zero external physical disks (zero
  Elements entries), and no SMB mount for192.168.0.22. No physical-device pass
  is claimed or inferred from loopback/NTFS-image success.
- All27 localization dictionaries and whitespace validation pass. No OS restart,
  personal-file deletion, account revocation, Git commit/push or GitHub release
  was performed in this continuation.

This closes the described discovered software defects and bounded regressions,
not every row's complete original prerequisite/provider/external-app matrix.
The158-row ledger remains explicitly incomplete. Do not report that only
personal login/hardware tests remain merely from these aggregate pass totals.

## Additional installed-source keyboard and queue acceptance

No production-source changes after the signed/installed Build23. Added two
native regression methods to the isolated test runner:

- `testKeyboardClipboardPaneSwitchAndTextEditingDoNotMutateSelection` passed
  in18.197s: actual Cmd-C, Tab, Cmd-V copied exact bytes to the other pane;
  Cmd-F opened search with that pane's path. Cmd-A/C/X/V/Delete in the path
  field edited only text, with both selected files unchanged and no duplicate
  output. Cmd-Y opened the actual text preview; Escape closed it.
  `/tmp/opencommander-b23-keyboard-native-retry.log`, result
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_15-09-59-+0100.xcresult`.
  First launch command omitted the existing cloned-package cache path and
  failed dependency checkout before running any test; corrected command used
  the same pinned cache as all previous builds, without dependency changes.
- `testRemoveCompletedRefreshesPagesAndListingsWithoutDeletingFiles` passed
  in20.158s: seeded65 completed cards with actual byte-verified owned destination
  files plus one paused card. Navigated to the older page; then the real
  Remove-all-completed button removed cards, clamped/hid pagination and disabled
  itself, retained the paused job, and refreshed the pane to display a file
  created after its previous listing. All65 output files/source stayed byte-exact.
  Fresh-process relaunch retained exactly the one paused job and did not start it.
  `/tmp/opencommander-b23-queue-native.log`, result
  `.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_17-28-38-+0100.xcresult`.

These two focused passes initially supplemented the earlier complete23-test run.
The subsequent combined full25-test native run also passed, zero failures,
486.744s: `/tmp/opencommander-b23-expanded-native.log`, result
`.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.25_17-30-44-+0100.xcresult`.
Test clone's rebuilt NTFS extension was
again detached before ad-hoc signing so it cannot shadow the production driver.
Build23 remains installed, without unnecessary replacement for test-only edits.
JOB-11 and PROP-05 evidence expanded; their full original prerequisite matrices
remain partial, not promoted based on these bounded checks.
