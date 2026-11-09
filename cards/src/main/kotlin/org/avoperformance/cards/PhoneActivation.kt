package org.avoperformance.cards

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.SystemClock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.avoperformance.horse.core.license.LicenseIssuer
import org.avoperformance.horse.core.license.LicenseRole
import org.avoperformance.horse.core.license.LicenseToken
import org.avoperformance.horse.core.license.NfcActivation
import org.avoperformance.horse.core.license.RegEvent
import org.avoperformance.horse.core.license.RegUser
import java.security.KeyPair
import java.time.LocalDate
import java.time.ZoneId

/**
 * «Activar móvil por NFC» (see [NfcActivation]): the issuer arms ONE activation (user, roles, last day) for
 * [WINDOW_MS]; while armed, [AvoHceService] answers the AVO app of the phone that is put against this one with a
 * licence signed for that phone. One activation per arming: after it the session disarms itself.
 */
object PhoneActivation {
    const val WINDOW_MS = 120_000L

    data class Armed(val user: RegUser, val roles: Set<LicenseRole>, val lastDay: LocalDate, val key: KeyPair, val untilElapsed: Long)

    sealed interface State {
        data object Idle : State
        data class Waiting(val armed: Armed) : State
        data class Done(val user: RegUser, val token: LicenseToken, val deviceHex: String) : State
        data class Failed(val reason: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state

    @Synchronized
    fun arm(user: RegUser, roles: Set<LicenseRole>, lastDay: LocalDate, key: KeyPair) {
        require(roles.isNotEmpty()) { "Marca al menos un rol" }
        _state.value = State.Waiting(Armed(user, roles, lastDay, key, SystemClock.elapsedRealtime() + WINDOW_MS))
    }

    @Synchronized
    fun cancel() { _state.value = State.Idle }

    /** After a result has been shown. */
    @Synchronized
    fun acknowledge() { if (_state.value !is State.Waiting) _state.value = State.Idle }

    @Synchronized
    fun armedNow(): Armed? {
        val w = _state.value as? State.Waiting ?: return null
        if (SystemClock.elapsedRealtime() > w.armed.untilElapsed) { _state.value = State.Failed("Tiempo agotado: no se acercó ningún móvil"); return null }
        return w.armed
    }

    /** Called by the HCE service with the reader's device id: signs the licence, records it and disarms. */
    @Synchronized
    fun issue(ctx: Context, deviceId: ByteArray): NfcActivation.Result? {
        val a = armedNow() ?: return null
        return try {
            val nowMs = System.currentTimeMillis()
            val token = LicenseIssuer.issueForDevice(a.key, deviceId, a.user.code, nowMs, a.lastDay, ZoneId.systemDefault(), a.roles)
            val deviceHex = deviceId.joinToString("") { "%02X".format(it) }
            val store = RegistryStore(ctx)
            val reg = store.load()
            val current = reg.user(a.user.code) ?: a.user
            store.save(reg.upsert(current.copy(expiresS = token.expiresAtS, rolesBits = token.roles, revoked = false),
                RegEvent(nowMs, a.user.code, RegEvent.Kind.MOVIL, token.roles, token.expiresAtS, "móvil ${deviceHex.take(8)}")))
            ctx.getSharedPreferences("license_issuer", Context.MODE_PRIVATE).edit().putLong("registry_changed_ms", nowMs).apply()
            _state.value = State.Done(current, token, deviceHex)
            NfcActivation.Result(a.user.card, token.encode())
        } catch (e: Exception) {
            _state.value = State.Failed("No se pudo emitir la licencia: ${e.message}")
            null
        }
    }
}

/**
 * Host Card Emulation of AVO Tarjetas (AID [NfcActivation.AID], declared in res/xml/avo_hce_service.xml). Android
 * routes the APDUs of a phone reading this one here; it only answers while an activation is armed.
 */
class AvoHceService : HostApduService() {
    private val card = NfcActivation.Card(issue = { id -> PhoneActivation.issue(applicationContext, id) },
        armed = { PhoneActivation.armedNow() != null })

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray =
        commandApdu?.let { card.process(it) } ?: NfcActivation.SW_WRONG_LENGTH

    override fun onDeactivated(reason: Int) { card.deselect() }
}
