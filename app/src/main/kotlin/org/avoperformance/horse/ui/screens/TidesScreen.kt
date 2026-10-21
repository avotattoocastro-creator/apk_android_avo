package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.avoperformance.horse.ui.components.AvoCard
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private data class MarineHour(val time: String, val sea: Double?, val wave: Double?, val period: Double?, val direction: Double?, val water: Double?)
private data class MarineForecast(val hours: List<MarineHour>, val receivedAt: Long)
private val hourFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
private fun JSONObject.valuesOrEmpty(key: String) = optJSONArray(key)
private fun org.json.JSONArray?.number(i: Int): Double? = this?.optDouble(i, Double.NaN)?.takeIf { it.isFinite() }
private fun fmt(v: Double?, unit: String) = if (v == null) "—" else String.format(Locale.getDefault(), "%.2f %s", v, unit)

private suspend fun fetchMarine(): MarineForecast = withContext(Dispatchers.IO) {
    // Approximate beach coordinate; Open-Meteo resolves the nearest ocean model cell.
    val url = URL("https://marine-api.open-meteo.com/v1/marine?latitude=43.397&longitude=-3.426&hourly=sea_level_height_msl,wave_height,wave_period,wave_direction,sea_surface_temperature&timezone=Europe%2FMadrid&forecast_days=7&cell_selection=sea")
    val conn = (url.openConnection() as HttpURLConnection).apply {
        connectTimeout = 12000
        readTimeout = 12000
        requestMethod = "GET"
    }
    try {
        if (conn.responseCode !in 200..299) error("Servidor marino: HTTP ${conn.responseCode}")
        val json = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
        val hourly = json.getJSONObject("hourly")
        val times = hourly.getJSONArray("time")
        val sea = hourly.valuesOrEmpty("sea_level_height_msl")
        val wave = hourly.valuesOrEmpty("wave_height")
        val period = hourly.valuesOrEmpty("wave_period")
        val direction = hourly.valuesOrEmpty("wave_direction")
        val water = hourly.valuesOrEmpty("sea_surface_temperature")
        MarineForecast((0 until times.length()).map { i ->
            MarineHour(times.getString(i), sea.number(i), wave.number(i), period.number(i), direction.number(i), water.number(i))
        }, System.currentTimeMillis())
    } finally { conn.disconnect() }
}

@Composable
fun TidesScreen() {
    var data by remember { mutableStateOf<MarineForecast?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(refresh) {
        loading = true
        try { data = fetchMarine(); error = null } catch (e: Exception) { error = e.message ?: "Sin conexión" }
        loading = false
    }
    val now = remember { LocalDateTime.now().format(hourFormat) }
    val hours = data?.hours.orEmpty()
    val nearest = hours.indexOfLast { it.time <= now }.coerceAtLeast(0)
    val current = hours.getOrNull(nearest)
    val sea = hours.mapNotNull { h -> h.sea?.let { h.time to it } }
    val turning = sea.windowed(3).mapNotNull { triple ->
        val a = triple[0].second
        val b = triple[1].second
        val c = triple[2].second
        if (b >= a && b > c) Triple(triple[1].first, b, "Pleamar aprox.")
        else if (b <= a && b < c) Triple(triple[1].first, b, "Bajamar aprox.")
        else null
    }.filter { it.first >= now }.take(8)
    LazyColumn(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            AvoCard("MAREAS · Regatón, Laredo") {
                Text("Modelo marino Open-Meteo · previsión, NO medición de mareógrafo")
                Text("Referencia: nivel medio global del mar, NO cero de carta.")
                Button(onClick = { refresh++ }, enabled = !loading) { Text(if (loading) "Actualizando…" else "Actualizar") }
                if (error != null) Text("Sin actualización: $error", color = MaterialTheme.colorScheme.error)
                if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (data != null) Text("Última consulta: " + java.text.DateFormat.getDateTimeInstance().format(java.util.Date(data!!.receivedAt)))
            }
        }
        item {
            AvoCard("Condiciones estimadas") {
                Text("Nivel marino: ${fmt(current?.sea, "m")}")
                Text("Oleaje: ${fmt(current?.wave, "m")} · periodo ${fmt(current?.period, "s")}")
                Text("Dirección oleaje: ${fmt(current?.direction, "°")}")
                Text("Temperatura superficial: ${fmt(current?.water, "°C")}")
                val before = hours.getOrNull((nearest - 1).coerceAtLeast(0))?.sea
                val after = hours.getOrNull(nearest + 1)?.sea
                if (before != null && after != null) Text(if (after > before) "Tendencia: subiendo" else if (after < before) "Tendencia: bajando" else "Tendencia: estable")
            }
        }
        if (sea.size >= 2) item {
            AvoCard("Evolución prevista · próximos 7 días") {
                val values = sea.map { it.second }
                val min = values.minOrNull() ?: 0.0
                val max = values.maxOrNull() ?: 1.0
                Canvas(Modifier.fillMaxWidth().height(170.dp)) {
                    val span = (max - min).coerceAtLeast(0.001)
                    val points = values.mapIndexed { i, v -> Offset(i.toFloat() * size.width / (values.size - 1), size.height - ((v - min) / span).toFloat() * size.height) }
                    points.zipWithNext().forEach { (a, b) -> drawLine(Color(0xFF4DB6C8), a, b, strokeWidth = 3f) }
                }
                Text("Rango del modelo: ${fmt(min, "m")} a ${fmt(max, "m")}")
            }
        }
        if (turning.isNotEmpty()) item {
            AvoCard("Próximos extremos estimados") {
                turning.forEach { (time, level, type) ->
                    Text("$type · ${time.replace('T', ' ')} · ${fmt(level, "m")}")
                }
            }
        }
        item {
            AvoCard("Precisión y uso") {
                Text("Las alturas y horas son estimaciones de un modelo oceánico de resolución aproximada de 8 km; pueden ser inexactas en playas y estuarios. No usar para navegación ni seguridad.")
                Text("Los extremos se calculan a partir de valores horarios y pueden diferir de las tablas oficiales del Instituto Hidrográfico de la Marina.")
                Text("Fuente: Open-Meteo Marine API (uso privado/no comercial).")
            }
        }
    }
}
