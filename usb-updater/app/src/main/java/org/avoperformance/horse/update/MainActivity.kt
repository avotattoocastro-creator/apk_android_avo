package org.avoperformance.horse.update

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Safe USB diagnostic. No flash writes. */
class MainActivity : Activity() {
    private val selectFirmware = 101
    private val selectUpdate = 102
    private val usbAction = "org.avoperformance.horse.update.USB_PERMISSION"
    private lateinit var usb: UsbManager
    private lateinit var status: TextView
    private lateinit var firmwareStatus: TextView
    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != usbAction) return
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            status.text = if (granted) "Permiso USB concedido.\n" + deviceReport() else "Permiso USB denegado.\n" + deviceReport()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        usb = getSystemService(USB_SERVICE) as UsbManager
        val filter = IntentFilter(usbAction)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(permissionReceiver, filter)

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 48, 32, 24) }
        val title = TextView(this).apply { text = "AVO PERFORMANCE HORSE UPDATE\nUSB Recovery · V1.7.1"; textSize = 23f }
        status = TextView(this).apply { textSize = 15f }
        firmwareStatus = TextView(this).apply { text = "Firmware: ninguno seleccionado" }
        val scan = Button(this).apply { text = "Detectar dispositivos USB" }
        val authorize = Button(this).apply { text = "Autorizar acceso USB al ESP32-S3" }
        val inspect = Button(this).apply { text = "Diagnosticar interfaces USB" }
        val probe = Button(this).apply { text = "Probar interfaz CDC (sin escritura)" }
        val rom = Button(this).apply { text = "Diagnóstico ROM (solo lectura)" }
        val identity = Button(this).apply { text = "Identificar chip ROM (solo lectura)" }
        val firmware = Button(this).apply { text = "Seleccionar firmware .bin (solo análisis)" }
        val install = Button(this).apply { text = "INSTALAR FIRMWARE POR USB (PENDIENTE DE VALIDACIÓN)"; isEnabled = false }
        val selfUpdate = Button(this).apply { text = "Actualizar esta aplicación desde APK" }
        scan.setOnClickListener { status.text = deviceReport() }
        authorize.setOnClickListener {
            val target = espDevice()
            if (target == null) status.text = "No se detecta el ESP32-S3 (VID 303A)."
            else if (usb.hasPermission(target)) status.text = "USB ya autorizado.\n" + deviceReport()
            else {
                val pending = PendingIntent.getBroadcast(this, 0, Intent(usbAction).setPackage(packageName),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                usb.requestPermission(target, pending)
                status.text = "Solicitud de autorización USB enviada a Android."
            }
        }
        inspect.setOnClickListener {
            val target = espDevice()
            status.text = when {
                target == null -> "No se detecta ESP32-S3."
                !usb.hasPermission(target) -> "Autoriza el acceso USB primero."
                else -> {
                    val connection = usb.openDevice(target)
                    if (connection == null) "Android no pudo abrir el dispositivo."
                    else try {
                        val interfaces = (0 until target.interfaceCount).joinToString("\n") { i ->
                            val intf = target.getInterface(i)
                            val endpoints = (0 until intf.endpointCount).joinToString { e ->
                                val ep = intf.getEndpoint(e)
                                "0x%02X(tipo=%d,dir=%d)".format(ep.address, ep.type, ep.direction)
                            }
                            "Interfaz $i: clase=${intf.interfaceClass}, subclase=${intf.interfaceSubclass}, protocolo=${intf.interfaceProtocol}; endpoints=$endpoints"
                        }
                        "USB abierto correctamente.\n$interfaces\n\nROM bootloader: aún sin comprobar. No se ha enviado ningún comando."
                    } finally { connection.close() }
                }
            }
        }
        probe.setOnClickListener {
            val target = espDevice()
            status.text = when {
                target == null -> "No se detecta dispositivo Espressif."
                !usb.hasPermission(target) -> "Primero autoriza el acceso USB."
                else -> {
                    val connection = usb.openDevice(target)
                    if (connection == null) "No se pudo abrir USB."
                    else try {
                        val candidates = (0 until target.interfaceCount).map { target.getInterface(it) }
                            .filter { it.interfaceClass == 10 && it.endpointCount >= 2 }
                        if (candidates.isEmpty()) "No hay interfaz CDC de datos."
                        else {
                            val intf = candidates.first()
                            if (!connection.claimInterface(intf, true)) "No se pudo reclamar interfaz CDC."
                            else try {
                                "Interfaz CDC reclamada correctamente. Endpoints: " +
                                    (0 until intf.endpointCount).joinToString { i ->
                                        val ep = intf.getEndpoint(i)
                                        "0x%02X tipo=%d dir=%d".format(ep.address, ep.type, ep.direction)
                                    } + "\nNo se han enviado comandos. Bootloader aún sin verificar."
                            } finally { connection.releaseInterface(intf) }
                        }
                    } catch (e: Exception) { "Diagnóstico CDC: ${e.message}" }
                    finally { connection.close() }
                }
            }
        }
        rom.setOnClickListener {
            val target = espDevice()
            status.text = when {
                target == null -> "No se detecta ESP32-S3."
                !usb.hasPermission(target) -> "Autoriza primero el USB."
                else -> {
                    val connection = usb.openDevice(target)
                    if (connection == null) "No se pudo abrir USB."
                    else try {
                        val intf = (0 until target.interfaceCount).map { target.getInterface(it) }
                            .firstOrNull { it.interfaceClass == 10 && it.endpointCount >= 2 }
                        if (intf == null) "No hay interfaz CDC de datos."
                        else if (!connection.claimInterface(intf, true)) "No se pudo reclamar CDC."
                        else try {
                            val output = (0 until intf.endpointCount).map { intf.getEndpoint(it) }
                                .firstOrNull { it.direction == 0 && it.type == 2 }
                            val input = (0 until intf.endpointCount).map { intf.getEndpoint(it) }
                                .firstOrNull { it.direction == 128 && it.type == 2 }
                            if (output == null || input == null) "Endpoints CDC incompletos."
                            else {
                                // ESP ROM SYNC command (SLIP-framed); no flash writes.
                                val sync = byteArrayOf(0x07, 0x07, 0x12, 0x20) + ByteArray(32) { 0x55.toByte() }
                                val packet = byteArrayOf(0x00, 0x08, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00) + sync
                                val frame = ArrayList<Byte>()
                                frame.add(0xC0.toByte())
                                for (value in packet) {
                                    when (value.toInt() and 0xff) {
                                        0xC0 -> { frame.add(0xDB.toByte()); frame.add(0xDC.toByte()) }
                                        0xDB -> { frame.add(0xDB.toByte()); frame.add(0xDD.toByte()) }
                                        else -> frame.add(value)
                                    }
                                }
                                frame.add(0xC0.toByte())
                                val bytes = frame.toByteArray()
                                val sent = connection.bulkTransfer(output, bytes, bytes.size, 1200)
                                val received = ByteArray(512)
                                val count = if (sent == bytes.size) connection.bulkTransfer(input, received, received.size, 1500) else -1
                                val response = if (count > 0) received.take(count).joinToString(" ") { "%02X".format(it.toInt() and 255) } else "sin respuesta"
                                val validation = if (count > 0) RomProtocol.syncReport(received.copyOf(count)) else "Sin respuesta ROM. Escritura bloqueada."
                                "SYNC enviado: $sent/${bytes.size} bytes. Recibidos: $count. Datos: $response\\n" +
                                    "No se ha escrito flash.\\n$validation"
                            }
                        } finally { connection.releaseInterface(intf) }
                    } catch (e: Exception) { "Diagnóstico ROM: ${e.message}" }
                    finally { connection.close() }
                }
            }
        }
        identity.setOnClickListener {
            val target = espDevice()
            if (target == null || !usb.hasPermission(target)) {
                status.text = "Conecta y autoriza primero el ESP32-S3."
            } else {
                status.text = "Leyendo registro ROM del chip..."
                Thread {
                    val result = try {
                        val connection = usb.openDevice(target) ?: error("No se pudo abrir USB")
                        try {
                            val intf = (0 until target.interfaceCount).map { target.getInterface(it) }
                                .firstOrNull { it.interfaceClass == 10 && it.endpointCount >= 2 } ?: error("Sin CDC")
                            check(connection.claimInterface(intf, true)) { "No se pudo reclamar CDC" }
                            try {
                                val output = (0 until intf.endpointCount).map { intf.getEndpoint(it) }
                                    .firstOrNull { it.direction == 0 && it.type == 2 } ?: error("Sin OUT")
                                val input = (0 until intf.endpointCount).map { intf.getEndpoint(it) }
                                    .firstOrNull { it.direction == 128 && it.type == 2 } ?: error("Sin IN")
                                val transport = RomTransport(connection, output, input)
                                val syncPayload = byteArrayOf(7, 7, 0x12, 0x20) + ByteArray(32) { 0x55.toByte() }
                                val sync = runCatching { transport.request(0x08, syncPayload) }.getOrNull()
                                if (sync == null || sync.payload.size < 2 ||
                                    sync.payload.takeLast(2).any { it.toInt() != 0 }) {
                                    "Sin SYNC ROM válido. Escritura bloqueada."
                                } else {
                                    // ESP32-S3 UART ROM date register, read-only (esptool chip detection).
                                    val addr = 0x60000078
                                    val p = ByteArray(4) { i -> (addr ushr (8 * i)).toByte() }
                                    val reply = runCatching { transport.request(0x0A, p) }.getOrNull()
                                    if (reply == null) "SYNC válido. READ_REG sin respuesta tras 3 intentos. Escritura bloqueada."
                                    else "SYNC válido. Registro ROM 0x60000078 = 0x%08X.\\nIdentidad provisional; particiones y protecciones NO verificadas. Escritura bloqueada.".format(reply.value)
                                }
                            } finally { connection.releaseInterface(intf) }
                        } finally { connection.close() }
                    } catch (e: Exception) { "Diagnóstico ROM: ${e.message}" }
                    runOnUiThread { status.text = result.replace("\\n", "\\n") }
                }.start()
            }
        }
        firmware.setOnClickListener { choose("application/octet-stream", selectFirmware) }
        selfUpdate.setOnClickListener { choose("application/vnd.android.package-archive", selectUpdate) }
        root.addView(title); root.addView(scan); root.addView(authorize); root.addView(inspect); root.addView(probe); root.addView(rom); root.addView(identity); root.addView(status)
        root.addView(firmware); root.addView(firmwareStatus); root.addView(install); root.addView(selfUpdate)
        root.addView(TextView(this).apply {
            text = "\nSEGURIDAD: escritura USB deshabilitada hasta verificar el bootloader y las particiones del reloj. La instalación de APK exige la misma firma que la versión instalada."
        })
        setContentView(ScrollView(this).apply { addView(root) })
        scan.performClick()
    }

    private fun espDevice(): UsbDevice? = usb.deviceList.values.firstOrNull { it.vendorId == 0x303A }
    private fun deviceReport(): String {
        val devices = usb.deviceList.values.toList()
        return if (devices.isEmpty()) "Sin dispositivos USB. Comprueba OTG y cable de datos."
        else devices.joinToString("\n\n") { d ->
            "VID: %04X  PID: %04X\nInterfaces: %d\nPermiso: %s".format(d.vendorId, d.productId, d.interfaceCount, usb.hasPermission(d))
        }
    }
    private fun choose(type: String, code: Int) {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            this.type = type
        }, code)
    }
    @Deprecated("Legacy activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        if (requestCode == selectFirmware) {
            try {
                val report = contentResolver.openInputStream(uri)?.let(FirmwareImage::inspect)
                    ?: error("No se pudo abrir el archivo")
                firmwareStatus.text = "Archivo: ${uri.lastPathSegment}\\nTamaño: ${report.bytes} bytes\\nSHA-256: ${report.sha256}\\n${report.reason}\\nINSTALACIÓN USB BLOQUEADA: particiones y protecciones no verificadas."
            } catch (e: Exception) { firmwareStatus.text = "Error: ${e.message}" }
        } else if (requestCode == selectUpdate) {
            try {
                startActivity(Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    this.data = uri
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                })
            } catch (e: Exception) { firmwareStatus.text = "Instalador: ${e.message}" }
        }
    }
    override fun onDestroy() {
        unregisterReceiver(permissionReceiver)
        super.onDestroy()
    }
}
