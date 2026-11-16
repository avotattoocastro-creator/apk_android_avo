# AVO-ENC-1 — RAW comprimido y cifrado en el casco + llavero de cuadras y personas

**Estado (16/11/2026): DISEÑO aprobado por el usuario. No hay código.** Nada está implementado, compilado ni verificado.
Las cifras marcadas **(E)** son estimaciones.

**Antes de escribir código:** integrar en `develop/avo-performance-horse` las ramas pendientes, por la regla del proyecto
(casco V5 incluido: `feature/back-v5-casco`).

## 1. Objetivo
- **Casco:** el casco (espalda V5) guarda en la microSD el RAW **completo**, **comprimido** y **cifrado**. Sacando la SD y
  abriéndola en un ordenador no se puede leer nada; solo nuestras apps (Android, Windows, iPad), con la tarjeta de una
  persona autorizada, pueden abrir los datos.
- **Quién lo abre:** los datos pertenecen a la **cuadra**. Pueden abrirlos las personas de esa cuadra (entrenador, jinete,
  veterinario, propietario) y, si se quiere, solo el propietario de cada caballo. Un propietario o veterinario que trabaja
  con varias cuadras usa **una sola tarjeta**.

## 2. Modelo de llaves (decisión del usuario, 16/11/2026)

| Llave | Quién la genera | Dónde está la parte privada | Para qué |
|---|---|---|---|
| **Cuadra** (P-256, una por cuadra y por versión) | AVO Tarjetas | AVO Tarjetas y el **llavero** de cada persona de esa cuadra | El casco cifra cada entrenamiento para la cuadra |
| **Personal** (P-256, una por persona) | AVO Tarjetas | AVO Tarjetas y el llavero de esa persona | Copias de un entrenamiento para un propietario, veterinario o destinatario concreto |
| **Clave secreta de la tarjeta** (ya existe) | AVO Tarjetas | Tarjeta NFC / activación de móvil | Abre el llavero en la app |
| **Firma de licencias** (ECDSA P-256, ya existe) | AVO Tarjetas | **Solo** AVO Tarjetas | Firma licencias, llaveros y la llave pública que se instala en el casco |

- **En la tarjeta NFC no van las llaves de cuadra:** una NTAG215/216 solo tiene 500–900 B. La tarjeta sigue llevando lo de
  hoy (identidad, clave secreta y licencia con roles).
- **El llavero va en la app,** cifrado con la clave secreta de la tarjeta. Sin acercar la tarjeta (o sin el móvil
  activado), no se abre.
- **Varias cuadras:** el llavero tiene una entrada por cuadra. Al empezar o dejar de trabajar con una cuadra, AVO Tarjetas
  reemite el llavero, igual que hoy el archivo `.avolic`, por WhatsApp, email o NFC de móvil a móvil.
- **iPad:** no tiene NFC, así que se activa por archivo, como hoy las licencias.

## 3. Algoritmos (nativos en las cuatro plataformas)
- **Acuerdo de clave:** ECDH **P-256**.
  - ESP32-S3: mbedTLS por software (≈ 50–150 ms por sesión, **E**).
  - iPad: CryptoKit `P256.KeyAgreement`.
  - Android: `KeyAgreement("ECDH")` con secp256r1.
  - Windows: .NET `ECDiffieHellman` nistP256.
  - X25519 se descarta porque .NET no lo tiene de serie.
- **Derivación:** HKDF-SHA256.
- **Cifrado:** AES-256-GCM, por hardware en el ESP32-S3; etiqueta de 16 B por bloque.
- **Compresión:** deflate en crudo (miniz `tdefl`, nivel 1) por bloque. Si un bloque no se reduce, se guarda tal cual
  (`algo = 0`).
- **Aleatoriedad:** `esp_random()` con la radio encendida (RNG por hardware); en las apps, el generador seguro del sistema.

## 4. Formato en la SD del casco: `.avoe` (un archivo por segmento, como hoy `P00n.avr`)

Todo en little-endian. **Se comprime antes de cifrar**, porque los datos cifrados ya no se pueden comprimir.

