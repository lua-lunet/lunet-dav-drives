-- Minimal S3 client for the configured object store.
--
-- Requires lunet.httpc, so this module only loads inside lunet-run and is not
-- unit testable; Hurl covers it against the running server. The signing logic
-- it delegates to lives in app.sigv4, which is pure and is unit tested.
--
-- httpc.request is non-blocking under the Lunet scheduler, which is why blob
-- traffic goes through it rather than through a shelled-out mc or curl.
--
-- Path-style addressing throughout, because the endpoint is an IP:port.
-- Blob keys are internal; nothing here is exposed by the native API.

local httpc = require("lunet.httpc")
local crypto = require("app.crypto")
local sigv4 = require("app.sigv4")

local record S3
end

-- Blob traffic sits in a request path, so never inherit httpc's 30s default.
local TIMEOUT_MS <const> = 5000

local function config(): string, string, sigv4.Credentials
   local endpoint = os.getenv("S3_ENDPOINT") or "http://127.0.0.1:19010"
   local bucket = os.getenv("S3_BUCKET") or "lunet-dav-drives"
   return endpoint, bucket, {
      access_key = os.getenv("S3_ACCESS_KEY_ID") or "",
      secret_key = os.getenv("S3_SECRET_ACCESS_KEY") or "",
      region = os.getenv("S3_REGION") or "garage",
   }
end

-- Strips the scheme so the host can be signed and the URL rebuilt.
local function split_endpoint(endpoint: string): string, string
   local scheme, host = endpoint:match("^(https?)://(.+)$")
   if not scheme then
      return nil, nil
   end
   return scheme, (host:gsub("/+$", ""))
end

local function header_value(headers: {httpc.Header}, name: string): string
   for i = 1, #headers do
      if headers[i].name:lower() == name:lower() then
         return headers[i].value
      end
   end
   return nil
end

function S3.get_object(key: string): string, string
   local endpoint, bucket, creds = config()
   local scheme, host = split_endpoint(endpoint)
   if not scheme then
      return nil, "S3_ENDPOINT is not a http(s) URL: " .. endpoint
   end

   local path = "/" .. bucket .. "/" .. key
   local amz_date = os.date("!%Y%m%dT%H%M%SZ") as string
   local request: sigv4.Request = {
      method = "GET",
      path = path,
      host = host,
      payload_sha256 = sigv4.EMPTY_PAYLOAD_SHA256,
      amz_date = amz_date,
   }

   local res, err = httpc.request({
      url = scheme .. "://" .. host .. path,
      method = "GET",
      timeout_ms = TIMEOUT_MS,
      headers = {
         ["Host"] = host,
         ["x-amz-content-sha256"] = sigv4.EMPTY_PAYLOAD_SHA256,
         ["x-amz-date"] = amz_date,
         ["Authorization"] = sigv4.authorization(request, creds),
      },
   })
   if not res then
      return nil, "object store unreachable: " .. tostring(err)
   end
   -- A served 4xx/5xx arrives as a normal response, so status must be checked.
   if res.status ~= 200 then
      return nil, "object store returned " .. tostring(res.status) .. ": " .. res.body
   end
   return res.body
end

function S3.head_object(key: string): {httpc.Header}, string
   local endpoint, bucket, creds = config()
   local scheme, host = split_endpoint(endpoint)
   if not scheme then
      return nil, "S3_ENDPOINT is not a http(s) URL: " .. endpoint
   end
   local path = "/" .. bucket .. "/" .. key
   local amz_date = os.date("!%Y%m%dT%H%M%SZ") as string
   local request: sigv4.Request = {
      method = "HEAD",
      path = path,
      host = host,
      payload_sha256 = sigv4.EMPTY_PAYLOAD_SHA256,
      amz_date = amz_date,
   }
   local res, err = httpc.request({
      url = scheme .. "://" .. host .. path,
      method = "HEAD",
      timeout_ms = TIMEOUT_MS,
      headers = {
         ["Host"] = host,
         ["x-amz-content-sha256"] = sigv4.EMPTY_PAYLOAD_SHA256,
         ["x-amz-date"] = amz_date,
         ["Authorization"] = sigv4.authorization(request, creds),
      },
   })
   if not res then
      return nil, "object store unreachable: " .. tostring(err)
   end
   if res.status ~= 200 then
      return nil, "object store returned " .. tostring(res.status)
   end
   return res.headers
end

function S3.put_object(key: string, body: string, content_type: string): string, string
   local endpoint, bucket, creds = config()
   local scheme, host = split_endpoint(endpoint)
   if not scheme then
      return nil, "S3_ENDPOINT is not a http(s) URL: " .. endpoint
   end
   local path = "/" .. bucket .. "/" .. key
   local amz_date = os.date("!%Y%m%dT%H%M%SZ") as string
   local body_sha256 = crypto.sha256_hex(body)
   local request: sigv4.Request = {
      method = "PUT",
      path = path,
      host = host,
      payload_sha256 = body_sha256,
      amz_date = amz_date,
   }
   local res, err = httpc.request({
      url = scheme .. "://" .. host .. path,
      method = "PUT",
      timeout_ms = TIMEOUT_MS,
      body = body,
      headers = {
         ["Host"] = host,
         ["Content-Type"] = content_type or "application/octet-stream",
         ["x-amz-content-sha256"] = body_sha256,
         ["x-amz-date"] = amz_date,
         ["Authorization"] = sigv4.authorization(request, creds),
      },
   })
   if not res then
      return nil, "object store unreachable: " .. tostring(err)
   end
   if res.status ~= 200 and res.status ~= 201 and res.status ~= 204 then
      return nil, "object store returned " .. tostring(res.status) .. ": " .. res.body
   end
   local version = header_value(res.headers, "x-amz-version-id")
   return version
end

function S3.delete_object(key: string): boolean, string
   local endpoint, bucket, creds = config()
   local scheme, host = split_endpoint(endpoint)
   if not scheme then
      return false, "S3_ENDPOINT is not a http(s) URL: " .. endpoint
   end
   local path = "/" .. bucket .. "/" .. key
   local amz_date = os.date("!%Y%m%dT%H%M%SZ") as string
   local request: sigv4.Request = {
      method = "DELETE",
      path = path,
      host = host,
      payload_sha256 = sigv4.EMPTY_PAYLOAD_SHA256,
      amz_date = amz_date,
   }
   local res, err = httpc.request({
      url = scheme .. "://" .. host .. path,
      method = "DELETE",
      timeout_ms = TIMEOUT_MS,
      headers = {
         ["Host"] = host,
         ["x-amz-content-sha256"] = sigv4.EMPTY_PAYLOAD_SHA256,
         ["x-amz-date"] = amz_date,
         ["Authorization"] = sigv4.authorization(request, creds),
      },
   })
   if not res then
      return false, "object store unreachable: " .. tostring(err)
   end
   if res.status ~= 200 and res.status ~= 204 then
      return false, "object store returned " .. tostring(res.status) .. ": " .. res.body
   end
   return true
end

return S3
