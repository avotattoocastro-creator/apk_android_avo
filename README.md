AVO Performance —Horse Edition—

Sistema de telemetría ecuestre para entrenamiento de caballos de carreras, salto y trabajo en pista. Combina GNSS RTK centimétrico, IMU en la cincha y análisis en móvil, tableta y PC.

Repositorio: avotattoocastro-creator/apk_android_avo · Rama de trabajo: develop/avo-performance-horse

⚠️ Repositorio público. No subir claves, certificados, keystores, credenciales NTRIP ni datos reales de clientes. Ver AVO Performance Seguridad —Horse Edition—.

Índice

Aplicaciones

	•	AVO Performance Android —Horse Edition—
	•	AVO Performance iOS —Horse Edition—
	•	AVO Performance Windows —Horse Edition—
	•	AVO Performance Motor —Horse Edition—

Hardware

	•	AVO Performance Reloj —Horse Edition—
	•	AVO Performance GPS —Horse Edition—
	•	AVO Performance Cincha —Horse Edition—
	•	AVO Performance Sinc —Horse Edition—
	•	AVO Performance Base de carga —Horse Edition—

Común

	•	AVO Performance Arquitectura —Horse Edition—
	•	AVO Performance Contratos de datos —Horse Edition—
	•	AVO Performance Compilación —Horse Edition—
	•	AVO Performance Reglas de desarrollo —Horse Edition—
	•	AVO Performance Seguridad —Horse Edition—

Estado general (17/11/2026)

Producto	Versión vigente	Compilado en CI	Verificado en hardware
AVO Performance Android —Horse Edition—	2.9-integrada-dev1 (vc 42)	✅	Pendiente
AVO Performance iOS —Horse Edition—	TestFlight desde develop	✅	Pendiente
AVO Performance Windows —Horse Edition—	V2 PRO	✅	Pendiente
AVO Performance Motor —Horse Edition—	Equine 1.1 · Training Analytics 1.0 · Track Work 1.0	✅ (tests)	—
AVO Performance Reloj —Horse Edition—	Firmware 3.7.10 · caja REV D	✅	Parcial
AVO Performance GPS —Horse Edition—	Firmware 3.14.3 · carcasa V2.2H Rev E.5	✅	Parcial
AVO Performance Cincha —Horse Edition—	Firmware 0.4.3 · cápsula REV 5.9.1	✅	Parcial
AVO Performance Sinc —Horse Edition—	V0.1 (propuesta)	—	No
AVO Performance Base de carga —Horse Edition—	V1 · PCB REV A	✅ (DRC/ERC)	No fabricada

«Compilado en CI» significa que GitHub Actions lo compila y pasa los tests. No significa que se haya probado montado en un caballo.

Aplicaciones

AVO Performance Android —Horse Edition—

App principal de campo. El teléfono va con el jinete o el entrenador, conectado al AVO Performance Reloj.

	•	Tecnología: Kotlin 2.0.21, Jetpack Compose, Room, osmdroid, HCE NFC. Usa el AVO Performance Motor por JNI (3 ABI).
	•	Versión: 2.9-integrada-dev1 (versionCode 42). Los versionCode siempre crecen.
	•	Funciones:
	•	BLE permanente con el AVO Performance Reloj (TELEMETRY v3) y descarga por BLE o Wi-Fi (AVO_CHEST_xxxx).
	•	NTRIP automático: recibe las correcciones RTCM3 del caster y las reenvía al AVO Performance Reloj, que las pasa al AVO Performance GPS.
	•	Sesiones, geocercas, mapas de pista y análisis del entrenamiento.
	•	Licencias con roles (cuadra, entrenador, jinete) y sincronización con Firebase.
	•	Apps auxiliares:
	•	AVO Performance Tarjetas 1.4-nfc-movil-dev1: emite licencias NFC (NTAG213/215/216, .avolic) y las activa de un móvil a otro por NFC.
	•	AVO Performance Update: flasheo de firmware por USB-C.
	•	Compilación: build-android.yml en Actions. Genera una APK con su SHA-256.

AVO Performance iOS —Horse Edition—

