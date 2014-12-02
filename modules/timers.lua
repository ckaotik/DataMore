local addonName, addon = ...
local timers = addon:NewModule('Timers', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore, C_Garrison
-- GLOBALS: wipe, pairs, ipairs, next, strsplit, strjoin, time

local defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				Item = {},
				Spell = {}, -- crafting, toys
				Garrison = {
					Shipments = {},
					Buildings = {},
					Missions = {},
				},
				-- Calendar = {},
			}
		}
	},
}

local function SingularPluralPattern(singular, plural)
	return singular:gsub('(.)', '%1?') .. plural:gsub('(.)', '%1?')
end
local function GlobalStringToPattern(str)
	local result = str:gsub('\1244(.-):(.-);', SingularPluralPattern)
	result = result:gsub('([%(%)])', '%%%1'):gsub('%%%d?$?c', '(.+)'):gsub('%%%d?$?s', '(.+)'):gsub('%%%d?$?d', '(%%d+)')
	return result
end
local DAY, DAYHOUR, HOUR, HOURMIN, MIN, SEC =
	GlobalStringToPattern(_G.GARRISON_DURATION_DAYS),
	GlobalStringToPattern(_G.GARRISON_DURATION_DAYS_HOURS),
	GlobalStringToPattern(_G.GARRISON_DURATION_HOURS),
	GlobalStringToPattern(_G.GARRISON_DURATION_HOURS_MINUTES),
	GlobalStringToPattern(_G.GARRISON_DURATION_MINUTES),
	GlobalStringToPattern(_G.GARRISON_DURATION_SECONDS)
local function ParseTimeString(timeString)
	local seconds = timeString:match('^'..SEC..'$')
	if not seconds then
		local hours, minutes = timeString:match('^'..HOURMIN..'$')
		if not hours then hours = timeString:match('^'..HOUR..'$') end
		if not hours then minutes = timeString:match('^'..MIN..'$') end
		if hours or minutes then
			seconds = 60*60 * (hours or 0) + 60 * (minutes or 0)
		else
			local days, hours = timeString:match('^'..DAYHOUR..'$')
			if not days then days = timeString:match('^'..DAY..'$') end
			seconds = 60*60*24 * (days or 0) + 60*60 * (hours or 0)
		end
	end
	return seconds
end

local function ScanGarrisonStatus()
	local character = timers.ThisCharacter

	wipe(character.Garrison.Shipments)
	wipe(character.Garrison.Buildings)
	-- Note: get info on buildings using C_Garrison.GetBuildingInfo(buildingID)
	for index, building in ipairs(C_Garrison.GetBuildings()) do
		-- work orders
		local name, texture, maxOrders, numReady, numActive, timeStarted, duration, _, _, _, _, itemID = C_Garrison.GetLandingPageShipmentInfo(building.buildingID)
		if maxOrders and maxOrders > 0 then
			local nextBatch = timeStarted and (timeStarted + duration) or 0
			character.Garrison.Shipments[building.buildingID] = strjoin('|', nextBatch, numActive or 0, numReady or 0, maxOrders, itemID or '')
		end

		-- buildings in progress
		local _, name, texPrefix, texture, description, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, inProgress, timeStarted, duration = C_Garrison.GetOwnedBuildingInfo(building.plotID)
		if inProgress then
			character.Garrison.Buildings[building.buildingID] = timeStarted + duration
		end
	end

	-- TODO: rewrite to store correct timestamp
	-- [[
	local missions = character.Garrison.Missions
	local now = time()
	-- flag old missions
	for missionID, expires in pairs(missions) do
		missions[missionID] = expires > now and -1 * expires or nil
	end
	-- now update/add currently active missions
	for index, mission in ipairs(C_Garrison.GetInProgressMissions()) do
		if missions[mission.missionID] then
			-- mission is known, remove flag but don't touch expiry
			missions[mission.missionID] = -1 * missions[mission.missionID]
		else
			-- new mission
			local seconds = ParseTimeString(mission.timeLeft)
			if seconds and seconds/mission.durationSeconds >= 0.95 then
				-- mission was just accepted
				missions[mission.missionID] = now + mission.durationSeconds
			else
				-- mission was accepted while addon was not present
				missions[mission.missionID] = now + seconds
			end
		end
	end
	-- remove expired missions
	for missionID, expires in pairs(missions) do
		if expires < 0 then
			missions[missionID] = nil
		end
	end
	--]]
	--[[ wipe(character.Garrison.Missions)
	-- Note: get info on missions using C_Garrison.GetBasicMissionInfo(missionID)
	for index, mission in ipairs(C_Garrison.GetInProgressMissions()) do
		-- missions
		-- this sucks but we don't have seconds remaining :(
		character.Garrison.Missions[mission.missionID] = time() + ParseTimeString(mission.timeLeft) or 0
	end --]]
	timers.ThisCharacter.lastUpdate = time()
