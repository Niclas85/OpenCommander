# Native Mac parity and restart acceptance — 2026-10-16

## 2026-10-17: visible-window continuation and tree acceptance

After the user exposed the windows, native Finder multi-selection to the
`Target` tree row passed. Both `Alpha.txt` and `Grüsse.txt` in
`/Users/niklaus/OpenCommander-MacUITest-Tree-Drop/Target` matched the original
synthetic Source files with `cmp`. A separate native internal hover over the
collapsed Target row expanded it, revealing Child (before/after screenshots
observed). The resulting duplicate-name dialog was cancelled; the corrected
German cancelled status appeared. No existing source was removed.

The driver now activates all windows of the intended test app and checks
destination focus before activating Finder. It still refuses covered endpoints;
earlier refused attempts sent no mouse events. The deprecated no-op activation
flag was removed after compilation diagnostics. Eleven provider regression
groups passed again; the signed application build remains
`external-drop-status-build.log`. Full external modifier/application permutations
and full Linux behavior parity remain unclaimed.

Installed and launched this incremental candidate at `/Applications/OpenCommander.app`.
Installer signature/FSKit identity checks passed. Previous app is retained at
`ntfs/NTFS3G/.build-native/App-before-install.SD3GKH/OpenCommander.saved`.
The installed app visibly starts with its normal local panes and Ready status.

## 2026-10-17: external Finder matrix continuation

Fetched `origin/codex/linux-desktop` again: still `e3b2981`, no newer committed
Linux functionality. Preserved unrelated Android/Linux working-tree changes.
Local drop hit-testing now rejects pointer positions outside the receiving
table, matching the online guard. External original-unavailable and conflict
Cancel paths no longer leave a misleading “loading” status.

Using only `google-live-9hIyW4/OpenCommander-MacUITest-External-Matrix`:
- Native Finder multi-selection (`Alpha.txt`, `Grüsse.txt`) to a local Folder
  row passed, with exact `cmp` readback and original source preservation.
- Repeated native drop displayed the two-item conflict dialog; Cancel preserved
  both destination contents. Toolbar Undo removed both visible copies.
- Explicit Move mode imported both Finder originals, retaining recovery files.
  After candidate restart, two Undo actions restored both source names and
  removed the visible destination copies. An earlier attempted Undo sequence
  did not change disk state and was not counted as a pass.
- The rebuilt candidate's shared import conflict dialog now ends with the
  German status “Die Aktion wurde abgebrochen.” Verified through Finder
  clipboard import after later native gestures were blocked by a covering
  ChatGPT window; these blocked gestures sent no events and are not passes.

Signed candidate builds passed (`external-drop-bounds-build.log`,
`external-drop-status-build.log`). The mouse driver can inspect only test Finder
windows, reports covered endpoint owners and attempts destination activation;
the existing ownership check remains mandatory. This is not full parity or
complete external-app/modifier/tree-hover acceptance.

Continuation blocker: the native driver repeatedly identified `source=Finder,
target=ChatGPT` and refused events. CUA explicitly refused access to the Codex
app for safety reasons, so no alternate mechanism was used to minimize or
control it. User must uncover the destination before further physical drag
acceptance. The latest candidate remains open; the installed version from the
previous accepted batch is unchanged in this continuation.

## 2026-10-17: cross-provider move recovery continuation

Added `PendingCrossCloudMove`: the intent is persisted before downloading;
nested download/upload receipts and retained-source journals survive process
loss. Recovery rechecks both accounts, source version, persisted paths and
destination ownership/content. Ambiguous upload ownership never authorizes
removing the source. The browser exposes these jobs in target-side recovery and
records Move/Undo only after verified completion.

`ntfs/NTFS3G/.build-native/cross-move-process-tests.log`: **53 PASS groups**, with
22 separate process phases. New phases cover intent, failed upload with source
preservation, new-process resume and retained-source reconciliation/Undo.
The first run was interrupted by a host restart (not initiated here); it is not
counted. Retry and expanded process run both completed successfully.

Live local DnD on the existing installed build used only
`google-live-9hIyW4/ArchiveSource`, `DragAcceptance-20261017` and
`DragMove-20261017` below the native build folder. A native multi-selection drag
copied `Archiv.txt` and `Ordner/Nested.txt`; a second drag in Move mode moved the
two test copies. Two toolbar Undo actions restored them. `cmp` and recursive
folder comparison verified original bytes after Move and Undo. Private recovery
sidecars remain; original fixture data was not removed. The normal UI drag did
not start a transfer; the authorized native mouse driver did. Covered-window
attempts were refused before sending mouse events and are not counted as passes.
The unchanged provider binary also passed all eleven regression groups.

