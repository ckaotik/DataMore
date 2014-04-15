local addonName, addon, _ = ...
-- DataStore plugin that stores character's equipment sets
local equipment = addon:NewModule('equipment', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: GetNumEquipmentSets, GetEquipmentSetInfo, GetEquipmentSetInfoByName, GetEquipmentSetLocations, EquipmentManager_UnpackLocation, EquipmentManager_GetItemInfoByLocation, GetItemInfo, GetVoidItemInfo, GetContainerItemLink, GetInventoryItemLink
-- GLOBALS: time, pairs, wipe

local SLOT_MISSING, SLOT_INVALID, SLOT_IGNORED = -1, 0, 1
local function UpdateEquipmentSet(setName, setIcon)
	local sets = equipment.ThisCharacter.equipmentSets
	if not sets[setName] then
		sets[setName] = {}
	end
	sets[setName].icon = setIcon or sets[setName].icon

	-- local itemIDs = GetEquipmentSetItemIDs(setName)
	local locations = GetEquipmentSetLocations(setName)
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
			sets[setName][slotID] = itemLink
		end
	end
end
local function UpdateEquipmentSets()
	local sets = equipment.ThisCharacter.equipmentSets
	for setName, setInfo in pairs(sets) do
		local _, setID = GetEquipmentSetInfoByName(setName)
		if not setID then
			wipe(setInfo)
			sets[setName] = nil
		end
	end

	for setID = 1, GetNumEquipmentSets() do
		local setName, setIcon = GetEquipmentSetInfo(setID)
		UpdateEquipmentSet(setName, setIcon)
	end
	equipment.ThisCharacter.lastUpdate = time()
end

local function _GetNumEquipmentSets(character)
	local count = 0
	for k, v in pairs(character.equipmentSets) do
		count = count + 1
	end
	return count
end

local function _GetEquipmentSetNames(character)
	local setNames = {}
	for setName, items in pairs(character.equipmentSets) do
		table.insert(setNames, setName)
	end
	table.sort(setNames)
	return setNames
end

local function _GetEquipmentSet(character, setName)
	local set = character.equipmentSets[setName]
	return setName, set.icon, set
end

local function _GetEquipmentSetItem(character, setID, slotID)
	return character.equipmentSets[setID][slotID]
end

function equipment:OnInitialize()
	equipment.db = LibStub("AceDB-3.0"):New('DataMore_EquipmentDB', {
		global = {
			Characters = {
				['*'] = {
					lastUpdate = nil,
					equipmentSets = {},
				}
			}
		}
	})

	DataStore:RegisterModule('DataMore_Equipment', equipment, {
		GetNumEquipmentSets = _GetNumEquipmentSets,
		GetEquipmentSetNames = _GetEquipmentSetNames,
		GetEquipmentSet = _GetEquipmentSet,
		GetEquipmentSetItem = _GetEquipmentSetItem,
	})
	-- TODO: sort out actual API and db structure
	DataStore:SetCharacterBasedMethod('GetNumEquipmentSets')
	DataStore:SetCharacterBasedMethod('GetEquipmentSetNames')
	DataStore:SetCharacterBasedMethod('GetEquipmentSet')
	DataStore:SetCharacterBasedMethod('GetEquipmentSetItem')
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
