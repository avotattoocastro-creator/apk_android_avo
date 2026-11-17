# Vectores del protocolo del reloj (geocercas y líneas)

`gen_watch_vectors.cpp` compila contra el código **real** del pecho (`lib/avo_core/src` del árbol 3.7.x, preparado como en
`.github/workflows/build-chest-v376-gnss-quality.yml`) y escribe `AVO.Windows.SelfTest/watch_vectors.json`:
configuración AVOC (`config_serialize`), geocerca (`fence_serialize`), veredictos de `validate_fence`, un fragmento BLE
(`ble_frag_build`), las pruebas HMAC de autorización (`avo_ble_auth`) y el test de cruce de líneas de `avo_session.cpp`.

Las autopruebas de Windows comprueban que su implementación produce y entiende **exactamente** esos bytes: así se envía al
reloj el mismo formato que la app Android, sin cambiar nada del firmware.

Generado el 31/10/2026 con el árbol 3.7.6 GNSS QUALITY (rama `feature/chest-v3-7-6-gnss-quality`).
