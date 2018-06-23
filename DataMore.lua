local addonName, addon = ...
LibStub('AceAddon-3.0'):NewAddon(addon, addonName, 'AceEvent-3.0')
_G[addonName] = addon -- expose us

-- GLOBALS: _G, Altoholic
-- GLOBALS: GetCVar, GetQuestResetTime, IsAddOnLoaded, GetItemInfo
-- GLOBALS: hooksecurefunc, assert, format, pairs, ipairs, string, time, date, tonumber, type

local function EnableGrids()
	if not IsAddOnLoaded('Altoholic_Grids') then return end
	hooksecurefunc(Altoholic.Tabs.Grids, 'OnShow', function()
		local children = { _G.AltoholicTabGrids:GetChildren() }
		for i, child in ipairs(children) do
			if child:GetObjectType() == 'Button' then
				child:Enable()
				child.Icon:SetDesaturated(false)
			end
		end
	end)
	addon:UnregisterEvent('ADDON_LOADED')
end
addon:RegisterEvent('ADDON_LOADED', EnableGrids)
EnableGrids()

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

	-- @see http://wowpedia.org/ItemString item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:level:specialization:upgrade:difficulty:numBonuses:bonus1:bonus2:...
	local _, simpleLink = GetItemInfo(itemID)
	local cleanedLink = itemLink:gsub('item:([^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:)[^:]*(.+)$', 'item:%10%2')
	return cleanedLink == simpleLink
end
