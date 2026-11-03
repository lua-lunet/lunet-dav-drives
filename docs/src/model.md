# Model

```
User *---* Team 1---1 Drive 1---* File
User 1--------------------------* Personal File
```

The location rule is XOR:

- a file is either personal to one user, or shared in one drive;
- never both;
- never neither.

Files are flat. A logical filename is one name. No filename contains `/`.

There are no nested folders, recursive paths, or generic permission
engines. A Drive is a security boundary derived only from Team membership,
and a File belongs to exactly one location: personal user space XOR shared
drive.

Internal IDs are stable and distinct from human-readable names.

## Source of truth

- The authoritative SQL schema is [sql/schema.sql](https://github.com/lua-lunet/lunet-dav-drives/blob/main/sql/schema.sql).
- The authoritative API contract is [openapi.yaml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/openapi.yaml).
