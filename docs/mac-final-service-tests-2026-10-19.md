# Additional service acceptance — 2026-10-19

## Actual TCP interruption

Added a loopback-only SFTP fixture fault. Drop-transfer.txt returns its first
payload block, then a later read closes the actual Paramiko TCP transport once.
Listening service remains available. Tests run for key and password login:
- interrupted download throws, never reports success or user cancellation;
- server original remains byte-identical;
- explicit second download succeeds and matches 1 MiB + 17 bytes exactly.

`final-tcp-midstream-20261019.log`: runner exit 0, both new cases and existing
FTP/FTPS/SFTP negative-auth, TLS and cancellation cases passed. Earlier
`final-tcp-loss-20261019.log` tested connection loss at file-open; it is not the
midstream evidence. No host network or user NAS share was disconnected.

## iCloud backend

`final-icloud-backend-20261019.log`: runtime runner --install exited 0. Actual
installed rclone setup selects Drive and requests explicit Apple ID; synthetic
password stdin encoding and local Unicode/empty-directory/immutable-write plan
passed. No real Apple credentials were submitted by this runner.

User subsequently authorized preparing real iCloud login. In installed app:
Settings / Locations → Add location → iCloud Drive online → New login.
Native CloudSetupAnswer is now waiting at Apple-ID / Apple Account; window
raised for user entry. No Apple ID inferred, password read, or 2FA bypassed.
Real account acceptance remains pending user entry; not counted as passed.

## NAS isolation limitation

Tried a separate own mount at `/private/tmp/OpenCommander-NASMount.sWpiMQ`.
Reuse refused as already mounted; forced new SMB session with no password
prompt was rejected for authentication. No mount created, no credential printed,
no original share unmounted, no server settings changed. Existing actual SMB
fixture/fault tests remain valid, but no real NAS disconnection is claimed.

Production app code unchanged in this continuation; installed verified release
left intact with the authorized iCloud setup dialog open. Do not replace/quit
it mid-login. Public sharing and fresh iCloud consent are not silently inferred
from simulated tests. WebDAV remains excluded by user instruction.
