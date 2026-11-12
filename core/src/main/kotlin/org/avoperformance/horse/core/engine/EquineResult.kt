package org.avoperformance.horse.core.engine

/**
 * Typed view of the AVO Equine Intelligence Engine output (format "avo-equine-analysis" v2, engine 1.1.x).
 * Values are never invented: missing values stay NaN / null and the UI shows "—" or "SIN DATOS DE CINCHA".
 * Times are GNSS seconds from the first epoch of the session ([itow0Ms] is the iTOW of that epoch).
 */
data class EqMetric(val name: String, val value: Double, val unit: String, val quality: String, val uncertainty: Double?, val algorithm: String, val version: String, val warnings: List<String>)
data class EqQuality(val domain: String, val level: String, val reasons: List<String>)
data class EqRtk(val totalS: Double, val fixS: Double, val floatS: Double, val noneS: Double, val timeToFixS: Double?, val fixLosses: Int, val hAccMedianFixM: Double?, val longestOutageS: Double?)
data class EqGaitSegment(val code: String, val name: String, val t0: Double, val t1: Double, val quality: String, val confidence: Double?, val basis: String)
data class EqGait(val classifier: String, val algorithm: String, val version: String, val segments: List<EqGaitSegment>)
data class EqSegmentPerf(
    val id: Int, val code: String, val name: String, val t0: Double, val t1: Double, val durationS: Double, val distanceM: Double?, val speedMean: Double?, val speedMax: Double?,
    val accelMax: Double?, val decelMax: Double?, val cadenceHz: Double?, val cadenceCv: Double?, val cadenceSigmaHz: Double?, val intervalCv: Double?, val amplitudeCv: Double?,
    val cycleCorr: Double?, val spectralStability: Double?, val strideLengthM: Double?, val fixFraction: Double, val gnssQuality: String, val imuQuality: String,
    val classQuality: String, val confidence: Double?, val warnings: List<String>,
)
data class EqAggregate(val code: String, val name: String, val segments: Int, val durationS: Double, val distanceM: Double, val speedMean: Double?, val speedMax: Double?, val cadenceHz: Double?, val strideLengthM: Double?, val timeFraction: Double)
data class EqPerformance(val classifier: String, val segments: List<EqSegmentPerf>, val perGait: List<EqAggregate>, val session: EqAggregate?)
data class EqCurve(
    val id: Int, val direction: String, val t0: Double, val t1: Double, val headingDeg: Double, val radiusM: Double, val radiusSigmaM: Double, val radiusGeomM: Double?,
    val centerLat: Double, val centerLon: Double, val vEntry: Double, val vExit: Double, val vMean: Double, val latAccMean: Double, val latAccMax: Double, val latAccSigma: Double,
    val cadenceBeforeHz: Double?, val cadenceDuringHz: Double?, val cadenceAfterHz: Double?, val quality: String, val warnings: List<String>,
)
data class EqAccelEvent(val type: String, val t0: Double, val t1: Double, val peak: Double, val peakSigma: Double, val mean: Double, val dv: Double, val quality: String, val source: String)
data class EqEvent(val id: String, val type: String, val t0: Double, val t1: Double, val data: List<String>, val quality: String, val reason: String, val algorithm: String, val version: String, val values: Map<String, Double>)
data class EqRelation(val x: String, val y: String, val gait: String, val n: Int, val slope: Double?, val intercept: Double?, val slopeSigma: Double?, val r: Double?, val spearman: Double?, val note: String)
data class EqFusion(val mode: String, val windows: Int, val ok: Int, val noSync: Int, val gnssGap: Int, val noCadence: Int, val medianSigmaTms: Double?, val relations: List<EqRelation>, val warnings: List<String>)
data class EqSpread(val median: Double?, val iqr: Double?, val n: Int, val reproducible: Boolean)
data class EqSymmetryGroup(val imu: Int, val gait: String, val windows: Int, val strides: Int, val ampLogRatio: EqSpread, val timingAsym: EqSpread, val halfSimilarity: EqSpread)
data class EqSymmetry(val label: String, val allowed: Boolean, val controls: List<Triple<String, String, String>>, val groups: List<EqSymmetryGroup>, val notes: List<String>)
class EqSeries(val t: DoubleArray, val speed: DoubleArray, val accel: DoubleArray, val latAccel: DoubleArray, val curvature: DoubleArray, val dist: DoubleArray,
               val lat: DoubleArray, val lon: DoubleArray, val quality: IntArray, val gait: IntArray)
