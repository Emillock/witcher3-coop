// Witcher Online state for the test bot's per-second report, and the scenario pass conditions.


// a session's scenario is over. Each scenario then starts as in fresh games: what it spawned dies and goes, the member
// leaves the party (it joins again as the next scenario has it), mortal with full health and no buffs, diagnostics
// from zero, back at the start.
function W3T_EndScenario(bot : W3T_Bot)
{
    var i : int;
    var client : r_MultiplayerClient;
    var coop : r_CoopEnemies;

    W3T_EndEntity(bot.scenarioEntity);
    for(i = 0; i < bot.scenarioEntities.Size(); i += 1)
    {
        W3T_EndEntity(bot.scenarioEntities[i]);
    }
    client = theGame.r_getMultiplayerClient();
    if(client.getInParty())
    {
        client.leaveParty();
    }
    // a horse called up goes too: later scenarios' monsters went for it instead of the member
    if(thePlayer.IsUsingHorse())
    {
        thePlayer.DismountVehicle(thePlayer.GetHorseCurrentlyMounted(), DT_instant);
    }
    W3T_EndEntity(thePlayer.GetHorseWithInventory());
    thePlayer.SetImmortalityMode(AIM_None, AIC_Cheat, true);
    thePlayer.RemoveAllNonAutoBuffs();
    thePlayer.ForceSetStat(BCS_Vitality, thePlayer.GetStatMax(BCS_Vitality));
    coop = client.getCoopEnemies();
    coop.ResetDiagnostics();
    // facing as at the start too: scenarios spawn monsters ahead of the player (after a ride a drowner landed on a ledge)
    if(bot.homeSet)
    {
        thePlayer.TeleportWithRotation(bot.home, bot.homeRot);
    }
    W3T_Log("SCENARIO " + bot.scenario + " cleaned up");
}

// gone at once: killed, its death animation would still reach the next scenario (as a monster's move)
function W3T_EndEntity(entity : CEntity)
{
    if(entity)
    {
        entity.Destroy();
    }
}

// a session's scenario starts once the last one's leftovers had time to go: counting starts from here
function W3T_BeginScenario(bot : W3T_Bot)
{
    theGame.r_getMultiplayerClient().getCoopEnemies().ResetDiagnostics();
}

// the mod's attack-sync events, each with its time on the PC's performance counter (WO_ClockMs, shared by both games;
// attack_sync.py pairs the leader's and the member's)
function W3T_DrainSyncLog(coop : r_CoopEnemies)
{
    var i : int;

    for(i = 0; i < coop.syncLog.Size(); i += 1)
    {
        W3T_Log("SYNC " + coop.syncLog[i]);
    }
    coop.syncLog.Clear();
}

