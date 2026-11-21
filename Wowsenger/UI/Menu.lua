-- Wowsenger – egen lille højreklik-menu (ingen EasyMenu/UIDropDownMenu: taint på Mainline/Forever).
local _, ns = ...

local UI = ns.UI

local Menu = {}
ns.Menu = Menu

local MAX = 8
local frame, buttons

local function Create()
	frame = CreateFrame("Frame", "WowsengerMenu", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	UI.Backdrop(frame)
	frame.title = UI.Text(frame, "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", 10, -8)
	buttons = {}
	for i = 1, MAX do
		local b = CreateFrame("Button", nil, frame)
		b:SetHeight(16)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8 - i * 16)
		b:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.text = UI.Text(b, "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 2, 0)
		b:SetScript("OnClick", function(self)
			frame:Hide()
			if self.fn then self.fn() end
		end)
		buttons[i] = b
	end
	-- Lukker, når musen har været væk fra menuen et øjeblik.
	frame:SetScript("OnUpdate", function(self, elapsed)
		if self:IsMouseOver() then
			self.away = 0
		else
			self.away = (self.away or 0) + elapsed
			if self.away > 1.5 then self:Hide() end
		end
	end)
	if UISpecialFrames then table.insert(UISpecialFrames, "WowsengerMenu") end
end

-- items = { { text, fn }, ... }
function Menu:Show(title, items)
	if not frame then Create() end
	frame.title:SetText(title or "")
	frame.items = items
	for i, b in ipairs(buttons) do
		local item = items[i]
		if item then
			b.text:SetText(item.text)
			b.fn = item.fn
			b:Show()
		else
			b.fn = nil
			b:Hide()
		end
	end
	frame:SetSize(170, 16 + (#items + 1) * 16)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 10, y / scale + 10)
	frame.away = 0
	frame:Show()
end

function Menu:Items()
	if not frame or not frame:IsShown() then return nil end
	return frame.items
end

function Menu:Hide()
	if frame then frame:Hide() end
end
