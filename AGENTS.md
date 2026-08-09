Alpha build workflow (0.x.y breaking semver)

Everything is scaffolding.
Every design, spec, schema, and test decision is provisional and may be replaced with a breaking change.
There are no backward-compatibility obligations.
When an assumption is found to be wrong, delete the wrong design and insert the corrected one.
Do not add compatibility shims, migration layers, deprecated aliases, feature flags, or historical documentation for abandoned alpha designs.
Git is the history. The working tree describes the current intended product.

Architectural laws

- One native HTTP API described by one OpenAPI 3.1 document.
- One authoritative SQL schema in `sql/schema.sql`.
- One runtime implementation for the product.
- One small Teal/Cyan-administered tooling surface.
- Flat personal spaces and flat Drives only.
- A File belongs to exactly one location: personal user space XOR shared drive.
- A Drive is a security boundary derived only from Team membership.
- No nested folders, recursive paths, folder ACLs, or generic permission engines.
- No server-side login/session state, browser auth, OAuth, JWT, or refresh tokens.
- Do not expose storage-provider details through the native API.
- Do not collapse logical files and physical blobs into one model.
- Keep internal IDs stable and distinct from human-readable names.
- Keep the implementation small; delete complexity when the model can be expressed directly.

Compat surface: NCe31 work-alike (issue #2)

- `app/nc31.tl` serves Login Flow v2 plus the OCS user/app-password surface; `app/nc31_dav.tl` serves one PROPFIND Depth:0 root sliver under `/remote.php/dav/files/{uid}/`.
- The compat contracts are `openapi/auth.yaml` and `openapi/dav.yaml`: legacy OpenAPI 3.0.3 documents carried verbatim from issue #2. The native contract stays `openapi.yaml` (OpenAPI 3.1), unchanged.
- Compat Hurl specs live in `specs/`, verbatim from the issue and never edited to pass, with fixtures in `specs/seed.sql` (users u1/u2; the fixture password is wired into `e2e/run-e2e.sh` as `FIXTURE_PASSWORD`).
- The native API and data model are not warped to fit the compat surface: the model is open for extension (one additive nullable column, `users.password_digest`) and closed for modification.
- Workalike, not a clone: unsupported surface is cleanly refused (404/405/409) and is never documented as supported.
- Semantic authority for the wire dialect is https://docs.nextcloud.com/server/31/admin_manual/ .
- Delivery: PRs gate on the required `build` check and squash-automerge to main.

Build and test workflow

```text
Teal source
  -> Cyan build
  -> tested unit smoke
  -> Lunet runs generated Lua from build/
  -> Hurl is the final DoD
```

Cyan owns the whole-project compile. Teal sources stay where they belong and Cyan
mirrors them as Lua under `build/`. Lunet only ever runs `build/server.lua`, and
`tested` only ever runs `build/tests/`. Nothing runs a `.tl` file directly.

The language is type checked, so lean on the compiler instead of writing tests
that restate types. Keep unit tests for pure logic and let Hurl prove behaviour
against the real running server. Hurl is the measure of done.

Modules that require Lunet APIs (`app.db`, `app.crypto`) only load inside
`lunet-run`, so they are not unit-testable under a plain Lua interpreter. Keep
pure logic in modules that require nothing, and let Hurl cover the rest.

Dependencies

When adding a dependency, consider adding its installation/bootstrap to
`make init`. Runtime/business dependencies that would otherwise fail obscurely
should also have a cheap fail-fast check at the start of `make test`, with an
error directing the developer to run `make init`. Build/test tools need not be
redundantly checked when their own build/test step already fails clearly if
absent.
