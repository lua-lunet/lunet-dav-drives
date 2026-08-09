local ffi = require("ffi")

ffi.cdef [[
int sodium_init(void);
void crypto_hash_sha256(unsigned char *out, const unsigned char *in, unsigned long long inlen);
char *sodium_bin2base64(char *b64, size_t b64_maxlen,
                        const unsigned char *bin, size_t bin_len,
                        int variant);
int sodium_base642bin(unsigned char *bin, size_t bin_maxlen,
                      const char *b64, size_t b64_len,
                      const char *ignore, size_t *bin_len,
                      const char **b64_end, int variant);
size_t crypto_auth_hmacsha256_statebytes(void);
int crypto_auth_hmacsha256_init(void *state, const unsigned char *key, size_t keylen);
int crypto_auth_hmacsha256_update(void *state, const unsigned char *in, unsigned long long inlen);
int crypto_auth_hmacsha256_final(void *state, unsigned char *out);
]]

-- The C surface this module calls, so the FFI boundary is typed here rather
-- than leaking `any` into callers.
local record Sodium
   sodium_init: function(): integer
   crypto_hash_sha256: function(out: ffi.cdata, input: string, inlen: integer)
   sodium_bin2base64: function(
      b64: ffi.cdata, b64_maxlen: integer,
      bin: string, bin_len: integer,
      variant: integer): ffi.cdata
   sodium_base642bin: function(
      bin: ffi.cdata, bin_maxlen: integer,
      b64: string, b64_len: integer,
      ignore: ffi.cdata, bin_len: ffi.cdata,
      b64_end: ffi.cdata, variant: integer): integer

   -- The streaming HMAC API is used rather than crypto_auth_hmacsha256, which
   -- accepts only 32 byte keys. SigV4 signing keys vary in length.
   crypto_auth_hmacsha256_statebytes: function(): integer
   crypto_auth_hmacsha256_init: function(state: ffi.cdata, key: string, keylen: integer): integer
   crypto_auth_hmacsha256_update: function(state: ffi.cdata, input: string, inlen: integer): integer
   crypto_auth_hmacsha256_final: function(state: ffi.cdata, out: ffi.cdata): integer
end

local BASE64_VARIANT_ORIGINAL <const> = 1
local SHA256_BYTES <const> = 32

local function load_sodium(): Sodium
   local candidates = { "sodium", "libsodium" }
   for i = 1, #candidates do
      local ok, lib = pcall(ffi.load, candidates[i])
      if ok and lib then
         return lib as Sodium
      end
   end
   error("app.crypto: unable to load libsodium (tried sodium, libsodium)", 0)
end

local lib = load_sodium()
assert(lib.sodium_init() >= 0)

-- Sized from the library itself rather than hardcoded, rounded up to whole
-- 8 byte words.
local HMAC_STATE_WORDS <const> =
   math.floor((tonumber(lib.crypto_auth_hmacsha256_statebytes()) + 7) / 8)

local record Crypto
   to_hex: function(raw: string): string
end

local function to_hex(raw: string): string
   local hex = {}
   for i = 1, #raw do
      hex[i] = string.format("%02x", string.byte(raw, i))
   end
   return table.concat(hex)
end

Crypto.to_hex = to_hex

function Crypto.sha256(data: string): string
   local out = ffi.new("unsigned char[?]", SHA256_BYTES)
   lib.crypto_hash_sha256(out, data, #data)
   return ffi.string(out, SHA256_BYTES)
end

function Crypto.sha256_hex(data: string): string
   return to_hex(Crypto.sha256(data))
end

-- Raw 32 byte MAC. Keys may be any length, which SigV4's chained derivation
-- requires. The state buffer is allocated as uint64 so it is 8 byte aligned.
function Crypto.hmac_sha256(key: string, data: string): string
   local state = ffi.new("uint64_t[?]", HMAC_STATE_WORDS)
   lib.crypto_auth_hmacsha256_init(state, key, #key)
   lib.crypto_auth_hmacsha256_update(state, data, #data)
   local out = ffi.new("unsigned char[?]", SHA256_BYTES)
   lib.crypto_auth_hmacsha256_final(state, out)
   return ffi.string(out, SHA256_BYTES)
end

function Crypto.hmac_sha256_hex(key: string, data: string): string
   return to_hex(Crypto.hmac_sha256(key, data))
end

function Crypto.base64_encode(data: string): string
   local out_len = math.floor((#data + 2) / 3) * 4 + 1
   local out = ffi.new("char[?]", out_len)
   lib.sodium_bin2base64(out, out_len, data, #data, BASE64_VARIANT_ORIGINAL)
   return ffi.string(out)
end

function Crypto.base64_decode(data: string): string, string
   local out = ffi.new("unsigned char[?]", #data + 1)
   local out_len = ffi.new("size_t[1]")
   local ignore = ffi.cast("const char *", nil)
   local endp = ffi.new("const char *[1]")
   local rc = lib.sodium_base642bin(
      out, #data, data, #data, ignore, out_len, endp, BASE64_VARIANT_ORIGINAL)
   if rc ~= 0 then
      return nil, "invalid base64"
   end
   local decoded_len = (out_len as ffi.OutNumber)[0]
   return ffi.string(out, tonumber(decoded_len) as integer)
end

return Crypto
