local lunet_json = require("lunet.jsonic")

local crypto = require("app.crypto")
local dav = require("app.nc31_dav")
local db = require("app.db")
local http = require("app.http")

-- NCe31 work-alike compat surface (issue #2): Login Flow v2 and the OCS
-- user/app-password endpoints, plus dispatch into the DAV sliver. The native
-- API (app.api) is untouched; server.tl splits on path prefix. WORKALIKE, NOT
-- A CLONE: anything outside openapi/auth.yaml + openapi/dav.yaml gets a clean
-- refusal, never emulated complexity.

local record Nc31
end

-- A login flow is initiated anonymously, granted with the real account
-- password, and collected exactly once by polling. Flows are ephemeral
-- NC-style ~20 minute state in a module-level table: the server is
-- single-process, and a restart simply voids pending flows (the client
-- restarts the flow).
local record Flow
   state: string
   expires_at: integer
   base: string
   user_id: string
   app_password: string
end

local flows: {string: Flow} = {}

local FLOW_TTL_SECONDS <const> = 1200
local APP_PASSWORD_CAP <const> = 24

local record AuthUser
   user_id: string
   email: string
   display_name: string
end

local function json_response(status: integer, value: any): string
   return http.response(status, { ["Content-Type"] = "application/json" }, lunet_json.encode(value))
end

local function message(status: integer, text: string): string
   return json_response(status, { message = text })
end

local function method_not_allowed(): string
   return message(405, "Method not allowed")
end

-- OCS envelope per auth.yaml. Failures carry status "failure" and a JSON null
-- data member; successes carry status "ok" and statuscode 200.
local function ocs_response(http_status: integer, statuscode: integer, msg: string, data: any): string
   return json_response(http_status, {
      ocs = {
         meta = {
            status = statuscode == 200 and "ok" or "failure",
            statuscode = statuscode,
            message = msg,
            totalitems = "",
            itemsperpage = "",
         },
         data = data,
      },
   })
end

local function ocs_failure(http_status: integer, statuscode: integer, msg: string): string
   return ocs_response(http_status, statuscode, msg, lunet_json.null)
end

-- App-password Basic auth: the native digest scheme
-- (app_passwords.secret_digest = sha256_hex(secret)). Deliberately duplicated
-- from app.api's auth_user rather than imported: the native module stays
-- untouched and the two surfaces evolve independently.
local function auth_app_password(req: http.Request): AuthUser
   local user_id, secret = http.decode_basic_auth(req.headers.authorization)
   if not user_id or not secret then
      return nil
   end
   local rows, err = db.query([[
      SELECT u.user_id, u.email, u.display_name
      FROM users u
      JOIN app_passwords ap ON ap.user_id = u.user_id
      WHERE u.user_id = $1
        AND ap.secret_digest = $2
      LIMIT 1
   ]], user_id, crypto.sha256_hex(secret))
   if err or not rows[1] then
      return nil
   end
   local row = rows[1]
   return {
      user_id = tostring(row.user_id),
      email = tostring(row.email),
      display_name = tostring(row.display_name),
   }
end

-- Real-account-password check against users.password_digest (Argon2id). A
-- NULL digest never matches, and an unknown user is indistinguishable from a
-- wrong password: no existence leak.
local function verify_real_password(login_name: string, password: string): boolean
   local rows, err = db.query(
      "SELECT password_digest FROM users WHERE user_id = $1 LIMIT 1", login_name)
   if err or not rows[1] then
      return false
   end
   local digest = rows[1].password_digest
   if type(digest) ~= "string" then
      return false
   end
   return crypto.argon2id_verify(digest as string, password)
end

local function auth_real_password(req: http.Request): string
   local user_id, password = http.decode_basic_auth(req.headers.authorization)
   if not user_id or not password then
      return nil
   end
   if not verify_real_password(user_id, password) then
      return nil
   end
   return user_id
end

local function app_password_count(user_id: string): integer
   local rows, err = db.query(
      "SELECT COUNT(*) AS n FROM app_passwords WHERE user_id = $1", user_id)
   if err or not rows[1] then
      return 0
   end
   return (tonumber(rows[1].n) or 0) as integer
end

-- Mint-at-grant semantics: the row is inserted immediately, so the credential
-- is valid from that moment and every mint is a NEW credential (no rotation).
local function mint_app_password(user_id: string, name: string): string, string
   local secret = crypto.random_hex(32)
   local ok, err = db.exec(
      "INSERT INTO app_passwords (user_id, name, secret_digest) VALUES ($1, $2, $3)",
      user_id, name, crypto.sha256_hex(secret))
   if not ok then
      return nil, err
   end
   return secret
end

local function flow_get(token: string): Flow
   if not token or token == "" then
      return nil
   end
   local flow = flows[token]
   if not flow then
      return nil
   end
   if flow.expires_at <= os.time() then
      flows[token] = nil
      return nil
   end
   return flow
end

-- POST /index.php/login/v2 — anonymous initiate.
local function handle_login_init(req: http.Request): string
   local token = crypto.random_hex(32)
   local base = "http://" .. (req.headers.host or "localhost")
   flows[token] = {
      state = "pending",
      expires_at = os.time() + FLOW_TTL_SECONDS,
      base = base,
      user_id = "",
      app_password = "",
   }
   return json_response(200, {
      poll = {
         token = token,
         endpoint = base .. "/login/v2/poll",
      },
      login = base .. "/login/v2/grant?token=" .. token,
   })
end

-- POST /login/v2/grant — the browser step. Unknown, expired, and
-- already-granted tokens are the same 404; unknown user and wrong password
-- are the same 401; the per-user app-password cap is 403.
local function handle_login_grant(req: http.Request): string
   local form = http.parse_form(req.body or "")
   local flow = flow_get(form.token)
   if not flow or flow.state ~= "pending" then
      return message(404, "Unknown or expired login token")
   end
   local login_name = form.loginName or ""
   if not verify_real_password(login_name, form.password or "") then
      return message(401, "Unknown user or wrong password")
   end
   if app_password_count(login_name) >= APP_PASSWORD_CAP then
      return message(403, "App password limit reached")
   end
   local secret, err = mint_app_password(login_name, "loginflow")
   if not secret then
      return message(500, err or "failed to mint app password")
   end
   flow.state = "granted"
   flow.user_id = login_name
   flow.app_password = secret
   return json_response(200, { granted = true })
end

-- POST /login/v2/poll — one-time pickup. Pending, unknown, expired, and
-- already-collected tokens are the same 404, per the contract.
local function handle_login_poll(req: http.Request): string
   local form = http.parse_form(req.body or "")
   local token = form.token or ""
   local flow = flow_get(token)
   if not flow or flow.state ~= "granted" then
      return message(404, "Login flow has not completed")
   end
   local body = {
      server = flow.base,
      loginName = flow.user_id,
      appPassword = flow.app_password,
   }
   flows[token] = nil
   return json_response(200, body)
end

-- Personal blob bytes only (owner_user_id = the user), for the quota block.
local function used_bytes(user_id: string): integer
   local rows, err = db.query([[
      SELECT COALESCE(SUM(b.size), 0) AS used
      FROM files f
      JOIN blobs b ON b.blob_id = f.blob_id
      WHERE f.owner_user_id = $1
   ]], user_id)
   if err or not rows[1] then
      return 0
   end
   return (tonumber(rows[1].used) or 0) as integer
end

local function user_data(user: AuthUser): {string: any}
   return {
      id = user.user_id,
      ["display-name"] = user.display_name,
      email = user.email,
      enabled = true,
      quota = {
         quota = -3,
         used = used_bytes(user.user_id),
         free = -3,
         total = -3,
         relative = 0,
      },
   }
end

-- Shared cloud/user gate, ordered per the contract: a missing OCS-APIRequest
-- header and failed app-password auth collapse into the same 401/997, and
-- only then is format checked (400/998).
local function ocs_app_password_user(req: http.Request, query: string): AuthUser, string
   local user: AuthUser = nil
   if http.header_value(req.headers, "OCS-APIRequest") == "true" then
      user = auth_app_password(req)
   end
   if not user then
      return nil, ocs_failure(401, 997, "Unauthorized")
   end
   if http.parse_form(query).format ~= "json" then
      return nil, ocs_failure(400, 998, "format must be json")
   end
   return user, nil
end

-- GET /ocs/v2.php/cloud/user
local function handle_ocs_current_user(req: http.Request, query: string): string
   local user, refusal = ocs_app_password_user(req, query)
   if not user then
      return refusal
   end
   return ocs_response(200, 200, "OK", user_data(user))
end

-- GET /ocs/v2.php/cloud/users/{id} — self-read only; any other id is a real
-- 403/403 (this is not a path-identity DAV route).
local function handle_ocs_user_by_id(req: http.Request, query: string, path_user_id: string): string
   local user, refusal = ocs_app_password_user(req, query)
   if not user then
      return refusal
   end
   if path_user_id ~= user.user_id then
      return ocs_failure(403, 403, "Forbidden")
   end
   return ocs_response(200, 200, "OK", user_data(user))
end

-- GET /ocs/v2.php/core/getapppassword — real password in, NEW app password
-- out; existing credentials stay valid. Unlike cloud/user, a missing
-- OCS-APIRequest header is 403/997 here (NCe31 dialect, specs/ocs/03).
local function handle_getapppassword(req: http.Request, query: string): string
   if http.header_value(req.headers, "OCS-APIRequest") ~= "true" then
      return ocs_failure(403, 997, "OCS-APIRequest header required")
   end
   local user_id = auth_real_password(req)
   if not user_id then
      return ocs_failure(401, 997, "Unauthorized")
   end
   if http.parse_form(query).format ~= "json" then
      return ocs_failure(400, 998, "format must be json")
   end
   if app_password_count(user_id) >= APP_PASSWORD_CAP then
      return ocs_failure(403, 999, "App password limit reached")
   end
   local secret, err = mint_app_password(user_id, "ocs-getapppassword")
   if not secret then
      return ocs_failure(500, 500, err or "failed to mint app password")
   end
   return ocs_response(200, 200, "OK", { apppassword = secret })
end

local function has_prefix(path: string, prefix: string): boolean
   return path:sub(1, #prefix) == prefix
end

-- The compat prefix set. Checked against the raw request-target; the query
-- string never disturbs a prefix match.
function Nc31.handles(path: string): boolean
   return has_prefix(path, "/index.php/login/")
      or has_prefix(path, "/login/v2/")
      or has_prefix(path, "/ocs/")
      or has_prefix(path, "/remote.php/")
end

function Nc31.dispatch(req: http.Request): string
   local path, query = http.split_query(req.path)
   if has_prefix(path, "/remote.php/") then
      return dav.dispatch(req)
   end
   if path == "/index.php/login/v2" then
      if req.method ~= "POST" then
         return method_not_allowed()
      end
      return handle_login_init(req)
   end
   if path == "/login/v2/grant" then
      if req.method ~= "POST" then
         return method_not_allowed()
      end
      return handle_login_grant(req)
   end
   if path == "/login/v2/poll" then
      if req.method ~= "POST" then
         return method_not_allowed()
      end
      return handle_login_poll(req)
   end
   if path == "/ocs/v2.php/cloud/user" then
      if req.method ~= "GET" then
         return method_not_allowed()
      end
      return handle_ocs_current_user(req, query)
   end
   local ocs_user_id = path:match("^/ocs/v2%.php/cloud/users/([^/]+)$")
   if ocs_user_id then
      if req.method ~= "GET" then
         return method_not_allowed()
      end
      return handle_ocs_user_by_id(req, query, ocs_user_id)
   end
   if path == "/ocs/v2.php/core/getapppassword" then
      if req.method ~= "GET" then
         return method_not_allowed()
      end
      return handle_getapppassword(req, query)
   end
   return message(404, "Not found")
end

return Nc31
