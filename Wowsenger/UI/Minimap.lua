-- Wowsenger – minimap-knap (LibDataBroker + LibDBIcon, samme libs som GuildCrafters og Grudge).
-- Venstreklik åbner/lukker vinduet (brugerens valg 2026-11-21). Tooltip: ulæste pr. samtale.
local _, ns = ...

local Data = ns.Data
local UI = ns.UI

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local LDB = LibStub("LibDataBroker-1.1", true)

local Minimap = {}
ns.Minimap = Minimap

function Minimap.Tooltip(tooltip)
	tooltip:AddLine("Wowsenger")
	local any = false
	for conv, n in pairs(ns.DB.unread) do
		if n > 0 then
			any = true
			tooltip:AddDoubleLine(UI.ConvTitle(conv), ("%d new"):format(n), 1, 1, 1, 1, 0.3, 0.3)
		end
	end
	if not any then tooltip:AddLine("No new messages", 0.6, 0.6, 0.6) end
	tooltip:AddLine(" ")
	tooltip:AddLine("|cffffd100Click|r to open Wowsenger", 0.8, 0.8, 0.8)
end

function Minimap.Setup()
	if not (LDB and LDBIcon) then return end
	local launcher = LDB:NewDataObject("Wowsenger", {
		type = "launcher",
		icon = ICON,
		OnClick = function() ns.Window:Toggle() end,
		OnTooltipShow = Minimap.Tooltip,
	})
	LDBIcon:Register("Wowsenger", launcher, ns.db.minimap)
end

function Minimap.Toggle()
	local settings = ns.db.minimap
	settings.hide = not settings.hide
	if not LDBIcon then return end
	if settings.hide then
		LDBIcon:Hide("Wowsenger")
		ns.Print("minimap button hidden. /wowsenger minimap shows it again.")
	else
		LDBIcon:Show("Wowsenger")
	end
end

ns.On("PLAYER_LOGIN", function() Minimap.Setup() end)
