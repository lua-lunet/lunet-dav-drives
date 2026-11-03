# NCe31 compat surface

Alongside the native API, the server carries a small Nextcloud 31
work-alike surface: Login Flow v2, the OCS user/app-password endpoints,
and a minimal DAV PROPFIND root.

## Contracts

The compat contracts are the legacy OpenAPI 3.0.3 documents carried
verbatim from the issue that specified them:

- [openapi/auth.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi/auth.yaml) — Login Flow v2 and the OCS user/app-password surface:
  `/index.php/login/v2`, `/login/v2/grant`, `/login/v2/poll`,
  `/ocs/v2.php/core/getapppassword`, `/ocs/v2.php/cloud/user`,
  `/ocs/v2.php/cloud/users/{userId}`.
- [openapi/dav.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi/dav.yaml) — the DAV surface.
- The native contract stays [openapi.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi.yaml)
  (OpenAPI 3.1), unchanged.

## What is actually supported

Today only the PROPFIND Depth:0 root sliver under
`/remote.php/dav/files/{uid}/` exists. `specs/dav/00_sliver_refusals.hurl`
pins the refusal matrix (MKCOL 405, COPY/MOVE 409, Depth≠0 403, cross-user
and deeper paths 404). The verbatim-carried `openapi/dav.yaml` is the
*target* contract, not a statement of what is implemented: everything else
it describes is cleanly refused, and the rest lands with the DAV re-spec.

## Work-alike, not a clone

The unsupported surface is cleanly refused (404/405/409) and is never
documented as supported. The native API and data model are not warped to
fit the compat surface: the model is open for extension and closed for
modification. Semantic authority for the wire dialect is the
[Nextcloud 31 admin manual](https://docs.nextcloud.com/server/31/admin_manual/).
