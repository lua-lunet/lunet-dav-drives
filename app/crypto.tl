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
unsigned long long crypto_pwhash_opslimit_interactive(void);
size_t crypto_pwhash_memlimit_interactive(void);
size_t crypto_pwhash_strbytes(void);
int crypto_pwhash_str(char *out, const char *passwd, unsigned long long passwdlen, unsigned long long opslimit, size_t memlimit);
int crypto_pwhash_str_verify(const char *str, const char *passwd, unsigned long long passwdlen);
void randombytes_buf(void * const buf, const size_t size);
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

   -- Argon2id password hashing and the CSPRNG, for the NCe31 compat surface.
   crypto_pwhash_opslimit_interactive: function(): integer
   crypto_pwhash_memlimit_interactive: function(): integer
   crypto_pwhash_strbytes: function(): integer
   crypto_pwhash_str: function(
      out: ffi.cdata, passwd: string, passwdlen: integer,
      opslimit: integer, memlimit: integer): integer
   crypto_pwhash_str_verify: function(str: string, passwd: string, passwdlen: integer): integer
   randombytes_buf: function(buf: ffi.cdata, size: integer)
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

-- Interactive Argon2id limits and the encoded-hash buffer size, read from the
-- library rather than hardcoded so a libsodium bump moves both together.
local PWHASH_OPSLIMIT <const> = tonumber(lib.crypto_pwhash_opslimit_interactive()) as integer
local PWHASH_MEMLIMIT <const> = tonumber(lib.crypto_pwhash_memlimit_interactive()) as integer
local PWHASH_STRBYTES <const> = tonumber(lib.crypto_pwhash_strbytes()) as integer

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

-- Argon2id encoded hash ($argon2id$v=19$m=...,t=...,p=1$...) at the library's
-- interactive limits, with a fresh random salt per call.
function Crypto.argon2id(password: string): string
   local out = ffi.new("char[?]", PWHASH_STRBYTES)
   local rc = lib.crypto_pwhash_str(
      out, password, #password, PWHASH_OPSLIMIT, PWHASH_MEMLIMIT)
   if rc ~= 0 then
      error("app.crypto: crypto_pwhash_str failed (out of memory)", 0)
   end
   return ffi.string(out)
end

-- Return code 0 is a match. Every failure — wrong password or a malformed
-- encoded string — is false, never an error. The length guard is required:
-- crypto_pwhash_str_verify only accepts encoded input shorter than strbytes,
-- and overlong input must not error out of the C call.
function Crypto.argon2id_verify(encoded: string, password: string): boolean
   if #encoded >= PWHASH_STRBYTES then
      return false
   end
   return lib.crypto_pwhash_str_verify(encoded, password, #password) == 0
end

-- Cryptographically secure randomness for login-flow tokens and minted app
-- passwords. Never shell out for this: io.popen would block the scheduler.
function Crypto.random_bytes(n: integer): string
   local buf = ffi.new("unsigned char[?]", n)
   lib.randombytes_buf(buf, n)
   return ffi.string(buf, n)
end

function Crypto.random_hex(n: integer): string
   return to_hex(Crypto.random_bytes(n))
end

return Crypto
