-- Tracer-round scaffolding.
--
-- This module exists only to prove the whole path is wired end to end:
--
--   Teal source -> Cyan build -> tested unit smoke
--     -> Lunet runs the generated Lua -> Hurl asserts the real HTTP response
--
-- It deliberately requires nothing. Modules that require Lunet APIs (app.db,
-- app.crypto) can only load inside lunet-run, so they are not unit-testable
-- under a plain Lua interpreter; Hurl covers them against the running server
-- instead. Keeping pure logic in its own module is what makes the unit smoke
-- fast and dependency-free.
--
-- Delete this module, its test, its route, and the hello_tracer table once
-- /health, /v1/me, and /v1/drives are real.

local record Hello
end

function Hello.greeting(subject: string): string
   return "hello " .. subject
end

return Hello
