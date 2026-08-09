# OCS current-user endpoint — identity is user_id (the stable login
# identity), never email.

GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{fixture_password}}
HTTP 200
[Captures]
app_password: jsonpath "$.ocs.data.apppassword"

GET {{host}}/ocs/v2.php/cloud/user?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{app_password}}
HTTP 200
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 200
jsonpath "$.ocs.data.id" == "u1"
jsonpath "$.ocs.data.email" exists
jsonpath "$.ocs.data.enabled" == true

# /cloud/users/{id} for one's own id -> 200, same data.
GET {{host}}/ocs/v2.php/cloud/users/u1?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{app_password}}
HTTP 200
[Asserts]
jsonpath "$.ocs.data.id" == "u1"
