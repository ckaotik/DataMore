local addonName, addon, _ = ...
local plugin = addon:NewModule('Professions', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS:
-- GLOBALS: time, pairs, wipe

local emptyTable, returnTable = {}, {}
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
						['*'] = 0, -- linkStub|true crafted link, keyed by recipe spellID
					},
				},
				Cooldowns = {
					['*'] = nil, -- expiry, keyed by recipe spellID
				},
			}
		},
		Recipes = {
			['*'] = { -- skillLine
				['*'] = '', -- recipeID:craftedItem
			},
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
local function GetSkillLineByName(skillName)
	for skillLine, spellID in pairs(skillLineMappings) do
		if skillName == GetSpellInfo(spellID) then
			return skillLine, spellID
		end
	end
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
		if index then
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
	end
	plugin.ThisCharacter.lastUpdate = time()
end

local function ScanRecipes()
	if not C_TradeSkillUI.IsTradeSkillReady() or C_TradeSkillUI.IsDataSourceChanging()
		or C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
		or C_TradeSkillUI.IsNPCCrafting() then
		return
	end

	local knownRecipes = 0
	local skillLine, skillName = C_TradeSkillUI.GetTradeSkillLine()
	local recipeList = plugin.db.global.Recipes[skillLine]
	wipe(recipeList)

	local allRecipes = C_TradeSkillUI.GetAllRecipeIDs()
	for i, recipeID in ipairs(allRecipes) do
		-- Store list of all recipes for the profession.
		local craftedItem = C_TradeSkillUI.GetRecipeItemLink(recipeID)
		local linkID, linkType = addon.GetLinkID(craftedItem)

		if linkType == 'enchant' then
			craftedItem = -1 * linkID
		elseif linkType == 'item' --[[ and addon.IsBaseLink(craftedItem) --]] then
			craftedItem = linkID
		end
		recipeList[i] = strjoin(':', recipeID, craftedItem)

		-- Store character's knowledge information.
		local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipeInfo and recipeInfo.learned then
			knownRecipes = bit.bor(knownRecipes, 2^i)
		end
		wipe(recipeInfo)
	end
	plugin.ThisCharacter.Recipes[skillLine] = knownRecipes
end

local function ScanCooldowns()
	local cooldowns = plugin.ThisCharacter.Cooldowns
	-- wipe(cooldowns)

	local now = time()
	for recipeID, expires in pairs(cooldowns) do
		if expires < now then
			cooldowns[recipeID] = nil
		end
	end

	for skillLine, recipes in pairs(plugin.db.global.Recipes) do
		for i, recipe in pairs(recipes) do
			local recipeID, craftedItem = strsplit(':', recipe, 2)
			local timeLeft, isDayCooldown, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(recipeID)
			-- print(skillLine, recipeID, timeLeft, isDayCooldown) -- 168835
			if timeLeft and timeLeft > 0 then
				cooldowns[recipeID] = time() + timeLeft
			end
		end
	end
end

-- TODO: API functionality
local primaryProfessions = {171, 164, 333, 202, 773, 755, 165, 197, 182, 186, 393}
local secondaryProfessions = {794, 184, 129, 356}
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

-- returns rank, maxRank, spellID, specialization
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

function plugin.IsCraftKnown(character, recipeID, legacy)
	local index, skillLine
	if legacy then skillLine = recipeID; recipeID = legacy end

	for tradeSkill, recipes in pairs(plugin.db.global.Recipes) do
		if not skillLine or tradeSkill == skillLine then
			for i, recipe in ipairs(recipes) do
				local skillRecipeID = strsplit(':', recipe, 2)
				if skillRecipeID == recipeID then
					skillLine = tradeSkill
					index = i
					break
				end
			end
		end
		if index then break end
	end
	return index and bit.band(character.Recipes[skillLine], 2^index) > 0
end

function plugin.GetNumCraftLines(character, skillLine)
	local count = 0
	local recipes = plugin.db.global.Recipes[skillLine] or emptyTable
	for i, recipe in ipairs(recipes) do
		if bit.band(character.Recipes[skillLine], 2^index) > 0 then
			count = count + 1
		end
	end
	return count
end

function plugin.GetCraftLineInfo(character, skillLine, index)
	-- note: index does not match book index!
	local recipes = plugin.db.global.Recipes[skillLine] or emptyTable
	local knownIndex = 0
	for i, recipe in ipairs(recipes) do
		if bit.band(character.Recipes[skillLine], 2^index) > 0 then
			knownIndex = knownIndex + 1
		end
		if index == knownIndex then
			local recipeID, spellID = strsplit(':', recipe, 2)
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
		if expires >= now and C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID) == skillLine then
			returnTable[recipeID] = expires
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

function plugin:OnEnable()
	ScanProfessions()
	self:RegisterEvent('TRADE_SKILL_DATA_SOURCE_CHANGED', function()
		ScanRecipes()
		ScanCooldowns()
	end)
	ScanCooldowns()
	self:RegisterEvent('SPELL_UPDATE_COOLDOWN', ScanCooldowns)

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
