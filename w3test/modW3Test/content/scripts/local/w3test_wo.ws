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
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Default);
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
// manager (15 % of max health each). Each hit must come back from the leader as the same health (within 2 %);
// then the puppet must die when the leader kills it, with no second drowner in this world.
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

    // scenarioCount: hits confirmed so far (0-3), then 5 once the death was seen
    if(bot.scenarioCount < 3)
    {
        if(bot.scenarioValue == 0)
        {
            action = new W3DamageAction in theGame.damageMgr;
            action.Initialize(thePlayer, puppet, thePlayer, "W3T", EHRT_Light, CPS_Undefined, true, false, false, false);
            action.AddDamage(theGame.params.DAMAGE_NAME_DIRECT, 0.15 * puppet.GetMaxHealth());
            theGame.damageMgr.ProcessAction(action);
            delete action;
            bot.scenarioValue = 1.0 - 0.15 * (bot.scenarioCount + 1);
            bot.scenarioTime = bot.ElapsedS();
            W3T_Log("HIT " + (bot.scenarioCount + 1) + " sent, expect hp " + FloatToStringPrec(bot.scenarioValue, 2));
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
            bot.scenarioValue = 0;
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
        + " twins=" + coop.twinsBound + " spawnFailures=" + coop.spawnFailures + " lastError=" + coop.lastError);
}
