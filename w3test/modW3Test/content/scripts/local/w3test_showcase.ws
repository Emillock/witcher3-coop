// showcase: a representative co-op session to film, e.g. run_test.py showcase --size 960x540 --record 300
// --record-from "SHOWCASE start" (with W3T_TICK=0.25). The member joins the leader's party in Novigrad; the leader sets
// the time to noon (members follow the leader's time) and both go to the nearest monster nest. Filming starts there:
// they fight the nest's own monsters side by side (the same encounter in both worlds, shared), run on together, then
// fight two drowners and a bandit archer the leader brings in. Both swing their swords and cast all five signs; the
// monsters go for both. The leader's monsters are brought down to 12% health so the waves end in kills within a minute
// (their copies follow, health is synced). Phases in scenarioCount.

function W3T_ShowcaseLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var target : CActor;
    var label : string;
    var spot : Vector;
    var phase : float;

    thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
    phase = bot.ElapsedS() - bot.scenarioTime;
    if(bot.scenarioCount >= 2)
    {
        W3T_HoldAt(bot.scenarioVec);
    }
    if(bot.scenarioCount == 0)
    {
        // once the party stands: noon, and off to the nest
        if(coop.GetRole() != 1)
        {
            return false;
        }
        bot.scenarioVec = W3T_NearestNest(label);
        if(bot.scenarioVec.W == 0)
        {
            W3T_Log("SHOWCASE no monster nest in " + label);
            W3T_Quit(2);
            return false;
        }
        theGame.SetGameTime(GameTimeCreate(GameTimeDays(theGame.GetGameTime()) + 1, 12, 0, 0), true);
        RequestWeatherChangeTo('WT_Clear', 0, false);
        thePlayer.Teleport(bot.scenarioVec + Vector(0, 0, 2));
        W3T_Log("SHOWCASE party up; going to nest " + label + " at " + W3T_VecStr(bot.scenarioVec));
        W3T_ShowcaseNext(bot);
        return false;
    }
    if(bot.scenarioCount == 1)
    {
        // the navigation mesh needs some seconds after a long teleport
        if(phase >= 6)
        {
            if(!theGame.GetWorld().NavigationFindSafeSpot(bot.scenarioVec + Vector(8, 0, 0), 0.5, 8.0, spot))
            {
                spot = bot.scenarioVec + Vector(8, 0, 1);
            }
            thePlayer.Teleport(spot);
            bot.scenarioVec = spot;
            W3T_ShowcaseNext(bot);
        }
        return false;
    }
    if(bot.scenarioCount == 2)
    {
        // filming starts once the member stands here too
        W3T_LookAt(member.ghost.GetWorldPosition());
        if(VecDistance(thePlayer.GetWorldPosition(), member.ghost.GetWorldPosition()) < 30 || phase > 40)
        {
            W3T_Log("SHOWCASE start");
            W3T_ShowcaseNext(bot);
        }
        return false;
    }
    if(bot.scenarioCount == 3)
    {
        W3T_LookAt(member.ghost.GetWorldPosition());
        if(phase > 3)
        {
            W3T_ShowcaseNext(bot);
        }
        return false;
    }
    if(bot.scenarioCount == 4 || bot.scenarioCount == 6)
    {
        // a wave: the nest's own monsters, then the ones brought in
        W3T_ShowcaseWeaken(bot, coop);
        target = W3T_ShowcaseHostTarget(coop);
        if(target && bot.ElapsedS() - bot.scenarioValue >= 2)
        {
            bot.scenarioValue = bot.ElapsedS();
            W3T_Log("SHOWCASE fighting " + target.GetReadableName() + " hp=" + FloatToStringPrec(target.GetHealthPercents(), 2)
                + " dist=" + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(), target.GetWorldPosition()), 1)
                + " enemies=" + coop.HostEnemyCount() + " member=" + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(),
                member.ghost.GetWorldPosition()), 1));
        }
        // one that keeps out of reach (an archer on a slope) would stall the wave: after 10 s it falls
        if(target && VecDistance(thePlayer.GetWorldPosition(), target.GetWorldPosition()) > 6)
        {
            if(bot.scenarioFarSince == 0)
            {
                bot.scenarioFarSince = bot.ElapsedS();
            }
            else if(bot.ElapsedS() - bot.scenarioFarSince > 10)
            {
                W3T_Log("SHOWCASE " + target.GetReadableName() + " keeps out of reach; it falls");
                target.Kill('W3T_Showcase', true);
                bot.scenarioFarSince = 0;
                return false;
            }
        }
        else
        {
            bot.scenarioFarSince = 0;
        }
        if(target && phase > 60)
        {
            W3T_Log("SHOWCASE wave took too long; the rest falls");
            W3T_ShowcaseKillAll(coop);
            target = NULL;
        }
        if(target)
        {
            bot.scenarioSeenAt = bot.ElapsedS();
            W3T_ShowcaseFight(bot, target);
            return false;
        }
        if(bot.scenarioSeenAt == 0 && phase < 15)
        {
            // the nest's monsters may take a moment to show up
            W3T_LookAt(member.ghost.GetWorldPosition());
            return false;
        }
        W3T_Log("SHOWCASE wave cleared");
        if(bot.scenarioCount == 4)
        {
            // back to the clearing where they arrived (the chase scatters them; around a nest it's mostly thick forest)
            spot = bot.scenarioVec;
            spot.W = 1;
            if(VecDistance2D(thePlayer.GetWorldPosition(), spot) < 5)
            {
                spot = W3T_SpotInView(thePlayer.GetWorldPosition());
            }
            if(spot.W != 0)
            {
                bot.scenarioVec = spot;
                thePlayer.ActionMoveToAsync(spot, MT_Run);
                W3T_Log("SHOWCASE running on to " + W3T_VecStr(spot));
            }
        }
        bot.scenarioSeenAt = 0;
        W3T_ShowcaseNext(bot);
        return false;
    }
    if(bot.scenarioCount == 5)
    {
        // run on together; the next wave comes once both are there
        W3T_LookAt(bot.scenarioVec);
        if((VecDistance2D(thePlayer.GetWorldPosition(), bot.scenarioVec) < 2.5 || phase > 12)
            && (VecDistance(thePlayer.GetWorldPosition(), member.ghost.GetWorldPosition()) < 8 || phase > 20))
        {
            spot = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 6.0;
            W3T_ShowcaseSpawn(bot, member, "characters\npc_entities\monsters\drowner_lvl1.w2ent", spot + Vector(2, 0, 0), false);
            W3T_ShowcaseSpawn(bot, member, "characters\npc_entities\monsters\drowner_lvl1.w2ent", spot + Vector(-2, 1, 0), false);
            W3T_ShowcaseSpawn(bot, member, "gameplay\community\community_npcs\nml\regular\baron_bandit_weak_bow.w2ent",
                spot + VecFromHeading(thePlayer.GetHeading()) * 3.0 + Vector(4, 0, 0), true);
            W3T_Log("SHOWCASE second wave");
            W3T_ShowcaseNext(bot);
        }
        return false;
    }
    // together again
    W3T_LookAt(member.ghost.GetWorldPosition());
    if(bot.scenarioCount == 7 && phase > 6)
    {
        W3T_Log("SHOWCASE done");
        W3T_ShowcaseNext(bot);
    }
    return bot.scenarioCount == 8;
}

