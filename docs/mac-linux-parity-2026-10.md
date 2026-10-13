# Linux → macOS parity transfer, October 2026

Current fixed reference: `origin/codex/linux-desktop` at `9db136167489b46bc6c7ad0a96375b8487c9be6e` (Linux 0.3.25rc10, not a public release).
Previous upstream batch reference: `9d79ef1fc47d1ff57e1496336dc02098d3388cce` (0.3.24).
Earlier continuation reference: `60ea0635bea0451ae370fddb586773143619552a`.
Previous shared baseline: `4e72b174ec0ea2579819a0425de0990055edf05f`.
Mac starting revision: `2f96726e07ccd687e825740c71ab255bb023ca3f`.

This is a work-in-progress checklist, **not a declaration of complete parity**.
Linux uses Qt/Python/rclone; Mac uses UIKit/AppKit/Swift and direct Graph/server
clients. Equivalent reachable behavior must be implemented and tested rather
than copying Linux mount or GUI code into the Mac target.

## Implemented in this batch

- OneDrive read-only requests: three attempts maximum, exponential 2/4-second
  fallback delays, server Retry-After respected, 30-second per-request budget.
  Authentication/permission errors and mutations are never replayed.
- OneDrive display-only listing cache: 32 directories maximum, five-minute age,
  at least ten-second cooldown after transient failures (longer Retry-After is
  respected), explicit timestamp/warning above
  the file list. Tools, transfers and metadata checks always request fresh data.
  Successful or uncertain mutations invalidate the cache; disconnect clears it.
- OneDrive context menu: copy logical path, open provider website, create a
  read-only sharing link with explicit anonymous-access warning. Copy/open are
  separate user actions; failed sharing requests are not automatically replayed.
- Refresh of the current online folder preserves surviving selected IDs;
  navigation up highlights the departed folder; other navigation clears selection.
- Operation progress shows elapsed time with explicit seconds/minutes/hours/days;
  the timer stops when the operation finishes or the controller is destroyed.
- Hidden History is not rebuilt on updates; opening it renders current records.
- Online file/tree listings and archive listings honor the global hidden-files
  preference. Malformed online timestamps render as an em dash.
- Local Undo verification is cancellable between entries and SHA-256 blocks;
  cancellation before the mutation leaves the destination unchanged and permits retry.
- Mac system libarchive provides TAR/TGZ/BZ2/XZ/7z/RAR archive navigation,
  preview materialization and selective extraction in the existing pane. Online
  server/OneDrive extraction accepts these formats too. All headers are validated
  before output creation; links, special files, traversal and duplicate/case-clashing
  paths are rejected. Limits: 100,000 entries / 4 GiB unpacked, 128 MiB previews.
  Decoder/encryption limitations fail safely; no shell extraction is used.
- Mac settings are an embedded non-modal panel. A separate settings control
  remains available during transfers; an already-open panel stays interactive.
  Appearance rebuilds are deferred until both transfer and panel have finished,
  preserving the active panes and cancellation controls.
- Local regular-file copies now use `DurableFileCopy.swift` and a saved queue
  through clipboard paste and non-replacement pane transfers: private staging,
  fsynced atomic journals, checkpointed
  blocks, explicit pause/resume/cancel, byte-for-byte prefix verification,
  source identity checks, exclusive destination publication and worker locks.
  Completed targets are validated on inspection. Volume UUIDs (when supplied by
  the filesystem), device IDs and source identity guard restart recovery.
  Publication-window recovery is explicit and validates inode/size/mtime.
- Queue: 1–4 concurrent local copy jobs, read/write and keep-both-family overlap
  reservations, private persistent index, explicit pause/resume/cancel, per-card
  compact/details persistence and completed-card removal without file deletion.
  Startup never automatically starts recovered jobs. Progress updates reuse the
  existing card controls, with at most four display updates per second.
  Completed queued copies feed normal History/Undo; a single versioned history
  envelope stores transfer IDs with the records to avoid duplicate callbacks.
  Directory/symlink checkpoints and phased move/replacement adapters are now
  implemented (see continuation below). **Not yet:** cloud checkpoints, legacy
  staging adoption or complete cross-platform transfer parity.

## Commit-by-commit remaining work

| Linux commit | Mac status / remaining behavior |
| --- | --- |
| `37482ba` | Native non-ZIP archive browsing/preview/selective extraction ported with safety tests, including the Linux RAR5 fixture. Still audit bounded media caching, empty-area context menus, queued work and unsupported provider metadata. |
| `19d75a1` | Direct OneDrive share menu ported. Installed Google Drive/Dropbox/iCloud provider actions still need native integration and tests. |
| `e77b549` | Existing server/OneDrive pane navigation and saved names remain. Audit place edit shortcut, credentials/session passphrases and stale-navigation protection. |
| `47d6b3e` | Existing Mac disk discovery/mounting remain. Audit direct place activation, generation guards and shutdown behavior against Linux tests. |
| `cd00195` | Online tree now shares local resizable-width settings. External rclone/provider cloud actions and drag previews still need parity work. Linux /proc/GVFS detection must not be used on Mac. |
| `0c57b5c` | Non-modal settings during transfers ported and live-tested. Destinations-only places bar implemented; Connections moved to the title toolbar. |
| `1017509` | Local file/tree queue/UI, volume identity, replacements and explicit restart recovery implemented and tested. Cloud integration remains. |
| `908010c` | Explicit legacy staging recovery still needs implementation after durable queue support. |
| `d578ae7` | Bounded Graph retries, display cache, shared reads, per-waiter cancellation, account isolation and pane invalidation ported with mocks. Google Drive OAuth setup pending. |
| `8dfedab` | Linux live rate-limit evidence is not Mac evidence; native UI behavior must be tested separately. |
| `ca4522c` | 1–4 concurrent local file/tree jobs, overlap locks, per-job controls/cards, restart recovery and phased moves implemented. Cloud transfers remain. |
| `71e2586` | Per-card compact/details state persisted and live-tested across restart for local copies. |
| `6f5762b` | Explicit elapsed-time units, online refresh selection retention, robust timestamps, lazy hidden History and cancellable undo hashing ported. Lazy column formatting, progress coalescing, idle transfer timers and verified rclone partial restart remain. |
| `1867ffe` | Shared OneDrive read invalidation and account guards added. Mutation guards consult the authoritative local queue for delete/rename/Undo/ZIP/local-cloud transfer paths; parent/child and pending-name families tested. This is not yet a global lock across all legacy/cloud workflows or simultaneous app windows. |
| `b3cfd84` | Saved place ordering and provider vector icons implemented; live reorder/icon checks still pending. |
| `84a3365` | Native generated offline handbook with accessible illustration and five chapter anchors added. Not the full 18-chapter Linux screenshot handbook yet. |
| `85a9e92` | Native unit/live evidence maintained here; complete interactive acceptance-plan parity still pending. |
| `30084bb` | Active-only elapsed time survives restart. Interrupted tree files continue before new files/completed-output revalidation; checkpoint progress retained. Damaged completed output still prevents publication. Cloud partial resume remains pending. |
| `60ea063` | Non-modal help, filter status/clear/Escape, local diagnostic copy added. Live checks and regression described below. |

