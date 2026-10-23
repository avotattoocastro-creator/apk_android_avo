package org.avoperformance.horse.update

import android.app.Activity
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** USB discovery only. Flashing deliberately disabled until verified ROM protocol and partition layout. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val usb = getSystemService(USB_SERVICE) as UsbManager
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 48, 32, 24) }
        val title = TextView(this).apply { text = "AVO PERFORMANCE HORSE UPDATE\nUSB Recovery · V1.0"; textSize = 24f }
        val status = TextView(this).apply { textSize = 16f }
        val scan = Button(this).apply { text = "Detectar dispositivos USB" }
        fun refresh() {
            val devices = usb.deviceList.values.toList()
            status.text = if (devices.isEmpty()) "Sin dispositivos USB detectados. Comprueba USB OTG y cable de datos."
            else devices.joinToString("\n\n") { d -> "VID: %04X  PID: %04X\nNombre: %s\nInterfaces: %d\nPermiso: %s".format(d.vendorId, d.productId, d.deviceName, d.interfaceCount, usb.hasPermission(d)) }
        }
        scan.setOnClickListener { refresh() }
        root.addView(title); root.addView(scan); root.addView(status)
        root.addView(TextView(this).apply { text = "\nGrabación USB deshabilitada en V1.0 hasta validar hardware, bootloader, particiones y mecanismo de recuperación." })
        setContentView(root)
        refresh()
    }
}
