local addonName, addon, _ = ...
local specializations = addon:NewModule('Specializations', 'AceEvent-3.0')

-- GLOBALS: _G, DataStore, LibStub
-- GLOBALS: GetNumSpecializations, GetSpecialization, GetSpecializationInfo, GetSpecializationMasterySpells
-- GLOBALS: GetTalentInfo, GetTalentInfoByID, GetTalentLink, GetMaxTalentTier, GetTalentRowSelectionInfo
-- GLOBALS: type, strsplit, tonumber, time, select, pairs, table, strjoin, unpack, wipe

local defaults = {
	global = {
		Characters = {
			['*'] = { -- character key, i.e. "Account.Realm.Name"
				['*'] = { -- specID
					talents = { -- keyed by tierIndex
						['*'] = nil, -- talentID -or- false when unselected -or- nil when not available
					},
					specID = nil,
					mastery = nil,
				},
				activeSpecGroup = 1,
				lastUpdate = nil,
			}
		},
		-- list of class talents
		--[[ talents = {
			['*'] = { -- class name
				-- [index] = spellID,
			},
		}, --]]
	},
}

-- --------------------------------------------------------
--  Scanning Functions
-- --------------------------------------------------------
local function ScanTalents()
	local character = specializations.ThisCharacter
	for specNum = 1, GetNumSpecializations() do
		local data = character[specNum]
		data.specID = GetSpecializationInfo(specNum)
		data.mastery = GetSpecializationMasterySpells(specNum)

		for tier = 1, GetMaxTalentTier() do
			local column, isUnspent, selection = 1, true, nil
			local talentID, name, texture, selected, available = GetTalentInfo(tier, column, 1)
			while talentID do
				-- GetTalentInfoBySpecialization(specNum, tier, column)
				if selected then selection = talentID end
				if selected or not available then isUnspent = false end
				column = column + 1
				talentID, name, texture, selected, available = GetTalentInfo(tier, column, 1)
			end
			if available and isUnspent then
				data.talents[tier] = false
			else
				data.talents[tier] = selection or nil
			end
		end
	end
	character.activeSpecGroup = GetSpecialization()
	character.lastUpdate = time()
end

