
-- Gallery.lua

-- Defines the main entrypoint to the Gallery plugin





--- The main list of galleries available
local g_Galleries = {};

--- The configuration
local g_Config = {};

--- The per-world per-player list of owned areas. Access as "g_Areas[WorldName][PlayerEntityID]"
local g_PlayerAreas = {};

--- The DB connection that provides the player areas
local g_DB = nil;

--- The file with the player areas database:
local DATABASE_FILE = "Galleries.sqlite";

--- The file from which the galleries and the configuration is read
local CONFIG_FILE = "Galleries.cfg";

local PLUGIN_PREFIX = "Gallery: ";




-- Static data:
--- Parameters that are required for each gallery:
local g_GalleryRequiredParams =
{
	{ Name = "MinX", Type = "number", },
	{ Name = "MinZ", Type = "number", },
	{ Name = "MaxX", Type = "number", },
	{ Name = "MaxZ", Type = "number", },
	{ Name = "FillStrategy", Type = "string", },
	{ Name = "WorldName", Type = "string", }
} ;

--- Parameters that are optional for each gallery (so that the type is checked):
local g_GalleryOptionalParams =
{
	{ Name = "AreaTemplate", Type = "string" },
	{ Name = "AreaEdge", Type = "number" },
} ;





--- Returns true if the gallery has all the minimum settings it needs
-- a_Index is used instead of gallery name if the name is not present
-- Also loads the gallery's schematic file and calculates helper dimensions
local function CheckGallery(a_Gallery, a_Index)
	-- Check if the name is given:
	if (a_Gallery.Name == nil) then
		LOGWARNNIG("Gallery #" .. a_Index .. " doesn't have a Name, disabling it.");
		return false;
	end
	
	-- Check all required parameters by name and type:
	for idx, param in ipairs(g_GalleryRequiredParams) do
		local p = a_Gallery[param.Name];
		if (p == nil) then
			LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\" is missing a required parameter '" .. param.Name .."'. Disabling the gallery.");
			return false;
		end
		if (type(p) ~= param.Type) then
			LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\"'s parameter \"" .. param.Name .."\" is wrong type. Expected " .. param.Type .. ", got " .. type(p) ..". Disabling the gallery.");
			return false;
		end
	end
	
	-- Check all optional parameters' types:
	for idx, param in ipairs(g_GalleryOptionalParams) do
		local p = a_Gallery[param.Name];
		if (p ~= nil) then
			if (type(p) ~= param.Type) then
				LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\"'s parameter \"" .. param.Name .."\" is wrong type. Expected " .. param.Type .. ", got " .. type(p) ..". Disabling the gallery.");
				return false;
			end
		end
	end
	
	-- Assign the world:
	a_Gallery.World = cRoot:Get():GetWorld(a_Gallery.WorldName);
	if (a_Gallery.World == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\" specifies an unknown world '" .. a_Gallery.WorldName .. "\".");
		return false;
	end

	-- Load the schematic, if requested:
	local AreaTemplate = a_Gallery["AreaTemplate"];
	if (AreaTemplate ~= nil) then
		local Schematic = cBlockArea();
		if (Schematic == nil) then
			LOGWARNING(PLUGIN_PREFIX .. "Cannot create the template schematic representation");
			return true;
		end
		if not(Schematic:LoadFromSchematicFile(AreaTemplate)) then
			LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\"'s AreaTemplate failed to load from \"" .. AreaTemplate .. "\".");
			return false;
		end
		a_Gallery.AreaTemplateSchematic = Schematic;
		a_Gallery.AreaSizeX = Schematic:GetSizeX();
		a_Gallery.AreaSizeZ = Schematic:GetSizeZ();
		a_Gallery.AreaTop   = Schematic:GetSizeY();
		a_Gallery.AreaTemplateSchematicTop = cBlockArea();
		a_Gallery.AreaTemplateSchematicTop:Create(a_Gallery.AreaSizeX, 255 - a_Gallery.AreaTop, a_Gallery.AreaSizeZ);
	else
		-- If no schematic is given, the area sizes must be specified:
		if ((a_Gallery.AreaSizeX == nil) or (a_Gallery.AreaSizeZ == nil)) then
			LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\" has neither AreaTemplate nor AreaSizeX / AreaSizeZ set.");
			return false;
		end
	end
	
	-- Calculate and check the number of areas per X / Z dimension:
	a_Gallery.NumAreasPerX = math.floor((a_Gallery.MaxX -  a_Gallery.MinX) / a_Gallery.AreaSizeX);
	if (a_Gallery.NumAreasPerX <= 0) then
		LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\" has areas wider than will fit in the X direction:" ..
			"AreaSizeX = " .. a_Gallery.AreaSizeX .. ", GallerySizeX = " .. tostring(a_Gallery.MaxX - a_Gallery.MinX));
		return false;
	end
	a_Gallery.NumAreasPerZ = math.floor((a_Gallery.MaxZ -  a_Gallery.MinZ) / a_Gallery.AreaSizeZ);
	if (a_Gallery.NumAreasPerZ <= 0) then
		LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\" has areas wider than will fit in the Z direction:" ..
			"AreaSizeZ = " .. a_Gallery.AreaSizeZ .. ", GallerySizeZ = " .. tostring(a_Gallery.MaxZ - a_Gallery.MinZ));
		return false;
	end
	a_Gallery.MaxAreaIdx = a_Gallery.NumAreasPerX * a_Gallery.NumAreasPerZ;
	
	-- Apply defaults:
	a_Gallery.AreaEdge = a_Gallery.AreaEdge or 2;

	if (a_Gallery.AreaSizeX <= a_Gallery.AreaEdge * 2) then
		LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. " has AreaEdge greater than X size: " ..
			"AreaEdge = " .. a_Gallery.AreaEdge .. ", GallerySizeX = " .. a_Gallery.AreaSizeX .. ". Gallery is disabled");
		return false;
	end
	if (a_Gallery.AreaSizeZ <= a_Gallery.AreaEdge * 2) then
		LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. " has AreaEdge greater than Z size: " ..
			"AreaEdge = " .. a_Gallery.AreaEdge .. ", GallerySizeZ = " .. a_Gallery.AreaSizeZ .. ". Gallery is disabled");
		return false;
	end

	-- All okay
	return true;
