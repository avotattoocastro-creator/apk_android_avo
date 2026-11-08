# Registro de cambios — AVO Performance Horse

Registro **único y compartido** entre todos los asistentes (Claude, ChatGPT/Codex) y personas que trabajen en el
proyecto. Rama de integración: **`develop/avo-performance-horse`**.

## Cómo añadir una entrada (obligatorio en cada cambio)

- Añadir la entrada **arriba** (orden cronológico inverso), en el **mismo commit** que el cambio o en el siguiente.
- Usar los niveles de `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`: **IMPLEMENTADO**, **COMPILADO / CI** (con número de
  ejecución y SHA) y **PROBADO FÍSICAMENTE** (con dispositivo, versión y evidencia). Si no hay prueba física, escribir
  **NO VERIFICADO**.
- No borrar ni reescribir entradas de otros autores; si algo era incorrecto, añadir una entrada nueva que lo corrija.

```
## AAAA-MM-DD — Módulo vX.Y.Z — título corto
**Autor:** Claude | ChatGPT | persona · **Commits:** `abc1234`, … · **CI:** run NNNN (éxito/fallo)
**Qué cambia:** …
**Por qué:** …
**Archivos:** …
**No se ha tocado:** … (si aplica)
**Validación:** IMPLEMENTADO / CI / PROBADO FÍSICAMENTE / NO VERIFICADO
**Pendiente:** …
```

---

## 2026-11-08 — iPad — Informe PDF del tramo, recorrido horizontal en los informes y cifras del Dashboard
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (capturas del entrenador 10:41–10:45):**
- «Análisis del tramo»: botón **Informe PDF** (junto a «Guardar en…»): PDF con datos del tramo, 12 cifras, recorrido del tramo, velocidad frente a metros con líneas cada 200 m y Vmáx, desglose de 200 m, observaciones, comparación con los tramos guardados y el análisis IA (si se ha hecho). Se guarda en `exportaciones/AVO_tramo_<sesión>_<hhmmss>.pdf` y abre el menú de compartir. `ReportBuilder.stretchPdf` reutiliza la cabecera y tablas de los informes (`PdfReportWriter` ya no es `final`; subtítulo configurable).
- Informes (PDF y vista HTML): el **recorrido se dibuja girado en horizontal** (eje principal por PCA, inicio a la izquierda), con flecha de norte girada y escala correcta (`ReportBuilder.routeLayout`). Antes salía en vertical, norte arriba.
- Todas las páginas: **sin la barra de título** centrada («Jinetes», «Reloj Wi-Fi»…); la cabecera AVO / barra del entrenamiento sube a la primera fila. Con el menú lateral oculto aparece un botón a su izquierda para volver a mostrarlo.
- Dashboard: las 5 cifras en una fila a **todo el ancho** bajo la portada y los accesos, sin cortarse.
**Archivos:** `Core/ReportBuilder.swift`, `App/StretchModel.swift`, `Views/StretchAnalysisView.swift`, `Views/ReportsView.swift`, `Views/HomeView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — IA sin texto («respuesta cortada por longitud») y cifras del Dashboard
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:**
- Análisis IA del tramo: gastaba ~7600 tokens y no mostraba texto. Claude Sonnet 5.5 piensa por defecto (pensamiento adaptativo) y `max_tokens` cubre pensamiento + texto: con 4096 todo se iba en pensar. Ahora el tramo usa `max_tokens` 32 000 con `output_config.effort = "medium"`, y el Asistente IA 16 000 (antes 4096, mismo problema posible). `ClaudeClient.stream` acepta `effort`.
- Dashboard: las 5 cifras siempre en una fila (con 3 columnas se cortaban Velocidad máxima y Sesión activa).
**Archivos:** `Core/ClaudeAPI.swift`, `App/AssistantModel.swift`, `App/StretchModel.swift`, `Views/HomeView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Corrige el archivo para TestFlight (Xcode 26)
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:** el run 42429837057 compiló y pasó las pruebas, pero el archivo Release falló: «the compiler is unable to type-check this expression in reasonable time» en la fila de «Tramos guardados» (`StableView.swift`). La fila pasa a una vista propia (`StableStretchRow`) y se simplifican las expresiones largas de `StretchAnalysisView` (parciales y observaciones). Sin cambios de comportamiento.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — France Galop: fichas de la cuadra y carreras (uso privado)
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (petición del entrenador 01:01/01:16, uso privado):**
- Cuadra: botón **France Galop** (cabecera) que abre france-galop.com en un navegador dentro de la app (`FranceGalopView`, WKWebView). «Leer página» lee lo que muestra la página: datos de la ficha (sexo/raza/capa, nacimiento, padres, entrenador, colores, criadores, valor, actuaciones, país…), **todas sus tablas** (resumen de carrera, actuaciones = carreras, compromisos) y los enlaces a fichas de caballos (página del entrenador o propietario = **toda la cuadra**).
- Ficha leída → «Guardar en la Cuadra» en un caballo existente o creándolo (nombre, raza y año de la ficha; solo rellena raza/año si estaban vacíos).
- Página del entrenador → «Vincular estos caballos con la Cuadra» (propone el caballo por nombre; «Crear en la Cuadra») → «Actualizar toda la cuadra»: abre cada ficha vinculada una a una, con pausas de ~3 s, y guarda sus datos y tablas.
- Ficha del caballo en Cuadra: tarjeta **France Galop** con los datos y las tablas guardadas, «Actualizar» y «Desvincular».
- No depende de la estructura interna de la web (lee texto visible, tablas HTML y enlaces); solo a petición del usuario. Datos en `france_galop.json` en la carpeta de la app.
**Archivos:** `ipad/AVOiPad/Core/FranceGalop.swift`, `ipad/AVOiPad/App/FranceGalopModel.swift`, `ipad/AVOiPad/Views/FranceGalopView.swift` (nuevos); `AppModel.swift`, `RootView.swift`, `StableView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO (sin acceso a france-galop.com desde el entorno de desarrollo: la lectura de etiquetas está hecha con la ficha de la captura del usuario).

## 2026-11-08 — iPad — Análisis del tramo (pantalla completa) y tramos guardados por caballo
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (petición del entrenador 00:57):**
- «Mapa»: botón **Análisis tramo** (arriba a la derecha, activo con un tramo seleccionado) que abre a pantalla completa `StretchAnalysisView`:
  - 14 cifras del tramo (distancia, duración, vel. media/máx., mejor 200 m, último 200 m frente al mejor, 2.ª mitad frente a 1.ª, tiempo hasta el 90 % de Vmáx, distancia y tiempo por encima del 90 %, aceleración/frenada máx. validadas, regularidad CV, cadencia, RTK FIX);
  - perfil de velocidad frente a metros con líneas cada 200 m y la Vmáx;
  - **desglose por tramos de 200 m** (tiempo, media, máx., aceleración media; el mejor resaltado; parcial final marcado);
  - observaciones calculadas con los datos (caída final, mitades, regularidad, punta, calidad GNSS, comparación con su mejor tramo guardado de distancia parecida);
  - comparación con los tramos guardados del caballo;
  - **análisis completo IA y recomendaciones** (Claude con la clave del Asistente IA, o el modelo de Apple), con el tramo, el resumen del entrenamiento completo y los tramos guardados; respeta el límite de gasto mensual.
- **Guardar el tramo en el caballo** (`tramos_guardados.json` en la carpeta de la app; con nombre opcional y el texto IA). Cuadra › caballo: además de «Entrenamientos de …» (completos), nueva lista **«Tramos guardados de …»** con Abrir (selecciona el entrenamiento y el tramo y abre el análisis) y Borrar.
**Archivos:** `ipad/AVOiPad/Core/StretchAnalysis.swift`, `ipad/AVOiPad/App/StretchModel.swift`, `ipad/AVOiPad/Views/StretchAnalysisView.swift` (nuevos); `AppModel.swift`, `RootView.swift`, `StableView.swift`, `AssistantModel.swift` (`addSpend` accesible).
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Inicio: sin logo redondo, rótulo y accesos más arriba
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** pantalla de inicio (`StartView`): quitado el logo redondo; el rótulo AVO / PERFORMANCE HORSE / TRAINING ANALYSIS sube a su sitio; la columna de accesos empieza arriba (antes centrada). Petición del entrenador: el jinete de la foto con los colores de la Cuadra Lezama — **no hecho**: requiere una foto propia (no se usan imágenes de Internet).
Dashboard en horizontal sin desplazamiento (se cortaba arriba): portada y cifras a la izquierda, accesos a toda la altura a la derecha.
**Archivos:** `ipad/AVOiPad/Views/StartView.swift`, `ipad/AVOiPad/Views/HomeView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Menú: Dashboard, Entrenamientos y Mapa antes de Análisis
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (bocetos del entrenador, 00:20–00:24):**
- Barra lateral: «Entrenamientos» (página `.sessions`) pasa a **Dashboard**; «Listado» pasa a **Entrenamientos** (título de la página también); **Mapa** va antes que Análisis.
- Dashboard: solo la portada, los accesos rápidos y las cifras (entrenamientos, distancia medida, demostración, velocidad máxima, sesión activa). Quitadas las tarjetas de sesiones recientes, Reloj AVO, Caballos, Disponibilidad de sensores, Estado de importaciones y Estado del sistema.
**Archivos:** `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/Views/HomeView.swift`, `ipad/AVOiPad/Views/StartView.swift`, `ipad/AVOiPad/Views/TrainingListView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Marca fija de velocidad máxima y barra de «Mapa» solo con el entrenamiento
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- Marca fija en el punto de velocidad máxima (velocidad filtrada): en el mapa, marcador naranja con rayo y «Vmáx 51,1 km/h» (`VmaxAnnotation`); en la gráfica de velocidad de «Mapa» y en el perfil de «Análisis», punto naranja. `SessionItem.maxSpeedPoint` (en caché por línea de tiempo).
- «Mapa»: la barra de arriba solo tiene el selector de entrenamiento (boceto del entrenador); Entreno 2, pestañas y Asignar siguen en «Análisis». «Mapa» ya no usa la vista de comparación.
**Archivos:** `ipad/AVOiPad/App/SessionItem.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/MapPageView.swift`.
- «Mapa» con un tramo seleccionado: arriba los datos del tramo y, a la vez, abajo a la izquierda los del punto seleccionado (tiempo, distancia, velocidad, aceleración y fase).
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Mapa sin tarjetas inferiores y doble toque para quitar el tramo
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- «Mapa»: quitadas las tarjetas Entrenamiento, leyenda de velocidad y Punto seleccionado bajo la gráfica (boceto del entrenador); la gráfica con pestañas y zonas ocupa el resto de la página, sin desplazamiento vertical. En «Análisis» siguen.
- Todas las gráficas sincronizadas: doble toque con el dedo o doble toque lateral del Apple Pencil (`UIPencilInteraction`) quita el tramo seleccionado.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/ChartsView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Satélite con zoom máximo y fuera el aviso NFC de Cuadra/Jinetes
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- Mapa: con el zoom al máximo la imagen de satélite desaparecía (rejilla vacía), porque Esri solo sirve hasta el nivel 19. `RouteEsriTileOverlay` llega ahora al nivel 22 ampliando un trozo de la tesela del nivel 19; si falta una tesela en un nivel ≥ 16 se amplía la del nivel anterior.
- Cuadra y Jinetes: quitada la tarjeta «El iPad no tiene NFC… / Pegar enlace avohorse://…» de la cabecera y la nota NFC de la ficha (petición del entrenador).
**Archivos:** `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/StableView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: sigue al cursor, datos del tramo, mapa en la mitad y desplazamiento lateral con zoom
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (bocetos del entrenador, 23:25–23:31):**
- El mapa se centra en el punto elegido en la gráfica o en la barra de tiempo **sin cambiar el zoom ni el giro** (`MapKitRoute.applyCursor`). No se mueve cuando el punto se toca en el propio mapa ni en el primer cursor de un recorrido.
- Con un tramo seleccionado en la gráfica, la franja superior del mapa muestra los datos del **tramo**: duración, distancia, vel. media, vel. máx., aceleración y frenada máx. validadas, inicio–fin.
- «Mapa»: mapa en la mitad superior, barra de tiempo (reproducción) entre el mapa y las gráficas, y debajo las gráficas con desplazamiento vertical (gráfica con pestañas + zonas, y las tarjetas Entrenamiento / leyenda / punto). En «Análisis» la reproducción sigue sobre el mapa.
- Gráficas con zoom: desplazamiento lateral con **dos dedos** (`TwoFingerPan`, UIKit, simultáneo con el resto de gestos), al arrastrar el cursor contra un borde, y en «Mapa» la barra de vista general con el recuadro arrastrable y «Completo».
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/ChartsView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: nueva distribución según el boceto del entrenador
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (página «Mapa»; los elementos sobre el mapa también en «Análisis»):**
- Franja de datos del punto del cursor (tiempo, distancia, velocidad, aceleración y fase) arriba del mapa, en lugar de abajo.
- Estadísticas en columna arriba a la derecha: Distancia, Vel. media, Tiempo, Vel. máx.
- Reproducción (play, velocidad, barra y tiempo) sobre el borde inferior del mapa.
- «Capas» abajo a la derecha, junto a los botones de zoom (el panel se abre encima).
- Debajo del mapa, una sola gráfica grande con pestañas Velocidad · Aceleración · Lateral · Inclinación · Vertical · Cadencia (las de cincha y cadencia solo si hay datos), con las franjas y asas de zonas y los botones de zonas dentro de la misma tarjeta. La pestaña elegida se recuerda.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Reloj Wi-Fi: motivo real del fallo, sondeo HTTP y protección de reinicios
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- Con el pecho 3.7.6 (AVO_1E8C) la página decía «WI-FI DISPONIBLE» mientras descargaba por Bluetooth «(no se pudo usar el Wi-Fi del reloj)», sin el motivo. Ahora `WifiSyncReport.wifiReason` y `WifiConnector.lastFailure` llevan el motivo hasta la pantalla (reloj rechaza activar el Wi-Fi, el iPad no se une a la red, o se une pero el reloj no responde por HTTP), y la etiqueta pasa a «WI-FI FALLÓ» con el motivo debajo hasta que una pasada por Wi-Fi funcione o se reconecte.
- Sondeo HTTP tras unirse: antes una sola petición con 20 s de tiempo de espera agotaba toda la ventana de 20 s; ahora peticiones de 4 s cada segundo durante 30 s (DHCP, ruta a 192.168.4.x y permiso de red local de iOS la primera vez).
- Unión a la red del reloj: un segundo intento a los 3 s si el primero falla (el SoftAP puede no estar emitiendo todavía), salvo que el usuario la rechace.
- `WifiBootGuard`: si `WIFI_SYNC(start)` no respondía (excepción) el intento quedaba marcado; cualquier apagado y encendido normal posterior del reloj bloqueaba el Wi-Fi como si se hubiera reiniciado por él. Ahora se borra el intento si el enlace Bluetooth sigue vivo.
**Archivos:** `ipad/AVOiPad/Core/WifiSync.swift`, `ipad/AVOiPad/App/WifiJoin.swift`, `ipad/AVOiPad/App/WatchWifiModel.swift`, `ipad/AVOiPad/Views/WatchWifiView.swift`.
**No se ha tocado:** firmware del pecho, protocolo BLE/HTTP, descarga por Bluetooth.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.
**Pendiente:** con el motivo visible, decidir si el fallo está en el reloj (3.7.6) o en iOS. La app Android tiene la misma marca de intento en `AvoWifiSyncManager` (revisar).

