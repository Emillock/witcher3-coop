"""Tests for the harness's session matrix (session_matrix.py, run_test.py --matrix, run_suite.py), without the game."""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import run_suite  # noqa: E402
import run_test  # noqa: E402
import session_matrix as sm  # noqa: E402

LOG = """10:00:00.000 BOT start scenario=session
10:00:01.000 SCENARIO gwent_duel start entry=0
10:00:02.000 GwentDuel: DUEL END result=win reason=normal
10:00:03.000 PASS condition met at t=40.0 scenario=gwent_duel
10:00:04.000 SCENARIO gwent_duel cleaned up
10:00:04.100 SCENARIO gwent_duel start entry=1
10:00:05.000 FAIL gwent duel: money moved by 0, expected 10
10:00:05.100 SCENARIO gwent_duel failed
10:00:06.000 SCENARIO gwent_duel cleaned up
10:00:06.100 SCENARIO gwent_duel start entry=2
10:00:07.000 STATE speed=1.00
"""


def test_parse_matrix_defaults_and_values():
    entries = sm.parse_matrix([
        {"scenario": "gwent_duel", "env": {"W3T_GWENT_DECKS": "North,North", "W3T_GWENT_SEED": 12345}},
        {"scenario": "gwent_duel", "label": "short", "duration": 30},
    ])
    assert [(e.index, e.scenario, e.label) for e in entries] == [(0, "gwent_duel", "gwent_duel-1"), (1, "gwent_duel", "short")]
    assert entries[0].env == {"W3T_GWENT_DECKS": "North,North", "W3T_GWENT_SEED": "12345"}
    assert entries[0].duration is None and entries[1].duration == 30


@pytest.mark.parametrize("data, problem", [
    ([], "non-empty"),
    ({"scenario": "gwent_duel"}, "non-empty"),
    (["gwent_duel"], "not an object"),
    ([{"env": {}}], "scenario"),
    ([{"scenario": "a,b"}], "scenario"),
    ([{"scenario": "gwent_duel", "envs": {}}], "unknown keys"),
    ([{"scenario": "gwent_duel", "env": {"W3T_DOCUMENTS": "x"}}], "not a per-entry setting"),
    ([{"scenario": "gwent_duel", "env": {"W3T_GWENT_SEED": 1.5}}], "string or an integer"),
    ([{"scenario": "gwent_duel", "env": {"W3T_GWENT_SEED": True}}], "string or an integer"),
    ([{"scenario": "gwent_duel", "env": {"W3T_GWENT_DECKS": "a\nW3T_GWENT_SEED=2"}}], "one line"),
    ([{"scenario": "gwent_duel", "env": {"W3T_GWENT_DECKS": "a|W3T_GWENT_SEED=2"}}], "without '\\|'"),
    ([{"scenario": "gwent_duel", "label": "has space"}], "label"),
    ([{"scenario": "gwent_duel", "label": "x"}, {"scenario": "gwent_duel", "label": "x"}], "twice"),
    ([{"scenario": "gwent_duel", "duration": 0}], "duration"),
])
def test_parse_matrix_rejects(data, problem):
    with pytest.raises(ValueError, match=problem):
        sm.parse_matrix(data)


def test_load_matrix(tmp_path):
    path = tmp_path / "m.json"
    path.write_text(json.dumps([{"scenario": "gwent_duel"}]), encoding="utf-8")
    assert sm.load_matrix(str(path))[0].label == "gwent_duel-1"
    path.write_text("[", encoding="utf-8")
    with pytest.raises(ValueError, match="not JSON"):
        sm.load_matrix(str(path))


def test_entry_settings_fall_back_to_the_environment_then_empty():
    entry = sm.parse_matrix([{"scenario": "gwent_duel", "env": {"W3T_GWENT_SEED": "7"}}])[0]
    settings = sm.entry_settings(entry, {"W3T_GWENT_SEED": "1", "W3T_GWENT_BET": "20", "W3T_OTHER": "x"})
    assert settings["W3T_GWENT_SEED"] == "7"
    assert settings["W3T_GWENT_BET"] == "20"
    assert settings["W3T_GWENT_CORRUPT_AT"] == ""
    assert set(settings) == set(sm.SETTINGS)


