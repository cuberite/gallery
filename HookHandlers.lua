
-- HookHandlers.lua

-- Implements the handlers for hooks, as needed to prevent players from interacting with areas





--- Registers all hook handlers
function InitHookHandlers()
	cPluginManager:AddHook(cPluginManager.HOOK_CHUNK_GENERATED,    OnChunkGenerated);
	cPluginManager:AddHook(cPluginManager.HOOK_CHUNK_GENERATING,   OnChunkGenerating);
	cPluginManager:AddHook(cPluginManager.HOOK_DISCONNECT,         OnDisconnect);
	cPluginManager:AddHook(cPluginManager.HOOK_EXPLODING,          OnExploding);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_LEFT_CLICK,  OnPlayerLeftClick);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_RIGHT_CLICK, OnPlayerRightClick);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_SPAWNED,     OnPlayerSpawned);
end





function OnDisconnect(a_Player, a_Reason)
	-- TODO: Remove the player's areas from the global list
end






function OnPlayerLeftClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace, a_Status)
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




function OnPlayerRightClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace, a_CursorX, a_CursorY, a_CursorZ, a_Status)
	if (a_BlockFace < 0) then
		-- This really means "use item" and no valid coords are given
		return false;
	end
	
	if (HandleTemplatingRightClick(a_Player, a_BlockX, a_BlockZ)) then
		return true;
	end
	
	local BlockX, BlockY, BlockZ = AddFaceDirection(a_BlockX, a_BlockY, a_BlockZ, a_BlockFace);
	local CanInteract, Reason = CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ);
	if (CanInteract) then
		return false;
	end
	
	a_Player:SendMessage("You are not allowed to build here. " .. Reason);
	return true;
end





function OnPlayerSpawned(a_Player)
	-- Read this player's areas for this world:
	local WorldName = a_Player:GetWorld():GetName();
	local PlayerName = a_Player:GetName();
	SetPlayerAreas(a_Player, g_DB:LoadPlayerAreasInWorld(WorldName, PlayerName));
	SetPlayerAllowances(WorldName, PlayerName, g_DB:LoadPlayerAllowancesInWorld(WorldName, PlayerName));
	return false;
end





--- Returns the gallery that covers the entire chunk's area
-- Returns nil if no such gallery
function GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ)
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
function ImprintChunkWithGallery(a_MinX, a_MinZ, a_MaxX, a_MaxZ, a_ChunkDesc, a_Gallery, a_ClearAbove)
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
	
	-- Fix the heightmap after all those changes:
	a_ChunkDesc:UpdateHeightmap();
end





--- Imprints the specified chunk with all the intersecting galleries' templates
-- if a_ClearAbove is true, the AreaTemplateSchematicTop is applied, too
function ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc, a_ClearAbove)
	local MinX = a_ChunkX * 16;
	local MinZ = a_ChunkZ * 16;
	local MaxX = MinX + 16;
	local MaxZ = MinZ + 16;
	for idx, gal in ipairs(g_Galleries) do
		ImprintChunkWithGallery(MinX, MinZ, MaxX, MaxZ, a_ChunkDesc, gal, a_ClearAbove);
	end
end





function OnChunkGenerated(a_World, a_ChunkX, a_ChunkZ, a_ChunkDesc)
	local Gallery = GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ);
	if ((Gallery ~= nil) and (Gallery.AreaTemplateSchematic ~= nil)) then
		-- The chunk has already been generated in OnChunkGenerating(), skip it
		return false;
	end
	
	-- Imprint whatever galleries intersect the chunk:
	ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc, true);
end





function OnChunkGenerating(a_World, a_ChunkX, a_ChunkZ, a_ChunkDesc)
	local Gallery = GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ);
	if ((Gallery == nil) or (Gallery.AreaTemplateSchematic == nil)) then
		-- The chunks is not covered by one gallery, or the gallery doesn't use a schematic
		return false;
	end

	-- The entire chunk is in a single gallery. Imprint the gallery schematic:
	a_ChunkDesc:SetUseDefaultComposition(false);
	a_ChunkDesc:SetUseDefaultHeight(false);
	a_ChunkDesc:SetUseDefaultStructures(false);
	a_ChunkDesc:SetUseDefaultFinish(false);
	ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc, false);
	return true;
end





function OnExploding(a_World, a_ExplosionSize, a_CanCauseFire, a_BlockX, a_BlockY, a_BlockZ, a_Source, a_Data)
	local Gallery = FindGalleryByCoords(a_World, a_BlockX, a_BlockZ);
	if (Gallery ~= nil) then
		-- Abort the explosion
		LOG("Aborted explosion at {" .. a_BlockX .. ", " .. a_BlockY .. ", " .. a_BlockZ .. "} due to gallery " .. Gallery.Name);
		return true;
	end
	
	-- Let it explode
	return false;
end




