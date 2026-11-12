# AVO GIRTH PCB REV B · Informe de validación virtual

| | |
|---|---|
| Objeto | PCB de la cincha REV B: ESP32-C3-MINI-1U-N4, LSM6DS3TR-C + MMC5983MA, BQ51013B + BQ24072, RT9080-33, LiPo 500 mAh, encendido magnético con MOSFET (Q10/Q11), Qi, ESP-NOW, 4 capas, 65,5 × 43,5 mm |
| Referencia auditada | rama `feature/avo-girth-pcb`, commit `2a703697abf613d9128fc1a258e179d274a839ee` (ficheros entregados en `hardware/girth/PCB/out/C3/`) |
| Firmware auditado | `firmware/girth/V0_3_0_C3` |
| Rama de auditoría | `audit/avo-girth-pcb-revb`, derivada de `feature/avo-girth-pcb`. No se ha tocado `main` ni `feature/avo-girth-pcb`, y los ficheros entregados de `out/C3/` no se han modificado |
| Evidencias | `hardware/girth/PCB/AUDITORIA_REV_B/` y, generadas por el CI, `AUDITORIA_REV_B/resultados_ci/` (flujo `.github/workflows/audit-girth-revb.yml`) |
| Fecha | 2026-10-29 |
| Pedidos | **Ninguno.** No se ha hecho ningún pedido ni pago |

**Veredicto (detalle en la sección 15): APTO PARA PROTOTIPOS CON RIESGOS IDENTIFICADOS.** Recomendación: fabricar la
**REV B.1** que propone esta auditoría (sección 13). Se ha generado sin mover ninguna pieza y supera ERC, DRC y la
comparación esquema ↔ placa. Cambia el modo del cargador al que pide el receptor Qi y refuerza el enclavamiento de la
batería.

Este informe **no declara el diseño validado al 100 %**. Queda **PENDIENTE DE VALIDACIÓN FÍSICA** (sección 14) todo lo
que depende de:
- la radio,
- la bobina Qi real,
- la mecánica real,
- la temperatura,
- la celda real.

Una primera versión de este informe pasó por una revisión independiente (un agente que no había hecho el trabajo y lo
contrastó con las evidencias). Encontró 17 problemas: valores mal copiados, resultados presentados como más firmes de lo
que eran y etiquetas de verificación incorrectas. Todos están corregidos en esta versión.

---

## 0. Niveles de verificación y cómo reproducir

| Nivel | Significado |
|---|---|
| **VERIFICADO MEDIANTE HERRAMIENTA** | Lo comprueba un programa (KiCad 9, ngspice, compilador, pruebas automáticas, QEMU, API de JLCPCB) y su salida original está guardada |
| **VERIFICADO POR CÁLCULO** | Ecuación del fabricante con los valores del diseño, en un script del repositorio o desarrollada en este informe |
| **SIMULADO** | ngspice con los modelos indicados; vale lo que valen los modelos (sus límites se dicen en cada caso) |
| **REVISADO DOCUMENTALMENTE** | Contrastado con la hoja de datos, la documentación oficial o el código fuente, sin herramienta ni cálculo |
| **PENDIENTE DE VALIDACIÓN FÍSICA** | Solo se puede confirmar con la placa montada |
| **NO VERIFICADO** | No se ha podido comprobar con los medios disponibles |

Cuando una fila combina dos niveles (p. ej. «SIMULADO + PENDIENTE DE VALIDACIÓN FÍSICA»), la primera parte es lo que
se ha hecho y la segunda lo que falta.

**CI de la auditoría.** Cada ejecución sustituye `resultados_ci/` por sus evidencias con un commit `[skip ci]`.
`resultados_ci/ORIGEN.txt` dice de qué commit y de qué ejecución son las que hay en la rama. Las cifras de este informe
salen de esa última ejecución (o de las anteriores que se indican, con resultados idénticos en lo que no cambió):

| Commit | Run | Qué añadió |
|---|---|---|
| 82b9609 | 40938084601 | primera ejecución completa (KiCad, firmware, pruebas) |
| d6a9b30 | 40938632678 | fabricación, GPIO, autonomía, cajetín |
| 05eab4e | 40941766181 | Qi y mecánica; la simulación aún fallaba (sección 3.1) |
| fabea5b | 40945369456 | SPICE estable, REV B.1 en KiCad, Monte Carlo de 200 casos |
| 6bc101d | 40947060573 | eFuse de QEMU v0.3 |
| 73bc658 | 40948659105 | DRC tras rellenar las zonas con pcbnew; QEMU con boceto mínimo de control |
| 36196af | 40950416060 | pila de GDB en QEMU |
| 7be067a | 40952218397 | REV B.1 con C41/R40 y su SPICE |
| b582bed | 40955158865 | C41 = C47339 comprobada en JLCPCB (evidencias actuales de `resultados_ci/`) |

**Reproducir:** los comandos de cada fase están en `audit-girth-revb.yml`. Los scripts aceptan una carpeta de salida,
por ejemplo `MC_N=200 python3 spice/sim_revb.py salida/` o `AVO_SPICE_VALORES="C41=470n,R40=100k" …` para una variante.

**Herramientas que no se pudieron usar y alternativa empleada**

| Herramienta | Problema | Alternativa |
|---|---|---|
| KiCad en el entorno de trabajo | sin Docker local | imagen oficial `kicad/kicad:9.0` en el CI (GitHub Actions) |
| `kicad-cli pcb drc --refill-zones` | no existe en KiCad 9 («Unknown argument») | rellenador de zonas de pcbnew (`fuente/ci_kicad.py`) y DRC después |
| ngspice por `apt` en local | sin acceso a los repositorios de Ubuntu | ngspice-42 compilado desde el código fuente (misma versión que el CI) para iterar; las cifras son las del CI |
| QEMU de Espressif en local | faltan `libslirp`/`libSDL2` y no se pueden instalar | solo en el CI |
| API de JLCPCB en local | el proxy la bloquea (403) | consulta desde el CI (`fuente/stock_jlc.py`) |
| PDF de TI, AOS y Mouser | el proxy bloquea las descargas | visor de documentos de ti.com, réplicas (chipdip) y clon de ESP-IDF por git |
| Modelos SPICE oficiales de AOS y del RT9080 | requieren registro o no están publicados | modelos de nivel 1 ajustados a la hoja de datos y modelo de comportamiento (sección 2.1) |
| Registros del CI | el proxy bloquea el almacenamiento de registros de GitHub | todas las salidas se guardan como ficheros en `resultados_ci/` |

---

## 1. Fase 1 · KiCad (ERC, DRC, paridad, redes, Gerber)

**Comandos** (`resultados_ci/kicad/comandos_y_salida.txt`):
- `kicad-cli sch erc` y `kicad-cli pcb drc --schematic-parity --severity-all`;
- relleno de zonas con pcbnew y DRC otra vez;
- `kicad-cli sch export netlist`;
- `kicad_audit.py` (pcbnew);
- exportación de Gerber y taladros, y comparación con `comparar_gerber.py`.

