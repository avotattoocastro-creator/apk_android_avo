# AVO Performance Horse — Windows Advanced Training Analysis V1

Aplicación WPF (.NET 10, Windows 10/11 x64), dependencias de tiempo de ejecución incluidas en la publicación de CI. Abre y valida sesiones Android `.avo` o segmentos RAW `.avr`, compara recorridos reales, genera métricas, tramos, gráficas y exportaciones.

## Abrir y utilizar

1. Descargar el artefacto `AVO-Windows-V1-x64` de GitHub Actions y extraer el ZIP.
2. Ejecutar `AVO.Performance.Horse.Windows.exe` en Windows 10/11 x64.
3. **Abrir entrenamiento** para importar un archivo `.avo` exportado desde la app Android (o `.avr` desde SD).
4. Seleccionar entrenamientos en el lateral; navegar por módulos. La sesión original no se modifica.
5. **Informes** exporta CSV/GPX/HTML (imprimir HTML en navegador para PDF).
6. **Mareas** carga JSON de instantánea **con fuente**, tipo y fecha. Valores faltantes se muestran como "Sin datos".

## Alcance de V1 y limitaciones verificables

- Sin datos reales no hay gráficas, mapa, diagnóstico ni cifras inventadas. El mapa actual es **vectorial offline**, no satélite.
- RAW soportado: `AVORAW1`, GNSS en UART `GNSS_SAMPLE`, contadores de `IMU_SAMPLE`; todavía **no** se extraen aceleraciones XYZ ni simetría biomecánica porque falta validar payload de las 3 IMU.
- Si un bloque está truncado se informa como parcial y no se interpreta ese bloque.
- Los datos marinos deben importarse con su procedencia. No hay proveedor de mareas en directo configurado para Windows.
- Servidor: botón abre el panel, importación manual desde URL HTTPS de archivo `.avo`. **No** hay sincronización bidireccional automática sin contrato/API y autenticación verificados.
- Evaluación visual vs los mockups: `docs/DESIGN_V1.md`.

## Compilación local

```powershell
# PowerShell en Windows con .NET SDK 10
dotnet run --project windows/AVO.Windows.SelfTest -c Release
dotnet publish windows/AVO.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Seguridad

El lector valida tamaños, nombres ZIP, SHA-256 de segmentos, CRCs, tipo de manifiesto y límites; evita descomprimir rutas arbitrarias del ZIP. No se guardan credenciales en el repositorio. La descarga remota permite solo HTTPS y se limita a 100 MB; tratar archivos externos como no confiables.
