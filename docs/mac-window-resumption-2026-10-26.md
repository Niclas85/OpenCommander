# Build24 acceptance resumed, 26 October 2026

Installed Build23 remains unchanged. The signed/notarized/stapled Build24
candidate remains held pending the remaining actual GUI acceptance; no release,
new account permission, personal-file mutation or reboot was performed.

## Actual native results

`/tmp/opencommander-b24-resumed-20261026-native.log`: two tests executed,
one passed and one failed, exit65. Result bundle:
`ntfs/NTFS3G/.build-native/ui-20261025/Logs/Test/Test-OpenCommander-2026.10.26_00-34-27-+0100.xcresult`.

- Final-source queue keyboard test passed, including the new pointer-return
  case: clicking an own fixture file leaves queue keyboard mode, Cmd-F opens
  the file search, queue focus can be restored, and both saved jobs resume with
  exact bytes. Forgetting cards preserves sources and completed destinations.
- The whole actual900x600 iteration passed: toolbar containment/hit checks,
  both path fields, shared language picker opened by keyboard and mouse,
  Escape dismissal, choosing Deutsch, and readable contained German queue
  controls. Retained screenshot `German-Transfers-900-points-Retina` inspected.
- Actual1366x768 sizing succeeded. Its initial Preview hit assertion failed
  before the wide settings/picker/queue sequence; that sequence is NOT passed.
  The retained screen recording's final frame reveals the concrete blocker:
  macOS requests Documents access for `OpenCommanderUITests-Runner` and places
  that system prompt over the test windows. This is not evidence of a Preview
  layout defect. Source inspection also shows updateDesktopActions does not
  disable Preview based on selection. No weaker hit assertion was substituted.
- Protected system prompt is not operated through another backend. The user
  was asked to explicitly click Allow themselves if it remains visible. The
  earlier generic Hinweis question is now narrowed to the actual prompt text.

Own exported attachments are retained in
`/private/tmp/OpenCommander-WindowEvidence-20261026.uSpUxe`.

## Additional bounded software regression

All eight scripts exited0. Logs use prefix
`/tmp/opencommander-b24-20261026-` and suffix `.log`:

- cloud-oauth: synthetic transport, PKCE/state, token response validation and
  publisher schema; not a new live provider sign-in.
- cloud-runtime: bounded process/configuration handling and sanitized errors.
- cloud-lease: account-change refusal, atomic refresh recovery and safe locks.
- profile-lease: actual SIGTERM/SIGKILL lock release, unsafe-node refusal.
- cloud-storage: Unicode listing, missing versus empty and observer lifecycle.
- durable-copy: actual SIGKILL checkpoint and fresh-process exact resume.
- durable-tree: replacement rollback, phased moves, source-change refusal.
- deletion-crash: six actual process-death Trash recovery cases on own files.

Aggregate passes do not establish every original Linux manual/provider/device
prerequisite. WebDAV stays excluded; complete parity remains unclaimed.

Three additional scripts exited0: `image-preview`, `onedrive` and
`ntfs-transfer`, with the same log prefix. OneDrive here is bounded synthetic
transport/cache/account-isolation regression, not a new real account sign-in.
NTFS used only new64MiB image `/private/tmp/OpenCommander-NTFS-Queue-j6dDKW/test.ntfs`
and the installed Build23 driver. Actual Foundation and durable regular-file/
directory copies APFS→NTFS passed. A paused1MiB checkpoint survived full device
detach/reattach and resumed with byte-exact output. Both disk6 attachments were
ejected. No existing physical disk or NAS was modified, and this does not claim
an unperformed candidate24 driver installation.
