# Native SMB copy, replacement, move and Undo — 2026-10-19

Exact signed candidate from `parity-20261019-archive-listing-build.log`, separate
test bundle only, production installed PID13306 unchanged. Existing narrow picker
selection of own FoundationTree survives test-app restarts. No whole-share/FDA
grant, remount, network configuration change, OS reboot or personal-file mutation.
Elements is not present/tested in this sequence.

## Fixtures and actual native operations

`native-nas-fixture.swift` refuses a running test app/existing local fixture,
verifies smbfs, then creates unique own NAS directory:
`/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg/FoundationTree/NativeTransfers-20261019-8C8550B0-C8AA-4373-AB1C-6EF8602913B5`.
Local root:
`/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw/NativeNASAcceptance`.
Manifest contains only those exact paths. Source initially45B original text,
later intentionally changed via patch to48B replacement text, not personal data.
Own Tree contains33B `Nested/Grüsse.txt` and `Nested/Empty` directory.

Visible app left/right paths, selection, F5/F6, conflict confirmation and toolbar
Undo were used. No direct engine call substitutes for these five native jobs:

| Job UUID | Actual native action | Verified outcome |
| --- | --- | --- |
|855CEE76-65C8-4F3A-8817-2AE0AED99F1A|F5 local→SMB Probe.txt|completed45/45B; independent cmp exact|
|60957A35-F2B5-40DF-9A5A-FFD94646C044|F5 changed local→SMB; native Replace|completed48/48B; independent cmp exact; toolbar Undo restores old45B and leaves local48B untouched|
|3B8F18A5-D02C-4C84-AE2D-27BF017872E3|F6 SMB Probe.txt→empty local Returned|completed45/45B; visible source removed, exact local bytes; regular quit, verified process gone, fresh launch, toolbar Undo restores exact NAS45B and removes returned entry|
|001C3173-1216-4321-832B-DBA06EFB024D|F5 local Tree→SMB|completed33/33B; exact Unicode bytes and empty directory|
|150EA936-3100-4DF9-9DB2-09B33A380384|F6 SMB Tree→empty local Returned|completed33/33B; exact local tree and old NAS path absent; toolbar Undo restores exact NAS tree and removes returned tree|

Each queue card was observed completed, with stored state/error independently
checked. The global label briefly remained Waiting while completed-job History
was being prepared, then settled to Completed; no claim of a persistent status
bug or untested fix. After final Undo, live panes show left Returned empty and
right NAS Tree+Probe.txt, success status1 action undone. Ordinary fresh process
also restored both pane locations without another scope prompt.

Independent repeatable `verify-native-nas.swift` passes overwrite-undone,
moved-to-local, move-undone, tree-copied, tree-moved-to-local, tree-move-undone
at the corresponding actual stages. The first inline verifier attempt did not
compile (throwing precondition autoclosure); it did not run or count as a pass.
Replacement standalone verifier reads data before assertions and passes.

Final retained integrity log:
`parity-20261019-native-nas-final-integrity.log`, exit0. It verifies both exact
restored NAS contents, empty Returned paths, untouched local48B source, five own
completed/error-free jobs, all queue IDs unique and no unfinished queue work.
Test app quit normally after final checks; production PID13306 remains running.

## Fresh real-SMB engine regression (separate from native UI coverage)

Ran current `tests/run-nas-exclusive-tests.sh` on new empty own fixture:
`/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg/FoundationTree/OpenCommander-LiveQA-Regression-20261019-Native`.
Exit0,16 PASS groups in `parity-20261019-native-nas-regression.log`:

- exclusive Unicode/hidden/empty-directory tree; prefix-verified pause/resume;
- changed partial refuses without repairing another writer's data;
- same-name concurrent jobs exactly one wins, source intact;
- replace retains private prior tree; overwrite Undo exact;
- cancel retains source/incomplete target without false completion;
- injected lost-write acknowledgement reconciles in a genuinely new process;
- replacement/source-move acknowledgement-loss replay and Undo;
- Finder tags/FinderInfo/resource fork/dates and hidden flag roundtrip;
- changed source metadata prevents destructive move;
- explicit ACL unsupported on this server is **safely refused with source
  retained**, not incorrectly claimed as ACL-preservation support.

These fault checkpoints operate on real SMB data but simulate the connection
error; they are not an actual cable disconnect/remount test. No Elements paths
were passed, so optional Elements cross-volume cases were not run. Own journals
remain at `/private/tmp/OpenCommander-NASExclusive-61E30B30-202C-477F-9EF0-2A4F4137E18F`.
Fixtures/recovery data retained, no cleanup of personal data or emptying Trash.

## Remaining scope

Real network drop/remount, wider account/share permissions and physical NTFS↔SMB
checks remain separate. This bounded evidence does not complete every original
Linux prerequisite. WebDAV is explicitly excluded; the rest of the158-case goal
remains active. Installed application has not yet been replaced by the candidate.
