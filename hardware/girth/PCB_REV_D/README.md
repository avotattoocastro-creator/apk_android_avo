# AVO GIRTH · PCB REV D (cincha: ESP32-C6 + LSM6DSV16X + MMC5983MA + ADS1292)

Placa de 46 × 30 mm, 4 capas, generada desde Python (`fuente/`), ruteada en el CI (Freerouting 1.9) y completada con
`fuente/repair.py`. Comprobada en el CI con KiCad 9 (DRC, ERC y paridad).

- **Ficheros para JLCPCB:** `out/FINAL/` (Gerber zip, BOM, CPL, STEP, informe, SHA256SUMS).
- **Informe y decisiones:** `DOCS/INFORME_PCB_REV_D.md`. **Batería:** `DOCS/CONSUMO_BATERIA.md` (1000 mAh).
- **Firmware:** `firmware/girth/V0_6_0`.

Flujo:
1. `python3 fuente/place_revd.py` y después `python3 fuente/build.py`. Así se genera la placa de colocación.
2. El CI (`build-girth-pcb-revd.yml`) rutea y comprueba.
3. `python3 fuente/repair.py` completa las conexiones que falten y escribe `kicad/*_ruteado.kicad_pcb`, que el CI usa
   tal cual. Con `--src` se parte de otra placa y con `--rip` se rehacen redes.
4. `fuente/stitch_gnd.py --write` añade vías de cosido en las islas del relleno de F.Cu.

**Estado: VERIFICADO POR SOFTWARE · NO VERIFICADO EN HARDWARE REAL.**
