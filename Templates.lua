
-- Templates.lua

-- Implements the various bits needed for templating ("/gal template" command) to work





local g_Templates = {};





--- Returns the relative Y-coord of the highest non-air block in the area
function GetAreaHeight(a_Area)
	local SizeZ = a_Area:GetSizeZ();
	local SizeX = a_Area:GetSizeX();
	local AirBlock = E_BLOCK_AIR;
	for y = a_Area:GetSizeY() - 1, 0, -1 do
		for z = 0, SizeZ - 1 do
			for x = 0, SizeX - 1 do
				if (a_Area:GetRelBlockType(x, y, z) ~= AirBlock) then
					return y;
				end
			end
		end
	end
	return 0;
end





--- Sends the current templating status, along with hints about what to do next, to the player
function SendTemplatingStatus(a_Player)
	assert(a_Player ~= nil);
	assert(IsPlayerTemplating(a_Player));
	
	local PlayerTemplate = g_Templates[a_Player:GetWorld():GetName()][a_Player:GetUniqueID()];
	local msg = "You are templating with the export file set to '" .. PlayerTemplate.FileName .. "'. Left-click on a block to (re)set the first corner. Right-click on a block to (re)set the second corner. ";
	local HasBothPoints = true;
	if ((PlayerTemplate.FirstPoint ~= nil) and (PlayerTemplate.SecondPoint ~= nil)) then
		local DiffX = math.abs(PlayerTemplate.FirstPoint.x - PlayerTemplate.SecondPoint.x);
		local DiffZ = math.abs(PlayerTemplate.FirstPoint.z - PlayerTemplate.SecondPoint.z);
		msg =
			"The current template is set, first corner at {" .. PlayerTemplate.FirstPoint.x .. ", " ..
			PlayerTemplate.FirstPoint.z .. "}, second corner at {" .. PlayerTemplate.SecondPoint.x .. ", " ..
			PlayerTemplate.SecondPoint.z .. "}. The area size is " .. DiffX .. " x " .. DiffZ ..
			" blocks. You can now use " .. cChatColor.Green .. g_Config.CommandPrefix .. " template export" ..
			cChatColor.White .. " to export the area, or left-click or right-click to re-adjust the coordinates. ";
	end
	msg =
		msg .. "You can also use " .. cChatColor.Green .. g_Config.CommandPrefix .. " template cancel" ..
		cChatColor.White .. " to cancel templating and return to normal gameplay.";
	a_Player:SendMessage(msg);
end





--- Returns true if the player currently is in the templating mode
function IsPlayerTemplating(a_Player)
	assert(a_Player ~= nil);
	
	local WorldTemplates = g_Templates[a_Player:GetWorld():GetName()];
	return (WorldTemplates ~= nil) and (WorldTemplates[a_Player:GetUniqueID()] ~= nil);
end





--- Starts templating for the specified player
function BeginTemplating(a_Player, a_FileName)
	assert(a_Player ~= nil);
	assert(a_FileName ~= nil);
	assert(not(IsPlayerTemplating(a_Player)));
	
	local WorldName = a_Player:GetWorld():GetName();
	if (g_Templates[WorldName] == nil) then
		g_Templates[WorldName] = {};
	end
	g_Templates[WorldName][a_Player:GetUniqueID()] =
	{
		PlayerName = a_Player:GetName();
		PlayerID = a_Player:GetUniqueID();
		WorldName = WorldName;
		FileName = a_FileName;
	};
	return true;
end





--- Cancels templating for the specified player
function CancelTemplating(a_Player)
	assert(a_Player ~= nil);
	assert(IsPlayerTemplating(a_Player));
	
	g_Templates[a_Player:GetWorld():GetName()][a_Player:GetUniqueID()] = nil;
end





