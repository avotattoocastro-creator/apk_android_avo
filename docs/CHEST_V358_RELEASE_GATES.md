# AVO CHEST V3.5.8 — control de publicación y OTA

## Estado
- Fuentes V3.5.8 y workflow de compilación: incorporados a la rama central.
- Compilación/artefacto V3.5.8: no verificados en esta revisión.
- Instalación V3.5.8: **BLOQUEADA** hasta resolver compatibilidad de firma.

## Problema crítico descubierto
CHEST V3.5.7 fija la clave pública SPKI con kid `AVO_OTA_RECOVERABLE_P256_V1`.
El código fuente del AVO Signer V0.1 proporcionado anteriormente genera una **clave nueva** en Android Keystore bajo el alias `AVO_OTA_SIGNING_P256_V1`, y exporta `public_key_spki_base64`.
No existe evidencia de que esa clave coincida con la clave pública fijada en el reloj. De hecho, el kid es distinto. **Cambiar solo el kid no soluciona una clave pública distinta.**

Una firma hecha con la clave privada del Signer V0.1 no puede autorizar la OTA de CHEST V3.5.7 salvo que se demuestre que corresponde a la clave pública fijada. El reloj exige `OTA_AUTH` y versión superior antes de `OTA_BEGIN`.

## Prueba obligatoria
1. Exportar la clave pública desde la aplicación AVO Signer.
2. Compararla con `python3 firmware/chest/V3_5_8/verify_signer_key.py exported-public-key.json`.
3. Verificar que Android realmente envía `OTA_AUTH=0x54`, con manifiesto y firma DER, antes de `OTA_BEGIN`.
4. Generar ZIP `firmware.bin`, `manifest.json`, `manifest.sig` con la **clave privada correspondiente a la clave anclada**.
5. Validar firma, destino, SHA-256, versión y rechazo de paquetes manipulados antes de instalar.
6. Comprobar arranque, reinicio y recuperación tras desconexión en pruebas físicas.

## Restricciones
- No incrustar ni subir una clave privada a GitHub, APK o firmware.
- No desactivar verificación de firmas para facilitar una actualización.
- Si no existe la clave privada correspondiente a la clave anclada, hay que estudiar una **recuperación por USB** u otro procedimiento de mantenimiento autorizado. No prometer OTA BLE firmada imposible.
- La compilación correcta del BIN no prueba que sea instalable por OTA en V3.5.7.
