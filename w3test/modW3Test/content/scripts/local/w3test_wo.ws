// Witcher Online state for the test bot's per-second report, and the scenario pass conditions.


function W3T_ScenarioCheck(bot : W3T_Bot) : bool
{
    var scenario : string = W3T_GetEnv("W3T_SCENARIO");
    var client : r_MultiplayerClient = theGame.r_getMultiplayerClient();
    var players : array<r_RemotePlayer>;
    var ghosts : int;
    var i : int;

    if(!client || !client.getInGame())
    {
        return false;
    }

    if(scenario == "smoke")
    {
        return true;
    }
    if(scenario == "sign_check")
    {
        return W3T_SignCheck(bot);
    }


    players = client.getPlayers();
    for(i = 0; i < players.Size(); i += 1)
    {
        if(players[i].ghost)
        {
            ghosts += 1;
        }
    }

    if(scenario == "facts_sync")
    {
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_FactsLeader(bot, client.getCoopEnemies());
        }
        if(ghosts < 1)
        {
            return false;
        }
        return W3T_FactsMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "puppet_follow" || scenario == "puppet_walk" || scenario == "puppet_glide")
    {
        client.getCoopEnemies().SetPuppetLocomotion(scenario != "puppet_glide");
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_MovesLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_FollowMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "see_each_other")
    {
        return ghosts >= StringToInt(W3T_GetEnv("W3T_PEERS"), 1);
    }

    if(scenario == "movement")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_MoverStep(bot);
        }
        return W3T_ObserverStep(bot, players[0]);
    }

    if(scenario == "shared_enemy")
    {
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_SharedEnemyLeader(bot, client.getCoopEnemies());
        }
        if(ghosts < 1)
        {
            return false;
        }
        return W3T_SharedEnemyMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "enemy_attacks")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_EnemyAttacksLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_EnemyAttacksMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "real_encounter")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_EncounterLeader(bot, client.getCoopEnemies());
        }
        return W3T_EncounterMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "sign_visuals")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            W3T_LookAt(players[0].ghost.GetWorldPosition());
            W3T_Log("SIGNFX leader played=" + client.getCoopEnemies().signVisualsPlayed + " active=" + client.getCoopEnemies().signVisualsActive);
            return client.getCoopEnemies().signVisualsActive >= 2;
        }
        return W3T_SignVisualsMember(bot);
    }

    if(scenario == "member_combat")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_CombatLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_CombatMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "enemy_projectiles")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_ProjectilesLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_ProjectilesMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "enemy_moves")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_EnemyMovesLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_EnemyMovesMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "dialog_sync")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_DialogLeader(bot, client.getCoopEnemies());
        }
        return W3T_DialogMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "quest_sync")
    {
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_QuestLeader(bot, client.getCoopEnemies());
        }
        if(ghosts < 1)
        {
            return false;
        }
        return W3T_QuestMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "reactions" || scenario == "twin_match")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(scenario == "reactions" && W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_ReactionsLeader(bot, client.getCoopEnemies(), players[0]);
        }
        if(scenario == "reactions")
        {
            return W3T_ReactionsMember(bot, client, client.getCoopEnemies(), players[0]);
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_TwinLeader(bot, client.getCoopEnemies());
        }
        return W3T_TwinMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    // the players are out of each other's sight for part of this one: no ghost needed
    if(scenario == "handoff")
    {
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_HandoffLeader(bot, client.getCoopEnemies(), players, client.getGlobalPlayers());
        }
        return W3T_HandoffMember(bot, client, client.getCoopEnemies(), players);
    }

    W3T_Log("FAIL unknown scenario " + scenario);
    W3T_Quit(2);
    return false;
}

// Mover: once the peer is visible, teleport 6 m back and forth along X every 8 s for the whole run, so an
// observer that arrives late still sees a move. Passes after two moves.
function W3T_MoverStep(bot : W3T_Bot) : bool
{
    var target : Vector;

    if(!bot.scenarioFlag)
    {
        bot.scenarioVec = thePlayer.GetWorldPosition();
        bot.scenarioFlag = true;
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }

    if(bot.ElapsedS() - bot.scenarioTime >= 8.0)
    {
        target = bot.scenarioVec;
        if(bot.scenarioCount % 2 == 0)
        {
            target.X += 6.0;
        }
        thePlayer.Teleport(target);
        bot.scenarioCount += 1;
        bot.scenarioTime = bot.ElapsedS();
        W3T_Log("MOVE " + bot.scenarioCount + " teleported to " + W3T_VecStr(target));
    }
    return bot.scenarioCount >= 2;
}

// Observer: counts moves of the peer's ghost (more than 4 m from where it last settled, and within 2 m of the
// position the peer reports over the network). Passes after two moves; works at any tick rate.
function W3T_ObserverStep(bot : W3T_Bot, peer : r_RemotePlayer) : bool
{
    var ghostPos : Vector;

    if(!peer.ghost)
    {
        return bot.scenarioCount >= 2;
    }
    ghostPos = peer.ghost.GetWorldPosition();
    if(!bot.scenarioFlag)
    {
        bot.scenarioVec = ghostPos;
        bot.scenarioFlag = true;
        W3T_Log("WATCH first ghost position " + W3T_VecStr(ghostPos));
    }
    else if(VecDistance(ghostPos, bot.scenarioVec) > 4.0 && VecDistance(ghostPos, peer.pos) < 2.0)
    {
        bot.scenarioCount += 1;
        bot.scenarioVec = ghostPos;
        W3T_Log("WATCH move " + bot.scenarioCount + ": ghost at " + W3T_VecStr(ghostPos) + " network " + W3T_VecStr(peer.pos));
    }
    return bot.scenarioCount >= 2;
}

// shared_enemy, leader: once a member joined the party, spawn a drowner 6 m ahead; after the member's three
// hits are applied here, kill it. Passes a few seconds after the kill (members need the death in a snapshot).
function W3T_SharedEnemyLeader(bot : W3T_Bot, coop : r_CoopEnemies) : bool
{
    var template : CEntityTemplate;
    var drowner : CNewNPC;
    var pos : Vector;
    var rot : EulerAngles;

    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1)
        {
            return false;
        }
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
        if(!template)
        {
            W3T_Log("FAIL drowner template not found");
            W3T_Quit(2);
            return false;
        }
        // the cheat channel: combat code resets the default one
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        pos = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 6.0;
        rot = thePlayer.GetWorldRotation();
        bot.scenarioEntity = theGame.CreateEntity(template, pos, rot, true, false, false, PM_DontPersist);
        drowner = (CNewNPC)bot.scenarioEntity;
        W3T_Log("ENEMY spawned drowner at " + W3T_VecStr(pos) + " readable='" + drowner.GetReadableName() + "'");
        bot.scenarioCount = 1;
        return false;
    }

    drowner = (CNewNPC)bot.scenarioEntity;
    if(!drowner)
    {
        W3T_Log("FAIL drowner is gone");
        W3T_Quit(2);
        return false;
    }
    W3T_Log("ENEMY leader netId=" + coop.HostNetIdOf(drowner) + " hp=" + FloatToStringPrec(drowner.GetHealthPercents(), 4)
        + " alive=" + drowner.IsAlive() + " hitsApplied=" + coop.hitsApplied + " pos=" + W3T_VecStr(drowner.GetWorldPosition()));

    if(bot.scenarioCount == 1 && coop.hitsApplied >= 3)
    {
        bot.scenarioCount = 2;
        bot.scenarioTime = bot.ElapsedS();
    }
    else if(bot.scenarioCount == 2 && bot.ElapsedS() - bot.scenarioTime >= 3.0)
    {
        W3T_Log("ENEMY leader kills the drowner at hp=" + FloatToStringPrec(drowner.GetHealthPercents(), 4));
        drowner.Kill('W3T', true);
        bot.scenarioCount = 3;
        bot.scenarioTime = bot.ElapsedS();
    }
    return bot.scenarioCount == 3 && !drowner.IsAlive() && bot.ElapsedS() - bot.scenarioTime >= 3.0;
}

