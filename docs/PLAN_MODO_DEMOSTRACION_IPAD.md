# Plan · Modo demostración 3D en la app del iPad (27/11/2026)

**Estado:** primera versión IMPLEMENTADA (27/11, PR #138): página «Demostración» con la web de `demo/avo-3d/web-3d` en un `WKWebView` (three.js dentro de la app, modelos descifrados en el CI). Es un paso intermedio hasta la versión nativa de este plan. NO VERIFICADA en el iPad.

## Resumen
La app del iPad tendrá un **Modo demostración** nativo: el caballo y el jockey de Enozone en 3D con RealityKit, el
**casco prototipo A** y la **cincha** sobre ellos, y al lado la pantalla real de la sesión en directo. Funciona sin
conexión, con datos simulados o con el directo real.

- **Decisión:** nativo (RealityKit + SwiftUI), no la página web dentro de un `WKWebView`: más fluido, menos batería,
  sin conexión y reutiliza la pantalla LIVE que ya existe.
- **Sin cambios de protocolo:** usa `TELEMETRY v3` (116 B) tal como ya lo publica el directo.

## Alcance
| Incluye | No incluye |
|---|---|
| Caballo + jockey 3D con paso, trote, galope, sprint y parado | Cambios en `TELEMETRY v3`, `BackStatus`, lotes de cincha, `AVO1` o `.avr` |
| Casco prototipo A (cápsula y anillo de 8 LED) y cincha sobre el modelo | Conexión BLE nueva: el iPad sigue sin conectarse al reloj |
| Paquetes animados cincha → casco → móvil y RTCM | Cambios en `Info.plist`, firmas o número de build de TestFlight |
| Panel de sesión en directo reutilizando la pantalla LIVE | Versión Android o Windows (fase posterior) |
| Fuente simulada y fuente real (directo de Firebase) | Modelos 3D en claro dentro de este repositorio público |

El iPad **no** recibe la telemetría por BLE: desde el PR #84 la recibe por Firebase (`live/{owner}/{sid}`), enviada
por el Android conectado al reloj. La fuente real del modo demostración será ese mismo directo.

## Arquitectura
```
Fuente simulada ──┐                    ┌──► Escena RealityKit (ARView .nonAR, iPadOS 17):
                  ├──► DemoState ──────┤      caballo + jockey USDZ, casco, cincha, paquetes
Directo Firebase ─┘  (velocidad, aire, └──► Panel SwiftUI (vistas de la pantalla LIVE)
                      RTK, baterías, cincha)
```
Las dos fuentes escriben en un mismo estado; la escena y el panel solo lo leen. El aire del caballo se elige por la
velocidad recibida.

## Preparación de los modelos
1. **Origen:** `horse.FBX` y `jockey.FBX` del paquete *Race Horse Jockey with LOD v1.4* (FBX 7.4, 30 fps, eje Y
   arriba). Se usan los LOD0; los LOD1 y los huesos visibles se descartan.
2. **Conversión (en un Mac):** Blender 4.x → importar los dos FBX → exportar USD (`.usdz`) con esqueleto y animación.
   Reality Converter también sirve si lee el FBX. No se puede hacer desde la sesión en la nube.
3. **Tramos de animación** (30 fps): paso 0–159 · galope 241–302 · sprint 304–362 · parado 365–409 · trote 541–604.
4. **Materiales:** cuerpo de 2048 px con mapa normal, crin con transparencia recortada y 13 chaquetillas de 1024 px.
5. **Tamaño objetivo:** menos de 15 MB en el bundle.

## Fases y criterios de aceptación
1. **F0 · Modelos (Mac).** USDZ con los cinco aires. Acepta: se abre en Vista Rápida del iPad, anima y pesa < 15 MB.
2. **F1 · Escena 3D.** Pantalla «Demostración», RealityKit con pista, focos, sombras y cámara orbital.
   Acepta: 60 fps en el iPad Pro M4 al galope, sin avisos de memoria.
3. **F2 · Sistema AVO.** Casco y cincha unidos a sus huesos, anillo de LED por estado RTK, paquetes animados.
   Acepta: el casco sigue la cabeza en los cinco aires y los LED cambian con Fix, Float y sin RTK.
4. **F3 · Datos.** Fuente simulada y fuente real, con la etiqueta SIMULACIÓN cuando toque.
   Acepta: pruebas unitarias del simulador y de la elección de aire por velocidad.
5. **F4 · Panel de sesión.** Franja y gráficas de LIVE junto a la escena. Acepta: los mismos números que LIVE.
6. **F5 · Prueba en iPad real.** Compilación de TestFlight y demostración completa.
   Acepta: 10 minutos seguidos sin cortes, temperatura y batería anotadas.

## Riesgos, licencia y verificación
| Riesgo | Efecto | Medida |
|---|---|---|
| Repositorio público | Los modelos del Asset Store quedarían descargables | Licencia confirmada por el usuario (27/11) para la app privada; los FBX, USDZ y texturas solo se suben **cifrados** (`demo/avo-3d/modelos_cifrados/`); el CI los descifra con el secreto `AVO_ASSETS_3D_KEY` |
| Conversión FBX → USDZ | Esqueleto de biped de 3ds Max con rotaciones mal convertidas | Probar primero solo el galope; comparar con la web |
| `RealityView` exige iPadOS 18 | La app pide iPadOS 17 | `ARView` en modo `.nonAR` |
| Capturas de UI del iPad ya fallan en `develop` | Sin captura automática | Pruebas unitarias; capturas a mano en F5 |
| Peso del bundle | Descarga de TestFlight más lenta | Texturas comprimidas; < 15 MB |

**Verificación:** el CI (`build-avo-ipad.yml`) solo demuestra que compila y que pasan las pruebas. «Verificado en
hardware» exige F5 en el iPad. Descargar los modelos en el CI exige tocar el workflow: se avisará al usuario antes.

## Decisiones pendientes
- [ ] ¿Quién hace la conversión a USDZ en el Mac (F0)?
- [x] Modelos: cifrados en el repositorio público; clave en el secreto `AVO_ASSETS_3D_KEY` (27/11). Falta crear el secreto y, en F1, el paso del workflow que los descifra (se avisará antes de tocarlo).
- [ ] Ubicación: ¿pantalla propia en la barra lateral o botón «Demostración» dentro de LIVE?
- [ ] ¿F3 con fuente real desde el principio o solo simulada para la primera demo?
- [ ] ¿Fuente directa del casco (firmware 5.0.0, mismos servicios que el pecho) o se sigue con el directo de Firebase?
