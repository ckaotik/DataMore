local addonName, addon, _ = ...
local talents = addon:NewModule('Talents', 'AceEvent-3.0') -- 'AceConsole-3.0'
-- TODO: should probably name this "Specializations" or so

-- TODO: Check glyph scan events
-- TODO: split into talents + glyphs

-- GLOBALS: _G, DataStore, LibStub
-- GLOBALS: GetTalentInfo, GetTalentLink, GetNumClasses, GetClassInfo, GetSpecializationInfoForClassID, UnitLevel, UnitClass, GetActiveSpecGroup, GetMaxTalentTier, GetSpecialization, GetItemInfo, GetNumSpecGroups, GetNumGlyphSockets, GetSpecializationInfo, GetTalentRowSelectionInfo, GetNumGlyphs, GetGlyphInfo, IsGlyphFlagSet, GetGlyphSocketInfo, ToggleGlyphFilter
-- GLOBALS: type, math, strsplit, tonumber, format, time, wipe, rawget, rawset, select, ipairs, pairs, table, strjoin, unpack
local rshift, band = bit.rshift, bit.band

local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = { -- character key, e.g. "Account.Realm.Name"
				lastUpdate = nil,
				--[[
				activeSpecGroup = nil, -- specialization index
				group1Spec = nil,      -- specialization ID
				group1Talents = {},    -- [tierX] = talentID / 0 (unspent) / null (not yet unlocked)
				group2Spec = nil,
				group2Talents = {},
				--]]

				active = nil,
				specs = '',
				talents1 = '',
				talents2 = '',

				glyphs = {},
				knownGlyphs = {},
			}
		},
		Glyphs = {
			['*'] = {}, -- class, e.g. "DRUID"
		},
	},
	--[[
	-- char, realm, class, faction, factionrealm, profile
	class = {
		glyphs = {
			-- [glyphID] = "glyphIndex|glyphType|glyphID|icon|description"
		},
	}, --]]
}

-- == Talent Scanning =====================================
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

local function ScanTalents()
	local data = talents.ThisCharacter
	local specs = {}

	for specNum = 1, GetNumSpecGroups() do
		local specialization = GetSpecialization(nil, nil, specNum)
		local specID = specialization and GetSpecializationInfo(specialization) or nil
		table.insert(specs, specID)

		local talentChoices = {}
		for tier = 1, GetMaxTalentTier() do
			local isUnspent, selection = GetTalentRowSelectionInfo(tier)
			table.insert(talentChoices, selection or 0)
		end
		data['talents'..specNum] = strjoin('|', unpack(talentChoices))
	end

	data.active = GetActiveSpecGroup()
	data.specs = strjoin('|', unpack(specs))
	data.lastUpdate = time()
end

-- == Glyph Scanning ======================================
local scanTooltip = CreateFrame('GameTooltip', 'DataStoreScanTooltip', nil, 'GameTooltipTemplate')
local glyphNameByID = setmetatable({}, {
	__index = function(self, id)
		scanTooltip:SetOwner(_G.UIParent, 'ANCHOR_NONE')
		scanTooltip:SetHyperlink('glyph:'..id)
		local name = _G[scanTooltip:GetName()..'TextLeft1']:GetText()
		scanTooltip:Hide()
		if name then
			self[id] = name
			return name
		end
	end
})

local function ScanGlyphs()
	local data = talents.ThisCharacter
	wipe(data.glyphs)

	for specNum = 1, GetNumSpecGroups() do
		for socket = 1, GetNumGlyphSockets() do
			local isAvailable, glyphType, tooltipIndex, spellID, icon, glyphID = GetGlyphSocketInfo(socket, specNum)
			if not isAvailable then
				data.glyphs[socket] = ''
			elseif not glyphID then
				data.glyphs[socket] = '0'
			else
				data.glyphs[socket] = strjoin('|', glyphID, spellID or '')
			end
		end
	end
end

local function ScanGlyphList()
	-- Blizzard provides no GetGlyphInfo(glyphID) function so we need to store all this data ourselves
	local data = talents.ThisCharacter
	-- data.knownGlyphs = 0
	if type(data.knownGlyphs) ~= 'table' then data.knownGlyphs = {} end
	wipe(data.knownGlyphs)

	local _, class = UnitClass('player')
	local glyphs = talents.db.global.Glyphs[class]
	wipe(glyphs)

	-- show all glyphs for scanning
	for _, filter in pairs({_G.GLYPH_FILTER_KNOWN, _G.GLYPH_FILTER_UNKNOWN, _G.GLYPH_TYPE_MAJOR, _G.GLYPH_TYPE_MINOR}) do
		if not IsGlyphFlagSet(filter) then
			ToggleGlyphFilter(filter)
		end
	end

	-- scan
	for index = 1, GetNumGlyphs() do
		local name, glyphType, isKnown, icon, glyphID, link, specNames = GetGlyphInfo(index)
		local glyphData
		if glyphID then
			local texture = icon:sub(17) -- strip 'Interface\\Icons\\'
			glyphs[glyphID] = strjoin('|', index, glyphType, glyphID, texture, specNames)
		end

		if glyphID and isKnown then
			-- data.knownGlyphs = data.knownGlyphs + bit.lshift(1, index-1)
			data.knownGlyphs[glyphID] = true
		end
	end

	-- TODO: restore previous filters
