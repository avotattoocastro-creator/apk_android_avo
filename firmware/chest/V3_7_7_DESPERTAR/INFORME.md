# AVO CHEST 3.7.7 DESPERTAR

Rama `feature/chest-3-7-7-despertar-espalda`, creada desde `feature/chest-v3-7-6-gnss-quality` (la 3.7.6 instalada).
Cadena: 3.7.6 GNSS QUALITY → `V3_7_7_DESPERTAR/tools/apply_v377.py` → versión `3.7.7` / `0x030707`.
Workflow: `.github/workflows/build-chest-v377-despertar.yml`.

Estado: **IMPLEMENTADO · NO VERIFICADO en el reloj.**

## 1. Sueño de la espalda (necesita BACK ≥ 3.14.0)
- **Al apagar el reloj** (`controlled_shutdown`, también por batería crítica): con la SD ya cerrada y justo antes de
  cortar el AXP2101, manda a la espalda la orden `BACK_SLEEP` (8) dos veces, separadas 150 ms. La espalda contesta el ACK
  y se duerme. Si el cierre de la SD falla, el reloj sigue encendido y no se manda.
- **Baliza de despertar:** mientras el reloj tiene espalda emparejada pero el enlace está caído (más de 2 s sin oírla),
  manda cada 100 ms un paquete DATA corto (una trama HEARTBEAT) a su espalda, en un solo intento. La espalda dormida
  escucha 160 ms cada 10 s y arranca al oírlo. Coste: unos 10 paquetes por segundo de ~40 B en el canal 1; el RTCM
  no se manda mientras no hay enlace, así que no compite.
- Con una espalda anterior a la 3.14.0 la orden 8 recibe NACK (orden desconocida) y no pasa nada.

## 2. Descarga por Wi-Fi
- **Causa encontrada (probable) de los fallos:** el bloqueo de seguridad «el reloj se reinició al encender el AP»
  (NVS `wifi_off`) era **para siempre**: sobrevivía a cualquier actualización de firmware y ninguna app lo levantaba
  (Android no manda `WIFI_SYNC 5`). El reinicio en bucle de la 3.7.4-wifi-rc1 lo dejó puesto: desde entonces todos los
  firmwares rechazan el Wi-Fi («radio del reloj») y la app pasa a Bluetooth.
- **3.7.7:** el bloqueo guarda qué firmware lo puso (`wifi_off_fw`). Al arrancar con otro firmware (o si lo puso uno
  anterior a la 3.7.7, que no lo guardaba) se borra y el Wi-Fi vuelve. Si **esta** versión se reinicia al encender el AP,
  se vuelve a bloquear igual que antes.
- Motivos de rechazo separados por BLE: `6` = bloqueado tras un reinicio, `7` = poca RAM interna (antes los dos eran `4`).
  El monitor serie dice cuál fue.

## 3. Bluetooth con varios móviles
- **Causa encontrada:** NimBLE-Arduino 2.5.1 guardaba como máximo **3 vínculos y 8 CCCD** (`nimconfig.h`). Cada móvil se
  suscribe a 3 notificaciones (CTRL_TX, TELEM y FILE). Con el tercer móvil se llenaba el almacén de CCCD y NimBLE
  (`ble_store_util_status_rr`) **borraba el vínculo del móvil más antiguo**. Ese móvil seguía teniendo su clave: al
  volver, el cifrado fallaba y se desconectaba enseguida; la app no lo arreglaba sola porque Android seguía diciendo
  «vinculado».
- **3.7.7:** `-DCONFIG_BT_NIMBLE_MAX_BONDS=6 -DCONFIG_BT_NIMBLE_MAX_CCCDS=20` en `build_chest.sh` (6 móviles × 3).
  RAM interna estática: unos +0,9 KB (estimado).
- Un móvil que ya perdió su vínculo necesita olvidar el reloj en Ajustes › Bluetooth una vez, o la app Android
  ≥ 2.8 (que lo hace sola).

## 4. Sin cambios
RAW/SD, sesiones y geocercas, tramas ESP-NOW (la baliza es una trama HEARTBEAT normal), NTRIP/RTCM, GNSS, pantallas,
USB AVO1, OTA, particiones. Todas las pruebas de la 3.7.6 pasan sobre el árbol 3.7.7 + `test_despertar_v377.py`.

## 5. Instalación
AVO Update por USB, igual que la 3.7.6 (imagen de aplicación). La 3.7.6 no tiene sufijo, así que la 3.7.7 también se
puede firmar para OTA con AVO Signer si se quiere.