-- --------------------------------------------------------
--  Specializations
-- --------------------------------------------------------
-- returns the specialization id (3 digits) as used by API functions
function specializations.GetSpecializationID(character, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character[specNum]
	return specData.specID
end

-- returns the specialization index (1-4)
function specializations.GetSpecialization(character, specNum)
	specNum = specNum or character.activeSpecGroup
	local specializationID = specializations.GetSpecializationID(character, specNum)
	for specIndex = 1, 4 do -- GetNumSpecializations()
		if GetSpecializationInfo(specIndex) == specializationID then
			return specIndex
		end
	end
end

-- returns the specialization mastery spellID
function specializations.GetSpecializationMastery(character, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character['spec'..specNum]
	if not specData then return end
	return specData.mastery
end

function specializations.GetNumSpecializations(character)
	return #character
end

-- returns the currently active specialization group
function specializations.GetActiveSpecialization(character)
	return character.activeSpecGroup
end

-- --------------------------------------------------------
--  Talents
-- --------------------------------------------------------
function specializations.GetNumUnspentTalents(character, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character[specNum]
	local numUnspent = 0
	for tier = 1, GetMaxTalentTier() do
		local selection = specData.talents[tier]
		numUnspent = numUnspent + (selection == false and 1 or 0)
	end
	return numUnspent
end

function specializations.GetTalentSelection(character, tier, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character[specNum]
	local talentID = specData and specData.talents[tier]
	return talentID
end

function specializations.GetTalentInfo(character, tier, specNum)
	local talentID = specializations.GetTalentSelection(character, tier, specNum)
	if talentID then
		return GetTalentInfoByID(talentID)
	end
end

-- --------------------------------------------------------
--  Legacy Functions
-- --------------------------------------------------------
-- GLOBALS: GetNumClasses, GetClassInfo, GetSpecializationInfoForClassID
-- GLOBALS: rawget, rawset, math
local classIDs = setmetatable({}, {
	__index = function(self, class)
		local classID = rawget(self, class)
		if classID then return classID end

		for i = 1, GetNumClasses() do
			local _, checkClass, classID = GetClassInfo(i)
			if checkClass == class then
				class = classID
				break
			end
		end

		if classID then
			rawset(self, class, classID)
			return classID
		end
	end
})

-- these are no longer really necessary but in here for compatibility purposes
-- DEPRECATED: use GetTalentLink(talentIndex, true, classIndex) instead
local function _GetTalentLink(talentID)
	return GetTalentLink(talentID)
end
local talentsPerTier = _G.NUM_TALENT_COLUMNS
local function _GetTalentRank(character, index, specNum, compatibilityMode)
	local tree
	if compatibilityMode then
		tree, index = index, compatibilityMode
	end

	specNum = specNum or character.activeSpecGroup
	local tier = math.ceil(index / talentsPerTier)
	return specializations.GetTalentSelection(character, tier, specNum) == index and 1 or 0
end
local function _GetClassTrees(class)
	local class = classIDs[class]
	if type(class) == 'number' then
		local specID = 1
		return function()
			local id, specName = GetSpecializationInfoForClassID(class, specID)
			specID = specID + 1
			-- returning name first guarantees backwards compatibility
			return specName, specID - 1
		end
	end
end
local function _GetTreeInfo(class, tree)
	if type(tree) ~= 'number' then return end
	local class = classIDs[class]
	if type(class) == 'number' then
		local _, _, _, icon, background = GetSpecializationInfoForClassID(class, tree)
		return icon, background
	end
end
local function _GetTreeNameByID(class, id)
	local class = classIDs[class]
	if type(class) == 'number' then
		local _, name = GetSpecializationInfoForClassID(class, id)
		return name
	end
end

-- --------------------------------------------------------
--  Setup
-- --------------------------------------------------------
local PublicMethods = {
	-- specialization
	GetSpecialization    = specializations.GetSpecialization,
	GetSpecializationID  = specializations.GetSpecializationID,
	GetSpecializationMastery = specializations.GetSpecializationMastery,
	GetNumSpecializations = specializations.GetNumSpecializations,
	-- talents
	GetNumUnspentTalents = specializations.GetNumUnspentTalents,
	GetTalentSelection   = specializations.GetTalentSelection,
	GetTalentInfo        = specializations.GetTalentInfo,
	GetActiveSpecialization = specializations.GetActiveSpecialization,

	-- legacy functions
	GetActiveTalents     = specializations.GetActiveSpecialization,
	GetClassTrees        = _GetClassTrees,
	GetTreeInfo          = _GetTreeInfo,
	GetTreeNameByID      = _GetTreeNameByID,
	GetTalentRank        = _GetTalentRank,
}
local nonCharacterMethods = { 'GetClassTrees', 'GetTreeInfo', 'GetTreeNameByID'}

function specializations:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods, true)
	for funcName, funcImpl in pairs(PublicMethods) do
		if not tContains(nonCharacterMethods, funcName) then
			DataStore:SetCharacterBasedMethod(funcName)
		end
	end
end

-- *** Event Handlers ***
function specializations:OnEnable()
	local initialized
	self:RegisterEvent('PLAYER_LOGIN', function(event)
		ScanTalents()
		self:UnregisterEvent(event)
	end)
	self:RegisterEvent('PLAYER_TALENT_UPDATE', ScanTalents)
	-- Unspent talent points via arg1 in CHARACTER_POINTS_CHANGED?
end

function specializations:OnDisable()
	self:UnregisterEvent('PLAYER_LOGIN')
	self:UnregisterEvent('PLAYER_TALENT_UPDATE')
end
