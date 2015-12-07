local addonName, addon, _ = ...
local glyphs = addon:NewModule('Glyphs', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: UnitClass, GetItemInfo, GetNumSpecGroups, GetNumGlyphSockets, GetGlyphSocketInfo, GetNumGlyphs, GetGlyphInfo, ToggleGlyphFilter, IsGlyphFlagSet
-- GLOBALS: wipe, type, strjoin, strsplit, tonumber, pairs, ipairs, time
local tinsert, tsort = table.insert, table.sort
local filters = {}

local defaults = {
	global = {
		Characters = {
			['*'] = { -- character key, e.g. "Account.Realm.Name"
				lastUpdate = nil,
				knownGlyphs  = {},
			}
		},
		-- stores class glyph lists
		glyphs = {
			['*'] = { -- class name
				-- [index] = strjoin('|', glyphID, glyphType, icon, description)
			},
		},
	},
}

-- == Glyph Scanning ======================================
local scanTooltip = CreateFrame('GameTooltip', 'DataMoreScanTooltip', nil, 'GameTooltipTemplate')
local glyphNameByID = setmetatable({}, {
	__index = function(self, id)
		scanTooltip:SetOwner(_G.UIParent, 'ANCHOR_NONE')
		scanTooltip:SetGlyphByID(id)
		local name = _G[scanTooltip:GetName()..'TextLeft1']:GetText()
		scanTooltip:Hide()
		if name and name ~= _G.EMPTY then
			self[id] = name
			return name
		end
	end
})

-- scans which glyphs are known
local GLYPH_FILTER_KNOWN   = _G.GLYPH_FILTER_KNOWN or 8
local GLYPH_FILTER_UNKNOWN = _G.GLYPH_FILTER_UNKNOWN or 8
local filters = {
	[GLYPH_FILTER_KNOWN]   = true,
	[GLYPH_FILTER_UNKNOWN] = true,
	[_G.GLYPH_TYPE_MAJOR]  = true,
	[_G.GLYPH_TYPE_MINOR]  = true,
}
local function ScanGlyphList()
	-- Blizzard provides no GetGlyphInfo(glyphID) function so we need to store all this data ourselves
	wipe(glyphs.ThisCharacter.knownGlyphs)

	local _, class = UnitClass('player')
	local classGlyphs = glyphs.db.global.glyphs[class]
	wipe(classGlyphs)

	-- show all glyphs for scanning
	for filter, _ in pairs(filters) do
		filters[filter] = IsGlyphFlagSet(filter)
		if not IsGlyphFlagSet(filter) then
			ToggleGlyphFilter(filter)
		end
	end

	-- scan
	for index = 1, GetNumGlyphs() do
		local name, glyphType, isKnown, icon, glyphID, link, description = GetGlyphInfo(index)
		if glyphID then
			local texture = icon:sub(17) -- strip 'Interface\\Icons\\'
			classGlyphs[index] = strjoin('|', glyphID, glyphType, texture, description)
		else
			-- "header", glyphType, 1 -- title: _G.GLYPH_STRING_PLURAL[glyphType]
			classGlyphs[index] = strjoin('|', 0, glyphType)
		end

		-- not storing as bit map b/c when glyph list changes, char data becomes invalid
		if glyphID and isKnown then
			glyphs.ThisCharacter.knownGlyphs[glyphID] = true
		end
	end

	-- restore previous filters
	for filter, state in pairs(filters) do
		if state ~= IsGlyphFlagSet(filter) then
			ToggleGlyphFilter(filter)
		end
	end

	glyphs.ThisCharacter.lastUpdate = time()
end

-- == Glyphs API ==========================================
function glyphs.GetGlyphLink(glyphID, glyphName)
	glyphName = glyphName or glyphNameByID[glyphID]
	if glyphName then
		return ('|cff66bbff|Hglyph:%s|h[%s]|h|r'):format(glyphID, glyphName)
	end
end

function glyphs.GetNumGlyphs(character)
	local characterKey = DataStore:GetCurrentCharacterKey()
	local _, class = DataStore:GetCharacterClass(characterKey)
	local classGlyphs = glyphs.db.global.glyphs[class]
	return #classGlyphs
end

-- arguments: <glyph: itemID | glyphID | glyphName>, returns: isKnown, isCorrectClass
function glyphs.IsGlyphKnown(character, glyph)
	local characterKey = DataStore:GetCurrentCharacterKey()
	local _, class = DataStore:GetCharacterClass(characterKey)
	local classGlyphs = glyphs.db.global.glyphs[class]

	local canLearn = false
	if type(glyph) == 'number' then
		-- this is a glyphID or itemID
		glyph = glyphNameByID[glyph] or (GetItemInfo(glyph))
	end
	if not glyph then return end

	-- convert glyph name to glyphID
	for index, glyphData in pairs(classGlyphs) do
		local glyphID = strsplit('|', glyphData)
		      glyphID = tonumber(glyphID)
		if glyphNameByID[glyphID] == glyph then
			canLearn = true
			glyph = glyphID
			break
		end
	end

	local isKnown = character.knownGlyphs[glyph]
	return isKnown, canLearn
end

function glyphs.GetGlyphInfo(character, index)
	local characterKey = DataStore:GetCurrentCharacterKey()
	local _, class     = DataStore:GetCharacterClass(characterKey)
	local classGlyphs  = glyphs.db.global.glyphs[class]
	local glyphData    = classGlyphs[index]
	if not glyphData then return end

	local glyph, isKnown, link
	local glyphID, glyphType, icon, description = strsplit('|', glyphData)
	      glyphID, glyphType = tonumber(glyphID), tonumber(glyphType)

	if glyphID == 0 then
		glyph   = _G.GLYPH_STRING_PLURAL and _G.GLYPH_STRING_PLURAL[glyphType]
			or (glyphType == 1 and _G.MAJOR_GLYPHS or _G.MINOR_GLYPHS)
		glyphID = nil
		isKnown = true
	else
		glyph   = glyphNameByID[glyphID]
		link    = glyphs.GetGlyphLink(glyphID, glyph)
		isKnown = DataStore:IsGlyphKnown(characterKey, glyphID)
		icon    = icon and 'Interface\\Icons\\'..icon
	end

	return glyph, glyphType, isKnown, icon, glyphID, link, description
end

function glyphs.GetGlyphInfoByID(glyphID)
	local glyphName = glyphNameByID[glyphID]
	local link = glyphs.GetGlyphLink(glyphID, glyphName)

	for class, classGlyphs in pairs(glyphs.db.global.glyphs) do
		for index, glyphData in ipairs(classGlyphs) do
			local glyph, glyphType, icon, description = strsplit('|', glyphData)
			if tonumber(glyph) == glyphID then
				return glyphName, tonumber(glyphType), false, 'Interface\\Icons\\'..icon, glyphID, link, description
			end
		end
	end
end

-- == Setup ===============================================
local PublicMethods = {
	GetNumGlyphs       = glyphs.GetNumGlyphs,
	GetGlyphInfo       = glyphs.GetGlyphInfo,
	IsGlyphKnown       = glyphs.IsGlyphKnown,
	-- non character methods
	GetGlyphLink       = glyphs.GetGlyphLink,
	GetGlyphInfoByID   = glyphs.GetGlyphInfoByID,
}

function glyphs:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods, true)
	for funcName, funcImpl in pairs(PublicMethods) do
		if funcName ~= 'GetGlyphLink' and funcName ~= 'GetGlyphInfoByID' then
			DataStore:SetCharacterBasedMethod(funcName)
		end
	end
end

function glyphs:OnEnable()
	self:RegisterEvent('PLAYER_LOGIN', function(event)
		ScanGlyphList()
		self:UnregisterEvent(event)
	end)
	self:RegisterEvent('USE_GLYPH', ScanGlyphList)
end

function glyphs:OnDisable()
	self:UnregisterEvent('PLAYER_LOGIN')
	self:UnregisterEvent('USE_GLYPH')
end
