-- SQLite.lua

-- Implements a SQLite class representing a DB in a SQLite file
-- Implements several helper functions for the DB object, such as ExecuteStatement() and CreateDBTable()
--[[
Usage:
  To add the helper SQLite functions to any object, call the SQLite_extend() function on the object:

local myObject = {}
SQLite_extend(myObject)
myObject:OpenDB("file.sqlite")
myObject:CreateDBTable(...)
myObject:ExecuteStatement(...)
--]]




local SQLite = {}





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
-- a_Columns is an array of {ColumnName, ColumnType}, WARNING: this function will destroy its contents!
-- Logs any errors and warnings to console
-- Returns true on success, false on error
function SQLite:CreateDBTable(a_TableName, a_Columns)
	-- Check params:
	assert(self)
	assert(self.DB)  -- Did you call Open()?
	assert(self.DBExec)
	assert(a_TableName ~= nil)
	assert(a_Columns ~= nil)
	assert(a_Columns[1])
	assert(a_Columns[1][1])

	-- Try to create the table first
	local ColumnDefs = {}
	for idx, col in ipairs(a_Columns) do
		ColumnDefs[idx] = col[1] .. " " .. (col[2] or "")
	end
	local sql = "CREATE TABLE IF NOT EXISTS '" .. a_TableName .. "' ("
	sql = sql .. table.concat(ColumnDefs, ", ")
	sql = sql .. ")"
	if (not(self:DBExec(sql))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB Table " .. a_TableName)
		return false
	end
	-- SQLite doesn't inform us if it created the table or not, so we have to continue anyway

	-- Add the map of LowerCaseColumnName => {ColumnName, ColumnType} to a_Columns:
	for _, col in ipairs(a_Columns) do
		a_Columns[string.lower(col[1])] = col
	end

	-- Check each column whether it exists
	-- Remove all the existing columns from a_Columns:
	local RemoveExistingColumnFromDef = function(UserData, NumCols, Values, Names)
		-- Remove the received column from a_Columns. Search for column name in the Names[] / Values[] pairs
		for i = 1, NumCols do
			if (Names[i] == "name") then
				local ColumnName = Values[i]:lower()
				-- Search the a_Columns if they have that column:
				for idx, col in ipairs(a_Columns) do
					if (ColumnName == col[1]:lower()) then
						table.remove(a_Columns, idx)
						break
					end
				end  -- for col - a_Columns[]
			end
		end  -- for i - Names[] / Values[]
		return 0
	end
	if (not(self:DBExec("PRAGMA table_info(" .. a_TableName .. ")", RemoveExistingColumnFromDef))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot query DB table structure")
		return false
	end

	-- Create the missing columns
	-- a_Columns now contains only those columns that are missing in the DB
	if (a_Columns[1]) then
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" is missing " .. #a_Columns .. " columns, fixing now.")
		for _, col in ipairs(a_Columns) do
			if (not(self:DBExec("ALTER TABLE '" .. a_TableName .. "' ADD COLUMN " .. col[1] .. " " .. (col[2] or "")))) then
				LOGWARNING(PLUGIN_PREFIX .. "Cannot add DB table \"" .. a_TableName .. "\" column \"" .. col[1] .. "\"")
				return false
			end
		end
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" columns fixed.")
	end

	return true
end






--- Executes an SQL query on the SQLite DB
-- a_Callback is called for each row returned by the query, it receives (a_CallbackParam, numColumns, values,
--   names) as its parameters
-- a_CallbackParam is any value that is then passed to a_Callback
-- Returns true on success, false and optional error code and message on failure
function SQLite:DBExec(a_SQL, a_Callback, a_CallbackParam)
	-- Check params:
	assert(self)
	assert(self.DB)  -- Did you call Open()?
	assert(type(a_SQL) == "string")

	local errCode = self.DB:exec(a_SQL, a_Callback, a_CallbackParam)
	if (errCode ~= sqlite3.OK) then
		return false, errCode, self.DB.errmsg()
	end
	return true
end





--- Executes the SQL statement, substituting "?" in the SQL with the specified params
-- Calls a_Callback for each row
-- The callback receives a dictionary table containing the row values (stmt:nrows())
-- a_Params is an array-table of values that are to be bound into the SQL statement, based on their index
-- a_RowIDCallback is an optional function that is called with the rowid of the last insert operation
-- Returns false and error message on failure (and logs info to console), or true on success
function SQLite:ExecuteStatement(a_SQL, a_Params, a_Callback, a_RowIDCallback)
	-- Check params:
	assert(self)
	assert(self.DB)  -- Did you call Open()?
	assert(a_SQL)
	assert(not(a_Params) or (type(a_Params) == "table"))
	assert(not(a_Callback) or (type(a_Callback) == "function"))
	assert(not(a_RowIDCallback) or (type(a_RowIDCallback) == "function"))

	-- Prepare the statement (SQL-compile):
	local Stmt, ErrCode, ErrMsg = self.DB:prepare(a_SQL)
	if (Stmt == nil) then
		ErrCode = ErrCode or self.DB:errcode()
		ErrMsg = ErrMsg or self.DB:errmsg()
		ErrMsg = (ErrCode or "<unknown>") .. " (" .. (ErrMsg or "<no message>") .. ")"
		LOGWARNING(PLUGIN_PREFIX .. "Cannot prepare SQL \"" .. a_SQL .. "\": " .. ErrMsg)
		LOGWARNING(PLUGIN_PREFIX .. "  Params = {" .. table.concat(a_Params or {}, ", ") .. "}")
		return nil, ErrMsg
	end

	-- Bind the values into the statement:
	if (a_Params) then
		ErrCode = Stmt:bind_values(unpack(a_Params))
		if ((ErrCode ~= sqlite3.OK) and (ErrCode ~= sqlite3.DONE)) then
			ErrMsg = (ErrCode or "<unknown>") .. " (" .. (self.DB:errmsg() or "<no message>") .. ")"
			LOGWARNING(PLUGIN_PREFIX .. "Cannot bind values to statement \"" .. a_SQL .. "\": " .. ErrMsg)
			Stmt:finalize()
			return nil, ErrMsg
		end
	end

	-- Step the statement:
	if not(a_Callback) then
		ErrCode = Stmt:step()
		if ((ErrCode ~= sqlite3.ROW) and (ErrCode ~= sqlite3.DONE)) then
			ErrMsg = (ErrCode or "<unknown>") .. " (" .. (self.DB:errmsg() or "<no message>") .. ")"
			LOGWARNING(PLUGIN_PREFIX .. "Cannot step statement \"" .. a_SQL .. "\": " .. ErrMsg)
			Stmt:finalize()
			return nil, ErrMsg
		end
		if (a_RowIDCallback) then
			a_RowIDCallback(self.DB:last_insert_rowid())
		end
	else
		-- Iterate over all returned rows:
		for v in Stmt:nrows() do
			a_Callback(v)
		end

		if (a_RowIDCallback) then
			a_RowIDCallback(self.DB:last_insert_rowid())
		end
	end
	Stmt:finalize()
	return true
end





--- Opens the specified file as the underlying DB
-- Returns true on success, false and optional error code and message on failure
function SQLite:OpenDB(a_FileName)
	-- Check params:
	assert(self)
	assert(not(self.DB))  -- Already opened?
	assert(type(a_FileName) == "string")

	-- Open the file:
	local DB, errCode, errMsg = sqlite3.open(a_FileName)
	if not(DB) then
		return false, errCode, errMsg
	end

	-- Success, store the DB file handle:
	self.DB = DB
	return true
end





--- Extends the object with the functions defined in this file
-- This practically makes the object a subclass of the SQLite class
function SQLite_extend(a_Object)
	-- Check params:
	assert(type(a_Object) == "table")

	for k, v in pairs(SQLite) do
		assert(not(a_Object[k]))  -- Already has an implementation of our function?
		a_Object[k] = v
	end
end



