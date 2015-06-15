local addonName, addon, _ = ...
local garrison = addon:NewModule('Garrison', 'AceEvent-3.0')

-- TODO: store invasions & history
-- TODO: store mission basic data (icon, ...)

-- GLOBALS: _G, LibStub, DataStore, C_Garrison
-- GLOBALS: wipe, pairs, ipairs, next, strsplit, strjoin, time
local GARRISON_MAX_BUILDING_LEVEL = _G.GARRISON_MAX_BUILDING_LEVEL or 3 -- only available after UI loaded
local GARRISON_FOLLOWER_MAX_LEVEL = _G.GARRISON_FOLLOWER_MAX_LEVEL or GetMaxPlayerLevel()
local GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY = _G.GARRISON_FOLLOWER_MAX_UPGRADE_QUALITY or _G.LE_ITEM_QUALITY_EPIC
local returnTable = {}
local followers = {}

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
					['*'] = '', -- followerData|isInactive|currentXP
				},
				Missions = { -- keyed by missionID
					['*'] = '', -- completion/expiry timestamp|follower:follower:follower
				},
				MissionHistory = { -- only tracks rare missions
					['*'] = { -- keyed by missionID
						-- string: 'start:end:chance:success:follower1:follower2:follower3:speedFactor:goldFactor:resourceFactor'
					},
				},
			},
		},
		Missions = { -- keyed by missionID
			['*'] = '',
		},
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

-- http://www.wowdb.com/objects/shipments
local objectMap = {
	[236641] =  60, -- Blacksmithing
	[235892] =  76, -- Alchemy
	[235913] =  90, -- Leatherworking
	[237146] =  91, -- Engineering
	[235790] =  93, -- Enchanting
	[237665] =  94, -- Tailoring
	[236649] =  95, -- Inscription
	[235773] =  96, -- Jewelcrafting

	[238761] =  24, -- Barn Shipment
	[233832] =  40, -- Lumber Mill Shipment
	[236721] = 159, -- Tribute

	[239067] =   8, -- War Mill Work Order (Horde)
	[239066] =   8, -- Dwarven Bunker Work Order (Alliance)
	[239238] =  29, -- Herb Garden Shipment (Horde)
	[235885] =  29, -- Herb Garden Shipment (Alliance)
	[240601] =  37, -- Spirit Lodge Work Order (Horde)
	[240602] =  37, -- Mage Tower Work Order (Alliance)
	[239237] =  61, -- Mine Shipment (Horde)
	[235886] =  61, -- Mine Shipment (Alliance)
	[238757] =  91, -- Workshop Work Order (Horde)
	[238756] =  91, -- Workshop Work Order (Alliance)
	[237355] = 111, -- Trading Post Shipment (Horde)
	[237027] = 111, -- Trading Post Shipment (Alliance)
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
		C_Garrison.RequestLandingPageShipmentInfo()
		if buildingID then
			garrison:SendMessage('DATAMORE_GARRISON_SHIPMENT_COLLECTED', buildingID)
		end
	end
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

local function ScanPlots()
	for index, info in ipairs(C_Garrison.GetPlots()) do
		ScanPlot(info.id)
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
local function ScanMission(missionID, timeLeft)
	if not missionID then return end
	local mission = C_Garrison.GetBasicMissionInfo(missionID)
	local successChance = C_Garrison.GetRewardChance(missionID) -- base -or- actual chance
	local missionFollowers

	if mission.state == -2 then     -- available
		timeLeft = timeLeft or mission.offerEndTime or 24*60*60
	elseif mission.state == -1 then -- active
		timeLeft = timeLeft or select(5, C_Garrison.GetMissionTimes(missionID))
		for _, followerID in ipairs(mission.followers) do
			local followerLink   = C_Garrison.GetFollowerLink(followerID)
			local garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))
			missionFollowers = (missionFollowers and missionFollowers..':' or '') .. garrFollowerID
		end
	end
	local timestamp = math.floor(time() + timeLeft + 0.5)
	local missionInfo = strjoin('|', timestamp, successChance, missionFollowers or '')
	garrison.ThisCharacter.Missions[missionID] = strtrim(missionInfo, '|')

	-- store general information about this mission not available via C_Garrison API
	-- name: .GetMissionName, numFollowers: .GetMissionMaxFollowers, rewards: .GetMissionRewardInfo
	local missionInfo = strjoin('|', mission.type, mission.location, mission.level, mission.iLevel, mission.durationSeconds, mission.isRare and 1 or 0, mission.cost, mission.typeAtlas, mission.locPrefix)
	garrison.db.global.Missions[missionID] = strtrim(missionInfo, '|')
