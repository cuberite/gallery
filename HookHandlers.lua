
-- HookHandlers.lua

-- Implements the handlers for hooks, as needed to prevent players from interacting with areas





local function OnPlayerBrokenBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)
	-- Update the area's DateLastChanged:
	local Area = FindPlayerAreaByCoords(a_Player, a_BlockX, a_BlockZ)
	if (Area ~= nil) then
		Area.NumBrokenBlocks = Area.NumBrokenBlocks + 1
		g_DB:UpdateAreaStats(Area)
	end
	
	-- Allow other plugins to execute:
	return false
end





local function OnPlayerDestroyed(a_Player)
	-- TODO: Remove the player's areas from the global list
	--[[
	NOTE: We can't do it by simply removing the areas, we support multiple logins of the same player, so we
	need to take care of one of the multiple logins disconnecting, but the rest staying - can't just erase the
	areas.
	So for now we "leak" the areas, it shouldn't be too much anyway - a few kilobytes at most per each unique
	playername.
	--]]
	-- RemovePlayerAreas(a_Player)
	-- RemovePlayerAllowances(a_Player)
end





local function OnPlayerLeftClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace, a_Status)
	if ((a_BlockFace >= 0) and (HandleTemplatingLeftClick(a_Player, a_BlockX, a_BlockZ))) then
		return true;
	end
	
	local CanInteract, Reason = CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ);
	if (CanInteract) then
		return false;
	end
	a_Player:SendMessage("You are not allowed to dig here. " .. Reason);
	return true;
end





local function OnPlayerPlacedBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)
	-- Update the area's DateLastChanged:
	local Area = FindPlayerAreaByCoords(a_Player, a_BlockX, a_BlockZ)
	if (Area ~= nil) then
		Area.NumPlacedBlocks = Area.NumPlacedBlocks + 1
		g_DB:UpdateAreaStats(Area)
	end
	
	-- Allow other plugins to execute:
	return false
end





local function OnPlayerRightClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace, a_CursorX, a_CursorY, a_CursorZ, a_Status)
	if (a_BlockFace < 0) then
		-- This really means "use item" and no valid coords are given
		return false;
	end
	
	if (HandleTemplatingRightClick(a_Player, a_BlockX, a_BlockZ)) then
		return true;
	end
	
	local BlockX, BlockY, BlockZ = AddFaceDirection(a_BlockX, a_BlockY, a_BlockZ, a_BlockFace);
	local CanInteract, Reason = CanPlayerInteractWithBlock(a_Player, BlockX, BlockY, BlockZ);
	if (CanInteract) then
		return false;
	end
	
	if (a_Player:GetEquippedItem().m_ItemType == E_BLOCK_AIR) then
		return false
	end
	
	a_Player:SendMessage("You are not allowed to build here. " .. Reason);
	return true;
end





local function OnPlayerSpawned(a_Player)
	-- Read this player's areas for this world:
	local WorldName = a_Player:GetWorld():GetName();
	local PlayerName = a_Player:GetName();
	SetPlayerAreas(a_Player, g_DB:LoadPlayerAreasInWorld(WorldName, PlayerName));
	SetPlayerAllowances(WorldName, PlayerName, g_DB:LoadPlayerAllowancesInWorld(WorldName, PlayerName));
	return false;
end





--- Returns the gallery that covers the entire chunk's area
-- Returns nil if no such gallery
local function GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ)
	local MinX = a_ChunkX * 16;
	local MinZ = a_ChunkZ * 16;
	local MaxX = MinX + 16;
	local MaxZ = MinZ + 16;
	for idx, gal in ipairs(g_Galleries) do
		if (
			(gal.AreaMinX <= MinX) and (gal.AreaMaxX >= MaxX) and
			(gal.AreaMinZ <= MinZ) and (gal.AreaMaxZ >= MaxZ)
		) then
			return gal;
		end
	end
	return nil;
end





