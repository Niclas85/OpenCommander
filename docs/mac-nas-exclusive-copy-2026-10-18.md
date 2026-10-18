# NAS exclusive copy acceptance — 2026-10-18

Scope: copying regular files and directories between the user's Elements NTFS
partition and the mounted SMB share `192.168.0.22/Test`. No personal file was
modified, no forced unmount, repair, formatting or OS restart was performed.

## Implementation

SMB copy jobs now use `NASExclusiveCopy` through the durable queue. Public files
are created with exclusive/no-follow flags and directories with exclusive mkdir.
Each item has a job ownership marker. Resume verifies the marker and existing
bytes before continuing. SHA-256 readback validates completed content. There is
no fallback from unsupported exclusive rename to a public overwriting rename.

The public target is visible while incomplete. The queue explicitly warns about
this, including compact cards and cancellation. Cancelled NAS recovery cards
cannot be forgotten through the queue. The source and partial copy are retained.
Explicit replacement claims and moves the old version into that job's private
recovery directory before exclusive creation of the new target. Undo restores
the backup through the same exclusive engine on SMB. Backups remain available.

The snapshot verifier opens an authoritative source descriptor before capturing
SMB attributes and checks that descriptor throughout the read. This corrects
false source-change failures caused by first-open SMB attribute refresh.

## Passed evidence

- `nas-final-live.log`: own fixtures `OpenCommander-LiveQA-Final-Qx72f8` on NAS
  and `OpenCommander-LiveQA-Final-JqQpaE` on Elements. Nested directories, empty
  folders, hidden files, Unicode names and 3 MiB+17-byte deterministic content.
- Pause and resume in a fresh process; changed partial data is refused without
  truncation; 20 concurrent same-name races each have exactly one winner.
- NAS replacement retains old contents; NAS-to-Elements production tree copy
  and overwrite retain the previous version; NAS replacement undo restores old
  bytes; cancellation preserves source and partial destination.
- `nas-final-safety.log` and `nas-final-queue.log`: both regression runners pass.
- Actual app UI before installation: F5 Elements-to-NAS, Ersetzen, Rückgängig
  (UI confirms one action undone), reverse NAS-to-Elements and Behalten.
  Queue reports completed; engine selection persisted as `nas-exclusive` on SMB.
- App UI fixtures: NAS `OpenCommander-LiveQA-UI-vx0o8b`, Elements
  `OpenCommander-LiveQA-UIBack-Ci4ngc`. Recursive content comparison passes
  excluding filesystem-generated AppleDouble `._*` sidecars.

## Installation

Final signed Catalyst build and signature preflight passed. Elements was normally
unmounted for the update. Installed `/Applications/OpenCommander.app`; previous
app retained at `.build-native/App-before-install.qarNKf/OpenCommander.saved`.
Installed dylib SHA-256:
`5c215e8354d1bbb96cc885ed00366e9a417823e43f52afe00da087717e785df4`.
Normal app identity/preferences retained. Elements remounted writable using
existing authorization; no new access grant or reboot was required.

Post-install UI verification also passed in both directions: `Source (2)` from
NAS to Elements, followed by a keep-both copy to NAS `Source (2) (2)`. Both cards
show Abgeschlossen / 100%; persisted engines are `tree` and `nas-exclusive`.
Recursive byte comparison (excluding generated AppleDouble sidecars) passed in
both directions. Installed app deep/strict signature verification passes.

## Explicit limits

This is not an assertion of all Linux parity or all NAS/server behaviors.
Physical cable/network-loss and server power-loss were not induced. The engine
requires ownership xattrs, rejects symlinks/special files, and does not promise
ACL/resource-fork/extended-attribute preservation. NAS move jobs are not converted
to copy-and-delete; existing safety refusal remains. Older failed jobs are not
silently migrated. Tests and recovery files are retained for investigation.
