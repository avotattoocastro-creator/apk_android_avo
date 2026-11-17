AVO Performance — Horse Edition —

Sistema de telemetría ecuestre para entrenamiento de caballos de carreras, salto y trabajo en pista. Combina GNSS RTK centimétrico, IMU en la cincha y análisis en móvil, tableta y PC.

Repositorio: avotattoocastro-creator/apk_android_avo · Rama de trabajo: develop/avo-performance-horse

⚠️ Repositorio público. No subir claves, certificados, keystores, credenciales NTRIP ni datos reales de clientes. Ver Seguridad.

Índice

Aplicaciones

	•	AVO Performance App Android
	•	AVO Performance App iOS
	•	AVO Performance App Windows

Hardware

	•	AVO Performance Reloj de pecho
	•	AVO Performance Hardware GPS
	•	AVO Performance Hardware IMU Cincha
	•	AVO Performance Hardware Sync
	•	AVO Performance Hardware Base de carga

Común

	•	Arquitectura · Contratos de datos · Compilación · Reglas · Seguridad

Estado general (17/11/2026)

Producto	Versión vigente	Compilado en CI	Verificado en hardware
AVO Performance App Android	2.9-integrada-dev1 (vc 42)	✅	Pendiente
AVO Performance App iOS	TestFlight desde develop	✅	Pendiente
AVO Performance App Windows	V2 PRO	✅	Pendiente
AVO Performance Reloj de pecho	Firmware 3.7.10 · caja REV D	✅	Parcial
AVO Performance Hardware GPS	Firmware 3.14.3 · carcasa V2.2H Rev E.5	✅	Parcial
AVO Performance Hardware IMU Cincha	GIRTH 0.4.3 · cápsula REV 5.9.1	✅	Parcial
AVO Performance Hardware Sync	V0.1 (propuesta)	—	No
AVO Performance Hardware Base de carga	DOCK V1 · PCB REV A	✅ (DRC/ERC)	No fabricado

«Compilado en CI» significa que GitHub Actions lo compila y pasa los tests. No significa que se haya probado montado en un caballo.

Aplicaciones

Las tres apps usan el mismo motor de cálculo, MotorAVO Equine (C++17): Equine 1.1, Training Analytics 1.0 y Track Work 1.0. Así las métricas salen idénticas en Android, iOS y Windows.

AVO Performance App Android

App principal de campo: el teléfono va con el jinete o el entrenador y está conectado al reloj de pecho.

	•	Tecnología: Kotlin 2.0.21, Jetpack Compose, Room, osmdroid, HCE NFC. El motor va por JNI (3 ABI).
	•	Versión: 2.9-integrada-dev1 (versionCode 42). Los versionCode siempre crecen.
	•	Funciones:
	•	BLE permanente con el reloj de pecho (TELEMETRY v3) y descarga por BLE o Wi-Fi (AVO_CHEST_xxxx).
	•	NTRIP automático: recibe las correcciones RTCM3 del caster y las reenvía al pecho, que las pasa al GPS.
	•	Sesiones, geocercas, mapas de pista y análisis del entrenamiento.
	•	Licencias con roles (cuadra, entrenador, jinete) y sincronización con Firebase.
	•	Apps auxiliares:
	•	AVO Tarjetas 1.4-nfc-movil-dev1: emite licencias NFC (NTAG213/215/216, .avolic) y las activa de un móvil a otro por NFC.
	•	AVO Update: flasheo de firmware por USB-C.
	•	Compilación: build-android.yml en Actions. Genera una APK con su SHA-256.

AVO Performance App iOS

