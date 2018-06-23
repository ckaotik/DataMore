local addonName, addon, _ = ...
local equipment = addon:NewModule('Equipment', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: GetNumEquipmentSets, GetEquipmentSetInfo, GetEquipmentSetInfoByName, GetEquipmentSetLocations, EquipmentManager_UnpackLocation, EquipmentManager_GetItemInfoByLocation, GetItemInfo, GetVoidItemInfo, GetContainerItemLink, GetInventoryItemLink
-- GLOBALS: time, pairs, wipe

local defaults = {
	global = {
		Characters = {
			['*'] = {
				lastUpdate = nil,
				EquipmentSets = {},
			}
		}
	}
}

local SLOT_MISSING, SLOT_INVALID, SLOT_IGNORED = -1, 0, 1
local function UpdateEquipmentSet(setName, setIcon)
	local sets = equipment.ThisCharacter.EquipmentSets
	if not sets[setName] then
		sets[setName] = {}
	end
	-- luckily equipment set names are unique
	sets[setName].icon = setIcon or sets[setName].icon

	-- local itemIDs = GetEquipmentSetItemIDs(setName)
	local setID = C_EquipmentSet.GetEquipmentSetID(setName)
	local locations = C_EquipmentSet.GetItemLocations(setID)
	for slotID, location in pairs(locations) do
		if location == SLOT_INVALID or location == SLOT_IGNORED or location == SLOT_MISSING then
			sets[setName][slotID] = nil
		else
			local itemLink
			local player, bank, bags, voidStorage, slot, container = EquipmentManager_UnpackLocation(location)

			if voidStorage then
				local itemID = GetVoidItemInfo(slot)
				_, itemLink = GetItemInfo(itemID)
			elseif bags then
				itemLink = GetContainerItemLink(container, slot)
			elseif bank then
				local bankSlot = slot - _G.BANK_CONTAINER_INVENTORY_OFFSET
				itemLink = GetContainerItemLink(_G.BANK_CONTAINER, bankSlot)
			elseif player then
				itemLink = GetInventoryItemLink('player', slot)
			end

			if not itemLink then
				-- item link not available, use generic
				local itemID = EquipmentManager_GetItemInfoByLocation(location)
				local oldItem = sets[setName][slotID]
				local oldItemID = oldItem and addon.GetLinkID(oldItem)

				if oldItemID and oldItemID == itemID then
					-- the item is the same, reuse old link
					itemLink = oldItem
				else
					_, itemLink = GetItemInfo(itemID)
				end
			end
			sets[setName][slotID] = itemLink:match('|H(.-)|h') or itemLink
		end
	end
end
local function UpdateEquipmentSets()
	local sets = equipment.ThisCharacter.EquipmentSets
	for setName, setInfo in pairs(sets) do
		local setID = C_EquipmentSet.GetEquipmentSetID(setName)
		if not setID then
			wipe(setInfo)
			sets[setName] = nil
		end
	end

	-- Nowadays, indices start at zero, it seems.
	for setID = 0, C_EquipmentSet.GetNumEquipmentSets() - 1 do
		local setName, setIcon = C_EquipmentSet.GetEquipmentSetInfo(setID)
		UpdateEquipmentSet(setName, setIcon)
	end
	equipment.ThisCharacter.lastUpdate = time()
end

local function _GetNumEquipmentSets(character)
	local count = 0
	for k, v in pairs(character.EquipmentSets) do
		count = count + 1
	end
	return count
end

local function _GetEquipmentSetNames(character)
	local setNames = {}
	for setName, items in pairs(character.EquipmentSets) do
		table.insert(setNames, setName)
	end
	table.sort(setNames)
	return setNames
end

local function _GetEquipmentSetItem(character, setName, slotID)
	local item = character.EquipmentSets[setName][slotID]
	local _, itemLink = GetItemInfo(item)
	return itemLink
end

local items = {}
local function _GetEquipmentSetItems(character, setName)
	wipe(items)
	for slotID, item in pairs(character.EquipmentSets[setName]) do
		local _, itemLink = GetItemInfo(item)
		items[slotID] = itemLink
	end
	return items
end

local function _GetEquipmentSet(character, setName)
	if not character.EquipmentSets[setName] then return end
	local icon = character.EquipmentSets[setName].icon
	local items = _GetEquipmentSetItems(character, setName)
	return setName, icon, items
end

function equipment:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, {
		GetNumEquipmentSets = _GetNumEquipmentSets,
		GetEquipmentSetNames = _GetEquipmentSetNames,
		GetEquipmentSet = _GetEquipmentSet,
		GetEquipmentSetItem = _GetEquipmentSetItem,
		GetEquipmentSetItems = _GetEquipmentSetItems,
	})
	-- TODO: sort out actual API and db structure
	DataStore:SetCharacterBasedMethod('GetNumEquipmentSets')
	DataStore:SetCharacterBasedMethod('GetEquipmentSetNames')
	DataStore:SetCharacterBasedMethod('GetEquipmentSet')
	DataStore:SetCharacterBasedMethod('GetEquipmentSetItem')
	DataStore:SetCharacterBasedMethod('GetEquipmentSetItems')
end
function equipment:OnEnable()
	self:RegisterEvent('BANKFRAME_OPENED', UpdateEquipmentSets)
	self:RegisterEvent('EQUIPMENT_SETS_CHANGED', UpdateEquipmentSets)

	UpdateEquipmentSets()
end
function equipment:OnDisable()
	self:UnregisterEvent('BANKFRAME_OPENED')
	self:UnregisterEvent('EQUIPMENT_SETS_CHANGED')
end
