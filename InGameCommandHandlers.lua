
-- InGameCommandHandlers.lua

-- Implements the handling of in-game commands available to players





--- Returns a human-readable description of an area, used for area listings
function DescribeArea(a_Area)
	return a_Area.Name .. "   (" .. a_Area.Gallery.Name .. " " .. a_Area.GalleryIndex .. ")";
end





local function SendAreaDetails(a_Player, a_Area, a_LeadingText)
	assert(tolua.type(a_Player) == "cPlayer")
	assert(type(a_Area) == "table")
	assert(type(a_LeadingText) == "string")

	a_Player:SendMessage(a_LeadingText .. DescribeArea(a_Area) .. ":")
	a_Player:SendMessage("  Boundaries: {" .. a_Area.MinX .. ", " .. a_Area.MinZ .. "} - {" .. tostring(a_Area.MaxX - 1) .. ", " .. tostring(a_Area.MaxZ - 1) .. "}")
	a_Player:SendMessage("  Buildable region: {" .. a_Area.StartX .. ", " .. a_Area.StartZ .. "} - {" .. tostring(a_Area.EndX - 1) .. ", " .. tostring(a_Area.EndZ - 1) .. "}")
	a_Player:SendMessage("  Unbuildable edge: " .. tostring(a_Area.StartX - a_Area.MinX) .. " blocks")
	if (a_Area.IsLocked) then
		a_Player:SendMessage("  The area is LOCKED.")
	end
end