| Comprobación | Resultado | Nivel | Evidencia (`resultados_ci/…`) |
|---|---|---|---|
| Ficheros auditados = entregados | SHA-256 de la entrada guardados | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/sha256_entrada.txt` |
| ERC | **0 errores, 0 avisos** | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/erc.rpt`, `erc.json` |
| DRC con paridad esquema ↔ placa | **0 violaciones, 0 pads sin conectar, 0 errores de huella** | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/drc.rpt`, `drc.json` |
| DRC tras rellenar las zonas otra vez | **0 / 0 / 0**; el relleno con pcbnew da 0 elementos sin conectar (898 pistas, 164 vías) | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/relleno_zonas.txt`, `kicad/drc_zonas_rellenadas_de_nuevo.rpt` |
| Cortocircuitos | ninguno (el DRC no tiene ninguna violación, tampoco de cortocircuito) | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/drc.json` |
| Esquema ↔ placa pad a pad | **0 diferencias.** El netlist del esquema tiene 327 pines y la placa 330 números de pad distintos. Los 3 de más son pads **sin número**, sin conexión eléctrica: ventanas de pasta de los EPAD de U1 y U2 y taladros NPTH de J1 | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/auditoria_placa.json`, `kicad/netlist_esquema.net` |
| Auditoría red a red | 84 redes; tabla con pads, longitud y anchos de cada red | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/auditoria_redes.csv` |
| Pistas, vías y planos | 164 vías, todas de 0,5/0,3 mm (anillo de 0,1 mm). Zonas GND en F.Cu (1520 mm²), In1 (2199 mm²) y B.Cu (2119 mm²); +3V3 en In2 (1943 mm²) | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/auditoria_placa.json` |
| Reglas | pista mín. 0,1, separación 0,1, vía 0,45, taladro 0,3, borde 0,3 mm | VERIFICADO MEDIANTE HERRAMIENTA (valores) + REVISADO DOCUMENTALMENTE (capacidades de JLCPCB para 4 capas) | `kicad/auditoria_placa.json` |
| Contorno | 65,5 × 43,5 mm (puntos D01/D02 del Gerber); 65,6 × 43,6 contando el ancho de línea de 0,1 mm | VERIFICADO MEDIANTE HERRAMIENTA | `fabricacion/fab_check.json`, `kicad/auditoria_placa.json` |
| Grosor y capas | 1,0 mm, 4 capas de cobre | VERIFICADO MEDIANTE HERRAMIENTA | idem |
| Gerber entregados = placa entregada | los 16 ficheros son **iguales** a los regenerados (sin contar las fechas) | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/comparacion_gerber.txt` |
| Todo es REV B | serigrafía «AVO GIRTH · REV B · ESP32-C3»; U4 = ESP32-C3-MINI-1U-N4 | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/auditoria_placa.json` |
| **Revisión del cajetín** | **dice «A»**, así que los Gerber llevan `TF.ProjectId …,A` y el `gbrjob` `"Revision": "A"` (P-9) | VERIFICADO MEDIANTE HERRAMIENTA | `kicad/auditoria_placa.json` |

---

## 2. Fase 2 · Alimentación (ngspice)

### 2.1 Modelos y sus límites

| Pieza | Modelo | Límite |
|---|---|---|
| BAV70 (D10–D13) | **oficial de Nexperia** | — |
| AO3400A (Q11), AO3401A (Q10), 2N7002 (Q16) | nivel 1, con VTO y KP **ajustados** a VGS(th) a 250 µA y a RDS(on) de la hoja; Cgs/Cgd y diodo de cuerpo | sin conducción por debajo del umbral, así que los tiempos de mantenimiento salen **conservadores**; sin fuga IDSS (sección 3.3); límites de hoja a 25 °C (el frío sube VGS(th) y no está simulado) |
| RT9080-33 (U3) | de comportamiento: salida ≈ min(3,3 V; Vin − Rdo·I), con Rdo sacado de la caída a 600 mA (0,52/0,88 Ω) | sin la dinámica del lazo (sobreimpulsos) |
| BQ24072 | camino BAT→OUT de 0,05/0,10 Ω (VDO de TI); con 5 V, fuente de 4,4 V | no modela el cargador ni el DPPM |
| ESP32-C3 | carga de comportamiento: 60 mA al arrancar, 82 mA en RX, ráfagas de 350 mA (2 ms cada 10 ms), 20 µA en sueño; no consume por debajo del brownout (2,51 V); pone PWR_HOLD **0,5 s** después de tener alimentación (supuesto, sin medir) | no es un modelo de Espressif |
| Celda | fuente + resistencia interna de 0,2/0,3 Ω | sin curva de descarga ni circuito de protección |
| Condensadores cerámicos | capacidad reducida por la polarización (factor 0,45–0,85) | sin ESR ni inductancia |

El netlist **se genera de la fuente de diseño** (`fuente/avo_girth_pcb.py`), no se copia a mano (`spice/sim_revb.py`).
Ficheros: `resultados_ci/spice/*.cir` (netlists), `*.log`, `*.png`, `resultados.json` y `salida.txt`.

### 2.2 Resultados

La 3V3 mínima se mide **después de t = 1 s**, ya en funcionamiento con ráfagas de TX. El encendido y el arranque quedan
fuera de esa ventana y se tratan en la sección 3.

| Caso | 3V3 mín. en TX | Nivel |
|---|---|---|
| Celda 4,2 / 3,7 V (Rint 0,2, Rdo típ.) | **3,30 V** | SIMULADO |
| Celda 3,5 V, Rint 0,3, Rdo máx., RPATH máx. | **3,04 V** | SIMULADO |
| Celda 3,4 V, peor caso | **2,94 V** (< 3,0 V de la hoja del módulo; > 2,51 V de brownout) | SIMULADO |
| Celda 3,3 V, peor caso | **2,84 V** (< 3,0 V; > brownout) | SIMULADO |
| Celda 3,3 V, típico | 3,02 V | SIMULADO |
| Brownout en algún caso (t > 1 s) | **no** | SIMULADO |
| **Pico al encender** (Q10 carga los ≈ 30 µF de entrada) | **4,8 A** (celda 3,3 V, Rint 0,3 Ω) a **9,8 A** (celda 4,2 V, Rint 0,2 Ω); > 1 A durante 33–43 µs (`resultados.json`, `i_pico_encendido_A`) | SIMULADO (idealizado: sin ESR ni inductancia) + PENDIENTE DE VALIDACIÓN FÍSICA (R-7) |

**Conclusión:**
- Con la celda por encima de 3,5 V, el ESP32-C3 se mantiene dentro de su hoja incluso en el peor caso.
- Entre 3,3 y 3,5 V, en el peor caso de tolerancias, las ráfagas de TX bajan la 3V3 a 2,84–3,04 V. Eso está fuera de la
  hoja del módulo, pero por encima del brownout.
- El firmware apaga cuando la batería pasa 10 s por debajo de 3,3 V (`girth_policy.h`). Propuesta: subir ese umbral a
  3,4 V (P-12).

Gráficas: `arranque_3.7V_rint0.2_rdo0.52.png`, `arranque_3.3V_rint0.3_rdo0.88.png`.

---

## 3. Fase 3 · Encendido magnético (Q10/Q11) (ngspice)

### 3.1 Problemas de la propia simulación, encontrados y corregidos (documentado)

1. **ngspice se detenía.** Daba «timestep too small» en `b.xu3.bdrop` (la función `max()` del regulador) y una matriz
   singular en el nodo del temporizador (CI de 05eab4e, `ventana_tip_3.0V.log`). Corregido así:
   - transición suave del regulador (softplus de 10 mV);
   - escalones `u()` cambiados por `tanh` de 5 mV;
   - resistencia de 1 GΩ en el nodo del temporizador.
2. **Columnas no encontradas.** ngspice escribe `v(VDD3)` y el script buscaba el nombre en minúsculas, lo que daba
   `KeyError`. Corregido.
3. **El caso «reed cerrado» se calculaba con el reed abierto.** En el análisis `.op`, una fuente PWL toma su valor DC (0),
   no su primer punto, y por eso salía 0,0 µA. Corregido con `DC <valor inicial>`.
4. **El criterio de «apagado» no servía.** Se usaba «3V3 < 1 V», pero sin consumo por debajo del brownout los
   condensadores se quedan en ≈ 2,4 V. Ahora el criterio es el estado de Q10: VSG < 0,3 V significa abierto.

### 3.2 Resultados de la REV B entregada

Lo que mide cada escenario (`spice/sim_revb.py`):
- **Ventana:** tiempo con 3V3 > 3,0 V tras cerrar el reed si el firmware **nunca** pone PWR_HOLD. Las simulaciones duran
  8 s (6 s en el Monte Carlo), así que un caso que sigue encendido al final se da como «> …».
- **Reinicio:** a t = 3 s el ESP32 se reinicia durante X s y después tarda 0,5 s más en poner PWR_HOLD. El reed ya está
  abierto desde t = 1 s.
- **«Caso peor»:** VGS(th) de Q11 en su máximo de hoja (1,45 V), C41 con un factor de 0,6 y C40 con 0,45, a 25 °C.

