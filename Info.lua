
-- Info.lua

-- Implements the g_PluginInfo standard plugin description





g_PluginInfo = 
{
	Name = "Gallery",
	Date = "2014-01-22",
	Description =
[[
This plugin allows users to automatically claim areas from a predefined "pool" of areas (galleries). Each such area
is then protected so that only the area owner can interact with the area.
]],
	
	AdditionalInfo =
	{
		{
			Title = "Setting up: galleries",
			Contents =
[[
Before the plugin can be fully used, the server admin needs to set up the galleries - define the galleries
where players are allowed to claim areas. Some other configuration options are available, too.
The configuration is read from the Galleries.cfg file located in the same folder as the MCServer executable.
If the file doesn't exist, the plugin outputs a message in the server console and stays inactive. The plugin
also creates an example configuration file named Galleries.example.cfg located next to the MCServer
executable. This file contains an example configuration with documentation on all of the used variables. You
might want to consult that file while continuing to read this description.

The config file contains settings that are formatted as Lua code. No worries, the code is very easy to
understand and modify. There are two sections, Galleries and Config. The Config section allows the admin to
change the configuration for the entire plugin, such as the command prefix that the plugin uses, or the
database engine to use. The Galleries section contains the definitions for all the galleries.

Each gallery needs to be enclosed in an extra pair of braces. It needs to contain the following values in
order to become functional: Name, WorldName, MinX, MinZ, MaxX, MaxZ, FillStrategy and either AreaTemplate or
AreaSizeX and AreaSizeZ. There is an optional AreaEdge parameter, too. Note that the plugin will tell you if
it detects any problems in the gallery definition.

The Name parameter identifies the gallery. It needs to be unique for each gallery. Note that it cannot
contain "funny symbols", stay safe and use only letters, numbers and underscores. Also note that this is the
name that the users will type in their "claim" command. Good names are short and descriptive.

The WorldName parameter specifies the world in which the gallery resides. The MinX, MinZ, MaxX anx MaxZ
parameters specify the position and dimensions of the gallery in that world. Note that it is a good idea to
make the dimensions perfectly divisible by the size of the area, otherwise the gallery will contain empty
space where no-one except the server admins will be allowed to build.

The FillStrategy parameter specifies the order in which the areas are claimed within the gallery. The value
is a string containing the letters x, z and symbols + and -. The x and z specify the axis and + or - specify
the direction on that axis, so "x+" means "along the x axis towards the positive numbers", while "z-" means
"along the z axis towards the negative numbers". Two such directions, one for each axis, are joined together
to make up the FillStrategy. The first direction is used first, once the areas reach the end of that
direction, it is reset back and the second direction is applied. For example, setting the FillStrategy to
"z-x+" means that the first area will start at [MinX, MaxZ], the next area claimed will be at [MinX, MaxZ -
AreaSizeZ], the third area at [MinX, MaxZ - 2 * AreaSizeZ] etc.; once the Z coord reaches MinZ, the next
area will be at [MinX + AreaSizeX, MaxZ].

Areas can be either left as the world generator generates them, or the plugin can fill them with a
predefined "image" loaded from a .schematic file. To leave the world as it was generated, fill in the
AreaSizeX and AreaSizeZ values. These indicate how large each area will be. On the other hand, if the
AreaTemplate parameter is specified, the image is loaded from the given file and its size is used for
AreaSizeX and AreaSizeZ (so there's no need to specify those when using AreaTemplate), and the image is
pasted onto the area when it is claimed.

The AreaEdge parameter allows you to specify that each area should have an "edge" where even its owner
cannot build. This is useful for templates that include paths along the template's border. The value
represents the number of blocks from each of the area's boundaries that are unbuildable.

The Config section can contain the value CommandPrefix. Other values, such as for specifying the DB storage
engine, are planned but not yet implemented.

The CommandPrefix specifies the common part of the in-game commands that the users and admins use with this
plugin. If not specified, the plugin uses "/gallery" as its value; this would make it register the commands
"/gallery claim", "/gallery info", "/gallery my" etc. Changing the value to "/gal", for example, would make
the plugin register "/gal claim", "/gal info", "/gal my" and so on.
]]
		},
		{
			Title = "Setting up: permissions",
			Contents =
[[
Caution! Pay attention when setting up permissions, since giving someone the wrong permissions could allow
them to wreck entire galleries for everyone.

The permissions system specifies which users are allowed to interact with what level of the gallery plugin.
There are basically four levels, each comprising a group of commands that can be used. The first level is
"normal users". Users with this level of access can claim areas and build stuff in their owned areas. This
is the level where you want most of your users. Second level is "restricted users", these don't have any
permissions and thus cannot interact with the Gallery plugin at all, thus they cannot claim areas. Consider
this level a "punishment" level. The third level is "VIPs", player with these permissions can view
information about other players' areas, can list and teleport to other players' areas by their name. The
highest level, "admins", can rename anyone's areas, build and destroy anywhere, transfer or remove area
ownership and reset anyone's area.

Note that most admin-level permissions need their non-admin-level permissions in order to work. If you give
someone "gallery.admin.goto" but not "gallery.goto", they will not be able to use the goto command at all.
]]
		},
	},  -- AdditionalInfo
	
	Commands =
	{
		["/gallery"] =
		{
			-- Due to having subcommands, this command does not use either Permission nor HelpString
			Permission = "",
			HelpString = "",
			Handler = nil,
			Subcommands =
			{
				allow =
				{
					HelpString = "allows a friend to build at your area",
					Permission = "gallery.allow",
					Handler = HandleCmdAllow,
					ParameterCombinations =
					{
						{
							Params = "FriendName",
							Help = "allows the specified friend to build at your area where you're standing now",
						},
					},
				},
				
				claim =
				{
					HelpString = "claims a new area",
					Permission = "gallery.claim",
					Handler = HandleCmdClaim,
					ParameterCombinations =
					{
						{
							Params = "GalleryName",
							Help = "claims a new area in the specified gallery. The gallery must be in the current world.",
						},
					},
				},  -- claim
				
				deny =
				{
					HelpString = "denies a friend the build permissions for your area",
					Permission = "gallery.deny",
					Handler = HandleCmdDeny,
					ParameterCombinations =
					{
						{
							Params = "FormerFriendName",
							Help = "denies the specified friend the build permission to your area where you're standing now",
						},
					},
				},
				
				goto =
				{
					HelpString = "teleports you to specified gallery area",
					Permission = "gallery.goto",
					Handler = HandleCmdGoto,
					ParameterCombinations =
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
				},  -- goto
				
				help =
				{
					HelpString = "prints detailed help for the subcommand",
					Permission = "gallery.help",
					Handler = HandleCmdHelp,
					ParameterCombinations =  -- fun part - make "/gal help help" work as expected
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
				},  -- help
				
				info =
				{
					HelpString = "prints information on the area you're currently standing at",
					Permission = "gallery.info",
					Handler = HandleCmdInfo,
				},  -- info
				
				list =
				{
					HelpString = "lists all available galleries",
					Permission = "gallery.list",
					Handler = HandleCmdList,
				},  -- list
				
				my =
				{
					HelpString = "lists all your areas",
					Permission = "gallery.my",
					Handler = HandleCmdMy,
					ParameterCombinations =
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
				},  -- my
				
				name = 
				{
					HelpString = "renames the area you're currently standing at",
					Permission = "gallery.name",
					Handler = HandleCmdName,
					ParameterCombinations =
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
				},  -- name
				
				reset =
				{
					HelpString = "resets the area you're standing on to its original state",
					Permission = "gallery.reset",
					Handler = HandleCmdReset,
					ParameterCombinations =
					{
						{
							Permission = "gallery.reset",
							Help = "If you are the owner of the area, resets it to its original state",
						},
						{
							Permission = "gallery.admin.reset",
							Help = "Resets the area you're standing on it to its original state, regardless of the ownership",
						}
					},
				},  -- reset
				
				template =
				{
					HelpString = "creates new .schematic template based on your selection",
					Permission = "gallery.admin.template",
					Handler = HandleCmdTemplate,
					ParameterCombinations =
					{
						{
							Params = "FileName",
							Help = "Lets you select an arbitrary square area, then saves its contents into a file, FileName.schematic",
						},
					},
				},  -- template
			},  -- Subcommands
		},  -- ["/gallery"]
	},  -- Commands
	
	Permissions =
	{
		["gallery.admin.buildanywhere"] =
		{
			Description = "Build in other people's areas and the public sidewalks.",
			RecommendedGroups = "admins, mods",
		},
		["gallery.admin.buildanywhere.<GalleryName>"] =
		{
			Description = "Build in other people's areas and the public sidewalks in the specific gallery.",
			RecommendedGroups = "local admins, local mods",
		},
		["gallery.admin.goto"] =
		{
			Description = "Teleport to any player's area.",
			RecommendedGroups = "VIPs",
		},
		["gallery.admin.info"] =
		{
			Description = "View information on any area.",
			RecommendedGroups = "VIPs",
			CommandsAffected = { "/gallery info", },
		},
		["gallery.admin.my"] =
		{
			Description = "View list of areas for other players, using the \"/gallery my @playername [<galleryname>]\" form.",
			RecommendedGroups = "VIPs", },
		["gallery.admin.name"] =
		{
			Description = "Rename any area for any player.",
			RecommendedGroups = "admins, mods",
		},
		["gallery.admin.template"] =
		{
			Description = "Create a .schematic file out of an in-game cuboid.",
			RecommendedGroups = "admins",
		},
		["gallery.claim"] =
		{
			Description = "Claim an area in any gallery.",
			RecommendedGroups = "normal users",
		},
		["gallery.goto"] =
		{
			Description = "Teleport to an area owned by self.",
			RecommendedGroups = "normal users",
		},
		["gallery.help"] =
		{
			Description = "Display help for subcommands.",
			RecommendedGroups = "everyone",
		},
		["gallery.info"] =
		{
			Description = "View information on an area owned by self.",
			RecommendedGroups = "normal users",
		},
		["gallery.list"] =
		{
			Description = "List available gallery.",
			RecommendedGroups = "normal users",
		},
		["gallery.my"] =
		{
			Description = "List all my owned areas.",
			RecommendedGroups = "normal users",
		},
		["gallery.name"] =
		{
			Description = "Rename an area owned by self.",
			RecommendedGroups = "normal users",
		},
	},
};  -- g_PluginInfo




