-- if true then return end

local addonName, addon, _ = ...
local mails = addon:NewModule('Mails', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: GetInboxHeaderInfo, GetItemInfo, GetSendMailItem, GetSendMailItemLink, UnitFullName, GetRealmName, GetSendMailMoney, GetSendMailCOD, GetInboxItem, GetInboxItemLink, GetInboxNumItems
-- GLOBALS: hooksecurefunc, time, strjoin, strsplit, wipe, pairs, table

local thisCharacter = DataStore:GetCharacter()

local DEFAULT_STATIONERY = 'Interface\\Icons\\INV_Misc_Note_01'

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Options = {
			ReadMails = false,
		},
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				Mails = {
					['*'] = {
						sender = nil,
						subject = nil,
						message = nil,
						stationery = nil,
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
				lastUpdate = nil,
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
	mail.money = ((money and money > 0) and money) or ((CODAmount and CODAmount > 0) and -1*CODAmount) or 0
	mail.expires = time() + daysLeft*24*60*60
	mail.lastUpdate = time()

	if addon.db.global.Options['ReadMails'] then
		-- this marks mail as read
		mail.message = GetInboxText(index)
	end

	mail.attachments = {}
	for attachmentIndex = 1, _G.ATTACHMENTS_MAX_RECEIVE do
		local itemLink = GetInboxItemLink(index, attachmentIndex)
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
	local recipientName, recipientRealm = strsplit('-', recipient)
	if not recipientRealm or recipientRealm == '' then
		recipientRealm = GetRealmName('player')
	end
	recipientName, recipientRealm = recipientName:lower(), recipientRealm:lower()

	-- figure out who this mail goes to
	local recipientKey
	for account in pairs(DataStore:GetAccounts()) do
		for realm in pairs(DataStore:GetRealms(account)) do
			if recipientRealm == realm:lower():gsub(' ', '') then
				for characterName, characterKey in pairs(DataStore:GetCharacters(account, realm)) do
					if characterName == recipientName then
						-- found the recipient!
						recipientKey = characterKey
					end
					if recipientKey then break end
				end
			end
			if recipientKey then break end
		end
		if recipientKey then break end
	end

	-- TODO: check guildies (@see DataStore_Mails:SendGuildMail())
	if not recipientKey or recipientKey == thisCharacter then return end

	local character = mails.db.global.Characters[recipientKey]
	local mail = {}

	local money     = GetSendMailMoney()
	local CODAmount = GetSendMailCOD()

	mail.sender  = strjoin('-', UnitFullName('player'))
	mail.subject = subject
	mail.message = body
	mail.money = ((money and money > 0) and money) or ((CODAmount and CODAmount > 0) and -1*CODAmount) or 0
	mail.expires = time() + 30*24*60*60
	mail.lastUpdate = time()

	for index = 1, _G.ATTACHMENTS_MAX_SEND do
		local _, _, count = GetSendMailItem(index)
		local itemLink = GetSendMailItemLink(index)
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

	table.insert(character.Mails, mail)
	table.sort(character.Mails, function(a, b)
		return a.expires < b.expires
	end)
	if not character.lastUpdate then
		character.lastUpdate = time()
	end
end

-- --------------------------------------------------------
local function _GetMail(character, mailIndex)
	return character.Mails[mailIndex]
end

-- @returns mailIcon, mailStationaryTexture
local function _GetMailStyle(character, mailIndex)
	local mail = _GetMail(character, mailIndex)
	local icon, stationery = 'Interface\\Icons\\INV_Misc_Note_01', DEFAULT_STATIONERY

	if mail then
		stationery = mail.stationery or stationery
		if #mail.attachments > 0 then
			-- show icon of first available item
			for attachmentIndex = 1, _G.ATTACHMENTS_MAX_RECEIVE do
				local attachment = mail.attachments[attachmentIndex]
				if attachment and attachment.count > 0 then
					local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(attachment.itemID)
					icon = texture
					break
				end
			end
		elseif mail.money then
			-- show money icon
			icon = 'Interface\\Icons\\INV_Misc_Coin_01'
		end
	end
	return icon, stationery
end

-- setup
local PublicMethods = {
	GetMailStyle = _GetMailStyle,
}

function mails:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', AddonDB_Defaults)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	DataStore:SetCharacterBasedMethod('GetMailStyle')
end

function mails:OnEnable()
	hooksecurefunc('SendMail', OnSendMail)

	-- self:RegisterEvent('LFG_LOCK_INFO_RECEIVED', UpdateLFGStatus)
end

function mails:OnDisable()
	-- self:UnregisterEvent('LFG_LOCK_INFO_RECEIVED')
end
