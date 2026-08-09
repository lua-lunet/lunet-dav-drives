local crypto = require("app.crypto")

local record Http
   record Request
      method: string
      path: string
      version: string
      headers: {string: string}
      body: string
   end
end

local status_text: {integer: string} = {
   [200] = "OK",
   [201] = "Created",
   [204] = "No Content",
   [207] = "Multi-Status",
   [400] = "Bad Request",
   [401] = "Unauthorized",
   [403] = "Forbidden",
   [404] = "Not Found",
   [405] = "Method Not Allowed",
   [409] = "Conflict",
   [412] = "Precondition Failed",
   [500] = "Internal Server Error",
}

function Http.parse_request(raw: string): Http.Request, string
   local head, body = raw:match("^(.-)\r\n\r\n(.*)$")
   if not head then
      return nil, "malformed request"
   end
   local lines: {string} = {}
   for line in (head .. "\r\n"):gmatch("(.-)\r\n") do
      lines[#lines + 1] = line
   end
   local method, path, version = lines[1]:match("^(%S+)%s+(%S+)%s+(%S+)$")
   if not method then
      return nil, "bad request line"
   end
   local headers: {string: string} = {}
   for i = 2, #lines do
      local key, value = lines[i]:match("^([^:]+):%s*(.*)$")
      if key then
         headers[key:lower()] = value
      end
   end
   return {
      method = method,
      path = path,
      version = version,
      headers = headers,
      body = body or "",
   }
end

function Http.decode_basic_auth(header: string): string, string
   if not header then
      return nil
   end
   local scheme, token = header:match("^(%S+)%s+(.+)$")
   if not scheme or scheme:lower() ~= "basic" then
      return nil
   end
   local decoded = crypto.base64_decode(token)
   if not decoded then
      return nil
   end
   local user, secret = decoded:match("^([^:]+):(.*)$")
   if not user then
      return nil
   end
   return user, secret
end

function Http.header_value(headers: {string: string}, name: string): string
   if not headers then
      return nil
   end
   return headers[name:lower()]
end

function Http.decode_path_segment(segment: string): string, string
   if not segment then
      return nil, "missing path segment"
   end
   local out = {}
   local i = 1
   while i <= #segment do
      local c = segment:sub(i, i)
      if c == "%" then
         local hex = segment:sub(i + 1, i + 2)
         if #hex < 2 or not hex:match("^[0-9a-fA-F][0-9a-fA-F]$") then
            return nil, "invalid percent-encoding"
         end
         out[#out + 1] = string.char(tonumber(hex, 16) as integer)
         i = i + 3
      else
         out[#out + 1] = c
         i = i + 1
      end
   end
   return table.concat(out)
end

-- parse_request keeps the full request-target in req.path, query string and
-- all; routes that accept query parameters split it off here, on the first
-- '?'. Returns the bare path and the raw query ("" when there is no '?').
function Http.split_query(path: string): string, string
   local at = path:find("?", 1, true)
   if not at then
      return path, ""
   end
   return path:sub(1, at - 1), path:sub(at + 1)
end

-- application/x-www-form-urlencoded decoding: '+' means space, THEN percent
-- triplets decode (so a literal "%2B" survives as '+'). This is deliberately
-- not decode_path_segment: in path segments '+' is a literal plus, and invalid
-- percent triplets here are left untouched rather than raising.
local function form_decode(value: string): string
   local spaced = value:gsub("%+", " ")
   return (spaced:gsub("%%(%x%x)", function(hex: string): string
      return string.char(tonumber(hex, 16) as integer)
   end))
end

-- Splits on '&', then on the first '='; a key without '=' gets "". Works for
-- both request bodies and query strings.
function Http.parse_form(body: string): {string: string}
   local out: {string: string} = {}
   for pair in (body .. "&"):gmatch("(.-)&") do
      if pair ~= "" then
         local key, value = pair:match("^([^=]*)=(.*)$")
         if key then
            out[form_decode(key)] = form_decode(value)
         else
            out[form_decode(pair)] = ""
         end
      end
   end
   return out
end

function Http.response(status: integer, headers: {string: string}, body: string): string
   local parts: {string} = {
      "HTTP/1.1 " .. tostring(status) .. " " .. (status_text[status] or "OK") .. "\r\n",
   }
   local has_length = false
   for key, value in pairs(headers or {}) do
      if key:lower() == "content-length" then
         has_length = true
      end
      parts[#parts + 1] = key .. ": " .. value .. "\r\n"
   end
   local payload = body or ""
   if not has_length then
      parts[#parts + 1] = "Content-Length: " .. tostring(#payload) .. "\r\n"
   end
   parts[#parts + 1] = "Connection: close\r\n\r\n"
   parts[#parts + 1] = payload
   return table.concat(parts)
end

return Http
