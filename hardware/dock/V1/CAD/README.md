# AVO DOCK V1 · caja (CadQuery 2.4)

`avo_dock_v1.py` genera en `out/`:
- `AVO_DOCK_V1_fondo.step/.stl`
- `AVO_DOCK_V1_frente.step/.stl`
- `AVO_DOCK_V1_CONJUNTO.step`, con las referencias: PCB, componentes, cápsulas, pogos, imanes y pantalla
- `informe.json`

Lee `../PCB/pcb_mecanica.json` (taladros, USB-C y envolventes), así que caja y PCB salen siempre del mismo dato. Se ejecuta en el CI (`.github/workflows/build-dock-v1-cad.yml`).

Impresión en PETG en la Centauri Carbon: el frente boca abajo (cara frontal sobre la cama) y el fondo con la placa trasera sobre la cama, los dos sin soportes salvo los ojales. Medidas y tornillería en `../DOCS/ARQUITECTURA.md`.
