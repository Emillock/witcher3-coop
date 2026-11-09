"""Source checks of the in-game Gwent bot (w3test/modW3Test/.../w3test_gwent.ws), without the game."""
import os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GWENT_WS = os.path.join(HERE, "w3test", "modW3Test", "content", "scripts", "local", "w3test_gwent.ws")


def source() -> str:
    """The bot's Gwent script."""
    with open(GWENT_WS, encoding="utf-8") as f:
        return f.read()


def block(text: str, start: str) -> str:
    """The text from `start` to the end of its brace block."""
    at = text.index(start)
    depth = 0
    for index in range(text.index("{", at), len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[at:index + 1]
    raise AssertionError(f"unbalanced braces after {start}")


def test_vanilla_match_fails_on_duel_lines() -> None:
    """R62: gwent_vanilla fails when the board logged any duel line outside a duel (the self-test's own lines aside)."""
    text = source()
    line = block(text, "public function DuelLine(")
    assert 'if(!duel && StrStartsWith(line, "DUEL ") && !StrStartsWith(line, "DUEL SELFTEST"))' in line
    assert "vanillaDuelLines += 1" in line
    match = block(text, "function W3T_GwentMatch(")
    check = match.index("if(!withSelfTest && gwent.vanillaDuelLines > 0)")
    assert match.index('if(gwent.result == "")') < check < match.index("FAIL single-player match logged duel lines: ")
    assert check < match.index("return true;")


def test_no_board_duel_ends_the_vanilla_match_and_checks_both_reasons() -> None:
    """W3T_GWENT_NO_BOARD: bot 1's board runs as the vanilla board, the bot ends that match as a win, and the verdict
    wants reason board there and hello_timeout on bot 0."""
    text = source()
    assert 'noBoard = !host && W3T_GetEnv("W3T_GWENT_NO_BOARD") == "1";' in text
    assert "manager.duelDebugNoBoard = noBoard;" in text
    assert text.count("manager.duelDebugNoBoard = false;") == 2
    poll = block(text, "public function Poll(")
    assert poll.index("duel && noBoard && boardOpen && !noBoardEnded") < poll.index("menu.W3T_EndAsWin()")
    end = block(text, "function W3T_EndAsWin()")
    assert end.index("OnMatchResult(true)") < end.index("CloseMenu()")
    verdict = block(text, "public function DuelVerdict(")
    assert 'host && reason != "hello_timeout"' in verdict and '!host && reason != "board"' in verdict
