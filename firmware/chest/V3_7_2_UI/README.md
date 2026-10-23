# AVO CHEST V3.7.2-rc1 — pantalla de siete franjas legible (sin LVGL)

**Estado: SIN VERIFICAR EN EL RELOJ.** Compila en GitHub Actions y pasa las comprobaciones en el
ordenador (simulación del panel), pero falta verlo en el Waveshare ESP32-S3 Touch AMOLED 2.06".

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
- `ui_assets.h`: fuentes e iconos generados (`tools/gen_ui_assets.py`), **78 KB en flash, 0 B de RAM**.
- RAM interna nueva: solo un búfer de envío de 13 KB. **LVGL no se usa.**
- Solo se envían al panel las franjas que cambian. Con la SD grabando, **solo parpadea el punto rojo** (500 ms), sin redibujar la franja amarilla.

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