class EqGirthSeries(val imu: IntArray, val t: DoubleArray, val cadenceHz: DoubleArray, val cadenceSigmaHz: DoubleArray, val strideLengthM: DoubleArray,
                    val cycleCorr: DoubleArray, val intervalCv: DoubleArray, val speed: DoubleArray, val status: List<String>)

data class EquineResult(
    val formatVersion: Int, val engine: String, val processedAt: String, val sessionId: String, val mode: String, val inputFingerprint: String,
    val paramsHash: String, val itow0Ms: Long?, val algorithms: Map<String, String>, val hasImu: Boolean, val hasGnss: Boolean,
    val warnings: List<String>, val cache: String?, val metrics: List<EqMetric>, val rtk: EqRtk, val quality: List<EqQuality>,
    val gaitV1: EqGait, val gaitV2: EqGait, val performance: EqPerformance, val curves: List<EqCurve>, val accelEvents: List<EqAccelEvent>,
    val events: List<EqEvent>, val fusion: EqFusion, val symmetry: EqSymmetry, val series: EqSeries?, val girth: EqGirthSeries?,
) {
    fun metric(name: String): EqMetric? = metrics.firstOrNull { it.name == name }

    /** GNSS seconds of an epoch given its iTOW (ms), handling one week rollover. */
    fun timeOfItow(itowMs: Long): Double? {
        val t0 = itow0Ms ?: return null
        var d = itowMs - t0
        if (d < -302_400_000L) d += 604_800_000L
        return d / 1000.0
    }

    /** Engine series value at time t (nearest epoch within maxDt), NaN otherwise. */
    fun gnssAt(values: DoubleArray, t: Double, maxDt: Double = 0.3): Double {
        val s = series ?: return Double.NaN
        val i = nearest(s.t, t) ?: return Double.NaN
        return if (kotlin.math.abs(s.t[i] - t) <= maxDt) values.getOrElse(i) { Double.NaN } else Double.NaN
    }

    fun gaitAt(t: Double): EqGaitSegment? = chosenGait().segments.firstOrNull { t >= it.t0 && t < it.t1 }
    fun chosenGait(): EqGait = if (performance.classifier == gaitV2.classifier) gaitV2 else gaitV1

    /** Girth window nearest to t for one IMU (windows are 2 s apart), or null. */
    fun girthAt(t: Double, imu: Int = preferredImu(), maxDt: Double = 1.5): Int? {
        val g = girth ?: return null
        var best: Int? = null; var bd = Double.MAX_VALUE
        for (k in g.t.indices) if (g.imu[k] == imu && g.t[k].isFinite()) { val d = kotlin.math.abs(g.t[k] - t); if (d < bd) { bd = d; best = k } }
        return best?.takeIf { bd <= maxDt }
    }
    fun preferredImu(): Int = girth?.imu?.minOrNull() ?: 0

    /** Aligns a GNSS-epoch series to arbitrary times (e.g. the app's track points). */
    fun alignGnss(values: DoubleArray, times: List<Double?>): List<Double> = times.map { t -> if (t == null) Double.NaN else gnssAt(values, t) }
    fun alignGirth(values: DoubleArray, times: List<Double?>): List<Double> = times.map { t -> t?.let { girthAt(it) }?.let { k -> values[k] } ?: Double.NaN }

    companion object {
        private fun nearest(a: DoubleArray, t: Double): Int? {
            if (a.isEmpty()) return null
            var lo = 0; var hi = a.size - 1
            while (lo < hi) { val m = (lo + hi) / 2; if (a[m] < t) lo = m + 1 else hi = m }
            return if (lo > 0 && kotlin.math.abs(a[lo - 1] - t) < kotlin.math.abs(a[lo] - t)) lo - 1 else lo
        }

        fun parse(text: String): EquineResult {
            val r = J(MiniJson.parse(text))
            if (r["error"].v != null) throw IllegalStateException(r["error"].s())
            require(r["formato"].s() == "avo-equine-analysis") { "no es un resultado del motor AVO" }
            val p = r["procedencia"]
            fun gait(j: J) = EqGait(j["clasificador"].s("GAIT_CLASSIFIER_V1"), j["algoritmo"].s(), j["version"].s(),
                j["segmentos"].list.map { EqGaitSegment(it["codigo"].s(), it["aire"].s(), it["t0"].d(), it["t1"].d(), it["calidad"].s(), it["confianza"].dOrNull(), it["base"].s()) })
            fun agg(j: J) = EqAggregate(j["codigo"].s(), j["aire"].s(), j["segmentos"].i(), j["duracion_s"].d(), j["distancia_m"].d(), j["velocidad_media"].dOrNull(),
                j["velocidad_max"].dOrNull(), j["cadencia_media_hz"].dOrNull(), j["longitud_tranco_m"].dOrNull(), j["fraccion_tiempo"].d())
            fun spread(j: J) = EqSpread(j["mediana"].dOrNull(), j["iqr"].dOrNull(), j["n"].i(), j["reproducible"].b())
            val ser = r["series"].takeIf { !it.isNull }?.let { s ->
                EqSeries(s["t"].doubles(), s["velocidad"].doubles(), s["aceleracion"].doubles(), s["aceleracion_lateral"].doubles(), s["curvatura"].doubles(),
                    s["distancia"].doubles(), s["lat"].doubles(), s["lon"].doubles(), s["calidad"].ints(), s["aire"].ints())
            }
            val gir = r["series_cincha"].takeIf { !it.isNull }?.let { s ->
                EqGirthSeries(s["imu"].ints(), s["t"].doubles(), s["cadencia_hz"].doubles(), s["sigma_cadencia_hz"].doubles(), s["longitud_tranco_m"].doubles(),
                    s["correlacion_ciclos"].doubles(), s["cv_intervalos"].doubles(), s["velocidad"].doubles(), s["estado"].strings())
            }
            val perf = r["rendimiento"]
            val fu = r["fusion"]
            val sy = r["simetria"]
            val rtk = r["rtk"]
            return EquineResult(
                formatVersion = r["version_formato"].i(), engine = r["motor"].s(), processedAt = r["procesado_utc"].s(), sessionId = r["sesion"]["id"].s(),
                mode = p["modo"].s("OFFLINE_ANALYSIS"), inputFingerprint = p["huella_entrada"].s(), paramsHash = p["hash_parametros"].s(), itow0Ms = p["itow_inicial_ms"].l(),
                algorithms = p["algoritmos"].keys.associateWith { p["algoritmos"][it].s() }, hasImu = p["tiene_cincha"].b(), hasGnss = p["tiene_gnss"].b(),
                warnings = r["advertencias"].strings(), cache = r["cache"].v as? String,
                metrics = r["metricas"].list.map { EqMetric(it["nombre"].s(), it["valor"].d(), it["unidad"].s(), it["calidad"].s(), it["incertidumbre"].dOrNull(), it["algoritmo"].s(), it["version"].s(), it["avisos"].strings()) },
                rtk = EqRtk(rtk["total_s"].d(), rtk["fix_s"].d(), rtk["float_s"].d(), rtk["sin_solucion_s"].d(), rtk["tiempo_hasta_fix_s"].dOrNull()?.takeIf { it >= 0 },
                    rtk["perdidas_fix"].i(), rtk["hacc_mediana_fix_m"].dOrNull()?.takeIf { it >= 0 }, rtk["interrupcion_max_s"].dOrNull()),
                quality = r["calidad"].list.map { EqQuality(it["dominio"].s(), it["nivel"].s(), it["motivos"].strings()) },
                gaitV1 = gait(r["aires"]), gaitV2 = gait(r["aires_v2"]),
                performance = EqPerformance(perf["clasificador"].s(), perf["segmentos"].list.map {
                    EqSegmentPerf(it["id"].i(), it["codigo"].s(), it["aire"].s(), it["t0"].d(), it["t1"].d(), it["duracion_s"].d(), it["distancia_m"].dOrNull(), it["velocidad_media"].dOrNull(),
                        it["velocidad_max"].dOrNull(), it["aceleracion_max"].dOrNull(), it["desaceleracion_max"].dOrNull(), it["cadencia_media_hz"].dOrNull(), it["cadencia_cv"].dOrNull(),
                        it["cadencia_sigma_hz"].dOrNull(), it["cv_intervalos"].dOrNull(), it["cv_amplitud"].dOrNull(), it["correlacion_ciclos"].dOrNull(), it["estabilidad_espectral"].dOrNull(),
                        it["longitud_tranco_m"].dOrNull(), it["fraccion_fix"].d(), it["calidad_gnss"].s(), it["calidad_imu"].s(), it["calidad_clasificacion"].s(), it["confianza"].dOrNull(), it["avisos"].strings())
                }, perf["por_aire"].list.map { agg(it) }, perf["sesion"].takeIf { !it.isNull }?.let { agg(it) }),
                curves = r["curvas"]["lista"].list.map {
                    EqCurve(it["id"].i(), it["direccion"].s(), it["t0"].d(), it["t1"].d(), it["giro_deg"].d(), it["radio_m"].d(), it["radio_sigma_m"].d(), it["radio_geometrico_m"].dOrNull(),
                        it["centro_lat"].d(), it["centro_lon"].d(), it["v_entrada"].d(), it["v_salida"].d(), it["v_media"].d(), it["a_lateral_media"].d(), it["a_lateral_max"].d(), it["a_lateral_sigma"].d(),
                        it["cadencia_antes_hz"].dOrNull(), it["cadencia_durante_hz"].dOrNull(), it["cadencia_despues_hz"].dOrNull(), it["calidad"].s(), it["avisos"].strings())
                },
                accelEvents = r["cinematica"]["eventos"].list.map { EqAccelEvent(it["tipo"].s(), it["t0"].d(), it["t1"].d(), it["pico_m_s2"].d(), it["sigma_pico_m_s2"].d(), it["media_m_s2"].d(), it["dv"].d(), it["calidad"].s(), it["fuente"].s()) },
                events = r["eventos"].list.map { e -> EqEvent(e["id"].s(), e["tipo"].s(), e["t0"].d(), e["t1"].d(), e["datos"].strings(), e["calidad"].s(), e["motivo"].s(), e["algoritmo"].s(), e["version"].s(),
                    e["valores"].keys.associateWith { e["valores"][it].d() }) },
                fusion = EqFusion(fu["modo"].s(), fu["ventanas"].i(), fu["ventanas_ok"].i(), fu["sin_sincronia"].i(), fu["hueco_gnss"].i(), fu["sin_cadencia"].i(), fu["incertidumbre_temporal_mediana_ms"].dOrNull(),
                    fu["relaciones"].list.map { EqRelation(it["x"].s(), it["y"].s(), it["aire"].s(), it["n"].i(), it["pendiente"].dOrNull(), it["ordenada"].dOrNull(), it["sigma_pendiente"].dOrNull(), it["r"].dOrNull(), it["spearman"].dOrNull(), it["nota"].s()) },
                    fu["avisos"].strings()),
                symmetry = EqSymmetry(sy["etiqueta"].s(), sy["conclusiones_permitidas"].b(), sy["controles"].list.map { Triple(it["control"].s(), it["estado"].s(), it["motivo"].s()) },
                    sy["grupos"].list.map { EqSymmetryGroup(it["imu"].i(), it["aire"].s(), it["ventanas"].i(), it["trancos"].i(), spread(it["log_cociente_amplitud"]), spread(it["asimetria_temporal"]), spread(it["similitud_mitades"])) },
                    sy["notas"].strings()),
                series = ser, girth = gir,
            )
        }
    }
}

