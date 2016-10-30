
-- Gallery.lua

-- Defines the main entrypoint to the Gallery plugin





--- The main list of galleries available
-- Is both an array of gallery objects and a map (gallery name -> gallery object)
g_Galleries = {};

--- The per-world per-player list of owned areas. Access as "g_Areas[WorldName][PlayerName]"
-- Each such item is both an array of area objects and a map of area name -> area object
g_PlayerAreas = {};

--- The per-world per-player array of allowances. Access as "g_PlayerAllowances[WorldName][PlayerName]"
-- Each such item is both an array of area objects and a map of area name -> area object
g_PlayerAllowances = {};





--[[
Each gallery is loaded from the config file, checked for validity and preprocessed to contain the following members:
{
	AreaEdge -- Edge of each area that is "public", i. e. non-buildable even by area's owner.
	AreaMaxX, AreaMaxZ, AreaMinX, AreaMinZ -- The (tight) bounding box for all the areas in the gallery
	AreaSizeX, AreaSizeZ -- Dimensions of each area in the gallery
	FillStrategy -- Strategy used for allocating the areas in the gallery.
	MaxAreaIdx -- The maximum index of a valid area in this gallery
	MinX, MinZ, MaxX, MaxZ -- Dimensions of the gallery, in block coords
	Name -- Name of the gallery, as used in the commands
	NextAreaIdx -- index of the next-to-be-claimed area
	NumAreasPerX, NumAreasPerZ -- Number of areas in the X and Z directions
	TeleportCoordY  -- Y coord where the player is teleported upon claiming.
	World -- The cWorld where the gallery is placed
	WorldName -- Name of the world for which the gallery is defined.

	-- Optional members:
	AreaTemplate -- The name of the schematic file that will be used to initialize new areas within the gallery
	AreaTemplateSchematic -- The loaded schematic used for new areas
	AreaTemplateSchematicTop -- An empty schematic that fills the space from the AreaTemplateSchematic to the top of the world
	AreaTop -- The Y size of the AreaTemplateSchematic
	Biome -- The biome to set in the gallery. String in the config file, biome type in the in-memory structure.
}
--]]





--- Converts area index to area coords in the specified gallery
function AreaIndexToCoords(a_Index, a_Gallery)
	if (a_Gallery.FillStrategy == "z+x+") then
		local AreaX = math.floor(a_Index / a_Gallery.NumAreasPerZ);
		local AreaZ = a_Index % a_Gallery.NumAreasPerZ;
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "z-x+") then
		local AreaX = math.floor(a_Index / a_Gallery.NumAreasPerZ);
		local AreaZ = a_Gallery.NumAreasPerZ - (a_Index % a_Gallery.NumAreasPerZ) - 1;
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "z+x-") then
		local AreaX = a_Gallery.NumAreasPerX - math.floor(a_Index / a_Gallery.NumAreasPerZ) - 1;
		local AreaZ = a_Index % a_Gallery.NumAreasPerZ;
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "z-x-") then
		local AreaX = a_Gallery.NumAreasPerX - math.floor(a_Index / a_Gallery.NumAreasPerZ) - 1;
		local AreaZ = a_Gallery.NumAreasPerZ - (a_Index % a_Gallery.NumAreasPerZ) - 1;
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "x+z+") then
		local AreaX = a_Index % a_Gallery.NumAreasPerX;
		local AreaZ = math.floor(a_Index / a_Gallery.NumAreasPerX);
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "x-z+") then
		local AreaX = a_Gallery.NumAreasPerX - (a_Index % a_Gallery.NumAreasPerX) - 1;
		local AreaZ = math.floor(a_Index / a_Gallery.NumAreasPerZ);
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "x+z-") then
		local AreaX = a_Index % a_Gallery.NumAreasPerX;
		local AreaZ = a_Gallery.NumAreasPerZ - math.floor(a_Index / a_Gallery.NumAreasPerX) - 1;
		return AreaX, AreaZ;
	elseif (a_Gallery.FillStrategy == "x-z-") then
		local AreaX = a_Gallery.NumAreasPerX - (a_Index % a_Gallery.NumAreasPerX) - 1;
		local AreaZ = a_Gallery.NumAreasPerZ - math.floor(a_Index / a_Gallery.NumAreasPerX) - 1;
		return AreaX, AreaZ;
	end
	-- This shouldn't happen, the FillStrategy is be checked in CheckGallery()
	LOGWARNING("Unknown FillStrategy: \"" .. a_Gallery.FillStrategy .. "\"");
