
-- StorageSQLite.lua

-- Implements the SQLite-backed database storage

--[[
Usage: Call SQLite_CreateStorage() to get an object that has all the functions implemented below.

g_DB = SQLite_CreateStorage(config)
...
local areas = g_DB:LoadAllPlayerAreas()
--]]





--- The SQLite backend namespace:
local StorageSQLite = {}

--- The columns definition for the Areas table
-- A lookup map of LowerCaseColumnName => {ColumnName, ColumnType} is added in the initialization
local g_AreasColumns =
{
	{"ID",              "INTEGER PRIMARY KEY AUTOINCREMENT"},
	{"MinX",            "INTEGER"},  -- The bounds of this area, including the non-buildable "sidewalk"
	{"MaxX",            "INTEGER"},  -- The bounds of this area, including the non-buildable "sidewalk"
	{"MinZ",            "INTEGER"},  -- The bounds of this area, including the non-buildable "sidewalk"
	{"MaxZ",            "INTEGER"},  -- The bounds of this area, including the non-buildable "sidewalk"
	{"StartX",          "INTEGER"},  -- The buildable bounds of this area
	{"EndX",            "INTEGER"},  -- The buildable bounds of this area
	{"StartZ",          "INTEGER"},  -- The buildable bounds of this area
	{"EndZ",            "INTEGER"},  -- The buildable bounds of this area
	{"Name",            "TEXT"},     -- The name given to the area
	{"WorldName",       "TEXT"},     -- Name of the world where the area belongs
	{"PlayerName",      "TEXT"},     -- Name of the owner
	{"GalleryName",     "TEXT"},     -- Name of the gallery from which the area has been claimed
	{"GalleryIndex",    "INTEGER"},  -- Index of the area in the gallery from which this area has been claimed
	{"DateClaimed",     "TEXT"},     -- ISO 8601 DateTime of the claiming
	{"ForkedFromID",    "INTEGER"},  -- The ID of the area from which this one has been forked
	{"IsLocked",        "INTEGER"},  -- If nonzero, the area is locked and cannot be edited unless the player has the "gallery.admin.overridelocked" permission
	{"LockedBy",        "TEXT"},     -- Name of the player who last locked / unlocked the area
	{"DateLocked",      "TEXT"},     -- ISO 8601 DateTime when the area was last locked / unlocked
	{"DateLastChanged", "TEXT"},     -- ISO 8601 DateTime when the area was last changed
	{"TickLastChanged", "INTEGER"},  -- World Age, in ticks, when the area was last changed
	{"NumPlacedBlocks", "INTEGER"},  -- Total number of blocks that the players have placed in the area
	{"NumBrokenBlocks", "INTEGER"},  -- Total number of blocks that the players have broken in the area
	{"EditMaxX",        "INTEGER"},  -- Maximum X coord of the edits within the area
	{"EditMaxY",        "INTEGER"},  -- Maximum Y coord of the edits within the area
	{"EditMaxZ",        "INTEGER"},  -- Maximum Z coord of the edits within the area
	{"EditMinX",        "INTEGER"},  -- Minimum X coord of the edits within the are
	{"EditMinY",        "INTEGER"},  -- Minimum Y coord of the edits within the are
	{"EditMinZ",        "INTEGER"},  -- Minimum Z coord of the edits within the are
}



--- Formats the datetime (as returned by os.time() ) into textual representation used in the DB
function FormatDateTime(a_DateTime)
	assert(type(a_DateTime) == "number");

	return os.date("%Y-%m-%dT%H:%M:%S", a_DateTime);
end





