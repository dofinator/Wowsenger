# Wowsenger – design og protokol

Messenger-agtig chat i WoW: **gruppesamtaler** mellem venner på tværs af guilds plus almindelige
1:1-whispers, samlet i ét vindue med ulæst-markeringer og historik. Ingen server: gruppebeskeder går
mellem spillernes addons som addon-whispers. Søsterprojekt til GuildCrafters, GuildGamble og Grudge
(samme opbygning, Compat.lua og simulator med lupa).

Status: **v0.1.0 bygget 2026-11-21, kun simuleret** (`python tools/sim.py`: 23 scenarier, 114 checks).
Intet er set i en rigtig klient endnu. Mål: WoW Forever først, Retail bagefter.

## 1. Hvad brugeren har bestemt (2026-11-21)

- Kernen: **gruppesamtaler, hvor venner, der er offline, får beskederne, når de logger ind.**
- Fravalgt i denne runde: "skriver..."/"set"-markeringer og en chat-fane i GuildCrafters.
- Layout: **ét vindue med en liste til venstre** (Groups øverst, "+ New group", People under) og
  samtalen til højre med skrivefelt nederst. Valgt fra mockups.
- Medlemmer: **alle på realmen**, ikke kun egen guild.
- **1:1-whispers ligger også i vinduet**, også med folk uden addonen (almindelige whispers).
- Navn: **Wowsenger** (ikke guild-bundet; intet CurseForge-projekt med det navn fundet 2026-11-21).
- Ny besked med vinduet lukket: **lille toast** i hjørnet (5 s, blød lyd, klik åbner). Valgt fra
  mockups; fravalgt: kun tal på minimap-knappen, linje i den normale chat.
- Ny gruppe: **dialog** "New group" med navn + afkrydsning af medlemmer. Fravalgt: "Start group
  with..." fra højreklik.
- **Alle medlemmer må tilføje og fjerne**, alle kan forlade. **Ingen invitation at acceptere**.
- Whispers står **begge steder** (Wowsenger og Blizzards chat). Vinduet åbnes med **minimap-knappen**
  (`/wowsenger` findes også). Egne alts genkendes **automatisk**: alle karakterer på kontoen, der har
  logget ind med Wowsenger.
- **Forever først**: `## Interface: 16001, 120105, 120107`; junction i
  `_forever_\Interface\AddOns\Wowsenger` -> `Wowsenger/` i dette repo.

## 2. Vilkår, der styrer designet

1. **Ingen server og ingen fælles kanal.** Folk er i forskellige guilds, så GUILD-kanalen kan ikke
   bruges. Gruppebeskeder sendes som addon-whisper til hvert medlem (§4).
2. **Man kan ikke sende til nogen, der er offline.** Levering sker, når modtageren er online samtidig
   med *et hvilket som helst* andet medlem, der har beskeden (§5).
3. **Addon-beskeder er spærret i bosskampe, M+ og rated PvP**, og på Forever er dungeons og raids
   "communication-restricted". Whispers kan have "secret values", som
   addons ikke må læse eller gemme. Wowsenger stoler derfor aldrig på, at en enkelt besked når frem (§5).
4. **255 bytes pr. addon-besked.** Lange beskeder deles af AceComm.
5. **Klienter:** WoW Forever først, så Retail 12.x (samme familie). Classic-klienterne senere (en
   .toc-linje og et tjek af Compat.lua). Alt klientafhængigt går gennem `Compat.lua`.

## 3. Begreber

- **Gruppe**: `id` = `<opretterens Navn-Realm>:<løbenummer>:<6 tilfældige hex>`, et navn, en
  medlemsliste og en version. Den tilfældige del gør, at kun dem, der har fået gruppen, kender id'et.
- **Besked**: `(gruppe-id, forfatter, nr)`, hvor `nr` tæller op pr. forfatter pr. gruppe, plus
  tidspunkt (servertid) og tekst. Samme nøgle to gange = én besked.
- **Samtale** i listen = en gruppe (`g:<id>`) eller en person (`w:<Navn-Realm>`).
- Navne er altid `Navn-Realm` internt; vist kort på egen realm, egne karakterer som "You".

