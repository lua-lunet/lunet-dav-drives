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

ADMIN="$ROOT/tools/admin.tl"
PERSONAL_BODY='personal bytes'
PERSONAL_NAME='personal.txt'
DRIVE_BODY='shared bytes'
DRIVE_NAME='shared.txt'
DELETE_PERSONAL_BODY='delete personal'
DELETE_DRIVE_BODY='delete drive'
MOVE_BLOCKED_BODY='blocked move'
MOVE_BODY='move me'
FIXTURE_PASSWORD='fixture-password'

body_length() {
   printf '%s' "$1" | wc -c | tr -d ' '
}

shell_quote() {
   printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

mint_password() {
   user_id=$1
   name=$2
   output=$("$LUAJIT" "$ADMIN" app-password mint "$user_id" "$name")
   secret=$(printf '%s\n' "$output" | awk -F': ' '/^secret: /{print $2; exit}')
   eval "password_$user_id=$(shell_quote "$secret")"
}

seed_user() {
   "$LUAJIT" "$ADMIN" user add "$1" "$2" "$3" >/dev/null
}

seed_team() {
   "$LUAJIT" "$ADMIN" team add "$1" "$2" >/dev/null
}

seed_member() {
   "$LUAJIT" "$ADMIN" team member-add "$1" "$2" >/dev/null
}

verify_object() {
   expected_body=$1
   expected_key=$2
   docker run --rm --network lunet-dav-drives-e2e_default \
      -e EXPECTED_BODY="$expected_body" -e EXPECTED_KEY="$expected_key" \
      -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
      -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" \
      -e AWS_DEFAULT_REGION="$S3_REGION" \
      -e AWS_EC2_METADATA_DISABLED=true \
      --entrypoint /bin/sh amazon/aws-cli -c '
         set -e
         actual=$(aws --endpoint-url http://garage:3900 s3 cp \
            "s3://lunet-dav-drives/$EXPECTED_KEY" - --no-progress)
         [ "$actual" = "$EXPECTED_BODY" ]
      '
}

run_hurl() {
   spec=$1
   shift
   "$HURL" --test "$ROOT/$spec" \
      --variable host="$APP_HOST" \
      --variable port="$APP_PORT" \
      "$@"
}

run_auth() {
   user_id=$1
   display_name=$2
   email=$3
   password_var=$4
   eval "password=\${$password_var}"
   run_hurl spec/auth.hurl \
      --variable user_id="$user_id" \
      --variable password="$password" \
      --variable display_name="$display_name" \
      --variable email="$email"
}

case "${1:-}" in
   up)
      $COMPOSE up -d --wait postgres garage
      $COMPOSE run --rm s3init
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

LUAJIT=$(command -v luajit)

$COMPOSE up -d --wait postgres garage
$COMPOSE run --rm s3init

# The s3init one-shot generates (and reuses) the e2e S3 key in the s3creds
# volume; read it back so the app server inherits real credentials.
s3_creds=$($COMPOSE run --rm --entrypoint /bin/sh s3init -c 'cat /creds/s3.env')
S3_ACCESS_KEY_ID=$(printf '%s\n' "$s3_creds" | sed -n 's/^S3_ACCESS_KEY_ID=//p')
S3_SECRET_ACCESS_KEY=$(printf '%s\n' "$s3_creds" | sed -n 's/^S3_SECRET_ACCESS_KEY=//p')
[ -n "$S3_ACCESS_KEY_ID" ] && [ -n "$S3_SECRET_ACCESS_KEY" ] \
   || { echo "s3init produced no credentials"; exit 1; }
export S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY

echo "loading sql/schema.sql"
psql -X -v ON_ERROR_STOP=1 -q \
   -c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;'
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/sql/schema.sql"

echo "loading specs/seed.sql"
psql -X -v ON_ERROR_STOP=1 -q -f "$ROOT/specs/seed.sql"

echo "seeding users, teams, memberships, and app passwords"
seed_user user1 user1@example.test "User One"
seed_user user2 user2@example.test "User Two"
seed_user user3 user3@example.test "User Three"
seed_user user4 user4@example.test "User Four"
seed_user user5 user5@example.test "User Five"
seed_user user6 user6@example.test "User Six"
seed_user user7 user7@example.test "User Seven"
seed_user user8 user8@example.test "User Eight"
seed_user user9 user9@example.test "User Nine"

