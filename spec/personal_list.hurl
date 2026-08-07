GET http://{{host}}:{{port}}/v1/personal/files
[BasicAuth]
{{user_id}}: {{password}}

HTTP 200
[Asserts]
header "Content-Type" == "application/json"
jsonpath "$.files" count == 0
