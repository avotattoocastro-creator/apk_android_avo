# Sesión de ruteado de la fuente (opcional)

Si aquí hay un `placa.dsn` y un `placa.ses` de Freerouting 1.9.0, el workflow `build-dock-v1-pcb.yml` importa la sesión **solo si** el DSN que exporta el CI es igual a este (sin contar la línea `host_version`). Si no coinciden, rutea en el CI con `-mp 40`.

Sirve para rutear fuera del CI cuando Freerouting tarda más que el límite del job:
```
java -jar freerouting-1.9.0.jar -de placa.dsn -do placa.ses -mp 40
```
Se usa el DSN que exportó el CI (artefacto `out/ruteado/placa.dsn`).
