# CHEST V3.7.5-usb1 — Descarga de entrenamientos al PC por USB (protocolo AVO1)

**Base:** 3.7.5-rc5 (la última con pruebas de campo). El parche también se aplica sin cambios sobre 3.7.6-rc1.
**BIN marcado UNVERIFIED:** compilado en CI, no probado en el reloj. Instalar con AVO Update por USB.

No cambia: formato RAW, grabación, BLE, ESP-NOW, NTRIP/RTCM, GNSS, OTA, Wi-Fi ni particiones. En la pantalla solo se añade la de «CONECTADO AL PC» (ver abajo); con un cargador todo sigue igual.

## Pantalla «CONECTADO AL PC»

- **Con un PC en el cable**, la pantalla de carga se sustituye por «CONECTADO AL PC». El PC se detecta por las tramas USB de inicio de trama que envía cada milisegundo (`Serial.isPlugged()`), o por haber recibido órdenes AVO1 en los últimos 30 s.
  - Debajo muestra el estado: «Abre AVO Windows», «Comparando entrenamientos», «Descargando 2 de 5» con barra y %, «Sincronizado · N entrenamientos nuevos» / «Todo está ya en el PC», «Descarga interrumpida» o «Grabando».
  - Abajo, la batería real.
- **Con un cargador o una batería externa** no hay tramas USB, así que se ve la **misma pantalla de carga de la 3.7.2, sin ningún cambio**.
- **Mismas reglas que la pantalla de carga:**
  - si se graba, se ven las siete tarjetas;
  - un toque corto enseña las tarjetas 30 s;
  - OTA y apagado tienen prioridad;
  - mismo brillo (15 s al máximo y luego atenuada).
- **Se mostraría también con otro equipo** que haga de anfitrión USB, como un móvil con AVO Update por OTG.
- **Vista previa:** el artefacto de CI `AVO-CHEST-V3-7-5-USB1-PANTALLA-PC-PREVIEW` se genera con el mismo código de dibujo (`host/pc_preview.cpp`).

## Funcionamiento

```
PC (AVO Windows) ──cable USB-C──► puerto serie USB del reloj (USB-Serial/JTAG, VID 303A · PID 1001)
  1. Windows avisa de la conexión (WM_DEVICECHANGE) o la app lo detecta en su comprobación de cada 4 s.
  2. La app busca los COM con VID_303A&PID_1001 y envía «AVO1 HELLO».
  3. LIST → compara con la biblioteca del PC → descarga los que faltan → SHA-256 → paquete .avo → importación.
```

- **Sin RAM interna nueva.** Se ejecuta en la tarea `loop` de Arduino, que hasta ahora solo dormía (`app_loop`). Los buffers (línea de entrada, respuesta y bloque de fichero, unos 10 KB) van en PSRAM.
- **Mismo puerto que el registro.** Cada respuesta es una sola línea `#AVO1 …\n` escrita con una sola llamada `write()`. Una línea de registro de otra tarea puede ir antes o después, nunca dentro. El PC ignora todo lo que no empiece por `#AVO1 `.
- **DTR y RTS a 0.** La app abre el puerto con las dos líneas bajas, la misma combinación que el monitor de AVO Update. Esa combinación nunca reinicia el ESP32-S3.
- **Solo lectura.** No escribe, renombra ni borra nada en la microSD.
  - No sirve sesiones `OPEN` (en grabación o interrumpidas sin recuperar).
  - No responde a LIST, SHA ni READ mientras se graba.
  - Las rutas se construyen solo con identificadores validados (`S[A-Za-z0-9_-]{1,22}`).
- **Mismo etag y SHA-256 que la descarga Wi-Fi** de la 3.7.4. El SHA-256 se calcula sobre los segmentos concatenados.

## Órdenes (PC → reloj, una línea ASCII, máx. 159 caracteres)

| Orden | Respuesta |
|---|---|
| `AVO1 HELLO` | `#AVO1 HELLO {"api":1,"name":"AVO-CHEST","fw","device","recording","sd","battery_pct","vbus","raw_format","max_read":4096}`. Responde también durante una grabación. |
| `AVO1 LIST` | una línea `#AVO1 T {"id","state","ready","segments","size","start_rtc_ms","active_ms","etag","sizes":[…]}` por sesión, y al final `#AVO1 END <n>` |
| `AVO1 SHA <id>` | `#AVO1 SHA {"id","sha256","size","etag"}` |
| `AVO1 PROGRESS <fase> <i> <n> <pct> <nuevos>` | `#AVO1 OK PROGRESS`. Solo para la pantalla del reloj. Fases: 1 comparando, 2 descargando i de n (pct %), 3 sincronizado (nuevos), 4 grabando, 5 interrumpida. Sin esta orden, el reloj muestra «Descargando» mientras recibe READ. |
| `AVO1 READ <id> <seg> <offset> <len> <etag>` | `#AVO1 DATA <seg> <offset> <n> <crc32 hex> <base64>`, con n ≤ 4096. Se recorta al final del segmento. |

