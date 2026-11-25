-- Wowsenger – hovedvinduet (brugerens valg 2026-11-21: liste til venstre).
--
--   +- Wowsenger ----------------------------------------[_][X]+
--   | Groups        | Raid group   4 members, 2 online      |
--   |  Raid     (3) | -- While you were offline --          |
--   |  Alts         | 20:01 Anna: Tuesday 20:00?            |
--   | + New group   | 20:03 Bob: works for me               |
--   | People        | 20:05 You: great                      |
--   |  Anna       x | (x = slet, vises når musen er over)   |
--   | Deleted Bob. Undo                                     |
--   |  Bob          | [ Message Raid group...            ] //|
--   +------------------------------------------------------+
-- Højreklik på en samtale = menu, hover = tooltip (medlemmer, online).
-- Brugerens valg 2026-11-25 (fra mockups): x på person-rækken sletter med det samme + "Undo" i 10 s,
-- "_" folder vinduet sammen til en titellinje med antal nye, vinduet kan trækkes større i hjørnet,
-- og markøren står i skrivefeltet, når man vælger en samtale.
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data
local Groups = ns.Groups
local Whispers = ns.Whispers
local UI = ns.UI

local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 620, 410
local MIN_W, MIN_H, MAX_W, MAX_H = 470, 260, 1400, 1000
local LEFT_W = 160
local ROW_H = 18
local BAR_H = 28
local UNDO_FOR = 10
local frame, body, list, smf, input, header, sub, empty, bar
local selected -- "g:<gid>" / "w:<navn>"
local lines = {} -- de viste linjer (til test)
local undo, undoToken -- slettede samtaler, der kan fortrydes ({ removed, ... })

local function RowsFor(height)
	return math.floor((height - 42) / ROW_H)
end

local function Clamp(v, lo, hi)
	v = tonumber(v) or lo
	if v < lo then return lo end
	if v > hi then return hi end
	return math.floor(v + 0.5)
end

