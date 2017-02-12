
-- WebList.lua

-- Implements the webadmin page listing the gallery areas, and the News





local ins = table.insert
local g_NumAreasPerPage = 50

-- Contains the PNG file for "Preview not available yet" image
local g_PreviewNotAvailableYetPng

--- Object that manages area previews - creates, stores, refreshes...
local g_AreaPreview





--- Checks the previews for the specified areas and regenerates the ones that are outdated
-- a_Areas is an array of areas as loaded from the DB
local function RefreshPreviewForAreas(a_Areas)
	-- Check params and preconditions:
	assert(type(a_Areas) == "table")
	assert(g_Config.WebPreview)
	assert(g_AreaPreview)

	-- Check each area and each rotation:
	local toExport = {}  -- array of {Area = <db-area>, NumRotations = <number>}
	local idx = 1
	for _, area in ipairs(a_Areas) do
		toExport[idx] = area
		idx = idx + 1
	end

	-- Sort the ToExport array by coords (to help reuse the chunks):
	table.sort(toExport,
		function (a_Item1, a_Item2)
			-- Compare the X coord first:
			if (a_Item1.MinX < a_Item2.MinX) then
				return true
			end
			if (a_Item1.MinX > a_Item2.MinX) then
				return false
			end
			-- The X coord is the same, compare the Z coord:
			return (a_Item1.MinZ < a_Item2.MinZ)
		end
	)

	-- Export each area:
	for _, area in ipairs(toExport) do
		for rot = 0, 3 do
			g_AreaPreview:RefreshPreview(area, rot)
		end
	end
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
				ins(Page, "?action=getpreview&areaid=")
				ins(Page, Area.ID)
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
	local areaID = tonumber(a_Request.Params["areaid"])
	local rot = tonumber(a_Request.Params["rot"])
	if (not(areaID) or not(rot)) then
		return "Invalid identification"
	end

	local img = g_AreaPreview:GetPreview(areaID, rot)
	if not(img) then
		return g_PreviewNotAvailableYetPng, "image/png"
	end
	return img, "image/png"
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
		local page, responseType = handler(a_Gallery, a_Request, action)
		if (page and (page ~= "")) then
			return page, responseType
		end
	end

	-- No action, or the action handler returned nothing
	return BuildGalleryPager(a_Gallery, a_Request) .. BuildGalleryAreaList(a_Gallery, a_Request) .. BuildGalleryPager(a_Gallery, a_Request)
end





--- Initializes the web preview
-- Queries the DB for all areas, then checks the age of each area's output files; regenerates missing and old files
local function InitWebPreview()
	-- Read the "preview not available yet" image:
	g_PreviewNotAvailableYetPng = cFile:ReadWholeFile(cPluginManager:GetCurrentPlugin():GetLocalFolder() .. "/PreviewNotAvailableYet.png")

	-- Initialize the preview storage and creation object:
	g_AreaPreview = InitAreaPreview(g_Config.WebPreview.MCSchematicToPng)

	-- RefreshPreviewForAreas(g_DB:LoadAllAreas())
end





local function HandleWebLatestClaims(a_Request)
	-- Schedule the previews for a refresh:
	local Areas = g_DB:LoadLatestClaimedAreas(g_Config.NumWebNewsClaims or 20)
	if (g_Config.WebPreview) then
		RefreshPreviewForAreas(Areas)
	end

	-- Compose the page:
	local res =
	{
		"<h2>Latest claimed areas</h2>\n",
		"<table>\n",
		"<tr><th>#</th><th>Claimed</th><th>Player</th><th>Position</th><th>Block changes</th>",
		g_Config.WebPreview and "<th colspan=4>Preview</th>" or "",
		"</tr>\n"
	}
	local requestBasePath = a_Request.Path .. "/../"
	for idx, area in ipairs(Areas) do
		local cells =
		{
			idx,
			string.gsub(area.DateClaimed, "T", " "),
			cWebAdmin:GetHTMLEscapedString(area.PlayerName),
			cWebAdmin:GetHTMLEscapedString(area.GalleryName) .. " " .. area.GalleryIndex,
			"+" .. area.NumPlacedBlocks .. " / -" .. area.NumBrokenBlocks
		}
		if (g_Config.WebPreview) then
			for rot = 0, 3 do
				table.insert(cells, string.format("<img src=\"/~%s%s?action=getpreview&areaid=%d&rot=%d\"/>",
					requestBasePath, area.GalleryName, area.ID, rot)
				)
			end
		end
		table.insert(res, "<tr><td valign='top'>" .. table.concat(cells, "</td><td valign='top'>") .. "</td></tr>\n")
	end
	table.insert(res, "</table>\n")
	return table.concat(res)
end





local function HandleWebLatestChanges(a_Request)
	-- Schedule the previews for a refresh:
	local Areas = g_DB:LoadLatestChangedAreas(g_Config.NumWebNewsChanges or 20)
	if (g_Config.WebPreview) then
		RefreshPreviewForAreas(Areas)
	end

	-- Compose the page:
	local res =
	{
		"<h2>Latest edits</h2>\n",
		"<table>\n",
		"<tr><th>#</th><th>Changed</th><th>Player</th><th>Position</th><th>Total block changes</th>",
		g_Config.WebPreview and "<th colspan=4>Preview</th>" or "",
		"</tr>\n"
	}
	local requestBasePath = a_Request.Path .. "/../"
	for idx, area in ipairs(Areas) do
		local cells =
		{
			idx,
			string.gsub(area.DateLastChanged, "T", " "),
			cWebAdmin:GetHTMLEscapedString(area.PlayerName),
			cWebAdmin:GetHTMLEscapedString(area.GalleryName) .. " " .. area.GalleryIndex,
			"+" .. area.NumPlacedBlocks .. " / -" .. area.NumBrokenBlocks
		}
		if (g_Config.WebPreview) then
			for rot = 0, 3 do
				table.insert(cells, string.format("<img src=\"/~%s%s?action=getpreview&areaid=%d&rot=%d\"/>",
					requestBasePath, area.GalleryName, area.ID, rot)
				)
			end
		end
		table.insert(res, "<tr><td valign='top'>" .. table.concat(cells, "</td><td valign='top'>") .. "</td></tr>\n")
	end
	table.insert(res, "</table>\n")
	return table.concat(res)
end





--- Registers the web page in the webadmin and does whatever initialization is needed
function InitWebList()
	-- For each gallery, add a webadmin tab of the name, and a custom handler producing HTML for that gallery
	for _, gal in ipairs(g_Galleries) do
		cWebAdmin:AddWebTab(gal.Name, gal.Name,
			function (a_Request)
				return BuildGalleryPage(gal, a_Request)
			end
		)
	end

	-- Add the News tabs:
	cWebAdmin:AddWebTab("Latest claims",  "latest-claims",  HandleWebLatestClaims)
	cWebAdmin:AddWebTab("Latest changes", "latest-changes", HandleWebLatestChanges)

	if (g_Config.WebPreview) then
		InitWebPreview()
	end
end




