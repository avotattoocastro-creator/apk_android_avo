# Datos de prueba del PPK (motor 2.0.0-dev33)

| Fichero | Qué es | Origen y licencia |
|---|---|---|
| `07590920.05o`, `30400920.05o`, `07590920.05n` | RINEX 2.10 de dos estaciones GEONET (Japón), 2/4/2005 00:00–01:00 GPST, 30 s, L1/L2; línea base de ~3,3 km | datos de prueba de RTKLIB (`test/data/rinex`), BSD 2-cláusulas |
| `P43300USA_R_20190012056_17M_15S_MO.crx` | CRINEX 3.0 (Hatanaka) de la estación P433, 1/1/2019 20:56:45–21:14:00, 15 s, 70 épocas | datos de prueba de georinex (MIT); origen: red pública de EE. UU. |

Los valores esperados de `P433…crx` (70 épocas, primera época 20:56:45, satélites) son los de las pruebas de georinex.
| `gz/*.gz` | los mismos ficheros comprimidos con `gzip` de Python (`mtime=0`): niveles 1, 6 y 9, y dos miembros seguidos (el primero sin comprimir, nivel 0) | generados el 27/11/2026 para `avo_eq_gunzip` |
