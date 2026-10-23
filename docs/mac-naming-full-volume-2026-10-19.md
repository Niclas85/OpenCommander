# Native case-only rename and full-volume recovery — 19 October 2026

Isolated app/profile/root only:
`/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw`.
Normal installed app, provider accounts and production FSKit registration untouched.
Each refreshed clone has its extension detached before ad-hoc signing. Previous
clone products are retained beside it. No restart of the computer.

## Case-only rename (FILE-08 follow-up)

Found real parity bug: existing-name preflight rejected case-only changes on
case-insensitive APFS. New `SafeFileOperations.renameEntry` uses same-directory
atomic `renamex_np(RENAME_EXCL)` on macOS, never an overwriting rename or fragile
two-hop temporary name. Preflight distinguishes distinct hard-link entries;
the exclusive syscall still refuses a destination introduced after preflight.
No-op same-name edits add no history record. Sibling-rename Undo uses the same
exclusive mechanism after its existing unchanged-destination verification.

Regression: file/folder/symlink case-only rename, serialized/reloaded Undo,
hard-link and dangling-link collision retention. Entire safety runner passed
33 groups (`parity-20261019-case-rename-safety.log`). Signed candidate build
passed (`parity-20261019-case-rename-build.log`). Native F2 changed own
Grüsse-Prüfung.txt → grüsse-prüfung.txt, visible new spelling/status. Toolbar
Undo restored old spelling and reported one action undone; independent bytes
still match prior source (SHA-256 cdb15bb96012aee8460e45bee45d212b584f3c683b97d8cf1899b65928e60a77).

## Real ENOSPC, not a full host disk (FILE-11)

Created new 16-MiB HFS+ `full-volume.dmg`, mounted only at own FullVolume path.
Synthetic 20-MiB FullDiskSource.bin SHA-256:
`cd52d81e25f372e6fa4db2c0dfceb59862c1969cab17096da352b34950c973cc`.
Native F5 stopped at 15,728,640 / 20,971,520 bytes (75%); no public destination.
Source exact. Found two real defects: worker replaced ENOSPC with EIO, and queue
stored a language-frozen OS sentence/global status remained Queued.

DurableFileCopy now preserves failing syscall errno (zero-byte writes use EIO).
Queue saves coded Cocoa/POSIX failure, optional stable reconnect key and recovery
path; display derives current app-language message. Older raw error field stays
backward-readable. New failed-state transition updates global status explicitly.
Previous errors deliberately remain available after a later successful retry.

Signed corrected candidate build passed (`parity-20261019-enospc-build.log`).
Queue regression 14 groups (`parity-20261019-queue-enospc.log`) includes JSON
round-trip, DE/EN dynamic presentation and NAS recovery details; durable-copy
regression 12 groups (`parity-20261019-enospc-durable.log`) includes actual
mid-transfer SIGKILL and fresh-process exact resume.

Native Settings switched isolated app to German. Explicit Resume of SAME job
`A5890CE1-67BF-486A-8F84-7F5746F825A1` on still-full volume safely stopped again.
Card/global status correctly displayed insufficient free space in German.
Independent journal: failed, 15,728,640 bytes, NSPOSIXErrorDomain 28, error null.
App quit/relaunch retained German, both pane paths and same coded error; no
automatic transfer retry and still no published destination.

Quit test app, detached only own image, resized that image from 16 to 40 MiB,
reattached at same path. Explicit Resume of SAME job completed at 100%; global
status Abgeschlossen and visible destination. Independent cmp verifies all
20 MiB against unchanged source; journal completed at 20,971,520 bytes. This is
real ENOSPC/remount recovery, not a claim about a physical NTFS disk or network.

Native F5 into separate own 0555 ReadOnly directory refused before admission
with Zielordner ist nicht beschreibbar; directory empty, source exact. Restored
that test directory to its original intended 0755 after checking. Own test image
detached after comparisons; image, successful payload and recovery evidence kept.

Normal /Applications version was not replaced: this candidate awaits the rest
of the requested overall acceptance. Full 158-case parity remains incomplete;
WebDAV alone is explicitly excluded.
