# Cloud move replacement — 2026-10-18

Cloud replacement acceptance completed after the installed Dropbox correction.
This does not certify complete Linux acceptance.

## Implementation

- Cloud to local replacement persists the existing local destination backup
  and its verification proof in the publication/Undo record. Both current
  destination and backup are checked before retaining/restoring a cloud source.
- Local to cloud replacement persists source fingerprint and move intent in
  the replacement job before displacement. A nested source-retention journal
  resumes without replaying an already completed upload. Undo restores both
  the local original and the previous cloud destination.
- Cloud to cloud replacement, including two folders in the same account, uses
  an outer durable move intent, nested download/replacement and source-retention
  journals. The original target proof survives source retention and Undo.
- A changed recovery object blocks source restoration before making changes.
  Folders replace as a whole, never merge silently.

## Automated acceptance

The expanded cloud-client runner includes backup tampering, replacement folder
contents/empty directories and fresh-process interruption/resume/Undo phases.
The runner completed successfully: 67 PASS groups, including 29 fresh-process
phases. File-safety regression and both offline handbook groups also passed.
The signed Catalyst candidate and unchanged V2 extension preflight passed.
An initial test-only compile error (nonoptional force unwrap), an encapsulation
error in a new recovery check, and an outdated handbook preservation assertion
were corrected before these passing runs. One earlier compiler run was invalid
because a source changed during compilation; it is not counted as evidence.

## Live acceptance in progress

The installed version was quit normally and the separate candidate launched.
F6 on the own local fixture into the existing Dropbox fixture now offers the
full Replace/Keep both/Skip/Cancel conflict sheet. Replace was selected and the
durable replacement move was started.
The local-to-Dropbox replacement move completed. Independent recursive download
matched the complete source fixture (including Empty); the visible local source
was absent. Two-sided Undo completed: the restored local source and independently
downloaded previous Dropbox target each matched their original trees exactly.
Cloud-to-local F6 for the own `a.txt` into MoveDownload is now running; the old
local test destination contains `previous local destination` and a newline.
That move and Undo both completed: local publication matched ABCD, provider
listing showed the source retained under its per-job recovery name, then Undo
restored the exact original 27-byte local destination and the cloud ABCD file.
Dropbox-to-Google replacement of the own folder is the next live check.
The Google target's old tree was independently downloaded before any mutation.
The real conflict sheet offered Replace and was accepted. During preparation,
Cancel stopped only this test operation; UI reported `Abgebrochen;
abgeschlossene Schritte bleiben erhalten.` and offered explicit recovery.
Later was selected, and the candidate was quit normally for the final rebuild.
The preserved outer journal is `C101B384-4FBF-4821-86E4-F418A0B1F2C6`.
This is controlled cancellation/app restart, not a global network outage test.
Independent post-cancel target download exactly matched the pre-cancel Google
tree. The visible Dropbox files also matched. The full Dropbox snapshot now
contains two private recovery files from the preceding file-move/Undo test;
these explain the full-tree difference from the older FreshUndo baseline and
must be preserved, not discarded. `CrossCancelSource` is the exact full source
baseline for the cross-provider result/Undo checks.

A further restart issue was found and corrected: path-backed cloud providers
issue new session-local item IDs after relaunch. Download preparation now reuses
the account/path-bound journal, rather than creating a duplicate for the new ID.
Its destination-directory identity is rechecked before reuse. A fresh-process
test asserts that only one journal remains.
The final cloud-client rerun with this fix and strict legacy-backup proof
preflight also completed successfully (67 groups).
Read-only end-state reconciliation was added for replacement local/cloud moves
when a process dies after successful Undo but before History saves success.
Fresh-process confirmations assert zero mutations; the latest runner passed
69 groups including 31 fresh-process phases. New final native build still
required before installation.
The final signed native build now passed. Tested candidate dylib SHA-256:
`207ef45e24ce42b86c6b342394983be47b7dd7dced3b97c87c13e26af67ed9fe`.
After relaunch, Google authentication remained valid and the UI found the
retained cross-provider move. Explicit Resume was selected; completion and
two-sided Undo remain pending.

Existing installed app remains intact while these changes are being verified.

## Current blocker: host storage

Live cross-provider resumption stopped with Cocoa out-of-space while creating
its private configuration lease. The UI reported failure, not success, and kept
the checkpoint. Test app was quit normally. Data volume free space fluctuated
from about 2.2 GiB to 1.2 GiB; encrypted swap was about 13 GiB in use.
Only rebuildable own caches were removed: experimental-app ModuleCache and
Intermediates, plus mac-acceptance-20261018 Intermediates (about 314 MiB).
App products/backups, source, evidence and personal/other-project files remain.
The rejected forced-delete attempt made no changes; non-forced removal of the
three exact validated cache directories completed successfully.

The real OS failure also exposed English Cocoa text in the German cloud alert.
Cloud browser errors now use coded, app-language presentation for Cocoa/POSIX
errors, avoiding private configuration paths. DE/EN regression assertions were
added to FileOperationSafetyTests; these final presentation changes have NOT
yet been compiled/tested at that checkpoint. The follow-up below supersedes it.

## Final live acceptance after storage recovery

The final candidate, including localized OS failures and completed-card cleanup,
built successfully with extension signature checks. Dylib SHA-256:
`cae160553adc1ce584cf36a30c67856f5e19efd828a7633d96f6889c657ccffc`.
The updated FileOperationSafety runner passed 31 groups; transfer queue 11 groups.

The existing cross-provider journal was explicitly resumed through the native
Google recovery dialog, without another login. UI completed successfully.
An independent Google recursive download (`CrossCompletedTarget`) exactly matched
the entire `CrossCancelSource` baseline, including private fixture recovery files.
Dropbox listing confirmed the visible original was absent and retained as
`.OpenCommander-Moved-50C20041-DFE4-4E48-9F8B-6C10C96D7331`.

Native History entry 115 identified Dropbox fixture → Google fixture. Its Undo
completed with “1 Aktion(en) rückgängig gemacht”. Independent Dropbox download
`CrossUndoSource` exactly matched `CrossCancelSource`; independent Google download
`CrossUndoTargetFinal` exactly matched `GoogleBeforeCrossMove`. No personal files
were mutated. The earlier controlled interruption and real disk-full failure were
both followed by successful resumption and two-sided Undo.

Performance limitation: this small multi-file fixture still took roughly eleven
minutes for resumption and several minutes for Undo because of repeated provider
proof reads. Correctness passed; this is not a claim of optimized cloud latency.
Global network-outage behavior and full Linux parity remain separate coverage.

## Installation

Installed the exact tested bundle at `/Applications/OpenCommander.app` after
normal quit and verifying no OpenCommander NTFS mount was active. Extension and
host signatures passed. Previous version retained at
`.build-native/App-before-install.RP516v/OpenCommander.saved`.
Installed dylib hash matches the candidate above; app launched successfully.
Post-install native Google location loaded its file/tree listing, including the
restored QA folder, without another authentication prompt.

At least 3–5 GiB additional host reserve was requested. Do not install before
the final safety/build checks and resumed cross-provider completion/Undo.
Full Linux acceptance remains open; in particular native WebDAV connection
and environment-specific iCloud/authentication/mount cases are not covered by
these cloud-move results.
