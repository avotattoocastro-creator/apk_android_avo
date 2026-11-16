# AVO DOCK V1 · PCB REV A (15/11/2026)

**Estado:** diseño verificado por software en el CI con KiCad 9 (ejecución 43789462892):
- DRC: 0 errores y 0 conexiones incompletas;
- paridad esquema ↔ placa: 0;
- ERC: 0/0;
- puerta superada.

Los ficheros de fabricación están en `out/FINAL/`. **No fabricada. No verificada en hardware.**

**Ruteado:** Freerouting 1.9.0 de la ejecución 43788505774. Se guarda tal cual en `kicad/AVO_DOCK_V1_PCB_ruteado.kicad_pcb` y el CI lo reutiliza sin volver a rutear. Si cambia la colocación, hay que borrar ese fichero.

## Cómo se genera
```
cd fuente
python3 place_dock.py      # colocación → colocacion_dock.json y ../pcb_mecanica.json (lo lee el CAD)
python3 build.py           # placa de colocación + vías a planos, esquema, proyecto y piezas.json
```
En el CI se hace el ruteado (Freerouting 1.9.0), el relleno de zonas, el DRC con paridad y el ERC. Después viene la puerta de fabricación (`fuente/gate.py`). Solo si la supera se generan los Gerber, la BOM y el CPL de JLCPCB y el STEP en `out/FINAL/`.

## Placa
- 130 × 76 mm, esquinas R3, 4 capas, 1,6 mm, ENIG. Todos los componentes en la cara F.
- Capas: F.Cu y B.Cu de señal (con relleno GND tras el ruteado); In1 = plano GND; In2 = plano +3V3 (vía desde cada pad).
- **Zona de red** en (−65…−46, −12…38) con un **foso de 6,5 mm** sin cobre en ninguna capa. Las pistas de red (1,0 mm, F.Cu) las traza el generador.
- 4 taladros NPTH Ø3,2 para M3 de nailon.

Arquitectura, conexiones y pendientes: `../DOCS/ARQUITECTURA.md`.
