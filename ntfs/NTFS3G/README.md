# NTFS-3G / FSKit prototype — NOT production-ready

## Latest continuation (14 October 2026, evening)

### Physical Elements: build13 write/read PASS after admin approval

After explicit user approval and native administrator authentication, a bounded
one-shot diagnostic temporarily granted access to the identity-checked raw
Elements partition, then restored root:operator 0640 BEFORE writing. Normal-user
openntfs2 mount passed. A new unique test folder retained one 4408-byte Unicode
file, fsynced and read back exactly. After normal unmount, independent Apple
read-only NTFS verified identical data/SHA256
`0be852739ee7f57faf1abc416a0265f45129219cc4005cb49a0b2b9331a1ea08`.
Final state is /Volumes/Elements, read-only, original device permissions. No
existing file was changed or deleted. Evidence:
`.build-native/registration-repair13.jIVxHz/physical-elements-after-restart.log`.
This verifies physical driver I/O, not a production privileged helper or a new
OpenCommander UI-copy test. The temporary deprecated Authorization Services
utility is diagnostic-only and was not installed into the app.

### Post-restart: normal build 13 mounted tests PASS twice

After the user performed the approved restart (boot time verified), unchanged
installed build13/NTFSModuleV2 passed two complete isolated runs, fixtures
uLwHKI and m9cu0T. Case/Unicode, read/write/copy, rename/replace/delete,
truncate/fsync and mounted timestamps passed. Independent Apple read-only
reopen verified persisted content, names and timestamps. Both images detached
normally; no images remain attached. Logs are in
`.build-native/registration-repair13.jIVxHz/after-restart{,-repeat}.log`.
This supersedes the startup-blocked observations below, not the production
readiness warning. Elements remains read-only and was not written/remounted.

### Build 13: registration after updates and single-copy installation

The normal app now initializes its native bridge at launch and refreshes the
installed FSKit registration once per changed app version/module signature.
It validates both signatures, matching teams and the actual Boolean FSKit and
sandbox entitlements before invoking the two registration tools with exact
arguments. It stores the fingerprint only after both commands succeed. It does
not change extension approval or mount a device. Each child has a bounded wait.
Build-directory copies and the separate diagnostic host are excluded.

After building with `build-experimental-app.sh --fresh-registration`, quit the
app normally and use `sh ntfs/NTFS3G/install-experimental-app.sh`. The installer
retains the old app in a `.saved` backup and MOVES the verified build to
`/Applications/OpenCommander.app`; leaving a second `.app` in DerivedData was
observed to create a second extension registration despite Xcode's
`REGISTER_APP_WITH_LAUNCH_SERVICES=NO`. Installation refuses an active normal app
or mounted OpenCommander NTFS volume. Launch the installed app afterward.

Build 13 is signed, installed and launches with original settings. Its automatic
registration ran successfully from the host; PlugInKit shows one V2 registration
at the installed path. Registration retry/idempotence/path tests pass, including
read-only validation of the actual installed signatures. This is NOT yet proof
of a successful FSKit mount. The fresh `VfmrBb` test timed out after45 seconds
before module execution. After saving V2 OFF and ON in Settings, fresh `7LMaXn`
also timed out. Both detached normally. A normal app relaunch leaves its one
registration UUID unchanged. The existing FSKit startup remains blocked; no
current normal-host mounted-write PASS is claimed. No OS/session/service reset
was performed. Evidence: `.build-native/registration-repair13.jIVxHz/`.

### Normal-host build 12, metadata/pagination improvements; launch still blocked

Latest detailed evidence and Linux update:
[`docs/mac-linux-parity-2026-10-14.md`](../../docs/mac-linux-parity-2026-10-14.md).
The signed normal-host experimental build 12 is now installed and visibly
starts at `/Applications/OpenCommander.app`, with original settings preserved.
Opt-in `build-experimental-app.sh --fresh-registration` selects fixed V2 module
ID `.NTFSModuleV2`, alias `openntfs2`, display `OpenCommander NTFS 2`; normal
release/default metadata remains fail-closed and no automatic media matching is
enabled. The user explicitly approved V2 through Settings. The separate
diagnostic's earlier PASS results below are historical, not V2 acceptance.

The first normal V2 launch failed with ExtensionKit error 2/underlying 5:
FSKit referenced the unregistered build-product URL rather than the installed
Applications URL. Supported Launch Services/PlugInKit refresh, explicit off/save
and on/save in freshly reopened Settings, and final build 12 installation with
the source plug-in removed from registration did NOT restore startup. Final new
fixture `fskit-fixture.nKCEht/test.ntfs` timed out at 45 seconds, before mounted
write tests, and detached normally. Do not create more identities or keep
repeating the same probe as a supposed repair. The exact launch/cache cause is
not resolved; no reboot/logout/protected-service reset/security bypass occurred.
The normal host app is usable; its NTFS V2 mounted-write gate remains blocked.

New code/tests: access/modify/change/birth updates preserve 100ns precision and
validate all selected dates before combined resizing; metadata errors propagate.
Enumeration now streams to the FSKit packer with native cookies, not an array of
all directory names. `directory-cookies.patch` fixes the pinned engine's bitmap
bit offset for resumed enumeration; five page sizes over 200 unique entries,
EOF, bad-cookie zero-I/O refusal, injected read failures and reopen pass.
Native arm64 and x86_64/Rosetta regressions passed. Updated FSKit integration
compiles/signs, but its new timestamps/pagination are NOT live-mounted verified.

`test-engine-readback.sh` independently passes exact data/names and positive-epoch
100ns modify/birth dates through Apple's read-only NTFS driver on a new synthetic
image, with normal detach. The native engine also persists pre-1970 fractions
correctly; Apple's macOS 15.6 reader underflows the negative-epoch birth fixture.
That independent negative-date check is explicitly NOT passed. No production
crash/power-loss, ACL/link/xattr, automatic-mount or physical-authorization gate
is implied by the native/Apple image tests.