| Caso | Resultado | Nivel |
|---|---|---|
| **Ventana sin PWR_HOLD**, caso peor | celda 3,3 V: **2,90 s**; 3,5 V: 3,25 s; 3,7 V: 3,59 s; 4,2 V: 4,35 s | SIMULADO |
| Ventana sin PWR_HOLD, típico | 3,3 V: 7,14 s; 3,5 V: 7,69 s; 3,7 y 4,2 V: **> 7,9 s** (siguen encendidas al final). Con la celda a 3,0 V la 3V3 no llega a 3,0 V (celda vacía) | SIMULADO |
| **Monte Carlo de 200 casos** (VGS(th) de Q10 y Q11 uniforme en todo su margen, C40 0,45–1,1, C41 0,6–1,1, resistencias ±1 %, celda 3,2–4,2 V) | ventana mínima **3,49 s**, percentil 1 **3,62 s**; **más de la mitad sigue encendida a los 6 s** (mediana > 5,9 s). El Monte Carlo no llega a las esquinas: el peor caso fijo (2,90 s) es más bajo | SIMULADO |
| Margen frente al firmware | `gpow::hold()` es lo primero de `setup()` (REVISADO DOCUMENTALMENTE, código). El tiempo real hasta ese punto **no se ha medido**: QEMU no llega a `setup()` (sección 11.1). Con el 0,5 s supuesto, el margen es ≈ **5,8×** (2,90 / 0,5) | SIMULADO + **NO VERIFICADO** (tiempo de arranque) |
| **Reinicio del ESP32** | típico: aguanta 0,3, 0,6 y 1,0 s, y **cae con 1,5 s**. Caso peor: aguanta 0,3 s y **cae con 0,6 s**, así que el límite está entre 0,3 y 0,6 s de reinicio (**0,8–1,1 s sin PWR_HOLD**). Monte Carlo con 0,6 s: **3 de 200 caen** (3V3 mín. 2,45 V) | SIMULADO (conservador por el nivel 1; sin frío) |
| **Apagado** (PWR_HOLD = 0 y sueño profundo) con el reed abierto (caso normal, fuera del soporte) | Q10 abre a los **1,87 s** y no se vuelve a enganchar | SIMULADO |
| Apagado con el reed cerrado 60 s antes (batería baja o apagado remoto con la cincha en el soporte) | Q10 abre a los **1,87 s**; quedan **6,8 µA** por la red del reed | SIMULADO |
| Apagado con el reed cerrado **2,9 s antes** (peor caso) | Q10 abre a los **6,95 s**: la cola del impulso (C40·R41 ≈ 15 s) mantiene PWR_G. Retrasa el apagado, no lo impide | SIMULADO |
| Volver a encender (reed abierto y cerrado de nuevo 0,5–5 s después de apagar; peor caso de Q11, C40 y C41) | **se engancha en los 5 casos** (la 3V3 vuelve a > 3,0 V) | SIMULADO |
| **Con 5 V** (Qi/USB) y PWR_HOLD = 0 | sigue encendida (por D10); al quitar los 5 V, Q10 abre a los **2,66 s** | SIMULADO |
| Bloqueos | en los escenarios simulados no hay ningún estado sin salida: con 5 V no apaga (es el diseño) y al quitarlos apaga sola. No es una demostración para todos los estados posibles | SIMULADO (solo esos escenarios) |
| Apagado con la celda muy baja o tras un brownout | **no simulado** | NO VERIFICADO |

Gráficas en `resultados_ci/spice/`:
- `ventana_tip_3.3V.png`, `ventana_peor_3.3V.png`
- `reinicio_0.6s_peor.png`, `reinicio_1.5s_peor.png`
- `apagado_reed_abierto.png`, `apagado_reed_cerrado_2_9_s_antes.png`, `apagado_reed_cerrado_60_s_antes.png`
- `reencendido_1.0s.png`, `reencendido_3.0s.png`
- `carga_5V.png`
- `montecarlo.png`

**Límites del caso de reinicio:**
- solo varía VGS(th) de Q11 y C41;
- está a 25 °C;
- se simula con el reed abierto. En el soporte, con el reed cerrado, C40 no aporta corriente continua a PWR_G, así que
  se espera lo mismo, pero no se ha simulado.

### 3.3 Consumo apagado

| Caso | Resultado | Nivel |
|---|---|---|
| Reed abierto (fuera del soporte) | el modelo da 0,0 µA porque **no tiene fuga**. La cifra real la dan las fugas de la hoja de AOS: IDSS ≤ 1 µA a 25 °C (a VDS = 30 V; a 4 V es menor) para Q10 y para Q11 (por R40), así que **≤ 2 µA a 25 °C**. AOS da hasta 5 µA a 55 °C | REVISADO DOCUMENTALMENTE + PENDIENTE DE VALIDACIÓN FÍSICA |
| Reed cerrado (en el soporte), celda 4,2 V | **7,7 µA** (R45 y R49/R50) | SIMULADO |
| Riesgo térmico (R-15) | con R40 = 1 MΩ, una fuga de Q11 de 0,5 µA ya pone 0,5 V en la puerta de Q10 (su VGS(th) mín.). A 55 °C, Q10 podría conducir con la placa apagada. La REV B.1 baja R40 a 100 k (≤ 0,5 V con 5 µA) | REVISADO DOCUMENTALMENTE |

### 3.4 Corrección de firmware (R-2)

En el peor caso de tolerancias, un reinicio por vigilante o por fallo puede apagar la placa. Corrección aplicada en la
rama de auditoría (`girth_power.cpp`):
- PWR_HOLD queda bloqueado con `gpio_hold_en` mientras la placa funciona. Según ESP-IDF, `gpio_hold_en` sirve para
  «retain the state of GPIOs when the chip or system is reset (e.g. watchdog time-out …)»
  ([ESP-IDF v5.3, GPIO del ESP32-C3](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32c3/api-reference/peripherals/gpio.html)).
- Antes de escribir 0 para apagar, se suelta el bloqueo.

La documentación no aclara si la ROM anula el bloqueo en todos los tipos de reinicio. Por eso esta mejora queda
**PENDIENTE DE VALIDACIÓN FÍSICA**: hay que provocar un reinicio por vigilante sin 5 V y comprobar que la placa no se
apaga. El firmware compila con el cambio (sección 11). La corrección de hardware equivalente (C41 = 470 nF) va en la
REV B.1 (sección 13).

---

## 4. Fase 4 · Qi (BQ51013B) y cargador (BQ24072)

Detalle completo, con fuentes y cálculos: `qi/AUDITORIA_QI.md`, `qi/calc_qi.py` y `qi/calc_qi_salida.txt`.

| Comprobación | Resultado | Nivel |
|---|---|---|
| Patillaje de U1 y U2 frente a TI (SLUSB62D, SLUS810N) | correcto | REVISADO DOCUMENTALMENTE |
| Resonancia serie | C1 = 247 nF resuena en 90–105 kHz solo si Ls′ = 9,30–12,66 µH. La bobina no está identificada ni medida (**H-1**). Bobina comercial propuesta: **TDK WR202010-18M8-ID** (Ø20 mm, 11 µH, JLC C3606542) | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |
| Resonancia paralelo (1 MHz) | la fórmula de C2 de `DOCS/AJUSTE_QI.md` era errónea (**H-2**). Corregida en la rama: C2 = 1/((2π·fD)²·Ls − 1/C1) | VERIFICADO POR CÁLCULO |
| Corriente de carga | ICHG = KISET/RISET = **239–298 mA** con las tolerancias de KISET y de RISET (241–295 mA con RISET nominal); 0,54 C típ. | VERIFICADO POR CÁLCULO (`qi/calc_qi_salida.txt`) |
| Límite de entrada | REV B: ILIM 3,3 k da **399–526 mA**. El máximo pasa de los 494 mA del límite del Qi, lo que el propio cálculo señala. REV B.1: USB500, 450–500 mA con VIN-DPM | VERIFICADO POR CÁLCULO + REVISADO DOCUMENTALMENTE |
| **Modo del cargador frente al Qi** | U1 con EN1 = EN2 = 0 usa el límite de comunicación adaptativo, que según TI «requires the battery charger device to have input voltage regulation». El BQ24072 en modo ILIM (EN2 = 1, REV B) **no tiene VIN-DPM**; en USB100 y USB500 sí lo tiene (EN2 = 0, SLUS810, tabla 1) (**H-3**). La REV B.1 lo pone en USB500 | REVISADO DOCUMENTALMENTE; efecto en la carga Qi: PENDIENTE DE VALIDACIÓN FÍSICA |
| Protección térmica | las dos NTC (RT1 del Qi y RT2 del cargador) están **en la placa**, a 3,8–3,9 mm de U1 y U2, **no en la celda** (**H-4**). Ventana del Qi: −0,2…45,2 °C (corte caliente de 39,9 a 51,2 °C en el peor caso), así que puede cortar por el calor de la propia placa | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |
| Terminación, precarga y temporizador | precarga de 26,7 mA durante 30 min (13,3 mAh); terminación según la hoja | REVISADO DOCUMENTALMENTE |
| Alimentación del sistema mientras carga | DPPM del BQ24072 (VSYS sigue a VBAT más un margen); con 5 V la placa sigue encendida (sección 3) | REVISADO DOCUMENTALMENTE + SIMULADO |
| Batería baja o muy descargada | precarga; recuperación a través del diodo de Q10 si la celda está en protección (**H-9**) | PENDIENTE DE VALIDACIÓN FÍSICA |
| Calentamiento | hasta 0,61 W en el BQ24072 al empezar la carga rápida (ΔTJ ≈ 27 °C en placa JEDEC) (**H-12**) | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |
| Menores | H-5 (una sola huella para ROS y RFOD), H-6 (C_COMM), H-7 (0,54 C sin hoja de la celda), H-8 (referencia SLUSAF8 en un comentario), H-10 (11 µF en VIN5), H-11 (margen VSYS/RT9080) | ver `qi/AUDITORIA_QI.md` |

