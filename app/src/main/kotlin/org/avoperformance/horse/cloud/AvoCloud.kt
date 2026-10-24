package org.avoperformance.horse.cloud

import android.content.Context
import android.util.Base64
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.FirebaseDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import org.avoperformance.horse.core.identity.AvoUserCard
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * App-to-app sending over the internet with Firebase (Spark free plan: Authentication + Realtime Database).
 * No own server and no Cloud Storage: the .avo file travels in base64 chunks under `blobs/<recipient>/<msg>`
 * and the notice under `inbox/<recipient>/<msg>`. The recipient downloads it, checks the SHA-256 and deletes both.
 * Permissions: firebase/database.rules.json (only the owner of the NFC card can read or delete their inbox).
 *
 * Login = user NFC card: email `<code>@avo-cards.app` (not a real address) and password = card secret.
 * The same card on another phone opens the same account.
 */
class AvoCloud(private val ctx: Context) {
    data class Contact(val code: String, val name: String)
    data class Incoming(val id: String, val from: String, val fromName: String, val sessionId: String,
                        val size: Long, val sha256: String, val chunks: Int, val createdMs: Long)

    private val app: FirebaseApp by lazy {
        FirebaseApp.getApps(ctx).firstOrNull { it.name == NAME } ?: FirebaseApp.initializeApp(ctx, FirebaseOptions.Builder()
            .setApplicationId(FirebaseConfig.APP_ID).setApiKey(FirebaseConfig.API_KEY)
            .setProjectId(FirebaseConfig.PROJECT_ID).setDatabaseUrl(FirebaseConfig.DATABASE_URL).build(), NAME)
    }
    private val auth get() = FirebaseAuth.getInstance(app)
    private val db get() = FirebaseDatabase.getInstance(app, FirebaseConfig.DATABASE_URL)

    private fun <T> Task<T>.await(): T = Tasks.await(this, 60, TimeUnit.SECONDS)

    /** Signs in with the card; on first use it creates the account and publishes the name in the directory. */
    suspend fun signIn(card: AvoUserCard): Unit = withContext(Dispatchers.IO) {
        val email = emailOf(card.code)
        if (auth.currentUser?.email == email) return@withContext
        if (auth.currentUser != null) auth.signOut()
        try {
            auth.signInWithEmailAndPassword(email, card.secret).await()
        } catch (signInError: Exception) {
            try { auth.createUserWithEmailAndPassword(email, card.secret).await() }
            catch (e: Exception) {
                val collision = e is FirebaseAuthUserCollisionException || (e.cause is FirebaseAuthUserCollisionException)
                throw IllegalStateException(if (collision) "La clave de esta tarjeta no coincide con la registrada (¿tarjeta regrabada?)"
                    else "Sin conexión con el servicio de envío: ${(e.cause ?: e).message}")
            }
        }
        val uid = auth.currentUser?.uid ?: error("Inicio de sesión fallido")
        db.getReference("users/${card.code}").setValue(mapOf("name" to card.name, "uid" to uid)).await()
    }

    fun signOut() = runCatching { auth.signOut() }

    suspend fun contacts(me: AvoUserCard): List<Contact> = withContext(Dispatchers.IO) {
        signIn(me)
        db.getReference("users").get().await().children.mapNotNull { s ->
            val code = s.key ?: return@mapNotNull null
            if (code == me.code || !AvoUserCard.CODE.matches(code)) null
            else Contact(code, s.child("name").getValue(String::class.java) ?: code)
        }.sortedBy { it.name.lowercase() }
    }

