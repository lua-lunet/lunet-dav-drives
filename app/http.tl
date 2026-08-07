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
