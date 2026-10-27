# Witcher 3 co-op (Remastered)

Play The Witcher 3: Wild Hunt **Remastered (patch 5.01)** with friends over Steam, using
[Witcher Online](https://github.com/rejuvenate7/WitcherOnline) ported to the Remastered build.

- The port of Witcher Online itself is in the fork
  [Emillock/WitcherOnline](https://github.com/Emillock/WitcherOnline): branch `remastered-5.01` (v0.1.0,
  presence only) and `shared-enemies` (true co-op, v0.2.0 and later; tag `v0.2.0`). It is included here as the
  submodule `WitcherOnline`, pinned to the `shared-enemies` commit these tools were tested with. Clone with
  `git clone --recurse-submodules`.
- This repo holds what goes around it:
  - **w3relay**: carries the game's traffic over Steam, so nobody opens ports or shares an IP address.
  - The **player package** builder.
  - The **test harness** that runs two game copies on one PC with an in-game bot.

## Status: v0.2.0 pre-release

Players see each other in their own worlds, and each keeps their own save. Since v0.2.0 (branch
`shared-enemies`), when players are in a Witcher Online party:
- **Monsters are shared.** The leader's world owns them; members fight copies that walk, run, attack, react and
  die as the leader's monsters do. Members' hits count in the leader's world, and the monsters' hits land on members.
- **Quest progress is shared:** the journal and the game's quest facts (read from the engine), and members
  follow the leader's tracked quest.
- **Dialogue stays together:** the leader's choices and skips apply to members in the same scene.
- **Signs show:** everyone sees each other's Igni, Aard, Axii, Yrden and Quen, not only the casting gesture.

Not released yet (branch `shared-enemies` after v0.2.0): monster copies make the same attack as the leader's
monsters (the same swing, spell or sign, so spells' area effects show for members too), and dodge, taunt, jump back
and parry when they do. v0.1.0 was presence only. Gwent duels between players are switched off. Details: [docs/true-coop-design.md](docs/true-coop-design.md).

| | |
|---|---|
| Tested | Two game copies on one PC: presence, movement, and every shared-monster and journal scenario below. Over real Steam, two accounts on one PC (the second in a Sandboxie box): the joiner finds the host's lobby and game traffic flows both ways. |
| Not tested yet | Two different PCs over the internet. Real encounters beyond one monster nest (other tests spawn monsters by script). Chat, emotes and horses on 5.01. |
| Known limits | Monster copies make the same attack as the leader's monsters: a swing plays the leader's own animation, a median 16-56 ms behind for most monsters (drowner, wraiths, harpy, humans, werewolf, katakan, troll, endrega, arachas), about 0.1 s for the water hag and the bear (some swings can only be identified at their hit window or from the monster's pose; the copy then plays faster to catch up). A spell or sign is the copy's own same task. Their dodges, taunts, jump-backs, parries and other moves play the leader's animation the same way (a median 18-25 ms behind), and they fire their projectiles; tested casters' spells show for members (leshen, mages, spriggan, bruxa, scolopendromorph, golems), Shaelmaar's copy now swings with it, and its ground-shaking dig, rain of rocks and their confusion and damage reach members, and summoned creatures (shared like any monster) are untested. Status effects (burning, knockdown, bleeding) are forwarded both ways, also those a monster's attack or aura applies without a hit (a fugas' vomit, a wraith's blindness), and effects a monster's attack plays from its script show on its copy (the fugas' vomit fire, though not its vomiting motion); they work unless another mod replaces the game's effect list, as the Workshop mod "Consumables Balanced" does (no burning, bleeding or knockdown at all, also without co-op). Quest-fact sync reads the 5.01 game's memory layout and switches itself off if a patch changes it. |

## Playing

Download `W3Coop-0.2.0.zip` from [Releases](https://github.com/Emillock/witcher3-coop/releases) and copy
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
<root>\WitcherNativeBridge      rejuvenate7/WitcherNativeBridge (master supports 5.01)
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
python package\build_package.py 0.2.0
```

The last step writes `<root>\work\dist\W3Coop-0.2.0` and its zip. [config.py](config.py) finds the game
through Steam's library folders. You can override paths with `W3_GAME_DIR`, `W3C_ROOT` and `W3C_WORK`.

## Testing

| Command | What it does |
|---|---|
| `python relay\selftest.py` | Two relays and a mock Steam, no game. Checks traffic in both directions, a client that arrives late, and that a non-member can't reach the server. |
| `./compile.sh <tag>` (Git Bash) | Deploys the port and the test bot into the game folder and runs only the game's script compiler. |
| `python run_test.py see_each_other` | Starts a local server and two games driven by the bot. They must spawn each other. |
| `python run_test.py movement [--relay]` | One bot walks while the other checks that its copy follows. `--relay` sends the second bot through w3relay over mock Steam. |
| `python run_test.py shared_enemy` | Shared enemies ([design](docs/true-coop-design.md)). The second bot joins the first one's party. The first spawns a drowner; the second hits its copy three times. Both must agree on its health, and the copy must die when the first bot kills it. |
| `python run_test.py enemy_attacks [--monster PATH]` | The leader's drowner attacks the member's ghost: its puppet attacks too and the hits land on the member, after the member's own armor. `W3T_DIRECT_EFFECTS=N` also waits for N effects its attacks apply without a hit (the member is then hit but never killed). |
| `python run_test.py attack_view [--monster PATH]` | The leader's drowner attacks only the leader. On the member, its copy's attacks must really play (the copy's own hit windows fire), each at the leader's character, none at the member, none of its own. Also logs how often the copy played the same animation (on its slot), and every attack's timing on both sides (`SYNC` lines). |
| `python attack_sync.py <run folder> [scenario]` | From a run's `SYNC` lines: per attack, whether the copy played the leader's animation, how long after the leader's monster it started (median, p90), how far behind its hit window came, and whether hits that cut the leader's swing short cut the copy's too. `attack_view` settings: `W3T_VIEW_ATTACKS=N` (the leader passes after N attacks, 4), `W3T_VIEW_KEEP=N` (the leader steps back to N m: throws, charges), `W3T_VIEW_MORTAL=1` (the leader can be hit: wolves and ghouls ignore an invulnerable one), `W3T_VIEW_PROVOKE=1` (a light hit every 3 s while it stays out of combat), `W3T_COUNTER=N` (every N s the monster is told to counter-attack, as after a few hits: a fugas' vomit, a werewolf's charge; also in `enemy_attacks`), `W3T_MONSTER_HP=0.4` (its health first), `W3T_VIEW_HIT=1` (with `W3T_TICK=0.1`) hits the monster as each attack starts, `W3T_SLOT_ATTACKS=0` turns the slot animations off, `W3T_POSE=0` naming by pose. |
| `python run_test.py enemy_spells [--monster PATH]` | The leader fights a spell caster (a leshen by default), close for 6 s and 11 m off for 6 s. The copy must make the leader's attack tasks (two thirds the same task) and cast its spell (the leshen's roots spawn on the member's side) at the leader, never at the member. |
| `python run_test.py real_encounter` | Both bots go to the nearest active monster nest (from the map pins). The member's own encounter monsters there must become copies of the leader's, never fight beside them, and die when the leader kills its monsters. |
| `python run_test.py member_combat` | The member fights the leader's (immortal) drowner's copy with real sword swings, Igni and Aard: the leader applies the hits and the effects they carry. |
| `python run_test.py sign_visuals` | The member fights the leader's drowner and casts all five signs: its own Igni and Aard play their effects, and the leader shows each sign at the member's character (Igni's fire, Aard's wave, Axii, Yrden's trap, Quen's shield), with the member's own Yrden range and duration and its Quen's hit bursts. `W3T_OLD_SIGNS=1` ignores the sign fields of the member's snapshots, as from an older version. |
| `python run_test.py sign_check --bots 1` | One game, no co-op needed: the game's effect definitions and what Igni/Aard do to a drowner (a diagnostic: with a mod that replaces the game's effect list, no status effect takes hold). |
| `python run_test.py enemy_projectiles [--monster PATH]` | The leader's archer (a Baron's bandit with a bow by default) shoots at the member's ghost: copies of its arrows fly on the member's side, and a hit lands on the member. |
| `python run_test.py enemy_moves [--monster PATH]` | The leader swings at its monster (a sword bandit by default, made to dodge every swing and taunt every 6 s), which dodges, parries or taunts; the puppet must show the same dodges and parries (the leader's animation on its slot; with `W3T_SLOT_MOVES=0` made by its own AI) for 3 of 4 of at least 8. Taunts and moves of its own are logged. |
| `python run_test.py enemy_summons [--monster PATH]` | Diagnostic: the leader fights a summoner (a noonwraith by default); passes once a monster it summoned has a copy on the member. In Novigrad neither a noonwraith nor a leshen summoned within 4 minutes, so it is not in the suite. |
| `python run_test.py reactions` | The leader's hits replay on the member's puppet; a bleeding hit reaches the member with its effect. |
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
