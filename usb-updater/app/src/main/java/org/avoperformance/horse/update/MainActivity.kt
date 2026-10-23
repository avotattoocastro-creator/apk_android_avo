package org.avoperformance.horse.update

import android.app.Activity
import android.content.Intent
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.security.MessageDigest

/** Diagnostic and package-selection application. ROM flashing is intentionally not enabled. */
class MainActivity : Activity() {
    private val selectFirmware = 101
    private val selectUpdate = 102
    private lateinit var status: TextView
    private lateinit var firmwareStatus: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val usb = getSystemService(USB_SERVICE) as UsbManager
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 48, 32, 24)
        }
        val title = TextView(this).apply {
            text = "AVO PERFORMANCE HORSE UPDATE\nUSB Recovery · V1.1"
            textSize = 23f
        }
        status = TextView(this).apply { textSize = 15f }
        firmwareStatus = TextView(this).apply { text = "Firmware: ninguno seleccionado" }
        val scan = Button(this).apply { text = "Detectar dispositivos USB" }
        val firmware = Button(this).apply { text = "Seleccionar firmware .bin (solo análisis)" }
        val selfUpdate = Button(this).apply { text = "Actualizar esta aplicación desde APK" }
        val safety = TextView(this).apply {
            text = "\nSEGURIDAD: la escritura de flash está desactivada hasta validar la interfaz USB, bootloader, tabla de particiones y firma del firmware.\n\nPara actualizar esta aplicación, selecciona una APK con el mismo ID y la misma firma. Android pedirá confirmación."
        }
        scan.setOnClickListener {
            val devices = usb.deviceList.values.toList()
            status.text = if (devices.isEmpty()) "No se detectan dispositivos USB. Comprueba OTG y cable de datos."
            else devices.joinToString("\n\n") { d ->
                "VID: %04X  PID: %04X\nNombre: %s\nInterfaces: %d\nPermiso: %s".format(
                    d.vendorId, d.productId, d.deviceName, d.interfaceCount, usb.hasPermission(d))
            }
        }
        firmware.setOnClickListener { choose("application/octet-stream", selectFirmware) }
        selfUpdate.setOnClickListener { choose("application/vnd.android.package-archive", selectUpdate) }
        root.addView(title); root.addView(scan); root.addView(status)
        root.addView(firmware); root.addView(firmwareStatus)
        root.addView(selfUpdate); root.addView(safety)
        setContentView(ScrollView(this).apply { addView(root) })
        scan.performClick()
    }

    private fun choose(type: String, code: Int) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            this.type = type
        }
        startActivityForResult(intent, code)
    }

    @Deprecated("Legacy activity result used for Android 10 compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        if (requestCode == selectFirmware) {
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                var length = 0L
                contentResolver.openInputStream(uri)?.use { input ->
                    val buf = ByteArray(8192)
                    while (true) {
                        val count = input.read(buf)
                        if (count < 0) break
                        digest.update(buf, 0, count)
                        length += count
                    }
                } ?: error("No se pudo abrir el archivo")
                val sha = digest.digest().joinToString("") { "%02x".format(it) }
                firmwareStatus.text = "Archivo: ${uri.lastPathSegment}\nTamaño: $length bytes\nSHA-256: $sha\nPendiente de validar compatibilidad y firma. NO se ha grabado."
            } catch (e: Exception) {
                firmwareStatus.text = "Error al leer firmware: ${e.message}"
            }
        } else if (requestCode == selectUpdate) {
            try {
                val install = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    data = uri
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(install)
            } catch (e: Exception) {
                firmwareStatus.text = "No se pudo abrir el instalador: ${e.message}"
            }
        }
    }
}
