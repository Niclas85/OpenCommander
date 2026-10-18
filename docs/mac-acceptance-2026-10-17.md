# Mac acceptance continuation — 2026-10-17

Reference fetched again: `origin/codex/linux-desktop` at `e3b2981`.
This is bounded acceptance evidence, not proof that every Linux state or every
third-party application behaves identically. Existing unrelated staged Linux
and Android changes were preserved.

## Automated results

All 14 regression runners exited successfully: Commander tools, handbook,
cloud storage discovery, OAuth, credential leases, runtime, cloud clients,
OneDrive, durable file and tree copies, transfer queue, NTFS access policy,
NTFS registration and remote transport fixtures. The additional real loopback
FTP, FTPS, SFTP key and SFTP password runner also exited successfully.
Together these logs contain 148 PASS groups (overlapping fixture groups are not
148 distinct features). Cloud tests include 22 separate-process phases.

Logs: `ntfs/NTFS3G/.build-native/acceptance-*.log`.
File-provider tests separately passed all eleven existing groups, 32 modifier
policy combinations and five new external transport policy assertions.

## Visible acceptance

Synthetic fixture: `.build-native/google-live-9hIyW4/OpenCommander-MacUITest-External-Keys`.

- Finder → OpenCommander: Option copied Alpha despite Move mode; exact bytes
  matched and source remained.
- Explicit Move imported the Unicode filename, retaining a private recoverable
  original. Undo restored the source and removed the visible destination.
- OpenCommander → Finder with Option copied Alpha; exact bytes matched.
- Search defaults to the active path, case sensitivity unchecked; `alpha*`
  found `Alpha.txt` with its full absolute path.
- Compare reported Alpha equal and the deliberately different sentinel unequal.
- Multi-rename preview numbered two selected files, apply renamed both, History
  showed timestamp and paths, and its Undo restored both original names.

## Fixed regression

The previous modifier change treated Catalyst's copy-only external transport
as the user's chosen file operation. Consequently explicit external Move was
lost. External operations now capture the toolbar/modifier intent separately;
the existing original-URL check still refuses moving temporary promises.

## Explicit limits — not passes

- Finder Command-drag into Catalyst was rejected without modifying files.
  Apple documents that UIKit move proposals are only supported within an app:
  <https://developer.apple.com/documentation/uikit/uidropoperation/move>.
  Explicit Move is tested; a native AppKit receiving implementation would be
  needed to remove the Command gesture restriction. The handbook explains it.
- Command-Option alias creation is unsupported and safely rejected.
- Arbitrary third-party apps, all publisher/provider login variants, exhaustive
  simultaneous-workflow failures and complete illustrated handbook parity are
  not claimed. No current physical Elements test is possible without the disk.
- Linux FUSE and real Linux desktop interactions were not exercised on this Mac.

The tested incremental build was installed at `/Applications/OpenCommander.app`.
Previous app: `.build-native/App-before-install.Mu6Vuh/OpenCommander.saved`.
Signature and FSKit identity checks passed. The installed app launched; a
Command-C/Command-V synthetic copy completed and matched exact bytes.
No NTFS drive was remounted, no approval changed, and the computer was not
restarted. This build must not be labelled complete cross-platform parity.
