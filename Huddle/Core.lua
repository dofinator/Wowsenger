-- Huddle – kerne: navnerum, events, udskrift, fejlsøgnings-spor.
local addonName, ns = ...

local Huddle = CreateFrame("Frame")
ns.frame = Huddle
ns.addonName = addonName

local Compat = ns.Compat
ns.VERSION = Compat.GetAddOnVersion(addonName)

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffHuddle|r: " .. msg)
end

local function DebugValue(value)
	if Compat.IsSecret(value) then return "<secret>" end
	return tostring(value)
end

-- Hvert signal gemmes i HuddleDB.trace (de seneste 200 linjer, læses i SavedVariables-filen) og skrives
-- i chatten, når /huddle debug er slået til. Aldrig beskedtekster: kun typer, navne og tal.
local TRACE_MAX = 200
function ns.Debug(msg, ...)
	local n = select("#", ...)
	local args = {}
	for i = 1, n do args[i] = DebugValue((select(i, ...))) end
	local line = msg:format(unpack(args, 1, n))
	local db = ns.DB
	if db then
		db.trace = db.trace or {}
		table.insert(db.trace, date("%m-%d %H:%M:%S ") .. line)
		while #db.trace > TRACE_MAX do table.remove(db.trace, 1) end
	end
	if ns.db and ns.db.debug then
		DEFAULT_CHAT_FRAME:AddMessage("|cff999999[Huddle debug]|r " .. line)
	end
end

-- Event-håndtering: moduler lægger funktioner i ns.events[EVENT].
ns.events = {}
ns.registered = {}

function ns.On(event, fn)
	local list = ns.events[event]
	if not list then
		list = {}
		ns.events[event] = list
		ns.registered[event] = Compat.TryRegister(Huddle, event)
	end
	table.insert(list, fn)
end

Huddle:SetScript("OnEvent", function(_, event, ...)
	local list = ns.events[event]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			ns.Debug("error in %s: %s", event, err)
			if geterrorhandler then geterrorhandler()(err) end
		end
	end
end)

-- Moduler, der skal startes efter SavedVariables er læst.
local loaders = {}
function ns.OnLoad(fn) table.insert(loaders, fn) end

ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	ns.Data:Init()
	for _, fn in ipairs(loaders) do fn() end
end)

-- Lille fælles "noget har ændret sig"-signal til UI'et (samles til én opdatering).
local listeners = {}
function ns.Listen(fn) table.insert(listeners, fn) end
function ns.Changed(what, key, extra)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, what, key, extra)
		if not ok then ns.Debug("listener error: %s", err) end
	end
end
