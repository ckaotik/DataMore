local addonName, addon = ...
local lockouts = addon:NewModule('Timers', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS:
-- GLOBALS:

local thisCharacter = DataStore:GetCharacter()

-- track cooldowns such as aura:24755, item:39878, item:44717
-- addon:SendMessage("DATASTORE_ITEM_COOLDOWN_UPDATED", itemID)

local function UpdateSavedBosses()
	local bosses = lockouts.ThisCharacter.WorldBosses
	wipe(bosses)
	for i = 1, GetNumSavedWorldBosses() do
		local name, id, reset = GetSavedWorldBossInfo(i)
		bosses[id] = time() + reset
	end
	lockouts.ThisCharacter.lastUpdate = time()
end

-- Mixins
--[[ function lockouts.GetLFGInfo(character, dungeonID)
	local instanceInfo = character.LFGs[dungeonID]
	if not instanceInfo then return end
end --]]

-- setup
local PublicMethods = {
	-- Looking for Group
	-- GetLFGs                  = lockouts.GetLFGs,
}

function lockouts:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', {
		global = {
			Characters = {
				['*'] = {				-- ["Account.Realm.Name"]
					lastUpdate = nil,
					ItemCooldowns = {},
					SpellCooldowns = {},
				}
			}
		},
	}, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	for methodName in pairs(PublicMethods) do
		DataStore:SetCharacterBasedMethod(methodName)
	end
end

function lockouts:OnEnable()
	self.db.char.lastUpdate = time()
	-- self:RegisterEvent('LFG_LOCK_INFO_RECEIVED', UpdateLFGStatus)

	-- clear expired
	--[[ local now = time()
	for characterKey, character in pairs(self.db.global.Characters) do
		for dungeonID, data in pairs(character.LFGs) do
			local status, reset, numDefeated = strsplit('|', data)
			              reset = tonumber(reset)
			if status ~= '1' and status ~= '0' then
				character.LFGs[dungeonID] = strtrim(status, ':')
			elseif reset and reset ~= 0 and reset < now then
				-- had lockout, lockout expired, LFG is available
				character.LFGs[dungeonID] = 0
			end
		end
	end --]]
end

function lockouts:OnDisable()
	-- self:UnregisterEvent('LFG_LOCK_INFO_RECEIVED')
end
