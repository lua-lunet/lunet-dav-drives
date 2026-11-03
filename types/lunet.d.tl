-- Declarations for the `lunet` core module provided by lunet-run.
-- Verified against lunet v0.18.2 macos.

local record lunet
   spawn: function(fn: function())
   sleep: function(ms: integer)
end

return lunet
