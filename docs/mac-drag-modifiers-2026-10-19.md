# Actual mouse drag/toggle/modifier acceptance — 19 October 2026

Current signed candidate (case-only rename and coded ENOSPC fixes), isolated
MacUITests clone/root `/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw`.
Existing explicit user authorization for guarded local mouse test driver applies.
Recompiled driver from `ios/tests/FileDropTests/drag.swift`; no guards removed.
Coordinates derived from current app/Finder screenshots plus actual window bounds.
No personal files, account permissions or production NTFS registration changed.

## Actual gestures and independent end-state verification

- Copy toggle off/0: Left/Clipboard.txt dragged into initially empty DragTarget.
  Native card completed; source remains and destination cmp exact (43 bytes).
- Move toggle on/1, verified in AX and screenshot: own Grüsse-Prüfung.txt dragged
  into DragTarget. Native card completed, queue move=true; source public name
  absent and destination matches independent own Right/Source.txt (62 bytes).
  Native Undo restored source exactly and removed visible moved destination.
- Move toggle still on/1, Option held after source selection: Clipboard.txt
  dragged into initially empty OptionTarget. Native card completed, queue
  move=false; source remains and destination cmp exact. Hold over target tested
  without cancellation. Source row dims during lift; bound app screenshot does
  not capture the WindowServer drag-ghost layer, so exact ghost appearance is
  not claimed visually verified from that screenshot.
- Copy toggle off/0: actual Finder Command-drag of own CommandFromFinder.txt
  into empty CommandTarget. Native destination/card appeared, queue move=true;
  original visible Finder path absent. Target SHA-256 matches synthetic expected
  `3dff732895ce340c78fbe0a10ae2f62b4c008a732b1eb68ff368d8e3c759625d`.
  Native Undo reports one action undone, exact Finder source restored, visible
  target absent. All end-state checks are independent of UI success text.
- Move toggle on/1: actual Finder Option-drag of that restored synthetic file
  into empty CommandTarget completed with queue move=false; source and target
  cmp exact. This is a real external modifier check, not only policy unit tests.

## Escape countercheck and test-driver correction

Initial `--finder-source --command --cancel` failed: the target was published
and source moved, queue grew from 8 to 9. Native Undo restored the exact source
and removed the visible target. This failed attempt is not a cancellation pass.
Another long-hover attempt plus a separate CUA Escape returned a UI-state-change
error; no new job/target appeared, but that ambiguous attempt is not counted.

The driver's original Escape inherited held modifier state. Test cancellation
now explicitly releases modifiers and posts plain Escape down/up with empty
flags while the mouse remains held. The corrected driver was recompiled from
source; same Finder source and target, command drag then plain Escape produced
no target, exact unchanged source SHA-256 and unchanged queue count 9. Subsequent
positive Finder Option-drag from the same icon/coordinates created the exact
target and increased count to 10, confirming a functioning source/target route.
This verifies plain Escape after modifier release, NOT held Command-Escape or a
universal modifier-shortcut cancellation guarantee. No product cancellation code
was changed on the basis of the ambiguous key-injection attempt.

Final file-provider regression runner passed 15 groups, exit 0:
`ntfs/NTFS3G/.build-native/parity-20261019-drag-modifiers-policy.log`.
Fetched `origin/codex/linux-desktop` again; reference remains e3b2981ad5a88551be81b86b6c6453e26e2e2ff5.
At handoff isolated copy toggle restored to Copy/0, test app quit, zero queued
or running fixture jobs. Finder QA window returned to its original synthetic
DropboxExport directory; its moved window position remains left. Synthetic
files/recovery records retained. No personal document navigation changed.

The first local gesture was refused BEFORE events because Chrome covered both
endpoints. Only the own test window was moved by its visible title strip; retry
passed. Own already-existing Finder QA window was navigated to synthetic source
and moved left; unrelated windows/documents not modified or minimized. Guard
requires current visible window owner and named Finder fixture. A few native
AX-only button/switch clicks did not trigger an action; fresh screenshot-based
clicks and explicit switch values were used instead. No failed/no-op action is
counted as a successful gesture.

## Not a universal external-app pass

This verifies the listed toggle/modifier/file-URL cases, not arbitrary promises,
attachments, every provider, Option+Command/link semantics, external hover/scroll,
or the entire 158-case matrix. Existing browser, TextEdit, Preview, cloud and
archive evidence remains separately scoped. FILE-03 remains partial because
its complete visible-ghost expectation and exhaustive destination prerequisites
have not all been directly verified. No new app installation in this round.
