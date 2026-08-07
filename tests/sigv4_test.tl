local tested = require("tested")
local sigv4 = require("app.sigv4")
local crypto = require("app.crypto")

-- Known-answer vectors from the AWS Signature Version 4 documentation. Signing
-- is entirely specified and easy to get subtly wrong, so it is worth pinning
-- against published values rather than against our own output.
tested.test("derives the AWS documented signing key", function()
   local key = sigv4.signing_key(
      "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "20150830", "us-east-1", "iam")
   tested.assert({
      given = "the AWS documented secret, date, region and service",
      should = "derive the documented signing key",
      expected = "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9",
      actual = crypto.to_hex(key),
   })
end)

tested.test("hashes the empty payload to the documented constant", function()
   tested.assert({
      given = "an empty request body",
      should = "match the published empty payload hash",
      expected = sigv4.EMPTY_PAYLOAD_SHA256,
      actual = crypto.sha256_hex(""),
   })
end)

tested.test("hmac matches RFC 4231 test case 1", function()
   local key = string.rep(string.char(0x0b), 20)
   tested.assert({
      given = "RFC 4231 test case 1",
      should = "produce the published HMAC-SHA256",
      expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
      actual = crypto.hmac_sha256_hex(key, "Hi There"),
   })
end)

tested.test("canonical request lays out signed headers in order", function()
   local canonical = sigv4.canonical_request({
      method = "GET",
      path = "/lunet-dav-drives/hello_tracer.txt",
      host = "127.0.0.1:19010",
      payload_sha256 = sigv4.EMPTY_PAYLOAD_SHA256,
      amz_date = "20150830T123600Z",
   })
   tested.assert({
      given = "a path-style GET",
      should = "produce the canonical request the S3 spec expects",
      expected = "GET\n"
         .. "/lunet-dav-drives/hello_tracer.txt\n"
         .. "\n"
         .. "host:127.0.0.1:19010\n"
         .. "x-amz-content-sha256:" .. sigv4.EMPTY_PAYLOAD_SHA256 .. "\n"
         .. "x-amz-date:20150830T123600Z\n"
         .. "\n"
         .. "host;x-amz-content-sha256;x-amz-date\n"
         .. sigv4.EMPTY_PAYLOAD_SHA256,
      actual = canonical,
   })
end)

tested.test("scope date is the leading day of the amz date", function()
   tested.assert({
      given = "a full amz timestamp",
      should = "take the yyyymmdd prefix",
      expected = "20150830",
      actual = sigv4.date_stamp("20150830T123600Z"),
   })
end)

tested.test("base64 helpers round-trip a sample string", function()
   local encoded = crypto.base64_encode("lunet")
   local decoded, err = crypto.base64_decode(encoded)
   tested.assert({
      given = "a short ASCII string",
      should = "survive base64 encode and decode",
      expected = "lunet",
      actual = decoded,
   })
   tested.assert_nil({
      given = "a valid base64 sample",
      should = "decode without error",
      actual = err,
   })
end)

return tested