end

local function IsActiveMission(mission)
	if type(mission) == 'number' then
		mission = garrison.ThisCharacter.Missions[mission]
	end
	local timestamp, successChance, missionFollowers = strsplit('|', mission or '')
	return missionFollowers and missionFollowers ~= ''
end

-- TODO: adjust to work with numbered placeholders (%2$d)
local numberMappings = {
	['GARRISON_DURATION_DAYS_HOURS']    = {d =   1, h =   2, m = nil, s = nil},
	['GARRISON_DURATION_HOURS_MINUTES'] = {d = nil, h =   1, m =   2, s = nil},
	['GARRISON_DURATION_DAYS']          = {d =   1, h = nil, m = nil, s = nil},
	['GARRISON_DURATION_HOURS']         = {d = nil, h =   1, m = nil, s = nil},
	['GARRISON_DURATION_MINUTES']       = {d = nil, h = nil, m =   1, s = nil},
	['GARRISON_DURATION_SECONDS']       = {d = nil, h = nil, m = nil, s =   1},
}
local numbers = {}
local function GetNumbers(number) table.insert(numbers, number); return '' end
local fontString = UIParent:CreateFontString(nil, nil, 'GameFontNormal')
local function GetTimeLeftApproximate(timeLeftText)
	wipe(numbers)
	timeLeftText:gsub('%d+', GetNumbers)
	for pattern, map in pairs(numberMappings) do
		fontString:SetFormattedText(_G[pattern], unpack(numbers), 0, 0, 0, 0)
		-- get resolved sequences, e.g |4One:Many;
		if fontString:GetText() == timeLeftText then
			-- found the pattern, now calculate the time
			local timeLeft = 0
			if map.s then timeLeft = timeLeft + numbers[map.s] end
			if map.m then timeLeft = timeLeft + numbers[map.m]*60 end
			if map.h then timeLeft = timeLeft + numbers[map.h]*60*60 end
			if map.d then timeLeft = timeLeft + numbers[map.d]*60*60*24 end
			return timeLeft
		end
	end
end

local function ScanMissions()
	wipe(returnTable)
	C_Garrison.GetInProgressMissions(returnTable)
	-- remove outdated data
	for missionID, info in pairs(garrison.ThisCharacter.Missions) do
		local exists = false
		if IsActiveMission(info) then
			-- remove elsewhere collected missions
			for _, mission in pairs(returnTable) do
				exists = mission.missionID == missionID
				if exists then break end
			end
			if not exists then
				-- mission has been collected elsewhere
				local _, _, _, _, _, duration, isRare = garrison.GetBasicMissionInfo(missionID)
				local timestamp, successChance, missionFollowers = strsplit('|', info)
				      timestamp, successChance = timestamp * 1, successChance * 1

				if isRare then
					-- store mission history data
					garrison.ThisCharacter.MissionHistory[missionID] = garrison.ThisCharacter.MissionHistory[missionID] or {}
					-- assume mission was failed and without bonuses
					local missionInfo = strjoin('|', time() - duration, timestamp, successChance, 0, missionFollowers, 1, 1, 1)
					table.insert(garrison.ThisCharacter.MissionHistory[missionID], missionInfo)
				end
			end
		end
		if not exists then
			garrison.ThisCharacter.Missions[missionID] = nil
		end
	end

	-- now add current data
	for _, info in pairs(returnTable) do
		if garrison.ThisCharacter.Missions[info.missionID] == '' then
			-- mission must have been started elsewhere
			local timeLeft = GetTimeLeftApproximate(info.timeLeft)
			ScanMission(info.missionID, timeLeft)
		end
	end
	for _, info in pairs(C_Garrison.GetAvailableMissions()) do
		ScanMission(info.missionID)
	end
end

function garrison:GARRISON_MISSION_NPC_OPENED(event)
	self.ThisCharacter.lastUpdate = time()
end

function garrison:GARRISON_MISSION_STARTED(event, missionID)
	-- update status and followers
	ScanMission(missionID)