Current evidence: `.build-native/continuation-20261014.boHcRd/`.
Normal app backups: `.build-native/App-before-v2.BGkCs7/OpenCommander.saved`
(original V1/build11) and `.build-native/App-before-v2-build12.3RrMLJ/OpenCommander.saved`
(first V2/build11). Old held synthetic images A8Io8Z/disk7 and WYFIqz/disk8 remain
unmounted and attached; resolve paths before later cleanup, never delete backing
files. Seven other unmounted generated safety sets were gzip-compressed and
decompression-SHA-256 verified before removing uncompressed copies; all `.gz`
recovery copies, source, logs and Elements metadata backup remain.

### Fresh separate registration: mounted write/read tests PASS

After the user's Xcode sign-in, the signed diagnostic build succeeded with
legitimate development provisioning profiles for both separate identities.
The verified app is installed at `/Applications/OpenCommander NTFS Starttest.app`;
the normal `/Applications/OpenCommander.app` was not replaced. The user explicitly
approved activating **OpenCommander NTFS Starttest**. Its switch was enabled,
saved, and reopened to verify it remained ON; the original module remained ON.
The diagnostic host's default-folder-app prompt was declined.

`sh ntfs/NTFS3G/test-fskit.sh --diagnostic` completed with exit 0 on a NEW 64 MiB
fixture `.build-native/fskit-fixture.0ygTjm/test.ntfs`. Native engine tests passed,
then the diagnostic extension actually launched and passed mounted Unicode,
exact case-preserving enumeration, case-insensitive access, case-only rename,
create/read/write, copy, replacement, delete, truncate and fsync tests.
After normal detach, Apple's separate read-only NTFS implementation verified
the persisted names, Unicode payload, 517-byte file and rename/delete state.
Both mounts detached normally. This restores a working **diagnostic** startup
path without reboot, logout, service reset or security bypass. It does NOT prove
the original module identity is repaired or automatic mounting is reliable.
The exact cause of the original registration/launch failure remains unresolved.

A second full run also exited 0 on NEW fixture `fskit-fixture.dViHHa/test.ntfs`,
including mounted operations, independent Apple reopen and both normal detaches.
The test-harness guard/timeout/signature-identity regressions also passed.

`Elements` was only inspected read-only and remains Apple's `ntfs` read-only
mount at `/Volumes/Elements`, partition UUID
`005C1A70-98E8-48E6-8809-334901DC6E32`, raw permissions `0:5:640`.
No physical-drive writes, remounts or permission changes occurred in this test.
The older held `fskit-fixture.A8Io8Z/test.ntfs` remains attached and must not be
deleted or blindly detached. Only obsolete generated safety fixtures from
`safety-images.0cCgPj` were removed for space (reproducible, not recoverable
through Trash); source, evidence logs and Elements' metadata backup were kept.

Evidence: `.build-native/fresh-registration-evidence.1bjjSO/` contains the
signed build, both mounted test runs, harness and system launch logs. Production safety and
automatic-mount gates below still apply; do not ship the diagnostic identity
as a production replacement or claim always-writable NTFS support.

### Earlier preparation: separate registration and signing account

The user approved a fresh, separate launch diagnostic (still NO restart/logout).
`build-launch-diagnostic.sh` prepares a separate host/module pair:
`com.github.niklaus85.OpenCommander.NTFSStartTest` and its `.NTFSModule`, with
mount short name `openntfsdiag` and display name `OpenCommander NTFS Starttest`.
Normal defaults/IDs/short name remain unchanged. The diagnostic host's generated
Info.plist advertises no folder or URL handlers, and the extension claims no
media automatically. It must be installed separately at
`/Applications/OpenCommander NTFS Starttest.app`, never over the normal app.

The signed build FAILED before installation: Xcode reports **No Accounts** and
no development provisioning profiles for either new identity. Xcode's Apple
Accounts UI was opened and independently confirmed empty; it is left there for
the user to sign in using **Add Apple Account…**. No password/2FA code is requested
in chat. No new account, provisioning profile or working registration was created.
Do not reuse a mismatched existing profile, forge entitlements, or ad-hoc sign
this restricted extension to bypass that gate.

`build-launch-diagnostic.sh --compile-only` PASSED with signing disabled solely
as compile evidence. Both separate IDs, the `openntfsdiag` alias, the diagnostic
marker and empty media matching were checked in the built metadata. The unsigned
product stays in `.build-native/launch-diagnostic-app`; it has NOT been installed,
registered, launched or approved. That successful compile is NOT a driver test.
Normal signature mode rejects the diagnostic identity and diagnostic mode rejects
the production identity. The missing diagnostic preflight fails before an image
is created. Test-harness regressions pass. After the user finishes Xcode sign-in,
rerun the signed builder (no `--compile-only`), verify the app/extension signatures,
install separately, approve only the named diagnostic in Settings, and run
`sh ntfs/NTFS3G/test-fskit.sh --diagnostic`. Only new synthetic images are allowed.

Logs: `/tmp/opencommander-ntfs-launch-diagnostic-build.log` (No Accounts),
`/tmp/opencommander-ntfs-launch-diagnostic-compile.log` (compile PASS), and
`/tmp/opencommander-ntfs-diagnostic-harness.log`. Existing installed build 11 and
Elements' read-only mount/device permissions are unchanged by this preparation.

### Latest installed diagnostic: direct-entry build 11

To test whether the Debug trampoline was involved, the non-UI FSKit target now
opts out of Xcode's Debug dylib layout (`ENABLE_DEBUG_DYLIB=NO`, target-only).
Apple documents this supported opt-out in
[Understanding build product layout changes](https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes).
The module is a single ~1.3 MiB signed executable rather than a small stub plus
debug/preview dylibs. Sandbox, FSKit entitlement, module/app IDs, safety gates
and empty automatic matching metadata are unchanged. Build 11 was built in
fresh `.build-native/direct-entry-app`, verified, installed and its host app
launched; Settings still shows the extension ON. Prior build 10 is recoverable
at `.build-native/App-before-direct.vbyZqa/OpenCommander.saved`.

