# Mac continuation acceptance, 18 October 2026

Reference: `codex/linux-desktop@e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`.
The remote branch was checked again and had not advanced. This is additional
bounded evidence, not a declaration of full Linux parity.

## Implemented and verified

- Local folder properties now calculate a bounded report on demand. Inaccessible
  descendants produce a visibly partial lower bound and an error count, not a
  misleading complete size or a swallowed error. Time/entry/overflow limits are
  explicit; symbolic links and private recovery directories are excluded.
  Existing transfer-verification size semantics remain unchanged.
- Command-L opens the existing Go to Folder dialog. Shared local path parsing
  accepts absolute paths, home paths and local file URLs, preserves meaningful
  trailing spaces, and rejects remote file-URL hosts, embedded credentials,
  queries, fragments and NULs. macOS no longer applies the iOS Documents alias.
- English/German messages and handbook were updated.

Regression runners `run-swift-safety.sh`, `run-commander-tools-tests.sh` and
`run-handbook-tests.sh` exited zero. The r22 isolated native build succeeded.
Logs are under `ntfs/NTFS3G/.build-native/acceptance-20261018-continuation-*`.

Native properties fixture: a readable 22-byte file and a denied directory with
a 39-byte file. Initial properties did not scan. Calculate showed at least
22 bytes, two examined entries and one read error. Restoring directory access
and calculating again showed 61 bytes. Original test permissions were restored.

Native path fixture includes Unicode, shell punctuation, percent/hash and a
literal trailing space. Its percent-encoded local file URL opened Proof.txt.
A remote-host file URL was rejected with the German error, preserving the
current folder. Command-A/Backspace in the filter edited text and did not delete
the selected file.

## External mixed-selection acceptance

Only synthetic files in
`/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-2sdjC5/ExternalR22`
were used. The guarded, authorized local mouse driver retained fixture and
visible endpoint ownership checks. Covered-endpoint attempts were refused
before sending events; own Finder/test-app windows were raised before retrying.

1. Finder Option-drag of a Unicode file plus a directory into OpenCommander:
   exact bytes, nested child and empty subdirectory preserved; source retained.
2. Repeating the drop showed two conflicts. Cancel left all content unchanged.
3. Changed only the synthetic source files, repeated the drop and chose Replace:
   target matched both new source contents; unrelated sentinel was unchanged.
4. Two toolbar Undo actions restored the original directory and Unicode file,
   verified independently by bytes; new source versions were untouched.
5. Selected only the two target elements, Option-dragged into empty Finder
   destination: exact original bytes and empty subdirectory arrived; source
   remained and the unselected sentinel was not exported.
6. Selected both Finder results and Command-dragged into an empty app folder:
   Finder source became empty; both exact contents and empty directory arrived.

Original SHA-256: Unicode file
`0c16e13df88b49d5406741fa8abed140c54ee507407d5b769a0ed14e1c99bf2a`,
child `59e7328da503abedfb870d0ea603a16560cec1470d4456521aec7ef3b8f7e636`.
Replacement SHA-256: Unicode file
`04a9b5b65c3ea2921b4a68baa7c23dde68b5bd370b1498e07621758e4658dbd0`,
child `53af5296adf42a8610fbf63a38ca67bf64710f90fb5f3348a37af2465df2f836`.

## Limits

The earlier successful 7,204-second bounded CloudFileClient endurance run is
retained, not repeated or relabelled as a live-provider network endurance run.
Elements is unavailable. No physical-disk test, OS restart, new account grant,
commit or push occurred. Arbitrary third-party representations and every
original Linux manual prerequisite remain unaccepted. In particular this
local properties proof does not claim remote recursive-size parity.

## Installed and checked

The normal signed build succeeded and replaced `/Applications/OpenCommander.app`.
Deep strict signature verification passed. Its debug-library SHA-256 is
`6c3d30411157cc5fb2a9acd9799097755158a675f75bab2de04147c58b421a73`.
The previous app is retained at
`ntfs/NTFS3G/.build-native/App-before-install.buqnP2/OpenCommander.saved`.
The stable NTFSModuleV2 identity remains unchanged. No active transfer was
interrupted; the installed app's queue showed completed jobs before quitting.

After launch, Google Drive displayed 14 file rows and OneDrive 15, without
new authentication. Google's existing duplicate-name protection warning remains;
no personal cloud content was changed. Original iCloud/Downloads panes restored.

Fresh NTFS image integration exited zero, including file/tree transfers and
byte-exact durable resume after complete detach/reattach. Fixture retained at
`/private/tmp/OpenCommander-NTFS-Queue-xtqkTn`; image normally ejected.
Log: `ntfs/NTFS3G/.build-native/acceptance-20261018-continuation-postinstall-ntfs.log`.
