# NAS publication investigation — NOT RELEASED

The requested NAS fix is not complete. Installed app remains unchanged.

Confirmed on the user's SMB Test share with newly created synthetic fixtures:

1. `renamex_np(RENAME_EXCL)` returns ENOTSUP.
2. A Foundation same-volume `moveItem` fallback can finish regular transfers,
   but SMB file IDs change with the pathname. A pre-publication content-digest
   candidate recovered the regular-file pause/resume/readback case.
3. Tree verification still reported changed metadata on a newly copied hidden
   file. This was not ignored or represented as success.
4. Most importantly, two concurrent Foundation moves to the same destination
   both reported success, removed both synthetic sources and left one target.
   This is a lost synthetic publication, not a passing concurrency test.

Concrete rejected run: `/Volumes/Test/OpenCommander-LiveQA-NASFix-CZSZ9u`.
Race 0: one success; race 1: two successes and both sources absent. Other
rejected fixtures: `Opfoyf`, `EXVL8H`, `sU6hbE` under the same NASFix prefix.
All used only test-generated content; no personal files were modified.

The candidate modifications to DurableFileCopy and DurableTreeTransfer were
fully reversed, verified against the pre-turn Git content (both were clean
before this turn). The test-only Foundation concurrency diagnostic is retained
in LiveVolumeTests. No corrected version was installed because the safety gate
failed. Local durable copy/tree baseline runners passed, but do not cure SMB.

The public Foundation documentation promises refusal when a destination already
exists, but does not establish an atomic concurrent no-replace guarantee:
https://developer.apple.com/documentation/foundation/filemanager/moveitem(at:to:)
Do not use check-then-rename or suppress the failure. A follow-up needs a
server-enforced no-replace primitive or a journaled exclusive-create publication
design with explicit incomplete-target/recovery semantics, covering both files
and directories, replacement, lost responses and concurrent other clients.

Three detached own 64-MiB images were gzip-compressed (recoverable `.gz` files):
`/private/tmp/OpenCommander-NTFS-Queue-2b661D/test.ntfs`,
`/private/tmp/OpenCommander-NTFS-Queue-x2tlCR/test.ntfs`, and
`/private/tmp/OpenCommander-NTFS-Queue-xtqkTn/test.ntfs`.
No personal data or other project's build was removed. No reboot, security
change, NAS setting change, drive remount, commit or push.