def test_control_text_carries_every_bot_setting_and_no_harness_one():
    settings = dict.fromkeys(sm.SETTINGS, "")
    settings.update(W3T_GWENT_DECKS="a+b,c+d", W3T_GWENT_LOGDIFF="report")
    lines = sm.control_text(3, settings).splitlines()
    assert lines[0] == "go 3"
    assert "W3T_GWENT_DECKS=a+b,c+d" in lines
    assert "W3T_GWENT_CORRUPT_AT=" in lines
    assert len(lines) == 1 + len(sm.ENTRY_SETTINGS)
    assert not any(line.startswith("W3T_GWENT_LOGDIFF") for line in lines)


def test_write_control_replaces_the_file(tmp_path):
    path = str(tmp_path / "control.txt")
    sm.write_control(path, "go 0\n")
    sm.write_control(path, sm.END_CONTROL)
    assert open(path, encoding="utf-8").read() == "end"
    assert not os.path.exists(path + ".tmp")


def test_cut_entry():
    first = sm.cut_entry(LOG, 0, "gwent_duel")
    assert first.startswith("10:00:01.000 SCENARIO gwent_duel start entry=0")
    assert "DUEL END result=win" in first and "cleaned up" in first and "entry=1" not in first
    second = sm.cut_entry(LOG, 1, "gwent_duel")
    assert "FAIL gwent duel" in second and "DUEL END" not in second and "entry=2" not in second
    assert sm.cut_entry(LOG, 2, "gwent_duel").endswith("STATE speed=1.00\n")
    assert sm.cut_entry(LOG, 3, "gwent_duel") == ""
    assert sm.cut_entry(LOG, 0, "gwent_vanilla") == ""


def test_entry_state():
    passed, failed = sm.cut_entry(LOG, 0, "gwent_duel"), sm.cut_entry(LOG, 1, "gwent_duel")
    running = sm.cut_entry(LOG, 2, "gwent_duel")
    assert sm.entry_state([passed, passed], "gwent_duel", 5, 600) == "decided"
    assert sm.entry_state([passed, failed], "gwent_duel", 5, 600) == "decided"
    assert sm.entry_state([passed, running], "gwent_duel", 5, 600) == "running"
    assert sm.entry_state([passed, running], "gwent_duel", 601, 600) == "hung"
    assert sm.entry_state([passed, ""], "gwent_duel", 5, 600) == "running"
    # a pass of another scenario does not count
    assert sm.entry_state([passed.replace("scenario=gwent_duel", "scenario=gwent_duelx")], "gwent_duel", 5, 600) == "running"


@pytest.mark.parametrize("decided, end, start", [
    (3, "done", None),        # every entry decided
    (1, "hung", 1),           # the hung entry was recorded as failed: go on with the next in fresh games
    (1, "exited", 1),
    (0, "exited", 0),
    (1, "done", 1),           # the games ended without being told to
    (1, "owner", None),       # the owner's Documents changed: stop
    (1, "timeout", None),     # the run's own timeout
])
def test_next_launch(decided, end, start):
    assert sm.next_launch(decided, 3, end) == start


def test_bot_settings_expand_decks_and_seed():
    entry = sm.parse_matrix([{"scenario": "gwent_duel", "env": {"W3T_GWENT_DECKS": "plain_nr,North",
                                                                 "W3T_GWENT_SEED": "4000000000"}}])[0]
    settings = run_test.bot_settings(entry, {})
    assert settings["W3T_GWENT_DECKS"].split(",")[1] == "North"
    assert "+" in settings["W3T_GWENT_DECKS"].split(",")[0]
    assert settings["W3T_GWENT_SEED"] == str(4000000000 - 2 ** 32)
    assert run_test.bot_settings(sm.parse_matrix([{"scenario": "gwent_duel"}])[0], {})["W3T_GWENT_DECKS"] == ""


