local addonName, addon, _ = ...
local plugin = addon:NewModule('Wardrobe', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS:
-- GLOBALS: time, pairs, wipe

local defaults = {
	global = {
		Appearances = {
			['*'] = { -- categoryID
				-- visualID
			},
		},
		Characters = {
			['*'] = {
				lastUpdate = nil,
			}
		}
	}
}

local function AddAppearance(categoryID, appearance)
	table.insert(plugin.db.global.Appearances[categoryID], appearance.visualID)
end

local function ScanTransmogCollection()
	for i = 1, #_G.TRANSMOG_SLOTS do
		local categoryID = TRANSMOG_SLOTS[i].armorCategoryID
		local slot = TRANSMOG_SLOTS[i].slot
		if _G.TRANSMOG_SLOTS[i].transmogType == _G.LE_TRANSMOG_TYPE_APPEARANCE then
			if categoryID then
				local appearances = C_TransmogCollection.GetCategoryAppearances(categoryID)
				for j, appearance in ipairs(appearances) do
					AddAppearance(categoryID, appearance)
				end
			else
				for categoryID = _G.FIRST_TRANSMOG_COLLECTION_WEAPON_TYPE, _G.LAST_TRANSMOG_COLLECTION_WEAPON_TYPE do
					local name, isWeapon, canEnchant, canMainHand, canOffHand = C_TransmogCollection.GetCategoryInfo(categoryID)
					if name and isWeapon and (
						(slot == 'MAINHANDSLOT' and canMainHand) or
						(slot == 'SECONDARYHANDSLOT' and canOffHand)
					) then
						local appearances = C_TransmogCollection.GetCategoryAppearances(categoryID)
						for j, appearance in ipairs(appearances) do
							AddAppearance(categoryID, appearance)
						end
					end
				end
			end
		end
	end

	plugin.ThisCharacter.lastUpdate = time()
end

local function _IsAppearanceCollected(visualID, limitCategoryID)
	local found = false
	for categoryID, appearances in pairs(plugin.db.global.Appearances) do
		if not limitCategoryID or categoryID == limitCategoryID then
			found = tContains(appearances, visualID)
		end
		if found then break end
	end
	return found and true or false
end

local function _IsItemAppearanceCollected(item)
	local itemLink = select(2, GetItemInfo(item))
	-- TODO
	-- C_TransmogCollection.PlayerHasTransmog(itemID, itemAppearanceModID)
end

function plugin:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, {
		IsAppearanceCollected = _IsAppearanceCollected,
		IsItemAppearanceCollected = _IsItemAppearanceCollected,
	})
	-- DataStore:SetCharacterBasedMethod('GetNumEquipmentSets')
end
function plugin:OnEnable()
	self:RegisterEvent('TRANSMOG_COLLECTION_UPDATED', ScanTransmogCollection)
	ScanTransmogCollection()
end
function plugin:OnDisable()
	self:UnregisterEvent('TRANSMOG_COLLECTION_UPDATED')
end

	--[[
		C_TransmogCollection.GetIllusions()
		C_TransmogCollection.GetOutfits()
		C_TransmogCollection.GetAppearanceSources()
		C_TransmogCollection.PlayerHasTransmog()

	  	local isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotTransmogrifyReason, hasUndo, isHideVisual, texture = C_Transmog.GetSlotInfo(slotID, _G.LE_TRANSMOG_TYPE_APPEARANCE)

		TRANSMOG_COLLECTION_UPDATED

		category = WardrobeCollectionFrame_GetArmorCategoryIDFromSlot(slot)
		category = C_TransmogCollection.GetAppearanceSourceInfo(selectedSourceID)
		C_TransmogCollection.GetCategoryAppearances(categoryID)
	--]]

	-- Item Link => Transmog Source => Visual ID
	-- C_TransmogCollection.PlayerKnowsSource(sourceID)
	-- C_TransmogCollection.GetShowMissingSourceInItemTooltips()
	-- /run C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
	-- C_TransmogCollection.PlayerCanCollectSource(sourceID)
	-- C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(itemModifiedAppearanceID)
	-- local transmogKnown = C_TransmogCollection.PlayerHasTransmog(itemID, itemAppearanceModID)

	-- local itemID, class, subClass, equipSlot, texture, classID, subClassID = GetItemInfoInstant(item)

	--[[
	SPELL_FAILED_CUSTOM_ERROR_281 = "Ihr habt diese Vorlagen bereits gesammelt."
	SPELL_FAILED_CUSTOM_ERROR_289 = "Ihr habt diese Vorlage bereits gesammelt."
	TRANSMOGRIFY_STYLE_UNCOLLECTED = "Ihr habt diese Vorlage noch nicht gesammelt."
	TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN = "Ihr habt diese Vorlage bereits gesammelt."
	TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN = "Ihr habt diese Vorlage noch nicht gesammelt."
	TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN = "Ihr habt diese Vorlage bereits von einem anderen Gegenstand erhalten."
	--]]
