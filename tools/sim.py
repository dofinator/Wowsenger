"""Wowsenger – simulator: den rigtige addon-kode i flere falske WoW-klienter (Lua 5.1 via lupa).

    pip install lupa
    python tools/sim.py            # alle scenarier
    python tools/sim.py 3 7        # kun scenarie 3 og 7
    python tools/sim.py -v         # vis chat-linjer ved fejl

Verden: klienter, der er online, får addon-whispers og whispers med det samme (ved næste step);
til en offline spiller svarer "serveren" med "No player named '%s' is currently playing." som i spillet.
Logout gemmer WowsengerDB, login starter en ny Lua-runtime med den gemte data (som /reload).
"""
import os
import re
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Wowsenger")
VERBOSE = "-v" in sys.argv
NOT_FOUND = "No player named '%s' is currently playing."
ALLOWED_GLOBALS = ("WowsengerDB", "WowsengerTestDB", "SLASH_WOWSENGER1", "SLASH_WOWSENGER2")


def toc_files(toc="Wowsenger.toc"):
    files = []
    with open(os.path.join(ADDON, toc), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(line.replace("\\", os.sep))
    return files


def strip(s):
    if s is None:
        return None
    s = str(s)
    s = re.sub(r"\|c[0-9a-fA-F]{8}", "", s).replace("|r", "")
    s = re.sub(r"\|H.-?\|h(.*?)\|h", r"\1", s)
    return s


def items(t):
    return list(t.items()) if t is not None else []


def values(t):
    return [v for _, v in sorted(items(t), key=lambda kv: kv[0])] if t is not None else []


class Client:
    def __init__(self, world, name, realm="Spineshatter", cls="PRIEST", db=None, account=None,
                 addons=("Wowsenger",)):
        # addons: mappenavne i indlæsningsrækkefølge, fx ("Wowsenger", "WowsengerTest") når begge er slået til.
        self.addon = addons[0]
        self.world = world
        self.name, self.realm = name, realm
        self.full = f"{name}-{realm}"
        self.account = account or self.full
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        with open(os.path.join(ROOT, "tools", "wowmock.lua"), encoding="utf-8") as f:
            self.lua.execute(f.read())
        self.mock = self.lua.globals().mock
        self.mock.now = world.now
        self.mock.player = self.lua.table_from({"name": name, "realm": realm, "class": cls})
        self.mock.guids = self.lua.table()
        if db:
            self.lua.execute(self.addon + "DB = " + db)
        self.nss = {}
        allowed = "{" + ", ".join(f"{g} = true" for g in ALLOWED_GLOBALS) + "}"
        # Hver fil kører i et miljø, der fejler ved skrivning til andre globaler end vores egne
        # (at overskrive en Blizzard-global giver taint i spillet).
        loader = self.lua.eval("""function(code, name, ns, addon)
            local allowed = %s
            local env = setmetatable({}, {
                __index = _G,
                __newindex = function(_, k, v)
                    if not allowed[k] then error("Wowsenger writes global " .. tostring(k), 2) end
                    _G[k] = v
                end,
            })
            local f = assert(loadstring(code, name))
            setfenv(f, env)
            f(addon, ns)
        end""" % allowed)
        plain = self.lua.eval("function(code, name) assert(loadstring(code, name))() end")
        for addon in addons:
            self.nss[addon] = self.load(addon, loader, plain)
        self.ns = self.nss[self.addon]
        for addon in addons:
            self.fire("ADDON_LOADED", addon)
        self.fire("PLAYER_LOGIN")
        self.fire("PLAYER_ENTERING_WORLD")

    def load(self, addon, loader, plain):
        ns = self.lua.table()
        self.mock.loadedAddons[addon] = True   # "loading" tæller som indlæst i spillet
        for rel in toc_files(addon + ".toc"):
            if rel.startswith("Libs"):
                if self.nss:
                    continue   # bibliotekerne findes kun én gang, som i spillet (LibStub)
                if rel.endswith("LibStub.lua"):
                    with open(os.path.join(ADDON, rel), encoding="utf-8") as f:
                        plain(f.read(), "@" + rel)
                    self.mock.registerLibStubs()
                elif "AceSerializer" in rel:
                    path = os.path.join(ADDON, "Libs", "AceSerializer-3.0", "AceSerializer-3.0.lua")
                    with open(path, encoding="utf-8") as f:
                        plain(f.read(), "@AceSerializer-3.0.lua")
                continue
            with open(os.path.join(ADDON, rel), encoding="utf-8") as f:
                loader(f.read(), "@" + rel, ns, addon)
        return ns

    # --- grundlæggende ---
    def fire(self, event, *args):
        self.mock.fire(event, *args)

    def call(self, obj, method, *args):
        o = self.ns[obj]
        return o[method](o, *args)

    def slash(self, text):
        self.lua.globals().SlashCmdList.WOWSENGER(text)

    def chat(self):
        return [strip(m) for m in values(self.mock.chat)]

    def sent(self):
        out = [dict(prefix=m.prefix, text=m.text, target=m.target) for m in values(self.mock.sent)]
        self.mock.sent = self.lua.table()
        return out

    def whispers_out(self):
        out = [dict(text=m.text, target=m.target) for m in values(self.mock.whispersOut)]
        self.mock.whispersOut = self.lua.table()
        return out

    def combat(self, on):
        self.mock.inCombat = on
        if not on:
            self.fire("PLAYER_REGEN_ENABLED")

    def secret(self, value):
        self.mock.secret[value] = True

    # --- data ---
    def db(self):
        return self.lua.globals()[self.addon + "DB"]

    def groups(self):
        out = {}
        for gid, g in items(self.db().groups):
            out[gid] = dict(name=g.name, members=sorted(k for k, _ in items(g.members)),
                            left=bool(g.left), ver=g.ver)
        return out

    def group_id(self, name):
        for gid, g in self.groups().items():
            if g["name"] == name:
                return gid
        return None

    def messages(self, gid):
        return [dict(a=m.a, n=m.n, x=m.x, late=bool(m.late)) for m in values(self.db().messages[gid])] \
            if self.db().messages[gid] is not None else []

    def texts(self, gid):
        return [m["x"] for m in self.messages(gid)]

    def whisper_log(self, who):
        lst = self.db().whispers[who]
        return [dict(out=bool(e.out), x=e.x, hidden=bool(e.hidden)) for e in values(lst)] if lst is not None else []

    def unread(self, conv):
        return self.db().unread[conv] or 0

    def create(self, name, members):
        t = self.lua.table_from(members)
        return self.call("Groups", "Create", name, t)

    def post(self, gid, text):
        return self.call("Groups", "Post", gid, text)

    def online(self, who):
        return bool(self.call("Comm", "IsOnline", who))

    # --- UI ---
    def open(self, conv=None):
        self.call("Window", "Open", conv)
        self.world.step(0.5)

    def lines(self):
        return [strip(l) for l in values(self.call("Window", "Lines"))]

    def list_items(self):
        out = []
        for it in values(self.call("Window", "Items")):
            if it.kind == "header":
                out.append("# " + it.text)
            elif it.kind == "new":
                out.append("+ New group")
            elif it.kind == "undo":
                out.append("undo")
            else:
                out.append(it.conv)
        return out

    def toast(self):
        if not self.call("Toast", "IsShown"):
            return None
        title, line = self.call("Toast", "Texts")
        return strip(title), strip(line)

    def menu(self, conv):
        return [it.text for it in values(self.call("Window", "MenuFor", conv))]

    def menu_click(self, conv, text):
        for it in values(self.call("Window", "MenuFor", conv)):
            if it.text == text:
                it.fn()
                return True
        return False

    def confirm(self):
        shown, text = self.lua.eval("function(ns) return ns.UI.ConfirmShown() end")(self.ns)
        return strip(text) if shown else None

    def confirm_yes(self):
        self.lua.eval("function() WowsengerConfirm.yes.scripts.OnClick(WowsengerConfirm.yes) end")()


class World:
    def __init__(self):
        self.now = 1000.0
        self.clients = {}       # full -> Client (online)
        self.saved = {}         # account -> WowsengerDB som Lua-kode
        self.loss = None        # fn(sender_full, target_full, payload_text) -> True = tabt
        self.secret_whispers = False
        self.line = 0
        self.log = []           # (fra, til, tekst) for hver leveret addon-besked
        self.bnet_ids = {}      # account -> Battle.net-konto-id

    def bnet_friends(self, a, b):
        """Gør a og b til Battle.net-venner (begge veje)."""
        for me, other in ((a, b), (b, a)):
            info = me.lua.table_from({"battleTag": other.battletag, "bnetAccountID": other.bnet_id,
                                      "accountName": "|Kq%d|k" % other.bnet_id})
            me.mock.bnet[other.bnet_id] = info
            me.mock.bnetFriends[len(me.mock.bnetFriends) + 1] = info

    def login(self, name, realm="Spineshatter", cls="PRIEST", account=None, addons=("Wowsenger",)):
        full = f"{name}-{realm}"
        acct = account or full
        c = Client(self, name, realm, cls, db=self.saved.get((acct, addons[0])), account=acct, addons=addons)
        # Battle.net: én konto pr. account, med fast id og BattleTag i simulatoren.
        if acct not in self.bnet_ids:
            self.bnet_ids[acct] = 100 + len(self.bnet_ids)
        c.bnet_id = self.bnet_ids[acct]
        c.battletag = f"{acct.split('-')[0]}#{c.bnet_id}"
        self.clients[full] = c
        self.step(0.5)
        return c

    def logout(self, c):
        self.saved[(c.account, c.addon)] = c.lua.eval("function() return mock.dump(%sDB) end" % c.addon)()
        del self.clients[c.full]

    def sender_name(self, sender, recipient):
        return sender.name if sender.realm == recipient.realm else sender.full

    def resolve(self, sender, target):
        if target is None:
            return None
        return target if "-" in target else f"{target}-{sender.realm}"

    def deliver(self):
        for _ in range(50):
            moved = False
            for c in list(self.clients.values()):
                for m in c.sent():
                    moved = True
                    full = self.resolve(c, m["target"])
                    r = self.clients.get(full)
                    if r is None:
                        c.mock.system(NOT_FOUND % m["target"])
                    elif not (self.loss and self.loss(c.full, full, m["text"])):
                        self.log.append((c.full, full, m["text"]))
                        r.mock.receive(m["prefix"], m["text"], "WHISPER", self.sender_name(c, r))
                for w in c.whispers_out():
                    moved = True
                    full = self.resolve(c, w["target"])
                    r = self.clients.get(full)
                    if r is None:
                        c.mock.system(NOT_FOUND % w["target"])
                        continue
                    self.line += 1
                    if self.secret_whispers:
                        r.secret(w["text"])
                        c.secret(w["text"])
                    guid = "Player-1-" + c.name
                    r.mock.guids[guid] = c.lua.globals().mock.player["class"]
                    r.fire("CHAT_MSG_WHISPER", w["text"], self.sender_name(c, r), "", "", "", "", 0, 0, "", 0,
                           self.line, guid)
                    c.fire("CHAT_MSG_WHISPER_INFORM", w["text"], self.sender_name(r, c), "", "", "", "", 0, 0, "",
                           0, self.line, "Player-1-" + r.name)
                for m in values(c.mock.bnOut):
                    moved = True
                    r = next((x for x in self.clients.values() if x.bnet_id == m.id), None)
                    if r is None:
                        continue
                    self.line += 1
                    if self.secret_whispers:
                        r.secret(m.text)
                        c.secret(m.text)
                    r.fire("CHAT_MSG_BN_WHISPER", m.text, "|Kq%d|k" % c.bnet_id, "", "", "", "", 0, 0, "", 0,
                           self.line, "", c.bnet_id)
                    c.fire("CHAT_MSG_BN_WHISPER_INFORM", m.text, "|Kq%d|k" % r.bnet_id, "", "", "", "", 0, 0, "",
                           0, self.line, "", r.bnet_id)
                c.mock.bnOut = c.lua.table()
            if not moved:
                return

    def step(self, seconds, dt=0.5):
        t = 0.0
        while t < seconds - 1e-9:
            d = min(dt, seconds - t)
            self.now += d
            for c in list(self.clients.values()):
                c.mock.advance(d)
            self.deliver()
            t += d


# ---------------------------------------------------------------------------
checks = 0
failures = []
current = None


def check(cond, msg, client=None):
    global checks
    checks += 1
    if not cond:
        failures.append(f"[{current}] {msg}")
        if VERBOSE and client is not None:
            print("    chat:", client.chat()[-8:])


SCENARIOS = []


def scenario(name):
    def deco(fn):
        SCENARIOS.append((name, fn))
        return fn
    return deco


def trio():
    w = World()
    a = w.login("Anna", cls="MAGE")
    b = w.login("Bob", cls="WARRIOR")
    c = w.login("Cleo", "Firemaw")
    w.step(6)
    return w, a, b, c


# ---------------------------------------------------------------------------
@scenario("1. gruppe oprettes, alle online får den og beskeder; ulæst og toast hos modtageren")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(1)
    check(b.groups().get(gid, {}).get("name") == "Raid group", "Bob har gruppen", b)
    check(c.groups().get(gid, {}).get("members") == ["Anna-Spineshatter", "Bob-Spineshatter", "Cleo-Firemaw"],
          "Cleo (anden realm) har gruppen med alle tre", c)
    check(any("added to the group Raid group" in l for l in b.chat()), "Bob får besked om, at han er tilføjet", b)
    w.step(6)  # HELLO-runden ved login er færdig, alle kender hinanden som online
    a.post(gid, "Tuesday 20:00?")
    w.step(1)
    check(b.texts(gid) == ["Tuesday 20:00?"], "Bob har beskeden", b)
    check(c.texts(gid) == ["Tuesday 20:00?"], "Cleo har beskeden", c)
    check(b.unread("g:" + gid) == 1, "ulæst = 1 hos Bob")
    check(a.unread("g:" + gid) == 0, "egen besked er ikke ulæst")
    t = b.toast()
    check(t is not None and t[0] == "Raid group" and t[1] == "Anna: Tuesday 20:00?", f"toast hos Bob: {t}")
    check(a.toast() is None, "ingen toast for egen besked")
    b.open("g:" + gid)
    check(b.unread("g:" + gid) == 0, "åbnet samtale = ikke ulæst")
    check(any(l.endswith("Anna: Tuesday 20:00?") for l in b.lines()), f"vinduet viser beskeden: {b.lines()}")
    b.call("Window", "Type", "works for me")
    w.step(1)
    check(a.texts(gid) == ["Tuesday 20:00?", "works for me"], "Anna får Bobs svar skrevet i vinduet", a)
    check(any(l.endswith("You: works for me") for l in b.lines()), "egen linje står som You")


@scenario("2. offline-ven får beskederne ved login via et andet medlem (forfatteren er offline)")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(6)
    w.logout(c)
    w.step(1)
    a.post(gid, "one")
    a.post(gid, "two")
    w.step(1)
    check(b.texts(gid) == ["one", "two"], "Bob har begge", b)
    w.logout(a)
    w.step(1)
    c = w.login("Cleo", "Firemaw")
    w.step(8)
    check(c.texts(gid) == ["one", "two"], f"Cleo fik dem fra Bob: {c.texts(gid)}", c)
    check(all(m["late"] for m in c.messages(gid)), "markeret som indhentet")
    check(not any("No player named" in l for l in c.chat()), "fejlbeskeden om Anna (offline) er skjult", c)
    check(c.unread("g:" + gid) == 2, "2 ulæste hos Cleo")
    c.open("g:" + gid)
    lines = c.lines()
    check("-- While you were offline --" in lines, f"skillelinje vises: {lines}")
    check(lines.index("-- While you were offline --") < [i for i, l in enumerate(lines) if l.endswith("one")][0],
          "skillelinjen står før de indhentede beskeder")


@scenario("3. tilføjet mens offline: får gruppen og historikken, når en anden kommer online")
def _():
    w = World()
    a = w.login("Anna")
    w.step(6)
    gid = a.create("Alts", ["Dora-Spineshatter"])
    a.post(gid, "hello Dora")
    w.step(2)
    check(not any("No player named" in l for l in a.chat()), "ingen fejlbesked om Dora i Annas chat", a)
    d = w.login("Dora")
    w.step(6)
    check(gid not in d.groups(), "Dora kender ikke gruppen endnu (ingen fælles gruppe at hilse på)")
    w.step(300)
    check(d.groups().get(gid, {}).get("name") == "Alts", "Annas faste runde finder Dora (mangler versionen)", d)
    check(d.texts(gid) == ["hello Dora"], "og historikken kommer med", d)
    # Når Dora har bekræftet, holder Anna op med at pinge hende, hvis hun går offline.
    w.logout(d)
    w.step(1200 + 300)
    a.sent()
    w.step(300)
    check(not any(m["target"].startswith("Dora") for m in a.sent()), "ingen pings til en offline ven, der har det hele")


@scenario("4. ven der kommer online (vennelisten/guild-beskeden) får HELLO med det samme")
def _():
    w = World()
    a = w.login("Anna")
    w.step(6)
    gid = a.create("Alts", ["Dora-Spineshatter"])
    w.step(2)
    d = w.login("Dora")
    a.mock.system("|Hplayer:Dora-Spineshatter|h[Dora]|h has come online.")
    w.step(8)
    check(gid in d.groups(), "Dora har gruppen få sekunder efter, hun kom online", d)


@scenario("5. ikke-medlemmer og forfalskede afsendere afvises; dubletter tælles én gang")
def _():
    w, a, b, c = trio()
    e = w.login("Evil")
    w.step(6)
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    w.step(6)
    # Beskederne skrives som Lua-literaler og serialiseres med den rigtige AceSerializer.
    msg = e.lua.eval("function(s) return LibStub('AceSerializer-3.0'):Serialize(loadstring('return ' .. s)()) end")
    fake = msg('{ k = "M", g = %r, m = { a = "Evil-Spineshatter", n = 1, t = 5, x = "spam" } }' % gid)
    b.mock.receive("Wowsenger1", fake, "WHISPER", "Evil")
    check(b.texts(gid) == [], "besked fra ikke-medlem afvist")
    forged = msg('{ k = "M", g = %r, m = { a = "Anna-Spineshatter", n = 9, t = 5, x = "forged" } }' % gid)
    b.mock.receive("Wowsenger1", forged, "WHISPER", "Evil")
    check(b.texts(gid) == [], "ikke-medlem kan ikke sende i et medlems navn")
    group = msg('{ k = "G", d = { id = %r, name = "Hacked", m = { "Evil-Spineshatter", "Bob-Spineshatter" },'
                ' v = 9999999999, by = "Evil" } }' % gid)
    b.mock.receive("Wowsenger1", group, "WHISPER", "Evil")
    check(b.groups()[gid]["name"] == "Raid group", "ikke-medlem kan ikke ændre gruppen")
    forged2 = msg('{ k = "M", g = %r, m = { a = "Anna-Spineshatter", n = 7, t = 5, x = "fake anna" } }' % gid)
    a_name = "Bob"  # et medlem, der ikke er forfatteren, uden indhentnings-flag
    c_like = msg('{ k = "M", g = %r, m = { a = "Bob-Spineshatter", n = 7, t = 5, x = "fake bob" } }' % gid)
    a.mock.receive("Wowsenger1", c_like, "WHISPER", "Cleo-Firemaw")
    check("fake bob" not in a.texts(gid), "medlem uden for gruppen kan ikke skrive i Bobs navn")
    b.mock.receive("Wowsenger1", forged2, "WHISPER", a_name)
    a.post(gid, "real")
    w.step(1)
    raw = msg('{ k = "M", g = %r, m = { a = "Anna-Spineshatter", n = 1, t = 5, x = "real" } }' % gid)
    b.mock.receive("Wowsenger1", raw, "WHISPER", "Anna")
    check(b.texts(gid) == ["real"], f"samme besked to gange = én: {b.texts(gid)}")
    # Et medlem må ikke sende en "original" i et andet medlems navn (kun indhentning må relaye).
    gid2 = a.create("Three", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(2)
    as_anna = msg('{ k = "M", g = %r, m = { a = "Anna-Spineshatter", n = 5, t = 5, x = "not anna" } }' % gid2)
    c.mock.receive("Wowsenger1", as_anna, "WHISPER", "Bob-Spineshatter")
    check("not anna" not in c.texts(gid2), "medlem kan ikke skrive som et andet medlem uden indhentning")


@scenario("6. fjernet medlem: får besked, gruppen forsvinder, kan ikke skrive mere")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(6)
    a.call("Groups", "Update", gid, "Raid group", a.lua.table_from(["Anna-Spineshatter", "Bob-Spineshatter"]))
    w.step(1)
    check(c.groups()[gid]["left"], "Cleo er ude", c)
    check(any("no longer in Raid group" in l for l in c.chat()), "Cleo får det at vide", c)
    check(b.groups()[gid]["members"] == ["Anna-Spineshatter", "Bob-Spineshatter"], "Bob ser den nye liste", b)
    c.open()
    check("g:" + gid not in c.list_items(), "gruppen står ikke i Cleos liste")
    check(c.post(gid, "still here?") is None, "Cleo kan ikke skrive i gruppen")
    a.post(gid, "secret plans")
    w.step(1)
    check("secret plans" not in c.texts(gid), "Cleo får ikke nye beskeder")


@scenario("7. forlad gruppe via menu + bekræft; de andre ser det")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(6)
    b.open("g:" + gid)
    check(b.menu("g:" + gid) == ["Edit group...", "Leave group"], f"menu: {b.menu('g:' + gid)}")
    b.menu_click("g:" + gid, "Leave group")
    check(b.confirm() is not None and "Leave Raid group?" in b.confirm(), f"bekræft-boks: {b.confirm()}")
    b.confirm_yes()
    w.step(1)
    check(b.groups()[gid]["left"], "Bob er ude")
    check(a.groups()[gid]["members"] == ["Anna-Spineshatter", "Cleo-Firemaw"], "Anna ser det", a)
    check(c.groups()[gid]["members"] == ["Anna-Spineshatter", "Cleo-Firemaw"], "Cleo ser det", c)


@scenario("8. i kamp: intet sendes, alt kommer bagefter i rækkefølge")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    w.step(6)
    a.combat(True)
    a.post(gid, "first")
    a.post(gid, "second")
    w.step(2)
    check(b.texts(gid) == [], "intet i kamp")
    a.combat(False)
    w.step(1)
    check(b.texts(gid) == ["first", "second"], f"bagefter i rækkefølge: {b.texts(gid)}")
    w.step(6)  # den gamle toast er væk
    b.combat(True)
    a.post(gid, "third")
    w.step(1)
    check(b.toast() is None, "ingen toast i kamp")
    b.combat(False)
    w.step(0.5)
    check(b.toast() is not None and b.toast()[1] == "1 new message", f"samlet toast efter kampen: {b.toast()}")


@scenario("9. 1:1-whispers: gemmes begge veje, ulæst og toast; secret = grå markering")
def _():
    w, a, b, c = trio()
    a.call("Whispers", "Send", "Bob-Spineshatter", "got linen?")
    w.step(1)
    check(b.whisper_log("Anna-Spineshatter") == [dict(out=False, x="got linen?", hidden=False)], "Bob har den", b)
    check(a.whisper_log("Bob-Spineshatter") == [dict(out=True, x="got linen?", hidden=False)], "Anna har kopien", a)
    check(b.unread("w:Anna-Spineshatter") == 1, "ulæst hos Bob")
    check(b.toast() == ("Anna", "Anna: got linen?"), f"toast: {b.toast()}")
    b.open("w:Anna-Spineshatter")
    b.call("Window", "Type", "20 in the mail")
    w.step(1)
    check(a.whisper_log("Bob-Spineshatter")[-1] == dict(out=False, x="20 in the mail", hidden=False), "svar", a)
    w.secret_whispers = True
    a.call("Whispers", "Send", "Bob-Spineshatter", "boss pull now")
    w.step(1)
    last = b.whisper_log("Anna-Spineshatter")[-1]
    check(last["hidden"] and last["x"] is None, f"secret tekst gemmes ikke: {last}")
    check(any("hidden during an encounter" in l for l in b.lines()), "vinduet viser markeringen")


@scenario("10. fejlbesked skjules kun for vores egne addon-beskeder")
def _():
    w = World()
    a = w.login("Anna")
    w.step(6)
    a.mock.system(NOT_FOUND % "Zed")
    check(any("No player named 'Zed'" in l for l in a.chat()), "fremmed fejlbesked vises")
    gid = a.create("Alts", ["Dora-Spineshatter"])
    w.step(1)
    check(not any("Dora" in l and "No player" in l for l in a.chat()), "egen ping-fejl skjult")
    a.call("Whispers", "Send", "Dora-Spineshatter", "are you there?")
    w.step(1)
    check(any("No player named 'Dora-Spineshatter'" in l for l in a.chat()),
          "egen whisper til offline ven viser fejlen, selv lige efter et ping", a)


@scenario("11. tabt besked fyldes ud ved næste HELLO")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    w.step(6)
    w.loss = lambda s, t, text: s.startswith("Anna") and "lost" in text
    a.post(gid, "lost")
    a.post(gid, "kept")
    w.step(1)
    check(b.texts(gid) == ["kept"], f"Bob mangler den tabte: {b.texts(gid)}")
    w.loss = None
    w.step(300)
    check(b.texts(gid) == ["lost", "kept"], f"hullet fyldt: {b.texts(gid)}")


@scenario("12. egen alt: samme konto, gruppen ses, at skrive tilføjer alten")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    a.post(gid, "from main")
    w.step(6)
    w.logout(a)
    alt = w.login("Annalt", account="Anna-Spineshatter")
    w.step(6)
    check(gid in alt.groups(), "alten ser gruppen (kontoens data)")
    alt.open("g:" + gid)
    check(any(l.endswith("You: from main") for l in alt.lines()), f"mainens besked står som You: {alt.lines()}")
    alt.post(gid, "from alt")
    w.step(2)
    check("Annalt-Spineshatter" in b.groups()[gid]["members"], "Bob ser alten som medlem", b)
    check(b.texts(gid)[-1] == "from alt", "Bob har altens besked", b)


@scenario("13. samtidige ændringer ender ens hos alle")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(6)
    a.call("Groups", "Update", gid, "Name A", None)
    b.call("Groups", "Update", gid, "Name B", None)
    w.step(2)
    w.step(300)
    names = {x.groups()[gid]["name"] for x in (a, b, c)}
    vers = {x.groups()[gid]["ver"] for x in (a, b, c)}
    check(len(names) == 1 and len(vers) == 1, f"samme navn/version: {names} {vers}")


@scenario("14. New group-dialog: kandidater, fejl, opret")
def _():
    w, a, b, c = trio()
    a.mock.friends = a.lua.table_from([a.lua.table_from({"name": "Bob", "connected": True}),
                                       a.lua.table_from({"name": "Zed-Firemaw", "connected": False})])
    a.call("Whispers", "Send", "Cleo-Firemaw", "hi")
    w.step(1)
    a.open()
    check(a.list_items() == ["# Groups", "+ New group", "# People", "w:Cleo-Firemaw"], f"liste: {a.list_items()}")
    a.call("NewGroup", "Open", None)
    keys = [cand.key for cand in values(a.call("NewGroup", "Candidates"))]
    check(set(keys) == {"Bob-Spineshatter", "Zed-Firemaw", "Cleo-Firemaw"}, f"kandidater: {keys}")
    f = a.call("NewGroup", "Frame")
    a.call("NewGroup", "Submit")
    check(strip(f.error.text) == "Enter a name for the group.", f"fejl uden navn: {f.error.text}")
    f.name.SetText(f.name, "Raid group")
    a.call("NewGroup", "Submit")
    check(strip(f.error.text) == "Pick at least one member.", "fejl uden medlemmer")
    f.add.SetText(f.add, "bad name 1")
    a.call("NewGroup", "AddByName")
    check("character name" in strip(f.error.text), "ugyldigt navn afvises")
    f.add.SetText(f.add, "Dora")
    a.call("NewGroup", "AddByName")
    keys = {cand.key: bool(cand.checked) for cand in values(a.call("NewGroup", "Candidates"))}
    check(keys.get("Dora-Spineshatter") is True, "tilføjet ved navn og krydset af")
    a.call("NewGroup", "Submit")
    w.step(1)
    gid = a.group_id("Raid group")
    check(gid is not None and a.groups()[gid]["members"] == ["Anna-Spineshatter", "Dora-Spineshatter"],
          f"gruppen oprettet: {a.groups()}")
    check(not a.call("NewGroup", "IsShown") and a.call("Window", "Selected") == "g:" + gid, "dialog lukket, gruppe valgt")
    a.call("NewGroup", "Open", gid)
    check(strip(f.title.text) == "Edit group" and strip(f.ok.text) == "Save", "redigering har sin egen titel")


@scenario("15. demo: intet sendes, kan fjernes")
def _():
    w = World()
    a = w.login("Anna")
    w.step(6)
    a.sent()
    a.slash("debug demo")
    w.step(1)
    check("demo:1" in a.groups(), "demo-gruppe findes")
    a.open("g:demo:1")
    a.call("Window", "Type", "test")
    w.step(1)
    check(a.sent() == [], "intet sendt fra demo")
    check(a.texts("demo:1")[-1] == "test", "kan skrive lokalt")
    check("-- While you were offline --" in a.lines(), "demo viser skillelinjen")
    a.slash("debug demo off")
    check("demo:1" not in a.groups(), "demo fjernet")


@scenario("16. historik begrænses til 500 pr. gruppe, også efter nummerering videre")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    w.step(6)
    for i in range(520):
        a.post(gid, f"m{i}")
    w.step(60)
    check(len(a.messages(gid)) == 500, "500 hos Anna")
    check(len(b.messages(gid)) == 500 and b.texts(gid)[-1] == "m519", f"Bob: {len(b.messages(gid))}")
    a.post(gid, "after")
    w.step(1)
    check(a.messages(gid)[-1]["n"] == 521 and b.texts(gid)[-1] == "after", "nummereringen fortsætter")


@scenario("17. kun tilladte globaler, ingen Blizzard-popups; .toc dækker alle filer")
def _():
    w = World()
    a = w.login("Anna")  # loaderen fejler allerede, hvis en fil skriver en anden global
    a.slash("debug demo")
    a.open("g:demo:1")
    a.menu_click("g:demo:1", "Remove demo group")
    check(True, "loaded without writing foreign globals")
    listed = {os.path.normpath(f) for f in toc_files() if not f.startswith("Libs")}
    on_disk = set()
    for root, _, files in os.walk(ADDON):
        if "Libs" in root:
            continue
        for fn in files:
            if fn.endswith(".lua"):
                on_disk.add(os.path.normpath(os.path.relpath(os.path.join(root, fn), ADDON)))
    check(listed == on_disk, f"toc vs filer: {listed ^ on_disk}")


@scenario("23. toasten: øverst i midten over action bars, kan trækkes, pladsen huskes")
def _():
    w = World()
    a = w.login("Anna")
    w.step(6)
    a.slash("toast test")
    t = a.lua.globals().WowsengerToast
    check(a.toast() is not None, "prøve-toast vises")
    check(list(a.call("Toast", "Point"))[:3] == ["TOP", t.points[1][2], "TOP"] or
          (t.points[1][1] == "TOP" and t.points[1][3] == "TOP"), f"standardplads øverst i midten: {list(t.points[1].values())}")
    check(t.strata == "FULLSCREEN_DIALOG", f"over action bars: {t.strata}")
    t.scripts.OnDragStart(t)
    t.ClearAllPoints(t)
    t.SetPoint(t, "CENTER", a.lua.globals().UIParent, "CENTER", 200, 50)
    t.scripts.OnDragStop(t)
    t.scripts.OnClick(t, "LeftButton")      # spillets klik, når man slipper efter træk
    check(a.toast() is not None and not a.call("Window", "IsShown"), "træk åbner ikke vinduet og lukker ikke toasten")
    pos = a.db().settings.toastPos
    check(pos is not None and pos.point == "CENTER" and pos.x == 200, "pladsen gemmes")
    w.step(1)
    t.scripts.OnClick(t, "LeftButton")
    check(a.toast() is None and not a.call("Window", "IsShown"), "klik på prøve-toasten lukker den bare")
    w.logout(a)
    a = w.login("Anna")
    w.step(6)
    a.slash("toast test")
    t = a.lua.globals().WowsengerToast
    check(t.points[1][1] == "CENTER" and t.points[1][4] == 200, "pladsen huskes efter login")
    a.slash("toast reset")
    check(t.points[1][1] == "TOP" and a.db().settings.toastPos is None, "reset sætter den øverst igen")


@scenario("24. udgivelse: CHANGELOG passer til versionen, pakken indeholder kun addonen")
def _():
    toc = open(os.path.join(ADDON, "Wowsenger.toc"), encoding="utf-8").read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    first = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").readline().strip()
    check(first == f"# Wowsenger {version}", f"CHANGELOG starter med '# Wowsenger {version}': {first!r}")
    check(re.search(r"^## X-Curse-Project-ID:\s*\d+", toc, re.M) is not None, "CurseForge-projekt-id i .toc")
    pkg = open(os.path.join(ROOT, ".pkgmeta"), encoding="utf-8").read()
    for name in ("tools", "assets", "SPEC.md", "CLAUDE.md"):
        check(f"  - {name}" in pkg, f".pkgmeta udelader {name}")


@scenario("25. testudgaven WowsengerTest: egne data, og kun én kopi kører ad gangen")
def _():
    def toc(name):
        return open(os.path.join(ADDON, name), encoding="utf-8").read()

    def head(text, key):
        m = re.search(r"^## %s:.*$" % key, text, re.M)
        return m.group(0) if m else None

    def body(text):
        return [l for l in text.splitlines() if l.strip() and not l.startswith("#")]
    main, test = toc("Wowsenger.toc"), toc("WowsengerTest.toc")
    check(body(main) == body(test), "WowsengerTest.toc lister de samme filer som Wowsenger.toc")
    for key in ("Interface", "Version", "IconTexture"):
        check(head(main, key) == head(test, key), f"samme {key} i begge .toc ({head(test, key)})")
    check(head(test, "SavedVariables") == "## SavedVariables: WowsengerTestDB", "testudgaven gemmer i WowsengerTestDB")
    check("[TEST]" in (head(test, "Title") or ""), "testudgaven hedder [TEST] på AddOns-listen")
    check("  - Wowsenger/WowsengerTest.toc" in toc(os.path.join("..", ".pkgmeta")), "WowsengerTest.toc kommer ikke med i pakken")

    # Testudgaven alene: virker som den rigtige, men med sine egne data.
    w = World()
    a = w.login("Anna", addons=("WowsengerTest",))
    b = w.login("Bob")
    w.step(6)
    gid = a.create("Test", ["Bob-Spineshatter"])
    w.step(1)
    a.post(gid, "hej fra testudgaven")
    w.step(1)
    check(b.texts(gid) == ["hej fra testudgaven"], "testudgaven taler med den udgivne addon")
    g = a.lua.globals()
    check(g.WowsengerTestDB is not None and g.WowsengerDB is None, "testudgaven bruger WowsengerTestDB og rører ikke WowsengerDB")
    w.logout(a)
    a = w.login("Anna", addons=("WowsengerTest",))
    check(a.texts(gid) == ["hej fra testudgaven"], "testudgavens data huskes efter login")
    a2 = World().login("Anna")
    check(a2.groups() == {}, "den udgivne addon ser ikke testudgavens grupper")

    # Begge slået til: Wowsenger indlæses først og kører; WowsengerTest holder sig i ro og siger det.
    w = World()
    c = w.login("Cleo", addons=("Wowsenger", "WowsengerTest"))
    test_ns = c.nss["WowsengerTest"]
    check(test_ns.inactive is True and not c.ns.inactive, "kun den udgivne kopi kører")
    check(c.lua.globals().WowsengerTestDB is None, "den inaktive kopi laver ingen gemte data")
    check(any("Not running" in l and "Wowsenger is enabled too" in l for l in c.chat()), f"besked i chatten: {c.chat()}")
    c.slash("debug demo")
    check(c.call("Groups", "Get", "demo:1") is not None, "/wowsenger er den udgivne kopis")
    check(test_ns.DB is None, "den inaktive kopi læste aldrig data")


@scenario("18. ukendte events (Forever kaster fejl) stopper ikke addonen")
def _():
    w = World()
    orig = Client.__init__

    def init(self, *a, **k):
        orig(self, *a, **k)
    a = w.login("Anna")
    a.mock.unknownEvents = a.lua.table_from({"CHAT_MSG_WHISPER_INFORM": True})
    reg = a.lua.eval("function(ns) return ns.Compat.TryRegister(CreateFrame('Frame'), 'CHAT_MSG_WHISPER_INFORM') end")
    check(reg(a.ns) is False, "TryRegister svarer false i stedet for at fejle")


@scenario("19. minimap-tooltip viser ulæste; /wowsenger åbner og lukker")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    w.step(6)
    a.post(gid, "ping")
    w.step(1)
    tip = b.lua.globals().GameTooltip
    tip.SetOwner(tip)
    b.ns.Minimap.Tooltip(tip)
    lines = [strip(l) for l in values(tip.lines)]
    check("Raid group | 1 new" in lines, f"tooltip: {lines}")
    b.slash("")
    check(b.call("Window", "IsShown"), "/wowsenger åbner")
    b.slash("")
    check(not b.call("Window", "IsShown"), "/wowsenger lukker")


@scenario("20. alt-indmelding: kun præcis 'afsenderen kommer med', aldrig en fjernet eller med falsk main")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter", "Cleo-Firemaw"])
    w.step(6)
    a.call("Groups", "Update", gid, "Raid group", a.lua.table_from(["Anna-Spineshatter", "Bob-Spineshatter"]))
    w.step(1)
    ser = c.lua.eval("function(s) return LibStub('AceSerializer-3.0'):Serialize(loadstring('return ' .. s)()) end")
    ver = b.groups()[gid]["ver"] + 10
    rejoin = ser('{ k = "G", j = "Anna-Spineshatter", d = { id = %r, name = "Raid group", v = %d, by = "Cleo-Firemaw",'
                 ' m = { "Anna-Spineshatter", "Bob-Spineshatter", "Cleo-Firemaw" } } }' % (gid, ver))
    b.mock.receive("Wowsenger1", rejoin, "WHISPER", "Cleo-Firemaw")
    check("Cleo-Firemaw" not in b.groups()[gid]["members"], "fjernet medlem kan ikke melde sig ind som alt")
    e = w.login("Evil")
    grab = ser('{ k = "G", j = "Anna-Spineshatter", d = { id = %r, name = "Mine", v = %d, by = "Evil",'
               ' m = { "Evil-Spineshatter" } } }' % (gid, ver))
    b.mock.receive("Wowsenger1", grab, "WHISPER", "Evil")
    check(b.groups()[gid]["members"] == ["Anna-Spineshatter", "Bob-Spineshatter"], "alt kan ikke fjerne andre")
    fake_main = ser('{ k = "G", j = "Zed-Spineshatter", d = { id = %r, name = "Raid group", v = %d, by = "Evil",'
                    ' m = { "Anna-Spineshatter", "Bob-Spineshatter", "Evil-Spineshatter" } } }' % (gid, ver))
    b.mock.receive("Wowsenger1", fake_main, "WHISPER", "Evil")
    check("Evil-Spineshatter" not in b.groups()[gid]["members"], "main skal være medlem")


@scenario("21. sent medlem efter oprydning: indhentning i bidder, og den kører ikke i ring")
def _():
    w, a, b, c = trio()
    gid = a.create("Raid group", ["Bob-Spineshatter"])
    w.step(6)
    w.logout(b)
    for i in range(520):
        a.post(gid, f"m{i}")
    a.call("Groups", "Update", gid, "Raid group",
           a.lua.table_from(["Anna-Spineshatter", "Bob-Spineshatter", "Cleo-Firemaw"]))
    w.step(2)
    check(0 < len(c.messages(gid)) <= 100, f"første bid er højst 100: {len(c.messages(gid))}")
    w.step(300 * 5)
    check(len(c.messages(gid)) == 500 and c.texts(gid)[-1] == "m519", f"Cleo har alle 500: {len(c.messages(gid))}")
    w.log = []
    w.step(300 * 2)
    m_count = sum(1 for (_, _, text) in w.log if "^Sk^SM" in text)
    check(m_count == 0, f"når alle har alt, sendes ingen beskeder igen: {m_count}")
    b = w.login("Bob")
    w.step(300 * 6)
    check(len(b.messages(gid)) == 500, f"Bob kom tilbage og fik de 500: {len(b.messages(gid))}")


@scenario("22. Battle.net-whispers (blå): gemmes under BattleTag, svar fra vinduet, ikke i New group")
def _():
    w, a, b, c = trio()
    w.bnet_friends(a, b)
    a.call("Whispers", "Send", b.battletag, "hi from bnet")
    w.step(1)
    conv = "w:" + a.battletag
    check(b.whisper_log(a.battletag) == [dict(out=False, x="hi from bnet", hidden=False)], "Bob har den", b)
    check(a.whisper_log(b.battletag) == [dict(out=True, x="hi from bnet", hidden=False)], "Anna har kopien", a)
    check(b.unread(conv) == 1, "ulæst hos Bob")
    check(b.toast() == ("Anna", "Anna: hi from bnet"), f"toast: {b.toast()}")
    b.open(conv)
    check(b.call("Window", "Header")[1] == "Battle.net whisper", f"overskrift: {b.call('Window', 'Header')}")
    check(b.menu(conv) == ["Delete conversation"], f"menu uden Invite: {b.menu(conv)}")
    b.call("Window", "Type", "hey back")
    w.step(1)
    check(a.whisper_log(b.battletag)[-1] == dict(out=False, x="hey back", hidden=False), "svar fra vinduet", a)
    check(any(l.endswith("You: hey back") for l in b.lines()), f"egen linje: {b.lines()}")
    b.call("NewGroup", "Open", None)
    keys = [cand.key for cand in values(b.call("NewGroup", "Candidates"))]
    check(not any("#" in k for k in keys), f"BattleTags er ikke gruppe-kandidater: {keys}")
    # Ukendt konto (ingen BattleTag at læse): ignoreres i stedet for at gemme en |K-streng.
    b.fire("CHAT_MSG_BN_WHISPER", "who?", "|Kq999|k", "", "", "", "", 0, 0, "", 0, 1, "", 999)
    check(not any("Kq" in k for k, _ in items(b.db().whispers)), "intet gemt under et beskyttet navn")
    # Ikke på vennelisten: kan ikke sendes, og spilleren får det at vide.
    c.call("Whispers", "Open", "Zed#1")
    c.open("w:Zed#1")
    c.call("Window", "Type", "hello?")
    check(any("could not find Zed#1" in l for l in c.chat()), f"besked i chatten: {c.chat()[-2:]}")
    w.secret_whispers = True
    a.call("Whispers", "Send", b.battletag, "boss now")
    w.step(1)
    last = b.whisper_log(a.battletag)[-1]
    check(last["hidden"] and last["x"] is None, f"secret tekst gemmes ikke: {last}")


@scenario("26. lettere at bruge: x sletter + Undo, fold sammen til titellinje, træk større, markør i feltet")
def _():
    w = World()
    a = w.login("Anna")
    me = "Anna-Spineshatter"
    line = [0]

    def whisper(who, text):
        line[0] += 1
        a.fire("CHAT_MSG_WHISPER", text, who, "", "", "", "", 0, 0, "", 0, line[0], "Player-1-" + who)
        w.step(0.2)

    for who in ("Bob", "Cleo", "Dan"):
        whisper(who, "hi from " + who)
    bob, cleo, dan = ("w:%s-Spineshatter" % n for n in ("Bob", "Cleo", "Dan"))

    def row_for(conv):
        rows, visible = a.call("Window", "Rows")
        for i in range(1, visible + 1):
            r = rows[i]
            if r is not None and r.item is not None and r.item.conv == conv:
                return r
        return None

    def undo_row():
        rows, visible = a.call("Window", "Rows")
        for i in range(1, visible + 1):
            r = rows[i]
            if r is not None and r.item is not None and r.item.kind == "undo":
                return r
        return None

    # Markør i skrivefeltet: når man klikker på en samtale i listen, og når toasten åbner en.
    a.open(bob)
    check(a.call("Window", "InputFocused"), "Open(samtale) sætter markøren i feltet")
    a.mock.focus = None
    r = row_for(cleo)
    r.Click(r, "LeftButton")
    check(a.call("Window", "Selected") == cleo, "klik vælger samtalen")
    check(a.call("Window", "InputFocused"), "klik på en samtale sætter markøren i feltet")

    # x kun på person-rækker, kun mens musen er over.
    r = row_for(dan)
    check(not r["del"].shown, "x skjult uden mus")
    r.Enter(r)
    check(r["del"].shown and not r.badge.shown, "x vises (og ulæst-tallet skjules) ved hover")
    r.Leave(r)
    check(not r["del"].shown and r.badge.shown, "x væk igen, når musen går")
    rows, visible = a.call("Window", "Rows")
    hdr = rows[1]
    hdr.Enter(hdr)
    check(not hdr["del"].shown, "intet x på overskriften 'Groups'")
    hdr.Leave(hdr)

    # Slet Dan med x'et (han har 1 ulæst): væk med det samme, ingen bekræftelse, Undo står i listen.
    check(a.unread(dan) == 1, "Dan har 1 ulæst")
    r = row_for(dan)
    r.Enter(r)
    d = r["del"]
    d.Click(d)
    check(a.db().whispers["Dan-Spineshatter"] is None, "Dans samtale slettet")
    check(a.confirm() is None, "ingen bekræftelse")
    check(dan not in a.list_items() and a.list_items()[-1] == "undo", f"liste: {a.list_items()}")
    check(a.unread(dan) == 0, "ulæst væk med samtalen")
    check("Deleted Dan." in strip(undo_row().label.text), f"undo-tekst: {strip(undo_row().label.text)}")
    # Slet Cleo (den valgte) via højreklik-menuen: også uden bekræftelse; Undo samler begge.
    a.menu_click(cleo, "Delete conversation")
    check(a.confirm() is None and a.call("Window", "Selected") is None, "menu-slet uden bekræftelse")
    check("Deleted 2 conversations." in strip(undo_row().label.text), f"undo-tekst: {strip(undo_row().label.text)}")
    # Dan skriver igen, mens Undo står der: Undo lægger det gamle foran det nye.
    whisper("Dan", "you there?")
    u = undo_row()
    u.Click(u, "LeftButton")
    check([e["x"] for e in a.whisper_log("Dan-Spineshatter")] == ["hi from Dan", "you there?"],
          f"Dan efter Undo: {a.whisper_log('Dan-Spineshatter')}")
    check(a.whisper_log("Cleo-Spineshatter") != [], "Cleo tilbage")
    check(a.unread(dan) == 2, f"ulæst tilbage og lagt sammen: {a.unread(dan)}")
    check(a.call("Window", "Selected") == cleo, "den valgte samtale er valgt igen")
    check("undo" not in a.list_items(), "Undo væk efter brug")
    # Uden Undo: væk efter 10 s, også efter /reload.
    a.call("Window", "Delete", bob)
    w.step(5)
    check("undo" in a.list_items(), "Undo står der stadig efter 5 s")
    w.step(6)
    check("undo" not in a.list_items(), "Undo væk efter 10 s")
    w.logout(a)
    a = w.login("Anna")
    check(a.db().whispers["Bob-Spineshatter"] is None, "slettet for altid efter reload")
    check(a.call("Window", "Delete", "g:nope") is False, "grupper slettes ikke med x")

    # Fold sammen: titellinjen med antal nye; beskeder giver ulæst + toast; minimap-klik folder ud.
    a.open(cleo)
    a.call("Window", "Fold")
    check(not a.call("Window", "IsShown") and a.call("Window", "IsFolded"), "foldet sammen")
    check(a.db().settings.folded is True, "huskes")
    whisper("Cleo", "ping")
    check(a.unread(cleo) == 1, "ulæst, mens den er foldet (samtalen ses ikke)")
    check(a.toast() is not None, "toast, mens den er foldet")
    total = sum(v for _, v in items(a.db().unread))
    check(total >= 2 and strip(a.call("Window", "BarText")) == "Wowsenger  (%d new)" % total,
          f"titellinje: {strip(a.call('Window', 'BarText'))}")
    bar = a.lua.globals().WowsengerBar
    bar.left, bar.top = 120, 700   # titellinjen er trukket hen et andet sted
    a.mock.ldb["Wowsenger"].OnClick()
    pt = list(a.call("Window", "Frame").GetPoint(a.call("Window", "Frame")))
    check(pt[0] == "TOPLEFT" and pt[3:] == [120, 700], f"folder ud, hvor titellinjen står: {pt}")
    check(a.call("Window", "IsShown") and not a.call("Window", "IsFolded"), "minimap-klik folder ud")
    check(a.unread(cleo) == 0 and a.db().settings.folded is None, "ud: læst og ikke længere foldet")
    a.call("Window", "Fold")
    w.logout(a)
    a = w.login("Anna")
    check(a.call("Window", "IsFolded") and not a.call("Window", "IsShown"), "foldet igen efter reload")
    a.lua.eval("function() WowsengerBar.close.scripts.OnClick(WowsengerBar.close) end")()
    check(not a.call("Window", "IsFolded") and not a.call("Window", "IsShown"), "X på titellinjen lukker")
    check(a.db().settings.folded is None, "lukket = ikke foldet næste gang")
    a.call("Window", "Fold")
    bar = a.lua.globals().WowsengerBar
    bar.scripts.OnClick(bar, "LeftButton")
    check(a.call("Window", "IsShown"), "klik på titellinjen folder ud")

    # Træk større: flere rækker i listen, størrelsen huskes og holdes inden for grænserne.
    for i in range(40):
        whisper("P%02d" % i, "hey")
    a.open()
    rows, visible = a.call("Window", "Rows")
    small = visible
    f = a.call("Window", "Frame")
    f.SetSize(f, 800, 640)
    a.lua.eval("function() WowsengerFrame.grip.scripts.OnMouseUp(WowsengerFrame.grip) end")()
    rows, visible = a.call("Window", "Rows")
    check(visible == (640 - 42) // 18 and visible > small, f"rækker {small} -> {visible}")
    shown = sum(1 for i in range(1, visible + 1) if rows[i].shown)
    check(shown == visible, f"alle {visible} rækker bruges: {shown}")
    s = a.db().settings.size
    check((s.w, s.h) == (800, 640), f"størrelse gemt: {s.w}x{s.h}")
    f.SetSize(f, 3000, 100)
    a.call("Window", "SaveSize")
    s = a.db().settings.size
    check((s.w, s.h) == (1400, 260), f"grænser: {s.w}x{s.h}")
    f.SetSize(f, 800, 640)
    a.call("Window", "SaveSize")
    w.logout(a)
    a = w.login("Anna")
    a.open()
    f = a.call("Window", "Frame")
    check((f.width, f.height) == (800, 640), f"størrelse efter reload: {f.width}x{f.height}")
    check(a.call("Window", "Rows")[1] == (640 - 42) // 18, "rækker passer til den gemte størrelse")


# ---------------------------------------------------------------------------
def main():
    global current
    wanted = [a for a in sys.argv[1:] if a.isdigit()]
    for name, fn in SCENARIOS:
        num = name.split(".")[0]
        if wanted and num not in wanted:
            continue
        current = name
        before = len(failures)
        try:
            fn()
        except Exception as e:  # noqa: BLE001
            failures.append(f"[{name}] crashed: {e!r}")
        status = "ok" if len(failures) == before else "FAIL"
        print(f"{status:4} {name}")
    print(f"\n{checks} checks, {len(failures)} failures")
    for f in failures:
        print("  " + f)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
