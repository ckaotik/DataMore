local addonName, ns = ...

-- GLOBALS: _G, LibStub, DataStore, EXPANSION_LEVEL
-- GLOBALS: IsAddOnLoaded, UnitLevel, GetQuestResetTime, GetRFDungeonInfo, GetNumRFDungeons, GetLFGDungeonRewardCapInfo, GetLFGDungeonNumEncounters, GetLFGDungeonRewards, GetLFDLockInfo, LFG_INSTANCE_INVALID_CODES
-- GLOBALS: type, next, wipe, pairs, time, date, string, tonumber, math, strsplit

local addonName  = "DataMore_Lockouts"
   _G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local addon = _G[addonName]
local thisCharacter = DataStore:GetCharacter()

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				LFGs = {},
			}
		}
	}
}

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
	local playerLevel = UnitLevel("player")

	local lfgs = addon.ThisCharacter.LFGs
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
				status = string.format("%s:%s:%s", reason or '', info1 or '', info2 or '')
			end

			local dungeonReset = 0
			if numDefeated > 0 or doneToday then
				dungeonReset = isWeekly and ns.GetNextMaintenance() or (time() + GetQuestResetTime())
			end

			if status == 0 and dungeonReset == 0 and numDefeated == 0 then
				lfgs[dungeonID] = 0
			else
				lfgs[dungeonID] = string.format("%s|%d|%d", status, dungeonReset, numDefeated)
			end
		end
	end
	addon.ThisCharacter.lastUpdate = time()
end

-- Mixins
local function _GetLFGInfo(character, dungeonID)
	local instanceInfo = character.LFGs[dungeonID]
	if not instanceInfo then return end

	local status, reset, numDefeated = string.split("|", instanceInfo)
	status = tonumber(status) or status
	if type(status) == "string" then
		local playerName, lockedReason, subReason1, subReason2 = strsplit(":", status)
		if lockedReason == 1029 or lockedReason == 1030 or lockedReason == 1031 then
			status = _G["INSTANCE_UNAVAILABLE_OTHER_TOO_SOON"]
		else
			status = string.format(_G["INSTANCE_UNAVAILABLE_SELF_"..(LFG_INSTANCE_INVALID_CODES[lockedReason] or "OTHER")],
				playerName, subReason1, subReason2)
		end
	else
		status = status == 1 and true or false
	end

	return status, tonumber(reset), tonumber(numDefeated)
end

local function _GetLFGs(character)
	local lastKey = nil
	return function()
		local dungeonID, info = next(character.LFGs, lastKey)
		lastKey = dungeonID

		return dungeonID, _GetLFGInfo(character, dungeonID)
	end
end

-- setup
local PublicMethods = {
	GetCurrencyCaps = _GetCurrencyCaps,
	GetCurrencyCapInfo = _GetCurrencyCapInfo,
	GetLFGs = _GetLFGs,
	GetLFGInfo = _GetLFGInfo,
	GetCurrencyWeeklyAmount = _GetCurrencyWeeklyAmount,
	IsWeeklyQuestCompletedBy = _IsWeeklyQuestCompletedBy,
}

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)

	DataStore:RegisterModule(addonName, addon, PublicMethods)
	DataStore:SetCharacterBasedMethod("GetCurrencyCaps")
	DataStore:SetCharacterBasedMethod("GetCurrencyCapInfo")
	DataStore:SetCharacterBasedMethod("GetLFGs")
	DataStore:SetCharacterBasedMethod("GetLFGInfo")
	DataStore:SetCharacterBasedMethod("GetCurrencyWeeklyAmount")
	DataStore:SetCharacterBasedMethod("IsWeeklyQuestCompletedBy")
end

function addon:OnEnable()
	addon:RegisterEvent("LFG_LOCK_INFO_RECEIVED", UpdateLFGStatus)

	-- clear expired
	local now = time()
	for characterKey, character in pairs(addon.Characters) do
		for dungeonID, data in pairs(character.LFGs) do
			local status, reset, numDefeated = strsplit("|", data)
			reset = tonumber(reset)
			if reset and reset ~= 0 and reset < now and tonumber(status) then
				-- had lockout, lockout expired, LFG is available
				character.LFGs[dungeonID] = 0
			end
		end
	end
end

function addon:OnDisable()
	addon:UnregisterEvent("LFG_LOCK_INFO_RECEIVED")
end