end

-- == Specialization API ==================================
-- returns the specialization id (3 digits) as used by API functions
function talents.GetSpecializationID(character, specNum)
	local spec1, spec2 = strsplit('|', character.specs)
	return tonumber((specNum or character.active) == 1 and spec1 or spec2)
end

-- returns the specialization index (1-4)
function talents.GetSpecialization(character, specNum)
	specNum = specNum or character.active

	local specializationID = talents.GetSpecializationID(character, specNum)
	for specIndex = 1, 4 do -- GetNumSpecializations()
		local specID = GetSpecializationInfo(specIndex)
		if specID == specializationID then
			return specIndex
		end
	end
end

-- == Talents API =========================================
function talents.GetNumUnspentTalents(character, specNum)
	specNum = specNum or character.active
	local numUnspent = 0

	local tiers = { strsplit('|', character['talents'..specNum]) }
	for tier, selection in ipairs(tiers) do
		if selection == 0 then
			numUnspent = numUnspent + 1
		end
	end
	return numUnspent
end

function talents.GetTalentSelection(character, tier, specNum)
	specNum = specNum or character.active
	local talentID = select(tier, strsplit('|', character['talents'..specNum]))
	      talentID = tonumber(talentID or '')
	return talentID
end

function talents.GetTalentInfo(character, tier, specNum)
	local talentID = talents.GetTalentSelection(character, tier, specNum)
	if talentID then
		return GetTalentInfoByID(talentID)
	end
end

function talents.GetActiveTalents(character)
	return character.active
end

-- == Glyphs API ==========================================
local glyphs = talents

local sortTable = {}
local function GetGlyphAtIndex(glyphs, index)
	wipe(sortTable)
	for glyphID, glyphData in pairs(glyphs) do
		table.insert(sortTable, glyphData)
	end
	table.sort(sortTable)

	local _, _, glyphID = strsplit('|', sortTable[index])
	return tonumber(glyphID or '')
end
local function GetGlyphIndex(glyphs, searchGlyphID)
	wipe(sortTable)
	for glyphID, glyphData in pairs(glyphs) do
		table.insert(sortTable, glyphData)
	end
	table.sort(sortTable)

	-- print('search', searchGlyphID, type(searchGlyphID))
	for index, glyphData in ipairs(sortTable) do
		local _, _, glyphID = strsplit('|', sortTable[index])

		-- print('compare to', glyphData)
		if tonumber(glyphID or '') == searchGlyphID then
			return index
		end
	end
end

function glyphs.GetGlyphLink(glyphID, glyphName)
	glyphName = glyphName or glyphNameByID[glyphID]
	if glyphName then
		return format('|cff66bbff|Hglyph:%s|h[%s]|h|r', glyphID, glyphName)
	end
end

function glyphs.GetNumGlyphs(character)
	local characterKey = DataStore:GetCurrentCharacterKey()
	local _, class = DataStore:GetCharacterClass(characterKey)
	local glyphs = talents.db.global.Glyphs[class]

	local count = 0
	for _ in pairs(glyphs) do
		count = count + 1
	end
	return count
end

-- arguments: <glyph: itemID | glyphID | glyphName>, returns: isKnown, isCorrectClass
function glyphs.IsGlyphKnown(character, glyph)
	local characterKey = DataStore:GetCurrentCharacterKey()
	local _, class = DataStore:GetCharacterClass(characterKey)
	local glyphs = talents.db.global.Glyphs[class]

	local canLearn = false
	if type(glyph) == 'number' and glyphs[glyph] then
		-- this is a glyphID
		canLearn = true
	elseif type(glyph) == 'number' then
		-- this is an itemID
		glyph = GetItemInfo(glyph)
	end

	if type(glyph) == 'string' then
		-- convert itemName to glyphID
		for glyphID, glyphData in pairs(glyphs) do
			if glyphNameByID[glyphID] == glyph then
				canLearn = true
				glyph = glyphID
				break
			end
		end
	end

	local isKnown = character.knownGlyphs[glyph]
	return isKnown, canLearn
end