function W3T_ScenarioCheck(bot : W3T_Bot) : bool
{
    var scenario : string = bot.scenario;
    var client : r_MultiplayerClient = theGame.r_getMultiplayerClient();
    var coop : r_CoopEnemies;
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
    W3T_DrainSyncLog(client.getCoopEnemies());

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

    if(scenario == "showcase")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_ShowcaseLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_ShowcaseMember(bot, client, client.getCoopEnemies(), players[0]);
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

    if(scenario == "social")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_SocialSender(bot);
        }
        return W3T_SocialWatcher(bot, players[0]);
    }

    if(scenario == "horse_ride")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_HorseRider(bot);
        }
        // W3T_HORSE_PARTY=1: in the rider's party, as co-op players are
        if(W3T_GetEnv("W3T_HORSE_PARTY") == "1" && !client.getInParty())
        {
            W3T_Log("PARTY join " + players[0].username);
            client.joinParty(players[0].username);
            return false;
        }
        return W3T_HorseWatcher(bot, players[0]);
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

    if(scenario == "attack_view")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_AttackViewLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_AttackViewMember(bot, client, client.getCoopEnemies(), players[0]);
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
        coop = client.getCoopEnemies();
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_SignVisualsLeader(bot, coop, players[0]);
        }
        return W3T_SignVisualsMember(bot, client, coop, players[0]);
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

    if(scenario == "trade")
    {
        if(players.Size() < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_TradeSeller(bot, client, players[0]);
        }
        return W3T_TradeBuyer(bot, client, players[0]);
    }

    if(scenario == "enemy_crowd")
    {
        if(players.Size() < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_CrowdLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_CrowdMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "player_effects")
    {
        if(players.Size() < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_PlayerEffectsWatcher(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_PlayerEffectsTaker(bot, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "leader_death")
    {
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_LeaderDeathLeader(bot, client.getCoopEnemies(), players);
        }
        return W3T_LeaderDeathMember(bot, client, client.getCoopEnemies(), players);
    }

    if(scenario == "member_death")
    {
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_DeathLeader(bot, client.getCoopEnemies(), players);
        }
        return W3T_DeathMember(bot, client, client.getCoopEnemies(), players);
    }

    if(scenario == "enemy_effects")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_EffectsLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_EffectsMember(bot, client, client.getCoopEnemies(), players[0]);
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

    if(scenario == "enemy_spells")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_EnemySpellsLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_EnemySpellsMember(bot, client, client.getCoopEnemies(), players[0]);
    }

    if(scenario == "enemy_summons")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_EnemySummonsLeader(bot, client.getCoopEnemies(), players[0]);
        }
        return W3T_EnemySummonsMember(bot, client, client.getCoopEnemies(), players[0]);
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

    if(scenario == "encounter_mismatch")
    {
        if(ghosts < 1)
        {
            return false;
        }
        if(W3T_GetEnv("W3T_ROLE") == "mover")
        {
            return W3T_TwinLeader(bot, client.getCoopEnemies());
        }
        return W3T_MismatchMember(bot, client, client.getCoopEnemies(), players[0]);
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

// social, sender: every 15 s a chat line, then a wave and a bow (Witcher Online's chat and emote commands), so a
// watcher that arrives late still sees a round. Passes after one round.
function W3T_SocialSender(bot : W3T_Bot) : bool
{
    var t : float;

    if(!bot.scenarioFlag)
    {
        bot.scenarioFlag = true;
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    t = bot.ElapsedS() - bot.scenarioTime;
    if(bot.scenarioStep == 0 && t >= 2)
    {
        mpghosts_chat("w3test hello " + bot.scenarioCount);
        W3T_Log("SOCIAL chat w3test hello " + bot.scenarioCount);
        bot.scenarioStep = 1;
    }
    else if(bot.scenarioStep == 1 && t >= 5)
    {
        mpghosts_emote(0);
        W3T_Log("SOCIAL emote 0 (wave)");
        bot.scenarioStep = 2;
    }
    else if(bot.scenarioStep == 2 && t >= 10)
    {
        mpghosts_emote(1);
        W3T_Log("SOCIAL emote 1 (bow)");
        bot.scenarioStep = 3;
    }
    else if(bot.scenarioStep == 3 && t >= 15)
    {
        theGame.r_getMultiplayerClient().clearLocalEmoteState();
        bot.scenarioCount += 1;
        bot.scenarioStep = 0;
        bot.scenarioTime = bot.ElapsedS();
    }
    return bot.scenarioCount >= 1;
}

// social, watcher: the sender's chat line shows over its character here, and each emote it makes plays on it (two
// different ones).
function W3T_SocialWatcher(bot : W3T_Bot, peer : r_RemotePlayer) : bool
{
    var now : float;
    var emote : int;

    if(!peer.ghost)
    {
        return false;
    }
    now = theGame.GetEngineTimeAsSeconds();
    if(!bot.scenarioFlag && StrFindFirst(peer.lastChat, "w3test hello") == 0 && peer.chatShownAt > 0)
    {
        bot.scenarioFlag = true;
        W3T_Log("SOCIAL watcher chat shown: " + peer.lastChat);
    }
    // a new emote (its time changed) that plays on the character: its animation runs until a later time (its number:
    // as the sender sends it, or -1 right after it played, kept as prevEmote)
    if(peer.lastEmoteTime != bot.scenarioValue && peer.currentAnimEndTime > now)
    {
        bot.scenarioValue = peer.lastEmoteTime;
        emote = peer.lastEmote;
        if(emote < 0)
        {
            emote = peer.prevEmote;
        }
        if(StrFindFirst(bot.scenarioText, " " + emote + " ") < 0)
        {
            bot.scenarioText += " " + emote + " ";
            bot.scenarioCount += 1;
        }
        W3T_Log("SOCIAL watcher emote " + emote + " plays for " + FloatToStringPrec(peer.currentAnimEndTime - now, 2)
            + " s; emotes seen:" + bot.scenarioText);
    }
    return bot.scenarioFlag && bot.scenarioCount >= 2;
}

// horse_ride, rider: calls its horse and mounts it (as quests do), rides it 8 m back and forth every 4 s (four times),
// then gets off and, 2 s later, walks 6 m away, leaving the horse there. Passes once away.
function W3T_HorseRider(bot : W3T_Bot) : bool
{
    var coop : r_CoopEnemies;
    var horse : CNewNPC;
    var target : Vector;
    var rot : EulerAngles;

    if(bot.scenarioCount >= 5)
    {
        horse = thePlayer.GetHorseWithInventory();
        if(bot.scenarioCount == 5 && horse && bot.ElapsedS() - bot.scenarioTime >= 2.0)
        {
            rot = horse.GetWorldRotation();
            thePlayer.TeleportWithRotation(horse.GetWorldPosition() + VecFromHeading(rot.Yaw + 90) * 6.0, rot);
            bot.scenarioCount = 6;
            W3T_Log("HORSE rider walked off from its horse at " + W3T_VecStr(horse.GetWorldPosition()));
        }
        coop = theGame.r_getMultiplayerClient().getCoopEnemies();
        W3T_Log("HORSE rider off: sends " + coop.parkedText + " (" + coop.parkedSent + " sent)");
        return bot.scenarioCount >= 6;
    }
    if(!thePlayer.IsUsingHorse())
    {
        // (again every 5 s: a horse called from far away takes a while)
        if(bot.ElapsedS() - bot.scenarioTime >= 5.0)
        {
            bot.scenarioTime = bot.ElapsedS();
            InstantMountPlayer('None', EVT_Horse, false, false);
            W3T_Log("HORSE mount");
        }
        return bot.scenarioCount >= 2;
    }
    horse = thePlayer.GetHorseCurrentlyMounted();
    if(!bot.scenarioFlag)
    {
        bot.scenarioFlag = true;
        bot.scenarioVec = horse.GetWorldPosition();
        bot.scenarioTime = bot.ElapsedS();
        W3T_Log("HORSE mounted at " + W3T_VecStr(bot.scenarioVec));
        return false;
    }
    if(bot.scenarioCount == 4 && bot.ElapsedS() - bot.scenarioTime >= 4.0)
    {
        thePlayer.DismountVehicle(horse, DT_instant);
        bot.scenarioCount = 5;
        bot.scenarioTime = bot.ElapsedS();
        W3T_Log("HORSE off at " + W3T_VecStr(horse.GetWorldPosition()));
        return false;
    }
    if(bot.ElapsedS() - bot.scenarioTime >= 4.0)
    {
        target = bot.scenarioVec;
        rot = horse.GetWorldRotation();
        if(bot.scenarioCount % 2 == 0)
        {
            target += VecFromHeading(rot.Yaw) * 8.0;
        }
        horse.TeleportWithRotation(target, rot);
        bot.scenarioCount += 1;
        bot.scenarioTime = bot.ElapsedS();
        W3T_Log("HORSE ride " + bot.scenarioCount + " to " + W3T_VecStr(target) + " mounted=" + thePlayer.IsUsingHorse());
    }
    return false;
}

// horse_ride, watcher: the rider's character sits on a horse here too (Witcher Online's horse for remote riders), and
// that horse follows the rider: two rides seen (more than 4 m from where it last settled, within 2.5 m of the position
// the rider reports). Then, the rider off, its horse stays in sight where it was left for 3 s (scenarioStep: seconds
// seen so).
function W3T_HorseWatcher(bot : W3T_Bot, peer : r_RemotePlayer) : bool
{
    var horsePos, spot, aim : Vector;
    var rot : EulerAngles;
    var onHorse, hasHorse : bool;

    if(!peer.ghost)
    {
        return bot.scenarioCount >= 2 && bot.scenarioStep >= 3;
    }
    onHorse = peer.ghost.IsUsingHorse(true);
    aim = peer.ghost.GetWorldPosition();
    if(peer.horse)
    {
        hasHorse = true;
        horsePos = peer.horse.GetWorldPosition();
        if(!peer.isMounted)
        {
            aim = horsePos;
        }
    }
    // in view: 7 m behind the rider (or the horse it left) as the camera looks (screenshots)
    if(VecDistance2D(thePlayer.GetWorldPosition() + theCamera.GetCameraForwardOnHorizontalPlane() * 7.0, aim) > 2.0
        && theGame.GetWorld().NavigationFindSafeSpot(aim - theCamera.GetCameraForwardOnHorizontalPlane() * 7.0, 0.5, 3.0, spot))
    {
        rot.Yaw = theCamera.GetCameraHeading();
        thePlayer.TeleportWithRotation(spot, rot);
    }
    W3T_Log("HORSE watcher mounted=" + peer.isMounted + " horse=" + hasHorse + " onHorse=" + onHorse
        + " horseVisible=" + (hasHorse && peer.horse.GetVisibility()) + " ghostVisible=" + peer.ghost.GetVisibility()
        + " horseToRider=" + FloatToStringPrec(VecDistance2D(horsePos, peer.pos), 2) + " rides=" + bot.scenarioCount
        + " parked=" + peer.parkedHorse + "/" + FloatToStringPrec(theGame.GetEngineTimeAsSeconds() - peer.parkedAt, 1)
        + " heard=" + theGame.r_getMultiplayerClient().getCoopEnemies().parkedHeard);
    if(bot.scenarioCount >= 2 && !peer.isMounted && hasHorse && peer.horse.GetVisibility() && peer.parkedHorse
        && VecDistance2D(horsePos, peer.parkedPos) < 1.5 && VecDistance2D(horsePos, peer.pos) > 3.0)
    {
        bot.scenarioStep += 1;
        W3T_Log("HORSE watcher sees the horse left at " + W3T_VecStr(horsePos) + " (its owner's game: "
            + W3T_VecStr(peer.parkedPos) + "), its rider " + FloatToStringPrec(VecDistance2D(horsePos, peer.pos), 1) + " m away");
    }
    if(!peer.isMounted || !peer.horse || !onHorse)
    {
        return bot.scenarioCount >= 2 && bot.scenarioStep >= 3;
    }
    if(!bot.scenarioFlag)
    {
        bot.scenarioFlag = true;
        bot.scenarioVec = horsePos;
        W3T_Log("HORSE watcher sees the rider mounted at " + W3T_VecStr(horsePos));
    }
    else if(VecDistance2D(horsePos, bot.scenarioVec) > 4.0 && VecDistance2D(horsePos, peer.pos) < 2.5)
    {
        bot.scenarioCount += 1;
        bot.scenarioVec = horsePos;
        W3T_Log("HORSE watcher ride " + bot.scenarioCount + ": horse at " + W3T_VecStr(horsePos) + " network " + W3T_VecStr(peer.pos));
    }
    return bot.scenarioCount >= 2 && bot.scenarioStep >= 3;
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
        + " pos=" + W3T_VecStr(puppet.GetWorldPosition()) + " xp=" + GetWitcherPlayer().levelManager.GetPointsTotal(EExperiencePoint)
        + " dist=" + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(), puppet.GetWorldPosition()), 1));

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
        // (with the kill's experience: this player hit it, so it is this player's kill too)
        W3T_Log("ENEMY member saw the drowner die; no duplicate; xp=" + GetWitcherPlayer().levelManager.GetPointsTotal(EExperiencePoint)
            + " credited=" + coop.killsCredited);
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
    var spot, safe, best, reachable : Vector;
    var x, y, bestX : float;
    var i, r : int;

    bestX = 2;
    for(r = 12; r <= 14; r += 2)
    {
        for(i = 0; i < 32; i += 1)
        {
            spot = from + VecFromHeading(i * 11.25) * r;
            if(theGame.GetWorld().NavigationFindSafeSpot(spot, 0.5, 2.0, safe) && theGame.GetWorld().NavigationLineTest(from, safe, 0.5))
            {
                if(reachable.W == 0)
                {
                    reachable = safe;
                    reachable.W = 1;
                }
                if(theCamera.WorldVectorToViewRatio(safe, x, y) && AbsF(x) < bestX && AbsF(y) < 0.9)
                {
                    bestX = AbsF(x);
                    best = safe;
                    best.W = 1;
                }
            }
        }
    }
    // none in view: any reachable one
    if(best.W == 0)
    {
        return reachable;
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

// W3T_COUNTER=N: every N s in combat the monster is told to counter-attack, as after a few hits (a fugas' vomit, a
// werewolf's or katakan's charge come only so)
function W3T_Counter(bot : W3T_Bot, npc : CNewNPC)
{
    var every : float;

    every = StringToFloat(W3T_GetEnv("W3T_COUNTER"), 0);
    if(every > 0 && W3T_Fighting(npc) && bot.ElapsedS() - bot.scenarioActAt >= every)
    {
        bot.scenarioActAt = bot.ElapsedS();
        npc.SignalGameplayEvent('LaunchCounterAttack');
    }
}

// in a fight: its combat graph, or in combat by its AI (a werewolf fights in its exploration graph)
function W3T_Fighting(npc : CNewNPC) : bool
{
    return npc.GetBehaviorGraphInstanceName() == 'Combat' || npc.IsInCombat();
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
        if(W3T_GetEnv("W3T_MONSTER_HP") != "")
        {
            drowner.SetHealthPerc(StringToFloat(W3T_GetEnv("W3T_MONSTER_HP"), 1.0));
        }
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
    W3T_Counter(bot, drowner);
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
        + " ghostDist=" + FloatToStringPrec(VecDistance(drowner.GetWorldPosition(), member.ghost.GetWorldPosition()), 2)
        + " directEffects=" + coop.directEffectsSent + " victimFx=" + coop.victimFxSent + " fx=" + coop.fxChanges + "/" + coop.lastFx
        + " graphAttacks=" + coop.graphAttacksSeen);

    // W3T_DIRECT_EFFECTS=N: also N effects its tasks put straight on the ghost (a fugas' vomit)
    if(bot.scenarioCount == 1 && coop.hurtsCaptured >= 2 && coop.PendingHurtCount() == 0
        && coop.directEffectsSent >= StringToInt(W3T_GetEnv("W3T_DIRECT_EFFECTS"), 0))
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
        // waiting for effects that come rarely: hit, never killed
        if(W3T_GetEnv("W3T_DIRECT_EFFECTS") != "")
        {
            thePlayer.SetImmortalityMode(AIM_Immortal, AIC_Cheat, true);
        }
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
        + " lastHurtDelay=" + FloatToStringPrec(coop.lastHurtDelay, 2) + " directEffects=" + coop.directEffectsApplied + "/"
        + coop.directEffectsHeld + " victimFx=" + coop.victimFxPlayed + " fx=" + coop.fxMirrored + " puppetEffectsDropped="
        + coop.puppetEffectsDropped + " graphAttacks=" + coop.graphAttacksPlayed + "/" + coop.graphAttacksRefused + "/" + coop.graphEndsPlayed
        + " lastError=" + coop.lastError);

    if(coop.attackPlayFailures > 0 || coop.movePlayFailures > 0)
    {
        W3T_Log("FAIL the puppet could not play the leader's attack or move: " + coop.lastError);
        W3T_Quit(1);
        return false;
    }

    // the monster's swings show on its puppet, and its hits land (and W3T_DIRECT_EFFECTS of its effects that come
    // without a hit)
    if(bot.scenarioCount == 0 && coop.hurtsApplied >= 2 && coop.hurtDamageTaken > 0 && coop.attacksPlayed >= 1
        && coop.directEffectsApplied >= StringToInt(W3T_GetEnv("W3T_DIRECT_EFFECTS"), 0))
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