// shared_enemy, member: join the leader's party, then hit the drowner's puppet three times through the damage
// manager. This game's stats scale each hit; the leader's health must drop by exactly the fraction this game
// sent (within 2 %). Then the puppet must die when the leader kills it, with no second drowner in this world.
function W3T_SharedEnemyMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var action : W3DamageAction;
    var puppet : CNewNPC;
    var entities : array<CGameplayEntity>;
    var npc : CNewNPC;
    var hp : float;
    var index, others, i : int;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }

    index = -1;
    for(i = 0; i < coop.PuppetCount(); i += 1)
    {
        if(coop.PuppetAt(i) && StrFindFirst(coop.PuppetAt(i).GetReadableName(), "drowner_lvl1") >= 0)
        {
            index = i;
        }
    }
    if(index < 0)
    {
        return bot.scenarioCount >= 5;
    }
    puppet = coop.PuppetAt(index);
    hp = coop.PuppetHostHp(index);
    W3T_Log("ENEMY member puppet hp=" + FloatToStringPrec(hp, 4) + " local=" + FloatToStringPrec(puppet.GetHealthPercents(), 4)
        + " alive=" + coop.PuppetAlive(index) + " spawned=" + coop.PuppetSpawned(index) + " pending=" + coop.PendingHitCount()
        + " pos=" + W3T_VecStr(puppet.GetWorldPosition()));

    // scenarioCount: hits confirmed so far (0-3), then 5 once the death was seen; scenarioFlag: a hit in flight
    if(bot.scenarioCount < 3)
    {
        if(!bot.scenarioFlag)
        {
            coop.lastHitFrac = 0;
            action = new W3DamageAction in theGame.damageMgr;
            action.Initialize(thePlayer, puppet, thePlayer, "W3T", EHRT_Light, CPS_Undefined, true, false, false, false);
            action.AddDamage(theGame.params.DAMAGE_NAME_DIRECT, 0.04 * puppet.GetMaxHealth());
            theGame.damageMgr.ProcessAction(action);
            delete action;
            if(coop.lastHitFrac <= 0)
            {
                W3T_Log("FAIL hit " + (bot.scenarioCount + 1) + " was not captured for the leader");
                W3T_Quit(1);
                return false;
            }
            bot.scenarioValue = MaxF(0, hp - coop.lastHitFrac);
            bot.scenarioFlag = true;
            bot.scenarioTime = bot.ElapsedS();
            W3T_Log("HIT " + (bot.scenarioCount + 1) + " sent: " + FloatToStringPrec(coop.lastHitFrac, 4)
                + " of max health after this game's stats, expect hp " + FloatToStringPrec(bot.scenarioValue, 4));
        }
        else if(coop.PendingHitCount() == 0 && bot.ElapsedS() - bot.scenarioTime >= 2.0)
        {
            if(AbsF(hp - bot.scenarioValue) > 0.02)
            {
                W3T_Log("FAIL hit " + (bot.scenarioCount + 1) + ": leader reports hp " + FloatToStringPrec(hp, 4)
                    + ", expected " + FloatToStringPrec(bot.scenarioValue, 2));
                W3T_Quit(1);
                return false;
            }
            bot.scenarioCount += 1;
            bot.scenarioFlag = false;
            W3T_Log("HIT " + bot.scenarioCount + " confirmed by the leader: hp " + FloatToStringPrec(hp, 4));
        }
        return false;
    }

    if(bot.scenarioCount == 3 && !coop.PuppetAlive(index) && !puppet.IsAlive())
    {
        FindGameplayEntitiesInSphere(entities, puppet.GetWorldPosition(), 20.0, 32, '', FLAG_OnlyAliveActors, thePlayer);
        for(i = 0; i < entities.Size(); i += 1)
        {
            npc = (CNewNPC)entities[i];
            if(npc && npc != puppet && StrFindFirst(npc.GetReadableName(), "drowner_lvl1") >= 0)
            {
                others += 1;
            }
        }
        if(others > 0)
        {
            W3T_Log("FAIL " + others + " other drowner(s) alive next to the puppet");
            W3T_Quit(1);
            return false;
        }
        W3T_Log("ENEMY member saw the drowner die; no duplicate");
        bot.scenarioCount = 5;
    }
    return bot.scenarioCount >= 5;
}

// a spot on the navmesh about `range` m from `from` with a clear walkable line back to it (W = 0 if none)
// the monster the leader's scenarios spawn: W3T_MONSTER (run_test.py --monster) or a drowner. Human enemies need a
// template with real combat AI, e.g. gameplay\community\community_npcs\nml\regular\baron_bandit_strong_sword.w2ent
// (crowd_npc ones spawned alone stand idle in combat)
function W3T_MonsterPath(optional fallback : string) : string
{
    if(W3T_GetEnv("W3T_MONSTER") != "")
    {
        return W3T_GetEnv("W3T_MONSTER");
    }
    if(fallback != "")
    {
        return fallback;
    }
    return "characters\npc_entities\monsters\drowner_lvl1.w2ent";
}

// a walkable spot 12-14 m from `from`, with a free path to it, as near the middle of the screen as there is one
// (both bots load the same save, so their cameras look the same way: in view for screenshots); W = 0 if none
function W3T_SpotInView(from : Vector) : Vector
{
    var spot, safe, best : Vector;
    var x, y, bestX : float;
    var i, r : int;

    bestX = 2;
    for(r = 12; r <= 14; r += 2)
    {
        for(i = 0; i < 32; i += 1)
        {
            spot = from + VecFromHeading(i * 11.25) * r;
            if(theGame.GetWorld().NavigationFindSafeSpot(spot, 0.5, 2.0, safe) && theGame.GetWorld().NavigationLineTest(from, safe, 0.5)
                && theCamera.WorldVectorToViewRatio(safe, x, y) && AbsF(x) < bestX && AbsF(y) < 0.9)
            {
                bestX = AbsF(x);
                best = safe;
                best.W = 1;
            }
        }
    }
    return best;
}

function W3T_WalkableSpot(from : Vector, range : float) : Vector
{
    var spot, safe : Vector;
    var i : int;

    for(i = 0; i < 16; i += 1)
    {
        spot = from + VecFromHeading(i * 22.5) * range;
        if(theGame.GetWorld().NavigationFindSafeSpot(spot, 0.5, 3.0, safe) && theGame.GetWorld().NavigationLineTest(from, safe, 0.5))
        {
            safe.W = 1;
            return safe;
        }
    }
    spot.W = 0;
    return spot;
}

// turns the camera toward a spot, for screenshots (run_test.py --shots)
function W3T_LookAt(target : Vector)
{
    theGame.GetGameCamera().GetActivePivotRotationController().SetDesiredHeading(VecHeading(target - thePlayer.GetWorldPosition()));
}

// enemy_attacks, leader: spawn a drowner next to the member's ghost (12-14 m away if `far`: archers close by fight
// in melee), neutral to this Geralt so the ghost is its only target. Passes once at least two of its hits on the
// ghost were sent and acknowledged.
function W3T_EnemyAttacksLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer, optional fallback : string,
    optional far : bool) : bool
{
    var template : CEntityTemplate;
    var drowner : CNewNPC;
    var target : CActor;
    var targetName : string;
    var pos : Vector;
    var rot : EulerAngles;

    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1 || !member.ghost)
        {
            return false;
        }
        template = (CEntityTemplate)LoadResource(W3T_MonsterPath(fallback), true);
        if(!template)
        {
            W3T_Log("FAIL no template " + W3T_MonsterPath(fallback));
            W3T_Quit(2);
            return false;
        }
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        if(far)
        {
            pos = W3T_SpotInView(member.ghost.GetWorldPosition());
        }
        if(pos.W == 0)
        {
            pos = member.ghost.GetWorldPosition() + VecFromHeading(member.ghost.GetHeading()) * 3.0;
        }
        rot = member.ghost.GetWorldRotation();
        bot.scenarioEntity = theGame.CreateEntity(template, pos, rot, true, false, false, PM_DontPersist);
        drowner = (CNewNPC)bot.scenarioEntity;
        drowner.SetAttitude(thePlayer, AIA_Neutral);
        drowner.SetAttitude(member.ghost, AIA_Hostile);
        if(far)
        {
            drowner.NoticeActor(member.ghost);  // humans 12 m away don't notice it by themselves
        }
        W3T_Log("ENEMY spawned " + W3T_MonsterPath(fallback) + " next to " + member.username + "'s ghost at " + W3T_VecStr(pos));
        bot.scenarioCount = 1;
        return false;
    }

    drowner = (CNewNPC)bot.scenarioEntity;
    if(!drowner)
    {
        W3T_Log("FAIL drowner is gone");
        W3T_Quit(2);
        return false;
    }

    W3T_LookAt(drowner.GetWorldPosition());
    target = drowner.GetTarget();
    targetName = "none";
    if(target == thePlayer)
    {
        targetName = "leader";
    }
    else if(target && target.HasTag('MPEntity'))
    {
        targetName = "ghost";
    }
    else if(target)
    {
        targetName = target.GetReadableName();
    }
    W3T_Log("ENEMY leader drowner target=" + targetName + " hp=" + FloatToStringPrec(drowner.GetHealthPercents(), 4)
        + " ghostHits=" + coop.ghostHitsSeen + " hurtsCaptured=" + coop.hurtsCaptured + " pendingHurts=" + coop.PendingHurtCount()
        + " attacks=" + coop.attacksSeen + " moves=" + coop.movesSeen
        + " tracked=" + coop.HostNetIdOf(drowner) + " ghostAttitude=" + drowner.GetAttitude(member.ghost)
        + " ghostDist=" + FloatToStringPrec(VecDistance(drowner.GetWorldPosition(), member.ghost.GetWorldPosition()), 2));

    if(bot.scenarioCount == 1 && coop.hurtsCaptured >= 2 && coop.PendingHurtCount() == 0)
    {
        W3T_Log("ENEMY leader: " + coop.hurtsCaptured + " hits on the ghost sent and acknowledged");
        bot.scenarioCount = 2;
    }
    return bot.scenarioCount == 2;
}

