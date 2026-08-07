local crypto = require("app.crypto")
local db = require("app.db")
local s3 = require("app.s3")

local record Files
end

local OBJECT_PREFIX <const> = "_objects/"

local function normalize_name(name: string): string, string
   if not name or name == "" then
      return nil, "empty name"
   end
   if name:find("/", 1, true) then
      return nil, "slash in name"
   end
   return name
end

local function object_key(sha256: string): string
   return OBJECT_PREFIX .. sha256
end

local function etag_for(file_id: any, revision: any, sha256: string): string
   return crypto.sha256_hex(tostring(file_id) .. ":" .. tostring(revision) .. ":" .. sha256)
end

local function file_summary(row: db.Row): {string: any}
   return {
      file_id = tostring(row.file_id),
      name = tostring(row.name),
      revision = tonumber(row.revision) as integer,
      mime_type = row.mime_type and tostring(row.mime_type) or nil,
   }
end

local function file_metadata(row: db.Row): {string: any}
   return {
      file_id = tostring(row.file_id),
      name = tostring(row.name),
      revision = tonumber(row.revision) as integer,
      mime_type = row.mime_type and tostring(row.mime_type) or nil,
      etag = tostring(row.etag),
      size = tonumber(row.size) as integer,
      sha256 = tostring(row.sha256),
      mtime_epoch = tonumber(row.mtime_epoch) as integer,
   }
end

