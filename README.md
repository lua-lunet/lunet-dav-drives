# Lunet Dav Drives

Lunet Dav Drives is a small document-storage service built around flat shared Drives.

It is an alpha 0.x.y system.
Everything is scaffolding.
Breaking pivots are expected.
There are no compatibility guarantees yet.

## Model

```
User *---* Team 1---1 Drive 1---* File
User 1--------------------------* Personal File
```

The location rule is XOR:

- a file is either personal to one user, or shared in one drive;
- never both;
- never neither.

Files are flat. A logical filename is one name. No filename contains `/`.

## Security

Drive access comes only from Team membership.
For the MVP, every Team member has read/write access to that Team’s Drive.

Personal space is owner-only.

There are no nested ACLs, folders, inherited permissions, public links, or sharing graphs.

## Native API

The application-facing API is described in [openapi.yaml](./openapi.yaml).

It provides:

- health checks;
- identity lookup for the authenticated user;
- drive listing and drive metadata;
- flat file read/write/delete in drives and personal space;
- a transactional personal-to-drive move.

Authentication is HTTP Basic:

- username = `user_id`
- password = app-password plaintext secret

## Administration

Users, Teams, memberships, and app passwords are intentionally CLI-managed for now.

Examples:

The CLI in [tools/admin.tl](./tools/admin.tl) is still untyped Lua in a `.tl`
file, so it is currently excluded from the Cyan build. It gets annotated and
wired in with `/v1/me`.

```sh
make init
make db-reset
luajit build/tools/admin.lua user add user7 user7@example.test "User Seven"
luajit build/tools/admin.lua team add A A
luajit build/tools/admin.lua team member-add A user7
luajit build/tools/admin.lua app-password mint user7 test
```

## Storage

Logical file security and physical object storage are separate.

- PostgreSQL stores users, teams, drives, memberships, logical files, and audit history.
- A configured S3-compatible object store stores blob bytes.
- Blob keys are internal implementation details and are not exposed by the native API.

## Development

Start here:

```sh
make init
make help
```

`make init` installs and checks every dependency — build, test, and runtime —
and seeds `.env` from [.env.example](./.env.example). It is safe to rerun; it
only fetches what is missing.

`make help` documents every target and is what a bare `make` prints.

Then the whole chain is one command:

```sh
make test
```

```text
Teal source
  -> Cyan build
  -> tested unit smoke
  -> Lunet runs generated Lua from build/
  -> Hurl is the final DoD
```

Cyan compiles every Teal source into `build/`. Lunet only ever runs
`build/server.lua` and `tested` only ever runs `build/tests`; nothing runs a
`.tl` file directly. The language is type checked, so the compiler carries the
load that tests would otherwise carry, and Hurl against the real running server
is the measure of done.

`make test` begins with a fast check of the runtime dependencies it cannot
usefully proceed without, and tells you to run `make init` if one is missing.

The docker ports in [e2e/e2e.env](./e2e/e2e.env) are deliberately distinct from
other lunet-dav stacks so several can run on one machine at once.

## Schema and API source of truth

- [sql/schema.sql](./sql/schema.sql)
- [openapi.yaml](./openapi.yaml)