App de análisis para iPad, pensada para revisar el entrenamiento en la cuadra o en la pista.

	•	Tecnología: SwiftUI, iPadOS 17+, Xcode 26. Llama al AVO Performance Motor desde Swift.
	•	Distribución: TestFlight, que sale de develop cuando cambian ipad/**, equine-intelligence/**, avo_core/** o el workflow. El build number es automático.
	•	Funciones:
	•	Análisis avanzado: velocidad RTK, parciales, zancada, aire y pulso.
	•	Descarga de sesiones por BLE.
	•	Trabajo en pista (Track Work 1.0).
	•	Previsto: página Vídeo sincronizada con hora GPS mediante AVO Performance Sinc —Horse Edition—.
	•	⚠️ No tocar certificados, perfiles, Bundle Identifier ni el build number. Si cambia el uso de BLE o de la localización, revisar Info.plist (NSBluetoothAlwaysUsageDescription, etc.).

AVO Performance Windows —Horse Edition—

Estación de análisis y gestión en el PC de la cuadra.

	•	Tecnología: C# WPF .NET 10, MVVM, WinRT BLE y winscard.dll. Usa el AVO Performance Motor como DLL por P/Invoke.
	•	Versión: V2 PRO.
	•	Funciones:
	•	Análisis avanzado y comparación de sesiones.
	•	Descarga por USB del AVO Performance Reloj con el protocolo AVO1: bloques de 4 KB con CRC-32 y SHA-256. Requiere firmware ≥ 3.7.5.
	•	Geocercas y gestión de pistas.
	•	Lector NFC ACS ACR122U para las licencias.

AVO Performance Motor —Horse Edition—

Núcleo de cálculo compartido en C++17 (MotorAVO Equine). Las tres apps lo usan, así que las métricas salen idénticas en Android, iOS y Windows.

	•	Módulos: Equine 1.1, Training Analytics 1.0 y Track Work 1.0.
	•	Integración: JNI en AVO Performance Android, P/Invoke en AVO Performance Windows y Swift en AVO Performance iOS.
	•	Cualquier cambio debe pasar los tests unitarios y la compilación cruzada de las tres plataformas.

Hardware

AVO Performance Reloj —Horse Edition—

El cerebro del sistema: va en el pecho, graba la sesión y hace de puente con las apps.

	•	Placa: Waveshare ESP32-S3-Touch-AMOLED-2.06" (panel CO5300 410×502, PMIC AXP2101, flash de 32 MB usada como 16 MB, microSD SDMMC 1-bit).
	•	⚠️ Los pads IO14 / IO15 del reverso son el bus I²C. No usarlos como GPIO libres.
	•	Funciones:
	•	Graba las sesiones RAW .avr en la microSD.
	•	Pantalla de 7 franjas, con la tarjeta «Calidad GNSS».
	•	Puente BLE, Wi-Fi AP y USB con las apps.
	•	Reenvía el RTCM3 al AVO Performance GPS por ESP-NOW.
	•	Firmware: 3.7.10. Para OTA firmada, solo versiones X.Y.Z sin sufijos: un -rc2 o -usb1 hace que el reloj rechace el paquete.
	•	Caja: REV D, 42 × 73,5 × 22,4 mm, interruptor KAN-28 bajo la barbilla y 4×M3 con insertos.

AVO Performance GPS —Horse Edition—

Unidad GNSS RTK centimétrica en la espalda del jinete. También recoge los datos de la AVO Performance Cincha.

Unidad vigente (espalda, prototipo Heltec)

	•	Placas: Heltec Wireless Stick Lite V3 (ESP32-S3) + u-blox ZED-F9P (placa URTK1.2) + antena multibanda Q39.
	•	Energía: LiPo 654060 de 2000 mAh y regulador Pololu S7V8F3 (SHDN = GPIO34, VIN al 3V3 de la Heltec).
	•	UART del ZED-F9P: RX = GPIO35, TX = GPIO33, 460 800 baudios.
	•	Funciones:
	•	RTK a 8 Hz, con las correcciones que llegan de AVO Performance Android a través del AVO Performance Reloj.
	•	GirthHub: recibe los lotes de la AVO Performance Cincha.
	•	Envía BackStatus v3 (108 B) al AVO Performance Reloj.
	•	Firmware: 3.14.3, que incluye la vigilancia GNSS de la 3.13.12 (firmware/back/V3_8_0).
	•	Carcasa: V2.2H Rev E.5. Las Rev E.6 y E.7.3, con conectores magnéticos pogo, son de prueba.

En desarrollo

	•	AVO Performance GPS Casco (BACK V5): la misma función en una cápsula de 55 × 55 × 22,6 mm para el casco, con base magnética.
	•	ZED-F9P soldado, antena plana L1/L2 y un solo ESP32-S3.
	•	Pogo de 5 contactos con USB, encendido por sensor Hall y caja totalmente estanca.
	•	PCB REV A diseñada, no fabricada. Solo para entrenamiento.
	•	AVO Performance GPS V4 (PCB propia, firmware/back/V4_0_0, 4.0.0-dev2): en papel/KiCad.
	•	⚠️ No instalar en el hardware actual. No tiene batería, modo carga, calidad GNSS ni GirthHub.

AVO Performance Cincha —Horse Edition—

Sensor de movimiento en la cincha: aporta cadencia, zancada, apoyos y, con ECG, el pulso.

	•	Placa: Seeed XIAO ESP32-C6 + BNO085 (I²C 0x4A, rango ±8 g; pendiente evaluar ±16 g para los saltos).
	•	Energía: LiPo EEMB LP403048 de 500 mAh. Carga por pogo magnético de 3 pines (1 = +5 V · 2 = GND · 3 = MTCK).
	•	Funciones: IMU de 9 ejes y cuaternión a ~125 Hz, enviados al AVO Performance GPS por ESP-NOW en lotes de 220 B. Requiere AVO Performance GPS ≥ 3.10.0.
	•	Firmware: GIRTH 0.4.3.
	•	Cápsula:
	•	REV 5.9.1 (vigente).
	•	En develop: REV 5.9.2 (pogo empotrado) y REV 5.10 (ECG CJMCU-30003 / MAX30003).
	•	PCB propia: antes de fabricarla hay que elegir arquitectura:
	•	(a) prototipo validado: pogo + BNO085 + ECG MAX30003, o
	•	(b) diseño en papel: Qi + reed + LSM6DS3TR-C / MMC5983MA.

AVO Performance Sinc —Horse Edition—

Accesorio para grabar vídeo del entrenamiento con hora GPS exacta en cada fotograma. Después, la app superpone en el vídeo la velocidad, la zancada y el pulso.

	•	Estado: propuesta V0.1. No hay PCB, CAD, firmware ni código de la app.
	•	Funciona a cualquier distancia. El caballo y AVO Performance Sinc toman la hora de los satélites por separado, y los datos se juntan después.
	•	Hardware propuesto:
	•	Seeed XIAO ESP32-C3.
	•	GPS con pin PPS: u-blox MAX-M10S o ATGM336H.
	•	LiPo de 400–500 mAh.
	•	LED blanco codificado, para GoPro o dron.
	•	Pulsador de marcas y caja de PETG/TPU.
	•	Coste estimado: 17–32 €.
	•	Precisión esperada (sin medir):
	•	1–5 ms con AVO Performance iOS por BLE.
	•	±½ fotograma con el LED en cámaras externas.
	•	Protocolo: BLE AVO SYNC v1, un servicio GATT propio. No modifica ningún contrato existente.
	•	Firmware previsto en firmware/sync/V0_1.

AVO Performance Base de carga —Horse Edition—

Soporte de pared (DOCK V1) que carga 2 AVO Performance GPS Casco y 2 AVO Performance Cincha a la vez y descarga los entrenamientos.

	•	Estado: PCB REV A y caja diseñadas y verificadas en el CI (DRC 0, ERC 0/0, 0 interferencias). No fabricada.
	•	Rama claude/dock-cargador-v1, PR #45.
	•	Carpeta hardware/dock/V1.
	•	Alimentación: red de 230 V con módulo Mean Well IRM-20-5, o USB-C de 5 V. La red tiene prioridad.
	•	Electrónica:
	•	ESP32-S3-MINI-1U.
	•	Hub USB2514B con dos modos: modo PC (el ordenador ve los cascos) y modo autónomo (la base sirve los entrenamientos por Wi-Fi).
	•	Cada puerto mide su carga (TPS2553 + INA180A2), y la pantalla IPS de 2,0" muestra «cargando / completa / sin cápsula».
	•	Conexiones: pogo de 5 contactos para los cascos y de 3 para las cinchas (REV 5.9.1 y REV 5.10).
	•	Caja: PETG, 200 × 190 × 55 mm, con alojamientos imantados.
	•	Previsto:
	•	Lector de QR para actualizar la licencia de todos los cascos mientras cargan.
	•	Contrato nuevo DockStatus v1 en las tres apps.
	•	⚠️ No es un producto certificado: necesita ensayo CE antes de venderse.

Común

AVO Performance Arquitectura —Horse Edition—

                 Caster NTRIP (RTCM3)
                         │
          AVO Performance Android ── BLE / Wi-Fi ──┐
                         │ RTCM3 (BLE, CRC-24Q)     │
                         ▼                          │
   ┌──────── AVO Performance Reloj ◄────────────────┘
   │   graba .avr en microSD · pantalla · BLE/Wi-Fi/USB
   │        ▲ BackStatus v3 (108 B)     │ RTCM3
   │        │ ESP-NOW                   ▼
   │   AVO Performance GPS (RTK 8 Hz + GirthHub)
   │        ▲
   │        │ lotes IMU 220 B (ESP-NOW)
   │   AVO Performance Cincha (~125 Hz)
   │
   ├── USB AVO1 ──► AVO Performance Windows
   └── BLE ───────► AVO Performance iOS ◄── BLE ── AVO Performance Sinc

   AVO Performance Base de carga ── pogo ──► GPS Casco y Cincha
                                 ── USB / Wi-Fi ──► PC

AVO Performance Contratos de datos —Horse Edition—

Si cambia un formato, hay que actualizar a la vez el firmware y todas las apps que lo leen.

Enlace	Formato	Tamaño / integridad	Requisito mínimo
GPS → Reloj (ESP-NOW)	BackStatus v3	108 B	GPS ≥ 3.9.0, Reloj ≥ 3.7.6
Cincha → GPS (ESP-NOW)	Lote IMU	220 B	GPS ≥ 3.10.0
Reloj → Apps (BLE GATT)	TELEMETRY v3	116 B	—
Reloj → Windows (USB)	AVO1	Bloques de 4 KB, CRC-32 + SHA-256	Reloj ≥ 3.7.5, Windows ≥ V1.1
Android → Reloj → GPS	RTCM3	CRC-24Q	—
Sinc → iOS (BLE)	AVO SYNC v1	16 / 32 B	Propuesta
Base de carga → Apps	DockStatus v1	Por definir	Propuesta
Sesiones	.avr (RAW)	—	—
Configuración	TLV AVOC	—	—
Licencias	.avolic	Firma ECDSA P-256	—

AVO Performance Compilación —Horse Edition—

Todos los binarios se generan en GitHub Actions. Los workflows se disparan con push a develop, filtrados por paths:; no se ejecutan en los PR.

	•	Firmware del AVO Performance Reloj, GPS y Cincha (.bin).
	•	AVO Performance Android: build-android.yml (APK).
	•	AVO Performance Windows: instalador / .exe.
	•	AVO Performance iOS: TestFlight.
	•	KiCad: PCB de AVO Performance Cincha, GPS y Base de carga.
	•	Archivo: archivar-artefactos.yml guarda la última versión de cada artefacto en archivo/binarios/.

Descarga: Actions → el run correspondiente → Artifacts. Cada artefacto incluye su SHA-256.

No modificar workflows, rutas de artefactos, firmas (AVO_UPDATER_KEYSTORE_*), Info.plist, perfiles ni el build number de TestFlight sin avisar y sin confirmación.

AVO Performance Reglas de desarrollo —Horse Edition—

	1.	Una sola develop. Cada tarea va en una rama corta que sale de develop y vuelve por PR con merge commit y el CI en verde.
	2.	Nada de líneas paralelas de una misma app o firmware.
	3.	Antes de borrar ramas antiguas, comprobar que existe su etiqueta backup/2026-11-12/* o backup/2026-11-17/*.
	4.	OTA del AVO Performance Reloj: solo versiones X.Y.Z sin sufijos.
	5.	Tiempo real: nada de delay() en los bucles IMU (125 Hz) ni GNSS (8 Hz). Usar FreeRTOS, colas e interrupciones.
	6.	AVO Performance GPS: respetar la secuencia de encendido del Pololu (GPIO34) y la lógica de BACK_SLEEP para evitar brownouts.
	7.	Commits en Conventional Commits con el módulo: feat(pecho), fix(espalda), feat(cincha), fix(android), feat(ipad), feat(windows), feat(motor), cad(carcasa).
	8.	CAD: FreeCAD 1.0.2 y Shapr3D. Se imprime en Elegoo Centauri Carbon: PETG para la estructura y TPU 85A/95A para juntas y tapones. Tolerancia de encaje 0,2–0,3 mm. Objetivo IP67.
	9.	PCB: KiCad 9.
	10.	Documentación en español. Cada entrega indica qué está compilado en CI y qué está verificado en hardware real.

AVO Performance Seguridad —Horse Edition—

	•	Prohibido subir .jks, .keystore, .p12, .pfx, .p8, .mobileprovision, .env, google-services.json con claves restringidas, credenciales NTRIP o claves ECDSA privadas.
	•	La clave privada de licencias vive solo en AVO Performance Tarjetas (y en su copia cifrada). En GitHub solo está la pública (AVO_LICENSE_PUBLIC_KEYS).
	•	Firmas de APK y de App Store Connect: solo como GitHub Secrets.
	•	Las credenciales NTRIP las introduce cada usuario en los ajustes de la app.

AVO Performance Documentación —Horse Edition—

	•	CLAUDE.md y AGENTS.md: reglas para agentes. Si algo choca, manda el repositorio.
	•	claude/ y docs/: un documento por versión de firmware, carcasa, PCB y app.

© AVO Performance. Todos los derechos reservados.
