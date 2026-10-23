# OpenCommander macOS 1.3 — corrected experimental GUI preview (2026-10-23)

Apple Silicon (arm64) only, macOS13 or newer. This is NOT a production/notarized
release. It is signed with Apple Development, not Developer ID. Gatekeeper may
reject this download. Do not disable macOS security protections. If blocked,
build the supplied source in Xcode or wait for a properly notarized release.

## Corrections

- Cross-process profile writer exclusion before queue/history initialization.
- Cloud move/replace recovery, cancellation, restart reconciliation and safer Undo.
- Drag-and-drop representations, modifier handling and file conflict recovery.
- Clear completed transfers with immediate queue/pagination refresh.
- Search, compare, multi-rename and keyboard/dialog Escape handling.
- File/archive properties, NAS transfer safety and localized diagnostics.
- More apps at https://haenggi.vip/ in help/settings across supported platforms.

## Important differences from the local development installation

This PUBLIC GUI package excludes the experimental FSKit NTFS extension,
privileged NTFS helper and device-bound provisioning profiles. It does NOT add
integrated NTFS writing on another Mac. The complete NTFS engine/integration,
licenses, pinned vendor source, patches and build/test scripts are included in
the separately downloadable matching source archive. NTFS image write/read and
detach/reattach tests passed on the locally approved development installation,
not on this driver-free public GUI package. Existing macOS-mounted volumes
remain subject to their own drivers and permissions.

The public copy has development/keychain-group entitlements removed and is
re-signed. Existing locally provisioned account credentials/grants are not
guaranteed to migrate to this packaging variant. Cloud services require a valid
account/provider connection and may require publisher OAuth configuration.
No user tokens, passwords, private keys or provisioning profiles are distributed.

## Verification and limits

Fresh automated file safety, transfer queue, durable copy/tree, cloud recovery,
OneDrive protocol, loopback FTP/FTPS/SFTP, drop representation, preview, handbook
and NTFS policy/image regression runners passed on2026-10-23. Native local
copy/move drags, Keep/Replace/Cancel, Undo, queue clearing and restart checks
passed on the separate test app. The installed development build launched and
passed its post-install NTFS image tests. These results do not certify every
external application/cloud combination or this public copy's new account flows.

Acceptance ledger:48 native-verified bounded cases,102 partial,8 requiring
account/hardware prerequisites;158 total. Full Linux parity is NOT certified.
WebDAV is excluded. Physical Elements/NAS and fresh personal2FA/multi-drive
account matrices were not repeated in this run. See the source's docs/
mac-regression-continuation-2026-10-23.md and acceptance ledger for exact scope.

## Install and provenance

Extract the ZIP and copy OpenCommander.app to Applications only after keeping
your previous app as a backup. Quit it before replacing. This does not bypass
Gatekeeper, protected-folder consent or filesystem-extension approval.

SOURCE-COMMIT.txt identifies the matching pushed source commit. The historical
macos-v1.2-preview.20260912 tag is unchanged; GitHub's automatic source links for
that OLD tag still refer to its OLD commit. Use the explicitly dated matching
source asset for these corrections. Original September assets remain available.

OpenCommander GUI, ZIPFoundation and Zstandard licenses accompany the GUI ZIP.
The source's NTFS-3G integration is separately GPL-2.0-or-later, not MIT-only.
