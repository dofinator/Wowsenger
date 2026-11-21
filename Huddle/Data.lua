-- Huddle – gemte data (HuddleDB, pr. konto, så grupper og historik følger med mellem ens karakterer).
--
-- HuddleDB = {
--   version  = 1,
--   settings = { debug, toast, sound, minimap = { hide }, window = { point, relPoint, x, y } },
--   chars    = { ["Navn-Realm"] = { class, last } },     -- egne karakterer (automatisk ved login)
--   counter  = 0,                                        -- løbenummer til nye gruppe-id'er
--   groups   = { [gid] = Group },
--   messages = { [gid] = { Msg, ... } },                 -- sorteret efter (t, a, n), max MAX_MESSAGES
--   whispers = { ["Navn-Realm"] = { Whisper, ... } },    -- 1:1, max MAX_WHISPERS pr. person
--   unread   = { [samtale] = antal },                    -- samtale = "g:<gid>" eller "w:<Navn-Realm>"
--   peers    = { ["Navn-Realm"] = { class, addon } },    -- hvad vi ved om andre (klasse, har Huddle)
--   trace    = { ... },                                  -- fejlsøgning (Core.lua)
-- }
-- Group   = { name, members = { [navn] = true }, ver, by, former = { [navn] = true }, created, left, demo }
-- Msg     = { a = forfatter, n = nr, t = servertid, x = tekst, late = true hvis den kom ved indhentning }
-- Whisper = { out = true|nil, t, x, hidden = true|nil (secret under encounter) }
local _, ns = ...

local Compat = ns.Compat
local Data = {}
ns.Data = Data

Data.MAX_MESSAGES = 500
Data.MAX_WHISPERS = 500

local DEFAULT_SETTINGS = {
	debug = false,
	toast = true,
	sound = true,
	minimap = { hide = false },
}

local function Fill(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			if type(v) == "table" then
				target[k] = {}
				Fill(target[k], v)
			else
				target[k] = v
			end
		elseif type(v) == "table" and type(target[k]) == "table" then
			Fill(target[k], v)
		end
	end
end

function Data:Init()
	HuddleDB = type(HuddleDB) == "table" and HuddleDB or {}
	local db = HuddleDB
	db.version = db.version or 1
	db.settings = type(db.settings) == "table" and db.settings or {}
	Fill(db.settings, DEFAULT_SETTINGS)
	for _, k in ipairs({ "chars", "groups", "messages", "whispers", "unread", "peers" }) do
		if type(db[k]) ~= "table" then db[k] = {} end
	end
	db.counter = tonumber(db.counter) or 0
	ns.DB = db
	ns.db = db.settings

	ns.me = Compat.MyName()
	if ns.me then
		db.chars[ns.me] = db.chars[ns.me] or {}
		db.chars[ns.me].class = Compat.MyClass()
		db.chars[ns.me].last = Compat.Now()
	end
end

-- Er navnet en af mine egne karakterer (på denne konto)?
function Data:IsMine(name)
	return name ~= nil and ns.DB.chars[name] ~= nil
end

-- Version, der altid er større end den gamle og normalt = servertid (lærdom fra GuildCrafters: tom
-- gemt data må ikke tabe til gamle kopier).
function Data.Bump(old)
	return math.max((tonumber(old) or 0) + 1, Compat.Now())
end

function Data:Class(name)
	if self:IsMine(name) then return ns.DB.chars[name].class end
	local p = ns.DB.peers[name]
	return p and p.class
end

function Data:Peer(name)
	local p = ns.DB.peers[name]
	if not p then
		p = {}
		ns.DB.peers[name] = p
	end
	return p
end

------------------------------------------------------------------------
-- Ulæste
------------------------------------------------------------------------
function Data:AddUnread(conv)
	ns.DB.unread[conv] = (ns.DB.unread[conv] or 0) + 1
end

function Data:ClearUnread(conv)
	if ns.DB.unread[conv] then
		ns.DB.unread[conv] = nil
		return true
	end
end

function Data:Unread(conv)
	return ns.DB.unread[conv] or 0
end

function Data:TotalUnread()
	local n = 0
	for _, c in pairs(ns.DB.unread) do n = n + c end
	return n
end

------------------------------------------------------------------------
-- 1:1-whispers
------------------------------------------------------------------------
function Data:AddWhisper(name, entry)
	local list = ns.DB.whispers[name]
	if not list then
		list = {}
		ns.DB.whispers[name] = list
	end
	table.insert(list, entry)
	while #list > self.MAX_WHISPERS do table.remove(list, 1) end
end

function Data:LastWhisperTime(name)
	local list = ns.DB.whispers[name]
	local last = list and list[#list]
	return last and last.t or 0
end
