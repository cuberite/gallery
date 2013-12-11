
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
	-- TODO: This shouldn't happen, the FillStrategy should be checked in CheckGallery()
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
		Index = a_Gallery.NextAreaIdx;
		MinX = MinX,
		MaxX = MaxX,
		MinZ = MinZ,
		MaxZ = MaxZ,
		StartX = MinX + a_Gallery.AreaEdge,
		EndX   = MaxX - a_Gallery.AreaEdge,
		StartZ = MinZ + a_Gallery.AreaEdge,
		EndZ   = MaxZ - a_Gallery.AreaEdge,
		Gallery = a_Gallery;
	};
	-- TODO: Store this area in the DB
	
	a_Gallery.NextAreaIdx = NextAreaIdx + 1;
	-- TODO: Update this in the storage

	-- Add this area to Player's areas:
	table.insert(g_PlayerAreas[a_Player:GetWorld():GetName()][a_Player:GetUniqueID()], Area);
	
	return Area;
end





--- Returns the gallery of the specified name in the specified world
function FindGallery(a_GalleryName, a_WorldName)
	for idx, gal in ipairs(g_Galleries) do
		if ((gal.Name == a_GalleryName) and (gal.WorldName == a_WorldName)) then
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
					WorldAreas[a_Player:GetUniqueID()] = LoadPlayerAreas(a_World:GetName(), a_Player:GetName());
				end
			);
			g_PlayerAreas[a_World:GetName()] = WorldAreas;
		end
	);
end





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





function IsInArea(a_Area, a_BlockX, a_BlockZ)
	return (
		(a_BlockX >= a_Area.StartX) and
		(a_BlockX <  a_Area.EndX) and
		(a_BlockZ >= a_Area.StartZ) and
		(a_BlockZ <  a_Area.EndZ)
	)
end





function CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)
	-- If the player is outside all galleries, bail out:
	local Gallery = FindGalleryByCoords(a_Player:GetWorld(), a_BlockX, a_BlockZ);
	if (Gallery == nil) then
		-- Allowed to do anything outside the galleries
		return true;
	end
	
	-- Inside a gallery, retrieve the areas:
	local Areas = g_PlayerAreas[a_Player:GetWorld():GetName()][a_Player:GetUniqueID()];
	if (Areas == nil) then
		-- The player is an admin who can interact with anything anywhere
		return true;
	end
	
	for idx, area in ipairs(Areas) do
		if (IsInArea(area, a_BlockX, a_BlockZ)) then
			-- This player's area, allow them
			return true;
		end
	end
	
	-- Not this player's area, disallow:
	return false;
end





function InitGalleries()
	-- Load the last used area index for each gallery:
	for idx, gallery in ipairs(g_Galleries) do
		DBExec("SELECT NextAreaIdx FROM GalleryEnd WHERE GalleryName = \"" .. gallery.Name .. "\"",
			function (UserData, NumCols, Values, Names)
				for i = 1, NumCols do
					if (Names[i] == NextAreaIdx) then
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




