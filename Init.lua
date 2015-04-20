
-- Gallery_init.lua

-- Defines the Initialize function for the Gallery plugin





function Initialize(a_Plugin)
	-- Load the InfoReg library file for registering the Info.lua command table:
	dofile(cPluginManager:GetPluginsPath() .. "/InfoReg.lua")
	
	-- Load the config
	LoadConfig()

	-- Initialize the DB storage:
	InitStorage()

	-- Initialize the values in galleries stored in the DB:
	g_DB:LoadGalleries()

	-- Load per-player list of areas for all currently connected players:
	LoadAllPlayersAreas()

	-- Register commands:
	RegisterPluginInfoCommands()
	RegisterPluginInfoConsoleCommands()
	
	-- Hook to the player interaction events so that we can disable them:
	InitHookHandlers()

	return true;
end





