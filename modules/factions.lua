local addonName, addon, _ = ...
local factions = addon:NewModule('Factions', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: GetNumFactions, GetFactionInfo, GetFactionInfoByID, GetFriendshipReputation, ExpandFactionHeader, CollapseFactionHeader
-- GLOBALS: wipe, select, strsplit, pairs, hooksecurefunc, tonumber, time

--[[ NOTE: most info is accessible by using these functions
	GetFactionInfoByID(factionID) returns name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isIndented, factionID, hasBonus, canBeLFGBonus
	GetFriendshipReputation(factionID) returns friendID, friendRep, friendMaxRep, friendName, friendText, friendTexture, friendTextLevel, friendThreshold, nextFriendThreshold
--]]

local thisCharacter = DataStore:GetCharacter()
local FACTION_INACTIVE = -1

local reputationStandings = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000, 43000 }
local friendshipStandings = { 0, 8400, 16800, 25200, 33600, 42000, 43000 }
local friendStandingsTexts = {} -- filled on scan .. this sucks, see @TODO below

-- --------------------------------------------------------
--  Data Management
-- --------------------------------------------------------
local collapsedHeaders, isScanning = {}, false
local function ScanReputations()
	if isScanning then return end
	isScanning = true

	local character = factions.ThisCharacter
	wipe(character.reputations)
	wipe(collapsedHeaders)

	-- expand everything while storing original states
	local index = 1
	while true do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed, _, _, _, factionID = GetFactionInfo(index)
		if isHeader and isCollapsed then
			-- 'Inactive' doesn't have a factionID
			collapsedHeaders[factionID or FACTION_INACTIVE] = true
			-- expand on the go (top->bottom) makes sure we get everything
			ExpandFactionHeader(index)
			-- TODO: do we want to keep proper order? then we'll have to SetFactionActive(index)
		end
		index = index + 1
		if index > GetNumFactions() then break end
	end

	-- now do the actual scan
	local factionList
	for index = 1, GetNumFactions() do
		local name, _, standingID, _, _, reputation, atWarWith, _, isHeader, isCollapsed, hasRep, _, isIndented, factionID, hasBonus, canBeLFGBonus = GetFactionInfo(index)
		local friendID, friendRep, _, _, _, _, friendTextLevel = GetFriendshipReputation(factionID)
		if friendID then
			-- TODO: FIXME: only works for standings this character has
			local friendStanding = factions.GetFriendshipStanding(friendRep)
			friendStandingsTexts[friendStanding] = friendTextLevel
		end

		-- print('scanning faction', factionID, name, reputation)
		factionList = (factionList and factionList..',' or '') .. (factionID or FACTION_INACTIVE)
		character.reputations[factionID or FACTION_INACTIVE] = reputation
	end
	character.factions = factionList
	character.lastUpdate = time()

	-- restore pre-scan states
	for index = GetNumFactions(), 1, -1 do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed, _, _, _, factionID = GetFactionInfo(index)
		if isHeader and (collapsedHeaders[factionID or FACTION_INACTIVE]) then
			CollapseFactionHeader(index)
		end
	end
	isScanning = false
end

-- --------------------------------------------------------
--  API functions
-- --------------------------------------------------------
function factions.GetFriendshipStanding(reputation)
	local standingID, standingLabel, standingLow, standingHigh
	for standing = #friendshipStandings, 1, -1 do
		if reputation >= friendshipStandings[standing] then
			standingID, standingLabel = standing, friendStandingsTexts[standing]
			standingLow, standingHigh = friendshipStandings[standing], friendshipStandings[standing + 1]
			break
		end
	end
	return standingID, standingLabel, standingLow or 0, standingHigh or standingLow or 0
end

