# Wowsenger

Messenger-agtig chat i World of Warcraft: gruppesamtaler med dine venner (også på tværs af guilds)
og dine whispers, samlet i ét vindue med ulæst-markeringer og historik. Venner, der var offline, får
gruppens beskeder, når de logger ind, fra et hvilket som helst andet medlem, der er online.

Mål: WoW Forever (derefter Retail). Status: v0.1.0, kun testet i simulatoren.

## Brug

- **Minimap-knappen** åbner og lukker vinduet (eller `/wowsenger`).
- **+ New group**: giv gruppen et navn, og kryds venner af (eller skriv `Navn` / `Navn-Realm`).
  Alle i gruppen skal have Wowsenger. Alle medlemmer kan tilføje og fjerne folk.
- Klik på en samtale for at læse og skrive. Whispers kommer også i Wowsenger (og stadig i den normale chat),
  også de blå Battle.net-whispers (vist under vennens BattleTag).
- Højreklik på en samtale: Edit group, Leave group, Invite to party, Delete conversation.
- En ny besked, mens vinduet er lukket, giver en lille boks øverst på skærmen. Klik åbner samtalen;
  træk den, hvis den skal stå et andet sted (`/wowsenger toast test` viser en prøve, `/wowsenger toast reset`).

Kommandoer: `/wowsenger help` viser dem. Til test alene: `/wowsenger debug demo` (en lokal demo-gruppe,
intet sendes), `/wowsenger debug demo off`.

Grænser: man får kun beskeder, mens man er online samtidig med mindst ét andet medlem. I bosskampe,
M+ og dungeons kan spillet spærre addon-beskeder; de kommer bagefter. Højst 500 beskeder pr. gruppe.

## Udvikling

- Koden ligger i `Wowsenger/`.
- Testudgave i spillet: `WowsengerTest` er et link fra spillets AddOns-mappe til `Wowsenger/` i repoet og
  indlæses via `WowsengerTest.toc`, så den udgivne addon fra CurseForge kan ligge i `AddOns\Wowsenger` ved siden af:

  ```
  mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WowsengerTest" "<repo>\Wowsenger"
  ```

  Slå én af dem til på AddOns-listen; er begge slået til, kører den udgivne, og testudgaven skriver
  "Not running". Testudgaven gemmer for sig (`WowsengerTestDB`). Ændringer virker efter `/reload`
  (genstart spillet, når der kommer nye filer i .toc'en). `WowsengerTest.toc` skal liste de samme filer og
  samme `Interface`/`Version` som `Wowsenger.toc`; simulatoren (scenarie 25) fejler ellers.
- Test: `pip install lupa`, derefter `python tools/sim.py`.
- Design og protokol: [SPEC.md](SPEC.md).
