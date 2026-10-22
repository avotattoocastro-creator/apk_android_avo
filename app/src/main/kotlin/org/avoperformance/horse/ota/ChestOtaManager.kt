package org.avoperformance.horse.ota

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import org.avoperformance.horse.AppContainer
import org.avoperformance.horse.core.ble.BleStatus
import org.avoperformance.horse.core.ble.ChestOtaProtocol
import org.avoperformance.horse.core.ble.Idempotency
import org.avoperformance.horse.core.ble.MsgType
import org.avoperformance.horse.core.ble.WatchSessionState

/** Transfer engine for V3.5.0. Not exposed for execution until signed firmware
 * authenticity and hardware rollback have been verified on an actual watch.
 * Reconnect/version checking is intentionally not misrepresented as tested. */
class ChestOtaManager(private val container: AppContainer) {
    data class State(val phase: String = "Sin actualización", val confirmed: Int = 0, val total: Int = 0, val error: String? = null, val events: List<String> = emptyList(), val versionBefore: String? = null, val versionAfter: String? = null)
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state
    @Volatile private var active = false
    @Volatile private var cancelRequested = false

    /** The ZIP is signed, but only the verified firmware.bin may enter the ESP32 transport. */
    fun inspectSignedPackage(packageBytes: ByteArray): SignedOtaVerifier.Verified {
        val verified = SignedOtaVerifier.verify(packageBytes)
        val inspection = ChestOtaProtocol.inspect(verified.firmware)
        require(inspection.valid) { inspection.reason }
        return verified
    }
    fun isApproved(packageBytes: ByteArray): Boolean = runCatching { inspectSignedPackage(packageBytes); true }.getOrDefault(false)
    @Volatile private var positiveAuthVersion: String? = null
    val positiveAuthorizationConfirmed: Boolean get() = positiveAuthVersion != null
    val safeInstallationAvailable: Boolean = false // Watch-side signature enforcement and anti-rollback not yet proven
    fun cancel() { cancelRequested = true }
    private fun report(phase: String, note: String) {
        val old = _state.value
        _state.value = old.copy(phase = phase, events = (old.events + note).takeLast(20))
    }

    /** Non-flashing diagnostic: malformed authorization must be rejected by the watch. */
    suspend fun probeInvalidAuthorization(): String = withContext(Dispatchers.IO) {
        check(!active) { "Hay una operación OTA activa" }
        val watch = container.watch
        check(watch.isReady && watch.client != null) { "Conecta y autoriza el reloj primero" }
        check(watch.info.value?.firmware == "3.5.7") { "Diagnóstico limitado a CHEST 3.5.7" }
        val payload = ChestOtaProtocol.authPayload(
            "{\"schema\":\"avo-ota-manifest-v1\"}".toByteArray(Charsets.UTF_8),
            ByteArray(70)
        )
        val response = watch.client!!.request(MsgType.OTA_AUTH, payload, Idempotency.STATE_CHANGING, 12000, 0)
        val result = when (response.statusEnum) {
            BleStatus.VERIFY_FAILED -> "CORRECTO: el reloj rechazó la firma inválida (VERIFY_FAILED)"
            BleStatus.OK -> "FALLO DE SEGURIDAD: el reloj aceptó una firma inválida; OTA bloqueada"
            else -> "Resultado no concluyente: ${response.statusEnum.texto}"
        }
        report("Diagnóstico OTA_AUTH", result)
        result
    }

    /** Checks a genuine signature on the watch without sending OTA_BEGIN or firmware data. */
    suspend fun probeValidAuthorization(packageBytes: ByteArray): String = withContext(Dispatchers.IO) {
        check(!active) { "Hay una operación OTA activa" }
        positiveAuthVersion = null
        val verified = inspectSignedPackage(packageBytes)
        val watch = container.watch
        check(watch.isReady && watch.client != null) { "Conecta y autoriza el reloj primero" }
        check(watch.info.value?.firmware == "3.5.7") { "Prueba limitada a CHEST 3.5.7" }
        val response = watch.client!!.request(
            MsgType.OTA_AUTH, ChestOtaProtocol.authPayload(verified.manifest, verified.signature),
            Idempotency.STATE_CHANGING, 12000, 0
        )
        val result = if (response.statusEnum == BleStatus.OK) {
            positiveAuthVersion = verified.version
            "CONFIRMADO: el reloj aceptó OTA_AUTH para ${verified.version}; no se ha enviado firmware"
        } else {
            "NO AUTORIZADO: respuesta del reloj ${response.statusEnum.texto}"
        }
        report("Diagnóstico OTA_AUTH válido", result)
        result
    }

