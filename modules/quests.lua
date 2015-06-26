local addonName, addon, _ = ...
local quests = addon:NewModule('Quests', 'AceEvent-3.0') -- 'AceConsole-3.0'

local emptyTable = {}

local defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				Quests = {
					['*'] = { -- keyed by questID
						['*'] = 0, -- using this line causes started quests w/o progress to not be tracked
					},
				},
			}
		}
	}
}
-- /spew DataMore:GetModule('Quests').ThisCharacter.Quests

local function _GetAchievementProgress(character, achievementID)
	local characterKey = type(character) == 'string' and character or DataStore:GetCurrentCharacterKey()

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
	local characterKey = type(character) == 'string' and character or DataStore:GetCurrentCharacterKey()

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
	local data = character.Quests[questID]
	local progress = 0
	if type(data) == 'number' then
		progress = data/100
	elseif data then
		local numCriteria = 0
		local text, objectiveType, completed, FALSE = GetQuestObjectiveInfo(questID, numCriteria + 1, false)
		while objectiveType do
			numCriteria = numCriteria + 1
			local criteriaProgress = data[numCriteria] or 0
			local goal = text and text:match('%d+/(%d+)') or 100
			      goal = goal*1
			if criteriaProgress > goal then
				criteriaProgress = goal
			end
			progress = progress + criteriaProgress/goal
			text, objectiveType, completed, FALSE = GetQuestObjectiveInfo(questID, numCriteria + 1, false)
		end
		if data.requiredMoney then
			numCriteria = numCriteria + 1
			local characterKey = DataStore:GetCurrentCharacterKey()
			local money = DataStore:GetMoney(characterKey) or 0
			if money >= data.requiredMoney then
				progress = progress + 1
			else
				progress = progress + money/data.requiredMoney
			end
		end
		progress = progress > 0 and (progress / numCriteria) or 0
	end
	return progress
end

local function UpdateQuestProgress()
	wipe(quests.ThisCharacter.Quests)

	local numRows, numQuests = GetNumQuestLogEntries()
	for questIndex = 1, numRows do
		local title, _, _, isHeader, _, isComplete, frequency, questID = GetQuestLogTitle(questIndex)

		if not isHeader and isComplete then
			quests.ThisCharacter.Quests[questID] = 100
		elseif not isHeader then
			quests.ThisCharacter.Quests[questID] = {}

			-- local progress = GetQuestProgressBarPercent(questID)
			local requiredMoney = GetQuestLogRequiredMoney(questIndex)
			if requiredMoney > 0 then
				quests.ThisCharacter.Quests[questID].requiredMoney = requiredMoney
			end

			local numObjectives = GetNumQuestLeaderBoards(questIndex)
			for i = 1, numObjectives do
				-- local text, objectiveType, completed, FALSE = GetQuestObjectiveInfo(questID, i, false)
				local text, objectiveType, completed = GetQuestLogLeaderBoard(i, questIndex)
				local progress, goal = completed and 100 or 0, 100
				if text then
					progress, goal = text:match('(%d+)/(%d+)')
					progress = progress and 1*progress or 0
					goal = goal and goal*1 or 100
				else
					print(title, isHeader, isComplete, frequency, questID, questIndex, text, '...', GetQuestProgressBarPercent(questID), GetQuestObjectiveInfo(questID, i, false))
				end
				if progress ~= 0 then
					quests.ThisCharacter.Quests[questID][i] = progress
				end
			end

			if not next(quests.ThisCharacter.Quests[questID]) then
				-- zero progress is zero progress
				quests.ThisCharacter.Quests[questID] = 0
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
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	DataStore:SetCharacterBasedMethod('GetQuestProgress')
	DataStore:SetCharacterBasedMethod('GetQuestProgressPercentage')
	DataStore:SetCharacterBasedMethod('GetAchievementProgress')
end

function quests:OnEnable()
	self:RegisterEvent('PLAYER_ALIVE', UpdateQuestProgress)
	self:RegisterEvent('UNIT_QUEST_LOG_CHANGED', UpdateQuestProgress)
	-- self:RegisterEvent("QUEST_COMPLETE", UpdateQuestProgress)
	UpdateQuestProgress()
end

function quests:OnDisable()
	self:UnregisterEvent('PLAYER_ALIVE')
	self:UnregisterEvent('UNIT_QUEST_LOG_CHANGED')
	-- self:UnregisterEvent("QUEST_COMPLETE")
end
