local addonName, addon = ...
local lockouts = addon:NewModule('Lockouts', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore, EXPANSION_LEVEL
-- GLOBALS: IsAddOnLoaded, UnitLevel, GetQuestResetTime, GetRFDungeonInfo, GetNumRFDungeons, GetLFGDungeonRewardCapInfo, GetLFGDungeonNumEncounters, GetLFGDungeonRewards, GetLFDLockInfo, LFG_INSTANCE_INVALID_CODES, GetNumSavedWorldBosses, GetSavedWorldBossInfo, GetNumSavedInstances, GetSavedInstanceInfo, GetLFGDungeonEncounterInfo, GetSavedInstanceChatLink, GetSavedInstanceInfo, GetSavedInstanceEncounterInfo, RequestRaidInfo
-- GLOBALS: type, next, wipe, pairs, time, date, string, tonumber, math, strsplit, strjoin, strtrim, bit, unpack

local defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				LFGs = {},
				WorldBosses = {},
				Instances = {},
				InstanceLinks = {},
			}
		}
	}
}

local thisCharacter = DataStore:GetCharacter()

-- *** Scanning functions ***
local LFGInfos = {
	-- GetNumX(), GetXInfo(index) returning same data as GetLFGDungeonInfo(dungeonID)
	{ GetNumRandomDungeons, GetLFGRandomDungeonInfo },
	{ GetNumRandomScenarios, GetRandomScenarioInfo },
	{ GetNumRFDungeons, GetRFDungeonInfo },
	{ GetNumFlexRaidDungeons, GetFlexRaidDungeonInfo },
}

local function UpdateLFGStatus()
	-- TODO: group data by dungeon?
	local playerLevel = UnitLevel('player')

	local lfgs = lockouts.ThisCharacter.LFGs
	wipe(lfgs)
	for i, funcs in pairs(LFGInfos) do
		local getNum, getInfo = funcs[1], funcs[2]
		for index = 1, getNum() do
			local dungeonID, _, _, _, minLevel, maxLevel, _, _, _, expansionLevel = getInfo(index)
			local _, _, completed, available, _, _, _, _, _, _, isWeekly = GetLFGDungeonRewardCapInfo(dungeonID)
			local numBosses, numDefeated = GetLFGDungeonNumEncounters(dungeonID)
			local doneToday = GetLFGDungeonRewards(dungeonID)

			local status = completed
			if available ~= 1 or EXPANSION_LEVEL < expansionLevel or playerLevel < minLevel or playerLevel > maxLevel then
				-- not available
				local _, reason, info1, info2 = GetLFDLockInfo(dungeonID, 1)
				status = string.format('%s:%s:%s', reason or '', info1 or '', info2 or '')
				status = strtrim(status, ':') -- trim trailing ::
			end

			local dungeonReset = 0
			if available == 1 and (numDefeated > 0 or doneToday) then
				dungeonReset = isWeekly and addon.GetNextMaintenance() or (time() + GetQuestResetTime())
			end

			if status == 0 and dungeonReset == 0 and numDefeated == 0 then
				-- dungeon available but no lockout
				-- lfgs[dungeonID] = 0
			elseif status ~= 0 and status ~= 1 then
				-- dungeon not available, store only the reason
				lfgs[dungeonID] = tonumber(status) or status
			else
				-- dungeon has lockout info
				local defeatedBosses = 0
				for encounterIndex = 1, numBosses do
					local _, _, defeated = GetLFGDungeonEncounterInfo(dungeonID, encounterIndex)
					defeatedBosses = bit.bor(defeatedBosses, defeated and 2^(encounterIndex-1) or 0)
				end
				-- marker so we know how many bosses there are
				defeatedBosses = bit.bor(defeatedBosses, 2^numBosses)

				lfgs[dungeonID] = string.format('%s|%d|%d', status, dungeonReset, defeatedBosses)
			end
		end
	end
	lockouts.ThisCharacter.lastUpdate = time()
end

local function UpdateSavedBosses()
	local bosses = lockouts.ThisCharacter.WorldBosses
	wipe(bosses)
	for i = 1, GetNumSavedWorldBosses() do
		local name, id, reset = GetSavedWorldBossInfo(i)
		bosses[id] = time() + reset
	end
	lockouts.ThisCharacter.lastUpdate = time()
end

