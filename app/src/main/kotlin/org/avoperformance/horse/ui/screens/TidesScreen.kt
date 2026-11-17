package org.avoperformance.horse.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.tide.Astro
import org.avoperformance.horse.core.tide.MoonPhase
import org.avoperformance.horse.core.tide.TideExtreme
import org.avoperformance.horse.core.tide.TideMath
import org.avoperformance.horse.data.Settings
import org.avoperformance.horse.data.TrainingMarineEntity
import org.avoperformance.horse.tide.Forecast
import org.avoperformance.horse.tide.TidePort
import org.avoperformance.horse.tide.TideRepository
import org.avoperformance.horse.ui.components.AvoCard
import org.avoperformance.horse.ui.components.MetricTile
import org.avoperformance.horse.ui.theme.AvoColors
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

private val es = Locale.forLanguageTag("es-ES")
private val zone: ZoneId get() = ZoneId.systemDefault()
private val hm = DateTimeFormatter.ofPattern("HH:mm")
private val sea = Color(0xFF3D9BFF)
private val seaDeep = Color(0xFF0E3F78)
private fun Long.local(): LocalDateTime = Instant.ofEpochMilli(this).atZone(zone).toLocalDateTime()
private fun Long.hhmm(): String = local().format(hm)
private fun m2(v: Double?): String = v?.let { String.format(es, "%.2f", it) } ?: "—"
private fun dayStart(d: LocalDate): Long = d.atStartOfDay(zone).toInstant().toEpochMilli()

fun moonEmoji(p: MoonPhase) = when (p) {
    MoonPhase.NEW -> "🌑"; MoonPhase.WAXING_CRESCENT -> "🌒"; MoonPhase.FIRST_QUARTER -> "🌓"; MoonPhase.WAXING_GIBBOUS -> "🌔"
    MoonPhase.FULL -> "🌕"; MoonPhase.WANING_GIBBOUS -> "🌖"; MoonPhase.LAST_QUARTER -> "🌗"; MoonPhase.WANING_CRESCENT -> "🌘"
}

fun weatherEmoji(code: Int?, night: Boolean = false) = when (code) {
    null -> "·"; 0 -> if (night) "🌙" else "☀️"; 1, 2 -> if (night) "☁️" else "⛅"; 3 -> "☁️"; 45, 48 -> "🌫️"
    in 51..67, in 80..82 -> "🌧️"; in 71..77, 85, 86 -> "🌨️"; in 95..99 -> "⛈️"; else -> "·"
}

private fun coefColor(c: Int?) = when {
    c == null -> AvoColors.Unknown; c >= 95 -> AvoColors.Red; c >= 70 -> AvoColors.RedLight; c >= 45 -> AvoColors.Blue; else -> AvoColors.Silver
}