// enemy_attacks, member: join the leader's party; the leader's drowner attacks this player's ghost, and those
// hits must land on this Geralt (at least two, with real damage after this game's armor).
function W3T_EnemyAttacksMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        client.joinParty(leader.username);
        return false;
    }

    if(coop.PuppetCount() > 0)
    {
        W3T_LookAt(coop.PuppetAt(0).GetWorldPosition());
    }
    W3T_Log("ENEMY member vitality=" + FloatToStringPrec(thePlayer.GetStat(BCS_Vitality), 0) + " hurtsApplied=" + coop.hurtsApplied
        + " dodged=" + coop.hurtsDodged + " damageTaken=" + FloatToStringPrec(coop.hurtDamageTaken, 1) + " puppets=" + coop.PuppetCount()
        + " attacksPlayed=" + coop.attacksPlayed + " attackFailures=" + coop.attackPlayFailures
        + " movesPlayed=" + coop.movesPlayed + " moveFailures=" + coop.movePlayFailures
        + " lastHurtDelay=" + FloatToStringPrec(coop.lastHurtDelay, 2) + " lastError=" + coop.lastError);

    if(coop.attackPlayFailures > 0 || coop.movePlayFailures > 0)
    {
        W3T_Log("FAIL the puppet could not play the leader's attack or move: " + coop.lastError);
        W3T_Quit(1);
        return false;
    }

    // the monster's swings show on its puppet, and its hits land
    if(bot.scenarioCount == 0 && coop.hurtsApplied >= 2 && coop.hurtDamageTaken > 0 && coop.attacksPlayed >= 1)
    {
        W3T_Log("ENEMY member took " + FloatToStringPrec(coop.hurtDamageTaken, 1) + " damage from " + coop.hurtsApplied
            + " of the leader's monster's hits; its puppet played " + coop.attacksPlayed + " attacks and "
            + coop.movesPlayed + " other moves");
        // survive the rest of the run
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioCount = 1;
    }
    return bot.scenarioCount == 1;
}

// enemy_moves, leader: the monster of enemy_attacks (a nekker unless W3T_MONSTER: they dodge), told every 2 s that
// an attack is coming (as the game tells a target), so it dodges; taunts count too. Passes once a move was captured.
function W3T_EnemyMovesLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var monster : CNewNPC;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member, "characters\npc_entities\monsters\nekker_lvl1.w2ent");
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    monster = (CNewNPC)bot.scenarioEntity;
    W3T_LookAt(monster.GetWorldPosition());
    if(bot.ElapsedS() - bot.scenarioTime >= 2)
    {
        bot.scenarioTime = bot.ElapsedS();
        monster.SignalGameplayEventParamInt('Time2Dodge', (int)EDT_Attack_Light);
    }
    W3T_Log("MOVES leader moves=" + coop.movesSeen + " last=" + NameToString(coop.lastMoveAnim) + " attacks=" + coop.attacksSeen + " dodging=" + monster.IsCurrentlyDodging());
    return coop.movesSeen >= 1;
}

// enemy_moves, member: the puppet plays the leader's monster's dodges and taunts (at least one, none refused).
function W3T_EnemyMovesMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(coop.PuppetCount() > 0)
    {
        W3T_LookAt(coop.PuppetAt(0).GetWorldPosition());
    }
    W3T_Log("MOVES member movesPlayed=" + coop.movesPlayed + " moveFailures=" + coop.movePlayFailures
        + " attacksPlayed=" + coop.attacksPlayed + " lastError=" + coop.lastError);
    if(coop.movePlayFailures > 0)
    {
        W3T_Log("FAIL the puppet could not play the leader's move: " + coop.lastError);
        W3T_Quit(1);
        return false;
    }
    return coop.movesPlayed >= 1;
}

// sign_check: an actor's effect manager, to build an effect the way it does and see why it is denied
@addMethod(CActor)
function W3T_EffectManager() : W3EffectManager
{
    return effectManager;
}

// sign_check (one bot, no co-op): Igni and Aard on a plain drowner 3 m ahead, every 2 s; logs whether they burn
// or knock it down, and which effect abilities the sign skills contain. Passes after 40 s.
function W3T_SignCheck(bot : W3T_Bot) : bool
{
    var template : CEntityTemplate;
    var drowner : CNewNPC;
    var rot : EulerAngles;
    var abilities : array<name>;
    var pos : Vector;
    var i : int;
    var line : string;
    var node : SCustomNode;
    var j : int;
    var nameOk, stringOk, stringOk2 : bool;
    var effect : CBaseGameplayEffect;
    var nameVal : name;
    var stringVal, stringVal2 : string;

    if(bot.scenarioCount == 0)
    {
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
        pos = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 3.0;
        bot.scenarioEntity = theGame.CreateEntity(template, pos, rot, true, false, false, PM_DontPersist);
        ((CNewNPC)bot.scenarioEntity).SetImmortalityMode(AIM_Immortal, AIC_Default);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        theGame.GetDefinitionsManager().GetContainedAbilities(thePlayer.GetSkillAbilityName(S_Magic_1), abilities);
        line = "aard contains:";
        for(i = 0; i < abilities.Size(); i += 1)
        {
            line += " " + NameToString(abilities[i]) + "/" + IsEffectNameValid(abilities[i]);
        }
        abilities.Clear();
        theGame.GetDefinitionsManager().GetContainedAbilities(thePlayer.GetSkillAbilityName(S_Magic_2), abilities);
        line += "; igni contains:";
        for(i = 0; i < abilities.Size(); i += 1)
        {
            line += " " + NameToString(abilities[i]) + "/" + IsEffectNameValid(abilities[i]);
        }
        W3T_Log("SIGN " + line);
        node = theGame.GetDefinitionsManager().GetCustomDefinition('effects');
        W3T_Log("SIGN effectMgr ready=" + theGame.IsEffectManagerInitialized() + " xmlEffects=" + node.subNodes.Size()
            + " valid BurningEffect=" + IsEffectNameValid('BurningEffect') + " KnockdownEffect=" + IsEffectNameValid('KnockdownEffect')
            + " KnockdownTypeApplicator=" + IsEffectNameValid('KnockdownTypeApplicator') + " PoisonEffect=" + IsEffectNameValid('PoisonEffect'));
        // what the first effect definitions look like (5.01 may name the attribute differently)
        for(i = 0; i < 3 && i < node.subNodes.Size(); i += 1)
        {
            line = "SIGN def " + i + " node=" + NameToString(node.subNodes[i].nodeName) + " attrs:";
            for(j = 0; j < node.subNodes[i].attributes.Size(); j += 1)
            {
                line += " " + NameToString(node.subNodes[i].attributes[j].attributeName) + "=" + NameToString(node.subNodes[i].values[j]);
            }
            W3T_Log(line);
        }
        if(node.subNodes.Size() > 0)
        {
            nameOk = theGame.GetDefinitionsManager().GetCustomNodeAttributeValueName(node.subNodes[0], 'name_name', nameVal);
            stringOk = theGame.GetDefinitionsManager().GetCustomNodeAttributeValueString(node.subNodes[0], 'name_name', stringVal);
            stringOk2 = theGame.GetDefinitionsManager().GetCustomNodeAttributeValueString(node.subNodes[0], 'name', stringVal2);
            W3T_Log("SIGN def 0 as name: " + nameOk + " '" + NameToString(nameVal) + "'; as string: " + stringOk + " '" + stringVal
                + "'; 'name' as string: " + stringOk2 + " '" + stringVal2 + "'; valid=" + IsEffectNameValid(nameVal));
            line = "SIGN all effects:";
            for(i = 0; i < node.subNodes.Size(); i += 1)
            {
                theGame.GetDefinitionsManager().GetCustomNodeAttributeValueName(node.subNodes[i], 'name_name', nameVal);
                line += " " + NameToString(nameVal);
            }
            W3T_Log(line);
        }
        if(W3T_GetEnv("W3T_REINIT_EFFECTS") == "1")
        {
            theGame.effectMgr.Initialize();
            W3T_Log("SIGN after re-init: BurningEffect=" + IsEffectNameValid('BurningEffect') + " KnockdownTypeApplicator="
                + IsEffectNameValid('KnockdownTypeApplicator'));
        }
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 1;
        return false;
    }
    drowner = (CNewNPC)bot.scenarioEntity;
    if(bot.scenarioCount == 1)
    {
        // results: 0 undefined, 1 deny, 2 override, 3 pass, 4 cumulate
        W3T_Log("SIGN direct: burning on drowner=" + (int)drowner.AddEffectDefault(EET_Burning, thePlayer, "W3T") + " has="
            + drowner.HasBuff(EET_Burning) + " immune=" + drowner.IsImmuneToBuff(EET_Burning) + "; stagger on drowner="
            + (int)drowner.AddEffectDefault(EET_Stagger, thePlayer, "W3T") + " has=" + drowner.HasBuff(EET_Stagger)
            + "; bleeding on player=" + (int)thePlayer.AddEffectDefault(EET_Bleeding, drowner, "W3T") + " has=" + thePlayer.HasBuff(EET_Bleeding)
            + "; potion Cat on player=" + (int)thePlayer.AddEffectDefault(EET_Cat, thePlayer, "W3T") + " has=" + thePlayer.HasBuff(EET_Cat));
        // what InternalAddEffect checks before it denies: the effect object, its duration and resistance
        effect = theGame.effectMgr.MakeNewEffect(EET_Burning, thePlayer, drowner, drowner.W3T_EffectManager(), 0, "W3T");
        if(effect)
        {
            W3T_Log("SIGN made burning: duration=" + FloatToStringPrec(effect.GetDurationLeft(), 2) + " resist="
                + FloatToStringPrec(effect.GetBuffResist(), 2) + " alive=" + drowner.IsAlive());
        }
        else
        {
            W3T_Log("SIGN made burning: none");
        }
        // the base effects.xml also defines the effects' abilities (durations); are they loaded?
        W3T_Log("SIGN abilities defined: BurningEffect=" + theGame.GetDefinitionsManager().IsAbilityDefined('BurningEffect')
            + " KnockdownEffect=" + theGame.GetDefinitionsManager().IsAbilityDefined('KnockdownEffect')
            + " BleedingEffect=" + theGame.GetDefinitionsManager().IsAbilityDefined('BleedingEffect')
            + " Mutagen01Effect=" + theGame.GetDefinitionsManager().IsAbilityDefined('Mutagen01Effect')
            + " WeakenEffect=" + theGame.GetDefinitionsManager().IsAbilityDefined('WeakenEffect'));
        effect = theGame.effectMgr.MakeNewEffect(EET_Cat, thePlayer, thePlayer, thePlayer.W3T_EffectManager(), 0, "W3T");
        if(effect)
        {
            W3T_Log("SIGN made Cat: duration=" + FloatToStringPrec(effect.GetDurationLeft(), 2));
        }
    }
    W3T_LookAt(drowner.GetWorldPosition());
    rot.Yaw = VecHeading(drowner.GetWorldPosition() - thePlayer.GetWorldPosition());
    thePlayer.TeleportWithRotation(thePlayer.GetWorldPosition(), rot);
    thePlayer.GoToCombatIfNeeded(drowner);
    if(bot.scenarioCount % 2 == 1)
    {
        GetWitcherPlayer().SetEquippedSign(ST_Igni);
    }
    else
    {
        GetWitcherPlayer().SetEquippedSign(ST_Aard);
    }
    thePlayer.GainStat(BCS_Stamina, thePlayer.GetStatMax(BCS_Stamina));
    thePlayer.SetupCombatAction(EBAT_CastSign, BS_Pressed);
    bot.scenarioCount += 1;
    W3T_Log("SIGN cast=" + bot.scenarioCount + " hp=" + FloatToStringPrec(drowner.GetHealthPercents(), 3) + " burning=" + drowner.HasBuff(EET_Burning)
        + " knockdown=" + (drowner.HasBuff(EET_Knockdown) || drowner.HasBuff(EET_HeavyKnockdown)) + " stagger="
        + (drowner.HasBuff(EET_Stagger) || drowner.HasBuff(EET_LongStagger)) + " dist="
        + FloatToStringPrec(VecDistance(drowner.GetWorldPosition(), thePlayer.GetWorldPosition()), 1));
    return bot.ElapsedS() - bot.scenarioTime > 40;
}

