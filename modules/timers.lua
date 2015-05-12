local addonName, addon = ...
local timers = addon:NewModule('Timers', 'AceEvent-3.0')
-- TODO: garrison components have been moved into garrison.lua

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
					Buildings = {},
					Missions = {},
				},
				-- Calendar = {},
			}
		}
	},
}

-- --------------------------------------------------------
--  Utility functions
-- --------------------------------------------------------
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

-- --------------------------------------------------------
--  Garrison Scanning
-- --------------------------------------------------------
-- Note: get info on buildings using C_Garrison.GetBuildingInfo(buildingID)
local function ScanGarrisonBuildings()
	local buildings = timers.ThisCharacter.Garrison.Buildings
	wipe(buildings)
	for index, building in ipairs(C_Garrison.GetBuildings()) do
		local _, name, texPrefix, texture, description, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, inProgress, timeStarted, duration = C_Garrison.GetOwnedBuildingInfo(building.plotID)
		if inProgress then
			-- buildings in progress
			buildings[building.buildingID] = timeStarted + duration
		end
	end
	timers.ThisCharacter.lastUpdate = time()
end

-- Note: get info on missions using C_Garrison.GetBasicMissionInfo(missionID)
local function ScanGarrisonMissions(event, ...)
	local missions = timers.ThisCharacter.Garrison.Missions
	local now = time()
	-- flag known and remove outdated missions
	for missionID, expires in pairs(missions) do
		if expires <= now then
			missions[missionID] = nil
		else
			missions[missionID] = -1 * expires
		end
	end
	-- update/add currently active missions
	for index, mission in ipairs(C_Garrison.GetInProgressMissions()) do
		if missions[mission.missionID] then
			-- mission is known, remove flag but don't touch expiry
			missions[mission.missionID] = -1 * missions[mission.missionID]
		else
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

-- --------------------------------------------------------
-- Mixins
-- --------------------------------------------------------
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

-- Setup
local PublicMethods = {
	-- Garrisons
	GetGarrisonBuildExpiry   = timers.GetGarrisonBuildExpiry,
	IterateGarrisonBuilds    = timers.IterateGarrisonBuilds,
}

local garrisonMissionEvents = {
	'GARRISON_MISSION_COMPLETE_RESPONSE',   -- for failed missions
	'GARRISON_MISSION_BONUS_ROLL_COMPLETE', -- for succeeded missions
	'GARRISON_MISSION_STARTED' -- for new missions
}
local garrisonBuildingEvents = {'GARRISON_BUILDING_PLACED', 'GARRISON_BUILDING_ACTIVATED', 'GARRISON_BUILDING_ACTIVATABLE'}
function timers:OnEnable()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end

	for _, event in pairs(garrisonMissionEvents) do
		self:RegisterEvent(event, ScanGarrisonMissions)
	end
	for _, event in pairs(garrisonBuildingEvents) do
		self:RegisterEvent(event, ScanGarrisonBuildings)
	end

	-- initial scan
	C_Timer.After(1, function()
		ScanGarrisonBuildings()
		ScanGarrisonMissions()
	end)
end

function timers:OnDisable()
	for _, event in pairs(garrisonMissionEvents)  do self:UnregisterEvent(event) end
	for _, event in pairs(garrisonBuildingEvents) do self:UnregisterEvent(event) end
end
