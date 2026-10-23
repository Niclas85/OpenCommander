# Native late cloud reply acceptance — 2026-10-19

NAV-10, separate Mac test bundle/profile only. Existing authorized Drive
configuration referenced, never copied; root restricted to own existing
OpenCommander-LiveQA-Size12-wUvOA0 fixture. No cloud file mutation, new login,
permission grant, production installation or host restart.

Signed build `parity-20261019-late-cloud-listing-build.log`, exit 0. Clone's FSKit
extension detached before ad-hoc signing. DEBUG acceptance hook is limited to
exact MacUITests bundle plus validated AppDelegate.macUITestRoot. Normal build
cannot activate it. It holds an actual returned provider listing on a separate
async task, intentionally ignoring caller cancellation until explicit release,
bounded to 90 seconds. This models a late successful callback, not an actual
Internet outage or new provider implementation.

## Executed native sequence

1. Own HoldCloudListing.txt UUID 2CA6A5FD-C8B4-49F1-B7CA-E22B31229CC0 armed.
2. Opened direct Drive in left pane. Spinner/Ordner wird geladen displayed;
   CloudListingReady.txt independently confirms actual provider response arrived
   and is held before publication (same UUID, not an old marker).
3. Clicked return-to-local while busy, then immediately opened ToolsA left.
   Seven local entries displayed; right remains ToolsB.
4. Moved ONLY own flag to HoldCloudListing.saved, retaining it as evidence.
   CloudListingReleased.txt confirms same UUID and exactly:
   released=true cancelled=true stale=true. No timeout counted as release.
5. After release, native view remains ToolsA/seven entries, right ToolsB and
   status Ordner geöffnet. No cloud view/result replaced the current local pane.
   Independently checked online_pane_session_v1_1 remains absent both before and
   after release: delayed callback did not resurrect saved cloud navigation.
6. Reopened the same Drive location without a hold flag; normal retry result
   completed with Sub and a.txt, spinner removed, right still ToolsB.

This is real native UI plus controlled late delivery of real Drive metadata.
It does not claim physical network disconnect, every provider or every transfer
boundary. Existing model shared-read/invalidation tests remain separate evidence.

## NAV-11 and bounded Drive restart follow-up

Native successful retry displayed named `Google Drive – Werkzeugtest:/` and
Sub/a.txt, no raw profile ID as sole location label. Opened Sub: path becomes
`Google Drive – Werkzeugtest:/Sub`, b.txt listed, right ToolsB unchanged.

Regular app quit. Independently decoded only the test saved navigation metadata:
stable cloud location ID and components exactly [Sub], not session-local item IDs.
Fresh process PID 43662 observed after an initial UI observation timeout; same
process re-observed, never relaunched to mask the timeout. Restore first shows
loading at root, then resolves Sub and displays b.txt with correct named /Sub
path and matching expanded tree. Existing authorized configuration works without
another login; this is not a new OAuth-consent or all-provider credential test.

Clicked return-to-local after restored /Sub: left ToolsA/seven entries, right
ToolsB, no remaining online path label. NAV-11 bounded sequence complete.

Handoff: restored local RenameRestart/ToolsB, test app quit, exact temporary test
profile reference removed; original production configuration/account untouched.
Hold flag remains saved/inactive, Ready/Released nonce evidence retained. A/B
originals still match their recorded SHA-256 hashes. Installed app unchanged.
