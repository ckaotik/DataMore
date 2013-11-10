local addonName, ns = ...

-- GLOBALS: GetCVar, GetQuestResetTime
-- GLOBALS: assert ,format, pairs, string, time, date, tonumber

local initialize -- forward declaration
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
function ns.RegisterOverrides(moduleName, module, publicMethods)
	for methodName, method in pairs(publicMethods) do
		RegisteredOverrides[methodName] = {
			func = method,
			owner = module,
		}
	end
end
function ns.SetCharacterBasedMethod(methodName)
	if RegisteredOverrides[methodName] then
		RegisteredOverrides[methodName].isCharBased = true
	end
end
local origMetatable = getmetatable(DataStore)
local lookupMethods = {
	__index = function(self, key)
		if not RegisteredOverrides[key] then
			return origMetatable.__index(origMetatable, key)
		end

		return function(self, arg1, ...)
			if RegisteredOverrides[key].isCharBased then
				local owner = RegisteredOverrides[key].owner
				local charKey = arg1
				arg1 = owner.Characters[arg1]
				arg1.key = charKey
				if not arg1.lastUpdate then return end
			end
			return RegisteredOverrides[key].func(arg1, ...)
		end
	end
}
setmetatable(DataStore, lookupMethods)

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
