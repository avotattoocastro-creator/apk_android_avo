# AVO DOCK V1 · PCB REV A (15/11/2026)

**Estado:** generada por `fuente/` y comprobada en el CI con KiCad 9 (`.github/workflows/build-dock-v1-pcb.yml`). Ver el informe en `out/`. **No fabricada. No verificada en hardware.**

## Cómo se genera
```
cd fuente
python3 place_dock.py      # colocación → colocacion_dock.json y ../pcb_mecanica.json (lo lee el CAD)
python3 build.py           # placa de colocación + vías a planos, esquema, proyecto y piezas.json
```
En el CI se hace el ruteado (Freerouting 1.9.0), el relleno de zonas, el DRC con paridad y el ERC. Después viene la puerta de fabricación (`fuente/gate.py`). Solo si la supera se generan los Gerber, la BOM y el CPL de JLCPCB y el STEP en `out/FINAL/`.

## Placa
- 130 × 76 mm, esquinas R3, 4 capas, 1,6 mm, ENIG. Todos los componentes en la cara F.
- Capas: F.Cu e In2 de señal (In2 con relleno +3V3); In1 y B.Cu de GND macizo.
- **Zona de red** en (−65…−46, −12…38) con un **foso de 6,5 mm** sin cobre en ninguna capa. Las pistas de red (1,0 mm, F.Cu) las traza el generador.
- 4 taladros NPTH Ø3,2 para M3 de nailon.

Arquitectura, conexiones y pendientes: `../DOCS/ARQUITECTURA.md`.
