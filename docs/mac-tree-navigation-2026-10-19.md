# Mac tree navigation parity — 2026-10-19

Work in progress, NAV-01/NAV-02 not promoted by implementation alone.

Linux tree explicitly uses no text elision and resize-to-content horizontal
scrolling. Mac tree columns had persistent splitters but plain width-bound
UITableViews, so deep or long folder names were truncated without a horizontal
route to their endings. Added shared CommanderTreeViewport for local and all
embedded online trees: viewport scrolls horizontally, contained table handles
vertical rows, content width includes measured full names plus indentation.
Column headers/files/toolbar remain outside the horizontal scroller.

During actual native inspection, typed /tmp paths did not reveal the matching
/private/tmp tree ancestors. Directory ancestry/target comparisons now resolve
physical aliases for matching only; displayed and operation paths are unchanged.
Explicit navigation scrolls the corresponding expanded tree row into view;
hover-only rebuilds retain their existing viewport anchor.

Own Navigation fixture has three long Unicode directory levels, suffixes
Ende-A/Ende-B/Ende-C and only one synthetic Navigation.txt. New RenameStale
two-file fixture was prepared but NOT used: ledger inspection showed TOOLS-07
already has native acceptance, so that case was not needlessly repeated.

Native intermediate evidence: /private/tmp ancestry now actually expands and
reveals Navigation, first/second/third Unicode levels with the right pane still
ToolsB. Initial horizontal CUA scroll did NOT move, so NAV-02 remains incomplete.
Added vertical-table rejection of horizontal pans so the enclosing viewport can
own them. Final gesture build/native checks remain in progress, not claimed.

Foundation resolvingSymlinksInPath itself still shortens /private/tmp to /tmp.
Added `DesktopInteractionPolicy.treePath` using POSIX realpath for matching only;
`parity-20261019-tree-identity-safety.log` runner exit 0 covers that exact case,
Unicode symbolic alias, missing-directory fallback, unchanged display URL and
existing safety suite. Earlier Foundation-only attempt was not sufficient.

Explicit reveal survives asynchronous ancestor loads, clears only when target
row arrives, while ordinary hover-only rebuild keeps its anchor. DEBUG isolated
test diagnostics record numerical tree viewport geometry only, no names/tokens.

No normal app installation, personal file mutation, mount or reboot.

## Final candidate native bounded results

`parity-20261019-tree-scroll-final-build.log`: signed build exit 0, extension
security/identity verification passed. Separate clone extension detached before
signing. Real navigation into all three own levels works; tree reveals matching
ancestors after asynchronous listing, right pane stays ToolsB.

CUA coordinate scrolling did not move the viewport while another app was in
front. This is NOT counted as a pass. Extended the previously authorized guarded
local mouse driver with horizontal-wheel-only modes: isolated test resource,
visible endpoint owner checks, no modifiers/buttons, cannot run on installed app.
Actual wheel events in the now-frontmost test window passed:
TreeHorizontal-1 visible=179, content=685, offset progressed 0→506. Screenshot
shows the actual suffixes Ende-A/Ende-B/Ende-C; headers/files stay fixed. Reverse
wheel returns offset=0. Numerical geometry retained in own DragEvents.log.

Native splitter drag increased visible tree width 179→299 points and persisted
tree_fraction_1=0.46759019162173565. Regular quit/relaunch reproduced width 299.
No OS restart. Narrow-name failure discovered at that wider splitter setting:
fixed Size/Type/Date widths leave no visible filename in the remaining file pane.
This pre-existing responsive-layout gap still needs correction. NAV-02 stays
partial, also because the online viewport has not yet had the full native wheel
and resize sequence. No complete no-overlap pass is claimed.

NAV-01 audit also found no explicit active-pane visual update on activePane's
setter (only permanent blue/green accents). Full active-source indication and
its native action check remain open; do not infer that from independent paths.

Handoff: test app quit, hidden-files preference restored off, local panes
RenameRestart/ToolsB restored, own originally-unset tree_fraction_1 removed to
restore its original default. Fixtures/evidence retained, no personal deletion.

## Follow-up — fixed file columns and active pane

Candidate `parity-20261019-file-viewport-active-build.log` signed build exit 0.
Generalized horizontal viewport to hold both sort header and table at minimum
440-point content width; fixed filter/title remain outside. Local and direct
online file tables now retain filenames instead of allowing metadata constraints
to crush their width. No metadata columns silently removed or shrunk.