--- Fixes the area table after loading
-- Assigns the proper Gallery object to the area
-- Synthesizes area name if not present
-- Returns the input table on success, nil on failure
function StorageSQLite:FixupAreaAfterLoad(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.GalleryName ~= nil)

	-- Assign the proper Gallery object to the area:
	if (a_Area.Gallery == nil) then
		a_Area.Gallery = FindGalleryByName(a_Area.GalleryName);
		if (a_Area.Gallery == nil) then
			return;
		end
	end

	-- Fix area name, if not present:
	if ((a_Area.Name == nil) or (a_Area.Name == "")) then
		a_Area.Name = a_Area.GalleryName .. " " .. tostring(a_Area.GalleryIndex)
	end

	-- Convert IsLocked from "number or bool" to "bool":
	a_Area.IsLocked = (a_Area.IsLocked ~= 0) and (a_Area.IsLocked ~= false) and (a_Area.IsLocked ~= nil)

	-- Add some defaults:
	a_Area.NumPlacedBlocks = a_Area.NumPlacedBlocks or 0
	a_Area.NumBrokenBlocks = a_Area.NumBrokenBlocks or 0

	return a_Area
end





--- Returns a table of top area counts per player, up to a_Limit rows (sorted by count desc)
--[[
If a_PlayerName is given, that player is added to the table as well (if not already there)
The table returned has the format:
{
	{NumAreas = Count1, PlayerName = "PlayerName1"},
	{NumAreas = Count2, PlayerName = "PlayerName2"},
	...
}
--]]

function StorageSQLite:GetPlayerAreaCounts(a_Limit, a_PlayerName)
	a_Limit = tonumber(a_Limit) or 5

	-- Add the top N players:
	local res = {}
	self:ExecuteStatement(
		"SELECT COUNT(*) AS NumAreas, PlayerName FROM Areas GROUP BY PlayerName ORDER BY NumAreas DESC LIMIT ?", -- .. a_Limit,
		{ a_Limit },
		function (a_Values)
			local PlayerName = a_Values["PlayerName"]
			if (a_Values["NumAreas"] and PlayerName) then
				table.insert(res, {NumAreas = a_Values["NumAreas"], PlayerName = PlayerName})
				if (PlayerName == a_PlayerName) then
					a_PlayerName = nil  -- Do not add the specified player, they're already present
				end
			end
		end
	)

	-- Add a_Player, if not already added:
	if (a_PlayerName) then
		local HasFound = false
		self:ExecuteStatement(
			"SELECT COUNT(*) AS NumAreas FROM Areas WHERE PlayerName = ?",
			{ a_PlayerName },
			function (a_Values)
				if (a_Values["NumAreas"] and a_Values["PlayerName"]) then
					table.insert(res, {NumAreas = a_Values["NumAreas"], PlayerName = a_PlayerName})
					HasFound = true
				end
			end
		)
		if not(HasFound) then
			table.insert(res, {NumAreas = 0, PlayerName = a_PlayerName})
		end
	end

	return res
end





--- Loads the areas for a single player in the specified world
-- Returns a table that has both an array of the area objects, as well as a map AreaName -> area object
-- Also deletes areas with invalid gallery from the DB (TODO: move this to a separate function?)
function StorageSQLite:LoadPlayerAreasInWorld(a_WorldName, a_PlayerName)
	assert(a_WorldName ~= nil);
	assert(a_PlayerName ~= nil);

	local res = {};
	local ToDelete = {};  -- List of IDs to delete because of missing Gallery
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE PlayerName = ? AND WorldName = ?",
		{
			a_PlayerName,
			a_WorldName,
		},
		function (a_Values)
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area == nil) then
				-- The area is invalid (bad gallery etc), schedule it for removing:
				table.insert(ToDelete, a_Values.ID);
			else
				table.insert(res, area);
				res[area.Name] = area;
			end
		end
	)

	-- Remove areas that reference non-existent galleries:
	if (ToDelete[1] ~= nil) then
		local stmt = self.DB:prepare("DELETE FROM Areas WHERE ID = ?");
		for idx, id in ipairs(ToDelete) do
			stmt:bind_values(id);
			stmt:step();
		end
		stmt:finalize();
	end

	return res;
end





--- Loads up to a_NumAreas most recently claimed areas
-- Returns an array-table of area descriptions, in recentness order (most recent first)
function StorageSQLite:LoadLatestClaimedAreas(a_NumAreas)
	-- Check params:
	assert(self)
	assert(tonumber(a_NumAreas))

	-- Query the DB:
	local res = {}
	self:ExecuteStatement(
		"SELECT * FROM Areas ORDER BY DateClaimed DESC LIMIT " .. tonumber(a_NumAreas),
		{},
		function (a_Values)
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area) then
				table.insert(res, area)
			end
		end
	)
	return res