**Lo que no se puede simular del Qi** (`qi/AUDITORIA_QI.md` §4):
- la comunicación WPC (ASK por COMM, que depende del transmisor);
- la calibración FOD (TI: «There is no formula»);
- el acoplamiento y la alineación;
- el lazo de control con el transmisor;
- la eficiencia;
- la temperatura real;
- la recuperación de la celda muy descargada.

---

## 5. Fase 5 · ESP32-C3

| Comprobación | Resultado | Nivel | Evidencia |
|---|---|---|---|
| Tabla GPIO firmware ↔ esquema | **15 GPIO, 0 discrepancias**, ningún GPIO libre (tabla abajo) | VERIFICADO MEDIANTE HERRAMIENTA | `esp32/gpio_tabla.md` (con el símbolo oficial de Espressif) |
| Alimentación | 3V3 con C22 10 µF, C23 22 µF y C24 100 nF; caída en TX en la sección 2 | VERIFICADO MEDIANTE HERRAMIENTA (redes) + SIMULADO | `kicad/auditoria_redes.csv`, SPICE |
| Pines de arranque | GPIO9 (BOOT, TP2) con R12 10 k a 3V3: arranque normal. GPIO8 (LED, activo bajo, con R15 1 k y D1 a 3V3) con R13 10 k a 3V3: vale 1 al arrancar, como pide el modo descarga. GPIO2 = SCL con R21 4,7 k a 3V3 (la hoja del módulo pide GPIO2 = 1) | REVISADO DOCUMENTALMENTE | `fuente/avo_girth_pcb.py`, hoja del ESP32-C3-MINI-1 |
| EN | R11 10 k a 3V3 + C25 1 µF a GND (el retardo RC que pide la hoja) | REVISADO DOCUMENTALMENTE | idem |
| USB | GPIO18/19 → R18/R19 22 Ω → U6 USBLC6 → J1; CC con 5,1 k (R16/R17) | VERIFICADO MEDIANTE HERRAMIENTA (redes) | `kicad/auditoria_redes.csv` |
| Flash y grabación | 4 MB; por USB-Serial-JTAG o por UART0 (TP4/TP5) | REVISADO DOCUMENTALMENTE | README |
| Particiones OTA | `PartitionScheme=default`: dos ranuras OTA de 1 310 720 B. El firmware ocupa **1 010 541 B (77 %)** | VERIFICADO MEDIANTE HERRAMIENTA | `firmware/compilacion_produccion.txt` |
| Vigilante | vigilantes de tareas del núcleo de Arduino; los reinicios se tratan en la sección 3 | REVISADO DOCUMENTALMENTE (código) | — |
| ADC de batería | GPIO3 (ADC1), divisor 1 M/1 M + 100 nF (C34) | REVISADO DOCUMENTALMENTE | — |
| Despertar | GPIO1 (reed) y GPIO4 (CHG_PG), por nivel, dentro de GPIO0–5 | REVISADO DOCUMENTALMENTE (código) | `girth_power.cpp` |
| Antena externa | conector del módulo de **3.ª generación (W.FL / MHF III)**, no U.FL. El texto de `gate.py` decía «U.FL / MHF I» (corregido en la rama) | REVISADO DOCUMENTALMENTE | README, hoja del módulo |
| Banda sin cobre bajo la antena FPC | ninguna pista, vía ni pad en las 4 capas | VERIFICADO MEDIANTE HERRAMIENTA | `mecanica/mecanica_salida.txt` |
| Rendimiento RF y ESP-NOW por radio | — | **NO VERIFICADO** (no se puede validar por software) | — |

| Firmware | GPIO | Pin | Red |
|---|---|---|---|
| PIN_IMU_INT | 0 | 12 | IMU_INT |
| PIN_REED | 1 | 13 | REED |
| PIN_SCL | 2 | 5 | I2C_SCL |
| PIN_BAT_ADC | 3 | 6 | BAT_ADC |
| PIN_CHG_PG | 4 | 18 | CHG_PG |
| PIN_PWR_HOLD | 5 | 19 | PWR_HOLD |
| PIN_SDA | 6 | 20 | I2C_SDA |
| PIN_CHG_STAT | 7 | 21 | CHG_STAT |
| PIN_LED | 8 | 22 | LED |
| PIN_BOOT | 9 | 23 | BOOT |
| PIN_QI_CHG | 10 | 16 | QI_CHG |
| USB D− / D+ | 18 / 19 | 26 / 27 | USB_DM / USB_DP |
| UART0 RX / TX | 20 / 21 | 30 / 31 | U0RX / U0TX |

---

## 6. Fase 6 · Sensores

| Comprobación | Resultado | Nivel |
|---|---|---|
| Alimentación | LSM6 a 3V3 con C27/C28 100 nF; MMC a 3V3 con C29 1 µF y C31 100 nF; MAG_CAP con C30 10 µF | VERIFICADO MEDIANTE HERRAMIENTA (redes) |
| Direcciones I²C | LSM6DS3TR-C en **0x6A** (SA0 a GND) y MMC5983MA en **0x30** (fija): no chocan | REVISADO DOCUMENTALMENTE (`girth_board.h`, esquema) |
| Pull-ups | 4,7 k a 3V3. Mínimo (3,3 − 0,4) V / 3 mA = 0,97 k. Subida 0,85 · 4,7 k · 50 pF ≈ 0,2 µs < 0,3 µs (modo rápido, 400 kHz) | VERIFICADO POR CÁLCULO (aquí); los 50 pF de bus son supuestos → PENDIENTE DE VALIDACIÓN FÍSICA |
| Niveles | todo a 3,3 V, sin traslación | REVISADO DOCUMENTALMENTE |
| Frecuencias | LSM6 a 104 Hz (acelerómetro y giróscopo); MMC a 100 Hz continuo con SET/RESET automático | REVISADO DOCUMENTALMENTE (código) |
| Interrupción | INT1 del LSM6 (dato listo) → GPIO0, que marca el ritmo de la adquisición | REVISADO DOCUMENTALMENTE (código) |
| Rangos | ±8 g, ±2000 dps, ±8 G (±800 µT) | REVISADO DOCUMENTALMENTE (código) |
| **Saturación** | paso, trote y galope no saturan (pico de 5,2 g en el galope). **El salto satura 5 muestras a ±8 g** (pico simulado 12,9 g, error máx. 4,9 g); propuesta: ±16 g (P-11) | VERIFICADO MEDIANTE HERRAMIENTA (simulador de marcha) |
| Interferencia magnética | imanes de la cápsula y del soporte: **406 µT** con la polaridad del README, 555 µT con 3 imanes por esquina y **918 µT en el peor caso, por encima de los ±800 µT del MMC** (R-9) | VERIFICADO POR CÁLCULO (dipolo, N35) + PENDIENTE DE VALIDACIÓN FÍSICA |
| Orientación de los ejes | el firmware envía los ejes del sensor sin rotar; la orientación en la cincha depende del montaje | PENDIENTE DE VALIDACIÓN FÍSICA |
| Calibración | la cincha no calibra offset ni hierro duro/blando (se hace en el receptor) | REVISADO DOCUMENTALMENTE (código) |
| Simulador de movimiento | `firmware/girth/V0_3_0_C3/pruebas/marcha.py`: señales sintéticas de 9 canales a 104 Hz (paso, trote, galope y salto con aterrizaje de 10,5 g), 20 s | VERIFICADO MEDIANTE HERRAMIENTA |
| Adquisición, empaquetado y proceso de 9 canales | pasan por el empaquetado real (`girth_pack.h`) y por el receptor real de la espalda (`GirthHub` de `avo_core`). Paso, trote y galope llegan **idénticos** (error ≤ 0,00012 g, 0,034 dps y 0,00012 G); 220 B por paquete, 2288 B/s | VERIFICADO MEDIANTE HERRAMIENTA |
| Datos brutos frente a fusión | la cincha envía **datos brutos** (int16 escalados, `IMU_FMT_9AXIS_I16`); la fusión no está en la cincha y no se valida aquí | REVISADO DOCUMENTALMENTE (código) |

