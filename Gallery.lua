
-- Gallery.lua

-- Defines the main entrypoint to the Gallery plugin





--- The main list of galleries available
g_Galleries = {};

--- The per-world per-player list of owned areas. Access as "g_Areas[WorldName][PlayerEntityID]"
g_PlayerAreas = {};





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
function ClaimArea(a_Player, a_Gallery)
	local NextAreaIdx = a_Gallery.NextAreaIdx;
	if (NextAreaIdx >= a_Gallery.MaxAreaIdx) then
		return nil, "The gallery is full";
	end
	local AreaX, AreaZ = AreaIndexToCoords(NextAreaIdx, a_Gallery)

	local MinX, MaxX, MinZ, MaxZ = AreaCoordsToBlockCoords(a_Gallery, AreaX, AreaZ);
	
	-- DEBUG:
	a_Player:SendMessage("Claiming area #" .. NextAreaIdx .. " at area-coords [" .. AreaX .. ", " .. AreaZ .. "]");
	a_Player:SendMessage("  block-coords: {" .. MinX .. ", " .. MinZ .. "} - {" .. MaxX .. ", " .. MaxZ .. "}");

	local Area = {
		MinX = MinX,
		MaxX = MaxX,
		MinZ = MinZ,
		MaxZ = MaxZ,
		StartX = MinX + a_Gallery.AreaEdge,
		EndX   = MaxX - a_Gallery.AreaEdge,
		StartZ = MinZ + a_Gallery.AreaEdge,
		EndZ   = MaxZ - a_Gallery.AreaEdge,
		Gallery = a_Gallery;
		GalleryIndex = a_Gallery.NextAreaIdx;
		PlayerName = a_Player:GetName();
		Name = a_Gallery.Name .. " " .. tostring(a_Gallery.NextAreaIdx);
	};
	g_DB:AddArea(Area);
	
	a_Gallery.NextAreaIdx = NextAreaIdx + 1;
	g_DB:UpdateGallery(a_Gallery);

	-- Add this area to Player's areas:
	local PlayerAreas = GetPlayerAreas(a_Player);
	table.insert(PlayerAreas, Area);
	PlayerAreas[Area.Name] = Area;
	
	return Area;
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
			local WorldAreas = {}
			a_World:ForEachPlayer(
				function (a_Player)
					SetPlayerAreas(a_Player, g_DB:LoadPlayerAreasInWorld(a_World:GetName(), a_Player:GetName()));
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
-- TODO: Allow permission-based overrides, global for all galleries and per-gallery
function CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)
	-- If the player has the admin permission, allow them:
	if (a_Player:HasPermission("gallery.admin.buildanywhere")) then
		return true;
	end
	
	-- If the player is outside all galleries, bail out:
	local Gallery = FindGalleryByCoords(a_Player:GetWorld(), a_BlockX, a_BlockZ);
	if (Gallery == nil) then
		-- Allowed to do anything outside the galleries
		return true;
	end
	
	-- If the player has the admin permission for this gallery, allow them:
	if (a_Player:HasPermission("gallery.admin.buildanywhere." .. Gallery.Name)) then
		return true;
	end
	
	-- Inside a gallery, retrieve the areas:
	local Area = FindPlayerAreaByCoords(a_Player, a_BlockX, a_BlockZ);
	if (Area == nil) then
		-- Not this player's area, disable interaction
		return false, "This area is owned by someone else.";
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
	for idx, area in ipairs(GetPlayerAreas(a_Player)) do
		if ((a_BlockX >= area.MinX) and (a_BlockX < area.MaxX) and (a_BlockZ >= area.MinZ) and (a_BlockZ < area.MaxZ)) then
			return area;
		end
	end
	return nil;
end




