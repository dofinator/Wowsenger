-- Huddle – alle klient-afhængige WoW-kald samles her.
-- Mål-klient: WoW Forever (Mainline-API med Midnights "secret values"). Testklient bagefter: Retail.
-- Ingen kald uden for denne fil må antage, at en værdi kan læses.
local _, ns = ...

local Compat = {}
ns.Compat = Compat

Compat.IS_MAINLINE = WOW_PROJECT_ID ~= nil and WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
Compat.IS_FOREVER = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == 18

-- En "secret value" kan vises af Blizzards UI, men en addon må ikke sammenligne, gemme eller regne med den.
function Compat.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

-- Returnerer værdien, eller nil hvis den er hemmelig.
function Compat.Safe(value)
	if Compat.IsSecret(value) then return nil end
	return value
end
local Safe = Compat.Safe

------------------------------------------------------------------------
-- Navne. Huddle bruger altid "Navn-Realm" internt (venner kan være på andre realms).
------------------------------------------------------------------------
local myRealm
function Compat.MyRealm()
	if not myRealm then
		myRealm = (GetNormalizedRealmName and Safe(GetNormalizedRealmName()))
		if not myRealm or myRealm == "" then
			myRealm = ((Safe(GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", ""))
		end
	end
	return myRealm
end

local function StripCodes(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	return text
end

-- "Anna" / "Anna-Firemaw" / ("Anna", "Fire Maw") -> "Anna-Firemaw". nil hvis navnet er hemmeligt/tomt.
function Compat.FullName(name, realm)
	name = Safe(name)
	if type(name) ~= "string" then return nil end
	name = strtrim(StripCodes(name))
	if name == "" then return nil end
	realm = Safe(realm)
	if not realm or realm == "" then
		local base, r = name:match("^(.-)%-(.+)$")
		if base and base ~= "" then name, realm = base, r end
	end
	if not realm or realm == "" then realm = Compat.MyRealm() end
	realm = realm:gsub("%s", "")
	-- Første bogstav stort, resten småt (som spillet viser navne). Kun ASCII ændres.
	name = name:sub(1, 1):upper() .. name:sub(2)
	return name .. "-" .. realm
end

-- "Anna-Spineshatter" -> "Anna" på egen realm, ellers uændret. Battle.net: "Anna#1234" -> "Anna".
function Compat.ShortName(full)
	if type(full) ~= "string" then return "?" end
	if Compat.IsBNetKey(full) then return (full:match("^(.-)#") or full) end
	local base, realm = full:match("^(.-)%-(.+)$")
	if base and realm == Compat.MyRealm() then return base end
	return full
end

function Compat.MyName()
	local ok, name = pcall(UnitName, "player")
	return Compat.FullName(ok and name or nil)
end

function Compat.MyClass()
	local ok, _, class = pcall(UnitClass, "player")
	return ok and Safe(class) or nil
end

------------------------------------------------------------------------
-- Tid
------------------------------------------------------------------------
function Compat.Now()
	local t = GetServerTime and Safe(GetServerTime())
	if type(t) == "number" and t > 0 then return t end
	return time()
end

------------------------------------------------------------------------
-- Chat
------------------------------------------------------------------------

-- Almindelig whisper. Retail/Forever har C_ChatInfo.SendChatMessage, ældre klienter kun den globale.
-- Returnerer true hvis kaldet ikke fejlede (det betyder ikke, at beskeden nåede frem).
function Compat.SendWhisper(text, target)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if not send then return false end
	return (pcall(send, text, "WHISPER", nil, target))
end

------------------------------------------------------------------------
-- Battle.net-whispers (blå tekst). Samtalen gemmes under vennens BattleTag ("Anna#1234"): den er
-- almindelig tekst, mens kontonavnet er en beskyttet |K-streng, som addons hverken må læse eller gemme.
-- Konto-id'et (bnetIDAccount) bruges kun til at sende og slås op hver gang (det kan skifte mellem sessioner).
------------------------------------------------------------------------
function Compat.IsBNetKey(key)
	return type(key) == "string" and key:find("#", 1, true) ~= nil
end

local bnetIDs = {} -- [BattleTag] = bnetIDAccount (denne session)

function Compat.BNetTag(bnetID)
	bnetID = Safe(bnetID)
	if type(bnetID) ~= "number" or bnetID <= 0 or not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then
		return nil
	end
	local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
	local tag = ok and type(info) == "table" and Safe(info.battleTag) or nil
	if type(tag) ~= "string" or not Compat.IsBNetKey(tag) then return nil end
	bnetIDs[tag] = bnetID
	return tag
end

local function FindBNetID(tag)
	if bnetIDs[tag] then return bnetIDs[tag] end
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return nil end
	local ok, n = pcall(BNGetNumFriends)
	n = ok and Safe(n) or 0
	for i = 1, n do
		local ok2, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
		if ok2 and type(info) == "table" and Safe(info.battleTag) == tag then
			local id = Safe(info.bnetAccountID)
			if type(id) == "number" then
				bnetIDs[tag] = id
				return id
			end
		end
	end
end

-- Forever/Retail: C_BattleNet.SendWhisper; Classic: BNSendWhisper. false hvis vennen ikke kan findes.
function Compat.SendBNetWhisper(tag, text)
	local id = FindBNetID(tag)
	if not id then return false end
	local send = (C_BattleNet and C_BattleNet.SendWhisper) or BNSendWhisper
	if not send then return false end
	return (pcall(send, id, text))
end

-- Chat-filter (Forever har kun ChatFrameUtil-udgaven, Classic kun den globale).
function Compat.AddMessageEventFilter(event, fn)
	if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
		ChatFrameUtil.AddMessageEventFilter(event, fn)
		return true
	elseif ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter(event, fn)
		return true
	end
	return false
end

-- Shift-klik på et item, mens vores skrivefelt har fokus: linket skal ind i det.
-- Forever/Retail: ChatFrameUtil.InsertLink, Classic: ChatEdit_InsertLink. Post-hook, ændrer intet for Blizzard.
function Compat.HookInsertLink(fn)
	if not hooksecurefunc then return false end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(link) if type(link) == "string" then fn(link) end end)
		return true
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", function(link) if type(link) == "string" then fn(link) end end)
		return true
	end
	return false
end

function Compat.Invite(name)
	local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	if invite then pcall(invite, name) end
end

-- Klik på et link i vores beskedvindue (spillerlinks, item-links).
function Compat.ItemRef(link, text, button, frame)
	if SetItemRef then pcall(SetItemRef, link, text, button, frame) end
end

-- Klassefarvet navn.
function Compat.ColorName(name, class)
	local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	local color = class and colors and colors[class]
	if not color then return name end
	if color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
	local function hex(v) return math.floor(v * 255 + 0.5) end
	return ("|cff%02x%02x%02x%s|r"):format(hex(color.r), hex(color.g), hex(color.b), name)
end

-- Kun InCombatLockdown styrer noget (lært i GuildCrafters: C_ChatInfo-lockdown-funktionerne svarer
-- "true" uden for kamp i Retail 12.1). De andre vises kun i /huddle debug.
function Compat.InCombat()
	return InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

function Compat.Diagnostics()
	local out = {}
	local function Ask(label, fn)
		if not fn then out[#out + 1] = label .. "=n/a" return end
		local ok, v = pcall(fn)
		if not ok then v = "error" elseif Compat.IsSecret(v) then v = "<secret>" end
		out[#out + 1] = label .. "=" .. tostring(v)
	end
	Ask("combat", InCombatLockdown)
	Ask("InChatMessagingLockdown", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
	Ask("AreOutgoingAddonChatMessagesRestricted", C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
	out[#out + 1] = "project=" .. tostring(WOW_PROJECT_ID)
	out[#out + 1] = "filterAPI=" .. ((ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) and "ChatFrameUtil"
		or (ChatFrame_AddMessageEventFilter and "global") or "none")
	return table.concat(out, " ")
end

-- Registrerer et event uden at fejle, hvis klienten ikke kender det (Forever kaster en fejl).
function Compat.TryRegister(frame, event)
	return (pcall(frame.RegisterEvent, frame, event))
end

------------------------------------------------------------------------
-- Kandidater til "New group": venner og guild-medlemmer (klassen med, hvis den kendes).
------------------------------------------------------------------------
function Compat.Friends()
	local out = {}
	if C_FriendList and C_FriendList.GetNumFriends then
		local ok, n = pcall(C_FriendList.GetNumFriends)
		n = ok and Safe(n) or 0
		for i = 1, n do
			local ok2, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
			if ok2 and type(info) == "table" then
				local key = Compat.FullName(info.name)
				if key then
					out[#out + 1] = { key = key, online = Safe(info.connected) and true or false,
						class = Safe(info.classTag) or Safe(info.className) }
				end
			end
		end
	elseif GetNumFriends and GetFriendInfo then
		for i = 1, GetNumFriends() do
			local name, _, class, _, connected = GetFriendInfo(i)
			local key = Compat.FullName(name)
			if key then out[#out + 1] = { key = key, online = connected and true or false } end
		end
	end
	return out
end

-- Kun online guild-medlemmer (en stor guild har hundredvis; resten skrives ind ved navn).
function Compat.OnlineGuildMembers()
	local out = {}
	if not (IsInGuild and Safe(IsInGuild())) or not GetNumGuildMembers then return out end
	local ok, n = pcall(GetNumGuildMembers)
	n = ok and Safe(n) or 0
	for i = 1, n do
		local ok2, name, _, _, _, _, _, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
		if ok2 and Safe(online) then
			local key = Compat.FullName(name)
			if key then out[#out + 1] = { key = key, online = true, class = Safe(class) } end
		end
	end
	return out
end

function Compat.GetAddOnVersion(addonName)
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return get and get(addonName, "Version") or "?"
end
