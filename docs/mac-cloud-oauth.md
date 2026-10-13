# Publisher desktop OAuth — Mac and Linux

Both builds accept the same **optional public application identities**. End users
sign in with their own cloud account; they do not create their own Azure project
when an approved publisher identity is supplied. No publisher identity is enabled
by this change. Provider approval, production limits and a real authenticated
round trip must be verified separately before advertising universal sign-in.

Mac Settings → Add location → provider opens the assistant in the existing window.
“Custom desktop app registration” overrides the bundled identity for a **new**
connection. Blank fields use the bundle identity, or the verified backend's default
when none is bundled. Existing configurations/accounts are never migrated or
overwritten. Cancelled/failed attempts are not saved as locations. Partial private
setup configurations may remain, outside the repository.

## Package an identity

Provide these environment variables to the Xcode build, matching `linux/build.sh`:

- `OPENCOMMANDER_GOOGLE_OAUTH_FILE`: official Google JSON exported for an
  **installed desktop** application; only its desktop ID/secret are packaged.
- `OPENCOMMANDER_ONEDRIVE_OAUTH_FILE`: JSON with exactly `client_id` (GUID) and
  `flow` set to `pkce`.
- `OPENCOMMANDER_DROPBOX_OAUTH_FILE`: JSON with exactly `client_id` (public app key)
  and `flow` set to `pkce`.

Store the input files outside source control (for example the ignored
`release/private-oauth/`). Microsoft/Dropbox server secrets, user tokens, Google
web/service-account exports and additional account fields are refused. Bundle
resources are generated with the **same validator** as Linux. A rebuild without
opt-in removes stale identities from the build product, not from user profiles.
Never hand-edit or commit credential-bearing `rclone.conf` files.

## Register the provider

For public OneDrive/Dropbox clients permit the exact desktop callback
`http://localhost:53682/`. Microsoft uses the `common` authority (organizational
and personal accounts) and `Files.ReadWrite.All offline_access User.Read`. Dropbox
requests offline access plus `account_info.read`, `files.metadata.read/write`,
`files.content.read/write`, and `sharing.read/write`, as the Linux reference does.
Enable the matching permissions in the provider registration; organizations may
require their administrator's consent. Scopes and production availability are
not silently widened by OpenCommander.

The flow uses fresh state and S256 PKCE, accepts callbacks only on 127.0.0.1 with
matching state/Host, requires a refresh token and exchanges codes only at fixed
official HTTPS endpoints. The callback and exchange are bounded and cancellable;
provider responses, codes and tokens are not shown in History or logs. Tokens are
written only after a successful exchange to a fresh 0600 user configuration.
OneDrive drive selection and a fresh directory check must also succeed before
saving the location. A browser website login by itself is not a file connection.

Provider references: [Microsoft authorization-code/PKCE flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow),
[Microsoft desktop redirect rules](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url),
[Dropbox OAuth](https://docs.dropboxapi.com/dropbox-api/docs/oauth).

## Verification

`sh tests/run-cloud-oauth-tests.sh` checks shared schemas, an RFC S256 vector,
callback rejection/denial/bounds, occupied port, timeout/cancellation, a real
synthetic loopback socket, bounded mock HTTP responses, private new-file writes,
existing-account preservation, and publisher packaging. It uses **no real account**
and is not a provider production-approval or live-authentication test.