// attack_view, leader: a drowner (or W3T_MONSTER) spawns 3 m from this Geralt and attacks only it, not the member's
// copy. Passes once it attacked 4 times (W3T_VIEW_ATTACKS).
function W3T_AttackViewLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var template : CEntityTemplate;
    var npc : CNewNPC;
    var rot : EulerAngles;
    var action : W3DamageAction;
    var keep, hide : float;
    var spot, away : Vector;

    if(bot.scenarioCount == 0)
    {
        if(coop.GetRole() != 1)
        {
            return false;
        }
        template = (CEntityTemplate)LoadResource(W3T_MonsterPath(), true);
        // W3T_VIEW_MORTAL=1: hit but never killed (some animals may not go for an invulnerable target)
        if(W3T_GetEnv("W3T_VIEW_MORTAL") == "1")
        {
            thePlayer.SetImmortalityMode(AIM_Immortal, AIC_Cheat, true);
        }
        else
        {
            thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        }
        rot.Yaw = thePlayer.GetHeading() + 180;
        bot.scenarioEntity = theGame.CreateEntity(template, thePlayer.GetWorldPosition() + VecFromHeading(thePlayer.GetHeading()) * 3.0,
            rot, true, false, false, PM_DontPersist);
        npc = (CNewNPC)bot.scenarioEntity;
        npc.SetAttitude(thePlayer, AIA_Hostile);
        npc.SetAttitude(member.ghost, AIA_Neutral);
        // W3T_MONSTER_HP: its health first (some attacks come below a threshold: Shaelmaar's rocks at half)
        if(W3T_GetEnv("W3T_MONSTER_HP") != "")
        {
            npc.SetHealthPerc(StringToFloat(W3T_GetEnv("W3T_MONSTER_HP"), 1.0));
        }
        bot.scenarioCount = 1;
        return false;
    }
    npc = (CNewNPC)bot.scenarioEntity;
    W3T_LookAt(npc.GetWorldPosition());
    W3T_Counter(bot, npc);
    // W3T_VIEW_HIDE=N: every N s in a fight its monster vanishes for 1.5 s and reappears 4 m aside, as a teleport with
    // forceInvisible does (no tested monster vanished by itself): its copy must hide and follow
    hide = StringToFloat(W3T_GetEnv("W3T_VIEW_HIDE"), 0);
    if(hide > 0 && !npc.GetVisibility() && bot.ElapsedS() - bot.scenarioFarSince >= 1.5)
    {
        npc.SetVisibility(true);
        W3T_Log("VIEW shown");
    }
    else if(hide > 0 && W3T_Fighting(npc) && npc.GetVisibility() && bot.ElapsedS() - bot.scenarioFarSince >= hide)
    {
        bot.scenarioFarSince = bot.ElapsedS();
        npc.SetVisibility(false);
        npc.Teleport(npc.GetWorldPosition() + VecFromHeading(npc.GetHeading() + 90) * 4.0);
        W3T_Log("VIEW hidden");
    }
    // it stays on the leader (stood off, the member's character can come nearer, and it switched to that one)
    if(W3T_Fighting(npc) && npc.GetTarget() != thePlayer && bot.ElapsedS() - bot.scenarioSeenAt >= 2)
    {
        bot.scenarioSeenAt = bot.ElapsedS();
        npc.SetAttitude(member.ghost, AIA_Neutral);
        npc.SignalGameplayEventParamObject('ForceTarget', thePlayer);
    }
    // W3T_VIEW_KEEP=N: once it fights, the leader steps back to N m when the monster comes closer, at most every 4 s
    // (ranged attacks: a troll throws at 5-16 m, a giant or werewolf charges from 5 m). Away from the monster, or toward
    // the member once that would be over 30 m from them, so the fight doesn't drift off past the 60 m hand-off.
    keep = StringToFloat(W3T_GetEnv("W3T_VIEW_KEEP"), 0);
    away = thePlayer.GetWorldPosition() - npc.GetWorldPosition();
    if(VecDistance2D(npc.GetWorldPosition() + VecNormalize2D(away) * keep, member.ghost.GetWorldPosition()) > 30)
    {
        away = member.ghost.GetWorldPosition() - npc.GetWorldPosition();
    }
    if(keep > 0 && W3T_Fighting(npc) && bot.ElapsedS() - bot.scenarioTime >= 4
        && VecDistance2D(npc.GetWorldPosition(), thePlayer.GetWorldPosition()) < keep - 3
        && theGame.GetWorld().NavigationFindSafeSpot(npc.GetWorldPosition() + VecNormalize2D(away) * keep, 0.5, 3.0, spot))
    {
        rot.Yaw = VecHeading(npc.GetWorldPosition() - spot);
        thePlayer.TeleportWithRotation(spot, rot);
        bot.scenarioTime = bot.ElapsedS();
    }
    // W3T_VIEW_PROVOKE=1: still out of combat, it takes a light hit every 3 s (some casters never start a fight)
    if(W3T_GetEnv("W3T_VIEW_PROVOKE") == "1" && npc.GetBehaviorGraphInstanceName() != 'Combat' && bot.ElapsedS() - bot.scenarioTime >= 3)
    {
        bot.scenarioTime = bot.ElapsedS();
        action = new W3DamageAction in theGame.damageMgr;
        action.Initialize(thePlayer, npc, thePlayer, "W3T", EHRT_Light, CPS_Undefined, true, false, false, false);
        action.AddDamage(theGame.params.DAMAGE_NAME_DIRECT, 0.01 * npc.GetMaxHealth());
        theGame.damageMgr.ProcessAction(action);
        delete action;
    }
    if(W3T_GetEnv("W3T_POSE") != "")
    {
        coop.poseNaming = W3T_GetEnv("W3T_POSE") == "1";
    }
    // experiment (W3T_VIEW_HIT=1, best with W3T_TICK=0.1): a hit as each attack starts, which cuts its swing short
    if(W3T_GetEnv("W3T_VIEW_HIT") == "1" && coop.attacksSeen > bot.scenarioStep)
    {
        bot.scenarioStep = coop.attacksSeen;
        action = new W3DamageAction in theGame.damageMgr;
        action.Initialize(thePlayer, npc, thePlayer, "W3T", EHRT_Heavy, CPS_Undefined, true, false, false, false);
        action.AddDamage(theGame.params.DAMAGE_NAME_DIRECT, 0.02 * npc.GetMaxHealth());
        theGame.damageMgr.ProcessAction(action);
        delete action;
    }
    W3T_Log("VIEW leader attacks=" + coop.attacksSeen + " falseStarts=" + coop.attackFalseStarts + " poseNamed=" + coop.poseNamed
        + " projectiles=" + coop.projectilesSeen + " target=" + (npc.GetTarget() == thePlayer) + " hurtsCaptured=" + coop.hurtsCaptured
        + " graph=" + npc.GetBehaviorGraphInstanceName() + " fx=" + coop.fxChanges + "/" + coop.lastFx + " visible=" + npc.GetVisibility()
        + " graphAttacks=" + coop.graphAttacksSeen);
    return coop.attacksSeen >= StringToInt(W3T_GetEnv("W3T_VIEW_ATTACKS"), 4);
}

// attack_view, member: watches the copy of the drowner that attacks the leader. The leader's attacks must really play
// on the copy: its own attack events fire (an accepted AI action alone proved nothing: for a long time it never ran),
// only right after a mirrored attack, and at the leader's character (at most 1 in 10 at this player).
function W3T_AttackViewMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var puppet : CNewNPC;
    var spot : Vector;
    var rot : EulerAngles;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        // 4 m behind the leader, as players stand: the drowner (3 m in front of the leader) is nearer the leader, and
        // this camera sees the fight over the leader's shoulder
        if(theGame.GetWorld().NavigationFindSafeSpot(leader.ghost.GetWorldPosition() - VecFromHeading(leader.ghost.GetHeading()) * 4.0,
            0.5, 2.0, spot))
        {
            rot.Yaw = leader.ghost.GetHeading();
            thePlayer.TeleportWithRotation(spot, rot);
        }
        return false;
    }
    // experiments: the leader's swing animations on the copy's slot (W3T_SLOT_ATTACKS=0: its own AI's swings), which slot
    if(W3T_GetEnv("W3T_SLOT_ATTACKS") != "")
    {
        coop.slotAttacks = W3T_GetEnv("W3T_SLOT_ATTACKS") == "1";
    }
    if(W3T_GetEnv("W3T_ATTACK_SLOT") != "")
    {
        coop.attackSlot = WO_ToName(W3T_GetEnv("W3T_ATTACK_SLOT"));
    }
    if(coop.PuppetCount() > 0)
    {
        puppet = coop.PuppetAt(0);
        W3T_LookAt(puppet.GetWorldPosition());
        if(puppet.GetTarget() == leader.ghost)
        {
            bot.scenarioCount += 1;  // reports with the copy going for the leader's character
        }
        else if(puppet.GetTarget() == thePlayer)
        {
            bot.scenarioStep += 1;   // ...and for this player instead
        }
        W3T_Log("VIEW member attacksPlayed=" + coop.attacksPlayed + " failures=" + coop.attackPlayFailures + " attackEvents="
            + coop.puppetAttackEvents + " ownAttacks=" + coop.puppetOwnAttacks + " wrongTarget=" + coop.puppetWrongTargets
            + " targetLeader=" + bot.scenarioCount
            + " targetMe=" + bot.scenarioStep + " facingLeader=" + FloatToStringPrec(AngleDistance(puppet.GetHeading(),
            VecHeading(leader.ghost.GetWorldPosition() - puppet.GetWorldPosition())), 0) + " graph=" + puppet.GetBehaviorGraphInstanceName()
            + " sameTask=" + coop.puppetSameTasks + " otherTask=" + coop.puppetOtherTasks + " sameAnim=" + coop.puppetSameAnims + "/" + coop.attackAnimsCompared
            + " pair=" + coop.lastAnimPair + " slot=" + coop.slotAttacksPlayed + "/" + coop.slotAttacksRefused + "/" + coop.slotAttacksMissed + " catchUps=" + coop.slotCatchUps
            + " projectilesFired=" + coop.projectilesFired + " slotState=" + coop.lastSlotState + " fx=" + coop.fxMirrored
            + " visible=" + puppet.GetVisibility() + " puppetEffectsDropped=" + coop.puppetEffectsDropped
            + " graphAttacks=" + coop.graphAttacksPlayed + "/" + coop.graphAttacksRefused + "/" + coop.graphEndsPlayed
            + " lastError=" + coop.lastError);
    }
    // most of them really play (a few can fall into a hit reaction), not many more hit windows than the leader's (the
    // puppet picks its own attack: a two-hit one where the leader's monster swung once doubles them), hardly any at the
    // wrong player (the first one can start before the puppet switched to the leader), none on its own
    return coop.attacksPlayed >= 6 && coop.puppetAttackEvents * 2 >= coop.attacksPlayed
        && coop.puppetAttackEvents <= coop.attacksPlayed * 5 / 2 + 1 && coop.puppetWrongTargets <= Max(1, coop.puppetAttackEvents / 10)
        && coop.puppetOwnAttacks == 0;
}

