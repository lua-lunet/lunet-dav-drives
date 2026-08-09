# OCS header contract and cross-user forbidden case.

GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{fixture_password}}
HTTP 200
[Captures]
app_password: jsonpath "$.ocs.data.apppassword"

# Missing OCS-APIRequest header -> 401/997, even with valid credentials.
GET {{host}}/ocs/v2.php/cloud/user?format=json
[BasicAuth]
u1: {{app_password}}
HTTP 401
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 997

# Missing format=json -> 400/998.
GET {{host}}/ocs/v2.php/cloud/user
OCS-APIRequest: true
[BasicAuth]
u1: {{app_password}}
HTTP 400
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 998

# Wrong app password -> 401/997.
GET {{host}}/ocs/v2.php/cloud/user?format=json
OCS-APIRequest: true
[BasicAuth]
u1: wrong-app-password
HTTP 401
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 997

# Requesting another user's /cloud/users/{id} -> 403 (existence is not
# leaked either way; both a real other user and a fictitious one are 403/404
# consistently — this endpoint always refuses cross-identity reads).
GET {{host}}/ocs/v2.php/cloud/users/u2?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{app_password}}
HTTP 403
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 403
