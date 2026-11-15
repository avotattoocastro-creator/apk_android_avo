# Sesión de ruteado (Freerouting 1.9.0)

- `placa.dsn`: el DSN que exportó el CI (ejecución 43769163241) desde `kicad/AVO_DOCK_V1_PCB_colocacion.kicad_pcb`.
- `placa.ses`: resultado de `java -jar freerouting-1.9.0.jar -de placa.dsn -do placa.ses -mp 40`, ejecutado fuera del CI (18 min de ruteado y 2 min de optimización). En el CI, Freerouting con `-mp 150` no terminó en los 40 min del límite.

El workflow `build-dock-v1-pcb.yml` importa esta sesión **solo si** el DSN que exporta en ese momento es igual a este (sin contar la línea `host_version`). Si se cambia la colocación, el DSN cambia y el CI vuelve a rutear con Freerouting.