// enemy_moves, leader: the monster of enemy_attacks (a sword bandit unless W3T_MONSTER), immortal, and this Geralt
// swings at it every 2 s: a real attack warns it as the game does, at the right moment (warnings sent by script alone
// came mid-attack). The bandit dodges every warning, also mid-attack (W3T_AlwaysDodge; humans dodge through
// CBTTaskDodge). A nekker dodges through its tree's own nodes, about once a minute or less. Taunts count too.
// Passes once a move was captured.
function W3T_EnemyMovesLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var monster : CNewNPC;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member, "gameplay\community\community_npcs\nml\regular\baron_bandit_strong_sword.w2ent");
        if(bot.scenarioCount == 1)
        {
            monster = (CNewNPC)bot.scenarioEntity;
            monster.SetImmortalityMode(AIM_Immortal, AIC_Default);
            monster.SetAttitude(thePlayer, AIA_Hostile);
            monster.NoticeActor(thePlayer);
            monster.AddTag('W3T_AlwaysDodge');
        }
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    monster = (CNewNPC)bot.scenarioEntity;
    W3T_SwingAt(bot, monster);
    W3T_Log("MOVES leader moves=" + coop.movesSeen + " last=" + coop.lastMoveKind + "/" + NameToString(coop.lastMoveAnim)
        + " task=" + coop.lastMoveTask + " attacks=" + coop.attacksSeen + " dodging=" + monster.IsCurrentlyDodging());
    return coop.movesSeen >= 1;
}

// the leader's light attack at `monster` every 2 s, from 1.8 m off its body (teleporting there if 0.7 m farther; a
// golem can't attack someone standing inside its body)
function W3T_SwingAt(bot : W3T_Bot, monster : CNewNPC)
{
    var spot : Vector;
    var rot : EulerAngles;
    var reach : float;

    W3T_LookAt(monster.GetWorldPosition());
    if(bot.ElapsedS() - bot.scenarioTime < 2)
    {
        return;
    }
    bot.scenarioTime = bot.ElapsedS();
    reach = 1.8 + MaxF(0, monster.GetRadius() - 0.5);
    if(VecDistance(thePlayer.GetWorldPosition(), monster.GetWorldPosition()) > reach + 0.7)
    {
        spot = monster.GetWorldPosition() + VecNormalize(thePlayer.GetWorldPosition() - monster.GetWorldPosition()) * reach;
        rot.Yaw = VecHeading(monster.GetWorldPosition() - spot);
        thePlayer.TeleportWithRotation(spot, rot);
    }
    thePlayer.GoToCombatIfNeeded(monster);
    thePlayer.SetupCombatAction(EBAT_LightAttack, BS_Pressed);
}

// enemy_spells, leader: a spell caster (a leshen unless W3T_MONSTER: its roots), immortal, next to the member's ghost
// and hostile to both players. This Geralt swings at it every 2 s for 6 s, then stands off for 6 s (W3T_KITE, 11 m;
// monsters cast at range, up close they only swing). W3T_MONSTER_HP sets its health first. Lists the attack tasks it starts (CoopAttackId, e.g.
// CBTTaskLeshyRootAttack:0); passes after 16 of them (W3T_SPELL_ATTACKS).
function W3T_EnemySpellsLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var monster : CNewNPC;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member, "characters\npc_entities\monsters\lessog_lvl1.w2ent");
        if(bot.scenarioCount == 1)
        {
            monster = (CNewNPC)bot.scenarioEntity;
            monster.SetImmortalityMode(AIM_Immortal, AIC_Default);
            monster.SetAttitude(thePlayer, AIA_Hostile);
            monster.NoticeActor(thePlayer);
            // W3T_MONSTER_HP: some spells come below a health threshold (a golem's pillar arena)
            if(W3T_GetEnv("W3T_MONSTER_HP") != "")
            {
                monster.SetHealthPerc(StringToFloat(W3T_GetEnv("W3T_MONSTER_HP"), 1.0));
            }
            // noon (members follow the leader's time), for recordings
            theGame.SetGameTime(GameTimeCreate(GameTimeDays(theGame.GetGameTime()) + 1, 12, 0, 0), true);
        }
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    monster = (CNewNPC)bot.scenarioEntity;
    W3T_SwingOrKite(bot, monster);
    if(coop.lastAttackTask != "" && StrFindFirst(bot.scenarioText, " " + coop.lastAttackTask + " ") < 0)
    {
        bot.scenarioText += " " + coop.lastAttackTask + " ";
    }
    W3T_Log("SPELLS leader attacks=" + coop.attacksSeen + " spawns=" + coop.spellSpawns + " fx=" + coop.lastFxSpawn
        + " task=" + coop.lastAttackTask
        + " seen:" + bot.scenarioText);
    return coop.attacksSeen >= StringToInt(W3T_GetEnv("W3T_SPELL_ATTACKS"), 16);
}

// whether `actor` has the component combat tickets come from (diagnostics)
function W3T_HasCombatData(actor : CActor) : bool
{
    var data : CCombatDataComponent;

    data = (CCombatDataComponent)actor.GetComponentByClassName('CCombatDataComponent');
    if(data)
    {
        return true;
    }
    return false;
}

// enemy_spells, enemy_summons: 6 s swinging at the monster, then 6 s standing off (W3T_KiteDistance), in turn (monsters
// cast and summon at range, up close they only swing)
function W3T_SwingOrKite(bot : W3T_Bot, monster : CNewNPC)
{
    var spot : Vector;
    var rot : EulerAngles;

    if(FloorF(bot.ElapsedS() / 6) % 2 == 0)
    {
        W3T_SwingAt(bot, monster);
        return;
    }
    W3T_LookAt(monster.GetWorldPosition());
    if(VecDistance(thePlayer.GetWorldPosition(), monster.GetWorldPosition()) < W3T_KiteDistance() - 3
        && theGame.GetWorld().NavigationFindSafeSpot(monster.GetWorldPosition()
        + VecNormalize2D(thePlayer.GetWorldPosition() - monster.GetWorldPosition()) * W3T_KiteDistance(), 0.5, 3.0, spot))
    {
        rot.Yaw = VecHeading(monster.GetWorldPosition() - spot);
        thePlayer.TeleportWithRotation(spot, rot);
    }
}

// enemy_spells: how far the leader stands off (W3T_KITE, 11 m by default)
function W3T_KiteDistance() : float
{
    if(W3T_GetEnv("W3T_KITE") != "")
    {
        return StringToFloat(W3T_GetEnv("W3T_KITE"), 11.0);
    }
    return 11.0;
}

// enemy_spells, member: the puppet makes the leader's monster's attack tasks (the same spell or swing), at least 8,
// two thirds of them the same task or another plain swing, and casts a spell (spawns its area entity) at the player the leader's monster
// attacks, never at another; its own projectiles don't fly (the leader's come as copies)
function W3T_EnemySpellsMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
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
    if(W3T_GetEnv("W3T_AI_FREE") != "")
    {
        coop.puppetAiFree = W3T_GetEnv("W3T_AI_FREE") == "1";
    }
    if(coop.PuppetCount() > 0)
    {
        W3T_Log("SPELLS copy graph=" + coop.PuppetAt(0).GetBehaviorGraphInstanceName() + " targetLeader="
            + (coop.PuppetAt(0).GetTarget() == leader.ghost) + " targetMe=" + (coop.PuppetAt(0).GetTarget() == thePlayer)
            + " dist=" + FloatToStringPrec(VecDistance(coop.PuppetAt(0).GetWorldPosition(), leader.ghost.GetWorldPosition()), 1)
            + " gate asked=" + coop.gateAsked + " heldByMove=" + coop.gateHeldByMove + " otherTask=" + coop.gateOtherTask + " denied=" + coop.lastGateDenied
            + " movesPlayed=" + coop.movesPlayed + " fxTasks=" + coop.puppetFxTasks + " fx=" + coop.lastFxSpawn + " ghostCombatData="
            + W3T_HasCombatData(leader.ghost));
    }
    W3T_Log("SPELLS member attacksPlayed=" + coop.attacksPlayed + " sameTask=" + coop.puppetSameTasks + " swingSwaps=" + coop.puppetSwingSwaps + " otherTask="
        + coop.puppetOtherTasks + " attackEvents=" + coop.puppetAttackEvents + " sameAnim=" + coop.puppetSameAnims + "/" + coop.attackAnimsCompared
        + " ownAttacks=" + coop.puppetOwnAttacks + " spawns=" + coop.spellSpawns + " wrongSpells=" + coop.spellWrongTargets + " quickEnds=" + coop.puppetAttackQuickEnds + " projectilesMuted=" + coop.projectilesMuted + " projectilesFired="
        + coop.projectilesFired + " lastTask=" + coop.lastPuppetTask + " lastError=" + coop.lastError);
    return coop.attacksPlayed >= 8
        && (coop.puppetSameTasks + coop.puppetSwingSwaps) * 3 >= (coop.puppetSameTasks + coop.puppetSwingSwaps + coop.puppetOtherTasks) * 2
        && coop.puppetSameTasks >= 4 && coop.spellSpawns >= 1 && coop.spellWrongTargets == 0;
}

// enemy_summons, leader: a summoner (a noonwraith unless W3T_MONSTER: it calls up doppelgangers), immortal, next to
// the member's ghost and hostile to both players; this Geralt swings at it and stands off in turn (W3T_SwingOrKite). Passes once another monster
// (a summoned one) is among its shared monsters.
function W3T_EnemySummonsLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var monster, other : CNewNPC;
    var names : string;
    var i, others : int;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member, "characters\npc_entities\monsters\noonwraith_lvl1.w2ent");
        if(bot.scenarioCount == 1)
        {
            monster = (CNewNPC)bot.scenarioEntity;
            monster.SetImmortalityMode(AIM_Immortal, AIC_Default);
            monster.SetAttitude(thePlayer, AIA_Hostile);
            monster.NoticeActor(thePlayer);
        }
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    monster = (CNewNPC)bot.scenarioEntity;
    W3T_SwingOrKite(bot, monster);
    for(i = 0; i < coop.HostEnemyCount(); i += 1)
    {
        other = coop.HostEnemyAt(i);
        if(other && other != monster && other.IsAlive() && StrFindFirst(other.GetReadableName(), "monsters") >= 0)
        {
            others += 1;
            names += " " + other.GetReadableName();
        }
    }
    W3T_Log("SUMMONS leader enemies=" + coop.HostEnemyCount() + " summoned=" + others + names + " attacks=" + coop.attacksSeen);
    return others >= 1;
}

