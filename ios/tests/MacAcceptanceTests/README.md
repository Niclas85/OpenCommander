# Isolated native acceptance fixtures

`fixture.swift` accepts only a pre-created physical directory immediately under
`/private/tmp` named `OpenCommander-MacUITest-Acceptance-20261018-*`. Compile it
with `Localization.swift` and `FileOperationSafety.swift`, then run it against a
fresh `mktemp -d` directory with that prefix. It never overwrites existing files.

The seed includes 80 navigation folders, two PNGs, a destination sentinel,
1000 audit entries (one real oldest-page copy Undo, all others non-undoable
synthetic cloud records), and 20 explicitly paused 64KiB local jobs. Queue paths
must retain physical `/private/tmp` spelling: the transfer engine deliberately
refuses symlink ancestors such as `/tmp`.

Only the DEBUG clone with bundle ID
`com.github.niklaus85.OpenCommander.MacUITests` reads `MacUITestRoot.txt` or the
`OPENCOMMANDER_MAC_UI_ROOT` launch variable. History seeding is once per root,
size/count bounded, with named synthetic paths and verified snapshots for the
single actual Undo. No provider login or production preference import is needed.

For a native preference-restart test, place `PreserveAppState.txt` in this
isolated root. The first launch initializes the fixture as usual; subsequent
launches preserve language and pane bookmarks/paths. The production bundle
never reads this marker. Without it, existing deterministic XCTest launches
continue to reset language and pane paths on every start.

`interactive.swift` adds bounded image/text/binary/archive-source fixtures and
four trees of 1,000 small files. It writes only missing synthetic files. Do not
rerun it while testing a move or missing-source condition: that would recreate
the intentionally missing input and invalidate that test.

Copy `BrowserDrag.html` beside the fixture's `Media` directory. Open it in a new
Safari or Chrome window; do not reuse account tabs. The authorized local mouse
driver supports only fixed app modes, checks visible fixture window titles and
refuses covered endpoints. Inspect fresh window bounds before each gesture.

Do not register the clone's FSKit module: unregister its generated host after
building, move only its generated `.appex` out of the disposable bundle, then
sign that clone. The installed production NTFS driver must remain selected.

This is fixture infrastructure, not a passing test result. Dated executions,
hashes, failure/retry distinctions and remaining coverage are recorded in
`docs/mac-acceptance-2026-10-18.md` and the corresponding 158-case ledger.

`media.swift` creates bounded six-second synthetic WAV/H.264 and a validated
two-frame GIF in `MediaExtra`, only under the same isolated root guard. Existing
media are duration/frame validated, never overwritten. The native GIF check
asserts readable first-frame preview, not animation parity. A lossless WebP was
generated separately from the fixture's own PNG with the locally installed
encoder; the app does not depend on that encoder. Playback, actual pointer
seeking versus AX-only value changes, replay, temporary-file lifetime and
single-item Trash/Undo results are recorded separately in the endurance report.