// sign_visuals, member: casts Igni and Aard in turn every 3 s, into the camera's view (scenarioCount: casts); its own
// sign entity must play the sign's throw effect (seen: scenarioValue bit 1 Igni, bit 2 Aard). The leader passes once
// two of this player's casts showed their visual at its copy.
function W3T_SignVisualsMember(bot : W3T_Bot) : bool
{
    var rot : EulerAngles;
    var igni : W3IgniEntity;
    var aard : W3AardEntity;
    var seen : int;

    igni = (W3IgniEntity)GetWitcherPlayer().GetSignEntity(ST_Igni);
    aard = (W3AardEntity)GetWitcherPlayer().GetSignEntity(ST_Aard);
    seen = (int)bot.scenarioValue;
    if(igni && igni.effects.Size() > 0 && (igni.IsEffectActive(igni.effects[0].throwEffect, true)
        || (igni.effects.Size() > 1 && igni.IsEffectActive(igni.effects[1].throwEffect, true))))
    {
        seen = seen | 1;
    }
    if(aard && aard.effects.Size() > 0 && aard.IsEffectActive(aard.effects[0].baseCommonThrowEffect, true))
    {
        seen = seen | 2;
    }
    bot.scenarioValue = seen;

    if(bot.ElapsedS() - bot.scenarioTime >= 3)
    {
        bot.scenarioTime = bot.ElapsedS();
        rot.Yaw = theCamera.GetCameraHeading();
        thePlayer.TeleportWithRotation(thePlayer.GetWorldPosition(), rot);
        if(bot.scenarioCount % 2 == 0)
        {
            GetWitcherPlayer().SetEquippedSign(ST_Igni);
        }
        else
        {
            GetWitcherPlayer().SetEquippedSign(ST_Aard);
        }
        thePlayer.GainStat(BCS_Stamina, thePlayer.GetStatMax(BCS_Stamina));
        thePlayer.SetupCombatAction(EBAT_CastSign, BS_Pressed);
        bot.scenarioCount += 1;
    }
    W3T_Log("SIGNFX member casts=" + bot.scenarioCount + " ownIgni=" + ((seen & 1) != 0) + " ownAard=" + ((seen & 2) != 0)
        + " lastSign=" + FloatToStringPrec(theGame.r_getMultiplayerClient().getLastSignTime(), 1));
    return seen == 3;
}

// member_combat, leader: the drowner of enemy_attacks, immortal so it takes every kind of hit. Passes once members'
// hits did damage and their effects were added to its hits (whether they take hold is logged: in the test games no
// effect does, members' or not; see sign_check).
function W3T_CombatLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var monster : CNewNPC;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member);
        if(bot.scenarioCount == 1)
        {
            ((CNewNPC)bot.scenarioEntity).SetImmortalityMode(AIM_Immortal, AIC_Default);
        }
        return false;
    }
    monster = (CNewNPC)bot.scenarioEntity;
    W3T_LookAt(monster.GetWorldPosition());
    if(monster.HasBuff(EET_Burning))
    {
        bot.scenarioFlag = true;
    }
    W3T_Log("COMBAT leader hitsApplied=" + coop.hitsApplied + " effects=" + coop.hitEffectsApplied + " held=" + coop.hitEffectsHeld + " hp="
        + FloatToStringPrec(monster.GetHealthPercents(), 3) + " burning=" + monster.HasBuff(EET_Burning)
        + " knockedDown=" + (monster.HasBuff(EET_Knockdown) || monster.HasBuff(EET_HeavyKnockdown))
        + " stagger=" + monster.HasBuff(EET_Stagger) + " everBurned=" + bot.scenarioFlag);
    return coop.hitsApplied >= 3 && coop.hitEffectsApplied >= 2;
}

// member_combat, member: walks up to the puppet and fights it as a player: three sword swings, Igni, Aard, then a fire
// hit and a knockdown carried by this player's damage actions (on 5.01 the player's signs carry no effects: their
// skills' effect names are missing from the game's effect list), over and over (scenarioCount: steps done). Passes
// once its sword and its signs sent hits and effects went out.
function W3T_CombatMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var puppet : CNewNPC;
    var spot : Vector;
    var rot : EulerAngles;
    var step : int;
    var action : W3DamageAction;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(coop.PuppetCount() < 1)
    {
        return false;
    }
    puppet = coop.PuppetAt(0);
    if(VecDistance(thePlayer.GetWorldPosition(), puppet.GetWorldPosition()) > 2.5)
    {
        spot = puppet.GetWorldPosition() + VecNormalize(thePlayer.GetWorldPosition() - puppet.GetWorldPosition()) * 1.8;
        rot.Yaw = VecHeading(puppet.GetWorldPosition() - spot);
        thePlayer.TeleportWithRotation(spot, rot);
    }
    W3T_LookAt(puppet.GetWorldPosition());
    thePlayer.GoToCombatIfNeeded(puppet);

    step = bot.scenarioCount % 7;
    if(step < 3)
    {
        thePlayer.SetupCombatAction(EBAT_LightAttack, BS_Pressed);
    }
    else if(step >= 5)
    {
        action = new W3DamageAction in theGame.damageMgr;
        action.Initialize(thePlayer, puppet, thePlayer, "W3TestHit", EHRT_Light, CPS_SpellPower, false, false, true, false);
        if(step == 5)
        {
            action.AddDamage(theGame.params.DAMAGE_NAME_FIRE, 50);
            action.AddEffectInfo(EET_Burning);
        }
        else
        {
            action.SetProcessBuffsIfNoDamage(true);
            action.AddEffectInfo(EET_KnockdownTypeApplicator);
        }
        theGame.damageMgr.ProcessAction(action);
        delete action;
    }
    else
    {
        if(step == 3)
        {
            GetWitcherPlayer().SetEquippedSign(ST_Igni);
        }
        else
        {
            GetWitcherPlayer().SetEquippedSign(ST_Aard);
        }
        thePlayer.GainStat(BCS_Stamina, thePlayer.GetStatMax(BCS_Stamina));
        thePlayer.SetupCombatAction(EBAT_CastSign, BS_Pressed);
    }
    bot.scenarioCount += 1;

    W3T_Log("COMBAT member step=" + step + " hitsSent=" + coop.hitsSent + " melee=" + coop.meleeHitsSent + " sign="
        + coop.signHitsSent + " effects=" + coop.hitEffectsSent + " puppetBurning=" + puppet.HasBuff(EET_Burning) + " puppetDown="
        + (puppet.HasBuff(EET_Knockdown) || puppet.HasBuff(EET_HeavyKnockdown) || puppet.HasBuff(EET_Stagger) || puppet.HasBuff(EET_LongStagger)) + " dist="
        + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(), puppet.GetWorldPosition()), 1));
    return coop.meleeHitsSent >= 3 && coop.signHitsSent >= 1 && coop.hitEffectsSent >= 2;
}

// enemy_projectiles, leader: the monster of enemy_attacks (a Baron's bandit with a bow unless W3T_MONSTER) shoots at
// the member's ghost. Passes once two of its projectiles were captured and one hit the ghost.
function W3T_ProjectilesLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member, "gameplay\community\community_npcs\nml\regular\baron_bandit_weak_bow.w2ent", true);
        return false;
    }
    W3T_LookAt(bot.scenarioEntity.GetWorldPosition());
    W3T_Log("PROJ leader projectiles=" + coop.projectilesSeen + " attacks=" + coop.attacksSeen + " moves=" + coop.movesSeen
        + " hurts=" + coop.hurtsCaptured);
    return coop.projectilesSeen >= 2 && coop.hurtsCaptured >= 1;
}

