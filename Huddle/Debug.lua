-- Huddle – fejlsøgning og demo (så vinduet kan prøves alene, uden venner online).
local _, ns = ...

local Compat = ns.Compat
local Data = ns.Data

local Debug = {}
ns.DebugTools = Debug

local DEMO_GID = "demo:1"
local DEMO_MEMBERS = { "Anna-Demo", "Bob-Demo", "Cleo-Demo" }

-- Lokal demo-gruppe og demo-whispers. Intet sendes; gruppen er markeret demo og bliver aldrig synkroniseret.
function Debug.Demo()
	local now = Compat.Now()
	local g = { name = "Demo group", members = {}, former = {}, ver = 1, by = ns.me, created = now - 3600, demo = true }
	g.members[ns.me] = true
	for _, n in ipairs(DEMO_MEMBERS) do g.members[n] = true end
	ns.DB.groups[DEMO_GID] = g
	ns.DB.peers["Anna-Demo"] = { class = "MAGE" }
	ns.DB.peers["Bob-Demo"] = { class = "WARRIOR" }
	ns.DB.peers["Cleo-Demo"] = { class = "PRIEST" }
	ns.DB.messages[DEMO_GID] = {
		{ a = "Anna-Demo", n = 1, t = now - 3000, x = "Anyone up for Deadmines tonight?" },
		{ a = "Bob-Demo", n = 1, t = now - 2900, x = "Sure, after 20:00" },
		{ a = ns.me, n = 1, t = now - 2800, x = "I'm in" },
		{ a = "Cleo-Demo", n = 1, t = now - 600, x = "I can heal", late = true },
		{ a = "Anna-Demo", n = 2, t = now - 500, x = "Great, see you at the entrance", late = true },
	}
	ns.Groups.catchup[DEMO_GID] = "Cleo-Demo#1"
	ns.DB.whispers["Anna-Demo"] = {
		{ t = now - 1200, x = "Do you have spare Linen Cloth?" },
		{ out = true, t = now - 1100, x = "Yes, 20 in the mail" },
	}
	ns.DB.unread["g:" .. DEMO_GID] = 2
	ns.DB.unread["w:Anna-Demo"] = 1
	ns.Print("demo group and whisper added. Remove them with /huddle debug demo off.")
	ns.Window:Open()
	ns.Toast:Notify("g:" .. DEMO_GID, "Anna-Demo", "Great, see you at the entrance", true)
end

function ns.Debug_RemoveDemo()
	ns.DB.groups[DEMO_GID] = nil
	ns.DB.messages[DEMO_GID] = nil
	ns.DB.unread["g:" .. DEMO_GID] = nil
	for _, n in ipairs(DEMO_MEMBERS) do
		ns.DB.whispers[n] = nil
		ns.DB.unread["w:" .. n] = nil
		ns.DB.peers[n] = nil
	end
	ns.Print("demo removed.")
	ns.Window:Refresh()
end

function Debug.Status()
	ns.Print(("version %s, you are %s"):format(ns.VERSION, tostring(ns.me)))
	DEFAULT_CHAT_FRAME:AddMessage("  " .. Compat.Diagnostics())
	local n = 0
	for gid, g in pairs(ns.DB.groups) do
		if not g.left then
			n = n + 1
			local online = {}
			for _, name in ipairs(ns.Groups:Others(g)) do
				if ns.Comm:IsOnline(name) then online[#online + 1] = Compat.ShortName(name) end
			end
			DEFAULT_CHAT_FRAME:AddMessage(("  %s: %d members, %d messages, online: %s%s"):format(g.name,
				#ns.Groups:Members(g), #ns.Groups:Messages(gid), #online > 0 and table.concat(online, ", ") or "nobody",
				ns.Groups:Active(g) and "" or " (not active on this character)"))
		end
	end
	if n == 0 then DEFAULT_CHAT_FRAME:AddMessage("  no groups yet") end
	DEFAULT_CHAT_FRAME:AddMessage(("  waiting to send: %d"):format(ns.Comm:QueueLength()))
end
