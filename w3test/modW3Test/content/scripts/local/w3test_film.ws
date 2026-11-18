// film: one unbroken co-op session to record, played rather than staged. It opens where the save starts, with both
// players standing together: they share a horse, greet each other, travel to the nearest monster nest and there fight
// its monsters side by side with swords and signs, shoot the crossbow, take a limb off one, loot what a shared kill
// leaves, charm another to fight for them, and open the player menu.
// Every chapter is logged as "FILM chapter <name>", which is where montage.py cuts; filming starts at "FILM ready",
// which both games log. The only teleport after that is the travel to the nest, which has a chapter of its own so
// that the reel can leave it out; anything else that has to be closed outright says so in the log.
// Usage: run_test.py film --size 960x540 --record 300 --record-from "FILM ready" (with W3T_TICK=0.25).

function W3T_FilmNext(bot : W3T_Bot, chapter : string)
{
    bot.scenarioCount += 1;
    bot.scenarioTime = bot.ElapsedS();
    bot.scenarioStep = 0;
    bot.scenarioSeenAt = 0;
    if(chapter != "")
    {
        W3T_Log("FILM chapter " + chapter);
    }
}

// the film's camera: at what is happening, from far enough back that both players and the monster are in the
// picture (the default sits close behind a shoulder, which in a forest is mostly fern)
function W3T_FilmCamera(target : Vector)
{
    theGame.GetGameCamera().GetActivePivotRotationController().SetDesiredHeading(
        VecHeading(target - thePlayer.GetWorldPosition()));
    theGame.GetGameCamera().GetActivePivotRotationController().SetDesiredPitch(-14.0);
    theGame.GetGameCamera().GetActivePivotDistanceController().SetDesiredDistance(5.5);
}

function W3T_FilmDrowner() : string
{
    return "characters\npc_entities\monsters\drowner_lvl1.w2ent";
}

function W3T_FilmBandit() : string
{
    return "gameplay\community\community_npcs\nml\regular\baron_bandit_strong_sword.w2ent";
}

// a spot a few metres ahead of the leader, on the navigation mesh where there is one
function W3T_FilmAhead(metres : float) : Vector
{
    var want, spot : Vector;

    want = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * metres;
    if(theGame.GetWorld().NavigationFindSafeSpot(want, 0.5, 4.0, spot))
    {
        return spot;
    }
    return want;
}

function W3T_FilmFarTarget(coop : r_CoopEnemies) : CActor
{
    var best : CActor;
    var npc : CNewNPC;
    var dist, bestDist : float;
    var i : int;

    for(i = 0; i < coop.HostEnemyCount(); i += 1)
    {
        npc = coop.HostEnemyAt(i);
        if(!npc || !npc.IsAlive())
        {
            continue;
        }
        dist = VecDistance(thePlayer.GetWorldPosition(), npc.GetWorldPosition());
        if(dist > bestDist && dist < 30)
        {
            bestDist = dist;
            best = npc;
        }
    }
    return best;
}

// a monster this many metres off, on ground it can stand on, asked for again every 6 s until one is there
function W3T_FilmSpawnAgain(bot : W3T_Bot, member : r_RemotePlayer, path : string, metres : float)
{
    var spot : Vector;

    if(bot.ElapsedS() - bot.scenarioActAt < 6.0)
    {
        return;
    }
    bot.scenarioActAt = bot.ElapsedS();
    bot.scenarioStep += 1;
    spot = W3T_WalkableSpot(thePlayer.GetWorldPosition(), metres);
    if(spot.W == 0)
    {
        spot = W3T_FilmAhead(metres);
    }
    W3T_ShowcaseSpawn(bot, member, path, spot, metres > 8);
}

