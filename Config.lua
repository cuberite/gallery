
-- Config.lua

-- Implements loading and verifying the configuration from the file






--- The configuration
g_Config = {};





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





local function GetSchematicHighestNonAirBlock(a_Schematic)
	for y = a_Schematic:GetSizeY() - 1, 0, -1 do
		if (a_Schematic:GetRelBlockType(0, y, 0) ~= E_BLOCK_AIR) then
			return y;
		end
	end
	return 0;
end





--- Returns true if the gallery has all the minimum settings it needs
-- a_Index is used instead of gallery name if the name is not present
-- Also loads the gallery's schematic file and calculates helper dimensions
function CheckGallery(a_Gallery, a_Index)
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
		a_Gallery.TeleportCoordY = GetSchematicHighestNonAirBlock(Schematic) + 1;
	else
		-- If no schematic is given, the area sizes must be specified:
		if ((a_Gallery.AreaSizeX == nil) or (a_Gallery.AreaSizeZ == nil)) then
			LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\" has neither AreaTemplate nor AreaSizeX / AreaSizeZ set.");
			return false;
		end
		a_Gallery.TeleportCoordY = 256;
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
function VerifyGalleries()
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
function VerifyConfig()
	g_Config.CommandPrefix = g_Config.CommandPrefix or "/gallery";
	g_Config.DatabaseEngine = g_Config.DatabaseEngine or "sqlite";
	g_Config.DatabaseParams = g_Config.DatabaseParams or {};
end





--- Loads the galleries from the config file CONFIG_FILE
function LoadConfig()
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
	local Sandbox = {};
	setfenv(cfg, Sandbox);
	cfg();
	
	-- Retrieve the values we want from the sandbox:
	g_Galleries, g_Config = Sandbox.Galleries, Sandbox.Config;
	if (g_Galleries == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Galleries not found in the config file '" .. CONFIG_FILE .. "'. Gallery plugin inactive.");
		g_Galleries = {};
	end
	if (g_Config == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Config not found in the config file '" .. CONFIG_FILE .. "'. Using defaults.");
		g_Config = {};  -- Defaults will be inserted by VerifyConfig()
	end
end




