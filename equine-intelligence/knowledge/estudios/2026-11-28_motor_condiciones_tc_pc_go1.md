# Motor nocturno 2026-11-28 — comparables por condiciones (TC1–TC4, PC1–PC3, GO1)

**KB-1 1.34.0 · motor 2.0.0-dev41 · training 1.7.0.** Probado en local (ASan/UBSan y Release); **NO VERIFICADO** con
caballos reales.

## Qué se implementó y por qué

La ficha de campo del iPad ya graba temperatura, humedad, going, jinete y pesos (training 1.1.0), pero A7, A8, A9 y la
cinética de la FC los ignoraban al elegir comparables. Con datos de los PROTOTIPOS (GNSS RTK de la espalda, IMU y ECG
de la cincha 0.5.0 y la ficha de campo) eso daba falsas «pérdidas de forma»: una V200 más baja en un día de calor
húmedo, o una zancada más corta en going blando, se leía como empeoramiento. Era el punto d) de la lista (TC, PC) y el
primero de e) (GO1). La evidencia ya estaba reunida en los estudios del 20/11 13:12 (temperatura y peso) y 21:08
(going); esta noche solo hacía falta la fórmula del WBGT.

`src/training/conditions.cpp`:

- **TC1.** WBGT medido (`condiciones.wbgt_c`, nuevo campo de la ficha) o estimado con la aproximación del Bureau of
  Meteorology de Australia: **WBGT = 0,567·T + 0,393·e + 3,94**, con **e = HR/100 · 6,105 · exp(17,27·T / (237,7 + T))**
  en hPa. Supone sol pleno y brisa ligera y tiende a sobrestimar frente a otros modelos [E-r]; como sobrestima, marca
  más sesiones como «calor» y A9 se equivoca menos por calor (decisión prudente) [I].
- **TC2.** A9 (V200 y VHRmax) y la cinética de la FC (τ CF2, THR100 RC1, FC del tramo fijo FW1) solo con
  |ΔT| ≤ 5 °C [I].
- **TC3.** «Calor» si WBGT ≥ 28 °C, o T ≥ 30 °C con humedad ≥ 70 % (sin humedad anotada, T ≥ 30 °C) [I]. A9 no juzga
  esa sesión (marca `A9_NO_COMPARABLE_CALOR`, INFO) y las sesiones con calor solo se comparan entre sí.
- **TC4.** Día del periodo de calor (14 días sin sesiones con calor lo cierran); los 10 primeros salen como
  transición de aclimatación (INFO) [I].
- **PC2.** A7 y A8 solo con |Δpeso del jinete con equipo| ≤ 3 kg y con el mismo jinete si tiene ≥ 8 comparables
  (las 5 de la línea base mínima + las 3 que se juzgan) [I].
- **PC3.** Peso cargado / peso corporal > 13 %: INFO, no es un umbral de riesgo [E/I].
- **GO1.** Mismo estrato de going: FIRME (firme y bueno-firme), BUENO, BLANDO (bueno-blando y blando), PESADO [I].

Si a una de las dos sesiones le falta el dato, la comparación se mantiene. No hay coeficiente de corrección (TC5, PC4).
Ninguna regla nueva sube el estado del caballo. Los umbrales son opciones JSON (`condiciones`) con su etiqueta en el
JSON (`parametros.etiquetas`).

## Ejemplo numérico (comprobado en `tests/test_conditions.cpp`)

- 30 °C y 50 %: e = 0,5 · 6,105 · exp(518,1 / 267,7) = 0,5 · 6,105 · 6,927 = 21,14 hPa → WBGT = 17,01 + 8,31 + 3,94
  = **29,26 °C**: calor.
- 20 °C y 50 %: e = 11,66 hPa → WBGT = **19,86 °C**.
- 25 °C y 60 %: WBGT ≈ 25,6 °C: sin calor. 31 °C y 75 %: WBGT ≈ 34,7 °C: calor.
- Ocho sesiones a 12 °C (V200 ≈ 15 m/s) y tres a 24 °C (13,8 m/s): sin temperatura, A9 marcaba pérdida de forma; con
  TC2 no hay comparables a ±5 °C y no se juzga. Con las tres a 16 °C sí se compara y sale A9.
