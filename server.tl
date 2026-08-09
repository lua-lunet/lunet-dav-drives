local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. here .. "/?/init.lua;" .. package.path

local lunet = require("lunet")
local socket = require("lunet.socket")
local api = require("app.api")
local http = require("app.http")
local nc31 = require("app.nc31")

local host = os.getenv("APP_HOST") or "127.0.0.1"
local port = tonumber(os.getenv("APP_PORT") or "8081") as integer

lunet.spawn(function()
   local listener, err = socket.listen("tcp", host, port)
   if not listener then
      io.stderr:write("failed to listen: " .. tostring(err) .. "\n")
      return
   end
   io.stderr:write("lunet-dav-drives listening on http://" .. host .. ":" .. tostring(port) .. "\n")
   while true do
      local client = socket.accept(listener)
      if client then
         lunet.spawn(function()
            local raw = socket.read(client)
            if not raw then
               socket.close(client)
               return
            end
            local req, parse_err = http.parse_request(raw)
            if not req then
               socket.write(client, http.response(400, { ["Content-Type"] = "text/plain" }, parse_err))
            elseif nc31.handles(req.path) then
               socket.write(client, nc31.dispatch(req))
            else
               socket.write(client, api.dispatch(req))
            end
            socket.close(client)
         end)
      end
   end
end)
