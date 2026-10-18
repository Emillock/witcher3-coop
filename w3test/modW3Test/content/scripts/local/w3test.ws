// In-game test bot. Does nothing unless the W3T_SCENARIO environment variable is set.
// Env: W3T_SCENARIO (name), W3T_SAVE (part of a save filename; newest save if empty), W3T_DURATION (seconds in game).

import function W3T_GetEnv(key : string) : string;
import function W3T_Log(line : string);
import function W3T_TimeMs() : int;
import function W3T_Quit(code : int);

function W3T_Active() : bool
{
    return W3T_GetEnv("W3T_SCENARIO") != "";
}

function W3T_VecStr(v : Vector) : string
{
    return FloatToStringPrec(v.X, 2) + "," + FloatToStringPrec(v.Y, 2) + "," + FloatToStringPrec(v.Z, 2);
}

@addField(CR4Game)
var w3t_bot : W3T_Bot;

@addField(CR4Game)
var w3t_loadRequested : bool;

// theGame is const outside CR4Game, so its added fields are changed through methods.
@addMethod(CR4Game)
function W3T_ClaimLoad() : bool
{
    if(w3t_loadRequested)
    {
        return false;
    }
    w3t_loadRequested = true;
    return true;
}

@addMethod(CR4Game)
function W3T_StartBot()
{
    if(!w3t_bot)
    {
        w3t_bot = new W3T_Bot in this;
        w3t_bot.Start();
    }
}

@wrapMethod(CR4StartupMoviesMenu)
function OnConfigUI()
{
    wrappedMethod();

    if(W3T_Active())
    {
        W3T_Log("MENU startup movies -> skip");
        CloseMenu();
    }
}

// The "story so far" recap (gamestart/recap_wip.usm, about 3 minutes) plays before the main menu.
@wrapMethod(CR4RecapMoviesMenu)
function OnConfigUI()
{
    wrappedMethod();

    if(W3T_Active())
    {
        W3T_Log("MENU recap movie -> skip");
        CloseMenu();
    }
}

// CDPR account / telemetry consent prompt: close it without signing in or answering consent questions
// (nothing is stored, so the owner still sees it on their own next launch).
@wrapMethod(CR4StartupExperienceMenu)
function OnConfigUI()
{
    wrappedMethod();

    if(W3T_Active())
    {
        W3T_Log("MENU startup experience (account/telemetry prompt) -> close without answering");
        CloseMenu();
    }
}

@wrapMethod(CR4MenuBase)
function OnConfigUI()
{
    wrappedMethod();

    if(W3T_Active())
    {
        W3T_Log("MENU open " + NameToString(GetMenuName()));
    }
}

// Logs every system dialog and answers it (OK / Yes) so nothing waits for a human.
@wrapMethod(CR4GuiManager)
function ShowProgressDialog( messageId : int, title : string, message : string, localizationNeeded:bool, type : EUserDialogButtons, progressValue:float, progressType:EUserMessageProgressType, progressTag:name)
{
    var text : string;

    wrappedMethod(messageId, title, message, localizationNeeded, type, progressValue, progressType, progressTag);

    if(!W3T_Active())
    {
        return;
    }

    if(localizationNeeded)
    {
        text = GetLocStringByKeyExt(title) + " | " + GetLocStringByKeyExt(message);
    }
    else
    {
        text = title + " | " + message;
    }
    W3T_Log("DIALOG id=" + messageId + " type=" + (int)type + " text=" + text);

    if(type == UDB_Ok || type == UDB_OkCancel)
    {
        UserDialogCallback(messageId, UMA_Ok);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered OK");
    }
    else if(type == UDB_YesNo)
    {
        UserDialogCallback(messageId, UMA_Yes);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered Yes");
    }
}

@wrapMethod(CR4CommonMainMenuBase)
function OnConfigUI()
{
    var saves : array<SSavegameInfo>;
    var wanted : string;
    var i : int;

    wrappedMethod();

    if(!W3T_Active() || !theGame.W3T_ClaimLoad())
    {
        return true;
    }

    wanted = W3T_GetEnv("W3T_SAVE");
    theGame.ListSavedGames(saves);
    W3T_Log("MENU main menu, saves=" + saves.Size() + " wanted='" + wanted + "'");

    if(wanted == "")
    {
        W3T_Log("LOAD newest save");
        theGame.LoadLastGameInit();
        return true;
    }

    for(i = 0; i < saves.Size(); i += 1)
    {
        if(StrFindFirst(saves[i].filename, wanted) >= 0)
        {
            W3T_Log("LOAD " + saves[i].filename);
            theGame.LoadGameInit(saves[i], false);
            return true;
        }
    }

    W3T_Log("FAIL no save matches '" + wanted + "'");
    W3T_Quit(3);
}

