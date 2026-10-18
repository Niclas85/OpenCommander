# External drag and drop — 8 September 2026

This is an incremental implementation, **not complete Finder parity**.

## 2026-10-18: native browser promises and location-bar acceptance

Safari and Chrome's synthetic local image promises reached OpenCommander with
exact PNG bytes. A live Safari drop exposed a hidden private NSItemProvider
transport filename. Temporary representations now receive a visible fallback
name instead; genuine originals and intentional hidden names are unchanged.
Moving a mere temporary browser copy is explicitly refused without deleting
anything. The provider runner now has 15 passing groups, including transport-
name regression, web-URL rejection and slow/cancelled provider ownership.

Location-bar dragging is independently typed and cannot consume file drags.
The reverse negative test exposed an unwanted text-file import from a location
button: it now advertises only an own-process private type, explicitly excluded
from file loading, rather than exporting its label as plain text.
Native reorder, context alternatives, Escape, persistence and successful drop
during a test-image attach passed after fixing the drag-end delegate callback.
The authorized mouse driver now requires the visible external window's
synthetic test title, not just its app process identity.

Details and limits: `../docs/mac-acceptance-2026-10-18.md`. Arbitrary third-party
apps and complete Linux manual acceptance are not inferred from these cases.

## 2026-10-17: archive-member drag acceptance

Added lazy, bounded extraction of selected archive members and directory trees.
Archive drags are copies even when Move is selected. Native AppKit promises
provide Finder destinations; short-lived process-local tokens retain the
original provider for internal drops. Catalyst otherwise serializes a folder
as ZIP bytes. Temporary incoming sources now bypass deferred local execution:
their staging stays owned through conflicts and completion instead of being
released before the queue starts.

Live synthetic fixture: `ntfs/NTFS3G/.build-native/google-live-9hIyW4`.
Passed with the authorized mouse driver and independent byte comparisons:

- ZIP text member to the opposite local pane.
- ZIP folder to the opposite local pane, preserving `Ordner/Nested.txt`.
- ZIP text member directly to the named Finder test window.
- ZIP folder directly to Finder, preserving the nested file as a directory.
- Existing local destination opens Replace/Keep/Cancel; Cancel preserves bytes.
- Original ZIP SHA-256 remains
  `e4130c4898f4f69aff4124c12cd43c3c7e7bc808b656ecdccc4ea59ed2a8a7d2`.

Automated: eleven provider groups, 25 archive/safety groups (ZIP, TAR, compressed
TAR and 7z selected-member cases), 39 cloud groups including eleven separate
restart phases, seven queue, ten durable-copy and seven durable-tree groups.
Signed Catalyst build passed and was installed for live acceptance; previous
app preserved at `App-before-install.2twblQ/OpenCommander.saved` below the
native build directory. No reboot, NTFS mount or security permission change.
One provider test compile initially failed for lack of disk space; its rerun
passed. Finder operation-zero attempts are not counted as successful drops.
Authenticated Google archive uploads also passed: both `Archiv.txt` and
`Ordner/Nested.txt` appeared in the synthetic online folder. Independent rclone
readback matched SHA-256 `d6c4f669cf875730decb8bd04695fbc0eac4b6b0558645405ad57d4b8dc39093`
and `c710dd1760ea6f8dc82fd0cbc6d88816f72126c7eb8c526484de5c968418ed80`
respectively. UI showed byte progress and the verification-readback phase before
reporting completion. Saved Google authentication survived the rebuild/relaunch.
Toolbar Undo of the uploaded archive folder completed with “1 Aktion(en)
rückgängig gemacht”; the folder disappeared from the live listing while the
original archive and local/Finder copies remained intact.
Additional reruns: Graph 24, Commander tools 3, handbook 2, NTFS access policy 3
and registration 3 groups passed. No physical-disk write claim is made.
Exhaustive external application/modifier cases and full early-move interruption
recovery remain open; these passes do not assert complete Linux parity.

## Implemented

- Incoming file URLs, files and directory representations from other apps.
- Outgoing physical files and folders expose both NSURL and a typed file
  representation, including directory drags from the tree.
- Drops onto a physical folder in either list/tree target that folder; empty
  list space targets the current directory. ZIP and read-only targets reject.
- Actual drag items determine internal transfers, not mutable selection state
  or a stale global source-pane reference.
- The Copy/Move toolbar choice is captured when the drop starts. External Move
  is explicit, and refused when the provider only supplies a temporary copy.
