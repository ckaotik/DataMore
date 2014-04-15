local addonName, addon = ...

-- GLOBALS: GetCVar, GetQuestResetTime
-- GLOBALS: assert ,format, pairs, string, time, date, tonumber
LibStub('AceAddon-3.0'):NewAddon(addon, addonName)

local initialize = function()
	-- expose this addon
	-- _G[addonName] = addon
end

local frame, eventHooks = CreateFrame("Frame"), {}
local function eventHandler(frame, event, arg1, ...)
	if event == 'ADDON_LOADED' and arg1 == addonName then
		-- make sure core initializes before anyone else
		initialize()
	end

	if eventHooks[event] then
		for id, listener in pairs(eventHooks[event]) do
			listener(frame, event, arg1, ...)
		end
	end
end
frame:SetScript("OnEvent", eventHandler)
addon.events = frame

-- TODO: replace with AceEvent
function addon.RegisterEvent(event, callback, id, silentFail)
	assert(callback and event and id, format("Usage: RegisterEvent(event, callback, id[, silentFail])"))
	if not eventHooks[event] then
		eventHooks[event] = {}
		frame:RegisterEvent(event)
	end
	assert(silentFail or not eventHooks[event][id], format("Event %s already registered by id %s.", event, id))

	eventHooks[event][id] = callback
end
function addon.UnregisterEvent(event, id)
	if not eventHooks[event] or not eventHooks[event][id] then return end
	eventHooks[event][id] = nil
	if addon.Count(eventHooks[event]) < 1 then
		eventHooks[event] = nil
		frame:UnregisterEvent(event)
	end
end

-- ========================================================
--  Overriding some existing modules
-- ========================================================
local RegisteredOverrides = {}
-- allows overriding DataStore methods
function addon.RegisterOverride(module, methodName, method, methodType)
	RegisteredOverrides[methodName] = {
		func  = method,
		owner = module,
		isCharBased  = methodType and methodType == 'character',
		isGuildBased = methodType and methodType == 'guild',
	}
end
function addon.SetOverrideType(methodName, methodType)
	local override = RegisteredOverrides[methodName]
	assert(override, 'No method registered to name "'..methodName..'"')
	override.isCharBased = methodType == 'character'
	override.isGuildBased = methodType == 'guild'
end
-- returns (by reference!) method and module of override, nil if no such override exists
function addon.GetOverride(methodName)
	local override = RegisteredOverrides[methodName]
	if override then
		return override.func, override.owner
	end
end
function addon.IsAvailable(methodName)
	if addon.GetOverride(methodName) then
		return true
	end
	-- TODO:
end

local origMetatable = getmetatable(_G.DataStore)
local lookupMethods = {
	__index = function(self, methodName)
		if not RegisteredOverrides[methodName] then
			return origMetatable.__index(origMetatable, methodName)
		end

		return function(self, arg1, ...)
			local dataTable
			local method = RegisteredOverrides[methodName]
			-- we'll provide module's data table but add in the originally requested key

			if method.isCharBased then
				dataTable = method.owner.Characters[arg1]
				dataTable.key = arg1
				if not dataTable.lastUpdate then return end
			elseif method.isGuildBased then
				dataTable = method.owner.Guilds[arg1]
				dataTable.key = arg1
				if not dataTable then return end
			end
			return RegisteredOverrides[methodName].func(dataTable or arg1, ...)
		end
	end
}
-- this is where we actually touch DataStore's internals
setmetatable(_G.DataStore, lookupMethods)

-- ========================================================
--  Functions required by modules
-- ========================================================
local lastMaintenance, nextMaintenance
function addon.GetLastMaintenance()
	if not lastMaintenance then
		local region = string.lower( GetCVar('portal') or '' )
		local maintenanceWeekDay = (region == 'us' and 2) -- tuesday
			or (region == 'eu' and 3) -- wednesday
			or (region == 'kr' and 4) -- ?
			or (region == 'tw' and 4) -- ?
			or (region == 'cn' and 4) -- ?
			or 2

		-- this gives us the time a reset happens, though GetQuestResetTime might not be available at launch
		local dailyReset = time() + GetQuestResetTime()
		if dailyReset == 0 then return end

		local dailyResetWeekday = tonumber(date('%w', dailyReset))
		        lastMaintenance = dailyReset - ((dailyResetWeekday - maintenanceWeekDay)%7) * 24*60*60
		if lastMaintenance == dailyReset then
			lastMaintenance = lastMaintenance - 7*24*60*60
		end
	end
	return lastMaintenance
end
function addon.GetNextMaintenance()
	if nextMaintenance then
		return nextMaintenance
	else
		local lastMaintenance = addon.GetLastMaintenance()
		if lastMaintenance then
			nextMaintenance = lastMaintenance + 7*24*60*60
		end
	end
	return nextMaintenance
end

function addon.GetLinkID(link)
	if not link or type(link) ~= "string" then return end
	local linkType, id = link:match("\124H([^:]+):([^:\124]+)")
	if not linkType then
		linkType, id = link:match("([^:\124]+):([^:\124]+)")
	end
	return tonumber(id), linkType
end
