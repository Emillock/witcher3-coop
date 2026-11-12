"""Tests for the scene input table (scene_inputs.py) against the game's own scenes."""
import os
import sys

import pytest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import scene_inputs  # noqa: E402
from config import GAME  # noqa: E402

BUNDLES = os.path.join(GAME, "content", "content0", "bundles")
# the game's own debug scene (vanilla's PlayMovieScene plays it with "Input"), and a quest scene whose second
# input is named by hand - the case a game cannot guess and this table exists for
MOVIE = r"movies\cutscenes\movie_player.w2scene"
QUEST = (r"quests\part_2\quest_files\q206_berserkers\scenes"
         r"\q206_05_h01_02e_gp_geralt_on_massacre_corpse.w2scene")

pytestmark = pytest.mark.skipif(not os.path.isdir(BUNDLES), reason="no game bundles to read")


def inputs_for(path: str) -> list[str]:
    from pathlib import Path

    import bundle

    for name in ("blob.bundle", "startup.bundle", "bob.bundle", "ep1.bundle"):
        try:
            data = bundle.extract(Path(BUNDLES) / name, path)
        except Exception:
            continue
        return scene_inputs.inputs_of(data)
    pytest.skip(f"{path} is in none of the bundles read")


def test_default_input_is_named_and_marked_cinematic():
    """A scene whose input has no name of its own uses the editor's default, and this one is a cutscene."""
    assert inputs_for(MOVIE) == ["Input*"]


def test_named_input_comes_out_of_the_resource():
    """The q206 oneliner has the default input and a named one; the named one cannot be guessed."""
    found = inputs_for(QUEST)
    assert [i.rstrip("*") for i in found] == ["Input", "in_first_body"]


def test_cinematic_marks_only_cinematic_sections():
    """A gameplay section is not marked: the q206 inputs lead into sections with isGameplay set."""
    assert not any(i.endswith("*") for i in inputs_for(QUEST))


def test_text_of_reads_both_string_forms():
    assert scene_inputs.text_of(bytes([0x80 | 5]) + b"hello") == "hello"
    assert scene_inputs.text_of(bytes([5]) + "hi".encode("utf-16-le")) == "hi"
    assert scene_inputs.text_of(b"") == ""
