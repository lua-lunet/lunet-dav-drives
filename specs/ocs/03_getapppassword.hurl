# App-password provisioning via GET /ocs/v2.php/core/getapppassword.
#
# Laws covered:
#   - real account password in (Basic auth on the provisioning call) -> one-time
#     `apppassword` out (exact key, camelCase variant rejected by the client).
#   - each call mints a NEW credential; existing credentials stay valid.
#   - the minted credential authenticates both DAV and OCS routes.
#   - missing Basic auth -> 401; wrong real password -> 401; missing
#     OCS-APIRequest header -> OCS error.

# Happy path: mint password A.
GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{fixture_password}}
HTTP 200
[Captures]
app_password_a: jsonpath "$.ocs.data.apppassword"
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 200
jsonpath "$.ocs.data.apppassword" isString

# Mint password B — must differ from A, and A must stay valid.
GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{fixture_password}}
HTTP 200
[Captures]
app_password_b: jsonpath "$.ocs.data.apppassword"
[Asserts]
jsonpath "$.ocs.data.apppassword" != "{{app_password_a}}"

# A still authenticates DAV (PROPFIND on the personal root).
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 0
[BasicAuth]
u1: {{app_password_a}}
HTTP 207

# B authenticates DAV too — creating B did not revoke A.
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 0
[BasicAuth]
u1: {{app_password_b}}
HTTP 207

# B authenticates an OCS route (current user).
GET {{host}}/ocs/v2.php/cloud/user?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{app_password_b}}
HTTP 200
[Asserts]
jsonpath "$.ocs.data.id" == "u1"

# Missing Basic auth -> 401 (no apppassword minted, no existence leak).
GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
HTTP 401

# Wrong real password -> 401.
GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
[BasicAuth]
u1: definitely-not-the-fixture-password
HTTP 401

# Missing OCS-APIRequest header -> OCS error (997 / 403 per NCe31 dialect).
GET {{host}}/ocs/v2.php/core/getapppassword?format=json
[BasicAuth]
u1: {{fixture_password}}
HTTP 403