- Provider temporary files are copied to private staging **inside** their
  callback and held through conflict dialogs and file operations. Only owned
  staging is cleaned; security scopes are released explicitly.
- Existing Keep/Replace/Cancel, progress and undo paths are reused; concurrent
  drops during preparation/transfer/conflict dialogs are rejected.
- A nonresponding provider times out after two minutes; late completions cannot
  start a transfer. Preparation failures never delete source files.
- Enter/Cmd-C/Cmd-V/Delete/Space are no longer intercepted by file commands
  while editing the destination path or another text input.

## Verification

### 2026-10-16: native Finder file promises

Replaced outgoing online Catalyst drags with AppKit `NSFilePromiseProvider`
sessions. Finder chooses the destination, then the app downloads and validates
the content before copying it there. No synchronous lazy file URL is published.
External drags offer Copy only; the cloud source is never implicitly deleted.
Internal drops carry short-lived, process-local selection tokens so the existing
online conflict/undo/account-isolation paths remain available.

Live passes in the new empty `NativeFinderExport` fixture:
- Direct OneDrive `Prüfung.txt` → Finder, SHA-256
  `f22397714deba47daec0996619e9df49eb2b51c90e3525318495726342db8a30`.
- Direct OneDrive `Zweite.txt` → Finder, SHA-256
  `3ac6eee7bf357defaf5106d9c6c1f4e947c3326d1402d308c6657e1b9e359bbd`.
- Direct `External.txt` → Finder: byte-for-byte match.
- Command-selected `Ordner` + `ExternalFolder` → Finder in one native session:
  both arrived, recursive comparison matched their nested contents.
- Native online `External.txt` → local `Right/Ziel`: byte-for-byte match.
- Native online `External.txt` moved into online `Ziel`; UI verified the same
  item ID there. Undo emptied `Ziel` and restored the source ID in its parent.
- Escape cancelled a native online drag without starting a transfer.
- OneDrive and cloud-client regression suites passed; signed normal-host build
  and signature/FSKit preflight passed.

The native hit test normalizes coordinates before converting to Catalyst's UI
scale. The mouse driver now sends motion deltas as well as absolute positions.
Use a visibly unobstructed Finder drop point; a drag ending with operation 0 is
not a successful transfer. Finder must be raised above other applications;
an obscured target was correctly rejected during the test.

Installed the normal host at `/Applications/OpenCommander.app`, preserving the
stable `NTFSModuleV2` identity. Previous app backup:
`ntfs/NTFS3G/.build-native/App-before-install.KToLuh/OpenCommander.saved`.
The installed app launched with the existing German settings and locations.
This acceptance is scoped to Finder export and the above regressions, not a
claim of exhaustive Linux parity or interrupted-cloud-job restart coverage.

### 2026-10-16: authenticated OneDrive acceptance follow-up

New live fixture: `OneDrive online:/OpenCommander-DnD-QA-20261016-iA4mZf`.
Only synthetic files from the existing local fixture were used.

Passed through actual mouse/UI actions:

- Local Unicode file dragged to OneDrive and downloaded by dragging onto the
  local `Right/Ziel` folder row. Original and returned SHA-256 match:
  `f22397714deba47daec0996619e9df49eb2b51c90e3525318495726342db8a30`.
- Duplicate-name upload opens Replace/Keep Both/Skip/Cancel dialog. Replace
  completed; History recorded source, destination, time and an enabled Undo.
  Undo restored the original OneDrive item identity.
- Explicit Move dragged the online file into online `Ziel`; opening that folder
  confirmed the item. Undo emptied that folder and restored the parent item.
- Online preview downloaded and displayed the expected synthetic text.
- Command-selected local folder plus second file uploaded together. The nested
  folder downloaded back via drag; `cmp` confirmed the descendant bytes.
- Escape cancelled an online drag before any destination transfer.
- OneDrive and cloud-client regression suites passed again, and the signed
  Catalyst build passed. Authentication survived another rebuild/app restart.

Follow-up after the user put the app in front: the lazy `public.file-url`
experiment deadlocked Catalyst's synchronous pasteboard resolution against a
MainActor download. The process sample in `/tmp/opencommander-hang-20261016.txt`
identified the wait. Removed that representation, terminated only the hung
test process, rebuilt and verified that the UI and saved login work again.
Do not reintroduce a URL callback that needs the blocked main actor.

