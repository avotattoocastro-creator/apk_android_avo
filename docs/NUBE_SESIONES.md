# Nube AVO — entrenamientos en el servidor (Firebase Storage)

Decisión del usuario (20/11/2026): «servidor para subir los entrenamientos que muestre también datos en tiempo real».
- **Tiempo real:** ya existe, es el LIVE (`docs/LIVE_SERVIDOR.md`, Realtime Database `live/`).
- **Entrenamientos completos:** esta Nube, en **Cloud Storage for Firebase** del mismo proyecto
  (`avo-performance-horse-7be14`, plan **Blaze** desde el 20/11/2026).

Sin cambios de contratos binarios ni de firmware: se sube el mismo paquete `.avo` (AVO-TRAINING-1) que ya generan
WhatsApp y Compartir.

## Contrato (igual en Android, iPad y Windows)

| Elemento | Valor |
|---|---|
| Bucket | `avo-performance-horse-7be14.firebasestorage.app` (el bucket por defecto al activar Storage) |
| Ruta | `trainings/<CODIGO_TARJETA>/AVO_<sessionId>.avo` (un solo nivel; caracteres fuera de `A-Za-z0-9_-` → `_`, máx. 130) |
| Contenido | paquete `.avo` AVO-TRAINING-1, máx. **40 MB** |
| Metadatos propios | `sha256` (del `.avo`, **obligatorio**, minúsculas), `fp` (huella de lo empaquetado: SHA-256 del RAW + códigos + nombres de caballo y jinete, separados por U+001F, 16 primeros bytes del SHA-256 en hex), `sessionId`, `horseCode`, `horseName`, `riderCode`, `riderName`, `assignedMs` (ms UTC de la última asignación a mano; 0 = nunca), `startRtcMs`, `distanceM`, `app` |
| Cuenta | la tarjeta AVO: correo `<codigo>@avo-cards.app` + clave de la tarjeta (Firebase Authentication, igual que Compartir y LIVE) |
| Permisos | solo el dueño lista, lee, sube y borra su carpeta (`firebase/storage.rules`). Para enviar a otros se sigue usando Compartir |

Código: `core/.../cloud/CloudSync.kt` (rutas y huellas), `app/.../cloud/CloudBackup.kt` (subida),
`ipad/AVOiPad/Core/CloudStorage.swift`, `windows/AVO.Windows.Core/Services/AvoCloud.cs` (listado y descarga por REST).
Las tres implementaciones comparten los mismos vectores de prueba (`CloudSyncTest.kt`, `CloudStorageTests.swift`,
`CloudTests.cs`).

## Funcionamiento

- **Android 2.11-nube-dev1:** tras cada descarga verificada con el reloj (con caballo y jinete) se lanza la pasada de
  Compartir, que ahora también sube a la nube lo pendiente (hasta 5 por pasada; el resto en la siguiente, cada 15 min o
  al abrir la app). Antes de subir mira el `fp` remoto: si ya está, no sube nada (sirve tras reinstalar). Si se
  reasigna caballo o jinete, la huella cambia y se vuelve a subir. No sube los entrenamientos importados de otros.
  Interruptor y estado en **Compartir › Nube AVO** (activado por defecto; mismas preferencias de red que Compartir).
- **iPad:** página **Servidor › Nube AVO**. Usa la tarjeta guardada en LIVE. «Ver mi nube» lista; «Importar» descarga,
  comprueba el `sha256` y lo importa con las validaciones de siempre.
- **Windows:** página **Servidor › Nube AVO**. Se pega el enlace de la tarjeta (Android: Compartir › Mi cuenta ›
  «Entrar en el iPad») o «código clave». La tarjeta se guarda cifrada con DPAPI en `%LOCALAPPDATA%\…\nube.tarjeta`.

## Cambiar caballo y jinete desde cualquier app (Android 2.12, 20/11/2026)
- **Regla:** gana la asignación más reciente (`assignedMs`), la misma de AVO-ASSIGN-1 al importar.
- **Android:** al asignar (Historial › Asignar, detalle, o la nueva confirmación tras la descarga) guarda la hora y vuelve
  a subir. Antes de subir lee los metadatos de la nube; si allí hay una asignación más nueva (hecha en el iPad o Windows),
  la aplica en el móvil en vez de pisarla. Cada hora repasa todos sus entrenamientos en la nube por si cambiaron.
- **iPad y Windows:** al guardar una asignación (Asignar, o «Cambiar» en la lista de la Nube, que importa el entrenamiento
  si hace falta) reescriben el manifiesto como siempre y, si ese entrenamiento está en la nube, suben el `.avo` nuevo
  (subida «multipart» de Firebase Storage) con `assignedMs` = `asignacion.actualizadoUtc`.
- Vector compartido de la huella: `ab`, `HORSE_001`, `RIDER_001`, `LEZAMA`, `Ana` → `a242c37ddf781698761028f9ea2c649f`.

## Confirmación tras la descarga y directo (Android 2.12)
- Tras cada descarga verificada sale «Confirma caballo y jinete» con lo que grabó el pecho: **Confirmar** (guarda y sube)
  o **Más tarde** (se puede cambiar en Historial › Asignar). Al instalar la 2.12, los entrenamientos que ya había se dan
  por confirmados.
- «Directo (LIVE en el iPad)» viene **activado por defecto**; se puede apagar en Compartir.

## Puesta en marcha (a mano, en la consola de Firebase)

1. Plan **Blaze** (hecho el 20/11/2026) y una alerta de presupuesto (Google Cloud › Facturación › Presupuestos).
2. **Storage › Comenzar**: región de la UE (recomendado `europe-southwest1`, Madrid). El bucket debe llamarse
   `avo-performance-horse-7be14.firebasestorage.app`; si la consola crea otro nombre, hay que cambiar la constante en
   las tres apps.
3. **Storage › Reglas**: pegar `firebase/storage.rules` y publicar.
4. iPad y Windows usan la clave web de Firebase por REST. Si la clave está restringida a Android, la entrada falla con
   «Firebase rechaza la clave…»: añadir una app iOS/web en la consola o quitar la restricción a la clave.

## Coste estimado (no medido)
Unos 10–20 MB por hora de entrenamiento. Con 10 caballos al día, unos 5 GB/mes: céntimos al mes en Storage.

## Estado
IMPLEMENTADO. Reglas probadas en el emulador por CI. Apps compiladas por CI. **NO VERIFICADO** con el bucket real ni
en dispositivos.