Evidencia: `resultados_ci/firmware/pruebas_salida.txt` y `resultados_pruebas.json`.

---

## 7. Fase 7 · ESP-NOW (pruebas automáticas en el PC)

`firmware/girth/V0_3_0_C3/pruebas/test_cincha.cpp`, compilado con `g++` junto con la biblioteca de protocolo real de la
espalda (`firmware/back/V3_8_0/lib/avo_core`). **Valida la lógica del protocolo, no la radio.**

| Prueba | Resultado | Nivel |
|---|---|---|
| Pérdida aleatoria | se cuenta exacta | VERIFICADO MEDIANTE HERRAMIENTA |
| **Duplicados** | no se cuentan como pérdida, pero `GirthHub` **los reenvía al pecho** (60 reenviados para 50 únicos) (R-10) | VERIFICADO MEDIANTE HERRAMIENTA |
| **Desorden** | llegan los 40, pero **19 se cuentan como perdidos** (R-10) | VERIFICADO MEDIANTE HERRAMIENTA |
| Reinicio de la cincha | no falsea pérdidas (identificador de arranque) | VERIFICADO MEDIANTE HERRAMIENTA |
| Reconexión tras un corte | correcta | VERIFICADO MEDIANTE HERRAMIENTA |
| Integridad | rechaza los 200 paquetes corruptos | VERIFICADO MEDIANTE HERRAMIENTA |
| Identificación | rechaza otra cincha que no está emparejada | VERIFICADO MEDIANTE HERRAMIENTA |
| Carga de transmisión | 220 B, 11,4 paquetes/s, 2329 B/s | VERIFICADO MEDIANTE HERRAMIENTA |
| Ocupación de la radio | ≈ 2,9 % a 1 Mbps, contando ×1,3 por reintentos (`autonomia/autonomia.md`) | VERIFICADO POR CÁLCULO |
| Apagado remoto (bit en el PING) | correcto | VERIFICADO MEDIANTE HERRAMIENTA |
| Compatibilidad con la espalda | mismo `avo_girth_link.h`; las 37 pruebas de la espalda pasan (414 comprobaciones) | VERIFICADO MEDIANTE HERRAMIENTA |
| Cambio de canal, saturación de TX y sincronización de tiempo | lógica de colas y semáforos revisada en el código; el comportamiento real depende de la radio | REVISADO DOCUMENTALMENTE (código) + NO VERIFICADO (radio) |
| Alcance, pérdida real, coexistencia y antena | — | **NO VERIFICADO** (solo con hardware) |

Resultado global: **19 pruebas, 4313 comprobaciones, 0 fallidas** (`resultados_ci/firmware/pruebas_salida.txt`).

---

## 8. Fase 8 · Batería y autonomía (teórica, sin mediciones)

`autonomia/autonomia.py` → `resultados_ci/autonomia/autonomia.md`. **VERIFICADO POR CÁLCULO; nada medido.**

| Escenario | Corriente | 500 mAh nueva | envejecida (80 %) | a 0 °C (85 %) |
|---|---|---|---|---|
| Firmware V0.3.0 (`WIFI_PS_NONE`, receptor siempre encendido) | 94,0 mA | **5,1 h** | 4,0 h | 4,3 h |
| Con ahorro de radio (propuesta, ventana de recepción ≈ 15 %) | 45,5 mA | 10,4 h | 8,3 h | 8,9 h |
| Con ahorro de radio y magnetómetro a 20 Hz | 42,9 mA | 11,1 h | 8,8 h | 9,4 h |

- **Apagada:** ≤ 2 µA fuera del soporte a 25 °C (sección 3.3) y 7–9 µA dentro del soporte. Domina la autodescarga de la
  celda.
- **Carga:** 239–298 mA, unas 1,9–2,7 h (estimado).

**Hallazgo (P-10):** el README daba 25–45 mA y 11–20 h; con el firmware actual son ≈ 94 mA y ≈ 5 h. Corregido en el
README de la rama. Llegar a unas 10 h exige el ahorro de radio del ESP-NOW, que cambia la latencia de la recepción y hay
que probar con la espalda.

---

## 9. Fase 9 · Fabricación en JLCPCB

`fabricacion/fab_check.py` → `resultados_ci/fabricacion/fab_check.json`. Las existencias y los precios son de hoy,
consultados en la API de JLCPCB (`fuente/stock_jlc.py`, `resultados_ci/fabricacion/existencias/`; la fecha de la
consulta está en el JSON).

| Comprobación | Resultado | Nivel |
|---|---|---|
| Gerber | 16 ficheros: 4 capas (L1–L4), pasta, serigrafía, máscara, contorno y taladros PTH/NPTH | VERIFICADO MEDIANTE HERRAMIENTA |
| Grosor y acabado | 1,0 mm. **ENIG** figura en el `gbrjob`, pero el acabado **se elige en el pedido** (no va en los Gerber) | VERIFICADO MEDIANTE HERRAMIENTA |
| BOM ↔ CPL ↔ placa | 85 montadas, 85 en la BOM y 85 en el CPL; ninguna sin pareja. DNP: C5. A mano (fuera de la BOM): L1, L2, TP1–TP8, SW1 y SW2 | VERIFICADO MEDIANTE HERRAMIENTA |
| Códigos LCSC | los 41 coinciden con `piezas.json`; el encapsulado de JLC coincide con la huella en todos | VERIFICADO MEDIANTE HERRAMIENTA |
| Existencias para 2 placas | **hay de todas** (p. ej. C3-MINI-1U C2911374, BQ24072 2868 uds.) | VERIFICADO MEDIANTE HERRAMIENTA |
| Pin 1 | lista de la posición y el ángulo del pin 1 de cada pieza; la polaridad no se comprueba con herramienta | VERIFICADO MEDIANTE HERRAMIENTA (lista) + PENDIENTE DE VALIDACIÓN FÍSICA (vista previa y placa) |
| **Giros del CPL** | el CPL sale de KiCad sin correcciones. Propuesta de giros desde la base comunitaria `cpl_rotations_db.csv`: SOT-23 −90°, QFN-16 +270°, USB-C 180°; ninguno para RHL-20, LGA ni el módulo. **Hay que confirmarlos en la vista previa del pedido** | VERIFICADO MEDIANTE HERRAMIENTA (propuesta) + PENDIENTE DE VALIDACIÓN FÍSICA (vista previa de JLCPCB) |
| Cara inferior | ninguna pieza | VERIFICADO MEDIANTE HERRAMIENTA |
| Piezas externas | bobina Qi (L1/L2: pads para hilo), reed (SW1/SW2), batería (J2) y antena FPC W.FL | REVISADO DOCUMENTALMENTE |
| REV B.1: existencias de su BOM y pieza nueva de C41 | hay existencias de las 41 líneas. C41 = **C47339** (Samsung CL05A474KP5NNNC, 470 nF 10 V X5R 0402, Extended, 700 175 uds.); alternativa C92361 (25 V, 176 020 uds.). Un primer código candidato (C1543) resultó ser de 820 pF y se descartó gracias a esta comprobación | VERIFICADO MEDIANTE HERRAMIENTA (`resultados_ci/rev_b1/existencias.txt`, `pieza_C41_C1543.txt`) |

### Presupuesto actualizado (5 PCB, 2 montadas, PCBA estándar)

| Partida | REV B | REV B.1 |
|---|---|---|
| Componentes para 2 placas (precios de hoy, con compra mínima y merma) | 33,13 US$ | **33,06 US$** (misma fórmula, existencias de la consulta de la REV B.1) |
| Montaje: puesta en marcha 25,56 + plantilla 8,21 + cargas × 1,53 + soldaduras × 2 × 0,0176 + manipulación 14,93 + embalaje 0,50 + rayos X (5 piezas × 2 × 0,82) | **132,66 US$** (41 cargas, 356 soldaduras) | **132,59 US$** (41 cargas, 354 soldaduras) |
| **Total sin PCB desnuda ni envío** | **165,79 US$** | **165,65 US$** |
| PCB desnuda: 4 capas, 65,5 × 43,5 mm, 1,0 mm, ENIG, 5 uds. | **NO VERIFICADO** (solo lo da el presupuestador de JLCPCB) | igual |
| Envío, aduanas e impuestos | NO VERIFICADO | igual |