```
CABECERA
  magic "AVOE" · ver u8 = 1 · flags u8 · hdrLen u16
  sessionId (16 B) · segmento u16 · creado (u32, s UTC) · nº de serie del casco (8 B)
  prefijo de nonce (4 B, aleatorio por segmento)
  nº de destinatarios u8, y por cada uno:
    tipo u8 (1 = cuadra, 2 = persona, 3 = propietario de caballo) · keyId (8 B = SHA-256(SPKI)[0..8])
    pública efímera (65 B, P-256 sin comprimir) · llave de sesión envuelta (32 B + etiqueta de 16 B)
  SHA-256 de todo lo anterior (32 B)

BLOQUES (hasta el final del archivo)
  seq u32 · plano u32 (bytes RAW) · cifrado u32 · algo u8 (0 = guardado, 1 = deflate) · fin u8 (1 = último del segmento)
  datos cifrados con AES-256-GCM (nonce = prefijo 4 B ‖ seq u64; AAD = SHA-256 de la cabecera ‖ seq ‖ plano ‖ algo ‖ fin)
  etiqueta (16 B)
```

- **Llave de sesión:** 32 B aleatorios por segmento.
- **Envoltura para un destinatario:**
  - `KEK = HKDF-SHA256(ECDH(efímera, pública del destinatario), sal = efímera ‖ pública, info = "AVO-ENC-1/wrap")`;
  - `envuelta = AES-256-GCM(KEK, nonce = 0, llave de sesión, AAD = keyId ‖ sessionId ‖ segmento)`;
  - la nonce cero vale porque cada KEK se usa una sola vez.
- **Bloques de 16 KB de RAW:**
  - Si se corta la corriente, se pierde como mucho el último bloque (≈ 2–4 s de datos, **E**).
  - Cada bloque se lee por separado, así que una SD dañada no arruina el resto.
- **Compresión esperada:** de 2 a 3,5 veces (**E**, sin medir). Hay que medirla con RAW reales del 07–08/11.
- **Integridad:** la etiqueta GCM de cada bloque y la de la cabecera sustituyen la comprobación por SHA-256 de los
  segmentos. Las descargas Wi-Fi, BLE y USB (bloques AVO1 con CRC-32/SHA-256) mueven los archivos sin tocarlos.

## 5. El `.avo` cifrado (en las apps)
- **Empaquetado:** al descargar, las apps empaquetan los `.avoe` en el `.avo` de siempre. **Los segmentos se copian byte a
  byte, sin descifrar.**
- **Bloque `cifrado` del `manifest.json`:**
  - `formato: "AVO-ENC-1"`;
  - lista de destinatarios con tipo, `keyId`, nombre y, por segmento, la pública efímera y la llave envuelta.
- **Asignar caballo (AVO-ASSIGN-1):** la app de alguien que pueda abrir el entrenamiento (la cuadra) **añade un
  destinatario** para la llave personal del propietario de ese caballo y, si se configura, para su veterinario. Solo cambia
  `manifest.json`; los segmentos no se tocan.
- **Enviar a otro usuario** (Firebase, archivo): se añade un destinatario para su llave personal antes de enviar.
- **El motor** recibe el RAW descifrado **en memoria**. Las apps no escriben el RAW descifrado en disco y la caché guarda el
  cifrado. Esto hay que revisarlo en la caché de RAW del iPad y en la de Windows.
- **Archivos antiguos:** las apps siguen abriendo los `.avr` y `.avo` sin cifrar.

## 6. El llavero: `.avokeys`
- **Formato del archivo:** `AVO-KEYRING-1` · código de usuario · base64(iv ‖ AES-256-GCM(K, JSON) ‖ firma ECDSA).
  - `K = HMAC-SHA256(clave secreta de la tarjeta, "AVO-KEYRING/1")`, el mismo esquema que el `.avolic`.
  - Lo firma AVO Tarjetas con su clave de licencias, para que nadie pueda fabricar o cambiar un llavero.