end





--- Verifies that each gallery has all the minimum settings it needs
local function VerifyGalleries()
	-- Filter out galleries that are not okay:
	local GalleriesOK = {};
	for idx, gallery in ipairs(g_Galleries) do
		if (CheckGallery(gallery, idx)) then
			table.insert(GalleriesOK, gallery);
		end
	end
	g_Galleries = GalleriesOK;
end





--- Checks if g_Config has all the keys it needs, adds defaults for the missing ones
local function VerifyConfig()
	g_Config.CommandPrefix = g_Config.CommandPrefix or "/gallery";
end





--- Loads the galleries from the config file CONFIG_FILE
local function LoadConfig()
	if not(cFile:Exists(CONFIG_FILE)) then
		-- No file to read from, silently bail out
		-- But first copy our example file to the folder, to let the admin know the format:
		local PluginFolder = cPluginManager:Get():GetCurrentPlugin():GetLocalFolder()
		cFile:Copy(PluginFolder .. "/example.cfg", (CONFIG_FILE:gsub(".cfg", ".example.cfg")));
		return;
	end
	
	-- Load and compile the config file:
	local cfg, err = loadfile(CONFIG_FILE);
	if (cfg == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open " .. CONFIG_FILE .. ": " .. err);
		LOGWARNING(PLUGIN_PREFIX .. "No galleries were loaded");
		return;
	end
	
	-- Execute the loaded file in a sandbox:
	-- This is Lua-5.1-specific and won't work in Lua 5.2!
	local SecureEnvironment = {};
	setfenv(cfg, SecureEnvironment);
	cfg();
	
	-- Retrieve the values we want from the sandbox:
	g_Galleries, g_Config = SecureEnvironment.Galleries, SecureEnvironment.Config;
	if (g_Galleries == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Galleries not found in the config file '" .. CONFIG_FILE .. "'. Gallery plugin inactive.");
		g_Galleries = {};
	end
	if (g_Config == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Config not found in the config file '" .. CONFIG_FILE .. "'. Using defaults.");
		g_Config = {};  -- Defaults will be inserted by VerifyConfig()
	end
end





--- Converts area index to area coords in the specified gallery
local function AreaIndexToCoords(a_Index, a_Gallery)
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
local function AreaCoordsToBlockCoords(a_Gallery, a_AreaX, a_AreaZ)
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
local function ClaimArea(a_Player, a_Gallery)
	local NextAreaIdx = a_Gallery.NextAreaIdx;
	if (NextAreaIdx >= a_Gallery.MaxAreaIdx) then
		return nil, "The gallery is full";
	end
	local AreaX, AreaZ = AreaIndexToCoords(NextAreaIdx, a_Gallery)

	local MinX, MaxX, MinZ, MaxZ = AreaCoordsToBlockCoords(a_Gallery, AreaX, AreaZ);
	
	-- DEBUG:
	a_Player:SendMessage("Claiming area #" .. NextAreaIdx .. " at area-coords [" .. AreaX .. ", " .. AreaZ .. "]");
	a_Player:SendMessage("  block-coords: {" .. MinX .. ", " .. MinZ .. "} - {" .. MaxX .. ", " .. MaxZ .. "}");

	a_Gallery.NextAreaIdx = NextAreaIdx + 1;
	-- TODO: Update this in the storage

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
	};
	-- TODO: Store this area in the DB
	
	-- TODO: Add this area to Player's areas
	
	return Area;
end





--- Returns the gallery of the specified name in the specified world
local function FindGallery(a_GalleryName, a_WorldName)
	for idx, gal in ipairs(g_Galleries) do
		if ((gal.Name == a_GalleryName) and (gal.WorldName == a_WorldName)) then
			return gal;
		end
	end
	return nil;
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
	local Gallery = FindGallery(a_Split[3], a_Player:GetWorld():GetName());
	if (Gallery == nil) then
		a_Player:SendMessage("There's no gallery " .. a_Split[3]);
		-- Be nice, send the list of galleries to the player:
		HandleCmdList({"/gal", "list"}, a_Player);
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
	
	-- TODO: Teleport to the area:
	return true;
end





local function HandleCmdMy(a_Split, a_Player)
	-- TODO
	return true;
end





local function HandleCmdGoto(a_Split, a_Player)
	-- TODO
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
} ;





local function SendUsage(a_Player, a_Message)
	if (a_Message ~= nil) then
		a_Player:SendMessage(a_Message);
	end
	for cmd, info in pairs(g_Subcommands) do
		a_Player:SendMessage("  " .. g_Config.CommandPrefix .. " " .. cmd .. " " .. info.Params .. " - " .. info.Help);
	end
end





local function HandleGalleryCmd(a_Split, a_Player)
	if (#a_Split <= 1) then
		SendUsage(a_Player, "The " .. g_Config.CommandPrefix .. " command requires an additional verb:");
		return true;
	end
	
	local Subcommand = g_Subcommands[a_Split[2]];
	if (Subcommand == nil) then
		SendUsage(a_Player, "Unknown verb: " .. a_Split[2]);
		return true;
	end
	-- TODO: Check permission
	return Subcommand.Handler(a_Split, a_Player);
end





local function RegisterSubcommands()
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





--- Loads the areas for a single player in the specified world
local function LoadPlayerAreas(a_WorldName, a_PlayerName)
	if (g_DB == nil) then
		return {};
	end

	local res = {};
	local stmt = g_DB:prepare("SELECT MinX, MaxX, MinZ, MaxZ FROM Areas WHERE PlayerName = ? AND WorldName = ?");
	stmt:bind_values(a_PlayerName, a_WorldName);
	for v in stmt:rows() do
		table.insert(res, {MinX = v[1], MaxX = v[2], MinZ = v[3], MaxZ = v[4],});
	end
	stmt:finalize();
	return res;
	
	--[[
	-- DEBUG: return a dummy area to test prevention:
	return
	{
		{
			MinX = 102,
			MaxX = 115,
			MinZ = 102,
			MaxZ = 115,
		}
	};
	--]]
end




local function LoadAllPlayersAreas()
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





local function OnDisconnect(a_Player, a_Reason)
	-- TODO: Remove the player's areas from the global list
end





local function FindGalleryByCoords(a_World, a_BlockX, a_BlockZ)
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





local function IsInArea(a_Area, a_BlockX, a_BlockZ)
	return (
		(a_BlockX >= a_Area.MinX) and
		(a_BlockX <= a_Area.MaxX) and
		(a_BlockZ >= a_Area.MinZ) and
		(a_BlockZ <= a_Area.MaxZ)
	)
end





local function CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)
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





local function OnPlayerLeftClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace, a_Status)
	if (CanPlayerInteractWithBlock(a_Player, a_BlockX, a_BlockY, a_BlockZ)) then
		return false;
	end
	a_Player:SendMessage("You are not allowed to dig here");
	return true;
