# Native queue reservations — 2026-10-19

Separate preserved MacUITests profile only, normal installed application unchanged.
`queue-reservations.swift` refuses running test bundle/nonterminal old queue and
existing backup/fixture. Three paused synthetic admissions, concurrency two:
IDs 121EC5B0-4526-410D-A1FA-A3A9BF31C301 (copy), ..302 (move of same source),
..303 (independent copy). Reserved.bin is a separate own 64-MiB copy, not any
personal data or prior test source; all paths below own QueueControls/Reservations.
200-ms worker-only checkpoints enabled for this exact isolated root.

## Native overlap sequence before explanatory-label correction

- Resume Copy initially waits because explicitly paused Move also reserves the
  same source. Resume Move lets earlier Copy run, Move stays queued.
- Pause Copy saves exactly 35,651,584 bytes (53%); Move remains queued at zero.
- Resume independent Gamma starts and finishes 67,108,864 bytes even while
  paused Copy keeps the overlapping Move blocked.
- Select own DeleteMe.txt while independent Gamma visibly copying at 73%, open
  Delete dialog, choose Trash. File disappears and list/status updates. Completion
  overlaps are not proven: Gamma finished before final observation, so this
  alone does NOT complete JOB-12 "actual deletion during active worker".
- Select Reserved.bin, Delete → Trash: rejected with German reserved-path
  explanation; source stays listed, move stays queued, paused copy unchanged.
- Undo restores DeleteMe.txt and file listing; independent byte check verifies
  exact original contents. Reserved.bin still exactly 64 MiB of byte 65.

Found UI gap: overlapping queued Move says only "Wartend", no reason. New
presentation snapshot derives "Wartend — Pfad durch anderen Auftrag reserviert"
from authoritative running/paused conflicting jobs; does not alter scheduling or
persist a translated reason. Unit coverage includes running and paused blockers,
independent capacity waits, clearing stale annotation after cancellation and
explicit pause precedence. Queue suite exit 0:
parity-20261019-queue-reservations-regression.log.

## Remaining parity gap identified explicitly

The Linux JOB-05 expected sequence includes deferring conflicting deletion.
Current Mac foreground deletion instead safely refuses and asks to finish/cancel
the reserving job. This is safe but not identical: deferred, cancellable deletion
admission is still an implementation gap, not a completed manual pass. Do not
promote JOB-05 based on safe refusal alone.

## Correction / release / native Undo

Signed build parity-20261019-queue-reservations-build.log exits 0 with security
checks. Relaunched exact isolated profile: recovered Move remains explicitly
paused until Resume. Resume Move while Copy paused now displays German
"Wartend — Pfad durch anderen Auftrag reserviert" in compact summary and expanded
timestamped Details. Expanding/collapsing only Move changes its card, not Copy.

Cancel paused Copy: preserves its 35,651,584-byte private prefix; immediately
releases path. Move transitions from queued to actual planning, no manual second
Resume needed. Independent Gamma remains completed. While Move actually active
in planning, independent DeleteMe.txt is again moved to Trash; fresh UI observation
shows missing DeleteMe plus Move still active. Undo returns DeleteMe with Move
still active; unlike the first deletion this proves actual temporal overlap.
This is active move planning, not payload-copying/Dropbox coverage of JOB-12.

Moved own slow flag intact to SlowQueueReservations.saved to stop deliberately
delaying planning checkpoints. Actual Move then completes. Independent read:
destination exactly 64 MiB byte 65, original source no longer exposed, source
quarantined under .OpenCommanderMoved-2EA4AAD4-7C0B-4FCF-925D-D59481C0EDBC;
independent Gamma exactly 64 MiB byte 67; cancelled Copy payload exactly
35,651,584 bytes byte 65. Cancelled Copy final target absent.

History shows exact source/destination, 19.10.2026 12:11:14 and dedicated Undo
button HistoryUndo-1071. Clicking that exact entry restores source and removes
published move destination into private .OpenCommanderUndo recovery location.
Following observation timed out; checked same PID 3346 still live and actual
filesystem restored, rebound same exact app (no restart). Native observation
then confirms history entry removed, count 1072→1071, global German Undo success.
Normal app PID 13306 unchanged. Regular quit of isolated app at end.

All three admissions terminal, no active slow flag, no OS/network/mount changes.
No installation yet because broader acceptance/deferred-deletion gap remains.

Final independent verification exits 0:
parity-20261019-queue-reservations-integrity.log. Restored original and private
Undo destination identical full byte pattern; independent output exact, cancelled
prefix exact, DeleteMe original text restored, no active slow flag/all jobs terminal.
Original/restored SHA-256 dbfaca2662cb70b69dfefd5ac95d1f54a73663092d46cefdc9609dc695a12c98.
