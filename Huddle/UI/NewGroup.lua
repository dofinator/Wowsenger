-- Huddle – dialogen "New group" / "Edit group" (brugerens valg 2026-11-21: dialog med afkrydsning).
--
--   +- New group --------------------+
--   | Name  [Raid group          ]   |
--   | Members                        |
--   |  [x] Anna-Spineshatter         |
--   |  [x] Bob-Spineshatter          |
--   |  [ ] Cleo-Firemaw              |
--   | Add by name [          ] [Add] |
--   |            [Create] [Cancel]   |
--   +--------------------------------+
-- Kandidater: nuværende medlemmer, venner, seneste whisper-partnere, medlemmer af mine andre grupper og
-- online guild-medlemmer. Alle medlemmer må ændre gruppen.
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data
local Groups = ns.Groups
local UI = ns.UI

local NewGroup = {}
ns.NewGroup = NewGroup

local ROWS = 9
local RECENT = 15
local frame, list
local state -- { gid = nil|gid, candidates = { { key, checked, online } }, byKey = {} }

local function AddCandidate(key, checked, online)
	if not key or key == ns.me then return end
	local c = state.byKey[key]
	if not c then
		c = { key = key }
		state.byKey[key] = c
		table.insert(state.candidates, c)
	end
	if checked then c.checked = true end
	if online then c.online = true end
end

local function Sort()
	table.sort(state.candidates, function(a, b)
		if (a.checked or false) ~= (b.checked or false) then return a.checked == true end
		if (a.online or false) ~= (b.online or false) then return a.online == true end
		return a.key < b.key
	end)
end