seed_team A A
seed_team B B
seed_team C C

seed_member A user1
seed_member A user2
seed_member B user3
seed_member B user4
seed_member C user5
seed_member C user6
seed_member A user7
seed_member B user7
seed_member B user8
seed_member C user8
seed_member A user9
seed_member B user9
seed_member C user9

mint_password user1 e2e
mint_password user2 e2e
mint_password user3 e2e
mint_password user4 e2e
mint_password user5 e2e
mint_password user6 e2e
mint_password user7 e2e
mint_password user8 e2e
mint_password user9 e2e

make -C "$ROOT" check-s3
make -C "$ROOT" start

"$HURL" --test "$ROOT/spec/health.hurl" \
   --variable host="$APP_HOST" \
   --variable port="$APP_PORT"

run_auth user1 "User One" user1@example.test password_user1
run_auth user2 "User Two" user2@example.test password_user2
run_auth user3 "User Three" user3@example.test password_user3
run_auth user4 "User Four" user4@example.test password_user4
run_auth user5 "User Five" user5@example.test password_user5
run_auth user6 "User Six" user6@example.test password_user6
run_auth user7 "User Seven" user7@example.test password_user7
run_auth user8 "User Eight" user8@example.test password_user8
run_auth user9 "User Nine" user9@example.test password_user9

run_hurl spec/drives.hurl \
   --variable user_id=user1 \
   --variable password="$password_user1" \
   --variable drive_id_1=1 \
   --variable drive_name_1=A

run_hurl spec/drives.hurl \
   --variable user_id=user2 \
   --variable password="$password_user2" \
   --variable drive_id_1=1 \
   --variable drive_name_1=A

run_hurl spec/drives.hurl \
   --variable user_id=user3 \
   --variable password="$password_user3" \
   --variable drive_id_1=2 \
   --variable drive_name_1=B

run_hurl spec/drives.hurl \
   --variable user_id=user4 \
   --variable password="$password_user4" \
   --variable drive_id_1=2 \
   --variable drive_name_1=B

run_hurl spec/drives.hurl \
   --variable user_id=user5 \
   --variable password="$password_user5" \
   --variable drive_id_1=3 \
   --variable drive_name_1=C

run_hurl spec/drives.hurl \
   --variable user_id=user6 \
   --variable password="$password_user6" \
   --variable drive_id_1=3 \
   --variable drive_name_1=C

run_hurl spec/drives_two.hurl \
   --variable user_id=user7 \
   --variable password="$password_user7" \
   --variable drive_id_1=1 \
   --variable drive_name_1=A \
   --variable drive_id_2=2 \
   --variable drive_name_2=B

run_hurl spec/drives_two.hurl \
   --variable user_id=user8 \
   --variable password="$password_user8" \
   --variable drive_id_1=2 \
   --variable drive_name_1=B \
   --variable drive_id_2=3 \
   --variable drive_name_2=C

run_hurl spec/drives_three.hurl \
   --variable user_id=user9 \
   --variable password="$password_user9" \
   --variable drive_id_1=1 \
   --variable drive_name_1=A \
   --variable drive_id_2=2 \
   --variable drive_name_2=B \
   --variable drive_id_3=3 \
   --variable drive_name_3=C

run_hurl spec/drive_detail.hurl \
   --variable user_id=user1 \
   --variable password="$password_user1" \
   --variable drive_id=1 \
   --variable drive_name=A \
   --variable forbidden_drive_id=2

run_hurl spec/personal_list.hurl \
   --variable user_id=user1 \
   --variable password="$password_user1"

run_hurl spec/drive_files_list.hurl \
   --variable user_id=user1 \
   --variable password="$password_user1" \
   --variable drive_id=1

run_hurl spec/personal_file.hurl \
   --variable user_id=user1 \
   --variable password="$password_user1" \
   --variable other_user_id=user2 \
   --variable other_password="$password_user2" \
   --variable name="$PERSONAL_NAME" \
   --variable body="$PERSONAL_BODY" \
   --variable body_length="$(body_length "$PERSONAL_BODY")"

