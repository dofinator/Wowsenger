-- Wowsenger – almindelige 1:1-whispers (også med folk uden addonen). Blizzards chat viser dem stadig
-- (brugerens valg 2026-11-21); Wowsenger gemmer en kopi og viser samtalen i sit vindue.
-- Under encounters/M+ kan teksten være "secret": så gemmes kun en grå markering (SPEC.md §7).
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data

local Whispers = {}
ns.Whispers = Whispers

-- Nyeste først.
function Whispers:List()
	local list = {}
	for name in pairs(ns.DB.whispers) do list[#list + 1] = name end
	table.sort(list, function(a, b)
		local ta, tb = Data:LastWhisperTime(a), Data:LastWhisperTime(b)
		if ta ~= tb then return ta > tb end
		return a < b
	end)
	return list
end

function Whispers:Messages(name) return ns.DB.whispers[name] or {} end

-- Åbner en (evt. tom) samtale med en person.
function Whispers:Open(name)
	if not Compat.IsBNetKey(name) then name = Compat.FullName(name) end
	if not name then return end
	ns.DB.whispers[name] = ns.DB.whispers[name] or {}
	return name
end

-- Sletter samtalen og giver det slettede tilbage, så det kan fortrydes (Undo i listen).
function Whispers:Delete(name)
	local list = ns.DB.whispers[name]
	if not list then return nil end
	local conv = "w:" .. name
	local removed = { name = name, list = list, unread = ns.DB.unread[conv] }
	ns.DB.whispers[name] = nil
	ns.DB.unread[conv] = nil
	return removed
end

-- Fortryd: lægger de slettede linjer tilbage foran det, der evt. er kommet til siden.
function Whispers:Restore(removed)
	if not removed then return end
	local now = ns.DB.whispers[removed.name]
	local list = removed.list
	if now then
		for _, e in ipairs(now) do table.insert(list, e) end
		while #list > Data.MAX_WHISPERS do table.remove(list, 1) end
	end
	ns.DB.whispers[removed.name] = list
	local conv = "w:" .. removed.name
	if removed.unread then ns.DB.unread[conv] = (ns.DB.unread[conv] or 0) + removed.unread end
end

function Whispers:Send(name, text)
	if type(text) ~= "string" or text == "" or not name then return false end
	-- Kopien gemmes, når spillet bekræfter med CHAT_MSG_(BN_)WHISPER_INFORM.
	if Compat.IsBNetKey(name) then
		return Compat.SendBNetWhisper(name, text:sub(1, 255))
	end
	ns.Comm.userSentAt[name] = GetTime()
	return Compat.SendWhisper(text:sub(1, 255), name)
end

-- Karakter-samtaler (ikke Battle.net), til fx "New group"-kandidater.
function Whispers:Characters()
	local out = {}
	for _, key in ipairs(self:List()) do
		if not Compat.IsBNetKey(key) then out[#out + 1] = key end
	end
	return out
end

local function ClassFromGUID(guid)
	guid = Compat.Safe(guid)
	if type(guid) ~= "string" or not GetPlayerInfoByGUID then return nil end
	local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
	return ok and Compat.Safe(class) or nil
end

-- name = "Navn-Realm" eller en BattleTag.
local function Store(out, text, name, guid)
	local entry = { out = out or nil, t = Compat.Now() }
	if Compat.IsSecret(text) or type(text) ~= "string" then
		entry.hidden = true
	else
		entry.x = text
	end
	local class = ClassFromGUID(guid)
	if class then Data:Peer(name).class = class end
	Data:AddWhisper(name, entry)
	if not out then ns.Changed("incoming", "w:" .. name, entry) end
	ns.Changed("whisper", name)
end

local function Record(out, text, name, guid)
	name = Compat.FullName(name)
	if not name or Data:IsMine(name) then return end
	Store(out, text, name, guid)
end

ns.On("CHAT_MSG_WHISPER", function(text, sender, _, _, _, flags, _, _, _, _, _, guid)
	-- GM-whispers og den slags hører ikke hjemme i en vennesamtale.
	if Compat.Safe(flags) == "GM" then return end
	Record(false, text, sender, guid)
end)

ns.On("CHAT_MSG_WHISPER_INFORM", function(text, target, _, _, _, _, _, _, _, _, _, guid)
	Record(true, text, target, guid)
end)

-- Battle.net: argument 13 er vennens konto-id (afsender ved WHISPER, modtager ved INFORM).
-- Navnet (argument 2) er en beskyttet |K-streng og bruges ikke.
local function RecordBNet(out, text, bnetID)
	local tag = Compat.BNetTag(bnetID)
	if not tag then
		ns.Debug("Battle.net whisper without a readable BattleTag ignored")
		return
	end
	Store(out, text, tag)
end

ns.On("CHAT_MSG_BN_WHISPER", function(text, _, _, _, _, _, _, _, _, _, _, _, bnetID)
	RecordBNet(false, text, bnetID)
end)

ns.On("CHAT_MSG_BN_WHISPER_INFORM", function(text, _, _, _, _, _, _, _, _, _, _, _, bnetID)
	RecordBNet(true, text, bnetID)
end)
