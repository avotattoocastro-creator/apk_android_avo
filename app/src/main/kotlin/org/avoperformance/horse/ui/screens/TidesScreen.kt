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
/** Parabolic interpolation of hourly model samples: estimated minute, not official tide-table time. */
private fun extrema(points: List<SeaPoint>): List<Extremum> = points.windowed(3).mapNotNull { triple ->
    val a = triple[0].sea ?: return@mapNotNull null
    val b = triple[1].sea ?: return@mapNotNull null
    val c = triple[2].sea ?: return@mapNotNull null
    val high = b >= a && b > c
    val low = b <= a && b < c
    if (!high && !low) return@mapNotNull null
    val denominator = a - 2 * b + c
    val shift = if (kotlin.math.abs(denominator) < 1e-9) 0.0
        else ((a - c) / (2 * denominator)).coerceIn(-0.5, 0.5)
    val interpolated = b - denominator * shift * shift / 2.0
    Extremum(triple[1].date.plusMinutes((shift * 60).roundToInt().toLong()), interpolated, high)
}
/** Official astronomical tide table for Santander, not a measurement at El Regatón. */
private data class OfficialDay(val date: LocalDate, val coefficient0: Int, val coefficient12: Int, val events: List<Extremum>)
private fun parseOfficialTable(html: String): List<OfficialDay> {
    val rows = Regex("<tr\\b[^>]*>(.*?)</tr>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE)).findAll(html)
    val dateFormat = DateTimeFormatter.ofPattern("dd/MM/yy")
    fun cellText(raw: String): String = android.text.Html.fromHtml(
        raw, android.text.Html.FROM_HTML_MODE_LEGACY
    ).toString().replace("\\s+".toRegex(), " ").trim()
    fun height(raw: String) = raw.replace(",", ".").toDoubleOrNull()
    fun event(date: LocalDate, time: String, value: String, high: Boolean): Extremum? {
        val hour = runCatching { LocalTime.parse(time, DateTimeFormatter.ofPattern("H:mm")) }.getOrNull() ?: return null
        val h = height(value) ?: return null
        return Extremum(date.atTime(hour), h, high)
    }
    return rows.mapNotNull { row ->
        val cells = Regex("<(?:td|th)\\b[^>]*>(.*?)</(?:td|th)>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
            .findAll(row.groupValues[1]).map { cellText(it.groupValues[1]) }.toList()
        val dateIndex = cells.indexOfFirst { Regex("\\d{2}/\\d{2}/\\d{2}").containsMatchIn(it) }
        if (dateIndex < 0 || cells.size - dateIndex < 11) return@mapNotNull null
        val values = cells.drop(dateIndex)
        val date = runCatching { LocalDate.parse(values[0], dateFormat) }.getOrNull() ?: return@mapNotNull null
        // Date, moon phase, high1 time/height, high2 time/height, coefficient 0h/12h, low1 time/height, low2 time/height.
        val offset = 2 // Fecha, fase lunar, pleamar mañana (hora/altura), pleamar tarde (hora/altura), coef. 0h/12h, bajamar mañana/tarde
        if (values.size < offset + 10) return@mapNotNull null
        val c0 = values[offset + 4].toIntOrNull() ?: return@mapNotNull null
        val c12 = values[offset + 5].toIntOrNull() ?: return@mapNotNull null
        val events = listOfNotNull(
            event(date, values[offset], values[offset + 1], true),
            event(date, values[offset + 2], values[offset + 3], true),
            event(date, values[offset + 6], values[offset + 7], false),
            event(date, values[offset + 8], values[offset + 9], false)
        ).sortedBy { it.date }
        if (events.size < 2 || c0 !in 0..120 || c12 !in 0..120) null else OfficialDay(date, c0, c12, events)
    }.toList().distinctBy { it.date }
}
private suspend fun fetchOfficialDays(): List<OfficialDay> = withContext(Dispatchers.IO) {
    val conn = (URL("https://www.puertosantander.es/es/tabla-de-mareas").openConnection() as HttpURLConnection).apply {
        connectTimeout = 10000; readTimeout = 10000
    }
    try {
        if (conn.responseCode !in 200..299) return@withContext emptyList()
        val html = conn.inputStream.bufferedReader().use { it.readText() }
        parseOfficialTable(html).filter { it.date >= LocalDate.now(zone).minusDays(1) && it.date <= LocalDate.now(zone).plusDays(7) }
    } finally { conn.disconnect() }
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
private fun TideGauge(points: List<SeaPoint>, now: LocalDateTime, next: Extremum?) {
    val current = points.lastOrNull { it.date <= now }?.sea
    val values = points.mapNotNull { it.sea }
    if (current == null || values.size < 3) {
        Text("Nivel del mar no disponible")
        return
    }
    val lo = values.minOrNull() ?: current
    val hi = values.maxOrNull() ?: current
    val fraction = ((current - lo) / (hi - lo).coerceAtLeast(.01)).toFloat().coerceIn(0f, 1f)
    val index = points.indexOfLast { it.date <= now }
    val before = points.getOrNull(index - 1)?.sea
    val rising = before != null && current > before
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(80.dp).height(200.dp).background(Color(0xFF142B37), RoundedCornerShape(12.dp))) {
            Box(Modifier.fillMaxWidth().fillMaxHeight(fraction).align(Alignment.BottomCenter)
                .background(if (rising) Color(0xFF197D64) else Color(0xFF237DAD), RoundedCornerShape(10.dp)))
            Text(if (rising) "↑" else "↓", color = Color.White,
                style = MaterialTheme.typography.headlineLarge, modifier = Modifier.align(Alignment.Center))
        }
        Spacer(Modifier.width(18.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (rising) "SUBIENDO ↑" else "BAJANDO ↓", color = aqua, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text("Nivel estimado: ${current.show("m", 2)}", style = MaterialTheme.typography.titleLarge)
            Text("Rango previsto: ${lo.show("m", 2)} / ${hi.show("m", 2)}")
            if (next != null) {
                val remaining = Duration.between(now, next.date).toMinutes().coerceAtLeast(0)
                Text("Próxima ${if (next.high) "pleamar" else "bajamar"}: ${next.date.format(fmtHour)}", fontWeight = FontWeight.Bold)
                Text("Faltan ${remaining / 60} h ${remaining % 60} min", color = gold)
            }
        }
    }
    Text("Escala relativa al rango del modelo, NO altura oficial sobre cero de carta.", style = MaterialTheme.typography.labelSmall)
}
@Composable
private fun TideEventRow(e: Extremum, coefficient0: Int? = null, coefficient12: Int? = null) {
    val high = e.high
    val shade = if (high) Color(0xFF713C43) else Color(0xFF27654F)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 2.dp)
            .background(shade, RoundedCornerShape(6.dp))
            .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(if (high) "▲ PLEAMAR" else "▼ BAJAMAR",
            modifier = Modifier.weight(1f), color = Color.White,
            style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
        Text(e.date.format(fmtHour), color = Color.White, fontWeight = FontWeight.Bold,
            modifier = Modifier.width(64.dp))
        Text(e.height.show("m", 2), color = Color.White, modifier = Modifier.width(68.dp))
        val coefficient = if (e.date.hour < 12) coefficient0 else coefficient12
        Column(Modifier.width(55.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (coefficient != null) {
                Text("COEF.", color = Color.White, style = MaterialTheme.typography.labelSmall)
                Text(coefficient.toString(), color = Color(0xFFFFE16B), fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            } else {
                Text("—", color = Color.LightGray, style = MaterialTheme.typography.labelMedium)
            }
        }
        /* Wave graphic intentionally replaced by a readable per-event coefficient.
        Canvas(Modifier.width(45.dp).height(26.dp)) {
            val p = Path()
            for (i in 0..32) {
                val x = size.width * i / 32f
                val t = i / 32f
                val y = if (high) size.height * (0.74f - 0.55f * kotlin.math.sin(t * Math.PI).toFloat())
                    else size.height * (0.25f + 0.55f * kotlin.math.sin(t * Math.PI).toFloat())
                if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
            }
            drawPath(p, Color(0xFF76D7F4), style = Stroke(width = 3f))
        } */
    }
}
@Composable
private fun MultiDayTable(extremes: List<Extremum>, firstDay: LocalDate, numberOfDays: Int = 7, coefficient0: Int? = null, coefficient12: Int? = null) {
    (0 until numberOfDays).forEach { offset ->
        val date = firstDay.plusDays(offset.toLong())
        val rows = extremes.filter { it.date.toLocalDate() == date }.sortedBy { it.date }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 5.dp),
            horizontalArrangement = Arrangement.SpaceBetween) {
            Text(date.format(DateTimeFormatter.ofPattern("EEEE d MMMM", es))
                .replaceFirstChar { it.uppercase() }, color = gold, fontWeight = FontWeight.Bold)
            Text(moonPhase(date), style = MaterialTheme.typography.labelSmall, color = aqua)
        }
        if (rows.isEmpty()) Text("Sin predicción disponible", style = MaterialTheme.typography.bodySmall)
        rows.forEach { TideEventRow(it, coefficient0, coefficient12) }
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
    var official by remember { mutableStateOf<List<OfficialDay>>(emptyList()) }
    var refresh by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var tab by remember { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf(LocalDate.now(zone)) }
    var now by remember { mutableStateOf(LocalDateTime.now(zone)) }
    LaunchedEffect(Unit) { while (true) { now = LocalDateTime.now(zone); delay(60000) } }
    LaunchedEffect(refresh) {
        loading = true
        try { data = fetchTides(); error = null } catch (e: Exception) { error = e.message ?: "No se pudo actualizar" }
        official = runCatching { fetchOfficialDays() }.getOrDefault(emptyList())
        loading = false
    }
    val all = data?.sea.orEmpty()
    val day = all.filter { it.date.toLocalDate() == selected }
    val officialToday = official.firstOrNull { it.date == now.toLocalDate() }
    val officialWeek = official.filter { it.date >= now.toLocalDate() && it.date < now.toLocalDate().plusDays(7) }
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
        if (!loading && official.isEmpty()) Text("Tabla oficial de Santander no disponible para estas fechas. Se muestran solo estimaciones del modelo.", color = gold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (tab == 0) {
                item {
                    AvoCard("ESTADO DE LA MAREA · MODELO") {
                        TideGauge(day, now, next)
                        Text(now.format(DateTimeFormatter.ofPattern("EEEE d 'de' MMMM · HH:mm", es))
                            .replaceFirstChar { it.uppercase() })
                        Text(officialToday?.let { "Coef. Santander 0h/12h: ${it.coefficient0} / ${it.coefficient12}" } ?: "Coeficiente oficial: no disponible", color = gold, style = MaterialTheme.typography.titleMedium)
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
                        val today = (officialToday?.events ?: ex).filter { it.date.toLocalDate() == selected }
                        if (today.isEmpty()) Text("Sin extremos disponibles")
                        today.forEach { e -> TideEventRow(e) }
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
                    AvoCard("CALENDARIO DE MAREAS · 7 DÍAS") {
                        Text(if (officialWeek.isNotEmpty()) "Santander: predicción astronómica oficial, alturas sobre el cero del puerto." else "Predicciones del modelo; altura respecto al nivel medio.", style = MaterialTheme.typography.bodySmall)
                        if (officialWeek.isNotEmpty()) {
                            Text("Coeficiente en cada fila: referencia oficial de las 0 h o 12 h, no medición exacta del instante de marea.", color = gold)
                            (0 until 7).forEach { offset ->
                                val date = LocalDate.now(zone).plusDays(offset.toLong())
                                val entry = officialWeek.firstOrNull { it.date == date }
                                if (entry != null) {
                                    Text("Coef. oficial 0h/12h: " + entry.coefficient0 + " / " + entry.coefficient12, color = gold)
                                    MultiDayTable(entry.events, date, 1, entry.coefficient0, entry.coefficient12)
                                } else {
                                    Text("Santander sin datos oficiales para $date · modelo MSL", color = gold)
                                    MultiDayTable(ex, date, 1)
                                }
                            }
                        } else {
                            Text("Coeficiente oficial no disponible", color = gold)
                            MultiDayTable(ex, LocalDate.now(zone))
                        }
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
                    Text("Fuentes: Open-Meteo Marine/Weather (modelo) y, cuando esté disponible, tabla astronómica de la Autoridad Portuaria de Santander. Santander es una referencia regional, NO una medición en El Regatón.", style = MaterialTheme.typography.bodySmall)
                    Text("Los extremos del modelo se interpolan a minutos, pero no equivalen a una tabla oficial. Las alturas de Santander se refieren al cero del puerto; las del modelo, al nivel medio. No mezclar referencias ni utilizar para navegación.", style = MaterialTheme.typography.bodySmall)
                    data?.let { Text("Actualizado: ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it.fetched))}", style = MaterialTheme.typography.labelSmall) }
                }
            }
        }
    }
}

/** Explicit opt-in snapshot: forecast model values, never labeled as measured tide. */
suspend fun marineSnapshotForTraining(sessionId: String, timestampMs: Long): org.avoperformance.horse.data.TrainingMarineEntity {
    val forecast = fetchTides()
    val officialDay = runCatching { fetchOfficialDays().firstOrNull { it.date == java.time.Instant.ofEpochMilli(timestampMs).atZone(zone).toLocalDate() } }.getOrNull()
    val at = java.time.Instant.ofEpochMilli(timestampMs).atZone(zone).toLocalDateTime()
    val point = forecast.sea.minByOrNull { kotlin.math.abs(java.time.Duration.between(it.date, at).toMinutes()) }
        ?: error("No hay previsión marina disponible")
    val delta = kotlin.math.abs(java.time.Duration.between(point.date, at).toHours())
    require(delta <= 2) { "El entrenamiento está fuera de los 7 días de previsión. No se inventarán datos históricos." }
    val w = forecast.weather.minByOrNull { kotlin.math.abs(java.time.Duration.between(it.date, at).toMinutes()) }
    val previous = forecast.sea.getOrNull(forecast.sea.indexOf(point) - 1)?.sea
    val trend = if (point.sea == null || previous == null) "DESCONOCIDA"
        else if (point.sea > previous) "SUBIENDO" else if (point.sea < previous) "BAJANDO" else "ESTABLE"
    return org.avoperformance.horse.data.TrainingMarineEntity(
        sessionId = sessionId, location = "El Regatón, Laredo",
        sampleMs = point.date.atZone(zone).toInstant().toEpochMilli(),
        source = "Open-Meteo Marine/Weather · modelo, no medición",
        levelMsl = point.sea, waveM = point.wave, wavePeriodS = point.period,
        waterC = point.temp, windKmh = w?.wind, gustKmh = w?.gust, tideTrend = trend,
        tideCoefficient = officialDay?.let { if (at.hour < 12) it.coefficient0 else it.coefficient12 },
        coefficientSource = if (officialDay != null) "Puerto de Santander · predicción astronómica, referencia Santander" else null
    )
}