end





--- Converts Area coords into blockcoords in the specified gallery.
function AreaCoordsToBlockCoords(a_Gallery, a_AreaX, a_AreaZ)
	local X = a_AreaX * a_Gallery.AreaSizeX;
	local Z = a_AreaZ * a_Gallery.AreaSizeZ;
	if (a_Gallery.FillStrategy == "x+z+") then
		return a_Gallery.MinX + X, a_Gallery.MinX + X + a_Gallery.AreaSizeX, a_Gallery.MinZ + Z, a_Gallery.MinZ + Z + a_Gallery.AreaSizeZ;
	elseif (a_Gallery.FillStrategy == "x+z-") then
		return a_Gallery.MinX + X, a_Gallery.MinX + X + a_Gallery.AreaSizeX, a_Gallery.MaxZ - Z - a_Gallery.AreaSizeZ, a_Gallery.MinZ - Z;
	elseif (a_Gallery.FillStrategy == "x-z+") then
		return a_Gallery.MaxX - X - a_Gallery.AreaSizeX, a_Gallery.MaxX - X, a_Gallery.MinZ + Z, a_Gallery.MinZ + Z + a_Gallery.AreaSizeZ;
	elseif (a_Gallery.FillStrategy == "x-z-") then
		return a_Gallery.MaxX - X - a_Gallery.AreaSizeX, a_Gallery.MaxX - X, a_Gallery.MaxZ - Z - a_Gallery.AreaSizeZ, a_Gallery.MaxZ - Z;
	elseif (a_Gallery.FillStreategy == "z+x+") then
		return a_Gallery.MinX + X, a_Gallery.MinX + X + a_Gallery.AreaSizeX, a_Gallery.MinZ + Z, a_Gallery.MinZ + Z + a_Gallery.AreaSizeZ;
	elseif (a_Gallery.FillStrategy == "z-x+") then
		return a_Gallery.MinX + X, a_Gallery.MinX + X + a_Gallery.AreaSizeX, a_Gallery.MaxZ - Z - a_Gallery.AreaSizeZ, a_Gallery.MaxZ - Z;
	elseif (a_Gallery.FillStrategy == "z+x-") then
		return a_Gallery.MaxX - X - a_Gallery.AreaSizeX, a_Gallery.MaxX - X, a_Gallery.MinZ + Z, a_Gallery.MinZ + Z + a_Gallery.AreaSizeZ;
	elseif (a_Gallery.FillStrategy == "z-x-") then
		return a_Gallery.MaxX - X - a_Gallery.AreaSizeX, a_Gallery.MaxX - X, a_Gallery.MaxZ - Z - a_Gallery.AreaSizeZ, a_Gallery.MaxZ - Z;
	end
end





--- Claims an area in a gallery for the specified player. Returns a table describing the area
-- If there's no space left in the gallery, returns nil and error message
-- a_ForkedFromArea is an optional param, specifying the area from which the new area is forking; used to write statistics into DB
function ClaimArea(a_Player, a_Gallery, a_ForkedFromArea)
	-- Check params:
	assert(tolua.type(a_Player) == "cPlayer")
	assert(type(a_Gallery) == "table")
	assert((a_ForkedFromArea == nil) or (type(a_ForkedFromArea) == "table"))

	-- Claim in the DB:
	local Area = g_DB:ClaimArea(a_Gallery, a_Player:GetName(), a_ForkedFromArea)

	-- Add this area to Player's areas:
	local PlayerAreas = GetPlayerAreas(a_Player);
	table.insert(PlayerAreas, Area);
	PlayerAreas[Area.Name] = Area;

	return Area;
end





