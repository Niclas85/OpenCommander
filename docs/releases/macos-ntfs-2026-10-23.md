# OpenCommander macOS 1.3 — notarized experimental NTFS preview r2

Revision r2 corrects the first October NTFS package's native FSKit signing
entitlements. The first package passed notarization/Gatekeeper but macOS refused
to launch its extension because a Catalyst-only `application-identifier` was not
authorized by the native module's profile. Use the **r2** asset, not the first ZIP.
The distribution gate now independently checks each restricted signed identity
against the corresponding profile, with regression tests for this exact failure.

Apple Silicon (arm64). GUI requires macOS 13 or newer; integrated NTFS writing
requires macOS 15.4 or newer and approval of the included FSKit extension.
This is an experimental preview, not a claim of complete Linux feature parity.

## Complete NTFS distribution

This package includes the NTFS-3G-backed writable FSKit module
**OpenCommander NTFS 2**, the narrowly scoped NTFS authorization helper, and
unrestricted Developer ID distribution profiles. All executable components are
Developer ID signed with hardened runtime. Apple accepted the complete app for
notarization on 2026-10-23; its ticket is attached and Gatekeeper validation is
required by the packaging script. Notarization is not a filesystem reliability
certification or App Store review.

No publisher API key, private signing key, password, cloud token or account
configuration is included. End users do not need an Apple developer account.

Quit OpenCommander and preserve your previous app before copying the new app
to Applications. macOS may request approval of the filesystem extension and
administrator authorization for its mount helper. These approvals cannot be
pre-granted by a public download. Do not disable Gatekeeper or other security
protections. Unsafe/hibernated or damaged NTFS volumes may be refused writable
mounts to protect their contents; writing is not guaranteed for every disk state.

## Features, evidence and limits

Includes the October corrections for cloud move/replace recovery, cancellation,
restart reconciliation, drag-and-drop representations/modifiers, Undo, transfer
queue clearing/pagination, search, compare, multi-rename, NAS safety and localized
diagnostics. Help/settings include https://haenggi.vip/ for more apps.

Revision r2 was installed and passed mounted NTFS image write/read, Unicode,
case-preserving listing, rename/replace/delete, timestamps, copy, truncate and
fsync tests. After detach, Apple's independent read-only NTFS driver verified
persisted bytes and metadata. The image was safely detached again. The public
candidate also passed the strengthened signature/profile/NTFS-component/
notarization/Gatekeeper gate and eight distribution policy regression tests.
This does not replace a fresh install and physical disk test on every target Mac.
Physical Elements/NAS tests were not repeated during this signing/release run.

Acceptance ledger: 48 native-verified bounded cases, 102 partial, 8 needing
account/hardware prerequisites; 158 total. Full Linux parity is NOT certified.
WebDAV remains excluded. Personal cloud sign-in and third-party drag combinations
remain subject to the detailed acceptance ledger in the corresponding source.
Keep backups before using experimental NTFS writing on important data.

## Source and licenses

Use the separately published `OpenCommander-<commit>-ntfs-source.zip` matching
SOURCE-COMMIT.txt. It includes the GPL NTFS engine's complete pinned vendor
source, patches, integration, build/test scripts, COPYING and notices. The NTFS
integration is GPL-2.0-or-later, not MIT-only. The GUI, ZIPFoundation and Zstandard
licenses also accompany this download. The old September release tag is not
moved: GitHub's automatic source links for that tag still point to its old code.

This full NTFS asset supersedes the driver-free October GUI preview for users
who need integrated NTFS. Older assets remain available and are separately named.
