
-- InfoReg.lua

-- Implements registration functions that use g_PluginInfo




--- Registers all commands specified in the g_PluginInfo.Commands
function RegisterPluginInfoCommands()
	-- A sub-function that registers all subcommands of a single command, using the command's Subcommands table
	-- The a_Prefix param already contains the space after the previous command
	local function RegisterSubcommands(a_Prefix, a_Subcommands)
		assert(a_Subcommands ~= nil);
		
		for cmd, info in pairs(a_Subcommands) do
			local CmdName = a_Prefix .. cmd;
			cPluginManager.BindCommand(cmd, info.Permission or "", info.Handler, info.HelpString or "");
			-- Recursively register any subcommands:
			if (info.Subcommands ~= nil) then
				RegisterSubcommands(a_Prefix .. cmd .. " ", info.Subcommands);
			end
		end
	end
	
	-- Loop through all commands in the plugin info, register each:
	RegisterSubcommands("/", g_PluginInfo.Commands);
end




