local addonName, addon = ...
local weeklies   = addon:NewModule('Weeklies', 'AceEvent-3.0') -- 'AceConsole-3.0'

-- GLOBALS: LibStub, DataStore
-- GLOBALS: IsAddOnLoaded, GetCurrencyListSize, GetCurrencyListLink, GetCurrencyInfo
-- GLOBALS: wipe, time, tonumber, string, math, pairs

local thisCharacter = DataStore:GetCharacter()

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				WeeklyCurrency = {},
				WorldBosses = {},
			}
		}
	}
}

--[[
num = GetNumSavedWorldBosses()
name, id, reset = GetSavedWorldBossInfo(i)
instanceID for worldbosses: 322
WORLD_BOSS_FOUR_CELESTIALS = "The Four Celestials";
WORLD_BOSS_GALLEON = "Galleon";
WORLD_BOSS_NALAK = "Nalak";
WORLD_BOSS_OONDASTA = "Oondasta";
WORLD_BOSS_ORDOS = "Ordos";
WORLD_BOSS_SHA_OF_ANGER = "Sha of Anger";
--]]

local function UpdateSavedBosses()
	local bosses = weeklies.ThisCharacter.WorldBosses
	wipe(bosses)
	for i = 1, GetNumSavedWorldBosses() do
		local name, id, reset = GetSavedWorldBossInfo(i)
		bosses[id] = time() + reset
	end
end

local function _GetSavedWorldBosses(character)
	return character.WorldBosses
end

local function _GetNumSavedWorldBosses(character)
	return #character.WorldBosses
end

local function _IsWorldBossKilledBy(character, bossID)
	return character.WorldBosses[bossID]
end

local function UpdateWeeklyCap()
	if GetCurrencyListSize() < 1 then return end
	local currencies = weeklies.ThisCharacter.WeeklyCurrency
	wipe(currencies)

	for i = 1, GetCurrencyListSize() do
		local currencyLink = GetCurrencyListLink(i)
		if currencyLink then
			local currencyID = tonumber(string.match(currencyLink, 'currency:(%d+)'))
			local _, currentAmount, _, weeklyAmount, weeklyMax, totalMax = GetCurrencyInfo(currencyID)
			if weeklyMax and weeklyMax > 0 then
				currencies[currencyID] = weeklyAmount
			end
		end
	end
	weeklies.ThisCharacter.lastUpdate = time()
end

local function _GetCurrencyCaps(character)
	return character.WeeklyCurrency
end

local function _GetCurrencyWeeklyAmount(character, currencyID)
	local lastMaintenance = addon.GetLastMaintenance()
	if character == thisCharacter then
		-- always hand out live data as we might react to CURRENCY_DISPLAY_UPDATE later than our requestee
		UpdateWeeklyCap()
	end
	if lastMaintenance and character.lastUpdate and character.lastUpdate >= lastMaintenance then
		return character.WeeklyCurrency[currencyID]
	else
		return 0
	end
end

local function _GetCurrencyCapInfo(character, currencyID, characterKey)
	-- DataStore:GetCharacterTable(module, name, realm, account)
	local weeklyAmount = _GetCurrencyWeeklyAmount(character, currencyID)
	local name, _, _, _, weeklyMax, totalMax = GetCurrencyInfo(currencyID)

	local currentAmount
	if IsAddOnLoaded('DataStore_Currencies') then
		_, _, currentAmount = DataStore:GetCurrencyInfoByName(characterKey, name)
	end

	if totalMax%100 == 99 then -- valor and justice caps are weird
		totalMax  = math.floor(totalMax/100)
		weeklyMax = math.floor(weeklyMax/100)
	end

	return currentAmount, totalMax, weeklyAmount, weeklyMax
end

local function _IsWeeklyQuestCompletedBy(character, questID)
	local characterKey = type(character) == 'string' and character or character.key
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
	GetCurrencyCaps = _GetCurrencyCaps,
	GetCurrencyCapInfo = _GetCurrencyCapInfo,
	GetCurrencyWeeklyAmount = _GetCurrencyWeeklyAmount,
	GetSavedWorldBosses = _GetSavedWorldBosses,
	GetNumSavedWorldBosses = _GetNumSavedWorldBosses,
	IsWorldBossKilledBy = _IsWorldBossKilledBy,
	IsWeeklyQuestCompletedBy = _IsWeeklyQuestCompletedBy,
}

function weeklies:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', AddonDB_Defaults)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for funcName, funcImpl in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(funcName)
	end

	-- we need this as an override, since we need access to the characterKey
	addon.RegisterOverride(self, 'IsWeeklyQuestCompletedBy', _IsWeeklyQuestCompletedBy, 'character')
end

function weeklies:OnEnable()
	self:RegisterEvent('CURRENCY_DISPLAY_UPDATE', UpdateWeeklyCap)
	-- TODO: track world boss kills
	--[[self:RegisterEvent('QUEST_LOG_UPDATE', function()
		if GetNextMaintenance() then
			UpdateWeeklyCap()
			self:UnregisterEvent('QUEST_LOG_UPDATE')
		end
	end) --]]
end
function weeklies:OnDisable()
	self:UnregisterEvent('CURRENCY_DISPLAY_UPDATE')
	-- self:UnregisterEvent('QUEST_LOG_UPDATE')
end
