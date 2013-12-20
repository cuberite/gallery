
-- CmdHandlers.lua

-- Implements the handling of in-game commands available to players





--- Registers all the command handlers
function InitCmdHandlers()
	-- Register the generic "gallery" command that will actually handle all the /gallery commands:
	cPluginManager.BindCommand(g_Config.CommandPrefix, "", HandleGalleryCmd, "");  -- Must not use any permission!

	-- Register the subcommands, so that they are listed in the help:
	RegisterSubcommands();
end





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





local function HandleCmdList(a_Split, a_Player)
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





local function HandleCmdClaim(a_Split, a_Player)
	if (#a_Split < 3) then
		a_Player:SendMessage("You need to specify the gallery where to claim.");
		a_Player:SendMessage("Usage: " .. g_Config.CmdPrefix .. " claim <Gallery>");
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





local function HandleCmdMy(a_Split, a_Player)
	if (#a_Split == 2) then
		-- "/gal my" command, list all areas in this world
		ListPlayerAreasInWorld(a_Player);
		return true;
	end
	
	-- "/gal my <gallery>" command, list all areas in the specified gallery
	-- Note that the gallery may be in a different world, need to list using DB Storage
	ListPlayerAreasInGallery(a_Player, a_Split[3]);
	return true;
end





local function HandleCmdGoto(a_Split, a_Player)
	-- Basic parameter check:
	if (#a_Split < 3) then
		a_Player:SendMessage("Not enough parameters");
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " goto <areaName>");
		return true;
	end
	
	local ReqAreaName = table.concat(a_Split, " ", 3);
	local Area = GetPlayerAreas(a_Player)[ReqAreaName];
	if (Area == nil) then
		a_Player:SendMessage("You don't own an area of that name.");
		return true;
	end
	
	a_Player:TeleportToCoords(Area.MinX + 0.5, Area.Gallery.TeleportCoordY + 0.001, Area.MinZ + 0.5);
	return true;
end





local function HandleCmdName(a_Split, a_Player)
	-- Check the params:
	if (#a_Split ~= 3) then
		a_Player:SendMessage("Usage: " .. g_Config.CommandPrefix .. " name <areaName>");
		a_Player:SendMessage("areaName may contain only a-z, A-Z, 0-9, +, -, /, * and _");
		return true;
	end
	local NewName = a_Split[3];
	local Unacceptable = NewName:gsub("[a-zA-Z0-9%-_/*+%.]", "");  -- Erase all valid chars, all that's left is unacceptable
	if (Unacceptable ~= "") then
		a_Player:SendMessage("The following characters are not acceptable in an area name: " .. Unacceptable);
		return true;
	end
	
	-- Check what the current area is:
	local Area = FindPlayerAreaByCoords(a_Player, a_Player:GetPosX(), a_Player:GetPosZ());
	if (Area == nil) then
		a_Player:SendMessage("You can only name your areas. Stand in your area and then issue the command again");
		return true;
	end
	
	-- Renaming to same name?
	if (Area.Name == NewName) then
		a_Player:SendMessage("This area is already named '" .. NewName .. "'.");
		return true;
	end
	
	-- Check the DB for duplicate name:
	local OldName = Area.Name;
	if (g_DB:IsAreaNameUsed(a_Player:GetName(), a_Player:GetWorld():GetName(), NewName)) then
		a_Player:SendMessage("This area name is already used, pick another one.");
		return true;
	end
	
	-- Rename in the DB:
	g_DB:NameArea(Area, NewName);
	
	-- Rename in the loaded table:
	local PlayerAreas = GetPlayerAreas(a_Player);
	PlayerAreas[OldName] = nil;
	PlayerAreas[NewName] = Area;
	Area.Name = NewName;
	
	a_Player:SendMessage("Area '" .. OldName .. "' renamed to '" .. NewName .. "'.");
	return true;
end





local function HandleCmdInfo(a_Split, a_Player)
	-- TODO: Admin-level info tool, if the player has the necessary permissions
	
	local BlockX = math.floor(a_Player:GetPosX());
	local BlockZ = math.floor(a_Player:GetPosZ());
	local Area = FindPlayerAreaByCoords(a_Player, BlockX, BlockZ);
	if (Area == nil) then
		a_Player:SendMessage("This isn't your area.");
		return true;
	else
		SendAreaDetails(a_Player, Area, "This is your area ");
	end
	return true;
end





--- The list of subcommands, their handler functions and metadata:
local g_Subcommands =
{
	list =
	{
		Help = "lists all available galleries",
		Permission = "gallery.list",
		Handler = HandleCmdList,
	},
	claim =
	{
		Params = "<gallery>",
		Help = "claims a new area in the <gallery>",
		Permission = "gallery.claim",
		Handler = HandleCmdClaim,
	},
	my =
	{
		Params = "[<gallery>]",
		Help = "lists all your areas [in the <gallery>]",
		Permission = "gallery.my",
		Handler = HandleCmdMy,
	},
	goto =
	{
		Params = "<gallery> <areaID>",
		Help = "teleports you to specified gallery area",
		Permission = "gallery.goto",
		Handler = HandleCmdGoto,
	},
	name = 
	{
		Params = "<newName>",
		Help = "renames the area you're currently standing at",
		Permission = "gallery.name",
		Handler = HandleCmdName,
	},
	info =
	{
		Help = "prints information on the area you're currently standing at",
		Permission = "gallery.info",
		Handler = HandleCmdInfo,
	},
} ;





function SendUsage(a_Player, a_Message)
	if (a_Message ~= nil) then
		a_Player:SendMessage(a_Message);
	end
	for cmd, info in pairs(g_Subcommands) do
		a_Player:SendMessage("  " .. g_Config.CommandPrefix .. " " .. cmd .. " " .. (info.Params or "") .. " - " .. info.Help);
	end
end





function HandleGalleryCmd(a_Split, a_Player)
	-- Verify that a subcommand has been given:
	if (#a_Split <= 1) then
		SendUsage(a_Player, "The " .. g_Config.CommandPrefix .. " command requires an additional verb:");
		return true;
	end
	
	-- Find the subcommand:
	local Subcommand = g_Subcommands[a_Split[2]];
	if (Subcommand == nil) then
		SendUsage(a_Player, "Unknown verb: " .. a_Split[2]);
		return true;
	end
	
	-- Check the permission:
	if not(a_Player:HasPermission(Subcommand.Permission)) then
		a_Player:SendMessage("You don't have permission to use this command");
		return true;
	end
	
	-- Execute the handler:
	return Subcommand.Handler(a_Split, a_Player);
end





function RegisterSubcommands()
	local CP = g_Config.CommandPrefix;
	for cmd, info in pairs(g_Subcommands) do
		local FullCmd = CP .. " " .. cmd;
		if ((info.Params ~= nil) and (info.Params ~= "")) then
			FullCmd = FullCmd .. " " .. info.Params;
		end
		local HelpString = " - " .. info.Help;
		cPluginManager.BindCommand(FullCmd, info.Permission, HandleGalleryCmd, HelpString);
	end
end





