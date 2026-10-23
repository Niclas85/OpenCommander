# Native tool boundary and recovery acceptance — 2026-10-19

Scope: separate Mac Catalyst test bundle `com.github.niklaus85.OpenCommander.MacUITests`,
isolated `/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw` profile.
Normal installed app, personal files and production journals were not changed.

## TOOLS-02 — executed native

Fixture generator `ios/tests/MacAcceptanceTests/tools-limits.swift` created 100,100
empty search files in 100 directories and a directory symlink cycle, plus 10,001
flat rename candidates. It refuses an existing fixture rather than overwriting it.
Generator completed successfully; log `parity-20261019-tools-limit-fixture.log`.

Search `Needle` in ToolsA with hidden files off and NoRead directory mode 000:
exactly three full-path results, no traversal of Sub/Cycle, German permission
warning names NoRead and explicitly says `Ergebnis unvollständig.`

Search `*` in ToolsLarge runs with spinner and disabled fields, then explicitly
reports the 100000-entry boundary and says no complete result is reported. No
partial list is silently presented as complete.

A separate run was observed busy, then cancelled in the same computer-control
call. Final dialog remained open, spinner stopped, inputs enabled and status
`⚠ Die Aktion wurde abgebrochen.` An earlier attempt merely closed an already
finished dialog and is NOT counted as cancellation evidence.

## TOOLS-09 — native candidate count; archive issue discovered

Main pane loaded all 10,001 ToolsRenameLimit entries. Command-A visibly selected
10001/10001. Shift-Command-M, pattern Changed-[N][E], Preview: German 1–10,000
selection limit; Apply disabled; no Changed-* entry exists afterward.

Opening own ToolsBoundary.zip exposed a real bug: the archive root passed
isPhysical(), opening a search dialog with the ZIP file as the search folder.
ViewController now requires isPhysicalDirectory() on the active folder and both
comparison sides after routing online providers. Native corrected-build retest
is recorded separately below when executed; initial behavior is NOT a pass.

## Corrupt persisted rename journal — native safe gate

Test app quit; injected only new synthetic batch
1F112C49-9679-4329-8DCC-C3136B042301 with invalid JSON record, permissions 0700/0600.
On launch, German global status explained saved renames could not be checked,
were preserved, and multi-rename was locked. Selecting both RenameRestart files
and invoking Shift-Command-M did not open a rename dialog or mutate data.

Test app quit, injected batch moved intact to CorruptRenameBatch.saved (not
deleted). Relaunch returned Bereit; same selection again opened multi-rename.
No production journal or prior valid test receipt was edited.

Original SHA-256 after both fault and recovery:

- A.txt: ef0c611ee94ca13b7a7eea2061e0ef1dbc85bdfb1ef8706ce87dc0bfaff2c1fe
- B.txt: 60b4599db6499857b4bd6fcf96db820639200428d421c46082dbd4e3660e6dbd

## Corrected archive guard — native retest completed

`parity-20261019-tools-archive-build.log`: signed candidate build exit 0.
`parity-20261019-tools-limits-regression.log`: tools engine and five actual
SIGKILL-boundary scenarios exit 0. Isolated clone refreshed from that candidate,
FSKit extension detached before ad-hoc signing; production extension untouched.

Native own ToolsBoundary.zip opened with A.txt/B.txt visible. Command-F and
Shift-Command-M with A.txt selected correctly stayed in main window and explained
in German that archives/media libraries are unsupported by these tools. Compare
from active archive and again from active physical right pane with left archive
also correctly refused. No search/rename/compare dialog leaked an archive file URL.
From active physical ToolsB, Command-F still opened editable ToolsB folder search.
This satisfies the bounded TOOLS-09 archive and candidate-count sequence.

At handoff, test app quit, left pane restored to RenameRestart, synthetic NoRead
directory permission restored to 0755. All generated empty-file fixtures and
corrupt-journal evidence retained; no host reboot, production install or mount.

Full Linux parity and installation remain incomplete; WebDAV excluded by request.
