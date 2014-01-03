
-- CmdHandlers.lua

-- Implements the handling of in-game commands available to players





--- Returns a human-readable description of an area, used for area listings
function DescribeArea(a_Area)
	return a_Area.Name .. "   (" .. a_Area.Gallery.Name .. " " .. a_Area.GalleryIndex .. ")";
end





local function SendAreaDetails(a_Player, a_Area, a_LeadingText)
	assert(a_Player ~= nil);
	assert(a_Area ~= nil);
	assert(a_LeadingText ~= nil);
	
	a_Player:SendMessage(a_LeadingText .. DescribeArea(a_Area) .. ":");
	a_Player:SendMessage("  Boundaries: {" .. a_Area.MinX .. ", " .. a_Area.MinZ .. "} - {" .. tostring(a_Area.MaxX - 1) .. ", " .. tostring(a_Area.MaxZ - 1) .. "}");
	a_Player:SendMessage("  Buildable region: {" .. a_Area.StartX .. ", " .. a_Area.StartZ .. "} - {" .. tostring(a_Area.EndX - 1) .. ", " .. tostring(a_Area.EndZ - 1) .. "}");
	a_Player:SendMessage("  Unbuildable edge: " .. tostring(a_Area.StartX - a_Area.MinX) .. " blocks");
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
		a_Player:SendMessage("  " .. DescribeArea(area));
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
		a_Player:SendMessage("  " .. DescribeArea(area));
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
		a_Player:SendMessage("  " .. DescribeArea(area));
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





function HandleCmdClaim(a_Split, a_Player)
	if (#a_Split < 3) then
		a_Player:SendMessage("You need to specify the gallery where to claim.");
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " claim <Gallery>");
		return true;
	end
	
	-- Find the gallery specified:
	local Gallery = FindGalleryByName(a_Split[3]);
	if (Gallery == nil) then
		a_Player:SendMessage("There's no gallery " .. a_Split[3]);
		-- Be nice, send the list of galleries to the player:
		HandleCmdList({"/gal", "list"}, a_Player);
		return true;
	end
	if (Gallery.WorldName ~= a_Player:GetWorld():GetName()) then
		a_Player:SendMessage("That gallery is in world " .. Gallery.WorldName .. ", you need to go to that world before claiming.");
		return true;
	end
	
	-- Claim an area:
	local Area, ErrMsg = ClaimArea(a_Player, Gallery);
	if (Area == nil) then
		a_Player:SendMessage("Cannot claim area in gallery " .. Gallery.Name .. ": " .. ErrMsg);
		return true;
	end
	
	-- Fill the area with the schematic, if available:
	if (Gallery.AreaTemplateSchematic ~= nil) then
		Gallery.AreaTemplateSchematic:Write   (a_Player:GetWorld(), Area.MinX, 0,               Area.MinZ);
		Gallery.AreaTemplateSchematicTop:Write(a_Player:GetWorld(), Area.MinX, Gallery.AreaTop, Area.MinZ);
	end
	
	-- Teleport to the area:
	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5);
	return true;
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





