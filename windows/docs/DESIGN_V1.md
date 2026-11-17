# AVO PERFORMANCE HORSE — Windows V1

Diseño visual aprobado (22/10/2026): 2 composiciones originales del chat «Desarrollo aplicación Windows de análisis de entrenamientos avanzada», incluidas en `AVO_WINDOWS_REFERENCIAS_UI_V1.zip` del proyecto. **Esas imágenes son objetivo estético, no capturas de funcionamiento.**

## Correspondencia visual

| Composición | Módulo Windows | Evidencia de V1 |
| --- | --- | --- |
| Pantalla de inicio | Inicio | Lista real, métricas sin datos falsos |
| Análisis de ruta | Análisis | Recorrido vectorial GNSS con color velocidad, zoom/arrastre |
| Gráficas sincronizadas | Análisis + Gráficas | Velocity / hAcc y marcador sincronizado |
| Tramos | Tramos | Desglose GNSS de 500 m |
| Biomecánica | Biomecánica | Conteo real de lotes/muestras, sin pseudométricas |
| Comparación | Comparar | Superposición de dos series y resumen |
| Mareas | Mareas | Instantánea JSON con procedencia/tipo/fecha |
| Informes | Informes | CSV, GPX, HTML imprimible a PDF |
| Servidor | Servidor | Acceso al panel y descarga HTTPS validada; no sincronización no contratada |

**Trabajo pendiente para equivalencia visual exacta:** mapas satelitales con proveedor y licencia autorizados, render 3D de cincha/caballo, series físicas calibradas IMU, análisis de marcha, informe PDF renderizado internamente, subida/sync servidor con API autenticada y tests E2E con hardware. No marcar esas funciones como probadas.

## Contratos

- Importar `.avo` ZIP con `manifest.json` que declare `format=AVO-TRAINING-1`, `segmentHashes` por archivo y segmentos bajo `segments/`.
- Para `.avr`: cabecera AVORAW1, CRC32, bloques, trama UART, `GNSS_SAMPLE`; abortar ante bloque truncado y no inventar GNSS.
- Coordenadas provienen del chaleco del jinete; IMU de la cincha del caballo. Las posiciones vacías no se reemplazan por trazados de demostración.
- El SHA de entrenamiento declarado por el reloj no es el SHA del ZIP. La aplicación comprueba hashes de segmento y CRC de RAW; no afirma verificar por su cuenta el hash canónico del reloj.
- Mareas: archivo local JSON con `source`, `kind=prediccion|modelo|medicion`, `timestamp` ISO8601 con zona, magnitudes opcionales. No se hacen predicciones sin proveedor.
- La API del servidor requiere contrato validado; `live.avoperformance.org` es panel, **no** se debe inventar endpoint de subida.

## Compilación y pruebas

- Requiere SDK .NET 10 / Windows runner y WPF. CI: `.github/workflows/build-avo-windows.yml`.
- Tests sin paquetes NuGet de terceros: `dotnet run --project windows/AVO.Windows.SelfTest -c Release`.
- Publicar portable auto-contenido win-x64 en GitHub Actions. La compilación CI no acredita prueba física ni estética exacta.
