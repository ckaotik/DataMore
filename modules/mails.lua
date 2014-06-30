if true then return end

local addonName, addon, _ = ...
local moduleName = 'DataMore_Mails'
local mails      = addon:NewModule('mails', 'AceEvent-3.0') -- 'AceConsole-3.0'

local characters    = DataStore:GetCharacters() -- TODO: heirlooms may be mailed x-realm!
local thisCharacter = DataStore:GetCharacter()
local realm = GetRealmName()
      realm = realm:gsub(' ', '')

local DEFAULT_STATIONERY = 'Interface\\Icons\\INV_Misc_Note_01'
local DEFAULT_ICON = 'Interface\\Icons\\INV_Crate_02'

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				Mails = {
					['*'] = {
						sender = nil,
						subject = nil,
						message = nil,
						stationery = DEFAULT_STATIONERY,
						expires = 0, -- x < 0: deleted in x, x > 0: returned in x
						lastUpdate = nil,

						money = 0, -- x < 0: COD, x > 0: earned
						attachments = {
							['*'] = {
								itemID = nil,
								itemLink = nil, -- only used if item is enchanted etc
								count = 0,
							},
						},
					}
				},
			}
		}
	}
}

local function ScanMail(mails, index)
	local mail = {}

	local icon, stationery, sender, subject, money, CODAmount, daysLeft, numAttachments, wasRead, wasReturned, textCreated, canReply = GetInboxHeaderInfo(index)

	-- local senderName, senderRealm = strsplit('-', sender)
	mail.sender = sender
	mail.subject = subject
	mail.stationery = stationery ~= DEFAULT_STATIONERY and stationery or nil
	mail.money = money > 0 and money or -1*CODAmount
	mail.expires = time() + daysLeft*24*60*60
	mail.lastUpdate = time()

	--[[
	-- this marks mail as read
	local bodyText, texture, isTakeable, isInvoice = GetInboxText(index)
	mail.message = bodyText
	if isInvoice then
		local invoiceType, itemName, playerName, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin = GetInboxInvoiceInfo(index)
	end
	--]]

	mail.attachments = {}
	for attachmentIndex = 1, _G.ATTACHMENTS_MAX_RECEIVE do
		local itemlink = GetInboxItemLink(index, attachmentIndex)
		local _, _, count = GetInboxItem(index, attachmentIndex)
		if itemLink then
			local itemID = mails.GetLinkID(itemLink)
			local _, simpleLink = GetItemInfo(itemID)
			table.insert(mail.attachments, {
				itemID = itemID,
				itemLink = itemLink ~= simpleLink and itemLink or nil,
				count = count,
			})
		end
	end

	table.insert(mails.ThisCharacter.Mails, mail)
end

local function ScanInbox()
	local character = mails.ThisCharacter
	wipe(character.Mails)

	for index = 1, GetInboxNumItems() do
		ScanMail(index)
	end
end

local function OnSendMail(recipient, subject, body)
	recipient = recipient:lower()
	for characterName, characterKey in pairs(characters) do
		characterName = characterName:lower()
		if recipient == characterName or recipient == characterName..'-'..realm then
			return
		end

		if strlower(characterName) == strlower(recipient) then						-- if recipient is a known alt ..
			local character = mails.db.global.Characters[characterKey]

			if mailAttachments then
				for k, v in pairs(mailAttachments) do		--  .. save attachments into his mailbox
					table.insert(character.Mails, {				-- not in the mail cache, since they arrive directly in an alt's mailbox
						icon = v.icon,
						link = v.link,
						count = v.count,
						sender = UnitName('player'),
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
					sender = UnitName('player'),
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

function mails:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(moduleName .. 'DB', AddonDB_Defaults)

	DataStore:RegisterModule(moduleName, self, PublicMethods)
	-- DataStore:SetCharacterBasedMethod("GetCurrencyCaps")
end

function mails:OnEnable()
	hooksecurefunc('SendMail', OnSendMail)

	-- self:RegisterEvent("LFG_LOCK_INFO_RECEIVED", UpdateLFGStatus)
end

function mails:OnDisable()
	-- self:UnregisterEvent("LFG_LOCK_INFO_RECEIVED")
end
