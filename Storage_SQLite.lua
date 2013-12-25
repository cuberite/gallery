
-- Storage_SQLite.lua

-- Implements the SQLite-backed database storage





--- The SQLite backend namespace:
local SQLite = {};





--- Executes an SQL query on the SQLite DB
function SQLite:DBExec(a_SQL, a_Callback, a_CallbackParam)
	assert(a_SQL ~= nil);
	
	local ErrCode = self.DB:exec(a_SQL, a_Callback, a_CallbackParam);
	if (ErrCode ~= sqlite3.OK) then
		LOGWARNING(PLUGIN_PREFIX .. "Error " .. ErrCode .. " (" .. self.DB:errmsg() ..
			") while processing SQL command >>" .. a_SQL .. "<<"
		);
		return false;
	end
	return true;
end






--- Executes the SQL statement, substituting "?" in the SQL with the specified params; calls a_Callback for each row
-- The callback receives a dictionary table containing the row values (stmt:nrows())
function SQLite:ExecuteStatement(a_SQL, a_Params, a_Callback)
	assert(a_SQL ~= nil);
	assert(a_Params ~= nil);
	
	local Stmt, ErrCode, ErrMsg = self.DB:prepare(a_SQL);
	if (Stmt == nil) then
		LOGWARNING("Cannot execute SQL \"" .. a_SQL .. "\": " .. ErrCode .. " (" .. ErrMsg .. ")");
		return nil, ErrMsg;
	end
	Stmt:bind_values(unpack(a_Params));
	if (a_Callback == nil) then
		Stmt:step();
	else
		for v in Stmt:nrows() do
			a_Callback(v);
		end
	end
	Stmt:finalize();
	return true;
end





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
function SQLite:CreateDBTable(a_TableName, a_Columns)
	assert(a_TableName ~= nil);
	assert(a_Columns ~= nil);
	
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
-- Also deletes areas with invalid gallery from the DB (TODO: move this to a separate function?)
function SQLite:LoadPlayerAreasInWorld(a_WorldName, a_PlayerName)
	assert(a_WorldName ~= nil);
	assert(a_PlayerName ~= nil);
	
	local res = {};
	local ToDelete = {};  -- List of IDs to delete because of missing Gallery
	local stmt = self.DB:prepare("SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex, Name FROM Areas WHERE PlayerName = ? AND WorldName = ?");
	stmt:bind_values(a_PlayerName, a_WorldName);
	for v in stmt:rows() do
		local Gallery = FindGalleryByName(v[10]);
		if (Gallery == nil) then
			table.insert(ToDelete, v[1]);
		else
			local Name = v[12];
			if ((Name == nil) or (Name == "")) then
				Name = Gallery.Name .. " " .. tostring(v[11]);
			end
			local area =
			{
				ID = v[1],
				MinX = v[2], MaxX = v[3], MinZ = v[4], MaxZ = v[5],
				StartX = v[6], EndX = v[7], StartZ = v[8], EndZ = v[9],
				Gallery = Gallery,
				GalleryIndex = v[11],
				Name = Name,
				PlayerName = a_PlayerName,
			};
			table.insert(res, area);
			res[area.Name] = area;
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





--- Loads the areas for a single player in the specified gallery
function SQLite:LoadPlayerAreasInGallery(a_GalleryName, a_PlayerName)
	assert(a_GalleryName ~= nil);
	assert(a_PlayerName ~= nil);
	
	local Gallery = FindGalleryByName(a_GalleryName);
	if (Gallery == nil) then
		-- no such gallery
		return {};
	end
	
	local res = {};
	local stmt = self.DB:prepare("SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryIndex, Name FROM Areas WHERE PlayerName = ? AND GalleryName = ?");
	stmt:bind_values(a_PlayerName, a_GalleryName);
	for v in stmt:rows() do
		local Name = v[11];
		if ((Name == nil) or (Name == "")) then
			Name = a_GalleryName .. " " .. tostring(v[10]);
		end
		local area =
		{
			ID = v[1],
			MinX = v[2], MaxX = v[3], MinZ = v[4], MaxZ = v[5],
			StartX = v[6], EndX = v[7], StartZ = v[8], EndZ = v[9],
			Gallery = Gallery,
			GalleryIndex = v[10],
			PlayerName = a_PlayerName,
			Name = Name,
		};
		table.insert(res, area);
		res[area.Name] = area;
	end
	stmt:finalize();
	
	return res;
