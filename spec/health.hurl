GET http://{{host}}:{{port}}/health

HTTP 200
[Asserts]
jsonpath "$.ok" == true
