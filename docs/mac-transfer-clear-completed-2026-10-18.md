# Transfer card cleanup — 2026-10-18

Implemented a localized “Remove all completed” header action. It removes only completed queue records, retains unfinished and recovery-sensitive jobs, and does not delete transferred files, recovery backups or history. Individual and bulk removal refresh both file panes. Rendering clamps the scroll position after cards disappear.

Validation:
- TransferQueueTests: 11 PASS groups (`queue-clear-completed-tests.log`). Includes mixed states, protected NAS cancellation, persistence, all-completed-to-empty and unchanged source/target/recovery bytes.
- FileOperationSafetyTests: 31 PASS groups (`queue-clear-file-safety.log`).
- Candidate build and extension signature checks passed (`queue-clear-completed-build.log`).
- Native UI: opened the existing list of 43 completed QA cards, scrolled down, selected “Alle abgeschlossenen entfernen”; empty-state text appeared and cleanup button disabled. Persisted job count became zero. Both panes remained populated after closing the panel. Normal app quit/relaunch retained the empty list.
- Previous card store backed up privately in `.build-native/queue-before-clear.LWpM4V/copy-jobs-v1.json` before acceptance.

After cross-cloud replacement resumption and two-sided Undo passed independent
live comparisons, this exact candidate was installed at `/Applications/OpenCommander.app`.
The previous app is retained in `.build-native/App-before-install.RP516v/OpenCommander.saved`.
This report does not certify full Linux parity.
