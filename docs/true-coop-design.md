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

## Milestone 2: combat feel

Animation mirroring for puppets (attack, hit reaction, death) from host behavior events; aggro on the
nearest player; hand-off when the host leaves the area (enemies revert to local AI after 1.5 s, the OOT
True Co-op rule).

## Milestone 3: quest progress

The Witcher 3 drives quest conditions from the facts database (`FactsAdd`, `FactsQuerySum`,
`FactsRemove`) plus journal states. Host broadcasts fact writes (re-entrancy guard on apply), and a snapshot
diff on join; clients apply them in a session layer so their own save only keeps them if the player saves
while in the party (decision for the owner). Dialog choices are already synced by Witcher Online's party.

Exit test: host bot sets a quest fact and advances a journal objective; client bot reads the same fact value
and objective state; a third bot joining late gets the same snapshot hash.

## Open questions

- Which damage entry point catches all player damage (swords, signs, bombs, crossbow) on 5.x: to be found by
  reading `damageManagerProcessor.ws` and testing each weapon type with the bot.
- Whether community/encounter spawns can be matched reliably between two worlds, or puppets should always be
  spawned fresh and local twins hidden.
- Save policy for mirrored facts.
