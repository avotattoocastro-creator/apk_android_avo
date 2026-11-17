package org.avoperformance.horse.core.license

/**
 * Roles marked on the licence card (AVO Tarjetas). Several can be combined; the app enables the union of
 * their functions ([LicenseFeatures]). Stored as bits inside the signed licence: they cannot be added
 * without the issuer's key.
 */
enum class LicenseRole(val bit: Int, val label: String, val summary: String) {
    JINETE(0x01, "Jinete", "Graba con el chaleco; queda como jinete de todos los entrenamientos de su app"),
    ENTRENADOR(0x02, "Entrenador", "Graba con el chaleco y elige el jinete de cada entrenamiento"),
    DESARROLLADOR(0x04, "Desarrollador", "Todas las funciones, también diagnósticos"),
    PROPIETARIO(0x08, "Propietario", "Consulta y recibe los entrenamientos de sus caballos, mareas"),
    VETERINARIO(0x10, "Veterinario", "Consulta, análisis y recepción de entrenamientos");

    companion object {
        const val ALL_BITS = 0x1F
        fun fromBits(bits: Int): Set<LicenseRole> = entries.filter { bits and it.bit != 0 }.toSet()
        fun toBits(roles: Collection<LicenseRole>): Int = roles.fold(0) { acc, r -> acc or r.bit }
        /** "Jinete, Propietario" in the order of the enum. */
        fun label(roles: Collection<LicenseRole>): String = entries.filter { it in roles }.joinToString(", ") { it.label }
    }
}

/**
 * Functions of the app that depend on the licence. Consultation of the data already collected (trainings,
 * analysis, comparisons, stable) is always available, even with the licence expired.
 */
enum class LicenseFeature(val label: String) {
    /** Watch/vest link, recording, downloads (BLE and Wi-Fi), NTRIP, geofences, devices. */
    GRABAR("Conectar el chaleco y grabar"),
    /** Choose any rider for the trainings (otherwise a Jinete card fixes the holder as rider). */
    ELEGIR_JINETE("Elegir el jinete"),
    MAREAS("Mareas y meteorología"),
    /** Sending and receiving trainings between AVO users. */
    COMPARTIR("Enviar y recibir entrenamientos"),
    /** General settings, NFC tags, riders, storage and backups. */
    AJUSTES("Ajustes"),
    DIAGNOSTICO("Diagnósticos");
}

/** THE table role → functions. Change it here and both apps follow. */
object LicenseFeatures {
    val BY_ROLE: Map<LicenseRole, Set<LicenseFeature>> = mapOf(
        LicenseRole.JINETE to setOf(LicenseFeature.GRABAR, LicenseFeature.MAREAS, LicenseFeature.COMPARTIR, LicenseFeature.AJUSTES),
        LicenseRole.ENTRENADOR to setOf(LicenseFeature.GRABAR, LicenseFeature.ELEGIR_JINETE, LicenseFeature.MAREAS, LicenseFeature.COMPARTIR, LicenseFeature.AJUSTES),
        LicenseRole.DESARROLLADOR to LicenseFeature.entries.toSet(),
        LicenseRole.PROPIETARIO to setOf(LicenseFeature.MAREAS, LicenseFeature.COMPARTIR, LicenseFeature.AJUSTES),
        LicenseRole.VETERINARIO to setOf(LicenseFeature.COMPARTIR, LicenseFeature.AJUSTES),
    )

    fun of(roles: Collection<LicenseRole>): Set<LicenseFeature> = roles.flatMap { BY_ROLE[it].orEmpty() }.toSet()

    /** The holder is the fixed rider of every training: Jinete without a role that may choose the rider. */
    fun fixedRider(roles: Collection<LicenseRole>): Boolean = LicenseRole.JINETE in roles && LicenseFeature.ELEGIR_JINETE !in of(roles)

    /** The holder becomes the default rider (pre-selected) when the card has Jinete. */
    fun defaultRider(roles: Collection<LicenseRole>): Boolean = LicenseRole.JINETE in roles
}
