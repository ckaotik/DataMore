if true then return end

local addonName, ns, _ = ...

local addonName  = "DataMore_Mails"
local addon      = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
   _G[addonName] = addon

local characters    = DataStore:GetCharacters()
local thisCharacter = DataStore:GetCharacter()
local realm = GetRealmName()
      realm = realm:gsub(' ', '')

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				LFGs = {},
			}
		}
	}
}

local function SendMail_Hook(recipient, subject, body, ...)
	recipient = recipient:lower()
	for characterName, characterKey in pairs(characters) do
		characterName = characterName:lower()
		if recipient == characterName or recipient == characterName..'-'..realm then
			return
		end

		if strlower(characterName) == strlower(recipient) then						-- if recipient is a known alt ..
			local character = addon.db.global.Characters[characterKey]

			if mailAttachments then
				for k, v in pairs(mailAttachments) do		--  .. save attachments into his mailbox
					table.insert(character.Mails, {				-- not in the mail cache, since they arrive directly in an alt's mailbox
						icon = v.icon,
						link = v.link,
						count = v.count,
						sender = UnitName("player"),
						lastCheck = time(),
						daysLeft = 30,
					} )
				end
			end

			-- .. then save the mail itself + gold if any
			local moneySent = GetSendMailMoney()
			if (moneySent > 0) or (strlen(body) > 0) then
				local mailIcon
				if moneySent > 0 then
					mailIcon = ICON_COIN
				else
					mailIcon = ICON_NOTE
				end
				table.insert(character.Mails, {
					money = moneySent,
					icon = mailIcon,
					text = body,
					subject = subject,
					sender = UnitName("player"),
					lastCheck = time(),
					daysLeft = 30,
				} )
			end

			-- if the alt has never checked his mail before, this value won't be correct, so set it to make sure expiry returns proper results.
			character.lastUpdate = time()

			table.sort(character.Mails, function(a, b)		-- show mails with the lowest expiry first
				return a.daysLeft < b.daysLeft
			end)

			isRecipientAnAlt = true
			break
		end
	end
end

-- setup
local PublicMethods = {
	-- GetCurrencyCaps = _GetCurrencyCaps,
}

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)

	DataStore:RegisterModule(addonName, addon, PublicMethods)
	-- DataStore:SetCharacterBasedMethod("GetCurrencyCaps")
end

function addon:OnEnable()
	hooksecurefunc('SendMail', SendMail_Hook)

	-- addon:RegisterEvent("LFG_LOCK_INFO_RECEIVED", UpdateLFGStatus)
end

function addon:OnDisable()
	-- addon:UnregisterEvent("LFG_LOCK_INFO_RECEIVED")
end
