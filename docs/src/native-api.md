# Native API

The application-facing API is described by one OpenAPI 3.1 document:
[openapi.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi.yaml).

Authentication is HTTP Basic (`user_id` + app-password plaintext secret).

## Endpoints

| Path | Purpose |
| --- | --- |
| `GET /health` | Service is healthy |
| `GET /v1/me` | Authenticated user identity |
| `GET /v1/drives` | Drives visible to the authenticated user |
| `GET /v1/drives/{drive_id}` | Drive metadata |
| `GET /v1/drives/{drive_id}/files` | Flat file listing for the drive |
| `PUT /v1/drives/{drive_id}/files/{name}` | Created or replaced file metadata |
| `GET /v1/drives/{drive_id}/files/{name}` | Raw file bytes |
| `HEAD /v1/drives/{drive_id}/files/{name}` | File metadata headers |
| `DELETE /v1/drives/{drive_id}/files/{name}` | Deleted |
| `GET /v1/personal/files` | Personal file listing |
| `PUT /v1/personal/files/{name}` | Created or replaced personal file |
| `GET /v1/personal/files/{name}` | Raw personal file bytes |
| `HEAD /v1/personal/files/{name}` | Personal file metadata headers |
| `DELETE /v1/personal/files/{name}` | Deleted personal file |
| `POST /v1/personal/files/{name}/move-to-drive` | Transactional personal-to-drive move |

The table is a map, not the contract: [openapi.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi.yaml)
is the contract. What the Hurl specs in [spec/](https://github.com/lua-lunet/lunet-dav-drives/tree/main/spec)
prove is what is supported.
