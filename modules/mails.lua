local addonName, addon, _ = ...
local mails = addon:NewModule('Mails', 'AceEvent-3.0')

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: GetInboxHeaderInfo, GetItemInfo, GetSendMailItem, GetSendMailItemLink, UnitFullName, GetRealmName, GetSendMailMoney, GetSendMailCOD, GetInboxText, GetInboxItem, GetInboxItemLink, GetInboxNumItems
-- GLOBALS: hooksecurefunc, time, strjoin, strsplit, wipe, pairs, table, type

local thisCharacter = DataStore:GetCharacter()
local playerRealm

local DEFAULT_STATIONERY = 'Interface\\Icons\\INV_Misc_Note_01'
local STATUS_UNREAD, STATUS_READ, STATUS_RETURNED, STATUS_RETURNED_READ = 0, 1, 2, 3

-- these subtables need unique identifier
local AddonDB_Defaults = {
	global = {
		Settings = {
			ReadMails = false,
		},
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				Mails = {
					['*'] = {
						sender = nil,
						subject = '',
						message = '',
						stationery = DEFAULT_STATIONERY,
						expires = 0,
						status = STATUS_UNREAD,
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

local function GetRecipientKey(recipient, realm)
	if recipient and realm then
		-- yes, I'm that lazy
		recipient = strjoin('-', recipient, realm:gsub(' ', ''))
	end
	local recipientName, recipientRealm = strsplit('-', recipient)
	if not recipientRealm or recipientRealm == '' then
		recipientRealm = playerRealm
	end
	recipientName, recipientRealm = recipientName:lower(), recipientRealm:lower()

	-- figure out who this mail goes to
	local recipientKey
	for account in pairs(DataStore:GetAccounts()) do
		for realm in pairs(DataStore:GetRealms(account)) do
			if recipientRealm == realm:lower():gsub(' ', '') then
				for characterName, characterKey in pairs(DataStore:GetCharacters(realm, account)) do
					if characterName:lower() == recipientName then
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
	return recipientKey
end

local function ScanMail(index, ...)
	if not index then return end

	local character, isInbox
	local sender, subject, message, money, CODAmount, daysLeft, status, stationery
	if type(index) == 'number' then
		-- inbox
		character = mails.ThisCharacter
		isInbox = true

		-- marks mail as read
		message = mails.db.global.Settings['ReadMails'] and GetInboxText(index) or nil
		local wasRead, wasReturned, icon
		icon, stationery, sender, subject, money, CODAmount, daysLeft, _, wasRead, wasReturned = GetInboxHeaderInfo(index)
		if not icon or not sender then return end

		status = (wasReturned and wasRead and STATUS_RETURNED_READ)
			or (wasReturned and STATUS_RETURNED)
			or (wasRead and STATUS_READ)
			or STATUS_UNREAD
		sender = sender:find('-') and sender or strjoin('-', sender, playerRealm)
	else
		-- outbox
		character = mails.db.global.Characters[index]

		_, subject, message = ...
		daysLeft, status, stationery = 30, STATUS_UNREAD, DEFAULT_STATIONERY
		money, CODAmount = GetSendMailMoney(), GetSendMailCOD()
		sender  = strjoin('-', UnitFullName('player'))
	end

	table.insert(character.Mails, {})
	local mail = character.Mails[ #character.Mails ]

	mail.sender = sender
	mail.subject = subject
	mail.message = message
	mail.stationery = stationery ~= DEFAULT_STATIONERY and stationery or nil
	mail.money = ((money and money > 0) and money) or ((CODAmount and CODAmount > 0) and -1*CODAmount) or 0
	mail.expires = math.floor(time() + daysLeft*24*60*60)
	mail.status = status
	mail.lastUpdate = time()

	mail.attachments = {}
	for attachmentIndex = 1, isInbox and _G.ATTACHMENTS_MAX_RECEIVE or _G.ATTACHMENTS_MAX_SEND do
		local itemLink, count
		if isInbox then
			itemLink    = GetInboxItemLink(index, attachmentIndex)
			_, _, count = GetInboxItem(index, attachmentIndex)
		else
			itemLink    = GetSendMailItemLink(attachmentIndex)
			_, _, count = GetSendMailItem(attachmentIndex)
		end

		if itemLink then
			table.insert(mail.attachments, {
				itemID = addon.GetLinkID(itemLink),
				itemLink = not addon.IsBaseLink(itemLink) and itemLink or nil,
				count = count,
			})
		end
	end

	if not isInbox then
		table.sort(character.Mails, function(a, b)
			return a.expires < b.expires
		end)
		if not character.lastUpdate then
			-- apply lastUpdate so data is considered valid
			character.lastUpdate = 0
		end
	end
end

local function ScanInbox()
	local character = mails.ThisCharacter
	wipe(character.Mails)

	for index = 1, GetInboxNumItems() do
		ScanMail(index)
	end

	character.lastUpdate = time()
end

local function OnSendMail(recipient, subject, body)
	local recipientKey = GetRecipientKey(recipient)
	-- TODO: check guildies (@see DataStore_Mails:SendGuildMail())

	if not recipientKey or recipientKey == thisCharacter then return end
	ScanMail(recipientKey, recipient, subject, body)
end

local function OnReturnMail(mailIndex)
	-- Note: GetInboxHeaderInfo(mailIndex), GetInboxItemLink & CO WORK HERE!
	local mail = mails.ThisCharacter.Mails[mailIndex]
	local recipientKey = GetRecipientKey(mail.sender)
	mail.sender = thisCharacter
	mail.status = STATUS_RETURNED
	table.insert(mails.db.global.Characters[recipientKey].Mails, mail)
end

local function OnOpenMail()
	-- this handles a one-time scan when opening the mail frame
	ScanInbox()
	mails:UnregisterEvent('MAIL_INBOX_UPDATE')
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
	_, playerRealm = UnitFullName('player')

	hooksecurefunc('SendMail', OnSendMail)
	hooksecurefunc('ReturnInboxItem', OnReturnMail)
	-- we don't handle DeleteInboxItem since MAIL_SUCCESS fires directly afterwards

	self:RegisterEvent('MAIL_SUCCESS', ScanInbox)
	self:RegisterEvent('MAIL_SHOW', function()
		self:RegisterEvent('MAIL_INBOX_UPDATE', OnOpenMail)
	end)
end

function mails:OnDisable()
	self:UnregisterEvent('MAIL_SHOW')
	self:UnregisterEvent('MAIL_CLOSED')
	self:UnregisterEvent('MAIL_INBOX_UPDATE')
	self:UnregisterEvent('MAIL_SUCCESS')
end
