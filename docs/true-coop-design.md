# True co-op for The Witcher 3 (Remastered): shared enemies, then quests

Witcher Online gives presence (players see each other) but every player has a separate world: their own
enemies, quests and loot. This plan adds host authority on top of Witcher Online's transport, in the order
the coop-anything playbook recommends (authority, then world/quest state, then transitions).

## Model

- **Party host is the authority** for hostile NPCs near party members. Other players mirror the host's
  enemies and send "I hit enemy N for X" claims; the host applies them and broadcasts results.
- **Each player keeps their own save.** Story state is mirrored from the host's facts (below), never pushed
  back. Leaving the party returns a player to their own world unchanged.
- **Network ids**: the host numbers enemies it shares (`netId`, per session). Messages reference netIds,
  never engine handles.

## Milestone 1: one shared enemy (vertical slice)

1. Host: every 100 ms, collect hostile NPCs within 40 m of any party member (`FindGameplayEntitiesInRange`
   around each player's position, filter `GetAttitude(thePlayer) == AIA_Hostile`, alive). For each: netId,
   template path (`GetReadableName` of the entity template), appearance, position, heading, health
   percentage, alive flag, current target (player name or none).
2. Client: for each netId, find a local twin (same template within 5 m of the host position) or spawn one
   from the template. Turn the twin into a puppet: AI off (no target, no attack), immortal locally,
   position/heading driven from host state (teleport if far, otherwise MoveTo), health bar from host state.
   Despawn puppets the host no longer reports; kill the puppet when the host reports death.
3. Client attacks on a puppet: wrap the damage pipeline (`W3DamageManagerProcessor` /
   `CActor.ReduceHealth*`) so damage to a puppet is not applied locally but sent to the host
   (`hit netId amount type`). Host applies it to the real NPC as a damage action from the remote player's
   ghost, so aggro and reactions happen on the host.
4. Host enemies attacking a ghost: give Witcher Online ghosts the player's attitude group so host AI targets
   them; damage dealt to a ghost is sent to its player (`hurt amount`) and applied to their real Geralt.

Exit test (`shared_enemy`, 2 bots): host bot spawns a drowner 6 m ahead; both bots see it (client via a
puppet); client bot applies 3 hits through the normal damage path; both log the same health after each hit
(within 2 %); host kills it; client's puppet dies within 2 s; no duplicate drowner on the client.

Kill switch: `MPGhosts_SharedEnemies` menu option; when off, everything below is inactive.

### As built (steps 1-4; exit tests pass)

Code: `scripts/local/coopEnemies.ws` in the Witcher Online fork, plus a `COOP` opcode in the client ASI and the
server.

- **Transport.** `COOP` packets carry a channel name and fields. The server keeps each player's latest value per
  channel (at most 4) and rebroadcasts it every 100 ms, like Witcher Online's own state; the client passes a
  channel's value to scripts only when it changed. Both channels are state, so a lost packet is repaired by
  the next one.
  - `en` (leader): `epoch seq area`, hit acknowledgements `user session lastSeq`, a template table, then per
    enemy `netId template appearance x y z yaw health alive`. At most 24 enemies.
  - `hit` (member): `leader epoch session hurtAck`, then every hit not yet acknowledged as `seq netId fraction`.
  - `hurt` (leader): `epoch`, then every hit on a member's ghost not yet acknowledged, as
    `user seq netId hitReaction` plus raw damage `type value` pairs.
- **Roles.** Witcher Online's party decides: the leader of a party with members is the authority; a member
  mirrors its leader in the same area. Not in a party: nothing changes.
- **Puppets.** Twin search: same `GetReadableName()` within 10 m, else spawn from that path with `LoadResource`.
  AI is pre-empted with `CAIDoNothingAction` at `BTAP_AboveCombat` (the pattern `DogNPC.ws` uses) and given back
  on release. Movement uses the movement adjustor like Witcher Online's ghosts; health uses `SetHealthPerc`.
- **Hits.** `CNewNPC.OnTakeDamage` is wrapped. For a puppet, the damage this game computed (own stats, skills,
  crits, the monster's resistances) is sent as a fraction of max health and zeroed locally. The leader applies
  the fraction as direct damage, with the member's ghost as attacker. Fractions keep level-scaled health
  consistent between worlds. The damage processor multiplies an NPC attacker's damage by
  `damage_final_multiplier` (difficulty; 3.3x on the test save), so the leader divides it back out.
- **Monsters hurting members (step 4).** On the leader, party members' ghosts join the player's attitude group
  and become gameplay-visible, since attack tickets skip invisible non-player targets (`btTicket.ws`). They stay
  invulnerable. A `W3DamageManagerProcessor.ProcessAction` wrap records a shared monster's hit on a ghost: its
  raw damage types and values and its hit reaction, before the ghost's invulnerability zeroes them. The member
  applies them to its own Geralt with the monster's puppet as attacker, so the member's armor, Quen and
  difficulty count; a hit that lands mid-dodge misses. The same wrap stops ghosts' own AI from damaging the
  leader's monsters, since members' hits arrive as claims. The leader also collects NPCs hostile to a member's
  ghost, not only to its own Geralt. Ghost hits register even though Witcher Online disables ghost collisions.
- **Duplicates.** Hostile NPCs within 30 m of a member that match nothing in the leader's world are hidden and
  idled while the member mirrors the leader, and restored when the member leaves.
- **Kill switch.** The menu toggle is `MPGhosts_LocalEnemiesOnly`; off (the default) means shared. A new label in
  the mod's `.w3strings` is still needed.
- **Confirmed in game:** `GetReadableName()` returns the depot path (`characters\npc_entities\monsters\
  drowner_lvl1.w2ent`), and `LoadResource` spawns from it.
- **Still open:** whether `BTAP_AboveCombat` keeps every monster's combat tree idle (the drowner puppet
  followed the leader's positions); how forced-idle monsters look when hit; twin matching on real encounter
  spawns (the test spawns by script, so the member had no twin).

Tests (2026-10-18):
- `server_coop_test.py` (server channel, no game): PASS.
- `run_test.py shared_enemy`, 2 clients on one PC: PASS. The member sent three hits of 4 % after its own
  stats. Both games agreed on 0.96, 0.92 and 0.88. The puppet died about 0.6 s after the leader's kill,
  within 0.6 m of the real drowner, with no duplicate.
- `run_test.py enemy_attacks`, 2 clients: PASS. The leader's drowner, neutral to the leader, attacked the
  member's ghost. Five hits were captured and acknowledged, and the member took 560 and 588 damage from the
  first two after its own armor.
- Over real Steam between two accounts (2026-10-19; the joiner's relay in a Sandboxie box logged in to a second
  account): `movement` PASS and `shared_enemy` PASS (0.96, 0.92 and 0.88 on both sides; the puppet died with the
  leader's drowner).
- Earlier runs failed and found three bugs:
  - the NPC difficulty multiplier was applied to members' hits;
  - the leader only tracked monsters hostile to its own Geralt;
  - the test leader's invulnerability was reset on the default channel (now `AIC_Cheat`).

## Milestone 2: combat feel

Animation mirroring for puppets (attack, hit reaction, death) from host behavior events; aggro on the
nearest player; hand-off when the host leaves the area (enemies revert to local AI after 1.5 s, the OOT
True Co-op rule).

### As built (tests pass)

- **Attacks.** On the leader, a `CNewNPC.OnPreAttackEvent` wrap catches a shared monster's hit window:
  - At `AET_DurationStart` it records the animation name (`GetAnimNameFromEventAnimInfo`) under a new attack
    number, and the snapshot goes out at once.
  - At `AET_DurationEnd`, where the hit is processed, it records the animation time of the hit.

  The member's puppet plays that animation through a forced `CAIPlayAnimationSlotAction` at `BTAP_Emergency`, above
  the idle tree; afterwards it is idle again. A direct `ActionPlaySlotAnimationAsync` is refused while the idle
  tree owns the puppet's actions.
- **Hits in time with the swing.** Each hurt carries its attack number and hit time. The member applies it when
  its puppet's swing reaches that point (0.27-0.34 s after arrival in the test), so the member sees the wind-up
  and can dodge it. A hurt from an attack the member missed lands at once.
- **Hand-off by distance.** The leader shares only with members within 60 m; a member farther than that, or in
  another area, releases its puppets and hidden monsters immediately, and its own world's monsters take over.
  The leader's world does not simulate monsters far from the leader.
- **No finishers on puppets**, via `DisableFinishers` (killing blow) and `DisableFinisher` (living target): a
  finisher would kill the puppet outside the leader's say.
- **Hit reactions.**
  - The leader records every hit on a shared monster: who hit it and the hit reaction type. Members replay hits
    by others, since the hitter's own game already reacted.
  - The vanilla reaction needs damage dealt, so a member's own hit on a puppet keeps 0.01 damage instead of 0.
  - The forced idle tree swallows hit reactions, so a hit lifts it for 0.8 s and the monster's own AI plays the
    reaction. A puppet's own damage on a member is dropped; members are only hurt by the leader's hits.
- **Effects of monster hits** (bleeding, poison, stagger, knockdown) travel with the hurt as effect types. The
  member's own immunities and resistances decide whether they take hold.
- **Matching an encounter that exists in both worlds.** Unmatched local hostiles near a member are hidden and
  idle. When the leader's copy of one appears, the member's own monster is found (same template, within 10 m),
  shown again and made the puppet. No duplicate is spawned.
- **Not done:** special attacks that are not attack animations (charges, jumps, spells, projectiles); hit
  reactions are best effort: one of two mirrored hits showed `IsInHitAnim` in the test.

Tests (2026-10-19, 2 clients on one PC):
- `enemy_attacks`: PASS. The puppet started all 5 attacks, and the member took 1735 damage in 3 hits.
- `handoff`: PASS. Puppets were released 2.8 s after the member went 120 m away, and mirrored again 2.0 s after
  it came back.
- `reactions`: PASS. Both of the leader's hits were replayed (one showed a hit animation), and the bleeding hit
  reached the member with its effect.
- `twin_match`: PASS. The member's own drowner became the puppet; no duplicate.
- `shared_enemy`: PASS.

The tests confirm each attack and reaction was accepted by the AI. That the animations look right has to be
checked by eye.

## Milestone 3: quest progress

The Witcher 3 drives quest conditions from the facts database (`FactsAdd`, `FactsQuerySum`,
`FactsRemove`) plus journal states. Host broadcasts fact writes (re-entrancy guard on apply), and a snapshot
diff on join; clients apply them in a session layer so their own save only keeps them if the player saves
while in the party (decision for the owner). Dialog choices are already synced by Witcher Online's party.

Exit test: host bot sets a quest fact and advances a journal objective; client bot reads the same fact value
and objective state; a third bot joining late gets the same snapshot hash.

### As built (journal; tests pass)

- **What can be captured.** `FactsAdd` is a native import, so scripts cannot wrap it, and quest graph fact blocks
  write to the facts database without any script involved. General fact sync would need an engine-level hook
  and is not done. The journal is reachable: the native journal reports every quest and objective update to the
  HUD (`CR4ScriptedHud.OnQuestEvent` / `OnQuestObjectiveEvent`), including the quest system's own.
- **Journal sync.**
  - Every game records those updates by unique tag with the latest status.
  - The leader sends the session's list (up to 48 entries) every second on a `jr` channel. A changing tick makes
    a member that joins later get the list too; the client passes on unchanged state only once.
  - Members apply only forward changes: inactive, then active, then succeeded or failed; never backwards, never
    from one outcome to the other. Objectives are found by tag through the quest hierarchy, because
    `GetEntryByTag` does not find an objective that is still inactive in this game.
  - Tags can contain spaces; the client restores `*` to spaces in co-op fields.
- **Other quest progress in co-op.** Shared monsters die in both worlds, so their death facts are written in
  both. Witcher Online's party already syncs dialogue choices.
- **Save policy.** Mirrored journal states are applied to the member's world and kept if the member saves. The
  member's quest graph may later move the same entries itself; only forward changes are mirrored, so nothing is
  ever undone.

Test (2026-10-19, 2 clients): `quest_sync` PASS. The leader activated an inactive objective before the member
joined. The member joined 15 s later and had the objective, at the same status, 2 s after joining.

## Party: scenes, dialogue and tracking

Cutscenes and dialogue scenes are not started in sync. Each player's scene plays when their own quest
reaches it, so players at the same quest point see it at about the same time. Forcing a scene to play in
another world would bypass that world's quest graph. Within a scene:

- **Choices** (Witcher Online): the leader's pick is selected for followers in the same dialogue within 8 m.
  The leader sees "waiting for party" until followers reach the choice.
  - Witcher Online dropped the pick when a follower had not reached the choices yet. It now waits up to 20 s
    for matching choices.
  - Its choice matching never matched choices without a play-go chunk, because "None" was compared with "none".
- **Skips:** the leader's line and cutscene skips (`SSST_Skip`) are replayed by members in the same scene
  (same scene path). Members' own skips stay local.
- **Tracked quest:** the leader's tracked quest and highlighted objective go out with the journal list,
  immediately when they change. Members follow when the leader changes them, for quests active for them;
  in between, a member can track something else.

Test `dialog_sync` (the bots drive the HUD dialogue module directly, inside a scene name set for the test):
the leader tracks two quests in turn, skips twice, and picks choice B; the member reaches the same choices 6 s
later. PASS: both tracking switches followed, both skips replayed, and the pick was applied 2 s after the member
reached the choices.

## Verification (2026-10-19, all milestones)

`run_suite.py` with two game clients on one PC; every scenario is pass/fail by the in-game bots.

| Scenario | Local | Real Steam, two accounts (`--steam-box`) |
|---|---|---|
| see_each_other | PASS | PASS |
| movement | PASS | PASS |
| shared_enemy | PASS | PASS |
| enemy_attacks | PASS | PASS |
| reactions | PASS | PASS |
| twin_match | PASS | PASS |
| handoff | PASS | PASS |
| quest_sync | PASS | PASS |
| dialog_sync | PASS | PASS |

Also passing: `server_coop_test.py` (server co-op channel, no game) and `relay/selftest.py`. Over Steam, every run
joined the host's lobby through the second account, and traffic flowed both ways.

## Open questions

- Which damage entry point catches all player damage (swords, signs, bombs, crossbow) on 5.x: the claims use the
  victim's `OnTakeDamage`, which every damage source goes through; only scripted direct-damage hits are tested.
- Encounter matching is tested with script-spawned twins; real encounters are untested.
- General fact sync (engine-level hook of the facts database).
