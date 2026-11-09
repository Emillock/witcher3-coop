# Witcher 3 co-op (Remastered)

Play The Witcher 3: Wild Hunt **Remastered (patch 5.01)** with friends over Steam, using
[Witcher Online](https://github.com/rejuvenate7/WitcherOnline) ported to the Remastered build. Everyone keeps
their own save. The party leader's world owns the monsters, and the others fight copies that move, attack and
die as the leader's do.

## Download

**[v0.5.0](https://github.com/Emillock/witcher3-coop/releases/tag/v0.5.0)** is the current release. Take
`W3Coop-0.5.0.zip`, copy its four folders into your Witcher 3 folder, and make sure both players run the same
version. `W3Coop\README.txt` inside the package covers hosting, joining and uninstalling.

- Game build 5.0.0.1048522, or Steam's update of 2026-10-29 (5.0.0.1090142).
- The host needs Java 21 or newer. Nobody opens a port or shares an IP address - the traffic goes over Steam.
- It is marked pre-release: every feature has passed its own test, but this is early software. What is tested
  and what the known limits are: [docs/status.md](docs/status.md).

## What a party shares

- **Monsters.** The leader's world owns them; members fight copies that walk, run, attack, cast, dodge, taunt,
  react and die as the leader's monsters do. Members' hits count in the leader's world, and the monsters' hits
  land on members.
- **The loot of a shared kill.** What a monster dropped in the leader's world is on its body in yours, the same
  items. Neither player takes the other's drop.
- **Quest progress.** The journal and the game's quest facts, and members follow the leader's tracked quest.
- **Dialogue.** The leader's choices and skips apply to members in the same scene.
- **Signs, bombs and bolts.** Everyone sees each other's Igni, Aard, Axii, Yrden and Quen, the sign gathering in
  the caster's hand, and bombs and bolts flying and exploding.
- **Room for a cutscene.** While you watch one the leader's monsters leave your character alone, and your
  friends are asked whether to wait for you.
- **The leader's people.** Someone the leader can talk to and your world has not got is named for you and stood
  where the leader sees him, as a sight.

What each release added, and what is merged but not yet released:
[docs/versions.md](docs/versions.md).

## Playing

One of you runs `Host co-op.cmd` and starts the game; the other runs `Join co-op.cmd` and starts
theirs. In game, walk up to your friend's character, press the interact key and answer "Yes": that forms the
party, and everything above is shared from then on. The party leader is whoever was asked.

How the connection works:

1. `Host co-op.cmd` starts the Witcher Online server and a w3relay host.
2. The relay host creates a friends-only Steam lobby.
3. `Join co-op.cmd` finds that lobby and opens a local UDP port, and the game connects to it.
4. Packets travel over Steam's networking (`ISteamNetworkingMessages`).

The relay runs as Valve's free test app Spacewar (AppID 480), so while it runs Steam shows "Playing Spacewar".
It loads the game's own `steam_api64.dll`. No Steamworks SDK files are in this repo.

## For developers

| | |
|---|---|
| Building from source, repo layout | [docs/building.md](docs/building.md) |
| The test harness and its scenarios | [docs/testing.md](docs/testing.md) |
| How the shared world works, and what a truly shared one would take | [docs/true-coop-design.md](docs/true-coop-design.md) |
| What is tested, and the known limits | [docs/status.md](docs/status.md) |
| Version history | [docs/versions.md](docs/versions.md) |

The mod itself lives in the fork [Emillock/WitcherOnline](https://github.com/Emillock/WitcherOnline), branch
`shared-enemies`, and is included here as the submodule `WitcherOnline`, pinned to the commit these tools were
tested with. Clone with `git clone --recurse-submodules`. This repo holds what goes around it: **w3relay**,
which carries the game's traffic over Steam; the **player package** builder; and the **test harness** that runs
two game copies on one PC with an in-game bot.

## Credits and licenses

- This repo: MIT, see [LICENSE](LICENSE).
- Witcher Online: rejuvenate7 and contributors, GPL-3.0. The player package ships the modified source.
- WitcherNativeBridge: Flawkee and rejuvenate7, MIT.
- Ultimate ASI Loader: ThirteenAG, MIT.
- The approach (Steam relay over Spacewar, automated multi-instance tests) follows the
  [coop-anything](https://github.com/cranebeaker/coop-anything) playbook.

This project is not affiliated with CD PROJEKT RED or Valve. The Witcher 3 is a trademark of CD PROJEKT S.A.
