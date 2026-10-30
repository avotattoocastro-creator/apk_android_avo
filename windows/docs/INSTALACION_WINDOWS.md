# AVO Performance Horse — Windows Advanced Analysis V2 PRO · Instalación

## Requisitos
- Windows 10 (1903 o posterior) u 11, 64 bits (x64).
- No necesita instalar .NET: la aplicación es **portable y autocontenida** (incluye el runtime .NET 10).
- Conexión a Internet opcional: solo para las teselas del mapa satélite (Esri), mareas (IHM) y meteorología (Open-Meteo).
  Todo lo demás funciona sin conexión.

## Descarga
1. GitHub → Actions → workflow **«AVO Windows - build, tests, screenshots and package»** → ejecución en verde de la rama
   `feature/windows-advanced-analysis`.
2. Artefacto **`AVO-Windows-V2-PRO-x64`** (ZIP). Opcional: **`AVO-Windows-V2-demo-sintetica`** (sesiones de demostración
   SINTÉTICAS para probar la aplicación sin datos reales).

## Instalación
1. Extraer el ZIP en una carpeta con permisos de escritura (por ejemplo `C:\AVO\Windows`).
2. Mantener juntos `AVO.Performance.Horse.Windows.exe` y `avo_equine.dll` (motor de análisis AVO).
3. Ejecutar `AVO.Performance.Horse.Windows.exe`.
   - La distribución **no está firmada digitalmente**: Windows SmartScreen puede mostrar «Windows protegió su PC».
     Pulsar «Más información» → «Ejecutar de todas formas» solo si el ZIP procede del artefacto oficial de GitHub Actions.

## Uso básico
- **Abrir**: archivos `.avo` exportados por la app Android (o `.avr` RAW de la SD). También se pueden arrastrar a la ventana.
- Los archivos se validan (manifiesto, SHA-256 por segmento, CRC de bloques) y se copian sin cambios a la biblioteca local.
  El original nunca se modifica.
- Datos de la aplicación: `%LOCALAPPDATA%\AVO Performance Horse\Windows\` (biblioteca, tramos, notas, análisis del motor,
  caché de teselas y de entorno, ajustes y **registros** en `registros\avo-windows-AAAAMMDD.log`).

## Desinstalación
Borrar la carpeta de la aplicación y, si se desea, `%LOCALAPPDATA%\AVO Performance Horse\Windows\`.

## Depuración
- Registro estructurado JSON por líneas en `registros\`.
- Modo de captura (el mismo que usa CI): `AVO.Performance.Horse.Windows.exe --capture C:\salida --demo C:\demo --root C:\datos_prueba`.