## 2026-11-07 — iPad — Mapa: datos del cursor en una franja horizontal
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** en la compilación 38 el recuadro del cursor ocupaba todo el ancho y casi la mitad del mapa (el `Divider` lo estiraba). Ahora es una sola franja horizontal y baja en la parte inferior del mapa, como en el boceto del usuario: Punto · tiempo · distancia · velocidad · aceleración | fase · tiempo fase · distancia fase · «de» total; solo ocupa lo que necesita y deja libres los botones de zoom.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: tiempo y distancia del cursor dentro de la fase
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** el recuadro «Punto del cursor» añade, cuando el cursor cae dentro de una fase del motor (calentamiento, trabajo o enfriamiento de «trabajo_pista», ya con las correcciones a mano), «En <fase>»: tiempo y distancia desde el inicio de esa fase y la duración y distancia totales de la fase. Se detecta por la posición del cursor, sin tener que pulsar «Ver: Calentamiento / Trabajo / Enfriamiento» (que solo acerca las gráficas), así que funciona también en «Mapa».
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: datos del punto exacto del cursor
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** recuadro «Punto del cursor» en la esquina inferior izquierda del mapa (Análisis y Mapa, `MapCursorOverlay`): tiempo, distancia desde el inicio (m), velocidad (km/h) y aceleración longitudinal validada (m/s²) del punto exacto donde está el cursor (toque en el recorrido, en la línea de tiempo o reproducción). Usa los mismos valores que las lecturas de las gráficas (`cursorSpeed`, `cursorAccel`; nuevo `cursorDistanceM`). Petición del usuario sobre captura de la compilación 36.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: playa en horizontal y giro con dos dedos
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** el mapa del recorrido (`MapKitRoute`) se puede girar con dos dedos y «Ajustar» lo orienta para que el recorrido quede en HORIZONTAL: eje principal de las posiciones (componentes principales en Web Mercator), rumbo de la cámara elegido lo más cerca posible del norte (en el Regatón el mar queda arriba); si el recorrido no tiene una dirección clara (ratio de varianzas < 1,6) se deja el norte arriba. El encuadre mide el recorrido a lo largo y a lo ancho de la pantalla girada y respeta los márgenes (datos arriba a la derecha). El zoom +/− mantiene el giro (cámara en vez de `setVisibleMapRect`). Botón nuevo en Análisis y Mapa: «Norte arriba» / «Recorrido en horizontal» (se recuerda en `map.alignRoute`). Petición del usuario: «necesito ver la playa en horizontal».
**Archivos:** `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad. El mapa de la comparación (Entreno 2, SwiftUI `Map`) se gira con dos dedos pero no se orienta solo.

## 2026-11-06 — iPad — Análisis rediseñado: mapa a todo el ancho, línea de tiempo y todas las gráficas con scroll; «Entreno 2»; «Mapa» en el menú
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (pedido del usuario sobre una captura anotada de la compilación 33):**
- **Análisis** (`MapPageView`): una sola columna con scroll vertical:
  - mapa a todo el ancho (58 % de la altura, mínimo 380 pt); el panel «Capa base / Trazo» queda oculto tras el botón «Capas»; distancia, tiempo, velocidad media y máxima van en pequeño sobre la esquina superior derecha del mapa (`MapStatsOverlay`); los botones de zoom bajan a la esquina inferior derecha;
  - debajo, la línea de tiempo (perfil de velocidad con zonas y asas, reproducción) y los botones de zonas;
  - después, TODAS las gráficas de «Gráficas» (`ChartsNavigator` + `ChartsStack(skipSpeed: true)`, sin repetir la velocidad), con el mismo cursor, zoom y rango;
  - al final, las tarjetas que estaban en la columna derecha: Entrenamiento (fases), leyenda y punto seleccionado (`MapInfoCards`). Se elimina `MapSidePanel`; los tramos siguen en su página.
- **«Entreno 2»** (`RootPairMenu`, en la barra del entrenamiento junto al entrenamiento activo): elige un segundo entrenamiento y Análisis pasa a comparar los dos (entreno 1 azul, entreno 2 amarillo): cabecera con ambos y «Quitar entreno 2», barra de zoom y rango de la comparación, recorridos superpuestos grandes y gráficas alineadas (`CompareResults`, `CompareMap`, `CompareChartToolbar`, `CompareRangeCard` pasan a ser internos). `CompareModel.pairId` / `setPair(_:)`: la comparación contiene solo esos dos; al cambiar el entrenamiento activo se mantiene el entreno 2 (si coinciden, se quita).
- **Menú lateral:** nueva entrada **«Mapa»** debajo de «Análisis» (`Page.map`, `nav.Map`): el mapa ocupa la página con la línea de tiempo debajo y sin gráficas (o los dos recorridos con «Entreno 2»).
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/ChartsView.swift`, `ipad/AVOiPad/Views/CompareView.swift`, `ipad/AVOiPad/App/CompareModel.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.
**Pendiente:** cursor de la línea de tiempo sobre el mapa de la comparación; revisar con el usuario la altura del mapa.

## 2026-11-06 — iPad — Asistente IA: corrección de «Probar conexión» que borraba la clave
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** en Ajustes del asistente, «Guardar clave», «Probar conexión» y «Borrar clave» estaban en la misma fila del `Form`; en SwiftUI un toque en esa fila dispara todos los botones, así que «Probar conexión» borraba la clave y respondía «No hay clave guardada» (visto en el iPad con la compilación 33). Ahora cada botón va en su fila con `.buttonStyle(.borderless)` y «Borrar clave del iPad» queda aparte, al final. Al guardar, se comprueba que la clave se lee del Llavero y el asistente pasa a usar Claude (se desactiva «Usar el modelo de Apple»).
**Archivos:** `ipad/AVOiPad/Views/AssistantView.swift`, `ipad/AVOiPad/App/AssistantModel.swift`.
**Validación:** IMPLEMENTADO · error reproducido por el usuario en el iPad (compilación 33) · corrección NO VERIFICADA.

## 2026-11-06 — iPad — Asistente IA: Claude (API) y modelo de Apple analizan el entrenamiento activo
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** ver `git log` · **CI:** pendiente
**Qué cambia:**
- **Nueva pestaña «Asistente IA»** en la barra del entrenamiento (`Page.assistant` = `Assistant`, `tab.Assistant`, después de «Trabajo en pista»; `App/AssistantModel.swift`, `Views/AssistantView.swift`):
  - conversación sobre el entrenamiento activo con respuesta en streaming, botón Detener y «Nueva conversación»;
  - preguntas rápidas: explicar la sesión, fatiga y recuperación, comparar con la historia, zancada y cincha, próximo entrenamiento;
  - la conversación se reinicia al cambiar de entrenamiento.
- **Claude por la API, directo desde el iPad** (`Core/ClaudeAPI.swift`): `POST https://api.anthropic.com/v1/messages` (`anthropic-version: 2023-06-01`, SSE).
  - Modelos: Sonnet 5.5 (por defecto), Haiku 5.5 y Opus 5.5.
  - **Contexto:** cabecera (caballo, raza de la Cuadra, jinete, fecha, ventana útil, estado del motor), resumen `avo-training-session`, análisis completo del motor compactado (sin `series`, listas numéricas largas resumidas en n/mín./máx./media, listas de objetos recortadas, decimales redondeados; incluye `trabajo_pista`) y resúmenes ya calculados de hasta 15 sesiones anteriores del mismo caballo. Tope de 180 000 caracteres (por debajo de los 100 000 tokens de Haiku 5.5).
  - El contexto va en un bloque de sistema con `cache_control` (las preguntas siguientes leen de caché) y se reutiliza mientras no cambie la sesión ni su análisis.
  - Instrucciones: responder en español, solo con los datos recibidos, citando cifras; umbrales de raza y mano de galope tratados como no validados; sin diagnósticos veterinarios.
