package org.avoperformance.signer

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.widget.*
import org.json.JSONObject
import java.security.*
import java.security.spec.ECGenParameterSpec
import java.util.Base64

class MainActivity : Activity() {
    private val alias = "AVO_OTA_SIGNING_P256_V1"
    private val ks = KeyStore.getInstance("AndroidKeyStore")
    private lateinit var status: TextView
    private var firmware: ByteArray? = null
    private var manifest: ByteArray? = null
    private var signature: ByteArray? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ks.load(null)
        val panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32,48,32,24) }
        status = TextView(this).apply { text = "AVO Signer · versión experimental"; textSize = 18f }
        panel.addView(status)
        fun button(title: String, action: () -> Unit) { panel.addView(Button(this).apply { text=title; setOnClickListener { action() } }) }
        button("1. Crear clave privada") { createKey() }
        button("2. Compartir clave pública") { exportPublicKey() }
        button("3. Seleccionar BIN") {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
            }, 100)
        }
        button("4. Autorizar y firmar") { authorize() }
        button("5. Compartir firma") { exportSignature() }
        setContentView(ScrollView(this).apply { addView(panel) })
    }
    private fun createKey() = try {
        if (ks.containsAlias(alias)) { status.text="Clave existente; no se sobrescribe"; return }
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC,"AndroidKeyStore")
        generator.initialize(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationValidityDurationSeconds(30)
            .build())
        generator.generateKeyPair()
        status.text="Clave creada en Android Keystore. Protección hardware pendiente de comprobar."
    } catch (e:Exception) { status.text="Error creando clave: ${e.message}" }
    private fun exportPublicKey() = try {
        val pub=ks.getCertificate(alias)?.publicKey?.encoded ?: error("Crea primero la clave")
        val json=JSONObject().put("alg","ES256").put("kid",alias)
            .put("public_key_spki_base64",Base64.getEncoder().encodeToString(pub)).toString(2)
        share(json)
    } catch (e:Exception) { status.text="Error: ${e.message}" }
    private fun authorize() {
        if (firmware==null) { status.text="Selecciona un BIN"; return }
        if (!ks.containsAlias(alias)) { status.text="Primero crea una clave"; return }
        val km=getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        if (!km.isDeviceSecure) { status.text="Activa bloqueo seguro del teléfono"; return }
        val intent=km.createConfirmDeviceCredentialIntent("Autorizar firma AVO","Confirma tu identidad para firmar")
        if (intent==null) { status.text="Autenticación no disponible"; return }
        startActivityForResult(intent,101)
    }
    private fun sign() = try {
        val bin=firmware ?: error("Falta BIN")
        val hash=MessageDigest.getInstance("SHA-256").digest(bin).joinToString("") { "%02x".format(it) }
        val raw=JSONObject().put("schema","avo-ota-manifest-v1")
            .put("target","AVO_CHEST_WAVESHARE_ESP32S3")
            .put("filename","firmware.bin").put("size",bin.size)
            .put("sha256",hash).put("alg","ES256").put("kid",alias)
            .toString().toByteArray(Charsets.UTF_8)
        val signer=Signature.getInstance("SHA256withECDSA")
        signer.initSign(ks.getKey(alias,null) as PrivateKey)
        signer.update(raw)
        manifest=raw; signature=signer.sign()
        status.text="Firma creada; exporta el paquete de firma. SHA-256: $hash"
    } catch (e:Exception) { status.text="Error de firma: ${e.message}" }
    private fun exportSignature() = try {
        val m=manifest ?: error("Firma primero")
        val s=signature ?: error("Firma primero")
        share(JSONObject().put("format","avo-ota-signed-envelope-v1")
            .put("manifest_utf8_base64",Base64.getEncoder().encodeToString(m))
            .put("signature_der_base64",Base64.getEncoder().encodeToString(s)).toString(2))
    } catch (e:Exception) { status.text="Error: ${e.message}" }
    private fun share(text:String) {
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type="text/plain"; putExtra(Intent.EXTRA_TEXT,text)
        },"Exportar AVO"))
    }
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (resultCode!=RESULT_OK) return
        if (requestCode==100) try {
            val uri=data?.data ?: error("No hay archivo")
            firmware=contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("Lectura fallida")
            manifest=null; signature=null
            status.text="Firmware cargado: ${firmware!!.size} bytes"
        } catch(e:Exception) { status.text="Error leyendo BIN: ${e.message}" }
        if (requestCode==101) sign()
    }
}
