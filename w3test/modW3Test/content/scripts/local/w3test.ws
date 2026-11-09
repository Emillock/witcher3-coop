// In-game test bot. Does nothing unless the W3T_SCENARIO environment variable is set.
// Env: W3T_SCENARIO (name), W3T_SAVE (part of a save filename; newest save if empty), W3T_DURATION (seconds in game).
// A session runs several scenarios in one game: W3T_SCENARIOS (comma-separated) and W3T_CONTROL, a file in which the
// harness writes "go N" (start scenario N) or "end". Lines after "go N" are scenario N's own settings, NAME=VALUE (an
// empty value clears it; run_test.py --matrix): the bot sets them in its environment right before scenario N starts,
// so W3T_GetEnv returns them from then on.

import function W3T_GetEnv(key : string) : string;
import function W3T_SetEnv(assignment : string);
import function W3T_Log(line : string);
import function W3T_TimeMs() : int;
import function W3T_ReadFile(path : string) : string;
import function W3T_ReadLines(path : string) : string;
import function W3T_Quit(code : int);

function W3T_Active() : bool
{
    return W3T_GetEnv("W3T_SCENARIO") != "";
}

function W3T_Split(text : string, separator : string) : array<string>
{
    var parts : array<string>;
    var left, right : string;

    while(text != "")
    {
        if(!StrSplitFirst(text, separator, left, right))
        {
            parts.PushBack(text);
            break;
        }
        parts.PushBack(left);
        text = right;
    }
    return parts;
}

// the session's control file, line by line (W3T_ReadLines joins them with "|": splitting the file's text at "\n" or
// at StrChar(10) found no line break in game)
function W3T_SessionControl() : array<string>
{
    return W3T_Split(W3T_ReadLines(W3T_GetEnv("W3T_CONTROL")), "|");
}

// the harness's word in a session (the control file's first line): N for "go N", -2 for "end", -1 for nothing yet
function W3T_SessionGoOf(control : array<string>) : int
{
    var words : array<string>;

    if(control.Size() == 0)
    {
        return -1;
    }
    words = W3T_Split(control[0], " ");
    if(words.Size() >= 1 && words[0] == "end")
    {
        return -2;
    }
    if(words.Size() >= 2 && words[0] == "go")
    {
        return StringToInt(words[1], -1);
    }
    return -1;
}

function W3T_SessionGo() : int
{
    return W3T_SessionGoOf(W3T_SessionControl());
}

// the settings after "go N": this scenario's own, set in the environment before it starts
function W3T_ApplySessionSettings(control : array<string>)
{
    var i : int;

    for(i = 1; i < control.Size(); i += 1)
    {
        if(StrFindFirst(control[i], "=") > 0)
        {
            W3T_SetEnv(control[i]);
            W3T_Log("SESSION setting " + control[i]);
        }
    }
}

// a scenario's verdict failed. Alone the bot quits (W3T_Quit(1)), as before; in a session it logs the failure and
// goes on, so the harness can start the next scenario in the same game.
function W3T_FailScenario(why : string)
{
    W3T_Log("FAIL " + why);
    if(W3T_GetEnv("W3T_SCENARIOS") == "")
    {
        W3T_Quit(1);
        return;
    }
    W3T_Log("SCENARIO " + W3T_CurrentScenario() + " failed");
}

// the scenario running now (in a session too)
function W3T_CurrentScenario() : string
{
    if(theGame.w3t_bot)
    {
        return theGame.w3t_bot.scenario;
    }
    return W3T_GetEnv("W3T_SCENARIO");
}

function W3T_VecStr(v : Vector) : string
{
    return FloatToStringPrec(v.X, 2) + "," + FloatToStringPrec(v.Y, 2) + "," + FloatToStringPrec(v.Z, 2);
}

@addField(CR4Game)
var w3t_bot : W3T_Bot;

@addField(CR4Game)
var w3t_loadRequested : bool;

// voicesets played on monsters here, and the last one (W3T_NoteVoiceset)
@addField(CR4Game)
var w3t_voices : int;

@addField(CR4Game)
var w3t_lastVoice : string;

@addMethod(CR4Game)
function W3T_NoteVoiceset(who : string, voiceSet : string)
{
    w3t_voices += 1;
    w3t_lastVoice = who + ":" + voiceSet;
}

