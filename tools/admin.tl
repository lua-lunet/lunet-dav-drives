local function sql_quote(s)
   return "'" .. (s:gsub("'", "''")) .. "'"
end

local function tmpfile()
   local name = os.tmpname()
   local f = assert(io.open(name, "w"))
   return name, f
end

local function run_capture(cmd)
   local pipe = assert(io.popen(cmd .. " 2>&1", "r"))
   local out = pipe:read("*a")
   local ok = pipe:close()
   if ok ~= true and ok ~= 0 then
      error(out, 0)
   end
   return out
end

local function psql_sql(sql)
   local path, f = tmpfile()
   f:write(sql)
   f:close()
   local cmd = "psql -X -v ON_ERROR_STOP=1 -qAt -f " .. sql_quote(path)
   local out = run_capture(cmd)
   os.remove(path)
   return out
end

local function psql_rows(sql)
   local out = psql_sql(sql)
   local rows = {}
   for line in out:gmatch("[^\r\n]+") do
      rows[#rows + 1] = line
   end
   return rows
end

local function digest_sha256(text)
   local path, f = tmpfile()
   f:write("printf %s " .. sql_quote(text) .. " | shasum -a 256 | awk '{print $1}'")
   f:close()
   local out = run_capture("sh " .. sql_quote(path))
   os.remove(path)
   return (out:gsub("%s+$", ""))
end

local function rand_secret()
   local out = run_capture("openssl rand -hex 32")
   return (out:gsub("%s+$", ""))
end

local function usage()
   io.stderr:write([[
Usage:
  admin user add <user_id> <email> <display_name>
  admin user show <user_id>
  admin team add <team_name> <drive_name>
  admin team show <team>
  admin team member-add <team> <user_id>
  admin team member-remove <team> <user_id>
  admin app-password mint <user_id> [name]
  admin app-password revoke <app_password_id>
]])
   os.exit(1)
end

local function require_args(n)
   if #arg < n then
      usage()
   end
end

local function user_add()
   require_args(5)
   local user_id = arg[3]
   local email = arg[4]
   local display_name = arg[5]
   psql_sql(
      "INSERT INTO users (user_id, email, display_name) VALUES ("
      .. sql_quote(user_id) .. ", "
      .. sql_quote(email) .. ", "
      .. sql_quote(display_name) .. ");\n"
   )
   print("added user " .. user_id)
end

local function user_show()
   require_args(3)
   local rows = psql_rows(
      "SELECT user_id || '|' || email || '|' || display_name || '|' || ctime::text || '|' || mtime::text\n"
      .. "FROM users WHERE user_id = " .. sql_quote(arg[3]) .. ";\n"
   )
   if #rows == 0 then
      io.stderr:write("user not found\n")
      os.exit(1)
   end
   local user_id, email, display_name, ctime, mtime = rows[1]:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
   print("user_id: " .. user_id)
   print("email: " .. email)
   print("display_name: " .. display_name)
   print("ctime: " .. ctime)
   print("mtime: " .. mtime)
end

local function team_add()
   require_args(4)
   local team_name = arg[3]
   local drive_name = arg[4]
   psql_sql(
      "BEGIN;\n"
      .. "WITH t AS (\n"
      .. "  INSERT INTO teams (team_name) VALUES (" .. sql_quote(team_name) .. ")\n"
      .. "  RETURNING team_id\n"
      .. ")\n"
      .. "INSERT INTO drives (team_id, drive_name)\n"
      .. "SELECT team_id, " .. sql_quote(drive_name) .. " FROM t;\n"
      .. "COMMIT;\n"
   )
   print("added team " .. team_name)
end

local function team_show()
   require_args(3)
   local rows = psql_rows(
      "SELECT t.team_id || '|' || t.team_name || '|' || d.drive_id || '|' || d.drive_name\n"
      .. "FROM teams t JOIN drives d ON d.team_id = t.team_id\n"
      .. "WHERE t.team_name = " .. sql_quote(arg[3]) .. ";\n"
   )
   if #rows == 0 then
      io.stderr:write("team not found\n")
      os.exit(1)
   end
   local team_id, team_name, drive_id, drive_name = rows[1]:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
   print("team_id: " .. team_id)
   print("team_name: " .. team_name)
   print("drive_id: " .. drive_id)
   print("drive_name: " .. drive_name)
end

local function member_add()
   require_args(4)
   local team_name = arg[3]
   local user_id = arg[4]
   psql_sql(
      "INSERT INTO team_members (user_id, team_id)\n"
      .. "SELECT " .. sql_quote(user_id) .. ", team_id FROM teams WHERE team_name = " .. sql_quote(team_name) .. ";\n"
   )
   print("added membership " .. user_id .. " -> " .. team_name)
end

local function member_remove()
   require_args(4)
   local team_name = arg[3]
   local user_id = arg[4]
   psql_sql(
      "DELETE FROM team_members\n"
      .. "USING teams\n"
      .. "WHERE team_members.team_id = teams.team_id\n"
      .. "  AND teams.team_name = " .. sql_quote(team_name) .. "\n"
      .. "  AND team_members.user_id = " .. sql_quote(user_id) .. ";\n"
   )
   print("removed membership " .. user_id .. " -> " .. team_name)
end

local function app_password_mint()
   require_args(3)
   local user_id = arg[3]
   local name = arg[4] or "app"
   local secret = rand_secret()
   local digest = digest_sha256(secret)
   local rows = psql_rows(
      "INSERT INTO app_passwords (user_id, name, secret_digest)\n"
      .. "VALUES (" .. sql_quote(user_id) .. ", " .. sql_quote(name) .. ", " .. sql_quote(digest) .. ")\n"
      .. "RETURNING app_password_id;\n"
   )
   if #rows == 0 then
      io.stderr:write("failed to mint app password\n")
      os.exit(1)
   end
   print("app_password_id: " .. rows[1])
   print("secret: " .. secret)
end

local function app_password_revoke()
   require_args(3)
   local app_password_id = arg[3]
   psql_sql("DELETE FROM app_passwords WHERE app_password_id = " .. sql_quote(app_password_id) .. ";\n")
   print("revoked app_password_id " .. app_password_id)
end

if #arg < 2 then
   usage()
end

local cmd1 = arg[1]
local cmd2 = arg[2]
if cmd1 == "user" and cmd2 == "add" then
   user_add()
elseif cmd1 == "user" and cmd2 == "show" then
   user_show()
elseif cmd1 == "team" and cmd2 == "add" then
   team_add()
elseif cmd1 == "team" and cmd2 == "show" then
   team_show()
elseif cmd1 == "team" and cmd2 == "member-add" then
   member_add()
elseif cmd1 == "team" and cmd2 == "member-remove" then
   member_remove()
elseif cmd1 == "app-password" and cmd2 == "mint" then
   app_password_mint()
elseif cmd1 == "app-password" and cmd2 == "revoke" then
   app_password_revoke()
else
   usage()
end
