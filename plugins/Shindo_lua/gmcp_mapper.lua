--All the required modules loaded here
require("luabins")
require("serialize")
local version = "0.1.1"

-- Colour Stuff
local ansi = "\27["
local dred = "\27[0;31m"
local dgreen = "\27[0;32m"
local dyellow = "\27[0;33m"
local dblue = "\27[0;34m"
local dmagenta = "\27[0;35m"
local dcyan = "\27[0;36m"
local dwhite = "\27[0;37m"
local bred = "\27[31;1m"
local bgreen = "\27[32;1m"
local byellow = "\27[33;1m"
local bblue = "\27[34;1m"
local bmagenta = "\27[35;1m"
local bcyan = "\27[36;1m"
local bwhite = "\27[37;1m"

-- Strip all color codes from a string
function strip_colours (s)
  s = s:gsub("@@", "\0")  -- change @@ to 0x00
  s = s:gsub("@%-", "~")    -- fix tildes (historical)
  s = s:gsub("@x%d?%d?%d?", "") -- strip valid and invalid xterm color codes
  s = s:gsub("@.([^@]*)", "%1") -- strip normal color codes and hidden garbage
  return (s:gsub("%z", "@")) -- put @ back (has parentheses on purpose)
end -- strip_colours

-- This Section handles all the database calls to open close etc
require("lsqlite3")
dbPath = GetPluginInstallDirectory().."/Shindo_DB/aardwolf.db"
local db = assert(sqlite3.open(dbPath))

forced_opened = false
force_nests = 0
function forceOpenDB()
  force_nests = force_nests+1
  if not db:isopen() then
    forced_opened = true
    -- print("Forcing open")
    db = assert (sqlite3.open(dbPath))
  end
end

function closeDBifForcedOpen()
  force_nests = force_nests-1
  if forced_opened and (force_nests <= 0) then
    force_nests = 0
    forced_opened = false
    -- print("Forcing closed")
    db:close()
  end
end

function DBisOpen(warn)
  if db:isopen() then
    return true
  end
  if warn then
    Note("MAPPER ERROR: The map database is closed for safety when not connected to Aardwolf.\n"
    .."If you want to change the DB, please connect to the game.")
  end
  return false
end

function dbnrowsWRAPPER(query)
  forceOpenDB()
  iter,vm,i = db:nrows(query)
  local function itwrap(vm, i)
    retval = iter(vm, i)
    if not retval then
      closeDBifForcedOpen()
      return nil
    end
    return retval
  end
  return itwrap,vm,i
end

function dbCheckExecute(query)
  forceOpenDB()
  local code = db:exec(query)
  dbcheck(code, query)
  closeDBifForcedOpen()
end

function dbcheck (code, query)
  if code ~= sqlite3.OK and    -- no error
    code ~= sqlite3.ROW and   -- completed OK with another row of data
    code ~= sqlite3.DONE then -- completed OK, no more rows
    local err = db:errmsg ()  -- the rollback will change the error message
    err = err.."\n\nCODE: "..code.."\nQUERY: "..query.."\n"
    db:exec ("ROLLBACK")      -- rollback any transaction to unlock the database
    error (err, 3)            -- show error in caller's context
  end -- if
end -- dbcheck
-- end of Database Handling

--Local variables
local rooms = {}
local room_not_in_database = {}
local areas = {}
local environments = {}
local user_terrain_colour = {}
local performing_maintenance = false
local mytier = 0
local mylevel = 1
local speedwalk_prefix = "run"
local max_depth = 200
local RoomListTable = {}
local NumberOfFoundRooms = 0
local CurrentFoundRoom = 0
local shownotes = 1

local bounce_recall = nil
local bounce_portal = nil

local valid_direction = {
  n = "n",
  s = "s",
  e = "e",
  w = "w",
  u = "u",
  d = "d",
  N = "n",
  S = "s",
  E = "e",
  W = "w",
  U = "u",
  D = "d",
  north = "n",
  south = "s",
  east = "e",
  west = "w",
  up = "u",
  down = "d"
}  -- end of valid_direction

local directions = {
  n=true,
  s=true,
  e=true,
  w=true,
  u=true,
  d=true
}

local expand_direction = {
  n = "north",
  s = "south",
  e = "east",
  w = "west",
  u = "up",
  d = "down",
}  -- end of expand_direction

local convert_direction = {
  north = "n",
  south = "s",
  east = "e",
  west = "w",
  up = "u",
  down = "d"
}

-- for calculating one-way paths
local inverse_direction = {
  n = "s",
  s = "n",
  e = "w",
  w = "e",
  u = "d",
  d = "u"
}  -- end of inverse_direction

function fixbool (b)
  if b then
    return 1
  else
    return 0
  end -- if
end -- fixbool

function fixsql (s)
  if s then
    return "'" .. (string.gsub (s, "'", "''")) .. "'" -- replace single quotes with two lots of single quotes
  else
    return "NULL"
  end -- if
end -- fixsql

-- Create Database Variables --
count = 0
roomcount = 0
endroomcount = 0
areacount = 0
coordcount = 0
directioncount = 0
environmentcount = 0

-- This Section contains all the functions we need to manipulate strings, numbers and tables
function compareTables(primary, secondary)
  for i,v in pairs(primary) do
    if secondary[i] ~= v then
      return false
    end
  end
  return true
end

function nilToStr(n)
  return (((n ~= nil) and tostring(n)) or "")
end

function positive_integer_check(input)
  input = tonumber(input)
  if input == nil or input < 0 or input % 1 ~= 0 then
    return false
  else
    return true
  end
end

function level_check(input)
  input = tonumber(input)
  if positive_integer_check(input) == false then
    return false
  else
    return true
  end
end

function Trim(ToTrim)
  return (ToTrim:gsub("^%s*(.-)%s*$", "%1"))
end

function tprint (t, indent, done)
  -- show strings differently to distinguish them from numbers
  local function show (val)
    if type (val) == "string" then
      return '"' .. val .. '"'
    else
      return tostring (val)
    end -- if
  end -- show
  if type (t) ~= "table" then
    Note("tprint got " .. type (t))
    return
  end -- not table
  -- entry point here
  done = done or {}
  indent = indent or 0
  for key, value in pairs (t) do
    Note(string.rep (" ", indent)) -- indent it
    if type (value) == "table" and not done [value] then
      done [value] = true
      Note(show (key).. " : \n");
      tprint (value, indent + 2, done)
    else
      Note(show (key).. " = ".. show (value).."\n")
    end
  end
end

function positive_integer_check(input)
  input = tonumber(input)
  if input == nil or input < 0 or input % 1 ~= 0 then
    return false
  else
    return true
  end
end

-- end of functions required to handle data

flagType = nil
function mark_prison_flag()
  if (flagType ~= nil) and (room_at_bounceback ~= nil) and (rooms[room_at_bounceback] ~= nil) then
    if (current_room == room_at_bounceback) then
      if (flagType == "noportal") and (rooms[room_at_bounceback].noportal ~= 1) then
        Note('Marking room (', room_at_bounceback, ') noportal')
        rooms[room_at_bounceback].noportal = 1
      end
      if (flagType == "norecall") and (rooms[room_at_bounceback].norecall ~= 1) then
        Note('Marking room (', room_at_bounceback, ') norecall')
        rooms[room_at_bounceback].norecall = 1
      end
      dbCheckExecute("BEGIN TRANSACTION;")
      save_room_to_database(room_at_bounceback, rooms[room_at_bounceback])
      dbCheckExecute("COMMIT;")
    else
      Note("You were moving too quickly (or moved while blind?) to safely flag your room as "..flagType..".\n")
    end
  end
  flagType = nil
end

function map_bounceportal (name, line, wildcards)
  wildcards[1] = Trim(wildcards[1])
  if wildcards[1]=="" then
    if bounce_portal and bounce_portal.dir then
      Note("\nBOUNCEPORTAL: Currently set to '"..bounce_portal.dir.."'")
    else
      Note("\nBOUNCEPORTAL: Not currently set.")
    end
    return
  elseif wildcards[1]=="clear" then
    bounce_portal = nil
    Note("\nBOUNCEPORTAL: cleared.")
    dbCheckExecute(string.format("DELETE from storage where name is %s;", fixsql("bounce_portal")))
    return
  end

  local pnum = tonumber(wildcards[1])

  if pnum==nil then
    Note("\nBOUNCEPORTAL FAILED: The required parameter for mapper bounceportal is <portal_index>.\n"..
    "Current portal indexes can be found in the 'mapper portals' output.\n")
    return
  end

  local count = 1
  local found = false
  for row in dbnrowsWRAPPER(PORTALS_QUERY) do
    if count == pnum then
      if row.fromuid == "*" then
        bounce_portal = {dir=row.dir, uid=row.touid}
        Note("\nBOUNCEPORTAL: Set portal #"..count.." ("..row.dir..") as the bounce portal for portal-friendly norecall rooms.")
        dbCheckExecute(string.format("INSERT OR REPLACE INTO storage (name, data) VALUES (%s,%s);", 
        fixsql("bounce_portal"), 
        fixsql(serialize.save("bounce_portal"))))
      else
        Note("\nBOUNCEPORTAL FAILED: Portal #"..pnum.." is a recall portal.\n"..
        "You must choose a mapper portal that does not use either the recall or home commands for the bounce portal.")
      end
      found = true
    end
    count = count + 1
  end
  if found == false then
    Note(string.format("\nBOUNCEPORTAL FAILED: Did not find index %s in the list of portals. Try 'mapper portals' to see the list.\n",
    pnum))
  end