// enemy_summons, member: a copy of a monster the leader's summoner called up (another monster template than the
// summoner's; people who join the fight, like city guards, don't count)
function W3T_EnemySummonsMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var puppet : CActor;
    var names : string;
    var i, others : int;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    for(i = 0; i < coop.PuppetCount(); i += 1)
    {
        puppet = coop.PuppetAt(i);
        names += " " + puppet.GetReadableName();
        if(puppet.GetReadableName() != W3T_MonsterPath("characters\npc_entities\monsters\noonwraith_lvl1.w2ent")
            && StrFindFirst(puppet.GetReadableName(), "monsters") >= 0)
        {
            others += 1;
        }
    }
    if(coop.PuppetCount() > 0)
    {
        W3T_LookAt(coop.PuppetAt(0).GetWorldPosition());
    }
    W3T_Log("SUMMONS member puppets=" + coop.PuppetCount() + " summoned=" + others + names + " spawned=" + coop.puppetsSpawned
        + " spawnFailures=" + coop.spawnFailures + " lastError=" + coop.lastError);
    return others >= 1;
}

// enemy_moves: the leader's test monster taunts whenever its tree comes to a taunt, at most every 6 s
@wrapMethod(CBTTaskTaunt)
function IsAvailable() : bool
{
    if(GetNPC().HasTag('W3T_AlwaysDodge'))
    {
        useXMLTauntChance = false;
        tauntDelay = 6;
    }
    return wrappedMethod();
}

// enemy_moves: the leader's test monster dodges whenever it is warned of an attack, also mid-attack
@wrapMethod(CBTTaskDodge)
function GetDodgeStats()
{
    wrappedMethod();
    if(GetNPC().HasTag('W3T_AlwaysDodge'))
    {
        dodgeChanceAttackLight = 100;
        dodgeChanceAttackHeavy = 100;
        allowDodgeWhileAttacking = true;
    }
}

// enemy_moves, member: the puppet shows the leader's monster's dodges and parries, on its slot (the leader's animation)
// or, with W3T_SLOT_MOVES=0, made by its own AI (its own dodge or parry animation is seen playing): 3 of 4 of at least
// 8 (one can be cut short by the next). Taunts and moves it made by itself are logged (a monster's tree may dodge
// natively, out of the mod's reach).
function W3T_EnemyMovesMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    if(W3T_GetEnv("W3T_SLOT_MOVES") != "")
    {
        coop.slotMoves = W3T_GetEnv("W3T_SLOT_MOVES") == "1";
    }
    if(coop.PuppetCount() > 0)
    {
        W3T_LookAt(coop.PuppetAt(0).GetWorldPosition());
    }
    W3T_Log("MOVES member movesPlayed=" + coop.movesPlayed + " started=" + coop.puppetMovesStarted + " animated="
        + coop.puppetMovesAnimated
        + " missed=" + coop.puppetMovesMissed + " own=" + coop.puppetOwnMoves + " taunts=" + coop.puppetTauntsStarted + "/"
        + coop.tauntsMirrored + " parries=" + coop.puppetParriesStarted + "/" + coop.parriesMirrored + " animOnly=" + coop.movesAnimOnly + " dodges=" + coop.puppetDodgesAnimated + "/" + coop.dodgesMirrored
        + " puppetDodged=" + coop.puppetDodgesSeen + " attacksPlayed=" + coop.attacksPlayed + " ownAttacks="
        + coop.puppetOwnAttacks + " attackEvents=" + coop.puppetAttackEvents + " moveEvents=" + coop.moveAnimEvents
        + " lastAnim=" + NameToString(coop.lastPuppetMoveAnim) + " slotMoves=" + coop.slotMovesPlayed + "/" + coop.slotMovesRefused
        + " lastError=" + coop.lastError);
    if(bot.ElapsedS() - bot.scenarioTime >= 20)
    {
        bot.scenarioTime = bot.ElapsedS();
        W3T_Log("MOVETRACE" + coop.moveTrace);
    }
    return coop.dodgesMirrored + coop.parriesMirrored >= 8 && (coop.puppetDodgesAnimated + coop.puppetParriesStarted
        + coop.slotDodgesParries) * 4 >= (coop.dodgesMirrored + coop.parriesMirrored) * 3;
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

// sign_visuals, leader: a drowner for the member to fight (out of combat its Axii doesn't go off), immortal so the signs
// don't kill it. Stays 4-8 m from the member's copy, looking at it (for screenshots). Passes once each of the member's
// signs showed its visual there (Quen: its shield) and Yrden's runes lay, the member's Yrden range and duration arrived,
// and its Quen's hit burst was copied when the drowner hit the member's shield. With W3T_OLD_SIGNS=1 the member's
// snapshot fields 73-79 are ignored, as from an older version: the visuals must still show, from this game's stats.
function W3T_SignVisualsLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var ghostPos, spot, away : Vector;
    var rot : EulerAngles;
    var dist, shieldLeft : float;

    if(bot.scenarioCount == 0)
    {
        // W3T_OLD_SIGNS=1: as if the member ran a version without snapshot fields 73-79 (the fallback)
        coop.assumeOldSigns = W3T_GetEnv("W3T_OLD_SIGNS") == "1";
        W3T_EnemyAttacksLeader(bot, coop, member);
        if(bot.scenarioCount == 1)
        {
            ((CNewNPC)bot.scenarioEntity).SetImmortalityMode(AIM_Immortal, AIC_Default);
        }
        return false;
    }
    ghostPos = member.ghost.GetWorldPosition();
    shieldLeft = -1;
    if(IsNameValid(member.quenShield))
    {
        shieldLeft = member.quenShieldUntil - theGame.GetEngineTimeAsSeconds();
    }
    dist = VecDistance(thePlayer.GetWorldPosition(), ghostPos);
    if(dist < 4 || dist > 8)
    {
        away = VecFromHeading(member.ghost.GetHeading() + 180);
        if(dist > 0.5)
        {
            away = VecNormalize(thePlayer.GetWorldPosition() - ghostPos);
        }
        if(theGame.GetWorld().NavigationFindSafeSpot(ghostPos + away * 6.0, 0.5, 2.0, spot))
        {
            rot.Yaw = VecHeading(ghostPos - spot);
            thePlayer.TeleportWithRotation(spot, rot);
        }
    }
    // a little beside the copy: looking straight at it, this Geralt stands in the way
    W3T_LookAt(ghostPos + VecFromHeading(VecHeading(ghostPos - thePlayer.GetWorldPosition()) + 90) * 2.0);
    W3T_Log("SIGNFX leader played=" + coop.signVisualsPlayed + " active=" + coop.signVisualsActive + " aard="
        + coop.SignVisualsOf(ST_Aard) + " yrden=" + coop.SignVisualsOf(ST_Yrden) + " igni=" + coop.SignVisualsOf(ST_Igni)
        + " quen=" + coop.SignVisualsOf(ST_Quen) + " axii=" + coop.SignVisualsOf(ST_Axii) + " quenShield=" + coop.quenShieldsShown
        + " quenHit=" + coop.quenHitsShown + " yrdenRunes=" + coop.yrdenRunesShown + " last=" + coop.lastSignVisual
        + " signFx=" + member.signFx + " theirYrden=" + FloatToStringPrec(member.castYrdenRange, 2) + "/"
        + FloatToStringPrec(member.castYrdenDuration, 2) + " theirQuenLevel=" + member.castQuenLevel + " quenUp=" + member.quenUp
        + " shieldLeft=" + FloatToStringPrec(shieldLeft, 1) + " ghostDist=" + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(), ghostPos), 1));
    if(!(coop.SignVisualsOf(ST_Aard) > 0 && coop.SignVisualsOf(ST_Yrden) > 0 && coop.SignVisualsOf(ST_Igni) > 0
        && coop.SignVisualsOf(ST_Axii) > 0 && coop.SignVisualsOf(ST_Quen) > 0 && coop.yrdenRunesShown > 0))
    {
        return false;
    }
    if(coop.assumeOldSigns)
    {
        return !member.signFx;
    }
    return coop.quenHitsShown > 0 && member.signFx && member.castYrdenRange > 0 && member.castYrdenDuration > 0;
}

// sign_visuals, member: joins the party and casts all five signs in turn every 3 s at the leader's drowner, in combat
// with it (scenarioCount: casts); its own Igni and Aard must play their throw effects (seen: scenarioValue bit 1 Igni,
// bit 2 Aard). The leader passes once each sign showed its visual at this player's copy, Quen's shield too.
function W3T_SignVisualsMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var puppet : CNewNPC;
    var rot : EulerAngles;
    var yrden : W3YrdenEntity;
    var ownYrden : string;
    var igni : W3IgniEntity;
    var aard : W3AardEntity;
    var seen, sign : int;

    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        bot.scenarioVec = thePlayer.GetWorldPosition();
        return false;
    }
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
        if(coop.PuppetCount() > 0)
        {
            puppet = coop.PuppetAt(0);
            rot.Yaw = VecHeading(puppet.GetWorldPosition() - bot.scenarioVec);
            W3T_LookAt(puppet.GetWorldPosition());
            thePlayer.GoToCombatIfNeeded(puppet);
        }
        // back on the spot it joined at: the drowner's hits push it around (off the quay, out of the leader's view)
        thePlayer.TeleportWithRotation(bot.scenarioVec, rot);
        // after two rounds only Quen: the other signs now hold the leader's drowner too (Axii dazes it, Yrden slows it,
        // Igni and Aard burn and fell it), and it must get to hit the shield
        sign = bot.scenarioCount % 5;
        if(bot.scenarioCount >= 10)
        {
            sign = 4;
        }
        switch(sign)
        {
            case 0: GetWitcherPlayer().SetEquippedSign(ST_Igni); break;
            case 1: GetWitcherPlayer().SetEquippedSign(ST_Aard); break;
            case 2: GetWitcherPlayer().SetEquippedSign(ST_Axii); break;
            case 3: GetWitcherPlayer().SetEquippedSign(ST_Yrden); break;
            default: GetWitcherPlayer().SetEquippedSign(ST_Quen); break;
        }
        thePlayer.GainStat(BCS_Stamina, thePlayer.GetStatMax(BCS_Stamina));
        thePlayer.SetupCombatAction(EBAT_CastSign, BS_Pressed);
        bot.scenarioCount += 1;
    }
    yrden = (W3YrdenEntity)GetWitcherPlayer().GetSignEntity(ST_Yrden);
    ownYrden = "none";
    if(yrden)
    {
        ownYrden = FloatToStringPrec(yrden.WO_TrapRange(), 2) + "/" + FloatToStringPrec(yrden.WO_TrapDuration(), 2);
    }
    W3T_Log("SIGNFX member casts=" + bot.scenarioCount + " ownIgni=" + ((seen & 1) != 0) + " ownAard=" + ((seen & 2) != 0)
        + " lastSign=" + FloatToStringPrec(client.getLastSignTime(), 1) + " cast=" + client.getCastSignType() + " ownYrden=" + ownYrden
        + " quenUp=" + thePlayer.HasBuff(EET_BasicQuen) + " quenBursts=" + client.getQuenBurstSeq() + " puppets=" + coop.PuppetCount()
        + " inCombat=" + thePlayer.IsInCombat());
    return seen == 3 && bot.scenarioCount >= 10;
}

