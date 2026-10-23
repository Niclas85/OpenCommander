# Durable batch-rename intent engine — 19 October 2026

Goal continuation after native partial-rollback/History acceptance. That previous
acceptance covers handled failure and later app restart, NOT a kill during the
mutation loop. This is a new, separate recovery capability; UI integration is
still required before production startup recovery can be claimed.

## Implemented foundation

- CommanderTools.rename accepts an explicit CommanderRenameJournal. Before each
  mutation it durably writes a source-derived destination snapshot and Undo record;
  the proof is NOT first reconstructed after mutation. Ordinary calls without a
  journal remain unchanged for now.
- Private owner-only UUID batch directories, exclusive/no-follow temporary files,
  fd-relative openat/renameat publication and fsync of record/directory. Source
  identity checked around fingerprint capture. Journal size/count and file owner,
  type, link count, snapshot consistency, lifecycle flags and sibling paths checked.
- Recovery only reads/reconciles. An unchanged original means unexecuted/already
  restored intent; a verified moved target produces explicit Undo. Changed or
  missing targets retain original proof/error and cannot be blindly moved as an
  original. No batch replay or automatic filesystem changes.

## Executed evidence

Expanded tools runner exits 0, 16 PASS groups:
`ntfs/NTFS3G/.build-native/parity-20261019-rename-journal-guarded.log`.
Five fresh isolated /private/tmp/OpenCommander-RenameCrash-* fixtures require
actual SIGKILL/exit137, then new processes:

1. Intent saved, kill before first rename: originals unchanged, no recovery move.
2. Kill after first rename BEFORE commit acknowledgement: prewritten proof finds
   exact target; explicit Undo restores exact Unicode source; next recovery empty.
3. First entry committed, kill before second mutation: only first entry recovered,
   second source unchanged, exact Undo.
4. After kill, occupied original name: Undo refuses it, preserves occupant; retaining
   own synthetic collision elsewhere allows exact Undo.
5. After kill, target changed externally: original proof retained; Undo refuses to
   publish changed target as original; changed bytes stay untouched.

Additional tests: unwritable journal refuses BEFORE source rename; an unexecuted
intent does not adopt/delete a foreign target; inconsistent snapshot rejected.
First new crash-helper compile failed because throwing && expressions lacked an
outer try; corrected helper passes. Failed attempt not counted.
Signed Catalyst host/V2 extension build passes:
`parity-20261019-rename-journal-build.log`.

## Earlier integration checkpoint (superseded below)

Normal controller must select its isolated/production journal root, pass the journal
to the rename engine, and reconcile unfinished batches into persistent History on
startup with stable batch/entry deduplication. Successful Undo/rollback needs a
durable completion receipt so stale intents are not reoffered after later external
renames. Preserve conflicts/corrupt journals, avoid automatic mutation/replay,
and test native UI restart recovery plus publication/History-save kill windows.

Do not declare in-flight app recovery complete merely because this opt-in engine
suite passes. REC-03 remains partial. Installed app was not replaced; no personal
files, provider/security permissions, physical drive or OS reboot involved.

## Completed normal-workflow integration and native acceptance

Controller now supplies its per-profile RenameBatches root for LOCAL batch rename.
Startup checks saved batches in the background and merges only journal-owned
records into History by stable batch/entry UUID and matching proof. Already-present
records are not duplicated, unrelated history retained, completed/unexecuted
intents removed only from their own history references. Corruption/ownership
mismatch preserves state, reports error and blocks new batch rename. No automatic
batch replay or file mutation at startup. Independent batches stay separate Undo
actions rather than being collapsed into one recovered operation.

Successful rollback/Undo writes a durable finished receipt. Receipt failure leaves
the data-restored state serializable and not marked completed; retry writes only
the receipt and preserves later external edits. Finished receipts prevent adopting
later external renames of the same inode/content/path. One new implementation
bug (entry-ID parameter shadowing batch ID during validation) was caught by the
guard tests and fixed with explicit self.id before any installed-app replacement.
Failed intermediate runs are retained as diagnostics, not passing evidence.

Final expanded runner passes 18 groups, including actual-kill cases, startup
merge/ownership/dedup, separate batch grouping and receipt-write-failure retry:
`parity-20261019-rename-startup-grouped-final.log`. Safety runner passes 33 groups:
`parity-20261019-rename-receipt-safety.log`. Signed final build/unchanged V2 extension:
`parity-20261019-rename-startup-grouped-build.log`.

### Actual isolated native app killed DURING batch

Only DEBUG MacUITests bundle with a valid isolated root accepts the own fixture
PauseRenameAfterFirstCheckpoint marker. Production host cannot activate this hook.
Marker pauses after first committed journal, before second mutation/History publish;
worker checks cancellation and has a 90-second timeout. No UI main-thread block.

Native preview A.txt→Restart-A.txt, B.txt→Restart-B.txt, then Apply. Ready marker
identifies batch 327AF1D6-74CB-44B6-8218-59FA55798AF9, entry
7639FB6A-227E-4D37-BC2F-7E2A79AED66E. Independently verified only Restart-A.txt
and original B.txt present and committed journal on disk. Matched exact own process
PID/path 28327, sent SIGKILL ONLY to that test app. Moved own pause marker to .saved.
Computer and normal /Applications process were not restarted/killed.

Same app relaunch reports exactly one recovered step in German. History shows
original→Restart-A path with Undo (index 1064), total 1065 entries including older
synthetic fixture history. Second quit/relaunch stays at 1065, no duplicate import
and B.txt still unexecuted. Specific History Undo succeeds, total 1064, journal
finished=true. Both original source SHA-256 restored/unchanged:

- A.txt ef0c611ee94ca13b7a7eea2061e0ef1dbc85bdfb1ef8706ce87dc0bfaff2c1fe
- B.txt 60b4599db6499857b4bd6fcf96db820639200428d421c46082dbd4e3660e6dbd

After app quit, externally renamed ONLY own restored A.txt back to same Restart-A
path. Next app start leaves that external rename alone, reports Ready, History
still 1064 and no RenameRestart entry. Thus completion receipt actually prevents
stale operation reimport, not only a model assertion. Test app quit and external
test rename restored to A.txt; exact hashes rechecked. All own proof/receipt and
marker evidence retained. First app observation timed out; process was verified
live and SAME app re-observed, never restarted merely because of that timeout.

Native run used the signed recovery build cloned with its extension detached;
subsequent grouping-only refinement has separate model tests and signed build.
This proves stated local batch cases, not every native copy/provider/hardware
kill window. REC-03/full Linux parity remain partial. Main installed app unchanged.
