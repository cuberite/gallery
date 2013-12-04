
-- Gallery.lua

-- Defines the main entrypoint to the Gallery plugin





-- The main list of galleries available
local g_Galleries = {};

-- The configuration
local g_Config = {};

local CONFIG_FILE = "Galleries.cfg"





--- Verifies that each gallery has all the minimum settings it needs
local function VerifyGalleries()
	-- TODO
end





--- Checks if g_Config has all the keys it needs, adds defaults for the missing ones
local function VerifyConfig()
	g_Config.CommandPrefix = g_Config.CommandPrefix or "/gallery";
end





--- Loads the galleries from the config file CONFIG_FILE
local function LoadConfig()
	if not(cFile:Exists(CONFIG_FILE)) then
		-- No file to read from, silently bail out
		return;
	end
	
	-- Load and compile the config file:
	local f, err = loadfile(CONFIG_FILE);
	if (f == nil) then
		LOGWARNING("Cannot open " .. CONFIG_FILE .. ": " .. err);
		LOGWARNING("No galleries were loaded");
		return;
	end
	
	-- Sandbox the loaded file, just in case, and execute:
	local SecureEnvironment = {};
	setfenv(f, SecureEnvironment);
	f();
	
	-- Retrieve the values we want:
	g_Galleries, g_Config = SecureEnvironment.Galleries, SecureEnvironment.Config;
end





local function HandleCmdList(a_Split, a_Player)
	-- TODO
	return true;
end





local function HandleCmdClaim(a_Split, a_Player)
	-- TODO
	return true;
end





local function HandleCmdMy(a_Split, a_Player)
	-- TODO
	return true;
end





--- The list of subcommands, their handler functions and metadata:
local g_Subcommands =
{
	{
		Cmd  = "list",
		Params = "",
		Help = "lists all available galleries",
		Permission = "gallery.list",
		Handler = HandleCmdList,
	},
	{
		Cmd = "claim",
		Params = "<gallery>",
		Help = "claims a new area in the <gallery>",
		Permission = "gallery.claim",
		Handler = HandleCmdClaim,
	},
	{
		Cmd = "my",
		Params = "[<gallery>]",
		Help = "lists all your areas [in the <gallery>]",
		Permission = "gallery.my",
		Handler = HandleCmdMy,
	},
} ;





local function SendUsage(a_Player, a_Message)
	if (a_Message ~= nil) then
		a_Player:SendMessage(a_Message);
	end
	for idx, cmd in ipairs(g_Subcommands) do
		a_Player:SendMessage("  " .. g_Config.CommandPrefix .. " " .. cmd.Cmd .. " " .. cmd.Params .. " - " .. cmd.Help);
	end
end





local function HandleGalleryCmd(a_Split, a_Player)
	if (#a_Split <= 1) then
		SendUsage(a_Player, "The " .. g_Config.CommandPrefix .. " command requires an additional verb:");
		return true;
	end
	
	local Subcommand = g_Subcommands[a_Split[1]];
	if (Subcommand == nil) then
		SendUsage(a_Player, "Unknown verb: " .. a_Split[1]);
		return true;
	end
	return Subcommand.Handler(a_Split, a_Player);
end





local function RegisterSubcommands()
	local CP = g_Config.CommandPrefix;
	for idx, cmd in ipairs(g_Subcommands) do
		local FullCmd = CP .. " " .. cmd.Cmd;
		local HelpString = " - " .. cmd.Help;
		cPluginManager.BindCommand(FullCmd, cmd.Permission, HandleGalleryCmd, HelpString);
	end
end





-- All the initialization code should be here:

-- Load the config
LoadConfig();

-- Verify the settings:
VerifyGalleries();
VerifyConfig();

-- Register the generic "gallery" command that will actually handle all the /gallery commands:
cPluginManager.BindCommand(g_Config.CommandPrefix, "gallery.*", HandleGalleryCmd, "");

-- Register the subcommands, so that they are listed in the help:
RegisterSubcommands();