--- Imprints the specified chunk with the specified gallery's template, where (if) they intersect
-- If a_ClearAbove is true, the AreaTemplateSchematicTop is applied, too
local function ImprintChunkWithGallery(a_MinX, a_MinZ, a_MaxX, a_MaxZ, a_ChunkDesc, a_Gallery, a_ClearAbove)
	if (a_Gallery.AreaTemplateSchematic == nil) then
		-- This gallery doesn't have a template
		return;
	end
	if (
		(a_Gallery.AreaMaxX < a_MinX) or (a_Gallery.AreaMinX > a_MaxX) or
		(a_Gallery.AreaMaxZ < a_MinZ) or (a_Gallery.AreaMinZ > a_MaxZ)
	) then
		-- This gallery doesn't intersect the chunk
		return;
	end
	
	-- Calc the bounds of the areas that should be present in this chunk:
	local SizeX = a_Gallery.AreaSizeX;
	local SizeZ = a_Gallery.AreaSizeZ;
	local StartX = a_Gallery.AreaMinX + SizeX * math.floor((a_MinX - a_Gallery.AreaMinX) / SizeX);
	local EndX   = a_Gallery.AreaMinX + SizeX * math.ceil ((a_MaxX - a_Gallery.AreaMinX) / SizeX);
	local StartZ = a_Gallery.AreaMinZ + SizeZ * math.floor((a_MinZ - a_Gallery.AreaMinZ) / SizeZ);
	local EndZ   = a_Gallery.AreaMinZ + SizeZ * math.ceil ((a_MaxZ - a_Gallery.AreaMinZ) / SizeZ);
	if (StartX < a_Gallery.AreaMinX) then
		StartX = a_Gallery.AreaMinX
	end
	if (EndX > a_Gallery.AreaMaxX) then
		EndX = a_Gallery.AreaMaxX
	end
	if (StartZ < a_Gallery.AreaMinZ) then
		StartZ = a_Gallery.AreaMinZ
	end
	if (EndZ > a_Gallery.AreaMaxZ) then
		EndZ = a_Gallery.AreaMaxZ
	end
	local FromX = StartX - a_ChunkDesc:GetChunkX() * 16;
	local ToX   = EndX   - a_ChunkDesc:GetChunkX() * 16 - 1;
	local FromZ = StartZ - a_ChunkDesc:GetChunkZ() * 16;
	local ToZ   = EndZ   - a_ChunkDesc:GetChunkZ() * 16 - 1;
	
	-- Imprint the schematic into the chunk
	local Template = a_Gallery.AreaTemplateSchematic;
	local TemplateTop = a_Gallery.AreaTemplateSchematicTop;
	local Top = a_Gallery.AreaTop;
	for z = FromZ, ToZ, a_Gallery.AreaSizeZ do
		for x = FromX, ToX, a_Gallery.AreaSizeX do
			a_ChunkDesc:WriteBlockArea(Template, x, 0, z);
			if (a_ClearAbove) then
				a_ChunkDesc:WriteBlockArea(TemplateTop, x, Top, z);
			end
		end
	end

	-- Imprint the biome into the portion of the chunk covered by the gallery
	local Biome = a_Gallery.Biome;
	if (Biome ~= nil) then
		local BlockX = a_ChunkDesc:GetChunkX() * 16;
		local BlockZ = a_ChunkDesc:GetChunkZ() * 16;
		local MinX = 0;
		if (a_Gallery.AreaMinX > BlockX) then
			MinX = a_Gallery.AreaMinX - BlockX;
		end
		local MaxX = 15;
		if (a_Gallery.AreaMaxX < BlockX + 15) then
			MaxX = a_Gallery.AreaMaxX - BlockX;
		end
		local MinZ = 0;
		if (a_Gallery.AreaMinZ > BlockZ) then
			MinZ = a_Gallery.AreaMinZ - BlockZ;
		end
		local MaxZ = 15;
		if (a_Gallery.AreaMaxZ < BlockZ + 15) then
			MaxZ = a_Gallery.AreaMaxZ - BlockZ;
		end
		for z = MinZ, MaxZ do for x = MinX, MaxX do
			a_ChunkDesc:SetBiome(x, z, Biome);
		end end
	end
	
	-- Fix the heightmap after all those changes:
	a_ChunkDesc:UpdateHeightmap();
end





--- Imprints the specified chunk with all the intersecting galleries' templates
-- if a_ClearAbove is true, the AreaTemplateSchematicTop is applied, too
local function ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc, a_ClearAbove)
	local MinX = a_ChunkX * 16;
	local MinZ = a_ChunkZ * 16;
	local MaxX = MinX + 16;
	local MaxZ = MinZ + 16;
	for idx, gal in ipairs(g_Galleries) do
		ImprintChunkWithGallery(MinX, MinZ, MaxX, MaxZ, a_ChunkDesc, gal, a_ClearAbove);
	end
end





local function OnChunkGenerated(a_World, a_ChunkX, a_ChunkZ, a_ChunkDesc)
	local Gallery = GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ);
	if ((Gallery ~= nil) and (Gallery.AreaTemplateSchematic ~= nil)) then
		-- The chunk has already been generated in OnChunkGenerating(), skip it
		return false;
	end
	
	-- Imprint whatever galleries intersect the chunk:
	ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc, true);
end





