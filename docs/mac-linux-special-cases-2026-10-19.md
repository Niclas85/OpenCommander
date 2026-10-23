# Additional bounded Linux → Mac acceptance, 19 October 2026

Reference fetched again: `origin/codex/linux-desktop` remains
`e3b2981ad5a88551be81b86b6c6453e26e2e2ff5`. WebDAV deliberately excluded.
This is not a declaration of full parity of all 158 original manual cases.

## SERVER-03: actual encrypted OpenSSH key and expiring private agent

Extended the loopback fixture with a synthetic encrypted OpenSSH RSA key.
Native DesktopBridge SFTP talks to the existing disposable Paramiko server.
Test starts its own ssh-agent with a short private socket path, temporarily
selects it only in the test process, and restores the original environment.
No personal agent/keychain/server is accessed. Synthetic askpass is fixture-only.

Final r3 log passes: empty agent refuses locked key; ssh-add unlocks for ten
seconds; actual expiry refuses subsequent SFTP; explicit re-unlock reconnects
and downloads exact fixture bytes. Encrypted file bytes and 0600 permissions
unchanged. Agent is terminated on normal test exit. Help and SSH error text
now explain prior time-limited unlock and re-unlock after expiry (DE/EN).

Earlier r1 failed because /var/folders made its socket path too long. R2 used
legacy encrypted PEM without a companion public key and failed authentication;
the specified OpenSSH-format fixture in r3 passes. Neither failed run counts
as a passing product test. Existing FTP/FTPS/password/key suites and actual
TCP interruption, cancellation, host-key and TLS refusal also passed in r3.
Log: `.build-native/parity-20261019-agent-live-r3.log`.

## REC-12 and queue admission

Disposable clone only: `/private/tmp/OpenCommander-MacUITest-Special-20261019-dYWldw`.
FSKit extension detached before ad-hoc signing; production registration untouched.
Seeded malformed Transfers journal plus independent known-good backup, Source.txt
and Sentinel.txt. Native startup and F5 safely refused with no publication;
all data hashes unchanged. Found misleading `Queued` global status despite
refusal. Fixed: known admission errors do not enqueue/fall back; asynchronous
queue errors update global status. Queue now exposes stable localized error
keys; full queue is not misdescribed as unreadable/corrupt. Panel tracks error
identity, not only its presence. Native corrected repeat displays accurate
error in panel and global status, never `Queued`; damaged original retained.

Queue regression tests pass damaged journal retention, zero destination writes,
1,000-card capacity refusal, removal then successful retry and exact bytes.
An initial test run was invalidated by an edited input; the next reused a source
already moved by an earlier test and timed out. A distinct new admission fixture
passes; failed attempts are not passes. Log: `parity-20261019-queue-errors-r3.log`.

## PROP-03 subset

Native Command-I on own Sizes folder displays size `—`, offers explicit bounded
calculation, then reports exactly 10 bytes (6 + 4). A cycle symlink and external
sentinel symlink are not followed. This verifies native opt-in and symlink
behavior; large/denied/time-limit variants remain separate regression evidence.

## JOB-11 / SAFE-05 continuation

Native full queue previously constructed all 1,000 cards; its accessibility
observation timed out. Added pages of at most 50 visible cards, newest first.
All global controls and persistence retain full job collection. Page bounds
clamp after removals; error keys remain live even with unchanged card IDs.
Fresh paged tests/build/native verification are in progress, not yet passed.

No reboot, production account/security changes, personal-file deletion or
commit/push. Installation will follow verified build/native checks.

## Completed follow-up native checks

Paged queue native F5 at capacity displays correct full-queue text, Page 1/20;
Older opens Page 2/20. AX contains exactly 50 TransferProgress controls there.
Removing one cancelled card updates count to 999. Retrying F5 completes, cmp
exact, 999 cancelled plus one completed in journal. Global remove-completed
on Page 2 removes the completed card from the other page, count 999 and button
disabled, while copied file remains exact. A stale global capacity warning
after freeing a card was additionally cleared when that exact error disappears.
This is not a universal one-second latency or heap-growth benchmark: AX itself
still takes seconds to enumerate 50 rich cards. No timeout counted as a pass.

