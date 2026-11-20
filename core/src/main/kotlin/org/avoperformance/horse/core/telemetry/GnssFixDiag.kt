package org.avoperformance.horse.core.telemetry

/**
 * 2.16-fixdiag (21/11/2026): «¿Por qué no hay RTK FIX?». Lee los campos de la espalda ≥ 3.15.0 que el pecho ≥ 3.7.11 pone
 * en el texto DIAG_GET (BackStatus v4: antena y RF de UBX-MON-RF, familias RTCM recibidas y usadas, estación base y su
 * distancia, modelo dinámico, constelaciones) y los cruza con la calidad de señal y la solución actual.
 * Es una pantalla de diagnóstico temporal (decisión del usuario: «una vez solucionado simplificamos datos en el apk»).
 * Contrato: docs/DIAGNOSTICO_FIX_RTK.md. Mismos bits que firmware/back/V3_8_0/lib/avo_core/src/avo_payloads.h (RtcmTypeBit).
 */
object RtcmFamilies {
    const val BASE_POS = 1 shl 0
    const val GPS_MSM = 1 shl 1
    const val GLO_MSM = 1 shl 2
    const val GAL_MSM = 1 shl 3
    const val BDS_MSM = 1 shl 4
    const val QZS_MSM = 1 shl 5
    const val SBS_MSM = 1 shl 6
    const val GLO_BIAS = 1 shl 7
    const val GPS_LEGACY = 1 shl 8
    const val GLO_LEGACY = 1 shl 9
    const val ANT_DESC = 1 shl 10
    const val EPHEM = 1 shl 11
    const val MSM7 = 1 shl 12
    const val MSM4 = 1 shl 13
    const val MSM56 = 1 shl 14
    const val MSM123 = 1 shl 15

    private val NAMES = listOf(
        BASE_POS to "posición de la base (1005/1006)", GPS_MSM to "GPS", GLO_MSM to "GLONASS", GAL_MSM to "Galileo", BDS_MSM to "BeiDou",
        QZS_MSM to "QZSS", SBS_MSM to "SBAS", GLO_BIAS to "sesgos GLONASS (1230)", GPS_LEGACY to "GPS antiguo (1001-1004)",
        GLO_LEGACY to "GLONASS antiguo (1009-1012)", ANT_DESC to "descripción de antena (1007/1008/1033)", EPHEM to "efemérides",
        MSM7 to "MSM7", MSM4 to "MSM4", MSM56 to "MSM5/6", MSM123 to "MSM1-3 (solo código)",
    )

    fun describe(bits: Int): String = if (bits == 0) "ninguna" else NAMES.filter { (bits and it.first) != 0 }.joinToString(", ") { it.second }

    /** Constelaciones con observaciones MSM, en el orden GPS, GLONASS, Galileo, BeiDou. */
    fun constellations(bits: Int): List<String> = listOf(GPS_MSM to "GPS", GLO_MSM to "GLONASS", GAL_MSM to "Galileo", BDS_MSM to "BeiDou")
        .filter { (bits and it.first) != 0 }.map { it.second }
}

