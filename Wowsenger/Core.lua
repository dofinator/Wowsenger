-- Wowsenger – kerne: navnerum, events, udskrift, fejlsøgnings-spor.
local addonName, ns = ...

local Wowsenger = CreateFrame("Frame")
ns.frame = Wowsenger
ns.addonName = addonName

local Compat = ns.Compat
ns.VERSION = Compat.GetAddOnVersion(addonName)

-- Testudgaven (WowsengerTest.toc, et link til repoet) gemmer i WowsengerTestDB, så den aldrig rører den
-- udgivne addons data. De to deler /wowsenger, addon-beskeder og vinduesnavne, så kun én må køre:
-- den, der indlæses sidst (WowsengerTest), holder sig helt i ro, hvis den anden allerede er indlæst.
ns.DB_NAME = addonName .. "DB"
ns.IS_TEST = addonName ~= "Wowsenger"
local otherCopy = ns.IS_TEST and "Wowsenger" or "WowsengerTest"
ns.inactive = Compat.IsAddOnLoaded(otherCopy)

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffWowsenger|r: " .. msg)
end

local function DebugValue(value)
	if Compat.IsSecret(value) then return "<secret>" end
	return tostring(value)
end

-- Hvert signal gemmes i WowsengerDB.trace (de seneste 200 linjer, læses i SavedVariables-filen) og skrives
-- i chatten, når /wowsenger debug er slået til. Aldrig beskedtekster: kun typer, navne og tal.
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
		DEFAULT_CHAT_FRAME:AddMessage("|cff999999[Wowsenger debug]|r " .. line)
	end
end

-- Event-håndtering: moduler lægger funktioner i ns.events[EVENT].
ns.events = {}
ns.registered = {}

function ns.On(event, fn)
	if ns.inactive then return end
	local list = ns.events[event]
	if not list then
		list = {}
		ns.events[event] = list
		ns.registered[event] = Compat.TryRegister(Wowsenger, event)
	end
	table.insert(list, fn)
end

Wowsenger:SetScript("OnEvent", function(_, event, ...)
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

if ns.inactive then
	-- Sig det én gang ved login; ellers ser det bare ud, som om addonen er død.
	Wowsenger:RegisterEvent("PLAYER_LOGIN")
	ns.events.PLAYER_LOGIN = { function()
		ns.Print("|cffff4040Not running:|r " .. otherCopy .. " is enabled too. Disable one of them in the "
			.. "AddOns list, then /reload.")
	end }
end

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
