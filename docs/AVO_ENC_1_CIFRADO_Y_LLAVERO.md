# AVO-ENC-1 — RAW comprimido y cifrado en el casco + llavero de cuadras y personas

**Estado (16/11/2026): DISEÑO aprobado por el usuario. No hay código.** Nada está implementado, compilado ni verificado.
Las cifras marcadas **(E)** son estimaciones.

**Antes de escribir código:** integrar en `develop/avo-performance-horse` las ramas pendientes, por la regla del proyecto
(casco V5 incluido: `feature/back-v5-casco`).

## 0. Alcance (decisión del usuario, 16/11/2026 21:11)
- **AVO-ENC-1 es solo para el casco**, el producto con PCB propia dedicada al sistema.
- **El pecho y la espalda actuales no se cifran.** Son el **banco de pruebas** y siguen grabando `.avr` sin cifrar, lo que
  facilita depurar.
- Las apps siguen leyendo los `.avr` y `.avo` sin cifrar del banco de pruebas y, además, los `.avoe` del casco.
- **El casco es hardware nuevo, sin la herencia del banco de pruebas.** Desde la primera versión de producción puede llevar:
  - el **arranque seguro** y el **cifrado de flash** del ESP32-S3: protegen el firmware y la configuración (la pública de
    cuadra, el número de serie). Queman eFuses de forma irreversible, así que se activan en la placa de serie, no en los
    prototipos;
  - opcionalmente, un **elemento seguro** (p. ej. ATECC608B), si se quiere identidad del casco no clonable. No hace falta
    para AVO-ENC-1, porque el casco solo guarda llaves públicas.

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
- ~~¿Con la cuadra caducada se pueden consultar en solo lectura los entrenamientos ya descargados?~~ **Resuelto
  (16/11/2026 21:39):** sí, todo lo generado durante la licencia activa (§14).
- ~~¿Quién rellena las plazas?~~ **Resuelto (16/11/2026 21:48):** el cliente las elige en la app al recibir la licencia y
  el casco ata la elección (§15).
- ~~¿Se cifra también lo que guardan el pecho y la espalda actuales?~~ **Resuelto (16/11/2026):** no. Son el banco de
  pruebas; solo cifra el casco.
- ~~¿El casco de serie lleva un elemento seguro (ATECC608B)?~~ **Resuelto (16/11/2026):** sí, por AVO-LOCK-1 (§12).

## 12. AVO-LOCK-1 — el casco solo funciona dentro del sistema y de su licencia (16/11/2026 21:14)
**Requisito del usuario:** el casco no se puede usar más allá del sistema y de la licencia que tenga. Ni con apps de
terceros, ni copiado, ni en otra cuadra sin licencia, ni con un firmware modificado.
Con esto se resuelve la decisión del elemento seguro: **el casco de serie lleva un ATECC608B**.

| Capa | Cómo | Qué impide |
|---|---|---|
| **Identidad no clonable** | ATECC608B con su par de llaves P-256 generado dentro del chip, que nunca sale. En fábrica, AVO Tarjetas firma su **certificado de casco** (nº de serie y pública). | Fabricar un «casco» falso que nuestras apps acepten, o clonar uno |
| **Licencia del casco** | Token firmado por AVO Tarjetas (nº de serie, cuadra, keyId de la cuadra, fecha de fin, funciones), con el mismo esquema que `.avolic`. El casco lo comprueba con la pública de licencias y guarda la última fecha vista, para que no sirva retrasar el reloj. La fecha la da el **GNSS** (ZED-F9P). | Usar el casco sin licencia, caducado o en otra cuadra |
| **Solo apps autorizadas** | Al conectar (BLE, Wi-Fi o USB), el casco envía un reto aleatorio. La app lo firma con la **llave de la cuadra** de su llavero, y el casco lo verifica con la pública de cuadra instalada (firmada, §7). A la vez, la app comprueba el certificado del casco con un reto que firma el ATECC. Después se crea una llave de sesión ECDH para cifrar todo el canal. | Que una app de terceros o un móvil sin licencia de esa cuadra configure, grabe, haga streaming o descargue |
| **Firmware intocable** | Arranque seguro v2 y cifrado de flash del ESP32-S3 en la placa de serie. Las OTA van firmadas (mantienen el formato `X.Y.Z`). | Quitar las comprobaciones cambiando el firmware o leer la flash |
| **Datos** | AVO-ENC-1 (§1–§9): cifrados para la cuadra | Leer la SD fuera del sistema |

