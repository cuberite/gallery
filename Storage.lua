
-- Storage.lua

-- Implements DB storage backend for the plugin





--- The DB connection that provides the player areas
g_DB = nil;





function InitStorage()
	local DBEngine = string.lower(g_Config.DatabaseEngine);
	if (DBEngine == "sqlite") then
		g_DB = SQLite_CreateStorage(g_Config.DatabaseParams);
	elseif (DBEngine == "mysql") then
		-- TODO: MySQL bindings (via LuaRocks)
	end
	
	-- If the DB failed to initialize, fall back to SQLite:
	if (g_DB == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "DB access failed to initialize, falling back to SQLite.");
		g_DB = SQLite_CreateStorage();
	end
end





