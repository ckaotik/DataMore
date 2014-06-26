local addonName, ns, _ = ...

-- TODO: Check glyph scan events
-- TODO: split into talents + glyphs

-- GLOBALS: _G, DataStore, LibStub
-- GLOBALS: GetTalentInfo, GetTalentLink, GetNumClasses, GetClassInfo, GetSpecializationInfoForClassID, UnitLevel, UnitClass, GetActiveSpecGroup, GetMaxTalentTier, GetSpecialization, GetItemInfo, GetNumSpecGroups, GetNumGlyphSockets, GetSpecializationInfo, GetTalentRowSelectionInfo
-- GLOBALS: type, math, strsplit, tonumber, format, time, wipe, rawget, rawset, select, ipairs, pairs, table, strjoin, unpack
local rshift, band = bit.rshift, bit.band

local addonName  = "DataMore_Talents"
local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
_G[addonName] = addon

local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = { -- character key, e.g. "Account.Realm.Name"
				lastUpdate = nil,
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
	}
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
	local data = addon.ThisCharacter
	local specs = {}

	for specNum = 1, GetNumSpecGroups() do
		local specialization = GetSpecialization(nil, nil, specNum)
		local specID = specialization and GetSpecializationInfo(specialization) or nil
		table.insert(specs, specID)

		local talents = {}
		for tier = 1, GetMaxTalentTier() do
			local isUnspent, selection = GetTalentRowSelectionInfo(tier)
			table.insert(talents, selection or 0)
		end
		data['talents'..specNum] = strjoin('|', unpack(talents))
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
	local data = addon.ThisCharacter
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
	local data = addon.ThisCharacter
	-- data.knownGlyphs = 0
	if type(data.knownGlyphs) ~= 'table' then data.knownGlyphs = {} end
	wipe(data.knownGlyphs)

	local _, class = UnitClass('player')
	local glyphs = addon.db.global.Glyphs[class]
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
local function _GetSpecializationID(character, specNum)
	local spec1, spec2 = strsplit('|', character.specs)
	return tonumber((specNum or character.active) == 1 and spec1 or spec2)
end

-- returns the specialization index (1-4)
local function _GetSpecialization(character, specNum)
	specNum = specNum or character.active

	local specializationID = _GetSpecializationID(character, specNum)
	for specIndex = 1, 4 do -- GetNumSpecializations()
		local specID = GetSpecializationInfo(specIndex)
		if specID == specializationID then
			return specIndex
		end
	end
end

-- == Talents API =========================================
local function _GetNumUnspentTalents(character, specNum)
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

local function _GetTalentSelection(character, tier, specNum)
	specNum = specNum or character.active
	local talentID = select(tier, strsplit('|', character['talents'..specNum]))
	      talentID = tonumber(talentID or '')
	return talentID
end

local function _GetTalentInfo(character, tier, specNum)
	local talentID = _GetTalentSelection(character, tier, specNum)
	if talentID then
		local _, class = DataStore:GetCharacterClass(character.key)
	    	     class = classIDs[class]
		return GetTalentInfo(talentID, true, nil, nil, class)
	end
end

-- == Glyphs API ==========================================
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

	print('search', searchGlyphID, type(searchGlyphID))
	for index, glyphData in ipairs(sortTable) do
		local _, _, glyphID = strsplit('|', sortTable[index])

		print('compare to', glyphData)
		if tonumber(glyphID or '') == searchGlyphID then
			return index
		end
	end
end

local function _GetGlyphLink(glyphID, glyphName)
	glyphName = glyphName or glyphNameByID[glyphID]
	if glyphName then
		return format("|cff66bbff|Hglyph:%s|h[%s]|h|r", glyphID, glyphName)
	end
end

local function _GetNumGlyphs(character)
	local _, class = DataStore:GetCharacterClass(character.key)
	local glyphs = addon.db.global.Glyphs[class]

	local count = 0
	for _ in pairs(glyphs) do
		count = count + 1
	end
	return count
end

-- arguments: <glyph: itemID | glyphID | glyphName>, returns: isKnown, isCorrectClass
local function _IsGlyphKnown(character, glyph)
	local _, class = DataStore:GetCharacterClass(character.key)
	local glyphs = addon.db.global.Glyphs[class]

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

