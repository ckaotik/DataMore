local addonName, ns = ...

-- GLOBALS: _G, DataStore, LibStub, UIParent
-- GLOBALS:GetTalentInfo, GetTalentLink, GetNumClasses, GetClassInfo, GetSpecializationInfoForClassID, UnitLevel, UnitClass, GetActiveSpecGroup, GetMaxTalentTier, GetSpecialization
-- GLOBALS: type, math, strsplit, tonumber, format, time, wipe

local addonName  = "DataMore_Talents"
   _G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
local addon = _G[addonName]

local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				ActiveTalents = nil,		-- 1 for primary, 2 for secondary
				Class = nil,				-- englishClass
				TalentTrees = {},
			}
		}
	}
}

-- *** Utility functions ***
local LeftShift, RightShift, bAnd = bit.lshift, bit.rshift, bit.band
local talentsPerTier = NUM_TALENT_COLUMNS

local scanTooltip = CreateFrame("GameTooltip", "DataStoreScanTooltip", nil, "GameTooltipTemplate")
local glyphNameByID = setmetatable({}, {
	__index = function(self, id)
		scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		scanTooltip:SetHyperlink("glyph:"..id)
		local name = _G[scanTooltip:GetName().."TextLeft1"]:GetText()
		scanTooltip:Hide()
		if name then
			self[id] = name
			return name
		end
	end
})

-- *** Scanning functions ***
local function ScanTalents()
	local level = UnitLevel("player")
	if not level or level < 10 then return end		-- don't scan anything for low level characters

	local char = addon.ThisCharacter
	local _, englishClass = UnitClass("player")

	char.ActiveTalents = GetActiveSpecGroup()			-- returns 1 or 2
	char.Class = englishClass

	wipe(char.TalentTrees)

	local attrib, offset
	for specNum = 1, 2 do												-- primary and secondary specs
		attrib = 0
		offset = 0

		local specialization = GetSpecialization(nil, nil, specNum)
		local unspentTalents = 0

		for tier = 1, GetMaxTalentTier() do
			local selected, isSelected, isAvailable, _
			local talentOffset = (tier-1)*talentsPerTier
			for talent = 1, talentsPerTier do
				_, _, _, _, isSelected, isAvailable = GetTalentInfo(talentOffset + talent, nil, specNum)
				selected = selected or (isSelected and talentOffset + talent)
			end

			if isAvailable and not selected then
				unspentTalents = unspentTalents + 1
			end

			-- bits 0-2 = tier 1
			-- bits 3-5 = tier 2
			-- etc..
			attrib = attrib + LeftShift((isAvailable or selected ~= 0) and 1 or 0, offset)
			attrib = attrib + LeftShift(((selected or 0) - 1)%3 + 1, offset+1)

			offset = offset + 3 -- each tier takes 3 bits (1 available + 2 selection)
		end

		char["Spec" .. specNum] = format("%d|%d", specialization, unspentTalents)
		char["Talents" .. specNum] = attrib
	end

	char.lastUpdate = time()
end

local function GetClassIDFromName(class)
	if type(class) == "string" then
		for i=1,GetNumClasses() do
			local _, checkClass, classID = GetClassInfo(i)
			if checkClass == class then
				class = classID
				break
			end
		end
	end
	return class
end

-- ** Mixins **
local function _GetClassTrees(class)
	local class = GetClassIDFromName(class)
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
	if type(tree) == "number" then
		local class = GetClassIDFromName(class)
		if type(class) == "number" then
			local _, _, _, icon, background = GetSpecializationInfoForClassID(class, tree)
			return icon, background
		end
	end
end

local function _GetTreeNameByID(class, id)
	local class = GetClassIDFromName(class)
	if type(class) == "number" then
		local _, name = GetSpecializationInfoForClassID(class, id)
		return name
	end
end

-- TODO: no longer required, use GetTalentLink(talentIndex, true, classIndex) instead
local function _GetTalentLink(index, class, compatibilityMode)
	if compatibilityMode then
		-- this code is old and talent links only reference the current character's talents
		local id, name = index, compatibilityMode
		return format("|cff4e96f7|Htalent:%s|h[%s]|h|r", id, name)
	else
		class = GetClassIDFromName(class)
		return GetTalentLink(index, true, class)
	end
end

local function _GetTalentInfo(class, index)
	local class = GetClassIDFromName(class)
	if type(class) == "number" then
		local name, texture, tier, column = GetTalentInfo(index, true, nil, nil, class)

		-- local link = GetTalentLink(index, true, nil, nil, class)
		-- local spellID = tonumber(link:match("talent:(%d+)"))

		return --[[spellID,--]] name, texture, tier, column, 1
	end
