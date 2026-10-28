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
  channel (at most 4) and forwards it on arrival (since 2026-10-22; before, only on its 100 ms broadcast tick, which
  held a monster's attack back 0-100 ms). The tick repeats a channel nothing new came on for 100 ms, so a lost
  packet is repaired. The client passes a channel's value to scripts only when it changed.
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
  - It also records whom the monster attacks: its target as a player's username (the leader, or the member whose
    character it is). If the target is momentarily unset, the last player it went for is kept.

  On the member, the puppet's own AI plays the attack:
  - Its idle tree is lifted for 1.1 s: long enough to start an attack, short enough not to start a second.
  - It notices the attacked player (this Geralt, or the leader's character here). If its AI holds on to another
    target, it forgets everyone first. During the window it is pointed back each tick if its perception picks this
    player again.
  - The leader's character is armed on the member's side too (player attitude group, gameplay-visible), so puppets
    can attack it. Before, it stayed `friendly_to_player` and puppets ignored it.
  - The puppet's own hits do no damage (`OnBeforeDamage`); the hit itself comes as the leader's hurt.
  - So the attack lands at the same moment and on the same player. Since later on 2026-10-21 it is also the same
    attack (next point), and since 2026-10-22 the same animation (below).

  Until 2026-10-21 the puppet was given the leader's animation through a forced `CAIPlayAnimationSlotAction`. The
  action was accepted, so `attacksPlayed` counted it, but the animation never played. The owner saw the copies
  stand still. Investigation:
  - A monster's graph (e.g. `monster_drowner_combat.w2beh`) plays attacks from its Combat state; the idle puppet is
    never there.
  - Its 'Attack' event (the AI tree's `eventStateName`) is refused there too, as are 'MonsterEnterCombat' and
    `CAIExecuteAttackAction`.
  - `attack_view` now checks what really plays: the puppet's own `OnPreAttackEvent` hit windows, each at the
    attacked player, none of its own.
- **The same attack, and spells** (2026-10-21, later the same day):
  - The leader now sends an attack when its attack task starts (a `CBTTaskAttack.OnActivate` wrap; every kind
    calls it: swings, charges, spells, signs, summons, projectiles), not at its first hit window. It carries which
    task it is, `CoopAttackId`: the task's class and attack type (its animation set), the same in every copy of a
    monster, e.g. `CBTTaskLeshyRootAttack:0`. The hit window adds the animation later. An attack without a task (a
    counter from the parry task) still goes at its hit window. The attack field becomes `task|anim`; a 0.2.0 member
    takes it as an animation name, which it doesn't use, and attacks as before.
  - The puppet may start only that task for the first 0.6 s of the window, then any (the same can be out of reach).
    It never starts a summon: what the leader's monster summons is shared. Sixteen attack task kinds decide their
    availability without `CBTTaskAttack.IsAvailable` (signs, magic, projectiles, summons, bombs, charges, ...), so
    each has its own gate wrap. A task already running isn't stopped by the gate (the tree asks again while it
    runs), and the idle tree waits until it ends (up to 6 s) with the puppet standing: a spell's loop outlasts the
    1.1 s window, and its effect comes late.
  - Aiming: the puppet's combat target selection (`CBTTaskCombatTargetSelection`) is told whom to attack with the
    game's 'ForceTarget' event, as quests do ('UnforceTarget' when a twin is released). Forgetting the others
    (`ForgetAllActors`, and per tick `ForgetActor` on this player) restarted its combat tree each time: in
    `enemy_spells` 26 of its attack tasks ended within 0.5 s for 16 mirrored attacks, and the leshen's roots never
    came. With 'ForceTarget': 1-4, and the roots come.
  - So a spell is the puppet's own: it spawns its area entity in the member's world itself, at the player the
    leader's monster attacks. Damage stays single: a projectile-like spell (roots, rocks: `Init(npc)`) names the
    monster as attacker, so the leader forwards its hits on the member's character and the member drops its
    puppet's; an area entity that is itself the attacker (`CDamageAreaEntity`, `W3DamageAreaTrigger`) is neither
    forwarded nor dropped, so each world's own area hurts the player standing in it.
  - A puppet's own `W3AdvancedProjectile` doesn't fly on a member (it goes at once): the leader's projectiles
    come as copies, and the puppet now makes projectile attacks too.
  - `attack_view` (drowner): the same task 7 of 7, the same animation 4 of 7 (the attack type is the same; the
    graph picks the variant, `monster_drowner_attack_dynamic1-3`), no attack at the wrong player. (Before the slot
    animations below.)
  - `enemy_spells` (a leshen, immortal; the leader swings at it for 6 s, then stands 11 m off for 6 s, since up
    close monsters only swing): its roots came on the member as often as on the leader (4 and 4, 3 and 3, within
    0.1-0.4 s), aimed at the leader every time, and the puppet took the same task 14-15 times of 16.
  - Which monsters cast, and where their spells are: the AI trees (`.w2behtree`, most in
    `content0\bundles\startup.bundle`) name the task classes they use.
    - The ice giant has no spell at all (plain attacks, a charge, taunts).
    - The golem tree (golems, earth and fire elementals) gates the stone smash, fire throw, projectile throws and a
      pillar arena behind abilities, distance, a clean shot and (the arena) low health. A fire golem 20 m off at 40%
      health threw fire and fireballs; an earth elemental never cast in 3-4 minutes.
    - `CBTTaskSpawnFXEntity` (effect entities, not attack tasks) is in 33 trees: Blood and Wine monsters and mages'
      specials. They sit in the branch of an attack task, so the puppet runs them with the same attack.
    - The bombardment is only the fairytale witch's, the drop from above only Shaelmaar's (`sharley`);
      `BTTaskFrostAreaAttack` is in no tree.
  - Puppets' AI stays free while their monster fights (a mirrored attack in the last 6 s), no longer only for each
    window: big monsters (golems, giants, the scolopendromorph) spend a window turning and stepping into range, and
    the idle tree at its end restarted that, so their puppets hardly attacked (a fire golem's: none in 86 windows; its
    tree asked for an attack 4 times). The gates keep the free AI to the leader's monster's attacks and moves: a
    puppet's plain animation tasks (`CBTTaskPlayAnimationEventDecorator` itself: native dodges, slams) only while a
    mirrored move waits or plays. A window lasts up to 2.5 s until the puppet starts an attack, then 1.1 s.
  - The attack a puppet may make: the leader's monster's task; for a plain swing any plain swing (the tree picks its
    attack type itself, and refusing it often meant no attack at all); after 0.6 s a plain swing as a fallback. Never
    a spell or special attack the leader's monster didn't make (a mage's puppet cast twice as many spells before).
  - Projectiles dropped from above (Shaelmaar's boulders) get no caster (`Init(NULL)`): the monster whose task spawns
    them stands in (`projectileSpawner`), so the leader mirrors them and a member mutes its puppet's own.
  - `enemy_spells` with each caster (2026-10-22, puppets' AI free; the leader's spawns / the puppet's):
    | Monster | Spells | Spawns |
    |---|---|---|
    | leshen | roots | 21 / 18 |
    | Hearts of Stone mage (`hakland_mage`) | tornado, magic coil, wind, sand cage | 2 / 3 |
    | spriggan | `CBTTaskSpawnMultipleEntities3StateAttack`, projectile | 12 / 11 |
    | scolopendromorph | effect entities, spit | 12 / 11 |
    | bruxa | scream (`CBTTaskSpawnFXEntity`) | 3 / 2 |
    | fire golem | fire throw, fireballs (attacks: 67 for 48 mirrored) | - |
    | water hag, echinops | projectile attacks (the puppet's own muted, the leader's copied) | - |
    | Shaelmaar | boulders, projectiles, dust | 5 / 0: its puppet barely acts (asked for an attack 5 times in 228 windows; since 2026-10-22 its swings play on the slot) |
    The fairytale witch (bombardment) and the base game's black mage never fought in the test spot.
  - `enemy_spells` settings: `W3T_KITE` (stand-off, 11 m), `W3T_MONSTER_HP` (its health first),
    `W3T_SPELL_ATTACKS` (the leader passes after that many, 16), `W3T_AI_FREE=0` (the old idle-between-windows).
- **The same animation, about 30 ms behind** (2026-10-22):
  - Before, the puppet's own AI picked the swing within the leader's task (a drowner's `CBTTaskAttack:1` is one of
    `monster_drowner_attack_dynamic1-3`, picked at random by its graph): 1 of 7 matched, and it started a median
    297 ms (p90 789 ms) after the leader's. The time went to the server's 100 ms tick, the hit window that named the
    animation, and the puppet's tree picking an attack.
  - Leader: an attack counts once it plays (`CommitAttack`): at its first animation event, at its hit window, or
    still running two frames later. A task the graph refuses ends at once and starts again every frame (a bear
    between its attacks made 1454 "attacks" in 150 s). The first animation event ('SyncBlend', 'SlideToTarget', ...)
    names the animation, and the snapshot goes out from that event (`HostSend`), not on the next frame. The attack
    field becomes `task|anim|time|cut`: the animation's own time when sent, and "1" once a hit cut the attack short.
  - Server: co-op state is forwarded on arrival (Transport).
  - Member: a plain swing, or an attack without a task, plays the leader's animation straight on the puppet's
    `NPC_ANIM_SLOT` through its animated component (`PlaySlotAnimationAsync`; the name comes from the new native
    `WO_ToName`). Unlike the AI slot action of 2026-10-21 this plays, in the Exploration graph too. Meanwhile the
    gate holds its own swings, also at `OnActivate`: human trees start attack tasks without asking `IsAvailable`.
    A spell stays the puppet's own task, since its effect comes from it (since 2026-10-26 throws, spits, the
    arachas' pull and charges play on the slot too, below). Any slot animation still playing stops first, and before
    a mirrored move: it would hide them (a leshen's roots came 1 time in 4).
  - Some animations have no event before the hit window (hag, arachas, endrega, bear, troll, some human swings).
    They are named only there, 0.1-0.65 s in. The puppet's own swing waits up to 0.7 s for the name. The slot
    animation then plays faster, at most twice as fast, until it has caught up (`CatchUp`), so the hit lands closer
    to the leader's. Later parts of an attack (a drowner's counter: dodge, then lunge) play on the slot as they come.
  - A hit that ends the leader's attack within 0.5 s sets the cut flag. The puppet's slot animation then stops
    (playing no animation on the slot ends the one there), so its own hit reaction shows. An attack that goes on
    through a hit goes on on the puppet too. With a hit at each attack's start, all 10 swings that were cut short
    after starting on a slot stopped on the puppet as well. The actor-action form of the slot was refused 6 times in
    7, and `GAMEPLAY_SLOT` isn't in the Exploration graph, so neither could be stopped that way.
  - If a slot attack's hit window never comes twice in a row (a graph without the slot), that monster's puppets swing
    with their own AI again (`SlotAttackCheck`).
  - Naming more swings as they start (later on 2026-10-22). What reaches scripts before a hit window was read from
    the game's animation sets (CR2W `.w2anims` in the bundles: each `CSkeletalAnimationSetEntry` holds its events
    inline). Sound, footstep and effect events, often the earliest, never reach scripts, not even through entity
    callbacks (`AddAnimEventCallback`); the attack task gets duration and generic events ('SyncBlend',
    'SlideToTarget'); enum events ('RotateEvent': at once in human swings, 0.2 s into an arachas' or a troll's) come
    only to `CActor.OnEnumAnimEvent`, now wrapped. Over 18 animation sets, the attack animations named later than
    0.15 s fell from 123 of 220 to 81 (the ice giant's 40 of them; humans', harpies' and wraiths' none).
    - A name counts only from an animation that started with the attack (its own time at most the attack's age plus
      0.35 s: some graphs start a swing before its task, a katakan's by 0.2 s; and not the animation that played
      before, still blending out), within 0.6 s, and only an attack animation (a task can start with a run). The hit
      window still names an attack nothing named.
    - Bookkeeping: a hit window belongs to the attack while its task runs, or after it if it is still its animation
      (a bear's task can end before its hit window: two attacks were counted, and the copy swung twice). Once a
      leader names animations, a copy never stands in its own swing (it swung where a bear only started a task).
    - The troll's attack task (`CBTTaskTrollAttack`: its own events only pick targets) plays on the slot too.
    - Special attacks (2026-10-26): throws and spits (`CBTTaskProjectileAttack`, `...WithPrepare`: their projectile
      comes as a copy anyway), the arachas' tongue pull and charges play on the slot too (`CoopSlotSwing`); before,
      the puppet's own AI rarely started them, so its copy stood still while the leader's monster threw or spat. Their
      animations can be named later: within 2 s (a troll's throw has no event before 1.1 s, a cyclops' ground slam
      before 1 s), from anything but moving about (no "run", "walk", "strafe", "turn", "idle", "move" unless an
      "attack"), and a late one catches up from up to 1.6 s behind. Only swings are checked for a hit window (a spit or
      a pull has none: two such checks in a row had switched the arachas' puppets back to their own AI). Names from
      events also teach pose naming, so a monster's second throw can be named by its pose.
    - Attacks in phases (3-state attacks: a troll's rage; charges): each phase that starts while the task runs (its
      animation's own time under 0.35 s) is named and sent, and a loop's restart too ("anim#n"), so the puppet plays
      start, loop and end in turn (`NextPhase`). The loop's effect (`playFXOnLoopStart`) comes with the script effects
      (below).
    - Verified with `attack_view` and `W3T_VIEW_KEEP=10` (the leader steps back to 10 m: a troll throws at 5-16 m,
      from its tree): a troll's throws named first at 1.1 s ('Prepare'), then by pose at 0.24-0.31 s, the puppet
      starting them 0.25-0.33 s in; every rock came as a copy (6 of 6); its rage played start, loop and end on the
      slot. Charges (5 m and more, facing the target, a clear line) never came in that test: monsters closed in and
      swung. An armored arachas (`arachas_lvl2__armored`: its tree charges within 5 m, every 5 s at most) charged on
      2026-10-27: its puppet started the same jump 30 ms after the leader's monster, its hit window 28 ms behind. A
      werewolf charges only as a counter-attack, after its counter dodge left it 4-12 m away (`W3T_COUNTER=4`, the
      leader hit but never killed; standing off made it circle and taunt instead): its puppet started the same charge
      104 ms behind (named 77 ms in, then caught up), its hit window 45 ms behind.
    - Script effects (2026-10-27). Effects a task plays from script never showed on a puppet that plays the leader's
      animation on its slot: a fugas' vomit (`playFXOnLoopStart`), a bite's blood as it lands (`fxOnDamageInstigated`),
      a wraith's vanishing and reappearing (the teleport tasks' `disappearfxName`, `appearFXName`,
      `additionalAppearFXName`), and whatever the generic `CBTTaskPlayEffect` plays on its monster (in 54 trees:
      Shaelmaar's digging, a bruxa, Dettlaff, the giant). The leader learns those names from each attack task that
      starts, each teleport task asked whether it may start and each effect task that plays one on its own monster,
      checks every frame which of them play on its monster (`IsEffectActive`), and
      sends that set with the attack (`task|anim|time|cut|fx`), with `!hidden` while its monster is invisible
      (`GetVisibility`: a wraith between vanishing and reappearing). The member plays them on the puppet (again when
      one ended there first: the fugas replays its vomit every 0.25 s), stops those gone, and hides the puppet
      meanwhile, moving it straight to the leader's spot. `attack_view` and `enemy_attacks` with a fugas and
      `W3T_COUNTER=4` (its vomit is a counter-attack): 5 of 5 vomits on the puppet, 14-44 ms behind. A wraith
      (`wraith_lvl1`, the leader standing off at 14 m) teleported twice: its vanishing and reappearing effects played on
      the puppet, 4 of 4, 42 ms behind; it never turned invisible. Teleports with `forceInvisible` do (the leshen's
      crows, Hym, the witches), but none came in tests, so `W3T_VIEW_HIDE=5` does what they do: every 5 s the leader's
      monster turns invisible for 1.5 s and reappears 4 m aside. A drowner's puppet hid 26 of 26 times, 13 ms after
      the leader's monster (42 ms at most), and reappeared 0-0.5 m from it (`!shown/m` in the log).
    - Attacks on the graph alone (2026-10-27): a 3-state attack whose task only raises a graph event, loops, then sets
      `AttackEnd` (a fugas' vomit; `CBTTask3StateAttack` and the subclasses that keep its `Main`) has no animation
      event scripts see before its end, so nothing could name its start or loop for the slot. The leader sends its
      event and attack type with the attack (`|event:type:0`, and `|event:endType:1` once it sees `AttackEnd` go up,
      with the end's attack type); the member sets the same behavior variables on the puppet and raises the event,
      later sets `AttackEnd` too, so the same graph plays the same start, loop and end. The puppet's graph check
      (`RaiseForceEvent`) refuses the event, also every frame for 0.3 s, yet raised unchecked
      (`RaiseForceEventWithoutTestCheck`) the graph plays it. Raised in the same frame as a swing on its slot was
      stopped, the puppet kept the swing's pose for the whole attack, so then it waits 0.1 s. To tell, both sides log
      the monster's bones 0.5, 1, 1.5 and 2 s into such an attack (`LP`, `MP`); `attack_sync.py` compares them (summed
      over 15 bones, about their centre): the puppet's against the leader's monster's at the same moment, and half a
      second apart as a yardstick. A fugas' vomit (`W3T_COUNTER=4`): 2 of 2 on the puppet, error 0.02-0.14 at all four
      moments against 0.2-0.5 for other moments, started 120 ms after the leader's task was sent (about 30 ms when no
      swing was on its slot), its end 19 ms behind. A troll's rage (`CBTTask3StateWithDistAndRot`, a 6 s loop): error
      0.24 against 2.6 half a second apart, 40 ms behind, its end 26 ms behind. Hit windows of the attack on the
      puppet's graph aren't counted as its own attacks. Charges, pulls and 3-state projectile attacks stay on the slot
      (their own `Main` moves or shoots).
    - Wolves and ghouls never fought the invulnerable test leader; with `W3T_VIEW_MORTAL=1` (hit, never killed) a
      ghoul's 8 swings and a wolf's one played with the same animation, a median 30 ms behind.
  - Pose naming, for swings with no event at all before their hit window (a bear's bite hits at 0.6 s): 0.12, 0.2
    and 0.3 s into an unnamed attack, the leader compares its monster's bones (`GetBoneWorldMatrixByIndex`, model
    space, about their centre) with each swing that monster type made before (learned from hit windows), sampled
    with `GetBoneMatrixMovementModelSpaceInAnimation` at times from 0 to 0.4 s past the attack's age. It names the
    attack when the match is clear: error under 0.5 (15 bones, metres) with the next best 2.5 times that, or the next
    best 4.5 times the best. Over 200 test snapshots of bears, trolls, arachas, endregas and katakans the rule passed
    no wrong one; a wrong one would be put right by the hit window. The bear's median start went from 604 to 257 ms,
    and its hits from 298 to 33 ms behind.
  - `attack_view` per monster, measured with `attack_sync.py`. Both games and the server ran on one PC; over the
    internet, add the network's one-way delay. Start: from the leader's attack task to the puppet's animation.
    Hit window: the puppet's first, after the leader's.
    | Monster | Same animation | Start, median (p90) | Hit window, median | Start, first slot version |
    |---|---|---|---|---|
    | drowner | 13 / 13 | 24 ms (43) | 18 ms | 25 ms |
    | nightwraith | 10 / 10 | 28 ms (46) | 24 ms | 24 ms |
    | harpy | 6 / 6 | 16 ms (28) | 24 ms | 136 ms |
    | sword bandit | 12 / 12 | 24 ms (43) | 28 ms | 56 ms |
    | alghoul | 8 / 8 | 25 ms (955) | 52 ms | 84 ms |
    | werewolf | 10 / 10 | 32 ms (163) | 47 ms | 71 ms |
    | katakan | 9 / 9 | 38 ms (165) | 67 ms | 38 ms |
    | troll | 8 / 8 | 44 ms | 22 ms | - |
    | endrega | 10 / 10 | 47 ms (177) | 176 ms | 162 ms |
    | arachas | 7 / 7 | 56 ms (135) | 96 ms | 176 ms |
    | water hag | 13 / 13 | 89 ms (160) | 108 ms | 103 ms |
    | bear | 10 / 10 | 98 ms (297) | 73 ms | 362 ms |

    The troll's row is from the run before (in the last one it stayed out of combat). The water hag's swings have no
    event before their hit window at 0.05 s, so they are named there; its catch-up keeps the hit about 0.1 s behind.
    In some runs the wolf, ghoul and troll stayed out of combat in this test (the leader's monster never attacked),
    and the cyclops lost its target.
- **Moves on the slot** (2026-10-25). Every move of the leader's monster (dodge, taunt, jump-back, parry, and the
  other animated moves of its tree: strafes, counter-attacks' first parts, fear) plays with its exact animation on the
  puppet's `NPC_ANIM_SLOT`, as attacks do: sent from the event that names it, with the animation's time (the move
  field becomes `kind:param:anim:time`), caught up if it comes late. Nothing is left for the puppet's AI to make, so an
  attack after it plays at once. A mirrored hit that dealt damage stops a move on the slot (a dodged or parried hit
  deals none), for the puppet's hit reaction. A counter-attack that came as a move first isn't started again when it
  comes as an attack at its hit window. If the slot refuses a move, the puppet's own AI makes it as before.
  `enemy_moves` (sword bandit): moves shown 7 of 12 and the same animation 3 times, a median 1182 ms late (p90 3168),
  through the puppet's AI; on the slot 26 of 26, the same animation every time, a median 18-25 ms late (p90 31-37).
- **Dodges, taunts, jump-backs, parries** (2026-10-21) were made by the puppet's own AI too, like attacks (since
  2026-10-25 only when the slot refuses the move):
  - The leader sends the kind with the move: by the task class (`CBTTaskDodge`, `CBTTaskTaunt`,
    `CBTTask3StateTaunt`, `CBTTaskJumpBack`), or else by the animation's name ("dodge", "evade", "taunt",
    "jump_back"; a nekker dodges through the plain decorator). The move field becomes `kind:param:anim`, where param
    is the dodge direction (`DodgeDirection`) or the taunt type. A 0.2.0 member takes that as an unknown animation
    name and plays nothing, as before.
  - The member lifts the idle tree as for an attack, sets the dodge direction, and repeats the game's dodge warning
    ('Time2Dodge') from 0.45 s on until the puppet dodges. Right after the idle tree goes, its `CBTTaskDodge`
    activates without the animation playing (every activation at +0.25 s failed), so it is warned again if 0.9 s
    pass without the animation. A warning while it dodges would restart the dodge (`allowDodgeOverlap`).
  - Where the move is a scripted task, wraps make it the puppet's only choice: `CBTTaskDodge.Dodge` takes the
    warning for sure, in the leader's direction, and never by itself; its counter-attack branch is off.
    `CBTTaskTaunt` and `CBTTaskJumpBack` are available only while the leader's move of that kind waits.
  - Parries (`CBTTaskPerformParry` animations with "parry" in the name; its guard and counter-attack animations
    aren't parries, and counters come as attacks): the member raises the puppet's guard, warns it ('ParryStart')
    until its parry task is up (`CanParryAttack`), then parries as `CNewNPC.OnParry` does ('parryAttackType',
    'ParryPerform'), again 0.5 s on if no parry animation started. A puppet parries only then, for sure (no chance
    roll, no counter instead). The parry task took about a second to come up, and in some tries never did.
  - Its attack tasks (`CBTTaskAttack.IsAvailable`) may start only in a mirrored attack's window, and not while a
    mirrored move waits or is under way: an attack that arrives then follows when the move is over, as on the
    leader (a parry, then the counter-attack). Dropping the move for the newer attack lost most parries, since
    the leader's bandit counters 0.8 s after parrying.
  - It stands still meanwhile: the locomotion drive took the leader's monster's dodge for a run and broke the
    puppet's dodge off.
  - A move doesn't switch the puppet's target, and neither does an attack that arrives during one (until the move
    is over): each switch (`ForgetAllActors`, or the per-tick turn back from this player) restarts its combat tree.
    In a long test session, where the puppet kept picking this player, that delayed dodges to +1.5-2.5 s and only
    30 of 53 played.
  - On a member's screen, other players' swings warn no one (a `CActor.SetAttackData` wrap): the copy dodged at
    the leader's character's replayed swings by itself. The member's own swings still warn, so a copy can dodge
    the member's blade.
  - `enemy_moves` uses a Baron's sword bandit, which dodges through `CBTTaskDodge`; the test makes it dodge every
    warning and taunt every 6 s. Each mirrored move counts once the puppet's own move animation of that kind plays
    (its `OnAnimEvent`; `IsCurrentlyDodging` is set before the animation and never for a nekker). Three runs passed,
    with 9 of 11, 7 of 8 and 8 of 8 dodges played (not counting the 0, 3 and 2 that gave way to a following
    attack), and no move of the puppet's own. In the full suite's session it passed with 5 of 6. Taunts played 3 of
    5 times in the runs that had any. With parries added the test now counts dodges only (3 of 4 of at least 8);
    parries played 2 of 4, 4 of 5, 3 of 5 and 4 of 11 in four runs.
  - A nekker (`--monster ...nekker_lvl1.w2ent`, 7 minutes): its 2 dodges played on the puppet, but the puppet also
    dodged 6 times by itself. A nekker dodges through native tree nodes under the plain decorator, which the wraps
    can't hold back; these came without any warning sent, likely as its answer to the mirrored hits.
  - Before, these moves went through the slot action and never showed. The old test missed it: a nekker never
    sets `IsCurrentlyDodging`, even when it dodges.
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
  - Effects put straight on a target, not through a hit (2026-10-27), never reached members before: a fugas' vomit
    burns or poisons (`AddEffectCustom` in its loop), a charge staggers, many swings add a critical effect as they
    land (`ApplyCriticalEffectOnTarget`), a wraith's aura blinds anyone near it. The leader wraps
    `CActor.AddEffectCustom` and `AddEffectDefault`; one a shared monster puts on a member's ghost goes as a hurt of
    its own, `type:duration:add:mul` among its effects and no damage (the same effect on the same player at most
    once a second; a wraith's blindness lasts 3 s). The member adds it with that duration and value, unless it is
    dodging. `enemy_attacks` with a fugas: its burning reached the member twice and took hold (`EI_Pass`); a
    nightwraith's blindness aura reached the member standing 7 m away 14 times in `attack_view`.
  - A puppet's own effects on others are dropped in a member's world (`DropsPuppetEffect`: its aura, a task of its
    own), since the leader's come forwarded; its effects on itself stay.
  - Damage over time on a ghost was never sent, so that a burning member doesn't burn twice (the effect ticks in the
    member's own world). Ticks a task deals itself (Shaelmaar's tornado around its digging: `SetIsDoTDamage`, the
    causer a task, not an effect) now go as hurts too.
  - The effect a hit plays on its victim (`fxOnDamageVictim`: a fugas' fire, sand, sparks) rides with the hurt as
    `fx:name` and plays on the member's Geralt as it lands (`EventDamageInstigated`, wrapped). Not seen in a test
    yet: the fugas' fire comes with its vomit, which deals no hit.
- **Other players' signs.** Witcher Online replayed only the casting gesture on a remote player's copy, so nobody
  saw another player's signs.
  - Now each cast also creates the sign's own entity at the copy, only to play its effects: no projectile, no
    damage, no slowing trap. It appears 0.4 s in.
    - Igni: the fire cone. Aard: the wave. Axii: its cast and throw effects. All are removed after 3 s.
    - Yrden: the trap as the sign draws it (`CreateTrap`). Rune entities sit on a circle with one in the middle,
      on the ground where it was cast, at the caster's range. They fade out after the caster's trap duration or at
      their next Yrden.
    - Quen: its cast effect is empty in the game's template. What shows is the lasting shield on the copy
      (`lastingEffectUpgNone`/`Upg1-3` by the caster's `S_Magic_s13` level). It is up exactly while the caster's
      own shield is.
    - Whenever the caster's Quen plays its hit burst (`quen_lasting_shield_hit`: a hit on the shield, or the hit
      that breaks it) or the exploding shield's impulse (`lasting_shield_impulse`), the copy plays it too. A shield
      that runs out fades without a burst, as in vanilla.
  - Each player's snapshot carries what the copies need (fields 73-79):
    - 73: their Quen shield is up (`HasBuff(EET_BasicQuen)`). A Quen-absorbed hit plays no hit animation, so
      `lastHit` can't stand in for it.
    - 74: the sign of the last cast, recorded when the cast succeeded. `GetCurrentlyCastSign()` at snapshot time
      can differ: once, a cast while knocked into the water arrived as the previous sign.
    - 75-76: the last Yrden's range (with the Gryphon set's scale) and trap duration, read from the sign entity
      after `GetSignStats` (added getters, the fields are protected).
    - 77: the last Quen's shield level.
    - 78-79: how often their Quen's hit burst and impulse started. The sender polls its own effects every 50 ms.
  - From a game without these fields (an older version), the copy falls back to this game's own Geralt: Yrden's
    range and duration, Quen's level, and the shield goes down after this game's own Quen duration.
  - A cast is marked when `W3PlayerWitcher.CastSign` succeeds. Key presses (`OnCastSign`, `AltCastSign`) are no
    longer marked: they reach `CastSign` a few frames later through the combat action buffer, so each cast was
    sent twice, the first time before its sign was known. Casts started another way, like the test bot's, were
    never sent.
  - `sign_visuals` checks all five through `IsEffectActive` and the Yrden rune count (2026-10-20).
    - The member fights the leader's drowner, because out of combat Axii doesn't go off.
    - Screenshots show Igni's fire, Aard's wave and Yrden's runes at the copy, as in the caster's own window.
    - Axii's and Quen's lasting effects are faint at the test's 640x360 shots, in both windows.
- **Effects of members' hits** travel the other way (Igni's burning, Aard's knockdown, bombs):
  - The member reads them from its hit after the damage processor added them, and sends them with the claim, or
    alone when the hit did no damage (Aard).
  - The leader adds them to its applied hit, processed even without damage, so the monster's own resistances
    decide.
  - Damage over time stays in the member's world: its effect ticks with the member's skills and the ticks are
    claimed. On the leader, damage over time from a ghost is always dropped.
  - See Open questions: in the test games no status effect takes hold, so only the messages are verified.
  - A member's hit carries its hit reaction (2026-10-28; `r:<type>` among its effects, which an older leader takes
    for no effect): the leader's monster reacts as hit there, a heavy blow heavily and a burning tick not at all
    (every claim was a light hit before), and other members' copies replay that. `member_combat` swings heavily once
    a round: the leader applied 2 heavy hits.
  - Effects a member puts straight on a puppet, not through a hit (2026-10-28), stayed in the member's world: Axii
    confuses (and staggers) its target with `AddEffectCustom`, Yrden slows whoever stands in it, 0.1 s at a time.
    A member's Axii dazed only its copy, while the leader's monster went on attacking. The `AddEffectCustom` and
    `AddEffectDefault` wraps now send each one this player put on a puppet and that took hold, as an effect-only
    hit with its length (`type:seconds` among the hit's effects; the leader adds it with that length, its monster's
    resistances decide). Ones added while a damage action is processed are left out (they go with that hit). The
    same effect on the same puppet goes at most every 0.5 s, lasting at least 0.6 s, so Yrden's slowdown holds
    while the monster stands in it and ends shortly after. Axii's puppet skill (`EET_AxiiGuardMe`, a human fights
    for the caster) stays in the caster's world. `member_combat` now also casts Axii and Yrden: their confusion,
    stagger and slowdown went to the leader alone, and the leader's drowner was confused and slowed (each kind is
    recorded as it takes hold: the next hit, a burning tick too, ends Axii's confusion within a second, so a 1 s
    check missed it).
  - The leader's world decides which effects show on a copy (2026-10-28): one of the member's own on it that the
    leader's monster doesn't have, resisted or already ended there, goes after a second (not forced). The copy had
    stayed dazed by the member's Axii while the leader's monster, hit by a burning tick, fought on. Only with a leader
    that lists its effects (a newer version: it sends its own with `hz`). `member_combat`: 5 dropped.
  - A member who hit a shared monster is its killer when the copy dies (`Kill` with this player as attacker), so
    the kill's experience comes as for its own kill, wherever it stands. Before, as for anyone's kill, only within
    20 m of it (`ShouldGiveExp`). `shared_enemy` logs it.
- **Status effects on the leader's monster show on its copies** (2026-10-28). Before, a copy showed only the hit
  reaction: when the leader set its monster on fire, knocked it down with Aard or froze it, members saw it standing
  as before. The leader now lists its monsters' effects that show (`CoopShowsEffect`: burning, frozen, knockdowns,
  staggers, ragdoll, blindness, Axii's confusion and its slowdown, immobilized, paralyzed, tangled, poison, bleeding,
  Yrden's and frost slowdown, Moon Dust) with its script effects, `!e<type>:<seconds>` each (the length as applied),
  sent at once when the list changes. The member puts each on the copy with that length (`AddEffectCustom`, source
  `W3CoopShown`, the copy as its creator) and takes it off when it leaves the list, not forced, so a knockdown's
  animation finishes as it would. One the member's own hit put there already stays as it is; their damage over time
  on the copy is dropped like any not the member's, and a released twin loses them.
  - `enemy_effects`: the leader gives its immortal drowner burning, knockdown, frozen, blindness, confusion and
    bleeding, 6 s apart. All five the drowner took (it refused bleeding) were on the copy a median 23 ms later
    (max 32 ms) and were taken off 26 ms after they ended there. Screenshots show the copy burning, lying knocked
    down and frozen in ice, as the leader's drowner.
- **Other players' bombs and crossbow bolts** (2026-10-28). Witcher Online showed only the throw or aim animation
  on a remote player's character; the bomb, its explosion and the bolt were seen by the thrower alone. Each player's
  game now sends its own bombs (`W3Petard.ThrowProjectile` with this player as owner: the item, where it left the
  hand, where it goes) and shots (a projectile this player fired, caught by the projectile wraps: its template,
  start, target, angle, speed and range; a shot at a bone goes to that bone) on a channel of its own, `pt epoch n
  {seq kind what from to angle speed range}`: those of the last 1.5 s, at once. Once none is left the message goes
  out empty, so that a stale one never plays for a player who comes near later. Every other game near that player
  throws a copy from their character there: a bomb from its own inventory item (`GetDeploymentItemEntity`, the
  character its owner), a shot from the template, as for monster projectiles. A copy's hits are dropped everywhere
  (the attacker a player's character, the causer a throwable or projectile): the real ones reach the leader as the
  thrower's claims, and their effects show on the copies through the leader's monster (above). Blocked abilities
  (Moon Dust, Dimeritium) are not damage, so a copy exploding at the leader's monster blocks them there too.
  Cluster bomblets (an alchemy skill) spawn only in the thrower's world.
  - `member_combat` now also throws a Dancing Star and shoots a bodkin bolt at the copy: both hits were claimed and
    applied (the bolt for 56 of 882 health), and the leader's game threw a copy of each (6 of 6 in a longer run, none
    failed) whose damage it dropped. The leader's screenshots show the copy's fire burst at its drowner.
  - Test gotcha: an immortal monster drained to nothing lies unconscious, and bolts pass it by (`CanCollideWithVictim`);
    the burning ticks claimed in `member_combat` drained it within seconds, so its leader now heals it below half
    health. A bolt also stops at once if it starts inside its shooter.
- **Matching an encounter that exists in both worlds.** Unmatched local hostiles near a member are hidden and
  idle. When the leader's copy of one appears, the member's own monster is found (same template, within 10 m),
  shown again and made the puppet. No duplicate is spawned.
  - Real encounter (`real_encounter`, 2026-10-19). Both bots teleported to the nearest active monster nest from
    the map pins: `lw_nest_ep1_poi_31_mp`, 1 km from the save.
  - Each world's own encounter spawned 5 nekkers (`nekker_lvl5_customize_ep1`). On the member all 5 bound as
    twins: none spawned, none left visible beside them.
  - When the leader killed its 5, the 5 puppets died within half a second.
  - Test setup: after the 1 km teleport, the bots wait 6 s for the navigation mesh, then stand on a walkable spot
    near the nest. A raw offset from the pin was a cliff edge, and the member kept sliding 30 m down, so puppets
    were released and rebound each time. They also return to the spot if they fall through the ground.
- **Movement.** Puppets slide to the leader's positions with the movement adjustor (a 0.15 s slide per frame
  toward the latest 10 Hz snapshot, a teleport beyond 12 m). While sliding they walk and run on their own legs:
  - The member estimates how fast the leader's monster moves from successive snapshots.
  - It sets the puppet's gameplay move speed (`SetGameplayRelativeMoveSpeed`) and direction, as Witcher Online
    does for horses: 1 (walk) up to 2 m/s, 2 (run) up to 4.5 m/s, 3 above.
  - The speed is 0 when the monster stands, while a mirrored attack plays, and when no snapshot came for 0.5 s.
  - The monster's behavior graph picks its own walk or run animation. No engine patch was needed.

  Measured as stride: a foot's swing along the facing, relative to the pelvis (or torso) of the same pose, over
  1.5 s windows while moving. Skeletons without `l_foot`/`r_foot` use the bones nearest four points at foot height
  around the body. `puppet_walk` (2026-10-19, 2 clients on one PC; leader's monster vs member's puppet, and the
  largest momentary gap):

  | Monster | Leader's stride | Puppet's stride | Largest gap |
  |---|---|---|---|
  | drowner | 1.48 m | 1.42 m | 1.73 m |
  | wolf | 0.83 m | 0.74 m | 0.75 m |
  | nekker | 1.76 m | 1.42 m | 1.33 m |
  | ghoul | 1.48 m | 1.12 m | 0.91 m |
  | endrega worker | 1.05 m | 1.17 m | 0.52 m |
  | cave troll | 1.13 m | 1.04 m | 0.46 m |
  | werewolf | 2.60 m | 2.42 m | 1.17 m |

  With locomotion off (`puppet_glide`, slide only) the puppets' strides were 0.11 m (drowner; its leader's
  1.42 m) and 0.12 m (nekker; 1.75 m).
  - Human enemies work the same way. A Baron's bandit
    (`gameplay\community\community_npcs\nml\regular\baron_bandit_strong_sword.w2ent`) passes `puppet_walk`:
    leader's stride 1.25 m, puppet 0.91 m. It circles and sidesteps before closing in, and its puppet follows
    within 0.36 m. `crowd_npc` templates (bandit, Skellige pirate, Nilfgaardian squire) spawned alone stand idle
    in combat, so tests need a community template.
  - Leaps show a gap until the next slide catches up: a nekker's 9.8 m leap gave one 9.8 m sample, and the
    next was 0.4 m. The test therefore fails only on a gap above 3.5 m that lasts a second.
  - Tried and dropped: moving puppets through the AI (`CAIMoveToPoint` at `BTAP_Emergency`, as cutscenes do). The
    forced move never moved a puppet, with or without `enterExplorationOnStart`, and the gaps grew to 8 m.
  - `GetRelativeMoveSpeed` and `GetVelocity` read 0 for monster NPCs even while they run, so speeds come from
    positions.
- **Other moves** are mirrored like attacks: dodges, jump-backs, taunts, fear, parries, shots, and wraith and
  wyvern moves.
  - Capture: these behavior-tree tasks share `CBTTaskPlayAnimationEventDecorator`. The leader wraps its
    `OnAnimEvent`, which carries the animation's name, and sends each new animation (or a restart) as
    `moveSeq`/`moveAnim` with the enemy. Attack and hit-reaction tasks keep their own paths.
  - Playback (since 2026-10-25): every move plays with the leader's animation on the puppet's slot, as attacks do
    (`SlotMove`); before, dodges, taunts, jump-backs and parries were made by the puppet's own AI (above) and the rest
    went through the slot action, which plays nothing.
  - Moves faster than the 10 Hz snapshots collapse into the newest. (The leader now also sends a move from the event
    that names it, so a new one goes out at once.)
  - `enemy_moves` tells the leader's monster every 2 s that an attack is coming, as the game tells a target.
    Moves seen on the leader and played on the puppet (2026-10-19), none refused:

    | Monster | Moves |
    |---|---|
    | nekker | `c_dodge250_2`, `c_dodge250_3` |
    | werewolf | `monster_werewolf_dodge_b01` |
    | wolf | `wolf_taunt_02` |
    | cave troll | `monster_cave_troll_taunt_1` |
    | Baron's bandit | `man_npc_sword_1hand_taunt_7_left`, `..._8_left` |

    A drowner that keeps attacking never dodged.
- **Attacks of other enemy types:** `enemy_attacks --monster` passes with a Baron's bandit (4 sword swings
  mirrored, 3 hits landed), a nekker and a cave troll. A wolf mirrored 40 attacks but then chased the Novigrad
  citizens around the test spot, so its second hit on the ghost never came.
