package org.avoperformance.signer

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.widget.*
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.*
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Offline firmware signing tool. Public key MUST be pinned by OTA verifier. */
class MainActivity : Activity() {
    private val alias = "AVO_OTA_SIGNING_P256_V1"
    private val ks = KeyStore.getInstance("AndroidKeyStore")
    private lateinit var status: TextView
    private lateinit var version: EditText
    private var firmware: ByteArray? = null
    private var output: ByteArray? = null
    private val maxFirmwareBytes = 6 * 1024 * 1024

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ks.load(null)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32,48,32,32) }
        layout.addView(TextView(this).apply { text="AVO SIGNER"; textSize=25f })
        status = TextView(this).apply { text="Sin clave ni firmware seleccionado"; textSize=16f }
        layout.addView(status)
        version = EditText(this).apply { hint="Versión, por ejemplo 3.5.6"; setSingleLine(true) }
        layout.addView(version)
        fun addButton(label:String, callback:()->Unit) { layout.addView(Button(this).apply { text=label; setOnClickListener { callback() } }) }
        addButton("1 · Crear clave privada") { createKey() }
        addButton("2 · Exportar clave pública") { exportPublicKey() }
        addButton("3 · Seleccionar firmware BIN") {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type="*/*"; addCategory(Intent.CATEGORY_OPENABLE)
            }, 100)
        }
        addButton("4 · Autorizar y firmar") { authorize() }
        addButton("5 · Guardar paquete OTA firmado") {
            if (output==null) { status.text="Primero firma el firmware"; return@addButton }
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                type="application/zip"; addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_TITLE,"AVO_CHEST_SIGNED_OTA.zip")
            },102)
        }
        addButton("Diagnóstico de seguridad de la clave") { diagnose() }
        setContentView(ScrollView(this).apply { addView(layout) })
    }
    private fun createKey() = try {
        if (ks.containsAlias(alias)) { status.text="Clave ya existente. No se ha sustituido."; return }
        val gen=KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC,"AndroidKeyStore")
        gen.initialize(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationValidityDurationSeconds(30)
            .build())
        gen.generateKeyPair()
        status.text="Clave creada. Exporta y conserva la clave pública. Revisa diagnóstico."
    } catch(e:Exception) { status.text="Error: ${e.message}" }
    private fun diagnose() = try {
        val key=ks.getKey(alias,null) as? PrivateKey ?: error("Primero crea la clave")
        val factory=KeyFactory.getInstance(key.algorithm,"AndroidKeyStore")
        val info=factory.getKeySpec(key,KeyInfo::class.java)
        status.text=if(info.isInsideSecureHardware)
            "Clave protegida por hardware Android Keystore"
        else "ATENCIÓN: Android no confirma protección hardware para esta clave"
    } catch(e:Exception) { status.text="Diagnóstico fallido: ${e.message}" }
    private fun exportPublicKey() = try {
        val pub=ks.getCertificate(alias)?.publicKey?.encoded ?: error("No hay clave")
        val json=JSONObject().put("format","avo-public-key-v1").put("alg","ES256")
            .put("kid",alias).put("spki_der_base64",Base64.getEncoder().encodeToString(pub)).toString(2)
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type="text/plain"; putExtra(Intent.EXTRA_TEXT,json)
        },"Exportar clave pública"))
    } catch(e:Exception) { status.text="Error: ${e.message}" }
    private fun authorize() {
        if(firmware==null) { status.text="Selecciona firmware"; return }
        if(!ks.containsAlias(alias)) { status.text="Crea la clave primero"; return }
        val v=version.text.toString().trim()
        if(!Regex("[0-9]+\\.[0-9]+\\.[0-9]+([.-][A-Za-z0-9]+)*").matches(v)) {
            status.text="Indica una versión válida (ejemplo 3.5.6)"; return
        }
        val km=getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        if(!km.isDeviceSecure) { status.text="Activa PIN o biometría en Android"; return }
        val auth=km.createConfirmDeviceCredentialIntent("Firmar firmware AVO","Confirma la identidad para autorizar la firma")
        if(auth==null) { status.text="Autenticación no disponible"; return }
        startActivityForResult(auth,101)
    }
    private fun sign() = try {
        val bin=firmware ?: error("Falta BIN")
        val hash=MessageDigest.getInstance("SHA-256").digest(bin).joinToString("") { "%02x".format(it) }
        val manifest=JSONObject().put("schema","avo-ota-manifest-v1")
            .put("target","AVO_CHEST_WAVESHARE_ESP32S3")
            .put("version",version.text.toString().trim())
            .put("firmware","firmware.bin").put("size",bin.size)
            .put("sha256",hash).put("alg","ES256").put("kid",alias)
            .toString().toByteArray(Charsets.UTF_8)
        val key=ks.getKey(alias,null) as PrivateKey
        val signer=Signature.getInstance("SHA256withECDSA")
        signer.initSign(key); signer.update(manifest)
        val sig=signer.sign() // ASN.1 DER; verifier must use same encoding
        val check=Signature.getInstance("SHA256withECDSA")
        check.initVerify(ks.getCertificate(alias).publicKey); check.update(manifest)
        check.verify(sig) || error("La verificación local de firma falló")
        output=ByteArrayOutputStream().use { bytes ->
            ZipOutputStream(bytes).use { zip ->
                fun entry(name:String,data:ByteArray) {
                    zip.putNextEntry(ZipEntry(name)); zip.write(data); zip.closeEntry()
                }
                entry("firmware.bin",bin)
                entry("manifest.json",manifest)
                entry("manifest.sig",sig)
            }
            bytes.toByteArray()
        }
        status.text="Paquete firmado y verificado. SHA-256: $hash. Guarda el ZIP."
    } catch(e:Exception) { output=null; status.text="Error al firmar: ${e.message}" }
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(resultCode!=RESULT_OK) return
        try {
            when(requestCode) {
                100 -> {
                    val uri=data?.data ?: error("No se seleccionó archivo")
                    val length=contentResolver.openFileDescriptor(uri,"r")?.use { it.statSize } ?: -1L
                    if(length>maxFirmwareBytes) error("BIN demasiado grande")
                    val bytes=contentResolver.openInputStream(uri)?.use { stream ->
                        val out=ByteArrayOutputStream()
                        val buf=ByteArray(8192)
                        while(true) {
                            val n=stream.read(buf)
                            if(n<0) break
                            if(out.size()+n>maxFirmwareBytes) error("BIN supera 6 MiB")
                            out.write(buf,0,n)
                        }
                        out.toByteArray()
                    } ?: error("No se pudo leer")
                    if(bytes.size<1024) error("Archivo demasiado pequeño para un firmware")
                    firmware=bytes; output=null
                    status.text="BIN seleccionado: ${bytes.size} bytes"
                }
                101 -> sign()
                102 -> {
                    val uri=data?.data ?: error("Destino inválido")
                    contentResolver.openOutputStream(uri,"w")?.use { it.write(output ?: error("No hay ZIP")) }
                        ?: error("No se pudo guardar")
                    status.text="Paquete OTA firmado guardado"
                }
            }
        } catch(e:Exception) { status.text="Error: ${e.message}" }
    }
}
