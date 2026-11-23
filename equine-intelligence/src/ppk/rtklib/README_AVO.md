# RTKLIB (subconjunto) en el motor AVO

Origen: [rtklibexplorer/RTKLIB](https://github.com/rtklibexplorer/RTKLIB), rama `demo5`, commit `75a2e56` (26/07/2025).
Licencia: BSD de 2 cláusulas (`LICENSE_RTKLIB.txt`), compatible con el repositorio público.

Cambios respecto al original (los únicos):
- `rtklib.h`: bloque al principio con `WIN32` (si solo está `_WIN32`), `ENAGLO`, `ENAGAL`, `ENAQZS`, `ENACMP` y `NFREQ 3`, para que CMake, NDK, Xcode y MSVC compilen igual.
- `rtkcmn.c`: `execcmd()` devuelve siempre -1 (el motor no lanza procesos; en iOS `system()` no existe).
- `rcv/*.c`: `#include "../rtklib.h"` (antes `"rtklib.h"`), para compilar sin ruta de cabeceras extra en Xcode.
- Fuera: `rcv/comnav.c` y `rcv/tersus.c` (no compilan en demo5) y los ficheros de aplicación (`postpos.c`, `rtksvr.c`, `stream.c`...).

El motor solo usa: decodificador u-blox (RXM-RAWX/SFRBX), lector RINEX, efemérides y `rtkpos` (RTK cinemático con LAMBDA).
La compilación de estos ficheros va sin avisos ni sanitizadores (`CMakeLists.txt`).
