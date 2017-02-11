-- AreaPreview.lua

-- Implements the AreaPreview class providing area previews for webadmin

--[[
The webadmin handlers use this class to request images of the areas. This class uses a network connection to
MCSchematicToPng to generate the images, and stores them in the Storage DB as a cache. Since the webadmin
needs to finish the request as soon as possible (no async), if an image doesn't exist, nil is returned; and
if an image is stale, it is still returned (and a refresh is scheduled). An additional periodic task is used
to schedule image refresh for existing out-of-date images.

Usage:
Call InitAreaPreview(a_Config) to create a new object of the AreaPreview class, then use its functions to
query previews. Note that the preview generator works in an asynchronous way, call RefreshPreview() to
schedule a refresh and GetPreview() to retrieve the PNG image; if GetPreview fails, check back later if the
image has been generated. No completion callbacks are currently provided.

local areaPreview = InitAreaPreview(config)
areaPreview:RefreshPreview(areaID, numRotations)
...
local pngImage = areaPreview:GetPreview(areaID, numRotations)
if not(pngImage) then
	-- No preview available yet, check back later
else
	-- Use the image in pngImage
end
--]]





local AreaPreview =
{
	m_RenderQueue = {},            -- Queued requests for rendering, to be sent once the MCSchematicToPng connection is established
	m_IsFullyConnected = false,    -- True iff MCSchematicToPng connection has been fully established (can send requests)
	m_LastWorld = nil,             -- The cWorld object of the last export (used for partial cleanup)
	m_LastGalleryName = "",        -- The name of the last export area's gallery (used for partial cleanup)
	m_NumExported = 0,             -- Number of exported previews (used for partial cleanup)
	m_HostName = "localhost",      -- Hostname where to connect to the MCSchematicToPng jsonnet service
	m_Port = 9999,                 -- Port where to connect to the MCSchematicToPng jsonnet service
	m_Link = nil,                  -- When connected to MCSchematicToPng, contains the cTCPLink for the connection
	m_IncomingData = "",           -- Buffer for the data incoming on m_Link, before being parsed
	m_PendingRenderCommands = {},  -- The render commands that have been sent to MCSchematicToPng, but not finished yet
	m_NextCmdID = 0,               -- The CmdID to be used for the next command
}

AreaPreview.__index = AreaPreview


--- Class used for the AreaPreview's m_DB member, providing (and hiding) DB access
local AreaPreviewDB = {}





-- If assigned to an open file, the comm to MCSchematicToPng will be written to it
local g_LogFile = nil  -- io.open("MCSchematicToPng-comm.log", "wb")





--- Returns the chunk coords of chunks that intersect the given area's export cuboid
-- The returned value has the form of { {Chunk1x, Chunk1z}, {Chunk2x, Chunk2z}, ...}
local function GetAreaChunkCoords(a_Area)
	assert(type(a_Area) == "table")
	local MinChunkX = math.floor(a_Area.StartX / 16)
	local MinChunkZ = math.floor(a_Area.StartZ / 16)
	local MaxChunkX = math.floor((a_Area.EndX + 15) / 16)
	local MaxChunkZ = math.floor((a_Area.EndZ + 15) / 16)
	local res = {}
	for z = MinChunkZ, MaxChunkZ do
		for x = MinChunkX, MaxChunkX do
			table.insert(res, {x, z})
		end
	end
	assert(res[1])  -- Check that at least one chunk coord pair is being returned
	return res
end