- **Projectiles** (arrows, bolts, spit, boulders, fireballs: everything derived from `W3AdvancedProjectile`).
  - Capture: the leader wraps the class's four shoot functions. A shared monster's shot is sent with the enemy
    for 1.5 s: projectile template, start, target, angle, speed and range.
  - Playback: members create the same projectile at the same spot with the puppet as caster, damage and effect
    zeroed, and shoot it the same way.
  - Damage: the hit arrives as a hurt from the leader, and a puppet's own damage is dropped anyway.
  - `enemy_projectiles` (2026-10-19): Baron's bandit with a bow (2 arrows copied, 1 hit landed on the member),
    with a crossbow (bolts) and a poison arachas (venom). A tailed endrega only fought in melee.
  - Shots faster than the snapshots collapsed into the newest (the arachas fired 8, and the member saw 2); each shot
    now goes out with the next frame's snapshot: Shaelmaar's rain of rocks (2026-10-27, at 40% health) came 187 for
    187.
- **Summons.** A summoned creature is a hostile NPC near the leader like any other, so the leader collects it and
  members get a copy. Verified 2026-10-28: `enemy_summons --monster ...lessog_lvl1.w2ent` (the leader swings at the
  leshen for 6 s, then stands off at 11 m for 6 s, in turn: up close it only swung, 140 times in 5 minutes) summoned
  wolves (`wolf_lvl1__summon`) after 3 minutes; 4 s later the leader shared 3 of them and the member had 3 wolf
  copies. A Novigrad guard who joined the fight was collected and copied too. A puppet never starts its own summon
  task (its gate, above).
