-- Cyan owns the whole-project compile.
--
-- Teal sources live where they belong (app/, tests/, tools/, server.tl) and
-- Cyan mirrors them as Lua under build/. Lunet only ever runs build/server.lua,
-- and `tested` only ever runs build/tests/.
--
-- include is an explicit allowlist because source_dir is the repo root, which
-- also holds .tools/ and build/.
return {
   source_dir = ".",
   build_dir = "build",

   include = {
      "server.tl",
      "app/**/*.tl",
      "tests/**/*.tl",
      -- tools/admin.tl is still untyped Lua in a .tl file and does not type
      -- check. It is not on the tracer path. Annotate it and add it here in the
      -- step that needs administered users for /v1/me.
   },

   -- Declarations for the modules Lunet and tested provide at runtime.
   include_dir = { "types" },

   -- LuaJIT is the runtime, so no compatibility shim is generated.
   gen_target = "5.1",
   gen_compat = "off",

   feat_arity = "on",
   warning_error = { "unused", "redeclaration" },
}
