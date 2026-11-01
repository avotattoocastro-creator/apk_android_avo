# AVO Performance Horse — iPad (duplicado de Windows Advanced Analysis V2 PRO)

App nativa SwiftUI para iPadOS 17 o posterior, pensada para el iPad Pro M4. Es la traducción fiel de la app Windows
(`windows/`, rama `feature/windows-girth-movimiento`): mismas pantallas, textos, formatos de archivo y cálculos, y el
mismo motor C++ AVO Equine compilado dentro de la app.

- **Código:** `AVOiPad/Core` (núcleo portado de `AVO.Windows.Core`), `AVOiPad/Engine` (puente al motor C++),
  `AVOiPad/App` (modelos de cada pantalla, Bluetooth y Wi‑Fi) y `AVOiPad/Views` (pantallas).
- **Pruebas:** `AVOiPadTests` reúne las autopruebas de Windows en XCTest, con los mismos vectores del firmware.
  `AVOiPadUITests` hace capturas de todas las pantallas.
- **Reglas del port:** `PORTING.md` y `UI_CONTRACT.md`.
- **Proyecto:** `project.yml`. El `.xcodeproj` se genera con XcodeGen y no se guarda en git.
- **CI:** `.github/workflows/build-avo-ipad.yml` (macOS):
  1. sesiones de demostración, compilación y pruebas en el simulador del iPad Pro 13" (M4);
  2. capturas en horizontal y vertical en la rama `ci/ipad-visual-evidence`;
  3. subida firmada a **TestFlight** si existen los secretos.

## Diferencias con Windows
| Windows | iPad |
|---|---|
| Lector NFC USB (PC/SC) | No disponible: el iPad no tiene NFC. Se muestra el UID guardado y se puede pegar un enlace `avohorse://`. |
| «Reloj USB» (puerto serie) | **Reloj Wi‑Fi**: el iPad pide al reloj por Bluetooth que encienda su Wi‑Fi (`WIFI_SYNC`, pecho ≥ 3.7.4), se une a `AVO_CHEST_XXXX` y descarga por HTTP con reanudación y SHA-256, igual que Android 2.3-wifi. |
| Clave del reloj con DPAPI | Llavero de iOS. |
| Abrir y arrastrar archivos | Botón «Abrir» (app Archivos), «Abrir con…», AirDrop o Compartir desde otra app. |
| Exportar a carpeta | Hoja de compartir: guardar en Archivos, AirDrop o Mail. |
| Demostración descargada | Las sesiones DEMO van dentro de la app. |

## Instalar en el iPad (TestFlight)
Pasos una sola vez, con la cuenta Apple Developer:
1. **Crear la app:** en App Store Connect → Apps → «+» → Nueva app, plataforma iOS, con el ID de paquete
   `org.avoperformance.horse.ipad`. Si ese ID ya está ocupado, elige otro y guárdalo en la variable de repositorio
   `AVO_IPAD_BUNDLE_ID`.
2. **Crear la clave de la API:** en App Store Connect → Usuarios y acceso → Integraciones → Claves de la API de App
   Store Connect, crea una clave con el rol **Admin** y descarga el `.p8`.
3. **Añadir los secretos:** en GitHub → Settings → Secrets and variables → Actions, añade:
   - `APPLE_TEAM_ID`: el ID del equipo, de 10 caracteres, que aparece en developer.apple.com → Membership;
   - `ASC_KEY_ID` y `ASC_ISSUER_ID`: los dos se ven en la página de la clave;
   - `ASC_KEY_P8_BASE64`: el resultado de `base64 -i AuthKey_XXXX.p8`.
4. **Lanzar la compilación:** en Actions → «AVO iPad» → Run workflow (o haz push a `feature/ipad-app`). Cuando Apple
   termine de procesarla, la compilación aparece en la app **TestFlight** del iPad.
5. **Para las siguientes versiones:** cada push a `feature/ipad-app` sube una compilación nueva.

## Estado
IMPLEMENTADO y COMPILADO / CI (ver `docs/REGISTRO_DE_CAMBIOS.md`). **NO VERIFICADO** en un iPad real, ni con el reloj por
Bluetooth o Wi‑Fi, ni con sesiones reales con cincha.
