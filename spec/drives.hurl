GET http://{{host}}:{{port}}/v1/drives
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
[Asserts]
header "Content-Type" == "application/json"
jsonpath "$.drives[0].drive_id" == "{{drive_id_1}}"
jsonpath "$.drives[0].name" == "{{drive_name_1}}"
