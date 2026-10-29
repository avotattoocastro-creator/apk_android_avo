"""Runs inside the KiCad 9 Docker image.
   python3 ci_route.py export board.kicad_pcb board.dsn      → Specctra DSN for Freerouting
   python3 ci_route.py import board.kicad_pcb board.ses out.kicad_pcb  → imports the routed session
"""
import sys

import pcbnew

mode = sys.argv[1]
board = pcbnew.LoadBoard(sys.argv[2])
if mode == "export":
    ok = pcbnew.ExportSpecctraDSN(board, sys.argv[3])
    print("DSN exportado:", ok)
    sys.exit(0 if ok else 1)
elif mode == "import":
    ok = pcbnew.ImportSpecctraSES(board, sys.argv[3])
    print("SES importado:", ok)
    # GND pours on the outer layers (left out of the DSN so Freerouting does not treat them as planes)
    base = [z for z in board.Zones() if z.GetNetname() == "GND" and z.GetLayer() == pcbnew.In1_Cu][0]
    for lay in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = base.Duplicate()
        try:
            z = z.Cast()
        except Exception as e:
            print("Cast:", e)
        z.SetLayer(lay)
        for fn, arg in (("SetPadConnection", pcbnew.ZONE_CONNECTION_THERMAL),
                        ("SetThermalReliefGap", pcbnew.FromMM(0.3)),
                        ("SetThermalReliefSpokeWidth", pcbnew.FromMM(0.3)),
                        ("SetLocalClearance", pcbnew.FromMM(0.2))):
            try:
                getattr(z, fn)(arg)
            except Exception as e:
                print(fn, e)
        board.Add(z)
    print("zonas GND exteriores añadidas")
    # +3V3 pour on In2 (In2 was a routing layer for Freerouting); it fills around the In2 tracks
    z = base.Duplicate()
    try:
        z = z.Cast()
    except Exception as e:
        print("Cast:", e)
    z.SetLayer(pcbnew.In2_Cu)
    z.SetNet(board.FindNet("+3V3"))
    board.Add(z)
    print("zona +3V3 en In2 añadida")
    # keep the fanouts we placed (locked) and everything Freerouting added
    pcbnew.SaveBoard(sys.argv[4], board)
    sys.exit(0 if ok else 1)
else:
    raise SystemExit("modo desconocido")
