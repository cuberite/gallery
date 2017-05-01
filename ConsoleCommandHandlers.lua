-- ConsoleCommandHandlers.lua

-- Implements the handling of console commands available to server admins





--- Returns true if the area has suspicious stats - zero NumPlacedBlocks, or invalid min / max edit range
local function AreaNeedsFixingStats(a_Area)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.Gallery)
	assert(a_Area.Gallery.AreaEdge)

	-- Zero placed blocks is suspicious
	if (a_Area.NumPlacedBlocks == 0) then
		return true
	end

	-- No edit range is a definite reason for stats recalc:
	if (
		not(a_Area.EditMaxX) or not(a_Area.EditMinX) or
		not(a_Area.EditMaxY) or not(a_Area.EditMinY) or
		not(a_Area.EditMaxZ) or not(a_Area.EditMinZ)
	) then
		return true
	end

	-- Inverted min / max edit range is suspicious
	if (
		(a_Area.EditMaxX < a_Area.EditMinX) or
		(a_Area.EditMaxY < a_Area.EditMinY) or
		(a_Area.EditMaxZ < a_Area.EditMinZ)
	) then
		return true
	end

	-- Out-of-bounds min / max edit range is suspicious:
	local gal = a_Area.Gallery
	if (
		(a_Area.EditMinX < 0) or (a_Area.EditMaxX >= gal.AreaSizeX - 2 * gal.AreaEdge) or
		(a_Area.EditMinY < 0) or (a_Area.EditMaxY >= 255) or
		(a_Area.EditMinZ < 0) or (a_Area.EditMaxZ >= gal.AreaSizeZ - 2 * gal.AreaEdge)
	) then
		return true
	end

	-- Nothing suspicious, no need to fix stats:
	return false
end





function HandleConsoleCmdCheckIndices(a_Split, a_EntireCommand)
	-- Check params:
	local shouldForce = false
	for _, v in ipairs(a_Split) do
		if (v == "-force") then
			shouldForce = true
		end
	end

	-- If there are any players connected, refuse to process unless forced explicitly:
	if not(shouldForce) then
		if (cRoot:Get():GetServer():GetNumPlayers() ~= 0) then
			return true, "Cannot check indices, there are players connected to the server. " ..
			"You can use the \"-force\" parameter to force checking despite players being present, " ..
			"but that is not advisable - there's no concurrency protection, your DB could become corrupt."
		end
	end

	-- Check the indices in each gallery:
	for _, gallery in ipairs(g_Galleries) do
		g_DB:CheckAreaIndices(gallery, "<console>")
	end

	return true, "Indices checked"
end





function HandleConsoleCmdFixBlockStats(a_Split, a_EntireCommand)
	-- Check params:
	local shouldForce = false
	local isSingleAreaOp = false
	local singleAreaID = 0
	for _, v in ipairs(a_Split) do
		if (v == "-force") then
			shouldForce = true
		end
		local n = tonumber(v)
		if (n) then
			isSingleAreaOp = true
			singleAreaID = n
		end
	end

	-- If there are any players connected, refuse to process unless forced explicitly:
	if not(shouldForce) then
		if (cRoot:Get():GetServer():GetNumPlayers() ~= 0) then
			return true, "Cannot fix block stats, there are players connected to the server. You can use the \"-force\" parameter to force fixing despite players being present."
		end
	end

	-- Find all areas that need fixing:
	local ToFix
	if (isSingleAreaOp) then
		local area = { g_DB:LoadAreaByID(singleAreaID) }
		if not(area[1]) then
			return true, string.format("Cannot load area ID %d from the DB: %s",
				PLUGIN_PREFIX, singleAreaID, area[2] or "<no message>"
			)
		end
		ToFix = { area[1] }
	else
		local Areas = g_DB:LoadAllAreas()
		ToFix = {}
		for _, area in ipairs(Areas) do
			if (area.Gallery.AreaTemplateSchematic and AreaNeedsFixingStats(area)) then
				table.insert(ToFix, area)
			end
		end
	end

	-- Sort the areas by their X coord first, Z coord second, to put near areas together for chunk sharing:
	table.sort(ToFix,
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

	-- Fix each area that has a nil blockstat, queueing each next area to the world tick thread of the world in which it resides:
	local idx = 1
	local NumToFix = #ToFix
	local FixNextArea
	FixNextArea = function(a_CBWorld)
		-- After each 50 areas log progress and unload the chunks:
		if (idx % 50 == 0) then
			LOG("Fixing block stats for area " .. idx .. " out of " .. NumToFix)
			a_CBWorld:QueueUnloadUnusedChunks()
		end

		-- Fix the area:
		ToFix[idx].Gallery.World:ChunkStay(GetAreaChunkCoords(ToFix[idx]), nil,
			function()
				local area = ToFix[idx]
				local gal = area.Gallery
				local ba = cBlockArea()
				ba:Read(gal.World, area.MinX + gal.AreaEdge, area.MaxX - gal.AreaEdge - 1, 0, 255, area.MinZ + gal.AreaEdge, area.MaxZ - gal.AreaEdge - 1)
				ba:Merge(gal.AreaTemplateSchematic, -gal.AreaEdge, 0, -gal.AreaEdge, cBlockArea.msSimpleCompare)
				area.EditMinX, area.EditMinY, area.EditMinZ, area.EditMaxX, area.EditMaxY, area.EditMaxZ = ba:GetNonAirCropRelCoords()
				if (area.EditMinX > area.EditMaxX) then
					-- The entire area is the same as the template, reset all the coords to "invalid" (min > max):
					area.EditMinX, area.EditMinY, area.EditMinZ = area.EndX - area.StartX, 255, area.EndZ - area.StartZ
					area.EditMaxX, area.EditMaxY, area.EditMaxZ = 0, 0, 0
				end
				area.NumPlacedBlocks = ba:CountNonAirBlocks()
				g_DB:UpdateAreaBlockStatsAndEditRange(area)

				-- Queue the next area:
				idx = idx + 1
				if (ToFix[idx]) then
					ToFix[idx].Gallery.World:QueueTask(FixNextArea)
				else
					LOG("Area block stats fixed")
				end
			end
		)
	end

	if (ToFix[1]) then
		LOG(string.format("%sFixing area block stats... (Number of areas: %d)",
			PLUGIN_PREFIX, #ToFix
		))
		ToFix[1].Gallery.World:QueueTask(FixNextArea)
	end
	return true
end





