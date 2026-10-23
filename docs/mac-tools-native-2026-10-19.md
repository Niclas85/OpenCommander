# Native search, comparison and partial multi-rename — 19 October 2026

Linux reference e3b2981; WebDAV excluded. Own MacUITests clone/profile and fixture
`/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw` only. No provider
permissions, personal files, production filesystem extension or OS restart.
Signed host candidate built; clone extension detached before ad-hoc signing.
Normal /Applications app not replaced pending the remaining overall acceptance.

## Fixed TOOL-08 parity gap: incomplete rollback and History

Previously a failed rollback threw a string and lost the remaining steps' History
records. Linux retains those records. CommanderTools now captures FileUndoRecord
immediately after each successful mutation, uses verified Undo for rollback and
throws structured RenameFailure carrying only still-unreverted records. Controller
adds them to persistent History and reports the exact remaining count in German/
English. It never fabricates a new proof from an externally changed destination
after failure. Default moves use exclusive same-directory rename, not overwriting
rename. Successful rollback records are not incorrectly added as pending work.

Regression injects second-step failure plus occupied original name, checks
preserved records/error, JSON reload, safe refusal while occupied, then exact Undo
after removing only synthetic collision. Another variant modifies destination
after first step; rollback and later Undo refuse to move that changed content.
First test compile failed due throwing autoclosures; second run failed due the
previous cancellation test's still-set token. Corrected/reset fixture r3 passes
four groups; neither failed attempt counts. Final localized runner passes five
groups: `parity-20261019-tools-localized-final.log`.

### Actual native fault/restart/Undo

Own RenamePartial/A.bin is 16 MiB, SHA-256
080acf35a507ac9849cfcba47dc2ad83e01b75663a516279c8b9d243b719643e.
B.txt (35 bytes) temporarily had user-immutable flag; plan Result-[N][E] valid.
Own kqueue fixture watcher `rename-collision-watch.swift` observes first committed
rename and creates ONLY missing A.bin with O_EXCL (51-byte synthetic occupant).
It exits 0; boundary log `parity-20261019-rename-native-watch.log` confirms injection.
Second rename fails, rollback of first is blocked by new original-name occupant.
Native alert explicitly reports one retained History step; Apply disabled.
Result-A.bin retains exact original hash; B.txt never renamed, occupant untouched.

Quit/relaunch: History entry 1064 retains original→Result-A.bin and Undo. Clicking
that specific Undo refuses existing destination with German explanation. Moved
ONLY injected occupant to own Collision-A.saved (retained, not deleted), removed
own B.txt's temporary immutable flag. Clicking SAME History Undo succeeds: original
A.bin has exact original hash, Result-A.bin/Result-B.txt absent, B.txt unchanged.
This is real local fault and persisted UI History, not merely model serialization.
Does not certify process-kill durability DURING batch execution or remote batches.

## TOOLS-01 native search

Command-F starts at actual active pane path (RenamePartial), Match case unchecked.
Changed absolute path to ToolsA; NEEDLE insensitive gives exactly three rows with
full paths: Needle.txt, needle-small.txt, Sub/Needle-Nested.txt. Hidden hit omitted.
Match case selected with NEEDLE gives zero; Needle*.txt gives two. ToolsB absolute
path gives exactly one; activating result opens ToolsB in left pane, right pane
CommandTarget unchanged. New dialog defaults Match case unchecked again.

With hidden files enabled, Needle gives exactly four including .Needle-Hidden.txt.
Needle-?ested.txt gives exactly the nested hit; activating opens ToolsA/Sub in left
pane, right unchanged. Sub/Cycle is a directory symlink to parent: no duplicate or
endless traversal. Hidden files restored to off. Bound UI rows show complete paths.
Read-only search only; no fixture content mutated.

## TOOLS-03 native comparison and localization correction

ToolsA↔ToolsB yields eight expected rows: Needle.txt equal; Different.txt different
despite both five bytes; OnlyLeft/OnlyRight correct; Denied.txt unreadable; remaining
nested/one-sided entries correct, symlink cycle not traversed. No synchronize/delete
action. Initial German UI leaked English Cocoa permission detail. Scan warnings
and unreadable comparison details now use existing app-language OS presentation;
final signed candidate native repeat shows German access-denied detail correctly.
Own Denied.txt temporarily 000, restored original 0644 after native repeat;
independent cmp verifies equal originals. Different.txt hashes remain distinct.

## TOOL-06 subset and localized plan errors

Structured localized explanations now identify invalid counter/selection, invalid
name, duplicate/occupied destination, changed source and traversal limit. Native
two-file previews Same.txt, B.txt and ../escape respectively explain duplicate,
occupied and invalid target in German; Apply remains disabled, no files renamed.
Full cyclic-plan/native matrix remains partial. Unit DE/EN permission/invalid-name/
limit checks pass. Successful signed final build:
`parity-20261019-tools-localized-build.log`; duplicate localization check passes.

Test app quit, temporary permissions/flags restored, own collision/data/evidence
retained. No complete Linux parity claimed; remaining acceptance cases stay open.
