# Deferred local deletion — 2026-10-19

In-progress JOB-05 parity implementation; not installed and not a full case pass.
Previous Mac foreground deletion rejected conflicting reserved paths. Now a
confirmed conflicting single-file/symlink deletion admits its own visible saved
queue job, source-writing reservation, Pause/Resume/Cancel, explicit deletion
label and Trash/private-recovery route. Admission is never reported as completed
deletion and does not dismiss media viewers as if deletion had succeeded.

Admission records lstat device/inode/type/size/mtime, with canonical parent but
no following the selected symlink itself. Restored queued/running jobs become
paused, including deletion, and never automatically start. Stateful repeat
requests for same unfinished deletion are refused instead of creating duplicate
mutators. Source path is revalidated before use. Before altering the entry, queue
persists an exclusive, private same-parent .OpenCommanderUndo-UUID staging path;
source atomically renames without overwriting into items/original-name and its
identity is checked again. A mismatched racing entry is restored without
overwriting any newly appeared source; failure retains recovery path if needed.

Default Trash uses the macOS Trash API, preserves original filename. Non-Trash
Delete keeps private original as existing foreground Delete does. Completed
job captures actual recovery destination; history integration records Delete,
not Move/Copy, and existing verified Undo handles restoration. Per-job fsynced
receipt supports explicit replay after completion before final queue save without
touching a newly created entry at the old source path.

## Regression evidence

parity-20261019-deferred-delete-final-regression.log exits 0:

- Paused-copy source reservation blocks deletion; exact source unchanged.
- Cancel queued deletion invokes no mutator and releases only its own work.
- Replaced inode and in-place changed content both refuse before mutator.
- Pending deletion survives new queue instance as paused; explicit Resume still
  waits until paused copy cancellation, then removes original once to own
  simulated Trash with exact bytes retained.
- Simulated running journal after per-job receipt: explicit new-instance Resume
  validates retained actual destination, does not call deletion again, preserves
  a newly created unrelated file at original source path.
- Literal selected filename deletion-receipt.json cannot collide with receipt.
- Injected mutator failure retains exact staged original; retry succeeds.
- Real default private (non-system-Trash) deletion retains exact bytes, validates
  through FileUndoRecord and restores exact source. No personal files/system
  Trash touched by these model tests. Other Trash scenarios use own simulated
  directory, not evidence of actual macOS Trash UI behavior.

## Explicit remaining gaps

- Reserved directories were initially refused. The later recursive implementation
  and real folder Trash/Undo evidence are in mac-folder-deletion-2026-10-19.md;
  this limitation is superseded, not a current refusal.
- Missing-receipt recovery is now implemented with private pre-mutation bookmarks;
  six actual Core/OS Trash SIGKILL cases pass, including original-path reuse.
  See mac-trash-recovery-2026-10-19.md for exact scope and Catalyst/UI remaining work.
- Source parent rebind/other-process racing faults, unavailable filesystem,
  volume-remount identity and broader directory/symlink native matrix remain.
- Finder Put Back is confirmed disabled for tested Foundation and NSWorkspace
  API probes; native Finder-created positive control is enabled and restores
  correctly. This is a real remaining integration gap, not merely assumed wrong
  staging destination. OpenCommander Undo remains verified.
- Native symlink/directory/fault matrix still partial; see executed file sequence below.

## Native own-file system Trash / lifecycle / Undo

`deferred-delete.swift` admits two own paused copy fixtures only after checking
stopped test bundle and terminal-only old journal, with exclusive backup and new
source directory. Own DeferredDelete.txt is 58 bytes, Independent.txt 55 bytes.
Deletion itself was requested through native selection → Delete → Trash, not
seeded as a completed/deletion fixture. Candidate built and signed successfully
in parity-20261019-deferred-delete-final-build.log (exit 0).

- First native request ID 52ABF850-AEF9-423C-BFF9-50D82E52752F displays explicit
  "Löschen: DeferredDelete.txt · Wartend — Pfad durch anderen Auftrag reserviert",
  route to Papierkorb, Pause and Abbrechen. Global admission text explicitly
  says no deletion completed. Source stays selected and unchanged.
- Native Cancel: cancelled/no partial data, source still exact; both own copy
  jobs remain paused. No default deletion handler ran for this cancelled request.
- Second native request B69B4428-3888-46B6-8900-1E76F2A0C1DA waits. Regular quit
  and relaunch: deletion and both copies paused, source still present; no auto
  mutation. Explicit Resume deletion still waits on paused Copy ..C401.
- Cancel only ..C401: deletion completes through real macOS Trash API, actual
  /Users/niklaus/.Trash/DeferredDelete.txt; independent copy ..C402 remains paused.
  Independent file read confirms exact original text in Trash, source absent.
  Staging/receipt remains in own source parent .OpenCommanderUndo-B69B4428-...
- Native History correctly shows "1 Element(e) gelöscht", timestamp
  19.10.2026 12:24:08, exact source→Trash route and HistoryUndo-1071 button.
  Click that exact Undo: history count 1072→1071, source reappears and German
  "1 Aktion(en) rückgängig gemacht". No ambiguous toolbar target used.
- Cancel untouched independent ..C402 to leave all own fixture jobs terminal;
  regular quit. No OS reboot, no mounts, normal installed app PID 13306 untouched.

Found mixed-language global status "transfers: 1" during this native sequence:
two ViewController lookups used nonexistent "transfers" key. Corrected both to
existing localized transfer_queue. Transient duplicate-deletion admission errors
now clear on accepted control actions (unless still at 1,000-card capacity), so
users are not left stuck with a stale failed-admission banner after cancellation.
New duplicate-request regression verifies no second mutator and intact source.

The native sequence used the signed pre-banner-fix candidate. Final matching
handoff build parity-20261019-deferred-delete-handoff-build.log exits 0, signed
host/extension checks pass. Handbook tests exit 0, including explicit deferred
deletion scope and still-unsupported reserved folders in DE/EN offline guidance.
Full queue regression parity-20261019-deferred-delete-complete-regression.log
exits 0, including duplicate admission/control-banner regression and all prior
queue tests.

Final isolated clone refreshed from that exact candidate with FSKit extensions
detached before signing. Native relaunch still shows restored DeferredDelete.txt
and Independent.txt, no automatic deletion or copy; terminal cards have no
pause/resume controls and both global pause/resume buttons disabled. Regular
quit. verify-deferred-delete.swift exits 0 after relaunch: originals exact,
neither blocked copy published, cancelled request had no staging, real completed
Trash receipt retained with correct UUID/actual destination, Trash destination
absent because native Undo restored it, all jobs terminal and IDs unique.
Evidence parity-20261019-deferred-delete-native-integrity-final.log.

Independent saved test profile check after final relaunch: history count remains
1071, completed deletion UUID remains in transferIDs, no duplicate Delete history
is recreated after Undo.

No installed app replacement. Original user data and other Trash entries untouched.