local function Gather(gid)
	state = { gid = gid, candidates = {}, byKey = {} }
	local g = gid and Groups:Get(gid)
	if g then
		for name in pairs(g.members) do
			if not Data:IsMine(name) then AddCandidate(name, true) end
		end
	end
	for _, f in ipairs(Compat.Friends()) do AddCandidate(f.key, false, f.online) end
	local recent = ns.Whispers:Characters()
	for i = 1, math.min(#recent, RECENT) do AddCandidate(recent[i]) end
	for _, other in pairs(ns.DB.groups) do
		if not other.left and not other.demo then
			for name in pairs(other.members) do
				if not Data:IsMine(name) then AddCandidate(name) end
			end
		end
	end
	for _, m in ipairs(Compat.OnlineGuildMembers()) do AddCandidate(m.key, false, true) end
	for _, c in ipairs(state.candidates) do
		if ns.Comm:IsOnline(c.key) then c.online = true end
	end
	Sort()
end

local function Error(text)
	frame.error:SetText(text or "")
end

local function Checked()
	local out = {}
	for _, c in ipairs(state.candidates) do
		if c.checked then out[#out + 1] = c.key end
	end
	return out
end

function NewGroup:Submit()
	local name = strtrim(frame.name:GetText() or "")
	if name == "" then return Error("Enter a name for the group.") end
	local members = Checked()
	if #members == 0 then return Error("Pick at least one member.") end
	if state.gid then
		local g = Groups:Get(state.gid)
		-- Er en af mine karakterer med, bliver den ved med at være det.
		for n in pairs(g.members) do
			if Data:IsMine(n) then members[#members + 1] = n end
		end
		Groups:Update(state.gid, name, members)
		frame:Hide()
		ns.Window:Open("g:" .. state.gid)
	else
		local gid = Groups:Create(name, members)
		frame:Hide()
		ns.Window:Open("g:" .. gid)
	end
end

function NewGroup:AddByName()
	local text = strtrim(frame.add:GetText() or "")
	local key = Compat.FullName(text)
	local base = text:match("^([^%-]+)")
	if not key or not base or base:find("[%s%d%p]") then
		return Error("Type a character name, like Anna or Anna-Firemaw.")
	end
	if key == ns.me then return Error("That's you.") end
	AddCandidate(key, true)
	state.byKey[key].checked = true
	Sort()
	frame.add:SetText("")
	Error()
	list:SetItems(state.candidates)
end

local function Create()
	frame = CreateFrame("Frame", "HuddleNewGroup", UIParent, "BackdropTemplate")
	frame:SetSize(320, 390)
	frame:SetPoint("CENTER", 0, 40)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	UI.Backdrop(frame, true)
	if UISpecialFrames then table.insert(UISpecialFrames, "HuddleNewGroup") end

	frame.title = UI.Text(frame, "GameFontNormal")
	frame.title:SetPoint("TOP", 0, -18)

	local nameLabel = UI.Text(frame, "GameFontNormalSmall")
	nameLabel:SetPoint("TOPLEFT", 24, -46)
	nameLabel:SetText("Name")
	frame.name = UI.EditBox(frame, 210)
	frame.name:SetPoint("LEFT", nameLabel, "LEFT", 60, 0)
	frame.name:SetMaxLetters(40)
	frame.name:SetScript("OnTextChanged", function() Error() end)

	local membersLabel = UI.Text(frame, "GameFontNormalSmall")
	membersLabel:SetPoint("TOPLEFT", 24, -74)
	membersLabel:SetText("Members")

	local box = CreateFrame("Frame", nil, frame)
	box:SetPoint("TOPLEFT", 20, -90)
	box:SetSize(280, ROWS * 20)
	list = UI.ScrollList(box, ROWS, 20, function(row)
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(20, 20)
		row.check:SetPoint("LEFT", 0, 0)
		row.label = UI.Text(row, "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
		local function Toggle()
			if row.item then
				row.item.checked = not row.item.checked
				Error()
				list:Update()
			end
		end
		row.check:SetScript("OnClick", Toggle)
		row:SetScript("OnClick", Toggle)
	end, function(row, c)
		row.check:SetChecked(c.checked and true or false)
		local text = UI.Name(c.key)
		if c.online then text = text .. "  " .. UI.GRAY .. "online|r" end
		row.label:SetText(text)
	end)

	local addLabel = UI.Text(frame, "GameFontNormalSmall")
	addLabel:SetPoint("TOPLEFT", 24, -(98 + ROWS * 20))
	addLabel:SetText("Add by name")
	frame.add = UI.EditBox(frame, 130)
	frame.add:SetPoint("LEFT", addLabel, "LEFT", 90, 0)
	frame.add:SetScript("OnEnterPressed", function() NewGroup:AddByName() end)
	local addButton = UI.Button(frame, "Add", 60)
	addButton:SetPoint("LEFT", frame.add, "RIGHT", 6, 0)
	addButton:SetScript("OnClick", function() NewGroup:AddByName() end)

	frame.error = UI.Text(frame, "GameFontRedSmall")
	frame.error:SetPoint("BOTTOMLEFT", 24, 48)
	frame.error:SetPoint("RIGHT", -24, 0)
	frame.error:SetJustifyH("LEFT")

	frame.ok = UI.Button(frame, "Create", 100)
	frame.ok:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 18)
	frame.ok:SetScript("OnClick", function() NewGroup:Submit() end)
	local cancel = UI.Button(frame, CANCEL or "Cancel", 100)
	cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 18)
	cancel:SetScript("OnClick", function() frame:Hide() end)
	frame.name:SetScript("OnEnterPressed", function() NewGroup:Submit() end)
end

-- gid = nil: ny gruppe. Ellers redigeres gruppen (navn og medlemmer).
function NewGroup:Open(gid)
	if not frame then Create() end
	if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
	Gather(gid)
	local g = gid and Groups:Get(gid)
	frame.title:SetText(g and "Edit group" or "New group")
	frame.ok:SetText(g and (SAVE or "Save") or "Create")
	frame.name:SetText(g and g.name or "")
	frame.add:SetText("")
	Error()
	frame:Show()
	list:SetItems(state.candidates)
	if not g then frame.name:SetFocus() end
end

function NewGroup:IsShown() return frame ~= nil and frame:IsShown() end

-- Til test: { { key, checked, online } }
function NewGroup:Candidates() return state and state.candidates or {} end
function NewGroup:Frame() return frame end