Authenticated interruption exposed the upload-success/receipt-loss window. The
candidate correctly refused destructive ownership inference; the source was not
retired. The synthetic Google destination contains a 47-byte `External.txt`
(SHA-256 `97ff2e97ee5a49866e2d69a87a05a50c442eef205358b65a4baee43b08539afa`).
Its journal was preserved under
`google-live-9hIyW4/InterruptedLegacyCrossMove-C34513D8` after closing the failed
candidate. The actual drop chose the existing `OpenCommander-Test-0.3.22-…`
folder instead of the intended Google QA directory, so that destination hit is
not accepted. Added explicit bounds and row validation for online drop targets.

New cross-provider jobs now upload under a random preflight-vacant private name,
then persist provider object identity before final publication. Recovery after
a lost rename response requires the same server object ID and exact content;
foreign equal-content final names are refused. Legacy unreceipted final-name
uploads remain fail-closed.

Final nonce regression run: **54 PASS groups**, including all 22 process phases,
in `ntfs/NTFS3G/.build-native/cross-nonce-verified-tests.log`. Lost upload response,
lost rename response, a foreign equal-content final name, re-created provider
clients, source retention and Undo all passed. The earlier fault injection hit
the provider's lower-level temporary upload rather than final publication; that
failed test was corrected to interrupt publication and rerun, not counted as a pass.
Signed Catalyst build and extension identity/sandbox/FSKit checks passed in
`ntfs/NTFS3G/.build-native/cross-nonce-build.log`.

After the user unlocked the Mac, the corrected candidate completed an authenticated
OneDrive-to-Google move recovery on 2026-10-17. Only `External.txt` in the named QA
folders was used. The candidate process was killed immediately after persisting
`publication.json` with a provider identity (job B487A3FA-AC21-45D6-A1E4-4407D0149DCF).
On relaunch, Google opened without reauthentication and offered the pending move.
Resume completed, recorded History entry 61 at 11:04:38 with an enabled Undo
button, and removed the completed journal. Independent Google metadata confirmed
47 bytes and SHA-256 `97ff2e97ee5a49866e2d69a87a05a50c442eef205358b65a4baee43b08539afa`.
History Undo then completed with “1 Aktion(en) rückgängig gemacht”. OneDrive
listed the original `External.txt` again (47 bytes), and an independent Google
listing confirmed its user-visible destination name was absent. The final
drop-target retest is still in progress; this does not yet accept the entire
matrix or authorize a full parity claim.

The corrected candidate then passed a real native mouse copy from the OneDrive
QA file list into blank space in the Google QA file list. The new upload journal
resolved exactly `/OpenCommander-Google-QA-20261017-9hIyW4`, both panes displayed
`External.txt`, and independent Google SHA-256 matched the 47-byte fixture above.
The first attempt was refused by the mouse driver's covered-window guard, with
no events; raising the app and retrying succeeded. No arbitrary target folder
was selected in this accepted retest.

Repeating the native drag displayed the German existing-name conflict dialog;
Cancel preserved the independent destination hash. An Escape-cancelled drag of
`Zweite.txt` created no destination. Dropping that file onto the visible `Backend`
folder subsequently completed at the exact child path, with independent 53-byte
SHA-256 verification against the persisted source snapshot.

The verified incremental candidate was installed at `/Applications/OpenCommander.app`
and launched. The installer passed signature and FSKit identity checks and retained
the previous app at `ntfs/NTFS3G/.build-native/App-before-install.qxYwzd/OpenCommander.saved`.
No host restart, NTFS mount or approval change was performed. The remaining
exhaustive external drag permutations and full Linux parity are still not claimed.

Earlier, the next authenticated live retry was blocked by the computer-use service:
the Mac is locked and automatic unlock failed. Manual unlock was requested.
At that earlier stopping point no unlock bypass, host restart or installation
was performed. The authenticated retry and incremental installation are recorded
above; this historical blocker no longer applies. No full parity claim.

Post-install smoke: the process runs from `/Applications/OpenCommander.app`.
Both OneDrive and Google list their QA folders without another sign-in.
CrossCloudMoves and CloudUploads each contain zero pending job manifests.

