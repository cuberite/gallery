
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
	{ Name = "AreaEdge",     Type = "number" },
	{ Name = "Biome",        Type = "string" },
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
	
	-- Check the FillStrategy param:
	local AllowedStrategies = {"x+z+", "x-z+", "x+z-", "x-z-", "z+x+", "z+x-", "z-x+", "z-x-"};
	local ReqStrategy = a_Gallery.FillStrategy;
	local IsStrategyValid = false;
	for idx, strategy in ipairs(AllowedStrategies) do
		if (ReqStrategy == strategy) then
			IsStrategyValid = true;
		end
	end
	if not(IsStrategyValid) then
		LOGWARNING(PLUGIN_PREFIX .. "Gallery \"" .. a_Gallery.Name .. "\"'s FillStrategy is not recognized. The gallery is disabled.");
		return false;
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
		if (a_Gallery.AreaTop < 255) then
			a_Gallery.AreaTemplateSchematicTop:Create(a_Gallery.AreaSizeX, 255 - a_Gallery.AreaTop, a_Gallery.AreaSizeZ);
		else
			a_Gallery.AreaTemplateSchematicTop:Create(a_Gallery.AreaSizeX, 0, a_Gallery.AreaSizeZ);
		end
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
	
	-- Set the gallery's minimum and maximum area coords
	-- (that is, minima and maxima rounded to the area coords)
	if (a_Gallery.FillStrategy:find("x%+")) then
		-- "x+" direction, the areas are calculated from the MinX side of the gallery
		a_Gallery.AreaMinX = a_Gallery.MinX;
		a_Gallery.AreaMaxX = a_Gallery.MinX + a_Gallery.AreaSizeX * a_Gallery.NumAreasPerX;
	else
		-- "x-" direction, the areas are calculated from the MaxX side of the gallery
		a_Gallery.AreaMinX = a_Gallery.MaxX - a_Gallery.AreaSizeX * a_Gallery.NumAreasPerX;
		a_Gallery.AreaMaxX = a_Gallery.MaxX;
	end
	if (a_Gallery.FillStrategy:find("z%+")) then
		-- "z+" direction, the areas are calculated from the MinZ side of the gallery
		a_Gallery.AreaMinZ = a_Gallery.MinZ;
		a_Gallery.AreaMaxZ = a_Gallery.MinZ + a_Gallery.AreaSizeZ * a_Gallery.NumAreasPerZ;
	else
		-- "z-" direction, the areas are calculated from the MaxZ side of the gallery
		a_Gallery.AreaMinZ = a_Gallery.MaxZ - a_Gallery.AreaSizeZ * a_Gallery.NumAreasPerZ;
		a_Gallery.AreaMaxZ = a_Gallery.MaxZ;
	end
	
	-- Look up biome, if set, and convert to EMCSBiome enum:
	if (a_Gallery.Biome ~= nil) then
		local BiomeType = StringToBiome(a_Gallery.Biome);
		if (BiomeType == biInvalidBiome) then
			LOGWARNING(PLUGIN_PREFIX .. "Gallery " .. a_Gallery.Name .. " has invalid Biome \"" .. a_Gallery.Biome .. "\"; biome support turned off.");
			a_Gallery.Biome = nil;
		else
			a_Gallery.Biome = BiomeType;
		end
	end

	-- All okay
	return true;
end





--- Verifies that each gallery has all the minimum settings it needs
-- Returns an array+map of the accepted galleries
local function VerifyGalleries(a_Galleries)
	-- Filter out galleries that are not okay:
	local GalleriesOK = {}
	for idx, gallery in ipairs(a_Galleries) do
		if (CheckGallery(gallery, idx)) then
			GalleriesOK[gallery.Name] = gallery
			table.insert(GalleriesOK, gallery)
		end
	end
	return GalleriesOK
end





