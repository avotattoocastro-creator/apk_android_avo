package org.avoperformance.signer

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.widget.*
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.WindowManager
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
    private lateinit var identityState: TextView
    private var page = "home"
    private lateinit var version: EditText
    private var firmware: ByteArray? = null
    private var output: ByteArray? = null
    private val maxFirmwareBytes = 6 * 1024 * 1024

    private val navy = Color.rgb(12,25,41)
    private val tile = Color.rgb(24,48,71)
    private val blue = Color.rgb(118,185,255)
    private val mint = Color.rgb(70,220,161)
    private fun dp(n:Int)=(n*resources.displayMetrics.density).toInt()
    private fun bg(color:Int, radius:Int=16)=GradientDrawable().apply {
        setColor(color); cornerRadius=dp(radius).toFloat()
    }
    private fun label(t:String, size:Float, color:Int=Color.WHITE, bold:Boolean=false)=TextView(this).apply {
        text=t; textSize=size; setTextColor(color)
        if(bold) setTypeface(null,Typeface.BOLD)
    }
    private fun action(title:String, options:Array<String>, callbacks:Array<()->Unit>) {
        android.app.AlertDialog.Builder(this).setTitle(title).setItems(options) { _,which -> callbacks[which]() }.show()
    }
    private fun pickFirmware() {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type="*/*"; addCategory(Intent.CATEGORY_OPENABLE)
        },100)
    }
    private fun savePackage() {
        if(output==null) { status.text="Primero firma el firmware"; return }
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            type="application/zip"; addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_TITLE,"AVO_CHEST_SIGNED_OTA.zip")
        },102)
    }
    private fun unavailable(feature:String) {
        android.app.AlertDialog.Builder(this).setTitle(feature)
            .setMessage("Esta función está pendiente de implementación y validación. No se ha activado una protección inexistente.")
            .setPositiveButton("Entendido",null).show()
    }
    private fun refreshIdentity() {
        if(::identityState.isInitialized) identityState.text =
            if(ks.containsAlias(alias)) "Clave local disponible · Sin respaldo"
            else "Sin clave oficial activada"
    }
    private fun showKeys() {
        page="keys"
        val p=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL
            setPadding(dp(18),dp(24),dp(18),dp(24))
            setBackgroundColor(navy)
            isFocusableInTouchMode=true
            requestFocus()
        }
        fun textLine(t:String,size:Float,color:Int=Color.WHITE): TextView =
            label(t,size,color).apply { setPadding(0,dp(8),0,dp(12)) }
        p.addView(textLine("‹  Volver",18f,blue).apply { setOnClickListener { showHome() } })
        p.addView(textLine("Mis claves",27f))
        val state=textLine(if(ks.containsAlias(alias)) "Clave Keystore disponible" else "Sin clave creada",17f,mint)
        p.addView(state)
        p.addView(textLine("Las claves Keystore no permiten exportar la parte privada. La recuperación cifrada requerirá una clave nueva.",14f,Color.LTGRAY))
        fun item(title:String, detail:String, callback:()->Unit) {
            val card=LinearLayout(this).apply {
                orientation=LinearLayout.VERTICAL
                setPadding(dp(16),dp(15),dp(16),dp(15))
                background=bg(tile,16)
                setOnClickListener { callback() }
            }
            card.addView(textLine(title,17f))
            card.addView(textLine(detail,13f,Color.LTGRAY))
            p.addView(card,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(12) })
        }
        item("Crear clave Keystore","Protección local no exportable") {
            createKey()
            state.text=if(ks.containsAlias(alias)) "Clave Keystore disponible" else "Sin clave creada"
        }
        item("Exportar clave pública","Compartir clave pública SPKI JSON") { exportPublicKey() }
        item("Diagnóstico de seguridad","Comprobar protección hardware") { diagnose() }
        item("Importar clave · Pendiente","Recuperación cifrada en desarrollo") { unavailable("Importar clave") }
        item("Exportar copia privada · Pendiente","No disponible para claves Keystore") { unavailable("Exportar copia privada") }
        status= textLine("No compartas ninguna clave privada.",13f,Color.LTGRAY)
        p.addView(status)
        setContentView(ScrollView(this).apply { addView(p) })
    }
    private fun showHome() {
        page="home"
        buildDashboard()
    }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if(page!="home") showHome() else super.onBackPressed()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ks.load(null)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
        buildDashboard()
    }
    private fun buildDashboard() {
        super.onCreate(savedInstanceState)
        window.statusBarColor=navy
        window.navigationBarColor=navy
        val root=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL; setPadding(dp(14),dp(18),dp(14),dp(18))
            background=bg(navy,24)
        }
        root.addView(label("AVO PERFORMANCE",12f,Color.LTGRAY))
        root.addView(label("AVO PERFOMANCE\nSINGER KEY",26f,Color.WHITE,true).apply {
            setPadding(0,dp(5),0,dp(18))
        })
        val identity=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL; setPadding(dp(16),dp(16),dp(16),dp(16))
            background=bg(tile,18)
        }
        identity.addView(label("♢  Identidad de firma",20f,Color.WHITE,true))
        identityState=label(if(ks.containsAlias(alias)) "Clave local disponible · Sin respaldo" else "Sin clave oficial activada",18f).apply {
            setPadding(0,dp(14),0,dp(6))
        })
        identity.addView(identityState)
        status=label("Configura y respalda tu clave antes de publicar firmware",14f,Color.LTGRAY)
        identity.addView(status)
        root.addView(identity)
        val space=View(this).apply { layoutParams=LinearLayout.LayoutParams(1,dp(14)) }
        root.addView(space)
        val items=listOf(
            Triple("⚿","Mis claves",0),Triple("▤","Firmar BIN",1),
            Triple("⬡","Verificar OTA",2),Triple("⬡","Paquetes",3),
            Triple("◴","Historial",4),Triple("⚙","Configuración",5)
        )
        val grid=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL }
        items.chunked(2).forEach { pair ->
            val row=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL }
            pair.forEach { (symbol,name,id) ->
                val cell=LinearLayout(this).apply {
                    orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER
                    setPadding(dp(8),dp(18),dp(8),dp(18))
                    background=bg(tile,16)
                    isClickable=true
                    setOnClickListener {
                        when(id) {
                            0 -> showKeys()
                            1 -> action("Firmar BIN",arrayOf("Seleccionar firmware BIN","Autorizar y firmar","Guardar ZIP firmado"),arrayOf(
                                {pickFirmware()},{authorize()},{savePackage()}
                            ))
                            2 -> unavailable("Verificar OTA")
                            3 -> unavailable("Paquetes")
                            4 -> unavailable("Historial")
                            5 -> unavailable("Configuración")
                        }
                    }
                }
                cell.addView(label(symbol,28f,blue,true).apply { gravity=Gravity.CENTER })
                cell.addView(label(name,15f,Color.WHITE,true).apply {
                    gravity=Gravity.CENTER; setPadding(0,dp(9),0,0)
                })
                row.addView(cell,LinearLayout.LayoutParams(0,dp(116),1f).apply {
                    setMargins(dp(4),dp(4),dp(4),dp(4))
                })
            }
            grid.addView(row)
        }
        root.addView(grid)
        version=EditText(this).apply {
            hint="Versión de firmware (ej. 3.5.6)"
            setHintTextColor(Color.LTGRAY); setTextColor(Color.WHITE)
            setSingleLine(true)
        }
        // Version is edited only on the signing workflow; do not autofocus the dashboard.
        version.isFocusableInTouchMode=false
        root.addView(version)
        root.addView(label("Las funciones aún no implementadas aparecen identificadas como pendientes.",12f,Color.LTGRAY).apply {
            gravity=Gravity.CENTER; setPadding(dp(6),dp(14),dp(6),0)
        })
        setContentView(ScrollView(this).apply {
            isFocusableInTouchMode=true; requestFocus()
            setBackgroundColor(navy); addView(root)
        })
    }
    private fun createKey() { try {
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
        refreshIdentity()
    } catch(e:Exception) { status.text="Error: ${e.message}" } }
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
