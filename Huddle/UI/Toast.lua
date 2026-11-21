-- Huddle – lille toast ved ny besked, når vinduet er lukket (brugerens valg 2026-11-21).
--
--   +- Raid group ------------------+
--   | Anna: Tuesday 20:00?          |
--   | Click to open                 |
--   +-------------------------------+
-- 5 sek., blød lyd (kun gruppebeskeder; Blizzard spiller selv en lyd ved whispers).
-- I kamp samles beskederne og vises bagefter som én toast.
local _, ns = ...

local Compat = ns.Compat
local UI = ns.UI

local Toast = {}
ns.Toast = Toast

local SHOW_FOR = 5
local frame
local current -- { conv, count }
local pending = {} -- i kamp: { conv, text, sender }

-- Standardplads: øverst i midten, hvor Blizzard selv viser beskeder (brugerens valg 2026-11-21; nederst
-- til højre lå den bag action bars). Kan trækkes; pladsen gemmes i settings.toastPos.
local DEFAULT_POINT = { "TOP", "TOP", 0, -120 }

local function Place()
	frame:ClearAllPoints()
	local pos = ns.db.toastPos
	if pos and pos.point then
		frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
	end
end

local function Create()
	frame = CreateFrame("Button", "HuddleToast", UIParent, "BackdropTemplate")
	frame:SetSize(280, 58)
	-- Over action bars og andre addons' rammer.
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		ns.db.toastPos = { point = point, relPoint = relPoint, x = x, y = y }
		self.hideAt = GetTime() + SHOW_FOR
		-- Spillet sender et klik, når man slipper efter et træk; det skal ikke åbne vinduet.
		C_Timer.After(0, function() self.dragging = false end)
	end)
	Place()
	UI.Backdrop(frame)
	frame.title = UI.Text(frame, "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", 12, -10)
	frame.title:SetPoint("RIGHT", -12, 0)
	frame.title:SetJustifyH("LEFT")
	frame.line = UI.Text(frame, "GameFontHighlightSmall")
	frame.line:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	frame.line:SetPoint("RIGHT", -12, 0)
	frame.line:SetJustifyH("LEFT")
	if frame.line.SetWordWrap then frame.line:SetWordWrap(false) end
	frame.hint = UI.Text(frame, "GameFontDisableSmall")
	frame.hint:SetPoint("TOPLEFT", frame.line, "BOTTOMLEFT", 0, -3)
	frame.hint:SetText("Click to open, drag to move")
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnClick", function(self, button)
		if self.dragging then return end
		self:Hide()
		if button == "LeftButton" and current and current.conv ~= "test" then ns.Window:Open(current.conv) end
	end)
	frame:SetScript("OnUpdate", function(self)
		if self.hideAt and GetTime() >= self.hideAt and not self:IsMouseOver() then self:Hide() end
	end)
	frame:Hide()
end

local function Short(text, n)
	if #text > n then return text:sub(1, n - 3) .. "..." end
	return text
end

local function Show(conv, title, line, sound)
	if not frame then Create() end
	if current and current.conv == conv and frame:IsShown() then
		current.count = current.count + 1
		frame.title:SetText(("%s  %s(%d new)|r"):format(title, UI.GRAY, current.count))
	else
		current = { conv = conv, count = 1 }
		frame.title:SetText(title)
	end
	frame.line:SetText(line)
	frame.hideAt = GetTime() + SHOW_FOR
	frame:Show()
	if sound and ns.db.sound and PlaySound then
		PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081, "Master")
	end
end

-- Kaldes for hver ny besked fra en anden (Window afgør, om vinduet er lukket).
function Toast:Notify(conv, sender, text, isGroup)
	if not ns.db.toast then return end
	if Compat.InCombat() then
		table.insert(pending, conv)
		return
	end
	local line = text and (UI.Name(sender) .. ": " .. Short(UI.Clean(text), 70)) or UI.Name(sender)
	Show(conv, UI.ConvTitle(conv), line, isGroup)
end

-- /huddle toast test: en prøve-toast, der står lidt længere, så den kan trækkes på plads.
function Toast:Test()
	Show("test", "Huddle", "This is where new messages pop up", false)
	frame.hideAt = GetTime() + 15
end

-- /huddle toast reset: tilbage til standardpladsen.
function Toast:ResetPosition()
	ns.db.toastPos = nil
	if frame then Place() end
end

function Toast:Point()
	if not frame then return nil end
	return frame:GetPoint(1)
end

function Toast:IsShown()
	return frame ~= nil and frame:IsShown()
end

function Toast:Texts()
	if not self:IsShown() then return nil end
	return frame.title:GetText(), frame.line:GetText()
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if #pending == 0 or ns.Window:IsShown() then
		pending = {}
		return
	end
	local n, last = #pending, pending[#pending]
	pending = {}
	if n == 1 then
		Show(last, UI.ConvTitle(last), "1 new message", true)
	else
		Show(last, "Huddle", ("%d new messages"):format(n), true)
	end
end)
