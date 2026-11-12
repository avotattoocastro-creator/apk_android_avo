# Claude

Las instrucciones del proyecto son comunes para todos los asistentes y están en [`AGENTS.md`](AGENTS.md).
Léelas antes de trabajar y documenta cada cambio en [`docs/REGISTRO_DE_CAMBIOS.md`](docs/REGISTRO_DE_CAMBIOS.md).

Resumen de las reglas permanentes (el detalle manda en `AGENTS.md`):
- Una sola rama de integración, `develop/avo-performance-horse`, y ramas cortas por tarea integradas por PR con
  *merge commit*.
- No borrar ramas antiguas hasta que existan las 53 etiquetas `backup/2026-11-12/*`.
- Nunca subir `.jks`, `.keystore`, `.p12`, `.p8`, `.mobileprovision`, credenciales NTRIP ni claves privadas. La clave
  privada ECDSA de licencias vive solo en AVO Tarjetas.
- Separar siempre «compilado en CI» de «verificado en hardware real».
- No tocar workflows, firmas, `Info.plist` ni el número de build de TestFlight sin avisar al usuario.
