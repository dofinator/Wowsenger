-- Minimal falsk WoW-API til tools/sim.py. Én kopi pr. klient (egen Lua-runtime). Kun det Huddle bruger.
mock = { now = 1000, clock = 1763700000, timers = {}, frames = {}, chat = {}, sent = {}, whispersOut = {},
	comm = {}, ldb = {}, secret = {}, friends = {}, filters = {}, hooks = {}, inCombat = false,
	player = { name = "Tester", realm = "Spineshatter", class = "PRIEST" } }

unpack = unpack or table.unpack
function issecretvalue(v) return v ~= nil and mock.secret[v] == true end

function GetTime() return mock.now end
local realTime = os.time
function time(t) if t then return realTime(t) end return mock.clock + math.floor(mock.now - 1000) end
function GetServerTime() return time() end
date = os.date

C_Timer = {}
function C_Timer.After(delay, fn) table.insert(mock.timers, { at = mock.now + delay, fn = fn }) end

function mock.advance(seconds)
	local target = mock.now + seconds
	while true do
		local best, bi
		for i, t in ipairs(mock.timers) do
			if t.at <= target and (not best or t.at < best.at) then best, bi = t, i end
		end
		if not best then break end
		table.remove(mock.timers, bi)
		mock.now = best.at
		best.fn()
	end
	mock.now = target
	for _, f in ipairs(mock.frames) do
		local onUpdate = f.scripts.OnUpdate
		if onUpdate and f.shown then onUpdate(f, seconds) end
	end
end

function UnitName(unit) if unit == "player" then return mock.player.name, nil end end
function UnitClass(unit) if unit == "player" then return mock.player.class, mock.player.class end end
function GetRealmName() return mock.player.realm end
function GetNormalizedRealmName() return (mock.player.realm:gsub("%s", "")) end
function GetAddOnMetadata() return "0.1.0" end
function geterrorhandler() return function(err) error(err) end end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function InCombatLockdown() return mock.inCombat end
function IsInGuild() return false end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 100, 100 end
function PlaySound(id) mock.sounds = (mock.sounds or 0) + 1 end
function GetPlayerInfoByGUID(guid) local c = mock.guids and mock.guids[guid]; if c then return c, c end end
SOUNDKIT = { TELL_MESSAGE = 3081 }
YES, CANCEL, DELETE, SAVE = "Yes", "Cancel", "Delete", "Save"
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
RAID_CLASS_COLORS = {
	PRIEST = { r = 1, g = 1, b = 1, colorStr = "ffffffff" },
	MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" },
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
}

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(mock.chat, msg) end }
SlashCmdList = {}
UISpecialFrames = {}
-- Huddle må ikke bruge Blizzards popups/menuer (taint).
StaticPopupDialogs = setmetatable({}, { __newindex = function(_, k) error("StaticPopupDialogs." .. tostring(k)) end })
function StaticPopup_Show(name) error("StaticPopup_Show(" .. tostring(name) .. ")") end
function EasyMenu() error("EasyMenu") end

-- Chat: Forever-udgaven af filter-API'et. mock.system(text) kører filtrene som chatvinduet gør.
ChatFrameUtil = {}
function ChatFrameUtil.AddMessageEventFilter(event, fn)
	mock.filters[event] = mock.filters[event] or {}
	table.insert(mock.filters[event], fn)
end
function ChatFrameUtil.InsertLink(link) return false end
function mock.system(text)
	mock.fire("CHAT_MSG_SYSTEM", text)
	for _, fn in ipairs(mock.filters.CHAT_MSG_SYSTEM or {}) do
		if fn(DEFAULT_CHAT_FRAME, "CHAT_MSG_SYSTEM", text) then return false end
	end
	table.insert(mock.chat, text)
	return true
