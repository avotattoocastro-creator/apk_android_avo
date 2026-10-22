# AVO CHEST V3.5.9 — interfaz de siete franjas (diseño aprobado)

Objetivo: implementar en la pantalla REAL Waveshare ESP32-S3 Touch AMOLED 2.06" la distribución de siete franjas de la última referencia aprobada por el usuario, con **tipografía NEGRA grande y legible** y fondo de franjas brillante, bordes redondeados, separaciones negras. La imagen de referencia es un mockup, NO telemetría real; nunca codificar como constantes RSSI, temperatura, satélites, tasa, duración ni porcentaje ilustrativos.

Orden estricto:
1. BLUETOOTH — verde conectado / rojo desconectado; detalle real si disponible.
2. CHALECO — verde funcionamiento correcto / rojo fallo; versión real.
3. ESPALDA — verde enlace activo / rojo sin enlace; RSSI solo si se mide.
4. CINCHA (IMU) — verde 3 IMU con datos recientes / rojo desconectada o sin datos. No inferir conexión de cincha por conexión de espalda.
5. GPS / RTK — rojo sin GNSS; azul GNSS autónomo válido sin NTRIP; verde cuando NTRIP aporta correcciones, mostrando **estado GNSS real** (DGNSS, RTK FLOAT, RTK FIX), satélites y precisión si disponibles. No afirmar FIX solo porque NTRIP esté conectado.
6. TARJETA SD — rojo ausente/error; verde montada y disponible; azul grabando (preferencia funcional del usuario, aunque la imagen ilustrativa mostraba amarillo). Tiempo de grabación real solo si está disponible.
7. BATERÍA — porcentaje real grande en negro. Fondo según nivel: verde >50%, amarillo 21–50%, rojo <=20%; si porcentaje desconocido mostrar '--%' y estado de aviso. Estado «Cargando...» solo si USB/carga es detectable; «Carga completa» cuando corresponda. No confundir presencia de USB con corriente real de carga.

Reglas técnicas:
- Tamaño de fuente maximizado dentro de los píxeles reales y medido con API de texto de Arduino_GFX; reducir texto secundario si falta espacio. Siete franjas visibles sin scroll.
- Renderizar con Arduino_GFX ya presente; no introducir dependencias LVGL innecesarias.
- La pantalla circular USB de V3.5.9 sigue siendo un modo separado al conectar USB.
- Los colores representan ESTADOS reales y no los datos de demostración de la imagen.
- No bloquear el loop ni BLE, ESP-NOW, SD, GNSS, geocercas ni OTA. Preservar estados de pantalla al conectar/desconectar USB.
- Compilación obligatoria por GitHub Actions y verificación en hardware antes de publicar un ZIP OTA firmado ES256.
- El estado actual del repositorio solo incluye la pantalla circular USB; ESTA ESPECIFICACIÓN NO ES UNA IMPLEMENTACIÓN NI UNA APK/FIRMWARE VERIFICADOS.
