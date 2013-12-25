
-- HookHandlers.lua

-- Implements the handlers for hooks, as needed to prevent players from interacting with areas





--- Registers all hook handlers
function InitHookHandlers()
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





