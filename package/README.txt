WITCHER 3 CO-OP (Witcher Online for The Witcher 3 Remastered)
=============================================================

See your friends in your world and travel together. Each player keeps their own save:
enemies, quests and loot are NOT shared, so do quests side by side and make the same choices.
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
Status: tested with two game copies on one PC (players see each other and follow each other's
movement, also through the Steam relay with a stand-in for Steam). Not yet tested between two
real Steam accounts on different PCs.
