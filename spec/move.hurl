PUT http://{{host}}:{{port}}/v1/personal/files/{{blocked_name}}
Content-Type: text/plain
[BasicAuth]
{{user_id}}: {{password}}

`{{blocked_body}}`

HTTP 201

POST http://{{host}}:{{port}}/v1/personal/files/{{blocked_name}}/move-to-drive
Content-Type: application/json
[BasicAuth]
{{user_id}}: {{password}}

{"drive_id":"{{forbidden_drive_id}}"}

HTTP 404

PUT http://{{host}}:{{port}}/v1/personal/files/{{name}}
Content-Type: text/plain
[BasicAuth]
{{user_id}}: {{password}}

`{{body}}`

HTTP 201
[Asserts]
jsonpath "$.name" == "{{name}}"
jsonpath "$.revision" == 1

POST http://{{host}}:{{port}}/v1/personal/files/{{name}}/move-to-drive
Content-Type: application/json
[BasicAuth]
{{user_id}}: {{password}}

{"drive_id":"{{drive_id}}"}

HTTP 200
[Asserts]
jsonpath "$.name" == "{{name}}"

GET http://{{host}}:{{port}}/v1/personal/files/{{name}}
[BasicAuth]
{{user_id}}: {{password}}

HTTP 404

GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
[BasicAuth]
{{reader_user_id}}: {{reader_password}}

HTTP 200
Content-Type: text/plain
[Asserts]
header "Content-Length" == "{{body_length}}"

GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
[BasicAuth]
{{other_user_id}}: {{other_password}}

HTTP 404
