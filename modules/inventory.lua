local addonName, addon, _ = ...
local inventory = addon:NewModule('inventory', 'AceEvent-3.0')

-- GLOBALS: _G
-- GLOBALS: GetInventoryItemLink
-- GLOBALS: time

local function UpdateInventoryItem(slotID)
	local inventory = _G['DataStore_Inventory'].ThisCharacter.Inventory
	local link = GetInventoryItemLink('player', slotID)

	-- we want to save the full link, no matter what
	-- also, if there is no item, unset it
	inventory[slotID] = link
end

local function UpdateInventoryItems(event, arg1)
	if arg1 then
		UpdateInventoryItem(arg1)
	else
		for slotID = 1, _G.INVSLOT_LAST_EQUIPPED do
			UpdateInventoryItem(slotID)
		end
	end
	_G['DataStore_Inventory'].ThisCharacter.lastUpdate = time()
end

function inventory:OnEnable()
	self:RegisterEvent('PLAYER_ALIVE', UpdateInventoryItems)
	self:RegisterEvent('PLAYER_EQUIPMENT_CHANGED', UpdateInventoryItems)
end
function inventory:OnDisable()
	self:UnregisterEvent('PLAYER_ALIVE')
	self:UnregisterEvent('PLAYER_EQUIPMENT_CHANGED')
end
-- function inventory:OnInitialize() end