    /** Sends [file] (.avo package) to [to]. First the chunks, then the notice, so the recipient never sees an incomplete delivery. */
    suspend fun send(me: AvoUserCard, to: String, sessionId: String, file: File, progress: (Int, Int) -> Unit): Unit = withContext(Dispatchers.IO) {
        require(file.length() in 1..MAX_BYTES) { "El entrenamiento ocupa ${file.length() / 1_048_576} MB; máximo ${MAX_BYTES / 1_048_576} MB" }
        signIn(me)
        val ref = db.getReference("inbox/$to").push()
        val id = ref.key ?: error("Sin identificador de envío")
        val sha = MessageDigest.getInstance("SHA-256")
        val bytes = file.readBytes()
        sha.update(bytes)
        val chunks = ((bytes.size + CHUNK - 1) / CHUNK)
        try {
            for (i in 0 until chunks) {
                val part = bytes.copyOfRange(i * CHUNK, minOf(bytes.size, (i + 1) * CHUNK))
                db.getReference("blobs/$to/$id/$i").setValue(Base64.encodeToString(part, Base64.NO_WRAP)).await()
                progress(i + 1, chunks)
            }
            ref.setValue(mapOf("from" to me.code, "fromName" to me.name, "sessionId" to sessionId, "size" to bytes.size.toLong(),
                "sha256" to sha.digest().joinToString("") { "%02x".format(it) }, "chunks" to chunks, "createdMs" to System.currentTimeMillis())).await()
        } catch (e: Exception) {
            throw IllegalStateException("Envío interrumpido: ${(e.cause ?: e).message}")
        }
    }

    /** Notices that arrive in my inbox (including the ones that were already there). */
    fun incoming(me: AvoUserCard): Flow<Incoming> = callbackFlow {
        signIn(me)
        val ref = db.getReference("inbox/${me.code}")
        val l = object : ChildEventListener {
            override fun onChildAdded(s: DataSnapshot, previous: String?) { parse(s)?.let { trySend(it) } }
            override fun onChildChanged(s: DataSnapshot, previous: String?) {}
            override fun onChildRemoved(s: DataSnapshot) {}
            override fun onChildMoved(s: DataSnapshot, previous: String?) {}
            override fun onCancelled(e: DatabaseError) { close(IllegalStateException(e.message)) }
        }
        ref.addChildEventListener(l)
        awaitClose { ref.removeEventListener(l) }
    }

    /** Downloads, checks the SHA-256, saves to [target] and deletes the delivery from the service. */
    suspend fun receive(me: AvoUserCard, m: Incoming, target: File): Unit = withContext(Dispatchers.IO) {
        signIn(me)
        val snap = db.getReference("blobs/${me.code}/${m.id}").get().await()
        val tmp = File(target.parentFile, target.name + ".part")
        val sha = MessageDigest.getInstance("SHA-256")
        tmp.outputStream().use { out ->
            for (i in 0 until m.chunks) {
                val b64 = snap.child(i.toString()).getValue(String::class.java) ?: error("Falta el trozo ${i + 1}/${m.chunks}")
                val part = Base64.decode(b64, Base64.NO_WRAP)
                sha.update(part); out.write(part)
            }
        }
        val got = sha.digest().joinToString("") { "%02x".format(it) }
        if (tmp.length() != m.size || got != m.sha256) { tmp.delete(); error("Entrenamiento recibido dañado (SHA-256 distinto)") }
        check(tmp.renameTo(target)) { "No se pudo guardar" }
        discard(me, m.id)
    }

    suspend fun discard(me: AvoUserCard, id: String): Unit = withContext(Dispatchers.IO) {
        db.getReference("blobs/${me.code}/$id").removeValue().await()
        db.getReference("inbox/${me.code}/$id").removeValue().await()
    }

    private fun parse(s: DataSnapshot): Incoming? = runCatching {
        Incoming(s.key!!, s.child("from").getValue(String::class.java)!!, s.child("fromName").getValue(String::class.java) ?: "",
            s.child("sessionId").getValue(String::class.java)!!, s.child("size").getValue(Long::class.java)!!,
            s.child("sha256").getValue(String::class.java)!!, s.child("chunks").getValue(Long::class.java)!!.toInt(),
            s.child("createdMs").getValue(Long::class.java) ?: 0L)
    }.getOrNull()

    companion object {
        private const val NAME = "avo-transfer"
        const val CHUNK = 256 * 1024
        const val MAX_BYTES = 30L * 1024 * 1024
        fun emailOf(code: String) = code.lowercase() + "@avo-cards.app"
    }
}
