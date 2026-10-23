# Deferred folder deletion — 2026-10-19

Extends the earlier file-only deferred deletion implementation. JOB-05 remains
partial for documented Trash/Finder/fault boundaries, not an overall parity pass.

## Implementation

- Folder admission immediately saves a visible, cancellable pending-proof job.
  Complete SafeFileOperations.snapshot runs on a dedicated serial utility worker,
  not the UI or queue-state thread. Only one admission tree scan at a time.
  The saved proof is 32 bytes including full content, entry identity/metadata,
  names, hierarchy, empty directories and link targets; symlinks are not followed.
- Scheduler cannot mutate the folder until proof exists and pending=false;
  running/paused conflicting jobs still reserve it. Explicit paused state persists
  across restart, including unfinished proof. Pause/Cancel signal the reader;
  rapid Resume before the old reader exits schedules a new proof afterwards.
- Root identity and complete saved contents are checked before staging, again
  after atomic no-overwrite rename, and at retained destination. Changed/additional
  children stop deletion. If control interrupts post-rename checking before the
  OS deletion call, source is restored without overwriting a new occupant.
- A receipt from an earlier mutation is not treated as an unperformed operation:
  cancellation during its verification must not falsely claim no-effect deletion.

## Regression evidence

Queue runner exit 0: parity-20261019-folder-deletion-controls.log. Six cases:

1. Unchanged nested tree privately removed and restored exactly, including empty
   directories, external symlink and cycle link, no traversal of link targets.
2. Edited child, same length and restored modification time: content hash rejects
   change even though root inode and entry count unchanged; altered tree intact.
3. Added child: no deletion, exact altered tree preserved.
4. Cancel blocked admission proof: GUI-facing state cancelled before reader exits,
   original tree exact and independent paused reservation not started.
5. Pause unfinished proof, reopen queue, explicit Resume: no automatic scan/action,
   new proof still waits on reservation; cancellation of blocker releases one
   removal; restored tree exact.
6. Cancel proof after internal rename: request visible before acknowledgment,
   original complete tree restored, no retained-payload claim for empty bookkeeping.

All existing single-file deletion, changed/replaced source, duplicate controls,
receipts, retries, concurrency, path aliases, queue capacity and paging tests pass.

## Native macOS Trash, restart and Undo

Separate stopped MacUITests fixture only, prepared by deferred-folder.swift;
normal /Applications/OpenCommander.app never changed. Own folder with Nested/
Grüsse.txt (UTF-8 Japanese/German contents), Nested/Empty, external link to own
outside.txt and cycle link to original folder. Two paused admissions:
..C501 reserves folder for copy, ..C502 independent tiny file.

Signed build parity-20261019-folder-deletion-build.log exits 0. Isolated clone
has FSKit extensions detached before ad-hoc signing. Initial getApp observation
times out; same PID 52118 confirmed live, same handle re-observation succeeds;
no redundant restart performed because of the timeout.

Native folder selection → Delete → Trash creates actual deletion UUID
40FAE1BC-A92F-4564-A1F3-D179C95CD20D. Background proof finishes, compact native
summary states "Löschen: DeferredDeleteFolder · Wartend — Pfad durch anderen
Auftrag reserviert". Independent disk read proves saved 32-byte proof, pending
false and queued state. Source still present; no premature success.

Regular quit/relaunch: deletion and both copy admissions paused, no automatic
mutation. Explicit Resume deletion again waits; Cancel only ..C501 releases it.
Real OS Trash completes at /Users/niklaus/.Trash/DeferredDeleteFolder, independent
..C502 remains paused. Corrected native German global status now "Übertragungen: 1"
(previous nonexistent-key "transfers: 1" is gone in this candidate).

Toolbar Undo of this latest own deletion restores folder and updates file list/
German success. Cancel ..C502 leaves all jobs terminal, regular quit.

Compiled independent verifier parity-20261019-verify-deferred-folder exits 0:
live restored complete snapshot EXACTLY equals saved admission proof, including
all identities, content, Unicode child, empty directory, both link strings and
unchanged external target; retained receipt UUID/destination correct, old Trash
destination absent after Undo, no copy output, independent source intact, all
job IDs unique and terminal. Evidence folder-deletion-native-integrity.log.
The verifier uses real source modules, not a separate digest approximation.

## Still open

Finder Put Back remains open. Later mac-trash-recovery-2026-10-19.md supersedes
the Core missing-receipt gap with six actual SIGKILL cases; whole Catalyst GUI
kill/import and other environments remain separate. Parent
rebind, unavailable filesystem/remount and complete native fault matrix are not
inferred from these own local cases. No personal files or other Trash entries
modified, no OS reboot/mount/new permissions, installed app unchanged.

Current handbook updates recursive folder proof and explicitly directs deferred
restoration through OpenCommander Undo pending Finder acceptance. Handbook runner
parity-20261019-folder-deletion-handbook.log exits 0. Final signed candidate
parity-20261019-folder-deletion-handoff-build.log exits 0 with host/extension
security checks. Transfer engine is identical to the native-tested candidate;
handoff changes only guide text and removes obsolete folder-refusal localization.
The isolated clone has the native-tested engine/older guide, not an installed app
replacement. All current fixture jobs terminal and normal installed app unchanged.

Ledger correction: JOB-05's previous new deletion evidence had accidentally
landed under JOB-06 (latency case) because a generic-text patch matched a later
entry. Moved evidence/description to the correct exact ID; restored JOB-06 to its
original partial/no-complete-native-sequence statement. No status/count inflated.