def test_results_agree_from_texts():
    win, loss = "x DUEL END result=win reason=normal\n", "x DUEL END result=loss reason=normal\n"
    assert run_test.gwent_results_agree_texts([win, loss])[0]
    assert not run_test.gwent_results_agree_texts([win, win])[0]
    assert not run_test.gwent_results_agree_texts([win, ""])[0]


def test_window_mode():
    assert run_test.window_mode("", 0, 0) == "minimized"
    assert run_test.window_mode("", 2, 0) == "noactivate"
    assert run_test.window_mode("", 0, 60) == "noactivate"
    assert run_test.window_mode("noactivate", 0, 0) == "noactivate"


def test_suite_matrix_file_matches_the_matrix():
    data = run_suite.matrix_entries(run_suite.GWENT_DUEL_MATRIX)
    entries = sm.parse_matrix(data)
    assert [e.label for e in entries] == [name for name, _ in run_suite.GWENT_DUEL_MATRIX]
    assert all(e.scenario == "gwent_duel" for e in entries)
    assert entries[0].env == run_suite.GWENT_DUEL_MATRIX[0][1]
    # only the switches some entry sets are cleared from the environment of the runs it starts (as before Task 13b)
    assert run_suite.GWENT_DUEL_SWITCHES == ["W3T_GWENT_CORRUPT_AT", "W3T_GWENT_DECKS", "W3T_GWENT_EXIT_AT",
                                             "W3T_GWENT_EXPECT", "W3T_GWENT_FORCE_DRAW", "W3T_GWENT_IDLE_AT",
                                             "W3T_GWENT_IDLE_SEAT", "W3T_GWENT_LEADER_FIRST", "W3T_GWENT_MULLIGAN",
                                             "W3T_GWENT_REASON", "W3T_GWENT_REPLAY", "W3T_GWENT_SEED",
                                             "W3T_GWENT_SURRENDER_AT", "W3T_GWENT_TIMED"]


def test_suite_matrix_quits_a_game_only_in_its_last_entry() -> None:
    """W3T_GWENT_EXIT_AT ends a game: its entry runs last, so the duels before it share the launch."""
    exits = [i for i, (_, settings) in enumerate(run_suite.GWENT_DUEL_MATRIX) if "W3T_GWENT_EXIT_AT" in settings]
    assert exits == [len(run_suite.GWENT_DUEL_MATRIX) - 1]
    name, settings = run_suite.GWENT_DUEL_MATRIX[-1]
    assert settings["W3T_GWENT_EXPECT"] == "nocontest" and settings["W3T_GWENT_REASON"] == "opponent_left"
    idle = [s for _, s in run_suite.GWENT_DUEL_MATRIX if s.get("W3T_GWENT_IDLE_AT", "").isdigit()]
    assert idle and all(s["W3T_GWENT_REASON"] == "stuck_wait" and "W3T_GWENT_TIMED" not in s for s in idle)
    at_end = [s for _, s in run_suite.GWENT_DUEL_MATRIX if s.get("W3T_GWENT_IDLE_AT") == "end"]
    assert at_end and all(s["W3T_GWENT_FORCE_DRAW"] == "1" and s["W3T_GWENT_REPLAY"] == "0" for s in at_end)


def test_exit_and_idle_are_per_entry_settings_the_bots_read() -> None:
    """W3T_GWENT_EXIT_AT and W3T_GWENT_IDLE_AT go to the bots in the control file (an empty value clears it)."""
    assert "W3T_GWENT_EXIT_AT" in sm.ENTRY_SETTINGS and "W3T_GWENT_IDLE_AT" in sm.ENTRY_SETTINGS
    text = sm.control_text(3, {"W3T_GWENT_EXIT_AT": "6"})
    assert text.splitlines()[0] == "go 3"
    assert "W3T_GWENT_EXIT_AT=6" in text.splitlines() and "W3T_GWENT_IDLE_AT=" in text.splitlines()