// member_combat, leader: the drowner of enemy_attacks, immortal so it takes every kind of hit. Passes once members'
// hits did damage and their effects were added to its hits (whether they take hold is logged), copies of the
// member's bomb and bolt flew here (their own damage dropped), and the member's Axii confused it and its Yrden slowed
// it (scenarioStep bits 1 and 2).
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
    // (drained to nothing, an immortal monster lies unconscious, and bolts pass it by)
    if(monster.GetHealthPercents() < 0.5)
    {
        monster.SetHealthPerc(1.0);
    }
    // (as they took hold: the next hit, a burning tick too, ends Axii's confusion within a second)
    if(coop.effectTypesHeld.Contains((int)EET_Confusion))
    {
        bot.scenarioStep = bot.scenarioStep | 1;
    }
    if(coop.effectTypesHeld.Contains((int)EET_Slowdown))
    {
        bot.scenarioStep = bot.scenarioStep | 2;
    }
    W3T_Log("COMBAT leader hitsApplied=" + coop.hitsApplied + " effects=" + coop.hitEffectsApplied + " held=" + coop.hitEffectsHeld + " hp="
        + FloatToStringPrec(monster.GetHealthPercents(), 3) + " burning=" + monster.HasBuff(EET_Burning)
        + " knockedDown=" + (monster.HasBuff(EET_Knockdown) || monster.HasBuff(EET_HeavyKnockdown))
        + " stagger=" + monster.HasBuff(EET_Stagger) + " everBurned=" + bot.scenarioFlag + " throwCopies=" + coop.throwCopies
        + " copyFailures=" + coop.throwCopyFailures + " copyDamageDropped=" + coop.throwDamageDropped + " everConfused=" + ((bot.scenarioStep & 1) != 0) + " everSlowed=" + ((bot.scenarioStep & 2) != 0)
        + " lastError=" + coop.lastError);
    return coop.hitsApplied >= 3 && coop.hitEffectsApplied >= 2 && coop.throwCopies >= 2 && bot.scenarioStep == 3;
}

// member_combat, member: walks up to the puppet and fights it as a player: three sword swings, Igni, Aard, a fire hit
// and a knockdown carried by this player's damage actions, a bomb, a crossbow bolt, Axii and Yrden, over and over
// (scenarioCount: steps done). Passes once its sword, signs, bomb and bolt sent hits, effects went out, and Axii's
// confusion and Yrden's slowdown (put straight on the puppet, no hit) went out alone.
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

    step = bot.scenarioCount % 11;
    if(step == 7)
    {
        W3T_ThrowBomb(puppet);
    }
    else if(step == 8)
    {
        W3T_ShootBolt(puppet);
    }
    else if(step >= 9)
    {
        if(step == 9)
        {
            GetWitcherPlayer().SetEquippedSign(ST_Axii);
        }
        else
        {
            GetWitcherPlayer().SetEquippedSign(ST_Yrden);
        }
        thePlayer.GainStat(BCS_Stamina, thePlayer.GetStatMax(BCS_Stamina));
        thePlayer.SetupCombatAction(EBAT_CastSign, BS_Pressed);
    }
    else if(step < 3)
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
        + coop.signHitsSent + " effects=" + coop.hitEffectsSent + " bomb=" + coop.bombHitsSent + " bolt=" + coop.boltHitsSent
        + " ownEffects=" + coop.ownEffectsSent + " localDropped=" + coop.localEffectsDropped + " puppetConfused=" + puppet.HasBuff(EET_Confusion) + " throwsSent=" + coop.throwsSent + " lastThrow=" + coop.lastThrow + " puppetBurning=" + puppet.HasBuff(EET_Burning) + " puppetDown="
        + (puppet.HasBuff(EET_Knockdown) || puppet.HasBuff(EET_HeavyKnockdown) || puppet.HasBuff(EET_Stagger) || puppet.HasBuff(EET_LongStagger)) + " dist="
        + FloatToStringPrec(VecDistance(thePlayer.GetWorldPosition(), puppet.GetWorldPosition()), 1));
    return coop.meleeHitsSent >= 3 && coop.signHitsSent >= 1 && coop.hitEffectsSent >= 2 && coop.bombHitsSent >= 1 && coop.boltHitsSent >= 1
        && coop.ownEffectsSent >= 1;
}

// a Dancing Star thrown at the target as the player's throw does (its item and arc from the inventory)
function W3T_ThrowBomb(target : CActor)
{
    var ids : array<SItemUniqueId>;
    var bomb : W3Petard;

    ids = thePlayer.inv.AddAnItem('Dancing Star 1', 1);
    bomb = (W3Petard)thePlayer.inv.GetDeploymentItemEntity(ids[0], thePlayer.GetWorldPosition() + Vector(0, 0, 1.7), thePlayer.GetWorldRotation());
    bomb.Initialize(thePlayer, ids[0]);
    bomb.ThrowProjectile(target.GetWorldPosition() + Vector(0, 0, 1));
    W3T_Log("COMBAT member threw a bomb");
}

// a bodkin bolt shot at the target as the player's crossbow does, from where a crossbow holds it (in front of the
// player: from inside its own body the bolt stopped there)
function W3T_ShootBolt(target : CActor)
{
    var ids : array<SItemUniqueId>;
    var crossbow : SItemUniqueId;
    var bolt : W3BoltProjectile;
    var from : Vector;

    ids = thePlayer.inv.AddAnItem('Bodkin Bolt', 1);
    GetWitcherPlayer().GetItemEquippedOnSlot(EES_RangedWeapon, crossbow);
    from = thePlayer.GetWorldPosition() + VecNormalize2D(target.GetWorldPosition() - thePlayer.GetWorldPosition()) * 0.8;
    from.Z += 1.4;
    bolt = (W3BoltProjectile)thePlayer.inv.GetDeploymentItemEntity(ids[0], from, thePlayer.GetWorldRotation());
    bolt.InitializeCrossbow(thePlayer, ids[0], crossbow);
    bolt.ThrowProjectile(target.GetWorldPosition() + Vector(0, 0, 1));
    W3T_Log("COMBAT member shot a bolt at " + W3T_VecStr(target.GetWorldPosition()) + " from " + W3T_VecStr(bolt.GetWorldPosition())
        + " alive=" + target.IsAlive() + " unconscious=" + target.IsKnockedUnconscious() + " hp="
        + FloatToStringPrec(target.GetHealthPercents(), 3));
}

// trade, leader: gets a Dwarven spirit and offers it to the member for 10 crowns (Witcher Online's trade: the bot answers
// its popups, see w3test.ws). Passes once the spirit is gone from its inventory and 10 crowns came in (scenarioValue:
// money before, scenarioVec.X: spirits before).
function W3T_TradeSeller(bot : W3T_Bot, client : r_MultiplayerClient, buyer : r_RemotePlayer) : bool
{
    var spirits, money : int;

    if(!buyer.ghost)
    {
        return false;
    }
    if(bot.scenarioCount == 0)
    {
        thePlayer.inv.AddAnItem('Dwarven spirit', 1);
        bot.scenarioValue = thePlayer.GetMoney();
        bot.scenarioVec.X = thePlayer.inv.GetItemQuantityByName('Dwarven spirit');
        bot.scenarioCount = 1;
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    if(bot.scenarioCount == 1 && bot.ElapsedS() - bot.scenarioTime >= 3)
    {
        W3T_Log("TRADE seller offers a Dwarven spirit to " + buyer.username);
        client.tradeWithPlayer(buyer.ghost);
        bot.scenarioCount = 2;
    }
    spirits = thePlayer.inv.GetItemQuantityByName('Dwarven spirit');
    money = thePlayer.GetMoney();
    W3T_Log("TRADE seller step=" + bot.scenarioCount + " spirits=" + spirits + "/" + (int)bot.scenarioVec.X + " money=" + money + "/"
        + (int)bot.scenarioValue + " flag=" + client.getOutgoingTradeFlag() + " price=" + client.getOutgoingTradePrice());
    return bot.scenarioCount == 2 && spirits == (int)bot.scenarioVec.X - 1 && money == (int)bot.scenarioValue + 10;
}

// trade, member: accepts the offer (w3test.ws answers the popup). Passes once it has one more Dwarven spirit and
// 10 crowns less.
function W3T_TradeBuyer(bot : W3T_Bot, client : r_MultiplayerClient, seller : r_RemotePlayer) : bool
{
    var spirits, money : int;

    if(bot.scenarioCount == 0)
    {
        bot.scenarioValue = thePlayer.GetMoney();
        bot.scenarioVec.X = thePlayer.inv.GetItemQuantityByName('Dwarven spirit');
        bot.scenarioCount = 1;
    }
    spirits = thePlayer.inv.GetItemQuantityByName('Dwarven spirit');
    money = thePlayer.GetMoney();
    W3T_Log("TRADE buyer spirits=" + spirits + "/" + (int)bot.scenarioVec.X + " money=" + money + "/" + (int)bot.scenarioValue);
    return spirits == (int)bot.scenarioVec.X + 1 && money == (int)bot.scenarioValue - 10;
}

// enemy_crowd, leader: W3T_CROWD (default 40; it shares up to 48) immortal drowners in a ring 6-12 m around the
// member's character, neutral to this Geralt. Passes 10 s after the last, with all of them shared.
function W3T_CrowdLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var template : CEntityTemplate;
    var npc : CNewNPC;
    var pos, spot : Vector;
    var rot : EulerAngles;
    var wanted, i : int;

    wanted = StringToInt(W3T_GetEnv("W3T_CROWD"), 40);
    if(coop.GetRole() != 1 || !member.ghost)
    {
        return false;
    }
    if(bot.scenarioCount == 0)
    {
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
        for(i = 0; i < wanted; i += 1)
        {
            pos = member.ghost.GetWorldPosition() + VecFromHeading(i * 360.0 / wanted) * (6.0 + (i % 3) * 3.0);
            if(!theGame.GetWorld().NavigationFindSafeSpot(pos, 0.5, 3.0, spot))
            {
                spot = pos;
            }
            rot.Yaw = VecHeading(member.ghost.GetWorldPosition() - spot);
            npc = (CNewNPC)theGame.CreateEntity(template, spot, rot, true, false, false, PM_DontPersist);
            npc.SetImmortalityMode(AIM_Immortal, AIC_Default);
            npc.SetAttitude(thePlayer, AIA_Neutral);
            bot.scenarioEntities.PushBack(npc);
        }
        W3T_Log("CROWD leader spawned " + bot.scenarioEntities.Size() + " drowners");
        bot.scenarioCount = 1;
        bot.scenarioTime = bot.ElapsedS();
    }
    W3T_Log("CROWD leader shared=" + coop.HostEnemyCount() + " snapshotBytesMax=" + coop.hostSendBytesMax + " hurtsCaptured=" + coop.hurtsCaptured);
    return coop.HostEnemyCount() >= wanted && bot.ElapsedS() - bot.scenarioTime >= 10;
}