// enemy_projectiles, member: copies of the leader's monster's projectiles fly from its puppet (at least two, none
// failed), and a hit lands as a hurt.
function W3T_ProjectilesMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(coop.PuppetCount() > 0)
    {
        W3T_LookAt(coop.PuppetAt(0).GetWorldPosition());
    }
    W3T_Log("PROJ member fired=" + coop.projectilesFired + " failures=" + coop.projectileFailures + " hurtsApplied=" + coop.hurtsApplied
        + " lastError=" + coop.lastError);
    if(coop.projectileFailures > 0)
    {
        W3T_Log("FAIL the leader's projectile could not be fired here: " + coop.lastError);
        W3T_Quit(1);
        return false;
    }
    return coop.projectilesFired >= 2 && coop.hurtsApplied >= 1;
}

// handoff, leader: a drowner next to the member's ghost, as in enemy_attacks. Passes after seeing the member
// go far away (beyond sharing range) and come back; the member's position comes from the global player list,
// since its ghost despawns while it is away.
function W3T_HandoffLeader(bot : W3T_Bot, coop : r_CoopEnemies, players : array<r_RemotePlayer>, globals : array<r_RemotePlayer>) : bool
{
    var dist : float;

    if(bot.scenarioCount == 0)
    {
        if(players.Size() < 1 || !players[0].ghost)
        {
            return false;
        }
        W3T_EnemyAttacksLeader(bot, coop, players[0]);
        bot.scenarioVec = players[0].pos;
        return false;
    }
    if(globals.Size() < 1)
    {
        return bot.scenarioCount >= 4;
    }

    // scenarioCount: 1 drowner spawned, 2 member went far, 4 member came back
    dist = VecDistance(globals[0].pos, bot.scenarioVec);
    W3T_Log("HANDOFF leader sees the member " + FloatToStringPrec(dist, 1) + " m from the start; leaderEnemies="
        + coop.HostEnemyCount());
    if(bot.scenarioCount == 1 && dist > 80)
    {
        bot.scenarioCount = 2;
    }
    else if(bot.scenarioCount == 2 && dist < 20)
    {
        bot.scenarioCount = 4;
    }
    return bot.scenarioCount >= 4;
}

// handoff, member: once the drowner is mirrored, go 120 m away: the puppets must be released within 5 s (this
// world runs its own monsters there); come back: the drowner must be mirrored again.
function W3T_HandoffMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, players : array<r_RemotePlayer>) : bool
{
    var target : Vector;

    if(!client.getInParty())
    {
        if(players.Size() < 1)
        {
            return false;
        }
        W3T_Log("PARTY join " + players[0].username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(players[0].username);
        return false;
    }

    W3T_Log("HANDOFF member phase=" + bot.scenarioCount + " puppets=" + coop.PuppetCount() + " suppressed=" + coop.SuppressedCount()
        + " pos=" + W3T_VecStr(thePlayer.GetWorldPosition()));

    // scenarioCount: 0 waiting for the puppet, 1 sent away, 2 released and sent back, 3 mirrored again
    if(bot.scenarioCount == 0 && coop.PuppetCount() > 0)
    {
        bot.scenarioVec = thePlayer.GetWorldPosition();
        target = bot.scenarioVec;
        target.X += 120;
        thePlayer.Teleport(target);
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 1;
        W3T_Log("HANDOFF member went 120 m away");
    }
    else if(bot.scenarioCount == 1)
    {
        if(coop.PuppetCount() == 0 && coop.SuppressedCount() == 0)
        {
            W3T_Log("HANDOFF member released the leader's monsters after " + FloatToStringPrec(bot.ElapsedS() - bot.scenarioTime, 1) + " s");
            thePlayer.Teleport(bot.scenarioVec);
            bot.scenarioTime = bot.ElapsedS();
            bot.scenarioCount = 2;
        }
        else if(bot.ElapsedS() - bot.scenarioTime > 5)
        {
            W3T_Log("FAIL puppets still mirrored 5 s after leaving sharing range");
            W3T_Quit(1);
        }
    }
    else if(bot.scenarioCount == 2 && coop.PuppetCount() > 0)
    {
        W3T_Log("HANDOFF member mirrors the drowner again after " + FloatToStringPrec(bot.ElapsedS() - bot.scenarioTime, 1) + " s");
        bot.scenarioCount = 3;
    }
    return bot.scenarioCount == 3;
}

// reactions, leader: a drowner next to the member's ghost (as in enemy_attacks). This Geralt hits it twice, then
// makes it land a bleeding hit on the ghost; passes 5 s later.
function W3T_ReactionsLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var drowner : CNewNPC;
    var action : W3DamageAction;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member);
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    drowner = (CNewNPC)bot.scenarioEntity;
    if(!drowner)
    {
        W3T_Log("FAIL drowner is gone");
        W3T_Quit(2);
        return false;
    }

    // scenarioCount: 1 spawned, 2-3 after this Geralt's hits, 4 after the bleeding hit, 5 done
    if(bot.scenarioCount < 4 && bot.ElapsedS() - bot.scenarioTime >= 3)
    {
        if(bot.scenarioCount < 3)
        {
            action = new W3DamageAction in theGame.damageMgr;
            action.Initialize(thePlayer, drowner, thePlayer, "W3T", EHRT_Light, CPS_Undefined, true, false, false, false);
            action.AddDamage(theGame.params.DAMAGE_NAME_DIRECT, 0.05 * drowner.GetMaxHealth());
            theGame.damageMgr.ProcessAction(action);
            delete action;
            W3T_Log("REACT leader hit its drowner (" + bot.scenarioCount + ")");
        }
        else if(member.ghost)
        {
            action = new W3DamageAction in theGame.damageMgr;
            action.Initialize(drowner, member.ghost, drowner, "W3T", EHRT_Light, CPS_AttackPower, true, false, false, false);
            action.AddDamage(theGame.params.DAMAGE_NAME_PHYSICAL, 10);
            action.AddEffectInfo(EET_Bleeding);
            theGame.damageMgr.ProcessAction(action);
            delete action;
            W3T_Log("REACT leader's drowner landed a bleeding hit on the ghost");
        }
        bot.scenarioCount += 1;
        bot.scenarioTime = bot.ElapsedS();
    }
    if(bot.scenarioCount == 4 && bot.ElapsedS() - bot.scenarioTime >= 5)
    {
        bot.scenarioCount = 5;
    }
    return bot.scenarioCount == 5;
}

// reactions, member: the leader's two hits must be replayed on the puppet, and the drowner's bleeding hit must
// reach this Geralt with its effect.
function W3T_ReactionsMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        client.joinParty(leader.username);
        return false;
    }

    W3T_Log("REACT member mirroredHits=" + coop.hitReactionsMirrored + " hitAnims=" + coop.hitAnimsSeen + " hurts=" + coop.hurtsApplied
        + " hurtEffects=" + coop.hurtEffectsApplied + " bleeding=" + thePlayer.HasBuff(EET_Bleeding) + " puppets=" + coop.PuppetCount());

    if(bot.scenarioCount == 0 && coop.hitReactionsMirrored >= 2 && coop.hurtEffectsApplied >= 1)
    {
        W3T_Log("REACT member replayed " + coop.hitReactionsMirrored + " of the leader's hits (" + coop.hitAnimsSeen
            + " hit animations seen) and got " + coop.hurtEffectsApplied + " effect(s) with the drowner's hits");
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioCount = 1;
    }
    return bot.scenarioCount == 1;
}

function W3T_TwinSpot(start : Vector) : Vector
{
    start.Y += 8;
    return start;
}

// twin_match, leader: some seconds after the member joined, spawn a drowner 8 m north of the start; the member
// has its own drowner there (its world's copy of the same encounter).
function W3T_TwinLeader(bot : W3T_Bot, coop : r_CoopEnemies) : bool
{
    var template : CEntityTemplate;
    var rot : EulerAngles;

    // scenarioCount: 1 start recorded, 2 member joined, 3 drowner spawned, 4 done
    if(bot.scenarioCount == 0)
    {
        bot.scenarioVec = thePlayer.GetWorldPosition();
        bot.scenarioCount = 1;
    }
    else if(bot.scenarioCount == 1 && coop.GetRole() == 1)
    {
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 2;
    }
    else if(bot.scenarioCount == 2 && bot.ElapsedS() - bot.scenarioTime >= 6)
    {
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioEntity = theGame.CreateEntity(template, W3T_TwinSpot(bot.scenarioVec), rot, true, false, false, PM_DontPersist);
        W3T_Log("TWIN leader spawned its drowner at " + W3T_VecStr(W3T_TwinSpot(bot.scenarioVec)));
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 3;
    }
    else if(bot.scenarioCount == 3 && bot.ElapsedS() - bot.scenarioTime >= 10)
    {
        bot.scenarioCount = 4;
    }
    return bot.scenarioCount == 4;
}