## 2026-10-17: early move recovery continuation (under test)

Local-to-cloud move intents now persist before upload, alongside the existing
private upload payload. Recovery requires an unchanged local fingerprint and
the original account. Verified upload receipts bridge into a nested retained-
source journal; ambiguous matching destinations do not authorize source removal.

Cloud-to-local moves now persist download intent before network transfer. After
publication, a serialized local Undo proof bridges into the nested cloud-source
retention journal. Recovery verifies the target directory identity, local content,
remote version and account before completing. Existing copy checkpoints remain
compatible. Added failure/changed-source/account tests and separate-process move
phases in the cloud runner. The signed Catalyst build succeeded, but final tests
and authenticated acceptance are still pending; this code is not yet installed.
The host restarted during the first test/build attempts; those interrupted runs
produced no usable result and were started again. No reboot was initiated here.
Direct cloud-to-cloud early-transfer recovery remains open.

The expanded run passed process phases 12–17 (early upload intent, upload,
source retention, restart Undo; early download intent and local publication).
Phase 18 correctly exposed an invalid session-local ID comparison when resuming
a path-backed download move. Recovery now compares the persisted source path
for path-backed providers, retaining endpoint/account/name/destination/content
guards; stable-ID providers still compare IDs. Full rerun is pending. The
oversized async test entry point was split into helper functions after compiler
memory pressure; interrupted/modified-during-build runs are not counted as passes.

Final rerun: `ntfs/NTFS3G/.build-native/early-move-verified-tests.log` passed all
48 groups, including all 18 separate-process phases and the corrected phase 18.
These are synthetic provider/process-restart checks, not authenticated live
cloud acceptance. The final signed Catalyst build after the ID correction also
succeeded, including extension identity, sandbox and FSKit signature checks
(`ntfs/NTFS3G/.build-native/early-move-verified-build.log`).
The installed app is still unchanged for this continuation.

## Scope and reference

- Fetched `origin/codex/linux-desktop` at `e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`.
  The only commit since `86aaca7` changes website guides/metadata, not Linux app
  behavior. It does not require a new native application feature port.
- Existing uncommitted Mac changes, staged Linux integration, Android version
  changes and release artifacts were preserved. No commit or push requested.
- No computer reboot, new permissions or real-disk formatting performed.

## Verified

- Installed V2 NTFS extension passed a new isolated image write/read test plus
  Foundation and durable file/tree transfers, faults, persistence, and paused
  copy recovery after full detach/reattach. Exact bytes matched. Both image
  attachments were detached normally.
  Log: `/tmp/opencommander-ntfs-20261016.log`.
  Retained image: `/private/tmp/OpenCommander-NTFS-Queue-W6zsAP/test.ntfs`.
- macOS reports no external physical disk. A new Elements test cannot be
  claimed; the user has been asked to attach it.
- Authenticated OneDrive upload restart: isolated test app was killed after
  durable preparation. After relaunch, without reauthentication, its recovery
  dialog resumed into the original online folder. Downloaded bytes matched.
- Authenticated OneDrive download restart: isolated app was killed after
  download-intent publication. Relaunch offered recovery and wrote to the
  originally chosen local directory. SHA-256:
  `e7cad1e60ec3a607395aaf33cd6ff914d3f9efedb498a3b6bb5d12e9b2321141`.
  History showed the source/destination/time; its local Undo succeeded.
- Six separate synthetic processes cover partial upload recovery, original
  source absence, remote-success reconciliation, download intent, reusable
  staged content and changed source/staging/destination refusal.
- Cloud copy history no longer adds a duplicate disabled audit row above its
  working Undo entry.
- Persistent local-to-cloud and cloud-to-local move Undo added. Restoration is
  verified before retiring the other copy; collisions retain both copies.
  Synthetic serialized-history tests passed in both directions.
- Live OneDrive-to-local move and its History Undo passed for the synthetic
  `AAA-Restart-20261016.txt`: original online ID/name restored, local destination
  retired recoverably, and UI reported one action undone.
- Live local-to-OneDrive move followed by app quit/relaunch and History Undo
  passed for `LocalMoveUndo-20261016.txt`. The restored source hash was
  `763950194a170968c6de2de3998dc71fdc7897353c000cae7af5c48ce2473a91`;
  UI reported one action undone. The original recovery copy remains recoverable.
