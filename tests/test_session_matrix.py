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
    # every per-entry setting is cleared from the environment of the runs it starts
    assert set(sm.SETTINGS) <= set(run_suite.GWENT_DUEL_SWITCHES)


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
