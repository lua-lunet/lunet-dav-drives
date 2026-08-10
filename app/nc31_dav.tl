local crypto = require("app.crypto")
local db = require("app.db")
local http = require("app.http")

-- The DAV sliver the carried NCe31 specs touch (issue #2): PROPFIND with
-- Depth: 0 on the authenticated user's own files root, answered 207. Every
-- other DAV verb and path shape is a clean refusal per openapi/dav.yaml; the
-- full DAV re-spec is a deliberate follow-up, so nothing else is emulated.

local record Nc31Dav
end

-- SabreDAV-shaped error bodies (dav.yaml's DavError schema), with the
-- exception class SabreDAV would raise for the status.
local dav_exception: {integer: string} = {
   [401] = "Sabre\\DAV\\Exception\\NotAuthenticated",
   [403] = "Sabre\\DAV\\Exception\\Forbidden",
   [404] = "Sabre\\DAV\\Exception\\NotFound",
   [405] = "Sabre\\DAV\\Exception\\MethodNotAllowed",
   [409] = "Sabre\\DAV\\Exception\\Conflict",
}

local function dav_error(status: integer, msg: string): string
   local body = '<?xml version="1.0" encoding="utf-8"?>\n'
      .. '<d:error xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns">\n'
      .. '  <s:exception>' .. (dav_exception[status] or "Sabre\\DAV\\Exception") .. '</s:exception>\n'
      .. '  <s:message>' .. msg .. '</s:message>\n'
      .. '</d:error>\n'
   local headers: {string: string} = { ["Content-Type"] = "application/xml" }
   if status == 401 then
      headers["WWW-Authenticate"] = 'Basic realm="lunet-dav-drives"'
   end
   return http.response(status, headers, body)
end

-- App-password Basic auth returning the authenticated user_id. Same digest
-- scheme as the native API (app_passwords.secret_digest = sha256_hex(secret)),
-- duplicated here so the compat surface never imports app.api internals.
local function auth_user_id(req: http.Request): string
   local user_id, secret = http.decode_basic_auth(req.headers.authorization)
   if not user_id or not secret then
      return nil
   end
   local rows, err = db.query([[
      SELECT ap.user_id
      FROM app_passwords ap
      WHERE ap.user_id = $1
        AND ap.secret_digest = $2
      LIMIT 1
   ]], user_id, crypto.sha256_hex(secret))
   if err or not rows[1] then
      return nil
   end
   return tostring(rows[1].user_id)
end

-- The schema CHECK on user_id forbids only '/', so XML metacharacters
-- (<, &, quotes) are provisionable in principle. Escape everything emitted
-- rather than relying on provisioning hygiene.
local function xml_escape(s: string): string
   return (s:gsub("[&<>\"']", {
      ["&"] = "&amp;",
      ["<"] = "&lt;",
      [">"] = "&gt;",
      ['"'] = "&quot;",
      ["'"] = "&apos;",
   }))
end

-- Minimal Depth:0 collection answer: the root's own props only.
local function propfind_root(path: string, uid: string): string
   local body = '<?xml version="1.0" encoding="utf-8"?>\n'
      .. '<d:multistatus xmlns:d="DAV:">\n'
      .. '  <d:response>\n'
      .. '    <d:href>' .. xml_escape(path) .. '</d:href>\n'
      .. '    <d:propstat>\n'
      .. '      <d:prop>\n'
      .. '        <d:displayname>' .. xml_escape(uid) .. '</d:displayname>\n'
      .. '        <d:resourcetype><d:collection/></d:resourcetype>\n'
      .. '      </d:prop>\n'
      .. '      <d:status>HTTP/1.1 200 OK</d:status>\n'
      .. '    </d:propstat>\n'
      .. '  </d:response>\n'
      .. '</d:multistatus>\n'
   return http.response(207, { ["Content-Type"] = "application/xml" }, body)
end

-- Refusal order matches dav.yaml: MKCOL and COPY/MOVE are refused for
-- everyone (dav.yaml lists no 401 for them), deeper paths and unknown verbs
-- are 404, and only then does the PROPFIND root flow authenticate, check the
-- path uid against the auth uid (mismatch is 404 — never a leak), and refuse
-- any Depth other than "0".
function Nc31Dav.dispatch(req: http.Request): string
   if req.method == "MKCOL" then
      return dav_error(405, "MKCOL is not supported; drives are provisioned administratively")
   end
   if req.method == "COPY" or req.method == "MOVE" then
      return dav_error(409, req.method .. " is not supported")
   end
   local path = http.split_query(req.path)
   local uid = path:match("^/remote%.php/dav/files/([^/]+)/?$")
   if not uid then
      return dav_error(404, "Not found")
   end
   if req.method ~= "PROPFIND" then
      return dav_error(404, "Not found")
   end
   local auth_uid = auth_user_id(req)
   if not auth_uid then
      return dav_error(401, "Username or password was incorrect")
   end
   if uid ~= auth_uid then
      return dav_error(404, "Not found")
   end
   if http.header_value(req.headers, "depth") ~= "0" then
      return dav_error(403, "Only Depth: 0 is supported on this resource")
   end
   return propfind_root(path, uid)
end

return Nc31Dav
