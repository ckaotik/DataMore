local addonName, addon = ...
local garrison = addon:NewModule('Garrison', 'AceEvent-3.0')

-- TODO: store invasions & history
-- TODO: store mission basic data (icon, ...)

-- GLOBALS: _G, LibStub, DataStore, C_Garrison
-- GLOBALS: wipe, pairs, ipairs, next, strsplit, strjoin, time
local GARRISON_MAX_BUILDING_LEVEL = _G.GARRISON_MAX_BUILDING_LEVEL or 3 -- only available after UI loaded
local GARRISON_FOLLOWER_MAX_LEVEL = _G.GARRISON_FOLLOWER_MAX_LEVEL or GetMaxPlayerLevel()
local GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY = _G.GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY or _G.LE_ITEM_QUALITY_EPIC
local returnTable = {}

local defaults = {
	global = {
		Characters = {
			['*'] = { -- keyed by characterKey
				lastUpdate = nil,
				lastResourceCollection = nil,
				Plots = { -- keyed by plotID
					['*'] = '', -- buildingID|rank|upgrade|follower,
					-- upgrade: timestamp: activate, 1: can upgrade, 0: plan missing
				},
				Shipments = { -- keyed by base buildingID
					['*'] = '', -- capacity|completed|queued|nextBatch
				},
				Followers = { -- keyed by garrFollowerID, usable in *ByID(garrFollowerID) functions
					['*'] = '', -- followerLink
				},
				Missions = { -- keyed by missionID
					['*'] = '', -- completion/expiry timestamp|follower:follower:follower
				},
				MissionHistory = { -- only tracks rare missions
					['*'] = { -- keyed by missionID
						-- string: 'start:end:chance:success:follower1:follower2:follower3:speedFactor:goldFactor:resourceFactor'
					},
				},
			}
		}
	},
}

-- needed for compatibility with DataStore_Garrisons
local buildingNames = {
	[  0] = 'TownHall',
	[  8] = 'DwarvenBunker', 		-- bunker/war mill
	[ 24] = 'Barn',
	[ 26] = 'Barracks',
	[ 29] = 'HerbGarden',
	[ 34] = 'LunarfallInn', 		-- inn/tavern
	[ 37] = 'MageTower',
	[ 40] = 'LumberMill',
	[ 42] = 'Menagerie', 			-- battle pets
	[ 51] = 'Storehouse',
	[ 52] = 'SalvageYard',
	[ 60] = 'TheForge', 			-- blacksmithing
	[ 61] = 'LunarfallExcavation', 	-- mines
	[ 64] = 'FishingShack', 		-- fishing
	[ 65] = 'Stables',
	[ 76] = 'AlchemyLab', 			-- alchemy
	[ 90] = 'TheTannery', 			-- leatherworking
	[ 91] = 'EngineeringWorks', 	-- engineering
	[ 93] = 'EnchantersStudy', 		-- enchanting
	[ 94] = 'TailoringEmporium', 	-- tailoring
	[ 95] = 'ScribesQuarters', 		-- inscription
	[ 96] = 'GemBoutique', 			-- jewelcrafting
	[111] = 'TradingPost',
	[159] = 'GladiatorsSanctum',
	[162] = 'GnomishGearworks',
}
local buildingMap = {}
for buildingID, identifier in pairs(buildingNames) do
	-- map DataStore identifiers
	buildingMap[identifier] = buildingID
	if buildingID > 0 then
		-- also map building names
		local _, name = C_Garrison.GetBuildingInfo(buildingID)
		buildingMap[name] = buildingID
	end
end

-- list taken from http://www.wowhead.com/objects=45
local objectMap = {
	[230850] =  76, -- Alchemy Lab Work Order
	[233832] =  40, -- Lumber Mill Work Order
	[235892] =  76, -- Alchemy Work Order
	[236641] =  60, -- Blacksmithing Work Order
	[236649] =  95, -- Inscription Work Order
	[236652] =  96, -- Jewelcrafting Work Order
	[236721] = 159, -- Tribute
	[236948] =  90, -- Leatherworking Work Order
	[237027] = 111, -- Trading Post Work Order
	[237138] =  93, -- Enchanting Work Order
	[237146] =  91, -- Engineering Work Order
	[237665] =  94, -- Tailoring Work Order
	[238756] =  91, -- Workshop Work Order
	[238757] =  91, -- Workshop Work Order
	[238761] =  24, -- Barn Work Order
	[239066] =   8, -- Dwarven Bunker Work Order
	[239067] =   8, -- War Mill Work Order
	[239237] =  61, -- Mine Work Order
	[239238] =  29, -- Herb Garden Work Order
	[240601] =  37, -- Spirit Lodge Work Order
	[240602] =  37, -- Mage Tower Work Order
}