**Errores:** `#AVO1 ERR <orden> <código>`.

| Código | Significado |
|---|---|
| `recording` | el reloj está grabando |
| `sd` | microSD no disponible |
| `id` | identificador no válido o inexistente |
| `open` | sesión sin cerrar |
| `segment` | segmento inexistente |
| `changed` | el etag ya no coincide |
| `range` | offset fuera del segmento |
| `io` | error de lectura de la microSD |
| `mem` | sin memoria libre |
| `cmd` | orden desconocida |

Las líneas que no empiezan por `AVO1 ` se ignoran. Las de más de 159 caracteres se descartan hasta el siguiente salto de línea.

## Lado Windows (AVO Windows V1.1)

- **Detección.** `ChestPortFinder` busca en el registro de Windows (`Enum\USB\VID_303A&PID_1001*`) los COM presentes. Se activa con `WM_DEVICECHANGE` y con la comprobación de cada 4 s.
  - Si hay que reconectar el reloj, basta con desenchufarlo y volverlo a enchufar.
  - Con el reloj grabando, la app pregunta cada 4 s y descarga cuando termina.
- **Comparación** (`ChestSync.Run`), entrenamiento a entrenamiento:
  - Ya está en el PC si aparece en `Documentos\AVO Performance Horse\Reloj\indice_reloj.json` con el mismo etag y tamaño.
  - Si el etag cambió, pero el tamaño no, o si el entrenamiento ya se importó como `.avo` de Android, se pide el SHA-256. Cuando coincide, no se descarga. Es el caso de un entrenamiento que el móvil ha marcado como subido.
- **Descarga.**
  - Bloques de 4 KB, con CRC-32 por bloque y 3 intentos ante un bloque dañado o una respuesta perdida.
  - Se reanuda desde el byte ya escrito (`.descargando\`) si se desconecta el cable.
  - Al final se comprueba el SHA-256 con el reloj. Si no coincide, se borra la copia parcial y no se guarda nada.
- **Resultado.** El paquete `AVO_<id>_<dispositivo>.avo` (formato AVO-TRAINING-1, igual que el de Android) se guarda en la carpeta y se importa en la lista.
  - Caballo y jinete quedan «Sin identificar»: el reloj no los guarda en la lista.
- **Interfaz.** En Inicio aparece la tarjeta «RELOJ POR USB», con el estado, el progreso, la carpeta y el botón SINCRONIZAR RELOJ. El mismo botón está en la cabecera.

## Pruebas

- **CI firmware** (`tests/test_usb_v375.py`): compila `usb_sync.cpp` real para el PC (`-DAVO_HOST_TEST`, `-Wall -Werror`) y lo usa como lo haría la app.
  - Lista, descarga con CRC y SHA-256.
  - Comprueba que no sirve sesiones OPEN y que rechaza el etag cambiado, el rango, el segmento inexistente, el recorrido de rutas (`../`), las órdenes desconocidas, el ruido, las líneas largas y la grabación.
  - Comprueba que la microSD queda intacta.
  - Además compila el BIN del ESP32-S3.
- **Transcripción compartida.** Las respuestas reales del firmware se guardan en `windows/AVO.Windows.SelfTest/usb_transcript.json`. La CI del firmware falla si dejan de coincidir; las autopruebas de Windows las reproducen.
- **CI Windows** (`AVO.Windows.SelfTest`):
  - transcripción del firmware real: descarga de 2 de 3 y segunda conexión sin lecturas;
  - reloj simulado con fallos:
    - CRC dañado y respuesta perdida (reintento);
    - paquete que se abre;
    - entrenamiento ya importado desde Android;
    - cambio de etag sin cambio de datos;
    - cable desconectado y reanudación desde el byte 8192;
    - grabación;
    - entrenamiento modificado durante la descarga;
    - SHA-256 distinto;
    - dispositivo que no es AVO.
- **Física: PENDIENTE (ninguna hecha).**
  1. Instalar `AVO_CHEST_V3_7_5_USB1_UNVERIFIED.bin` con AVO Update. En el monitor deben aparecer `usbsync OK` y `AVO-CHEST 3.7.5-usb1 ready`. Comprobar que `[AVO MEM] ready` no baja respecto a la rc5.
  2. Conectar al PC con la app abierta: se detecta en ≤ 5 s y descarga los entrenamientos. Que el reloj **no se reinicie** al abrir el puerto.
  3. Desconectar a mitad y volver a conectar: se reanuda y el SHA-256 coincide.
  4. Segunda conexión: «todos ya en el PC», sin descargas.
  5. Pantalla: con el PC sale «CONECTADO AL PC» y el progreso. Con un cargador de pared sale la pantalla de carga de siempre. Al desconectar del PC vuelve la pantalla de antes.
  6. Con el reloj conectado al PC, la espalda y el BLE del móvil siguen funcionando. Iniciar una grabación: la descarga se detiene.
  7. Medir la velocidad real (estimación: 200–500 KB/s) y anotarla.
