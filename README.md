# AVO Performance Horse — Android

Repositorio de la aplicación Android del sistema AVO Performance Horse.

## Estado
- Acceso de escritura comprobado el 19/10/2026.
- Pendiente incorporar el **código fuente real de la app Android** (carpeta app/, Gradle y dependencias).
- La compilación de una APK de depuración se ejecutará automáticamente con GitHub Actions al subir fuentes a main.

## Cómo obtener la APK
1. Incorporar el proyecto Android (settings.gradle.kts o settings.gradle, build.gradle.kts o build.gradle, app/ y preferiblemente el Gradle Wrapper).
2. Abrir **Actions** y el workflow **Build AVO Android APK**.
3. La compilación se inicia automáticamente al subir código a main; también puede iniciarse con Run workflow.
4. Descargar el artefacto **AVO-Performance-Horse-debug-APK** de la ejecución.

La APK de depuración sirve para pruebas. Una versión de distribución requiere firma propia y un proceso de release.

## Seguridad
Este repositorio es **público**. No incorporar contraseñas, claves NTRIP, tokens de API ni credenciales del servidor. Utilizar configuración externa y GitHub Actions Secrets cuando corresponda.
