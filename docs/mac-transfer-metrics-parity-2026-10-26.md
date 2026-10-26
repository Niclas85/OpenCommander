# Transfer metrics parity, Build25, 26 October 2026

## Direct reference audit and implemented gaps

The original JOB-01/JOB-02 requirements were read alongside
`linux/opencommander/transfers_ui.py`, `linux/opencommander/formatting.py` and
`linux/tests/test_formatting.py`. The Mac UI had decimal single-unit elapsed
labels and no file count, throughput or ETA. Ordinary copied-byte progress could
also reach100% before destination publication. These were actual gaps, not just
unexecuted manual tests.

- `CommanderDuration` now uses the exact Linux component form, truncating
  fractions, clamping negative durations to zero and localizing day singular/
  plural. Nonfinite inputs show an em dash; huge finite inputs cannot overflow
  an Int. The thirteen boundary vectors were independently run against the
  original Python function and both Swift language variants.
- Queue copy progress is capped at99% until successful completion. The separate
  labelled verification meter may still reach100%; it does not mean publication.
- Optional persisted file counts preserve compatibility with existing queues.
  Regular copies count one file, trees count leaf files/symlinks (not directories),
  and the NAS exclusive-copy adapter emits verified file completions. Resuming
  starts from the journal's completed entries rather than counting them twice.
  Zero-byte files count; empty directories do not pretend to be files. Legacy
  unavailable counters are displayed as unknown.
- A bounded presentation-only rolling sampler uses monotonic time and new byte
  deltas, never saved bytes divided by time since restart. Pause, control
  requests, verification, counter/time resets and a three-second stall invalidate
  the estimate. Unknown speed/ETA uses an em dash. Nothing in the sampler decides
  scheduling, data integrity, resumption or publication.
- Expanded transfer details and accessibility descriptions include counts,
  speed and remaining estimate in German/English. The same controls, cards,
  keyboard operations and durable journals remain in use.

## Actual regression evidence

All following scripts exited0:

- `/tmp/opencommander-b25-transfer-queue-final3.log`:35 PASS groups. Includes
  fresh-rate versus saved-byte distinction, pause/stall/verification/reset
  refusal,99/100 boundary, persisted regular-file counters, and production NAS
  adapter on an **owned local fixture**, with pause/resume/replay, byte-exact
  payload, zero-byte file and empty directory. This is not live SMB acceptance.
- `/tmp/opencommander-b25-durable-tree.log`:7 PASS groups including resumed
  file counts, Unicode/hidden files/symlink, monotonic count, rollback and Undo.
- `/tmp/opencommander-b25-swift-safety.log`:41 PASS groups including thirteen
  original duration vectors for German and English, huge finite/nonfinite input.
- `/tmp/opencommander-b25-linux-duration-reference.log`: original Python
  formatting function,13 independent expected vectors. No full Linux pytest
  environment exists here; that suite is not claimed executed.
- `/tmp/opencommander-b25-ntfs-transfer.log`:22 PASS groups. New64MiB image
  `/private/tmp/OpenCommander-NTFS-Queue-tDwb2z/test.ntfs`, current Swift transfer
  engines with the **installed Build23** FSKit driver. Foundation and durable
  file/tree copies passed; full detach/reattach resumed byte-exactly. Both disk6
  attachments ejected. No physical Elements/NAS pass inferred.
- All27 localization dictionaries pass duplicate-key checks; git diff whitespace
  check passes.

Two intermediate additions to the queue test failed to compile (throwing work
inside nonthrowing assertion autoclosures, then an undefined test-local `fm`).
They were corrected before the final successful run; those attempts are not
passes. An accidental no-argument invocation of the physical NAS script refused
before any filesystem work and is not counted as a live test.

## Build and remaining native gate

Release Build25 and the29-test native debug target both built successfully.
UI clone FSKit extension detached before ad-hoc signing, preserving the normal
installed driver. The new native metrics test prepares only its own saved paused
fixture; it must confirm the visible exact duration, file count, unknown paused
speed/ETA and99% unpublished status. Merely compiling it is not acceptance.

Full writable-NTFS candidate signed with the existing Developer ID and exact
distribution profiles:
`ntfs/NTFS3G/.build-native/developer-id-signed-20261026-b25/OpenCommander.app`.
Apple Accepted submission `12658beb-e7d6-48ed-a782-635c79d60e3b`.
`/tmp/opencommander-b25-release-build.log`, `...b25-ui-build.log`,
`...b25-sign.log`, `...b25-notary-status.json`.

Build24 is superseded by these source changes and is not an installation
candidate for the final corrected state. Installed Build23 remains unchanged
until relevant native acceptance passes. Full158-case parity remains unproven.

The focused final native run subsequently **passed both tests**, zero failures,
51.717s, exit0: actual900x600 and1366x768 complete settings/picker/German queue
sequences and the new visible paused metrics test. No system permission was
changed by the agent. `/tmp/opencommander-b25-metrics-window-native.log`, result
`ui-20261025/Logs/Test/Test-OpenCommander-2026.10.26_08-20-24-+0100.xcresult`.
Stapling and the full writable-NTFS distribution/Gatekeeper gate also passed:
`/tmp/opencommander-b25-staple.log`, `/tmp/opencommander-b25-distribution.log`.

