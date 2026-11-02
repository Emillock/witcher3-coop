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
        if(!boardOpen || surrendered)
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
        minigame = thePlayer.GetGwintMinigameState();
        result = "lost";
        if(minigame == EMS_End_PlayerWon)
        {
            result = "won";
        }
        W3T_Log("GWENT RESULT " + result + " (minigame state " + (int)minigame + ", self-test " + selfTest
            + ", surrendered " + surrendered + ")");
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
