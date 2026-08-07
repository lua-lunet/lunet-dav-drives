-- Minimal declarations for the LuaJIT FFI.
--
-- Only the surface this project uses is declared. `cdata` is deliberately
-- opaque: callers cast a loaded library to a record describing the exact C
-- functions they call, so the C boundary is typed at the call site rather than
-- being `any` everywhere.

local record ffi
   type cdata = any
   type ctype = any

   -- A one-element numeric out-parameter, e.g. ffi.new("size_t[1]").
   -- cdata is deliberately opaque, so reading one back needs an explicit cast.
   type OutNumber = {integer: number}

   cdef: function(definition: string)
   load: function(name: string, global?: boolean): any
   new: function(ct: string, ...: any): cdata
   cast: function(ct: string, value: any): cdata
   typeof: function(ct: string): ctype
   sizeof: function(ct: string): integer
   -- Omitting len reads up to the first NUL, as strlen would.
   string: function(ptr: cdata, len?: integer): string

   os: string
   arch: string
end

return ffi
