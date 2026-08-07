-- Declarations for the `lunet` core module provided by lunet-run.
-- Verified against lunet v0.7.1 macos.

local record lunet
   spawn: function(fn: function())
   sleep: function(seconds: number)
end

return lunet