**Qué hace el casco según su estado** (confirmado el 16/11/2026):
- **Licencia válida:** funciona todo.
- **Faltan 7 días o menos:** funciona todo, y la app avisa.
- **Caducada:**
  - **no graba** sesiones nuevas ni hace streaming;
  - **sí deja descargar** lo ya grabado a una app autorizada de su cuadra, porque los datos son del cliente;
  - se reactiva con una licencia nueva que se instala desde la app, como hoy el `.avolic`.
- **Sin licencia o de otra cuadra:** solo deja instalar una licencia firmada; nada más.
- **Sin conexión:** la licencia se comprueba en el propio casco y no necesita internet.

**Límites honestos:**
- **Atacante con laboratorio:** con medios caros (glitching, microscopio) un chip puede llegar a atacarse. Esto sube el
  listón muy por encima de lo que compensa copiar el sistema.
- **Fecha antes del primer fix GNSS:** se usa la última fecha guardada, que solo avanza, y la licencia se comprueba en
  cuanto hay fix.
- **Llaves de producción:** la pública de licencias y el certificado de fábrica se graban al producir el casco; ninguna
  llave privada va en el firmware ni en el repositorio.

**Decisiones (confirmadas por el usuario el 16/11/2026 21:18):**
1. **Margen al caducar:** aviso desde 7 días antes y bloqueo de la grabación el día de fin.
2. **Con la licencia caducada,** los datos ya grabados **sí** se pueden descargar a una app autorizada de su cuadra.
3. **Dos licencias:** el casco lleva su licencia (de la cuadra) y la app la de la persona que conecta. Hacen falta las dos.

## 13. Alquiler mensual: cambiar el casco de cuadra (16/11/2026 21:19)
El casco se alquila por meses. Cuando un cliente lo devuelve, se puede entregar a otra cuadra. Lo hace **solo AVO**, con
AVO Tarjetas, porque hace falta firmar una licencia nueva. Una cuadra no puede pasárselo a otra por su cuenta.

**Mes a mes:**
- la licencia del casco vale hasta el fin del periodo pagado;
- al renovar, AVO emite una licencia nueva, que la cuadra instala desde la app con un archivo, igual que el `.avolic`;
- si no se renueva, rigen las reglas de §12: aviso 7 días antes, el día de fin deja de grabar y lo grabado se puede descargar.

**Devolución y entrega a otra cuadra:**
1. **Antes de devolverlo**, la app de la cuadra muestra «Devolver casco». Comprueba que todas las sesiones están descargadas
   y, si falta alguna, avisa y ofrece descargarla. El casco marca cada sesión descargada.
2. **AVO emite para el casco** (identificado por el nº de serie de su ATECC608B):
   - una **licencia de la cuadra nueva**;
   - la **llave pública de esa cuadra**, firmada.
3. **Al instalarla**, el casco:
   - **borra la SD**. Los `.avoe` de la cuadra anterior ya eran ilegibles para la nueva, porque iban cifrados para la anterior,
     pero se borran igualmente;
   - olvida la llave pública anterior, los emparejamientos y la configuración (geocercas, ajustes de la cuadra);
   - guarda un registro interno del cambio: fecha, cuadra anterior y nueva, nº de licencia.