end
function garrison:GARRISON_MISSION_COMPLETE_RESPONSE(event, missionID, _, success)
	local _, _, _, _, _, durationSeconds, isRare, _, _, followers = garrison.GetBasicMissionInfo(missionID)
	if durationSeconds and isRare then
		-- only logging rare missions
		local missionFollowers, goldBoost, resourceBoost = '', 0, 0
		for followerIndex = 1, 3 do
			local garrFollowerID = followers and followers[followerIndex]
			if garrFollowerID then
				for traitIndex = 1, 3 do
					local traitID = C_Garrison.GetFollowerTraitAtIndexByID(garrFollowerID, traitIndex)
					goldBoost     =     goldBoost + (traitID == 256 and 1 or 0)
					resourceBoost = resourceBoost + (traitID ==  79 and 1 or 0)
				end
			end
			missionFollowers = (missionFollowers ~= '' and missionFollowers..':' or '') .. (garrFollowerID or 0)
		end

		local successChance = C_Garrison.GetRewardChance(missionID)
			or (GarrisonMissionFrame.MissionComplete.ChanceFrame.ChanceText:GetText():match('%d+') * 1)
		local duration  = select(5, C_Garrison.GetMissionTimes(missionID)) or durationSeconds
		local startTime = (self.ThisCharacter.Missions[missionID].timestamp or duration) - duration

		local missionInfo = strjoin('|', startTime, time(), successChance, success and 1 or 0, missionFollowers, durationSeconds/duration, goldBoost, resourceBoost)
		self.ThisCharacter.MissionHistory[missionID] = self.ThisCharacter.MissionHistory[missionID] or {}
		table.insert(self.ThisCharacter.MissionHistory[missionID], missionInfo)
	end
	-- remove mission from active list
	self.ThisCharacter.Missions[missionID] = nil
end
function garrison:GARRISON_MISSION_LIST_UPDATE(event, missionStarted)
	-- started missions are already handled above
	if missionStarted then return end
	ScanMissions()
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
	local resources = math.floor((time()-timestamp)/(10*60))
	return math.min(500, resources)
end

function garrison.GetMissionTableLastVisit(character)
	return character.lastUpdate
end

-- Followers
function garrison.GetFollowerIDByName(followerName)
	-- first, scan all collected followers
	for characterKey, data in pairs(garrison.db.global.Characters) do
		for garrFollowerID in pairs(data.Followers) do
			if C_Garrison.GetFollowerNameByID(garrFollowerID) == followerName then
				return garrFollowerID
			end
		end
	end
	-- follower is not collected, is it a basic follower?
	for _, follower in pairs(C_Garrison.GetFollowers()) do
		if follower.name == followerName then
			return follower.garrFollowerID or follower.followerID
		end
	end
end

function garrison.GetFollowers(character)
	wipe(returnTable)
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive, xp = strsplit('|', followerData)
		local _, quality, level = strsplit(':', linkData)
		local levelXP = level == GARRISON_FOLLOWER_MAX_LEVEL
			and C_Garrison.GetFollowerQualityTable()[quality]
			or C_Garrison.GetFollowerXPTable()[level]
		returnTable[garrFollowerID] = {
			isInactive = inactive == '1',
			link    = garrison.GetFollowerLink(character, garrFollowerID),
			xp      = xp,
			levelXP = 0,
		}
	end
	return returnTable
end

function garrison.GetFollowerIDs(character, includeInactive)
	wipe(returnTable)
	for garrFollowerID, followerData in pairs(character.Followers) do
		local _, inactive = strsplit('|', followerData)
		if includeInactive or inactive == '0' then
			tinsert(returnTable, garrFollowerID)
		end
	end
	return returnTable
end

function garrison.GetFollowerInfo(character, garrFollowerID)
	local followerData = character.Followers[garrFollowerID]
	if not followerData then return end
	local linkData, inactive, xp = strsplit('|', followerData)

	local _, quality, level, iLevel, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4 = strsplit(':', linkData)
	if not quality then return end
	quality, level, iLevel, xp     = quality*1, level*1, iLevel*1, xp*1
	skill1, skill2, skill3, skill4 = skill1*1, skill2*1, skill3*1, skill4*1
	trait1, trait2, trait3, trait4 = trait1*1, trait2*1, trait3*1, trait4*1

	local levelXP = level == GARRISON_FOLLOWER_MAX_LEVEL and C_Garrison.GetFollowerQualityTable()[quality] or C_Garrison.GetFollowerXPTable()[level]

	return quality, level, iLevel, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4, xp, levelXP, inactive == '1'
end