// twin_match, member: after joining, spawn this world's drowner at the same spot (hidden while unmatched); when
// the leader's appears, this one must become its puppet instead of a second, spawned drowner.
function W3T_TwinMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var template : CEntityTemplate;
    var mine : CNewNPC;
    var entities : array<CGameplayEntity>;
    var npc : CNewNPC;
    var rot : EulerAngles;
    var others, i : int;

    if(bot.scenarioCount == 0)
    {
        bot.scenarioVec = thePlayer.GetWorldPosition();
        bot.scenarioCount = 1;
        return false;
    }
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(bot.scenarioCount == 1)
    {
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
        bot.scenarioEntity = theGame.CreateEntity(template, W3T_TwinSpot(bot.scenarioVec), rot, true, false, false, PM_DontPersist);
        W3T_Log("TWIN member spawned this world's drowner at " + W3T_VecStr(W3T_TwinSpot(bot.scenarioVec)));
        bot.scenarioCount = 2;
        return false;
    }

    mine = (CNewNPC)bot.scenarioEntity;
    W3T_Log("TWIN member puppets=" + coop.PuppetCount() + " twins=" + coop.twinsBound + " spawned=" + coop.puppetsSpawned
        + " suppressed=" + coop.SuppressedCount() + " mine=" + W3T_VecStr(mine.GetWorldPosition()) + " visible=" + mine.GetVisibility());

    for(i = 0; i < coop.PuppetCount() && bot.scenarioCount == 2; i += 1)
    {
        if(StrFindFirst(coop.PuppetAt(i).GetReadableName(), "drowner_lvl1") < 0)
        {
            continue;
        }
        if(coop.PuppetSpawned(i))
        {
            W3T_Log("FAIL a second drowner was spawned instead of binding this world's");
            W3T_Quit(1);
            return false;
        }
        if(coop.PuppetAt(i) == mine)
        {
            FindGameplayEntitiesInSphere(entities, mine.GetWorldPosition(), 20.0, 32, '', FLAG_OnlyAliveActors, thePlayer);
            for(i = 0; i < entities.Size(); i += 1)
            {
                npc = (CNewNPC)entities[i];
                if(npc && npc != mine && StrFindFirst(npc.GetReadableName(), "drowner_lvl1") >= 0)
                {
                    others += 1;
                }
            }
            if(others > 0)
            {
                W3T_Log("FAIL " + others + " other drowner(s) next to the bound one");
                W3T_Quit(1);
                return false;
            }
            W3T_Log("TWIN member's own drowner became the leader's puppet; no duplicate");
            bot.scenarioCount = 3;
        }
    }
    return bot.scenarioCount == 3;
}

// real_encounter: the nearest active monster nest of this world, from the map pins (both bots load the same save,
// so they pick the same one); W = 0 if none
function W3T_NearestNest(out label : string) : Vector
{
    var manager : CCommonMapManager;
    var areas : array<SAreaMapPinInfo>;
    var pins : array<SEntityMapPinInfo>;
    var best : Vector;
    var bestDist, d : float;
    var worlds : string;
    var i, j : int;

    manager = theGame.GetCommonMapManager();
    areas = manager.GetAreaMapPins();
    bestDist = 100000;
    for(i = 0; i < areas.Size(); i += 1)
    {
        worlds += " " + areas[i].worldPath;
        if(areas[i].worldPath != theGame.GetWorld().GetDepotPath())
        {
            continue;
        }
        pins = manager.GetEntityMapPins(areas[i].worldPath);
        for(j = 0; j < pins.Size(); j += 1)
        {
            if(pins[j].entityType != 'MonsterNest' || manager.IsEntityMapPinDisabled(pins[j].entityName))
            {
                continue;
            }
            d = VecDistance2D(pins[j].entityPosition, thePlayer.GetWorldPosition());
            if(d < bestDist)
            {
                bestDist = d;
                best = pins[j].entityPosition;
                best.W = 1;
                label = NameToString(pins[j].entityName) + ", " + FloatToStringPrec(d, 0) + " m away";
            }
        }
    }
    if(best.W == 0)
    {
        label = "this world " + theGame.GetWorld().GetDepotPath() + "; areas:" + worlds;
    }
    return best;
}

// real_encounter: right after a long teleport the ground's collision may not be loaded and the player falls through;
// back to the spot whenever it is 25 m below it (the ground beside a nest can be 12 m lower than its pin; a fall
// through the world drops 30 m a second)
function W3T_HoldAt(spot : Vector)
{
    var pos : Vector;

    pos = thePlayer.GetWorldPosition();
    if(pos.Z < spot.Z - 25)
    {
        W3T_Log("ENCOUNTER fell through the ground at " + W3T_VecStr(pos) + "; back to the nest");
        thePlayer.Teleport(spot);
    }
}

// real_encounter: 6 s after arriving (the navigation mesh has loaded), stand on a walkable spot near the nest
// (scenarioCount 10 while waiting; scenarioVec: the nest, then that spot); true once standing there
function W3T_SettleAtNest(bot : W3T_Bot, offset : Vector) : bool
{
    var safe : Vector;

    if(bot.scenarioCount != 10)
    {
        return true;
    }
    if(bot.ElapsedS() - bot.scenarioTime < 6)
    {
        return false;
    }
    if(!theGame.GetWorld().NavigationFindSafeSpot(bot.scenarioVec + offset, 0.5, 8.0, safe))
    {
        safe = bot.scenarioVec + offset + Vector(0, 0, 1);
    }
    thePlayer.Teleport(safe);
    W3T_Log("ENCOUNTER stands at " + W3T_VecStr(safe));
    bot.scenarioVec = safe;
    bot.scenarioTime = bot.ElapsedS();
    bot.scenarioCount = 1;
    return false;
}

// real_encounter, leader: once the member joined, both go to the nearest active monster nest, where this world's
// own encounter spawns. 25 s after its monsters are shared, the leader kills them; passes 10 s later.
function W3T_EncounterLeader(bot : W3T_Bot, coop : r_CoopEnemies) : bool
{
    var nest : Vector;
    var label : string;
    var i : int;

    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1)
        {
            return false;
        }
        nest = W3T_NearestNest(label);
        if(nest.W == 0)
        {
            W3T_Log("FAIL no active monster nest in " + label);
            W3T_Quit(2);
            return false;
        }
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioVec = nest;
        thePlayer.Teleport(nest + Vector(0, 0, 2));
        W3T_Log("ENCOUNTER leader goes to nest " + label + " at " + W3T_VecStr(nest));
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 10;
        return false;
    }
    if(!W3T_SettleAtNest(bot, Vector(5, 0, 0)))
    {
        return false;
    }
    W3T_HoldAt(bot.scenarioVec);
    W3T_Log("ENCOUNTER leader enemies=" + coop.HostEnemyCount() + " pos=" + W3T_VecStr(thePlayer.GetWorldPosition()));
    if(bot.scenarioCount == 1)
    {
        if(coop.HostEnemyCount() > 0)
        {
            for(i = 0; i < coop.HostEnemyCount(); i += 1)
            {
                W3T_Log("ENCOUNTER leader monster " + coop.HostEnemyAt(i).GetReadableName() + " at "
                    + W3T_VecStr(coop.HostEnemyAt(i).GetWorldPosition()));
            }
            bot.scenarioTime = bot.ElapsedS();
            bot.scenarioCount = 2;
        }
        else if(bot.ElapsedS() - bot.scenarioTime > 90)
        {
            W3T_Log("FAIL no monsters at the nest after 90 s");
            W3T_Quit(2);
        }
    }
    else if(bot.scenarioCount == 2 && bot.ElapsedS() - bot.scenarioTime >= 25)
    {
        W3T_Log("ENCOUNTER leader kills its " + coop.HostEnemyCount() + " monsters");
        for(i = 0; i < coop.HostEnemyCount(); i += 1)
        {
            coop.HostEnemyAt(i).Kill('W3T', true);
        }
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 3;
    }
    return bot.scenarioCount == 3 && bot.ElapsedS() - bot.scenarioTime >= 10;
}

// real_encounter, member: goes to the same nest. This world's own encounter spawns there too: within 25 m, every
// visible hostile must be one of the leader's puppets (bound twins or spawned copies), never a monster of its own
// fighting beside them; and the puppets die when the leader kills its monsters.
function W3T_EncounterMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var entities : array<CGameplayEntity>;
    var npc : CNewNPC;
    var nest : Vector;
    var label : string;
    var loose, alive, i, j : int;
    var isPuppet : bool;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(bot.scenarioCount == 0)
    {
        nest = W3T_NearestNest(label);
        if(nest.W == 0)
        {
            W3T_Log("FAIL no active monster nest in " + label);
            W3T_Quit(2);
            return false;
        }
        bot.scenarioVec = nest;
        thePlayer.Teleport(nest + Vector(0, 0, 2));
        W3T_Log("ENCOUNTER member goes to nest " + label);
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 10;
        return false;
    }
    if(!W3T_SettleAtNest(bot, Vector(5, 2, 0)))
    {
        return false;
    }

    W3T_HoldAt(bot.scenarioVec);
    FindGameplayEntitiesInSphere(entities, thePlayer.GetWorldPosition(), 25.0, 64, '', FLAG_OnlyAliveActors, thePlayer);
    for(i = 0; i < entities.Size(); i += 1)
    {
        npc = (CNewNPC)entities[i];
        if(!npc || GetAttitudeBetween(npc, thePlayer) != AIA_Hostile || !npc.GetVisibility())
        {
            continue;
        }
        isPuppet = false;
        for(j = 0; j < coop.PuppetCount(); j += 1)
        {
            if(coop.PuppetAt(j) == npc)
            {
                isPuppet = true;
            }
        }
        if(!isPuppet)
        {
            loose += 1;
            W3T_Log("ENCOUNTER member's own visible hostile " + npc.GetReadableName() + " at " + W3T_VecStr(npc.GetWorldPosition()));
        }
    }
    for(j = 0; j < coop.PuppetCount(); j += 1)
    {
        if(coop.PuppetAlive(j))
        {
            alive += 1;
        }
    }
    W3T_Log("ENCOUNTER member puppets=" + coop.PuppetCount() + " alive=" + alive + " twins=" + coop.twinsBound
        + " spawned=" + coop.puppetsSpawned + " suppressed=" + coop.SuppressedCount() + " loose=" + loose
        + " killed=" + coop.puppetsKilled + " pos=" + W3T_VecStr(thePlayer.GetWorldPosition()));

    if(bot.scenarioCount == 1 && coop.PuppetCount() > 0)
    {
        bot.scenarioCount = 2;
    }
    // a moment of overlap while a twin is matched is fine; scenarioValue counts checks in a row with loose ones
    if(bot.scenarioCount == 2 && loose > 0)
    {
        bot.scenarioValue += 1;
        if(bot.scenarioValue >= 5)
        {
            W3T_Log("FAIL " + loose + " of this world's own monsters fight beside the leader's");
            W3T_Quit(1);
            return false;
        }
    }
    else
    {
        bot.scenarioValue = 0;
    }
    if(bot.scenarioCount == 2 && coop.puppetsKilled > 0 && alive == 0)
    {
        W3T_Log("ENCOUNTER member: " + coop.puppetsKilled + " puppets died with the leader's monsters (twins "
            + coop.twinsBound + ", spawned " + coop.puppetsSpawned + ")");
        bot.scenarioCount = 3;
    }
    return bot.scenarioCount == 3;
}