data class GnssFixInput(
    val rfAnt: Int?, val rfPower: Int?, val rfJamState: Int?, val rfJamL1: Int?, val rfJamL2: Int?,
    val rfAgcL1: Int?, val rfAgcL2: Int?, val rfNoiseL1: Int?, val rfNoiseL2: Int?, val rfAgeS: Int?,
    val rtcmTypes: Int?, val rtcmUsed: Int?, val baseId: Int?, val baseDistDam: Int?, val dynModel: Int?, val gnssSet: Int?,
    val sv: Int?, val svUsed: Int?, val sig: Int?, val sigUsed: Int?, val sigCarrier: Int?, val sigCorrected: Int?,
    val sigL2: Int?, val sigL2Used: Int?, val cno: Int?, val cnoMin: Int?, val cnoMax: Int?,
    val fixLost: Int?, val ttffFixS: Int?, val fixedS: Long?, val floatS: Long?,
    val backFw: String?,
) {
    /** True when the back (≥ 3.15.0) and the chest (≥ 3.7.11) send the v4 block. */
    val hasV4: Boolean get() = rfAnt != null && rtcmTypes != null

    companion object {
        private fun i(m: Map<String, String>, k: String): Int? = m[k]?.trim()?.toLongOrNull()?.takeIf { it in 0..0xFFFFFFFFL }?.toInt()
        private fun u8(m: Map<String, String>, k: String): Int? = i(m, k)?.takeIf { it in 0..254 }      // 255 = unknown
        private fun u16(m: Map<String, String>, k: String): Int? = i(m, k)?.takeIf { it in 0..65534 }  // 65535 = unknown

        fun from(diag: Map<String, String>): GnssFixInput = GnssFixInput(
            u8(diag, "rf_ant"), u8(diag, "rf_pwr"), u8(diag, "rf_jam"), u8(diag, "rf_jam1"), u8(diag, "rf_jam2"),
            u8(diag, "rf_agc1"), u8(diag, "rf_agc2"), u16(diag, "rf_noise1"), u16(diag, "rf_noise2"), u8(diag, "rf_age"),
            i(diag, "rtcm_types"), i(diag, "rtcm_used"), u16(diag, "base_id"), u16(diag, "base_dam"), u8(diag, "dyn"), i(diag, "gnss_set"),
            i(diag, "sv"), i(diag, "sv_used"), i(diag, "sig"), i(diag, "sig_used"), i(diag, "sig_cr"), i(diag, "sig_corr"),
            i(diag, "sig_l2"), i(diag, "sig_l2_used"), i(diag, "cno"), i(diag, "cno_min"), i(diag, "cno_max"),
            i(diag, "fix_lost"), i(diag, "ttff_fix")?.takeIf { it in 0..65534 }, i(diag, "fixed_s")?.toLong(), i(diag, "float_s")?.toLong(),
            diag["back_fw"]?.takeIf { it.isNotBlank() && it != "?" },
        )
    }
}

enum class FixSeverity { BLOQUEA, AVISO, INFO, BIEN }

data class FixFinding(val severity: FixSeverity, val text: String)

data class FixRow(val label: String, val value: String, val severity: FixSeverity)

data class GnssFixReport(val findings: List<FixFinding>, val rows: List<FixRow>)

object GnssFixDiag {
    /** Distances above which the base makes the FIX slow (warning) or unlikely (blocking). */
    const val BASE_WARN_KM = 20.0
    const val BASE_BAD_KM = 35.0
    const val CNO_GOOD = 40
    const val CNO_BAD = 35

    private val ANT = mapOf(0 to "iniciando", 1 to "desconocido (sin supervisión de antena)", 2 to "OK", 3 to "CORTOCIRCUITO", 4 to "ABIERTA / desconectada")
    private val JAM = mapOf(0 to "desconocido", 1 to "OK", 2 to "AVISO", 3 to "CRÍTICO")
    private val DYN = mapOf(0 to "portátil", 2 to "estacionario", 3 to "peatón", 4 to "automoción", 5 to "mar", 6 to "aire < 1 g", 7 to "aire < 2 g", 8 to "aire < 4 g")