--- Checks if g_Config has all the keys it needs, adds defaults for the missing ones
-- Returns the corrected configuration (but changes the one in the parameter as well)
local function VerifyConfig(a_Config)
	a_Config.CommandPrefix = a_Config.CommandPrefix or "/gallery"
	a_Config.DatabaseEngine = a_Config.DatabaseEngine or "sqlite"
	a_Config.DatabaseParams = a_Config.DatabaseParams or {}
	
	-- Check the WebPreview, if it doesn't have all the requirements, set it to nil to disable previewing:
	if (a_Config.WebPreview) then
		if not(a_Config.WebPreview.ThumbnailFolder) then
			LOGINFO(PLUGIN_PREFIX .. "Gallery: The config doesn't define WebPreview.ThumbnailFolder. Web preview is disabled.")
			a_Config.WebPreview = nil
		end
		if (a_Config.WebPreview and not(a_Config.WebPreview.MCSchematicToPng)) then
			LOGINFO(PLUGIN_PREFIX .. "Gallery: The config doesn't define WebPreview.MCSchematicToPng. Web preview is disabled.")
			a_Config.WebPreview = nil
		end
		if (a_Config.WebPreview and not(cFile:Exists(a_Config.WebPreview.MCSchematicToPng))) then
			LOGINFO(PLUGIN_PREFIX .. "Gallery: The WebPreview.MCSchematicToPng in the config is not valid. Web preview is disabled.")
			a_Config.WebPreview = nil
		end
	end

	-- Apply the CommandPrefix - change the actual g_PluginInfo table:
	a_Config.CommandPrefix = a_Config.CommandPrefix or "/gallery"
	if (a_Config.CommandPrefix ~= "/gallery") then
		g_PluginInfo.Commands[a_Config.CommandPrefix] = g_PluginInfo.Commands["/gallery"]
		g_PluginInfo.Commands["/gallery"] = nil
	end
	
	return a_Config
end





--- Loads the galleries from the config file CONFIG_FILE
function LoadConfig()
	if not(cFile:Exists(CONFIG_FILE)) then
		-- No file to read from, bail out with a log message
		-- But first copy our example file to the folder, to let the admin know the format:
		local PluginFolder = cPluginManager:Get():GetCurrentPlugin():GetLocalFolder()
		local ExampleFile = CONFIG_FILE:gsub(".cfg", ".example.cfg");
		cFile:Copy(PluginFolder .. "/example.cfg", ExampleFile);
		LOGWARNING(PLUGIN_PREFIX .. "The config file '" .. CONFIG_FILE .. "' doesn't exist. An example configuration file '" .. ExampleFile .. "' has been created for you.");
		LOGWARNING(PLUGIN_PREFIX .. "No galleries were loaded");
		g_Config = VerifyConfig({})
		g_Galleries = VerifyGalleries({})
		return;
	end
	
	-- Load and compile the config file:
	local cfg, err = loadfile(CONFIG_FILE);
	if (cfg == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open '" .. CONFIG_FILE .. "': " .. err);
		LOGWARNING(PLUGIN_PREFIX .. "No galleries were loaded");
		g_Config = VerifyConfig({})
		g_Galleries = VerifyGalleries({})
		return;
	end
	
	-- Execute the loaded file in a sandbox:
	-- This is Lua-5.1-specific and won't work in Lua 5.2!
	local Sandbox = {};
	setfenv(cfg, Sandbox);
	cfg();
	
	-- Retrieve the values we want from the sandbox:
	local Galleries, Config = Sandbox.Galleries, Sandbox.Config;
	if (Galleries == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Galleries not found in the config file '" .. CONFIG_FILE .. "'. Gallery plugin inactive.");
		Galleries = {};
	end
	if (Config == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Config not found in the config file '" .. CONFIG_FILE .. "'. Using defaults.");
		Config = {};  -- Defaults will be inserted by VerifyConfig()
	end
	g_Config = VerifyConfig(Config)
	g_Galleries = VerifyGalleries(Galleries)
end




