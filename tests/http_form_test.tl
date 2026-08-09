local tested = require("tested")
local http = require("app.http")

tested.test("split_query splits on the first question mark", function()
   local path, query = http.split_query("/ocs/v2.php/cloud/user?format=json")
   tested.assert({
      given = "a request target with a query string",
      should = "return the path without the query",
      expected = "/ocs/v2.php/cloud/user",
      actual = path,
   })
   tested.assert({
      given = "a request target with a query string",
      should = "return the query without the question mark",
      expected = "format=json",
      actual = query,
   })
end)

tested.test("split_query leaves a queryless path intact", function()
   local path, query = http.split_query("/health")
   tested.assert({
      given = "a request target without a question mark",
      should = "return the path unchanged",
      expected = "/health",
      actual = path,
   })
   tested.assert({
      given = "a request target without a question mark",
      should = "return an empty query",
      expected = "",
      actual = query,
   })
end)

tested.test("split_query splits only on the first question mark", function()
   local path, query = http.split_query("/x?y?z")
   tested.assert({
      given = "a request target with two question marks",
      should = "keep the second one inside the query",
      expected = "y?z",
      actual = query,
   })
   tested.assert({
      given = "a request target with two question marks",
      should = "return the path up to the first",
      expected = "/x",
      actual = path,
   })
end)

tested.test("parse_form decodes plus as space and percent triplets", function()
   local form = http.parse_form("token=abc+def&loginName=u1&password=p%40ss%3Dx")
   tested.assert({
      given = "a form value containing '+'",
      should = "decode '+' as a space",
      expected = "abc def",
      actual = form.token,
   })
   tested.assert({
      given = "a plain form value",
      should = "pass through unchanged",
      expected = "u1",
      actual = form.loginName,
   })
   tested.assert({
      given = "a form value with percent triplets including %3D",
      should = "decode them after splitting on the first '='",
      expected = "p@ss=x",
      actual = form.password,
   })
end)

tested.test("parse_form keeps an encoded plus literal", function()
   local form = http.parse_form("a=%2B")
   tested.assert({
      given = "a percent-encoded plus sign",
      should = "decode to '+' rather than a space",
      expected = "+",
      actual = form.a,
   })
end)

tested.test("parse_form treats a key without '=' as an empty value", function()
   local form = http.parse_form("token&other=x")
   tested.assert({
      given = "a pair without '='",
      should = "map the key to an empty string",
      expected = "",
      actual = form.token,
   })
   tested.assert({
      given = "a following well-formed pair",
      should = "still parse",
      expected = "x",
      actual = form.other,
   })
end)

tested.test("parse_form of an empty body is an empty table", function()
   local form = http.parse_form("")
   tested.assert({
      given = "an empty body",
      should = "produce no keys",
      expected = true,
      actual = next(form) == nil,
   })
end)

return tested