4. **Sesiones sin descargar:** el casco **rechaza** el cambio de cuadra salvo que la licencia nueva lleve la marca
   `BORRAR_PENDIENTES`, que AVO solo pone si la cuadra anterior lo confirma o si hay que forzarlo.
5. **Las apps de la cuadra anterior** ya no pueden conectarse: el reto de §12 exige la llave de la cuadra nueva.

**Lo que no cambia:** la identidad del casco (certificado del ATECC608B). En AVO Tarjetas cada casco tiene su historial:
cuadras, periodos, licencias y devoluciones.

## 14. Jerarquía de licencias: la de la cuadra manda (16/11/2026 21:35)
**Regla del usuario:** con la licencia de la cuadra caducada no funciona ninguna licencia que cuelgue de ella: ni la del
entrenador, ni las de los jockeys, ni los caballos.

```
Licencia de CUADRA (raíz, fecha de fin)
 ├─ Licencias de PERSONA en esa cuadra (entrenador, jockey, veterinario, propietario)
 ├─ CABALLOS de la cuadra y sus asignaciones
 └─ Licencias de CASCO de la cuadra (§12, §13)
```

**Aclaración del usuario (16/11/2026 21:39):** las licencias de entrenador, jockeys, caballos, etc. **no tienen caducidad
propia**. Todas van asociadas a la cuadra y a su caducidad, y no funcionan más allá de esa fecha.

**Cómo se aplica:**
- **Las licencias hijas no llevan fecha de fin.** Solo llevan el id de su cuadra. La única fecha de fin es la de la licencia
  de la cuadra, y la app la comprueba siempre antes que la de la persona (o la del casco).
- **Personas con varias cuadras** (veterinario, propietario): solo se corta su acceso a la cuadra caducada. Con las demás
  cuadras sigue funcionando igual.
- **Renovar la cuadra reactiva todo** lo que cuelga de ella. No hace falta reemitir las licencias de las personas.
- **Fecha fiable:** la app usa la fecha más reciente entre el reloj del dispositivo, la última fecha vista (que solo avanza)
  y la fecha GNSS que le da el casco al conectar. Atrasar el reloj del móvil no sirve.
- **Aviso:** desde 7 días antes del fin de la cuadra, todas las apps de la cuadra lo muestran, igual que con el casco.

**Con la cuadra caducada** (confirmado por el usuario el 16/11/2026 21:39):
- **No se genera nada nuevo:** no se graba, no hay streaming, no se asignan caballos ni se crean entrenamientos o carreras.
- **Sí se puede ver en las apps todo lo generado mientras la licencia estuvo activa,** en solo lectura (entrenamientos,
  carreras, análisis e informes que ya existían). Nada posterior a la fecha de fin.
- **Se puede descargar del casco** lo ya grabado (§12, punto 2), que por definición se grabó con la licencia activa.
- Exportar y enviar a otros usuarios quedan bloqueados mientras esté caducada.

**Cambios por componente:**
- **AVO Tarjetas:** la fecha de fin solo existe en la licencia de cuadra; las licencias de persona y caballo no la llevan.
- **Apps (Android, Windows, iPad):** comprobar la cuadra antes que la persona; avisos y bloqueos.
- **Casco:** la fecha de fin de su licencia ya es, como máximo, la de la cuadra.

## 15. Cupo de caballos de la licencia de cuadra (16/11/2026 21:43)
**Regla del usuario:**
- la licencia de cuadra incluye un **número de caballos** contratado;
- **no se puede cambiar de caballo** durante el periodo: solo contratando otro caballo o al **renovar** la licencia (p. ej.
  licencia de 1 caballo y 1 mes: hasta renovar no se puede asignar otro caballo);
- **desde que se asigna un caballo nuevo a una plaza, el anterior queda bloqueado** para usarse con el casco.

**Flujo confirmado por el usuario (16/11/2026 21:48):**
1. El cliente puede **crear en la app todos los caballos que quiera** (fichas, datos, fotos). Crear un caballo no gasta
   plaza.
