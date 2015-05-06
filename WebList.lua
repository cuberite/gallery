
-- WebList.lua

-- Implements the webadmin page listing the gallery areas





local ins = table.insert
local g_NumAreasPerPage = 50

-- Contains the PNG file for "Preview not available yet" image
local g_PreviewNotAvailableYetPng





--- Uses MCSchematicToPng to convert .schematic files into PNG previews for the specified areas
local ExportCounter = 0
local function ExportPreviewForAreas(a_Areas)
	-- Write the list file:
	local fnam = g_Config.WebPreview.ThumbnailFolder .. "/export" .. ExportCounter .. ".txt"
	ExportCounter = ExportCounter + 1
	local f, msg = io.open(fnam, "w")
	if not(f) then
		LOG(PLUGIN_PREFIX .. "Cannot export preview, failed to open list file for MCSchematicToPng: " .. (msg or "<unknown error>"))
		return
	end
	for _, area in ipairs(a_Areas) do
		local base = g_Config.WebPreview.ThumbnailFolder .. "/" .. area.Area.GalleryName .. "/" .. area.Area.GalleryIndex
		f:write(base .. ".schematic\n")
		f:write(" outfile: " .. base .. "." .. area.NumRotations .. ".png\n")
		f:write(" numcwrotations: " .. area.NumRotations .. "\n")
		if (area.Area.EditMinX) then
			f:write(" startx: " .. area.Area.EditMinX .. "\n")
		elseif (area.Area.ExportMinX) then
			f:write(" startx: " .. area.Area.ExportMinX - area.Area.MinX .. "\n")
		end
		if (area.Area.EditMinY) then
			f:write(" starty: " .. area.Area.EditMinY .. "\n")
		elseif (area.Area.ExportMinY) then
			f:write(" starty: " .. area.Area.ExportMinY .. "\n")
		end
		if (area.Area.EditMinZ) then
			f:write(" startz: " .. area.Area.EditMinZ .. "\n")
		elseif (area.Area.ExportMinZ) then
			f:write(" startz: " .. area.Area.ExportMinZ - area.Area.MinZ .. "\n")
		end
		if (area.Area.EditMaxX) then
			f:write(" endx: " .. area.Area.EditMaxX .. "\n")
		elseif (area.Area.ExportMaxX) then
			f:write(" endx: " .. area.Area.ExportMaxX - area.Area.MinX .. "\n")
		end
		if (area.Area.EditMaxY) then
			f:write(" endy: " .. area.Area.EditMaxY .. "\n")
		elseif (area.Area.ExportMaxY) then
			f:write(" endy: " .. area.Area.ExportMaxY .. "\n")
		end
		if (area.Area.EditMaxZ) then
			f:write(" endz: " .. area.Area.EditMaxZ .. "\n")
		elseif (area.Area.ExportMaxZ) then
			f:write(" endz: " .. area.Area.ExportMaxZ - area.Area.MinZ .. "\n")
		end
	end
	f:close()
	
	-- Start MCSchematicToPng:
	local cmdline = g_Config.WebPreview.MCSchematicToPng .. " " .. fnam .. " >" .. fnam .. ".out 2>" .. fnam .. ".err"
	if (cFile:GetExecutableExt() == ".exe") then
		-- We're on a Windows-like OS, use "start /b <cmd>" to execute in the background:
		cmdline = "start /b " .. cmdline
	else
		-- We're on a Linux-like OS, use "<cmd> &" to execute in the background:
		cmdline = cmdline .. " &"
	end
	os.execute(cmdline)  -- There's no platform-independent way of checking the result
end