@Composable
fun TidesScreen(c: AppContainer) {
    val repo = c.tides
    var ports by remember { mutableStateOf<List<TidePort>>(emptyList()) }
    var port by remember { mutableStateOf<TidePort?>(null) }
    var ext by remember { mutableStateOf<List<TideExtreme>>(emptyList()) }
    var fc by remember { mutableStateOf<Forecast?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var refresh by remember { mutableIntStateOf(0) }
    var choosePort by remember { mutableStateOf(false) }
    val today = remember { LocalDate.now(zone) }
    var selected by remember { mutableStateOf(today) }
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); nowMs = System.currentTimeMillis() } }
    val lat = c.settings.spotLat; val lon = c.settings.spotLon

    LaunchedEffect(refresh) {
        loading = true; error = null
        try {
            ports = repo.portsNear(lat, lon)
            port = ports.firstOrNull { it.id == c.settings.tidePortId } ?: ports.firstOrNull()
            val p = port ?: error("Lista de puertos del IHM no disponible")
            ext = repo.extremes(p.id, dayStart(today.minusDays(1)), dayStart(today.plusDays(15)))
        } catch (e: Exception) { error = e.message ?: "Sin conexión" }
        fc = runCatching { repo.forecast(lat, lon) }.getOrNull() ?: fc
        loading = false
    }

    val days = (0 until 14).map { today.plusDays(it.toLong()) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
        item {
            Row(Modifier.fillMaxWidth().clickable { choosePort = true }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(c.settings.spotName.uppercase(), color = AvoColors.Text, fontSize = 20.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                    Text(port?.let { "Puerto de referencia: ${it.name} · ${String.format(es, "%.0f", it.distKm)} km  ▾" } ?: "Elegir puerto  ▾", color = AvoColors.TextDim, fontSize = 13.sp)
                }
                IconButton(onClick = { refresh++ }, enabled = !loading) { Text("↻", color = AvoColors.Silver, fontSize = 22.sp) }
            }
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = AvoColors.Red, trackColor = AvoColors.Surface2)
            error?.let { Text(it, color = AvoColors.Warn, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp), fontSize = 13.sp) }
        }
        item { DayStrip(days, selected, ext) { selected = it } }
        if (selected == today && ext.isNotEmpty()) item { NowCard(ext, nowMs) }
        item {
            AvoCard(selected.format(DateTimeFormatter.ofPattern("EEEE d 'de' MMMM", es))) {
                TideChart(ext, selected, nowMs, lat, lon)
            }
        }
        item { ExtremesCard(ext, selected) }
        item { SunMoonCard(selected, lat, lon) }
        fc?.let { f -> item { WeatherCard(f, selected, nowMs, lat, lon) } }
        item {
            Text("IHM · Instituto Hidrográfico de la Marina · Open-Meteo", color = AvoColors.TextDim, fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
    if (choosePort) PortDialog(ports, port, onDismiss = { choosePort = false }) { p ->
        c.settings.tidePortId = p.id; choosePort = false; refresh++
    }
}

@Composable
private fun DayStrip(days: List<LocalDate>, selected: LocalDate, ext: List<TideExtreme>, onPick: (LocalDate) -> Unit) {
    val state = rememberLazyListState()
    LazyRow(state = state, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(days) { d ->
            val on = d == selected
            val start = dayStart(d)
            val coef = ext.filter { it.tMs in start until start + 86_400_000 }.mapNotNull { it.coefficient }.maxOrNull()
            val moon = Astro.moon(start + 43_200_000)
            val shape = RoundedCornerShape(14.dp)
            Column(
                Modifier.width(62.dp).clip(shape).background(if (on) AvoColors.Red else AvoColors.Surface)
                    .border(1.dp, if (on) AvoColors.Red else AvoColors.Line, shape).clickable { onPick(d) }.padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(d.format(DateTimeFormatter.ofPattern("EEE", es)).uppercase().take(3), color = if (on) Color.White else AvoColors.TextDim, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Text(d.dayOfMonth.toString(), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black)
                Text(moonEmoji(moon.phase), fontSize = 13.sp)
                Text(coef?.toString() ?: "—", color = if (on) Color.White else coefColor(coef), fontSize = 13.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun NowCard(ext: List<TideExtreme>, nowMs: Long) {
    val level = TideMath.levelAt(ext, nowMs) ?: return
    val frac = (TideMath.fraction(ext, nowMs) ?: 0.5).toFloat()
    val next = ext.firstOrNull { it.tMs > nowMs }
    val coef = TideMath.coefficientAt(ext, nowMs)
    AvoCard("Ahora") {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 56.dp, height = 132.dp).clip(RoundedCornerShape(28.dp)).background(AvoColors.Surface2).border(1.dp, AvoColors.Line, RoundedCornerShape(28.dp))) {
                Box(Modifier.fillMaxWidth().fillMaxHeight(frac.coerceIn(0.04f, 1f)).align(Alignment.BottomCenter)
                    .background(Brush.verticalGradient(listOf(sea, seaDeep))))
                Text(if (level.rising) "▲" else "▼", color = Color.White, fontSize = 22.sp, modifier = Modifier.align(Alignment.Center))
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(m2(level.heightM), color = AvoColors.Text, fontSize = 40.sp, fontWeight = FontWeight.Black)
                    Text(" m", color = AvoColors.TextDim, fontSize = 16.sp, modifier = Modifier.padding(bottom = 7.dp))
                }
                Text(if (level.rising) "SUBIENDO" else "BAJANDO", color = sea, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp)
                next?.let {
                    val mins = ((it.tMs - nowMs) / 60_000).coerceAtLeast(0)
                    Spacer(Modifier.height(6.dp))
                    Text("${if (it.high) "Pleamar" else "Bajamar"} ${it.tMs.hhmm()} · ${m2(it.heightM)} m", color = AvoColors.Text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Text("en ${mins / 60} h ${mins % 60} min", color = AvoColors.RedLight, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }
            }
            CoefRing(coef)
        }
    }
}

@Composable
private fun CoefRing(coef: Int?) {
    val col = coefColor(coef)
    Box(Modifier.size(86.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val st = 7.dp.toPx()
            drawArc(AvoColors.Surface2, 135f, 270f, false, style = Stroke(st, cap = StrokeCap.Round), topLeft = Offset(st / 2, st / 2), size = Size(size.width - st, size.height - st))
            val sweep = 270f * (((coef ?: 20) - 20) / 100f).coerceIn(0f, 1f)
            if (coef != null) drawArc(col, 135f, sweep, false, style = Stroke(st, cap = StrokeCap.Round), topLeft = Offset(st / 2, st / 2), size = Size(size.width - st, size.height - st))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(coef?.toString() ?: "—", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black)
            Text("COEF.", color = AvoColors.TextDim, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        }
    }
}

/** Day curve from official extremes; night shaded; drag to read the level at any minute. */
@Composable
private fun TideChart(ext: List<TideExtreme>, day: LocalDate, nowMs: Long, lat: Double, lon: Double) {
    val start = dayStart(day); val end = start + 86_400_000
    val pts = remember(ext, day) { TideMath.curve(ext, start, end, 5 * 60_000L) }
    if (pts.size < 2) { Text("Sin predicción para este día", color = AvoColors.TextDim); return }
    val dayExt = ext.filter { it.tMs in start until end }
    val sun = remember(day) { Astro.sun(start + 43_200_000, lat, lon) }
    val lo = minOf(pts.minOf { it.second }, 0.0); val hi = pts.maxOf { it.second } + 0.4
    var scrub by remember(day) { mutableStateOf<Long?>(null) }
    val shown = scrub ?: nowMs.takeIf { it in start until end }
    shown?.let { t ->
        val lv = TideMath.levelAt(ext, t)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(t.hhmm(), color = AvoColors.RedLight, fontSize = 18.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.width(10.dp))
            Text("${m2(lv?.heightM)} m", color = AvoColors.Text, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(8.dp))
            Text(if (lv?.rising == true) "subiendo" else "bajando", color = AvoColors.TextDim, fontSize = 13.sp, modifier = Modifier.padding(bottom = 2.dp))
        }
    }
    Canvas(
        Modifier.fillMaxWidth().height(210.dp).padding(top = 6.dp)
            .pointerInput(day) { detectTapGestures { o -> scrub = start + (o.x / size.width * 86_400_000).toLong() } }
            .pointerInput(day) { detectDragGestures(onDragEnd = {}) { ch, _ -> scrub = start + (ch.position.x.coerceIn(0f, size.width.toFloat()) / size.width * 86_400_000).toLong() } }
    ) {
        val top = 22f; val bottom = size.height - 22f
        fun x(t: Long) = ((t - start).toFloat() / 86_400_000f) * size.width
        fun y(h: Double) = (bottom - ((h - lo) / (hi - lo)).toFloat() * (bottom - top))
        // night
        val night = Color(0xFF06070B)
        sun.riseMs?.let { drawRect(night, Offset(0f, 0f), Size(x(it).coerceIn(0f, size.width), size.height)) }
        sun.setMs?.let { val xs = x(it).coerceIn(0f, size.width); drawRect(night, Offset(xs, 0f), Size(size.width - xs, size.height)) }
        for (h in 0..24 step 3) { val xx = size.width * h / 24f; drawLine(AvoColors.Line, Offset(xx, top), Offset(xx, bottom), 1f) }
        val path = Path(); val area = Path()
        pts.forEachIndexed { i, (t, h) -> if (i == 0) { path.moveTo(x(t), y(h)); area.moveTo(x(t), bottom) ; area.lineTo(x(t), y(h)) } else { path.lineTo(x(t), y(h)); area.lineTo(x(t), y(h)) } }
        area.lineTo(x(pts.last().first), bottom); area.close()
        drawPath(area, Brush.verticalGradient(listOf(sea.copy(alpha = 0.55f), seaDeep.copy(alpha = 0.15f)), top, bottom))
        drawPath(path, sea, style = Stroke(5f, cap = StrokeCap.Round))
        dayExt.forEach { e ->
            val p = Offset(x(e.tMs), y(e.heightM))
            drawCircle(Color.White, 7f, p); drawCircle(if (e.high) AvoColors.Red else sea, 4.5f, p)
        }
        if (nowMs in start until end) {
            val xx = x(nowMs)
            drawLine(AvoColors.Red.copy(alpha = 0.8f), Offset(xx, top - 10), Offset(xx, bottom), 3f)
        }
        scrub?.let { t ->
            val xx = x(t)
            drawLine(Color.White.copy(alpha = 0.7f), Offset(xx, top - 10), Offset(xx, bottom), 2f)
            TideMath.levelAt(ext, t)?.let { drawCircle(Color.White, 8f, Offset(xx, y(it.heightM))) }
        }
    }
    Row(Modifier.fillMaxWidth()) {
        listOf("0", "3", "6", "9", "12", "15", "18", "21", "24").forEachIndexed { i, s ->
            Text(s, color = AvoColors.TextDim, fontSize = 10.sp, modifier = Modifier.weight(1f), textAlign = if (i == 0) androidx.compose.ui.text.style.TextAlign.Start else if (i == 8) androidx.compose.ui.text.style.TextAlign.End else androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

@Composable
private fun ExtremesCard(ext: List<TideExtreme>, day: LocalDate) {
    val start = dayStart(day)
    val list = ext.filter { it.tMs in start until start + 86_400_000 }
    AvoCard("Pleamares y bajamares") {
        if (list.isEmpty()) Text("—", color = AvoColors.TextDim)
        list.forEach { e ->
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(12.dp)).background(AvoColors.Surface2).padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(30.dp).background(if (e.high) AvoColors.Red else sea, CircleShape), contentAlignment = Alignment.Center) {
                    Text(if (e.high) "▲" else "▼", color = Color.White, fontSize = 13.sp)
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (e.high) "PLEAMAR" else "BAJAMAR", color = AvoColors.TextDim, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                    Text(e.tMs.hhmm(), color = AvoColors.Text, fontSize = 22.sp, fontWeight = FontWeight.Black)
                }
                Text("${m2(e.heightM)} m", color = AvoColors.Text, fontSize = 17.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(78.dp))
                Column(Modifier.width(48.dp), horizontalAlignment = Alignment.End) {
                    if (e.coefficient != null) {
                        Text(e.coefficient.toString(), color = coefColor(e.coefficient), fontSize = 20.sp, fontWeight = FontWeight.Black)
                        Text("COEF.", color = AvoColors.TextDim, fontSize = 9.sp)
                    }
                }
            }
        }
        val c = list.mapNotNull { it.coefficient }.maxOrNull()
        if (c != null) Text(TideMath.coefficientLabel(c), color = coefColor(c), fontSize = 13.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun SunMoonCard(day: LocalDate, lat: Double, lon: Double) {
    val start = dayStart(day)
    val sun = remember(day) { Astro.sun(start + 43_200_000, lat, lon) }
    val moon = remember(day) { Astro.moon(start + 43_200_000) }
    val (mr, ms) = remember(day) { Astro.moonRiseSet(start, lat, lon) }
    AvoCard("Sol y luna") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricTile("Salida sol", sun.riseMs?.hhmm(), "", Modifier.weight(1f), AvoColors.Warn, "☀")
            MetricTile("Puesta sol", sun.setMs?.hhmm(), "", Modifier.weight(1f), AvoColors.RedLight)
            val len = if (sun.riseMs != null && sun.setMs != null) (sun.setMs!! - sun.riseMs!!) / 60_000 else null
            MetricTile("Horas de luz", len?.let { "${it / 60}h ${it % 60}m" }, "", Modifier.weight(1f))
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricTile("Amanecer", sun.dawnMs?.hhmm(), "", Modifier.weight(1f))
            MetricTile("Anochecer", sun.duskMs?.hhmm(), "", Modifier.weight(1f))
            MetricTile("Mediodía", sun.noonMs.hhmm(), "", Modifier.weight(1f))
        }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(moonEmoji(moon.phase), fontSize = 40.sp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(moon.phase.label, color = AvoColors.Text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Text("Iluminación ${moon.illumination} % · ${String.format(es, "%.1f", moon.ageDays)} días", color = AvoColors.TextDim, fontSize = 13.sp)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("↑ ${mr?.hhmm() ?: "—"}", color = AvoColors.Silver, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                Text("↓ ${ms?.hhmm() ?: "—"}", color = AvoColors.Silver, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun WindArrow(deg: Double?) {
    if (deg == null) { Text("·", color = AvoColors.TextDim); return }
    Canvas(Modifier.size(16.dp)) {
        rotate(deg.toFloat() + 180f) {
            val p = Path().apply { moveTo(size.width / 2, 0f); lineTo(size.width, size.height); lineTo(size.width / 2, size.height * 0.72f); lineTo(0f, size.height); close() }
            drawPath(p, AvoColors.Silver)
        }
    }
}

@Composable
private fun WeatherCard(f: Forecast, day: LocalDate, nowMs: Long, lat: Double, lon: Double) {
    val start = dayStart(day)
    val hours = f.weather.filter { it.tMs in start until start + 86_400_000 }
    val seaH = f.sea.filter { it.tMs in start until start + 86_400_000 }
    val sun = remember(day) { Astro.sun(start + 43_200_000, lat, lon) }
    val ref = if (nowMs in start until start + 86_400_000) nowMs else start + 13 * 3_600_000
    val cur = hours.minByOrNull { abs(it.tMs - ref) }
    val s = seaH.minByOrNull { abs(it.tMs - ref) }
    AvoCard("Tiempo y mar") {
        if (cur != null) Row(verticalAlignment = Alignment.CenterVertically) {
            Text(weatherEmoji(cur.code), fontSize = 38.sp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(cur.airC?.let { "${it.roundToInt()}°" } ?: "—", color = AvoColors.Text, fontSize = 30.sp, fontWeight = FontWeight.Black)
                Text(TideRepository.weatherText(cur.code), color = AvoColors.TextDim, fontSize = 13.sp)
            }
            Column(horizontalAlignment = Alignment.End) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    WindArrow(cur.windDir); Spacer(Modifier.width(4.dp))
                    Text("${cur.windKmh?.roundToInt() ?: "—"} km/h ${TideRepository.compass(cur.windDir)}", color = AvoColors.Text, fontWeight = FontWeight.Bold)
                }
                Text("Rachas ${cur.gustKmh?.roundToInt() ?: "—"} km/h", color = AvoColors.TextDim, fontSize = 13.sp)
            }
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricTile("Ola", s?.waveM?.let { String.format(es, "%.1f", it) }, "m", Modifier.weight(1f), sea)
            MetricTile("Periodo", s?.periodS?.let { String.format(es, "%.0f", it) }, "s", Modifier.weight(1f))
            MetricTile("Agua", s?.waterC?.let { String.format(es, "%.1f", it) }, "°C", Modifier.weight(1f), AvoColors.Cyan)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricTile("Lluvia", cur?.rainMm?.let { String.format(es, "%.1f", it) }, "mm", Modifier.weight(1f))
            MetricTile("Humedad", cur?.humidityPct?.roundToInt()?.toString(), "%", Modifier.weight(1f))
            MetricTile("Presión", cur?.pressureHpa?.roundToInt()?.toString(), "hPa", Modifier.weight(1f))
        }
        if (hours.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(hours) { h ->
                    val night = (sun.riseMs != null && h.tMs < sun.riseMs!!) || (sun.setMs != null && h.tMs > sun.setMs!!)
                    val isNow = abs(h.tMs - nowMs) < 1_800_000
                    Column(
                        Modifier.width(52.dp).clip(RoundedCornerShape(12.dp)).background(if (isNow) AvoColors.RedDark else AvoColors.Surface2).padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(h.tMs.local().hour.toString().padStart(2, '0'), color = AvoColors.TextDim, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        Text(weatherEmoji(h.code, night), fontSize = 18.sp)
                        Text(h.airC?.let { "${it.roundToInt()}°" } ?: "—", color = AvoColors.Text, fontWeight = FontWeight.Bold)
                        WindArrow(h.windDir)
                        Text(h.windKmh?.roundToInt()?.toString() ?: "—", color = AvoColors.Silver, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun PortDialog(ports: List<TidePort>, current: TidePort?, onDismiss: () -> Unit, onPick: (TidePort) -> Unit) {
    var q by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Puerto de referencia") },
        text = {
            Column {
                OutlinedTextField(q, { q = it }, singleLine = true, label = { Text("Buscar") }, modifier = Modifier.fillMaxWidth())
                LazyColumn(Modifier.heightIn(max = 380.dp)) {
                    items(ports.filter { q.isBlank() || it.name.contains(q, true) }.take(60)) { p ->
                        Row(Modifier.fillMaxWidth().clickable { onPick(p) }.padding(vertical = 10.dp)) {
                            Text(p.name, color = if (p.id == current?.id) AvoColors.Red else AvoColors.Text, modifier = Modifier.weight(1f), fontWeight = if (p.id == current?.id) FontWeight.Bold else FontWeight.Normal)
                            Text("${p.distKm.roundToInt()} km", color = AvoColors.TextDim, fontSize = 13.sp)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Cerrar") } },
    )
}

/** Conditions at the start of a training: official IHM tide at that minute plus weather/sea (forecast or archive). */
suspend fun marineSnapshotForTraining(repo: TideRepository, settings: Settings, sessionId: String, timestampMs: Long): TrainingMarineEntity {
    val lat = settings.spotLat; val lon = settings.spotLon
    val port = repo.portsNear(lat, lon).let { l -> l.firstOrNull { it.id == settings.tidePortId } ?: l.firstOrNull() } ?: error("Lista de puertos del IHM no disponible")
    val ext = repo.extremes(port.id, timestampMs - 86_400_000, timestampMs + 86_400_000)
    val level = TideMath.levelAt(ext, timestampMs)
    val ageDays = (System.currentTimeMillis() - timestampMs) / 86_400_000
    val f = if (ageDays in -7..60) runCatching { repo.forecast(lat, lon, pastDays = (ageDays + 2).toInt().coerceIn(1, 92)) }.getOrNull() else null
    val w = f?.weather?.minByOrNull { abs(it.tMs - timestampMs) }?.takeIf { abs(it.tMs - timestampMs) <= 90 * 60_000L }
        ?: repo.historicWeather(lat, lon, timestampMs)
    val s = f?.sea?.minByOrNull { abs(it.tMs - timestampMs) }?.takeIf { abs(it.tMs - timestampMs) <= 90 * 60_000L }
    return TrainingMarineEntity(
        sessionId = sessionId, location = "${settings.spotName} · ${port.name}",
        sampleMs = timestampMs,
        source = "IHM (marea oficial) · Open-Meteo",
        levelMsl = level?.heightM, waveM = s?.waveM, wavePeriodS = s?.periodS,
        waterC = s?.waterC, windKmh = w?.windKmh, gustKmh = w?.gustKmh,
        tideTrend = when { level == null -> "DESCONOCIDA"; level.rising -> "SUBIENDO"; else -> "BAJANDO" },
        tideCoefficient = TideMath.coefficientAt(ext, timestampMs),
        coefficientSource = "IHM · ${port.name}"
    )
}
