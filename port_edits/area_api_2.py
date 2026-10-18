# Second half of the area port (anno.ws Chill Out block, map pins); area_api.py stopped at the Chill Out block.
import os

from edit_lib import SCRIPTS, edit


def edit_span(rel, start, end, new):
    path = os.path.join(SCRIPTS, rel)
    s = open(path, newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    i = s.index(start)
    j = s.index(end, i) + len(end)
    s = s[:i] + new.replace("\n", nl) + s[j:]
    open(path, "w", newline="").write(s)
    print(f"{rel}: replaced span starting {start!r}")


edit(r"local\anno.ws", [
    ("normalizeRegion(AreaTypeToName(players[i].area))", "normalizeRegion(WO_AreaCodeToRegion(players[i].area))"),
    ("normalizeRegion(AreaTypeToName(theGame.GetCommonMapManager().GetCurrentArea()))",
     "normalizeRegion(WO_AreaToRegion(theGame.GetCommonMapManager().GetCurrentArea()))"),
])

edit_span(r"local\anno.ws", "    var area: EAreaName;", "WO_Bob(this, m_groups);\n    }",
          """    var area: name;
    wrappedMethod();

    area = theGame.GetCommonMapManager().GetCurrentArea();

    if (area == 'AN_Prologue_Village' || area == 'AN_Prologue_Village_Winter') {
        WO_WhiteOrchard(this, m_groups);
    } else if (area == 'AN_Bob') {
        WO_Bob(this, m_groups);
    }""")

edit(r"sharedutils\mappins\map_pin.ws", [
    ("  var region: EAreaName;", "  var region: int; // old EAreaName code, see areaCompat.ws"),
    ("    _region: EAreaName,", "    _region: int,"),
])

edit(r"sharedutils\mappins\main.ws", [
    ("shown_area: EAreaName) {", "shown_area: name) {"),
    ("  var journal_area: int;\n", ""),
    ("normalizeRegion(AreaTypeToName(shown_area));", "normalizeRegion(WO_AreaToRegion(shown_area));"),
    ("  journal_area = theGame.GetCommonMapManager().GetCurrentJournalArea();\n", ""),
    ("normalizeRegion(AreaTypeToName(current_pin.region))", "normalizeRegion(WO_AreaCodeToRegion(current_pin.region))"),
    ('    flash_object.SetMemberFlashInt("journalAreaId", journal_area);',
     '    flash_object.SetMemberFlashUInt("journalAreaId", NameToFlashUInt(theGame.GetCommonMapManager().GetJournalAreaByPosition(shown_area, current_pin.position)));'),
])
