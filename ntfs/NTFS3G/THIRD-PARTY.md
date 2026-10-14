# Third-party source and licensing

This integration is GPL-2.0-or-later, NOT part of the independently written
MIT-licensed OpenCommanderNTFS Swift package.

## NTFS-3G

- Project: https://github.com/tuxera/ntfs-3g
- Release: 2026.7.7 (security release)
- Source: https://download.tuxera.com/opensource/ntfs-3g_ntfsprogs-2026.7.7.tgz
- SHA-256: `d67b769025d32860549d35c2147e45024d172f81c540d750390ce3602c059dab`
- The complete unmodified release source is retained in `vendor/`.
- Copyright, AUTHORS, COPYING and COPYING.LIB are in the source archive.
- Build uses the GPL-covered NTFS engine; no FUSE library is linked.
- `case-preserving-readdir.patch` changes directory enumeration to return the
  original on-disk spelling, without changing case-insensitive lookups or
  collision checks. The native and both universal builds apply it with zero
  fuzz to generated copies only. Include this patch and its application script
  in the corresponding source for distributed engine binaries.
- `directory-cookies.patch` fixes the bitmap-bit offset when directory
  enumeration resumes within a bitmap byte. Without it, a resumed final page
  can read unallocated index blocks and report EIO. It also applies only to
  generated native/universal copies with zero fuzz; include it in corresponding
  source along with the pagination and early-stop regression tests.

## NTFSKit engine facade

- Project: https://github.com/whereteam/ntfskit
- Revision: `b7153a8dd51b895d0a87345c6ad8e95bda963ed3`
- Original files: `NTFSModule/bridge/ntfs_bridge.c` and `ntfs_bridge.h`
- SPDX license in these files: GPL-2.0-or-later.
- Only the callback-backed byte-copy facade was adapted. No proprietary app
  UI, BitLocker, formatter, kernel-offloaded I/O or filesystem Swift code was imported.
- OpenCommander changes include required flush callback, checked I/O bounds,
  no automatic journal reset, read-only safety preflight, duplicate/name checks,
  propagated close errors and recovery-name-based replacement.

## Recovery inspection laboratory tool

- `build-recovery-inspector.sh` also compiles the pinned upstream
  `ntfsprogs/ntfsrecover.c`, `playlog.c` and `utils.c` under GPL-2.0-or-later.
- The entry-point symbol is renamed at compile time. `recovery-parser.patch`
  is applied only to a generated build copy, with zero fuzz; the retained vendor
  archive stays unmodified. The patch corrects the initial multi-page
  continuation distance and prevents a past-page record dereference. Both
  recovery tools include this patch; distribute it and the regression tests
  as part of their corresponding source. OpenCommander's
  GPL wrapper supplies fixed read-only/dry-run options and accepts regular
  test images only. The original copyright and license notices remain in the
  corresponding vendor source archive.
- This is not a physical-device repair tool or an installed app component.
  Its binary, if distributed, has the same corresponding-source obligations.
- The additional recovery sandbox compiles the same patched `ntfsrecover`
  source with renamed `main`, `ntfs_mount` and `fopen` symbols so that the GPL
  laboratory wrapper supplies a read-only boot stream and a disposable memory
  device. `playlog` remains unmodified. No source-device write implementation
  or physical apply operation is included; corresponding-source obligations
  also apply to distribution of this laboratory binary.
- `build-recovery-checkpoint.sh` builds a **separate** opt-in experimental
  checkpoint tool from the same GPL sources. Its additional GPL writer is
  restricted to exactly the two mapped `$LogFile` restart pages after sandbox
  replay, validation and durable local backup. The default overlay binary has
  no device-write implementation. Include the checkpoint source, patch,
  tests and build scripts in corresponding source for that experimental binary.

## Distribution gate

Distribute the corresponding source, this notice, COPYING, build/test scripts,
and complete vendor source alongside any binary containing this engine, in
accordance with GPLv2 section 3. Do not label the linked filesystem extension
MIT-only. Do not distribute an app-store binary before checking the compatibility
of its distribution terms with GPL obligations. This development work does not
grant a commercial Tuxera or Paragon license.
