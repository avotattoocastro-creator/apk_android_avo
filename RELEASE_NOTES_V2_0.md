# AVO Performance Horse — Android V2.0

**versionCode 12 · versionName 2.0 · rama `develop/avo-performance-horse`**

## Diseño
- Toda la app usa los colores de la pantalla de inicio: negro #030406, rojo AVO #ED122A / #B71625 / #FF495A,
  plata y azul eléctrico para datos. Tarjetas con degradado y borde fino, mosaicos de métricas, selectores tipo píldora.
- Navegación: **Inicio · Entrenar · Historial · Mareas · Cuadra** y engranaje de **Ajustes** arriba.
- Se han quitado los textos explicativos que solo ocupaban espacio. Se mantienen los avisos y errores reales.
- **La pantalla de arranque no se ha modificado.**

## Mareas (estilo Tu Marea Pro, datos oficiales)
- Predicción oficial del **Instituto Hidrográfico de la Marina (IHM)**: horas y alturas de pleamares y bajamares sobre
  el cero hidrográfico del puerto. Es la misma fuente que usan las apps de mareas españolas.
- Puerto de referencia: el más cercano al lugar de entrenamiento (por defecto El Regatón), con selector y buscador.
- Tira de 14 días con coeficiente y fase lunar, estado «Ahora» (altura, sube/baja, próxima marea y cuenta atrás,
  anillo de coeficiente), curva del día que se puede **deslizar** para leer la altura a cualquier minuto, noche sombreada.
- Coeficiente = 70 × carrera / carrera media del puerto (3 meses de predicciones del IHM), escala 20–120.
- Sol (salida, puesta, crepúsculos, horas de luz), luna (fase, iluminación, salida y puesta). Calculados en el móvil.
- Tiempo y mar por horas (Open-Meteo): temperatura, viento y rachas con dirección, lluvia, humedad, presión, ola,
  periodo y temperatura del agua.
- Caché en el móvil: los meses del IHM se guardan 30 días y funcionan sin conexión.

## Análisis de entrenamientos
- Pestañas **Resumen · Mapa y gráficas · Datos**.
- Resumen: distancia, tiempo, tiempo en movimiento, velocidades, ritmo, aceleración y frenada máximas en g, cadencia
  máxima, desnivel y % RTK FIX; mapa; reparto de aires; **tramos rápidos**; **eventos**; parciales; marea y tiempo.
- Mapa **Mapa / Satélite / Híbrido**, trazado coloreado por velocidad, aire o RTK, reproducción con barra de tiempo.
- **Gráficas sincronizadas** con zoom común: velocidad, aceleración, cadencia de la IMU de la cincha, altitud y precisión.
  Al tocar una gráfica se mueve el punto en el mapa y en todas las demás.
- Tramo A–B con métricas y tramos guardados (como en V1.9).
- Datos: GNSS/RTK, IMU cincha, velocidad y tramos, pendiente y altitud, fichero y borrado del reloj.
- Marea y tiempo de la sesión para **cualquier fecha** (IHM + Open-Meteo, archivo histórico para sesiones antiguas).

## Valores honestos
- Los aires se estiman por velocidad GNSS (parado < 1,5 km/h, paso < 8, trote < 16, galope ≥ 16).
- La cadencia se mide por la periodicidad de la aceleración de la cincha, sin depender de la escala del sensor.
- No se muestra aceleración en g desde la IMU porque su escala no está documentada; la aceleración en g procede de la velocidad GNSS.

## Cuadra
- **Foto de cada caballo** (se reduce a 720 px y se guarda en el móvil). Base de datos 3 → 4 con migración.
- Sesiones, kilómetros y velocidad máxima de cada caballo.

## Retirado
- Todo lo de **OTA**: ya se actualiza con la app AVO USB Updater. Protocolo, verificador, pantalla y flujo de diagnóstico eliminados.

## No se ha tocado
BLE, NTRIP/RTCM, sincronización y descarga, NFC, geocercas, No molestar y compartir por WhatsApp funcionan igual.

## Pendiente de verificar en el móvil
Aspecto en pantalla, lectura real del IHM y Open-Meteo, mapa híbrido y migración de la base de datos con datos existentes.