- 62 kg de jinete sobre 450 kg = 13,78 % → PC3.

## Fuentes

| Cifra | Fuente | Etiqueta | Acceso |
|---|---|---|---|
| Fórmula del WBGT (0,567; 0,393; 3,94; 6,105; 17,27; 237,7) y su sesgo al alza | Bureau of Meteorology, «Thermal comfort observations», citado en NCAR GeoCAT «Humid Heat Metrics», https://ncar.github.io/geocat-applications/applications/humid_heat_metrics.html | E-r / I | AGREGADOR (leído el 28/11). La página del BoM y la validación de PMC7240860 no se pudieron leer (permiso no concedido); no se esquivó |
| FC submáxima ≈ +12 lpm a 7 m/s con calor (135 frente a 123 lpm) | Hargreaves, Kronfeld & Naylor 1999, *EVJ* 31:314, doi 10.1111/j.2042-3306.1999.tb03823.x | E-r | AGREGADOR (estudio 20/11 13:12) |
| FC de pico igual con WBGT 12,5 frente a 29,5 °C (213 frente a 214 lpm) | Ebisuda et al. 2023, *Front Vet Sci* 10:1230212, doi 10.3389/fvets.2023.1230212 | E | TEXTO COMPLETO (estudio 20/11 13:12) |
| WBGT 28–33 °C en las carreras de verano (norma externa citada) | Nomura et al. 2019, *J Equine Sci* 30:17, doi 10.1294/jes.30.17 | E-r | RESUMEN (estudios 20/11 y 22/11) |
| FC más alta solo con calor húmedo (32–34 °C y 80–85 %) | Geor et al. 1995, *EVJ Suppl* 20:125, doi 10.1111/j.2042-3306.1995.tb05018.x | E-r | AGREGADOR |
| Aclimatación en unos 10 días | Geor, McCutcheon & Lindinger 1996, *EVJ Suppl* 22:63, doi 10.1111/j.2042-3306.1996.tb05033.x | E-r | AGREGADOR |
| Recuperación a 2 min ≈ 4 lpm distinta entre ≥ 18 °C y ≤ 5 °C | Schrurs et al. 2024, *Animals* 14:1342, doi 10.3390/ani14091342 | E | TEXTO COMPLETO |
| Mejores tiempos con peso cargado / peso corporal ≈ 12,0–12,7 % en 1000 m | Lee & Park 2011, *Arch Zootec* 60:281 | E | TEXTO COMPLETO |
| Peso confundido con la calidad del caballo en carrera | Bugislaus et al. 2004, *Arch Tierz* 47:505 | E | TEXTO COMPLETO |
| El jinete no cambia la zancada en galope fuerte | Schrurs et al. 2022, *PLoS ONE* 17:e0273310, doi 10.1371/journal.pone.0273310 | E | TEXTO COMPLETO |
| Going como estrato de comparables (51 % de concordancia del going oficial) | estudio 20/11 21:08 (Rosanowski 2018, Northrop 2024, Schmitt 2024) | E / I | ver estudio |

Cortes propios [I]: ±5 °C, 28 °C, 30 °C con 70 %, 10 y 14 días, ±3 kg, 8 comparables del mismo jinete, 13 %, estratos
de going. Árabes de carreras en llano: sin datos de temperatura ni de peso en ninguna fuente leída; se usan los mismos
cortes [I].

## Qué falta calibrar (`docs/PROTOCOLO_PRUEBAS_CAMPO_PROTOTIPO.md` §6 quinquies)

- **TC5:** coeficiente propio de V200 por °C o por WBGT (≥ 3 trabajos de referencia frescos y ≥ 3 con calor, misma
  pista y going).
- Validar la aproximación del WBGT con un medidor (`wbgt_c` en la ficha).
- **TC4:** trabajo de referencia en los días 1–3 y 10–14 de la primera ola de calor.
- **PC4:** el mismo caballo con dos jinetes (≥ 3 sesiones cada uno).
- GO2–GO4 (going continuo, going oficial, firme y carga ósea) siguen sin implementar.