--- Handles the admin version of the goto command
local function HandleCmdGotoAdmin(a_Split, a_Player)
	-- "/gal goto @playername <areaname>"
	-- Check param count:
	if (#a_Split ~= 4) then
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " goto @playername <areaName>");
		return true;
	end
	
	-- Check permission:
	if not(a_Player:HasPermission("gallery.admin.goto")) then
		a_Player:SendMessage("You do not have the required permission to use this command");
		return true;
	end
	
	local Area = g_DB:LoadPlayerAreaByName(a_Split[3]:sub(2), a_Split[4]);
	if (Area == nil) then
		a_Player:SendMessage("They don't have such an area.");
		-- Do NOT send the area list - the player may not have sufficient rights
		return true;
	end
	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5);
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
	
	local ReqAreaName = a_Split[3];
	local Area = GetPlayerAreas(a_Player)[ReqAreaName];
	if (Area == nil) then
		a_Player:SendMessage("You don't own an area of that name.");
		return true;
	end
	
	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5);
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
		if (Msg ~= nil) then
			a_Player:SendMessage(Msg);
		end
		return true;
	end
	
	local Area = nil;
	local NewName = nil;
	if (#a_Split == 3) then
		-- "/gal name <newareaname>", allow renaming any player's area
		Area = g_DB:LoadAreaByPos(a_Player:GetWorld():GetName(), a_Player:GetPosX(), a_Player:GetPosZ());
		if (Area == nil) then
			a_Player:SendMessage("There's no area claimed here");
			return true;
		end
		NewName = a_Split[3];
	elseif (#a_Split == 4) then
		-- "/gal name <MyOldAreaName> <MyNewAreaName>", only for my areas
		Area = GetPlayerAreas(a_Player)[a_Split[3]];
		if (Area == nil) then
			a_Player:SendMessage("You don't own an area of name '" .. a_Split[3] .. "'.");
			return true;
		end
		NewName = a_Split[4];
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
	if (Msg ~= nil) then
		a_Player:SendMessage(Msg);
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
	local Area = nil;
	if (#a_Split == 3) then
		-- Rename by position:
		Area = FindPlayerAreaByCoords(a_Player, a_Player:GetPosX(), a_Player:GetPosZ());
		if (Area == nil) then
			a_Player:SendMessage(
				"You can only name your areas. Stand in your area and then issue the command again, or specify the old name (" ..
				g_Config.CommandPrefix .. " name <oldname> <newname>)"
			);
			return true;
		end
	else
		-- Rename by old name:
		Area = GetPlayerAreas(a_Player)[a_Split[3]];
		if (Area == nil) then
			a_Player:SendMessage("You don't own an area of name '" .. a_Split[3] .. "'.");
			return true;
		end
	end
	
	-- Rename:
	local IsSuccess, Msg = RenamePlayerArea(a_Player:GetName(), Area.Name, a_Split[4]);
	if (Msg ~= nil) then
		a_Player:SendMessage(Msg);
	end
	
	return true;
end





function HandleCmdInfo(a_Split, a_Player)
	local BlockX = math.floor(a_Player:GetPosX());
	local BlockZ = math.floor(a_Player:GetPosZ());

	local Area = nil;
	local LeadingLine = nil;
	if (a_Player:HasPermission("gallery.admin.info")) then
		-- Admin-level info tool, if the player has the necessary permissions, print info about anyone's area:
		Area = g_DB:LoadAreaByPos(a_Player:GetWorld():GetName(), BlockX, BlockZ);
		if (Area == nil) then
			a_Player:SendMessage("There is no claimed area here.");
			return true;
		end;
		LeadingLine = "This is " .. Area.PlayerName .. "'s area ";
	else
		-- Default infotool - print only info on own areas:
		Area = FindPlayerAreaByCoords(a_Player, BlockX, BlockZ);
		if (Area == nil) then
			a_Player:SendMessage("This isn't your area.");
			return true;
		end
		LeadingLine = "This is your area ";
	end

	assert(Area ~= nil);
	assert(LeadingLine ~= nil);
	SendAreaDetails(a_Player, Area, LeadingLine);
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
	assert(g_Subcommands ~= nil);
	local Subcommand = g_Subcommands[a_Split[3]];
	if ((Subcommand == nil) or not(a_Player:HasPermission(Subcommand.Permission))) then
		-- Not found or no permission to use that subcommand
		SendUsage(a_Player);
	end;
	
	-- Print detailed help on the subcommand:
	local CommonPrefix = ColCmd .. g_Config.CommandPrefix .. " " .. a_Split[3];
	a_Player:SendMessage(CommonPrefix .. ColText .. " - " .. Subcommand.Help);
	local Variants = {};
	for idx, variant in ipairs(Subcommand.DetailedHelp or {}) do
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





function SendUsage(a_Player, a_Message)
	if (a_Message ~= nil) then
		a_Player:SendMessage(a_Message);
	end
	local HasAnyCommands = false;
	local Commands = {};
	local Command = g_PluginInfo.Commands[g_Config.CommandPrefix];
	if (Command == nil) then
		a_Player:SendMessage("Unhandled command");
		return;
	end
	for cmd, info in pairs(Command.Subcommands) do
		if (a_Player:HasPermission(info.Permission)) then
			table.insert(Commands, "  " .. cChatColor.Green .. g_Config.CommandPrefix .. " " .. cmd .. cChatColor.White .. " - " .. info.Help);
		end
	end
	if (#Commands == 0) then
		a_Player:SendMessage("You are not allowed to use any subcommands.");
	else
		table.sort(Commands);
		for idx, cmd in ipairs(Commands) do
			a_Player:SendMessage(cmd);
		end
	end
end





