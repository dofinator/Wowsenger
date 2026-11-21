-- Huddle – grupper og gruppebeskeder (uden transport; Comm.lua sender og modtager).
--
-- Regler (SPEC.md §5-6):
--   * En besked er (gruppe, forfatter, nr). Samme nøgle to gange = én besked.
--   * Beskeder og gruppe-ændringer accepteres kun fra nuværende medlemmer. Original = afsender er forfatter;
--     ellers er det en relay fra et medlem (forfatteren skal være eller have været medlem).
--   * Alle medlemmer må tilføje og fjerne. Nyeste version vinder (Data.Bump; lige versioner: "by" afgør).
local _, ns = ...

local Data = ns.Data
local Compat = ns.Compat

local Groups = {}
ns.Groups = Groups

local MAX_TEXT = 2000
local index = {}        -- [gid] = { ["forfatter#nr"] = true } (bygges ved første brug, gemmes ikke)
Groups.catchup = {}     -- [gid] = nøgle på første besked, der kom ved indhentning i denne session

local RaiseFloor -- defineres ved Have()

local function Key(a, n) return a .. "#" .. n end

local function Index(gid)
	local idx = index[gid]
	if not idx then
		idx = {}
		for _, m in ipairs(ns.DB.messages[gid] or {}) do idx[Key(m.a, m.n)] = true end
		index[gid] = idx
	end
	return idx
end

function Groups:Get(gid) return ns.DB.groups[gid] end

function Groups:IsMember(g, name)
	return g ~= nil and name ~= nil and g.members[name] == true
end

-- Er jeg (nogen af mine karakterer) med i gruppen?
function Groups:HasMe(g)
	for name in pairs(g.members) do
		if Data:IsMine(name) then return true end
	end
	return false
end

-- Er karakteren, jeg spiller lige nu, med (kun den kan sende og modtage)?
function Groups:Active(g)
	return g ~= nil and not g.left and not g.demo and self:IsMember(g, ns.me)
end

