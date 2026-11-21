-- Huddle – transport: addon-whispers til hvert medlem (AceComm + AceSerializer), SPEC.md §4-5.
--
-- Beskedtyper (felt k). Ukendte typer ignoreres; nye data = ny type, aldrig nye felter i gamle typer.
--   H  { g = { [gid] = { v = version, h = have } }, r = 1 hvis svar, hv = addon-version }
--   G  { d = gruppe-definition }                       (Groups:Def)
--   M  { g = gid, m = { a, n, t, x }, s = 1 ved indhentning }
--   P / Q                                              ping / pong (/huddle debug ping)
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data
local Groups = ns.Groups

local PREFIX = "Huddle1"
local SYNC_LIMIT = 100          -- beskeder pr. gruppe pr. HELLO; resten tages ved næste runde
local TICK = 300                -- hvert 5. minut: HELLO til dem, der er online eller ikke har seneste version
local ONLINE_FOR = 1200         -- så længe regner vi en, vi har hørt fra, for online (sek.)
local NOT_FOUND_WINDOW = 15     -- "No player named X" inden for så mange sek. efter en afsendelse = offline

local Comm = {}
ns.Comm = Comm

local AceComm = LibStub("AceComm-3.0")
local Serializer = LibStub("AceSerializer-3.0")
AceComm:Embed(Comm)

Comm.online = {}   -- [navn] = GetTime() for sidste besked fra dem
Comm.sentAt = {}   -- [navn] = GetTime() for sidste afsendelse til dem
Comm.acked = {}    -- [gid] = { [navn] = version, de har bekræftet }
local queue = {}   -- beskeder, der venter på at kampen slutter

------------------------------------------------------------------------
-- Online-status
------------------------------------------------------------------------
function Comm:MarkOnline(name)
	self.online[name] = GetTime()
	Data:Peer(name).addon = true
end

function Comm:MarkOffline(name)
	if self.online[name] then
		self.online[name] = nil
		ns.Debug("%s is offline", name)
		ns.Changed("online", name)
	end
end

function Comm:IsOnline(name)
	local t = self.online[name]
	return t ~= nil and GetTime() - t < ONLINE_FOR
end

------------------------------------------------------------------------
-- Afsendelse
------------------------------------------------------------------------
local function RawSend(target, payload)
	Comm.sentAt[target] = GetTime()
	local ok, err = pcall(Comm.SendCommMessage, Comm, PREFIX, Serializer:Serialize(payload), "WHISPER", target, "NORMAL")
	if not ok then ns.Debug("send %s to %s failed: %s", payload.k, target, err) end
end

local function Flush()
	if Compat.InCombat() then return end
	while #queue > 0 do
		local item = table.remove(queue, 1)
		RawSend(item.target, item.payload)
	end
end

function Comm:Send(target, payload)
	if not target or Data:IsMine(target) then return end
	-- Holder rækkefølgen: står der noget i kø, kommer det nye bagerst.
	if Compat.InCombat() or #queue > 0 then
		table.insert(queue, { target = target, payload = payload })
		Flush()
		return
	end
	RawSend(target, payload)
end

function Comm:QueueLength() return #queue end

------------------------------------------------------------------------
-- HELLO
------------------------------------------------------------------------
function Comm:HelloPayload(peer, reply)
	local g = {}
	for gid, group in pairs(ns.DB.groups) do
		if Groups:Active(group) and group.members[peer] then
			g[gid] = { v = group.ver, h = Groups:Have(gid) }
		end
	end
	return { k = "H", g = g, r = reply and 1 or nil, hv = ns.VERSION }
end

function Comm:Hello(peer, reply)
	self:Send(peer, self:HelloPayload(peer, reply))
end

-- Alle andre medlemmer af mine aktive grupper.
function Comm:AllPeers()
	local set = {}
	for _, group in pairs(ns.DB.groups) do
		if Groups:Active(group) then
			for name in pairs(group.members) do
				if not Data:IsMine(name) then set[name] = true end
			end
		end
	end
	return set