- Graph, durable copy/tree, queue, file safety and NTFS registration/access
  regression suites passed. Current signed isolated Catalyst builds passed.
- Authenticated large upload restart passed. A synthetic 12,582,913-byte file
  resumed at server-confirmed offset 3,276,800; the test app was then killed
  at 6,553,600 and relaunched. It resumed at 6,553,600 without sign-in and
  completed. UI download into `LargeReadback` matched the original with `cmp`
  and SHA-256 `1cf6db96abc65f772194126f8a99aee41e75c38d77b728d388e032d92c06efa6`.
  Both durable job and upload capability checkpoint were removed on success.
- Live acceptance found and fixed bounded `nextExpectedRanges` replies and
  incomplete visible upload placeholders wrongly treated as foreign conflicts.
  Only an account/destination/staged-source-bound saved upload session can
  resume a mismatching placeholder; no session means no overwrite.
- Cloud history now classifies timeout, name conflict and temporary service
  failure using localization keys; the detail dialog includes that failure.
  Final Graph and cloud regressions: `/tmp/opencommander-placeholder-tests.log`
  and `/tmp/opencommander-placeholder-cloud-tests.log`; safety regression:
  `/tmp/opencommander-final-undo-safety.log`.

## New implementation still under acceptance

- Large OneDrive upload sessions retain a private capability checkpoint only
  for validated durable jobs. On retry, verify the staged source fingerprint
  and ask the server for its next byte range. Never forward Graph credentials
  to a preauthenticated upload/status URL. New-client interruption/offset and
  source-change tests cover this; authenticated individual large-file restart
  passed as described above. Nested partially uploaded placeholders still need
  separate acceptance.
- Pending recovery now records per-job failures and continues independent jobs.
  Failed checkpoints remain available on explicit refresh.
- Download checkpoints currently restart an incomplete network download, but
  reuse complete verified staging. This is not byte-range download recovery.
- The new move Undo is implemented/tested independently of interrupted move
  recovery; do not equate the two.

## Remaining

Full native parity is not yet accepted. Outstanding cases include interrupted
cross-backend moves/replacements, legacy staging adoption, authenticated
Google-native export/cache lifecycle, exhaustive provider failure and physical
USB reconnect/multiple-drive/helper-failure acceptance. Toolkit-native controls
are not pixel-identical. No claim of full Linux desktop execution on this Mac.
At this earlier checkpoint the normal installed app had not yet been replaced;
the follow-up installation below supersedes that installation status.
Final read-only physical inventory still showed no external disk. No persistent
test pause flag remains, and the completed large upload has no remaining job
or upload-session capability checkpoint. No computer restart was performed.

## Follow-up continuation

- Refetched Linux reference: still `e3b2981`; no newer app changes to port.
- Added nested incomplete-upload recovery, requiring a per-file saved session.
  Extra remote paths and type changes fail before mutation. Ordinary mismatching
  files without a session remain untouched. Fixture acceptance passed.
- Added durable confirmed cloud replacement intents. Staging and the original
  version proof are published before displacement; the old content is retained
  under a deterministic per-job recovery name. Restart can resume the new upload
  or reconcile completed publication without replay, retaining replacement Undo.
  Unpublished `.preparing-*` directories do not block valid recovery jobs.
- Replacement fixtures cover wrong account, missing original local source,
  interruption after old-content retention, upload failure, unexpected foreign
  destination, completed-publication reconciliation and subsequent Undo.
- Cloud lease/OAuth/runtime/storage, Commander tools, durable files/trees,
  handbook, NTFS access/registration, Graph, remote parsing, safety and transfer
  queue suites rerun; logs `/tmp/opencommander-completion-*.log`.
- Live loopback remote transports rerun with private disposable fixtures:
  `/tmp/opencommander-completion-remote-live.log`. Negative authentication and
  nonempty-directory diagnostics in that log are intentional tests.
- NTFS Foundation and durable transfer/detach/reattach recovery rerun successfully:
  `/tmp/opencommander-completion-ntfs-transfer.log`; retained image fixture
  `/private/tmp/OpenCommander-NTFS-Queue-AImit5`. No physical disk was available.

This closes implementation gaps for nested upload sessions and confirmed online
replacements, not interrupted cross-backend move cleanup, legacy partial-copy
adoption, global multi-window reservations or authenticated Google-native export
acceptance. Full parity must not be inferred from the passing subsets.

## Follow-up live acceptance and installation

