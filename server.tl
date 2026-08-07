local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. here .. "/?/init.lua;" .. package.path

local lunet = require("lunet")
local socket = require("lunet.socket")
local json = require("lunet.jsonic")

local crypto = require("app.crypto")
local db = require("app.db")
local hello = require("app.hello")
local http = require("app.http")

local function json_body(status: integer, value: any): string
   return http.response(status, { ["Content-Type"] = "application/json" }, json.encode(value))
end

local function text_body(status: integer, body: string): string
   return http.response(status, { ["Content-Type"] = "text/plain" }, body)
end

local function unauthorized(): string
   return http.response(
      401,
      { ["WWW-Authenticate"] = 'Basic realm="lunet-dav-drives"' },
      "Unauthorized")
end

local record User
   user_id: string
   email: string
   display_name: string
end

local function auth_user(req: http.Request): User
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

local function handle_health(): string
   return json_body(200, { ok = true })
end

-- Tracer-round route. Delete alongside app/hello.tl and the hello_tracer table.
local function handle_hello(): string
   local rows, err = db.query("SELECT subject FROM hello_tracer ORDER BY id LIMIT 1")
   if err then
      return text_body(500, err)
   end
   if not rows[1] then
      return text_body(500, "hello_tracer is empty")
   end
   return json_body(200, { message = hello.greeting(tostring(rows[1].subject)) })
end

local function handle_me(req: http.Request): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   return json_body(200, {
      user_id = user.user_id,
      display_name = user.display_name,
      email = user.email,
   })
end

local function handle_drives(req: http.Request): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local rows, err = db.query([[
      SELECT d.drive_id, d.drive_name
      FROM drives d
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
      ORDER BY d.drive_id
   ]], user.user_id)
   if err then
      return text_body(500, err)
   end
   local drives: {{string: string}} = {}
   for i = 1, #rows do
      drives[i] = {
         drive_id = tostring(rows[i].drive_id),
         name = tostring(rows[i].drive_name),
      }
   end
   return json_body(200, { drives = drives })
end

local function handle_drive(req: http.Request, drive_id: string): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local rows, err = db.query([[
      SELECT d.drive_id, d.drive_name
      FROM drives d
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
      LIMIT 1
   ]], user.user_id, drive_id)
   if err then
      return text_body(500, err)
   end
   if not rows[1] then
      return text_body(404, "Not found")
   end
   return json_body(200, {
      drive_id = tostring(rows[1].drive_id),
      name = tostring(rows[1].drive_name),
   })
end

local function dispatch(req: http.Request): string
   if req.method == "GET" and req.path == "/health" then
      return handle_health()
   end
   if req.method == "GET" and req.path == "/hello" then
      return handle_hello()
   end
   if req.method == "GET" and req.path == "/v1/me" then
      return handle_me(req)
   end
   if req.method == "GET" and req.path == "/v1/drives" then
      return handle_drives(req)
   end
   local drive_id = req.path:match("^/v1/drives/([^/]+)$")
   if drive_id and req.method == "GET" then
      return handle_drive(req, drive_id)
   end
   return text_body(404, "Not found")
end

local host = os.getenv("APP_HOST") or "127.0.0.1"
local port = tonumber(os.getenv("APP_PORT") or "8081") as integer

lunet.spawn(function()
   local listener, err = socket.listen("tcp", host, port)
   if not listener then
      io.stderr:write("failed to listen: " .. tostring(err) .. "\n")
      return
   end
   io.stderr:write("lunet-dav-drives listening on http://" .. host .. ":" .. tostring(port) .. "\n")
   while true do
      local client = socket.accept(listener)
      if client then
         lunet.spawn(function()
            local raw = socket.read(client)
            if not raw then
               socket.close(client)
               return
            end
            local req, parse_err = http.parse_request(raw)
            if not req then
               socket.write(client, text_body(400, parse_err))
            else
               socket.write(client, dispatch(req))
            end
            socket.close(client)
         end)
      end
   end
end)