Las tarifas de PCBA son las publicadas por JLCPCB y ya usadas en el presupuesto anterior (`FEES` en `fab_check.py`). El
C3, el LSM6 y el MMC son «Standard only», así que la PCBA estándar es obligatoria.

**Configuración del pedido (preparada, no enviada):**
- 4 capas, 65,5 × 43,5 mm, 1,0 mm, ENIG, 5 PCB;
- PCBA estándar, 2 placas, montaje en una cara (Top).

Ficheros:
- **REV B:** `out/C3/AVO_GIRTH_PCB_C3_GERBER_JLCPCB.zip`, `…_BOM_…csv` y `…_CPL_…csv`.
- **REV B.1:** `resultados_ci/rev_b1/AVO_GIRTH_PCB_C3_REV_B1_GERBER_JLCPCB.zip`,
  `corregida/AVO_GIRTH_PCB_C3_REV_B1_BOM_JLCPCB.csv` y `corregida/AVO_GIRTH_PCB_C3_REV_B1_CPL_JLCPCB.csv`.

En los dos casos hay que revisar los giros en la vista previa.

---

## 10. Fase 10 · Mecánica (cápsula REV 5.8.1 y STL)

Detalle: `mecanica/AUDITORIA_MECANICA.md`, `mecanica/mecanica.py`, `mecanica_salida.txt`, `plano_planta.png` y
`corte_vertical.png`. Hay dos escenarios:
- **A:** la cuna sube 0,6 mm, como pide el README de la PCB.
- **B:** el CAD 5.8.1 sin cambios.

| Comprobación | Resultado | Nivel |
|---|---|---|
| Contorno, muescas y ranura | 65,500 × 43,500 mm, iguales en KiCad, Gerber y fuente. Las 8 muescas quedan centradas en las columnas (holgura 0,80 mm); holgura lateral 0,15 mm | VERIFICADO MEDIANTE HERRAMIENTA |
| **Tapa** | los postes **chocan**. A: J2 2,50 · U4 2,15 · U6 1,00 · D13 0,65 · C25 0,15 mm, y el labio invade 0,55 mm. B: J2 1,85 · U4 1,50 · U6 0,35 · D13 0,00 mm; el labio queda a 0,10 mm. En los dos la tapa no asienta y **la junta no sella** | VERIFICADO MEDIANTE HERRAMIENTA |
| **Antena FPC** | la del CAD está fuera de la banda sin cobre. Una FPC de 28 × 6 mm dentro de la banda choca con los postes y con la columna Ø7 del inserto M3 | VERIFICADO MEDIANTE HERRAMIENTA |
| Sujeción y vibración | la placa apoya en el 6,1 % de su superficie (anillo de la cuna). **Nada la aprieta desde arriba**: el labio queda a 0,10 mm (B) y los postes a 0,45 mm (A) | VERIFICADO MEDIANTE HERRAMIENTA + PENDIENTE DE VALIDACIÓN FÍSICA |
| USB-C | la cápsula no tiene abertura; con la tapa quitada el acceso es justo | VERIFICADO MEDIANTE HERRAMIENTA + PENDIENTE DE VALIDACIÓN FÍSICA |
| Batería, bobina y reed | caben; el cable de la batería tiene 2,11 mm libres; el reed queda bajo SW1/SW2 | VERIFICADO MEDIANTE HERRAMIENTA |
| Imanes frente al magnetómetro | sección 6 (hasta 918 µT) | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |

**Todo esto son cambios del CAD de la cápsula, no de la PCB** (C1–C14 de `mecanica/AUDITORIA_MECANICA.md` §3). No
impide fabricar la placa para los 2 prototipos de banco, pero montarla en la cápsula exige la REV 5.9 del CAD.

---

## 11. Fase 11 · Firmware

| Comprobación | Resultado | Nivel | Evidencia |
|---|---|---|---|
| Compilación de producción (arduino-esp32 3.3.12, `CDCOnBoot=cdc`, 4 MB, particiones por defecto) | compila; **1 010 541 B (77 %)**, 11 % de RAM | VERIFICADO MEDIANTE HERRAMIENTA | `firmware/compilacion_produccion.txt`, `sha256_produccion.txt` |
| Pruebas automáticas en el PC | cincha: 19 pruebas, 4313 comprobaciones, 0 fallos. Espalda: 37 pruebas, 414 comprobaciones, 0 fallos | VERIFICADO MEDIANTE HERRAMIENTA | `firmware/pruebas_salida.txt`, `pruebas_espalda.txt` |
| **Error encontrado y corregido** | en `girth_policy`, `out_since = now \| 1`: cuando `now` era par, la resta sin signo daba la vuelta y la placa se apagaba **al instante** al salir del soporte (≈ 50 % de las veces). Corregido a `now ? now : 1`; lo cubre la prueba `alimentacion.fuera_del_soporte_apaga_a_los_3s` | VERIFICADO MEDIANTE HERRAMIENTA | `girth_policy.h`, `test_cincha.cpp` |
| Estados de alimentación | fuera del soporte 3 s → apaga; vuelve al soporte → cancela; batería < 3,3 V durante 10 s → apaga (no si está cargando); base Qi fuera del soporte → duerme (con USB no); apagado remoto; solo despierta por el reed si está abierto | VERIFICADO MEDIANTE HERRAMIENTA | `test_cincha.cpp` |
| Sensores, empaquetado, comunicaciones y errores | secciones 6 y 7 | VERIFICADO MEDIANTE HERRAMIENTA | idem |
| Arranque en **QEMU** (Espressif 9.2.2, `esp32c3`) | ver 11.1 | VERIFICADO MEDIANTE HERRAMIENTA (lo que QEMU emula) | `resultados_ci/qemu/` |
| Vigilante, OTA y recuperación | dos ranuras OTA en la tabla de particiones; recuperación con BOOT (TP2) o por UART0. **AVO Update aún no instala en el C3** (README) | REVISADO DOCUMENTALMENTE | README |
| Periféricos sin modelo (radio, I²C con sensores, ADC, Qi) | **no se simulan**: QEMU no emula la radio ni el ADC del C3, ni los sensores | NO VERIFICADO | — |

### 11.1 QEMU

Variante de prueba: Serial en UART0, flash en DIO y registro `info`.

1. **eFuse.** Con eFuse a cero (chip v0.0), el registro de UART0 no muestra nada después del `entry 0x403cbf10` de la ROM.
   Se pasó a la imagen de eFuse que usa ESP-IDF para QEMU (chip v0.3), en `qemu/efuse_esp32c3_rev0_3.bin`.
2. **Boceto mínimo de control** (`qemu/minimo/`, mismas opciones de compilación, sin radio): **arranca y funciona**. Pasa
   por el cargador, la tabla de particiones, el arranque de ESP-IDF, `setup()` y más de 50 vueltas de `loop()`
   (`resultados_ci/qemu/minimo.uart0.log`). La cadena de arranque con estas opciones funciona en QEMU.
3. **Firmware de la cincha:** **no llega a `setup()`.** La pila de GDB (`resultados_ci/qemu/cincha.pila_gdb.txt`) lo
   deja parado en un constructor global de ESP-IDF, antes de `setup()`:
   `start_cpu0_default → do_global_ctors → adc2_init_code_calibration → adc_calc_hw_calibration_code →
   adc_hal_self_calibration → read_cal_channel → adc_oneshot_ll_get_event`. Esa calibración del ADC2 se enlaza porque el
   firmware usa Wi-Fi/ESP-NOW, y QEMU no emula el ADC SAR del C3, así que la espera no termina nunca.
   **Es un límite del simulador, no un error del firmware:** el boceto mínimo, sin Wi-Fi, pasa ese punto.

**Qué valida QEMU:** la imagen combinada, el cargador, la tabla de particiones y la carga de la aplicación hasta el
arranque de ESP-IDF.

**Qué no valida:** `setup()`, la radio, los periféricos ni el tiempo hasta `gpow::hold()`. Todo eso queda **NO
VERIFICADO** por simulación y **PENDIENTE DE VALIDACIÓN FÍSICA**.

---

## 12. Tabla de riesgos