// The task every growl and battle cry goes through. Its Main is latent and cannot be wrapped, so this counts the
// moment the behaviour tree asks whether it may run: on the leader that happens for its own monsters, on a member
// it should not happen for a copy at all (its AI is suppressed).
@wrapMethod(CBTTaskPlayVoiceSet)
function IsAvailable() : bool
{
    if(GetActor())
    {
        theGame.W3T_NoteVoiceset(GetActor().GetReadableName(), voiceSet);
    }
    return wrappedMethod();
}

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
    else
    {
        w3t_bot.Resume();
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
        // the trade's price slider (Witcher Online's r_TradeWindow): 10 crowns, as a player would set and confirm
        if(GetMenuName() == 'PopupMenu' && W3T_CurrentScenario() == "trade")
        {
            W3T_Log("MENU trade price -> 10 crowns");
            theGame.r_getMultiplayerClient().setTradeAmount(10);
            CloseMenu();
        }
        // it pauses the game, the bot's loop too: respawn as its button does (loads the last save)
        if(GetMenuName() == 'DeathScreenMenu')
        {
            W3T_Log("MENU death screen -> respawn from the last save");
            theGame.SetIsRespawningInLastCheckpoint();
            theGame.LoadLastGameInit(true);
        }
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

    if(theGame.w3t_bot)
    {
        theGame.w3t_bot.CountDialog();
    }
    if(type == UDB_Ok || type == UDB_OkCancel)
    {
        UserDialogCallback(messageId, UMA_Ok);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered OK");
    }
    else if(type == UDB_YesNo && messageId == W3CoopTradeMessageId() && W3T_CurrentScenario() != "trade")
    {
        // W3Coop's offer to trade with a party member: only the trade scenario takes it, the rest go on to the
        // party question behind it
        UserDialogCallback(messageId, UMA_No);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered No");
    }
    else if(type == UDB_YesNo && messageId == W3CoopWaitMessageId() && W3T_CurrentScenario() != "cutscene_wait")
    {
        // W3Coop's offer to wait for a party member's cutscene: taking it holds the bot still, which every other
        // scenario reads as a bot that stopped working
        UserDialogCallback(messageId, UMA_No);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered No");
    }
    else if(type == UDB_YesNo && messageId == W3CoopTravelMessageId() && W3T_CurrentScenario() != "follow_travel")
    {
        // W3Coop's offer to follow the leader: only follow_travel takes it (other tests move the bots themselves)
        UserDialogCallback(messageId, UMA_No);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered No");
    }
    else if(type == UDB_YesNo && messageId == W3CoopTravelMessageId() && W3T_GetEnv("W3T_HOLD_DIALOG") != "")
    {
        // for screenshots of it; the dialog pauses the game, the bot's loop too, so the run doesn't get further
        W3T_Log("DIALOG left open (W3T_HOLD_DIALOG)");
    }
    else if(type == UDB_YesNo)
    {
        UserDialogCallback(messageId, UMA_Yes);
        HideUserDialog(messageId);
        W3T_Log("DIALOG answered Yes");
    }
}

