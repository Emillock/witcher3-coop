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

    players = client.getPlayers();
    for(i = 0; i < players.Size(); i += 1)
    {
        if(players[i].ghost)
        {
            ghosts += 1;
        }
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

// enemy_attacks, leader: spawn a drowner next to the member's ghost, neutral to this Geralt so the ghost is its
// only target. Passes once at least two of its hits on the ghost were sent and acknowledged.
function W3T_EnemyAttacksLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
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
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
        if(!template)
        {
            W3T_Log("FAIL drowner template not found");
            W3T_Quit(2);
            return false;
        }
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        pos = member.ghost.GetWorldPosition() + VecFromHeading(member.ghost.GetHeading()) * 3.0;
        rot = member.ghost.GetWorldRotation();
        bot.scenarioEntity = theGame.CreateEntity(template, pos, rot, true, false, false, PM_DontPersist);
        drowner = (CNewNPC)bot.scenarioEntity;
        drowner.SetAttitude(thePlayer, AIA_Neutral);
        W3T_Log("ENEMY spawned drowner next to " + member.username + "'s ghost at " + W3T_VecStr(pos));
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
        + " attacks=" + coop.attacksSeen
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

    W3T_Log("ENEMY member vitality=" + FloatToStringPrec(thePlayer.GetStat(BCS_Vitality), 0) + " hurtsApplied=" + coop.hurtsApplied
        + " dodged=" + coop.hurtsDodged + " damageTaken=" + FloatToStringPrec(coop.hurtDamageTaken, 1) + " puppets=" + coop.PuppetCount()
        + " attacksPlayed=" + coop.attacksPlayed + " attackFailures=" + coop.attackPlayFailures
        + " lastHurtDelay=" + FloatToStringPrec(coop.lastHurtDelay, 2) + " lastError=" + coop.lastError);

    if(coop.attackPlayFailures > 0)
    {
        W3T_Log("FAIL the puppet could not play the leader's attack: " + coop.lastError);
        W3T_Quit(1);
        return false;
    }

    // the drowner's swings show on its puppet, and its hits land
    if(bot.scenarioCount == 0 && coop.hurtsApplied >= 2 && coop.hurtDamageTaken > 0 && coop.attacksPlayed >= 1)
    {
        W3T_Log("ENEMY member took " + FloatToStringPrec(coop.hurtDamageTaken, 1) + " damage from " + coop.hurtsApplied
            + " of the leader's drowner hits; its puppet played " + coop.attacksPlayed + " attacks");
        // survive the rest of the run
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioCount = 1;
    }
    return bot.scenarioCount == 1;
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
