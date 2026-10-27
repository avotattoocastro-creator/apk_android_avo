# Licencias de AVO Performance Horse (tarjeta NFC y archivo)

App Android **2.4-license-dev1** · AVO Tarjetas **1.1-license-dev1** · rama `feature/avo-license-nfc` · 27/10/2026.
Estado: implementado, núcleo probado en JVM (25 pruebas), **NO VERIFICADO** en teléfono ni con tarjetas reales.

## Qué hace

- La **tarjeta NFC de usuario** puede llevar una **licencia de la app** con fecha de fin, grabada con AVO Tarjetas.
- Se acerca **una vez** al móvil y la licencia queda guardada en él hasta esa fecha. Para renovar, se regraba la tarjeta con otra fecha y se acerca de nuevo.
- Si el usuario está lejos, AVO Tarjetas genera un **archivo de licencia** (`.avolic`) que se envía por WhatsApp o email.
- Al caducar, o sin licencia, la app pasa a **modo consulta**:
  - **Se puede:** ver entrenamientos ya guardados, análisis, comparativas, la cuadra y Acerca de.
  - **Bloqueado:** conexión con el chaleco (y con ella espalda y cincha), grabación, descargas BLE/Wi-Fi, NTRIP, mareas y meteorología, compartir por Firebase, Ajustes y tarjetas de caballo y jinete. El servicio en segundo plano se detiene.
  - En Inicio aparece el aviso «SISTEMA SIN LICENCIA ACTIVA» con el botón «Reactivar licencia».
- Aviso en Inicio **7 días antes** de caducar. Los datos no se borran nunca.

## Seguridad

| Amenaza | Protección |
|---|---|
| Cambiar la fecha de la tarjeta | Firma **ECDSA P-256 / SHA-256** sobre usuario, UID, fechas y serie. La clave privada solo está en AVO Tarjetas; la app solo lleva la pública. Cambiar un byte invalida la firma. |
| Copiar la licencia a otra tarjeta normal | La firma incluye el **UID del chip**. En otra tarjeta, el UID no coincide y la app la rechaza. |
| Copiar a una tarjeta «mágica» con UID modificable | **No se puede impedir con NTAG213/215/216.** Haría falta NTAG 424 DNA. Limitación aceptada. |
| Reenviar el archivo de licencia a otra persona | El archivo va **cifrado (AES-256-GCM)** con una clave derivada del secreto de la tarjeta de ese usuario. Solo lo abre un móvil donde se haya acercado esa tarjeta. Además va firmado y marcado «por archivo». |
| Atrasar el reloj del móvil | Hora efectiva = la mayor entre: hora del móvil, última hora conocida (guardada) y contador monotónico desde el arranque (no se puede cambiar). En Android 13+ manda la **hora de red**. Si el móvil va atrasado, se avisa. |
| Editar los datos guardados de la licencia | La licencia y su registro de hora se guardan juntos, cifrados con una clave del **Android Keystore** (AES-GCM). Si se alteran, se pierde la licencia. |
| Prestar la tarjeta para activar otro móvil | No se puede impedir sin conexión: la tarjeta es el «carné». |
| Recompilar la app sin la comprobación | **El repositorio es público.** Cualquiera puede compilarla sin licencias. Recomendación: hacer el repositorio **privado**. |

## Puesta en marcha (una sola vez)

1. Instala **AVO Tarjetas 1.1** y pulsa **Clave de licencias → GENERAR CLAVE**.
2. Pulsa **EXPORTAR COPIA CIFRADA**, pon una contraseña de 10 caracteres o más y guarda el archivo fuera del móvil.
   - Sin esa copia, si pierdes el móvil, habrá que regrabar todas las tarjetas y publicar otra app.
