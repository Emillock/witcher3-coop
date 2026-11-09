"""Session entries with their own settings, for run_test.py --matrix.

A matrix file is JSON: a list of entries, each {"scenario": NAME, "label": TEXT, "env": {SETTING: VALUE, ...},
"duration": SECONDS}; only "scenario" is required. The entries run one after another in shared game launches. The
harness tells the bots which entry to run through the session's control file: its first line is "go N" (start entry
N) or "end", and the lines after "go N" are that entry's settings as NAME=VALUE (an empty value clears it). The bots
apply them right before the entry starts, so the process-start environment only gives the defaults.

Everything here is independent of the game, so it can be tested without one.
"""
import json
import os
import re
import time
from dataclasses import dataclass

# per-entry settings the bots read (sent in the control file)
ENTRY_SETTINGS = ("W3T_GWENT_DECKS", "W3T_GWENT_SEED", "W3T_GWENT_MULLIGAN", "W3T_GWENT_LEADER_FIRST",
                  "W3T_GWENT_CORRUPT_AT", "W3T_GWENT_BREAK_TEMPLATES", "W3T_GWENT_EXPECT", "W3T_GWENT_REASON",
                  "W3T_GWENT_BET", "W3T_GWENT_TIMED", "W3T_GWENT_FORCE_DRAW", "W3T_GWENT_REPLAY",
                  "W3T_GWENT_SURRENDER_AT", "W3T_GWENT_EXIT_AT", "W3T_GWENT_IDLE_AT", "W3T_GWENT_IDLE_SEAT",
                  "W3T_GWENT_NO_BOARD")
# per-entry settings only the harness reads (never sent to the bots)
HARNESS_SETTINGS = ("W3T_GWENT_LOGDIFF",)
SETTINGS = ENTRY_SETTINGS + HARNESS_SETTINGS
ENTRY_KEYS = ("scenario", "label", "env", "duration")
END_CONTROL = "end"
LABEL_RE = re.compile(r"^[A-Za-z0-9_.,+-]+$")

# how a launch ended (run_test.launch): the run goes on in fresh games after "hung", "exited" and "unstarted"
STOP_ENDS = ("owner", "timeout")


@dataclass(frozen=True)
class Entry:
    """One matrix entry: a scenario run with its own settings."""
    index: int
    scenario: str
    label: str
    env: dict
    duration: int | None


def parse_matrix(data: object) -> list[Entry]:
    """The entries of a decoded matrix file; raises ValueError naming the first problem."""
    if not isinstance(data, list) or not data:
        raise ValueError("a matrix is a non-empty JSON list of entries")
    entries, labels = [], set()
    for index, raw in enumerate(data):
        where = f"entry {index + 1}"
        if not isinstance(raw, dict):
            raise ValueError(f"{where}: not an object")
        unknown = sorted(set(raw) - set(ENTRY_KEYS))
        if unknown:
            raise ValueError(f"{where}: unknown keys {unknown} (known: {', '.join(ENTRY_KEYS)})")
        scenario = raw.get("scenario")
        if not isinstance(scenario, str) or not LABEL_RE.match(scenario) or "," in scenario:
            raise ValueError(f"{where}: 'scenario' must be a scenario name")
        label = raw.get("label", f"{scenario}-{index + 1}")
        if not isinstance(label, str) or not LABEL_RE.match(label):
            raise ValueError(f"{where}: label {label!r} must be letters, digits and _.,+- only")
        if label in labels:
            raise ValueError(f"{where}: label {label!r} is used twice")
        labels.add(label)
        env = raw.get("env", {})
        if not isinstance(env, dict):
            raise ValueError(f"{where}: 'env' must be an object")
        values = {}
        for name, value in env.items():
            if name not in SETTINGS:
                raise ValueError(f"{where}: {name} is not a per-entry setting (known: {', '.join(SETTINGS)})")
            if isinstance(value, bool) or not isinstance(value, (str, int)):
                raise ValueError(f"{where}: {name} must be a string or an integer")
            text = str(value)
            if "\n" in text or "\r" in text or "|" in text:
                # the bots get the control file's lines joined by "|" (w3test.asi's W3T_ReadLines)
                raise ValueError(f"{where}: {name} must be one line without '|'")
            values[name] = text
        duration = raw.get("duration")
        if duration is not None and (isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0):
            raise ValueError(f"{where}: 'duration' must be a positive number of seconds")
        entries.append(Entry(index, scenario, label, values, duration))
    return entries