end

PORTALS_QUERY = [=[select rooms.area,rooms.name,exits.touid,exits.fromuid,exits.dir,exits.level from exits left outer join rooms on rooms.uid=exits.touid where exits.fromuid in ('*','**') order by rooms.area,exits.touid]=]

function map_bouncerecall (recallIndex)
  recallIndex = Trim(recallIndex) or ""
  if recallIndex == "" then
    if bounce_recall and bounce_recall.dir then
      Note("BOUNCERECALL: Currently set to '"..bounce_recall.dir.."'\n")
    else
      Note("BOUNCERECALL: Not currently set.\n")
    end
    return
  elseif recallIndex == "clear" then
    bounce_recall = nil
    Note("BOUNCERECALL: cleared.\n")
    dbCheckExecute(string.format("DELETE from storage where name is %s;", fixsql("bounce_recall")))
    return
  end

  local pnum = tonumber(recallIndex)
  if pnum==nil then
    Note("\nBOUNCERECALL FAILED: The required parameter for mapper bouncerecall is <recall_portal_index>.\n"..
    "Current portal indexes can be found in the 'mapper portals' output.\n")
    return
  end

  local count = 1
  local found = false
  for row in dbnrowsWRAPPER(PORTALS_QUERY) do
    if count == pnum then
      if row.fromuid == "**" then
        bounce_recall = {dir=row.dir, uid=row.touid}
        Note("BOUNCERECALL: Set recall portal #"..pnum.." ("..row.dir..") as the bounce recall for recall-friendly noportal rooms.\n")
        --[[
        dbCheckExecute(string.format("INSERT OR REPLACE INTO storage (name, data) VALUES (%s,%s);",
        fixsql("bounce_recall"), 
        fixsql(serialize.save("bounce_recall"))))
        --]]
      else
        Note("BOUNCERECALL FAILED: Portal #"..pnum..
        " is not a recall portal.\n You must choose a mapper portal that uses either the recall or home commands for the bounce recall.\n")
      end
      found = true
    end
    count = count + 1
  end
  if found == false then
    Note(string.format("BOUNCERECALL FAILED: Did not find index %s in the list of portals.\n Try .MapperPortalList to see the list.\n", pnum))
  end
end

-- check for consistency mistakes with bounce portal/recall flags
function check_bounce_consistency()
  local bounce_portal_orphaned = (bounce_portal ~= nil)
  local bounce_recall_orphaned = (bounce_recall ~= nil)
  local inconsistent_recall_flag = nil
  local inconsistent_portal_flag = nil
  if (bounce_portal_orphaned or bounce_recall_orphaned) then
    local row_id = 1
    for row in dbnrowsWRAPPER(PORTALS_QUERY) do
      if (bounce_portal_orphaned and (row.dir==bounce_portal.dir)) then
        if (row.fromuid == "*") then
          bounce_portal_orphaned = false
        else
          inconsistent_portal_flag = row_id
        end
      end
      if (bounce_recall_orphaned and (row.dir==bounce_recall.dir)) then
        if (row.fromuid == "**") then
          bounce_recall_orphaned = false
        else
          inconsistent_recall_flag = row_id
        end
      end
      row_id = row_id+1
    end
    if bounce_portal_orphaned then
      if inconsistent_portal_flag then
        Note("BOUNCE PORTAL WARNING: Your designated bounce portal #"..inconsistent_portal_flag.." '"..bounce_portal.dir.."' was flagged as a recall, which is inconsistent with correct functioning.\n")
      else
        Note("BOUNCE PORTAL WARNING: Your designated bounce portal '"..bounce_portal.dir.."' did not exist in your mapper portals list.\n")
      end
      Note("BOUNCE PORTAL WARNING: Your mapper bounceportal setting will be cleared. If this is undesired, please correct the aforementioned error and set it again.\n")
      map_bounceportal(nil, nil, {"clear"})
    end
    if bounce_recall_orphaned then
      if inconsistent_recall_flag then
        Note("BOUNCE RECALL WARNING: Your designated bounce recall #"..inconsistent_recall_flag.." '"..bounce_recall.dir.."' was flagged as a non-recall portal, which is inconsistent with correct functioning.\n")
      else
        Note("BOUNCE RECALL WARNING: Your designated bounce recall '"..bounce_recall.dir.."' did not exist in your mapper portals list.\n")
      end
      Note("BOUNCE RECALL WARNING: Your mapper bouncerecall setting will be cleared. If this is undesired, please correct the aforementioned error and set it again.\n")
      map_bouncerecall(nil, nil, {"clear"})
    end
  end
end

function norecall_room()
  if (current_room ~= nil) and (rooms[current_room] ~= nil) and (rooms[current_room].norecall ~= 1) then
    flagType = "norecall"
    check_blindness()
  end
end

function noportal_room()
  if (current_room ~= nil) and (rooms[current_room] ~= nil) and (rooms[current_room].noportal ~= 1) then
    flagType = "noportal"
    check_blindness()
  end
end

function check_blindness()
  room_at_bounceback = current_room
  Note("Checking for blindness flag before marking this room "..flagType.."...\n")
  blinded = true
  Send_GMCP_Packet("request room")
  EnableTrigger("blindness_watch", true)
  SendToServer("aflags")
end

function manual_norecall(room_id, norecall)
  local room = load_room_from_database(room_id)
  if room ~= nil then
    room.norecall = norecall
    save_room_to_database(room_id, room)
    Note("No-recall flag "..(norecall == 1 and "set on" or "removed from").." room "..room_id..".\n")
  else
    Note("NORECALL ERROR: Room "..room_id.." is not in the database.\n")
  end
end

function manual_noportal(room_id, noportal)
  local room = load_room_from_database(room_id)
  if room ~= nil then
    room.noportal = noportal
    save_room_to_database(room_id, room)
    Note("No-portal flag "..(noportal == 1 and "set on" or "removed from").." room "..room_id..".\n")
  else
    Note("NOPORTAL ERROR: Room "..room_id.." is not in the database.\n")
  end
end

function set_norecall_thisroom(status)
  status = tonumber(status)
  if not ((status == 0) or(status == 1) ) then
    Note("Please set this with a value of 0 / 1, for false / true.\n") 
    return
  end
  local room = rooms[current_room]
  if room ~= nil then
    room.norecall = status
    save_room_to_database(current_room, room)
    Note("No-recall flag "..(status == 1 and "set on" or "removed from").." room "..current_room..".\n")
  else
    Note("NOPORTAL ERROR: Room "..current_room.." is not in the database.\n")
  end

end

function set_noportal_thisroom(status)
  status = tonumber(status)
  if not ((status == 0) or(status == 1) ) then
    Note("Please set this with a value of 0 / 1, for false / true.\n") 
    return
  end
  local room = rooms[current_room]
  if room ~= nil then
    room.noportal = status
    save_room_to_database(current_room, room)
    Note("No-portal flag "..(status == 1 and "set on" or "removed from").." room "..current_room..".\n")
  else
    Note("NOPORTAL ERROR: Room "..current_room.." is not in the database.\n")
  end
end

function map_portal_delete (portalname)
  local keywords = portalname
  local target_index = nil
  if string.sub(keywords,1,1) == "#" and type(tonumber(string.sub(keywords,2)))=="number" then
    target_index = tonumber(string.sub(keywords,2))
    local count = 0
    local found = false
    for row in dbnrowsWRAPPER(PORTALS_QUERY) do
      count = count + 1
      if count == target_index then
        keywords = row.dir
        found = true
      end
    end
    if found == false then
      Note(string.format("\nDELETE FAILED: Did not find portal #%s in the list of portals. Try 'mapper portals' to see the list.\n", 
      target_index))
      return
    end
  end

  local portal_exists = false
  for n in dbnrowsWRAPPER (string.format ("SELECT * FROM exits WHERE fromuid in ('*','**') AND dir = %s", fixsql(keywords))) do
    portal_exists = true
  end

  if portal_exists then
    Note(string.format("Deleted mapper portal"..(((target_index ~= nil) and " index #"..target_index) or "").." with keywords '%s'.\n",
    keywords))
  else
    Note(string.format("DELETE FAILED: Did not find a mapper portal with keywords '%s'.\n",
    keywords))
  end

  query = string.format("DELETE FROM exits WHERE fromuid in ('*','**') AND dir = %s;",
  fixsql(keywords))
  dbCheckExecute(query)
  check_bounce_consistency()
end -- map_portal_delete

-- map_portal_list function contributed by Spartacus
function map_portal_list ()
  local line
  local cmd
  local txt
  -- show portals stored in the exits table
  local hl = "+-----+------------+----------------------+-------+----------------------+-----+\n"
  local hr = "|   # | area       | room name            |  vnum | portal commands      | lvl |\n"

  Note("\n"..hl)
  Note(hr)
  Note(hl)

  local count = 0
  for row in dbnrowsWRAPPER(PORTALS_QUERY) do
    count = count + 1
    line = string.format("|"..((((bounce_portal and (row.dir==bounce_portal.dir)) or (bounce_recall and (row.dir==bounce_recall.dir))) and "*") or " ").."%+3.3s | %-10.10s | %-20.20s | %+5.5s | %-20.20s | %+3.3s |\n",
    count,
    row.area or "N/A",
    row.name or "N/A"
    , row.touid,
    row.dir,
    row.level)
    --    if row.level <= mylevel+(mytier*10) then
    --      -- make the whole line clickable
    --      cmd = "mapper goto " .. row.touid
    --      txt = "click here to run to " .. (row.name or "N/A") .. "\n[ " .. row.dir .. " ]"
    --      Hyperlink(cmd, line, txt, (((row.fromuid=="*") and "") or "red"), "", false, NoUnderline_hyperlinks)
    --      Note()
    --    else
    --      Note(line)
    --    end -- if row.level
    Note( line )
  end -- for row (portals query)
  Note(hl)
  Note("|* Indicates designated bouncerecall/bounceportal |\n")
  Note("+-------------------------------------------------+\n")

