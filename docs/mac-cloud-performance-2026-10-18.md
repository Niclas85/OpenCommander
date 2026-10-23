# Cloud performance continuation

## Implemented

- Process-local rclone executable digest reuse across bridge requests. Every hit
  rechecks device/inode, size, owner/group, mode and nanosecond mtime/ctime, plus
  the expected digest marker. A changed executable requires a full hash; remote
  content and account proofs are not cached.
- Removed the redundant listremotes subprocess for normal IO. The private
  configuration still undergoes bounded parsing, exact remote/type validation,
  credential validation and configuration-lease checks. Explicit profile discovery
  still invokes listremotes.

## Evidence

- Runtime tests: 11 PASS groups, including restored-mtime modification, digest
  marker mutation, permissions and symlink refusal; fresh bridge-runtime instances
  reuse only unchanged local binary proof.
- Benchmark: 20 full executable hashes 1.3489 s; 20 validated identity checks
  0.0021 s (631.8x for this local substep, NOT end-to-end cloud transfer speed).
- Configuration lease tests: 5 PASS groups.
- Native Catalyst build and extension signatures passed (`cloud-performance-build.log`).
- Candidate Dropbox listing, folder navigation and a.txt preview passed; visible
  text was ABCD. Google listing timed out under severe host storage pressure.
- Full cloud-client regression compilation was explicitly stopped after free
  storage fell to 178 MiB. This run is NOT a passing regression result. Only own
  rebuildable compiler caches were removed; space recovered to about 1.3 GiB.

## Reference and remaining work

Fetched origin; Linux branch remains e3b2981. Existing 158-case acceptance ledger
is not reclassified: full native parity is not proven. In particular, WebDAV/GIO
equivalence and service-dependent iCloud/sharing/mount cases remain unaccepted.
No new Linux feature implementation is claimed by this performance change.

Candidate remains separate and was quit normally. Installed app is unchanged
from the previously accepted cloud replacement release. Do not install this
candidate until full regression and Google live access have been rerun with
sufficient stable free space. No restart or personal-file cleanup was performed.

## 2026-10-19 acceptance and installation

Free space recovered to 13 GiB before work; no further deletion was necessary.
Full cloud-client regression rerun completed with 69 PASS groups (including
fresh-process replacement/resume/Undo): `cloud-performance-clients-retry.log`.
Candidate Google listing loaded the QA folder without another authentication
prompt or timeout. Prior Dropbox native navigation and exact ABCD preview passed.
Installed the tested signed candidate at `/Applications/OpenCommander.app` and
verified normal startup. Previous version remains recoverable at
`.build-native/App-before-install.BSQRin/OpenCommander.saved`.
About 10 GiB remained after tests. This supersedes the installation hold above;
it does not certify full Linux parity or an end-to-end transfer speedup factor.