// film, leader: runs the session chapter by chapter. Chapters 0-2 are the setting up, before the recording starts.
function W3T_FilmLeader(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var phase : float;
    var spot, ghostPos : Vector;
    var label : string;
    var target : CActor;
    var npc, horse : CNewNPC;
    var params : SCustomEffectParams;
    var dc : CDismembermentComponent;
    var wounds : array<name>;

    thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
    phase = bot.ElapsedS() - bot.scenarioTime;
    if(bot.scenarioCount >= 5)
    {
        W3T_HoldAt(bot.scenarioVec);
    }
    ghostPos = thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 6.0;
    if(member.ghost)
    {
        ghostPos = member.ghost.GetWorldPosition();   // without one, the camera looks ahead rather than at nothing
    }
    // a monster's attack pulls a rider off his horse, and a nest sends them without pause: while the two of them
    // settle, gather and ride, what the nest has sent is cleared away
    if(bot.scenarioCount <= 4)
    {
        W3T_ShowcaseKillAll(coop);
    }

    // 0: where the save starts, both players already standing together: noon, clear weather, and onto the horse
    //    before anyone is filming (getting on one a second time is refused on this build)
    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1 || !member.ghost)
        {
            return false;
        }
        if(bot.scenarioStep == 0)
        {
            bot.scenarioStep = 1;
            bot.scenarioVec = W3T_NearestNest(label);
            if(bot.scenarioVec.W == 0)
            {
                W3T_Log("FILM no monster nest in " + label);
                W3T_Quit(2);
                return false;
            }
            W3T_Log("FILM the nest for the fighting: " + label);
            theGame.SetGameTime(GameTimeCreate(GameTimeDays(theGame.GetGameTime()) + 1, 12, 0, 0), true);
            RequestWeatherChangeTo('WT_Clear', 0, false);
            return false;
        }
        if(thePlayer.IsUsingHorse())
        {
            W3T_Log("FILM the leader waits on horseback");
            W3T_FilmNext(bot, "");
            return false;
        }
        if(phase >= 50)
        {
            W3T_Log("FILM no horse came");
            W3T_FilmNext(bot, "");
            return false;
        }
        if(bot.ElapsedS() - bot.scenarioActAt >= 6.0)
        {
            bot.scenarioActAt = bot.ElapsedS();
            InstantMountPlayer('None', EVT_Horse, false, false);
        }
        return false;
    }
    // 1: the recording starts once the member is standing here too
    if(bot.scenarioCount == 1)
    {
        if(!member.ghost)
        {
            return false;
        }
        W3T_FilmCamera(ghostPos);
        if(bot.scenarioStep == 0 && (VecDistance(thePlayer.GetWorldPosition(), ghostPos) < 25 || phase > 70))
        {
            bot.scenarioStep = 1;
            bot.scenarioValue = bot.ElapsedS();
            W3T_Log("FILM ready");
        }
        // the recorder waits for that line in both games and then a moment more: the chapter starts after it
        if(bot.scenarioStep == 1 && bot.ElapsedS() - bot.scenarioValue > 7)
        {
            W3T_FilmNext(bot, "ride");
        }
        return false;
    }
    // 2: one horse, two riders - the leader is already on it, the member climbs on behind
    if(bot.scenarioCount == 2)
    {
        W3T_FilmCamera(ghostPos);
        if(bot.scenarioStep == 0)
        {
            bot.scenarioStep = 1;
            mpghosts_chat("Climb on.");     // the member's run to the horse starts from this word
        }
        if(!thePlayer.IsUsingHorse())
        {
            if(bot.ElapsedS() - bot.scenarioActAt >= 5.0)
            {
                bot.scenarioActAt = bot.ElapsedS();
                InstantMountPlayer('None', EVT_Horse, false, false);
                W3T_Log("FILM the leader is not on its horse; asking again");
            }
            if(phase > 20)
            {
                W3T_FilmNext(bot, "meet");
            }
            return false;
        }
        if(member.isRiding && bot.scenarioSeenAt == 0)
        {
            bot.scenarioSeenAt = bot.ElapsedS();
            W3T_Log("FILM the member is on the horse");
            mpghosts_chat("Hold on.");
        }
        if((bot.scenarioSeenAt > 0 && bot.ElapsedS() - bot.scenarioSeenAt > 12) || phase > 40)
        {
            thePlayer.DismountVehicle(thePlayer.GetHorseCurrentlyMounted(), DT_normal);
            W3T_Log("FILM both get off");
            W3T_FilmNext(bot, "meet");
        }
        return false;
    }
    // 3: a word and a wave, back on their feet
    if(bot.scenarioCount == 3)
    {
        W3T_FilmCamera(ghostPos);
        if(bot.scenarioStep == 0 && phase > 2)
        {
            bot.scenarioStep = 1;
            mpghosts_chat("Well met, friend.");
        }
        else if(bot.scenarioStep == 1 && phase > 5)
        {
            bot.scenarioStep = 2;
            mpghosts_emote(0);
        }
        else if(bot.scenarioStep == 2 && phase > 9)
        {
            bot.scenarioStep = 3;
            mpghosts_chat("Come on, there's work.");
        }
        if(phase > 14)
        {
            client.clearLocalEmoteState();
            W3T_FilmNext(bot, "travel");
        }
        return false;
    }
    // 4: to the nest - a teleport for both of them, which is why this chapter is not in the reel
    if(bot.scenarioCount == 4)
    {
        if(bot.scenarioStep == 0)
        {
            bot.scenarioStep = 1;
            mpghosts_chat("To the nest.");
            return false;
        }
        if(bot.scenarioStep == 1 && phase > 2)
        {
            bot.scenarioStep = 2;
            thePlayer.Teleport(bot.scenarioVec + Vector(0, 0, 2));
            W3T_Log("FILM both travel to the nest");
            return false;
        }
        if(bot.scenarioStep == 2 && phase > 10)
        {
            bot.scenarioStep = 3;
            // close to the nest itself: the ground is open there, while a few metres out it is fern to the chest
            if(!theGame.GetWorld().NavigationFindSafeSpot(bot.scenarioVec + Vector(4, 0, 0), 0.5, 6.0, spot))
            {
                spot = bot.scenarioVec + Vector(4, 0, 1);
            }
            thePlayer.Teleport(spot);
            bot.scenarioVec = spot;
            return false;
        }
        if(bot.scenarioStep == 3 && phase > 16)
        {
            W3T_FilmNext(bot, "run");
        }
        return false;
    }
    // 5: running on together, to where the nest's monsters come from
    if(bot.scenarioCount == 5)
    {
        if(bot.scenarioStep == 0 && phase > 2)
        {
            bot.scenarioStep = 1;
            spot = W3T_SpotInView(thePlayer.GetWorldPosition());
            if(spot.W == 0)
            {
                spot = W3T_FilmAhead(12.0);
            }
            bot.scenarioPos = spot;
            thePlayer.ActionMoveToAsync(spot, MT_Run);
            W3T_Log("FILM leader runs to " + W3T_VecStr(spot));
        }
        W3T_FilmCamera(bot.scenarioPos);
        if(phase > 12 || (bot.scenarioStep == 1 && VecDistance2D(thePlayer.GetWorldPosition(), bot.scenarioPos) < 2.5))
        {
            W3T_FilmNext(bot, "fight");
        }
        return false;
    }
    // 6: the nest's own monsters, fought with sword and signs; two drowners if the nest is slow
    if(bot.scenarioCount == 6)
    {
        W3T_ShowcaseWeaken(bot, coop);
        target = W3T_ShowcaseHostTarget(coop);
        // the nest's own stock was cleared so that the ride could happen, and it refills slowly: this chapter
        // keeps two or three monsters in the fight itself
        if(coop.HostEnemyCount() < 2 && bot.ElapsedS() - bot.scenarioUntil >= 8.0)
        {
            bot.scenarioUntil = bot.ElapsedS();
            spot = W3T_WalkableSpot(thePlayer.GetWorldPosition(), 9.0);
            if(spot.W == 0)
            {
                spot = W3T_FilmAhead(9.0);
            }
            W3T_ShowcaseSpawn(bot, member, W3T_FilmDrowner(), spot, true);
            W3T_ShowcaseSpawn(bot, member, W3T_FilmDrowner(), spot + Vector(2, 2, 0), true);
        }
        if(phase > 70)
        {
            W3T_ShowcaseKillAll(coop);
            W3T_FilmNext(bot, "bolt");
            return false;
        }
        if(target)
        {
            bot.scenarioSeenAt = bot.ElapsedS();
            W3T_ShowcaseFight(bot, target);
            if(bot.ElapsedS() - bot.scenarioValue >= 3)
            {
                bot.scenarioValue = bot.ElapsedS();
                W3T_Log("FILM fighting " + target.GetReadableName() + " hp="
                    + FloatToStringPrec(target.GetHealthPercents(), 2) + " shared=" + coop.HostEnemyCount()
                    + " member " + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(), ghostPos), 1) + " m off");
            }
            return false;
        }
        if(phase > 35 && bot.scenarioSeenAt > 0 && bot.ElapsedS() - bot.scenarioSeenAt > 4)
        {
            W3T_ShowcaseKillAll(coop);
            W3T_FilmNext(bot, "bolt");
        }
        return false;
    }
    // 7: the crossbow, at one that is still a way off
    if(bot.scenarioCount == 7)
    {
        target = W3T_FilmFarTarget(coop);
        if(!target)
        {
            W3T_FilmSpawnAgain(bot, member, W3T_FilmDrowner(), 12.0);
            if(phase > 22)
            {
                W3T_ShowcaseKillAll(coop);
                W3T_FilmNext(bot, "wound");
            }
            return false;
        }
        W3T_FilmCamera(target.GetWorldPosition());
        if(bot.ElapsedS() - bot.scenarioActAt >= 2.0)
        {
            bot.scenarioActAt = bot.ElapsedS();
            W3T_ShootBolt(target);
            bot.scenarioStep += 1;
        }
        if(phase > 22)
        {
            W3T_FilmNext(bot, "wound");
        }
        return false;
    }
    // 8: a killing blow that takes a limb, in both worlds
    if(bot.scenarioCount == 8)
    {
        if(coop.HostEnemyCount() < 1)
        {
            W3T_FilmSpawnAgain(bot, member, W3T_FilmDrowner(), 6.0);
            if(phase > 30)
            {
                W3T_FilmNext(bot, "loot");
            }
            return false;
        }
        npc = coop.HostEnemyAt(0);
        W3T_FilmCamera(npc.GetWorldPosition());
        // the copy needs a moment, and a swing or two reads better than a monster that simply falls apart
        if(phase < 7)
        {
            W3T_ShowcaseFight(bot, npc);
            return false;
        }
        dc = (CDismembermentComponent)npc.GetComponentByClassName('CDismembermentComponent');
        if(dc)
        {
            dc.GetWoundsNames(wounds);
        }
        if(wounds.Size() > 0)
        {
            npc.SetDismembermentInfo(wounds[0], npc.GetWorldPosition() - thePlayer.GetWorldPosition(), false);
            npc.SetBehaviorVariable('dismemberAnim', 1.0);
            npc.Kill('W3TFilm', true);
            npc.AddTimer('DelayedDismemberTimer', 0.05);
            W3T_Log("FILM the killing blow takes " + NameToString(wounds[0]) + "; wounds seen " + coop.woundsSeen);
        }
        else
        {
            W3T_Log("FILM no wound is defined on " + npc.GetReadableName() + "; it just falls");
            npc.Kill('W3TFilm', true);
        }
        W3T_FilmNext(bot, "loot");
        return false;
    }
    // 9: what a shared kill leaves, for the member to take
    if(bot.scenarioCount == 9)
    {
        if(bot.scenarioMark == 0)
        {
            bot.scenarioMark = coop.dropItemsSent + 1;   // a drop of this chapter's own, not one from before
        }
        target = W3T_ShowcaseHostTarget(coop);
        if(!target)
        {
            W3T_FilmSpawnAgain(bot, member, W3T_FilmDrowner(), 5.0);
            if(phase > 45 || (phase > 22 && coop.dropItemsSent >= bot.scenarioMark))
            {
                bot.scenarioMark = 0;
                W3T_FilmNext(bot, "axii");
            }
            return false;
        }
        // not weakened here: it has to live long enough for its copy to stand in the member's world, and the
        // leader strikes it down only after that
        if(phase > 12)
        {
            W3T_ShowcaseFight(bot, target);
        }
        else
        {
            W3T_FilmCamera(target.GetWorldPosition());
        }
        if(phase > 45)
        {
            bot.scenarioMark = 0;
            W3T_FilmNext(bot, "axii");
        }
        return false;
    }
    // 10: Axii's puppet, which fights for the party in both worlds
    if(bot.scenarioCount == 10)
    {
        if(bot.scenarioStep == 0)
        {
            bot.scenarioStep = 1;
            spot = W3T_FilmAhead(7.0);
            W3T_ShowcaseSpawn(bot, member, W3T_FilmBandit(), spot, true);
            W3T_ShowcaseSpawn(bot, member, W3T_FilmBandit(), spot + Vector(3, 1, 0), true);
            return false;
        }
        npc = (CNewNPC)W3T_ShowcaseHostTarget(coop);
        if(bot.scenarioStep == 1 && npc && phase > 7)
        {
            bot.scenarioStep = 2;
            params.effectType = EET_AxiiGuardMe;
            params.creator = thePlayer;
            params.sourceName = "W3TFilm";
            params.duration = 60;
            npc.AddEffectCustom(params);
            W3T_Log("FILM the leader charms " + npc.GetReadableName() + " charmed=" + npc.HasBuff(EET_AxiiGuardMe));
        }
        if(npc)
        {
            W3T_FilmCamera(npc.GetWorldPosition());
        }
        if(bot.scenarioStep == 2 && bot.ElapsedS() - bot.scenarioValue >= 3)
        {
            bot.scenarioValue = bot.ElapsedS();
            W3T_Log("FILM charmed shared=" + coop.HostEnemyCount() + " charmedTicks=" + coop.charmedShared
                + " dropped=" + coop.charmedHurtsDropped);
        }
        if(phase > 30)
        {
            W3T_FilmNext(bot, "menu");
        }
        return false;
    }
    // 11: the player menu, which the member opens on the leader
    if(bot.scenarioCount == 11)
    {
        W3T_FilmCamera(ghostPos);
        if(bot.scenarioStep == 0 && phase > 1)
        {
            bot.scenarioStep = 1;
            mpghosts_chat("Open the menu on me.");
        }
        if(phase > 16)
        {
            W3T_FilmNext(bot, "");
            mpghosts_chat("Good hunting!");
            W3T_Log("FILM done");
        }
        return false;
    }
    W3T_FilmCamera(ghostPos);
    return phase > 4;
}

