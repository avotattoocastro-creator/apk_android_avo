package org.avoperformance.horse.tide

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.avoperformance.horse.core.tide.TideExtreme
import org.avoperformance.horse.core.tide.TideMath
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.*

data class TidePort(val id: String, val name: String, val lat: Double, val lon: Double, val distKm: Double = 0.0)

data class HourWeather(
    val tMs: Long, val airC: Double?, val windKmh: Double?, val gustKmh: Double?, val windDir: Double?,
    val rainMm: Double?, val cloudPct: Double?, val code: Int?, val pressureHpa: Double?, val humidityPct: Double?,
)

data class HourSea(val tMs: Long, val waveM: Double?, val periodS: Double?, val waveDir: Double?, val waterC: Double?)

data class Forecast(val weather: List<HourWeather>, val sea: List<HourSea>, val fetchedMs: Long)

/** Official tide predictions from the Instituto Hidrográfico de la Marina plus Open-Meteo conditions, with disk cache. */
class TideRepository(private val ctx: Context) {
    private val dir = File(ctx.filesDir, "tide").apply { mkdirs() }
    private val api = "https://ideihm.covam.es/api-ihm/getmarea"

    private fun http(url: String): String {
        check(org.avoperformance.horse.license.LicenseGate.fullAccess) { "Mareas y meteorología disponibles con licencia activa" }
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000; readTimeout = 20_000
            setRequestProperty("User-Agent", "AVO-Performance-Horse/2.0 (Android)")
        }
        try {
            if (c.responseCode !in 200..299) error("HTTP ${c.responseCode}")
            return c.inputStream.bufferedReader().use { it.readText() }
        } finally { c.disconnect() }
    }

    /** Reads a cached file if younger than [maxAgeMs]; otherwise downloads, falling back to any stale copy offline. */
    private fun cached(name: String, maxAgeMs: Long, url: String): String {
        val f = File(dir, name)
        if (f.exists() && System.currentTimeMillis() - f.lastModified() < maxAgeMs) return f.readText()
        return try {
            http(url).also { f.writeText(it) }
        } catch (e: Exception) {
            if (f.exists()) f.readText() else throw e
        }
    }

    suspend fun ports(): List<TidePort> = withContext(Dispatchers.IO) {
        val j = JSONObject(cached("ports.json", 7L * 86_400_000, "$api?request=getlist&format=json"))
        val arr = j.getJSONObject("estaciones").getJSONArray("puertos")
        (0 until arr.length()).mapNotNull { i ->
            val p = arr.getJSONObject(i)
            val lat = p.optString("lat").toDoubleOrNull() ?: return@mapNotNull null
            val lon = p.optString("lon").toDoubleOrNull() ?: return@mapNotNull null
            TidePort(p.optString("id"), p.optString("puerto"), lat, lon)
        }
    }

    suspend fun portsNear(lat: Double, lon: Double): List<TidePort> =
        ports().map { it.copy(distKm = km(lat, lon, it.lat, it.lon)) }.sortedBy { it.distKm }

    private fun monthKey(ms: Long) = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).let { "%04d%02d".format(it.year, it.monthValue) }

    private suspend fun month(portId: String, yyyymm: String): List<TideExtreme> = withContext(Dispatchers.IO) {
        val text = cached("ihm_${portId}_$yyyymm.json", 30L * 86_400_000, "$api?request=gettide&id=$portId&month=$yyyymm&format=json")
        parseMonth(text)
    }

    suspend fun extremes(portId: String, fromMs: Long, toMs: Long): List<TideExtreme> = coroutineScope {
        val keys = generateSequence(fromMs - 86_400_000) { it + 86_400_000 }.takeWhile { it <= toMs + 86_400_000 }.map { monthKey(it) }.toSet()
        val all = keys.map { async { runCatching { month(portId, it) }.getOrDefault(emptyList()) } }.awaitAll().flatten().sortedBy { it.tMs }
        if (all.isEmpty()) error("Sin predicción oficial del IHM para este puerto")
        val mean = meanRange(portId, fromMs) ?: TideMath.meanRange(all)
        val withC = TideMath.withCoefficients(all, mean)
        val i0 = (withC.indexOfFirst { it.tMs >= fromMs } - 1).coerceAtLeast(0)
        val i1 = (withC.indexOfLast { it.tMs <= toMs } + 2).coerceAtMost(withC.size)
        withC.subList(i0, i1.coerceAtLeast(i0))
    }

    /** Mean range over three months of predictions (covers several spring/neap cycles): coefficient 70. */
    private suspend fun meanRange(portId: String, nowMs: Long): Double? = coroutineScope {
        val keys = listOf(-31L, 0L, 31L).map { monthKey(nowMs + it * 86_400_000) }
        val ext = keys.map { async { runCatching { month(portId, it) }.getOrDefault(emptyList()) } }.awaitAll().flatten().sortedBy { it.tMs }
        TideMath.meanRange(ext)
    }

    /** Hourly weather and sea state, [pastDays] back and 7 days ahead (cached for 1 h). */
    suspend fun forecast(lat: Double, lon: Double, pastDays: Int = 2): Forecast = withContext(Dispatchers.IO) {
        val key = "%.3f_%.3f_%d".format(java.util.Locale.US, lat, lon, pastDays)
        val w = runCatching {
            JSONObject(cached("wx_$key.json", 3_600_000, "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
                "&hourly=temperature_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,precipitation,cloud_cover,weather_code,pressure_msl,relative_humidity_2m" +
                "&timezone=GMT&past_days=$pastDays&forecast_days=7"))
        }.getOrNull()
        val m = runCatching {
            JSONObject(cached("sea_$key.json", 3_600_000, "https://marine-api.open-meteo.com/v1/marine?latitude=$lat&longitude=$lon" +
                "&hourly=wave_height,wave_period,wave_direction,sea_surface_temperature&timezone=GMT&past_days=$pastDays&forecast_days=7&cell_selection=sea"))
        }.getOrNull()
        val weather = w?.optJSONObject("hourly")?.let { h ->
            val t = h.getJSONArray("time")
            (0 until t.length()).map { i ->
                HourWeather(isoUtc(t.getString(i)), h.num("temperature_2m", i), h.num("wind_speed_10m", i), h.num("wind_gusts_10m", i),
                    h.num("wind_direction_10m", i), h.num("precipitation", i), h.num("cloud_cover", i), h.num("weather_code", i)?.toInt(),
                    h.num("pressure_msl", i), h.num("relative_humidity_2m", i))
            }
        }.orEmpty()
        val sea = m?.optJSONObject("hourly")?.let { h ->
            val t = h.getJSONArray("time")
            (0 until t.length()).map { i -> HourSea(isoUtc(t.getString(i)), h.num("wave_height", i), h.num("wave_period", i), h.num("wave_direction", i), h.num("sea_surface_temperature", i)) }
        }.orEmpty()
        if (weather.isEmpty() && sea.isEmpty()) error("Sin conexión con Open-Meteo")
        Forecast(weather, sea, System.currentTimeMillis())
    }

    /** Historical weather for a past training (Open-Meteo archive/reanalysis, available for any date). */
    suspend fun historicWeather(lat: Double, lon: Double, atMs: Long): HourWeather? = withContext(Dispatchers.IO) {
        val d = Instant.ofEpochMilli(atMs).atZone(ZoneOffset.UTC).toLocalDate()
        val url = "https://archive-api.open-meteo.com/v1/archive?latitude=$lat&longitude=$lon&start_date=$d&end_date=$d" +
            "&hourly=temperature_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m,precipitation,cloud_cover,weather_code,pressure_msl,relative_humidity_2m&timezone=GMT"
        val h = runCatching { JSONObject(cached("arch_%.3f_%.3f_$d.json".format(java.util.Locale.US, lat, lon), 30L * 86_400_000, url)).getJSONObject("hourly") }.getOrNull() ?: return@withContext null
        val t = h.getJSONArray("time")
        val list = (0 until t.length()).map { i ->
            HourWeather(isoUtc(t.getString(i)), h.num("temperature_2m", i), h.num("wind_speed_10m", i), h.num("wind_gusts_10m", i),
                h.num("wind_direction_10m", i), h.num("precipitation", i), h.num("cloud_cover", i), h.num("weather_code", i)?.toInt(),
                h.num("pressure_msl", i), h.num("relative_humidity_2m", i))
        }.filter { it.airC != null || it.windKmh != null }
        list.minByOrNull { abs(it.tMs - atMs) }?.takeIf { abs(it.tMs - atMs) <= 90 * 60_000L }
    }

    companion object {
        private val isoFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
        fun isoUtc(s: String): Long = LocalDateTime.parse(s, isoFmt).toInstant(ZoneOffset.UTC).toEpochMilli()
        private fun JSONObject.num(k: String, i: Int): Double? = optJSONArray(k)?.optDouble(i, Double.NaN)?.takeIf { it.isFinite() }

        /** IHM monthly JSON: mareas.datos.marea[] {fecha, hora (UTC), altura (m over chart datum), tipo}. */
        fun parseMonth(text: String): List<TideExtreme> {
            val datos = JSONObject(text).getJSONObject("mareas").getJSONObject("datos")
            val raw = datos.opt("marea")
            val arr = when (raw) { is JSONArray -> raw; is JSONObject -> JSONArray().put(raw); else -> JSONArray() }
            return (0 until arr.length()).mapNotNull { i ->
                val m = arr.getJSONObject(i)
                val t = runCatching { LocalDateTime.parse("${m.getString("fecha")}T${m.getString("hora").padStart(5, '0')}", isoFmt).toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrNull()
                    ?: return@mapNotNull null
                val h = m.optString("altura").replace(",", ".").toDoubleOrNull() ?: return@mapNotNull null
                TideExtreme(t, h, m.optString("tipo").lowercase().startsWith("plea"))
            }.sortedBy { it.tMs }
        }

        fun km(la1: Double, lo1: Double, la2: Double, lo2: Double): Double {
            val r = PI / 180
            val a = sin((la2 - la1) * r / 2).pow(2) + cos(la1 * r) * cos(la2 * r) * sin((lo2 - lo1) * r / 2).pow(2)
            return 6371 * 2 * asin(sqrt(a))
        }

        fun weatherText(code: Int?): String = when (code) {
            null -> "—"; 0 -> "Despejado"; 1 -> "Poco nuboso"; 2 -> "Nubes y claros"; 3 -> "Cubierto"
            45, 48 -> "Niebla"; in 51..57 -> "Llovizna"; in 61..67 -> "Lluvia"; in 71..77 -> "Nieve"
            in 80..82 -> "Chubascos"; in 85..86 -> "Chubascos de nieve"; in 95..99 -> "Tormenta"; else -> "—"
        }

        fun compass(deg: Double?): String = deg?.let { listOf("N", "NE", "E", "SE", "S", "SO", "O", "NO")[((it % 360 + 360) % 360 / 45 + 0.5).toInt() % 8] } ?: "—"
    }
}
