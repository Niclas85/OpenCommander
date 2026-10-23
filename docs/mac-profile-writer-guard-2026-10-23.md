# Mac profile writer guard — 2026-10-23

WebDAV remains excluded. This advances START-05, not full Linux parity.

## Correction

LaunchServices ordinarily reuses the app, but the queue's serial executor alone
does not prevent a forced second process from modifying the same profile.
The Catalyst AppDelegate now acquires a lifetime `CommanderProfileLease` before
fixture preparation, preference import, history or queue initialization. A busy
or inaccessible lease produces a localized alert in a minimal controller, never
the file/queue controller. This is not a stale-PID-file mechanism: `flock` owns
the open descriptor, close-on-exec prevents inheritance into child tools, and
the persistent lock file is never deleted. Nonregular, symlink, hard-linked or
foreign-owned lock files are refused. Failure does not silently disable safety.

## Process and native evidence

`parity-20261023-profile-lease-tests.log` exits0 with5 PASS groups:

- A second owner and path alias are excluded; a different profile can be leased;
  a new lock is0600 and normal release permits reacquisition.
- An actual own test child terminated with SIGTERM15 releases ownership.
- An actual own test child killed with SIGKILL9 releases ownership.
- A symlink lock is refused without changing its target sentinel.
- Hard-linked, directory and FIFO locks are refused without blocking or changing
  the sentinel. No process other than the synthetic child was signalled.

Native own fixture:
`/private/tmp/OpenCommander-MacUITest-ProfileGuard-20261023-AXOmYO`.
Separate MacUITests clone, extensions detached before signing. Production app
was not launched or replaced. A separate test holder acquired this root first.
The real native app displayed the German profile-in-use alert. Before dismissing
it, an independent check established that test preferences still referenced the
previous Keyboard fixture and the new root's Transfers directory did not exist:
startup had not initialized the blocked profile. OK quit the refused app.

After confirming the exact own holder process command, SIGTERM released it.
The same native clone then launched normally, displaying Left/Guard.txt28B and
Right/Sentinel.txt42B. Normal Command-Q, independently confirmed process absence,
and a fresh exact-clone launch succeeded without deleting the lock file.
The independent verifier then tried another lease while that native app was
running and received `.inUse`, also verifying exact file contents and no jobs.
After a final normal quit it acquired the same lease and again verified unchanged
files, no extra directory entries and an empty/absent queue.

Logs `parity-20261023-native-profile-running.log` and
`parity-20261023-native-profile-closed.log` each contain the corresponding PASS.
Helper `verify-profile-guard.swift` is constrained to the own dated test prefix.

## Build and regression

`parity-20261023-profile-lease-build.log`: BUILD SUCCEEDED; exact extension
identity, signature, sandbox and FSKit checks pass. The initial standalone holder
compile attempt with top-level code outside main.swift failed; adding its @main
entry corrected that helper. The failed attempt is not counted as a test pass.

`parity-20261023-profile-safety.log`: exit0,38 PASS groups.
`parity-20261023-profile-queue.log`: exit0,33 PASS groups, including cancellation,
reservation conflict refusal, damaged/full store refusal and1000-card pagination.
These are regression groups, not38/33 newly signed-off manual ledger cases.

## Remaining limits

This tests one real app against a separate real process holding the same lease,
not two forced native app executables. Independent directories are tested by the
lease model, not two fully independent UI preference/account profiles. Existing
instance folder handoff, every startup argument variant and the complete original
START-05 prerequisite sequence are not yet individually signed off. START-05
therefore remains partial; installed production app remains unchanged.