end

local function _GetTalentRank(character, index, specNum, compatibilityMode)
	local tree
	if compatibilityMode then
		tree, index = index, compatibilityMode
	end

	local tier = math.floor((index-1) / talentsPerTier) -- this is actually tier-1
	local attrib = character["Talents"..(specNum or character.ActiveTalents)]
		  attrib = RightShift(attrib, 3*tier+1) -- ignore isAvailable bit
	local selectedTalent = bAnd(attrib, 3)

	return selectedTalent == index - (tier*talentsPerTier) and 1 or 0
end

local function _GetSpecialization(character, specNum)
	specNum = specNum or character.ActiveTalents
	local specialization = strsplit("|", character["Spec"..specNum] or "")
	return tonumber(specialization or 0)
end

local function _GetNumUnspentTalents(character, specNum)
	specNum = specNum or character.ActiveTalents
	local _, unspent = strsplit("|", character["Spec"..specNum] or "")
	return tonumber(unspent or 0)
end

local function _GetGlyphLink(glyphID)
	local glyphName = glyphNameByID[glyphID]
	local link, icon -- Blizzard doesn't expose glyph icons :(
	if glyphName then
		return format("|cff66bbff|Hglyph:%s|h[%s]|h|r", glyphID, glyphName)
	end
end

local function _GetGlyphInfoByID(glyphID)
	local glyphName = glyphNameByID[glyphID]
	local link, icon -- Blizzard doesn't expose glyph icons :(
	if glyphName then
		link = format("|cff66bbff|Hglyph:%s|h[%s]|h|r", glyphID, glyphName)
	end

	return glyphName, icon or "", link
end

--[[
local glyphID = addon.ItemIDToGlyphID[itemID]
if not glyphID then return end

local id
for index, glyph in ipairs(character.GlyphList) do
	id = RightShift(glyph, 4)

	if id == glyphID then
		local isKnown = bAnd(RightShift(glyph, 3), 1)
		return (isKnown == 1) and true or nil, true
	end
end
--]]

-- FIXME: this requires DataStore_Talents
-- <glyph: itemID | glyphName>
local function _IsGlyphKnown(character, glyph)
	-- returns: isKnown, isKnown or canLearn
	if type(glyph) == "number" then
		local glyphID = DataStore_Talents.ItemIDToGlyphID[glyph]
		if not glyphID then return end
		glyph = glyphNameByID[glyphID]
	end

	local characterTalents = DataStore_Talents.Characters[ character.key ]
	for _, glyphInfo in ipairs(characterTalents.GlyphList) do
		local glyphID = RightShift(glyphInfo, 4)
		if glyphNameByID[glyphID] == glyph then
			local isKnown = bAnd(RightShift(glyphInfo, 3), 1)
			return (isKnown == 1) and true or nil, true
		end
	end
end

-- *** Register with DataStore ***
local PublicMethods = {
	GetClassTrees = _GetClassTrees,
	GetTreeInfo = _GetTreeInfo,
	GetTreeNameByID = _GetTreeNameByID,
	GetTalentLink = _GetTalentLink,
	GetTalentInfo = _GetTalentInfo,
	GetTalentRank = _GetTalentRank,
	GetSpecialization = _GetSpecialization,
	GetNumUnspentTalents = _GetNumUnspentTalents,
	GetGlyphLink = _GetGlyphLink,
	GetGlyphInfo = _GetGlyphInfo,
	GetGlyphInfoByID = _GetGlyphInfoByID,
	IsGlyphKnown = _IsGlyphKnown,
}

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)

	DataStore:RegisterModule(addonName, addon, {})
	ns.RegisterOverrides(addonName, addon, PublicMethods)
	ns.SetCharacterBasedMethod("GetTalentRank")
	ns.SetCharacterBasedMethod("GetSpecialization")
	ns.SetCharacterBasedMethod("GetNumUnspentTalents")
	ns.SetCharacterBasedMethod("GetGlyphInfo")
	ns.SetCharacterBasedMethod("IsGlyphKnown")

	ScanTalents()
end

-- *** Event Handlers ***
function addon:OnEnable()
	addon:RegisterEvent("PLAYER_ALIVE", ScanTalents)
	addon:RegisterEvent("PLAYER_TALENT_UPDATE", ScanTalents)
end

function addon:OnDisable()
	addon:UnregisterEvent("PLAYER_ALIVE")
	addon:UnregisterEvent("PLAYER_TALENT_UPDATE")
end
