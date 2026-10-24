package org.avoperformance.horse.cloud

import android.content.Context
import android.util.Base64
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseException
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DatabaseError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.avoperformance.horse.core.identity.AvoUserCard
import org.avoperformance.horse.core.share.Contact
import org.avoperformance.horse.core.share.GrantState
import org.avoperformance.horse.core.share.Notice
import org.avoperformance.horse.core.share.OfflineException
import org.avoperformance.horse.core.share.ShareBackend
import org.avoperformance.horse.core.share.TransferMeta
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Firebase connection (Spark: Authentication + Realtime Database, no Cloud Storage or Functions).
 * Account = AVO NFC card: email `<code>@avo-cards.app` (not a real address) + card secret.
 * Data structure and permissions: firebase/database.rules.json (tested with the emulator).
 */
class FirebaseShare(private val ctx: Context) {
    data class Invitation(val sender: String, val senderName: String, val state: GrantState, val ms: Long)

    private val app: FirebaseApp by lazy {
        FirebaseApp.getApps(ctx).firstOrNull { it.name == NAME } ?: FirebaseApp.initializeApp(ctx, FirebaseOptions.Builder()
            .setApplicationId(FirebaseConfig.APP_ID).setApiKey(FirebaseConfig.API_KEY)
            .setProjectId(FirebaseConfig.PROJECT_ID).setDatabaseUrl(FirebaseConfig.DATABASE_URL).build(), NAME)
    }
    private val auth get() = FirebaseAuth.getInstance(app)
    private val db get() = FirebaseDatabase.getInstance(app, FirebaseConfig.DATABASE_URL)
    /** Last path used (only for diagnosing permission errors). */
    @Volatile private var lastPath = ""
    private fun r(path: String): DatabaseReference { lastPath = path; return db.getReference(path) }

    /** Connection state with the Firebase server (true = connected). */
    fun connected(): Flow<Boolean> = callbackFlow {
        val ref = r(".info/connected")
        val l = object : ValueEventListener {
            override fun onDataChange(s: DataSnapshot) { trySend(s.getValue(Boolean::class.java) == true) }
            override fun onCancelled(e: DatabaseError) { trySend(false) }
        }
        ref.addValueEventListener(l)
        awaitClose { ref.removeEventListener(l) }
    }

    private suspend fun ensureOnline() {
        withTimeoutOrNull(15_000) { connected().first { it } } ?: throw OfflineException("Sin conexión con Firebase")
    }

    /** Runs a Firebase task translating errors: network → OfflineException; permissions → IllegalStateException. */
    private suspend fun <T> call(online: Boolean = true, block: () -> Task<T>): T = withContext(Dispatchers.IO) {
        if (online) ensureOnline()
        try { Tasks.await(block(), 60, TimeUnit.SECONDS) }
        catch (e: TimeoutException) { throw OfflineException("Firebase no responde", e) }
        catch (e: ExecutionException) { throw translate(e.cause ?: e) }
    }

    private fun translate(e: Throwable): Exception {
        val m = e.message.orEmpty()
        return when {
            m.contains("ermission denied", true) || m.contains("PERMISSION_DENIED") -> PermissionException("$m en ${lastPath.ifBlank { "?" }} como ${signedInCode ?: "sin sesión"}")
            m.contains("offline", true) || m.contains("network", true) || m.contains("Unable to resolve", true) -> OfflineException(m, e)
            e is Exception -> e
            else -> Exception(m, e)
        }
    }

    class PermissionException(m: String) : IllegalStateException("Permiso denegado por Firebase: $m")

    // ------------------------------------------------------------- account (NFC card)