def test_idle_seat_is_a_per_entry_setting_the_bots_read() -> None:
    """R55: W3T_GWENT_IDLE_SEAT goes to the bots in the control file like W3T_GWENT_IDLE_AT."""
    assert "W3T_GWENT_IDLE_SEAT" in sm.ENTRY_SETTINGS and "W3T_GWENT_IDLE_SEAT" not in sm.HARNESS_SETTINGS
    lines = sm.control_text(5, {"W3T_GWENT_IDLE_SEAT": "B"}).splitlines()
    assert lines[0] == "go 5" and "W3T_GWENT_IDLE_SEAT=B" in lines
    assert "W3T_GWENT_IDLE_SEAT=" in sm.control_text(6, {}).splitlines()


def test_suite_matrix_has_the_timed_duels() -> None:
    """R55: a Timed duel whose seat B never acts (A must win, B lose, the bet moves: the verdict's default) and a Timed
    duel both play; Timed is never combined with W3T_GWENT_IDLE_AT, and the idle seat's entry expects a result."""
    timed = {name: s for name, s in run_suite.GWENT_DUEL_MATRIX if s.get("W3T_GWENT_TIMED") == "1"}
    idle = [s for s in timed.values() if s.get("W3T_GWENT_IDLE_SEAT") == "B"]
    played = [s for s in timed.values() if "W3T_GWENT_IDLE_SEAT" not in s]
    assert len(idle) == 1 and played
    assert all("W3T_GWENT_IDLE_AT" not in s for s in timed.values())
    assert all(s.get("W3T_GWENT_EXPECT", "result") == "result" for s in timed.values())
    seats = [s["W3T_GWENT_IDLE_SEAT"] for _, s in run_suite.GWENT_DUEL_MATRIX if "W3T_GWENT_IDLE_SEAT" in s]
    assert set(seats) <= {"A", "B"}


def test_planned_exit_only_for_bot_1_quitting_on_purpose() -> None:
    """A game that ends during an entry is a planned exit only for bot 1, rc 0, with EXIT_AT and its exit line."""
    settings = {"W3T_GWENT_EXIT_AT": "6"}
    start = "10:00:00.000 SCENARIO gwent_duel start entry=4\n"
    part = start + "10:00:30.000 GWENT exit (board sent seq 6): quits the game\n"
    assert sm.planned_exit(settings, 1, 0, part)
    assert not sm.planned_exit(settings, 0, 0, part)            # bot 0 never quits on purpose
    assert not sm.planned_exit(settings, 1, 3221225477, part)   # a crash is a crash
    assert not sm.planned_exit(settings, 1, 0, start)
    assert not sm.planned_exit({"W3T_GWENT_EXIT_AT": ""}, 1, 0, part)


def test_results_fit_when_bot_1_quit_its_game() -> None:
    """W3T_GWENT_EXIT_AT: bot 1 has no DUEL END (it quit mid-match); bot 0 must end as no contest."""
    left = "x GwentDuel: DUEL END result=nocontest reason=opponent_left game=0\n"
    assert run_test.gwent_results_agree_texts([left, "x GWENT exit (board sent seq 6): quits the game\n"], True)[0]
    win = "x GwentDuel: DUEL END result=win reason=match game=0\n"
    assert not run_test.gwent_results_agree_texts([win, ""], True)[0]
    assert not run_test.gwent_results_agree_texts([left, ""], False)[0]
    assert not run_test.gwent_results_agree_texts([left, left], True)[0]