| # | Riesgo | Prob. | Impacto | Estado y mitigación | Nivel |
|---|---|---|---|---|---|
| R-1 | Qi inestable: límite adaptativo del BQ51013B con un BQ24072 sin VIN-DPM (modo ILIM) (H-3) | media | media: la carga Qi puede oscilar; el USB no se ve afectado | **corrección propuesta en la REV B.1** (USB500). Placa validada en KiCad; efecto en la carga Qi pendiente de prueba | REVISADO DOCUMENTALMENTE + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-2 | Un reinicio del ESP32 de 0,3–0,6 s (0,8–1,1 s sin PWR_HOLD) apaga la placa en el peor caso de tolerancias (3/200 en el Monte Carlo con 0,6 s) | baja | media | firmware: `gpio_hold_en` (pendiente de prueba física). Hardware: **C41 = 470 nF en la REV B.1** (simulado: aguanta 1,5 s en el peor caso y 0/200 en el Monte Carlo) | SIMULADO + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-3 | Bobina Qi sin identificar: resonancia fuera de 90–105 kHz (H-1) | alta si no se elige | alta: sin carga Qi | TDK WR202010-18M8-ID y medir Ls/Ls′; montar la opción B de condensadores si hace falta | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-4 | NTC en la placa y no en la celda: la celda no está protegida por temperatura al cargar, y el Qi puede cortar por el calor de la placa (H-4) | media | **alta en uso real** (LiPo); baja en banco vigilado | prototipos: cargar solo vigilados. Siguiente revisión: NTC en la celda y red TS del Qi | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-5 | Cápsula 5.8.1: la tapa no cierra ni sella, la antena no cabe y la placa no está sujeta | **cierta** con el CAD actual | alta para montarla en el caballo; nula en banco | cambios C1–C14 del CAD | VERIFICADO MEDIANTE HERRAMIENTA |
| R-6 | 3V3 por debajo de 3,0 V en TX con la celda entre 3,3 y 3,5 V (peor caso) | baja | baja-media: fuera de la hoja, sin brownout | umbral de batería baja a 3,4 V (P-12) | SIMULADO |
| R-7 | Pico de corriente al encender (sección 2.2): podría disparar la protección contra cortocircuito de la celda | baja | media: no enciende a la primera | medir con la celda real; si dispara, frenar la puerta de Q10 | SIMULADO + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-8 | Giros del CPL incorrectos en JLCPCB | media | alta: piezas giradas | revisar la vista previa con la tabla de giros propuestos | VERIFICADO MEDIANTE HERRAMIENTA + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-9 | Los imanes saturan el MMC5983MA (hasta 918 µT > 800 µT) | media | media: rumbo inválido | 1 imán por esquina y diagonales opuestas (C14); medir | VERIFICADO POR CÁLCULO + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-10 | `GirthHub` (espalda) reenvía los duplicados y cuenta como perdidos los paquetes desordenados | alta con radio real | baja-media: estadística de pérdidas falsa y datos repetidos en el pecho | corregir en `avo_core` (ventana de secuencia); no afecta a la PCB | VERIFICADO MEDIANTE HERRAMIENTA |
| R-11 | Saturación a ±8 g al aterrizar de un salto | media | baja-media | ±16 g (cambia la escala del protocolo: coordinar con la espalda) | VERIFICADO MEDIANTE HERRAMIENTA |
| R-12 | Rendimiento RF (alcance, pérdidas, antena W.FL) | — | alta | prueba de campo | NO VERIFICADO |
| R-13 | Autonomía real ≈ 5 h, no 11–20 h | cierta con el firmware actual | media | ahorro de radio | VERIFICADO POR CÁLCULO |
| R-14 | El cajetín de la REV B lleva revisión «A» en los Gerber | cierta | baja: confusión de revisiones | «B.1» en la REV B.1 | VERIFICADO MEDIANTE HERRAMIENTA |
| R-15 | Con calor, la fuga de Q11 a través de R40 = 1 M puede abrir Q10 con la placa apagada (consumo o encendido no deseado) | baja | media | **R40 = 100 k en la REV B.1** | REVISADO DOCUMENTALMENTE + PENDIENTE DE VALIDACIÓN FÍSICA |
| R-16 | QEMU no llega a `setup()`: el arranque real del firmware y su tiempo hasta `hold()` no están comprobados | — | media | primer arranque en la placa (sección 14) | NO VERIFICADO |

---

## 13. Problemas, correcciones propuestas y comparación antes/después

### 13.1 Lista de problemas

| # | Problema | Dónde | Corrección | Estado |
|---|---|---|---|---|
| P-1 | BQ24072 en modo ILIM (sin VIN-DPM) con el Qi en límite adaptativo (H-3) | PCB | USB500: EN1 = VSYS, EN2 = GND | **REV B.1** (placa validada en KiCad; efecto en el Qi pendiente) |
| P-2 | Bobina Qi sin definir (H-1) | BOM/montaje | TDK WR202010-18M8-ID y medida | propuesta |
| P-3 | Fórmula de C2 errónea (H-2) | `DOCS/AJUSTE_QI.md` | fórmula de TI | **corregida en la rama** |
| P-4 | NTC fuera de la celda (H-4) | PCB | NTC en la celda; red TS del Qi | propuesta (siguiente revisión) |
| P-5 | Un reinicio largo apaga en el peor caso (R-2) | firmware + PCB | `gpio_hold_en` en PWR_HOLD; C41 = 470 nF | **hechas en la rama** (firmware) y **en la REV B.1** (C41); pendientes de prueba física |
| P-6 | `now \| 1` en la política de alimentación (apagado instantáneo en ≈ 50 % de los casos) | firmware | `now ? now : 1` | **corregida en la rama** |
| P-7 | Duplicados y desorden en `GirthHub` | firmware de la espalda | ventana de secuencia | propuesta |
| P-8 | Cápsula (C1–C14) | CAD | REV 5.9 | propuesta |
| P-9 | Cajetín con «A» en los Gerber | PCB | «B.1» | **REV B.1** |
| P-10 | README con 11–20 h de autonomía | documentación | ≈ 5 h | **corregida en la rama** |
| P-11 | ±8 g satura en los saltos | firmware | ±16 g | propuesta |
| P-12 | Umbral de batería baja de 3,3 V | firmware | 3,4 V | propuesta |
| P-13 | «U.FL / MHF I» en `gate.py` | documentación | «W.FL / MHF III» | **corregida en la rama** |
| P-14 | README con «< 1 µA apagada» sin distinguir dentro y fuera del soporte | README | ≤ 2 µA fuera (25 °C) y ≈ 7–8 µA dentro | **corregida en la rama** |
| P-15 | La línea de arranque solo salía al final de `setup()`, después de la radio | firmware | línea temprana con `Serial.flush()` | **hecha en la rama** |
| P-16 | R40 = 1 M es sensible a la fuga de Q11 con calor (R-15) | PCB (valor) | 100 k | **REV B.1** |

### 13.2 REV B.1 (`AUDITORIA_REV_B/corregida/`)

Se genera con `corregida/aplicar_rev_b1.py` **a partir de la placa entregada, sin modificarla**:
- `corregida/CAMBIOS.diff` contiene el diff de la fuente;
- `corregida/aplicar_salida.txt` lista el cobre quitado y añadido y los cambios de la BOM.

Los ficheros entregados de la REV B (`out/C3/`) **no se tocan**.

**Cobre:**
- **U2 pin 5 (EN2):** pasa de CHG_EN2 a **GND**, con un tramo nuevo hasta el EPAD (igual que los pines 4 y 8).
- **U2 pin 6 (EN1):** pasa de GND a **VSYS**, con un tramo de 0,2 mm hasta la vía de VSYS que tiene debajo, a ≥ 0,24 mm de
  los pads 5 y 7. EN1 es una entrada lógica (máx. abs. 7 V; VSYS ≤ 4,4 V). Mientras VSYS no sube, EN1 vale 0 y el
  cargador empieza en USB100, que también tiene VIN-DPM.
- **R8:** se queda sin función y pasa a **DNP**. La pista del pin 5 a R8.1 se conserva y pasa a GND. Sus pads llevan
  pasta, lo que es inocuo.
- **No se mueve ninguna pieza.** Hay **15 cambios de tramos** (3 de GND quitados, 9 de CHG_EN2 que pasan a GND y 3 nuevos)
  y 3 pads cambian de red (U2.5, U2.6 y R8.1).

**Valores** (sin cambios de cobre):
- **C41 220 nF → 470 nF** (0402).
- **R40 1 M → 100 k** (pieza que ya está en la BOM).

