PUT http://{{host}}:{{port}}/v1/personal/files/{{personal_name}}
Content-Type: text/plain
[BasicAuth]
{{owner_user_id}}: {{owner_password}}

`{{personal_body}}`

HTTP 201

DELETE http://{{host}}:{{port}}/v1/personal/files/{{personal_name}}
[BasicAuth]
{{owner_user_id}}: {{owner_password}}

HTTP 204

GET http://{{host}}:{{port}}/v1/personal/files/{{personal_name}}
[BasicAuth]
{{owner_user_id}}: {{owner_password}}

HTTP 404

GET http://{{host}}:{{port}}/v1/personal/files
[BasicAuth]
{{owner_user_id}}: {{owner_password}}

HTTP 200
[Asserts]
jsonpath "$.files" count == 0

PUT http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{drive_name}}
Content-Type: text/plain
[BasicAuth]
{{member_user_id}}: {{member_password}}

`{{drive_body}}`

HTTP 201

DELETE http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{drive_name}}
[BasicAuth]
{{non_member_user_id}}: {{non_member_password}}

HTTP 404

DELETE http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{drive_name}}
[BasicAuth]
{{member_user_id}}: {{member_password}}

HTTP 204

GET http://{{host}}:{{port}}/v1/drives/{{drive_id}}/files/{{drive_name}}
[BasicAuth]
{{member_user_id}}: {{member_password}}

HTTP 404
