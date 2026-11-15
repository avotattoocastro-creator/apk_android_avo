# AVO SYNC v1: vídeo con hora GPS (gadget BLE + página «Cámara» del iPad)

**Estado (15/11/2026):**
- **Página «Cámara» del iPad:** IMPLEMENTADA. Compilación y pruebas en CI pendientes. **NO VERIFICADA** en iPad real.
- **Gadget:** no existe. No hay firmware, PCB ni caja.

Mientras no haya gadget, la app graba con el reloj del iPad y lo indica en pantalla y en el archivo.
Las cifras marcadas **(E)** son estimaciones; nada está medido.

## 1. Idea
- El caballo graba en su microSD con la hora GPS del ZED-F9P, como siempre.
- El iPad graba el vídeo y guarda, para cada fotograma, su hora GPS. Esa hora se la da un gadget pequeño (GPS con PPS +
  ESP32-C3) por Bluetooth a 1–3 m.
- Después las dos cosas se juntan por la hora.
- Funciona con el caballo lejos (playa): **no se transmite nada del caballo durante la grabación**.

## 2. Contrato BLE AVO SYNC v1 (nuevo, independiente)
No toca `TELEMETRY v3`, `BackStatus v3`, lotes de cincha, `AVO1` ni `.avr`. Fuente única en la app: `ipad/AVOiPad/Core/AvoSync.swift`.

| | UUID |
|---|---|
| Servicio AVO SYNC | `09F575BC-1C6E-451D-8257-4EBF6B42E3CB` |
| RX (iPad → gadget, escritura sin respuesta) | `F89FCE07-E7A8-4527-AF87-5320C18F48FD` |
| TX (gadget → iPad, notificaciones) | `0C80602B-9074-40F3-94B0-B99E280303A2` |

Tramas little-endian, tamaño fijo, `ver = 1` en el byte 0, tipo en el byte 1:

| Trama | Dir. | Tamaño | Campos |
|---|---|---|---|
| `TIME_REQ` (1) | iPad → gadget | 16 B | ver u8 · tipo u8 · seq u16 · rsv u32 · t1_ns u64 (reloj del iPad) |
| `TIME_RESP` (2) | gadget → iPad | 32 B | ver · tipo · seq u16 · flags u8 (b0 fix, b1 hora válida, b2 PPS bloqueado, b3 en retención) · sats u8 · rsv u16 · t1_ns u64 (eco) · t2_utc_ns u64 · t3_utc_ns u64 |
| `MARK` (3) | gadget → iPad | 16 B | ver · tipo · seq u16 · marca u16 (1 serie, 2 vuelta, 3 fin) · rsv u16 · utc_ns u64 |
| `STATUS` (4) | gadget → iPad, cada 5 s | 16 B | ver · tipo · batería_mV u16 · batería_% u8 · fix u8 · sats u8 · flags u8 · hAcc_mm u32 · uptime_s u32 |

- `utc_ns` son nanosegundos desde 1970-01-01 UTC, sin segundos intercalares.
- El gadget debe anotar t2 al recibir `TIME_REQ` y t3 justo antes de notificar.
- La hora se calcula con la recta PPS (`UTC = a · t_esp + b`) ajustada con NAV-PVT.

## 3. Cálculo en el iPad
- Cada segundo hay un intercambio tipo NTP:
  - `offset = ((t2 − t1) + (t3 − t4)) / 2`
  - `retardo = (t4 − t1) − (t3 − t2)`
- t4 se anota en la cola BLE propia, antes de pasar a la cola principal.
- Se descartan las muestras con retardo > 250 ms y las que llegan sin «hora válida».
- De cada ventana de 10 s se queda la muestra de **menor retardo**.
- La recta por mínimos cuadrados absorbe la deriva del reloj del iPad. Pendientes > 200 ppm se tratan como ruido.
  - En pantalla, la recta usa los últimos 5 min.
  - En el archivo del vídeo, usa hasta 2 h.
- **Precisión (E):** ± (retardo mínimo / 2 + dispersión). Se espera 1–5 ms (E), pero **hay que medirla** con la prueba del LED a 240 fps.
- La app **no cambia el reloj del iPad**. Cada fotograma conserva su sello del reloj del iPad (`host_ns`, el mismo dominio
  que `mach_absolute_time`), y la hora GPS se calcula con la recta.

## 4. Archivos de la página «Cámara»
Carpeta `videos/` de la app (Application Support/AVO Performance Horse/iPad):
- `AVO_VIDEO_AAAAMMDD_HHMMSS.mov`: HEVC, cámara trasera, 1080p o 4K a 30/60/120/240 fps según el iPad. Sin audio.
  El primer fotograma es t = 0 del archivo.
