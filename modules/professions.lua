local addonName, addon, _ = ...
local plugin = addon:NewModule('Professions', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS:
-- GLOBALS: time, pairs, wipe

local defaults = {
	global = {
		Characters = {
			['*'] = {
				lastUpdate = nil,
				Professions = {
					['*'] = { -- keyed by skillLine
						rank = 0,
						maxRank = 0,
						link = '',
						spell = 0, -- spellID
						specialization = nil, -- spellID
					},
				},
				Recipes = {
					['*'] = { -- keyed by skillLine
						['*'] = nil, -- linkStub|true crafted link, keyed by recipe spellID
					},
				},
				Cooldowns = {
					['*'] = nil, -- expiry, keyed by recipe spellID
				},
			}
		},
		--[[ Guilds = {
			['*'] = {
				Members = {
					['*'] = {				-- ["MemberName"]
						lastUpdate = nil,
						Version = nil,
						Professions = {},		-- 3 profession links : [1] & [2] for the 2 primary professions, [3] for cooking ([4] for archaeology ? wait & see)
					},
				},
			},
		}, --]]
	}
}

local skillLineMappings = {
	-- primary crafting
	[171] =  2259, -- 'Alchemy',
	[164] =  2018, -- 'Blacksmithing',
	[333] =  7411, -- 'Enchanting',
	[202] =  4036, -- 'Engineering',
	[773] = 45357, -- 'Inscription',
	[755] = 25229, -- 'Jewelcrafting',
	[165] =  2108, -- 'Leatherworking',
	[197] =  3908, -- 'Tailoring',
	-- primary gathering
	[182] = 13614, -- 'Herbalism',
	[186] =  2575, -- 'Mining',
	[393] =  8613, -- 'Skinning',
	-- secondary
	[794] = 78670, -- 'Archaeology',
	[184] =  2550, -- 'Cooking',
	[129] =  3273, -- 'First Aid',
	[356] =  7620, -- 'Fishing',
}
local primaryProfessions = {171, 164, 333, 202, 773, 755, 165, 197, 182, 186, 393}
local secondaryProfessions = {794, 184, 129, 356}

local emptyTable, returnTable = {}, {}

local function GetSkillLineByName(skillName)
	for skillLine, spellID in pairs(skillLineMappings) do
		if skillName == GetSpellInfo(spellID) then
			return skillLine, spellID
		end
	end
end

local tradeSkillFilters = {}
local function SaveFilters()
	local skillName = GetTradeSkillLine()
	local filters = tradeSkillFilters[skillName]
	if not filters then
		tradeSkillFilters[skillName] = {}
		filters = tradeSkillFilters[skillName]
	end

	filters.selected 	 = GetTradeSkillSelectionIndex()
	filters.name 		 = GetTradeSkillItemNameFilter()
	filters.levelMin,
	filters.levelMax 	 = GetTradeSkillItemLevelFilter()
	filters.hasMaterials = _G.TradeSkillFrame.filterTbl.hasMaterials
	filters.hasSkillUp 	 = _G.TradeSkillFrame.filterTbl.hasSkillUp

	if not GetTradeSkillInvSlotFilter(0) then
		if not filters.slots then filters.slots = {} end
		wipe(filters.slots)
		for i = 1, select('#', GetTradeSkillInvSlots()) do
			filters.slots[i] = GetTradeSkillInvSlotFilter(i)
		end
	end
	if not GetTradeSkillCategoryFilter(0) then
		if not filters.subClasses then filters.subClasses = {} end
		wipe(filters.subClasses)
		for i = 1, select('#', GetTradeSkillSubClasses()) do
			filters.subClasses[i] = GetTradeSkillCategoryFilter(i)
		end
	end

	if not filters.collapsed then filters.collapsed = {} end
	wipe(filters.collapsed)
	for index = 1, GetNumTradeSkills() do
		local _, skillType, _, isExpanded = GetTradeSkillInfo(index)
		if skillType:find('header') and not isExpanded then
			table.insert(filters.collapsed, index)
		end
	end
end
local function RestoreFilters()
	local skillName = GetTradeSkillLine()
	local filters = skillName and tradeSkillFilters[skillName] or nil
	if not skillName or not filters then return end

	SetTradeSkillItemNameFilter(filters.name)
	SetTradeSkillItemLevelFilter(filters.levelMin or 0, filters.levelMax or 0)
	TradeSkillOnlyShowMakeable(filters.hasMaterials)
	TradeSkillOnlyShowSkillUps(filters.hasSkillUp)

	if filters.slots and #filters.slots > 0 then
		SetTradeSkillInvSlotFilter(0, 1, 1)
		for index, enabled in pairs(filters.slots) do
			SetTradeSkillInvSlotFilter(index, enabled)
		end
	end
	if filters.subClasses and #filters.subClasses > 0 then
		SetTradeSkillCategoryFilter(0, 1, 1)
		for index, enabled in pairs(filters.subClasses) do
			SetTradeSkillCategoryFilter(index, enabled)
		end
	end
	for _, index in ipairs(filters.collapsed) do
		CollapseTradeSkillSubClass(index)
	end

	TradeSkillUpdateFilterBar()
	SelectTradeSkill(filters.selected)
end
local function RemoveFilters()
	ExpandTradeSkillSubClass(0)
	SetTradeSkillItemLevelFilter(0, 0)
    SetTradeSkillItemNameFilter(nil)
    TradeSkillSetFilter(-1, -1)
end

local function ScanProfessions()
	local professions = plugin.ThisCharacter.Professions
	for skillLine, profession in pairs(professions) do
		wipe(profession)
	end
	wipe(professions)

	local numProfessions = select('#', GetProfessions())
	for i = 1, numProfessions do
		local index = select(i, GetProfessions())
		local name, icon, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, specIndex, specOffset = GetProfessionInfo(index)

		local profession = professions[skillLine]
		profession.rank = rank
		profession.maxRank = maxRank

		local spellIndex = spellOffset + (specOffset == 1 and 2 or 1)
		local spellLink, tradeLink = GetSpellLink(spellIndex, _G.BOOKTYPE_PROFESSION)
		local spellID = addon.GetLinkID(spellLink)
		profession.spell = spellID
		profession.link = tradeLink

		if specIndex > -1 then
			spellLink = GetSpellLink(spellOffset + specOffset, _G.BOOKTYPE_PROFESSION)
			spellID = addon.GetLinkID(spellLink)
			profession.specialization = spellID
		end
	end
	plugin.ThisCharacter.lastUpdate = time()
end

local function ScanRecipes(skillLine)
	local recipes = plugin.ThisCharacter.Recipes[skillLine]
	wipe(recipes)

	RemoveFilters()
	for index = 1, GetNumTradeSkills() do
		local skillName, skillType = GetTradeSkillInfo(index)
		if skillName and not skillType:find('header') then
			local recipeLink = GetTradeSkillRecipeLink(index)
			local recipeID = addon.GetLinkID(recipeLink)

			local craftedLink = GetTradeSkillItemLink(index)
			local linkID, linkType = addon.GetLinkID(craftedLink)
			if linkType == 'enchant' and linkID == recipeID then
				-- Craft result is identical to recipe
				craftedLink = true
			elseif linkType == 'item' and addon.IsBaseLink(craftedLink) then
				craftedLink = linkID
			end
			recipes[recipeID] = craftedLink
		end
	end
end

local function ScanCooldowns()
	local cooldowns = plugin.ThisCharacter.Cooldowns
	wipe(cooldowns)

	for skillLine, recipes in pairs(plugin.ThisCharacter.Recipes) do
		for recipeID, _ in pairs(recipes) do
			local start, duration = GetSpellCooldown(recipeID)
			local expires = (start or 0) + (duration or 0)
			if expires > 0 then
				cooldowns[recipeID] = expires
			end
		end
	end
end

-- TODO: API functionality
function plugin.GetProfessions(character)
	if not character.Professions then return {} end

	local prof1, prof2 = nil, nil
	for i, skillLine in ipairs(primaryProfessions) do
		if character.Professions[skillLine].rank > 0 then
			if not prof1 then
				prof1 = skillLine
			else
				prof2 = skillLine;
				break
			end
		end
	end
	local arch, fish, cook, firstAid = 794, 356, 184, 129
	return {prof1, prof2, arch, fish, cook, firstAid}
end

function plugin.GetProfessionInfo(character, profSkillLine)
	local profession = character.Professions[profSkillLine]
	if profession then
		return profession.rank or 0, profession.maxRank or 0, profession.spell or skillLineMappings[skillLine] or nil, profession.specialization
	end
	return 0, 0, 0, nil
end

function plugin.GetProfessionTradeLink(character, skillLine)
	local profession = character.Professions[skillLine]
	return profession and profession.link or ''
end

function plugin.IsCraftKnown(character, skillLine, recipeID)
	return (character.Recipes[skillLine] and character.Recipes[skillLine][recipeID]) and true or false
end

function plugin.GetNumCraftLines(character, skillLine)
	local count = 0
	for _ in pairs(character.Recipes[skillLine]) do
		count = count + 1
	end
	return count
end

function plugin.GetCraftLineInfo(character, skillLine, index)
	-- note: index does not match book index!
	local recipes = character.Recipes[skillLine] or emptyTable
	local i = 0
	for spellID, crafted in pairs(recipes) do
		i = i + 1;
		if i > index then break end
		if i == index then
			return false, nil, spellID
		end
	end
	return nil
end

function plugin.GetNumActiveCooldowns(character, skillLine)
	local cooldowns = plugin.GetProfessionCooldowns(character, skillLine)
	return #cooldowns
end

function plugin.GetProfessionCooldowns(character, skillLine)
	wipe(returnTable)
	for recipeID, expires in pairs(character.Cooldowns) do
		if expires >= now then
			if not skillLine or (character.Recipes[skillLine] and character.Recipes[skillLine][recipeID]) then
				returnTable[recipeID] = expires
			end
		end
	end
	return returnTable
end

function plugin.GetCraftCooldownInfo(character, skillLine, recipeID)
	if not recipeID then
		recipeID = skillLine
		skillLine = nil
	end
	local expires = character.Cooldowns[recipeID] or 0
	local name = GetSpellInfo(recipeID)
	local expiresIn = expires - time()
	return name, expiresIn > 0 and expiresIn or 0, expires, time()
end

function plugin:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	local methods = {
		GetProfessions = self.GetProfessions,
		GetProfessionInfo = self.GetProfessionInfo,
		GetProfessionTradeLink = self.GetProfessionTradeLink,
		GetProfessionCooldowns = self.GetProfessionCooldowns,
		GetNumCraftLines = self.GetNumCraftLines,
		IsCraftKnown = self.IsCraftKnown,
		GetNumActiveCooldowns = self.GetNumActiveCooldowns,
		GetCraftCooldownInfo = self.GetCraftCooldownInfo,
		GetCraftLineInfo = self.GetCraftLineInfo,

		-- legacy support
		GetCookingRank     = function(character) return self.GetProfessionInfo(character, 184) end,
		GetFishingRank     = function(character) return self.GetProfessionInfo(character, 356) end,
		GetFirstAidRank    = function(character) return self.GetProfessionInfo(character, 129) end,
		GetArchaeologyRank = function(character) return self.GetProfessionInfo(character, 794) end,
		GetProfession1 = function(character)
			for _, skillLine in ipairs(primaryProfessions) do
				if character.Professions[skillLine] then
					return self.GetProfessionInfo(character, skillLine)
				end
			end
		end,
		GetProfession2 = function(character)
			local prof1 = nil
			for _, skillLine in ipairs(primaryProfessions) do
				if character.Professions[skillLine] and prof1 then
					return self.GetProfessionInfo(character, skillLine)
				end
				prof1 = prof1 or character.Professions[skillLine]
			end
		end,
		GetProfession = function(character, name) return (GetSkillLineByName(name)) end,
		GetProfessionSpellID = function(name) return select(2, GetSkillLineByName(name)) end,
		ClearExpiredCooldowns = nop,

		--[[
		GetNumRecipesByColor = _GetNumRecipesByColor(profession),
		GetArchaeologyRaceArtifacts = _GetArchaeologyRaceArtifacts(race),
		GetRaceNumArtifacts = _GetRaceNumArtifacts(race),
		GetArtifactInfo = _GetArtifactInfo(race, index),
		IsArtifactKnown = _IsArtifactKnown(character, spellID),
		GetGuildCrafters = _GetGuildCrafters(guild),
		GetGuildMemberProfession = _GetGuildMemberProfession(guild, member, index),
		--]]
	}

	DataStore:RegisterModule(self.name, self, methods, true)
	for methodName in pairs(methods) do
		if methodName ~= 'ClearExpiredCooldowns' and methodName ~= 'GetProfessionSpellID' then
			DataStore:SetCharacterBasedMethod(methodName)
		end
	end
end

local function OnTradeSkillShow()
	if IsTradeSkillReady() then
		plugin:UnregisterEvent('TRADE_SKILL_UPDATE')
		local skillName, _, maxRank = GetTradeSkillLine()
		if (IsNPCCrafting() and maxRank == 0) or IsTradeSkillGuild() or IsTradeSkillLinked() then
			-- only scan our own professions
			return
		else
			local skillLine, spellID = GetSkillLineByName(skillName)
			SaveFilters()
			ScanRecipes(skillLine, spellID)
			ScanCooldowns()
			RestoreFilters()
		end
	else
		plugin:RegisterEvent('TRADE_SKILL_UPDATE', OnTradeSkillShow)
	end
end

function plugin:OnEnable()
	-- CHAT_MSG_SKILL, CHAT_MSG_SYSTEM
	self:RegisterEvent('TRADE_SKILL_SHOW', OnTradeSkillShow)
	self:RegisterEvent('SPELL_UPDATE_COOLDOWN', ScanCooldowns)
	ScanProfessions()
	-- Update cooldowns of known recipes
	-- ScanCooldowns()

	-- self:RegisterEvent('ARTIFACT_COMPLETE', OnArtifactComplete)
	-- self:RegisterEvent('ARTIFACT_HISTORY_READY', OnArtifactHistoryReady)
	-- RequestArtifactCompletionHistory()
end

function plugin:OnDisable()
	self:UnregisterEvent('TRADE_SKILL_SHOW')
	self:UnregisterEvent('SPELL_UPDATE_COOLDOWN')
	self:UnregisterEvent('ARTIFACT_COMPLETE')
	self:UnregisterEvent('ARTIFACT_HISTORY_READY')
end
