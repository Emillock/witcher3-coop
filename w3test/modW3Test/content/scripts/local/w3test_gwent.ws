// Gwent scenarios (one bot each), a vanilla match against the AI, no duel. The bot opens the Gwent board against the
// first deck of W3T_GWENT_DECKS (a built-in AI deck: Nilf, NilfEasy, North, nml, scotial, ske; default North), sets
// CR4GwintManager.duelDebugAutoplay (Witcher Online's script passes it to the board as gwint.game.debug.autoplay) and
// waits for the result (GWENT RESULT won|lost). The board's duel log lines (OnDuelLog, which Witcher Online hands to
// r_MultiplayerClient.duelLog) go to the bot log as "GwentDuel: <line>" through a wrap of duelLog.
// gwent_vanilla: until the board's autoplay also plays vanilla matches, the bot surrenders W3T_GWENT_HOLD seconds
//   (default 1; longer to look at the board, e.g. with run_test.py --shots) after the board is up. Passes on the result.
// gwent_selftest: the bot also sets CR4GwintManager.duelSelfTest, so Witcher Online's script turns on the board's
//   gwint.game.debug.selfTest and the board replays the duel test vectors (DuelSelfTest). The bot surrenders
//   W3T_GWENT_HOLD seconds after the "DUEL SELFTEST pass=<n> fail=<m>" line, or W3T_GWENT_SELFTEST_WAIT seconds
//   (default 30) after the board is up without it. Passes only if that line came with n > 0 and m = 0, and Witcher
//   Online's duel deck fields passed the script checks below (GWENT script checks ok ...): no card or leader name in
//   GetCardDefs/GetLeaderDefs has a space or "~" or fails to come back through the wo3 encoding, the selected player
//   deck round-trips through WO_GwentDeckFields/WO_GwentParseDeck, and 4.04 or marker-less deck fields give protocol 0.
// gwent_duel (two bots): a Gwent duel between the bots through the local server and Witcher Online's challenge.
//   Each bot plays its own entry of W3T_GWENT_DECKS (bot 0 the first, bot 1 the second; default North,North): a
//   built-in deck name for GetDeck (North and NilfEasy hold cards; Nilf, nml, scotial, ske are starter decks without
//   cards) or an inline deck "leader+card+card+..." (run_test.py turns the names in w3test\gwent_decks.txt into
//   these). Bot 0 (W3T_ROLE mover, the host, seat A) challenges bot 1 for W3T_GWENT_BET crowns (default 10;
//   W3T_GWENT_TIMED=1 for a timed duel, W3T_GWENT_SEED forces the seed), bot 1 accepts in Witcher Online's popup (see
//   w3test.ws), and both boards play themselves (CR4GwintManager.duelDebugAutoplay; W3T_GWENT_MULLIGAN=1 redraws at
//   the mulligan, default 0 declines; W3T_GWENT_LEADER_FIRST=1 makes autoplay play its leader as soon as it can). W3T_GWENT_BREAK_TEMPLATES=1 makes bot 0's board send a wrong card table hash.
//   W3T_GWENT_CORRUPT_AT=<seq> makes bot 0's board add 1 to one card's power right before it sends that seq, so the
//   peer's hash check fails (desync: both boards must log DUEL DESYNC and end as no contest, reason desync).
//   Each bot logs its money before and after and passes when its board's duel lines match W3T_GWENT_EXPECT:
//   "result" (default): DUEL HELLO ok with its seat, at least one DUEL ROUND, DUEL END result=win|loss|draw, and the
//   money moved by +bet, -bet or 0; "nocontest": DUEL END result=nocontest (with reason W3T_GWENT_REASON if set) and
//   no money change; with W3T_GWENT_CORRUPT_AT also a "DUEL DESYNC" line and reason=desync. Every bot also needs
//   Witcher Online's "DUEL DYNAMIC cards=0" (no dynamic cards for the duel deck name).
//   In a session (run_test.py --matrix) each duel reads these W3T_GWENT_* settings when it starts (the control file
//   sets them, see w3test.ws), the Gwent state starts over between duels (W3T_ResetGwent), and a failed verdict does
//   not end the game: the bot logs it and the next duel follows in the same game.

@addField(CR4Game)
var w3t_gwent : W3T_Gwent;