Additional live passes: Finder → online `External.txt` and `ExternalFolder`,
then multi-selection download into local `Right`. SHA-256 matches the originals
for both the file and the folder's `Nested.txt`. A direct online folder promise
also reached Finder as `ExternalFolder 2`; its descendant hash matches.
Text-file export to Finder is still under investigation and is not accepted.
The driver retains its foreground/fixture guards and slower external trajectory.
`preferredPresentationStyle = .attachment` alone did not fix text export.
Using generic `public.data` did not fix it either and was reverted. Publishing
an asynchronous file representation under `public.file-url` also blocked the
app (`/tmp/opencommander-urlpromise-hang-20261016.txt`); it was removed. Only the
typed file representation is retained, never a lazy file-URL representation.
OneDrive and cloud-client suites passed again (`/tmp/opencommander-acceptance-*.log`).
The production app has NOT been replaced: external single-file export and live
interrupted-cloud-job recovery still prevent complete release acceptance.

Production installation remains unchanged pending the remaining acceptance.
The online fixture and recovery copies remain available for continuation.

### 2026-10-16: authorized native mouse acceptance

The user explicitly approved the CoreGraphics test driver. The isolated app at
`/tmp/OpenCommander-MacUITests.rTbs9X/Build/Products/Debug-maccatalyst/OpenCommander.app`
was tested against `/private/tmp/OpenCommander-MacUITest-20261015-iA4mZf`.
The driver now focuses only the isolated bundle, waits for activation, sets
click count/event number/pressure, validates endpoints against its visible
window and supports Escape cancellation. No permissions were changed.

Passed via real posted mouse sequences, visible UI and filesystem verification:

- File copy into an empty destination; source retained and SHA-256 identical.
- Undo of that copy removes the destination and retains the source.
- Move into the empty destination removes the source; Undo restores it.
- Shift-selected two-file drag copies both, with completed transfer cards.
- Existing-target conflict dialog appears; Cancel preserves both files' hashes.
- Nested folder dragged onto a destination folder row lands in that folder;
  descendant bytes match and Undo removes the copied subtree.
- Escape during a drag starts no transfer and creates no destination subtree.

Root cause: directly opened roots lacked `listingDirectory`; successful
enumeration now populates it. Isolated startup regression verifies directly
opened roots, non-directory rows and a nonexistent directory. Eight native
file-provider groups and the Mac Catalyst build pass.

Additional acceptance on 2026-10-16:

- Finder → OpenCommander: synthetic file and folder with nested file copied.
- OpenCommander → Finder: both exported successfully; all three copies of each
  test payload have identical SHA-256 hashes, with originals retained.
- Folder from the file list → a destination in the folder tree: completed at
  the intended Right/Ordner path, nested bytes identical. Undo removed only the
  copied folder and retained the original.
- Re-ran eight file-provider groups, 17 cloud-client groups, 23 safety groups,
  six transfer-queue groups, ten durable-copy groups and seven durable-tree
  groups; all passed. These are automated regressions, not live cloud approval.

Cloud acceptance remains blocked/incomplete:

### Latest authentication verification — 2026-10-16

The last device-code login succeeded in the correctly signed isolated app:
OneDrive displayed 28 root entries. Quit the app normally, verified that its
process had exited, relaunched it and selected OneDrive online. It loaded the
same 28 root entries without a device code, browser interaction or login prompt.
This accepts live Keychain-backed session restoration across an app restart
(including acquiring a new access token from the stored refresh credential).
No token values were extracted or logged. No Mac reboot was performed and the
production app remains unchanged. Earlier authentication blockers below are
historical and superseded by this result; file-transfer acceptance is separate.

The next real device login ended with `The network connection was lost` before
the account became connected. Device-token polling now tolerates up to three
transient transport failures, respecting the polling interval, expiry and
session cancellation. Certificate errors remain terminal; refresh-token and
file mutation requests are unchanged. Regression tests cover recovery, the
retry budget and certificate refusal; the OneDrive suite and signed Catalyst
build pass. Live authentication still requires completion in the browser.

Sign-in follow-up: Microsoft authentication reached the isolated app, but saving
the token failed with Keychain status -34018. The ad-hoc test signature had no
keychain entitlements. Rebuilt successfully with Apple Development signing,
team WB497999XX and the isolated bundle's own keychain group. Detached the test
NTFS extension again before launch, re-signed retaining the generated
entitlements, and verified the complete bundle with `codesign --verify --deep
--strict`. A fresh device-code login is required to verify token persistence;
this is not yet accepted as an end-to-end authentication pass. Production
installation and its keychain group were not changed. On the subsequent UI
inspection iCloud did list 12 entries; its earlier loading delay is therefore
not evidence of permanent unavailability. No iCloud transfer has been accepted.