// Witcher Online's trade popups (trade): the seller picks the Dwarven spirit, the buyer accepts the offer; and its
// Gwent challenge popup (gwent_duel): the challenged bot accepts
@wrapMethod(CR4ItemSelectionPopup)
function OnConfigUI()
{
    var ids : array<SItemUniqueId>;

    wrappedMethod();
    if(W3T_Active() && W3T_CurrentScenario() == "gwent_duel" && m_DataObject.wo_isReceivingGwent)
    {
        // accepted on the scenario's next step: Witcher Online marks the request as shown only after this popup opened,
        // and acceptGwentRequest does nothing before that. Its OnCallSelectItem accepts whatever item is picked.
        W3T_Log("MENU gwent: " + m_DataObject.wo_toGwent + " challenges for " + m_DataObject.wo_betAmount + " crowns -> accept");
        theGame.W3T_GwentState().ChallengeShown(this);
        return true;
    }
    if(!W3T_Active() || W3T_CurrentScenario() != "trade")
    {
        return true;
    }
    if(m_DataObject.wo_isTrade)
    {
        ids = thePlayer.inv.GetItemsByName('Dwarven spirit');
        W3T_Log("MENU trade: offers " + ids.Size() + " Dwarven spirit(s), picks one");
        if(ids.Size() > 0)
        {
            OnCallSelectItem(ids[0]);
        }
    }
    else if(m_DataObject.wo_isReceivingTrade)
    {
        ids = m_DataObject.targetInventory.GetItemsByName('Dwarven spirit');
        W3T_Log("MENU trade: offered " + ids.Size() + " Dwarven spirit for " + m_DataObject.wo_crownsAmount + " crowns -> accept");
        if(ids.Size() > 0)
        {
            OnCallSelectItem(ids[0]);
        }
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
    public var scenarioEntity : CEntity;
    public var scenarioEntities : array<CEntity>;
    public var scenarioStep : int;       // a fighting bot's moves
    public var scenarioActAt : float;    // when it last moved
    public var scenarioSeenAt : float;   // when it last saw an enemy
    public var scenarioFarSince : float; // since when its target has been out of reach
    public var scenarioPos : Vector;     // where it stood when it last moved (stuck checks)
    public var scenarioValue : float;
    public var dialogsAnswered : int;    // system dialogs this bot answered (party_invite checks one was asked)
    public var scenarioName : name;
    public var scenarioText : string;
    public var scenarioPhase : int;      // which part of a scenario measured in parts is running
    public var scenarioMark : int;       // the counter value the open watch window belongs to
    public var scenarioUntil : float;    // when that window closes (0: none open)
    public var scenarioWindows : int;    // windows closed
    public var scenarioHeard : int;      // ...with a sound active in them
    public var scenarioOnsetHits : int;  // ...with a new sound starting in them
    public var scenarioOnsets : int;     // new sounds in all
    public var scenarioWasOn : bool;     // whether it was sounding on the last tick
    public var scenarioWindowOn : bool;
    public var scenarioWindowOnset : bool;
    public var scenarioBones : array<int>;  // ticks each watched bone sounded on (W3T_SoundBones)
    public var scenarioHitAnims : int;   // hits of ours the victim answered with a hit animation
    public var scenarioAnimUntil : float;

    public var scenario : string;        // the one running (empty in a session until the harness says go)
    public var scenarioIndex : int;      // its place in the session
    public var settleUntil : float;      // after a switch: let the last scenario's monsters go first
    public var begun : bool;             // the session's scenario has started after settling
    public var home : Vector;            // where the save put the player, and its facing; each session scenario starts there
    public var homeRot : EulerAngles;
    public var homeSet : bool;

    public function Start()
    {
        startMs = W3T_TimeMs();
        scenarioIndex = -1;
        if(W3T_GetEnv("W3T_SCENARIOS") == "")
        {
            scenario = W3T_GetEnv("W3T_SCENARIO");
            scenarioIndex = 0;
            begun = true;
        }
        W3T_Log("BOT start scenario=" + W3T_GetEnv("W3T_SCENARIO"));
        GotoState('W3T_Running');
    }

    // after a save was loaded (member_death) its loop may have gone with the old world: it runs on, scenario state kept
    public function Resume()
    {
        if(ElapsedS() - lastReportReal < 3)
        {
            return;
        }
        W3T_Log("BOT resumes after a load");
        if(GetCurrentStateName() == 'W3T_Running')
        {
            GotoState('W3T_RunningAgain');
        }
        else
        {
            GotoState('W3T_Running');
        }
    }

    // a session's next scenario: the last one's leftovers go, the free-form state and the Gwent state start over, and
    // the scenario's own settings from the control file apply. The start line comes first, so the harness's cut of
    // this scenario's log holds its reset and settings lines too.
    public function NextScenario(index : int, next : string, control : array<string>)
    {
        if(scenario != "")
        {
            W3T_EndScenario(this);
        }
        W3T_Log("SCENARIO " + next + " start entry=" + index);
        theGame.W3T_ResetGwent();
        W3T_ApplySessionSettings(control);
        scenarioVec = Vector(0, 0, 0);
        scenarioFlag = false;
        scenarioTime = 0;
        scenarioCount = 0;
        scenarioEntity = NULL;
        scenarioEntities.Clear();
        scenarioStep = 0;
        scenarioActAt = 0;
        scenarioSeenAt = 0;
        scenarioFarSince = 0;
        scenarioPos = Vector(0, 0, 0);
        scenarioValue = 0;
        scenarioName = '';
        scenarioText = "";
        scenarioPhase = 0;
        scenarioMark = 0;
        scenarioUntil = 0;
        scenarioWindows = 0;
        scenarioHeard = 0;
        scenarioOnsetHits = 0;
        scenarioOnsets = 0;
        scenarioWasOn = false;
        scenarioWindowOn = false;
        scenarioWindowOnset = false;
        scenarioBones.Clear();
        scenarioHitAnims = 0;
        scenarioAnimUntil = 0;
        scenarioIndex = index;
        scenario = next;
        settleUntil = ElapsedS() + 5;
        begun = false;
    }

    public function CountDialog()
    {
        dialogsAnswered += 1;
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
    // can observe this instance too. Fails after W3T_DURATION seconds without a pass. In a session the harness
    // decides when to go on (and when a scenario failed); this game only reports.
    entry function RunLoop()
    {
        var duration : float;
        var grace : float;
        var passedAt : float;
        var startedAt : float;
        var streak : int;
        var session : array<string>;
        var control : array<string>;
        var go : int;

        duration = StringToFloat(W3T_GetEnv("W3T_DURATION"), 240.0);
        grace = StringToFloat(W3T_GetEnv("W3T_GRACE"), 20.0);
        session = W3T_Split(W3T_GetEnv("W3T_SCENARIOS"), ",");
        passedAt = -1;

        while(true)
        {
            parent.Report();

            // a tutorial hint pauses the game until closed; the sandbox turns them off, this closes any that still shows
            if(theGame.GetTutorialSystem() && theGame.GetTutorialSystem().HasActiveTutorial())
            {
                theGame.GetTutorialSystem().HideTutorialHint('', true);
                W3T_Log("HINT closed a tutorial hint");
            }

            // the player is at 0,0,0 until the save has placed it, some seconds after the bot starts
            if(!parent.homeSet && VecLengthSquared(thePlayer.GetWorldPosition()) > 1)
            {
                parent.home = thePlayer.GetWorldPosition();
                parent.homeRot = thePlayer.GetWorldRotation();
                parent.homeSet = true;
            }

            if(session.Size() > 0)
            {
                // one read: the word and the settings come from the same version of the file
                control = W3T_SessionControl();
                go = W3T_SessionGoOf(control);
                if(go == -2)
                {
                    W3T_Log("BOT session done after " + parent.reports + " reports");
                    W3T_Quit(0);
                }
                if(go >= 0 && go < session.Size() && go != parent.scenarioIndex)
                {
                    parent.NextScenario(go, session[go], control);
                    startedAt = parent.ElapsedS();
                    passedAt = -1;
                    streak = 0;
                }
            }

            // keep stepping after a pass too: some scenarios act for their peers (e.g. the mover)
            if(parent.scenario != "" && parent.ElapsedS() >= parent.settleUntil)
            {
                if(!parent.begun)
                {
                    W3T_BeginScenario(parent);
                    parent.begun = true;
                }
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
                        W3T_Log("PASS condition met at t=" + FloatToStringPrec(passedAt, 1) + " scenario=" + parent.scenario);
                    }
                    else if(session.Size() == 0 && parent.ElapsedS() - startedAt > duration)
                    {
                        W3T_Log("FAIL condition not met within " + FloatToStringPrec(duration, 0) + " s");
                        W3T_Quit(1);
                    }
                }
                else if(session.Size() == 0 && parent.ElapsedS() - passedAt > grace)
                {
                    W3T_Log("BOT done after " + parent.reports + " reports");
                    W3T_Quit(0);
                }
            }

            // W3T_TICK: shorter steps for scenarios that act, like the showcase's fights
            Sleep(StringToFloat(W3T_GetEnv("W3T_TICK"), 1.0));
        }
    }
}

// the same loop, entered again after a load (W3T_Bot.Resume)
state W3T_RunningAgain in W3T_Bot extends W3T_Running
{
}