--- Lists all areas that the player owns in their current world
function ListPlayerAreasInWorld(a_Player)
	local Areas = GetPlayerAreas(a_Player);

	-- Send count:
	if (#Areas == 0) then
		a_Player:SendMessage("You own no areas in this world");
	elseif (#Areas == 1) then
		a_Player:SendMessage("You own 1 area in this world:");
	else
		a_Player:SendMessage("You own " .. #Areas .. " areas in this world:");
	end

	-- Send list:
	for idx, area in ipairs(Areas) do
		a_Player:SendMessage(cCompositeChat("  " .. DescribeArea(area) .. " (", mtInfo)
			:AddRunCommandPart("goto", "/gal goto " .. area.Name, "bn")
			:AddTextPart(")")
		)
	end
end





--- Lists all areas that the player owns in the specified gallery
-- Note that the gallery may be in a different world, DB is used for the listing
function ListPlayerAreasInGallery(a_Player, a_GalleryName)
	-- Retrieve all areas in the gallery from the DB:
	local Gallery = FindGalleryByName(a_GalleryName);
	if (Gallery == nil) then
		a_Player:SendMessage("There is no gallery of that name.");
		-- TODO: As a courtesy for the player, list ALL the galleries available throughout the worlds
		return true;
	end
	local Areas = g_DB:LoadPlayerAreasInGallery(a_GalleryName, a_Player:GetName());

	-- Send count:
	if (#Areas == 0) then
		a_Player:SendMessage("You own no areas in that gallery");
	elseif (#Areas == 1) then
		a_Player:SendMessage("You own 1 area in that gallery:");
	else
		a_Player:SendMessage("You own " .. #Areas .. " areas in that gallery:");
	end

	-- Send list:
	for idx, area in ipairs(Areas) do
		a_Player:SendMessage(cCompositeChat("  " .. DescribeArea(area) .. " (", mtInfo)
			:AddRunCommandPart("goto", "/gal goto " .. area.Name, "bn")
			:AddTextPart(")")
		)
	end
end





--- Lists all the areas that a_Owner has in a_GalleryName (may be nil)
-- The list is sent to a_Player
-- "/gal my @playername [<galleryname>]" command
local function ListOtherPlayerAreas(a_Player, a_OwnerName, a_GalleryName)
	-- If GalleryName is given, check that it exists:
	if (a_GalleryName ~= nil) then
		local Gallery = FindGalleryByName(a_GalleryName);
		if (Gallery == nil) then
			a_Player:SendMessage("There is no gallery of that name.");
			-- TODO: As a courtesy for the player, list ALL the galleries available throughout the worlds
			return true;
		end
	end

	-- Retrieve all areas in the gallery from the DB:
	local Areas;
	if (a_GalleryName == nil) then
		Areas = g_DB:LoadAllPlayerAreas(a_OwnerName);
	else
		Areas = g_DB:LoadPlayerAreasInGallery(a_GalleryName, a_OwnerName);
	end

	-- Send count:
	if (#Areas == 0) then
		a_Player:SendMessage("They own no areas");
	elseif (#Areas == 1) then
		a_Player:SendMessage("They own 1 area:");
	else
		a_Player:SendMessage("They own " .. #Areas .. " areas:");
	end

	-- Send list:
	for idx, area in ipairs(Areas) do
		a_Player:SendMessage(cCompositeChat("  " .. DescribeArea(area) .. " (", mtInfo)
			:AddRunCommandPart("goto", "/gal goto @" .. a_OwnerName .. " " .. area.Name, "bn")
			:AddTextPart(")")
		)
	end
end





--- Renames an area for the specified player from the old name to the new name
-- Returns true if successful, false and reason string if not
local function RenamePlayerArea(a_PlayerName, a_AreaWorldName, a_OldAreaName, a_NewAreaName)
	assert(a_PlayerName ~= nil);
	assert(a_AreaWorldName ~= nil);
	assert(a_OldAreaName ~= nil);
	assert(a_NewAreaName ~= nil);

	-- Check the new name for invalid chars:
	local Unacceptable = a_NewAreaName:gsub("[a-zA-Z0-9%-_/*+%.]", "");  -- Erase all valid chars, all that's left is unacceptable
	if (Unacceptable ~= "") then
		return false, "The following characters are not acceptable in an area name: " .. Unacceptable;
	end

	-- Renaming to same name?
	if (a_OldAreaName == a_NewAreaName) then
		return false, "This area is already named '" .. a_NewAreaName .. "'.";
	end

	-- Check the DB for duplicate name:
	if (g_DB:IsAreaNameUsed(a_PlayerName, a_AreaWorldName, a_NewAreaName)) then
		return false, "This area name is already used, pick another one.";
	end

	-- Rename in the DB:
	g_DB:RenameArea(a_PlayerName, a_OldAreaName, a_NewAreaName);

	-- Rename in the loaded table, if it exists (player connected):
	local PlayerAreas = g_PlayerAreas[a_AreaWorldName][a_PlayerName];
	if (PlayerAreas ~= nil) then
		local Area = PlayerAreas[a_OldAreaName];
		assert(Area ~= nil);
		PlayerAreas[a_OldAreaName] = nil;
		PlayerAreas[a_NewAreaName] = Area;
		Area.Name = a_NewAreaName;
	end

	return true, "Area '" .. a_OldAreaName .. "' renamed to '" .. a_NewAreaName .. "'.";
end





function HandleCmdAllow(a_Split, a_Player)
	-- Check the params:
	if (#a_Split < 3) then
		a_Player:SendMessage(cCompositeChat("You need to specify the player whom to allow here.", mtFailure))
		a_Player:SendMessage(cCompositeChat("Usage: ", mtInfo)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " allow ", g_Config.CommandPrefix .. " allow ")
			:AddTextPart("FriendName", "2")
		)
		return true;
	end
	local FriendName = a_Split[3]

	-- Get the area to be allowed:
	local BlockX = math.floor(a_Player:GetPosX())
	local BlockZ = math.floor(a_Player:GetPosZ())
	local Area = FindPlayerAreaByCoords(a_Player, BlockX, BlockZ)
	if (Area == nil) then
		a_Player:SendMessage(cCompositeChat("You do not own this area", mtFailure))
		return true
	end

	-- Allow the player:
	local res, msg = g_DB:AllowPlayerInArea(Area, FriendName)
	if not(res) then
		a_Player:SendMessage(cCompositeChat("Cannot store allowed friend to DB: " .. (msg or "<no details>"), mtFailure))
		return true
	end

	-- Reload the allowed player's allowances:
	local WorldName = a_Player:GetWorld():GetName()
	local Allowances = GetPlayerAllowances(WorldName, FriendName)
	if (Allowances ~= nil) then
		-- Hack: we're using the actual area as the Allowance. They have compatible structure, after all
		table.insert(Allowances, Area)
	end

	a_Player:SendMessage(cCompositeChat("You have allowed " .. FriendName .. " to build in your area " .. DescribeArea(Area), mtInfo))
	return true
end





function HandleCmdClaim(a_Split, a_Player)
	if (#a_Split < 3) then
		a_Player:SendMessage(cCompositeChat("You need to specify the gallery where to claim.", mtFailure))
		a_Player:SendMessage(cCompositeChat("Usage: ", mtInfo)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " claim ", g_Config.CommandPrefix .. " claim ")
			:AddTextPart("Gallery", "2")
		)
		return true
	end

	-- Find the gallery specified:
	local Gallery = FindGalleryByName(a_Split[3])
	if (Gallery == nil) then
		a_Player:SendMessage(cCompositeChat("There's no gallery " .. a_Split[3], mtFailure))
		-- Be nice, send the list of galleries to the player:
		HandleCmdList({"/gal", "list"}, a_Player)
		return true
	end
	if (Gallery.WorldName ~= a_Player:GetWorld():GetName()) then
		a_Player:SendMessage(cCompositeChat("That gallery is in world " .. Gallery.WorldName .. ", you need to go to that world before claiming.", mtFailure))
		return true
	end

	-- Claim an area:
	local Area, ErrMsg = ClaimArea(a_Player, Gallery)
	if (Area == nil) then
		a_Player:SendMessage(cCompositeChat("Cannot claim area in gallery " .. Gallery.Name .. ": " .. ErrMsg, mtFailure))
		return true
	end

	-- Fill the area with the schematic, if available:
	if (Gallery.AreaTemplateSchematic ~= nil) then
		Gallery.AreaTemplateSchematic:Write   (a_Player:GetWorld(), Area.MinX, 0,               Area.MinZ)
		if (Gallery.AreaTemplateSchematicTop) then
			Gallery.AreaTemplateSchematicTop:Write(a_Player:GetWorld(), Area.MinX, Gallery.AreaTop, Area.MinZ)
		end
	end

	-- Teleport to the area and set orientation to look at the area:
	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5)
	a_Player:SendRotation(-45, 0)
	return true
end





function HandleCmdDeny(a_Split, a_Player)
	-- Check the params:
	if (#a_Split < 3) then
		a_Player:SendMessage(cCompositeChat("You need to specify the player whom to deny here.", mtFailure))
		a_Player:SendMessage(cCompositeChat("Usage: ", mtInfo)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " deny ", g_Config.CommandPrefix .. " deny ")
			:AddTextPart("FormerFriendName", "2")
		)
		return true
	end
	local FormerFriendName = a_Split[3]

	-- Get the area to be allowed:
	local BlockX = math.floor(a_Player:GetPosX())
	local BlockZ = math.floor(a_Player:GetPosZ())
	local Area = FindPlayerAreaByCoords(a_Player, BlockX, BlockZ)
	if (Area == nil) then
		a_Player:SendMessage(cCompositeChat("You do not own this area", mtFailure))
		return true
	end

	-- Deny the player:
	local res, msg = g_DB:DenyPlayerInArea(Area, FormerFriendName)
	if not(res) then
		a_Player:SendMessage(cCompositeChat("Denying failed in the DB: " .. (msg or "<no details>"), mtFailure))
		return true
	end

	-- Reload the allowed player's allowances:
	local WorldName = a_Player:GetWorld():GetName()
	local Allowances = GetPlayerAllowances(WorldName, FormerFriendName)
	if (Allowances ~= nil) then
		local NewAllowances = {}
		for idx, allow in ipairs(Allowances) do
			if (allow ~= Area) then
				table.insert(NewAllowances, allow)
			end
		end
		SetPlayerAllowances(WorldName, FormerFriendName, NewAllowances)
	end

	a_Player:SendMessage("You have denied " .. FormerFriendName .. " to build in your area " .. DescribeArea(Area))
	return true;
end





function HandleCmdFork(a_Split, a_Player)
	-- Check params - we expect none:
	if (a_Split[3] ~= nil) then
		a_Player:SendMessage(cCompositeChat("Too many parameters", mtFailure))
		a_Player:SendMessage(cCompositeChat("Usage: ", mtInfo)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " fork", g_Config.CommandPrefix .. " fork")
		)
		return true
	end

	-- Find the area where the player is:
	local World = a_Player:GetWorld()
	local BlockX = math.floor(a_Player:GetPosX())
	local BlockZ = math.floor(a_Player:GetPosZ())
	local PlayerID = a_Player:GetUniqueID()
	local Area = g_DB:LoadAreaByPos(World:GetName(), BlockX, BlockZ)
	if (Area == nil) then
		a_Player:SendMessage(cCompositeChat("There is no area claimed here, nothing to fork.", mtFailure))
		return true
	end

	a_Player:SendMessage(cCompositeChat("Preparing the forked area, please stand by...", mtInfo))

	-- Claim a new area:
	local NewArea, ErrMsg = ClaimArea(a_Player, Area.Gallery, Area)
	if (NewArea == nil) then
		a_Player:SendMessage(ErrMsg)
		return true
	end

	-- Copy the area contents and teleport the player, once copied:
	CopyAreaContents(Area, NewArea,
		function ()
			World:DoWithEntityByID(PlayerID,
				function (a_Entity)
					if (a_Entity:GetEntityType() ~= cEntity.etPlayer) then
						LOGWARNING("Not a cPlayer anymore? Type = " .. a_Entity:GetEntityType())
						return
					end
					-- a_Entity is a cPlayer, we can use cPlayer methods to teleport them and send them new rotation:
					a_Entity:TeleportToCoords(NewArea.MinX + 0.5, NewArea.Gallery.TeleportCoordY + 0.001, NewArea.MinZ + 0.5)
					a_Entity:SendRotation(-45, 0)
					a_Entity:SendMessage(cCompositeChat("Here's your new forked area", mtInfo))
				end
			)
		end
	)

	return true
end





--- Handles the admin version of the goto command
local function HandleCmdGotoAdmin(a_Split, a_Player)
	-- "/gal goto @playername <areaname>"
	-- Check param count:
	if (#a_Split < 4) then
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " goto @playername <areaName>");
		return true;
	end
	local AreaName = table.concat(a_Split, " ", 4);

	-- Check permission:
	if not(a_Player:HasPermission("gallery.admin.goto")) then
		a_Player:SendMessage("You do not have the required permission to use this command");
		return true;
	end

	local Area = g_DB:LoadPlayerAreaByName(a_Split[3]:sub(2), AreaName);
	if (Area == nil) then
		a_Player:SendMessage("They don't have such an area.");
		-- Do NOT send the area list - the player may not have sufficient rights
		return true;
	end
	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5);
	return true;
end





function HandleCmdGoto(a_Split, a_Player)
	-- Basic parameter check:
	if (#a_Split < 3) then
		a_Player:SendMessage("Not enough parameters");
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " goto <areaName>");
		return true;
	end

	-- If the first char is a @, it is the admin override:
	if (a_Split[3]:sub(1, 1) == '@') then
		return HandleCmdGotoAdmin(a_Split, a_Player);
	end

	local ReqAreaName = table.concat(a_Split, " ", 3);  -- Support spaces in names
	local Area = GetPlayerAreas(a_Player)[ReqAreaName];
	if (Area == nil) then
		a_Player:SendMessage("You don't own an area named \"" .. ReqAreaName .. "\".");
		return true;
	end

	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5);
	return true;
end





function HandleCmdHelp(a_Split, a_Player)
	local ColCmd    = cChatColor.Green;
	local ColParams = cChatColor.Blue;
	local ColText   = cChatColor.White;

	-- For the parameter-less invocation, list all the subcommands:
	if (#a_Split == 2) then
		SendUsage(a_Player, "Listing all subcommands, use " .. ColCmd .. g_Config.CommandPrefix .. " help " .. ColParams .. "<subcommand>" .. ColText .. " for more info on a specific subcommand");
		return true;
	end

	-- Find the requested subcommand:
	local Subcommands = g_PluginInfo.Commands[a_Split[1]].Subcommands;
	assert(Subcommands ~= nil);
	local Subcommand = Subcommands[a_Split[3]];
	if ((Subcommand == nil) or not(a_Player:HasPermission(Subcommand.Permission))) then
		-- Not found or no permission to use that subcommand
		a_Player:SendMessage("Subcommand " .. a_Split[3] .. " not found.");
		SendUsage(a_Player);
		return
	end;

	-- Print detailed help on the subcommand:
	local CommonPrefix = ColCmd .. g_Config.CommandPrefix .. " " .. a_Split[3];
	a_Player:SendMessage(CommonPrefix .. ColText .. " - " .. Subcommand.HelpString);
	local Variants = {};
	for idx, variant in ipairs(Subcommand.ParameterCombinations or {}) do
		if ((variant.Permission == nil) or a_Player:HasPermission(variant.Permission)) then
			table.insert(Variants, "  " .. CommonPrefix .. " " .. ColParams .. (variant.Params or "") .. ColText .. " - " .. variant.Help);
		end
	end
	if (#Variants == 0) then
		a_Player:SendMessage("There is no specific parameter combination");
	else
		a_Player:SendMessage("The following parameter combinations are recognized:");
		for idx, txt in ipairs(Variants) do
			a_Player:SendMessage(txt);
		end
	end

	return true;
end






function HandleCmdInfo(a_Split, a_Player)
	local BlockX = math.floor(a_Player:GetPosX());
	local BlockZ = math.floor(a_Player:GetPosZ());

	local Area, LeadingLine
	if (a_Player:HasPermission("gallery.admin.info")) then
		-- Admin-level info tool, if the player has the necessary permissions, print info about anyone's area:
		Area = g_DB:LoadAreaByPos(a_Player:GetWorld():GetName(), BlockX, BlockZ);
		if not(Area) then
			a_Player:SendMessage("There is no claimed area here.")
			return true
		end;
		LeadingLine = "This is " .. Area.PlayerName .. "'s area "
	else
		-- Default infotool - print only info on own areas:
		Area = FindPlayerAreaByCoords(a_Player, BlockX, BlockZ)
		if not(Area) then
			a_Player:SendMessage("This isn't your area.")
			return true
		end
		LeadingLine = "This is your area "
	end

	assert(Area)
	assert(LeadingLine)
	SendAreaDetails(a_Player, Area, LeadingLine)
	return true
end





function HandleCmdList(a_Split, a_Player)
	local WorldName = a_Player:GetWorld():GetName();

	-- First count the galleries in this world:
	local NumGalleries = 0;
	for idx, gal in ipairs(g_Galleries) do
		if (gal.WorldName == WorldName) then
			NumGalleries = NumGalleries + 1;
		end
	end

	if (NumGalleries == 0) then
		a_Player:SendMessage("There are no galleries defined for this world.");
		return true;
	end

	-- List all the galleries in this world:
	a_Player:SendMessage("Number of galleries in this world: " .. NumGalleries);
	for idx, gal in ipairs(g_Galleries) do
		if (gal.WorldName == WorldName) then
			a_Player:SendMessage("  " .. gal.Name);
		end
	end

	return true;
end





function HandleCmdLockArea(a_Split, a_Player)
	-- Lock the area:
	local IsSuccess, ErrCode, Msg = LockAreaByCoords(a_Player:GetWorld():GetName(), a_Player:GetPosX(), a_Player:GetPosZ(), a_Player:GetName())
	if not(IsSuccess) then
		a_Player:SendMessage(Msg or ("<Unknown error while locking area (" .. (ErrCode or "<UnknownCode>") .. ">"))
		return true
	end

	-- Notify the player:
	a_Player:SendMessage("The area has been locked.")
	return true
end





function HandleCmdMy(a_Split, a_Player)
	if (#a_Split == 2) then
		-- "/gal my" command, list all areas in this world
		ListPlayerAreasInWorld(a_Player);
		return true;
	end

	if (a_Split[3]:sub(1, 1) == '@') then
		-- "/gal my @playername [<gallery>]" command, available only to admins
		if not(a_Player:HasPermission("gallery.admin.my")) then
			a_Player:SendMessage("You do not have the required permission to use this command");
			return true;
		end
		ListOtherPlayerAreas(a_Player, a_Split[3]:sub(2), a_Split[4]);
		return true;
	end

	-- "/gal my <gallery>" command, list all areas in the specified gallery
	-- Note that the gallery may be in a different world, need to list using DB Storage
	ListPlayerAreasInGallery(a_Player, a_Split[3]);
	return true;
end





local function HandleCmdNameAdmin(a_Split, a_Player)
	-- Basic params check:
	if (#a_Split < 3) then
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " name <areaName>");
		a_Player:SendMessage("areaName may contain only a-z, A-Z, 0-9, +, -, /, * and _");
		return true;
	end

	-- Is the first arg a @playername?
	if (a_Split[3]:sub(1, 1) == '@') then
		if (#a_Split ~= 5) then
			a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " name @playername <oldareaname> <newareaname>");
			return true
		end
		local IsSuccess, Msg = RenamePlayerArea(a_Split[3]:sub(2), a_Player:GetWorld():GetName(), a_Split[4], a_Split[5]);
		if not(IsSuccess) then
			a_Player:SendMessage("Failed to rename area: " .. (Msg or "<no message>"))
		end
		return true;
	end

	local Area
	local NewName
	if (#a_Split == 3) then
		-- "/gal name <newareaname>", allow renaming any player's area
		Area = g_DB:LoadAreaByPos(a_Player:GetWorld():GetName(), a_Player:GetPosX(), a_Player:GetPosZ());
		if not(Area) then
			a_Player:SendMessage("There's no area claimed here")
			return true
		end
		NewName = a_Split[3]
	elseif (#a_Split == 4) then
		-- "/gal name <MyOldAreaName> <MyNewAreaName>", only for my areas
		Area = GetPlayerAreas(a_Player)[a_Split[3]];
		if not(Area) then
			a_Player:SendMessage("You don't own an area of name '" .. a_Split[3] .. "'.")
			return true
		end
		NewName = a_Split[4]
	else
		-- Unknown syntax
		a_Player:SendMessage("Usage (pick one):");
		a_Player:SendMessage("  " .. g_Config.CommandPrefix .. " name @PlayerName <OldAreaName> <NewAreaName>");
		a_Player:SendMessage("  " .. g_Config.CommandPrefix .. " name <MyOldAreaName> <MyNewAreaName>");
		a_Player:SendMessage("  " .. g_Config.CommandPrefix .. " name <ThisAreaNewName>");
		return true;
	end

	-- Do the actual rename:
	local IsSuccess, Msg = RenamePlayerArea(Area.PlayerName, Area.Gallery.WorldName, Area.Name, NewName);
	if not(IsSuccess) then
		a_Player:SendMessage("Failed to rename area: " .. (Msg or "<no message>"))
	end
	return true;
end





function HandleCmdName(a_Split, a_Player)
	-- Check the admin-level access (can rename others' areas):
	if (a_Player:HasPermission("gallery.admin.name")) then
		return HandleCmdNameAdmin(a_Split, a_Player);
	end

	-- Basic params check:
	if (#a_Split < 3) then
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " name <areaName>");
		a_Player:SendMessage("areaName may contain only a-z, A-Z, 0-9, +, -, /, * and _");
		return true;
	end

	-- Get the area to rename:
	local Area, NewName
	if (#a_Split == 3) then
		-- Rename by position:
		Area = FindPlayerAreaByCoords(a_Player, a_Player:GetPosX(), a_Player:GetPosZ());
		if not(Area) then
			a_Player:SendMessage(
				"You can only name your areas. Stand in your area and then issue the command again, or specify the old name (" ..
				g_Config.CommandPrefix .. " name <oldname> <newname>)"
			)
			return true
		end
		NewName = a_Split[3]
	else
		-- Rename by old name:
		Area = GetPlayerAreas(a_Player)[a_Split[3]]
		if not(Area) then
			a_Player:SendMessage("You don't own an area of name '" .. a_Split[3] .. "'.")
			return true
		end
		NewName = a_Split[4]
	end

	-- Rename:
	local IsSuccess, Msg = RenamePlayerArea(a_Player:GetName(), Area.Gallery.WorldName, Area.Name, NewName);
	if not(IsSuccess) then
		a_Player:SendMessage("Failed to rename area: " .. (Msg or "<no message>"))
	end

	return true;
end





function HandleCmdRemove(a_Split, a_Player)
	-- Find the appropriate area:
	local Area = g_DB:LoadAreaByPos(a_Player:GetWorld():GetName(), a_Player:GetPosX(), a_Player:GetPosZ())
	if (Area == nil) then
		a_Player:SendMessage("There is no gallery area here")
		return true
	end

	-- Remove the area:
	g_DB:RemoveArea(Area, a_Player:GetName())
	RemovePlayerArea(a_Player, Area)

	-- Notify the player:
	a_Player:SendMessage("The area has been unclaimed.")
	return true
end





function HandleCmdReset(a_Split, a_Player)
	-- Find the appropriate Area:
	local BlockX = math.floor(a_Player:GetPosX());
	local BlockZ = math.floor(a_Player:GetPosZ());
	local Template, TemplateTop, AreaTop
	local MinX, MinZ;
	if (a_Player:HasPermission("gallery.admin.reset")) then
		-- Admin-level reset tool, if the player has the necessary permissions, reset anyone's area:
		local Gallery = FindGalleryByCoords(a_Player:GetWorld(), BlockX, BlockZ);
		if not(Gallery) then
			a_Player:SendMessage("There is no gallery here")
			return true
		end
		MinX, MinZ = GetAreaCoordsFromBlockCoords(Gallery, BlockX, BlockZ);
		Template = Gallery.AreaTemplateSchematic;
		TemplateTop = Gallery.AreaTemplateSchematicTop;
		AreaTop = Gallery.AreaTop;
	else
		-- Default reset tool - reset only own areas:
		local Area = FindPlayerAreaByCoords(a_Player, BlockX, BlockZ);
		if not(Area) then
			a_Player:SendMessage("This isn't your area.")
			return true
		end
		MinX = Area.MinX;
		MinZ = Area.MinZ;
		Template = Area.Gallery.AreaTemplateSchematic;
		TemplateTop = Area.Gallery.AreaTemplateSchematicTop;
		AreaTop = Area.Gallery.AreaTop;
	end

	assert(MinX ~= nil);
	assert(MinZ ~= nil);
	assert(AreaTop ~= nil);

	-- Check if there is a valid schematic in the gallery:
	if (Template == nil) then
		a_Player:SendMessage("Cannot reset this area, the gallery doesn't use schematic templates");
		return true;
	end

	-- Reset the area:
	Template:Write(a_Player:GetWorld(), MinX, 0, MinZ);
	if (TemplateTop) then
		TemplateTop:Write(a_Player:GetWorld(), MinX, AreaTop, MinZ);
	end
	a_Player:SendMessage("Area has been reset");
	return true;
end





function HandleCmdSelect(a_Split, a_Player)
	-- Get the Gallery:
	local World = a_Player:GetWorld()
	local BlockX = math.floor(a_Player:GetPosX())
	local BlockZ = math.floor(a_Player:GetPosZ())
	local Gallery = FindGalleryByCoords(World, BlockX, BlockZ)
	if not(Gallery) then
		a_Player:SendMessage(cCompositeChat("Cannot select, there is no gallery here.", mtFailure))
		return true
	end

	-- Get the area buildable coords:
	local StartX, StartZ, EndX, EndZ = GetAreaBuildableCoordsFromBlockCoords(Gallery, BlockX, BlockZ)
	if not(StartX) then
		a_Player:SendMessage(cCompositeChat("Cannot select, there is no gallery area here.", mtFailure))
		return true
	end

	-- Select the area in WorldEdit:
	local Cuboid = cCuboid(
		Vector3i(StartX, 0, StartZ),
		Vector3i(EndX, 255, EndZ)
	)
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_Player, Cuboid)
	if (IsSuccess == nil) then
		a_Player:SendMessage(cCompositeChat("Cannot select, WorldEdit is not installed.", mtFailure))
		return true
	elseif (IsSuccess == false) then
		a_Player:SendMessage(cCompositeChat("Cannot select, WorldEdit reported an error.", mtFailure))
		return true
	end

	-- Report success:
	a_Player:SendMessage(cCompositeChat("Selected the entire area.", mtInfo))
	return true
end





function HandleCmdStats(a_Split, a_Player)
	-- Retrieve the stats from the DB:
	local Limit = 5
	local PlayerName = a_Player:GetName()
	local PlayerAreaCounts = g_DB:GetPlayerAreaCounts(Limit, PlayerName)
	if (not(PlayerAreaCounts) or (#PlayerAreaCounts == 0)) then
		return true
	end

	-- List the top gallerists:
	local Top = #PlayerAreaCounts
	if (Top > Limit) then
		Top = Limit
	end
	a_Player:SendMessage("Top " .. Top .. " gallerists:")
	local Width = math.floor(math.log10(PlayerAreaCounts[1].NumAreas + 0.5));
	for idx, stat in ipairs(PlayerAreaCounts) do
		local Style = ""
		if (stat.PlayerName == PlayerName) then
			Style = "2"
		end
		local Prefix = "  -: "
		if (idx <= Limit) then
			Prefix = "  " .. idx .. ": "
		end
		local Padding = string.rep("0", Width - math.floor(math.log10(stat.NumAreas + 0.5)))
		local Msg = cCompositeChat()
			:AddTextPart(Prefix .. Padding .. (stat.NumAreas) .. " areas    ", Style)
			:AddSuggestCommandPart(stat.PlayerName, "/gal my @" .. stat.PlayerName, Style)
		a_Player:SendMessage(Msg)
	end
	return true
end





function HandleCmdTemplate(a_Split, a_Player)
	local Third = a_Split[3];
	local Usage =
		"Left-click and right-click on blocks to set the corners of the area to export, then use " ..
		cChatColor.Green .. g_Config.CommandPrefix .. " template export" .. cChatColor.White ..
		" command to export the selection. You can also use " .. cChatColor.Green .. g_Config.CommandPrefix ..
		" template cancel" .. cChatColor.White .. " to cancel the export and return to normal gameplay. Further hints will be provided as you go.";

	if (IsPlayerTemplating(a_Player)) then
		if (
			(Third == "export") or
			(Third == "done") or
			(Third == "yes")
		) then
			local IsSuccess, Msg = ExportTemplate(a_Player);
			a_Player:SendMessage(Msg);
			if not(IsSuccess) then
				a_Player:SendMessage(
					"Use " .. cChatColor.Green .. g_Config.CommandPrefix .. " template export" .. cChatColor.White ..
					" command to retry exporting the selection, or " .. cChatColor.Green .. g_Config.CommandPrefix ..
					" template cancel" .. cChatColor.White .. " to cancel the export and return to normal gameplay."
				);
			else
				CancelTemplating(a_Player);
				a_Player:SendMessage("You are now back in normal gameplay.");
			end
		elseif (
			(Third == "cancel") or
			(Third == "abort") or
			(Third == "no")
		) then
			CancelTemplating(a_Player);
			a_Player:SendMessage("The previous template command has been aborted. You are now playing normally.");
		else
			a_Player:SendMessage("Unrecognized parameter!");
			a_Player:SendMessage("You are currently in the templating mode. " .. Usage);
		end
	else
		if (Third == nil) then
			a_Player:SendMessage("This subcommand requires a parameter - the base file name to save to.");
			return true;
		end
		BeginTemplating(a_Player, Third .. ".schematic");
		a_Player:SendMessage("You have switched to templating mode. " .. Usage);
	end
	return true;
end





function HandleCmdUnclaim(a_Split, a_Player)
	-- Get the gallery in which the player is standing:
	local Area = FindPlayerAreaByCoords(a_Player, a_Player:GetPosX(), a_Player:GetPosZ())
	if (Area == nil) then
		a_Player:SendMessage("This isn't your area.")
		return true
	end

	-- Remove the area:
	g_DB:RemoveArea(Area, a_Player:GetName())
	RemovePlayerArea(a_Player, Area)

	-- Notify the player:
	a_Player:SendMessage("The area has been unclaimed.")
	return true
end





function HandleCmdUnlockArea(a_Split, a_Player)
	-- Lock the area:
	local IsSuccess, ErrCode, Msg = UnlockAreaByCoords(a_Player:GetWorld():GetName(), a_Player:GetPosX(), a_Player:GetPosZ(), a_Player:GetName())
	if not(IsSuccess) then
		a_Player:SendMessage(Msg or ("<Unknown error while unlocking area (" .. (ErrCode or "<UnknownCode>") .. ">"))
		return true
	end

	-- Notify the player:
	a_Player:SendMessage("The area has been unlocked.")
	return true
end





function HandleCmdVisit(a_Split, a_Player)
	-- Check the param count:
	if ((#a_Split ~= 3) and (#a_Split ~= 4)) then
		a_Player:SendMessage("Usage: " .. cChatColor.Green .. g_Config.CommandPrefix .. " visit " .. cChatColor.Blue .. "<GalleryName> [<AreaNumber>]");
		return true;
	end

	-- Get the requested gallery:
	local GalleryName = a_Split[3];
	local Gallery = FindGalleryByName(GalleryName);
	if (Gallery == nil) then
		a_Player:SendMessage("There is no gallery named \"" .. GalleryName .. "\" in this world.");
		return true;
	end

	-- Get the requested area (last claimed area in gallery if not specified):
	local AreaIndex = tonumber(a_Split[4]) or Gallery.NextAreaIdx;

	-- Teleport:
	local BlockX, _, BlockZ = AreaCoordsToBlockCoords(Gallery, AreaIndexToCoords(AreaIndex, Gallery));
	assert(BlockX ~= nil);
	assert(BlockZ ~= nil);
	a_Player:TeleportToCoords(BlockX + 0.5, Gallery.TeleportCoordY + 0.001, BlockZ + 0.5);
	a_Player:SendMessage("Welcome to " .. GalleryName .. " " .. AreaIndex .. ".");
	return true;
end





function SendUsage(a_Player, a_Message)
	if (a_Message) then
		a_Player:SendMessage(a_Message)
	end
	local Commands = {};
	local Command = g_PluginInfo.Commands[g_Config.CommandPrefix];
	if (Command == nil) then
		a_Player:SendMessage("Unhandled command");
		return;
	end
	for cmd, info in pairs(Command.Subcommands) do
		if (a_Player:HasPermission(info.Permission)) then
			table.insert(Commands, "  " .. cChatColor.Green .. g_Config.CommandPrefix .. " " .. cmd .. cChatColor.White .. " - " .. info.HelpString);
		end
	end
	if not(Commands[1]) then
		a_Player:SendMessage("You are not allowed to use any subcommands.")
	else
		table.sort(Commands)
		for idx, cmd in ipairs(Commands) do
			a_Player:SendMessage(cmd)
		end
	end
end