- **Clave de API en el Llavero de iOS** (`AvoKeychain`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`): la pega el usuario en Ajustes del asistente; nunca está en el código ni en el repositorio (regla 6). «Probar conexión» y «Borrar clave».
- **Gasto:** estimación por respuesta con los precios de lista (tokens y ~$ en el pie de cada respuesta), contador del mes en el iPad y límite configurable (5–100 $, 50 $ por defecto) que bloquea las preguntas al alcanzarlo. El tope real son los 100 $/mes de créditos de API del plan Max en Claude Console (organización sin método de pago ni recarga automática).
- **Modelo de Apple sin conexión** (`Core/OnDeviceAssistant.swift`, Foundation Models, iPadOS 26 con Apple Intelligence): opción gratuita que solo recibe el resumen de la sesión; compila con `#if canImport(FoundationModels)`, así que el CI de pruebas con un SDK anterior lo deja desactivado.
- **Pruebas:** `AVOiPadTests/AssistantTests.swift` (compactación del JSON, coste estimado, forma de la clave, mensajes de error, mezcla del `usage` del streaming); captura de la página `Assistant` en `ScreenshotTests` (sin clave: tarjeta de configuración).
**Por qué:** el usuario quiere un analista IA dentro de la app con los créditos de API incluidos en su plan Max, sin servidor (el Servidor AVO aún no funciona). Cuando funcione, `ClaudeClient.endpoint` puede apuntar a él y quitar la clave del iPad.
**Archivos:** `ipad/AVOiPad/Core/ClaudeAPI.swift` (nuevo), `ipad/AVOiPad/Core/OnDeviceAssistant.swift` (nuevo), `ipad/AVOiPad/App/AssistantModel.swift` (nuevo), `ipad/AVOiPad/Views/AssistantView.swift` (nuevo), `ipad/AVOiPad/App/AppModel.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPadTests/AssistantTests.swift` (nuevo), `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** el motor (`equine-intelligence`), Android, Windows, firmware.
**Validación:** IMPLEMENTADO · sin compilador Swift en la sesión (pendiente de CI macOS) · NO VERIFICADO en el iPad ni con la API real.
**Pendiente:** probar en el iPad con la clave real; renderizado completo de Markdown (títulos y listas se muestran como texto); llevarlo a Android y Windows; pasar por el Servidor AVO cuando esté operativo.

## 2026-11-03 — iPad — AVO Track Work 1.0.0 integrado: página «Trabajo en pista», entrenamiento vs carrera y Track Work en la historia
**Autor:** Claude · **Rama:** `feature/ipad-app` (sobre `7a6bb83`) · **Commits:** pendiente · **CI:** pendiente
**Qué cambia:**
- **`Core/TrackWork.swift`:** decodifica TODO el bloque `trabajo_pista` (tolerante, `nil` si falta):
  - perfil de raza (umbrales, velocidades de referencia, base de parciales 200 m o furlong);
  - cincha (VeDBA medio, por aire y carga, giros y grados por mano, saturación), zancadas (resumen y lista), mano (EXPERIMENTAL);
  - trabajos y pasadas: parciales con tiempo acumulado y velocidad, mejores 200…1600 m (tiempo, velocidad, dónde), v. máx y tiempo hasta ella, distancia > 90 %, últimos 200/400 m, índice de caída, zancada a la máxima y a las velocidades de referencia, ajustes f/l, mano por trabajo, recuperación y pausa;
  - recorrido (pasadas, mejor pasada, % dentro de la geocerca, cruces ignorados en sentido contrario), fases, series, eventos y avisos.
  - Se mantienen los nombres antiguos (`efforts`, `passes`, `sectionals`, `fatiguePct`, `recoveryS`…).
- **Nueva página «Trabajo en pista»** (`Page.trackWork`, pestaña de la barra del entrenamiento después de Gráficas, `tab.TrackWork`; `App/TrackWorkModel.swift`, `Views/TrackWorkView.swift`):
  - cabecera con la raza de la ficha, el perfil usado (aviso y «Volver a analizar» si no coinciden), la base de las fases (velocidad / líneas / corregidas) y los avisos;
  - franja de la estructura (calentamiento / trabajo / calma con minutos al paso, trote y galope) y fichas de resumen de las series;
  - tabla ordenable de trabajos y pasadas; al tocar una fila se selecciona en toda la app (rango, cursor y ventana de Gráficas) y se abre su detalle: parciales (tabla y barras en s o km/h), mejores distancias, velocidad frente a distancia con la máxima y la franja del 90 %, frecuencia y longitud de zancada frente a la velocidad con los valores de referencia resaltados, cincha y giros del trabajo, eventos;
  - «Mejores distancias de la sesión», cincha de la sesión, recorrido y eventos.
  - Sin datos: «Sin datos», «Requiere cincha» o «Requiere líneas de salida y meta».
- **Análisis (mapa):** el panel «Entrenamiento» queda como resumen (fases, recuentos, seleccionado) con el botón «Ver trabajo en pista»; la lista de trabajos pasa a la nueva página.
- **Ficha de la carrera:** bloque «Entrenamiento vs carrera, tramo a tramo» (`Views/RaceTrainingSplitsView.swift`, `RaceTrainingSplits` en `Core/RaceAnalysis.swift`):
  - por defecto, el trabajo o pasada más rápido por velocidad media (con ≥ 2 parciales completos) de los 60 días anteriores a la carrera; menú para elegir otro;
  - tramos alineados desde la meta (último parcial completo ↔ 200–ARR), solo piezas completas; tiempo y km/h de entrenamiento y carrera, % de la velocidad de carrera y perfil de caída (último / mejor tramo) en ambos;
  - analiza con el motor (resultado en caché) los entrenamientos de la ventana que aún no tienen resultado;
  - explica que los parciales del entrenamiento son en la playa y los de la carrera en la pista.
- **Historia del caballo:** sección «Trabajo en pista»: evolución de la mejor pasada, su velocidad media, índice de caída, recuperación y VeDBA en galope; carga VeDBA por día/semana con su ACWR; tabla de líneas base y tendencias de `TRABAJO.*`, `CINCHA.*`, `RECORRIDO.*` y `carga_vedba`; impactos atípicos y motivos de la cincha. `TrainingSessionSummary.trabajoPista` y la carga VeDBA de `TrainingLoad` se decodifican; las tendencias de Track Work salen de la tarjeta general.
- **Pruebas:** `AVOiPadTests/TrackWorkTests.swift` (JSON real del motor para las sesiones sintéticas de `test_racing.cpp` con cincha y con líneas tipo Regatón; decodificación tolerante; velocidad-distancia; motor real sobre la demo con raza PSI; alineación entrenamiento-carrera). Capturas: página `TrackWork` añadida a `ScreenshotTests`.
**Supuestos:** «mejor pasada» por defecto en la carrera = mayor velocidad media (el motor llama mejor pasada a la más corta en tiempo); un parcial cuenta como completo si mide ±5 % de la base; los giros por mano de un trabajo se calculan con el giro medio de sus zancadas (|giro| ≥ 4 °/s).
**Archivos:** `ipad/AVOiPad/Core/TrackWork.swift`, `ipad/AVOiPad/Core/RaceAnalysis.swift`, `ipad/AVOiPad/Core/TrainingAnalytics.swift`, `ipad/AVOiPad/App/TrackWorkModel.swift` (nuevo), `ipad/AVOiPad/App/AppModel.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/App/RacesModel.swift`, `ipad/AVOiPad/App/HorseHistoryModel.swift`, `ipad/AVOiPad/Views/TrackWorkView.swift` (nuevo), `ipad/AVOiPad/Views/RaceTrainingSplitsView.swift` (nuevo), `ipad/AVOiPad/Views/RaceDetailView.swift`, `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/HorseHistoryView.swift`, `ipad/AVOiPadTests/TrackWorkTests.swift` (nuevo), `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** el motor (`equine-intelligence`), Android, Windows, firmware.
**Validación:** IMPLEMENTADO · sin compilador Swift en la sesión (pendiente de CI macOS) · NO VERIFICADO en el iPad ni con caballos reales.

## 2026-11-03 — iPad — raza en la ficha del caballo: desplegable de razas de carreras
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:** el campo «Raza» de la ficha del caballo (Cuadra) pasa a ser un desplegable agrupado:
- **Galope:** Pura Sangre Inglés (PSI), AQPS, Pura Sangre Árabe (PSA), Anglo-Árabe (AA) y Cuarto de Milla de carreras.
- **Trote:** Trotón Francés, Standardbred y Trotón escandinavo/sueco.
- **Otra:** texto libre.

Debajo se indica el perfil de AVO Track Work que se aplicará:
- PSI y AQPS → `PSI`;
- PSA y AA → `ARABE`;
- trotones y Cuarto de Milla → `GENERICO`, con un aviso de que el análisis de galope no aplica al trote.

Se guarda como texto en `Breed`, compatible con Android y Windows; las razas escritas a mano se conservan.
**Archivos:** `ipad/AVOiPad/Core/TrackWork.swift`, `ipad/AVOiPad/Views/StableView.swift`, `ipad/AVOiPadTests/RacingBreedTests.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO.

## 2026-11-01 — iPad 1.0.x — Biomecánica en la línea de tiempo del entrenamiento (zoom, tramo, desplazamiento, leyendas activables)
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` → `feature/ipad-app` · **Commits:** ver `git log` · **CI:** pendiente
**Qué cambia (petición del usuario con captura):**
- Las gráficas de la cincha ya no usan una ventana local de 4 s: están en la **línea de tiempo compartida** (`charts.domain`), igual que Análisis y Gráficas.
  - Gráficas: |a|, ejes x/y/z, giro, movimiento sin gravedad, balanceo/cabeceo y cadencia.
  - Comparten cursor, zoom (pellizco y botones), selección de tramo («Guardar como tramo»), filtro por fase y barra de desplazamiento (`ChartsNavigator`).
- **Barra común `SyncZoomBar`:** seleccionar tramo, acercar y alejar, desplazar, restablecer, **«Ver ±2 s del cursor»** (la vista de detalle anterior), guardar o quitar tramo y reproducción.
- **Leyendas activables** en todas las gráficas de la cincha (`BiomechModel.legend`, que busca el nombre exacto de la serie).
- **Datos:** series de sesión completa (`SyncSource`) reducidas con LTTB a la ventana visible fuera del hilo principal (`BiomechModel.refreshPanels`); franjas de fases bajo cada gráfica.
**Validación:** IMPLEMENTADO · CI pendiente · NO VERIFICADO en el iPad.

---

## 2026-11-01 — iPad 1.0.x — Gráficas: líneas activables, barra de desplazamiento y filtro por fase; Listado: eliminar y exportar entrenamientos
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` → `feature/ipad-app` · **Commits:** `ed7d6fc` y siguientes · **CI:** iPad run 41349352965 ✅ (84 pruebas, todas las capturas)
**Qué cambia (peticiones del usuario con capturas del iPad):**
- **Gráficas:**
  - cada entrada de la leyenda es un interruptor que muestra u oculta su línea, la banda ±σ o los marcadores de su color (`SyncLegend.keys`, `sigma` y `marker`; `ChartsModel.hiddenLegend`; `ChartsLegends`);
  - **barra de vista general** (`ChartsOverviewBar`) con el perfil de velocidad, las fases, las repeticiones, el cursor y el **recuadro de la ventana visible, que se arrastra para desplazarse** con zoom o en sesiones largas. Sin zoom, al tocar se acerca a ¼ de la sesión;
  - **filtro por fase:** Completo, Calentamiento, Trabajo y Enfriamiento hacen zoom a la fase del motor.
- **Listado, «Eliminar entrenamiento…»:**
  - pide confirmación;
  - borra solo lo que guarda la app (copia de la biblioteca, RAW, análisis, resumen, correcciones, valoración, tramos, notas y favorito) y **nunca los archivos del usuario**;
  - `eliminados.json` evita que «Buscar entrenamientos perdidos» lo vuelva a importar; abrirlo a propósito lo importa otra vez.
- **Listado, «Exportar a AVO Horse»** (de uno o de todos los filtrados):
  - copia el **original verificado** (.avo o .avr, mismo SHA-256) en Archivos › En mi iPad › AVO Horse › **Exportados** con el nombre `AVO_<fecha_hora>_<caballo>`;
  - si ya estaba exportado, no lo duplica;
  - sirve para enviarlo por AirDrop o correo, o para pasarlo a otro iPad, a AVO Windows o a Android.
- **Pruebas:** borrar (lista, biblioteca, archivo del usuario intacto, marca de eliminado, reimportar) y exportar (mismo SHA-256, sin duplicar).
**Validación:** IMPLEMENTADO · CI ✅ · **NO VERIFICADO** en el iPad real.

---

## 2026-11-01 — iPad 1.0.x — líneas de salida y meta en el mapa, zonas arrastrables e integración en `feature/ipad-app`
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` → **`feature/ipad-app`** (avance rápido, sin cambios de otros autores desde `babaf8c`) · **Commits:** `78ed42c`, `d3b038d` · **CI:** iPad run 41343000760 ✅ (83 pruebas unitarias; capturas)
**Qué cambia:**
- **Mapa de Análisis:** líneas de salida (verde) y meta (roja) de las correcciones, con una bandera y el nombre, y una **flecha hacia el lado por el que cuenta el cruce**. Sin flecha si el sentido es AMBOS. Archivos: `MapCourseLine`, `CourseLineOverlay` y `CourseLabelAnnotation` en `MapKitRoute.swift`.
- **Perfil de velocidad:** **asas arrastrables** en los bordes de la fase de trabajo (fila baja) y de cada repetición (fila alta).
  - Al arrastrar, el cursor se mueve (el mapa sigue al caballo) y aparece la hora.
  - Al soltar, se guarda la corrección y el motor vuelve a analizar.
  - Archivos: `SyncHandle`, `SyncHandleLayer` y `CorrectionsModel.handles/moveHandle`.
  - Solo las asas reciben los toques; el resto de la gráfica mantiene el cursor, el rango y el zoom.
- **Prueba unitaria:** dirección de la flecha (DCHA_A_IZQ con A al oeste y B al este → norte) y sin flecha con AMBOS.
**Validación:** IMPLEMENTADO · CI ✅ · captura del simulador con las asas sobre las franjas · **NO VERIFICADO** en el iPad real.
**Pendiente:** Windows y Android.

---

## 2026-11-01 — iPad 1.0.x — navegación reorganizada y «Análisis» con zonas editables (+ motor: correcciones manuales)
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` (sale de `feature/ipad-app` `babaf8c` + `feature/avo-training-analytics`) · **Commits:** `008443c`, `3e5045f`, `4287548` · **CI:** iPad run 41338103300 ✅ (compilación, 83 pruebas unitarias, capturas; falla la captura de Inicio en horizontal, que no ha cambiado) · motor run 41337324883 ✅
**Qué cambia (petición del usuario con una foto de la pantalla):**
- **Barra lateral solo con páginas generales:** Inicio, Entrenamientos, Listado, Análisis, Carreras, Cuadra, Jinetes, Geocercas y líneas, Reloj Wi-Fi y Servidor AVO.
- **Barra del entrenamiento**, arriba en las páginas de un entrenamiento (`TrainingBar` en `RootView.swift`):
  - entrenamiento activo;
  - pestañas Análisis, Resumen, Gráficas, Tramos, GPS, Biomecánica, Comparar, Mareas, Informes y Motor;
  - Asignar.
  - `Page.isTrainingPage`; nueva página `.summary`, que es la antigua vista «Análisis del caballo».
- **«Análisis» = la foto:** es la antigua página Mapa.
  - Mapa y panel derecho con distancia, tiempo y velocidades, la nueva tarjeta **«Entrenamiento»** (fases, repeticiones y pasadas, que se seleccionan al tocarlas), la leyenda, los tramos y el punto seleccionado.
  - Perfil de velocidad con **franjas de zonas**: fases, repeticiones y pasadas (`SyncBand` con `lane` y `height`).
  - Barra de tiempo.
  - **Botones de zonas:** Salida aquí, Meta aquí, Inicio trabajo, Fin trabajo, Inicio/Fin repetición, Quitar repetición y Restablecer.
- **Correcciones:**
  - se guardan en `correcciones.json` (`CorrectionsModel`), en tiempo GPS absoluto (iTOW), sin tocar los datos;
  - cada cambio vuelve a analizar con el motor;
  - las líneas de salida y meta se calculan a 50 m a través del recorrido en el cursor, en el sentido del movimiento (`DCHA_A_IZQ`).
- **Raza:** el texto de la Cuadra (PSI, Pura sangre inglés, Árabe…) se pasa al motor como `raza` (`TrackWorkBreed`).
- **Motor:**
  - opciones `trabajos_manuales` y `fases_manuales` (iTOW);
  - trabajos `manual`, `fases.base` = `MANUAL` y `correcciones_manuales`;
  - el hash de parámetros incluye las correcciones;
  - prueba `pista.manual_corrections` (83 casos).
- **Swift:** `Core/TrackWork.swift` lee `trabajo_pista`; `EquineAnalysis.trackWork`.
- **Prueba de capturas:** navega por la barra lateral y por las pestañas (`tab.*`).
**Validación:**
- IMPLEMENTADO · CI ✅.
- Capturas del simulador iPad Pro 13" en horizontal y vertical (rama `ci/ipad-visual-evidence`).
- Prueba unitaria con la sesión DEMO del Regatón: 1 repetición manual de 30 s, fase MANUAL y recorrido con salida y meta.
- **NO VERIFICADO** en el iPad real.
**Pendiente:**
- Dibujar las líneas de salida y meta en el mapa.
- Mover las zonas arrastrándolas.
- Llevar lo mismo a Windows y Android.
- Integrar en `feature/ipad-app`.

---

## 2026-11-01 — Motor AVO Equine — Track Work: recorrido de entrenamiento con líneas de salida y meta (opcional)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` · **Commits:** `7a34604` · **CI:** run 41334018208 ✅ (Linux ASan/UBSan 82 casos/1157 comprobaciones, Windows MSVC, Android NDK ×3, JNI, fixtures)
**Por qué:** el usuario comparte su zona de entrenamiento (Playa del Regatón, Laredo), con la geocerca de grabación, el calentamiento, la salida, el trabajo, la meta y el enfriamiento.
- Aclara que es una **referencia aproximada que puede variar**.
- Aclara que **todos los datos salen del chaleco GPS RTK y de la cincha BNO085**.
- Por eso el recorrido es **opcional**: sin líneas sigue la detección por velocidad y cincha.
**Qué cambia:**
- **Opciones** `recorrido` (líneas `salida`, `meta` o `salida_meta` con sentido, y `geocerca`) o `plan_geocercas` (el `geocercas.json` de Windows/iPad: `Lines` con `Role` y `Direction`, y `Fences` de tipo polígono).
- **Cruces:** misma geometría que el reloj y AVO Windows, con el instante interpolado.
- **Pasadas** SALIDA → META con el mismo análisis que los trabajos. La SALIDA cruzada al revés anula la salida pendiente; así el calentamiento que pasa la línea hacia atrás no crea pasadas falsas.
- **Fases** por líneas (`fases.base` = `LINEAS`).
- **Geocerca:** porcentaje de épocas dentro y aviso.
- **Parciales:** último tramo hasta la línea.
- **Hash de parámetros** con el recorrido.
- **Historia:** `RECORRIDO.mejor_pasada_s` y `RECORRIDO.v_media_mejor`.
- **Refactorización:** el cálculo de un trabajo se hace en una sola función (`fill_effort`) para trabajos y pasadas.
- **Fixtures** regeneradas.
**Validación:**
- IMPLEMENTADO. 82 casos y 1157 comprobaciones con ASan/UBSan, y en Release.
- **Recorrido sintético como el del dibujo:** calentamiento hacia atrás pasando la salida, giro, galope de 1200 m, enfriamiento pasando la meta y vuelta cruzando la meta al revés.
  - 1 pasada de 75,08 s (real 75,08 s).
  - Recuperación de 15,8 s (real 15,83 s).
  - Igual con sentido AMBOS.
  - Con las líneas en el sentido equivocado no aparecen pasadas.
  - Con una geocerca menor, avisa.
  - También a través de la API C con un `geocercas.json` de Windows.
- **NO VERIFICADO** con datos reales.
**Pendiente:** que las apps pasen su `geocercas.json` al motor.

---

## 2026-11-01 — Motor AVO Equine — AVO Track Work 1.0.0: el módulo de «carreras» pasa a ser de ENTRENAMIENTO (fases, series, recuperación)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` · **Commits:** `ef704d8` · **CI:** run 41330093878 ✅ (Linux ASan/UBSan 79 casos/1103 comprobaciones, Windows MSVC, Android NDK ×3, JNI, fixtures)
**Por qué:** el usuario aclara que el objetivo es analizar los **entrenamientos** de caballos de carreras PSI y árabes, no las carreras. Esta entrada corrige el enfoque de la anterior («AVO Racing 1.0.0»).
**Qué cambia:**
- **Nombres:**
  - bloque JSON `carreras` → **`trabajo_pista`** (con `modulo` = `AVO_TRACK_WORK`);
  - `procedencia.algoritmos.carreras` → `trabajo_pista`;
  - métricas de la historia `CARRERA.*` → **`TRABAJO.*`**;
  - resumen de sesión `carreras` → `trabajo_pista`;
  - ficha `13_CARRERAS.md` → **`13_TRABAJO_PISTA.md`**.
  - El código interno se sigue llamando `racing`.
  - Ninguna app leía todavía estos nombres.
- **Nuevo: estructura del entrenamiento (`SESSION_PHASES_V1`):**
  - fases de calentamiento, trabajo y vuelta a la calma, con duración, distancia y tiempo por aire;
  - por trabajo: **recuperación hasta el paso** y **pausa hasta la siguiente repetición**, con su velocidad;
  - **series:** repeticiones y rápidas, **caída de la máxima y de la zancada** entre la primera y la última repetición rápida, y recuperación media;
  - aviso de **calentamiento corto** (menos de 10 min antes del primer trabajo rápido; valor de partida).
- **Historia:**
  - el resumen guarda `trabajo_pista.sesion`;
  - métricas informativas `TRABAJO.recuperacion_hasta_paso_s`, `TRABAJO.caida_entre_series_pct` y `TRABAJO.calentamiento_s`;
  - el calentamiento corto aparece como motivo.
- **Fixtures** regeneradas.
**Validación:**
- IMPLEMENTADO.
- 79 casos y 1103 comprobaciones con ASan/UBSan.
- Nueva prueba `pista.training_morning_structure`: mañana sintética con calentamiento de 4 min, 2 repeticiones a 16 y 15 m/s con paseo entre ellas y vuelta a la calma.
  - Caída 6,24 % (real 6,25 %).
  - Recuperación 6,5 s (real 6,1 s).
  - Pausa y fases correctas.
- **NO VERIFICADO** con caballos reales.

---

## 2026-11-01 — Motor AVO Equine — AVO Racing 1.0.0 (caballos de carreras PSI y árabe)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` · **Commits:** `3631bd9` · **CI:** run 41328572986 ✅ (Linux ASan/UBSan 78 casos/1086 comprobaciones, Windows MSVC 78 casos, Android NDK ×3, JNI en JVM, fixtures)
**Qué cambia (petición del usuario: «añadir todo lo posible a los caballos de carreras PSI y árabes»):**
- **Nuevo módulo** `src/racing/` + `include/avo_eq/racing.h`. Añade el bloque `carreras` al análisis y lo documenta la ficha 13.
- **Perfiles de raza** `GENERICO` / `PSI` / `ARABE`: velocidades de trabajo, rápida y alta, velocidades de referencia y rangos de zancada.
- **Cincha en el marco del caballo:**
  - escala BNO085 (byte 15 = 1) o por gravedad;
  - vertical por gravedad y eje de avance por PCA, con el sentido confirmado por la inclinación frente a la aceleración GNSS;
  - **VeDBA** y carga de la cincha;
  - **giros a cada mano** (tiempo y grados, por aire);
  - saturación.
- **Zancadas en galope:**
  - frecuencia y longitud (con la velocidad GNSS);
  - pico vertical y desplazamiento vertical del tronco;
  - rasgo lateral.
- **Mano de galope** (experimental): el rasgo lateral es especular entre manos. Se autocalibra en curvas o se fija con `signo_mano`. Da los cambios de mano y el porcentaje de mano de fuera en curva.
- **Trabajos (GNSS):**
  - galope de trabajo o trabajo rápido;
  - parciales cada 200 m o cada furlong (`parcial_m`);
  - mejores 200–1600 m;
  - máxima y tiempo hasta ella, distancia por encima del 90 %;
  - últimos 200/400 m e **índice de caída**;
  - zancada a la máxima, rectas frecuencia/longitud–velocidad y **zancada a las velocidades de referencia**.
- **Eventos** (experimentales): impacto atípico, movimiento lateral brusco y saturación.
- **Ingesta:** `Session::imu_units` (byte 15 de la cabecera IMU) y recuento de lotes fusionados (formato 1).
- **Historia de entrenamientos:**
  - el resumen guarda el bloque `carreras`;
  - la distancia a alta velocidad usa el umbral de la raza;
  - carga VeDBA con ACWR;
  - líneas base y tendencias `CARRERA.*` y `CINCHA.*`;
  - las métricas se definen en una sola tabla (`metric_specs`).
- **Opciones de la API** (`avo_eq_analyse_ex`): `raza`, `parcial_m` y `signo_mano`. El hash de parámetros y `procedencia.algoritmos.carreras` invalidan la caché.
- **Fixtures** `core/src/test/resources/equine/*_analysis.json` regeneradas: añaden el bloque `carreras` y cambia el hash de parámetros.
**Archivos:** `equine-intelligence/{include/avo_eq/racing.h,src/racing/racing.cpp,include/avo_eq/{types,engine,training,avo_eq_c}.h,src/core/engine.cpp,src/capi/capi.cpp,src/ingestion/ingestion.cpp,src/training/training.cpp,tests/test_racing.cpp,tests/test_training.cpp,README.md,docs/FORMATO_RESULTADOS.md,docs/algoritmos/{12_ENTRENAMIENTO,13_CARRERAS}.md}`, fixtures.
**Validación:**
- IMPLEMENTADO.
- Linux: 78 casos y 1086 comprobaciones con ASan/UBSan, y en Release.
- Sesión sintética con física conocida (cincha girada 170°/35°, curvas y cambios de mano):
  - máxima 17,04 m/s;
  - frecuencia 2,451 Hz (real 2,43) y longitud 6,95 m (real 7,0);
  - mano 100 % en curvas y 2 de 2 cambios;
  - giros de 71° y 85° (reales 73° y 86°).
- **NO VERIFICADO** con caballos reales.
**Pendiente:**
- Validar la mano con vídeo.
- Ajustar los perfiles PSI y árabe con sesiones reales.
- Usar los lotes fusionados (cuaternión) del BNO085.
- Rango de ±16 g para impactos fuertes.
- Pantallas en las apps.

---

## 2026-11-01 — iPad 1.0.x — AVO Training Analytics 1.0.0 en la app: valoración del entrenador, «Historia del caballo» y forma antes de la carrera
**Autor:** Claude · **Rama:** `feature/ipad-app` (sobre `18e647e`) · **Commits:** pendiente · **CI:** pendiente
**Qué cambia:**
- **Envoltorios Swift** (`Engine/EquineEngine.swift`): `trainingSummary(analysisJson:extraJson:)` (síncrono) y `trainingAnalyse(inputJson:optionsJson:)` (async, cancelable con la bandera nativa, más `trainingAnalyseSync`), mismos códigos y `{"error"}` que `analyseJson`.
- **Modelos** (`Core/TrainingAnalytics.swift`): «avo-training-session» y «avo-training-analysis» con decodificación tolerante (claves ausentes, `null` o tipos erróneos → nil): carga (externa, sRPE, aguda, crónica semanal, ACWR, monotonía, tensión), desvíos con z y VIGILAR/REVISAR (solo el sentido malo se marca; la velocidad es informativa), líneas base, tendencias SUBE/BAJA/ESTABLE y estado NORMAL/VIGILAR/REVISAR con motivos. `TrainingRating` + `valoraciones.json`.
- **Resumen por sesión** (`App/AppModel+Training.swift`, `runEngine`): tras cada análisis se guarda `paths.analysis/<id>/training_summary.json` con extra `{"id","caballo" (código de la Cuadra o nombre),"jinete","fecha_utc" (inicio de la sesión, ISO UTC),"valoracion","pista"}`; se regenera al cambiar la valoración. Si falta el resumen, la historia lo genera reutilizando el resultado guardado del motor.
- **Análisis:** tarjeta «Valoración del entrenador» (RPE 1–10, estado BIEN/CANSADO/RARO/COJERA, pista superficie/estado, nota) guardada en `paths.root/valoraciones.json` por id de sesión. El nombre del caballo de la cabecera abre su historia.
- **«Historia del caballo»** (`App/HorseHistoryModel.swift`, `Views/HorseHistoryView.swift`, pantalla completa desde RootView): botón «Historia de entrenamientos» en la ficha del caballo (Cuadra) y desde Análisis. Estado con motivos («orientativo, no es un diagnóstico veterinario»), carga por día/semana apilada por aire + alta velocidad con aguda 7 d / crónica 28 d, ACWR con la banda, sRPE, monotonía/tensión, última sesión frente a su línea base, tendencias de 8 semanas y lista de sesiones (abre la sesión en Análisis). Excluye DEMO salvo caballo DEMO.
- **Carreras:** bloque «Forma antes de la carrera» en la ficha (`fecha_referencia` = día de la carrera): estado, ACWR, monotonía y tendencias; se añade a las observaciones si es VIGILAR/REVISAR o el ACWR sale de la banda.
- **Pruebas** `AVOiPadTests/TrainingAnalyticsTests.swift`: API C real con resúmenes sintéticos (ACWR ≈ 1 con carga estable, línea base con ≥ 4 sesiones, z ≥ 2 → VIGILAR, z ≥ 3 → REVISAR, COJERA y sRPE, errores y cancelación, valoraciones tolerantes).
**Archivos:** `ipad/AVOiPad/Engine/EquineEngine.swift`, `ipad/AVOiPad/Core/{TrainingAnalytics,RaceAnalysis}.swift`, `ipad/AVOiPad/App/{AppModel,AppModel+Shell,AppModel+Training,HorseHistoryModel,RacesModel,RootView}.swift`, `ipad/AVOiPad/Views/{HorseHistoryView,TrainingRatingCard,AnalysisView,SharedShellComponents,StableView,RaceDetailView}.swift`, `ipad/AVOiPadTests/TrainingAnalyticsTests.swift`.
**No se ha tocado:** motor C++ (`equine-intelligence/`), importación, reloj, capturas (la historia no es una página del menú).
**Validación:** IMPLEMENTADO · sin compilador Swift en la sesión (CI macOS pendiente) · **NO VERIFICADO** en iPad ni con sesiones reales.
**Pendiente:** compilar en CI y pasar `TrainingAnalyticsTests`; probar en iPad con la historia real de un caballo; ajustar factores de carga y umbrales con el entrenador; la primera apertura de la historia puede tardar si hay muchas sesiones sin resumen (se generan una a una con el resultado guardado del motor).

---

## 2026-11-01 — iPad 1.0.x — «Carreras»: PDF de tracking de France Galop / McLloyd y análisis frente a los entrenamientos
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** pendiente · **CI:** pendiente
**Qué cambia (petición del entrenador):**
- **Nueva página «Carreras»** (`Page.races` = "Races", menú tras «Listado», icono `flag.checkered`, `App/RacesModel.swift`, `Views/RacesView.swift`): lista con fecha, hipódromo, carrera, distancia, caballo, puesto/participantes, tiempo y diferencia con el ganador; filtros por caballo y fechas; botón **«Añadir carrera»** (selector de PDF).
- **Ficha del caballo (Cuadra):** tarjeta «Carreras de …» con **«Añadir carrera»** y la lista de sus carreras (al tocar, se abre la ficha de la carrera).
- **Lectura del PDF «Statistiques Tracking»** (`Core/RaceTrackingParser.swift`, PDFKit): cabecera (hipódromo, categoría, carrera, distancia, fecha y «Redk du 1er»), resumen (número, cuerda, tiempo oficial, últimos 600 m, «Parcouru vs. 1er») y una página por caballo (jockey, puesto, tiempo y redk, tramo más rápido, velocidad máxima y media; por tramo de 200 m: tiempo acumulado, tiempo del tramo, velocidad media, foulées). Acepta texto con un valor por línea o con etiqueta y valores en la misma línea. Las posiciones por tramo se calculan ordenando los tiempos acumulados (el texto del gráfico de posiciones del PDF no tiene un orden fiable); coinciden con el PDF en la muestra. Zancada = longitud del tramo / foulées (primer tramo = distancia − resto). Otro PDF: «Formato de carrera no reconocido».
- **Caballo:** se busca por nombre normalizado y prefijo de palabras (Zakyna ⊂ ZAKYNA AL ZARAYAN). Desde la ficha del caballo se guarda directamente si hay una sola coincidencia; si no, o desde «Carreras», hoja «Añadir carrera» para confirmar caballo de la Cuadra y participante (preseleccionada la mejor coincidencia).
- **Guardado:** `carreras.json` en la carpeta de la app (escritura atómica) + copia del PDF en `carreras/`.
- **Ficha de la carrera** (`Views/RaceDetailView.swift`): cabecera, resultado (puesto, tiempo oficial, distancia al ganador en s y cuerpos con 1 cuerpo ≈ 0,2 s), tabla completa transcrita (nuestro caballo resaltado), tabla por tramos de cualquier participante, gráficas (velocidad por tramo frente a ganador y mediana del campo, posición en carrera, foulées y zancada, distancia al primero), notas, compartir el PDF y eliminar.
- **«Análisis según los entrenamientos»** (`Core/RaceAnalysis.swift`, funciones puras): caída en el final (último tramo / mejor tramo anterior) frente a la mediana del campo, segundos perdidos en el final, por terreno de más y en la salida; entrenamientos del caballo anteriores al día de la carrera (mejor 200/400/600 m sostenido con ventana por distancia y velocidad filtrada, trabajos > 40 km/h ≥ 200 m, caída en trabajos ≥ 400 m, tendencia de los 3 últimos); tiempo corregido y puesto estimado («habría ganado N posiciones» / «no habría cambiado el puesto: le faltaron X s para el N.º»), «Hemos optimizado N posiciones» cuando el caballo terminó mejor de lo que indicaba su perfil, nivel de confianza (Alta/Media/Baja), observaciones concretas y nota de método. Se comparan proporciones, no velocidades absolutas.
- **Capturas (CI):** en modo captura se importa la carrera de muestra incluida en la app (`Resources/demo_race_20261029BOU03.pdf`) enlazada al caballo DEMO «Rayo (demo)» como Zakyna, marcada DEMOSTRACIÓN; `ScreenshotTests` incluye "Races".
**Archivos:** `ipad/AVOiPad/Core/{RaceModels,RaceTrackingParser,RaceAnalysis}.swift`, `ipad/AVOiPad/App/{RacesModel,AppModel,AppModel+Shell,RootView}.swift`, `ipad/AVOiPad/Views/{RacesView,RaceDetailView,SharedRaceImport,StableView}.swift`, `ipad/AVOiPad/Resources/demo_race_20261029BOU03.pdf`, `ipad/AVOiPadTests/RaceParserTests.swift`, `ipad/AVOiPadTests/Fixtures/20261029BOU03_last_times_fr.pdf`, `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** núcleo de entrenamientos (`SessionTimeline`, importación .avo/.avr), motor, reloj Wi‑Fi/BLE, resto de páginas.
**Validación:** IMPLEMENTADO · sin compilar en la sesión (CI macOS pendiente) · el algoritmo de lectura se comprobó fuera de Swift con `pdftotext` (texto simple y con maquetación) sobre la muestra · **NO VERIFICADO** en iPad ni con el texto real que devuelve PDFKit.
**Pendiente:** compilar en CI y pasar `RaceParserTests`; comprobar con PDFKit en iPad que el orden del texto es el esperado; probar con más PDF de France Galop (otras distancias, no clasificados, empates); validar con el entrenador la referencia de caída y el umbral de 40 km/h.

---

## 2026-11-01 — iPad 1.0.x — página «Listado de entrenamientos» y búsqueda de entrenamientos perdidos
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** pendiente · **CI:** pendiente
**Qué cambia (petición del entrenador):**
- **Nueva página «Listado»** (`Page.trainingList` = "List", menú tras «Entrenamientos», `App/TrainingListModel.swift`, `Views/TrainingListView.swift`): tabla densa a todo el ancho (`Table` ordenable en ancho regular, lista de filas en ancho compacto) con Fecha y hora, Caballo, Jinete, Modalidad, Duración, Distancia, Vel. máx., Cincha, Geocercas visitadas, Origen (Archivo / Wi-Fi / Bluetooth / Demo / Recuperado, leído del `source` del manifiesto .avo), Estado del motor y favorito. Tocar una fila la selecciona (entrenamiento activo); el botón «Abrir» de la fila o el menú contextual la abre en Análisis. Cabecera «N entrenamientos · X km · HH:MM total» del conjunto filtrado.
- **Filtros** (guardados en UserDefaults): texto, caballo y jinete (sesiones + Cuadra/Jinetes), modalidad, fecha desde/hasta (días de Europe/Madrid) con atajos Hoy / 7 días / 30 días / Todo, geocerca (las definidas en `geocercas.json`; un entrenamiento coincide si algún punto del recorrido cae dentro: círculo por haversine, polígono por punto en polígono; se calcula una vez por sesión fuera del hilo principal y se guarda en caché hasta que cambien las geocercas), solo con cincha, solo favoritos, ocultar DEMO y «Limpiar filtros».
- **«Buscar entrenamientos perdidos»:** recorre fuera del hilo principal Documents (Archivos › En mi iPad › AVO Horse), Documents/Inbox, tmp, Library/Caches, Application Support y la carpeta de la app (biblioteca, caché RAW, `reloj/descargas`). Toma .avo, .avr y carpetas de segmentos P00n.avr; descarta por SHA-256 del archivo, SHA-256 de segmentos o ID de sesión lo que ya está cargado; las carpetas completas se empaquetan como .avo (`AvoPackageWriter`, `source: recuperado-ipad`, en `reloj/recuperados`) y las que tienen `.wifi_etag`/`.ble_sizes` o huecos se informan como incompletas; .part/.tmp como interrumpidas. Lo nuevo se importa con `app.importFiles`. Hoja de resultado «N archivos revisados · M recuperados · K duplicados · J incompletos/dañados» con la lista y el motivo. «Buscar en una carpeta…»: carpeta de Archivos con acceso de seguridad, profundidad 6 y máximo 2000 archivos (los archivos se copian a `entrada` antes de importar).
- Estado vacío «No hay entrenamientos en el iPad» con Abrir / Reloj Wi-Fi / Buscar perdidos.
- `Info.plist`: `LSSupportsOpeningDocumentsInPlace = true`; al arrancar se crea `Documents/Entrenamientos` para que la carpeta de la app aparezca en Archivos.
**Archivos:** `ipad/AVOiPad/App/{TrainingListModel,AppModel,AppModel+Shell,RootView}.swift`, `ipad/AVOiPad/Views/TrainingListView.swift`, `ipad/AVOiPad/Resources/Info.plist`, `ipad/AVOiPadTests/TrainingListTests.swift`, `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** núcleo (`Core/`, `Engine/`), importación (`importFiles`), descarga Wi-Fi/BLE del reloj, resto de páginas.
**Validación:** IMPLEMENTADO · sin compilar en la sesión (CI macOS pendiente) · NO VERIFICADO en iPad.
**Pendiente:** compilar en CI; probar en iPad la tabla (columnas, orden, selección), el doble toque (no implementado: se abre con el botón de la fila o el menú contextual) y la búsqueda con archivos reales en Archivos.
## 2026-11-01 — Motor AVO Equine — AVO Training Analytics 1.0.0 (análisis de la historia de entrenamientos, fase 1)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` (sale de `feature/ipad-app` `33476df`) · **Commits:** `78893e4`, `d1edc03`, `6816a98` · **CI:** run 41315952401 ✅ (Linux ASan/UBSan 71 casos/1020 comprobaciones, Windows MSVC 71 casos, Android NDK ×3, JNI en JVM, fixtures, resumen → historia) sobre `6816a98`
**Qué cambia (petición del usuario: analizar los entrenamientos para Android, Windows e iOS):**
- **Nuevo módulo del motor C++** `src/training/` + `include/avo_eq/training.h`. Es una sola implementación para
  las tres plataformas: Android (JNI), Windows (DLL) e iPad (compila `equine-intelligence/src` entero).
- **Resumen por sesión** (`avo-training-session`):
  - tiempo y distancia por aire;
  - velocidad, tranco, cadencia y regularidad;
  - distancia a alta velocidad;
  - aceleraciones de la trayectoria GNSS;
  - calidad, valoración del entrenador (RPE, estado, nota) y pista.
- **Historia del caballo** (`avo-training-analysis`):
  - carga externa por aires (heurística `AVO_TRAINING_LOAD_V1`, configurable) y carga sRPE;
  - carga aguda 7 d, crónica 28 d, ACWR, monotonía y tensión;
  - línea base propia (mediana y MAD de 60 d, mínimo 4 sesiones) y desvíos z robustos;
  - tendencias Theil-Sen por semana;
  - estado NORMAL / VIGILAR / REVISAR con motivos. No es un diagnóstico.
- **API C:** `avo_eq_training_summary` y `avo_eq_training_analyse`, con cancelación y los mismos códigos.
- **CLI:** `avo_training_cli`.
- **Análisis de sesión:** añade `sesion.inicio_utc` (primera época GNSS con fecha y hora UTC). Fixtures
  `core/src/test/resources/equine/*_analysis.json` regeneradas (solo cambia esa clave).
- **CI:** `build-equine-engine.yml` se lanza también en esta rama y ejecuta resumen → historia con la fixture.
- `tests/test_fusion.cpp`: falta `#include <algorithm>` (rompía la compilación con el GCC nuevo del runner, run 41314987063).
- `tests/test_dsp.cpp`: `normal_distribution` con desviación 0 abortaba con las aserciones de GCC 15 (run 41315372137); se construye con 1 cuando no hay ruido (no se usa).
**Archivos:** `equine-intelligence/{include/avo_eq/training.h,include/avo_eq/avo_eq_c.h,src/training/training.cpp,src/capi/training_capi.cpp,src/core/engine.cpp,tools/training/avo_training_cli.cpp,tests/test_training.cpp,CMakeLists.txt,README.md,docs/FORMATO_RESULTADOS.md,docs/algoritmos/12_ENTRENAMIENTO.md}`, `core/src/test/resources/equine/{synthetic,sample}_analysis.json`, `.github/workflows/build-equine-engine.yml`.
**No se ha tocado:** el resto de algoritmos del motor, las apps Android, Windows e iPad (sin pantallas todavía) y el firmware.
**Validación:** IMPLEMENTADO · compilado y probado en Linux (71 casos, 1020 comprobaciones, ASan/UBSan) · CI run 41315952401 en verde · **NO VERIFICADO** con sesiones reales. Los factores de carga y los umbrales son valores de partida.
**Pendiente:**
- Integrar en las apps: JNI/Kotlin, P/Invoke/C# y Swift.
- Pantalla «Entrenamientos del caballo» y formulario de valoración tras cada sesión.
- Ajustar umbrales con datos reales.
- Fases 2 (etiquetas) y 3 (modelos).

---

## 2026-11-01 — iPad 1.0.x — página GPS, Análisis centrado en el caballo, Comparar rediseñado
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** pendiente · **CI:** pendiente
**Qué cambia (petición del usuario tras revisar la app en su iPad):**
- **Nueva página «GPS»** (`Page.gps`, menú tras «Mapa», `App/GpsModel.swift`, `Views/GpsView.swift`): todos los datos GNSS/RTK del chaleco sin mapa (distribución de soluciones y franja temporal, satélites, hAcc mediana/p95, precisión de velocidad, pérdidas de señal, saltos descartados, frecuencia, épocas, altitud MSL, velocidad reportada frente a derivada, receptor y sensores, nota de la antena del chaleco).
- **GNSS fuera del resto de páginas:** Análisis, Mapa (sin modo «Calidad GNSS» ni tarjeta GNSS/RTK), Tramos (sin fila RTK FIX ni observaciones GNSS), Comparar, Motor (sin dominio GNSS ni eventos GNSS), Entrenamientos, Cuadra, pie de página, Biomecánica y Mareas. En Informes la opción pasa a «Datos GPS», desactivada por defecto. Las exportaciones CSV/Core no cambian.
- **Análisis centrado en el caballo:** caballo · jinete · modalidad a la derecha del título; sección «Análisis del caballo» (aires del motor, zonas de velocidad, esfuerzo, aceleraciones/frenadas validadas, curvas, marcha de la cincha) solo con datos medidos; el mosaico de altitud pasa a «Esfuerzo · tiempo en movimiento».
- **Inicio sin menú lateral** (botón «Menú» arriba a la izquierda); accesos «Entrenamientos» y «Análisis» en Inicio.
- **Comparar:** columna derecha con un único desplazamiento vertical (recorridos, velocidad, aceleración, IMU cincha → desvíos laterales e inclinaciones, cadencia del motor, estadísticas y motor al final); `Views/CompareImuSeries.swift`.
- Diagrama de la cincha: las etiquetas ya no se cortan en el borde.
**Archivos:** `ipad/AVOiPad/App/{GpsModel,AppModel,AppModel+Shell,RootView,MapModel,SegmentsModel,ReportsModel,CompareModel,BiomechModel}.swift`, `ipad/AVOiPad/Views/{GpsView,CompareImuSeries,AnalysisView,MapPageView,SegmentsView,CompareView,EngineView,HomeView,StableView,StartView,ReportsView,BiomechView,HorseDiagramView,TidesView,SharedShellComponents}.swift`, `ipad/AVOiPadUITests/ScreenshotTests.swift`.
**No se ha tocado:** núcleo (`Core/`, `Engine/`), Gráficas, Reloj Wi‑Fi/BLE.
**Validación:** IMPLEMENTADO · sin compilar en la sesión (CI macOS pendiente) · NO VERIFICADO en iPad.

---

## 2026-11-01 — iPad 1.0.0 — duplicado de la app Windows V2 PRO para iPad Pro M4 (SwiftUI nativo)
**Autor:** Claude · **Rama:** `feature/ipad-app` (sale de `feature/windows-girth-movimiento` `8101304`)
**Qué cambia:**
- **Nueva app `ipad/`**, nativa en SwiftUI para iPadOS 17 o posterior, con las 16 pantallas de Windows: Inicio, Entrenamientos, Cuadra, Jinetes, Análisis, Mapa (Esri satélite/híbrido con caché, o vectorial sin conexión, más reproducción), Gráficas sincronizadas, Tramos, Biomecánica, Comparar, Geocercas y líneas, Mareas y entorno, Informes, Servidor y Motor, además de la hoja Asignar.
- **Núcleo portado de `AVO.Windows.Core` a Swift** con los mismos formatos y cálculos:
  - lectura de `.avo` y `.avr` con SHA-256 y lector ZIP propio;
  - filtro Kalman con suavizado RTS, tramos, comparador, entorno IHM y Open-Meteo;
  - informes PDF (escritor propio), HTML, CSV, GPX y JSON;
  - `cuadra.json`, `geocercas.json` y `recortes.json`, intercambiables con Windows.
- **Motor C++ AVO Equine:** el mismo código fuente compilado dentro de la app, con su API en C.
- **Reloj:**
  - protocolo BLE portado de Windows/Android, con la clave en el llavero de iOS;
  - envío y lectura de geocercas;
  - **descarga por Wi‑Fi** (`WIFI_SYNC` + HTTP, pecho ≥ 3.7.4) en lugar del USB.
- **Sin NFC:** el iPad no tiene NFC.
- **CI `build-avo-ipad.yml` (macOS):**
  - sesiones DEMO, XcodeGen y compilación;
  - XCTest en el simulador del iPad Pro 13" (M4);
  - capturas en horizontal y vertical en `ci/ipad-visual-evidence`;
  - subida a TestFlight cuando están los secretos `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` y `ASC_KEY_P8_BASE64` (ver `ipad/README.md`).
**Por qué:** usar la app de análisis en el iPad Pro M4.
**Archivos:** `ipad/**`, `.github/workflows/build-avo-ipad.yml`.
**No se ha tocado:** `windows/`, Android, firmware y motor (solo se compilan).
**Validación:** COMPILADO / CI run 41297030454 (`commit` de la rama): compilación, 51 pruebas unitarias en verde (formatos, seguridad, algoritmos, vectores del reloj, Wi‑Fi simulado, motor, sesiones DEMO) y 32 capturas. **NO VERIFICADO** en un iPad real, con el reloj por Bluetooth o Wi‑Fi, ni con sesiones reales.
**TestFlight:** compilación 1.0.0 (8) firmada con Xcode 26.6 y subida a App Store Connect (`org.avoperformance.horse.ipad`, equipo 4J2D6P5BJX), run 41307176561, 01/11/2026 13:40.
**Pendiente:** probar en el iPad, probar la descarga Wi‑Fi con un pecho 3.7.4 o posterior, e integrar en develop.

## 2026-10-31 — Windows V2 PRO — geocercas, líneas de salida y meta con sentido, y envío al reloj por Bluetooth
**Autor:** Claude · **Rama:** `feature/windows-advanced-analysis`
**Qué cambia:**
- **Página «Geocercas y líneas»:** mapa editable por clic con los 8 huecos de geocerca del reloj (círculo de 5 m a 5 km o polígono de hasta 24 vértices, activa o no) y sus 4 líneas virtuales (extremos A y B, uso salida y meta, salida, meta o control, y sentido que marca).
  - Las validaciones son las de `validate_fence()`.
  - Los cruces del entrenamiento abierto aparecen con su sentido y con «Marca» o «No marca», junto con las vueltas y los tiempos de salida a meta.
  - «Crear tramos» convierte esos tiempos en tramos.
- **Enviar al reloj / Leer del reloj** por Bluetooth del PC (WinRT), con el **mismo protocolo y formato que la app Android** (portado de `BleProtocol.kt`, `AvoClient.kt`, `WatchConfig.kt` y `Fence.kt`):
  - emparejamiento sin código y autorización del PC con BOOT, la misma reclamación de Android;
  - clave guardada con DPAPI por usuario;
  - `SET_FENCE` por hueco, `SET_ACTIVE_FENCES` y `SET_CONFIG` leer-modificar-escribir solo para las líneas;
  - comprobación final con `GET_CONFIG`.
  - Antes de enviar se confirma la lista de cambios. Solo se envía lo que cambia y se conservan la identidad y las secciones desconocidas.
**Limitación del reloj (no se ha tocado el firmware):** el pecho cuenta los cruces de las líneas en los dos sentidos.
- `VirtualLine` no tiene campo de sentido y `crosses()` es simétrico.
- El sentido se guarda en el PC y se aplica al analizar el entrenamiento.
- La línea 1 es la que el reloj usa para cronometrar vueltas.
- Para que el reloj marque solo en un sentido habría que ampliar el firmware: un byte de sentido al final de la sección de línea, que el formato permite.
**Archivos:**
- `windows/AVO.Windows.Core/Watch/{AvoBle.cs,AvoConfig.cs,Geofences.cs}`, `windows/AVO.Windows/Ble/WinBle.cs`;
- `ViewModels/MainViewModel.Geofences.cs`, `Views/GeofencesView.*`, `Controls/MapControl.cs` (formas y clic);
- csproj: TFM `net10.0-windows10.0.19041.0` y DPAPI;
- `windows/tools/watch-vectors/`, `AVO.Windows.SelfTest/{WatchTests.cs,watch_vectors.json}`.
**Validación:**
- IMPLEMENTADO.
- Las autopruebas comprueban la configuración, las geocercas, los fragmentos BLE, las pruebas HMAC y el test de cruce **byte a byte contra el código real del firmware**.
- Flujo completo (autorización con BOOT, envío, verificación y rechazo sin autorización) contra un reloj simulado.
- **NO VERIFICADO con el reloj ni con Bluetooth real.**

## 2026-10-31 — Windows V2 PRO — pantalla de inicio: logo y letras nítidos (vectoriales)
**Autor:** Claude · **Rama:** `feature/windows-advanced-analysis`
**Qué cambia:**
- **Antes:** la foto de inicio (recorte ampliado ×3 de CONCEPTO_02) llevaba la cabeza de caballo y los textos incrustados y borrosos.
- **Foto:** se han borrado de ella con *inpainting* (OpenCV); la escena no cambia.
- **Cabeza de caballo:** trazada desde el original como contornos de grosor variable.
- **«AVO»:** reconstruido geométricamente con las medidas del original.
- **Textos:** PERFORMANCE HORSE, TRAINING ANALYSIS y CIENCIA · TECNOLOGÍA · RENDIMIENTO pasan a contornos de Montserrat (OFL), con el interletrado ajustado al ancho original.
- **Resultado:** todo se dibuja en vectores sobre la foto (`Views/HeroArt.xaml`), así que se ve nítido a cualquier tamaño y escala.
**Por qué:** lo pidió el usuario. Las letras y la cabeza del caballo se veían borrosas en el PC.
**Archivos:** `windows/AVO.Windows/{Views/HeroArt.xaml(.cs),Views/StartView.xaml,Assets/avo_home_hero.jpg}`, `windows/tools/hero-art/`.
**Validación:** IMPLEMENTADO · capturas del CI.

## 2026-10-31 — Windows V2 PRO — Cuadra, Jinetes, asignación de entrenamientos y lector NFC USB
**Autor:** Claude · **Rama:** `feature/windows-advanced-analysis` · **Commits:** ver `git log`
**Qué cambia:**
- **Cuadra y Jinetes:** páginas nuevas en el menú lateral.
  - Fichas con los campos de Android (`HorseEntity`/`RiderEntity`).
  - Cada ficha muestra sus entrenamientos, totales (entrenamientos, km, tiempo, velocidad máxima, último) y la etiqueta NFC asociada.
  - Los caballos y jinetes que traen los archivos importados se dan de alta solos: por código, o por nombre si no hay código. Los de demostración quedan marcados DEMO.
- **Asignar caballo y jinete** a un entrenamiento, desde la cabecera, la lista de entrenamientos o la ficha.
  - Si se escribe un nombre nuevo, se crea su ficha.
  - Opción para rellenar lo que falte en los demás entrenamientos.
  - Botón «Asignar a los N sin caballo/jinete» en la ficha.
  - Orden de prioridad: asignación del usuario > código del archivo > nombre del archivo.
  - Solo se cambian los metadatos en el PC (`cuadra.json`); el archivo no se toca.
- **Lector NFC USB PC/SC** (`winscard.dll`):
  - Lee las etiquetas `avohorse://identity/horse|rider/…` de la app Android con las mismas validaciones que `AvoNfc.import`, incluidas las tarjetas de usuario con licencia. Nunca sobrescribe una ficha existente.
  - Rellena el panel Asignar.
  - Graba fichas en NTAG213/215/216 con el mismo NDEF que `NfcScreen` de Android y lo verifica leyéndolo.
  - Solo escribe el área NDEF y rechaza las etiquetas bloqueadas.
**Por qué:** lo pidió el usuario. Quiere los caballos con sus entrenamientos, los jinetes con los suyos, asignar los entrenamientos que llegan sin ellos y registrar caballos y jinetes por NFC.
**Archivos:**
- `windows/AVO.Windows.Core/Stable/{Stable.cs,Nfc.cs}`; `Models.cs`, `TrainingImporter.cs`, `RawReader.cs` (código del archivo) y `SessionTimeline.cs`;
- `windows/AVO.Windows/ViewModels/{MainViewModel.Stable.cs,SessionItem.cs,Mvvm.cs,MainViewModel.cs}`, `Views/StableView.*`, `MainWindow.xaml`, `HomeView.xaml`, temas;
- `App.xaml.cs`: recorrido NFC en el modo captura;
- `windows/AVO.Windows.SelfTest/StableTests.cs`.
**No se ha tocado:** firmware, Android ni el formato de los archivos.
**Validación:**
- IMPLEMENTADO.
- Autopruebas de URI, NDEF, NTAG215 simulada tras un lector PC/SC y almacén.
- Recorrido NFC en el modo captura de CI con lector simulado.
- **NO VERIFICADO con un lector NFC real ni con etiquetas físicas.**

## 2026-10-30 — Windows Advanced Analysis V2 PRO 2.0.0 (rama feature/windows-advanced-analysis)
**Autor:** Claude · **Commits:** `2d3383c` (importa motor EIE + Windows de `feature/avo-wifi-sync`), `f9f9fdc` (integra develop
18a9823), `18bbe5c`…`f626309` · **CI:** build-avo-windows run [41084991763](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41084991763) (éxito: 106 autopruebas, publicación, 33 capturas)
**Qué cambia:** nueva app Windows V2 PRO sobre la V1 con motor (pestaña «Motor AVO» de EIE): paleta de `Theme.kt`, componentes
XAML reutilizables, MVVM, 11 vistas (inicio, análisis, mapa satélite/híbrido Esri con reproducción, gráficas sincronizadas con
el mapa, tramos persistentes, biomecánica con el motor, comparador, mareas IHM + Open-Meteo, informes PDF/HTML/CSV/GPX/JSON,
servidor no conectado, motor). Lectura RAW ampliada (todos los campos de GNSS_SAMPLE, IMU_SAMPLE 9 ejes en LSB, MARKER),
velocidad reportada/derivada/filtrada (Kalman + RTS documentado), biblioteca con SHA-256 y duplicados, registro JSON.
Generador de sesiones de DEMOSTRACIÓN sintéticas (`windows/tools/demo-fixtures`) y modo `--capture` para evidencia visual.
**Por qué:** encargo «Windows Advanced Analysis V2 PRO» con las referencias `AVO_WINDOWS_CONCEPTO_01/02`.
**Archivos:** `windows/**`, `equine-intelligence/**` (copia sin cambios de wifi-sync), `.github/workflows/build-avo-windows.yml`,
`build-equine-engine.yml`, `core/src/test/resources/equine/*` (fixtures).
**No se ha tocado:** Android, firmware, motor C++ (solo se compila y se usa).
**Validación:** IMPLEMENTADO · COMPILADO / CI (run 41084991763, `f626309`) · PROBADO AUTOMÁTICAMENTE (106 comprobaciones) ·
**NO VERIFICADO** con sesiones reales con cincha (no existen) ni manualmente en un PC con Windows.
**Actualización 30/10 17:30:** pantalla de inicio reproducida como en `AVO_WINDOWS_CONCEPTO_02` (foto, logotipo y lema
recortados de la imagen de referencia del usuario, acciones reales a la derecha, ventana sin barra ni menú en el inicio); el
panel anterior pasa a «Entrenamientos». La foto sale de la maqueta (1536×1024) y se reescala: sustituible por un original
de alta resolución en `windows/AVO.Windows/Assets/avo_home_hero.jpg`.
**Actualización 30/10 21:45:** las 5 acciones del inicio son funcionales y se comprueban en CI pulsándolas por UI Automation
(abrir → importa y abre «Análisis»; recientes → «Entrenamientos» con historial y favoritos persistentes; servidor; comparar; informes).
**Actualización 30/10 23:30 (tras la primera prueba del usuario en su PC, sin entrenamientos):** mapa centrado en el Regatón
cuando no hay recorrido (antes mostraba océano 0°,0° con teselas «Map data not yet available»), panel claro «Todavía no hay
entrenamientos» con «Abrir» y «Cargar demostración» (descarga las sesiones SINTÉTICAS publicadas en la pre-release).
Descarga directa: pre-release `windows-v2-pro-latest` (EXE único con el motor incluido).
**Actualización 30/10 23:50:** integrada en V2 PRO la descarga automática del reloj por USB de `feature/chest-usb-pc-sync`
(`ChestUsb.cs`, `SimWatch.cs`, `usb_transcript.json` y sus pruebas sin cambios; interfaz portada a MVVM: botón «Reloj USB»,
tarjeta en «Entrenamientos», aviso en el estado vacío, detección por WM_DEVICECHANGE y sondeo cada 4 s). Requiere el
firmware de pecho **3.7.5-usb1** (rama `feature/chest-usb-pc-sync`, NO VERIFICADO); con otro firmware se informa al usuario.
**Actualización 31/10 00:20 (petición del usuario con sesiones reales HORSE_001):** inicio y fin del entrenamiento útil por
sesión («Inicio = cursor», «Fin = cursor», «Usar selección», «Archivo completo» en la cabecera de sesión). Se guarda en
`recortes.json`; todas las vistas, tramos, comparativas e informes usan ese tramo con la base de tiempo del archivo completo.
**Pendiente:** prueba manual en Windows; sesiones reales `.avo`; calibración/orientación IMU; contrato del servidor; firma
del ejecutable; modelo 3D autorizado; integración en develop.

---

## 2026-10-23 — Copias de código fuente y traspaso para asistentes
**Autor:** Claude · Zips en la raíz: `AVO_ANDROID_V2_0_REDISENO_MAREAS_ANALISIS_FUENTES.zip` (actualizado),
`AVO_UPDATER_V2_1_0_FUENTES.zip`, `AVO_BACK_V3_8_0_FUENTES.zip`. Documento `docs/TRASPASO_ASISTENTES_2026-10-23.md`
con versiones, carpetas, CI, arquitectura y reglas. `AGENTS.md` apunta a él. Sin cambios de código.

---

## 2026-10-23 — ESPALDA V3.8.0 (máxima precisión RTK) + USB Updater 2.1.0 (instala en la espalda)
**Autor:** Claude · **CI:** espalda [40015971416](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40015971416) (éxito, artefacto `AVO-BACK-V3-8-0-HELTEC`) · updater [40015367842](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40015367842) (éxito)
**Origen:** copia de la espalda leída con la app (AVO BACK **3.5.0**, Arduino-ESP32 3.3.12). Fuente: `AVO_BACK_V3_5_0.ino`
del paquete `firmware/chest/V3_5_4` + `avo_core` de 3.7.0-rc2. Nuevo paquete independiente `firmware/back/V3_8_0`
(el pecho conserva su propia copia de `avo_core`; **no se toca el firmware del pecho**).
**Qué cambia en la espalda:** 8 Hz con 4 constelaciones (límite RTK del ZED-F9P; la 3.5.0 pedía 10 Hz), constelaciones
según el ritmo pedido por el pecho (10 Hz sin BDS, 12 Hz GPS+GAL), RTK fijo explícito, modelo Airborne <2g, máscara 10°,
perfil en VALSET aparte con degradación segura, RTCM al ZED también durante la reconfiguración, Wi-Fi sin ahorro de
energía y a potencia máxima, ACK de ESP-NOW 25 ms, cola de 48, monitor serie con búfer, marcador `AVO-BACK`.
**Protocolo con el pecho:** sin cambios.
**USB Updater 2.1.0:** instalación también en la espalda por CP2102 (reinicio ClassicReset, comprobación de arranque por
el mismo enlace y relectura de otadata); bloquea firmware del pecho en la espalda y viceversa; identifica «AVO-BACK x.y.z».
**Validación:** espalda: 23 casos / 159 comprobaciones en ordenador (ZED simulado) y compilación CI (868 KB, 25 % de app0);
updater: 65 pruebas JVM. **NO VERIFICADO** en hardware.
**Pendiente:** instalar en la espalda, comprobar en el monitor serie `perfil=COMPLETO` y `ritmo=8 Hz (medido 8.0 Hz)`, y
comparar tiempo hasta RTK FIX y % de FIX en un entrenamiento frente a la 3.5.0.

---

## 2026-10-23 — USB Updater 2.0.1 — lectura fiable con la espalda Heltec (CP2102)
**Autor:** Claude · **CI:** [40011606283](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40011606283) (**éxito**)
**Prueba física (capturas del usuario, 21:14–21:15):** espalda Heltec por CP2102: «Información del dispositivo» **correcta**
(ESP32-S3 v0.2, MAC AC:A7:04:06:CD:24, flash GD 8 MB, sin Secure Boot ni cifrado, particiones Arduino por defecto
app0/app1 3264 KB + spiffs 1536 KB + coredump; arranca app0: Arduino (ESP-IDF v5.5.5), compilado el 16-09-2026 21:14:44).
**Fallo:** «Leer firmware» y «Copia completa» se detuvieron con «bloque de 3302 bytes en 0x11000» / «4030 bytes en 0x47000»:
se perdían bytes a 921 600 baudios con 64 bloques en vuelo (el CP2102 tiene un búfer muy pequeño). La verificación lo detectó y no guardó nada.
**Corrección:** en puentes USB-UART 460 800 baudios, 2 bloques en vuelo, piezas de 64 KB que solo se escriben si su MD5
coincide, y hasta 4 reintentos por pieza reiniciando el chip y recargando el stub. USB nativo sin cambios.
**Validación:** 64 pruebas JVM en local · **NO VERIFICADO** de nuevo con la Heltec.

---

## 2026-10-23 — USB Updater 2.0.0 — lectura, identificación y copia de seguridad (pecho y espalda) + diseño AVO 2.0
**Autor:** Claude · **Commits:** `7327094` · **CI:** [40009097029](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40009097029) (**éxito**)
**Qué cambia:**
- Nueva sección **Lectura y copia de seguridad** (solo lectura): información del dispositivo (chip, MAC, flash, seguridad,
  particiones, otadata, descriptor de cada app), **leer firmware** (app que arranca, recortada, SHA-256 y textos
  identificativos), **leer partición**, **copia completa de la flash** e informe `.txt`. Archivos guardados con el selector de Android.
- Soporte del módulo de **espalda Heltec Wireless Stick Lite V3**: puente **CP2102** (`Cp210xLink`, protocolo AN571) y
  CDC genéricos (CH9102/CH343); reinicio `ClassicReset` por DTR/RTS; filtro USB ampliado.
- Lectura rápida con el **stub oficial de Espressif** esp-flasher-stub v1.4.1 (Apache-2.0/MIT, `assets/stub/` con licencias)
  y 921 600 baudios; cada bloque comprobado con el MD5 del chip.
- Diseño de la app 2.0: colores AVO, tarjetas y botones como la app de entrenamiento, **pantalla de inicio** con la imagen
  AVO y el estado del programador (USB OTG, dispositivo, permiso, instalador, lectura rápida, almacenamiento). Su botón
  «ENTRAR AHORA» queda por encima de la barra de navegación. Icono AVO.
- versionCode 20 / versionName 2.0.0; artefacto `AVO-Performance-Horse-Update-V2-0-0-DEBUG`.
- Comprobaciones de seguridad del CI: la carga en RAM solo puede estar en `StubFlasher.kt` y el código de lectura no puede usar comandos de escritura ni borrado.
**No se ha tocado:** el flujo de instalación del pecho (planificador, escritura, otadata, verificación).
**Validación:** IMPLEMENTADO · 64 pruebas JVM en local (incluida la lectura completa con stub simulado y la garantía de que la flash no cambia) · **NO VERIFICADO** con la Heltec ni con el pecho.
**Pendiente:** probar con la espalda real; si el reinicio automático no entra en modo descarga, usar PRG + RST.

---

## 2026-10-23 — Android V2.0 — rediseño AVO, mareas IHM estilo Tu Marea Pro, análisis de entrenamientos, sin OTA
**Autor:** Claude · **Commits:** `049abc7` (+ documentación y zip) · **CI:** [39998714393](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39998714393) (**éxito**: pruebas core, pruebas JVM app y APK debug `AVO_Performance_Horse_V2_0_debug.apk`)
**Qué cambia:**
- Tema con los colores de la pantalla de arranque (negro, rojo AVO, plata, azul). Nuevos componentes: `MetricTile`, `MetricGrid`, `Segmented`, `ScreenHeader`; `AvoCard` con degradado y `trailing`.
- Navegación: Inicio · Entrenar · Historial · Mareas · Cuadra + engranaje de Ajustes. Inicio, Entrenar, Historial y Cuadra rediseñados; textos explicativos eliminados.
- Mareas (`tide/TideRepository.kt`, `core/tide/Tides.kt`): predicción oficial IHM (`ideihm.covam.es/api-ihm/getmarea`), puerto más cercano o elegido, curva coseno entre extremos, coeficiente 70 × carrera / carrera media (3 meses), sol y luna locales, Open-Meteo por horas, caché en disco. Pantalla estilo Tu Marea Pro con curva deslizable.
- Análisis (`core/raw/TrainingInsights.kt`): aceleración/frenada en g, altitud, desnivel y pendiente, aires por velocidad, tramos rápidos, parciales, eventos, cadencia de la IMU de la cincha (autocorrelación, sin escala). Pantalla Resumen / Mapa y gráficas / Datos con mapa Mapa/Satélite/Híbrido y gráficas sincronizadas con zoom común.
- Condiciones de la sesión para cualquier fecha (IHM + Open-Meteo, archivo histórico).
- Foto del caballo; Room 3 → 4 (`horses.photoPath`).
- Ajustes: lugar de entrenamiento (nombre y coordenadas, o posición del chaleco).
- OTA retirada por completo: `ota/`, `ChestOtaProtocol`, `MsgType.OTA_*`, `supportsOta`, tarjeta de Inicio, sección de Dispositivos y workflow `diagnose-android-ota.yml`.
- versionCode 12 / versionName 2.0; el workflow publica `AVO-Performance-Horse-V2-0-APK` y convierte los errores `e:` de Kotlin en anotaciones.
- `AVO_ANDROID_V2_0_REDISENO_MAREAS_ANALISIS_FUENTES.zip` en la raíz con app/, core/, gradle/ y `RELEASE_NOTES_V2_0.md`.
**No se ha tocado:** pantalla de arranque, BLE, NTRIP/RTCM, sincronización, NFC, geocercas, No molestar, compartir.
**Validación:** IMPLEMENTADO · CI correcto · pruebas core 48/48 en local · **NO VERIFICADO** en móvil.
**Pendiente:** comprobar en el móvil la lectura del IHM y Open-Meteo, comparar horas y coeficientes con Tu Marea, mapa híbrido y migración con datos reales. Aviso: el botón «ENTRAR AHORA» de la pantalla de arranque queda bajo la barra de navegación de Android (no se ha modificado por petición del usuario).

---

## 2026-10-23 — CHEST V3.7.2-rc1 — correcciones tras la primera prueba física (brillo en carga, cambio de pantalla, esquinas)
**Autor:** Claude · **Commits:** `6477310` · **CI:** [39968163291](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39968163291) (**éxito**; RAM estática sin cambios, 71.048 B)
**Prueba física (fotos del usuario, 16:12):** CHEST con 3.7.2-rc1 instalado. **Correcto:** orientación (BLUETOOTH arriba),
legibilidad, «V3.7.2-RC1», BLE conectado, espalda conectada (RSSI −64/−70 dBm), GPS DGNSS con 25 satélites, SD disponible,
cincha mostrada en rojo «Desconectada» (no estaba conectada), pantalla de carga «59 % CARGANDO USB».
**Fallos observados:** (1) brillo de carga demasiado bajo; (2) al desconectar el cargador quedaban restos del anillo de
carga entre las franjas; (3) la franja superior e inferior se cortaban en las esquinas curvas (icono BT, círculo de estado,
icono de batería y «%»).
**Causas y correcciones:**
1. El brillo con USB estaba fijado a 25. Ahora: 255 durante 15 s al conectar, al tocar o al pulsar BOOT/POWER; luego 25.
2. Al quitar el USB se borraba `charge_screen` antes de comprobarlo, así que solo se repintaban las franjas cambiadas.
   Ahora `ui.cpp` registra qué pantalla hay realmente en el panel (`Shown`) y cualquier vuelta a las franjas las repinta todas.
3. El área visible tiene esquinas de ~120 px (estimado con las fotos). Franjas de 62 px con 19 px de margen arriba/abajo;
   la 1 y la 7 siguen la curva y su contenido entra 24 px. Nueva comprobación en ordenador: ningún píxel de contenido
   fuera del área visible.
**No se ha tocado:** comunicaciones, NTRIP, GNSS, OTA ni almacenamiento.
**Validación:** comprobaciones en ordenador correctas; **pendiente de ver en el reloj** las tres correcciones.

## 2026-10-23 — Documentación — registro común y reglas para asistentes
**Autor:** Claude · **Commits:** ver el commit que añade este archivo
**Qué cambia:** se crean este registro, `AGENTS.md` (reglas para cualquier asistente) y `CLAUDE.md` (remite a
`AGENTS.md`). Se actualizan `README.md` y `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` con el programador USB y CHEST 3.7.x.
**Por qué:** petición del usuario: que todos los cambios queden documentados en la rama de GitHub, centralizados
entre Claude y ChatGPT.
**Validación:** documentación; no aplica CI de firmware ni de Android.

## 2026-10-23 — CHEST V3.7.2-rc1 — pantallas de carga USB y apagado seguro por fases reales
**Autor:** Claude · **Commits:** `b2a8fb3`, `3e85c41` · **CI:** [39964200690](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39964200690) (fallo: colisión con macros de color de Arduino_GFX), [39965639870](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39965639870) (**éxito**)
**Qué cambia:**
- Pantalla de carga según referencia del usuario: anillo con extremos redondeados, batería con nivel real y rayo,
  porcentaje grande, «CARGANDO USB» / «CARGA COMPLETA» / «USB CONECTADO». En 3.7.1 la función existía pero **no se
  llamaba** (aviso `render_charging defined but not used`). Ahora se muestra con USB salvo si se está grabando;
  un toque corto (< 0,8 s) alterna 30 s con las siete franjas.
- Pantalla de apagado: icono, «APAGANDO...», «Guardando entrenamiento» y barra de **4 fases reales**
  (1 detener sesión, 2 cerrar archivos SD, 3 guardar caja negra, 4 apagar). Si la SD no se cierra, el firmware
  ya cancelaba el apagado; ahora se muestra «NO SE PUDO GUARDAR — El reloj sigue encendido» durante 6 s.
- Constantes de color renombradas a `C_*` porque Arduino_GFX define `GREEN`, `RED`, `BLUE`, `YELLOW`, `WHITE` como macros.
- El workflow publica errores de compilación y uso de memoria como anotaciones.
**Archivos:** `firmware/chest/V3_7_2_UI/` (`src/ui*.{h,cpp}`, `tools/apply_v372.py`, `tools/gen_ui_assets.py`), `.github/workflows/build-chest-v372-ui.yml`.
**Cambios fuera de la pantalla:** `tools/apply_v372.py` añade `shutdown_phase` y `shutdown_fail_ms` a `PowerState` y
6 líneas en `controlled_shutdown()` (controller.cpp) que publican la fase, más 300 ms antes de `pmu_power_off()`.
**No se ha tocado (petición expresa del usuario):** BLE, ESP-NOW, UART, NTRIP/RTCM, GNSS, OTA ni almacenamiento.
El orden del apagado es el mismo.
**Validación:** COMPILADO / CI (39965639870). Comprobaciones en ordenador con el mismo código de dibujo (panel simulado):
correctas. **NO VERIFICADO en el reloj.**

## 2026-10-23 — CHEST V3.7.2-rc1 — pantalla de siete franjas legible, sin LVGL
**Autor:** Claude · **Commits:** `f60c125` · **CI:** [39963751268](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39963751268) (fallo: la prueba nueva detectaba «LVGL» dentro de un comentario; corregido en `b2a8fb3`)
**Problema observado (foto del usuario, 3.7.1-rc2):** imagen girada 180°, texto ilegible y bordes en escalera.
**Causas:** `setRotation(0)` con el panel montado al revés; fuente interna 5×7 a escala 1–2 (6–14 px);
el CO5300 exige columnas/filas pares y Arduino_GFX dibujaba anchos impares.
**Qué cambia:**
- Nuevo motor `ui_fb`: framebuffer RGB565 410×502 en **PSRAM** (402 KB de 8 MB), primitivas suavizadas, texto UTF-8,
  envío alineado a pares y **giro 180° por software** (el controlador sigue en rotación 0 y conserva su
  desplazamiento de columna de 22 px; `setRotation(2)` lo pondría a 0).
- `ui_dash` (diseño), `ui_model` (estado real → franjas según `V3_5_9/UI_7_FRANJAS_ESPECIFICACION.md`),
  `ui_assets.h` generado: fuentes Barlow Condensed (SIL OFL) e iconos Font Awesome Free 7 (OFL / CC BY 4.0), 148 KB en flash.
- Solo se redibujan las franjas que cambian. Con la SD grabando **solo parpadea el punto rojo** (500 ms), a petición del usuario.
- GPS: rojo sin GNSS, azul autónomo, verde con correcciones NTRIP aplicadas. Batería: verde >50 %, amarillo 21–50 %, rojo ≤20 %.
- **Sin LVGL** (el usuario indica que LVGL satura la RAM interna y rompe BLE y el enlace con la espalda).
**Memoria (CI 39965639870):** RAM estática 71.048 B frente a 70.328 B en 3.7.1-rc2 (+720 B); más un búfer de envío
dinámico de 13 KB en RAM interna. Flash del programa: 1.528.319 B.
**Validación:** COMPILADO / CI. **NO VERIFICADO en el reloj.**
**Pendiente en el reloj:** orientación (BLUETOOTH arriba) sin desplazamiento lateral; esquinas de la primera y la
última franja; parpadeo del punto; línea serie `[AVO MEM] UI V3.7.2`; BLE y espalda estables; margen de pila de la
tarea UI (4 KB, sin cambios). Con USB el brillo sigue limitado a 25 (como 3.7.1).

## 2026-10-23 — Programador USB 1.8.0-beta2 — versión AVO real en los BIN de Arduino
**Autor:** Claude · **Commits:** `a0d2d32` · **CI:** [39963751136](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39963751136) (**éxito**, SHA `f60c125` que incluye `a0d2d32`)
**Qué cambia:** Arduino escribe `arduino-lib-builder <hash>` en `esp_app_desc_t`; la app lo mostraba como versión.
Ahora se lee `AVO_FW_VERSION` junto a `AVO-CHEST` en el primer segmento y la marca `AVOCHEST-IMG-V1:WS-AMOLED-2.06`.
Se usa para la etiqueta, la descripción de los slots (lectura de 1 KB) y la confirmación de arranque por USB.
**Comprobado con archivos reales del usuario:** `AVO_CHEST_V3_7_1_RC2_OTA_UNVERIFIED.bin` (1.364.544 B, SHA-256
`6ca9c695…cbee`) válido: 7 segmentos, checksum y SHA-256 adjunto correctos, versión «AVO-CHEST 3.7.1-rc2».
Tabla `AVO_CHEST_V3_5_0.ino.partitions.bin` = nvs 0x9000, otadata 0xE000, app0 0x10000, app1 0x610000 (6 MB),
blackbox 0xC10000, coredump 0xC50000, con registro MD5. Bootloader: flash 16 MB.
**Validación:** CI, 59 pruebas unitarias. **NO VERIFICADO con el reloj.**

## 2026-10-23 — Programador USB 1.8.0-beta1 — programador completo (bloques A–E)
**Autor:** Claude · **Commits:** `14fdeac` (A), `8a954fd` (B), `346e459` (C), `652344e` (D), `620844c` (E) · **CI:** [39959974774](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39959974774) (**éxito**)
**Qué cambia:**
- A: cliente ROM ESP32-S3 (estado de 4 bytes, SYNC, READ/WRITE_REG, GET_SECURITY_INFO, SPI_ATTACH/SET_PARAMS,
  watchdogs), lectura de flash por registros SPI1 **verificada con el MD5 del propio chip**, tabla de particiones, otadata, slots.
- B: validación completa del BIN (segmentos, checksum, SHA-256 adjunto, descriptor, revisión de chip). Sustituye
  `FlashWriter` (usaba el formato FLASH_BEGIN de ESP32 y leía mal el estado).
- C: planificador (actualización normal / recuperación USB), FLASH_BEGIN S3 de 5 palabras, verificación MD5,
  huellas de zonas protegidas, activación `otadata` como `esp_ota_set_boot_partition()`, reinicio por DTR/RTS y
  comprobación del primer arranque.
- D: interfaz Android en español, hilo de trabajo, cancelación segura, permisos tras re-enumeración, filtro USB 303A:1001.
- E: ESP32-S3 simulado y pruebas; workflow con comprobaciones de seguridad.
**Seguridad:** solo se escribe el slot OTA destino y una copia de otadata; nunca bootloader, tabla, NVS, blackbox
ni coredump. Bloqueo con Secure Boot, Flash Encryption o Secure Download.
**Validación:** CI (58 pruebas en simulación). **NO VERIFICADO con el reloj.** Primera prueba física: solo «LEER RELOJ».
**Detalle:** `usb-updater/README.md`, `usb-updater/docs/VERIFICACION_V1_8_0.md`.

## Historial anterior
Ver `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` (hasta CHEST V3.5.7, 22/10/2026) y los README de `firmware/chest/V3_*`.
Las versiones CHEST 3.6.x, 3.7.0-rc1/rc2 y 3.7.1-rc2 constan en sus carpetas y workflows (`build-chest-v3*.yml`)
pero no tenían entrada en este registro.