function garrison.GetFollowerLink(character, garrFollowerID)
	local link = C_Garrison.GetFollowerLinkByID(garrFollowerID)
	local followerData = character.Followers[garrFollowerID]
	if link and followerData then
		local linkData = strsplit('|', followerData)
		link = link:gsub('garrfollower:([^\124]+)', 'garrfollower:' .. linkData)
	end
	return link
end

function garrison.GetNumFollowers(character, excludeInactive)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local _, inactive = strsplit('|', followerData)
		if not excludeInactive or inactive == '0' then
			count = count + 1
		end
	end
	return count
end

function garrison.GetNumFollowersWithItemLevel(character, iLevel, includeInactive, strict)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive = strsplit('|', followerData)
		if includeInactive or inactive == '0' then
			local equipLevel = (linkData:match('.-:.-:.-:(.-):') or 0) * 1
			if equipLevel >= iLevel and (not strict or equipLevel == iLevel) then
				count = count + 1
			end
		end
	end
	return count
end

function garrison.GetNumFollowersWithLevel(character, level, includeInactive, strict)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive = strsplit('|', followerData)
		if includeInactive or inactive == '0' then
			local charLevel = (linkData:match('.-:.-:(.-):') or 0) * 1
			if charLevel >= level and (not strict or charLevel == level) then
				count = count + 1
			end
		end
	end
	return count
end

function garrison.GetNumFollowersWithQuality(character, quality, includeInactive)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive = strsplit('|', followerData)
		if includeInactive or inactive == '0' then
			local followerQuality = (linkData:match('.-:(.-):') or 0) * 1
			if followerQuality == quality then
				count = count + 1
			end
		end
	end
	return count
end

local function SkillInList(skillID, ...)
	for i = 1, select('#', ...) do
		local id = (select(i, ...))*1
		if id > 0 and id == skillID then
			return true
		end
	end
end
function garrison.GetNumFollowersWithSkill(character, skillID, includeInactive)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive = strsplit('|', followerData)
		local _, _, _, _, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4 = strsplit(':', linkData)
		if (includeInactive or inactive == '0') and SkillInList(skillID, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4) then
			count = count + 1
		end
	end
	return count
end

local function CounterInList(threatID, ...)
	for i = 1, select('#', ...) do
		local skillID = (select(i, ...))*1
		local skillCounter = skillID > 0 and C_Garrison.GetFollowerAbilityCounterMechanicInfo(skillID) or nil
		if skillCounter and skillCounter == threatID then
			return true
		end
	end
end
function garrison.GetNumFollowersWithCounter(character, threatID, includeInactive)
	local count = 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive = strsplit('|', followerData)
		local _, _, _, _, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4 = strsplit(':', linkData)
		if (includeInactive or inactive == '0') and CounterInList(threatID, skill1, skill2, skill3, skill4, trait1, trait2, trait3, trait4) then
			count = count + 1
		end
	end
	return count
end

function garrison.GetFollowersAverageItemLevel(character, includeInactive)
	local itemLevels, numFollowers = 0, 0
	for garrFollowerID, followerData in pairs(character.Followers) do
		local linkData, inactive = strsplit('|', followerData)
		local _, _, level, iLevel = strsplit(':', linkData, 5)
		if (includeInactive or inactive == '0') and level == GARRISON_FOLLOWER_MAX_LEVEL then
			itemLevels = itemLevels + iLevel
			numFollowers = numFollowers + 1
		end
	end
	if numFollowers == 0 then
		itemLevels = 600
		numFollowers = 1
	end
	return itemLevels/numFollowers
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
		if followerID ~= 0 then
			followers[followerID] = DataStore:GetFollowerLink(characterKey, followerID)
		end
	end)

	return startTime*1, collectTime*1, successChance*1, success == '1' and true or false, followers, speedFactor*1, goldFactor*1, resourceFactor*1
end

-- Missions
local function AddFollower(followerID) tinsert(followers, followerID*1) end
-- returns static, non character-based mission data
function garrison.GetBasicMissionInfo(missionID)
	wipe(followers)
	local missionType, location, level, iLevel, duration, isRare, cost, typeAtlas, locPrefix
	local info = C_Garrison.GetBasicMissionInfo(missionID)
	if info then
		missionType, location, level, iLevel, duration, isRare, cost, typeAtlas, locPrefix = info.type, info.location, info.level, info.iLevel, info.durationSeconds, info.isRare, info.cost, info.typeAtlas, info.locPrefix
		for k, followerID in pairs(info.followers) do
			local followerLink   = C_Garrison.GetFollowerLink(followerID)
			local garrFollowerID = tonumber(followerLink:match('garrfollower:(%d+)'))
			followers[k] = garrFollowerID
		end
	else
		local missionInfo = missionID and garrison.db.global.Missions[missionID]
		if not missionInfo then return end
		-- try figure out mission followers
		local missionFollowers = select(3, strsplit('|', missionInfo)) or ''
		missionFollowers:gsub('[^:]+', AddFollower)
		missionType, location, level, iLevel, duration, isRare, cost, typeAtlas, locPrefix = strsplit('|', missionInfo)
	end
	return missionType, typeAtlas, level*1, iLevel*1, cost*1, duration*1, isRare == '1' and true or false, locPrefix, location, followers
