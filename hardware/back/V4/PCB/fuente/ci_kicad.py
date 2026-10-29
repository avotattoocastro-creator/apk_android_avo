"""Runs inside the official KiCad 9 Docker image (GitHub Actions): fills the zones with KiCad's own filler,
saves the board, and writes a JSON summary of the board (pads, nets, zones) for the report."""
import json
import sys

import pcbnew

src, dst = sys.argv[1], sys.argv[2]
board = pcbnew.LoadBoard(src)
filler = pcbnew.ZONE_FILLER(board)
zones = board.Zones()
filler.Fill(zones)
pcbnew.SaveBoard(dst, board)

info = {"zones": [], "footprints": len(board.GetFootprints()), "tracks": 0, "vias": 0,
        "unconnected": None}
for z in zones:
    info["zones"].append({"net": z.GetNetname(), "layer": board.GetLayerName(z.GetFirstLayer()),
                          "filled_area_mm2": round(z.GetFilledArea() / 1e12, 1)})
for t in board.GetTracks():
    if t.GetClass() == "PCB_VIA":
        info["vias"] += 1
    else:
        info["tracks"] += 1
try:
    board.BuildConnectivity()
    info["unconnected"] = board.GetConnectivity().GetUnconnectedCount(True)
except Exception as e:  # API differences between versions
    info["unconnected_error"] = str(e)
json.dump(info, open(dst + ".info.json", "w"), indent=1)
print(json.dumps(info, indent=1))