@addMethod(CR4Game)
function W3T_GwentState() : W3T_Gwent
{
    if(!w3t_gwent)
    {
        w3t_gwent = new W3T_Gwent in this;
    }
    return w3t_gwent;
}

// a session's next scenario: the last Gwent scenario's state goes (its deck, step, lines, money before), and the
// board's test switches are off, as after a match (W3T_Gwent.Closed). The next duel starts from step 0: it reads its
// own settings and its money again.
@addMethod(CR4Game)
function W3T_ResetGwent()
{
    var manager : CR4GwintManager;

    if(!w3t_gwent)
    {
        return;
    }
    manager = GetGwintManager();
    manager.duelDebugAutoplay = false;
    manager.duelSelfTest = false;
    manager.duelDebugMulligan = false;
    manager.duelDebugLeaderFirst = false;
    manager.duelDebugBreakTemplates = false;
    manager.duelDebugCorruptAt = 0;
    W3T_Log("GWENT state reset (result " + w3t_gwent.result + ", money " + thePlayer.GetMoney() + ")");
    w3t_gwent = NULL;
}

statemachine class W3T_Gwent
{
    public var deck : string;
    public var selfTest : bool;    // gwent_selftest: ask the board for its self-test
    public var requested : bool;
    public var boardOpen : bool;
    public var boardAtMs : int;
    public var selfTestLine : string;   // the self-test's summary line once it came
    public var selfTestAtMs : int;
    public var scriptChecksOk : bool;   // gwent_selftest: Witcher Online's deck exchange checks passed
    public var surrendered : bool;
    public var result : string;   // "won" or "lost" once the menu closed
    public var frames : int;      // the watcher's frames (latent functions keep running while the board is open)
    // gwent_duel
    public var duel : bool;
    public var hasDuelDeck : bool;      // GetCurrentPlayerDeck returns duelDeck (the deck Witcher Online sends)
    public var duelDeck : SDeckDefinition;
    public var duelStep : int;
    public var duelStepAt : float;
    public var duelBet : int;
    public var moneyBefore : int;
    public var helloLine : string;      // the board's first "DUEL HELLO" line
    public var endLine : string;        // its last "DUEL END" line
    public var rounds : int;            // its "DUEL ROUND" lines
    public var dynamicLine : string;    // Witcher Online's "DUEL DYNAMIC cards=<n>" (GetDynamicCards of the duel decks)
    public var desyncLine : string;     // the board's first "DUEL DESYNC" line
    public var duelPassed : bool;
    public var challengePopup : CR4ItemSelectionPopup;   // the guest's open challenge popup, accepted on the next step
    public var combatLogged : bool;     // EndCombat found this bot in combat once already

    // the challenge popup opened (w3test.ws)
    public function ChallengeShown(popup : CR4ItemSelectionPopup)
    {
        challengePopup = popup;
    }

    public function Start(deckName : string, withSelfTest : bool)
    {
        var manager : CR4GwintManager;

        deck = deckName;
        selfTest = withSelfTest;
        manager = theGame.GetGwintManager();
        manager.SetHasDoneTutorial(true);
        manager.SetHasDoneDeckTutorial(true);
        manager.setDoubleAIEnabled(false);
        manager.SetEnemyDeck(WO_ToName(deckName));
        manager.duelSelfTest = withSelfTest;
        manager.duelDebugAutoplay = true;
        // no fade lock when the menu closes (as the debug console's matches)
        manager.testMatch = true;
        thePlayer.SetGwintMinigameState(EMS_None);
        requested = true;
        if(withSelfTest)
        {
            scriptChecksOk = ScriptChecks();
        }
        W3T_Log("GWENT start vanilla match against " + deckName + " (player deck faction "
            + (int)manager.GetSelectedPlayerDeck() + ", self-test " + withSelfTest + ")");
        theGame.RequestMenu('GwintGame');
        GotoState('W3T_GwentWatching');
    }

    // Witcher Online's duel deck exchange, checked against this game's card table (no board needed)
    public function ScriptChecks() : bool
    {
        var manager : CR4GwintManager;
        var defs : array<SCardDefinition>;
        var leaders : array<SCardDefinition>;
        var deck : SDeckDefinition;
        var parsed : SDeckDefinition;
        var text : string;
        var protocol : int;
        var badNames : int;
        var i : int;
        var ok : bool;

        manager = theGame.GetGwintManager();
        defs = manager.GetCardDefs();
        leaders = manager.GetLeaderDefs();
        for(i = 0; i < leaders.Size(); i += 1)
        {
            defs.PushBack(leaders[i]);
        }
        for(i = 0; i < defs.Size(); i += 1)
        {
            text = NameToString(defs[i].cardName);
            if(StrContains(text, " ") || StrContains(text, "~") || WO_GwentDecodeName(WO_GwentEncodeName(defs[i].cardName)) != defs[i].cardName)
            {
                badNames += 1;
                W3T_Log("GWENT card name not safe for the wo3 packet: '" + text + "'");
            }
        }

        deck = manager.GetCurrentPlayerDeck();
        protocol = WO_GwentParseDeck("3 " + WO_GwentDeckFields(deck), parsed);
        ok = badNames == 0 && defs.Size() > 0 && protocol == WO_GwentProtocol() && parsed.leaderCard == deck.leaderCard
            && parsed.specialCard == deck.specialCard && parsed.cards.Size() == deck.cards.Size() && parsed.unlocked;
        for(i = 0; ok && i < deck.cards.Size(); i += 1)
        {
            ok = parsed.cards[i] == deck.cards[i];
        }
        // a 4.04 client's fields (faction, leader index, card indices) and the 5.x port's before duels (faction, 0)
        ok = ok && WO_GwentParseDeck("3 1001 12 13 14", parsed) == 0 && parsed.cards.Size() == 0;
        ok = ok && WO_GwentParseDeck("3 0", parsed) == 0 && WO_GwentParseDeck("", parsed) == 0;
        ok = ok && WO_GwentParseDeck("3 gp2 a b c", parsed) == 2 && parsed.cards.Size() == 0;

        W3T_Log("GWENT script checks " + W3T_OkText(ok) + " (names=" + defs.Size() + " unsafe=" + badNames + " deck leader="
            + NameToString(deck.leaderCard) + " cards=" + deck.cards.Size() + " protocol=" + protocol + ")");
        return ok;
    }

    public function BoardUp()
    {
        boardOpen = true;
        boardAtMs = W3T_TimeMs();
    }

    // the surrender (see the scenarios above)
    public function Poll(menu : CR4GwintGameMenu)
    {
        var hold : float;

        if(!menu || result != "")
        {
            return;
        }
        // a duel plays itself (the board's autoplay) and ends by itself
        if(duel || !boardOpen || surrendered)
        {
            return;
        }
        hold = StringToFloat(W3T_GetEnv("W3T_GWENT_HOLD"), 1.0);
        if(!selfTest && SecondsSince(boardAtMs) > hold)
        {
            Surrender(menu, "board up");
        }
        else if(selfTest && selfTestLine != "" && SecondsSince(selfTestAtMs) > hold)
        {
            Surrender(menu, "self-test reported");
        }
        else if(selfTest && selfTestLine == ""
            && SecondsSince(boardAtMs) > StringToFloat(W3T_GetEnv("W3T_GWENT_SELFTEST_WAIT"), 30.0))
        {
            Surrender(menu, "no self-test line");
        }
    }

    public function SecondsSince(ms : int) : float
    {
        return (W3T_TimeMs() - ms) / 1000.0;
    }

    public function Surrender(menu : CR4GwintGameMenu, why : string)
    {
        surrendered = true;
        W3T_Log("GWENT surrender (" + why + ")");
        menu.OnQuitGameConfirmed();
    }

    // one line of the board's duel log, already in the bot log as "GwentDuel: <line>"
    public function DuelLine(line : string)
    {
        if(duel && result == "")
        {
            if(helloLine == "" && StrStartsWith(line, "DUEL HELLO"))
            {
                helloLine = line;
            }
            if(StrStartsWith(line, "DUEL ROUND "))
            {
                rounds += 1;
            }
            if(StrStartsWith(line, "DUEL END "))
            {
                endLine = line;
            }
            if(StrStartsWith(line, "DUEL DYNAMIC "))
            {
                dynamicLine = line;
            }
            if(desyncLine == "" && StrStartsWith(line, "DUEL DESYNC "))
            {
                desyncLine = line;
            }
        }
        if(requested && result == "" && selfTestLine == "" && StrStartsWith(line, "DUEL SELFTEST pass="))
        {
            selfTestLine = "GwentDuel: " + line;
            selfTestAtMs = W3T_TimeMs();
        }
    }

    // "GwentDuel: DUEL SELFTEST pass=<n> fail=0" with n > 0
    public function SelfTestPassed() : bool
    {
        var words : array<string>;

        words = W3T_Split(selfTestLine, " ");
        return scriptChecksOk && words.Size() == 5 && StrStartsWith(words[3], "pass=") && words[3] != "pass=0"
            && words[4] == "fail=0";
    }

    public function Closed(menu : CR4GwintGameMenu)
    {
        var minigame : EMinigameState;
        var manager : CR4GwintManager;

        // the test switches only for the match this scenario opened
        manager = theGame.GetGwintManager();
        manager.duelDebugAutoplay = false;
        manager.duelSelfTest = false;
        manager.duelDebugMulligan = false;
        manager.duelDebugLeaderFirst = false;
        manager.duelDebugBreakTemplates = false;
        manager.duelDebugCorruptAt = 0;
        minigame = thePlayer.GetGwintMinigameState();
        result = "lost";
        if(minigame == EMS_End_PlayerWon)
        {
            result = "won";
        }
        W3T_Log("GWENT RESULT " + result + " (minigame state " + (int)minigame + ", self-test " + selfTest
            + ", surrendered " + surrendered + ")");
    }

    // gwent_duel, one step a report (see the scenarios above). 0: own deck and test switches; 1: the host challenges
    // once both sides see each other's duel protocol; 2: the match; 3: a moment for the settlement; 4: the verdict.
    public function DuelStep(bot : W3T_Bot, client : r_MultiplayerClient, peer : r_RemotePlayer) : bool
    {
        var manager : CR4GwintManager;
        var decks : array<string>;
        var deckEntry : string;
        var host : bool;
        var seed : int;
        var noItem : SItemUniqueId;

        host = W3T_GetEnv("W3T_ROLE") == "mover";
        manager = theGame.GetGwintManager();
        if(!boardOpen && duelStep <= 2 && W3T_GetEnv("W3T_SCENARIOS") != "")
        {
            EndCombat();
        }
        if(challengePopup)
        {
            W3T_Log("GWENT duel accepts the challenge");
            challengePopup.OnCallSelectItem(noItem);
            challengePopup = NULL;
        }
        if(duelStep == 0)
        {
            // once the save has placed the player and the world has settled
            if(!bot.homeSet || bot.ElapsedS() < 10)
            {
                return false;
            }
            decks = W3T_Split(W3T_GetEnv("W3T_GWENT_DECKS"), ",");
            while(decks.Size() < 2)
            {
                decks.PushBack("North");
            }
            deckEntry = decks[0];
            if(!host)
            {
                deckEntry = decks[1];
            }
            if(!W3T_GwentDeckFromEntry(deckEntry, duelDeck))
            {
                W3T_Log("FAIL gwent duel: deck " + deckEntry + " is not a built-in deck or has an unknown card");
                W3T_Quit(1);
                return false;
            }
            hasDuelDeck = true;
            duel = true;
            requested = true;
            manager.SetHasDoneTutorial(true);
            manager.SetHasDoneDeckTutorial(true);
            manager.setDoubleAIEnabled(false);
            manager.duelDebugAutoplay = true;
            // monsters roam near the test save; a dead bot never gets to its board
            thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Cheat, true);
            manager.duelDebugMulligan = W3T_GetEnv("W3T_GWENT_MULLIGAN") == "1";
            manager.duelDebugLeaderFirst = W3T_GetEnv("W3T_GWENT_LEADER_FIRST") == "1";
            manager.duelDebugBreakTemplates = host && W3T_GetEnv("W3T_GWENT_BREAK_TEMPLATES") == "1";
            manager.duelDebugCorruptAt = 0;
            if(host)
            {
                manager.duelDebugCorruptAt = StringToInt(W3T_GetEnv("W3T_GWENT_CORRUPT_AT"), 0);
            }
            duelBet = StringToInt(W3T_GetEnv("W3T_GWENT_BET"), 10);
            if(thePlayer.GetMoney() < duelBet)
            {
                thePlayer.AddMoney(duelBet - thePlayer.GetMoney());
            }
            // read here, before the deck goes out: the guest may accept the challenge before its next step runs
            moneyBefore = thePlayer.GetMoney();
            W3T_Log("GWENT duel money before=" + moneyBefore + " bet=" + duelBet);
            W3T_Log("GWENT duel deck " + deckEntry + " (leader " + NameToString(duelDeck.leaderCard) + ", " + duelDeck.cards.Size()
                + " cards), host " + host + ", break templates " + manager.duelDebugBreakTemplates + ", corrupt at "
                + manager.duelDebugCorruptAt + ", mulligan redraw " + manager.duelDebugMulligan + ", leader first "
                + manager.duelDebugLeaderFirst);
            duelStep = 1;
            duelStepAt = bot.ElapsedS();
            return false;
        }
        if(duelStep == 1)
        {
            // the deck goes out in every wo3 packet: give it a few seconds to reach the peer, and wait for the peer's
            if(bot.ElapsedS() - duelStepAt < 5 || !client.gwentProtocolMatches(peer))
            {
                return false;
            }
            if(host)
            {
                seed = StringToInt(W3T_GetEnv("W3T_GWENT_SEED"), 0);
                W3T_Log("GWENT duel challenge " + peer.username + " (id " + peer.id + ", seed " + seed + ", timed "
                    + (W3T_GetEnv("W3T_GWENT_TIMED") == "1") + ")");
                client.W3T_GwentChallenge(peer.id, W3T_GetEnv("W3T_GWENT_TIMED") == "1", duelBet, seed);
            }
            GotoState('W3T_GwentWatching');
            duelStep = 2;
            duelStepAt = bot.ElapsedS();
            return false;
        }
        if(duelStep == 2)
        {
            if(result == "")
            {
                if(!boardOpen && bot.ElapsedS() - duelStepAt > 120)
                {
                    W3T_Log("FAIL gwent duel: no board 120 s after the challenge");
                    W3T_Quit(1);
                }
                return false;
            }
            duelStep = 3;
            duelStepAt = bot.ElapsedS();
            return false;
        }
        if(duelStep == 3)
        {
            if(bot.ElapsedS() - duelStepAt < 3)
            {
                return false;
            }
            duelStep = 4;
            duelPassed = DuelVerdict(host);
        }
        return duelPassed;
    }

    // In a session the bots stand in the world for an hour, and monsters roam near the test save. Witcher Online does
    // not show a challenge to a player in combat, so the duel would never start (most likely what happened to the one
    // duel of 21 that got "no board 120 s after the challenge": its guest had moved 23 m from its start point without
    // being told to). Before the board is up, hostile actors within 40 m of a bot in combat go at once.
    public function EndCombat()
    {
        var entities : array<CGameplayEntity>;
        var npc : CNewNPC;
        var removed : int;
        var i : int;

        if(!thePlayer.IsInCombat())
        {
            return;
        }
        FindGameplayEntitiesInSphere(entities, thePlayer.GetWorldPosition(), 40.0, 64, '', FLAG_OnlyAliveActors, thePlayer);
        for(i = 0; i < entities.Size(); i += 1)
        {
            npc = (CNewNPC)entities[i];
            if(npc && GetAttitudeBetween(npc, thePlayer) == AIA_Hostile)
            {
                W3T_Log("GWENT duel: in combat before the board, removes " + npc.GetReadableName() + " at "
                    + W3T_VecStr(npc.GetWorldPosition()));
                npc.Destroy();
                removed += 1;
            }
        }
        if(removed == 0 && !combatLogged)
        {
            W3T_Log("GWENT duel: in combat before the board, no hostile within 40 m");
        }
        combatLogged = true;
    }

    // whether the board's duel lines and the money match W3T_GWENT_EXPECT (fails the bot otherwise)
    public function DuelVerdict(host : bool) : bool
    {
        var words : array<string>;
        var expect : string;
        var reason : string;
        var outcome : string;
        var why : string;
        var moneyAfter : int;
        var wanted : int;

        expect = W3T_GetEnv("W3T_GWENT_EXPECT");
        if(expect == "")
        {
            expect = "result";
        }
        moneyAfter = thePlayer.GetMoney();
        words = W3T_Split(endLine, " ");
        if(words.Size() >= 4)
        {
            outcome = StrAfterFirst(words[2], "result=");
            reason = StrAfterFirst(words[3], "reason=");
        }
        W3T_Log("GWENT duel money before=" + moneyBefore + " after=" + moneyAfter + " bet=" + duelBet + " (" + endLine + ")");

        wanted = 0;
        if(endLine == "")
        {
            why = "the board sent no DUEL END line";
        }
        else if(dynamicLine != "DUEL DYNAMIC cards=0")
        {
            why = "the duel decks must have no dynamic cards, got [" + dynamicLine + "]";
        }
        else if(expect == "nocontest")
        {
            if(outcome != "nocontest")
            {
                why = "expected result=nocontest";
            }
            else if(W3T_GetEnv("W3T_GWENT_REASON") != "" && reason != W3T_GetEnv("W3T_GWENT_REASON"))
            {
                why = "expected reason=" + W3T_GetEnv("W3T_GWENT_REASON");
            }
            else if(W3T_GetEnv("W3T_GWENT_CORRUPT_AT") != "" && (desyncLine == "" || reason != "desync"))
            {
                why = "expected DUEL DESYNC and reason=desync, got [" + desyncLine + "]";
            }
        }
        else
        {
            if(helloLine != "DUEL HELLO ok seat=" + W3T_GwentSeatName(host))
            {
                why = "expected DUEL HELLO ok seat=" + W3T_GwentSeatName(host) + ", got [" + helloLine + "]";
            }
            else if(rounds < 1)
            {
                why = "no DUEL ROUND line";
            }
            else if(outcome == "win")
            {
                wanted = duelBet;
            }
            else if(outcome == "loss")
            {
                wanted = -duelBet;
            }
            else if(outcome != "draw")
            {
                why = "expected result=win|loss|draw";
            }
        }
        if(why == "" && moneyAfter - moneyBefore != wanted)
        {
            why = "money moved by " + (moneyAfter - moneyBefore) + ", expected " + wanted;
        }
        if(why != "")
        {
            // the board has closed: in a session the next duel can follow in this game
            W3T_FailScenario("gwent duel: " + why + " (" + endLine + ")");
            return false;
        }
        W3T_Log("GWENT duel ok: " + endLine + ", " + rounds + " rounds, money " + (moneyAfter - moneyBefore));
        return true;
    }
}

