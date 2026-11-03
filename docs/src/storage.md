# Storage

Logical file security and physical object storage are separate.

- **PostgreSQL** stores users, teams, drives, memberships, logical files,
  and audit history. The authoritative schema is
  [sql/schema.sql](https://github.com/lua-lunet/lunet-dav-drives/blob/main/sql/schema.sql).
- **An S3-compatible object store** stores blob bytes.
- Blob keys are internal implementation details and are not exposed by the
  native API.

Logical files and physical blobs are distinct models and are not collapsed
into one. Storage-provider details do not leak through the native API.

## The e2e object store

The e2e stack uses
[Garage](https://garagehq.deuxfleurs.fr/) (`dxflrs/garage`), the rust
S3-compatible stand-in with the same sigv4 API the client uses. MinIO was
dropped because it delisted its community binaries and images (dl.min.io
410, the Docker Hub image pulled in 2025, the quay.io org locked).

Garage implements versioning but not S3 Object Lock: the local stack
exercises the put/get/delete flows end to end, while WORM behaviour
(delete-refusal, GOVERNANCE retention, bypass-governance) can only be
verified against the real Scaleway nl-ams bucket.