end

function garrison.GetMissionInfo(character, missionID)
	local missionInfo = character.Missions[missionID]
	if not missionInfo then return end
	local timestamp, successChance, missionFollowers = strsplit('|', missionInfo)
	local remainingTime = timestamp - time()
	if remainingTime < 0 then remainingTime = 0 end
	missionFollowers = missionFollowers or ''

	-- resolve followers
	wipe(followers)
	missionFollowers:gsub('[^:]+', AddFollower)

	local missionType, typeAtlas, level, ilevel, cost, duration = garrison.GetBasicMissionInfo(missionID)
	return missionType, typeAtlas, level, ilevel, cost, duration, followers, remainingTime, successChance
end

function garrison.GetGarrisonMissionExpiry(character, missionID)
	local mission = character.Missions[missionID]
	local expires = strsplit('|', mission)
	return expires*1
end

function garrison.GetMissions(character, scope)
	wipe(returnTable)
	for missionID, missionInfo in pairs(character.Missions) do
		local matches, expires = not scope, nil
		local isActive = IsActiveMission(missionInfo)
		if scope == 'available' then
			matches = not isActive
		elseif scope == 'active' then
			matches = isActive
		elseif scope == 'completed' then
			expires = garrison.GetGarrisonMissionExpiry(character, missionID)
			matches = isActive and expires <= time()
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

-- Plots and Buildings
function garrison.GetPlotInfo(character, plotID)
	local data = plotID and character.Plots[plotID] or nil
	if not data then return end

	local buildingID, rank, upgradeInfo, followerID = strsplit('|', data)
	buildingID  = buildingID ~= '' and buildingID*1 or nil
	rank        = buildingID and rank*1 or nil
	followerID  = followerID and followerID*1 or nil
	upgradeInfo = upgradeInfo and upgradeInfo*1 or 0

	local completes  = upgradeInfo > 1 and upgradeInfo or nil
	local canUpgrade = upgradeInfo == 1
	return plotID, buildingID, rank, followerID, canUpgrade, completes
end

function garrison.GetBuildingInfo(character, building)
	-- map to buildingID
	building = type(building) == 'number' and building or buildingMap[building]
	if not building then return end
	-- get localized, faction-appropriate building name to compare with
	building = select(2, C_Garrison.GetBuildingInfo(building)) or 'TownHall'
	if not building then return end
	for plotID in pairs(character.Plots) do
		local _, buildingID, rank, followerID, canUpgrade, completes = garrison.GetPlotInfo(character, plotID)
		if buildingID then
			local buildingName = select(2, C_Garrison.GetBuildingInfo(buildingID)) or 'TownHall'
			if buildingName == building then
				return buildingID, rank, followerID, canUpgrade, completes
			end
		end
	end
end

function garrison.IteratePlots(character, includeEmpty)
	local plots, key = character.Plots, nil
	return function()
		local buildingID, rank, completes, followerID, canUpgrade
		repeat
			key = next(plots, key)
			plotID, buildingID, rank, followerID, canUpgrade, completes = garrison.GetPlotInfo(character, key)
		until not plotID or buildingID or includeEmpty
		return plotID, buildingID, rank, followerID, canUpgrade, completes
	end
