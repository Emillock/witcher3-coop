WITCHER 3 CO-OP (Witcher Online for The Witcher 3 Remastered)
=============================================================

See your friends in your world and travel together. Each player keeps their own save.

In a party (walk up to a friend's character, press the interact key and pick "Join party"),
the party leader's world is the one that counts:
- Monsters are shared: everyone fights the leader's monsters. They walk, run, attack, cast,
  dodge, taunt and shoot along with the leader's monsters (the same attack or spell). Your hits count in the leader's world, their attacks reach
  you (dodge them as usual), and they die for everyone.
- Quest progress is shared through the journal: objectives the leader reaches show up in your
  journal too (only forward; nothing you finished is undone). The quest the leader tracks becomes
  your tracked quest when the leader switches it.
- Cutscenes and dialogues play in each player's own game when their quest gets there; stay near
  the leader (within 8 m) to share them. The leader's dialogue choices are picked for everyone
  in the same dialogue (also if you get there a few seconds later), and when the leader skips a
  line or cutscene, it is skipped for you too.
- You see each other's signs, not only the casting gesture: Igni's fire, Aard's wave, Axii,
  Yrden's trap on the ground and Quen's shield.
- Farther than about 60 m from the leader, your own world's monsters take over again.
- The hidden quest facts the leader's game sets during the session are shared too (also only
  forward), so your quests can follow the leader's progress. Loot stays per player.
To play without shared monsters, turn on "MPGhosts_LocalEnemiesOnly" in the mod's options.
Gwent duels between players are switched off in this version.

What you need
-------------
- The Witcher 3: Wild Hunt Remastered (patch 5.01) on Steam, and Steam running.
- Your friends in your Steam friends list.
- The host only: Java 21 or newer (https://adoptium.net). Joining players don't need it.

Install (everyone)
------------------
1. Close the game.
2. Copy everything in this folder (bin, dlc, mods, W3Coop) into your Witcher 3 folder,
   the one that already has "bin" and "content" in it
   (Steam: right-click the game > Manage > Browse local files).
3. Don't install "Custom Player Characters" or "Chill Out" next to this; they clash with it.
4. If you subscribed to the Steam Workshop mod "Fast travel from anywhere", unsubscribe:
   it was made for the old version and stops every mod from loading on Remastered.

Play
----
Host:  run bin\w3coop\Host co-op.cmd, type your name, keep the window open.
       Steam opens an invite window; invite your friends.
Join:  run bin\w3coop\Join co-op.cmd, type your name, keep the window open.
       It finds your hosting friend by itself.
Then everyone starts The Witcher 3 from Steam and loads a save. Meet up in the same region.
While the window runs, Steam shows you as "Playing Spacewar": that's Valve's free test app
the connection uses. Nothing to buy.

If something goes wrong
-----------------------
- "Steam is not running": start Steam, log in, run the .cmd again.
- The joiner keeps "Looking for a friend": the host's window must be open, and you must be
  Steam friends. Or ask the host for the lobby number shown in their window and run
  Join co-op.cmd --lobby NUMBER from a command prompt in bin\w3coop.
- A "Script Compilation Errors" window at startup: another mod clashes; remove it and retry.
- Igni never sets anything on fire, nothing bleeds or gets knocked down: another mod replaced
  the game's effect list. The Steam Workshop mod "Consumables Balanced" does; unsubscribe from it
  (this happens without co-op too).

Uninstall
---------
Delete mods\modWitcherOnline, mods\modWitcherOnlineCompat, dlc\dlcWitcherOnline, bin\w3coop,
bin\WitcherOnline, the three files bin\x64_dx12\dinput8.dll, WitcherNativeBridge.asi and
WitcherOnlineClient.asi, bin\config\r4game\user_config_matrix\pc\modWitcherOnline.xml and W3Coop.

Credits and licenses
--------------------
Witcher Online by rejuvenate7 and contributors (GPL-3.0), ported to Remastered here.
WitcherNativeBridge by Flawkee and rejuvenate7 (MIT). Ultimate ASI Loader by ThirteenAG (MIT).
Licenses and the full source of the modified parts are in W3Coop\licenses and W3Coop\source.
Status: tested with automated bots, two game copies on one PC, also through real Steam between
two accounts. Covered: seeing each other and movement; shared monsters (hits, attacks, hit
reactions, deaths, leaving and coming back; their copies walk and run like the leader's monsters);
journal progress, quest facts and dialogue choices. Not yet tested on two different PCs over the
internet.
Known limits: a monster's copy plays the same attack animation, but for a few swings (some of the
bear's, the water hag's) it starts about 0.1-0.3 s late and then catches up; a dodge shows about
half a second late; parries show only part of the time.
Burning, bleeding and knockdown are passed on but unverified in normal play.
