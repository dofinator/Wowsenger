-- Huddle – /huddle (/hd). Vinduet åbnes normalt med minimap-knappen; kommandoerne er til resten.
local _, ns = ...

local function Help()
	ns.Print("commands:")
	for _, line in ipairs({
		"/huddle – open or close the Huddle window",
		"/huddle minimap – show or hide the minimap button",
		"/huddle toast – turn the new-message popup on or off",
		"/huddle toast test – show a sample popup (drag it where you want it)",
		"/huddle toast reset – put the popup back at the top of the screen",
		"/huddle sound – turn the group message sound on or off",
		"/huddle status – groups, who is online, what the game tells the addon",
		"/huddle debug – print what Huddle sends and receives",
		"/huddle debug ping <name> – check that addon messages reach someone",
		"/huddle debug demo [off] – a local demo group to try the window alone",
	}) do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
	end
end

local function OnOff(key, label)
	ns.db[key] = not ns.db[key]
	ns.Print(label .. " " .. (ns.db[key] and "on" or "off") .. ".")
end

SLASH_HUDDLE1 = "/huddle"
SLASH_HUDDLE2 = "/hd"
SlashCmdList.HUDDLE = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		ns.Window:Toggle()
	elseif cmd == "minimap" then
		ns.Minimap.Toggle()
	elseif cmd == "toast" then
		local sub = rest:lower()
		if sub == "test" then
			ns.Toast:Test()
		elseif sub == "reset" then
			ns.Toast:ResetPosition()
			ns.Print("popup moved back to the top of the screen.")
		else
			OnOff("toast", "new-message popup")
		end
	elseif cmd == "sound" then
		OnOff("sound", "group message sound")
	elseif cmd == "status" then
		ns.DebugTools.Status()
	elseif cmd == "debug" then
		local sub, arg = rest:match("^(%S*)%s*(.-)$")
		sub = (sub or ""):lower()
		if sub == "ping" and arg ~= "" then
			ns.Comm:Ping(arg)
		elseif sub == "demo" then
			if arg:lower() == "off" then ns.Debug_RemoveDemo() else ns.DebugTools.Demo() end
		else
			OnOff("debug", "debug output")
		end
	else
		Help()
	end
end