end
function hooksecurefunc(a, b, c)
	local tbl, name, fn = a, b, c
	if type(a) == "string" then tbl, name, fn = _G, a, b end
	local orig = tbl[name]
	tbl[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end

C_ChatInfo = {}
function C_ChatInfo.SendChatMessage(text, kind, lang, target)
	if mock.chatBlocked then error("blocked") end
	table.insert(mock.whispersOut, { text = text, kind = kind, target = target })
end
C_PartyInfo = { InviteUnit = function(name) mock.invited = name end }
-- Battle.net: mock.bnet[id] = { battleTag, bnetAccountID } (alle konti, klienten kender), mock.bnetFriends = liste.
mock.bnet, mock.bnetFriends, mock.bnOut = {}, {}, {}
C_BattleNet = {}
function C_BattleNet.GetAccountInfoByID(id) return mock.bnet[id] end
function C_BattleNet.GetFriendAccountInfo(i) return mock.bnetFriends[i] end
function C_BattleNet.SendWhisper(id, text) table.insert(mock.bnOut, { id = id, text = text }) end
function BNGetNumFriends() return #mock.bnetFriends end
C_FriendList = {}
function C_FriendList.GetNumFriends() return #mock.friends end
function C_FriendList.GetFriendInfoByIndex(i) return mock.friends[i] end
function C_FriendList.ShowFriends() end

------------------------------------------------------------------------
-- Frames: ukendte metoder er no-ops.
------------------------------------------------------------------------
local Frame = {}
local function NewObject(kind)
	local o = { kind = kind, scripts = {}, events = {}, shown = true, text = nil, points = {}, children = {} }
	return setmetatable(o, Frame)
end
Frame.__index = function(o, k)
	local m = rawget(Frame, k)
	if m then return m end
	if k == "TitleText" then return nil end
	if type(k) == "string" and k:find("^%u") then return function() end end
	return nil
end
function Frame.SetScript(o, name, fn) o.scripts[name] = fn end
function Frame.GetScript(o, name) return o.scripts[name] end
function Frame.RegisterEvent(o, ev)
	if mock.unknownEvents and mock.unknownEvents[ev] then error("unknown event " .. ev) end
	o.events[ev] = true
end
function Frame.Show(o)
	local was = mock.visible(o)
	o.shown = true
	if not was and mock.visible(o) and o.scripts.OnShow then o.scripts.OnShow(o) end
end
function Frame.Hide(o) o.shown = false end
function Frame.IsShown(o) return o.shown end
function Frame.IsVisible(o) return mock.visible(o) end
function Frame.SetShown(o, v) if v then o:Show() else o:Hide() end end
function Frame.SetText(o, t)
	o.text = t
	if o.kind == "EditBox" and o.scripts.OnTextChanged then o.scripts.OnTextChanged(o, false) end
end
function Frame.GetText(o) return o.text end
function Frame.Insert(o, t) o:SetText((o.text or "") .. t) end
function Frame.SetFocus(o) mock.focus = o end
function Frame.ClearFocus(o) if mock.focus == o then mock.focus = nil end end
function Frame.HasFocus(o) return mock.focus == o end
function Frame.SetChecked(o, v) o.checked = v and true or false end
function Frame.GetChecked(o) return o.checked end
function Frame.SetPoint(o, ...) table.insert(o.points, { ... }) end
function Frame.ClearAllPoints(o) o.points = {} end
function Frame.GetPoint(o) local p = o.points[1] or {}; return p[1], p[2], p[3], p[4], p[5] end
function Frame.SetSize(o, w, h) o.width, o.height = w, h end
function Frame.SetWidth(o, w) o.width = w end
function Frame.SetHeight(o, h) o.height = h end
function Frame.GetWidth(o) return o.width or 300 end
function Frame.GetHeight(o) return o.height or 300 end
function Frame.GetEffectiveScale() return 1 end
function Frame.SetFrameStrata(o, s) o.strata = s end
function Frame.IsMouseOver() return false end
function Frame.CreateFontString(o) local fs = NewObject("FontString"); fs.parent = o; table.insert(o.children, fs); return fs end
function Frame.CreateTexture(o) local t = NewObject("Texture"); t.parent = o; return t end
function Frame.Click(o, button) if o.scripts.OnClick then o.scripts.OnClick(o, button or "LeftButton") end end
function Frame.Enter(o) if o.scripts.OnEnter then o.scripts.OnEnter(o) end end
-- ScrollingMessageFrame
function Frame.AddMessage(o, text) o.msgs = o.msgs or {}; table.insert(o.msgs, text) end
function Frame.Clear(o) o.msgs = {} end

function CreateFrame(kind, name, parent, template)
	local f = NewObject(kind)
	f.parent = parent
	f.template = template
	if parent then table.insert(parent.children, f) end
	table.insert(mock.frames, f)
	if name then _G[name] = f end
	return f
end
UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
function GameTooltip.SetOwner(o) o.lines = {} end
function GameTooltip.AddLine(o, text) o.lines = o.lines or {}; table.insert(o.lines, tostring(text)) end
function GameTooltip.AddDoubleLine(o, l, r) o.lines = o.lines or {}; table.insert(o.lines, tostring(l) .. " | " .. tostring(r)) end
function GameTooltip.Show(o) o.shown = true end

function FauxScrollFrame_GetOffset(f) return f.offset or 0 end
function FauxScrollFrame_Update(f, total, shown) f.total, f.visible = total, shown end
function FauxScrollFrame_OnVerticalScroll(f, offset, rowH, update) f.offset = math.floor(offset / rowH + 0.5); update() end

function mock.fire(event, ...)
	for _, f in ipairs(mock.frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

function mock.visible(o)
	while o do
		if not o.shown then return false end
		o = o.parent
	end
	return true
end

------------------------------------------------------------------------
-- Libs: LibStub og AceSerializer køres rigtigt; AceComm, LibDataBroker og LibDBIcon er stubbe.
------------------------------------------------------------------------
function mock.registerLibStubs()
	local comm = LibStub:NewLibrary("AceComm-3.0", 999)
	function comm:Embed(target)
		function target:RegisterComm(prefix, method)
			mock.comm[prefix] = { obj = self, method = method or "OnCommReceived" }
		end
		function target:SendCommMessage(prefix, text, dist, to, prio)
			if mock.addonBlocked then error("blocked") end
			table.insert(mock.sent, { prefix = prefix, text = text, dist = dist, target = to })
		end
	end
	local ldb = LibStub:NewLibrary("LibDataBroker-1.1", 999)
	function ldb:NewDataObject(name, obj) mock.ldb[name] = obj; return obj end
	local icon = LibStub:NewLibrary("LibDBIcon-1.0", 999)
	function icon:Register(name, obj, db) mock.iconDB = db end
	function icon:Hide() mock.iconHidden = true end
	function icon:Show() mock.iconHidden = false end
end

function mock.receive(prefix, text, dist, sender)
	local h = mock.comm[prefix]
	if h then h.obj[h.method](h.obj, prefix, text, dist, sender) end
end

-- Gemmer HuddleDB som Lua-kode (til "logout" -> "login" i simulatoren).
function mock.dump(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
	local parts = {}
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
		parts[#parts + 1] = indent .. "  " .. key .. " = " .. mock.dump(v[k], indent .. "  ")
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
