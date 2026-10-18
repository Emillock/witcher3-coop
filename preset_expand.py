# Expands a user_config_matrix preset (e.g. graphics.xml "low") into concrete {group: {var: value}} settings.
# Usage: preset_expand.py <graphics.xml> <preset id>
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict


def expand_preset(graphics_xml, preset_id):
    root = ET.parse(graphics_xml).getroot()
    group_default = root.find("Group").get("id")
    options = {}
    for var in root.iter("Var"):
        opts = {o.get("id"): [(e.get("overrideGroup"), e.get("varId"), e.get("value")) for e in o.iter("Entry")]
                for o in var.iter("Option")}
        options[var.get("id")] = (var.get("overrideGroup"), opts)

    out = OrderedDict()
    for preset in root.iter("Preset"):
        if preset.get("id") != preset_id:
            continue
        for e in preset.iter("Entry"):
            group, var, value = e.get("overrideGroup") or group_default, e.get("varId"), e.get("value")
            if var.startswith("Virtual_"):
                for g, v, val in options.get(var, (None, {}))[1].get(value, []):
                    out.setdefault(g or group, OrderedDict())[v] = val
            else:
                out.setdefault(group, OrderedDict())[var] = value
    return out


if __name__ == "__main__":
    for g, pairs in expand_preset(sys.argv[1], sys.argv[2]).items():
        for v, val in pairs.items():
            print(f"{g}\t{v}\t{val}")