function glyphs.GetGlyphInfo(character, index)
	local characterKey = DataStore:GetCurrentCharacterKey()
	local _, class = DataStore:GetCharacterClass(characterKey)
	local glyphs = talents.db.global.Glyphs[class]

	local glyphID    = GetGlyphAtIndex(glyphs, index)
	local glyphData  = talents.db.global.Glyphs[class][glyphID]
	if not glyphData then return end

	local _, glyphType, _, icon, specNames = strsplit('|', glyphData)
	local glyphName = glyphNameByID[glyphID]
	local link = glyphs.GetGlyphLink(glyphID, glyphName)
	local isKnown = DataStore:IsGlyphKnown(characterKey, glyphID)

	return glyphName, tonumber(glyphType), isKnown, 'Interface\\Icons\\'..icon, glyphID, link, specNames
end

function glyphs.GetGlyphInfoByID(glyphID)
	local glyphName = glyphNameByID[glyphID]
	local link = glyphs.GetGlyphLink(glyphID, glyphName)

	for class, glyphs in pairs(talents.db.global.Glyphs) do
		if glyphs[glyphID] then
			local _, glyphType, _, icon, specNames = strsplit('|', glyphs[glyphID])
			return glyphName, tonumber(glyphType), false, 'Interface\\Icons\\'..icon, glyphID, link, specNames
		end
	end
end

-- == LEGACY FUNCTIONS ====================================
local talentsPerTier = _G.NUM_TALENT_COLUMNS
local function _GetTalentRank(character, index, specNum, compatibilityMode)
	local tree
	if compatibilityMode then
		tree, index = index, compatibilityMode
	end

	specNum = specNum or character.active
	local tier = math.ceil(index / talentsPerTier)
	return talents.GetTalentSelection(character, tier, specNum) == index and 1 or 0
end

-- these are no longer really necessary but in here for compatibility purposes
-- DEPRECATED: use GetTalentLink(talentIndex, true, classIndex) instead
local function _GetTalentLink(talentID)
	return GetTalentLink(talentID)
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

-- == Setup ===============================================
local PublicMethods = {
	GetClassTrees        = _GetClassTrees,
	GetTreeInfo          = _GetTreeInfo,
	GetTreeNameByID      = _GetTreeNameByID,
	GetTalentRank        = _GetTalentRank,

	GetSpecialization    = talents.GetSpecialization,
	GetSpecializationID  = talents.GetSpecializationID,
	GetNumUnspentTalents = talents.GetNumUnspentTalents,
	GetTalentSelection   = talents.GetTalentSelection,
	GetTalentInfo        = talents.GetTalentInfo,
	GetActiveTalents     = talents.GetActiveTalents,

	-- GetNumGlyphs         = glyphs.GetNumGlyphs,
	-- GetGlyphLink         = glyphs.GetGlyphLink,
	-- GetGlyphInfo         = glyphs.GetGlyphInfo,
	-- GetGlyphInfoByID     = glyphs.GetGlyphInfoByID,
	-- IsGlyphKnown         = glyphs.IsGlyphKnown,
}

function talents:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', AddonDB_Defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods, true)
	for funcName, funcImpl in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(funcName)
	end

	--[[ DataStore:RegisterModule(self.name, self, {})
	for methodName, method in pairs(PublicMethods) do
		addon.RegisterOverride(self, methodName, method)
	end
	addon.SetOverrideType('GetTalentRank', 'character')

	addon.SetOverrideType('GetSpecialization', 'character')
	addon.SetOverrideType('GetSpecializationID', 'character')
	addon.SetOverrideType('GetNumUnspentTalents', 'character')
	addon.SetOverrideType('GetTalentSelection', 'character')
	addon.SetOverrideType('GetTalentInfo', 'character')

	addon.SetOverrideType('GetGlyphInfo', 'character')
	addon.SetOverrideType('GetGlyphInfoByID', 'character')
	addon.SetOverrideType('IsGlyphKnown', 'character')
	--]]
end

-- *** Event Handlers ***
function talents:OnEnable()
	local initialized
	self:RegisterEvent('PLAYER_LOGIN', function(...)
		ScanTalents()
		if false and not initialized then
			ScanGlyphs()
			ScanGlyphList()
			initialized = true
		end
	end)
	self:RegisterEvent('PLAYER_TALENT_UPDATE', ScanTalents)

	-- self:RegisterEvent('GLYPH_ADDED', ScanGlyphs)
	-- self:RegisterEvent('GLYPH_REMOVED', ScanGlyphs)
	-- self:RegisterEvent('GLYPH_UPDATED', ScanGlyphs)
	-- self:RegisterEvent('USE_GLYPH', ScanGlyphList)
end

function talents:OnDisable()
	self:UnregisterEvent('PLAYER_LOGIN')
	self:UnregisterEvent('PLAYER_TALENT_UPDATE')

	-- self:UnregisterEvent('GLYPH_ADDED')
	-- self:UnregisterEvent('GLYPH_REMOVED')
	-- self:UnregisterEvent('GLYPH_UPDATED')
	-- self:UnregisterEvent('USE_GLYPH')
end
