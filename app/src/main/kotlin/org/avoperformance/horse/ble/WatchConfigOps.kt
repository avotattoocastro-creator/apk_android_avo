package org.avoperformance.horse.ble

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.config.WatchConfig
import org.avoperformance.horse.core.geo.Fence

/**
 * Read-modify-write of the watch configuration. Always starts from the
 * configuration read from the watch, so fields unknown to the app are preserved.
 */
class WatchConfigOps(private val watch: WatchConnection) {
    private val _config = MutableStateFlow<WatchConfig?>(null)
    val config: StateFlow<WatchConfig?> = _config

    suspend fun read(): Result<WatchConfig> = runCatching {
        val c = watch.client ?: error("Sin conexión con el reloj")
        when (val r = WatchConfig.decode(c.getConfig())) {
            is WatchConfig.Companion.Result.Ok -> r.config.also { _config.value = it }
            is WatchConfig.Companion.Result.Error -> error("Configuración del reloj ilegible: ${r.reason}")
        }
    }

    suspend fun write(cfg: WatchConfig): String? {
        val p = cfg.problems()
        if (p.isNotEmpty()) return p.joinToString("\n")
        val c = watch.client ?: return "Sin conexión con el reloj"
        val m = runCatching { c.setConfig(cfg.encode()) }.getOrElse { return it.message }
        if (m.statusEnum != BleStatus.OK) return "El reloj rechazó la configuración: ${m.statusEnum.texto}"
        // payload[0] = number of fields the watch corrected to stay in range (0xFF = error)
        val fixed = m.payload.getOrNull(0)?.toInt()?.and(0xFF) ?: 0
        read()
        return if (fixed in 1..0xFE) "Guardado; el reloj ajustó $fixed valor(es) a su rango válido" else null
    }

    suspend fun setIdentity(horseId: Long, horseCode: String, riderId: Long, riderCode: String): String? {
        val cur = read().getOrElse { return it.message }
        return write(cur.copy(horseId = horseId, horseName = horseCode, riderId = riderId, riderName = riderCode))
    }

    /** SET_FENCE for one slot; the watch validates it with the same rules as [Fence.validate]. */
    suspend fun setFence(slot: Int, f: Fence): String? {
        if (f.type != org.avoperformance.horse.core.geo.FenceType.NONE) f.validate()?.let { return it }   // NONE = delete the slot
        val c = watch.client ?: return "Sin conexión con el reloj"
        val m = runCatching { c.setFence(f.setFenceRequest(slot)) }.getOrElse { return it.message }
        if (m.statusEnum != BleStatus.OK) return "El reloj rechazó la geocerca: ${m.statusEnum.texto}"
        read()
        return null
    }

    suspend fun setActive(mask: Int, auto: Boolean): String? {
        val c = watch.client ?: return "Sin conexión con el reloj"
        val st = runCatching { c.setActiveFences(mask, auto) }.getOrElse { return it.message }
        if (st != BleStatus.OK) return "El reloj respondió: ${st.texto}"
        read()
        return null
    }
}
