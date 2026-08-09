PUT http://{{host}}:{{port}}/v1/personal/files/{{name}}
Content-Type: text/plain
[BasicAuth]
{{user_id}}: {{password}}

`{{body}}`

HTTP 201
[Asserts]
header "Content-Type" == "application/json"
jsonpath "$.name" == "{{name}}"
jsonpath "$.revision" == 1

GET http://{{host}}:{{port}}/v1/personal/files/{{name}}
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
Content-Type: text/plain
`{{body}}`

HEAD http://{{host}}:{{port}}/v1/personal/files/{{name}}
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
[Asserts]
header "Content-Type" == "text/plain"
header "Content-Length" == "{{body_length}}"

GET http://{{host}}:{{port}}/v1/personal/files
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
[Asserts]
jsonpath "$.files[0].name" == "{{name}}"
jsonpath "$.files[0].revision" == 1

GET http://{{host}}:{{port}}/v1/personal/files/{{name}}
[BasicAuth]
{{other_user_id}}: {{other_password}}

HTTP 404
