local addonName, addon = ...
local lockouts = addon:NewModule('Lockouts', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore, EXPANSION_LEVEL
-- GLOBALS: IsAddOnLoaded, UnitLevel, GetQuestResetTime, GetRFDungeonInfo, GetNumRFDungeons, GetLFGDungeonRewardCapInfo, GetLFGDungeonNumEncounters, GetLFGDungeonRewards, GetLFDLockInfo, LFG_INSTANCE_INVALID_CODES, GetNumSavedWorldBosses, GetSavedWorldBossInfo, GetNumSavedInstances, GetSavedInstanceInfo, GetLFGDungeonEncounterInfo
-- GLOBALS: type, next, wipe, pairs, time, date, string, tonumber, math, strsplit, strjoin, strtrim, bit

local thisCharacter = DataStore:GetCharacter()

-- *** Scanning functions ***
local LFGInfos = {
	-- GetNumX(), GetXInfo(index) returning same data as GetLFGDungeonInfo(dungeonID)
	GetNumRandomDungeons, GetLFGRandomDungeonInfo,
	GetNumRFDungeons, GetRFDungeonInfo,
	GetNumRandomScenarios, GetRandomScenarioInfo,
	GetNumFlexRaidDungeons, GetFlexRaidDungeonInfo
}
-- TYPEID_DUNGEON, TYPEID_RANDOM_DUNGEON
-- LFG_SUBTYPEID_DUNGEON, LFG_SUBTYPEID_HEROIC, LFG_SUBTYPEID_RAID, LFG_SUBTYPEID_SCENARIO

local function UpdateLFGStatus()
	-- TODO: group data by dungeon?
	local playerLevel = UnitLevel('player')

	local lfgs = lockouts.ThisCharacter.LFGs
	wipe(lfgs)
	for i = 1, #LFGInfos, 2 do
		local getNum, getInfo = LFGInfos[i], LFGInfos[i+1]
		for index = 1, getNum() do
			local dungeonID, _, _, _, minLevel, maxLevel, _, _, _, expansionLevel = getInfo(index)
			local _, _, completed, available, _, _, _, _, _, _, isWeekly = GetLFGDungeonRewardCapInfo(dungeonID)
			local _, numDefeated = GetLFGDungeonNumEncounters(dungeonID)
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
				lfgs[dungeonID] = 0
			elseif status ~= 0 and status ~= 1 then
				-- dungeon not available, story only the reason
				lfgs[dungeonID] = status
			else
				lfgs[dungeonID] = string.format('%s|%d|%d', status, dungeonReset, numDefeated)
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

	for index = 1, GetNumSavedInstances() do
		local instanceName, instanceID, instanceReset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numBosses, numDefeatedBosses = GetSavedInstanceInfo(index)

		local numEncounters, numCompleted = GetLFGDungeonNumEncounters(instanceID)
		if numCompleted > 0 then -- we'll also track expired ids
			local killedBosses = 0
			for encounterIndex = 1, numEncounters do
				local bossName, texture, isKilled = GetLFGDungeonEncounterInfo(instanceID, encounterIndex)
				if isKilled then
					killedBosses = bit.bor(killedBosses, 2^(encounterIndex-1))
				end
			end

			local instanceKey      = strjoin('|', instanceID, difficulty)
			instances[instanceKey] = strjoin('|', locked and (instanceReset + time()) or 0, extended, isRaid, killedBosses)
		end
	end
	lockouts.ThisCharacter.lastUpdate = time()
end

-- Mixins
-- Looking for Group
function lockouts.GetLFGInfo(character, dungeonID)
	local instanceInfo = character.LFGs[dungeonID]
	if not instanceInfo then return end

	local status, reset, numDefeated = strsplit('|', instanceInfo)
	local lockedReason, subReason1, subReason2 = strsplit(':', status)
	      lockedReason = tonumber(lockedReason) or nil

	if lockedReason == 0 or lockedReason == 1 then
		status = lockedReason == 1 and true or false
	elseif lockedReason == 1029 or lockedReason == 1030 or lockedReason == 1031 then
		status = _G['INSTANCE_UNAVAILABLE_OTHER_TOO_SOON']
	else
		local reasonText = _G['INSTANCE_UNAVAILABLE_SELF_'..(LFG_INSTANCE_INVALID_CODES[lockedReason] or 'OTHER')]
		status = string.format(reasonText, subReason1, subReason2)
	end

	return status, tonumber(reset), tonumber(numDefeated)
end

function lockouts.GetLFGs(character)
	local lastKey = nil
	return function()
		local dungeonID, info = next(character.LFGs, lastKey)
		lastKey = dungeonID

		return dungeonID, lockouts.GetLFGInfo(character, dungeonID)
	end
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

-- Insstance Lockouts
function lockouts.GetNumInstanceLockouts(character)
	local total, locked = 0, 0
	for instanceKey, instanceData in pairs(character.Instances) do
		local instanceReset = strsplit('|', instanceData)
		if instanceReset == '0' then
			locked = locked + 1
		end
		total = total + 1
	end
	return total, locked
end

function lockouts.GetInstanceLockoutInfo(character, instance, difficulty)
	if not instance or not difficulty then return end
	local instanceInfo = character.Instances[strjoin('|', instance, difficulty)]
	if not instanceInfo then return end

	local instanceReset, extended, isRaid, killedBosses = strsplit('|', instanceInfo)
	-- local resetsIn = instanceReset > 0 and (instanceReset - time()) or 0

	return tonumber(instanceReset), extended == '1', isRaid == '1', tonumber(killedBosses)
end

function lockouts.GetNumDefeatedEncounters(character, instance, difficulty)
	if not instance or not difficulty then return end
	local _, _, _, killedBosses = lockouts.GetInstanceLockoutInfo(character, instance, difficulty)
	local numKilled = 0
	while killedBosses > 0 do
		numKilled = numKilled + (killedBosses%2)
		killedBosses = bit.rshift(killedBosses, 1)
	end
	return numKilled
end

function lockouts.IsEncounterDefeated(character, instance, difficulty, encounterIndex)
	if not instance or not difficulty or not encounterIndex then return end
	local _, _, _, killedBosses = lockouts.GetInstanceLockoutInfo(character, instance, difficulty)
	return bit.band(killedBosses, 2^(encounterIndex-1)) > 0
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
	GetLFGs                  = lockouts.GetLFGs,
	GetLFGInfo               = lockouts.GetLFGInfo,
	-- World Bosses
	GetSavedWorldBosses      = lockouts.GetSavedWorldBosses,
	GetNumSavedWorldBosses   = lockouts.GetNumSavedWorldBosses,
	IsWorldBossKilledBy      = lockouts.IsWorldBossKilledBy,
	-- Instance Lockouts
	GetNumInstanceLockouts   = lockouts.GetNumInstanceLockouts,
	GetInstanceLockoutInfo   = lockouts.GetInstanceLockoutInfo,
	GetNumDefeatedEncounters = lockouts.GetNumDefeatedEncounters,
	IsEncounterDefeated      = lockouts.IsEncounterDefeated,
	-- Weeky Quests
	IsWeeklyQuestCompletedBy = lockouts.IsWeeklyQuestCompletedBy, -- TODO: does not really belong here?
}

function lockouts:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', {
		global = {
			Characters = {
				['*'] = {				-- ["Account.Realm.Name"]
					lastUpdate = nil,
					LFGs = {},
					WorldBosses = {},
					Instances = {},
				}
			}
		}
	}, true)

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
	-- UpdateSavedBosses()
	-- UpdateSavedInstances()

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
	end
end

function lockouts:OnDisable()
	self:UnregisterEvent('LFG_LOCK_INFO_RECEIVED')
	self:UnregisterEvent('UPDATE_INSTANCE_INFO')
end