    suspend fun signIn(card: AvoUserCard) {
        val email = emailOf(card.code)
        if (auth.currentUser?.email == email) return
        if (auth.currentUser != null) auth.signOut()
        try {
            call(online = false) { auth.signInWithEmailAndPassword(email, card.secret) }
        } catch (e: OfflineException) { throw e } catch (_: Exception) {
            try { call(online = false) { auth.createUserWithEmailAndPassword(email, card.secret) } }
            catch (e: OfflineException) { throw e }
            catch (e: Exception) {
                val collision = e is FirebaseAuthUserCollisionException || e.cause is FirebaseAuthUserCollisionException || e.message.orEmpty().contains("already in use")
                throw IllegalStateException(if (collision) "Esta tarjeta ya está registrada con otra clave (¿tarjeta regrabada o copiada?)" else "No se pudo entrar: ${e.message}")
            }
        }
        val uid = auth.currentUser?.uid ?: error("Inicio de sesión fallido")
        call { r("users/${card.code}").setValue(mapOf("name" to card.name, "uid" to uid)) }
    }

    fun signOut() = runCatching { auth.signOut() }
    val signedInCode: String? get() = auth.currentUser?.email?.substringBefore('@')?.uppercase()

    suspend fun directory(): List<Contact> = call { r("users").get() }.children.mapNotNull { s ->
        val code = s.key ?: return@mapNotNull null
        Contact(code, s.child("name").getValue(String::class.java) ?: code)
    }.sortedBy { it.name.lowercase() }

    /** Invites [to] to receive my trainings (they must accept it). */
    suspend fun invite(me: Contact, to: String) {
        val cur = call { r("grants/$to/${me.code}").get() }
        when (cur.child("state").getValue(String::class.java)) {
            null -> {}
            "BLOCKED" -> error("Ese usuario no acepta envíos tuyos")
            "ACCEPTED", "PENDING" -> return
            else -> call { r("grants/$to/${me.code}").removeValue() } // rejected before: invite again
        }
        call { r("grants/$to/${me.code}").setValue(mapOf("state" to "PENDING", "senderName" to me.name, "ms" to System.currentTimeMillis())) }
    }

    /** Removes [to] from my recipients (withdraws the invitation or authorization). */
    suspend fun withdraw(me: String, to: String) = call { r("grants/$to/$me").removeValue() }

    suspend fun outgoingState(me: String, to: String): GrantState? =
        call { r("grants/$to/$me/state").get() }.getValue(String::class.java)?.let { runCatching { GrantState.valueOf(it) }.getOrNull() }

    /** Invitations received (who wants to send me trainings). */
    suspend fun invitations(me: String): List<Invitation> = call { r("grants/$me").get() }.children.mapNotNull { s ->
        val st = s.child("state").getValue(String::class.java)?.let { runCatching { GrantState.valueOf(it) }.getOrNull() } ?: return@mapNotNull null
        Invitation(s.key ?: return@mapNotNull null, s.child("senderName").getValue(String::class.java) ?: "", st, s.child("ms").getValue(Long::class.java) ?: 0)
    }

    /** Accept, reject or block a sender. */
    suspend fun respond(me: String, sender: String, state: GrantState) {
        require(state != GrantState.PENDING)
        call { r("grants/$me/$sender/state").setValue(state.name) }
    }
    /** Removes a sender (if blocked, this lifts the block). */
    suspend fun forgetSender(me: String, sender: String) = call { r("grants/$me/$sender").removeValue() }

    /** Live notices: used to start the download as soon as something arrives (with the app running). */
    fun inboxChanges(me: String): Flow<String> = callbackFlow {
        val ref = r("inbox/$me")
        val l = object : ChildEventListener {
            override fun onChildAdded(s: DataSnapshot, previous: String?) { s.key?.let { trySend(it) } }
            override fun onChildChanged(s: DataSnapshot, previous: String?) {}
            override fun onChildRemoved(s: DataSnapshot) {}
            override fun onChildMoved(s: DataSnapshot, previous: String?) {}
            override fun onCancelled(e: DatabaseError) { close(translate(e.toException())) }
        }
        ref.addChildEventListener(l)
        awaitClose { ref.removeEventListener(l) }
    }

    // ------------------------------------------------------------- transfer backend (ShareEngine)

