local addonName, addon = ...
LibStub('AceAddon-3.0'):NewAddon(addon, addonName)
_G[addonName] = addon -- expose us

-- GLOBALS: GetCVar, GetQuestResetTime
-- GLOBALS: assert ,format, pairs, string, time, date, tonumber, type

-- ========================================================
--  Functions required by modules
-- ========================================================
local lastMaintenance, nextMaintenance
function addon.GetLastMaintenance()
	if not lastMaintenance then
		local region = string.lower( GetCVar('portal') or '' )
		local maintenanceWeekDay = (region == 'us' and 2) -- tuesday
			or (region == 'eu' and 3) -- wednesday
			or (region == 'kr' and 4) -- ?
			or (region == 'tw' and 4) -- ?
			or (region == 'cn' and 4) -- ?
			or 2

		-- this gives us the time a reset happens, though GetQuestResetTime might not be available at launch
		local dailyReset = time() + GetQuestResetTime()
		if dailyReset == 0 then return end

		local dailyResetWeekday = tonumber(date('%w', dailyReset))
		        lastMaintenance = dailyReset - ((dailyResetWeekday - maintenanceWeekDay)%7) * 24*60*60
		if lastMaintenance == dailyReset then
			lastMaintenance = lastMaintenance - 7*24*60*60
		end
	end
	return lastMaintenance
end
function addon.GetNextMaintenance()
	if nextMaintenance then
		return nextMaintenance
	else
		local lastMaintenance = addon.GetLastMaintenance()
		if lastMaintenance then
			nextMaintenance = lastMaintenance + 7*24*60*60
		end
	end
	return nextMaintenance
end

function addon.GetLinkID(link)
	if not link or type(link) ~= "string" then return end
	local linkType, id = link:match("\124H([^:]+):([^:\124]+)")
	if not linkType then
		linkType, id = link:match("([^:\124]+):([^:\124]+)")
	end
	return tonumber(id), linkType
end

function addon.IsBaseLink(itemLink)
	local itemID, linkType = addon.GetLinkID(itemLink)
	if not itemID or linkType ~= 'item' then return end

	-- @see http://wowpedia.org/ItemString
	-- item:itemId:enchantId:jewelId1:jewelId2:jewelId3:jewelId4:suffixId:uniqueId:linkLevel:reforgeId:upgradeId
	local _, simpleLink = GetItemInfo(itemID)
	local cleanedLink = itemLink:gsub('item:([^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:)[^:]+(.+)$', 'item:%10%2')
	return cleanedLink == simpleLink
end