--- Returns the 6 coords for the area's bounds for export
-- MinX, MaxX, MinY, MaxY, MinZ, MaxZ
-- The returned coords are in world coordinates
local function GetAreaExportCoords(a_Area)
	-- a_Area's ExportMinX and StartX are world-coords, while EditMinX is relative-to-StartX, so we need to unify.
	-- EditMaxX is still relative to StartX, therefore the min / max processing is different.

	-- MinX:
	local minX = a_Area.ExportMinX
	if not(minX) then
		minX = a_Area.StartX + (a_Area.EditMinX or 0)
	end

	-- MaxX:
	local maxX = a_Area.ExportMaxX
	if not(maxX) then
		if (a_Area.EditMaxX) then
			maxX = a_Area.StartX + a_Area.EditMaxX
		else
			maxX = a_Area.EndX
		end
	end

	-- MinZ:
	local minZ = a_Area.ExportMinZ
	if not(minZ) then
		minZ = a_Area.StartZ + (a_Area.EditMinZ or 0)
	end

	-- MaxX:
	local maxZ = a_Area.ExportMaxZ
	if not(maxZ) then
		if (a_Area.EditMaxZ) then
			maxZ = a_Area.StartZ + a_Area.EditMaxZ
		else
			maxZ = a_Area.EndZ
		end
	end

	return
		minX, maxX,
		a_Area.ExportMinY or a_Area.EditMinY or 0,
		a_Area.ExportMaxY or a_Area.EditMaxY or 255,
		minZ, maxZ
end





--------------------------------------------------------------------------------
-- AreaPreview:

--- Starts the connection to MCSchematicToPng
function AreaPreview:Connect()
	-- Check params:
	assert(self)
	assert(self.m_HostName)
	assert(self.m_Port)
	assert(not(self.m_Link))

	-- Start the connection:
	cNetwork:Connect(self.m_HostName, self.m_Port,
	{
		OnError = function (a_Link, a_ErrorCode, a_ErrorMsg)
			LOGWARNING(PLUGIN_PREFIX .. "Error in connection to MCSchematicToPng (" .. self.HostName .. ":" .. self.Port .. "): " .. (a_ErrorMsg or "<unknown error>"))
			self:Disconnected()
		end,
		OnRemoteClosed = function (a_Link)
			self:Disconnected()
		end,
		OnReceivedData = function (a_Link, a_Data)
			self.m_Link = a_Link
			self:ProcessIncomingData(a_Data)
		end
	})
end





--- Called when the connection to MCSchematicToPng is disconnected.
-- Resets all internal variables to their defaults, so that reconnection works
function AreaPreview:Disconnected()
	-- Check params:
	assert(self)

	-- Reset link-related state:
	self.m_Link = nil
	self.m_IncomingData = ""
	self.m_IsFullyConnected = false

	-- Move m_PendingRenderCommands back into the m_RenderQueue:
	for _, cmd in pairs(self.m_PendingRenderCommands) do
		cmd.CmdID = nil  -- Reset the Command ID
		table.insert(self.m_RenderQueue, cmd)
	end
	self.m_PendingRenderCommands = {}
end





--- Retrieves the DB area description
-- a_DBAreaOrID is either the DB area (in which case this function just returns it) or the ID of a DB area
-- Returns the DB area description on success, or nil and optional error message on failure
function AreaPreview:GetDBArea(a_DBAreaOrID)
	-- Check params:
	assert(self)
	assert((type(a_DBAreaOrID) == "table") or (type(a_DBAreaOrID) == "number"))

	if (type(a_DBAreaOrID) == "table") then
		-- Assume this is the DB area. Check that it has some of the members normally associated with an area:
		if (
			a_DBAreaOrID.ID and
			a_DBAreaOrID.WorldName and
			a_DBAreaOrID.MinX and
			a_DBAreaOrID.GalleryName
		) then
			return a_DBAreaOrID
		end
		return nil, "GetDBArea() was given a table that doesn't look like a DB area"
	end

	-- We were given a number, consider it a DB area ID and load the area description from the DB:
	return g_DB:LoadAreaByID(a_DBAreaOrID)
end





--- Returns an unused CmdID for a new command
function AreaPreview:GetNextCmdID()
	-- Check params:
	assert(self)

	local cmdID = self.m_NextCmdID or 0
	self.m_NextCmdID = cmdID + 1
	return cmdID
end