// ------------------------------------------------------------------ comparison
data class EqDiff(val name: String, val unit: String, val a: Double?, val b: Double?, val diff: Double?, val comparable: Boolean, val context: String)
data class EqRoute(val attempted: Boolean, val comparable: Boolean, val reason: String, val medianXtrackM: Double?, val coverage: Double?, val meanSpeedDiff: Double?, val totalTimeDiffS: Double?,
                   val s: DoubleArray, val speedA: DoubleArray, val speedB: DoubleArray, val timeDiffS: DoubleArray)
data class EqComparison(val sessionA: String, val sessionB: String, val comparable: Boolean, val reasons: List<String>, val diffs: List<EqDiff>, val route: EqRoute,
                        val patternComputed: Boolean, val patternDtw: Double?, val patternNote: String, val equivalentCurves: Int) {
    companion object {
        fun parse(text: String): EqComparison {
            val r = J(MiniJson.parse(text))
            if (r["error"].v != null) throw IllegalStateException(r["error"].s())
            require(r["formato"].s() == "avo-equine-comparison") { "no es una comparación del motor AVO" }
            val ro = r["recorrido"]
            return EqComparison(r["sesion_a"].s(), r["sesion_b"].s(), r["comparable"].b(), r["motivos"].strings(),
                r["diferencias"].list.map { EqDiff(it["metrica"].s(), it["unidad"].s(), it["a"].dOrNull(), it["b"].dOrNull(), it["diferencia"].dOrNull(), it["comparable"].b(), it["contexto"].s()) },
                EqRoute(ro["intentado"].b(), ro["comparable"].b(), ro["motivo"].s(), ro["separacion_mediana_m"].dOrNull(), ro["cobertura"].dOrNull(), ro["diferencia_velocidad_media"].dOrNull(),
                    ro["diferencia_tiempo_total_s"].dOrNull(), ro["perfil"]["s"].doubles(), ro["perfil"]["velocidad_a"].doubles(), ro["perfil"]["velocidad_b"].doubles(), ro["perfil"]["diferencia_tiempo_s"].doubles()),
                r["patron"]["calculado"].b(), r["patron"]["distancia_dtw_m_s"].dOrNull(), r["patron"]["nota"].s(), r["curvas_equivalentes"].list.size)
        }
    }
}