end -- map_portal_list

function load_room_from_database (uid)
  local room
  local u = tostring(uid)
  assert (uid, "No UID supplied to load_room_from_database")

  -- if not in database, don't look again
  if room_not_in_database [u] then
    return nil
  end -- no point looking

  for row in dbnrowsWRAPPER(string.format ("SELECT * FROM rooms WHERE uid = %s", fixsql (u))) do
    room = {
      name = row.name,
      area = row.area,
      building = row.building,
      terrain = row.terrain,
      info = row.info,
      notes = row.notes,
      x = row.x or 0,
      y = row.y or 0,
      z = row.z or 0,
      noportal = row.noportal,
      norecall = row.norecall,
      exits = {},
      exit_locks = {},
      ignore_exits_mismatch = (row.ignore_exits_mismatch == 1)
    }

    for exitrow in dbnrowsWRAPPER(string.format ("SELECT * FROM exits WHERE fromuid = %s", fixsql (u))) do
      room.exits [exitrow.dir] = tostring (exitrow.touid)
      room.exit_locks [exitrow.dir] = tostring(exitrow.level)
    end -- for each exit

  end   -- finding room

  if room then
    if not rooms then
      -- this shouldn't even be possible. what the hell.
      rooms = {}
    end
    rooms [u] = room
    for row in dbnrowsWRAPPER(string.format ("SELECT * FROM bookmarks WHERE uid = %s", fixsql (u))) do
      rooms [u].notes = row.notes
    end   -- finding room

    return room
  end -- if found

  -- room not found in database
  room_not_in_database [u] = true
  return nil

end -- load_room_from_database

function ExecuteWithWaits(cexit_command)
  wait.make (function()
    SendNoEcho("echo {begin running}")
    local partial_cexit_command = cexit_command
    local strbegin,strend = string.find(partial_cexit_command,";?wait%(%d*.?%d+%);?")
    while strbegin do
      strbegin,strend = string.find(partial_cexit_command,";?wait%(%d*.?%d+%);?")
      if strbegin ~= nil and strbegin ~= 1 then
        Execute(string.sub(partial_cexit_command,1,strbegin-1))
      end
      if strend then
        local wait_time = tonumber(string.match(string.sub(partial_cexit_command,strbegin,strend),"wait%((%d*.?%d+)%)"))
        SendNoEcho("echo {mapper_wait}wait("..wait_time..")")
        line, wildcards = wait.regexp("^\\{mapper_wait\\}wait\\(([0-9]*\\.?[0-9]+)\\)",nil,trigger_flag.OmitFromOutput)
        Note("CEXIT WAIT: waiting for "..wait_time.." seconds before continuing.")
        BroadcastPlugin(999, "repaint")
        wait.time(wait_time)
        partial_cexit_command = string.sub(partial_cexit_command, strend+1)
      end
    end
    Execute(partial_cexit_command)
    SendNoEcho("echo {end running}")
  end)
end

function custom_exits_delete ()
  local query = string.format("delete from exits where fromuid=%s and dir not in ('n','s','e','w','d','u');", fixsql(current_room))
  dbCheckExecute(query)
  for k,v in pairs(rooms[current_room].exits) do
    if not directions[k] then
      Note(string.format("Found custom exit \"%s\" to room %s \"%s\".\n",
      k,
      rooms[current_room].exits[k],
      rooms[rooms[current_room].exits[k]].name))
      --Note("Found custom exit \""..k.."\" to room "..rooms[current_room].exits[k].." \""..rooms[rooms[current_room].exits[k]].name.."\"")
      rooms[current_room].exits[k] = nil
      rooms[current_room].exit_locks[k] = nil
    end
  end
  Note("Removed custom exits from the current room.")
end

-- this function adds a command to open a door go in its direction and then close it unless 
-- specificily instructed not to.
-- It uses the gmcp information from the current room to determine the destination room.
function custom_exits_add_door (doordirection)
  local _, _, DoorDir, LeaveDoorOpen = string.find(doordirection,"([nNsSeEwWuUdD])%s?(%d?)")
  if DoorDir == nil then
    Note("This function requires a direction as part of the input, n, e, s, w, u or d.\n")
    return
  end
  room = rooms[current_room]
  cexit_dest = room.exits[valid_direction[DoorDir]]
  if LeaveDoorOpen == "1" then
    cexit_command = string.format("%s;%s",
    DoorDir,
    DoorDir)
  else
    cexit_command = string.format("open %s;%s;close %s",
    DoorDir,
    DoorDir,
    inverse_direction[DoorDir])
  end
  local query =
  --Note(
  string.format ("INSERT OR REPLACE INTO exits (dir, fromuid, touid) VALUES (%s, %s, %s);",
  fixsql (cexit_command),  -- direction (eg. "n")
  fixsql (current_room),  -- from current room
  fixsql (cexit_dest) -- destination room
  )
  --.."\n")
  dbCheckExecute(query)
  SendToServer(cexit_command)
  ---[[
  Note(string.format("Adding custom exit:\"%s\" from %s to %s.\n",
  fixsql (cexit_command),  -- direction (eg. "n")
  fixsql (current_room),  -- from current room
  fixsql (cexit_dest) -- destination room
  ))
  --]]
end -- custom_exits_add_door

-- custom_exits_add function contributed by Spartacus
function custom_exits_add (customexitcmd)
  local remap = {
    n = "north",
    w = "west",
    s = "south",
    e = "east",
    u = "up",
    d = "down"
  }
  local _, _, cexit_dest, cexit_command = string.find(customexitcmd,"(%d+)%s(.*)")
  local cexit_start

  if cexit_dest == "" then
    Note("we need a destination uid")
    return
  end
  if cexit_command == "" then
    Note("Nothing to do!")
    return
  end -- if cexit_command

  if current_room then
    cexit_start = current_room
  else
    Note("CEXIT FAILED: No room received from the mud yet. Try using the 'LOOK' command first.")
    return
  end -- if current_room

  if cexit_start == "-1" then
    Note ("CEXIT FAILED: You cannot link custom exits from unmappable rooms.")
    return
  end
  dbCheckExecute(string.format ("INSERT OR REPLACE INTO exits (dir, fromuid, touid) VALUES (%s, %s, %s);",
  fixsql (cexit_command),  -- direction (eg. "n")
  fixsql (cexit_start),  -- from current room
  fixsql (cexit_dest) -- destination room
  ))

  SendToServer(cexit_command)
end -- custom_exits_add

last_area_requested = ""
function save_room_to_database (uid,room)
  assert (uid, "No UID supplied to save_room_to_database")
  local area_exists = false
  for n in dbnrowsWRAPPER (string.format ("SELECT uid FROM areas where uid=%s", fixsql(room.area))) do
    area_exists = true
  end
  if not area_exists then
    if last_area_requested ~= room.area then
      last_area_requested = room.area
      Send_GMCP_Packet("request area")
    end
    return false
  end

  dbCheckExecute(string.format (
  "INSERT OR REPLACE INTO rooms (uid, name, terrain, info, x, y, z, area, noportal, norecall, ignore_exits_mismatch) VALUES (%s, %s, %s, %s, %i, %i, %i, %s, %d, %d, %d);",
  fixsql (uid),
  fixsql (room.name),
  fixsql (room.terrain),
  fixsql (room.info),
  room.x or 0, room.y or 0, room.z or 0, fixsql(room.area),
  room.noportal or 0,
  room.norecall or 0,
  room.ignore_exits_mismatch and 1 or 0
  ))

  local exists = false
  for n in dbnrowsWRAPPER(string.format ("SELECT * FROM rooms_lookup WHERE uid = %s", fixsql(uid))) do
    exists = true
  end
  -- don't add multiple times, maintaining backwards database compatibility (there's no uniqueness constraint on rooms_lookup.uid)
  if not exists then
    dbCheckExecute(string.format ("INSERT INTO rooms_lookup (uid, name) VALUES (%s, %s);", fixsql(uid), fixsql(room.name)))
  else
    dbCheckExecute(string.format ("DELETE FROM rooms_lookup WHERE uid = %s",fixsql(uid)))
    dbCheckExecute(string.format ("INSERT INTO rooms_lookup (uid, name) VALUES (%s, %s);", fixsql(uid), fixsql(room.name)))
  end

  room_not_in_database [uid] = nil

  if show_database_mods then
    Note("Added room", uid, "to database. Name:", room.name, "\n")
  end -- if
  return true
end -- function save_room_to_database

BASE_CEXIT_DELAY = 2

function change_cexit_delay(temp_delay)
  temp_cexit_delay = tonumber(temp_delay)
  if temp_cexit_delay == nil or temp_cexit_delay < BASE_CEXIT_DELAY or temp_cexit_delay > 40 then
    Note("CEXIT_DELAY FAILED: Invalid delay given ("..temp_delay.."). Must be a number from 2 to 40.\n")
    temp_cexit_delay = nil
  end
  Note("CEXIT_DELAY: The next mapper custom exit will have ".. (temp_cexit_delay or BASE_CEXIT_DELAY) .." seconds to complete.\n")