local function _GetGlyphInfo(character, index)
	local _, class = DataStore:GetCharacterClass(character.key)
	local glyphs = addon.db.global.Glyphs[class]

	local glyphID    = GetGlyphAtIndex(glyphs, index)
	local glyphData  = addon.db.global.Glyphs[class][glyphID]
	if not glyphData then return end

	local _, glyphType, _, icon, specNames = strsplit('|', glyphData)
	local glyphName = glyphNameByID[glyphID]
	local link = _GetGlyphLink(glyphID, glyphName)
	local isKnown = DataStore:IsGlyphKnown(character.key, glyphID)

	return glyphName, tonumber(glyphType), isKnown, 'Interface\\Icons\\'..icon, glyphID, link, specNames
end

local function _GetGlyphInfoByID(glyphID)
	local glyphName = glyphNameByID[glyphID]
	local link = _GetGlyphLink(glyphID, glyphName)

	for class, glyphs in pairs(addon.db.global.Glyphs) do
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
	return _GetTalentSelection(character, tier, specNum) == index and 1 or 0
end

-- these are no longer really necessary but in here for compatibility purposes
-- DEPRECATED: use GetTalentLink(talentIndex, true, classIndex) instead
local function _GetTalentLink(index, class, compatibilityMode)
	if compatibilityMode then
		-- this code is old and talent links only reference the current character's talents
		local id, name = index, compatibilityMode
		return format("|cff4e96f7|Htalent:%s|h[%s]|h|r", id, name)
	else
		class = classIDs[class]
		return GetTalentLink(index, true, class)
	end
end
local function _GetClassTrees(class)
	local class = classIDs[class]
	if type(class) == "number" then
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
	if type(tree) ~= "number" then return end
	local class = classIDs[class]
	if type(class) == "number" then
		local _, _, _, icon, background = GetSpecializationInfoForClassID(class, tree)
		return icon, background
	end
end
local function _GetTreeNameByID(class, id)
	local class = classIDs[class]
	if type(class) == "number" then
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

	GetSpecialization    = _GetSpecialization,
	GetSpecializationID  = _GetSpecializationID,
	GetNumUnspentTalents = _GetNumUnspentTalents,
	GetTalentSelection   = _GetTalentSelection,
	GetTalentInfo        = _GetTalentInfo,

	GetGlyphLink     = _GetGlyphLink,
	GetGlyphInfo     = _GetGlyphInfo,
	GetGlyphInfoByID = _GetGlyphInfoByID,
	IsGlyphKnown     = _IsGlyphKnown,
}

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)

	DataStore:RegisterModule(addonName, addon, {})
	for methodName, method in pairs(PublicMethods) do
		ns.RegisterOverride(addon, methodName, method)
	end
	ns.SetOverrideType('GetTalentRank', 'character')

	ns.SetOverrideType('GetSpecialization', 'character')
	ns.SetOverrideType('GetSpecializationID', 'character')
	ns.SetOverrideType('GetNumUnspentTalents', 'character')
	ns.SetOverrideType('GetTalentSelection', 'character')
	ns.SetOverrideType('GetTalentInfo', 'character')

	ns.SetOverrideType('GetGlyphInfo', 'character')
	ns.SetOverrideType('GetGlyphInfoByID', 'character')
	ns.SetOverrideType('IsGlyphKnown', 'character')
end

-- *** Event Handlers ***
function addon:OnEnable()
	local initialized
	addon:RegisterEvent('PLAYER_LOGIN', function(...)
		ScanTalents()
		if not initialized then
			ScanGlyphs()
			ScanGlyphList()
			initialized = true
		end
	end)
	addon:RegisterEvent('PLAYER_TALENT_UPDATE', ScanTalents)

	addon:RegisterEvent('GLYPH_ADDED', ScanGlyphs)
	addon:RegisterEvent('GLYPH_REMOVED', ScanGlyphs)
	addon:RegisterEvent('GLYPH_UPDATED', ScanGlyphs)
	addon:RegisterEvent('USE_GLYPH', ScanGlyphList)
end

function addon:OnDisable()
	addon:UnregisterEvent('PLAYER_LOGIN')
	addon:UnregisterEvent('PLAYER_TALENT_UPDATE')

	addon:UnregisterEvent('GLYPH_ADDED')
	addon:UnregisterEvent('GLYPH_REMOVED')
	addon:UnregisterEvent('GLYPH_UPDATED')
	addon:UnregisterEvent('USE_GLYPH')
end