## Verification

Mock Graph tests cover read throttling/backoff, Retry-After, long delays, mutation
non-replay, cancellation, sharing permissions/link validation, explicit cached
listings, cooldown, fresh tool reads and cache invalidation/access denial.
File-safety tests cover duration units and malformed duration values.
No personal cloud item is shared, changed or deleted by these fixtures.

Verified 2026-10-11:
- `tests/run-onedrive-tests.sh`: 19 passing groups.
- `tests/run-swift-safety.sh`: 11 passing groups.
- `tests/run-commander-tools-tests.sh`: three passing groups.
- `tests/run-remote-tests.sh`: profile/parser group plus live FTP, FTPS,
  SFTP-key and SFTP-password variants passed against disposable local servers.
- Debug Mac Catalyst arm64 build with experimental NTFS write condition passed;
  deep/strict code-signature verification passed.
- Native UI: real OneDrive listing loaded; context menu contains the new actions;
  anonymous-access warning displayed and cancelled without creating a link;
  refresh retained the selected folder; opening hidden History rendered timestamps
  and action/Undo controls. Transient cache fallback is covered by mock Graph
  fixtures, not by forcing throttling on the personal account.

The development build was launched for verification. `/Applications/OpenCommander.app`
was not replaced. These changes have not been committed or pushed in this batch.

Graph behavior references:
- https://learn.microsoft.com/en-us/graph/throttling
- https://learn.microsoft.com/en-us/graph/api/driveitem-createlink

Verified 2026-10-12 (continuation):
- Graph regression: 20 passing groups, including visibility/timestamp policies.
- Safety regression: 15 passing groups, including cancellable Undo verification,
  TAR/TGZ/BZ2/XZ/7z native fixtures, path/link/special-file/case-collision attacks
  and the actual Linux RAR5 stored fixture.
- Experimental NTFS-enabled Mac Catalyst development build succeeded and its
  signature passed verification. Live UI browsing of a TAR.XZ archive and its
  subfolder worked; Quick Look displayed the Unicode text fixture correctly.
  Double-click archive navigation and generic labels passed in the latest build. Live extraction
  and Undo verification passed: selected folder extraction excluded the other
  file, and Undo removed the published test folder while retaining README.txt.
- Latest experimental NTFS-enabled Mac build and deep/strict signature check passed.

Further continuation (2026-10-12):
- `DurableTreeTransfer`: whole-root private staging, regular-file checkpoints,
  hidden entries, dangling links (not followed), retained replacement backups,
  exclusive publication and original-source quarantine for phased moves.
  New root journal guard: 64 MiB maximum, O_NOFOLLOW, volume/device checks.
- Queue adapters now accept local trees, links, replacements and moves. History
  remembers the retained original; Undo restores it only after fingerprint checks.
- Shared Graph display reads coalesce across browser clients; cancellation is
  independent per waiter. Disconnect/login generation guards prevent stale token
  refresh or old account results from restoring a previous account.
- Fresh mutations invalidate both display caches and trees. Cached transient
  failures schedule display-only reload after the cooldown, never retry writes.
- Transfer cards reuse controls, save active-only duration, idle timers stop,
  and diagnostics copy locally. A full queue reports the rejected admission.
- History stores action keys; switching language translates new/known legacy
  labels. Localization cache and current language are protected for worker use.
- Filter no-matches/clear counts are explicit. macOS correction/suggestion input
  is disabled for filter fields so Escape is not consumed by spelling suggestions.
- Native offline help is non-modal, isolated from remote content with CSP and a
  navigation allowlist. Five chapter links and an accessible two-pane SVG diagram.
  Help remains accessible during legacy transfers; appearance changes are deferred.
- Table-cell date formatters are reused; reused icons reset their text. UI folder
  size excludes named UUID recovery directories, but includes ordinary hidden files.
- Test groups: Graph 22, file safety 16, tree transfer 4, file copy 8, queue 4,
  offline handbook 1. Latest help/size Catalyst build succeeded.
- Live: replace tree via Cmd-C/Cmd-V conflict prompt, verify Unicode/hidden payload,
  Undo restores the old target. Cmd-X/Cmd-V moves the tree, retains the original
  privately and Undo restores it. Completed test cards removed through UI (no
  file removal). Help anchors work; local navigation works while help stays open.
- Test-only directories retained under `/private/tmp/opencommander-directory-ui-20261012`.
  No personal cloud content changed/shared. No install, commit, push or release.
- Host SSD was nearly full; three older, unmounted synthetic NTFS fixtures were
  gzip-compressed with SHA-256 decompression verification. Their recoverable .gz
  copies remain in their original fixture directories; source/personal data untouched.

Cloud/path-reservation continuation (2026-10-12):
- `CloudConnection` contains metadata only (name, type, explicitly selected
  config path, remote, optional relative root), max 100 profiles. Credential data
  does not enter preferences or History. Private config must be regular, owned by
  the user, mode 600; its remote type is checked before each native request.
- AppKit `RcloneRuntime` installs only from official HTTPS downloads.rclone.org,
  validates release format/minimum 1.75.2 and the unique published ZIP SHA-256,
  bounds downloads/extraction/output, validates the executable version, keeps the
  upstream README/license and checks private binary SHA-256 before reuse.
  No shell, stderr logging, inherited rclone credentials, FUSE or system mounts.
  Native child requests are cancellable and have total/time/output limits.
- Actual runtime install verified at 1.75.2. Its 3 MiB README required an 8 MiB
  documentation bound. Installed privately under Application Support/OpenCommander/Runtime.
- Command plan uses immutable changes, one high/low-level attempt and literal
  arguments after `--`. `copyto` does not support create-empty-src-dirs in 1.75.2;
  directory operations use `copy` / `move` with explicit empty-directory flags.
- `CloudFileClient` reuses the server client's pane, recursive transfer/tools,
  byte progress, source-version checks and read-back verification. Cloud names
  may include colon/backslash; backend-specific name checks remain in the client.
  Mutations invalidate display reads. Cloud moves retain and verify a private
  recovery copy; cloud removal moves into a recovery name (not the provider trash).
  Metadata/hash versions are conservative guards, **not server-side conditional
  atomic updates**. Recovery is retained on uncertainty; no destructive replay.
