package org.avoperformance.horse.update

import android.app.Activity
import android.app.AlertDialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AVO PERFORMANCE HORSE UPDATE — USB programmer and reader for AVO ESP32-S3 modules.
 * Install: chest watch only. Read / backup: any ESP32-S3 (chest by USB-Serial/JTAG, back module by CP2102).
 * All USB work runs on one worker thread; the UI only renders state.
 */
class MainActivity : Activity() {
    private val selectFirmware = 101
    private val selectUpdate = 102
    private val saveFile = 103

    // AVO 2.0 palette (same as the boot screen of the training app)
    private val cBg = Color.parseColor("#030406")
    private val cSurface = Color.parseColor("#101014")
    private val cSurface2 = Color.parseColor("#1A1B20")
    private val cLine = Color.parseColor("#2A2B31")
    private val cRed = Color.parseColor("#ED122A")
    private val cRedDark = Color.parseColor("#B71625")
    private val cRedLight = Color.parseColor("#FF495A")
    private val cText = Color.parseColor("#F2F2F4")
    private val cDim = Color.parseColor("#9C9DA4")
    private val cSilver = Color.parseColor("#C9CBD1")
    private val cOk = Color.parseColor("#52DD40")
    private val cWarn = Color.parseColor("#FFC42C")
    private val cBad = Color.parseColor("#FF3945")
    private val cGrey = Color.parseColor("#93949B")