- The isolated app requires its own Microsoft device-code sign-in. The sign-in
  page was opened, but successful authentication was not observed. Production
  tokens were not copied into the test app.
- iCloud stayed in loading state and displayed the delayed-provider message;
  no file transfer was attempted there.
- Google Drive listed successfully and the UI created the empty test directory
  `Meine Ablage/OpenCommander-DnD-QA-20261016-iA4mZf`. Both subsequent mouse-test
  attempts aborted at the foreground-app guard, before posting any mouse events.
  Thus no Google Drive drag transfer is accepted yet. The empty directory is
  retained for continuation, not silently removed.

This accepts the listed local/Finder/tree cases, NOT the complete matrix:
authenticated online-provider drags, independent hover expansion/autoscrolling,
and the remaining external multi-selection/move/conflict cases still require
acceptance. The production installation has not been replaced. Local writes
were confined to the synthetic fixture; only the named empty test directory
was created on Google Drive.

Signed arm64 Mac Catalyst debug build succeeds. Existing unrelated compiler
deprecation warnings remain. Native Foundation provider tests exercise
files/folders, Unicode, ordered multiple selection, duplicate removal,
temporary file and directory staging, unsafe suggested names, original
preservation, rejected web URLs, errors, raw file URLs and timeout handling.

```sh
xcrun swiftc -swift-version 5 ios/OpenCommander/FileDropTransfer.swift \
  ios/tests/FileDropTests/main.swift -o /tmp/opencommander-file-drop-tests
/tmp/opencommander-file-drop-tests
```

Visible path-field navigation was exercised successfully. A synthetic Finder
fixture was prepared at `/private/tmp/OpenCommander-DragUI.ZVs81E`, but the
actual cross-application mouse drag was **not run**: focus was changing to other
user tasks. Finder windows temporarily minimized for setup were restored;
the two test Finder windows were closed. No desktop files or external disks
were copied, moved or deleted. No production release was made.

## Earlier diagnosis (superseded by the dated acceptance above)

Further diagnosis: the isolated runtime trace recorded `drag beginning` and
repeated destination `canHandle` queries but no committed drop. Inspection found
that directly opened FileEntry roots never populated `listingDirectory`, so
`offersDirectoryDrop` rejected the current directory's background. Successful
directory enumeration now caches that directory shape. The isolated launch
regression passed for Left/Right roots, regular files and a missing directory;
the Mac build and eight provider groups also pass. CUA's drag call produces only
a single movement event and does not reliably lift the source. End-to-end mouse
acceptance remains pending, not passed. A separate native mouse test driver has
been proposed to the user; do not run it without their explicit approval.

2026-10-15 follow-up: user confirmed that the isolated left-to-empty-right
mouse drag did not transfer a file. Corrected background drop proposals to use
`unspecified` instead of claiming an existing destination row, made decorative
empty-state backgrounds noninteractive, and stopped selection callbacks from
reloading/replacing potential source cells (local and online panes).
The updated isolated Mac Catalyst app builds and the eight native provider test
groups pass. CUA dragging still produces no transfer; a successful physical
mouse retest has NOT been observed. This is not accepted as fixed yet.

## Still required

- Finder → folder row/tree; external multiple selection, cancellation, conflicts,
  and explicit Move/Undo regression tests. Basic bidirectional file/folder drags
  and local list-to-tree copying are now accepted as described above.
- Actual provider applications, network/cloud volumes, and iPad Files testing.
- Finder-style same-volume default move, Option/Command drag overrides,
  spring-loaded folders and native cross-app move cursor negotiation. UIKit
  permits `.move` proposals only for allowed sessions; external imports use a
  `.copy` proposal while the explicit toolbar choice controls our file action.
  Do not describe this behavior as identical to Finder.
- Plain web links, aliases and extracting virtual ZIP entries by dragging are
  not implemented by this file-transfer change.

The app Help contains the Copy/Move procedure and these main limitations in
German and English (other languages fall back to English for the new entries).

## 2026-10-17 direct Google Drive live mouse acceptance

User explicitly approved the existing local mouse driver. The driver now has an
opt-in installed-app fixture mode, rejects covered endpoints before posting any
events, and can position only the named synthetic Finder window by its title bar.
No personal files were used. Installed build rollback: App-before-install.Es0ANF.

- PASS direct Google `Prüfung.txt` dragged into the opposite local pane; 157 bytes
  compared equal to the synthetic source with `cmp`.
