package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.avoperformance.horse.ui.components.AvoCard
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.roundToInt

private val zone = ZoneId.of("Europe/Madrid")
private val gold = Color(0xFFD3A72C)
private val aqua = Color(0xFF54C6DC)
private val fmtHour = DateTimeFormatter.ofPattern("HH:mm")
private val fmtIso = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
private val es = Locale("es", "ES")
private data class SeaPoint(val date: LocalDateTime, val sea: Double?, val wave: Double?, val period: Double?, val direction: Double?, val temp: Double?)
private data class WeatherPoint(val date: LocalDateTime, val wind: Double?, val gust: Double?, val direction: Double?, val air: Double?, val rain: Double?)
private data class TideData(val sea: List<SeaPoint>, val weather: List<WeatherPoint>, val fetched: Long)
private data class Extremum(val date: LocalDateTime, val height: Double, val high: Boolean)
private fun org.json.JSONArray?.num(i: Int): Double? = this?.optDouble(i, Double.NaN)?.takeIf { it.isFinite() }
private fun Double?.show(unit: String, digits: Int = 1): String = if (this == null) "—" else "%.${digits}f %s".format(es, this, unit)
private fun loadJson(url: String): JSONObject {
    val conn = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 12000; readTimeout = 12000
    }
    return try {
        if (conn.responseCode !in 200..299) error("HTTP ${conn.responseCode}")
        JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
    } finally { conn.disconnect() }
}
private suspend fun fetchTides(): TideData = withContext(Dispatchers.IO) {
    val marine = loadJson("https://marine-api.open-meteo.com/v1/marine?latitude=43.397&longitude=-3.426&hourly=sea_level_height_msl,wave_height,wave_period,wave_direction,sea_surface_temperature&timezone=Europe%2FMadrid&forecast_days=7&cell_selection=sea")
    val m = marine.getJSONObject("hourly")
    val mt = m.getJSONArray("time")
    val sea = (0 until mt.length()).map { i ->
        SeaPoint(LocalDateTime.parse(mt.getString(i), fmtIso), m.optJSONArray("sea_level_height_msl").num(i), m.optJSONArray("wave_height").num(i), m.optJSONArray("wave_period").num(i), m.optJSONArray("wave_direction").num(i), m.optJSONArray("sea_surface_temperature").num(i))
    }
    val weather = try {
        val j = loadJson("https://api.open-meteo.com/v1/forecast?latitude=43.397&longitude=-3.426&hourly=wind_speed_10m,wind_gusts_10m,wind_direction_10m,temperature_2m,precipitation&timezone=Europe%2FMadrid&forecast_days=7")
        val w = j.getJSONObject("hourly"); val wt = w.getJSONArray("time")
        (0 until wt.length()).map { i ->
            WeatherPoint(LocalDateTime.parse(wt.getString(i), fmtIso), w.optJSONArray("wind_speed_10m").num(i), w.optJSONArray("wind_gusts_10m").num(i), w.optJSONArray("wind_direction_10m").num(i), w.optJSONArray("temperature_2m").num(i), w.optJSONArray("precipitation").num(i))
        }
    } catch (_: Exception) { emptyList() }
    TideData(sea, weather, System.currentTimeMillis())
}
private fun extrema(points: List<SeaPoint>): List<Extremum> = points.windowed(3).mapNotNull { triple ->
    val a = triple[0].sea ?: return@mapNotNull null
    val b = triple[1].sea ?: return@mapNotNull null
    val c = triple[2].sea ?: return@mapNotNull null
    when {
        b >= a && b > c -> Extremum(triple[1].date, b, true)
        b <= a && b < c -> Extremum(triple[1].date, b, false)
        else -> null
    }
}
private fun moonPhase(date: LocalDate): String {
    val days = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.of(2000, 1, 6), date).toDouble()
    val age = ((days % 29.530588853) + 29.530588853) % 29.530588853
    return when {
        age < 1.85 -> "Luna nueva"
        age < 7.38 -> "Creciente"
        age < 9.22 -> "Cuarto creciente"
        age < 14.77 -> "Gibosa creciente"
        age < 16.61 -> "Luna llena"
        age < 22.15 -> "Gibosa menguante"
        age < 23.99 -> "Cuarto menguante"
        else -> "Menguante"
    }
}
@Composable
private fun TideCurve(points: List<SeaPoint>, now: LocalDateTime, modifier: Modifier = Modifier) {
    val valid = points.mapIndexedNotNull { i, p -> p.sea?.let { i to it } }
    if (valid.size < 2) { Box(modifier.height(180.dp), contentAlignment = Alignment.Center) { Text("Curva no disponible") }; return }
    val lo = valid.minOf { it.second }; val hi = valid.maxOf { it.second }
    Column(modifier) {
        Canvas(Modifier.fillMaxWidth().height(190.dp)) {
            val top = 18f; val bottom = size.height - 18f
            val range = (hi - lo).coerceAtLeast(.01)
            fun x(i: Int) = size.width * i / (points.size - 1).coerceAtLeast(1)
            fun y(v: Double) = bottom - ((v - lo) / range).toFloat() * (bottom - top)
            for (k in 0..4) {
                val yy = top + (bottom - top) * k / 4f
                drawLine(Color.White.copy(alpha = .10f), Offset(0f, yy), Offset(size.width, yy), 1f)
            }
            val path = Path()
            valid.forEachIndexed { n, pair ->
                if (n == 0) path.moveTo(x(pair.first), y(pair.second)) else path.lineTo(x(pair.first), y(pair.second))
            }
            drawPath(path, aqua, style = Stroke(width = 4f))
            val index = points.indexOfLast { it.date <= now }
            if (index in points.indices) {
                val xx = x(index)
                drawLine(gold, Offset(xx, 0f), Offset(xx, size.height), 2f)
                points[index].sea?.let { drawCircle(gold, 6f, Offset(xx, y(it))) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(points.first().date.format(fmtHour), style = MaterialTheme.typography.labelSmall)
            Text("AHORA", color = gold, style = MaterialTheme.typography.labelSmall)
            Text(points.last().date.format(fmtHour), style = MaterialTheme.typography.labelSmall)
        }
    }
}
@Composable
private fun Metric(title: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier.padding(vertical = 5.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = Color.LightGray)
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    }
}
@Composable
fun TidesScreen() {
    var data by remember { mutableStateOf<TideData?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var tab by remember { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf(LocalDate.now(zone)) }
    var now by remember { mutableStateOf(LocalDateTime.now(zone)) }
    LaunchedEffect(Unit) { while (true) { now = LocalDateTime.now(zone); delay(60000) } }
    LaunchedEffect(refresh) {
        loading = true
        try { data = fetchTides(); error = null } catch (e: Exception) { error = e.message ?: "No se pudo actualizar" }
        loading = false
    }
    val all = data?.sea.orEmpty()
    val day = all.filter { it.date.toLocalDate() == selected }
    val ex = extrema(all)
    val next = ex.firstOrNull { it.date > now }
    val current = all.lastOrNull { it.date <= now }
    val weather = data?.weather?.lastOrNull { it.date <= now }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text("EL REGATÓN", color = gold, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Laredo · Cantabria", style = MaterialTheme.typography.bodySmall)
            }
            TextButton(onClick = { refresh++ }, enabled = !loading) { Text(if (loading) "Cargando…" else "↻ Actualizar") }
        }
        TabRow(selectedTabIndex = tab) {
            listOf("Hoy", "Calendario", "Condiciones").forEachIndexed { i, label ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(label) })
            }
        }
        if (error != null) Text("Sin actualización: $error", color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(12.dp))
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (tab == 0) {
                item {
                    AvoCard("ESTADO DE LA MAREA · MODELO") {
                        val before = all.getOrNull((all.indexOf(current) - 1).coerceAtLeast(0))?.sea
                        val trend = if (current?.sea != null && before != null && current.sea > before) "SUBIENDO ↑" else if (current?.sea != null && before != null && current.sea < before) "BAJANDO ↓" else "SIN TENDENCIA"
                        Text(trend, color = aqua, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                        Text(now.format(DateTimeFormatter.ofPattern("EEEE d 'de' MMMM · HH:mm", es)).replaceFirstChar { it.uppercase() })
                        if (next != null) {
                            val remaining = Duration.between(now, next.date).toMinutes().coerceAtLeast(0)
                            Text("Próxima ${if (next.high) "pleamar" else "bajamar"} · ${next.date.format(fmtHour)}", fontWeight = FontWeight.Bold)
                            Text("Faltan ${remaining / 60} h ${remaining % 60} min", color = gold, style = MaterialTheme.typography.titleLarge)
                        }
                        Text("Nivel previsto respecto al nivel medio: ${current?.sea.show("m", 2)}", style = MaterialTheme.typography.bodySmall)
                    }
                }
                item {
                    AvoCard("CURVA DE MAREA · HOY") {
                        TideCurve(day, now, Modifier.fillMaxWidth())
                        Text("Previsión horaria del modelo; alturas relativas al nivel medio, no al cero de carta.", style = MaterialTheme.typography.labelSmall)
                    }
                }
                item {
                    AvoCard("PLEAMARES Y BAJAMARES") {
                        val today = ex.filter { it.date.toLocalDate() == selected }
                        if (today.isEmpty()) Text("Sin extremos disponibles")
                        today.forEach { e ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(if (e.high) "▲ Pleamar" else "▼ Bajamar", color = if (e.high) aqua else gold)
                                Text(e.date.format(fmtHour), fontWeight = FontWeight.Bold)
                                Text(e.height.show("m", 2))
                            }
                        }
                    }
                }
                item {
                    AvoCard("VISTAZO AL MAR") {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Metric("Olas", current?.wave.show("m"))
                            Metric("Período", current?.period.show("s"))
                            Metric("Agua", current?.temp.show("°C"))
                        }
                    }
                }
            } else if (tab == 1) {
                item {
                    AvoCard("SELECCIONA UN DÍA") {
                        Text(selected.format(DateTimeFormatter.ofPattern("EEEE d 'de' MMMM", es)).replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.titleLarge)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            TextButton(onClick = { selected = selected.minusDays(1) }, enabled = selected > LocalDate.now(zone)) { Text("‹ Anterior") }
                            TextButton(onClick = { selected = LocalDate.now(zone) }) { Text("Hoy") }
                            TextButton(onClick = { selected = selected.plusDays(1) }, enabled = selected < LocalDate.now(zone).plusDays(6)) { Text("Siguiente ›") }
                        }
                        Text("Fase lunar aproximada: ${moonPhase(selected)}")
                    }
                }
                item { AvoCard("CURVA DEL DÍA") { TideCurve(day, now, Modifier.fillMaxWidth()) } }
                item {
                    AvoCard("TABLA DEL DÍA") {
                        val selectedEx = ex.filter { it.date.toLocalDate() == selected }
                        selectedEx.forEach { e ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(if (e.high) "Pleamar ▲" else "Bajamar ▼")
                                Text(e.date.format(fmtHour), fontWeight = FontWeight.Bold)
                                Text(e.height.show("m", 2))
                            }
                        }
                        if (selectedEx.isEmpty()) Text("No hay extremos calculados para este día")
                    }
                }
            } else {
                item {
                    AvoCard("OLEAJE") {
                        Metric("Altura de ola", current?.wave.show("m"))
                        Metric("Período", current?.period.show("s"))
                        Metric("Dirección", current?.direction.show("°", 0))
                        Metric("Temperatura del agua", current?.temp.show("°C"))
                    }
                }
                item {
                    AvoCard("VIENTO Y METEOROLOGÍA") {
                        Metric("Viento", weather?.wind.show("km/h"))
                        Metric("Rachas", weather?.gust.show("km/h"))
                        Metric("Dirección", weather?.direction.show("°", 0))
                        Metric("Temperatura ambiente", weather?.air.show("°C"))
                        Metric("Precipitación horaria", weather?.rain.show("mm"))
                    }
                }
            }
            item {
                AvoCard("DATOS Y PRECISIÓN") {
                    Text("Fuentes: Open-Meteo Marine y Open-Meteo Weather. Datos previstos/modelados, NO mareógrafo en directo ni tabla oficial IHM.", style = MaterialTheme.typography.bodySmall)
                    Text("Extremos aproximados calculados con muestras horarias. Modelo oceánico de resolución limitada en estuarios. No usar para navegación ni seguridad.", style = MaterialTheme.typography.bodySmall)
                    data?.let { Text("Actualizado: ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it.fetched))}", style = MaterialTheme.typography.labelSmall) }
                }
            }
        }
    }
}