state W3T_GwentWatching in W3T_Gwent
{
    event OnEnterState(prevStateName : name)
    {
        Watch();
    }

    // every frame while the match is on (the game is paused then, but latent functions run), with a line a second
    entry function Watch()
    {
        var menu : CR4GwintGameMenu;
        var reportedMs : int;
        var board : string;

        while(parent.result == "")
        {
            parent.frames += 1;
            menu = (CR4GwintGameMenu)theGame.GetGuiManager().GetRootMenu();
            if(W3T_TimeMs() - reportedMs >= 1000)
            {
                reportedMs = W3T_TimeMs();
                board = "none";
                if(menu)
                {
                    board = "open";
                }
                W3T_Log("GWENT watch frames=" + parent.frames + " board=" + board + " paused=" + theGame.IsPaused());
            }
            parent.Poll(menu);
            SleepOneFrame();
        }
    }
}

function W3T_OkText(ok : bool) : string
{
    if(ok)
    {
        return "ok";
    }
    return "FAILED";
}

// one vanilla match; withSelfTest: also the board's self-test, which must report no failure
function W3T_GwentMatch(bot : W3T_Bot, withSelfTest : bool) : bool
{
    var gwent : W3T_Gwent;
    var decks : array<string>;

    gwent = theGame.W3T_GwentState();
    if(!gwent.requested)
    {
        // once the save has placed the player and the world has settled
        if(!bot.homeSet || bot.ElapsedS() < 10)
        {
            return false;
        }
        decks = W3T_Split(W3T_GetEnv("W3T_GWENT_DECKS"), ",");
        if(decks.Size() == 0)
        {
            decks.PushBack("North");
        }
        gwent.Start(decks[0], withSelfTest);
        return false;
    }
    if(gwent.result == "")
    {
        return false;
    }
    if(withSelfTest && !gwent.SelfTestPassed())
    {
        if(!gwent.scriptChecksOk)
        {
            W3T_Log("FAIL Witcher Online's duel deck checks (see GWENT script checks)");
        }
        else if(gwent.selfTestLine == "")
        {
            W3T_Log("FAIL the board sent no DUEL SELFTEST line");
        }
        else
        {
            W3T_Log("FAIL self-test: " + gwent.selfTestLine);
        }
        W3T_Quit(1);
        return false;
    }
    return true;
}

