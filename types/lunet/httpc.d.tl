-- Declarations for `lunet.httpc` provided by lunet-run.
--
-- Verified by probing lunet v0.7.1 macos. The upstream release ships no type
-- declarations and no reference docs for this module, so everything below was
-- established empirically; see the notes on each field for what was actually
-- observed. Upstream issue: lua-lunet/lunet (asking for declarations and
-- reference docs for every module, with this file as the worked example).
--
-- NON-BLOCKING. httpc.request yields to the Lunet scheduler rather than
-- blocking the process. Verified: with a request stalled against a blackholed
-- address, a sibling coroutine spawned with lunet.spawn continued to run and
-- ticked 30 times before the request returned. This is why server code must use
-- httpc rather than shelling out to curl or mc through io.popen, which would
-- stall every in-flight coroutine.
--
-- The backend appears to be libcurl: failures surface libcurl's own message
-- strings ("Could not connect to server", "Timeout was reached") and requests
-- carry a `User-Agent: lunet-httpc/0.1` header by default.

local record httpc

   -- Options for a single request. request() takes exactly one table; calling
   -- it as request(method, url) fails with "httpc.request requires options
   -- table".
   --
   -- WARNING: unrecognised keys are ignored silently. `timeout` (rather than
   -- `timeout_ms`) is accepted without complaint and has no effect, leaving the
   -- 30 second default in place. Spell these exactly.
   record Options
      -- Full URL including scheme. Required.
      url: string

      -- Defaults to "GET". "POST", "PUT" and "DELETE" verified as sent
      -- verbatim on the wire.
      method: string

      -- Sent as a name-value map, not an array. Merged with the defaults
      -- below; an explicit Content-Type overrides the default one.
      headers: {string: string}

      -- Request body. Content-Length is set automatically from its length.
      -- When a body is supplied without a Content-Type header, libcurl's
      -- default of application/x-www-form-urlencoded is sent, which is rarely
      -- what a non-form caller wants, so set Content-Type explicitly.
      body: string

      -- Total timeout in milliseconds. DEFAULTS TO 30000, which is far too
      -- long for a dependency sitting in a request path; set it explicitly.
      -- Verified honoured. The names `timeout`, `timeout_seconds`,
      -- `connect_timeout` and `connect_timeout_ms` are all silently ignored.
      timeout_ms: integer
   end

   -- One response header. Headers come back as an ordered array of these
   -- records rather than as a map, so repeated headers (Set-Cookie) are
   -- preserved. Names are returned in the case the server sent them, so match
   -- them case-insensitively.
   record Header
      name: string
      value: string
   end

   record Response
      -- HTTP status code, e.g. 200. Note that any complete response is a
      -- success: 4xx and 5xx arrive here rather than as an error, so callers
      -- must check this field. Only transport failures return nil.
      status: integer
      body: string
      headers: {Header}

      -- The URL that actually served the response, after any redirects.
      effective_url: string
   end

   -- Returns nil plus a message on transport failure (connection refused,
   -- timeout, DNS). A served HTTP error is NOT a failure; see Response.status.
   request: function(options: Options): Response, string
end

return httpc