## 4. Transport (Comm.lua)

- Præfiks `Wowsenger1`, AceComm-3.0 + AceSerializer-3.0, distribution `WHISPER` til hvert medlem.
- Typer (felt `k`): `H` hello `{ g = { [gid] = { v, h } }, r, hv }`, `G` gruppe `{ d, j }`,
  `M` besked `{ g, m = { a, n, t, x }, s, f }`, `P`/`Q` ping/pong. Ukendte typer ignoreres. Ny data
  senere = ny type, aldrig nye felter i de eksisterende (lærdommen fra GuildCrafters §5).
- **Hvem er online?** Den, vi har hørt fra inden for 20 min, og som ikke har givet "No player named".
  - Ved login (+5 s): `H` til alle andre medlemmer af mine grupper; modtageren svarer med `H` (`r = 1`).
  - Hvert 5. minut: `H` til dem, der er online, og til dem, der ikke har bekræftet den nyeste version
    af en fælles gruppe (fx tilføjet, mens de var offline).
  - "X has come online" (venner og guild) for et medlem: `H` efter 5 s.
  - Efter hver loading screen (fx ud af en dungeon): `H` til dem, der er online.
  - En ny gruppe (`G`, man ikke kendte) besvares med `H`, så begge ved, de er online.
- Nye beskeder (`M`) sendes kun til medlemmer, der er online; resten får dem ved indhentning (§5).
- "No player named 'X' is currently playing." skjules og markerer X offline, hvis vi har sendt X en
  addon-besked inden for 15 s, **medmindre** spilleren selv har whispered X i samme tidsrum (så ses
  fejlen om deres egen whisper). Filter: `ChatFrameUtil.AddMessageEventFilter` (Forever) eller
  `ChatFrame_AddMessageEventFilter` (Classic). **Ikke set i spillet**: om addon-whispers til offline
  spillere giver den fejlbesked på Forever, og om filteret skjuler den.
- I kamp (`InCombatLockdown`) sendes intet; alt står i kø og sendes i rækkefølge efter kampen.
  `C_ChatInfo`-lockdown-funktionerne styrer intet (GuildCrafters-lærdom), de vises i `/wowsenger status`.

## 5. Levering til dem, der var offline (indhentning)

- Alle medlemmer gemmer gruppens historik: højst 500 beskeder pr. gruppe.
- `H` bærer pr. fælles gruppe version `v` og `h = { forfatter -> nr }`: det højeste nr, hvor der ikke
  mangler noget mellem "bunden" og nr. Modtageren sender de beskeder, der mangler (`M` med `s = 1`),
  ældste først, højst 100 pr. gruppe pr. runde; resten tages ved næste runde (5 min).
- **Bunden** (`g.floor`) pr. forfatter: beskeder, man selv har ryddet væk (over 500), eller som
  afsenderen ikke havde (den første `M` pr. forfatter i en indhentning har `f = 1`; er dens nr højere
  end `h + 1`, flyttes bunden op). Uden bunden ville et sent medlem bede om de samme gamle beskeder
  igen og igen (sim scenarie 21).
- Et hul (en tabt besked midt i) gør, at den anden sender fra hullet og frem; dubletter ignoreres.
- Man får beskederne, så snart man er online samtidig med ét hvilket som helst medlem, der har dem.
- Skillelinje "While you were offline" før den første indhentede besked i denne session.
- Kendt grænse: er man aldrig online samtidig med et andet medlem, får man intet.

## 6. Grupper og medlemmer (Groups.lua)

- Oprettes i "New group"-dialogen: navn + medlemmer (venner, seneste whisper-partnere, medlemmer af
  mine andre grupper, online guild-medlemmer, eller skrevet ind som `Navn` / `Navn-Realm`).
- Ændringer er versionerede (`G`, version = `max(gammel + 1, servertid)`); nyeste vinder, lige
  versioner afgøres af `by`. Ændringen sendes til både gamle og nye medlemmer.
- Accepteres kun fra nuværende medlemmer. **Et fjernet medlem kan ikke selv melde sig ind igen**
  (fundet af sim scenarie 20); bliver det tilføjet af en anden, kommer den nye version fra de andre.