## 6. Verificación física pendiente
1. Monitor serie: `AVO-CHEST 3.7.7 ready`. Anotar `[AVO MEM] ready` y comparar con la 3.7.6.
2. Con la espalda 3.14.0: apagar el reloj → la espalda debe dormirse en ≤ 1 s (`A DORMIR (el pecho se apaga…`).
3. Encender el reloj → la espalda debe arrancar en ≤ 10 s y enlazar (`[SUENO] despierta: pecho encendido oido…`).
4. Wi-Fi: en el monitor, `Wi-Fi block left by firmware … cleared` (si estaba bloqueado) y descarga por Wi-Fi correcta.
5. Bluetooth: vincular 3–4 móviles distintos y comprobar que el primero sigue conectando.

## 7. 3.7.8 VINCULAR (encima de la 3.7.7)
Petición del usuario: 3 pulsaciones rápidas del botón BOOT (USER) ponen el reloj en modo «conectar un móvil».
Parche: `firmware/chest/V3_7_8_VINCULAR/tools/apply_v378.py` (el mismo workflow compila ya la 3.7.8).
- `BootButton` tiene un evento nuevo `TRIPLE` (3 pulsaciones, cada una a menos de 350 ms de la anterior). La doble
  pulsación (volver a la pantalla principal) se reconoce ahora 350 ms después de soltar, por si llega la tercera.
- **3 pulsaciones → modo vincular durante 120 s** (otra triple pulsación lo cierra):
  - si hay un móvil conectado, se desconecta y queda bloqueado durante la ventana, para que su reconexión automática
    no vuelva a quedarse con el reloj (el reloj solo admite un móvil a la vez);
  - el reloj se anuncia de nuevo por Bluetooth;
  - la petición de autorización del móvil nuevo («Autorizar» en la app) se confirma sola: la triple pulsación ya es la
    confirmación física, no hace falta pulsar BOOT otra vez;
  - la ventana se cierra al autorizar el móvil nuevo o a los 120 s.
- Pantalla: la tarjeta Bluetooth dice **MODO VINCULAR** mientras dura.
- Pruebas: `tests_test_vincular_v378.py` (estática) y `host/bootbutton_host.cpp` (pulsación, doble, triple y larga).

## 8. 3.7.9 CARGA (encima de la 3.7.8)
Prueba del usuario (09/11): al conectar el pecho a cargar se despertaba la espalda. Con USB el AXP2101 enciende el reloj,
el firmware arranca (pantalla de carga) y la 3.7.7 emitía la baliza de despertar.
- Con USB y **sin grabar** («retención por carga»):
  - si la espalda está enlazada, se le manda `BACK_SLEEP` (dos veces) y, 1,5 s después, el pecho deja de transmitirle;
  - si no está enlazada, el silencio es inmediato;
  - en silencio no hay baliza ni paquetes DATA (latido, CAPS, órdenes se descartan), así que una espalda dormida no
    lo oye nunca.
- Al quitar el USB (o al empezar a grabar) vuelve la baliza y la espalda se despierta en ≤ 10 s.
- Parche: `firmware/chest/V3_7_9_CARGA/tools/apply_v379.py`; prueba `tests_test_carga_v379.py`.

## 9. 3.7.10 CARGA APAGADO (encima de la 3.7.9)
Petición del usuario: con el pecho apagado, al conectarlo a cargar y desenchufarlo debe apagarse solo, y en ningún
momento del proceso debe despertar a la espalda.
- Al arrancar se lee por qué se encendió el AXP2101 (registro 0x20: bit0 = tecla PWR, bit2 = USB conectado).
  Encendido por el USB y no por PWR → **arranque de carga** (monitor: `encendido por USB (solo carga)`).
- Durante un arranque de carga el pecho **no transmite nada a la espalda** (ni baliza ni DATA), tampoco después de
  desenchufar, hasta que se apaga. En los primeros segundos de cualquier arranque, antes de leer el PMU, tampoco.
- **USB retirado 2 s** en un arranque de carga, sin sesión → apagado controlado (SD cerrada y corte del AXP2101,
  como una pulsación larga de PWR).
- Si durante la carga se pulsa BOOT o PWR, o empieza una sesión, pasa a ser un encendido normal: al desenchufar
  sigue encendido y llama a la espalda como siempre.
- Parche: `firmware/chest/V3_7_10_CARGA_APAGADO/tools/apply_v3710.py`.
