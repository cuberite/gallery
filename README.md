This plugin allows users to automatically claim areas from a predefined "pool" of areas (galleries). Each such area is then protected so that only the area owner can interact with the area. 

# Setting up: galleries
Before the plugin can be fully used, the server admin needs to set up the galleries - define the galleries where players are allowed to claim areas. Some other configuration options are available, too. The configuration is read from the Galleries.cfg file located in the same folder as the MCServer executable. If the file doesn't exist, the plugin outputs a message in the server console and stays inactive. The plugin also creates an example configuration file named Galleries.example.cfg located next to the MCServer executable. This file contains an example configuration with documentation on all of the used variables. You might want to consult that file while continuing to read this description.

The config file contains settings that are formatted as Lua code. No worries, the code is very easy to understand and modify. There are two sections, Galleries and Config. The Config section allows the admin to change the configuration for the entire plugin, such as the command prefix that the plugin uses, or the database engine to use. The Galleries section contains the definitions for all the galleries.

Each gallery needs to be enclosed in an extra pair of braces. It needs to contain the following values in order to become functional: Name, WorldName, MinX, MinZ, MaxX, MaxZ, FillStrategy and either AreaTemplate or AreaSizeX and AreaSizeZ. There is an optional AreaEdge parameter, too. Note that the plugin will tell you if it detects any problems in the gallery definition.

The Name parameter identifies the gallery. It needs to be unique for each gallery. Note that it cannot contain "funny symbols", stay safe and use only letters, numbers and underscores. Also note that this is the name that the users will type in their "claim" command. Good names are short and descriptive.

The WorldName parameter specifies the world in which the gallery resides. The MinX, MinZ, MaxX anx MaxZ parameters specify the position and dimensions of the gallery in that world. Note that it is a good idea to make the dimensions perfectly divisible by the size of the area, otherwise the gallery will contain empty space where no-one except the server admins will be allowed to build.

The FillStrategy parameter specifies the order in which the areas are claimed within the gallery. The value is a string containing the letters x, z and symbols + and -. The x and z specify the axis and + or - specify the direction on that axis, so "x+" means "along the x axis towards the positive numbers", while "z-" means "along the z axis towards the negative numbers". Two such directions, one for each axis, are joined together to make up the FillStrategy. The first direction is used first, once the areas reach the end of that direction, it is reset back and the second direction is applied. For example, setting the FillStrategy to "z-x+" means that the first area will start at [MinX, MaxZ], the next area claimed will be at [MinX, MaxZ - AreaSizeZ], the third area at [MinX, MaxZ - 2 * AreaSizeZ] etc.; once the Z coord reaches MinZ, the next area will be at [MinX + AreaSizeX, MaxZ].

