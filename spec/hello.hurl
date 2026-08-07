# Tracer-round spec.
#
# The subject variable is the value the e2e script seeded into hello_tracer, so
# a pass proves the value travelled Postgres -> Lunet server -> HTTP response.
# Delete alongside app/hello.tl and the /hello route.

GET http://{{host}}:{{port}}/hello

HTTP 200
[Asserts]
header "Content-Type" == "application/json"
jsonpath "$.message" == "hello {{subject}}"