-- --------------------------------------------------------
--  Gathering Data
-- --------------------------------------------------------
function garrison:SHOW_LOOT_TOAST(event, lootType, link, quantity, specID, sex, isPersonal, lootSource)
	if C_Garrison.IsOnGarrisonMap() and lootSource == 10 then
		self.ThisCharacter.lastResourceCollection = time()
	end
end

-- shipments
local function ScanShipment(plotID)
	local buildingID, name = C_Garrison.GetOwnedBuildingInfo(plotID)
	if not buildingID then return end -- no building in plot

	local name, _, capacity, completed, queued, startTime, duration, _, _, _, _, itemID = C_Garrison.GetLandingPageShipmentInfo(buildingID)
	if not name then return end -- building has no shipments, ever
	local baseID = name and buildingMap[name] or buildingID
	if capacity and capacity > 0 then
		if startTime then
			local nextBatch = startTime and (startTime + duration) or 0
			garrison.ThisCharacter.Shipments[baseID] = strjoin('|', capacity, completed, queued, nextBatch)
		else
			garrison.ThisCharacter.Shipments[baseID] = capacity
		end
	else
		garrison.ThisCharacter.Shipments[baseID] = 0
	end
end
local function ScanShipments(event, updatedPlotID)
	wipe(garrison.ThisCharacter.Shipments)
	for plotID, plotData in pairs(garrison.ThisCharacter.Plots) do
		ScanShipment(plotID)
	end
	garrison.ThisCharacter.lastUpdate = time()
end
local function ScanShipmentLoot(event)
	if not C_Garrison.IsOnGarrisonMap() then return end
	local source = GetLootSourceInfo(1)
	local guidType, _, _, _, _, id = strsplit('-', source)
	if guidType == 'GameObject' then
		local buildingID = objectMap[id * 1]
		if not buildingID then return end
		C_Garrison.RequestLandingPageShipmentInfo()
		garrison:SendMessage('DATAMORE_GARRISON_SHIPMENT_COLLECTED', buildingID)
	end
end

-- landing page updates with a slight delay
function garrison:SHIPMENT_CRAFTER_INFO(event, success, numActive, capacity, plotID)
	if success == 1 then C_Garrison.RequestLandingPageShipmentInfo() end
	self:UnregisterEvent('SHIPMENT_CRAFTER_INFO')
	self:UnregisterEvent('SHIPMENT_CRAFTER_CLOSED')
end

-- buildings
local function ScanPlot(plotID)
	if not plotID then return end
	local buildingID, name, texPath, icon, description, rank, currencyID, currencyQty, goldQty, _, needsPlan, _, _, upgrades, canUpgrade, isMaxLevel, hasFollowerSlot, _, _, _, isBeingBuilt, timeStarted, buildTime, _, canActivate = C_Garrison.GetOwnedBuildingInfo(plotID)
	local garrFollowerID = hasFollowerSlot and select(6, C_Garrison.GetFollowerInfoForBuilding(plotID))
	      garrFollowerID = tonumber(garrFollowerID or '', 16)

	local upgradeInfo = isBeingBuilt and (timeStarted + buildTime) or (canUpgrade and 1 or 0)
	garrison.ThisCharacter.Plots[plotID] = strjoin('|', buildingID or '', rank or 0, upgradeInfo)
	if garrFollowerID then
		garrison.ThisCharacter.Plots[plotID] = garrison.ThisCharacter.Plots[plotID] .. '|' .. garrFollowerID
	end
end

-- triggered when garrison level changes
function garrison:GARRISON_UPDATE(event)
	local plotID, buildingID = 0, 0
	local rank       = C_Garrison.GetGarrisonInfo()
	local canUpgrade = C_Garrison.CanUpgradeGarrison()
	garrison.ThisCharacter.Plots[plotID] = strjoin('|', buildingID, rank, canUpgrade and 1 or 0)