--- Returns a preview for the specified area
-- a_DBAreaOrID is the table describing the area, or a single number - the area's ID
-- a_NumRotations is the number specifying the number of rotations
-- Returns the PNG data as a string, with optional second value "true" if the image is outdated
-- Returns nil and an optional error msg on failure
-- If the image is missing or outdated, automatically schedules a refresh
function AreaPreview:GetPreview(a_DBAreaOrID, a_NumRotations)
	-- Check params:
	assert(self)
	assert((type(a_DBAreaOrID) == "table") or (type(a_DBAreaOrID) == "number"))
	assert(type(a_NumRotations) == "number")

	-- If the area is specified using an ID, retrieve the whole DB area table:
	local area = self:GetDBArea(a_DBAreaOrID)
	if not(area) then
		return nil, "Invalid area ID"
	end

	-- Retrieve the PNG data from the DB:
	local imgRec, msg = self.m_DB:GetAreaPreview(area.ID, a_NumRotations)
	if not(imgRec) then
		self:RefreshPreview(area, a_NumRotations)
		return nil, "Failed to retrieve PNG image from the DB: " .. (msg or "<no message>")
	end

	-- If the image is outdated, schedule a refresh:
	if (area.TickLastChanged > imgRec.TickExported) then
		self:RefreshPreview(area,a_NumRotations)
		return imgRec.PngData, true
	end

	-- Image is up to date:
	return imgRec.PngData
end





--- Processes a reply to a previously sent command incoming from the network connection
-- a_CmdReply is the command reply parsed into a table
function AreaPreview:ProcessIncomingCmdReply(a_CmdReply)
	-- Check params:
	assert(self)
	assert(type(a_CmdReply) == "table")

	-- Find the command:
	local cmdID = a_CmdReply.CmdID
	if not(cmdID) then
		LOG(PLUGIN_PREFIX .. "MCSchematicToPng connection received a cmd reply without CmdID; ignoring message.")
		return
	end
	if (cmdID == "SetNameCmdID") then
		-- Ignore this response, it was the SetName command
		return
	end
	local cmd = self.m_PendingRenderCommands[cmdID]
	if not(cmd) then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with an invalid CmdID %q; ignoring message.",
			PLUGIN_PREFIX, cmdID
		))
		return
	end
	self.m_PendingRenderCommands[cmdID] = nil

	-- Check the command status:
	local status = a_CmdReply.Status
	if (status == "error") then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with an error for CmdID %q: %s",
			PLUGIN_PREFIX, cmdID, a_CmdReply.ErrorText or "[no message]"
		))
		return
	end
	if (status ~= "ok") then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with an unknown status %q for CmdID %q: %s",
			PLUGIN_PREFIX, tostring(status), cmdID, a_CmdReply.ErrorText or "[no message]"
		))
		return
	end

	-- Store the image data into DB:
	if not(a_CmdReply.PngData) then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with no PNG data for CmdID %q",
			PLUGIN_PREFIX, cmdID
		))
		return
	end
	local pngData = Base64Decode(a_CmdReply.PngData)
	self.m_DB:SetAreaPreview(cmd.AreaID, cmd.NumCWRotations, cmd.TickExported, pngData)
end





--- Processes the data incoming from the network connection
function AreaPreview:ProcessIncomingData(a_Data)
	-- Check params:
	assert(self)
	assert(type(a_Data) == "string")

	-- Log the incoming data to the logfile:
	if (g_LogFile) then
		g_LogFile:write("Incoming data (", string.len(a_Data), " bytes):\n", a_Data, "\n\n")
	end

	-- Split data on message boundaries
	self.m_IncomingData = self.m_IncomingData .. a_Data
	while (true) do
		local found = self.m_IncomingData:find("\23")
		if not(found) then
			return
		end
		-- Got a full JSON message from the peer, parse, process and remove it from buffer:
		local json, msg = cJson:Parse(self.m_IncomingData:sub(1, found))
		if not(json) then
			LOGWARNING(string.format("%sMCSchematicToPng connection received unparsable data: %s", PLUGIN_PREFIX, msg or "[no message]"))
			self.m_Link:Close()
			self:Disconnected()
			return ""
		end
		self:ProcessIncomingMessage(json)
		self.m_IncomingData = self.m_IncomingData:sub(found + 1)
	end
