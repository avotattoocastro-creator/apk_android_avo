# AVO-ASSIGN-1 — Asignación de caballo y jinete a un entrenamiento

Estado: **IMPLEMENTADO en el motor (pruebas en CI)**. Apps: ver el registro de cambios. **NO VERIFICADO** en hardware.

## Problema
Si un entrenamiento se graba con el caballo equivocado (o sin elegirlo), el RAW guarda lo que tenía el reloj en su
configuración (p. ej. `HORSE_001`). Cada app corregía la asignación por su cuenta (Android en su base de datos, Windows
en `cuadra.json`, iPad en su cuadra) y el motor seguía leyendo el RAW: el mismo entrenamiento salía con caballos distintos
según la app.

## Reglas
1. **El RAW (`.avr`) no se modifica nunca.** Su SHA-256 identifica el entrenamiento ante el reloj, en la deduplicación
   de Windows (USB) y en Android (`watchSha256`).
2. **El manifiesto `manifest.json` del `.avo` es la fuente de verdad de la identidad.** Al reasignar, la app reescribe
   **solo** `manifest.json`; los segmentos se copian byte a byte, así que `sha256` y `segmentHashes` no cambian.
3. **Prioridad al leer:** bloque `asignacion` → campos de primer nivel `horseCode`/`horseName`/`riderCode`/`riderName`
   → cabecera del RAW.
4. **El motor recibe la asignación** en las opciones de `avo_eq_analyse_ex` / `avo_eq_compare_ex`:
   `{"asignacion": {"horseCode", "horseName", "riderCode", "riderName"}}` (el bloque del manifiesto tal cual; las
   demás claves se ignoran). La salida lleva `sesion.caballo` / `jinete` (código asignado; si solo hay nombre, el
   nombre), `caballo_nombre` / `jinete_nombre`, `caballo_raw` / `jinete_raw` (lo que dice el RAW) e
   `identidad` = `ASIGNACION` | `RAW`. **Los números del análisis no cambian.** La asignación entra en el hash de
   parámetros: un análisis guardado no se reutiliza tras reasignar.
5. **En origen:** antes de grabar, la app envía al pecho el caballo y el jinete elegidos (sección `T_IDENTITY` de la
   configuración AVOC, que el pecho copia en la cabecera del RAW). Si no hay caballo elegido, avisa antes de empezar.
6. **Entre apps:** al importar un `.avo` cuyo `sha256` ya existe, se actualiza la asignación si la del fichero es más
   reciente (`asignacion.actualizadoUtc`). Nunca se duplica el entrenamiento.

## Formato (aditivo; `format` sigue siendo `AVO-TRAINING-1`)
```json
{
  "format": "AVO-TRAINING-1",
  "sessionId": "S1E8C_000402_002",
  "horseCode": "H_4f9e2597-3fce-48", "horseName": "Zakina",
  "riderCode": "AVO-A66T-F2E9", "riderName": "Andoni Lezama",
  "sha256": "…", "segmentHashes": {"P001.avr": "…"},
  "asignacion": {
    "version": 1,
    "horseCode": "H_4f9e2597-3fce-48", "horseName": "Zakina",
    "riderCode": "AVO-A66T-F2E9", "riderName": "Andoni Lezama",
    "actualizadoUtc": "2026-11-12T23:50:00Z",
    "app": "android | ipad | windows",
    "raw": {"horseCode": "HORSE_001", "riderCode": "AVO-A66T-F2E9"}
  }
}
```
- Los campos de primer nivel y los de `asignacion` deben coincidir: los lectores antiguos solo ven los de primer nivel.
- `raw` guarda lo que dice la cabecera del RAW (`horse_name` / `rider_name`), para no perderlo.
- Un manifiesto sin `asignacion` sigue siendo válido (ficheros anteriores a AVO-ASSIGN-1).

## Línea de comandos
`avo_eq_cli SESION.avr --caballo CODIGO --caballo-nombre NOMBRE --jinete CODIGO --jinete-nombre NOMBRE`