end
function garrison:GARRISON_BUILDING_PLACED(event, plotID, isNewPlacement)
	ScanPlot(plotID)
	if isNewPlacement then
		ScanShipment(plotID)
	end
end
function garrison:GARRISON_BUILDING_REMOVED(event, plotID, buildingID)
	self.ThisCharacter.Plots[plotID] = nil
	-- clear shipments for this building
	local _, name = C_Garrison.GetBuildingInfo(buildingID)
	local baseID = name and buildingMap[name] or buildingID
	self.ThisCharacter.Shipments[baseID] = nil
end
function garrison:GARRISON_BUILDING_ACTIVATED(event, plotID, buildingID)
	ScanPlot(plotID)
end
-- triggered when assigned followers change
function garrison:GARRISON_BUILDING_UPDATE(event, buildingID)
	for _, plotID in pairs(C_Garrison.GetPlotsForBuilding(buildingID)) do
		local building, _, _, _, _, _, _, _, _, _, _, _, _, buildings = C_Garrison.GetOwnedBuildingInfo(plotID)
		if building == buildingID then
			ScanPlot(plotID)
			break
		end
	end
end

-- followers
local function ScanFollower(followerID)
	if not followerID then return end
	local followerLink = C_Garrison.GetFollowerLink(followerID)
	local followerData, garrFollowerID = followerLink:match('garrfollower:((%d+)[^\124]+)')
	local garrFollowerID = tonumber(garrFollowerID)

	local inactive = C_Garrison.GetFollowerStatus(followerID) == _G.GARRISON_FOLLOWER_INACTIVE and 1 or 0
	local xp = C_Garrison.GetFollowerXP(followerID)
	garrison.ThisCharacter.Followers[garrFollowerID] = strjoin('|', followerData, inactive, xp)
end

local function ScanFollowers()
	wipe(garrison.ThisCharacter.Followers)
	for index, follower in ipairs(C_Garrison.GetFollowers()) do
		-- uncollected have plain .followerID, collected have hex .garrFollowerID
		if follower.isCollected then ScanFollower(follower.followerID) end
	end
end

function garrison:GARRISON_FOLLOWER_UPGRADED(event, followerID)
	ScanFollower(followerID)
end
function garrison:GARRISON_FOLLOWER_ADDED(event, followerID)
	ScanFollower(followerID)
end
function garrison:GARRISON_FOLLOWER_REMOVED(event, followerID)
	local followerLink   = C_Garrison.GetFollowerLink(followerID)
	local garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))
	self.ThisCharacter.Followers[garrFollowerID] = nil
end

-- missions
local function ScanMission(missionID)
	if not missionID then return end
	local mission = C_Garrison.GetBasicMissionInfo(missionID)
	local timestamp, followers

	if mission.state == -2 then     -- available
		timestamp = math.floor(time() + mission.offerEndTime + 0.5)
	elseif mission.state == -1 then -- active
		timestamp = time() + select(5, C_Garrison.GetMissionTimes(missionID))

		for _, followerID in ipairs(mission.followers) do
			local followerLink   = C_Garrison.GetFollowerLink(followerID)
			local garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))
			followers = (followers and followers..':' or '') .. garrFollowerID
		end
	end
	garrison.ThisCharacter.Missions[missionID] = followers and strjoin('|', timestamp, followers) or timestamp
end

local function ScanMissions()
	for missionID, info in pairs(garrison.ThisCharacter.Missions) do
		if type(info) == 'number' then
			garrison.ThisCharacter.Missions[missionID] = nil
		end
	end
	for index, info in ipairs(C_Garrison.GetAvailableMissions()) do
		ScanMission(info.missionID)
	end
end

function garrison:GARRISON_MISSION_NPC_OPENED(event)
	-- remove elsewhere collected missions
	wipe(returnTable)
	C_Garrison.GetInProgressMissions(returnTable)
	for missionID, missionInfo in pairs(self.ThisCharacter.Missions) do
		if type(missionInfo) == 'string' then
			local exists = false
			for _, mission in pairs(returnTable) do
				exists = mission.missionID == missionID
				if exists then break end
			end
			if not exists then
				self.ThisCharacter.Missions[missionID] = nil
			end
		end
	end
	self.ThisCharacter.lastUpdate = time()
end

function garrison:GARRISON_MISSION_STARTED(event, missionID)
	-- update status and followers
	ScanMission(missionID)
