# Ports Witcher Online's area handling to the Remastered (5.x) name-based area API.
from edit_lib import edit

edit(r"local\remotePlayer.ws", [
    ("public var area     : EAreaName;", "public var area     : int; // old EAreaName code, see areaCompat.ws"),
])

edit(r"local\client.ws", [
    ("private var partyTargetLastKnownArea : EAreaName;", "private var partyTargetLastKnownArea : int;"),
    ("        var currentArea : EAreaName;\n", "        var currentArea : int;\n"),
])
edit(r"local\client.ws", [
    ("currentArea = theGame.GetCommonMapManager().GetCurrentArea();", "currentArea = WO_CurrentAreaCode();"),
], count_all=True)
edit(r"local\client.ws", [
    ("list += theGame.GetCommonMapManager().GetCurrentArea();", "list += WO_CurrentAreaCode();"),
    ("if(players[i].area == theGame.GetCommonMapManager().GetCurrentArea())", "if(players[i].area == WO_CurrentAreaCode())"),
    ("GetWorldPathFromAreaType(players[i].area)", "GetWorldPathFromAreaType(WO_AreaFromCode(players[i].area))"),
    ("normalizeRegion(AreaTypeToName(players[i].area))", "normalizeRegion(WO_AreaCodeToRegion(players[i].area))"),
    ("normalizeRegion(AreaTypeToName(theGame.GetCommonMapManager().GetCurrentArea()))",
     "normalizeRegion(WO_AreaToRegion(theGame.GetCommonMapManager().GetCurrentArea()))"),
])

edit(r"local\anno.ws", [
    ("normalizeRegion(AreaTypeToName(players[i].area))", "normalizeRegion(WO_AreaCodeToRegion(players[i].area))"),
    ("normalizeRegion(AreaTypeToName(theGame.GetCommonMapManager().GetCurrentArea()))",
     "normalizeRegion(WO_AreaToRegion(theGame.GetCommonMapManager().GetCurrentArea()))"),
    ("""    var area: EAreaName;
    wrappedMethod();

    area = CO_CurrentArea();

    if (area == AN_NMLandNovigrad) {

    } else if (area == AN_Skellige_ArdSkellig) {

    } else if (area == AN_Kaer_Morhen) {

    } else if (area == AN_Prologue_Village) {
        WO_WhiteOrchard(this, m_groups);
    } else if (area == AN_Prologue_Village_Winter) {
        WO_WhiteOrchard(this, m_groups);
    } else if (area == AN_Wyzima) {

    } else if (area == (int) AN_Dlc_Bob) {
        WO_Bob(this, m_groups);
    }""",
     """    var area: name;
    wrappedMethod();

    area = theGame.GetCommonMapManager().GetCurrentArea();

    if (area == 'AN_Prologue_Village' || area == 'AN_Prologue_Village_Winter') {
        WO_WhiteOrchard(this, m_groups);
    } else if (area == 'AN_Bob') {
        WO_Bob(this, m_groups);
    }"""),
])

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