## Environment and cleanup

Relocating a copy of the existing24 test products entirely into
`/private/tmp/OpenCommander-IsolatedUI-20261026.COu7pi` did not initialize
XCTest automation (timeout, exit65, zero tests executed). A manually bound copied
app refused concurrent normal-profile access, then its own OK closed it. The
existing profile/queue/history were not opened by that second instance. No
protected OS prompt was operated and no security permission was changed.

Disk fell from7.7GiB free to191MiB during the turn; current host swap usage was
13,271.94MiB. That observation does not prove which process caused the disk loss.
Only three validated, inactive, own ModuleCache.noindex directories were
removed (developer-id-release, experimental-app, ui-20261025), reclaiming about
806MiB; they are regenerable. Five64MiB own unmounted fixtures (Rl6xzu, J5VKu9,
TgotZ8, DCOqzr, aZTHNp) were losslessly compressed with originals retained until
all gzip integrity checks passed, then only those uncompressed originals were
removed. All images remain recoverable by decompression. Sources, account data,
logs, app backups, existing installations and personal files were preserved.

## Remaining real functional gap found during reference audit

JOB-06 is not merely missing a test. `ViewController.showProgress` still disables
the main view's interaction for foreground cloud/server mutations, retaining
only the separate Settings/Help/Cancel access. `operationInProgress` also
suppresses normal file keyboard commands and mutation menus. Linux expects
normal unrelated folder/location navigation during a slow copy. Build25's
local durable queue is background-capable; its improvements must not be cited
as fixing that separate foreground-cloud behavior. A safe follow-up needs
operation-owned immutable source/destination snapshots and explicit mutation
reservations before enabling independent pane navigation; simply deleting the
interaction guard risks redirecting completion/Undo or racing a reserved path.
The frozen25 acceptance and install gate do not establish full parity here.

The reference branch was rechecked with read-only ls-remote on26 October:
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`, unchanged.

## Full native regression and completed incremental installation

The complete final `MacDesktopParityTests` suite **passed29 tests, zero failures,
588.011s, exit0**. Includes the final-source queue pointer-return, exact metrics,
both real window sizes, copy/move drop toggle and readonly refusal, restart/
history/Undo, clipboard text-field safety, search paths, cancellation and retry,
quota cache, archive rejection and20,000-entry cold/filter/warm navigation.
`/tmp/opencommander-b25-full-native.log`, result
`ui-20261025/Logs/Test/Test-OpenCommander-2026.10.26_08-22-21-+0100.xcresult`.
This29-case native suite is not the entire158-case original manual matrix.

Focused900/1366 Retina attachments retained at
`/private/tmp/OpenCommander-B25-WindowEvidence.T7CKCE`. Wide settings and German
queue screenshots inspected: controls contained/readable, both file panes
present, no blocking system dialog. No private/background screenshot is added
to public repository artifacts.

Production UI and saved store both confirmed zero jobs, no active transfer.
Normal Cmd-Q terminated the actual installed process before exchange. Build23
was moved, not deleted, to
`ntfs/NTFS3G/.build-native/App-before-b25.pUUtWH/OpenCommander.previous`.
Exact signed/notarized/stapled Build25 copied to `/Applications/OpenCommander.app`;
installed Info reports25, executable cmp matches candidate, full distribution/
Gatekeeper gate passes. Started production PID9272 from `/Applications`.
No preferences, history, account configuration or account credential was copied
from test fixtures or rewritten for installation.

Post-install `test-fskit.sh` exited0 with22 PASS groups. Only new64MiB own image
`.build-native/fskit-fixture.Aa7PQR/test.ntfs` was attached. Installed25 FSKit
write/read/case-only rename/replace/delete/truncate/fsync/timestamps passed;
independent Apple readonly reopen confirmed persisted Unicode/data/timestamps.
Both disk6 attachments ejected. `/tmp/opencommander-b25-installed-ntfs.log`;
`/tmp/opencommander-b25-installed-distribution.log` confirms final installed gate.

Existing OneDrive, Google Drive and Dropbox online locations opened after the
actual app update without new sign-in. OneDrive and Dropbox exposed real file
rows. An initial Google AX snapshot exposed no table rows despite a populated
folder tree; this was NOT treated as an empty directory or a pass by itself.
Reopen and actual app screenshot confirmed a populated Google file list and711
listed items. Its existing duplicate-name safety warning remains visible;
ambiguous entries are hidden and whole-folder copy/compare protected. No user
duplicates were changed or deleted. This verifies account/list continuity, not
new destructive per-provider move/share/network-loss acceptance. The original
leftroot and rightiCloud Drive panes and German language were restored.

No NAS is mounted; read-only TCP445 probe to192.168.0.22 failed. No physical
Elements test is inferred from synthetic images. No reboot, commit, push or
new public release was performed. The overall goal remains active: particularly
JOB-06's foreground-cloud navigation gap and the remaining provider/device/
external-application matrix are still explicitly open.