end





--- Loads up to a_NumAreas most recently changed areas
-- Returns an array-table of area descriptions, in recentness order (most recent first)
function StorageSQLite:LoadLatestChangedAreas(a_NumAreas)
	-- Check params:
	assert(self)
	assert(tonumber(a_NumAreas))

	-- Query the DB:
	local res = {}
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE ((NumPlacedBlocks > 0) OR (NumBrokenBlocks > 0)) ORDER BY DateLastChanged DESC LIMIT " .. tonumber(a_NumAreas),
		{},
		function (a_Values)
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area) then
				table.insert(res, area)
			end
		end
	)
	return res
end





--- Loads all player allowances in the specified world
-- Returns a table that has both an array of the area objects, as well as a map AreaName -> area object
function StorageSQLite:LoadPlayerAllowancesInWorld(a_WorldName, a_PlayerName)
	local res = {};
	self:ExecuteStatement(
		[[
			SELECT Areas.MinX AS MinX, Areas.MinZ AS MinZ, Areas.MaxX AS MaxX, Areas.MaxZ as MaxZ,
				Areas.StartX AS StartX, Areas.StartZ AS StartZ, Areas.EndX AS EndX, Areas.EndZ AS EndZ,
				Areas.PlayerName AS PlayerName, Areas.Name AS Name, Areas.ID AS ID,
				Areas.GalleryIndex AS GalleryIndex, Areas.GalleryName AS GalleryName,
				Areas.IsLocked AS IsLocked, Areas.LockedBy AS LockedBy, Areas.DateLocked as DateLocked
			FROM Areas INNER JOIN Allowances ON Areas.ID = Allowances.AreaID
			WHERE Areas.WorldName = ? AND Allowances.FriendName = ?
		]],
		{
			a_WorldName,
			a_PlayerName,
		},
		function (a_Values)
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area == nil) then
				return;
			end
			table.insert(res, area)
			res[area.Name] = area
		end
	);
	return res;
end





--- Loads the areas for a single player in the specified gallery
-- Returns a table that has both an array of the area objects, as well as a map AreaName -> area object
function StorageSQLite:LoadPlayerAreasInGallery(a_GalleryName, a_PlayerName)
	assert(a_GalleryName ~= nil);
	assert(a_PlayerName ~= nil);

	local Gallery = FindGalleryByName(a_GalleryName);
	if (Gallery == nil) then
		-- no such gallery
		return {};
	end

	local res = {};
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE PlayerName = ? AND GalleryName = ?",
		{
			a_PlayerName,
			a_GalleryName,
		},
		function (a_Values)
			-- Assign the proper gallery object to the area:
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area == nil) then
				return;
			end
			table.insert(res, area);
			res[area.Name] = area;
		end
	)

	return res;
end





--- Loads all the areas in the DB
-- Returns a table that has both an array of the area objects, as well as a map AreaName -> area object
function StorageSQLite:LoadAllAreas()
	local res = {};
	self:ExecuteStatement(
		"SELECT * FROM Areas",
		{},
		function (a_Values)
			-- Assign the proper gallery:
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area == nil) then
				return
			end
			table.insert(res, area)
			res[area.Name] = area
		end
	)

	return res;
end





--- Loads all the areas for a single player
-- Returns a table that has both an array of the area objects, as well as a map AreaName -> area object
function StorageSQLite:LoadAllPlayerAreas(a_PlayerName)
	assert(a_PlayerName ~= nil);

	local res = {};
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE PlayerName = ?",
		{
			a_PlayerName
		},
		function (a_Values)
			-- Assign the proper gallery:
			local area = self:FixupAreaAfterLoad(a_Values)
			if (area == nil) then
				return
			end
			table.insert(res, area)
			res[area.Name] = area
		end
	)

	return res;
end