// joins the party 3 s after seeing the leader, goes to the same nest, fights the copies of the leader's monsters near
// the leader (both in one shot), otherwise runs after the leader. Done after two waves and 10 s without enemies.
function W3T_ShowcaseMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var target : CActor;
    var ghostPos, spot : Vector;
    var label : string;

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
    if(bot.scenarioCount == 0)
    {
        bot.scenarioVec = W3T_NearestNest(label);
        if(bot.scenarioVec.W == 0)
        {
            return false;
        }
        thePlayer.Teleport(bot.scenarioVec + Vector(0, 0, 2));
        W3T_Log("SHOWCASE member going to nest " + label);
        W3T_ShowcaseNext(bot);
        return false;
    }
    if(bot.scenarioCount == 1)
    {
        if(bot.ElapsedS() - bot.scenarioTime >= 6)
        {
            if(!theGame.GetWorld().NavigationFindSafeSpot(bot.scenarioVec + Vector(6, 3, 0), 0.5, 8.0, spot))
            {
                spot = bot.scenarioVec + Vector(6, 3, 1);
            }
            thePlayer.Teleport(spot);
            bot.scenarioVec = spot;
            W3T_ShowcaseNext(bot);
        }
        return false;
    }
    W3T_HoldAt(bot.scenarioVec);

    target = W3T_ShowcasePuppet(coop, ghostPos);
    if(target)
    {
        if(bot.ElapsedS() - bot.scenarioSeenAt > 5)
        {
            bot.scenarioValue += 1;
            W3T_Log("SHOWCASE member wave " + FloatToStringPrec(bot.scenarioValue, 0));
        }
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
    return bot.scenarioValue >= 2 && bot.ElapsedS() - bot.scenarioSeenAt > 10;
}

