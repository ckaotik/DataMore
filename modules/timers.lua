local addonName, addon = ...
local timers = addon:NewModule('Timers', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore, C_Garrison
-- GLOBALS: wipe, pairs, ipairs, next, strsplit, strjoin, time

local defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				Item = {},
				Spell = {}, -- crafting, toys
				-- Garrison = {},
				-- Calendar = {},
			}
		}
	},
}

-- --------------------------------------------------------
--  Scanning
-- --------------------------------------------------------
local function ScanItemStatus()
	-- TODO: scan equipped item cds + container items
end

local function ScanSpellStatus()
	-- TODO: scan profession cooldowns, toy cooldowns
	-- track cooldowns such as aura:24755, item:39878, item:44717
	-- addon:SendMessage("DATASTORE_ITEM_COOLDOWN_UPDATED", itemID)
end

-- --------------------------------------------------------
-- Mixins
-- --------------------------------------------------------
-- Setup
local PublicMethods = {
}

function timers:OnEnable()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end
end

function timers:OnDisable()
end
