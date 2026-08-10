# DAV sliver — refusal matrix. The carried auth/OCS specs (issue #2) exercise
# only the PROPFIND Depth: 0 happy path; this spec pins the sliver's clean
# refusals so they are proven, not just advertised. The full team-folders DAV
# re-spec is issue #6; whatever lands there absorbs or replaces this file.

# Mint a credential via the OCS provisioning route (real password in).
GET {{host}}/ocs/v2.php/core/getapppassword?format=json
OCS-APIRequest: true
[BasicAuth]
u1: {{fixture_password}}
HTTP 200
[Captures]
app_password: jsonpath "$.ocs.data.apppassword"

# Control: the one implemented DAV route. PROPFIND Depth: 0 on own root -> 207.
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 0
[BasicAuth]
u1: {{app_password}}
HTTP 207

# Unauthenticated PROPFIND -> 401 with a WWW-Authenticate challenge.
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 0
HTTP 401
[Asserts]
header "WWW-Authenticate" exists

# Wrong app password -> 401.
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 0
[BasicAuth]
u1: not-the-app-password
HTTP 401

# Path user != authenticated user -> 404, never 403 (no existence leak).
PROPFIND {{host}}/remote.php/dav/files/u2/
Depth: 0
[BasicAuth]
u1: {{app_password}}
HTTP 404

# Depth: 1 is refused on the sliver -> 403.
PROPFIND {{host}}/remote.php/dav/files/u1/
Depth: 1
[BasicAuth]
u1: {{app_password}}
HTTP 403

# Drives are admin-provisioned, never client-created: MKCOL -> 405.
MKCOL {{host}}/remote.php/dav/files/u1/newdrive/
[BasicAuth]
u1: {{app_password}}
HTTP 405

# COPY -> 409 (unsupported).
COPY {{host}}/remote.php/dav/files/u1/a.txt
[BasicAuth]
u1: {{app_password}}
HTTP 409

# MOVE -> 409 (same-location rename arrives with the issue #6 re-spec).
MOVE {{host}}/remote.php/dav/files/u1/a.txt
[BasicAuth]
u1: {{app_password}}
HTTP 409

# Nothing exists below the root yet: deeper paths -> 404.
PROPFIND {{host}}/remote.php/dav/files/u1/anything/
Depth: 0
[BasicAuth]
u1: {{app_password}}
HTTP 404

# GET is not part of the sliver -> 404.
GET {{host}}/remote.php/dav/files/u1/
[BasicAuth]
u1: {{app_password}}
HTTP 404

# Non-files /remote.php/ paths -> 404.
PROPFIND {{host}}/remote.php/webdav
Depth: 0
[BasicAuth]
u1: {{app_password}}
HTTP 404
