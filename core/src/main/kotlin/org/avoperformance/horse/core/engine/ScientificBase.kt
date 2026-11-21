package org.avoperformance.horse.core.engine

// Base científica KB-1 del motor (equine-intelligence/docs/algoritmos/14_BASE_CIENTIFICA.md). Modelos tolerantes de:
//  · «trabajo_pista.base_cientifica» de una sesión (bandas B1/B2/B3 con sus límites, Verheyen, fatiga ósea) y la
//    velocidad de los últimos 600 m de cada trabajo («trabajo_pista.trabajos.lista[].v_ultimos_600m»);
//  · «estado.base_cientifica» / «sesiones[].base_cientifica» de la historia (avo-training-analysis).
// Un campo ausente o null queda en null: la app enseña «sin datos» y nunca calcula ni estima nada aquí.

/** Banda de velocidad con sus límites en m/s (vMax null en B3). */
data class KbBand(val code: String, val vMin: Double?, val vMax: Double?, val distanceM: Double?, val timeS: Double?) {
    val name: String get() = when (code) { "B1_TRABAJO" -> "B1 · trabajo"; "B2_INTERMEDIA" -> "B2 · intermedia"; "B3_ALTA" -> "B3 · alta"; else -> code }
    val limitsText: String get() = KbFormat.range(vMin, vMax)
}

/** Velocidad de los últimos 600 m de un trabajo (null si mide menos de 600 m). */
data class KbFinal600(val id: Int, val kind: String, val distanceM: Double?, val timeS: Double?, val speed: Double?) {
    val title: String get() = (if (kind == "PASADA") "Pasada " else "Trabajo ") + id
}

data class KbSession(
    val version: String, val breed: String, val racePace: Double?, val racePaceOrigin: String, val bands: List<KbBand>,
    val canterMinSpeed: Double?, val gallopCut: Double?, val canterM: Double?, val gallopM: Double?,
    val bonePct: Double?, val boneLowPct: Double?, val boneValidMinSpeed: Double?, val strides: Double?, val calibrated: Boolean?,
    val final600: List<KbFinal600>,
) {
    companion object {
        /** Desde el bloque «trabajo_pista»; null si no trae «base_cientifica» (análisis anteriores a KB-1). */
        fun fromTrackWork(tp: J): KbSession? {
            val o = tp["base_cientifica"]
            if (o.v !is Map<*, *>) return null
            val vh = o["verheyen"]
            val fo = o["fatiga_osea"]
            val efforts = tp["trabajos"]["lista"].list + tp["recorrido"]["pasadas"].list
            return KbSession(
                version = o["version"].s(), breed = tp["perfil"]["raza"].s(), racePace = o["v_carrera_m_s"].dOrNull(), racePaceOrigin = o["v_carrera_origen"].s(),
                bands = o["bandas"].list.map { KbBand(it["banda"].s(), it["v_min"].dOrNull(), it["v_max"].dOrNull(), it["distancia_m"].dOrNull(), it["tiempo_s"].dOrNull()) },
                canterMinSpeed = vh["canter_v_min"].dOrNull(), gallopCut = vh["corte_galope_m_s"].dOrNull(),
                canterM = vh["canter_m"].dOrNull(), gallopM = vh["galope_rapido_m"].dOrNull(),
                bonePct = fo["pct"].dOrNull(), boneLowPct = fo["pct_extrapolado_lento"].dOrNull(), boneValidMinSpeed = fo["v_min_validada"].dOrNull(),
                strides = fo["zancadas_estimadas"].dOrNull(), calibrated = fo["calibrado"].v as? Boolean,
                final600 = efforts.map { KbFinal600(it["id"].i(), it["tipo"].s(), it["distancia_m"].dOrNull(), it["ultimos_600m_s"].dOrNull(), it["v_ultimos_600m"].dOrNull()) },
            )
        }

        /** Desde el JSON completo de un análisis «avo-equine-analysis». */
        fun fromAnalysis(text: String): KbSession? = fromTrackWork(J(MiniJson.parse(text))["trabajo_pista"])
    }
}

data class KbWindow(val bandsM: List<Double?>, val canterM: Double?, val gallopM: Double?, val bonePct: Double?, val sessions: Int, val sessionsWithoutData: Int) {
    companion object {
        fun of(j: J): KbWindow? = if (j.v !is Map<*, *>) null else
            KbWindow((0..2).map { j["bandas_m"][it].dOrNull() }, j["canter_m"].dOrNull(), j["galope_rapido_m"].dOrNull(), j["fatiga_osea_pct"].dOrNull(),
                j["sesiones"].i(), j["sesiones_sin_datos"].i())
    }
}

data class KbRule(val rule: String, val level: String, val action: String, val text: String, val evidence: String) {
    val code: String get() = codeOf(rule)
    val title: String get() = titleOf(rule)
    val isLimit: Boolean get() = action == "LIMITAR"