--- Returns the chunk coords of chunks that intersect the given area
-- The returned value has the form of { {Chunk1x, Chunk1z}, {Chunk2x, Chunk2z}, ...}
function GetAreaChunkCoords(a_Area)
	assert(type(a_Area) == "table");
	local MinChunkX = math.floor(a_Area.MinX / 16);
	local MinChunkZ = math.floor(a_Area.MinZ / 16);
	local MaxChunkX = math.floor((a_Area.MaxX + 15) / 16);
	local MaxChunkZ = math.floor((a_Area.MaxZ + 15) / 16);
	local res = {};
	for z = MinChunkZ, MaxChunkZ do
		for x = MinChunkX, MaxChunkX do
			table.insert(res, {x, z});
		end
	end
	assert(#res > 0);
	return res;
end





--- Copies the contents of src area into dst area, then calls the callback
function CopyAreaContents(a_SrcArea, a_DstArea, a_DoneCallback)
	assert(type(a_SrcArea) == "table");
	assert(type(a_DstArea) == "table");
	assert(a_SrcArea.Gallery == a_DstArea.Gallery);  -- Only supports copying in the same gallery
	assert(a_SrcArea.Gallery.World ~= nil);
	assert((a_DoneCallback == nil) or (type(a_DoneCallback) == "function"));

	local Clipboard = cBlockArea();
	local World = a_SrcArea.Gallery.World;

	-- Callback that is scheduled once the src is copied into Clipboard
	local function WriteDst()
		World:ChunkStay(GetAreaChunkCoords(a_DstArea), nil,
			function()
				Clipboard:Write(World, a_DstArea.MinX, 0, a_DstArea.MinZ);
				if (a_DoneCallback ~= nil) then
					a_DoneCallback();
				end
			end
		)
	end

	-- Copy the source area into a clipboard:
	World:ChunkStay(GetAreaChunkCoords(a_SrcArea), nil,
		function()
			Clipboard:Read(World, a_SrcArea.MinX, a_SrcArea.MaxX - 1, 0, 255, a_SrcArea.MinZ, a_SrcArea.MaxZ - 1);
			World:QueueTask(WriteDst);
		end
	);
end





--- Returns the gallery of the specified name in the specified world
local LastGalleryByName = nil;
function FindGalleryByName(a_GalleryName)
	-- use a cache of size 1 to improve performance for area loading
	if (
		(LastGalleryByName ~= nil) and
		(LastGalleryByName.Name == a_GalleryName)
	) then
		return LastGalleryByName;
	end

	for idx, gal in ipairs(g_Galleries) do
		if (gal.Name == a_GalleryName) then
			LastGalleryByName = gal;
			return gal;
		end
	end
	return nil;
end





function LoadAllPlayersAreas()
	cRoot:Get():ForEachWorld(
		function (a_World)
			local WorldName = a_World:GetName();
			a_World:ForEachPlayer(
				function (a_Player)
					local PlayerName = a_Player:GetName();
					SetPlayerAreas(a_Player, g_DB:LoadPlayerAreasInWorld(WorldName, PlayerName));
					SetPlayerAllowances(WorldName, PlayerName, g_DB:LoadPlayerAllowancesInWorld(WorldName, PlayerName));
				end
			);
		end
	);
end





--- Returns the gallery that intersects the specified coords, or nil if no such gallery
function FindGalleryByCoords(a_World, a_BlockX, a_BlockZ)
	for idx, gallery in ipairs(g_Galleries) do
		if (gallery.World == a_World) then
			if (
				(a_BlockX >= gallery.MinX) and
				(a_BlockX <= gallery.MaxX) and
				(a_BlockZ >= gallery.MinZ) and
				(a_BlockZ <= gallery.MaxZ)
			) then
				return gallery;
			end
		end
	end
	return nil;
end





--- Returns StartX, StartZ, EndX, EndZ for a (hypothetical) area that intersects the specified coords
-- If no area the gallery could intersect the coords, returns nothing
function GetAreaBuildableCoordsFromBlockCoords(a_Gallery, a_BlockX, a_BlockZ)
	if (
		(a_BlockX < a_Gallery.AreaMinX) or (a_BlockX >= a_Gallery.AreaMaxX) or
		(a_BlockX < a_Gallery.AreaMinX) or (a_BlockX >= a_Gallery.AreaMaxX)
	) then
		-- Not inside this gallery
		return;
	end

	local SizeX = a_Gallery.AreaSizeX;
	local SizeZ = a_Gallery.AreaSizeZ;
	local MinX = a_Gallery.AreaMinX + SizeX * math.floor((a_BlockX - a_Gallery.AreaMinX) / SizeX);
	local MinZ = a_Gallery.AreaMinZ + SizeZ * math.floor((a_BlockZ - a_Gallery.AreaMinZ) / SizeZ);
	local Edge = a_Gallery.AreaEdge
	return MinX + Edge, MinZ + Edge, MinX + SizeX - Edge - 1, MinZ + SizeZ - Edge - 1;
end





--- Returns MinX, MinZ, MaxX, MaxZ for a (hypothetical) area that intersects the specified coords
-- If no area the gallery could intersect the coords, returns nothing
function GetAreaCoordsFromBlockCoords(a_Gallery, a_BlockX, a_BlockZ)
	if (
		(a_BlockX < a_Gallery.AreaMinX) or (a_BlockX >= a_Gallery.AreaMaxX) or
		(a_BlockX < a_Gallery.AreaMinX) or (a_BlockX >= a_Gallery.AreaMaxX)
	) then
		-- Not inside this gallery
		return;
	end

	local SizeX = a_Gallery.AreaSizeX;
	local SizeZ = a_Gallery.AreaSizeZ;
	local MinX = a_Gallery.AreaMinX + SizeX * math.floor((a_BlockX - a_Gallery.AreaMinX) / SizeX);
	local MinZ = a_Gallery.AreaMinZ + SizeZ * math.floor((a_BlockZ - a_Gallery.AreaMinZ) / SizeZ);
	return MinX, MinZ, MinX + SizeX, MinZ + SizeZ;
end





--- Returns the list of all areas that the specified player owns in this world
-- The table has been preloaded from the DB on player's spawn
-- If for any reason the table doesn't exist, return an empty table
function GetPlayerAreas(a_Player)
	local res = g_PlayerAreas[a_Player:GetWorld():GetName()][a_Player:GetName()];
	if (res == nil) then
		res = {};
		g_PlayerAreas[a_Player:GetWorld():GetName()][a_Player:GetName()] = res;
	end
	return res;
end





--- Sets the player areas for the specified player in the global area table
function SetPlayerAreas(a_Player, a_Areas)
	local WorldAreas = g_PlayerAreas[a_Player:GetWorld():GetName()];
	if (WorldAreas == nil) then
		WorldAreas = {};
		g_PlayerAreas[a_Player:GetWorld():GetName()] = WorldAreas;
	end
	WorldAreas[a_Player:GetName()] = a_Areas;
end





function GetPlayerAllowances(a_WorldName, a_PlayerName)
	assert(a_WorldName ~= nil);
	assert(a_PlayerName ~= nil);

	local res = g_PlayerAllowances[a_WorldName][a_PlayerName];
	if (res == nil) then
		res = {};
		g_PlayerAllowances[a_WorldName][a_PlayerName] = res;
	end
	return res;
end





--- Replaces the area for each player that is using it, either as owned or allowance
function ReplaceAreaForAllPlayers(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID ~= nil)
	assert(a_Area.Gallery ~= nil)

	-- Replace in Ownership:
	for _, areas in pairs(g_PlayerAreas[a_Area.Gallery.WorldName] or {}) do
		for idx, area in ipairs(areas or {}) do
			if (area.ID == a_Area.ID) then
				areas[idx] = a_Area
			end
		end
		areas[a_Area.Name] = a_Area
	end

	-- Replace in Allowances:
	for _, allowances in pairs(g_PlayerAllowances[a_Area.Gallery.WorldName] or {}) do
		for idx, area in ipairs(allowances or {}) do
			if (area.ID == a_Area.ID) then
				areas[idx] = a_Area
			end
		end
		allowances[a_Area.Name] = a_Area
	end
end





--- Removes the specified area from the internal cache of player's areas
function RemovePlayerArea(a_Player, a_Area)
	-- Check params:
	assert(tolua.type(a_Player) == "cPlayer")
	assert(type(a_Area) == "table")
	assert(a_Area.ID ~= nil)

	-- Remove the area from the Ownership cache:
	local PlayerAreas = GetPlayerAreas(a_Player);
	for idx, area in ipairs(PlayerAreas) do
		if (area.ID == a_Area.ID) then
			table.remove(PlayerAreas, idx)
			break
		end
	end
	PlayerAreas[a_Area.Name] = nil

	-- Remove the area from the Allowances:
	for _, allowances in pairs(g_PlayerAllowances[a_Area.Gallery.WorldName]) do
		for idx, area in ipairs(allowances or {}) do
			if (area.ID == a_Area.ID) then
				table.remove(allowances, idx)
				break
			end
		end
		allowances[a_Area.Name] = nil
	end
end





function SetPlayerAllowances(a_WorldName, a_PlayerName, a_Allowances)
	assert(a_WorldName ~= nil);
	assert(a_PlayerName ~= nil);

	local WorldAllowances = g_PlayerAllowances[a_WorldName];
	if (WorldAllowances == nil) then
		WorldAllowances = {};
		g_PlayerAllowances[a_WorldName] = WorldAllowances;
	end
	WorldAllowances[a_PlayerName] = a_Allowances;
end





--- Returns true if the specified block lies within the area's buildable space
function IsInArea(a_Area, a_BlockX, a_BlockZ)
	return (
		(a_BlockX >= a_Area.StartX) and
		(a_BlockX <  a_Area.EndX) and
		(a_BlockZ >= a_Area.StartZ) and
		(a_BlockZ <  a_Area.EndZ)
	)
end





--- Returns true if the specified player can interact with the specified block
-- This takes into account the areas owned by the player
function CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)
	-- If the player has the admin permission, allow them:
	if (a_Player:HasPermission("gallery.admin.buildanywhere")) then
		return true;
	end

	-- If the player is outside all galleries, bail out:
	local Gallery = FindGalleryByCoords(a_Player:GetWorld(), a_BlockX, a_BlockZ);
	if (Gallery == nil) then
		-- Check the config whether building outside galleries is allowed:
		if (g_Config.AllowBuildOutsideGalleries) then
			-- Config says allow anyone:
			return true;
		end
		if (a_Player:HasPermission("gallery.admin.buildoutside")) then
			-- Player has the permission:
			return true;
		end
		return false, "Building outside galleries is forbidden. Use the " .. g_Config.CommandPrefix .. " command to interact with the galleries.";
	end

	-- If the player has the admin permission for this gallery, allow them:
	if (a_Player:HasPermission("gallery.admin.buildanywhere." .. Gallery.Name)) then
		return true;
	end

	-- Inside a gallery, retrieve the areas:
	local Area = FindPlayerAreaByCoords(a_Player, a_BlockX, a_BlockZ);
	if (Area == nil) then
		-- Not this player's area, check allowances:
		local Allowance = FindPlayerAllowanceByCoords(a_Player, a_BlockX, a_BlockZ)
		if (Allowance == nil) then
			return false, "This area is owned by someone else.";
		end
		-- Is the allowance locked?
		if (Allowance.IsLocked and not(a_Player:HasPermission("gallery.admin.overridelocked"))) then
			return false, "This area is locked"
		end
		-- Allowed via an allowance, is it within the allowed buildable space? (exclude the sidewalks):
		if not(IsInArea(Allowance, a_BlockX, a_BlockZ)) then
			return false, "This is the public sidewalk.";
		end
		return true;
	end

	-- Is the area locked?
	if (Area.IsLocked and not(a_Player:HasPermission("gallery.admin.overridelocked"))) then
		return false, "This area is locked"
	end

	-- This player's area, is it within the allowed buildable space? (exclude the sidewalks):
	if not(IsInArea(Area, a_BlockX, a_BlockZ)) then
		return false, "This is the public sidewalk.";
	end

	-- Allowed:
	return true;