end
function garrison:GARRISON_MISSION_COMPLETE_RESPONSE(event, missionID, _, success)
	local mission = C_Garrison.GetBasicMissionInfo(missionID)
	if mission and mission.isRare then
		-- only logging rare missions
		local followers, goldBoost, resourceBoost = '', 0, 0
		for followerIndex = 1, 3 do
			local followerID, garrFollowerID = mission.followers and mission.followers[followerIndex], 0
			if followerID then
				for traitIndex = 1, 3 do
					local traitID = C_Garrison.GetFollowerTraitAtIndex(followerID, traitIndex)
					goldBoost     =     goldBoost + (traitID == 256 and 1 or 0)
					resourceBoost = resourceBoost + (traitID ==  79 and 1 or 0)
				end
				local followerLink = C_Garrison.GetFollowerLink(followerID)
				garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))
			end
			followers = (followers ~= '' and followers..':' or '') .. garrFollowerID
		end

		local successChance = C_Garrison.GetRewardChance(missionID)
			or (GarrisonMissionFrame.MissionComplete.ChanceFrame.ChanceText:GetText():match('%d+') * 1)
		local duration      = select(5, C_Garrison.GetMissionTimes(missionID))
		local startTime     = (self.ThisCharacter.Missions[missionID].timestamp or duration) - duration

		local missionInfo = strjoin('|', startTime, time(), successChance, success and 1 or 0, followers, mission.durationSeconds/duration, goldBoost, resourceBoost)
		self.ThisCharacter.MissionHistory[missionID] = self.ThisCharacter.MissionHistory[missionID] or {}
		table.insert(self.ThisCharacter.MissionHistory[missionID], missionInfo)
	end
	-- remove mission from active list
	self.ThisCharacter.Missions[missionID] = nil
end
function garrison:GARRISON_MISSION_LIST_UPDATE(event, missionStarted)
	-- started missions are already handled above
	if missionStarted then return end
	for i, mission in pairs(C_Garrison.GetAvailableMissions()) do
		ScanMission(mission.missionID)
	end
end

-- --------------------------------------------------------
-- Mixins
-- --------------------------------------------------------
function garrison.GetLastResourceCollectionTime(character)
	return character.lastResourceCollection
end

function garrison.GetUncollectedResources(character)
	local timestamp = garrison.GetLastResourceCollectionTime(character)
	if not timestamp then return 0 end

	-- cache generates 1 resource per 10 minutes
	local resources = (timestamp - time())/(10*60)
	return math.min(500, resources)
end

function garrison.GetMissionTableLastVisit(character)
	return character.lastUpdate
end

-- Followers
function garrison.GetFollowerInfo(character, garrFollowerID)
	local followerData = character.Followers[garrFollowerID]
	if not followerData then return end
	local linkData, inactive, xp = strsplit('|', followerData)

	local _, quality, level, iLevel, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4 = strsplit(':', linkData)
	quality, level, iLevel, xp     = quality*1, level*1, iLevel*1, xp*1
	skill1, skill2, skill3, skill4 = skill1*1, skill2*1, skill3*1, skill4*1
	trait1, trait2, trait3, trait4 = trait1*1, trait2*1, trait3*1, trait4*1

	local levelXP = level == GARRISON_FOLLOWER_MAX_LEVEL and C_Garrison.GetFollowerQualityTable()[quality] or C_Garrison.GetFollowerXPTable()[level]

	return quality, level, iLevel, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4, xp, levelXP, inactive == '1'
end

function garrison.GetFollowerLink(character, garrFollowerID)
	local link = C_Garrison.GetFollowerLinkByID(garrFollowerID)
	local followerData = character.Followers[garrFollowerID]
	if followerData then
		local linkData = strsplit('|', followerData)
		link = followerLink:gsub('garrfollower:([^\124]+)', 'garrfollower:' .. linkData)
	end
	return link
end

function garrison.GetNumFollowers(character)
	local count = 0
	for garrFollowerID in pairs(character.Followers) do
		count = count + 1
	end
	return count
end

function garrison.GetNumFollowersWithItemLevel(character, iLevel)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local equipLevel = followerData:match('.-:.-:.-:(.-):')
		if tonumber(equipLevel or '') >= iLevel then
			count = count + 1
		end
	end
	return count
end