end

function map_areas (areas)
  local line = ""
  local query = ""
  local area = areas or ""
  local count = 0

  local hr = "| keyword    | Area Name                               | Explored |\n"
  local hl = "+------------+-----------------------------------------+----------+\n"
  local fmt = "| %10.10s | %-39.39s | %8.8s |\n"
  if area == "" then
    query = "SELECT uid, name FROM areas WHERE uid in (SELECT DISTINCT area FROM rooms) ORDER BY name;"
    intro = "\nThe following areas have been mapped:\n"
  else
    query = string.format("SELECT uid, name FROM areas WHERE name LIKE %s AND uid in (SELECT DISTINCT area FROM rooms) ORDER BY name;", fixsql("%"..area.."%"))
    intro = string.format("\nThe following areas matching '%s' have been mapped:\n",area)
  end -- if area

  Note(intro)
  Note(hl)
  Note(hr)
  Note(hl)
  local total_explored = 0
  for row in dbnrowsWRAPPER(query) do
    query2 = string.format("SELECT count(uid) as count FROM rooms WHERE area=%s;",fixsql(row.uid))
    for row2 in dbnrowsWRAPPER(query2) do
      line = string.format(fmt,row.uid, row.name, row2.count)
      total_explored = total_explored + row2.count
    end
    Note(line)
    count = count + 1
  end

  Note(hl)
  line = string.format ("Found %s areas containing %s rooms mapped.\n", count, total_explored)
  Note(line)
end

function show_this_room ()
  local room = rooms[current_room]
  if room ~= nil then
    Note("Details about this room:\n")
    Note("+---------------------------+\n")
    Note("Name: "..(room.name or "").."\n")
    Note("ID: "..(current_room or "").."\n")
    Note("Area: "..(room.area or "").."\n")
    Note("Terrain: "..(room.terrain or "").."\n")
    Note("Info: "..(room.info or "").."\n")
    Note("Notes: "..(room.notes or "").."\n")
    local flags = ''
    if room.noportal == 1 then
      flags = flags .. ' noportal'
    end
    if room.norecall == 1 then
      flags = flags .. ' norecall'
    end
    Note("Flags:".. flags.. "\n")
    Note("Exits: \n")
    tprint(room.exits,2)
    Note("Exit locks: \n")
    if room.exit_locks then
      tprint(room.exit_locks,2)
    else
      Note("none\n")
    end
    if (room.ignore_exits_mismatch) then mismatch = "yes" else mismatch = "no" end
    Note(string.format("Ignore exits mismatch: %s.\n", mismatch))
    --Note("Ignore exits mismatch: ".. if (room.ignore_exits_mismatch) then "yes" else "no" end.. "\n")
    Note("+---------------------------+\n")
  else
    Note("THISROOM ERROR: You need to type 'LOOK' first to initialize the mapper before trying to get room information.\n")
  end
end -- show_this_room

function room_edit_note (newnotes)
  if current_room ~= nil then
    uid = current_room
    room = rooms[current_room]
  end

  if uid == nil then -- still nothing?
    print("No room received from the mud yet. Try using the 'LOOK' command first.")
    return
  end

  local notes, found

  for row in dbnrowsWRAPPER(string.format ("SELECT * FROM bookmarks WHERE uid = %s", fixsql (uid))) do
    notes = row.notes
    found = true
  end   -- finding room

  if newnotes == nil or newnotes == "" then
    if found then
      newnotes = utils.inputbox ("Modify room comment (clear it to delete from database)", room.name, notes)
    else
      newnotes = utils.inputbox ("Enter room comment (creates a note for this room)", room.name, notes)
    end -- if
  end

  if not newnotes then
    return
  end -- if cancelled

  if newnotes == "" then
    if not found then
      Note("No comment entered, note not saved.\n")
      return
    else
      dbCheckExecute(string.format (
      "DELETE FROM bookmarks WHERE uid = %s;",
      fixsql (uid)
      ))
      Note("Notefor room", uid, "deleted. Was previously:", notes, "\n")
      rooms [uid].notes = nil
      return
    end -- if
  end -- if

  if notes == newnotes then
    return -- no change made
  end -- if

  if found then
    dbCheckExecute(string.format (
    "UPDATE bookmarks SET notes = %s WHERE uid = %s;",
    fixsql (newnotes),
    fixsql (uid)
    ))
    Note("Notefor room", uid, "changed to:", newnotes)
  else
    dbCheckExecute(string.format (
    "INSERT INTO bookmarks (uid, notes) VALUES (%s, %s);",
    fixsql (uid),
    fixsql (newnotes)
    ))
    Note("Noteadded to room", uid, ":", newnotes, "\n")
  end -- if

  rooms [uid].notes = newnotes
end -- room_edit_note

function update_gmcp_area(GMCPAreaData)
  local areaid = GMCPAreaData.id
  local areaname = GMCPAreaData.name
  local texture = GMCPAreaData.texture
  local color = GMCPAreaData.col
  local x, y, z = GMCPAreaData.x, GMCPAreaData.y, GMCPAreaData.z
  local flags = GMCPAreaData.flags or ""

  dbCheckExecute (string.format (
  "REPLACE INTO areas (uid, name, texture, color, flags) VALUES (%s, %s, %s, %s, %s);",
  fixsql (areaid),
  fixsql (areaname),
  fixsql (texture),
  fixsql (color),
  fixsql (flags)
  ))

  area = {
    name = areaname,
    texture = texture,
    color = color,
    virtual = (flags:find("virtual") ~= nil)
  }
  areas [areaid] = area

  Send_GMCP_Packet("request room") -- Just got a new area update. Now check for our room again.
  return
end

function save_room_exits(uid,GMCPRoomData)
  if rooms[uid] == nil then
    return
  end
  if GMCPRoomData.exits ~= nil then
    for dir,touid in pairs(GMCPRoomData.exits) do
      if dir then
        dbCheckExecute (string.format ([[
        INSERT OR REPLACE INTO exits (dir, fromuid, touid)
        VALUES (%s, %s, %s);
        ]],
        fixsql (dir),  -- direction (eg. "n")
        fixsql (uid),  -- from current room
        fixsql (touid) -- destination room
        ))

        if show_database_mods then
          Note("Added exit: ", dir, "from room: ",uid, "to room: ", touid, " to database.\n")
        end -- if

        if rooms[uid].exits[dir] ~= touid then
          rooms[uid].exit_locks[dir] = "0"
        end
        rooms[uid].exits[dir] = touid
      else
        Note("Cannot make sense of:", exit, "\n")
      end -- if can decode
    end -- for each exit
  end -- have exits.
end -- save_room_exits

function update_gmcp_sectors(GMCPSectorData)
  dbCheckExecute("BEGIN TRANSACTION;")
  dbCheckExecute ("DELETE FROM environments;")
  for i,v in pairs(gmcp_sectors_list.sectors) do
    dbCheckExecute( string.format([[
    INSERT OR REPLACE INTO environments VALUES (%s,%s,%s);
    ]], v.id, fixsql(v.name), v.color))
  end
  dbCheckExecute("COMMIT;")

  for row in dbnrowsWRAPPER("SELECT * FROM environments") do
    environments [tonumber (row.uid)] = row.name
    terrain_colours [row.name] = tonumber (row.color)
  end -- finding environments
end

function map_portal_recall (portalIndex)
  -- flag a portal as using "recall"
  local query = "INSERT OR REPLACE INTO rooms (uid, name, area) VALUES ('**', '___HERE___', '___EVERYWHERE___')"
  dbCheckExecute(query)

  local pnum = tonumber(portalIndex)

  if pnum==nil then
    Note("\nPORTALRECALL FAILED: The required parameter for .MapperPortalRecall is <portal_index>.\nCurrent portal indexes can be found by using the .MapperPortalList command.\n")
    return
  end

  local count = 1
  local found = false
  for row in dbnrowsWRAPPER(PORTALS_QUERY) do
    if count == pnum then

      -- toggle between '*' and '**'
      query = string.format ([[
      INSERT OR REPLACE INTO exits (dir, fromuid, touid, level)
      VALUES (%s, %s, %s, %s);
      ]],
      fixsql(row.dir),      -- direction (eg. "home")
      fixsql(((row.fromuid == "*") and "**") or "*"),
      fixsql(row.touid),    -- destination room
      fixsql(row.level)
      )
      dbCheckExecute(query)

      -- remove the old pre-toggle entry
      query = string.format ([[
      DELETE FROM exits WHERE dir=%s AND fromuid=%s AND touid=%s AND level=%s;
      ]],
      fixsql(row.dir),
      fixsql(row.fromuid),
      fixsql(row.touid),    -- destination room
      fixsql(row.level)
      )
      dbCheckExecute(query)

      Note(string.format("\nPORTALRECALL: Recall flag %s portal '%s' to '%s'.\n",((row.fromuid == "*") and "added to") or "removed from",row.dir,(row.name or "N/A")))
      found = true
      check_bounce_consistency()
    end
    count = count + 1
  end
  if found == false then
    Note(string.format("\nPORTALRECALL FAILED: Did not find index %s in the list of portals. Try .MapperPortalList to see the list.\n", pnum))
  end
end -- map_recall