--- Compares the area to the gallery template (if available), thus calculating the coord range of the changes
-- If the gallery has no template, there's no way to calculate and this function just bails out
-- When the ranges are calculated, they are stored back in the DB
-- a_Area is the DB description of the area
-- a_BlockArea is a cBlockArea containing the area's blocks read from the world
local function UpdateAreaEditRange(a_Area, a_BlockArea)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.Gallery)
	assert(tolua.type(a_BlockArea) == "cBlockArea")
	
	-- If there's no gallery template, bail out:
	if not(a_Area.Gallery.AreaTemplateSchematic) then
		return
	end
	
	-- Get the range of the edits by msSimpleCompare-ing to the gallery's template:
	a_BlockArea:Merge(a_Area.Gallery.AreaTemplateSchematic, -a_Area.Gallery.AreaEdge, 0, -a_Area.Gallery.AreaEdge, cBlockArea.msSimpleCompare)
	a_Area.EditMinX, a_Area.EditMinY, a_Area.EditMinZ, a_Area.EditMaxX, a_Area.EditMaxY, a_Area.EditMaxZ = a_BlockArea:GetNonAirCropRelCoords()
	if (a_Area.EditMinX > a_Area.EditMaxX) then
		-- The entire area is the same as the template, reset all the coords to the template's ones:
		a_Area.EditMinX, a_Area.EditMinY, a_Area.EditMinZ, a_Area.EditMaxX, a_Area.EditMaxY, a_Area.EditMaxZ = a_Area.Gallery.AreaTemplateSchematic:GetNonAirCropRelCoords()
	end
	g_DB:UpdateAreaEditRange(a_Area)
end





--- Generates the preview files for the specified areas
-- a_Areas is an array of {Area = {<db-area>}, NumRotations = ...}
local function GeneratePreviewForAreas(a_Areas)
	if not(a_Areas[1]) then
		return
	end
	
	-- Get a list of .schematic files that need updating
	local ToExport = {}
	for _, area in ipairs(a_Areas) do
		if not(ToExport[area]) then
			local fnam = g_Config.WebPreview.ThumbnailFolder .. "/" .. area.Area.GalleryName .. "/" .. area.Area.GalleryIndex .. ".schematic"
			local ftim = FormatDateTime(cFile:GetLastModificationTime(fnam))
			if (area.Area.DateLastChanged > ftim) then
				table.insert(ToExport, area.Area)
			end
			ToExport[area] = true
		end
	end
	
	-- Export the .schematic files for each area, process one are after another, using ChunkStays:
	-- (after one area is written to a file, schedule another ChunkStay for the next area)
	-- Note that due to multithreading, the export needs to be scheduled onto the World Tick thread, otherwise a deadlock may occur
	local ba = cBlockArea()
	local idx = 1
	local ProcessArea
	local LastGallery
	ProcessArea = function()
		local area = ToExport[idx]
		ba:Read(area.Gallery.World, area.MinX + area.Gallery.AreaEdge, area.MaxX - area.Gallery.AreaEdge - 1, 0, 255, area.MinZ + area.Gallery.AreaEdge, area.MaxZ - area.Gallery.AreaEdge - 1)
		ba:SaveToSchematicFile(g_Config.WebPreview.ThumbnailFolder .. "/" .. area.GalleryName .. "/" .. area.GalleryIndex .. ".schematic")
		-- Calculate the edit range by comparing with the gallery's template:
		UpdateAreaEditRange(area, ba)
		idx = idx + 1
		if (ToExport[idx]) then
			-- When moving to the next gallery or after 10 areas, unload chunks that are no longer needed and queue the task on the new world:
			-- When all chunks are loaded, the ChunkStay produces one deep nested call, going over LUAI_MAXCCALLS
			if ((ToExport[idx].Gallery ~= LastGallery) or (idx % 10 == 0)) then
				LastGallery.World:QueueUnloadUnusedChunks()
				LastGallery = ToExport[idx].Gallery
				LastGallery.World:QueueTask(
					function()
						LastGallery.World:ChunkStay(GetAreaChunkCoords(ToExport[idx]), nil, ProcessArea)
					end
				)
			else
				-- Queue the next area on the same world:
				ToExport[idx].Gallery.World:ChunkStay(GetAreaChunkCoords(ToExport[idx]), nil, ProcessArea)
			end
		else
			ExportPreviewForAreas(a_Areas)
		end
	end
	if (ToExport[1]) then
		-- Queue the export task on the cWorld instance, so that it is executed in the world's Tick thread:
		LastGallery = ToExport[1].Gallery
		LastGallery.World:QueueTask(
			function()
				LastGallery.World:ChunkStay(GetAreaChunkCoords(ToExport[1]), nil, ProcessArea)
			end
		)
	else
		ExportPreviewForAreas(a_Areas)
	end
