# NAS move, metadata and reconnect acceptance — 2026-10-18

Follow-up to `mac-nas-exclusive-copy-2026-10-18.md`. Only fresh
`OpenCommander-LiveQA-*` fixtures were modified. Personal files were not used.

## Implementation

- The durable queue uses the exclusive NAS engine for copies and moves when
  either endpoint is SMB. A move verifies content and metadata, then retains
  its source under a private `.OpenCommanderMoved-<job>/` recovery directory.
- Version-2 journals reconcile lost write, backup-rename and source-rename
  acknowledgements. Same-share remounts may change the device number; stable
  volume identity is checked before accepting that change.
- Connection errors pause the queue with a reconnect/resume explanation.
  Resuming verifies the existing prefix; changed partial files are refused.
- Undo restores the retained source through exclusive creation before retaining
  the destination. Recovery copies are deliberately kept, not silently deleted.
- Finder tags, FinderInfo, resource forks, other bounded extended attributes,
  creation/modification dates and hidden flags are preserved and verified.
  SMB mode masks are synthetic: original POSIX rwx bits are retained in a
  portable attribute and restored on return, not represented as server ACLs.
- Fresh NAS directory enumeration sometimes returned creation time as mtime.
  Reopening alone was insufficient. Timestamp-only mismatches now have a
  bounded 64-second retry window; pause/cancel remains checked. Other metadata
  changes fail immediately. Different timestamps are never accepted as equal.

## Evidence

Logs below are in `ntfs/NTFS3G/.build-native/`:

- `nas-move-final.log`: all cases passed on mounted `192.168.0.22/Test` and
  physical Elements NTFS, including Unicode/hidden/empty trees, byte hashes,
  new-process resume, cancellation, concurrent exclusive creation, replacement,
  overwrite undo, lost acknowledgements, move replay and move undo.
- Physical Elements → NAS → Elements move verifies bytes, extended attributes,
  absence of the original public names and presence of both recovery sources.
- Finder metadata and mode 0751 survived local → NAS → local; hidden-only
  flag roundtrip passed separately. A changed source xattr blocked its move.
- Explicit ACL case returned `ACL_HIDDEN_SERVER_UNSUPPORTED_SOURCE_RETAINED`:
  safe refusal passed, native ACL preservation did **not** pass on this server.
- `nas-move-safety.log` and `nas-move-queue.log`: regression runners exited 0.
- `nas-move-final-build.log`: stable NTFS V2 Mac Catalyst build and extension
  signature verification succeeded.
- Isolated SMB mount `/private/tmp/OpenCommander-NASMount.Tu7678` was normally
  unmounted after an injected lost-write acknowledgement. Resume while absent
  refused; same-share remount and fresh-process resume succeeded, with an
  exact 8 MiB comparison. The ordinary NAS mount was left connected. The
  isolated mount was normally unmounted again after the check.

## Boundaries

The disconnect check combines real mount disappearance with an injected
connection error. It is not a physical cable-pull, server power-loss or arbitrary
TCP failure test. ACLs unsupported by the server stop the move safely rather
than being silently discarded. Incomplete new targets may be visible until
completion; private recovery versions consume disk space and remain available.
These results do not establish universal NAS compatibility or full Linux parity.

## UI and installation

The freshly built app completed F6 Elements → NAS and F6 NAS → Elements in
the visible UI. The Undo button then reported one action undone, restoring the
NAS folder and removing the public Elements destination. Data and tree shape
matched the fixture (excluding AppleDouble sidecars consumed by fixture `ditto`).

UI fixtures: NAS `OpenCommander-LiveQA-MoveUI-9JAfTN`, Elements
`OpenCommander-LiveQA-MoveUI-1avO9Q`.

Installed at `/Applications/OpenCommander.app` after normal app quit and normal
Elements unmount; no reboot or forced unmount. Previous application retained at
`ntfs/NTFS3G/.build-native/App-before-install.tvKcZ3/OpenCommander.saved`.
Installed debug dylib SHA-256:
`dea0d00a096c2a76cb9e5d064cbb552a2268c528153dac357c4a904c00dc2f8c`.
The stable V2 extension passed signature verification. Elements reappeared as
writable `openntfs` with existing authorization after remount. Installed-app
NAS → Elements and Elements → NAS F6 both reported completion at 100%.
Final data/tree comparison passed and the moved public source was absent.