end





--- Returns the player-owned area for the specified coords, or nil if no such area
function FindPlayerAreaByCoords(a_Player, a_BlockX, a_BlockZ)
	-- Check params:
	assert(tolua.type(a_Player) == "cPlayer", "a_Player is not a cPlayer instance")
	a_BlockX = tonumber(a_BlockX)
	a_BlockZ = tonumber(a_BlockZ)
	assert(a_BlockX ~= nil, "a_BlockX is not a number")
	assert(a_BlockZ ~= nil, "a_BlockZ is not a number")

	-- Search for the area:
	for idx, area in ipairs(GetPlayerAreas(a_Player)) do
		if (
			(a_BlockX >= area.MinX) and (a_BlockX < area.MaxX) and
			(a_BlockZ >= area.MinZ) and (a_BlockZ < area.MaxZ)
		) then
			return area;
		end
	end

	-- No area found:
	return nil;
end





--- Returns the player-allowed area for the specified coords, or nil if no such area
function FindPlayerAllowanceByCoords(a_Player, a_BlockX, a_BlockZ)
	local Allowances = GetPlayerAllowances(a_Player:GetWorld():GetName(), a_Player:GetName());
	for idx, area in ipairs(Allowances) do
		if (
			(a_BlockX >= area.MinX) and (a_BlockX < area.MaxX) and
			(a_BlockZ >= area.MinZ) and (a_BlockZ < area.MaxZ)
		) then
			return area;
		end
	end
	return nil;
end




