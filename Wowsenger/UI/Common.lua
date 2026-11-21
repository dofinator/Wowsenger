-- Wowsenger – fælles UI-hjælpere: rammer, rullelister, ja/nej-boks, navne og tekster.
-- Ingen Blizzard-popups (StaticPopup/EasyMenu): på Mainline/Forever giver addon-kode i dem "taint"
-- (lært i Grudge 0.1.0). Derfor egne små vinduer her og i Menu.lua.
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data

local UI = {}
ns.UI = UI

UI.GRAY = "|cff808080"
UI.YELLOW = "|cffffd100"

function UI.Backdrop(frame, dialog)
	if not frame.SetBackdrop then return end
	if dialog then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	else
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	end
end

function UI.Button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, 22)
	b:SetText(text)
	return b
end

function UI.EditBox(parent, width)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width, 20)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return e
end

function UI.Text(parent, font, layer)
	return parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlightSmall")
end

-- Navn til visning: "You" for egne karakterer, kort navn på egen realm, klassefarvet.
UI.BNET = "|cff82c5ff" -- Blizzards farve for Battle.net-whispers

function UI.Name(name)
	if Data:IsMine(name) then return "You" end
	if Compat.IsBNetKey(name) then return UI.BNET .. Compat.ShortName(name) .. "|r" end
	return Compat.ColorName(Compat.ShortName(name), Data:Class(name))
end

function UI.Clock(t)
	return date("%H:%M", t)
end

function UI.Day(t)
	return date("%a %d %b", t)
end

function UI.Ago(t)
	if not t or t == 0 then return "never" end
	local s = Compat.Now() - t
	if s < 120 then return "just now" end
	if s < 7200 then return ("%d min ago"):format(math.floor(s / 60)) end
	if s < 172800 then return ("%d hours ago"):format(math.floor(s / 3600)) end
	return ("%d days ago"):format(math.floor(s / 86400))
end

-- Tekst fra andre: links (item, spell, player) beholdes, teksturer og andre koder fjernes.
function UI.Clean(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
	text = text:gsub("[\r\n]+", " ")
	return text
end

-- Samtalens titel: gruppenavn eller personens navn.
function UI.ConvTitle(conv)
	local kind, key = conv:match("^(%a):(.+)$")
	if kind == "g" then
		local g = ns.Groups:Get(key)
		return g and g.name or "?"
	elseif kind == "w" then
		return UI.Name(key)
	end
	return "?"
end

------------------------------------------------------------------------
-- Rulleliste med faste rækker (FauxScrollFrame). make(row, i) bygger en række, render(row, item) fylder den.
------------------------------------------------------------------------
local scrollCount = 0
function UI.ScrollList(parent, rows, rowHeight, make, render)
	scrollCount = scrollCount + 1
	local list = { rows = {}, items = {} }
	local scroll = CreateFrame("ScrollFrame", "WowsengerScroll" .. scrollCount, parent, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 0)
	list.scroll = scroll
	for i = 1, rows do
		local row = CreateFrame("Button", nil, parent)
		row:SetHeight(rowHeight)
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * rowHeight)
		row:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
		make(row, i)
		list.rows[i] = row
	end
	function list:Update()
		local offset = FauxScrollFrame_GetOffset(scroll) or 0
		for i, row in ipairs(self.rows) do
			local item = self.items[offset + i]
			row.item = item
			if item then
				render(row, item)
				row:Show()
			else
				row:Hide()
			end
		end
		FauxScrollFrame_Update(scroll, #self.items, #self.rows, rowHeight)
	end
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function() list:Update() end)
	end)
	function list:SetItems(items)
		self.items = items
		self:Update()
	end
	return list
end

------------------------------------------------------------------------
-- Ja/nej-boks
------------------------------------------------------------------------
local confirm
function UI.Confirm(text, yesText, onYes)
	if not confirm then
		confirm = CreateFrame("Frame", "WowsengerConfirm", UIParent, "BackdropTemplate")
		confirm:SetSize(320, 96)
		confirm:SetPoint("TOP", UIParent, "TOP", 0, -160)
		confirm:SetFrameStrata("DIALOG")
		confirm:SetClampedToScreen(true)
		confirm:EnableMouse(true)
		UI.Backdrop(confirm, true)
		confirm.text = UI.Text(confirm, "GameFontHighlight")
		confirm.text:SetPoint("TOP", 0, -22)
		confirm.text:SetWidth(280)
		confirm.yes = UI.Button(confirm, YES or "Yes", 110)
		confirm.yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -4, 16)
		confirm.no = UI.Button(confirm, CANCEL or "Cancel", 110)
		confirm.no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 4, 16)
		confirm.no:SetScript("OnClick", function() confirm:Hide() end)
		if UISpecialFrames then table.insert(UISpecialFrames, "WowsengerConfirm") end
	end
	confirm.text:SetText(text)
	confirm.yes:SetText(yesText or YES or "Yes")
	confirm.yes:SetScript("OnClick", function()
		confirm:Hide()
		onYes()
	end)
	confirm:Show()
end

function UI.ConfirmShown()
	return confirm ~= nil and confirm:IsShown(), confirm and confirm.text:GetText()
end