- `AVO_VIDEO_….avosync.json`, con estos campos:
  - `source` (`avo_sync` | `reloj_ipad`)
  - `first_frame_host_ns`, `last_frame_host_ns`, `first_frame_utc_ns`
  - `fit` (`ref_host_ns`, `offset_at_ref_ns`, `slope`) y `samples` (mínimos por ventana)
  - `error_bound_ms`, `min_delay_ms`, `spread_ms`, `holdover`
  - `marks` (tipo + `utc_ns`)
  - `system_clock_start` / `system_clock_end` (pares reloj del iPad ↔ hora del sistema)
  - `width`, `height`, `fps_nominal`, `frames`, `codec`, `gadget_name`, `app_version`

  **UTC del fotograma** = `host_ns` del fotograma + `offset(host_ns)` de la recta. Con `reloj_ipad` se usa la hora del
  sistema (NTP de iOS, decenas de ms (E)).

## 5. Página «Cámara» (iPad)
- En el menú lateral, debajo de «Análisis». Siempre activa, aunque no haya entrenamiento abierto.
- **Vista previa:** muestra la hora en directo (GPS en verde o reloj del iPad en amarillo) y el contador REC. El botón de
  grabar está abajo.
- **Recuadro AVO SYNC:** conectar o desconectar el gadget, hora válida o en retención, satélites, precisión (E), retardo
  mínimo, muestras, batería y hAcc.
- **Grabación:**
  - formato;
  - marcas «Serie», «Vuelta» y «Fin» con la hora actual. Las del botón del gadget llegan con su propia hora.
- **Vídeos grabados:**
  - fecha y hora de inicio, duración, formato y fuente de la hora;
  - reproducir, con la hora GPS del fotograma visible y saltos a las marcas;
  - compartir el vídeo y su `.json`;
  - borrar.
- Al salir de la página, o si la cámara se interrumpe o la app pasa a segundo plano, la grabación se para y se guarda.
- Permisos nuevos en `Info.plist`, avisado al usuario:
  - `NSCameraUsageDescription`;
  - `NSPhotoLibraryAddUsageDescription`, para «Guardar vídeo» desde Compartir.

## 5 bis. Vídeo con los datos del entrenamiento (desde el 15/11/2026)
- **Caballo:** se elige antes de grabar, en el panel. Se guarda en `horse` del `.avosync.json`.
- **Asociación al entrenamiento:**
  - Automática: el entrenamiento importado que coincide en hora con el tramo útil del vídeo, prefiriendo el del mismo caballo.
  - A mano: desde el reproductor, con «Automático», un entrenamiento de la lista o «Ninguno». Se guarda en `training_id`
    (`""` = ninguno).
- **Unión por la hora:** `t = t[0] + (UTC del fotograma − utc0)`. `utc0` es la hora UTC del GNSS de la espalda. Si el
  entrenamiento no la tiene, se usa la hora de inicio del reloj de pecho, menos exacta.
- **Indicadores elegibles** (botón «Datos», selección guardada en el iPad):
  - velocímetro, barra de distancia, recorrido con la posición, rumbo (brújula) y coordenadas;
  - aire, aceleración, aceleración lateral, tranco (frecuencia y longitud, motor + cincha), IMU de la cincha (vertical
    fusionada o |a|), altitud, calidad GNSS y hora GPS;
  - caballo y fecha;
  - pulso: aparece «sin datos», porque el ECG de la cincha (fmt 2) aún no se decodifica en el iPad.
- **Mismo dibujo en pantalla y en el exportado:** `VideoOverlayRenderer`, con Core Graphics.
- **Recorte no destructivo:** `trim_start_s` / `trim_end_s`, con agarres, «Inicio aquí», «Fin aquí» y «Quitar recorte».
  El `.mov` original no se toca.
- **Exportar con datos:** `AVAssetExportSession` + `AVVideoComposition` con Core Image.
  - HEVC, 24–60 fps (los vídeos a 120/240 fps se exportan a 60).
  - Respeta el recorte.
  - El resultado va a `videos/exportados/<vídeo>_datos.mov` y se puede «Guardar en Fotos» o compartir.

## 6. Pendiente
1. Gadget: prototipo XIAO ESP32-C3 + GPS con PPS (MAX-M10S recomendado) y firmware `firmware/sync/V0_1` con este contrato.
2. Pruebas del gadget (ninguna hecha):
   - PPS frente al ZED-F9P;
   - LED grabado a 240 fps para medir el error real y calibrar el retardo de la cámara;
   - 1 h de estabilidad;
   - playa a más de 500 m.
3. Pulso sobre el vídeo cuando el iPad decodifique el ECG de la cincha. Lista de vídeos dentro de cada entrenamiento
   (Análisis).
4. LED codificado e importación de vídeos externos (GoPro, dron).
5. Android y Windows (mismo contrato).
