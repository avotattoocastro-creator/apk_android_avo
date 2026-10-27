package org.avoperformance.horse.license

import android.app.Application
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.avoperformance.horse.AppLog
import org.avoperformance.horse.BuildConfig
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.license.ActivationResult
import org.avoperformance.horse.core.license.ClockReading
import org.avoperformance.horse.core.license.LicenseClock
import org.avoperformance.horse.core.license.LicenseCrypto
import org.avoperformance.horse.core.license.LicenseFeature
import org.avoperformance.horse.core.license.LicenseFeatures
import org.avoperformance.horse.core.license.LicenseRole
import org.avoperformance.horse.core.license.LicenseToken
import org.avoperformance.horse.core.license.LicenseFile
import org.avoperformance.horse.core.license.LicenseIssuer
import org.avoperformance.horse.core.license.LicensePolicy
import org.avoperformance.horse.core.license.LicenseStatus
import org.avoperformance.horse.core.license.StoredLicense
import org.avoperformance.horse.security.SecureStore
import java.security.PublicKey
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Global switch read by the hardware/network entry points (watch link, NTRIP, Wi-Fi download, sharing,
 * tides). It is set by [LicenseManager] before any of those objects is created.
 */
object LicenseGate {
    /** Functions enabled by the active licence (all of them in builds without licence keys). */
    @Volatile var features: Set<LicenseFeature> = LicenseFeature.entries.toSet()
        internal set
    /** User code of a licence with the Jinete role: rider given to trainings that arrive without one. */
    @Volatile var defaultRiderCode: String? = null
        internal set
    fun allows(f: LicenseFeature): Boolean = f in features
    /** Watch, recording, downloads and NTRIP. */
    val canRecord: Boolean get() = allows(LicenseFeature.GRABAR)
    const val BLOCKED = "Función no incluida en tu licencia o licencia caducada"
}

/**
 * Licence of this phone. The accepted licence and its clock record are kept as ONE blob in [SecureStore]
 * (AES-GCM with an Android Keystore key): editing or deleting part of it makes it unreadable (= no licence).
 * The trusted public keys are compiled in from the CI variable AVO_LICENSE_PUBLIC_KEYS; without keys the
 * build does not enforce licences (development builds), and the app says so in Ajustes → Licencia.
 */
class LicenseManager(private val app: Application, private val secure: SecureStore, private val log: AppLog, scope: CoroutineScope) {
    private val configText: String = BuildConfig.AVO_LICENSE_PUBLIC_KEYS
    private val configError: String?
    private val trusted: List<PublicKey>
    init {
        var err: String? = null
        trusted = try { LicenseCrypto.parseTrustedKeys(configText) } catch (e: Exception) { err = "Claves de licencia de la app dañadas"; emptyList() }
        configError = err
    }

    /** True when this build checks licences. */
    val enforced: Boolean get() = configText.isNotBlank()
    val keyIds: List<String> get() = trusted.map { k -> LicenseCrypto.keyId(k).joinToString("") { "%02X".format(it) } }

    private var stored: StoredLicense? = load()
    private val _status = MutableStateFlow<LicenseStatus>(LicenseStatus.None)
    val status: StateFlow<LicenseStatus> = _status
    private val _clockBehind = MutableStateFlow(false)
    /** The phone clock is behind the trusted time (manually moved back?). */
    val clockBehind: StateFlow<Boolean> = _clockBehind
    private val _message = MutableStateFlow<String?>(null)
    /** Result of the last activation attempt, shown on the licence screen. */
    val message: StateFlow<String?> = _message

    private val _features = MutableStateFlow<Set<LicenseFeature>>(LicenseFeature.entries.toSet())
    /** Functions enabled now (roles of the active licence; none when expired; all when not enforced). */
    val features: StateFlow<Set<LicenseFeature>> = _features

    init {
        refresh()
        scope.launch { while (true) { delay(60_000); refresh() } }
    }

    val fullAccess: Boolean get() = _status.value.fullAccess
    fun allows(f: LicenseFeature): Boolean = f in _features.value

    /** Roles of the active licence (empty when expired, missing or not enforced). */
    val roles: Set<LicenseRole> get() = (_status.value as? LicenseStatus.Active)?.token?.roleSet.orEmpty()

    /** Holder of an active licence with the Jinete role: (user code, name) to use as rider, else null. */
    val licenseRider: Pair<String, String>? get() = (_status.value as? LicenseStatus.Active)
        ?.takeIf { LicenseFeatures.defaultRider(it.token.roleSet) }?.let { it.token.userCode to it.userName.ifBlank { it.token.userCode } }

    /** Jinete licence without a role that may choose the rider: the rider cannot be changed in this app. */
    val riderLocked: Boolean get() = (_status.value as? LicenseStatus.Active)?.let { LicenseFeatures.fixedRider(it.token.roleSet) } == true

    /** Active licence token (base64) published in the sharing profile, so that others can check the roles. */
    val publicTokenB64: String? get() = (_status.value as? LicenseStatus.Active)?.token?.let { java.util.Base64.getEncoder().encodeToString(it.encode()) }

