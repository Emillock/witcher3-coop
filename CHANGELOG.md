# Changelog

Every published version of W3Coop, newest first.

**This file changes when a version is published, and at no other time.** Work that is merged but not yet in
anyone's hands belongs in [docs/versions.md](docs/versions.md) under "Not released yet"; it moves here on the
day it is released. `gh_release.py` refuses to publish a tag that has no section here, and takes the release
notes from that section when it is not given a notes file.

Each heading is `## [<version>] - <date> - <what the release is about>`. Every release so far is a
pre-release: two players on two PCs have played on it, but it has not had wide testing.

## [0.6.1] - 2026-11-12 - watch your friend's cutscenes

- A member can watch the cutscene its leader is watching, in its own world, instead of standing around while
  it plays. Off until you turn it on (Options, Mods, Witcher Online, "Watch Leader's Cutscenes"): it needs the
  people of that scene to be in your world, and the scene runs against your own save as well as the leader's.
  Dialogues are unchanged - they stay each player's own, and the leader's choices and skips already carry.
- Joining late catches you up: the leader sends its whole journal in the background, active quests first,
  where it used to send only what changed while you were connected, and only the last 48 of those.
- A player carried on another's horse is put back on when a destroyed horse, a scene or a teleport tears the
  attachment away, instead of being left standing where it was dropped.
- The mod's own text, its section of the game's options included, reads in every language the game runs in.
- With this, all ten reports from the two-player session of 2026-11-09 are accounted for.

## [0.6.0] - 2026-11-11 - the fixes from the first real session on two PCs

- A monster killed in the leader's world no longer lives on in yours, left standing, walking and unhittable.
- The mod's own text reads again: the party HUD's names, the round menu, the join, trade and duel prompts.
- A player standing still is seen standing still: anyone paused or in a menu was seen striding on the spot.
- You are asked whether to follow the leader's fast travel again, which is what 0.4.0 promised.
- Villagers asleep in bed are no longer stood to attention in your world.

## [0.5.0] - 2026-11-09 - shared kills leave you their loot; cutscenes no longer leave you fighting blind

- A monster you kill leaves you its loot: what it dropped in the leader's world is on its body in yours.
- While you watch a cutscene the leader's monsters leave your character alone, and your friends are asked
  whether to wait for you.
- Hits on a copy sound like hits; they were silent wherever the base game plays the sound itself.
- People the leader can talk to and your world has not got are named for you and stood where the leader sees
  them, as a sight.
- You are told, once per quest, when the leader is behind you on it.
- The round player menu is built again for Remastered, so trading and emotes have their menu back.
- The fight is described thirty times a second instead of ten, and a member's fight is the leader's fight too.
- The host's server has room for more co-op channels; both players need this version's `Host co-op.cmd`.

## [0.4.0] - 2026-11-01 - joining a party works again; no monsters left standing

- Joining a party works again: the menu it used shows nothing on Remastered, so interacting with a player
  asks in the game's own dialog.
- No copy of a monster is left standing in a member's world.
- A member left behind when the leader fast-travels is asked whether to follow.

## [0.3.1] - 2026-10-30 - works with the game update; effects, bombs, horses

- Runs on the game's update of 2026-10-29 (build 5.0.0.1090142), where every earlier package crashed at
  startup. Should a later patch break it again, the native bridge says so instead of crashing.
- Attacks that run on the monster's animation graph alone (a fugas' vomit, a troll's rage) play on the copy.
- Burning, freezing, knockdown, blinding and Axii show on copies, and on players, not only hit reactions.
- Bombs and crossbow bolts fly and explode for the other players too.
- A member's Axii and Yrden hold the leader's monster itself; a member who hit a shared monster gets the
  kill's experience wherever it stands.
- A member killed in a shared fight respawns and is back in the fight instead of being killed again at once.
- A member on horseback can be fought; a member's heavy blow lands heavily in the leader's world too.
- Up to 48 monsters are shared at once, was 24. A player's horse stays in sight where it was left.
- Players are told when someone near them runs another W3Coop version.

## [0.3.0] - 2026-10-27 - copies move like the leader's monsters

- Monster copies play the leader's monsters' exact attack and move animations a few dozen milliseconds
  behind, and dodge, taunt, jump back and parry when they do.
- Effects a monster's attack plays from its script show on the copy, and effects it applies without a hit
  (a fugas' burning vomit, a wraith's blinding aura) reach members.

## [0.2.0] - 2026-10-21 - true co-op

- Shared monsters: in a party, everyone fights the leader's monsters. Members' sword hits and signs count in
  the leader's world, the monsters' hits land on members, and monsters die for everyone. More than about 60 m
  from the leader, your own world's monsters take over again.
- Shared quest progress: journal objectives and the game's hidden quest facts follow the leader (only
  forward), and members follow the leader's tracked quest.

## [0.1.0] - 2026-10-18 - presence

- The first public build of Witcher Online for The Witcher 3 Remastered (patch 5.01), with a Steam relay so
  friends can join without opening ports.
- Players see each other in their own worlds and can travel together. Each player keeps their own save;
  monsters, quests and loot are not shared yet.

[0.6.1]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.6.1
[0.6.0]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.6.0
[0.5.0]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.5.0
[0.4.0]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.4.0
[0.3.1]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.3.1
[0.3.0]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.3.0
[0.2.0]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.2.0
[0.1.0]: https://github.com/Emillock/witcher3-coop/releases/tag/v0.1.0
