# AVO BACK V4 REV B · montaje, pruebas y riesgos pendientes

(REV A con Qi y Hall: ver este fichero en el commit `3883369`.)

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
| Imanes Ø5 × 1 | 6 en la cápsula + 6 en el soporte | (REV B: sin imanes de sensor) |
| **Contactos del fondo** | **3 × tornillo M2 × 5 avellanado inox A2 + 3 tuercas M2 + 3 juntas tóricas 2 × 1 NBR** | SYS (P1), BAT (P2), GND (P3) |
| **Pines con muelle del soporte del chaleco** | **2 × pin pogo Ø2,0 (≥ 5,5 mm, carrera ≥ 1 mm, ≥ 1 A)** + hilo del puente | bajo SYS y BAT, punta 0,8 mm sobre la cara |
| Base de carga | 2 pines pogo en BAT y GND + cargador Li-ion CC/CV 4,2 V ≤ 1 A con protección | (pieza aparte, no dibujada en la V4; ver la del prototipo E.6) |
| Junta tórica de la antena | 6 × 1 | torre de la tapa |
| PCB AVO BACK V4 REV B montada (JLCPCB) | 1 | |
| URTK1.2, adaptador SMA en L, antena Q39 | 1 | los actuales |
| Batería 654060 2000 mAh | 1 | **cambiar la clavija PH2.0 por JST SH 1,0 (2 vías)**, pin 1 = + |
| Antena FPC 2,4 GHz con conector del módulo (U.FL/IPEX) | 1 | pegada al techo de la tapa, en el cuello |
| Mazo de 8 hilos (AWG 28–30, ~60 mm) | 1 | URTK1.2 ↔ J4, según `INTEGRACION_GNSS.md` |

## Orden de montaje
1. **Probetas primero**:
   - **P1 (cola):** separadores, bolsillo de la PCB, **avellanados y ranuras de los contactos**, topes de la L en la
     tapa, torre, S5–S8 y gancho.
   - **P2 (cuello):** S1–S4, clics de la bandeja y labio.
   - Comprobar insertos, cabezas enrasadas y el encaje de la L.
2. **Base:**
   - Insertos de los 2 separadores.
   - Imanes de la cápsula, desde dentro.
   - Los 3 tornillos de contacto desde fuera, con la cabeza enrasada, y la junta tórica en su ranura interior.
3. **PCB en su bolsillo**, sobre los 2 pivotes, con los 3 tornillos pasando por P1/P2/P3. Poner las tuercas M2 sobre las
   coronas y apretarlas con suavidad: aplastan las juntas y sujetan la placa.
4. Batería en su cuna (cable hacia la cola, por el paso del extremo +X) y enchufada a J2.
5. Bandeja URTK sobre el marco de la batería; los 4 clics la sujetan.
6. Mazo soldado a la URTK1.2 (por la cara superior, sin que los hilos asomen por debajo más de 1 mm) y a J4.
7. Adaptador en L enroscado a J2 del ZED. URTK1.2 sobre la bandeja: los 2 pivotes entran en sus agujeros −X.
   **Anillos** sobre la PCB alrededor de los separadores; 2 × M3 × 6 por los agujeros +X de la URTK1.2.
8. Antena FPC al techo de la tapa (zona del cuello) y su cable al conector del módulo.
9. Junta TPU en su ranura; tapa (los topes de la L y la torre encajan en el cuerpo de la L); 8 tornillos en cruz.
10. Antena Q39 enroscada a la rosca de la L (4,4 mm libres).
11. **Soporte del chaleco:** soldar el hilo del puente entre las colas de los 2 pines; meterlos desde abajo por los
    agujeros SYS/BAT y pegarlos con epoxi (punta 0,8 mm sobre la cara); el hilo queda en el canal inferior.

## Primer encendido (antes de cerrar)
1. **Polímetro**:
   - BAT (cabeza de P2) ↔ + de la celda: a través de F1.
   - GND (P3) ↔ − de la celda.
   - SYS (P1) sin tensión.
