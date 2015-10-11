
-- SchematicToPng.lua

-- Implements the cSchematicToPng class representing a connection to MCSchematicToPng





local cSchematicToPng = {}





function cSchematicToPng:Connect()
	-- Check params:
	assert(self)
	assert(self.Port)
	
	-- Start the connection:
	cNetwork:Connect("localhost", self.Port,
	{
		OnError = function (a_Link, a_ErrorCode, a_ErrorMsg)
			LOGWARNING(PLUGIN_PREFIX .. "Failed to connect to MCSchematicToPng: " .. (a_ErrorMsg or "<unknown error>"))
			self:Disconnected()
		end,
		OnConnected = function (a_Link)
			self.Link = a_Link
		end,
		OnRemoteClosed = function (a_Link)
			self:Disconnected()
		end,
		OnReceivedData = function (a_Link, a_Data)
			if not(self.Version) then
				-- Receiving the initial handshake - name and version information:
				self.RecvBuffer = (self.RecvBuffer or "") .. a_Data
				local header = self.RecvBuffer:match("[^\n]*\n[^\n]*\n")
				if (header and (header ~= "MCSchematicToPng\n1\n")) then
					LOGWARNING(PLUGIN_PREFIX .. "MCSchematicToPng connection received unknown header: \"" .. header .. "\"")
					a_Link:Close()
					self.Link = nil
					self:Disconnected()
					return
				end
				self.Version = header
				return
			end

			-- Received an error message
			LOGWARNING(PLUGIN_PREFIX .. "Error received from MCSchematicToPng: \"" .. (a_Data or "<no data>") .. "\"")
		end
	})
end





--- Called when the link gets disconnected
-- Resets all internal variables to their defaults, so that reconnection works
function cSchematicToPng:Disconnected()
	assert(self)
	
	self.Link = nil
	self.Version = nil
	self.RecvBuffer = nil
end





function cSchematicToPng:ReconnectIfNeeded()
	assert(self)
	
	if (self.Link) then
		-- The link is valid, no reconnection needed
		return
	end
	
	-- The link is not valid, try to reconnect:
	self:Connect()
end





function cSchematicToPng:Write(a_Data)
	if not(self.Link) then
		return
	end
	self.Link:Send(a_Data)
end





function SchematicToPng_new(a_Port)
	cSchematicToPng.Port = a_Port
	cSchematicToPng:Connect()
	return cSchematicToPng
end




