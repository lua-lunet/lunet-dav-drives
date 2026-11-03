# Security

Drive access comes only from Team membership.
For the MVP, every Team member has read/write access to that Team's Drive.

Personal space is owner-only.

There are no nested ACLs, folders, inherited permissions, public links, or
sharing graphs.

## Authentication

Native API authentication is HTTP Basic:

- username = `user_id`
- password = app-password plaintext secret

There is no server-side login/session state, no browser auth, no OAuth, no
JWT, and no refresh tokens. The NCe31 compat surface issues app passwords
([OCS getapppassword](compat.md)) that the native API then verifies.

## Administration

Users, Teams, memberships, and app passwords are intentionally CLI-managed
for now, via [tools/admin.tl](https://github.com/lua-lunet/lunet-dav-drives/blob/main/tools/admin.tl).
The CLI is currently excluded from the Cyan build; it gets annotated and
wired in with `/v1/me`.
