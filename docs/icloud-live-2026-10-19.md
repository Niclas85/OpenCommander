# iCloud live continuation — storage blocker

Installed direct iCloud profile listed successfully. Started own QA fixture:
`/private/tmp/OpenCommander-iCloudQA-20261019.pxOC6p` (two tiny, distinct Unicode
text versions, Source/Replacement and empty Received).

In the actual iCloud browser Actions → New folder created
`OpenCommander-iCloudQA-20261019-pxOC6p`. Independent local iCloud File Provider
metadata confirms this folder exists. No personal file was mutated. Upload,
replacement, move and two-sided Undo have NOT yet been executed or passed.

Host free storage fell from 835 MiB to 157 MiB while preparing the run. Removed
only own completed compiler caches (~344 MiB) and a closed test build (~54 MiB).
Personal files, production backups and original XCTest logs remain untouched.
Attempted compression of own XCTest logs failed; its incomplete archive was
removed and originals retained. Free space after cleanup about 202 MiB.

Computer control twice failed to create its observation image, including after
cleanup. No further cloud mutations or builds started. Existing installed app
left unchanged; no reboot, no network interruption, no installer invocation.
User was asked to restore several GB of stable free space / close large apps.
This is a blocked partial live run, not a successful iCloud write acceptance.

## Subsequent continuation: actual Unicode lookup failure

User authorized removal of non-personal temporary build data. Removed ~188 MiB
of own compiler index/stat caches and ~1.4 GiB of unused temporary Gradle cache
at `/private/tmp/opengames-gradle1485/caches` after checking no process/open file
used it. Active other-project test logs, personal files and app backups retained.
Host free space reached 2.0 GiB but continued fluctuating.

Installed app's F5 upload of the 55-byte Unicode source reported failure during
verification, and its download also failed. Listing subsequently showed the
published file. Independent read-only backend download with a private copied
configuration and NFC spelling succeeded and cmp matched the original exactly.
Same download with the NFD spelling returned by the listing failed (exit 3,
directory not found). This isolates a real iCloud path-encoding issue rather
than treating a generic error or listing as successful acceptance.

`CloudConnection.address` now composes only iCloud wire paths to NFC, including
configured root and rename destination. Other providers' literal UTF-8 remains
unchanged; local filenames and configuration identity are not rewritten.
Runtime regression passed all 13 groups, including explicit UTF-8 byte checks
(Swift String equality alone is canonically equivalent and insufficient).
Updated app build and full cloud-client regression started. Live verification
of the corrected app remains pending at this point; no full-parity claim.

Also removed four unused Gradle distribution downloads (582 MiB), after checking
open files and confirming the sole Java process was an unrelated Firebase
emulator. These are re-downloadable tools, not project/user data. Total cleanup
performed in this continuation is approximately 2.1 GiB. Host free space later
rose above 6 GiB; changes from other concurrent work are not counted as our cleanup.

The first corrected build still failed live. Capturing its non-secret child
command showed NFD on the wire despite NFC in the command plan. Minimal native
Process→printf and Process→env experiments confirmed Foundation decomposes both
argv and environment strings on this Mac. Therefore a plan-only assertion was
insufficient. Added a signed native helper: bounded base64 JSON argv travels as
ASCII, then NSString UTF8String→execv preserves exact bytes without a shell.
Envelope is removed before exec; same PID/stdin/stdout/stderr and cancellation
remain. Runtime real-process tests passed 14 groups including exact NFC/NFD and
literal shell-metacharacter arguments. Building second correction; no failed
live run is counted as pass. Production host fails closed if packaged helper is
missing; build/installer validate helper presence and signature.

## Corrected native live results

Second build succeeded, including signed argument helper and unchanged stable
FSKit V2 identity. 15 runtime groups and 69 cloud-client groups passed; actual
backend runner (`--install`) also passed Unicode local fixture / immutable
refusal and synthetic Apple setup. All runners exited zero.

In the corrected native app, F5 downloaded the NFD-listed iCloud filename to own
Received folder, UI `iCloud Drive online: fertig`; independent cmp matches the
55-byte original. F5 from own Replacement folder showed explicit conflict
choices; chose Ersetzen. UI completed, independent read-only download matches
the 80-byte replacement. History entry 125 shows timestamp 08:05:16 and exact
own fixture source→iCloud route. Its specific Undo completed and independent
download+cmp restores original 55 bytes. Recovery versions retained, not purged.
F6 iCloud→own Moved folder now started for a fresh move acceptance.

F6 move subsequently completed. cmp confirms local bytes; independent lsf of
the own cloud folder shows original name absent and recovery objects retained.
Specific HistoryUndo-128 completed; local publication absent and independent
download+cmp confirms online original restored. Normal app quit/relaunch keeps
authentication and restores online test path. Only remaining pending-upload
manifest source was independently checked as this exact own Source fixture.
Explicitly selected Fortsetzen for that single earlier interrupted QA upload;
reconciliation is currently running, not yet counted as passed.

Reconciliation completed (`iCloud Drive online: fertig`), and no job.json remains
under CloudUploads. No new login required. Installed exact signed tested build
at `/Applications/OpenCommander.app`, retaining previous app at
`.build-native/App-before-install.SOC5Dv/OpenCommander.saved`. Deep strict
signature validation passed after install; normal installed app launched.
Removed only the private diagnostic configuration COPY after its read-only
checks; original connection, pins and recovery versions unchanged.

Scope: these are actual iCloud download, replacement, two Undo flows, move and
fresh-process pending-upload reconciliation, plus 69 cloud-client/15 runner
groups and installed backend fixtures. Earlier 177-group non-WebDAV regression
is documented separately. They do not individually execute every original Linux
manual acceptance variation, public sharing or fresh physical Elements tests.
WebDAV is deliberately excluded. No reboot, network/security setting change,
commit or push was performed.
