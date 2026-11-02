// Gwent scenarios.
// gwent_vanilla (one bot): a vanilla match against the AI, no duel. The bot opens the Gwent board against the first
// deck of W3T_GWENT_DECKS (a built-in AI deck: Nilf, NilfEasy, North, nml, scotial, ske; default North), sets the
// board's gwint.game.debug.autoplay and waits for the result (GWENT RESULT won|lost). The lines Witcher Online's
// CR4GwintGameMenu.DuelLog keeps (the board's build probe "GwentDuel: probe probe-1") go to the bot log. Until the
// board's autoplay also plays vanilla matches, the bot surrenders once the probe line is in: W3T_GWENT_HOLD seconds
// later (default 1; longer to look at the board, e.g. with run_test.py --shots).

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
    public var requested : bool;
    public var probe : bool;
    public var probeAtMs : int;
    public var surrendered : bool;
    public var result : string;   // "won" or "lost" once the menu closed
    public var frames : int;      // the watcher's frames (latent functions keep running while the board is open)

    public function Start(deckName : string)
    {
        var manager : CR4GwintManager;

        deck = deckName;
        manager = theGame.GetGwintManager();
        manager.SetHasDoneTutorial(true);
        manager.SetHasDoneDeckTutorial(true);
        manager.setDoubleAIEnabled(false);
        manager.SetEnemyDeck(WO_ToName(deckName));
        // no fade lock when the menu closes (as the debug console's matches)
        manager.testMatch = true;
        thePlayer.SetGwintMinigameState(EMS_None);
        requested = true;
        W3T_Log("GWENT start vanilla match against " + deckName + " (player deck faction "
            + (int)manager.GetSelectedPlayerDeck() + ")");
        theGame.RequestMenu('GwintGame');
        GotoState('W3T_GwentWatching');
    }

    // the menu's log lines into the bot log; then the surrender, W3T_GWENT_HOLD seconds after the probe line
    public function Poll(menu : CR4GwintGameMenu)
    {
        if(!menu || result != "")
        {
            return;
        }
        Drain(menu);
        if(probe && !surrendered && (W3T_TimeMs() - probeAtMs) / 1000.0 > StringToFloat(W3T_GetEnv("W3T_GWENT_HOLD"), 1.0))
        {
            surrendered = true;
            W3T_Log("GWENT surrender");
            menu.OnQuitGameConfirmed();
        }
    }

    public function Drain(menu : CR4GwintGameMenu)
    {
        var i : int;

        for(i = 0; i < menu.duelLogLines.Size(); i += 1)
        {
            W3T_Log(menu.duelLogLines[i]);
            if(!probe && StrStartsWith(menu.duelLogLines[i], "GwentDuel: probe "))
            {
                probe = true;
                probeAtMs = W3T_TimeMs();
            }
        }
        menu.duelLogLines.Clear();
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
        W3T_Log("GWENT RESULT " + result + " (minigame state " + (int)minigame + ", probe " + probe + ", surrendered "
            + surrendered + ")");
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

function W3T_GwentVanilla(bot : W3T_Bot) : bool
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
        gwent.Start(decks[0]);
        return false;
    }
    return gwent.result != "";
}

@wrapMethod(CR4GwintGameMenu)
function OnConfigUI()
{
    wrappedMethod();

    if(W3T_Active() && W3T_CurrentScenario() == "gwent_vanilla")
    {
        m_flashValueStorage.SetFlashBool("gwint.game.debug.autoplay", true);
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