3. Pulsa **Copiar** (clave pública) y pégala en GitHub:
   - **Settings → Secrets and variables → Actions → Variables → New repository variable**;
   - nombre `AVO_LICENSE_PUBLIC_KEYS`;
   - valor: la clave. Si hay varias, sepáralas con comas (por ejemplo, una clave nueva y la anterior durante un cambio).
   - No es un secreto: es la clave pública.
4. Lanza la compilación de Android. El aviso de CI dice «Licencias ACTIVADAS: 1 clave(s)».
   - **Sin la variable, la APK no controla licencias:** versión de desarrollo, todo desbloqueado. En Ajustes → Licencia indica «NO REQUERIDA».
5. Antes de instalar la app con licencias, graba tu propia tarjeta con licencia: en cuanto se instale, la app pedirá activarla.

## Uso diario

- **Grabar o renovar una tarjeta:** en **Tarjetas emitidas** pulsa **Renovar** o **Licencia**, elige la fecha y acerca la tarjeta.
  - Para una tarjeta nueva: **Nueva tarjeta personal** con **Licencia de la app** marcado.
  - La fecha elegida está incluida: la licencia vale hasta las 23:59 de ese día.
  - Las tarjetas con licencia no se bloquean, para poder renovarlas.
  - Usa NTAG215 o NTAG216.
- **Licencia por archivo:** pulsa **Por archivo**, elige la fecha y comparte por WhatsApp o email.
  - El usuario lo abre con la app, o en la app: **Inicio → Reactivar licencia → ABRIR ARCHIVO DE LICENCIA**.
  - Si el móvil es nuevo, primero tiene que acercar su tarjeta una vez, aunque esté caducada.
- **Comprobar una tarjeta:** acércala con AVO Tarjetas en modo lectura. Muestra la fecha y si la firma es válida, si es de otra clave o si es una copia.

## Formato

- **Registro NDEF:** tipo externo `avoperformance.org:lic`, entre el registro URI de identidad y el AAR.
  - Ocupa 107 B con un UID de 7 B.
  - Disposición: `AVOL` · ver · keyId(4) · uidLen · UID · código de usuario(13) · emitida(u32 s) · caduca(u32 s, exclusiva) · serie(4) · flags · firma r‖s(64).
  - Firma sobre `"AVO-LICENSE/1\0"` + cuerpo. `flags` bit 0 = licencia por archivo.
- **Archivo `.avolic`:**
  - Formato: `AVO-LICENSE-FILE-1` · código de usuario · base64(iv ‖ AES-256-GCM(token)).
  - La clave AES es HMAC-SHA256(secreto de la tarjeta, `"AVO-LICENSE-FILE/1"`).
- **Copia de la clave:**
  - Formato: `AVO-LICENSE-KEY-BACKUP-1` · base64(iteraciones ‖ sal ‖ iv ‖ AES-256-GCM(SPKI ‖ PKCS#8)).
  - La clave se deriva con PBKDF2-HMAC-SHA256 (310 000 iteraciones).
- **Código:**
  - `core/.../core/license/` (pruebas en `core/src/test/.../license/LicenseTest.kt`);
  - `app/.../license/LicenseManager.kt`;
  - `app/.../ui/screens/LicenseScreens.kt`;
  - `cards/`.

## Pendiente de verificar en teléfono

1. Generar la clave, exportar e importar la copia en otro móvil.
2. Compilar con la variable y comprobar que la app pide la licencia.
3. Grabar una tarjeta NTAG215 con licencia, activarla, comprobar «Activa hasta…» y leerla en AVO Tarjetas.
4. Copiar el contenido NDEF a otra tarjeta y comprobar que se rechaza.
5. Licencia por archivo por WhatsApp y por email: abrirla desde el chat y desde el botón de la app.
6. Caducidad, con una fecha cercana:
   - modo consulta;
   - chaleco desconectado;
   - mareas y ajustes bloqueados;
   - servicio detenido;
   - reactivación con tarjeta y con archivo.
7. Atrasar la fecha del móvil (sin hora automática) y comprobar que la licencia sigue caducada y aparece el aviso.