function W3T_GwentVanilla(bot : W3T_Bot) : bool
{
    return W3T_GwentMatch(bot, false);
}

function W3T_GwentSelfTest(bot : W3T_Bot) : bool
{
    return W3T_GwentMatch(bot, true);
}

function W3T_GwentDuel(bot : W3T_Bot, client : r_MultiplayerClient, peer : r_RemotePlayer) : bool
{
    return theGame.W3T_GwentState().DuelStep(bot, client, peer);
}

function W3T_GwentSeatName(host : bool) : string
{
    if(host)
    {
        return "A";
    }
    return "B";
}

// A W3T_GWENT_DECKS entry as a deck: a built-in deck name (GetDeck, difficulty 1) or "leader+card+card+...".
// False when the deck is unknown or names a card the game does not have.
function W3T_GwentDeckFromEntry(deckEntry : string, out deck : SDeckDefinition) : bool
{
    var manager : CR4GwintManager;
    var empty : SDeckDefinition;
    var card : SCardDefinition;
    var parts : array<string>;
    var i : int;

    manager = theGame.GetGwintManager();
    deck = empty;
    if(StrContains(deckEntry, "+"))
    {
        parts = W3T_Split(deckEntry, "+");
        deck.deckName = 'w3t_gwent_duel';
        deck.leaderCard = WO_ToName(parts[0]);
        for(i = 1; i < parts.Size(); i += 1)
        {
            deck.cards.PushBack(WO_ToName(parts[i]));
        }
    }
    else if(!manager.GetDeck(WO_ToName(deckEntry), 1, deck))
    {
        return false;
    }
    deck.unlocked = true;
    if(!manager.GetGwentCard(deck.leaderCard, card))
    {
        W3T_Log("GWENT unknown leader " + NameToString(deck.leaderCard));
        return false;
    }
    for(i = 0; i < deck.cards.Size(); i += 1)
    {
        if(!manager.GetGwentCard(deck.cards[i], card))
        {
            W3T_Log("GWENT unknown card " + NameToString(deck.cards[i]));
            return false;
        }
    }
    return true;
}