This did NOT restore FSKit mounting. A NEW 64 MiB image
`.build-native/fskit-fixture.2tzHJx/test.ntfs` passed native engine tests, but its
FSKit probe timed out after 45 seconds without a module process appearing.
That new image detached normally (disk8); no mounted file write test ran.
The older A8Io8Z/disk7 image remains held as described below. System logs show
the request entering FSKit's per-user extension lookup, but not reaching our
engine. Missing entitlements and the Debug trampoline are not demonstrated
causes. The exact cause inside the registration/launch chain is unresolved;
do not describe this diagnostic packaging change as a fix or promise that
an OS restart/update would resolve it. Logs:
`/tmp/opencommander-ntfs-direct-entry-build.log`,
`/tmp/opencommander-ntfs-direct-entry-fskit.log`,
`/tmp/opencommander-ntfs-direct-entry-system.log`.

### No-restart continuation

The user expressly forbids a computer restart; no reboot, logout, protected
service restart, process kill of a system service, security reset or permission
workaround is authorized/performed. The existing extension remains enabled.
Obsolete app registrations were refreshed through Launch Services (files were
not removed); PlugInKit may rediscover older copies still on disk. Refreshing
the installed registration and one normal Settings off/on cycle did not restore
launching. The new isolated mount waited without starting a module process;
its own `/sbin/mount` child was terminated, never a system service. A subsequent
30-second bounded mount retry also timed out. No mounted file writes ran.

The public Security framework independently validates the installed signature,
exact module ID, Boolean app-sandbox=true and FSKit entitlement=true. This
contradicts the earlier ExtensionKit sandbox diagnostic; it does not establish
the root cause or a working driver. `tests/signature_preflight.swift` now checks
this before FSKit tests and after experimental builds. `tests/run_bounded.swift`
bounds the test's own mount child to 45 seconds with exit 124 on timeout, without
restarting services. `test-harness.sh` covers argument guards, success/failure,
timeout, launch failure and wrong-identity refusal; CI includes these controls.

Cleanup limitation: the private NEW 64 MiB image
`.build-native/fskit-fixture.A8Io8Z/test.ntfs` remains attached as `/dev/disk7`,
unmounted, because macOS refuses detach as busy. Even a force-detach request
limited to this identity-checked virtual image was refused; no force operation
was attempted on physical media. Do not remove its backing file or detach an
identifier blindly later: re-resolve the exact image via `hdiutil info` first.
Mountpoint: `/private/tmp/fskit-fixture.U55YUs/mount` (not actually mounted).
`Elements` remains Apple-read-only at `/Volumes/Elements`, raw node 0:5:640.
Logs: `/tmp/opencommander-ntfs-registration-refresh.log`,
`/tmp/opencommander-ntfs-retoggle-mount.log`,
`/tmp/opencommander-ntfs-refresh-system.log`. No code rebuild/app replacement
was done in this no-restart continuation. Automatic and current FSKit mounted
write support remain unverified/blocked; do not promote the prototype.

Directory enumeration is now case-preserving, while lookups and collision
checks remain case-insensitive. `case-preserving-readdir.patch` changes only
the generated pinned engine's enumeration callback, not its volume flags or
stored names. Both universal slices and native builds apply the same patch.
The FSKit capability explicitly reports `insensitiveCasePreserving`.
New native regressions cover exact mixed-case/Unicode spelling, enumeration
callbacks, early stop, failed enumeration and preservation after read-only
reopen. Allocation-backed directory indexes also use mixed-case entries.

The signed app was installed and a fresh 64 MiB image passed mounted create,
read/write, case-only rename, exact directory spelling, case-insensitive read,
copy, replacement, delete, truncate and fsync. Independent Apple read-only
reopen confirmed the original names and payloads. Logs:
`/tmp/opencommander-case-fskit.log`, `/tmp/opencommander-case-engine.log`.
All 31 Swift tests and the recovery/refusal/checkpoint-rollback suites passed.
These are image tests; the previous successful physical `Elements` test is
documented below. No new physical-device write or permission change occurred.

### Automatic mounting: experimental implementation, NOT a passed feature

`build-experimental-app.sh --automount` generates separate development-only
matching metadata for GPT Basic Data, MBR Windows_NTFS and partitionless media,
and builds into separate DerivedData. Before claiming a matching NTFS resource,
the module runs the same explicitly read-only engine safety inspection used
by the writer. Unsafe/unclean/hibernated volumes are declined for the system's
read-only fallback. A read-only probe resource is allowed; actual write access
is decided when the separate loaded resource is opened. No `recover` flag,
automatic repair, privileged helper or device-permission change is added.
The normal/release Info.plist remains unchanged with empty `FSMediaTypes`.

`test-automount.sh` creates a new image and uses ordinary `hdiutil attach`,
without `mount -F`. A read-only `statfs` guard requires the exact image device,
mount root, `openntfs` type and writable flag before any mounted write test.
On this Mac (15.6 / 24G84), this gate FAILED: the system selected Apple's
`ntfs` driver read-only, despite the opt-in installed matching metadata.
Fixture: `.build-native/automount-fixture.VCgGNV/test.ntfs`; normally detached.
Log: `/tmp/opencommander-auto-test.log`. A subsequent explicit control mount
also hit the known per-user FSKit registration/task-launch mismatch after the
test app update; this is not a passed automatic or physical mount test.
Settings listed OpenCommander in the overview but omitted it from the detailed
module list; no consent/security setting was changed. The automount test build
must not remain installed or be promoted to release on this evidence.