function garrison.GetNumFollowersWithLevel(character, level)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local charLevel = followerData:match('.-:.-:(.-):')
		if tonumber(charLevel or '') >= level then
			count = count + 1
		end
	end
	return count
end

function garrison.GetNumFollowersWithQuality(character, quality)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local followerQuality = followerData:match('.-:(.-):')
		if tonumber(followerQuality or '') >= quality then
			count = count + 1
		end
	end
	return count
end

-- Mission History
function garrison.GetNumHistoryMissions(character)
	local numMissions = 0
	for missionID, history in pairs(character.MissionHistory) do
		numMissions = numMissions + 1
	end
	return numMissions
end

function garrison.IterateHistoryMissions(character)
	local missions, missionID = character.MissionHistory, nil
	return function()
		missionID = next(missions, missionID)
		if missionID then
			return missionID, garrison.GetMissionHistorySize(character, missionID)
		end
	end
end

-- Mission History for a specific mission
function garrison.GetMissionHistorySize(character, missionID)
	local history = missionID and character.MissionHistory[missionID]
	local numRecords = history and #history or 0
	return numRecords
end

local followers = {}
function garrison.GetMissionHistoryInfo(character, missionID, index)
	local history = missionID and character.MissionHistory[missionID]
	local data = history and history[index]
	if not data then return end

	local characterKey = DataStore:GetCurrentCharacterKey()
	local startTime, collectTime, successChance, success, missionFollowers, speedFactor, goldFactor, resourceFactor = strsplit('|', data)

	-- resolve followers
	wipe(followers)
	missionFollowers:gsub('[^:]+', function(followerID)
		followerID = tonumber(followerID)
		followers[followerID] = DataStore:GetFollowerLink(characterKey, followerID)
	end)

	return startTime, collectTime, successChance, success, followers, speedFactor, goldFactor, resourceFactor
end

-- Missions
function garrison.GetGarrisonMissionExpiry(character, missionID)
	local mission = character.Missions[missionID]
	local expires = strsplit('|', mission)
	return expires*1
end

--[[ function garrison.GetMissionInfo(character, missionID)
	-- local mission = character.Missions[missionID]
	local availableUntil, 	-- if available, expiry time, otherwise 0
		  lastStarted		-- when was the mission last started
	return availableUntil, lastStarted
	-- "Kampf", "GarrMission_MissionIcon-Combat", 100, 675, 25, 36000, {1 = 216, 2=, 3=}, 1234, 100
	return missionType, typeAtlas, level, ilevel, cost, duration, followers, remainingTime, successChance
end --]]

function garrison.GetMissions(character, scope)
	wipe(returnTable)
	for missionID, missionInfo in pairs(character.Missions) do
		local matches, expires = not scope, nil
		if scope == 'available' then
			matches = type(missionInfo) == 'number'
		elseif scope == 'active' then
			matches = type(missionInfo) == 'string'
		elseif scope == 'completed' then
			expires = garrison.GetGarrisonMissionExpiry(character, missionID)
			matches = type(missionInfo) == 'string' and expires <= time()
		end

		if matches then
			expires = expires or garrison.GetGarrisonMissionExpiry(character, missionID)
			returnTable[missionID] = expires
			--[[-- DataStore_Garrisons return values
			returnTable[missionID] = {
				cost = mission.cost,
				durationSeconds = mission.durationSeconds,
				level = mission.level,
				iLevel = mission.iLevel,
				type = mission.type,
				typeAtlas = mission.typeAtlas,
				startTime = time(),
				successChance = select(4, C_Garrison.GetPartyMissionInfo(missionID)),
				followers = {followerID, followerID, followerID},
			} --]]
		end
	end
	return returnTable
end

function garrison.GetNumMissions(character, scope)
	local count = 0
	local missions = garrison.GetMissions(character, scope)
	for missionID in pairs(missions) do
		count = count + 1
	end
	return count
end

--[[ function garrison.GetBuildingInfo(character, building)
	if not buildingID then return end
	local buildingID = type(building) == 'number' and building or buildingMap[building]
	if not buildingID then return end

	local completes 		-- timestamp when building can be activated or nil if completely built
	local buildingID, rank
	return buildingID, rank
end

function garrison.IterateBuildings(character)
	local builds, buildingID = character.Garrison.Buildings, nil
	return function()
		buildingID = next(builds, buildingID)
		return buildingID, garrison.GetBuildInfo(character, buildingID)
	end
end --]]
--[[ needs to replace
function timers.IterateGarrisonBuilds(character)
	local builds, buildingID = character.Garrison.Buildings, nil
	return function()
		buildingID = next(builds, buildingID)
		return buildingID, timers.GetGarrisonBuildExpiry(character, buildingID)
	end
end
--]]

