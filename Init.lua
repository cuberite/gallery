
-- Gallery_init.lua

-- Defines the Initialize function for the Gallery plugin





function Initialize(a_Plugin)
	a_Plugin:SetVersion(1);

	-- Load the config
	LoadConfig();

	-- Verify the settings:
	VerifyGalleries();
	VerifyConfig();

	-- Initialize the DB storage:
	InitStorage();

	-- Initialize the values in galleries stored in the DB:
	InitGalleries();

	-- Load per-player list of areas for all currently connected players:
	LoadAllPlayersAreas();

	-- Initialize in-game commands:
	InitCmdHandlers();
	
	-- Hook to the player interaction events so that we can disable them:
	InitHookHandlers();

	return true;
end





