# Mac/Linux parity continuation — 2026-10-15

## Follow-up: durable cloud uploads and drag/drop acceptance

- Added an atomic persisted upload journal and private prepared content for
  non-replacing copies from local storage or another online provider. Opening
  the destination online pane (or refreshing it) offers pending uploads.
- Recovery checks the endpoint, account, restored parent and staged hashes.
  Partial directories are checked before missing descendants are added.
  Changed targets are refused; ambiguous already-completed uploads deliberately
  receive no destructive Undo ownership. Concurrent replay of one job is refused.
- Synthetic cloud tests passed for journal reload, missing original source,
  account mismatch, partial folders, conflicting destination and completed-upload
  reconciliation. These are NOT an authenticated app-kill/relaunch acceptance.
- Native file-provider drag/drop tests passed all eight groups, including
  promised folders/files, raw URLs, extensionless files, failures and timeouts.
  Physical mouse drag/drop, cross-app hover/cancel and authenticated cloud drag/drop
  are still not accepted. The isolated UI fixture is open for a real mouse check.
- Still incomplete: durable downloads, move/replacement recovery, byte-offset
  upload sessions, migration of legacy temporary staging, and recovery UI live
  acceptance. Upload preparation itself must finish before it is recoverable.
- Installed application remains unchanged. No release or full parity claim.

## Changes

- Integrated the `linux/` changes from a8839e0 through upstream
  `86aaca7abd04173b649227990dd9e40cb069cadc`. Retained the existing backup
  verification before destructive Undo. Windows-specific modules are shared-tree
  dependencies, not a claim that Windows device APIs were ported to macOS.
- Native Mac Undo for known CloudStorage/Mobile Documents paths now persists a
  provider proof that tolerates an unchanged inode refresh, while retaining
  device, metadata and content verification. Older saved proofs remain strict.
  All snapshots now also reject identity/metadata changes during verification.
- Fixed the NTFS transfer integration harness's obsolete hardcoded `openntfs`
  alias: verify the installed extension signature, read its allowlisted FS type
  (`openntfs2` here), and bound each mount invocation to 45 seconds.

## Verified this turn

- Mac Catalyst arm64 Debug build succeeded, signing disabled. New build not
  installed; the installed signed build14 NTFS service was left in place.
- Native file safety suite, including new inode refresh, content-change,
  path-prefix and in-read replacement regressions, passed.
- Swift cloud client, durable file/tree transfer, queue, NTFS access-policy and
  registration suites passed.
- Linux portable online suite: **24 passed, 5 skipped** with isolated Python
  3.11 / PySide6 6.11.2. This is not a real Linux desktop acceptance test.
- Full Linux operations/resume attempt on macOS: **17 passed, 61 failed**;
  Linux-only `renameat2` and mount assumptions prevent using this as a parity
  pass. Do not hide or reinterpret these results as Linux-host validation.
- NTFS native image suite passed, including metadata, pagination, disk-full,
  write/flush failure propagation, persistence and hibernation write refusal.
- Mounted isolated NTFS image: Foundation file/folder and durable file/tree
  copies passed. A paused copy resumed after full image detach/reattach with
  exact byte equality. Both attachments detached normally. Initial attempt used
  the obsolete alias and failed before copying; the corrected rerun passed.
- No external physical disk was present according to `diskutil list external
  physical`. No Elements test or existing-data changes this turn; no reboot.

## Evidence

- `/tmp/OpenCommander-Parity-20261015-build.log`
- `/tmp/OpenCommander-Parity-20261015-ntfs.log`
- `/tmp/OpenCommander-Parity-20261015-mounted-ntfs.log`
- `/tmp/OpenCommander-Parity-20261015-online.log`
- Retained isolated image: `/private/tmp/OpenCommander-NTFS-Queue-fZVyEJ/test.ntfs`

## Still open

Full native parity is **not complete**. The remaining list in
`ios/MAC-LINUX-PARITY.json` still applies: durable direct-cloud restart/adoption,
cross-backend move Undo and per-item failure recovery, Google-native export and
media-cache lifecycle, global workflow/window reservations, authenticated provider
acceptance and all physical external drag/drop states. Physical USB reconnect,
multiple NTFS drives and helper failure recovery also require further acceptance.
No commit, push or installed-app replacement performed this turn.
