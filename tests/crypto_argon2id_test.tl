local tested = require("tested")
local crypto = require("app.crypto")

tested.test("argon2id round-trips a password", function()
   local encoded = crypto.argon2id("correct horse battery staple")
   tested.assert({
      given = "a freshly hashed password",
      should = "verify against the same password",
      expected = true,
      actual = crypto.argon2id_verify(encoded, "correct horse battery staple"),
   })
   tested.assert({
      given = "a freshly hashed password",
      should = "reject a different password",
      expected = false,
      actual = crypto.argon2id_verify(encoded, "correct horse battery staplex"),
   })
end)

tested.test("argon2id output carries the argon2id prefix and a random salt", function()
   local a = crypto.argon2id("pepper")
   local b = crypto.argon2id("pepper")
   tested.assert({
      given = "a freshly minted hash",
      should = "carry the $argon2id$ prefix",
      expected = "$argon2id$",
      actual = string.sub(a, 1, 10),
   })
   tested.assert({
      given = "two hashes of the same password",
      should = "differ because the salt is random",
      expected = false,
      actual = a == b,
   })
end)

-- Known-answer pair from libsodium's own test suite
-- (test/default/pwhash_argon2id.c, str_tests "valid(7)"): this exact encoded
-- hash must verify against "password" through crypto_pwhash_str_verify, and
-- the suite asserts a wrong password fails against it.
tested.test("argon2id_verify matches the libsodium known-answer pair", function()
   local hash = "$argon2id$v=19$m=256,t=3,p=1$MDEyMzQ1Njc$G5ajKFCoUzaXRLdz7UJb5wGkb2Xt+X5/GQjUYtS2+TE"
   tested.assert({
      given = "the libsodium test-suite hash and its password",
      should = "verify",
      expected = true,
      actual = crypto.argon2id_verify(hash, "password"),
   })
   tested.assert({
      given = "the libsodium test-suite hash and a wrong password",
      should = "not verify",
      expected = false,
      actual = crypto.argon2id_verify(hash, "passwordx"),
   })
end)

tested.test("argon2id_verify refuses an overlong encoded string without erroring", function()
   tested.assert({
      given = "an encoded string far longer than crypto_pwhash_strbytes",
      should = "return false rather than raise",
      expected = false,
      actual = crypto.argon2id_verify(string.rep("A", 4096), "x"),
   })
end)

tested.test("random_bytes draws differ", function()
   tested.assert({
      given = "two 32-byte draws from the CSPRNG",
      should = "differ",
      expected = false,
      actual = crypto.random_bytes(32) == crypto.random_bytes(32),
   })
end)

tested.test("random_hex is lowercase hex twice as long as the byte count", function()
   local token = crypto.random_hex(16)
   tested.assert({
      given = "a 16-byte random token as hex",
      should = "be 32 characters long",
      expected = 32,
      actual = #token,
   })
   tested.assert({
      given = "a 16-byte random token as hex",
      should = "be lowercase hex only",
      expected = true,
      actual = string.match(token, "^[0-9a-f]+$") ~= nil,
   })
end)

return tested
