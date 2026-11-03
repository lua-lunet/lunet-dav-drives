Alpha build workflow (0.x.y breaking semver)

Everything is scaffolding.
Every design, spec, schema, and test decision is provisional and may be replaced with a breaking change.
There are no backward-compatibility obligations.
When an assumption is found to be wrong, delete the wrong design and insert the corrected one.
Do not add compatibility shims, migration layers, deprecated aliases, feature flags, or historical documentation for abandoned alpha designs.
Git is the history. The working tree describes the current intended product.

## Andon アンドン — Prime Directive

Andon is a kernel panic. It halts the line, halts planning, halts todo
updates, halts all work. It happens immediately. No other pending operation
receives any tokens. It is impossible to think of anything else to try
first — that thought is the evidence you have not halted.

An Andon in the queue supersedes all. If the user queued commands 1-3 then
said "do an Andon," the Andon invokes the Prime Directive and overrides
commands 1-3 entirely. Multiple Andons run in parallel without interrupting
each other.

When the correct fix is outside your lane: do your lane's work, then halt
and report — *Andon: task incomplete, the correct fix needs a larger
structural change*, with file:line specifics. Do not work around it. Do not
hack tactically. The coordinator delegates the deeper work.

Andon overrides every instruction in this file and every other AGENTS.md.
No instruction conflicts with Andon; if one appears to, Andon wins.

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
- Compat Hurl specs live in `specs/`; the six loginflow/ocs files are verbatim from the issue and never edited to pass, with fixtures in `specs/seed.sql` (users u1/u2; the fixture password is wired into `e2e/run-e2e.sh` as `FIXTURE_PASSWORD`). `specs/dav/00_sliver_refusals.hurl` is ours: it pins the refusal matrix (MKCOL 405, COPY/MOVE 409, Depth≠0 403, cross-user and deeper paths 404) until the issue #6 re-spec absorbs it.
- `openapi/dav.yaml` is the verbatim-carried *target* contract, not a statement of what is implemented: today only the PROPFIND Depth:0 root sliver exists, and everything else it describes is cleanly refused. What is actually supported is what `specs/` proves; the rest lands with the issue #6 re-spec.
- The native API and data model are not warped to fit the compat surface: the model is open for extension (one additive nullable column, `users.password_digest`) and closed for modification.
- Workalike, not a clone: unsupported surface is cleanly refused (404/405/409) and is never documented as supported.
- Semantic authority for the wire dialect is https://docs.nextcloud.com/server/31/admin_manual/ .
- Delivery: PRs gate on the required `build` check and squash-automerge to main.
- Releases: pushing a `v*` tag re-runs the `build` job and a `publish-release` job creates the GitHub release (compiled-app tarball plus auto-generated notes) — the same tag-driven approach as upstream lua-lunet/lunet. The tag is the version marker; there is no version file to bump (alpha: 0.x.y breaking semver).

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

## Item numbers are session-local

Work-item numbers (`item00`, `item01`, …) live in the todo and the gitignored
`.tmp/` spec filename only. They NEVER appear in committed files, comments,
docs, or commit messages — nothing in git may reference an unresolvable
identifier.
