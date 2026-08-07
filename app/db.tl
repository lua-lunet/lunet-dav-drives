local pg = require("lunet.postgres")

local record DB
   type Row = pg.Row
end

local function config(): pg.Config
   return {
      host = os.getenv("PGHOST") or "127.0.0.1",
      port = tonumber(os.getenv("PGPORT") or "5432") as integer,
      user = os.getenv("PGUSER") or "postgres",
      password = os.getenv("PGPASSWORD") or "",
      database = os.getenv("PGDATABASE") or "lunet_dav_drives",
   }
end

function DB.query(sql: string, ...: any): {DB.Row}, string
   local conn, open_err = pg.open(config())
   if not conn then
      return nil, open_err
   end
   local rows, query_err = pg.query(conn, sql, ...)
   pg.close(conn)
   if query_err then
      return nil, query_err
   end
   return rows
end

function DB.exec(sql: string, ...: any): boolean, string
   local conn, open_err = pg.open(config())
   if not conn then
      return false, open_err
   end
   local _, exec_err = pg.exec(conn, sql, ...)
   pg.close(conn)
   if exec_err then
      return false, exec_err
   end
   return true
end

return DB
