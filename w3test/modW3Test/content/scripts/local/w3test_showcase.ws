// showcase: a representative co-op session to film, e.g. run_test.py showcase --size 960x540 --record 240
// --record-from "SHOWCASE start" (with W3T_TICK=0.25). The leader and the member meet, the member joins the party, they
// run together, then fight the leader's monsters side by side: two drowners and a nekker, then two bandits, one with a
// bow. Both swing their swords and cast all five signs; the monsters go for both. Phases in scenarioCount (leader).

function W3T_ShowcaseLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var target : CActor;
    var ahead : Vector;
    var phase : float;

    thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
    phase = bot.ElapsedS() - bot.scenarioTime;
    if(bot.scenarioCount == 0)
    {
        // the member's copy is here: filming starts
        W3T_Log("SHOWCASE start");
        W3T_ShowcaseNext(bot);
        return false;
    }
    if(bot.scenarioCount == 1)
    {
        // greet until the party stands (the member joins after 3 s)
        W3T_LookAt(member.ghost.GetWorldPosition());
        if(coop.GetRole() == 1 && phase > 5)
        {
            bot.scenarioVec = W3T_SpotInView(thePlayer.GetWorldPosition());
            if(bot.scenarioVec.W == 0)
            {
                bot.scenarioVec = thePlayer.GetWorldPosition() + VecFromHeading(theCamera.GetCameraHeading()) * 10.0;
            }
            W3T_Log("SHOWCASE party up; running to " + W3T_VecStr(bot.scenarioVec));
            thePlayer.ActionMoveToAsync(bot.scenarioVec, MT_Run);
            W3T_ShowcaseNext(bot);
        }
        return false;
    }
    if(bot.scenarioCount == 2)
    {
        // run together; the first wave comes once both are there
        W3T_LookAt(bot.scenarioVec);
        if(VecDistance2D(thePlayer.GetWorldPosition(), bot.scenarioVec) < 2.0 || phase > 12)
        {
            if(VecDistance(thePlayer.GetWorldPosition(), member.ghost.GetWorldPosition()) < 6.0 || phase > 20)
            {
                ahead = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 11.0;
                W3T_ShowcaseSpawn(bot, member, "characters\npc_entities\monsters\drowner_lvl1.w2ent", ahead + Vector(2, 0, 0), false);
                W3T_ShowcaseSpawn(bot, member, "characters\npc_entities\monsters\drowner_lvl1.w2ent", ahead + Vector(-2, 1, 0), false);
                W3T_ShowcaseSpawn(bot, member, "characters\npc_entities\monsters\nekker_lvl1.w2ent", ahead + Vector(0, -2, 0), false);
                W3T_Log("SHOWCASE wave 1");
                W3T_ShowcaseNext(bot);
            }
        }
        return false;
    }
    if(bot.scenarioCount == 3 || bot.scenarioCount == 4)
    {
        target = W3T_ShowcaseNearest(bot.scenarioEntities);
        if(target && phase > 75)
        {
            // a fight that drags on: the rest falls, for both
            W3T_Log("SHOWCASE wave took too long; killing the rest");
            W3T_ShowcaseKillAll(bot);
            target = NULL;
        }
        if(target)
        {
            W3T_ShowcaseFight(bot, target);
            return false;
        }
        if(bot.scenarioCount == 4)
        {
            W3T_Log("SHOWCASE wave 2 cleared");
            W3T_ShowcaseNext(bot);
            return false;
        }
        W3T_Log("SHOWCASE wave 1 cleared; wave 2");
        ahead = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 8.0;
        W3T_ShowcaseSpawn(bot, member, "gameplay\community\community_npcs\nml\regular\baron_bandit_strong_sword.w2ent", ahead, true);
        W3T_ShowcaseSpawn(bot, member, "gameplay\community\community_npcs\nml\regular\baron_bandit_weak_bow.w2ent",
            W3T_ShowcaseFar(thePlayer.GetWorldPosition()), true);
        W3T_ShowcaseNext(bot);
        return false;
    }
    // together again
    W3T_LookAt(member.ghost.GetWorldPosition());
    if(phase > 6 && bot.scenarioCount == 5)
    {
        W3T_Log("SHOWCASE done");
        bot.scenarioCount = 6;
    }
    return bot.scenarioCount == 6;
}

// joins the party 3 s after seeing the leader, fights the copies of the leader's monsters next to them, otherwise
// runs after the leader. Done once both waves (5 monsters) fell and nothing came for 8 s.
function W3T_ShowcaseMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var target : CActor;
    var ghostPos : Vector;

    thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
    ghostPos = leader.ghost.GetWorldPosition();
    if(!client.getInParty())
    {
        W3T_LookAt(ghostPos);
        if(bot.scenarioTime == 0)
        {
            bot.scenarioTime = bot.ElapsedS();
        }
        if(!bot.scenarioFlag && bot.ElapsedS() - bot.scenarioTime > 3)
        {
            W3T_Log("PARTY join " + leader.username);
            client.joinParty(leader.username);
            bot.scenarioFlag = true;
        }
        return false;
    }
    target = W3T_ShowcasePuppet(coop);
    if(target)
    {
        bot.scenarioSeenAt = bot.ElapsedS();
        W3T_ShowcaseFight(bot, target);
        return false;
    }
    W3T_LookAt(ghostPos);
    if(VecDistance(thePlayer.GetWorldPosition(), ghostPos) > 4.0 && bot.ElapsedS() - bot.scenarioActAt > 1.0)
    {
        thePlayer.ActionMoveToAsync(ghostPos + VecFromHeading(leader.ghost.GetHeading() + 90) * 2.5, MT_Run);
        bot.scenarioActAt = bot.ElapsedS();
    }
    W3T_Log("SHOWCASE member killed=" + coop.puppetsKilled + " hitsSent=" + coop.hitsSent);
    return coop.puppetsKilled >= 5 && bot.ElapsedS() - bot.scenarioSeenAt > 8;
}

