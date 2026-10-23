# Full NTFS public distribution preparation — 2026-10-23

User explicitly requested the public NTFS-writing feature, approved creating the
Developer ID certificate/profiles, and supplied the CSR contact address privately.
No existing certificate revoked. Existing installed app and public GUI-only
preview remain unchanged in this preparation.

## Completed

- Apple portal was already signed into team WB497999XX. Developer ID Application
  G2 creation available; no existing Developer ID certificate found initially.
- Native Certificate Assistant reached the CSR form, but the Mac subsequently
  locked. Automatic native access failed; no screen unlock or bypass attempted.
- Read-only Security API check found the existing login keychain unlocked.
  `create-developer-id-csr.swift` disables interactive authentication in its own
  process, creates a new dedicated permanent RSA2048 key, and
  signs a public PKCS#10 request using Apple's Security framework. It never
  exports the private key, handles a login password or unlocks a keychain.
  The request included isExtractable=false, but a later read-only key-reference
  query reported extractable=true (item metadata omitted the field). Therefore
  nonextractability is NOT claimed; the platform's export policy was not changed
  and the private key was never exported. Earlier helper wording was corrected.
- CSR saved0600 in ignored `.build-native/developer-id-20261023.chUfNT/`.
  Independent `openssl req -verify -noout` returned verify OK. Contact email
  not copied into tracked source/docs or public release artifacts.
- Public CSR submitted through the normal Apple portal file chooser. Apple
  created Developer ID Application certificate A95GLWW9PX, downloaded and imported
  normally. Valid local signing identity SHA1:
  F1E94882CE21B463C2243767E8BEC333A51FEFCB, expires2027-11-22.
- Created and downloaded Developer ID profiles for exact existing app/module IDs:
  OpenCommander Mac Developer ID 20261023 and
  OpenCommander NTFS 2 Developer ID 20261023. Host uses Mac Catalyst, module Mac.
  CMS-decoded profiles passed strict model checks: exact team/application identity,
  ProvisionsAllDevices=true, no ProvisionedDevices field, no debug entitlement,
  and module FSKit entitlement=true. Actual profile expiry2044-10-18; portal
  availability/certificate dates are different. No device identifiers published.
- `test-macos-ntfs-distribution.py`:6 synthetic policy tests pass. The read-only
  full distribution gate refuses the installed Debug build as intended. This
  does not establish a positive signed/notarized public package test.
- Unsigned Release Catalyst arm64 build with hardened runtime and no Debug dylib
  succeeded: `parity-20261023-developer-id-release-build.log`. Product at
  `.build-native/developer-id-release/Build/Products/Release-maccatalyst/OpenCommander.app`.
  Exact NTFSModuleV2 identity, OPENCOMMANDER_NTFS3G_EXPERIMENTAL write marker,
  NTFS access helper, cloud argument helper and SSH helper all present. Nothing
  stripped. No app installation, FSKit registration or disk mount performed.

## Signing and notarization boundary / remaining work

After explicit approval, `authorize-developer-id-codesign.swift` added one
sign-only ACL for `/usr/bin/codesign` to the exact new key, matched to the new
certificate by public key. Existing ACLs and prompt policies were preserved;
no partition list, other key, password or keychain lock state was changed.
Independent readback confirmed the narrowly scoped ACL. A timestamped signing
probe then passed.

`sign-macos-ntfs-release.sh` signed a separate full Release app copy, including
the writable FSKit module, three helpers and Mac bridge, with Developer ID,
hardened runtime and secure timestamps. Both distribution profiles were embedded.
Strict deep signature verification and the Security-framework FSKit preflight
passed. Candidate: `.build-native/developer-id-signed-20261023/OpenCommander.app`.
The initial full distribution gate refused it at `xcrun stapler`, as expected
before notarization. A later relative-path issue in stapler validation was fixed
by passing a canonical absolute app path (without accepting input symlinks).

User explicitly approved Apple's internal-use API agreement at action time.
The access request was submitted and approved. The separately authorized
`OpenCommander Notarization` team key was created with Developer role only.
The initial one-time download could not be located. After separate explicit
approval, only that unused key was revoked and an equivalent Developer-role
replacement created. The replacement download was captured directly with the
documented download event, moved outside the repository to a private directory
(0700, key file0600), validated with Apple, and stored in a local Keychain profile.
No key contents were printed, committed, bundled or published. Publisher
credentials must remain private and must never be required by end users.

Apple accepted submission 45f4a718-6c78-4f5e-9e94-e1b3966bc1a2 on 2026-10-23,
with statusSummary "Ready for distribution". Submitted ZIP SHA256:
40ca0b60b1e28c687f6d8b2cbe21d35b4de088005eb610ed4ef1c07133eddcf8.
The ticket was stapled successfully. Direct absolute-path stapler validation and
Gatekeeper assessment passed (source=Notarized Developer ID).

Remaining: complete full packaging gate and publish verified GitHub assets.
Ship matching GPL engine source/vendor archive/notices with the full binary.
The GUI-only public preview is not silently described as NTFS-capable.

## Post-publication installation regression / r2

Installation of the exact GitHub download preserved the previous app in ignored
`.build-native/notarized-install.PVgR43/OpenCommander.previous` and retained user
settings. App startup and Gatekeeper passed. Mounted NTFS image testing found a
real runtime failure: taskgated reported `Unsatisfied entitlements:
application-identifier` for the native FSKit module, despite notarization success.
The native profile authorizes `com.apple.application-identifier`, not the
Catalyst-only unprefixed identity. The release was immediately marked with this
failure rather than continuing to claim runtime readiness.

The signer now emits the unprefixed identity only for the Catalyst host, never
the native module. The distribution gate checks restricted identity entitlement
authorization for both bundles, including regression tests that refuse the
original notarized package. Revision r2 is separately signed and submitted.
No personal volume was mounted or written, and the failed test image detached.

Apple accepted corrected submission 730f8b7a-4174-4ad7-bba8-a75036243b82.
The corrected app was stapled, passed the strengthened distribution gate and
installed at `/Applications/OpenCommander.app`. The normal app started with
existing settings/locations. With its existing extension approval unchanged,
`test-fskit.sh` completed successfully (exit0), log:
`.build-native/parity-20261023-installed-r2-ntfs-test.log`.
Mounted tests passed Unicode/case-preserving listing, case-only rename, exact
access/modify/create timestamps, copy metadata preservation, create/read/write,
copy/rename/replace/delete/truncate/fsync. After detach, Apple's independent
read-only NTFS implementation verified persisted bytes, Unicode, rename/delete
state and exact timestamps; the test image was detached again. Engine safety
regressions also passed. No physical user disk was touched and no reboot used.