- **Not done:**
  - Shaelmaar's swings play on its puppet now (2026-10-27, `attack_view`: 12 of 12 with the leader's animation,
    0.26-0.58 s late: its swings show nothing before a RotateEvent or their hit window, and its two shoulder swings
    look too alike early for pose naming). At 40% health (`W3T_MONSTER_HP=0.4`, the leader standing off at 12 m) it
    also digs in and shakes the ground (`CBTTaskTornadoAttack` with a 3-state animation, which reaches the puppet as
    moves, 20-30 ms behind; its tremor effects 42-50 ms behind), confusing and hurting everyone near it (with the
    member its target in `enemy_attacks`: 6 confusions and 22 damage ticks reached the member), and rains rocks
    (99 of 99 and 187 of 187 copied). Its charges (7-16 m, moving slowly) never came. The puppet's AI had also
    swung on its own during the digging; a plain swing no longer stands in for an attack whose animation came to the
    slot as moves. The fairytale witch and the black mage never
    fought at the test spot, not even hit (`W3T_VIEW_PROVOKE`) or with a leader that can be hit; the offset spawns
    of two bosses (Dettlaff, the toad) weren't tried;
  - moves that are not behavior-tree tasks (scripted encounter animations);
  - (hit reactions, best effort at first: one of two mirrored hits showed `IsInHitAnim` in the 2026-10-19 test.
    Measured again 2026-10-28 with `W3T_REACT_HITS=16 run_test.py reactions`, light and heavy hits in turn while the
    drowner attacked: the leader's drowner flinched at all 16 and its copy at the same 16, none other, a median 50 ms
    after the leader's (max 76 ms; `attack_sync.py` matches LR/MR to each hit).)

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

### As built (journal and facts; tests pass)

- **What can be captured.** `FactsAdd` is a native import, so scripts cannot wrap it, and quest graph fact blocks
  write to the facts database without any script involved. So facts are read from the database itself (below).
  The journal is reachable from scripts: the native journal reports every quest and objective update to the
  HUD (`CR4ScriptedHud.OnQuestEvent` / `OnQuestObjectiveEvent`), including the quest system's own.
- **Facts sync.** The client ASI reads the engine's facts database, without hooks, on the game thread when a
  script asks:
  - **Finding it.** The facts natives reach the database as `game->systems[1]` (`FactsQuerySum`: `mov rax,[game];
    cmp [rax+0xFDC0],1; mov rax,[rax+0xFDB8]; mov rsi,[rax+8]`). The client finds that code by a byte pattern and
    takes the global and both offsets from the matched bytes.
  - **Layout on 5.01**, found by probing with a known fact, a before/after memory diff and node dumps:
    - the facts map is at `+0x58`, with the fact count at `+0x64`;
    - its nodes come from one pool, `[+0x68, +0x80)`, with node size `0x28` at `+0x74` and free slots linked from
      `+0x78` via `+0x20`;
    - a node (pack 4) has the key text at `+0x00`, the key size at `+0x08`, the entries at `+0x0C`, the entry
      count at `+0x14` and the link at `+0x20`;
    - entries are 24 bytes, with the int value first.
  - **Safety.** Every read is guarded. If the used slots don't add up to the map's fact count, nothing is reported
    and sync stays off; a different game build disables it instead of misreading it.
  - **Sending.** `WO_FactsBaseline()` records every fact's sum when a save is loaded (8,078 facts on the test save,
    under a millisecond). `WO_FactsPage(40)` returns the facts changed since then, a page per call in turn. The
    leader sends a page every 0.5 s on `fx`, so a late member gets all pages.
  - **Applying.** Members raise a fact to the leader's sum with `FactsAdd`, never lower it, so a member who is
    further along keeps its value. Fact expiry is ignored: all entries are summed.
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

