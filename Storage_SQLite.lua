
-- Storage_SQLite.lua

-- Implements the SQLite-backed database storage





--- The SQLite backend namespace:
local SQLite = {};





--- Executes an SQL query on the SQLite DB
function SQLite:DBExec(a_SQL, a_Callback, a_CallbackParam)
	local ErrCode = self.DB:exec(a_SQL, a_Callback, a_CallbackParam);
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
function SQLite:CreateDBTable(a_TableName, a_Columns)
	-- Try to create the table first
	local sql = "CREATE TABLE IF NOT EXISTS '" .. a_TableName .. "' (";
	sql = sql .. table.concat(a_Columns, ", ");
	sql = sql .. ")";
	if (not(self:DBExec(sql))) then
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
	if (not(self:DBExec("PRAGMA table_info(" .. a_TableName .. ")", RemoveExistingColumn))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot query DB table structure");
		return false;
	end
	
	-- Create the missing columns
	-- a_Columns now contains only those columns that are missing in the DB
	if (#a_Columns > 0) then
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" is missing " .. #a_Columns .. " columns, fixing now.");
		for idx, ColumnName in ipairs(a_Columns) do
			if (not(self:DBExec("ALTER TABLE '" .. a_TableName .. "' ADD COLUMN " .. ColumnName))) then
				LOGWARNING(PLUGIN_PREFIX .. "Cannot add DB table \"" .. a_TableName .. "\" column \"" .. ColumnName .. "\"");
				return false;
			end
		end
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" columns fixed.");
	end
	
	return true;
end





--- Loads the areas for a single player in the specified world
function SQLite:LoadPlayerAreas(a_WorldName, a_PlayerName)
	local res = {};
	local ToDelete = {};  -- List of IDs to delete because of missing Gallery
	local stmt = self.DB:prepare("SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex FROM Areas WHERE PlayerName = ? AND WorldName = ?");
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
		local stmt = self.DB:prepare("DELETE FROM Areas WHERE ID = ?");
		for idx, id in ipairs(ToDelete) do
			stmt:bind_values(id);
			stmt:step();
		end
		stmt:finalize();
	end
	
	return res;
end





--- Loads the next area index for each gallery
function SQLite:LoadGalleries()
	for idx, gallery in ipairs(g_Galleries) do
		self:DBExec("SELECT NextAreaIdx FROM GalleryEnd WHERE GalleryName = \"" .. gallery.Name .. "\"",
			function (UserData, NumCols, Values, Names)
				for i = 1, NumCols do
					if (Names[i] == "NextAreaIdx") then
						gallery.NextAreaIdx = tonumber(Values[i]);
						return;
					end
				end
			end
		);
		if (gallery.NextAreaIdx == nil) then
			gallery.NextAreaIdx = 0;
		end
	end
end





--- Stores the specified area in the DB. Called as a member function of the g_DB object, hence the self param.
function SQLite:StoreArea(a_Area)
	local stmt = self.DB:prepare("INSERT INTO Areas (MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex, WorldName, PlayerName) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
	stmt:bind_values(
		a_Area.MinX, a_Area.MaxX, a_Area.MinZ, a_Area.MaxZ,
		a_Area.StartX, a_Area.EndX, a_Area.StartZ, a_Area.EndZ,
		a_Area.Gallery.Name, a_Area.GalleryIndex,
		a_Area.Gallery.WorldName,
		a_Area.PlayerName
	);
	stmt:step();
	stmt:finalize();
	a_Area.ID = self.DB:last_insert_rowid();
end





function SQLite_CreateStorage(a_Params)
	DB = SQLite;
	local DBFile = a_Params.File or "Galleries.sqlite";
	
	-- Open the DB:
	local ErrCode, ErrMsg;
	DB.DB, ErrCode, ErrMsg = sqlite3.open(DBFile);
	if (DB.DB == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open database \"" .. DBFile .. "\": " .. ErrMsg);
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
		not(DB:CreateDBTable("Areas", AreasColumns)) or
		not(DB:CreateDBTable("GalleryEnd", GalleryEndColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!");
		error("Cannot create DB tables!");
	end
	
	-- Returns the initialized database access object
	return DB;
end