// gwent_duel: the bot's own duel deck is the one Witcher Online sends to the peer and shows on its board
@wrapMethod(CR4GwintManager)
function GetCurrentPlayerDeck() : SDeckDefinition
{
    if(W3T_Active() && theGame.w3t_gwent && theGame.w3t_gwent.hasDuelDeck)
    {
        return theGame.w3t_gwent.duelDeck;
    }
    return wrappedMethod();
}

// gwent_duel: the host's challenge as the challenge popup and the bet slider would send it (type, bet), with the seed
// forced when W3T_GWENT_SEED is set
@addMethod(r_MultiplayerClient)
function W3T_GwentChallenge(toId : string, timed : bool, bet : int, seed : int)
{
    clearGwentRequestState();
    outgoingGwentTo = toId;
    if(timed)
    {
        setGwentGameType(GG_Timed);
    }
    else
    {
        setGwentGameType(GG_Normal);
    }
    setGwentBetAmount(bet);
    if(seed != 0)
    {
        outgoingGwentSeed = seed;
    }
}

@wrapMethod(CR4GwintGameMenu)
function OnConfigUI()
{
    wrappedMethod();

    if(W3T_Active() && theGame.w3t_gwent && theGame.w3t_gwent.requested)
    {
        theGame.w3t_gwent.BoardUp();
        W3T_Log("GWENT board open; gwint.game.debug.autoplay set");
    }
}

// the board's duel log (Witcher Online only writes it to LogChannel, which reaches no file) into the bot log
@wrapMethod(r_MultiplayerClient)
function duelLog(line : string)
{
    wrappedMethod(line);

    if(W3T_Active())
    {
        W3T_Log("GwentDuel: " + line);
        if(theGame.w3t_gwent)
        {
            theGame.w3t_gwent.DuelLine(line);
        }
    }
}

@wrapMethod(CR4GwintGameMenu)
function OnClosingMenu()
{
    wrappedMethod();

    if(W3T_Active() && theGame.w3t_gwent)
    {
        theGame.w3t_gwent.Closed(this);
    }
}