// quest_sync, leader: before anyone joins, activate an inactive objective of an active quest (as a quest would);
// passes once a member has been in the party for 8 s.
function W3T_QuestLeader(bot : W3T_Bot, coop : r_CoopEnemies) : bool
{
    var manager : CWitcherJournalManager;
    var quests, phases, objectives : array<CJournalBase>;
    var objective : CJournalBase;
    var i, j, k : int;

    manager = theGame.GetJournalManager();
    if(bot.scenarioCount == 0)
    {
        manager.GetActivatedOfType('CJournalQuest', quests);
        for(i = 0; i < quests.Size() && !objective; i += 1)
        {
            if(manager.GetEntryStatus(quests[i]) != JS_Active)
            {
                continue;
            }
            phases.Clear();
            manager.GetAllChildren(quests[i], phases);
            for(j = 0; j < phases.Size() && !objective; j += 1)
            {
                objectives.Clear();
                manager.GetAllChildren(phases[j], objectives);
                for(k = 0; k < objectives.Size() && !objective; k += 1)
                {
                    if((CJournalQuestObjective)objectives[k] && manager.GetEntryStatus(objectives[k]) == JS_Inactive
                        && IsNameValid(objectives[k].GetUniqueScriptTag()))
                    {
                        objective = objectives[k];
                    }
                }
            }
        }
        if(!objective)
        {
            W3T_Log("FAIL no inactive objective in an active quest (" + quests.Size() + " quests)");
            W3T_Quit(2);
            return false;
        }
        bot.scenarioName = objective.GetUniqueScriptTag();
        manager.ActivateEntry(objective, JS_Active, true, true);
        W3T_Log("QUEST leader activated objective " + NameToString(bot.scenarioName) + " status="
            + coop.JournalStatusOf(bot.scenarioName));
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 1;
        return false;
    }

    W3T_Log("QUEST leader recorded=" + coop.JournalRecorded(bot.scenarioName) + " role=" + coop.GetRole());
    if(bot.scenarioCount == 1 && !coop.JournalRecorded(bot.scenarioName) && bot.ElapsedS() - bot.scenarioTime > 3)
    {
        W3T_Log("FAIL the HUD did not report the objective change");
        W3T_Quit(1);
        return false;
    }
    if(coop.GetRole() == 1)
    {
        if(bot.scenarioCount == 1)
        {
            bot.scenarioCount = 2;
            bot.scenarioTime = bot.ElapsedS();
        }
        else if(bot.scenarioCount == 2 && bot.ElapsedS() - bot.scenarioTime >= 8)
        {
            bot.scenarioCount = 3;
        }
    }
    return bot.scenarioCount == 3;
}

// quest_sync, member: join 10 s after starting (after the leader's change) and get the objective from the
// leader's journal list.
function W3T_QuestMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        if(bot.ElapsedS() >= 10)
        {
            W3T_Log("PARTY join " + leader.username + " (late)");
            client.joinParty(leader.username);
        }
        return false;
    }

    W3T_Log("QUEST member lists=" + coop.journalMessages + " missing=" + coop.journalMissing + " seen=" + coop.lastJournalSeen
        + " journalApplied=" + coop.journalApplied + " last=" + NameToString(coop.lastJournalApplied)
        + " status=" + coop.JournalStatusOf(coop.lastJournalApplied) + " wanted=" + coop.lastJournalAppliedStatus);
    if(bot.scenarioCount == 0 && coop.journalApplied >= 1
        && coop.JournalStatusOf(coop.lastJournalApplied) == coop.lastJournalAppliedStatus)
    {
        W3T_Log("QUEST member has the leader's objective " + NameToString(coop.lastJournalApplied) + " in its journal");
        bot.scenarioCount = 1;
    }
    return bot.scenarioCount == 1;
}

function W3T_DialogModule() : CR4HudModuleDialog
{
    return (CR4HudModuleDialog)((CR4ScriptedHud)theGame.GetHud()).GetHudModule("DialogModule");
}

// two dialogue choices as a scene would offer them
function W3T_TestChoices() : array<SSceneChoice>
{
    var choices : array<SSceneChoice>;
    var choice : SSceneChoice;

    choice.description = "W3T choice A";
    choice.dialogAction = DialogAction_NONE;
    choices.PushBack(choice);
    choice.description = "W3T choice B";
    choices.PushBack(choice);
    return choices;
}

// an active quest other than the tracked one
function W3T_OtherActiveQuest() : CJournalQuest
{
    var manager : CWitcherJournalManager;
    var quests : array<CJournalBase>;
    var i : int;

    manager = theGame.GetJournalManager();
    manager.GetActivatedOfType('CJournalQuest', quests);
    for(i = 0; i < quests.Size(); i += 1)
    {
        if((CJournalQuest)quests[i] && manager.GetEntryStatus(quests[i]) == JS_Active && quests[i] != manager.GetTrackedQuest())
        {
            return (CJournalQuest)quests[i];
        }
    }
    return NULL;
}

// dialog_sync, leader: track two other quests in turn, skip twice in a (named) scene, then pick choice B of a
// two-choice dialogue the member only reaches 6 s later.
function W3T_DialogLeader(bot : W3T_Bot, coop : r_CoopEnemies) : bool
{
    var journalQuest : CJournalQuest;
    var wait : float;

    if(bot.scenarioCount >= 7)
    {
        return true;
    }
    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1)
        {
            return false;
        }
        coop.SetSceneForTest("w3t\\test_scene.w2scene");
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 1;
        return false;
    }

    wait = 4;
    if(bot.scenarioCount >= 3 && bot.scenarioCount <= 4)
    {
        wait = 1.5;
    }
    if(bot.ElapsedS() - bot.scenarioTime < wait)
    {
        return false;
    }
    bot.scenarioTime = bot.ElapsedS();

    // scenarioCount: 1-2 tracking, 3-4 skips, 5 dialogue pick, 6 waiting for the member, 7 done
    if(bot.scenarioCount <= 2)
    {
        journalQuest = W3T_OtherActiveQuest();
        if(!journalQuest)
        {
            W3T_Log("FAIL fewer than two active quests to track");
            W3T_Quit(2);
            return false;
        }
        theGame.GetJournalManager().SetTrackedQuest(journalQuest);
        W3T_Log("DIALOG leader tracks " + NameToString(journalQuest.GetUniqueScriptTag()));
    }
    else if(bot.scenarioCount <= 4)
    {
        W3T_DialogModule().OnDialogSkipped(1);
        W3T_Log("DIALOG leader skipped a line");
    }
    else if(bot.scenarioCount == 5)
    {
        W3T_DialogModule().OnDialogChoicesSet(W3T_TestChoices(), false);
        W3T_DialogModule().OnDialogOptionAccepted(1);
        W3T_Log("DIALOG leader picked choice B");
    }
    else if(bot.scenarioCount == 6)
    {
        if(bot.ElapsedS() - bot.scenarioValue < 20)
        {
            bot.scenarioTime -= wait;
            return false;
        }
    }
    if(bot.scenarioCount == 5)
    {
        bot.scenarioValue = bot.ElapsedS();
    }
    bot.scenarioCount += 1;
    return bot.scenarioCount == 7;
}

// dialog_sync, member: follows the leader's tracking (twice) and skips (twice); reaches the leader's dialogue
// choices 6 s after the leader picked, and the leader's pick must still be applied here.
function W3T_DialogMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var tracked : name;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        client.joinParty(leader.username);
        return false;
    }
    if(!bot.scenarioFlag)
    {
        coop.SetSceneForTest("w3t\\test_scene.w2scene");
        bot.scenarioFlag = true;
    }

    if(theGame.GetJournalManager().GetTrackedQuest())
    {
        tracked = theGame.GetJournalManager().GetTrackedQuest().GetUniqueScriptTag();
    }
    W3T_Log("DIALOG member trackedApplied=" + coop.trackedApplied + " tracked=" + NameToString(tracked) + " skips=" + coop.skipsApplied
        + " choicesActive=" + client.hasActiveDialogChoices() + " leaderPicks=" + leader.lastDialogCount + "/" + leader.prevDialogCount
        + " leaderIndex=" + leader.lastDialogIndex + " trace=" + client.dialogSyncTrace + " phase=" + bot.scenarioCount);

    // scenarioCount: 0 waiting for the leader's pick, 1 lagging behind it, 2 at the choices, 3 pick applied
    if(bot.scenarioCount == 0 && leader.lastDialogCount > 0)
    {
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 1;
    }
    else if(bot.scenarioCount == 1 && bot.ElapsedS() - bot.scenarioTime >= 6)
    {
        W3T_DialogModule().OnDialogChoicesSet(W3T_TestChoices(), false);
        W3T_Log("DIALOG member reached the choices 6 s after the leader picked");
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 2;
    }
    else if(bot.scenarioCount == 2)
    {
        if(!client.hasActiveDialogChoices())
        {
            W3T_Log("DIALOG member: the leader's pick was applied " + FloatToStringPrec(bot.ElapsedS() - bot.scenarioTime, 1) + " s later");
            bot.scenarioCount = 3;
        }
        else if(bot.ElapsedS() - bot.scenarioTime > 8)
        {
            W3T_Log("FAIL the leader's pick was not applied to the lagging member");
            W3T_Quit(1);
            return false;
        }
    }

    return bot.scenarioCount == 3 && coop.trackedApplied >= 2 && tracked == coop.lastTrackedApplied && coop.skipsApplied >= 2;
}