- A confirmed replacement in the synthetic OneDrive QA folder survived forced
  termination after retaining the old version. Relaunch required no sign-in;
  explicit recovery published the new 135-byte content, downloaded byte-exactly.
  History Undo restored the original 127-byte content, also downloaded and
  compared byte-exactly. Only synthetic test files were changed.
- Final cloud replacement fixtures and signed Mac build passed. Installed the
  verified incremental build at `/Applications/OpenCommander.app`, retaining
  the prior application at
  `ntfs/NTFS3G/.build-native/App-before-install.2P1JWl/OpenCommander.saved`.
  German settings and configured locations survived. The installed application
  listed OneDrive online files without a new login.
- Post-install NTFS image tests passed Foundation and durable copies plus
  byte-exact recovery after full detach/reattach. Log:
  `/tmp/opencommander-postinstall-ntfs-transfer.log`. The test image was ejected;
  retained fixture: `/private/tmp/OpenCommander-NTFS-Queue-NADOdb`.
- No physical Elements disk was available, no computer restart or additional
  extension permission change was performed. This installation is a tested
  incremental build, not an assertion of complete Linux parity or exhaustive
  external drag-and-drop/provider/hardware acceptance.

## Software-only continuation (Elements explicitly unavailable)

- Linux reference refetched and unchanged at `e3b2981`. No new Elements test is
  required for this software pass; prior physical evidence remains valid for
  its recorded build, not a new hardware acceptance claim.
- Independent delete/extract/duplicate batches now record each failed item and
  continue independent entries without replay. Swift, URL and Cocoa cancellation
  stop the batch immediately. ZIP preparation failures identify the affected
  source and publication failures identify the archive destination.
- Cross-provider and cloud-to-local moves now persist a source-retention intent
  before renaming the source. Local-to-cloud moves use a deterministic recoverable
  sibling name instead of an unjournaled Trash transition. Recovery checks both
  endpoints/accounts and destination bytes before changing a source; completed
  source retention is reconciled without replay. Local destination metadata is
  checked against its original Undo proof as well as its contents.
- Nine separate cloud-fixture processes now include source-retention preparation,
  simulated process loss after local/remote renames and reconciliation/Undo.
  Final passing log: `/tmp/opencommander-software-final-cloud.log`.
- Live testing found global Undo incorrectly selected an older local operation
  when the active pane stayed local after a cloud move. Toolbar Undo and Cmd-Z
  now select the newest eligible entry in shared history, independent of pane.
- Authenticated local-to-OneDrive synthetic move, app restart and global Undo
  passed. Forced termination at the new test-only source-retention checkpoint
  also passed: relaunch offered exactly one move, no new login, recovery completed
  and Undo restored the 125-byte original with SHA-256
  `0454fb4c3083b3f41c2e6e1e973ea1372ee3cbcd3a7527711bb0e0f81043c45f`.
- Safety, queue and Commander tools suites passed; signed Mac builds passed.
  The normal installed app has not yet been replaced in this software-only pass.
- The reverse authenticated move also passed forced termination after remote
  source retention, explicit restart recovery and Undo. Independent download into
  `MoveReadback` matched the same 125-byte SHA-256 above. Both new move journals
  were empty afterwards, and the test-only pause flag was removed.
- That live test exposed sparse Graph listing rows without `parentReference`.
  Move preparation now uses complete fresh metadata; existing sparse intents
  resolve the original stable Graph ID under version/content guards. A nested
  fixture verifies restoration to the correct parent rather than drive root.
- ZIP, extraction and duplicate publication now use durable upload staging with
  a validated persisted action key. Upload failure and removal of original
  temporary output do not lose the prepared result. The final suite including
  sparse-parent and generated-result cases passed in
  `/tmp/opencommander-generated-recovery-tests.log`.
- Foreground operations gate new/resumed queue workers, closing the race through
  the still-visible transfer panel. Existing independent workers continue. Added
  queue-path checks for extraction, duplication and the actual bulk-rename apply
  step. New-job/resume/release tests pass in
  `/tmp/opencommander-foreground-queue-tests.log`.
- Final signed build: `/tmp/opencommander-software-final-gates-build.log`.
  Cloud lease/OAuth/runtime/storage, durable copy/tree, handbook, NTFS policy and
  registration and safety reruns: `/tmp/opencommander-software-final-*.log`.
  Graph and real loopback FTP/FTPS/SFTP key/password suites passed in
  `/tmp/opencommander-software-graph.log` and
  `/tmp/opencommander-software-live-remote.log`; authentication/TLS negative-case
  diagnostics are intentional failures inside otherwise passing tests.
