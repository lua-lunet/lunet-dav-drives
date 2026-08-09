# Login Flow v2 — error cases.

# Unknown poll token -> 404.
POST {{host}}/login/v2/poll
Content-Type: application/x-www-form-urlencoded
[Form]
token: not-a-real-token
HTTP 404

# Unknown login token on grant -> 404.
POST {{host}}/login/v2/grant
Content-Type: application/x-www-form-urlencoded
[Form]
token: not-a-real-token
loginName: u1
password: {{fixture_password}}
HTTP 404

# Grant with the wrong real password -> 401 (not granted; polling keeps 404ing).
POST {{host}}/index.php/login/v2
HTTP 200
[Captures]
poll_token: jsonpath "$.poll.token"
login_token: jsonpath "$.login" regex "token=(.+)$"

POST {{host}}/login/v2/grant
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{login_token}}
loginName: u1
password: wrong-real-password
HTTP 401

POST {{host}}/login/v2/poll
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{poll_token}}
HTTP 404

# Grant naming a nonexistent user -> 401 (same as wrong password; no existence leak).
POST {{host}}/index.php/login/v2
HTTP 200
[Captures]
login_token2: jsonpath "$.login" regex "token=(.+)$"

POST {{host}}/login/v2/grant
Content-Type: application/x-www-form-urlencoded
[Form]
token: {{login_token2}}
loginName: no-such-user
password: {{fixture_password}}
HTTP 401