    /**
     * [carrSoln] 0 sin RTK, 1 FLOAT, 2 FIX (TELEMETRY); [correctionsUsedMoving] = el receptor está usando correcciones ahora
     * (contador RXM-RTCM subiendo, de GnssChain); null = no se sabe.
     */
    fun analyze(d: GnssFixInput, carrSoln: Int?, correctionsUsedMoving: Boolean?): GnssFixReport {
        val f = mutableListOf<FixFinding>()
        val rows = mutableListOf<FixRow>()
        fun add(s: FixSeverity, t: String) { f += FixFinding(s, t) }

        if (carrSoln == 2) add(FixSeverity.BIEN, "RTK FIX ahora mismo.")
        else if (carrSoln == 1) add(FixSeverity.INFO, "RTK FLOAT: las correcciones funcionan; falta resolver las ambigüedades (cielo abierto y unos minutos).")

        if (!d.hasV4) {
            add(FixSeverity.INFO, "Faltan los datos de antena y correcciones: hace falta la espalda 3.15.0 y el pecho 3.7.11 (espalda actual: ${d.backFw ?: "desconocida"}).")
        }

        // ---- antena y RF (UBX-MON-RF)
        when (d.rfAnt) {
            3 -> add(FixSeverity.BLOQUEA, "Antena en CORTOCIRCUITO: revisa el cable y el conector de la antena.")
            4 -> add(FixSeverity.BLOQUEA, "Antena ABIERTA (desconectada o cable roto): revisa el conector SMA/u.FL y el cable.")
        }
        if (d.rfJamState == 3) add(FixSeverity.BLOQUEA, "Interferencia CRÍTICA en la antena (jamming): aleja la antena de la electrónica, el móvil o cables de alimentación.")
        else if (d.rfJamState == 2) add(FixSeverity.AVISO, "Interferencia en la antena (aviso de jamming): puede impedir el FIX.")
        val jamMax = listOfNotNull(d.rfJamL1, d.rfJamL2).maxOrNull()
        if (jamMax != null && jamMax >= 80 && (d.rfJamState ?: 0) < 2) add(FixSeverity.AVISO, "Indicador de interferencia alto ($jamMax de 255): hay una señal parásita cerca de la antena.")
        if (listOfNotNull(d.rfAgcL1, d.rfAgcL2).any { it <= 5 || it >= 95 }) add(FixSeverity.AVISO, "Ganancia de entrada (AGC) en un extremo: amplificador de antena saturado o sin alimentación.")

        // ---- señal
        val cno = d.cno?.takeIf { (d.sig ?: 0) > 0 }
        if (cno != null && cno < CNO_BAD) add(FixSeverity.BLOQUEA, "Señal débil (C/N₀ media $cno dBHz): cielo tapado, antena tapada por la carcasa o sin plano de masa. Para FIX hace falta ≥ $CNO_GOOD.")
        else if (cno != null && cno < CNO_GOOD) add(FixSeverity.AVISO, "Señal justa (C/N₀ media $cno dBHz): el FIX puede tardar o no llegar. Lo ideal es ≥ $CNO_GOOD.")
        if ((d.sigUsed ?: 0) > 0 && d.sigCarrier == 0) add(FixSeverity.BLOQUEA, "Ninguna señal se usa con fase de portadora: sin eso no hay FLOAT ni FIX (suele ser señal débil o correcciones que no casan).")
        if (d.sig != null && d.sig > 0 && d.sigL2 == 0) add(FixSeverity.BLOQUEA, "No se recibe la segunda banda (L2/E5b/B2): antena de una sola banda o dañada. El ZED-F9P necesita antena multibanda para un FIX fiable.")
        else if ((d.sigL2 ?: 0) > 0 && d.sigL2Used == 0) add(FixSeverity.AVISO, "La segunda banda se recibe pero no se usa (${d.sigL2} señales): señal L2 demasiado débil.")

        // ---- correcciones
        val types = d.rtcmTypes
        val used = d.rtcmUsed
        if (types != null) {
            val msm = types and (RtcmFamilies.GPS_MSM or RtcmFamilies.GLO_MSM or RtcmFamilies.GAL_MSM or RtcmFamilies.BDS_MSM or RtcmFamilies.QZS_MSM)
            if (types == 0) add(FixSeverity.BLOQUEA, "No llega ninguna corrección RTCM a la espalda en el último minuto.")
            else {
                if ((types and RtcmFamilies.BASE_POS) == 0) add(FixSeverity.BLOQUEA, "La base no envía su posición (mensaje 1005/1006): sin ella el receptor no puede hacer RTK. Cambia de punto de montaje.")
                if (msm == 0 && (types and (RtcmFamilies.GPS_LEGACY or RtcmFamilies.GLO_LEGACY)) != 0)
                    add(FixSeverity.BLOQUEA, "La base solo envía mensajes antiguos (1004/1012): el ZED-F9P usa MSM (1074/1077…). Elige un punto de montaje con MSM4 o MSM7.")
                else if (msm == 0) add(FixSeverity.BLOQUEA, "Las correcciones no traen observaciones MSM de ninguna constelación: no sirven para RTK.")
                else if ((types and (RtcmFamilies.MSM4 or RtcmFamilies.MSM56 or RtcmFamilies.MSM7)) == 0)
                    add(FixSeverity.BLOQUEA, "Las observaciones son MSM1-3 (solo código, sin fase): no sirven para RTK. Elige un punto de montaje MSM4 o MSM7.")
                val consts = RtcmFamilies.constellations(types)
                if (consts.size == 1) add(FixSeverity.AVISO, "Las correcciones solo traen ${consts[0]}: con pocas constelaciones el FIX cuesta más.")
                if ((types and RtcmFamilies.GLO_MSM) != 0 && (types and RtcmFamilies.GLO_BIAS) == 0)
                    add(FixSeverity.INFO, "Falta el mensaje 1230 (sesgos GLONASS): el receptor puede no usar GLONASS para el FIX.")
            }
            if (types != 0 && used == 0) add(FixSeverity.BLOQUEA, "Llegan correcciones pero el receptor no usa ninguna (RXM-RTCM): base incompatible o mensajes dañados.")
            else if (used != null && used != 0) {
                val notUsed = RtcmFamilies.constellations(types and used.inv())
                if (notUsed.isNotEmpty()) add(FixSeverity.INFO, "Llegan correcciones de ${notUsed.joinToString(", ")} que el receptor no está usando.")
            }
        }
        if (correctionsUsedMoving == false && types != null && types != 0) add(FixSeverity.AVISO, "El receptor no ha usado correcciones en los últimos segundos.")

        // ---- base
        val km = d.baseDistDam?.let { it / 100.0 }
        if (km != null && km > BASE_BAD_KM) add(FixSeverity.BLOQUEA, String.format(java.util.Locale.ROOT, "La base está a %.1f km: demasiado lejos para un FIX fiable. Usa un punto de montaje más cercano (< %.0f km) o una red (VRS).", km, BASE_WARN_KM))
        else if (km != null && km > BASE_WARN_KM) add(FixSeverity.AVISO, String.format(java.util.Locale.ROOT, "La base está a %.1f km: el FIX tardará más. Mejor < %.0f km.", km, BASE_WARN_KM))

        // ---- historia
        val fixed = d.fixedS ?: 0
        if (carrSoln != 2 && fixed > 0) add(FixSeverity.INFO, "Ya hubo FIX desde el arranque ($fixed s en total, perdido ${d.fixLost ?: 0} veces): el sistema puede fijar; ahora lo impide el entorno.")
        if (f.none { it.severity == FixSeverity.BLOQUEA || it.severity == FixSeverity.AVISO } && carrSoln != 2 && d.hasV4)
            add(FixSeverity.INFO, "No se ve ninguna causa clara: espera 2-3 minutos a cielo abierto, quieto, y vuelve a mirar.")

        // ---- filas de datos
        fun sev(bad: Boolean, warn: Boolean = false) = if (bad) FixSeverity.BLOQUEA else if (warn) FixSeverity.AVISO else FixSeverity.BIEN
        d.rfAnt?.let { rows += FixRow("Antena", ANT[it] ?: "?", sev(it >= 3)) }
        d.rfPower?.let { rows += FixRow("Alimentación de antena", when (it) { 0 -> "apagada"; 1 -> "encendida"; else -> "desconocida" }, FixSeverity.INFO) }
        d.rfJamState?.let { rows += FixRow("Interferencias", "${JAM[it] ?: "?"} · indicador L1 ${d.rfJamL1 ?: "—"} L2 ${d.rfJamL2 ?: "—"} (de 255)", sev(it == 3, it == 2 || (jamMax ?: 0) >= 80)) }
        if (d.rfAgcL1 != null || d.rfAgcL2 != null) rows += FixRow("AGC (ganancia de entrada)", "L1 ${d.rfAgcL1 ?: "—"} % · L2 ${d.rfAgcL2 ?: "—"} %", FixSeverity.INFO)
        if (d.rfNoiseL1 != null || d.rfNoiseL2 != null) rows += FixRow("Ruido", "L1 ${d.rfNoiseL1 ?: "—"} · L2 ${d.rfNoiseL2 ?: "—"}", FixSeverity.INFO)
        d.rfAgeS?.let { rows += FixRow("Lectura de antena", "hace $it s", if (it > 15) FixSeverity.AVISO else FixSeverity.INFO) }
        if (d.sig != null) rows += FixRow("Señales", "${d.sigUsed ?: "—"} usadas de ${d.sig} · con fase ${d.sigCarrier ?: "—"} · corregidas ${d.sigCorrected ?: "—"}", sev(d.sigCarrier == 0 && (d.sigUsed ?: 0) > 0))
        if (d.sigL2 != null) rows += FixRow("Segunda banda (L2/E5b/B2)", "${d.sigL2} recibidas · ${d.sigL2Used ?: "—"} usadas", sev((d.sig ?: 0) > 0 && d.sigL2 == 0, (d.sigL2 > 0 && d.sigL2Used == 0)))
        if (cno != null) rows += FixRow("C/N₀ (dBHz)", "media $cno · mín ${d.cnoMin ?: "—"} · máx ${d.cnoMax ?: "—"}", sev(cno < CNO_BAD, cno < CNO_GOOD))
        if (d.sv != null) rows += FixRow("Satélites", "${d.svUsed ?: "—"} usados de ${d.sv}", FixSeverity.INFO)
        types?.let { rows += FixRow("Correcciones recibidas", RtcmFamilies.describe(it), sev(it == 0 || (it and RtcmFamilies.BASE_POS) == 0)) }
        used?.let { rows += FixRow("Usadas por el receptor", RtcmFamilies.describe(it), sev(types != null && types != 0 && it == 0)) }
        if (d.baseId != null || km != null) rows += FixRow("Estación base", "ID ${d.baseId ?: "—"} · " + (km?.let { String.format(java.util.Locale.ROOT, "%.1f km", it) } ?: "distancia sin calcular (sin posición 3D)"),
            sev(km != null && km > BASE_BAD_KM, km != null && km > BASE_WARN_KM))
        d.dynModel?.let { rows += FixRow("Modelo dinámico", DYN[it] ?: "código $it", FixSeverity.INFO) }
        d.gnssSet?.let { g -> rows += FixRow("Constelaciones activas", listOf(1 to "GPS", 2 to "GLONASS", 4 to "Galileo", 8 to "BeiDou").filter { (g and it.first) != 0 }.joinToString(", ") { it.second }.ifEmpty { "—" }, FixSeverity.INFO) }
        if (d.fixedS != null || d.floatS != null) rows += FixRow("Tiempo desde el arranque", "FIX ${d.fixedS ?: 0} s · FLOAT ${d.floatS ?: 0} s · FIX perdido ${d.fixLost ?: 0} veces" +
            (d.ttffFixS?.let { " · primer FIX a los $it s" } ?: ""), FixSeverity.INFO)
        d.backFw?.let { rows += FixRow("Firmware de la espalda", it, FixSeverity.INFO) }

        val order = listOf(FixSeverity.BLOQUEA, FixSeverity.AVISO, FixSeverity.INFO, FixSeverity.BIEN)
        return GnssFixReport(f.sortedBy { order.indexOf(it.severity) }, rows)
    }
}