- Online local-to-cloud staging now compares the staged content with the source
  snapshot before upload, rather than accidentally hashing the source twice.
- Settings offers named/configurable Google Drive, Dropbox, iCloud and rclone
  OneDrive profiles, file chooser, optional root, read-only connection test,
  persist/show/hide/reorder/remove and embedded pane activation. Existing direct
  Graph OneDrive remains separate. Removing a profile does not delete credentials.
  **New-account OAuth/password setup wizard is NOT implemented yet.** The UI
  explicitly says an existing private rclone configuration is required.
- Synthetic adapter tests: Unicode/colon/backslash upload, fresh verified
  download, same-provider move with retained/verified backup, stale-source refusal
  and recoverable removal (3 groups). Actual rclone local-alias test confirms
  Unicode tree/empty-directory copy and immutable overwrite refusal. No personal
  provider credentials or cloud files were used.
- Latest Graph 22 groups; safety 16; local tree 5; queue 5; regular copy 8;
  handbook 1. Full live FTP/FTPS/SFTP-key/SFTP-password regression passed against
  disposable loopback servers using the existing test environment.
- Latest experimental NTFS-enabled Catalyst arm64 build succeeded. Cloud settings,
  new provider icons and mutation guards still require native live verification:
  the Mac became locked, and computer-use could not proceed. Requested manual unlock.
- Six further unmounted synthetic NTFS images were losslessly compressed and
  compared by SHA-256; uncompressed originals removed only after verification,
  .gz recovery copies retained. Free space recovered to ~1.3 GiB but remains tight.

Remaining parity gates (not exhaustive): new-account cloud setup; durable cloud
queue/checkpoints and adoption of legacy staging; global resource reservations
across all workflows/windows; bounded online media/cache lifecycle; empty-area
context menus/provider sharing integrations; full illustrated 18-chapter help and
interactive acceptance-plan parity; complete native UI regression and iOS build
compatibility check; real per-user FSKit mounting gate. No full-parity claim.

Final verification before the locked-UI gate (2026-10-12):
- New tree rollback phase: if a move's source changes after destination
  publication, the verified payload returns to private staging and the verified
  previous destination is restored. Changed source and copied payload remain;
  retry refuses the changed source before any destination mutation. Six tree
  test groups pass, including this injected race and unfinished-file-first resume.
- Browser shutdown cancels pending display retries, advances read/selection
  generations and releases its stale clipboard. Main-queue notifications declare
  the MainActor executor without changing synchronous login ordering; new actor
  isolation warnings are gone in the latest build.
- FSKit gate now **passes on an isolated new 64 MiB test image** using the
  already-installed NTFS extension: Unicode/create/read-write/copy/rename/replace/
  delete/truncate/fsync. Independent Apple NTFS read-only remount verifies exact
  Unicode bytes, 517-byte data and rename/delete persistence. Both mounts detached.
  Fixture: `ntfs/NTFS3G/.build-native/fskit-fixture.GiSS2f/test.ntfs`.
  This does not assert universal writing on every NTFS disk or test a personal drive.
- Latest experimental Catalyst build succeeds; regular-copy 8, tree 6, queue 5,
  Graph 22, safety 16, tools 3, cloud adapter 3, runtime 4, handbook 1 groups;
  four real loopback server variants pass. Personal cloud authorization remains
  untouched and the current new cloud UI has not been live-verified while locked.
- Still a security/verification gate for rclone profiles: pin/freeze an explicitly
  approved configuration/account during a request and handle refresh-token rotation
  without silently accepting a changed account. Current checks validate the private
  file and remote type, not a server-side atomic account/configuration snapshot.
  Do not claim production-ready direct cloud parity or publish this prototype.

External-filesystem verification (2026-10-12):
- Generic iOS device compatibility build also succeeds without signing. This
  verifies compilation, not visible iPhone/iPad behavior.
- New `tests/run-ntfs-transfer-tests.sh` creates only its own 64 MiB virtual image,
  validates virtual/image/size before each mount, uses no sudo and detaches on exit.
  Foundation and durable regular/tree APFS→NTFS copies pass, including a source
  with mode 600, an older modification time, Unicode and hidden child data.
  These are content tests, not a promise that every unsupported NTFS metadata
  attribute is preserved by the experimental extension.
- Found an actual recovery bug: FSKit changes both st_dev and the reported volume
  UUID on detach/reattach, even for the same image. New checkpoints use a validated
  NTFS boot serial/geometry identity (read-only $Boot stream when the raw device is
  held exclusively), with stable Disk Arbitration partition UUID fallback. Other
  volumes retain reported UUID/device guards. Legacy records cannot silently adopt
  an unknown changed identity.
- Device numbers are normalized only after the stored volume identity is verified;
  inode/size/time, payload-prefix checks and exclusive publication still apply.
  Test passes after 1 MiB pause, full detach/reattach and 3 MiB byte-equal resume.
  Malformed headers, changed serials and offset Data slices are unit-tested.
- Latest Catalyst build with the native identity bridge succeeds. Regular-copy
  groups now 9; tree 6. Separate tests remain under private temporary fixture
  directories; no personal disks were attached, written or modified.
- Locations refresh uses sorted JSON keys so equivalent preferences do not cause
  spurious button recreation. The Mac-only clipboard path is separated from the
  unchanged iOS fallback without unreachable compiled statements.
- Non-modal settings: navigation remained usable in the other pane; theme toggle
  worked during an actual 256 MiB copy with elapsed-time and Cancel controls still
  visible. Both test copies were explicitly undone; the original settings restored.
- `tests/run-durable-copy-tests.sh`: eight passing groups, including publication
  recovery, changed destination refusal and changed volume UUID refusal.
- `tests/run-transfer-queue-tests.sh`: four passing groups; actual two-worker
  scheduling, pending-name conflicts, overlap policy, persistence, card removal
  and running-index restart with explicit resume.
- Local queue live UI: 128 MiB copy, normal History Undo, pause at 59%, compact
  card persistence through actual application exit/relaunch, explicit resume and
  byte-for-byte completed data check passed. A separate attempted live cancel
  raced with completion; it is not recorded as a passed live cancellation test.
  Cancellation is verified by the engine fixtures.
- Repeated Graph, file-safety and Commander tool regressions passed (20/15/3 groups).
- Local copy queue integration and final UUID/recovery Mac builds passed. Source
  and output test data were private fixtures, not personal or online files.
- Directory/cloud checkpoints, queued replacements/phased moves, legacy recovery
  and the other cloud/UI rows above remain open. No complete-parity claim is made.

