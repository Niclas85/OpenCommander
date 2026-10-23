# Actual abrupt-process recovery — 19 October 2026

This extends the Linux parity acceptance without WebDAV. These are isolated
production-engine tests, not a claim that every native GUI/provider case passes.
No personal files, production credentials, app process or host network changed.
Only test children sent SIGKILL to themselves; the computer was not restarted.

## Local copy during data transfer

New runner `ios/tests/DurableCopyCrashTests/main.swift` generates a deterministic
1-MiB source inside a fresh `/private/tmp/OpenCommander-DurableCrash-*` directory.
Separate processes prepare, copy until the durably saved 64-KiB checkpoint and
kill themselves, then inspect and explicitly resume. Harness requires actual
signal exit 137; ordinary errors/completion do not count as the requested crash.

Fresh process finds readable copying journal at exactly 65,536 bytes, no visible
destination, unchanged source. Resume starts at that checkpoint, checks prefix,
completes, and both source and destination match every byte. Entire durable-copy
runner exits 0, 12 PASS groups including previous corruption/identity cases.
Log: `ntfs/NTFS3G/.build-native/parity-20261019-local-sigkill.log`.

## Cloud move committed but response lost

Production PendingCrossCloudMove/CloudFileClient/PendingOnlineMove use the
existing synthetic filesystem transport, not Google/Dropbox infrastructure.
Four independent fixtures: target absent/replacement, each killed immediately
after target publication/source retention rename committed but BEFORE callback.
Each actual SIGKILL is required by the harness; normal throws are insufficient.

Another process deliberately changes that fixture's visible or retained source.
Resume refuses cleanup, preserves changed source, exact verified destination and
pending intent. Only synthetic source bytes are then restored. Another fresh
process reconciles completion, publishes exact destination and retains precisely
one source recovery object. A final process obtains Undo, restores original
source and previous target (or removes only newly published target), verifies
exact bytes and explicitly removes completed journal. All four variants pass.

Final cloud-client runner exits 0, 85 PASS groups, including the 69 previous
groups and four new groups for each actual-kill variant. Earlier 81-group run
passed without changed-source probes; final run supersedes its coverage.
Log: `ntfs/NTFS3G/.build-native/parity-20261019-cloud-sigkill-final.log`.

## Remaining scope

REC-03 and REC-10 remain partial: this does not prove native recovery-dialog
visibility, physical filesystem-crossing cleanup, an interrupted host network,
or every real provider. WebDAV alone is excluded; SMB/NAS remains in scope.
No product change was necessary for the passing abrupt-loss recovery cases.

## Native naming follow-up

In the isolated special test app, F2 renamed own Source.txt to Grüsse-Prüfung.txt;
independent comparison against the prior own Right/Source.txt was exact. Existing
Clipboard.txt collision preserved both names but displayed only generic failure.
Invalid ../Invalid.txt was refused with explicit valid-name message and no file
outside Left. Command-Shift-N created Neuer Ordner – Zürich in Left, visible in
the same pane and independently present as a directory.

Changed rename preflight to lstat-based existence (also catches dangling-link
collisions), with specific localized existing-target message. Worker OS errors
use existing coded app-language error presentation rather than generic failure.
Signed candidate build completed successfully, including stable V2 extension and
helper checks (`parity-20261019-rename-errors-build.log`). File safety runner
passes 32 groups (`parity-20261019-rename-safety.log`). Refreshed only the isolated
clone, detaching its filesystem extension before ad-hoc signing. Normal installed
app and its registration remain unchanged.

Corrected native repeat explicitly reports existing destination/data not replaced;
both filenames remain. Temporarily changed own Left directory from 0755 to 0555:
rename to NoWrite.txt refused with explicit access denied/read-only message,
source bytes unchanged, destination absent. Restored directory to original 0755.
Independent Clipboard.txt SHA-256 unchanged before/after collision and permission
tests. New folder shortcut is Command-Shift-N, the macOS counterpart of Linux
Control-Shift-N. This bounded FILE-08 sequence has native evidence; exhaustive
case-only naming behavior and all online-provider variants are separate scope.