// each of the leader's monsters once, as it shows up: 12% health
function W3T_ShowcaseWeaken(bot : W3T_Bot, coop : r_CoopEnemies)
{
    var i : int;
    var npc : CNewNPC;

    for(i = 0; i < coop.HostEnemyCount(); i += 1)
    {
        npc = coop.HostEnemyAt(i);
        if(npc && npc.IsAlive() && !bot.scenarioEntities.Contains(npc))
        {
            npc.SetHealthPerc(0.12);
            bot.scenarioEntities.PushBack(npc);
        }
    }
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
    W3T_Log("SHOWCASE spawned " + path + " at " + W3T_VecStr(spot));
}

function W3T_ShowcaseNearest(list : array<CActor>) : CActor
{
    var i : int;
    var best : CActor;
    var dist, bestDist : float;

    bestDist = 1000;
    for(i = 0; i < list.Size(); i += 1)
    {
        if(list[i] && list[i].IsAlive())
        {
            dist = VecDistance(thePlayer.GetWorldPosition(), list[i].GetWorldPosition());
            if(dist < bestDist)
            {
                bestDist = dist;
                best = list[i];
            }
        }
    }
    return best;
}

// the leader's monsters near it (the co-op layer's list: the nest's own and the ones spawned)
function W3T_ShowcaseHostTarget(coop : r_CoopEnemies) : CActor
{
    var enemies : array<CActor>;
    var i : int;

    for(i = 0; i < coop.HostEnemyCount(); i += 1)
    {
        enemies.PushBack(coop.HostEnemyAt(i));
    }
    return W3T_ShowcaseNearest(enemies);
}

// the nearest copy within 12 m of the leader, else the nearest at all
function W3T_ShowcasePuppet(coop : r_CoopEnemies, leaderPos : Vector) : CActor
{
    var puppets, near : array<CActor>;
    var i : int;

    for(i = 0; i < coop.PuppetCount(); i += 1)
    {
        puppets.PushBack(coop.PuppetAt(i));
        if(VecDistance(coop.PuppetAt(i).GetWorldPosition(), leaderPos) < 12)
        {
            near.PushBack(coop.PuppetAt(i));
        }
    }
    if(W3T_ShowcaseNearest(near))
    {
        return W3T_ShowcaseNearest(near);
    }
    return W3T_ShowcaseNearest(puppets);
}

function W3T_ShowcaseKillAll(coop : r_CoopEnemies)
{
    var i : int;

    for(i = 0; i < coop.HostEnemyCount(); i += 1)
    {
        if(coop.HostEnemyAt(i).IsAlive())
        {
            coop.HostEnemyAt(i).Kill('W3T_Showcase', true);
        }
    }
}