--- Exports the template created by the specified player.
-- Returns true if successful, false and error message if not
function ExportTemplate(a_Player)
	assert(a_Player ~= nil);
	assert(IsPlayerTemplating(a_Player));

	local PlayerTemplate = g_Templates[a_Player:GetWorld():GetName()][a_Player:GetUniqueID()];
	assert(PlayerTemplate ~= nil);
	if ((PlayerTemplate.FirstPoint == nil) or (PlayerTemplate.SecondPoint == nil)) then
		return false, "One of the corners haven't been set.";
	end
	
	-- Read the coords, sort them:
	local MinX = PlayerTemplate.FirstPoint.x;
	local MaxX = PlayerTemplate.SecondPoint.x;
	if (MinX > MaxX) then
		MinX, MaxX = MaxX, MinX;  -- swap them
	end
	local MinZ = PlayerTemplate.FirstPoint.z;
	local MaxZ = PlayerTemplate.SecondPoint.z;
	if (MinZ > MaxZ) then
		MinZ, MaxZ = MaxZ, MinZ;  -- swap them
	end
	MaxX = MaxX + 1;
	MaxZ = MaxZ + 1;

	-- Read the template from the world:
	local BlockArea = cBlockArea();
	if not(BlockArea:Read(a_Player:GetWorld(), MinX, MaxX, 0, 255, MinZ, MaxZ, cBlockArea.baTypes or cBlockArea.baMetas)) then
		return false, "Cannot read the template data.";
	end
	
	-- Crop the area up to the max height:
	local AreaHeight = GetAreaHeight(BlockArea);
	local CroppedArea = cBlockArea();
	CroppedArea:Create(MaxX - MinX, AreaHeight + 1, MaxZ - MinZ);
	CroppedArea:Merge(BlockArea, 0, 0, 0, cBlockArea.msOverwrite);
	
	-- Save to file:
	LOG("Saving to file '" .. PlayerTemplate.FileName .. "'...");
	if not(CroppedArea:SaveToSchematicFile(PlayerTemplate.FileName)) then
		return false, "Cannot save schematic";
	end
	
	return true, "Template has been exported to '" .. PlayerTemplate.FileName .. "'.";
end





--- Called when a player left-clicks
-- If the player is templating, processes the click and returns true
-- Returns false if the player is not templating and normal click handling should continue
function HandleTemplatingLeftClick(a_Player, a_BlockX, a_BlockZ)
	local WorldTemplates = g_Templates[a_Player:GetWorld():GetName()];
	if (WorldTemplates == nil) then
		-- The player is not templating (there's no templating in this world)
		-- At least initialize the g_Templates[] for the current world
		g_Templates[a_Player:GetWorld():GetName()] = {};
		return false;
	end
	
	-- If the player is not templating, return control to the normal handler:
	local PlayerTemplate = WorldTemplates[a_Player:GetUniqueID()];
	if (PlayerTemplate == nil) then
		return false;
	end
	
	-- The player is templating, (re-)set the first point:
	PlayerTemplate.FirstPoint = {x = a_BlockX, z = a_BlockZ};
	a_Player:SendMessage("First corner set to {" .. a_BlockX .. ", " .. a_BlockZ .. "}.");
	SendTemplatingStatus(a_Player);
	
	return true;
end






--- Called when a player right-clicks
-- If the player is templating, processes the click and returns true
-- Returns false if the player is not templating and normal click handling should continue
function HandleTemplatingRightClick(a_Player, a_BlockX, a_BlockZ)
	local WorldTemplates = g_Templates[a_Player:GetWorld():GetName()];
	if (WorldTemplates == nil) then
		-- The player is not templating (there's no templating in this world)
		-- At least initialize the g_Templates[] for the current world
		g_Templates[a_Player:GetWorld():GetName()] = {};
		return false;
	end
	
	-- If the player is not templating, return control to the normal handler:
	local PlayerTemplate = WorldTemplates[a_Player:GetUniqueID()];
	if (PlayerTemplate == nil) then
		return false;
	end
	
	-- The player is templating, (re-)set the second point:
	PlayerTemplate.SecondPoint = {x = a_BlockX, z = a_BlockZ};
	a_Player:SendMessage("Second corner set to {" .. a_BlockX .. ", " .. a_BlockZ .. "}.");
	SendTemplatingStatus(a_Player);
	
	return true;
end