**Revisión «B.1»** en el cajetín y en la serigrafía.

**Atención:** la fuente de `fuente/` no se ha cambiado. Si se regenera la placa desde la fuente, los tramos de cobre de
la REV B.1 hay que pasarlos a mano a `fuente/`; están descritos en `aplicar_rev_b1.py`.

### 13.3 Comparación antes/después

| | REV B (entregada) | REV B.1 (propuesta) |
|---|---|---|
| ERC | 0 errores / 0 avisos | **0 / 0** |
| DRC con paridad (zonas rellenadas con pcbnew) | 0 violaciones / 0 sin conectar / 0 huellas | **0 / 0 / 0** |
| Diferencias esquema ↔ placa | 0 | **0** |
| Redes y vías | 84 redes, 164 vías | 83 redes (desaparece CHG_EN2), 164 vías |
| Modo del BQ24072 | ILIM (EN2 = 1, EN1 = 0): sin VIN-DPM | **USB500** (EN2 = 0, EN1 = 1): VIN-DPM de 4,35–4,63 V |
| Límite de entrada | 399–526 mA (R7 = 3,3 k) | 450–500 mA (interno) |
| Corriente de carga | 239–298 mA | igual |
| Ventana sin PWR_HOLD, peor caso (celda 3,3 / 3,7 / 4,2 V) | 2,90 / 3,59 / 4,35 s | **2,56 / 3,34 / 4,20 s** |
| Reinicio del ESP32, peor caso | aguanta 0,3 s; cae con 0,6 s | **aguanta 0,3, 0,6, 1,0 y 1,5 s** |
| Monte Carlo (200): ventana mín. / caídas en el reinicio de 0,6 s | 3,49 s / 3 | **3,03 s / 0** (3V3 mín. 2,91 V) |
| Apagado tras PWR_HOLD = 0 (reed abierto) | 1,87 s | **3,99 s** |
| Apagado al quitar los 5 V | 2,66 s | **5,67 s** |
| Reencendido (5 casos) | se engancha en los 5 | **se engancha en los 5** |
| Consumo apagado con el reed cerrado | 7,7 µA | **7,7 µA** |
| Cajetín y Gerber | «A» | **«B.1»** (`TF.ProjectId …,B.1`, `"Revision": "B.1"`) |
| Montaje | 85 piezas, 41 líneas de BOM, 356 soldaduras | 84 piezas (R8 DNP), 41 líneas (la de 220 nF pasa a 470 nF), 354 soldaduras |
| Aviso de `kicad_audit` | — | tramo de VSYS de 0,2 mm (< 0,3 mm para potencia): **aceptado**, porque solo alimenta la entrada EN1 (µA) |

Evidencias: `resultados_ci/rev_b1/` (`erc.rpt`, `drc.rpt`, `auditoria_placa.json`, `auditoria_redes.csv`,
`AVO_GIRTH_PCB_C3_REV_B1_GERBER_JLCPCB.zip`, `arriba.png`, placa con las zonas rellenas y existencias) y
`resultados_ci/spice_rev_b1/` (los mismos escenarios SPICE con C41 = 470 nF y R40 = 100 k).

---

## 14. Pruebas físicas pendientes (orden recomendado con las 2 placas)

1. **Inspección.** Inspección visual y por rayos X (U1, U2, U4, U5, U7); polaridad de D1, J2 y U6; giros del CPL frente a
   la placa.
2. **Consumo apagado.** Sin batería, con una fuente de laboratorio limitada a 100 mA en BAT_RAW: ≤ 2 µA fuera del soporte
   y ≈ 7–8 µA con el reed cerrado; repetir en caliente (R-15).
3. **Encendido con el reed.** Pico de corriente con la celda real y su protección (R-7); ventana sin PWR_HOLD.
4. **Primer arranque del firmware.** Tiempo hasta PWR_HOLD (R-16); apagado fuera del soporte (≈ 2 s en la REV B o
   ≈ 4 s en la B.1, después de los 3 s del firmware).
5. **Reinicio por vigilante sin 5 V.** ¿Se mantiene PWR_HOLD con `gpio_hold_en`? (R-2).
6. **Caída de la 3V3 en TX** con la celda a 3,4 y a 3,3 V, con osciloscopio (R-6).
7. **USB-C:** enumeración, grabación y carga por USB.
8. **Bobina Qi:**
   - Ls y Ls′ con un medidor LCR a 100 kHz;
   - ajuste de C1/C2;
   - carga Qi con el transmisor real y su comunicación (comparar REV B y B.1 si se monta alguna REV B);
   - FOD (H-1, H-3, H-5, H-6).
9. **Temperaturas** de U1, U2 y la celda cargando dentro de la cápsula (H-4, H-12).
10. **Sensores:** WHO_AM_I, ruido en reposo, orientación de los ejes y saturación con los imanes montados (R-9).
11. **ESP-NOW con la espalda:** pérdidas, alcance con la antena W.FL, reconexión, cambio de canal, y duplicados y
    desorden con radio real (R-10, R-12).
12. **Autonomía real** con la celda de 500 mAh (R-13).
13. **Mecánica** con la cápsula REV 5.9: cierre, junta (IP67), vibración y acceso al USB-C (R-5).

---

## 15. Veredicto final

## **APTO PARA PROTOTIPOS CON RIESGOS IDENTIFICADOS**

**Por qué es apto para fabricar 5 PCB y montar 2:**

- **KiCad (VERIFICADO MEDIANTE HERRAMIENTA).**
  - ERC y DRC sin errores, con paridad, también tras rellenar las zonas otra vez con pcbnew.
  - 0 diferencias pad a pad entre el esquema y la placa.
  - Los Gerber entregados son idénticos a los regenerados.
- **Fabricación (VERIFICADO MEDIANTE HERRAMIENTA).** BOM, CPL y placa coherentes, y hoy hay existencias de todas las
  piezas para 2 placas.
- **Alimentación y encendido magnético (SIMULADO, con modelos conservadores).**
  - Enciende con margen: ventana ≥ 2,9 s (REV B) o ≥ 2,56 s (REV B.1) en el peor caso, frente a los 0,5 s supuestos
    para el arranque.
  - Se apaga sola fuera del soporte y vuelve a encender.
  - No se queda bloqueada en ninguno de los escenarios simulados.
  - Apagada consume ≤ 2 µA según las hojas de datos.
- **Firmware (VERIFICADO MEDIANTE HERRAMIENTA).**
  - Compila y pasa todas las pruebas automáticas.
  - La cadena de 9 canales llega íntegra al receptor real de la espalda.
  - Su imagen arranca en QEMU hasta el inicio de ESP-IDF.
- **Ningún error de hardware** impide el funcionamiento básico en banco: USB, arranque, sensores y ESP-NOW.

**Por qué no es «APTO PARA PROTOTIPOS» sin más:**

- **Qi:**
  - el modo del cargador no es el que pide el BQ51013B (R-1);
  - la bobina no está definida (R-3);
  - las NTC no protegen la celda (R-4).
- **Enclavamiento:** en el peor caso de tolerancias puede soltarse en un reinicio de 0,3–0,6 s (R-2).
- **Mecánica:** la cápsula actual no cierra ni sella (R-5). Es un cambio del CAD, no de la PCB.
- **Arranque real del firmware:** QEMU no llega a `setup()`, así que no está comprobado (R-16).
- **No validable por software:** radio, temperatura, mecánica real y celda real.

**Por qué no es «NO APTO»:**

- Ninguno de esos riesgos es un error de la PCB que la deje inservible o peligrosa en banco con la carga vigilada.
- Los dos que tocan a la placa y se pueden corregir sin rediseñarla (R-1 y R-2) ya tienen corrección en la REV B.1, con
  la misma colocación, ERC/DRC/paridad limpios y el mismo coste salvo una pieza.
- Lo que esas correcciones logran está **simulado o revisado en las hojas de datos, no medido**.

**Recomendación:**

1. Pedir la **REV B.1** (Gerber, BOM y CPL de la sección 9) en lugar de la REV B, revisando los giros en la vista previa
   de JLCPCB.
2. Comprar la bobina TDK WR202010-18M8-ID (o medir la que se vaya a usar) antes de probar el Qi.
3. Cargar los prototipos solo bajo vigilancia hasta resolver R-4.
4. Hacer las pruebas físicas de la sección 14 en ese orden.

El diseño **no está validado al 100 %**.