local function UpdateSavedInstances()
	local instances = lockouts.ThisCharacter.Instances
	wipe(instances)
	local instanceLinks = lockouts.ThisCharacter.InstanceLinks
	wipe(instanceLinks)

	for index = 1, GetNumSavedInstances() do
		local lockout = GetSavedInstanceChatLink(index)
		-- local guid, instanceID, difficulty, defeatedBosses = lockout:match('instancelock:([^:]+):([^:]+):([^:])+:([^:]+)')
		--      instanceID, defeatedBosses = tonumber(instanceID), tonumber(defeatedBosses)
		-- * defeatedBosses is a bitmap, but boss order differs from instance encounter order
		-- * instanceID is unique, but not found anywhere else ingame, especially not in EJ/API
		-- * instanceName does not match that of the EJ either

		local instanceName, lockoutID, resetsIn, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numBosses, numDefeatedBosses = GetSavedInstanceInfo(index)
		local reset = (locked and resetsIn > 0) and (resetsIn + time()) or 0
		-- local identifier = string.format("%x%x", instanceIDMostSig, lockoutID) -- used in RaidFrame

		local killedBosses = 0
		for encounterIndex = 1, numBosses do
			local _, _, defeated = GetSavedInstanceEncounterInfo(index, encounterIndex)
			killedBosses = bit.bor(killedBosses, defeated and 2^(encounterIndex-1) or 0)
		end
		-- marker so we know how many bosses there are
		killedBosses = bit.bor(killedBosses, 2^numBosses)

		instances[lockoutID] = strjoin('|', instanceName, difficulty, reset, extended and 1 or 0, isRaid and 1 or 0, killedBosses)
		instanceLinks[lockoutID] = lockout
	end
	lockouts.ThisCharacter.lastUpdate = time()
end

local encounters = {}
-- @returns <bool:encounter1Dead>, <bool:encounter2Dead>,  ...
local function GetEncounters(defeatedBosses)
	wipe(encounters)
	local encounterIndex = 1
	while defeatedBosses and defeatedBosses > 1 do -- ignore marker bit
		encounters[encounterIndex] = defeatedBosses%2 == 1
		encounterIndex = encounterIndex + 1
		defeatedBosses = bit.rshift(defeatedBosses, 1)
	end
	return unpack(encounters)
end

-- Mixins
-- Looking for Group
function lockouts.IterateLFGs(character, typeID, subTypeID)
	local lfgIndex, lfgType = 0, next(LFGInfos, nil)
	return function()
		while true do
			lfgIndex = lfgIndex + 1
			if not lfgType or not LFGInfos[lfgType] then
				-- invalid lfgType
				return nil
			end
			local instanceID, instanceName, instanceType, instanceSubType = LFGInfos[lfgType][2](lfgIndex)
			if not instanceID then
				-- no more instances in this group, try next one
				lfgType  = next(LFGInfos, lfgType)
				lfgIndex = 0
			elseif (typeID and typeID ~= instanceType) or (subTypeID and subTypeID ~= instanceSubType) then
				-- instance does not math specified types
				lfgIndex = lfgIndex + 1
			else
				-- found a match!
				return instanceID, instanceName, lockouts.GetLFGInfo(character, instanceID)
			end
		end
	end
end

function lockouts.GetLFGInfo(character, instanceID)
	local instanceInfo = character.LFGs[instanceID]
	if not instanceInfo then return end
	instanceInfo = tostring(instanceInfo)

	local status, reset, defeatedBosses = strsplit('|', instanceInfo)
	      defeatedBosses = tonumber(defeatedBosses or '') or 0
	local lockedReason, subReason1, subReason2 = strsplit(':', status or '')
	      lockedReason = tonumber(lockedReason) or nil

	if lockedReason == 0 or lockedReason == 1 then
		status = lockedReason == 1 and true or false
	elseif lockedReason == 1029 or lockedReason == 1030 or lockedReason == 1031 then
		status = _G['INSTANCE_UNAVAILABLE_OTHER_TOO_SOON']
	else
		local reasonText = _G['INSTANCE_UNAVAILABLE_SELF_'..(LFG_INSTANCE_INVALID_CODES[lockedReason] or 'OTHER')]
		status = string.format(reasonText, subReason1, subReason2)
	end

	local numDefeated, numBosses = 0, 0
	while defeatedBosses and defeatedBosses > 1 do -- ignore marker bit
		numDefeated = numDefeated + (defeatedBosses%2)
		numBosses = numBosses + 1
		defeatedBosses = bit.rshift(defeatedBosses, 1)
	end

	return status, tonumber(reset), numDefeated, numBosses
end

function lockouts.GetLFGEncounters(character, instanceID)
	local instanceInfo = character.LFGs[instanceID]
	if not instanceInfo then return end
	instanceInfo = tostring(instanceInfo)

	local _, _, defeatedBosses = strsplit('|', instanceInfo)
	            defeatedBosses = tonumber(defeatedBosses or '') or 0
	return GetEncounters(defeatedBosses)
end

-- World Bosses
function lockouts.GetNumSavedWorldBosses(character)
	return #character.WorldBosses
end

function lockouts.GetSavedWorldBosses(character)
	return character.WorldBosses
end

function lockouts.IsWorldBossKilledBy(character, bossID)
	local expires = character.WorldBosses[bossID]
	return expires
end

-- Instance Lockouts
function lockouts.GetNumInstanceLockouts(character)
	local total, locked = 0, 0
	for lockoutID, lockoutData in pairs(character.Instances) do
		local _, _, instanceReset = strsplit('|', lockoutData)
		if instanceReset == '0' then
			locked = locked + 1
		end
		total = total + 1
	end
	return total, locked
end

local sortTable = {}
function lockouts.IterateInstanceLockouts(character)
	local lockoutID = nil
	return function()
		local lockoutLink
		lockoutID, lockoutLink = next(character.InstanceLinks, lockoutID)
		return lockoutID, lockoutLink
	end
