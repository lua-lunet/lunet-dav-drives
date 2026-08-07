#!/bin/sh
# End-to-end run. Hurl is the definition of done.
#
#   Teal source -> Cyan build -> tested unit smoke
#     -> Lunet runs the generated Lua from build/ -> Hurl asserts real HTTP
#
# This script owns the last two steps: it brings up the runtime dependencies,
# loads the schema, starts the server from build/, and runs the Hurl specs.
#
# Set KEEP_STACK=1 to leave the server and containers up for poking at.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE="docker compose -f $ROOT/e2e/docker-compose.yml"
HURL="$ROOT/.tools/hurl/8.0.1/hurl-8.0.1-aarch64-apple-darwin/bin/hurl"

# Tracer-round seed value. It is asserted verbatim by spec/hello.hurl, so a pass
# proves the value came out of Postgres rather than out of the Lua source.
SUBJECT='from postgres'

case "${1:-}" in
   up)
      $COMPOSE up -d --wait postgres minio
      $COMPOSE run --rm minio-init
      exit 0
      ;;
   down)
      $COMPOSE down --remove-orphans
      exit 0
      ;;
esac

cleanup() {
   if [ "${KEEP_STACK:-0}" != "1" ]; then
      make -C "$ROOT" stop >/dev/null 2>&1 || true
      $COMPOSE down --remove-orphans >/dev/null 2>&1 || true
   fi
}
trap cleanup EXIT INT TERM

# Export so the server process and psql both inherit the connection settings.
set -a
. "$ROOT/e2e/e2e.env"
set +a

$COMPOSE up -d --wait postgres minio
$COMPOSE run --rm minio-init

echo "loading sql/schema.sql"
psql -X -v ON_ERROR_STOP=1 -q \
   -c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;'
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/sql/schema.sql"

echo "seeding hello_tracer"
psql -X -v ON_ERROR_STOP=1 -q \
   -c "INSERT INTO hello_tracer (subject) VALUES ('$SUBJECT');"

make -C "$ROOT" start

"$HURL" --test "$ROOT/spec/health.hurl" \
   --variable host="$APP_HOST" \
   --variable port="$APP_PORT"

"$HURL" --test "$ROOT/spec/hello.hurl" \
   --variable host="$APP_HOST" \
   --variable port="$APP_PORT" \
   --variable subject="$SUBJECT"

echo "e2e ok"
