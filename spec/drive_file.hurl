PUT http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
Content-Type: text/plain
[BasicAuth]
{{writer_user_id}}: {{writer_password}}

`{{body}}`

HTTP 201
[Asserts]
jsonpath "$.name" == "{{name}}"
jsonpath "$.revision" == 1

GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
[BasicAuth]
{{reader_user_id}}: {{reader_password}}

HTTP 200
Content-Type: text/plain
`{{body}}`

HEAD http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
[BasicAuth]
{{reader_user_id}}: {{reader_password}}

HTTP 200
[Asserts]
header "Content-Type" == "text/plain"
header "Content-Length" == "{{body_length}}"

GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files
[BasicAuth]
{{reader_user_id}}: {{reader_password}}

HTTP 200
[Asserts]
jsonpath "$.files[0].name" == "{{name}}"
jsonpath "$.files[0].revision" == 1

GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
[BasicAuth]
{{other_user_id}}: {{other_password}}

HTTP 404

PUT http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{name}}
Content-Type: text/plain
[BasicAuth]
{{other_user_id}}: {{other_password}}

`{{body}}`

HTTP 404