Tests (2026-10-19, 2 clients):
- `quest_sync` PASS. The leader activated an inactive objective before the member joined. The member joined 15 s
  later and had the objective, at the same status, 2 s after joining.
- `facts_sync` PASS. A fact set before the member joined arrived 1 s after joining, and one set afterwards 1 s
  after it was set. A fact the leader's game had changed by itself came along too.

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

## Many monsters at once (2026-10-28)

The leader shared at most 24 monsters; a member hides its own monsters the leader doesn't share, so in a bigger fight
some were invisible to the member while they fought the leader. `enemy_crowd` spawned 24 drowners around the
member's character: the member copied all 24 and both games kept full speed, and the leader's snapshot was at most
2.7 KB (about 110 bytes a monster). The limit is 48 now (as many as its search finds near each player); with 40
drowners all 40 were copied, the snapshot was at most 3.8 KB, and both games kept full speed. The server and the client read each datagram into 8192 bytes, and co-op messages are sent whole, so one
over 8 KB was cut; that takes nearly every monster in the middle of an attack with effects and a projectile in the
air at once. Both now read up to 64 KB (`server_coop_test.py` sends a 20 KB message through the server). The Steam
relay already took 64 KB.

## A member's death (2026-10-28)

A member killed by a shared monster gets the game's own death screen and loads its last save, as in single player
(Witcher Online has no death handling). `member_death` (the member joins with little health and no immortality, the
leader's immortal drowner kills it, the death screen's respawn loads the save) found:
- The party, the co-op state and the monster copies survive the load: about a second after the member is in the
  world again it is in the party, with its copy of the leader's drowner.