--- Loads an area of the specified name owned by the specified player
function StorageSQLite:LoadPlayerAreaByName(a_PlayerName, a_AreaName)
	assert(a_PlayerName ~= nil);
	assert(a_AreaName ~= nil);
	assert(a_AreaName ~= "");

	local res = nil;
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE PlayerName = ? AND Name = ?",
		{a_PlayerName, a_AreaName},
		function (a_Values)
			-- Assign the proper gallery:
			res = self:FixupAreaAfterLoad(a_Values)
		end
	);

	return res;
end





--- Loads an area identified by its ID
-- Returns the loaded area, or nil if there's no such area
function StorageSQLite:LoadAreaByID(a_AreaID)
	-- Check params:
	a_AreaID = tonumber(a_AreaID)
	assert(a_AreaID ~= nil)

	local res = nil
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE ID = ?",
		{
			a_AreaID
		},
		function (a_Values)
			res = self:FixupAreaAfterLoad(a_Values)
		end
	)

	return res
end





--- Loads whatever area intersects the given block coords.
-- Returns the loaded area, or nil if there's no area
function StorageSQLite:LoadAreaByPos(a_WorldName, a_BlockX, a_BlockZ)
	assert(a_WorldName ~= nil);
	assert(a_BlockX ~= nil);
	assert(a_BlockZ ~= nil);

	a_BlockX = math.floor(a_BlockX);
	a_BlockZ = math.floor(a_BlockZ);

	local res = nil;
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE WorldName = ? AND MinX <= ? AND MaxX > ? AND MinZ <= ? AND MaxZ > ?",
		{a_WorldName, a_BlockX, a_BlockX, a_BlockZ, a_BlockZ},
		function (a_Values)
			res = self:FixupAreaAfterLoad(a_Values)
		end
	);

	return res;
end





--- Loads the next area index for each gallery
function StorageSQLite:LoadGalleries()
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





--- Returns an array Areas for the areas in the specified index range in the specified gallery
-- If an area is not claimed, the array entry for it will be {}
-- a_SortBy is the column on which to sort. It is checked against the list of columns and if it doesn't fit any, the default "GalleryIndex" is used instead
function StorageSQLite:LoadGalleryAreasRange(a_GalleryName, a_SortBy, a_StartIndex, a_EndIndex)
	-- Check the a_SortBy column:
	if not(g_AreasColumns[a_SortBy:lower()]) then
		a_SortBy = "GalleryIndex"
	end
	if (g_AreasColumns[a_SortBy:lower()][2] == "TEXT") then
		a_SortBy = a_SortBy .. " COLLATE NOCASE"
	end

	-- Get the results:
	local res = {}
	self:ExecuteStatement(
		"SELECT * FROM Areas WHERE GalleryName = ? ORDER BY " .. a_SortBy .. " LIMIT ? OFFSET ?",
		{
			a_GalleryName,
			a_EndIndex - a_StartIndex,
			a_StartIndex
		},
		function (a_Values)
			table.insert(res, self:FixupAreaAfterLoad(a_Values) or {})
		end
	)
	return res
end





--- Stores a new area into the DB
function StorageSQLite:AddArea(a_Area)
	-- Check params:
	assert(type(a_Area) == "table");

	-- Add in the DB:
	local DateTimeNow = FormatDateTime(os.time())
	self:ExecuteStatement(
		"INSERT INTO Areas \
			(MinX, MaxX, MinZ, MaxZ, StartX, EndX, StartZ, EndZ, GalleryName, GalleryIndex, WorldName, \
			PlayerName, Name, DateClaimed, ForkedFromID, IsLocked, DateLastChanged, TickLastChanged, \
			NumPlacedBlocks, NumBrokenBlocks) \
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		{
			a_Area.MinX, a_Area.MaxX, a_Area.MinZ, a_Area.MaxZ,
			a_Area.StartX, a_Area.EndX, a_Area.StartZ, a_Area.EndZ,
			a_Area.Gallery.Name, a_Area.GalleryIndex,
			a_Area.Gallery.WorldName,
			a_Area.PlayerName,
			a_Area.Name,
			DateTimeNow,
			(a_Area.ForkedFrom or {}).ID or -1,
			a_Area.IsLocked or 0,
			DateTimeNow,
			a_Area.Gallery.World:GetWorldAge(),
			a_Area.NumPlacedBlocks or 0,
			a_Area.NumBrokenBlocks or 0,
		}
	);
	a_Area.ID = self.DB:last_insert_rowid();