-- first map_portal_add function was contributed by Spartacus.
function map_portal_add (PortalInfo)
  -- store portal as an exit from anywhere to the current or given room
  local destination = current_room
  Note(PortalInfo .."\n")
  local _, _, portallevel, portalcmd = string.find(PortalInfo,"(%d+)%s(.*)")

  -- check that we recieved both a portal command to store and a level for the portal
  if portalcmd == nil or portallevel == nil then
    Note("both the portal command and numerical level of the portal are required\n")
    return
  end

  portallevel = tonumber(portallevel) or 0
  Note("Portal level : "..portallevel.. " Portal command : ".. portalcmd.. "\n")
  if not destination then
    Note("PORTAL FAILED: No room received from the mud yet. Try using the 'LOOK' command first.\n")
    return
  end

  if not load_room_from_database(destination) then
    Note("PORTAL ["..portalcmd.."] FAILED: Room "..destination.." is unknown.\n")
    return
  end

  local level = (level_check(portallevel) and portallevel)

  if not level then
    Note("Portal creation cancelled.\n")
    return
  end

  create_portal(portalcmd, destination, level)
end -- map_portal_add

function create_portal(keyword, destination, level)
  local hhp_room_exists = 0
  local query = ""
  keyword = Trim(keyword)
  -- first check to see if our special 'from anywhere' room exists...
  for row in dbnrowsWRAPPER("select * from rooms where uid='*'") do
    hhp_room_exists = hhp_room_exists + 1
  end
  if hhp_room_exists == 0 then
    query = "INSERT OR REPLACE INTO rooms (uid, name, area) VALUES ('*', '___HERE___', '___EVERYWHERE___')"
    dbCheckExecute(query)
  end
  Note(string.format("Storing '%s' as a portal to %s.\n", keyword, destination))
  Note(string.format("\nPortal given minimum level lock of %s.\n", level))
  query = string.format ("INSERT OR REPLACE INTO exits (dir, fromuid, touid, level) VALUES (%s, %s, %s, %s);",
  fixsql (keyword),
  fixsql ("*"),           -- from anywhere
  fixsql (destination),
  fixsql (level) -- minimum level of the portal
  )
  dbCheckExecute(query)
end

lastarea = ""
function got_gmcp_room(GMCPRoomData)
  --Note("fired")
  local room_number = GMCPRoomData.num
  if not(room_number) then
    return
  end

  if current_room_is_cont ~= (GMCPRoomData.cont == "1") then
    current_room_is_cont = (GMCPRoomData.cont == "1")
  end

  gmcproom = {
    --name = strip_colours(GMCPRoomData.name),
    name = GMCPRoomData.name,
    area = GMCPRoomData.zone,
    building = 0,
    terrain = GMCPRoomData.terrain,
    info = GMCPRoomData.details,
    notes = "",
    x = GMCPRoomData.coord.x,
    y = GMCPRoomData.coord.y,
    z = 0,
    exits = {},
    exit_locks = {}
  }
  if gmcproom.area ~= lastarea then
    lastarea = gmcproom.area
    -- purge all virtual areas except the current area
    for k,v in pairs(areas) do
      if v.virtual and (k ~= lastarea) then
        purgezone(k)
      end
    end
  end

  -- Try to accomodate closed clan rooms and other nomap rooms.
  -- We'll have to make some other changes elsewhere as well.
  if room_number == "-1" then
    room_number = "nomap_"..gmcproom.name.."_"..gmcproom.area
  end

  current_room = room_number

  local area_exists = false
  for n in dbnrowsWRAPPER (string.format ("SELECT uid FROM areas where uid=%s", fixsql(gmcproom.area))) do
    area_exists = true
  end
  if not area_exists and last_area_requested ~= gmcproom.area then
    last_area_requested = gmcproom.area
    Send_GMCP_Packet("request area")
  end

  local room = rooms [room_number]
  -- not cached - see if in database
  if not room then
    room = load_room_from_database (room_number)
  end -- not in cache

  local check_compact = ""
  if not compact_mode then check_compact = "\n" end

  if shownotes and room and room.notes and room.notes ~= "" then
    Note(string.format("%s*** MAPPER NOTE *** -> %s%s%s\n", bcyan, dcyan, room.notes, dwhite))
    --AnsiNote(ColoursToANSI("@x033*** MAPPER NOTE *** -> "..room.notes.."@w"..check_compact))
  end

  -- re-save if we got information that is different than before
  local same_exits = ((room and compareTables(GMCPRoomData.exits, room.exits)) or false)
  if room and room.ignore_exits_mismatch and not same_exits then
    same_exits = true
    Note("(This room has exits that don't match the MUD, but you've chosen to ignore it.)")
  end
  local same_area = ((room and (nilToStr(room.area) == nilToStr(gmcproom.area))) or false)
  if not room or nilToStr(room.name) ~= nilToStr(gmcproom.name) or
    nilToStr(room.terrain) ~= nilToStr(gmcproom.terrain) or
    nilToStr(room.info) ~= nilToStr(gmcproom.info) or
    same_area == false or
    same_exits == false then
    if same_area then
      gmcproom.exits = (room.exits or {})
      gmcproom.exit_locks = (room.exit_locks or {})
      gmcproom.notes = nilToStr(room.notes)
      gmcproom.noportal = (room.noportal or 0)
      gmcproom.norecall = (room.norecall or 0)
    elseif room and nilToStr(room.area) ~= "" and areas[nilToStr(room.area)] then
      Note("This room has moved areas. You should 'mapper purgezone "..nilToStr(room.area)..
      "' if this new area replaces it.\n")
      map_purgeroom (nilToStr(room_number), gmcproom.area)
    else
      -- brand new area
      --         print("new area")
      gmcproom.exits = {}
      gmcproom.exit_locks = {}
      gmcproom.notes = ""
      gmcproom.noportal = 0
      gmcproom.norecall = 0
    end
    dbCheckExecute("BEGIN TRANSACTION;")
    local success = save_room_to_database(room_number, gmcproom)
    if success then
      rooms[room_number] = gmcproom
      if not same_exits or not same_area then
        save_room_exits(room_number,GMCPRoomData)
      end
    end
    dbCheckExecute("COMMIT;")

    if not success then
      return
    end
  end -- if room not there

  if expected_exit == "0" and from_room then
    fix_up_exit ()
  end -- exit was wrong

  return
end

function check_we_can_find ()
  if not current_room then
    Note("I don't know where you are right now - try: LOOK\n")
    --check_connected ()
    return false
  end
  if current_speedwalk then
    Note("The mapper has detected a speedwalk initiated inside another speedwalk. Aborting.\n")
    return false
  end -- if
  return true
end -- check_we_can_find

function findNearestJumpRoom(src, dst, target_type)
  local depth = 0
  --  local max_depth = mapper.config.SCAN.depth
  local room_sets = {}
  local rooms_list = {}
  local found = false
  local ftd = {}
  local destination = ""
  local next_room = 0
  local visited = ""
  local path_type = ""

  table.insert(rooms_list, fixsql(src))
  --  local main_status = GetInfo(53)
  while not found and depth < max_depth do
    depth = depth + 1
    -- prune the search space
    if visited ~= "" then
      visited = visited..","..table.concat(rooms_list, ",")
    else
      visited = table.concat(rooms_list, ",")
    end

    -- get all exits to any room in the previous set
    local q = string.format ("select fromuid, touid, dir, norecall, noportal from exits,rooms where rooms.uid = exits.touid and exits.fromuid in (%s) and exits.touid not in (%s) and exits.level <= %s order by length(exits.dir) asc",
    table.concat(rooms_list,","), visited, mylevel)
    local dcount = 0
    for row in dbnrowsWRAPPER(q) do
      dcount = dcount + 1
      table.insert(rooms_list, fixsql(row.touid))
      -- ordering by length(dir) ensures that custom exits (always longer than 1 char) get
      -- used preferentially to normal ones (1 char)
      if ((bounce_portal ~= nil or target_type == "*") and row.noportal ~= 1) 
        or ((bounce_recall ~= nil or target_type == "**") and row.norecall ~= 1) 
        or row.touid == dst then
        path_type = ((row.touid == dst) and 1) or ( (((row.noportal == 1) and 2) or 0) + (((row.norecall == 1) and 4) or 0) )
        -- path_type 1 means walking to the destination is closer than bouncing
        -- path_type 2 means the bounce room allows recalling but not portalling
        -- path_type 4 means the bounce room allows portalling but not recalling
        -- path_type 0 means the bounce room allows both portalling and recalling
        destination = row.touid
        found = true
        found_depth = depth
      end -- if src
    end -- for select

    if dcount == 0 then
      return -- there is no path to a portalable or recallable room
    end -- if dcount
  end -- while

  if found == false then
    return
  end
  return destination, path_type, found_depth
end

