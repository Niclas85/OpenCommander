# Online tool cancellation — 2026-10-19

## Confirmed race and correction

TOOLS-04 remains partial, not a real cloud account/UI acceptance yet.
Added deterministic provider-response race to CloudClientTests: toolChildren
marks its current task cancelled but successfully returns an empty listing.
Before correction, `CommanderOnlineTools.scan` returned a complete empty result:
runner exit 133, `cancelled empty online scan reported complete` in
`parity-20261019-online-tools-cancel-before.log`. This failure is evidence of the
bug, not a passing test. No network/account data used by this injected provider.

Correction checks task cancellation after awaited listings (including empty
ones), after scan completion, and before content comparison completion.
CommanderToolsController holds awaited rows locally and checks cancellation
before publishing them; OneDriveBrowser also checks before building comparison
rows. Successful late responses must not override a cancellation with equality.

Also closed a related mixed-context hole: before routing an online comparison,
ViewController requires each non-online side to be a physical directory. Archive
roots are physical files, and their root-only snapshots must not be treated as
an empty local directory when paired with a cloud pane.

Final regression `parity-20261019-online-tools-cancel-final.log` exited 0,
including the new cancellation test and existing actual process-kill/restart
Cloud-move scenarios. `parity-20261019-online-tools-context-build.log` signed
candidate build exited 0; extension identity/sandbox/FSKit verification passed.

## Real Google Drive native setup (bounded, no new login)

`ios/tests/MacAcceptanceTests/cloud-tools-profile.swift` references the existing
authorized production Drive configuration without reading/copying credentials.
It refuses existing test profiles, uses a new ID and restricts navigation root
to the existing own `OpenCommander-LiveQA-Size12-wUvOA0` QA folder. Normal profile
metadata is unchanged. Both isolated app panes loaded Sub/a.txt from that root.

Native Option-Command-C: both sides named correctly, Start produces spinner and
explicit possible-download message, Cancel during busy processing returns to
enabled Start with cancellation text and no comparison results. This is actual
Drive processing cancellation, not yet a claim of interruption within file-byte
reading specifically.

Full rerun completed: exactly two `Gleich` rows, `Sub/b.txt` and `a.txt`;
directories excluded from equality rows, spinner ended, Start enabled. This
actually downloads/hashes both sides through the authorized Drive backend.
Own fixture was read-only throughout; no upload/rename/share action executed.

Mixed native context test also completed: left own ToolsBoundary.zip, right
real Drive QA root. Compare invoked with archive active, then again with a.txt
selected on online right: both refuse in German before opening a tool dialog.
No ZIP-as-empty-directory comparison is produced.

No normal app install, personal file mutation, new permission grant, production
login or reboot in this continuation. The full provider/account matrix is not
claimed from either deterministic or single-provider evidence.

At handoff both panes restored to original local test folders, test app quit.
Helper --remove verified exact single test ID/root and removed only that own
temporary navigation reference (and matching test pane sessions). Original
production account/configuration/credentials were never changed or removed.
RenameRestart originals still match the previously recorded SHA-256 checksums.