end

local function ScanItemStatus()
	-- TODO: scan equipped item cds + container items
end

local function ScanSpellStatus()
	-- TODO: scan profession cooldowns, toy cooldowns
	-- track cooldowns such as aura:24755, item:39878, item:44717
	-- addon:SendMessage("DATASTORE_ITEM_COOLDOWN_UPDATED", itemID)
end

-- Mixins
function timers.GetGarrisonMissionExpiry(character, missionID)
	local mission = character.Garrison.Missions[missionID]
	return mission
end
function timers.IterateGarrisonMissions(character)
	local missions, missionID = character.Garrison.Missions, nil
	return function()
		missionID = next(missions, missionID)
		return missionID, timers.GetGarrisonMissionExpiry(character, missionID)
	end
end

function timers.GetGarrisonBuildExpiry(character, buildingID)
	local building = character.Garrison.Buildings[buildingID]
	return building
end
function timers.IterateGarrisonBuilds(character)
	local builds, buildingID = character.Garrison.Buildings, nil
	return function()
		buildingID = next(builds, buildingID)
		return buildingID, timers.GetGarrisonBuildExpiry(character, buildingID)
	end
end

function timers.GetGarrisonShipmentInfo(character, buildingID)
	local shipment = character.Garrison.Shipments[buildingID]
	if shipment then
		local nextBatch, numActive, numReady, maxOrders, itemID = strsplit('|', shipment)
		return nextBatch*1, numActive*1, numReady*1, maxOrders*1, itemID
	end
end
function timers.IterateGarrisonShipments(character)
	local missions, buildingID = character.Garrison.Shipments, nil
	return function()
		buildingID = next(missions, buildingID)
		return buildingID, timers.GetGarrisonShipmentInfo(character, buildingID)
	end
end

-- Setup
local PublicMethods = {
	-- Garrisons
	GetGarrisonMissionExpiry = timers.GetGarrisonMissionExpiry,
	IterateGarrisonMissions  = timers.IterateGarrisonMissions,
	GetGarrisonBuildExpiry   = timers.GetGarrisonBuildExpiry,
	IterateGarrisonBuilds    = timers.IterateGarrisonBuilds,
	GetGarrisonShipmentInfo  = timers.GetGarrisonShipmentInfo,
	IterateGarrisonShipments = timers.IterateGarrisonShipments,
}

function timers:OnEnable()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end

	self:RegisterEvent('GARRISON_LANDINGPAGE_SHIPMENTS', ScanGarrisonStatus)
	self:RegisterEvent('GARRISON_MISSION_LIST_UPDATE', ScanGarrisonStatus)
	self:RegisterEvent('GARRISON_BUILDING_PLACED', ScanGarrisonStatus)
	hooksecurefunc(C_Garrison, 'RequestShipmentInfo', ScanGarrisonStatus)
	hooksecurefunc(C_Garrison, 'RequestLandingPageShipmentInfo', ScanGarrisonStatus)
	hooksecurefunc(C_Garrison, 'RequestShipmentCreation', ScanGarrisonStatus)
	C_Garrison.RequestLandingPageShipmentInfo() -- will also trigger a scan
	-- TODO: there is currently no way to notice when a shipment has been collected
	-- self:RegisterEvent('VIGNETTE_REMOVED') -- for resource cache
	self:RegisterEvent('ITEM_PUSH', function(event, count, icon)
		if not C_Garrison.IsOnGarrisonMap() then return end
		ScanGarrisonStatus()
	end)
end

function timers:OnDisable()
	self:UnregisterEvent('GARRISON_MISSION_STARTED')
	self:UnregisterEvent('GARRISON_BUILDING_PLACED')
	self:UnregisterEvent('ITEM_PUSH')
end
