# Finder Command-drag acceptance — 2026-10-17

Reference fetched again: `origin/codex/linux-desktop` remains
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`.

## Root cause and implementation

Finder offers its Command drag as AppKit's generic operation (mask 4), which
Catalyst's copy/move drop proposals cannot accept. Returning a UIKit copy proposal
alone was tested and did not solve the problem; that attempted change was removed.
A native original-file-URL receiver now routes external drops into the existing
local or online transfer pipeline, with original-file validation, conflict
handling, verified source retention and History Undo.

External tracking reads the live modifier state, not a stale `NSApp.currentEvent`.
The last negotiated modifier state is retained through mouse-up, including an
immediate Command release. The native receiver unregisters while OpenCommander
is foreground, leaving internal UIKit and online/ZIP promise drags untouched.
Ordinary clicks pass through. Local and online receiver paths share their
existing tree-hover and edge-scroll logic, with exit/commit cleanup.

## Live evidence

Only synthetic files in `.build-native/google-live-9hIyW4/` and the existing
`OpenCommander-Google-QA-20261017-9hIyW4` cloud fixture were used.

- Finder Command → local: original path removed, target byte-for-byte equal to
  the independent prior copy; private recoverable source retained.
- Undo: original restored exactly, moved destination retired.
- Finder Option: identical destination; original remains.
- Internal Command move: passed after fixing an initial native-overlay
  interception regression. The failing attempts are not counted as passes.
- Finder Command conflict → Cancel: both original and existing target unchanged.
- Finder Command → Google Drive: completed, local original retained outside its
  original path, independent rclone readback SHA-256
  `baf3a0fa016843f0a74225448186d72aac2e8748f4b0fb4e5529e22df834a3d3`.
- Google Undo: UI reported one action undone; original restored exactly;
  independent online listing no longer contains `Command.txt`. Recovery entries
  were retained, not permanently deleted.

## Automated evidence

- File-provider tests: eleven groups, 32 modifier combinations and external
  semantic-move assertions passed.
- Commander tools: three groups passed (search, comparison, batch rename).
- Durable tree: seven groups passed, including source-retention recovery.
- Queue: seven groups passed, including restart and mutation reservations.
- Cloud: 54 groups passed, including 22 separate-process recovery phases.
  Log: `.build-native/finder-command-cloud-regression.log`.
- Handbook: both groups passed; native Finder guidance updated in DE/EN.
- NTFS access and registration: six groups passed without changing approval.
- Durable regular copy: ten groups passed.

## Final installed build

Signed build and exact FSKit signature/identity checks passed in
`.build-native/finder-native-final-build.log`. Installed at
`/Applications/OpenCommander.app`; rollback copy retained at
`.build-native/App-before-install.YbtDLk/OpenCommander.saved`.

After the final hover/scroll integration, Finder Command onto the `Child` folder
row moved the exact bytes into that child, not its parent. Undo restored the
original. Command-Option caused no transfer. After installation, the folder-row
Command move and Undo passed again; an internal Command move and Undo also
passed. The app was left open with its original iCloud/Downloads locations.

The installed NTFS extension passed the isolated-image integration suite:
native engine checks, Foundation and durable APFS-to-NTFS file/folder copies,
and paused-copy resume after full detach/reattach with exact bytes. The newly
created image was detached cleanly. Log:
`.build-native/finder-command-ntfs-image.log`; retained fixture:
`/private/tmp/OpenCommander-NTFS-Queue-MuiX7k`. This is not a physical Elements test.

Native hover/edge-scroll now reuses the existing handlers; exhaustive visible
hover/scroll permutations are not claimed from the folder-row acceptance.

## Scope limits

This is not a claim of exhaustive Linux reachable-state parity or compatibility
with every third-party source application. Physical Elements is unavailable.
Existing historical NTFS evidence remains distinct from new image tests.
No Mac restart, approval change, commit or push was performed.