def test_suite_env_keeps_suite_wide_settings():
    env = run_suite.suite_env({"W3T_GWENT_LOGDIFF": "report", "W3T_GWENT_BET": "20", "W3T_GWENT_SEED": "7",
                               "W3T_GWENT_DECKS": "North,North", "PATH": "x"})
    assert env == {"W3T_GWENT_LOGDIFF": "report", "W3T_GWENT_BET": "20", "PATH": "x"}
    # and a session entry then takes them as its defaults
    entry = sm.parse_matrix(run_suite.matrix_entries(run_suite.GWENT_DUEL_MATRIX[:1]))[0]
    settings = sm.entry_settings(entry, env)
    assert settings["W3T_GWENT_BET"] == "20" and settings["W3T_GWENT_LOGDIFF"] == "report"
    assert settings["W3T_GWENT_SEED"] == "1"


def test_entry_started_and_one_retry():
    assert not sm.entry_started(["", ""])
    assert sm.entry_started(["", "x SCENARIO gwent_duel start entry=2\n"])
    retried = set()
    assert sm.retry_unstarted(2, retried)
    assert not sm.retry_unstarted(2, retried)
    assert sm.retry_unstarted(3, retried)
    # an unstarted entry has no result, so the next launch starts with it again
    assert sm.next_launch(2, 4, "unstarted") == 2


def test_focus_watch_drops_destroyed_windows():
    import time

    import w3run
    watch = w3run.FocusWatch(every=0.05)
    pid = 0x7FFFFFF0  # no such process
    watch.add(pid, "BotA")
    with watch.lock:
        watch.windows[pid] = 0x7FFFFFF4  # no such window: IsIconic would say "not minimized"
    watch.start()
    time.sleep(0.4)
    watch.stop()
    assert watch.polls > 0
    assert "BotA" not in watch.minimized and "BotA" not in watch.shown
    assert pid not in watch.windows


def duel_log(seat_result: str, before: int, after: int, extra: str = "") -> str:
    return ("10:00:00.000 SCENARIO gwent_duel start entry=0\n"
            f"10:00:01.000 GwentDuel: DUEL END result={seat_result} reason=match game=0\n"
            f"10:00:02.000 GWENT duel money before={before} after={after} bet=10\n" + extra)


@pytest.fixture
def judged(tmp_path, monkeypatch):
    """A MatrixRun of two gwent_duel entries (a normal one and a corrupt check) whose logdiff step is stubbed."""
    entries = sm.parse_matrix([
        {"scenario": "gwent_duel", "label": "normal", "env": {"W3T_GWENT_DECKS": "North,North"}},
        {"scenario": "gwent_duel", "label": "corrupt", "env": {"W3T_GWENT_CORRUPT_AT": "8"}},
    ])
    matrix = run_test.MatrixRun(entries, {}, str(tmp_path), 2)
    outcome = {"rc": 0, "text": "OK: 3 + 3 applied messages and 2 rounds agree"}
    calls = []

    def fake_logdiff(paths):
        calls.append(paths)
        return outcome["rc"], outcome["text"]

    monkeypatch.setattr(run_test, "gwent_logdiff_files", fake_logdiff)
    return matrix, outcome, calls, tmp_path


def test_judge_pass_writes_the_parts(judged):
    matrix, _, calls, root = judged
    logs = {0: duel_log("win", 382, 392), 1: duel_log("loss", 382, 372)}
    assert matrix.judge(0, logs, True, "every bot passed 'gwent_duel'") == (True, "every bot passed 'gwent_duel'")
    folder = root / "entries" / "01-normal"
    assert (folder / "BotA.log").read_text(encoding="utf-8") == logs[0]
    assert [os.path.basename(p) for p in calls[0]] == ["BotA.log", "BotB.log"]


def test_judge_keeps_a_bot_failure(judged):
    matrix, _, _, _ = judged
    logs = {0: duel_log("win", 382, 392), 1: duel_log("loss", 382, 382, "x FAIL gwent duel: money moved by 0\n")}
    assert matrix.judge(0, logs, False, "BotB: gwent duel: money moved by 0") == (False, "BotB: gwent duel: money moved by 0")


