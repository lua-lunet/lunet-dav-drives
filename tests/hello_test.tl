local tested = require("tested")
local hello = require("app.hello")

tested.test("greeting formats the subject read from the database", function()
   tested.assert({
      given = "a subject value",
      should = "prefix it with hello",
      expected = "hello tracer",
      actual = hello.greeting("tracer"),
   })
end)

return tested
