
-- API.lua

-- Implements the functions that are considered "External API" callable by other plugins





--- Locks an area specified by the coords
-- Returns true on success, false and error ID and error message on failure
-- a_LockedByName is the name of the player locking the area (for information purposes only)
function LockAreaByCoords(a_WorldName, a_BlockX, a_BlockZ, a_LockedByName)
	-- Check params:
	a_BlockX = tonumber(a_BlockX)
	a_BlockZ = tonumber(a_BlockZ)
	if (
		not(type(a_WorldName) == "string") or
		not(type(a_BlockX) == "number") or
		not(type(a_BlockZ) == "number") or
		not(type(a_LockedByName) == "string")
	) then
		return false, "ParamError", "Invalid parameters. Expected string, number, number and string."
	end
	
	-- Find the appropriate area:
	local Area = g_DB:LoadAreaByPos(a_WorldName, a_BlockX, a_BlockZ)
	if (Area == nil) then
		return false, "NoAreaHere", "There is no gallery area here"
	end
	
	-- If the area is already locked, bail out:
	if (Area.IsLocked) then
		return false, "AlreadyLocked", "This area has already been locked by " .. Area.LockedBy .. " on " .. Area.DateLocked
	end
	
	-- Lock the area:
	g_DB:LockArea(Area, a_LockedByName)
	ReplaceAreaForAllPlayers(Area)
	
	return true
end





--- Unlocks an area specified by the coords
-- Returns true on success, false and error ID and error message on failure
-- a_UnlockedByName is the name of the player unlocking the area (for information purposes only)
function UnlockAreaByCoords(a_WorldName, a_BlockX, a_BlockZ, a_UnlockedByName)
	-- Check params:
	a_BlockX = tonumber(a_BlockX)
	a_BlockZ = tonumber(a_BlockZ)
	if (
		not(type(a_WorldName) == "string") or
		not(type(a_BlockX) == "number") or
		not(type(a_BlockZ) == "number") or
		not(type(a_UnlockedByName) == "string")
	) then
		return false, "ParamError", "Invalid parameters. Expected string, number, number and string."
	end
	
	-- Find the appropriate area:
	local Area = g_DB:LoadAreaByPos(a_WorldName, a_BlockX, a_BlockZ)
	if (Area == nil) then
		return false, "NoAreaHere", "There is no gallery area here"
	end
	
	-- If the area isn't locked, bail out:
	if not(Area.IsLocked) then
		return false, "NotLocked", "This area hasn't been locked."
	end
	
	-- Lock the area:
	g_DB:UnlockArea(Area, a_UnlockedByName)
	ReplaceAreaForAllPlayers(Area)
	
	return true
end