end





--- Checks the preview files for the specified areas and regenerates the ones that are outdated
-- a_Areas is an array of areas as loaded from the DB
local function RefreshPreviewForAreas(a_Areas)
	-- Check params and preconditions:
	assert(type(a_Areas) == "table")
	assert(g_Config.WebPreview)
	
	local ToExport = {}  -- array of {Area = <db-area>, NumRotations = <number>}
	for _, area in ipairs(a_Areas) do
		local fnam = g_Config.WebPreview.ThumbnailFolder .. "/" .. area.GalleryName .. "/" .. area.GalleryIndex
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".0.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 0})
		end
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".1.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 1})
		end
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".2.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 2})
		end
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".3.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 3})
		end
	end

	-- Sort the ToExport array by coords (to help reuse the chunks):
	table.sort(ToExport,
		function (a_Item1, a_Item2)
			-- Compare the X coord first:
			if (a_Item1.Area.MinX < a_Item2.Area.MinX) then
				return true
			end
			if (a_Item1.Area.MinX > a_Item2.Area.MinX) then
				return false
			end
			-- The X coord is the same, compare the Z coord:
			return (a_Item1.Area.MinZ < a_Item2.Area.MinZ)
		end
	)
	
	-- Export each area:
	GeneratePreviewForAreas(ToExport)
end





--- Returns the description of the specified area
local function GetAreaDescription(a_Area)
	assert(type(a_Area) == "table")
	
	-- If the area is not valid, return "<unclaimed>":
	if (a_Area.Name == nil) then
		return "<p style='color: grey'>&lt;unclaimed&gt;</p>"
	end
	
	-- Return the area's name and position, unless they're equal:
	local Position = a_Area.GalleryName .. " " .. a_Area.GalleryIndex
	if (Position == a_Area.Name) then
		return cWebAdmin:GetHTMLEscapedString(a_Area.Name)
	else
		return cWebAdmin:GetHTMLEscapedString(a_Area.Name .. " (" .. Position .. ")")
	end
end