------------------------------------------------------------------------
-- Listen til venstre
------------------------------------------------------------------------
local function Items()
	local items = { { kind = "header", text = "Groups" } }
	for _, gid in ipairs(Groups:List()) do
		items[#items + 1] = { kind = "conv", conv = "g:" .. gid }
	end
	items[#items + 1] = { kind = "new" }
	local people = Whispers:List()
	if #people > 0 then
		items[#items + 1] = { kind = "header", text = "People" }
		for _, name in ipairs(people) do
			items[#items + 1] = { kind = "conv", conv = "w:" .. name }
		end
	end
	if undo then items[#items + 1] = { kind = "undo" } end
	return items
end

local function Badge(conv)
	local n = Data:Unread(conv)
	if n > 0 then return ("|cffff4040%d|r"):format(n) end
	return ""
end

local function CanDelete(item)
	return item ~= nil and item.kind == "conv" and item.conv:find("^w:") ~= nil
end

-- x'et vises kun på den person-række, musen er over (og så skjules ulæst-tallet bag det).
local function SetHover(row, on)
	local show = on and CanDelete(row.item) or false
	row.del:SetShown(show)
	row.badge:SetShown(not show)
end

local function UndoText()
	if #undo == 1 then
		return ("Deleted %s."):format(Compat.ShortName(undo[1].name))
	end
	return ("Deleted %d conversations."):format(#undo)
end

local function RenderRow(row, item)
	row:UnlockHighlight()
	row.badge:SetText("")
	if item.kind == "header" then
		row.label:SetFontObject("GameFontNormalSmall")
		row.label:SetText(item.text)
		row.label:SetPoint("LEFT", 4, 0)
	elseif item.kind == "new" then
		row.label:SetFontObject("GameFontHighlightSmall")
		row.label:SetText(UI.GRAY .. "+ New group|r")
		row.label:SetPoint("LEFT", 12, 0)
	elseif item.kind == "undo" then
		row.label:SetFontObject("GameFontHighlightSmall")
		row.label:SetText(UI.GRAY .. UndoText() .. "|r  " .. UI.YELLOW .. "Undo|r")
		row.label:SetPoint("LEFT", 4, 0)
	else
		row.label:SetFontObject("GameFontHighlightSmall")
		local g = item.conv:match("^g:(.+)$") and Groups:Get(item.conv:sub(3))
		local title = UI.ConvTitle(item.conv)
		if g and g.demo then title = title .. UI.GRAY .. " (demo)|r" end
		row.label:SetText(title)
		row.label:SetPoint("LEFT", 12, 0)
		row.badge:SetText(Badge(item.conv))
		if item.conv == selected then row:LockHighlight() end
	end
	-- Rykker en ny række op under musen efter en sletning, får den x'et med det samme.
	SetHover(row, row:IsMouseOver())
end

local function GroupTooltip(gid)
	local g = Groups:Get(gid)
	if not g then return end
	GameTooltip:AddLine(g.name)
	for _, name in ipairs(Groups:Members(g)) do
		local state
		if Data:IsMine(name) then
			state = name == ns.me and "you" or "your character"
		elseif ns.Comm:IsOnline(name) then
			state = "|cff40ff40online|r"
		else
			state = UI.GRAY .. "offline|r"
		end
		GameTooltip:AddDoubleLine(Compat.ColorName(name, Data:Class(name)), state, 1, 1, 1, 1, 1, 1)
	end
	if g.demo then GameTooltip:AddLine("Demo group: nothing is sent.", 0.6, 0.6, 0.6) end
end

local function RowTooltip(row)
	local item = row.item
	if not item or item.kind ~= "conv" then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local kind, key = item.conv:match("^(%a):(.+)$")
	if kind == "g" then
		GroupTooltip(key)
	elseif Compat.IsBNetKey(key) then
		GameTooltip:AddLine(UI.BNET .. key .. "|r")
		GameTooltip:AddLine("Battle.net friend", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Last message " .. UI.Ago(Data:LastWhisperTime(key)), 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine(Compat.ColorName(key, Data:Class(key)))
		local peer = ns.DB.peers[key]
		if peer and peer.addon then GameTooltip:AddLine("Has Wowsenger", 0.6, 0.6, 0.6) end
		GameTooltip:AddLine("Last message " .. UI.Ago(Data:LastWhisperTime(key)), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffd100Right-click|r for options", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

-- Sletter en 1:1-samtale med det samme; "Undo" står nederst i listen i 10 s. Flere sletninger lige
-- efter hinanden samles i én Undo, der bringer dem alle tilbage.
function Window:Delete(conv)
	local key = conv and conv:match("^w:(.+)$")
	if not key then return false end
	local removed = Whispers:Delete(key)
	if not removed then return false end
	removed.wasSelected = selected == conv
	if selected == conv then selected = nil end
	undo = undo or {}
	table.insert(undo, removed)
	local token = {}
	undoToken = token
	C_Timer.After(UNDO_FOR, function()
		if undoToken ~= token then return end
		undo, undoToken = nil, nil
		Window:Refresh()
	end)
	ns.Debug("conversation deleted (%d to undo)", #undo)
	self:Refresh()
	ns.Changed("unread")
	return true
end

function Window:Undo()
	if not undo then return false end
	local restored = undo
	undo, undoToken = nil, nil
	for _, removed in ipairs(restored) do
		Whispers:Restore(removed)
		if removed.wasSelected then selected = "w:" .. removed.name end
	end
	self:Refresh()
	ns.Changed("unread")
	return true
end

function Window:CanUndo() return undo ~= nil end

function Window:MenuFor(conv)
	local kind, key = conv:match("^(%a):(.+)$")
	if kind == "g" then
		local g = Groups:Get(key)
		if not g then return nil end
		if g.demo then
			return { { text = "Remove demo group", fn = function() ns.Debug_RemoveDemo() end } }
		end
		return {
			{ text = "Edit group...", fn = function() ns.NewGroup:Open(key) end },
			{ text = "Leave group", fn = function()
				UI.Confirm(("Leave %s? You keep the messages you already have."):format(g.name), "Leave",
					function() Groups:Leave(key) end)
			end },
		}
	end
	local items = {}
	-- Battle.net-venner inviteres fra vennelisten (deres karakter kendes ikke her).
	if not Compat.IsBNetKey(key) then
		items[#items + 1] = { text = "Invite to party", fn = function() Compat.Invite(key) end }
	end
	-- Ingen bekræftelse: Undo i listen fortryder (samme som x'et på rækken).
	items[#items + 1] = { text = "Delete conversation", fn = function() Window:Delete(conv) end }
	return items
end

local function OnRowClick(row, button)
	local item = row.item
	if not item then return end
	if item.kind == "new" then
		ns.NewGroup:Open()
	elseif item.kind == "undo" then
		Window:Undo()
	elseif item.kind == "conv" then
		if button == "RightButton" then
			local items = Window:MenuFor(item.conv)
			if items then ns.Menu:Show(UI.ConvTitle(item.conv), items) end
		else
			Window:Select(item.conv)
		end
	end
end

local function MakeRow(row)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.label = UI.Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 12, 0)
	row.label:SetPoint("RIGHT", -24, 0)
	row.label:SetJustifyH("LEFT")
	if row.label.SetWordWrap then row.label:SetWordWrap(false) end
	row.badge = UI.Text(row, "GameFontHighlightSmall")
	row.badge:SetPoint("RIGHT", -2, 0)
	-- Blizzards grå "Pass"-kryds fra loot-rammen: findes i alle klienter.
	row.del = CreateFrame("Button", nil, row)
	row.del:SetSize(16, 16)
	row.del:SetPoint("RIGHT", 0, 0)
	row.del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	row.del:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
	row.del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
	row.del:SetScript("OnClick", function()
		if CanDelete(row.item) then Window:Delete(row.item.conv) end
	end)
	row.del:SetScript("OnEnter", function(self)
		SetHover(row, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Delete conversation")
		GameTooltip:AddLine("Undo stays below the list for a few seconds", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	row.del:SetScript("OnLeave", function()
		GameTooltip:Hide()
		SetHover(row, row:IsMouseOver())
	end)
	row.del:Hide()
	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", function(self)
		SetHover(self, true)
		RowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		-- Musen kan være gået ind på x'et (et barn af rækken): så skal det blive stående.
		SetHover(self, self.del:IsMouseOver())
	end)
end

------------------------------------------------------------------------
-- Samtalen til højre
------------------------------------------------------------------------
local function AddLine(text)
	lines[#lines + 1] = text
	smf:AddMessage(text)
end

local function RenderGroup(gid)
	local lastDay
	for _, m in ipairs(Groups:Messages(gid)) do
		local day = UI.Day(m.t)
		if day ~= lastDay then
			AddLine(UI.GRAY .. "-- " .. day .. " --|r")
			lastDay = day
		end
		if Groups:IsCatchupStart(gid, m) then AddLine(UI.YELLOW .. "-- While you were offline --|r") end
		AddLine(("%s%s|r %s: %s"):format(UI.GRAY, UI.Clock(m.t), UI.Name(m.a), UI.Clean(m.x)))
	end
end

local function RenderWhispers(name)
	local lastDay
	for _, e in ipairs(Whispers:Messages(name)) do
		local day = UI.Day(e.t)
		if day ~= lastDay then
			AddLine(UI.GRAY .. "-- " .. day .. " --|r")
			lastDay = day
		end
		local who = e.out and "You" or UI.Name(name)
		local text = e.hidden and (UI.GRAY .. "message hidden during an encounter, see your normal chat|r")
			or UI.Clean(e.x)
		AddLine(("%s%s|r %s: %s"):format(UI.GRAY, UI.Clock(e.t), who, text))
	end
end

local function RenderConversation()
	smf:Clear()
	lines = {}
	if not selected then
		header:SetText("")
		sub:SetText("")
		input:Hide()
		empty:Show()
		return
	end
	empty:Hide()
	input:Show()
	local kind, key = selected:match("^(%a):(.+)$")
	header:SetText(UI.ConvTitle(selected))
	if kind == "g" then
		local g = Groups:Get(key)
		local online = 0
		for _, name in ipairs(Groups:Others(g)) do
			if ns.Comm:IsOnline(name) then online = online + 1 end
		end
		sub:SetText(("%d members, %d online"):format(#Groups:Members(g), online))
		RenderGroup(key)
		input.hint = "Message " .. g.name .. "..."
	else
		sub:SetText(Compat.IsBNetKey(key) and "Battle.net whisper" or "Whisper")
		RenderWhispers(key)
		input.hint = "Whisper " .. Compat.ShortName(key) .. "..."
	end
	input.placeholder:SetText((input:GetText() or "") == "" and input.hint or "")
	smf:ScrollToBottom()
end

function Window:SendInput()
	local text = strtrim(input:GetText() or "")
	if text == "" or not selected then return end
	local kind, key = selected:match("^(%a):(.+)$")
	if kind == "g" then
		Groups:Post(key, text)
	else
		if not Whispers:Send(key, text) then
			if Compat.IsBNetKey(key) then
				ns.Print(("could not find %s on your Battle.net friends list."):format(key))
			else
				ns.Print("could not send the whisper.")
			end
		end
	end
	input:SetText("")
end

------------------------------------------------------------------------
-- Plads og størrelse
------------------------------------------------------------------------
-- Gemmer øverste venstre hjørne (så titellinjen og vinduet står samme sted), ellers ankerpunktet.
local function SavePosition(f)
	local left, top = f:GetLeft(), f:GetTop()
	if left and top then
		ns.db.window = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = top }
	else
		local point, _, relPoint, x, y = f:GetPoint(1)
		ns.db.window = { point = point, relPoint = relPoint, x = x, y = y }
	end
end

local function Place(f)
	f:ClearAllPoints()
	local pos = ns.db.window
	if pos and pos.point then
		f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		f:SetPoint("CENTER")
	end
end

local function Layout(height)
	if not list then return end
	list:SetVisibleRows(RowsFor(height))
	list:Update()
end

function Window:SaveSize()
	if not frame then return end
	ns.db.size = { w = Clamp(frame:GetWidth(), MIN_W, MAX_W), h = Clamp(frame:GetHeight(), MIN_H, MAX_H) }
	SavePosition(frame)
end

------------------------------------------------------------------------
-- Foldet sammen: kun en titellinje med antal nye (brugerens valg 2026-11-25)
------------------------------------------------------------------------
local function UpdateBar()
	if not bar then return end
	local n = Data:TotalUnread()
	local text = "Wowsenger"
	if n > 0 then text = text .. ("  |cffff4040(%d new)|r"):format(n) end
	bar.title:SetText(text)
	bar:SetWidth(frame and frame:GetWidth() or WIDTH)
end

local function CreateBar()
	bar = CreateFrame("Button", "WowsengerBar", UIParent, "BackdropTemplate")
	bar:SetHeight(BAR_H)
	bar:SetFrameStrata("HIGH")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:RegisterForClicks("LeftButtonUp")
	UI.Backdrop(bar)
	bar.title = UI.Text(bar, "GameFontNormal")
	bar.title:SetPoint("LEFT", 12, 0)
	bar:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:StartMoving()
	end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
		-- Spillet sender et klik, når man slipper efter et træk; det skal ikke folde vinduet ud.
		C_Timer.After(0, function() self.dragging = false end)
	end)
	bar:SetScript("OnClick", function(self)
		if self.dragging then return end
		Window:Unfold()
	end)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		ns.Minimap.Tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

	bar.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	bar.close:SetSize(24, 24)
	bar.close:SetPoint("RIGHT", -3, 0)
	bar.close:SetScript("OnClick", function() Window:Close() end)
	bar.expand = CreateFrame("Button", nil, bar)
	bar.expand:SetSize(24, 24)
	local art = Compat.ButtonArt(bar.expand, "RedButton-Expand", "Interface\\Buttons\\UI-Panel-BiggerButton")
	bar.expand:SetPoint("RIGHT", bar.close, "LEFT", art == "file" and 4 or 0, 0)
	bar.expand:SetScript("OnClick", function() Window:Unfold() end)
	bar:Hide()
end

------------------------------------------------------------------------
-- Opbygning
------------------------------------------------------------------------
local function Create()
	local template = "BasicFrameTemplateWithInset"
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo and not C_XMLUtil.GetTemplateInfo(template) then
		template = "BasicFrameTemplate"
	end
	frame = CreateFrame("Frame", "WowsengerFrame", UIParent, template)
	local size = ns.db.size or {}
	frame:SetSize(Clamp(size.w or WIDTH, MIN_W, MAX_W), Clamp(size.h or HEIGHT, MIN_H, MAX_H))
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	Compat.SetResizeBounds(frame, MIN_W, MIN_H, MAX_W, MAX_H)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)
	Place(frame)
	local title = frame.TitleText
	if not title then
		title = UI.Text(frame, "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
	end
	title:SetText("Wowsenger")
	if UISpecialFrames then table.insert(UISpecialFrames, "WowsengerFrame") end

	-- "_" ved siden af X: fold sammen til titellinjen.
	local fold = CreateFrame("Button", nil, frame)
	fold:SetSize(24, 24)
	local art = Compat.ButtonArt(fold, "RedButton-Condense", "Interface\\Buttons\\UI-Panel-SmallerButton")
	if frame.CloseButton then
		fold:SetPoint("RIGHT", frame.CloseButton, "LEFT", art == "file" and 4 or 0, 0)
	else
		fold:SetPoint("TOPRIGHT", -26, 0)
	end
	fold:SetScript("OnClick", function() Window:Fold() end)
	fold:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Minimize")
		GameTooltip:Show()
	end)
	fold:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.fold = fold

	body = CreateFrame("Frame", nil, frame)
	body:SetAllPoints(frame)

	-- Venstre: samtaler
	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT", 10, -30)
	left:SetPoint("BOTTOMLEFT", 10, 10)
	left:SetWidth(LEFT_W)
	list = UI.ScrollList(left, RowsFor(frame:GetHeight()), ROW_H, MakeRow, RenderRow)

	local divider = body:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.15)
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
	divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 4, 0)

	-- Højre: samtalen
	local rightX = 10 + LEFT_W + 12
	header = UI.Text(body, "GameFontNormal")
	header:SetPoint("TOPLEFT", rightX, -34)
	sub = UI.Text(body, "GameFontDisableSmall")
	sub:SetPoint("LEFT", header, "RIGHT", 8, 0)

	local headerHit = CreateFrame("Frame", nil, body)
	headerHit:SetPoint("TOPLEFT", rightX, -30)
	headerHit:SetPoint("TOPRIGHT", -14, -30)
	headerHit:SetHeight(18)
	headerHit:EnableMouse(true)
	headerHit:SetScript("OnEnter", function(self)
		if not selected or not selected:find("^g:") then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GroupTooltip(selected:sub(3))
		GameTooltip:Show()
	end)
	headerHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

	smf = CreateFrame("ScrollingMessageFrame", nil, body)
	smf:SetPoint("TOPLEFT", rightX, -56)
	smf:SetPoint("BOTTOMRIGHT", -14, 40)
	smf:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
	smf:SetJustifyH("LEFT")
	smf:SetFading(false)
	smf:SetMaxLines(Data.MAX_MESSAGES + 60)
	smf:SetHyperlinksEnabled(true)
	smf:EnableMouseWheel(true)
	smf:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown() then
			if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
		elseif delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
		Compat.ItemRef(link, text, button, DEFAULT_CHAT_FRAME)
	end)

	empty = UI.Text(body, "GameFontDisable")
	empty:SetPoint("CENTER", body, "CENTER", (LEFT_W + 12) / 2, 0)
	empty:SetText("Pick a conversation, or create a group.")

	input = UI.EditBox(body, WIDTH - rightX - 20)
	input:SetPoint("BOTTOMLEFT", rightX + 6, 14)
	input:SetPoint("BOTTOMRIGHT", -26, 14)
	input:SetMaxLetters(255)
	input.placeholder = UI.Text(input, "GameFontDisableSmall")
	input.placeholder:SetPoint("LEFT", 2, 0)
	input:SetScript("OnEnterPressed", function() Window:SendInput() end)
	input:SetScript("OnTextChanged", function(self)
		self.placeholder:SetText((self:GetText() or "") == "" and (self.hint or "") or "")
	end)
	Compat.HookInsertLink(function(link)
		if input:IsVisible() and input:HasFocus() then input:Insert(link) end
	end)

	-- Træk i hjørnet for at gøre vinduet større (samme greb som Blizzards chatvinduer).
	local grip = CreateFrame("Button", nil, body)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		Window:SaveSize()
	end)
	frame.grip = grip

	frame:SetScript("OnSizeChanged", function(_, _, height) Layout(height) end)
	frame:SetScript("OnShow", function()
		if selected then Data:ClearUnread(selected) end
		Window:Refresh()
	end)
	frame:Hide()
	CreateBar()
end

function Window:Refresh()
	UpdateBar()
	if not frame or not frame:IsShown() then return end
	if selected then
		local kind, key = selected:match("^(%a):(.+)$")
		local g = kind == "g" and Groups:Get(key)
		if (kind == "g" and (not g or g.left)) or (kind == "w" and not ns.DB.whispers[key]) then selected = nil end
	end
	list:SetItems(Items())
	RenderConversation()
	ns.Changed("unread")
end

local pending = false
function Window:RequestRefresh()
	if not frame or not frame:IsShown() or pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		Window:Refresh()
	end)
end

-- Markøren i skrivefeltet, når man vælger en samtale (Esc slipper den igen).
local function FocusInput()
	if input and input:IsShown() then input:SetFocus() end
end

function Window:Select(conv)
	selected = conv
	ns.db.lastConv = conv
	Data:ClearUnread(conv)
	self:Refresh()
	FocusInput()
end

function Window:Open(conv)
	if not frame then Create() end
	-- Foldet sammen (også når toasten åbner): vinduet folder ud dér, hvor titellinjen står.
	if bar:IsShown() then
		SavePosition(bar)
		bar:Hide()
		ns.db.folded = nil
		Place(frame)
	end
	if conv then
		selected = conv
		ns.db.lastConv = conv
		Data:ClearUnread(conv)
	end
	frame:Show()
	self:Refresh()
	if conv then FocusInput() end
end

function Window:Fold()
	if not frame then Create() end
	if frame:IsShown() then SavePosition(frame) end
	if input:HasFocus() then input:ClearFocus() end
	frame:Hide()
	Place(bar)
	ns.db.folded = true
	UpdateBar()
	bar:Show()
end

function Window:Unfold()
	if not selected and ns.db.lastConv then selected = ns.db.lastConv end
	self:Open()
end

function Window:Close()
	if bar then bar:Hide() end
	if frame then frame:Hide() end
	ns.db.folded = nil
end

function Window:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		self:Unfold() -- åbner, også når den er foldet sammen
	end
end

function Window:IsShown() return frame ~= nil and frame:IsShown() end
function Window:IsFolded() return bar ~= nil and bar:IsShown() end
function Window:BarText() return bar and bar.title:GetText() end
function Window:Frame() return frame end
function Window:Hide() if frame then frame:Hide() end end
function Window:Selected() return selected end
function Window:Lines() return lines end
function Window:Items() return frame and frame:IsShown() and list.items or {} end
function Window:Rows() return list and list.rows or {}, list and list.visible or 0 end
function Window:InputFocused() return input ~= nil and input:HasFocus() end
function Window:Header() return header and header:GetText(), sub and sub:GetText() end
function Window:Type(text)
	input:SetText(text)
	self:SendInput()
end

-- Var vinduet foldet sammen ved logout/reload, står titellinjen der igen.
ns.On("PLAYER_LOGIN", function()
	if ns.db.folded then Window:Fold() end
end)

------------------------------------------------------------------------
-- Nye beskeder: ulæst, toast, opdatering
------------------------------------------------------------------------
ns.Listen(function(what, key, entry)
	if what == "incoming" then
		local conv = key
		local visible = Window:IsShown() and selected == conv
		if not visible then Data:AddUnread(conv) end
		if not Window:IsShown() then
			local isGroup = conv:find("^g:") ~= nil
			local sender = isGroup and entry.a or conv:sub(3)
			local text = entry.x
			if entry.hidden then text = "(hidden during an encounter)" end
			ns.Toast:Notify(conv, sender, text, isGroup)
		end
		ns.Changed("unread")
	elseif what == "removed" then
		local g = Groups:Get(key)
		ns.Print(("you are no longer in %s."):format(g and g.name or "a group"))
	elseif what == "added" then
		local g = Groups:Get(key)
		if g then ns.Print(("you were added to the group %s. Open it with the minimap button."):format(g.name)) end
	end
	if what == "unread" then
		UpdateBar()
	else
		Window:RequestRefresh()
	end
end)