    fun backend(): ShareBackend = object : ShareBackend {
        override suspend fun grant(recipient: String, sender: String): GrantState? = outgoingState(sender, recipient)

        override suspend fun meta(transferId: String): TransferMeta? = try {
            val s = call { r("blobs/$transferId/meta").get() }
            if (!s.exists()) null else TransferMeta(transferId, s.str("owner"), s.str("ownerName"), s.str("sessionId"), s.str("horseName"),
                s.str("riderName"), s.long("size"), s.str("sha256"), s.long("chunks").toInt(), s.long("chunkSize").toInt(), s.long("createdMs"), s.long("expiresMs"))
        } catch (_: PermissionException) { null } // withdrawn, blocked or deleted: for me it no longer exists

        override suspend fun createMeta(m: TransferMeta) {
            call { r("blobs/${m.transferId}/meta").setValue(mapOf("owner" to m.owner, "ownerName" to m.ownerName.take(40), "sessionId" to m.sessionId,
                "horseName" to m.horseName.take(120), "riderName" to m.riderName.take(120), "size" to m.size, "sha256" to m.sha256.lowercase(),
                "chunks" to m.chunks, "chunkSize" to m.chunkSize, "createdMs" to m.createdMs, "expiresMs" to m.expiresMs)) }
        }

        override suspend fun uploadedChunks(transferId: String): Int =
            call { r("blobs/$transferId/n").get() }.getValue(Long::class.java)?.toInt() ?: 0

        override suspend fun putChunk(transferId: String, index: Int, data: ByteArray) {
            call { r("blobs/$transferId/c/$index").setValue(Base64.encodeToString(data, Base64.NO_WRAP)) }
            call { r("blobs/$transferId/n").setValue(index + 1) }
        }

        override suspend fun getChunk(transferId: String, index: Int): ByteArray? =
            call { r("blobs/$transferId/c/$index").get() }.getValue(String::class.java)?.let { Base64.decode(it, Base64.NO_WRAP) }

        override suspend fun markComplete(transferId: String) { call { r("blobs/$transferId/complete").setValue(true) } }
        override suspend fun isComplete(transferId: String): Boolean = try {
            call { r("blobs/$transferId/complete").get() }.getValue(Boolean::class.java) == true
        } catch (_: PermissionException) { false }

        override suspend fun allowRecipient(transferId: String, recipient: String) { call { r("blobs/$transferId/to/$recipient").setValue(true) } }
        override suspend fun revokeRecipient(transferId: String, recipient: String) { call { r("blobs/$transferId/to/$recipient").removeValue() } }

        override suspend fun notify(recipient: String, n: Notice) {
            call { r("inbox/$recipient/${n.transferId}").setValue(mapOf("from" to n.from, "fromName" to n.fromName.take(40), "sessionId" to n.sessionId,
                "horseName" to n.horseName.take(120), "size" to n.size, "createdMs" to n.createdMs)) }
        }

        override suspend fun inbox(me: String): List<Notice> = call { r("inbox/$me").get() }.children.mapNotNull { s ->
            runCatching { Notice(s.key!!, s.str("from"), s.str("fromName"), s.str("sessionId"), s.str("horseName"), s.long("size"), s.long("createdMs")) }.getOrNull()
        }

        override suspend fun removeNotice(me: String, transferId: String) { call { r("inbox/$me/$transferId").removeValue() } }

        override suspend fun putReceipt(transferId: String, me: String, value: String) {
            try { call { r("receipts/$transferId/$me").setValue(value) } } catch (_: PermissionException) { /* the sender already deleted the content */ }
        }

        override suspend fun receipts(transferId: String): Map<String, String> = try {
            call { r("receipts/$transferId").get() }.children.associate { (it.key ?: "") to (it.getValue(String::class.java) ?: "") }
        } catch (_: PermissionException) { emptyMap() }

        override suspend fun deleteTransfer(transferId: String) {
            call { r("receipts/$transferId").removeValue() }
            call { r("blobs/$transferId").removeValue() }
        }
    }

    private fun DataSnapshot.str(k: String) = child(k).getValue(String::class.java) ?: error("Falta $k")
    private fun DataSnapshot.long(k: String) = child(k).getValue(Long::class.java) ?: error("Falta $k")

    companion object {
        private const val NAME = "avo-share"
        fun emailOf(code: String) = code.lowercase() + "@avo-cards.app"
    }
}
