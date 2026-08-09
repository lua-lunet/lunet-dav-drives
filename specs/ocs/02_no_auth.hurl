# OCS with no credentials at all -> 401/997, not a 500.

GET {{host}}/ocs/v2.php/cloud/user?format=json
OCS-APIRequest: true
HTTP 401
[Asserts]
jsonpath "$.ocs.meta.statuscode" == 997

GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
HTTP 401