verify_object "$PERSONAL_BODY" "_objects/$(printf '%s' "$PERSONAL_BODY" | shasum -a 256 | awk '{print $1}')"

run_hurl spec/drive_file.hurl \
   --variable writer_user_id=user1 \
   --variable writer_password="$password_user1" \
   --variable reader_user_id=user2 \
   --variable reader_password="$password_user2" \
   --variable other_user_id=user3 \
   --variable other_password="$password_user3" \
   --variable drive_id=1 \
   --variable name="$DRIVE_NAME" \
   --variable body="$DRIVE_BODY" \
   --variable body_length="$(body_length "$DRIVE_BODY")"

run_hurl spec/delete.hurl \
   --variable owner_user_id=user4 \
   --variable owner_password="$password_user4" \
   --variable personal_name="delete-personal.txt" \
   --variable personal_body="$DELETE_PERSONAL_BODY" \
   --variable member_user_id=user2 \
   --variable member_password="$password_user2" \
   --variable non_member_user_id=user3 \
   --variable non_member_password="$password_user3" \
   --variable drive_id=1 \
   --variable drive_name="delete-drive.txt" \
   --variable drive_body="$DELETE_DRIVE_BODY"

run_hurl spec/move.hurl \
   --variable user_id=user7 \
   --variable password="$password_user7" \
   --variable drive_id=1 \
   --variable forbidden_drive_id=3 \
   --variable reader_user_id=user1 \
   --variable reader_password="$password_user1" \
   --variable other_user_id=user3 \
   --variable other_password="$password_user3" \
   --variable blocked_name="blocked-move.txt" \
   --variable blocked_body="$MOVE_BLOCKED_BODY" \
   --variable name="move-target.txt" \
   --variable body="$MOVE_BODY" \
   --variable body_length="$(body_length "$MOVE_BODY")"

move_state=$(psql -X -v ON_ERROR_STOP=1 -At -F '|' -P null=NULL \
   -c "SELECT
         (SELECT file_id::text FROM files WHERE name = 'move-target.txt' AND drive_id = 1),
         (SELECT file_id::text FROM file_events WHERE event_type = 'moved_to_drive' AND file_name = 'move-target.txt' ORDER BY event_id DESC LIMIT 1),
         (SELECT coalesce(owner_user_id, 'NULL') FROM files WHERE name = 'move-target.txt' AND drive_id = 1),
         (SELECT coalesce(drive_id::text, 'NULL') FROM files WHERE name = 'move-target.txt' AND drive_id = 1),
         (SELECT count(*)::text FROM files WHERE name = 'move-target.txt');
      ")
IFS='|' read -r current_file_id event_file_id owner_id drive_value row_count <<EOF
$move_state
EOF
if [ "$current_file_id" != "$event_file_id" ] || [ "$owner_id" != "NULL" ] || [ "$drive_value" != "1" ] || [ "$row_count" != "1" ]; then
   echo "unexpected move state: $move_state"
   exit 1
fi

run_hurl spec/security.hurl \
   --variable user_id=user1 \
   --variable password="$password_user1" \
   --variable drive_id=2

echo "e2e ok"

# NCe31 compat specs (issue #2). These run last, after every native spec and
# verification step, so a compat failure can never mask a native result.
# The compat specs take {{host}} as a full base URL — a different convention
# from the native host+port variable pair. The six loginflow/ocs files are
# verbatim (issue #2); specs/dav/00_sliver_refusals.hurl is ours, pinning the
# sliver's refusal matrix until the issue #6 re-spec absorbs it.
echo "running specs/ NCe31 compat specs"
"$HURL" --test "$ROOT/specs/loginflow/00_flow_v2.hurl" \
   "$ROOT/specs/loginflow/01_errors.hurl" \
   "$ROOT/specs/ocs/00_current_user.hurl" \
   "$ROOT/specs/ocs/01_forbidden_and_headers.hurl" \
   "$ROOT/specs/ocs/02_no_auth.hurl" \
   "$ROOT/specs/ocs/03_getapppassword.hurl" \
   "$ROOT/specs/dav/00_sliver_refusals.hurl" \
   --variable host="http://$APP_HOST:$APP_PORT" \
   --variable fixture_password="$FIXTURE_PASSWORD"