2. **Puente SYS–BAT con una pinza** (como el soporte): 3,3 V en TP6 y 3,3 V en TP9 al encender el ZED.
3. USB-C: el PC debe ver el ESP32-S3 (USB Serial/JTAG). Instalar el firmware **4.0.0-dev2** (AVO Update o esptool).
4. Monitor:
   - `ALIMENTACION: soporte del chaleco (SYS-BAT)`;
   - `ZED: FUNCIONANDO … puerto=UART2`;
   - `PPS: OK` con fix;
   - `MICROSD: GRABANDO`.
5. Quitar el puente: la placa se apaga al instante; corriente de la celda ≈ la de su PCM (µA).
6. Base de carga (BAT–GND): sube la tensión de la celda con la placa apagada. Por USB-C con el puente: `cargando por USB`.
7. Emparejar: 3 puentes de menos de 4 s seguidos → `3 encendidos rápidos: emparejamiento abierto 120 s`.

## Verificado por software (este trabajo)
- **CAD** (B-Rep, FreeCAD 1.0.2):
  - 7 piezas válidas y cerradas; STEP releídos.
  - STL estancos, sin autointersecciones; ΔV STL/B-Rep < 0,06 %.
  - 0 interferencias no previstas con la electrónica, contando las envolventes de la PCB, los tornillos de contacto, las
    juntas y los pines del soporte.
  - 0 voladizos fuera de límite (capas de 0,2 mm).
- **PCB** (KiCad 9 en el CI): ver `PCB/out/` (ERC, DRC con paridad de esquema, puerta de fabricación).
- **Firmware 4.0.0-dev2:** compilado en el CI; 44 pruebas en el ordenador.

## Pendiente de prueba física (NO VERIFICADO)
| # | Riesgo | Qué hacer |
|---|---|---|
| 1 | **Pinout de la URTK1.2** tomado de la foto de la cara de componentes | polímetro antes del mazo (`INTEGRACION_GNSS.md`) |
| 2 | **Rebote del contacto SYS–BAT al galope** (un corte de ms reinicia la placa) | prueba de campo; si hay reinicios: pines con más carrera o más reserva en VSYS |
| 3 | **Estanqueidad de los 3 contactos** (junta tórica 2 × 1 apretada por la tuerca) | 1 m, 30 min, papel secante; probar antes en la probeta P1 |
| 4 | Contacto BAT siempre con tensión en el exterior | F1 (1,5 A) + PCM de la celda; BAT y GND separados ~30 mm; limpiar y secar tras cada uso |
| 5 | Corrosión inox A2 / pines dorados con sudor | medir la resistencia de contacto tras varias sesiones; si sube, cambiar a latón dorado |
| 6 | microSD: corte sin aviso al quitar la cápsula | el firmware vacía cada 1 s; comprobar que la tarjeta se lee tras 20 cortes |
| 7 | Componentes o patas bajo la URTK1.2 (hay 1,2 mm hasta la bandeja) | medir con calibre; si hace falta, rebajar la bandeja |
| 8 | Posición/altura de J1 (USB-C), J3 (GH) y J6 (pila) de la URTK1.2 (estimadas por foto) | medir; el techo tiene rebaje de 0,7 en el canto −X |
| 9 | Interferencia del ESP32-S3 y de la microSD con la antena GNSS (PCB debajo de la antena) | comparar C/N0 y tiempo a FIX con la Rev E en el mismo sitio |
| 10 | Alcance ESP-NOW/BLE con la antena FPC en el techo del cuello | prueba con pecho y cincha en el caballo |
| 11 | microSD Hirose DM3AT: pines 9/10 del interruptor de tarjeta (de la huella de KiCad) | hoja de Hirose; el firmware no depende de la polaridad |
| 12 | Batería: clavija cambiada a SH 1,0 (polaridad) | comprobar antes de enchufar |
| 13 | Firmware: falta BLE directo con Android, Wi-Fi para descargas y OTA firmada | siguientes versiones de la 4.0.x |
