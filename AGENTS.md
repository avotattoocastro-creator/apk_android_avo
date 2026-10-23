# Instrucciones para asistentes (Claude, ChatGPT/Codex y otros)

Este repositorio se desarrolla con varios asistentes en conversaciones distintas. GitHub es la **única fuente
compartida**: lo que no esté en la rama no existe para el siguiente asistente.

## Reglas
1. Rama de integración: **`develop/avo-performance-horse`**. No trabajar sobre `main` ni sobre ramas históricas.
2. **Cada cambio se documenta en `docs/REGISTRO_DE_CAMBIOS.md`** (entrada arriba, con plantilla), en el mismo
   commit o en el siguiente. Incluir commits, ejecución de CI y nivel de validación.
3. Niveles de validación separados: IMPLEMENTADO · COMPILADO / CI (número de ejecución y SHA) · PROBADO FÍSICAMENTE
   (dispositivo, versión, evidencia). Sin prueba física: **NO VERIFICADO**. Ver `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`.
4. Antes de empezar, leer este archivo, `README.md`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` y las últimas entradas de
   `docs/REGISTRO_DE_CAMBIOS.md`, y comprobar `git log` de la rama.
5. Al cambiar una versión, actualizar también la matriz de `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` y la tabla de `README.md`.
6. No guardar credenciales NTRIP, tokens, contraseñas ni claves privadas en el repositorio.

## Restricciones técnicas del reloj de pecho (CHEST, Waveshare ESP32-S3 AMOLED 2.06")
- **No usar LVGL**: satura la RAM interna y rompe BLE con el móvil y el enlace con la espalda. La pantalla usa
  Arduino_GFX + el renderizador propio de `firmware/chest/V3_7_2_UI` (framebuffer en PSRAM).
- No modificar comunicaciones (BLE, ESP-NOW, UART, NTRIP/RTCM, GNSS), OTA ni almacenamiento cuando la tarea sea de
  pantalla u otra cosa; si es imprescindible, justificarlo y documentarlo en el registro.
- Arduino_GFX define `BLACK`, `RED`, `GREEN`, `BLUE`, `YELLOW`, `WHITE`… como macros: no usar esos nombres para constantes.
- El panel va montado girado 180°: el giro se hace por software (`UI_ROTATE_180` en `ui.cpp`), no con `setRotation(2)`.
- Mostrar solo datos reales del estado del sistema; nunca valores de demostración de los diseños de referencia.

## Componentes
| Carpeta | Qué es | Workflow |
|---|---|---|
| `app/`, `core/` | App Android AVO Performance Horse | `build-android.yml` |
| `usb-updater/` | App Android independiente para programar el reloj por USB | `build-usb-updater.yml` |
| `avo-signer/` | Firma de paquetes OTA | `build-avo-signer.yml` |
| `firmware/chest/V3_*` | Firmware del reloj de pecho por versiones (ZIP base + parches) | `build-chest-v*.yml` |