- Removed only three obsolete reproducible Xcode diagnostic build directories
  (`direct-entry-app`, `launch-diagnostic-app`, `experimental-automount-app`) to
  free disk space; source, installed app and rollback backups were preserved.

These new move checkpoints cover the verified-copy/source-retention boundary.
They do not yet turn interruption earlier in a move's upload/download into a
fully resumable move pipeline. Exhaustive cross-workflow reservations, earlier move
transfer interruptions, legacy staging adoption, remaining bulk recovery actions and
authenticated Google-native/export acceptance remain open. Full parity is not
claimed from these passing subsets.

Reachability note: the reference Linux application uses one MainWindow with a
per-profile QLockFile; it does not expose a new-window action. `legacy_staging`
is currently referenced by its transfer engine/store and tests, not by a UI
caller. These should not be presented as missing ordinary Mac UI buttons, nor
does this observation establish complete state-by-state parity.

### Upload-completion receipt continuation

`PendingCloudUpload` now atomically persists ownership evidence only after a
fresh upload completes and its contents/account are verified. Recovery checks
the job, endpoint, account, parent listing, object ID/name, content and provider
snapshot before returning the same Undo payload. Corrupt receipts fail closed;
an existing matching object without a receipt still acquires no destructive Undo.
This closes loss of known completion evidence, not the earlier ambiguous window
between remote success and saving the receipt, nor the full early-move pipeline.

The regression runner additionally exercises receipt creation and recovery in
two separate processes, after removal of the original local source, followed by
Undo. This is synthetic provider testing, not a new authenticated cloud test.
The new restart test exposed session-local provider IDs; receipt recovery now
restores the persisted reference before checking the parent listing. The final
full suite and all eleven process phases passed (exit 0), recorded in
`/tmp/opencommander-upload-receipt-tests.log`. `git diff --check` also passed.
The installed app remains unchanged. A new Mac build was deferred because free
disk space fell below 300 MiB; other projects and user data were not removed.

### Direct Google setup, subsequent installed correction

User requested direct Google setup in the installed Mac app. Live setup exposed
buffering of short stderr OAuth URLs: the child listened on loopback while the
UI waited without a browser action. `RcloneProcessRunner` now drains stderr with
bounded POSIX reads (including EINTR handling). A live child-process regression
proves callback delivery before child exit. Runtime and OAuth suites pass in
`/tmp/opencommander-google-login-runtime.log` and
`/tmp/opencommander-google-login-oauth.log`.

Signed build passed in `/tmp/opencommander-google-login-build.log`; installed
normally at `/Applications/OpenCommander.app` with previous app retained at
`ntfs/NTFS3G/.build-native/App-before-install.NwYjX6/OpenCommander.saved`.
No reboot, disk mount, NTFS approval change or account reset was performed.
Live retry now opens the Google account/consent page in Chrome. Selected the
existing Google account; stopped before Continue to confirm persistent Drive
read/edit/create/delete access through rclone. No direct Google profile has yet
been saved and no authenticated Google file-operation acceptance is claimed.

### Google consent authorized and completed; provider quota blocks acceptance

User explicitly approved persistent Google Drive read/edit/create/delete access.
The expired earlier OAuth flow was restarted; after a stalled Google page was
reloaded, Continue returned the visible loopback `Success!` page. The private
authorized config remains mode 0600 under CloudSetup/D9E6D80E-94AE-44C4-A4EB-B8283CC8EA7F.
No token contents were printed. Listing retries at 22:16 and 22:17 returned
Google HTTP 403 RATE_LIMIT_EXCEEDED/defaultPerMinutePerProject for the shared
client project. One UI listing attempt also reported unsupported/ambiguous
listing; its cause remains unverified because the bounded direct retries were
blocked at root lookup. Do not claim Google file-operation acceptance.

CloudSetupPanel now retains a completed authorization when its first listing
fails, offering Test and Save rather than forcing another OAuth flow. Incomplete
authentication still resets; explicit restart still creates an isolated config.
Build `/tmp/opencommander-google-verified-login-build.log` and runtime regression
`/tmp/opencommander-google-final-runtime.log` passed. Installed signed candidate;
rollback: `ntfs/NTFS3G/.build-native/App-before-install.X7RDCs/OpenCommander.saved`.
This is not an accepted full-parity release.

