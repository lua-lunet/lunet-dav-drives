-- Declarations for `lunet.socket` provided by lunet-run.
-- Verified against lunet v0.8.0 macos.

local record socket
   -- Opaque listener and connection handles (userdata at runtime).
   type Listener = any
   type Conn = any

   listen: function(kind: string, host: string, port: integer): Listener, string
   accept: function(listener: Listener): Conn, string
   connect: function(host: string, port: integer): Conn, string
   read: function(conn: Conn): string, string
   write: function(conn: Conn, data: string): string
   close: function(conn: Conn)
   getpeername: function(conn: Conn): string, string
   set_read_buffer_size: function(size: integer)
end

return socket