- **Contenido del JSON:**
  - el titular y su llave personal (PKCS#8);
  - las entradas `{tipo: "cuadra", id, nombre, keyId, pkcs8, desde, hasta}`, que incluyen las **versiones antiguas** de cada
    llave de cuadra para poder seguir leyendo los datos de antes de una rotación.
- **En la app:**
  - se guarda cifrado con el almacén del sistema (Keychain, Android Keystore, DPAPI);
  - se abre al acercar la tarjeta, o con el móvil activado.

## 7. Configurar el casco
- **Pública de cuadra firmada:** la app instala en el casco la **llave pública de su cuadra**, firmada por AVO Tarjetas
  (cuadra, keyId, versión, firma ECDSA). El casco lleva la pública de licencias, comprueba la firma y **rechaza llaves no
  firmadas**. Así, quien robe un casco no puede ponerle su propia llave para leer lo que grabe después.
- **Casco prestado a otra cuadra:** se instala la pública de la nueva cuadra. Lo grabado antes sigue siendo de la cuadra
  anterior.
- **Sin llave instalada:** el casco graba **sin cifrar**, marcado `SIN CIFRAR`, y la app avisa. Nunca se pierde un
  entrenamiento. *Decisión pendiente:* ¿se permite grabar sin cifrar?

## 8. Quitar acceso, rotar llaves y pérdidas
- **Quitar acceso solo vale hacia delante:** lo que alguien ya descargó y abrió no se puede «des-compartir».
- **Si alguien deja la cuadra o se pierde una tarjeta:**
  1. se crea una versión nueva de la llave de la cuadra;
  2. se instala en los cascos;
  3. se reemiten los llaveros de las personas que siguen.
- **Si se pierde la llave privada de una cuadra** (se pierde AVO Tarjetas sin copia), **sus datos cifrados no se pueden
  recuperar**. La copia completa con contraseña de AVO Tarjetas incluye ahora todas las llaves de cuadra y personales, y es
  imprescindible.
- **Ningún esquema con descifrado sin internet es inviolable:** un atacante con mucho tiempo y una tarjeta válida puede
  sacar las llaves de su propio llavero. El daño queda limitado a las cuadras y caballos de esa persona.

## 9. Cambios por componente (contrato: todo a la vez)

| Componente | Cambio |
|---|---|
| Firmware casco V5 | Escritor `.avoe` por bloques (miniz + AES-GCM + ECDH), llave pública de cuadra firmada en NVS, indicador «cifrado» en el estado |
| AVO Tarjetas | Llaves de cuadra (con versiones), llaves personales, pertenencia persona ↔ cuadras, emisión de `.avokeys`, firma de la pública para el casco, copia completa ampliada |
| Núcleo Android (Kotlin), Windows (C#), iPad (Swift) | Lector y escritor AVO-ENC-1, llavero, añadir destinatarios al asignar o enviar, descifrado en memoria para el motor |
| Apps | Abrir el llavero con la tarjeta, avisos «sin llave para esta cuadra» y «SIN CIFRAR», instalar la llave en el casco |
| Pruebas | **Vectores de prueba comunes** (mismos bytes en C, Kotlin, C# y Swift), simulación de corte de corriente, SD dañada, rotación de llaves |

## 10. Fases
0. Integrar las ramas pendientes en develop (requisito).
1. Biblioteca AVO-ENC-1 con vectores de prueba en las cuatro plataformas. Resultado: **compilado en CI**.
2. AVO Tarjetas: llaves y llaveros. Resultado: **compilado en CI**.
3. Apps: abrir, asignar y enviar entrenamientos cifrados. Resultado: **compilado en CI**.
4. Firmware del casco V5: escritor `.avoe`. Resultado: **compilado en CI**.
5. Pruebas en hardware: medir la compresión, el consumo y el tiempo por bloque, cortar la corriente y quitar la SD. Hasta
   entonces, nada está **verificado en hardware real**.

## 11. Decisiones pendientes del usuario
- ¿Se permite grabar **sin cifrar** si el casco no tiene llave? (propuesta: sí, marcado y con aviso)
- ¿El veterinario de un caballo recibe copia automática al asignar, o solo cuando se le envía?
- ¿Se cifra también lo que guardan el **pecho** y la espalda actual, o solo el casco V5?