- En ukendt gruppe accepteres kun, hvis både jeg og afsenderen står på listen.
- Beskeder: original kun fra forfatteren selv; fra et andet medlem kun som indhentning (`s = 1`), og
  forfatteren skal være eller have været medlem. Relayede beskeder kan ikke bevises (ingen
  signaturer): trusselsmodellen er "venner", med vilje.
- **Egne alts**: skriver man fra en karakter, der ikke er med, kommer den med først (`G` med
  `j = <min karakter, der er med>`). Accepteres kun, hvis ændringen er præcis "afsenderen kommer med",
  `j` er medlem, og afsenderen ikke er fjernet før. Kan ikke bevises (en anden kunne påstå at være en
  alt), men kræver gruppens tilfældige id.
- Forlad = ny version uden mine karakterer. En fjernet/forladt person beholder sin historik, men får
  intet nyt, og gruppen forsvinder fra listen.
- Ikke-medlemmer får aldrig teksten: der sendes kun til medlemmer.

## 7. 1:1-whispers (Whispers.lua)

- Læses fra `CHAT_MSG_WHISPER` / `CHAT_MSG_WHISPER_INFORM` (GM-whispers springes over) og gemmes pr.
  person, højst 500.
- **Battle.net-whispers** (blå tekst; tilføjet 2026-11-21, efter brugerens vens første forsøg):
  `CHAT_MSG_BN_WHISPER` / `_INFORM`, argument 13 = vennens konto-id. Samtalen gemmes under BattleTag'en
  (`Anna#1234`, almindelig tekst via `C_BattleNet.GetAccountInfoByID`); kontonavnet er en beskyttet
  |K-streng og bruges aldrig. Uden læsbar BattleTag ignoreres beskeden (den står stadig i Blizzards
  chat). Sendes med `C_BattleNet.SendWhisper(id, tekst)`, Classic:
  `BNSendWhisper`; id'et slås op i Battle.net-vennelisten. Vist i Battle.net-blå, menu kun "Delete
  conversation", ikke kandidater i "New group". **Ikke set i spillet.**
- Sendes med `C_ChatInfo.SendChatMessage(..., "WHISPER", nil, navn)` fra skrivefeltet (Enter).
  **Ikke set i spillet endnu.**
- Secret values: er beskedteksten "secret" (bosskamp, M+), gemmes den ikke. Den står i Blizzards chat
  som normalt, og samtalen viser en grå linje "message hidden during an encounter".
- Whispers står også i Blizzards chat (brugerens valg); Wowsenger ændrer intet der.

## 8. Vindue (UI/Window.lua)

```
+- Wowsenger ------------------------------------------[X]+
| Groups        | Raid group   4 members, 2 online      |
|  Raid       3 | -- Fri 21 Nov --                      |
|  Alts         | -- While you were offline --          |
| + New group   | 20:01 Anna: Tuesday 20:00?            |
| People        | 20:03 Bob: works for me               |
|  Anna       1 | 20:05 You: great                      |
|  Bob          | [ Message Raid group...            ]  |
+------------------------------------------------------+
```

- Blizzard-stil: `BasicFrameTemplateWithInset`, `ScrollingMessageFrame` (musehjul, links kan klikkes),
  `InputBoxTemplate`. Ulæst-tal i rødt pr. samtale. Navne klassefarvede, hvor klassen er kendt.
- Hover på en gruppe (i listen eller overskriften): medlemmer med online/offline.
- Højreklik på en gruppe: Edit group..., Leave group (bekræft). På en person: Invite to party,
  Delete conversation. Egne små vinduer i stedet for StaticPopup/EasyMenu (taint, Grudge).