-- original findpath function idea contributed by Spartacus
function findpath(src, dst, noportals, norecalls)
  if not rooms[src] then
    rooms[src] = load_room_from_database(src)
  end
  if not rooms[src] then
    return
  end

  local walk_one = nil
  for dir,touid in pairs(rooms[src].exits) do
    if tostring(touid) == tostring(dst) and tonumber(rooms[src].exit_locks[dir]) <= mylevel and ((walk_one == nil) or (#dir > #walk_one)) then
      walk_one = dir -- if one room away, walk there (don't portal), but prefer a cexit
    end
  end
  if walk_one ~= nil then
    return {{dir=walk_one, uid=touid}}, 1
  end
  local depth = 0
  --local max_depth = mapper.config.SCAN.depth
  local room_sets = {}
  local rooms_list = {}
  local found = false
  local ftd = {}
  local f = ""
  local next_room = 0

  if type(src) ~= "number" then
    src = string.match(src, "^(nomap_.+)$") or tonumber(src)
  end
  if type(dst) ~= "number" then
    dst = string.match(dst, "^(nomap_.+)$") or tonumber(dst)
  end

  if src == dst or src == nil or dst == nil then
    return {}
  end

  src = tostring(src)
  dst = tostring(dst)

  table.insert(rooms_list, fixsql(dst))

  local visited = ""
  --local main_status = GetInfo(53)
  while not found and depth < max_depth do
    --SetStatus(main_status.." (searching depth "..depth..")")
    --BroadcastPlugin (999, "repaint")
    depth = depth + 1
    if depth > 1 then
      ftd = room_sets[depth-1] or {}
      rooms_list = {}
      for k,v in pairs(ftd) do
        table.insert(rooms_list, fixsql(v.fromuid))
      end -- for from, to, dir
    end -- if depth

    -- prune the search space
    if visited ~= "" then
      visited = visited..","..table.concat(rooms_list, ",")
    else
      if noportals then
        visited = visited..fixsql("*")..","
      end
      if norecalls then
        visited = visited..fixsql("**")..","
      end
      visited = visited..table.concat(rooms_list, ",")
    end

    -- get all exits to any room in the previous set
    local q = string.format ("select fromuid, touid, dir from exits where touid in (%s) and fromuid not in (%s) and ((fromuid not in ('*','**') and level <= %s) or (fromuid in ('*','**') and level <= %s)) order by length(dir) asc",
    table.concat(rooms_list, ","),
    visited,
    mylevel,
    mylevel+(mytier*10))
    local dcount = 0
    room_sets[depth] = {}
    for row in dbnrowsWRAPPER(q) do
      dcount = dcount + 1
      -- ordering by length(dir) ensures that custom exits (always longer than 1 char) get
      -- used preferentially to normal ones (1 char)
      room_sets[depth][row.fromuid] = {fromuid=row.fromuid, touid=row.touid, dir=row.dir}
      if row.fromuid == "*" or (row.fromuid == "**" and f ~= "*" and f ~= src) or row.fromuid == src then
        f = row.fromuid
        found = true
        found_depth = depth
      end -- if src
    end -- for select

    if dcount == 0 then
      return -- there is no path from here to there
    end -- if dcount
  end -- while

  if found == false then
    return
  end

  -- We've gotten back to the starting room from our destination. Now reconstruct the path.
  local path = {}
  -- set ftd to the first from,to,dir set where from was either our start room or * or **
  ftd = room_sets[found_depth][f]

  if (f == "*" and rooms[src].noportal == 1) or (f == "**" and rooms[src].norecall == 1) then
    if rooms[src].norecall ~= 1 and bounce_recall ~= nil then
      table.insert(path, bounce_recall)
      if dst == bounce_recall.uid then
        return path, found_depth
      end
    elseif rooms[src].noportal ~= 1 and bounce_portal ~= nil then
      table.insert(path, bounce_portal)
      if dst == bounce_portal.uid then
        return path, found_depth
      end
    else
      local jump_room, path_type = findNearestJumpRoom(src, dst, f)
      if not jump_room then
        return
      end
      local path, first_depth = findpath(src,jump_room, true, true) 
      -- this could be optimized away by building the path in findNearestJumpRoom, 
      -- but the gain would be negligible
      if bit.band(path_type, 1) ~= 0 then
        -- path_type 1 means just walk to the destination
        return path, first_depth
      else
        local second_path, second_depth = findpath(jump_room, dst)
        for i,v in ipairs(second_path) do
          table.insert(path, v) -- bug on this line if path is nil?
        end
        return path, first_depth+second_depth
      end
    end
  end

  table.insert(path, {dir=ftd.dir, uid=ftd.touid})

  next_room = ftd.touid
  while depth > 1 do
    depth = depth - 1
    ftd = room_sets[depth][next_room]
    next_room = ftd.touid
    -- this caching is probably not noticeably useful, so disable it for now
    --      if not rooms[ftd.touid] then -- if not in memory yet, get it
    --         rooms[ftd.touid] = load_room_from_database (ftd.touid)
    --      end
    table.insert(path, {dir=ftd.dir, uid=ftd.touid})
  end -- while
  return path, found_depth
end -- function findpath

function build_speedwalk (path, prefix)

  stack_char = ";"
  --   if GetOption("enable_command_stack")==1 then
  --      stack_char = GetAlphaOption("command_stack_character")
  --   else
  --      stack_char = "\r\n"
  --   end

  -- build speedwalk string (collect identical directions)
  local tspeed = {}
  for _, dir in ipairs (path) do
    local n = #tspeed
    if n == 0 then
      table.insert (tspeed, { dir = dir.dir, count = 1 })
    else
      if expand_direction[dir.dir] ~= nil and tspeed [n].dir == dir.dir then
        tspeed [n].count = tspeed [n].count + 1
      else
        table.insert (tspeed, { dir = dir.dir, count = 1 })
      end -- if different direction
    end -- if
  end -- for

  if #tspeed == 0 then
    return
  end -- nowhere to go (current room?)

  -- now build string like: 2n3e4(sw)
  local s = ""

  local new_command = false
  for _, dir in ipairs (tspeed) do
    if expand_direction[dir.dir] ~= nil then
      if new_command then
        s = s .. stack_char .. speedwalk_prefix .. " "
        new_command = false
      end
      if dir.count > 1 then
        s = s .. dir.count
      end -- if
      s = s .. dir.dir
    else
      s = s .. stack_char .. dir.dir
      new_command = true
    end -- if
  end -- if

  if prefix ~= nil then
    if s:sub(1,1) == stack_char then
      return string.gsub(s:sub(2),";",stack_char)
    else
      return string.gsub(prefix.." "..s,";",stack_char)
    end
  end
  return string.gsub(s,";",stack_char)
end -- build_speedwalk

function map_where_uid (destination)
  if not check_we_can_find () then
    return
  end -- if

  local wanted = tonumber(destination)

  if not wanted then
    Note("The mapper where command expects a room id number as input.\n")
    return
  end

  if current_room and wanted == current_room then
    Note("You are already in that room.\n")
    return
  end -- if

  local paths = {}
  local foundpath = findpath(current_room, wanted)
  if foundpath ~= nil then
    paths[wanted] = {path=foundpath, reason=true}
  end

  local uid, item = next (paths, nil) -- extract first (only) path

  -- nothing? room not found
  if not item then
    Note(string.format ("Room %s not found\n", wanted))
    return
  end -- if

  -- turn into speedwalk
  local speedwalk = build_speedwalk (item.path, speedwalk_prefix)

  -- display it
  if speedwalk ~= nil then
    Note(string.format ("Path to %s is:\n%s\n", wanted, speedwalk))
    return(speedwalk)
  else
    Note(string.format("You're IN room %s!\n", wanted))
    return("")
  end
end -- map_where_uid

function map_goto(destination)
  local PathToDestination = map_where_uid(destination)
  if PathToDestination ~= "" then
    SendToServer(PathToDestination)
  end
end

function fix_up_exit ()
  local room = rooms [from_room]

  dbCheckExecute(string.format ("UPDATE exits SET touid = %s WHERE fromuid = %s AND dir = %s;",
  fixsql (current_room),     -- destination room
  fixsql (from_room),       -- from previous room
  fixsql (last_direction_moved)  -- direction (eg. "n")
  ))

  --   if show_database_mods then
  Note("Fixed exit", last_direction_moved, "from room", from_room, "to be to", current_room, "\n")
  --   end -- if

  room.exits [last_direction_moved] = current_room

  last_direction_moved = nil
  from_room = nil
end -- fix_up_exit

function purgezone(zoneuid)
  local query = "BEGIN TRANSACTION;"
  query = query..string.format ("delete from exits where touid in (select uid from rooms where area = %s);",fixsql(zoneuid))
  query = query..string.format ("delete from exits where fromuid in (select uid from rooms where area = %s);",fixsql(zoneuid))
  query = query..string.format ("delete from rooms_lookup where uid in (select uid from rooms where area = %s);", fixsql(zoneuid))
  query = query..string.format ("delete from bookmarks where uid in (select uid from rooms where area = %s);", fixsql(zoneuid))
  query = query..string.format ("delete from rooms where area = %s;", fixsql(zoneuid))
  query = query..string.format ("delete from areas where uid = %s;", fixsql(zoneuid))
  query = query.."COMMIT;"
  dbCheckExecute(query)

  for k,v in pairs(rooms) do
    for j,u in pairs(v.exits) do
      if (rooms[u] ~= nil) and (rooms[u].area == zoneuid) then
        v.exits[j] = nil
      end
    end
  end
  for k,v in pairs(rooms) do
    if v.area == zoneuid then
      rooms[k] = nil
    end
  end
  areas[zoneuid] = nil
  Send_GMCP_Packet("request room")
end

-- map_list_rooms function contributed by Spartacus
function map_list_rooms (SearchData)
  -- ok, so if I want to lookup a room in my db, I don't want it only if the mapper can find 
  -- a sw in a certain # of rooms. if it is in the db, I want its vnum and area, so that I can 
  -- figure out how to get there if the mapper does not know.
  -- Now has the added functionality that it can return a table of room numbers if requested to.
  local ReturnedRoomList = {}
  local _, _, ReturnList, RoomName = string.find(SearchData,"^(%d?)%s?(.*)$")
  if ReturnList ~= nil then 
    ReturnList = tonumber(ReturnList) or 0
  else 
    ReturnList = 0 
    --Note("was null\n")
  end
  RoomName = RoomName:match("^%s*(.-)%s*$") 
  local area = ""
  local count = 1
  if ReturnList  == 0 then
    Note("+------------------------------ START OF SEARCH -------------------------------+\n")
  end
  -- find matching rooms using FTS3
  local name = "%"..RoomName.."%"
  if string.sub(RoomName,1,1) == "\"" and string.sub(RoomName,-1) == "\"" then
    name = string.sub(RoomName,2,-2)
  end

  local SQLQuery = "SELECT rooms_lookup.uid as uid, rooms_lookup.name as name, "..
  "area FROM (select uid, name FROM rooms_lookup WHERE name LIKE %s) "..
  "AS rooms_lookup JOIN rooms ON rooms_lookup.uid = rooms.uid ORDER BY area LIMIT 101;"
  for row in dbnrowsWRAPPER(string.format (SQLQuery, fixsql (name))) do
    if count < 101 then
      if ReturnList  == 0 then
        Note(string.format("( %5d ) %-40s is in area \"%s\"\n",row.uid, row.name, row.area))
      else
        table.insert(ReturnedRoomList, row)
      end
    end
    count = count + 1
  end   -- finding room
  if count > 100 then
    if ReturnList  == 0 then
      Note(string.format("More than 100 search results found. Aborting query. Try a more specific search phrase than '%s'.\n",RoomName))
    end
  end
  if ReturnList  == 0 then
    Note("+-------------------------------- END OF SEARCH -------------------------------+\n")
  end

  if ReturnList ~= 0 then 
    return ReturnedRoomList
  end
  return {}
end -- map_list_rooms

-- map_list_rooms function contributed by Spartacus
function map_list_rooms_extended (SearchData, ReturnAsList, SearchByArea)
  -- ok, so if I want to lookup a room in my db, I don't want it only if the mapper can find 
  -- a sw in a certain # of rooms. if it is in the db, I want its vnum and area, so that I can 
  -- figure out how to get there if the mapper does not know.
  -- Now has the added functionality that it can return a table of room numbers if requested to.
  local ReturnedRoomList = {}
  local ReturnList = tonumber(ReturnAsList) or 0
  local SearchArea = tostring(SearchByArea) or ""
  RoomName = SearchData:match("^%s*(.-)%s*$") 
  local area = ""
  local count = 1
  if ReturnList  == 0 then
    Note("+------------------------------ START OF SEARCH -------------------------------+\n")
  end
  -- find matching rooms using FTS3
  local name = "%"..RoomName.."%"
  if string.sub(RoomName,1,1) == "\"" and string.sub(RoomName,-1) == "\"" then
    name = string.sub(RoomName,2,-2)
  end

  local SQLQuery = "SELECT rooms_lookup.uid as uid, rooms_lookup.name as name, "..
  "area FROM (select uid, name FROM rooms_lookup WHERE name LIKE %s) "..
  "AS rooms_lookup JOIN rooms ON rooms_lookup.uid = rooms.uid ORDER BY area LIMIT 101;"
  for row in dbnrowsWRAPPER(string.format (SQLQuery, fixsql (name))) do
    if SearchArea == "" then
      if count < 101 then
        if ReturnList  == 0 then
          Note(string.format("( %5d ) %-40s is in area \"%s\"\n",row.uid, row.name, row.area))
        else
          table.insert(ReturnedRoomList, row)
        end
      end
      count = count + 1
    elseif SearchArea == row.area then
      if count < 101 then
        if ReturnList  == 0 then
          Note(string.format("( %5d ) %-40s is in area \"%s\"\n",row.uid, row.name, row.area))
        else
          table.insert(ReturnedRoomList, row)
        end
      end
      count = count + 1
    end
  end   -- finding room
  if count > 100 then
    if ReturnList  == 0 then
      Note(string.format("More than 100 search results found. Aborting query. Try a more specific search phrase than '%s'.\n",RoomName))
    end
  end
  if ReturnList  == 0 then
    Note("+-------------------------------- END OF SEARCH -------------------------------+\n")
  end

  if ReturnList ~= 0 then 
    return ReturnedRoomList
  end
  return {}
end -- map_list_rooms_extended

function populate_room_list(RoomName)
  RoomListTable = map_list_rooms("1 "..RoomName)
  Note("+------------------------------ START OF SEARCH -------------------------------+\n")
  for count, RoomInfo in ipairs(RoomListTable) do
    Note(string.format("%03d, ( %5s ) %-40s is in \"%s\"\n",
    count, RoomInfo["uid"], RoomInfo["name"], RoomInfo["area"]))
    NumberOfFoundRooms = count
  end
  Note("+-------------------------------- END OF SEARCH -------------------------------+\n")
  CurrentFoundRoom = 0
end

function populate_room_list_with_area(SearchData)
  --SearchData == "areaname roomname"
  local _, _, SearchArea, RoomName = string.find(SearchData,"^(%w+)%s(.*)$")
  SearchArea = string.lower(SearchArea)
  if SearchArea == "here" then
    local room = load_room_from_database(current_room)
    SearchArea = room.area
  end
  RoomListTable = map_list_rooms_extended(RoomName, 1, SearchArea)
  Note("+------------------------------ START OF SEARCH -------------------------------+\n")
  for count, RoomInfo in ipairs(RoomListTable) do
    Note(string.format("%03d, ( %5s ) %-40s is in \"%s\"\n",
    count, RoomInfo["uid"], RoomInfo["name"], RoomInfo["area"]))
    NumberOfFoundRooms = count
  end
  Note("+-------------------------------- END OF SEARCH -------------------------------+\n")
  CurrentFoundRoom = 0
end

function goto_listed_number(NumberInList)
  if RoomListTable == {} then
    Note("There are no rooms in the list you wish to use.\n"..
    "Please execute \".MapperPopulateRoomList\" with a valid roomname to populate the list.\n")
    return
  end
  if not(positive_integer_check(NumberInList)) 
    and (tonumber(NumberInList) > NumberOfFoundRooms) then
    Note(string.format("This function requires a positive number between 1 and %s as input.\n"),
    NumberOfFoundRooms)
    return
  end
  CurrentFoundRoom = tonumber(NumberInList)
  map_goto(tonumber(RoomListTable[CurrentFoundRoom].uid))
end

function goto_listed_next()
  if RoomListTable == {} then
    Note("There are no rooms in the list you wish to use.\n"..
    "Please execute \".MapperPopulateRoomList\" with a valid roomname to populate the list.\n")
    return
  end
  if CurrentFoundRoom == 0 then
    CurrentFoundRoom = 1
    Note("Initialising the room we are looking for.\n")
  end
  if CurrentFoundRoom < 1 then
    CurrentFoundRoom = 1
  end
  if tonumber(RoomListTable[CurrentFoundRoom].uid) == tonumber(current_room) then
    -- if we are in the room for this search, head to the next room
    CurrentFoundRoom = CurrentFoundRoom + 1
  end
  if CurrentFoundRoom > NumberOfFoundRooms then
    CurrentFoundRoom = NumberOfFoundRooms
    Note("You can't search any further forward in the list.\n")
    return
  end
  Note(string.format("Going to %s in %s.\n", 
  RoomListTable[CurrentFoundRoom].name, 
  RoomListTable[CurrentFoundRoom].area))
  map_goto(tonumber(RoomListTable[CurrentFoundRoom].uid))
end

function goto_listed_previous()
  if RoomListTable == {} then
    Note("There are no rooms in the list you wish to use.\n"..
    "Please execute \".MapperPopulateRoomList\" with a valid roomname to populate the list.\n")
    return
  end
  if CurrentFoundRoom == 0 then 
    Note("Initialising the room we are looking for.\n")
    CurrentFoundRoom = NumberOfFoundRooms
  end
  if CurrentFoundRoom > NumberOfFoundRooms then
    CurrentFoundRoom = NumberOfFoundRooms
  end
  if tonumber(RoomListTable[CurrentFoundRoom].uid) == tonumber(current_room) then
    CurrentFoundRoom = CurrentFoundRoom - 1
  end
  if CurrentFoundRoom < 1 then 
    Note("You can't search any further back in the list.\n")
    CurrentFoundRoom = 1
    return
  end
  Note(string.format("Going to %s in %s.\n", 
  RoomListTable[CurrentFoundRoom].name, 
  RoomListTable[CurrentFoundRoom].area))
  map_goto(tonumber(RoomListTable[CurrentFoundRoom].uid))
end

function custom_exits_list (searcharea)
  local line = ""
  local count = 0
  local query

  area = Trim(searcharea or "")
  query = string.format("select uid, name, area, dir, touid from rooms inner join exits on rooms.uid = fromuid where lower(area) like %s and dir not in ('n','s','e','w','d','u') and fromuid not in ('*','**') order by area, uid", fixsql("%" .. area .. "%"))

  if area == "" then
    intro = "The following rooms have custom exits:\n"
  else
    if area == "here" then
      if current_room and gmcproom.area then
        area = gmcproom.area
      else
        Note("CEXITS HERE ERROR: The mapper doesn't know where you are. Type 'LOOK' and try again.\n")
        return
      end
      query = string.format("select uid, name, area, dir, touid from rooms inner join exits on rooms.uid = fromuid where lower(area) is %s and dir not in ('n','s','e','w','d','u') and fromuid not in ('*','**') order by uid", fixsql(area))
      intro = "The following rooms in the current area have custom exits:"
    elseif area == "thisroom" then
      if not current_room then
        Note("CEXITS THISROOM ERROR: The mapper doesn't know where you are. Type 'LOOK' and try again.\n")
        return
      end
      query = string.format("select uid, name, area, dir, touid from rooms inner join exits on rooms.uid = fromuid where fromuid=%s and dir not in ('n','s','e','w','d','u')", fixsql(current_room))
      intro = "The following custom exits are in this room:\n"
    else
      intro = string.format("The following rooms in areas partially matching '%s' have custom exits:\n",area)
    end
  end

  hr = "| area       | room name            | rm uid  | dir            | to uid  |\n"
  hl = "+------------+----------------------+---------+----------------+---------+\n"

  -- area - room name - room uid - direction - destination uid
  fmt = "| %10.10s | %-20.20s | %7.7s | %-14.14s | %7.7s |\n"
  Note ("\n"..intro)
  Note (hl)
  Note (hr)
  Note (hl)
  for row in dbnrowsWRAPPER(query) do
    line = string.format(fmt,row.area, row.name, row.uid, row.dir, row.touid)
    Note(line)
    --[[
    Hyperlink(string.format("mapper goto %s",row.uid), line, string.format("%s",row.dir), "", "", false, NoUnderline_hyperlinks)
    print("")
    ]]
    count = count + 1
  end -- custom exits query
  Note (hl)
  line = string.format ("Found %s custom exits.\n", count)
  Note (line.."\n")
end -- custom_exits_list

function create_tables ()
  -- create rooms table
  dbCheckExecute([[
  PRAGMA foreign_keys = ON;

  CREATE TABLE IF NOT EXISTS areas(
  uid TEXT NOT NULL,
  name TEXT,
  texture TEXT,
  color TEXT,
  flags TEXT NOT NULL DEFAULT '',
  PRIMARY KEY(uid));
  CREATE TABLE IF NOT EXISTS bookmarks(
  uid TEXT NOT NULL,
  notes TEXT,
  PRIMARY KEY(uid));
  CREATE TABLE IF NOT EXISTS environments(
  uid TEXT NOT NULL,
  name TEXT,
  color INTEGER,
  PRIMARY KEY(uid));
  CREATE TABLE IF NOT EXISTS exits(
  dir TEXT NOT NULL,
  fromuid TEXT NOT NULL,
  touid TEXT NOT NULL,
  level STRING NOT NULL DEFAULT '0',
  PRIMARY KEY(fromuid, dir));
  CREATE TABLE IF NOT EXISTS rooms(
  uid TEXT NOT NULL,
  name TEXT,
  area TEXT,
  building TEXT,
  terrain TEXT,
  info TEXT,
  notes TEXT,
  x INTEGER,
  y INTEGER,
  z INTEGER,
  norecall INTEGER,
  noportal INTEGER, ignore_exits_mismatch INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(uid));
  CREATE VIRTUAL TABLE rooms_lookup USING FTS3(uid, name);
  CREATE TABLE IF NOT EXISTS 'rooms_lookup_content'(docid INTEGER PRIMARY KEY, 'c0uid', 'c1name');
  CREATE TABLE IF NOT EXISTS 'rooms_lookup_segdir'(level INTEGER,idx INTEGER,start_block INTEGER,leaves_end_block INTEGER,end_block INTEGER,root BLOB,PRIMARY KEY(level, idx));
  CREATE TABLE IF NOT EXISTS 'rooms_lookup_segments'(blockid INTEGER PRIMARY KEY, block BLOB);
  CREATE TABLE IF NOT EXISTS storage (
  name        TEXT NOT NULL,
  data        TEXT NOT NULL,
  PRIMARY KEY (name)
  );
  CREATE TABLE IF NOT EXISTS terrain (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,   -- terrain name
  color       INTEGER,            -- RGB code
  date_added  DATE,               -- date added to database
  UNIQUE (name)
  );
  CREATE INDEX exits_touid_index ON exits (touid);
  CREATE INDEX rooms_area_index ON rooms (area);
  ]])

  -- Since the MUD sends terrain as a string and not as an integer,
  -- it was wrong to originally produce rooms with integer terrains.
  -- Or maybe it's wrong for the MUD to send strings. Either way, we now
  -- have databases with inconsistent data. So let's make it consistent.
  dbCheckExecute("UPDATE OR IGNORE rooms SET terrain = ifnull((SELECT name FROM environments WHERE environments.uid = rooms.terrain), rooms.terrain);")

  -- check if rooms_lookup table exists
  dbCheckExecute([[
  BEGIN TRANSACTION;
  DROP TABLE IF EXISTS rooms_lookup;
  CREATE VIRTUAL TABLE rooms_lookup USING FTS3(uid, name);
  INSERT INTO rooms_lookup (uid, name) SELECT uid, name FROM rooms;
  COMMIT;
  ]])
end -- function create_tables

function update_gmcp_mytier(GMCPCharBase)
  mytier = tonumber(GMCPCharBase.tier)
end

function update_gmcp_mystatus(GMCPCharStatus)
  mylevel = tonumber(GMCPCharStatus.level)
end

function report_mystuff()
  Note(string.format("Current level: %s\nCurrent tier: %s\n", mylevel, mytier))
end

function set_mytier(sent_value)
  if positive_integer_check(sent_value) then
    if (tonumber(sent_value) > -1) and (tonumber(sent_value) < 10) then
      mytier = tonumber(sent_value)
    else
      mytier = 0
      Note("Please select a level from 0 to 9. Your tier has been set to 0.\n")
    end
  else
    mytier = 0
    Note("We do not have a valid tier for your character. Your tier has been set to 0.\n")
  end
end

function set_mylevel(sent_value)
  if positive_integer_check(sent_value) then
    if (tonumber(sent_value) > 0) and (tonumber(sent_value) < 211) then
      mylevel = tonumber(sent_value)
    else
      mylevel = 0
      Note("Please select a level from 1 to 210. Your level has been set to 0.\n")
    end
  else
    mylevel = 0
    Note("We do not have a valid level for your character. It has defaulted to 0.\n")
  end
end

function processGMCPRoom(CapturedStuff)
  --Note("we got stuff".."\n")
  return
end

function OnBackgroundStartup()
  Note(string.format("%sGMCP %sMapper plugin%s version: %s%s%s\n", dgreen, dred, dwhite, dyellow, version, dwhite))
  Note(string.format("%sYou are using sqlite3 version: %s%s%s\n", dgreen, bgreen, sqlite3.version(), dwhite))
  -- we need to check if the can create the db file, if it doesn't exist
  local DBTest = sqlite3.open(dbPath)
  if DBTest:errcode() ~= 0 then
    Note(string.format("%serror code: %s%s%s\nWe had the following error when trying to open the database: %s%s%s\n",
    dred, bred, DBTest:errcode(), dwhite,
    bred, DBTest:errmsg(), dwhite))
  else
    Note(string.format("%sDB created or it already existed.\n%s", dgreen, dwhite))
    Note(string.format("%sPlease note that this does not mean it has tables in it.%s\n",byellow,dwhite))
    Note(string.format("%sIf you see %sno such table: areas%s then run %s.MapperSetup.%s\n",
    byellow, dred, byellow, bgreen, bwhite))
  end
  DBTest:close()
  Note(string.format("gmcp_mapper startup completed.\n"))
  --Send_GMCP_Packet("rawcolor on")
end

function PrepGMCP()
  --Send_GMCP_Packet("rawcolor on")
end

-- Initial Setup functions
RegisterSpecialCommand("MapperSetup","create_tables")
RegisterSpecialCommand("MapperGMCPForceOn","PrepGMCP")
-- Mapper Information functions
RegisterSpecialCommand("MapperShowThisRoom","show_this_room")
RegisterSpecialCommand("MapperListAreas","map_areas")
RegisterSpecialCommand("MapperListRooms","map_list_rooms")
RegisterSpecialCommand("MapperWhere","map_where_uid")
--Mapper Cexit functions
RegisterSpecialCommand("MapperCExitAdd","custom_exits_add")
RegisterSpecialCommand("MapperCExitAddDoor","custom_exits_add_door")
RegisterSpecialCommand("MapperCExitDelete","custom_exits_delete")
RegisterSpecialCommand("MapperCExitList","custom_exits_list")
--Mapper Portal functions
RegisterSpecialCommand("MapperPortalAdd","map_portal_add")
RegisterSpecialCommand("MapperPortalRecall","map_portal_recall")
RegisterSpecialCommand("MapperPortalBounceRecall","map_bouncerecall")
RegisterSpecialCommand("MapperPortalList","map_portal_list")
RegisterSpecialCommand("MapperPortalDelete","map_portal_delete")
--Mapper Movement functions
RegisterSpecialCommand("MapperGoto","map_goto")
RegisterSpecialCommand("MapperEditNote","room_edit_note")
--Mapper recall and portal status setting
RegisterSpecialCommand("MapperNoRecall","set_norecall_thisroom")
RegisterSpecialCommand("MapperNoPortal","set_noportal_thisroom")
--Mapper report level and tier for character
RegisterSpecialCommand("MapperReport","report_mystuff")
--Mapper special commands for moving around rooms looked up
RegisterSpecialCommand("MapperPopulateRoomList","populate_room_list")
RegisterSpecialCommand("MapperPopulateRoomListArea","populate_room_list_with_area")
RegisterSpecialCommand("MapperGotoListNumber","goto_listed_number")
RegisterSpecialCommand("MapperGotoListNext","goto_listed_next")
RegisterSpecialCommand("MapperGotoListPrevious","goto_listed_previous")