- PASS the same direct Google item dragged straight into the named Finder test
  folder; `cmp` confirmed identical bytes. Native promise write and operation 1
  were recorded by the app.
- PASS actual native Google document dragged directly into Finder as DOCX;
  ZIP integrity and parsed document XML confirmed both the Unicode sentence and
  the final test sentence.
- PASS CloudClient suite, including the new provider-exact Unicode spelling
  regression and all eleven cross-process restart phases.

The live run exposed canonical-equivalent remote path spelling as a risk: NFC
lookup failed while provider-listed NFD lookup succeeded. Stable path references
now refresh their exact spelling when resolved from a listing. The regression
reproduces that transition and verifies the download uses the provider's bytes.
An initial generic live error was not conclusively attributed to that issue;
one later transient connection error occurred before the successful retry.

Fixtures remain in `.build-native/google-live-9hIyW4/Export` and
`OpenCommander-MacUITest-Google-Finder`; Google originals remain in the QA folder.
This does not close the broader unaccepted matrix above (reverse Google import,
multi-selection/conflict variants, native modifier semantics, virtual ZIP items).
Disk space fell to 182 MiB during testing; only regenerable experimental-app
compiler/index caches were removed, leaving about 770 MiB. App backups retained.
# Modifier continuation — 2026-10-17

Shared copy/move/forbidden policy added for local and online drop destinations.
Option requests copy; Command requests move only if allowed by the source;
Command-Option (unsupported link) is rejected. Archive exports remain copies.
External asynchronous providers receive the committed action explicitly.

32 policy combinations and all 11 existing provider regression groups passed.
Signed Catalyst build passed. Native Command drag with Copy mode initially
copied: corrected the bridge to read the current native event's modifiers.
Retest moved Command.txt and retained its recoverable original; exact byte
comparison passed. Native Option drag with Move mode copied Option.txt and
preserved the source; exact byte comparison passed.

Native Command-Option caused no transfer or conflict dialog and preserved both
files. Google Option-upload in Move mode preserved its source; independent
rclone readback matched SHA-256 8c6f21be47c469442ca874fdeea9ee291680b5e0d9d5df8fc8b32147714da4f2.
Repeated native Google Command export in Copy mode completed, matched local
bytes, and removed the original online entry. Initial no-transfer attempt was
not counted as a pass. The diagnostic build confirmed native move operation 16
and Command event flags; temporary logging was removed from source afterward.
Toolbar Undo completed, restored the online entry and removed the local move
destination while preserving the separate local source used for the copy test.
Not yet accepted: external modifier permutations and full
Linux reachable-state parity. This candidate has not replaced the installed
app. Low disk space briefly interrupted testing; only the rebuildable
experimental-app/Index.noindex cache was removed. Space subsequently recovered.

# Finder Command continuation — 2026-10-17

The earlier Finder Command limitation is superseded by the native receiver
documented in `../docs/mac-finder-command-2026-10-17.md`. Local and authenticated
Google Command move/Undo, Option copy, conflict Cancel and folder-row targeting
passed. The installed build also passed Finder Command and internal Command
move/Undo. Original URLs and verified source retention remain mandatory.
Complete third-party and Linux state coverage is still not claimed.

# Bounded native continuation — 2026-10-18

Additional real native gestures passed with disposable fixtures: a Zstandard
archive folder into the other pane; one Unicode Zstandard member into the
dedicated Finder destination; a file onto a destination folder row; lower/upper
edge autoscroll followed by Escape without publication; and two-level tree
hover expansion without a navigation jump. Original archive hashes remained
unchanged. Zstandard decoding no longer depends on a Homebrew executable.

The synthetic TextEdit document proxy imported into a newly created NTFS image
with exact 32-byte content; its original remained. Independent full image
detach/reattach confirmed persistence. The reverse TextEdit gesture was blocked
by an overlapping window before input; that attempt remains a failure. After
the user freed the windows and the driver raised the named target immediately
behind the source (the same guard retained), the reverse native gesture passed:
TextEdit received the exact original file URL; source remained. The first
Undo/Save did not persist the restoration and is not an Undo pass; explicitly
restoring the synthetic text and saving returned the file to its original
32 bytes, independently verified. This is a file-URL
representation pass, not proof of arbitrary attachment types.
Native GUI observations and actual guarded
mouse gestures are distinguished in `../docs/mac-endurance-2026-10-18.md`.

An exhaustive arbitrary-third-party, server/account and modifier matrix remains
unaccepted. Existing passes do not imply every Linux manual prerequisite or
external application representation was exercised. No physical Elements disk
was available for a new test on this date.