end





--- Processes a single incoming message from the network connection
function AreaPreview:ProcessIncomingMessage(a_Message)
	-- Check params:
	assert(self)
	assert(type(a_Message) == "table")

	if (self.m_IsFullyConnected) then
		return self:ProcessIncomingCmdReply(a_Message)
	end

	-- Receiving the initial handshake - name and version information:
	if not(a_Message.MCSchematicToPng) then
		LOGWARNING(PLUGIN_PREFIX .. "MCSchematicToPng connection received invalid handshake.")
		self.m_Link:Close()
		self:Disconnected()
	end
	if (tostring(a_Message.MCSchematicToPng) ~= "2") then
		LOGWARNING(string.format("%sMCSchematicToPng connection received unhandled protocol version: %s",
			PLUGIN_PREFIX, tostring(a_Message.MCSchematicToPng))
		)
		self.m_Link:Close()
		self:Disconnected()
	end
	self.m_IsFullyConnected = true
	LOG(string.format("%sMCSchematicToPng connected successfully to %s:%s",
		PLUGIN_PREFIX, self.m_HostName, self.m_Port
	))
	self:SendJson({Cmd = "SetName", Name = "GalExport", CmdID = "SetNameCmdID"})

	-- Send the export requests that have been queued:
	for _, qi in ipairs(self.m_RenderQueue or {}) do
		self:SendRenderCommand(qi)
	end
	self.m_RenderQueue = {}
end





