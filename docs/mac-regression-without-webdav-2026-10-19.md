# Mac regression without WebDAV — 2026-10-19

Scope: user explicitly excluded WebDAV. No personal files, NAS settings,
credentials, public sharing permissions or system security settings changed.

## Completed regression

All following runners exited successfully after the listed harness fixes.
Logs are in `ntfs/NTFS3G/.build-native/parity-20261019-*.log`.

| Runner | PASS groups |
|---|---:|
| Swift file safety | 31 |
| Durable file copy | 10 |
| Durable tree transfer | 7 |
| Transfer queue | 11 |
| File drop representations | 15 |
| Commander tools | 3 |
| Offline handbook | 2 |
| Image preview | 8 |
| NTFS access policy | 3 |
| NTFS registration | 3 |
| NTFS transfer fixtures | 22 |
| Cloud OAuth and publisher packaging | 8 |
| Cloud storage discovery/preferences | 9 |
| OneDrive (`onedrive-retry`) | 24 |
| Live loopback FTP/FTPS/SFTP (`remote-live-retry`) | 5 |
| Actual SMB NAS (`nas-live`) | 16 |

177 PASS groups, not 177 original manual acceptance cases. Existing 69-group
cloud-client and 12-group runtime runs remain separate supporting evidence.

Two runner source lists were stale after BoundedFolderSize was introduced.
Added FileOperationSafety and Localization to remote/OneDrive compiler inputs;
initial compiler failures are NOT passes. NAS runner now accepts the already
supported optional second physical fixture instead of incorrectly requiring it.

NAS fixture: `/Volumes/Test/OpenCommander-LiveQA-20261019-GY1RAL`.
Local NAS journal/source: `/private/tmp/OpenCommander-NASExclusive-1F60F7C5-88E0-4351-A38D-4B9DCA684E6B`.
Includes byte-verified transfers, restart resumption, changed-prefix/source
refusal, conflict handling, hidden flags, ACL preservation or safe refusal.
No external physical disk was connected; this is SMB/local, NOT fresh Elements.

## Native acceptance with direct computer control

Apple XCTest build succeeded, but execution failed before tests because enabling
UI Automation requested an administrator password. The prompt was cancelled;
no new automation privilege was granted. XCTest execution is NOT counted as pass.

Instead used its current isolated clone and fresh own fixture
`/private/tmp/OpenCommander-MacUITest-20261019-Tgd5RB`:
- F5 copied Alpha.txt left to right; independent cmp exact.
- History newest own entry 1053 had timestamp, survived normal quit/relaunch.
  Its specific Undo removed destination and preserved source.
- Search defaulted to active Left path, Match case unchecked; alpha.txt found
  Alpha.txt and result displayed full physical path.
- Connections showed NAS Test, refreshed, closed without changing pane paths.
- Native mouse drag Alpha.txt into Right/DropHere succeeded; independent cmp
  exact. Initial CUA gesture had no transfer; guarded driver first refused a
  covered endpoint and sent no events. After raising the test window the actual
  authorized driver completed. Only this verified gesture counts as passed.

## Limits

This is a broad reproducible regression and four direct native acceptance flows,
not a claim that every prerequisite/variation of the 158-case Linux manual matrix
was individually executed. WebDAV is excluded. Fresh iCloud 2FA, public-sharing
permission creation, every filesystem/device variant, live host network switching
and new Elements hardware acceptance remain unexecuted in this run. Existing
production code was not changed by the harness corrections above.

## Installation

Normal signed build passed (`parity-20261019-install-build.log`) and was installed
at `/Applications/OpenCommander.app`; startup verified. Previous app retained in
`.build-native/App-before-install.GdEhjF/OpenCommander.saved`. Production FSKit
identity/signature checks passed; no disk mounted or security approval changed.
No full-parity completion is claimed by this installation.