function W3T_ShowcaseNext(bot : W3T_Bot)
{
    bot.scenarioCount += 1;
    bot.scenarioTime = bot.ElapsedS();
}

// one move every 0.8 s against `target`: sword swings and all five signs in turn; runs up to it first
function W3T_ShowcaseFight(bot : W3T_Bot, target : CActor)
{
    var pos : Vector;
    var step : int;

    pos = target.GetWorldPosition();
    W3T_LookAt(pos);
    thePlayer.GoToCombatIfNeeded(target);
    if(VecDistance(thePlayer.GetWorldPosition(), pos) > 3.5)
    {
        if(bot.ElapsedS() - bot.scenarioActAt > 1.0)
        {
            thePlayer.ActionMoveToAsync(pos + VecNormalize(thePlayer.GetWorldPosition() - pos) * 2.0, MT_Run);
            bot.scenarioActAt = bot.ElapsedS();
        }
        return;
    }
    if(bot.ElapsedS() - bot.scenarioActAt < 0.8)
    {
        return;
    }
    bot.scenarioActAt = bot.ElapsedS();
    step = bot.scenarioStep % 12;
    bot.scenarioStep += 1;
    if(step == 2 || step == 7)
    {
        thePlayer.SetupCombatAction(EBAT_HeavyAttack, BS_Released);
    }
    else if(step == 3)
    {
        W3T_ShowcaseSign(ST_Igni);
    }
    else if(step == 6)
    {
        W3T_ShowcaseSign(ST_Aard);
    }
    else if(step == 8)
    {
        W3T_ShowcaseSign(ST_Yrden);
    }
    else if(step == 10)
    {
        W3T_ShowcaseSign(ST_Quen);
    }
    else if(step == 11)
    {
        W3T_ShowcaseSign(ST_Axii);
    }
    else
    {
        thePlayer.SetupCombatAction(EBAT_LightAttack, BS_Pressed);
    }
}

function W3T_ShowcaseSign(sign : ESignType)
{
    GetWitcherPlayer().SetEquippedSign(sign);
    thePlayer.GainStat(BCS_Stamina, thePlayer.GetStatMax(BCS_Stamina));
    thePlayer.SetupCombatAction(EBAT_CastSign, BS_Pressed);
}

// hostile to both players; `notice`: humans spawned alone don't look for a fight by themselves
function W3T_ShowcaseSpawn(bot : W3T_Bot, member : r_RemotePlayer, path : string, at : Vector, notice : bool)
{
    var template : CEntityTemplate;
    var npc : CNewNPC;
    var spot : Vector;
    var rot : EulerAngles;

    template = (CEntityTemplate)LoadResource(path, true);
    if(!template)
    {
        W3T_Log("SHOWCASE no template " + path);
        return;
    }
    if(!theGame.GetWorld().NavigationFindSafeSpot(at, 0.5, 3.0, spot))
    {
        spot = at;
    }
    rot.Yaw = VecHeading(thePlayer.GetWorldPosition() - spot);
    npc = (CNewNPC)theGame.CreateEntity(template, spot, rot, true, false, false, PM_DontPersist);
    if(!npc)
    {
        return;
    }
    npc.SetAttitude(thePlayer, AIA_Hostile);
    npc.SetAttitude(member.ghost, AIA_Hostile);
    if(notice)
    {
        npc.NoticeActor(thePlayer);
        npc.NoticeActor(member.ghost);
    }
    bot.scenarioEntities.PushBack(npc);
    W3T_Log("SHOWCASE spawned " + path + " at " + W3T_VecStr(spot));
}

// the archer's spot: 12-14 m away, in view
function W3T_ShowcaseFar(from : Vector) : Vector
{
    var spot : Vector;

    spot = W3T_SpotInView(from);
    if(spot.W == 0)
    {
        spot = from + VecFromHeading(theCamera.GetCameraHeading()) * 12.0;
    }
    return spot;
}

function W3T_ShowcaseNearest(list : array<CEntity>) : CActor
{
    var i : int;
    var actor, best : CActor;
    var dist, bestDist : float;

    bestDist = 1000;
    for(i = 0; i < list.Size(); i += 1)
    {
        actor = (CActor)list[i];
        if(actor && actor.IsAlive())
        {
            dist = VecDistance(thePlayer.GetWorldPosition(), actor.GetWorldPosition());
            if(dist < bestDist)
            {
                bestDist = dist;
                best = actor;
            }
        }
    }
    return best;
}

function W3T_ShowcasePuppet(coop : r_CoopEnemies) : CActor
{
    var puppets : array<CEntity>;
    var i : int;

    for(i = 0; i < coop.PuppetCount(); i += 1)
    {
        puppets.PushBack(coop.PuppetAt(i));
    }
    return W3T_ShowcaseNearest(puppets);
}

function W3T_ShowcaseKillAll(bot : W3T_Bot)
{
    var i : int;
    var actor : CActor;

    for(i = 0; i < bot.scenarioEntities.Size(); i += 1)
    {
        actor = (CActor)bot.scenarioEntities[i];
        if(actor && actor.IsAlive())
        {
            actor.Kill('W3T_Showcase', true);
        }
    }
}
