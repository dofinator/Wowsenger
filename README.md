# Huddle

Messenger-agtig chat i World of Warcraft: gruppesamtaler med dine venner (også på tværs af guilds)
og dine whispers, samlet i ét vindue med ulæst-markeringer og historik. Venner, der var offline, får
gruppens beskeder, når de logger ind, fra et hvilket som helst andet medlem, der er online.

Mål: WoW Forever (derefter Retail). Status: v0.1.0, kun testet i simulatoren.

## Brug

- **Minimap-knappen** åbner og lukker vinduet (eller `/huddle`).
- **+ New group**: giv gruppen et navn, og kryds venner af (eller skriv `Navn` / `Navn-Realm`).
  Alle i gruppen skal have Huddle. Alle medlemmer kan tilføje og fjerne folk.
- Klik på en samtale for at læse og skrive. Whispers kommer også i Huddle (og stadig i den normale chat),
  også de blå Battle.net-whispers (vist under vennens BattleTag).
- Højreklik på en samtale: Edit group, Leave group, Invite to party, Delete conversation.
- En ny besked, mens vinduet er lukket, giver en lille boks øverst på skærmen. Klik åbner samtalen;
  træk den, hvis den skal stå et andet sted (`/huddle toast test` viser en prøve, `/huddle toast reset`).

Kommandoer: `/huddle help` viser dem. Til test alene: `/huddle debug demo` (en lokal demo-gruppe,
intet sendes), `/huddle debug demo off`.

Grænser: man får kun beskeder, mens man er online samtidig med mindst ét andet medlem. I bosskampe,
M+ og dungeons kan spillet spærre addon-beskeder; de kommer bagefter. Højst 500 beskeder pr. gruppe.

## Udvikling

- Koden ligger i `Huddle/`. `_forever_\Interface\AddOns\Huddle` er en junction hertil: ret, og `/reload`.
- Test: `pip install lupa`, derefter `python tools/sim.py`.
- Design og protokol: [SPEC.md](SPEC.md).
