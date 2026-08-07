GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
[Asserts]
header "Content-Type" == "application/json"
jsonpath "$.drive_id" == "{{drive_id}}"
jsonpath "$.name" == "{{drive_name}}"

GET http://{{host}}:{{port}}/v1/drives/{{forbidden_drive_id}}
[BasicAuth]
{{user_id}}: {{password}}

HTTP 404
