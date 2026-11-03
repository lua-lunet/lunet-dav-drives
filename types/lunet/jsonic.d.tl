-- Declarations for `lunet.jsonic` provided by lunet-run.
-- Verified against lunet v0.18.2 macos.

local record jsonic
   version: string
   null: any

   encode: function(value: any): string
   decode: function(text: string): any, string
   quotestring: function(s: string): string
   addnewline: function(state: any)
   use_lpeg: function()
end

return jsonic