Presentation and clipboard continuation (2026-10-12):
- Removed unnecessary folder reopening after appearance/language rebuilds, which
  silently activated the right pane. Existing panes retain directory, local
  selection/filter/tree and the embedded online navigation controller.
- Online appearance updates recolor the existing controls and update translated
  headings/buttons without reconnecting or duplicating actions/recognizers.
- Local cut intent is pinned to the system pasteboard change count. An external
  clipboard change discards the old local paths/move intent before either local
  or cloud paste. Native visible regression remains blocked by the locked Mac.
- Updated Catalyst and generic iOS builds both succeed. Strict/deep Mac signature
  verification succeeds. Cloud adapter (3), queue (5) and handbook (1) regression
  groups pass again. No installation, commit, push or release was performed.

Required next native checks after manual unlock:
1. Keep the left pane active with a selection/filter and an online folder open in
   the other pane; change theme/language and verify active pane, both paths,
   selections, tree expansion, online headings and unchanged account session.
2. Cut a synthetic local file, replace the clipboard in Finder or a text editor,
   then paste locally and online. The old cut must not move any file. Repeat a
   normal cut/paste and confirm it still moves with History/Undo.
3. Verify new place names/order/provider icons and an explicitly selected cloud
   configuration in the embedded pane. Do not approve new account grants silently.
4. Complete the interactive acceptance matrix against the frozen Linux reference.
   The locked UI is a verification blocker, not evidence of complete parity.

Direct Google Drive native documents remain a separate open gate: unknown export
sizes must not be mistaken for zero-length ordinary files. Implement explicit
export semantics and bounded verification before enabling full transfer parity.
Provider format reference: https://rclone.org/commands/rclone_lsjson/ and
https://rclone.org/drive/#importexport-of-google-documents .

## Unlocked native verification and continuation — 2026-10-13

- Restarted the experimental Mac bundle after manual unlock. Installed app and
  its permissions/FSKit extension were not replaced. SSD now has ~13 GiB free.
- Native regression found that `UITableView.isEditing` (for location reordering)
  hid all ordinary accessory controls. Language dropdown, theme switch, visibility
  switches and disclosure indicators now also provide editing accessories.
  Confirmed visible and interactive after rebuilding and restarting.
- Theme and German→English→German changes retain the selected local folder,
  filter, current directory and loaded OneDrive pane. Command+C still uses the
  selected left pane. Original German/light settings restored. OneDrive loaded
  through its existing account; no new login grant or account setting was changed.
- Filter with no matches shows an explicit message; a single Escape clears it
  locally and online. Downloads visibility off removes its place button; on
  restores it. Reordering actions move a location row down/up; original order
  restored. Provider icons were verified visually in the places bar.
- Real Finder clipboard test: cut a synthetic folder in OpenCommander, then copy
  the same folder in a new Finder tab and paste into the private test target.
  The job is a copy; source remains and Unicode/hidden file bytes match. Normal
  cut/paste is a move with retained recovery source; Undo restores the source.
  Both test operations undone through the native Undo button, their finished
  cards removed without deleting recovery data and the extra Finder tab closed.
  Automated Cmd+Z did not invoke the expected operation in one attempt; native
  button Undo passed. Do not claim a passed keyboard Undo regression from that.
- Local/online columns now share one locked, reused Gregorian date formatter,
  same yyyy-MM-dd HH:mm shape and system timezone. ISO fractional/whole timestamps
  and invalid/oversized values are tested. Native side-by-side date display passed.
  Local dark-mode heading colors now match the online pane's readable accents.
- Unknown native-document export sizes remain unknown (not zero bytes) and do
  not invalidate the entire cloud listing. Download/move/removal refuses before
  mutation with an explicit localized explanation. Cloud removal now snapshots
  and verifies all content before/after relocating it to recovery. Four synthetic
  cloud adapter groups pass. Full native Google document export is still open.
- Offline help now covers the same eighteen topics as Linux, with native Mac
  controls and honest platform/implementation limits in German and English.
  Eighteen chapter links and navigation to Tools were verified in the live panel.
  Two handbook groups pass. The Linux screenshot gallery, handbook search/print
  and full interactive acceptance documentation are not ported yet.
- Added matching free-area context menus locally and online: New Folder, Paste,
  Refresh, Search, Copy Folder Path. Live local menu created a folder in its own
  private fixture; row context menu remained intact. Both local and online blank
  filtered lists show the menu. Online Search starts at `/` in its actual online
  pane, with match-case off. No search, upload, sharing or account mutation run.
  Fixture retained: `/private/tmp/OpenCommander-DirectoryMenu-20261013.7uMDzl`.
- Mac builds/signatures succeed with these changes. Graph 22, safety 16, cloud
  adapter 4 and handbook 2 test groups pass. Copy/tree/remote regression and the
  final iOS compilation are being rechecked below; record outcomes, not starts.
- Old temporary Python fixture environment lost its dependencies. Initial server
  run failed before startup, not an app transfer failure. Preflight now reports
  missing imports; the harness avoids SIGPIPE writing to an exited fixture.
  New isolated test environment installed from PyPI under
  `/private/tmp/OpenCommander-RemoteQA-20261013.scdyt6/venv` (Paramiko 5.0.0,
  pyftpdlib 2.2.0, pyOpenSSL 26.4.0, cryptography 50.0.2).
- Asked for action-time confirmation to upload only newly generated synthetic
  data to a new OpenCommander-QA-20261013 folder in OneDrive/iCloud/Google Drive.
  No reply yet; no live cloud write/upload in this continuation. The direct rclone
  config/account pinning and new-account wizard gates remain open. No release,
  installation, commit, push or complete-parity claim.

Final continuation regression outcomes (2026-10-13):
- Regular copy: 9 groups; tree copy/move/replacement: 6 groups; safety: 16 groups;
  Graph/display policy: 22 groups; cloud adapter: 4 groups; offline handbook: 2.
- Loopback server run exits successfully with all four real variants passing:
  FTP, FTPS with validated test CA, SFTP key, SFTP password. Authentication
  refusal tests are expected failures, not accepted credentials or weakened TLS.
- Final generic iOS device build with the Mac-only menu additions succeeds.
  Latest native Mac build and deep/strict signature verification succeed.
- The experimental app is left running with existing OneDrive in one pane;
  temporary filters cleared and German/light preferences restored. No live cloud
  write performed while the requested confirmation remains unanswered.

## Approved three-provider live QA and conflict repair — 2026-10-13

The subsequent user reply **“Ja du darfst alles”** confirmed the specifically
proposed synthetic-data workflow: new `OpenCommander-QA-20261013` folders in
OneDrive, iCloud Drive and Google Drive; copy/overwrite/move/Undo and recoverable
cleanup only. This is not permission to change account access, grant security
permissions, publish, install, or touch personal files.