2. **Al recibir la licencia** (nueva o renovada), la app pide **seleccionar el caballo o los caballos** de las plazas
   contratadas, ni más ni menos.
3. Con eso la app **se activa para esos caballos**, que quedan **bloqueados: no se puede cambiar su nombre ni su id**
   mientras ocupen plaza (y tampoco después, para que su historial siga siendo suyo).
4. Hasta la siguiente renovación, o hasta contratar otra plaza, no se puede elegir otro caballo.

**Diseño:**
- **La licencia firmada lleva el número de plazas,** no los caballos: `plazas: N` y un número de licencia. AVO no necesita
  saber de antemano qué caballos elegirá el cliente.
- **Identidad del caballo:** cada ficha creada en la app recibe un `caballoId` aleatorio (UUID) que nunca se reutiliza. Al
  activarse, el nombre y el `caballoId` quedan bloqueados. Duplicar la ficha crea otro caballo, que no tiene plaza.
- **La elección se ata en el casco,** que es la pieza de confianza (arranque seguro, flash cifrada, ATECC608B):
  1. la app firma la elección `{nº de licencia, [caballoId, nombre]…}` con la llave de la cuadra y la envía al casco en la
     conexión autenticada de §12;
  2. el casco la acepta **solo si las plazas de ese nº de licencia están vacías** y si el número de caballos coincide con
     las plazas. Una vez guardada, **no la cambia** hasta que llegue una licencia con otro número (renovación o ampliación);
  3. el casco devuelve un **comprobante de activación** firmado por su ATECC608B. Las demás apps de la cuadra lo verifican
     con el certificado del casco y bloquean esos caballos igual.
  Si dos móviles de la cuadra eligen caballos distintos, vale la primera elección que llega al casco; la otra app recibe el
  comprobante y se corrige sola.
- **Varios cascos en la cuadra:** el comprobante del primer casco se instala en los demás desde la app; cada casco lo
  verifica con el certificado del que lo firmó y adopta la misma elección.
- **El casco solo graba con un caballo activado.** Antes de grabar, la app elige uno de los caballos activados y el casco lo
  comprueba; si no está, rechaza la sesión. El `caballoId` va en la cabecera del `.avoe` (dentro de la parte autenticada) y la
  app no deja reasignar (AVO-ASSIGN-1) una sesión a un caballo sin plaza en la fecha de la sesión.
- **Al renovar** (confirmado por el usuario el 16/11/2026 21:49): llega la licencia nueva (enlace `avo://` o QR) y la app
  muestra la selección con **los caballos que ya tenían plaza marcados de inicio**. El cliente confirma para seguir con
  ellos o cambia alguno por otro. Si no cambia nada, sus caballos siguen activados sin interrupción.
- **Caballo que deja la plaza:** desde la activación del nuevo queda **bloqueado para el casco** (no se puede grabar con
  él). Igual que en §14, **sus datos de cuando tenía plaza se pueden ver** en las apps.
- **Ampliar plazas a mitad de periodo:** AVO emite una licencia con más plazas y nuevo número; la app pide elegir solo los
  caballos de las plazas nuevas y mantiene los ya activados. La plaza nueva vence con la cuadra.
- **Historial en AVO Tarjetas:** al pedir la renovación, la cuadra envía el comprobante de activación del periodo y AVO
  guarda qué caballo ocupó cada plaza y cuándo.

**Cambios por componente:**
- **AVO Tarjetas:** número de plazas en la licencia de cuadra, verificación de comprobantes, historial.
- **Apps (Android, Windows, iPad):** pantalla «Selecciona los caballos de tu licencia» al recibirla, bloqueo de nombre e id,
  selector de caballo limitado a los activados, aviso «sin plaza».
- **Casco:** guardar la elección por nº de licencia, emitir el comprobante con el ATECC608B, comprobar el caballo antes de
  grabar, `caballoId` en la cabecera del `.avoe`.
