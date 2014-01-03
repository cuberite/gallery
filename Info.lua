
-- Info.lua

-- Implements the g_PluginInfo standard plugin description





g_PluginInfo = 
{
	Name = "Gallery",
	Date = "2013-12-29",
	Description = [[
		This plugin allows users to automatically claim areas from a predefined "pool" of areas (galleries). Each such area
		is then protected so that only the area owner can interact with the area.
	]],
	Commands =
	{
		["/gal"] =
		{
			-- Due to having subcommands, this command does not use either Permission nor HelpString
			Permission = "",
			HelpString = "",
			Handler = nil,
			Subcommands =
			{
				list =
				{
					HelpString = "lists all available galleries",
					Permission = "gallery.list",
					Handler = HandleCmdList,
				},
				
				claim =
				{
					HelpString = "claims a new area",
					Permission = "gallery.claim",
					Handler = HandleCmdClaim,
					DetailedHelp =
					{
						{
							Params = "GalleryName",
							Help = "claims a new area in the specified gallery. The gallery must be in the current world.",
						},
					},
				},
				
				my =
				{
					HelpString = "lists all your areas",
					Permission = "gallery.my",
					Handler = HandleCmdMy,
					DetailedHelp =
					{
						{
							Params = "",
							Help = "lists all your owned areas in this world",
						},
						{
							Params = "GalleryName",
							Help = "lists all your owned areas in the specified gallery",
						},
						{
							Params = "@PlayerName",
							Help = "lists all areas owned by the player in this world.",
							Permission = "gallery.admin.my",
						},
						{
							Params = "@PlayerName GalleryName",
							Help = "lists all areas owned by the player in the specified gallery",
							Permission = "gallery.admin.my",
						},
					},
				},
				
				goto =
				{
					HelpString = "teleports you to specified gallery area",
					Permission = "gallery.goto",
					Handler = HandleCmdGoto,
					DetailedHelp =
					{
						{
							Params = "AreaName",
							Help = "teleports you to the specified area",
						},
						{
							Params = "@PlayerName AreaName",
							Help = "teleports you to the specified area owned by the player",
							Permission = "gallery.admin.goto",
						},
					},
				},
				
				name = 
				{
					HelpString = "renames the area you're currently standing at",
					Permission = "gallery.name",
					Handler = HandleCmdName,
					DetailedHelp =
					{
						{
							Params = "NewName",
							Help = "renames your area you're currently standing in",
						},
						{
							Params = "OldName NewName",
							Help = "renames your area OldName to NewName",
						},
						{
							Params = "NewName",
							Help = "renames the area you're currently standing in (regardless of ownership)",
							Permission = "gallery.admin.name",
						},
						{
							Params = "@PlayerName OldName NewName",
							Help = "renames Player's area from OldName to NewName",
							Permission = "gallery.admin.name",
						},
					},
				},
				
				info =
				{
					HelpString = "prints information on the area you're currently standing at",
					Permission = "gallery.info",
					Handler = HandleCmdInfo,
				},
				
				help =
				{
					HelpString = "prints detailed help for the subcommand",
					Permission = "gallery.help",
					Handler = HandleCmdHelp,
					DetailedHelp =  -- fun part - make "/gal help help" work as expected
					{
						{
							Params = "",
							Help = "displays list of subcommands with basic help for each",
						},
						{
							Params = "Subcommand",
							Help = "displays detailed help for the subcommand, including all the parameter combinations",
						},
					},
				},
				
				template =
				{
					HelpString = "creates new .schematic template based on your selection",
					Permission = "gallery.admin.template",
					Handler = HandleCmdTemplate,
					DetailedHelp =
					{
						{
							Params = "FileName",
							Help = "Let's you select an arbitrary square area, then saves its contents into a file, FileName.schematic",
						},
					},
				},  -- template
			},  -- Subcommands
		},  -- gal
	},  -- Commands
};  -- g_PluginInfo