Fixture: `/private/tmp/OpenCommander-CloudQA-20261013.PpiWHS`. Two different
`Kopiertest.txt` versions, a Unicode filename/content and an empty directory.
Originals/readbacks remain locally for evidence; no personal file was used.

Verified through the experimental native application:

- Local complete tree → OneDrive Graph → iCloud FileProvider → Google Drive
  FileProvider, preserving Unicode names, empty directory and exact file bytes.
- Google Drive B → iCloud A with Replace, native Undo restores A; source B intact.
- Google Drive B → existing OneDrive A with Replace; download readback matches B;
  native online Undo restores original OneDrive A, retaining new B for recovery.
- Restored OneDrive A → existing local B with Replace; readback matches A; local
  Undo restores B. Cancel leaves B unchanged with no extra file. Keep Both creates
  `(2)` with exact A bytes, leaves B untouched; native Undo removes only the alias.
- Same-account OneDrive A → B with Keep Both moves the same remote item ID;
  online Undo removes the target alias and restores original A path. Cut status
  was explicitly confirmed before navigating; an earlier automated cut that
  failed to activate was cancelled without mutation, not counted as a move pass.
- History visibly includes real logical OneDrive paths and date/time. Cloud
  transfer progress and directory loading indicator observed during operations.

The first iCloud B → Google Drive A replacement succeeded, but Undo failed: the
provider staging `previous` file was no longer available and the visible new
file had already been moved into recovery. This is a real failed test, not a
pass. Its precise provider reconciliation cause is not established. Fixed:

- Check that the backup exists and (for new records) matches its persisted
  content snapshot **before** displacing the current destination during Undo.
- FileProvider copy replacements make and verify an independent previous-version
  copy in Application Support `OpenCommander/CloudRecovery/<UUID>/previous`.
  The destination snapshot is rechecked before displacement; the actual displaced
  content is checked before publication. Rollback prefers the actual displaced
  object so a racing edit is not discarded. Recovery copies are not auto-purged.
- Undo copies back the backup, verifies restored content, and retains the backup.
  A persisted publication phase supports retry after cancelled verification.
- Retested the exact failing iCloud→Google Replace/Undo sequence successfully;
  byte comparisons match original A and independent backup. Repeated replacement,
  exited/restarted application, then native Undo; exact A restored again.

Online copy replacement uses a verified backup-and-publish sequence, rather
than an unconditional destructive content PUT. Old target is moved with its
version guard into `.OpenCommander-Replaced-<UUID>`, fresh content uploaded and
read back, and only a vacant target is eligible for safe rollback. Undo checks
both content trees, retains the new version under `.OpenCommander-Undo-<UUID>`,
then restores the previous name. Whole folders replace fully, **not merge**.
New online→local copy history records store the logical source separately from
temporary staging paths and keep persisted local Undo functionality.

Cleanup verified:

- Google QA root moved through native Trash to
  `GoogleDrive-haenggi85@gmail.com/.Trash/OpenCommander-QA-20261013`; original A
  readback matches. No root remains in `Meine Ablage`.
- iCloud QA root moved through native Trash to
  `Library/Mobile Documents/.Trash/OpenCommander-QA-20261013`; original A readback
  matches. No root remains in `com~apple~CloudDocs`.
- Exact newly created OneDrive root item
  `408CCB3F9988F1F0!s117256ae371b4415bcae2e2c8d73bd56` moved to the OneDrive
  recycle bin with native confirmation; refreshed exact-name filter has no match
  and History reports recycle-bin destination. No permanent purge performed.
- Local private evidence and independent backups retained. Older QA folders and
  personal data were not cleaned or modified.

Regression evidence: safety **19** groups (missing/changed backup refuses before
destination writes; independent recovery survives discarded provider staging;
persisted snapshots; publish rollback; racing source edit retained), previous
Graph **22**, cloud adapter **8**, copy **9**, tree **6**. Latest final rebuild
and repeated cloud adapter regression outcomes are recorded below when complete.

Still open: full durable cloud queue/restart, cross-backend move Undo, persistent
online replacement Undo (currently session-only), cloud audit-card Undo,
Replace on online moves (explicitly unavailable), native Google-document export,
direct-cloud new-account wizard/config identity pinning, full handbook gallery
and all remaining interaction parity gates. FileProvider local
readbacks do not prove Google/iCloud server synchronization. No installation,
commit, push, release or full Linux-parity claim in this continuation.

### Additional offline handbook parity

- Added an in-panel localized search bar, case-insensitive literal queries,
  highlighted current/other matches, match counts, wrapping Next/Previous, and
  explicit no-match/unavailable state. No external navigation or resource loading.
- The initial native WebKit find API reported matches but did not visibly scroll
  this Catalyst panel; its native find toolbar also used the OS language rather
  than OpenCommander's language. These attempts were not counted as passed
  navigation. Replaced by narrowly scoped trusted host search over the app's own
  offline document. Queries are separate `callAsyncJavaScript` arguments, escaped
  literal expressions; highlights use text nodes, never `innerHTML`/`eval`.
- Native live test: lowercase `cloudrecovery` finds **1/1**, visibly scrolls to
  the History chapter and highlights `CloudRecovery` in orange. `rückgängig`
  finds **11**; Next changes 1→2, Previous 2→1. Nonexistent combined query reports
  no matches. Autocorrection/capitalization/spellcheck disabled for search text.
- Added system print/PDF preview with print-specific light styling, heading
  pagination and no search colors in print. Native preview shows **10 A4 pages**;
  first two page previews inspected, then Cancel. No printer selected, no physical
  print job submitted and no PDF written. System print controls follow macOS's
  system language; the document/search controls follow app language.
- Handbook HTML safety/layout **2** groups pass; new Node test validates the
  shipped script syntax, literal regexp metacharacters, Unicode, markup-looking
  queries and case-insensitive behavior. This adds no Node dependency to the app.
  The full Linux illustrated screenshot gallery remains open.

Latest completed outcomes before final source verification:
safety **19**, cloud adapter **8**, copy **9**, tree **6**, queue **5**, handbook
**2** plus search-script test. Mac builds and the generic iOS build succeeded
after the recovery changes; final all-source Mac/iOS results are recorded below.

Final all-source verification for this continuation:
- `opencommander-cloud-help-final-mac.log`: BUILD SUCCEEDED, deep/strict bundle
  signature verified. `opencommander-cloud-help-final-ios.log`: BUILD SUCCEEDED.
- Repeated final Graph **22**, regular copy **9**, tree **6** groups succeed.
  Safety **19**, cloud adapter **8**, queue **5**, handbook **2** and the separate
  literal-search script test succeeded with the implemented source changes.
