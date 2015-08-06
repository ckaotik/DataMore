local addonName, addon, _ = ...
local mails = addon:NewModule('Mails', 'AceEvent-3.0', 'AceComm-3.0', 'AceSerializer-3.0')

-- TODO: add "inbox mail" on successfull purchase on auction house

local commPrefix = 'DS_Mails'
local MSG_SENDMAIL_INIT, MSG_SENDMAIL_END, MSG_SENDMAIL_ATTACHMENT, MSG_SENDMAIL_BODY = 1, 2, 3, 4

-- GLOBALS: _G, LibStub, DataStore
-- GLOBALS: GetInboxHeaderInfo, GetItemInfo, GetSendMailItem, GetSendMailItemLink, UnitFullName, GetRealmName, GetSendMailMoney, GetSendMailCOD, GetInboxText, GetInboxItem, GetInboxItemLink, GetInboxNumItems, Ambiguate, GetItemIcon
-- GLOBALS: hooksecurefunc, time, strjoin, strsplit, wipe, pairs, ipairs, table, type, coroutine

local thisCharacter = DataStore:GetCharacter()
local playerRealm

local DEFAULT_STATIONERY = 'Interface\\ICONS\\INV_Misc_Note_01.blp'
local STATUS_UNREAD, STATUS_READ, STATUS_RETURNED, STATUS_RETURNED_READ = 0, 1, 2, 3

