GET http://{{host}}:{{port}}/v1/me
[BasicAuth]
user1: wrong

HTTP 401

GET http://{{host}}:{{port}}/v1/me
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
[Asserts]
jsonpath "$.user_id" == "{{user_id}}"
