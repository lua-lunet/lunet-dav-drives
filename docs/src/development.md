# Development and e2e

Start here:

```sh
make init
make help
```

`make init` installs and checks every dependency — build, test, and
runtime — and seeds `.env` from
[.env.example](https://github.com/lua-lunet/lunet-dav-drives/blob/main/.env.example).
It is safe to rerun; it only fetches what is missing. The Lua tooling rocks
(tl, cyan, tested) are version-pinned so a newly published major cannot
break the unit smoke.

`make help` documents every target and is what a bare `make` prints.

## The chain

The whole chain is one command:

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
`build/server.lua` and `tested` only ever runs `build/tests`; nothing runs
a `.tl` file directly. The language is type checked, so the compiler
carries the load that tests would otherwise carry, and Hurl against the
real running server is the measure of done.

`make test` begins with a fast check of the runtime dependencies it cannot
usefully proceed without, and tells you to run `make init` if one is
missing.

## The e2e docker stack

`make test` brings up the stack from
[e2e/docker-compose.yml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/e2e/docker-compose.yml):

- **postgres:16.4-alpine** on `127.0.0.1:55442` — the SQL store.
- **Garage** (`dxflrs/garage`) on `127.0.0.1:19010` — the S3-compatible
  blob store, configured by [e2e/garage.toml](https://github.com/lua-lunet/lunet-dav-drives/blob/main/e2e/garage.toml),
  region `garage`. Its admin API answers on `127.0.0.1:19011` for
  `make check-s3`.
- **s3init** — a one-shot that bootstraps the Garage layout, bucket, and
  access key via the admin API. Idempotent: the generated key is reused
  across restarts and recreated only when the secret is unknown.

The generated S3 credentials live in the `s3creds` volume;
[e2e/run-e2e.sh](https://github.com/lua-lunet/lunet-dav-drives/blob/main/e2e/run-e2e.sh)
sources them and exports them for the server. Stored objects are verified
by an aws-cli read-back against the Garage endpoint.

The docker ports are deliberately distinct from other lunet-dav stacks so
several can run on one machine at once. Keep them in step with
[e2e/e2e.env](https://github.com/lua-lunet/lunet-dav-drives/blob/main/e2e/e2e.env).

## Runtime

The lunet runtime is not a system dependency: the committed release
fetcher (`lunet_fetch_release_v0.18.2.lua`) downloads the official binary
release, verifies its SHA-256 against the release metadata before
extraction, and installs it project-locally under `.lunet/<tag>/`.
`make init` runs it; `make clean` removes the install.