local function OnChunkGenerating(a_World, a_ChunkX, a_ChunkZ, a_ChunkDesc)
	local Gallery = GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ);
	if ((Gallery == nil) or (Gallery.AreaTemplateSchematic == nil)) then
		-- The chunks is not covered by one gallery, or the gallery doesn't use a schematic
		return false;
	end

	-- The entire chunk is in a single gallery. Imprint the gallery schematic:
	a_ChunkDesc:SetUseDefaultComposition(false);
	a_ChunkDesc:SetUseDefaultHeight(false);
	a_ChunkDesc:SetUseDefaultFinish(false);
	if (Gallery.Biome ~= nil) then
		a_ChunkDesc:SetUseDefaultBiomes(false);
		-- The biome will be set in ImprintChunk()
	end
	ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc, false);
	return true;
end





local function OnExploding(a_World, a_ExplosionSize, a_CanCauseFire, a_BlockX, a_BlockY, a_BlockZ, a_Source, a_Data)
	-- Find any gallery close enough to the explosion:
	local MinX = a_BlockX - a_ExplosionSize - 1;
	local MaxX = a_BlockX + a_ExplosionSize + 1;
	local MinZ = a_BlockZ - a_ExplosionSize - 1;
	local MaxZ = a_BlockZ + a_ExplosionSize + 1;
	for idx, gal in ipairs(g_Galleries) do
		if (
			(gal.World == a_World) and
			(MaxX >= gal.MinX) and
			(MinX <= gal.MaxX) and
			(MaxZ >= gal.MinZ) and
			(MinZ <= gal.MaxZ)
		) then
			-- Gallery found, abort the explosion:
			return true;
		end
	end
	
	-- Let it explode
	return false;
end





--- This function gets called by WorldEdit each time a player performs a WE operation
-- Return true to abort the operation, false to continue
function WorldEditCallback(a_MinX, a_MaxX, a_MinY, a_MaxY, a_MinZ, a_MaxZ, a_Player, a_World, a_Operation)
	-- If the minima and maxima aren't in the same gallery, disallow (yes, even admins canNOT use those)
	local GalMin = FindGalleryByCoords(a_World, a_MinX, a_MinZ);
	local GalMax = FindGalleryByCoords(a_World, a_MaxX, a_MaxZ);
	if (GalMin ~= GalMax) then
		a_Player:SendMessage(cChatColor.LightPurple .. "WorldEdit actions across galleries are not allowed");
		return true;
	end
	if (GalMin == nil) then
		-- Outside the galleries, check the config and permissions:
		if (g_Config.AllowWEOutsideGalleries) then
			return false;
		end
		if (a_Player:HasPermission("gallery.admin.worldeditoutside")) then
			return false;
		end
		a_Player:SendMessage(cChatColor.LightPurple .. "Cannot allow WorldEdit action, outside the galleries");
		return true;
	end
	
	-- If the minima and maxima aren't in the same area, disallow unless admin override permission
	local Area = FindPlayerAreaByCoords(a_Player, a_MinX, a_MinZ);
	if (
		(Area == nil) or
		(a_MinX <  Area.StartX) or (a_MinZ <  Area.StartZ) or  -- Min is on sidewalk
		(a_MaxX >= Area.EndX)   or (a_MaxZ >= Area.EndZ)       -- Max not in area / on sidewalk
	) then
		-- The player doesn't own this area, allow WE only with an admin permission
		if (a_Player:HasPermission("gallery.admin.worldedit")) then
			return false;
		end
		a_Player:SendMessage(cChatColor.LightPurple .. "Cannot allow WorldEdit action, you don't own the area");
		return true;
	end
	
	if (a_Player:HasPermission("gallery.worldedit")) then
		return false;
	end
	a_Player:SendMessage(cChatColor.LightPurple .. "You don't have permission to use WorldEdit here");
	return true;
end





local function OnPluginsLoaded()
	-- Add a WE hook to each world
	cRoot:Get():ForEachWorld(
		function (a_World)
			local res = cPluginManager:CallPlugin("WorldEdit", "RegisterAreaCallback", "Gallery", "WorldEditCallback", a_World:GetName());
		end
	);
end





--- Registers all hook handlers
function InitHookHandlers()
	cPluginManager:AddHook(cPluginManager.HOOK_CHUNK_GENERATED,     OnChunkGenerated)
	cPluginManager:AddHook(cPluginManager.HOOK_CHUNK_GENERATING,    OnChunkGenerating)
	cPluginManager:AddHook(cPluginManager.HOOK_EXPLODING,           OnExploding)
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_BROKEN_BLOCK, OnPlayerBrokenBlock)
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_DESTROYED,    OnPlayerDestroyed)
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_LEFT_CLICK,   OnPlayerLeftClick)
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_PLACED_BLOCK, OnPlayerPlacedBlock)
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_RIGHT_CLICK,  OnPlayerRightClick)
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_SPAWNED,      OnPlayerSpawned)
	cPluginManager:AddHook(cPluginManager.HOOK_PLUGINS_LOADED,      OnPluginsLoaded)
end




