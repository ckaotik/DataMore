local addonName, addon, _ = ...

-- GLOBALS: _G, LibStub, DataStore, GetAutoCompleteRealms
-- GLOBALS: wipe, pairs, table, tContains

local Lib = LibStub('LibItemCache-1.1')
if not DataStore or Lib:HasCache() then return end

local Cache = Lib:NewCache()

function Cache:GetBag(realm, player, bag, tab, slot)
	local characterKey = DataStore:GetCharacter(player, realm, nil)
	if tab then
		-- guild bank
		local guildName = characterKey and DataStore:GetGuildInfo(characterKey)
		local guildKey  = guildName and DataStore:GetGuild(guildName, realm, nil)

		if guildKey then
			local icon = DataStore:GetGuildBankTabIcon(guildKey, tab)
			local name = DataStore:GetGuildBankTabName(guildKey, tab)
			local canView, canDeposit, numWithdrawals, numRemaining = true, true, 0, 0
			return name, icon, canView, canDeposit, numWithdrawals, numRemaining, true
		end
	elseif slot then
		if slot < _G.INVSLOT_FIRST_EQUIPPED or slot > _G.INVSLOT_LAST_EQUIPPED then
			-- equipped bags are saved in DataStore_Containers
			local _, link, numSlots = DataStore:GetContainerInfo(characterKey, bag == _G.BANK_CONTAINER and 100 or bag)
			if link then
				return link:match('item:(%d+)'), numSlots
			end
		end
	else
		local owned = DataStore:GetContainerSize(characterKey, _G.REAGENTBANK_CONTAINER)
		return owned
	end
end

function Cache:GetItem(realm, player, bag, tab, slot)
	local characterKey = DataStore:GetCharacter(player, realm, nil)
	local container
	if tab then
		-- guild bank
		local guildName = characterKey and DataStore:GetGuildInfo(characterKey)
		local guildKey  = guildName and DataStore:GetGuild(guildName, realm, nil)
		container = guildKey and DataStore:GetGuildBankTab(guildKey, tab)
	else
		container = DataStore:GetContainer(characterKey, bag == _G.BANK_CONTAINER and 100 or bag)
	end

	if container then
		local itemID, link, count = DataStore:GetSlotInfo(container, slot)
		if itemID then
			return ''..itemID, count
		end
	end
end

function Cache:GetItemCounts(realm, player, id)
	local characterKey = DataStore:GetCharacter(player, realm, nil)
	local equipment    = DataStore:GetInventoryItemCount(characterKey, id)
	local bags, bank, vault, reagents = DataStore:GetContainerItemCount(characterKey, id)
	return equipment, bags, bank, vault
end

function Cache:GetGuild(realm, player)
	local characterKey = DataStore:GetCharacter(player, realm, nil)
	return DataStore:GetGuildInfo(characterKey)

end

function Cache:GetMoney(realm, player)
	local characterKey = DataStore:GetCharacter(player, realm, nil)
	return DataStore:GetMoney(characterKey)
end

function Cache:GetPlayer(realm, player)
	local characterKey = DataStore:GetCharacter(player, realm, nil)
	local _, class = DataStore:GetCharacterClass(characterKey)
	local _, race  = DataStore:GetCharacterRace(characterKey)
	local faction  = DataStore:GetCharacterFaction(characterKey)
	local gender   = DataStore:GetCharacterGender(characterKey)
	return class, race, gender, faction
end

function Cache:DeletePlayer(realm, player)
	-- we don't delete players
end

local characters, realms, emptyTable = {}, nil, {}
function Cache:GetPlayers(realm)
	wipe(characters)
	realms = realms or GetAutoCompleteRealms()
	for account in pairs(DataStore:GetAccounts()) do
		for realmName in pairs(DataStore:GetRealms(account)) do
			if realmName == realm or tContains(realms or emptyTable, realmName:gsub(' ', '')) then
				for character in pairs(DataStore:GetCharacters(realmName, account)) do
					table.insert(characters, character)
				end
			end
		end
	end
	return characters
end