function Groups:Members(g)
	local list = {}
	for name in pairs(g.members) do list[#list + 1] = name end
	table.sort(list)
	return list
end

-- Andre medlemmer end mine egne karakterer.
function Groups:Others(g)
	local list = {}
	for _, name in ipairs(self:Members(g)) do
		if not Data:IsMine(name) then list[#list + 1] = name end
	end
	return list
end

-- Alle grupper, jeg er med i, nyeste aktivitet først.
function Groups:List()
	local list = {}
	for gid, g in pairs(ns.DB.groups) do
		if not g.left then list[#list + 1] = gid end
	end
	table.sort(list, function(a, b)
		local ta, tb = self:LastTime(a), self:LastTime(b)
		if ta ~= tb then return ta > tb end
		return a < b
	end)
	return list
end

function Groups:LastTime(gid)
	local msgs = ns.DB.messages[gid]
	local last = msgs and msgs[#msgs]
	local g = ns.DB.groups[gid]
	return last and last.t or (g and g.created) or 0
end

function Groups:Messages(gid) return ns.DB.messages[gid] or {} end

------------------------------------------------------------------------
-- Gruppe-definitionen på ledningen: { id, name, m = { navne }, v, by }
------------------------------------------------------------------------
function Groups:Def(gid)
	local g = ns.DB.groups[gid]
	return { id = gid, name = g.name, m = self:Members(g), v = g.ver, by = g.by }
end

local function ToSet(list)
	local set = {}
	for _, name in ipairs(list) do set[name] = true end
	return set
end

local function Newer(def, g)
	if def.v ~= g.ver then return def.v > g.ver end
	return tostring(def.by or "") > tostring(g.by or "")
end

local function Apply(g, def)
	local new = {}
	for _, raw in ipairs(def.m) do
		local name = Compat.FullName(raw)
		if name then new[name] = true end
	end
	for name in pairs(g.members or {}) do
		if not new[name] then g.former[name] = true end
	end
	for name in pairs(new) do g.former[name] = nil end
	g.members = new
	g.name = type(def.name) == "string" and def.name:sub(1, 40) or g.name or "Group"
	g.ver = def.v
	g.by = def.by
	g.left = not Groups:HasMe(g) or nil
end

-- En alt, der melder sig ind (j = den karakter på samme konto, der allerede er med): accepteres kun, hvis
-- ændringen er præcis "afsenderen kommer med", og afsenderen ikke er fjernet tidligere. Gruppe-id'et har en
-- tilfældig del, så kun dem, der har fået gruppen, kender det.
local function AltJoin(g, def, from, j)
	j = j and Compat.FullName(j)
	if not j or not g.members[j] or g.former[from] or g.members[from] then return false end
	local count, hasFrom = 0, false
	for _, raw in ipairs(def.m) do
		local name = Compat.FullName(raw)
		if name == from then
			hasFrom = true
		elseif not g.members[name] then
			return false
		end
		count = count + 1
	end
	local before = 0
	for _ in pairs(g.members) do before = before + 1 end
	return hasFrom and count == before + 1
end

-- En GROUP fra et andet medlem. Returnerer true, hvis noget ændrede sig.
function Groups:ApplyDef(def, from, joinOf)
	if type(def) ~= "table" or type(def.id) ~= "string" or type(def.m) ~= "table" or type(def.v) ~= "number" then
		return false
	end
	local inNew = false
	for _, raw in ipairs(def.m) do
		if Compat.FullName(raw) == from then inNew = true end
	end
	local g = ns.DB.groups[def.id]
	if g then
		if g.demo or not Newer(def, g) then return false end
		-- Et fjernet medlem må ikke selv melde sig ind igen; bliver det tilføjet af en anden, kommer den
		-- nye version fra de andre medlemmer.
		local allowed = g.members[from] or AltJoin(g, def, from, joinOf)
		if not allowed then
			ns.Debug("GROUP %s from non-member %s ignored", def.id, from)
			return false
		end
		local wasLeft = g.left
		Apply(g, def)
		ns.Debug("GROUP %s v%s from %s (%d members)", def.id, def.v, from, #def.m)
		if g.left and not wasLeft then ns.Changed("removed", def.id) end
	else
		local meIn = false
		for _, raw in ipairs(def.m) do
			if Compat.FullName(raw) == ns.me then meIn = true end
		end
		if not (meIn and inNew) then return false end
		g = { members = {}, former = {}, created = Compat.Now() }
		ns.DB.groups[def.id] = g
		Apply(g, def)
		ns.Debug("GROUP %s new from %s", def.id, from)
		ns.Changed("added", def.id)
	end
	ns.Changed("group", def.id)
	return true
end

------------------------------------------------------------------------
-- Egne ændringer
------------------------------------------------------------------------
function Groups:Create(name, members)
	local db = ns.DB
	local gid
	repeat
		db.counter = db.counter + 1
		gid = ("%s:%d:%06x"):format(ns.me, db.counter, math.random(0, 0xFFFFFF))
	until not db.groups[gid]
	local list = { ns.me }
	for _, m in ipairs(members) do
		if m ~= ns.me then list[#list + 1] = m end
	end
	local g = { members = {}, former = {}, created = Compat.Now() }
	db.groups[gid] = g
	Apply(g, { name = name, m = list, v = Data.Bump(0), by = ns.me })
	db.messages[gid] = db.messages[gid] or {}
	ns.Debug("created %s with %d members", gid, #list)
	if ns.Comm then ns.Comm:PushGroup(gid, list) end
	ns.Changed("group", gid)
	return gid
end

-- Ny medlemsliste og/eller nyt navn. Sendes til både gamle og nye medlemmer.
-- joinOf: når en alt melder sig ind, den af mine karakterer, der allerede er med.
function Groups:Update(gid, name, members, joinOf)
	local g = ns.DB.groups[gid]
	if not g or g.demo then return end
	local before = self:Members(g)
	Apply(g, { name = name or g.name, m = members or before, v = Data.Bump(g.ver), by = ns.me })
	local targets = ToSet(before)
	for name2 in pairs(g.members) do targets[name2] = true end
	local list = {}
	for name2 in pairs(targets) do list[#list + 1] = name2 end
	if ns.Comm then ns.Comm:PushGroup(gid, list, joinOf) end
	ns.Changed("group", gid)
end

function Groups:Leave(gid)
	local g = ns.DB.groups[gid]
	if not g then return end
	if g.demo then
		g.left = true
		ns.Changed("group", gid)
		return
	end
	local keep = {}
	for _, name in ipairs(self:Members(g)) do
		if not Data:IsMine(name) then keep[#keep + 1] = name end
	end
	self:Update(gid, g.name, keep)
end

------------------------------------------------------------------------
-- Beskeder
------------------------------------------------------------------------
local function Before(a, b)
	if a.t ~= b.t then return a.t < b.t end
	if a.a ~= b.a then return a.a < b.a end
	return a.n < b.n
end

-- Gemmer en besked. Returnerer true, hvis den var ny.
local function Store(gid, m)
	local idx = Index(gid)
	local key = Key(m.a, m.n)
	if idx[key] then return false end
	local list = ns.DB.messages[gid]
	if not list then
		list = {}
		ns.DB.messages[gid] = list
	end
	local pos = #list + 1
	while pos > 1 and Before(m, list[pos - 1]) do pos = pos - 1 end
	table.insert(list, pos, m)
	idx[key] = true
	while #list > Data.MAX_MESSAGES do
		local old = table.remove(list, 1)
		idx[Key(old.a, old.n)] = nil
		RaiseFloor(ns.DB.groups[gid], old.a, old.n)
	end
	return true
end

function Groups:NextNumber(gid, author)
	local high = 0
	for _, m in ipairs(ns.DB.messages[gid] or {}) do
		if m.a == author and m.n > high then high = m.n end
	end
	local g = ns.DB.groups[gid]
	g.seq = g.seq or {}
	high = math.max(high, g.seq[author] or 0) + 1
	g.seq[author] = high
	return high
end

-- Skriver i en gruppe. Er karakteren, jeg spiller, ikke med (en alt), kommer den med først.
function Groups:Post(gid, text)
	local g = ns.DB.groups[gid]
	if not g or g.left or type(text) ~= "string" or text == "" then return end
	if g.demo then
		Store(gid, { a = ns.me, n = self:NextNumber(gid, ns.me), t = Compat.Now(), x = text })
		ns.Changed("msg", gid)
		return
	end
	if not self:IsMember(g, ns.me) then
		local list, main = self:Members(g), nil
		for _, name in ipairs(list) do
			if Data:IsMine(name) then main = name end
		end
		list[#list + 1] = ns.me
		self:Update(gid, g.name, list, main)
	end
	local m = { a = ns.me, n = self:NextNumber(gid, ns.me), t = Compat.Now(), x = text:sub(1, MAX_TEXT) }
	Store(gid, m)
	if ns.Comm then ns.Comm:PushMessage(gid, m) end
	ns.Changed("msg", gid)
	return m
end

-- En besked fra et andet medlem (original eller relay). sync = kom som svar på HELLO (indhentning).
-- first = den første fra denne forfatter i afsenderens indhentning: har afsenderen intet før den, flyttes
-- bunden op, så vi ikke beder om de samme ældre beskeder igen og igen.
function Groups:Receive(gid, m, from, sync, first)
	local g = ns.DB.groups[gid]
	if not g or g.left or g.demo then return false end
	if type(m) ~= "table" or type(m.a) ~= "string" or type(m.n) ~= "number" or type(m.t) ~= "number"
		or type(m.x) ~= "string" then
		return false
	end
	if not g.members[from] then
		ns.Debug("MSG %s from non-member %s ignored", gid, from)
		return false
	end
	local author = Compat.FullName(m.a)
	if not author or not (g.members[author] or g.former[author]) then return false end
	if author ~= from and not sync then
		-- En original skal komme fra forfatteren selv; relays kommer kun som indhentning.
		ns.Debug("MSG %s: %s sent as %s, ignored", gid, from, author)
		return false
	end
	local msg = { a = author, n = math.floor(m.n), t = m.t, x = m.x:sub(1, MAX_TEXT) }
	if sync then msg.late = true end
	if sync and first then
		local have = self:Have(gid)[author] or 0
		if msg.n > have + 1 then RaiseFloor(g, author, msg.n - 1) end
	end
	if not Store(gid, msg) then return false end
	if sync and not self.catchup[gid] then self.catchup[gid] = Key(msg.a, msg.n) end
	if not Data:IsMine(author) then
		ns.Changed("incoming", "g:" .. gid, msg)
	end
	ns.Changed("msg", gid)
	return true
end

-- Hvad jeg har: { [forfatter] = højeste nr, hvor der ikke mangler noget mellem "bunden" og det }.
-- Bunden (g.floor) er det, jeg ved, at ingen sender mig igen: beskeder, jeg selv har ryddet væk, eller
-- som afsenderen ikke havde. Et hul (en tabt besked) gør, at den anden sender fra hullet og frem.
function Groups:Have(gid)
	local g = ns.DB.groups[gid]
	local floor = g and g.floor or {}
	local nums = {}
	for _, m in ipairs(ns.DB.messages[gid] or {}) do
		local list = nums[m.a]
		if not list then
			list = {}
			nums[m.a] = list
		end
		list[#list + 1] = m.n
	end
	local have = {}
	for author, f in pairs(floor) do have[author] = f end
	for author, list in pairs(nums) do
		table.sort(list)
		local high = floor[author] or 0
		for _, n in ipairs(list) do
			if n == high + 1 then high = n elseif n > high + 1 then break end
		end
		have[author] = high
	end
	return have
end

RaiseFloor = function(g, author, n)
	if not g then return end
	g.floor = g.floor or {}
	if n > (g.floor[author] or 0) then g.floor[author] = n end
end

-- Beskeder, den anden mangler ifølge deres "have" (ældste først, højst limit; resten ved næste HELLO).
function Groups:Missing(gid, have, limit)
	local out = {}
	have = type(have) == "table" and have or {}
	for _, m in ipairs(ns.DB.messages[gid] or {}) do
		if m.n > (tonumber(have[m.a]) or 0) then
			out[#out + 1] = m
			if limit and #out >= limit then break end
		end
	end
	return out
end

function Groups:IsCatchupStart(gid, m)
	return self.catchup[gid] == Key(m.a, m.n)
end