local function insert_event(conn: any, file_id: any, actor_user_id: string, event_type: string, from_owner_user_id: string, from_drive_id: any, to_owner_user_id: string, to_drive_id: any, file_name: string, revision: any): boolean, string
   local _, err = db.exec_conn(conn, [[
      INSERT INTO file_events (
         file_id, actor_user_id, event_type,
         from_owner_user_id, from_drive_id, to_owner_user_id, to_drive_id,
         file_name, revision
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
   ]], file_id, actor_user_id, event_type,
      from_owner_user_id, from_drive_id, to_owner_user_id, to_drive_id,
      file_name, revision)
   if err then
      return false, err
   end
   return true
end

local function query_one(sql: string, ...: any): db.Row, string
   local rows, err = db.query(sql, ...)
   if err or not rows[1] then
      return nil, err or "not found"
   end
   return rows[1]
end

function Files.list_personal(user_id: string): {db.Row}, string
   local rows, err = db.query([[
      SELECT file_id, name, revision, mime_type
      FROM files
      WHERE owner_user_id = $1
      ORDER BY name
   ]], user_id)
   return rows, err
end

function Files.list_drive(user_id: string, drive_id: string): {db.Row}, string
   local rows, err = db.query([[
      SELECT f.file_id, f.name, f.revision, f.mime_type
      FROM files f
      JOIN drives d ON d.drive_id = f.drive_id
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
      ORDER BY f.name
   ]], user_id, drive_id)
   return rows, err
end

function Files.get_drive_info(user_id: string, drive_id: string): db.Row, string
   return query_one([[
      SELECT d.drive_id, d.drive_name
      FROM drives d
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
      LIMIT 1
   ]], user_id, drive_id)
end

local function load_personal_file(user_id: string, name: string, want_body: boolean): db.Row, string
   local rows, err = db.query([[
      SELECT
         f.file_id, f.name, f.revision, f.mime_type, f.etag,
         b.sha256, b.size,
         EXTRACT(EPOCH FROM f.mtime)::bigint AS mtime_epoch
      FROM files f
      JOIN blobs b ON b.blob_id = f.blob_id
      WHERE f.owner_user_id = $1
        AND f.name = $2
      LIMIT 1
   ]], user_id, name)
   if err or not rows[1] then
      return nil, err or "not found"
   end
   local row = rows[1]
   if want_body then
      local body, s3_err = s3.get_object(object_key(tostring(row.sha256)))
      if s3_err then
         return nil, s3_err
      end
      row.body = body
   end
   return row
end

local function load_drive_file(user_id: string, drive_id: string, name: string, want_body: boolean): db.Row, string
   local rows, err = db.query([[
      SELECT
         f.file_id, f.name, f.revision, f.mime_type, f.etag,
         b.sha256, b.size,
         EXTRACT(EPOCH FROM f.mtime)::bigint AS mtime_epoch
      FROM files f
      JOIN blobs b ON b.blob_id = f.blob_id
      JOIN drives d ON d.drive_id = f.drive_id
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
        AND f.name = $3
      LIMIT 1
   ]], user_id, drive_id, name)
   if err or not rows[1] then
      return nil, err or "not found"
   end
   local row = rows[1]
   if want_body then
      local body, s3_err = s3.get_object(object_key(tostring(row.sha256)))
      if s3_err then
         return nil, s3_err
      end
      row.body = body
   end
   return row
end

function Files.head_personal(user_id: string, name: string): db.Row, string
   return load_personal_file(user_id, name, false)
end

function Files.head_drive(user_id: string, drive_id: string, name: string): db.Row, string
   return load_drive_file(user_id, drive_id, name, false)
end

function Files.get_personal(user_id: string, name: string): db.Row, string
   return load_personal_file(user_id, name, true)
end

function Files.get_drive_file(user_id: string, drive_id: string, name: string): db.Row, string
   return load_drive_file(user_id, drive_id, name, true)
end

local function put_common(conn: any, actor_user_id: string, scope_kind: string, scope_id: string, existing: db.Row, name: string, mime_type: string, body_sha256: string, size: any, version_id: string): db.Row, string
   local blob_rows, blob_err = db.query_conn(conn, [[
      INSERT INTO blobs (sha256, size, storage_key, storage_version_id)
      VALUES ($1, $2, $3, $4)
      RETURNING blob_id
   ]], body_sha256, size, object_key(body_sha256), version_id)
   if blob_err or not blob_rows[1] then
      return nil, blob_err or "blob insert failed"
   end
   local blob_id = blob_rows[1].blob_id
   if existing then
      local new_revision = tonumber(existing.revision) + 1
      local new_etag = etag_for(existing.file_id, new_revision, body_sha256)
      local _, update_err = db.exec_conn(conn, [[
         UPDATE files
         SET blob_id = $1,
             mime_type = $2,
             etag = $3,
             revision = $4,
             mtime = now()
         WHERE file_id = $5
      ]], blob_id, mime_type, new_etag, new_revision, existing.file_id)
      if update_err then
         return nil, update_err
      end
      local ok, event_err = insert_event(
         conn,
         existing.file_id,
         actor_user_id,
         "content_replaced",
         scope_kind == "personal" and actor_user_id or nil,
         scope_kind == "drive" and scope_id or nil,
         scope_kind == "personal" and actor_user_id or nil,
         scope_kind == "drive" and scope_id or nil,
         name,
         new_revision
      )
      if not ok then
         return nil, event_err
      end
      return {
         created = false,
         file_id = tostring(existing.file_id),
         name = name,
         revision = new_revision,
         mime_type = mime_type,
         etag = new_etag,
      }
   end

   local new_etag = etag_for("pending", 1, body_sha256)
   local file_rows, file_err = db.query_conn(conn, [[
      INSERT INTO files (owner_user_id, drive_id, name, blob_id, mime_type, etag, revision)
      VALUES ($1, $2, $3, $4, $5, $6, 1)
      RETURNING file_id, revision
   ]], scope_kind == "personal" and scope_id or nil, scope_kind == "drive" and scope_id or nil, name, blob_id, mime_type, new_etag)
   if file_err or not file_rows[1] then
      return nil, file_err or "file insert failed"
   end
   local file_row = file_rows[1]
   local file_id = file_row.file_id
   local final_etag = etag_for(file_id, 1, body_sha256)
   local _, etag_err = db.exec_conn(conn, [[
      UPDATE files SET etag = $1 WHERE file_id = $2
   ]], final_etag, file_id)
   if etag_err then
      return nil, etag_err
   end
   local ok, event_err = insert_event(
      conn,
      file_id,
      actor_user_id,
      "created",
      scope_kind == "personal" and actor_user_id or nil,
      scope_kind == "drive" and scope_id or nil,
      scope_kind == "personal" and actor_user_id or nil,
      scope_kind == "drive" and scope_id or nil,
      name,
      1
   )
   if not ok then
      return nil, event_err
   end
   return {
      created = true,
      file_id = tostring(file_id),
      name = name,
      revision = 1,
      mime_type = mime_type,
      etag = final_etag,
   }
end

local function upsert_file(actor_user_id: string, scope_kind: string, scope_id: string, name: string, body: string, mime_type: string): table, string
   local normalized, name_err = normalize_name(name)
   if not normalized then
      return nil, name_err
   end
   local content = body or ""
   local body_sha256 = crypto.sha256_hex(content)
   local size = #content
   local version_id, put_err = s3.put_object(object_key(body_sha256), content, mime_type)
   if put_err then
      return nil, put_err
   end
   local conn, open_err = db.open()
   if not conn then
      return nil, open_err
   end
   local _, begin_err = db.exec_conn(conn, "BEGIN")
   if begin_err then
      db.close(conn)
      return nil, begin_err
   end
   local existing_rows: {db.Row} = nil
   local existing_err: string = nil
   if scope_kind == "personal" then
      existing_rows, existing_err = db.query_conn(conn, [[
         SELECT file_id, revision
         FROM files
         WHERE owner_user_id = $1
           AND name = $2
         LIMIT 1
         FOR UPDATE
      ]], scope_id, normalized)
   else
      existing_rows, existing_err = db.query_conn(conn, [[
         SELECT f.file_id, f.revision
         FROM files f
         JOIN drives d ON d.drive_id = f.drive_id
         JOIN team_members tm ON tm.team_id = d.team_id
         WHERE tm.user_id = $1
           AND d.drive_id = $2
           AND f.name = $3
         LIMIT 1
         FOR UPDATE
      ]], actor_user_id, scope_id, normalized)
   end
   if existing_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, existing_err
   end
   local existing = existing_rows and existing_rows[1] or nil
   local row, row_err = put_common(conn, actor_user_id, scope_kind, scope_id, existing, normalized, mime_type, body_sha256, size, version_id)
   if row_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, row_err
   end
   local _, commit_err = db.exec_conn(conn, "COMMIT")
   if commit_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, commit_err
   end
   db.close(conn)
   return row
end

function Files.put_personal(actor_user_id: string, name: string, body: string, mime_type: string): table, string
   return upsert_file(actor_user_id, "personal", actor_user_id, name, body, mime_type)
end

function Files.put_drive(actor_user_id: string, drive_id: string, name: string, body: string, mime_type: string): table, string
   local rows, err = db.query([[
      SELECT d.drive_id
      FROM drives d
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
      LIMIT 1
   ]], actor_user_id, drive_id)
   if err or not rows[1] then
      return nil, err or "not found"
   end
   return upsert_file(actor_user_id, "drive", drive_id, name, body, mime_type)
end

local function delete_file(actor_user_id: string, scope_kind: string, scope_id: string, name: string): boolean, string
   local normalized, name_err = normalize_name(name)
   if not normalized then
      return false, name_err
   end
   local conn, open_err = db.open()
   if not conn then
      return false, open_err
   end
   local _, begin_err = db.exec_conn(conn, "BEGIN")
   if begin_err then
      db.close(conn)
      return false, begin_err
   end
   local rows: {db.Row} = nil
   local query_err: string = nil
   if scope_kind == "personal" then
      rows, query_err = db.query_conn(conn, [[
         SELECT file_id, revision
         FROM files
         WHERE owner_user_id = $1
           AND name = $2
         LIMIT 1
         FOR UPDATE
      ]], scope_id, normalized)
   else
      rows, query_err = db.query_conn(conn, [[
         SELECT f.file_id, f.revision
         FROM files f
         JOIN drives d ON d.drive_id = f.drive_id
         JOIN team_members tm ON tm.team_id = d.team_id
         WHERE tm.user_id = $1
           AND d.drive_id = $2
           AND f.name = $3
         LIMIT 1
         FOR UPDATE
      ]], actor_user_id, scope_id, normalized)
   end
   if query_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return false, query_err
   end
   local file = rows and rows[1] or nil
   if not file then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return false, "not found"
   end
   local ok_event, event_err = insert_event(
      conn,
      file.file_id,
      actor_user_id,
      "deleted",
      scope_kind == "personal" and actor_user_id or nil,
      scope_kind == "drive" and scope_id or nil,
      nil,
      nil,
      normalized,
      file.revision
   )
   if not ok_event then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return false, event_err
   end
   local _, delete_err = db.exec_conn(conn, "DELETE FROM files WHERE file_id = $1", file.file_id)
   if delete_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return false, delete_err
   end
   local _, commit_err = db.exec_conn(conn, "COMMIT")
   if commit_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return false, commit_err
   end
   db.close(conn)
   return true
end

function Files.delete_personal(actor_user_id: string, name: string): boolean, string
   return delete_file(actor_user_id, "personal", actor_user_id, name)
end

function Files.delete_drive(actor_user_id: string, drive_id: string, name: string): boolean, string
   local rows, err = db.query([[
      SELECT d.drive_id
      FROM drives d
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
      LIMIT 1
   ]], actor_user_id, drive_id)
   if err or not rows[1] then
      return false, err or "not found"
   end
   return delete_file(actor_user_id, "drive", drive_id, name)
end

local function move_file(actor_user_id: string, name: string, drive_id: string, new_name: string): table, string
   local source_name, source_err = normalize_name(name)
   if not source_name then
      return nil, source_err
   end
   local target_name = source_name
   if new_name and new_name ~= "" then
      local normalized, target_err = normalize_name(new_name)
      if not normalized then
         return nil, target_err
      end
      target_name = normalized
   end
   local conn, open_err = db.open()
   if not conn then
      return nil, open_err
   end
   local _, begin_err = db.exec_conn(conn, "BEGIN")
   if begin_err then
      db.close(conn)
      return nil, begin_err
   end
   local target_rows, target_err = db.query_conn(conn, [[
      SELECT d.drive_id
      FROM drives d
      JOIN team_members tm ON tm.team_id = d.team_id
      WHERE tm.user_id = $1
        AND d.drive_id = $2
      LIMIT 1
   ]], actor_user_id, drive_id)
   if target_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, target_err
   end
   if not target_rows[1] then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, "not found"
   end
      local source_rows, source_query_err = db.query_conn(conn, [[
         SELECT file_id, name, revision, mime_type, etag, blob_id
         FROM files
         WHERE owner_user_id = $1
           AND name = $2
         LIMIT 1
         FOR UPDATE
      ]], actor_user_id, source_name)
      if source_query_err then
         db.exec_conn(conn, "ROLLBACK")
         db.close(conn)
         return nil, source_query_err
      end
   local source = source_rows[1]
   if not source then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, "not found"
   end
   local conflict_rows, conflict_err = db.query_conn(conn, [[
      SELECT file_id
      FROM files
      WHERE drive_id = $1
        AND name = $2
      LIMIT 1
   ]], drive_id, target_name)
   if conflict_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, conflict_err
   end
   if conflict_rows[1] then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, "destination name occupied"
   end
   local _, update_err = db.exec_conn(conn, [[
      UPDATE files
      SET owner_user_id = NULL,
          drive_id = $1,
          name = $2,
          mtime = now()
      WHERE file_id = $3
   ]], drive_id, target_name, source.file_id)
   if update_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, update_err
   end
   local ok_event, event_err = insert_event(
      conn,
      source.file_id,
      actor_user_id,
      "moved_to_drive",
      actor_user_id,
      nil,
      nil,
      drive_id,
      target_name,
      source.revision
   )
   if not ok_event then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, event_err
   end
   local _, commit_err = db.exec_conn(conn, "COMMIT")
   if commit_err then
      db.exec_conn(conn, "ROLLBACK")
      db.close(conn)
      return nil, commit_err
   end
   db.close(conn)
   return {
      file_id = tostring(source.file_id),
      name = target_name,
      revision = tonumber(source.revision) as integer,
      mime_type = source.mime_type and tostring(source.mime_type) or nil,
      etag = tostring(source.etag),
   }
end

function Files.move_personal_to_drive(actor_user_id: string, name: string, drive_id: string, new_name: string): table, string
   return move_file(actor_user_id, name, drive_id, new_name)
end

function Files.format_http_date(epoch: any): string
   return os.date("!%a, %d %b %Y %H:%M:%S GMT", tonumber(epoch) as integer)
end

function Files.response_headers(row: db.Row): {string: string}
   return {
      ["Content-Type"] = row.mime_type and tostring(row.mime_type) or "application/octet-stream",
      ["Content-Length"] = tostring(row.size),
      ["ETag"] = '"' .. tostring(row.etag) .. '"',
      ["Last-Modified"] = Files.format_http_date(row.mtime_epoch),
   }
end

function Files.summary_from_row(row: db.Row): {string: any}
   return file_summary(row)
end

function Files.metadata_from_row(row: db.Row): {string: any}
   return file_metadata(row)
end

return Files
