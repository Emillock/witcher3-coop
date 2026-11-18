# What each version added

The current release is **v0.7.0**; see
[Releases](https://github.com/Emillock/witcher3-coop/releases) for the packages themselves.

This file is the working history and carries whatever is merged but not released yet, under "Not released
yet". [CHANGELOG.md](../CHANGELOG.md) is the published history: a version is written there as it is
published, and that file changes at no other time.

## Not released yet

A monster your friend charms with Axii is your ally too. The charm travels with it, so your copy of it is
charmed as well; it stays shared while the charm lasts, where it used to drop out of your world and come for you
again with its own mind back; and it cannot hurt anyone in the party any more. That last one was the worst of
it: the game lets an attack catch a charmed fighter's friends, so your friend's new ally was landing hits on you
- twenty attempts in twenty-one seconds, in the run that measured it.

## New in v0.7.0

Monsters your friend is fighting stand nearer to where they really are. A copy used to be put exactly where the
leader's monster was when the news left, so over the internet it stood a trip behind - and, when a packet was
late or lost, it waited there and then jumped to catch up. It now carries the monster's velocity and aims where
the monster will be, led by half the round trip, which the mod measures for itself. Measured over an imitated
150 ms link with 5% loss: 0.47 m behind on average before, 0.39 m after, the worst tenth 1.16 m before and
1.01 m after, and the copy no longer stands still between packets. A monster that is turning is not led, so
nothing wobbles. A hit that somehow arrives before the swing it belongs to now waits a moment for it instead of
landing out of nowhere.

Each party member's name on the party HUD now carries the round trip to them, which both sides measure for
themselves. It is the same figure the copies of shared monsters are led by, so it says what your co-op will feel
like rather than what a network tool thinks: two games on one PC read about 35 ms, and an imitated 150 ms link
reads about 0.4 s.

A monster that comes apart in one world comes apart in the others. A copy of the leader's monster is killed by
script, which plays a plain death, so a drowner cut in half next to your friend used to simply fall over on your
screen. The wound the engine picked there - one of the eight a drowner carries - now rides over with it, and the
copy loses the same limb as it dies, with the same particles and the gear it drops. A finisher's own animation
stays with the player who landed it.

Three contributions to the relay, all from localzet, merged on 2026-11-14 (#6, #7, #8). A host whose Java
server fails to start no longer opens a lobby: it used to print the warning and then put a joinable lobby in
front of a server that was not there, and sit there waiting. The relay's UDP sockets are checked as they are
set up, so a failed bind says which Winsock error it was, and the join path still advises picking another port
with `--local-port`. And the Java server is handed to its job object before it is allowed to run, so killing
the relay cannot leave a server behind holding the game's port. Each came with its own test, and the relay's
build runs all of them.

## New in v0.6.1

A member can watch the cutscene its leader is watching, instead of standing around while it plays. It is off
until you turn it on (Options, Mods, Witcher Online, "Watch Leader's Cutscenes"), because the scene plays
against your own save as well as the leader's. It needs the scene's people to be in your world, which is the
case when you are both at the same point of the same quest; when they are not, nothing happens and you are
told about the cutscene as before.

A member also catches up on a leader's quest progress from before it joined: the leader pages its whole
journal out, active quests first, where it used to send only what changed during the session and only the last
48 of those. The pager waits out a fight, having nothing urgent to say.

The last two of the ten reports from the 2026-11-09 session: a player carried on another player's horse is put
back on when its attachment is lost - a destroyed horse, a scene, a teleport - instead of being left standing
where it was dropped, unable to move and invisible to the rider once it was 100 m behind; and the crossbow
half of "arbalest not shooting", which measures working on this build (the aiming flag goes out every 50 ms,
the leader's own crossbow is in its ghost's hand and the ghost plays the aiming pose), so that report went
with the orphaned copies 0.6.0 fixed.

The mod's own text, including its section of the game's options, reads in any language the game runs in.
Remastered decodes each language's string table with that language's own key and in a format of its own, so
the port's tables - the English one copied under all seventeen names - gave nothing at all outside an English
game.

A player carried on another player's horse is put back on when its attachment is lost - a destroyed horse, a
scene, a teleport - instead of being left standing where it was dropped, unable to move and invisible to the
rider once it was 100 m behind.

The mod's own text reads in any language the game runs in, its section of the game's options included, which
was blank for every player whose game was not English. Remastered reads a string table in a format of its own,
and reads each language's file with that language's own key; the port shipped its English 4.x table under all
seventeen language names, so nothing in it resolved. The eighteen tables are written from the mod's own
en.csv now (and Ukrainian, which the port never had, is among them).


Gwent duels between players, on the 5.01 Gwent board rebuilt with Witcher Online's duel code. The duel
scripts are in the release, the board is not: it is built from each player's own game (see WitcherOnline
`gwent/README.md`), so it cannot be shipped.


## New in v0.6.0

The first session on two PCs with a friend found ten faults. These are the fixes.

- A monster killed in the leader's world no longer lives on in yours. Its copy could be left standing,
  walking and unhittable: a death during the leader's cutscene was never told, because the leader's own
  code does not run while a scene plays, and the copies a member holds through such a scene were dropped
  the moment it ended. Both are fixed; a held copy now survives a scene of up to 30 seconds.
- The mod's own text reads again. Every line it shows - the party HUD's names, the round menu's sections,
  the join, trade and duel prompts, the version warnings - came from a text file Remastered cannot read, so
  it came up blank or as a row of question marks. Those 94 lines are in the scripts now. (The mod's own
  section of the game's options is still unlabelled; the package's README.txt names its rows in order.)
- A player standing still is seen standing still. Anyone whose game was paused, in a menu or in the
  inventory was seen striding on the spot by everyone else.
- You are asked whether to follow the leader's fast travel again, which is what 0.4.0 promised. The
  leader's own loading screen looked to your game like a new leader arriving, so the journey was never
  recognised as one.
- Villagers asleep in bed are no longer stood to attention in your world: only people on their feet are
  stood in it.

Shown working in that session's other two reports, and most likely the same orphaned copies as the first
fault: the leader's Igni damage mirrors exactly, and the leader's crossbow bolt is copied for members.

## New in v0.5.0

- A monster you kill leaves you its loot: what it dropped in the leader's world is on its body in yours.
- A cutscene no longer leaves you fighting blind. The leader's monsters leave your character alone while you
  watch one, and your friends are asked whether to wait for you.
- Hits on a copy sound like hits; they were silent wherever the base game plays the sound itself.
- People the leader can talk to and your world has not got are named for you and stood where the leader sees
  them, as a sight.
- You are told, once per quest, when the leader is behind you on it.
- The round player menu is built again for Remastered, so trading and emotes have their menu back.
- The fight is described thirty times a second instead of ten, and a member's fight is the leader's fight too.
- A character that drifts from where its player says it stands is put back.
- The host's server has room for more co-op channels, which is what lets the new messages through. Both
  players should use this version's `Host co-op.cmd`.


## New in v0.4.0

Joining a party works again (the menu it used shows nothing on Remastered, so interacting with a
player now asks in the game's own dialog), no copy of a monster is left standing in a member's world, and a member
left behind when the leader fast-travels is asked whether to follow.


## New in v0.3.1

(Everyone needs these too, and the host its server; 0.3.0 and older crash at startup on the game's update
of 2026-10-29):
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
- Players see a message when someone near runs another W3Coop version (other versions work only in part).


## New in v0.3.0

Monster copies play the leader's monsters' exact attack and move animations, a few dozen
milliseconds behind (the same swing, throw, charge, spell or sign, so spells' area effects show for members too), and
dodge, taunt, jump back and parry when they do. Effects a monster's attack plays from its script show on the copy, and
effects it applies without a hit (a fugas' burning vomit, a wraith's blinding aura) reach members.


## Before that

v0.1.0 was presence only: players saw each other, with nothing shared.

How the shared world works, and what a truly shared one would take: [true-coop-design.md](true-coop-design.md).
