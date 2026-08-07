-- AWS Signature Version 4 signing for S3 requests.
--
-- Pure: this module requires only app.crypto, which needs nothing but the
-- LuaJIT FFI. That keeps it loadable outside lunet-run and therefore unit
-- testable, which matters because signing is fiddly, entirely specified, and
-- has published known-answer test vectors. See tests/sigv4_test.tl.
--
-- Scope is deliberately narrow: path-style addressing against one endpoint,
-- header-signed requests, no presigning, no chunked upload, no session tokens.

local crypto = require("app.crypto")

local record Sigv4
   -- Hex SHA-256 of the empty string, required on every unsigned-body request.
   EMPTY_PAYLOAD_SHA256: string

   record Credentials
      access_key: string
      secret_key: string
      region: string
   end

   record Request
      method: string
      -- Absolute, already-encoded path, e.g. "/bucket/key.txt".
      path: string
      host: string
      -- Hex SHA-256 of the body. Empty bodies use EMPTY_PAYLOAD_SHA256.
      payload_sha256: string
      -- Basic ISO8601 UTC, e.g. "20150830T123600Z".
      amz_date: string
   end
end

local ALGORITHM <const> = "AWS4-HMAC-SHA256"
local SERVICE <const> = "s3"

Sigv4.EMPTY_PAYLOAD_SHA256 =
   "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

-- The scope date is the leading yyyymmdd of the amz date.
function Sigv4.date_stamp(amz_date: string): string
   return amz_date:sub(1, 8)
end

-- Signing key derivation: HMAC chained over date, region, service, terminator.
function Sigv4.signing_key(secret_key: string, date_stamp: string, region: string, service: string): string
   local k_date = crypto.hmac_sha256("AWS4" .. secret_key, date_stamp)
   local k_region = crypto.hmac_sha256(k_date, region)
   local k_service = crypto.hmac_sha256(k_region, service)
   return crypto.hmac_sha256(k_service, "aws4_request")
end

-- Only the three headers this project signs, which must appear in the
-- canonical request in lowercase ascending order.
function Sigv4.canonical_request(req: Sigv4.Request): string
   return table.concat({
      req.method,
      req.path,
      "",
      "host:" .. req.host,
      "x-amz-content-sha256:" .. req.payload_sha256,
      "x-amz-date:" .. req.amz_date,
      "",
      "host;x-amz-content-sha256;x-amz-date",
      req.payload_sha256,
   }, "\n")
end

function Sigv4.string_to_sign(req: Sigv4.Request, scope: string): string
   return table.concat({
      ALGORITHM,
      req.amz_date,
      scope,
      crypto.sha256_hex(Sigv4.canonical_request(req)),
   }, "\n")
end

-- The value for the Authorization header.
function Sigv4.authorization(req: Sigv4.Request, creds: Sigv4.Credentials): string
   local date_stamp = Sigv4.date_stamp(req.amz_date)
   local scope = date_stamp .. "/" .. creds.region .. "/" .. SERVICE .. "/aws4_request"
   local key = Sigv4.signing_key(creds.secret_key, date_stamp, creds.region, SERVICE)
   local signature = crypto.to_hex(crypto.hmac_sha256(key, Sigv4.string_to_sign(req, scope)))
   return ALGORITHM
      .. " Credential=" .. creds.access_key .. "/" .. scope
      .. ", SignedHeaders=host;x-amz-content-sha256;x-amz-date"
      .. ", Signature=" .. signature
end

return Sigv4