-- takes a building name or buildingID
function garrison.GetShipmentInfo(character, building)
	local baseID
	if type(building) == 'string' then
		baseID = buildingMap[building]
	elseif buildingMap[building] then
		baseID = buildingMap[building]
	elseif not character.Shipments[building] then
		-- not a base id yet
		_, building = C_Garrison.GetBuildingInfo(building)
		baseID = buildingMap[building]
	else
		baseID = building
	end

	local capacity, completed, queued, nextBatch
	if baseID and character.Shipments[baseID] then
		capacity, completed, queued, nextBatch = strsplit('|', character.Shipments[baseID])
		capacity, completed, queued, nextBatch = capacity and capacity*1, completed and completed*1, queued and queued*1, nextBatch and nextBatch*1
	end
	return capacity or 0, queued or 0, completed or 0, nextBatch or 0
end

function garrison.IterateShipments(character)
	local shipments, baseID = character.Shipments, nil
	return function()
		baseID = next(shipments, baseID)
		if baseID then
			return baseID, garrison.GetShipmentInfo(character, baseID)
		end
	end
end

-- Setup
local PublicMethods = {
	-- Buildings
	-- GetBuildingInfo  = garrison.GetBuildingInfo,
	-- IterateBuildings = garrison.IterateBuildings,
	-- Shipments
	GetShipmentInfo  = garrison.GetShipmentInfo,
	IterateShipments = garrison.IterateShipments,
	-- Missions
	-- GetMissionInfo   = garrison.GetMissionInfo,
	GetGarrisonMissionExpiry = garrison.GetGarrisonMissionExpiry,
	GetMissions              = garrison.GetMissions,
	GetNumMissions           = garrison.GetNumMissions,
	-- GetAvailableMissions  = function(char) return garrison.GetMissions(char, 'available') end,
	-- GetActiveMissions     = function(char) return garrison.GetMissions(char, 'active') end,
	-- Mission History
	GetNumHistoryMissions  = garrison.GetNumHistoryMissions,
	IterateHistoryMissions = garrison.IterateHistoryMissions,
	GetMissionHistorySize  = garrison.GetMissionHistorySize,
	GetMissionHistoryInfo  = garrison.GetMissionHistoryInfo,
	-- Followers
	-- GetFollowerInfo = garrison.GetFollowerInfo,
	-- GetFollowerLink = garrison.GetFollowerLink,
	-- GetNumFollowers              = garrison.GetNumFollowers,
	GetNumFollowersWithLevel     = garrison.GetNumFollowersWithLevel,
	GetNumFollowersWithItemLevel = garrison.GetNumFollowersWithItemLevel,
	GetNumFollowersWithQuality   = garrison.GetNumFollowersWithQuality,

	-- compatibility with DataStore_Garrisons
	-- GetUncollectedResources       = garrison.GetUncollectedResources,
	-- GetLastResourceCollectionTime = garrison.GetLastResourceCollectionTime,
	-- GetMissionTableLastVisit   = garrison.GetMissionTableLastVisit,
	-- GetActiveMissionInfo       = garrison.GetMissionInfo,
	-- GetAvailableMissionInfo    = garrison.GetMissionInfo,
	-- GetNumActiveMissions    = function(char) return garrison.GetNumMissions(char, 'active') end,
	-- GetNumAvailableMissions = function(char) return garrison.GetNumMissions(char, 'available') end,
	-- GetNumCompletedMissions = function(char) return garrison.GetNumMissions(char, 'completed') end,
	-- GetNumFollowersAtLevel100  = function(char) return garrison.GetNumFollowersWithLevel(char, 100) end,
	-- GetNumFollowersAtiLevel615 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 615) end,
	-- GetNumFollowersAtiLevel630 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 630) end,
	-- GetNumFollowersAtiLevel645 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 645) end,
	-- GetNumFollowersAtiLevel660 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 660) end,
	-- GetNumFollowersAtiLevel675 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 675) end,
	-- GetNumRareFollowers        = function(char) return garrison.GetNumFollowersWithQuality(char, 2) end,
	-- GetNumEpicFollowers        = function(char) return garrison.GetNumFollowersWithQuality(char, 3) end,

	--[[
	-- GetFollowerID = _GetFollowerID, -- non-char data
	GetFollowers = _GetFollowers,
	GetFollowerSpellCounters = _GetFollowerSpellCounters,
	GetAvgWeaponiLevel = _GetAvgWeaponiLevel,
	GetAvgArmoriLevel = _GetAvgArmoriLevel,
	--]]
}