end

function lockouts.GetInstanceLockoutLink(character, lockoutID)
	return lockoutID and character.InstanceLinks[lockoutID]
end
function lockouts.GetInstanceLockoutInfo(character, lockoutID)
	local lockoutData = lockoutID and character.Instances[lockoutID]
	if not lockoutData then return end

	local instanceName, difficulty, instanceReset, extended, isRaid, defeatedBosses = strsplit('|', lockoutData)
	local defeatedBosses = tonumber(defeatedBosses)
	local numDefeated, numBosses = 0, 0
	while defeatedBosses and defeatedBosses > 1 do -- ignore marker bit
		numDefeated = numDefeated + (defeatedBosses%2)
		numBosses = numBosses + 1
		defeatedBosses = bit.rshift(defeatedBosses, 1)
	end

	return instanceName, tonumber(difficulty), tonumber(instanceReset), extended == '1', isRaid == '1', numDefeated, numBosses
end

function lockouts.GetInstanceLockoutEncounters(character, lockoutID)
	local lockoutData = lockoutID and character.Instances[lockoutID]
	if not lockoutData then return end

	local _, _, _, _, _, defeatedBosses = strsplit('|', lockoutData)
	                     defeatedBosses = tonumber(defeatedBosses)
	return GetEncounters(defeatedBosses)
end

function lockouts.IsEncounterDefeated(character, lockoutID, encounterIndex)
	local lockoutData = lockoutID and character.Instances[lockoutID]
	if not lockoutData or not encounterIndex then return end
	local _, _, _, _, _, defeatedBosses = strsplit('|', lockoutData)
	return bit.band(defeatedBosses, 2^(encounterIndex-1)) > 0
end

-- Weekly Quests
function lockouts.IsWeeklyQuestCompletedBy(character, questID)
	local characterKey = type(character) == 'string' and character or DataStore:GetCurrentCharacterKey()
	local _, lastUpdate = DataStore:GetQuestHistoryInfo(characterKey)
	local lastMaintenance = addon.GetLastMaintenance()
	if not (lastUpdate and lastMaintenance) or lastUpdate < lastMaintenance then
		return false
	else
		return DataStore:IsQuestCompletedBy(characterKey, questID) or false
	end
end

-- setup
local PublicMethods = {
	-- Looking for Group
	IterateLFGs              = lockouts.IterateLFGs,
	GetLFGInfo               = lockouts.GetLFGInfo,
	GetLFGEncounters         = lockouts.GetLFGEncounters,
	-- World Bosses
	GetSavedWorldBosses      = lockouts.GetSavedWorldBosses,
	GetNumSavedWorldBosses   = lockouts.GetNumSavedWorldBosses,
	IsWorldBossKilledBy      = lockouts.IsWorldBossKilledBy,
	-- Instance Lockouts
	IterateInstanceLockouts  = lockouts.IterateInstanceLockouts,
	GetNumInstanceLockouts   = lockouts.GetNumInstanceLockouts,
	GetInstanceLockoutInfo   = lockouts.GetInstanceLockoutInfo,
	GetInstanceLockoutLink   = lockouts.GetInstanceLockoutLink,
	GetInstanceLockoutEncounters = lockouts.GetInstanceLockoutEncounters,
	IsEncounterDefeated      = lockouts.IsEncounterDefeated,

	-- Weeky Quests
	IsWeeklyQuestCompletedBy = lockouts.IsWeeklyQuestCompletedBy, -- TODO: does not really belong here?
}

function lockouts:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end
end

function lockouts:OnEnable()
	self:RegisterEvent('LFG_LOCK_INFO_RECEIVED', UpdateLFGStatus)
	self:RegisterEvent('UPDATE_INSTANCE_INFO', function()
		UpdateSavedBosses()
		UpdateSavedInstances()
	end)
	RequestRaidInfo()

	-- TODO: apply to instance lockous as well
	-- clear expired
	local now = time()
	for characterKey, character in pairs(self.db.global.Characters) do
		for dungeonID, data in pairs(character.LFGs) do
			local status, reset, numDefeated = strsplit('|', data)
			              reset = tonumber(reset)
			if status ~= '1' and status ~= '0' then
				character.LFGs[dungeonID] = strtrim(status, ':')
			elseif reset and reset ~= 0 and reset < now then
				-- had lockout, lockout expired, LFG is available
				character.LFGs[dungeonID] = 0
			end
		end
		for lockoutID, lockoutData in pairs(character.Instances) do
			-- instances[lockoutID] =
			local a, b, reset, d, e, f = strsplit('|', lockoutData)
			            reset = tonumber(reset)
			if reset and reset ~= 0 and reset < now then
				character.Instances[lockoutID] = strjoin('|', a, b, 0, d, e, f)
			end
		end
	end
end

function lockouts:OnDisable()
	self:UnregisterEvent('LFG_LOCK_INFO_RECEIVED')
	self:UnregisterEvent('UPDATE_INSTANCE_INFO')
end
