
-- HookHandlers.lua

-- Implements the handlers for hooks, as needed to prevent players from interacting with areas





--- Registers all hook handlers
function InitHookHandlers()
	cPluginManager.AddHook(cPluginManager.HOOK_CHUNK_GENERATED,    OnChunkGenerated);
	cPluginManager.AddHook(cPluginManager.HOOK_CHUNK_GENERATING,   OnChunkGenerating);
	cPluginManager.AddHook(cPluginManager.HOOK_DISCONNECT,         OnDisconnect);
	cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_LEFT_CLICK,  OnPlayerLeftClick);
	cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_RIGHT_CLICK, OnPlayerRightClick);
	cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_SPAWNED,     OnPlayerSpawned);
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
	SetPlayerAreas(a_Player, g_DB:LoadPlayerAreasInWorld(a_Player:GetWorld():GetName(), a_Player:GetName()));
	return false;
end





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





function ImprintChunkWithGallery(a_MinX, a_MinZ, a_MaxX, a_MaxZ, a_ChunkDesc, a_Gallery)
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
	if (StartX <  a_Gallery.AreaMinX) then
		StartX = a_Gallery.AreaMinX
	end
	if (EndX >= a_Gallery.AreaMaxX) then
		EndX = a_Gallery.AreaMaxX
	end
	if (StartZ <  a_Gallery.AreaMinZ) then
		StartZ = a_Gallery.AreaMinZ
	end
	if (EndZ >= a_Gallery.AreaMaxZ) then
		EndZ = a_Gallery.AreaMaxZ
	end
	local FromX = StartX - a_ChunkDesc:GetChunkX() * 16;
	local ToX   = EndX   - a_ChunkDesc:GetChunkX() * 16;
	local FromZ = StartZ - a_ChunkDesc:GetChunkZ() * 16;
	local ToZ   = EndZ   - a_ChunkDesc:GetChunkZ() * 16;
	
	-- Imprint the schematic into the chunk
	local Template = a_Gallery.AreaTemplateSchematic;
	for z = FromZ, ToZ, a_Gallery.AreaSizeZ do
		for x = FromX, ToX, a_Gallery.AreaSizeX do
			a_ChunkDesc:WriteBlockArea(Template, x, 0, z);
		end
	end
	
	-- Fix the heightmap after all those changes:
	a_ChunkDesc:UpdateHeightmap();
end





function ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc)
	local MinX = a_ChunkX * 16;
	local MinZ = a_ChunkZ * 16;
	local MaxX = MinX + 16;
	local MaxZ = MinZ + 16;
	for idx, gal in ipairs(g_Galleries) do
		ImprintChunkWithGallery(MinX, MinZ, MaxX, MaxZ, a_ChunkDesc, gal);
	end
end





function OnChunkGenerated(a_World, a_ChunkX, a_ChunkZ, a_ChunkDesc)
end





function OnChunkGenerating(a_World, a_ChunkX, a_ChunkZ, a_ChunkDesc)
	if (GetGalleryForEntireChunk(a_ChunkX, a_ChunkZ) ~= nil) then
		-- The entire chunk is in a single gallery. Imprint the gallery schematic:
		a_ChunkDesc:SetUseDefaultComposition(false);
		a_ChunkDesc:SetUseDefaultHeight(false);
		a_ChunkDesc:SetUseDefaultStructures(false);
		a_ChunkDesc:SetUseDefaultFinish(false);
		ImprintChunk(a_ChunkX, a_ChunkZ, a_ChunkDesc);
		return true;
	end
	return false;
end