    private lateinit var usb: UsbManager
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var cancel = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())

    // state
    private var firmware: FirmwareImage.Result? = null
    private var firmwareName: String = ""
    private var snapshot: DeviceProbe.Snapshot? = null
    private var planText: String? = null
    private var planError: String? = null
    private var lastInfo: FlashReader.Info? = null
    private var lastReport: String? = null
    private var pendingSave: Pair<File, String>? = null

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
    private lateinit var readerState: TextView
    private lateinit var logView: TextView
    private lateinit var readButton: Button
    private lateinit var selectButton: Button
    private lateinit var installButton: Button
    private lateinit var cancelButton: Button
    private lateinit var infoButton: Button
    private lateinit var readFwButton: Button
    private lateinit var readPartButton: Button
    private lateinit var backupButton: Button
    private lateinit var reportButton: Button
    private lateinit var autoBoot: CheckBox
    // ---- Serial monitor (V2.2): what the watch prints over USB (boot, reboot reason, memory)
    private lateinit var monitorView: TextView
    private lateinit var monitorStartButton: Button
    private lateinit var monitorResetButton: Button
    private lateinit var monitorStopButton: Button
    private lateinit var monitorSaveButton: Button
    private val monitorRunning = AtomicBoolean(false)
    private val monitorLog = StringBuilder()
    @Volatile private var monitorDirty = false
    private lateinit var root: FrameLayout
    private var boot: View? = null
    private var bootRows: LinearLayout? = null
    private val log = StringBuilder()

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_DETACHED -> if (!busy.get()) { snapshot = null; planText = null }
            }
            refreshUsb(); refreshButtons(); refreshBoot()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = cBg
        window.navigationBarColor = cBg
        usb = getSystemService(USB_SERVICE) as UsbManager
        val filter = IntentFilter().apply {
            addAction(USB_PERMISSION_ACTION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(usbReceiver, filter)
        root = FrameLayout(this).apply { setBackgroundColor(cBg) }
        root.addView(buildUi())
        if (savedInstanceState == null) showBoot()
        setContentView(root)
        refreshUsb(); refreshFirmware(); refreshButtons()
    }

    // ------------------------------------------------------------------ styling helpers

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun rounded(fill: Int, stroke: Int? = null, radius: Int = 16) = GradientDrawable().apply {
        setColor(fill); cornerRadius = dp(radius).toFloat(); stroke?.let { setStroke(dp(1), it) }
    }

    private fun cardBg() = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(Color.parseColor("#15161B"), Color.parseColor("#0D0D11"))).apply {
        cornerRadius = dp(16).toFloat(); setStroke(dp(1), cLine)
    }

    private fun lp(top: Int = 0, bottom: Int = 0) = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        .apply { topMargin = dp(top); bottomMargin = dp(bottom) }

    /** Card with the red accent bar + silver title, like AvoCard in the training app. */
    private fun card(parent: LinearLayout, title: String): LinearLayout {
        val c = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; background = cardBg(); setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        val head = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        head.addView(View(this).apply { background = rounded(cRed, radius = 2) }, LinearLayout.LayoutParams(dp(3), dp(14)))
        head.addView(TextView(this).apply {
            text = title.uppercase(); setTextColor(cSilver); textSize = 12f; letterSpacing = 0.1f
            setTypeface(typeface, Typeface.BOLD); setPadding(dp(8), 0, 0, 0)
        })
        c.addView(head, lp(bottom = 10))
        parent.addView(c, lp(top = 5, bottom = 5))
        return c
    }

    private fun row(parent: LinearLayout, size: Float = 15f, color: Int = cText): TextView = TextView(this).apply {
        textSize = size; setTextColor(color); setPadding(0, dp(2), 0, dp(2)); parent.addView(this)
    }

    private fun primary(parent: LinearLayout, label: String, onClick: () -> Unit): Button = Button(this).apply {
        text = label; isAllCaps = true; setTextColor(Color.WHITE); textSize = 15f; setTypeface(typeface, Typeface.BOLD)
        background = rounded(cRed, radius = 26); stateListAnimator = null
        setOnClickListener { onClick() }
        parent.addView(this, lp(top = 8).apply { height = dp(50) })
    }

    private fun secondary(parent: LinearLayout, label: String, onClick: () -> Unit): Button = Button(this).apply {
        text = label; isAllCaps = true; setTextColor(cText); textSize = 14f; setTypeface(typeface, Typeface.BOLD)
        background = rounded(cSurface2, cLine, 26); stateListAnimator = null
        setOnClickListener { onClick() }
        parent.addView(this, lp(top = 8).apply { height = dp(46) })
    }

    private fun Button.enable(on: Boolean) { isEnabled = on; alpha = if (on) 1f else 0.38f }

    // ------------------------------------------------------------------ start screen

    private fun bootStatus(): List<Triple<String, String, Int>> {
        val device = UsbLinks.find(usb)
        val stubOk = runCatching { assets.open("stub/esp32s3.json").close() }.isSuccess
        val hostOk = packageManager.hasSystemFeature("android.hardware.usb.host")
        return listOf(
            Triple("Interfaz", "OK", cOk),
            Triple("USB OTG", if (hostOk) "Disponible" else "No disponible", if (hostOk) cOk else cBad),
            Triple("Dispositivo", device?.let { UsbLinks.typeOf(it)?.text ?: "Conectado" } ?: "Esperando conexión", if (device != null) cOk else cWarn),
            Triple("Permiso USB", when { device == null -> "—"; usb.hasPermission(device) -> "Concedido"; else -> "Se pedirá al usar" },
                when { device == null -> cGrey; usb.hasPermission(device) -> cOk; else -> cWarn }),
            Triple("Instalador ESP32-S3", "Listo", cOk),
            Triple("Lectura rápida", if (stubOk) "Stub Espressif listo" else "No disponible", if (stubOk) cOk else cBad),
            Triple("Almacenamiento", if (cacheDir.canWrite()) "OK" else "No disponible", if (cacheDir.canWrite()) cOk else cBad),
        )
    }

    private fun showBoot() {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(cBg) }
        col.addView(ImageView(this).apply {
            setImageResource(R.drawable.avo_brand_hero); scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = "AVO Horse Edition Performance"
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.44f))
        col.addView(TextView(this).apply {
            text = "INICIANDO PROGRAMADOR"; setTextColor(Color.WHITE); textSize = 17f; gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
        }, lp(top = 4))
        col.addView(ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true; indeterminateTintList = ColorStateList.valueOf(cRed)
            progressBackgroundTintList = ColorStateList.valueOf(Color.parseColor("#27292C"))
        }, lp(top = 8, bottom = 12).apply { leftMargin = dp(20); rightMargin = dp(20) })
        val rows = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; background = rounded(Color.parseColor("#101014"), cRedDark, 16)
            setPadding(dp(14), dp(6), dp(14), dp(6))
        }
        bootRows = rows
        col.addView(rows, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.42f).apply { leftMargin = dp(14); rightMargin = dp(14) })
        col.addView(TextView(this).apply {
            text = "Updater ${appVersion()}   |   ESP32-S3   |   AVO"; setTextColor(Color.parseColor("#ABABAE")); textSize = 11f; gravity = Gravity.CENTER
        }, lp(top = 9))
        col.addView(Button(this).apply {
            text = "ENTRAR AHORA"; setTextColor(cRedLight); background = null; stateListAnimator = null
            setOnClickListener { hideBoot() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(36) // stays above the Android navigation bar
        })
        boot = col
        root.addView(col, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        refreshBoot()
        main.postDelayed({ hideBoot() }, 3000)
    }

    private fun refreshBoot() {
        val rows = bootRows ?: return
        rows.removeAllViews()
        bootStatus().forEachIndexed { i, (label, value, color) ->
            val r = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(34) }
            r.addView(TextView(this).apply { text = label; setTextColor(Color.parseColor("#E8E8EA")); textSize = 13f },
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.42f))
            r.addView(TextView(this).apply { text = "●"; setTextColor(color); setPadding(0, 0, dp(8), 0) })
            r.addView(TextView(this).apply { text = value; setTextColor(color); textSize = 13f; maxLines = 2 },
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.58f))
            rows.addView(r)
            if (i < 6) rows.addView(View(this).apply { setBackgroundColor(Color.parseColor("#36373B")) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1))
        }
    }

    private fun hideBoot() {
        val b = boot ?: return
        boot = null; bootRows = null
        b.animate().alpha(0f).setDuration(250).withEndAction { root.removeView(b) }.start()
    }

    // ------------------------------------------------------------------ main UI

    private fun buildUi(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(14), dp(12), dp(48)) }
        val head = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(4), 0, 0, 0) }
        head.addView(TextView(this).apply { text = "AVO"; setTextColor(cRed); textSize = 24f; letterSpacing = 0.12f; setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        head.addView(TextView(this).apply { text = "  UPDATE"; setTextColor(cText); textSize = 17f; letterSpacing = 0.12f; setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        col.addView(head)
        col.addView(TextView(this).apply { text = "Programador y lector USB · V${appVersion()}"; setTextColor(cDim); textSize = 13f; setPadding(dp(4), 0, 0, dp(8)) })

        val dev = card(col, "Dispositivo")
        usbState = row(dev); permissionState = row(dev); chipState = row(dev)
        bootloaderState = row(dev); flashState = row(dev); securityState = row(dev)
        slotsState = row(dev, 13f, cSilver).apply { typeface = Typeface.MONOSPACE }
        autoBoot = CheckBox(this).apply {
            text = "Entrar en modo descarga automáticamente (reinicia el módulo)"; isChecked = true; setTextColor(cText)
            buttonTintList = ColorStateList.valueOf(cRed); dev.addView(this)
        }

        val rd = card(col, "Lectura y copia de seguridad")
        readerState = row(rd, 13f, cSilver).apply { typeface = Typeface.MONOSPACE; setTextIsSelectable(true); text = "Pecho (USB nativo) o espalda Heltec (CP2102). Solo lectura." }
        infoButton = primary(rd, "Información del dispositivo") { readInfo() }
        readFwButton = secondary(rd, "Leer firmware (.bin)") { readFirmware() }
        readPartButton = secondary(rd, "Leer partición…") { choosePartition() }
        backupButton = secondary(rd, "Copia completa de la flash") { fullBackup() }
        reportButton = secondary(rd, "Guardar informe (.txt)") { saveReport() }

        val fw = card(col, "Firmware (pecho o espalda)")
        selectButton = secondary(fw, "Seleccionar firmware BIN") { choose("*/*", selectFirmware) }
        firmwareState = row(fw, 14f).apply { setTextIsSelectable(true); text = "Ningún archivo seleccionado." }
        readButton = secondary(fw, "Comprobar módulo para instalar") { readWatch() }

        val inst = card(col, "Instalación")
        planState = row(inst, 13f, cSilver)
        installButton = primary(inst, "Instalar firmware por USB") { confirmInstall() }
        stepState = row(inst).apply { setTypeface(typeface, Typeface.BOLD) }
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100; progress = 0; visibility = View.GONE
            progressTintList = ColorStateList.valueOf(cRed); indeterminateTintList = ColorStateList.valueOf(cRed)
            progressBackgroundTintList = ColorStateList.valueOf(cSurface2)
            inst.addView(this, lp(top = 6))
        }
        resultState = row(inst)
        cancelButton = secondary(inst, "Cancelar") {
            cancel.set(true); stepState.text = "Cancelando… (si se está activando, se termina primero de forma segura)"
        }.apply { visibility = View.GONE }

        val mon = card(col, "Monitor serie")
        monitorStartButton = secondary(mon, "Iniciar monitor") { startMonitor(reset = false) }
        monitorResetButton = secondary(mon, "Reiniciar reloj y capturar") { startMonitor(reset = true) }
        monitorStopButton = secondary(mon, "Parar monitor") { monitorRunning.set(false) }.apply { visibility = View.GONE }
        monitorSaveButton = secondary(mon, "Guardar monitor (.txt)") { saveMonitor() }
        monitorView = row(mon, 10f, cSilver).apply { typeface = Typeface.MONOSPACE; setTextIsSelectable(true); text = "—" }

        val lg = card(col, "Registro")
        logView = row(lg, 11f, cDim).apply { typeface = Typeface.MONOSPACE; setTextIsSelectable(true) }

        val app = card(col, "Aplicación")
        secondary(app, "Actualizar esta aplicación desde APK") { choose("application/vnd.android.package-archive", selectUpdate) }
        row(app, 12f, cDim).text = "Instalación: solo el slot OTA de destino y una copia de otadata. Lectura: nunca escribe ni borra."
        return ScrollView(this).apply { setBackgroundColor(cBg); addView(col) }
    }

    private fun appVersion(): String = runCatching {
        @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0).versionName
    }.getOrNull() ?: "?"

    // ------------------------------------------------------------------ rendering

    private fun refreshUsb() {
        val device = UsbLinks.find(usb)
        usbState.setTextColor(if (device == null) cWarn else cOk)
        usbState.text = "USB: " + if (device == null) "esperando conexión (cable USB-C de datos)" else "✔ " + UsbLinks.describe(device)
        permissionState.text = "Permiso USB: " + when {
            device == null -> "—"
            usb.hasPermission(device) -> "✔ concedido"
            else -> "se pedirá al usarlo"
        }
        val s = snapshot
        if (s == null) {
            chipState.text = "Chip: sin leer"
            bootloaderState.text = ""; flashState.text = ""; securityState.text = ""; slotsState.text = ""
            listOf(bootloaderState, flashState, securityState, slotsState).forEach { it.visibility = View.GONE }
        } else {
            listOf(bootloaderState, flashState, securityState, slotsState).forEach { it.visibility = View.VISIBLE }
            chipState.text = "Chip: ✔ ESP32-S3 revisión ${s.chipRevisionText}"
            bootloaderState.text = "Bootloader: " + if (s.bootloaderValid) "✔ válido" else "✖ NO válido"
            flashState.text = "Flash: " + (s.physicalFlash?.let { "${it shr 20} MB" } ?: "desconocida") +
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
            s == null -> "Pulsa COMPROBAR MÓDULO PARA INSTALAR (particiones, slot activo y seguridad)."
            else -> ""
        }
    }

    private fun refreshButtons() {
        val idle = !busy.get()
        val any = UsbLinks.find(usb) != null
        readButton.enable(idle && any)
        monitorStartButton.enable(idle && any)
        monitorResetButton.enable(idle && any)
        monitorSaveButton.enable(idle)
        selectButton.enable(idle)
        installButton.enable(idle && planText != null && firmware?.validHeader == true && any)
        infoButton.enable(idle && any)
        readFwButton.enable(idle && any)
        readPartButton.enable(idle && any && lastInfo?.partitions?.isNotEmpty() == true)
        backupButton.enable(idle && any)
        reportButton.enable(idle && lastReport != null)
        cancelButton.visibility = if (idle) View.GONE else View.VISIBLE
    }

    private fun appendLog(line: String) {
        log.append(line).append('\n')
        if (log.length > 20000) log.delete(0, log.length - 20000)
        logView.text = log
    }

    private fun ui(block: () -> Unit) = runOnUiThread { if (!isDestroyed) block() }

    // ------------------------------------------------------------------ install (chest)

    private fun listener() = object : Installer.Listener {
        override fun onStep(step: Installer.Step, percent: Int?, detail: String) = ui {
            stepState.text = step.text + (percent?.let { " · $it %" } ?: "") + if (detail.isNotBlank()) "\n$detail" else ""
            progress.visibility = View.VISIBLE
            progress.isIndeterminate = percent == null
            if (percent != null) progress.progress = percent
        }
        override fun onLog(line: String) = ui { appendLog(line) }
    }

    // Install / read work with the chest (USB-Serial/JTAG) and the back module (CP2102).
    private fun port() = AnyDevicePort(this, usb) { ui { appendLog("Acepta el permiso USB en la pantalla del teléfono.") } }
    private fun anyPort() = AnyDevicePort(this, usb) { ui { appendLog("Acepta el permiso USB en la pantalla del teléfono.") } }

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
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("¿Instalar ${f.info?.label ?: firmwareName}?")
            .setMessage("$plan\n\nNo desconectes el reloj ni cierres la aplicación hasta que termine. El reloj se reiniciará varias veces.")
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
                    resultState.setTextColor(if (out.bootConfirmed) cOk else cWarn)
                    resultState.text = (if (out.bootConfirmed) "✔ " else "⚠ ") + out.message
                    if (!out.bootConfirmed) stepState.text = "Arranque no confirmado"
                    if (out.usbText.isNotBlank()) appendLog("Salida USB del firmware:\n" + out.usbText.takeLast(1500))
                    snapshot = null; updatePlan()
                }
            } catch (e: Exception) {
                ui {
                    resultState.setTextColor(cBad)
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

    // ------------------------------------------------------------------ read / backup (any ESP32-S3)

    private fun readerListener() = object : FlashReader.Listener {
        override fun onProgress(text: String, percent: Int?) = ui {
            stepState.text = text
            progress.visibility = View.VISIBLE
            progress.isIndeterminate = percent == null
            if (percent != null) progress.progress = percent
        }
        override fun onLog(line: String) = ui { appendLog(line) }
    }

    private fun reader() = FlashReader(anyPort(), readerListener(), cancel, stubJson = {
        assets.open("stub/esp32s3.json").bufferedReader().use { it.readText() }
    })

    private val stamp get() = SimpleDateFormat("yyyyMMdd_HHmm", Locale.US).format(Date())

    private fun baseName(info: FlashReader.Info): String {
        val boot = info.apps.firstOrNull { it.partition == info.bootPartition }
        val who = boot?.avo?.replace(" ", "_")?.removePrefix("AVO-") ?: boot?.project?.takeIf { it.isNotBlank() && it != "arduino-lib-builder" } ?: "ESP32S3"
        return "AVO_${who.replace(Regex("[^A-Za-z0-9._-]"), "_")}_${info.macCompact}"
    }

    /** Opens a session, runs [block], always resets the module back to its firmware. */
    private fun withModule(title: String, block: (FlashReader, FlashReader.Session) -> Unit) {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val auto = autoBoot.isChecked
        runExclusive {
            val r = reader()
            var s: FlashReader.Session? = null
            try {
                s = r.connect(auto)
                val info = s.info
                val report = info.report()
                ui {
                    lastInfo = info
                    readerState.text = report.joinToString("\n")
                    lastReport = report.joinToString("\n")
                }
                block(r, s)
            } catch (e: Exception) {
                ui { stepState.text = "✖ $title: " + message(e); appendLog("Error: ${message(e)}") }
            } finally {
                s?.let { r.finish(it) }
                ui { progress.visibility = View.GONE; window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
            }
        }
    }

    private fun readInfo() = withModule("Información") { _, s ->
        ui { stepState.text = "✔ Dispositivo leído · ${s.info.mac}"; s.info.report().forEach(::appendLog) }
    }

    private fun readFirmware() = withModule("Leer firmware") { r, s ->
        val part = s.info.bootPartition ?: fail(Failure.PARTITION, "no hay partición de aplicación")
        val tmp = File(cacheDir, "firmware.bin")
        tmp.outputStream().buffered().use { r.read(s, part.offset, part.size, it, "Leyendo ${part.name}") }
        val fp = FirmwareFingerprint.analyse(tmp.readBytes())
        val len = fp.imageBytes
        if (len != null) { val trimmed = tmp.readBytes().copyOf(len); tmp.writeBytes(trimmed) }
        val lines = buildList {
            add("── Firmware en ${part.name} (0x%X) ──".format(part.offset))
            add("Imagen: " + (len?.let { "%,d bytes".format(it) } ?: "no reconocida (se guarda la partición completa)"))
            fp.sha256?.let { add("SHA-256: $it") }
            fp.info?.let { i ->
                add("Proyecto: ${i.projectName} · versión ${i.version}")
                i.avoVersion?.let { add("Versión AVO: $it") }
                add("Compilado: ${i.buildDate} · ESP-IDF ${i.idfVersion}")
            }
            if (fp.strings.isNotEmpty()) { add("Textos identificativos:"); fp.strings.take(40).forEach { add("  $it") } }
        }
        ui {
            readerState.text = (lastReport ?: "") + "\n\n" + lines.joinToString("\n")
            lastReport = readerState.text.toString()
            lines.forEach(::appendLog)
            stepState.text = "✔ Firmware leído y verificado (MD5 del chip)"
            offerSave(tmp, "${baseName(s.info)}_${part.name}_$stamp.bin")
        }
    }

    private fun choosePartition() {
        val parts = lastInfo?.partitions ?: return
        val labels = parts.map { "%s · %s · %,d KB".format(it.name, FlashReader.Info.typeName(it), it.size / 1024) }.toTypedArray()
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Leer partición")
            .setItems(labels) { _, i -> readPartition(parts[i].name) }
            .setNegativeButton("Cancelar", null).show()
    }

    private fun readPartition(name: String) = withModule("Leer partición") { r, s ->
        val p = s.info.partitions.firstOrNull { it.name == name } ?: fail(Failure.PARTITION, "la partición $name ya no está")
        val tmp = File(cacheDir, "partition.bin")
        val sha = tmp.outputStream().buffered().use { r.read(s, p.offset, p.size, it, "Leyendo $name") }
        ui {
            appendLog("$name: %,d bytes · SHA-256 $sha".format(p.size))
            stepState.text = "✔ Partición $name leída y verificada"
            offerSave(tmp, "${baseName(s.info)}_${name}_$stamp.bin")
        }
    }

    private fun fullBackup() = withModule("Copia completa") { r, s ->
        val size = s.info.flashBytes ?: fail(Failure.INCOMPATIBLE, "tamaño de flash desconocido")
        val tmp = File(cacheDir, "flash_full.bin")
        if (cacheDir.usableSpace < size + (16L shl 20)) fail(Failure.UNSAFE, "no hay espacio libre en el teléfono")
        val sha = tmp.outputStream().buffered().use { r.read(s, 0, size, it, "Copia completa") }
        ui {
            appendLog("Copia completa: %,d bytes · SHA-256 %s".format(size, sha))
            lastReport = (lastReport ?: "") + "\n\nCopia completa de la flash: %,d bytes · SHA-256 %s".format(size, sha)
            stepState.text = "✔ Copia completa verificada (MD5 del chip en cada bloque)"
            offerSave(tmp, "${baseName(s.info)}_FLASH_COMPLETA_${size shr 20}MB_$stamp.bin")
        }
    }

    // ------------------------------------------------------------------ serial monitor

    private fun monitorAppend(text: String) {
        synchronized(monitorLog) {
            monitorLog.append(text)
            if (monitorLog.length > 4_000_000) monitorLog.delete(0, monitorLog.length - 3_000_000)
        }
        monitorDirty = true
    }

    private fun monitorRefresh() {
        if (!monitorDirty) return
        monitorDirty = false
        val tail = synchronized(monitorLog) { monitorLog.substring(maxOf(0, monitorLog.length - 12_000)) }
        ui { monitorView.text = tail }
    }

    /**
     * Reads what the watch prints on its USB port (Serial/ESP log) and keeps it. When the watch reboots the
     * USB port disappears and reappears: the monitor reconnects on its own and keeps capturing, so the boot of
     * the next start (reset reason, [AVO MEM]) is recorded. Writes nothing to the watch except, with
     * [reset], a normal reboot (the same as the button) to capture from the start.
     */
    private fun startMonitor(reset: Boolean) = runExclusive {
        monitorRunning.set(true)
        synchronized(monitorLog) { monitorLog.setLength(0) }
        monitorAppend("=== Monitor serie AVO · %s ===\n".format(java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())))
        ui { monitorStopButton.visibility = View.VISIBLE; stepState.text = "Monitor serie activo" }
        var link: RomLink? = null
        var firstOpen = true
        val buf = ByteArray(4096)
        var lastUi = 0L
        try {
            while (monitorRunning.get() && !cancel.get()) {
                if (link == null || !link.isOpen) {
                    runCatching { link?.close() }
                    link = runCatching { anyPort().open(2_000) }.getOrNull()
                    if (link == null) { android.os.SystemClock.sleep(200); continue }
                    link.setBaud(115_200)
                    if (firstOpen && reset) {
                        monitorAppend("[reiniciando el reloj]\n")
                        link.setLines(dtr = false, rts = true); android.os.SystemClock.sleep(120); link.setLines(dtr = false, rts = false)
                    } else link.setLines(dtr = false, rts = false)
                    monitorAppend(if (firstOpen) "[conectado: ${link.kind.text}]\n" else "\n[reconectado ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())}]\n")
                    firstOpen = false
                }
                val n = link.read(buf, 200)
                if (n > 0) monitorAppend(String(buf, 0, n, Charsets.ISO_8859_1))
                else if (!link.isOpen) {   // n <= 0 with the port present = no data (timeout), not a disconnection
                    monitorAppend("\n[USB desconectado ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())} — reinicio del reloj? reconectando…]\n")
                    runCatching { link.close() }; link = null
                }
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - lastUi > 300) { lastUi = now; monitorRefresh() }
            }
        } finally {
            runCatching { link?.close() }
            monitorRunning.set(false)
            monitorAppend("\n=== monitor parado ===\n")
            monitorRefresh()
            ui { monitorStopButton.visibility = View.GONE; stepState.text = "Monitor serie parado" }
        }
    }

    private fun saveMonitor() {
        val text = synchronized(monitorLog) { monitorLog.toString() }
        if (text.isBlank()) { appendLog("El monitor está vacío"); return }
        val tmp = File(cacheDir, "monitor.txt").apply { writeText(text) }
        offerSave(tmp, "AVO_monitor_serie_$stamp.txt", "text/plain")
    }

    private fun saveReport() {
        val text = lastReport ?: return
        val tmp = File(cacheDir, "informe.txt").apply { writeText(text + "\n\n" + log) }
        offerSave(tmp, "${lastInfo?.let { baseName(it) } ?: "AVO"}_informe_$stamp.txt", "text/plain")
    }

    private fun offerSave(file: File, name: String, mime: String = "application/octet-stream") {
        pendingSave = file to name
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = mime; putExtra(Intent.EXTRA_TITLE, name)
        }, saveFile)
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
        if (requestCode == saveFile) {
            val (file, name) = pendingSave ?: return
            pendingSave = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) { appendLog("Archivo no guardado: $name (sigue en la caché hasta la próxima lectura)"); return }
            runExclusive {
                val ok = runCatching { contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out, 1 shl 16) } } ?: error("sin acceso") }
                ui { appendLog(if (ok.isSuccess) "✔ Guardado: ${displayName(uri)}" else "✖ No se pudo guardar: ${ok.exceptionOrNull()?.message}") }
            }
            return
        }
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
        main.removeCallbacksAndMessages(null)
        unregisterReceiver(usbReceiver)
        worker.shutdown()
        super.onDestroy()
    }
}
