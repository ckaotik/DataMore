local addonName, addon, _ = ...
local factions = addon:NewModule('Factions', 'AceEvent-3.0')

-- GLOBALS: _G
-- GLOBALS:
-- GLOBALS:

local thisCharacter = DataStore:GetCharacter()

--[[
name,       desc, standing, min,     max,     rep, war,  _,  hdr, clps, rep, _, indnt,  id, bonus, lfg
"Gilde", 			 "", 4, 0, 		 3000,      0, nil, nil,   1, nil, nil, nil, nil, 1169, false, false
"Mondklingen", 		 "", 8, 42000, 	43000,  42999, nil, nil, nil, nil, nil, nil, nil, 1168, false, false
"Mists of Pandaria", "", 4, 0, 		 3000,      0, nil,   1,   1, nil, nil, nil, nil, 1245, false, false
"Die Klaxxi", 		 "", 5, 3000, 	 9000,   3150, nil, nil, nil, nil, nil, nil, nil, 1337,  true,  true
"Die Ackerbauern",   "", 6, 9000,   21000,  18582, nil, nil,   1, nil,   1, nil,   1, 1272,  true,  true
"Gina Lehmkrall",    "", 2, 8400,   16800,   9450, nil, nil, nil, nil, nil, nil,   1, 1281, false, false

GetFriendshipReputation(1281)
1281, 9450, 42999, "Gina Lehmkrall", "F\195\188r Gina Lehmkrall seid Ihr ein Bekannter. Gina mag Sumpflilien und verwirbelte Nebelsuppe.", nil, "Bekannter", 8400, 16800
--]]

-- NOTE: most info is accessible by using GetFactionInfoByID(factionID) in the client addon
-- local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isIndented, factionID, hasBonus, canBeLFGBonus = GetFactionInfoByID(factionID)
-- friendID, friendRep, friendMaxRep, friendName, friendText, friendTexture, friendTextLevel, friendThreshold, nextFriendThreshold = GetFriendshipReputation(factionID)

local collapsedHeaders = {}
local function ScanReputations()
	wipe(collapsedHeaders)

	-- expand everything while storing original states
	local index = 1
	while true do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed, _, _, _, factionID = GetFactionInfo(index)
		if isHeader and isCollapsed then
			-- 'Inactive' doesn't have a factionID
			collapsedHeaders[factionID or name] = true
			-- expand on the go (top->bottom) makes sure we get everything
			ExpandFactionHeader(index)
			-- TODO: do we want to keep proper order? then we'll have to SetFactionActive(index)
		end
		index = index + 1
		if index > GetNumFactions() then break end
	end

	-- now do the actual scan
	for index = 1, GetNumFactions() do
		local name, _, standingID, _, _, reputation, atWarWith, _, isHeader, isCollapsed, hasRep, _, isIndented, factionID, hasBonus, canBeLFGBonus = GetFactionInfo(index)
		local friendID, friendRep, friendMaxRep, friendName, friendText, friendTexture, friendTextLevel, friendThreshold, nextFriendThreshold = GetFriendshipReputation(factionID)
		-- TODO: evaluate and store data
		-- print('scanning faction', factionID, name, reputation)
	end

	-- restore pre-scan states
	for index = GetNumFactions(), 1, -1 do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed, _, _, _, factionID = GetFactionInfo(index)
		if isHeader and (collapsedHeaders[factionID] or collapsedHeaders[name]) then
			CollapseFactionHeader(index)
		end
	end
end

-- setup
local PublicMethods = {
--	GetMailStyle = _GetMailStyle,
}

function factions:OnInitialize()
	-- self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', AddonDB_Defaults)

	-- DataStore:RegisterModule(self.name, self, PublicMethods)
	-- DataStore:SetCharacterBasedMethod('GetMailStyle')
end

function factions:OnEnable()
	-- hooksecurefunc('SendMail', OnSendMail)
	-- self:RegisterEvent('MAIL_SUCCESS', ScanInbox)
	-- ScanReputations()
end

function factions:OnDisable()
	-- self:UnregisterEvent('MAIL_SHOW')
end