end





--- Checks the specified gallery's area indices against the Claimed and Removed area lists.
-- Areas that are in neither are added to the Removed list
function StorageSQLite:CheckAreaIndices(a_Gallery, a_RemovedBy)
	-- Check params:
	a_RemovedBy = tostring(a_RemovedBy)
	assert(type(a_Gallery) == "table")
	assert(a_Gallery.Name)
	assert(a_RemovedBy)

	-- Walk through all claimed areas, remember them in a map of GalleryIndex -> true:
	local IsPresent = {}
	local MaxIndex = 0
	self:ExecuteStatement(
		"SELECT GalleryIndex FROM Areas WHERE GalleryName = ?",
		{
			a_Gallery.Name
		},
		function (a_Values)
			IsPresent[a_Values.GalleryIndex] = true
			if (a_Values.GalleryIndex > MaxIndex) then
				MaxIndex = a_Values.GalleryIndex
			end
		end
	)

	-- Walk through all removed areas, add them to the map:
	self:ExecuteStatement(
		"SELECT GalleryIndex FROM RemovedAreas WHERE GalleryName = ?",
		{
			a_Gallery.Name
		},
		function (a_Values)
			IsPresent[a_Values.GalleryIndex] = true
		end
	)

	-- Add all areas between index 0 and MaxIndex that are not present into the RemovedAreas table:
	local now = FormatDateTime(os.time())
	for idx = 0, MaxIndex do
		if not(IsPresent[idx]) then
			self:ExecuteStatement(
				"INSERT INTO RemovedAreas(GalleryName, GalleryIndex, RemovedBy, DateRemoved) VALUES (?, ?, ?, ?)",
				{
					a_Gallery.Name,
					idx,
					a_RemovedBy,
					now
				}
			)
		end  -- if not(IsPresent)
	end  -- for idx

	-- Remove areas from RemovedAreas that are above the MaxIndex:
	self:ExecuteStatement(
		"DELETE FROM RemovedAreas WHERE GalleryName = ? AND GalleryIndex > ?",
		{
			a_Gallery.Name,
			MaxIndex
		}
	)
end





--- Claims an area either from the list of removed areas, or a fresh new one
-- Returns the Area table, or nil and string description of the error
function StorageSQLite:ClaimArea(a_Gallery, a_PlayerName, a_ForkedFromArea)
	-- Check params:
	assert(type(a_Gallery) == "table")
	assert(type(a_PlayerName) == "string")
	assert((a_ForkedFromArea == nil) or (type(a_ForkedFromArea) == "table"))

	-- Get the index for the new area:
	local NextAreaIdx = self:PopRemovedArea(a_Gallery)
	if (NextAreaIdx == -1) then
		NextAreaIdx = a_Gallery.NextAreaIdx
	end
	if (NextAreaIdx >= a_Gallery.MaxAreaIdx) then
		return nil, "The gallery is full";
	end
	local AreaX, AreaZ = AreaIndexToCoords(NextAreaIdx, a_Gallery)

	local MinX, MaxX, MinZ, MaxZ = AreaCoordsToBlockCoords(a_Gallery, AreaX, AreaZ);

	local Area = {
		MinX = MinX,
		MaxX = MaxX,
		MinZ = MinZ,
		MaxZ = MaxZ,
		StartX = MinX + a_Gallery.AreaEdge,
		EndX   = MaxX - a_Gallery.AreaEdge,
		StartZ = MinZ + a_Gallery.AreaEdge,
		EndZ   = MaxZ - a_Gallery.AreaEdge,
		Gallery = a_Gallery,
		GalleryIndex = NextAreaIdx,
		PlayerName = a_PlayerName,
		Name = a_Gallery.Name .. " " .. tostring(NextAreaIdx),
		ForkedFrom = a_ForkedFromArea,
		NumPlacedBlocks = 0,
		NumBrokenBlocks = 0,
	};
	self:AddArea(Area);

	-- Update the next area idx in the gallery object:
	if (a_Gallery.NextAreaIdx == NextAreaIdx) then
		a_Gallery.NextAreaIdx = NextAreaIdx + 1;
		self:UpdateGallery(a_Gallery);
	end

	return Area
