# Opt-in automatic external NTFS writing (build 14)

The setting is in **Connections → Configure automatic NTFS write access**, also
reachable through the NTFS extension onboarding. It uses Apple's SMAppService
daemon approval, not saved administrator credentials, sudoers edits, setuid
executables or the deprecated one-shot diagnostic authorizer.

## Scope and boundaries

- Disabled by default. Requires the separately approved FSKit extension and a
  signed experimental write-enabled build installed in Applications.
- While OpenCommander runs, it observes mounts and attempts normal unmount /
  writable remount of external **USB NTFS partitions** only. Internal disks,
  whole disks, disk images, non-NTFS and non-writable media are refused.
- The service authenticates the XPC client's signing identifier, Apple signing
  anchor and team. The app likewise verifies the helper. Only the active console
  user is eligible; arbitrary commands, paths and user IDs are not an IPC API.
- The independent root worker checks partition UUID, geometry, physical-device
  description, NTFS boot signature, original device owner/group/mode and device
  descriptor identity. It grants a **maximum 60-second ownership lease** for the
  selected raw partition and a fixed /Volumes/OpenCommander-UUID mountpoint.
- Restoration uses retained file descriptors, not a potentially reused pathname.
  EOF from daemon death, explicit lease completion or timeout restores ownership.
  The worker ignores TERM/HUP/INT/PIPE during its bounded lifetime. SIGKILL and
  catastrophic OS/hardware failure are not covered by a userspace guarantee.
- Mounting happens in the login user's FSKit context. No dirty/hibernation safety
  override, force unmount, checkpoint repair, format, journal reset or raw write.
  Failed mounting attempts restore Apple's read-only mount where possible and
  do not retry in a loop. The device is retried after reconnection/app relaunch.
- Disabling stops future automatic attempts and unregisters the service. It does
  not forcibly unmount a drive containing active user work.
- The lease temporarily permits other processes running as that same user to
  access that raw partition. This is a macOS 15 FSKit compatibility compromise,
  not a general-purpose privilege API. Do not present it as zero additional risk.

## Verification and remaining acceptance

Live acceptance on 14 October 2026: user approved the SMAppService background
item in Settings. Initial test found and fixed relative executable lookup and
empty-string MountPoint handling. Added regression checks. Updated signed build14
re-registered with retained approval (no second password). Elements automatically
mounted writable twice, including after app relaunch. A new 4408-byte file was
fsynced/read, then independently verified through Apple's read-only NTFS after
normal unmount. SHA256 matched again after the second automatic writable mount:
`0be852739ee7f57faf1abc416a0265f45129219cc4005cb49a0b2b9331a1ea08`.
Raw permissions were restored to root:operator 0640; UI lists Elements at the
stable /Volumes/OpenCommander-005C1A70-98E8-48E6-8809-334901DC6E32 path.
Hardware unplug/replug and deliberate worker/daemon failure acceptance remain
open. These two successful mounts are not evidence for those scenarios.

The signed arm64 app and helper build; static signature/plist validation passes.
Policy tests reject malformed/missing/mismatched identities, internal/whole/image
media, non-NTFS partition descriptions and read-only media. Command exit/timeout
tests and remote transport regression pass. These are not proof of the complete
privileged lifecycle. Live setup, writable automount, cancellation, daemon/client
interruption, reconnect and independent readback must be recorded separately.
The physical one-shot write test from build13 does not certify this new service.

Apple references:
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/fskit/fsresource
- https://developer.apple.com/forums/thread/788609