App de análisis para iPad, pensada para revisar el entrenamiento en la cuadra o en la pista.

	•	Tecnología: SwiftUI, iPadOS 17+, Xcode 26. El motor C++17 se llama desde Swift.
	•	Distribución: TestFlight, que sale de develop cuando cambian ipad/**, equine-intelligence/**, avo_core/** o el workflow. El build number es automático.
	•	Funciones:
	•	Análisis avanzado: velocidad RTK, parciales, zancada, aire y pulso.
	•	Descarga de sesiones por BLE.
	•	Trabajo en pista (Track Work 1.0).
	•	Previsto: página Vídeo sincronizada con hora GPS mediante AVO Performance Hardware Sync.
	•	⚠️ No tocar certificados, perfiles, Bundle Identifier ni el build number. Si cambia el uso de BLE o de la localización, revisar Info.plist (NSBluetoothAlwaysUsageDescription, etc.).

AVO Performance App Windows

Estación de análisis y gestión en el PC de la cuadra.

	•	Tecnología: C# WPF .NET 10, MVVM, WinRT BLE y winscard.dll. El motor va como DLL por P/Invoke.
	•	Versión: V2 PRO.
	•	Funciones:
	•	Análisis avanzado y comparación de sesiones.
	•	Descarga por USB con el protocolo AVO1: bloques de 4 KB con CRC-32 y SHA-256. Requiere pecho ≥ 3.7.5.
	•	Geocercas y gestión de pistas.
	•	Lector NFC ACS ACR122U para las licencias.

Hardware

AVO Performance Reloj de pecho

El cerebro del sistema: graba la sesión y hace de puente con las apps.

	•	Placa: Waveshare ESP32-S3-Touch-AMOLED-2.06" (panel CO5300 410×502, PMIC AXP2101, flash de 32 MB usada como 16 MB, microSD SDMMC 1-bit).
	•	⚠️ Los pads IO14 / IO15 del reverso son el bus I²C. No usarlos como GPIO libres.
	•	Funciones:
	•	Graba las sesiones RAW .avr en la microSD.
	•	Pantalla de 7 franjas, con la tarjeta «Calidad GNSS».
	•	Puente BLE, Wi-Fi AP y USB con las apps.
	•	Reenvía el RTCM3 al GPS por ESP-NOW.
	•	Firmware: 3.7.10. Para OTA firmada, solo versiones X.Y.Z sin sufijos: un -rc2 o -usb1 hace que el pecho rechace el paquete.
	•	Caja: REV D, 42 × 73,5 × 22,4 mm, interruptor KAN-28 bajo la barbilla y 4×M3 con insertos.

AVO Performance Hardware GPS

Unidad GNSS RTK centimétrica que va en la espalda del jinete. También recoge los datos de la cincha.

Unidad vigente (espalda, prototipo Heltec)

	•	Placas: Heltec Wireless Stick Lite V3 (ESP32-S3) + u-blox ZED-F9P (placa URTK1.2) + antena multibanda Q39.
	•	Energía: LiPo 654060 de 2000 mAh y regulador Pololu S7V8F3 (SHDN = GPIO34, VIN al 3V3 de la Heltec).
	•	UART del ZED-F9P: RX = GPIO35, TX = GPIO33, 460 800 baudios.
	•	Funciones:
	•	RTK a 8 Hz con las correcciones que llegan del móvil vía pecho.
	•	GirthHub: recibe los lotes de la cincha.
	•	Envía BackStatus v3 (108 B) al pecho.
	•	Firmware: 3.14.3, que incluye la vigilancia GNSS de la 3.13.12 (firmware/back/V3_8_0).
	•	Carcasa: V2.2H Rev E.5. Las Rev E.6 y E.7.3, con conectores magnéticos pogo, son de prueba.

En desarrollo

	•	BACK V5 Casco: la misma función en una cápsula de 55 × 55 × 22,6 mm para el casco, con base magnética.
	•	ZED-F9P soldado, antena plana L1/L2 y un solo ESP32-S3.
	•	Pogo de 5 contactos con USB, encendido por sensor Hall y caja totalmente estanca.
	•	PCB REV A diseñada; no fabricada. Solo para entrenamiento.
	•	Espalda V4 (PCB propia, firmware/back/V4_0_0, 4.0.0-dev2): en papel/KiCad.
	•	⚠️ No instalar en el hardware actual. No tiene batería, modo carga, calidad GNSS ni GirthHub.

AVO Performance Hardware IMU Cincha

Sensor de movimiento en la cincha: aporta la cadencia, la zancada, los apoyos y (con ECG) el pulso.

	•	Placa: Seeed XIAO ESP32-C6 + BNO085 (I²C 0x4A, rango ±8 g; pendiente evaluar ±16 g para los saltos).
	•	Energía: LiPo EEMB LP403048 de 500 mAh. Carga por pogo magnético de 3 pines (1 = +5 V · 2 = GND · 3 = MTCK).
	•	Funciones: IMU de 9 ejes y cuaternión a ~125 Hz, enviados al GPS por ESP-NOW en lotes de 220 B. Requiere espalda ≥ 3.10.0.
	•	Firmware: GIRTH 0.4.3.
	•	Cápsula:
	•	REV 5.9.1 (vigente).
	•	En develop: REV 5.9.2 (pogo empotrado) y REV 5.10 (ECG CJMCU-30003 / MAX30003).
	•	PCB propia: antes de fabricarla hay que elegir arquitectura:
	•	(a) prototipo validado: pogo + BNO085 + ECG MAX30003, o
	•	(b) diseño en papel: Qi + reed + LSM6DS3TR-C / MMC5983MA.

AVO Performance Hardware Sync

Accesorio para grabar vídeo del entrenamiento con hora GPS exacta en cada fotograma. Después, la app superpone velocidad, zancada y pulso sobre el vídeo.

	•	Estado: propuesta V0.1. No hay PCB, CAD, firmware ni código de la app.
	•	Funciona a cualquier distancia: el caballo y el gadget toman la hora de los satélites por separado y los datos se juntan después.
	•	Hardware propuesto:
	•	Seeed XIAO ESP32-C3.
	•	GPS con pin PPS: u-blox MAX-M10S o ATGM336H.
	•	LiPo de 400–500 mAh.
	•	LED blanco codificado, para GoPro o dron.
	•	Pulsador de marcas y caja de PETG/TPU.
	•	Coste estimado: 17–32 €.
	•	Precisión esperada:
	•	1–5 ms con el iPad por BLE (estimación, sin medir).
	•	±½ fotograma con el LED en cámaras externas.
	•	Protocolo: BLE AVO SYNC v1, un servicio GATT propio. No modifica ningún contrato existente.
	•	Firmware previsto en firmware/sync/V0_1.

AVO Performance Hardware Base de carga

Soporte de pared (AVO DOCK V1) que carga 2 cascos GPS + 2 cinchas a la vez y descarga los entrenamientos.

	•	Estado: PCB REV A y caja diseñadas y verificadas en el CI (DRC 0, ERC 0/0, 0 interferencias). No fabricada. Rama claude/dock-cargador-v1, PR #45. Carpeta hardware/dock/V1.
	•	Alimentación: red de 230 V con módulo Mean Well IRM-20-5, o USB-C de 5 V. La red tiene prioridad.
	•	Electrónica:
	•	ESP32-S3-MINI-1U.
	•	Hub USB2514B: en modo PC el ordenador ve los cascos; en modo autónomo el soporte sirve los entrenamientos por Wi-Fi.
	•	Cada puerto mide su carga (TPS2553 + INA180A2) y la pantalla IPS de 2,0" muestra «cargando / completa / sin cápsula».
	•	Conexiones: pogo de 5 contactos para los cascos y de 3 para las cinchas (REV 5.9.1 y REV 5.10).
	•	Caja: PETG, 200 × 190 × 55 mm, con alojamientos imantados.
	•	Previsto: lector de QR para actualizar la licencia de todos los cascos mientras cargan, y un contrato nuevo DockStatus v1 en las tres apps.
	•	⚠️ No es un producto certificado: necesita ensayo CE antes de venderse.

Común

Arquitectura

                 Caster NTRIP (RTCM3)
                         │
               App Android ──── BLE / Wi-Fi ────┐
                         │ RTCM3 (BLE, CRC-24Q) │
                         ▼                      │
   ┌──────────── RELOJ DE PECHO ◄───────────────┘
   │   graba .avr en microSD · pantalla · BLE/Wi-Fi/USB
   │        ▲ BackStatus v3 (108 B)     │ RTCM3
   │        │ ESP-NOW                   ▼
   │   HARDWARE GPS (RTK 8 Hz + GirthHub)
   │        ▲
   │        │ lotes IMU 220 B (ESP-NOW)
   │   IMU CINCHA (~125 Hz)
   │
   ├── USB AVO1 ──► App Windows
   └── BLE ───────► App iOS ◄── BLE ── Hardware Sync (hora GPS)

   Base de carga ── pogo ──► cascos GPS y cinchas · USB/Wi-Fi ──► PC

Contratos de datos

Si cambia un formato, hay que actualizar a la vez el firmware y todas las apps que lo leen.

Enlace	Formato	Tamaño / integridad	Requisito mínimo
GPS → Pecho (ESP-NOW)	BackStatus v3	108 B	Espalda ≥ 3.9.0, Pecho ≥ 3.7.6
Cincha → GPS (ESP-NOW)	Lote IMU	220 B	Espalda ≥ 3.10.0
Pecho → Apps (BLE GATT)	TELEMETRY v3	116 B	—
Pecho → Windows (USB)	AVO1	Bloques de 4 KB, CRC-32 + SHA-256	Pecho ≥ 3.7.5, Windows ≥ V1.1
Android → Pecho → GPS	RTCM3	CRC-24Q	—
Sync → iPad (BLE)	AVO SYNC v1	16 / 32 B	Propuesta
Base de carga → Apps	DockStatus v1	Por definir	Propuesta
Sesiones	.avr (RAW)	—	—
Configuración	TLV AVOC	—	—
Licencias	.avolic	Firma ECDSA P-256	—

Compilación (GitHub Actions)

Todos los binarios se generan en Actions. Los workflows se disparan con push a develop, filtrados por paths:. No se ejecutan en los PR.

	•	Firmware: pecho, GPS y cincha (.bin).
	•	Android: build-android.yml, que genera la APK.
	•	Windows: instalador / .exe.
	•	iOS: TestFlight.
	•	KiCad: PCB de la cincha, del GPS y de la base de carga.
	•	Archivo: archivar-artefactos.yml guarda la última versión de cada artefacto en archivo/binarios/.

Descarga: Actions → el run correspondiente → Artifacts. Cada artefacto incluye su SHA-256.

No modificar workflows, rutas de artefactos, firmas (AVO_UPDATER_KEYSTORE_*), Info.plist, perfiles ni el build number de TestFlight sin avisar y sin confirmación.

Reglas de desarrollo

	1.	Una sola develop. Cada tarea va en una rama corta que sale de develop y vuelve por PR con merge commit y el CI en verde.
	2.	Nada de líneas paralelas de una misma app o firmware.
	3.	Antes de borrar ramas antiguas, comprobar que existe su etiqueta backup/2026-11-12/* o backup/2026-11-17/*.
	4.	OTA del pecho: solo versiones X.Y.Z sin sufijos.
	5.	Tiempo real: nada de delay() en los bucles IMU (125 Hz) ni GNSS (8 Hz). Usar FreeRTOS, colas e interrupciones.
	6.	GPS: respetar la secuencia de encendido del Pololu (GPIO34) y la lógica de BACK_SLEEP para evitar brownouts.
	7.	Commits en Conventional Commits con el módulo: feat(pecho), fix(espalda), feat(cincha), fix(android), feat(ipad), feat(windows), feat(motor), cad(carcasa).
	8.	CAD: FreeCAD 1.0.2 y Shapr3D. Se imprime en Elegoo Centauri Carbon: PETG para la estructura y TPU 85A/95A para juntas y tapones. Tolerancia de encaje 0,2–0,3 mm. Objetivo IP67.
	9.	PCB: KiCad 9.
	10.	Documentación en español. Cada entrega indica qué está compilado en CI y qué está verificado en hardware real.

Seguridad

	•	Prohibido subir .jks, .keystore, .p12, .pfx, .p8, .mobileprovision, .env, google-services.json con claves restringidas, credenciales NTRIP o claves ECDSA privadas.
	•	La clave privada de licencias vive solo en AVO Tarjetas (y en su copia cifrada). En GitHub solo está la pública (AVO_LICENSE_PUBLIC_KEYS).
	•	Firmas de APK y de App Store Connect: solo como GitHub Secrets.
	•	Las credenciales NTRIP las introduce cada usuario en los ajustes de la app.

Documentación

	•	CLAUDE.md y AGENTS.md: reglas para agentes. Si algo choca, manda el repositorio.
	•	claude/ y docs/: un documento por versión de firmware, carcasa, PCB y app.

© AVO Performance. Todos los derechos reservados.