end





--- Marks the specified area as locked in the DB
-- a_LockedByName is the name of the player locking the area
function StorageSQLite:LockArea(a_Area, a_LockedByName)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID ~= nil)
	assert(type(a_LockedByName) == "string")

	-- Set the area's properties:
	a_Area.IsLocked = true
	a_Area.LockedBy = a_LockedByName
	a_Area.DateLocked = FormatDateTime(os.time())

	-- Update the DB:
	self:ExecuteStatement(
		"UPDATE Areas SET IsLocked = ?, LockedBy = ?, DateLocked = ? WHERE ID = ?",
		{
			1,
			a_LockedByName,
			a_Area.DateLocked,
			a_Area.ID
		}
	)
end





--- Removes an area from the RemovedAreas table in the specified gallery, and returns its GalleryIndex
-- Returns -1 if there's no suitable area in the RemovedAreas table
function StorageSQLite:PopRemovedArea(a_Gallery)
	-- Check params:
	assert(type(a_Gallery) == "table")

	-- Get the lowest index stored in the DB:
	local AreaIndex = -1
	local AreaID = -1
	self:ExecuteStatement(
		"SELECT ID, GalleryIndex FROM RemovedAreas WHERE GalleryName = ? LIMIT 1",
		{
			a_Gallery.Name
		},
		function (a_Values)
			AreaIndex = a_Values["GalleryIndex"]
			AreaID = a_Values["ID"]
		end
	)

	-- If the area is valid, remove it from the table:
	if (AreaID < 0) then
		return -1
	end
	self:ExecuteStatement(
		"DELETE FROM RemovedAreas WHERE ID = ?",
		{
			AreaID
		}
	)

	return AreaIndex
end





function StorageSQLite:IsAreaNameUsed(a_PlayerName, a_WorldName, a_AreaName)
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





--- Removes the claim on the specified area
-- The area is recycled into the RemovedAreas table which then serves as source of new areas for claiming
-- a_RemovedBy is the name of the player removing the area
function StorageSQLite:RemoveArea(a_Area, a_RemovedBy)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(type(a_RemovedBy) == "string")

	-- TODO: Check that the area really exists

	-- Add the area to the RemovedAreas table:
	self:ExecuteStatement(
		"INSERT INTO RemovedAreas (GalleryIndex, GalleryName, DateRemoved, RemovedBy) VALUES (?, ?, ?, ?)",
		{
			a_Area.GalleryIndex,
			a_Area.Gallery.Name,
			FormatDateTime(os.time()),
			a_RemovedBy
		}
	)

	-- Remove the area from the Areas table:
	self:ExecuteStatement(
		"DELETE FROM Areas WHERE ID = ?",
		{
			a_Area.ID
		}
	)

	-- Remove any allowances on the area:
	self:ExecuteStatement(
		"DELETE FROM Allowances WHERE AreaID = ?",
		{
			a_Area.ID
		}
	)
end





--- Modifies an existing area's name, if it doesn't collide with any other existing area names
-- If the name is already used, returns false; returns true if renamed successfully
function StorageSQLite:RenameArea(a_PlayerName, a_AreaName, a_NewName)
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





--- Marks the specified area as unlocked in the DB
-- a_UnlockedByName is the name of the player unlocking the area
function StorageSQLite:UnlockArea(a_Area, a_UnlockedByName)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID ~= nil)
	assert(type(a_UnlockedByName) == "string")

	-- Set the area's properties:
	a_Area.IsLocked = false
	a_Area.LockedBy = a_UnlockedByName
	a_Area.DateLocked = FormatDateTime(os.time())

	-- Update the DB:
	self:ExecuteStatement(
		"UPDATE Areas SET IsLocked = ?, LockedBy = ?, DateLocked = ? WHERE ID = ?",
		{
			0,
			a_UnlockedByName,
			a_Area.DateLocked,
			a_Area.ID
		}
	)
