# QEMU (Espressif) para el ESP32-C3 — fichero de eFuse

`efuse_esp32c3_rev0_3.bin` (1024 B) es la imagen de eFuse por defecto que ESP-IDF usa con QEMU para el ESP32-C3
(«Chip revision 0.3»): copiada byte a byte de `tools/idf_py_actions/qemu_ext.py` de ESP-IDF (rama master, commit
d445e947156f276dfe0db5804e4edf6ae90fe6fb del 2026-10-28; licencia Apache-2.0). Solo tiene un byte distinto de cero
(desplazamiento 38 = 0x0C: revisión de chip v0.3).

Con una imagen de eFuse toda a cero el chip emulado es v0.0; con ella el cargador de arduino-esp32 3.3 se detuvo en
silencio justo después de `entry 0x403cbf10` (CI de 05eab4e y fabea5b). Causa probable (a confirmar con el CI que usa
este fichero): ESP-IDF 5.x exige por defecto una revisión mínima del C3 y el cargador de Arduino no imprime el error.
