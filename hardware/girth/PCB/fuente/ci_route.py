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
    # keep the fanouts we placed (locked) and everything Freerouting added
    pcbnew.SaveBoard(sys.argv[4], board)
    sys.exit(0 if ok else 1)
else:
    raise SystemExit("modo desconocido")
