# AVO · Demostración 3D (web) — caballo, jockey y sistema AVO

Páginas web de demostración del sistema y herramientas para regenerarlas. Sirven de referencia visual para el
**Modo demostración** de la app del iPad (plan: [`docs/PLAN_MODO_DEMOSTRACION_IPAD.md`](../../docs/PLAN_MODO_DEMOSTRACION_IPAD.md)).

**Estado:** IMPLEMENTADO como páginas web. No forma parte de ninguna app ni firmware. Probado solo en navegador de
escritorio (Chrome) y en una captura de móvil; **NO VERIFICADO** en iPad.

## Carpetas

| Carpeta | Qué es |
|---|---|
| `web-3d/` | Caballo de carreras + jockey en 3D (three.js 0.160, FBXLoader), con el **casco prototipo A** y la **cincha**, paquetes animados (cincha → casco 220 B por ESP-NOW, casco → móvil `TELEMETRY v3` 116 B por BLE, RTCM3 del móvil al casco) y el móvil con la sesión en directo. Telemetría simulada. |
| `web-muybridge/` | Versión 2D con los 11 fotogramas reales de «The Horse in Motion» (Muybridge, 1878, dominio público) coloreados en bayo. Es la versión anterior: todavía muestra la espalda y el pecho. |
| `herramientas/muybridge/` | Pasos 1–3 que generan `galope.webp` y `esfera.webp` a partir de `src/muybridge.jpg`. Reproducible bit a bit. |
| `herramientas/fbx/fbxinfo.py` | Lector mínimo de FBX binario (mallas, materiales, pilas de animación) usado para inspeccionar los modelos. |

## Modelos 3D (en el repositorio solo CIFRADOS)

`web-3d/` necesita `web-3d/modelos/modelos.zip` (con `horse.fbx` y `jockey.fbx`) y `web-3d/tex/` con las texturas
convertidas. Son del paquete **«Race Horse Jockey with LOD» v1.4 de Enozone** (Unity Asset Store). El usuario tiene la
licencia para la app privada, pero **este repositorio es público**, así que solo se guardan **cifrados** (AES-256-CBC,
PBKDF2 200 000 iteraciones) en `modelos_cifrados/enozone_3d.zip.enc`. Borrarlos después no bastaría: quedarían en el
historial de git.

```
AVO_ASSETS_3D_KEY='<clave>' demo/avo-3d/modelos_cifrados/descifrar.sh   # deja web-3d/modelos y web-3d/tex
```

La clave no está en el repositorio. En GitHub va como secreto **`AVO_ASSETS_3D_KEY`** (lo crea el usuario en
Settings → Secrets and variables → Actions). `.gitignore` impide subir los archivos descifrados.

Tramos de animación de la toma única (30 fps), del importador de Unity del paquete:

| Aire | Fotogramas |
|---|---|
| Paso | 0–159 |
| Galope | 241–302 |
| Sprint | 304–362 |
| Parado | 365–409 |
| Trote | 541–604 |

Texturas que espera la página (`web-3d/tex/`): `horse_body.jpg`, `horse_body_n.jpg`, `horse_hair.png`,
`horse_hair_n.jpg`, `saddle.jpg`, `saddle_n.jpg`, `jockey_n.jpg` y `silk_00.jpg` … `silk_13.jpg`
(`silk_00` = `jockey_body.tga`; `silk_NN` = `casaque_NN.tga`).

## Probar en local

```
cd demo/avo-3d/web-3d        # o web-muybridge
python3 -m http.server 8000  # abrir http://localhost:8000
```

`web-3d` carga three.js desde jsdelivr, así que necesita internet.

## Regenerar los sprites de Muybridge

```
cd demo/avo-3d/herramientas/muybridge
python3 01_extraer_siluetas.py
python3 02_render_bayo.py
python3 03_empaquetar_sprites.py   # escribe ../../web-muybridge/*.webp
```

Requiere Python 3 con OpenCV, NumPy y Pillow.
