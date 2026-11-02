// Gwent scenarios (one bot each), a vanilla match against the AI, no duel. The bot opens the Gwent board against the
// first deck of W3T_GWENT_DECKS (a built-in AI deck: Nilf, NilfEasy, North, nml, scotial, ske; default North), sets
// the board's gwint.game.debug.autoplay and waits for the result (GWENT RESULT won|lost). The lines Witcher Online's
// CR4GwintGameMenu.DuelLog keeps ("GwentDuel: ...", the board's OnDuelLog) go to the bot log.
// gwent_vanilla: until the board's autoplay also plays vanilla matches, the bot surrenders W3T_GWENT_HOLD seconds
//   (default 1; longer to look at the board, e.g. with run_test.py --shots) after the board is up. Passes on the result.
// gwent_selftest: the bot also sets CR4GwintManager.duelSelfTest, so Witcher Online's script turns on the board's
//   gwint.game.debug.selfTest and the board replays the duel test vectors (DuelSelfTest). The bot surrenders
//   W3T_GWENT_HOLD seconds after the "DUEL SELFTEST pass=<n> fail=<m>" line, or W3T_GWENT_SELFTEST_WAIT seconds
//   (default 30) after the board is up without it. Passes only if that line came with n > 0 and m = 0.

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
        // no fade lock when the menu closes (as the debug console's matches)
        manager.testMatch = true;
        thePlayer.SetGwintMinigameState(EMS_None);
        requested = true;
        W3T_Log("GWENT start vanilla match against " + deckName + " (player deck faction "
            + (int)manager.GetSelectedPlayerDeck() + ", self-test " + withSelfTest + ")");
        theGame.RequestMenu('GwintGame');
        GotoState('W3T_GwentWatching');
    }

    public function BoardUp()
    {
        boardOpen = true;
        boardAtMs = W3T_TimeMs();
    }

    // the menu's log lines into the bot log; then the surrender (see the scenarios above)
    public function Poll(menu : CR4GwintGameMenu)
    {
        var hold : float;

        if(!menu || result != "")
        {
            return;
        }
        Drain(menu);
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

    public function Drain(menu : CR4GwintGameMenu)
    {
        var i : int;

        for(i = 0; i < menu.duelLogLines.Size(); i += 1)
        {
            W3T_Log(menu.duelLogLines[i]);
            if(selfTestLine == "" && StrStartsWith(menu.duelLogLines[i], "GwentDuel: DUEL SELFTEST pass="))
            {
                selfTestLine = menu.duelLogLines[i];
                selfTestAtMs = W3T_TimeMs();
            }
        }
        menu.duelLogLines.Clear();
    }

    // "GwentDuel: DUEL SELFTEST pass=<n> fail=0" with n > 0
    public function SelfTestPassed() : bool
    {
        var words : array<string>;

        words = W3T_Split(selfTestLine, " ");
        return words.Size() == 5 && StrStartsWith(words[3], "pass=") && words[3] != "pass=0" && words[4] == "fail=0";
    }

    public function Closed(menu : CR4GwintGameMenu)
    {
        var minigame : EMinigameState;

        Drain(menu);
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
        if(gwent.selfTestLine == "")
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
        m_flashValueStorage.SetFlashBool("gwint.game.debug.autoplay", true);
        theGame.w3t_gwent.BoardUp();
        W3T_Log("GWENT board open; gwint.game.debug.autoplay set");
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