Known-good queue backup restored in the closed disposable profile; normal
restart and subsequent transfers succeeded. Damaged journal backup unchanged.
Native Command-C/V copied exact bytes, Command-X retained source until Paste,
then moved exact bytes and removed the old source. Empty-area context-menu
Paste also exact. Missing-source test after external rename reports explicit
missing/unavailable, publishes nothing; positive source data remains intact.
Definitive negative run used only folder double-clicks/clicks after Copy, not
path-field automation which may change system clipboard revision. Complete
selection validation now rejects missing members instead of silently skipping
them; unit proof includes mixed missing entries, web URLs and broken symlinks.

Queue preflight now rejects a whole dangerous batch before admission. Actual
F5 folder→own child, F6 symlink-alias→own child, and F5 same source/preferred
destination all refuse clearly. Independent journal has zero Recursive jobs;
original tree remains only Keep.txt and empty Child. Legacy transfer engine
checks remain in place; this adds early protection to queued admission.

Native handbook: about:blank document, 18 chapter anchors; SSH search Match 1/3
and Next 2/3; Print opened native ten-page preview, cancelled with no printer
selected and no print/PDF submission. Archive chapter link visibly scrolls to
the actual archive section (screenshot inspected), not a blank external page.
Publisher link visible but not opened. Static CSP/resource safety tests remain.

Successful current logs: `parity-20261019-queue-pages.log` (13 groups),
`parity-20261019-clipboard-safety.log` (32 groups), native agent r3 (8 groups),
and signed build `parity-20261019-path-clipboard-build.log`. Earlier failed
attempts remain diagnostic and are not included in these passing totals.

Installed that exact signed build at `/Applications/OpenCommander.app`.
Previous app retained at `.build-native/App-before-install.eYh6Z1/OpenCommander.saved`.
Installed startup restores German, iCloud test path and file without new login.
Stable FSKit V2 and helper signatures validated; no volume remount/approval changed.
The master ledger now records 31 bounded native cases, 117 partial, 10 requiring
environment/account capabilities. `complete` remains false, not a release of a
fully certified 158-case parity matrix. WebDAV remains excluded.

Next gated live case: installed normal app opened Google Drive own QA folder
`OpenCommander-LiveQA-Size12-wUvOA0/a.txt`. Context action opened the explicit
public-sharing warning; Create NOT pressed. This only stages consent, does not
create a permission/link. User action-time confirmation requested for this
exact synthetic file, since a link can expose it persistently to anyone holding
the link. Public sharing, fresh multi-account login/device variants and other
partial sequences are not silently marked passed.

## CLOUD-09: authorized Google public-link live check

User explicitly approved the pending public-link action for that exact synthetic
`OpenCommander-LiveQA-Size12-wUvOA0/a.txt` file. Clicked Create once in the
installed app. The provider returned a Google Drive sharing URL; Open link
opened that same file in Chrome. Browser displays `a.txt`, an `Anmelden` link
(not a signed-in account), and Download; Google's viewer reports no preview.
An independent HTTPS download with no credentials, cookies, or application
configuration succeeded: exactly five bytes `31 32 33 34 0a` (`1234\n`), SHA-256
`a883dafc480d466ee04e0d6da986bd78eb1fdd2178d04693723da3a8f95d42f4`.
Thus the grant and unauthenticated read actually work, not merely link creation.
The capability URL is deliberately omitted from this repository document.

The permission remains public to link holders as explicitly approved; closing
the result does not revoke it. No other file/account permission was changed.
Dropbox and OneDrive public-link grants remain untested; CLOUD-09 is partial,
not a complete three-provider pass. No source fix or new installation was
needed for this successful check; the signed app installed above remains active.