end




local function OnPlayerRightClick(a_Player, a_BlockX, a_BlockY, a_BlockZ, a_BlockFace, a_CursorX, a_CursorY, a_CursorZ, a_Status)
	if (a_BlockFace < 0) then
		-- This really means "use item" and no valid coords are given
		-- TODO: We want to disallow using buckets and doors etc, too (see FS #405)
		return false;
	end
	
	local BlockX, BlockY, BlockZ = AddFaceDirection(a_BlockX, a_BlockY, a_BlockZ, a_BlockFace);
	if (CanPlayerInteractWithBlock(a_Player, BlockX, BlockY, BlockZ)) then
		return false;
	end
	a_Player:SendMessage("You are not allowed to build here");
	return true;
end





function OnPlayerSpawned(a_Player)
	-- Read this player's areas for this world:
	g_PlayerAreas[a_Player:GetWorld():GetName()][a_Player:GetUniqueID()] = LoadPlayerAreas(a_Player:GetWorld():GetName(), a_Player:GetName());
	return false;
end





--- Executes a command on the g_DB object
local function DBExec(a_SQL, a_Callback, a_CallbackParam)
	local ErrCode = g_DB:exec(a_SQL, a_Callback, a_CallbackParam);
	if (ErrCode ~= sqlite3.OK) then
		LOGWARNING(PLUGIN_PREFIX .. "Error " .. ErrCode .. " (" .. self.DB:errmsg() ..
			") while processing SQL command >>" .. a_SQL .. "<<"
		);
		return false;
	end
	return true;
end





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
local function CreateDBTable(a_TableName, a_Columns)
	-- Try to create the table first
	local sql = "CREATE TABLE IF NOT EXISTS '" .. a_TableName .. "' (";
	sql = sql .. table.concat(a_Columns, ", ");
	sql = sql .. ")";
	if (not(DBExec(sql))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB Table " .. a_TableName);
		return false;
	end
	-- SQLite doesn't inform us if it created the table or not, so we have to continue anyway
	
	-- Check each column whether it exists
	-- Remove all the existing columns from a_Columns:
	local RemoveExistingColumn = function(UserData, NumCols, Values, Names)
		-- Remove the received column from a_Columns. Search for column name in the Names[] / Values[] pairs
		for i = 1, NumCols do
			if (Names[i] == "name") then
				local ColumnName = Values[i]:lower();
				-- Search the a_Columns if they have that column:
				for j = 1, #a_Columns do
					-- Cut away all column specifiers (after the first space), if any:
					local SpaceIdx = string.find(a_Columns[j], " ");
					if (SpaceIdx ~= nil) then
						SpaceIdx = SpaceIdx - 1;
					end
					local ColumnTemplate = string.lower(string.sub(a_Columns[j], 1, SpaceIdx));
					-- If it is a match, remove from a_Columns:
					if (ColumnTemplate == ColumnName) then
						table.remove(a_Columns, j);
						break;  -- for j
					end
				end  -- for j - a_Columns[]
			end
		end  -- for i - Names[] / Values[]
		return 0;
	end
	if (not(DBExec("PRAGMA table_info(" .. a_TableName .. ")", RemoveExistingColumn))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot query DB table structure");
		return false;
	end
	
	-- Create the missing columns
	-- a_Columns now contains only those columns that are missing in the DB
	if (#a_Columns > 0) then
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" is missing " .. #a_Columns .. " columns, fixing now.");
		for idx, ColumnName in ipairs(a_Columns) do
			if (not(DBExec("ALTER TABLE '" .. a_TableName .. "' ADD COLUMN " .. ColumnName))) then
				LOGWARNING(PLUGIN_PREFIX .. "Cannot add DB table \"" .. a_TableName .. "\" column \"" .. ColumnName .. "\"");
				return false;
			end
		end
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" columns fixed.");
	end
	
	return true;
end





function OpenDB()
	-- Open the DB:
	local ErrCode, ErrMsg;
	g_DB, ErrCode, ErrMsg = sqlite3.open(DATABASE_FILE);
	if (g_DB == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open database \"" .. DATABASE_FILE .. "\": " .. ErrMsg);
		error(ErrMsg);  -- Abort the plugin
	end
	
	-- Create the tables, if they don't exist yet:
	local AreasColumns =
	{
		"ID INTEGER PRIMARY KEY AUTOINCREMENT",
		"MinX", "MaxX", "MinZ", "MaxZ",
		"StartX", "EndX", "StartZ", "EndZ",
		"WorldName",
		"PlayerName",
	};
	local GalleryEndColumns =
	{
		"GalleryName",
		"NextAreaIdx",
	};
	if (
		not(CreateDBTable("Areas", AreasColumns)) or
		not(CreateDBTable("GalleryEnd", GalleryEndColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!");
		error("Cannot create DB tables!");
	end
end





local function InitGalleries()
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





-- All the initialization code should be down here, global:

-- Load the config
LoadConfig();

-- Verify the settings:
VerifyGalleries();
VerifyConfig();

-- Open the DB connection:
OpenDB();

-- Initialize the values in galleries stored in the DB:
InitGalleries();

-- Load per-player list of areas for all currently connected players:
LoadAllPlayersAreas();

-- Register the generic "gallery" command that will actually handle all the /gallery commands:
cPluginManager.BindCommand(g_Config.CommandPrefix, "gallery.*", HandleGalleryCmd, "");

-- Register the subcommands, so that they are listed in the help:
RegisterSubcommands();

-- Hook to the player interaction events so that we can disable them:
cPluginManager.AddHook(cPluginManager.HOOK_DISCONNECT,         OnDisconnect);
cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_LEFT_CLICK,  OnPlayerLeftClick);
cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_RIGHT_CLICK, OnPlayerRightClick);
cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_SPAWNED,     OnPlayerSpawned);