end

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
	-- non character-based data
	GetBasicMissionInfo = garrison.GetBasicMissionInfo,

	-- Buildings
	IteratePlots     = garrison.IteratePlots,
	GetPlotInfo      = garrison.GetPlotInfo,
	GetBuildingInfo  = garrison.GetBuildingInfo,
	GetUncollectedResources = garrison.GetUncollectedResources,
	GetLastResourceCollectionTime = garrison.GetLastResourceCollectionTime,
	-- Shipments
	GetShipmentInfo  = garrison.GetShipmentInfo,
	IterateShipments = garrison.IterateShipments,
	-- Missions
	GetMissions      = garrison.GetMissions,
	GetNumMissions   = garrison.GetNumMissions,
	GetMissionInfo   = garrison.GetMissionInfo,
	GetGarrisonMissionExpiry = garrison.GetGarrisonMissionExpiry,
	GetMissionTableLastVisit = garrison.GetMissionTableLastVisit,
	-- Mission History
	GetNumHistoryMissions  = garrison.GetNumHistoryMissions,
	IterateHistoryMissions = garrison.IterateHistoryMissions,
	GetMissionHistorySize  = garrison.GetMissionHistorySize,
	GetMissionHistoryInfo  = garrison.GetMissionHistoryInfo,
	-- Followers
	GetFollowerIDs  = garrison.GetFollowerIDs,
	GetNumFollowers = garrison.GetNumFollowers,
	GetFollowerInfo = garrison.GetFollowerInfo,
	GetFollowerLink = garrison.GetFollowerLink,
	GetFollowersAverageItemLevel = garrison.GetFollowersAverageItemLevel,
	GetNumFollowersWithLevel     = garrison.GetNumFollowersWithLevel,
	GetNumFollowersWithItemLevel = garrison.GetNumFollowersWithItemLevel,
	GetNumFollowersWithQuality   = garrison.GetNumFollowersWithQuality,
	GetNumFollowersWithSkill     = garrison.GetNumFollowersWithSkill,
	GetNumFollowersWithCounter   = garrison.GetNumFollowersWithCounter,

	-- compatibility with DataStore_Garrisons
	GetFollowerID              = garrison.GetFollowerIDByName,
	GetActiveMissionInfo       = garrison.GetMissionInfo,
	GetAvailableMissionInfo    = garrison.GetMissionInfo,
	GetFollowers               = garrison.GetFollowers,
	GetAvailableMissions       = function(char) return garrison.GetMissions(char, 'available') end,
	GetActiveMissions          = function(char) return garrison.GetMissions(char, 'active') end,
	GetNumActiveMissions       = function(char) return garrison.GetNumMissions(char, 'active') end,
	GetNumAvailableMissions    = function(char) return garrison.GetNumMissions(char, 'available') end,
	GetNumCompletedMissions    = function(char) return garrison.GetNumMissions(char, 'completed') end,
	GetNumFollowersAtLevel100  = function(char) return garrison.GetNumFollowersWithLevel(char, 100, true, true) end,
	GetNumFollowersAtiLevel615 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 615, true) end,
	GetNumFollowersAtiLevel630 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 630, true) end,
	GetNumFollowersAtiLevel645 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 645, true) end,
	GetNumFollowersAtiLevel660 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 660, true) end,
	GetNumFollowersAtiLevel675 = function(char) return garrison.GetNumFollowersWithItemLevel(char, 675, true) end,
	GetNumRareFollowers        = function(char) return garrison.GetNumFollowersWithQuality(char, 3, true) end,
	GetNumEpicFollowers        = function(char) return garrison.GetNumFollowersWithQuality(char, 4, true) end,
	GetAvgWeaponiLevel         = function(char) return garrison.GetFollowersAverageItemLevel(char) end,
	GetAvgArmoriLevel          = function(char) return garrison.GetFollowersAverageItemLevel(char) end,
	GetFollowerSpellCounters = function(char, spellType, id) return garrison[spellType == 'AbilityCounters' and 'GetNumFollowersWithCounter' or 'GetNumFollowersWithSkill'](char, id) end,
}

function garrison:OnEnable()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	-- we will override parts of DataStore_Garrisons
	DataStore:RegisterModule(self.name, self, PublicMethods, true)
	for methodName in pairs(PublicMethods) do
		if methodName ~= 'GetBasicMissionInfo' and methodName ~= 'GetFollowerID' then
			DataStore:SetCharacterBasedMethod(methodName)
		end
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
		-- landing page updates with a slight delay
		C_Timer.After(0.5, C_Garrison.RequestLandingPageShipmentInfo)
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
			ScanPlots()
			ScanFollowers()
			ScanMissions()
			-- don't store empty data sets for characters without garrisons
			self.ThisCharacter.lastUpdate = self.ThisCharacter.lastUpdate or time()

			-- TODO: prune history data
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
	self:UnregisterEvent('SHIPMENT_UPDATE')
	self:UnregisterEvent('SHIPMENT_CRAFTER_INFO')
	self:UnregisterEvent('SHIPMENT_CRAFTER_CLOSED')
end
