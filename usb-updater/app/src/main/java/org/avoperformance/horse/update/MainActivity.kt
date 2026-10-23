package org.avoperformance.horse.update

import android.app.Activity
import android.app.AlertDialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AVO PERFORMANCE HORSE UPDATE — USB programmer for the AVO chest watch (ESP32-S3).
 * All USB work runs on one worker thread; the UI only renders state.
 */
class MainActivity : Activity() {
    private val selectFirmware = 101
    private val selectUpdate = 102

    private lateinit var usb: UsbManager
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var cancel = AtomicBoolean(false)

    // state
    private var firmware: FirmwareImage.Result? = null
    private var firmwareName: String = ""
    private var snapshot: DeviceProbe.Snapshot? = null
    private var planText: String? = null
    private var planError: String? = null

    // views
    private lateinit var usbState: TextView
    private lateinit var permissionState: TextView
    private lateinit var chipState: TextView
    private lateinit var bootloaderState: TextView
    private lateinit var flashState: TextView
    private lateinit var securityState: TextView
    private lateinit var slotsState: TextView
    private lateinit var firmwareState: TextView
    private lateinit var planState: TextView
    private lateinit var stepState: TextView
    private lateinit var progress: ProgressBar
    private lateinit var resultState: TextView
    private lateinit var logView: TextView
    private lateinit var readButton: Button
    private lateinit var selectButton: Button
    private lateinit var installButton: Button
    private lateinit var cancelButton: Button
    private lateinit var autoBoot: CheckBox
    private val log = StringBuilder()

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_DETACHED -> if (!busy.get()) { snapshot = null; planText = null }
            }
            refreshUsb()
            refreshButtons()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        usb = getSystemService(USB_SERVICE) as UsbManager
        val filter = IntentFilter().apply {
            addAction(USB_PERMISSION_ACTION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(usbReceiver, filter)
        buildUi()
        refreshUsb()
        refreshFirmware()
        refreshButtons()
    }

    // ------------------------------------------------------------------ UI construction

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun section(root: LinearLayout, title: String) {
        root.addView(TextView(this).apply {
            text = title; textSize = 13f; setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.rgb(0x8A, 0x5A, 0x00)); setPadding(0, dp(20), 0, dp(6))
            letterSpacing = 0.08f
        })
    }

    private fun row(root: LinearLayout): TextView = TextView(this).apply {
        textSize = 15f; setPadding(0, dp(2), 0, dp(2)); root.addView(this)
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(20), dp(16), dp(24)) }
        root.addView(TextView(this).apply {
            text = "AVO PERFORMANCE HORSE UPDATE"; textSize = 22f; setTypeface(typeface, Typeface.BOLD)
        })
        root.addView(TextView(this).apply {
            text = "Programador USB del reloj de pecho · V${appVersion()}"; textSize = 13f; setTextColor(Color.GRAY)
        })

        section(root, "ESTADO DEL RELOJ")
        usbState = row(root); permissionState = row(root); chipState = row(root)
        bootloaderState = row(root); flashState = row(root); securityState = row(root)
        slotsState = row(root).apply { textSize = 13f; typeface = Typeface.MONOSPACE }
        autoBoot = CheckBox(this).apply {
            text = "Entrar en modo bootloader automáticamente por USB (reinicia el reloj)"; isChecked = true
            root.addView(this)
        }
        readButton = Button(this).apply { text = "LEER RELOJ"; setOnClickListener { readWatch() } }
        root.addView(readButton)

        section(root, "FIRMWARE")
        selectButton = Button(this).apply { text = "SELECCIONAR FIRMWARE BIN"; setOnClickListener { choose("*/*", selectFirmware) } }
        root.addView(selectButton)
        firmwareState = row(root).apply { setTextIsSelectable(true) }

        section(root, "INSTALACIÓN")
        planState = row(root).apply { textSize = 13f }
        installButton = Button(this).apply {
            text = "INSTALAR FIRMWARE POR USB"; textSize = 17f; setTypeface(typeface, Typeface.BOLD)
            setOnClickListener { confirmInstall() }
        }
        root.addView(installButton)
        stepState = row(root).apply { setTypeface(typeface, Typeface.BOLD) }
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100; progress = 0; visibility = View.GONE; root.addView(this)
        }
        resultState = row(root)
        cancelButton = Button(this).apply {
            text = "CANCELAR"; visibility = View.GONE
            setOnClickListener { cancel.set(true); stepState.text = "Cancelando… (si se está activando, se termina primero de forma segura)" }
        }
        root.addView(cancelButton)

        section(root, "REGISTRO")
        logView = row(root).apply { textSize = 11f; typeface = Typeface.MONOSPACE; setTextIsSelectable(true) }

        section(root, "APLICACIÓN")
        root.addView(Button(this).apply {
            text = "Actualizar esta aplicación desde APK"
            setOnClickListener { choose("application/vnd.android.package-archive", selectUpdate) }
        })
        root.addView(TextView(this).apply {
            textSize = 12f; setTextColor(Color.GRAY)
            text = "Seguridad: solo se escribe el slot OTA de destino y una copia de otadata. Nunca se tocan el bootloader, " +
                "la tabla de particiones, NVS, blackbox ni coredump. Con Secure Boot o Flash Encryption activos la instalación se bloquea."
        })
        setContentView(ScrollView(this).apply { addView(root) })
    }

    private fun appVersion(): String = runCatching {
        @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0).versionName
    }.getOrNull() ?: "?"

    // ------------------------------------------------------------------ rendering

    private fun ok(b: Boolean) = if (b) "✔" else "✖"

    private fun refreshUsb() {
        val device = UsbCdcLink.findWatch(usb)
        usbState.text = "USB: " + if (device == null) "✖ desconectado (conecta el reloj con un cable USB-C de datos)"
            else "✔ conectado (VID %04X · PID %04X%s)".format(device.vendorId, device.productId,
                if (device.productId == USB_JTAG_SERIAL_PID) " · USB-Serial/JTAG" else "")
        permissionState.text = "Permiso USB: " + when {
            device == null -> "—"
            usb.hasPermission(device) -> "✔ concedido"
            else -> "pendiente (se pedirá al leer el reloj)"
        }
        val s = snapshot
        if (s == null) {
            chipState.text = "Chip: sin leer"
            bootloaderState.text = "Bootloader: sin comprobar"
            flashState.text = "Memoria flash: sin leer"
            securityState.text = "Seguridad: sin comprobar"
            slotsState.text = ""
        } else {
            chipState.text = "Chip: ✔ ESP32-S3 revisión ${s.chipRevisionText}"
            bootloaderState.text = "Bootloader: ✔ ROM disponible · bootloader de segunda etapa " +
                if (s.bootloaderValid) "válido" else "✖ NO válido"
            flashState.text = "Memoria flash: " + (s.physicalFlash?.let { "${it shr 20} MB físicos" } ?: "desconocida") +
                (s.configuredFlash?.let { " · ${it shr 20} MB configurados" } ?: "")
            val sec = s.security
            securityState.text = "Seguridad: " + if (!sec.secureBoot && !sec.flashEncryption && !sec.secureDownload)
                "✔ sin Secure Boot ni Flash Encryption" else
                "✖ Secure Boot ${if (sec.secureBoot) "ACTIVO" else "no"} · Flash Encryption ${if (sec.flashEncryption) "ACTIVO" else "no"}"
            slotsState.text = s.slots.joinToString("\n") {
                (if (s.bootSlot == it.index) "▶ " else "  ") + it.label + ": " +
                    (if (!it.headerValid) "vacío/dañado" else it.description ?: "imagen válida")
            }
        }
    }

    private fun refreshFirmware() {
        val f = firmware
        firmwareState.text = if (f == null) "Ningún archivo seleccionado." else buildString {
            append("Nombre: $firmwareName\n")
            append("Tamaño: %,d bytes\n".format(f.bytes))
            append("Versión: ${f.info?.label?.ifBlank { null } ?: "no detectada"}\n")
            f.info?.idfVersion?.takeIf { it.isNotBlank() }?.let { append("ESP-IDF: $it\n") }
            append("SHA-256: ${f.sha256}\n")
            append((if (f.validHeader) "✔ " else "✖ ") + f.reason)
        }
        updatePlan()
    }

    private fun updatePlan() {
        val s = snapshot
        val info = firmware?.info
        planText = null; planError = null
        if (s != null && info != null) {
            try { planText = InstallPlanner.plan(s, info).summary().joinToString("\n") }
            catch (e: UpdateException) { planError = e.userMessage }
        }
        planState.text = when {
            planError != null -> "✖ $planError"
            planText != null -> planText
            firmware?.validHeader != true -> "Selecciona un firmware válido."
            s == null -> "Pulsa LEER RELOJ para comprobar particiones, slot activo y seguridad."
            else -> ""
        }
    }

    private fun refreshButtons() {
        val idle = !busy.get()
        readButton.isEnabled = idle && UsbCdcLink.findWatch(usb) != null
        selectButton.isEnabled = idle
        installButton.isEnabled = idle && planText != null && firmware?.validHeader == true &&
            UsbCdcLink.findWatch(usb) != null
        cancelButton.visibility = if (idle) View.GONE else View.VISIBLE
    }

    private fun appendLog(line: String) {
        log.append(line).append('\n')
        if (log.length > 20000) log.delete(0, log.length - 20000)
        logView.text = log
    }

    private fun ui(block: () -> Unit) = runOnUiThread { if (!isDestroyed) block() }

    // ------------------------------------------------------------------ operations

    private fun listener() = object : Installer.Listener {
        override fun onStep(step: Installer.Step, percent: Int?, detail: String) = ui {
            stepState.text = step.text + (percent?.let { " · $it %" } ?: "") + if (detail.isNotBlank()) "\n$detail" else ""
            progress.visibility = View.VISIBLE
            progress.isIndeterminate = percent == null
            if (percent != null) progress.progress = percent
        }
        override fun onLog(line: String) = ui { appendLog(line) }
    }

    private fun port() = AndroidDevicePort(this, usb) { ui { appendLog("Acepta el permiso USB en la pantalla del teléfono.") } }

    private fun runExclusive(task: () -> Unit) {
        if (!busy.compareAndSet(false, true)) return
        cancel = AtomicBoolean(false)
        resultState.text = ""
        refreshButtons()
        worker.execute {
            try { task() } finally {
                busy.set(false)
                ui { progress.isIndeterminate = false; refreshUsb(); refreshButtons() }
            }
        }
    }

    private fun readWatch() = runExclusive {
        val auto = autoBoot.isChecked
        try {
            val snap = Installer(port(), listener(), cancel).probe(auto)
            ui {
                snapshot = snap
                snap.report().forEach(::appendLog)
                stepState.text = "Reloj leído correctamente."
                progress.visibility = View.GONE
                updatePlan()
            }
        } catch (e: Exception) {
            ui { stepState.text = "✖ " + message(e); progress.visibility = View.GONE; appendLog("Error: ${message(e)}") }
        }
    }

    private fun confirmInstall() {
        val plan = planText ?: return
        val f = firmware ?: return
        AlertDialog.Builder(this)
            .setTitle("¿Instalar ${f.info?.label ?: firmwareName}?")
            .setMessage("$plan\n\nNo desconectes el reloj ni cierres la aplicación hasta que termine. " +
                "El reloj se reiniciará varias veces.")
            .setPositiveButton("INSTALAR") { _, _ -> install() }
            .setNegativeButton("Cancelar", null)
            .show()
    }

    private fun install() {
        val image = firmware?.image ?: return
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val auto = autoBoot.isChecked
        runExclusive {
            try {
                val out = Installer(port(), listener(), cancel).install(image, Installer.Options(autoBootloader = auto))
                ui {
                    resultState.setTextColor(if (out.bootConfirmed) Color.rgb(0, 120, 0) else Color.rgb(170, 90, 0))
                    resultState.text = (if (out.bootConfirmed) "✔ " else "⚠ ") + out.message
                    if (!out.bootConfirmed) stepState.text = "Arranque no confirmado"
                    if (out.usbText.isNotBlank()) appendLog("Salida USB del firmware:\n" + out.usbText.takeLast(1500))
                    snapshot = null; updatePlan()
                }
            } catch (e: Exception) {
                ui {
                    resultState.setTextColor(Color.rgb(170, 0, 0))
                    resultState.text = "✖ " + message(e)
                    stepState.text = "Instalación no completada"
                    appendLog("Error: ${message(e)}")
                    snapshot = null; updatePlan()
                }
            } finally {
                ui { window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
            }
        }
    }

    private fun message(e: Exception) = (e as? UpdateException)?.userMessage ?: (e.message ?: e.javaClass.simpleName)

    // ------------------------------------------------------------------ file selection

    private fun choose(type: String, code: Int) {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            this.type = type
        }, code)
    }

    private fun displayName(uri: Uri): String = runCatching {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment ?: "firmware.bin"

    @Deprecated("Legacy activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        if (requestCode == selectFirmware) {
            val name = displayName(uri)
            firmwareState.text = "Analizando $name…"
            runExclusive {
                val result = try {
                    contentResolver.openInputStream(uri)?.let(FirmwareImage::inspect) ?: error("No se pudo abrir el archivo")
                } catch (e: Exception) {
                    FirmwareImage.Result(0, "—", false, null, e.message ?: "No se pudo leer el archivo")
                }
                ui { firmware = result; firmwareName = name; refreshFirmware() }
            }
        } else if (requestCode == selectUpdate) {
            try {
                startActivity(Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    this.data = uri
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                })
            } catch (e: Exception) { appendLog("Instalador: ${e.message}") }
        }
    }

    override fun onDestroy() {
        cancel.set(true) // deferred automatically while otadata is being written
        unregisterReceiver(usbReceiver)
        worker.shutdown()
        super.onDestroy()
    }
}
