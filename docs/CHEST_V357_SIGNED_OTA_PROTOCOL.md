# AVO CHEST V3.5.7 — contrato OTA firmada (candidato)

Estado: diseño/código candidato; **no probado en ESP32 ni en Android real**. No instalar hasta CI de firmware y prueba física.

## Transición

CHEST V3.5.6 utiliza OTA BLE sin firma obligatoria. La primera instalación de V3.5.7 debe realizarse con el cliente OTA legado compatible o por USB. Una vez instalada V3.5.7, el receptor rechaza OTA_BEGIN sin autorización firmada. **Antes de instalar V3.5.7 debe existir una APK que implemente OTA_AUTH y estar probada**, para evitar bloquear futuras OTA BLE.

## Paquete firmado

ZIP con `firmware.bin`, `manifest.json`, `manifest.sig`. Firma ES256 ECDSA P-256 DER sobre los bytes exactos de manifest.json; el reloj usa clave pública anclada, nunca clave privada. El manifiesto declara `target`, `version`, `size`, `sha256` y `kid`; el destino previsto es `AVO_CHEST_WAVESHARE_ESP32S3` y la clave `AVO_OTA_RECOVERABLE_P256_V1`.

## Secuencia BLE candidata

1. Enviar `OTA_AUTH=0x54` con `u16LE manifest_length`, `u16LE signature_length`, bytes del manifiesto y firma DER; esperar ACK positivo.
2. Enviar `OTA_BEGIN=0x50` con `u32LE size` y 32 bytes SHA-256, idénticos al manifiesto autenticado.
3. Enviar `OTA_DATA=0x51` en orden secuencial y finalmente `OTA_END=0x52`.
4. Receptor verifica tamaño y hash completo antes de cambiar la partición de arranque. Los bloques se escriben previamente solo en partición OTA inactiva.
5. El arranque nuevo debe confirmar salud; verificar persistencia tras apagado y encendido y recuperación ante corte de energía.

## Evidencias pendientes

- Integrar fuentes V3.5.7 en el árbol de firmware de esta rama (el candidato se distribuyó como ZIP de fuentes separado).
- Compilar con Arduino-ESP32 y dependencias exactas; resolver incompatibilidades de API mbedTLS/cJSON.
- Implementar/verificar en Android el envío real de OTA_AUTH y sus ACK.
- Pruebas de firma válida, firmware alterado, versión inferior, destino incorrecto, interrupción BLE, corte de energía y arranque persistente.
- Definir política de rotación/revocación de clave y anti-rollback resistente a manipulación.

**No confundir verificación ES256 del ZIP en Android con autenticación ejecutada dentro del firmware del reloj.**