function garrison:OnEnable()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end

	-- resources
	self:RegisterEvent('SHOW_LOOT_TOAST')

	-- buildings
	self:RegisterEvent('GARRISON_UPDATE')
	self:RegisterEvent('GARRISON_BUILDING_UPDATE') -- fired when assigned follower changes
	self:RegisterEvent('GARRISON_BUILDING_PLACED')
	self:RegisterEvent('GARRISON_BUILDING_REMOVED')
	self:RegisterEvent('GARRISON_BUILDING_ACTIVATED')

	-- shipments
	self:RegisterEvent('LOOT_READY', ScanShipmentLoot)
	self:RegisterEvent('GARRISON_LANDINGPAGE_SHIPMENTS', ScanShipments)
	hooksecurefunc(C_Garrison, 'RequestShipmentCreation', function(numShipments)
		-- events are only registered on demand
		self:RegisterEvent('SHIPMENT_CRAFTER_INFO')
		self:RegisterEvent('SHIPMENT_CRAFTER_CLOSED', garrison.SHIPMENT_CRAFTER_INFO, self)
	end)

	-- missions
	self:RegisterEvent('GARRISON_MISSION_NPC_OPENED')
	self:RegisterEvent('GARRISON_MISSION_STARTED')
	self:RegisterEvent('GARRISON_MISSION_COMPLETE_RESPONSE')
	-- self:RegisterEvent('GARRISON_MISSION_LIST_UPDATE') -- overwritten for first run

	-- followers
	self:RegisterEvent('GARRISON_FOLLOWER_ADDED')
	self:RegisterEvent('GARRISON_FOLLOWER_REMOVED')
	self:RegisterEvent('GARRISON_FOLLOWER_UPGRADED')

	-- initialization
	self:RegisterEvent('GARRISON_MISSION_LIST_UPDATE', function(self, event, ...)
		-- first time initialization
		if C_Garrison.GetGarrisonInfo() then
			ScanFollowers()
			ScanMissions()
			-- don't store empty data sets for characters without garrisons
			self.ThisCharacter.lastUpdate = self.ThisCharacter.lastUpdate or time()
		end
		self:UnregisterEvent(event)
		self:RegisterEvent(event)
	end, self)
end

function garrison:OnDisable()
	self:UnregisterEvent('SHOW_LOOT_TOAST')

	-- building events
	self:UnregisterEvent('GARRISON_UPDATE')
	self:UnregisterEvent('GARRISON_BUILDING_UPDATE')
	self:UnregisterEvent('GARRISON_BUILDING_PLACED')
	self:UnregisterEvent('GARRISON_BUILDING_REMOVED')
	self:UnregisterEvent('GARRISON_BUILDING_ACTIVATED')

	-- mission events
	self:UnregisterEvent('GARRISON_MISSION_NPC_OPENED')
	self:UnregisterEvent('GARRISON_MISSION_STARTED')
	self:UnregisterEvent('GARRISON_MISSION_COMPLETE_RESPONSE')
	-- self:UnregisterEvent('GARRISON_RANDOM_MISSION_ADDED')
	self:UnregisterEvent('GARRISON_MISSION_LIST_UPDATE')

	-- follower events
	self:UnregisterEvent('GARRISON_FOLLOWER_ADDED')
	self:UnregisterEvent('GARRISON_FOLLOWER_REMOVED')
	self:UnregisterEvent('GARRISON_FOLLOWER_UPGRADED')
	self:UnregisterEvent('GARRISON_UPGRADEABLE_RESULT')

	-- shipment events
	self:UnregisterEvent('LOOT_READY')
	self:UnregisterEvent('GARRISON_LANDINGPAGE_SHIPMENTS')
	self:UnregisterEvent('SHIPMENT_CRAFTER_INFO')
	self:UnregisterEvent('SHIPMENT_CRAFTER_CLOSED')
end
