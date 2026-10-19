# Witcher 3 co-op (Remastered)

Play The Witcher 3: Wild Hunt **Remastered (patch 5.01)** with friends over Steam, using
[Witcher Online](https://github.com/rejuvenate7/WitcherOnline) ported to the Remastered build.

- The port of Witcher Online itself is in the fork
  [Emillock/WitcherOnline, branch `remastered-5.01`](https://github.com/Emillock/WitcherOnline/tree/remastered-5.01).
- This repo holds what goes around it:
  - **w3relay**: carries the game's traffic over Steam, so nobody opens ports or shares an IP address.
  - The **player package** builder.
  - The **test harness** that runs two game copies on one PC with an in-game bot.

## Status: v0.1.0 pre-release

Players see each other in their own worlds, and each keeps their own save. Released (v0.1.0): presence only.

In development (branch `shared-enemies`, not released yet), when players are in a Witcher Online party:
- **Monsters are shared.** The leader's world owns them; members fight copies that move, attack, react and die
  as the leader's monsters do. Members' hits count in the leader's world, and the monsters' hits land on members.
- **Quest progress is shared** through the journal.

Gwent duels between players are switched off. Details: [docs/true-coop-design.md](docs/true-coop-design.md).

| | |
|---|---|
| Tested | Two game copies on one PC: presence, movement, and every shared-monster and journal scenario below. Over real Steam, two accounts on one PC (the second in a Sandboxie box): the joiner finds the host's lobby and game traffic flows both ways. |
| Not tested yet | Two different PCs over the internet. Real encounters (tests spawn monsters by script). Chat, emotes, horses, party and dialogue sync on 5.01. |
| Known limits | Quest facts outside the journal are not synced (only an engine-level hook could). Special monster moves that are not attack animations (charges, spells, projectiles) are not mirrored. |

## Playing

Download `W3Coop-0.1.0.zip` from [Releases](https://github.com/Emillock/witcher3-coop/releases) and copy
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
<root>\WitcherOnline            Emillock/WitcherOnline, branch remastered-5.01
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
python package\build_package.py 0.1.0
```

The last step writes `<root>\work\dist\W3Coop-0.1.0` and its zip. [config.py](config.py) finds the game
through Steam's library folders. You can override paths with `W3_GAME_DIR`, `W3C_ROOT` and `W3C_WORK`.

## Testing

| Command | What it does |
|---|---|
| `python relay\selftest.py` | Two relays and a mock Steam, no game. Checks traffic in both directions, a client that arrives late, and that a non-member can't reach the server. |
| `./compile.sh <tag>` (Git Bash) | Deploys the port and the test bot into the game folder and runs only the game's script compiler. |
| `python run_test.py see_each_other` | Starts a local server and two games driven by the bot. They must spawn each other. |
| `python run_test.py movement [--relay]` | One bot walks while the other checks that its copy follows. `--relay` sends the second bot through w3relay over mock Steam. |
| `python run_test.py shared_enemy` | Shared enemies ([design](docs/true-coop-design.md)). The second bot joins the first one's party. The first spawns a drowner; the second hits its copy three times. Both must agree on its health, and the copy must die when the first bot kills it. |
| `python run_test.py enemy_attacks` | The leader's drowner attacks the member's ghost: its puppet plays the attacks and the hits land on the member, after the member's own armor. |
| `python run_test.py reactions` | The leader's hits replay on the member's puppet; a bleeding hit reaches the member with its effect. |
| `python run_test.py twin_match` | A drowner exists in both worlds: the member's own becomes the puppet, with no duplicate. |
| `python run_test.py handoff` | The member goes 120 m away (its world runs its own monsters again) and comes back (shared again). |
| `python run_test.py quest_sync` | The leader advances a quest objective before the member joins; after joining, the member has it in its journal. |
| `python run_suite.py [--steam-box <box>]` | All the scenarios above in a row, with a summary table. |
| `python server_coop_test.py` | The server's co-op channel with two fake clients, no game. |
| `run_test.py <scenario> --steam-box <box>` | Over real Steam between two accounts on one PC. The host relay uses this PC's Steam; the joiner relay runs in a [Sandboxie-Plus](https://sandboxie-plus.com) box whose Steam is logged in to a second account. |
| `python arrange_windows.py` | Places all open Witcher 3 windows side by side (the harness does this for its bots). |
| `python deploy.py uninstall` | Removes exactly the files deploy installed (`<root>\work\deploy-manifest.json`), restoring anything it replaced. |

Under the test bot (`w3test.asi`, which runs only when the harness sets `W3T_DOCUMENTS`), each game uses a
throwaway Documents folder. That folder holds copies of your settings and of your newest save (or `--save SUBSTR`),
so tests never write your saves or settings. The bot also:

- applies the lowest graphics preset at 640x360 and 30 FPS, with ray tracing off;
- mutes the game;
- lets two copies start at once and keeps both running unfocused;
- skips the intro movies, answers start-up dialogs and loads the save.

Two copies of the game still need a fair amount of GPU memory.

## Layout

| Path | Contents |
|---|---|
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
