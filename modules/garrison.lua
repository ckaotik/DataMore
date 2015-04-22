local addonName, addon = ...
local garrison = addon:NewModule('Garrison', 'AceEvent-3.0')
-- if true then return end

-- GLOBALS: _G, LibStub, DataStore, C_Garrison
-- GLOBALS: wipe, pairs, ipairs, next, strsplit, strjoin, time
local GARRISON_MAX_BUILDING_LEVEL = _G.GARRISON_MAX_BUILDING_LEVEL or 3 -- only available after UI loaded
local GARRISON_FOLLOWER_MAX_LEVEL = _G.GARRISON_FOLLOWER_MAX_LEVEL or GetMaxPlayerLevel()
local GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY = _G.GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY or _G.LE_ITEM_QUALITY_EPIC

local defaults = {
	global = {
		Characters = {
			['*'] = { -- keyed by characterKey
				lastUpdate = nil,
				Buildings = {
					['*'] = { -- keyed by buildingID
						rank = 0,
						activate = nil,   -- timestamp:build completed but needs activation|nil:otherwise
						follower = nil,   -- garrFollowerID of worker
						canUpgrade = nil, -- true|false:plan missing|nil:already max rank
						-- TODO: shipments (completed/active/max)
					},
				},
				Followers = {
					['*'] = { -- keyed by garrFollowerID, usable in *ByID(garrFollowerID) functions
						quality = GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY,
						level   = GARRISON_FOLLOWER_MAX_LEVEL,
						iLevel  = 600,
						inactive = nil,
						abilities = '', -- ability ids followed by trait ids, each separated by ':'
						-- xp      = 0, -- current amount
						-- levelXP = 0, -- amount needed for level/quality up
					},
				},
				Missions = { -- keyed by missionID
					['*'] = {
						timestamp = nil,   -- expiry or completion time, depends on status
						followers = nil, -- if ongoing: garrFollowerIDs separated by ':', nil otherwise
					},
				},
				MissionHistory = { -- only tracks rare missions
					['*'] = { -- keyed by missionID
						-- string: 'start:end:chance:success:follower1:follower2:follower3:speedFactor:goldFactor:resourceFactor'
					},
				},
				-- TODO: Invasions + InvasionHistory
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

-- sizes: 0=small, 1=medium, 2=large, 3=herbs, 4=mine, 5=fishing, 6=pets
-- local buildingOptions = C_Garrison.GetBuildingsForSize(1)
-- contains: buildingID[, plotID], name, cost, goldCost, buildTime, needsPlan, icon

-- --------------------------------------------------------
--  Gathering Data
-- --------------------------------------------------------
-- buildings
local function ScanPlot(plotID)
	if not plotID then return end
	local buildingID, name, texPath, icon, description, rank, currencyID, currencyQty, goldQty, _, needsPlan, _, _, upgrades, canUpgrade, isMaxLevel, hasFollowerSlot, _, _, _, isBeingBuilt, timeStarted, buildDuration, _, canActivate = C_Garrison.GetOwnedBuildingInfo(plotID)
	-- TODO: upgrades is not available unless on garrison map? weird...
	local baseID = rank == 1 and buildingID or (upgrades and upgrades[1]) or nil
	if not baseID then print('cannot find building base id', plotID, buildingID, upgrades, upgrades and upgrades[1]) return end
	if isBeingBuilt then
		print('is being built', baseID, buildingID, name, texPath, icon, description, rank, currencyID, currencyQty, goldQty, needsPlan, upgrades, canUpgrade, isMaxLevel, hasFollowerSlot, isBeingBuilt, timeStarted, buildDuration, canActivate)
	end
	local garrFollowerID = hasFollowerSlot and select(6, C_Garrison.GetFollowerInfoForBuilding(plotID))

	garrison.ThisCharacter.Buildings[baseID] = garrison.ThisCharacter.Buildings[baseID] or {}
	local buildingInfo = garrison.ThisCharacter.Buildings[baseID]
	buildingInfo.rank = rank
	buildingInfo.follower = tonumber(garrFollowerID or '', 16)
	buildingInfo.activate = isBeingBuilt and (timeStarted + buildTime) or nil
	buildingInfo.canUpgrade = canUpgrade
	if isMaxLevel then buildingInfo.canUpgrade = nil end
end

local function ScanBuildings()
	local buildings = garrison.ThisCharacter.Buildings
	wipe(buildings)
	-- scan buildings
	for index, building in ipairs(C_Garrison.GetBuildings()) do
		ScanPlot(building.plotID)
	end
	-- re-add town hall data
	garrison:GARRISON_UPDATE()
end

function garrison:GARRISON_UPDATE(event)
	local buildingID = 0
	self.ThisCharacter.Buildings[buildingID] = self.ThisCharacter.Buildings[buildingID] or {}
	local buildingInfo = self.ThisCharacter.Buildings[buildingID]
	buildingInfo.rank = C_Garrison.GetGarrisonInfo()
	buildingInfo.canUpgrade = C_Garrison.CanUpgradeGarrison()
	if buildingInfo.rank == GARRISON_MAX_BUILDING_LEVEL then
		buildingInfo.canUpgrade = nil
	end
end
function garrison:GARRISON_BUILDING_PLACED(event, plotID, isNewPlacement)
	ScanPlot(plotID)
end
function garrison:GARRISON_BUILDING_ACTIVATED(event, plotID, buildingID)
	ScanPlot(plotID)
end
function garrison:GARRISON_BUILDING_REMOVED(event, plotID, buildingID)
	buildingID = select(14, C_Garrison.GetBuildingInfo(buildingID))[1] or buildingID
	self.ThisCharacter.Buildings[buildingID] = nil
end
function garrison:GARRISON_BUILDING_UPDATE(event, buildingID)
	local plot, baseBuildingID
	for _, plot in pairs(C_Garrison.GetPlotsForBuilding(buildingID)) do
		local building, _, _, _, _, _, _, _, _, _, _, _, _, buildings = C_Garrison.GetOwnedBuildingInfo(plot)
		if building == buildingID then
			plotID = plot
			baseBuildingID = buildings[1] or buildingID
			break
		end
	end
	if plotID and garrison.ThisCharacter.Buildings[baseBuildingID] then
		local garrFollowerID = select(6, C_Garrison.GetFollowerInfoForBuilding(plotID))
		garrison.ThisCharacter.Buildings[baseBuildingID].follower = tonumber(garrFollowerID or '', 16)
	end
end

-- followers
local function ScanFollower(followerID)
	if not followerID then return end
	local followerLink   = C_Garrison.GetFollowerLink(followerID)
	local garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))

	garrison.ThisCharacter.Followers[garrFollowerID] = garrison.ThisCharacter.Followers[garrFollowerID] or {}
	local followerInfo = garrison.ThisCharacter.Followers[garrFollowerID]
	followerInfo.level   = C_Garrison.GetFollowerLevel(followerID)
	followerInfo.iLevel  = C_Garrison.GetFollowerItemLevelAverage(followerID)
	followerInfo.quality = C_Garrison.GetFollowerQuality(followerID)
	followerInfo.inactive = C_Garrison.GetFollowerStatus(followerID) == _G.GARRISON_FOLLOWER_INACTIVE and true or nil
	followerInfo.abilities = strjoin(':',
		C_Garrison.GetFollowerAbilityAtIndex(followerID, 1), C_Garrison.GetFollowerAbilityAtIndex(followerID, 2),
		C_Garrison.GetFollowerAbilityAtIndex(followerID, 3), C_Garrison.GetFollowerAbilityAtIndex(followerID, 4),
		C_Garrison.GetFollowerTraitAtIndex(followerID, 1), C_Garrison.GetFollowerTraitAtIndex(followerID, 2),
		C_Garrison.GetFollowerTraitAtIndex(followerID, 3), C_Garrison.GetFollowerTraitAtIndex(followerID, 4))
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
	local mission   = C_Garrison.GetBasicMissionInfo(missionID)
	local timestamp = time() + (mission.offerEndTime or select(5, C_Garrison.GetMissionTimes(missionID)))

	local followers
	for _, followerID in ipairs(mission.followers) do
		local followerLink   = C_Garrison.GetFollowerLink(followerID)
		local garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))
		followers = (followers and followers..':' or '') .. garrFollowerID
	end

	-- note: mission.state: -2 = available, -1 = active
	garrison.ThisCharacter.Missions[missionID] = garrison.ThisCharacter.Missions[missionID] or {}
	local missionInfo = garrison.ThisCharacter.Missions[missionID]
	missionInfo.timestamp = timestamp
	missionInfo.followers = followers
