# AVO CHEST V3.7.2-rc1 — pantalla de siete franjas legible (sin LVGL)

**Estado:** primera prueba física el 23-10-2026 (fotos del usuario): orientación correcta, texto legible, BLE,
espalda, GPS DGNSS y SD funcionando con la nueva pantalla. Correcciones de esa prueba en curso (ver registro).

## Qué fallaba en 3.7.1-rc2 (foto del 23-10-2026)
| Problema | Causa | Corrección |
|---|---|---|
| Imagen girada 180° (BATERÍA arriba, texto del revés) | `setRotation(0)` con el panel montado al revés en la caja | Giro de 180° **por software** al enviar píxeles; el controlador sigue en rotación 0 con su desplazamiento de columna de 22 px (con `setRotation(2)` ese desplazamiento pasaría a 0 y la imagen se movería 22 px) |
| Texto ilegible | Fuente interna 5×7 a escala 1–2 (6–14 px) | Fuentes Barlow Condensed suavizadas de 17 a 96 px |
| Bordes en escalera | Arduino_GFX dibuja con anchos impares y el CO5300 exige columnas y filas pares | Todo envío al panel se alinea a pares |
| Iconos toscos | Líneas de 1 px | Iconos Font Awesome suavizados (caballo, chaleco, satélite, SD…) |

## Arquitectura y memoria
- `ui_fb`: framebuffer RGB565 de 410×502 en **PSRAM** (402 KB de 8 MB), primitivas suavizadas, texto UTF-8, envío con giro de 180° y alineación par.
- `ui_dash`: diseño de las siete franjas y de las pantallas OTA, apagado y carga.
- `ui_model`: traduce el estado real (`AppSnapshot`) a cada franja según `V3_5_9/UI_7_FRANJAS_ESPECIFICACION.md`. Los datos caducados nunca se muestran como OK.
- `ui_assets.h`: fuentes e iconos generados (`tools/gen_ui_assets.py`), **148 KB en flash, 0 B de RAM**.
- RAM interna nueva: solo un búfer de envío de 13 KB. **LVGL no se usa.**
- Solo se envían al panel las franjas que cambian. Con la SD grabando, **solo parpadea el punto rojo** (500 ms), sin redibujar la franja amarilla.

## Pantalla de carga (USB)
Aparece al conectar USB salvo que se esté grabando (entonces se ven las franjas). Un **toque corto** alterna
30 s con las franjas. Anillo con extremos redondeados y halo, icono de batería con nivel real y rayo
cuando el cargador carga, porcentaje grande y «CARGANDO USB» / «CARGA COMPLETA» / «USB CONECTADO»
(cargador inactivo). Todo sale del PMIC AXP2101; nada se estima.
**Brillo con USB:** máximo (255) durante 15 s al conectar, al tocar la pantalla o al pulsar BOOT/POWER; después
se atenúa a 25. Al desconectar el cargador se vuelve al brillo configurado y se repintan las siete franjas completas.

## Esquinas curvas de la pantalla
El área visible (panel + ventana de la caja AVO) tiene esquinas de ~120 px de radio (estimado con fotos del reloj,
`PANEL_R` en `ui_dash.h`). Las franjas 1 y 7 siguen esa curva y su contenido se desplaza 24 px hacia dentro
(sin el icono pequeño de la derecha). La vista previa comprueba que **ningún píxel de texto o icono** queda fuera
del área visible y genera imágenes `*_contorno.png` con el contorno estimado en rojo. Si en el reloj aún se corta
algo, basta ajustar `PANEL_R` y `EDGE_INSET_X`.

## Pantalla de apagado seguro
Al mantener POWER: icono, «APAGANDO...», «Guardando entrenamiento» y una barra de **cuatro fases reales**
publicadas por `controlled_shutdown()`: 1 detener sesión, 2 cerrar archivos SD, 3 guardar caja negra, 4 apagar.
Si la SD no se puede cerrar, el firmware ya cancelaba el apagado; ahora además se muestra
«NO SE PUDO GUARDAR — El reloj sigue encendido» durante 6 s.

## Cambios fuera de la pantalla (mínimos)
`tools/apply_v372.py`: dos campos en `PowerState` y seis líneas en `controlled_shutdown()` que publican la fase,
más 300 ms antes de cortar la alimentación para que se vea la última fase. **No se modifica** BLE, ESP-NOW,
UART, NTRIP/RTCM, GNSS, OTA ni el almacenamiento; el orden del apagado es el mismo.

## Colores (estados reales)
BLUETOOTH, CHALECO, ESPALDA y CINCHA: verde OK / rojo fallo. GPS: rojo sin GNSS, azul GNSS autónomo,
verde con correcciones NTRIP aplicadas. SD: rojo error/ausente, verde disponible, amarillo grabando.
Batería: verde >50 %, amarillo 21–50 % (o desconocida «--%»), rojo ≤20 %; «Cargando...» solo si el cargador está cargando.

## Vista previa
`host/preview.cpp` compila el mismo código de dibujo con un panel simulado y genera imágenes PNG
(artefacto `AVO-CHEST-V3-7-2-RC1-UI-PREVIEW` en Actions). Los valores de esas imágenes son **entradas de prueba**;
el firmware solo muestra datos reales.

## Pendiente de verificar en el reloj
1. Orientación correcta (BLUETOOTH arriba) y ningún desplazamiento lateral.
2. Esquinas de las franjas superior e inferior dentro de las esquinas redondeadas del panel.
3. Parpadeo del punto rojo al grabar y fluidez general.
4. Memoria: línea `[AVO MEM] UI V3.7.2` en el registro serie (RAM interna y PSRAM libres).

## Licencias
Barlow Condensed: SIL OFL 1.1 (`licenses/BarlowCondensed-OFL.txt`, google/fonts e7db6ca).
Font Awesome Free 7: fuentes SIL OFL 1.1, iconos CC BY 4.0 (`licenses/FontAwesome-Free-LICENSE.txt`, FortAwesome/Font-Awesome 14c65a3).