end





--- Updates the NumPlacedBlocks and NumBrokenBlocks values in the DB for the specified area
function StorageSQLite:UpdateAreaBlockStats(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID ~= nil)

	-- Update the DB:
	self:ExecuteStatement(
		"UPDATE Areas SET NumPlacedBlocks = ?, NumBrokenBlocks = ? WHERE ID = ?",
		{
			a_Area.NumPlacedBlocks,
			a_Area.NumBrokenBlocks,
			a_Area.ID
		}
	)
end





--- Updates the DateLastChanged, TickLastChanged, NumPlacedBlocks, NumBrokenBlocks and edit range values in the DB for the specified area
function StorageSQLite:UpdateAreaBlockStatsAndEditRange(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID)

	-- Update the DB:
	self:ExecuteStatement(
		"UPDATE Areas SET \
		NumPlacedBlocks = ?, NumBrokenBlocks = ?, \
		DateLastChanged = ?, TickLastChanged = ?, \
		EditMinX = ?, EditMinY = ?, EditMinZ = ?, \
		EditMaxX = ?, EditMaxY = ?, EditMaxZ = ? \
		WHERE ID = ?",
		{
			a_Area.NumPlacedBlocks,
			a_Area.NumBrokenBlocks,
			FormatDateTime(os.time()), a_Area.Gallery.World:GetWorldAge(),
			a_Area.EditMinX, a_Area.EditMinY, a_Area.EditMinZ,
			a_Area.EditMaxX, a_Area.EditMaxY, a_Area.EditMaxZ,
			a_Area.ID
		}
	)
end





--- Updates the edit range values (MaxEditX etc.) in the DB for the specified area
function StorageSQLite:UpdateAreaEditRange(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID)

	-- Update the DB:
	self:ExecuteStatement(
		"UPDATE Areas SET EditMaxX = ?, EditMaxY = ?, EditMaxZ = ?, EditMinX = ?, EditMinY = ?, EditMinZ = ? WHERE ID = ?",
		{
			a_Area.EditMaxX, a_Area.EditMaxY, a_Area.EditMaxZ,
			a_Area.EditMinX, a_Area.EditMinY, a_Area.EditMinZ,
			a_Area.ID
		}
	)
end





--- Updates the DateLastChanged, TickLastChanged, NumPlacedBlocks and NumBrokenBlocks values in the DB for the specified area
function StorageSQLite:UpdateAreaStats(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID ~= nil)

	-- Update the DB:
	self:ExecuteStatement(
		"UPDATE Areas SET DateLastChanged = ?, TickLastChanged = ?, NumPlacedBlocks = ?, NumBrokenBlocks = ? WHERE ID = ?",
		{
			FormatDateTime(os.time()),
			a_Area.Gallery.World:GetWorldAge(),
			a_Area.NumPlacedBlocks,
			a_Area.NumBrokenBlocks,
			a_Area.ID
		}
	)
end





function StorageSQLite:UpdateGallery(a_Gallery)
	self:ExecuteStatement(
		"UPDATE GalleryEnd SET NextAreaIdx = ? WHERE GalleryName = ?",
		{
			a_Gallery.NextAreaIdx,
			a_Gallery.Name
		}
	);
end





--- Adds the playername to the list of allowed players in the specified area
-- Returns success state and an error message in case of failure
function StorageSQLite:AllowPlayerInArea(a_Area, a_PlayerName)
	assert(a_Area ~= nil)
	assert(a_Area.ID ~= nil)
	assert(type(a_PlayerName) == "string")

	-- First try if the pairing is already there:
	local IsThere = false
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Allowances WHERE AreaID = ? AND FriendName = ?",
		{
			a_Area.ID,
			a_PlayerName
		},
		function (a_Values)
			IsThere = true
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end
	if (IsThere) then
		return false, a_PlayerName .. " is already allowed"
	end

	-- Insert the new pairing
	return self:ExecuteStatement(
		"INSERT INTO Allowances (AreaID, FriendName) VALUES (?, ?)",
		{
			a_Area.ID,
			a_PlayerName
		}
	)