function factions.GetReputationStanding(reputation)
	local standingID, standingLabel, standingLow, standingHigh
	for standing = #reputationStandings, 1, -1 do
		if reputation >= reputationStandings[standing] then
			-- GetText('FACTION_STANDING_LABEL'..standingID, UnitSex('player'))
			standingID, standingLabel = standing, _G['FACTION_STANDING_LABEL'..standing]
			standingLow, standingHigh = reputationStandings[standing], reputationStandings[standing + 1]
			break
		end
	end
	return standingID, standingLabel, standingLow or 0, standingHigh or standingLow or 0
end

function factions.GetStanding(reputation, factionID)
	local _, _, _, _, _, _, _, _, isHeader, _, hasRep = GetFactionInfoByID(factionID)
	if isHeader and not hasRep then return end

	if GetFriendshipReputation(factionID) then
		return factions.GetFriendshipStanding(reputation)
	else
		return factions.GetReputationStanding(reputation)
	end
end

function factions.GetNumFactions(character)
	local numFactions = 0
	for factionID, reputation in pairs(character.reputations) do
		numFactions = numFactions + 1
	end
	return numFactions
end

-- /spew DataStore:GetFactionInfo("Default.Die Aldor.Nemia", 2)
function factions.GetFactionInfoByID(character, factionID)
	local reputation = character.reputations[factionID]
	if not reputation then return end

	local standingID, standingText, low, high = factions.GetStanding(reputation, factionID)
	return factionID, reputation, standingID, standingText, low, high
end

function factions.GetFactionInfo(character, index)
	local factionID = select(index, strsplit(',', character.factions))
	      factionID = factionID and tonumber(factionID)
	if not factionID then factionID = next(character.reputations, index > 1 and (index-1) or nil) end
	return factions.GetFactionInfoByID(character, factionID)
end

function factions.GetFactionInfoByName(character, factionName)
	for factionID, reputation in pairs(character.reputations) do
		local name = GetFactionInfo(factionID)
		if name == factionName then
			return factions.GetFactionInfoByID(character, factionID)
		end
	end
end

function factions.GetFactionInfoGuild(character)
	return factions.GetFactionInfoByID(character, 1168)
end

local PublicMethods = {
	-- general functions
	GetFriendshipStanding = factions.GetFriendshipStanding,
	GetReputationStanding = factions.GetReputationStanding,
	GetStanding           = factions.GetStanding,
	-- character functions
	GetNumFactions        = factions.GetNumFactions,
	GetFactionInfoGuild   = factions.GetFactionInfoGuild,
	GetFactionInfoByName  = factions.GetFactionInfoByName,
	GetFactionInfoByID    = factions.GetFactionInfoByID,
	GetFactionInfo        = factions.GetFactionInfo,
}

function factions:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', {
		global = {
			Characters = {
				['*'] = {
					lastUpdate = nil,
					factions = '', -- holds the display order
					reputations = {}, -- hold the faction's reputaton standing
				}
			}
		}
	}, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	DataStore:SetCharacterBasedMethod('GetNumFactions')
	DataStore:SetCharacterBasedMethod('GetFactionInfoGuild')
	DataStore:SetCharacterBasedMethod('GetFactionInfoByName')
	DataStore:SetCharacterBasedMethod('GetFactionInfoByID')
	DataStore:SetCharacterBasedMethod('GetFactionInfo')
end

function factions:OnEnable()
	hooksecurefunc('SetFactionActive', ScanReputations)
	hooksecurefunc('SetFactionInactive', ScanReputations)
	-- TODO: check events
	self:RegisterEvent('UPDATE_FACTION', ScanReputations)
	-- add event for guild join (=> resets reputation)
	--[[
	DataStore_Reputations uses these:
	addon:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
	addon:RegisterEvent("COMBAT_TEXT_UPDATE", OnFactionChange)
	addon:RegisterEvent("PLAYER_GUILD_UPDATE", OnPlayerGuildUpdate)
	--]]

	ScanReputations()
end

function factions:OnDisable()
	self:UnregisterEvent('UPDATE_FACTION')
end
