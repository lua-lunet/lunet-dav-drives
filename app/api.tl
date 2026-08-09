local lunet_json = require("lunet.jsonic")

local crypto = require("app.crypto")
local db = require("app.db")
local files = require("app.files")
local http = require("app.http")

local record Api
end

local record User
   user_id: string
   email: string
   display_name: string
end

local function json_body(status: integer, value: any): string
   return http.response(status, { ["Content-Type"] = "application/json" }, lunet_json.encode(value))
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

local function not_found(): string
   return text_body(404, "Not found")
end

local function bad_request(message: string): string
   return text_body(400, message)
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

local function file_response(row: table, is_head: boolean): string
   local headers = files.response_headers(row)
   if is_head then
      return http.response(200, headers, "")
   end
   return http.response(200, headers, tostring(row.body or ""))
end

local function json_file_response(status: integer, row: table): string
   return json_body(status, {
      file_id = row.file_id,
      name = row.name,
      revision = row.revision,
      mime_type = row.mime_type,
      etag = row.etag,
   })
end

local function handle_health(): string
   return json_body(200, { ok = true })
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
   local drives = {}
   for i = 1, #rows do
      drives[i] = {
         drive_id = tostring(rows[i].drive_id),
         name = tostring(rows[i].drive_name),
      }
   end
   return json_body(200, { drives = drives })
end

local function handle_drive_detail(req: http.Request, drive_id: string): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local row, err = files.get_drive_info(user.user_id, drive_id)
   if err then
      return not_found()
   end
   return json_body(200, {
      drive_id = tostring(row.drive_id),
      name = tostring(row.drive_name),
   })
end

local function handle_drive_files(req: http.Request, drive_id: string): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local rows, err = files.list_drive(user.user_id, drive_id)
   if err then
      return not_found()
   end
   local out = {}
   for i = 1, #rows do
      out[i] = files.summary_from_row(rows[i])
   end
   return json_body(200, { files = out })
end

local function handle_personal_files(req: http.Request): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local rows, err = files.list_personal(user.user_id)
   if err then
      return text_body(500, err)
   end
   local out = {}
   for i = 1, #rows do
      out[i] = files.summary_from_row(rows[i])
   end
   return json_body(200, { files = out })
end

local function handle_personal_file(req: http.Request, name: string): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local decoded, decode_err = http.decode_path_segment(name)
   if not decoded then
      return bad_request(decode_err)
   end
   if req.method == "GET" then
      local row, err = files.get_personal(user.user_id, decoded)
      if err then
         return not_found()
      end
      return file_response(row, false)
   end
   if req.method == "HEAD" then
      local row, err = files.head_personal(user.user_id, decoded)
      if err then
         return not_found()
      end
      return file_response(row, true)
   end
   if req.method == "PUT" then
      local row, err = files.put_personal(user.user_id, decoded, req.body or "", http.header_value(req.headers, "content-type") or "application/octet-stream")
      if err then
         if err == "slash in name" or err == "empty name" then
            return bad_request(err)
         end
         return text_body(500, err)
      end
      return json_file_response(row.created and 201 or 200, row)
   end
   if req.method == "DELETE" then
      local ok, err = files.delete_personal(user.user_id, decoded)
      if not ok then
         if err == "slash in name" or err == "empty name" then
            return bad_request(err)
         end
         return not_found()
      end
      return http.response(204, {}, "")
   end
   return text_body(405, "Method Not Allowed")
end

local function handle_drive_file(req: http.Request, drive_id: string, name: string): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local decoded, decode_err = http.decode_path_segment(name)
   if not decoded then
      return bad_request(decode_err)
   end
   if req.method == "GET" then
      local row, err = files.get_drive_file(user.user_id, drive_id, decoded)
      if err then
         return not_found()
      end
      return file_response(row, false)
   end
   if req.method == "HEAD" then
      local row, err = files.head_drive(user.user_id, drive_id, decoded)
      if err then
         return not_found()
      end
      return file_response(row, true)
   end
   if req.method == "PUT" then
      local row, err = files.put_drive(user.user_id, drive_id, decoded, req.body or "", http.header_value(req.headers, "content-type") or "application/octet-stream")
      if err then
         if err == "slash in name" or err == "empty name" then
            return bad_request(err)
         end
         return not_found()
      end
      return json_file_response(row.created and 201 or 200, row)
   end
   if req.method == "DELETE" then
      local ok, err = files.delete_drive(user.user_id, drive_id, decoded)
      if not ok then
         if err == "slash in name" or err == "empty name" then
            return bad_request(err)
         end
         return not_found()
      end
      return http.response(204, {}, "")
   end
   return text_body(405, "Method Not Allowed")
end

local function handle_move_to_drive(req: http.Request, name: string): string
   local user = auth_user(req)
   if not user then
      return unauthorized()
   end
   local decoded, decode_err = http.decode_path_segment(name)
   if not decoded then
      return bad_request(decode_err)
   end
   local payload = lunet_json.decode(req.body or "") as {string: any}
   if not payload or type(payload) ~= "table" or not payload.drive_id then
      return bad_request("missing drive_id")
   end
   local target_name = payload.name
   local row, err = files.move_personal_to_drive(user.user_id, decoded, tostring(payload.drive_id), target_name and tostring(target_name) or nil)
   if err then
      if err == "slash in name" or err == "empty name" or err == "invalid percent-encoding" then
         return bad_request(err)
      end
      if err == "destination name occupied" then
         return text_body(409, err)
      end
      return not_found()
   end
   return json_body(200, row)
end

function Api.dispatch(req: http.Request): string
   if req.method == "GET" and req.path == "/health" then
      return handle_health()
   end
   if req.method == "GET" and req.path == "/v1/me" then
      return handle_me(req)
   end
   if req.method == "GET" and req.path == "/v1/drives" then
      return handle_drives(req)
   end
   local drive_id = req.path:match("^/v1/drives/([^/]+)$")
   if drive_id and (req.method == "GET") then
      return handle_drive_detail(req, drive_id)
   end
   local drive_files_id = req.path:match("^/v1/drives/([^/]+)/files$")
   if drive_files_id and req.method == "GET" then
      return handle_drive_files(req, drive_files_id)
   end
   local drive_file_id, drive_file_name = req.path:match("^/v1/drives/([^/]+)/files/([^/]+)$")
   if drive_file_id and drive_file_name then
      return handle_drive_file(req, drive_file_id, drive_file_name)
   end
   if req.method == "GET" and req.path == "/v1/personal/files" then
      return handle_personal_files(req)
   end
   local move_name = req.path:match("^/v1/personal/files/([^/]+)/move%-to%-drive$")
   if move_name and req.method == "POST" then
      return handle_move_to_drive(req, move_name)
   end
   local personal_name = req.path:match("^/v1/personal/files/([^/]+)$")
   if personal_name then
      return handle_personal_file(req, personal_name)
   end
   return not_found()
end

return Api
