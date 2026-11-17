## Diseño de la REV A (texto fijo)
- Arquitectura, conexiones del ESP32-S3, puertos y seguridad eléctrica: `hardware/dock/V1/DOCS/ARQUITECTURA.md`.
- **Selector de alimentación:**
  - con red: Q1 y Q1B (AO3401A en paralelo) conducen y Q2 queda apagado;
  - sin red: conduce Q2 desde el USB-C;
  - el diodo interno de cada PMOS impide alimentar el IRM al revés y devolver corriente al PC.
- **Puertos:** TPS2553 con el EN en el S3 (100 k a GND: apagados al arrancar) → shunt de 50 mΩ → contacto, con INA180A2 (× 50; 1 A = 2,5 V).
- **Hub USB2514B** configurado por patillas: CFG_SEL = 00, LOCAL_PWR = 1, NON_REM = 00, puerto 4 desactivado. La potencia de los puertos la manda el S3, no PRTPWR.