local defaults = {
	global = {
		Settings = {
			ReadMails = false,
		},
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				Mails = {
					['*'] = {
						sender = nil,
						subject = '',
						message = '',
						stationery = DEFAULT_STATIONERY,
						expires = 0,
						status = STATUS_UNREAD,

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

-- Data Gathering
-- --------------------------------------------------------
local function IsRecipientKnown(recipient, realm)
	if recipient and realm then recipient = recipient .. '-' .. realm:gsub(' ', '') end
	local recipientName, recipientRealm = strsplit('-', recipient)
	if not recipientRealm or recipientRealm == '' then
		recipientRealm = playerRealm
	end
	recipientName, recipientRealm = recipientName:lower(), recipientRealm:lower()

	local contactName = nil
	local isFriend, isGuildMember = false, false
	-- plain old realm contacts
	if DataStore:GetContactInfo(thisCharacter, recipientName)
		or DataStore:GetContactInfo(thisCharacter, recipient) then
		isFriend = true
		contactName = recipient
	end

	-- battle tag / realID contacts
	local isBNetFriend
	for friendIndex = 1, BNGetNumFriends() do
		local focussedToon
		for toonIndex = 1, BNGetNumFriendToons(friendIndex) do
			local hasFocus, toonName, client, realmName, realmID, faction = BNGetFriendToonInfo(friendIndex, toonIndex)
			if hasFocus and client == _G.BNET_CLIENT_WOW then
				-- this allows us to override the whisper recipient
				focussedToon = toonName .. '-' .. realmName:gsub(' ', '')
			end
			if client == _G.BNET_CLIENT_WOW then
				local toonCompare, realmCompare  = toonName:lower(), realmName:gsub(' ', ''):lower()
				if toonCompare == recipientName and realmCompare == recipientRealm then
					focussedToon = focussedToon or toonName .. '-' .. realmName
					isBNetFriend = true
				end
				if hasFocus then
					-- this allows us to override the whisper recipient
					focussedToon = toonName .. '-' .. realmName:gsub(' ', '')
				end
			end
		end
		if isBNetFriend then
			contactName = focussedToon
			break
		end
	end

	-- guild members
	local recipientName = Ambiguate(recipient, 'guild')
	local player = DataStore:GetNameOfMain(recipientName)
	-- TODO: FIXME: we only care about guild member using DataStore
	if player and DataStore:IsGuildMemberOnline(player) then
		isGuildMember = true
		contactName = player
	end

	return contactName, isGuildMember, isFriend, isBNetFriend
end

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

	local isInbox = index > 0
	local sender, subject, message, money, CODAmount, daysLeft, status, stationery
	if isInbox then
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
		_, subject, message = ...
		daysLeft, status, stationery = 30, STATUS_UNREAD, DEFAULT_STATIONERY
		money, CODAmount = GetSendMailMoney(), GetSendMailCOD()
		sender  = strjoin('-', UnitFullName('player'))
	end

	local mail = {}
	mail.sender = sender
	mail.subject = subject
	mail.message = message
	mail.stationery = stationery ~= DEFAULT_STATIONERY and stationery or nil
	mail.money = ((money and money > 0) and money) or ((CODAmount and CODAmount > 0) and -1*CODAmount) or 0
	mail.expires = math.floor(time() + daysLeft*24*60*60)
	mail.status = status

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

	return mail
end

local function StoreForeignMail(mail, recipientKey)
	if not recipientKey or not mail then return end
	local character = mails.db.global.Characters[recipientKey]
	table.insert(character.Mails, mail)
	-- keep sorting intact
	table.sort(character.Mails, function(a, b)
		return a.expires < b.expires
	end)

	if not character.lastUpdate then
		-- apply lastUpdate so data is considered valid
		character.lastUpdate = 0
	end
end

-- takes required actions when a mail is sent (either via outbox or as a retour)
local function HandleMail(mail, recipient)
	local recipientKey = GetRecipientKey(recipient)
	if recipientKey then
		-- recipient is an alt
		StoreForeignMail(mail, recipientKey)
	else
		-- TODO: also notify when recipient is a friend
		local contactName, isGuild, isFriend, isBNFriend = IsRecipientKnown(recipient)

		-- might be a guild member
		-- local recipientName = Ambiguate(recipient, 'guild')
		-- local player = DataStore:GetNameOfMain(recipientName)
		-- if player and DataStore:IsGuildMemberOnline(player) then
		if isGuild then
			mails:NotifyGuild(mail, contactName, recipient)
		end
	end
end

local sentMail -- temporary storage for mails until MAIL_SUCCESS fires
local function ScanInbox()
	if sentMail then
		local recipient = sentMail.recipient
		sentMail.recipient = nil
		HandleMail(sentMail, recipient)
		sentMail = nil
	end

	local character = mails.ThisCharacter
	wipe(character.Mails)

	for index = 1, GetInboxNumItems() do
		local mail = ScanMail(index)
		table.insert(character.Mails, mail)
	end
	character.lastUpdate = #character.Mails > 0 and time() or nil
end

function mails:NotifyGuild(mail, player, recipientName)
	-- we inform <player> that her character <recipientName> received mail
	local data = mails:Serialize(MSG_SENDMAIL_INIT, recipientName)
	mails:SendCommMessage(commPrefix, data, 'WHISPER', player)

	for index, attachment in ipairs(mail.attachments) do
		local icon = GetItemIcon(attachment.itemID)
		local link = attachment.itemLink or select(2, GetItemInfo(attachment.itemID))
		local data = mails:Serialize(MSG_SENDMAIL_ATTACHMENT, icon, link, attachment.count)
		mails:SendCommMessage(commPrefix, data, 'WHISPER', player)
	end

	if mail.money ~= 0 or mail.message ~= '' then
		local data = mails:Serialize(MSG_SENDMAIL_BODY, mail.subject, mail.message, mail.money)
		mails:SendCommMessage(commPrefix, data, 'WHISPER', player)
	end
	mails:SendCommMessage(commPrefix, mails:Serialize(MSG_SENDMAIL_END), 'WHISPER', player)
end

-- called on SendMail(), but may fail with MAIL_FAILED due to invalid recipient
local function OnSendMail(recipient, subject, body)
	sentMail = ScanMail(0, recipient, subject, body)
	sentMail.recipient = recipient
end

-- called on ReturnMail()
local function OnReturnMail(mailIndex)
	local mail = mails.ThisCharacter.Mails[mailIndex]
	local recipient = mail.sender
	      mail.sender = thisCharacter
	      mail.status = STATUS_RETURNED
	HandleMail(mail, recipient)
end

local function OnOpenMail()
	-- this handles a one-time scan when opening the mail frame
	ScanInbox()
	mails:UnregisterEvent('MAIL_INBOX_UPDATE')
end

-- Mixins
-- --------------------------------------------------------
function mails.GetNumMails(character)
	return #(character.Mails)
end

function mails.GetMail(character, mailIndex)
	return character.Mails[mailIndex]
end

-- @returns mailIcon, mailStationaryTexture
function mails.GetMailStyle(character, mailIndex)
	local mail = mails.GetMail(character, mailIndex)
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

-- icon, stationery, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply, isGM, itemQuantity = GetInboxHeaderInfo(index)

-- Communication
-- --------------------------------------------------------
local function HandleGuildNotification(args)
	local sender, recipientName = unpack(args)
	if not sender:find('-') then -- must be same realm then
		sender = sender .. '-' .. select(2, UnitFullName('player'))
	end
	-- local recipientKey = strjoin('.', 'Default', GetRealmName(), recipientName) -- TODO: this can't be correct
	local mail = {
		sender = sender, -- TODO: handle realm name for people from other realms
		attachments = {},
	}

	-- TODO: mails in transit ("pending") if non guild member
	-- mail.status = timeOfArrival
	local contactName, isGuild, isFriend, isBNFriend = IsRecipientKnown(sender)

	coroutine.yield()

	-- can be triggered multiple times
	while args.event == MSG_SENDMAIL_ATTACHMENT do
		local _, icon, itemLink, count = unpack(args)
		table.insert(mail.attachments, {
			itemID = addon.GetLinkID(itemLink),
			itemLink = not addon.IsBaseLink(itemLink) and itemLink or nil,
			count = count,
		})
		coroutine.yield()
	end

	if args.event == MSG_SENDMAIL_BODY then
		local _, subject, body, money = unpack(args)
		mail.subject = subject
		mail.message = body
		mail.money   = money
		coroutine.yield()
	end

	if args.event == MSG_SENDMAIL_END then
		-- HandleMail(mail, recipientName)
		mails:SendMessage('DATASTORE_GUILD_MAIL_RECEIVED', sender, recipientName)
	end
end

local commRoutine, commArgs = nil, {}
local function ResumeRoutine(event, ...)
	wipe(commArgs)
	for i = 1, select('#', ...) do
		commArgs[i] = select(i, ...)
	end
	commArgs.event = event
	commRoutine(commArgs) -- args are only accepted on first start
end
local GuildCommCallbacks = {
	[MSG_SENDMAIL_INIT] = function(...)
			commRoutine = coroutine.wrap(HandleGuildNotification)
			ResumeRoutine(MSG_SENDMAIL_INIT, ...)
		end,
	[MSG_SENDMAIL_ATTACHMENT] = function(...) ResumeRoutine(MSG_SENDMAIL_ATTACHMENT, ...) end,
	[MSG_SENDMAIL_BODY]       = function(...) ResumeRoutine(MSG_SENDMAIL_BODY, ...) end,
	[MSG_SENDMAIL_END]        = function(...) ResumeRoutine(MSG_SENDMAIL_END, ...) end,
}

-- setup
-- --------------------------------------------------------
local PublicMethods = {
	-- TODO: MOAAAARR! We need more!
	-- GetNumMails = mails.GetNumMails,
	-- GetMailboxLastVisit = _GetMailboxLastVisit,
	-- GetMailItemCount = _GetMailItemCount,
	-- GetMailAttachments = _GetMailAttachments,
	-- GetMailInfo = _GetMailInfo,
	-- GetMailSender = _GetMailSender,
	-- GetMailExpiry = _GetMailExpiry,
	-- GetMailSubject = _GetMailSubject,
	-- GetNumExpiredMails = _GetNumExpiredMails,
	GetMailStyle = mails.GetMailStyle,
}

function mails:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(self.name .. 'DB', defaults, true)

	DataStore:RegisterModule(self.name, self, PublicMethods)
	DataStore:SetCharacterBasedMethod('GetMailStyle')

	DataStore:SetGuildCommCallbacks(commPrefix, GuildCommCallbacks)
end

function mails:OnEnable()
	_, playerRealm = UnitFullName('player')

	hooksecurefunc('SendMail', OnSendMail)
	hooksecurefunc('ReturnInboxItem', OnReturnMail)
	-- we don't handle DeleteInboxItem since MAIL_SUCCESS fires directly afterwards

	self:RegisterEvent('MAIL_SUCCESS', ScanInbox)
	self:RegisterEvent('MAIL_FAILED', function() sentMail = nil end)
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