Apple acknowledges Disk Arbitration/physical-access issues in
[this FSKit discussion](https://developer.apple.com/forums/thread/788609),
and describes per-user registration and newer lifecycle improvements in
[AppEx lifecycle improvements](https://developer.apple.com/forums/thread/831396).
Neither an OS upgrade nor reliable automatic physical mounting has been tested
here. Do not claim that upgrading alone guarantees a fix. The remaining gate
is a supported, reproducible automatic mount and physical authorization flow
on a fresh user session/system, without weakening security protections.

Final default-prototype build 10 was signature-verified, installed and launched
at `/Applications/OpenCommander.app`; the automatic-claiming marker is absent
and `FSMediaTypes` is empty. The previous automatic test app is retained as
`.build-native/App-auto-test.xwElf4/OpenCommander.saved` (not registered).
The final explicit fixture mount was refused by macOS with
`Module com.github.niklaus85.OpenCommander.NTFSModule is disabled!`.
At that point the detailed Settings pane listed OpenCommander NTFS as **off**.
After the user's explicit approval, the switch was enabled through Settings,
saved with Done, and reopened to verify it remained **on**. A new isolated
fixture (`fskit-fixture.wN1lAk/test.ntfs`) passed its native tests but the FSKit
probe failed before mounted writes: ExtensionKit error 2, underlying error 16,
`Extension must have com.apple.security.app-sandbox entitlement`.
The installed extension's actual signed entitlements already contain this key
as true; strict deep signature verification passes. The active registration
points to the correct installed build 10. This contradiction is consistent
with stale registration/launch state, not proof that source entitlements are
missing. No entitlement/security requirement was removed or bypassed.
The failed image detached normally, and Elements remains read-only.
Logs: `/tmp/opencommander-ntfs-reenabled-fskit.log` and
`/tmp/opencommander-ntfs-reenabled-system.log` (also copied into
`.build-native/case-automount-evidence.7y9IX1/`). A supported fresh login/session
or normal restart is the next diagnostic step, not a guaranteed fix, and has
not been performed.
Log: `/tmp/opencommander-case-final-fskit.log`; the failed fixture was detached.
Earlier case-preserving mounted/Apple-readback PASS evidence remains valid for
the preceding build, but the final installed extension's activation is NOT
verified. The final native suite (including case-preserving index growth and
hibernation refusal) passed. `Elements` remains Apple-read-only and its original
raw-node permissions remain `root:operator 0640`.

The previous independent MIT engine remains separate. This GPL-2.0-or-later
integration builds NTFS-3G 2026.7.7 without FUSE and uses callback I/O so the
same engine facade can operate on a regular test image or an FSKit resource.
See [THIRD-PARTY.md](THIRD-PARTY.md) for provenance and source delivery.

## Build / tests

Requires Xcode tools, make and pkg-config (`brew install pkgconf` on this Mac).

```sh
sh ntfs/NTFS3G/build-engine.sh
sh ntfs/NTFS3G/test-engine.sh
swift test --package-path ntfs/OpenCommanderNTFS
```

The build does not install drivers, FUSE or command-line tools system-wide.
Generated files stay in `.build-native`. The image tests exclusively CREATE
a new regular file, format that file, and keep it for independent inspection.
They do not accept an existing disk as a write target. Image runners default to
the host architecture. The universal app/extension now builds for Apple Silicon
and Intel; the safety-image suite also passes under Rosetta on Intel code.
This does not constitute physical-drive or production-release approval.

To build the opt-in macOS prototype after building the engine:

```sh
sh ntfs/NTFS3G/build-experimental-app.sh
```

The scheme also builds its containing Catalyst app. No automatic claim of
NTFS devices is configured (`FSMediaTypes` is empty). The ordinary build still
refuses mounts. Do not turn the experimental build into the default release.

The script keeps a separate DerivedData directory and uses one explicit setting
for the Swift compilation condition and an installed Info.plist capability
marker. It verifies that marker and the signature, but does not install, grant
permissions or mount disks. Install its printed app explicitly at
`/Applications/OpenCommander.app` before running the FSKit tests. The preflight
now checks this exact installed app and rejects ordinary/legacy unmarked builds
before allocating a test image. Other installation locations are not supported
by this test workflow. After an ordinary app update, repeat this check: enabling
the extension in Settings cannot restore code omitted from that build.

On 12 September the ordinary installed build reproduced `Operation not
supported` from loadResource (exit 69), not the earlier task-launch failure.
The extension was registered but had been rebuilt without the experimental
condition. A new 64 MiB fixture was used and detached; no physical disk changed.

The corrected experimental app was then built, signature-verified and installed
locally, retaining a backup of the previous app. The full FSKit test passed on
12 September: mount, Unicode, create/read/write, copy, rename, replace, delete,
truncate and fsync, followed by clean detach and independent Apple NTFS read-only
verification. Fixture: `.build-native/fskit-fixture.bH63ek/test.ntfs`.
This resolves the reproduced build-mode regression, not the production safety
gates below. The public GitHub preview remains unchanged and lacks this extension.
Automatic remounting of physical NTFS media is still deliberately disabled.
A second fresh image (`.build-native/fskit-fixture.pHQfb2/test.ntfs`) passed the
same full sequence immediately afterwards. Both images were detached normally.
No sudo, permission reset, system-daemon restart or physical-disk write was used.

## Physical drive check (14 October 2026)

The attached 5 TB `Elements` volume was initially mounted read-only by Apple's
NTFS implementation. The first isolated mount attempt selected the disabled
`com.github.niklaus85.OpenCommander.MacUITests.NTFSModule` from a disposable
UI-test clone instead of the installed production module. Unregistering only
that clone from Launch Services resolved this collision. `run-mac-ui-tests.sh`
now moves its FSKit extension outside the disposable app before signing or
launching it: UI tests must not advertise the production `openntfs` short name.
No extension consent, security setting or production installation was changed.

After that correction, a fresh 64 MiB fixture (`fskit-fixture.03c4HZ/test.ntfs`)
passed all mounted VFS tests and independent Apple read-only reopen checks.
The installed OpenCommander UI also copied a synthetic 169-byte UTF-8 file to
this image using F5; exact byte comparison passed (SHA-256
`8c24bc0576f3afbbe565ac0783effba4fe030fd7475b0630dc0c2ccb9c48170a`).
The image was detached normally after leaving its directory in the app.

A normal, non-forced unmount of `Elements` succeeded, but the attempted FSKit
mount stopped during resource probing with `Permission denied` (exit 69).
The system log specifically reported `FSBlockDeviceResource` open failure,
`NSPOSIXErrorDomain Code=13`, before the module received the real resource.
This is physical-device access authorization, not a failed engine write test
and not evidence that extension consent is missing. No force, raw write,
permission change or root-context retry was attempted. `diskutil mount readOnly`
restored the original volume at `/Volumes/Elements`, verified read-only.
No test file was written to the physical drive. Authorized physical-device
mounting and the subsequent physical write/readback test remain unverified.

After the user explicitly authorized a temporary per-partition device-access
test, a disposable native authorization utility changed only the owner of
`/dev/rdisk6s1` long enough to request the mount in the login user's context.
It then restored `root:operator`, mode `0640`, before any file-write test.
The identity guard uses the partition UUID and stable `IOKitSize`: `TotalSize`
changes between mounted filesystem capacity and unmounted partition capacity
and must not be used as a stable device identity check.

The device-access error was resolved, but the installed module then refused
activation with `EROFS`: `Write refused: dirty, hibernated, unsupported, or
unreadable NTFS volume`. This is a successful fail-closed safety gate, not a
successful physical write test. No force/recovery option, flag clearing,
formatting or filesystem repair was attempted. `Elements` was restored at
`/Volumes/Elements` using Apple's read-only NTFS mount; the original raw-device
owner/group/mode were independently verified. No test directory or file was
created on the physical disk. The one-shot diagnostic utility is retained only
in `/private/tmp/OpenCommander-NTFS-Authorized-glVW9S`; its deprecated
Authorization Services execution mechanism is NOT installed or adopted as a
production app helper.

The subsequent explicitly read-only `ntfsinfo -m` diagnostic (no force or
recovery option) identified the specific gate: `Volume is scheduled for check`.
In this tool's `utils_mount_volume` implementation this refusal is reached
when `VOLUME_IS_DIRTY` is set. It is therefore a confirmed dirty/check-required
volume, not merely a hypothesis from the module's combined error message.
The diagnostic exited without opening the volume for writing; the original
`root:operator 0640` device permissions and Apple read-only mount were restored
and verified again. Log: `/private/tmp/OpenCommander-NTFS-Authorized-glVW9S/inspection.log`.
No filesystem repair, dirty-bit clearing or physical write test was performed.

After the user reported completing a Windows check, the same partition was
identified again by UUID and capacity. A new read-only `ntfsinfo -m` run no
longer refused the dirty bit: it reported NTFS 3.1 and volume flags `0x0080`
(bit `0x0001` clear). It also reported a valid but unclean `$LogFile` restart
state, and `EINVAL` reading the bitmap. The latter must not be presented as
proof of disk damage: native raw-device reads require sector alignment.
An additional read-only probe therefore uses the app's NTFS engine with
sector-aligned callback reads, an `O_RDONLY` descriptor and no write callback.
Its clean-image control passed bitmap-tail, hibernation and clean-journal
checks. After the separate macOS authorization, the physical aligned probe
completed: NTFS 3.1, flags `0x0080`, dirty bit clear, hibernation check successful,
unaligned bitmap-tail read successful, journal structurally valid but not clean
(`JOURNAL valid=yes clean=no`). The earlier bitmap `EINVAL` was therefore a
raw-access alignment issue, not a reproduced bitmap read failure through the
app's I/O adapter. The read-only engine closed successfully and original device
permissions and Apple's read-only mount were again restored and verified.
No physical writable mount or test-file creation was retried: the journal safety
gate remains unresolved even after the Windows dirty-bit check was cleared.

## Recovery development — implementation status (14 October 2026)

Unclean removal must eventually be handled by validated transaction replay,
not by silently accepting an inconsistent volume. NTFS-3G's ordinary `recover`
mount flag clears the Windows log and can introduce inconsistencies; it is NOT
equivalent to committed-transaction replay. See the upstream
[manual](https://github.com/tuxera/ntfs-3g/wiki/Manual) and the vendored
`ntfsrecover.8.in`. This integration still does not enable that flag.

Implemented and tested in source:

- `nk_inspect_io` performs an explicitly read-only preflight, removing both
  write and flush callbacks regardless of the caller's requested access.
  Structured reports distinguish dirty flags, replay-required journals,
  invalid journals, cached Windows metadata, hibernation, unsupported NTFS
  versions and metadata I/O errors. This is inspection, not repair approval.
- Every engine write mount now checks the journal **before** opening for
  writing; its existing Windows/hibernation and dirty-volume protections remain.
  FSKit uses this same engine entry point, so its error no longer conflates all
  these conditions into one generic message.
- `test-safety.sh` constructs ten groups of synthetic-image tests, including
  valid clean/unclean restart pages, invalid journals and Windows-cache 2.0
  headers. Refusals preserve the complete image byte-for-byte, with zero device
  writes or flushes; original contents remain readable through read-only mounts.
- `build-recovery-inspector.sh` compiles the pinned upstream `ntfsrecover` and
  `playlog` sources behind a laboratory-only entry point. It always passes
  `--no-action --sync`, pins an owned regular image through an `O_RDONLY`
  descriptor, and rejects device nodes, symlinks, extra options and images over
  1 GiB. It is not installed or bundled into the app. Other blockers prevent
  even this dry-run parser from starting.
- `test-recovery.sh` verifies additional dry-run groups, including unchanged
  SHA-256 hashes after the dry runs and rejection of incomplete synthetic
  transactions. A successful simulation is explicitly **not** authorization
  to apply changes. Positive replay of real committed transactions, durable
  staging/rollback and crash/interruption recovery are NOT yet verified.
- Native engine regression tests, all 31 Swift package tests and the additional
  Intel safety-image run under Rosetta pass; the
  experimental universal Catalyst app/extension build passes without signing
  or installation. This is source/build evidence, not a new installed driver
  or a passed physical-drive write test. CI now includes the native tests.

Run these on a Mac, without sudo or any physical-volume argument:

```sh
sh ntfs/NTFS3G/test-engine.sh
sh ntfs/NTFS3G/test-recovery.sh
swift test --package-path ntfs/OpenCommanderNTFS
```

Automatic journal replay and reliable writes after arbitrary unplugging remain
unfinished. Hibernated/cached, unsupported or corrupt volumes must remain
read-only when safe replay cannot be proven. No filesystem implementation can
guarantee recovery of user data that had not reached the device before unplugging.

### Recovery sandbox follow-up

`build-recovery-overlay.sh` builds a second laboratory tool. It redirects the
upstream `ntfsrecover --sync` device into a bounded shared-memory overlay. The
original descriptor is always `O_RDONLY`; repair writes and flushes can only
touch disposable RAM. There is no apply/commit command. The tool rejects
caller-supplied recovery/apply flags and device paths; a physical read-only
descriptor can only be supplied by an already-authorized caller. Replay runs
in a disposable child with a 120-second limit and a 16 MiB changed-page budget.
Any I/O, replay, budget, source-change or post-inspection error discards the
candidate. This is **not** installed in the app or an automatic repair mode.

The stdio bootstrap adapter now provides the actual 1024-byte source boot
sector through a read-only memory stream. Returning a failed `fopen` would
leave upstream's stack boot buffer uninitialized and invalidate its geometry
calculations; the regression control explicitly verifies these bootstrap bytes.

A complete synthetic checkpoint fixture now passes real virtual journal
checkpoint completion: two restart pages change only in the memory overlay,
and a separate RAM-only validation copy successfully creates, writes, reads
and deletes a proof file. The original image's SHA-256 remains unchanged.
This fixture has no pending committed user-data updates and is not evidence
of support for arbitrary interrupted transactions. Incomplete journals, cached
Windows state and hibernation still refuse repair. The overlay tests also
exercise cross-page changes, fork visibility, memory exhaustion and writable
descriptor refusal. `test-recovery.sh` includes these controls.

The physical `Elements` read-only sandbox was initially tested with the corrected boot
adapter. Its kernel device ownership was restored **before** the worker started,
which inherited only an already-open read-only descriptor. Upstream replay
refused `Could not wraparound` and reported zero played actions. Zero pages and
zero writes were staged; nothing was applied. The temporary fixture log is
`/private/tmp/OpenCommander-NTFS-Authorized-glVW9S/stage-readonly.log`.
Original `root:operator 0640` device permissions and Apple's read-only mount at
`/Volumes/Elements` were verified afterward. This does not prove the disk is
corrupt, but that parser could not validate its journal sequence. Automatic
physical repair/write enablement therefore remains unfinished; do not bypass
this refusal by clearing the journal or its flags.

### Initial continuation parser correction

The detailed read-only `Elements` trace identified an upstream traversal bug:
the latest tail copy (physical page 3, logical page 10934) was preceded by a
record starting on page 10932 and continuing through page 10933. The initial
`walkback` call always supplied zero skipped pages. It therefore calculated the
next record at offset `0x19c0`, outside the 4096-byte page, instead of `0x0a00`.
The misleading `Could not wraparound` refusal did not establish disk damage.

`recovery-parser.patch` counts initial continuation pages using the tail copy's
logical `file_offset`, handles circular distances, rejects impossible geometry,
and prevents the wraparound check from dereferencing a record beyond its page.
It is applied only to generated build copies of the pinned GPL source, with
zero fuzz. No journal record is skipped by searching for plausible bytes, and
no safety gate or physical-write protection is removed.

The actual patched parser passes targeted AddressSanitizer/UndefinedBehaviorSanitizer
controls for multi-page continuation, adjacent and wrapped pages, version 2
geometry, and invalid tail offsets. A complete new synthetic image with a
record spanning three pages now passes both dry-run and virtual recovery,
including RAM-only file create/write/read/delete. Its SHA-256 stays unchanged;
an invalid tail-offset counterpart is refused. Full `test-recovery.sh` and
native engine tests pass. This is still checkpoint completion without pending
user-data changes, not general transaction-recovery certification.

The corrected physical `Elements` sandbox retest passed on 14 October 2026:
upstream reported two played actions, two staged restart pages, and the virtual
filesystem passed the clean-journal preflight. A separate RAM-only copy then
passed create/write/read/delete. The only inherited source descriptor remained
`O_RDONLY`; `source_write_callbacks=0 applied=NO`. The original raw-device
permissions were restored before replay, and Apple's read-only mount at
`/Volumes/Elements` was restored and verified afterward. Log:
`/tmp/opencommander-elements-continuation-fixed.log`.

This resolves the reproduced parser refusal on this journal. It does **not**
prove crash-safe replay of arbitrary transactions, repair the physical source,
or enable automatic repair in the app. At that stage, the new source had not
been installed or committed. See the physical follow-up below for the later
explicit apply and signed app update; no automatic repair or writable remount
has been added to the installed app.

### Explicit checkpoint-only repair experiment

After being told there was no full backup, the owner stated that the data was
not important. A separately built experimental tool, `recovery-checkpoint`,
now provides a narrow, explicit two-page apply workflow. This is **not** a
general recovery writer and does not change the default sandbox binary's
read-only contract. It is not bundled into the app or automatically invoked.

- Replay still runs in RAM against an `O_RDONLY` source; the disposable replay
  child never inherits the separate writable descriptor.
- Only the exact two 4096-byte `$LogFile` restart pages, mapped from the source
  attribute, may change. A candidate with any other changed metadata is refused.
  Both replacement pages must be identical valid clean NTFS 1.1 restart pages.
- Source/output identity, geometry, absence of a mounted physical source and
  original page contents are checked before apply. The one-shot local native
  authorization wrapper additionally pins the USB partition UUID and size.
- A new, exclusive local backup contains exact original and replacement pages;
  it and its directory entry are flushed before device writes. This is a
  metadata-page backup, **not a backup of the volume's files**.
- Each page is flushed and the result read back and reinspected. Ordinary
  write/flush failures attempt restoration and flushing of both original pages.
  Power loss, hardware failure and failed rollback still cannot be guaranteed
  safe; a critical rollback failure requires keeping the device unmounted.
- New-image regression controls pass successful apply, write and flush failure
  rollback with full-image SHA-256 comparison, and refusal of extra metadata,
  missing/existing backup files and mismatched output identity. Fault injection
  exists only in the separately compiled sanitizer-enabled test binary.

`test-recovery.sh` now runs those new-image controls too. It never passes a
physical device to the checkpoint tool. Physical results must be recorded
separately; test-image success alone does not authorize an unattended repair.

### Physical checkpoint apply and installed update (14 October 2026)

After native macOS administrator authorization was completed, the guarded
checkpoint experiment succeeded on `Elements` (`005C1A70-98E8-48E6-8809-334901DC6E32`):
two actions replayed in RAM, exactly two restart pages were backed up, applied,
flushed and read back, and the physical read-only safety preflight passed.
The 16,432-byte original/replacement backup is retained at
`.build-native/Elements-checkpoint.S2F6Go/original-and-replacement.bin`.
This is NOT a backup of the drive's files. Log:
`/tmp/opencommander-elements-checkpoint-now.log`.

The old installed experimental module then mounted the physical volume read/write
at `/private/tmp/OpenCommander-NTFS-Authorized-glVW9S/Elements`. Its subsequent
`statfs` calls repeatedly scanned the complete bitmap and stalled for minutes
on the 5 TB device; a process sample confirms `volumeStatistics -> nk_statvfs ->
ntfs_volume_get_free_space -> ntfs_attr_get_free_bits`. The file-test verifier
refused its mount guard before creating its test folder. A separate C query
reported the correct `openntfs` type, exact mount/device and read/write flags;
the verifier's earlier refusal remains unexplained and must not count as a
passed physical file write. A normal unmount succeeded; no forced physical
unmount, formatting or deletion of user files was performed.

The bridge now uses NTFS-3G's maintained `FreeSpaceKnown` counters after the
initial bitmap scan. A regression test verifies 100 repeated statfs queries
cause no further reads, and allocation/deletion counts match an independent
fresh bitmap recount. The module also supplies FSKit's required `maximumFileSize`.
The native image suite and signed Catalyst build pass with these changes.

The new experimental app was installed at `/Applications/OpenCommander.app`,
retaining the same bundle identifiers, developer identity and team. Its signature
and experimental write marker were verified. The previous app is recoverable
at `.build-native/App-before-statfs.6kljdB/OpenCommander.saved` (rename to `.app`
to restore). The backup and generated build app were unregistered from Launch
Services to avoid advertising duplicate `openntfs` handlers.

Runtime verification of this update is BLOCKED: the first fresh-image mount
reported ExtensionKit error 2/16, and a subsequent request hung with the user
FSKit agent reporting an existing instance with PID 0 and a null connection.
No new module process started. System Settings showed OpenCommander NTFS already
enabled; switching only that extension off/on left it enabled but did not clear
the stale instance. No preferences were edited manually. The stalled mount
request was stopped, but the new 64 MiB image
`fskit-fixture.0QRs2y/test.ntfs` remains attached unmounted as `/dev/disk7` because
ordinary detach reports resource busy. Do not force-eject user disks.

With `Elements` normally unmounted, the attempt to restart only the verified
`user/501/com.apple.fskit.fskit_agent` service was denied by SIP. No alternative
kill, security bypass, SIP change or root-daemon restart was attempted. `Elements`
was restored at `/Volumes/Elements` using Apple's read-only mount; original raw
device access `root:operator 0640` is verified. A user-approved Mac restart is
the next integration step, followed by a fresh image gate, physical file
create/write/readback, OpenCommander UI copy, normal unmount and independent
Apple readback. Those physical file tests had not passed at this earlier stage;
the reconnected-drive result below supersedes that integration status.

### Reconnected Elements: physical file tests PASS (14 October 2026)

The exact external USB partition UUID and 5 TB geometry were rechecked after
reconnection. The fresh 64 MiB image `fskit-fixture.lCkP0x/test.ntfs` passed all
FSKit operations and independent Apple NTFS read-only persistence checks, and
was detached normally. Log: `/tmp/opencommander-ntfs-reconnected-fskit.log`.

The physical test first used a strictly read-only diagnostic: NTFS 3.1, flags
`0x0080` (dirty bit clear), valid clean journal, no hibernation, and successful
aligned bitmap tail read/close. No checkpoint repair was repeated. The user
completed native macOS authorization for the previously approved device-access
test; original `root:operator 0640` permissions were restored before file writes.

The prior test guard failure is now explained: Foundation canonicalizes
`/private/tmp` to `/tmp`, but the verifier had canonicalized only its input, not
the expected work directory. Canonicalizing both paths fixes the comparison
while preserving all device, filesystem type, mount-root and access checks.

On the installed experimental `openntfs` mount, the verifier exclusively
created `OpenCommander-Test-20261014-glVW9S/Direkter-Schreibtest.txt`, synchronized
it and read back its exact 169-byte synthetic payload. OpenCommander then copied
the separate `OpenCommander-Schreibtest.txt` using F5; its transfer card reported
completed, 169/169 bytes, 100%. Direct byte comparison and SHA-256 matched.

After leaving the mounted directory in the app and normally unmounting it,
Apple's independent read-only `ntfs` implementation successfully read both files.
Both, and the original synthetic source, have SHA-256
`8c24bc0576f3afbbe565ac0783effba4fe030fd7475b0630dc0c2ccb9c48170a`.
Final state: `/Volumes/Elements`, Apple read-only NTFS, raw node `root:operator
0640`; no active physical test or authorization helper remains. The test folder
and metadata sidecars were retained. No existing user file was overwritten or
deleted. Log: `/tmp/opencommander-elements-reconnected-live.log`; durable copies
of both logs are retained next to the checkpoint-page backup.

This proves the tested physical file-write/readback and OpenCommander-copy
paths, not arbitrary crash recovery, unattended physical access or automatic
writable mounting after reconnect. The lab's temporary raw-device ownership
mechanism is still not a production helper. Enumeration through the module
currently shows lower-case names, while Apple readback confirms that stored
mixed-case names were preserved; that enumeration issue is still open.

Although the user reported a restart, host uptime still showed 29 days. The
successful current session must not be reported as proof of a kernel reboot.
No SIP change, protected-service restart or forced physical unmount was used.

## Observed results (8 September 2026)

- Native image tests pass: small and nonresident writes, resize/zero fill,
  Unicode, case collisions, directory rename, create/delete, directory index
  growth to 200 entries, replace, case-only rename, restore after injected
  replacement failure, real ENOSPC, device-write and flush error reporting,
  persistence after reopen, read-only protection, hibernation rejection.
- macOS's own read-only NTFS implementation independently mounted the result
  and read the expected 13-byte `HELLO.TXT`, 8192-byte `large.bin`, and 200
  directory entries. That test image was then detached.
- Signed macOS app and embedded FSKit module build successfully (Apple Silicon).
- FSKit mount and VFS write tests now PASS on macOS 15.6, without sudo:
  Unicode, create/read/write (including a 2 MiB file), copy, rename, atomic
  replacement via Foundation, delete, truncate and fsync.
- After clean detach, Apple's separate read-only NTFS driver read back the
  exact Unicode payload and 517-byte truncated file and confirmed deletions.
- Earlier failures: an initial missing `.ready` container transition was
  fixed. The remaining `Operation not permitted` was diagnosed in the kernel
  log as `System Policy: fskitd ... deny(1) file-mount` at the Documents path.
  Moving only the test mountpoint to a private `/private/tmp/fskit-fixture.*`
  directory resolved it. No TCC permissions or SIP settings were changed.
- The user subsequently authorized two `sudo mount` attempts. Both failed
  earlier with `mount: Unable to invoke task`; logs show module discovery but
  no launch of our extension. Administrator authorization was NOT the fix.
- Read-only diagnosis: pluginkit lists the signed extension, and the login
  user's FSKit enabledModules preferences contain its bundle identifier, but
  `FSClient.shared.fetchInstalledExtensions` from both interpreted and compiled
  command-line checks returns only Apple's exFAT/MS-DOS modules. Actual mount
  nevertheless starts and activates our extension. The old preflight's hard
  failure was a false negative; missing API entries now fall back to read-only
  pluginkit registration lookup and a warning, not an assertion of approval.
- OpenCommander UI tests and production safety gates are still NOT passed.

Full corrected `sh ntfs/NTFS3G/test-fskit.sh` run: exit 0, fixture
`.build-native/fskit-fixture.Tj5klb/test.ntfs`, test directory
`OpenCommander-Test-6BFC5EAA-B9EF-451F-A9B4-FED258166BDB`.
Both FSKit and Apple read-only mounts were detached normally. No physical
disk was written or remounted. The successful script output ends with:

```text
PASS FSKit mount: Unicode, create, read/write, copy, rename, replace, delete, truncate, fsync
"disk7" ejected.
PASS independent Apple NTFS read-only reopen: exact Unicode content, 517-byte data, rename/delete persistence
"disk7" ejected.
```

## Next integration test

First run the read-only preflight as the normal login user:

```sh
sh ntfs/NTFS3G/test-fskit.sh --check-only
```

If neither discovery method finds the module, launch the built experimental
containing app and check its File System Extension in System Settings → General
→ Login Items & Extensions. Do not interpret the FSClient omission warning as
a request to re-enable an already working extension. Do not edit preferences manually,
disable SIP, or restart system FSKit services while user disks are attached.

Only once preflight succeeds and at least 512 MiB is free, run:

```sh
sh ntfs/NTFS3G/test-fskit.sh
```

This prepares a fresh image, verifies that its device is a virtual 64 MiB disk
image, and mounts in the login user's context, without sudo. FSKit extension
registration/consent is per-user; root does not inherit that state. Apple
confirms this in [AppEx lifecycle improvements](https://developer.apple.com/forums/thread/831396).
The mountpoint is a newly created private temporary directory, outside protected
Documents. `tests/mounted_tests.swift` exercises VFS file operations. It checks
the reported type `openntfs` (not `fskit`) and the canonical mount root before
writing. `tests/verify_reopened.swift` checks persistence after detach and
read-only remount with Apple's `ntfs` driver. OpenCommander UI tests remain a
separate gate; success of the script alone is not full release approval.

Preflight now exits 0 with an explicit warning when the module is registered
but omitted by FSClient. It does not call that a passed mount/write test.
Shell syntax and Swift runtime checks pass. Initially only about 195 MiB was
free; later 1.2 GiB was available. The test refuses new fixtures below 512 MiB. Existing fixtures are
retained, never silently deleted. The mkntfs warning about Windows being unable
to boot from a raw image is expected: these are data-volume fixtures, not
Windows boot disks.

## Remaining safety / functionality gates

- Crash/power-loss consistency and interrupted metadata writes are NOT proven.
  Recovery-name replacement protects the previous target in tested ordinary
  failure paths; it is not a crash-atomic NTFS transaction or journal replay.
- Dirty volumes and Windows hibernation are rejected for writing. No forced
  recovery, journal reset, formatting of user disks, or security-policy changes.
- Symlink/hardlink creation, NTFS ACL mapping and extended
  attributes are not complete in the FSKit prototype. Compressed/encrypted
  file writes and writes to NTFS system files are refused.
- Timestamp-setting now passes native and positive-epoch Apple readback gates,
  but current normal-host FSKit startup prevents live-mounted verification of
  the new setter/pagination. Apple's pre-1970 birth-date reader limitation is
  documented in the latest continuation.
- Mount/unmount lifecycle, concurrency, open-unlink, very large files and
  rollback failures still need comprehensive integration testing.
- `Elements` has now received the explicitly authorized checkpoint repair and
  isolated synthetic test files described above. It has not been reformatted;
  existing user files were not selected as write/delete targets.

### Cleanup of the failed system mount

The denied mount initially left two test extension processes holding the
64 MiB image. Both processes were verified as belonging to this test and
terminated; the image then detached normally. No system-wide FSKit daemon
was restarted, and no physical disk was detached. A `deinit` cleanup for the
engine handle was added to cover failed-mount teardown as well.

Three obsolete generated image files were removed to reclaim approximately
131 MiB; they are reproducible with the test script. The latest successful
native fixture is retained in `.build-native/test-images.9x6e9V/test.ntfs`.