def load_matrix(path: str) -> list[Entry]:
    """The entries of the matrix file at path (see parse_matrix)."""
    with open(path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"{path}: not JSON ({e})") from e
    return parse_matrix(data)


def entry_settings(entry: Entry, base_env: dict) -> dict[str, str]:
    """Every per-entry setting for this entry: its own value, else the process environment's (the default), else
    empty. Empty values are kept, so the bots clear what an earlier entry set."""
    return {name: entry.env.get(name, base_env.get(name, "")) for name in SETTINGS}


def control_text(index: int, settings: dict[str, str]) -> str:
    """The control file that starts entry `index` with these settings (only the ones the bots read)."""
    lines = [f"go {index}"] + [f"{name}={settings.get(name, '')}" for name in ENTRY_SETTINGS]
    return "\n".join(lines) + "\n"


def write_control(path: str, text: str, attempts: int = 100) -> None:
    """Replaces the control file in one step (a bot reading it sees the old or the new text, never a part); retries
    while a bot has it open."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    for attempt in range(attempts):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            if attempt + 1 == attempts:
                raise
            time.sleep(0.05)


def entry_marker(index: int, scenario: str) -> str:
    """The bot's log line (after its time stamp) where entry `index` starts."""
    return f"SCENARIO {scenario} start entry={index}"


NEXT_START_RE = re.compile(r"^\S+ SCENARIO \S+ start\b", re.M)


def cut_entry(log: str, index: int, scenario: str) -> str:
    """A session log's part for entry `index`: from its start line to the next entry's start line (or the end);
    empty if the entry has not started."""
    marker = re.search(r"^\S+ " + re.escape(entry_marker(index, scenario)) + r"$", log, re.M)
    if not marker:
        return ""
    following = NEXT_START_RE.search(log, marker.end())
    return log[marker.start():following.start() if following else len(log)]


def pass_re(scenario: str) -> re.Pattern:
    """A bot's pass line for this scenario."""
    return re.compile(rf"PASS condition met at t=\S+ scenario={re.escape(scenario)}(\s|$)")


def failed_marker(scenario: str) -> str:
    """The line a bot logs in a session when its verdict for this scenario failed and it goes on (W3T_FailScenario)."""
    return f"SCENARIO {scenario} failed"


def entry_state(segments: list[str], scenario: str, elapsed: float, limit: float) -> str:
    """Where an entry stands from every bot's log part: "decided" once each bot passed or reported its failure,
    "hung" when that did not happen within `limit` seconds, else "running"."""
    pattern = pass_re(scenario)
    if all(pattern.search(s) or failed_marker(scenario) in s for s in segments):
        return "decided"
    return "hung" if elapsed > limit else "running"


# the line bot 1 logs right before it quits its game on purpose (W3T_GWENT_EXIT_AT, w3test_gwent.ws)
EXIT_MARKER = "GWENT exit (board sent seq "
# the bot that quits with W3T_GWENT_EXIT_AT (the guest, bot 1)
EXIT_BOT = 1


def planned_exit(settings: dict[str, str], bot: int, rc: int, segment: str) -> bool:
    """Whether a game that ended during an entry quit on purpose: the entry sets W3T_GWENT_EXIT_AT, it is bot 1's game,
    it ended with exit code 0, and its log part says it quits (EXIT_MARKER)."""
    return bool(settings.get("W3T_GWENT_EXIT_AT")) and bot == EXIT_BOT and rc == 0 and EXIT_MARKER in segment


def entry_started(segments: list[str]) -> bool:
    """Whether some bot started the entry (its log part, from cut_entry, is not empty)."""
    return any(segments)


def retry_unstarted(index: int, retried: set[int]) -> bool:
    """Whether entry `index`, which never started in the last launch, gets one more try in fresh games: once only.
    Records the try in `retried`."""
    if index in retried:
        return False
    retried.add(index)
    return True


def next_launch(decided: int, total: int, end: str) -> int | None:
    """The entry the next launch starts with after a launch that ended with `end` (see run_test.launch) and
    `decided` entries decided so far, or None when the run is over: every entry decided, or a stop (the owner's
    Documents changed, the run's own timeout). A failed entry is never retried; an entry that never started is
    still undecided after its launch ("unstarted"), so the next launch starts with it again."""
    if decided >= total or end in STOP_ENDS:
        return None
    return decided
