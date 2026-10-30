# Witcher 3 co-op (Remastered)

Play The Witcher 3: Wild Hunt **Remastered (patch 5.01)** with friends over Steam, using
[Witcher Online](https://github.com/rejuvenate7/WitcherOnline) ported to the Remastered build.

- The port of Witcher Online itself is in the fork
  [Emillock/WitcherOnline](https://github.com/Emillock/WitcherOnline): branch `remastered-5.01` (v0.1.0,
  presence only) and `shared-enemies` (true co-op, v0.2.0 and later; tags `v0.2.0`, `v0.3.0`). It is included here as the
  submodule `WitcherOnline`, pinned to the `shared-enemies` commit these tools were tested with. Clone with
  `git clone --recurse-submodules`.
- This repo holds what goes around it:
  - **w3relay**: carries the game's traffic over Steam, so nobody opens ports or shares an IP address.
  - The **player package** builder.
  - The **test harness** that runs two game copies on one PC with an in-game bot.

## Status: v0.3.0 pre-release

Players see each other in their own worlds, and each keeps their own save. Since v0.2.0 (branch
`shared-enemies`), when players are in a Witcher Online party:
- **Monsters are shared.** The leader's world owns them; members fight copies that walk, run, attack, react and
  die as the leader's monsters do. Members' hits count in the leader's world, and the monsters' hits land on members.
- **Quest progress is shared:** the journal and the game's quest facts (read from the engine), and members
  follow the leader's tracked quest.
- **Dialogue stays together:** the leader's choices and skips apply to members in the same scene.
- **Signs show:** everyone sees each other's Igni, Aard, Axii, Yrden and Quen, not only the casting gesture.

New in v0.3.0: monster copies play the leader's monsters' exact attack and move animations, a few dozen
milliseconds behind (the same swing, throw, charge, spell or sign, so spells' area effects show for members too), and
dodge, taunt, jump back and parry when they do. Effects a monster's attack plays from its script show on the copy, and
effects it applies without a hit (a fugas' burning vomit, a wraith's blinding aura) reach members.
Not released yet (after v0.3.0; the host needs this version's server):
- Runs on the game's update of 2026-10-29 (build 5.0.0.1090142): every earlier package crashed at startup there,
  because one code signature the native bridge looks for changed (fixed in the bundled bridge, which now accepts
  both forms; its source is in the package). Should a later patch break it again, the bridge says so in a message
  and the game reports the mod's missing functions, instead of crashing at startup.
- Attacks that run on the monster's animation graph alone (a fugas' vomit, a troll's rage) play their body
  animation on the copy too.
- A monster burning, frozen, knocked down, blinded or dazed by Axii looks that way on its copies (before, only its
  hit reaction showed); a burning, frozen or knocked-down player looks that way to the others.
- A player's bombs and crossbow bolts fly and explode for the other players too (harmless copies: the hit counts
  once, through the thrower).
- A member's Axii and Yrden hold the leader's monster too, not only its copy; a member who hit a shared monster gets
  the kill's experience wherever it stands.
- A member killed in a shared fight respawns from its save as usual and is back in the fight: the leader's monsters
  no longer keep hitting its character meanwhile (those hits all landed on the respawn and killed it again).
- A member on horseback can be fought: the leader's monsters went for its horse and then stood by it.
- A member's heavy blow lands heavily in the leader's world too (every member's hit was a light one there).
- Up to 48 monsters are shared at once (was 24; past that a member didn't see the rest).
- A player's horse stays in sight for the others where they left it (Witcher Online showed it only while ridden).

v0.1.0 was presence only. Gwent duels between players are switched off. Details: [docs/true-coop-design.md](docs/true-coop-design.md).

| | |
|---|---|
| Tested | Two game copies on one PC: presence, movement, riding, chat and emotes, trading, a player's death, and every shared-monster and journal scenario below. Over real Steam, two accounts on one PC (the second in a Sandboxie box): the joiner finds the host's lobby and game traffic flows both ways. |
| Not tested yet | Two different PCs over the internet. Three or more players (a third game needs more graphics memory than the test PC has). Real encounters beyond one monster nest and one bandit camp (others are spawned by script). |
| Known limits | Copies follow the leader's monsters a few dozen milliseconds behind (most swings 16-56 ms; the water hag's and the bear's about 0.1 s, then caught up). Untested moves: Shaelmaar's charges, the fairytale witch's and the black mage's spells (they never fought in tests), scripted encounter animations. At most 48 monsters are shared at once; a member's own copies of any more stay hidden. Finishers and dismemberment on a shared monster are not mirrored (others see it die normally). Axii's puppet skill (a human fighting for the caster) works in the caster's world only. A mod that replaces the game's effect list, like the Workshop mod "Consumables Balanced", leaves no burning, bleeding or knockdown at all, also without co-op. Quest-fact sync reads the 5.01 game's memory layout and switches itself off if a patch changes it. Gwent duels between players are off (Remastered rebuilt Gwent). |

## Playing

Download `W3Coop-0.3.0.zip` from [Releases](https://github.com/Emillock/witcher3-coop/releases) and copy
its contents into your Witcher 3 folder. `W3Coop\README.txt` inside covers hosting, joining and uninstalling.
The host needs Java 21 or newer.

How the connection works:

1. `Host co-op.cmd` starts the Witcher Online server and a w3relay host.
2. The relay host creates a friends-only Steam lobby.
3. `Join co-op.cmd` finds that lobby and opens a local UDP port, and the game connects to it.
4. Packets travel over Steam's networking (`ISteamNetworkingMessages`).

The relay runs as Valve's free test app Spacewar (AppID 480), so while it runs Steam shows "Playing Spacewar".
It loads the game's own `steam_api64.dll`. No Steamworks SDK files are in this repo.

## Building

You need Windows, Visual Studio 2022 with the C++ desktop workload, JDK 21, Python 3.10+ and Git Bash.
Put the repos side by side:

```
<root>\witcher3-coop            this repo (any folder name)
<root>\WitcherOnline            Emillock/WitcherOnline, branch shared-enemies (remastered-5.01 for v0.1.0); without it,
                                the tools use this repo's WitcherOnline submodule (git submodule update --init)
<root>\WitcherNativeBridge      rejuvenate7/WitcherNativeBridge (master supports 5.01; the 5.0.0.1090142 fix is a local
                                commit, its source in the package's W3Coop\source\WitcherNativeBridge.zip)
<root>\deps\ultimate-asi-loader-9.7.4\dinput8.dll and LICENSE
                                from Ultimate-ASI-Loader-NoPDB_x64.zip, ThirteenAG/Ultimate-ASI-Loader v9.7.4
```

Run these from a Developer Command Prompt:

```bat
cd <root>\WitcherNativeBridge
msbuild WitcherNativeBridge.sln -p:Configuration=Release -p:Platform=x64

rem The client project's own OutDir points at a GOG install, so override it.
cd <root>\WitcherOnline\client
msbuild MultiplayerClient.sln -p:Configuration=Release -p:Platform=x64 -p:OutDir=<root>\WitcherOnline\client\build\Release\

cd <root>\WitcherOnline\server
mkdir build\classes
javac -encoding UTF-8 -d build\classes src\*.java
cd build\classes && jar cfm ..\WitcherServer.jar ..\..\src\META-INF\MANIFEST.MF *.class

cd <root>\witcher3-coop
relay\build.cmd
w3test\build.cmd
python package\build_package.py 0.3.0
```

The last step writes `<root>\work\dist\W3Coop-0.3.0` and its zip. [config.py](config.py) finds the game
through Steam's library folders. You can override paths with `W3_GAME_DIR`, `W3C_ROOT` and `W3C_WORK`.

## Testing

| Command | What it does |
|---|---|
| `python relay\selftest.py` | Two relays and a mock Steam, no game. Checks traffic in both directions, a client that arrives late, and that a non-member can't reach the server. |
| `./compile.sh <tag>` (Git Bash) | Deploys the port and the test bot into the game folder and runs only the game's script compiler. |
| `python run_test.py see_each_other` | Starts a local server and two games driven by the bot. They must spawn each other. |
| `python run_test.py movement [--relay]` | One bot walks while the other checks that its copy follows. `--relay` sends the second bot through w3relay over mock Steam. |
| `python run_test.py horse_ride` | One bot calls its horse, mounts it and rides, then gets off and walks away; the other checks that its copy sits on Witcher Online's horse for remote riders, that the horse follows, and that it stays in sight where it was left. `W3T_HORSE_PARTY=1`: in a party. |
| `python run_test.py social` | One bot chats and makes two emotes (wave, bow); the other checks that the line shows over its copy and each emote plays on it. |
| `python run_test.py shared_enemy` | Shared enemies ([design](docs/true-coop-design.md)). The second bot joins the first one's party. The first spawns a drowner; the second hits its copy three times. Both must agree on its health, and the copy must die when the first bot kills it. |
| `python run_test.py enemy_attacks [--monster PATH]` | The leader's drowner attacks the member's ghost: its puppet attacks too and the hits land on the member, after the member's own armor. `W3T_DIRECT_EFFECTS=N` also waits for N effects its attacks apply without a hit (the member is then hit but never killed). |
| `python run_test.py attack_view [--monster PATH]` | The leader's drowner attacks only the leader. On the member, its copy's attacks must really play (the copy's own hit windows fire), each at the leader's character, none at the member, none of its own. Also logs how often the copy played the same animation (on its slot), and every attack's timing on both sides (`SYNC` lines). |
| `python attack_sync.py <run folder> [scenario]` | From a run's `SYNC` lines: per attack, whether the copy played the leader's animation, how long after the leader's monster it started (median, p90), how far behind its hit window came, and whether hits that cut the leader's swing short cut the copy's too; for attacks raised on the copy's graph, how close the copy's pose is to the leader's monster's. `attack_view` settings: `W3T_VIEW_ATTACKS=N` (the leader passes after N attacks, 4), `W3T_VIEW_KEEP=N` (the leader steps back to N m: throws, charges), `W3T_VIEW_MORTAL=1` (the leader can be hit: wolves and ghouls ignore an invulnerable one), `W3T_VIEW_RIDE=1` (the leader fights from its horse), `W3T_VIEW_PROVOKE=1` (a light hit every 3 s while it stays out of combat), `W3T_COUNTER=N` (every N s the monster is told to counter-attack, as after a few hits: a fugas' vomit, a werewolf's charge; also in `enemy_attacks`), `W3T_MONSTER_HP=0.4` (its health first), `W3T_VIEW_HIT=1` (with `W3T_TICK=0.1`) hits the monster as each attack starts, `W3T_SLOT_ATTACKS=0` turns the slot animations off, `W3T_POSE=0` naming by pose, `W3T_VIEW_HIDE=N` (every N s the monster turns invisible for 1.5 s and reappears 4 m aside, as an invisible teleport does; it attacks less, so lower `W3T_VIEW_ATTACKS`). |
| `python run_test.py enemy_spells [--monster PATH]` | The leader fights a spell caster (a leshen by default), close for 6 s and 11 m off for 6 s. The copy must make the leader's attack tasks (two thirds the same task) and cast its spell (the leshen's roots spawn on the member's side) at the leader, never at the member. |
| `python run_test.py real_encounter` | Both bots go to the nearest active monster nest (from the map pins). The member's own encounter monsters there must become copies of the leader's, never fight beside them, and die when the leader kills its monsters. `W3T_PIN_TYPE=BanditCamp` (or another map pin kind): a bandit camp instead. |
| `python run_test.py enemy_effects` | The leader burns, knocks down, freezes, blinds and confuses its (immortal) drowner one after another; the member checks that its copy gets each effect and loses it when it ends on the leader's drowner. |
| `python run_test.py encounter_mismatch` | The member's world has a nekker where the leader's has a drowner: the member's nekker must stay hidden (not a copy) and the leader's drowner come as a spawned copy. |
| `python run_test.py trade` | The leader sells the member a Dwarven spirit for 10 crowns through Witcher Online's trade popups (the bots answer them): the item and the money must move. |
| `python run_test.py enemy_crowd` | The leader shares 40 drowners around the member (it shares up to 48); the member must copy every one. `W3T_CROWD=N` for another number. |
| `python run_test.py player_effects` | The member burns, is knocked down, frozen and poisoned in turn; the leader checks that its character shows each and loses it again. |
| `python run_test.py mounted_fight` | The member rides its horse while the leader's drowner fights it: the drowner must attack (it goes for the horse) and its hits reach the riding member, each swing once. |
| `python run_test.py member_death` | The member (little health, mortal) is killed by the leader's drowner and respawns from its save as the death screen does: it must be back in the party with its copy of the drowner, without the hits that were aimed at its character meanwhile. |
| `python run_test.py leader_death` | The leader dies and respawns from its save: the member lets go of its monsters meanwhile, stays in the party and copies the leader's new drowner. |
| `python run_test.py member_combat` | The member fights the leader's (immortal) drowner's copy with real sword swings, Igni, Aard, Axii, Yrden, a bomb and a crossbow bolt: the leader applies the hits and the effects they carry (Axii's confusion and Yrden's slowdown, put on without a hit, too), and throws harmless copies of the bomb and bolt from the member's character. |
| `python run_test.py sign_visuals` | The member fights the leader's drowner and casts all five signs (after two rounds only Quen, so that the drowner, dazed and slowed by the others, gets to hit the shield): its own Igni and Aard play their effects, and the leader shows each sign at the member's character (Igni's fire, Aard's wave, Axii, Yrden's trap, Quen's shield), with the member's own Yrden range and duration and its Quen's hit bursts. `W3T_OLD_SIGNS=1` ignores the sign fields of the member's snapshots, as from an older version. |
| `python run_test.py sign_check --bots 1` | One game, no co-op needed: the game's effect definitions and what Igni/Aard do to a drowner (a diagnostic: with a mod that replaces the game's effect list, no status effect takes hold). |
| `python run_test.py enemy_projectiles [--monster PATH]` | The leader's archer (a Baron's bandit with a bow by default) shoots at the member's ghost: copies of its arrows fly on the member's side, and a hit lands on the member. |
| `python run_test.py enemy_moves [--monster PATH]` | The leader swings at its monster (a sword bandit by default, made to dodge every swing and taunt every 6 s), which dodges, parries or taunts; the puppet must show the same dodges and parries (the leader's animation on its slot; with `W3T_SLOT_MOVES=0` made by its own AI) for 3 of 4 of at least 8. Taunts and moves of its own are logged. |
| `python run_test.py enemy_summons [--monster PATH]` | The leader fights a summoner (a noonwraith by default), swinging at it and standing off in turn; passes once a monster it summoned has a copy on the member. A leshen (`--monster characters\npc_entities\monsters\lessog_lvl1.w2ent`) summoned wolves after about 3 minutes; a noonwraith never did, so it is not in the suite. |
| `python run_test.py reactions` | The leader's hits replay on the member's puppet; a bleeding hit reaches the member with its effect. `W3T_REACT_HITS=N`: N hits (light and heavy in turn); `attack_sync.py` then compares the copy's flinches with the leader's monster's. |
| `python run_test.py twin_match` | A drowner exists in both worlds: the member's own becomes the puppet, with no duplicate. |
| `python run_test.py handoff` | The member goes 120 m away (its world runs its own monsters again) and comes back (shared again). |
| `python run_test.py quest_sync` | The leader advances a quest objective before the member joins; after joining, the member has it in its journal. |
| `python run_test.py dialog_sync` | The member follows the leader's tracked quest and skips, and gets the leader's dialogue pick when it reaches the choices 6 s later. |
| `python run_test.py facts_sync` | Quest facts the leader's game sets (before and after the member joins) reach the member with the same values. |
| `python run_test.py puppet_follow` | The leader's drowner runs 14 m; its copy is never more than 3.5 m behind it for a second, and is within 1.5 m of it once it has run 8 m. |
| `python run_test.py puppet_walk [--monster PATH]` | As `puppet_follow`, and the copy must run on its legs: its foot swings at least half as far as the leader's real monster's (a slide alone swings it about 0.1 m). `--monster` takes another template's depot path. `puppet_glide` is the same run with copies only sliding, as a baseline. |
| `run_test.py <scenario> --shots S` | Also saves both bots' windows as PNG every S seconds (in the run folder). |
| `run_test.py a,b,c` | A session: several scenarios in one pair of games, which load only once. After each scenario the bots clean up (its monsters die and go, counters reset, back to the start) when the harness says so (a control file), and each scenario gets its own `RESULT` line. |
| `run_test.py showcase --size 960x540 --record 240 --record-from "SHOWCASE start"` (with `W3T_TICK=0.25`) | A representative co-op session to film: the bots meet, form a party, run together and fight two waves side by side with swords and all five signs. `--record` films both windows side by side with ffmpeg (`video.mp4` in the run folder); `--size` sets the window and render resolution. |
| `python run_suite.py [--steam-box <box> [--all]] [--no-session]` | The scenarios above with a summary table. Those that can share a game run as one session; quest_sync, dialog_sync, facts_sync and real_encounter get fresh games. Over Steam only 4 scenarios run by default (only the transport differs): movement, shared_enemy, member_combat, sign_visuals. |
| `python server_coop_test.py` | The server's co-op channel with two fake clients, no game. |
| `run_test.py <scenario> --steam-box <box>` | Over real Steam between two accounts on one PC. The host relay uses this PC's Steam; the joiner relay runs in a [Sandboxie-Plus](https://sandboxie-plus.com) box whose Steam is logged in to a second account. |
| `python arrange_windows.py` | Places all open Witcher 3 windows side by side (the harness does this for its bots). |
| `python deploy.py uninstall` | Removes exactly the files deploy installed (`<root>\work\deploy-manifest.json`), restoring anything it replaced. |

Under the test bot (`w3test.asi`, which runs only when the harness sets `W3T_DOCUMENTS`), each game uses a
throwaway Documents folder. That folder holds copies of your settings and of your newest save (or `--save SUBSTR`),
so tests never write your saves or settings. The bot also:

- applies the lowest graphics preset at 640x360 (or `--size`) and 30 FPS, with ray tracing off;
- mutes the game;
- lets two copies start at once and keeps both running unfocused;
- skips the intro movies, answers start-up dialogs and loads the save.

`W3T_DISABLE_MODS=modA,modB` switches those mods off in the test games' sandboxed `mods.settings` only (e.g. a Workshop mod, to see whether it causes a problem).

Both games load at once (`--serial` loads one after the other, as before). Two copies of the game still need a fair
amount of GPU memory: about 10.6 GB of 12 GB here, loading at once or not.

## Layout

| Path | Contents |
|---|---|
| `WitcherOnline/` | Submodule: the mod (the Emillock/WitcherOnline fork, GPL-3.0), pinned to the tested `shared-enemies` commit |
| `relay/` | w3relay (host and join), the mock `steam_api64.dll` for one-PC tests, self-test |
| `package/` | Package builder, `Host co-op.cmd`, `Join co-op.cmd`, player README |
| `w3test/` | The test bot: ASI (test-mode hooks, env natives) and script mod (scenarios) |
| `run_test.py`, `w3run.py`, `sandbox.py`, `preset_expand.py`, `deploy.py`, `compile.sh` | Harness |
| `ws_*_check.py`, `wnb_static_check.py`, `port_edits/`, `exe_strings.py`, `pe_imports.py` | Static checks and scripted edits used during the port |
| `docs/` | Design notes |

## Credits and licenses

- This repo: MIT, see [LICENSE](LICENSE).
- Witcher Online: rejuvenate7 and contributors, GPL-3.0. The player package ships the modified source.
- WitcherNativeBridge: Flawkee and rejuvenate7, MIT.
- Ultimate ASI Loader: ThirteenAG, MIT.
- The approach (Steam relay over Spacewar, automated multi-instance tests) follows the
  [coop-anything](https://github.com/cranebeaker/coop-anything) playbook.

This project is not affiliated with CD PROJEKT RED or Valve. The Witcher 3 is a trademark of CD PROJEKT S.A.