    suspend fun transfer(packageBytes: ByteArray) = withContext(Dispatchers.IO) {
        check(safeInstallationAvailable) { "OTA bloqueada: falta demostrar verificación de firma y anti-rollback en el reloj físico" }
        val verified = inspectSignedPackage(packageBytes)
        val image = verified.firmware
        check(!active) { "Otra actualización ya está activa" }
        active = true
        cancelRequested = false
        var began = false
        try {
            val precheck = ChestOtaProtocol.inspect(image)
            require(precheck.valid) { precheck.reason }
            val watch = container.watch
            check(watch.isReady) { "Pecho sin conexión/autorización" }
            check(watch.info.value?.supportsOta == true) { "Firmware sin capacidad OTA anunciada" }
            val status = watch.client!!.getStatus()
            check(status.session != WatchSessionState.RECORDING && status.rec != org.avoperformance.horse.core.ble.RecStatus.RECORDING) { "Entrenamiento activo" }
            val battery = status.batteryPct
            check(battery != null && battery >= 60) { "Batería no verificable o inferior al 60 %" }
            check(!container.ntrip.running) { "Detén NTRIP antes de actualizar" }
            check(!container.sync.isBusy) { "Descarga de entrenamientos en curso" }
            val beforeVersion = watch.info.value?.firmware
            _state.value = State("Preparando", 0, image.size, versionBefore = beforeVersion)
            report("Preparando", "Firmware anterior: ${beforeVersion ?: "no comunicado"}; bytes=${image.size}")
            val client = watch.client!!
            val authorization = client.request(
                MsgType.OTA_AUTH,
                ChestOtaProtocol.authPayload(verified.manifest, verified.signature),
                Idempotency.STATE_CHANGING, 12000, 0
            )
            check(authorization.statusEnum == BleStatus.OK) {
                "OTA_AUTH rechazado por el reloj: ${authorization.statusEnum.texto}"
            }
            report("Autorizado", "OTA_AUTH confirmado por el reloj para ${verified.version}")
            val b = client.request(MsgType.OTA_BEGIN, ChestOtaProtocol.beginPayload(image), Idempotency.STATE_CHANGING, 12000, 0)
            check(b.statusEnum == BleStatus.OK) { "OTA_BEGIN rechazado: ${b.statusEnum.texto}" }
            began = true
            report("Transfiriendo", "OTA_BEGIN confirmado por firmware: ${b.statusEnum}")
            var offset = 0
            while (offset < image.size) {
                if (cancelRequested) throw CancellationException("Cancelada por el usuario")
                val size = minOf(128, image.size - offset)
                val reply = client.request(MsgType.OTA_DATA, ChestOtaProtocol.dataPayload(offset, image, size), Idempotency.STATE_CHANGING, 12000, 0)
                check(reply.statusEnum == BleStatus.OK) { "OTA_DATA ${offset}: ${reply.statusEnum.texto}" }
                val ackOffset = ChestOtaProtocol.confirmedOffset(reply.payload)
                check(ackOffset == (offset + size).toLong()) { "Desplazamiento no confirmado en $offset" }
                offset += size
                _state.value = State("Transfiriendo", offset, image.size)
            }
            report("Verificando en el pecho", "Todos los desplazamientos OTA_DATA confirmados: $offset bytes")
            val end = try {
                client.request(MsgType.OTA_END, idem = Idempotency.STATE_CHANGING, timeoutMs = 15000, retries = 0)
            } catch (t: Throwable) {
                report("OTA_END sin confirmación", "El reloj puede haberse reiniciado antes del ACK: ${t.message}")
                null
            }
            if (end != null) {
                check(end.statusEnum == BleStatus.OK) { "OTA_END rechazado: ${end.statusEnum.texto}; ${end.payload.decodeToString()}" }
                report("Reiniciando", "OTA_END confirmado por firmware: OK; esperar arranque y versión")
            }
            // V3.5.0 can reboot before the GATT response is delivered. Never equate a
            // disconnect or 100% byte ACKs with successful installation.
            val after = withTimeoutOrNull(90_000L) {
                var disconnected = false
                repeat(45) {
                    delay(2000L)
                    if (!watch.isReady) disconnected = true
                    val current = watch.client
                    if (watch.isReady && current != null && (disconnected || it >= 5)) {
                        val info = runCatching { current.getInfo() }.getOrNull()
                        if (info != null && info.firmware != beforeVersion) return@withTimeoutOrNull info.firmware
                    }
                }
                null
            }
            if (after != null) {
                _state.value = _state.value.copy(phase = "Versión nueva anunciada: $after (verificar en el reloj)", versionAfter = after)
                report(_state.value.phase, "GET_INFO tras reconexión comunica $after; versión anterior $beforeVersion")
            } else {
                report("No se ha confirmado la instalación", "No se ha observado una versión nueva durante 90 s; no repetir OTA sin diagnóstico")
            }
        } catch (t: Throwable) {
            if (began && _state.value.phase !in listOf("Reiniciando", "No se ha confirmado la instalación")) runCatching { container.watch.client?.request(MsgType.OTA_ABORT, idem = Idempotency.STATE_CHANGING, timeoutMs = 2000, retries = 0) }
            report("Error", "Excepción OTA: ${t.message}")
            _state.value = _state.value.copy(error = t.message)
            throw t
        } finally { active = false }
    }
}
