# Lunet Dav Drives

Lunet Dav Drives is a small document-storage service built around flat shared Drives.

It is an alpha 0.x.y system.
Everything is scaffolding.
Breaking pivots are expected.
There are no compatibility guarantees yet.

## The pipeline

```text
Teal source
  -> Cyan build
  -> tested unit smoke
  -> Lunet runs generated Lua from build/
  -> Hurl is the final DoD
```

Cyan owns the whole-project compile: every Teal source is compiled into
`build/`. Lunet only ever runs `build/server.lua` and `tested` only ever
runs `build/tests`; nothing runs a `.tl` file directly. The language is
type checked, so the compiler carries the load that tests would otherwise
carry, and Hurl against the real running server is the measure of done.

## What is in the box

- A native HTTP API, described by one OpenAPI 3.1 document
  ([openapi.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi.yaml)):
  health, identity, drive listing and metadata, flat file
  read/write/delete in drives and personal space, and a transactional
  personal-to-drive move.
- A small Nextcloud 31 work-alike compat surface: Login Flow v2, the OCS
  user/app-password endpoints, and a minimal DAV PROPFIND root.
- PostgreSQL for users, teams, drives, memberships, logical files, and
  audit history; an S3-compatible object store for blob bytes.
- Hurl specs that prove the wire behaviour of all of it against the real
  running server.

## Where next

- [Model](model.md) — the data model and the location rule.
- [Security](security.md) — how access is decided.
- [Native API](native-api.md) — the application-facing surface.
- [NCe31 compat surface](compat.md) — the Nextcloud work-alike.
- [Storage](storage.md) — logical files vs physical blobs.
- [Development and e2e](development.md) — building, testing, and the local docker stack.