// enemy_crowd, member: joins the party (invulnerable) and must copy every one of the leader's drowners.
function W3T_CrowdMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var wanted : int;

    wanted = StringToInt(W3T_GetEnv("W3T_CROWD"), 40);
    if(!client.getInParty())
    {
        W3T_Log("PARTY join " + leader.username);
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        client.joinParty(leader.username);
        return false;
    }
    W3T_Log("CROWD member puppets=" + coop.PuppetCount() + " spawned=" + coop.puppetsSpawned + " hurtsApplied=" + coop.hurtsApplied
        + " lastError=" + coop.lastError);
    return coop.PuppetCount() >= wanted;
}

// player_effects, member: puts burning, a knockdown, frozen and poison on itself, 6 s apart (invulnerable, so only
// their look and animation count). Passes 8 s after the last.
function W3T_PlayerEffectsTaker(bot : W3T_Bot, coop : r_CoopEnemies, other : r_RemotePlayer) : bool
{
    var effects : array<EEffectType>;
    var given : int;

    effects.PushBack(EET_Burning);
    effects.PushBack(EET_Knockdown);
    effects.PushBack(EET_Frozen);
    effects.PushBack(EET_Poison);
    if(bot.scenarioCount == 0)
    {
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        bot.scenarioCount = 1;
        bot.scenarioTime = bot.ElapsedS();
        return false;
    }
    given = bot.scenarioCount - 1;
    if(given < effects.Size() && bot.ElapsedS() - bot.scenarioTime >= 6)
    {
        W3T_Log("PEFFECTS taker gave itself " + EffectTypeToName(effects[given]) + " result="
            + (int)thePlayer.AddEffectDefault(effects[given], thePlayer, "W3Test") + " sends " + coop.ownShownText);
        bot.scenarioCount += 1;
        bot.scenarioTime = bot.ElapsedS();
    }
    W3T_Log("PEFFECTS taker sends " + coop.ownShownText + " (" + coop.parkedSent + " sent)");
    return given >= effects.Size() && bot.ElapsedS() - bot.scenarioTime >= 8;
}

// player_effects, leader: watches the member's character; passes once 3 of its effects showed on it and as many were
// taken off again (scenarioStep: kinds seen on it, as bits).
function W3T_PlayerEffectsWatcher(bot : W3T_Bot, coop : r_CoopEnemies, other : r_RemotePlayer) : bool
{
    var ghost : CActor;
    var spot : Vector;
    var rot : EulerAngles;

    ghost = other.ghost;
    if(!ghost)
    {
        return false;
    }
    // in view: 5 m behind the member's character as the camera looks (screenshots)
    if(VecDistance2D(thePlayer.GetWorldPosition() + theCamera.GetCameraForwardOnHorizontalPlane() * 5.0, ghost.GetWorldPosition()) > 1.5
        && theGame.GetWorld().NavigationFindSafeSpot(ghost.GetWorldPosition() - theCamera.GetCameraForwardOnHorizontalPlane() * 5.0, 0.5, 3.0, spot))
    {
        rot.Yaw = theCamera.GetCameraHeading();
        thePlayer.TeleportWithRotation(spot, rot);
    }
    if(ghost.HasBuff(EET_Burning))
    {
        bot.scenarioStep = bot.scenarioStep | 1;
    }
    if(ghost.HasBuff(EET_Knockdown))
    {
        bot.scenarioStep = bot.scenarioStep | 2;
    }
    if(ghost.HasBuff(EET_Frozen))
    {
        bot.scenarioStep = bot.scenarioStep | 4;
    }
    if(ghost.HasBuff(EET_Poison))
    {
        bot.scenarioStep = bot.scenarioStep | 8;
    }
    W3T_Log("PEFFECTS watcher shown=" + coop.ghostEffectsShown + " ended=" + coop.ghostEffectsEnded + " seen=" + bot.scenarioStep
        + " burning=" + ghost.HasBuff(EET_Burning) + " down=" + ghost.HasBuff(EET_Knockdown) + " frozen=" + ghost.HasBuff(EET_Frozen)
        + " poison=" + ghost.HasBuff(EET_Poison) + " heard=" + coop.parkedHeard);
    return coop.ghostEffectsShown >= 3 && coop.ghostEffectsEnded >= 3;
}

// leader_death, leader: spawns the drowner of enemy_attacks; once the member has its copy, dies (the death screen
// respawns it from its save, which has no drowner) and spawns a new one when back (scenarioCount: 1 drowner, 2 dead,
// 3 alive again, 4 new drowner). Passes once the new drowner is shared (the member is still in the party).
function W3T_LeaderDeathLeader(bot : W3T_Bot, coop : r_CoopEnemies, players : array<r_RemotePlayer>) : bool
{
    if(players.Size() < 1)
    {
        return bot.scenarioCount >= 4;
    }
    if(bot.scenarioCount == 0)
    {
        if(players[0].ghost)
        {
            W3T_EnemyAttacksLeader(bot, coop, players[0]);
            bot.scenarioTime = bot.ElapsedS();
        }
        return false;
    }
    if(bot.scenarioCount == 1 && bot.ElapsedS() - bot.scenarioTime >= 10)
    {
        W3T_Log("DEATH leader dies");
        bot.scenarioCount = 2;
        thePlayer.SetImmortalityMode(AIM_None, AIC_Cheat, true);
        thePlayer.SetImmortalityMode(AIM_None, AIC_Default, true);
        thePlayer.Kill('W3T', true);
    }
    else if(bot.scenarioCount == 2 && thePlayer.IsAlive())
    {
        W3T_Log("DEATH leader alive again");
        bot.scenarioCount = 3;
        bot.scenarioTime = bot.ElapsedS();
    }
    else if(bot.scenarioCount == 3 && bot.ElapsedS() - bot.scenarioTime >= 5 && players[0].ghost)
    {
        bot.scenarioCount = 0;
        W3T_EnemyAttacksLeader(bot, coop, players[0]);
        bot.scenarioCount = 4;
        bot.scenarioTime = bot.ElapsedS();
        W3T_Log("DEATH leader spawned a new drowner");
    }
    W3T_Log("DEATH leader step=" + bot.scenarioCount + " alive=" + thePlayer.IsAlive() + " role=" + coop.GetRole() + " enemies="
        + coop.HostEnemyCount());
    return bot.scenarioCount == 4 && coop.HostEnemyCount() > 0 && coop.GetRole() == 1 && bot.ElapsedS() - bot.scenarioTime >= 5;
}

// leader_death, member: has a copy of the leader's drowner; while the leader is dead (its snapshots stop) lets go of
// it within 8 s, and copies the drowner the leader spawns after its respawn (scenarioCount: 1 copy, 2 let go, 3 new
// copy).
function W3T_LeaderDeathMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, players : array<r_RemotePlayer>) : bool
{
    if(!client.getInParty())
    {
        if(players.Size() > 0 && bot.scenarioCount == 0)
        {
            W3T_Log("PARTY join " + players[0].username);
            thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
            client.joinParty(players[0].username);
        }
        return false;
    }
    if(bot.scenarioCount == 0 && coop.PuppetCount() > 0)
    {
        bot.scenarioCount = 1;
    }
    else if(bot.scenarioCount == 1 && coop.PuppetCount() == 0)
    {
        W3T_Log("DEATH member let go of the leader's monsters");
        bot.scenarioCount = 2;
    }
    else if(bot.scenarioCount == 2 && coop.PuppetCount() > 0)
    {
        W3T_Log("DEATH member copies the leader's new drowner");
        bot.scenarioCount = 3;
    }
    W3T_Log("DEATH member step=" + bot.scenarioCount + " puppets=" + coop.PuppetCount() + " role=" + coop.GetRole() + " inParty="
        + client.getInParty());
    return bot.scenarioCount == 3;
}