    companion object {
        val catalogue = listOf("A1_CANTER_30D", "A2_GALOPE_30D", "A3_RAMPA", "A5_VUELTA_DESCANSO", "A6_VUELTA_TENDON", "A6B_POCO_GALOPE_60D",
            "A6C_COCIENTE_GALOPE", "A7_CAIDA_ZANCADA", "A8_CAIDA_VELOCIDAD_FINAL", "KB_SIN_RAPIDO_30D", "KB_FATIGA_OSEA_7D")
        fun codeOf(r: String): String = when {
            r.startsWith("KB_FATIGA_OSEA") -> "FO 7 d"
            r.startsWith("KB_SIN_RAPIDO") -> "SR 30 d"
            else -> r.substringBefore('_')
        }
        fun titleOf(r: String): String = when (r) {
            "A1_CANTER_30D" -> "Canter acumulado en 30 días"
            "A2_GALOPE_30D" -> "Galope rápido acumulado en 30 días"
            "A3_RAMPA" -> "Subida brusca del trabajo rápido"
            "A5_VUELTA_DESCANSO" -> "Vuelta al trabajo rápido tras descanso"
            "A6_VUELTA_TENDON" -> "Vuelta tras descanso largo (≥ 90 días)"
            "A6B_POCO_GALOPE_60D" -> "Pocos días de galope en 60 días"
            "A6C_COCIENTE_GALOPE" -> "Cociente de galope bajo"
            "A7_CAIDA_ZANCADA" -> "Zancada más corta que su línea base"
            "A8_CAIDA_VELOCIDAD_FINAL" -> "Velocidad final más baja que su línea base"
            "KB_SIN_RAPIDO_30D" -> "Sin trabajo rápido en 30 días"
            "KB_FATIGA_OSEA_7D" -> "Fatiga ósea de 7 días"
            else -> r
        }
    }
}

data class KbHistory(
    val version: String, val available: Boolean, val d7: KbWindow?, val d30: KbWindow?, val prev30: KbWindow?, val d60: KbWindow?,
    val boneWeeklyMedianPct: Double?, val boneRatio7d: Double?, val daysWithoutFastWork: Int?, val gallopDays60d: Int?,
    val gallopRatio: Double?, val gallopRatioDays60: Int?, val gallopRatioDays90: Int?, val returnDay: Int?, val returnRestDays: Int?,
    val rules: List<KbRule>, val note: String,
) {
    fun rule(code: String): KbRule? = rules.firstOrNull { it.rule == code }

    companion object {
        /** Bloque «base_cientifica» (de «estado» o de una sesión); null si falta. */
        fun of(o: J): KbHistory? {
            if (o.v !is Map<*, *>) return null
            val cg = o["cociente_galope"]
            val vd = o["vuelta_descanso"]
            fun int(j: J): Int? = j.dOrNull()?.toInt()
            return KbHistory(
                version = o["version"].s(), available = o["disponible"].b(), d7 = KbWindow.of(o["d7"]), d30 = KbWindow.of(o["d30"]),
                prev30 = KbWindow.of(o["d30_anteriores"]), d60 = KbWindow.of(o["d60"]),
                boneWeeklyMedianPct = o["fatiga_osea_mediana_semanal_pct"].dOrNull(), boneRatio7d = o["fatiga_osea_ratio_7d"].dOrNull(),
                daysWithoutFastWork = int(o["dias_sin_trabajo_rapido"]), gallopDays60d = int(o["dias_galope_60d"]),
                gallopRatio = cg["valor"].dOrNull(), gallopRatioDays60 = int(cg["dias_galope_60d"]), gallopRatioDays90 = int(cg["dias_galope_90d"]),
                returnDay = int(vd["dia"]), returnRestDays = int(vd["dias_sin_rapido_antes"]),
                rules = o["reglas"].list.map { KbRule(it["regla"].s(), it["nivel"].s(), it["accion"].s(), it["texto"].s(), it["evidencia"].s()) },
                note = o["nota"].s(),
            )
        }

        /** «estado.base_cientifica» de un resultado «avo-training-analysis». */
        fun fromTrainingAnalysis(text: String): KbHistory? {
            val r = J(MiniJson.parse(text))
            require(r["formato"].s() == "avo-training-analysis") { "no es un resultado avo-training-analysis" }
            return of(r["estado"]["base_cientifica"])
        }
    }
}

object KbFormat {
    const val NO_DATA = "sin datos"
    const val BONE_NOTE = "Índice relativo, no es una probabilidad de lesión."
    const val UNCALIBRATED = "Sin calibrar: fuera del PSI (árabes incluidos) se usan los parámetros de PSI."
    private val es = java.util.Locale.forLanguageTag("es-ES")
    private fun f(v: Double, d: Int) = String.format(es, "%.${d}f", v)
    fun ms(v: Double?, d: Int = 1): String = v?.takeIf { it.isFinite() }?.let { f(it, d) + " m/s" } ?: NO_DATA
    fun metres(v: Double?): String = v?.takeIf { it.isFinite() }?.let { f(it, 0) + " m" } ?: NO_DATA
    fun distance(v: Double?): String = v?.takeIf { it.isFinite() }?.let { if (it >= 10_000) f(it / 1000, 1) + " km" else f(it, 0) + " m" } ?: NO_DATA
    fun percent(v: Double?, d: Int = 2): String = v?.takeIf { it.isFinite() }?.let { f(it, d) + " %" } ?: NO_DATA
    fun ratio(v: Double?, d: Int = 2): String = v?.takeIf { it.isFinite() }?.let { f(it, d) } ?: NO_DATA
    fun range(lo: Double?, hi: Double?): String {
        val l = lo?.takeIf { it.isFinite() }
        val h = hi?.takeIf { it.isFinite() }
        return when {
            l != null && h != null -> f(l, 1) + "–" + f(h, 1) + " m/s"
            l != null -> "≥ " + f(l, 1) + " m/s"
            h != null -> "< " + f(h, 1) + " m/s"
            else -> NO_DATA
        }
    }
    fun sentence(t: String): String = if (t.isEmpty()) t else t.replaceFirstChar { it.uppercase() }.let { if (it.endsWith(".")) it else "$it." }
}