end





--- Removes the playername from the list of allowed players in the specified area
-- Returns success state and an error message in case of failure
function StorageSQLite:DenyPlayerInArea(a_Area, a_PlayerName)
	assert(a_Area ~= nil)
	assert(a_Area.ID ~= nil)
	assert(type(a_PlayerName) == "string")

	-- First try whether the pairing is already there:
	local IsThere = false
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Allowances WHERE AreaID = ? AND FriendName = ?",
		{
			a_Area.ID,
			a_PlayerName
		},
		function (a_Values)
			IsThere = true;
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end
	if not(IsThere) then
		return false, a_PlayerName .. " has not been allowed"
	end

	-- Insert the new pairing
	return self:ExecuteStatement(
		"DELETE FROM Allowances WHERE AreaID = ? AND FriendName = ?",
		{
			a_Area.ID,
			a_PlayerName
		}
	)
end





function SQLite_CreateStorage(a_Params)
	-- Create a new object and extend it with SQLite basic methods and then StorageSQLite methods:
	local res = {}
	SQLite_extend(res)
	for k, v in pairs(StorageSQLite) do
		assert(not(res[k]))  -- Duplicate method?
		res[k] = v
	end

	-- Open the DB:
	local DBFile = a_Params.File or "Galleries.sqlite"
	local isSuccess, errCode, errMsg = res:OpenDB(DBFile)
	if not(isSuccess) then
		LOGWARNING(string.format("%sCannot open database \"%s\": error %s: %s",
			PLUGIN_PREFIX, DBFile, errCode or "<no code>", errMsg or "<no message>"
		))
		error(errMsg or "<no message>")  -- Abort the plugin
	end

	-- Create the tables, if they don't exist yet:
	local GalleryEndColumns =
	{
		{"GalleryName", "TEXT"},
		{"NextAreaIdx", "INTEGER"},
	};
	local AllowancesColumns =
	{
		{"AreaID", "INTEGER"},
		{"FriendName", "TEXT"},
	};
	local RemovedAreasColumns =
	{
		{"ID",           "INTEGER PRIMARY KEY AUTOINCREMENT"},
		{"GalleryName",  "TEXT"},
		{"GalleryIndex", "INTEGER"},
		{"RemovedBy",    "TEXT"},
		{"DateRemoved",  "TEXT"},
	}
	if (
		not(res:CreateDBTable("Areas",        g_AreasColumns)) or
		not(res:CreateDBTable("GalleryEnd",   GalleryEndColumns)) or
		not(res:CreateDBTable("Allowances",   AllowancesColumns)) or
		not(res:CreateDBTable("RemovedAreas", RemovedAreasColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!")
		error("Cannot create DB tables!")
	end

	-- Areas that have no DateClaimed assigned get a dummy value:
	res:ExecuteStatement("UPDATE Areas SET DateClaimed='1999-01-01T00:00:00' WHERE DateClaimed IS NULL")

	-- Set each area with an unassigned DateLastChanged to its claiming date, so that the value is always present:
	res:ExecuteStatement("UPDATE Areas SET DateLastChanged = DateClaimed WHERE DateLastChanged IS NULL")

	-- Set each area with an unassigned TickLastChanged to zero tick:
	res:ExecuteStatement("UPDATE Areas SET TickLastChanged = 0 WHERE TickLastChanged IS NULL")

	-- Set initial statistics values for areas that pre-date statistics collection:
	res:ExecuteStatement("UPDATE Areas SET NumPlacedBlocks = 0 WHERE NumPlacedBlocks IS NULL")
	res:ExecuteStatement("UPDATE Areas SET NumBrokenBlocks = 0 WHERE NumBrokenBlocks IS NULL")

	return res
end