// member_death, leader: the drowner of enemy_attacks, immortal, fights the member's character until the member dies;
// its game loads the member's save. Passes once the member was dead (no hurts sent for it meanwhile) and is alive in
// this party again (scenarioCount: 1 drowner spawned, 2 member dead, 3 back).
function W3T_DeathLeader(bot : W3T_Bot, coop : r_CoopEnemies, players : array<r_RemotePlayer>) : bool
{
    var ghost, alive : bool;

    // (no short-circuit in this language: the index only once there is one)
    ghost = false;
    alive = true;
    if(players.Size() > 0)
    {
        if(players[0].ghost)
        {
            ghost = true;
        }
        alive = players[0].isAlive;
    }
    if(bot.scenarioCount == 0)
    {
        if(ghost)
        {
            W3T_EnemyAttacksLeader(bot, coop, players[0]);
            if(bot.scenarioCount == 1)
            {
                ((CNewNPC)bot.scenarioEntity).SetImmortalityMode(AIM_Immortal, AIC_Default);
            }
        }
        return false;
    }
    if(bot.scenarioCount == 1 && !alive)
    {
        W3T_Log("DEATH leader: the member died");
        bot.scenarioCount = 2;
        bot.scenarioTime = bot.ElapsedS();
    }
    else if(bot.scenarioCount == 2 && ghost && alive && coop.GetRole() == 1)
    {
        W3T_Log("DEATH leader: the member is back in the party after " + FloatToStringPrec(bot.ElapsedS() - bot.scenarioTime, 1) + " s");
        bot.scenarioCount = 3;
    }
    W3T_Log("DEATH leader step=" + bot.scenarioCount + " ghost=" + ghost + " alive=" + alive + " role=" + coop.GetRole() + " hurtsCaptured="
        + coop.hurtsCaptured + " droppedDead=" + coop.hurtsDroppedDead + " pendingHurts=" + coop.PendingHurtCount() + " enemies=" + coop.HostEnemyCount());
    return bot.scenarioCount == 3;
}

// member_death, member: joins the party with little health and no immortality, so the leader's drowner kills it;
// the death screen respawns it from the last save (w3test.ws answers it). Passes once it is back in the party, with
// a copy of the leader's drowner, and no more than 2 hurts landed in its first 3 s alive again (they had piled up
// while it was dead and killed it again at once); then it is invulnerable (scenarioCount: 1 joined, 2 died, 3 alive
// again, 4 back; scenarioValue: hurts applied when alive again).
function W3T_DeathMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, players : array<r_RemotePlayer>) : bool
{
    if(bot.scenarioCount == 0)
    {
        if(players.Size() < 1)
        {
            return false;
        }
        if(!players[0].ghost)
        {
            return false;
        }
        if(!client.getInParty())
        {
            W3T_Log("PARTY join " + players[0].username);
            client.joinParty(players[0].username);
            return false;
        }
        thePlayer.SetImmortalityMode(AIM_None, AIC_Cheat, true);
        thePlayer.SetImmortalityMode(AIM_None, AIC_Default, true);
        bot.scenarioCount = 1;
    }
    if(bot.scenarioCount == 1)
    {
        if(thePlayer.IsAlive() && coop.PuppetCount() > 0 && thePlayer.GetStat(BCS_Vitality) > 30)
        {
            thePlayer.ForceSetStat(BCS_Vitality, 30);
        }
        if(!thePlayer.IsAlive())
        {
            W3T_Log("DEATH member died");
            bot.scenarioCount = 2;
            bot.scenarioTime = bot.ElapsedS();
        }
    }
    else if(bot.scenarioCount == 2 && thePlayer.IsAlive())
    {
        W3T_Log("DEATH member alive again after " + FloatToStringPrec(bot.ElapsedS() - bot.scenarioTime, 1) + " s, hp="
            + FloatToStringPrec(thePlayer.GetStat(BCS_Vitality), 0));
        bot.scenarioCount = 3;
        bot.scenarioTime = bot.ElapsedS();
        bot.scenarioValue = coop.hurtsApplied;
    }
    else if(bot.scenarioCount == 3 && bot.ElapsedS() - bot.scenarioTime >= 3 && coop.hurtsApplied - bot.scenarioValue > 2)
    {
        W3T_Log("FAIL " + (coop.hurtsApplied - bot.scenarioValue) + " hurts landed in the first 3 s after the respawn");
        W3T_Quit(1);
        return false;
    }
    else if(bot.scenarioCount == 3 && bot.ElapsedS() - bot.scenarioTime >= 3 && thePlayer.IsAlive() && client.getInParty()
        && coop.PuppetCount() > 0)
    {
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
        W3T_Log("DEATH member back in the party with " + coop.PuppetCount() + " copies, " + FloatToStringPrec(bot.ElapsedS() - bot.scenarioTime, 1)
            + " s after it was alive again");
        bot.scenarioCount = 4;
    }
    W3T_Log("DEATH member step=" + bot.scenarioCount + " alive=" + thePlayer.IsAlive() + " hp=" + FloatToStringPrec(thePlayer.GetStat(BCS_Vitality), 0)
        + " inParty=" + client.getInParty() + " joined=" + client.getJoinedParty() + " puppets=" + coop.PuppetCount() + " role=" + coop.GetRole()
        + " hurtsApplied=" + coop.hurtsApplied + " droppedDead=" + coop.hurtsDroppedDead + " ghosts=" + players.Size());
    return bot.scenarioCount == 4;
}

// the status effects enemy_effects gives (W3T_EFFECTS: EEffectType numbers, "18,9"; default burning, knockdown,
// frozen, blindness, confusion, bleeding)
function W3T_TestEffects() : array<EEffectType>
{
    var effects : array<EEffectType>;
    var text, piece : string;

    text = W3T_GetEnv("W3T_EFFECTS");
    if(text == "")
    {
        effects.PushBack(EET_Burning);
        effects.PushBack(EET_Knockdown);
        effects.PushBack(EET_Frozen);
        effects.PushBack(EET_Blindness);
        effects.PushBack(EET_Confusion);
        effects.PushBack(EET_Bleeding);
        return effects;
    }
    while(text != "")
    {
        piece = text;
        text = "";
        if(StrFindFirst(piece, ",") >= 0)
        {
            text = StrAfterFirst(piece, ",");
            piece = StrBeforeFirst(piece, ",");
        }
        effects.PushBack((EEffectType)StringToInt(piece, 0));
    }
    return effects;
}

// enemy_effects, leader: the drowner of enemy_attacks, immortal, gets this Geralt's status effects one after another,
// 6 s apart. Passes once all were given and the last had 8 s to end.
function W3T_EffectsLeader(bot : W3T_Bot, coop : r_CoopEnemies, member : r_RemotePlayer) : bool
{
    var monster : CNewNPC;
    var effects : array<EEffectType>;
    var type : EEffectType;
    var result : EEffectInteract;
    var given : int;

    if(bot.scenarioCount == 0)
    {
        W3T_EnemyAttacksLeader(bot, coop, member);
        if(bot.scenarioCount == 1)
        {
            ((CNewNPC)bot.scenarioEntity).SetImmortalityMode(AIM_Immortal, AIC_Default);
            bot.scenarioTime = bot.ElapsedS();
        }
        return false;
    }
    monster = (CNewNPC)bot.scenarioEntity;
    W3T_LookAt(monster.GetWorldPosition());
    effects = W3T_TestEffects();
    given = bot.scenarioCount - 1;
    if(given < effects.Size() && bot.ElapsedS() - bot.scenarioTime >= 6)
    {
        type = effects[given];
        result = monster.AddEffectDefault(type, thePlayer, "W3Test");
        W3T_Log("EFFECTS leader gave " + (int)type + " (" + EffectTypeToName(type) + ") result=" + (int)result + " held="
            + monster.HasBuff(type));
        bot.scenarioCount += 1;
        bot.scenarioTime = bot.ElapsedS();
    }
    W3T_Log("EFFECTS leader listed=" + coop.effectsListed + " fx=" + coop.lastFx + " hp=" + FloatToStringPrec(monster.GetHealthPercents(), 3));
    return given >= effects.Size() && bot.ElapsedS() - bot.scenarioTime >= 8;
}

// enemy_effects, member: each status effect on the leader's drowner shows on its copy while it lasts there and goes
// with it. Passes once 4 were on the copy and as many ended.
function W3T_EffectsMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var puppet : CNewNPC;

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
    W3T_Log("EFFECTS member mirrored=" + coop.effectsMirrored + " held=" + coop.effectsMirrorHeld + " ended=" + coop.effectsMirrorEnded
        + " burning=" + puppet.HasBuff(EET_Burning) + " down=" + (puppet.HasBuff(EET_Knockdown) || puppet.HasBuff(EET_HeavyKnockdown))
        + " frozen=" + puppet.HasBuff(EET_Frozen) + " blind=" + puppet.HasBuff(EET_Blindness) + " confused=" + puppet.HasBuff(EET_Confusion)
        + " bleeding=" + puppet.HasBuff(EET_Bleeding) + " hp=" + FloatToStringPrec(puppet.GetHealthPercents(), 3));
    return coop.effectsMirrorHeld >= 4 && coop.effectsMirrorEnded >= 4;
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

// encounter_mismatch, member: after joining, spawns a nekker where the leader spawns its drowner (this world's encounter
// came out differently). Passes once the leader's drowner is here as a spawned copy while this world's nekker is
// hidden and not a copy (the leader's world has no such nekker, so this player doesn't see one).
function W3T_MismatchMember(bot : W3T_Bot, client : r_MultiplayerClient, coop : r_CoopEnemies, leader : r_RemotePlayer) : bool
{
    var template : CEntityTemplate;
    var mine : CNewNPC;
    var rot : EulerAngles;
    var spawnedDrowner, minePuppet : bool;
    var i : int;

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
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\nekker_lvl1.w2ent", true);
        bot.scenarioEntity = theGame.CreateEntity(template, W3T_TwinSpot(bot.scenarioVec), rot, true, false, false, PM_DontPersist);
        W3T_Log("MISMATCH member spawned this world's nekker at " + W3T_VecStr(W3T_TwinSpot(bot.scenarioVec)));
        bot.scenarioCount = 2;
        return false;
    }
    mine = (CNewNPC)bot.scenarioEntity;
    for(i = 0; i < coop.PuppetCount(); i += 1)
    {
        if(coop.PuppetAt(i) == mine)
        {
            minePuppet = true;
        }
        else if(StrFindFirst(coop.PuppetAt(i).GetReadableName(), "drowner_lvl1") >= 0 && coop.PuppetSpawned(i))
        {
            spawnedDrowner = true;
        }
    }
    W3T_Log("MISMATCH member puppets=" + coop.PuppetCount() + " spawnedDrowner=" + spawnedDrowner + " nekkerIsCopy=" + minePuppet
        + " suppressed=" + coop.SuppressedCount() + " nekkerVisible=" + mine.GetVisibility() + " nekkerAlive=" + mine.IsAlive()
        + " hurtsApplied=" + coop.hurtsApplied);
    return spawnedDrowner && !minePuppet && !mine.GetVisibility();
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