// film, member: joins the party, comes to the leader and then plays along by what it sees - climbs onto the horse the
// leader sits on, fights the copies near it, takes what a shared kill leaves, opens the player menu when asked, and
// otherwise runs after the leader. It is done when the leader says so.
function W3T_FilmMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var pos, ghostPos, spot : Vector;
    var label : string;
    var puppet : CNewNPC;
    var took : int;

    thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
    if(!leader.ghost)
    {
        return false;
    }
    ghostPos = leader.ghost.GetWorldPosition();
    pos = thePlayer.GetWorldPosition();

    if(!client.getInParty())
    {
        W3T_FilmCamera(ghostPos);
        if(bot.scenarioTime == 0)
        {
            bot.scenarioTime = bot.ElapsedS();
        }
        if(!bot.scenarioFlag && bot.ElapsedS() - bot.scenarioTime > 3)
        {
            bot.scenarioFlag = true;
            W3T_Log("PARTY join " + leader.username);
            client.joinParty(leader.username);
        }
        return false;
    }
    // 0: both start from the same save, so they are already standing together: the recording begins here
    if(bot.scenarioCount == 0)
    {
        W3T_FilmCamera(ghostPos);
        if(VecDistance(pos, ghostPos) > 6.0 && bot.ElapsedS() - bot.scenarioActAt > 1.0)
        {
            bot.scenarioActAt = bot.ElapsedS();
            thePlayer.ActionMoveToAsync(ghostPos, MT_Run);
        }
        if(VecDistance(pos, ghostPos) < 25)
        {
            W3T_Log("FILM ready");
            bot.scenarioCount = 3;
            bot.scenarioVec = pos;
        }
        return false;
    }
    // the leader's word that the fighting is elsewhere: the same teleport it makes, and a moment for the ground
    if(!bot.filmTravelled && StrFindFirst(leader.lastChat, "To the nest") >= 0)
    {
        bot.filmTravelled = true;
        bot.scenarioVec = W3T_NearestNest(label);
        if(bot.scenarioVec.W != 0)
        {
            thePlayer.Teleport(bot.scenarioVec + Vector(6, 3, 2));
            bot.filmTravelFrom = bot.ElapsedS();
            W3T_Log("FILM member travels to the nest " + label);
        }
        return false;
    }
    if(bot.filmTravelled && bot.ElapsedS() - bot.filmTravelFrom < 8)
    {
        return false;       // the navigation mesh is not there yet; nothing it does now would work
    }

    W3T_HoldAt(bot.scenarioVec);
    // the leader's word: a wave back, and the player menu when it asks for it
    if(!bot.scenarioFlag2 && StrFindFirst(leader.lastChat, "Well met") >= 0)
    {
        bot.scenarioFlag2 = true;
        mpghosts_emote(0);
        mpghosts_chat("Right behind you.");
    }
    if(!bot.filmMenu && StrFindFirst(leader.lastChat, "Open the menu") >= 0)
    {
        bot.filmMenu = true;
        bot.scenarioValue = bot.ElapsedS();
        W3T_FilmCamera(ghostPos);
        client.createMenu(leader.ghost);
        W3T_Log("FILM member opens the player menu on " + leader.username + ", entries " + coop.menuEntries);
        return false;
    }
    // left open it would cover this window for the rest of the film
    if(bot.filmMenu && bot.scenarioValue > 0 && bot.ElapsedS() - bot.scenarioValue > 7)
    {
        bot.scenarioValue = 0;
        theGame.ClosePopup('ItemSelectionPopup');
        W3T_Log("FILM member closes the player menu");
        return false;
    }
    if(StrFindFirst(leader.lastChat, "Good hunting") >= 0)
    {
        W3T_Log("FILM member is done");
        return true;
    }

    if(!bot.filmCalled && StrFindFirst(leader.lastChat, "Climb on") >= 0)
    {
        bot.filmCalled = true;      // the leader is waiting on its horse: the run to it starts now
        bot.filmBoardFrom = bot.ElapsedS();
    }
    if(!leader.isMounted)
    {
        bot.filmBoardFrom = 0;
    }
    // on the horse the leader rides: run to it, climb on from beside it (once - after the ride there is work)
    if(leader.isMounted && !client.isRiding() && !bot.filmRode)
    {
        W3T_FilmCamera(ghostPos);
        if(bot.filmBoardFrom == 0)
        {
            bot.filmBoardFrom = bot.ElapsedS();
        }
        if(!bot.filmCalled)
        {
            return false;           // not called over yet: the horse is still being got onto
        }
        if(VecDistance(pos, ghostPos) > 3.5 && bot.ElapsedS() - bot.filmBoardFrom < 15)
        {
            if(bot.ElapsedS() - bot.scenarioActAt > 1.0)
            {
                bot.scenarioActAt = bot.ElapsedS();
                thePlayer.ActionMoveToAsync(ghostPos, MT_Run);
            }
            W3T_ShowcaseUnstick(bot, ghostPos);
            return false;
        }
        if(bot.ElapsedS() - bot.scenarioActAt >= 2.5)
        {
            bot.scenarioActAt = bot.ElapsedS();
            if(VecDistance(pos, ghostPos) > 3.5 && bot.ElapsedS() - bot.filmBoardFrom >= 15)
            {
                // fifteen seconds of running and still not there: the rest is closed outright, and said so
                thePlayer.Teleport(ghostPos);
                W3T_Log("FILM member steps to the horse (a hop of "
                    + FloatToStringPrec(VecDistance(pos, ghostPos), 1) + " m)");
            }
            client.ridePlayer(leader.ghost);
            W3T_Log("FILM member climbs onto " + leader.username + " from "
                + FloatToStringPrec(VecDistance(pos, ghostPos), 1) + " m");
        }
        return false;
    }
    if(client.isRiding())
    {
        // off when the leader is off, or after half a minute: otherwise it would sit where the horse was while
        // the rest of the session happens without it
        if(bot.filmRideFrom == 0)
        {
            bot.filmRideFrom = bot.ElapsedS();
            bot.filmSawMounted = bot.ElapsedS();
        }
        // a member being carried stops seeing its leader as mounted at all, so the ride is counted in
        // seconds aboard: twelve, which is what the leader's own ride chapter waits for
        if(bot.ElapsedS() - bot.filmRideFrom > 12.0)
        {
            client.stopRiding();
            bot.filmRode = true;
            W3T_Log("FILM member gets off after " + FloatToStringPrec(bot.ElapsedS() - bot.filmRideFrom, 1) + " s");
            bot.filmRideFrom = 0;
            bot.filmBoardFrom = 0;
            return false;
        }
        W3T_FilmCamera(ghostPos + VecFromHeading(leader.ghost.GetHeading()) * 12.0);
        return false;
    }

    // what the leader's kill left, before looking for the next fight: at a nest there is always another copy
    if(bot.filmSpot.W != 0 && coop.dropItemsGiven > bot.filmLooted)
    {
        if(bot.filmLootFrom == 0)
        {
            bot.filmLootFrom = bot.ElapsedS();
        }
        if(bot.ElapsedS() - bot.scenarioUntil >= 4.0)
        {
            bot.scenarioUntil = bot.ElapsedS();
            W3T_Log("FILM member goes for what fell at " + W3T_VecStr(bot.filmSpot) + ", "
                + FloatToStringPrec(VecDistance2D(pos, bot.filmSpot), 1) + " m off; given " + coop.dropItemsGiven
                + ", taken " + bot.filmLooted);
        }
        if(bot.ElapsedS() - bot.filmLootFrom > 20)
        {
            W3T_Log("FILM member cannot get to what fell at " + W3T_VecStr(bot.filmSpot) + "; it leaves it");
            bot.filmLooted = coop.dropItemsGiven;
            bot.filmLootFrom = 0;
            return false;
        }
        if(VecDistance2D(pos, bot.filmSpot) > 5.0)
        {
            W3T_FilmCamera(bot.filmSpot);
            if(bot.ElapsedS() - bot.scenarioActAt > 1.0)
            {
                bot.scenarioActAt = bot.ElapsedS();
                thePlayer.ActionMoveToAsync(bot.filmSpot, MT_Run);
            }
            W3T_ShowcaseUnstick(bot, bot.filmSpot);
            return false;
        }
        took = W3T_TakeRemains(bot.filmSpot);
        if(took == 0)
        {
            took = W3T_TakeRemains(ghostPos);
        }
        bot.filmLooted = coop.dropItemsGiven;
        bot.filmLootFrom = 0;
        W3T_Log("FILM member took " + took + " container(s) at " + W3T_VecStr(bot.filmSpot) + "; it now carries "
            + W3T_MyItemCount() + ", drops given " + coop.dropItemsGiven);
        return false;
    }

    // the copies of the leader's monsters
    puppet = (CNewNPC)W3T_ShowcasePuppet(coop, ghostPos);
    if(puppet)
    {
        bot.filmSpot = puppet.GetWorldPosition();
        bot.filmSpot.W = 1;
        if(bot.ElapsedS() - bot.scenarioUntil >= 4.0)
        {
            bot.scenarioUntil = bot.ElapsedS();
            W3T_Log("FILM member fights a copy at " + W3T_VecStr(bot.filmSpot) + " drops heard=" + coop.dropsHeard
                + " filled=" + coop.dropsGiven + " items=" + coop.dropItemsGiven + " taken=" + bot.filmLooted);
        }
        W3T_ShowcaseFight(bot, puppet);
        W3T_ShowcaseUnstick(bot, puppet.GetWorldPosition());
        return false;
    }
    // otherwise: at the leader's side
    W3T_FilmCamera(ghostPos);
    // beside the leader, not inside it: two Geralts standing in one spot read as one
    if((VecDistance(pos, ghostPos) > 4.5 || VecDistance(pos, ghostPos) < 2.0)
        && bot.ElapsedS() - bot.scenarioActAt > 1.5)
    {
        bot.scenarioActAt = bot.ElapsedS();
        thePlayer.ActionMoveToAsync(ghostPos + VecFromHeading(leader.ghost.GetHeading() + 90) * 3.5, MT_Run);
    }
    W3T_ShowcaseUnstick(bot, ghostPos);
    return false;
}