Areas can be either left as the world generator generates them, or the plugin can fill them with a predefined "image" loaded from a .schematic file. To leave the world as it was generated, fill in the AreaSizeX and AreaSizeZ values. These indicate how large each area will be. On the other hand, if the AreaTemplate parameter is specified, the image is loaded from the given file and its size is used for AreaSizeX and AreaSizeZ (so there's no need to specify those when using AreaTemplate), and the image is pasted onto the area when it is claimed.

The AreaEdge parameter allows you to specify that each area should have an "edge" where even its owner cannot build. This is useful for templates that include paths along the template's border. The value represents the number of blocks from each of the area's boundaries that are unbuildable.

The Config section can contain the value CommandPrefix. Other values, such as for specifying the DB storage engine, are planned but not yet implemented.

The CommandPrefix specifies the common part of the in-game commands that the users and admins use with this plugin. If not specified, the plugin uses "/gallery" as its value; this would make it register the commands "/gallery claim", "/gallery info", "/gallery my" etc. Changing the value to "/gal", for example, would make the plugin register "/gal claim", "/gal info", "/gal my" and so on. 

# Setting up: permissions
Caution! Pay attention when setting up permissions, since giving someone the wrong permissions could allow them to wreck entire galleries for everyone.

The permissions system specifies which users are allowed to interact with what level of the gallery plugin. There are basically four levels, each comprising a group of commands that can be used. The first level is "normal users". Users with this level of access can claim areas and build stuff in their owned areas. This is the level where you want most of your users. Second level is "restricted users", these don't have any permissions and thus cannot interact with the Gallery plugin at all, thus they cannot claim areas. Consider this level a "punishment" level. The third level is "VIPs", player with these permissions can view information about other players' areas, can list and teleport to other players' areas by their name. The highest level, "admins", can rename anyone's areas, build and destroy anywhere, transfer or remove area ownership and reset anyone's area.

Note that most admin-level permissions need their non-admin-level permissions in order to work. If you give someone "gallery.admin.goto" but not "gallery.goto", they will not be able to use the goto command at all. 

# Commands

### General
| Command | Permission | Description |
| ------- | ---------- | ----------- |
|/gallery allow | gallery.allow | allows a friend to build at your area|
|/gallery claim | gallery.claim | claims a new area|
|/gallery deny | gallery.deny | denies a friend the build permissions for your area|
|/gallery fork | gallery.fork | copy-and-claims an area|
|/gallery goto | gallery.goto | teleports you to specified gallery area|
|/gallery help | gallery.help | prints detailed help for the subcommand|
|/gallery info | gallery.info | prints information on the area you're currently standing at|
|/gallery list | gallery.list | lists all available galleries|
|/gallery my | gallery.my | lists all your areas|
|/gallery name | gallery.name | renames the area you're currently standing at|
|/gallery reset | gallery.reset | resets the area you're standing on to its original state|
|/gallery select | gallery.select | selects the entire area you're standing in.|
|/gallery stats | gallery.stats | shows statistics about the galleries on this server|
|/gallery template | gallery.admin.template | creates new .schematic template based on your selection|
|/gallery visit | gallery.visit | teleports you to the specified gallery|



# Permissions
| Permissions | Description | Commands | Recommended groups |
| ----------- | ----------- | -------- | ------------------ |
| gallery.admin.buildanywhere | Build in other people's areas and the public sidewalks. |  | admins, mods |
| gallery.admin.buildanywhere.<GalleryName> | Build in other people's areas and the public sidewalks in the specific gallery. |  | local admins, local mods |
| gallery.admin.goto | Teleport to any player's area. | `/gallery goto @PlayerName AreaName`, `/gallery goto`, `/gallery goto @PlayerName AreaName` | VIPs |
| gallery.admin.info | View information on any area. | `/gallery info` | VIPs |
| gallery.admin.my | View list of areas for other players, using the "/gallery my @playername [<galleryname>]" form. | `/gallery my @PlayerName`, `/gallery my @PlayerName GalleryName`, `/gallery my`, `/gallery my @PlayerName`, `/gallery my @PlayerName GalleryName` | VIPs |
| gallery.admin.name | Rename any area for any player. | `/gallery name NewName`, `/gallery name @PlayerName OldName NewName`, `/gallery name`, `/gallery name NewName`, `/gallery name @PlayerName OldName NewName` | admins, mods |
| gallery.admin.template | Create a .schematic file out of an in-game cuboid. | `/gallery template`, `/gallery template` | admins |
| gallery.admin.worldedit | Allows the use of worldedit anywhere in the gallery. |  | admins |
| gallery.allow | Allow another player to build in your area. | `/gallery allow`, `/gallery allow` | normal users |
| gallery.claim | Claim an area in any gallery. | `/gallery claim`, `/gallery claim` | normal users |
| gallery.deny | Deny another player to build in your area. | `/gallery deny`, `/gallery deny` | normal users |
| gallery.fork |  | `/gallery fork`, `/gallery fork` |  |
| gallery.goto | Teleport to any player's area. | `/gallery goto @PlayerName AreaName`, `/gallery goto`, `/gallery goto @PlayerName AreaName` | VIPs |
| gallery.help | Display help for subcommands. | `/gallery help`, `/gallery help` | everyone |
| gallery.info | View information on an area owned by self. | `/gallery info`, `/gallery info` | normal users |
| gallery.list | List available gallery. | `/gallery list`, `/gallery list` | normal users |
| gallery.my | View list of areas for other players, using the "/gallery my @playername [<galleryname>]" form. | `/gallery my @PlayerName`, `/gallery my @PlayerName GalleryName`, `/gallery my`, `/gallery my @PlayerName`, `/gallery my @PlayerName GalleryName` | VIPs |
| gallery.name | Rename any area for any player. | `/gallery name NewName`, `/gallery name @PlayerName OldName NewName`, `/gallery name`, `/gallery name NewName`, `/gallery name @PlayerName OldName NewName` | admins, mods |
| gallery.reset |  | `/gallery reset` |  |
| gallery.select |  | `/gallery select`, `/gallery select` |  |
| gallery.stats |  | `/gallery stats`, `/gallery stats` |  |
| gallery.visit | Teleport to any gallery. | `/gallery visit`, `/gallery visit` | normal users |
| gallery.worldedit | Allows the use of WorldEdit within each individual area. |  | normal users |
