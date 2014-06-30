local addonName, addon, _ = ...
local quests = addon:NewModule('Quests', 'AceEvent-3.0') -- 'AceConsole-3.0'

local characters    = DataStore:GetCharacters()
local thisCharacter = DataStore:GetCharacter()
local emptyTable = {}

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				QuestProgress = {},
			}
		}
	}
}

local function _GetAchievementProgress(character, achievementID)
	local characterKey = type(character) == 'string' and character or character.key

	local _, _, _, completed, _, _, _, _, flags = GetAchievementInfo(achievementID)
	local isShared = bit.band(flags, ACHIEVEMENT_FLAGS_ACCOUNT) == ACHIEVEMENT_FLAGS_ACCOUNT

	local achievementProgress = 0
	local achievementGoal = 0

	for index = 1, GetAchievementNumCriteria(achievementID) do
		local _, _, _, _, requiredQuantity,_, _, _, quantityString = GetAchievementCriteriaInfo(achievementID, index)
		local requiredQuantityString = tonumber( quantityString:match('/%s*(%d+)') or '' )
		if requiredQuantityString and requiredQuantityString ~= requiredQuantity then
			-- fix currencies being multiplied by 100
			requiredQuantity = requiredQuantityString
		end

		local _, critCompleted, progress = DataStore:GetCriteriaInfo(characterKey, achievementID, index, isShared)
		achievementProgress = achievementProgress + (critCompleted and requiredQuantity or progress or 0)
		achievementGoal     = achievementGoal + requiredQuantity
	end
	return achievementProgress, achievementGoal, isShared
end

local function GetReputationProgress(character, faction, minReputation)
	local characterKey = type(character) == 'string' and character or character.key

	local factionName = GetFactionInfoByID(faction)
	local _, _, currentReputation = DataStore:GetRawReputationInfo(characterKey, factionName)

	return currentReputation, minReputation
end

-- [questID][criteriaIndex] = {handler, args, ...}
local progressHandler = {
	[32474] = { -- test of valor (alliance)
		[1] = {_GetAchievementProgress, 8031}
	},
	[32476] = { -- test of valor (horde)
		[1] = {_GetAchievementProgress, 8031}
	},
	[31468] = { -- trial of the black prince (honored)
		[1] = {GetReputationProgress, 1359, 9000}
	},
	[32429] = { -- the prince's pursuit (horde, revered)
		[1] = {GetReputationProgress, 1359, 21000}
	},
	[32374] = { -- the prince's pursuit (alliance, revered)
		[1] = {GetReputationProgress, 1359, 21000}
	},
	[32592] = { -- i need a champion (exhalted)
		[1] = {GetReputationProgress, 1359, 42000}
	},
	[33342] = { -- Drive Back The Flame (shaohao honored)
		[1] = {GetReputationProgress, 1492, 9000}
	},
}

local function _GetQuestProgress(character, questID)
	return character.QuestProgress[questID] or emptyTable
end

local function _GetQuestProgressPercentage(character, questID)
	local data = _GetQuestProgress(character, questID)

	local current, max = 0, 0
	for criteriaIndex, criteriaProgress in ipairs(data) do
		local critCurrent, critMax
		local objective, progress = criteriaProgress:match('^(.+): ([^:]+)$')
		if progress then
			critCurrent, critMax = string.split('/', progress)
		end
		current = current + (critCurrent and tonumber(critCurrent) or 0)
		max     = max     + (critMax     and tonumber(critMax)     or 1)
	end

	if data[0] then
		-- money required
		local characterMoney = DataStore:GetMoney(character.key)
		current = current + math.min(characterMoney, data[0])
		max     = max     + data[0]
	end

	if max == 0 then
		return 0
	else
		return current / max
	end
end

local function UpdateQuestProgress()
	local questProgress = quests.ThisCharacter.QuestProgress
	wipe(questProgress)

	for questIndex = 1, (GetNumQuestLogEntries()) do
		local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID, startEvent, displayQuestID = GetQuestLogTitle(questIndex)

		-- print('scanning', questIndex, GetQuestLogTitle(questIndex))
		-- /spew DataMore_Quests.ThisCharacter.QuestProgress[29433]

		if not isHeader then
			questProgress[questID] = {}

			local requiredMoney = GetQuestLogRequiredMoney(questIndex)
			if requiredMoney > 0 then
				questProgress[questID][0] = requiredMoney
			end

			local numObjectives = GetNumQuestLeaderBoards(questIndex)
			for i = 1, numObjectives do
				local text, objectiveType, finished = GetQuestLogLeaderBoard(i, questIndex)
				if not text:find(': .-/.-') then
					text = text .. ': ' .. (finished and 1 or 0) .. '/1'
				end

				if not finished and progressHandler[questID] and progressHandler[questID][i] then
					local current, goal = progressHandler[questID][i][1](thisCharacter,
						select(2, unpack(progressHandler[questID][i])))
					local objective = text:match('^(.+): [^:]+$')

					questProgress[questID][i] = string.format('%s: %s/%s', objective, current or 0, goal or 1)
				else
					questProgress[questID][i] = text
				end
			end
		end
	end

	quests.ThisCharacter.lastUpdate = time()
end

-- setup
local PublicMethods = {
	GetQuestProgress = _GetQuestProgress,
	GetQuestProgressPercentage = _GetQuestProgressPercentage,
	GetAchievementProgress = _GetAchievementProgress, -- TODO: FIXME: does not belong here
}

function quests:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', AddonDB_Defaults)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	DataStore:SetCharacterBasedMethod('GetQuestProgress')
	DataStore:SetCharacterBasedMethod('GetQuestProgressPercentage')
	DataStore:SetCharacterBasedMethod('GetAchievementProgress')

	for methodName, method in pairs(PublicMethods) do
		addon.RegisterOverride(self, methodName, method, 'character')
	end
end

function quests:OnEnable()
	self:RegisterEvent('PLAYER_ALIVE', UpdateQuestProgress)
	self:RegisterEvent('UNIT_QUEST_LOG_CHANGED', UpdateQuestProgress)
	-- self:RegisterEvent("QUEST_COMPLETE", UpdateQuestProgress)
end

function quests:OnDisable()
	self:UnregisterEvent('PLAYER_ALIVE')
	self:UnregisterEvent('UNIT_QUEST_LOG_CHANGED')
	-- self:UnregisterEvent("QUEST_COMPLETE")
end