--- Returns the HTML code for a form that contains an action button for a specific area
-- Either a_AreaID must be valid, or a_GalleryName and a_GalleryIndex
local function AddActionButton(a_Action, a_FormDest, a_AreaID, a_GalleryName, a_GalleryIndex, a_ButtonText)
	-- Check params:
	assert(a_Action)
	assert(a_FormDest)
	assert(a_AreaID or (a_GalleryName and a_GalleryIndex))
	assert(a_ButtonText)
	
	if (a_AreaID) then
		return
			[[<form action="]]..
			a_FormDest ..
			[[" method="POST"><input type="hidden" name="action" value="]] ..
			a_Action ..
			[["/><input type="hidden" name="areaid" value="]] ..
			a_AreaID ..
			[["/><input type="submit" value="]] ..
			a_ButtonText ..
			[["/></form>]]
	else
		return
			[[<form action="]]..
			a_FormDest ..
			[[" method="POST"><input type="hidden" name="action" value="]] ..
			a_Action ..
			[["/><input type="hidden" name="galleryname" value="]] ..
			a_GalleryName ..
			[["/><input type="hidden" name="galleryindex" value="]] ..
			a_GalleryIndex ..
			[["/><input type="submit" value="]] ..
			a_ButtonText ..
			[["/></form>]]
	end
end





--- Returns the (relative) path to the specified page number, based on the request's path
-- a_SortBy is the optional sorting parameter
local function PathToPage(a_RequestPath, a_PageNum, a_SortBy)
	local res = "/" .. a_RequestPath .. "?startidx=" .. tostring((a_PageNum - 1) * g_NumAreasPerPage)
	if (a_SortBy) then
		res = res .. "&sortby=" .. a_SortBy
	end
	return res
end





--- Returns the HTML list of areas in the specified gallery, based on the range in the request
local function BuildGalleryAreaList(a_Gallery, a_Request)
	-- Read the request params:
	local StartIdx = tonumber(a_Request.Params["startidx"]) or 0
	local EndIdx = StartIdx + g_NumAreasPerPage - 1
	local SortBy = a_Request.Params["sortby"] or "GalleryIdx"
	
	-- Get the areas from the DB, as a map of Idx -> Area
	local Areas = g_DB:LoadGalleryAreasRange(a_Gallery.Name, SortBy, StartIdx, EndIdx)
	
	-- Queue the areas for re-export:
	if (g_Config.WebPreview) then
		local AreaArray = {}
		for idx, area in pairs(Areas) do
			table.insert(AreaArray, area)
		end
		RefreshPreviewForAreas(AreaArray)
	end
	
	-- Build the page:
	local FormDest = "/" .. a_Request.Path .. "?startidx=" .. StartIdx .. "&sortby=" .. SortBy
	local Page = {"<table><tr><th><a href=\"/"}
	ins(Page, a_Request.Path)
	ins(Page, "?sortby=GalleryIndex\">Index</a></th>")
	if (g_Config.WebPreview) then
		ins(Page, "<th colspan=4>Preview</th>")
	end
	ins(Page, "<th><a href=\"/")
	ins(Page, a_Request.Path)
	ins(Page, "?sortby=Name\">Area</a></th><th>Player</th><th>Date claimed</th><th colspan=2 width='1%'>Action</th></tr>")
	for idx, Area in ipairs(Areas) do
		ins(Page, "<tr><td valign='top'>")
		ins(Page, Area.GalleryIndex or "&nbsp;")
		ins(Page, "</td><td valign='top'>")
		if (g_Config.WebPreview) then
			for rot = 0, 3 do
				ins(Page, "<img src=\"/~")
				ins(Page, a_Request.Path)
				ins(Page, "?action=getpreview&galleryname=")
				ins(Page, Area.GalleryName)
				ins(Page, "&galleryidx=")
				ins(Page, Area.GalleryIndex)
				ins(Page, "&rot=")
				ins(Page, rot)
				ins(Page, "\"/></td><td valign='top'>")
			end
		end
		ins(Page, GetAreaDescription(Area))
		ins(Page, "</td><td valign='top'>")
		ins(Page, cWebAdmin:GetHTMLEscapedString(Area.PlayerName) or "&nbsp;")
		ins(Page, "</td><td valign='top'>")
		ins(Page, Area.DateClaimed or "&nbsp;")
		ins(Page, "</td><td valign='top'>")
		if (Area.IsLocked) then
			ins(Page, AddActionButton("unlock", FormDest, Area.ID, nil, nil, "Unlock"))
		elseif (Area.Name) then
			ins(Page, AddActionButton("lock", FormDest, Area.ID, nil, nil, "Lock"))
		end
		ins(Page, "</td><td valign='top'>")
		-- If the area is claimed, add the Remove action button:
		if (Area.Name) then
			ins(Page, AddActionButton("remove", FormDest, Area.ID, a_Gallery.Name, idx, "Remove"))
		end
		ins(Page, "</td></tr>")
	end
	
	return table.concat(Page)
end





--- Returns the pager for the specified gallery, positioned by the parameters in a_Request
local function BuildGalleryPager(a_Gallery, a_Request)
	-- Read the request params:
	local StartIdx = a_Request.Params["startidx"] or 0
	local EndIdx = StartIdx + g_NumAreasPerPage - 1
	local CurrentPage = StartIdx / g_NumAreasPerPage + 1
	local Path = a_Request.Path
	local SortBy = a_Request.Params["sortby"]
	local MaxPageNum = math.ceil(a_Gallery.NextAreaIdx / g_NumAreasPerPage)
	
	-- Insert the "first page" link:
	local res = {"<table><tr><th><a href=\""}
	ins(res, PathToPage(Path, 1, SortBy))
	ins(res, "\">|&lt;&lt;&lt</a></th><th width='100%' style='align: center'><center>")
	
	-- Insert the page links for up to 5 pages in each direction:
	local Pager = {}
	for PageNum = CurrentPage - 5, CurrentPage + 5 do
		if ((PageNum > 0) and (PageNum <= MaxPageNum)) then
			ins(Pager, table.concat({
				"<a href=\"",
				PathToPage(Path, PageNum, SortBy),
				"\">",
				PageNum,
				"</a>"
			}))
		end
	end
	ins(res, table.concat(Pager, " | "))
	
	-- Insert the "last page" link:
	ins(res, "</center></th><th><a href=\"")
	ins(res, PathToPage(Path, MaxPageNum, SortBy))
	ins(res, "\">&gt;&gt;&gt;|</a></th></table>")
	
	return table.concat(res)
end





--- Locks the area specified in the request and returns the HTML to be displayed to the client
local function ExecuteLock(a_Gallery, a_Request)
	-- Get the AreaID from the request:
	local AreaID = a_Request.PostParams["areaid"]
	if not(AreaID) then
		-- invalid request, just return the base page:
		return BuildGalleryAreaList(a_Gallery, a_Request)
	end
	
	-- Lock the area:
	LockAreaByID(AreaID, a_Request.Username and ("<web: " .. a_Request.Username ..">") or "<web: unknown user>")
	
	-- Return the base page with a notification:
	return "<p>Area locked</p>" .. BuildGalleryPager(a_Gallery, a_Request) .. BuildGalleryAreaList(a_Gallery, a_Request) .. BuildGalleryPager(a_Gallery, a_Request)
end





--- Unlocks the area specified in the request and returns the HTML to be displayed to the client
local function ExecuteUnlock(a_Gallery, a_Request)
	-- Get the AreaID from the request:
	local AreaID = a_Request.PostParams["areaid"]
	if not(AreaID) then
		-- invalid request, just return the base page:
		return BuildGalleryAreaList(a_Gallery, a_Request)
	end
	
	-- Unlock the area:
	UnlockAreaByID(AreaID, a_Request.Username and ("<web: " .. a_Request.Username ..">") or "<web: unknown user>")
	
	-- Return the base page with a notification:
	return "<p>Area unlocked</p>" .. BuildGalleryPager(a_Gallery, a_Request) .. BuildGalleryAreaList(a_Gallery, a_Request) .. BuildGalleryPager(a_Gallery, a_Request)
end





--- Shows a confirmation page for the area removal
local function ExecuteRemove(a_Gallery, a_Request)
	-- Get the AreaID from the request:
	local AreaID = a_Request.PostParams["areaid"]
	if not(AreaID) then
		-- Invalid request, just return the base page:
		return BuildGalleryAreaList(a_Gallery, a_Request)
	end
	
	-- Get the area details:
	local Area = g_DB:LoadAreaByID(AreaID)
	if not(Area) then
		-- Invalid area specified, just return the base page:
		return BuildGalleryAreaList(a_Gallery, a_Request)
	end
	
	-- Show ALL the area's properties, alpha-sorted:
	local res =
	{
		"<p><b>Are you sure you want to remove the following area?</b></p><table><tr><td>",
		AddActionButton("removeconfirm", a_Request.URL, AreaID, nil, nil, "Remove"),
		"</td><td><a href=\"",
		a_Request.URL,
		"\">Cancel</a></td><td width='100%'></td></tr></table><br/><table>",
	}
	local Properties = {}
	for k, v in pairs(Area) do
		if (type(v) ~= "table") then
			table.insert(Properties, {Name = k, Value = v})
		end
	end
	table.sort(Properties,
		function (a_Prop1, a_Prop2)
			return (a_Prop1.Name < a_Prop2.Name)
		end
	)
	for _, prop in ipairs(Properties) do
		ins(res, "<tr><td>")
		ins(res, cWebAdmin:GetHTMLEscapedString(prop.Name))
		ins(res, "</td><td>")
		ins(res, cWebAdmin:GetHTMLEscapedString(tostring(prop.Value)))
		ins(res, "</td></tr>")
	end
	ins(res, "</table>")
	
	return table.concat(res)
end





--- Removes the area specified in the request and returns the HTML to be displayed to the client
local function ExecuteRemoveConfirmed(a_Gallery, a_Request)
	-- Get the AreaID from the request:
	local AreaID = a_Request.PostParams["areaid"]
	if not(AreaID) then
		-- invalid request, just return the base page:
		return BuildGalleryAreaList(a_Gallery, a_Request)
	end
	
	-- Remove the area:
	local Area = g_DB:LoadAreaByID(AreaID)
	if (Area) then
		g_DB:RemoveArea(Area, a_Request.Username and ("<web: " .. a_Request.Username ..">") or "<web: unknown user>")
	end
	
	-- Return the base page with a notification:
	return "<p>Area removed</p>" .. BuildGalleryPager(a_Gallery, a_Request) .. BuildGalleryAreaList(a_Gallery, a_Request) .. BuildGalleryPager(a_Gallery, a_Request)
end





local function ExecuteGetPreview(a_Gallery, a_Request)
	-- Get the params:
	local GalleryName = a_Request.Params["galleryname"]
	local GalleryIdx = a_Request.Params["galleryidx"]
	local rot = a_Request.Params["rot"]
	if not(GalleryName) or not(GalleryIdx) or not(rot) then
		return "Invalid identification"
	end
	
	local fnam = g_Config.WebPreview.ThumbnailFolder .. "/" .. GalleryName .. "/" .. GalleryIdx .. "." .. rot .. ".png"
	local f, msg = io.open(fnam, "rb")
	if not(f) then
		return g_PreviewNotAvailableYetPng
	end
	local res = f:read("*all")
	f:close()
	return res
end





--- A map of "action" -> handler(a_Gallery, a_Request, a_Action)
local g_ActionHandlers =
{
	["lock"]          = ExecuteLock,
	["unlock"]        = ExecuteUnlock,
	["remove"]        = ExecuteRemove,
	["removeconfirm"] = ExecuteRemoveConfirmed,
	["getpreview"]    = ExecuteGetPreview,
}





--- Returns the HTML page for the specified gallery and specified request
local function BuildGalleryPage(a_Gallery, a_Request)
	-- If an action is to be performed, do it:
	local action = a_Request.PostParams["action"] or a_Request.Params["action"]
	local handler = g_ActionHandlers[action]
	if (handler) then
		local Page = handler(a_Gallery, a_Request, action)
		if (Page and (Page ~= "")) then
			return Page
		end
	end
	
	-- No action, or the action handler returned nothing
	return BuildGalleryPager(a_Gallery, a_Request) .. BuildGalleryAreaList(a_Gallery, a_Request) .. BuildGalleryPager(a_Gallery, a_Request)
end





--- Initializes the web preview
-- Queries the DB for all areas, then checks the age of each area's output files; regenerates missing and old files
local function InitWebPreview()
	-- Create folders for the thumbnail files:
	cFile:CreateFolder(g_Config.WebPreview.ThumbnailFolder)
	for _, gallery in ipairs(g_Galleries) do
		cFile:CreateFolder(g_Config.WebPreview.ThumbnailFolder .. "/" .. gallery.Name)
	end

	-- Read the "preview not available yet" image:
	g_PreviewNotAvailableYetPng = cFile:ReadWholeFile(cPluginManager:GetCurrentPlugin():GetLocalFolder() .. "/PreviewNotAvailableYet.png")
	
	-- RefreshPreviewForAreas(g_DB:LoadAllAreas())
end





--- Registers the web page in the webadmin and does whatever initialization is needed
function InitWebList()
	-- For each gallery, add a webadmin tab of the name, and a custom handler producing HTML for that gallery
	for _, gal in ipairs(g_Galleries) do
		cPluginManager:Get():GetCurrentPlugin():AddWebTab(gal.Name,
			function (a_Request)
				return BuildGalleryPage(gal, a_Request)
			end
		)
	end
	
	if (g_Config.WebPreview) then
		InitWebPreview()
	end
end