end





--- Loads all the areas for a single player
function SQLite:LoadAllPlayerAreas(a_PlayerName)
	assert(a_PlayerName ~= nil);
	
	local res = {};
	local stmt = self.DB:prepare("SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex, Name FROM Areas WHERE PlayerName = ?");
	stmt:bind_values(a_PlayerName);
	for v in stmt:rows() do
		local Gallery = FindGalleryByName(v[10]);
		if (Gallery ~= nil) then
			local Name = v[12];
			if ((Name == nil) or (Name == "")) then
				Name = v[10] .. " " .. tostring(v[11]);
			end
			local area =
			{
				ID = v[1],
				MinX = v[2], MaxX = v[3], MinZ = v[4], MaxZ = v[5],
				StartX = v[6], EndX = v[7], StartZ = v[8], EndZ = v[9],
				Gallery = Gallery,
				GalleryIndex = v[11],
				PlayerName = a_PlayerName,
				Name = Name,
			};
			table.insert(res, area);
			res[area.Name] = area;
		end
	end
	stmt:finalize();
	
	return res;
end





--- Loads an area of the specified name owned by the specified player
function SQLite:LoadPlayerAreaByName(a_PlayerName, a_AreaName)
	assert(a_PlayerName ~= nil);
	assert(a_AreaName ~= nil);
	assert(a_AreaName ~= "");
	
	local res = nil;
	self:ExecuteStatement(
		"SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex FROM Areas WHERE PlayerName = ? AND Name = ?",
		{a_PlayerName, a_AreaName},
		function (a_Values)
			local Gallery = FindGalleryByName(a_Values.GalleryName);
			if (Gallery == nil) then
				return;
			end
			res =
			{
				ID = a_Values.ID,
				MinX = a_Values.MinX, MaxX = a_Values.MaxX, MinZ = a_Values.MinZ, MaxZ = a_Values.MaxZ,
				StartX = a_Values.StartX, EndX = a_Values.EndX, StartZ = a_Values.StartZ, EndZ = a_Values.EndZ,
				Gallery = Gallery,
				GalleryIndex = a_Values.GalleryIndex,
				PlayerName = a_PlayerName,
				Name = a_AreaName,
			};
		end
	);
	
	return res;
end





--- Loads whatever area intersects the given block coords.
-- Returns the loaded area, or nil if there's no area
function SQLite:LoadAreaByPos(a_WorldName, a_BlockX, a_BlockZ)
	assert(a_WorldName ~= nil);
	assert(a_BlockX ~= nil);
	assert(a_BlockZ ~= nil);
	
	a_BlockX = math.floor(a_BlockX);
	a_BlockZ = math.floor(a_BlockZ);
	
	local res = nil;
	self:ExecuteStatement(
		"SELECT ID, MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex, PlayerName, Name FROM Areas WHERE WorldName = ? AND MinX <= ? AND MaxX > ? AND MinZ <= ? AND MaxZ > ?",
		{a_WorldName, a_BlockX, a_BlockX, a_BlockZ, a_BlockZ},
		function (a_Values)
			local Gallery = FindGalleryByName(a_Values.GalleryName);
			if (Gallery == nil) then
				return;
			end
			res =
			{
				ID = a_Values.ID,
				MinX = a_Values.MinX, MaxX = a_Values.MaxX, MinZ = a_Values.MinZ, MaxZ = a_Values.MaxZ,
				StartX = a_Values.StartX, EndX = a_Values.EndX, StartZ = a_Values.StartZ, EndZ = a_Values.EndZ,
				Gallery = Gallery,
				GalleryIndex = a_Values.GalleryIndex,
				PlayerName = a_Values.PlayerName,
				Name = a_Values.Name,
			};
		end
	);
	
	return res;
end