- `git diff --check` succeeds. Work remains uncommitted on
  `codex/mac-linux-parity`; no installation or external repository write.

## Refreshed upstream pull and bidirectional safety alignment — 2026-10-13

- Fetched origin again. Mac branch upstream is already current at `2f96726`.
  Linux advanced from `60ea063` to `9d79ef1` (five commits, version 0.3.24).
  Imported the full latest `linux/` tree via an indexed binary Git patch after
  verifying that those paths had no local changes/untracked files. This preserves
  all Mac work and does not merge the divergent branch's older iOS/NTFS files.
  The imported index matched the remote Linux tree exactly before local backports.
- New upstream work: bounded cloud retry waits and explicit pending-pause wait;
  one progress/details presentation with controls independent of path length;
  setup validation/iCloud password wire format; Google project quota cooldown;
  read-only Google SHA-256 fallback after an evicted FUSE file's EIO, with cache
  guards and verification progress distinct from copied bytes.
- Mac engines report saved-prefix/whole-tree hash checks as separate phases and
  byte counters. Queue keeps the already copied byte count, persists active
  verification time, distinguishes a requested pause/cancel from a stopped worker,
  clears dead pending requests after restart and retains the last failure on resume.
  Native cards have a separate controls row, bounded route labels, a compact
  summary and separate copied/checked counters; no fabricated zero transfer speed.
- Mac rclone setup validates the selected section before accessing the provider:
  token presence/type, OneDrive drive selection, iCloud encoded-password/device
  verification, malformed/encrypted/duplicate config refusal. Error identifiers
  contain no credential values. This does **not** close the existing immutable
  account/config identity and refresh-rotation gate or implement a setup wizard.
- Display fallback lists are now bound to a private, bounded, validated config
  digest. A changed account/config purges cached rows and cooldowns; a config change
  during a read refuses its result. Authentication failures take precedence over
  quota text in both implementations. The digest is session-only and never logged.
  This display guard is not immutable configuration pinning for mutations, and
  token rotation conservatively forces a fresh display read.
- Native child stderr is drained with a 16 KiB retained limit and classified into
  sanitized error keys, never displayed/logged raw. Google project-quota cooldown
  is at least 60 seconds. Cloud display reads coalesce, have three attempts maximum,
  2/4-second waits, a cancellation watchdog, a 32-directory / five-minute explicit
  fallback cache and in-flight invalidation. Authentication clears fallback data.
  Tools/mutations use fresh reads; writes are not replayed. No credentials/accounts
  or existing mounts were changed by these mock tests.
- Linux backport of the Mac Undo preflight: missing/changed backup refuses **before**
  moving the visible current version; new backup snapshots persist. Legacy histories
  still require a readable backup. New initially unverifiable backups cannot later
  silently become a different previous version. Linux also reports missing rclone
  during password preparation explicitly instead of passing None to subprocess.
  Known Undo failures in current and saved Linux histories are translated using
  the selected UI language without rewriting paths or guessing unknown messages.
  String backup paths from resumable journals are normalized before snapshotting.
  Local source modifications remain uncommitted on top of the imported 0.3.24 code.
- The Linux `/proc`/FUSE-cache SHA proof is not copied into macOS. The Mac native
  FileProvider is not that cache namespace; bypassing a local pending write on a
  guessed server would be unsafe. Durable direct-cloud transfers remain open.

Final verification for this upstream batch:
- Isolated Python 3.12 test environment:
  `/private/tmp/OpenCommander-LinuxParity-20261013.6oTwz4/venv`, PyPI pinned
  requirements (PySide6 6.11.2, libarchive-c 5.3, pytest 9.1.1). Uses the existing
  checksum-verified app-private rclone and an explicitly nonexistent test config,
  not personal default credentials. Initial missing-rclone failure was test setup;
  repeat runs succeeded. Latest imported suite collected 338 tests before additions.
- Final Linux cloud/config/listing/login/verification/formatting/protocol,
  external-cloud/share and recovery-preflight subset: **106 passed, 3 skipped**
  (`opencommander-upstream-linux-final-expanded-20261013.log`). Skips require
  FUSE/rclone mounts unavailable on macOS. Recovery/config-specific subset separately
  passes **14** tests; this overlaps the combined run and is not added to its count.
- Qt offscreen pause/cards/verification/cloud-auth subset: **7 passed**
  (`opencommander-upstream-qt-final-portable-20261013.log`). Two tests now explicitly
  select German rather than relying on the host locale. An attempted broader six-test
  UI selection had **4 passed, 2 failed**: those two start actual transfers and read
  Linux `/proc/self/mountinfo`, which does not exist on macOS. No fake mount data was
  supplied and no complete Linux-host/GUI/package/FUSE pass is claimed.
- Mac cloud adapter **12**, runtime/config/process **5**, copy **10**, tree **7**,
  queue **6**, Graph **22**, safety **19**, handbook **2**, Commander tools **3**
  groups pass. Runtime local-rclone integration separately passes **6** groups.
  Initial Swift closure/variadic localization compilation issues were repaired;
  the new identity-test fixture now advances its injected clock beyond a quota
  cooldown before expecting a fresh response; production cooldown remains enforced.
- Final all-source Mac Catalyst build: **BUILD SUCCEEDED**
  (`opencommander-upstream-bound-mac-20261013.log`), deep/strict signature verified.
  iOS device-platform control build, signing disabled: **BUILD SUCCEEDED**
  (`opencommander-upstream-bound-ios-20261013.log`). Both include the final display
  identity guard and sanitized authentication-priority changes. Whitespace checks
  pass (upstream CRLF CSV checked with `core.whitespace=cr-at-eol`).
- Attempted native UI test: `cgWindowNotFound`; enabled-surface inventory explicitly
  reports the Mac locked. Requested manual unlock; did not bypass the lock. Prepared
  only a private synthetic 128 MiB local fixture at
  `/private/tmp/OpenCommander-UpstreamUI-20261013.QQNspr`; no transfer started.
- Asked for Linux host/SSH details and clarified whether bidirectional parity is
  intended. No reply yet. No Linux host execution, account grant, personal cloud
  upload, install, release, commit or push in this refreshed-pull continuation.
- A final fetch confirmed the same Mac `2f96726` and Linux `9d79ef1` references.
  Full parity remains open; importing source and these partial regression gates
  do not establish equivalence for every reachable state.

## New codex/linux-desktop commit integrated — 2026-10-13 evening

Fetch discovered `9db1361` after the previous checks. All 32 changed source,
documentation, public example and release-draft paths were imported into the
working tree, preserving the prior Mac changes and Linux safety backports. The
new CHANGELOG section was inserted with a separate patch because the local safety
section occupies the same insertion point. No whole-branch merge of old iOS/NTFS
sources, credential registration, release, commit, push or app installation.