end

local function ScanMissions()
	for missionID, info in pairs(garrison.ThisCharacter.Missions) do
		if not info.followers then
			garrison.ThisCharacter.Missions[missionID] = nil
		end
	end
	for index, info in ipairs(C_Garrison.GetAvailableMissions()) do
		ScanMission(info.missionID)
	end
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

		local missionInfo = strjoin(':', startTime, time(), successChance, success and 1 or 0, followers, mission.durationSeconds/duration, goldBoost, resourceBoost)
		self.ThisCharacter.MissionHistory[missionID] = self.ThisCharacter.MissionHistory[missionID] or {}
		table.insert(self.ThisCharacter.MissionHistory[missionID], missionInfo)
	end
	-- remove mission from active list
	self.ThisCharacter.MissionHistory[missionID] = nil
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
function garrison.GetMissionInfo(character, missionID)
	-- local mission = character.Garrison.Missions[missionID]
	local availableUntil, 	-- if available, expiry time, otherwise 0
		  lastStarted		-- when was the mission last started
	return availableUntil, lastStarted
end
function garrison.IterateMissions(character)
	local missions, missionID = character.Garrison.Missions, nil
	return function()
		missionID = next(missions, missionID)
		if missionID then
			return missionID, garrison.GetMissionInfo(character, missionID)
		end
	end
end

