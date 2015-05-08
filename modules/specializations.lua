local addonName, addon, _ = ...
local specializations = addon:NewModule('Specializations', 'AceEvent-3.0')

-- GLOBALS: _G, DataStore, LibStub
-- GLOBALS: GetNumSpecGroups, GetSpecialization, GetSpecializationInfo, GetSpecializationMasterySpells
-- GLOBALS: GetNumGlyphSockets, GetGlyphSocketInfo, GetSpellInfo
-- GLOBALS: GetTalentInfo, GetTalentInfoByID, GetTalentLink, GetActiveSpecGroup, GetMaxTalentTier, GetTalentRowSelectionInfo
-- GLOBALS: type, strsplit, tonumber, time, select, pairs, table, strjoin, unpack, wipe

local defaults = {
	global = {
		Characters = {
			['*'] = { -- character key, i.e. "Account.Realm.Name"
				['*'] = { -- spec{specNum}
					talents = {
						-- [tierIndex] = talentID,
					},
					glyphs = {
						-- [socketID] = strjoin('|', glyphID, spellID),
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
		},
		-- list of class glyphs
		glyphs = {
			['*'] = { -- class name
				-- [index] = strjoin('|', glyphID, glyphType, icon, description),
			},
		}, --]]
	},
}

-- --------------------------------------------------------
--  Scanning Functions
-- --------------------------------------------------------
local function ScanTalents()
	local character = specializations.ThisCharacter
	for specNum = 1, GetNumSpecGroups() do
		local specIndex = GetSpecialization(nil, nil, specNum) or 0
		local data = character['spec' .. specNum]
		data.specID = GetSpecializationInfo(specIndex)
		data.mastery = GetSpecializationMasterySpells(specIndex)

		for tier = 1, GetMaxTalentTier() do
			local column, isUnspent, selection = 1, true, nil
			local talentID, name, texture, selected, available = GetTalentInfo(tier, column, specNum)
			while talentID do
				-- GetTalentInfoBySpecialization(specIndex, tier, column)
				if selected then selection = talentID end
				if selected or not available then isUnspent = false end
				column = column + 1
				talentID, name, texture, selected, available = GetTalentInfo(tier, column, specNum)
			end
			data.talents[tier] = not isUnspent and selection or false
		end
	end
	character.activeSpecGroup = GetActiveSpecGroup()
	character.lastUpdate = time()
end

-- scans which glyphs are used in which spec/socket
local function ScanGlyphs()
	local data = specializations.ThisCharacter
	for specNum = 1, GetNumSpecGroups() do
		local specData = data['spec'..specNum]
		wipe(specData.glyphs)

		for socket = 1, GetNumGlyphSockets() do
			local isAvailable, _, _, spellID, _, glyphID = GetGlyphSocketInfo(socket, specNum)
			if not isAvailable then
				specData.glyphs[socket] = nil
			elseif not glyphID then
				specData.glyphs[socket] = '0'
			else
				specData.glyphs[socket] = strjoin('|', glyphID, spellID or '')
			end
		end
	end
	data.lastUpdate = time()
end

-- --------------------------------------------------------
--  Specializations
-- --------------------------------------------------------
-- returns the specialization id (3 digits) as used by API functions
function specializations.GetSpecializationID(character, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character['spec'..specNum]
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

-- returns the currently active specialization group
-- named for backwards compatibility
function specializations.GetActiveTalents(character)
	return character.activeSpecGroup
end

-- --------------------------------------------------------
--  Glyphs
-- --------------------------------------------------------
function specializations.GetGlyphSocketInfo(character, specNum, socket)
	specNum = specNum or character.activeSpecGroup
	local specData = character['spec'..specNum]
	local _, glyphType, tooltipIndex = GetGlyphSocketInfo(socket, specNum)
	if not specData or not glyphType then return end -- invalid socket or spec number

	local glyphID, spellID, icon
	local enabled = specData.glyphs[socket] and true or false
	if enabled then
		glyphID, spellID = strsplit('|', specData.glyphs[socket])
		glyphID, spellID = tonumber(glyphID), tonumber(spellID)
		_, _, icon = GetSpellInfo(spellID)
	end
	return enabled, glyphType, spellID, icon, glyphID, tooltipIndex
end

-- --------------------------------------------------------
--  Talents
-- --------------------------------------------------------
function specializations.GetNumUnspentTalents(character, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character['spec'..specNum]
	local numUnspent = 0
	for tier = 1, GetMaxTalentTier() do
		local selection = specData.talents[tier]
		numUnspent = numUnspent + (selection == false and 1 or 0)
	end
	return numUnspent
end

function specializations.GetTalentSelection(character, tier, specNum)
	specNum = specNum or character.activeSpecGroup
	local specData = character['spec'..specNum]
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
	-- glyphs
	GetGlyphSocketInfo   = specializations.GetGlyphSocketInfo,
	-- talents
	GetNumUnspentTalents = specializations.GetNumUnspentTalents,
	GetTalentSelection   = specializations.GetTalentSelection,
	GetTalentInfo        = specializations.GetTalentInfo,
	GetActiveTalents     = specializations.GetActiveTalents,

	-- legacy functions
	GetClassTrees        = _GetClassTrees,
	GetTreeInfo          = _GetTreeInfo,
	GetTreeNameByID      = _GetTreeNameByID,
	GetTalentRank        = _GetTalentRank,
}
local nonCharacterMethods = { 'GetClassTrees',  'GetTreeInfo',  'GetTreeNameByID'}

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
		ScanGlyphs()
		self:UnregisterEvent(event)
	end)
	self:RegisterEvent('PLAYER_TALENT_UPDATE', ScanTalents)
	self:RegisterEvent('GLYPH_ADDED',   ScanGlyphs)
	self:RegisterEvent('GLYPH_REMOVED', ScanGlyphs)
	self:RegisterEvent('GLYPH_UPDATED', ScanGlyphs)
end

function specializations:OnDisable()
	self:UnregisterEvent('PLAYER_LOGIN')
	self:UnregisterEvent('PLAYER_TALENT_UPDATE')
	self:UnregisterEvent('GLYPH_ADDED')
	self:UnregisterEvent('GLYPH_REMOVED')
	self:UnregisterEvent('GLYPH_UPDATED')
end