--- Schedules a refresh for the specified area's preview, if the area has changed since the last preview was
-- made (or there's no preview available at all).
-- a_DBAreaOrID is the table describing the area, or a single number - the area's ID
-- a_NumRotations is the number specifying the number of rotations
-- Returns nil and optional error message on failure, true on regeneration success, true and "up-to-date" on
-- success when no regen needed
function AreaPreview:RefreshPreview(a_DBAreaOrID, a_NumRotations)
	-- Check params:
	assert(self)
	assert((type(a_DBAreaOrID) == "table") or (type(a_DBAreaOrID) == "number"))
	assert(type(a_NumRotations) == "number")

	-- If the area is specified using an ID, retrieve the whole DB area table:
	local area = self:GetDBArea(a_DBAreaOrID)
	if not(area) then
		return nil, "Invalid area ID"
	end

	-- Check if the preview image is stale:
	local previewTick, msg = self.m_DB:GetAreaPreviewTickExported(area.ID, a_NumRotations)
	if not(previewTick) then
		return nil, "Failed to query last export's tick from DB: " .. (msg or "<no message>")
	end
	if (previewTick >= area.TickLastChanged) then
		return true, "up-to-date"
	end

	return self:RegeneratePreview(area, a_NumRotations)
end





--- Schedules the specified area's preview to be regenerated.
-- a_DBAreaOrID is the table describing the area, or a single number - the area's ID
-- a_NumRotations is the number specifying the number of rotations
-- Returns true on success, nil and optional error message on failure
function AreaPreview:RegeneratePreview(a_DBAreaOrID, a_NumRotations)
	-- Check params:
	assert(self)
	assert((type(a_DBAreaOrID) == "table") or (type(a_DBAreaOrID) == "number"))
	assert(type(a_NumRotations) == "number")

	-- If the area is specified using an ID, retrieve the whole DB area table:
	local area = self:GetDBArea(a_DBAreaOrID)
	if not(area) then
		return nil, "Invalid area ID"
	end

	-- Prepare the request:
	local request =
	{
		Cmd = "RenderSchematic",
		HorzSize = 6,
		VertSize = 8,
		AreaID = area.ID,
		NumCWRotations = a_NumRotations,
	}

	-- Read the area contents from the world:
	local ba = cBlockArea()
	local world = cRoot:Get():GetWorld(area.WorldName)
	world:QueueTask(
		function ()
			world:ChunkStay(
				GetAreaChunkCoords(area),
				nil,
				function ()  -- OnAllChunksAvailable callback
					-- Read the block data into the Json request:
					ba:Read(world, GetAreaExportCoords(area))
					request.BlockData = Base64Encode(ba:SaveToSchematicString())
					if not(request.BlockData) then
						LOGWARNING(string.format("%sFailed to export block area for web preview: AreaID = %d, NumRotations = %d",
							PLUGIN_PREFIX, area.ID, a_NumRotations
						))
						return
					end
					request.TickExported = world:GetWorldAge()

					-- Send the MCSchematicToPng Json request:
					if (self.m_IsFullyConnected) then
						self:SendRenderCommand(request)
					else
						table.insert(self.m_RenderQueue, request)
						self:Connect()
					end

					-- Partial cleanup:
					if (
						(self.m_LastWorld ~= world) or                  -- If exporting in another world than the previous export
						(self.m_LastGalleryName ~= area.GalleryName) or -- If exporting from a different gallery than the previous export
						(self.m_NumExported % 10 == 0)                  -- At regular intervals
					) then
						if (self.m_LastWorld) then
							self.m_LastWorld:QueueUnloadUnusedChunks()
						end
						self.m_LastWorld = world
					end
				end  -- OnAllChunksAvailable callback
			)  -- ChunkStay
		end  -- Task callback
	)
	return true
end





--- Sends the given table as a JSON message to the connected MCSchematicToPng
-- a_JsonTable is a table that will be serialized and sent over the network connection
function AreaPreview:SendJson(a_JsonTable)
	-- Check params and preconditions:
	assert(self)
	assert(self.m_Link)

	local json = cJson:Serialize(a_JsonTable)

	-- DEBUG: Log into file:
	if (g_LogFile) then
		g_LogFile:write("Sending JSON:\n", json, "\n\n")
	end

	self.m_Link:Send(json)
	self.m_Link:Send('\23')
end





--- Sends the specified render command to the connected MCSchematicToPng
-- Assumes that the connection is already established
-- a_QueueItem is a table describing the export request
function AreaPreview:SendRenderCommand(a_RenderCommand)
	-- Check params and preconditions:
	assert(self)
	assert(type(a_RenderCommand) == "table")
	assert(self.m_IsFullyConnected)

	-- Assignd CmdID, add to PendingCommands:
	a_RenderCommand.CmdID = self:GetNextCmdID()
	self.m_PendingRenderCommands[a_RenderCommand.CmdID] = a_RenderCommand

	-- Write to the link:
	self:SendJson(a_RenderCommand)
end





--- Returns the DB row corresponding to the specified area preview description
-- a_AreaID is the ID of the area (in the Areas table)
-- a_NumRotations is the number of CW rotations applied before visualising the area
-- Returns the entire DB row as a key-value table on success, or nil and optional error message on failure
function AreaPreviewDB:GetAreaPreview(a_AreaID, a_NumRotations)
	-- Check params:
	assert(self)
	assert(type(a_AreaID) == "number")
	assert(type(a_NumRotations) == "number")

	local res
	local isSuccess, msg = self:ExecuteStatement(
		"SELECT * FROM AreaPreviews WHERE AreaID = ? AND NumRotations = ?",
		{
			a_AreaID,
			a_NumRotations,
		},
		function(a_Values)
			res = a_Values
		end
	)
	if not(isSuccess) then
		return nil, msg
	end

	return res
end





--- Returns the TickExported value for the specified area preview description
-- a_AreaID is the ID of the area (in the Areas table)
-- a_NumRotations is the number of CW rotations applied before visualising the area
-- Returns the TickExported value from the DB on success, -1 if there's no such preview in the DB,
-- nil and error message on failure
function AreaPreviewDB:GetAreaPreviewTickExported(a_AreaID, a_NumRotations)
	-- Check params:
	assert(self)
	assert(type(a_AreaID) == "number")
	assert(type(a_NumRotations) == "number")

	local res = -1
	local isSuccess, msg = self:ExecuteStatement(
		"SELECT TickExported FROM AreaPreviews WHERE AreaID = ? AND NumRotations = ?",
		{
			a_AreaID,
			a_NumRotations,
		},
		function(a_Values)
			res = a_Values.TickExported
		end
	)
	if not(isSuccess) then
		return nil, msg
	end

	return res
end





--- Stores the preview for the specified area into the DB
-- a_AreaID is the ID of the area (in the Areas table)
-- a_NumRotations is the number of CW rotations applied before visualising the area
-- a_TickExported is the age of the area's world, in ticks, when the area was exported
-- a_PngData is the raw PNG image data (string)
-- Returns true on success, nil and optional error message on failure
function AreaPreviewDB:SetAreaPreview(a_AreaID, a_NumRotations, a_TickExported, a_PngData)
	-- Check params:
	assert(self)
	assert(type(a_AreaID) == "number")
	assert(type(a_NumRotations) == "number")
	assert(type(a_TickExported) == "number")
	assert(type(a_PngData) == "string")

	-- Delete any previous image (ignore errors):
	self:ExecuteStatement(
		"DELETE FROM AreaPreviews WHERE AreaID = ? AND NumRotations = ?",
		{
			a_AreaID, a_NumRotations
		}
	)

	-- Store new image:
	return self:ExecuteStatement(
		"INSERT INTO AreaPreviews (AreaID, NumRotations, TickExported, PngData) VALUES (?, ?, ?, ?)",
		{
			a_AreaID, a_NumRotations, a_TickExported, a_PngData
		}
	)
end





--- Creates a new AreaPreview object based on the specified config
-- a_MCSchematicToPngConfig is a table from which the HostName and Port members are used (default: "localhost:9999")
-- Returns a AreaPreview object
function InitAreaPreview(a_MCSchematicToPngConfig)
	-- Check params:
	assert(type(a_MCSchematicToPngConfig) == "table")

	-- Create the object and extend it with and AreaPreview functions:
	local res = {}
	for k, v in pairs(AreaPreview) do
		assert(not(res[k]))  -- Has an implementation with a duplicate name?
		res[k] = v
	end

	-- Create the DB member object:
	res.m_DB = {}
	SQLite_extend(res.m_DB)
	for k, v in pairs(AreaPreviewDB) do
		assert(not(res.m_DB[k]))  -- Has an implementation with a duplicate name?
		res.m_DB[k] = v
	end

	-- Open the DB file:
	local isSuccess, errCode, errMsg = res.m_DB:OpenDB("GalleryPreviews.sqlite")
	if not(isSuccess) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open the Previews database: " .. (errCode or "<no errCode>") .. ", " .. (errMsg or "<no message>"))
		error(errMsg or "<no message>")  -- Abort the plugin
	end

	-- Create the DB tables and columns, if not already present:
	local AreaPreviewsColumns =
	{
		{"AreaID",       "INTEGER"},
		{"NumRotations", "INTEGER"},
		{"PngData",      "BLOB"},     -- The PNG image binary data
		{"TickExported", "INTEGER"},  -- The world tick on which the preview data was exported
	}
	if (not(res.m_DB:CreateDBTable("AreaPreviews", AreaPreviewsColumns))) then
		error("Cannot create AreaPreviews DB table")
	end


	-- Connect to MCSchematicToPng's jsonnet service:
	res.m_HostName = tostring(a_MCSchematicToPngConfig.HostName) or "localhost"
	res.m_Port = tonumber(a_MCSchematicToPngConfig.Port) or 9999
	res.m_RenderQueue = {}
	res.m_PendingRenderCommands = {}
	res.m_IncomingData = ""
	res:Connect()

	return res
end