Synthetic local fixtures only: `/private/tmp/OpenCommander-GoogleQA-20261016-mzISQx`.
Original SHA256 720f1689db3fdd415013acd7c7594b167ea40e86773ce817816f641d9a9a359f;
replacement SHA256 5c9b0d8c0a798421f6c30fe81593a052a75c9dd59080f3133e09b073c937f621.
No Google test upload, modification or deletion was performed.

## Follow-up 2026-10-17: own Google Desktop client

Created the explicitly approved OpenCommander macOS Desktop OAuth client in
project opencommander-511504; the Linux client was left unchanged. Authentication
succeeded. The application-private CloudSetup configuration has mode 0600 and
contains the own client credentials and token; no secret/token was added to Git.
Root listing after restart succeeded without another login (720 entries before
QA creation). Two exact-name duplicate groups explained the earlier root failure.

Cloud listings now exclude ambiguous normalized-name groups with an explicit
localized warning while retaining unrelated entries. Recursive tools still reject
partial listings; collisions remain blocked, but unique destination names can be
used. This is not full ID-based support for Google duplicate names.

Signed build and extension preflight passed; installed in /Applications with
rollback at ntfs/NTFS3G/.build-native/App-before-install.MZtKQ2/OpenCommander.saved.
The saved Google Drive online location opens the root and QA folder in the pane.
Backend live tests passed upload/download, overwrite, move/rename and cloud copy,
each with byte-for-byte readback. Only synthetic data was used in
OpenCommander-Google-QA-20261017-9hIyW4; retained for UI verification.
Logs/fixtures: ntfs/NTFS3G/.build-native/google-live-9hIyW4/.
UI transfer acceptance and isolated client regression were still running at this
checkpoint. Concurrent source changes interrupted earlier compiler test runs;
do not count these interrupted runs as passes. Full Linux parity remains unclaimed.

Final follow-up checks: isolated CloudClientTests and all eleven restart phases
passed (google-collision-snapshot-tests.log); cloud storage regression passed
(google-storage-tests-rerun.log). App Cmd-C/Cmd-V from the local synthetic file
to the direct Google QA folder completed with readback verification, visible
progress and history item 48 at 08:23:05 including Undo. After normal app quit
and relaunch the saved Google location listed root and the same uploaded test
file without another login. No computer reboot was initiated. Duplicate-name
entries remain deliberately excluded with a warning, not fully supported.
Google preview was invoked but no rendered preview was confirmed in this run;
do not count it as accepted. Google-native document export and the complete
Google/Finder drag-and-drop matrix remain unverified.

### Later 2026-10-17 preview/export acceptance

Replaced the invisible Catalyst document preview path on macOS with a native
QuickLookUI QLPreviewView panel. The bridge retains the downloaded file through
the close callback; local/media/iOS fallbacks remain. Build and signature
preflight passed; installed with rollback App-before-install.JQwnpN.
Visible native preview accepted for local Prüfung.txt and an actual native
Google document exported to DOCX, including Unicode content in the rendered view.

Synthetic Google document 1CLiNKcOyHoXe7moOrMhWU5neeXMJki5duRlZR74NBf8 was created,
populated and read back through the Drive/Docs connector, then placed only in the
existing Google QA folder. App Save export to google-live-9hIyW4/Export succeeded;
DOCX XML was parsed and checked for the exact Unicode sentence and final sentence.
Provider metadata confirmed the original still exists as a native Google Doc in
the same QA folder. No personal files were altered.

The standard CUA drag attempt did not demonstrate a committed transfer. Requested
specific authorization for the existing local native mouse test driver; do not
count Google/Finder mouse acceptance as complete until its result is recorded.

### 2026-10-17 approved native mouse tests completed

See `ios/DRAG-AND-DROP-STATUS.md` for evidence and remaining scope. Direct Google
text file -> opposite local pane and -> Finder passed with byte-identical readback.
Actual native Google document -> Finder passed as a valid DOCX with verified XML
text. Installed Unicode-path correction (rollback App-before-install.Es0ANF),
CloudClient regression suite and eleven restart phases passed. Login survived the
app replacement/relaunch without a new authorization prompt. No computer reboot,
NTFS mount, personal data change, commit or push performed. Full Linux parity and
the remaining drag matrix are not claimed by these three successful live cases.