--- Loads the next area index for each gallery
function SQLite:LoadGalleries()
	for idx, gallery in ipairs(g_Galleries) do
		local SQL = "SELECT NextAreaIdx FROM GalleryEnd WHERE GalleryName = \"" .. gallery.Name .. "\"";
		self:DBExec(SQL,
			function (UserData, NumCols, Values, Names)
				for i = 1, NumCols do
					if (Names[i] == "NextAreaIdx") then
						gallery.NextAreaIdx = tonumber(Values[i]);
						return 0;
					end
				end
				return 0;
			end
		);
		if (gallery.NextAreaIdx == nil) then
			self:ExecuteStatement(
				"SELECT MAX(GalleryIndex) as mx FROM Areas WHERE GalleryName = ?",
				{ gallery.Name },
				function (a_Values)
					gallery.NextAreaIdx = a_Values.mx;
				end
			);
			if (gallery.NextAreaIdx == nil) then
				-- This is normal for when the gallery was created for the very first time. Create the record in the DB.
				gallery.NextAreaIdx = 0;
			else
				-- This is not normal, warn the admin about possible DB corruption:
				LOGWARNING("Gallery \"" .. gallery.Name .. "\" doesn't have its NextAreaIdx set in the database, will be reset to " .. gallery.NextAreaIdx);
			end
			self:ExecuteStatement("INSERT INTO GalleryEnd (GalleryName, NextAreaIdx) VALUES (?, ?)", {gallery.Name, gallery.NextAreaIdx});
		end
	end
end





--- Stores a new area into the DB
function SQLite:AddArea(a_Area)
	assert(a_Area ~= nil);
	
	self:ExecuteStatement(
		"INSERT INTO Areas (MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex, WorldName, PlayerName, Name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		{
			a_Area.MinX, a_Area.MaxX, a_Area.MinZ, a_Area.MaxZ,
			a_Area.StartX, a_Area.EndX, a_Area.StartZ, a_Area.EndZ,
			a_Area.Gallery.Name, a_Area.GalleryIndex,
			a_Area.Gallery.WorldName,
			a_Area.PlayerName,
			a_Area.Name,
		}
	);
	a_Area.ID = self.DB:last_insert_rowid();
end





function SQLite:IsAreaNameUsed(a_PlayerName, a_WorldName, a_AreaName)
	assert(a_PlayerName ~= nil);
	assert(a_WorldName ~= nil);
	assert(a_AreaName ~= nil);
	
	local IsNameUsed = false;
	self:ExecuteStatement(
		"SELECT ID FROM Areas WHERE WorldName = ? AND PlayerName = ? AND Name = ?",
		{
			a_WorldName,
			a_PlayerName,
			a_AreaName,
		},
		function (a_Values)
			IsNameUsed = true;
		end
	);
	return IsNameUsed;
end





--- Modifies an existing area's name, if it doesn't collide with any other existing area names
-- If the name is already used, returns false; returns true if renamed successfully
function SQLite:RenameArea(a_PlayerName, a_AreaName, a_NewName)
	assert(a_PlayerName ~= nil);
	assert(a_AreaName ~= nil);
	assert(a_NewName ~= nil);
	
	-- Load the area:
	local Area = self:LoadPlayerAreaByName(a_PlayerName, a_AreaName);
	if (Area == nil) then
		return false, "Area doesn't exist";
	end
	
	-- Check if the name is already used:
	if (self:IsAreaNameUsed(a_PlayerName, Area.Gallery.WorldName, a_NewName)) then
		return false
	end
	
	-- Rename the area:
	self:ExecuteStatement(
		"UPDATE Areas SET Name = ? WHERE GalleryName = ? AND ID = ?",
		{
			a_NewName,
			Area.Gallery.Name,
			Area.ID,
		}
	);
	return true;
end





function SQLite:UpdateGallery(a_Gallery)
	self:ExecuteStatement(
		"UPDATE GalleryEnd SET NextAreaIdx = ? WHERE GalleryName = ?",
		{
			a_Gallery.NextAreaIdx,
			a_Gallery.Name
		}
	);
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
		"Name",                              -- The name given to the area
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