    /**
     * Roles of another AVO user from the licence published in their profile: only if the signature is valid with a
     * key of this app and the licence belongs to [code]. Null when it cannot be verified.
     */
    fun verifiedRoles(code: String, tokenB64: String?): Set<LicenseRole>? {
        if (tokenB64.isNullOrBlank() || trusted.isEmpty()) return null
        val t = runCatching { LicenseToken.decode(java.util.Base64.getDecoder().decode(tokenB64)) }.getOrNull() ?: return null
        if (t.userCode != code || !LicensePolicy.verifySignature(t, trusted)) return null
        if (System.currentTimeMillis() >= t.expiresAtMs) return null   // expired licence: no roles shown
        return t.roleSet
    }

    private fun load(): StoredLicense? = secure.getString(KEY)?.let { runCatching { StoredLicense.decode(it) }.getOrNull() }

    private fun save(s: StoredLicense) { secure.putString(KEY, s.encode()); stored = s }

    private fun networkTimeMs(): Long? = if (Build.VERSION.SDK_INT >= 33) {
        try { SystemClock.currentNetworkTimeClock().millis() } catch (_: Exception) { null }
    } else null

    private fun bootCount(): Int = runCatching { Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT) }.getOrDefault(-1)

    private fun readClock(previous: StoredLicense?): ClockReading =
        LicenseClock.read(System.currentTimeMillis(), SystemClock.elapsedRealtime(), bootCount(), networkTimeMs(), previous?.clock)

    /** Recomputes the status (every minute, on resume, after an activation) and keeps the clock record. */
    @Synchronized
    fun refresh() {
        val s = stored
        val clock = readClock(s)
        if (s != null) {
            val prev = s.clock
            if (clock.record.highWaterMs - prev.highWaterMs > 60_000 || clock.record.bootCount != prev.bootCount || clock.source == "red")
                save(s.copy(clock = clock.record))
        }
        _clockBehind.value = clock.systemClockBehind
        val st = configError?.let { LicenseStatus.Invalid(it) } ?: LicensePolicy.status(stored, trusted, clock.effectiveMs)
        val before = _status.value
        _status.value = st
        val f = when (st) {
            LicenseStatus.NotEnforced -> LicenseFeature.entries.toSet()
            is LicenseStatus.Active -> LicenseFeatures.of(st.token.roleSet)
            else -> emptySet()
        }
        LicenseGate.features = f
        LicenseGate.defaultRiderCode = licenseRider?.first
        _features.value = f
        if (before.fullAccess != st.fullAccess || before::class != st::class) log.i("LICENCIA", describe(st))
    }

    /** User card tapped: [licenseBytes] from its NDEF licence record, [tagUid] from the chip. */
    @Synchronized
    fun activateFromCard(licenseBytes: ByteArray?, tagUid: ByteArray?, card: AvoUserCard?): String? {
        if (!enforced) return null
        if (licenseBytes == null) {
            return if (fullAccess) null else "Esta tarjeta no lleva licencia de la app".also { _message.value = it }
        }
        val r = LicensePolicy.activate(licenseBytes, tagUid, card?.code, card?.name ?: "", trusted, stored, readClock(stored))
        return applyResult(r, "tarjeta")
    }

    /** Licence file received by email/WhatsApp; it is decrypted with the secret of the phone's identity card. */
    @Synchronized
    fun activateFromFile(text: String, identity: AvoUserCard?): String {
        if (!enforced) return "Esta versión de la app no usa licencias"
        if (identity == null) return ("Este móvil aún no conoce tu tarjeta AVO. Acerca tu tarjeta (aunque su licencia esté caducada) " +
            "y vuelve a abrir el archivo.").also { _message.value = it }
        val bytes = try { LicenseFile.decode(text, identity) } catch (e: IllegalArgumentException) {
            return "Archivo de licencia no válido: ${e.message}".also { _message.value = it }
        }
        val r = LicensePolicy.activateFromFile(bytes, identity.code, identity.name, trusted, stored, readClock(stored))
        return applyResult(r, "archivo")!!
    }

    private fun applyResult(r: ActivationResult, via: String): String? {
        val text = when (r) {
            is ActivationResult.Activated -> {
                save(r.stored)
                log.i("LICENCIA", "activada por $via hasta ${day(r.stored.token.expiresAtS)} (${r.stored.token.userCode})")
                (if (r.renewed) "Licencia renovada" else "Licencia activada") + " hasta el ${day(r.stored.token.expiresAtS)}"
            }
            is ActivationResult.AlreadyActive -> { save(r.stored); "Licencia activa hasta el ${day(r.stored.token.expiresAtS)}" }
            is ActivationResult.Refused -> { log.w("LICENCIA", "rechazada ($via): ${r.reason}"); r.reason }
        }
        refresh()
        _message.value = text
        return text
    }

    fun describe(st: LicenseStatus = _status.value): String = when (st) {
        LicenseStatus.NotEnforced -> "Licencias no activadas en esta versión"
        LicenseStatus.None -> "Sin licencia"
        is LicenseStatus.Active -> "Activa hasta el ${day(st.token.expiresAtS)} · ${LicenseRole.label(st.token.roleSet)}"
        is LicenseStatus.Expired -> "Caducada el ${day(st.token.expiresAtS)}"
        is LicenseStatus.Invalid -> st.reason
    }

    companion object {
        private const val KEY = "license.state.v1"
        private val FMT = DateTimeFormatter.ofPattern("dd/MM/yyyy")
        /** Last valid day (the expiry is 00:00 of the next day). */
        fun day(expiresAtS: Long): String = LicenseIssuer.lastDayOf(expiresAtS, ZoneId.systemDefault()).format(FMT)
    }
}