def test_judge_fails_on_divergence_and_on_results_that_do_not_fit(judged):
    matrix, outcome, _, _ = judged
    outcome.update(rc=1, text="DIVERGED at seq=5: A to B: ...")
    ok, why = matrix.judge(0, {0: duel_log("win", 382, 392), 1: duel_log("loss", 382, 372)}, True, "passed")
    assert not ok and why.startswith("duel logs diverged: DIVERGED at seq=5")
    outcome.update(rc=0, text="OK")
    ok, why = matrix.judge(0, {0: duel_log("win", 382, 392), 1: duel_log("win", 382, 392)}, True, "passed")
    assert not ok and "do not fit together" in why


def test_judge_corrupt_entry_expects_its_seq(judged):
    matrix, outcome, _, _ = judged
    outcome.update(rc=1, text="DIVERGED at seq=8: A to B: ...")
    logs = {0: duel_log("nocontest", 382, 382), 1: duel_log("nocontest", 382, 382)}
    assert matrix.judge(1, logs, True, "passed") == (True, "passed")
    outcome.update(rc=1, text="DIVERGED at seq=9: A to B: ...")
    ok, why = matrix.judge(1, logs, True, "passed")
    assert not ok and "W3T_GWENT_CORRUPT_AT" in why


def test_logdiff_verdict_for_a_corrupt_end_message():
    """W3T_GWENT_CORRUPT_AT=end: the first divergence must be at an end of game message (E), whatever its seq."""
    at_end = "DIVERGED at seq=41: B to A: sender hash 0000aaaa, receiver mine=0000bbbb (1.3039g0.41.E.A.0000aaaa)"
    assert run_test.gwent_logdiff_verdict(1, at_end, "end")[0]
    ok, why = run_test.gwent_logdiff_verdict(1, "DIVERGED at seq=8: A to B: sender hash 1, receiver mine=2 "
                                                "(1.3039g0.8.S._.00000001)", "end")
    assert not ok and "W3T_GWENT_CORRUPT_AT=end" in why
    assert not run_test.gwent_logdiff_verdict(0, "OK: 40 + 40 applied messages and 3 rounds agree", "end")[0]


def test_judge_hung_entry_stays_failed(judged):
    matrix, _, _, root = judged
    why = "not decided within 50 s: BotA: no pass (did not finish); BotB: no pass (did not finish)"
    logs = {0: "10:00:00.000 SCENARIO gwent_duel start entry=0\n", 1: ""}
    assert matrix.judge(0, logs, False, why) == (False, why)
    assert (root / "entries" / "01-normal" / "BotB.log").read_text(encoding="utf-8") == ""


def test_suite_reads_session_results():
    text = ("RESULT a-s1: PASS (every bot passed 'gwent_duel') [120s]\n"
            "RESULT b-s2: FAIL (not decided within 60 s: BotA: no pass (did not finish)) [61s]\n")
    rows = run_suite.session_rows(text, ["a-s1", "b-s2", "c-s3"], "gwent_duel ")
    assert rows == [("gwent_duel a-s1", "PASS", 120, "every bot passed 'gwent_duel'"),
                    ("gwent_duel b-s2", "FAIL", 61, "not decided within 60 s: BotA: no pass (did not finish)"),
                    ("gwent_duel c-s3", "ERROR", 0, "no result line")]


def test_focus_summary():
    import w3run
    watch = w3run.FocusWatch()
    watch.polls = 10
    watch.minimized = {"BotA": [8, 10]}
    watch.shown = {"BotA": [["12:00:00.1", "12:00:00.2", 0.0], ["12:10:00.0", "12:10:00.0", 0.0]]}
    text = watch.summary()
    assert "a game window was the foreground window 0 times" in text
    assert "BotA 8/10 samples" in text
    assert "BotA 12:00:00.1 to 12:00:00.2, 12:10:00.0 to 12:10:00.0" in text
    watch.foreground = [("12:00:01", "BotB", "W2ViewportClass")]
    assert "foreground window 1 times (first 12:00:01 BotB W2ViewportClass)" in watch.summary()