Native additions:
- New durable jobs start as compact single rows with name, state, percentage,
  bounded progress and the applicable controls. Details remains per-card and
  persisted; includes timestamp, complete route, copied/checked counters and time.
- Transfer list is docked below the file panes instead of covering them. Its top
  divider resizes the list and saves the height without forcing a fixed maximum.
- Pointer-time local drop checks are lexical and use cached directory shape, with
  no FileProvider stat on every mouse movement. Self, descendants and same-parent
  no-op drops refuse before transfer. Tree hover expands after 650 ms and edge
  scrolling uses a timer. Direct-online trees have equivalent hover loading,
  generation/account guards and loaded-ancestry cycle/no-op refusal. Authoritative
  transfer validation remains required at release, including symlink/race checks.
- New-account cloud assistant is embedded in the same window for Google Drive,
  OneDrive, Dropbox and iCloud. Each attempt has a fresh UUID/private configuration
  under Application Support/OpenCommander/CloudSetup, distinct from all existing
  accounts. The existing explicit configuration chooser remains accessible.
- Configuration questions use bounded structured backend responses and bounded
  RCLONE_STATE/RCLONE_RESULT child environment answers; credentials are not CLI
  arguments. iCloud password encoding uses the verified backend's stdin interface.
  Raw errors and credential values are not placed in History or diagnostics.
- Browser routing accepts only the verified child process's fixed loopback auth
  endpoint. Passwords, device codes and phone choices remain explicit. iCloud SMS
  request/resend reuses the backend state with a 30-second cooldown; `sms` is not
  submitted as a code. Fatal errors reset to a new login, not an advanced password
  question. Only successful setup, config validation, fresh list validation and
  profile persistence may report a saved connection. Global file shortcuts are
  suppressed while the setup panel is open; Escape cancels it.
- The Mac wizard currently uses backend OAuth, not the new Linux publisher-native
  PKCE client loader or publisher packaging checks. Public registrations and
  complete authenticated new-account flows remain explicit gates. No claim that
  all providers are now identical or universally approved for distribution.
- Help documents the wizard, private credential storage, independent website
  sign-in, single-row transfers, resizing and remaining direct-cloud limitations.

Current verification:
- Linux cloud/config/native-PKCE/public-client/package-audit/protocol/recovery
  subset on this Mac: **127 passed, 3 FUSE-dependent skipped**. Qt offscreen auth/
  iCloud/compact-height/progress subset: **27 passed** after making the test window's
  default German language explicit. The initial run had 12 label failures due to
  the English host locale; behavior was not changed to satisfy those labels.
  Tests use a private Python environment and no personal default rclone config:
  `/private/tmp/OpenCommander-LinuxLatest-20261013.7nfdLa/venv`.
- Swift cloud adapter **12**, runtime/setup/process **7**, queue **6**, safety
  **20**, handbook **2** groups pass. Optional verified-rclone integration adds
  **3** groups: private metadata, credential-free iCloud service/Apple-ID question,
  stdin encoding and local alias tree/immutable-conflict checks. Earlier transfer,
  Graph and Commander tools gates remain separately documented.
- Actual backend testing caught missing `--all` for iCloud; now explicitly selects
  service Drive and reaches the Apple-ID question without any account credentials.
- Native app initially trapped on a duplicate `cloud_setup_required` localization
  key; corrected to a distinct required-field key. `tests/check-swift-localization.py`
  now verifies all seven Swift dictionary literals against duplicate keys. Initial
  Swift nested-type/responder-name collisions were also corrected before rebuild.
- Signed Mac Catalyst and unsigned iOS control builds succeed; native app starts
  again. Final bundle is deep/strict signature valid. Whitespace gates pass.
- Visible native checks: F5 copied a private file and nested folder (source and
  destination SHA-256 match); both compact rows completed at 100%. Expanded Details
  shows timestamp and route without duplicating summary. Divider resize saved
  approximately 306.88 points; list height, expanded first card and compact second
  card survive app restart. Original iCloud/Downloads pane paths restore afterward.
- Visible iCloud setup: new panel opens in the existing window; shows its private
  storage guidance; actual backend reaches Apple-ID; empty Continue is rejected;
  Cancel closes the panel and **zero direct-cloud profiles** were saved. No Apple
  ID, password, token, consent grant, authenticated cloud write or account change
  was used. Receiving SMS and completing real provider OAuth remain unverified.
- Automated native mouse drag from the private fixture to its target folder did
  not emit a transfer. This is not counted as a successful DnD acceptance check.
  Manual native drag/lift/hover/escape and external-app permutations remain open.
- A test-coordinate mistake triggered Undo on a previous QA deletion. The app
  refused content verification before displacement; relevant QA delete records
  remain `destinationReverted=false` and `completed=false`. No personal file change
  resulted. No repeat Undo or automatic cleanup/replacement was attempted.
- Private fixture/evidence remains at
  `/private/tmp/OpenCommander-LatestUI-20261013.vjUTCd`; its two new test-copy cards
  and history entries are retained. Installed `/Applications` app is untouched.

Full parity is still open: publisher-native PKCE/build identities, immutable
account/config pinning for mutations and refresh rotation, durable direct-cloud
queue/restart, cross-backend/persistent online Undo and online-move replacement,
native Google exports, bounded external-edit/media lifecycle, global reservations,
full illustrated handbook and complete real-Linux/native interaction acceptance.

Final source checks: all 32 paths changed by `9db1361` are present. Blob comparison
matches the upstream versions for 26 paths; the remaining six retain Mac ignore
rules and the documented Linux safety/locale backports (`.gitignore`, CHANGELOG,
cloud_config, ui, test_cloud_config, test_ui). Final fetch still reports `9db1361`.
`opencommander-latest-complete-source-mac-20261013.log` and
`opencommander-latest-complete-source-ios-20261013.log` both record BUILD SUCCEEDED;
Mac deep/strict signature, JSON manifest and duplicate/whitespace checks pass.
The test panel was closed after persistence checks; original normal panes remain.

## Commit/push batch — publisher OAuth parity, 2026-10-13

The user requested complete parity plus commit/push. Latest fetch still references
Linux `9db1361` and Mac `2f96726`; no unrelated source reset or branch-wide merge.

Native additions in this batch:
- Public/custom desktop identities use the Linux schema. Microsoft and Dropbox
  use native S256 PKCE, fresh state/verifier, fixed official authorization/token
  endpoints, the same scopes and `http://localhost:53682/` redirect. No confidential
  client secret. Loopback binds 127.0.0.1 only and checks Host, state, single code,
  bounds and denial. Wait/exchange cancel and time out; no raw responses are logged.
