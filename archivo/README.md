# Archivo — todo el proyecto en `main` (17/11/2026)

`main` contiene la **última versión de todo** para tenerlo a mano y no perder nada:

- **Código fuente:** todo `develop/avo-performance-horse` (cabeza `a2a100b`, PR #7–#59) más las ramas que aún no
  estaban en `develop`, cada una en su propia carpeta:
  - `hardware/dock/V1` — DOCK V1 soporte de pared y cargador (PR #45)
  - `hardware/back/V5_CASCO` — casco V5 (PCB + CAD)
  - `hardware/girth/CINCHA_MONTAJE` — cápsula REV 6.3.1 con funda (PR #60)
  - `hardware/girth/REV5` — REV 5.11.2 cierre magnético
  - `hardware/girth/PCB_REV_C` — consulta de existencias JLCPCB
- **Subidas manuales antiguas de `main`** (23/10): ZIP de fuentes Android en la raíz y `firmware/chest/V3_6_1_R8`.
- **Binarios:** `archivo/binarios/<categoría>/<artefacto>/` con el `.zip` del artefacto de GitHub Actions, un
  `README.md` con rama, commit, run y SHA-256, e índice en `archivo/binarios/INDICE.md`. Se guarda la **versión más
  reciente de cada nombre de artefacto**.
- **Etiquetas de respaldo:** `backup/2026-11-12/*` (las 53 ramas auditadas) y `backup/2026-11-17/*` (todas las ramas
  tal como estaban hoy). Cualquier rama se puede recuperar desde su etiqueta aunque se borre.

## Versiones más recientes (para continuar)
| Componente | Versión | Dónde |
|---|---|---|
| Pecho | 3.7.10 | `firmware/chest/V3_7_10_CARGA_APAGADO` |
| Espalda (hardware actual) | 3.14.3 | `firmware/back/V3_8_0` |
| Espalda V4 (otro hardware, **no instalar en el actual**) | 4.0.0-dev2 | `firmware/back/V4_0_0` |
| Cincha XIAO actual | 0.5.0 (ECG) | `firmware/girth/V0_5_0` |
| Cincha PCB REV D (no fabricada) | 0.6.0 | `firmware/girth/V0_6_0`, `hardware/girth/PCB_REV_D` |
| Android | 2.9-integrada-dev1 (vc 42) | `app/` |
| AVO Tarjetas | 1.4-nfc-movil-dev1 (vc 5) | `cards/` |
| AVO Update | 2.3.1 (vc 28) | `usb-updater/` |
| Windows | 2.0.0 V2 PRO | `windows/` |
| iPad | 1.0.0 (build automático) | `ipad/` |
| Motor C++ | 2.0.0-dev1 | `equine-intelligence/` |

Todo es **compilado en CI**; nada de lo integrado desde el 12/11 está **verificado en hardware real**.
El trabajo nuevo sigue haciéndose en `develop/avo-performance-horse`; `main` es el archivo completo.
