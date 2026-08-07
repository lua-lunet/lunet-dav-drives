-- Declarations for `lunet.postgres` provided by lunet-run.
-- Verified against lunet v0.7.1 macos: open takes a config table, query and
-- exec both accept $n placeholders followed by their bind values, and rows come
-- back as an array of column-name-keyed tables.

local record postgres
   -- Opaque connection handle (userdata at runtime).
   type Conn = any

   -- One result row, keyed by column name. Postgres integers arrive as
   -- numbers and text as strings, so values are read through `as`.
   type Row = {string: any}

   record Config
      host: string
      port: integer
      user: string
      password: string
      database: string
   end

   open: function(config: Config): Conn, string
   close: function(conn: Conn)

   query: function(conn: Conn, sql: string, ...: any): {Row}, string
   exec: function(conn: Conn, sql: string, ...: any): {string: any}, string

   query_params: function(conn: Conn, sql: string, ...: any): {Row}, string
   exec_params: function(conn: Conn, sql: string, ...: any): {string: any}, string
end

return postgres