// facts_sync, leader: a fact before the member joins (late-join snapshot) and one after (real time); passes once a
// member has been in the party for 10 s after the second.
function W3T_FactsLeader(bot : W3T_Bot, coop : r_CoopEnemies) : bool
{
    if(bot.scenarioCount == 0)
    {
        if(!coop.FactsReady())
        {
            return false;
        }
        FactsAdd("w3t_coop_fact_a", 3);
        W3T_Log("FACTS leader set w3t_coop_fact_a=" + FactsQuerySum("w3t_coop_fact_a"));
        bot.scenarioCount = 1;
    }
    else if(bot.scenarioCount == 1 && coop.GetRole() == 1)
    {
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 2;
    }
    else if(bot.scenarioCount == 2 && bot.ElapsedS() - bot.scenarioTime >= 3)
    {
        FactsAdd("w3t_coop_fact_b", 4);
        W3T_Log("FACTS leader set w3t_coop_fact_b=" + FactsQuerySum("w3t_coop_fact_b"));
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 3;
    }
    else if(bot.scenarioCount == 3 && bot.ElapsedS() - bot.scenarioTime >= 10)
    {
        bot.scenarioCount = 4;
    }
    return bot.scenarioCount == 4;
}

// facts_sync, member: join 10 s after starting; both of the leader's facts must arrive with the same sums.
function W3T_FactsMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        if(bot.ElapsedS() >= 10)
        {
            W3T_Log("PARTY join " + leader.username + " (late)");
            client.joinParty(leader.username);
        }
        return false;
    }
    W3T_Log("FACTS member a=" + FactsQuerySum("w3t_coop_fact_a") + " b=" + FactsQuerySum("w3t_coop_fact_b")
        + " applied=" + coop.factsApplied + " last=" + coop.lastFactApplied + " ready=" + coop.FactsReady());
    return FactsQuerySum("w3t_coop_fact_a") == 3 && FactsQuerySum("w3t_coop_fact_b") == 4;
}

// puppet_follow, leader: a drowner (or W3T_MONSTER) 14 m from the member's ghost (neutral to this Geralt), so it
// runs to the ghost; passes 20 s later.
function W3T_MovesLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var template : CEntityTemplate;
    var drowner : CNewNPC;
    var path : string;
    var pos : Vector;
    var rot : EulerAngles;

    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1 || !member.ghost)
        {
            return false;
        }
        pos = W3T_SpotInView(member.ghost.GetWorldPosition());
        if(pos.W == 0)
        {
            pos = W3T_WalkableSpot(member.ghost.GetWorldPosition(), 14.0);
        }
        if(pos.W == 0)
        {
            W3T_Log("FAIL no walkable spot 14 m from the ghost");
            W3T_Quit(2);
            return false;
        }
        path = W3T_MonsterPath();
        template = (CEntityTemplate)LoadResource(path, true);
        if(!template)
        {
            W3T_Log("FAIL no template " + path);
            W3T_Quit(2);
            return false;
        }
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioEntity = theGame.CreateEntity(template, pos, rot, true, false, false, PM_DontPersist);
        drowner = (CNewNPC)bot.scenarioEntity;
        drowner.SetAttitude(thePlayer, AIA_Neutral);
        drowner.SetAttitude(member.ghost, AIA_Hostile);
        W3T_Log("MOVES leader spawned " + path + " " + FloatToStringPrec(VecDistance(pos, member.ghost.GetWorldPosition()), 1) + " m from the ghost at " + W3T_VecStr(pos));
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioCount = 1;
        return false;
    }
    drowner = (CNewNPC)bot.scenarioEntity;
    W3T_LookAt(drowner.GetWorldPosition());
    W3T_Log("MOVES leader monster at " + W3T_VecStr(drowner.GetWorldPosition()) + " stride=" + FloatToStringPrec(coop.hostMaxSwing, 3)
        + " bone=" + coop.strideBone + " combat=" + drowner.IsInCombat() + " toMe=" + (int)GetAttitudeBetween(drowner, thePlayer)
        + " toGhost=" + (int)GetAttitudeBetween(drowner, member.ghost) + " target=" + drowner.GetTarget()
        + " action=" + (int)drowner.GetCurrentActionType() + " state=" + NameToString(drowner.GetCurrentStateName()));
    if(bot.scenarioCount == 1 && bot.ElapsedS() - bot.scenarioTime >= 20)
    {
        bot.scenarioCount = 2;
    }
    return bot.scenarioCount == 2;
}

// puppet_follow, member: while the leader's monster runs toward this player's ghost, its puppet never stays more
// than 3.5 m from the leader's position for 1 s (scenarioValue: largest gap seen), and is within 1.5 m once the
// monster has run 8 m.
function W3T_FollowMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var puppet : CNewNPC;
    var gap : float;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(coop.PuppetCount() < 1)
    {
        return false;
    }
    puppet = coop.PuppetAt(0);
    W3T_LookAt(puppet.GetWorldPosition());
    gap = VecDistance(puppet.GetWorldPosition(), coop.PuppetTarget(0));
    if(!bot.scenarioFlag)
    {
        bot.scenarioFlag = true;
        bot.scenarioVec = coop.PuppetTarget(0);
    }
    bot.scenarioValue = MaxF(bot.scenarioValue, gap);
    // a leap shows a gap until the next slide catches up; only a lasting one is lost sync (scenarioTime: since when)
    if(gap <= 3.5)
    {
        bot.scenarioCount = 0;
    }
    else if(bot.scenarioCount == 0)
    {
        bot.scenarioCount = 1;
        bot.scenarioTime = bot.ElapsedS();
    }
    W3T_Log("FOLLOW member puppet at " + W3T_VecStr(puppet.GetWorldPosition()) + " gap=" + FloatToStringPrec(gap, 2)
        + " maxGap=" + FloatToStringPrec(bot.scenarioValue, 2) + " toMe=" + FloatToStringPrec(VecDistance(puppet.GetWorldPosition(), thePlayer.GetWorldPosition()), 1)
        + " stride=" + FloatToStringPrec(coop.puppetMaxSwing, 3) + " bone=" + coop.strideBone);
    if(bot.scenarioCount == 1 && bot.ElapsedS() - bot.scenarioTime >= 1.0)
    {
        W3T_Log("FAIL the puppet stayed " + FloatToStringPrec(gap, 2) + " m behind the leader's monster for 1 s");
        W3T_Quit(1);
        return false;
    }
    // wherever the monster's own AI takes it (some keep their distance from the ghost)
    return VecDistance2D(coop.PuppetTarget(0), bot.scenarioVec) >= 8 && gap < 1.5;
}

function W3T_ReportExtra(bot : W3T_Bot)
{
    var client : r_MultiplayerClient;
    var coop : r_CoopEnemies;
    var players : array<r_RemotePlayer>;
    var globalPlayers : array<r_RemotePlayer>;
    var line : string;
    var i : int;

    client = theGame.r_getMultiplayerClient();
    if(!client)
    {
        W3T_Log("WO client=none");
        return;
    }

    globalPlayers = client.getGlobalPlayers();
    line = "WO user=" + client.getUsername() + " id=" + client.getUserId() + " inGame=" + client.getInGame()
        + " global=" + globalPlayers.Size();

    players = client.getPlayers();
    line += " near=" + players.Size();
    for(i = 0; i < players.Size(); i += 1)
    {
        line += " [" + players[i].username + " pos=" + W3T_VecStr(players[i].pos);
        if(players[i].ghost)
        {
            line += " ghostPos=" + W3T_VecStr(players[i].ghost.GetWorldPosition());
        }
        else
        {
            line += " ghost=none";
        }
        line += "]";
    }
    W3T_Log(line);

    coop = client.getCoopEnemies();
    W3T_Log("COOP role=" + coop.GetRole() + " party=" + client.getInParty() + "/" + client.getJoinedParty()
        + " leaderEnemies=" + coop.HostEnemyCount() + " puppets=" + coop.PuppetCount() + " suppressed=" + coop.SuppressedCount()
        + " hitsSent=" + coop.hitsSent + " hitsApplied=" + coop.hitsApplied + " spawned=" + coop.puppetsSpawned
        + " twins=" + coop.twinsBound + " spawnFailures=" + coop.spawnFailures + " hurtsCaptured=" + coop.hurtsCaptured
        + " hurtsApplied=" + coop.hurtsApplied + " lastError=" + coop.lastError);
}