- **Hurtigere at bruge (brugerens valg 2026-11-25, fra mockups):**
  - **Slet med x**: musen over en person-række viser Blizzards grå loot-"Pass"-kryds (ulæst-tallet
    skjules imens). Klik sletter med det samme, uden bekræftelse; menuens "Delete conversation" gør det
    samme. Nederst i listen står "Deleted Anna. Undo" i 10 s; flere sletninger i træk samles
    ("Deleted 3 conversations."), og Undo bringer dem alle tilbage (også ulæst-tal; nye whispers, der er
    kommet imens, lægges efter de gamle). Grupper har intet x (forlad = højreklik + bekræft).
  - **Fold sammen**: knap ved siden af X (atlas "RedButton-Condense" på Mainline/Forever, ellers
    `UI-Panel-SmallerButton`) gør vinduet til en titellinje "Wowsenger (3 new)" samme sted. Klik på den,
    minimap-knappen eller en toast folder ud dér, hvor linjen står; dens X lukker. Foldet = vinduet
    regnes som lukket (ulæst + toast). Huskes over /reload (`settings.folded`). Esc lukker ikke linjen.
  - **Træk større** i hjørnet nederst til højre (chatvinduernes greb), 470x260 til 1400x1000; listen
    viser flere rækker. Størrelse i `settings.size`, plads som øverste venstre hjørne i `settings.window`.
  - **Markøren i skrivefeltet**, når man klikker på en samtale eller åbner den fra en toast (Esc slipper).
    Minimap-knappen/`/wowsenger` sætter den ikke (så man kan gå videre med tastaturet).
  - Fravalgt denne gang: "Select"-tilstand med afkrydsning, sletning fra overskriften (alle / ældre end
    7 dage), lille flydende knap, skjul listen, "+ New whisper", ulæste øverst, auto-oprydning, fade.
- Toast (UI/Toast.lua): øverst i midten (brugerens valg 2026-11-21: nederst til højre lå den bag action
  bars), strata FULLSCREEN_DIALOG, kan trækkes (plads i `settings.toastPos`; `/wowsenger toast test` viser en
  prøve, `/wowsenger toast reset` sætter den tilbage), 5 s, lyd kun for gruppebeskeder (Blizzard spiller selv en
  ved whispers), "(N new)" ved flere fra samme samtale. I kamp samles alt til én toast bagefter.
- "New group"-dialogen (UI/NewGroup.lua) bruges også til "Edit group".
- Shift-klik på et item, mens skrivefeltet har fokus, sætter linket ind (post-hook på
  `ChatFrameUtil.InsertLink`). **Ikke set i spillet.**
- `/wowsenger debug demo` laver en lokal demo-gruppe og en demo-whisper (sendes aldrig), så vinduet kan
  prøves alene; `/wowsenger debug demo off` fjerner dem.

## 9. Gemt data (SavedVariables `WowsengerDB`, pr. konto)

Beskrevet øverst i `Wowsenger/Data.lua`: `chars` (egne karakterer), `groups` (med `members`, `former`,
`ver`, `by`, `floor`, `seq`), `messages`, `whispers`, `unread`, `peers` (klasse, har Wowsenger), `trace`
(fejlsøgning: kun typer og navne, aldrig beskedtekst), `settings`.

## 10. Test

- `python tools/sim.py` (lupa): hver klient er sin egen Lua-runtime med den rigtige addon-kode;
  verden leverer addon-whispers og whispers, svarer "No player named" for offline spillere, og
  logout/login gemmer og læser WowsengerDB. Hver fil kører i et miljø, der fejler ved skrivning til
  fremmede globaler (taint). AceComm er en stub (deling af lange beskeder testes ikke).
- 21 scenarier: oprettelse og live-beskeder, indhentning via et andet medlem, tilføjet mens offline,
  "has come online", ikke-medlemmer og forfalskninger, fjernet, forlad, kamp-kø, whispers og secret
  values, fejlbesked-filteret, tabt besked, alts, samtidige ændringer, New group-dialogen, demo,
  500-grænsen, globaler/.toc, ukendte events, minimap/slash, alt-indmelding, sent medlem efter oprydning,
  Battle.net-whispers.
- Mutationstjek 2026-11-21: 8 rettelser fjernet én ad gangen; hver gang fejlede den tilhørende test.
- Rigtig klient: Forever. `/wowsenger debug ping <navn>` (svar = "pong from ..."), `/wowsenger status`, og
  `WowsengerDB.trace` i `_forever_\WTF\Account\<konto>\SavedVariables\Wowsenger.lua`.
