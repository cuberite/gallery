
-- Storage.lua

-- Implements DB storage backend for the plugin





--- The DB connection that provides the player areas
g_DB = nil;





function InitStorage()
	-- TODO: Query g_Config for the DB engine to use - SQLite (built-in) or MySQL (via LuaRocks)
	OpenDB();
end





--- Executes a command on the g_DB object
function DBExec(a_SQL, a_Callback, a_CallbackParam)
	local ErrCode = g_DB:exec(a_SQL, a_Callback, a_CallbackParam);
	if (ErrCode ~= sqlite3.OK) then
		LOGWARNING(PLUGIN_PREFIX .. "Error " .. ErrCode .. " (" .. self.DB:errmsg() ..
			") while processing SQL command >>" .. a_SQL .. "<<"
		);
		return false;
	end
	return true;
end





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
function CreateDBTable(a_TableName, a_Columns)
	-- Try to create the table first
	local sql = "CREATE TABLE IF NOT EXISTS '" .. a_TableName .. "' (";
	sql = sql .. table.concat(a_Columns, ", ");
	sql = sql .. ")";
	if (not(DBExec(sql))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB Table " .. a_TableName);
		return false;
	end
	-- SQLite doesn't inform us if it created the table or not, so we have to continue anyway
	
	-- Check each column whether it exists
	-- Remove all the existing columns from a_Columns:
	local RemoveExistingColumn = function(UserData, NumCols, Values, Names)
		-- Remove the received column from a_Columns. Search for column name in the Names[] / Values[] pairs
		for i = 1, NumCols do
			if (Names[i] == "name") then
				local ColumnName = Values[i]:lower();
				-- Search the a_Columns if they have that column:
				for j = 1, #a_Columns do
					-- Cut away all column specifiers (after the first space), if any:
					local SpaceIdx = string.find(a_Columns[j], " ");
					if (SpaceIdx ~= nil) then
						SpaceIdx = SpaceIdx - 1;
					end
					local ColumnTemplate = string.lower(string.sub(a_Columns[j], 1, SpaceIdx));
					-- If it is a match, remove from a_Columns:
					if (ColumnTemplate == ColumnName) then
						table.remove(a_Columns, j);
						break;  -- for j
					end
				end  -- for j - a_Columns[]
			end
		end  -- for i - Names[] / Values[]
		return 0;
	end
	if (not(DBExec("PRAGMA table_info(" .. a_TableName .. ")", RemoveExistingColumn))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot query DB table structure");
		return false;
	end
	
	-- Create the missing columns
	-- a_Columns now contains only those columns that are missing in the DB
	if (#a_Columns > 0) then
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" is missing " .. #a_Columns .. " columns, fixing now.");
		for idx, ColumnName in ipairs(a_Columns) do
			if (not(DBExec("ALTER TABLE '" .. a_TableName .. "' ADD COLUMN " .. ColumnName))) then
				LOGWARNING(PLUGIN_PREFIX .. "Cannot add DB table \"" .. a_TableName .. "\" column \"" .. ColumnName .. "\"");
				return false;
			end
		end
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" columns fixed.");
	end
	
	return true;
end





--- Loads the areas for a single player in the specified world
function LoadPlayerAreas(a_WorldName, a_PlayerName)
	if (g_DB == nil) then
		return {};
	end

	local res = {};
	local ToDelete = {};  -- List of IDs to delete because of missing Gallery
	local stmt = g_DB:prepare("SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex FROM Areas WHERE PlayerName = ? AND WorldName = ?");
	stmt:bind_values(a_PlayerName, a_WorldName);
	for v in stmt:rows() do
		local area =
		{
			ID = v[1],
			MinX = v[2], MaxX = v[3], MinZ = v[4], MaxZ = v[5],
			StartX = v[6], EndX = v[7], StartZ = v[8], EndZ = v[9],
			Gallery = FindGalleryByName(a_WorldName, v[10]),
			GalleryIndex = v[11],
		};
		if (area.Gallery == nil) then
			table.insert(ToDelete, v[1]);
		else
			table.insert(res, area);
		end
	end
	stmt:finalize();
	
	-- Remove areas that reference non-existent galleries:
	if (#ToDelete > 0) then
		local stmt = g_DB:prepare("DELETE FROM Areas WHERE ID = ?");
		for idx, id in ipairs(ToDelete) do
			stmt:bind_values(id);
			stmt:step();
		end
		stmt:finalize();
	end
	
	return res;
end





function OpenDB()
	-- Open the DB:
	local ErrCode, ErrMsg;
	g_DB, ErrCode, ErrMsg = sqlite3.open(DATABASE_FILE);
	if (g_DB == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open database \"" .. DATABASE_FILE .. "\": " .. ErrMsg);
		error(ErrMsg);  -- Abort the plugin
	end
	
	-- Create the tables, if they don't exist yet:
	local AreasColumns =
	{
		"ID INTEGER PRIMARY KEY AUTOINCREMENT",
		"MinX", "MaxX", "MinZ", "MaxZ",      -- The bounds of this area, including the non-buildable "sidewalk"
		"StartX", "EndX", "StartZ", "EndZ",  -- The buildable bounds of this area
		"WorldName",                         -- Name of the world where the area belongs
		"PlayerName",                        -- Name of the owner
		"GalleryName",                       -- Name of the gallery from which the area has been claimed
		"GalleryIndex"                       -- Index of the area in the gallery from which this area has been claimed
	};
	local GalleryEndColumns =
	{
		"GalleryName",
		"NextAreaIdx",
	};
	if (
		not(CreateDBTable("Areas", AreasColumns)) or
		not(CreateDBTable("GalleryEnd", GalleryEndColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!");
		error("Cannot create DB tables!");
	end
end