function garrison.GetBuildingInfo(character, building)
	local buildingID = type(building) == 'number' and building or nil
	for id, name in pairs(buildingNames) do
		if building == name then
			buildingID = id; break
		end
	end
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
end
--[[ needs to replace
function timers.IterateGarrisonBuilds(character)
	local builds, buildingID = character.Garrison.Buildings, nil
	return function()
		buildingID = next(builds, buildingID)
		return buildingID, timers.GetGarrisonBuildExpiry(character, buildingID)
	end
end
--]]

function garrison.GetShipmentInfo(character, buildingID)
	local shipment = character.Garrison.Shipments[buildingID]
	if shipment then
		local nextBatch, numActive, numReady, maxOrders = strsplit('|', shipment)
		return nextBatch*1, numActive*1, numReady*1, maxOrders*1
	end
end
function garrison.IterateShipments(character)
	local missions, buildingID = character.Garrison.Shipments, nil
	return function()
		buildingID = next(missions, buildingID)
		return buildingID, garrison.GetShipmentInfo(character, buildingID)
	end
end
--[[ needs to replace
function timers.IterateGarrisonShipments(character)
	local missions, buildingID = character.Garrison.Shipments, nil
	return function()
		buildingID = next(missions, buildingID)
		-- TODO: buildingID is actually baseID, return both!
		-- buildingID, nextBatch, numActive, numReady, maxOrders
		return buildingID, timers.GetGarrisonShipmentInfo(character, buildingID)
	end
end
--]]

-- Setup
local PublicMethods = {
	GetMissionInfo   = garrison.GetMissionInfo,
	IterateMissions  = garrison.IterateMissions,
	GetBuildingInfo  = garrison.GetBuildingInfo,
	IterateBuildings = garrison.IterateBuildings,
	GetShipmentInfo  = garrison.GetShipmentInfo,
	IterateShipments = garrison.IterateShipments,
}
PublicMethods = {} -- TODO: remove this line

function garrison:OnEnable()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end

	-- fully scan buildings on login
	wipe(self.ThisCharacter.Buildings)
	self:RegisterEvent('GARRISON_UPDATE')
	self:RegisterEvent('GARRISON_BUILDING_UPDATE') -- fired when assigned follower changes
	self:RegisterEvent('GARRISON_BUILDING_PLACED')
	self:RegisterEvent('GARRISON_BUILDING_REMOVED')
	self:RegisterEvent('GARRISON_BUILDING_ACTIVATED')

	-- missions
	self:RegisterEvent('GARRISON_MISSION_STARTED')
	self:RegisterEvent('GARRISON_MISSION_COMPLETE_RESPONSE')
	-- self:RegisterEvent('GARRISON_MISSION_LIST_UPDATE') -- overwritten for first run
	self:RegisterEvent('GARRISON_RANDOM_MISSION_ADDED', print) -- TODO: investigate!

	-- followers
	self:RegisterEvent('GARRISON_FOLLOWER_ADDED')
	self:RegisterEvent('GARRISON_FOLLOWER_REMOVED')
	self:RegisterEvent('GARRISON_FOLLOWER_UPGRADED')

	-- initialization
	self:RegisterEvent('GARRISON_MISSION_LIST_UPDATE', function(self, event, ...)
		-- first time initialization
		ScanBuildings()
		ScanFollowers()
		ScanMissions()
		if next(self.ThisCharacter.Followers) then
			-- don't store empty data sets for followers without garrisons
			self.ThisCharacter.lastUpdate = time()
		end
		self:UnregisterEvent(event)
		self:RegisterEvent(event)
	end, self)

	--[[ shipment handling is complicated
	self:RegisterEvent('GARRISON_LANDINGPAGE_SHIPMENTS', ScanGarrisonShipments)
	-- TODO: this gets called too soon
	hooksecurefunc(C_Garrison, 'RequestShipmentCreation', ScanGarrisonShipments)
	-- there is currently no easy way to notice when a shipment has been collected
	self:RegisterEvent('ITEM_PUSH', function(event, inventoryID, icon)
		if not C_Garrison.IsOnGarrisonMap() then return end
		ScanGarrisonShipments()
	end)
	self:RegisterEvent('CHAT_MSG_CURRENCY', function(event, msg)
		if not C_Garrison.IsOnGarrisonMap() then return end
		ScanGarrisonShipments()
	end) --]]
end

function garrison:OnDisable()
	-- building events
	self:UnregisterEvent('GARRISON_UPDATE')
	self:UnregisterEvent('GARRISON_BUILDING_UPDATE')
	self:UnregisterEvent('GARRISON_BUILDING_PLACED')
	self:UnregisterEvent('GARRISON_BUILDING_REMOVED')
	self:UnregisterEvent('GARRISON_BUILDING_ACTIVATED')

	-- mission events
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
	-- self:UnregisterEvent('GARRISON_LANDINGPAGE_SHIPMENTS')
	-- self:UnregisterEvent('SHIPMENT_CRAFTER_INFO')
	-- self:UnregisterEvent('ITEM_PUSH')
end
