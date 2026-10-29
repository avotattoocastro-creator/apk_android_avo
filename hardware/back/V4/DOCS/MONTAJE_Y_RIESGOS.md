# AVO BACK V4 · montaje, pruebas y riesgos pendientes

## Material
| Pieza | Cantidad | Nota |
|---|---|---|
| Tapa, base, bandeja URTK, soporte, contraplaca | 1 de cada | PETG, **sin soportes**, orientación ya dada en `CAD/STL` (tapa boca abajo, contraplaca boca abajo) |
| Anillos de los separadores | 2 | PETG (están en el mismo STL) |
| Junta perimetral | 1 | TPU 95A |
| Tornillos de cierre | 8 × M3 × 10 cabeza cilíndrica (DIN 912) | + 8 juntas tóricas NBR 3 × 1 bajo la cabeza (como la Rev E) |
| Insertos de la tapa | 8 × M3 ≤ 5 mm (taladro Ø4,0 × 5,5) | |
| Separadores de la URTK1.2 | 2 insertos M3 ≤ 5 mm en la base + 2 × M3 × 6 | lado +X de la URTK1.2 |
| Soporte → contraplaca | 6 insertos M3 ≤ 4 mm + 6 × M3 × 8 avellanados | como la Rev E |
| Imanes Ø5 × 1 | 6 en la cápsula + 6 en el soporte + **3 bajo el Hall** en el soporte | |
| Junta tórica de la antena | 6 × 1 | torre de la tapa |
| PCB AVO BACK V4 montada (JLCPCB) | 1 | |
| URTK1.2, adaptador SMA en L, antena Q39 | 1 | los actuales |
| Batería 654060 2000 mAh | 1 | **cambiar la clavija PH2.0 por JST SH 1,0 (2 vías)**, pin 1 = + |
| Bobina Qi 30 × 23 | 1 | la actual; hilos soldados a L1/L2 |
| Antena FPC 2,4 GHz con conector del módulo (U.FL/IPEX) | 1 | pegada al techo de la tapa, en el cuello |
| Mazo de 8 hilos (AWG 28–30, ~60 mm) | 1 | URTK1.2 ↔ J4, según `INTEGRACION_GNSS.md` |

## Orden de montaje
1. **Probetas primero**: P1 (cola: separadores, bolsillo de la PCB, topes de la L en la tapa, torre, S5–S8, gancho) y
   P2 (cuello: S1–S4, clics de la bandeja, labio). Comprobar insertos, cabezas enrasadas y el encaje de la L.
2. Base: insertos de los 2 separadores; imanes de la cápsula (desde dentro).
3. Bobina Qi en su alojamiento bajo la PCB, ferrita hacia arriba; hilos hacia L1/L2.
4. PCB en su bolsillo, sobre los 2 pivotes. Soldar los hilos de la bobina.
5. Batería en su cuna (cable hacia la cola, por el paso del extremo +X) y enchufada a J2.
6. Bandeja URTK sobre el marco de la batería; los 4 clics la sujetan.
7. Mazo soldado a la URTK1.2 (por la cara superior, sin que los hilos asomen por debajo más de 1 mm) y a J4.
8. Adaptador en L enroscado a J2 del ZED. URTK1.2 sobre la bandeja: los 2 pivotes entran en sus agujeros −X.
   **Anillos** sobre la PCB alrededor de los separadores; 2 × M3 × 6 por los agujeros +X de la URTK1.2.
9. Antena FPC al techo de la tapa (zona del cuello) y su cable al conector del módulo.
10. Junta TPU en su ranura; tapa (los topes de la L y la torre encajan en el cuerpo de la L); 8 tornillos en cruz.
11. Antena Q39 enroscada a la rosca de la L (4,4 mm libres).

## Primer encendido (antes de cerrar)
1. Fuente limitada a 150 mA en lugar de la batería: medir **3,3 V (TP6)** y **0 V en 3V3_ZED (TP9)** con la cápsula
   fuera del soporte.
2. USB-C: el PC debe ver el ESP32-S3 (USB Serial/JTAG). Instalar el firmware **4.0.0-dev1** (AVO Update o esptool).
3. Imán bajo el Hall: «SOPORTE (Hall): EN EL SOPORTE» y 3,3 V en TP9 (ZED encendido).
4. Monitor: `ZED: FUNCIONANDO … puerto=UART2`, `PPS: OK` con fix, `MICROSD: GRABANDO`.
5. Carga: base Qi y USB → `alimentacion externa SI`, `cargando`; medir la corriente de carga (≈ 0,45 A).
6. Sueño: quitar el imán 3 s → consumo total < 100 µA.

## Verificado por software (este trabajo)
- CAD (B-Rep, FreeCAD 1.0.2): 7 piezas válidas y cerradas; STEP releídos; STL estancos, sin autointersecciones,
  ΔV STL/B-Rep < 0,06 %; 0 interferencias no previstas con la electrónica (envolventes de la PCB incluidas);
  0 voladizos fuera de límite en las piezas (capas de 0,2 mm). Tornillos 1,8–2,3 mm por dentro de la junta.
- PCB (KiCad 9 en el CI): ver `PCB/out/` (ERC, DRC con paridad de esquema, puerta de fabricación).
- Firmware 4.0.0-dev1: compilado en el CI (ESP32-S3, 1,0 MB = 30 % de app0); 44 pruebas en el ordenador.

## Pendiente de prueba física (NO VERIFICADO)
| # | Riesgo | Qué hacer |
|---|---|---|
| 1 | **Pinout de la URTK1.2** tomado de la foto de la cara de componentes | polímetro antes del mazo (`INTEGRACION_GNSS.md`) |
| 2 | Componentes o patas bajo la URTK1.2 (hay 1,2 mm hasta la bandeja) | medir con calibre; si hace falta, rebajar la bandeja |
| 3 | Posición/altura de J1 (USB-C), J3 (GH) y J6 (pila) de la URTK1.2 (estimadas por foto) | medir; el techo tiene rebaje de 0,7 en el canto −X |
| 4 | Inductancia de la bobina Qi: condensadores de resonancia C1–C4 supuestos (como la cincha) | medir L de la bobina y ajustar |
| 5 | Calentamiento con Qi + carga a 0,45 A dentro de la cápsula cerrada | medir temperatura de U1/U2 a los 30 min |
| 6 | Interferencia del ESP32-S3 y de la microSD con la antena GNSS (PCB debajo de la antena) | comparar C/N0 y tiempo a FIX con la Rev E en el mismo sitio |
| 7 | Alcance ESP-NOW/BLE con la antena FPC en el techo del cuello | prueba con pecho y cincha en el caballo |
| 8 | Hall DRV5032: pinout DBZ (1 VDD · 2 OUT · 3 GND) y disparo con los 3 imanes a ~3 mm | comprobar con la hoja de TI y en P1 |
| 9 | microSD Hirose DM3AT: pines 9/10 del interruptor de tarjeta (de la huella de KiCad) | hoja de Hirose; el firmware no depende de la polaridad |
| 10 | Estanqueidad (8 tornillos; tramo de 53 mm entre S3 y S5) | 1 m, 30 min, papel secante |
| 11 | Sujeción de la PCB por 2 anillos + 2 pisadores + 2 pivotes al galope | prueba de vibración / campo |
| 12 | Batería: clavija cambiada a SH 1,0 (polaridad) | comprobar antes de enchufar |
| 13 | Firmware: falta BLE directo con Android, Wi-Fi para descargas y OTA firmada en la V4 (el núcleo actual recibe el RTCM a través del pecho, como la 3.11.0) | siguientes versiones de la 4.0.x |