Native local split widened to 0.46759019162173565 again: A.txt/B.txt remain
visible. Guarded horizontal wheel changed FileHorizontal-1 visible=322/content=440
offset 0→118, screenshot verifies all metadata/date and header move together;
reverse restored names. Right pane remains unchanged.

ActivePane setter now updates both shell borders/accessibility value. Native
right Needle selection: right active, left inactive, both selections independent,
Command-F defaults ToolsB. Then left A selection: left active/right inactive,
right Needle still selected, Command-F defaults RenameRestart. Blue active shell
outline visibly changes, not merely permanent pane-color accents.

Own existing real Drive QA root loaded through temporary long-display-name
profile metadata only, no new login/credential copy or cloud mutation. Native
online tree visible=299/content=701, wheel 0→402 exposes Ende-Online suffix.
Online file viewport visible=322/content=440, wheel 0→118 exposes metadata with
matching sort headers. Screenshots confirm both, right local pane untouched.

Found another existing presentation gap during that actual run: online static
surfaces initially light while asynchronously loaded cells use host dark theme.
Mount now applies existing refreshPresentation after host attachment, without
reconnecting or resetting navigation. Corrected theme candidate retest pending.

First theme retest remained light: navigation.view did not guarantee the embedded
browser's view had loaded, so refreshPresentation's isViewLoaded guard skipped
it. Mount now explicitly sets child appearance, loads its view, then refreshes.
That first attempt is not a pass.

Viewport clipping audit also found drag-hit tests checking the full expanded
table rectangle rather than clipped ancestors. Added CommanderVisibleHit to
native cloud/archive source hit tests and local/online drop target checks;
hidden or outside-viewport rows cannot claim a neighbouring pane. DEBUG isolated
candidate assertions check actual overflowing geometry rejects a point that is
inside the table but outside its viewport. Full external drag matrix still open.

Final signed `parity-20261019-viewport-final-build.log` exit 0. Native restored
Drive view now uniformly dark: headers, filter, tree background, empty surfaces
and freshly loaded rows all match the host. This fixes the failed first retest.
Native wheel repeats trigger `PASS clipped viewport hit OneDriveTreeHorizontal`
and `PASS clipped viewport hit OnlineFileHorizontal-1` in own DragEvents.log,
proving actual overflowing tables reject outside-viewport points.

`parity-20261019-viewport-file-drop.log` regression runner exit 0, including
virtual files/folders, staging boundary, cancellation, slow-provider timeout and
late-callback cleanup. An actual mouse drag of own real Drive a.txt to fresh own
ViewportDrop local pane was accepted; UI shows cancellable 0/5-byte download
progress, actual rclone copyto child observed live. Completion/readback still
pending at this intermediate documentation checkpoint; no success claimed yet.

## Completed final-candidate native follow-up

The real Drive→local mouse drop completed with `fertig`; ViewportDrop/a.txt is
exactly five bytes `1234\n`, independent cmp passes, SHA-256
a883dafc480d466ee04e0d6da986bd78eb1fdd2178d04693723da3a8f95d42f4.
Cloud a.txt and Sub remain listed. Copy mode, source not removed, no conflict
or replacement of any pre-existing file. This is a bounded actual drag regression,
not the entire external-program/modifier matrix.

On the same final candidate, local three-level Navigation path reopened with
hidden system ancestors visible. TreeHorizontal-1 visible=299/content=685,
actual wheel 0→386; screenshot simultaneously shows Ende-A/Ende-B/Ende-C and
fully visible Navigation.txt in the file column. Right pane remains ViewportDrop.
The formerly failing filename-overlap condition is corrected. Actual app
restart into this final candidate also restored the widened 299-point tree,
including the direct-cloud pane before returning local. Native NAV-01 and NAV-02
bounded sequences now completed; broader scaling/provider matrices not implied.

Final handoff after follow-up: test app quit, local RenameRestart/ToolsB panes
restored, hidden off, originally-unset test width restored. Only temporary test
cloud navigation metadata removed with exact ID/root validation; production
account/configuration untouched. Own ViewportDrop/a.txt retained as evidence.
RenameRestart A/B still match original recorded hashes. Installed app unchanged.
