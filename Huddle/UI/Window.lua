-- Huddle – hovedvinduet (brugerens valg 2026-11-21: liste til venstre).
--
--   +- Huddle ------------------------------------------[X]+
--   | Groups        | Raid group   4 members, 2 online      |
--   |  Raid     (3) | -- While you were offline --          |
--   |  Alts         | 20:01 Anna: Tuesday 20:00?            |
--   | + New group   | 20:03 Bob: works for me               |
--   | People        | 20:05 You: great                      |
--   |  Anna     (1) |                                       |
--   |  Bob          | [ Message Raid group...            ]  |
--   +------------------------------------------------------+
-- Højreklik på en samtale = menu, hover = tooltip (medlemmer, online).
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data
local Groups = ns.Groups
local Whispers = ns.Whispers
local UI = ns.UI

local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 620, 410
local LEFT_W = 160
local ROW_H = 18
local frame, list, smf, input, header, sub, empty
local selected -- "g:<gid>" / "w:<navn>"
local lines = {} -- de viste linjer (til test)

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
	return items
end

local function Badge(conv)
	local n = Data:Unread(conv)
	if n > 0 then return ("|cffff4040%d|r"):format(n) end
	return ""
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
		if peer and peer.addon then GameTooltip:AddLine("Has Huddle", 0.6, 0.6, 0.6) end
		GameTooltip:AddLine("Last message " .. UI.Ago(Data:LastWhisperTime(key)), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffd100Right-click|r for options", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

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
	items[#items + 1] = { text = "Delete conversation", fn = function()
			UI.Confirm(("Delete your history with %s?"):format(Compat.ShortName(key)), DELETE or "Delete", function()
				ns.DB.whispers[key] = nil
				Data:ClearUnread(conv)
				if selected == conv then selected = nil end
				Window:Refresh()
			end)
		end }
	return items
end

local function OnRowClick(row, button)
	local item = row.item
	if not item then return end
	if item.kind == "new" then
		ns.NewGroup:Open()
	elseif item.kind == "conv" then
		if button == "RightButton" then
			local items = Window:MenuFor(item.conv)
			if items then ns.Menu:Show(UI.ConvTitle(item.conv), items) end
		else
			Window:Select(item.conv)
		end
	end
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
-- Opbygning
------------------------------------------------------------------------
local function Create()
	local template = "BasicFrameTemplateWithInset"
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo and not C_XMLUtil.GetTemplateInfo(template) then
		template = "BasicFrameTemplate"
	end
	frame = CreateFrame("Frame", "HuddleFrame", UIParent, template)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		ns.db.window = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	local pos = ns.db.window
	if pos and pos.point then
		frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER")
	end
	local title = frame.TitleText
	if not title then
		title = UI.Text(frame, "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
	end
	title:SetText("Huddle")
	if UISpecialFrames then table.insert(UISpecialFrames, "HuddleFrame") end

	-- Venstre: samtaler
	local left = CreateFrame("Frame", nil, frame)
	left:SetPoint("TOPLEFT", 10, -30)
	left:SetPoint("BOTTOMLEFT", 10, 10)
	left:SetWidth(LEFT_W)
	local rows = math.floor((HEIGHT - 42) / ROW_H)
	list = UI.ScrollList(left, rows, ROW_H, function(row)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.label = UI.Text(row, "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", 12, 0)
		row.label:SetPoint("RIGHT", -24, 0)
		row.label:SetJustifyH("LEFT")
		if row.label.SetWordWrap then row.label:SetWordWrap(false) end
		row.badge = UI.Text(row, "GameFontHighlightSmall")
		row.badge:SetPoint("RIGHT", -2, 0)
		row:SetScript("OnClick", OnRowClick)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end, RenderRow)

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.15)
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
	divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 4, 0)

	-- Højre: samtalen
	local rightX = 10 + LEFT_W + 12
	header = UI.Text(frame, "GameFontNormal")
	header:SetPoint("TOPLEFT", rightX, -34)
	sub = UI.Text(frame, "GameFontDisableSmall")
	sub:SetPoint("LEFT", header, "RIGHT", 8, 0)

	local headerHit = CreateFrame("Frame", nil, frame)
	headerHit:SetPoint("TOPLEFT", rightX, -30)
	headerHit:SetSize(WIDTH - rightX - 14, 18)
	headerHit:EnableMouse(true)
	headerHit:SetScript("OnEnter", function(self)
		if not selected or not selected:find("^g:") then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GroupTooltip(selected:sub(3))
		GameTooltip:Show()
	end)
	headerHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

	smf = CreateFrame("ScrollingMessageFrame", nil, frame)
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

	empty = UI.Text(frame, "GameFontDisable")
	empty:SetPoint("CENTER", frame, "CENTER", (LEFT_W + 12) / 2, 0)
	empty:SetText("Pick a conversation, or create a group.")

	input = UI.EditBox(frame, WIDTH - rightX - 20)
	input:SetPoint("BOTTOMLEFT", rightX + 6, 14)
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

	frame:SetScript("OnShow", function()
		if selected then Data:ClearUnread(selected) end
		Window:Refresh()
	end)
	frame:Hide()
end

function Window:Refresh()
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

function Window:Select(conv)
	selected = conv
	ns.db.lastConv = conv
	Data:ClearUnread(conv)
	self:Refresh()
end

function Window:Open(conv)
	if not frame then Create() end
	if conv then
		selected = conv
		ns.db.lastConv = conv
		Data:ClearUnread(conv)
	end
	frame:Show()
	self:Refresh()
end

function Window:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		if not selected and ns.db.lastConv then selected = ns.db.lastConv end
		self:Open()
	end
end

function Window:IsShown() return frame ~= nil and frame:IsShown() end
function Window:Hide() if frame then frame:Hide() end end
function Window:Selected() return selected end
function Window:Lines() return lines end
function Window:Items() return frame and frame:IsShown() and list.items or {} end
function Window:Header() return header and header:GetText(), sub and sub:GetText() end
function Window:Type(text)
	input:SetText(text)
	self:SendInput()
end

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
	if what ~= "unread" then Window:RequestRefresh() end
end)
