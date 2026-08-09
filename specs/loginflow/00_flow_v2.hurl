# Login Flow v2 — full happy path against the pre-seeded fixture user u1.
# No chassis seeding: users are provisioned by specs/seed.sql, never by a
# client-facing registration endpoint.

# 1. Initiate — anonymous, no auth.
POST {{host}}/index.php/login/v2
HTTP 200
[Captures]
poll_token: jsonpath "$.poll.token"
login_token: jsonpath "$.login" regex "token=(.+)$"
[Asserts]
jsonpath "$.poll.token" exists
jsonpath "$.poll.endpoint" exists
jsonpath "$.login" exists

# 2. Poll before grant -> 404 (not completed yet).
POST {{host}}/login/v2/poll
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{poll_token}}
HTTP 404

# 3. User authenticates ("in browser") with their real user_id + real
# password — grants the pending login token.
POST {{host}}/login/v2/grant
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{login_token}}
loginName: u1
password: {{fixture_password}}
HTTP 200

# 4. Poll again -> 200, one-time body with the minted app password.
POST {{host}}/login/v2/poll
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{poll_token}}
HTTP 200
[Captures]
app_password: jsonpath "$.appPassword"
[Asserts]
jsonpath "$.loginName" == "u1"
jsonpath "$.appPassword" exists

# 5. Token is consumed: polling again -> 404.
POST {{host}}/login/v2/poll
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{poll_token}}
HTTP 404

# 6. The minted app password authenticates DAV as u1 (PROPFIND on root).
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 0
[BasicAuth]
u1: {{app_password}}
HTTP 207
