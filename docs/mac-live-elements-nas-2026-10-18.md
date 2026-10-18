# Physical Elements and NAS acceptance, 18 October 2026

User confirmed both devices available and supplied NAS host 192.168.0.22.
Only freshly created OpenCommander-LiveQA-* directories were written. No
format, repair, remount, detach, personal-content mutation, or OS restart.

## Elements: bounded tests passed

Physical USB disk6s1, 5 TB, volume Elements, partition UUID
005C1A70-98E8-48E6-8809-334901DC6E32. Already mounted read/write via FSKit
`openntfs` at `/Volumes/OpenCommander-005C1A70-98E8-48E6-8809-334901DC6E32`.
No new administrator prompt or remount was needed or performed.

Fresh fixture: `OpenCommander-LiveQA-20261018-eHWAwp` under that mount.
`ios/tests/LiveVolumeTests/main.swift` compiled against production durable
file/tree, volume identity and safety code. Exit zero:

- Foundation write/read, Unicode name, rename, overwrite and return copy.
- Production 3,145,865-byte durable copy with pause/resume and return copy.
- Production tree copy including hidden file and empty directory; exact size.

Forward/returned durable bytes share SHA-256
`f9ef6c8cc84e9bd046df978b405a3c8f95c582a8c25b86fb5bf779851cbbdd3e`.
Installed OpenCommander automatically displayed Elements, listed the fixture,
and created UI-Schreibtest through its New Folder dialog; independently verified.
The status shows `Unknown (openntfs)` rather than a friendly NTFS format label;
this cosmetic issue remains open. This is not a power-loss or physical-remount test.

## NAS: basic I/O and native properties passed; durable publication FAILED

SMB port 445 reachable. A no-password CLI listing rejected authentication, but
Finder subsequently connected the Test share using the available login.
Mounted `//nikki@192.168.0.22/Test` at `/Volumes/Test` (`smbfs`).
OpenCommander automatically displayed the Network: Test location.

Fresh fixture `/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg`.
Foundation write/read/rename/overwrite/return passed. Production durable file
and tree tests FAILED with NSPOSIXErrorDomain 45, Operation not supported.
The file journal reached a fully copied payload and then paused at exclusive
publication (`renamex_np(..., RENAME_EXCL)`). Tree publication also uses this
operation. Do not replace it with check-then-ordinary-rename: that could overwrite
a concurrently created destination. Recovery artifacts and sources are retained.
No success is claimed for resume completion or Elements-to-NAS app copying.

A separate Foundation copy of the synthetic tree succeeded. In the installed
app, Command-I on FoundationTree displayed name/path, dates, owner/group and
permissions without scanning. Calculate then reported exactly 6 bytes, including
the hidden test file, matching the fixture. This verifies bounded real NAS
properties, not denied-access/disconnect or every NAS implementation.

Fixtures retained for investigation; no cleanup of unrelated data. Installed
app unchanged in this batch. NAS durable publication remains an actual blocker
to full NAS parity, not an environment-only missing test.