- Witcher Online keeps the dead member's character in the leader's world through the load, and the leader's
  monster went on hitting it: 11 hurts piled up in the 40 s of death screen and loading, and landed together as the
  member respawned (5965 health down to 249), so it died again at once, over and over.
- Now the leader leaves a dead member's character alone (it is disarmed: out of gameplay sight and friendly, by the
  member's own snapshot field `isAlive`), sends no hurts for it and drops those still waiting, and a member drops
  any that arrive while it is dead. In the test 1 hurt was dropped, the member respawned with 5140 health and
  fought on.
- The leader's death needed nothing new (`leader_death`): its game pauses on the death screen, so its snapshots stop
  and members let go of its monsters 8 s later (their own take over); after the leader's respawn its new monsters
  are shared again, and the member stayed in the party throughout.

## Presence on 5.01: horses, chat, emotes (2026-10-28)

Witcher Online's own presence features, first tested on the port with `horse_ride` and `social`:
- **Riding.** A rider's copy sits on Witcher Online's horse for remote riders
  (`dlc\dlc_mpmod\data\entities\horse_vehicle.w2ent`, appearance from the rider's menu choice), which slides after
  the rider's position: 0-0.24 m apart within a second, also in a party (screenshots show it drawn).
- **The horse left behind.** Witcher Online hid that horse when its rider got off, so others never saw a player's
  horse standing (reported by the owner). Each player's game now sends where its own horse stands while not ridden
  and within 100 m (`coop hz seq 1 x y z yaw`, or `hz seq 0`, on change and every 2 s; the count makes each one new,
  since the client passes a channel's message on only when it changed). The others keep the horse in sight there,
  following the real one when it wanders, and hide it again on `0` or after 5 s without word. A horse made this way
  loads its rider's AI when the rider mounts it (as Witcher Online's own spawn does), so the rider still sits on it.
  The server keeps up to 8 co-op channels per player (was 4: a leader already used en, hurt, jr, fx). `horse_ride`:
  the rider gets off and walks 6 m away; the watcher sees the horse where it was left within 1 s, the rider 6 m off.
- **A player's own effects** (2026-10-28). Witcher Online showed nothing of them: a burning or frozen player looked
  as always to the others, and a knocked-down one stood. Each player now sends its effects that show (the same set
  as for monsters, `type:seconds` each, `-` for none) with its horse's place on `hz` (`hz seq flag x y z yaw
  effects`, the horse fields zero without one): at once when they change. The others put each on that player's
  character as long as it lasts there (source `W3CoopShown`, the character its creator, so its damage over time is
  dropped like any a player's character deals), and take it off when it ended (not forced). `player_effects`: the
  member burns, is knocked down, frozen and poisoned in turn; on the leader all four were on its character and
  ended with it, and screenshots show the fire, the knockdown and the frozen look.
- **Trading** (2026-10-28, `trade`). Witcher Online's own trade works on 5.01: the leader offered a Dwarven spirit to
  the member through its item popup and price slider (10 crowns), the member's game showed the offer and accepted
  it; the leader had one spirit less and 10 crowns more, the member one more and 10 crowns less. The bot answers the
  popups as they open (`w3test.ws`), so how they look is not checked.
- **Chat and emotes.** A chat line showed over the sender's copy within 0.2 s; a wave and a bow played on it
  0.17-0.18 s after they were made (Witcher Online resets the emote number to -1 once played; the number played
  stays as `prevEmote`).

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
| facts_sync | PASS | PASS |
| puppet_walk | PASS (stride: leader's drowner 1.34 m, puppet 1.57 m) | PASS (1.42 m, 1.54 m) |
| enemy_moves | PASS (nekker dodge `c_dodge250_2` mirrored) | PASS (the same dodge) |
| real_encounter | PASS (5 nekkers at a real nest: 5 bound as twins, all died with the leader's) | PASS (3 bound, 2 spawned where the member's world had fewer; all died) |
| enemy_projectiles | PASS (bow bandit: 2 arrows copied, hits landed) | PASS |
| member_combat | PASS (real sword swings, Igni, Aard; forwarded effects added) | PASS |
| sign_visuals | PASS (Igni fire and Aard wave active on both sides) | PASS |

Latest runs (2026-10-20, after sign visuals): 16/16 over real Steam. Locally, 15 of 16 passed in the full run;
enemy_moves failed once (its nekker never paused attacking to dodge) and passed twice after a test fix. The 4
scenarios that share that spawn code were rerun and passed. Also passing: `server_coop_test.py` (server
co-op channel, no game) and `relay/selftest.py`. Over Steam, every run joined the host's lobby through the second
account, and traffic flowed both ways.

## Open questions

- Members' damage. Real sword swings and Igni/Aard casts on a puppet are claimed and applied (`member_combat`,
  2026-10-20), and so are a bomb's and a crossbow bolt's (2026-10-28, thrown and shot by the test bot from its
  inventory as the game does; a real player's aimed throw and shot are untested).
- Status effects: solved 2026-10-21. No status effect took hold in the test games because of a Steam Workshop
  mod the owner had subscribed to, not because of the test setup or Witcher Online:
  - "Consumables Balanced" (Workshop item 3252471752, `modConsumablesBalanced`) ships its own
    `gameplay\abilities\effects.xml` (and `abilities_plus\effects.xml`). It replaces the game's effect list:
    72 effects were loaded instead of 154, without `BurningEffect`, `KnockdownEffect`, `BleedingEffect` and the
    other core ones, so every such effect was made with duration 0 and denied. This hits a normal game too, since
    Workshop mods load there as well.
  - With it off in the test sandbox (`W3T_DISABLE_MODS=modConsumablesBalanced`), `sign_check` shows burning,
    stagger and bleeding taking hold, and Igni sets a drowner on fire on every cast.
  - Effect forwarding then works both ways: in `member_combat` the member's Igni and Aard hits carried 6 effects
    to the leader's drowner, 3 held, and it burned; in `reactions` the leader's drowner's bleeding hit made the
    member bleed.
- Encounter matching is tested with script-spawned twins and one real nest (nekkers). An encounter that came out
  differently in the member's world (`encounter_mismatch`, 2026-10-28: a nekker there, a drowner in the leader's at
  the same spot): the member's nekker stayed hidden and idle, not a copy, and the leader's drowner came as a spawned
  copy. Random sets in real encounters are still untested.
- The facts layout is from 5.01; a game patch that changes it turns fact sync off (logged as the reason) until
  the layout is checked again.