@wrapMethod(CR4Player)
function OnSpawned(spawnData : SEntitySpawnData)
{
    wrappedMethod(spawnData);

    if(W3T_Active())
    {
        W3T_SkipLoadingVideo("player spawned");
        theGame.W3T_StartBot();
    }
}

@wrapMethod(CR4Game)
function OnAfterLoadingScreenGameStart()
{
    wrappedMethod();

    if(W3T_Active())
    {
        W3T_Log("LOADING screen finished");
    }
}

// The recap video on the loading screen otherwise plays to the end before the world starts.
function W3T_SkipLoadingVideo(when : string)
{
    if(theGame.IsLoadingScreenVideoPlaying())
    {
        W3T_Log("LOADING video playing at " + when + " -> cancel");
        theGame.GetGuiManager().CancelFlashbackVideo();
    }
}

statemachine class W3T_Bot
{
    public var startMs : int;
    public var reports : int;

    // free-form scenario state
    public var scenarioVec : Vector;
    public var scenarioFlag : bool;
    public var scenarioTime : float;
    public var scenarioCount : int;

    public function Start()
    {
        startMs = W3T_TimeMs();
        W3T_Log("BOT start scenario=" + W3T_GetEnv("W3T_SCENARIO"));
        GotoState('W3T_Running');
    }

    public function ElapsedS() : float
    {
        return (W3T_TimeMs() - startMs) / 1000.0;
    }

    public var lastReportReal : float;
    public var lastReportGame : float;

    public function Report()
    {
        var line : string;
        var real : float;
        var game : float;
        var speed : float;

        // game seconds per real second: well below 1 means the engine runs at very low FPS
        real = ElapsedS();
        game = theGame.GetEngineTimeAsSeconds();
        if(real > lastReportReal && lastReportReal > 0)
        {
            speed = (game - lastReportGame) / (real - lastReportReal);
        }
        lastReportReal = real;
        lastReportGame = game;

        line = "STATE speed=" + FloatToStringPrec(speed, 2) + " t=" + FloatToStringPrec(ElapsedS(), 1)
            + " pos=" + W3T_VecStr(thePlayer.GetWorldPosition())
            + " area=" + NameToString(theGame.GetCommonMapManager().GetCurrentArea())
            + " hp=" + FloatToStringPrec(thePlayer.GetStat(BCS_Vitality), 0);
        W3T_Log(line);
        W3T_ReportExtra(this);
        reports += 1;
    }
}

state W3T_Running in W3T_Bot
{
    event OnEnterState(prevStateName : name)
    {
        RunLoop();
    }

    // Passes once the scenario condition holds for 3 reports in a row, then stays W3T_GRACE seconds so peers
    // can observe this instance too. Fails after W3T_DURATION seconds without a pass.
    entry function RunLoop()
    {
        var duration : float;
        var grace : float;
        var passedAt : float;
        var streak : int;

        duration = StringToFloat(W3T_GetEnv("W3T_DURATION"), 240.0);
        grace = StringToFloat(W3T_GetEnv("W3T_GRACE"), 20.0);
        passedAt = -1;

        while(true)
        {
            parent.Report();

            // keep stepping after a pass too: some scenarios act for their peers (e.g. the mover)
            if(W3T_ScenarioCheck(parent))
            {
                streak += 1;
            }
            else
            {
                streak = 0;
            }

            if(passedAt < 0)
            {
                if(streak >= 3)
                {
                    passedAt = parent.ElapsedS();
                    W3T_Log("PASS condition met at t=" + FloatToStringPrec(passedAt, 1));
                }
                else if(parent.ElapsedS() > duration)
                {
                    W3T_Log("FAIL condition not met within " + FloatToStringPrec(duration, 0) + " s");
                    W3T_Quit(1);
                }
            }
            else if(parent.ElapsedS() - passedAt > grace)
            {
                W3T_Log("BOT done after " + parent.reports + " reports");
                W3T_Quit(0);
            }

            Sleep(1.0);
        }
    }
}
