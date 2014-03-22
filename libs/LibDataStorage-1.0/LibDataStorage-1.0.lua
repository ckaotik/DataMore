--[[
TODO: License & explain stuff ...
--]]

local MAJOR, MINOR = 'LibDataStorage-1.0', 1
assert(LibStub, MAJOR..' requires LibStub')
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local LibItemUpgrade = LibStub('LibItemUpgradeInfo-1.0', true)

local sub, gsub, trim, find, strrep = string.sub, string.gsub, string.trim, string.find, string.rep
local bor = bit.bor
local tinsert = table.insert
local assert, type, tonumber = assert, type, tonumber

--[[--  items  --]]--
-- compression idea: remove unnecessary link information while maintaining all data
local function GetShortItemLink(itemLink)
	local itemString = itemLink and itemLink:lower():match('(item:[^\124]+)')
	if not itemLink or not itemString then return itemLink end

	-- @see http://wowpedia.org/ItemString
	-- item:itemId:enchantId:jewelId1:jewelId2:jewelId3:jewelId4:suffixId:uniqueId:linkLevel:reforgeId:upgradeId
	-- we're removing the item's uniqueId and linkLevel
	local data = gsub(itemString, '^item:([^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:)[^:]+:[^:]+(.+)$', '%10:0%2')

	-- TODO: decide if we want to do this, since it effects tooltip display ingame
	if LibItemUpgrade then
		local upgradeID = LibItemUpgrade:GetUpgradeID(itemString)
		local upgraded = upgradeID and LibItemUpgrade:GetCurrentUpgrade(upgradeID)

		if upgraded == 0 then
			-- this item has not been upgraded, we can remove upgrade info, too
			data = gsub(data, '^('..strrep('[^:]+:', 10)..')[^:]+', '%10')
		end
	end

	-- remove empty trailing attributes
	data = trim(data, '\t\r\n:0') -- we assume here, that itemID will never be 0
	if not find(data, ':') then
		data = tonumber(data)
	end

	return data
end

-- item:itemID|itemString|itemLink [, storage:table] [, key:string]
-- if no storage is supplied, will only return storable value
function lib:StoreItem(item, storage, key)
	if type(item) == 'string' then
		-- this is an itemLink
		item = GetShortItemLink(item)
	end
	if storage and key then
		storage[key] = item
	elseif storage then
		tinsert(storage, item)
	end
	return item
end

function lib:RetrieveItem(storage, key)
	assert(storage, 'Usage: lib:RetrieveItem(storage[, key])')
	local data = storage
	if type(data) == 'table' then
		data = key and storage[key] or nil
	end
	if data then
		data = 'item:' .. data
	end
	return data
end

--[[-- strings --]]--
-- compression idea: join multiple strings together using smart separator
-- storage:StoreStrings(index, ...)

--[[-- numbers --]]--
-- compression idea: change to different base?
-- storage:StoreNumber(value)

--[[-- bits --]]--
function lib:StoreBit(index, value, storage, key)
	local oldValue = 0
	if storage and type(storage) == 'table' and key then
		oldValue = storage[key]
	elseif storage then
		if type(storage) == 'string' then
			oldValue = tonumber(storage) or 0
		else
			oldValue = storage
		end
	end

	-- convert value to 0/1
	value = (not value or value == 0 or value == '0') and 0 or 1

	-- TODO: FIXME: is this true? what if it was previously 1 and now 0?
	-- local newValue = bor(oldValue, value)
	-- bOr((history[index] or 0), 2^bitPos)	-- read: value = SetBit(value, bitPosition)
end

--[[
local function TestBit(value, pos)
   local mask = 2^pos
   if bAnd(value, mask) == mask then
      return true
   end
end

--]]
