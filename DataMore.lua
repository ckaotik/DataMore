local addonName, ns = ...

-- GLOBALS: GetCVar, GetQuestResetTime
-- GLOBALS: assert ,format, pairs, string, time, date, tonumber

local initialize = function()
	-- expose this addon
	_G[addonName] = ns
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
ns.events = frame

function ns.RegisterEvent(event, callback, id, silentFail)
	assert(callback and event and id, format("Usage: RegisterEvent(event, callback, id[, silentFail])"))
	if not eventHooks[event] then
		eventHooks[event] = {}
		frame:RegisterEvent(event)
	end
	assert(silentFail or not eventHooks[event][id], format("Event %s already registered by id %s.", event, id))

	eventHooks[event][id] = callback
end
function ns.UnregisterEvent(event, id)
	if not eventHooks[event] or not eventHooks[event][id] then return end
	eventHooks[event][id] = nil
	if ns.Count(eventHooks[event]) < 1 then
		eventHooks[event] = nil
		frame:UnregisterEvent(event)
	end
end

-- ========================================================
--  Overriding some existing modules
-- ========================================================
local RegisteredOverrides = {}
-- allows overriding DataStore methods
function ns.RegisterOverride(module, methodName, method, methodType)
	RegisteredOverrides[methodName] = {
		func  = method,
		owner = module,
		isCharBased  = methodType and methodType == 'character',
		isGuildBased = methodType and methodType == 'guild',
	}
end
function ns.SetOverrideType(methodName, methodType)
	local override = RegisteredOverrides[methodName]
	assert(override, 'No method registered to name "'..methodName..'"')
	override.isCharBased = methodType == 'character'
	override.isGuildBased = methodType == 'guild'
end
-- returns (by reference!) method and module of override, nil if no such override exists
function ns.GetOverride(methodName)
	local override = RegisteredOverrides[methodName]
	if override then
		return override.func, override.owner
	end
end
function ns.IsAvailable(methodName)
	if ns.GetOverride(methodName) then
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

		local owner = RegisteredOverrides[methodName].owner
		-- we'll provide module's data table but add in the originally requested key

		return function(self, arg1, ...)
			local dataTable
			if owner.isCharBased then
				dataTable = owner.Characters[arg1]
				dataTable.key = arg1
				if not dataTable.lastUpdate then return end
			elseif owner.isGuildBased then
				dataTable = owner.Guilds[arg1]
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
function ns.GetLastMaintenance()
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
function ns.GetNextMaintenance()
	if nextMaintenance then
		return nextMaintenance
	else
		local lastMaintenance = ns.GetLastMaintenance()
		if lastMaintenance then
			nextMaintenance = lastMaintenance + 7*24*60*60
		end
	end
	return nextMaintenance
end