end

-- Har peer ikke bekræftet den nyeste version af en fælles gruppe?
function Comm:Pending(peer)
	for gid, group in pairs(ns.DB.groups) do
		if Groups:Active(group) and group.members[peer] then
			local acked = self.acked[gid] and self.acked[gid][peer]
			if not acked or acked < group.ver then return true end
		end
	end
	return false
end

function Comm:HelloAll()
	for peer in pairs(self:AllPeers()) do self:Hello(peer) end
end

-- Den faste runde: kun dem, der er online, eller som mangler en gruppe-ændring (fx tilføjet mens offline).
function Comm:Tick()
	for peer in pairs(self:AllPeers()) do
		if self:IsOnline(peer) or self:Pending(peer) then self:Hello(peer) end
	end
end

local function Ack(gid, peer, v)
	Comm.acked[gid] = Comm.acked[gid] or {}
	if type(v) == "number" and v > (Comm.acked[gid][peer] or 0) then Comm.acked[gid][peer] = v end
end

local function OnHello(msg, sender)
	local entries = type(msg.g) == "table" and msg.g or {}
	if type(msg.hv) == "string" then Data:Peer(sender).version = msg.hv end
	for gid, group in pairs(ns.DB.groups) do
		if Groups:Active(group) and group.members[sender] then
			local e = type(entries[gid]) == "table" and entries[gid] or nil
			if e then Ack(gid, sender, e.v) end
			if not e or type(e.v) ~= "number" or e.v < group.ver then
				Comm:Send(sender, { k = "G", d = Groups:Def(gid) })
			end
			local seen = {}
			for _, m in ipairs(Groups:Missing(gid, e and e.h, SYNC_LIMIT)) do
				local first = not seen[m.a] or nil
				seen[m.a] = true
				Comm:Send(sender, { k = "M", g = gid, m = { a = m.a, n = m.n, t = m.t, x = m.x }, s = 1,
					f = first and 1 or nil })
			end
		end
	end
	if not msg.r then Comm:Hello(sender, true) end
end

------------------------------------------------------------------------
-- Modtagelse
------------------------------------------------------------------------
function Comm:OnCommReceived(prefix, text, distribution, sender)
	if prefix ~= PREFIX then return end
	if Compat.IsSecret(text) or Compat.IsSecret(sender) then return end
	sender = Compat.FullName(sender)
	if not sender or sender == ns.me then return end
	local ok, msg = Serializer:Deserialize(text)
	if not ok or type(msg) ~= "table" then return end
	self:MarkOnline(sender)
	local k = msg.k
	if k == "H" then
		ns.Debug("HELLO from %s%s", sender, msg.r and " (reply)" or "")
		OnHello(msg, sender)
	elseif k == "G" then
		local known = type(msg.d) == "table" and ns.DB.groups[msg.d.id] ~= nil
		if Groups:ApplyDef(msg.d, sender, msg.j) then
			Ack(msg.d.id, sender, msg.d.v)
			-- Ny gruppe: hils tilbage, så afsenderen ved, vi er online, og vi får historikken.
			if not known then self:Hello(sender, true) end
		end
	elseif k == "M" then
		Groups:Receive(msg.g, msg.m, sender, msg.s == 1, msg.f == 1)
	elseif k == "P" then
		self:Send(sender, { k = "Q", hv = ns.VERSION })
	elseif k == "Q" then
		ns.Print(("pong from %s (Huddle %s)"):format(sender, tostring(msg.hv)))
	end
	ns.Changed("online", sender)
end

------------------------------------------------------------------------
-- Egne ændringer ud
------------------------------------------------------------------------
function Comm:PushGroup(gid, targets, joinOf)
	local def = Groups:Def(gid)
	for _, name in ipairs(targets) do
		if not Data:IsMine(name) then
			self:Send(name, { k = "G", d = def, j = joinOf })
			-- En alt, der lige er kommet med, kender ikke de andre endnu: hils, så beskeder kan flyde.
			if joinOf then self:Hello(name) end
		end
	end