- A successful exchange requires bounded Bearer/refresh tokens and integral expiry.
  Only a new empty owned 0600 non-symlink/non-hardlinked configuration may be seeded;
  existing account files refuse unchanged. OneDrive drive selection and fresh list
  check still precede profile saving. Failed retries use another fresh private UUID.
  Cancel invalidates the callback request ID before closing, preventing stale browser
  callbacks. Existing Graph/device-code accounts are not migrated.
- Google installed-desktop identities are written privately, not sent in arguments.
  The optional expert fields appear in the existing setup window. Microsoft/Dropbox
  do not show a secret field. Empty fields choose bundled identity/backend defaults.
- Xcode packaging accepts the same three `OPENCOMMANDER_*_OAUTH_FILE` variables as
  Linux and calls the same schema validator. Bounded input, all-identity validation,
  private generated resources and stale-identity removal. No real app identity,
  user account credential, token or new registration is bundled by this change.
  Publisher setup is documented in `docs/mac-cloud-oauth.md` and offline Help.

Verification rerun before committing:
- `opencommander-final-cloud-oauth-20261013.log`: **8 groups passed**, covering
  schema rejection, RFC S256 vector, callback/port/cancel/timeout checks, a real
  synthetic loopback socket, bounded mock token HTTP exchange, new config safety
  and shared publisher packaging. No real provider account or consent used.
- Final native regressions: cloud adapter **12**, runtime/setup/process **7** plus
  optional verified-rclone **3**, local copy **10**, tree/move **7**, queue **6**,
  Graph **22**, safety **20**, Commander tools **3**, handbook **2** groups pass.
  Remote profile/path/MLSD/SFTP parser checks also pass; the real FTP/SFTP
  loopback fixture option was not rerun. Its build now includes the new OAuth source.
  Adding Help's publisher guidance required updating its regression to preserve
  the localized base as a prefix for that chapter; other base text remains exact.
- Linux cloud/OAuth/recovery/package subset again **127 passed, 3 FUSE skips**;
  Qt offscreen subset again **27 passed**. No complete Linux-host/FUSE/live UI claim.
- Mac signed and iOS unsigned control builds succeeded after OAuth integration;
  Mac deep/strict signature passed. Native UI starts, opens the OneDrive expert
  field in the same window, refuses `invalid-synthetic-id` with a German message
  before invoking backend/browser, and Escape closes it. Original panes retained.
  Final cancellation-guard Mac rebuild also succeeds with a valid deep/strict
  signature; the change is inside the Mac-only assistant, not the iOS source path.
- No personal cloud writes, provider grants, real tokens, installed app replacement
  or existing-drive write in this batch. Browser login/refresh/production approval
  acceptance remains unverified and requires approved provider registrations.

Full parity is **not complete**. Remaining durable direct-cloud queue/restart,
persistent/cross-backend online Undo, mutation identity pinning/refresh rotation,
Google document export/external edit lifecycle, global reservations, failed-action
history, live Connections refresh and full native/Linux interaction gates are
still listed in the manifest. Commit/push publishes this tested source progress,
not a release or a declaration that all reachable behaviors are identical.

## Continuation: 2026-10-14

Code commit `16e7923` closes the build and discovery problems identified in the
previous batch. NTFS now builds verified, separate arm64 and x86_64 archives and
combines them for the Mac extension. The native image tools remain separate.
The universal Mac application, extension and UI-test target build successfully;
both architectures are present in the application and extension executables.
All twelve native NTFS image-test groups pass on arm64 and on x86_64 under
Rosetta, including writes/reopen, disk-full/fault propagation and hibernation
refusal. Only newly generated image files were written.

Connections is now a list inside the current application window. It refreshes
every five seconds, on request and after mount/eject. A visible test created a
new HFS+ image, observed it in the panel, ejected that exact image with the panel
control, and observed its removal while the panel stayed open. Discovery no
longer coordinates/enumerates every provider's contents: an unavailable cloud
account previously held up the entire list. Explicit access records recent
disabled-domain observations for up to five minutes; successful access clears
that observation. No provider credentials enter this state.

Local and online panes now share plain-click replacement, Command toggle and
Shift/Command-Shift range selection over the displayed order. Pure policy tests
cover ranges, sorted order and stale anchors. Visible plain-click checks pass;
physical modifier-click acceptance is still pending. Online ZIP, extraction and
duplicate operations now retain verified upload Undo proofs. Bulk delete,
archive, duplicate and export failures are persisted in history; precise
per-item failure/recovery coverage remains an open audit item.

`sh tests/run-remote-tests.sh --live` creates its own temporary Python environment
and runs real loopback FTP, FTPS, SFTP-key and SFTP-password fixtures. All four
groups passed, including transfer bytes, navigation/search/rename, recovery,
cancellation, TLS/host-key refusal and wrong-password protection.

The UI target no longer inherits macOS 26.2 as its minimum. The isolated debug
application uses `com.github.niklaus85.OpenCommander.MacUITests`, separate defaults,
private temporary files and its own transfer queue. `sh tests/run-mac-ui-tests.sh`
builds that clone without registering an Apple app/profile. The Xcode UI runner
still times out while enabling this host's automation mode: Developer mode is
disabled and no administrator authorization is available. No OS security setting
was changed. Existing CUA access independently verified plain selection, F5 copy
with matching bytes, timestamped History and Undo after relaunch, default search
path, unchecked match-case and absolute-path results, and the Connections flow.
An automated CUA drag did not lift/publish a file and is not counted as a pass.

The [GitHub verification for the code commit](https://github.com/Niclas85/OpenCommander/actions/runs/38474662853)
has successful Apple and Linux jobs. Linux ran **403 passed, 3 skipped**, then
built and uploaded its package. Qt/PulseAudio runtime dependencies are installed
before tests; the existing verified recent-rclone installer prepares the backend
instead of relying on Ubuntu's obsolete backend. The transfer regression now
opens the current compact card's Details and verifies its totals, duration, rate
and actual copied bytes. Apple ran safety, cloud client/discovery/configuration
lease tests, **31 NTFS package tests**, and a successful iOS Simulator build.
The independent Android job still fails its pre-existing incomplete iOS locale
key-set gate; the workflow is not reported as entirely green.

Current FSKit `--check-only` finds the installed registered module but FSClient
omits it. That neither proves it disabled nor confirms present write activation.
A fresh isolated mount/write acceptance needs administrator authorization.
The installed application, existing disks, personal cloud data and permissions
were not changed in this continuation. Durable direct-cloud restart, cross-backend
move Undo, Google native-document export/external editing and the remaining
interaction gates are still tracked in `ios/MAC-LINUX-PARITY.json`; full parity
has not been declared.