end

-- Kun til dem, der er online; de andre får beskeden ved næste HELLO (indhentning).
function Comm:PushMessage(gid, m)
	local group = ns.DB.groups[gid]
	for name in pairs(group.members) do
		if not Data:IsMine(name) and self:IsOnline(name) then
			self:Send(name, { k = "M", g = gid, m = { a = m.a, n = m.n, t = m.t, x = m.x } })
		end
	end
end

function Comm:Ping(target)
	target = Compat.FullName(target)
	if not target then return end
	ns.Print("ping " .. target .. " ...")
	RawSend(target, { k = "P" })
end

------------------------------------------------------------------------
-- "No player named 'X' is currently playing." efter vores egne afsendelser: X er offline, og beskeden
-- skjules. Mønsteret bygges af klientens egen tekst, så det virker på alle sprog.
------------------------------------------------------------------------
local notFoundPattern
local function NotFoundName(text)
	if type(text) ~= "string" or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return nil end
	if not notFoundPattern then
		local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
		local pattern = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.-)")
		notFoundPattern = "^" .. pattern .. "$"
	end
	local name = text:match(notFoundPattern)
	return name and Compat.FullName(name)
end

-- Har spilleren selv whispered personen lige nu, skal fejlbeskeden ses (den handler om deres whisper).
Comm.userSentAt = {}
local function OursRecently(name)
	local t = name and Comm.sentAt[name]
	if t == nil or GetTime() - t >= NOT_FOUND_WINDOW then return false end
	local u = Comm.userSentAt[name]
	return not (u and GetTime() - u < NOT_FOUND_WINDOW)
end

function Comm.SystemFilter(_, _, text, ...)
	if Compat.IsSecret(text) then return false end
	local name = NotFoundName(text)
	if name and OursRecently(name) then return true end
	return false
end

-- "|Hplayer:Anna-Realm|h[Anna]|h has come online." (venner og guild) -> HELLO, hvis vi deler en gruppe.
local function CameOnlineName(text)
	if type(text) ~= "string" then return nil end
	local link = text:match("|Hplayer:([^|:]+)")
	if link and type(ERR_FRIEND_ONLINE_SS) == "string" then
		local tail = ERR_FRIEND_ONLINE_SS:match("|h(.-)$")
		tail = tail and tail:gsub("^%[.-%]|h", "")
		if tail and tail ~= "" and text:find(tail, 1, true) then return Compat.FullName(link) end
	end
end

ns.On("CHAT_MSG_SYSTEM", function(text)
	if Compat.IsSecret(text) then return end
	local name = NotFoundName(text)
	if name and OursRecently(name) then
		Comm:MarkOffline(name)
		return
	end
	local online = CameOnlineName(text)
	if online and Comm:AllPeers()[online] then
		C_Timer.After(5, function() Comm:Hello(online) end)
	end
end)

ns.OnLoad(function()
	Comm:RegisterComm(PREFIX)
	Compat.AddMessageEventFilter("CHAT_MSG_SYSTEM", Comm.SystemFilter)
end)

local loggedIn = false
ns.On("PLAYER_LOGIN", function()
	C_Timer.After(5, function()
		loggedIn = true
		Comm:HelloAll()
	end)
	local function Loop()
		Comm:Tick()
		C_Timer.After(TICK, Loop)
	end
	C_Timer.After(TICK, Loop)
end)

-- Efter en loading screen (fx ud af en dungeon, hvor addon-beskeder kan være spærret): indhent.
ns.On("PLAYER_ENTERING_WORLD", function()
	if not loggedIn then return end
	C_Timer.After(3, function()
		for peer in pairs(Comm:AllPeers()) do
			if Comm:IsOnline(peer) then Comm:Hello(peer) end
		end
	end)
end)

ns.On("PLAYER_REGEN_ENABLED", Flush)
